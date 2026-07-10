import Foundation
import IOKit.hid
import NapeGestureCore

final class HIDInputMonitor {
    private let settings: NapeGestureSettings
    private let gate: SharedTargetDeviceGate
    private let matchedDevices: [DeviceIdentity]
    private var manager: IOHIDManager?
    private var targetDeviceCache: [ObjectIdentifier: Bool] = [:]
    private var isStopping = false

    var onTargetDeviceRemoval: (() -> Void)?
    var onAssociationAmbiguity: (() -> Void)?

    init(settings: NapeGestureSettings, gate: SharedTargetDeviceGate, matchedDevices: [DeviceIdentity] = []) {
        self.settings = settings
        self.gate = gate
        self.matchedDevices = matchedDevices
    }

    func start() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        isStopping = false
        targetDeviceCache.removeAll()

        let deviceMatches = HIDDeviceMatch.exactMatches(for: matchedDevices)
        let matcherMatches = HIDDeviceMatch.exactMatches(for: settings.targetDevices)
        let exactMatches = deviceMatches.isEmpty ? matcherMatches : deviceMatches
        let monitoredMatches = HIDDeviceMatch.pointingMatches() + exactMatches
        IOHIDManagerSetDeviceMatchingMultiple(manager, monitoredMatches as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            hidDeviceMatchingCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        IOHIDManagerRegisterInputValueCallback(
            manager,
            hidInputValueCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            hidDeviceRemovalCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw ToolError.hidManagerOpenFailed(result)
        }
    }

    func stop() {
        guard let manager else {
            return
        }

        isStopping = true
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        targetDeviceCache.removeAll()
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let isTargetDevice = isTargetDevice(device)

        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let integerValue = IOHIDValueGetIntegerValue(value)
        let time = HIDEventTimestamp.seconds(for: value)

        guard let activity = HIDTargetActivityMapper.activity(
            usagePage: usagePage,
            usage: usage,
            integerValue: integerValue,
            time: time
        ) else {
            return
        }
        let decision = gate.record(activity, isTargetDevice: isTargetDevice)
        if decision.shouldCancelGesture {
            onAssociationAmbiguity?()
        }
    }

    fileprivate func handleRemoval(device: IOHIDDevice) {
        let key = ObjectIdentifier(device)
        let removedTargetDevice = targetDeviceCache[key] ?? isTargetDevice(device)
        targetDeviceCache[key] = nil

        guard !isStopping, removedTargetDevice else {
            return
        }
        gate.reset()
        onTargetDeviceRemoval?()
    }

    fileprivate func handleMatched(device: IOHIDDevice) {
        _ = isTargetDevice(device)
    }

    private func isTargetDevice(_ device: IOHIDDevice) -> Bool {
        let key = ObjectIdentifier(device)
        if let cached = targetDeviceCache[key] {
            return cached
        }

        let identity = DeviceIdentity(hidDevice: device)
        let matchesKnownDevice = matchedDevices.contains { $0.stableID == identity.stableID }
        let matchesSettings = settings.targetDevices.isEmpty
            || settings.targetDevices.contains { $0.matches(identity) }
        let result = matchesKnownDevice || matchesSettings
        targetDeviceCache[key] = result
        return result
    }
}

private let hidInputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else {
        return
    }

    let monitor = Unmanaged<HIDInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handle(value: value)
}

private let hidDeviceMatchingCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else {
        return
    }

    let monitor = Unmanaged<HIDInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handleMatched(device: device)
}

private let hidDeviceRemovalCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else {
        return
    }

    let monitor = Unmanaged<HIDInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handleRemoval(device: device)
}
