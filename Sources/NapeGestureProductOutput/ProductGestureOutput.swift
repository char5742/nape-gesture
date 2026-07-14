import Foundation
import NapeGestureCore

public struct VerifiedProductGestureOutputContract: Equatable, Sendable {
    public let contractID: String
    public let schemaVersion: Int
    public let fixtureID: String
    public let fixtureSHA256: String
    public let sourceOSVersion: String
    public let sourceOSBuild: String

    init?(
        contractID: String,
        schemaVersion: Int,
        fixtureID: String,
        fixtureSHA256: String,
        sourceOSVersion: String,
        sourceOSBuild: String
    ) {
        guard schemaVersion > 0,
            Self.isNotBlank(contractID),
            Self.isNotBlank(fixtureID),
            Self.isSHA256(fixtureSHA256),
            Self.isNotBlank(sourceOSVersion),
            Self.isNotBlank(sourceOSBuild)
        else {
            return nil
        }

        self.contractID = contractID
        self.schemaVersion = schemaVersion
        self.fixtureID = fixtureID
        self.fixtureSHA256 = fixtureSHA256.lowercased()
        self.sourceOSVersion = sourceOSVersion
        self.sourceOSBuild = sourceOSBuild
    }

    private static func isNotBlank(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy { scalar in
                CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
            }
    }
}

public enum ProductGestureOutputFailure: String, Error, Equatable, Sendable {
    case unsupported
    case contractMismatch
    case invalidSession
    case eventCreationFailed
    case eventPostFailed
}

public struct ProductGestureOutputCapability: Equatable, Sendable {
    public static let defaultConfirmedFamilies: Set<TrackpadOutputEventFamily> = [.scroll]
    public static let defaultTrialFamilies: Set<TrackpadOutputEventFamily> = [
        .dockSwipe,
        .dockSwipePinch,
    ]
    public static let runtimeFamilies = defaultConfirmedFamilies.union(defaultTrialFamilies)

    public enum Status: String, Equatable, Sendable {
        case supported
        case unsupported
        case contractMismatch
    }

    public let status: Status
    public let contract: VerifiedProductGestureOutputContract?
    public let supportedFamilies: Set<TrackpadOutputEventFamily>
    public let confirmedFamilies: Set<TrackpadOutputEventFamily>
    public let trialFamilies: Set<TrackpadOutputEventFamily>
    public let reason: String?

    public var isSupported: Bool {
        status == .supported
    }

    public var failure: ProductGestureOutputFailure? {
        switch status {
        case .supported:
            nil
        case .unsupported:
            .unsupported
        case .contractMismatch:
            .contractMismatch
        }
    }

    public static var registeredFixtureCount: Int {
        TrackpadScrollMomentumContractDocumentReader.registeredFixtureCount
    }

    /// 既存のfail-closed判定を維持するため、contractMismatchの理由も返します。
    public var unsupportedReason: String? {
        return reason
    }

    public static func unsupported(reason: String) -> ProductGestureOutputCapability {
        ProductGestureOutputCapability(
            status: .unsupported,
            contract: nil,
            supportedFamilies: [],
            confirmedFamilies: [],
            trialFamilies: [],
            reason: reason
        )
    }

    public static func validated(
        fixtureData: Data
    ) -> ProductGestureOutputCapability {
        let report = TrackpadScrollMomentumContractDocumentReader.read(data: fixtureData)
        guard report.passed, let document = report.document else {
            let details = report.issues.map(\.message).joined(separator: " ")
            return contractMismatch(
                contract: nil,
                reason: details.isEmpty
                    ? "scroll / momentum contract fixtureを検証できません。"
                    : details
            )
        }

        let fixture = document.fixture
        guard
            let contract = VerifiedProductGestureOutputContract(
                contractID: fixture.contractID,
                schemaVersion: fixture.schemaVersion,
                fixtureID: fixture.fixtureID,
                fixtureSHA256: document.fixtureSHA256,
                sourceOSVersion: fixture.osVersion,
                sourceOSBuild: fixture.osBuild
            )
        else {
            return contractMismatch(
                contract: nil,
                reason: "検証済みfixtureからproduct output contract identityを構成できません。"
            )
        }

        return ProductGestureOutputCapability(
            status: .supported,
            contract: contract,
            supportedFamilies: runtimeFamilies,
            confirmedFamilies: defaultConfirmedFamilies,
            trialFamilies: defaultTrialFamilies,
            reason: nil
        )
    }

    private init(
        status: Status,
        contract: VerifiedProductGestureOutputContract?,
        supportedFamilies: Set<TrackpadOutputEventFamily>,
        confirmedFamilies: Set<TrackpadOutputEventFamily>,
        trialFamilies: Set<TrackpadOutputEventFamily>,
        reason: String?
    ) {
        self.status = status
        self.contract = contract
        self.supportedFamilies = supportedFamilies
        self.confirmedFamilies = confirmedFamilies
        self.trialFamilies = trialFamilies
        self.reason = reason
    }

    static func contractMismatch(
        contract: VerifiedProductGestureOutputContract?,
        reason: String
    ) -> ProductGestureOutputCapability {
        ProductGestureOutputCapability(
            status: .contractMismatch,
            contract: contract,
            supportedFamilies: [],
            confirmedFamilies: [],
            trialFamilies: [],
            reason: reason
        )
    }
}

public struct ProductGestureOutputResult: Equatable, Sendable {
    public private(set) var generatedEventCount: Int
    public private(set) var failedEventCreationCount: Int
    public private(set) var failure: ProductGestureOutputFailure?
    public private(set) var failureDetails: String?

    public init(
        generatedEventCount: Int,
        failedEventCreationCount: Int,
        failure: ProductGestureOutputFailure? = nil,
        failureDetails: String? = nil
    ) {
        let hasInvalidCount = generatedEventCount < 0 || failedEventCreationCount < 0
        self.generatedEventCount = max(generatedEventCount, 0)
        self.failedEventCreationCount = max(failedEventCreationCount, 0)
        self.failure =
            failure
            ?? ((hasInvalidCount || self.failedEventCreationCount > 0) ? .eventCreationFailed : nil)
        self.failureDetails = failureDetails
    }

    public static func rejected(_ failure: ProductGestureOutputFailure)
        -> ProductGestureOutputResult
    {
        ProductGestureOutputResult(
            generatedEventCount: 0,
            failedEventCreationCount: 0,
            failure: failure
        )
    }
}

public struct ProductGestureOutputTraceContext: Equatable, Sendable {
    public let captureRunToken: String
    public let scenarioID: String
    public let repoHeadSHA: String
    public let executableSHA256: String

    public init?(
        captureRunToken: String,
        scenarioID: String,
        repoHeadSHA: String,
        executableSHA256: String
    ) {
        guard UUID(uuidString: captureRunToken)?.uuidString.lowercased() == captureRunToken,
            !scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            Self.isCanonicalHex(repoHeadSHA, lengths: [40, 64]),
            Self.isCanonicalHex(executableSHA256, lengths: [64])
        else {
            return nil
        }
        self.captureRunToken = captureRunToken
        self.scenarioID = scenarioID
        self.repoHeadSHA = repoHeadSHA
        self.executableSHA256 = executableSHA256
    }

    private static func isCanonicalHex(_ value: String, lengths: Set<Int>) -> Bool {
        lengths.contains(value.count)
            && value.unicodeScalars.allSatisfy { scalar in
                (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
            }
    }
}

public struct ProductGestureOutputPostedEventTrace: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var postIndex: UInt64
    public var sessionID: TrackpadOutputSessionID
    public var family: TrackpadOutputEventFamily
    public var eventTimestamp: UInt64
    public var eventTypeRaw: Int
    public var delivery: TrackpadOutputDeliveryKind
    public var eventKind: TrackpadOutputProvenanceEventKind
    public var captureRunToken: String
    public var scenarioID: String
    public var repoHeadSHA: String
    public var executableSHA256: String
    public var prePostTargetProcessSerialNumber: Int64
    public var prePostTargetUnixProcessID: Int64

    public init(
        schemaVersion: Int = currentSchemaVersion,
        postIndex: UInt64,
        sessionID: TrackpadOutputSessionID,
        family: TrackpadOutputEventFamily,
        eventTimestamp: UInt64,
        eventTypeRaw: Int,
        delivery: TrackpadOutputDeliveryKind,
        eventKind: TrackpadOutputProvenanceEventKind,
        traceContext: ProductGestureOutputTraceContext,
        prePostTargetProcessSerialNumber: Int64,
        prePostTargetUnixProcessID: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.postIndex = postIndex
        self.sessionID = sessionID
        self.family = family
        self.eventTimestamp = eventTimestamp
        self.eventTypeRaw = eventTypeRaw
        self.delivery = delivery
        self.eventKind = eventKind
        captureRunToken = traceContext.captureRunToken
        scenarioID = traceContext.scenarioID
        repoHeadSHA = traceContext.repoHeadSHA
        executableSHA256 = traceContext.executableSHA256
        self.prePostTargetProcessSerialNumber = prePostTargetProcessSerialNumber
        self.prePostTargetUnixProcessID = prePostTargetUnixProcessID
    }
}

public protocol ProductGestureOutput: AnyObject {
    var capability: ProductGestureOutputCapability { get }

    func supports(_ family: TrackpadOutputEventFamily) -> Bool
    func post(_ event: TrackpadOutputSessionEvent) -> ProductGestureOutputResult
    func reset()
}
