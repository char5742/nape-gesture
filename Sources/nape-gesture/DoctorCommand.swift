import Foundation
import IOKit
import NapeGestureCore
import NapeGestureProductOutput

struct DoctorCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        try validateOptions()
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

    private func validateOptions() throws {
        let valueOptions: Set<String> = ["--config", "--benchmark-events"]
        let flagOptions: Set<String> = ["--json", "--probe-hid", "--assert-runtime-ready"]
        var seen = Set<String>()
        var index = 0

        while index < options.count {
            let option = options[index]
            guard valueOptions.contains(option) || flagOptions.contains(option) else {
                throw ToolError.invalidValue("doctor option", option)
            }
            guard seen.insert(option).inserted else {
                throw ToolError.invalidValue(option, "重複しています。")
            }

            if valueOptions.contains(option) {
                guard index + 1 < options.count, !options[index + 1].hasPrefix("--") else {
                    throw ToolError.missingValue(option)
                }
                index += 2
            } else {
                index += 1
            }
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
        if runtimeIdentity.isAppBundle && runtimeIdentity.launchContext == .commandLine {
            findings.append(
                "このdoctorは.app内の実行ファイルをCLIとして起動しています。TCC判定はNape Gesture.appではなく、実行元ターミナルまたは親アプリに帰属します。GUI本体の権限はアプリ内の「権限とデバイスを確認」で判定してください。"
            )
        }
        if runtimeIdentity.launchContext == .unknown {
            findings.append(
                "起動元をLaunchServices GUIまたはCLIのどちらとも安全に判定できません。権限付与対象を推測せず、通常の.app起動または明示的なCLI起動で再実行してください。"
            )
        }
        if !accessibilityTrusted {
            findings.append("アクセシビリティ権限が未許可です。`run`、`log`、実イベント投稿は開始できません。")
            findings.append("権限付与対象を確認してください: \(runtimeIdentity.permissionTargetDescription)")
        }

        let inventory = makeInventory(settings: settings, findings: &findings)
        let outputAdapter = TrackpadGestureOutputAdapter()
        let requiredFamilies: Set<TrackpadOutputEventFamily> = [
            .scroll,
            .dockSwipe,
            .dockSwipePinch,
        ]
        let outputContract = DoctorOutputContractStatus(
            capability: outputAdapter.capability,
            requiredFamilies: requiredFamilies
        )
        if !outputContract.supported {
            findings.append(
                "trackpad driver出力contractは\(outputContract.status)です。入力抑制を開始せず安全停止します。")
        }
        let probe =
            shouldProbeHID
            ? makeHIDProbe(
                settings: settings, matchedDevices: inventory.matchedDevices, findings: &findings)
            : DoctorHIDProbe(
                requested: false, succeeded: nil, error: nil, failureCode: nil, remediation: nil)
        let benchmark = BenchmarkRunner.run(events: benchmarkEvents)
        let tccStatus = DoctorTCCStatus(
            runtimeIdentity: runtimeIdentity,
            accessibilityTrusted: accessibilityTrusted,
            hidProbe: probe,
            inputMonitoringRemediation: remediation(forInputMonitoringProbe: probe)
        )
        let runtimeReadiness = DoctorRuntimeReadiness(
            runtimeIdentity: runtimeIdentity,
            settingsValidationIssues: settingsValidationIssues,
            accessibilityTrusted: accessibilityTrusted,
            inventoryError: inventory.error,
            requireMatchingTargetDevice: settings.requireMatchingTargetDevice,
            configuredTargetMatchers: settings.targetDevices.count,
            matchedTargetDeviceCount: inventory.matchedDevices.count,
            hidProbe: probe,
            outputContract: outputContract
        )

        if findings.isEmpty {
            findings.append(
                "診断範囲では致命的な問題は見つかりませんでした。実機操作と Spaces / Mission Control の画面挙動は別途検証してください。")
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
            mouseInterfaceCount: inventory.mouseInterfaceCount,
            matchedTargetDeviceCount: inventory.matchedDevices.count,
            matchedTargetDevices: inventory.matchedDevices,
            targetDeviceDiagnostics: inventory.targetDeviceDiagnostics,
            inventoryError: inventory.error,
            hidProbe: probe,
            tccStatus: tccStatus,
            outputContract: outputContract,
            runtimeReadiness: runtimeReadiness,
            benchmark: benchmark,
            settingsValidationIssues: settingsValidationIssues,
            findings: findings
        )
    }

    private func makeInventory(settings: NapeGestureSettings, findings: inout [String])
        -> DoctorInventory
    {
        do {
            let allDevices = try DeviceInventory.allDevices()
            let mouseInterfaces = DeviceInventory.mouseInterfaces(in: allDevices)
            let matchedDevices =
                settings.targetDevices.isEmpty
                ? []
                : DeviceInventory.matchedDevices(in: allDevices, settings: settings)

            if settings.requireMatchingTargetDevice && settings.targetDevices.isEmpty {
                findings.append("対象デバイス一致が必須ですが、対象デバイス条件が空です。")
            } else if settings.requireMatchingTargetDevice && matchedDevices.isEmpty {
                findings.append(
                    "設定に一致する対象デバイスが見つかりません。`devices --all --json` と `hid-log` で識別情報を確認してください。")
            } else if !settings.targetDevices.isEmpty && matchedDevices.isEmpty {
                findings.append("対象条件はありますが現在一致デバイスは未検出です。必須ではないため起動は止めません。")
            }

            return DoctorInventory(
                allDeviceCount: allDevices.count,
                mouseInterfaceCount: mouseInterfaces.count,
                matchedDevices: matchedDevices,
                targetDeviceDiagnostics: DoctorTargetDeviceDiagnostics(
                    settings: settings,
                    allDevices: allDevices,
                    mouseInterfaces: mouseInterfaces,
                    matchedDevices: matchedDevices,
                    inventoryError: nil
                ),
                error: nil
            )
        } catch {
            let message = describe(error)
            findings.append("HID デバイス一覧の取得に失敗しました: \(message)")
            return DoctorInventory(
                allDeviceCount: nil,
                mouseInterfaceCount: nil,
                matchedDevices: [],
                targetDeviceDiagnostics: DoctorTargetDeviceDiagnostics(
                    settings: settings,
                    allDevices: nil,
                    mouseInterfaces: nil,
                    matchedDevices: [],
                    inventoryError: message
                ),
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
        let monitor = HIDInputMonitor(
            settings: settings, gate: gate, matchedDevices: matchedDevices)

        do {
            try monitor.start()
            monitor.stop()
            return DoctorHIDProbe(
                requested: true, succeeded: true, error: nil, failureCode: nil, remediation: nil)
        } catch {
            monitor.stop()
            let message = describe(error)
            let remediation = remediation(for: error)
            findings.append("HID 入力監視を開始できませんでした: \(message)")
            return DoctorHIDProbe(
                requested: true,
                succeeded: false,
                error: message,
                failureCode: hidProbeFailureCode(for: error),
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
        guard case ToolError.hidManagerOpenFailed(let code) = error else {
            return nil
        }
        switch code {
        case kIOReturnNotPermitted:
            return
                "システム設定 > プライバシーとセキュリティ > 入力監視で、Codex、実行元ターミナル、または NapeGesture.app を許可してから再起動してください。"
        case kIOReturnExclusiveAccess:
            return
                "`hid-log --all` ではなく、`devices --all --json` で確認した vendor/product/usage 条件を指定してください。"
        default:
            return IOReturnDiagnostic.describe(code)
        }
    }

    private func hidProbeFailureCode(for error: Error) -> String? {
        guard case ToolError.hidManagerOpenFailed(let code) = error else {
            return nil
        }
        switch code {
        case kIOReturnNotPermitted:
            return "notPermitted"
        case kIOReturnNotPrivileged:
            return "notPrivileged"
        case kIOReturnNoDevice:
            return "noDevice"
        case kIOReturnExclusiveAccess:
            return "exclusiveAccess"
        default:
            return "ioReturn.\(code)"
        }
    }

    private func remediation(forInputMonitoringProbe probe: DoctorHIDProbe) -> String? {
        if let remediation = probe.remediation {
            return remediation
        }
        if probe.requested && probe.succeeded != true {
            return "システム設定 > プライバシーとセキュリティ > 入力監視で、runtimeIdentity の実行主体を許可してから再起動してください。"
        }
        if !probe.requested {
            return "`doctor --probe-hid` を実行して入力監視の状態を確認してください。"
        }
        return nil
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
            "起動経路: \(report.runtimeIdentity.launchContext.rawValue)",
            "TCC判定対象: \(report.runtimeIdentity.tccAttribution)",
            "キルスイッチ: \(report.killSwitchShortcut)",
            "アクセシビリティ: \(report.accessibilityTrusted ? "許可済み" : "未許可")",
            "対象デバイス一致必須: \(report.requireMatchingTargetDevice ? "はい" : "いいえ")",
            "対象入力の紐づけ秒: \(report.targetDeviceAssociationWindow)",
            "対象デバイス条件数: \(report.configuredTargetMatchers)",
            "HIDデバイス数: \(formatOptional(report.allHIDDeviceCount))",
            "マウスインターフェース数: \(formatOptional(report.mouseInterfaceCount))",
            "一致対象デバイス数: \(report.matchedTargetDeviceCount)",
            "trackpad output contract: \(report.outputContract.status)",
            "固定必須family: \(report.outputContract.requiredFamilies.joined(separator: ", "))",
            "不足family: \(report.outputContract.missingRequiredFamilies.isEmpty ? "なし" : report.outputContract.missingRequiredFamilies.joined(separator: ", "))",
            "確定family: \(report.outputContract.confirmedFamilies.joined(separator: ", "))",
            "試用family: \(report.outputContract.trialFamilies.joined(separator: ", "))",
            "runtime ready: \(report.runtimeReadiness.ready ? "はい" : "いいえ")",
        ]

        for device in report.matchedTargetDevices {
            lines.append("- \(device.displayName) stableId=\(device.stableID)")
        }

        if !report.targetDeviceDiagnostics.candidates.isEmpty {
            lines.append("対象デバイス候補:")
            for candidate in report.targetDeviceDiagnostics.candidates.prefix(5) {
                let score =
                    "\(candidate.bestEvaluation.matchedConditionCount)/\(candidate.bestEvaluation.conditionCount)"
                let mismatchFields = candidate.bestEvaluation.mismatches.map(\.field).joined(
                    separator: ",")
                lines.append(
                    "- \(candidate.device.displayName) stableId=\(candidate.device.stableID) matcher=\(candidate.bestMatcherIndex) score=\(score) mouseInterface=\(candidate.isMouseInterface ? "yes" : "no") mismatches=\(mismatchFields.isEmpty ? "-" : mismatchFields)"
                )
            }
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
            lines.append(
                contentsOf: report.settingsValidationIssues.map { "- \($0.path): \($0.message)" })
        }
        if !report.runtimeReadiness.failures.isEmpty {
            lines.append("runtime ready 不足:")
            lines.append(
                contentsOf: report.runtimeReadiness.failures.map { "- \($0.code): \($0.message)" })
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
    var mouseInterfaceCount: Int?
    var matchedDevices: [DeviceIdentity]
    var targetDeviceDiagnostics: DoctorTargetDeviceDiagnostics
    var error: String?
}

private struct DoctorTargetDeviceDiagnostics: Codable {
    var status: String
    var requireMatchingTargetDevice: Bool
    var configuredMatchers: [DeviceMatcher]
    var matcherConditionCounts: [Int]
    var matchedDeviceCount: Int
    var evaluatedDeviceCount: Int?
    var reportedCandidateCount: Int
    var candidates: [DoctorTargetDeviceCandidate]

    init(
        settings: NapeGestureSettings,
        allDevices: [DeviceIdentity]?,
        mouseInterfaces: [DeviceIdentity]?,
        matchedDevices: [DeviceIdentity],
        inventoryError: String?
    ) {
        requireMatchingTargetDevice = settings.requireMatchingTargetDevice
        configuredMatchers = settings.targetDevices
        matcherConditionCounts = settings.targetDevices.map(\.conditionCount)
        matchedDeviceCount = matchedDevices.count
        evaluatedDeviceCount = allDevices?.count

        if inventoryError != nil {
            status = "inventoryFailed"
            candidates = []
            reportedCandidateCount = 0
            return
        }
        if settings.targetDevices.isEmpty {
            status = settings.requireMatchingTargetDevice ? "matcherMissing" : "notConfigured"
            candidates = []
            reportedCandidateCount = 0
            return
        }
        if !matchedDevices.isEmpty {
            status = "matched"
        } else if settings.requireMatchingTargetDevice {
            status = "notFound"
        } else {
            status = "noCurrentMatch"
        }

        let mouseInterfaceKeys = Set((mouseInterfaces ?? []).map(Self.deviceDiagnosticKey))
        let allCandidates = Self.uniqueDevices(allDevices ?? []).compactMap {
            device -> DoctorTargetDeviceCandidate? in
            guard let best = Self.bestEvaluation(for: device, matchers: settings.targetDevices)
            else {
                return nil
            }
            let isMouseInterface = mouseInterfaceKeys.contains(Self.deviceDiagnosticKey(device))
            guard
                best.evaluation.isMatch || best.evaluation.matchedConditionCount > 0
                    || isMouseInterface
            else {
                return nil
            }
            return DoctorTargetDeviceCandidate(
                device: device,
                isMouseInterface: isMouseInterface,
                bestMatcherIndex: best.index,
                bestEvaluation: best.evaluation
            )
        }
        candidates = Array(allCandidates.sorted(by: Self.sortCandidates).prefix(12))
        reportedCandidateCount = candidates.count
    }

    private static func bestEvaluation(
        for device: DeviceIdentity,
        matchers: [DeviceMatcher]
    ) -> (index: Int, evaluation: DeviceMatcherEvaluation)? {
        matchers.enumerated()
            .map { index, matcher in
                (index: index, evaluation: matcher.evaluate(device))
            }
            .max { lhs, rhs in
                if lhs.evaluation.isMatch != rhs.evaluation.isMatch {
                    return !lhs.evaluation.isMatch && rhs.evaluation.isMatch
                }
                if lhs.evaluation.matchedConditionCount != rhs.evaluation.matchedConditionCount {
                    return lhs.evaluation.matchedConditionCount
                        < rhs.evaluation.matchedConditionCount
                }
                if lhs.evaluation.conditionCount != rhs.evaluation.conditionCount {
                    return lhs.evaluation.conditionCount < rhs.evaluation.conditionCount
                }
                return lhs.evaluation.mismatches.count > rhs.evaluation.mismatches.count
            }
    }

    private static func sortCandidates(
        _ lhs: DoctorTargetDeviceCandidate,
        _ rhs: DoctorTargetDeviceCandidate
    ) -> Bool {
        if lhs.bestEvaluation.isMatch != rhs.bestEvaluation.isMatch {
            return lhs.bestEvaluation.isMatch && !rhs.bestEvaluation.isMatch
        }
        if lhs.bestEvaluation.matchedConditionCount != rhs.bestEvaluation.matchedConditionCount {
            return lhs.bestEvaluation.matchedConditionCount
                > rhs.bestEvaluation.matchedConditionCount
        }
        if lhs.isMouseInterface != rhs.isMouseInterface {
            return lhs.isMouseInterface && !rhs.isMouseInterface
        }
        if lhs.bestEvaluation.conditionCount != rhs.bestEvaluation.conditionCount {
            return lhs.bestEvaluation.conditionCount > rhs.bestEvaluation.conditionCount
        }
        return deviceDiagnosticKey(lhs.device) < deviceDiagnosticKey(rhs.device)
    }

    private static func uniqueDevices(_ devices: [DeviceIdentity]) -> [DeviceIdentity] {
        var seen = Set<String>()
        var result: [DeviceIdentity] = []
        for device in devices {
            guard seen.insert(deviceDiagnosticKey(device)).inserted else {
                continue
            }
            result.append(device)
        }
        return result
    }

    private static func deviceDiagnosticKey(_ device: DeviceIdentity) -> String {
        "\(device.stableID);usagePage=\(device.primaryUsagePage);usage=\(device.primaryUsage)"
    }
}

private struct DoctorTargetDeviceCandidate: Codable {
    var device: DeviceIdentity
    var isMouseInterface: Bool
    var bestMatcherIndex: Int
    var bestEvaluation: DeviceMatcherEvaluation
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
    var mouseInterfaceCount: Int?
    var matchedTargetDeviceCount: Int
    var matchedTargetDevices: [DeviceIdentity]
    var targetDeviceDiagnostics: DoctorTargetDeviceDiagnostics
    var inventoryError: String?
    var hidProbe: DoctorHIDProbe
    var tccStatus: DoctorTCCStatus
    var outputContract: DoctorOutputContractStatus
    var runtimeReadiness: DoctorRuntimeReadiness
    var benchmark: BenchmarkReport
    var settingsValidationIssues: [SettingsValidationIssue]
    var findings: [String]

    var runtimeReadinessFailures: [String] {
        runtimeReadiness.failures.map(\.message)
    }
}

private struct DoctorRuntimeReadiness: Codable {
    var ready: Bool
    var failures: [DoctorRuntimeReadinessFailure]

    init(
        runtimeIdentity: RuntimeIdentity,
        settingsValidationIssues: [SettingsValidationIssue],
        accessibilityTrusted: Bool,
        inventoryError: String?,
        requireMatchingTargetDevice: Bool,
        configuredTargetMatchers: Int,
        matchedTargetDeviceCount: Int,
        hidProbe: DoctorHIDProbe,
        outputContract: DoctorOutputContractStatus
    ) {
        var failures: [DoctorRuntimeReadinessFailure] = []
        if runtimeIdentity.launchContext == .unknown {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "runtimeIdentity.ambiguous",
                    category: "tcc",
                    message: "起動元とTCC権限の帰属先を安全に判定できません。",
                    remediation: "通常の.app起動または明示的なCLI起動で再実行してください。"
                )
            )
        }
        if !settingsValidationIssues.isEmpty {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "settings.invalid",
                    category: "settings",
                    message: "設定ファイルに不正な値があります。",
                    remediation: "`check-config` で詳細を確認し、設定 UI または JSON を修正してください。"
                )
            )
        }
        if !accessibilityTrusted {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "accessibility.missing",
                    category: "tcc",
                    message: "アクセシビリティ権限が未許可です。",
                    remediation: "runtimeIdentity の実行主体をシステム設定のアクセシビリティで許可し、プロセスを再起動してください。"
                )
            )
        }
        if inventoryError != nil {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "hidInventory.failed",
                    category: "hid",
                    message: "HID デバイス一覧を取得できません。",
                    remediation: "HID デバイス一覧の取得エラーを解消してから再実行してください。"
                )
            )
        }
        if requireMatchingTargetDevice && configuredTargetMatchers == 0 {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "targetDevice.matcherMissing",
                    category: "targetDevice",
                    message: "対象デバイス一致が必須ですが、対象デバイス条件が空です。",
                    remediation: "`init-config` または設定 UI で対象デバイス条件を設定してください。"
                )
            )
        }
        if requireMatchingTargetDevice && matchedTargetDeviceCount == 0 {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "targetDevice.notFound",
                    category: "targetDevice",
                    message: "対象デバイス一致が必須ですが、現在一致デバイスがありません。",
                    remediation: "`devices --all --json` と `hid-log` で対象デバイス条件を確認してください。"
                )
            )
        }
        if !hidProbe.requested {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "inputMonitoring.notProbed",
                    category: "tcc",
                    message: "HID 入力監視プローブが未実行です。`--probe-hid` を付けてください。",
                    remediation: "`doctor --probe-hid` を実行して入力監視の状態を確認してください。"
                )
            )
        } else if hidProbe.succeeded != true {
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: "inputMonitoring.probeFailed",
                    category: "tcc",
                    message: "HID 入力監視プローブに失敗しました。",
                    remediation: hidProbe.remediation
                        ?? "runtimeIdentity の実行主体をシステム設定の入力監視で許可し、プロセスを再起動してください。"
                )
            )
        }
        if !outputContract.supported {
            let isMismatch =
                outputContract.status
                == ProductGestureOutputCapability.Status.contractMismatch.rawValue
            let isMissingFamily = outputContract.status == "missingFamilies"
            failures.append(
                DoctorRuntimeReadinessFailure(
                    code: isMismatch
                        ? "outputContract.contractMismatch"
                        : (isMissingFamily
                            ? "outputContract.missingFamilies" : "outputContract.unsupported"),
                    category: "outputContract",
                    message: isMismatch
                        ? "trackpad driver出力contractまたは同梱fixtureの整合性検証に失敗しました。"
                        : (isMissingFamily
                            ? "固定ジェスチャーに必要なproduct output familyが未実装です: \(outputContract.missingRequiredFamilies.joined(separator: ", "))"
                            : "trackpad driver出力contractをこの環境で構成できません。"),
                    remediation: isMissingFamily
                        ? "未実装familyのadapterとcontractを完成させてください。"
                        : "同梱fixtureのID、SHA-256、schema、contract ID、実体とevent生成可否を確認してください。"
                )
            )
        }
        self.failures = failures
        ready = failures.isEmpty
    }
}

private struct DoctorOutputContractStatus: Codable {
    var status: String
    var supported: Bool
    var contractID: String?
    var schemaVersion: Int?
    var fixtureID: String?
    var fixtureSHA256: String?
    var sourceOSVersion: String?
    var sourceOSBuild: String?
    var supportedFamilies: [String]
    var confirmedFamilies: [String]
    var trialFamilies: [String]
    var requiredFamilies: [String]
    var missingRequiredFamilies: [String]
    var reason: String?

    init(
        capability: ProductGestureOutputCapability,
        requiredFamilies: Set<TrackpadOutputEventFamily>
    ) {
        let missingFamilies = requiredFamilies.subtracting(capability.supportedFamilies)
        let missing = missingFamilies.map(\.rawValue).sorted()
        status =
            capability.isSupported && !missing.isEmpty
            ? "missingFamilies"
            : capability.status.rawValue
        supported = capability.isSupported && missing.isEmpty
        contractID = capability.contract?.contractID
        schemaVersion = capability.contract?.schemaVersion
        fixtureID = capability.contract?.fixtureID
        fixtureSHA256 = capability.contract?.fixtureSHA256
        sourceOSVersion = capability.contract?.sourceOSVersion
        sourceOSBuild = capability.contract?.sourceOSBuild
        supportedFamilies = capability.supportedFamilies.map(\.rawValue).sorted()
        confirmedFamilies = capability.confirmedFamilies.map(\.rawValue).sorted()
        trialFamilies = capability.trialFamilies.map(\.rawValue).sorted()
        self.requiredFamilies = requiredFamilies.map(\.rawValue).sorted()
        self.missingRequiredFamilies = missing
        reason = capability.reason
    }
}

private struct DoctorRuntimeReadinessFailure: Codable {
    var code: String
    var category: String
    var message: String
    var remediation: String
}

private struct DoctorTCCStatus: Codable {
    var permissionTarget: DoctorTCCPermissionTarget
    var accessibility: DoctorTCCPermissionStatus
    var inputMonitoring: DoctorTCCPermissionStatus

    init(
        runtimeIdentity: RuntimeIdentity,
        accessibilityTrusted: Bool,
        hidProbe: DoctorHIDProbe,
        inputMonitoringRemediation: String?
    ) {
        permissionTarget = DoctorTCCPermissionTarget(runtimeIdentity: runtimeIdentity)
        accessibility = DoctorTCCPermissionStatus(
            service: "accessibility",
            checked: true,
            granted: accessibilityTrusted,
            status: accessibilityTrusted ? "granted" : "missing",
            grantRequired: !accessibilityTrusted,
            remediation: accessibilityTrusted
                ? nil
                : "runtimeIdentity の実行主体をシステム設定のアクセシビリティで許可し、プロセスを再起動してください。"
        )

        if !hidProbe.requested {
            inputMonitoring = DoctorTCCPermissionStatus(
                service: "inputMonitoring",
                checked: false,
                granted: nil,
                status: "notProbed",
                grantRequired: nil,
                remediation: inputMonitoringRemediation
            )
        } else if hidProbe.succeeded == true {
            inputMonitoring = DoctorTCCPermissionStatus(
                service: "inputMonitoring",
                checked: true,
                granted: true,
                status: "granted",
                grantRequired: false,
                remediation: nil
            )
        } else {
            inputMonitoring = DoctorTCCPermissionStatus(
                service: "inputMonitoring",
                checked: true,
                granted: false,
                status: "probeFailed",
                grantRequired: hidProbe.failureCode == "notPermitted" ? true : nil,
                remediation: inputMonitoringRemediation
            )
        }
    }
}

private struct DoctorTCCPermissionTarget: Codable {
    var description: String
    var preferredGrantTarget: String
    var attribution: String
    var launchContext: String
    var processName: String
    var executablePath: String
    var bundleIdentifier: String?
    var bundlePath: String
    var isAppBundle: Bool
    var restartRequiredAfterGrant: Bool

    init(runtimeIdentity: RuntimeIdentity) {
        description = runtimeIdentity.permissionTargetDescription
        preferredGrantTarget = runtimeIdentity.tccAttribution
        attribution = runtimeIdentity.tccAttribution
        launchContext = runtimeIdentity.launchContext.rawValue
        processName = runtimeIdentity.processName
        executablePath = runtimeIdentity.executablePath
        bundleIdentifier = runtimeIdentity.bundleIdentifier
        bundlePath = runtimeIdentity.bundlePath
        isAppBundle = runtimeIdentity.isAppBundle
        restartRequiredAfterGrant = true
    }
}

private struct DoctorTCCPermissionStatus: Codable {
    var service: String
    var checked: Bool
    var granted: Bool?
    var status: String
    var grantRequired: Bool?
    var remediation: String?
}

private struct DoctorHIDProbe: Codable {
    var requested: Bool
    var succeeded: Bool?
    var error: String?
    var failureCode: String?
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
