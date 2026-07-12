import Darwin
import Foundation
import NapeGestureCore
import NapeGestureProductOutput

struct BundleAppCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let configuration = try commandConfiguration()
        let appURL = try destinationURL(outputPath: configuration.outputPath)
        let executablePath = try currentExecutablePath()
        let parentURL = appURL.deletingLastPathComponent()
        let parentStatus = try verifiedDirectoryBoundary(at: parentURL)
        let parentDescriptor = try openDirectory(at: parentURL, expectedStatus: parentStatus)
        defer { Darwin.close(parentDescriptor) }
        let destinationName = appURL.lastPathComponent
        let initialDestination = try itemStatus(
            parentDescriptor: parentDescriptor,
            name: destinationName
        )
        if initialDestination != nil, !configuration.replace {
            throw ToolError.bundleOutputAlreadyExists(appURL.path)
        }
        try validateVolumeRenameCapabilities(
            at: parentURL,
            replacingExistingItem: initialDestination != nil
        )
        try validateDestination(
            initialDestination,
            parentStatus: parentStatus,
            url: appURL
        )

        let temporaryName = ".nape-gesture-bundle-\(UUID().uuidString).app"
        let temporaryURL = parentURL.appendingPathComponent(temporaryName, isDirectory: true)
        let temporaryStatus = try createTemporaryBundleDirectory(
            name: temporaryName,
            parentDescriptor: parentDescriptor,
            parentStatus: parentStatus
        )
        var ownsTemporaryBundle = true

        do {
            try buildBundle(at: temporaryURL, executablePath: executablePath)
            let checkedItems = try BundleVerifier.verify(appPath: temporaryURL.path)
            let verifiedFingerprint = try bundleFingerprint(at: temporaryURL)
            try synchronizeBundleTree(at: temporaryURL)
            guard try bundleFingerprint(at: temporaryURL) == verifiedFingerprint else {
                throw ToolError.bundleVerificationFailed(
                    "永続化中に検証済み一時bundleの内容が変化しました: \(temporaryURL.path)"
                )
            }

            let replacedDestination = try installTemporaryBundle(
                parentDescriptor: parentDescriptor,
                temporaryName: temporaryName,
                temporaryURL: temporaryURL,
                temporaryStatus: temporaryStatus,
                verifiedFingerprint: verifiedFingerprint,
                destinationName: destinationName,
                destinationURL: appURL,
                initialDestination: initialDestination,
                parentStatus: parentStatus
            )
            ownsTemporaryBundle = false
            if let replacedDestination {
                try removeTemporaryBundleIfOwned(
                    name: temporaryName,
                    parentDescriptor: parentDescriptor,
                    parentURL: parentURL,
                    expectedStatus: replacedDestination,
                    parentStatus: parentStatus
                )
                try synchronizeDescriptor(
                    parentDescriptor,
                    description: "旧bundle cleanup後の親directory"
                )
            }

            print("アプリバンドルを作成しました: \(appURL.path)")
            print("検証済み:")
            for item in checkedItems {
                print("- \(item)")
            }
        } catch {
            let primaryError = error
            if ownsTemporaryBundle {
                do {
                    try removeTemporaryBundleIfOwned(
                        name: temporaryName,
                        parentDescriptor: parentDescriptor,
                        parentURL: parentURL,
                        expectedStatus: temporaryStatus,
                        parentStatus: parentStatus
                    )
                } catch {
                    throw ToolError.bundleVerificationFailed(
                        "一時bundleのcleanupにも失敗しました。"
                            + " primary=\(primaryError.localizedDescription)"
                            + " cleanup=\(error.localizedDescription)"
                    )
                }
            }
            throw primaryError
        }
    }

    private func destinationURL(outputPath: String) throws -> URL {
        let requestedURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        let name = requestedURL.lastPathComponent
        guard requestedURL.path != "/",
              !name.isEmpty,
              name != ".",
              name != "..",
              requestedURL.pathExtension.lowercased() == "app"
        else {
            throw ToolError.bundleVerificationFailed(
                "出力先は親directory直下の.app pathである必要があります: \(requestedURL.path)"
            )
        }
        let requestedParent = requestedURL.deletingLastPathComponent()
        let resolution = requestedParent.withUnsafeFileSystemRepresentation { path
            -> (path: String?, errorCode: Int32) in
            guard let path, let resolved = Darwin.realpath(path, nil) else {
                return (nil, errno)
            }
            defer { Darwin.free(resolved) }
            return (String(cString: resolved), 0)
        }
        guard let resolvedParentPath = resolution.path else {
            throw ToolError.bundleVerificationFailed(
                "bundle親directoryを実体pathへ解決できません: \(requestedParent.path)"
                    + " errno=\(resolution.errorCode)"
            )
        }
        let resolvedParent = URL(fileURLWithPath: resolvedParentPath, isDirectory: true)
        return resolvedParent.appendingPathComponent(name, isDirectory: true)
    }

    private func commandConfiguration() throws -> BundleAppCommandConfiguration {
        var outputPath: String?
        var replace = false
        var index = 0
        while index < options.count {
            switch options[index] {
            case "--replace":
                guard !replace else {
                    throw ToolError.invalidValue("--replace", "重複しています。")
                }
                replace = true
                index += 1
            case "--out":
                guard outputPath == nil else {
                    throw ToolError.invalidValue("--out", "重複しています。")
                }
                guard index + 1 < options.count,
                      !options[index + 1].hasPrefix("--")
                else {
                    throw ToolError.missingValue("--out")
                }
                outputPath = options[index + 1]
                index += 2
            default:
                throw ToolError.invalidValue("bundle-app option", options[index])
            }
        }

        let resolvedOutputPath = outputPath ?? URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("NapeGesture.app", isDirectory: true)
        .path
        return BundleAppCommandConfiguration(
            outputPath: resolvedOutputPath,
            replace: replace
        )
    }

    private func buildBundle(at appURL: URL, executablePath: String) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let bundledExecutableURL = macOSURL.appendingPathComponent("nape-gesture")

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: URL(fileURLWithPath: executablePath), to: bundledExecutableURL)
        try infoPlistData().write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)
        try writeDistributionResources(to: resourcesURL)
    }

    private func installTemporaryBundle(
        parentDescriptor: Int32,
        temporaryName: String,
        temporaryURL: URL,
        temporaryStatus: BundleFilesystemItemStatus,
        verifiedFingerprint: String,
        destinationName: String,
        destinationURL: URL,
        initialDestination: BundleFilesystemItemStatus?,
        parentStatus: BundleFilesystemItemStatus
    ) throws -> BundleFilesystemItemStatus? {
        guard try descriptorStatus(parentDescriptor).identity == parentStatus.identity else {
            throw ToolError.bundleVerificationFailed(
                "bundle構築中に親directory descriptorが変更されました: \(destinationURL.deletingLastPathComponent().path)"
            )
        }
        guard let currentTemporary = try itemStatus(
            parentDescriptor: parentDescriptor,
            name: temporaryName
        ),
              currentTemporary.identity == temporaryStatus.identity,
              currentTemporary.isDirectory,
              !currentTemporary.isSymbolicLink,
              currentTemporary.device == parentStatus.device,
              try bundleFingerprint(at: temporaryURL) == verifiedFingerprint
        else {
            throw ToolError.bundleVerificationFailed(
                "検証済み一時bundleのidentityまたは内容が構築完了時点から変化しました: \(temporaryURL.path)"
            )
        }

        let currentDestination = try itemStatus(
            parentDescriptor: parentDescriptor,
            name: destinationName
        )
        guard currentDestination?.identity == initialDestination?.identity else {
            throw ToolError.bundleVerificationFailed(
                "bundle構築中にdestinationが変更されたため置換を中止しました: \(destinationURL.path)"
            )
        }
        try validateDestination(
            currentDestination,
            parentStatus: parentStatus,
            url: destinationURL
        )

        if let initialDestination {
            try renameRelative(
                parentDescriptor: parentDescriptor,
                sourceName: temporaryName,
                destinationName: destinationName,
                flags: UInt32(RENAME_SWAP | RENAME_NOFOLLOW_ANY),
                operation: "destinationとの原子的swap"
            )
            let installed = try itemStatus(
                parentDescriptor: parentDescriptor,
                name: destinationName
            )
            let replaced = try itemStatus(
                parentDescriptor: parentDescriptor,
                name: temporaryName
            )
            guard installed?.identity == temporaryStatus.identity,
                  replaced?.identity == initialDestination.identity,
                  try bundleFingerprint(at: destinationURL) == verifiedFingerprint
            else {
                throw ToolError.bundleVerificationFailed(
                    "原子的swap後のentryが競合しました。安全でないrollbackは行わず両entryを保持します: \(destinationURL.path)"
                )
            }
            try synchronizeDescriptor(
                parentDescriptor,
                description: "原子的swap後の親directory"
            )
            return initialDestination
        }

        try renameRelative(
            parentDescriptor: parentDescriptor,
            sourceName: temporaryName,
            destinationName: destinationName,
            flags: UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY),
            operation: "destinationへの排他的rename"
        )
        guard try itemStatus(
            parentDescriptor: parentDescriptor,
            name: destinationName
        )?.identity == temporaryStatus.identity,
              try bundleFingerprint(at: destinationURL) == verifiedFingerprint
        else {
            throw ToolError.bundleVerificationFailed(
                "排他的rename後のentryが競合しました。安全でないrollbackは行わず現状を保持します: \(destinationURL.path)"
            )
        }
        try synchronizeDescriptor(
            parentDescriptor,
            description: "排他的rename後の親directory"
        )
        return nil
    }

    private func verifiedDirectoryBoundary(at directoryURL: URL) throws -> BundleFilesystemItemStatus {
        let rootURL = URL(fileURLWithPath: "/", isDirectory: true)
        guard let rootStatus = try itemStatus(at: rootURL), rootStatus.isDirectory else {
            throw ToolError.bundleVerificationFailed("filesystem rootをdirectoryとして確認できません。")
        }

        var currentURL = rootURL
        var currentStatus = rootStatus
        for component in directoryURL.pathComponents.dropFirst() {
            currentURL.appendPathComponent(component, isDirectory: true)
            guard let status = try itemStatus(at: currentURL) else {
                throw ToolError.bundleVerificationFailed(
                    "bundle親directoryが存在しません: \(currentURL.path)"
                )
            }
            guard !status.isSymbolicLink else {
                throw ToolError.bundleVerificationFailed(
                    "bundle出力pathのsymlink境界を拒否しました: \(currentURL.path)"
                )
            }
            guard status.isDirectory else {
                throw ToolError.bundleVerificationFailed(
                    "bundle出力pathの親要素がdirectoryではありません: \(currentURL.path)"
                )
            }
            currentStatus = status
        }
        return currentStatus
    }

    private func validateDestination(
        _ status: BundleFilesystemItemStatus?,
        parentStatus: BundleFilesystemItemStatus,
        url: URL
    ) throws {
        guard let status else {
            return
        }
        guard !status.isSymbolicLink else {
            throw ToolError.bundleVerificationFailed(
                "destinationがsymlinkのため置換を拒否しました: \(url.path)"
            )
        }
        guard status.isDirectory else {
            throw ToolError.bundleVerificationFailed(
                "destinationがdirectoryではないため置換を拒否しました: \(url.path)"
            )
        }
        guard status.device == parentStatus.device else {
            throw ToolError.bundleVerificationFailed(
                "destinationと一時bundleが同一filesystemではありません: \(url.path)"
            )
        }
        try validateExistingBundleIdentity(at: url)
    }

    private func createTemporaryBundleDirectory(
        name: String,
        parentDescriptor: Int32,
        parentStatus: BundleFilesystemItemStatus
    ) throws -> BundleFilesystemItemStatus {
        let result = name.withCString {
            Darwin.mkdirat(parentDescriptor, $0, mode_t(S_IRWXU))
        }
        guard result == 0 else {
            throw ToolError.bundleVerificationFailed(
                "一時bundle directoryを作成できません: \(name) errno=\(errno)"
            )
        }

        do {
            guard let status = try itemStatus(
                parentDescriptor: parentDescriptor,
                name: name
            ),
                  status.isDirectory,
                  !status.isSymbolicLink,
                  status.device == parentStatus.device
            else {
                throw ToolError.bundleVerificationFailed(
                    "一時bundle directoryの境界を確認できません: \(name)"
                )
            }
            return status
        } catch {
            throw ToolError.bundleVerificationFailed(
                "一時bundle directory作成後のidentity検査に失敗しました。"
                    + " path=\(name) error=\(error.localizedDescription)"
            )
        }
    }

    private func removeTemporaryBundleIfOwned(
        name: String,
        parentDescriptor: Int32,
        parentURL: URL,
        expectedStatus: BundleFilesystemItemStatus,
        parentStatus: BundleFilesystemItemStatus
    ) throws {
        guard try descriptorStatus(parentDescriptor).identity == parentStatus.identity else {
            throw ToolError.bundleVerificationFailed(
                "親directory descriptorが変化したため一時bundleのcleanupを拒否しました: \(parentURL.path)"
            )
        }
        guard let status = try itemStatus(
            parentDescriptor: parentDescriptor,
            name: name
        ) else {
            return
        }
        guard status.identity == expectedStatus.identity,
              status.isDirectory,
              !status.isSymbolicLink
        else {
            throw ToolError.bundleVerificationFailed(
                "一時bundleのidentityが変化したためcleanupを拒否しました: \(name)"
            )
        }

        try removeDirectoryTree(
            parentDescriptor: parentDescriptor,
            name: name,
            expectedStatus: expectedStatus,
            displayPath: parentURL.appendingPathComponent(name, isDirectory: true).path
        )
        guard try itemStatus(
            parentDescriptor: parentDescriptor,
            name: name
        ) == nil else {
            throw ToolError.bundleVerificationFailed(
                "一時bundle cleanup後もdirectory entryが残っています: "
                    + parentURL.appendingPathComponent(name, isDirectory: true).path
            )
        }
    }

    private func removeDirectoryTree(
        parentDescriptor: Int32,
        name: String,
        expectedStatus: BundleFilesystemItemStatus,
        displayPath: String
    ) throws {
        let descriptor = name.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw ToolError.bundleVerificationFailed(
                "cleanup対象directoryをdescriptor相対で開けません: \(displayPath) errno=\(errno)"
            )
        }

        do {
            let openedStatus = try descriptorStatus(descriptor)
            guard openedStatus.identity == expectedStatus.identity else {
                throw ToolError.bundleVerificationFailed(
                    "cleanup対象directoryのentryとdescriptor identityが一致しません: \(displayPath)"
                )
            }
            try removeDirectoryContents(
                descriptor: descriptor,
                displayPath: displayPath
            )
            Darwin.close(descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }

        guard try itemStatus(
            parentDescriptor: parentDescriptor,
            name: name
        )?.identity == expectedStatus.identity else {
            throw ToolError.bundleVerificationFailed(
                "cleanup直前にdirectory entryが変化しました: \(displayPath)"
            )
        }
        let result = name.withCString {
            Darwin.unlinkat(parentDescriptor, $0, AT_REMOVEDIR)
        }
        guard result == 0 else {
            throw ToolError.bundleVerificationFailed(
                "cleanup対象directoryを削除できません: \(displayPath) errno=\(errno)"
            )
        }
    }

    private func removeDirectoryContents(
        descriptor: Int32,
        displayPath: String
    ) throws {
        let enumerationDescriptor = Darwin.dup(descriptor)
        guard enumerationDescriptor >= 0 else {
            throw ToolError.bundleVerificationFailed(
                "cleanup対象directoryを列挙できません: \(displayPath) errno=\(errno)"
            )
        }
        guard let directory = Darwin.fdopendir(enumerationDescriptor) else {
            Darwin.close(enumerationDescriptor)
            throw ToolError.bundleVerificationFailed(
                "cleanup対象directory streamを開けません: \(displayPath) errno=\(errno)"
            )
        }
        defer { Darwin.closedir(directory) }

        errno = 0
        while let entry = Darwin.readdir(directory) {
            let entryName = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(entry.pointee.d_namlen) + 1
                ) {
                    String(cString: $0)
                }
            }
            if entryName == "." || entryName == ".." {
                continue
            }
            guard let status = try itemStatus(
                parentDescriptor: descriptor,
                name: entryName
            ) else {
                errno = 0
                continue
            }
            let childPath = "\(displayPath)/\(entryName)"
            if status.isDirectory && !status.isSymbolicLink {
                try removeDirectoryTree(
                    parentDescriptor: descriptor,
                    name: entryName,
                    expectedStatus: status,
                    displayPath: childPath
                )
            } else {
                let result = entryName.withCString {
                    Darwin.unlinkat(descriptor, $0, 0)
                }
                guard result == 0 else {
                    throw ToolError.bundleVerificationFailed(
                        "cleanup対象fileを削除できません: \(childPath) errno=\(errno)"
                    )
                }
            }
            errno = 0
        }
        guard errno == 0 else {
            throw ToolError.bundleVerificationFailed(
                "cleanup対象directoryの列挙中に失敗しました: \(displayPath) errno=\(errno)"
            )
        }
    }

    private func synchronizeBundleTree(at appURL: URL) throws {
        guard let rootStatus = try itemStatus(at: appURL),
              rootStatus.isDirectory,
              !rootStatus.isSymbolicLink,
              let enumerator = FileManager.default.enumerator(
                  at: appURL,
                  includingPropertiesForKeys: nil,
                  options: [],
                  errorHandler: nil
              )
        else {
            throw ToolError.bundleVerificationFailed(
                "永続化するbundle treeを列挙できません: \(appURL.path)"
            )
        }

        var items: [(URL, BundleFilesystemItemStatus)] = [(appURL, rootStatus)]
        for case let itemURL as URL in enumerator {
            guard let status = try itemStatus(at: itemURL),
                  !status.isSymbolicLink,
                  status.isDirectory || status.isRegularFile
            else {
                throw ToolError.bundleVerificationFailed(
                    "bundle永続化中にsymlinkまたは不正file typeを検出しました: \(itemURL.path)"
                )
            }
            items.append((itemURL, status))
        }

        for (url, status) in items.sorted(by: { $0.0.path.count > $1.0.path.count }) {
            let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC
                | (status.isDirectory ? O_DIRECTORY : 0)
            let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else {
                    return -1
                }
                return Darwin.open(path, flags)
            }
            guard descriptor >= 0 else {
                throw ToolError.bundleVerificationFailed(
                    "bundle itemを永続化用に開けません: \(url.path) errno=\(errno)"
                )
            }
            do {
                guard try descriptorStatus(descriptor).identity == status.identity else {
                    throw ToolError.bundleVerificationFailed(
                        "bundle itemのpathとdescriptor identityが一致しません: \(url.path)"
                    )
                }
                try synchronizeDescriptor(
                    descriptor,
                    description: "bundle item \(url.path)"
                )
                Darwin.close(descriptor)
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }
    }

    private func synchronizeDescriptor(
        _ descriptor: Int32,
        description: String
    ) throws {
        guard Darwin.fsync(descriptor) == 0 else {
            throw ToolError.bundleVerificationFailed(
                "\(description)をfilesystemへ永続化できません: errno=\(errno)"
            )
        }
    }

    private func validateExistingBundleIdentity(at appURL: URL) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        guard let contentsStatus = try itemStatus(at: contentsURL),
              contentsStatus.isDirectory,
              !contentsStatus.isSymbolicLink,
              let plistStatus = try itemStatus(at: infoPlistURL),
              plistStatus.isRegularFile,
              !plistStatus.isSymbolicLink,
              let data = try? Data(contentsOf: infoPlistURL),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let plist = object as? [String: Any],
              plist["CFBundleIdentifier"] as? String == "dev.char5742.nape-gesture",
              plist["CFBundleExecutable"] as? String == "nape-gesture",
              plist["CFBundlePackageType"] as? String == "APPL"
        else {
            throw ToolError.bundleVerificationFailed(
                "--replaceの既存destinationはNape Gesture app bundleである必要があります: \(appURL.path)"
            )
        }
    }

    private func validateVolumeRenameCapabilities(
        at parentURL: URL,
        replacingExistingItem: Bool
    ) throws {
        let values = try parentURL.resourceValues(
            forKeys: [
                .volumeSupportsExclusiveRenamingKey,
                .volumeSupportsSwapRenamingKey
            ]
        )
        guard values.volumeSupportsExclusiveRenaming == true else {
            throw ToolError.bundleVerificationFailed(
                "出力先filesystemは排他的renameをサポートしていません: \(parentURL.path)"
            )
        }
        if replacingExistingItem, values.volumeSupportsSwapRenaming != true {
            throw ToolError.bundleVerificationFailed(
                "出力先filesystemは原子的swap renameをサポートしていません: \(parentURL.path)"
            )
        }
    }

    private func bundleFingerprint(at appURL: URL) throws -> String {
        guard let rootStatus = try itemStatus(at: appURL),
              rootStatus.isDirectory,
              !rootStatus.isSymbolicLink,
              let enumerator = FileManager.default.enumerator(
                  at: appURL,
                  includingPropertiesForKeys: nil,
                  options: [],
                  errorHandler: nil
              )
        else {
            throw ToolError.bundleVerificationFailed(
                "bundle fingerprintのrootを読み取れません: \(appURL.path)"
            )
        }

        let prefix = appURL.path + "/"
        var records: [String] = []
        for case let itemURL as URL in enumerator {
            guard itemURL.path.hasPrefix(prefix),
                  let status = try itemStatus(at: itemURL),
                  !status.isSymbolicLink
            else {
                throw ToolError.bundleVerificationFailed(
                    "bundle fingerprintでsymlinkまたは不正pathを検出しました: \(itemURL.path)"
                )
            }
            let relativePath = String(itemURL.path.dropFirst(prefix.count))
            if status.isDirectory {
                records.append("D\u{0}\(relativePath)")
            } else if status.isRegularFile {
                let data = try Data(contentsOf: itemURL)
                records.append(
                    "F\u{0}\(relativePath)\u{0}\(data.count)\u{0}"
                        + TrackpadDriverEventCaptureManifest.sha256HexDigest(of: data)
                )
            } else {
                throw ToolError.bundleVerificationFailed(
                    "bundle fingerprintが通常file以外を検出しました: \(itemURL.path)"
                )
            }
        }
        let manifest = records.sorted().joined(separator: "\n") + "\n"
        return TrackpadDriverEventCaptureManifest.sha256HexDigest(of: Data(manifest.utf8))
    }

    private func openDirectory(
        at url: URL,
        expectedStatus: BundleFilesystemItemStatus
    ) throws -> Int32 {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw ToolError.bundleVerificationFailed(
                "bundle親directoryを安全に開けません: \(url.path) errno=\(errno)"
            )
        }
        do {
            guard try descriptorStatus(descriptor).identity == expectedStatus.identity else {
                throw ToolError.bundleVerificationFailed(
                    "bundle親directoryのpathとdescriptor identityが一致しません: \(url.path)"
                )
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func descriptorStatus(_ descriptor: Int32) throws -> BundleFilesystemItemStatus {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0 else {
            throw ToolError.bundleVerificationFailed(
                "filesystem descriptorを検査できません: fd=\(descriptor) errno=\(errno)"
            )
        }
        return BundleFilesystemItemStatus(value)
    }

    private func itemStatus(
        parentDescriptor: Int32,
        name: String
    ) throws -> BundleFilesystemItemStatus? {
        var value = stat()
        let result = name.withCString {
            Darwin.fstatat(parentDescriptor, $0, &value, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            return BundleFilesystemItemStatus(value)
        }
        if errno == ENOENT {
            return nil
        }
        throw ToolError.bundleVerificationFailed(
            "filesystem itemをdescriptor相対で検査できません: \(name) errno=\(errno)"
        )
    }

    private func renameRelative(
        parentDescriptor: Int32,
        sourceName: String,
        destinationName: String,
        flags: UInt32,
        operation: String
    ) throws {
        let result = sourceName.withCString { source in
            destinationName.withCString { destination in
                Darwin.renameatx_np(
                    parentDescriptor,
                    source,
                    parentDescriptor,
                    destination,
                    flags
                )
            }
        }
        guard result == 0 else {
            let errorCode = errno
            let suffix = errorCode == ENOTSUP
                ? " filesystemが必要な排他的/交換renameをサポートしていません。"
                : ""
            throw ToolError.bundleVerificationFailed(
                "\(operation)に失敗しました。source=\(sourceName) destination=\(destinationName)"
                    + " errno=\(errorCode)\(suffix)"
            )
        }
    }

    private func itemStatus(at url: URL) throws -> BundleFilesystemItemStatus? {
        var value = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> (result: Int32, errorCode: Int32) in
            guard let path else {
                return (-1, EINVAL)
            }
            let result = Darwin.lstat(path, &value)
            return (result, result == 0 ? 0 : errno)
        }
        if result.result == 0 {
            return BundleFilesystemItemStatus(value)
        }
        if result.errorCode == ENOENT {
            return nil
        }
        throw ToolError.bundleVerificationFailed(
            "filesystem itemを検査できません: \(url.path) errno=\(result.errorCode)"
        )
    }

    private func currentExecutablePath() throws -> String {
        if let path = Bundle.main.executablePath {
            return path
        }
        guard let first = CommandLine.arguments.first else {
            throw ToolError.executablePathUnavailable
        }
        return first
    }

    private func infoPlistData() -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>ja</string>
            <key>CFBundleDisplayName</key>
            <string>Nape Gesture</string>
            <key>CFBundleExecutable</key>
            <string>nape-gesture</string>
            <key>CFBundleIdentifier</key>
            <string>dev.char5742.nape-gesture</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>Nape Gesture</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>0.1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSMinimumSystemVersion</key>
            <string>13.0</string>
            <key>LSUIElement</key>
            \(lsUIElementPlistValue)
            <key>NSHighResolutionCapable</key>
            <true/>
            <key>NSHumanReadableCopyright</key>
            <string>Copyright © 2026 Nape Gesture contributors</string>
        </dict>
        </plist>
        """
        return Data(plist.utf8)
    }

    private var lsUIElementPlistValue: String {
        GUIAppLaunchPresenter.regularGUIApp.bundleLSUIElement ? "<true/>" : "<false/>"
    }

    private func writeDistributionResources(to resourcesURL: URL) throws {
        try distributionResourceData(
            fallback: fallbackLicenseText
        ).write(to: resourcesURL.appendingPathComponent("LICENSE.txt"), options: .atomic)

        try distributionResourceData(
            fallback: fallbackThirdPartyNotices
        ).write(to: resourcesURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"), options: .atomic)

        let trackpadResourcesURL = resourcesURL
            .appendingPathComponent("TrackpadContracts", isDirectory: true)
            .appendingPathComponent("25F80", isDirectory: true)
        try FileManager.default.createDirectory(
            at: trackpadResourcesURL,
            withIntermediateDirectories: true
        )
        try requiredProductResourceData(
            bundleRelativePath: TrackpadGestureOutputResources.contractRelativePath,
            repositoryRelativePath: TrackpadGestureOutputResources.repositoryContractRelativePath
        ).write(
            to: trackpadResourcesURL.appendingPathComponent("scroll-momentum-contract.json"),
            options: .atomic
        )
        try requiredProductResourceData(
            bundleRelativePath: TrackpadGestureOutputResources.modelRelativePath,
            repositoryRelativePath: TrackpadGestureOutputResources.repositoryModelRelativePath
        ).write(
            to: trackpadResourcesURL.appendingPathComponent("scroll-output-model.json"),
            options: .atomic
        )
    }

    private func requiredProductResourceData(
        bundleRelativePath: String,
        repositoryRelativePath: String
    ) throws -> Data {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleRelativePath))
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(repositoryRelativePath)
        )
        for url in candidates {
            guard let status = try? itemStatus(at: url),
                  status.isRegularFile,
                  !status.isSymbolicLink,
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty
            else {
                continue
            }
            return data
        }
        throw ToolError.bundleVerificationFailed(
            "配布必須resourceをbundleまたはrepositoryから読み込めません: \(bundleRelativePath)"
        )
    }

    private func distributionResourceData(fallback: String) -> Data {
        Data((fallback + "\n").utf8)
    }

    private var fallbackLicenseText: String {
        """
        MIT License

        Copyright (c) 2026 Nape Gesture contributors

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    }

    private var fallbackThirdPartyNotices: String {
        """
        # サードパーティ通知

        Nape Gesture は現在、サードパーティの Swift パッケージや外部ソースコード依存を持ちません。

        アプリは macOS が提供する Apple システムフレームワークへリンクします。

        - ApplicationServices
        - AppKit
        - Carbon
        - IOKit
        """
    }
}

private struct BundleAppCommandConfiguration {
    var outputPath: String
    var replace: Bool
}

private struct BundleFilesystemItemIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    let fileType: mode_t
}

private struct BundleFilesystemItemStatus {
    let device: UInt64
    let identity: BundleFilesystemItemIdentity
    let mode: mode_t

    init(_ value: stat) {
        let device = UInt64(value.st_dev)
        let fileType = value.st_mode & mode_t(S_IFMT)
        self.device = device
        identity = BundleFilesystemItemIdentity(
            device: device,
            inode: UInt64(value.st_ino),
            fileType: fileType
        )
        mode = value.st_mode
    }

    var isDirectory: Bool {
        mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    }

    var isRegularFile: Bool {
        mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    var isSymbolicLink: Bool {
        mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
    }
}
