import AppKit
import Foundation
import MacGestureCore

final class StatusApp: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: StatusApp?

    private let configPath: String
    private let runtime = MacGestureRuntime()
    private var settings: MacGestureSettings
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var retryTimer: Timer?
    private var autoRetryEnabled = true
    private var isSuspendedForSleep = false

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
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        installLifecycleObservers()
        startRetryTimer()
        startRuntime()
    }

    func applicationWillTerminate(_ notification: Notification) {
        retryTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        runtime.stop()
        Self.retainedDelegate = nil
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "MG"
        statusItem = item
    }

    private func refreshMenu() {
        let menu = NSMenu()
        let stateTitle = currentStateTitle()
        menu.addItem(NSMenuItem(title: stateTitle, action: nil, keyEquivalent: ""))

        if let error = runtime.lastError {
            menu.addItem(NSMenuItem(title: "エラー: \(error.localizedDescription)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("開始", action: #selector(startRuntime), enabled: !runtime.isRunning))
        menu.addItem(menuItem("緊急停止", action: #selector(stopRuntime), enabled: runtime.isRunning || autoRetryEnabled))
        menu.addItem(menuItem("停止", action: #selector(stopRuntime), enabled: runtime.isRunning || autoRetryEnabled))
        menu.addItem(menuItem("設定...", action: #selector(openSettings), enabled: true))
        menu.addItem(menuItem("権限とデバイスを確認", action: #selector(checkPermissions), enabled: true))
        menu.addItem(.separator())
        menu.addItem(menuItem("終了", action: #selector(quit), enabled: true))
        statusItem?.menu = menu
    }

    private func currentStateTitle() -> String {
        if runtime.isRunning {
            return "状態: 実行中"
        }
        if isSuspendedForSleep {
            return "状態: スリープ待機中"
        }
        if autoRetryEnabled && runtime.shouldRetryAutomatically {
            return "状態: 停止中（自動再試行中）"
        }
        return "状態: 停止中"
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func startRuntime() {
        autoRetryEnabled = true
        isSuspendedForSleep = false
        runtime.start(settings: settings)
        refreshMenu()
    }

    @objc private func stopRuntime() {
        autoRetryEnabled = false
        isSuspendedForSleep = false
        runtime.stop()
        refreshMenu()
    }

    @objc private func openSettings() {
        let controller = SettingsWindowController(settings: settings, configPath: configPath)
        controller.onSave = { [weak self] updated in
            guard let self else {
                return
            }
            do {
                try SettingsStore.write(updated, to: configPath)
                settings = updated
                autoRetryEnabled = true
                isSuspendedForSleep = false
                runtime.start(settings: updated)
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
            "HIDデバイス数: \(allDevices.count)",
            "ポインティングデバイス数: \(devices.count)",
            "対象一致数: \(matched.count)",
            "自動再試行: \(autoRetryEnabled ? "有効" : "無効")"
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
            configuration: TargetDeviceGateConfiguration(
                activationButton: settings.gesture.activationButton
            )
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
        guard autoRetryEnabled,
              !isSuspendedForSleep
        else {
            return
        }

        if runtime.isRunning {
            if runtime.refreshHealth(settings: settings) {
                refreshMenu()
            }
            return
        }

        guard runtime.shouldRetryAutomatically else {
            return
        }

        runtime.start(settings: settings)
        refreshMenu()
    }

    @objc private func handleWillSleep() {
        isSuspendedForSleep = true
        runtime.stop()
        refreshMenu()
    }

    @objc private func handleDidWake() {
        isSuspendedForSleep = false
        guard autoRetryEnabled else {
            refreshMenu()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + wakeRetryDelay) { [weak self] in
            guard let self, autoRetryEnabled, !isSuspendedForSleep else {
                return
            }
            runtime.start(settings: settings)
            refreshMenu()
        }
    }
}
