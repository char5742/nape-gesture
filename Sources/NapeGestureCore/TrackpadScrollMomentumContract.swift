import Foundation

public struct TrackpadScrollMomentumContractFixture: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public struct ReferenceLogger: Codable, Equatable, Sendable {
        public var repoHeadSHA: String
        public var executableSHA256: String
    }

    public struct SourceCapture: Codable, Equatable, Sendable {
        public var scenarioID: String
        public var sourceFile: String
        public var sourceLogSHA256: String
        public var sourceEventCount: Int
        public var contractPrefixEventCount: Int
        public var analysisStartCaptureIndex: UInt64
        public var captureStartedAt: String
        public var captureCompletedAt: String
    }

    public struct CommonContract: Codable, Equatable, Sendable {
        public var typeRawField: Int
        public var timestampRawField: Int
    }

    public struct ScrollContract: Codable, Equatable, Sendable {
        public struct PhaseValues: Codable, Equatable, Sendable {
            public var mayBegin: Int64
            public var began: Int64
            public var changed: Int64
            public var ended: Int64
        }

        public var eventTypeRaw: Int
        public var continuousRawField: Int
        public var continuousValue: Int64
        public var phaseRawField: Int
        public var phaseValues: PhaseValues
        public var terminalNamedDeltasRequirePositiveZero: Bool
        public var requiresCompletedLifecycle: Bool
        public var type22TimestampNondecreasingWithinLifecycle: Bool
    }

    public struct MomentumContract: Codable, Equatable, Sendable {
        public struct PhaseValues: Codable, Equatable, Sendable {
            public var inactive: Int64
            public var began: Int64
            public var continued: Int64
            public var ended: Int64
        }

        public var phaseRawField: Int
        public var phaseValues: PhaseValues
        public var scrollAndMomentumPhasesAreMutuallyExclusive: Bool
        public var beginsAfterScrollEnded: Bool
        public var terminalNamedDeltasRequirePositiveZero: Bool
        public var requiresCompletedLifecycle: Bool
        public var type22TimestampNondecreasingWithinLifecycle: Bool
    }

    public struct ScrollCompanionContract: Codable, Equatable, Sendable {
        public struct PairingCoverage: Codable, Equatable, Sendable {
            public var paired: Int
            public var pairableScroll: Int
        }

        public struct AssociationRule: Codable, Equatable, Sendable {
            public var preserveOrder: Bool
            public var phaseMustMatch: Bool
            public var maximumCaptureIndexDistance: UInt64
            public var candidateSelection: String
            public var unmatchedCompanionAllowed: Bool
            public var unmatchedScrollAllowed: Bool
            public var requiredMatchedScrollPhaseValues: [Int64]
            public var allowedUnmatchedScrollPhaseValues: [Int64]
            public var minimumPairingCoverage: PairingCoverage
            public var requiresScrollTimestampEquality: Bool
            public var requiresFixedCaptureIndexDelta: Bool
        }

        public struct ReferenceStatistics: Codable, Equatable, Sendable {
            public var pairedSampleCount: Int
            public var pairableScrollSampleCount: Int
            public var captureIndexDeltaValues: [Int64]
            public var anyTimestampEqualToScrollWheel: Bool
        }

        public var eventTypeRaw: Int
        public var classifierRawField: Int
        public var classifierValue: Int64
        public var envelopeClassifierValue: Int64
        public var phaseRawField: Int
        public var xMotionDoubleFields: [Int]
        public var xMotionFloatBitFields: [Int]
        public var yMotionDoubleFields: [Int]
        public var yMotionFloatBitFields: [Int]
        public var constantRawFields: [String: Int64]
        public var envelopeMustImmediatelyPrecede: Bool
        public var envelopeTimestampMustMatch: Bool
        public var associationRule: AssociationRule
        public var referenceStatistics: ReferenceStatistics
    }

    public var schemaVersion: Int
    public var fixtureID: String
    public var contractID: String
    public var status: String
    public var scope: String
    public var osVersion: String
    public var osBuild: String
    public var referenceDeviceLabel: String
    public var captureOrderField: String
    public var referenceLogger: ReferenceLogger
    public var sourceCaptures: [SourceCapture]
    public var supportedScenarioIDs: [String]
    public var common: CommonContract
    public var scroll: ScrollContract
    public var momentum: MomentumContract
    public var scrollCompanion: ScrollCompanionContract
}

public enum TrackpadScrollMomentumContractIssueCode: String, Codable, Equatable, Sendable {
    case fixtureReadFailed = "fixture_read_failed"
    case invalidFixtureJSON = "invalid_fixture_json"
    case typedFixtureDecodeFailed = "typed_fixture_decode_failed"
    case unregisteredFixture = "unregistered_fixture"
    case fixtureRegistrationMismatch = "fixture_registration_mismatch"
    case invalidContractDefinition = "invalid_contract_definition"
    case blockedByPrerequisite = "blocked_by_prerequisite"
    case unsupportedEvidenceKind = "unsupported_evidence_kind"
    case missingScenario = "missing_scenario"
    case scenarioNotConfirmed = "scenario_not_confirmed"
    case osVersionMismatch = "os_version_mismatch"
    case osBuildMismatch = "os_build_mismatch"
    case manifestDocumentMismatch = "manifest_document_mismatch"
    case captureIndexMismatch = "capture_index_mismatch"
    case physicalReferenceMismatch = "physical_reference_mismatch"
    case emptyEventSequence = "empty_event_sequence"
    case rawFieldMissing = "raw_field_missing"
    case rawTypeMismatch = "raw_type_mismatch"
    case rawTimestampMismatch = "raw_timestamp_mismatch"
    case continuousMismatch = "continuous_mismatch"
    case namedFieldMismatch = "named_field_mismatch"
    case simultaneousPhases = "simultaneous_phases"
    case emptyScrollEvent = "empty_scroll_event"
    case unknownScrollPhase = "unknown_scroll_phase"
    case unknownMomentumPhase = "unknown_momentum_phase"
    case invalidScrollTransition = "invalid_scroll_transition"
    case missingScrollTerminal = "missing_scroll_terminal"
    case missingScrollLifecycle = "missing_scroll_lifecycle"
    case invalidMomentumTransition = "invalid_momentum_transition"
    case missingMomentumTerminal = "missing_momentum_terminal"
    case missingMomentumLifecycle = "missing_momentum_lifecycle"
    case momentumWithoutScrollTerminal = "momentum_without_scroll_terminal"
    case lifecycleTimestampRegression = "lifecycle_timestamp_regression"
    case terminalDeltaMismatch = "terminal_delta_mismatch"
    case companionEnvelopeMissing = "companion_envelope_missing"
    case companionEnvelopeMismatch = "companion_envelope_mismatch"
    case companionFieldMismatch = "companion_field_mismatch"
    case unconfirmedGestureEvent = "unconfirmed_gesture_event"
    case companionUnmatched = "companion_unmatched"
    case requiredCompanionMissing = "required_companion_missing"
    case companionCoverageInsufficient = "companion_coverage_insufficient"
}

public struct TrackpadScrollMomentumContractIssue: Codable, Equatable, Sendable {
    public var code: TrackpadScrollMomentumContractIssueCode
    public var captureIndex: UInt64?
    public var message: String

    public init(
        code: TrackpadScrollMomentumContractIssueCode,
        captureIndex: UInt64? = nil,
        message: String
    ) {
        self.code = code
        self.captureIndex = captureIndex
        self.message = message
    }
}

public struct TrackpadScrollMomentumContractDocument: Equatable, Sendable {
    public let fixture: TrackpadScrollMomentumContractFixture
    public let fixtureSHA256: String
    public let rawTopLevelObject: LosslessJSONObject
    public let unknownTopLevelFields: LosslessJSONObject

    init(
        fixture: TrackpadScrollMomentumContractFixture,
        fixtureSHA256: String,
        rawTopLevelObject: LosslessJSONObject,
        unknownTopLevelFields: LosslessJSONObject
    ) {
        self.fixture = fixture
        self.fixtureSHA256 = fixtureSHA256
        self.rawTopLevelObject = rawTopLevelObject
        self.unknownTopLevelFields = unknownTopLevelFields
    }
}

public struct TrackpadScrollMomentumContractDocumentReadReport: Equatable, Sendable {
    public var passed: Bool
    public var document: TrackpadScrollMomentumContractDocument?
    public var issues: [TrackpadScrollMomentumContractIssue]

    public init(
        document: TrackpadScrollMomentumContractDocument?,
        issues: [TrackpadScrollMomentumContractIssue]
    ) {
        self.document = document
        self.issues = issues
        passed = issues.isEmpty && document != nil
    }
}

public enum TrackpadScrollMomentumContractDocumentReader {
    public static var registeredFixtureCount: Int {
        registrations.count
    }

    public static func read(data: Data) -> TrackpadScrollMomentumContractDocumentReadReport {
        let rawObject: LosslessJSONObject
        do {
            rawObject = try StrictJSONDocumentParser.parseObject(data: data)
        } catch {
            return TrackpadScrollMomentumContractDocumentReadReport(
                document: nil,
                issues: [
                    TrackpadScrollMomentumContractIssue(
                        code: .invalidFixtureJSON,
                        message: "scroll / momentum contract fixtureを厳格解析できません: \(error.localizedDescription)"
                    )
                ]
            )
        }

        let fixture: TrackpadScrollMomentumContractFixture
        do {
            fixture = try JSONDecoder().decode(
                TrackpadScrollMomentumContractFixture.self,
                from: data
            )
        } catch {
            return TrackpadScrollMomentumContractDocumentReadReport(
                document: nil,
                issues: [
                    TrackpadScrollMomentumContractIssue(
                        code: .typedFixtureDecodeFailed,
                        message: "scroll / momentum contract fixtureを型decodeできません: \(error.localizedDescription)"
                    )
                ]
            )
        }

        let fixtureSHA256 = TrackpadDriverEventCaptureManifest.sha256HexDigest(of: data)
        let document = TrackpadScrollMomentumContractDocument(
            fixture: fixture,
            fixtureSHA256: fixtureSHA256,
            rawTopLevelObject: rawObject,
            unknownTopLevelFields: rawObject.filteringKeys {
                !knownTopLevelFields.contains($0)
            }
        )
        var issues = validateRegistration(document)
        issues.append(contentsOf: validateDefinition(fixture))
        return TrackpadScrollMomentumContractDocumentReadReport(
            document: document,
            issues: issues
        )
    }

    public static func validate(
        document: TrackpadScrollMomentumContractDocument
    ) -> [TrackpadScrollMomentumContractIssue] {
        validateRegistration(document) + validateDefinition(document.fixture)
    }
}

private extension TrackpadScrollMomentumContractDocumentReader {
    struct Registration {
        var fixtureID: String
        var contractID: String
        var schemaVersion: Int
        var fixtureSHA256: String
        var osVersion: String
        var osBuild: String
    }

    static let registrations: [String: Registration] = [
        "trackpad-scroll-momentum-25F80-v1": Registration(
            fixtureID: "trackpad-scroll-momentum-25F80-v1",
            contractID: "trackpad-scroll-momentum-v1",
            schemaVersion: 1,
            fixtureSHA256: "8e2a1841ef23a47fcb274c1c8e7c7c39be43e8ab7c8792caf2cd874242a61294",
            osVersion: "26.5.1",
            osBuild: "25F80"
        )
    ]

    static let knownTopLevelFields: Set<String> = [
        "schemaVersion",
        "fixtureID",
        "contractID",
        "status",
        "scope",
        "osVersion",
        "osBuild",
        "referenceDeviceLabel",
        "captureOrderField",
        "referenceLogger",
        "sourceCaptures",
        "supportedScenarioIDs",
        "common",
        "scroll",
        "momentum",
        "scrollCompanion"
    ]

    static func validateRegistration(
        _ document: TrackpadScrollMomentumContractDocument
    ) -> [TrackpadScrollMomentumContractIssue] {
        let fixture = document.fixture
        guard let registration = registrations[fixture.fixtureID] else {
            return [
                TrackpadScrollMomentumContractIssue(
                    code: .unregisteredFixture,
                    message: "fixture IDは登録されていません: \(fixture.fixtureID)"
                )
            ]
        }
        guard registration.fixtureID == fixture.fixtureID,
              registration.contractID == fixture.contractID,
              registration.schemaVersion == fixture.schemaVersion,
              registration.fixtureSHA256 == document.fixtureSHA256,
              registration.osVersion == fixture.osVersion,
              registration.osBuild == fixture.osBuild
        else {
            return [
                TrackpadScrollMomentumContractIssue(
                    code: .fixtureRegistrationMismatch,
                    message: "fixture bytes、SHA-256、schema、contract ID、OS identityが登録値と一致しません。"
                )
            ]
        }
        return []
    }

    static func validateDefinition(
        _ fixture: TrackpadScrollMomentumContractFixture
    ) -> [TrackpadScrollMomentumContractIssue] {
        var problems: [String] = []
        let maximumRawField = TrackpadDriverEventLog.maximumRawFieldNumber
        let validField: (Int) -> Bool = { (0...maximumRawField).contains($0) }

        if fixture.schemaVersion != TrackpadScrollMomentumContractFixture.currentSchemaVersion {
            problems.append("schemaVersionが現行値ではありません。")
        }
        if fixture.status != "confirmed" || fixture.scope != "scroll-momentum" {
            problems.append("fixture scopeが確定済みscroll / momentumに限定されていません。")
        }
        if fixture.captureOrderField != "captureIndex" {
            problems.append("capture順の正本がcaptureIndexではありません。")
        }
        if !hasContent(fixture.referenceDeviceLabel)
            || !isCanonicalGitObjectID(fixture.referenceLogger.repoHeadSHA)
            || !isCanonicalSHA256(fixture.referenceLogger.executableSHA256)
        {
            problems.append("reference deviceまたはlogger identityが不正です。")
        }

        let supportedScenarios = Set(fixture.supportedScenarioIDs)
        let sourceScenarios = Set(fixture.sourceCaptures.map(\.scenarioID))
        if supportedScenarios.isEmpty
            || supportedScenarios.count != fixture.supportedScenarioIDs.count
            || sourceScenarios.count != fixture.sourceCaptures.count
            || supportedScenarios != sourceScenarios
        {
            problems.append("supported scenarioとsource captureの対応が一意ではありません。")
        }
        for source in fixture.sourceCaptures {
            if !isCanonicalSHA256(source.sourceLogSHA256)
                || source.sourceEventCount < source.contractPrefixEventCount
                || source.contractPrefixEventCount <= 0
                || source.analysisStartCaptureIndex >= UInt64(source.contractPrefixEventCount)
                || wallClock(source.captureStartedAt) == nil
                || wallClock(source.captureCompletedAt) == nil
                || wallClock(source.captureStartedAt)! > wallClock(source.captureCompletedAt)!
            {
                problems.append("source capture identityまたは解析境界が不正です: \(source.scenarioID)")
            }
        }

        let scroll = fixture.scroll
        let momentum = fixture.momentum
        let companion = fixture.scrollCompanion
        let allFieldNumbers = [
            fixture.common.typeRawField,
            fixture.common.timestampRawField,
            scroll.continuousRawField,
            scroll.phaseRawField,
            momentum.phaseRawField,
            companion.classifierRawField,
            companion.phaseRawField
        ] + companion.xMotionDoubleFields
            + companion.xMotionFloatBitFields
            + companion.yMotionDoubleFields
            + companion.yMotionFloatBitFields
        if !allFieldNumbers.allSatisfy(validField) {
            problems.append("contractにraw field 0...255外の番号があります。")
        }
        if companion.constantRawFields.keys.contains(where: {
            guard let field = Int($0) else { return true }
            return !validField(field)
        }) {
            problems.append("companion constant raw field番号が不正です。")
        }

        let scrollPhases = [
            scroll.phaseValues.mayBegin,
            scroll.phaseValues.began,
            scroll.phaseValues.changed,
            scroll.phaseValues.ended
        ]
        let momentumPhases = [
            momentum.phaseValues.inactive,
            momentum.phaseValues.began,
            momentum.phaseValues.continued,
            momentum.phaseValues.ended
        ]
        if Set(scrollPhases).count != scrollPhases.count
            || Set(momentumPhases).count != momentumPhases.count
            || momentum.phaseValues.inactive != 0
        {
            problems.append("scrollまたはmomentum phase値が一意ではありません。")
        }
        if !scroll.terminalNamedDeltasRequirePositiveZero
            || !scroll.requiresCompletedLifecycle
            || !scroll.type22TimestampNondecreasingWithinLifecycle
            || !momentum.scrollAndMomentumPhasesAreMutuallyExclusive
            || !momentum.beginsAfterScrollEnded
            || !momentum.terminalNamedDeltasRequirePositiveZero
            || !momentum.requiresCompletedLifecycle
            || !momentum.type22TimestampNondecreasingWithinLifecycle
        {
            problems.append("確定済みlifecycleまたはterminal要件が無効化されています。")
        }

        let rule = companion.associationRule
        let coverage = rule.minimumPairingCoverage
        if !companion.envelopeMustImmediatelyPrecede
            || !companion.envelopeTimestampMustMatch
            || !rule.preserveOrder
            || !rule.phaseMustMatch
            || rule.maximumCaptureIndexDistance == 0
            || rule.candidateSelection
                != "minimum-absolute-timestamp-difference-then-capture-index-distance"
            || rule.unmatchedCompanionAllowed
            || !rule.unmatchedScrollAllowed
            || rule.requiresScrollTimestampEquality
            || rule.requiresFixedCaptureIndexDelta
            || coverage.paired <= 0
            || coverage.pairableScroll <= 0
            || coverage.paired > coverage.pairableScroll
        {
            problems.append("scroll companion association ruleが対応済み実測規則ではありません。")
        }
        let allowedScrollPhases = Set(scrollPhases)
        if !Set(rule.requiredMatchedScrollPhaseValues).isSubset(of: allowedScrollPhases)
            || !Set(rule.allowedUnmatchedScrollPhaseValues).isSubset(of: allowedScrollPhases)
            || !Set(rule.requiredMatchedScrollPhaseValues).isDisjoint(
                with: Set(rule.allowedUnmatchedScrollPhaseValues)
            )
        {
            problems.append("companionのrequired / unmatched phase集合が不正です。")
        }

        return problems.map {
            TrackpadScrollMomentumContractIssue(
                code: .invalidContractDefinition,
                message: $0
            )
        }
    }

    static func hasContent(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    static func isCanonicalGitObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    static func wallClock(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
