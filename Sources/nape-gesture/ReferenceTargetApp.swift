import AppKit
import CoreGraphics
import Foundation

final class ReferenceTargetApp: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: ReferenceTargetApp?

    private let configuration: ReferenceTargetConfiguration
    private let encoder = JSONEncoder()
    private var outputHandle: FileHandle?
    private var terminationTimer: Timer?
    private var launchFailure: Error?
    private var window: NSWindow?
    private var textView: NSTextView?
    private var focusRecord: ReferenceTargetFocusRecord?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    private init(configuration: ReferenceTargetConfiguration) {
        self.configuration = configuration
        encoder.outputFormatting = [.sortedKeys]
        super.init()
    }

    static func run(options: [String]) throws {
        let configuration = try ReferenceTargetConfiguration(options: options)
        let app = NSApplication.shared
        let delegate = ReferenceTargetApp(configuration: configuration)
        try delegate.openOutputIfNeeded()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
        if let launchFailure = delegate.launchFailure {
            throw launchFailure
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminationTimer?.invalidate()
        terminationTimer = nil
        removeEventMonitors()
        closeOutputIfNeeded()
        Self.retainedDelegate = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nape Gesture Reference Target"
        window.center()

        let split = NSSplitView(frame: frame)
        split.dividerStyle = .thin
        split.isVertical = false

        let captureView = EventCaptureView(frame: NSRect(x: 0, y: 0, width: 760, height: 240))
        captureView.wantsLayer = true
        captureView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 280))
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        split.addArrangedSubview(captureView)
        split.addArrangedSubview(scrollView)
        window.contentView = split
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(captureView)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        focusRecord = focusCapturePointIfNeeded(captureView: captureView, window: window)

        self.window = window
        self.textView = textView
        textView.appendLine("ここにマウス、スクロール、ジェスチャーイベントが表示されます。")
        if let outputPath = configuration.outputPath {
            textView.appendLine("JSON Lines 出力: \(outputPath)")
        }
        installEventMonitors(textView: textView)

        do {
            try writeReadyFileIfNeeded()
            scheduleAutomaticTerminationIfNeeded()
        } catch {
            launchFailure = error
            NSApp.terminate(nil)
        }
    }

    private func openOutputIfNeeded() throws {
        guard let outputPath = configuration.outputPath else {
            return
        }

        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url, options: .atomic)
        outputHandle = try FileHandle(forWritingTo: url)
    }

    private func writeReadyFileIfNeeded() throws {
        guard let readyFilePath = configuration.readyFilePath else {
            return
        }

        let url = URL(fileURLWithPath: readyFilePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try encoder.encode(ReferenceTargetReadyRecord(
            ready: true,
            pid: ProcessInfo.processInfo.processIdentifier,
            timestamp: Date().timeIntervalSince1970,
            outputPath: configuration.outputPath,
            focus: focusRecord
        ))
        data.append(Data("\n".utf8))
        try data.write(to: url, options: .atomic)
    }

    private func focusCapturePointIfNeeded(
        captureView: NSView,
        window: NSWindow
    ) -> ReferenceTargetFocusRecord? {
        guard configuration.focusCapturePoint else {
            return nil
        }

        let captureCenter = NSPoint(x: captureView.bounds.midX, y: captureView.bounds.midY)
        let windowPoint = captureView.convert(captureCenter, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        let windowBounds = quartzWindowBounds(for: window)
        let quartzPoint = focusPoint(
            appKitScreenPoint: screenPoint,
            screen: window.screen,
            windowBounds: windowBounds
        )
        CGWarpMouseCursorPosition(quartzPoint)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        let cursorLocation = CGEvent(source: nil)?.location ?? quartzPoint
        return ReferenceTargetFocusRecord(
            requested: true,
            appKitScreenX: Double(screenPoint.x),
            appKitScreenY: Double(screenPoint.y),
            quartzX: Double(quartzPoint.x),
            quartzY: Double(quartzPoint.y),
            cursorX: Double(cursorLocation.x),
            cursorY: Double(cursorLocation.y),
            windowQuartzX: windowBounds.map { Double($0.minX) },
            windowQuartzY: windowBounds.map { Double($0.minY) },
            windowQuartzWidth: windowBounds.map { Double($0.width) },
            windowQuartzHeight: windowBounds.map { Double($0.height) }
        )
    }

    private func focusPoint(
        appKitScreenPoint point: NSPoint,
        screen: NSScreen?,
        windowBounds: CGRect?
    ) -> CGPoint {
        if let windowBounds {
            let verticalOffset = min(max(windowBounds.height * 0.28, 96), windowBounds.height - 32)
            return CGPoint(x: windowBounds.midX, y: windowBounds.minY + verticalOffset)
        }
        return quartzDisplayPoint(fromAppKitScreenPoint: point, screen: screen)
    }

    private func quartzDisplayPoint(
        fromAppKitScreenPoint point: NSPoint,
        screen: NSScreen?
    ) -> CGPoint {
        guard let screen else {
            return CGPoint(x: point.x, y: point.y)
        }
        return CGPoint(x: point.x, y: screen.frame.maxY - point.y)
    }

    private func quartzWindowBounds(for window: NSWindow) -> CGRect? {
        let windowID = CGWindowID(window.windowNumber)
        guard let descriptions = CGWindowListCreateDescriptionFromArray([windowID] as CFArray) as? [[String: Any]],
              let entry = descriptions.first,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any]
        else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private func scheduleAutomaticTerminationIfNeeded() {
        guard let duration = configuration.duration else {
            return
        }

        terminationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            NSApp.terminate(nil)
        }
    }

    private func installEventMonitors(textView: NSTextView) {
        let mask = NSEvent.EventTypeMask([
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseUp,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseUp,
            .otherMouseDragged,
            .scrollWheel,
            .keyDown,
            .keyUp,
            .swipe,
            .magnify,
            .rotate
        ])
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self, weak textView] event in
            self?.record(event: event, textView: textView)
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self, weak textView] event in
            self?.record(event: event, textView: textView)
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        localEventMonitor = nil
        globalEventMonitor = nil
    }

    private func record(event: NSEvent, textView: NSTextView?) {
        guard let eventName = targetEventName(for: event) else {
            return
        }
        let position = window?.contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        let record = TargetEventRecord(name: eventName, event: event, position: position)
        DispatchQueue.main.async { [weak self, weak textView] in
            self?.write(record)
            textView?.appendLine(record.displayLine)
        }
    }

    private func targetEventName(for event: NSEvent) -> String? {
        switch event.type {
        case .scrollWheel:
            return "scrollWheel"
        case .swipe:
            return "swipe"
        case .magnify:
            return "magnify"
        case .rotate:
            return "rotate"
        case .leftMouseDown:
            return "mouseDown"
        case .leftMouseUp:
            return "mouseUp"
        case .leftMouseDragged:
            return "mouseDragged"
        case .rightMouseDown:
            return "rightMouseDown"
        case .rightMouseUp:
            return "rightMouseUp"
        case .rightMouseDragged:
            return "rightMouseDragged"
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .otherMouseDragged:
            return "otherMouseDragged"
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        default:
            return nil
        }
    }

    private func write(_ record: TargetEventRecord) {
        guard let outputHandle,
              let data = try? encoder.encode(record)
        else {
            return
        }
        outputHandle.write(data)
        outputHandle.write(Data("\n".utf8))
    }

    private func closeOutputIfNeeded() {
        try? outputHandle?.close()
        outputHandle = nil
    }
}

private struct ReferenceTargetConfiguration {
    var outputPath: String?
    var duration: TimeInterval?
    var readyFilePath: String?
    var focusCapturePoint: Bool

    init(options: [String]) throws {
        outputPath = try Self.optionalValue(for: "--out", in: options)
        duration = try Self.optionalDuration(in: options)
        readyFilePath = try Self.optionalValue(for: "--ready-file", in: options)
        focusCapturePoint = options.contains("--focus-capture-point")
    }

    private static func optionalValue(for name: String, in options: [String]) throws -> String? {
        guard options.contains(name) else {
            return nil
        }
        return try SettingsStore.requiredValue(for: name, in: options)
    }

    private static func optionalDuration(in options: [String]) throws -> TimeInterval? {
        guard options.contains("--duration") else {
            return nil
        }

        let raw = try SettingsStore.requiredValue(for: "--duration", in: options)
        guard let duration = TimeInterval(raw), duration.isFinite, duration > 0 else {
            throw ToolError.invalidValue("--duration", raw)
        }
        return duration
    }
}

private struct ReferenceTargetReadyRecord: Codable, Equatable {
    var ready: Bool
    var pid: Int32
    var timestamp: TimeInterval
    var outputPath: String?
    var focus: ReferenceTargetFocusRecord?
}

private struct ReferenceTargetFocusRecord: Codable, Equatable {
    var requested: Bool
    var appKitScreenX: Double
    var appKitScreenY: Double
    var quartzX: Double
    var quartzY: Double
    var cursorX: Double
    var cursorY: Double
    var windowQuartzX: Double?
    var windowQuartzY: Double?
    var windowQuartzWidth: Double?
    var windowQuartzHeight: Double?
}

final class EventCaptureView: NSView {
    var onEvent: ((TargetEventRecord) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        let message = "この領域上で、生成イベント・純正トラックパッド・Nape Pro 操作を比較してください。"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor
        ]
        message.draw(at: NSPoint(x: 24, y: bounds.midY), withAttributes: attributes)
    }

    override func scrollWheel(with event: NSEvent) {
        emit("scrollWheel", event: event)
    }

    override func swipe(with event: NSEvent) {
        emit("swipe", event: event)
    }

    override func magnify(with event: NSEvent) {
        emit("magnify", event: event)
    }

    override func rotate(with event: NSEvent) {
        emit("rotate", event: event)
    }

    override func mouseDown(with event: NSEvent) {
        emit("mouseDown", event: event)
    }

    override func mouseUp(with event: NSEvent) {
        emit("mouseUp", event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        emit("otherMouseDown", event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        emit("otherMouseUp", event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        emit("rightMouseDown", event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        emit("rightMouseUp", event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        emit("mouseDragged", event: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        emit("otherMouseDragged", event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        emit("rightMouseDragged", event: event)
    }

    override func keyDown(with event: NSEvent) {
        emit("keyDown", event: event)
    }

    override func keyUp(with event: NSEvent) {
        emit("keyUp", event: event)
    }

    private func emit(_ name: String, event: NSEvent) {
        let position = convert(event.locationInWindow, from: nil)
        onEvent?(TargetEventRecord(name: name, event: event, position: position))
    }
}

struct TargetEventRecord: Codable, Equatable {
    var timestamp: TimeInterval
    var name: String
    var locationX: Double
    var locationY: Double
    var deltaX: Double
    var deltaY: Double
    var scrollingDeltaX: Double
    var scrollingDeltaY: Double
    var phase: UInt
    var momentumPhase: UInt
    var hasPreciseScrollingDeltas: Bool
    var magnification: Double
    var rotation: Double
    var buttonNumber: Int
    var clickCount: Int
    var modifierFlags: UInt
    var keyCode: UInt16?
    var generatedByNapeGesture: Bool

    init(name: String, event: NSEvent, position: NSPoint) {
        self.timestamp = event.timestamp
        self.name = name
        locationX = Double(position.x)
        locationY = Double(position.y)
        deltaX = Double(event.deltaX)
        deltaY = Double(event.deltaY)
        scrollingDeltaX = Double(event.scrollingDeltaX)
        scrollingDeltaY = Double(event.scrollingDeltaY)
        phase = event.phase.rawValue
        momentumPhase = event.momentumPhase.rawValue
        hasPreciseScrollingDeltas = event.hasPreciseScrollingDeltas
        magnification = Double(event.magnification)
        rotation = Double(event.rotation)
        buttonNumber = event.buttonNumber
        clickCount = event.clickCount
        modifierFlags = event.modifierFlags.rawValue
        keyCode = name == "keyDown" || name == "keyUp" ? event.keyCode : nil
        generatedByNapeGesture = event.cgEvent.map(CGEventUtilities.isGeneratedByThisTool) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case name
        case locationX
        case locationY
        case deltaX
        case deltaY
        case scrollingDeltaX
        case scrollingDeltaY
        case phase
        case momentumPhase
        case hasPreciseScrollingDeltas
        case magnification
        case rotation
        case buttonNumber
        case clickCount
        case modifierFlags
        case keyCode
        case generatedByNapeGesture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        name = try container.decode(String.self, forKey: .name)
        locationX = try container.decode(Double.self, forKey: .locationX)
        locationY = try container.decode(Double.self, forKey: .locationY)
        deltaX = try container.decode(Double.self, forKey: .deltaX)
        deltaY = try container.decode(Double.self, forKey: .deltaY)
        scrollingDeltaX = try container.decode(Double.self, forKey: .scrollingDeltaX)
        scrollingDeltaY = try container.decode(Double.self, forKey: .scrollingDeltaY)
        phase = try container.decode(UInt.self, forKey: .phase)
        momentumPhase = try container.decode(UInt.self, forKey: .momentumPhase)
        hasPreciseScrollingDeltas = try container.decode(Bool.self, forKey: .hasPreciseScrollingDeltas)
        magnification = try container.decode(Double.self, forKey: .magnification)
        rotation = try container.decode(Double.self, forKey: .rotation)
        buttonNumber = try container.decode(Int.self, forKey: .buttonNumber)
        clickCount = try container.decode(Int.self, forKey: .clickCount)
        modifierFlags = try container.decode(UInt.self, forKey: .modifierFlags)
        keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        generatedByNapeGesture = try container.decodeIfPresent(Bool.self, forKey: .generatedByNapeGesture) ?? false
    }

    var displayLine: String {
        let base = "\(Date()) \(name) loc=(\(Int(locationX)),\(Int(locationY)))"

        switch name {
        case "scrollWheel":
            return base
                + " dx=\(format(scrollingDeltaX)) dy=\(format(scrollingDeltaY))"
                + " phase=\(phase) momentum=\(momentumPhase) precise=\(hasPreciseScrollingDeltas)"
        case "swipe":
            return base + " dx=\(format(deltaX)) dy=\(format(deltaY)) phase=\(phase)"
        case "magnify":
            return base + " magnification=\(format(magnification)) phase=\(phase)"
        case "rotate":
            return base + " rotation=\(format(rotation)) phase=\(phase)"
        case "mouseDragged":
            return base + " dx=\(format(deltaX)) dy=\(format(deltaY))"
        case "otherMouseDown", "otherMouseUp", "rightMouseDown", "rightMouseUp":
            return base + " button=\(buttonNumber)"
        case "otherMouseDragged":
            return base + " button=\(buttonNumber) dx=\(format(deltaX)) dy=\(format(deltaY))"
        case "rightMouseDragged":
            return base + " button=\(buttonNumber) dx=\(format(deltaX)) dy=\(format(deltaY))"
        case "keyDown", "keyUp":
            return base
                + " keyCode=\(keyCode.map { String($0) } ?? "-")"
                + " flags=\(modifierFlags)"
        default:
            return base
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private extension NSTextView {
    func appendLine(_ line: String) {
        let attributed = NSAttributedString(string: line + "\n")
        textStorage?.append(attributed)
        scrollToEndOfDocument(nil)
    }
}
