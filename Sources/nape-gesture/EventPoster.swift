import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore

final class EventPoster {
    private static let keyReleaseDelay: TimeInterval = 0.01

    private let source: CGEventSource?

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
    }

    @discardableResult
    func postScroll(command: GestureCommand, mode: ScrollPostMode) -> EventPostResult {
        guard let event = makeScrollEvent(command: command, mode: mode) else {
            return EventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }
        event.post(tap: .cghidEventTap)
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

        guard CGEventUtilities.setMonotonicTimestamp(
            secondsSinceStartup: command.timestamp,
            on: event
        ) else {
            return nil
        }
        return event
    }

    @discardableResult
    func postMissionControl(timestamp: TimeInterval) -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl, timestamp: timestamp)
    }

    @discardableResult
    func postPageBack(timestamp: TimeInterval) -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand, timestamp: timestamp)
    }

    @discardableResult
    func postPageForward(timestamp: TimeInterval) -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand, timestamp: timestamp)
    }

    @discardableResult
    func postZoomIn(timestamp: TimeInterval) -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand, timestamp: timestamp)
    }

    @discardableResult
    func postZoomOut(timestamp: TimeInterval) -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand, timestamp: timestamp)
    }

    private func postKeyShortcut(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        timestamp: TimeInterval
    ) -> EventPostResult {
        let eventSpecifications = [
            (keyDown: true, timestamp: timestamp),
            (keyDown: false, timestamp: timestamp + Self.keyReleaseDelay)
        ]
        let events = eventSpecifications.compactMap { specification -> CGEvent? in
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: specification.keyDown
            ), CGEventUtilities.setMonotonicTimestamp(
                secondsSinceStartup: specification.timestamp,
                on: event
            ) else {
                return nil
            }
            return event
        }

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
