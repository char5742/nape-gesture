import Foundation
import NapeGestureCore

public struct FixedGestureProductSessionPost: Equatable, Sendable {
    public let gestureClass: FixedGestureClass
    public let family: TrackpadOutputEventFamily
    public let result: ProductGestureOutputResult

    public init(
        gestureClass: FixedGestureClass,
        family: TrackpadOutputEventFamily,
        result: ProductGestureOutputResult
    ) {
        self.gestureClass = gestureClass
        self.family = family
        self.result = result
    }
}

public final class FixedGestureProductSessionCoordinator {
    private static let pinchMotionScale = 0.5

    private struct PendingOutput {
        var event: TrackpadOutputSessionEvent
        var candidateMachine: FixedGestureSessionMachine
        var closesSession: Bool
    }

    private struct ActiveSession {
        var machine: FixedGestureSessionMachine
        var dockSwipeAxis: TrackpadOutputAxis?
        var dockSwipeProgress: Double
        var productOutputBegan: Bool
        var lastMotionX: Double
        var lastMotionY: Double
        var lastVelocityX: Double
        var lastVelocityY: Double
        var pendingOutput: PendingOutput?
    }

    public var capability: ProductGestureOutputCapability {
        output.capability
    }

    public var unsupportedRequiredFamilies: Set<TrackpadOutputEventFamily> {
        Self.requiredFamilies.filter { !output.supports($0) }
    }

    private static let requiredFamilies: Set<TrackpadOutputEventFamily> = [
        .scroll,
        .dockSwipe,
        .dockSwipePinch,
    ]

    private let output: any ProductGestureOutput
    private var activeSession: ActiveSession?

    public init(output: any ProductGestureOutput) {
        self.output = output
    }

    public func post(_ command: FixedGestureInputCommand) -> FixedGestureProductSessionPost {
        let family = Self.family(for: command.gestureClass)
        guard output.supports(family) else {
            return FixedGestureProductSessionPost(
                gestureClass: command.gestureClass,
                family: family,
                result: .rejected(.unsupported)
            )
        }

        var baseline: ActiveSession
        if command.phase == .began {
            guard activeSession == nil else {
                return rejected(command, family: family, failure: .invalidSession)
            }
            baseline = ActiveSession(
                machine: FixedGestureSessionMachine(
                    sessionID: command.sessionID,
                    sourceButton: command.sourceButton,
                    gestureClass: command.gestureClass
                ),
                dockSwipeAxis: nil,
                dockSwipeProgress: 0,
                productOutputBegan: false,
                lastMotionX: 0,
                lastMotionY: 0,
                lastVelocityX: 0,
                lastVelocityY: 0,
                pendingOutput: nil
            )
        } else {
            guard let activeSession,
                  activeSession.machine.sessionID == command.sessionID,
                  activeSession.machine.gestureClass == command.gestureClass,
                  activeSession.pendingOutput == nil
            else {
                return rejected(command, family: family, failure: .invalidSession)
            }
            baseline = activeSession
        }

        var candidate = baseline
        do {
            try candidate.machine.accept(command)
        } catch {
            return rejected(command, family: family, failure: .invalidSession)
        }

        let sourceVelocity = Self.velocity(
            deltaX: command.deltaX,
            deltaY: command.deltaY,
            previousTimestamp: activeSession?.machine.lastTimestamp,
            timestamp: command.timestamp
        )
        let motionX = Self.normalizedMotion(command.deltaX)
        let motionY = Self.normalizedMotion(command.deltaY)
        let velocityX = Self.normalizedMotion(sourceVelocity.x)
        let velocityY = Self.normalizedMotion(sourceVelocity.y)

        if command.gestureClass == .threeFingerSystemSwipe,
           candidate.dockSwipeAxis == nil,
           command.phase == .changed,
           (command.deltaX != 0 || command.deltaY != 0) {
            candidate.dockSwipeAxis = Self.dominantAxis(
                deltaX: command.deltaX,
                deltaY: command.deltaY
            )
        }
        if command.gestureClass == .threeFingerSystemSwipe,
           command.phase == .changed {
            let axis = candidate.dockSwipeAxis
                ?? Self.dominantAxis(deltaX: command.deltaX, deltaY: command.deltaY)
            let progressDelta = axis == .horizontal ? motionX : -motionY
            candidate.dockSwipeProgress += progressDelta
        } else if command.gestureClass == .pinch,
                  command.phase == .changed {
            candidate.dockSwipeProgress += Self.pinchMotion(x: motionX, y: motionY)
        }
        if command.phase == .changed,
           (command.deltaX != 0 || command.deltaY != 0) {
            candidate.lastMotionX = motionX
            candidate.lastMotionY = motionY
            candidate.lastVelocityX = velocityX
            candidate.lastVelocityY = velocityY
        }

        let outputPhase: TrackpadOutputInputPhase
        if command.gestureClass == .twoFingerScrollSwipe {
            outputPhase = Self.outputPhase(for: command.phase)
        } else if command.phase == .began {
            activeSession = candidate
            return emptyPost(for: command, family: family)
        } else if !candidate.productOutputBegan {
            guard command.phase == .changed,
                  command.deltaX != 0 || command.deltaY != 0
            else {
                activeSession = candidate.machine.isTerminal ? nil : candidate
                return emptyPost(for: command, family: family)
            }
            candidate.productOutputBegan = true
            outputPhase = .began
        } else {
            outputPhase = Self.outputPhase(for: command.phase)
        }

        let payload = Self.payload(
            for: command,
            outputPhase: outputPhase,
            dockSwipeAxis: candidate.dockSwipeAxis,
            dockSwipeProgress: candidate.dockSwipeProgress,
            motionX: motionX,
            motionY: motionY,
            lastMotionX: candidate.lastMotionX,
            lastMotionY: candidate.lastMotionY,
            sourceVelocityX: sourceVelocity.x,
            sourceVelocityY: sourceVelocity.y,
            lastVelocityX: candidate.lastVelocityX,
            lastVelocityY: candidate.lastVelocityY
        )
        let event = Self.sessionEvent(
            command: command,
            family: family,
            phase: outputPhase,
            payload: payload
        )
        let result = output.post(event)
        if result.failure == nil {
            if case .terminal = candidate.machine.state {
                activeSession = nil
            } else {
                activeSession = candidate
            }
        } else if result.generatedEventCount > 0 {
            baseline.dockSwipeAxis = candidate.dockSwipeAxis
            baseline.dockSwipeProgress = candidate.dockSwipeProgress
            baseline.productOutputBegan = candidate.productOutputBegan
            baseline.lastMotionX = candidate.lastMotionX
            baseline.lastMotionY = candidate.lastMotionY
            baseline.lastVelocityX = candidate.lastVelocityX
            baseline.lastVelocityY = candidate.lastVelocityY
            baseline.pendingOutput = PendingOutput(
                event: event,
                candidateMachine: candidate.machine,
                closesSession: candidate.machine.isTerminal
            )
            activeSession = baseline
        } else if command.phase == .began {
            activeSession = nil
        }
        return FixedGestureProductSessionPost(
            gestureClass: command.gestureClass,
            family: family,
            result: result
        )
    }

    @discardableResult
    public func cancelActive(
        reason: TrackpadOutputCancellationReason,
        timestamp: MonotonicEventTimestamp
    ) -> ProductGestureOutputResult {
        guard var activeSession else {
            return ProductGestureOutputResult(
                generatedEventCount: 0,
                failedEventCreationCount: 0
            )
        }

        if let pending = activeSession.pendingOutput, pending.closesSession {
            let retry = output.post(pending.event)
            if retry.failure == nil {
                self.activeSession = nil
            }
            return retry
        }

        if activeSession.machine.gestureClass != .twoFingerScrollSwipe,
           !activeSession.productOutputBegan,
           activeSession.pendingOutput == nil {
            self.activeSession = nil
            return ProductGestureOutputResult(
                generatedEventCount: 0,
                failedEventCreationCount: 0
            )
        }

        let event: TrackpadOutputSessionEvent
        let terminalMachine: FixedGestureSessionMachine
        if let pending = activeSession.pendingOutput {
            let normalizedTimestamp = max(timestamp, pending.event.timestamp)
            event = .cancellation(
                TrackpadOutputCancellationFrame(
                    sessionID: pending.event.sessionID,
                    captureOrder: pending.event.captureOrder,
                    timestamp: normalizedTimestamp,
                    family: pending.event.family,
                    reason: reason,
                    payload: Self.payload(of: pending.event)
                )
            )
            terminalMachine = pending.candidateMachine
        } else {
            guard let lastOrder = activeSession.machine.lastCaptureOrder,
                  let lastTimestamp = activeSession.machine.lastTimestamp
            else {
                return ProductGestureOutputResult(
                    generatedEventCount: 0,
                    failedEventCreationCount: 0
                )
            }
            let nextOrder = lastOrder.addingReportingOverflow(1)
            guard !nextOrder.overflow else {
                return .rejected(.invalidSession)
            }
            let command = FixedGestureInputCommand(
                sessionID: activeSession.machine.sessionID,
                sourceButton: activeSession.machine.sourceButton,
                gestureClass: activeSession.machine.gestureClass,
                captureOrder: nextOrder.partialValue,
                timestamp: max(timestamp, lastTimestamp),
                sourceKind: .cancellation,
                phase: .cancelled,
                deltaX: 0,
                deltaY: 0
            )
            var candidateMachine = activeSession.machine
            do {
                try candidateMachine.accept(command)
            } catch {
                return .rejected(.invalidSession)
            }
            let family = Self.family(for: command.gestureClass)
            let payload = Self.payload(
                for: command,
                outputPhase: .cancelled,
                dockSwipeAxis: activeSession.dockSwipeAxis,
                dockSwipeProgress: activeSession.dockSwipeProgress,
                motionX: 0,
                motionY: 0,
                lastMotionX: activeSession.lastMotionX,
                lastMotionY: activeSession.lastMotionY,
                sourceVelocityX: 0,
                sourceVelocityY: 0,
                lastVelocityX: activeSession.lastVelocityX,
                lastVelocityY: activeSession.lastVelocityY
            )
            event = .cancellation(
                TrackpadOutputCancellationFrame(
                    sessionID: command.sessionID,
                    captureOrder: command.captureOrder,
                    timestamp: command.timestamp,
                    family: family,
                    reason: reason,
                    payload: payload
                )
            )
            terminalMachine = candidateMachine
        }
        let result = output.post(event)
        if result.failure == nil {
            self.activeSession = nil
        } else if result.generatedEventCount > 0 {
            activeSession.pendingOutput = PendingOutput(
                event: event,
                candidateMachine: terminalMachine,
                closesSession: true
            )
            self.activeSession = activeSession
        }
        return result
    }

    public func reset() {
        activeSession = nil
        output.reset()
    }

    private func rejected(
        _ command: FixedGestureInputCommand,
        family: TrackpadOutputEventFamily,
        failure: ProductGestureOutputFailure
    ) -> FixedGestureProductSessionPost {
        FixedGestureProductSessionPost(
            gestureClass: command.gestureClass,
            family: family,
            result: .rejected(failure)
        )
    }

    private func emptyPost(
        for command: FixedGestureInputCommand,
        family: TrackpadOutputEventFamily
    ) -> FixedGestureProductSessionPost {
        FixedGestureProductSessionPost(
            gestureClass: command.gestureClass,
            family: family,
            result: ProductGestureOutputResult(
                generatedEventCount: 0,
                failedEventCreationCount: 0
            )
        )
    }

    private static func family(for gestureClass: FixedGestureClass) -> TrackpadOutputEventFamily {
        switch gestureClass {
        case .twoFingerScrollSwipe: .scroll
        case .threeFingerSystemSwipe: .dockSwipe
        case .pinch: .dockSwipePinch
        }
    }

    private static func payload(of event: TrackpadOutputSessionEvent) -> TrackpadOutputPayload? {
        switch event {
        case .input(let frame): frame.payload
        case .momentum(let frame): frame.payload
        case .cancellation(let frame): frame.payload
        }
    }

    private static func sessionEvent(
        command: FixedGestureInputCommand,
        family: TrackpadOutputEventFamily,
        phase: TrackpadOutputInputPhase,
        payload: TrackpadOutputPayload
    ) -> TrackpadOutputSessionEvent {
        return .input(
            TrackpadOutputInputFrame(
                sessionID: command.sessionID,
                captureOrder: command.captureOrder,
                timestamp: command.timestamp,
                phase: phase,
                continuation: phase == .ended ? .complete : nil,
                terminalDecision: family == .scroll
                    ? nil
                    : (phase == .cancelled ? .cancel : (phase == .ended ? .commit : nil)),
                payload: payload
            )
        )
    }

    private static func payload(
        for command: FixedGestureInputCommand,
        outputPhase: TrackpadOutputInputPhase,
        dockSwipeAxis: TrackpadOutputAxis?,
        dockSwipeProgress: Double,
        motionX: Double,
        motionY: Double,
        lastMotionX: Double,
        lastMotionY: Double,
        sourceVelocityX: Double,
        sourceVelocityY: Double,
        lastVelocityX: Double,
        lastVelocityY: Double
    ) -> TrackpadOutputPayload {
        let isTerminal = outputPhase == .ended || outputPhase == .cancelled
        switch command.gestureClass {
        case .twoFingerScrollSwipe:
            return .scroll(
                deltaX: command.deltaX,
                deltaY: command.deltaY,
                velocityX: sourceVelocityX,
                velocityY: sourceVelocityY
            )
        case .threeFingerSystemSwipe:
            let axis = dockSwipeAxis
                ?? dominantAxis(deltaX: command.deltaX, deltaY: command.deltaY)
            let terminalVelocity = axis == .horizontal ? lastVelocityX : -lastVelocityY
            return .dockSwipe(
                axis: axis,
                progress: dockSwipeProgress,
                motionX: isTerminal ? lastMotionX : motionX,
                motionY: isTerminal ? lastMotionY : motionY,
                terminalVelocityX: isTerminal ? terminalVelocity : 0,
                terminalVelocityY: isTerminal ? terminalVelocity : 0
            )
        case .pinch:
            let motion = pinchMotion(x: motionX, y: motionY)
            let terminalVelocity = pinchMotion(x: lastVelocityX, y: lastVelocityY)
            return .dockSwipePinch(
                progress: dockSwipeProgress,
                motion: isTerminal ? 0 : motion,
                terminalVelocity: isTerminal ? terminalVelocity : 0
            )
        }
    }

    private static func outputPhase(
        for phase: FixedGestureInputPhase
    ) -> TrackpadOutputInputPhase {
        switch phase {
        case .began: .began
        case .changed: .changed
        case .ended: .ended
        case .cancelled: .cancelled
        }
    }

    private static func dominantAxis(deltaX: Double, deltaY: Double) -> TrackpadOutputAxis {
        abs(deltaX) > abs(deltaY) ? .horizontal : .vertical
    }

    private static func velocity(
        deltaX: Double,
        deltaY: Double,
        previousTimestamp: MonotonicEventTimestamp?,
        timestamp: MonotonicEventTimestamp
    ) -> (x: Double, y: Double) {
        guard let previousTimestamp, timestamp > previousTimestamp else {
            return (0, 0)
        }
        let elapsed = Double(
            timestamp.nanosecondsSinceStartup - previousTimestamp.nanosecondsSinceStartup
        ) / Double(MonotonicEventClock.nanosecondsPerSecond)
        guard elapsed > 0 else {
            return (0, 0)
        }
        return (deltaX / elapsed, deltaY / elapsed)
    }

    private static func normalizedMotion(_ value: Double) -> Double {
        value / 300
    }

    private static func pinchMotion(x: Double, y: Double) -> Double {
        (y != 0 ? -y : x) * pinchMotionScale
    }
}
