import CoreFoundation
import Darwin
import Foundation

enum BundleVerifier {
    static func verify(appPath: String, requireSignature: Bool = false) throws -> [String] {
        let appURL = URL(fileURLWithPath: appPath).standardizedFileURL
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = macOSURL.appendingPathComponent(AppBundleIdentity.executableName)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let licenseURL = resourcesURL.appendingPathComponent("LICENSE.txt")
        let noticesURL = resourcesURL.appendingPathComponent("THIRD_PARTY_NOTICES.md")

        var failures: [String] = []
        let appDirectoryIsSafe = verifyDirectory(
            at: appURL,
            name: "アプリバンドル root",
            failures: &failures
        )
        let contentsDirectoryIsSafe = appDirectoryIsSafe && verifyDirectory(
            at: contentsURL,
            name: "Contents",
            failures: &failures
        )
        let macOSDirectoryIsSafe = contentsDirectoryIsSafe && verifyDirectory(
            at: macOSURL,
            name: "Contents/MacOS",
            failures: &failures
        )
        let resourcesDirectoryIsSafe = contentsDirectoryIsSafe && verifyDirectory(
            at: resourcesURL,
            name: "Contents/Resources",
            failures: &failures
        )
        let executableIsSafe = macOSDirectoryIsSafe
            && verifyExecutable(at: executableURL, failures: &failures)
        let executableIsContained = macOSDirectoryIsSafe && verifyContainment(
            of: executableURL,
            in: appURL,
            name: "実行ファイル",
            failures: &failures
        )
        let infoPlistIsSafe = contentsDirectoryIsSafe && verifyRegularFile(
            at: infoPlistURL,
            name: "Info.plist",
            failures: &failures
        )

        if infoPlistIsSafe {
            verifyInfoPlist(at: infoPlistURL, failures: &failures)
        }
        let licenseIsSafe = resourcesDirectoryIsSafe
            && verifyReadableNonEmptyFile(at: licenseURL, name: "LICENSE.txt", failures: &failures)
        let noticesAreSafe = resourcesDirectoryIsSafe
            && verifyReadableNonEmptyFile(
                at: noticesURL,
                name: "THIRD_PARTY_NOTICES.md",
                failures: &failures
            )

        let canVerifySignature = appDirectoryIsSafe
            && contentsDirectoryIsSafe
            && macOSDirectoryIsSafe
            && resourcesDirectoryIsSafe
            && executableIsSafe
            && executableIsContained
            && infoPlistIsSafe
            && licenseIsSafe
            && noticesAreSafe
        let signatureStatus = canVerifySignature
            ? verifyCodeSignature(appURL: appURL)
            : CodeSignatureStatus(isValid: false, message: "安全でない bundle 境界があるため未実行です。")
        if requireSignature, !signatureStatus.isValid {
            failures.append("コード署名検証に失敗しました: \(signatureStatus.message)")
        }

        if !failures.isEmpty {
            throw ToolError.bundleVerificationFailed(failures.joined(separator: "\n"))
        }

        return [
            "Info.plist",
            "Info.plist: CFBundleIdentifier=\(AppBundleIdentity.bundleIdentifier)",
            "Info.plist: CFBundleExecutable=\(AppBundleIdentity.executableName)",
            "Info.plist: CFBundleName=\(AppBundleIdentity.bundleName)",
            "Info.plist: CFBundleDisplayName=\(AppBundleIdentity.displayName)",
            "Info.plist: LSUIElement=false",
            "Contents/MacOS/\(AppBundleIdentity.executableName)",
            "Contents/Resources/LICENSE.txt",
            "Contents/Resources/THIRD_PARTY_NOTICES.md",
            signatureStatus.displayLine
        ]
    }

    @discardableResult
    private static func verifyDirectory(
        at url: URL,
        name: String,
        failures: inout [String]
    ) -> Bool {
        switch entryKind(at: url) {
        case .directory:
            return true
        case .symbolicLink:
            failures.append("\(name)に symlink は許可されません: \(url.path)")
        case .missing:
            failures.append("\(name)ディレクトリがありません: \(url.path)")
        case .regularFile, .other:
            failures.append("\(name)がディレクトリではありません: \(url.path)")
        }
        return false
    }

    @discardableResult
    private static func verifyRegularFile(
        at url: URL,
        name: String,
        failures: inout [String]
    ) -> Bool {
        switch entryKind(at: url) {
        case .regularFile:
            return true
        case .symbolicLink:
            failures.append("\(name)に symlink は許可されません: \(url.path)")
        case .missing:
            failures.append("\(name)がありません: \(url.path)")
        case .directory, .other:
            failures.append("\(name)が通常ファイルではありません: \(url.path)")
        }
        return false
    }

    @discardableResult
    private static func verifyExecutable(at url: URL, failures: inout [String]) -> Bool {
        guard verifyRegularFile(at: url, name: "実行ファイル", failures: &failures) else {
            return false
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            failures.append("実行ファイルに実行権限がありません: \(url.path)")
            return false
        }
        return true
    }

    @discardableResult
    private static func verifyContainment(
        of childURL: URL,
        in rootURL: URL,
        name: String,
        failures: inout [String]
    ) -> Bool {
        let resolvedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedChildURL = childURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPathPrefix = resolvedRootURL.path.hasSuffix("/")
            ? resolvedRootURL.path
            : resolvedRootURL.path + "/"

        guard resolvedChildURL.path.hasPrefix(rootPathPrefix) else {
            failures.append(
                "\(name)が bundle 内に収まっていません: \(childURL.path) -> \(resolvedChildURL.path)"
            )
            return false
        }
        return true
    }

    private static func entryKind(at url: URL) -> FileSystemEntryKind {
        var fileStatus = stat()
        guard lstat(url.path, &fileStatus) == 0 else {
            return .missing
        }

        switch fileStatus.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFLNK):
            return .symbolicLink
        case mode_t(S_IFDIR):
            return .directory
        case mode_t(S_IFREG):
            return .regularFile
        default:
            return .other
        }
    }

    private static func verifyInfoPlist(at url: URL, failures: inout [String]) {
        guard let data = try? Data(contentsOf: url) else {
            failures.append("Info.plist を読めません。")
            return
        }

        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard CFGetTypeID(object as CFTypeRef) == CFDictionaryGetTypeID(),
                  let plist = object as? [String: Any] else {
                failures.append("Info.plist の形式が辞書ではありません。")
                return
            }

            verifyExactString(
                key: "CFBundleExecutable",
                expected: AppBundleIdentity.executableName,
                in: plist,
                failures: &failures
            )
            verifyExactString(
                key: "CFBundlePackageType",
                expected: AppBundleIdentity.packageType,
                in: plist,
                failures: &failures
            )
            verifyExactBooleanFalse(key: "LSUIElement", in: plist, failures: &failures)
            verifyExactString(
                key: "CFBundleIdentifier",
                expected: AppBundleIdentity.bundleIdentifier,
                in: plist,
                failures: &failures
            )
            verifyExactString(
                key: "CFBundleName",
                expected: AppBundleIdentity.bundleName,
                in: plist,
                failures: &failures
            )
            verifyExactString(
                key: "CFBundleDisplayName",
                expected: AppBundleIdentity.displayName,
                in: plist,
                failures: &failures
            )
            if (plist["CFBundleShortVersionString"] as? String)?.isEmpty ?? true {
                failures.append("CFBundleShortVersionString が空です。")
            }
        } catch {
            failures.append("Info.plist を解析できません: \(error.localizedDescription)")
        }
    }

    private static func verifyExactString(
        key: String,
        expected: String,
        in plist: [String: Any],
        failures: inout [String]
    ) {
        guard let value = plist[key] else {
            failures.append("\(key) がありません。")
            return
        }
        guard CFGetTypeID(value as CFTypeRef) == CFStringGetTypeID(),
              let stringValue = value as? String else {
            failures.append("\(key) の型が string ではありません。")
            return
        }
        guard stringValue == expected else {
            failures.append("\(key) が \(expected) ではありません。")
            return
        }
    }

    private static func verifyExactBooleanFalse(
        key: String,
        in plist: [String: Any],
        failures: inout [String]
    ) {
        guard let value = plist[key] else {
            failures.append("\(key) がありません。")
            return
        }
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(),
              let booleanValue = value as? Bool else {
            failures.append("\(key) の型が Boolean ではありません。")
            return
        }
        guard booleanValue == false else {
            failures.append("\(key) が false ではありません。")
            return
        }
    }

    @discardableResult
    private static func verifyReadableNonEmptyFile(
        at url: URL,
        name: String,
        failures: inout [String]
    ) -> Bool {
        guard verifyRegularFile(at: url, name: name, failures: &failures) else {
            return false
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            failures.append("\(name) を読めないか空です。")
            return false
        }
        return true
    }

    private static func verifyCodeSignature(appURL: URL) -> CodeSignatureStatus {
        let codesignURL = URL(fileURLWithPath: "/usr/bin/codesign")
        guard FileManager.default.isExecutableFile(atPath: codesignURL.path) else {
            return CodeSignatureStatus(
                isValid: false,
                message: "codesign が見つかりません: \(codesignURL.path)"
            )
        }

        let process = Process()
        process.executableURL = codesignURL
        process.arguments = [
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            appURL.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CodeSignatureStatus(
                isValid: false,
                message: "codesign を実行できません: \(error.localizedDescription)"
            )
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = output?.isEmpty == false ? output! : "codesign が詳細を出力しませんでした。"

        guard process.terminationStatus == 0 else {
            return CodeSignatureStatus(isValid: false, message: message)
        }

        return CodeSignatureStatus(isValid: true, message: "codesign --verify --deep --strict に成功しました。")
    }
}

private enum FileSystemEntryKind {
    case missing
    case symbolicLink
    case directory
    case regularFile
    case other
}

private struct CodeSignatureStatus {
    let isValid: Bool
    let message: String

    var displayLine: String {
        if isValid {
            return "コード署名: 有効 (\(message))"
        }
        return "コード署名: 未検証 (\(message))"
    }
}

struct VerifyBundleCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let parsedOptions = try parseOptions()

        let checkedItems = try BundleVerifier.verify(
            appPath: parsedOptions.appPath,
            requireSignature: parsedOptions.requireSignature
        )
        print("アプリバンドル検証に成功しました: \(parsedOptions.appPath)")
        for item in checkedItems {
            print("- \(item)")
        }
    }

    private func parseOptions() throws -> ParsedVerifyBundleOptions {
        var requireSignature = false
        var appPath: String?

        for option in options {
            if option == "--require-signature" {
                guard !requireSignature else {
                    throw VerifyBundleOptionError.duplicateOption(option)
                }
                requireSignature = true
                continue
            }
            if option.hasPrefix("-") {
                throw VerifyBundleOptionError.unknownOption(option)
            }
            guard appPath == nil else {
                throw VerifyBundleOptionError.unexpectedArgument(option)
            }
            appPath = option
        }

        guard let appPath else {
            throw ToolError.missingValue("アプリバンドル")
        }
        return ParsedVerifyBundleOptions(appPath: appPath, requireSignature: requireSignature)
    }
}

private struct ParsedVerifyBundleOptions {
    let appPath: String
    let requireSignature: Bool
}

private enum VerifyBundleOptionError: LocalizedError {
    case unknownOption(String)
    case duplicateOption(String)
    case unexpectedArgument(String)

    var errorDescription: String? {
        switch self {
        case let .unknownOption(option):
            return "verify-bundle の未知の option です: \(option)"
        case let .duplicateOption(option):
            return "verify-bundle の option が重複しています: \(option)"
        case let .unexpectedArgument(argument):
            return "verify-bundle の余分な引数です: \(argument)"
        }
    }
}
