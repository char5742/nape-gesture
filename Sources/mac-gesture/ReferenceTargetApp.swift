import AppKit
import Foundation

final class ReferenceTargetApp: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: ReferenceTargetApp?

    private let outputPath: String?
    private let encoder = JSONEncoder()
    private var outputHandle: FileHandle?
    private var window: NSWindow?
    private var textView: NSTextView?

    init(outputPath: String?) {
        self.outputPath = outputPath
        encoder.outputFormatting = [.sortedKeys]
        super.init()
    }

    static func run(options: [String]) throws {
        let app = NSApplication.shared
        let delegate = ReferenceTargetApp(outputPath: SettingsStore.value(for: "--out", in: options))
        try delegate.openOutputIfNeeded()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        window.title = "Mac Gesture Reference Target"
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

        captureView.onEvent = { [weak self, weak textView] record in
            DispatchQueue.main.async {
                self?.write(record)
                textView?.appendLine(record.displayLine)
            }
        }

        split.addArrangedSubview(captureView)
        split.addArrangedSubview(scrollView)
        window.contentView = split
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(captureView)

        self.window = window
        self.textView = textView
        textView.appendLine("ここにマウス、スクロール、ジェスチャーイベントが表示されます。")
        if let outputPath {
            textView.appendLine("JSON Lines 出力: \(outputPath)")
        }
    }

    private func openOutputIfNeeded() throws {
        guard let outputPath else {
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

    override func mouseDragged(with event: NSEvent) {
        emit("mouseDragged", event: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        emit("otherMouseDragged", event: event)
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
        case "otherMouseDown", "otherMouseUp":
            return base + " button=\(buttonNumber)"
        case "otherMouseDragged":
            return base + " button=\(buttonNumber) dx=\(format(deltaX)) dy=\(format(deltaY))"
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
