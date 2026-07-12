import Foundation

public enum SettingsMigration {
    private static let canonicalModeKeys = [
        "button3Mode",
        "button4Mode",
        "button5Mode",
    ]

    private static let deprecatedModeValues: Set<String> = [
        "scrollAndNavigate",
        "spacesAndMissionControl",
        "zoom",
    ]

    private static let deprecatedGestureKeys: Set<String> = [
        "bindings",
        "directionLockRatio",
        "activationButton"
    ]

    private static let deprecatedCancellationKeys: Set<String> = [
        "offAxisCancelRatio"
    ]

    public static func requiresCanonicalRewrite(in data: Data) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let gesture = root["gesture"] as? [String: Any]
        else {
            return false
        }
        if !deprecatedGestureKeys.isDisjoint(with: gesture.keys) {
            return true
        }
        if canonicalModeKeys.contains(where: { key in
            guard let value = gesture[key] as? String else {
                return false
            }
            return deprecatedModeValues.contains(value)
        }) {
            return true
        }
        guard let cancellation = gesture["cancellation"] as? [String: Any] else {
            return false
        }
        return !deprecatedCancellationKeys.isDisjoint(with: cancellation.keys)
    }
}
