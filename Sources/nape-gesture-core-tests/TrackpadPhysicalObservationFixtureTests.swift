import Foundation

private struct PhysicalObservationFixture: Decodable {
    struct Privacy: Decodable {
        var containsSerializedEvents: Bool
        var containsPointerCoordinates: Bool
        var containsKeyboardData: Bool
        var containsDeviceIdentifiers: Bool
        var sourceRawLogsCommitted: Bool
    }

    struct Capture: Decodable {
        var scenarioID: String
        var sourceFile: String
        var status: String
        var sourceLogSHA256: String
        var sourceEventCount: Int
        var contractPrefixEventCount: Int
        var captureStartedAt: String
        var captureCompletedAt: String
    }

    struct LegacyDiscovery: Decodable {
        struct PhaseCounts: Decodable {
            var began: Int
            var changed: Int
            var ended: Int
            var cancelled: Int
        }

        var scenarioID: String
        var status: String
        var sourceFile: String
        var reason: String
        var sourceLogSHA256: String
        var sourceEventCount: Int
        var rawType31Count: Int
        var rawType31PhaseCounts: PhaseCounts
    }

    struct Contracts: Decodable {
        struct Common: Decodable {
            struct PhaseValues: Decodable {
                var mayBegin: Int
                var began: Int
                var changed: Int
                var ended: Int
                var cancelled: Int
            }

            var typeRawField: Int
            var timestampRawField: Int
            var phaseRawField: Int
            var phaseValues: PhaseValues
            var timestampMayRegressAcrossCaptureOrder: Bool
        }

        struct Scroll: Decodable {
            var eventTypeRaw: Int
            var continuousRawField: Int
            var continuousValue: Int
            var scrollPhaseRawField: Int
            var scrollPhaseValues: [Int]
            var momentumPhaseRawField: Int
            var momentumPhaseValues: [Int]
            var momentumTerminalValue: Int
            var scrollTerminalHasZeroNamedDelta: Bool
            var momentumTerminalHasZeroNamedDelta: Bool
            var phasesMutuallyExclusive: Bool
            var momentumStartsAfterScrollTerminal: Bool
            var requiresScrollLifecycle: Bool
            var requiresMomentumLifecycle: Bool
            var type22TimestampNondecreasingWithinLifecycle: Bool
        }

        struct ScrollCompanion: Decodable {
            struct AssociationRule: Decodable {
                struct MinimumPairingCoverage: Decodable {
                    var paired: Int
                    var pairableScroll: Int
                }

                var preserveOrder: Bool
                var phaseMustMatch: Bool
                var maximumCaptureIndexDistance: Int
                var candidateSelection: String
                var unmatchedScrollAllowed: Bool
                var requiredMatchedScrollPhaseValues: [Int]
                var allowedUnmatchedScrollPhaseValues: [Int]
                var minimumPairingCoverage: MinimumPairingCoverage
            }

            var eventTypeRaw: Int
            var classifierRawField: Int
            var classifierValue: Int
            var envelopeClassifierValue: Int
            var phaseRawField: Int
            var xMotionDoubleFields: [Int]
            var xMotionFloatBitFields: [Int]
            var yMotionDoubleFields: [Int]
            var yMotionFloatBitFields: [Int]
            var constantRawFields: [String: Int]
            var associationRule: AssociationRule
            var pairableScrollSampleCount: Int
            var pairedSampleCount: Int
            var captureIndexDeltaValues: [Int]
            var timestampEqualToScrollWheel: Bool
        }

        struct Candidate: Decodable {
            var eventTypeRaw: Int
            var classifierRawField: Int
            var classifierValue: Int
            var envelopeClassifierValue: Int?
            var classificationStatus: String
        }

        var scrollMomentumContractID: String
        var common: Common
        var scroll: Scroll
        var scrollCompanion: ScrollCompanion
        var navigationCandidate: Candidate
        var magnificationCandidate: Candidate
        var dockSwipeCandidate: Candidate
    }

    var schemaVersion: Int
    var fixtureID: String
    var status: String
    var osVersion: String
    var osBuild: String
    var deviceLabel: String
    var loggerRepoHeadSHA: String
    var loggerExecutableSHA256: String
    var captureOrderField: String
    var privateClassifierRawField: Int
    var privacy: Privacy
    var captures: [Capture]
    var legacyDiscovery: LegacyDiscovery
    var observedContracts: Contracts
    var remainingPhysicalCaptures: [String]
}

private func physicalObservationFixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/trackpad-contract/25F80/physical-observations.json")
}

private func isCanonicalSHA256(_ value: String) -> Bool {
    value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
        (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
    }
}

private func isCanonicalGitObjectID(_ value: String) -> Bool {
    [40, 64].contains(value.count) && value.unicodeScalars.allSatisfy { scalar in
        (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
    }
}

private func physicalObservationWallClock(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func collectPhysicalObservationJSONKeys(
    from value: Any,
    into keys: inout Set<String>
) {
    if let object = value as? [String: Any] {
        for (key, nestedValue) in object {
            keys.insert(key.lowercased())
            collectPhysicalObservationJSONKeys(from: nestedValue, into: &keys)
        }
    } else if let array = value as? [Any] {
        for nestedValue in array {
            collectPhysicalObservationJSONKeys(from: nestedValue, into: &keys)
        }
    }
}

func runTrackpadPhysicalObservationFixtureTests() {
    do {
        let data = try Data(contentsOf: physicalObservationFixtureURL())
        let rawFixture = try JSONSerialization.jsonObject(with: data)
        let fixture = try JSONDecoder().decode(PhysicalObservationFixture.self, from: data)

        expect(fixture.schemaVersion == 1, "物理観測fixture schemaVersionを固定する")
        expect(
            fixture.fixtureID == "trackpad-physical-observations-25F80-v1",
            "物理観測fixture IDを固定する"
        )
        expect(fixture.status == "partial", "未取得contractをpartialとして可視化する")
        expect(fixture.osVersion == "26.5.1", "物理観測fixtureをOS versionへ固定する")
        expect(fixture.osBuild == "25F80", "物理観測fixtureをOS buildへ固定する")
        expect(fixture.deviceLabel == "built-in-trackpad", "非一意のdevice labelだけを保持する")
        expect(fixture.captureOrderField == "captureIndex", "配送順の正本をcaptureIndexへ固定する")
        expect(fixture.privateClassifierRawField == 110, "private classifier fieldを固定する")
        expect(fixture.captures.count == 8, "8つの物理scenario状態を保持する")
        expect(isCanonicalSHA256(fixture.loggerExecutableSHA256), "logger executable SHAを保持する")
        expect(
            isCanonicalGitObjectID(fixture.loggerRepoHeadSHA),
            "logger repo HEADを正規化済み完全長で保持する"
        )
        let expectedScenarioIDs: Set<String> = [
            "pure-trackpad-vertical-scroll",
            "pure-trackpad-horizontal-scroll",
            "pure-trackpad-momentum-stop",
            "pure-trackpad-page-swipe-left-right",
            "pure-trackpad-pinch-in-out",
            "pure-trackpad-spaces-left-right",
            "pure-trackpad-mission-control-app-expose",
            "pure-trackpad-cancel-reverse"
        ]
        let actualScenarioIDs = fixture.captures.map(\.scenarioID)
        expect(
            Set(actualScenarioIDs) == expectedScenarioIDs
                && Set(actualScenarioIDs).count == actualScenarioIDs.count,
            "物理scenario集合を重複なく固定する"
        )
        let expectedSourceFiles: Set<String> = [
            "vertical-scroll.jsonl",
            "horizontal-scroll.jsonl",
            "momentum-stop.jsonl",
            "page-swipe-left-right.jsonl",
            "pinch-in-out.jsonl",
            "spaces-left-right.jsonl",
            "mission-control-app-expose.jsonl",
            "cancel-reverse.jsonl"
        ]
        expect(
            Set(fixture.captures.map(\.sourceFile)) == expectedSourceFiles,
            "全scenarioをlocal原本file名へ一意に対応付ける"
        )
        let expectedCaptureStates = [
            "pure-trackpad-vertical-scroll": "vertical-scroll.jsonl|usable",
            "pure-trackpad-horizontal-scroll": "horizontal-scroll.jsonl|usable",
            "pure-trackpad-momentum-stop": "momentum-stop.jsonl|usable",
            "pure-trackpad-page-swipe-left-right": "page-swipe-left-right.jsonl|candidate-only",
            "pure-trackpad-pinch-in-out": "pinch-in-out.jsonl|candidate-only",
            "pure-trackpad-spaces-left-right": "spaces-left-right.jsonl|candidate-only",
            "pure-trackpad-mission-control-app-expose": "mission-control-app-expose.jsonl|capture-window-missed",
            "pure-trackpad-cancel-reverse": "cancel-reverse.jsonl|usable"
        ]
        let actualCaptureStates = Dictionary(
            uniqueKeysWithValues: fixture.captures.map { capture in
                (capture.scenarioID, "\(capture.sourceFile)|\(capture.status)")
            }
        )
        expect(
            actualCaptureStates == expectedCaptureStates,
            "各scenarioのsource fileと確定度を固定する"
        )
        expect(
            fixture.captures.allSatisfy {
                isCanonicalSHA256($0.sourceLogSHA256)
                    && $0.sourceEventCount >= $0.contractPrefixEventCount
                    && $0.contractPrefixEventCount > 0
            },
            "全scenarioをsource SHAと非空prefixへ固定する"
        )
        expect(
            fixture.captures.allSatisfy { capture in
                guard
                    let startedAt = physicalObservationWallClock(capture.captureStartedAt),
                    let completedAt = physicalObservationWallClock(capture.captureCompletedAt)
                else {
                    return false
                }
                return startedAt <= completedAt
            },
            "全scenarioの開始・完了wall-clockを順序付きで保持する"
        )
        expect(
            fixture.captures.filter { $0.status == "capture-window-missed" }.map(\.scenarioID)
                == ["pure-trackpad-mission-control-app-expose"],
            "取得窓不成立scenarioを隠さない"
        )
        expect(!fixture.privacy.containsSerializedEvents, "公開fixtureへserialized eventを残さない")
        expect(!fixture.privacy.containsPointerCoordinates, "公開fixtureへpointer座標を残さない")
        expect(!fixture.privacy.containsKeyboardData, "公開fixtureへkeyboard情報を残さない")
        expect(!fixture.privacy.containsDeviceIdentifiers, "公開fixtureへdevice identifierを残さない")
        expect(!fixture.privacy.sourceRawLogsCommitted, "raw physical logをgit fixtureへ混在させない")
        var rawKeys = Set<String>()
        collectPhysicalObservationJSONKeys(from: rawFixture, into: &rawKeys)
        let forbiddenRawKeys: Set<String> = [
            "serializedeventbase64",
            "sourceuserdata",
            "rawfields",
            "keycode",
            "keyboardkeycode",
            "characters",
            "charactersignoringmodifiers",
            "pointercoordinates",
            "pointerx",
            "pointery",
            "mousex",
            "mousey",
            "locationx",
            "locationy",
            "deviceidentifier",
            "deviceuniqueid",
            "registryentryid",
            "vendorid",
            "productid",
            "serialnumber",
            "locationid"
        ]
        expect(
            rawKeys.isDisjoint(with: forbiddenRawKeys),
            "privacy宣言だけでなくraw JSON keyから入力情報混入を拒否する"
        )

        let legacy = fixture.legacyDiscovery
        expect(
            legacy.status == "not-adoptable"
                && legacy.scenarioID == "pure-trackpad-horizontal-scroll"
                && legacy.sourceFile == "horizontal-scroll.jsonl"
                && legacy.reason.contains("schema 1")
                && isCanonicalSHA256(legacy.sourceLogSHA256)
                && legacy.sourceEventCount == 524
                && legacy.rawType31Count == 21
                && legacy.rawType31PhaseCounts.began == 1
                && legacy.rawType31PhaseCounts.changed == 20
                && legacy.rawType31PhaseCounts.ended == 0
                && legacy.rawType31PhaseCounts.cancelled == 0,
            "terminalと開始wall-clockを欠くlegacy系列を採用不可へ固定する"
        )

        let contracts = fixture.observedContracts
        expect(
            contracts.scrollMomentumContractID == "trackpad-scroll-momentum-v1",
            "scroll / momentum contract IDを固定する"
        )
        expect(
            contracts.common.typeRawField == 55
                && contracts.common.timestampRawField == 58
                && contracts.common.phaseRawField == 132,
            "共通raw field番号を固定する"
        )
        let phaseValues = contracts.common.phaseValues
        expect(
            phaseValues.mayBegin == 128
                && phaseValues.began == 1
                && phaseValues.changed == 2
                && phaseValues.ended == 4
                && phaseValues.cancelled == 8,
            "共通phase値を固定する"
        )
        expect(
            contracts.common.timestampMayRegressAcrossCaptureOrder,
            "captureIndexとtimestamp順を分離する"
        )
        expect(
            contracts.scroll.eventTypeRaw == 22
                && contracts.scroll.continuousRawField == 88
                && contracts.scroll.continuousValue == 1
                && contracts.scroll.scrollPhaseRawField == 99
                && contracts.scroll.scrollPhaseValues == [1, 2, 4, 128]
                && contracts.scroll.momentumPhaseRawField == 123
                && contracts.scroll.momentumPhaseValues == [0, 1, 2, 3]
                && contracts.scroll.momentumTerminalValue == 3,
            "scroll / momentum contractを固定する"
        )
        expect(
            contracts.scroll.scrollTerminalHasZeroNamedDelta
                && contracts.scroll.momentumTerminalHasZeroNamedDelta
                && contracts.scroll.phasesMutuallyExclusive
                && contracts.scroll.momentumStartsAfterScrollTerminal
                && contracts.scroll.requiresScrollLifecycle
                && contracts.scroll.requiresMomentumLifecycle
                && contracts.scroll.type22TimestampNondecreasingWithinLifecycle,
            "scroll / momentumのterminal・phase・lifecycle・timestamp要件を固定する"
        )
        expect(
            contracts.scrollCompanion.eventTypeRaw == 29
                && contracts.scrollCompanion.classifierRawField == 110
                && contracts.scrollCompanion.classifierValue == 6
                && contracts.scrollCompanion.envelopeClassifierValue == 0
                && contracts.scrollCompanion.phaseRawField == 132
                && contracts.scrollCompanion.xMotionDoubleFields == [113, 114, 116, 118]
                && contracts.scrollCompanion.xMotionFloatBitFields == [115, 117, 164]
                && contracts.scrollCompanion.yMotionDoubleFields == [119, 139]
                && contracts.scrollCompanion.yMotionFloatBitFields == [123, 165]
                && contracts.scrollCompanion.constantRawFields == ["124": 0, "135": 1]
                && contracts.scrollCompanion.pairableScrollSampleCount == 1_172
                && contracts.scrollCompanion.pairedSampleCount == 1_165,
            "scroll companion実測を固定する"
        )
        expect(
            contracts.scrollCompanion.captureIndexDeltaValues == [-1, 2, 3, 4]
                && !contracts.scrollCompanion.timestampEqualToScrollWheel,
            "companionをtimestamp一致や固定index差で誤判定しない"
        )
        let associationRule = contracts.scrollCompanion.associationRule
        expect(
            associationRule.preserveOrder
                && associationRule.phaseMustMatch
                && associationRule.maximumCaptureIndexDistance == 8
                && associationRule.candidateSelection
                    == "minimum-absolute-timestamp-difference-then-capture-index-distance"
                && associationRule.unmatchedScrollAllowed
                && associationRule.requiredMatchedScrollPhaseValues == [1, 4, 128]
                && associationRule.allowedUnmatchedScrollPhaseValues == [2]
                && associationRule.minimumPairingCoverage.paired == 29
                && associationRule.minimumPairingCoverage.pairableScroll == 30,
            "scroll companionの再導出規則を曖昧にしない"
        )
        expect(
            contracts.navigationCandidate.eventTypeRaw == 30
                && contracts.navigationCandidate.classifierRawField == 110
                && contracts.navigationCandidate.classifierValue == 23
                && contracts.navigationCandidate.classificationStatus == "candidate-only"
                && contracts.magnificationCandidate.eventTypeRaw == 29
                && contracts.magnificationCandidate.classifierRawField == 110
                && contracts.magnificationCandidate.classifierValue == 8
                && contracts.magnificationCandidate.envelopeClassifierValue == 4
                && contracts.magnificationCandidate.classificationStatus == "candidate-only"
                && contracts.dockSwipeCandidate.eventTypeRaw == 29
                && contracts.dockSwipeCandidate.classifierRawField == 110
                && contracts.dockSwipeCandidate.classifierValue == 32
                && contracts.dockSwipeCandidate.classificationStatus == "single-direction-candidate",
            "未確定event familyを完成contractへ昇格させない"
        )
        let expectedRemainingCaptures: Set<String> = [
            "completed NavigationSwipe left and right series with action markers",
            "magnification positive and negative series with pinch-in and pinch-out markers",
            "DockSwipe opposite direction and cancel series",
            "Mission Control and App Expose series after ready-file"
        ]
        expect(
            Set(fixture.remainingPhysicalCaptures) == expectedRemainingCaptures
                && fixture.remainingPhysicalCaptures.count == expectedRemainingCaptures.count,
            "残る4つの物理capture境界を重複なく固定する"
        )
    } catch {
        expect(false, "物理観測fixtureをdecodeして検証できる: \(error)")
    }
}
