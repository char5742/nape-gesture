import Foundation

public struct GestureConfiguration: Codable, Equatable, Sendable {
    public static let defaultSystemGestureSensitivity = 1.0
    public static let minimumSystemGestureSensitivity = 0.25
    public static let maximumSystemGestureSensitivity = 2.0
    public static let systemGestureSensitivityStep = 0.05

    public var deadZonePoints: Double
    public var dragSensitivity: Double
    public var wheelSensitivity: Double
    public var buttonAssignments: GestureButtonAssignments
    public var systemGestureSensitivity: Double
    public var acceleration: GestureAccelerationConfiguration
    public var cancellation: GestureCancellationConfiguration
    public var momentum: MomentumConfiguration
    var legacyDirectionLockRatio: Double?

    public init(
        deadZonePoints: Double = 8.0,
        dragSensitivity: Double = 1.0,
        wheelSensitivity: Double = 1.0,
        buttonAssignments: GestureButtonAssignments = .default,
        systemGestureSensitivity: Double = GestureConfiguration.defaultSystemGestureSensitivity,
        acceleration: GestureAccelerationConfiguration = .default,
        cancellation: GestureCancellationConfiguration = .default,
        momentum: MomentumConfiguration = .default
    ) {
        self.deadZonePoints = deadZonePoints
        self.dragSensitivity = dragSensitivity
        self.wheelSensitivity = wheelSensitivity
        self.buttonAssignments = buttonAssignments
        self.systemGestureSensitivity = systemGestureSensitivity
        self.acceleration = acceleration
        self.cancellation = cancellation
        self.momentum = momentum
        legacyDirectionLockRatio = nil
    }

    public static let `default` = GestureConfiguration()

    private enum CodingKeys: String, CodingKey {
        case button3Mode
        case button4Mode
        case button5Mode
        case deadZonePoints
        case dragSensitivity
        case wheelSensitivity
        case buttonAssignments
        case systemGestureSensitivity
        case acceleration
        case cancellation
        case momentum
        case activationButton
        case directionLockRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(TrackpadGestureMode.self, forKey: .button3Mode)
        _ = try container.decodeIfPresent(TrackpadGestureMode.self, forKey: .button4Mode)
        _ = try container.decodeIfPresent(TrackpadGestureMode.self, forKey: .button5Mode)
        _ = try container.decodeIfPresent(MouseButton.self, forKey: .activationButton)
        legacyDirectionLockRatio = try container.decodeIfPresent(
            Double.self,
            forKey: .directionLockRatio
        )
        deadZonePoints = try container.decodeIfPresent(Double.self, forKey: .deadZonePoints) ?? 8.0
        dragSensitivity =
            try container.decodeIfPresent(Double.self, forKey: .dragSensitivity) ?? 1.0
        wheelSensitivity =
            try container.decodeIfPresent(Double.self, forKey: .wheelSensitivity) ?? 1.0
        buttonAssignments =
            try container.decodeIfPresent(GestureButtonAssignments.self, forKey: .buttonAssignments)
            ?? .default
        systemGestureSensitivity =
            try container.decodeIfPresent(Double.self, forKey: .systemGestureSensitivity)
            ?? Self.defaultSystemGestureSensitivity
        acceleration =
            try container.decodeIfPresent(
                GestureAccelerationConfiguration.self, forKey: .acceleration)
            ?? .default
        cancellation =
            try container.decodeIfPresent(
                GestureCancellationConfiguration.self, forKey: .cancellation)
            ?? .default
        momentum =
            try container.decodeIfPresent(MomentumConfiguration.self, forKey: .momentum) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(buttonAssignments, forKey: .buttonAssignments)
        try container.encode(systemGestureSensitivity, forKey: .systemGestureSensitivity)
        try container.encode(cancellation, forKey: .cancellation)
    }

    public func mode(for button: MouseButton) -> TrackpadGestureMode {
        buttonAssignments.assignment(for: button)?.legacyMode ?? .none
    }

    public var enabledButtons: Set<MouseButton> {
        GestureButtonAssignments.supportedSourceButtons
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
    var legacyOffAxisCancelRatio: Double?

    public init(
        maximumDuration: TimeInterval = 10.0,
        maximumInactivityInterval: TimeInterval = 2.0
    ) {
        self.maximumDuration = maximumDuration
        self.maximumInactivityInterval = maximumInactivityInterval
        legacyOffAxisCancelRatio = nil
    }

    public static let `default` = GestureCancellationConfiguration()

    private enum CodingKeys: String, CodingKey {
        case maximumDuration
        case maximumInactivityInterval
        case offAxisCancelRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maximumDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .maximumDuration
        ) ?? 10.0
        maximumInactivityInterval = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .maximumInactivityInterval
        ) ?? 2.0
        legacyOffAxisCancelRatio = try container.decodeIfPresent(
            Double.self,
            forKey: .offAxisCancelRatio
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maximumDuration, forKey: .maximumDuration)
        try container.encode(maximumInactivityInterval, forKey: .maximumInactivityInterval)
    }
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
