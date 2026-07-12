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
        case .input(let frame):
            payload = frame.payload
            switch frame.phase {
            case .began: phase = 1
            case .changed: phase = 2
            case .ended: phase = 4
            case .cancelled: phase = 8
            }
        case .cancellation(let frame):
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
            eventTypeRaw = 30
            classifier = 23
        case .dockSwipePinch:
            eventTypeRaw = 30
            classifier = 23
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
    private let compatibilityAdapter: RecognizedGestureIOHIDCompatibilityAdapter

    init(
        contract: TrackpadScrollMomentumContractFixture,
        compatibilityAdapter: RecognizedGestureIOHIDCompatibilityAdapter
    ) {
        typeRawField = contract.common.typeRawField
        timestampRawField = contract.common.timestampRawField
        self.compatibilityAdapter = compatibilityAdapter
    }

    func makeEvent(
        from specification: TrackpadGestureCandidatePreparedEvent,
        polarity: RecognizedDockSwipeTemplatePolarity
    ) -> CGEvent? {
        guard TrackpadScrollCGEventBuilder.supportsRawFieldLayout else {
            return nil
        }

        let recognizedPayload: RecognizedGestureIOHIDPayload
        switch specification.payload {
        case let .dockSwipe(
            axis,
            progress,
            motionX,
            motionY,
            terminalVelocityX,
            terminalVelocityY
        ):
            recognizedPayload = .dockSwipe(
                motion: axis == .horizontal ? 1 : 2,
                phase: specification.phase,
                progress: progress,
                positionX: motionX,
                positionY: motionY,
                terminalVelocityX: terminalVelocityX,
                terminalVelocityY: terminalVelocityY,
                terminalVelocityZ: 0
            )
        case let .dockSwipePinch(progress, _, terminalVelocity):
            recognizedPayload = .dockSwipe(
                motion: 4,
                phase: specification.phase,
                progress: progress,
                positionX: 0,
                positionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0,
                terminalVelocityZ: terminalVelocity
            )
        case .scroll:
            return nil
        }

        guard let event = compatibilityAdapter.makeEvent(
            payload: recognizedPayload,
            timestamp: specification.timestamp,
            polarity: polarity
        )
        else {
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

    private func rawField(_ number: Int) -> CGEventField {
        unsafeBitCast(UInt32(number), to: CGEventField.self)
    }
}
