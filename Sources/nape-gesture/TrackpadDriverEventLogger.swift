import AppKit
import CoreGraphics
import Darwin
import Dispatch
import Foundation
import NapeGestureCore

final class TrackpadDriverEventLogger {
    private static let maximumPendingEvents = 4_096

    private let encoder = JSONEncoder()
    private let options: [String]
    private let processingQueue = DispatchQueue(label: "com.napegesture.trackpad-event-log.processing")
    private let pendingEventSlots = DispatchSemaphore(value: maximumPendingEvents)
    private let stateLock = NSLock()
    private var outputHandle: FileHandle?
    private var closesOutputHandle = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var captureRunLoop: CFRunLoop?
    private var interruptSource: DispatchSourceSignal?
    private var runMetadata: TrackpadDriverEventLogMetadata?
    private var nextCaptureIndex: UInt64 = 0
    private var emittedEvents = 0
    private var loggingError: Error?
    private var acceptingEvents = false

    init(options: [String] = []) {
        self.options = options
        encoder.outputFormatting = [.sortedKeys]
    }

    func run() throws {
        if options.count == 1, let option = options.first, ["--help", "-h"].contains(option) {
            printCommandHelp()
            return
        }

        let configuration = try makeConfiguration()
        guard Self.supportsRawFieldScan else {
            throw TrackpadDriverEventLoggerError.unsupportedEventFieldLayout
        }
        runMetadata = try Self.makeMetadata(configuration: configuration)
        nextCaptureIndex = 0
        emittedEvents = 0
        loggingError = nil
        try AccessibilityPermission.ensurePrompted()

        outputHandle = try makeOutputHandle(path: configuration.outputPath)
        defer {
            stop()
            drainProcessingQueue()
            removeInterruptHandler()
            captureRunLoop = nil
            runMetadata = nil
            try? finalizeOutputHandle()
        }
        installInterruptHandler()

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.observedEventMask(),
            callback: trackpadDriverEventLoggerCallback,
            userInfo: userInfo
        ) else {
            throw ToolError.eventTapCreationFailed
        }

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw ToolError.eventTapCreationFailed
        }

        runLoopSource = source
        let runLoop = CFRunLoopGetCurrent()
        captureRunLoop = runLoop
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        setAcceptingEvents(true)

        let scanRange = "\(TrackpadDriverEventLog.rawFieldScanLowerBound)...\(TrackpadDriverEventLog.maximumRawFieldNumber)"
        if let duration = configuration.duration {
            fputs(
                "トラックパッド診断イベントログを開始しました。duration=\(duration)秒 eventTypes=0...63 rawFields=\(scanRange)\n",
                stderr
            )
            CFRunLoopRunInMode(.defaultMode, duration, false)
        } else {
            fputs(
                "トラックパッド診断イベントログを開始しました。eventTypes=0...63 rawFields=\(scanRange)。停止するには Ctrl-C を押してください。\n",
                stderr
            )
            CFRunLoopRun()
        }

        stop()
        drainProcessingQueue()
        let capturedLoggingError = loggingError
        do {
            try finalizeOutputHandle()
        } catch {
            if let capturedLoggingError {
                throw TrackpadDriverEventLoggerError.outputFinalizationFailed(
                    "captureError=\(capturedLoggingError.localizedDescription); finalizeError=\(error.localizedDescription)"
                )
            }
            throw error
        }
        if let capturedLoggingError {
            throw capturedLoggingError
        }
        guard emittedEvents > 0 else {
            throw TrackpadDriverEventLoggerError.noEventsCaptured
        }
        fputs("トラックパッド診断イベントログを終了しました。events=\(emittedEvents)\n", stderr)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isAcceptingEvents(), let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isAcceptingEvents() else {
            return Unmanaged.passUnretained(event)
        }

        let captureIndex = nextCaptureIndex
        let (followingIndex, overflow) = captureIndex.addingReportingOverflow(1)
        guard !overflow else {
            stopAcceptingEvents()
            processingQueue.async { [self] in
                fail(TrackpadDriverEventLoggerError.captureIndexOverflow)
            }
            return Unmanaged.passUnretained(event)
        }
        nextCaptureIndex = followingIndex

        guard pendingEventSlots.wait(timeout: .now()) == .success else {
            stopAcceptingEvents()
            processingQueue.async { [self] in
                fail(
                    TrackpadDriverEventLoggerError.pendingEventLimitExceeded(
                        Self.maximumPendingEvents
                    )
                )
            }
            return Unmanaged.passUnretained(event)
        }

        guard let copiedEvent = event.copy() else {
            pendingEventSlots.signal()
            stopAcceptingEvents()
            processingQueue.async { [self] in
                fail(TrackpadDriverEventLoggerError.eventCopyFailed(captureIndex))
            }
            return Unmanaged.passUnretained(event)
        }

        let capturedEvent = CapturedTrackpadDriverEvent(
            captureIndex: captureIndex,
            type: type,
            event: copiedEvent
        )
        processingQueue.async { [self] in
            defer { pendingEventSlots.signal() }
            process(capturedEvent)
        }

        return Unmanaged.passUnretained(event)
    }

    private func process(_ capturedEvent: CapturedTrackpadDriverEvent) {
        guard loggingError == nil else {
            return
        }
        guard let runMetadata else {
            fail(TrackpadDriverEventLoggerError.metadataUnavailable)
            return
        }

        do {
            let record = try Self.makeRecord(capturedEvent: capturedEvent, metadata: runMetadata)
            try writeRecord(record)
            emittedEvents += 1
        } catch let error as TrackpadDriverEventLoggerError {
            fail(error)
        } catch {
            fail(TrackpadDriverEventLoggerError.outputWriteFailed(error.localizedDescription))
        }
    }

    private func fail(_ error: Error) {
        guard loggingError == nil else {
            return
        }
        loggingError = error
        stopAcceptingEvents()
        if let captureRunLoop {
            CFRunLoopStop(captureRunLoop)
        }
    }

    private func drainProcessingQueue() {
        processingQueue.sync {}
    }

    private func isAcceptingEvents() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return acceptingEvents
    }

    private func setAcceptingEvents(_ accepting: Bool) {
        stateLock.lock()
        acceptingEvents = accepting
        stateLock.unlock()
    }

    private func stopAcceptingEvents() {
        setAcceptingEvents(false)
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    private func installInterruptHandler() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            fputs("SIGINTを受信したため、診断eventの受付を停止してqueueをdrainします。\n", stderr)
            stopAcceptingEvents()
            if let captureRunLoop {
                CFRunLoopStop(captureRunLoop)
            }
        }
        source.resume()
        interruptSource = source
    }

    private func removeInterruptHandler() {
        interruptSource?.cancel()
        interruptSource = nil
        signal(SIGINT, SIG_DFL)
    }

    private func makeConfiguration() throws -> TrackpadDriverEventLoggerConfiguration {
        var duration: TimeInterval?
        var outputPath: String?
        var scenarioID: String?
        var deviceLabel: String?
        var repoHeadSHA: String?
        var seenOptions = Set<String>()
        var index = 0
        let supportedOptions = [
            "--duration",
            "--out",
            "--scenario-id",
            "--device-label",
            "--repo-head-sha"
        ]

        while index < options.count {
            let option = options[index]
            guard supportedOptions.contains(option) else {
                throw TrackpadDriverEventLoggerError.unknownOption(option)
            }
            guard seenOptions.insert(option).inserted else {
                throw TrackpadDriverEventLoggerError.duplicateOption(option)
            }
            guard index + 1 < options.count else {
                throw ToolError.missingValue(option)
            }

            let value = options[index + 1]
            switch option {
            case "--duration":
                guard let parsed = TimeInterval(value), parsed.isFinite, parsed > 0 else {
                    throw ToolError.invalidValue(option, value)
                }
                duration = parsed
            case "--out":
                guard !value.isEmpty else {
                    throw ToolError.invalidValue(option, value)
                }
                outputPath = value
            case "--scenario-id":
                guard !value.isEmpty else {
                    throw ToolError.invalidValue(option, value)
                }
                scenarioID = value
            case "--device-label":
                guard !value.isEmpty else {
                    throw ToolError.invalidValue(option, value)
                }
                deviceLabel = value
            case "--repo-head-sha":
                guard Self.isValidGitObjectID(value) else {
                    throw ToolError.invalidValue(option, value)
                }
                repoHeadSHA = value.lowercased()
            default:
                break
            }
            index += 2
        }

        return TrackpadDriverEventLoggerConfiguration(
            duration: duration,
            outputPath: outputPath,
            scenarioID: scenarioID,
            deviceLabel: deviceLabel,
            repoHeadSHA: repoHeadSHA
        )
    }

    private static func isValidGitObjectID(_ value: String) -> Bool {
        guard [40, 64].contains(value.count) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
        }
    }

    private static func makeMetadata(
        configuration: TrackpadDriverEventLoggerConfiguration
    ) throws -> TrackpadDriverEventLogMetadata {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return TrackpadDriverEventLogMetadata(
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            osBuild: try operatingSystemBuild(),
            scenarioID: configuration.scenarioID,
            deviceLabel: configuration.deviceLabel,
            repoHeadSHA: configuration.repoHeadSHA
        )
    }

    private static func operatingSystemBuild() throws -> String {
        var size = 0
        let sizeResult = sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard sizeResult == 0, size > 1 else {
            let errorCode = sizeResult == 0 ? Int32(0) : errno
            throw TrackpadDriverEventLoggerError.operatingSystemBuildUnavailable(errorCode)
        }

        var buffer = [CChar](repeating: 0, count: size)
        let readResult = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname("kern.osversion", bytes.baseAddress, &size, nil, 0)
        }
        guard readResult == 0 else {
            throw TrackpadDriverEventLoggerError.operatingSystemBuildUnavailable(errno)
        }

        return buffer.withUnsafeBufferPointer { pointer in
            String(cString: pointer.baseAddress!)
        }
    }

    private func makeOutputHandle(path: String?) throws -> FileHandle {
        guard let path else {
            closesOutputHandle = false
            return .standardOutput
        }

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url, options: .atomic)
        closesOutputHandle = true
        return try FileHandle(forWritingTo: url)
    }

    private func writeRecord(_ record: TrackpadDriverEventLog) throws {
        guard let outputHandle else {
            throw TrackpadDriverEventLoggerError.outputHandleUnavailable
        }
        var data = try encoder.encode(record)
        data.append(0x0A)
        try outputHandle.write(contentsOf: data)
    }

    private func stop() {
        stopAcceptingEvents()
        if let captureRunLoop, let runLoopSource {
            CFRunLoopRemoveSource(captureRunLoop, runLoopSource, .commonModes)
        }
        self.eventTap = nil
        runLoopSource = nil
    }

    private func finalizeOutputHandle() throws {
        guard let outputHandle else {
            return
        }
        guard closesOutputHandle else {
            self.outputHandle = nil
            return
        }
        defer {
            self.outputHandle = nil
            closesOutputHandle = false
        }
        var failures: [String] = []
        do {
            try outputHandle.synchronize()
        } catch {
            failures.append("flush=\(error.localizedDescription)")
        }
        do {
            try outputHandle.close()
        } catch {
            failures.append("close=\(error.localizedDescription)")
        }
        if !failures.isEmpty {
            throw TrackpadDriverEventLoggerError.outputFinalizationFailed(
                failures.joined(separator: "; ")
            )
        }
    }

    private func printCommandHelp() {
        print(
            """
            nape-gesture trackpad-event-log [--duration <秒>] [--out <path>] [--scenario-id <ID>] [--device-label <ラベル>] [--repo-head-sha <SHA>]

            純正トラックパッドがCoreGraphicsへ送るイベント契約を、listen-onlyのCGEvent tapでJSON Linesとして記録します。
            callbackではイベントのcopy・採番・bounded queue投入だけを行い、event type 0...63とzeroを含むraw field 0...255をfieldNumber昇順で保存します。
            serializedEventBase64を正本とし、OS version/build、logger version、scenario ID、device label、repo HEAD SHAを各eventへ保存します。
            --repo-head-sha は40桁または64桁の完全な16進SHAを指定してください。診断中は対象外の入力を避けてください。
            --duration 未指定時は Ctrl-C まで継続し、SIGINT受信後にqueueをdrainしてflush / closeします。0 event、queue飽和、write / close失敗は非ゼロ終了します。--out 未指定時は標準出力へ書き出します。
            """
        )
    }

    private static func observedEventMask() -> CGEventMask {
        // 64ビットすべてを立て、shiftを行わずevent type 0...63を安全に観測する。
        CGEventMask.max
    }

    private static func makeRecord(
        capturedEvent: CapturedTrackpadDriverEvent,
        metadata: TrackpadDriverEventLogMetadata
    ) throws -> TrackpadDriverEventLog {
        let event = capturedEvent.event
        let fixedDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let fixedDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedDeltaZ = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3)
        let pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pointDeltaZ = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis3)
        return TrackpadDriverEventLog(
            metadata: metadata,
            captureIndex: capturedEvent.captureIndex,
            timestamp: event.timestamp,
            typeRaw: Int(capturedEvent.type.rawValue),
            typeName: capturedEvent.type.trackpadDriverStableName,
            eventSubtype: NSEvent(cgEvent: event).map { Int64($0.subtype.rawValue) },
            flags: event.flags.rawValue,
            scrollDeltaX: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            scrollDeltaY: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            scrollDeltaZ: event.getIntegerValueField(.scrollWheelEventDeltaAxis3),
            scrollFixedDeltaX: finiteValue(fixedDeltaX),
            scrollFixedDeltaXBitPattern: fixedDeltaX.bitPattern,
            scrollFixedDeltaY: finiteValue(fixedDeltaY),
            scrollFixedDeltaYBitPattern: fixedDeltaY.bitPattern,
            scrollFixedDeltaZ: finiteValue(fixedDeltaZ),
            scrollFixedDeltaZBitPattern: fixedDeltaZ.bitPattern,
            scrollPointDeltaX: finiteValue(pointDeltaX),
            scrollPointDeltaXBitPattern: pointDeltaX.bitPattern,
            scrollPointDeltaY: finiteValue(pointDeltaY),
            scrollPointDeltaYBitPattern: pointDeltaY.bitPattern,
            scrollPointDeltaZ: finiteValue(pointDeltaZ),
            scrollPointDeltaZBitPattern: pointDeltaZ.bitPattern,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData),
            rawFields: rawFields(event: event),
            serializedEventBase64: try serializedEventBase64(
                event: event,
                captureIndex: capturedEvent.captureIndex
            )
        )
    }

    private static func rawFields(event: CGEvent) -> [TrackpadDriverRawField] {
        (TrackpadDriverEventLog.rawFieldScanLowerBound...TrackpadDriverEventLog.maximumRawFieldNumber).map { fieldNumber in
            let field = rawEventField(fieldNumber: fieldNumber)
            let integerValue = event.getIntegerValueField(field)
            let doubleValue = event.getDoubleValueField(field)
            return TrackpadDriverRawField(
                fieldNumber: fieldNumber,
                integerValue: integerValue,
                doubleValue: finiteValue(doubleValue),
                doubleBitPattern: doubleValue.bitPattern
            )
        }
    }

    private static func finiteValue(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    private static var supportsRawFieldScan: Bool {
        MemoryLayout<CGEventField>.size == MemoryLayout<UInt32>.size
    }

    private static func rawEventField(fieldNumber: Int) -> CGEventField {
        // Swiftのfailable initializerを経由せず、公開C APIのuint32_tフィールド番号を同じビット表現で渡す。
        unsafeBitCast(UInt32(fieldNumber), to: CGEventField.self)
    }

    private static func serializedEventBase64(event: CGEvent, captureIndex: UInt64) throws -> String {
        guard let data = event.data else {
            throw TrackpadDriverEventLoggerError.serializedEventUnavailable(captureIndex)
        }
        return (data as Data).base64EncodedString()
    }
}

private struct TrackpadDriverEventLoggerConfiguration {
    var duration: TimeInterval?
    var outputPath: String?
    var scenarioID: String?
    var deviceLabel: String?
    var repoHeadSHA: String?
}

private struct CapturedTrackpadDriverEvent {
    var captureIndex: UInt64
    var type: CGEventType
    var event: CGEvent
}

private enum TrackpadDriverEventLoggerError: LocalizedError {
    case unknownOption(String)
    case duplicateOption(String)
    case unsupportedEventFieldLayout
    case operatingSystemBuildUnavailable(Int32)
    case metadataUnavailable
    case noEventsCaptured
    case captureIndexOverflow
    case pendingEventLimitExceeded(Int)
    case eventCopyFailed(UInt64)
    case serializedEventUnavailable(UInt64)
    case outputHandleUnavailable
    case outputWriteFailed(String)
    case outputFinalizationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unknownOption(option):
            return "trackpad-event-logで未対応のオプションです: \(option)"
        case let .duplicateOption(option):
            return "同じオプションを複数回指定できません: \(option)"
        case .unsupportedEventFieldLayout:
            return "この環境のCGEventField表現ではraw field scanを安全に実行できません。"
        case let .operatingSystemBuildUnavailable(code):
            return "OS build番号を取得できませんでした。errno=\(code)"
        case .metadataUnavailable:
            return "トラックパッド診断イベントのmetadataを準備できていません。"
        case .noEventsCaptured:
            return "トラックパッド診断イベントを1件も取得できませんでした。対象操作、capture時間、権限を確認してください。"
        case .captureIndexOverflow:
            return "トラックパッド診断イベントのcaptureIndexが上限に達しました。"
        case let .pendingEventLimitExceeded(limit):
            return "トラックパッド診断イベントの処理queueが上限に達しました。limit=\(limit)。captureを失敗として停止します。"
        case let .eventCopyFailed(captureIndex):
            return "CGEventのcopyに失敗しました。captureIndex=\(captureIndex)"
        case let .serializedEventUnavailable(captureIndex):
            return "serialized CGEvent dataを取得できませんでした。captureIndex=\(captureIndex)"
        case .outputHandleUnavailable:
            return "トラックパッド診断イベントログの出力先を開けていません。"
        case let .outputWriteFailed(details):
            return "トラックパッド診断イベントログの書き込みに失敗しました: \(details)"
        case let .outputFinalizationFailed(details):
            return "トラックパッド診断イベントログのflushまたはcloseに失敗しました: \(details)"
        }
    }
}

private extension CGEventType {
    var trackpadDriverStableName: String {
        switch self {
        case .null:
            return "null"
        case .leftMouseDown:
            return "leftMouseDown"
        case .leftMouseUp:
            return "leftMouseUp"
        case .rightMouseDown:
            return "rightMouseDown"
        case .rightMouseUp:
            return "rightMouseUp"
        case .mouseMoved:
            return "mouseMoved"
        case .leftMouseDragged:
            return "leftMouseDragged"
        case .rightMouseDragged:
            return "rightMouseDragged"
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        case .flagsChanged:
            return "flagsChanged"
        case .scrollWheel:
            return "scrollWheel"
        case .tabletPointer:
            return "tabletPointer"
        case .tabletProximity:
            return "tabletProximity"
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .otherMouseDragged:
            return "otherMouseDragged"
        default:
            return "raw-\(rawValue)"
        }
    }
}

private let trackpadDriverEventLoggerCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let logger = Unmanaged<TrackpadDriverEventLogger>.fromOpaque(userInfo).takeUnretainedValue()
    return logger.handle(type: type, event: event)
}
