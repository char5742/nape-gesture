import Foundation
import IOKit
import IOKit.hid
import NapeGestureCore

enum DeviceInventory {
    static func allDevices() throws -> [DeviceIdentity] {
        try hidDevices(filter: .all)
    }

    static func mouseInterfaces() throws -> [DeviceIdentity] {
        try hidDevices(filter: .mouse)
    }

    static func mouseInterfaces(in devices: [DeviceIdentity]) -> [DeviceIdentity] {
        MouseHIDInterface.interfaces(in: devices)
    }

    static func matchedDevices(settings: NapeGestureSettings) throws -> [DeviceIdentity] {
        let devices = try allDevices()
        return matchedDevices(in: devices, settings: settings)
    }

    static func matchedDevices(
        in devices: [DeviceIdentity],
        settings: NapeGestureSettings
    ) -> [DeviceIdentity] {
        MouseHIDInterface.matching(in: devices, matchers: settings.targetDevices)
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
    case mouse

    func includes(usagePage: Int, usage: Int) -> Bool {
        switch self {
        case .all:
            return true
        case .mouse:
            return MouseHIDInterface.includes(
                primaryUsagePage: usagePage,
                primaryUsage: usage
            )
        }
    }
}
