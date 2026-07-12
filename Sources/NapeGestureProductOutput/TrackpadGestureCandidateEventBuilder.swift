import CoreGraphics
import Foundation
import NapeGestureCore

public struct TrackpadGestureCandidatePreparedEvent: Sendable {
    public let eventTypeRaw: Int
    public let classifier: Int64
    public let phase: Int64
    public let timestamp: MonotonicEventTimestamp
    public let payload: TrackpadOutputPayload

    public init?(_ event: TrackpadOutputSessionEvent) {
        let phase: Int64
        let payload: TrackpadOutputPayload
        switch event {
        case let .input(frame):
            payload = frame.payload
            switch frame.phase {
            case .began: phase = 1
            case .changed: phase = 2
            case .ended: phase = 4
            case .cancelled: phase = 8
            }
        case let .cancellation(frame):
            guard let cancellationPayload = frame.payload else {
                return nil
            }
            payload = cancellationPayload
            phase = 8
        case .momentum:
            return nil
        }

        switch payload {
        case .dockSwipe:
            eventTypeRaw = 29
            classifier = 32
        case .navigationSwipe:
            eventTypeRaw = 30
            classifier = 23
        case .magnification:
            eventTypeRaw = 29
            classifier = 8
        case .scroll:
            return nil
        }
        self.phase = phase
        timestamp = event.timestamp
        self.payload = payload
    }
}

public final class TrackpadGestureCandidateCGEventBuilder {
    private let typeRawField: Int
    private let timestampRawField: Int
    private let baseEventFactory: ProductBaseEventFactory

    public init(
        contract: TrackpadScrollMomentumContractFixture,
        baseEventFactory: @escaping ProductBaseEventFactory = { CGEvent(source: nil) }
    ) {
        typeRawField = contract.common.typeRawField
        timestampRawField = contract.common.timestampRawField
        self.baseEventFactory = baseEventFactory
    }

    public func makeEvent(
        from specification: TrackpadGestureCandidatePreparedEvent
    ) -> CGEvent? {
        guard TrackpadScrollCGEventBuilder.supportsRawFieldLayout,
              let event = baseEventFactory(),
              let eventType = CGEventType(rawValue: UInt32(specification.eventTypeRaw))
        else {
            return nil
        }
        event.type = eventType
        event.timestamp = CGEventTimestamp(specification.timestamp.nanosecondsSinceStartup)
        event.setIntegerValueField(.eventSourceUserData, value: NapeGestureGeneratedEventMarker.value)
        event.setIntegerValueField(
            rawField(typeRawField),
            value: Int64(specification.eventTypeRaw)
        )
        event.setIntegerValueField(
            rawField(timestampRawField),
            value: Int64(specification.timestamp.nanosecondsSinceStartup)
        )
        event.setIntegerValueField(rawField(39), value: 0)
        event.setIntegerValueField(rawField(40), value: 0)
        event.setIntegerValueField(rawField(110), value: specification.classifier)
        event.setIntegerValueField(rawField(132), value: specification.phase)

        switch specification.payload {
        case let .dockSwipe(axis, progress, velocity):
            configureDockSwipe(
                event,
                axis: axis,
                progress: terminalValue(specification.phase, progress),
                velocity: terminalValue(specification.phase, velocity)
            )
        case let .navigationSwipe(direction, progress, velocity):
            configureNavigationSwipe(
                event,
                direction: direction,
                progress: terminalValue(specification.phase, progress),
                velocity: terminalValue(specification.phase, velocity)
            )
        case let .magnification(_, scaleDelta, velocity):
            configureMagnification(
                event,
                scaleDelta: terminalValue(specification.phase, scaleDelta),
                velocity: terminalValue(specification.phase, velocity)
            )
        case .scroll:
            return nil
        }

        guard event.data != nil,
              event.type.rawValue == UInt32(specification.eventTypeRaw),
              event.getIntegerValueField(rawField(110)) == specification.classifier,
              event.getIntegerValueField(rawField(132)) == specification.phase,
              event.getIntegerValueField(rawField(39)) == 0,
              event.getIntegerValueField(rawField(40)) == 0,
              event.getIntegerValueField(rawField(typeRawField)) == specification.eventTypeRaw,
              event.getIntegerValueField(rawField(timestampRawField))
                == Int64(specification.timestamp.nanosecondsSinceStartup),
              event.getIntegerValueField(.eventSourceUserData)
                == NapeGestureGeneratedEventMarker.value
        else {
            return nil
        }
        return event
    }

    private func configureDockSwipe(
        _ event: CGEvent,
        axis: TrackpadOutputAxis,
        progress: Double,
        velocity: Double
    ) {
        for field in [119, 139, 148] {
            event.setDoubleValueField(rawField(field), value: progress)
        }
        let progressBits = Float(progress).bitPattern
        for field in [123, 165] {
            event.setIntegerValueField(rawField(field), value: Int64(UInt64(progressBits)))
        }
        event.setIntegerValueField(rawField(143), value: progress == 0 ? 0 : 1)
        event.setIntegerValueField(rawField(144), value: 5)
        event.setDoubleValueField(rawField(125), value: axis == .horizontal ? velocity : 0)
        event.setDoubleValueField(rawField(126), value: axis == .vertical ? velocity : 0)
    }

    private func configureNavigationSwipe(
        _ event: CGEvent,
        direction: TrackpadOutputNavigationDirection,
        progress: Double,
        velocity: Double
    ) {
        let sign = direction == .left ? -1.0 : 1.0
        let signedProgress = abs(progress) * sign
        let signedVelocity = abs(velocity) * sign
        event.setIntegerValueField(rawField(134), value: event.getIntegerValueField(rawField(132)))
        event.setDoubleValueField(rawField(124), value: signedProgress)
        event.setDoubleValueField(rawField(125), value: signedVelocity)
        event.setDoubleValueField(rawField(126), value: 0)
        event.setIntegerValueField(
            rawField(135),
            value: Int64(UInt64(Float(signedProgress).bitPattern))
        )
        event.setDoubleValueField(rawField(129), value: signedVelocity)
        event.setDoubleValueField(rawField(130), value: 0)
    }

    private func configureMagnification(
        _ event: CGEvent,
        scaleDelta: Double,
        velocity: Double
    ) {
        for field in [113, 114, 116, 118] {
            event.setDoubleValueField(rawField(field), value: scaleDelta)
        }
        let scaleBits = Float(scaleDelta).bitPattern
        for field in [115, 117, 164] {
            event.setIntegerValueField(rawField(field), value: Int64(UInt64(scaleBits)))
        }
        event.setDoubleValueField(rawField(119), value: velocity)
    }

    private func terminalValue(_ phase: Int64, _ value: Double) -> Double {
        phase == 4 || phase == 8 ? 0 : value
    }

    private func rawField(_ number: Int) -> CGEventField {
        unsafeBitCast(UInt32(number), to: CGEventField.self)
    }
}
