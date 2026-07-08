import Foundation
import IOKit
import MacGestureCore

final class MacGestureRuntime {
    private var daemon: MacGestureDaemon?
    private var monitor: HIDInputMonitor?
    private var gate: SharedTargetDeviceGate?

    private(set) var isRunning = false
    private(set) var lastError: Error?

    var shouldRetryAutomatically: Bool {
        guard !isRunning, let lastError else {
            return false
        }
        return isRecoverableStartupError(lastError)
    }

    func start(settings: MacGestureSettings) {
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
            pendingMonitor = newMonitor
            let newDaemon = MacGestureDaemon(
                configuration: settings.gesture,
                targetGate: newGate,
                hidInputMonitor: newMonitor
            )
            try newDaemon.start()

            gate = newGate
            monitor = newMonitor
            daemon = newDaemon
            pendingMonitor = nil
            isRunning = true
            lastError = nil
        } catch {
            pendingMonitor?.stop()
            stop()
            lastError = error
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
    func refreshHealth(settings: MacGestureSettings) -> Bool {
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
            stop()
            lastError = error
            return true
        }
    }

    private func validateTargetDevicesIfNeeded(_ settings: MacGestureSettings) throws -> [DeviceIdentity] {
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

    private func validateRequiredTargetDevices(_ settings: MacGestureSettings) throws -> [DeviceIdentity] {
        guard !settings.targetDevices.isEmpty else {
            throw ToolError.targetDeviceMatcherRequired
        }

        let matched = try DeviceInventory.matchedDevices(settings: settings)
        guard !matched.isEmpty else {
            throw ToolError.targetDeviceNotFound
        }
        return matched
    }

    private func makeTargetDeviceGate(settings: MacGestureSettings) -> SharedTargetDeviceGate? {
        guard !settings.targetDevices.isEmpty else {
            return nil
        }
        return SharedTargetDeviceGate(
            configuration: TargetDeviceGateConfiguration(
                activationButton: settings.gesture.activationButton
            )
        )
    }

    private func makeHIDInputMonitor(
        settings: MacGestureSettings,
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

    private func isRecoverableStartupError(_ error: Error) -> Bool {
        guard let toolError = error as? ToolError else {
            return false
        }

        switch toolError {
        case .accessibilityPermissionRequired,
             .eventTapCreationFailed,
             .hidRegistryQueryFailed(_),
             .targetDeviceNotFound:
            return true
        case let .hidManagerOpenFailed(code):
            return code == kIOReturnNotPermitted
                || code == kIOReturnNotPrivileged
                || code == kIOReturnNoDevice
                || code == kIOReturnExclusiveAccess
        case .unknownCommand(_),
             .missingValue(_),
             .invalidValue(_, _),
             .invalidSettings(_),
             .targetDeviceMatcherRequired,
             .bundleOutputAlreadyExists(_),
             .bundleVerificationFailed(_),
             .executablePathUnavailable,
             .targetApplicationNotFound(_):
            return false
        }
    }
}
