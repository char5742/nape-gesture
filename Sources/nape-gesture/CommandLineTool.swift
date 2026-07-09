import Foundation
import IOKit
import NapeGestureCore

final class CommandLineTool {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() throws {
        let command = arguments.dropFirst().first ?? defaultCommand()
        let options = Array(arguments.dropFirst(command == defaultCommand() && arguments.count == 1 ? 1 : 2))

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "app":
            let configPath = try SettingsStore.configPath(from: options)
            try StatusApp.run(configPath: configPath)
        case "gui-smoke":
            try guiSmoke(options: options)
        case "run":
            let loaded = try SettingsStore.loadRuntimeSettings(from: options)
            let settings = loaded.settings
            print("設定ファイル: \(loaded.path)")
            let matchedDevices = try validateTargetDevicesIfNeeded(settings)
            let gate = makeTargetDeviceGate(settings: settings)
            let performanceRecorder = try RuntimePerformanceLogWriter.make(
                path: SettingsStore.value(for: "--performance-log", in: options)
            )
            let monitor = try makeHIDInputMonitor(settings: settings, gate: gate, matchedDevices: matchedDevices)
            let daemon = NapeGestureDaemon(
                configuration: settings.gesture,
                targetGate: gate,
                hidInputMonitor: monitor,
                performanceRecorder: performanceRecorder
            )
            try daemon.run()
        case "log":
            let logger = EventLogger(options: options)
            try logger.run()
        case "analyze-log":
            try AnalyzeLogCommand(options: options).run()
        case "compare-log":
            try CompareLogCommand(options: options).run()
        case "derive-parameters":
            try DeriveParametersCommand(options: options).run()
        case "analyze-hid-log":
            try AnalyzeHIDLogCommand(options: options).run()
        case "analyze-association":
            try AnalyzeAssociationCommand(options: options).run()
        case "analyze-target-log":
            try AnalyzeTargetLogCommand(options: options).run()
        case "analyze-performance-log":
            try AnalyzePerformanceLogCommand(options: options).run()
        case "check-config":
            try checkConfig(options: options)
        case "config-path":
            print(try SettingsStore.configPath(from: options))
        case "bundle-app":
            try BundleAppCommand(options: options).run()
        case "verify-bundle":
            try VerifyBundleCommand(options: options).run()
        case "generate-scroll":
            try GenerateScrollCommand(options: options).run()
        case "init-config":
            try initConfig(options: options)
        case "target":
            try ReferenceTargetApp.run(options: options)
        case "devices":
            try DeviceLister.printDevices(json: options.contains("--json"), includeAll: options.contains("--all"))
        case "hid-log":
            try HIDLogCommand(options: options).run()
        case "system-test":
            try SystemBehaviorTestCommand(options: options).run()
        case "benchmark":
            try BenchmarkCommand(options: options).run()
        case "doctor":
            try DoctorCommand(options: options).run()
        default:
            throw ToolError.unknownCommand(command)
        }
    }

    private func printHelp() {
        print(
            """
            nape-gesture

            使い方:
              nape-gesture app [--config <path>]
                  通常 GUI アプリを起動し、設定ウィンドウとメニューバー常駐UIを表示します。環境変数 NAPE_RUNTIME_PERFORMANCE_LOG で runtime 性能 JSON Lines を保存できます。

              nape-gesture gui-smoke [--config <path>] [--json] [--assert]
                  runtime を開始せずに active macOS GUI session 上で通常 GUI activation policy、設定ウィンドウ、status item NG、通常アプリメニュー、status menu を AppKit 内で作成して検査します。--assert で期待 UI と一致しない場合に失敗します。--config 未指定時は一時 config を使います。

              nape-gesture run [--performance-log <path>]
                  特定ボタン押下中のドラッグ・ホイールを生成スクロールへ変換します。
                  --config <path> で対象デバイスや感度を読み込みます。--performance-log で runtime 性能 JSON Lines を保存します。

              nape-gesture log [--duration <秒>] [--out <path>] [--exclude-generated|--only-generated]
                  グローバル入力イベントを JSON Lines で記録します。メタ情報は標準エラー、イベント本体は標準出力または --out に出します。

              nape-gesture analyze-log <path> [--json] [--assert-has-unmarked-passthrough-input] [--assert-has-unmarked-click] [--assert-has-unmarked-drag] [--assert-has-unmarked-wheel] [--assert-has-unmarked-click-drag-wheel] [--assert-kill-switch-shortcut] [--assert-gesture-before-kill-switch] [--assert-generated-scroll-log] [--assert-system-scenario <name>]
                  JSON Lines ログを解析し、しきい値候補を出します。--assert-has-unmarked-passthrough-input で未生成の移動またはスクロールがない場合、--assert-has-unmarked-click / --assert-has-unmarked-drag / --assert-has-unmarked-wheel で未生成の通常クリック / 通常ドラッグ / 通常ホイールがない場合、--assert-kill-switch-shortcut で未生成の Control + Option + Command + G keyDown / keyUp がない場合、--assert-gesture-before-kill-switch でキルスイッチ前の未生成ジェスチャー入力がない場合、--assert-generated-scroll-log で generate-scroll dry-run の生成スクロール契約を満たさない場合、--assert-system-scenario で system-test dry-run の期待イベント列を満たさない場合に失敗します。

              nape-gesture compare-log <baseline> <candidate> [--json]
                  純正入力ログと生成イベントログなど、2つの JSON Lines ログ差分を比較します。

              nape-gesture derive-parameters <path> [--json] [--assert-complete]
                  純正トラックパッドなどの JSON Lines ログから deadZone、加速度、慣性の候補値と未導出理由を出します。--assert-complete で acceleration / momentum 候補が未導出、または警告がある場合に失敗します。

              nape-gesture analyze-hid-log <path> [--json]
                  IOHID 生入力ログを device / usage ごとに集計します。

              nape-gesture analyze-association <hid-log> <event-log> [--window <秒>] [--target-stable-id <ID>] [--json] [--assert-valid-window]
                  HID 生入力ログとイベントタップログを相関し、対象入力の紐づけ秒を検証します。--assert-valid-window で対象 stableID 未指定、解析対象なし、互換 HID 候補なし、非互換 HID 近傍、対象外互換 HID 近傍、複数 HID デバイス採用、または associationWindow 外の入力がある場合に失敗します。

              nape-gesture analyze-target-log <path> [--json] [--assert-no-leaks] [--assert-has-unmarked-input] [--assert-has-unmarked-click] [--assert-has-unmarked-drag] [--assert-has-unmarked-wheel] [--assert-has-unmarked-click-drag-wheel] [--assert-has-gesture] [--assert-has-generated-event] [--assert-has-foreground-capture] [--assert-has-generated-foreground-capture] [--assert-generated-foreground-scroll-x-positive|--assert-generated-foreground-scroll-x-negative] [--assert-generated-foreground-scroll-events-at-least <数>] [--assert-generated-foreground-scroll-abs-x-at-least <値>]
                  Reference Target App が保存した AppKit 受信イベントを集計します。--assert-no-leaks で漏れ候補がある場合、--assert-has-unmarked-input で未マーク入力がない場合、--assert-has-unmarked-click / --assert-has-unmarked-drag / --assert-has-unmarked-wheel で未マーク通常クリック / 通常ドラッグ / 通常ホイールがない場合、--assert-has-unmarked-click-drag-wheel で3種類が揃わない場合、--assert-has-gesture で swipe / magnify / rotate がない場合、--assert-has-generated-event で Nape Gesture 生成イベントがない場合、--assert-has-foreground-capture で globalMonitor 以外の前面受信経路がない場合、--assert-has-generated-foreground-capture で前面受信経路へ届いた Nape Gesture 生成イベントがない場合に失敗します。生成foregroundスクロールの方向、重複排除後イベント数、X方向絶対量も assertion できます。

              nape-gesture analyze-performance-log <path> [--json] [--assert-baseline]
                  runtime 性能 JSON Lines を集計します。tap callback から投稿直前/直後までの p95/p99、投稿数、作成失敗数を出します。--assert-baseline で入力遅延基準を満たさない場合に失敗します。

              nape-gesture check-config [--config <path>] [--probe-hid]
                  対象デバイス設定と HID 入力監視の開始可否を確認します。

              nape-gesture config-path [--config <path>]
                  使用する設定ファイルのパスを表示します。

              nape-gesture bundle-app [--out <path>] [--replace]
                  現在の実行ファイルから .app バンドルを作成します。

              nape-gesture verify-bundle [--require-signature] <path>
                  .app バンドルの Info.plist、実行ファイル、配布文書、コード署名状態を検証します。

              nape-gesture generate-scroll --x <値> --y <値> [--steps <数>] [--phase auto|began|changed|ended|cancelled|momentum] [--momentum-steps <数>] [--dry-run] [--json|--log-json]
                  ピクセル単位のスクロールイベントを任意フェーズや慣性つきで生成します。--dry-run --log-json で compare-log 用 JSON Lines を出力します。

              nape-gesture init-config [--out <path>] [--vendor-id <ID>] [--product-id <ID>] [--manufacturer-contains <文字>] [--product-contains <文字>] [--transport-contains <文字>] [--usage-page <ID>] [--usage <ID>] [--association-window <秒>] [--allow-unmatched]
                  Nape Pro 向け、または指定した HID 条件向けの設定テンプレートを出力します。

              nape-gesture target [--out <path>] [--duration <秒>] [--ready-file <path>] [--focus-capture-point]
                  AppKit が受け取るイベントを表示する基準ウィンドウを開きます。--out で受信イベントを JSON Lines に保存します。--duration 指定時は指定秒数後に自動終了し、--ready-file でウィンドウ準備完了ファイルを書き出します。--focus-capture-point は検証自動化用に capture view 中心へカーソルを移動します。

              nape-gesture devices [--json] [--all]
                  IOHID で認識できるデバイスを表示します。通常はマウス系だけ、--all で全HIDを表示します。

              nape-gesture hid-log [--duration <秒>] [--vendor-id <ID>] [--product-id <ID>] [--usage-page <ID>] [--usage <ID>] [--all]
                  IOHID の生入力を JSON Lines で記録します。vendor/product/usage 指定時はその条件だけを開きます。

              nape-gesture system-test list
                  System Behavior Test のシナリオ一覧を表示します。

              nape-gesture system-test run --scenario <name> [--target finder|safari] [--dry-run] [--log-json] [--out <path>] [--post-to-pid <pid>]
                  Spaces / Mission Control / Safari / Finder 向けの実挙動検証イベント、または未マーク元入力を生成します。--dry-run --log-json で計画したイベントを JSON Lines で出力します。--post-to-pid は対応シナリオを Reference Target App などへ直接投稿し、OS 画面遷移を避けて受信経路を切り分ける診断用です。--target とは同時指定できません。

              nape-gesture benchmark [--events <数>] [--json] [--assert-baseline]
                  認識器とスクロール計画の純粋ロジック処理時間、CPU コスト、batch p95/p99 を測定します。--assert-baseline で性能基準を満たさない場合に失敗します。

              nape-gesture doctor [--config <path>] [--probe-hid] [--benchmark-events <数>] [--json] [--assert-runtime-ready]
                  権限、対象デバイス、HID入力監視、ベンチマークを一括診断します。--assert-runtime-ready で runtime 開始前提を満たさない場合に失敗します。
            """
        )
    }

    private func defaultCommand() -> String {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return "app"
        }
        return "help"
    }

    private func initConfig(options: [String]) throws {
        let settings = try makeInitialSettings(options: options)
        try SettingsStore.validateSettings(settings)
        if options.contains("--out") {
            let path = try SettingsStore.requiredValue(for: "--out", in: options)
            try SettingsStore.write(settings, to: path)
            print("設定テンプレートを書き出しました: \(path)")
        } else {
            print(try SettingsStore.string(for: settings))
        }
    }

    private func guiSmoke(options: [String]) throws {
        let usesExplicitConfig = options.contains("--config")
        let configPath = try guiSmokeConfigPath(options: options)
        if !usesExplicitConfig {
            try SettingsStore.writeTemplate(to: configPath)
        }
        let snapshot = try StatusApp.smokeSnapshot(configPath: configPath)
        if options.contains("--assert") {
            try snapshot.assertRegularGUI()
        }

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("通常 GUI app smoke: 成功")
        print("activationPolicy: \(snapshot.activationPolicy)")
        print("status item: \(snapshot.statusItemTitle ?? "なし")")
        print("settings window: \(snapshot.settingsWindowTitle ?? "なし")")
    }

    private func guiSmokeConfigPath(options: [String]) throws -> String {
        if options.contains("--config") {
            return try SettingsStore.configPath(from: options)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("NapeGesture", isDirectory: true)
            .appendingPathComponent("gui-smoke.config.json")
            .path
    }

    private func makeInitialSettings(options: [String]) throws -> NapeGestureSettings {
        let hasMatcherOption = [
            "--vendor-id",
            "--product-id",
            "--manufacturer-contains",
            "--product-contains",
            "--transport-contains",
            "--usage-page",
            "--usage"
        ].contains { options.contains($0) }

        let targetDeviceAssociation = TargetDeviceAssociationConfiguration(
            associationWindow: try optionalDoubleValue("--association-window", in: options)
                ?? TargetDeviceAssociationConfiguration.defaultAssociationWindow
        )

        if !hasMatcherOption && !options.contains("--allow-unmatched") {
            return NapeGestureSettings(
                gesture: .default,
                targetDeviceAssociation: targetDeviceAssociation,
                targetDevices: NapeGestureSettings.template.targetDevices,
                requireMatchingTargetDevice: true
            )
        }

        let matcher = DeviceMatcher(
            vendorID: try optionalIntValue("--vendor-id", in: options),
            productID: try optionalIntValue("--product-id", in: options),
            manufacturerContains: SettingsStore.value(for: "--manufacturer-contains", in: options),
            productContains: SettingsStore.value(for: "--product-contains", in: options),
            transportContains: SettingsStore.value(for: "--transport-contains", in: options),
            primaryUsagePage: try optionalIntValue("--usage-page", in: options),
            primaryUsage: try optionalIntValue("--usage", in: options)
        )
        let targetDevices = matcher.hasAnyCondition ? [matcher] : []
        let requireMatchingTargetDevice = !options.contains("--allow-unmatched")

        if requireMatchingTargetDevice && targetDevices.isEmpty {
            throw ToolError.targetDeviceMatcherRequired
        }

        return NapeGestureSettings(
            gesture: .default,
            targetDeviceAssociation: targetDeviceAssociation,
            targetDevices: targetDevices,
            requireMatchingTargetDevice: requireMatchingTargetDevice
        )
    }

    private func optionalIntValue(_ name: String, in options: [String]) throws -> Int? {
        guard options.contains(name) else {
            return nil
        }
        let raw = try SettingsStore.requiredValue(for: name, in: options)
        guard let value = Int(raw) else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func optionalDoubleValue(_ name: String, in options: [String]) throws -> Double? {
        guard options.contains(name) else {
            return nil
        }
        let raw = try SettingsStore.requiredValue(for: name, in: options)
        guard let value = Double(raw) else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func validateTargetDevicesIfNeeded(_ settings: NapeGestureSettings) throws -> [DeviceIdentity] {
        guard !settings.targetDevices.isEmpty else {
            if settings.requireMatchingTargetDevice {
                throw ToolError.targetDeviceMatcherRequired
            }
            return []
        }

        let matched = try DeviceInventory.matchedDevices(settings: settings)
        guard !matched.isEmpty else {
            if settings.requireMatchingTargetDevice {
                throw ToolError.targetDeviceNotFound
            }
            return []
        }

        let names = matched.map(\.displayName).joined(separator: ", ")
        print("対象デバイス: \(names)")
        return matched
    }

    private func validateRequiredTargetDevices(_ settings: NapeGestureSettings) throws -> [DeviceIdentity] {
        guard !settings.targetDevices.isEmpty else {
            throw ToolError.targetDeviceMatcherRequired
        }

        let matched = try DeviceInventory.matchedDevices(settings: settings)
        guard !matched.isEmpty else {
            throw ToolError.targetDeviceNotFound
        }

        return matched
    }

    private func checkConfig(options: [String]) throws {
        let loaded = try SettingsStore.loadRuntimeSettings(from: options)
        let settings = loaded.settings
        let shouldProbeHID = options.contains("--probe-hid")
        let allDevices = try DeviceInventory.allDevices()
        let devices = try DeviceInventory.pointingDevices()
        print("設定ファイル: \(loaded.path)")
        print("設定バリデーション: 成功")
        print("対象入力の紐づけ秒: \(settings.targetDeviceAssociation.associationWindow)")
        print("検出したHIDデバイス数: \(allDevices.count)")
        print("検出したポインティングデバイス数: \(devices.count)")

        if devices.isEmpty {
            print("ポインティングデバイスは見つかりませんでした。")
        } else {
            for device in devices {
                print("- \(device.displayName) vendorId=\(device.vendorID) productId=\(device.productID) transport=\(device.transport)")
            }
        }

        if !settings.requireMatchingTargetDevice {
            if settings.targetDevices.isEmpty {
                print("対象デバイス一致は必須ではありません。すべての入力デバイスが対象になり得ます。")
            } else {
                print("対象デバイス一致は必須ではありません。対象条件が未検出でも起動は止めませんが、ジェスチャー処理は一致した入力に限定します。")
            }
            let matched = try validateTargetDevicesIfNeeded(settings)
            if !matched.isEmpty {
                print("設定に一致した対象デバイス数: \(matched.count)")
                for device in matched {
                    print("- \(device.displayName) stableId=\(device.stableID)")
                }
            }
            if shouldProbeHID {
                try probeHIDInputMonitor(settings: settings, matchedDevices: matched)
            }
            return
        }

        let matched = try validateRequiredTargetDevices(settings)

        print("設定に一致した対象デバイス数: \(matched.count)")
        for device in matched {
            print("- \(device.displayName) stableId=\(device.stableID)")
        }

        if shouldProbeHID {
            try probeHIDInputMonitor(settings: settings, matchedDevices: matched)
        }
    }

    private func probeHIDInputMonitor(settings: NapeGestureSettings, matchedDevices: [DeviceIdentity]) throws {
        let gate = SharedTargetDeviceGate(
            configuration: TargetDeviceGateConfiguration(settings: settings)
        )
        let monitor = HIDInputMonitor(settings: settings, gate: gate, matchedDevices: matchedDevices)
        try monitor.start()
        monitor.stop()
        print("HID 入力監視を開始できました。")
    }

    private func makeTargetDeviceGate(settings: NapeGestureSettings) -> SharedTargetDeviceGate? {
        guard !settings.targetDevices.isEmpty else {
            return nil
        }
        return SharedTargetDeviceGate(
            configuration: TargetDeviceGateConfiguration(settings: settings)
        )
    }

    private func makeHIDInputMonitor(
        settings: NapeGestureSettings,
        gate: SharedTargetDeviceGate?,
        matchedDevices: [DeviceIdentity]
    ) throws -> HIDInputMonitor? {
        guard let gate else {
            return nil
        }

        let monitor = HIDInputMonitor(settings: settings, gate: gate, matchedDevices: matchedDevices)
        try monitor.start()
        print("対象デバイスの HID 入力監視を開始しました。")
        return monitor
    }
}

enum ToolError: LocalizedError {
    case unknownCommand(String)
    case missingValue(String)
    case invalidValue(String, String)
    case invalidSettings([SettingsValidationIssue])
    case accessibilityPermissionRequired
    case eventTapCreationFailed
    case hidManagerOpenFailed(IOReturn)
    case hidRegistryQueryFailed(kern_return_t)
    case targetDeviceMatcherRequired
    case targetDeviceNotFound
    case bundleOutputAlreadyExists(String)
    case bundleVerificationFailed(String)
    case executablePathUnavailable
    case targetApplicationNotFound(String)
    case benchmarkBaselineFailed(String)
    case guiSmokeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unknownCommand(command):
            return "未知のコマンドです: \(command)"
        case let .missingValue(name):
            return "\(name) の値がありません。"
        case let .invalidValue(name, value):
            return "\(name) の値が不正です: \(value)"
        case let .invalidSettings(issues):
            let details = issues
                .map { "- \($0.path): \($0.message)" }
                .joined(separator: "\n")
            return "設定ファイルの値が不正です。\n\(details)"
        case .accessibilityPermissionRequired:
            return "アクセシビリティ権限が必要です。システム設定でこの実行ファイルを許可してください。"
        case .eventTapCreationFailed:
            return "イベントタップを作成できませんでした。権限、入力監視、または他プロセスによる制限を確認してください。"
        case let .hidManagerOpenFailed(code):
            return "IOHIDManager を開けませんでした。code=\(code) (\(IOReturnDiagnostic.describe(code)))"
        case let .hidRegistryQueryFailed(code):
            return "IORegistry から HID デバイスを取得できませんでした。code=\(code)"
        case .targetDeviceMatcherRequired:
            return "対象デバイス一致が必須ですが、対象デバイス条件が空です。設定で対象製品名などを指定するか、明示的に requireMatchingTargetDevice を false にしてください。"
        case .targetDeviceNotFound:
            return "設定に一致する対象デバイスが見つかりませんでした。`nape-gesture devices` で識別情報を確認してください。"
        case let .bundleOutputAlreadyExists(path):
            return "出力先が既に存在します: \(path)。上書きする場合は --replace を指定してください。"
        case let .bundleVerificationFailed(message):
            return "アプリバンドル検証に失敗しました。\n\(message)"
        case .executablePathUnavailable:
            return "現在の実行ファイルのパスを取得できませんでした。"
        case let .targetApplicationNotFound(name):
            return "\(name) を見つけられませんでした。"
        case let .benchmarkBaselineFailed(message):
            return "benchmark の純粋ロジック基準を満たしていません。\n\(message)"
        case let .guiSmokeFailed(message):
            return "GUI smoke 検証に失敗しました。\n\(message)"
        }
    }
}

enum IOReturnDiagnostic {
    static func describe(_ code: IOReturn) -> String {
        switch code {
        case kIOReturnNotPermitted:
            return "入力監視が許可されていません。システム設定 > プライバシーとセキュリティ > 入力監視で、Codex、実行元ターミナル、または NapeGesture.app を許可してください。"
        case kIOReturnNotPrivileged:
            return "権限が不足しています。入力監視とアクセシビリティの許可状態を確認してください。"
        case kIOReturnNoDevice:
            return "対象デバイスが見つかりません。接続状態を確認してください。"
        case kIOReturnExclusiveAccess:
            return "他のプロセスがデバイスを排他的に使用している可能性があります。`hid-log --all` ではなく、`devices --all --json` で確認した `--vendor-id` / `--product-id` を指定してください。"
        default:
            return "未分類の IOKit エラーです。入力監視権限、対象デバイス、他プロセスの占有を確認してください。"
        }
    }
}
