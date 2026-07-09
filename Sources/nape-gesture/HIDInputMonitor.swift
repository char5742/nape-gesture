import Foundation
import IOKit.hid
import NapeGestureCore

final class HIDInputMonitor {
    private let settings: NapeGestureSettings
    private let gate: SharedTargetDeviceGate
    private let matchedDevices: [DeviceIdentity]
    private var manager: IOHIDManager?

    init(settings: NapeGestureSettings, gate: SharedTargetDeviceGate, matchedDevices: [DeviceIdentity] = []) {
        self.settings = settings
        self.gate = gate
        self.matchedDevices = matchedDevices
    }

    func start() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let deviceMatches = HIDDeviceMatch.exactMatches(for: matchedDevices)
        let matcherMatches = HIDDeviceMatch.exactMatches(for: settings.targetDevices)
        let exactMatches = deviceMatches.isEmpty ? matcherMatches : deviceMatches
        if exactMatches.isEmpty {
            IOHIDManagerSetDeviceMatchingMultiple(manager, HIDDeviceMatch.pointingMatches() as CFArray)
        } else {
            IOHIDManagerSetDeviceMatchingMultiple(manager, exactMatches as CFArray)
        }
        IOHIDManagerRegisterInputValueCallback(
            manager,
            hidInputValueCallback,
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

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let identity = DeviceIdentity(hidDevice: device)

        guard isTargetDevice(identity) else {
            return
        }

        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let integerValue = IOHIDValueGetIntegerValue(value)
        let time = ProcessInfo.processInfo.systemUptime

        guard let activity = HIDTargetActivityMapper.activity(
            usagePage: usagePage,
            usage: usage,
            integerValue: integerValue,
            time: time
        ) else {
            return
        }
        gate.record(activity)
    }

    private func isTargetDevice(_ device: DeviceIdentity) -> Bool {
        guard !settings.targetDevices.isEmpty else {
            return true
        }
        return settings.targetDevices.contains { $0.matches(device) }
    }
}

private let hidInputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else {
        return
    }

    let monitor = Unmanaged<HIDInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handle(value: value)
}
