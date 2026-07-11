import Darwin
import Foundation

public struct TrackpadDriverEventCaptureReadyRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var ready: Bool
    public var pid: Int32
    public var runToken: String
    public var leaseCreatedAt: String
    public var captureStartedAt: String?
    public var captureDeadlineAt: String?
    public var scenarioID: String?
    public var repoHeadSHA: String?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        ready: Bool,
        pid: Int32,
        runToken: String,
        leaseCreatedAt: Date,
        captureStartedAt: Date?,
        captureDeadlineAt: Date?,
        scenarioID: String?,
        repoHeadSHA: String?
    ) {
        self.schemaVersion = schemaVersion
        self.ready = ready
        self.pid = pid
        self.runToken = runToken
        self.leaseCreatedAt = TrackpadDriverEventCaptureManifest.wallClockString(
            for: leaseCreatedAt
        )
        self.captureStartedAt = captureStartedAt.map {
            TrackpadDriverEventCaptureManifest.wallClockString(for: $0)
        }
        self.captureDeadlineAt = captureDeadlineAt.map {
            TrackpadDriverEventCaptureManifest.wallClockString(for: $0)
        }
        self.scenarioID = scenarioID
        self.repoHeadSHA = repoHeadSHA
    }
}

public struct TrackpadDriverEventCaptureReadyLease: Equatable, Sendable {
    public var path: String
    public var pid: Int32
    public var runToken: String
    public var leaseCreatedAt: Date
    public var scenarioID: String?
    public var repoHeadSHA: String?

    public init(
        path: String,
        pid: Int32,
        runToken: String,
        leaseCreatedAt: Date,
        scenarioID: String?,
        repoHeadSHA: String?
    ) {
        self.path = path
        self.pid = pid
        self.runToken = runToken
        self.leaseCreatedAt = leaseCreatedAt
        self.scenarioID = scenarioID
        self.repoHeadSHA = repoHeadSHA
    }

    public func record(
        ready: Bool,
        captureStartedAt: Date? = nil,
        captureDeadlineAt: Date? = nil
    ) -> TrackpadDriverEventCaptureReadyRecord {
        TrackpadDriverEventCaptureReadyRecord(
            ready: ready,
            pid: pid,
            runToken: runToken,
            leaseCreatedAt: leaseCreatedAt,
            captureStartedAt: captureStartedAt,
            captureDeadlineAt: captureDeadlineAt,
            scenarioID: scenarioID,
            repoHeadSHA: repoHeadSHA
        )
    }
}

public enum TrackpadDriverEventCaptureReadyStoreError: LocalizedError, Equatable, Sendable {
    case parentDirectoryCreationFailed(path: String, details: String)
    case destinationAlreadyReserved(path: String)
    case exclusiveCreationFailed(path: String, errno: Int32)
    case encodingFailed(details: String)
    case writeFailed(path: String, details: String)
    case readFailed(path: String, details: String)
    case ownershipMismatch(path: String)
    case revokeFailed(path: String, errno: Int32, fallback: String)

    public var errorDescription: String? {
        switch self {
        case let .parentDirectoryCreationFailed(path, details):
            return "ready leaseの親directoryを作成できません。path=\(path) details=\(details)"
        case let .destinationAlreadyReserved(path):
            return "ready pathは既存leaseまたはfileに予約されています。新しいtokenを含む別pathを使ってください。path=\(path)"
        case let .exclusiveCreationFailed(path, errorCode):
            return "ready leaseを排他的に作成できません。path=\(path) errno=\(errorCode)"
        case let .encodingFailed(details):
            return "ready recordをencodeできません。details=\(details)"
        case let .writeFailed(path, details):
            return "ready recordを書き込めません。path=\(path) details=\(details)"
        case let .readFailed(path, details):
            return "ready recordを読み込めません。path=\(path) details=\(details)"
        case let .ownershipMismatch(path):
            return "ready leaseのtokenまたはPIDが一致しません。path=\(path)"
        case let .revokeFailed(path, errorCode, fallback):
            return "ready leaseを撤回できません。path=\(path) errno=\(errorCode) fallback=\(fallback)"
        }
    }
}

public struct TrackpadDriverEventCaptureReadyStore: Sendable {
    public init() {}

    public func reserve(
        path: String,
        pid: Int32,
        runToken: String,
        leaseCreatedAt: Date,
        scenarioID: String?,
        repoHeadSHA: String?
    ) throws -> TrackpadDriverEventCaptureReadyLease {
        let url = Self.standardizedFileURL(for: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw TrackpadDriverEventCaptureReadyStoreError.parentDirectoryCreationFailed(
                path: url.deletingLastPathComponent().path,
                details: error.localizedDescription
            )
        }

        let lease = TrackpadDriverEventCaptureReadyLease(
            path: url.path,
            pid: pid,
            runToken: runToken,
            leaseCreatedAt: leaseCreatedAt,
            scenarioID: scenarioID,
            repoHeadSHA: repoHeadSHA
        )
        let data = try Self.encodedData(for: lease.record(ready: false))
        let openResult = url.withUnsafeFileSystemRepresentation { fileSystemPath -> (Int32, Int32) in
            guard let fileSystemPath else {
                return (-1, EINVAL)
            }
            let descriptor = Darwin.open(
                fileSystemPath,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o666)
            )
            return (descriptor, descriptor >= 0 ? 0 : errno)
        }
        guard openResult.0 >= 0 else {
            if openResult.1 == EEXIST {
                throw TrackpadDriverEventCaptureReadyStoreError.destinationAlreadyReserved(
                    path: url.path
                )
            }
            throw TrackpadDriverEventCaptureReadyStoreError.exclusiveCreationFailed(
                path: url.path,
                errno: openResult.1
            )
        }

        let descriptor = openResult.0
        var descriptorIsOpen = true
        var shouldRemoveReservation = true
        defer {
            if descriptorIsOpen {
                _ = Darwin.close(descriptor)
            }
            if shouldRemoveReservation {
                _ = Self.unlink(url)
            }
        }
        try Self.write(data, to: descriptor, path: url.path)
        guard Darwin.fsync(descriptor) == 0 else {
            throw TrackpadDriverEventCaptureReadyStoreError.writeFailed(
                path: url.path,
                details: "fsync errno=\(errno)"
            )
        }
        let closeResult = Darwin.close(descriptor)
        descriptorIsOpen = false
        guard closeResult == 0 else {
            throw TrackpadDriverEventCaptureReadyStoreError.writeFailed(
                path: url.path,
                details: "close errno=\(errno)"
            )
        }
        shouldRemoveReservation = false
        return lease
    }

    public func publish(
        _ lease: TrackpadDriverEventCaptureReadyLease,
        captureStartedAt: Date,
        captureDeadlineAt: Date?
    ) throws -> TrackpadDriverEventCaptureReadyRecord {
        let existingRecord = try Self.readOwnedRecord(for: lease)
        guard !existingRecord.ready else {
            throw TrackpadDriverEventCaptureReadyStoreError.ownershipMismatch(
                path: lease.path
            )
        }
        let readyRecord = lease.record(
            ready: true,
            captureStartedAt: captureStartedAt,
            captureDeadlineAt: captureDeadlineAt
        )
        try Self.writeAtomically(readyRecord, toPath: lease.path)
        return readyRecord
    }

    public func revoke(_ lease: TrackpadDriverEventCaptureReadyLease) throws {
        let url = Self.standardizedFileURL(for: lease.path)
        var invalidated = false
        var invalidationFailure = "none"
        do {
            _ = try Self.readOwnedRecord(for: lease)
            try Self.writeAtomically(lease.record(ready: false), toPath: lease.path)
            invalidated = true
        } catch {
            invalidationFailure = error.localizedDescription
        }

        let unlinkResult = Self.unlink(url)
        if unlinkResult.result == 0 || unlinkResult.errorCode == ENOENT {
            return
        }
        if invalidated {
            return
        }
        throw TrackpadDriverEventCaptureReadyStoreError.revokeFailed(
            path: lease.path,
            errno: unlinkResult.errorCode,
            fallback: invalidationFailure
        )
    }

    public func readRecord(path: String) throws -> TrackpadDriverEventCaptureReadyRecord {
        let url = Self.standardizedFileURL(for: path)
        do {
            return try JSONDecoder().decode(
                TrackpadDriverEventCaptureReadyRecord.self,
                from: Data(contentsOf: url, options: .mappedIfSafe)
            )
        } catch {
            throw TrackpadDriverEventCaptureReadyStoreError.readFailed(
                path: url.path,
                details: "read/decode: \(error.localizedDescription)"
            )
        }
    }

    private static func readOwnedRecord(
        for lease: TrackpadDriverEventCaptureReadyLease
    ) throws -> TrackpadDriverEventCaptureReadyRecord {
        let record: TrackpadDriverEventCaptureReadyRecord
        do {
            record = try JSONDecoder().decode(
                TrackpadDriverEventCaptureReadyRecord.self,
                from: Data(
                    contentsOf: standardizedFileURL(for: lease.path),
                    options: .mappedIfSafe
                )
            )
        } catch {
            throw TrackpadDriverEventCaptureReadyStoreError.ownershipMismatch(
                path: lease.path
            )
        }
        guard record.pid == lease.pid, record.runToken == lease.runToken else {
            throw TrackpadDriverEventCaptureReadyStoreError.ownershipMismatch(
                path: lease.path
            )
        }
        return record
    }

    private static func writeAtomically(
        _ record: TrackpadDriverEventCaptureReadyRecord,
        toPath path: String
    ) throws {
        let data = try encodedData(for: record)
        let url = standardizedFileURL(for: path)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw TrackpadDriverEventCaptureReadyStoreError.writeFailed(
                path: url.path,
                details: error.localizedDescription
            )
        }
    }

    private static func encodedData(
        for record: TrackpadDriverEventCaptureReadyRecord
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(record)
            data.append(0x0A)
            return data
        } catch {
            throw TrackpadDriverEventCaptureReadyStoreError.encodingFailed(
                details: error.localizedDescription
            )
        }
    }

    private static func write(_ data: Data, to descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    bytes.count - written
                )
                if result < 0, errno == EINTR {
                    continue
                }
                guard result > 0 else {
                    throw TrackpadDriverEventCaptureReadyStoreError.writeFailed(
                        path: path,
                        details: "write errno=\(result < 0 ? errno : EIO)"
                    )
                }
                written += result
            }
        }
    }

    private static func standardizedFileURL(for path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func unlink(_ url: URL) -> (result: Int32, errorCode: Int32) {
        url.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath else {
                return (-1, EINVAL)
            }
            let result = Darwin.unlink(fileSystemPath)
            return (result, result == 0 ? 0 : errno)
        }
    }
}
