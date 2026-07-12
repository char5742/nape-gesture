import Foundation

public struct GestureRecognizer: Sendable {
    public private(set) var state: GestureState = .idle

    private let configuration: GestureConfiguration
    private var lastVelocityX: Double = 0
    private var lastVelocityY: Double = 0

    public init(configuration: GestureConfiguration = .default) {
        self.configuration = configuration
    }

    public mutating func handle(_ event: RawInputEvent) -> GestureDecision {
        switch event {
        case let .buttonDown(button, time):
            guard button == configuration.activationButton else {
                return GestureDecision(shouldSuppressOriginal: false)
            }
            state = .armed(startTime: time, lastTime: time, totalX: 0, totalY: 0)
            lastVelocityX = 0
            lastVelocityY = 0
            return GestureDecision(shouldSuppressOriginal: true)

        case let .buttonUp(button, time):
            guard button == configuration.activationButton else {
                return GestureDecision(shouldSuppressOriginal: false)
            }
            if shouldCancelForTiming(at: time) {
                return finish(at: time, cancelled: true)
            }
            return finish(at: time, cancelled: false)

        case let .move(deltaX, deltaY, time):
            if shouldCancelForTiming(at: time) {
                return finish(at: time, cancelled: true)
            }
            return handleMove(deltaX: deltaX, deltaY: deltaY, time: time)

        case let .wheel(deltaX, deltaY, time):
            if shouldCancelForTiming(at: time) {
                return finish(at: time, cancelled: true)
            }
            return handleWheel(deltaX: deltaX, deltaY: deltaY, time: time)

        case let .cancel(time):
            return finish(at: time, cancelled: true)
        }
    }

    public var isIdle: Bool {
        state == .idle
    }

    private mutating func handleMove(deltaX: Double, deltaY: Double, time: TimeInterval) -> GestureDecision {
        switch state {
        case .idle:
            return GestureDecision(shouldSuppressOriginal: false)

        case let .armed(startTime, lastTime, totalX, totalY):
            let nextX = totalX + deltaX
            let nextY = totalY + deltaY
            let distance = hypot(nextX, nextY)
            let velocity = velocity(deltaX: deltaX, deltaY: deltaY, previousTime: lastTime, time: time)
            lastVelocityX = velocity.x
            lastVelocityY = velocity.y

            guard distance >= configuration.deadZonePoints else {
                state = .armed(startTime: startTime, lastTime: time, totalX: nextX, totalY: nextY)
                return GestureDecision(shouldSuppressOriginal: true)
            }

            let direction = GestureDirection.dominant(deltaX: nextX, deltaY: nextY)
            let accelerated = acceleratedDeltas(
                deltaX: nextX,
                deltaY: nextY,
                velocityX: velocity.x,
                velocityY: velocity.y,
                sensitivity: configuration.dragSensitivity
            )
            state = .dragging(startTime: startTime, lastTime: time, direction: direction, totalX: nextX, totalY: nextY)
            return GestureDecision(
                commands: [
                    GestureCommand(
                        kind: .drag,
                        phase: .began,
                        direction: direction,
                        deltaX: accelerated.x,
                        deltaY: accelerated.y,
                        velocityX: velocity.x,
                        velocityY: velocity.y,
                        timestamp: time
                    )
                ],
                shouldSuppressOriginal: true
            )

        case let .dragging(startTime, lastTime, direction, totalX, totalY):
            let nextX = totalX + deltaX
            let nextY = totalY + deltaY
            let velocity = velocity(deltaX: deltaX, deltaY: deltaY, previousTime: lastTime, time: time)
            lastVelocityX = velocity.x
            lastVelocityY = velocity.y

            let accelerated = acceleratedDeltas(
                deltaX: deltaX,
                deltaY: deltaY,
                velocityX: velocity.x,
                velocityY: velocity.y,
                sensitivity: configuration.dragSensitivity
            )
            state = .dragging(startTime: startTime, lastTime: time, direction: direction, totalX: nextX, totalY: nextY)
            return GestureDecision(
                commands: [
                    GestureCommand(
                        kind: .drag,
                        phase: .changed,
                        direction: direction,
                        deltaX: accelerated.x,
                        deltaY: accelerated.y,
                        velocityX: velocity.x,
                        velocityY: velocity.y,
                        timestamp: time
                    )
                ],
                shouldSuppressOriginal: true
            )

        case .wheeling:
            return GestureDecision(shouldSuppressOriginal: true)
        }
    }

    private mutating func handleWheel(deltaX: Double, deltaY: Double, time: TimeInterval) -> GestureDecision {
        switch state {
        case .idle:
            return GestureDecision(shouldSuppressOriginal: false)

        case let .armed(startTime, _, _, _):
            let accelerated = acceleratedDeltas(
                deltaX: deltaX,
                deltaY: deltaY,
                velocityX: 0,
                velocityY: 0,
                sensitivity: configuration.wheelSensitivity
            )
            state = .wheeling(startTime: startTime, lastTime: time)
            return GestureDecision(
                commands: [
                    GestureCommand(
                        kind: .wheel,
                        phase: .began,
                        direction: nil,
                        deltaX: accelerated.x,
                        deltaY: accelerated.y,
                        velocityX: 0,
                        velocityY: 0,
                        timestamp: time
                    )
                ],
                shouldSuppressOriginal: true
            )

        case let .wheeling(startTime, lastTime):
            let velocity = velocity(deltaX: deltaX, deltaY: deltaY, previousTime: lastTime, time: time)
            lastVelocityX = velocity.x
            lastVelocityY = velocity.y
            let accelerated = acceleratedDeltas(
                deltaX: deltaX,
                deltaY: deltaY,
                velocityX: velocity.x,
                velocityY: velocity.y,
                sensitivity: configuration.wheelSensitivity
            )
            state = .wheeling(startTime: startTime, lastTime: time)
            return GestureDecision(
                commands: [
                    GestureCommand(
                        kind: .wheel,
                        phase: .changed,
                        direction: nil,
                        deltaX: accelerated.x,
                        deltaY: accelerated.y,
                        velocityX: velocity.x,
                        velocityY: velocity.y,
                        timestamp: time
                    )
                ],
                shouldSuppressOriginal: true
            )

        case .dragging:
            return GestureDecision(shouldSuppressOriginal: true)
        }
    }

    private mutating func finish(at time: TimeInterval, cancelled: Bool) -> GestureDecision {
        let finishedState = state
        state = .idle

        switch finishedState {
        case .idle:
            return GestureDecision(shouldSuppressOriginal: false)

        case .armed:
            return GestureDecision(shouldSuppressOriginal: true)

        case let .dragging(_, _, direction, _, _):
            return GestureDecision(
                commands: [
                    GestureCommand(
                        kind: .drag,
                        phase: cancelled ? .cancelled : .ended,
                        direction: direction,
                        deltaX: 0,
                        deltaY: 0,
                        velocityX: lastVelocityX,
                        velocityY: lastVelocityY,
                        timestamp: time
                    )
                ],
                shouldSuppressOriginal: true
            )

        case .wheeling:
            return GestureDecision(
                commands: [
                    GestureCommand(
                        kind: .wheel,
                        phase: cancelled ? .cancelled : .ended,
                        direction: nil,
                        deltaX: 0,
                        deltaY: 0,
                        velocityX: lastVelocityX,
                        velocityY: lastVelocityY,
                        timestamp: time
                    )
                ],
                shouldSuppressOriginal: true
            )
        }
    }

    private func velocity(deltaX: Double, deltaY: Double, previousTime: TimeInterval, time: TimeInterval) -> (x: Double, y: Double) {
        let elapsed = max(time - previousTime, 0.001)
        return (deltaX / elapsed, deltaY / elapsed)
    }

    private func acceleratedDeltas(
        deltaX: Double,
        deltaY: Double,
        velocityX: Double,
        velocityY: Double,
        sensitivity: Double
    ) -> (x: Double, y: Double) {
        let multiplier = accelerationMultiplier(velocityX: velocityX, velocityY: velocityY)
        return (deltaX * sensitivity * multiplier, deltaY * sensitivity * multiplier)
    }

    private func accelerationMultiplier(velocityX: Double, velocityY: Double) -> Double {
        let acceleration = configuration.acceleration
        guard acceleration.isEnabled,
              acceleration.thresholdVelocity > 0,
              acceleration.maximumMultiplier > 1
        else {
            return 1
        }

        let speed = hypot(velocityX, velocityY)
        guard speed > acceleration.thresholdVelocity else {
            return 1
        }

        let normalized = (speed - acceleration.thresholdVelocity) / acceleration.thresholdVelocity
        let exponent = max(acceleration.exponent, 0)
        let extra = pow(normalized, exponent)
        return min(acceleration.maximumMultiplier, 1 + extra)
    }

    private func shouldCancelForTiming(at time: TimeInterval) -> Bool {
        guard let timing = activeTiming else {
            return false
        }

        let cancellation = configuration.cancellation
        if cancellation.maximumDuration > 0, time - timing.startTime > cancellation.maximumDuration {
            return true
        }
        if cancellation.maximumInactivityInterval > 0, time - timing.lastTime > cancellation.maximumInactivityInterval {
            return true
        }
        return false
    }

    private var activeTiming: (startTime: TimeInterval, lastTime: TimeInterval)? {
        switch state {
        case .idle:
            return nil
        case let .armed(startTime, lastTime, _, _):
            return (startTime, lastTime)
        case let .dragging(startTime, lastTime, _, _, _):
            return (startTime, lastTime)
        case let .wheeling(startTime, lastTime):
            return (startTime, lastTime)
        }
    }

}

public enum GestureState: Equatable, Sendable {
    case idle
    case armed(startTime: TimeInterval, lastTime: TimeInterval, totalX: Double, totalY: Double)
    case dragging(startTime: TimeInterval, lastTime: TimeInterval, direction: GestureDirection?, totalX: Double, totalY: Double)
    case wheeling(startTime: TimeInterval, lastTime: TimeInterval)
}
