import Foundation

public struct TrackpadOutputSessionID: Codable, Comparable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TrackpadOutputSessionID, rhs: TrackpadOutputSessionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum TrackpadOutputSessionSequenceError: Error, Equatable, Sendable {
    case exhausted
}

public final class TrackpadOutputSessionSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var nextRawValue: UInt64?

    public init(startingAt: UInt64 = 1) {
        nextRawValue = startingAt
    }

    public func next() throws -> TrackpadOutputSessionID {
        lock.lock()
        defer { lock.unlock() }

        guard let rawValue = nextRawValue else {
            throw TrackpadOutputSessionSequenceError.exhausted
        }

        nextRawValue = rawValue == UInt64.max ? nil : rawValue + 1
        return TrackpadOutputSessionID(rawValue: rawValue)
    }
}

public enum TrackpadOutputEventFamily: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case scroll
    case dockSwipe
    case navigationSwipe
    case magnification
}

public enum TrackpadOutputInputPhase: String, Codable, Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
}

public enum TrackpadOutputMomentumPhase: String, Codable, Equatable, Sendable {
    case began
    case continued
    case ended
}

public enum TrackpadOutputContinuation: String, Codable, Equatable, Sendable {
    case complete
    case momentum
}

public enum TrackpadOutputTerminalDecision: String, Codable, Equatable, Sendable {
    case commit
    case cancel
}

public enum TrackpadOutputAxis: String, Codable, Equatable, Sendable {
    case horizontal
    case vertical
}

public enum TrackpadOutputNavigationDirection: String, Codable, Equatable, Sendable {
    case left
    case right
}

public enum TrackpadOutputCancellationReason: String, Codable, Equatable, Sendable {
    case inputLifecycle
    case killSwitch
    case runtimeStop
    case systemSleep
    case deviceDisconnected
    case permissionChanged
    case outputFailure
}

public enum TrackpadOutputPayload: Codable, Equatable, Sendable {
    case scroll(deltaX: Double, deltaY: Double, velocityX: Double, velocityY: Double)
    case dockSwipe(axis: TrackpadOutputAxis, progress: Double, velocity: Double)
    case navigationSwipe(direction: TrackpadOutputNavigationDirection, progress: Double, velocity: Double)
    case magnification(progress: Double, scaleDelta: Double, velocity: Double)

    public var family: TrackpadOutputEventFamily {
        switch self {
        case .scroll:
            .scroll
        case .dockSwipe:
            .dockSwipe
        case .navigationSwipe:
            .navigationSwipe
        case .magnification:
            .magnification
        }
    }

    var hasOnlyFiniteValues: Bool {
        scalarValues.allSatisfy(\.isFinite)
    }

    private var scalarValues: [Double] {
        switch self {
        case let .scroll(deltaX, deltaY, velocityX, velocityY):
            [deltaX, deltaY, velocityX, velocityY]
        case let .dockSwipe(_, progress, velocity),
             let .navigationSwipe(_, progress, velocity):
            [progress, velocity]
        case let .magnification(progress, scaleDelta, velocity):
            [progress, scaleDelta, velocity]
        }
    }
}

public struct TrackpadOutputInputFrame: Codable, Equatable, Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let captureOrder: UInt64
    public let timestamp: MonotonicEventTimestamp
    public let phase: TrackpadOutputInputPhase
    public let continuation: TrackpadOutputContinuation?
    public let terminalDecision: TrackpadOutputTerminalDecision?
    public let payload: TrackpadOutputPayload

    public init(
        sessionID: TrackpadOutputSessionID,
        captureOrder: UInt64,
        timestamp: MonotonicEventTimestamp,
        phase: TrackpadOutputInputPhase,
        continuation: TrackpadOutputContinuation? = nil,
        terminalDecision: TrackpadOutputTerminalDecision? = nil,
        payload: TrackpadOutputPayload
    ) {
        self.sessionID = sessionID
        self.captureOrder = captureOrder
        self.timestamp = timestamp
        self.phase = phase
        self.continuation = continuation
        self.terminalDecision = terminalDecision
        self.payload = payload
    }
}

public struct TrackpadOutputMomentumFrame: Codable, Equatable, Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let captureOrder: UInt64
    public let timestamp: MonotonicEventTimestamp
    public let phase: TrackpadOutputMomentumPhase
    public let payload: TrackpadOutputPayload

    public init(
        sessionID: TrackpadOutputSessionID,
        captureOrder: UInt64,
        timestamp: MonotonicEventTimestamp,
        phase: TrackpadOutputMomentumPhase,
        payload: TrackpadOutputPayload
    ) {
        self.sessionID = sessionID
        self.captureOrder = captureOrder
        self.timestamp = timestamp
        self.phase = phase
        self.payload = payload
    }
}

public struct TrackpadOutputCancellationFrame: Codable, Equatable, Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let captureOrder: UInt64
    public let timestamp: MonotonicEventTimestamp
    public let family: TrackpadOutputEventFamily
    public let reason: TrackpadOutputCancellationReason
    public let payload: TrackpadOutputPayload?

    public init(
        sessionID: TrackpadOutputSessionID,
        captureOrder: UInt64,
        timestamp: MonotonicEventTimestamp,
        family: TrackpadOutputEventFamily,
        reason: TrackpadOutputCancellationReason,
        payload: TrackpadOutputPayload?
    ) {
        self.sessionID = sessionID
        self.captureOrder = captureOrder
        self.timestamp = timestamp
        self.family = family
        self.reason = reason
        self.payload = payload
    }
}

public enum TrackpadOutputSessionEvent: Codable, Equatable, Sendable {
    case input(TrackpadOutputInputFrame)
    case momentum(TrackpadOutputMomentumFrame)
    case cancellation(TrackpadOutputCancellationFrame)

    public var sessionID: TrackpadOutputSessionID {
        switch self {
        case let .input(frame):
            frame.sessionID
        case let .momentum(frame):
            frame.sessionID
        case let .cancellation(frame):
            frame.sessionID
        }
    }

    public var captureOrder: UInt64 {
        switch self {
        case let .input(frame):
            frame.captureOrder
        case let .momentum(frame):
            frame.captureOrder
        case let .cancellation(frame):
            frame.captureOrder
        }
    }

    public var timestamp: MonotonicEventTimestamp {
        switch self {
        case let .input(frame):
            frame.timestamp
        case let .momentum(frame):
            frame.timestamp
        case let .cancellation(frame):
            frame.timestamp
        }
    }

    public var family: TrackpadOutputEventFamily {
        switch self {
        case let .input(frame):
            frame.payload.family
        case let .momentum(frame):
            frame.payload.family
        case let .cancellation(frame):
            frame.family
        }
    }

    var payloadForValidation: TrackpadOutputPayload? {
        switch self {
        case let .input(frame):
            frame.payload
        case let .momentum(frame):
            frame.payload
        case let .cancellation(frame):
            frame.payload
        }
    }
}

public enum TrackpadOutputSessionTerminalKind: String, Codable, Equatable, Sendable {
    case inputEnded
    case inputCancelled
    case momentumEnded
    case sessionCancelled
}

public struct TrackpadOutputSessionTerminal: Codable, Equatable, Sendable {
    public let kind: TrackpadOutputSessionTerminalKind
    public let decision: TrackpadOutputTerminalDecision?
    public let cancellationReason: TrackpadOutputCancellationReason?
    public let finalPayload: TrackpadOutputPayload?

    public init(
        kind: TrackpadOutputSessionTerminalKind,
        decision: TrackpadOutputTerminalDecision?,
        cancellationReason: TrackpadOutputCancellationReason? = nil,
        finalPayload: TrackpadOutputPayload? = nil
    ) {
        self.kind = kind
        self.decision = decision
        self.cancellationReason = cancellationReason
        self.finalPayload = finalPayload
    }
}

public enum TrackpadOutputSessionState: Equatable, Sendable {
    case awaitingInput
    case inputActive
    case awaitingMomentum
    case momentumActive
    case terminal(TrackpadOutputSessionTerminal)
}

public enum TrackpadOutputSessionEventKind: Equatable, Sendable {
    case input(TrackpadOutputInputPhase)
    case momentum(TrackpadOutputMomentumPhase)
    case cancellation(TrackpadOutputCancellationReason)
}

public enum TrackpadOutputSessionError: Error, Equatable, Sendable {
    case sessionIDMismatch(expected: TrackpadOutputSessionID, actual: TrackpadOutputSessionID)
    case familyMismatch(expected: TrackpadOutputEventFamily, actual: TrackpadOutputEventFamily)
    case invalidCaptureOrder(expected: UInt64, actual: UInt64)
    case captureOrderExceedsLimit(maximum: UInt64, actual: UInt64)
    case captureOrderExhaustedBeforeTerminal(maximum: UInt64)
    case timestampRegression(previous: MonotonicEventTimestamp, actual: MonotonicEventTimestamp)
    case timestampOutsideCurrentBoot(actual: MonotonicEventTimestamp, current: MonotonicEventTimestamp)
    case nonFinitePayload
    case invalidInputMetadata(phase: TrackpadOutputInputPhase)
    case cancellationPayloadRequired(state: TrackpadOutputSessionState)
    case momentumRequiresScroll(actual: TrackpadOutputEventFamily)
    case invalidTransition(state: TrackpadOutputSessionState, event: TrackpadOutputSessionEventKind)
    case terminalAlreadyReached(TrackpadOutputSessionTerminal)
    case sessionIncomplete(TrackpadOutputSessionState)
}

public struct TrackpadOutputSessionMachine: Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let family: TrackpadOutputEventFamily
    public private(set) var state: TrackpadOutputSessionState = .awaitingInput
    public private(set) var lastCaptureOrder: UInt64?
    public private(set) var lastTimestamp: MonotonicEventTimestamp?
    public private(set) var lastPayload: TrackpadOutputPayload?
    private let maximumCaptureOrder: UInt64

    public init(
        sessionID: TrackpadOutputSessionID,
        family: TrackpadOutputEventFamily,
        maximumCaptureOrder: UInt64 = UInt64.max
    ) {
        self.sessionID = sessionID
        self.family = family
        self.maximumCaptureOrder = maximumCaptureOrder
    }

    public mutating func accept(_ event: TrackpadOutputSessionEvent) throws {
        if case let .terminal(terminal) = state {
            throw TrackpadOutputSessionError.terminalAlreadyReached(terminal)
        }

        try validateIdentityAndOrdering(event)
        try validatePayload(event)
        let nextState = try transition(for: event)
        if event.captureOrder == maximumCaptureOrder {
            guard case .terminal = nextState else {
                throw TrackpadOutputSessionError.captureOrderExhaustedBeforeTerminal(
                    maximum: maximumCaptureOrder
                )
            }
        }

        state = nextState
        lastCaptureOrder = event.captureOrder
        lastTimestamp = event.timestamp
        if let payload = event.payloadForValidation {
            lastPayload = payload
        }
    }

    public func requireTerminal() throws -> TrackpadOutputSessionTerminal {
        guard case let .terminal(terminal) = state else {
            throw TrackpadOutputSessionError.sessionIncomplete(state)
        }
        return terminal
    }

    private func validateIdentityAndOrdering(_ event: TrackpadOutputSessionEvent) throws {
        guard event.sessionID == sessionID else {
            throw TrackpadOutputSessionError.sessionIDMismatch(expected: sessionID, actual: event.sessionID)
        }
        guard event.family == family else {
            throw TrackpadOutputSessionError.familyMismatch(expected: family, actual: event.family)
        }
        guard event.captureOrder <= maximumCaptureOrder else {
            throw TrackpadOutputSessionError.captureOrderExceedsLimit(
                maximum: maximumCaptureOrder,
                actual: event.captureOrder
            )
        }

        let expectedCaptureOrder: UInt64
        if let lastCaptureOrder {
            let increment = lastCaptureOrder.addingReportingOverflow(1)
            guard !increment.overflow else {
                throw TrackpadOutputSessionError.captureOrderExhaustedBeforeTerminal(
                    maximum: maximumCaptureOrder
                )
            }
            expectedCaptureOrder = increment.partialValue
        } else {
            expectedCaptureOrder = 0
        }
        guard event.captureOrder == expectedCaptureOrder else {
            throw TrackpadOutputSessionError.invalidCaptureOrder(
                expected: expectedCaptureOrder,
                actual: event.captureOrder
            )
        }

        if let lastTimestamp, event.timestamp < lastTimestamp {
            throw TrackpadOutputSessionError.timestampRegression(previous: lastTimestamp, actual: event.timestamp)
        }
        let currentTimestamp = MonotonicEventClock.now
        guard event.timestamp <= currentTimestamp else {
            throw TrackpadOutputSessionError.timestampOutsideCurrentBoot(
                actual: event.timestamp,
                current: currentTimestamp
            )
        }
    }

    private func validatePayload(_ event: TrackpadOutputSessionEvent) throws {
        if let payload = event.payloadForValidation, !payload.hasOnlyFiniteValues {
            throw TrackpadOutputSessionError.nonFinitePayload
        }

        switch event {
        case let .input(frame):
            try validateInputFrame(frame)
        case .momentum:
            guard family == .scroll else {
                throw TrackpadOutputSessionError.momentumRequiresScroll(actual: family)
            }
        case let .cancellation(frame):
            if let payload = frame.payload, payload.family != frame.family {
                throw TrackpadOutputSessionError.familyMismatch(
                    expected: frame.family,
                    actual: payload.family
                )
            }
            if state != .awaitingInput, frame.payload == nil {
                throw TrackpadOutputSessionError.cancellationPayloadRequired(state: state)
            }
        }
    }

    private func validateInputFrame(_ frame: TrackpadOutputInputFrame) throws {
        switch frame.phase {
        case .began, .changed:
            guard frame.continuation == nil, frame.terminalDecision == nil else {
                throw TrackpadOutputSessionError.invalidInputMetadata(phase: frame.phase)
            }
        case .ended:
            guard let continuation = frame.continuation else {
                throw TrackpadOutputSessionError.invalidInputMetadata(phase: frame.phase)
            }
            if family == .scroll {
                guard frame.terminalDecision == nil else {
                    throw TrackpadOutputSessionError.invalidInputMetadata(phase: frame.phase)
                }
            } else {
                guard continuation == .complete, frame.terminalDecision != nil else {
                    throw TrackpadOutputSessionError.invalidInputMetadata(phase: frame.phase)
                }
            }
        case .cancelled:
            guard frame.continuation == nil else {
                throw TrackpadOutputSessionError.invalidInputMetadata(phase: frame.phase)
            }
            if family == .scroll {
                guard frame.terminalDecision == nil else {
                    throw TrackpadOutputSessionError.invalidInputMetadata(phase: frame.phase)
                }
            } else {
                guard frame.terminalDecision == .cancel else {
                    throw TrackpadOutputSessionError.invalidInputMetadata(phase: frame.phase)
                }
            }
        }
    }

    private func transition(for event: TrackpadOutputSessionEvent) throws -> TrackpadOutputSessionState {
        let eventKind = kind(of: event)

        switch (state, event) {
        case (.awaitingInput, let .input(frame)) where frame.phase == .began:
            return .inputActive
        case (.inputActive, let .input(frame)) where frame.phase == .changed:
            return .inputActive
        case (.inputActive, let .input(frame)) where frame.phase == .ended:
            if frame.continuation == .momentum {
                return .awaitingMomentum
            }
            return .terminal(
                TrackpadOutputSessionTerminal(
                    kind: .inputEnded,
                    decision: frame.terminalDecision,
                    finalPayload: frame.payload
                )
            )
        case (.inputActive, let .input(frame)) where frame.phase == .cancelled:
            return .terminal(
                TrackpadOutputSessionTerminal(
                    kind: .inputCancelled,
                    decision: frame.terminalDecision,
                    cancellationReason: .inputLifecycle,
                    finalPayload: frame.payload
                )
            )
        case (.awaitingMomentum, let .momentum(frame)) where frame.phase == .began:
            return .momentumActive
        case (.momentumActive, let .momentum(frame)) where frame.phase == .continued:
            return .momentumActive
        case (.momentumActive, let .momentum(frame)) where frame.phase == .ended:
            return .terminal(
                TrackpadOutputSessionTerminal(
                    kind: .momentumEnded,
                    decision: nil,
                    finalPayload: frame.payload
                )
            )
        case (_, let .cancellation(frame)):
            return .terminal(
                TrackpadOutputSessionTerminal(
                    kind: .sessionCancelled,
                    decision: .cancel,
                    cancellationReason: frame.reason,
                    finalPayload: frame.payload
                )
            )
        default:
            throw TrackpadOutputSessionError.invalidTransition(state: state, event: eventKind)
        }
    }

    private func kind(of event: TrackpadOutputSessionEvent) -> TrackpadOutputSessionEventKind {
        switch event {
        case let .input(frame):
            .input(frame.phase)
        case let .momentum(frame):
            .momentum(frame.phase)
        case let .cancellation(frame):
            .cancellation(frame.reason)
        }
    }
}
