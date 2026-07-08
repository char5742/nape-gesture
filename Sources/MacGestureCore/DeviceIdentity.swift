import Foundation

public struct DeviceIdentity: Codable, Equatable, Sendable {
    public var manufacturer: String
    public var product: String
    public var vendorID: Int
    public var productID: Int
    public var transport: String
    public var primaryUsagePage: Int
    public var primaryUsage: Int

    public init(
        manufacturer: String,
        product: String,
        vendorID: Int,
        productID: Int,
        transport: String,
        primaryUsagePage: Int,
        primaryUsage: Int
    ) {
        self.manufacturer = manufacturer
        self.product = product
        self.vendorID = vendorID
        self.productID = productID
        self.transport = transport
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
    }

    public var displayName: String {
        "\(manufacturer) / \(product)"
    }

    public var stableID: String {
        [
            "vendor=\(vendorID)",
            "product=\(productID)",
            "manufacturer=\(normalized(manufacturer))",
            "name=\(normalized(product))",
            "transport=\(normalized(transport))"
        ].joined(separator: ";")
    }

    private enum CodingKeys: String, CodingKey {
        case manufacturer
        case product
        case vendorID
        case productID
        case transport
        case primaryUsagePage
        case primaryUsage
        case stableID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manufacturer = try container.decode(String.self, forKey: .manufacturer)
        product = try container.decode(String.self, forKey: .product)
        vendorID = try container.decode(Int.self, forKey: .vendorID)
        productID = try container.decode(Int.self, forKey: .productID)
        transport = try container.decode(String.self, forKey: .transport)
        primaryUsagePage = try container.decode(Int.self, forKey: .primaryUsagePage)
        primaryUsage = try container.decode(Int.self, forKey: .primaryUsage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manufacturer, forKey: .manufacturer)
        try container.encode(product, forKey: .product)
        try container.encode(vendorID, forKey: .vendorID)
        try container.encode(productID, forKey: .productID)
        try container.encode(transport, forKey: .transport)
        try container.encode(primaryUsagePage, forKey: .primaryUsagePage)
        try container.encode(primaryUsage, forKey: .primaryUsage)
        try container.encode(stableID, forKey: .stableID)
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

public struct DeviceMatcher: Codable, Equatable, Sendable {
    public var vendorID: Int?
    public var productID: Int?
    public var manufacturerContains: String?
    public var productContains: String?
    public var transportContains: String?
    public var primaryUsagePage: Int?
    public var primaryUsage: Int?

    public init(
        vendorID: Int? = nil,
        productID: Int? = nil,
        manufacturerContains: String? = nil,
        productContains: String? = nil,
        transportContains: String? = nil,
        primaryUsagePage: Int? = nil,
        primaryUsage: Int? = nil
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.manufacturerContains = manufacturerContains
        self.productContains = productContains
        self.transportContains = transportContains
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
    }

    public func matches(_ device: DeviceIdentity) -> Bool {
        guard hasAnyCondition else {
            return false
        }

        if let vendorID, vendorID != device.vendorID {
            return false
        }
        if let productID, productID != device.productID {
            return false
        }
        if let manufacturerContains, !device.manufacturer.localizedCaseInsensitiveContains(manufacturerContains) {
            return false
        }
        if let productContains, !device.product.localizedCaseInsensitiveContains(productContains) {
            return false
        }
        if let transportContains, !device.transport.localizedCaseInsensitiveContains(transportContains) {
            return false
        }
        if let primaryUsagePage, primaryUsagePage != device.primaryUsagePage {
            return false
        }
        if let primaryUsage, primaryUsage != device.primaryUsage {
            return false
        }
        return true
    }

    public var hasAnyCondition: Bool {
        vendorID != nil
            || productID != nil
            || manufacturerContains?.isEmpty == false
            || productContains?.isEmpty == false
            || transportContains?.isEmpty == false
            || primaryUsagePage != nil
            || primaryUsage != nil
    }
}
