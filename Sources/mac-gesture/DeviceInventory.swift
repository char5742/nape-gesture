import Foundation
import IOKit
import IOKit.hid
import MacGestureCore

enum DeviceInventory {
    static func allDevices() throws -> [DeviceIdentity] {
        try hidDevices(filter: .all)
    }

    static func pointingDevices() throws -> [DeviceIdentity] {
        try hidDevices(filter: .pointing)
    }

    static func matchedDevices(settings: MacGestureSettings) throws -> [DeviceIdentity] {
        let devices = try allDevices()
        guard !settings.targetDevices.isEmpty else {
            return devices
        }
        return devices.filter { device in
            settings.targetDevices.contains { $0.matches(device) }
        }
    }

    private static func hidDevices(filter: DeviceFilter) throws -> [DeviceIdentity] {
        guard let matching = IOServiceMatching(kIOHIDDeviceKey) else {
            return []
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            throw ToolError.hidRegistryQueryFailed(result)
        }
        defer {
            IOObjectRelease(iterator)
        }

        var devices: [DeviceIdentity] = []
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let usagePage = intProperty(service, kIOHIDPrimaryUsagePageKey)
            let usage = intProperty(service, kIOHIDPrimaryUsageKey)
            guard filter.includes(usagePage: usagePage, usage: usage) else {
                continue
            }

            devices.append(
                DeviceIdentity(
                    manufacturer: stringProperty(service, kIOHIDManufacturerKey) ?? "Unknown Manufacturer",
                    product: stringProperty(service, kIOHIDProductKey) ?? "Unknown Product",
                    vendorID: intProperty(service, kIOHIDVendorIDKey),
                    productID: intProperty(service, kIOHIDProductIDKey),
                    transport: stringProperty(service, kIOHIDTransportKey) ?? "Unknown Transport",
                    primaryUsagePage: usagePage,
                    primaryUsage: usage
                )
            )
        }

        return devices
    }

    private static func stringProperty(_ service: io_object_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func intProperty(_ service: io_object_t, _ key: String) -> Int {
        if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber {
            return value.intValue
        }
        return -1
    }
}

private enum DeviceFilter {
    case all
    case pointing

    func includes(usagePage: Int, usage: Int) -> Bool {
        switch self {
        case .all:
            return true
        case .pointing:
            return usagePage == kHIDPage_GenericDesktop
                && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer)
        }
    }
}
