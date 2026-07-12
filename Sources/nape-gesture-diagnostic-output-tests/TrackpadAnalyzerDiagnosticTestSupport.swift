import CoreGraphics
import Foundation
import NapeGestureCore
import NapeGestureDiagnosticOutput

enum TrackpadAnalyzerDiagnosticTestSupport {
    static func run() -> [String] {
        do {
            let fixture = try makeFixture()
            var failures: [String] = []

            let structure = TrackpadDriverEventAnalyzer.analyze(fixture.logData)
            if !structure.passed {
                failures.append("実CGEvent由来fixtureをstrict analyzerが受理しません。")
            }
            let negativeStructure = TrackpadDriverEventAnalyzer.analyze(fixture.negativeLogData)
            if negativeStructure.passed
                || !negativeStructure.issues.contains(where: {
                    $0.code == .rawFieldNumberOutOfRange
                })
            {
                failures.append("負のraw fieldを構造化失敗として拒否していません。")
            }

            let host = TrackpadDriverEventHostAnalyzer.analyze(records: [fixture.eventLog])
            if !host.passed || host.reconstructedEventCount != 1 {
                failures.append("実CGEvent由来fixtureをhostで再構築できません。")
            }
            if !host.rawFieldDifferences.contains(where: { $0.field == "sourceUserData" }) {
                failures.append("serializationで失われる生成marker差分をreportに保持していません。")
            }

            var subtypeUnavailable = fixture.eventLog
            subtypeUnavailable.eventSubtype = nil
            let nullableSubtypeHost = TrackpadDriverEventHostAnalyzer.analyze(
                records: [subtypeUnavailable]
            )
            if !nullableSubtypeHost.passed {
                failures.append("取得不能なeventSubtypeをhost再構築失敗にしています。")
            }

            var tampered = fixture.eventLog
            tampered.typeRaw = Int(CGEventType.keyDown.rawValue)
            let tamperedHost = TrackpadDriverEventHostAnalyzer.analyze(records: [tampered])
            if tamperedHost.passed || !tamperedHost.issues.contains(where: { $0.field == "typeRaw" }) {
                failures.append("serialized eventとrecordのtype改ざんをhost再構築が検出しません。")
            }

            do {
                try fixture.syntheticManifest.validate(logData: fixture.logData)
                try fixture.generatedManifest.validate(logData: fixture.logData)
            } catch {
                failures.append("正常fixtureのcapture manifest検証に失敗しました: \(error.localizedDescription)")
            }

            let validProvenance = TrackpadOutputProvenanceAnalyzer.analyze(
                records: [fixture.validProvenance],
                expectedLogSHA256: fixture.generatedManifest.logSHA256,
                expectedEvents: [fixture.eventLog]
            )
            if !validProvenance.passed {
                failures.append("正常なgeneratedProduct provenanceを拒否しています。")
            }

            let forbiddenProvenance = TrackpadOutputProvenanceAnalyzer.analyze(
                records: [fixture.pidProvenance],
                expectedLogSHA256: fixture.generatedManifest.logSHA256,
                expectedEvents: [fixture.eventLog]
            )
            if forbiddenProvenance.passed
                || !forbiddenProvenance.issues.contains(where: { $0.code == .forbiddenDelivery })
            {
                failures.append("PID配送provenanceを拒否していません。")
            }

            failures.append(
                contentsOf: validateContractFixture(
                    fixture.contractValid,
                    expectedContractPassed: true,
                    expectedIssue: nil,
                    label: "正常contract fixture"
                )
            )
            failures.append(
                contentsOf: validateContractFixture(
                    fixture.contractMissingMomentumTerminal,
                    expectedContractPassed: false,
                    expectedIssue: .missingMomentumTerminal,
                    label: "momentum terminal欠落contract fixture"
                )
            )
            failures.append(
                contentsOf: validateContractFixture(
                    fixture.contractUnconfirmedGesture,
                    expectedContractPassed: false,
                    expectedIssue: .unconfirmedGestureEvent,
                    label: "未確定type 29混入contract fixture"
                )
            )

            return failures
        } catch {
            return ["trackpad analyzer診断fixtureを生成できません: \(error.localizedDescription)"]
        }
    }

    static func writeFixtures(to directoryURL: URL) throws {
        let fixture = try makeFixture()
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        try fixture.logData.write(
            to: directoryURL.appendingPathComponent("host.jsonl"),
            options: .atomic
        )
        try fixture.logData.write(
            to: directoryURL.appendingPathComponent("generated.jsonl"),
            options: .atomic
        )
        try encodedLine(fixture.syntheticManifest).write(
            to: directoryURL.appendingPathComponent("host.manifest.json"),
            options: .atomic
        )
        try encodedLine(fixture.generatedManifest).write(
            to: directoryURL.appendingPathComponent("generated.manifest.json"),
            options: .atomic
        )
        try encodedLine(fixture.validProvenance).write(
            to: directoryURL.appendingPathComponent("generated.provenance.jsonl"),
            options: .atomic
        )
        try encodedLine(fixture.pidProvenance).write(
            to: directoryURL.appendingPathComponent("pid.provenance.jsonl"),
            options: .atomic
        )
        try fixture.negativeLogData.write(
            to: directoryURL.appendingPathComponent("negative-raw.jsonl"),
            options: .atomic
        )
        try encodedLine(fixture.negativeManifest).write(
            to: directoryURL.appendingPathComponent("negative-raw.manifest.json"),
            options: .atomic
        )
        try writeContractFixture(
            fixture.contractValid,
            prefix: "contract-valid",
            to: directoryURL
        )
        try writeContractFixture(
            fixture.contractMissingMomentumTerminal,
            prefix: "contract-missing-momentum-terminal",
            to: directoryURL
        )
        try writeContractFixture(
            fixture.contractUnconfirmedGesture,
            prefix: "contract-unconfirmed-gesture",
            to: directoryURL
        )
    }

    private static func makeFixture() throws -> Fixture {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: -24,
            wheel2: 12,
            wheel3: 0
        ) else {
            throw FixtureError.eventCreationFailed("scroll")
        }
        event.timestamp = MonotonicEventClock.nowTimestampNanoseconds
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(
            .eventSourceUserData,
            value: NapeGestureGeneratedEventMarker.value
        )
        event.setIntegerValueField(rawEventField(39), value: 0)
        event.setIntegerValueField(rawEventField(40), value: 0)

        let metadata = TrackpadDriverEventLogMetadata(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            osBuild: "diagnostic-fixture",
            scenarioID: "ci-generated-scroll",
            deviceLabel: "synthetic-cgevent",
            repoHeadSHA: String(repeating: "a", count: 40),
            captureRunToken: "11111111-2222-3333-4444-555555555555"
        )
        let eventLog = try TrackpadDriverEventSnapshotFactory.makeRecord(
            event: event,
            captureIndex: 0,
            metadata: metadata
        )
        let logData = try encodedLine(eventLog)
        let summary = try TrackpadDriverEventCaptureManifest.summarize(logData: logData)
        let executableSHA = String(repeating: "b", count: 64)
        let completedAt = Date(timeIntervalSince1970: 1_752_220_800.125)
        let startedAt = completedAt.addingTimeInterval(-1)
        let syntheticManifest = TrackpadDriverEventCaptureManifest(
            evidenceKind: .synthetic,
            logSummary: summary,
            loggerExecutableSHA256: executableSHA,
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt
        )
        let generatedManifest = TrackpadDriverEventCaptureManifest(
            evidenceKind: .generatedProduct,
            logSummary: summary,
            loggerExecutableSHA256: executableSHA,
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt
        )
        var negativeEventLog = eventLog
        negativeEventLog.rawFields[0].fieldNumber = -1
        let negativeLogData = try encodedLine(negativeEventLog)
        let negativeSummary = try TrackpadDriverEventCaptureManifest.summarize(
            logData: negativeLogData
        )
        let negativeManifest = TrackpadDriverEventCaptureManifest(
            evidenceKind: .synthetic,
            logSummary: negativeSummary,
            loggerExecutableSHA256: executableSHA,
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt
        )
        let validProvenance = TrackpadOutputProvenanceRecord(
            logSHA256: summary.logSHA256,
            captureIndex: 0,
            sessionID: TrackpadOutputSessionID(rawValue: 1),
            family: .scroll,
            eventTimestamp: eventLog.timestamp,
            eventTypeRaw: eventLog.typeRaw,
            delivery: .systemWide,
            eventKind: .scroll,
            captureRunToken: "11111111-2222-3333-4444-555555555555",
            scenarioID: "ci-generated-scroll",
            repoHeadSHA: String(repeating: "a", count: 40),
            executableSHA256: executableSHA
        )
        let pidProvenance = TrackpadOutputProvenanceRecord(
            logSHA256: summary.logSHA256,
            captureIndex: 0,
            sessionID: TrackpadOutputSessionID(rawValue: 1),
            family: .scroll,
            eventTimestamp: eventLog.timestamp,
            eventTypeRaw: eventLog.typeRaw,
            delivery: .targetPID,
            eventKind: .scroll,
            captureRunToken: "11111111-2222-3333-4444-555555555555",
            scenarioID: "ci-generated-scroll",
            repoHeadSHA: String(repeating: "a", count: 40),
            executableSHA256: executableSHA,
            destinationPID: 123
        )
        let contractValid = try makeContractFixture()
        let contractMissingMomentumTerminal = try makeContractFixture(
            droppingMomentumTerminal: true
        )
        let contractUnconfirmedGesture = try makeContractFixture(
            injectingUnconfirmedGesture: true
        )

        return Fixture(
            eventLog: eventLog,
            logData: logData,
            syntheticManifest: syntheticManifest,
            generatedManifest: generatedManifest,
            validProvenance: validProvenance,
            pidProvenance: pidProvenance,
            negativeLogData: negativeLogData,
            negativeManifest: negativeManifest,
            contractValid: contractValid,
            contractMissingMomentumTerminal: contractMissingMomentumTerminal,
            contractUnconfirmedGesture: contractUnconfirmedGesture
        )
    }

    private static func makeContractFixture(
        droppingMomentumTerminal: Bool = false,
        injectingUnconfirmedGesture: Bool = false
    ) throws -> ContractFixture {
        let metadata = TrackpadDriverEventLogMetadata(
            osVersion: "26.5.1",
            osBuild: "25F80",
            scenarioID: "pure-trackpad-vertical-scroll",
            deviceLabel: "generated-contract-fixture",
            repoHeadSHA: String(repeating: "a", count: 40),
            captureRunToken: "66666666-7777-4888-8999-aaaaaaaaaaaa"
        )
        let timestampBase: UInt64 = 1_000_000_000
        let events = try [
            makeScrollEvent(
                timestamp: timestampBase + 100,
                scrollPhase: 1,
                momentumPhase: 0,
                deltaY: -1
            ),
            makeCompanionEvent(
                timestamp: timestampBase + 99,
                classifier: 0,
                phase: 0,
                yMotion: 0
            ),
            makeCompanionEvent(
                timestamp: timestampBase + 99,
                classifier: 6,
                phase: 1,
                yMotion: -1
            ),
            makeScrollEvent(
                timestamp: timestampBase + 110,
                scrollPhase: 2,
                momentumPhase: 0,
                deltaY: -2
            ),
            makeCompanionEvent(
                timestamp: timestampBase + 109,
                classifier: injectingUnconfirmedGesture ? 7 : 0,
                phase: 0,
                yMotion: 0
            ),
            makeCompanionEvent(
                timestamp: timestampBase + 109,
                classifier: 6,
                phase: 2,
                yMotion: -2
            ),
            makeScrollEvent(
                timestamp: timestampBase + 120,
                scrollPhase: 4,
                momentumPhase: 0,
                deltaY: 0
            ),
            makeCompanionEvent(
                timestamp: timestampBase + 119,
                classifier: 0,
                phase: 0,
                yMotion: 0
            ),
            makeCompanionEvent(
                timestamp: timestampBase + 119,
                classifier: 6,
                phase: 4,
                yMotion: 0
            ),
            makeScrollEvent(
                timestamp: timestampBase + 130,
                scrollPhase: 0,
                momentumPhase: 1,
                deltaY: -3
            ),
            makeScrollEvent(
                timestamp: timestampBase + 140,
                scrollPhase: 0,
                momentumPhase: 2,
                deltaY: -2
            ),
            makeScrollEvent(
                timestamp: timestampBase + 150,
                scrollPhase: 0,
                momentumPhase: 3,
                deltaY: 0
            )
        ]
        let selectedEvents = droppingMomentumTerminal ? Array(events.dropLast()) : events
        let records = try selectedEvents.enumerated().map { index, event in
            try TrackpadDriverEventSnapshotFactory.makeRecord(
                event: event,
                captureIndex: UInt64(index),
                metadata: metadata
            )
        }
        let logData = try encodedLines(records)
        let summary = try TrackpadDriverEventCaptureManifest.summarize(logData: logData)
        let completedAt = Date(timeIntervalSince1970: 1_752_220_800.125)
        let manifest = TrackpadDriverEventCaptureManifest(
            evidenceKind: .generatedProduct,
            logSummary: summary,
            loggerExecutableSHA256: String(repeating: "c", count: 64),
            captureStartedAt: completedAt.addingTimeInterval(-1),
            captureCompletedAt: completedAt
        )
        let provenance = records.map { record in
            let eventKind: TrackpadOutputProvenanceEventKind = record.typeRaw
                == Int(CGEventType.scrollWheel.rawValue) ? .scroll : .gesture
            return TrackpadOutputProvenanceRecord(
                logSHA256: summary.logSHA256,
                captureIndex: record.captureIndex ?? UInt64.max,
                sessionID: TrackpadOutputSessionID(rawValue: 2),
                family: .scroll,
                eventTimestamp: record.timestamp,
                eventTypeRaw: record.typeRaw,
                delivery: .systemWide,
                eventKind: eventKind,
                captureRunToken: "66666666-7777-4888-8999-aaaaaaaaaaaa",
                scenarioID: "pure-trackpad-vertical-scroll",
                repoHeadSHA: String(repeating: "a", count: 40),
                executableSHA256: String(repeating: "c", count: 64)
            )
        }
        return ContractFixture(
            records: records,
            logData: logData,
            manifest: manifest,
            provenance: provenance
        )
    }

    private static func makeScrollEvent(
        timestamp: UInt64,
        scrollPhase: Int64,
        momentumPhase: Int64,
        deltaY: Int32
    ) throws -> CGEvent {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else {
            throw FixtureError.eventCreationFailed("scroll")
        }
        configureCommonFields(
            event,
            typeRaw: Int(CGEventType.scrollWheel.rawValue),
            timestamp: timestamp
        )
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.setIntegerValueField(rawEventField(110), value: 0)
        event.setIntegerValueField(rawEventField(124), value: 0)
        event.setIntegerValueField(rawEventField(132), value: 0)
        event.setIntegerValueField(rawEventField(135), value: 0)
        return event
    }

    private static func makeCompanionEvent(
        timestamp: UInt64,
        classifier: Int64,
        phase: Int64,
        yMotion: Float
    ) throws -> CGEvent {
        guard let event = CGEvent(source: nil),
              let gestureType = CGEventType(rawValue: 29)
        else {
            throw FixtureError.eventCreationFailed("type 29 companion")
        }
        event.type = gestureType
        configureCommonFields(event, typeRaw: 29, timestamp: timestamp)
        event.setIntegerValueField(rawEventField(88), value: 0)
        event.setIntegerValueField(rawEventField(99), value: 0)
        event.setIntegerValueField(rawEventField(110), value: classifier)
        event.setIntegerValueField(rawEventField(124), value: 0)
        event.setIntegerValueField(rawEventField(132), value: phase)
        event.setIntegerValueField(rawEventField(135), value: classifier == 6 ? 1 : 0)
        setMotionAliases(event, xMotion: 0, yMotion: yMotion)
        return event
    }

    private static func configureCommonFields(
        _ event: CGEvent,
        typeRaw: Int,
        timestamp: UInt64
    ) {
        event.timestamp = timestamp
        event.setIntegerValueField(rawEventField(39), value: 0)
        event.setIntegerValueField(rawEventField(40), value: 0)
        event.setIntegerValueField(
            .eventSourceUserData,
            value: NapeGestureGeneratedEventMarker.value
        )
        event.setIntegerValueField(rawEventField(55), value: Int64(typeRaw))
        event.setIntegerValueField(rawEventField(58), value: Int64(timestamp))
    }

    private static func setMotionAliases(
        _ event: CGEvent,
        xMotion: Float,
        yMotion: Float
    ) {
        for field in [113, 114, 116, 118] {
            event.setDoubleValueField(rawEventField(UInt32(field)), value: Double(xMotion))
        }
        for field in [115, 117, 164] {
            event.setIntegerValueField(
                rawEventField(UInt32(field)),
                value: Int64(UInt64(xMotion.bitPattern))
            )
        }
        for field in [119, 139] {
            event.setDoubleValueField(rawEventField(UInt32(field)), value: Double(yMotion))
        }
        for field in [123, 165] {
            event.setIntegerValueField(
                rawEventField(UInt32(field)),
                value: Int64(UInt64(yMotion.bitPattern))
            )
        }
    }

    private static func validateContractFixture(
        _ fixture: ContractFixture,
        expectedContractPassed: Bool,
        expectedIssue: TrackpadScrollMomentumContractIssueCode?,
        label: String
    ) -> [String] {
        var failures: [String] = []
        if !fixture.records.allSatisfy({
            $0.sourceUserData == NapeGestureGeneratedEventMarker.value
        }) {
            failures.append("\(label)の全eventにgenerated markerがありません。")
        }
        if !fixture.provenance.allSatisfy({ $0.delivery == .systemWide }) {
            failures.append("\(label)の全provenanceがsystemWideではありません。")
        }
        let eventKindsMatch = zip(fixture.records, fixture.provenance).allSatisfy {
            event, provenance in
            switch event.typeRaw {
            case Int(CGEventType.scrollWheel.rawValue):
                provenance.family == .scroll && provenance.eventKind == .scroll
            case 29:
                provenance.family == .scroll && provenance.eventKind == .gesture
            default:
                false
            }
        }
        if fixture.records.count != fixture.provenance.count || !eventKindsMatch {
            failures.append("\(label)のtype別scroll / gesture provenanceが一致しません。")
        }
        let structure = TrackpadDriverEventAnalyzer.analyze(fixture.logData)
        if !structure.passed {
            failures.append("\(label)をstrict analyzerが受理しません。")
        }
        let host = TrackpadDriverEventHostAnalyzer.analyze(records: fixture.records)
        if !host.passed || host.reconstructedEventCount != fixture.records.count {
            failures.append("\(label)をhostで全件再構築できません。")
        }
        do {
            try fixture.manifest.validate(logData: fixture.logData)
        } catch {
            failures.append("\(label)のmanifest検証に失敗しました: \(error.localizedDescription)")
        }
        let provenance = TrackpadOutputProvenanceAnalyzer.analyze(
            records: fixture.provenance,
            expectedLogSHA256: fixture.manifest.logSHA256,
            expectedEvents: fixture.records
        )
        if !provenance.passed {
            let codes = provenance.issues.map(\.code.rawValue).joined(separator: ",")
            failures.append("\(label)のsystemWide provenance検証に失敗しました: \(codes)")
        }

        do {
            let contractData = try Data(contentsOf: scrollMomentumContractURL())
            let readReport = TrackpadScrollMomentumContractDocumentReader.read(data: contractData)
            guard readReport.passed, let contract = readReport.document else {
                failures.append("登録済み25F80 contract fixtureを読めません。")
                return failures
            }
            let comparison = TrackpadScrollMomentumContractAnalyzer.analyze(
                documents: structure.documents,
                manifest: fixture.manifest,
                contract: contract
            )
            if comparison.passed != expectedContractPassed {
                failures.append("\(label)のcontract合否が期待値と一致しません。")
            }
            if let expectedIssue,
               !comparison.issues.contains(where: { $0.code == expectedIssue })
            {
                failures.append("\(label)に\(expectedIssue.rawValue)がありません。")
            }
        } catch {
            failures.append("25F80 contract fixtureを検証できません: \(error.localizedDescription)")
        }
        return failures
    }

    private static func writeContractFixture(
        _ fixture: ContractFixture,
        prefix: String,
        to directoryURL: URL
    ) throws {
        try fixture.logData.write(
            to: directoryURL.appendingPathComponent("\(prefix).jsonl"),
            options: .atomic
        )
        try encodedLine(fixture.manifest).write(
            to: directoryURL.appendingPathComponent("\(prefix).manifest.json"),
            options: .atomic
        )
        try encodedLines(fixture.provenance).write(
            to: directoryURL.appendingPathComponent("\(prefix).provenance.jsonl"),
            options: .atomic
        )
    }

    private static func scrollMomentumContractURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json"
            )
    }

    private static func encodedLine<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private static func encodedLines<Value: Encodable>(_ values: [Value]) throws -> Data {
        var data = Data()
        for value in values {
            data.append(try encodedLine(value))
        }
        return data
    }

    private static func rawEventField(_ number: UInt32) -> CGEventField {
        unsafeBitCast(number, to: CGEventField.self)
    }

    private struct Fixture {
        var eventLog: TrackpadDriverEventLog
        var logData: Data
        var syntheticManifest: TrackpadDriverEventCaptureManifest
        var generatedManifest: TrackpadDriverEventCaptureManifest
        var validProvenance: TrackpadOutputProvenanceRecord
        var pidProvenance: TrackpadOutputProvenanceRecord
        var negativeLogData: Data
        var negativeManifest: TrackpadDriverEventCaptureManifest
        var contractValid: ContractFixture
        var contractMissingMomentumTerminal: ContractFixture
        var contractUnconfirmedGesture: ContractFixture
    }

    private struct ContractFixture {
        var records: [TrackpadDriverEventLog]
        var logData: Data
        var manifest: TrackpadDriverEventCaptureManifest
        var provenance: [TrackpadOutputProvenanceRecord]
    }

    private enum FixtureError: LocalizedError {
        case eventCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case let .eventCreationFailed(kind):
                "\(kind) CGEventを作成できません。"
            }
        }
    }
}
