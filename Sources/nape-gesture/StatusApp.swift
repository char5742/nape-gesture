import AppKit
import Foundation
import NapeGestureCore
import NapeGestureProductOutput

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
        runtime.onTerminalFailure = { [weak self] _, failureKind in
            guard let self else {
                return
            }
            _ = recoveryState.recordRuntimeFailure(failureKind, at: currentTime())
            refreshMenu()
        }
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
        runtime.onTerminalFailure = nil
        runtime.stop()
        Self.retainedDelegate = nil
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(
            systemSymbolName: "hand.draw",
            accessibilityDescription: "Nape Gesture"
        ) {
            image.isTemplate = true
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "NG"
        }
        item.button?.toolTip = "Nape Gesture"
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

        let settingsItem = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "権限とデバイスを確認", action: #selector(checkPermissions), keyEquivalent: "")
        permissionsItem.target = self
        appMenu.addItem(permissionsItem)

        let systemSettingsItem = NSMenuItem(title: "システム設定", action: nil, keyEquivalent: "")
        let systemSettingsMenu = NSMenu(title: "システム設定")
        let accessibilitySettingsItem = NSMenuItem(title: "アクセシビリティ", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilitySettingsItem.target = self
        systemSettingsMenu.addItem(accessibilitySettingsItem)

        let inputMonitoringSettingsItem = NSMenuItem(title: "入力監視", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        inputMonitoringSettingsItem.target = self
        systemSettingsMenu.addItem(inputMonitoringSettingsItem)
        systemSettingsItem.submenu = systemSettingsMenu
        appMenu.addItem(systemSettingsItem)

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
        settingsWindow?.updateRuntimeStatus(
            presentation,
            errorMessage: runtime.lastError?.localizedDescription
        )
        menu.addItem(NSMenuItem(title: presentation.stateTitle, action: nil, keyEquivalent: ""))

        if let error = runtime.lastError {
            menu.addItem(NSMenuItem(title: "エラー: \(error.localizedDescription)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        if presentation.startEnabled {
            menu.addItem(menuItem("ジェスチャーを開始", action: #selector(startRuntime), enabled: true))
        }
        if runtime.isRunning {
            menu.addItem(menuItem("ジェスチャーを停止", action: #selector(stopRuntime), enabled: true))
        } else if recoveryState.shouldShowAutoRetry {
            menu.addItem(menuItem("自動再試行を停止", action: #selector(stopRuntime), enabled: true))
        }
        menu.addItem(menuItem("設定…", action: #selector(openSettings), enabled: true))
        menu.addItem(menuItem("権限とデバイスを確認", action: #selector(checkPermissions), enabled: true))

        let systemSettingsItem = NSMenuItem(title: "システム設定", action: nil, keyEquivalent: "")
        let systemSettingsMenu = NSMenu(title: "システム設定")
        systemSettingsMenu.addItem(menuItem("アクセシビリティ", action: #selector(openAccessibilitySettings), enabled: true))
        systemSettingsMenu.addItem(menuItem("入力監視", action: #selector(openInputMonitoringSettings), enabled: true))
        systemSettingsItem.submenu = systemSettingsMenu
        menu.addItem(systemSettingsItem)
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

        let runtimePresentation = RuntimeStatusPresenter.present(
            isRuntimeRunning: runtime.isRunning,
            recoveryState: recoveryState
        )
        let controller = SettingsWindowController(
            settings: settings,
            configPath: configPath,
            runtimePresentation: runtimePresentation,
            runtimeErrorMessage: runtime.lastError?.localizedDescription
        )
        controller.onCheckPermissions = { [weak self] in
            self?.checkPermissions()
        }
        controller.onSave = { [weak self] updated in
            guard let self else {
                return
            }
            try SettingsStore.write(updated, to: configPath)
            settings = updated
            let decision = recoveryState.recordSettingsSaved(at: currentTime())
            if decision.shouldStartRuntime {
                startRuntimeAndRecordResult()
            }
            refreshMenu()
        }
        settingsWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkPermissions() {
        let accessibilityTrusted = AccessibilityPermission.isTrusted
        let identity = RuntimeIdentity.current
        let inventory = PermissionDeviceInventory.load(settings: settings)
        let inputMonitoring = inventory.error == nil
            ? probeInputMonitoring(matchedDevices: inventory.matchedDevices)
            : .notProbed("HIDデバイス一覧の取得に失敗したため、入力監視を確認できません。")
        let diagnosticIdentity = OperatingSystemDiagnosticIdentity.current()
        let outputCapability = TrackpadGestureOutputAdapter().capability
        let requiredFamilies: Set<TrackpadOutputEventFamily> = [
            .scroll,
            .dockSwipe,
            .dockSwipePinch,
        ]
        let missingFamilies = requiredFamilies.subtracting(outputCapability.supportedFamilies)
            .map(\.rawValue)
            .sorted()
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
            "macOS: \(diagnosticIdentity?.version ?? "取得失敗")",
            "OS build: \(diagnosticIdentity?.build ?? "取得失敗")",
            "出力contract: \(outputCapability.status.rawValue)",
            "出力contract ID: \(outputCapability.contract?.contractID ?? "なし")",
            "出力fixture: \(outputCapability.contract?.fixtureID ?? "なし")",
            "出力fixture SHA-256: \(outputCapability.contract?.fixtureSHA256 ?? "なし")",
            "固定必須family: \(requiredFamilies.map(\.rawValue).sorted().joined(separator: ", "))",
            "不足family: \(missingFamilies.isEmpty ? "なし" : missingFamilies.joined(separator: ", "))",
            "キルスイッチ: \(KillSwitchShortcut.displayName)",
            "実行状態: \(runtime.isRunning ? "実行中" : "停止中")",
            "設定ファイル: \(configPath)",
            "ボタン3: \(settings.gesture.buttonAssignments.button3.displayName)",
            "ボタン4: \(settings.gesture.buttonAssignments.button4.displayName)",
            "ボタン5: \(settings.gesture.buttonAssignments.button5.displayName)",
            "システムジェスチャー感度: \(Int((settings.gesture.systemGestureSensitivity * 100).rounded()))%",
            "対象入力の紐づけ秒: \(settings.targetDeviceAssociation.associationWindow)",
            "HIDデバイス数: \(inventory.allDeviceCountDescription)",
            "マウスインターフェース数: \(inventory.mouseInterfaceCountDescription)",
            "対象一致数: \(inventory.matchedDeviceCountDescription)",
            "自動再試行: \(recoveryState.autoRetryEnabled ? "有効" : "無効")"
        ]

        if let error = runtime.lastError {
            lines.append("直近エラー: \(error.localizedDescription)")
        }
        if let reason = outputCapability.reason {
            lines.append("fail-closed理由: \(reason)")
        }

        if let inventoryError = inventory.error {
            lines.append("HID inventoryエラー: \(inventoryError)")
        }
        if !inventory.matchedDevices.isEmpty {
            lines.append("対象: " + inventory.matchedDevices.map(\.displayName).joined(separator: ", "))
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
        let settingsContentSize = settingsWindow?.window?.contentView?.bounds.size
        let settingsWindowSmoke = settingsWindow?.makeSmokeSnapshot()
        return StatusAppSmokeSnapshot(
            runtimeIdentity: RuntimeIdentity.current,
            activationPolicy: NSApp.activationPolicy().smokeValue,
            expectedActivationPolicy: launchPresentation.activationPolicy,
            opensSettingsWindowOnLaunch: launchPresentation.opensSettingsWindowOnLaunch,
            reopensSettingsWindowFromDock: launchPresentation.reopensSettingsWindowFromDock,
            keepsStatusMenu: launchPresentation.keepsStatusMenu,
            bundleLSUIElement: launchPresentation.bundleLSUIElement,
            statusItemTitle: statusItem?.button?.title,
            statusItemUsesSystemImage: statusItem?.button?.image != nil,
            statusMenuItems: statusItem?.menu?.items.map(StatusAppSmokeMenuItem.init) ?? [],
            applicationMenuItems: NSApp.mainMenu?.items.first?.submenu?.items.map(StatusAppSmokeMenuItem.init) ?? [],
            settingsWindowTitle: settingsWindow?.window?.title,
            settingsWindowIsVisible: settingsWindow?.window?.isVisible ?? false,
            settingsToolbarItems: settingsWindow?.window?.toolbar?.items.map(\.label) ?? [],
            settingsWindowContentWidth: settingsContentSize.map { Double($0.width) },
            settingsWindowContentHeight: settingsContentSize.map { Double($0.height) },
            settingsWindowSmoke: settingsWindowSmoke,
            permissionInventoryFailureIsDistinct: PermissionDeviceInventory.smokeFailureIsDistinct,
            runtimeIdentityClassificationIsStrict: RuntimeIdentitySmokeCheck.isStrict
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
    var statusItemUsesSystemImage: Bool
    var statusMenuItems: [StatusAppSmokeMenuItem]
    var applicationMenuItems: [StatusAppSmokeMenuItem]
    var settingsWindowTitle: String?
    var settingsWindowIsVisible: Bool
    var settingsToolbarItems: [String]
    var settingsWindowContentWidth: Double?
    var settingsWindowContentHeight: Double?
    var settingsWindowSmoke: SettingsWindowSmokeSnapshot?
    var permissionInventoryFailureIsDistinct: Bool
    var runtimeIdentityClassificationIsStrict: Bool

    func assertRegularGUI() throws {
        var failures: [String] = []
        if activationPolicy != expectedActivationPolicy {
            failures.append("activationPolicy が \(expectedActivationPolicy) ではありません: \(activationPolicy)")
        }
        if !statusItemUsesSystemImage && statusItemTitle != "NG" {
            failures.append("status item に system image または NG fallback がありません。")
        }
        let expectedSettingsWindowTitles = [
            "Nape Gesture - ジェスチャー",
            "Nape Gesture - 詳細",
        ]
        if !expectedSettingsWindowTitles.contains(settingsWindowTitle ?? "") {
            failures.append("設定ウィンドウ title が有効なpaneを示していません: \(settingsWindowTitle ?? "なし")")
        }
        if !settingsWindowIsVisible {
            failures.append("設定ウィンドウが表示状態ではありません。")
        }
        if settingsToolbarItems != ["ジェスチャー", "詳細"] {
            failures.append("設定toolbarがジェスチャー / 詳細の固定paneではありません: \(settingsToolbarItems)")
        }
        if abs((settingsWindowContentWidth ?? 0) - 680) > 1
            || abs((settingsWindowContentHeight ?? 0) - 620) > 1
        {
            failures.append(
                "設定ウィンドウのcontent sizeが680x620ではありません: "
                    + "\(settingsWindowContentWidth ?? 0)x\(settingsWindowContentHeight ?? 0)"
            )
        }

        if let settingsWindowSmoke {
            let expectedToolbarIdentifier = "settings.\(settingsWindowSmoke.selectedPane)"
            if settingsWindowSmoke.selectedToolbarItemIdentifier != expectedToolbarIdentifier {
                failures.append(
                    "選択paneとtoolbar itemが一致しません: "
                        + "pane=\(settingsWindowSmoke.selectedPane) "
                        + "toolbar=\(settingsWindowSmoke.selectedToolbarItemIdentifier ?? "なし")"
                )
            }
            if settingsWindowSmoke.windowIsResizable {
                failures.append("設定ウィンドウが意図せずresize可能です。")
            }
            if settingsWindowSmoke.initiallyApplyEnabled {
                failures.append("未変更の設定で変更を適用が有効です。")
            }
            if !settingsWindowSmoke.initiallyAdvancedConditionsHidden {
                failures.append("詳細な識別条件が初期状態で展開されています。")
            }
            let availableAssignments = Set(FixedGestureClass.allCases.map(\.displayName))
            if settingsWindowSmoke.buttonAssignmentSelections.count != 3
                || !settingsWindowSmoke.buttonAssignmentSelections.allSatisfy(
                    availableAssignments.contains
                )
                || settingsWindowSmoke.buttonAssignmentOptionCounts != [3, 3, 3]
            {
                failures.append(
                    "button割り当てcontrolが製品契約と一致しません: "
                        + "selected=\(settingsWindowSmoke.buttonAssignmentSelections) "
                        + "options=\(settingsWindowSmoke.buttonAssignmentOptionCounts)"
                )
            }
            if !settingsWindowSmoke.buttonAssignmentEditEnablesApply
                || !settingsWindowSmoke.buttonAssignmentRevertDisablesApply
                || !settingsWindowSmoke.buttonAssignmentIncludedInUpdatedSettings
            {
                failures.append("button割り当て変更、保存値、または復元時の状態が不正です。")
            }
            let expectedPassthrough = "ボタン3、4、5を押していない間は、通常のマウスとして動作します。"
            if settingsWindowSmoke.passthroughText != expectedPassthrough {
                failures.append("通常mouseへの復帰条件が設定画面に表示されていません。")
            }
            if settingsWindowSmoke.runtimeStatusText.isEmpty
                || !settingsWindowSmoke.runtimeStatusUsesSystemImage
            {
                failures.append("runtime状態がsystem image付きで表示されていません。")
            }
            if !settingsWindowSmoke.dirtyEditEnablesApply
                || !settingsWindowSmoke.revertingEditDisablesApply
            {
                failures.append("設定変更または復元時の適用button状態が不正です。")
            }
            if !settingsWindowSmoke.disclosureExpands
                || !settingsWindowSmoke.disclosureCollapses
            {
                failures.append("詳細な識別条件の開閉が完結しません。")
            }
            if !settingsWindowSmoke.paneSwitchesContent {
                failures.append("ジェスチャー / 詳細paneの切り替えが内容へ反映されません。")
            }
            if settingsWindowSmoke.gestureSensitivitySliderCount != 1
                || !settingsWindowSmoke.gestureSensitivityPercentText.hasSuffix("%")
                || !settingsWindowSmoke.gestureSensitivityEditEnablesApply
            {
                failures.append("共有システムジェスチャー感度controlが正しく動作しません。")
            }
            if settingsWindowSmoke.detailsEditableTextFieldCount != 10
                || settingsWindowSmoke.detailsCheckboxCount != 1
            {
                failures.append(
                    "詳細paneの安全設定control数が不正です: "
                        + "text=\(settingsWindowSmoke.detailsEditableTextFieldCount) "
                        + "checkbox=\(settingsWindowSmoke.detailsCheckboxCount)"
                )
            }
            if !settingsWindowSmoke.multipleMatchersPreserved {
                failures.append("GUIで先頭条件を編集した際に後続の対象device条件が失われます。")
            }
            if !settingsWindowSmoke.saveFailureKeepsDirtyState {
                failures.append("設定保存失敗後に未保存状態と再試行可能なApplyが保持されません。")
            }
        } else {
            failures.append("設定ウィンドウの操作smoke結果がありません。")
        }
        if !permissionInventoryFailureIsDistinct {
            failures.append("HID inventory取得失敗がdevice 0件として表示されます。")
        }
        if !runtimeIdentityClassificationIsStrict {
            failures.append("CLIまたは曖昧な起動をLaunchServices GUIとして誤分類できます。")
        }

        let statusTitles = statusMenuItems.map(\.title)
        let expectedStatusTitles = [
            "状態: 停止中",
            "ジェスチャーを開始",
            "設定…",
            "権限とデバイスを確認",
            "システム設定",
            "終了"
        ]
        for title in expectedStatusTitles where !statusTitles.contains(title) {
            failures.append("status menu に \(title) がありません。")
        }
        if statusMenuItems.first(where: { $0.title == "ジェスチャーを開始" })?.enabled != true {
            failures.append("停止中の status menu で ジェスチャーを開始 が有効ではありません。")
        }
        if statusTitles.contains("ジェスチャーを停止") || statusTitles.contains("自動再試行を停止") {
            failures.append("待機中の status menu に不要な停止操作があります。")
        }

        let applicationTitles = applicationMenuItems.map(\.title)
        let expectedApplicationTitles = [
            "設定…",
            "権限とデバイスを確認",
            "システム設定",
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

private enum RuntimeIdentitySmokeCheck {
    private static let bundlePath = "/Applications/Nape Gesture.app"
    private static let bundleIdentifier = "dev.char5742.nape-gesture"

    static var isStrict: Bool {
        let launchServices = RuntimeIdentity.resolveLaunchContext(
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            parentProcessIdentifier: 1,
            xpcServiceName: "application.\(bundleIdentifier).smoke",
            environmentBundleIdentifier: bundleIdentifier
        )
        let forgedCLI = RuntimeIdentity.resolveLaunchContext(
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            parentProcessIdentifier: 42,
            xpcServiceName: "application.\(bundleIdentifier).smoke",
            environmentBundleIdentifier: bundleIdentifier
        )
        let ambiguous = RuntimeIdentity.resolveLaunchContext(
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            parentProcessIdentifier: 1,
            xpcServiceName: nil,
            environmentBundleIdentifier: nil
        )
        let plainExecutable = RuntimeIdentity.resolveLaunchContext(
            bundlePath: "/tmp/nape-gesture",
            bundleIdentifier: nil,
            parentProcessIdentifier: 1,
            xpcServiceName: "application.\(bundleIdentifier).smoke",
            environmentBundleIdentifier: bundleIdentifier
        )
        return launchServices == .launchServicesApp
            && forgedCLI == .commandLine
            && ambiguous == .unknown
            && plainExecutable == .commandLine
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

private struct PermissionDeviceInventory {
    var allDevices: [DeviceIdentity]?
    var mouseInterfaces: [DeviceIdentity]?
    var matchedDevices: [DeviceIdentity]
    var error: String?

    static func load(settings: NapeGestureSettings) -> PermissionDeviceInventory {
        do {
            let allDevices = try DeviceInventory.allDevices()
            let mouseInterfaces = DeviceInventory.mouseInterfaces(in: allDevices)
            let matchedDevices = DeviceInventory.matchedDevices(
                in: allDevices,
                settings: settings
            )
            return PermissionDeviceInventory(
                allDevices: allDevices,
                mouseInterfaces: mouseInterfaces,
                matchedDevices: matchedDevices,
                error: nil
            )
        } catch {
            return failure(error.localizedDescription)
        }
    }

    static var smokeFailureIsDistinct: Bool {
        let failed = failure("smoke")
        let empty = PermissionDeviceInventory(
            allDevices: [],
            mouseInterfaces: [],
            matchedDevices: [],
            error: nil
        )
        return failed.allDeviceCountDescription == "取得失敗"
            && failed.mouseInterfaceCountDescription == "取得失敗"
            && failed.matchedDeviceCountDescription == "取得失敗"
            && empty.allDeviceCountDescription == "0"
            && empty.mouseInterfaceCountDescription == "0"
            && empty.matchedDeviceCountDescription == "0"
    }

    var allDeviceCountDescription: String {
        allDevices.map { String($0.count) } ?? "取得失敗"
    }

    var mouseInterfaceCountDescription: String {
        mouseInterfaces.map { String($0.count) } ?? "取得失敗"
    }

    var matchedDeviceCountDescription: String {
        error == nil ? String(matchedDevices.count) : "取得失敗"
    }

    private static func failure(_ message: String) -> PermissionDeviceInventory {
        PermissionDeviceInventory(
            allDevices: nil,
            mouseInterfaces: nil,
            matchedDevices: [],
            error: message
        )
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
