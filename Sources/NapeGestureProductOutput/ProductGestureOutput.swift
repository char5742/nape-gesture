import Darwin
import Foundation
import NapeGestureCore

public struct VerifiedProductGestureOutputContract: Equatable, Sendable {
    public let contractID: String
    public let schemaVersion: Int
    public let fixtureID: String
    public let fixtureSHA256: String
    public let osVersion: String
    public let osBuild: String

    init?(
        contractID: String,
        schemaVersion: Int,
        fixtureID: String,
        fixtureSHA256: String,
        osVersion: String,
        osBuild: String
    ) {
        guard schemaVersion > 0,
              Self.isNotBlank(contractID),
              Self.isNotBlank(fixtureID),
              Self.isSHA256(fixtureSHA256),
              Self.isNotBlank(osVersion),
              Self.isNotBlank(osBuild)
        else {
            return nil
        }

        self.contractID = contractID
        self.schemaVersion = schemaVersion
        self.fixtureID = fixtureID
        self.fixtureSHA256 = fixtureSHA256.lowercased()
        self.osVersion = osVersion
        self.osBuild = osBuild
    }

    private static func isNotBlank(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
        }
    }
}

public struct ProductGestureOutputSystemIdentity: Equatable, Sendable {
    public let osVersion: String
    public let osBuild: String

    public static func current() -> ProductGestureOutputSystemIdentity? {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        guard let osBuild = currentOperatingSystemBuild() else {
            return nil
        }

        return ProductGestureOutputSystemIdentity(
            osVersion: osVersion,
            osBuild: osBuild
        )
    }

    public init?(osVersion: String, osBuild: String) {
        guard !osVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !osBuild.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        self.osVersion = osVersion
        self.osBuild = osBuild
    }

    private static func currentOperatingSystemBuild() -> String? {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname("kern.osversion", bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else {
            return nil
        }

        return buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return nil
            }
            let osBuild = String(cString: baseAddress)
            return osBuild.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : osBuild
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
    public enum Status: String, Equatable, Sendable {
        case supported
        case unsupported
        case contractMismatch
    }

    public let status: Status
    public let contract: VerifiedProductGestureOutputContract?
    public let supportedFamilies: Set<TrackpadOutputEventFamily>
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
            reason: reason
        )
    }

    public static func validated(
        fixtureData: Data,
        systemIdentity: ProductGestureOutputSystemIdentity? = .current()
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
        guard let contract = VerifiedProductGestureOutputContract(
            contractID: fixture.contractID,
            schemaVersion: fixture.schemaVersion,
            fixtureID: fixture.fixtureID,
            fixtureSHA256: document.fixtureSHA256,
            osVersion: fixture.osVersion,
            osBuild: fixture.osBuild
        ) else {
            return contractMismatch(
                contract: nil,
                reason: "検証済みfixtureからproduct output contract identityを構成できません。"
            )
        }

        guard let systemIdentity else {
            return contractMismatch(
                contract: contract,
                reason: "現在のmacOS buildをkern.osversionから取得できないため、contractを検証できません。"
            )
        }

        guard contract.osVersion == systemIdentity.osVersion,
              contract.osBuild == systemIdentity.osBuild
        else {
            return contractMismatch(
                contract: contract,
                reason: "contractの対象OS (version \(contract.osVersion), build \(contract.osBuild)) "
                    + "と現在のOS (version \(systemIdentity.osVersion), build \(systemIdentity.osBuild)) が一致しません。"
            )
        }

        return ProductGestureOutputCapability(
            status: .supported,
            contract: contract,
            supportedFamilies: Set(TrackpadOutputEventFamily.allCases),
            reason: nil
        )
    }

    private init(
        status: Status,
        contract: VerifiedProductGestureOutputContract?,
        supportedFamilies: Set<TrackpadOutputEventFamily>,
        reason: String?
    ) {
        self.status = status
        self.contract = contract
        self.supportedFamilies = supportedFamilies
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
            reason: reason
        )
    }
}

public struct ProductGestureOutputResult: Equatable, Sendable {
    public private(set) var generatedEventCount: Int
    public private(set) var failedEventCreationCount: Int
    public private(set) var failure: ProductGestureOutputFailure?

    public init(
        generatedEventCount: Int,
        failedEventCreationCount: Int,
        failure: ProductGestureOutputFailure? = nil
    ) {
        let hasInvalidCount = generatedEventCount < 0 || failedEventCreationCount < 0
        self.generatedEventCount = max(generatedEventCount, 0)
        self.failedEventCreationCount = max(failedEventCreationCount, 0)
        self.failure = failure ?? ((hasInvalidCount || self.failedEventCreationCount > 0) ? .eventCreationFailed : nil)
    }

    public static func rejected(_ failure: ProductGestureOutputFailure) -> ProductGestureOutputResult {
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
        lengths.contains(value.count) && value.unicodeScalars.allSatisfy { scalar in
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
