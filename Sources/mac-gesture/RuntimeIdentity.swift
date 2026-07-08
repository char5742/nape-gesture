import Foundation

struct RuntimeIdentity: Codable {
    var processName: String
    var executablePath: String
    var bundleIdentifier: String?
    var bundlePath: String
    var isAppBundle: Bool

    static var current: RuntimeIdentity {
        let bundlePath = Bundle.main.bundlePath
        return RuntimeIdentity(
            processName: ProcessInfo.processInfo.processName,
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments.first ?? "不明",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            bundlePath: bundlePath,
            isAppBundle: bundlePath.hasSuffix(".app")
        )
    }

    var permissionTargetDescription: String {
        if isAppBundle {
            if let bundleIdentifier {
                return "\(bundlePath) (bundle ID: \(bundleIdentifier))"
            }
            return bundlePath
        }
        return executablePath
    }
}
