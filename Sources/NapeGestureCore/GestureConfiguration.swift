import Foundation

public struct GestureConfiguration: Codable, Equatable, Sendable {
    public var button3Mode: TrackpadGestureMode
    public var button4Mode: TrackpadGestureMode
    public var button5Mode: TrackpadGestureMode
    public var deadZonePoints: Double
    public var dragSensitivity: Double
    public var wheelSensitivity: Double
    public var acceleration: GestureAccelerationConfiguration
    public var cancellation: GestureCancellationConfiguration
    public var momentum: MomentumConfiguration

    public init(
        button3Mode: TrackpadGestureMode = .scrollAndNavigate,
        button4Mode: TrackpadGestureMode = .spacesAndMissionControl,
        button5Mode: TrackpadGestureMode = .zoom,
        deadZonePoints: Double = 8.0,
        dragSensitivity: Double = 1.0,
        wheelSensitivity: Double = 1.0,
        acceleration: GestureAccelerationConfiguration = .default,
        cancellation: GestureCancellationConfiguration = .default,
        momentum: MomentumConfiguration = .default
    ) {
        self.button3Mode = button3Mode
        self.button4Mode = button4Mode
        self.button5Mode = button5Mode
        self.deadZonePoints = deadZonePoints
        self.dragSensitivity = dragSensitivity
        self.wheelSensitivity = wheelSensitivity
        self.acceleration = acceleration
        self.cancellation = cancellation
        self.momentum = momentum
    }

    public static let `default` = GestureConfiguration()

    private enum CodingKeys: String, CodingKey {
        case button3Mode
        case button4Mode
        case button5Mode
        case deadZonePoints
        case dragSensitivity
        case wheelSensitivity
        case acceleration
        case cancellation
        case momentum
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasCanonicalModes = container.contains(.button3Mode)
            || container.contains(.button4Mode)
            || container.contains(.button5Mode)
        if hasCanonicalModes {
            button3Mode = try container.decodeIfPresent(TrackpadGestureMode.self, forKey: .button3Mode) ?? .scrollAndNavigate
            button4Mode = try container.decodeIfPresent(TrackpadGestureMode.self, forKey: .button4Mode) ?? .spacesAndMissionControl
            button5Mode = try container.decodeIfPresent(TrackpadGestureMode.self, forKey: .button5Mode) ?? .zoom
        } else {
            button3Mode = .scrollAndNavigate
            button4Mode = .spacesAndMissionControl
            button5Mode = .zoom
        }
        deadZonePoints = try container.decodeIfPresent(Double.self, forKey: .deadZonePoints) ?? 8.0
        dragSensitivity = try container.decodeIfPresent(Double.self, forKey: .dragSensitivity) ?? 1.0
        wheelSensitivity = try container.decodeIfPresent(Double.self, forKey: .wheelSensitivity) ?? 1.0
        acceleration = try container.decodeIfPresent(GestureAccelerationConfiguration.self, forKey: .acceleration) ?? .default
        cancellation = try container.decodeIfPresent(GestureCancellationConfiguration.self, forKey: .cancellation) ?? .default
        momentum = try container.decodeIfPresent(MomentumConfiguration.self, forKey: .momentum) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(button3Mode, forKey: .button3Mode)
        try container.encode(button4Mode, forKey: .button4Mode)
        try container.encode(button5Mode, forKey: .button5Mode)
        try container.encode(deadZonePoints, forKey: .deadZonePoints)
        try container.encode(dragSensitivity, forKey: .dragSensitivity)
        try container.encode(wheelSensitivity, forKey: .wheelSensitivity)
        try container.encode(acceleration, forKey: .acceleration)
        try container.encode(cancellation, forKey: .cancellation)
        try container.encode(momentum, forKey: .momentum)
    }

    public func mode(for button: MouseButton) -> TrackpadGestureMode {
        switch button {
        case .button3: button3Mode
        case .button4: button4Mode
        case .button5: button5Mode
        case .left, .right, .center: .none
        }
    }

    public var enabledButtons: Set<MouseButton> {
        Set([MouseButton.button3, .button4, .button5].filter { mode(for: $0) != .none })
    }

    public var enabledModes: Set<TrackpadGestureMode> {
        Set([button3Mode, button4Mode, button5Mode].filter { $0 != .none })
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

    public init(
        maximumDuration: TimeInterval = 10.0,
        maximumInactivityInterval: TimeInterval = 2.0
    ) {
        self.maximumDuration = maximumDuration
        self.maximumInactivityInterval = maximumInactivityInterval
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
