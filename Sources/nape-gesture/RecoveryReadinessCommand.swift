import Foundation

struct RecoveryReadinessCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        if options.contains("--json") && options.contains("--markdown") {
            throw ToolError.invalidValue("--json", "--markdown と併用できません。")
        }

        let report = RecoveryReadinessReport.make()
        if options.contains("--assert") {
            try report.assertReady()
        }

        let output: String
        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            output = String(decoding: try encoder.encode(report), as: UTF8.self)
        } else if options.contains("--markdown") {
            output = report.markdown
        } else {
            output = report.text
        }

        if let outputPath = try value("--out") {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try output.write(to: url, atomically: true, encoding: .utf8)
        } else {
            print(output)
        }
    }

    private func value(_ name: String) throws -> String? {
        guard let index = options.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = options.index(after: index)
        guard options.indices.contains(valueIndex) else {
            throw ToolError.missingValue(name)
        }
        return options[valueIndex]
    }
}

private struct RecoveryReadinessReport: Codable {
    var schemaVersion: Int
    var reportKind: String
    var scope: String
    var relatedIssues: [Int]
    var completionState: String
    var humanWorkPolicy: RecoveryHumanWorkPolicy
    var summary: RecoveryReadinessSummary
    var scenarios: [RecoveryReadinessScenario]

    static func make() -> RecoveryReadinessReport {
        let scenarios = RecoveryReadinessScenario.catalog
        return RecoveryReadinessReport(
            schemaVersion: 1,
            reportKind: "runtimeRecoveryReadiness",
            scope: "Issue #13 の復旧要件を、機械で固定済みの契約と実機・外部状態の最終証跡に分ける。",
            relatedIssues: [13, 16],
            completionState: "machine-readiness-ready-external-evidence-pending",
            humanWorkPolicy: RecoveryHumanWorkPolicy(
                humanWorkIsLastResort: true,
                automationPreference: "dry-run、core tests、doctor、computer-use、保存済みログ解析で代替できる確認を先に埋める。",
                needHumanLabelRule: "`need:human` は、実デバイス抜き差し、Mac スリープ復帰、TCC 変更など、人が実際に作業する必要が残る Issue / PR にだけ付ける。",
                computerUseBoundary: "System Settings の表示や GUI 操作は computer-use を優先する。ただし物理デバイス操作、ログイン資格情報、ユーザー判断が必要な場合は人間作業として扱う。"
            ),
            summary: RecoveryReadinessSummary(scenarios: scenarios),
            scenarios: scenarios
        )
    }

    func assertReady() throws {
        var failures: [String] = []
        let expectedScenarioIDs = Set([
            "sleep-wake-runtime-retry",
            "target-device-disconnect",
            "target-device-reconnect",
            "accessibility-permission-change",
            "input-monitoring-permission-change",
            "recoverable-runtime-failure",
            "human-fix-required-failure"
        ])
        let expectedNeedHumanCandidateIDs = Set([
            "sleep-wake-runtime-retry",
            "target-device-disconnect",
            "target-device-reconnect",
            "accessibility-permission-change",
            "input-monitoring-permission-change"
        ])
        let actualScenarioIDs = Set(scenarios.map(\.id))
        let actualNeedHumanCandidateIDs = Set(
            scenarios
                .filter(\.needHumanLabelAppliesWhenIssueRequiresAction)
                .map(\.id)
        )

        if schemaVersion != 1 {
            failures.append("schemaVersion は 1 である必要があります。")
        }
        if reportKind != "runtimeRecoveryReadiness" {
            failures.append("reportKind は runtimeRecoveryReadiness である必要があります。")
        }
        if !expectedScenarioIDs.isSubset(of: actualScenarioIDs) {
            let missing = expectedScenarioIDs.subtracting(actualScenarioIDs).sorted().joined(separator: ", ")
            failures.append("復旧シナリオが不足しています: \(missing)")
        }
        if !humanWorkPolicy.humanWorkIsLastResort {
            failures.append("人間作業は最後の手段として明示する必要があります。")
        }
        if !humanWorkPolicy.needHumanLabelRule.contains("need:human") {
            failures.append("need:human ラベルの運用境界を明示してください。")
        }
        if actualNeedHumanCandidateIDs != expectedNeedHumanCandidateIDs {
            let missing = expectedNeedHumanCandidateIDs.subtracting(actualNeedHumanCandidateIDs).sorted().joined(separator: ", ")
            let unexpected = actualNeedHumanCandidateIDs.subtracting(expectedNeedHumanCandidateIDs).sorted().joined(separator: ", ")
            failures.append("need:human 候補シナリオが期待値と一致しません。missing=[\(missing)] unexpected=[\(unexpected)]")
        }
        if scenarios.contains(where: { $0.completionState == "completed" }) {
            failures.append("外部証跡が残る recovery-readiness で completed を出してはいけません。")
        }

        for scenario in scenarios {
            if scenario.relatedIssues.contains(13) == false {
                failures.append("\(scenario.id) は Issue #13 との対応を持つ必要があります。")
            }
            if scenario.machineEvidence.isEmpty {
                failures.append("\(scenario.id) の machineEvidence が空です。")
            }
            if scenario.machineAssertions.isEmpty {
                failures.append("\(scenario.id) の machineAssertions が空です。")
            }
            if scenario.requiresExternalEvidence && scenario.externalEvidenceRequired.isEmpty {
                failures.append("\(scenario.id) の externalEvidenceRequired が空です。")
            }
            if scenario.requiresExternalEvidence
                && scenario.completionState != "machine-readiness-ready-external-evidence-pending" {
                failures.append("\(scenario.id) は外部証跡待ちとして扱う必要があります。")
            }
        }

        if summary.scenarioCount != scenarios.count {
            failures.append("summary.scenarioCount が scenarios.count と一致しません。")
        }
        if summary.externalEvidencePendingScenarioCount != scenarios.filter(\.requiresExternalEvidence).count {
            failures.append("summary.externalEvidencePendingScenarioCount が scenarios と一致しません。")
        }
        if summary.needHumanLabelCandidateScenarioCount != scenarios.filter(\.needHumanLabelAppliesWhenIssueRequiresAction).count {
            failures.append("summary.needHumanLabelCandidateScenarioCount が scenarios と一致しません。")
        }

        guard failures.isEmpty else {
            throw RecoveryReadinessAssertionError(failures: failures)
        }
    }

    var text: String {
        var lines = [
            "Runtime recovery readiness",
            "状態: \(completionState)",
            "対象 Issue: \(relatedIssues.map { "#\($0)" }.joined(separator: ", "))",
            "シナリオ数: \(summary.scenarioCount)",
            "外部証跡待ち: \(summary.externalEvidencePendingScenarioCount)",
            "need:human 候補: \(summary.needHumanLabelCandidateScenarioCount)",
            "",
            "方針:",
            "- \(humanWorkPolicy.automationPreference)",
            "- \(humanWorkPolicy.needHumanLabelRule)",
            "- \(humanWorkPolicy.computerUseBoundary)",
            "",
            "シナリオ:"
        ]

        for scenario in scenarios {
            lines.append("- \(scenario.id): \(scenario.title) [\(scenario.completionState)]")
            lines.append("  機械証跡: \(scenario.machineEvidence.joined(separator: " / "))")
            lines.append("  残る外部証跡: \(scenario.externalEvidenceRequired.joined(separator: " / "))")
        }

        return lines.joined(separator: "\n")
    }

    var markdown: String {
        var lines = [
            "# Runtime recovery readiness",
            "",
            "- schemaVersion: `\(schemaVersion)`",
            "- 状態: `\(completionState)`",
            "- 対象 Issue: \(relatedIssues.map { "#\($0)" }.joined(separator: ", "))",
            "- 人間作業方針: \(humanWorkPolicy.automationPreference)",
            "- `need:human`: \(humanWorkPolicy.needHumanLabelRule)",
            "",
            "## Summary",
            "",
            "| 項目 | 値 |",
            "| --- | --- |",
            "| シナリオ数 | \(summary.scenarioCount) |",
            "| 機械 readiness 済み | \(summary.machineReadinessScenarioCount) |",
            "| 外部証跡待ち | \(summary.externalEvidencePendingScenarioCount) |",
            "| need:human 候補 | \(summary.needHumanLabelCandidateScenarioCount) |",
            "",
            "## Scenarios",
            "",
            "| ID | 状態 | 機械証跡 | 残る外部証跡 | need:human |",
            "| --- | --- | --- | --- | --- |"
        ]

        for scenario in scenarios {
            lines.append(
                "| `\(scenario.id)` | \(scenario.completionState) | \(scenario.machineEvidence.joined(separator: "<br>")) | \(scenario.externalEvidenceRequired.joined(separator: "<br>")) | \(scenario.needHumanLabelAppliesWhenIssueRequiresAction ? "候補" : "不要") |"
            )
        }

        lines.append("")
        lines.append("## Boundary")
        lines.append("")
        lines.append(humanWorkPolicy.computerUseBoundary)
        lines.append("このレポートはスリープ、抜き差し、TCC 変更そのものの実機ログではありません。")
        return lines.joined(separator: "\n")
    }
}

private struct RecoveryHumanWorkPolicy: Codable {
    var humanWorkIsLastResort: Bool
    var automationPreference: String
    var needHumanLabelRule: String
    var computerUseBoundary: String
}

private struct RecoveryReadinessSummary: Codable {
    var scenarioCount: Int
    var machineReadinessScenarioCount: Int
    var externalEvidencePendingScenarioCount: Int
    var needHumanLabelCandidateScenarioCount: Int

    init(scenarios: [RecoveryReadinessScenario]) {
        scenarioCount = scenarios.count
        machineReadinessScenarioCount = scenarios.filter(\.machineReadinessReady).count
        externalEvidencePendingScenarioCount = scenarios.filter(\.requiresExternalEvidence).count
        needHumanLabelCandidateScenarioCount = scenarios.filter(\.needHumanLabelAppliesWhenIssueRequiresAction).count
    }
}

private struct RecoveryReadinessScenario: Codable {
    var id: String
    var title: String
    var relatedIssues: [Int]
    var concern: String
    var machineEvidence: [String]
    var machineAssertions: [String]
    var externalEvidenceRequired: [String]
    var requiresExternalEvidence: Bool
    var needHumanLabelAppliesWhenIssueRequiresAction: Bool
    var machineReadinessReady: Bool
    var completionState: String

    static let catalog: [RecoveryReadinessScenario] = [
        RecoveryReadinessScenario(
            id: "sleep-wake-runtime-retry",
            title: "スリープ前停止と wake 後遅延再試行",
            relatedIssues: [13, 16],
            concern: "スリープ中に runtime を保持せず、wake 後に必要な場合だけ自動再試行する。",
            machineEvidence: [
                "RuntimeRecoveryState core tests",
                "RuntimeStatusPresenter core tests",
                "NSWorkspace willSleep / didWake observer wiring"
            ],
            machineAssertions: [
                "スリープ前に runtime 停止を要求する",
                "スリープ中は既存の再試行予約を破棄する",
                "wake 後は遅延して `.automaticRetry(.wake)` を消費する"
            ],
            externalEvidenceRequired: [
                "実 Mac のスリープ復帰ログ",
                "常駐 UI のスリープ待機から復旧までの観測",
                "復帰後の `doctor --probe-hid --json --assert-runtime-ready`"
            ],
            requiresExternalEvidence: true,
            needHumanLabelAppliesWhenIssueRequiresAction: true,
            machineReadinessReady: true,
            completionState: "machine-readiness-ready-external-evidence-pending"
        ),
        RecoveryReadinessScenario(
            id: "target-device-disconnect",
            title: "対象デバイス消失時の停止と再試行待機",
            relatedIssues: [13, 16],
            concern: "Nape Pro など対象デバイスが消えた時に通常入力を壊さず、対象不在を診断できる。",
            machineEvidence: [
                "RuntimeRecoveryState `.targetDeviceNotFound` retry test",
                "doctor `targetDeviceDiagnostics`",
                "devices --all --json"
            ],
            machineAssertions: [
                "targetDevice.notFound を runtime ready failure として出す",
                "自動復旧可能な targetDeviceNotFound は再試行対象にする",
                "対象 matcher 不足は人間修正が必要な失敗として再試行しない"
            ],
            externalEvidenceRequired: [
                "実デバイス抜線時の runtime ログ",
                "対象不在時の常駐 UI 表示",
                "抜線後に通常マウス入力を壊していない target log"
            ],
            requiresExternalEvidence: true,
            needHumanLabelAppliesWhenIssueRequiresAction: true,
            machineReadinessReady: true,
            completionState: "machine-readiness-ready-external-evidence-pending"
        ),
        RecoveryReadinessScenario(
            id: "target-device-reconnect",
            title: "対象デバイス再接続後の復旧",
            relatedIssues: [13, 16],
            concern: "対象デバイスが戻った時に、手動停止を尊重しつつ自動再試行で復旧できる。",
            machineEvidence: [
                "RuntimeRecoveryState retry consumption tests",
                "RuntimeRecoveryState manual stop cancellation tests",
                "doctor --probe-hid --json"
            ],
            machineAssertions: [
                "ready 時刻で pendingRetry を消費する",
                "手動停止後は wake / reconnect 相当の自動再試行を開始しない",
                "HID probe 成功を runtime ready の前提にする"
            ],
            externalEvidenceRequired: [
                "実デバイス再接続後の HID inventory 差分",
                "再接続後の runtime 再開ログ",
                "再開後の gesture / normal input target log"
            ],
            requiresExternalEvidence: true,
            needHumanLabelAppliesWhenIssueRequiresAction: true,
            machineReadinessReady: true,
            completionState: "machine-readiness-ready-external-evidence-pending"
        ),
        RecoveryReadinessScenario(
            id: "accessibility-permission-change",
            title: "アクセシビリティ権限変更後の復旧導線",
            relatedIssues: [13, 16],
            concern: "権限が未許可になった時に、付与対象と System Settings 導線を誤らない。",
            machineEvidence: [
                "PermissionRecoveryPresenter core tests",
                "doctor `accessibility.missing` failure code",
                "runtimeIdentity permission target"
            ],
            machineAssertions: [
                "未許可時だけアクセシビリティ設定導線を必須表示する",
                "権限変更後の再起動案内を表示する",
                "runtimeIdentity の bundle ID / executable path を診断へ出す"
            ],
            externalEvidenceRequired: [
                "TCC 許可変更後の `doctor --json` 差分",
                "System Settings 上の許可対象確認",
                "変更後の再起動と runtime ready 確認"
            ],
            requiresExternalEvidence: true,
            needHumanLabelAppliesWhenIssueRequiresAction: true,
            machineReadinessReady: true,
            completionState: "machine-readiness-ready-external-evidence-pending"
        ),
        RecoveryReadinessScenario(
            id: "input-monitoring-permission-change",
            title: "入力監視権限変更後の復旧導線",
            relatedIssues: [13, 16],
            concern: "IOHID 開始失敗を入力監視境界として診断し、復旧手順を出す。",
            machineEvidence: [
                "PermissionRecoveryPresenter core tests",
                "doctor HID probe failure code",
                "IOReturnDiagnostic remediation"
            ],
            machineAssertions: [
                "入力監視未判定を許可済みと混同しない",
                "HID probe 未実行を runtime ready failure として出す",
                "HID probe 失敗時に remediation を出す"
            ],
            externalEvidenceRequired: [
                "入力監視 TCC 変更後の HID probe 結果",
                "System Settings 上の許可対象確認",
                "変更後の再起動と runtime ready 確認"
            ],
            requiresExternalEvidence: true,
            needHumanLabelAppliesWhenIssueRequiresAction: true,
            machineReadinessReady: true,
            completionState: "machine-readiness-ready-external-evidence-pending"
        ),
        RecoveryReadinessScenario(
            id: "recoverable-runtime-failure",
            title: "回復可能な runtime 失敗の自動再試行",
            relatedIssues: [13, 16],
            concern: "一時的な event tap / HID / target 不在を、手動修正なしで再試行する。",
            machineEvidence: [
                "RuntimeRecoveryState recoverable failure tests",
                "StatusApp retry timer wiring",
                "NapeGestureRuntime recovery failure kind mapping"
            ],
            machineAssertions: [
                "accessibilityPermissionMissing / eventTapCreationFailed / hidAccessUnavailable / targetDeviceNotFound を自動再試行対象にする",
                "自動再試行中は緊急停止と停止を有効にする",
                "runtime health refresh の失敗を recovery state に記録する"
            ],
            externalEvidenceRequired: [
                "実 runtime での一時失敗ログ",
                "復旧後の runtime event target log"
            ],
            requiresExternalEvidence: true,
            needHumanLabelAppliesWhenIssueRequiresAction: false,
            machineReadinessReady: true,
            completionState: "machine-readiness-ready-external-evidence-pending"
        ),
        RecoveryReadinessScenario(
            id: "human-fix-required-failure",
            title: "人間修正が必要な失敗の自動再試行禁止",
            relatedIssues: [13, 16],
            concern: "設定不正や matcher 未設定を無限再試行せず、修正導線へ寄せる。",
            machineEvidence: [
                "RuntimeRecoveryState human fix required tests",
                "SettingsValidator",
                "doctor runtimeReadiness failure codes"
            ],
            machineAssertions: [
                "invalidSettings / targetDeviceMatcherMissing / unrecoverable は pendingRetry を作らない",
                "設定保存または手動開始で自動再試行を再有効化する",
                "doctor は settings.invalid / targetDevice.matcherMissing を構造化する"
            ],
            externalEvidenceRequired: [
                "設定 UI または config 修正後の再実行ログ"
            ],
            requiresExternalEvidence: false,
            needHumanLabelAppliesWhenIssueRequiresAction: false,
            machineReadinessReady: true,
            completionState: "machine-readiness-ready"
        )
    ]
}

private struct RecoveryReadinessAssertionError: LocalizedError {
    var failures: [String]

    var errorDescription: String? {
        "runtime recovery readiness の検証に失敗しました。\n" + failures.map { "- \($0)" }.joined(separator: "\n")
    }
}
