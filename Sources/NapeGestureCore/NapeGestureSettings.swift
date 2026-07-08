import Foundation

public struct NapeGestureSettings: Codable, Equatable, Sendable {
    public var gesture: GestureConfiguration
    public var targetDeviceAssociation: TargetDeviceAssociationConfiguration
    public var targetDevices: [DeviceMatcher]
    public var requireMatchingTargetDevice: Bool

    public init(
        gesture: GestureConfiguration = .default,
        targetDeviceAssociation: TargetDeviceAssociationConfiguration = .default,
        targetDevices: [DeviceMatcher] = [],
        requireMatchingTargetDevice: Bool = true
    ) {
        self.gesture = gesture
        self.targetDeviceAssociation = targetDeviceAssociation
        self.targetDevices = targetDevices
        self.requireMatchingTargetDevice = requireMatchingTargetDevice
    }

    public static let `default` = NapeGestureSettings()

    public static let template = NapeGestureSettings(
        gesture: GestureConfiguration.default,
        targetDeviceAssociation: .default,
        targetDevices: [
            DeviceMatcher(productContains: "Nape Pro")
        ],
        requireMatchingTargetDevice: true
    )

    private enum CodingKeys: String, CodingKey {
        case gesture
        case targetDeviceAssociation
        case targetDevices
        case requireMatchingTargetDevice
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gesture = try container.decodeIfPresent(GestureConfiguration.self, forKey: .gesture) ?? .default
        targetDeviceAssociation = try container.decodeIfPresent(
            TargetDeviceAssociationConfiguration.self,
            forKey: .targetDeviceAssociation
        ) ?? .default
        targetDevices = try container.decodeIfPresent([DeviceMatcher].self, forKey: .targetDevices) ?? []
        requireMatchingTargetDevice = try container.decodeIfPresent(
            Bool.self,
            forKey: .requireMatchingTargetDevice
        ) ?? true
    }
}
