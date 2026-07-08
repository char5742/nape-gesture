import Foundation

public struct NapeGestureSettings: Codable, Equatable, Sendable {
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

    public static let `default` = NapeGestureSettings()

    public static let template = NapeGestureSettings(
        gesture: GestureConfiguration.default,
        targetDevices: [
            DeviceMatcher(productContains: "Nape Pro")
        ],
        requireMatchingTargetDevice: true
    )
}
