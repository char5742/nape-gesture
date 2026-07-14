import Foundation
import IOKit.hid
import NapeGestureCore

enum HIDDeviceMatch {
    static func mouseInterfaceMatches() -> [[String: Int]] {
        [
            [
                kIOHIDDeviceUsagePageKey: MouseHIDInterface.primaryUsagePage,
                kIOHIDDeviceUsageKey: MouseHIDInterface.primaryUsage
            ]
        ]
    }

    static func exactMatches(for devices: [DeviceIdentity]) -> [[String: Int]] {
        var seen = Set<String>()
        var matches: [[String: Int]] = []

        for device in devices {
            guard device.isMouseInterface else {
                continue
            }
            let match = matchDictionary(
                vendorID: device.vendorID,
                productID: device.productID
            )
            guard !match.isEmpty else {
                continue
            }

            let key = key(for: match)
            guard seen.insert(key).inserted else {
                continue
            }

            matches.append(match)
        }

        return matches
    }

    static func exactMatches(for matchers: [DeviceMatcher]) -> [[String: Int]] {
        var seen = Set<String>()
        var matches: [[String: Int]] = []

        for matcher in matchers {
            let match = matchDictionary(
                vendorID: matcher.vendorID,
                productID: matcher.productID
            )
            guard !match.isEmpty else {
                continue
            }

            let key = key(for: match)
            guard seen.insert(key).inserted else {
                continue
            }

            matches.append(match)
        }

        return matches
    }

    private static func matchDictionary(
        vendorID: Int?,
        productID: Int?
    ) -> [String: Int] {
        var match = [
            kIOHIDDeviceUsagePageKey: MouseHIDInterface.primaryUsagePage,
            kIOHIDDeviceUsageKey: MouseHIDInterface.primaryUsage
        ]
        if let vendorID, vendorID >= 0 {
            match[kIOHIDVendorIDKey] = vendorID
        }
        if let productID, productID >= 0 {
            match[kIOHIDProductIDKey] = productID
        }
        return match
    }

    private static func key(for match: [String: Int]) -> String {
        match
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ";")
    }
}
