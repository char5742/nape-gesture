import Foundation
import IOKit.hid
import NapeGestureCore

final class HIDLogCommand {
    private let options: [String]
    private let encoder = JSONEncoder()
    private var manager: IOHIDManager?

    init(options: [String]) {
        self.options = options
        encoder.outputFormatting = [.sortedKeys]
    }

    func run() throws {
        let includeAll = options.contains("--all")
        let duration = try durationValue(defaultValue: 10)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        if let exactDeviceMatch = try exactDeviceMatch() {
            IOHIDManagerSetDeviceMatching(manager, exactDeviceMatch as CFDictionary)
        } else if includeAll {
            IOHIDManagerSetDeviceMatching(manager, nil)
        } else {
            IOHIDManagerSetDeviceMatchingMultiple(manager, HIDDeviceMatch.pointingMatches() as CFArray)
        }

        IOHIDManagerRegisterInputValueCallback(
            manager,
            hidLogCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw ToolError.hidManagerOpenFailed(result)
        }

        fputs("HID入力ログを開始しました。duration=\(duration)秒 includeAll=\(includeAll)\n", stderr)
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, duration, false)
        stop()
    }

    fileprivate func handle(value: IOHIDValue) {
        let record = HIDInputLogRecord(value: value)
        if let data = try? encoder.encode(record) {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    private func stop() {
        guard let manager else {
            return
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    private func durationValue(defaultValue: TimeInterval) throws -> TimeInterval {
        guard options.contains("--duration") else {
            return defaultValue
        }
        let raw = try SettingsStore.requiredValue(for: "--duration", in: options)
        guard let value = TimeInterval(raw), value > 0 else {
            throw ToolError.invalidValue("--duration", raw)
        }
        return value
    }

    private func exactDeviceMatch() throws -> [String: Int]? {
        let hasVendor = options.contains("--vendor-id")
        let hasProduct = options.contains("--product-id")
        let hasUsagePage = options.contains("--usage-page")
        let hasUsage = options.contains("--usage")
        guard hasVendor || hasProduct || hasUsagePage || hasUsage else {
            return nil
        }

        var match: [String: Int] = [:]
        if hasVendor {
            match[kIOHIDVendorIDKey] = try intValue(for: "--vendor-id")
        }
        if hasProduct {
            match[kIOHIDProductIDKey] = try intValue(for: "--product-id")
        }
        if hasUsagePage {
            match[kIOHIDDeviceUsagePageKey] = try intValue(for: "--usage-page")
        }
        if hasUsage {
            match[kIOHIDDeviceUsageKey] = try intValue(for: "--usage")
        }
        return match
    }

    private func intValue(for name: String) throws -> Int {
        let raw = try SettingsStore.requiredValue(for: name, in: options)
        guard let value = Int(raw) else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }
}

extension HIDInputLogRecord {
    init(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let hidDevice = IOHIDElementGetDevice(element)

        self.init(
            time: MonotonicEventClock.nowSeconds,
            device: DeviceIdentity(hidDevice: hidDevice),
            usagePage: Int(IOHIDElementGetUsagePage(element)),
            usage: Int(IOHIDElementGetUsage(element)),
            integerValue: IOHIDValueGetIntegerValue(value),
            scaledValue: IOHIDValueGetScaledValue(value, IOHIDValueScaleType(kIOHIDValueScaleTypePhysical)),
            logicalMin: IOHIDElementGetLogicalMin(element),
            logicalMax: IOHIDElementGetLogicalMax(element),
            physicalMin: IOHIDElementGetPhysicalMin(element),
            physicalMax: IOHIDElementGetPhysicalMax(element)
        )
    }
}

private let hidLogCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else {
        return
    }
    let command = Unmanaged<HIDLogCommand>.fromOpaque(context).takeUnretainedValue()
    command.handle(value: value)
}
