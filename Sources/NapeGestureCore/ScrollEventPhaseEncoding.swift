import Foundation

public struct ScrollEventPhaseEncoding: Equatable, Sendable {
    public var scrollPhase: GesturePhase?
    public var momentumPhase: GesturePhase?

    public init(scrollPhase: GesturePhase?, momentumPhase: GesturePhase?) {
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
    }
}

public enum ScrollEventPhaseEncoder {
    public static func encode(command: GestureCommand) -> ScrollEventPhaseEncoding {
        switch command.kind {
        case .drag, .wheel:
            if command.phase == .momentum {
                return ScrollEventPhaseEncoding(scrollPhase: nil, momentumPhase: .changed)
            }
            return ScrollEventPhaseEncoding(scrollPhase: command.phase, momentumPhase: nil)
        case .momentum:
            return ScrollEventPhaseEncoding(
                scrollPhase: nil,
                momentumPhase: normalizedMomentumPhase(command.phase)
            )
        }
    }

    private static func normalizedMomentumPhase(_ phase: GesturePhase) -> GesturePhase {
        switch phase {
        case .momentum:
            return .changed
        case .began, .changed, .ended, .cancelled:
            return phase
        }
    }
}
