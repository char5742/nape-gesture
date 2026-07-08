import Foundation
import MacGestureCore

enum DeviceLister {
    static func printDevices(json: Bool, includeAll: Bool) throws {
        let devices = try includeAll ? DeviceInventory.allDevices() : DeviceInventory.pointingDevices()

        guard !devices.isEmpty else {
            print(includeAll ? "HIDデバイスは見つかりませんでした。" : "マウス系デバイスは見つかりませんでした。")
            return
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(devices)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        for device in devices {
            print("\(device.displayName) vendorId=\(device.vendorID) productId=\(device.productID) usagePage=\(device.primaryUsagePage) usage=\(device.primaryUsage) transport=\(device.transport) stableId=\(device.stableID)")
        }
    }
}
