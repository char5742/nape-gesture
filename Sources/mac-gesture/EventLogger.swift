import CoreGraphics
import Foundation
import MacGestureCore

final class EventLogger {
    private let encoder = JSONEncoder()
    private let options: [String]
    private var configuration = EventLoggerConfiguration(
        duration: nil,
        outputPath: nil,
        excludesGeneratedEvents: false,
        onlyGeneratedEvents: false
    )
    private var outputHandle: FileHandle?
    private var closesOutputHandle = false
    private var eventTap: CFMachPort?
    private var emittedEvents = 0

    init(options: [String] = []) {
        self.options = options
        encoder.outputFormatting = [.sortedKeys]
    }

    func run() throws {
        let configuration = try makeConfiguration()
        self.configuration = configuration
        try AccessibilityPermission.ensurePrompted()

        outputHandle = try makeOutputHandle(path: configuration.outputPath)
        defer {
            closeOutputHandleIfNeeded()
        }

        let mask = CGEventUtilities.eventMask(for: CGEventUtilities.observedMouseEventTypes)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: loggerCallback,
            userInfo: userInfo
        ) else {
            throw ToolError.eventTapCreationFailed
        }

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw ToolError.eventTapCreationFailed
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        if let duration = configuration.duration {
            fputs("イベントログを開始しました。duration=\(duration)秒\n", stderr)
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, duration, false)
            stop()
            fputs("イベントログを終了しました。events=\(emittedEvents)\n", stderr)
        } else {
            fputs("イベントログを開始しました。停止するには Ctrl-C を押してください。\n", stderr)
            CFRunLoopRun()
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let record = InputLogRecord(type: type, event: event)
        guard shouldEmit(record) else {
            return Unmanaged.passUnretained(event)
        }
        if let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) {
            writeLine(line)
            emittedEvents += 1
        }
        return Unmanaged.passUnretained(event)
    }

    private func makeConfiguration() throws -> EventLoggerConfiguration {
        if options.contains("--exclude-generated") && options.contains("--only-generated") {
            throw ToolError.invalidValue("--exclude-generated", "--only-generated と併用できません。")
        }

        let duration: TimeInterval?
        if options.contains("--duration") {
            let raw = try SettingsStore.requiredValue(for: "--duration", in: options)
            guard let parsed = TimeInterval(raw), parsed > 0 else {
                throw ToolError.invalidValue("--duration", raw)
            }
            duration = parsed
        } else {
            duration = nil
        }

        return EventLoggerConfiguration(
            duration: duration,
            outputPath: SettingsStore.value(for: "--out", in: options),
            excludesGeneratedEvents: options.contains("--exclude-generated"),
            onlyGeneratedEvents: options.contains("--only-generated")
        )
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

    private func shouldEmit(_ record: InputLogRecord) -> Bool {
        if configuration.excludesGeneratedEvents && record.generatedByMacGesture {
            return false
        }
        if configuration.onlyGeneratedEvents && !record.generatedByMacGesture {
            return false
        }
        return true
    }

    private func writeLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }
        outputHandle?.write(data)
    }

    private func stop() {
        guard let eventTap else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        self.eventTap = nil
    }

    private func closeOutputHandleIfNeeded() {
        guard closesOutputHandle, let outputHandle else {
            return
        }
        try? outputHandle.close()
        self.outputHandle = nil
        closesOutputHandle = false
    }
}

private struct EventLoggerConfiguration {
    var duration: TimeInterval?
    var outputPath: String?
    var excludesGeneratedEvents: Bool
    var onlyGeneratedEvents: Bool
}

extension InputLogRecord {
    init(type: CGEventType, event: CGEvent) {
        self.init(
            timestamp: event.timestamp,
            typeName: type.stableName,
            typeRaw: Int(type.rawValue),
            generatedByMacGesture: CGEventUtilities.isGeneratedByThisTool(event),
            buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
            deltaX: event.getIntegerValueField(.mouseEventDeltaX),
            deltaY: event.getIntegerValueField(.mouseEventDeltaY),
            scrollDeltaX: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            scrollDeltaY: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            pointDeltaX: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
            pointDeltaY: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags.rawValue
        )
    }
}

private extension CGEventType {
    var stableName: String {
        switch self {
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
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .otherMouseDragged:
            return "otherMouseDragged"
        case .scrollWheel:
            return "scrollWheel"
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        default:
            return "raw-\(rawValue)"
        }
    }
}

private let loggerCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let logger = Unmanaged<EventLogger>.fromOpaque(userInfo).takeUnretainedValue()
    return logger.handle(type: type, event: event)
}
