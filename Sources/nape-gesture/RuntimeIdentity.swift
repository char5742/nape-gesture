import Foundation

enum RuntimeLaunchContext: String, Codable {
    case launchServicesApp
    case commandLine
}

struct RuntimeIdentity: Codable {
    var processName: String
    var executablePath: String
    var bundleIdentifier: String?
    var bundlePath: String
    var isAppBundle: Bool
    var launchContext: RuntimeLaunchContext

    static var current: RuntimeIdentity {
        let bundlePath = Bundle.main.bundlePath
        let xpcServiceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]
        let launchContext: RuntimeLaunchContext =
            xpcServiceName?.hasPrefix("application.") == true
            ? .launchServicesApp
            : .commandLine
        return RuntimeIdentity(
            processName: ProcessInfo.processInfo.processName,
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments.first ?? "不明",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            bundlePath: bundlePath,
            isAppBundle: bundlePath.hasSuffix(".app"),
            launchContext: launchContext
        )
    }

    var tccAttribution: String {
        launchContext == .launchServicesApp && isAppBundle ? "appBundle" : "invokingProcess"
    }

    var permissionTargetDescription: String {
        if tccAttribution == "appBundle" {
            if let bundleIdentifier {
                return "\(bundlePath) (bundle ID: \(bundleIdentifier))"
            }
            return bundlePath
        }
        if isAppBundle {
            return "実行元ターミナルまたは親アプリ (CLI: \(executablePath))"
        }
        return executablePath
    }
}
