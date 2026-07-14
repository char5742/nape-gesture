import Darwin
import Foundation
import NapeGestureCore
import NapeGestureProductOutput

enum BundleVerifier {
    static func verify(appPath: String, requireSignature: Bool = false) throws -> [String] {
        let appURL = URL(fileURLWithPath: appPath)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = macOSURL.appendingPathComponent("nape-gesture")
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let licenseURL = resourcesURL.appendingPathComponent("LICENSE.txt")
        let noticesURL = resourcesURL.appendingPathComponent("THIRD_PARTY_NOTICES.md")
        let trackpadContractsURL = resourcesURL.appendingPathComponent(
            "TrackpadContracts",
            isDirectory: true
        )
        let trackpadBuildURL = trackpadContractsURL.appendingPathComponent(
            "25F80",
            isDirectory: true
        )
        let trackpadContractURL = resourcesURL.appendingPathComponent(
            TrackpadGestureOutputResources.contractRelativePath
        )
        let trackpadModelURL = resourcesURL.appendingPathComponent(
            TrackpadGestureOutputResources.modelRelativePath
        )
        let recognizedDockSwipeTemplatesURL = trackpadBuildURL.appendingPathComponent(
            "recognized-dockswipe-templates.json"
        )

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
        if !isRegularFile(executableURL) {
            failures.append("実行ファイルがありません: \(executableURL.path)")
        } else if !fileManager.isExecutableFile(atPath: executableURL.path) {
            failures.append("実行ファイルに実行権限がありません: \(executableURL.path)")
        }

        verifyInfoPlist(at: infoPlistURL, failures: &failures)
        verifyReadableNonEmptyFile(at: licenseURL, name: "LICENSE.txt", failures: &failures)
        verifyReadableNonEmptyFile(at: noticesURL, name: "THIRD_PARTY_NOTICES.md", failures: &failures)
        if !isDirectory(trackpadContractsURL) {
            failures.append("Contents/Resources/TrackpadContracts directoryがないかsymlinkです。")
        }
        if !isDirectory(trackpadBuildURL) {
            failures.append("Contents/Resources/TrackpadContracts/25F80 directoryがないかsymlinkです。")
        }
        verifyTrackpadResources(
            contractURL: trackpadContractURL,
            modelURL: trackpadModelURL,
            failures: &failures
        )
        verifyRecognizedDockSwipeTemplates(
            at: recognizedDockSwipeTemplatesURL,
            failures: &failures
        )
        let signatureStatus = verifyCodeSignature(appURL: appURL)
        if requireSignature, !signatureStatus.isValid {
            failures.append("コード署名検証に失敗しました: \(signatureStatus.message)")
        }

        if !failures.isEmpty {
            throw ToolError.bundleVerificationFailed(failures.joined(separator: "\n"))
        }

        return [
            "Info.plist",
            "Info.plist: LSUIElement=false",
            "Contents/MacOS/nape-gesture",
            "Contents/Resources/LICENSE.txt",
            "Contents/Resources/THIRD_PARTY_NOTICES.md",
            "Contents/Resources/TrackpadContracts/25F80/scroll-momentum-contract.json",
            "Contents/Resources/TrackpadContracts/25F80/scroll-output-model.json",
            "Contents/Resources/TrackpadContracts/25F80/recognized-dockswipe-templates.json",
            signatureStatus.displayLine
        ]
    }

    private static func isDirectory(_ url: URL) -> Bool {
        itemType(at: url) == mode_t(S_IFDIR)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        itemType(at: url) == mode_t(S_IFREG)
    }

    private static func itemType(at url: URL) -> mode_t? {
        var value = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                return -1
            }
            return Darwin.lstat(path, &value)
        }
        return result == 0 ? value.st_mode & mode_t(S_IFMT) : nil
    }

    private static func verifyInfoPlist(at url: URL, failures: inout [String]) {
        guard isRegularFile(url), let data = try? Data(contentsOf: url) else {
            failures.append("Info.plist を読めません。")
            return
        }

        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let plist = object as? [String: Any] else {
                failures.append("Info.plist の形式が辞書ではありません。")
                return
            }

            if plist["CFBundleExecutable"] as? String != "nape-gesture" {
                failures.append("CFBundleExecutable が nape-gesture ではありません。")
            }
            if plist["CFBundlePackageType"] as? String != "APPL" {
                failures.append("CFBundlePackageType が APPL ではありません。")
            }
            if plist["LSUIElement"] as? Bool != GUIAppLaunchPresenter.regularGUIApp.bundleLSUIElement {
                failures.append("LSUIElement が false ではありません。")
            }
            if plist["CFBundleIdentifier"] as? String != "dev.char5742.nape-gesture" {
                failures.append("CFBundleIdentifier が dev.char5742.nape-gesture ではありません。")
            }
            if plist["CFBundleName"] as? String != "Nape Gesture" {
                failures.append("CFBundleName が Nape Gesture ではありません。")
            }
            if plist["CFBundleDisplayName"] as? String != "Nape Gesture" {
                failures.append("CFBundleDisplayName が Nape Gesture ではありません。")
            }
            if (plist["CFBundleShortVersionString"] as? String)?.isEmpty ?? true {
                failures.append("CFBundleShortVersionString が空です。")
            }
        } catch {
            failures.append("Info.plist を解析できません: \(error.localizedDescription)")
        }
    }

    private static func verifyReadableNonEmptyFile(at url: URL, name: String, failures: inout [String]) {
        guard isRegularFile(url),
              let data = try? Data(contentsOf: url),
              !data.isEmpty
        else {
            failures.append("\(name) が存在しないか空です。")
            return
        }
    }

    private static func verifyTrackpadResources(
        contractURL: URL,
        modelURL: URL,
        failures: inout [String]
    ) {
        guard isRegularFile(contractURL),
              let contractData = try? Data(contentsOf: contractURL),
              !contractData.isEmpty
        else {
            failures.append("scroll / momentum contract resourceが存在しないか空です。")
            return
        }
        let report = TrackpadScrollMomentumContractDocumentReader.read(data: contractData)
        guard report.passed, report.document != nil else {
            failures.append(
                "scroll / momentum contract resourceが登録済みfixtureと一致しません: "
                    + report.issues.map(\.message).joined(separator: " ")
            )
            return
        }
        let capability = ProductGestureOutputCapability.validated(
            fixtureData: contractData
        )
        guard capability.isSupported, let verifiedContract = capability.contract else {
            failures.append("scroll / momentum contract resourceをproduct capabilityとして検証できません。")
            return
        }
        guard isRegularFile(modelURL),
              let modelData = try? Data(contentsOf: modelURL),
              !modelData.isEmpty
        else {
            failures.append("scroll output model resourceが存在しないか空です。")
            return
        }
        guard TrackpadScrollOutputModelFixtureReader.read(
            modelData: modelData,
            contract: verifiedContract
        ) != nil else {
            failures.append("scroll output model resourceのSHA、式、sample count、source contractが一致しません。")
            return
        }
    }

    private static func verifyRecognizedDockSwipeTemplates(
        at url: URL,
        failures: inout [String]
    ) {
        guard isRegularFile(url),
              let data = try? Data(contentsOf: url),
              !data.isEmpty
        else {
            failures.append("recognized DockSwipe templates resourceが存在しないか空です。")
            return
        }
        guard TrackpadDriverEventCaptureManifest.sha256HexDigest(of: data)
            == "852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6"
        else {
            failures.append(
                "recognized DockSwipe templates resourceのSHA-256が登録済みfixtureと一致しません。"
            )
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
        } catch {
            return CodeSignatureStatus(
                isValid: false,
                message: "codesign を実行できません: \(error.localizedDescription)"
            )
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
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
        var requireSignature = false
        var appPath: String?
        for option in options {
            if option == "--require-signature" {
                guard !requireSignature else {
                    throw ToolError.invalidValue("--require-signature", "重複しています。")
                }
                requireSignature = true
            } else if option.hasPrefix("--") {
                throw ToolError.invalidValue("verify-bundle option", option)
            } else if appPath == nil {
                appPath = option
            } else {
                throw ToolError.invalidValue("アプリバンドル", "複数pathは指定できません。")
            }
        }
        guard let appPath else {
            throw ToolError.missingValue("アプリバンドル")
        }

        let checkedItems = try BundleVerifier.verify(appPath: appPath, requireSignature: requireSignature)
        print("アプリバンドル検証に成功しました: \(appPath)")
        for item in checkedItems {
            print("- \(item)")
        }
    }
}
