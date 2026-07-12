import AppKit
import CoreGraphics
import Foundation
import NapeGestureCore

enum CGEventUtilities {
    static let generatedEventMarker = NapeGestureGeneratedEventMarker.value

    static let observedMouseEventTypes: [CGEventType] = [
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
        .keyDown,
        .keyUp,
        .tapDisabledByTimeout,
        .tapDisabledByUserInput,
    ]

    static func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    static func rawInput(from type: CGEventType, event: CGEvent) -> RawInputEvent? {
        let timestamp = MonotonicEventClock.seconds(fromTimestampNanoseconds: event.timestamp)

        switch type {
        case .otherMouseDown:
            return RawInputEvent.otherMouseButton(
                buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                isDown: true,
                time: timestamp
            )
        case .otherMouseUp:
            return RawInputEvent.otherMouseButton(
                buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                isDown: false,
                time: timestamp
            )
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let deltaX = Double(event.getIntegerValueField(.mouseEventDeltaX))
            let deltaY = Double(event.getIntegerValueField(.mouseEventDeltaY))
            return .move(deltaX: deltaX, deltaY: deltaY, time: timestamp)
        case .scrollWheel:
            let pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let fixedDeltaX =
                pointDeltaX != 0
                ? pointDeltaX : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            let fixedDeltaY =
                pointDeltaY != 0
                ? pointDeltaY : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            return .wheel(deltaX: fixedDeltaX, deltaY: fixedDeltaY, time: timestamp)
        default:
            return nil
        }
    }

    static func fixedGestureInput(
        from type: CGEventType,
        event: CGEvent
    ) -> FixedGestureSourceInputEvent? {
        let timestamp = MonotonicEventTimestamp(
            nanosecondsSinceStartup: event.timestamp
        )

        switch type {
        case .otherMouseDown:
            guard let button = MouseButton(
                buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber)
            ) else {
                return nil
            }
            return .buttonDown(button: button, timestamp: timestamp)
        case .otherMouseUp:
            guard let button = MouseButton(
                buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber)
            ) else {
                return nil
            }
            return .buttonUp(button: button, timestamp: timestamp)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return .move(
                deltaX: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                deltaY: Double(event.getIntegerValueField(.mouseEventDeltaY)),
                timestamp: timestamp
            )
        case .scrollWheel:
            let pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let deltaX = pointDeltaX != 0
                ? pointDeltaX
                : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            let deltaY = pointDeltaY != 0
                ? pointDeltaY
                : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            return .wheel(deltaX: deltaX, deltaY: deltaY, timestamp: timestamp)
        default:
            return nil
        }
    }

    static func isGeneratedByThisTool(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == generatedEventMarker
    }

    static func setGeneratedMarker(on event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
    }

    static func phaseValue(for phase: GesturePhase) -> Int64 {
        switch phase {
        case .began:
            return Int64(NSEvent.Phase.began.rawValue)
        case .changed:
            return Int64(NSEvent.Phase.changed.rawValue)
        case .ended:
            return Int64(NSEvent.Phase.ended.rawValue)
        case .cancelled:
            return Int64(NSEvent.Phase.cancelled.rawValue)
        case .momentum:
            return Int64(NSEvent.Phase.changed.rawValue)
        }
    }

    static func phaseValue(for phase: GesturePhase?) -> Int64 {
        guard let phase else {
            return 0
        }
        return phaseValue(for: phase)
    }

    static func phaseValues(for command: GestureCommand) -> (scroll: Int64, momentum: Int64) {
        let encoding = ScrollEventPhaseEncoder.encode(command: command)
        return (
            scroll: phaseValue(for: encoding.scrollPhase),
            momentum: phaseValue(for: encoding.momentumPhase)
        )
    }
}
