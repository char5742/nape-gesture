import Foundation
import IOKit
import NapeGestureCore

struct DoctorCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let benchmarkEvents = try intValue("--benchmark-events", defaultValue: 50_000)
        guard benchmarkEvents > 0 else {
            throw ToolError.invalidValue("--benchmark-events", String(benchmarkEvents))
        }

        let loaded = try SettingsStore.loadRuntimeSettings(from: options, validate: false)
        let report = makeReport(
            configPath: loaded.path,
            settings: loaded.settings,
            shouldProbeHID: options.contains("--probe-hid"),
            benchmarkEvents: benchmarkEvents
        )
        let shouldAssertRuntimeReady = options.contains("--assert-runtime-ready")

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(format(report))
        }

        if shouldAssertRuntimeReady && !report.runtimeReadinessFailures.isEmpty {
            fflush(stdout)
            throw DoctorRuntimeReadyAssertionError(failures: report.runtimeReadinessFailures)
        }
    }

    private func makeReport(
        configPath: String,
        settings: NapeGestureSettings,
        shouldProbeHID: Bool,
        benchmarkEvents: Int
    ) -> DoctorReport {
        var findings: [String] = []
        let runtimeIdentity = RuntimeIdentity.current
        let settingsValidationIssues = SettingsValidator.issues(for: settings)
        if !settingsValidationIssues.isEmpty {
            findings.append("設定ファイルに不正な値があります。`check-config` で詳細を確認して修正してください。")
        }
        let accessibilityTrusted = AccessibilityPermission.isTrusted
        if !accessibilityTrusted {
            findings.append("アクセシビリティ権限が未許可です。`run`、`log`、実イベント投稿は開始できません。")
            findings.append("権限付与対象を確認してください: \(runtimeIdentity.permissionTargetDescription)")
        }

        let inventory = makeInventory(settings: settings, findings: &findings)
        let probe = shouldProbeHID
            ? makeHIDProbe(settings: settings, matchedDevices: inventory.matchedDevices, findings: &findings)
            : DoctorHIDProbe(requested: false, succeeded: nil, error: nil, remediation: nil)
        let benchmark = BenchmarkRunner.run(events: benchmarkEvents)

        if findings.isEmpty {
            findings.append("診断範囲では致命的な問題は見つかりませんでした。実機操作と Spaces / Mission Control の画面挙動は別途検証してください。")
        }

        return DoctorReport(
            configPath: configPath,
            runtimeIdentity: runtimeIdentity,
            killSwitchShortcut: KillSwitchShortcut.displayName,
            accessibilityTrusted: accessibilityTrusted,
            requireMatchingTargetDevice: settings.requireMatchingTargetDevice,
            targetDeviceAssociationWindow: settings.targetDeviceAssociation.associationWindow,
            configuredTargetMatchers: settings.targetDevices.count,
            allHIDDeviceCount: inventory.allDeviceCount,
            pointingDeviceCount: inventory.pointingDeviceCount,
            matchedTargetDeviceCount: inventory.matchedDevices.count,
            matchedTargetDevices: inventory.matchedDevices,
            inventoryError: inventory.error,
            hidProbe: probe,
            benchmark: benchmark,
            settingsValidationIssues: settingsValidationIssues,
            findings: findings
        )
    }

    private func makeInventory(settings: NapeGestureSettings, findings: inout [String]) -> DoctorInventory {
        do {
            let allDevices = try DeviceInventory.allDevices()
            let pointingDevices = try DeviceInventory.pointingDevices()
            let matchedDevices = settings.targetDevices.isEmpty
                ? []
                : allDevices.filter { device in
                    settings.targetDevices.contains { $0.matches(device) }
                }

            if settings.requireMatchingTargetDevice && settings.targetDevices.isEmpty {
                findings.append("対象デバイス一致が必須ですが、対象デバイス条件が空です。")
            } else if settings.requireMatchingTargetDevice && matchedDevices.isEmpty {
                findings.append("設定に一致する対象デバイスが見つかりません。`devices --all --json` と `hid-log` で識別情報を確認してください。")
            } else if !settings.targetDevices.isEmpty && matchedDevices.isEmpty {
                findings.append("対象条件はありますが現在一致デバイスは未検出です。必須ではないため起動は止めません。")
            }

            return DoctorInventory(
                allDeviceCount: allDevices.count,
                pointingDeviceCount: pointingDevices.count,
                matchedDevices: matchedDevices,
                error: nil
            )
        } catch {
            let message = describe(error)
            findings.append("HID デバイス一覧の取得に失敗しました: \(message)")
            return DoctorInventory(
                allDeviceCount: nil,
                pointingDeviceCount: nil,
                matchedDevices: [],
                error: message
            )
        }
    }

    private func makeHIDProbe(
        settings: NapeGestureSettings,
        matchedDevices: [DeviceIdentity],
        findings: inout [String]
    ) -> DoctorHIDProbe {
        let gate = SharedTargetDeviceGate(
            configuration: TargetDeviceGateConfiguration(settings: settings)
        )
        let monitor = HIDInputMonitor(settings: settings, gate: gate, matchedDevices: matchedDevices)

        do {
            try monitor.start()
            monitor.stop()
            return DoctorHIDProbe(requested: true, succeeded: true, error: nil, remediation: nil)
        } catch {
            monitor.stop()
            let message = describe(error)
            let remediation = remediation(for: error)
            findings.append("HID 入力監視を開始できませんでした: \(message)")
            return DoctorHIDProbe(
                requested: true,
                succeeded: false,
                error: message,
                remediation: remediation
            )
        }
    }

    private func intValue(_ name: String, defaultValue: Int) throws -> Int {
        guard options.contains(name) else {
            return defaultValue
        }
        let raw = try SettingsStore.requiredValue(for: name, in: options)
        guard let value = Int(raw) else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func remediation(for error: Error) -> String? {
        guard case let ToolError.hidManagerOpenFailed(code) = error else {
            return nil
        }
        switch code {
        case kIOReturnNotPermitted:
            return "システム設定 > プライバシーとセキュリティ > 入力監視で、Codex、実行元ターミナル、または NapeGesture.app を許可してから再起動してください。"
        case kIOReturnExclusiveAccess:
            return "`hid-log --all` ではなく、`devices --all --json` で確認した vendor/product/usage 条件を指定してください。"
        default:
            return IOReturnDiagnostic.describe(code)
        }
    }

    private func format(_ report: DoctorReport) -> String {
        var lines = [
            "診断結果",
            "設定ファイル: \(report.configPath)",
            "プロセス名: \(report.runtimeIdentity.processName)",
            "実行ファイル: \(report.runtimeIdentity.executablePath)",
            "バンドルID: \(report.runtimeIdentity.bundleIdentifier ?? "なし")",
            "バンドルパス: \(report.runtimeIdentity.bundlePath)",
            "アプリバンドル実行: \(report.runtimeIdentity.isAppBundle ? "はい" : "いいえ")",
            "キルスイッチ: \(report.killSwitchShortcut)",
            "アクセシビリティ: \(report.accessibilityTrusted ? "許可済み" : "未許可")",
            "対象デバイス一致必須: \(report.requireMatchingTargetDevice ? "はい" : "いいえ")",
            "対象入力の紐づけ秒: \(report.targetDeviceAssociationWindow)",
            "対象デバイス条件数: \(report.configuredTargetMatchers)",
            "HIDデバイス数: \(formatOptional(report.allHIDDeviceCount))",
            "ポインティングデバイス数: \(formatOptional(report.pointingDeviceCount))",
            "一致対象デバイス数: \(report.matchedTargetDeviceCount)"
        ]

        for device in report.matchedTargetDevices {
            lines.append("- \(device.displayName) stableId=\(device.stableID)")
        }

        if let error = report.inventoryError {
            lines.append("HID一覧エラー: \(error)")
        }

        if report.hidProbe.requested {
            lines.append("HID入力監視プローブ: \(report.hidProbe.succeeded == true ? "成功" : "失敗")")
            if let error = report.hidProbe.error {
                lines.append("HID入力監視エラー: \(error)")
            }
            if let remediation = report.hidProbe.remediation {
                lines.append("復旧手順: \(remediation)")
            }
        } else {
            lines.append("HID入力監視プローブ: 未実行")
        }

        lines.append(BenchmarkFormatter.format(report.benchmark))
        if !report.settingsValidationIssues.isEmpty {
            lines.append("設定バリデーション:")
            lines.append(contentsOf: report.settingsValidationIssues.map { "- \($0.path): \($0.message)" })
        }
        lines.append("所見:")
        lines.append(contentsOf: report.findings.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }

    private func formatOptional(_ value: Int?) -> String {
        value.map(String.init) ?? "取得失敗"
    }
}

private struct DoctorInventory {
    var allDeviceCount: Int?
    var pointingDeviceCount: Int?
    var matchedDevices: [DeviceIdentity]
    var error: String?
}

private struct DoctorReport: Codable {
    var configPath: String
    var runtimeIdentity: RuntimeIdentity
    var killSwitchShortcut: String
    var accessibilityTrusted: Bool
    var requireMatchingTargetDevice: Bool
    var targetDeviceAssociationWindow: TimeInterval
    var configuredTargetMatchers: Int
    var allHIDDeviceCount: Int?
    var pointingDeviceCount: Int?
    var matchedTargetDeviceCount: Int
    var matchedTargetDevices: [DeviceIdentity]
    var inventoryError: String?
    var hidProbe: DoctorHIDProbe
    var benchmark: BenchmarkReport
    var settingsValidationIssues: [SettingsValidationIssue]
    var findings: [String]

    var runtimeReadinessFailures: [String] {
        var failures: [String] = []
        if !settingsValidationIssues.isEmpty {
            failures.append("設定ファイルに不正な値があります。")
        }
        if !accessibilityTrusted {
            failures.append("アクセシビリティ権限が未許可です。")
        }
        if inventoryError != nil {
            failures.append("HID デバイス一覧を取得できません。")
        }
        if requireMatchingTargetDevice && configuredTargetMatchers == 0 {
            failures.append("対象デバイス一致が必須ですが、対象デバイス条件が空です。")
        }
        if requireMatchingTargetDevice && matchedTargetDeviceCount == 0 {
            failures.append("対象デバイス一致が必須ですが、現在一致デバイスがありません。")
        }
        if !hidProbe.requested {
            failures.append("HID 入力監視プローブが未実行です。`--probe-hid` を付けてください。")
        } else if hidProbe.succeeded != true {
            failures.append("HID 入力監視プローブに失敗しました。")
        }
        return failures
    }
}

private struct DoctorHIDProbe: Codable {
    var requested: Bool
    var succeeded: Bool?
    var error: String?
    var remediation: String?
}

private struct DoctorRuntimeReadyAssertionError: LocalizedError {
    var failures: [String]

    var errorDescription: String? {
        let details = failures.map { "- \($0)" }.joined(separator: "\n")
        return """
        runtime ready 診断を満たしていません。
        \(details)
        """
    }
}
