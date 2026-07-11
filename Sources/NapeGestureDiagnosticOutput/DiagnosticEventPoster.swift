import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore

public final class DiagnosticEventPoster {
    private let source: CGEventSource?

    public init() {
        source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
    }

    @discardableResult
    public func postScroll(
        command: GestureCommand,
        mode: ScrollPostMode
    ) -> DiagnosticEventPostResult {
        guard let event = makeScrollEvent(command: command, mode: mode) else {
            return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }
        event.post(tap: .cghidEventTap)
        return DiagnosticEventPostResult(generatedEventCount: 1, failedEventCreationCount: 0)
    }

    public func makeScrollEvent(command: GestureCommand, mode: ScrollPostMode) -> CGEvent? {
        let deltas = mode.deltas(for: command)
        let wheel1 = quantize(deltas.y)
        let wheel2 = quantize(deltas.x)

        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheel1,
            wheel2: wheel2,
            wheel3: 0
        ) else {
            return nil
        }

        setGeneratedMarker(on: event)
        let phases = phaseValues(for: command)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phases.scroll)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phases.momentum)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.timestamp = CGEventTimestamp(max(command.timestamp, 0) * 1_000_000_000)
        return event
    }

    @discardableResult
    public func postMissionControl() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl)
    }

    @discardableResult
    public func postPageBack() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand)
    }

    @discardableResult
    public func postPageForward() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand)
    }

    @discardableResult
    public func postZoomIn() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand)
    }

    @discardableResult
    public func postZoomOut() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand)
    }

    private func postKeyShortcut(
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> DiagnosticEventPostResult {
        let events = [
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        ].compactMap { $0 }

        for event in events {
            setGeneratedMarker(on: event)
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }

        return DiagnosticEventPostResult(
            generatedEventCount: events.count,
            failedEventCreationCount: 2 - events.count
        )
    }

    private func setGeneratedMarker(on event: CGEvent) {
        event.setIntegerValueField(
            .eventSourceUserData,
            value: NapeGestureGeneratedEventMarker.value
        )
    }

    private func phaseValues(for command: GestureCommand) -> (scroll: Int64, momentum: Int64) {
        let encoding = ScrollEventPhaseEncoder.encode(command: command)
        return (
            scroll: phaseValue(for: encoding.scrollPhase),
            momentum: phaseValue(for: encoding.momentumPhase)
        )
    }

    private func phaseValue(for phase: GesturePhase?) -> Int64 {
        guard let phase else {
            return 0
        }
        switch phase {
        case .began:
            return Int64(NSEvent.Phase.began.rawValue)
        case .changed, .momentum:
            return Int64(NSEvent.Phase.changed.rawValue)
        case .ended:
            return Int64(NSEvent.Phase.ended.rawValue)
        case .cancelled:
            return Int64(NSEvent.Phase.cancelled.rawValue)
        }
    }

    private func quantize(_ value: Double) -> Int32 {
        let rounded = value.rounded()
        if rounded > Double(Int32.max) {
            return Int32.max
        }
        if rounded < Double(Int32.min) {
            return Int32.min
        }
        return Int32(rounded)
    }
}

public struct DiagnosticEventPostResult: Equatable {
    public var generatedEventCount: Int
    public var failedEventCreationCount: Int

    public init(generatedEventCount: Int, failedEventCreationCount: Int) {
        self.generatedEventCount = generatedEventCount
        self.failedEventCreationCount = failedEventCreationCount
    }
}

public enum ScrollPostMode: Equatable {
    case free
    case horizontal
    case forcedHorizontal(sign: Int)

    public func deltas(for command: GestureCommand) -> (x: Double, y: Double) {
        switch self {
        case .free:
            return (normalizeZero(command.deltaX), normalizeZero(command.deltaY))
        case .horizontal:
            let x = command.deltaX != 0 ? command.deltaX : command.deltaY
            return (normalizeZero(x), 0)
        case let .forcedHorizontal(sign):
            let magnitude = max(abs(command.deltaX), abs(command.deltaY))
            return (normalizeZero(Double(sign) * magnitude), 0)
        }
    }

    private func normalizeZero(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }
}
