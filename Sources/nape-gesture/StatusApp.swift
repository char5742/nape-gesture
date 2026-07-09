import AppKit
import Foundation
import NapeGestureCore

final class StatusApp: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: StatusApp?

    private let configPath: String
    private let runtime = NapeGestureRuntime()
    private var recoveryState = RuntimeRecoveryState()
    private var settings: NapeGestureSettings
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var retryTimer: Timer?

    private let retryInterval: TimeInterval = 5.0
    private let wakeRetryDelay: TimeInterval = 1.5

    init(configPath: String) throws {
        self.configPath = configPath
        settings = try SettingsStore.loadOrCreateDefault(at: configPath)
        super.init()
    }

    static func run(configPath: String) throws {
        let app = NSApplication.shared
        let delegate = try StatusApp(configPath: configPath)
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(GUIAppLaunchPresenter.regularGUIApp.activationPolicyValue)
        app.run()
    }

    static func smokeSnapshot(configPath: String) throws -> StatusAppSmokeSnapshot {
        let app = NSApplication.shared
        let previousDelegate = app.delegate
        let previousMainMenu = app.mainMenu
        let previousActivationPolicy = app.activationPolicy()
        let previousRetainedDelegate = retainedDelegate
        let delegate = try StatusApp(configPath: configPath)
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(GUIAppLaunchPresenter.regularGUIApp.activationPolicyValue)

        defer {
            delegate.settingsWindow?.close()
            if let statusItem = delegate.statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            delegate.statusItem = nil
            app.mainMenu = previousMainMenu
            app.setActivationPolicy(previousActivationPolicy)
            app.delegate = previousDelegate
            retainedDelegate = previousRetainedDelegate
        }

        delegate.installLaunchUIChrome()
        delegate.openSettings()
        delegate.waitForSmokeWindowVisibility()

        return delegate.makeSmokeSnapshot()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installLaunchUIChrome()
        installLifecycleObservers()
        startRetryTimer()
        startRuntime()
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettings()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        retryTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        runtime.stop()
        Self.retainedDelegate = nil
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "NG"
        statusItem = item
    }

    private func installLaunchUIChrome() {
        installApplicationMenu()
        installStatusItem()
        refreshMenu()
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let settingsItem = NSMenuItem(title: "設定...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "権限とデバイスを確認", action: #selector(checkPermissions), keyEquivalent: "")
        permissionsItem.target = self
        appMenu.addItem(permissionsItem)

        let accessibilitySettingsItem = NSMenuItem(title: "アクセシビリティ設定を開く", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilitySettingsItem.target = self
        appMenu.addItem(accessibilitySettingsItem)

        let inputMonitoringSettingsItem = NSMenuItem(title: "入力監視設定を開く", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        inputMonitoringSettingsItem.target = self
        appMenu.addItem(inputMonitoringSettingsItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Nape Gesture を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(NSMenuItem(title: "取り消す", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func refreshMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let presentation = RuntimeStatusPresenter.present(
            isRuntimeRunning: runtime.isRunning,
            recoveryState: recoveryState
        )
        menu.addItem(NSMenuItem(title: presentation.stateTitle, action: nil, keyEquivalent: ""))

        if let error = runtime.lastError {
            menu.addItem(NSMenuItem(title: "エラー: \(error.localizedDescription)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("開始", action: #selector(startRuntime), enabled: presentation.startEnabled))
        menu.addItem(menuItem("緊急停止", action: #selector(stopRuntime), enabled: presentation.emergencyStopEnabled))
        menu.addItem(menuItem("停止", action: #selector(stopRuntime), enabled: presentation.stopEnabled))
        menu.addItem(menuItem("設定...", action: #selector(openSettings), enabled: true))
        menu.addItem(menuItem("権限とデバイスを確認", action: #selector(checkPermissions), enabled: true))
        menu.addItem(menuItem("アクセシビリティ設定を開く", action: #selector(openAccessibilitySettings), enabled: true))
        menu.addItem(menuItem("入力監視設定を開く", action: #selector(openInputMonitoringSettings), enabled: true))
        menu.addItem(.separator())
        menu.addItem(menuItem("終了", action: #selector(quit), enabled: true))
        statusItem?.menu = menu
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func startRuntime() {
        let decision = recoveryState.requestManualStart(at: currentTime())
        if decision.shouldStartRuntime {
            startRuntimeAndRecordResult()
        }
        refreshMenu()
    }

    @objc private func stopRuntime() {
        let decision = recoveryState.requestManualStop(at: currentTime())
        if decision.shouldStopRuntime {
            runtime.stop()
        }
        refreshMenu()
    }

    @objc private func openSettings() {
        if let existingWindow = settingsWindow?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController(settings: settings, configPath: configPath)
        controller.onSave = { [weak self] updated in
            guard let self else {
                return
            }
            do {
                try SettingsStore.write(updated, to: configPath)
                settings = updated
                let decision = recoveryState.recordSettingsSaved(at: currentTime())
                if decision.shouldStartRuntime {
                    startRuntimeAndRecordResult()
                }
                refreshMenu()
            } catch {
                showAlert(title: "設定を保存できません", message: error.localizedDescription)
            }
        }
        settingsWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkPermissions() {
        let accessibilityTrusted = AccessibilityPermission.isTrusted
        let identity = RuntimeIdentity.current
        let allDevices = (try? DeviceInventory.allDevices()) ?? []
        let devices = (try? DeviceInventory.pointingDevices()) ?? []
        let matched = (try? DeviceInventory.matchedDevices(settings: settings)) ?? []
        let inputMonitoring = probeInputMonitoring(matchedDevices: matched)
        let recoveryPresentation = PermissionRecoveryPresenter.present(
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringGranted: inputMonitoring.granted,
            permissionTargetDescription: identity.permissionTargetDescription
        )

        var lines = [
            "\(recoveryPresentation.accessibility.serviceTitle): \(recoveryPresentation.accessibility.statusTitle)",
            "\(recoveryPresentation.inputMonitoring.serviceTitle): \(recoveryPresentation.inputMonitoring.statusTitle)",
            "入力監視詳細: \(inputMonitoring.detail)",
            "権限対象: \(recoveryPresentation.permissionTargetDescription)",
            "実行ファイル: \(identity.executablePath)",
            "バンドルID: \(identity.bundleIdentifier ?? "なし")",
            "キルスイッチ: \(KillSwitchShortcut.displayName)",
            "実行状態: \(runtime.isRunning ? "実行中" : "停止中")",
            "設定ファイル: \(configPath)",
            "対象入力の紐づけ秒: \(settings.targetDeviceAssociation.associationWindow)",
            "HIDデバイス数: \(allDevices.count)",
            "ポインティングデバイス数: \(devices.count)",
            "対象一致数: \(matched.count)",
            "自動再試行: \(recoveryState.autoRetryEnabled ? "有効" : "無効")"
        ]

        if let error = runtime.lastError {
            lines.append("直近エラー: \(error.localizedDescription)")
        }

        if !matched.isEmpty {
            lines.append("対象: " + matched.map(\.displayName).joined(separator: ", "))
        }

        if !accessibilityTrusted {
            AccessibilityPermission.prompt()
        }
        lines.append(recoveryPresentation.restartNotice)

        showPermissionAlert(
            title: "権限とデバイス",
            message: lines.joined(separator: "\n"),
            presentation: recoveryPresentation
        )
    }

    private func probeInputMonitoring(matchedDevices: [DeviceIdentity]) -> InputMonitoringProbeResult {
        if runtime.isRunning {
            return .notProbed("常駐実行中のため、停止せずに入力監視プローブは行いません。")
        }

        let gate = SharedTargetDeviceGate(
            configuration: TargetDeviceGateConfiguration(settings: settings)
        )
        let monitor = HIDInputMonitor(settings: settings, gate: gate, matchedDevices: matchedDevices)

        do {
            try monitor.start()
            monitor.stop()
            return .granted
        } catch {
            monitor.stop()
            return .failed(describe(error))
        }
    }

    @objc private func openAccessibilitySettings() {
        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
        }
        openSystemSettings(PermissionRecoveryPresenter.accessibilitySettingsURLString)
    }

    @objc private func openInputMonitoringSettings() {
        openSystemSettings(PermissionRecoveryPresenter.inputMonitoringSettingsURLString)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showPermissionAlert(
        title: String,
        message: String,
        presentation: PermissionRecoveryPresentation
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational

        var buttonActions: [() -> Void] = [{}]
        alert.addButton(withTitle: "閉じる")

        if presentation.accessibility.shouldOpenSettings {
            alert.addButton(withTitle: presentation.accessibility.settingsButtonTitle)
            buttonActions.append { [weak self] in
                self?.openAccessibilitySettings()
            }
        }

        if presentation.inputMonitoring.shouldOpenSettings {
            alert.addButton(withTitle: presentation.inputMonitoring.settingsButtonTitle)
            buttonActions.append { [weak self] in
                self?.openInputMonitoringSettings()
            }
        }

        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard buttonActions.indices.contains(index) else {
            return
        }
        buttonActions[index]()
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else {
            showAlert(title: "システム設定を開けません", message: "次の URL を開けませんでした。\n\(urlString)")
            return
        }
    }

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func installLifecycleObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func startRetryTimer() {
        retryTimer?.invalidate()
        let timer = Timer(timeInterval: retryInterval, repeats: true) { [weak self] _ in
            self?.retryRuntimeIfNeeded()
        }
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func retryRuntimeIfNeeded() {
        guard recoveryState.autoRetryEnabled,
              !recoveryState.isSuspendedForSleep
        else {
            return
        }

        if runtime.isRunning {
            if runtime.refreshHealth(settings: settings) {
                recordRuntimeFailure()
                refreshMenu()
            }
            return
        }

        let decision = recoveryState.retryIfReady(at: currentTime())
        if decision.shouldStartRuntime {
            startRuntimeAndRecordResult()
            refreshMenu()
        }
    }

    @objc private func handleWillSleep() {
        let decision = recoveryState.handleWillSleep(at: currentTime())
        if decision.shouldStopRuntime {
            runtime.stop()
        }
        refreshMenu()
    }

    @objc private func handleDidWake() {
        _ = recoveryState.handleDidWake(at: currentTime(), retryDelay: wakeRetryDelay)
        refreshMenu()

        DispatchQueue.main.asyncAfter(deadline: .now() + wakeRetryDelay) { [weak self] in
            guard let self else {
                return
            }
            let decision = recoveryState.retryIfReady(at: currentTime())
            guard decision.shouldStartRuntime else {
                return
            }
            startRuntimeAndRecordResult()
            refreshMenu()
        }
    }

    private func startRuntimeAndRecordResult() {
        runtime.start(settings: settings)
        if runtime.isRunning {
            recoveryState.recordRuntimeStarted()
        } else {
            recordRuntimeFailure()
        }
    }

    private func recordRuntimeFailure() {
        let failureKind = runtime.lastRecoveryFailureKind ?? .unrecoverable
        _ = recoveryState.recordRuntimeFailure(failureKind, at: currentTime())
    }

    private func currentTime() -> TimeInterval {
        Date().timeIntervalSince1970
    }

    private func makeSmokeSnapshot() -> StatusAppSmokeSnapshot {
        let launchPresentation = GUIAppLaunchPresenter.regularGUIApp
        return StatusAppSmokeSnapshot(
            runtimeIdentity: RuntimeIdentity.current,
            activationPolicy: NSApp.activationPolicy().smokeValue,
            expectedActivationPolicy: launchPresentation.activationPolicy,
            opensSettingsWindowOnLaunch: launchPresentation.opensSettingsWindowOnLaunch,
            reopensSettingsWindowFromDock: launchPresentation.reopensSettingsWindowFromDock,
            keepsStatusMenu: launchPresentation.keepsStatusMenu,
            bundleLSUIElement: launchPresentation.bundleLSUIElement,
            statusItemTitle: statusItem?.button?.title,
            statusMenuItems: statusItem?.menu?.items.map(StatusAppSmokeMenuItem.init) ?? [],
            applicationMenuItems: NSApp.mainMenu?.items.first?.submenu?.items.map(StatusAppSmokeMenuItem.init) ?? [],
            settingsWindowTitle: settingsWindow?.window?.title,
            settingsWindowIsVisible: settingsWindow?.window?.isVisible ?? false
        )
    }

    private func waitForSmokeWindowVisibility(timeout: TimeInterval = 2.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while !(settingsWindow?.window?.isVisible ?? false) && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

struct StatusAppSmokeSnapshot: Codable {
    var runtimeIdentity: RuntimeIdentity
    var activationPolicy: String
    var expectedActivationPolicy: String
    var opensSettingsWindowOnLaunch: Bool
    var reopensSettingsWindowFromDock: Bool
    var keepsStatusMenu: Bool
    var bundleLSUIElement: Bool
    var statusItemTitle: String?
    var statusMenuItems: [StatusAppSmokeMenuItem]
    var applicationMenuItems: [StatusAppSmokeMenuItem]
    var settingsWindowTitle: String?
    var settingsWindowIsVisible: Bool

    func assertRegularGUI() throws {
        var failures: [String] = []
        if activationPolicy != expectedActivationPolicy {
            failures.append("activationPolicy が \(expectedActivationPolicy) ではありません: \(activationPolicy)")
        }
        if statusItemTitle != "NG" {
            failures.append("status item title が NG ではありません: \(statusItemTitle ?? "なし")")
        }
        if settingsWindowTitle != "Nape Gesture 設定" {
            failures.append("設定ウィンドウ title が Nape Gesture 設定ではありません: \(settingsWindowTitle ?? "なし")")
        }
        if !settingsWindowIsVisible {
            failures.append("設定ウィンドウが表示状態ではありません。")
        }

        let statusTitles = statusMenuItems.map(\.title)
        let expectedStatusTitles = [
            "状態: 停止中",
            "開始",
            "緊急停止",
            "停止",
            "設定...",
            "権限とデバイスを確認",
            "アクセシビリティ設定を開く",
            "入力監視設定を開く",
            "終了"
        ]
        for title in expectedStatusTitles where !statusTitles.contains(title) {
            failures.append("status menu に \(title) がありません。")
        }
        if statusMenuItems.first(where: { $0.title == "開始" })?.enabled != true {
            failures.append("停止中の status menu で 開始 が有効ではありません。")
        }
        if statusMenuItems.first(where: { $0.title == "緊急停止" })?.enabled != true {
            failures.append("自動再試行が有効な停止中の status menu で 緊急停止 が有効ではありません。")
        }
        if statusMenuItems.first(where: { $0.title == "停止" })?.enabled != true {
            failures.append("自動再試行が有効な停止中の status menu で 停止 が有効ではありません。")
        }

        let applicationTitles = applicationMenuItems.map(\.title)
        let expectedApplicationTitles = [
            "設定...",
            "権限とデバイスを確認",
            "アクセシビリティ設定を開く",
            "入力監視設定を開く",
            "Nape Gesture を終了"
        ]
        for title in expectedApplicationTitles where !applicationTitles.contains(title) {
            failures.append("application menu に \(title) がありません。")
        }

        guard failures.isEmpty else {
            throw ToolError.guiSmokeFailed(failures.joined(separator: "\n"))
        }
    }
}

struct StatusAppSmokeMenuItem: Codable {
    var title: String
    var enabled: Bool
    var isSeparator: Bool

    init(_ item: NSMenuItem) {
        title = item.title
        enabled = item.isEnabled
        isSeparator = item.isSeparatorItem
    }
}

private enum InputMonitoringProbeResult {
    case granted
    case failed(String)
    case notProbed(String)

    var granted: Bool? {
        switch self {
        case .granted:
            return true
        case .failed:
            return false
        case .notProbed:
            return nil
        }
    }

    var detail: String {
        switch self {
        case .granted:
            return "許可済み"
        case let .failed(message):
            return "未許可または開始失敗: \(message)"
        case let .notProbed(message):
            return "未判定: \(message)"
        }
    }
}

private extension GUIAppLaunchPresentation {
    var activationPolicyValue: NSApplication.ActivationPolicy {
        switch activationPolicy {
        case "regular":
            return .regular
        case "accessory":
            return .accessory
        default:
            return .prohibited
        }
    }
}

private extension NSApplication.ActivationPolicy {
    var smokeValue: String {
        switch self {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }
}
