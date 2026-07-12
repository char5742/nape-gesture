import Foundation
import NapeGestureCore

public struct ProductGestureSessionPost: Equatable, Sendable {
    public var mode: TrackpadGestureMode
    public var family: TrackpadOutputEventFamily?
    public var result: ProductGestureOutputResult

    public init(
        mode: TrackpadGestureMode,
        family: TrackpadOutputEventFamily?,
        result: ProductGestureOutputResult
    ) {
        self.mode = mode
        self.family = family
        self.result = result
    }
}

public final class ProductGestureSessionCoordinator {
    private struct ActiveSession {
        var mode: TrackpadGestureMode
        var machine: TrackpadOutputSessionMachine
        var dockSwipeAxis: TrackpadOutputAxis?
        var nextCaptureOrder: UInt64
        var cancellationTimestampFloor: MonotonicEventTimestamp?
    }

    private struct ValidatedTransition {
        var machine: TrackpadOutputSessionMachine
        var nextCaptureOrder: UInt64?
    }

    public var capability: ProductGestureOutputCapability {
        output.capability
    }

    public var unsupportedRequiredFamilies: Set<TrackpadOutputEventFamily> {
        requiredFamilies.filter { !output.supports($0) }
    }

    private let output: any ProductGestureOutput
    private let enabledModes: Set<TrackpadGestureMode>
    private let sessionSequence: TrackpadOutputSessionSequence
    private var activeSession: ActiveSession?

    public init(
        enabledModes: Set<TrackpadGestureMode> = Set(
            TrackpadGestureMode.allCases.filter { $0 != .none }),
        output: any ProductGestureOutput,
        sessionSequence: TrackpadOutputSessionSequence = TrackpadOutputSessionSequence()
    ) {
        self.enabledModes = enabledModes
        self.output = output
        self.sessionSequence = sessionSequence
    }

    public func post(
        command: GestureCommand,
        continuation: TrackpadOutputContinuation? = nil
    ) -> ProductGestureSessionPost {
        let mode = command.mode
        let family = Self.family(for: mode)
        if command.phase == .began, activeSession != nil {
            return ProductGestureSessionPost(
                mode: mode, family: family, result: .rejected(.invalidSession))
        }
        if let activeSession,
            command.phase != .began,
            activeSession.mode != mode
        {
            return ProductGestureSessionPost(
                mode: mode, family: family, result: .rejected(.invalidSession))
        }
        guard mode != .none else {
            return ProductGestureSessionPost(
                mode: mode,
                family: nil,
                result: ProductGestureOutputResult(
                    generatedEventCount: 0,
                    failedEventCreationCount: 0
                )
            )
        }
        guard enabledModes.contains(mode), let family, output.supports(family) else {
            return ProductGestureSessionPost(
                mode: mode, family: family, result: .rejected(.unsupported))
        }
        guard
            let timestamp = MonotonicEventClock.timestamp(
                fromSecondsSinceStartup: command.timestamp
            ), let payload = payload(mode: mode, command: command)
        else {
            return ProductGestureSessionPost(
                mode: mode, family: family, result: .rejected(.invalidSession))
        }

        let event: TrackpadOutputSessionEvent
        do {
            event = try makeSessionEvent(
                mode: mode,
                family: family,
                command: command,
                timestamp: timestamp,
                payload: payload,
                continuation: continuation
            )
        } catch {
            return ProductGestureSessionPost(
                mode: mode, family: family, result: .rejected(.invalidSession))
        }

        let transition: ValidatedTransition
        do {
            transition = try validateTransition(for: event)
        } catch {
            if command.phase == .began {
                activeSession = nil
            }
            return ProductGestureSessionPost(
                mode: mode, family: family, result: .rejected(.invalidSession))
        }

        let result = output.post(event)
        guard result.failure == nil else {
            if result.generatedEventCount > 0 {
                recordCancellationTimestampFloor(event.timestamp)
            }
            if command.phase == .began, result.generatedEventCount == 0 {
                activeSession = nil
            }
            return ProductGestureSessionPost(mode: mode, family: family, result: result)
        }
        commit(transition)
        return ProductGestureSessionPost(mode: mode, family: family, result: result)
    }

    public func supportsMomentum(for command: GestureCommand) -> Bool {
        let mode = command.mode
        if let activeSession, activeSession.mode != mode {
            return false
        }
        guard let family = Self.family(for: mode) else {
            return false
        }
        return family == .scroll && output.supports(.scroll)
    }

    @discardableResult
    public func cancelActive(
        reason: TrackpadOutputCancellationReason,
        at time: TimeInterval
    ) -> ProductGestureOutputResult {
        guard let activeSession else {
            return ProductGestureOutputResult(generatedEventCount: 0, failedEventCreationCount: 0)
        }
        guard let timestamp = MonotonicEventClock.timestamp(fromSecondsSinceStartup: time) else {
            return .rejected(.invalidSession)
        }
        let normalizedTimestamp = max(
            timestamp,
            activeSession.cancellationTimestampFloor
                ?? activeSession.machine.lastTimestamp
                ?? timestamp
        )
        let event = TrackpadOutputSessionEvent.cancellation(
            TrackpadOutputCancellationFrame(
                sessionID: activeSession.machine.sessionID,
                captureOrder: activeSession.nextCaptureOrder,
                timestamp: normalizedTimestamp,
                family: activeSession.machine.family,
                reason: reason,
                payload: activeSession.machine.lastPayload
            )
        )
        var candidate = activeSession.machine
        do {
            try candidate.accept(event)
        } catch {
            return .rejected(.invalidSession)
        }

        let result = output.post(event)
        if result.failure == nil {
            self.activeSession = nil
        } else if result.generatedEventCount > 0 {
            recordCancellationTimestampFloor(event.timestamp)
        }
        return result
    }

    public func reset() {
        activeSession = nil
        output.reset()
    }

    private var requiredFamilies: Set<TrackpadOutputEventFamily> {
        Set(enabledModes.compactMap(Self.family(for:)))
    }

    private func makeSessionEvent(
        mode: TrackpadGestureMode,
        family: TrackpadOutputEventFamily,
        command: GestureCommand,
        timestamp: MonotonicEventTimestamp,
        payload: TrackpadOutputPayload,
        continuation: TrackpadOutputContinuation?
    ) throws -> TrackpadOutputSessionEvent {
        if command.kind == .momentum {
            guard let active = activeSession,
                active.mode == mode,
                active.machine.family == family
            else {
                throw ProductGestureOutputFailure.invalidSession
            }
            let phase: TrackpadOutputMomentumPhase
            switch command.phase {
            case .momentum:
                phase = active.machine.state == .awaitingMomentum ? .began : .continued
            case .ended:
                phase = .ended
            default:
                throw ProductGestureOutputFailure.invalidSession
            }
            return .momentum(
                TrackpadOutputMomentumFrame(
                    sessionID: active.machine.sessionID,
                    captureOrder: active.nextCaptureOrder,
                    timestamp: timestamp,
                    phase: phase,
                    payload: payload
                )
            )
        }

        let inputPhase: TrackpadOutputInputPhase
        switch command.phase {
        case .began:
            inputPhase = .began
        case .changed:
            inputPhase = .changed
        case .ended:
            inputPhase = .ended
        case .cancelled:
            inputPhase = .cancelled
        case .momentum:
            throw ProductGestureOutputFailure.invalidSession
        }

        if inputPhase == .began {
            guard activeSession == nil else {
                throw ProductGestureOutputFailure.invalidSession
            }
            let sessionID = try sessionSequence.next()
            activeSession = ActiveSession(
                mode: mode,
                machine: TrackpadOutputSessionMachine(sessionID: sessionID, family: family),
                dockSwipeAxis: family == .dockSwipe ? Self.dominantAxis(for: command) : nil,
                nextCaptureOrder: 0,
                cancellationTimestampFloor: nil
            )
        }
        guard let active = activeSession,
            active.mode == mode,
            active.machine.family == family
        else {
            throw ProductGestureOutputFailure.invalidSession
        }

        return .input(
            TrackpadOutputInputFrame(
                sessionID: active.machine.sessionID,
                captureOrder: active.nextCaptureOrder,
                timestamp: timestamp,
                phase: inputPhase,
                continuation: inputPhase == .ended
                    ? (family == .scroll ? continuation : .complete)
                    : nil,
                terminalDecision: family == .scroll
                    ? nil
                    : (inputPhase == .cancelled ? .cancel : (inputPhase == .ended ? .commit : nil)),
                payload: payload
            )
        )
    }

    private func validateTransition(
        for event: TrackpadOutputSessionEvent
    ) throws -> ValidatedTransition {
        guard let active = activeSession else {
            throw ProductGestureOutputFailure.invalidSession
        }
        var candidate = active.machine
        try candidate.accept(event)
        if case .terminal = candidate.state {
            return ValidatedTransition(machine: candidate, nextCaptureOrder: nil)
        }
        let next = active.nextCaptureOrder.addingReportingOverflow(1)
        guard !next.overflow else {
            throw ProductGestureOutputFailure.invalidSession
        }
        return ValidatedTransition(
            machine: candidate,
            nextCaptureOrder: next.partialValue
        )
    }

    private func commit(_ transition: ValidatedTransition) {
        guard var active = activeSession else {
            preconditionFailure("validated transitionのactive sessionが失われました。")
        }
        if case .terminal = transition.machine.state {
            activeSession = nil
            return
        }
        guard let nextCaptureOrder = transition.nextCaptureOrder else {
            preconditionFailure("nonterminal transitionの次capture orderがありません。")
        }
        active.machine = transition.machine
        active.nextCaptureOrder = nextCaptureOrder
        active.cancellationTimestampFloor = nil
        activeSession = active
    }

    private func recordCancellationTimestampFloor(_ timestamp: MonotonicEventTimestamp) {
        guard var active = activeSession else {
            return
        }
        active.cancellationTimestampFloor = max(
            timestamp,
            active.cancellationTimestampFloor
                ?? active.machine.lastTimestamp
                ?? timestamp
        )
        activeSession = active
    }

    private static func family(for mode: TrackpadGestureMode) -> TrackpadOutputEventFamily? {
        switch mode {
        case .none: nil
        case .twoFingerSwipe: .scroll
        case .systemSwipe: .dockSwipe
        case .pinch: .dockSwipePinch
        }
    }

    private func payload(
        mode: TrackpadGestureMode,
        command: GestureCommand
    ) -> TrackpadOutputPayload? {
        switch mode {
        case .twoFingerSwipe:
            return .scroll(
                deltaX: command.deltaX,
                deltaY: command.deltaY,
                velocityX: command.velocityX,
                velocityY: command.velocityY
            )
        case .systemSwipe:
            let axis = activeSession?.dockSwipeAxis ?? Self.dominantAxis(for: command)
            let motionX = command.deltaX / 300
            let motionY = command.deltaY / 300
            let progress = axis == .horizontal ? motionX : -motionY
            let isTerminal = command.phase == .ended || command.phase == .cancelled
            return .dockSwipe(
                axis: axis,
                progress: progress,
                motionX: isTerminal ? 0 : motionX,
                motionY: isTerminal ? 0 : motionY,
                terminalVelocityX: isTerminal ? command.velocityX / 300 : 0,
                terminalVelocityY: isTerminal ? command.velocityY / 300 : 0
            )
        case .pinch:
            let useY = command.deltaY != 0 || command.velocityY != 0
            let motion = useY ? -command.deltaY / 300 : command.deltaX / 300
            let velocity = useY ? -command.velocityY / 300 : command.velocityX / 300
            let isTerminal = command.phase == .ended || command.phase == .cancelled
            return .dockSwipePinch(
                progress: motion,
                motion: isTerminal ? 0 : motion,
                terminalVelocity: isTerminal ? velocity : 0
            )
        case .none:
            return nil
        }
    }

    private static func dominantAxis(for command: GestureCommand) -> TrackpadOutputAxis {
        abs(command.deltaX) > abs(command.deltaY) ? .horizontal : .vertical
    }

    private static func normalizedProgress(_ value: Double) -> Double {
        min(max(value / 300, -1), 1)
    }

    private static func normalizedVelocity(_ value: Double) -> Double {
        min(max(value / 1_000, -4), 4)
    }

    private static func normalizedScale(_ value: Double) -> Double {
        min(max(value / 400, -0.2), 0.2)
    }
}
