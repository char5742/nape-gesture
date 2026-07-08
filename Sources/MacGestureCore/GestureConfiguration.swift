import Foundation

public struct GestureConfiguration: Codable, Equatable, Sendable {
    public var activationButton: MouseButton
    public var deadZonePoints: Double
    public var directionLockRatio: Double
    public var dragSensitivity: Double
    public var wheelSensitivity: Double
    public var acceleration: GestureAccelerationConfiguration
    public var cancellation: GestureCancellationConfiguration
    public var momentum: MomentumConfiguration
    public var bindings: GestureBindings

    public init(
        activationButton: MouseButton = .button4,
        deadZonePoints: Double = 8.0,
        directionLockRatio: Double = 1.35,
        dragSensitivity: Double = 1.0,
        wheelSensitivity: Double = 1.0,
        acceleration: GestureAccelerationConfiguration = .default,
        cancellation: GestureCancellationConfiguration = .default,
        momentum: MomentumConfiguration = .default,
        bindings: GestureBindings = .default
    ) {
        self.activationButton = activationButton
        self.deadZonePoints = deadZonePoints
        self.directionLockRatio = directionLockRatio
        self.dragSensitivity = dragSensitivity
        self.wheelSensitivity = wheelSensitivity
        self.acceleration = acceleration
        self.cancellation = cancellation
        self.momentum = momentum
        self.bindings = bindings
    }

    public static let `default` = GestureConfiguration()

    private enum CodingKeys: String, CodingKey {
        case activationButton
        case deadZonePoints
        case directionLockRatio
        case dragSensitivity
        case wheelSensitivity
        case acceleration
        case cancellation
        case momentum
        case bindings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationButton = try container.decodeIfPresent(MouseButton.self, forKey: .activationButton) ?? .button4
        deadZonePoints = try container.decodeIfPresent(Double.self, forKey: .deadZonePoints) ?? 8.0
        directionLockRatio = try container.decodeIfPresent(Double.self, forKey: .directionLockRatio) ?? 1.35
        dragSensitivity = try container.decodeIfPresent(Double.self, forKey: .dragSensitivity) ?? 1.0
        wheelSensitivity = try container.decodeIfPresent(Double.self, forKey: .wheelSensitivity) ?? 1.0
        acceleration = try container.decodeIfPresent(GestureAccelerationConfiguration.self, forKey: .acceleration) ?? .default
        cancellation = try container.decodeIfPresent(GestureCancellationConfiguration.self, forKey: .cancellation) ?? .default
        momentum = try container.decodeIfPresent(MomentumConfiguration.self, forKey: .momentum) ?? .default
        bindings = try container.decodeIfPresent(GestureBindings.self, forKey: .bindings) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activationButton, forKey: .activationButton)
        try container.encode(deadZonePoints, forKey: .deadZonePoints)
        try container.encode(directionLockRatio, forKey: .directionLockRatio)
        try container.encode(dragSensitivity, forKey: .dragSensitivity)
        try container.encode(wheelSensitivity, forKey: .wheelSensitivity)
        try container.encode(acceleration, forKey: .acceleration)
        try container.encode(cancellation, forKey: .cancellation)
        try container.encode(momentum, forKey: .momentum)
        try container.encode(bindings, forKey: .bindings)
    }
}

public struct GestureAccelerationConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var thresholdVelocity: Double
    public var exponent: Double
    public var maximumMultiplier: Double

    public init(
        isEnabled: Bool = false,
        thresholdVelocity: Double = 900.0,
        exponent: Double = 1.2,
        maximumMultiplier: Double = 3.0
    ) {
        self.isEnabled = isEnabled
        self.thresholdVelocity = thresholdVelocity
        self.exponent = exponent
        self.maximumMultiplier = maximumMultiplier
    }

    public static let `default` = GestureAccelerationConfiguration()
}

public struct GestureCancellationConfiguration: Codable, Equatable, Sendable {
    public var maximumDuration: TimeInterval
    public var maximumInactivityInterval: TimeInterval
    public var offAxisCancelRatio: Double

    public init(
        maximumDuration: TimeInterval = 10.0,
        maximumInactivityInterval: TimeInterval = 2.0,
        offAxisCancelRatio: Double = 2.5
    ) {
        self.maximumDuration = maximumDuration
        self.maximumInactivityInterval = maximumInactivityInterval
        self.offAxisCancelRatio = offAxisCancelRatio
    }

    public static let `default` = GestureCancellationConfiguration()
}

public struct MomentumConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var minimumStartVelocity: Double
    public var stopVelocity: Double
    public var decayPerSecond: Double
    public var frameInterval: TimeInterval

    public init(
        isEnabled: Bool = true,
        minimumStartVelocity: Double = 140.0,
        stopVelocity: Double = 8.0,
        decayPerSecond: Double = 0.08,
        frameInterval: TimeInterval = 1.0 / 120.0
    ) {
        self.isEnabled = isEnabled
        self.minimumStartVelocity = minimumStartVelocity
        self.stopVelocity = stopVelocity
        self.decayPerSecond = decayPerSecond
        self.frameInterval = frameInterval
    }

    public static let `default` = MomentumConfiguration()
}
