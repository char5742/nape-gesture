import Foundation

public struct SettingsValidationIssue: Codable, Equatable, Sendable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public enum SettingsValidator {
    public static func issues(for settings: NapeGestureSettings) -> [SettingsValidationIssue] {
        var issues: [SettingsValidationIssue] = []
        validateCanonicalGesture(settings.gesture, issues: &issues)
        validate(settings.targetDeviceAssociation, issues: &issues)
        validateTargetDevices(settings, issues: &issues)
        return issues
    }

    public static func migrationIssues(
        for settings: NapeGestureSettings
    ) -> [SettingsValidationIssue] {
        var issues = issues(for: settings)
        validateLegacyGesture(settings.gesture, issues: &issues)
        return issues
    }

    public static func isValid(_ settings: NapeGestureSettings) -> Bool {
        issues(for: settings).isEmpty
    }

    private static func validateCanonicalGesture(
        _ gesture: GestureConfiguration,
        issues: inout [SettingsValidationIssue]
    ) {
        let cancellation = gesture.cancellation
        requireFinite(cancellation.maximumDuration, path: "gesture.cancellation.maximumDuration", message: "0以上の有限値にしてください。0で無効化できます。", issues: &issues) { $0 >= 0 }
        requireFinite(cancellation.maximumInactivityInterval, path: "gesture.cancellation.maximumInactivityInterval", message: "0以上の有限値にしてください。0で無効化できます。", issues: &issues) { $0 >= 0 }
    }

    private static func validateLegacyGesture(
        _ gesture: GestureConfiguration,
        issues: inout [SettingsValidationIssue]
    ) {
        requireFinite(gesture.deadZonePoints, path: "gesture.deadZonePoints", message: "0以上の有限値にしてください。", issues: &issues) { $0 >= 0 }
        requireFinite(gesture.dragSensitivity, path: "gesture.dragSensitivity", message: "0より大きい有限値にしてください。", issues: &issues) { $0 > 0 }
        requireFinite(gesture.wheelSensitivity, path: "gesture.wheelSensitivity", message: "0より大きい有限値にしてください。", issues: &issues) { $0 > 0 }

        if let directionLockRatio = gesture.legacyDirectionLockRatio {
            requireFinite(directionLockRatio, path: "gesture.directionLockRatio", message: "1以上の有限値にしてください。", issues: &issues) { $0 >= 1 }
        }

        let acceleration = gesture.acceleration
        requireFinite(acceleration.thresholdVelocity, path: "gesture.acceleration.thresholdVelocity", message: "0以上の有限値にしてください。", issues: &issues) { $0 >= 0 }
        requireFinite(acceleration.exponent, path: "gesture.acceleration.exponent", message: "0以上の有限値にしてください。", issues: &issues) { $0 >= 0 }
        requireFinite(acceleration.maximumMultiplier, path: "gesture.acceleration.maximumMultiplier", message: "1以上の有限値にしてください。", issues: &issues) { $0 >= 1 }

        if let offAxisCancelRatio = gesture.cancellation.legacyOffAxisCancelRatio {
            requireFinite(offAxisCancelRatio, path: "gesture.cancellation.offAxisCancelRatio", message: "0以上の有限値にしてください。", issues: &issues) { $0 >= 0 }
        }

        let momentum = gesture.momentum
        requireFinite(momentum.minimumStartVelocity, path: "gesture.momentum.minimumStartVelocity", message: "0以上の有限値にしてください。", issues: &issues) { $0 >= 0 }
        requireFinite(momentum.stopVelocity, path: "gesture.momentum.stopVelocity", message: "0以上の有限値にしてください。", issues: &issues) { $0 >= 0 }
        requireFinite(momentum.decayPerSecond, path: "gesture.momentum.decayPerSecond", message: "0より大きく1以下の有限値にしてください。", issues: &issues) { $0 > 0 && $0 <= 1 }
        requireFinite(momentum.frameInterval, path: "gesture.momentum.frameInterval", message: "0より大きい有限値にしてください。", issues: &issues) { $0 > 0 }
    }

    private static func validate(_ association: TargetDeviceAssociationConfiguration, issues: inout [SettingsValidationIssue]) {
        requireFinite(
            association.associationWindow,
            path: "targetDeviceAssociation.associationWindow",
            message: "0より大きい有限値にしてください。",
            issues: &issues
        ) { $0 > 0 }
    }

    private static func validateTargetDevices(_ settings: NapeGestureSettings, issues: inout [SettingsValidationIssue]) {
        if settings.requireMatchingTargetDevice && settings.targetDevices.isEmpty {
            issues.append(
                SettingsValidationIssue(
                    path: "targetDevices",
                    message: "対象デバイス一致が必須の場合は、対象デバイス条件を1つ以上設定してください。"
                )
            )
        }

        for (index, matcher) in settings.targetDevices.enumerated() {
            let prefix = "targetDevices[\(index)]"
            if !matcher.hasAnyCondition {
                issues.append(SettingsValidationIssue(path: prefix, message: "空の対象デバイス条件は使用できません。"))
            }
            requireOptionalNonNegative(matcher.vendorID, path: "\(prefix).vendorID", issues: &issues)
            requireOptionalNonNegative(matcher.productID, path: "\(prefix).productID", issues: &issues)
            requireOptionalNonNegative(matcher.primaryUsagePage, path: "\(prefix).primaryUsagePage", issues: &issues)
            requireOptionalNonNegative(matcher.primaryUsage, path: "\(prefix).primaryUsage", issues: &issues)
        }
    }

    private static func requireFinite(
        _ value: Double,
        path: String,
        message: String,
        issues: inout [SettingsValidationIssue],
        _ predicate: (Double) -> Bool
    ) {
        if !value.isFinite || !predicate(value) {
            issues.append(SettingsValidationIssue(path: path, message: message))
        }
    }

    private static func requireOptionalNonNegative(_ value: Int?, path: String, issues: inout [SettingsValidationIssue]) {
        guard let value, value < 0 else {
            return
        }
        issues.append(SettingsValidationIssue(path: path, message: "0以上にしてください。"))
    }
}
