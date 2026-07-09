import Foundation
import NapeGestureCore

enum BundleVerifier {
    static func verify(appPath: String, requireSignature: Bool = false) throws -> [String] {
        let appURL = URL(fileURLWithPath: appPath)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = macOSURL.appendingPathComponent(AppBundleIdentity.executableName)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let licenseURL = resourcesURL.appendingPathComponent("LICENSE.txt")
        let noticesURL = resourcesURL.appendingPathComponent("THIRD_PARTY_NOTICES.md")

        var failures: [String] = []
        let fileManager = FileManager.default

        if !isDirectory(appURL) {
            failures.append("アプリバンドルがディレクトリとして存在しません: \(appURL.path)")
        }
        if !isDirectory(contentsURL) {
            failures.append("Contents ディレクトリがありません。")
        }
        if !isDirectory(macOSURL) {
            failures.append("Contents/MacOS ディレクトリがありません。")
        }
        if !isDirectory(resourcesURL) {
            failures.append("Contents/Resources ディレクトリがありません。")
        }
        if !fileManager.fileExists(atPath: executableURL.path) {
            failures.append("実行ファイルがありません: \(executableURL.path)")
        } else if !fileManager.isExecutableFile(atPath: executableURL.path) {
            failures.append("実行ファイルに実行権限がありません: \(executableURL.path)")
        }

        verifyInfoPlist(at: infoPlistURL, failures: &failures)
        verifyReadableNonEmptyFile(at: licenseURL, name: "LICENSE.txt", failures: &failures)
        verifyReadableNonEmptyFile(at: noticesURL, name: "THIRD_PARTY_NOTICES.md", failures: &failures)
        let signatureStatus = verifyCodeSignature(appURL: appURL)
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

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private static func verifyInfoPlist(at url: URL, failures: inout [String]) {
        guard let data = try? Data(contentsOf: url) else {
            failures.append("Info.plist を読めません。")
            return
        }

        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let plist = object as? [String: Any] else {
                failures.append("Info.plist の形式が辞書ではありません。")
                return
            }

            if plist["CFBundleExecutable"] as? String != AppBundleIdentity.executableName {
                failures.append("CFBundleExecutable が \(AppBundleIdentity.executableName) ではありません。")
            }
            if plist["CFBundlePackageType"] as? String != AppBundleIdentity.packageType {
                failures.append("CFBundlePackageType が \(AppBundleIdentity.packageType) ではありません。")
            }
            if plist["LSUIElement"] as? Bool != GUIAppLaunchPresenter.regularGUIApp.bundleLSUIElement {
                failures.append("LSUIElement が false ではありません。")
            }
            if plist["CFBundleIdentifier"] as? String != AppBundleIdentity.bundleIdentifier {
                failures.append("CFBundleIdentifier が \(AppBundleIdentity.bundleIdentifier) ではありません。")
            }
            if plist["CFBundleName"] as? String != AppBundleIdentity.bundleName {
                failures.append("CFBundleName が \(AppBundleIdentity.bundleName) ではありません。")
            }
            if plist["CFBundleDisplayName"] as? String != AppBundleIdentity.displayName {
                failures.append("CFBundleDisplayName が \(AppBundleIdentity.displayName) ではありません。")
            }
            if (plist["CFBundleShortVersionString"] as? String)?.isEmpty ?? true {
                failures.append("CFBundleShortVersionString が空です。")
            }
        } catch {
            failures.append("Info.plist を解析できません: \(error.localizedDescription)")
        }
    }

    private static func verifyReadableNonEmptyFile(at url: URL, name: String, failures: inout [String]) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            failures.append("\(name) が存在しないか空です。")
            return
        }
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
        let requireSignature = options.contains("--require-signature")
        let paths = options.filter { !$0.hasPrefix("--") }
        guard paths.count == 1, let appPath = paths.first else {
            throw ToolError.missingValue("アプリバンドル")
        }

        let checkedItems = try BundleVerifier.verify(appPath: appPath, requireSignature: requireSignature)
        print("アプリバンドル検証に成功しました: \(appPath)")
        for item in checkedItems {
            print("- \(item)")
        }
    }
}
