import Foundation
import IOKit.hid
import MacGestureCore

enum HIDDeviceMatch {
    static func pointingMatches() -> [[String: Int]] {
        [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer
            ]
        ]
    }

    static func exactMatches(for devices: [DeviceIdentity]) -> [[String: Int]] {
        var seen = Set<String>()
        var matches: [[String: Int]] = []

        for device in devices {
            let match = matchDictionary(
                vendorID: device.vendorID,
                productID: device.productID,
                usagePage: device.primaryUsagePage,
                usage: device.primaryUsage
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
                productID: matcher.productID,
                usagePage: matcher.primaryUsagePage,
                usage: matcher.primaryUsage
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
        productID: Int?,
        usagePage: Int?,
        usage: Int?
    ) -> [String: Int] {
        var match: [String: Int] = [:]
        if let vendorID, vendorID >= 0 {
            match[kIOHIDVendorIDKey] = vendorID
        }
        if let productID, productID >= 0 {
            match[kIOHIDProductIDKey] = productID
        }
        if let usagePage, usagePage >= 0 {
            match[kIOHIDDeviceUsagePageKey] = usagePage
        }
        if let usage, usage >= 0 {
            match[kIOHIDDeviceUsageKey] = usage
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
