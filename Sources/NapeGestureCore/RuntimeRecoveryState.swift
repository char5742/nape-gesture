import Foundation

/// 常駐 runtime の停止、スリープ待機、自動再試行を外部 IO なしで判定する純粋状態。
public struct RuntimeRecoveryState: Equatable, Sendable {
    public private(set) var mode: RuntimeRecoveryMode
    public private(set) var autoRetryEnabled: Bool
    public private(set) var pendingRetry: RuntimeRetryRequest?
    public private(set) var shouldRetryAfterWake: Bool

    public init(
        mode: RuntimeRecoveryMode = .stopped(reason: .initial, stoppedAt: nil),
        autoRetryEnabled: Bool = true,
        pendingRetry: RuntimeRetryRequest? = nil,
        shouldRetryAfterWake: Bool = false
    ) {
        self.mode = mode
        self.autoRetryEnabled = autoRetryEnabled
        self.pendingRetry = pendingRetry
        self.shouldRetryAfterWake = shouldRetryAfterWake
    }

    public var isRunning: Bool {
        mode == .running
    }

    public var isSuspendedForSleep: Bool {
        mode == .suspendedForSleep
    }

    public var shouldShowAutoRetry: Bool {
        autoRetryEnabled && pendingRetry != nil && !isSuspendedForSleep
    }

    @discardableResult
    public mutating func requestManualStart(at time: TimeInterval) -> RuntimeRecoveryDecision {
        autoRetryEnabled = true
        mode = .starting(reason: .manualStart, requestedAt: time)
        pendingRetry = nil
        shouldRetryAfterWake = false
        return RuntimeRecoveryDecision(shouldStartRuntime: true, shouldStopRuntime: false)
    }

    public mutating func recordRuntimeStarted() {
        mode = .running
        pendingRetry = nil
        shouldRetryAfterWake = false
    }

    @discardableResult
    public mutating func requestManualStop(at time: TimeInterval) -> RuntimeRecoveryDecision {
        autoRetryEnabled = false
        mode = .stopped(reason: .manualStop, stoppedAt: time)
        pendingRetry = nil
        shouldRetryAfterWake = false
        return RuntimeRecoveryDecision(shouldStartRuntime: false, shouldStopRuntime: true)
    }

    @discardableResult
    public mutating func recordSettingsSaved(at time: TimeInterval) -> RuntimeRecoveryDecision {
        autoRetryEnabled = true
        mode = .starting(reason: .settingsSaved, requestedAt: time)
        pendingRetry = nil
        shouldRetryAfterWake = false
        return RuntimeRecoveryDecision(shouldStartRuntime: true, shouldStopRuntime: false)
    }

    @discardableResult
    public mutating func recordRuntimeFailure(
        _ failure: RuntimeRecoveryFailureKind,
        at time: TimeInterval
    ) -> RuntimeRecoveryDecision {
        let wasSuspendedForSleep = isSuspendedForSleep
        if !wasSuspendedForSleep {
            mode = .stopped(reason: .runtimeFailure(failure), stoppedAt: time)
            shouldRetryAfterWake = false
        }
        pendingRetry = retryRequest(for: failure, at: time, wasSuspendedForSleep: wasSuspendedForSleep)
        return RuntimeRecoveryDecision(shouldStartRuntime: false, shouldStopRuntime: false)
    }

    @discardableResult
    public mutating func handleWillSleep(at time: TimeInterval) -> RuntimeRecoveryDecision {
        shouldRetryAfterWake = autoRetryEnabled && (shouldRetryAfterWake || canRetryAfterWake)
        mode = .suspendedForSleep
        pendingRetry = nil
        return RuntimeRecoveryDecision(shouldStartRuntime: false, shouldStopRuntime: true)
    }

    @discardableResult
    public mutating func handleDidWake(at time: TimeInterval, retryDelay: TimeInterval) -> RuntimeRecoveryDecision {
        guard autoRetryEnabled else {
            mode = .stopped(reason: .manualStop, stoppedAt: time)
            pendingRetry = nil
            shouldRetryAfterWake = false
            return RuntimeRecoveryDecision(shouldStartRuntime: false, shouldStopRuntime: false)
        }

        guard shouldRetryAfterWake else {
            mode = .stopped(reason: .wake, stoppedAt: time)
            pendingRetry = nil
            shouldRetryAfterWake = false
            return RuntimeRecoveryDecision(shouldStartRuntime: false, shouldStopRuntime: false)
        }

        mode = .stopped(reason: .wake, stoppedAt: time)
        pendingRetry = RuntimeRetryRequest(
            reason: .wake,
            requestedAt: time,
            notBefore: time + max(retryDelay, 0)
        )
        shouldRetryAfterWake = false
        return RuntimeRecoveryDecision(shouldStartRuntime: false, shouldStopRuntime: false)
    }

    @discardableResult
    public mutating func retryIfReady(at time: TimeInterval) -> RuntimeRecoveryDecision {
        guard autoRetryEnabled,
              !isSuspendedForSleep,
              !isRunning,
              let retry = pendingRetry,
              retry.notBefore <= time
        else {
            return RuntimeRecoveryDecision(shouldStartRuntime: false, shouldStopRuntime: false)
        }

        mode = .starting(reason: .automaticRetry(retry.reason), requestedAt: time)
        pendingRetry = nil
        shouldRetryAfterWake = false
        return RuntimeRecoveryDecision(shouldStartRuntime: true, shouldStopRuntime: false)
    }

    private var canRetryAfterWake: Bool {
        switch mode {
        case .running,
             .starting:
            return true
        case .stopped,
             .suspendedForSleep:
            return pendingRetry != nil
        }
    }

    private func retryRequest(
        for failure: RuntimeRecoveryFailureKind,
        at time: TimeInterval,
        wasSuspendedForSleep: Bool
    ) -> RuntimeRetryRequest? {
        guard autoRetryEnabled,
              !wasSuspendedForSleep,
              failure.isAutomaticallyRetryable
        else {
            return nil
        }

        return RuntimeRetryRequest(reason: .runtimeFailure(failure), requestedAt: time, notBefore: time)
    }
}

public enum RuntimeRecoveryMode: Equatable, Sendable {
    case running
    case starting(reason: RuntimeStartReason, requestedAt: TimeInterval)
    case stopped(reason: RuntimeStopReason, stoppedAt: TimeInterval?)
    case suspendedForSleep
}

public enum RuntimeStartReason: Equatable, Sendable {
    case manualStart
    case settingsSaved
    case automaticRetry(RuntimeRetryReason)
}

public enum RuntimeStopReason: Equatable, Sendable {
    case initial
    case manualStop
    case wake
    case runtimeFailure(RuntimeRecoveryFailureKind)
}

public struct RuntimeRetryRequest: Equatable, Sendable {
    public var reason: RuntimeRetryReason
    public var requestedAt: TimeInterval
    public var notBefore: TimeInterval

    public init(reason: RuntimeRetryReason, requestedAt: TimeInterval, notBefore: TimeInterval) {
        self.reason = reason
        self.requestedAt = requestedAt
        self.notBefore = notBefore
    }
}

public enum RuntimeRetryReason: Equatable, Sendable {
    case wake
    case runtimeFailure(RuntimeRecoveryFailureKind)
}

public enum RuntimeRecoveryFailureKind: Equatable, Sendable {
    case accessibilityPermissionMissing
    case eventTapCreationFailed
    case hidAccessUnavailable
    case targetDeviceNotFound
    case invalidSettings
    case targetDeviceMatcherMissing
    case unrecoverable

    public var isAutomaticallyRetryable: Bool {
        switch self {
        case .accessibilityPermissionMissing,
             .eventTapCreationFailed,
             .hidAccessUnavailable,
             .targetDeviceNotFound:
            return true
        case .invalidSettings,
             .targetDeviceMatcherMissing,
             .unrecoverable:
            return false
        }
    }
}

public struct RuntimeRecoveryDecision: Equatable, Sendable {
    public var shouldStartRuntime: Bool
    public var shouldStopRuntime: Bool

    public init(shouldStartRuntime: Bool, shouldStopRuntime: Bool) {
        self.shouldStartRuntime = shouldStartRuntime
        self.shouldStopRuntime = shouldStopRuntime
    }
}
