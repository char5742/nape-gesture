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
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var logSHA256: String
    public var traceSHA256: String
    public var captureIndex: UInt64
    public var sessionID: TrackpadOutputSessionID?
    public var family: TrackpadOutputEventFamily?
    public var eventTimestamp: UInt64
    public var eventTypeRaw: Int?
    public var delivery: TrackpadOutputDeliveryKind
    public var eventKind: TrackpadOutputProvenanceEventKind
    public var captureRunToken: String
    public var scenarioID: String
    public var repoHeadSHA: String
    public var executableSHA256: String
    public var prePostTargetProcessSerialNumber: Int64
    public var prePostTargetUnixProcessID: Int64
    public var destinationPID: Int32?
    public var accessibilityElementRole: String?
    public var keyboardKeyCode: Int?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        logSHA256: String,
        traceSHA256: String = String(repeating: "b", count: 64),
        captureIndex: UInt64,
        sessionID: TrackpadOutputSessionID?,
        family: TrackpadOutputEventFamily?,
        eventTimestamp: UInt64,
        eventTypeRaw: Int?,
        delivery: TrackpadOutputDeliveryKind,
        eventKind: TrackpadOutputProvenanceEventKind,
        captureRunToken: String = "11111111-2222-3333-4444-555555555555",
        scenarioID: String = "provenance-test",
        repoHeadSHA: String = String(repeating: "c", count: 40),
        executableSHA256: String = String(repeating: "d", count: 64),
        prePostTargetProcessSerialNumber: Int64 = 0,
        prePostTargetUnixProcessID: Int64 = 0,
        destinationPID: Int32? = nil,
        accessibilityElementRole: String? = nil,
        keyboardKeyCode: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.logSHA256 = logSHA256
        self.traceSHA256 = traceSHA256
        self.captureIndex = captureIndex
        self.sessionID = sessionID
        self.family = family
        self.eventTimestamp = eventTimestamp
        self.eventTypeRaw = eventTypeRaw
        self.delivery = delivery
        self.eventKind = eventKind
        self.captureRunToken = captureRunToken
        self.scenarioID = scenarioID
        self.repoHeadSHA = repoHeadSHA
        self.executableSHA256 = executableSHA256
        self.prePostTargetProcessSerialNumber = prePostTargetProcessSerialNumber
        self.prePostTargetUnixProcessID = prePostTargetUnixProcessID
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
    case invalidTraceSHA256
    case traceSHA256Mismatch
    case invalidCaptureRunToken
    case captureRunTokenMismatch
    case invalidScenarioID
    case scenarioIDMismatch
    case invalidRepoHeadSHA
    case repoHeadSHAMismatch
    case invalidExecutableSHA256
    case executableSHA256Mismatch
    case eventCountMismatch
    case captureIndexMismatch
    case logCaptureIndexMismatch
    case eventTimestampMismatch
    case missingSessionID
    case invalidSessionID
    case sessionIDMismatch
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
    case prePostTargetProcessPresent
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
        expectedEvents: [TrackpadDriverEventLog],
        expectedCaptureRunToken: String? = nil,
        expectedScenarioID: String? = nil,
        expectedRepoHeadSHA: String? = nil,
        expectedExecutableSHA256: String? = nil
    ) -> TrackpadOutputProvenanceAnalysis {
        analyze(
            records: records,
            expectedLogSHA256: expectedLogSHA256,
            expectedEventCount: expectedEvents.count,
            expectedEvents: expectedEvents,
            expectedCaptureRunToken: expectedCaptureRunToken,
            expectedScenarioID: expectedScenarioID,
            expectedRepoHeadSHA: expectedRepoHeadSHA,
            expectedExecutableSHA256: expectedExecutableSHA256
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
            expectedEvents: nil,
            expectedCaptureRunToken: nil,
            expectedScenarioID: nil,
            expectedRepoHeadSHA: nil,
            expectedExecutableSHA256: nil
        )
    }

    private static func analyze(
        records: [TrackpadOutputProvenanceRecord],
        expectedLogSHA256: String,
        expectedEventCount: Int,
        expectedEvents: [TrackpadDriverEventLog]?,
        expectedCaptureRunToken: String?,
        expectedScenarioID: String?,
        expectedRepoHeadSHA: String?,
        expectedExecutableSHA256: String?
    ) -> TrackpadOutputProvenanceAnalysis {
        var issues: [TrackpadOutputProvenanceIssue] = []
        if records.isEmpty {
            issues.append(
                TrackpadOutputProvenanceIssue(
                    code: .emptyTrace,
                    message: "generated productのprovenance traceが空です。"
                )
            )
        }
        if !isSHA256(expectedLogSHA256) {
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

            if !isSHA256(record.logSHA256) {
                append(
                    .invalidLogSHA256,
                    index: index,
                    record: record,
                    message: "provenance recordのlog SHA-256が不正です。",
                    to: &issues
                )
            } else if record.logSHA256 != expectedLogSHA256 {
                append(
                    .logSHA256Mismatch,
                    index: index,
                    record: record,
                    message: "provenance recordが別のcapture logを参照しています。",
                    to: &issues
                )
            }

            if !isSHA256(record.traceSHA256) {
                append(
                    .invalidTraceSHA256,
                    index: index,
                    record: record,
                    message: "provenance recordのtrace SHA-256が不正です。",
                    to: &issues
                )
            } else if let first = records.first, record.traceSHA256 != first.traceSHA256 {
                append(
                    .traceSHA256Mismatch,
                    index: index,
                    record: record,
                    message: "provenance record間でtrace SHA-256が一致しません。",
                    to: &issues
                )
            }

            if !isCanonicalRunToken(record.captureRunToken) {
                append(
                    .invalidCaptureRunToken,
                    index: index,
                    record: record,
                    message: "provenance recordのcapture run tokenが不正です。",
                    to: &issues
                )
            } else if record.captureRunToken
                != (expectedCaptureRunToken ?? records.first?.captureRunToken)
            {
                append(
                    .captureRunTokenMismatch,
                    index: index,
                    record: record,
                    message: "provenance recordのcapture run tokenがmanifestまたは先頭recordと一致しません。",
                    to: &issues
                )
            }

            if record.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append(
                    .invalidScenarioID,
                    index: index,
                    record: record,
                    message: "provenance recordのscenario IDが空です。",
                    to: &issues
                )
            } else if record.scenarioID != (expectedScenarioID ?? records.first?.scenarioID) {
                append(
                    .scenarioIDMismatch,
                    index: index,
                    record: record,
                    message: "provenance recordのscenario IDがmanifestまたは先頭recordと一致しません。",
                    to: &issues
                )
            }

            if !isGitObjectID(record.repoHeadSHA) {
                append(
                    .invalidRepoHeadSHA,
                    index: index,
                    record: record,
                    message: "provenance recordのrepo HEAD SHAが不正です。",
                    to: &issues
                )
            } else if record.repoHeadSHA != (expectedRepoHeadSHA ?? records.first?.repoHeadSHA) {
                append(
                    .repoHeadSHAMismatch,
                    index: index,
                    record: record,
                    message: "provenance recordのrepo HEAD SHAがmanifestまたは先頭recordと一致しません。",
                    to: &issues
                )
            }

            if !isSHA256(record.executableSHA256) {
                append(
                    .invalidExecutableSHA256,
                    index: index,
                    record: record,
                    message: "provenance recordの実行binary SHA-256が不正です。",
                    to: &issues
                )
            } else if record.executableSHA256
                != (expectedExecutableSHA256 ?? records.first?.executableSHA256)
            {
                append(
                    .executableSHA256Mismatch,
                    index: index,
                    record: record,
                    message: "provenance recordの実行binary SHA-256がmanifestまたは先頭recordと一致しません。",
                    to: &issues
                )
            }

            if record.prePostTargetProcessSerialNumber != 0
                || record.prePostTargetUnixProcessID != 0
            {
                append(
                    .prePostTargetProcessPresent,
                    index: index,
                    record: record,
                    message: "投稿前eventのtarget process fieldが0ではありません。",
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
            } else if record.sessionID?.rawValue == 0 {
                append(
                    .invalidSessionID,
                    index: index,
                    record: record,
                    message: "generated product eventのoutput session IDが0です。",
                    to: &issues
                )
            } else if record.sessionID != records.first?.sessionID {
                append(
                    .sessionIDMismatch,
                    index: index,
                    record: record,
                    message: "provenance record間でoutput session IDが一致しません。",
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

        // field 39/40はsystem-wide投稿後にWindowServerが実配送先を付与するため、
        // capture logから投稿APIの宛先指定有無を逆算しない。
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
        switch record.eventKind {
        case .scroll:
            return actualKind == .scroll
        case .gesture:
            guard actualKind == .unclassified else {
                return false
            }
            if record.family == .scroll {
                return record.eventTypeRaw == 29
            }
            return true
        case .key, .pointer, .button, .unknown:
            return false
        }
    }

    private static func eventKind(
        _ eventKind: TrackpadOutputProvenanceEventKind,
        matches family: TrackpadOutputEventFamily
    ) -> Bool {
        switch family {
        case .scroll:
            eventKind == .scroll || eventKind == .gesture
        case .dockSwipe, .dockSwipePinch:
            eventKind == .gesture
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdef").contains(scalar)
        }
    }

    private static func isGitObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdef").contains(scalar)
        }
    }

    private static func isCanonicalRunToken(_ value: String) -> Bool {
        UUID(uuidString: value)?.uuidString.lowercased() == value
    }
}
