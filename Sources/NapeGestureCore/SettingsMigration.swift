import Foundation

public enum SettingsMigration {
    private static let deprecatedGestureKeys: Set<String> = [
        "acceleration",
        "actions",
        "activationButton",
        "applicationBindings",
        "applicationSettings",
        "bindings",
        "button3Mode",
        "button4Mode",
        "button5Mode",
        "buttonAssignments",
        "deadZonePoints",
        "directionBindings",
        "directionLockRatio",
        "dragSensitivity",
        "mode",
        "momentum",
        "wheelSensitivity",
    ]

    private static let deprecatedCancellationKeys: Set<String> = [
        "offAxisCancelRatio"
    ]

    private static let deprecatedTopLevelKeys: Set<String> = [
        "applicationBindings",
        "applicationSettings",
        "applicationOverrides",
        "applications",
    ]

    public static func requiresCanonicalRewrite(in data: Data) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if !deprecatedTopLevelKeys.isDisjoint(with: root.keys) {
            return true
        }

        guard let gestureValue = root["gesture"] else {
            return false
        }
        guard let gesture = gestureValue as? [String: Any] else {
            return false
        }
        if !deprecatedGestureKeys.isDisjoint(with: gesture.keys) {
            return true
        }
        guard let cancellation = gesture["cancellation"] as? [String: Any] else {
            return false
        }
        return !deprecatedCancellationKeys.isDisjoint(with: cancellation.keys)
    }
}
