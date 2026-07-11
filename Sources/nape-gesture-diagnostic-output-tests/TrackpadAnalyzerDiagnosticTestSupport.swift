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
            throw FixtureError.eventCreationFailed
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
            repoHeadSHA: String(repeating: "a", count: 40)
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
            eventKind: .scroll
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
            destinationPID: 123
        )

        return Fixture(
            eventLog: eventLog,
            logData: logData,
            syntheticManifest: syntheticManifest,
            generatedManifest: generatedManifest,
            validProvenance: validProvenance,
            pidProvenance: pidProvenance,
            negativeLogData: negativeLogData,
            negativeManifest: negativeManifest
        )
    }

    private static func encodedLine<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
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
    }

    private enum FixtureError: LocalizedError {
        case eventCreationFailed

        var errorDescription: String? {
            "scroll CGEventを作成できません。"
        }
    }
}
