import Foundation

public struct FixedGestureSessionTerminal: Codable, Equatable, Sendable {
    public let phase: FixedGestureInputPhase
    public let captureOrder: UInt64
    public let timestamp: MonotonicEventTimestamp

    public init(
        phase: FixedGestureInputPhase,
        captureOrder: UInt64,
        timestamp: MonotonicEventTimestamp
    ) {
        self.phase = phase
        self.captureOrder = captureOrder
        self.timestamp = timestamp
    }
}

public enum FixedGestureSessionState: Equatable, Sendable {
    case awaitingBegin
    case active
    case terminal(FixedGestureSessionTerminal)
}

public enum FixedGestureSessionError: Error, Equatable, Sendable {
    case terminalAlreadyReached(FixedGestureSessionTerminal)
    case sessionIDMismatch(expected: TrackpadOutputSessionID, actual: TrackpadOutputSessionID)
    case sourceButtonMismatch(expected: MouseButton, actual: MouseButton)
    case gestureClassMismatch(expected: FixedGestureClass, actual: FixedGestureClass)
    case captureOrderMismatch(expected: UInt64, actual: UInt64)
    case timestampRegression(
        previous: MonotonicEventTimestamp,
        actual: MonotonicEventTimestamp
    )
    case nonFiniteDelta
    case invalidBegin
    case invalidChange
    case invalidTerminal
    case incomplete(FixedGestureSessionState)
}

public struct FixedGestureSessionMachine: Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let sourceButton: MouseButton
    public let gestureClass: FixedGestureClass
    public private(set) var state: FixedGestureSessionState = .awaitingBegin
    public private(set) var lastCaptureOrder: UInt64?
    public private(set) var lastTimestamp: MonotonicEventTimestamp?

    public var isTerminal: Bool {
        if case .terminal = state {
            return true
        }
        return false
    }

    public init(
        sessionID: TrackpadOutputSessionID,
        sourceButton: MouseButton,
        gestureClass: FixedGestureClass
    ) {
        self.sessionID = sessionID
        self.sourceButton = sourceButton
        self.gestureClass = gestureClass
    }

    public mutating func accept(_ command: FixedGestureInputCommand) throws {
        if case let .terminal(terminal) = state {
            throw FixedGestureSessionError.terminalAlreadyReached(terminal)
        }
        guard command.sessionID == sessionID else {
            throw FixedGestureSessionError.sessionIDMismatch(
                expected: sessionID,
                actual: command.sessionID
            )
        }
        guard command.sourceButton == sourceButton else {
            throw FixedGestureSessionError.sourceButtonMismatch(
                expected: sourceButton,
                actual: command.sourceButton
            )
        }
        guard command.gestureClass == gestureClass else {
            throw FixedGestureSessionError.gestureClassMismatch(
                expected: gestureClass,
                actual: command.gestureClass
            )
        }

        let expectedCaptureOrder: UInt64
        if let lastCaptureOrder {
            let next = lastCaptureOrder.addingReportingOverflow(1)
            guard !next.overflow else {
                throw FixedGestureSessionError.captureOrderMismatch(
                    expected: UInt64.max,
                    actual: command.captureOrder
                )
            }
            expectedCaptureOrder = next.partialValue
        } else {
            expectedCaptureOrder = 0
        }
        guard command.captureOrder == expectedCaptureOrder else {
            throw FixedGestureSessionError.captureOrderMismatch(
                expected: expectedCaptureOrder,
                actual: command.captureOrder
            )
        }
        if let lastTimestamp, command.timestamp < lastTimestamp {
            throw FixedGestureSessionError.timestampRegression(
                previous: lastTimestamp,
                actual: command.timestamp
            )
        }
        guard command.deltaX.isFinite, command.deltaY.isFinite else {
            throw FixedGestureSessionError.nonFiniteDelta
        }

        let nextState: FixedGestureSessionState
        switch (state, command.phase, command.sourceKind) {
        case (.awaitingBegin, .began, .buttonDown)
            where command.captureOrder == 0 && command.deltaX == 0 && command.deltaY == 0:
            nextState = .active
        case (.active, .changed, .move), (.active, .changed, .wheel):
            nextState = .active
        case (.active, .ended, .buttonUp)
            where command.deltaX == 0 && command.deltaY == 0:
            nextState = .terminal(
                FixedGestureSessionTerminal(
                    phase: command.phase,
                    captureOrder: command.captureOrder,
                    timestamp: command.timestamp
                )
            )
        case (.active, .cancelled, .cancellation)
            where command.deltaX == 0 && command.deltaY == 0:
            nextState = .terminal(
                FixedGestureSessionTerminal(
                    phase: command.phase,
                    captureOrder: command.captureOrder,
                    timestamp: command.timestamp
                )
            )
        case (.awaitingBegin, _, _):
            throw FixedGestureSessionError.invalidBegin
        case (.active, .changed, _):
            throw FixedGestureSessionError.invalidChange
        case (.active, _, _):
            throw FixedGestureSessionError.invalidTerminal
        case (.terminal, _, _):
            preconditionFailure("terminal stateは先頭で拒否済みです。")
        }

        state = nextState
        lastCaptureOrder = command.captureOrder
        lastTimestamp = command.timestamp
    }

    public func requireTerminal() throws -> FixedGestureSessionTerminal {
        guard case let .terminal(terminal) = state else {
            throw FixedGestureSessionError.incomplete(state)
        }
        return terminal
    }
}
