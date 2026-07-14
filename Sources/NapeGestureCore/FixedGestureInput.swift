import Foundation

public enum FixedGestureClass: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case twoFingerScrollSwipe
    case threeFingerSystemSwipe
    case pinch

    public var displayName: String {
        switch self {
        case .twoFingerScrollSwipe: "2本指スクロール／スワイプ"
        case .threeFingerSystemSwipe: "3本指システムスワイプ"
        case .pinch: "4本指システムピンチ"
        }
    }

    public var legacyMode: TrackpadGestureMode {
        switch self {
        case .twoFingerScrollSwipe: .twoFingerSwipe
        case .threeFingerSystemSwipe: .systemSwipe
        case .pinch: .pinch
        }
    }
}

public struct GestureButtonAssignments: Codable, Equatable, Sendable {
    public var button3: FixedGestureClass
    public var button4: FixedGestureClass
    public var button5: FixedGestureClass

    public init(
        button3: FixedGestureClass = .twoFingerScrollSwipe,
        button4: FixedGestureClass = .threeFingerSystemSwipe,
        button5: FixedGestureClass = .pinch
    ) {
        self.button3 = button3
        self.button4 = button4
        self.button5 = button5
    }

    public static let `default` = GestureButtonAssignments()

    public static let supportedSourceButtons: Set<MouseButton> = [
        .button3,
        .button4,
        .center,
    ]

    public func assignment(for sourceButton: MouseButton) -> FixedGestureClass? {
        switch sourceButton {
        case .button3:
            button3
        case .button4:
            button4
        case .center:
            button5
        case .left, .right, .button5:
            nil
        }
    }

    public func assignment(forLogicalButtonNumber buttonNumber: Int) -> FixedGestureClass? {
        switch buttonNumber {
        case 3: button3
        case 4: button4
        case 5: button5
        default: nil
        }
    }
}

public enum GestureInputSourceKind: String, Codable, Equatable, Sendable {
    case buttonDown
    case move
    case wheel
    case buttonUp
    case cancellation
}

public enum FixedGestureInputPhase: String, Codable, Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
}

public enum FixedGestureSourceInputEvent: Equatable, Sendable {
    case buttonDown(button: MouseButton, timestamp: MonotonicEventTimestamp)
    case buttonUp(button: MouseButton, timestamp: MonotonicEventTimestamp)
    case move(deltaX: Double, deltaY: Double, timestamp: MonotonicEventTimestamp)
    case wheel(deltaX: Double, deltaY: Double, timestamp: MonotonicEventTimestamp)
    case cancel(timestamp: MonotonicEventTimestamp)

    public var timestamp: MonotonicEventTimestamp {
        switch self {
        case .buttonDown(_, let timestamp),
             .buttonUp(_, let timestamp),
             .move(_, _, let timestamp),
             .wheel(_, _, let timestamp),
             .cancel(let timestamp):
            timestamp
        }
    }
}

public struct FixedGestureInputCommand: Codable, Equatable, Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let sourceButton: MouseButton
    public let gestureClass: FixedGestureClass
    public let captureOrder: UInt64
    public let timestamp: MonotonicEventTimestamp
    public let sourceKind: GestureInputSourceKind
    public let phase: FixedGestureInputPhase
    public let deltaX: Double
    public let deltaY: Double

    public init(
        sessionID: TrackpadOutputSessionID,
        sourceButton: MouseButton,
        gestureClass: FixedGestureClass,
        captureOrder: UInt64,
        timestamp: MonotonicEventTimestamp,
        sourceKind: GestureInputSourceKind,
        phase: FixedGestureInputPhase,
        deltaX: Double,
        deltaY: Double
    ) {
        self.sessionID = sessionID
        self.sourceButton = sourceButton
        self.gestureClass = gestureClass
        self.captureOrder = captureOrder
        self.timestamp = timestamp
        self.sourceKind = sourceKind
        self.phase = phase
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public enum FixedGestureRecognitionFailure: Error, Equatable, Sendable {
    case sessionSequenceExhausted
    case captureOrderExhausted
    case timestampRegression(
        previous: MonotonicEventTimestamp,
        actual: MonotonicEventTimestamp
    )
}

public struct FixedGestureInputDecision: Equatable, Sendable {
    public let commands: [FixedGestureInputCommand]
    public let shouldSuppressOriginal: Bool
    public let failure: FixedGestureRecognitionFailure?

    public init(
        commands: [FixedGestureInputCommand] = [],
        shouldSuppressOriginal: Bool,
        failure: FixedGestureRecognitionFailure? = nil
    ) {
        self.commands = commands
        self.shouldSuppressOriginal = shouldSuppressOriginal
        self.failure = failure
    }
}

public struct ActiveFixedGestureInputSession: Equatable, Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let sourceButton: MouseButton
    public let gestureClass: FixedGestureClass
    public let startedAt: MonotonicEventTimestamp
    public fileprivate(set) var lastTimestamp: MonotonicEventTimestamp
    public fileprivate(set) var lastCaptureOrder: UInt64
}

public struct FixedGestureInputRecognizer: Sendable {
    public private(set) var activeSession: ActiveFixedGestureInputSession?
    public private(set) var pendingReleaseButton: MouseButton?

    private let cancellation: GestureCancellationConfiguration
    private let assignments: GestureButtonAssignments
    private let sessionSequence: TrackpadOutputSessionSequence

    public init(
        cancellation: GestureCancellationConfiguration = .default,
        assignments: GestureButtonAssignments = .default,
        sessionSequence: TrackpadOutputSessionSequence = TrackpadOutputSessionSequence()
    ) {
        self.cancellation = cancellation
        self.assignments = assignments
        self.sessionSequence = sessionSequence
    }

    public mutating func handle(
        _ event: FixedGestureSourceInputEvent
    ) -> FixedGestureInputDecision {
        switch event {
        case let .buttonDown(button, timestamp):
            return begin(button: button, timestamp: timestamp)
        case let .buttonUp(button, timestamp):
            return end(button: button, timestamp: timestamp)
        case let .move(deltaX, deltaY, timestamp):
            return change(
                sourceKind: .move,
                deltaX: deltaX,
                deltaY: deltaY,
                timestamp: timestamp
            )
        case let .wheel(deltaX, deltaY, timestamp):
            return change(
                sourceKind: .wheel,
                deltaX: deltaX,
                deltaY: deltaY,
                timestamp: timestamp
            )
        case let .cancel(timestamp):
            return cancel(timestamp: timestamp)
        }
    }

    public var isIdle: Bool {
        activeSession == nil
    }

    public var activeButton: MouseButton? {
        activeSession?.sourceButton
    }

    private mutating func begin(
        button: MouseButton,
        timestamp: MonotonicEventTimestamp
    ) -> FixedGestureInputDecision {
        guard activeSession == nil, pendingReleaseButton == nil,
              let gestureClass = assignments.assignment(for: button)
        else {
            return FixedGestureInputDecision(shouldSuppressOriginal: false)
        }

        let sessionID: TrackpadOutputSessionID
        do {
            sessionID = try sessionSequence.next()
        } catch {
            return FixedGestureInputDecision(
                shouldSuppressOriginal: false,
                failure: .sessionSequenceExhausted
            )
        }

        activeSession = ActiveFixedGestureInputSession(
            sessionID: sessionID,
            sourceButton: button,
            gestureClass: gestureClass,
            startedAt: timestamp,
            lastTimestamp: timestamp,
            lastCaptureOrder: 0
        )
        return FixedGestureInputDecision(
            commands: [
                FixedGestureInputCommand(
                    sessionID: sessionID,
                    sourceButton: button,
                    gestureClass: gestureClass,
                    captureOrder: 0,
                    timestamp: timestamp,
                    sourceKind: .buttonDown,
                    phase: .began,
                    deltaX: 0,
                    deltaY: 0
                )
            ],
            shouldSuppressOriginal: true
        )
    }

    private mutating func end(
        button: MouseButton,
        timestamp: MonotonicEventTimestamp
    ) -> FixedGestureInputDecision {
        if pendingReleaseButton == button {
            pendingReleaseButton = nil
            return FixedGestureInputDecision(shouldSuppressOriginal: true)
        }
        guard let session = activeSession, session.sourceButton == button else {
            return FixedGestureInputDecision(shouldSuppressOriginal: false)
        }
        if let failure = orderingFailure(session: session, timestamp: timestamp) {
            activeSession = nil
            return FixedGestureInputDecision(
                shouldSuppressOriginal: true,
                failure: failure
            )
        }
        if isExpired(session: session, timestamp: timestamp) {
            return finish(
                session: session,
                timestamp: timestamp,
                sourceKind: .cancellation,
                phase: .cancelled,
                shouldSuppressOriginal: true,
                keepPendingRelease: false
            )
        }
        return finish(
            session: session,
            timestamp: timestamp,
            sourceKind: .buttonUp,
            phase: .ended,
            shouldSuppressOriginal: true,
            keepPendingRelease: false
        )
    }

    private mutating func change(
        sourceKind: GestureInputSourceKind,
        deltaX: Double,
        deltaY: Double,
        timestamp: MonotonicEventTimestamp
    ) -> FixedGestureInputDecision {
        guard var session = activeSession else {
            return FixedGestureInputDecision(shouldSuppressOriginal: false)
        }
        if let failure = orderingFailure(session: session, timestamp: timestamp) {
            activeSession = nil
            pendingReleaseButton = session.sourceButton
            return FixedGestureInputDecision(
                shouldSuppressOriginal: true,
                failure: failure
            )
        }
        if isExpired(session: session, timestamp: timestamp) {
            return finishAfterExpiredChange(
                session: session,
                sourceKind: sourceKind,
                deltaX: deltaX,
                deltaY: deltaY,
                timestamp: timestamp,
            )
        }
        guard let captureOrder = nextCaptureOrder(after: session.lastCaptureOrder) else {
            activeSession = nil
            pendingReleaseButton = session.sourceButton
            return FixedGestureInputDecision(
                shouldSuppressOriginal: true,
                failure: .captureOrderExhausted
            )
        }

        session.lastCaptureOrder = captureOrder
        session.lastTimestamp = timestamp
        activeSession = session
        return FixedGestureInputDecision(
            commands: [
                FixedGestureInputCommand(
                    sessionID: session.sessionID,
                    sourceButton: session.sourceButton,
                    gestureClass: session.gestureClass,
                    captureOrder: captureOrder,
                    timestamp: timestamp,
                    sourceKind: sourceKind,
                    phase: .changed,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            ],
            shouldSuppressOriginal: true
        )
    }

    private mutating func cancel(
        timestamp: MonotonicEventTimestamp
    ) -> FixedGestureInputDecision {
        guard let session = activeSession else {
            return FixedGestureInputDecision(shouldSuppressOriginal: false)
        }
        if let failure = orderingFailure(session: session, timestamp: timestamp) {
            activeSession = nil
            pendingReleaseButton = session.sourceButton
            return FixedGestureInputDecision(
                shouldSuppressOriginal: false,
                failure: failure
            )
        }
        return finish(
            session: session,
            timestamp: timestamp,
            sourceKind: .cancellation,
            phase: .cancelled,
            shouldSuppressOriginal: false,
            keepPendingRelease: true
        )
    }

    private mutating func finish(
        session: ActiveFixedGestureInputSession,
        timestamp: MonotonicEventTimestamp,
        sourceKind: GestureInputSourceKind,
        phase: FixedGestureInputPhase,
        shouldSuppressOriginal: Bool,
        keepPendingRelease: Bool
    ) -> FixedGestureInputDecision {
        guard let captureOrder = nextCaptureOrder(after: session.lastCaptureOrder) else {
            activeSession = nil
            pendingReleaseButton = keepPendingRelease ? session.sourceButton : nil
            return FixedGestureInputDecision(
                shouldSuppressOriginal: shouldSuppressOriginal,
                failure: .captureOrderExhausted
            )
        }
        activeSession = nil
        pendingReleaseButton = keepPendingRelease ? session.sourceButton : nil
        return FixedGestureInputDecision(
            commands: [
                FixedGestureInputCommand(
                    sessionID: session.sessionID,
                    sourceButton: session.sourceButton,
                    gestureClass: session.gestureClass,
                    captureOrder: captureOrder,
                    timestamp: timestamp,
                    sourceKind: sourceKind,
                    phase: phase,
                    deltaX: 0,
                    deltaY: 0
                )
            ],
            shouldSuppressOriginal: shouldSuppressOriginal
        )
    }

    private mutating func finishAfterExpiredChange(
        session: ActiveFixedGestureInputSession,
        sourceKind: GestureInputSourceKind,
        deltaX: Double,
        deltaY: Double,
        timestamp: MonotonicEventTimestamp
    ) -> FixedGestureInputDecision {
        guard let changeOrder = nextCaptureOrder(after: session.lastCaptureOrder),
              let cancellationOrder = nextCaptureOrder(after: changeOrder)
        else {
            activeSession = nil
            pendingReleaseButton = session.sourceButton
            return FixedGestureInputDecision(
                shouldSuppressOriginal: true,
                failure: .captureOrderExhausted
            )
        }
        activeSession = nil
        pendingReleaseButton = session.sourceButton
        return FixedGestureInputDecision(
            commands: [
                FixedGestureInputCommand(
                    sessionID: session.sessionID,
                    sourceButton: session.sourceButton,
                    gestureClass: session.gestureClass,
                    captureOrder: changeOrder,
                    timestamp: timestamp,
                    sourceKind: sourceKind,
                    phase: .changed,
                    deltaX: deltaX,
                    deltaY: deltaY
                ),
                FixedGestureInputCommand(
                    sessionID: session.sessionID,
                    sourceButton: session.sourceButton,
                    gestureClass: session.gestureClass,
                    captureOrder: cancellationOrder,
                    timestamp: timestamp,
                    sourceKind: .cancellation,
                    phase: .cancelled,
                    deltaX: 0,
                    deltaY: 0
                ),
            ],
            shouldSuppressOriginal: true
        )
    }

    private func orderingFailure(
        session: ActiveFixedGestureInputSession,
        timestamp: MonotonicEventTimestamp
    ) -> FixedGestureRecognitionFailure? {
        guard timestamp >= session.lastTimestamp else {
            return .timestampRegression(previous: session.lastTimestamp, actual: timestamp)
        }
        return nil
    }

    private func isExpired(
        session: ActiveFixedGestureInputSession,
        timestamp: MonotonicEventTimestamp
    ) -> Bool {
        let duration = cancellation.maximumDuration
        if duration > 0,
           elapsedSeconds(from: session.startedAt, to: timestamp) > duration {
            return true
        }
        let inactivity = cancellation.maximumInactivityInterval
        if inactivity > 0,
           elapsedSeconds(from: session.lastTimestamp, to: timestamp) > inactivity {
            return true
        }
        return false
    }

    private func elapsedSeconds(
        from start: MonotonicEventTimestamp,
        to end: MonotonicEventTimestamp
    ) -> TimeInterval {
        guard end >= start else {
            return 0
        }
        return TimeInterval(end.nanosecondsSinceStartup - start.nanosecondsSinceStartup)
            / TimeInterval(MonotonicEventClock.nanosecondsPerSecond)
    }

    private func nextCaptureOrder(after current: UInt64) -> UInt64? {
        let next = current.addingReportingOverflow(1)
        return next.overflow ? nil : next.partialValue
    }
}
