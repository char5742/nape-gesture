import Foundation

public struct TrackpadScrollMomentumContractAnalysis: Codable, Equatable, Sendable {
    public var passed: Bool
    public var provided: Bool
    public var fixtureID: String?
    public var fixtureSHA256: String?
    public var contractID: String?
    public var osVersion: String?
    public var osBuild: String?
    public var referenceDeviceLabel: String?
    public var referenceLoggerRepoHeadSHA: String?
    public var referenceLoggerExecutableSHA256: String?
    public var scenarioID: String?
    public var evidenceKind: TrackpadDriverEventEvidenceKind?
    public var referenceSourceLogSHA256: String?
    public var analyzedEventCount: Int
    public var scrollEventCount: Int
    public var scrollCompanionCount: Int
    public var pairedCompanionCount: Int
    public var scrollLifecycleCount: Int
    public var momentumLifecycleCount: Int
    public var captureIndexDeltaValues: [Int64]
    public var equalTimestampPairCount: Int
    public var unknownFixtureFields: LosslessJSONObject
    public var issues: [TrackpadScrollMomentumContractIssue]

    public static func unavailable(message: String) -> Self {
        Self(
            provided: false,
            document: nil,
            scenarioID: nil,
            evidenceKind: nil,
            referenceSourceLogSHA256: nil,
            analyzedEventCount: 0,
            scrollEventCount: 0,
            scrollCompanionCount: 0,
            pairedCompanionCount: 0,
            scrollLifecycleCount: 0,
            momentumLifecycleCount: 0,
            captureIndexDeltaValues: [],
            equalTimestampPairCount: 0,
            issues: [
                TrackpadScrollMomentumContractIssue(
                    code: .fixtureReadFailed,
                    message: message
                )
            ]
        )
    }

    public static func fixtureFailure(
        _ report: TrackpadScrollMomentumContractDocumentReadReport
    ) -> Self {
        Self(
            provided: true,
            document: report.document,
            scenarioID: nil,
            evidenceKind: nil,
            referenceSourceLogSHA256: nil,
            analyzedEventCount: 0,
            scrollEventCount: 0,
            scrollCompanionCount: 0,
            pairedCompanionCount: 0,
            scrollLifecycleCount: 0,
            momentumLifecycleCount: 0,
            captureIndexDeltaValues: [],
            equalTimestampPairCount: 0,
            issues: report.issues
        )
    }

    public static func blocked(
        document: TrackpadScrollMomentumContractDocument,
        message: String
    ) -> Self {
        Self(
            provided: true,
            document: document,
            scenarioID: nil,
            evidenceKind: nil,
            referenceSourceLogSHA256: nil,
            analyzedEventCount: 0,
            scrollEventCount: 0,
            scrollCompanionCount: 0,
            pairedCompanionCount: 0,
            scrollLifecycleCount: 0,
            momentumLifecycleCount: 0,
            captureIndexDeltaValues: [],
            equalTimestampPairCount: 0,
            issues: [
                TrackpadScrollMomentumContractIssue(
                    code: .blockedByPrerequisite,
                    message: message
                )
            ]
        )
    }

    init(
        provided: Bool,
        document: TrackpadScrollMomentumContractDocument?,
        scenarioID: String?,
        evidenceKind: TrackpadDriverEventEvidenceKind?,
        referenceSourceLogSHA256: String?,
        analyzedEventCount: Int,
        scrollEventCount: Int,
        scrollCompanionCount: Int,
        pairedCompanionCount: Int,
        scrollLifecycleCount: Int,
        momentumLifecycleCount: Int,
        captureIndexDeltaValues: [Int64],
        equalTimestampPairCount: Int,
        issues: [TrackpadScrollMomentumContractIssue]
    ) {
        self.provided = provided
        fixtureID = document?.fixture.fixtureID
        fixtureSHA256 = document?.fixtureSHA256
        contractID = document?.fixture.contractID
        osVersion = document?.fixture.osVersion
        osBuild = document?.fixture.osBuild
        referenceDeviceLabel = document?.fixture.referenceDeviceLabel
        referenceLoggerRepoHeadSHA = document?.fixture.referenceLogger.repoHeadSHA
        referenceLoggerExecutableSHA256 = document?.fixture.referenceLogger.executableSHA256
        self.scenarioID = scenarioID
        self.evidenceKind = evidenceKind
        self.referenceSourceLogSHA256 = referenceSourceLogSHA256
        self.analyzedEventCount = analyzedEventCount
        self.scrollEventCount = scrollEventCount
        self.scrollCompanionCount = scrollCompanionCount
        self.pairedCompanionCount = pairedCompanionCount
        self.scrollLifecycleCount = scrollLifecycleCount
        self.momentumLifecycleCount = momentumLifecycleCount
        self.captureIndexDeltaValues = captureIndexDeltaValues
        self.equalTimestampPairCount = equalTimestampPairCount
        unknownFixtureFields = document?.unknownTopLevelFields ?? LosslessJSONObject()
        self.issues = issues
        passed = issues.isEmpty
    }
}

public enum TrackpadScrollMomentumContractAnalyzer {
    public static func analyze(
        documents: [TrackpadDriverEventDocument],
        manifest: TrackpadDriverEventCaptureManifest,
        contract: TrackpadScrollMomentumContractDocument
    ) -> TrackpadScrollMomentumContractAnalysis {
        Analyzer(
            documents: documents,
            manifest: manifest,
            contract: contract
        ).analyze()
    }
}

private struct Analyzer {
    private let documents: [TrackpadDriverEventDocument]
    private let manifest: TrackpadDriverEventCaptureManifest
    private let contractDocument: TrackpadScrollMomentumContractDocument

    init(
        documents: [TrackpadDriverEventDocument],
        manifest: TrackpadDriverEventCaptureManifest,
        contract: TrackpadScrollMomentumContractDocument
    ) {
        self.documents = documents
        self.manifest = manifest
        contractDocument = contract
    }

    func analyze() -> TrackpadScrollMomentumContractAnalysis {
        let fixture = contractDocument.fixture
        var issues: [TrackpadScrollMomentumContractIssue] = []
        let contractIssues = TrackpadScrollMomentumContractDocumentReader.validate(
            document: contractDocument
        )
        guard contractIssues.isEmpty else {
            return report(issues: contractIssues)
        }

        var logData = Data()
        for document in documents {
            logData.append(document.rawLineData)
            logData.append(0x0A)
        }
        do {
            try manifest.validate(logData: logData)
        } catch {
            issues.append(
                issue(
                    .manifestDocumentMismatch,
                    message: "manifestとcontract解析へ渡されたdocument bytesが一致しません: \(error.localizedDescription)"
                )
            )
            return report(issues: issues)
        }

        let strictReport = TrackpadDriverEventAnalyzer.analyze(logData)
        let captureIndexIssues = strictReport.issues.filter { issue in
            issue.code == .captureIndexMismatch
        }
        if !captureIndexIssues.isEmpty {
            issues.append(contentsOf: captureIndexIssues.map { strictIssue in
                issue(
                    .captureIndexMismatch,
                    captureIndex: strictIssue.captureIndex,
                    message: strictIssue.message
                )
            })
            return report(issues: issues)
        }
        guard strictReport.passed,
              strictReport.documents.count == documents.count
        else {
            issues.append(
                issue(
                    .blockedByPrerequisite,
                    message: "document bytesを再度strict解析した結果が不正です。issues=\(strictReport.issues.count)"
                )
            )
            return report(issues: issues)
        }
        let validatedDocuments = strictReport.documents

        guard manifest.evidenceKind == .physicalTrackpad
            || manifest.evidenceKind == .generatedProduct
        else {
            issues.append(
                issue(
                    .unsupportedEvidenceKind,
                    message: "contract比較にはphysicalTrackpadまたはgeneratedProduct証跡が必要です。actual=\(manifest.evidenceKind.rawValue)"
                )
            )
            return report(issues: issues)
        }
        guard let scenarioID = manifest.scenarioID else {
            issues.append(issue(.missingScenario, message: "contract比較にscenario IDが必要です。"))
            return report(issues: issues)
        }
        guard fixture.supportedScenarioIDs.contains(scenarioID),
              let sourceCapture = fixture.sourceCaptures.first(where: {
                  $0.scenarioID == scenarioID
              })
        else {
            issues.append(
                issue(
                    .scenarioNotConfirmed,
                    message: "scenarioは25F80の確定済みscroll / momentum contract対象ではありません: \(scenarioID)"
                )
            )
            return report(scenarioID: scenarioID, issues: issues)
        }

        if manifest.osVersion != fixture.osVersion {
            issues.append(
                issue(
                    .osVersionMismatch,
                    message: "candidate OS versionがfixtureと一致しません。expected=\(fixture.osVersion) actual=\(manifest.osVersion)"
                )
            )
        }
        if manifest.osBuild != fixture.osBuild {
            issues.append(
                issue(
                    .osBuildMismatch,
                    message: "candidate OS buildがfixtureと一致しません。expected=\(fixture.osBuild) actual=\(manifest.osBuild)"
                )
            )
        }

        let selectedDocuments: [TrackpadDriverEventDocument]
        if manifest.evidenceKind == .physicalTrackpad {
            let referenceMatches = manifest.logSHA256 == sourceCapture.sourceLogSHA256
                && manifest.eventCount == UInt64(sourceCapture.sourceEventCount)
                && manifest.deviceLabel == fixture.referenceDeviceLabel
                && manifest.repoHeadSHA == fixture.referenceLogger.repoHeadSHA
                && manifest.loggerExecutableSHA256 == fixture.referenceLogger.executableSHA256
                && manifest.captureStartedAt == sourceCapture.captureStartedAt
                && manifest.captureCompletedAt == sourceCapture.captureCompletedAt
            if !referenceMatches {
                issues.append(
                    issue(
                        .physicalReferenceMismatch,
                        message: "physicalTrackpad証跡が登録済みsource SHA、件数、device、logger、capture wall-clockと一致しません。"
                    )
                )
                return report(
                    scenarioID: scenarioID,
                    sourceCapture: sourceCapture,
                    issues: issues
                )
            }
            selectedDocuments = validatedDocuments.filter { document in
                guard let captureIndex = document.rawTopLevelObject["captureIndex"]?.uint64Value else {
                    return false
                }
                return captureIndex >= sourceCapture.analysisStartCaptureIndex
                    && captureIndex < UInt64(sourceCapture.contractPrefixEventCount)
            }
        } else {
            selectedDocuments = validatedDocuments
        }

        guard !selectedDocuments.isEmpty else {
            issues.append(issue(.emptyEventSequence, message: "contract比較対象eventがありません。"))
            return report(
                scenarioID: scenarioID,
                sourceCapture: sourceCapture,
                issues: issues
            )
        }

        var semanticEvents: [SemanticEvent] = []
        for document in selectedDocuments {
            guard let event = SemanticEvent(document: document) else {
                issues.append(
                    issue(
                        .blockedByPrerequisite,
                        captureIndex: document.eventLog.captureIndex,
                        message: "strict documentからcurrent schemaのraw eventを復元できません。"
                    )
                )
                continue
            }
            semanticEvents.append(event)
            validateCommonFields(event, fixture: fixture, issues: &issues)
        }

        var lifecycle = LifecycleAnalysis()
        analyzeLifecycles(
            semanticEvents,
            fixture: fixture,
            result: &lifecycle,
            issues: &issues
        )
        let companion = analyzeCompanions(
            semanticEvents,
            fixture: fixture,
            issues: &issues
        )

        return TrackpadScrollMomentumContractAnalysis(
            provided: true,
            document: contractDocument,
            scenarioID: scenarioID,
            evidenceKind: manifest.evidenceKind,
            referenceSourceLogSHA256: sourceCapture.sourceLogSHA256,
            analyzedEventCount: semanticEvents.count,
            scrollEventCount: lifecycle.scrollEventCount,
            scrollCompanionCount: companion.companionCount,
            pairedCompanionCount: companion.pairs.count,
            scrollLifecycleCount: lifecycle.scrollLifecycleCount,
            momentumLifecycleCount: lifecycle.momentumLifecycleCount,
            captureIndexDeltaValues: Array(Set(companion.pairs.compactMap { pair in
                pair.captureIndexDelta
            })).sorted(),
            equalTimestampPairCount: companion.pairs.filter { pair in
                pair.scroll.timestamp == pair.companion.timestamp
            }.count,
            issues: issues
        )
    }
}

private extension Analyzer {
    struct ActiveLifecycle {
        var startedAtCaptureIndex: UInt64
        var lastTimestamp: UInt64
    }

    struct LifecycleAnalysis {
        var scrollEventCount = 0
        var scrollLifecycleCount = 0
        var momentumLifecycleCount = 0
    }

    struct CompanionPair {
        var scroll: SemanticEvent
        var companion: SemanticEvent

        var captureIndexDelta: Int64? {
            guard scroll.captureIndex <= UInt64(Int64.max),
                  companion.captureIndex <= UInt64(Int64.max)
            else {
                return nil
            }
            return Int64(companion.captureIndex) - Int64(scroll.captureIndex)
        }
    }

    struct CompanionAnalysis {
        var companionCount: Int
        var pairs: [CompanionPair]
    }

    func report(
        scenarioID: String? = nil,
        sourceCapture: TrackpadScrollMomentumContractFixture.SourceCapture? = nil,
        issues: [TrackpadScrollMomentumContractIssue]
    ) -> TrackpadScrollMomentumContractAnalysis {
        TrackpadScrollMomentumContractAnalysis(
            provided: true,
            document: contractDocument,
            scenarioID: scenarioID,
            evidenceKind: manifest.evidenceKind,
            referenceSourceLogSHA256: sourceCapture?.sourceLogSHA256,
            analyzedEventCount: 0,
            scrollEventCount: 0,
            scrollCompanionCount: 0,
            pairedCompanionCount: 0,
            scrollLifecycleCount: 0,
            momentumLifecycleCount: 0,
            captureIndexDeltaValues: [],
            equalTimestampPairCount: 0,
            issues: issues
        )
    }

    func validateCommonFields(
        _ event: SemanticEvent,
        fixture: TrackpadScrollMomentumContractFixture,
        issues: inout [TrackpadScrollMomentumContractIssue]
    ) {
        let typeField = fixture.common.typeRawField
        guard let rawType = event.rawFields[typeField]?.integerValue else {
            issues.append(
                issue(
                    .rawFieldMissing,
                    captureIndex: event.captureIndex,
                    message: "raw type fieldがありません。field=\(typeField)"
                )
            )
            return
        }
        if rawType != Int64(event.typeRaw) {
            issues.append(
                issue(
                    .rawTypeMismatch,
                    captureIndex: event.captureIndex,
                    message: "raw typeがtop-level typeと一致しません。field=\(typeField) raw=\(rawType) topLevel=\(event.typeRaw)"
                )
            )
        }

        let timestampField = fixture.common.timestampRawField
        guard let rawTimestamp = event.rawFields[timestampField]?.integerValue,
              rawTimestamp >= 0
        else {
            issues.append(
                issue(
                    .rawFieldMissing,
                    captureIndex: event.captureIndex,
                    message: "raw timestamp fieldが非負整数ではありません。field=\(timestampField)"
                )
            )
            return
        }
        if UInt64(rawTimestamp) != event.timestamp {
            issues.append(
                issue(
                    .rawTimestampMismatch,
                    captureIndex: event.captureIndex,
                    message: "raw timestampがtop-level timestampと一致しません。field=\(timestampField) raw=\(rawTimestamp) topLevel=\(event.timestamp)"
                )
            )
        }
    }

    func analyzeLifecycles(
        _ events: [SemanticEvent],
        fixture: TrackpadScrollMomentumContractFixture,
        result: inout LifecycleAnalysis,
        issues: inout [TrackpadScrollMomentumContractIssue]
    ) {
        let scroll = fixture.scroll
        let momentum = fixture.momentum
        var scrollActive: ActiveLifecycle?
        var momentumActive: ActiveLifecycle?
        var momentumMayBegin = false

        for event in events where event.typeRaw == scroll.eventTypeRaw {
            result.scrollEventCount += 1
            guard let rawContinuous = event.rawFields[scroll.continuousRawField]?.integerValue else {
                issues.append(
                    issue(
                        .rawFieldMissing,
                        captureIndex: event.captureIndex,
                        message: "scroll continuous raw fieldがありません。field=\(scroll.continuousRawField)"
                    )
                )
                continue
            }
            if rawContinuous != scroll.continuousValue
                || event.integer("isContinuous") != scroll.continuousValue
            {
                issues.append(
                    issue(
                        .continuousMismatch,
                        captureIndex: event.captureIndex,
                        message: "scroll continuous値がfixtureと一致しません。expected=\(scroll.continuousValue) raw=\(rawContinuous) named=\(event.integer("isContinuous").map(String.init) ?? "nil")"
                    )
                )
            }

            guard let scrollPhase = event.rawFields[scroll.phaseRawField]?.integerValue,
                  let momentumPhase = event.rawFields[momentum.phaseRawField]?.integerValue
            else {
                issues.append(
                    issue(
                        .rawFieldMissing,
                        captureIndex: event.captureIndex,
                        message: "scrollまたはmomentum phase raw fieldがありません。"
                    )
                )
                continue
            }
            if event.integer("scrollPhase") != scrollPhase {
                issues.append(
                    issue(
                        .namedFieldMismatch,
                        captureIndex: event.captureIndex,
                        message: "raw scroll phaseとtop-level scrollPhaseが一致しません。raw=\(scrollPhase) named=\(event.integer("scrollPhase").map(String.init) ?? "nil")"
                    )
                )
            }
            if event.integer("momentumPhase") != momentumPhase {
                issues.append(
                    issue(
                        .namedFieldMismatch,
                        captureIndex: event.captureIndex,
                        message: "raw momentum phaseとtop-level momentumPhaseが一致しません。raw=\(momentumPhase) named=\(event.integer("momentumPhase").map(String.init) ?? "nil")"
                    )
                )
            }

            let scrollValues = scroll.phaseValues
            let momentumValues = momentum.phaseValues
            let allowedScroll: Set<Int64> = [
                0,
                scrollValues.mayBegin,
                scrollValues.began,
                scrollValues.changed,
                scrollValues.ended
            ]
            let allowedMomentum: Set<Int64> = [
                momentumValues.inactive,
                momentumValues.began,
                momentumValues.continued,
                momentumValues.ended
            ]
            if !allowedScroll.contains(scrollPhase) {
                issues.append(
                    issue(
                        .unknownScrollPhase,
                        captureIndex: event.captureIndex,
                        message: "25F80で未確定のscroll phaseです: \(scrollPhase)"
                    )
                )
                continue
            }
            if !allowedMomentum.contains(momentumPhase) {
                issues.append(
                    issue(
                        .unknownMomentumPhase,
                        captureIndex: event.captureIndex,
                        message: "25F80で未確定のmomentum phaseです: \(momentumPhase)"
                    )
                )
                continue
            }
            if scrollPhase != 0 && momentumPhase != momentumValues.inactive {
                issues.append(
                    issue(
                        .simultaneousPhases,
                        captureIndex: event.captureIndex,
                        message: "同じtype 22 eventでscroll phaseとmomentum phaseが同時にactiveです。"
                    )
                )
                continue
            }
            if scrollPhase == 0 && momentumPhase == momentumValues.inactive {
                issues.append(
                    issue(
                        .emptyScrollEvent,
                        captureIndex: event.captureIndex,
                        message: "type 22 eventにscrollまたはmomentum phaseがありません。"
                    )
                )
                continue
            }

            if scrollPhase != 0 {
                switch scrollPhase {
                case scrollValues.mayBegin:
                    if scrollActive != nil || momentumActive != nil {
                        issues.append(invalidScrollTransition(event, phase: scrollPhase))
                    }
                case scrollValues.began:
                    if scrollActive != nil || momentumActive != nil {
                        issues.append(invalidScrollTransition(event, phase: scrollPhase))
                    } else {
                        scrollActive = ActiveLifecycle(
                            startedAtCaptureIndex: event.captureIndex,
                            lastTimestamp: event.timestamp
                        )
                        momentumMayBegin = false
                    }
                case scrollValues.changed:
                    guard var active = scrollActive, momentumActive == nil else {
                        issues.append(invalidScrollTransition(event, phase: scrollPhase))
                        continue
                    }
                    validateTimestamp(event, active: active, family: "scroll", issues: &issues)
                    active.lastTimestamp = event.timestamp
                    scrollActive = active
                case scrollValues.ended:
                    guard let active = scrollActive, momentumActive == nil else {
                        issues.append(invalidScrollTransition(event, phase: scrollPhase))
                        continue
                    }
                    validateTimestamp(event, active: active, family: "scroll", issues: &issues)
                    validateTerminalDeltas(event, family: "scroll", issues: &issues)
                    scrollActive = nil
                    momentumMayBegin = true
                    result.scrollLifecycleCount += 1
                default:
                    break
                }
                continue
            }

            switch momentumPhase {
            case momentumValues.began:
                if momentumActive != nil || scrollActive != nil {
                    issues.append(invalidMomentumTransition(event, phase: momentumPhase))
                    continue
                }
                if !momentumMayBegin {
                    issues.append(
                        issue(
                            .momentumWithoutScrollTerminal,
                            captureIndex: event.captureIndex,
                            message: "momentum beganより前に完結したscroll endedがありません。"
                        )
                    )
                }
                momentumActive = ActiveLifecycle(
                    startedAtCaptureIndex: event.captureIndex,
                    lastTimestamp: event.timestamp
                )
                momentumMayBegin = false
            case momentumValues.continued:
                guard var active = momentumActive, scrollActive == nil else {
                    issues.append(invalidMomentumTransition(event, phase: momentumPhase))
                    continue
                }
                validateTimestamp(event, active: active, family: "momentum", issues: &issues)
                active.lastTimestamp = event.timestamp
                momentumActive = active
            case momentumValues.ended:
                guard let active = momentumActive, scrollActive == nil else {
                    issues.append(invalidMomentumTransition(event, phase: momentumPhase))
                    continue
                }
                validateTimestamp(event, active: active, family: "momentum", issues: &issues)
                validateTerminalDeltas(event, family: "momentum", issues: &issues)
                momentumActive = nil
                result.momentumLifecycleCount += 1
            default:
                issues.append(invalidMomentumTransition(event, phase: momentumPhase))
            }
        }

        if let scrollActive {
            issues.append(
                issue(
                    .missingScrollTerminal,
                    captureIndex: scrollActive.startedAtCaptureIndex,
                    message: "scroll beganに対応するendedがありません。"
                )
            )
        }
        if let momentumActive {
            issues.append(
                issue(
                    .missingMomentumTerminal,
                    captureIndex: momentumActive.startedAtCaptureIndex,
                    message: "momentum beganに対応するterminal 3がありません。"
                )
            )
        }
        if scroll.requiresCompletedLifecycle && result.scrollLifecycleCount == 0 {
            issues.append(issue(.missingScrollLifecycle, message: "完結したscroll lifecycleがありません。"))
        }
        if momentum.requiresCompletedLifecycle && result.momentumLifecycleCount == 0 {
            issues.append(issue(.missingMomentumLifecycle, message: "完結したmomentum lifecycleがありません。"))
        }
    }

    func analyzeCompanions(
        _ events: [SemanticEvent],
        fixture: TrackpadScrollMomentumContractFixture,
        issues: inout [TrackpadScrollMomentumContractIssue]
    ) -> CompanionAnalysis {
        let scroll = fixture.scroll
        let companionContract = fixture.scrollCompanion
        let allowedPhases: Set<Int64> = [
            scroll.phaseValues.mayBegin,
            scroll.phaseValues.began,
            scroll.phaseValues.changed,
            scroll.phaseValues.ended
        ]
        let pairableScrollEvents = events.filter { event in
            event.typeRaw == scroll.eventTypeRaw
                && event.rawFields[scroll.phaseRawField]
                    .flatMap(\.integerValue)
                    .map(allowedPhases.contains) == true
        }
        let companionEvents = events.filter { event in
            event.typeRaw == companionContract.eventTypeRaw
                && event.rawFields[companionContract.classifierRawField]?.integerValue
                    == companionContract.classifierValue
        }
        if manifest.evidenceKind == .generatedProduct {
            let confirmedClassifiers: Set<Int64> = [
                companionContract.envelopeClassifierValue,
                companionContract.classifierValue
            ]
            for event in events {
                guard event.typeRaw == scroll.eventTypeRaw
                    || event.typeRaw == companionContract.eventTypeRaw
                else {
                    issues.append(
                        issue(
                            .unconfirmedGestureEvent,
                            captureIndex: event.captureIndex,
                            message: "generated scroll familyへ未確定event typeが混在しています。actual=\(event.typeRaw)"
                        )
                    )
                    continue
                }
                guard event.typeRaw == companionContract.eventTypeRaw else {
                    continue
                }
                guard let classifier = event.rawFields[companionContract.classifierRawField]?.integerValue,
                      confirmedClassifiers.contains(classifier)
                else {
                    issues.append(
                        issue(
                            .unconfirmedGestureEvent,
                            captureIndex: event.captureIndex,
                            message: "generated scroll familyへ未確定のtype \(companionContract.eventTypeRaw) gestureが混在しています。許可classifier=\(confirmedClassifiers.sorted())"
                        )
                    )
                    continue
                }
            }
        }

        var eventByCaptureIndex: [UInt64: SemanticEvent] = [:]
        for event in events {
            if eventByCaptureIndex.updateValue(event, forKey: event.captureIndex) != nil {
                issues.append(
                    issue(
                        .captureIndexMismatch,
                        captureIndex: event.captureIndex,
                        message: "contract比較対象に重複captureIndexがあります。"
                    )
                )
            }
        }

        for companion in companionEvents {
            validateCompanionFields(companion, contract: companionContract, issues: &issues)
            guard companion.captureIndex > 0,
                  let envelope = eventByCaptureIndex[companion.captureIndex - 1]
            else {
                issues.append(
                    issue(
                        .companionEnvelopeMissing,
                        captureIndex: companion.captureIndex,
                        message: "scroll companion直前のenvelopeがありません。"
                    )
                )
                continue
            }
            let envelopeClassifier = envelope.rawFields[companionContract.classifierRawField]?.integerValue
            if envelope.typeRaw != companionContract.eventTypeRaw
                || envelopeClassifier != companionContract.envelopeClassifierValue
                || envelope.timestamp != companion.timestamp
            {
                issues.append(
                    issue(
                        .companionEnvelopeMismatch,
                        captureIndex: companion.captureIndex,
                        message: "直前eventが同timestampのtype \(companionContract.eventTypeRaw) / classifier \(companionContract.envelopeClassifierValue) envelopeではありません。"
                    )
                )
            }
        }

        var previousScrollPosition = -1
        var pairs: [CompanionPair] = []
        var matchedScrollPositions = Set<Int>()
        for companion in companionEvents {
            guard let companionPhase = companion.rawFields[companionContract.phaseRawField]?.integerValue else {
                continue
            }
            var best: (event: SemanticEvent, position: Int, timestampDifference: UInt64, distance: UInt64)?
            for (position, scrollEvent) in pairableScrollEvents.enumerated()
                where position > previousScrollPosition
            {
                guard scrollEvent.rawFields[scroll.phaseRawField]?.integerValue == companionPhase else {
                    continue
                }
                let distance = absoluteDifference(
                    scrollEvent.captureIndex,
                    companion.captureIndex
                )
                guard distance <= companionContract.associationRule.maximumCaptureIndexDistance else {
                    continue
                }
                let timestampDifference = absoluteDifference(
                    scrollEvent.timestamp,
                    companion.timestamp
                )
                if let currentBest = best,
                   (currentBest.timestampDifference < timestampDifference
                       || (currentBest.timestampDifference == timestampDifference
                           && currentBest.distance <= distance))
                {
                    continue
                }
                best = (scrollEvent, position, timestampDifference, distance)
            }
            guard let best else {
                issues.append(
                    issue(
                        .companionUnmatched,
                        captureIndex: companion.captureIndex,
                        message: "phase一致・順序保存・captureIndex距離\(companionContract.associationRule.maximumCaptureIndexDistance)以内のscrollがありません。"
                    )
                )
                continue
            }
            previousScrollPosition = best.position
            matchedScrollPositions.insert(best.position)
            pairs.append(CompanionPair(scroll: best.event, companion: companion))
        }

        let requiredPhases = Set(
            companionContract.associationRule.requiredMatchedScrollPhaseValues
        )
        let allowedUnmatched = Set(
            companionContract.associationRule.allowedUnmatchedScrollPhaseValues
        )
        for (position, scrollEvent) in pairableScrollEvents.enumerated()
            where !matchedScrollPositions.contains(position)
        {
            let phase = scrollEvent.rawFields[scroll.phaseRawField]?.integerValue
            if phase.map(requiredPhases.contains) == true || phase.map(allowedUnmatched.contains) != true {
                issues.append(
                    issue(
                        .requiredCompanionMissing,
                        captureIndex: scrollEvent.captureIndex,
                        message: "scroll phase \(phase.map(String.init) ?? "nil")に必要なcompanionがありません。"
                    )
                )
            }
        }

        let coverage = companionContract.associationRule.minimumPairingCoverage
        if pairs.count * coverage.pairableScroll
            < pairableScrollEvents.count * coverage.paired
        {
            issues.append(
                issue(
                    .companionCoverageInsufficient,
                    message: "scroll companion対応率が物理実測下限を下回ります。paired=\(pairs.count) pairableScroll=\(pairableScrollEvents.count) minimum=\(coverage.paired)/\(coverage.pairableScroll)"
                )
            )
        }

        return CompanionAnalysis(
            companionCount: companionEvents.count,
            pairs: pairs
        )
    }

    func validateCompanionFields(
        _ event: SemanticEvent,
        contract: TrackpadScrollMomentumContractFixture.ScrollCompanionContract,
        issues: inout [TrackpadScrollMomentumContractIssue]
    ) {
        for (fieldText, expected) in contract.constantRawFields {
            guard let field = Int(fieldText),
                  event.rawFields[field]?.integerValue == expected
            else {
                issues.append(
                    issue(
                        .companionFieldMismatch,
                        captureIndex: event.captureIndex,
                        message: "companion constant raw fieldが一致しません。field=\(fieldText) expected=\(expected)"
                    )
                )
                continue
            }
        }
        validateMotionAliases(
            event,
            doubleFields: contract.xMotionDoubleFields,
            floatBitFields: contract.xMotionFloatBitFields,
            axis: "x",
            issues: &issues
        )
        validateMotionAliases(
            event,
            doubleFields: contract.yMotionDoubleFields,
            floatBitFields: contract.yMotionFloatBitFields,
            axis: "y",
            issues: &issues
        )
    }

    func validateMotionAliases(
        _ event: SemanticEvent,
        doubleFields: [Int],
        floatBitFields: [Int],
        axis: String,
        issues: inout [TrackpadScrollMomentumContractIssue]
    ) {
        let doubles = doubleFields.compactMap { event.rawFields[$0]?.doubleValue }
        guard doubles.count == doubleFields.count,
              let expected = doubles.first,
              doubles.allSatisfy({ $0.bitPattern == expected.bitPattern })
        else {
            issues.append(
                issue(
                    .companionFieldMismatch,
                    captureIndex: event.captureIndex,
                    message: "companion \(axis) motion double fieldsが同じ値ではありません。fields=\(doubleFields)"
                )
            )
            return
        }
        for field in floatBitFields {
            guard let integer = event.rawFields[field]?.integerValue else {
                issues.append(
                    issue(
                        .companionFieldMismatch,
                        captureIndex: event.captureIndex,
                        message: "companion \(axis) motion Float32 bit aliasがありません。field=\(field)"
                    )
                )
                continue
            }
            let floatValue = Float(bitPattern: UInt32(truncatingIfNeeded: integer))
            if Double(floatValue).bitPattern != expected.bitPattern {
                issues.append(
                    issue(
                        .companionFieldMismatch,
                        captureIndex: event.captureIndex,
                        message: "companion \(axis) motion Float32 bit aliasがdouble fieldと一致しません。field=\(field)"
                    )
                )
            }
        }
    }

    func validateTimestamp(
        _ event: SemanticEvent,
        active: ActiveLifecycle,
        family: String,
        issues: inout [TrackpadScrollMomentumContractIssue]
    ) {
        if event.timestamp < active.lastTimestamp {
            issues.append(
                issue(
                    .lifecycleTimestampRegression,
                    captureIndex: event.captureIndex,
                    message: "同一\(family) lifecycle内でtype 22 timestampが逆行しました。previous=\(active.lastTimestamp) actual=\(event.timestamp)"
                )
            )
        }
    }

    func validateTerminalDeltas(
        _ event: SemanticEvent,
        family: String,
        issues: inout [TrackpadScrollMomentumContractIssue]
    ) {
        let integerFields = ["scrollDeltaX", "scrollDeltaY", "scrollDeltaZ"]
        let doubleFields = [
            ("scrollFixedDeltaX", "scrollFixedDeltaXBitPattern"),
            ("scrollFixedDeltaY", "scrollFixedDeltaYBitPattern"),
            ("scrollFixedDeltaZ", "scrollFixedDeltaZBitPattern"),
            ("scrollPointDeltaX", "scrollPointDeltaXBitPattern"),
            ("scrollPointDeltaY", "scrollPointDeltaYBitPattern"),
            ("scrollPointDeltaZ", "scrollPointDeltaZBitPattern")
        ]
        let invalidIntegers = integerFields.filter { event.integer($0) != 0 }
        let invalidDoubles = doubleFields.compactMap { valueField, bitPatternField -> String? in
            guard event.double(valueField) == 0,
                  event.unsignedInteger(bitPatternField) == Double(0).bitPattern
            else {
                return valueField
            }
            return nil
        }
        if !invalidIntegers.isEmpty || !invalidDoubles.isEmpty {
            issues.append(
                issue(
                    .terminalDeltaMismatch,
                    captureIndex: event.captureIndex,
                    message: "\(family) terminalのnamed delta 9種が正のzeroではありません。fields=\((invalidIntegers + invalidDoubles).joined(separator: ","))"
                )
            )
        }
    }

    func invalidScrollTransition(
        _ event: SemanticEvent,
        phase: Int64
    ) -> TrackpadScrollMomentumContractIssue {
        issue(
            .invalidScrollTransition,
            captureIndex: event.captureIndex,
            message: "scroll phase遷移が1 -> 2* -> 4契約に一致しません。phase=\(phase)"
        )
    }

    func invalidMomentumTransition(
        _ event: SemanticEvent,
        phase: Int64
    ) -> TrackpadScrollMomentumContractIssue {
        issue(
            .invalidMomentumTransition,
            captureIndex: event.captureIndex,
            message: "momentum phase遷移が1 -> 2* -> 3契約に一致しません。phase=\(phase)"
        )
    }

    func issue(
        _ code: TrackpadScrollMomentumContractIssueCode,
        captureIndex: UInt64? = nil,
        message: String
    ) -> TrackpadScrollMomentumContractIssue {
        TrackpadScrollMomentumContractIssue(
            code: code,
            captureIndex: captureIndex,
            message: message
        )
    }

    func absoluteDifference(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }
}

private struct SemanticEvent {
    struct RawField {
        var integerValue: Int64?
        var doubleValue: Double?
        var doubleBitPattern: UInt64?
    }

    var captureIndex: UInt64
    var timestamp: UInt64
    var typeRaw: Int
    var topLevel: LosslessJSONObject
    var rawFields: [Int: RawField]

    init?(document: TrackpadDriverEventDocument) {
        let topLevel = document.rawTopLevelObject
        guard let captureIndex = topLevel["captureIndex"]?.uint64Value,
              let timestamp = topLevel["timestamp"]?.uint64Value,
              let typeRawValue = topLevel["typeRaw"]?.int64Value,
              let typeRaw = Int(exactly: typeRawValue)
        else {
            return nil
        }
        var rawFields: [Int: RawField] = [:]
        for value in document.rawFields {
            guard let object = value.objectValue,
                  let numberValue = object["fieldNumber"]?.int64Value,
                  let number = Int(exactly: numberValue)
            else {
                return nil
            }
            rawFields[number] = RawField(
                integerValue: object["integerValue"]?.int64Value,
                doubleValue: object["doubleValue"]?.finiteDoubleValue,
                doubleBitPattern: object["doubleBitPattern"]?.uint64Value
            )
        }
        self.captureIndex = captureIndex
        self.timestamp = timestamp
        self.typeRaw = typeRaw
        self.topLevel = topLevel
        self.rawFields = rawFields
    }

    func integer(_ field: String) -> Int64? {
        topLevel[field]?.int64Value
    }

    func unsignedInteger(_ field: String) -> UInt64? {
        topLevel[field]?.uint64Value
    }

    func double(_ field: String) -> Double? {
        topLevel[field]?.finiteDoubleValue
    }
}
