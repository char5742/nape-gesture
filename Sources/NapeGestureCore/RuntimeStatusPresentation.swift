import Foundation

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
