import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MacGestureCore

final class EventPoster {
    private let source: CGEventSource?

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
    }

    func postScroll(command: GestureCommand, mode: ScrollPostMode) {
        guard let event = makeScrollEvent(command: command, mode: mode) else {
            return
        }
        event.post(tap: .cghidEventTap)
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

    func postMissionControl() {
        postKeyShortcut(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl)
    }

    func postPageBack() {
        postKeyShortcut(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand)
    }

    func postPageForward() {
        postKeyShortcut(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand)
    }

    func postZoomIn() {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand)
    }

    func postZoomOut() {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand)
    }

    private func postKeyShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        for event in [down, up] {
            CGEventUtilities.setGeneratedMarker(on: event)
            event.flags = flags
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
