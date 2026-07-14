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
            IOHIDManagerSetDeviceMatchingMultiple(
                manager,
                HIDDeviceMatch.mouseInterfaceMatches() as CFArray
            )
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

        guard identity.isMouseInterface, isTargetDevice(identity) else {
            return
        }

        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let integerValue = IOHIDValueGetIntegerValue(value)
        let time = MonotonicEventClock.nowSeconds

        if usagePage == kHIDPage_Button, let button = MouseButton(hidButtonUsage: usage) {
            if integerValue != 0 {
                gate.record(.buttonDown(button: button, time: time))
            } else {
                gate.record(.buttonUp(button: button, time: time))
            }
            return
        }

        guard usagePage == kHIDPage_GenericDesktop else {
            return
        }

        switch usage {
        case kHIDUsage_GD_X:
            guard integerValue != 0 else {
                return
            }
            gate.record(.pointer(deltaX: Double(integerValue), deltaY: 0, time: time))
        case kHIDUsage_GD_Y:
            guard integerValue != 0 else {
                return
            }
            gate.record(.pointer(deltaX: 0, deltaY: Double(integerValue), time: time))
        case kHIDUsage_GD_Wheel:
            guard integerValue != 0 else {
                return
            }
            gate.record(.wheel(deltaX: 0, deltaY: Double(integerValue), time: time))
        default:
            return
        }
    }

    private func isTargetDevice(_ device: DeviceIdentity) -> Bool {
        guard !settings.targetDevices.isEmpty else {
            return true
        }
        return settings.targetDevices.contains { $0.matchesMouseInterface(device) }
    }
}

private let hidInputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else {
        return
    }

    let monitor = Unmanaged<HIDInputMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handle(value: value)
}
