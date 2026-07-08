import Foundation

public enum PermissionRecoveryService: String, Sendable {
    case accessibility
    case inputMonitoring
}

public struct PermissionRecoveryAction: Equatable, Sendable {
    public var service: PermissionRecoveryService
    public var serviceTitle: String
    public var statusTitle: String
    public var settingsButtonTitle: String
    public var settingsURLString: String
    public var shouldOpenSettings: Bool
    public var requiresRestartAfterGrant: Bool

    public init(
        service: PermissionRecoveryService,
        serviceTitle: String,
        statusTitle: String,
        settingsButtonTitle: String,
        settingsURLString: String,
        shouldOpenSettings: Bool,
        requiresRestartAfterGrant: Bool
    ) {
        self.service = service
        self.serviceTitle = serviceTitle
        self.statusTitle = statusTitle
        self.settingsButtonTitle = settingsButtonTitle
        self.settingsURLString = settingsURLString
        self.shouldOpenSettings = shouldOpenSettings
        self.requiresRestartAfterGrant = requiresRestartAfterGrant
    }
}

public struct PermissionRecoveryPresentation: Equatable, Sendable {
    public var permissionTargetDescription: String
    public var restartNotice: String
    public var accessibility: PermissionRecoveryAction
    public var inputMonitoring: PermissionRecoveryAction

    public init(
        permissionTargetDescription: String,
        restartNotice: String,
        accessibility: PermissionRecoveryAction,
        inputMonitoring: PermissionRecoveryAction
    ) {
        self.permissionTargetDescription = permissionTargetDescription
        self.restartNotice = restartNotice
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }
}

public enum PermissionRecoveryPresenter {
    public static let accessibilitySettingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    public static let inputMonitoringSettingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    public static func present(
        accessibilityTrusted: Bool,
        inputMonitoringGranted: Bool?,
        permissionTargetDescription: String
    ) -> PermissionRecoveryPresentation {
        PermissionRecoveryPresentation(
            permissionTargetDescription: permissionTargetDescription,
            restartNotice: "権限変更後は Nape Gesture を再起動してから再確認してください。",
            accessibility: PermissionRecoveryAction(
                service: .accessibility,
                serviceTitle: "アクセシビリティ",
                statusTitle: accessibilityTrusted ? "許可済み" : "未許可",
                settingsButtonTitle: "アクセシビリティ設定を開く",
                settingsURLString: accessibilitySettingsURLString,
                shouldOpenSettings: !accessibilityTrusted,
                requiresRestartAfterGrant: true
            ),
            inputMonitoring: PermissionRecoveryAction(
                service: .inputMonitoring,
                serviceTitle: "入力監視",
                statusTitle: inputMonitoringStatusTitle(inputMonitoringGranted),
                settingsButtonTitle: "入力監視設定を開く",
                settingsURLString: inputMonitoringSettingsURLString,
                shouldOpenSettings: inputMonitoringGranted != true,
                requiresRestartAfterGrant: true
            )
        )
    }

    private static func inputMonitoringStatusTitle(_ granted: Bool?) -> String {
        switch granted {
        case .some(true):
            return "許可済み"
        case .some(false):
            return "未許可または開始失敗"
        case .none:
            return "未判定"
        }
    }
}
