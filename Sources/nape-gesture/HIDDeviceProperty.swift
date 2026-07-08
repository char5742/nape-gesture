import Foundation
import IOKit.hid
import NapeGestureCore

extension DeviceIdentity {
    init(hidDevice: IOHIDDevice) {
        self.init(
            manufacturer: HIDDeviceProperty.string(hidDevice, kIOHIDManufacturerKey) ?? "Unknown Manufacturer",
            product: HIDDeviceProperty.string(hidDevice, kIOHIDProductKey) ?? "Unknown Product",
            vendorID: HIDDeviceProperty.int(hidDevice, kIOHIDVendorIDKey),
            productID: HIDDeviceProperty.int(hidDevice, kIOHIDProductIDKey),
            transport: HIDDeviceProperty.string(hidDevice, kIOHIDTransportKey) ?? "Unknown Transport",
            primaryUsagePage: HIDDeviceProperty.int(hidDevice, kIOHIDPrimaryUsagePageKey),
            primaryUsage: HIDDeviceProperty.int(hidDevice, kIOHIDPrimaryUsageKey)
        )
    }
}

enum HIDDeviceProperty {
    static func string(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    static func int(_ device: IOHIDDevice, _ key: String) -> Int {
        if let value = IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber {
            return value.intValue
        }
        return -1
    }
}
