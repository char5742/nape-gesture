import Foundation
import IOKit
import NapeGestureCore

final class NapeGestureRuntime {
    private var daemon: NapeGestureDaemon?
    private var daemonGeneration: UUID?
    private var monitor: HIDInputMonitor?
    private var gate: SharedTargetDeviceGate?

    private(set) var isRunning = false
    private(set) var lastError: Error?
    private(set) var lastRecoveryFailureKind: RuntimeRecoveryFailureKind?
    var onTerminalFailure: ((Error, RuntimeRecoveryFailureKind) -> Void)?

    func start(settings: NapeGestureSettings) {
        guard stop() == nil else {
            return
        }

        var pendingMonitor: HIDInputMonitor?
        let generation = UUID()

        do {
            try SettingsStore.validateSettings(settings)
            let matchedDevices = try validateTargetDevicesIfNeeded(settings)
            let newGate = makeTargetDeviceGate(settings: settings)
            let newMonitor = try makeHIDInputMonitor(
                settings: settings,
                gate: newGate,
                matchedDevices: matchedDevices
            )
            let performanceRecorder = try RuntimePerformanceLogWriter.make(path: nil)
            pendingMonitor = newMonitor
            let newDaemon = NapeGestureDaemon(
                cancellation: settings.gesture.cancellation,
                buttonAssignments: settings.gesture.buttonAssignments,
                systemGestureSensitivity: settings.gesture.systemGestureSensitivity,
                targetGate: newGate,
                hidInputMonitor: newMonitor,
                performanceRecorder: performanceRecorder,
                onTerminalFailure: { [weak self] error in
                    self?.handleTerminalFailure(error, generation: generation)
                }
            )
            try newDaemon.start()

            gate = newGate
            monitor = newMonitor
            daemon = newDaemon
            daemonGeneration = generation
            pendingMonitor = nil
            isRunning = true
            lastError = nil
            lastRecoveryFailureKind = nil
        } catch {
            let failureKind = runtimeRecoveryFailureKind(for: error)
            pendingMonitor?.stop()
            let stopError = stop()
            lastError = stopError ?? error
            lastRecoveryFailureKind = stopError.map { runtimeRecoveryFailureKind(for: $0) } ?? failureKind
        }
    }

    @discardableResult
    func stop() -> Error? {
        let stopError = stopDaemonWithRetries()
        monitor?.stop()
        isRunning = false
        if let stopError {
            let failureKind = runtimeRecoveryFailureKind(for: stopError)
            lastError = stopError
            lastRecoveryFailureKind = failureKind
            onTerminalFailure?(stopError, failureKind)
            return stopError
        }
        daemon = nil
        daemonGeneration = nil
        monitor = nil
        gate = nil
        return nil
    }

    @discardableResult
    func refreshHealth(settings: NapeGestureSettings) -> Bool {
        guard isRunning else {
            return false
        }

        do {
            try SettingsStore.validateSettings(settings)
            guard AccessibilityPermission.isTrusted else {
                throw ToolError.accessibilityPermissionRequired
            }
            if settings.requireMatchingTargetDevice {
                _ = try validateRequiredTargetDevices(settings)
            }
            return false
        } catch {
            let failureKind = runtimeRecoveryFailureKind(for: error)
            let stopError = stop()
            lastError = stopError ?? error
            lastRecoveryFailureKind = stopError.map { runtimeRecoveryFailureKind(for: $0) } ?? failureKind
            return true
        }
    }

    private func validateTargetDevicesIfNeeded(_ settings: NapeGestureSettings) throws -> [DeviceIdentity] {
        guard !settings.targetDevices.isEmpty else {
            if settings.requireMatchingTargetDevice {
                throw ToolError.targetDeviceMatcherRequired
            }
            return []
        }

        let matched = try DeviceInventory.matchedDevices(settings: settings)
        guard !matched.isEmpty else {
            if settings.requireMatchingTargetDevice {
                throw ToolError.targetDeviceNotFound
            }
            return []
        }
        return matched
    }

    private func validateRequiredTargetDevices(_ settings: NapeGestureSettings) throws -> [DeviceIdentity] {
        guard !settings.targetDevices.isEmpty else {
            throw ToolError.targetDeviceMatcherRequired
        }

        let matched = try DeviceInventory.matchedDevices(settings: settings)
        guard !matched.isEmpty else {
            throw ToolError.targetDeviceNotFound
        }
        return matched
    }

    private func makeTargetDeviceGate(settings: NapeGestureSettings) -> SharedTargetDeviceGate? {
        guard !settings.targetDevices.isEmpty else {
            return nil
        }
        return SharedTargetDeviceGate(
            configuration: TargetDeviceGateConfiguration(settings: settings)
        )
    }

    private func makeHIDInputMonitor(
        settings: NapeGestureSettings,
        gate: SharedTargetDeviceGate?,
        matchedDevices: [DeviceIdentity]
    ) throws -> HIDInputMonitor? {
        guard let gate else {
            return nil
        }

        let monitor = HIDInputMonitor(settings: settings, gate: gate, matchedDevices: matchedDevices)
        try monitor.start()
        return monitor
    }

    private func handleTerminalFailure(_ error: Error, generation: UUID) {
        guard daemonGeneration == generation,
              daemon != nil || isRunning
        else {
            return
        }
        let stopError = stopDaemonWithRetries()
        monitor?.stop()
        isRunning = false
        let reportedError = stopError ?? error
        let failureKind = runtimeRecoveryFailureKind(for: reportedError)
        if stopError == nil {
            daemon = nil
            daemonGeneration = nil
            monitor = nil
            gate = nil
        }
        lastError = reportedError
        lastRecoveryFailureKind = failureKind
        onTerminalFailure?(reportedError, failureKind)
    }

    private func stopDaemonWithRetries(maximumAttempts: Int = 3) -> Error? {
        guard let daemon else {
            return nil
        }
        var lastError: Error?
        for _ in 0..<max(maximumAttempts, 1) {
            if let error = daemon.stop() {
                lastError = error
            } else {
                return nil
            }
        }
        return lastError
    }

    private func runtimeRecoveryFailureKind(for error: Error) -> RuntimeRecoveryFailureKind {
        guard let toolError = error as? ToolError else {
            return .unrecoverable
        }

        switch toolError {
        case .accessibilityPermissionRequired:
            return .accessibilityPermissionMissing
        case .eventTapCreationFailed:
            return .eventTapCreationFailed
        case .hidRegistryQueryFailed(_):
            return .hidAccessUnavailable
        case .targetDeviceNotFound:
            return .targetDeviceNotFound
        case let .hidManagerOpenFailed(code):
            switch code {
            case kIOReturnNotPermitted,
                 kIOReturnNotPrivileged,
                 kIOReturnNoDevice,
                 kIOReturnExclusiveAccess:
                return .hidAccessUnavailable
            default:
                return .unrecoverable
            }
        case .invalidSettings(_):
            return .invalidSettings
        case .targetDeviceMatcherRequired:
            return .targetDeviceMatcherMissing
        case .trackpadOutputContractUnavailable:
            return .outputContractUnsupported
        case .trackpadOutputContractMismatch:
            return .outputContractMismatch
        case .trackpadOutputPostingFailed:
            return .outputPostingFailed
        case .unknownCommand(_),
             .missingValue(_),
             .invalidValue(_, _),
             .bundleOutputAlreadyExists(_),
             .bundleVerificationFailed(_),
             .executablePathUnavailable,
             .targetApplicationNotFound(_),
             .benchmarkBaselineFailed(_),
             .guiSmokeFailed(_):
            return .unrecoverable
        }
    }
}
