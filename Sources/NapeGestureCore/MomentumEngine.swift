import Foundation

public struct MomentumEngine: Sendable {
    public private(set) var state: MomentumState = .idle
    private let configuration: MomentumConfiguration

    public init(configuration: MomentumConfiguration = .default) {
        self.configuration = configuration
    }

    public mutating func start(from command: GestureCommand) {
        guard configuration.isEnabled else {
            state = .idle
            return
        }

        let speed = hypot(command.velocityX, command.velocityY)
        guard speed >= configuration.minimumStartVelocity else {
            state = .idle
            return
        }

        state = .running(
            lastTime: command.timestamp,
            velocityX: command.velocityX,
            velocityY: command.velocityY,
            direction: command.direction
        )
    }

    public mutating func tick(at time: TimeInterval) -> GestureCommand? {
        guard case let .running(lastTime, velocityX, velocityY, direction) = state else {
            return nil
        }

        let elapsed = max(time - lastTime, configuration.frameInterval)
        let decay = pow(configuration.decayPerSecond, elapsed)
        let nextVelocityX = velocityX * decay
        let nextVelocityY = velocityY * decay
        let speed = hypot(nextVelocityX, nextVelocityY)

        guard speed >= configuration.stopVelocity else {
            state = .idle
            return GestureCommand(
                kind: .momentum,
                phase: .ended,
                direction: direction,
                deltaX: 0,
                deltaY: 0,
                velocityX: 0,
                velocityY: 0,
                timestamp: time
            )
        }

        state = .running(
            lastTime: time,
            velocityX: nextVelocityX,
            velocityY: nextVelocityY,
            direction: direction
        )

        return GestureCommand(
            kind: .momentum,
            phase: .momentum,
            direction: direction,
            deltaX: nextVelocityX * elapsed,
            deltaY: nextVelocityY * elapsed,
            velocityX: nextVelocityX,
            velocityY: nextVelocityY,
            timestamp: time
        )
    }
}

public enum MomentumState: Equatable, Sendable {
    case idle
    case running(lastTime: TimeInterval, velocityX: Double, velocityY: Double, direction: GestureDirection?)
}
