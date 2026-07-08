import Foundation

public enum ScrollGenerationPlanner {
    public static func makeCommands(
        deltaX: Double,
        deltaY: Double,
        steps: Int,
        interval: TimeInterval,
        phaseOverride: GesturePhase?,
        momentumSteps: Int,
        momentumDecay: Double,
        momentumScale: Double,
        startTime: TimeInterval
    ) -> [GestureCommand] {
        guard steps > 0, interval > 0, momentumSteps >= 0 else {
            return []
        }

        let stepDeltaX = deltaX / Double(steps)
        let stepDeltaY = deltaY / Double(steps)
        var commands: [GestureCommand] = []

        for index in 0..<steps {
            commands.append(
                GestureCommand(
                    kind: .wheel,
                    phase: phaseOverride ?? automaticPhase(index: index, count: steps),
                    direction: nil,
                    deltaX: stepDeltaX,
                    deltaY: stepDeltaY,
                    velocityX: stepDeltaX / interval,
                    velocityY: stepDeltaY / interval,
                    timestamp: startTime + Double(commands.count) * interval
                )
            )
        }

        guard momentumSteps > 0, momentumScale > 0 else {
            return commands
        }

        for index in 0..<momentumSteps {
            let factor = momentumScale * pow(momentumDecay, Double(index))
            let momentumDeltaX = stepDeltaX * factor
            let momentumDeltaY = stepDeltaY * factor
            commands.append(
                GestureCommand(
                    kind: .momentum,
                    phase: .momentum,
                    direction: nil,
                    deltaX: momentumDeltaX,
                    deltaY: momentumDeltaY,
                    velocityX: momentumDeltaX / interval,
                    velocityY: momentumDeltaY / interval,
                    timestamp: startTime + Double(commands.count) * interval
                )
            )
        }

        commands.append(
            GestureCommand(
                kind: .momentum,
                phase: .ended,
                direction: nil,
                deltaX: 0,
                deltaY: 0,
                velocityX: 0,
                velocityY: 0,
                timestamp: startTime + Double(commands.count) * interval
            )
        )

        return commands
    }

    private static func automaticPhase(index: Int, count: Int) -> GesturePhase {
        if count == 1 {
            return .changed
        }
        if index == 0 {
            return .began
        }
        if index == count - 1 {
            return .ended
        }
        return .changed
    }
}
