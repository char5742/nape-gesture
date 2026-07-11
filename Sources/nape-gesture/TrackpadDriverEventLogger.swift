import CoreGraphics
import Darwin
import Dispatch
import Foundation
import NapeGestureCore
import NapeGestureDiagnosticOutput

final class TrackpadDriverEventLogger {
    private static let maximumPendingEvents = 4_096

    private let encoder = JSONEncoder()
    private let manifestStore = TrackpadDriverEventCaptureManifestStore()
    private let readyStore = TrackpadDriverEventCaptureReadyStore()
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
    private var emittedEvents: UInt64 = 0
    private var loggingError: Error?
    private var acceptingEvents = false
    private var activeReadyLease: TrackpadDriverEventCaptureReadyLease?
    private var readyLifecycleError: Error?

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
        stateLock.lock()
        acceptingEvents = false
        activeReadyLease = nil
        readyLifecycleError = nil
        stateLock.unlock()
        if let readyFilePath = configuration.readyFilePath {
            guard let readyRunToken = configuration.readyRunToken else {
                throw TrackpadDriverEventLoggerError.readyConfigurationUnavailable
            }
            do {
                let lease = try readyStore.reserve(
                    path: readyFilePath,
                    pid: ProcessInfo.processInfo.processIdentifier,
                    runToken: readyRunToken,
                    leaseCreatedAt: Date(),
                    scenarioID: configuration.scenarioID,
                    repoHeadSHA: configuration.repoHeadSHA
                )
                stateLock.lock()
                activeReadyLease = lease
                stateLock.unlock()
            } catch {
                throw TrackpadDriverEventLoggerError.readyFilePreparationFailed(
                    error.localizedDescription
                )
            }
        }
        defer {
            stop()
            drainProcessingQueue()
            removeInterruptHandler()
            captureRunLoop = nil
            runMetadata = nil
            try? finalizeOutputHandle()
            if let readyLifecycleError {
                fputs(
                    "ready leaseの終了処理に失敗しました。\(readyLifecycleError.localizedDescription)\n",
                    stderr
                )
            }
        }
        guard TrackpadDriverEventSnapshotFactory.supportsRawFieldScan else {
            throw TrackpadDriverEventLoggerError.unsupportedEventFieldLayout
        }
        runMetadata = try Self.makeMetadata(configuration: configuration)
        let loggerExecutableSHA256: String?
        if configuration.manifestPath == nil {
            loggerExecutableSHA256 = nil
        } else {
            loggerExecutableSHA256 = try Self.runningExecutableSHA256()
        }
        nextCaptureIndex = 0
        emittedEvents = 0
        loggingError = nil
        try AccessibilityPermission.ensurePrompted()

        if let outputPath = configuration.outputPath, let manifestPath = configuration.manifestPath {
            do {
                try manifestStore.prepareDestination(
                    logPath: outputPath,
                    manifestPath: manifestPath
                )
            } catch let error as TrackpadDriverEventCaptureManifestStoreError {
                if case .pathConflict = error {
                    throw TrackpadDriverEventLoggerError.outputManifestPathConflict(outputPath)
                }
                throw TrackpadDriverEventLoggerError.manifestPreparationFailed(
                    error.localizedDescription
                )
            }
        }
        outputHandle = try makeOutputHandle(path: configuration.outputPath)
        installInterruptHandler()

        if configuration.outputPath == nil {
            fputs(
                "標準出力では確定後のfile bytesを再読込できないため、capture manifestは生成しません。\n",
                stderr
            )
        }

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
        let captureStartedAt = Date()
        do {
            try startAcceptingEvents(
                captureStartedAt: captureStartedAt,
                duration: configuration.duration
            )
        } catch {
            throw TrackpadDriverEventLoggerError.readyFileWriteFailed(
                error.localizedDescription
            )
        }

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
        let capturedReadyLifecycleError = currentReadyLifecycleError()
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
        let captureCompletedAt = Date()
        if let capturedReadyLifecycleError {
            throw TrackpadDriverEventLoggerError.readyFileInvalidationFailed(
                capturedReadyLifecycleError.localizedDescription
            )
        }
        if let capturedLoggingError {
            throw capturedLoggingError
        }
        guard emittedEvents > 0 else {
            throw TrackpadDriverEventLoggerError.noEventsCaptured
        }

        if let outputPath = configuration.outputPath {
            guard
                let manifestPath = configuration.manifestPath,
                let evidenceKind = configuration.evidenceKind,
                let loggerExecutableSHA256
            else {
                throw TrackpadDriverEventLoggerError.manifestConfigurationUnavailable
            }
            let logData = try Self.finalizedLogData(path: outputPath)
            let summary: TrackpadDriverEventCaptureLogSummary
            do {
                summary = try TrackpadDriverEventCaptureManifest.summarize(logData: logData)
            } catch {
                throw TrackpadDriverEventLoggerError.finalizedLogInspectionFailed(
                    error.localizedDescription
                )
            }
            guard summary.eventCount == emittedEvents else {
                throw TrackpadDriverEventLoggerError.finalizedLogEventCountMismatch(
                    emitted: emittedEvents,
                    finalized: summary.eventCount
                )
            }

            let manifest = TrackpadDriverEventCaptureManifest(
                evidenceKind: evidenceKind,
                logSummary: summary,
                loggerExecutableSHA256: loggerExecutableSHA256,
                captureStartedAt: captureStartedAt,
                captureCompletedAt: captureCompletedAt
            )
            do {
                try manifest.validate(logData: logData)
            } catch {
                throw TrackpadDriverEventLoggerError.manifestValidationFailed(
                    error.localizedDescription
                )
            }
            do {
                try manifestStore.writeAtomically(manifest, toPath: manifestPath)
            } catch let error as TrackpadDriverEventCaptureManifestStoreError {
                if case .renameFailed = error {
                    throw TrackpadDriverEventLoggerError.manifestRenameFailed(
                        error.localizedDescription
                    )
                }
                throw TrackpadDriverEventLoggerError.manifestWriteFailed(
                    error.localizedDescription
                )
            }
            fputs("capture manifestを保存しました。path=\(manifestPath)\n", stderr)
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

    private func startAcceptingEvents(
        captureStartedAt: Date,
        duration: TimeInterval?
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        acceptingEvents = true
        guard let activeReadyLease else {
            return
        }
        do {
            _ = try readyStore.publish(
                activeReadyLease,
                captureStartedAt: captureStartedAt,
                captureDeadlineAt: duration.map {
                    captureStartedAt.addingTimeInterval($0)
                }
            )
        } catch {
            acceptingEvents = false
            throw error
        }
    }

    private func stopAcceptingEvents() {
        stateLock.lock()
        if let activeReadyLease {
            do {
                try readyStore.revoke(activeReadyLease)
                self.activeReadyLease = nil
            } catch {
                if readyLifecycleError == nil {
                    readyLifecycleError = error
                }
            }
        }
        acceptingEvents = false
        stateLock.unlock()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    private func currentReadyLifecycleError() -> Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return readyLifecycleError
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
        var manifestPath: String?
        var evidenceKind: TrackpadDriverEventEvidenceKind?
        var readyFilePath: String?
        var readyRunToken: String?
        var seenOptions = Set<String>()
        var index = 0
        let supportedOptions = [
            "--duration",
            "--out",
            "--scenario-id",
            "--device-label",
            "--repo-head-sha",
            "--manifest-out",
            "--evidence-kind",
            "--ready-file",
            "--ready-token"
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
                guard Self.hasContent(value) else {
                    throw ToolError.invalidValue(option, value)
                }
                scenarioID = value
            case "--device-label":
                guard Self.hasContent(value) else {
                    throw ToolError.invalidValue(option, value)
                }
                deviceLabel = value
            case "--repo-head-sha":
                guard Self.isValidGitObjectID(value) else {
                    throw ToolError.invalidValue(option, value)
                }
                repoHeadSHA = value.lowercased()
            case "--manifest-out":
                guard !value.isEmpty else {
                    throw ToolError.invalidValue(option, value)
                }
                manifestPath = value
            case "--evidence-kind":
                guard let parsed = TrackpadDriverEventEvidenceKind(rawValue: value) else {
                    throw TrackpadDriverEventLoggerError.invalidEvidenceKind(value)
                }
                evidenceKind = parsed
            case "--ready-file":
                guard !value.isEmpty else {
                    throw ToolError.invalidValue(option, value)
                }
                readyFilePath = value
            case "--ready-token":
                guard let uuid = UUID(uuidString: value) else {
                    throw ToolError.invalidValue(option, value)
                }
                readyRunToken = uuid.uuidString.lowercased()
            default:
                break
            }
            index += 2
        }

        if let outputPath {
            manifestPath = manifestPath ?? outputPath + ".manifest.json"
            guard let evidenceKind else {
                throw TrackpadDriverEventLoggerError.missingEvidenceKind
            }
            guard let manifestPath else {
                throw TrackpadDriverEventLoggerError.manifestConfigurationUnavailable
            }
            do {
                try manifestStore.validateDistinctLocations(
                    logPath: outputPath,
                    manifestPath: manifestPath
                )
            } catch let error as TrackpadDriverEventCaptureManifestStoreError {
                if case .pathConflict = error {
                    throw TrackpadDriverEventLoggerError.outputManifestPathConflict(outputPath)
                }
                throw TrackpadDriverEventLoggerError.manifestPreparationFailed(
                    error.localizedDescription
                )
            }
            if evidenceKind != .synthetic {
                guard scenarioID != nil else {
                    throw TrackpadDriverEventLoggerError.requiredEvidenceMetadataMissing(
                        evidenceKind: evidenceKind,
                        option: "--scenario-id"
                    )
                }
                guard deviceLabel != nil else {
                    throw TrackpadDriverEventLoggerError.requiredEvidenceMetadataMissing(
                        evidenceKind: evidenceKind,
                        option: "--device-label"
                    )
                }
                guard repoHeadSHA != nil else {
                    throw TrackpadDriverEventLoggerError.requiredEvidenceMetadataMissing(
                        evidenceKind: evidenceKind,
                        option: "--repo-head-sha"
                    )
                }
            }
        } else {
            if manifestPath != nil {
                throw TrackpadDriverEventLoggerError.manifestRequiresFileOutput
            }
            if evidenceKind != nil {
                throw TrackpadDriverEventLoggerError.evidenceKindRequiresManifest
            }
        }

        if readyFilePath != nil, readyRunToken == nil {
            throw TrackpadDriverEventLoggerError.readyFileRequiresToken
        }
        if readyRunToken != nil, readyFilePath == nil {
            throw TrackpadDriverEventLoggerError.readyTokenRequiresFile
        }

        if let readyFilePath, let readyRunToken {
            let readyFileName = URL(fileURLWithPath: readyFilePath).lastPathComponent.lowercased()
            guard readyFileName.contains(readyRunToken) else {
                throw TrackpadDriverEventLoggerError.readyFilePathRequiresToken(
                    readyRunToken
                )
            }
            for reservedPath in [outputPath, manifestPath].compactMap({ $0 }) {
                do {
                    guard try !manifestStore.fileDestinationPathsConflict(
                        readyFilePath,
                        reservedPath
                    ) else {
                        throw TrackpadDriverEventLoggerError.readyFilePathConflict(
                            readyFilePath
                        )
                    }
                } catch let error as TrackpadDriverEventLoggerError {
                    throw error
                } catch {
                    throw TrackpadDriverEventLoggerError.readyFilePreparationFailed(
                        error.localizedDescription
                    )
                }
            }
        }

        return TrackpadDriverEventLoggerConfiguration(
            duration: duration,
            outputPath: outputPath,
            scenarioID: scenarioID,
            deviceLabel: deviceLabel,
            repoHeadSHA: repoHeadSHA,
            manifestPath: manifestPath,
            evidenceKind: evidenceKind,
            readyFilePath: readyFilePath,
            readyRunToken: readyRunToken
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

    private static func hasContent(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private static func runningExecutableSHA256() throws -> String {
        var requiredSize: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &requiredSize)
        guard requiredSize > 1 else {
            throw TrackpadDriverEventLoggerError.runningExecutableHashUnavailable(
                "実行file pathの必要buffer長を取得できませんでした。"
            )
        }

        var buffer = [CChar](repeating: 0, count: Int(requiredSize))
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            _NSGetExecutablePath(pointer.baseAddress, &requiredSize)
        }
        guard result == 0, let baseAddress = buffer.withUnsafeBufferPointer({ $0.baseAddress }) else {
            throw TrackpadDriverEventLoggerError.runningExecutableHashUnavailable(
                "実行file pathを取得できませんでした。"
            )
        }

        let executableURL = URL(fileURLWithPath: String(cString: baseAddress))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        do {
            let values = try executableURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize > 0 else {
                throw TrackpadDriverEventLoggerError.runningExecutableHashUnavailable(
                    "実行fileが空またはregular fileではありません。path=\(executableURL.path)"
                )
            }
            let executableData = try Data(contentsOf: executableURL, options: .mappedIfSafe)
            guard !executableData.isEmpty else {
                throw TrackpadDriverEventLoggerError.runningExecutableHashUnavailable(
                    "実行file bytesが空です。path=\(executableURL.path)"
                )
            }
            return TrackpadDriverEventCaptureManifest.sha256HexDigest(of: executableData)
        } catch let error as TrackpadDriverEventLoggerError {
            throw error
        } catch {
            throw TrackpadDriverEventLoggerError.runningExecutableHashUnavailable(
                "path=\(executableURL.path) details=\(error.localizedDescription)"
            )
        }
    }

    private static func finalizedLogData(path: String) throws -> Data {
        let logURL = URL(fileURLWithPath: path).standardizedFileURL
        do {
            return try Data(contentsOf: logURL, options: .mappedIfSafe)
        } catch {
            throw TrackpadDriverEventLoggerError.finalizedLogReadFailed(
                "path=\(logURL.path) details=\(error.localizedDescription)"
            )
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
            nape-gesture trackpad-event-log [--duration <秒>] [--out <path>] [--manifest-out <path>] [--ready-file <path> --ready-token <UUID>] [--evidence-kind <synthetic|physicalTrackpad|generatedProduct>] [--scenario-id <ID>] [--device-label <ラベル>] [--repo-head-sha <SHA>]

            純正トラックパッドがCoreGraphicsへ送るイベント契約を、listen-onlyのCGEvent tapでJSON Linesとして記録します。
            callbackではイベントのcopy・採番・bounded queue投入だけを行い、event type 0...63とzeroを含むraw field 0...255をfieldNumber昇順で保存します。
            serializedEventBase64を正本とし、OS version/build、logger version、scenario ID、device label、repo HEAD SHAを各eventへ保存します。
            --repo-head-sha は40桁または64桁の完全な16進SHAを指定してください。診断中は対象外の入力を避けてください。
            --out指定時は--evidence-kindが必須です。--manifest-out省略時は<out>.manifest.jsonへsidecarを生成します。physicalTrackpad / generatedProductでは--scenario-id、--device-label、--repo-head-shaも必須です。
            manifestはcapture開始・完了wall-clockと、確定log fileのflush / close後に再読込した最終bytesを保存し、同じdirectoryのtemporary fileからatomic renameします。capture開始前に同じpathの旧sidecarを削除するため、失敗captureに旧manifestは残りません。
            --ready-fileには呼び出し側が新規発行した--ready-token UUIDが必須で、file名にもtokenを含めます。権限確認前にready:falseの排他的leaseを作り、既存pathは削除せず失敗します。event受付開始時だけtoken、PID、開始wall-clock、有限durationのdeadline、scenario ID、repo HEAD SHAを持つready:trueへatomic更新し、受付停止前にready:falseへ戻してunlinkします。監視側は全field、deadline、PID生存を確認してから物理操作を開始してください。
            --out未指定時はJSON Linesを標準出力へ書き出しますが、完全性を証明できるfile bytesがないためmanifestを生成しません。--manifest-outまたは--evidence-kindだけの指定は失敗します。
            --duration未指定時はCtrl-Cまで継続し、SIGINT受信後にqueueをdrainしてflush / closeします。0 event、queue飽和、log write / flush / close、executable SHA取得、manifest write / renameの失敗は非ゼロ終了します。
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
        do {
            return try TrackpadDriverEventSnapshotFactory.makeRecord(
                event: capturedEvent.event,
                observedType: capturedEvent.type,
                captureIndex: capturedEvent.captureIndex,
                metadata: metadata
            )
        } catch let error as TrackpadDriverEventSnapshotError {
            switch error {
            case .unsupportedEventFieldLayout:
                throw TrackpadDriverEventLoggerError.unsupportedEventFieldLayout
            case let .serializedEventUnavailable(captureIndex):
                throw TrackpadDriverEventLoggerError.serializedEventUnavailable(captureIndex)
            }
        }
    }
}

private struct TrackpadDriverEventLoggerConfiguration {
    var duration: TimeInterval?
    var outputPath: String?
    var scenarioID: String?
    var deviceLabel: String?
    var repoHeadSHA: String?
    var manifestPath: String?
    var evidenceKind: TrackpadDriverEventEvidenceKind?
    var readyFilePath: String?
    var readyRunToken: String?
}

private struct CapturedTrackpadDriverEvent {
    var captureIndex: UInt64
    var type: CGEventType
    var event: CGEvent
}

private enum TrackpadDriverEventLoggerError: LocalizedError {
    case unknownOption(String)
    case duplicateOption(String)
    case invalidEvidenceKind(String)
    case missingEvidenceKind
    case manifestRequiresFileOutput
    case evidenceKindRequiresManifest
    case requiredEvidenceMetadataMissing(
        evidenceKind: TrackpadDriverEventEvidenceKind,
        option: String
    )
    case outputManifestPathConflict(String)
    case readyFilePathConflict(String)
    case readyFileRequiresToken
    case readyTokenRequiresFile
    case readyFilePathRequiresToken(String)
    case readyConfigurationUnavailable
    case manifestConfigurationUnavailable
    case unsupportedEventFieldLayout
    case operatingSystemBuildUnavailable(Int32)
    case runningExecutableHashUnavailable(String)
    case metadataUnavailable
    case noEventsCaptured
    case captureIndexOverflow
    case pendingEventLimitExceeded(Int)
    case eventCopyFailed(UInt64)
    case serializedEventUnavailable(UInt64)
    case outputHandleUnavailable
    case outputWriteFailed(String)
    case outputFinalizationFailed(String)
    case manifestPreparationFailed(String)
    case finalizedLogReadFailed(String)
    case finalizedLogInspectionFailed(String)
    case finalizedLogEventCountMismatch(emitted: UInt64, finalized: UInt64)
    case manifestValidationFailed(String)
    case manifestWriteFailed(String)
    case manifestRenameFailed(String)
    case readyFilePreparationFailed(String)
    case readyFileWriteFailed(String)
    case readyFileInvalidationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unknownOption(option):
            return "trackpad-event-logで未対応のオプションです: \(option)"
        case let .duplicateOption(option):
            return "同じオプションを複数回指定できません: \(option)"
        case let .invalidEvidenceKind(value):
            let values = TrackpadDriverEventEvidenceKind.allCases.map(\.rawValue).joined(separator: ", ")
            return "--evidence-kindが不正です: \(value)。指定可能値: \(values)"
        case .missingEvidenceKind:
            return "--outでcapture manifestを生成する場合は--evidence-kindが必要です。"
        case .manifestRequiresFileOutput:
            return "--manifest-outは--outと同時に指定してください。標準出力からmanifestは生成できません。"
        case .evidenceKindRequiresManifest:
            return "--evidence-kindは--outによるcapture manifest生成時だけ指定できます。"
        case let .requiredEvidenceMetadataMissing(evidenceKind, option):
            return "\(evidenceKind.rawValue)証跡には\(option)が必要です。"
        case let .outputManifestPathConflict(path):
            return "イベントログとcapture manifestを同じlocationや親子pathへ出力できません: \(path)"
        case let .readyFilePathConflict(path):
            return "ready fileをイベントログまたはcapture manifestと同じlocationや親子pathへ出力できません: \(path)"
        case .readyFileRequiresToken:
            return "--ready-fileには一意な--ready-token UUIDが必要です。"
        case .readyTokenRequiresFile:
            return "--ready-tokenは--ready-fileと同時に指定してください。"
        case let .readyFilePathRequiresToken(token):
            return "--ready-fileのfile名にはrun固有tokenを含めてください。token=\(token)"
        case .readyConfigurationUnavailable:
            return "ready fileのtoken設定が完全ではありません。"
        case .manifestConfigurationUnavailable:
            return "capture manifestの出力設定が完全ではありません。"
        case .unsupportedEventFieldLayout:
            return "この環境のCGEventField表現ではraw field scanを安全に実行できません。"
        case let .operatingSystemBuildUnavailable(code):
            return "OS build番号を取得できませんでした。errno=\(code)"
        case let .runningExecutableHashUnavailable(details):
            return "実行中logger executableのSHA-256を取得できませんでした: \(details)"
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
        case let .manifestPreparationFailed(details):
            return "capture開始前に旧manifest sidecarを無効化できませんでした: \(details)"
        case let .finalizedLogReadFailed(details):
            return "flush / close後のイベントログbytesを再読込できませんでした: \(details)"
        case let .finalizedLogInspectionFailed(details):
            return "flush / close後のイベントログを再集計できませんでした: \(details)"
        case let .finalizedLogEventCountMismatch(emitted, finalized):
            return "書き込み済みevent数と確定fileのevent数が一致しません。emitted=\(emitted) finalized=\(finalized)"
        case let .manifestValidationFailed(details):
            return "capture manifestの検証に失敗しました: \(details)"
        case let .manifestWriteFailed(details):
            return "capture manifest temporary fileの書き込みに失敗しました: \(details)"
        case let .manifestRenameFailed(details):
            return "capture manifestのatomic renameに失敗しました: \(details)"
        case let .readyFilePreparationFailed(details):
            return "capture開始前にready leaseを排他的予約できませんでした: \(details)"
        case let .readyFileWriteFailed(details):
            return "event受付開始後のready file書き込みに失敗しました: \(details)"
        case let .readyFileInvalidationFailed(details):
            return "event受付停止前のready lease撤回に失敗しました: \(details)"
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
