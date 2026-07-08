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

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()
        installStatusItem()
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
        let accessibility = AccessibilityPermission.isTrusted ? "許可済み" : "未許可"
        let identity = RuntimeIdentity.current
        let allDevices = (try? DeviceInventory.allDevices()) ?? []
        let devices = (try? DeviceInventory.pointingDevices()) ?? []
        let matched = (try? DeviceInventory.matchedDevices(settings: settings)) ?? []
        let inputMonitoring = probeInputMonitoring(matchedDevices: matched)

        var lines = [
            "アクセシビリティ: \(accessibility)",
            "入力監視: \(inputMonitoring)",
            "権限対象: \(identity.permissionTargetDescription)",
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

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
            lines.append("アクセシビリティ未許可の場合は、権限対象を許可してからアプリを再起動してください。")
        }

        showAlert(title: "権限とデバイス", message: lines.joined(separator: "\n"))
    }

    private func probeInputMonitoring(matchedDevices: [DeviceIdentity]) -> String {
        if runtime.isRunning {
            return "実行中"
        }

        let gate = SharedTargetDeviceGate(
            configuration: TargetDeviceGateConfiguration(settings: settings)
        )
        let monitor = HIDInputMonitor(settings: settings, gate: gate, matchedDevices: matchedDevices)

        do {
            try monitor.start()
            monitor.stop()
            return "許可済み"
        } catch {
            monitor.stop()
            return "未許可または開始失敗: \(describe(error))"
        }
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
