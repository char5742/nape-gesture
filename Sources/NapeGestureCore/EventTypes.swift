import Foundation

public enum MouseButton: Int, Codable, Equatable, Hashable, Sendable {
    case left = 0
    case right = 1
    case center = 2
    case button3 = 3
    case button4 = 4
    case button5 = 5

    public init(buttonNumber: Int64) {
        self = MouseButton(rawValue: Int(buttonNumber)) ?? .button3
    }

    public init?(hidButtonUsage: Int) {
        guard hidButtonUsage > 0 else {
            return nil
        }
        self.init(rawValue: hidButtonUsage - 1)
    }
}

public enum GesturePhase: String, Codable, Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
    case momentum
}

public enum GestureDirection: String, Codable, Equatable, Sendable {
    case left
    case right
    case up
    case down

    public static func dominant(deltaX: Double, deltaY: Double) -> GestureDirection {
        if abs(deltaX) >= abs(deltaY) {
            return deltaX < 0 ? .left : .right
        }
        return deltaY < 0 ? .up : .down
    }
}

public enum GestureCommandKind: String, Codable, Equatable, Sendable {
    case drag
    case wheel
    case momentum
}

public struct GestureCommand: Codable, Equatable, Sendable {
    public var kind: GestureCommandKind
    public var phase: GesturePhase
    public var direction: GestureDirection?
    public var deltaX: Double
    public var deltaY: Double
    public var velocityX: Double
    public var velocityY: Double
    public var timestamp: TimeInterval

    public init(
        kind: GestureCommandKind,
        phase: GesturePhase,
        direction: GestureDirection?,
        deltaX: Double,
        deltaY: Double,
        velocityX: Double,
        velocityY: Double,
        timestamp: TimeInterval
    ) {
        self.kind = kind
        self.phase = phase
        self.direction = direction
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.timestamp = timestamp
    }
}

public enum RawInputEvent: Equatable, Sendable {
    case buttonDown(button: MouseButton, time: TimeInterval)
    case buttonUp(button: MouseButton, time: TimeInterval)
    case move(deltaX: Double, deltaY: Double, time: TimeInterval)
    case wheel(deltaX: Double, deltaY: Double, time: TimeInterval)
    case cancel(time: TimeInterval)

    public var time: TimeInterval {
        switch self {
        case let .buttonDown(_, time),
             let .buttonUp(_, time),
             let .move(_, _, time),
             let .wheel(_, _, time),
             let .cancel(time):
            return time
        }
    }
}

public struct GestureDecision: Equatable, Sendable {
    public var commands: [GestureCommand]
    public var shouldSuppressOriginal: Bool

    public init(commands: [GestureCommand] = [], shouldSuppressOriginal: Bool) {
        self.commands = commands
        self.shouldSuppressOriginal = shouldSuppressOriginal
    }
}
