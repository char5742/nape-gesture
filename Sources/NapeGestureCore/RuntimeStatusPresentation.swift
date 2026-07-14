import Darwin
import Foundation

public struct OperatingSystemDiagnosticIdentity: Equatable, Sendable {
    public let version: String
    public let build: String

    public static func current() -> OperatingSystemDiagnosticIdentity? {
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let version =
            "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)"
        guard let build = currentBuild() else {
            return nil
        }
        return OperatingSystemDiagnosticIdentity(version: version, build: build)
    }

    private static func currentBuild() -> String? {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname("kern.osversion", bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else {
            return nil
        }

        return buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return nil
            }
            let build = String(cString: baseAddress)
            return build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : build
        }
    }
}

public struct RuntimeStatusPresentation: Equatable, Sendable {
    public var stateTitle: String
    public var startEnabled: Bool
    public var emergencyStopEnabled: Bool
    public var stopEnabled: Bool

    public init(
        stateTitle: String,
        startEnabled: Bool,
        emergencyStopEnabled: Bool,
        stopEnabled: Bool
    ) {
        self.stateTitle = stateTitle
        self.startEnabled = startEnabled
        self.emergencyStopEnabled = emergencyStopEnabled
        self.stopEnabled = stopEnabled
    }
}

public enum RuntimeStatusPresenter {
    public static func present(
        isRuntimeRunning: Bool,
        recoveryState: RuntimeRecoveryState
    ) -> RuntimeStatusPresentation {
        RuntimeStatusPresentation(
            stateTitle: stateTitle(isRuntimeRunning: isRuntimeRunning, recoveryState: recoveryState),
            startEnabled: !isRuntimeRunning,
            emergencyStopEnabled: isRuntimeRunning || recoveryState.autoRetryEnabled,
            stopEnabled: isRuntimeRunning || recoveryState.autoRetryEnabled
        )
    }

    private static func stateTitle(
        isRuntimeRunning: Bool,
        recoveryState: RuntimeRecoveryState
    ) -> String {
        if isRuntimeRunning {
            return "状態: 実行中"
        }
        if recoveryState.isSuspendedForSleep {
            return "状態: スリープ待機中"
        }
        if recoveryState.shouldShowAutoRetry {
            return "状態: 停止中（自動再試行中）"
        }
        return "状態: 停止中"
    }
}
