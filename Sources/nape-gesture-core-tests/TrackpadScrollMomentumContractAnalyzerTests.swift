import Foundation
import NapeGestureCore

private func scrollMomentumContractFixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json")
}

private func physicalObservationContractFixtureURL() -> URL {
    scrollMomentumContractFixtureURL()
        .deletingLastPathComponent()
        .appendingPathComponent("physical-observations.json")
}

private func collectContractFixtureJSONKeys(
    _ value: Any,
    into keys: inout Set<String>
) {
    if let object = value as? [String: Any] {
        for (key, nested) in object {
            keys.insert(key.lowercased())
            collectContractFixtureJSONKeys(nested, into: &keys)
        }
    } else if let array = value as? [Any] {
        for nested in array {
            collectContractFixtureJSONKeys(nested, into: &keys)
        }
    }
}

private func readScrollMomentumContract() -> TrackpadScrollMomentumContractDocument? {
    do {
        let data = try Data(contentsOf: scrollMomentumContractFixtureURL())
        let report = TrackpadScrollMomentumContractDocumentReader.read(data: data)
        expect(report.passed, "登録済みscroll / momentum contract fixtureを読める")
        return report.document
    } catch {
        expect(false, "scroll / momentum contract fixtureを読める: \(error)")
        return nil
    }
}

private func contractRawFields(
    typeRaw: Int,
    timestamp: UInt64,
    scrollPhase: Int64 = 0,
    momentumPhase: Int64 = 0,
    classifier: Int64 = 0,
    companionPhase: Int64 = 0,
    xMotion: Float = 0,
    yMotion: Float = 0,
    continuous: Int64 = 0
) -> [TrackpadDriverRawField] {
    let xDouble = Double(xMotion)
    let yDouble = Double(yMotion)
    let xFloatBits = Int64(UInt64(xMotion.bitPattern))
    let yFloatBits = Int64(UInt64(yMotion.bitPattern))
    let xDoubleFields: Set<Int> = [113, 114, 116, 118]
    let xFloatFields: Set<Int> = [115, 117, 164]
    let yDoubleFields: Set<Int> = [119, 139]
    let yFloatFields: Set<Int> = [123, 165]

    return (0...TrackpadDriverEventLog.maximumRawFieldNumber).map { fieldNumber in
        var integerValue: Int64 = 0
        var doubleValue = Double(0)
        switch fieldNumber {
        case 55:
            integerValue = Int64(typeRaw)
            doubleValue = Double(typeRaw)
        case 58:
            integerValue = Int64(timestamp)
            doubleValue = Double(timestamp)
        case 88:
            integerValue = continuous
            doubleValue = Double(continuous)
        case 99:
            integerValue = scrollPhase
            doubleValue = Double(scrollPhase)
        case 110:
            integerValue = classifier
            doubleValue = Double(classifier)
        case 123:
            integerValue = typeRaw == 29 ? yFloatBits : momentumPhase
            doubleValue = Double(integerValue)
        case 124:
            integerValue = 0
        case 132:
            integerValue = companionPhase
            doubleValue = Double(companionPhase)
        case 135:
            integerValue = typeRaw == 29 && classifier == 6 ? 1 : 0
            doubleValue = Double(integerValue)
        default:
            if xDoubleFields.contains(fieldNumber) {
                doubleValue = xDouble
            } else if xFloatFields.contains(fieldNumber) {
                integerValue = xFloatBits
                doubleValue = Double(integerValue)
            } else if yDoubleFields.contains(fieldNumber) {
                doubleValue = yDouble
            } else if yFloatFields.contains(fieldNumber) {
                integerValue = yFloatBits
                doubleValue = Double(integerValue)
            }
        }
        return TrackpadDriverRawField(
            fieldNumber: fieldNumber,
            integerValue: integerValue,
            doubleValue: doubleValue,
            doubleBitPattern: doubleValue.bitPattern
        )
    }
}

private func makeContractEvent(
    captureIndex: UInt64,
    timestamp: UInt64,
    typeRaw: Int,
    scrollPhase: Int64 = 0,
    momentumPhase: Int64 = 0,
    classifier: Int64 = 0,
    companionPhase: Int64 = 0,
    xMotion: Float = 0,
    yMotion: Float = 0,
    deltaX: Double = 0,
    deltaY: Double = 0
) -> TrackpadDriverEventLog {
    let continuous: Int64 = typeRaw == 22 ? 1 : 0
    return TrackpadDriverEventLog(
        metadata: TrackpadDriverEventLogMetadata(
            osVersion: "26.5.1",
            osBuild: "25F80",
            scenarioID: "pure-trackpad-vertical-scroll",
            deviceLabel: "generated-contract-test",
            repoHeadSHA: String(repeating: "a", count: 40)
        ),
        captureIndex: captureIndex,
        timestamp: timestamp,
        typeRaw: typeRaw,
        typeName: typeRaw == 22 ? "scrollWheel" : "gesture",
        eventSubtype: 0,
        scrollDeltaX: Int64(deltaX),
        scrollDeltaY: Int64(deltaY),
        scrollDeltaZ: 0,
        scrollFixedDeltaX: deltaX,
        scrollFixedDeltaY: deltaY,
        scrollFixedDeltaZ: 0,
        scrollPointDeltaX: deltaX,
        scrollPointDeltaY: deltaY,
        scrollPointDeltaZ: 0,
        scrollPhase: scrollPhase,
        momentumPhase: typeRaw == 29 && classifier == 6
            ? Int64(UInt64(yMotion.bitPattern))
            : momentumPhase,
        isContinuous: continuous,
        sourceUserData: NapeGestureGeneratedEventMarker.value,
        rawFields: contractRawFields(
            typeRaw: typeRaw,
            timestamp: timestamp,
            scrollPhase: scrollPhase,
            momentumPhase: momentumPhase,
            classifier: classifier,
            companionPhase: companionPhase,
            xMotion: xMotion,
            yMotion: yMotion,
            continuous: continuous
        ),
        serializedEventBase64: "AA=="
    )
}

private func makeContractSequence() -> [TrackpadDriverEventLog] {
    [
        makeContractEvent(
            captureIndex: 0,
            timestamp: 100,
            typeRaw: 22,
            scrollPhase: 1,
            deltaY: -1
        ),
        makeContractEvent(captureIndex: 1, timestamp: 99, typeRaw: 29),
        makeContractEvent(
            captureIndex: 2,
            timestamp: 99,
            typeRaw: 29,
            classifier: 6,
            companionPhase: 1,
            yMotion: -1
        ),
        makeContractEvent(
            captureIndex: 3,
            timestamp: 110,
            typeRaw: 22,
            scrollPhase: 2,
            deltaY: -2
        ),
        makeContractEvent(captureIndex: 4, timestamp: 109, typeRaw: 29),
        makeContractEvent(
            captureIndex: 5,
            timestamp: 109,
            typeRaw: 29,
            classifier: 6,
            companionPhase: 2,
            yMotion: -2
        ),
        makeContractEvent(
            captureIndex: 6,
            timestamp: 120,
            typeRaw: 22,
            scrollPhase: 4
        ),
        makeContractEvent(captureIndex: 7, timestamp: 119, typeRaw: 29),
        makeContractEvent(
            captureIndex: 8,
            timestamp: 119,
            typeRaw: 29,
            classifier: 6,
            companionPhase: 4
        ),
        makeContractEvent(
            captureIndex: 9,
            timestamp: 130,
            typeRaw: 22,
            momentumPhase: 1,
            deltaY: -3
        ),
        makeContractEvent(
            captureIndex: 10,
            timestamp: 140,
            typeRaw: 22,
            momentumPhase: 2,
            deltaY: -2
        ),
        makeContractEvent(
            captureIndex: 11,
            timestamp: 150,
            typeRaw: 22,
            momentumPhase: 3
        )
    ]
}

private struct ContractTestInput {
    var documents: [TrackpadDriverEventDocument]
    var manifest: TrackpadDriverEventCaptureManifest
}

private func makeContractTestInput(
    _ events: [TrackpadDriverEventLog],
    scenarioID: String = "pure-trackpad-vertical-scroll",
    osBuild: String = "25F80",
    evidenceKind: TrackpadDriverEventEvidenceKind = .generatedProduct,
    requireStrictPass: Bool = true
) -> ContractTestInput? {
    var normalizedEvents = events
    for index in normalizedEvents.indices {
        guard var metadata = normalizedEvents[index].metadata else {
            expect(false, "contract test eventにmetadataがある")
            return nil
        }
        metadata.scenarioID = scenarioID
        metadata.osBuild = osBuild
        normalizedEvents[index].metadata = metadata
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = Data()
    for event in normalizedEvents {
        do {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        } catch {
            expect(false, "contract test eventをencodeできる: \(error)")
            return nil
        }
    }
    let strictReport = TrackpadDriverEventAnalyzer.analyze(data)
    if requireStrictPass {
        expect(strictReport.passed, "contract test event列がstrict current schemaを満たす")
    }
    do {
        let summary = try TrackpadDriverEventCaptureManifest.summarize(logData: data)
        return ContractTestInput(
            documents: strictReport.documents,
            manifest: TrackpadDriverEventCaptureManifest(
                evidenceKind: evidenceKind,
                logSHA256: summary.logSHA256,
                logByteCount: summary.logByteCount,
                eventCount: summary.eventCount,
                firstEventTimestamp: summary.firstEventTimestamp,
                lastEventTimestamp: summary.lastEventTimestamp,
                osVersion: summary.metadata.osVersion,
                osBuild: summary.metadata.osBuild,
                scenarioID: summary.metadata.scenarioID,
                deviceLabel: summary.metadata.deviceLabel,
                repoHeadSHA: summary.metadata.repoHeadSHA,
                loggerVersion: summary.metadata.loggerVersion,
                loggerExecutableSHA256: String(repeating: "c", count: 64),
                captureStartedAt: "2026-07-11T00:00:00.000Z",
                captureCompletedAt: "2026-07-11T00:00:01.000Z"
            )
        )
    } catch {
        expect(false, "contract test manifestを実データから作れる: \(error)")
        return nil
    }
}

private func analyzeContract(
    _ events: [TrackpadDriverEventLog],
    scenarioID: String = "pure-trackpad-vertical-scroll",
    osBuild: String = "25F80",
    evidenceKind: TrackpadDriverEventEvidenceKind = .generatedProduct,
    requireStrictPass: Bool = true,
    mutateManifest: ((inout TrackpadDriverEventCaptureManifest) -> Void)? = nil
) -> TrackpadScrollMomentumContractAnalysis? {
    guard let contract = readScrollMomentumContract(),
          let input = makeContractTestInput(
              events,
              scenarioID: scenarioID,
              osBuild: osBuild,
              evidenceKind: evidenceKind,
              requireStrictPass: requireStrictPass
          )
    else {
        return nil
    }
    var manifest = input.manifest
    mutateManifest?(&manifest)
    return TrackpadScrollMomentumContractAnalyzer.analyze(
        documents: input.documents,
        manifest: manifest,
        contract: contract
    )
}

private func contractHasIssue(
    _ report: TrackpadScrollMomentumContractAnalysis?,
    _ code: TrackpadScrollMomentumContractIssueCode
) -> Bool {
    report?.issues.contains(where: { $0.code == code }) == true
}

private func mutateRawInteger(
    _ event: inout TrackpadDriverEventLog,
    fieldNumber: Int,
    value: Int64
) {
    guard let index = event.rawFields.firstIndex(where: { $0.fieldNumber == fieldNumber }) else {
        preconditionFailure("raw fieldがありません: \(fieldNumber)")
    }
    event.rawFields[index].integerValue = value
}

private func testScrollMomentumContractFixtureIdentity() {
    do {
        let data = try Data(contentsOf: scrollMomentumContractFixtureURL())
        let report = TrackpadScrollMomentumContractDocumentReader.read(data: data)
        expect(TrackpadScrollMomentumContractDocumentReader.registeredFixtureCount == 1, "登録fixtureを1件に限定する")
        expect(report.passed, "fixture ID / SHA / schema / OS登録を完全一致で受理する")
        expect(
            report.document?.fixtureSHA256
                == "8e2a1841ef23a47fcb274c1c8e7c7c39be43e8ab7c8792caf2cd874242a61294",
            "scroll / momentum fixture SHAを固定する"
        )
        let rawFixture = try JSONSerialization.jsonObject(with: data)
        var rawKeys = Set<String>()
        collectContractFixtureJSONKeys(rawFixture, into: &rawKeys)
        let forbiddenKeys: Set<String> = [
            "serializedeventbase64",
            "sourceuserdata",
            "rawfields",
            "keycode",
            "pointercoordinates",
            "deviceidentifier",
            "vendorid",
            "productid",
            "serialnumber",
            "locationid"
        ]
        expect(
            rawKeys.isDisjoint(with: forbiddenKeys),
            "versioned contract fixtureへ入力payloadやdevice identifierを含めない"
        )

        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["futureContractField"] = ["retained": true]
        let modified = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let modifiedReport = TrackpadScrollMomentumContractDocumentReader.read(data: modified)
        expect(!modifiedReport.passed, "登録SHAと異なるfixtureを拒否する")
        expect(
            modifiedReport.document?.unknownTopLevelFields.contains("futureContractField") == true,
            "未登録fixtureでもunknown fieldを捨てずreport用documentへ保持する"
        )
        expect(
            modifiedReport.issues.contains(where: { $0.code == .fixtureRegistrationMismatch }),
            "fixture bytes変更をregistration mismatchとして返す"
        )

        let malformed = Data("{\"fixtureID\":\"a\",\"fixtureID\":\"b\"}".utf8)
        let malformedReport = TrackpadScrollMomentumContractDocumentReader.read(data: malformed)
        expect(!malformedReport.passed, "duplicate fixture keyを拒否する")
        expect(
            malformedReport.issues.contains(where: { $0.code == .invalidFixtureJSON }),
            "duplicate keyを厳格JSON issueとして返す"
        )
    } catch {
        expect(false, "fixture reader testを実行できる: \(error)")
    }
}

private func testScrollMomentumContractMatchesPhysicalObservationProvenance() {
    guard let contract = readScrollMomentumContract() else {
        return
    }
    do {
        let data = try Data(contentsOf: physicalObservationContractFixtureURL())
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let observedContracts = object["observedContracts"] as! [String: Any]
        let captures = object["captures"] as! [[String: Any]]
        let usableCaptures = captures.filter { $0["status"] as? String == "usable" }
        let observedSources = Dictionary(
            uniqueKeysWithValues: usableCaptures.map { capture in
                (
                    capture["scenarioID"] as! String,
                    [
                        capture["sourceFile"] as! String,
                        capture["sourceLogSHA256"] as! String,
                        String(capture["sourceEventCount"] as! Int),
                        String(capture["contractPrefixEventCount"] as! Int),
                        String(capture["analysisStartCaptureIndex"] as! Int),
                        capture["captureStartedAt"] as! String,
                        capture["captureCompletedAt"] as! String
                    ].joined(separator: "|")
                )
            }
        )
        let contractSources = Dictionary(
            uniqueKeysWithValues: contract.fixture.sourceCaptures.map { source in
                (
                    source.scenarioID,
                    [
                        source.sourceFile,
                        source.sourceLogSHA256,
                        String(source.sourceEventCount),
                        String(source.contractPrefixEventCount),
                        String(source.analysisStartCaptureIndex),
                        source.captureStartedAt,
                        source.captureCompletedAt
                    ].joined(separator: "|")
                )
            }
        )

        expect(
            observedContracts["scrollMomentumContractID"] as? String
                == contract.fixture.contractID,
            "観測台帳と専用fixtureのcontract IDを一致させる"
        )
        expect(object["osVersion"] as? String == contract.fixture.osVersion, "観測台帳と専用fixtureのOS versionを一致させる")
        expect(object["osBuild"] as? String == contract.fixture.osBuild, "観測台帳と専用fixtureのOS buildを一致させる")
        expect(
            object["deviceLabel"] as? String == contract.fixture.referenceDeviceLabel,
            "観測台帳と専用fixtureのreference deviceを一致させる"
        )
        expect(
            object["loggerRepoHeadSHA"] as? String
                == contract.fixture.referenceLogger.repoHeadSHA,
            "観測台帳と専用fixtureのlogger repo SHAを一致させる"
        )
        expect(
            object["loggerExecutableSHA256"] as? String
                == contract.fixture.referenceLogger.executableSHA256,
            "観測台帳と専用fixtureのlogger executable SHAを一致させる"
        )
        expect(observedSources == contractSources, "採用した4 source captureの原本identityと解析境界を一致させる")
    } catch {
        expect(false, "観測台帳と専用fixtureのprovenanceを照合できる: \(error)")
    }
}

private func testScrollMomentumContractAcceptsConfirmedSequence() {
    let report = analyzeContract(makeContractSequence())

    expect(report?.passed == true, "25F80の確定済みscroll / companion / momentum列を受理する")
    expect(report?.scrollEventCount == 6, "type 22件数を集計する")
    expect(report?.scrollCompanionCount == 3, "scroll companion件数を集計する")
    expect(report?.pairedCompanionCount == 3, "phaseと局所順序でcompanionを対応付ける")
    expect(report?.scrollLifecycleCount == 1, "scroll lifecycleを完結数で集計する")
    expect(report?.momentumLifecycleCount == 1, "momentum lifecycleを完結数で集計する")
    expect(report?.captureIndexDeltaValues == [2], "固定差を要求せず実際のcaptureIndex差をreportする")
    expect(report?.equalTimestampPairCount == 0, "scrollとcompanionのtimestamp同値を要求しない")
}

private func testScrollMomentumContractRejectsLifecycleBreakage() {
    var missingScrollTerminal = makeContractSequence()
    mutateRawInteger(&missingScrollTerminal[6], fieldNumber: 99, value: 2)
    missingScrollTerminal[6].scrollPhase = 2
    let missingScrollReport = analyzeContract(missingScrollTerminal)
    expect(contractHasIssue(missingScrollReport, .missingScrollTerminal), "scroll terminal欠落を失敗にする")

    let missingMomentumTerminal = analyzeContract(Array(makeContractSequence().dropLast()))
    expect(contractHasIssue(missingMomentumTerminal, .missingMomentumTerminal), "momentum terminal欠落を失敗にする")

    var simultaneous = makeContractSequence()
    mutateRawInteger(&simultaneous[3], fieldNumber: 123, value: 1)
    simultaneous[3].momentumPhase = 1
    let simultaneousReport = analyzeContract(simultaneous)
    expect(contractHasIssue(simultaneousReport, .simultaneousPhases), "scroll / momentum同時activeを拒否する")

    var regressing = makeContractSequence()
    regressing[3].timestamp = 90
    mutateRawInteger(&regressing[3], fieldNumber: 58, value: 90)
    let regressingReport = analyzeContract(regressing)
    expect(contractHasIssue(regressingReport, .lifecycleTimestampRegression), "同一type22 lifecycle内timestamp逆行を拒否する")
}

private func testScrollMomentumContractRejectsTerminalAndFieldMismatch() {
    var terminalDelta = makeContractSequence()
    terminalDelta[11].scrollPointDeltaY = -1
    terminalDelta[11].scrollPointDeltaYBitPattern = Double(-1).bitPattern
    let terminalReport = analyzeContract(terminalDelta)
    expect(contractHasIssue(terminalReport, .terminalDeltaMismatch), "momentum terminalのnamed delta非0を拒否する")

    var negativeZeroTerminal = makeContractSequence()
    negativeZeroTerminal[11].scrollPointDeltaY = -0.0
    negativeZeroTerminal[11].scrollPointDeltaYBitPattern = Double(-0.0).bitPattern
    let negativeZeroReport = analyzeContract(negativeZeroTerminal)
    expect(contractHasIssue(negativeZeroReport, .terminalDeltaMismatch), "momentum terminalの-0.0を正のzeroとして受理しない")

    var continuous = makeContractSequence()
    mutateRawInteger(&continuous[3], fieldNumber: 88, value: 0)
    let continuousReport = analyzeContract(continuous)
    expect(contractHasIssue(continuousReport, .continuousMismatch), "raw continuous field不一致を拒否する")

    var rawTimestamp = makeContractSequence()
    mutateRawInteger(&rawTimestamp[0], fieldNumber: 58, value: 99)
    let timestampReport = analyzeContract(rawTimestamp)
    expect(contractHasIssue(timestampReport, .rawTimestampMismatch), "raw 58とtop-level timestamp不一致を拒否する")
}

private func testScrollMomentumContractRejectsCompanionBreakage() {
    var missingChangedCompanion = makeContractSequence()
    mutateRawInteger(&missingChangedCompanion[5], fieldNumber: 110, value: 0)
    let coverageReport = analyzeContract(missingChangedCompanion)
    expect(contractHasIssue(coverageReport, .companionCoverageInsufficient), "changed companion欠落が実測coverageを下回れば拒否する")

    var missingEndedCompanion = makeContractSequence()
    mutateRawInteger(&missingEndedCompanion[8], fieldNumber: 110, value: 0)
    let requiredReport = analyzeContract(missingEndedCompanion)
    expect(contractHasIssue(requiredReport, .requiredCompanionMissing), "ended companion欠落を拒否する")

    var envelopeMismatch = makeContractSequence()
    mutateRawInteger(&envelopeMismatch[4], fieldNumber: 110, value: 1)
    let envelopeReport = analyzeContract(envelopeMismatch)
    expect(contractHasIssue(envelopeReport, .companionEnvelopeMismatch), "companion直前envelope classifier違いを拒否する")

    var phaseMismatch = makeContractSequence()
    mutateRawInteger(&phaseMismatch[5], fieldNumber: 132, value: 1)
    phaseMismatch[5].scrollPhase = 0
    let phaseReport = analyzeContract(phaseMismatch)
    expect(contractHasIssue(phaseReport, .companionUnmatched), "companion phase不一致を拒否する")

    var aliasMismatch = makeContractSequence()
    mutateRawInteger(&aliasMismatch[5], fieldNumber: 165, value: 0)
    let aliasReport = analyzeContract(aliasMismatch)
    expect(contractHasIssue(aliasReport, .companionFieldMismatch), "companion motion alias不一致を拒否する")

    var unconfirmedGesture = makeContractSequence()
    mutateRawInteger(&unconfirmedGesture[4], fieldNumber: 110, value: 7)
    let unconfirmedReport = analyzeContract(unconfirmedGesture)
    expect(contractHasIssue(unconfirmedReport, .unconfirmedGestureEvent), "generated scroll familyへの未確定type 29 classifier混入を拒否する")

    var unconfirmedEventType = makeContractSequence()
    unconfirmedEventType.append(
        makeContractEvent(captureIndex: 12, timestamp: 160, typeRaw: 30)
    )
    let unconfirmedTypeReport = analyzeContract(unconfirmedEventType)
    expect(contractHasIssue(unconfirmedTypeReport, .unconfirmedGestureEvent), "generated scroll familyへの未確定event type混入を拒否する")
}

private func testScrollMomentumContractBindsManifestAndCaptureOrder() {
    let mismatchedManifest = analyzeContract(
        makeContractSequence(),
        mutateManifest: { manifest in
            manifest.logSHA256 = String(repeating: "d", count: 64)
        }
    )
    expect(
        contractHasIssue(mismatchedManifest, .manifestDocumentMismatch),
        "manifestと解析document bytesの不一致を拒否する"
    )

    var duplicateCaptureIndex = makeContractSequence()
    duplicateCaptureIndex[1].captureIndex = 0
    let duplicateReport = analyzeContract(
        duplicateCaptureIndex,
        requireStrictPass: false
    )
    expect(
        contractHasIssue(duplicateReport, .captureIndexMismatch),
        "重複captureIndexをtrapせず構造化issueとして拒否する"
    )
}

private func testScrollMomentumContractFailsClosedOutsideConfirmedScope() {
    let candidateScenario = analyzeContract(
        makeContractSequence(),
        scenarioID: "pure-trackpad-pinch-in-out"
    )
    expect(contractHasIssue(candidateScenario, .scenarioNotConfirmed), "magnification候補scenarioを確定contractとして受理しない")

    let otherBuild = analyzeContract(
        makeContractSequence(),
        osBuild: "25F81"
    )
    expect(contractHasIssue(otherBuild, .osBuildMismatch), "未知OS buildをfail closedにする")

    let synthetic = analyzeContract(makeContractSequence(), evidenceKind: .synthetic)
    expect(contractHasIssue(synthetic, .unsupportedEvidenceKind), "syntheticを純正contract合格証跡にしない")
}

private func testScrollMomentumContractReportIsCodable() {
    guard let report = analyzeContract(makeContractSequence()),
          let data = try? JSONEncoder().encode(report),
          let decoded = try? JSONDecoder().decode(
              TrackpadScrollMomentumContractAnalysis.self,
              from: data
          )
    else {
        expect(false, "contract analysis reportをCodable round-tripできる")
        return
    }
    expect(decoded == report, "contract analysis reportをlosslessにCodable round-tripできる")
}

func runTrackpadScrollMomentumContractAnalyzerTests() {
    testScrollMomentumContractFixtureIdentity()
    testScrollMomentumContractMatchesPhysicalObservationProvenance()
    testScrollMomentumContractAcceptsConfirmedSequence()
    testScrollMomentumContractRejectsLifecycleBreakage()
    testScrollMomentumContractRejectsTerminalAndFieldMismatch()
    testScrollMomentumContractRejectsCompanionBreakage()
    testScrollMomentumContractBindsManifestAndCaptureOrder()
    testScrollMomentumContractFailsClosedOutsideConfirmedScope()
    testScrollMomentumContractReportIsCodable()
}
