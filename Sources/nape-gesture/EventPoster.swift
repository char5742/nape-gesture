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
    func postScroll(command: GestureCommand, mode: ScrollPostMode) -> EventPostResult {
        guard let event = makeScrollEvent(command: command, mode: mode) else {
            return EventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }
        if let pid = targetProcessID(for: mode) {
            event.postToPid(pid)
        } else {
            event.post(tap: postTap(for: mode))
        }
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
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltas.y)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: deltas.x)
        let pointerLocation = currentPointerLocation()
        event.location = pointerLocation
        if let target = windowTargetUnderPointer(at: pointerLocation) {
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointer,
                value: Int64(target.windowNumber)
            )
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                value: Int64(target.windowNumber)
            )
        }

        event.timestamp = CGEventTimestamp(max(command.timestamp, 0) * 1_000_000_000)
        return event
    }

    @discardableResult
    func postMissionControl() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl)
    }

    @discardableResult
    func postPageBack() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_LeftBracket), flags: .maskCommand)
    }

    @discardableResult
    func postPageForward() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_RightBracket), flags: .maskCommand)
    }

    @discardableResult
    func postZoomIn() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: [.maskCommand, .maskShift])
    }

    @discardableResult
    func postZoomOut() -> EventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand)
    }

    private func postKeyShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> EventPostResult {
        let sequence = ShortcutEventSequence.keyEvents(keyCode: keyCode, flags: flags)
        let rawEvents = sequence.map { shortcutEvent in
            makeKeyEvent(
                keyCode: shortcutEvent.keyCode,
                keyDown: shortcutEvent.isKeyDown,
                flags: shortcutEvent.flags
            )
        }
        guard rawEvents.allSatisfy({ $0 != nil }) else {
            return EventPostResult(
                generatedEventCount: 0,
                failedEventCreationCount: rawEvents.filter { $0 == nil }.count
            )
        }
        let events = rawEvents.compactMap { $0 }

        for (index, event) in events.enumerated() {
            CGEventUtilities.setGeneratedMarker(on: event)
            event.post(tap: .cgSessionEventTap)
            if index < events.count - 1 {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }

        return EventPostResult(
            generatedEventCount: events.count,
            failedEventCreationCount: rawEvents.count - events.count
        )
    }

    private func makeKeyEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
        event?.flags = flags
        return event
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

    private func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func postTap(for mode: ScrollPostMode) -> CGEventTapLocation {
        switch mode {
        case .free, .horizontal:
            return .cgSessionEventTap
        case .forcedHorizontal:
            return .cghidEventTap
        }
    }

    private func targetProcessID(for mode: ScrollPostMode) -> pid_t? {
        switch mode {
        case .free, .horizontal:
            return windowTargetUnderPointer(at: currentPointerLocation())?.processID
                ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        case .forcedHorizontal:
            return nil
        }
    }

    private func windowTargetUnderPointer(at point: CGPoint) -> WindowTarget? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let descriptions = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for description in descriptions {
            guard let layer = description[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let ownerPID = pidValue(description[kCGWindowOwnerPID as String]),
                  let windowNumber = windowNumberValue(description[kCGWindowNumber as String]),
                  let bounds = description[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.contains(point)
            else {
                continue
            }
            return WindowTarget(processID: ownerPID, windowNumber: windowNumber)
        }

        return nil
    }

    private func pidValue(_ raw: Any?) -> pid_t? {
        if let value = raw as? pid_t {
            return value
        }
        if let value = raw as? Int {
            return pid_t(value)
        }
        return nil
    }

    private func windowNumberValue(_ raw: Any?) -> UInt32? {
        if let value = raw as? UInt32 {
            return value
        }
        if let value = raw as? Int, value >= 0 {
            return UInt32(value)
        }
        return nil
    }
}

private struct WindowTarget {
    var processID: pid_t
    var windowNumber: UInt32
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
