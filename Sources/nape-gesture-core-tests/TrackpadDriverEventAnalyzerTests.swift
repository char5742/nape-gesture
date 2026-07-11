import Foundation
import NapeGestureCore

private func makeAnalyzerEventObject(
    captureIndex: UInt64 = 0,
    timestamp: UInt64 = 100
) -> [String: Any] {
    let rawFields = (TrackpadDriverEventLog.rawFieldScanLowerBound...TrackpadDriverEventLog.maximumRawFieldNumber)
        .map { fieldNumber in
            let doubleValue = Double(fieldNumber)
            return TrackpadDriverRawField(
                fieldNumber: fieldNumber,
                integerValue: Int64(fieldNumber),
                doubleValue: doubleValue,
                doubleBitPattern: doubleValue.bitPattern
            )
        }
    let event = TrackpadDriverEventLog(
        metadata: TrackpadDriverEventLogMetadata(
            osVersion: "26.0.0",
            osBuild: "25A123",
            scenarioID: "strict-analyzer",
            deviceLabel: "純正トラックパッド",
            repoHeadSHA: String(repeating: "a", count: 40)
        ),
        captureIndex: captureIndex,
        timestamp: timestamp,
        typeRaw: 0,
        typeName: "observedType",
        eventSubtype: 0,
        flags: UInt64.max,
        scrollDeltaX: 0,
        scrollDeltaY: 0,
        scrollDeltaZ: 0,
        scrollFixedDeltaX: 0,
        scrollFixedDeltaY: 0,
        scrollFixedDeltaZ: 0,
        scrollPointDeltaX: 0,
        scrollPointDeltaY: 0,
        scrollPointDeltaZ: 0,
        scrollPhase: 0,
        momentumPhase: 0,
        isContinuous: 0,
        sourceUserData: 0,
        rawFields: rawFields,
        serializedEventBase64: Data([0x01, 0x02, 0x03]).base64EncodedString()
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let encoded = try? encoder.encode(event),
          let object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    else {
        preconditionFailure("analyzer test fixtureを生成できません。")
    }
    return object
}

private func analyzerJSONLines(_ objects: [[String: Any]]) -> Data {
    var result = Data()
    for object in objects {
        guard let line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            preconditionFailure("analyzer test JSON lineを生成できません。")
        }
        result.append(line)
        result.append(0x0A)
    }
    return result
}

private func analyzerReport(_ objects: [[String: Any]]) -> TrackpadDriverEventAnalyzerReport {
    TrackpadDriverEventAnalyzer.analyze(analyzerJSONLines(objects))
}

private func analyzerHasIssue(
    _ report: TrackpadDriverEventAnalyzerReport,
    _ code: TrackpadDriverEventAnalyzerIssueCode
) -> Bool {
    report.issues.contains { $0.code == code }
}

private func testTrackpadAnalyzerAcceptsStrictCurrentSchema() {
    let report = analyzerReport([makeAnalyzerEventObject()])

    expect(report.passed, "strict current schemaのevent logを受理する")
    expect(report.documents.count == 1, "valid lineをtyped documentとして保持する")
    expect(report.documents.first?.eventLog.captureIndex == 0, "typed TrackpadDriverEventLogを保持する")
    expect(report.documents.first?.rawLineData.isEmpty == false, "元raw line Dataを保持する")
}

private func testTrackpadAnalyzerRejectsFileBoundaryViolations() {
    let emptyReport = TrackpadDriverEventAnalyzer.analyze(Data())
    expect(analyzerHasIssue(emptyReport, .emptyFile), "空fileを構造化issueにする")

    let invalidUTF8 = TrackpadDriverEventAnalyzer.analyze(Data([0x7B, 0xFF, 0x7D, 0x0A]))
    expect(analyzerHasIssue(invalidUTF8, .invalidUTF8), "不正UTF-8を構造化issueにする")
    expect(invalidUTF8.issues.first(where: { $0.code == .invalidUTF8 })?.line == 1, "UTF-8 issueにlineを持たせる")

    var missingFinalLF = analyzerJSONLines([makeAnalyzerEventObject()])
    missingFinalLF.removeLast()
    let missingFinalLFReport = TrackpadDriverEventAnalyzer.analyze(missingFinalLF)
    expect(analyzerHasIssue(missingFinalLFReport, .missingFinalLineFeed), "最終LF欠落を失敗にする")

    var emptyLine = analyzerJSONLines([makeAnalyzerEventObject()])
    emptyLine.append(0x0A)
    let emptyLineReport = TrackpadDriverEventAnalyzer.analyze(emptyLine)
    expect(analyzerHasIssue(emptyLineReport, .emptyLine), "空行を失敗にする")

    let nonObjectReport = TrackpadDriverEventAnalyzer.analyze(Data("[]\n".utf8))
    expect(analyzerHasIssue(nonObjectReport, .oneObjectPerLineViolation), "top-level arrayを1行1object違反にする")

    let multipleObjects = TrackpadDriverEventAnalyzer.analyze(Data("{} {}\n".utf8))
    expect(analyzerHasIssue(multipleObjects, .oneObjectPerLineViolation), "1行の複数objectを失敗にする")
}

private func testTrackpadAnalyzerRejectsMalformedAndTruncatedJSON() {
    let malformed = TrackpadDriverEventAnalyzer.analyze(Data("{\"schemaVersion\":2,}\n".utf8))
    expect(analyzerHasIssue(malformed, .malformedJSON), "malformed JSONを構造化issueにする")

    let truncated = TrackpadDriverEventAnalyzer.analyze(Data("{\"schemaVersion\":2\n".utf8))
    expect(analyzerHasIssue(truncated, .truncatedJSON), "truncated JSONを構造化issueにする")
}

private func testTrackpadAnalyzerRejectsExcessiveNestingWithoutCrashing() {
    let allowedDepth = 128
    let allowed = String(repeating: "[", count: allowedDepth)
        + "null"
        + String(repeating: "]", count: allowedDepth)
        + "\n"
    let allowedReport = TrackpadDriverEventAnalyzer.analyze(Data(allowed.utf8))
    expect(
        !analyzerHasIssue(allowedReport, .nestingTooDeep),
        "nesting上限ちょうどのJSONを上限超過にしない"
    )

    let depth = 130
    let nested = String(repeating: "[", count: depth)
        + "null"
        + String(repeating: "]", count: depth)
        + "\n"
    let report = TrackpadDriverEventAnalyzer.analyze(Data(nested.utf8))

    expect(analyzerHasIssue(report, .nestingTooDeep), "nesting上限超過を構造化issueにする")
    expect(!report.passed, "深すぎるJSONを成功扱いしない")
}

private func testTrackpadAnalyzerAcceptsUnavailableEventSubtype() {
    var omitted = makeAnalyzerEventObject()
    omitted.removeValue(forKey: "eventSubtype")
    expect(analyzerReport([omitted]).passed, "取得不能で省略されたeventSubtypeを受理する")

    var nullValue = makeAnalyzerEventObject()
    nullValue["eventSubtype"] = NSNull()
    expect(analyzerReport([nullValue]).passed, "nullのeventSubtypeを受理する")

    var invalid = makeAnalyzerEventObject()
    invalid["eventSubtype"] = "0"
    expect(
        analyzerHasIssue(analyzerReport([invalid]), .invalidFieldType),
        "eventSubtypeの文字列型を拒否する"
    )
}

private func testTrackpadAnalyzerUsesRawRequiredKeys() {
    var object = makeAnalyzerEventObject()
    object.removeValue(forKey: "typeName")
    let report = analyzerReport([object])

    expect(analyzerHasIssue(report, .missingRequiredKey), "legacy decoderがnil補完する必須key欠落を失敗にする")
    expect(
        report.issues.contains { $0.message.contains("typeName") },
        "必須key issueに欠落key名を含める"
    )
}

private func testTrackpadAnalyzerRejectsReorderedEventsAndRawFields() {
    let eventReport = analyzerReport([
        makeAnalyzerEventObject(captureIndex: 1, timestamp: 101),
        makeAnalyzerEventObject(captureIndex: 0, timestamp: 100)
    ])
    expect(analyzerHasIssue(eventReport, .captureIndexMismatch), "reordered captureIndexを失敗にする")
    expect(analyzerHasIssue(eventReport, .timestampOutOfOrder), "減少timestampを失敗にする")

    var object = makeAnalyzerEventObject()
    guard var rawFields = object["rawFields"] as? [[String: Any]] else {
        preconditionFailure("rawFields fixtureがarrayではありません。")
    }
    rawFields.swapAt(0, 1)
    object["rawFields"] = rawFields
    let rawFieldReport = analyzerReport([object])

    expect(analyzerHasIssue(rawFieldReport, .rawFieldOrderMismatch), "reordered rawFieldsを失敗にする")
    let retainedFields = rawFieldReport.documents.first?.rawFields ?? []
    expect(retainedFields.first?.objectValue?["fieldNumber"]?.int64Value == 1, "元rawFields配列順を保持する")
    expect(retainedFields.dropFirst().first?.objectValue?["fieldNumber"]?.int64Value == 0, "rawFieldsをsortせず保持する")
    expect(rawFieldReport.documents.first?.eventLog.rawFields.first?.fieldNumber == 0, "typed logとは別にraw順を保持する")
}

private func testTrackpadAnalyzerRejectsMetadataMismatch() {
    let first = makeAnalyzerEventObject(captureIndex: 0, timestamp: 100)
    var second = makeAnalyzerEventObject(captureIndex: 1, timestamp: 101)
    guard var metadata = second["metadata"] as? [String: Any] else {
        preconditionFailure("metadata fixtureがobjectではありません。")
    }
    metadata["osBuild"] = "25A124"
    second["metadata"] = metadata

    let report = analyzerReport([first, second])
    expect(analyzerHasIssue(report, .metadataMismatch), "全行metadata不一致を失敗にする")
    expect(report.issues.first(where: { $0.code == .metadataMismatch })?.captureIndex == 1, "metadata issueにcaptureIndexを持たせる")
}

private func testTrackpadAnalyzerRejectsMissingAndDuplicateRawFields() {
    var missingObject = makeAnalyzerEventObject()
    guard var missingFields = missingObject["rawFields"] as? [[String: Any]] else {
        preconditionFailure("rawFields fixtureがarrayではありません。")
    }
    missingFields.remove(at: 10)
    missingObject["rawFields"] = missingFields
    let missingReport = analyzerReport([missingObject])
    expect(analyzerHasIssue(missingReport, .rawFieldCountMismatch), "raw field件数不足を失敗にする")
    expect(analyzerHasIssue(missingReport, .rawFieldMissing), "raw field欠落番号を失敗にする")

    var duplicateObject = makeAnalyzerEventObject()
    guard var duplicateFields = duplicateObject["rawFields"] as? [[String: Any]] else {
        preconditionFailure("rawFields fixtureがarrayではありません。")
    }
    duplicateFields[1] = duplicateFields[0]
    duplicateObject["rawFields"] = duplicateFields
    let duplicateReport = analyzerReport([duplicateObject])
    expect(analyzerHasIssue(duplicateReport, .rawFieldDuplicate), "raw field番号重複を失敗にする")
    expect(analyzerHasIssue(duplicateReport, .rawFieldMissing), "重複に伴うraw field欠落を失敗にする")
}

private func testTrackpadAnalyzerRejectsRawFieldTypeAndBitPatternMismatch() {
    var typeObject = makeAnalyzerEventObject()
    guard var typeFields = typeObject["rawFields"] as? [[String: Any]] else {
        preconditionFailure("rawFields fixtureがarrayではありません。")
    }
    typeFields[0]["integerValue"] = "0"
    typeObject["rawFields"] = typeFields
    let typeReport = analyzerReport([typeObject])
    expect(analyzerHasIssue(typeReport, .invalidFieldType), "raw field値型違いを失敗にする")

    var bitPatternObject = makeAnalyzerEventObject()
    guard var bitPatternFields = bitPatternObject["rawFields"] as? [[String: Any]] else {
        preconditionFailure("rawFields fixtureがarrayではありません。")
    }
    bitPatternFields[1]["doubleBitPattern"] = NSNumber(value: Double(2).bitPattern)
    bitPatternObject["rawFields"] = bitPatternFields
    let bitPatternReport = analyzerReport([bitPatternObject])
    expect(analyzerHasIssue(bitPatternReport, .doubleBitPatternMismatch), "finite doubleとbit pattern不一致を失敗にする")
}

private func testTrackpadAnalyzerRejectsBrokenBase64() {
    var object = makeAnalyzerEventObject()
    object["serializedEventBase64"] = "AQI"
    let report = analyzerReport([object])

    expect(analyzerHasIssue(report, .invalidBase64), "padding欠落を含む非canonical Base64を失敗にする")
}

private func testTrackpadAnalyzerPreservesUnknownFieldsAndWideIntegers() {
    var object = makeAnalyzerEventObject()
    object["futureTopLevel"] = [
        "wideUnsigned": NSNumber(value: UInt64.max),
        "sequence": [3, 2, 1]
    ]
    guard var metadata = object["metadata"] as? [String: Any] else {
        preconditionFailure("metadata fixtureがobjectではありません。")
    }
    metadata["futureMetadata"] = ["enabled": true]
    object["metadata"] = metadata

    let report = analyzerReport([object])
    let document = report.documents.first
    let wideUnsigned = document?
        .unknownTopLevelFields["futureTopLevel"]?
        .objectValue?["wideUnsigned"]

    expect(report.passed, "unknown fieldを拒否しない")
    expect(wideUnsigned == .unsignedInteger(UInt64.max), "UInt64をDoubleへ丸めず保持する")
    expect(document?.unknownMetadataFields.contains("futureMetadata") == true, "unknown metadata fieldを保持する")
    expect(document?.rawTopLevelObject.contains("futureTopLevel") == true, "unknown top-level fieldをraw documentにも保持する")
}

private func testTrackpadAnalyzerReportIsCodableAndEquatable() {
    let report = analyzerReport([makeAnalyzerEventObject()])
    let encoded = try? JSONEncoder().encode(report)
    let decoded = encoded.flatMap { try? JSONDecoder().decode(TrackpadDriverEventAnalyzerReport.self, from: $0) }

    expect(encoded != nil, "analyzer reportをCodableでencodeできる")
    expect(decoded == report, "analyzer reportをlosslessにCodable round-tripできる")
}

public func runTrackpadDriverEventAnalyzerTests() {
    testTrackpadAnalyzerAcceptsStrictCurrentSchema()
    testTrackpadAnalyzerRejectsFileBoundaryViolations()
    testTrackpadAnalyzerRejectsMalformedAndTruncatedJSON()
    testTrackpadAnalyzerRejectsExcessiveNestingWithoutCrashing()
    testTrackpadAnalyzerAcceptsUnavailableEventSubtype()
    testTrackpadAnalyzerUsesRawRequiredKeys()
    testTrackpadAnalyzerRejectsReorderedEventsAndRawFields()
    testTrackpadAnalyzerRejectsMetadataMismatch()
    testTrackpadAnalyzerRejectsMissingAndDuplicateRawFields()
    testTrackpadAnalyzerRejectsRawFieldTypeAndBitPatternMismatch()
    testTrackpadAnalyzerRejectsBrokenBase64()
    testTrackpadAnalyzerPreservesUnknownFieldsAndWideIntegers()
    testTrackpadAnalyzerReportIsCodableAndEquatable()
}
