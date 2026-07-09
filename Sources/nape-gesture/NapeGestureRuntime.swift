import Foundation
import IOKit
import NapeGestureCore

final class NapeGestureRuntime {
    private var daemon: NapeGestureDaemon?
    private var monitor: HIDInputMonitor?
    private var gate: SharedTargetDeviceGate?

    private(set) var isRunning = false
    private(set) var lastError: Error?
    private(set) var lastRecoveryFailureKind: RuntimeRecoveryFailureKind?

    func start(settings: NapeGestureSettings) {
        stop()

        var pendingMonitor: HIDInputMonitor?

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
                configuration: settings.gesture,
                targetGate: newGate,
                hidInputMonitor: newMonitor,
                performanceRecorder: performanceRecorder
            )
            try newDaemon.start()

            gate = newGate
            monitor = newMonitor
            daemon = newDaemon
            pendingMonitor = nil
            isRunning = true
            lastError = nil
            lastRecoveryFailureKind = nil
        } catch {
            let failureKind = runtimeRecoveryFailureKind(for: error)
            pendingMonitor?.stop()
            stop()
            lastError = error
            lastRecoveryFailureKind = failureKind
        }
    }

    func stop() {
        daemon?.stop()
        monitor?.stop()
        daemon = nil
        monitor = nil
        gate = nil
        isRunning = false
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
            stop()
            lastError = error
            lastRecoveryFailureKind = failureKind
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
        case .unknownCommand(_),
             .missingValue(_),
             .invalidValue(_, _),
             .bundleOutputAlreadyExists(_),
             .bundleVerificationFailed(_),
             .executablePathUnavailable,
             .targetApplicationNotFound(_),
             .benchmarkBaselineFailed(_):
            return .unrecoverable
        }
    }
}
