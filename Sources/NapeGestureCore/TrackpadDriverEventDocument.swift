import Foundation

public struct TrackpadDriverEventDocument: Codable, Equatable, Sendable {
    public var line: Int
    public var rawLineData: Data
    public var eventLog: TrackpadDriverEventLog
    public var rawTopLevelObject: LosslessJSONObject
    public var rawFields: [LosslessJSONValue]
    public var unknownTopLevelFields: LosslessJSONObject
    public var unknownMetadataFields: LosslessJSONObject

    public init(
        line: Int,
        rawLineData: Data,
        eventLog: TrackpadDriverEventLog,
        rawTopLevelObject: LosslessJSONObject,
        rawFields: [LosslessJSONValue],
        unknownTopLevelFields: LosslessJSONObject,
        unknownMetadataFields: LosslessJSONObject
    ) {
        self.line = line
        self.rawLineData = rawLineData
        self.eventLog = eventLog
        self.rawTopLevelObject = rawTopLevelObject
        self.rawFields = rawFields
        self.unknownTopLevelFields = unknownTopLevelFields
        self.unknownMetadataFields = unknownMetadataFields
    }

    public var log: TrackpadDriverEventLog {
        eventLog
    }

    public var typedLog: TrackpadDriverEventLog {
        eventLog
    }

    public var rawMetadata: LosslessJSONObject? {
        rawTopLevelObject["metadata"]?.objectValue
    }
}

extension TrackpadDriverEventDocument {
    static let currentTopLevelFieldNames: Set<String> = [
        "schemaVersion",
        "metadata",
        "captureIndex",
        "timestamp",
        "typeRaw",
        "typeName",
        "eventSubtype",
        "flags",
        "scrollDeltaX",
        "scrollDeltaY",
        "scrollDeltaZ",
        "scrollFixedDeltaX",
        "scrollFixedDeltaXBitPattern",
        "scrollFixedDeltaY",
        "scrollFixedDeltaYBitPattern",
        "scrollFixedDeltaZ",
        "scrollFixedDeltaZBitPattern",
        "scrollPointDeltaX",
        "scrollPointDeltaXBitPattern",
        "scrollPointDeltaY",
        "scrollPointDeltaYBitPattern",
        "scrollPointDeltaZ",
        "scrollPointDeltaZBitPattern",
        "scrollPhase",
        "momentumPhase",
        "isContinuous",
        "sourceUserData",
        "rawFieldScanUpperBound",
        "rawFields",
        "serializedEventBase64"
    ]

    static let currentMetadataFieldNames: Set<String> = [
        "loggerName",
        "loggerVersion",
        "osVersion",
        "osBuild",
        "scenarioID",
        "deviceLabel",
        "repoHeadSHA",
        "canonicalEventRepresentation",
        "rawFieldScanPolicy"
    ]
}
