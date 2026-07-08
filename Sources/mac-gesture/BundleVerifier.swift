import Foundation

enum BundleVerifier {
    static func verify(appPath: String) throws -> [String] {
        let appURL = URL(fileURLWithPath: appPath)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = macOSURL.appendingPathComponent("mac-gesture")
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

        if !failures.isEmpty {
            throw ToolError.bundleVerificationFailed(failures.joined(separator: "\n"))
        }

        return [
            "Info.plist",
            "Contents/MacOS/mac-gesture",
            "Contents/Resources/LICENSE.txt",
            "Contents/Resources/THIRD_PARTY_NOTICES.md"
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

            if plist["CFBundleExecutable"] as? String != "mac-gesture" {
                failures.append("CFBundleExecutable が mac-gesture ではありません。")
            }
            if plist["CFBundlePackageType"] as? String != "APPL" {
                failures.append("CFBundlePackageType が APPL ではありません。")
            }
            if plist["LSUIElement"] as? Bool != true {
                failures.append("LSUIElement が true ではありません。")
            }
            if (plist["CFBundleIdentifier"] as? String)?.isEmpty ?? true {
                failures.append("CFBundleIdentifier が空です。")
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
}

struct VerifyBundleCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        guard let appPath = options.first, !appPath.hasPrefix("--") else {
            throw ToolError.missingValue("アプリバンドル")
        }

        let checkedItems = try BundleVerifier.verify(appPath: appPath)
        print("アプリバンドル検証に成功しました: \(appPath)")
        for item in checkedItems {
            print("- \(item)")
        }
    }
}
