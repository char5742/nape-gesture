import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore

final class EventPoster {
    private let source: CGEventSource?

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
    }

    @discardableResult
    func postScroll(command: GestureCommand, mode: ScrollPostMode, to pid: pid_t? = nil) -> EventPostResult {
        guard let event = makeScrollEvent(command: command, mode: mode) else {
            return EventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }
        post(event, to: pid)
        return EventPostResult(generatedEventCount: 1, failedEventCreationCount: 0)
    }

    func makeScrollEvent(command: GestureCommand, mode: ScrollPostMode) -> CGEvent? {
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

        CGEventUtilities.setGeneratedMarker(on: event)
        let phases = CGEventUtilities.phaseValues(for: command)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phases.scroll)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phases.momentum)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)

        event.timestamp = CGEventTimestamp(max(command.timestamp, 0) * 1_000_000_000)
        return event
    }

    @discardableResult
    func postMissionControl() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl)
    }

    @discardableResult
    func postPageBack() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand)
    }

    @discardableResult
    func postPageForward() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand)
    }

    @discardableResult
    func postZoomIn() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand)
    }

    @discardableResult
    func postZoomOut() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand)
    }

    private func postKeyShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> EventPostResult {
        let events = [
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        ].compactMap { $0 }

        for event in events {
            CGEventUtilities.setGeneratedMarker(on: event)
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }

        return EventPostResult(
            generatedEventCount: events.count,
            failedEventCreationCount: 2 - events.count
        )
    }

    private func post(_ event: CGEvent, to pid: pid_t?) {
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
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

struct EventPostResult: Equatable {
    var generatedEventCount: Int
    var failedEventCreationCount: Int

    static let none = EventPostResult(generatedEventCount: 0, failedEventCreationCount: 0)
}

enum ScrollPostMode: Equatable {
    case free
    case horizontal
    case forcedHorizontal(sign: Int)

    func deltas(for command: GestureCommand) -> (x: Double, y: Double) {
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
