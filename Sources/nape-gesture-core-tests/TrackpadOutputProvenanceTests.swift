import Foundation
import NapeGestureCore

func runTrackpadOutputProvenanceTests() {
    testTrackpadOutputProvenanceAcceptsSystemWideGestureRecords()
    testTrackpadOutputProvenanceRejectsForbiddenDeliveryAndEventKinds()
    testTrackpadOutputProvenanceRejectsTraceIdentityAndPrePostTargetMismatch()
    testTrackpadOutputProvenanceRejectsCaptureOrderHashAndFamilyMismatch()
    testTrackpadOutputProvenanceRejectsNoncanonicalLogSHA256()
    testTrackpadOutputProvenanceAcceptsTimestampRegression()
    testTrackpadOutputProvenanceRejectsCaptureLogMismatch()
    testTrackpadOutputProvenanceAcceptsActualScrollWithGeneratedMarker()
    testTrackpadOutputProvenanceAcceptsScrollFamilyCompanionGesture()
    testTrackpadOutputProvenanceRejectsActualKeyMasqueradingAsScroll()
    testTrackpadOutputProvenanceRejectsEveryKnownForbiddenActualType()
    testTrackpadOutputProvenanceAcceptsWindowServerResolvedTargetFields()
    testTrackpadOutputProvenanceRejectsMissingGeneratedMarker()
    testTrackpadOutputProvenanceKeepsPrivateGestureTypesUnclassified()
    testTrackpadOutputProvenanceDocumentReaderIsStrictAndPreservesUnknownFields()
    testTrackpadOutputProvenanceRoundTrips()
}

private func makeProvenanceRecord(
    captureIndex: UInt64,
    timestamp: UInt64,
    family: TrackpadOutputEventFamily = .scroll,
    eventKind: TrackpadOutputProvenanceEventKind = .scroll,
    delivery: TrackpadOutputDeliveryKind = .systemWide,
    logSHA256: String = String(repeating: "a", count: 64),
    destinationPID: Int32? = nil,
    accessibilityElementRole: String? = nil,
    keyboardKeyCode: Int? = nil,
    eventTypeRaw: Int? = 22
) -> TrackpadOutputProvenanceRecord {
    TrackpadOutputProvenanceRecord(
        logSHA256: logSHA256,
        captureIndex: captureIndex,
        sessionID: TrackpadOutputSessionID(rawValue: 1),
        family: family,
        eventTimestamp: timestamp,
        eventTypeRaw: eventTypeRaw,
        delivery: delivery,
        eventKind: eventKind,
        destinationPID: destinationPID,
        accessibilityElementRole: accessibilityElementRole,
        keyboardKeyCode: keyboardKeyCode
    )
}

private func makeActualEvent(
    captureIndex: UInt64 = 0,
    timestamp: UInt64 = 100,
    typeRaw: Int = 22,
    sourceUserData: Int64 = NapeGestureGeneratedEventMarker.value,
    rawFields: [TrackpadDriverRawField] = []
) -> TrackpadDriverEventLog {
    TrackpadDriverEventLog(
        captureIndex: captureIndex,
        timestamp: timestamp,
        typeRaw: typeRaw,
        typeName: "raw-\(typeRaw)",
        sourceUserData: sourceUserData,
        rawFields: rawFields
    )
}

private func makeRawField(number: Int, integerValue: Int64) -> TrackpadDriverRawField {
    let doubleValue = Double(integerValue)
    return TrackpadDriverRawField(
        fieldNumber: number,
        integerValue: integerValue,
        doubleValue: doubleValue,
        doubleBitPattern: doubleValue.bitPattern
    )
}

private func testTrackpadOutputProvenanceAcceptsSystemWideGestureRecords() {
    let sha = String(repeating: "a", count: 64)
    let records = [
        makeProvenanceRecord(captureIndex: 0, timestamp: 100, logSHA256: sha),
        makeProvenanceRecord(
            captureIndex: 1,
            timestamp: 100,
            family: .dockSwipe,
            eventKind: .gesture,
            logSHA256: sha
        )
    ]

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: records,
        expectedLogSHA256: sha,
        expectedEventCount: records.count
    )

    expect(analysis.passed, "system-wideのscroll / gesture provenanceを受理する")
    expect(analysis.issues.isEmpty, "正常provenanceにissueを追加しない")
}

private func testTrackpadOutputProvenanceRejectsForbiddenDeliveryAndEventKinds() {
    let sha = String(repeating: "b", count: 64)
    let records = [
        makeProvenanceRecord(
            captureIndex: 0,
            timestamp: 100,
            delivery: .targetPID,
            logSHA256: sha,
            destinationPID: 123
        ),
        makeProvenanceRecord(
            captureIndex: 1,
            timestamp: 101,
            eventKind: .key,
            delivery: .keyboardShortcut,
            logSHA256: sha,
            keyboardKeyCode: 124
        ),
        makeProvenanceRecord(
            captureIndex: 2,
            timestamp: 102,
            family: .navigationSwipe,
            eventKind: .gesture,
            delivery: .accessibility,
            logSHA256: sha,
            accessibilityElementRole: "AXScrollBar"
        )
    ]

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: records,
        expectedLogSHA256: sha,
        expectedEventCount: records.count
    )
    let codes = Set(analysis.issues.map(\.code))

    expect(!analysis.passed, "PID / Accessibility / shortcut provenanceを失敗にする")
    expect(codes.contains(.forbiddenDelivery), "system-wide以外の配送を検出する")
    expect(codes.contains(.forbiddenDeliveryMetadata), "禁止配送metadataを検出する")
    expect(codes.contains(.forbiddenEventKind), "generated key eventを検出する")
}

private func testTrackpadOutputProvenanceRejectsTraceIdentityAndPrePostTargetMismatch() {
    let sha = String(repeating: "8", count: 64)
    var first = makeProvenanceRecord(captureIndex: 0, timestamp: 100, logSHA256: sha)
    first.captureRunToken = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    first.scenarioID = "wrong-scenario"
    first.repoHeadSHA = String(repeating: "e", count: 40)
    first.executableSHA256 = String(repeating: "f", count: 64)
    first.prePostTargetUnixProcessID = 42

    var second = makeProvenanceRecord(captureIndex: 1, timestamp: 101, logSHA256: sha)
    second.traceSHA256 = String(repeating: "9", count: 64)
    second.sessionID = TrackpadOutputSessionID(rawValue: 2)

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [first, second],
        expectedLogSHA256: sha,
        expectedEvents: [
            makeActualEvent(captureIndex: 0, timestamp: 100),
            makeActualEvent(captureIndex: 1, timestamp: 101)
        ],
        expectedCaptureRunToken: "11111111-2222-3333-4444-555555555555",
        expectedScenarioID: "provenance-test",
        expectedRepoHeadSHA: String(repeating: "c", count: 40),
        expectedExecutableSHA256: String(repeating: "d", count: 64)
    )
    let codes = Set(analysis.issues.map(\.code))

    expect(codes.contains(.captureRunTokenMismatch), "manifestと異なるcapture run tokenを拒否する")
    expect(codes.contains(.scenarioIDMismatch), "manifestと異なるscenario IDを拒否する")
    expect(codes.contains(.repoHeadSHAMismatch), "manifestと異なるrepo HEAD SHAを拒否する")
    expect(codes.contains(.executableSHA256Mismatch), "manifestと異なるbinary SHAを拒否する")
    expect(codes.contains(.traceSHA256Mismatch), "record間で異なるtrace SHAを拒否する")
    expect(codes.contains(.sessionIDMismatch), "record間で異なるsession IDを拒否する")
    expect(codes.contains(.prePostTargetProcessPresent), "投稿前target process fieldの非0を拒否する")
}

private func testTrackpadOutputProvenanceRejectsCaptureOrderHashAndFamilyMismatch() {
    let expectedSHA = String(repeating: "c", count: 64)
    let records = [
        makeProvenanceRecord(
            captureIndex: 1,
            timestamp: 200,
            family: .dockSwipe,
            eventKind: .scroll,
            logSHA256: "invalid"
        ),
        makeProvenanceRecord(
            captureIndex: 1,
            timestamp: 200,
            logSHA256: String(repeating: "d", count: 64)
        )
    ]

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: records,
        expectedLogSHA256: expectedSHA,
        expectedEventCount: 3
    )
    let codes = Set(analysis.issues.map(\.code))

    expect(codes.contains(.eventCountMismatch), "manifest event countとの不一致を検出する")
    expect(codes.contains(.captureIndexMismatch), "captureIndex欠落・重複を検出する")
    expect(codes.contains(.invalidLogSHA256), "不正なrecord SHA-256を検出する")
    expect(codes.contains(.logSHA256Mismatch), "別logを参照するrecordを検出する")
    expect(codes.contains(.familyEventKindMismatch), "familyとevent kindの不一致を検出する")
}

private func testTrackpadOutputProvenanceRejectsNoncanonicalLogSHA256() {
    let lowercaseSHA = String(repeating: "a", count: 64)
    let uppercaseSHA = lowercaseSHA.uppercased()
    let record = makeProvenanceRecord(
        captureIndex: 0,
        timestamp: 100,
        logSHA256: uppercaseSHA
    )

    let recordAnalysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [record],
        expectedLogSHA256: lowercaseSHA,
        expectedEventCount: 1
    )
    expect(
        recordAnalysis.issues.map(\.code).contains(.invalidLogSHA256),
        "大文字を含むrecord log SHA-256をcanonical値として受理しない"
    )

    let expectedAnalysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [makeProvenanceRecord(captureIndex: 0, timestamp: 100)],
        expectedLogSHA256: uppercaseSHA,
        expectedEventCount: 1
    )
    expect(
        expectedAnalysis.issues.map(\.code).contains(.invalidExpectedLogSHA256),
        "大文字を含むexpected log SHA-256をcanonical値として受理しない"
    )
}

private func testTrackpadOutputProvenanceAcceptsTimestampRegression() {
    let sha = String(repeating: "a", count: 64)
    let records = [
        makeProvenanceRecord(captureIndex: 0, timestamp: 101, logSHA256: sha),
        makeProvenanceRecord(captureIndex: 1, timestamp: 100, logSHA256: sha)
    ]

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: records,
        expectedLogSHA256: sha,
        expectedEventCount: records.count
    )

    expect(
        analysis.passed,
        "provenance順をcaptureIndexで保持し、actual event timestampの局所逆行を許可する"
    )
}

private func testTrackpadOutputProvenanceRoundTrips() {
    let record = makeProvenanceRecord(captureIndex: 0, timestamp: 100)
    let encoded = try? JSONEncoder().encode(record)
    let decoded = encoded.flatMap {
        try? JSONDecoder().decode(TrackpadOutputProvenanceRecord.self, from: $0)
    }

    expect(decoded == record, "provenance recordをJSON round-tripする")
}

private func testTrackpadOutputProvenanceRejectsCaptureLogMismatch() {
    let sha = String(repeating: "e", count: 64)
    let records = [
        makeProvenanceRecord(captureIndex: 0, timestamp: 100, logSHA256: sha)
    ]
    let eventLogs = [
        makeActualEvent(
            captureIndex: 1,
            timestamp: 101,
            typeRaw: 29
        )
    ]

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: records,
        expectedLogSHA256: sha,
        expectedEvents: eventLogs
    )
    let codes = Set(analysis.issues.map(\.code))

    expect(codes.contains(.logCaptureIndexMismatch), "capture logとのcaptureIndex不一致を検出する")
    expect(codes.contains(.eventTimestampMismatch), "capture logとのtimestamp不一致を検出する")
    expect(codes.contains(.eventTypeMismatch), "capture logとのevent type不一致を検出する")
}

private func testTrackpadOutputProvenanceAcceptsActualScrollWithGeneratedMarker() {
    let sha = String(repeating: "f", count: 64)
    let record = makeProvenanceRecord(captureIndex: 0, timestamp: 100, logSHA256: sha)
    let event = makeActualEvent(
        rawFields: [
            makeRawField(number: 39, integerValue: 0),
            makeRawField(number: 40, integerValue: 0)
        ]
    )

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [record],
        expectedLogSHA256: sha,
        expectedEvents: [event]
    )

    expect(analysis.passed, "generated marker付きactual scrollを受理する")
    expect(analysis.issues.isEmpty, "valid actual scrollにissueを追加しない")
}

private func testTrackpadOutputProvenanceAcceptsScrollFamilyCompanionGesture() {
    let sha = String(repeating: "6", count: 64)
    let records = [
        makeProvenanceRecord(
            captureIndex: 0,
            timestamp: 100,
            family: .scroll,
            eventKind: .scroll,
            logSHA256: sha,
            eventTypeRaw: 22
        ),
        makeProvenanceRecord(
            captureIndex: 1,
            timestamp: 99,
            family: .scroll,
            eventKind: .gesture,
            logSHA256: sha,
            eventTypeRaw: 29
        )
    ]
    let targetProcessFields = [
        makeRawField(number: 39, integerValue: 0),
        makeRawField(number: 40, integerValue: 0)
    ]
    let events = [
        makeActualEvent(rawFields: targetProcessFields),
        makeActualEvent(
            captureIndex: 1,
            timestamp: 99,
            typeRaw: 29,
            rawFields: targetProcessFields
        )
    ]

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: records,
        expectedLogSHA256: sha,
        expectedEvents: events
    )

    expect(analysis.passed, "scroll familyでtype 22 scrollとtype 29 companion gestureを受理する")
    expect(analysis.issues.isEmpty, "正常なscroll companion provenanceにissueを追加しない")

    let wrongGestureRecord = makeProvenanceRecord(
        captureIndex: 0,
        timestamp: 100,
        family: .scroll,
        eventKind: .gesture,
        logSHA256: sha,
        eventTypeRaw: 30
    )
    let wrongGesture = makeActualEvent(
        typeRaw: 30,
        rawFields: targetProcessFields
    )
    let wrongAnalysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [wrongGestureRecord],
        expectedLogSHA256: sha,
        expectedEvents: [wrongGesture]
    )
    expect(
        wrongAnalysis.issues.contains(where: { $0.code == .actualEventKindMismatch }),
        "scroll familyのgestureをtype 29以外で偽装できない"
    )
}

private func testTrackpadOutputProvenanceRejectsActualKeyMasqueradingAsScroll() {
    let sha = String(repeating: "1", count: 64)
    let record = makeProvenanceRecord(
        captureIndex: 0,
        timestamp: 100,
        logSHA256: sha,
        eventTypeRaw: 10
    )
    let event = makeActualEvent(typeRaw: 10)

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [record],
        expectedLogSHA256: sha,
        expectedEvents: [event]
    )
    let codes = Set(analysis.issues.map(\.code))

    expect(codes.contains(.actualForbiddenEventKind), "scrollと偽装したactual key eventを拒否する")
    expect(codes.contains(.actualEventKindMismatch), "actual keyとscroll宣言の不一致を検出する")
    expect(!codes.contains(.eventTypeMismatch), "同じtypeRawを記載した偽装もactual種別から検出する")
}

private func testTrackpadOutputProvenanceRejectsEveryKnownForbiddenActualType() {
    let forbiddenTypes = [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 23, 24, 25, 26, 27]
    let sha = String(repeating: "2", count: 64)

    for typeRaw in forbiddenTypes {
        let record = makeProvenanceRecord(
            captureIndex: 0,
            timestamp: 100,
            logSHA256: sha,
            eventTypeRaw: typeRaw
        )
        let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
            records: [record],
            expectedLogSHA256: sha,
            expectedEvents: [makeActualEvent(typeRaw: typeRaw)]
        )

        expect(
            analysis.issues.contains { $0.code == .actualForbiddenEventKind },
            "known actual key / pointer / button / nullを拒否する typeRaw=\(typeRaw)"
        )
    }
}

private func testTrackpadOutputProvenanceAcceptsWindowServerResolvedTargetFields() {
    let sha = String(repeating: "3", count: 64)
    let records = [
        makeProvenanceRecord(captureIndex: 0, timestamp: 100, logSHA256: sha),
        makeProvenanceRecord(captureIndex: 1, timestamp: 101, logSHA256: sha)
    ]
    let events = [
        makeActualEvent(
            rawFields: [
                makeRawField(number: 39, integerValue: 4_174_843),
                makeRawField(number: 40, integerValue: 69_888)
            ]
        ),
        makeActualEvent(
            captureIndex: 1,
            timestamp: 101,
            rawFields: [
                makeRawField(number: 39, integerValue: 4_174_843),
                makeRawField(number: 40, integerValue: 69_888)
            ]
        )
    ]

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: records,
        expectedLogSHA256: sha,
        expectedEvents: events
    )
    expect(analysis.passed, "system-wide投稿後にWindowServerが付与した配送先fieldを受理する")
    expect(analysis.issues.isEmpty, "OS解決後の配送先fieldを明示的PID投稿と誤判定しない")
}

private func testTrackpadOutputProvenanceRejectsMissingGeneratedMarker() {
    let sha = String(repeating: "4", count: 64)
    let record = makeProvenanceRecord(captureIndex: 0, timestamp: 100, logSHA256: sha)
    let event = makeActualEvent(sourceUserData: 0)

    let analysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [record],
        expectedLogSHA256: sha,
        expectedEvents: [event]
    )

    expect(
        analysis.issues.contains { $0.code == .missingGeneratedMarker },
        "actual eventのgenerated marker欠落を拒否する"
    )
}

private func testTrackpadOutputProvenanceKeepsPrivateGestureTypesUnclassified() {
    let sha = String(repeating: "5", count: 64)
    let privateGestureRecord = makeProvenanceRecord(
        captureIndex: 0,
        timestamp: 100,
        family: .dockSwipe,
        eventKind: .gesture,
        logSHA256: sha,
        eventTypeRaw: 29
    )
    let privateGesture = makeActualEvent(typeRaw: 29)
    let privateAnalysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [privateGestureRecord],
        expectedLogSHA256: sha,
        expectedEvents: [privateGesture]
    )

    expect(privateAnalysis.passed, "未知/private actual typeをPhase 2までgesture未分類として受理する")

    let privateScrollRecord = makeProvenanceRecord(
        captureIndex: 0,
        timestamp: 100,
        logSHA256: sha,
        eventTypeRaw: 29
    )
    let privateScrollAnalysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [privateScrollRecord],
        expectedLogSHA256: sha,
        expectedEvents: [privateGesture]
    )

    expect(
        privateScrollAnalysis.issues.contains { $0.code == .actualEventKindMismatch },
        "scrollと偽装した未知/private actual typeを拒否する"
    )

    let scrollAsGestureRecord = makeProvenanceRecord(
        captureIndex: 0,
        timestamp: 100,
        family: .navigationSwipe,
        eventKind: .gesture,
        logSHA256: sha
    )
    let scrollAsGestureAnalysis = TrackpadOutputProvenanceAnalyzer.analyze(
        records: [scrollAsGestureRecord],
        expectedLogSHA256: sha,
        expectedEvents: [makeActualEvent()]
    )

    expect(
        scrollAsGestureAnalysis.issues.contains { $0.code == .actualEventKindMismatch },
        "gestureと偽装した既知actual scrollを拒否する"
    )
}

private func testTrackpadOutputProvenanceDocumentReaderIsStrictAndPreservesUnknownFields() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let record = makeProvenanceRecord(captureIndex: 0, timestamp: 100)
    guard var line = try? encoder.encode(record) else {
        expect(false, "provenance strict reader用recordをencodeできる")
        return
    }
    line.removeLast()
    line.append(contentsOf: Data(",\"futureField\":18446744073709551615}".utf8))
    line.append(0x0A)

    let documents = try? TrackpadOutputProvenanceDocumentReader.read(data: line)
    expect(documents?.count == 1, "厳格readerが正しいprovenance JSON Linesを読む")
    expect(
        documents?.first?.rawObject["futureField"] == .unsignedInteger(UInt64.max),
        "未知fieldとUInt64最大値をraw objectへ保持する"
    )

    var truncated = line
    truncated.removeLast()
    expectProvenanceReadThrows("LF終端のないprovenanceを拒否する") {
        _ = try TrackpadOutputProvenanceDocumentReader.read(data: truncated)
    }

    let duplicateKey = Data(
        "{\"schemaVersion\":1,\"schemaVersion\":1}\n".utf8
    )
    expectProvenanceReadThrows("重複keyのあるprovenanceを拒否する") {
        _ = try TrackpadOutputProvenanceDocumentReader.read(data: duplicateKey)
    }

    let blankLine = line + Data("\n".utf8)
    expectProvenanceReadThrows("空recordのあるprovenanceを拒否する") {
        _ = try TrackpadOutputProvenanceDocumentReader.read(data: blankLine)
    }
}

private func expectProvenanceReadThrows(
    _ message: String,
    operation: () throws -> Void
) {
    do {
        try operation()
        expect(false, message)
    } catch {
        expect(true, message)
    }
}
