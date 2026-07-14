import Darwin
import Foundation

enum RuntimeLaunchContext: String, Codable {
    case launchServicesApp
    case commandLine
    case unknown
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
        let environment = ProcessInfo.processInfo.environment
        return RuntimeIdentity(
            processName: ProcessInfo.processInfo.processName,
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments.first ?? "不明",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            bundlePath: bundlePath,
            isAppBundle: bundlePath.hasSuffix(".app"),
            launchContext: resolveLaunchContext(
                bundlePath: bundlePath,
                bundleIdentifier: Bundle.main.bundleIdentifier,
                parentProcessIdentifier: getppid(),
                xpcServiceName: environment["XPC_SERVICE_NAME"],
                environmentBundleIdentifier: environment["__CFBundleIdentifier"]
            )
        )
    }

    static func resolveLaunchContext(
        bundlePath: String,
        bundleIdentifier: String?,
        parentProcessIdentifier: pid_t,
        xpcServiceName: String?,
        environmentBundleIdentifier: String?
    ) -> RuntimeLaunchContext {
        guard bundlePath.hasSuffix(".app") else {
            return .commandLine
        }
        guard parentProcessIdentifier == 1 else {
            return .commandLine
        }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .unknown
        }

        let expectedServiceName = "application.\(bundleIdentifier)"
        let serviceMatches =
            xpcServiceName == expectedServiceName
            || xpcServiceName?.hasPrefix(expectedServiceName + ".") == true
        guard serviceMatches, environmentBundleIdentifier == bundleIdentifier else {
            return .unknown
        }
        return .launchServicesApp
    }

    var tccAttribution: String {
        switch launchContext {
        case .launchServicesApp where isAppBundle:
            return "appBundle"
        case .commandLine:
            return "invokingProcess"
        case .launchServicesApp, .unknown:
            return "unknown"
        }
    }

    var permissionTargetDescription: String {
        if tccAttribution == "appBundle" {
            if let bundleIdentifier {
                return "\(bundlePath) (bundle ID: \(bundleIdentifier))"
            }
            return bundlePath
        }
        if tccAttribution == "unknown" {
            return "判定不能 (bundle: \(bundlePath), executable: \(executablePath))"
        }
        if isAppBundle {
            return "実行元ターミナルまたは親アプリ (CLI: \(executablePath))"
        }
        return executablePath
    }
}
