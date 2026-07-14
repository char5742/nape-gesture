import AppKit
import CoreGraphics
import Foundation
import NapeGestureCore

struct CursorAnchorSystemVerificationReport: Codable, Equatable {
    let schemaVersion: Int
    let logicalButtonNumber: Int
    let sourceButtonNumber: Int
    let foregroundBundleIdentifier: String
    let anchorX: Double
    let anchorY: Double
    let moveSampleCount: Int
    let intervalMilliseconds: Double
    let maximumDeviationPoints: Double
    let longestDeviationMilliseconds: Double
    let wheelMaximumDeviationPoints: Double
    let wheelLongestDeviationMilliseconds: Double
    let unexpectedMouseMovedEventCount: UInt32
    let normalMoveRecoveredAfterDrag: Bool
    let normalMoveRecoveredAfterWheel: Bool
}

struct CursorAnchorSystemVerifier {
    private static let napeGestureBundleIdentifier = "dev.char5742.nape-gesture"
    private static let positionTolerance: Double = 0.75
    private static let visibleDeviationLimit: TimeInterval = 1.0 / 120.0

    let logicalButtonNumber: Int
    let amount: Double
    let steps: Int
    let interval: TimeInterval

    func run() throws -> CursorAnchorSystemVerificationReport {
        guard let foreground = NSWorkspace.shared.frontmostApplication,
              let foregroundBundleIdentifier = foreground.bundleIdentifier,
              foregroundBundleIdentifier != Self.napeGestureBundleIdentifier
        else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "Nape Gesture以外のforeground applicationを確定できませんでした。"
            )
        }
        let sourceButton = try sourceButtonForLogicalButton()
        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let cgMouseButton = CGMouseButton(rawValue: UInt32(sourceButton.rawValue))
        else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "mouse event sourceを作成できませんでした。"
            )
        }
        eventSource.setLocalEventsFilterDuringSuppressionState(
            [],
            state: .eventSuppressionStateSuppressionInterval
        )

        let originalPosition = currentPointerLocation()
        let anchor = safeAnchorPosition()
        let setupResult = CGWarpMouseCursorPosition(anchor)
        guard setupResult == .success,
              waitForPosition(anchor, timeout: 0.1)
        else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "検証開始位置へcursorを移動できませんでした。CGError=\(setupResult.rawValue)"
            )
        }
        defer {
            _ = CGWarpMouseCursorPosition(originalPosition)
        }

        let mouseMovedCountBefore = CGEventSource.counterForEventType(
            .hidSystemState,
            eventType: .mouseMoved
        )
        let moveMetrics = try runMoveSession(
            anchor: anchor,
            source: eventSource,
            mouseButton: cgMouseButton,
            buttonNumber: Int64(sourceButton.rawValue)
        )
        let mouseMovedCountAfter = CGEventSource.counterForEventType(
            .hidSystemState,
            eventType: .mouseMoved
        )
        let unexpectedMouseMovedEventCount = mouseMovedCountAfter &- mouseMovedCountBefore
        guard unexpectedMouseMovedEventCount == 0 else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "drag session中に未投稿のmouseMoved eventを検出しました: count=\(unexpectedMouseMovedEventCount)"
            )
        }
        let recoveredAfterDrag = try assertNormalMove(
            from: anchor,
            source: eventSource,
            deltaX: 21,
            deltaY: 13
        )

        let dragRecoveryResult = CGWarpMouseCursorPosition(anchor)
        guard dragRecoveryResult == .success,
              waitForPosition(anchor, timeout: 0.1)
        else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "wheel検証前にanchorへ戻せませんでした。CGError=\(dragRecoveryResult.rawValue)"
            )
        }

        let wheelMetrics = try runWheelSession(
            anchor: anchor,
            source: eventSource,
            mouseButton: cgMouseButton,
            buttonNumber: Int64(sourceButton.rawValue)
        )
        let recoveredAfterWheel = try assertNormalMove(
            from: anchor,
            source: eventSource,
            deltaX: -17,
            deltaY: 11
        )

        return CursorAnchorSystemVerificationReport(
            schemaVersion: 1,
            logicalButtonNumber: logicalButtonNumber,
            sourceButtonNumber: sourceButton.rawValue,
            foregroundBundleIdentifier: foregroundBundleIdentifier,
            anchorX: Double(anchor.x),
            anchorY: Double(anchor.y),
            moveSampleCount: steps,
            intervalMilliseconds: interval * 1_000,
            maximumDeviationPoints: moveMetrics.maximumDeviation,
            longestDeviationMilliseconds: moveMetrics.longestDeviation * 1_000,
            wheelMaximumDeviationPoints: wheelMetrics.maximumDeviation,
            wheelLongestDeviationMilliseconds: wheelMetrics.longestDeviation * 1_000,
            unexpectedMouseMovedEventCount: unexpectedMouseMovedEventCount,
            normalMoveRecoveredAfterDrag: recoveredAfterDrag,
            normalMoveRecoveredAfterWheel: recoveredAfterWheel
        )
    }

    private func runMoveSession(
        anchor: CGPoint,
        source: CGEventSource,
        mouseButton: CGMouseButton,
        buttonNumber: Int64
    ) throws -> CursorDeviationMetrics {
        var buttonIsDown = false
        defer {
            if buttonIsDown,
               let release = mouseEvent(
                   source: source,
                   type: .otherMouseUp,
                   position: anchor,
                   mouseButton: mouseButton,
                   buttonNumber: buttonNumber,
                   deltaX: 0,
                   deltaY: 0
               ) {
                release.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: max(interval, 0.002))
            }
        }

        guard let buttonDown = mouseEvent(
            source: source,
            type: .otherMouseDown,
            position: anchor,
            mouseButton: mouseButton,
            buttonNumber: buttonNumber,
            deltaX: 0,
            deltaY: 0
        ) else {
            throw ToolError.invalidValue("cursor anchor検証", "button down eventを作成できませんでした。")
        }
        buttonDown.post(tap: .cghidEventTap)
        buttonIsDown = true
        Thread.sleep(forTimeInterval: max(interval, 0.002))
        try requireAnchor(anchor, context: "button down後")

        let sampler = CursorDeviationSampler(
            anchor: anchor,
            tolerance: Self.positionTolerance
        )
        sampler.start()
        let deltas = moveDeltas()
        for delta in deltas {
            guard let move = mouseEvent(
                source: source,
                type: .otherMouseDragged,
                position: CGPoint(
                    x: anchor.x + CGFloat(delta.x),
                    y: anchor.y + CGFloat(delta.y)
                ),
                mouseButton: mouseButton,
                buttonNumber: buttonNumber,
                deltaX: delta.x,
                deltaY: delta.y
            ) else {
                _ = sampler.stop()
                throw ToolError.invalidValue("cursor anchor検証", "drag eventを作成できませんでした。")
            }
            move.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: interval)
        }
        Thread.sleep(forTimeInterval: Self.visibleDeviationLimit)
        let metrics = sampler.stop()
        try requireAcceptable(metrics, context: "高頻度move中")
        try requireAnchor(anchor, context: "move列完了後")

        guard let buttonUp = mouseEvent(
            source: source,
            type: .otherMouseUp,
            position: anchor,
            mouseButton: mouseButton,
            buttonNumber: buttonNumber,
            deltaX: 0,
            deltaY: 0
        ) else {
            throw ToolError.invalidValue("cursor anchor検証", "button up eventを作成できませんでした。")
        }
        buttonUp.post(tap: .cghidEventTap)
        buttonIsDown = false
        Thread.sleep(forTimeInterval: max(interval, 0.002))
        try requireAnchor(anchor, context: "button up後")
        return metrics
    }

    private func runWheelSession(
        anchor: CGPoint,
        source: CGEventSource,
        mouseButton: CGMouseButton,
        buttonNumber: Int64
    ) throws -> CursorDeviationMetrics {
        var buttonIsDown = false
        defer {
            if buttonIsDown,
               let release = mouseEvent(
                   source: source,
                   type: .otherMouseUp,
                   position: anchor,
                   mouseButton: mouseButton,
                   buttonNumber: buttonNumber,
                   deltaX: 0,
                   deltaY: 0
               ) {
                release.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: max(interval, 0.002))
            }
        }
        guard let buttonDown = mouseEvent(
            source: source,
            type: .otherMouseDown,
            position: anchor,
            mouseButton: mouseButton,
            buttonNumber: buttonNumber,
            deltaX: 0,
            deltaY: 0
        ) else {
            throw ToolError.invalidValue("cursor anchor検証", "wheel sessionのbutton downを作成できませんでした。")
        }
        buttonDown.post(tap: .cghidEventTap)
        buttonIsDown = true
        Thread.sleep(forTimeInterval: max(interval, 0.002))
        try requireAnchor(anchor, context: "wheel session開始後")

        let sampler = CursorDeviationSampler(
            anchor: anchor,
            tolerance: Self.positionTolerance
        )
        sampler.start()
        guard let wheel = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: 19,
            wheel2: -13,
            wheel3: 0
        ) else {
            _ = sampler.stop()
            throw ToolError.invalidValue("cursor anchor検証", "wheel eventを作成できませんでした。")
        }
        wheel.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 19)
        wheel.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -13)
        wheel.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: max(interval, Self.visibleDeviationLimit))
        let metrics = sampler.stop()
        try requireAcceptable(metrics, context: "wheel sample中")
        try requireAnchor(anchor, context: "wheel sample後")

        guard let buttonUp = mouseEvent(
            source: source,
            type: .otherMouseUp,
            position: anchor,
            mouseButton: mouseButton,
            buttonNumber: buttonNumber,
            deltaX: 0,
            deltaY: 0
        ) else {
            throw ToolError.invalidValue("cursor anchor検証", "wheel sessionのbutton upを作成できませんでした。")
        }
        buttonUp.post(tap: .cghidEventTap)
        buttonIsDown = false
        Thread.sleep(forTimeInterval: max(interval, 0.002))
        try requireAnchor(anchor, context: "wheel session終了後")
        return metrics
    }

    private func assertNormalMove(
        from anchor: CGPoint,
        source: CGEventSource,
        deltaX: Int64,
        deltaY: Int64
    ) throws -> Bool {
        let expected = CGPoint(
            x: anchor.x + CGFloat(deltaX),
            y: anchor.y + CGFloat(deltaY)
        )
        guard let move = mouseEvent(
            source: source,
            type: .mouseMoved,
            position: expected,
            mouseButton: .left,
            buttonNumber: 0,
            deltaX: deltaX,
            deltaY: deltaY
        ) else {
            throw ToolError.invalidValue("cursor anchor検証", "通常mouse moveを作成できませんでした。")
        }
        move.post(tap: .cghidEventTap)
        guard waitForPosition(expected, timeout: 0.1) else {
            let actual = currentPointerLocation()
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "session終了後に通常mouse移動へ復帰しませんでした: expected=(\(expected.x), \(expected.y)), actual=(\(actual.x), \(actual.y))"
            )
        }
        return true
    }

    private func moveDeltas() -> [(x: Int64, y: Int64)] {
        let perStep = max(12.0, min(abs(amount) / Double(max(steps, 1)), 96.0))
        let pattern: [(Double, Double)] = [
            (1.0, -0.75),
            (-1.5, 0.5),
            (0.625, 1.375),
            (-0.875, -1.25),
            (1.75, 0.875),
            (-1.0, -0.75),
        ]
        var deltas = (0..<(steps - 1)).map { index in
            let scale = pattern[index % pattern.count]
            return (
                x: Int64((perStep * scale.0).rounded()),
                y: Int64((perStep * scale.1).rounded())
            )
        }
        let accumulatedX = deltas.reduce(Int64(0)) { $0 + $1.x }
        let accumulatedY = deltas.reduce(Int64(0)) { $0 + $1.y }
        deltas.append((x: -accumulatedX, y: -accumulatedY))
        return deltas
    }

    private func mouseEvent(
        source: CGEventSource,
        type: CGEventType,
        position: CGPoint,
        mouseButton: CGMouseButton,
        buttonNumber: Int64,
        deltaX: Int64,
        deltaY: Int64
    ) -> CGEvent? {
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: position,
            mouseButton: mouseButton
        )
        event?.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        event?.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
        event?.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }

    private func sourceButtonForLogicalButton() throws -> MouseButton {
        switch logicalButtonNumber {
        case 3:
            .button3
        case 4:
            .button4
        case 5:
            .center
        default:
            throw ToolError.invalidValue("--logical-button", String(logicalButtonNumber))
        }
    }

    private func safeAnchorPosition() -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func waitForPosition(_ expected: CGPoint, timeout: TimeInterval) -> Bool {
        let deadline = MonotonicEventClock.nowSeconds + timeout
        repeat {
            if distance(from: currentPointerLocation(), to: expected) <= Self.positionTolerance {
                return true
            }
            Thread.sleep(forTimeInterval: 0.0005)
        } while MonotonicEventClock.nowSeconds < deadline
        return false
    }

    private func requireAnchor(_ anchor: CGPoint, context: String) throws {
        let actual = currentPointerLocation()
        let deviation = distance(from: actual, to: anchor)
        guard deviation <= Self.positionTolerance else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "\(context)にcursorがanchorから外れました: deviation=\(deviation)"
            )
        }
    }

    private func requireAcceptable(
        _ metrics: CursorDeviationMetrics,
        context: String
    ) throws {
        guard metrics.maximumDeviation <= Self.positionTolerance else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "\(context)にcursor座標の逸脱を検出しました: max=\(metrics.maximumDeviation)"
            )
        }
        guard metrics.longestDeviation < Self.visibleDeviationLimit else {
            throw ToolError.invalidValue(
                "cursor anchor検証",
                "\(context)に目視可能なcursor逸脱を検出しました: max=\(metrics.maximumDeviation), duration_ms=\(metrics.longestDeviation * 1_000)"
            )
        }
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> Double {
        hypot(Double(lhs.x - rhs.x), Double(lhs.y - rhs.y))
    }
}

private struct CursorDeviationMetrics {
    let maximumDeviation: Double
    let longestDeviation: TimeInterval
}

private final class CursorDeviationSampler {
    private let anchor: CGPoint
    private let tolerance: Double
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "dev.char5742.nape-gesture.cursor-anchor-sampler")
    private let group = DispatchGroup()
    private var isRunning = false
    private var maximumDeviation = 0.0
    private var deviationStartedAt: TimeInterval?
    private var longestDeviation = 0.0

    init(anchor: CGPoint, tolerance: Double) {
        self.anchor = anchor
        self.tolerance = tolerance
    }

    func start() {
        lock.lock()
        isRunning = true
        lock.unlock()
        group.enter()
        queue.async { [self] in
            defer { group.leave() }
            while running() {
                sample()
                Thread.sleep(forTimeInterval: 0.0005)
            }
            sample()
        }
    }

    func stop() -> CursorDeviationMetrics {
        lock.lock()
        isRunning = false
        lock.unlock()
        group.wait()

        lock.lock()
        defer { lock.unlock() }
        finishDeviation(at: MonotonicEventClock.nowSeconds)
        return CursorDeviationMetrics(
            maximumDeviation: maximumDeviation,
            longestDeviation: longestDeviation
        )
    }

    private func running() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    private func sample() {
        guard let position = CGEvent(source: nil)?.location else {
            return
        }
        let now = MonotonicEventClock.nowSeconds
        let deviation = hypot(
            Double(position.x - anchor.x),
            Double(position.y - anchor.y)
        )

        lock.lock()
        defer { lock.unlock() }
        maximumDeviation = max(maximumDeviation, deviation)
        if deviation > tolerance {
            if deviationStartedAt == nil {
                deviationStartedAt = now
            }
        } else {
            finishDeviation(at: now)
        }
    }

    private func finishDeviation(at timestamp: TimeInterval) {
        guard let deviationStartedAt else {
            return
        }
        longestDeviation = max(longestDeviation, timestamp - deviationStartedAt)
        self.deviationStartedAt = nil
    }
}
