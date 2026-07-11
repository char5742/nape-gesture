import Darwin
import Foundation
import NapeGestureCore
import NapeGestureDiagnosticOutput

final class AnalyzeTrackpadEventLogCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        if options == ["--help"] || options == ["-h"] {
            printHelp()
            return
        }

        let configuration = try parseConfiguration()
        let logData = try readData(path: configuration.logPath, role: "event log")
        let logSHA256 = TrackpadDriverEventCaptureManifest.sha256HexDigest(of: logData)
        let coreReport = TrackpadDriverEventAnalyzer.analyze(logData)
        let structure = TrackpadEventStructureAnalysis(report: coreReport)
        let eventLogs = coreReport.documents.map(\.eventLog)

        let manifest = analyzeManifest(
            path: configuration.manifestPath,
            logData: logData
        )
        let host = TrackpadDriverEventHostAnalyzer.analyze(records: eventLogs)
        let provenance = analyzeProvenance(
            path: configuration.provenancePath,
            required: manifest.value?.evidenceKind == .generatedProduct,
            expectedLogSHA256: manifest.value?.logSHA256 ?? logSHA256,
            expectedEvents: eventLogs
        )

        let report = TrackpadEventLogAnalysisReport(
            logPath: configuration.logPath,
            manifestPath: configuration.manifestPath,
            provenancePath: configuration.provenancePath,
            logSHA256: logSHA256,
            structure: structure,
            manifest: manifest,
            hostReconstruction: host,
            provenance: provenance
        )
        printReport(report, json: configuration.json)
        fflush(stdout)
        guard report.passed else {
            throw TrackpadEventLogAnalysisFailure()
        }
    }

    private func parseConfiguration() throws -> TrackpadEventLogAnalysisConfiguration {
        var logPath: String?
        var manifestPath: String?
        var provenancePath: String?
        var json = false
        var index = 0
        var seenOptions = Set<String>()

        while index < options.count {
            let option = options[index]
            switch option {
            case "--manifest", "--provenance":
                guard seenOptions.insert(option).inserted else {
                    throw TrackpadEventLogAnalysisCommandError.duplicateOption(option)
                }
                guard index + 1 < options.count else {
                    throw ToolError.missingValue(option)
                }
                let value = options[index + 1]
                guard !value.isEmpty else {
                    throw ToolError.invalidValue(option, value)
                }
                if option == "--manifest" {
                    manifestPath = value
                } else {
                    provenancePath = value
                }
                index += 2
            case "--json":
                guard seenOptions.insert(option).inserted else {
                    throw TrackpadEventLogAnalysisCommandError.duplicateOption(option)
                }
                json = true
                index += 1
            default:
                if option.hasPrefix("-") {
                    throw TrackpadEventLogAnalysisCommandError.unknownOption(option)
                }
                guard logPath == nil else {
                    throw TrackpadEventLogAnalysisCommandError.unexpectedArgument(option)
                }
                logPath = option
                index += 1
            }
        }

        guard let logPath else {
            throw TrackpadEventLogAnalysisCommandError.missingLogPath
        }
        guard let manifestPath else {
            throw TrackpadEventLogAnalysisCommandError.missingManifestPath
        }
        return TrackpadEventLogAnalysisConfiguration(
            logPath: logPath,
            manifestPath: manifestPath,
            provenancePath: provenancePath,
            json: json
        )
    }

    private func analyzeManifest(
        path: String,
        logData: Data
    ) -> TrackpadEventManifestAnalysis {
        var issues: [TrackpadEventSectionIssue] = []
        let data: Data
        do {
            data = try readData(path: path, role: "capture manifest")
        } catch {
            issues.append(.init(code: "read_failed", message: error.localizedDescription))
            return TrackpadEventManifestAnalysis(value: nil, issues: issues)
        }

        if data.last != 0x0A {
            issues.append(
                .init(
                    code: "missing_final_line_feed",
                    message: "capture manifestはLFで終端されていません。"
                )
            )
        }
        if data.dropLast().contains(0x0A) {
            issues.append(
                .init(
                    code: "multiple_lines",
                    message: "capture manifestは1行1objectである必要があります。"
                )
            )
        }

        let rawObject: LosslessJSONObject?
        do {
            rawObject = try StrictJSONDocumentParser.parseObject(data: data)
        } catch {
            rawObject = nil
            issues.append(.init(code: "malformed_json", message: error.localizedDescription))
        }
        if let rawObject {
            let unknownKeys = rawObject.members
                .map(\.key)
                .filter { !Self.manifestFieldNames.contains($0) }
                .sorted()
            if !unknownKeys.isEmpty {
                issues.append(
                    .init(
                        code: "unknown_fields",
                        message: "現行capture manifestに未知fieldがあります: \(unknownKeys.joined(separator: ","))"
                    )
                )
            }
        }

        let manifest: TrackpadDriverEventCaptureManifest?
        do {
            manifest = try JSONDecoder().decode(
                TrackpadDriverEventCaptureManifest.self,
                from: data
            )
        } catch {
            manifest = nil
            issues.append(.init(code: "typed_decode_failed", message: error.localizedDescription))
        }
        if let manifest {
            do {
                try manifest.validate(logData: logData)
            } catch {
                issues.append(.init(code: "validation_failed", message: error.localizedDescription))
            }
        }
        return TrackpadEventManifestAnalysis(value: manifest, issues: issues)
    }

    private func analyzeProvenance(
        path: String?,
        required: Bool,
        expectedLogSHA256: String,
        expectedEvents: [TrackpadDriverEventLog]
    ) -> TrackpadEventProvenanceSection {
        guard let path else {
            let issues = required
                ? [
                    TrackpadEventSectionIssue(
                        code: "required_trace_missing",
                        message: "generatedProductのcaptureには--provenanceが必要です。"
                    )
                ]
                : []
            return TrackpadEventProvenanceSection(
                required: required,
                provided: false,
                recordCount: 0,
                unknownFields: [],
                analysis: nil,
                issues: issues
            )
        }

        let data: Data
        do {
            data = try readData(path: path, role: "provenance trace")
        } catch {
            return TrackpadEventProvenanceSection(
                required: required,
                provided: true,
                recordCount: 0,
                unknownFields: [],
                analysis: nil,
                issues: [.init(code: "read_failed", message: error.localizedDescription)]
            )
        }

        let documents: [TrackpadOutputProvenanceDocument]
        do {
            documents = try TrackpadOutputProvenanceDocumentReader.read(data: data)
        } catch {
            return TrackpadEventProvenanceSection(
                required: required,
                provided: true,
                recordCount: 0,
                unknownFields: [],
                analysis: nil,
                issues: [.init(code: "invalid_json_lines", message: error.localizedDescription)]
            )
        }

        let unknownFields = documents.compactMap { document -> TrackpadEventUnknownFields? in
            let unknown = document.rawObject.filteringKeys {
                !Self.provenanceFieldNames.contains($0)
            }
            guard !unknown.members.isEmpty else {
                return nil
            }
            return TrackpadEventUnknownFields(
                line: document.line,
                captureIndex: document.record.captureIndex,
                topLevel: unknown,
                metadata: LosslessJSONObject()
            )
        }
        let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
            records: documents.map(\.record),
            expectedLogSHA256: expectedLogSHA256,
            expectedEvents: expectedEvents
        )
        return TrackpadEventProvenanceSection(
            required: required,
            provided: true,
            recordCount: documents.count,
            unknownFields: unknownFields,
            analysis: analysis,
            issues: []
        )
    }

    private func readData(path: String, role: String) throws -> Data {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        } catch {
            throw TrackpadEventLogAnalysisCommandError.fileReadFailed(
                role: role,
                path: path,
                details: error.localizedDescription
            )
        }
    }

    private func printReport(_ report: TrackpadEventLogAnalysisReport, json: Bool) {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report) {
                print(String(decoding: data, as: UTF8.self))
                return
            }
        }

        print("Trackpad event解析: \(report.passed ? "成功" : "失敗")")
        print("log SHA-256: \(report.logSHA256)")
        print("構造: \(status(report.structure.passed)) events=\(report.structure.eventCount) issues=\(report.structure.issues.count)")
        print("manifest: \(status(report.manifest.passed)) evidenceKind=\(report.manifest.value?.evidenceKind.rawValue ?? "不明") issues=\(report.manifest.issues.count)")
        print("CGEvent再構築: \(status(report.hostReconstruction.passed)) reconstructed=\(report.hostReconstruction.reconstructedEventCount)/\(report.hostReconstruction.eventCount) issues=\(report.hostReconstruction.issues.count) rawDifferences=\(report.hostReconstruction.rawFieldDifferences.count)")
        print("provenance: \(status(report.provenance.passed)) required=\(report.provenance.required) provided=\(report.provenance.provided) records=\(report.provenance.recordCount)")

        for issue in report.structure.issues {
            print("- [structure/\(issue.code.rawValue)] line=\(issue.line.map(String.init) ?? "-") captureIndex=\(issue.captureIndex.map(String.init) ?? "-"): \(issue.message)")
        }
        for issue in report.manifest.issues {
            print("- [manifest/\(issue.code)] \(issue.message)")
        }
        for issue in report.hostReconstruction.issues {
            print("- [host/\(issue.field)] captureIndex=\(issue.captureIndex.map(String.init) ?? "-"): \(issue.message)")
        }
        for difference in report.hostReconstruction.rawFieldDifferences {
            print("- [host/raw-difference/\(difference.field)] captureIndex=\(difference.captureIndex.map(String.init) ?? "-"): \(difference.message)")
        }
        for issue in report.provenance.issues {
            print("- [provenance/\(issue.code)] \(issue.message)")
        }
        for issue in report.provenance.analysis?.issues ?? [] {
            print("- [provenance/\(issue.code.rawValue)] record=\(issue.recordIndex.map(String.init) ?? "-") captureIndex=\(issue.captureIndex.map(String.init) ?? "-"): \(issue.message)")
        }
    }

    private func status(_ passed: Bool) -> String {
        passed ? "成功" : "失敗"
    }

    private func printHelp() {
        print(
            """
            nape-gesture analyze-trackpad-event-log <log.jsonl> --manifest <manifest.json> [--provenance <trace.jsonl>] [--json]

            trackpad-event-logの現行raw schema、capture manifest、serialized CGEvent再構築を検証します。
            evidenceKindがgeneratedProductの場合は--provenanceが必須です。生成marker、actual event type、raw target process field、配送provenanceを照合し、製品source境界guardと併せてPID、Accessibility、shortcut経路を禁止します。
            合成eventの成功はlogger / analyzer経路の機械検証であり、純正trackpad contract値の完成証跡にはなりません。
            問題がある場合もreportを出力した後に非ゼロ終了します。
            """
        )
    }

    private static let manifestFieldNames: Set<String> = [
        "schemaVersion",
        "evidenceKind",
        "logSHA256",
        "logByteCount",
        "eventCount",
        "firstEventTimestamp",
        "lastEventTimestamp",
        "osVersion",
        "osBuild",
        "scenarioID",
        "deviceLabel",
        "repoHeadSHA",
        "loggerVersion",
        "loggerExecutableSHA256",
        "captureStartedAt",
        "captureCompletedAt"
    ]

    private static let provenanceFieldNames: Set<String> = [
        "schemaVersion",
        "logSHA256",
        "captureIndex",
        "sessionID",
        "family",
        "eventTimestamp",
        "eventTypeRaw",
        "delivery",
        "eventKind",
        "destinationPID",
        "accessibilityElementRole",
        "keyboardKeyCode"
    ]
}

private struct TrackpadEventLogAnalysisConfiguration {
    var logPath: String
    var manifestPath: String
    var provenancePath: String?
    var json: Bool
}

private struct TrackpadEventSectionIssue: Codable, Equatable {
    var code: String
    var message: String
}

private struct TrackpadEventUnknownFields: Codable, Equatable {
    var line: Int
    var captureIndex: UInt64?
    var topLevel: LosslessJSONObject
    var metadata: LosslessJSONObject
}

private struct TrackpadEventStructureAnalysis: Codable, Equatable {
    var passed: Bool
    var eventCount: Int
    var unknownFields: [TrackpadEventUnknownFields]
    var issues: [TrackpadDriverEventAnalyzerIssue]

    init(report: TrackpadDriverEventAnalyzerReport) {
        passed = report.passed
        eventCount = report.documents.count
        unknownFields = report.documents.compactMap { document in
            guard !document.unknownTopLevelFields.members.isEmpty
                || !document.unknownMetadataFields.members.isEmpty
            else {
                return nil
            }
            return TrackpadEventUnknownFields(
                line: document.line,
                captureIndex: document.eventLog.captureIndex,
                topLevel: document.unknownTopLevelFields,
                metadata: document.unknownMetadataFields
            )
        }
        issues = report.issues
    }
}

private struct TrackpadEventManifestAnalysis: Codable, Equatable {
    var passed: Bool
    var value: TrackpadDriverEventCaptureManifest?
    var issues: [TrackpadEventSectionIssue]

    init(value: TrackpadDriverEventCaptureManifest?, issues: [TrackpadEventSectionIssue]) {
        passed = value != nil && issues.isEmpty
        self.value = value
        self.issues = issues
    }
}

private struct TrackpadEventProvenanceSection: Codable, Equatable {
    var passed: Bool
    var required: Bool
    var provided: Bool
    var recordCount: Int
    var unknownFields: [TrackpadEventUnknownFields]
    var analysis: TrackpadOutputProvenanceAnalysis?
    var issues: [TrackpadEventSectionIssue]

    init(
        required: Bool,
        provided: Bool,
        recordCount: Int,
        unknownFields: [TrackpadEventUnknownFields],
        analysis: TrackpadOutputProvenanceAnalysis?,
        issues: [TrackpadEventSectionIssue]
    ) {
        self.required = required
        self.provided = provided
        self.recordCount = recordCount
        self.unknownFields = unknownFields
        self.analysis = analysis
        self.issues = issues
        if required && !provided {
            passed = false
        } else if provided {
            passed = issues.isEmpty && analysis?.passed == true
        } else {
            passed = issues.isEmpty
        }
    }
}

private struct TrackpadEventLogAnalysisReport: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var passed: Bool
    var logPath: String
    var manifestPath: String
    var provenancePath: String?
    var logSHA256: String
    var structure: TrackpadEventStructureAnalysis
    var manifest: TrackpadEventManifestAnalysis
    var hostReconstruction: TrackpadDriverEventHostAnalysis
    var provenance: TrackpadEventProvenanceSection

    init(
        logPath: String,
        manifestPath: String,
        provenancePath: String?,
        logSHA256: String,
        structure: TrackpadEventStructureAnalysis,
        manifest: TrackpadEventManifestAnalysis,
        hostReconstruction: TrackpadDriverEventHostAnalysis,
        provenance: TrackpadEventProvenanceSection
    ) {
        passed = structure.passed
            && manifest.passed
            && hostReconstruction.passed
            && provenance.passed
        self.logPath = logPath
        self.manifestPath = manifestPath
        self.provenancePath = provenancePath
        self.logSHA256 = logSHA256
        self.structure = structure
        self.manifest = manifest
        self.hostReconstruction = hostReconstruction
        self.provenance = provenance
    }
}

private enum TrackpadEventLogAnalysisCommandError: LocalizedError {
    case duplicateOption(String)
    case unknownOption(String)
    case unexpectedArgument(String)
    case missingLogPath
    case missingManifestPath
    case fileReadFailed(role: String, path: String, details: String)

    var errorDescription: String? {
        switch self {
        case let .duplicateOption(option):
            return "同じオプションを複数回指定できません: \(option)"
        case let .unknownOption(option):
            return "analyze-trackpad-event-logで未対応のオプションです: \(option)"
        case let .unexpectedArgument(argument):
            return "余分な引数があります: \(argument)"
        case .missingLogPath:
            return "解析するtrackpad event JSON Lines pathがありません。"
        case .missingManifestPath:
            return "--manifest <path>が必要です。"
        case let .fileReadFailed(role, path, details):
            return "\(role)を読めませんでした。path=\(path) details=\(details)"
        }
    }
}

private struct TrackpadEventLogAnalysisFailure: LocalizedError {
    var errorDescription: String? {
        "trackpad event logが厳格解析contractを満たしていません。上のreportを確認してください。"
    }
}
