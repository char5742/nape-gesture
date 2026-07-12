import Foundation
import NapeGestureCore

public struct ProductGestureSessionPost: Equatable, Sendable {
    public var action: GestureAction
    public var result: ProductGestureOutputResult

    public init(action: GestureAction, result: ProductGestureOutputResult) {
        self.action = action
        self.result = result
    }
}

public final class ProductGestureSessionCoordinator {
    private struct ActiveSession {
        var action: GestureAction
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
    private let sessionSequence: TrackpadOutputSessionSequence
    private var activeSession: ActiveSession?

    public init(
        output: any ProductGestureOutput,
        sessionSequence: TrackpadOutputSessionSequence = TrackpadOutputSessionSequence()
    ) {
        self.output = output
        self.sessionSequence = sessionSequence
    }

    public func post(
        command: GestureCommand,
        continuation: TrackpadOutputContinuation? = nil
    ) -> ProductGestureSessionPost {
        let action = activeSession?.action ?? Self.action(for: command)
        if command.phase == .began, activeSession != nil {
            return ProductGestureSessionPost(action: action, result: .rejected(.invalidSession))
        }
        if let activeSession,
           command.phase != .began,
           activeSession.action != action
        {
            return ProductGestureSessionPost(action: action, result: .rejected(.invalidSession))
        }
        guard action != .none else {
            return ProductGestureSessionPost(
                action: action,
                result: ProductGestureOutputResult(
                    generatedEventCount: 0,
                    failedEventCreationCount: 0
                )
            )
        }
        guard let family = Self.family(for: action), output.supports(family) else {
            return ProductGestureSessionPost(action: action, result: .rejected(.unsupported))
        }
        guard let timestamp = MonotonicEventClock.timestamp(
            fromSecondsSinceStartup: command.timestamp
        ), let payload = payload(action: action, command: command) else {
            return ProductGestureSessionPost(action: action, result: .rejected(.invalidSession))
        }

        let event: TrackpadOutputSessionEvent
        do {
            event = try makeSessionEvent(
                action: action,
                family: family,
                command: command,
                timestamp: timestamp,
                payload: payload,
                continuation: continuation
            )
        } catch {
            return ProductGestureSessionPost(action: action, result: .rejected(.invalidSession))
        }

        let transition: ValidatedTransition
        do {
            transition = try validateTransition(for: event)
        } catch {
            if command.phase == .began {
                activeSession = nil
            }
            return ProductGestureSessionPost(action: action, result: .rejected(.invalidSession))
        }

        let result = output.post(event)
        guard result.failure == nil else {
            if result.generatedEventCount > 0 {
                recordCancellationTimestampFloor(event.timestamp)
            }
            if command.phase == .began, result.generatedEventCount == 0 {
                activeSession = nil
            }
            return ProductGestureSessionPost(action: action, result: result)
        }
        commit(transition)
        return ProductGestureSessionPost(action: action, result: result)
    }

    public func supportsMomentum(for command: GestureCommand) -> Bool {
        let action = activeSession?.action ?? Self.action(for: command)
        guard let family = Self.family(for: action) else {
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
        [.dockSwipe, .scroll]
    }

    private func makeSessionEvent(
        action: GestureAction,
        family: TrackpadOutputEventFamily,
        command: GestureCommand,
        timestamp: MonotonicEventTimestamp,
        payload: TrackpadOutputPayload,
        continuation: TrackpadOutputContinuation?
    ) throws -> TrackpadOutputSessionEvent {
        if command.kind == .momentum {
            guard let active = activeSession,
                  active.action == action,
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
                action: action,
                machine: TrackpadOutputSessionMachine(sessionID: sessionID, family: family),
                dockSwipeAxis: family == .dockSwipe ? Self.dominantAxis(for: command) : nil,
                nextCaptureOrder: 0,
                cancellationTimestampFloor: nil
            )
        }
        guard let active = activeSession,
              active.action == action,
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

    private static func family(for action: GestureAction) -> TrackpadOutputEventFamily? {
        switch action {
        case .none:
            nil
        case .smoothScroll, .horizontalScroll:
            .scroll
        case .missionControl, .spaceLeft, .spaceRight, .dockSwipe:
            .dockSwipe
        case .pageBack, .pageForward:
            .navigationSwipe
        case .zoomIn, .zoomOut:
            .magnification
        }
    }

    private static func action(for command: GestureCommand) -> GestureAction {
        switch command.kind {
        case .drag:
            .dockSwipe
        case .wheel, .momentum:
            .smoothScroll
        }
    }

    private func payload(
        action: GestureAction,
        command: GestureCommand
    ) -> TrackpadOutputPayload? {
        switch action {
        case .smoothScroll:
            return .scroll(
                deltaX: command.deltaX,
                deltaY: command.deltaY,
                velocityX: command.velocityX,
                velocityY: command.velocityY
            )
        case .horizontalScroll:
            let useX = command.deltaX != 0
                || (command.deltaY == 0 && command.velocityX != 0)
            let delta = useX ? command.deltaX : command.deltaY
            let velocity = useX ? command.velocityX : command.velocityY
            return .scroll(deltaX: delta, deltaY: 0, velocityX: velocity, velocityY: 0)
        case .dockSwipe:
            let axis = activeSession?.dockSwipeAxis ?? Self.dominantAxis(for: command)
            let delta = axis == .horizontal ? command.deltaX : command.deltaY
            let velocity = axis == .horizontal ? command.velocityX : command.velocityY
            return .dockSwipe(
                axis: axis,
                progress: Self.normalizedProgress(delta),
                velocity: Self.normalizedVelocity(velocity)
            )
        case .missionControl:
            return .dockSwipe(
                axis: .vertical,
                progress: Self.normalizedProgress(-abs(command.deltaY)),
                velocity: Self.normalizedVelocity(-abs(command.velocityY))
            )
        case .spaceLeft:
            return .dockSwipe(
                axis: .horizontal,
                progress: Self.normalizedProgress(abs(command.deltaX)),
                velocity: Self.normalizedVelocity(abs(command.velocityX))
            )
        case .spaceRight:
            return .dockSwipe(
                axis: .horizontal,
                progress: Self.normalizedProgress(-abs(command.deltaX)),
                velocity: Self.normalizedVelocity(-abs(command.velocityX))
            )
        case .pageBack:
            return .navigationSwipe(
                direction: .right,
                progress: Self.normalizedProgress(abs(command.deltaX)),
                velocity: Self.normalizedVelocity(abs(command.velocityX))
            )
        case .pageForward:
            return .navigationSwipe(
                direction: .left,
                progress: Self.normalizedProgress(-abs(command.deltaX)),
                velocity: Self.normalizedVelocity(-abs(command.velocityX))
            )
        case .zoomIn:
            return .magnification(
                progress: Self.normalizedProgress(abs(command.deltaY)),
                scaleDelta: Self.normalizedScale(abs(command.deltaY)),
                velocity: Self.normalizedVelocity(abs(command.velocityY))
            )
        case .zoomOut:
            return .magnification(
                progress: Self.normalizedProgress(-abs(command.deltaY)),
                scaleDelta: Self.normalizedScale(-abs(command.deltaY)),
                velocity: Self.normalizedVelocity(-abs(command.velocityY))
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
