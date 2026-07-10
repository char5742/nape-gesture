import Foundation

public enum ScrollGenerationPlanner {
    public static let maximumCommandCount = 100_000

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
        guard deltaX.isFinite,
              deltaY.isFinite,
              steps > 0,
              interval.isFinite,
              interval > 0,
              momentumSteps >= 0,
              momentumDecay.isFinite,
              (0...1).contains(momentumDecay),
              momentumScale.isFinite,
              momentumScale >= 0,
              startTime.isFinite
        else {
            return []
        }

        let generatedMomentumCount = momentumSteps > 0 && momentumScale > 0
            ? momentumSteps
            : 0
        let (nonTerminalCommandCount, countOverflowed) = steps.addingReportingOverflow(
            generatedMomentumCount
        )
        let includesMomentumTerminal = generatedMomentumCount > 0
        let (commandCount, terminalOverflowed) = nonTerminalCommandCount.addingReportingOverflow(
            includesMomentumTerminal ? 1 : 0
        )
        guard !countOverflowed,
              !terminalOverflowed,
              commandCount <= maximumCommandCount
        else {
            return []
        }

        let stepDeltaX = deltaX / Double(steps)
        let stepDeltaY = deltaY / Double(steps)
        let stepVelocityX = stepDeltaX / interval
        let stepVelocityY = stepDeltaY / interval
        guard stepDeltaX.isFinite,
              stepDeltaY.isFinite,
              stepVelocityX.isFinite,
              stepVelocityY.isFinite
        else {
            return []
        }
        var commands: [GestureCommand] = []
        commands.reserveCapacity(commandCount)

        for index in 0..<steps {
            let timestamp = startTime + Double(commands.count) * interval
            guard timestamp.isFinite,
                  MonotonicEventClock.timestampNanoseconds(
                    fromSecondsSinceStartup: timestamp
                  ) != nil
            else {
                return []
            }
            commands.append(
                GestureCommand(
                    kind: .wheel,
                    phase: phaseOverride ?? automaticPhase(index: index, count: steps),
                    direction: nil,
                    deltaX: stepDeltaX,
                    deltaY: stepDeltaY,
                    velocityX: stepVelocityX,
                    velocityY: stepVelocityY,
                    timestamp: timestamp
                )
            )
        }

        guard generatedMomentumCount > 0 else {
            return commands
        }

        for index in 0..<generatedMomentumCount {
            let factor = momentumScale * pow(momentumDecay, Double(index))
            let momentumDeltaX = stepDeltaX * factor
            let momentumDeltaY = stepDeltaY * factor
            let momentumVelocityX = momentumDeltaX / interval
            let momentumVelocityY = momentumDeltaY / interval
            let timestamp = startTime + Double(commands.count) * interval
            guard factor.isFinite,
                  momentumDeltaX.isFinite,
                  momentumDeltaY.isFinite,
                  momentumVelocityX.isFinite,
                  momentumVelocityY.isFinite,
                  timestamp.isFinite,
                  MonotonicEventClock.timestampNanoseconds(
                    fromSecondsSinceStartup: timestamp
                  ) != nil
            else {
                return []
            }
            commands.append(
                GestureCommand(
                    kind: .momentum,
                    phase: .momentum,
                    direction: nil,
                    deltaX: momentumDeltaX,
                    deltaY: momentumDeltaY,
                    velocityX: momentumVelocityX,
                    velocityY: momentumVelocityY,
                    timestamp: timestamp
                )
            )
        }

        let terminalTimestamp = startTime + Double(commands.count) * interval
        guard terminalTimestamp.isFinite,
              MonotonicEventClock.timestampNanoseconds(
                fromSecondsSinceStartup: terminalTimestamp
              ) != nil
        else {
            return []
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
                timestamp: terminalTimestamp
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
