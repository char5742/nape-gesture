import Foundation

public struct MacGestureSettings: Codable, Equatable, Sendable {
    public var gesture: GestureConfiguration
    public var targetDevices: [DeviceMatcher]
    public var requireMatchingTargetDevice: Bool

    public init(
        gesture: GestureConfiguration = .default,
        targetDevices: [DeviceMatcher] = [],
        requireMatchingTargetDevice: Bool = true
    ) {
        self.gesture = gesture
        self.targetDevices = targetDevices
        self.requireMatchingTargetDevice = requireMatchingTargetDevice
    }

    public static let `default` = MacGestureSettings()

    public static let template = MacGestureSettings(
        gesture: GestureConfiguration.default,
        targetDevices: [
            DeviceMatcher(productContains: "Nape Pro")
        ],
        requireMatchingTargetDevice: true
    )
}
