import Foundation
import NapeGestureCore

struct BundleAppCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let outputPath = try outputPath()
        let executablePath = try currentExecutablePath()
        let appURL = URL(fileURLWithPath: outputPath)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let bundledExecutableURL = macOSURL.appendingPathComponent("nape-gesture")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: appURL.path) {
            guard options.contains("--replace") else {
                throw ToolError.bundleOutputAlreadyExists(appURL.path)
            }
            try fileManager.removeItem(at: appURL)
        }

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: URL(fileURLWithPath: executablePath), to: bundledExecutableURL)
        try infoPlistData().write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)
        try writeDistributionResources(to: resourcesURL)
        let checkedItems = try BundleVerifier.verify(appPath: appURL.path)

        print("アプリバンドルを作成しました: \(appURL.path)")
        print("検証済み:")
        for item in checkedItems {
            print("- \(item)")
        }
    }

    private func outputPath() throws -> String {
        if options.contains("--out") {
            return try SettingsStore.requiredValue(for: "--out", in: options)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NapeGesture.app", isDirectory: true)
            .path
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
            fileName: "LICENSE",
            fallback: fallbackLicenseText
        ).write(to: resourcesURL.appendingPathComponent("LICENSE.txt"), options: .atomic)

        try distributionResourceData(
            fileName: "THIRD_PARTY_NOTICES.md",
            fallback: fallbackThirdPartyNotices
        ).write(to: resourcesURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"), options: .atomic)
    }

    private func distributionResourceData(fileName: String, fallback: String) -> Data {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            return data
        }
        return Data(fallback.utf8)
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

        Mac Mouse Fix のソースコード、定数、状態遷移、調整値はこのプロジェクトへコピーしていません。
        """
    }
}
