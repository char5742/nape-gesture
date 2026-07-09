import Foundation

public struct TargetDeviceGateConfiguration: Codable, Equatable, Sendable {
    public var activationButton: MouseButton
    public var associationWindow: TimeInterval

    public init(
        activationButton: MouseButton,
        associationWindow: TimeInterval = TargetDeviceAssociationConfiguration.defaultAssociationWindow
    ) {
        self.activationButton = activationButton
        self.associationWindow = associationWindow
    }

    public init(settings: NapeGestureSettings) {
        self.init(
            activationButton: settings.gesture.activationButton,
            associationWindow: settings.targetDeviceAssociation.associationWindow
        )
    }
}

public struct TargetDeviceAssociationConfiguration: Codable, Equatable, Sendable {
    public static let defaultAssociationWindow: TimeInterval = 0.12

    public var associationWindow: TimeInterval

    public init(
        associationWindow: TimeInterval = Self.defaultAssociationWindow
    ) {
        self.associationWindow = associationWindow
    }

    public static let `default` = TargetDeviceAssociationConfiguration()
}

public enum TargetDeviceActivity: Equatable, Sendable {
    case buttonDown(button: MouseButton, time: TimeInterval)
    case buttonUp(button: MouseButton, time: TimeInterval)
    case pointer(deltaX: Double, deltaY: Double, time: TimeInterval)
    case wheel(deltaX: Double, deltaY: Double, time: TimeInterval)

    public var time: TimeInterval {
        switch self {
        case let .buttonDown(_, time),
             let .buttonUp(_, time),
             let .pointer(_, _, time),
             let .wheel(_, _, time):
            return time
        }
    }
}

public struct TargetDeviceGateState: Equatable, Sendable {
    public private(set) var activeButtons: Set<MouseButton> = []
    public private(set) var lastTargetActivityTime: TimeInterval?

    private let configuration: TargetDeviceGateConfiguration

    public init(configuration: TargetDeviceGateConfiguration) {
        self.configuration = configuration
    }

    public mutating func record(_ activity: TargetDeviceActivity) {
        lastTargetActivityTime = activity.time

        switch activity {
        case let .buttonDown(button, _):
            activeButtons.insert(button)
        case let .buttonUp(button, _):
            activeButtons.remove(button)
        case .pointer, .wheel:
            break
        }
    }

    public func shouldHandle(_ event: RawInputEvent) -> Bool {
        switch event {
        case let .buttonDown(button, time):
            return button == configuration.activationButton && hasRecentTargetActivity(at: time)
        case let .buttonUp(button, time):
            return button == configuration.activationButton
                && (activeButtons.contains(configuration.activationButton) || hasRecentTargetActivity(at: time))
        case let .move(_, _, time), let .wheel(_, _, time):
            return hasRecentTargetActivity(at: time)
        case .cancel:
            return true
        }
    }

    private func hasRecentTargetActivity(at time: TimeInterval) -> Bool {
        guard let lastTargetActivityTime else {
            return false
        }
        return abs(time - lastTargetActivityTime) <= configuration.associationWindow
    }
}
