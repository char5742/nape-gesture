import Foundation

public enum TrackpadOutputDeliveryKind: String, Codable, Equatable, Sendable {
    case systemWide
    case targetPID
    case accessibility
    case keyboardShortcut
}

public enum TrackpadOutputProvenanceEventKind: String, Codable, Equatable, Sendable {
    case scroll
    case gesture
    case key
    case pointer
    case button
    case unknown
}

public struct TrackpadOutputProvenanceRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var logSHA256: String
    public var captureIndex: UInt64
    public var sessionID: TrackpadOutputSessionID?
    public var family: TrackpadOutputEventFamily?
    public var eventTimestamp: UInt64
    public var eventTypeRaw: Int?
    public var delivery: TrackpadOutputDeliveryKind
    public var eventKind: TrackpadOutputProvenanceEventKind
    public var destinationPID: Int32?
    public var accessibilityElementRole: String?
    public var keyboardKeyCode: Int?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        logSHA256: String,
        captureIndex: UInt64,
        sessionID: TrackpadOutputSessionID?,
        family: TrackpadOutputEventFamily?,
        eventTimestamp: UInt64,
        eventTypeRaw: Int?,
        delivery: TrackpadOutputDeliveryKind,
        eventKind: TrackpadOutputProvenanceEventKind,
        destinationPID: Int32? = nil,
        accessibilityElementRole: String? = nil,
        keyboardKeyCode: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.logSHA256 = logSHA256
        self.captureIndex = captureIndex
        self.sessionID = sessionID
        self.family = family
        self.eventTimestamp = eventTimestamp
        self.eventTypeRaw = eventTypeRaw
        self.delivery = delivery
        self.eventKind = eventKind
        self.destinationPID = destinationPID
        self.accessibilityElementRole = accessibilityElementRole
        self.keyboardKeyCode = keyboardKeyCode
    }
}

public enum TrackpadOutputProvenanceIssueCode: String, Codable, Equatable, Sendable {
    case emptyTrace
    case invalidExpectedLogSHA256
    case schemaVersionMismatch
    case invalidLogSHA256
    case logSHA256Mismatch
    case eventCountMismatch
    case captureIndexMismatch
    case logCaptureIndexMismatch
    case eventTimestampMismatch
    case missingSessionID
    case missingFamily
    case missingEventType
    case eventTypeMismatch
    case forbiddenDelivery
    case forbiddenDeliveryMetadata
    case forbiddenEventKind
    case familyEventKindMismatch
    case actualForbiddenEventKind
    case actualEventKindMismatch
    case missingGeneratedMarker
    case rawTargetProcessPresent
}

public struct TrackpadOutputProvenanceIssue: Codable, Equatable, Sendable {
    public var code: TrackpadOutputProvenanceIssueCode
    public var recordIndex: Int?
    public var captureIndex: UInt64?
    public var message: String

    public init(
        code: TrackpadOutputProvenanceIssueCode,
        recordIndex: Int? = nil,
        captureIndex: UInt64? = nil,
        message: String
    ) {
        self.code = code
        self.recordIndex = recordIndex
        self.captureIndex = captureIndex
        self.message = message
    }
}

public struct TrackpadOutputProvenanceAnalysis: Codable, Equatable, Sendable {
    public var passed: Bool
    public var recordCount: Int
    public var expectedEventCount: Int
    public var issues: [TrackpadOutputProvenanceIssue]

    public init(
        recordCount: Int,
        expectedEventCount: Int,
        issues: [TrackpadOutputProvenanceIssue]
    ) {
        self.passed = issues.isEmpty
        self.recordCount = recordCount
        self.expectedEventCount = expectedEventCount
        self.issues = issues
    }
}

public enum TrackpadOutputProvenanceAnalyzer {
    public static func analyze(
        records: [TrackpadOutputProvenanceRecord],
        expectedLogSHA256: String,
        expectedEvents: [TrackpadDriverEventLog]
    ) -> TrackpadOutputProvenanceAnalysis {
        analyze(
            records: records,
            expectedLogSHA256: expectedLogSHA256,
            expectedEventCount: expectedEvents.count,
            expectedEvents: expectedEvents
        )
    }

    public static func analyze(
        records: [TrackpadOutputProvenanceRecord],
        expectedLogSHA256: String,
        expectedEventCount: Int
    ) -> TrackpadOutputProvenanceAnalysis {
        analyze(
            records: records,
            expectedLogSHA256: expectedLogSHA256,
            expectedEventCount: expectedEventCount,
            expectedEvents: nil
        )
    }

    private static func analyze(
        records: [TrackpadOutputProvenanceRecord],
        expectedLogSHA256: String,
        expectedEventCount: Int,
        expectedEvents: [TrackpadDriverEventLog]?
    ) -> TrackpadOutputProvenanceAnalysis {
        var issues: [TrackpadOutputProvenanceIssue] = []
        let normalizedExpectedSHA = expectedLogSHA256.lowercased()

        if records.isEmpty {
            issues.append(
                TrackpadOutputProvenanceIssue(
                    code: .emptyTrace,
                    message: "generated productのprovenance traceが空です。"
                )
            )
        }
        if !isSHA256(normalizedExpectedSHA) {
            issues.append(
                TrackpadOutputProvenanceIssue(
                    code: .invalidExpectedLogSHA256,
                    message: "manifestのlog SHA-256が64桁の16進値ではありません。"
                )
            )
        }
        if expectedEventCount < 0 || records.count != expectedEventCount {
            issues.append(
                TrackpadOutputProvenanceIssue(
                    code: .eventCountMismatch,
                    message: "provenance件数がcapture manifestのevent countと一致しません。"
                )
            )
        }

        for (index, record) in records.enumerated() {
            if record.schemaVersion != TrackpadOutputProvenanceRecord.currentSchemaVersion {
                append(
                    .schemaVersionMismatch,
                    index: index,
                    record: record,
                    message: "provenance schemaVersionが現行versionと一致しません。",
                    to: &issues
                )
            }

            let normalizedRecordSHA = record.logSHA256.lowercased()
            if !isSHA256(normalizedRecordSHA) {
                append(
                    .invalidLogSHA256,
                    index: index,
                    record: record,
                    message: "provenance recordのlog SHA-256が不正です。",
                    to: &issues
                )
            } else if normalizedRecordSHA != normalizedExpectedSHA {
                append(
                    .logSHA256Mismatch,
                    index: index,
                    record: record,
                    message: "provenance recordが別のcapture logを参照しています。",
                    to: &issues
                )
            }

            if record.captureIndex != UInt64(index) {
                append(
                    .captureIndexMismatch,
                    index: index,
                    record: record,
                    message: "provenance captureIndexが0始まりの連続順序ではありません。",
                    to: &issues
                )
            }
            if let expectedEvents, expectedEvents.indices.contains(index) {
                let expectedEvent = expectedEvents[index]
                if expectedEvent.captureIndex != record.captureIndex {
                    append(
                        .logCaptureIndexMismatch,
                        index: index,
                        record: record,
                        message: "provenance captureIndexがcapture logと一致しません。",
                        to: &issues
                    )
                }
                if expectedEvent.timestamp != record.eventTimestamp {
                    append(
                        .eventTimestampMismatch,
                        index: index,
                        record: record,
                        message: "provenance event timestampがcapture logと一致しません。",
                        to: &issues
                    )
                }
                if record.eventTypeRaw != expectedEvent.typeRaw {
                    append(
                        .eventTypeMismatch,
                        index: index,
                        record: record,
                        message: "provenance event typeがcapture logと一致しません。",
                        to: &issues
                    )
                }
                validateActualEvent(
                    expectedEvent,
                    for: record,
                    index: index,
                    issues: &issues
                )
            }
            if record.sessionID == nil {
                append(
                    .missingSessionID,
                    index: index,
                    record: record,
                    message: "generated product eventにoutput session IDがありません。",
                    to: &issues
                )
            }
            if record.family == nil {
                append(
                    .missingFamily,
                    index: index,
                    record: record,
                    message: "generated product eventにoutput familyがありません。",
                    to: &issues
                )
            }
            if record.eventTypeRaw == nil {
                append(
                    .missingEventType,
                    index: index,
                    record: record,
                    message: "generated product eventにevent type raw valueがありません。",
                    to: &issues
                )
            }

            if record.delivery != .systemWide {
                append(
                    .forbiddenDelivery,
                    index: index,
                    record: record,
                    message: "generated product eventがsystem-wide以外へ配送されています。",
                    to: &issues
                )
            }
            if record.destinationPID != nil
                || record.accessibilityElementRole != nil
                || record.keyboardKeyCode != nil
            {
                append(
                    .forbiddenDeliveryMetadata,
                    index: index,
                    record: record,
                    message: "generated product eventにPID、Accessibility、shortcut metadataが混在しています。",
                    to: &issues
                )
            }

            if ![.scroll, .gesture].contains(record.eventKind) {
                append(
                    .forbiddenEventKind,
                    index: index,
                    record: record,
                    message: "generated product eventにscroll / gesture以外のevent kindが混在しています。",
                    to: &issues
                )
            }
            if let family = record.family, !eventKind(record.eventKind, matches: family) {
                append(
                    .familyEventKindMismatch,
                    index: index,
                    record: record,
                    message: "output familyとprovenance event kindが一致しません。",
                    to: &issues
                )
            }
        }

        return TrackpadOutputProvenanceAnalysis(
            recordCount: records.count,
            expectedEventCount: expectedEventCount,
            issues: issues
        )
    }

    private static func append(
        _ code: TrackpadOutputProvenanceIssueCode,
        index: Int,
        record: TrackpadOutputProvenanceRecord,
        message: String,
        to issues: inout [TrackpadOutputProvenanceIssue]
    ) {
        issues.append(
            TrackpadOutputProvenanceIssue(
                code: code,
                recordIndex: index,
                captureIndex: record.captureIndex,
                message: message
            )
        )
    }

    private static func validateActualEvent(
        _ event: TrackpadDriverEventLog,
        for record: TrackpadOutputProvenanceRecord,
        index: Int,
        issues: inout [TrackpadOutputProvenanceIssue]
    ) {
        if event.sourceUserData != NapeGestureGeneratedEventMarker.value {
            append(
                .missingGeneratedMarker,
                index: index,
                record: record,
                message: "capture logのactual eventにNape Gesture generated markerがありません。",
                to: &issues
            )
        }

        let actualKind = ActualEventKind(typeRaw: event.typeRaw)
        if actualKind.isForbidden {
            append(
                .actualForbiddenEventKind,
                index: index,
                record: record,
                message: "capture logのactual event typeがgenerated productで禁止されています。actualTypeRaw=\(event.typeRaw)",
                to: &issues
            )
        }
        if !actualEventKind(actualKind, matches: record) {
            append(
                .actualEventKindMismatch,
                index: index,
                record: record,
                message: "provenanceのfamily / event kindがcapture logのactual event typeと一致しません。actualTypeRaw=\(event.typeRaw)",
                to: &issues
            )
        }

        // raw logから判定する配送情報はtarget process fieldに限定し、AX経路は推論しない。
        let targetProcessFields = [39, 40].filter { fieldNumber in
            guard let value = event.rawField(number: fieldNumber)?.integerValue else {
                return false
            }
            return value != 0
        }
        if !targetProcessFields.isEmpty {
            append(
                .rawTargetProcessPresent,
                index: index,
                record: record,
                message: "capture logのraw fieldにtarget process指定があります。fields=\(targetProcessFields.map(String.init).joined(separator: ","))",
                to: &issues
            )
        }
    }

    private enum ActualEventKind: Equatable {
        case scroll
        case key
        case button
        case pointer
        case null
        case unclassified

        init(typeRaw: Int) {
            switch typeRaw {
            case 22:
                self = .scroll
            case 10, 11, 12:
                self = .key
            case 1, 2, 3, 4, 25, 26:
                self = .button
            case 5, 6, 7, 23, 24, 27:
                self = .pointer
            case 0:
                self = .null
            default:
                self = .unclassified
            }
        }

        var isForbidden: Bool {
            switch self {
            case .key, .button, .pointer, .null:
                true
            case .scroll, .unclassified:
                false
            }
        }
    }

    private static func actualEventKind(
        _ actualKind: ActualEventKind,
        matches record: TrackpadOutputProvenanceRecord
    ) -> Bool {
        let requiresScroll = record.family == .scroll || record.eventKind == .scroll
        let requiresGesture = record.family.map(isGestureFamily) == true || record.eventKind == .gesture

        if requiresScroll, actualKind != .scroll {
            return false
        }
        if requiresGesture, actualKind != .unclassified {
            return false
        }
        return true
    }

    private static func isGestureFamily(_ family: TrackpadOutputEventFamily) -> Bool {
        switch family {
        case .scroll:
            false
        case .dockSwipe, .navigationSwipe, .magnification:
            true
        }
    }

    private static func eventKind(
        _ eventKind: TrackpadOutputProvenanceEventKind,
        matches family: TrackpadOutputEventFamily
    ) -> Bool {
        switch family {
        case .scroll:
            eventKind == .scroll
        case .dockSwipe, .navigationSwipe, .magnification:
            eventKind == .gesture
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdef").contains(scalar)
        }
    }
}
