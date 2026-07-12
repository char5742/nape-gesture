import Foundation

public struct TrackpadDriverRawFieldValue: Codable, Equatable, Sendable {
    public var integerValue: Int64?
    public var doubleValue: Double?
    public var doubleBitPattern: UInt64?

    public init(
        integerValue: Int64? = nil,
        doubleValue: Double? = nil,
        doubleBitPattern: UInt64? = nil
    ) {
        self.integerValue = integerValue
        self.doubleValue = doubleValue
        self.doubleBitPattern = doubleBitPattern
    }
}

public struct TrackpadDriverRawField: Codable, Equatable, Sendable {
    public var fieldNumber: Int
    public var integerValue: Int64?
    public var doubleValue: Double?
    public var doubleBitPattern: UInt64

    public init(
        fieldNumber: Int,
        integerValue: Int64? = nil,
        doubleValue: Double? = nil,
        doubleBitPattern: UInt64
    ) {
        self.fieldNumber = fieldNumber
        self.integerValue = integerValue
        self.doubleValue = doubleValue
        self.doubleBitPattern = doubleBitPattern
    }
}

public struct TrackpadDriverEventLogMetadata: Codable, Equatable, Sendable {
    public static let currentLoggerVersion = 2
    public static let defaultLoggerName = "trackpad-event-log"
    public static let defaultCanonicalEventRepresentation = "serializedEventBase64"
    public static let allRawFieldValuesPolicy = "orderedAllValuesIncludingZero"

    public var loggerName: String
    public var loggerVersion: Int
    public var osVersion: String
    public var osBuild: String
    public var scenarioID: String?
    public var deviceLabel: String?
    public var repoHeadSHA: String?
    public var captureRunToken: String?
    public var canonicalEventRepresentation: String
    public var rawFieldScanPolicy: String

    public init(
        loggerName: String = Self.defaultLoggerName,
        loggerVersion: Int = Self.currentLoggerVersion,
        osVersion: String,
        osBuild: String,
        scenarioID: String? = nil,
        deviceLabel: String? = nil,
        repoHeadSHA: String? = nil,
        captureRunToken: String? = nil,
        canonicalEventRepresentation: String = Self.defaultCanonicalEventRepresentation,
        rawFieldScanPolicy: String = Self.allRawFieldValuesPolicy
    ) {
        self.loggerName = loggerName
        self.loggerVersion = loggerVersion
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.scenarioID = scenarioID
        self.deviceLabel = deviceLabel
        self.repoHeadSHA = repoHeadSHA
        self.captureRunToken = captureRunToken
        self.canonicalEventRepresentation = canonicalEventRepresentation
        self.rawFieldScanPolicy = rawFieldScanPolicy
    }
}

public struct TrackpadDriverEventLog: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let rawFieldScanLowerBound = 0
    public static let maximumRawFieldNumber = 255

    public var schemaVersion: Int
    public var metadata: TrackpadDriverEventLogMetadata?
    public var captureIndex: UInt64?
    public var timestamp: UInt64
    public var typeRaw: Int
    public var typeName: String
    public var eventSubtype: Int64?
    public var flags: UInt64
    public var scrollDeltaX: Int64
    public var scrollDeltaY: Int64
    public var scrollDeltaZ: Int64
    public var scrollFixedDeltaX: Double?
    public var scrollFixedDeltaXBitPattern: UInt64
    public var scrollFixedDeltaY: Double?
    public var scrollFixedDeltaYBitPattern: UInt64
    public var scrollFixedDeltaZ: Double?
    public var scrollFixedDeltaZBitPattern: UInt64
    public var scrollPointDeltaX: Double?
    public var scrollPointDeltaXBitPattern: UInt64
    public var scrollPointDeltaY: Double?
    public var scrollPointDeltaYBitPattern: UInt64
    public var scrollPointDeltaZ: Double?
    public var scrollPointDeltaZBitPattern: UInt64
    public var scrollPhase: Int64
    public var momentumPhase: Int64
    public var isContinuous: Int64
    public var sourceUserData: Int64
    public var rawFieldScanUpperBound: Int?
    public var rawFields: [TrackpadDriverRawField]
    public var serializedEventBase64: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case metadata
        case captureIndex
        case timestamp
        case typeRaw
        case typeName
        case eventSubtype
        case flags
        case scrollDeltaX
        case scrollDeltaY
        case scrollDeltaZ
        case scrollFixedDeltaX
        case scrollFixedDeltaXBitPattern
        case scrollFixedDeltaY
        case scrollFixedDeltaYBitPattern
        case scrollFixedDeltaZ
        case scrollFixedDeltaZBitPattern
        case scrollPointDeltaX
        case scrollPointDeltaXBitPattern
        case scrollPointDeltaY
        case scrollPointDeltaYBitPattern
        case scrollPointDeltaZ
        case scrollPointDeltaZBitPattern
        case scrollPhase
        case momentumPhase
        case isContinuous
        case sourceUserData
        case rawFieldScanUpperBound
        case rawFields
        case serializedEventBase64
    }

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        metadata: TrackpadDriverEventLogMetadata? = nil,
        captureIndex: UInt64? = nil,
        timestamp: UInt64,
        typeRaw: Int,
        typeName: String,
        eventSubtype: Int64? = nil,
        flags: UInt64 = 0,
        scrollDeltaX: Int64 = 0,
        scrollDeltaY: Int64 = 0,
        scrollDeltaZ: Int64 = 0,
        scrollFixedDeltaX: Double? = 0,
        scrollFixedDeltaXBitPattern: UInt64? = nil,
        scrollFixedDeltaY: Double? = 0,
        scrollFixedDeltaYBitPattern: UInt64? = nil,
        scrollFixedDeltaZ: Double? = 0,
        scrollFixedDeltaZBitPattern: UInt64? = nil,
        scrollPointDeltaX: Double? = 0,
        scrollPointDeltaXBitPattern: UInt64? = nil,
        scrollPointDeltaY: Double? = 0,
        scrollPointDeltaYBitPattern: UInt64? = nil,
        scrollPointDeltaZ: Double? = 0,
        scrollPointDeltaZBitPattern: UInt64? = nil,
        scrollPhase: Int64 = 0,
        momentumPhase: Int64 = 0,
        isContinuous: Int64 = 0,
        sourceUserData: Int64 = 0,
        rawFieldScanUpperBound: Int? = Self.maximumRawFieldNumber,
        rawFields: [TrackpadDriverRawField] = [],
        serializedEventBase64: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.captureIndex = captureIndex
        self.timestamp = timestamp
        self.typeRaw = typeRaw
        self.typeName = typeName
        self.eventSubtype = eventSubtype
        self.flags = flags
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.scrollDeltaZ = scrollDeltaZ
        self.scrollFixedDeltaX = scrollFixedDeltaX
        self.scrollFixedDeltaXBitPattern = scrollFixedDeltaXBitPattern ?? scrollFixedDeltaX?.bitPattern ?? 0
        self.scrollFixedDeltaY = scrollFixedDeltaY
        self.scrollFixedDeltaYBitPattern = scrollFixedDeltaYBitPattern ?? scrollFixedDeltaY?.bitPattern ?? 0
        self.scrollFixedDeltaZ = scrollFixedDeltaZ
        self.scrollFixedDeltaZBitPattern = scrollFixedDeltaZBitPattern ?? scrollFixedDeltaZ?.bitPattern ?? 0
        self.scrollPointDeltaX = scrollPointDeltaX
        self.scrollPointDeltaXBitPattern = scrollPointDeltaXBitPattern ?? scrollPointDeltaX?.bitPattern ?? 0
        self.scrollPointDeltaY = scrollPointDeltaY
        self.scrollPointDeltaYBitPattern = scrollPointDeltaYBitPattern ?? scrollPointDeltaY?.bitPattern ?? 0
        self.scrollPointDeltaZ = scrollPointDeltaZ
        self.scrollPointDeltaZBitPattern = scrollPointDeltaZBitPattern ?? scrollPointDeltaZ?.bitPattern ?? 0
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.isContinuous = isContinuous
        self.sourceUserData = sourceUserData
        self.rawFieldScanUpperBound = rawFieldScanUpperBound
        self.rawFields = rawFields.sorted { $0.fieldNumber < $1.fieldNumber }
        self.serializedEventBase64 = serializedEventBase64
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        metadata = try container.decodeIfPresent(TrackpadDriverEventLogMetadata.self, forKey: .metadata)
        captureIndex = try container.decodeIfPresent(UInt64.self, forKey: .captureIndex)
        timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        typeRaw = try container.decode(Int.self, forKey: .typeRaw)
        typeName = try container.decode(String.self, forKey: .typeName)
        eventSubtype = try container.decodeIfPresent(Int64.self, forKey: .eventSubtype)
        flags = try container.decodeIfPresent(UInt64.self, forKey: .flags) ?? 0
        scrollDeltaX = try container.decodeIfPresent(Int64.self, forKey: .scrollDeltaX) ?? 0
        scrollDeltaY = try container.decodeIfPresent(Int64.self, forKey: .scrollDeltaY) ?? 0
        scrollDeltaZ = try container.decodeIfPresent(Int64.self, forKey: .scrollDeltaZ) ?? 0
        scrollFixedDeltaX = try Self.decodeDouble(
            container,
            valueKey: .scrollFixedDeltaX,
            bitPatternKey: .scrollFixedDeltaXBitPattern,
            schemaVersion: schemaVersion
        )
        scrollFixedDeltaXBitPattern = try container.decodeIfPresent(
            UInt64.self,
            forKey: .scrollFixedDeltaXBitPattern
        ) ?? scrollFixedDeltaX?.bitPattern ?? 0
        scrollFixedDeltaY = try Self.decodeDouble(
            container,
            valueKey: .scrollFixedDeltaY,
            bitPatternKey: .scrollFixedDeltaYBitPattern,
            schemaVersion: schemaVersion
        )
        scrollFixedDeltaYBitPattern = try container.decodeIfPresent(
            UInt64.self,
            forKey: .scrollFixedDeltaYBitPattern
        ) ?? scrollFixedDeltaY?.bitPattern ?? 0
        scrollFixedDeltaZ = try Self.decodeDouble(
            container,
            valueKey: .scrollFixedDeltaZ,
            bitPatternKey: .scrollFixedDeltaZBitPattern,
            schemaVersion: schemaVersion
        )
        scrollFixedDeltaZBitPattern = try container.decodeIfPresent(
            UInt64.self,
            forKey: .scrollFixedDeltaZBitPattern
        ) ?? scrollFixedDeltaZ?.bitPattern ?? 0
        scrollPointDeltaX = try Self.decodeDouble(
            container,
            valueKey: .scrollPointDeltaX,
            bitPatternKey: .scrollPointDeltaXBitPattern,
            schemaVersion: schemaVersion
        )
        scrollPointDeltaXBitPattern = try container.decodeIfPresent(
            UInt64.self,
            forKey: .scrollPointDeltaXBitPattern
        ) ?? scrollPointDeltaX?.bitPattern ?? 0
        scrollPointDeltaY = try Self.decodeDouble(
            container,
            valueKey: .scrollPointDeltaY,
            bitPatternKey: .scrollPointDeltaYBitPattern,
            schemaVersion: schemaVersion
        )
        scrollPointDeltaYBitPattern = try container.decodeIfPresent(
            UInt64.self,
            forKey: .scrollPointDeltaYBitPattern
        ) ?? scrollPointDeltaY?.bitPattern ?? 0
        scrollPointDeltaZ = try Self.decodeDouble(
            container,
            valueKey: .scrollPointDeltaZ,
            bitPatternKey: .scrollPointDeltaZBitPattern,
            schemaVersion: schemaVersion
        )
        scrollPointDeltaZBitPattern = try container.decodeIfPresent(
            UInt64.self,
            forKey: .scrollPointDeltaZBitPattern
        ) ?? scrollPointDeltaZ?.bitPattern ?? 0
        scrollPhase = try container.decodeIfPresent(Int64.self, forKey: .scrollPhase) ?? 0
        momentumPhase = try container.decodeIfPresent(Int64.self, forKey: .momentumPhase) ?? 0
        isContinuous = try container.decodeIfPresent(Int64.self, forKey: .isContinuous) ?? 0
        sourceUserData = try container.decodeIfPresent(Int64.self, forKey: .sourceUserData) ?? 0
        rawFieldScanUpperBound = try container.decodeIfPresent(Int.self, forKey: .rawFieldScanUpperBound)
        if let orderedFields = try? container.decode([TrackpadDriverRawField].self, forKey: .rawFields) {
            rawFields = orderedFields.sorted { $0.fieldNumber < $1.fieldNumber }
        } else if let legacyFields = try? container.decode(
            [String: TrackpadDriverRawFieldValue].self,
            forKey: .rawFields
        ) {
            rawFields = legacyFields.compactMap { key, value in
                guard let fieldNumber = Int(key) else {
                    return nil
                }
                return TrackpadDriverRawField(
                    fieldNumber: fieldNumber,
                    integerValue: value.integerValue,
                    doubleValue: value.doubleValue,
                    doubleBitPattern: value.doubleBitPattern ?? value.doubleValue?.bitPattern ?? 0
                )
            }.sorted { $0.fieldNumber < $1.fieldNumber }
        } else {
            rawFields = []
        }
        serializedEventBase64 = try container.decodeIfPresent(String.self, forKey: .serializedEventBase64)
    }

    public func rawField(number: Int) -> TrackpadDriverRawField? {
        rawFields.first { $0.fieldNumber == number }
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        valueKey: CodingKeys,
        bitPatternKey: CodingKeys,
        schemaVersion: Int
    ) throws -> Double? {
        let value = try container.decodeIfPresent(Double.self, forKey: valueKey)
        if schemaVersion >= currentSchemaVersion, container.contains(bitPatternKey) {
            return value
        }
        return value ?? 0
    }
}
