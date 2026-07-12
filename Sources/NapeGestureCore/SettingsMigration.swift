import Foundation

public enum SettingsMigration {
    private static let deprecatedGestureKeys: Set<String> = [
        "bindings",
        "directionLockRatio"
    ]

    private static let deprecatedCancellationKeys: Set<String> = [
        "offAxisCancelRatio"
    ]

    public static func containsDeprecatedGestureKeys(in data: Data) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gesture = root["gesture"] as? [String: Any]
        else {
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
