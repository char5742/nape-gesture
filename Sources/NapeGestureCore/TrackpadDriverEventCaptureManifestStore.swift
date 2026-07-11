import Darwin
import Foundation

public enum TrackpadDriverEventCaptureManifestTemporaryFileOperation: String, Equatable, Sendable {
    case write
    case synchronize
    case close
}

public enum TrackpadDriverEventCaptureManifestStoreError: LocalizedError, Equatable, Sendable {
    case pathConflict(logPath: String, manifestPath: String)
    case pathResolutionFailed(path: String, details: String)
    case parentDirectoryMissing(path: String)
    case parentPathIsNotDirectory(path: String)
    case parentDirectoryInspectionFailed(path: String, details: String)
    case destinationIsDirectory(path: String)
    case destinationInspectionFailed(path: String, details: String)
    case destinationRemovalFailed(path: String, details: String)
    case manifestEncodingFailed(details: String)
    case temporaryFileCreationFailed(path: String, errno: Int32)
    case temporaryFileOperationFailed(
        operation: TrackpadDriverEventCaptureManifestTemporaryFileOperation,
        path: String,
        errno: Int32
    )
    case temporaryFileCleanupFailed(path: String, details: String, primaryFailure: String)
    case renameFailed(path: String, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case let .pathConflict(logPath, manifestPath):
            return "イベントログとcapture manifestが同じlocationまたはfile予定地の親子pathを参照しています。logPath=\(logPath) manifestPath=\(manifestPath)"
        case let .pathResolutionFailed(path, details):
            return "pathのsymlinkを安全に解決できませんでした。path=\(path) details=\(details)"
        case let .parentDirectoryMissing(path):
            return "manifest親directoryが存在しません。path=\(path)"
        case let .parentPathIsNotDirectory(path):
            return "manifest親pathがdirectoryではありません。path=\(path)"
        case let .parentDirectoryInspectionFailed(path, details):
            return "manifest親directoryを検査できませんでした。path=\(path) details=\(details)"
        case let .destinationIsDirectory(path):
            return "manifest pathがdirectoryです。path=\(path)"
        case let .destinationInspectionFailed(path, details):
            return "既存manifest sidecarを検査できませんでした。path=\(path) details=\(details)"
        case let .destinationRemovalFailed(path, details):
            return "既存manifest sidecarを削除できませんでした。path=\(path) details=\(details)"
        case let .manifestEncodingFailed(details):
            return "capture manifestをencodeできませんでした。details=\(details)"
        case let .temporaryFileCreationFailed(path, errorCode):
            return "temporary fileを作成できません。path=\(path) errno=\(errorCode)"
        case let .temporaryFileOperationFailed(operation, path, errorCode):
            return "temporary fileの\(operation.rawValue)に失敗しました。path=\(path) errno=\(errorCode)"
        case let .temporaryFileCleanupFailed(path, details, primaryFailure):
            return "失敗後のtemporary fileを削除できませんでした。path=\(path) details=\(details) primaryFailure=\(primaryFailure)"
        case let .renameFailed(path, errorCode):
            return "path=\(path) errno=\(errorCode)"
        }
    }
}

public struct TrackpadDriverEventCaptureManifestStore: Sendable {
    public init() {}

    public func pathsReferToSameLocation(
        _ firstPath: String,
        _ secondPath: String
    ) throws -> Bool {
        let firstURL = try Self.resolvedLocationURL(for: firstPath)
        let secondURL = try Self.resolvedLocationURL(for: secondPath)
        if firstURL.path == secondURL.path {
            return true
        }

        guard
            let firstIdentity = Self.fileIdentity(at: firstURL),
            let secondIdentity = Self.fileIdentity(at: secondURL)
        else {
            return false
        }
        return firstIdentity == secondIdentity
    }

    public func fileDestinationPathsConflict(
        _ firstPath: String,
        _ secondPath: String
    ) throws -> Bool {
        let firstURL = try Self.resolvedLocationURL(for: firstPath)
        let secondURL = try Self.resolvedLocationURL(for: secondPath)
        if firstURL.path == secondURL.path {
            return true
        }
        if let firstIdentity = Self.fileIdentity(at: firstURL),
           let secondIdentity = Self.fileIdentity(at: secondURL),
           firstIdentity == secondIdentity
        {
            return true
        }

        let comparisonIsCaseSensitive = try Self.volumeSupportsCaseSensitiveNames(
            at: firstURL
        ) && Self.volumeSupportsCaseSensitiveNames(at: secondURL)
        let firstComponents = Self.normalizedPathComponents(
            firstURL.pathComponents,
            caseSensitive: comparisonIsCaseSensitive
        )
        let secondComponents = Self.normalizedPathComponents(
            secondURL.pathComponents,
            caseSensitive: comparisonIsCaseSensitive
        )
        if firstComponents == secondComponents {
            return true
        }
        return Self.isStrictPathPrefix(firstComponents, of: secondComponents)
            || Self.isStrictPathPrefix(secondComponents, of: firstComponents)
    }

    public func validateDistinctLocations(logPath: String, manifestPath: String) throws {
        guard try !fileDestinationPathsConflict(logPath, manifestPath) else {
            throw TrackpadDriverEventCaptureManifestStoreError.pathConflict(
                logPath: logPath,
                manifestPath: manifestPath
            )
        }
    }

    public func prepareDestination(logPath: String, manifestPath: String) throws {
        try validateDistinctLocations(logPath: logPath, manifestPath: manifestPath)

        let fileManager = FileManager.default
        let manifestURL = Self.standardizedFileURL(for: manifestPath)
        try Self.validateParentDirectory(of: manifestURL, fileManager: fileManager)

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: manifestURL.path)
        } catch where Self.isNoSuchFileError(error) {
            return
        } catch {
            throw TrackpadDriverEventCaptureManifestStoreError.destinationInspectionFailed(
                path: manifestURL.path,
                details: error.localizedDescription
            )
        }

        if attributes[.type] as? FileAttributeType == .typeDirectory {
            throw TrackpadDriverEventCaptureManifestStoreError.destinationIsDirectory(
                path: manifestURL.path
            )
        }

        let removalResult = Self.unlinkItem(at: manifestURL)
        if removalResult.result == 0 || removalResult.errorCode == ENOENT {
            return
        }
        throw TrackpadDriverEventCaptureManifestStoreError.destinationRemovalFailed(
            path: manifestURL.path,
            details: "errno=\(removalResult.errorCode)"
        )
    }

    public func writeAtomically(
        _ manifest: TrackpadDriverEventCaptureManifest,
        toPath manifestPath: String
    ) throws {
        let fileManager = FileManager.default
        let manifestURL = Self.standardizedFileURL(for: manifestPath)
        try Self.validateParentDirectory(of: manifestURL, fileManager: fileManager)

        let manifestData: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var encoded = try encoder.encode(manifest)
            encoded.append(0x0A)
            manifestData = encoded
        } catch {
            throw TrackpadDriverEventCaptureManifestStoreError.manifestEncodingFailed(
                details: error.localizedDescription
            )
        }

        let temporaryURL = manifestURL.deletingLastPathComponent().appendingPathComponent(
            ".\(manifestURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        var descriptor: Int32 = -1
        var temporaryFileExists = false
        defer {
            if descriptor >= 0 {
                _ = Darwin.close(descriptor)
            }
            if temporaryFileExists {
                _ = Self.unlinkItem(at: temporaryURL)
            }
        }

        do {
            let openResult = temporaryURL.withUnsafeFileSystemRepresentation { path -> (Int32, Int32) in
                guard let path else {
                    return (-1, EINVAL)
                }
                let openedDescriptor = Darwin.open(
                    path,
                    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                    mode_t(0o666)
                )
                return (openedDescriptor, openedDescriptor >= 0 ? 0 : errno)
            }
            guard openResult.0 >= 0 else {
                throw TrackpadDriverEventCaptureManifestStoreError.temporaryFileCreationFailed(
                    path: temporaryURL.path,
                    errno: openResult.1
                )
            }
            descriptor = openResult.0
            temporaryFileExists = true

            try Self.write(
                manifestData,
                to: descriptor,
                temporaryPath: temporaryURL.path
            )
            guard Darwin.fsync(descriptor) == 0 else {
                throw TrackpadDriverEventCaptureManifestStoreError.temporaryFileOperationFailed(
                    operation: .synchronize,
                    path: temporaryURL.path,
                    errno: errno
                )
            }

            let descriptorToClose = descriptor
            descriptor = -1
            guard Darwin.close(descriptorToClose) == 0 else {
                throw TrackpadDriverEventCaptureManifestStoreError.temporaryFileOperationFailed(
                    operation: .close,
                    path: temporaryURL.path,
                    errno: errno
                )
            }

            let renameResult = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
                manifestURL.withUnsafeFileSystemRepresentation { destinationPath -> (Int32, Int32) in
                    guard let temporaryPath, let destinationPath else {
                        return (-1, EINVAL)
                    }
                    let result = Darwin.rename(temporaryPath, destinationPath)
                    return (result, result == 0 ? 0 : errno)
                }
            }
            guard renameResult.0 == 0 else {
                throw TrackpadDriverEventCaptureManifestStoreError.renameFailed(
                    path: manifestURL.path,
                    errno: renameResult.1
                )
            }
            temporaryFileExists = false
        } catch {
            let primaryFailure = error
            if descriptor >= 0 {
                _ = Darwin.close(descriptor)
                descriptor = -1
            }
            if temporaryFileExists {
                let cleanupResult = Self.unlinkItem(at: temporaryURL)
                if cleanupResult.result == 0 || cleanupResult.errorCode == ENOENT {
                    temporaryFileExists = false
                } else {
                    throw TrackpadDriverEventCaptureManifestStoreError.temporaryFileCleanupFailed(
                        path: temporaryURL.path,
                        details: "errno=\(cleanupResult.errorCode)",
                        primaryFailure: primaryFailure.localizedDescription
                    )
                }
            }
            throw primaryFailure
        }
    }

    private static func write(_ data: Data, to descriptor: Int32, temporaryPath: String) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var writtenByteCount = 0
            while writtenByteCount < bytes.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: writtenByteCount),
                    bytes.count - writtenByteCount
                )
                if result < 0, errno == EINTR {
                    continue
                }
                guard result > 0 else {
                    let errorCode = result < 0 ? errno : EIO
                    throw TrackpadDriverEventCaptureManifestStoreError.temporaryFileOperationFailed(
                        operation: .write,
                        path: temporaryPath,
                        errno: errorCode
                    )
                }
                writtenByteCount += result
            }
        }
    }

    private static func validateParentDirectory(
        of manifestURL: URL,
        fileManager: FileManager
    ) throws {
        let directoryURL = manifestURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw TrackpadDriverEventCaptureManifestStoreError.parentPathIsNotDirectory(
                    path: directoryURL.path
                )
            }
            return
        }

        do {
            _ = try fileManager.attributesOfItem(atPath: directoryURL.path)
            throw TrackpadDriverEventCaptureManifestStoreError.parentPathIsNotDirectory(
                path: directoryURL.path
            )
        } catch let error as TrackpadDriverEventCaptureManifestStoreError {
            throw error
        } catch where isNoSuchFileError(error) {
            throw TrackpadDriverEventCaptureManifestStoreError.parentDirectoryMissing(
                path: directoryURL.path
            )
        } catch {
            throw TrackpadDriverEventCaptureManifestStoreError.parentDirectoryInspectionFailed(
                path: directoryURL.path,
                details: error.localizedDescription
            )
        }
    }

    private static func resolvedLocationURL(for path: String) throws -> URL {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: "/", isDirectory: true)
        var pendingComponents = Array(URL(fileURLWithPath: path).pathComponents.dropFirst())
        var resolvedURL = rootURL
        var resolvedSymbolicLinkCount = 0

        while !pendingComponents.isEmpty {
            let component = pendingComponents.removeFirst()
            if component == "." {
                continue
            }
            if component == ".." {
                resolvedURL.deleteLastPathComponent()
                continue
            }
            let candidateURL = resolvedURL.appendingPathComponent(component)
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(atPath: candidateURL.path)
            } catch where isNoSuchFileError(error) {
                resolvedURL = candidateURL
                continue
            } catch {
                throw TrackpadDriverEventCaptureManifestStoreError.pathResolutionFailed(
                    path: path,
                    details: "component=\(candidateURL.path) error=\(error.localizedDescription)"
                )
            }

            guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
                resolvedURL = candidateURL
                continue
            }
            resolvedSymbolicLinkCount += 1
            guard resolvedSymbolicLinkCount <= 64 else {
                throw TrackpadDriverEventCaptureManifestStoreError.pathResolutionFailed(
                    path: path,
                    details: "symlink解決回数が上限を超えました。last=\(candidateURL.path)"
                )
            }

            let destination: String
            do {
                destination = try fileManager.destinationOfSymbolicLink(atPath: candidateURL.path)
            } catch {
                throw TrackpadDriverEventCaptureManifestStoreError.pathResolutionFailed(
                    path: path,
                    details: "symlink=\(candidateURL.path) error=\(error.localizedDescription)"
                )
            }

            let destinationURL: URL
            if destination.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: destination)
            } else {
                let baseURL = URL(fileURLWithPath: resolvedURL.path, isDirectory: true)
                destinationURL = URL(
                    fileURLWithPath: destination,
                    relativeTo: baseURL
                ).absoluteURL
            }
            pendingComponents = Array(destinationURL.pathComponents.dropFirst()) + pendingComponents
            resolvedURL = rootURL
        }

        return resolvedURL
    }

    private static func standardizedFileURL(for path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func isStrictPathPrefix(
        _ prefix: [String],
        of components: [String]
    ) -> Bool {
        prefix.count < components.count
            && Array(components.prefix(prefix.count)) == prefix
    }

    private static func normalizedPathComponents(
        _ components: [String],
        caseSensitive: Bool
    ) -> [String] {
        components.map { component in
            let normalized = component.precomposedStringWithCanonicalMapping
            guard !caseSensitive else {
                return normalized
            }
            return normalized.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        }
    }

    private static func volumeSupportsCaseSensitiveNames(at url: URL) throws -> Bool {
        let fileManager = FileManager.default
        var candidate = url
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                break
            }
            candidate = parent
        }
        do {
            let values = try candidate.resourceValues(
                forKeys: [.volumeSupportsCaseSensitiveNamesKey]
            )
            return values.volumeSupportsCaseSensitiveNames ?? true
        } catch {
            throw TrackpadDriverEventCaptureManifestStoreError.pathResolutionFailed(
                path: url.path,
                details: "volume case-sensitivity: \(error.localizedDescription)"
            )
        }
    }

    private static func fileIdentity(at url: URL) -> FileIdentity? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else {
            return nil
        }
        return FileIdentity(device: device, inode: inode)
    }

    private static func unlinkItem(at url: URL) -> (result: Int32, errorCode: Int32) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return (-1, EINVAL)
            }
            let result = Darwin.unlink(path)
            return (result, result == 0 ? 0 : errno)
        }
    }

    private static func isNoSuchFileError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain, cocoaError.code == NSFileNoSuchFileError {
            return true
        }
        if cocoaError.domain == NSPOSIXErrorDomain, cocoaError.code == Int(ENOENT) {
            return true
        }
        if let underlyingError = cocoaError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlyingError.domain == NSPOSIXErrorDomain && underlyingError.code == Int(ENOENT)
        }
        return false
    }
}

private struct FileIdentity: Equatable {
    var device: UInt64
    var inode: UInt64
}
