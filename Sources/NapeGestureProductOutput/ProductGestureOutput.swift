import CryptoKit
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

private struct RegisteredProductGestureOutputFixture {
    var contractID: String
    var schemaVersion: Int
    var fixtureID: String
    var fixtureSHA256: String
    var osVersion: String
    var osBuild: String
}

private enum ProductGestureOutputContractRegistry {
    // Issue #122で、repo内fixtureの固定hashと対応OS buildをここへ登録する。
    static let fixtures: [String: RegisteredProductGestureOutputFixture] = [:]
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

    private init(osVersion: String, osBuild: String) {
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

public enum ProductGestureOutputFailure: String, Equatable, Sendable {
    case unsupported
    case contractMismatch
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
        ProductGestureOutputContractRegistry.fixtures.count
    }

    /// 既存のfail-closed判定を維持するため、contractMismatchの理由も返します。
    public var unsupportedReason: String? {
        return reason
    }

    public static func unsupported(reason: String) -> ProductGestureOutputCapability {
        ProductGestureOutputCapability(
            status: .unsupported,
            contract: nil,
            reason: reason
        )
    }

    static func validated(
        contract: VerifiedProductGestureOutputContract,
        fixtureData: Data
    ) -> ProductGestureOutputCapability {
        guard let registered = ProductGestureOutputContractRegistry.fixtures[contract.fixtureID] else {
            return contractMismatch(
                contract: contract,
                reason: "fixture ID \(contract.fixtureID)はproduct output registryへ登録されていません。"
            )
        }

        let actualFixtureSHA256 = SHA256.hash(data: fixtureData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard registered.contractID == contract.contractID,
              registered.schemaVersion == contract.schemaVersion,
              registered.fixtureID == contract.fixtureID,
              registered.fixtureSHA256 == contract.fixtureSHA256,
              registered.osVersion == contract.osVersion,
              registered.osBuild == contract.osBuild,
              actualFixtureSHA256 == registered.fixtureSHA256
        else {
            return contractMismatch(
                contract: contract,
                reason: "fixture内容、hash、schema、contract ID、対象OSのいずれかが登録済みcontractと一致しません。"
            )
        }

        guard let currentSystem = ProductGestureOutputSystemIdentity.current() else {
            return contractMismatch(
                contract: contract,
                reason: "現在のmacOS buildをkern.osversionから取得できないため、contractを検証できません。"
            )
        }

        guard contract.osVersion == currentSystem.osVersion,
              contract.osBuild == currentSystem.osBuild
        else {
            return contractMismatch(
                contract: contract,
                reason: "contractの対象OS (version \(contract.osVersion), build \(contract.osBuild)) "
                    + "と現在のOS (version \(currentSystem.osVersion), build \(currentSystem.osBuild)) が一致しません。"
            )
        }

        return ProductGestureOutputCapability(
            status: .supported,
            contract: contract,
            reason: nil
        )
    }

    private init(
        status: Status,
        contract: VerifiedProductGestureOutputContract?,
        reason: String?
    ) {
        self.status = status
        self.contract = contract
        self.reason = reason
    }

    private static func contractMismatch(
        contract: VerifiedProductGestureOutputContract,
        reason: String
    ) -> ProductGestureOutputCapability {
        ProductGestureOutputCapability(
            status: .contractMismatch,
            contract: contract,
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

public protocol ProductGestureOutput: AnyObject {
    var capability: ProductGestureOutputCapability { get }

    func post(action: GestureAction, command: GestureCommand) -> ProductGestureOutputResult
    func supportsMomentum(for action: GestureAction) -> Bool
    func cancelAll()
}

public final class TrackpadGestureOutputAdapter: ProductGestureOutput {
    public let capability: ProductGestureOutputCapability = .unsupported(
        reason: "このmacOS build用のtrackpad output contractはまだ導出・検証されていません。"
    )

    public init() {}

    public func post(action _: GestureAction, command _: GestureCommand) -> ProductGestureOutputResult {
        .rejected(.unsupported)
    }

    public func supportsMomentum(for _: GestureAction) -> Bool {
        false
    }

    public func cancelAll() {}
}
