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
        evaluate(device).isMatch
    }

    public func evaluate(_ device: DeviceIdentity) -> DeviceMatcherEvaluation {
        var matchedConditions: [String] = []
        var mismatches: [DeviceMatcherConditionMismatch] = []

        evaluateEqual(
            field: "vendorID",
            expected: vendorID,
            actual: device.vendorID,
            matchedConditions: &matchedConditions,
            mismatches: &mismatches
        )
        evaluateEqual(
            field: "productID",
            expected: productID,
            actual: device.productID,
            matchedConditions: &matchedConditions,
            mismatches: &mismatches
        )
        evaluateContains(
            field: "manufacturer",
            expectedContains: manufacturerContains,
            actual: device.manufacturer,
            matchedConditions: &matchedConditions,
            mismatches: &mismatches
        )
        evaluateContains(
            field: "product",
            expectedContains: productContains,
            actual: device.product,
            matchedConditions: &matchedConditions,
            mismatches: &mismatches
        )
        evaluateContains(
            field: "transport",
            expectedContains: transportContains,
            actual: device.transport,
            matchedConditions: &matchedConditions,
            mismatches: &mismatches
        )
        evaluateEqual(
            field: "primaryUsagePage",
            expected: primaryUsagePage,
            actual: device.primaryUsagePage,
            matchedConditions: &matchedConditions,
            mismatches: &mismatches
        )
        evaluateEqual(
            field: "primaryUsage",
            expected: primaryUsage,
            actual: device.primaryUsage,
            matchedConditions: &matchedConditions,
            mismatches: &mismatches
        )

        return DeviceMatcherEvaluation(
            conditionCount: conditionCount,
            matchedConditions: matchedConditions,
            mismatches: mismatches
        )
    }

    public var conditionCount: Int {
        [
            vendorID.map { _ in 1 },
            productID.map { _ in 1 },
            nonEmpty(manufacturerContains).map { _ in 1 },
            nonEmpty(productContains).map { _ in 1 },
            nonEmpty(transportContains).map { _ in 1 },
            primaryUsagePage.map { _ in 1 },
            primaryUsage.map { _ in 1 }
        ]
        .compactMap { $0 }
        .reduce(0, +)
    }

    public var hasAnyCondition: Bool {
        conditionCount > 0
    }

    private func evaluateEqual(
        field: String,
        expected: Int?,
        actual: Int,
        matchedConditions: inout [String],
        mismatches: inout [DeviceMatcherConditionMismatch]
    ) {
        guard let expected else {
            return
        }
        if expected == actual {
            matchedConditions.append(field)
        } else {
            mismatches.append(
                DeviceMatcherConditionMismatch(
                    field: field,
                    expected: String(expected),
                    actual: String(actual),
                    relation: "equals"
                )
            )
        }
    }

    private func evaluateContains(
        field: String,
        expectedContains: String?,
        actual: String,
        matchedConditions: inout [String],
        mismatches: inout [DeviceMatcherConditionMismatch]
    ) {
        guard let expectedContains = nonEmpty(expectedContains) else {
            return
        }
        if actual.localizedCaseInsensitiveContains(expectedContains) {
            matchedConditions.append(field)
        } else {
            mismatches.append(
                DeviceMatcherConditionMismatch(
                    field: field,
                    expected: expectedContains,
                    actual: actual,
                    relation: "contains"
                )
            )
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

public struct DeviceMatcherEvaluation: Codable, Equatable, Sendable {
    public var conditionCount: Int
    public var matchedConditionCount: Int
    public var matchedConditions: [String]
    public var mismatches: [DeviceMatcherConditionMismatch]
    public var isMatch: Bool

    public init(
        conditionCount: Int,
        matchedConditions: [String],
        mismatches: [DeviceMatcherConditionMismatch]
    ) {
        self.conditionCount = conditionCount
        self.matchedConditions = matchedConditions
        matchedConditionCount = matchedConditions.count
        self.mismatches = mismatches
        isMatch = conditionCount > 0 && mismatches.isEmpty
    }
}

public struct DeviceMatcherConditionMismatch: Codable, Equatable, Sendable {
    public var field: String
    public var expected: String
    public var actual: String
    public var relation: String

    public init(field: String, expected: String, actual: String, relation: String) {
        self.field = field
        self.expected = expected
        self.actual = actual
        self.relation = relation
    }
}
