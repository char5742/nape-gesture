import CryptoKit
import Foundation

public enum TrackpadDriverEventEvidenceKind: String, Codable, CaseIterable, Sendable {
    case synthetic
    case physicalTrackpad
    case generatedProduct
}

public struct TrackpadDriverEventCaptureLogSummary: Equatable, Sendable {
    public var logSHA256: String
    public var logByteCount: UInt64
    public var eventCount: UInt64
    public var firstEventTimestamp: UInt64
    public var lastEventTimestamp: UInt64
    public var metadata: TrackpadDriverEventLogMetadata

    public init(
        logSHA256: String,
        logByteCount: UInt64,
        eventCount: UInt64,
        firstEventTimestamp: UInt64,
        lastEventTimestamp: UInt64,
        metadata: TrackpadDriverEventLogMetadata
    ) {
        self.logSHA256 = logSHA256
        self.logByteCount = logByteCount
        self.eventCount = eventCount
        self.firstEventTimestamp = firstEventTimestamp
        self.lastEventTimestamp = lastEventTimestamp
        self.metadata = metadata
    }
}

public enum TrackpadDriverEventCaptureLogInspectionError: LocalizedError, Equatable {
    case emptyLog
    case unterminatedLastRecord
    case emptyRecord(line: UInt64)
    case invalidRecord(line: UInt64, details: String)
    case missingMetadata(line: UInt64)
    case metadataMismatch(line: UInt64)
    case eventCountOverflow

    public var errorDescription: String? {
        switch self {
        case .emptyLog:
            return "確定済みトラックパッドイベントログにeventがありません。"
        case .unterminatedLastRecord:
            return "確定済みトラックパッドイベントログの最終JSON Lines recordが改行で終端されていません。"
        case let .emptyRecord(line):
            return "確定済みトラックパッドイベントログに空recordがあります。line=\(line)"
        case let .invalidRecord(line, details):
            return "確定済みトラックパッドイベントログのrecordをdecodeできません。line=\(line) details=\(details)"
        case let .missingMetadata(line):
            return "確定済みトラックパッドイベントログのmetadataがありません。line=\(line)"
        case let .metadataMismatch(line):
            return "確定済みトラックパッドイベントログ内でmetadataが一致しません。line=\(line)"
        case .eventCountOverflow:
            return "確定済みトラックパッドイベントログのevent数が上限を超えました。"
        }
    }
}

public enum TrackpadDriverEventCaptureManifestValidationError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidLogSHA256
    case emptyLog
    case zeroEvents
    case invalidTimestampRange
    case invalidOSVersion
    case invalidOSBuild
    case invalidScenarioID
    case invalidDeviceLabel
    case invalidRepoHeadSHA
    case missingScenarioID(evidenceKind: TrackpadDriverEventEvidenceKind)
    case missingDeviceLabel(evidenceKind: TrackpadDriverEventEvidenceKind)
    case missingRepoHeadSHA(evidenceKind: TrackpadDriverEventEvidenceKind)
    case invalidLoggerVersion
    case invalidLoggerExecutableSHA256
    case invalidCaptureCompletionWallClock
    case logMismatch(field: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "未対応のcapture manifest schemaVersionです: \(version)"
        case .invalidLogSHA256:
            return "capture manifestのlogSHA256が正規化済みSHA-256ではありません。"
        case .emptyLog:
            return "capture manifestのlogByteCountは1以上である必要があります。"
        case .zeroEvents:
            return "capture manifestのeventCountは1以上である必要があります。"
        case .invalidTimestampRange:
            return "capture manifestのfirstEventTimestampがlastEventTimestampを超えています。"
        case .invalidOSVersion:
            return "capture manifestのosVersionが空です。"
        case .invalidOSBuild:
            return "capture manifestのosBuildが空です。"
        case .invalidScenarioID:
            return "capture manifestのscenarioIDが空です。"
        case .invalidDeviceLabel:
            return "capture manifestのdeviceLabelが空です。"
        case .invalidRepoHeadSHA:
            return "capture manifestのrepoHeadSHAが完全な正規化済みGit object IDではありません。"
        case let .missingScenarioID(evidenceKind):
            return "\(evidenceKind.rawValue)証跡のcapture manifestにはscenarioIDが必要です。"
        case let .missingDeviceLabel(evidenceKind):
            return "\(evidenceKind.rawValue)証跡のcapture manifestにはdeviceLabelが必要です。"
        case let .missingRepoHeadSHA(evidenceKind):
            return "\(evidenceKind.rawValue)証跡のcapture manifestにはrepoHeadSHAが必要です。"
        case .invalidLoggerVersion:
            return "capture manifestのloggerVersionは1以上である必要があります。"
        case .invalidLoggerExecutableSHA256:
            return "capture manifestのloggerExecutableSHA256が正規化済みSHA-256ではありません。"
        case .invalidCaptureCompletionWallClock:
            return "capture manifestのcaptureCompletedAtがISO 8601 wall-clockではありません。"
        case let .logMismatch(field):
            return "capture manifestと確定済みログが一致しません。field=\(field)"
        }
    }
}

public struct TrackpadDriverEventCaptureManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var evidenceKind: TrackpadDriverEventEvidenceKind
    public var logSHA256: String
    public var logByteCount: UInt64
    public var eventCount: UInt64
    public var firstEventTimestamp: UInt64
    public var lastEventTimestamp: UInt64
    public var osVersion: String
    public var osBuild: String
    public var scenarioID: String?
    public var deviceLabel: String?
    public var repoHeadSHA: String?
    public var loggerVersion: Int
    public var loggerExecutableSHA256: String
    public var captureCompletedAt: String

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        evidenceKind: TrackpadDriverEventEvidenceKind,
        logSHA256: String,
        logByteCount: UInt64,
        eventCount: UInt64,
        firstEventTimestamp: UInt64,
        lastEventTimestamp: UInt64,
        osVersion: String,
        osBuild: String,
        scenarioID: String? = nil,
        deviceLabel: String? = nil,
        repoHeadSHA: String? = nil,
        loggerVersion: Int,
        loggerExecutableSHA256: String,
        captureCompletedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.evidenceKind = evidenceKind
        self.logSHA256 = logSHA256
        self.logByteCount = logByteCount
        self.eventCount = eventCount
        self.firstEventTimestamp = firstEventTimestamp
        self.lastEventTimestamp = lastEventTimestamp
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.scenarioID = scenarioID
        self.deviceLabel = deviceLabel
        self.repoHeadSHA = repoHeadSHA
        self.loggerVersion = loggerVersion
        self.loggerExecutableSHA256 = loggerExecutableSHA256
        self.captureCompletedAt = captureCompletedAt
    }

    public init(
        evidenceKind: TrackpadDriverEventEvidenceKind,
        logSummary: TrackpadDriverEventCaptureLogSummary,
        loggerExecutableSHA256: String,
        captureCompletedAt: Date
    ) {
        let metadata = logSummary.metadata
        self.init(
            evidenceKind: evidenceKind,
            logSHA256: logSummary.logSHA256,
            logByteCount: logSummary.logByteCount,
            eventCount: logSummary.eventCount,
            firstEventTimestamp: logSummary.firstEventTimestamp,
            lastEventTimestamp: logSummary.lastEventTimestamp,
            osVersion: metadata.osVersion,
            osBuild: metadata.osBuild,
            scenarioID: metadata.scenarioID,
            deviceLabel: metadata.deviceLabel,
            repoHeadSHA: metadata.repoHeadSHA,
            loggerVersion: metadata.loggerVersion,
            loggerExecutableSHA256: loggerExecutableSHA256,
            captureCompletedAt: Self.wallClockString(for: captureCompletedAt)
        )
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TrackpadDriverEventCaptureManifestValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard Self.isCanonicalSHA256(logSHA256) else {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidLogSHA256
        }
        guard logByteCount > 0 else {
            throw TrackpadDriverEventCaptureManifestValidationError.emptyLog
        }
        guard eventCount > 0 else {
            throw TrackpadDriverEventCaptureManifestValidationError.zeroEvents
        }
        guard firstEventTimestamp <= lastEventTimestamp else {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidTimestampRange
        }
        guard Self.hasContent(osVersion) else {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidOSVersion
        }
        guard Self.hasContent(osBuild) else {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidOSBuild
        }
        if let scenarioID, !Self.hasContent(scenarioID) {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidScenarioID
        }
        if let deviceLabel, !Self.hasContent(deviceLabel) {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidDeviceLabel
        }
        if let repoHeadSHA, !Self.isCanonicalGitObjectID(repoHeadSHA) {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidRepoHeadSHA
        }
        if evidenceKind != .synthetic {
            guard scenarioID != nil else {
                throw TrackpadDriverEventCaptureManifestValidationError.missingScenarioID(
                    evidenceKind: evidenceKind
                )
            }
            guard deviceLabel != nil else {
                throw TrackpadDriverEventCaptureManifestValidationError.missingDeviceLabel(
                    evidenceKind: evidenceKind
                )
            }
            guard repoHeadSHA != nil else {
                throw TrackpadDriverEventCaptureManifestValidationError.missingRepoHeadSHA(
                    evidenceKind: evidenceKind
                )
            }
        }
        guard loggerVersion > 0 else {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidLoggerVersion
        }
        guard Self.isCanonicalSHA256(loggerExecutableSHA256) else {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidLoggerExecutableSHA256
        }
        guard Self.wallClockDate(from: captureCompletedAt) != nil else {
            throw TrackpadDriverEventCaptureManifestValidationError.invalidCaptureCompletionWallClock
        }
    }

    public func validate(logData: Data) throws {
        try validate()
        let summary = try Self.summarize(logData: logData)
        let metadata = summary.metadata

        try requireEqual(logSHA256, summary.logSHA256, field: "logSHA256")
        try requireEqual(logByteCount, summary.logByteCount, field: "logByteCount")
        try requireEqual(eventCount, summary.eventCount, field: "eventCount")
        try requireEqual(firstEventTimestamp, summary.firstEventTimestamp, field: "firstEventTimestamp")
        try requireEqual(lastEventTimestamp, summary.lastEventTimestamp, field: "lastEventTimestamp")
        try requireEqual(osVersion, metadata.osVersion, field: "osVersion")
        try requireEqual(osBuild, metadata.osBuild, field: "osBuild")
        try requireEqual(scenarioID, metadata.scenarioID, field: "scenarioID")
        try requireEqual(deviceLabel, metadata.deviceLabel, field: "deviceLabel")
        try requireEqual(repoHeadSHA, metadata.repoHeadSHA, field: "repoHeadSHA")
        try requireEqual(loggerVersion, metadata.loggerVersion, field: "loggerVersion")
    }

    public static func summarize(logData: Data) throws -> TrackpadDriverEventCaptureLogSummary {
        guard !logData.isEmpty else {
            throw TrackpadDriverEventCaptureLogInspectionError.emptyLog
        }
        guard logData.last == 0x0A else {
            throw TrackpadDriverEventCaptureLogInspectionError.unterminatedLastRecord
        }

        let decoder = JSONDecoder()
        var lineStart = logData.startIndex
        var lineNumber: UInt64 = 0
        var eventCount: UInt64 = 0
        var firstEventTimestamp: UInt64?
        var lastEventTimestamp: UInt64?
        var sharedMetadata: TrackpadDriverEventLogMetadata?

        for index in logData.indices where logData[index] == 0x0A {
            let (nextLineNumber, lineOverflow) = lineNumber.addingReportingOverflow(1)
            guard !lineOverflow else {
                throw TrackpadDriverEventCaptureLogInspectionError.eventCountOverflow
            }
            lineNumber = nextLineNumber
            guard lineStart != index else {
                throw TrackpadDriverEventCaptureLogInspectionError.emptyRecord(line: lineNumber)
            }

            let recordData = logData.subdata(in: lineStart..<index)
            let record: TrackpadDriverEventLog
            do {
                record = try decoder.decode(TrackpadDriverEventLog.self, from: recordData)
            } catch {
                throw TrackpadDriverEventCaptureLogInspectionError.invalidRecord(
                    line: lineNumber,
                    details: error.localizedDescription
                )
            }

            guard let metadata = record.metadata else {
                throw TrackpadDriverEventCaptureLogInspectionError.missingMetadata(line: lineNumber)
            }
            if let sharedMetadata, sharedMetadata != metadata {
                throw TrackpadDriverEventCaptureLogInspectionError.metadataMismatch(line: lineNumber)
            }
            sharedMetadata = metadata

            let (nextEventCount, eventOverflow) = eventCount.addingReportingOverflow(1)
            guard !eventOverflow else {
                throw TrackpadDriverEventCaptureLogInspectionError.eventCountOverflow
            }
            eventCount = nextEventCount
            if firstEventTimestamp == nil {
                firstEventTimestamp = record.timestamp
            }
            lastEventTimestamp = record.timestamp
            lineStart = logData.index(after: index)
        }

        guard
            eventCount > 0,
            let firstEventTimestamp,
            let lastEventTimestamp,
            let sharedMetadata
        else {
            throw TrackpadDriverEventCaptureLogInspectionError.emptyLog
        }

        return TrackpadDriverEventCaptureLogSummary(
            logSHA256: sha256HexDigest(of: logData),
            logByteCount: UInt64(logData.count),
            eventCount: eventCount,
            firstEventTimestamp: firstEventTimestamp,
            lastEventTimestamp: lastEventTimestamp,
            metadata: sharedMetadata
        )
    }

    public static func sha256HexDigest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func wallClockString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func requireEqual<Value: Equatable>(
        _ manifestValue: Value,
        _ logValue: Value,
        field: String
    ) throws {
        guard manifestValue == logValue else {
            throw TrackpadDriverEventCaptureManifestValidationError.logMismatch(field: field)
        }
    }

    private static func hasContent(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && isLowercaseHex(value)
    }

    private static func isCanonicalGitObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.count) && isLowercaseHex(value)
    }

    private static func isLowercaseHex(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
        }
    }

    private static func wallClockDate(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
