import AppKit
import Foundation
import NapeGestureCore

final class SettingsWindowController: NSWindowController {
    var onSave: ((NapeGestureSettings) -> Void)?

    private var settings: NapeGestureSettings
    private let configPath: String
    private let activationButtonField = NSTextField()
    private let associationWindowField = NSTextField()
    private let deadZoneField = NSTextField()
    private let directionLockField = NSTextField()
    private let dragSensitivityField = NSTextField()
    private let wheelSensitivityField = NSTextField()
    private let accelerationEnabledCheck = NSButton(checkboxWithTitle: "速度に応じて加速度を適用する", target: nil, action: nil)
    private let accelerationThresholdField = NSTextField()
    private let accelerationExponentField = NSTextField()
    private let accelerationMaximumField = NSTextField()
    private let momentumEnabledCheck = NSButton(checkboxWithTitle: "慣性スクロールを適用する", target: nil, action: nil)
    private let momentumMinimumStartVelocityField = NSTextField()
    private let momentumStopVelocityField = NSTextField()
    private let momentumDecayField = NSTextField()
    private let momentumFrameIntervalField = NSTextField()
    private let maximumDurationField = NSTextField()
    private let maximumInactivityField = NSTextField()
    private let offAxisCancelRatioField = NSTextField()
    private let targetVendorIDField = NSTextField()
    private let targetProductIDField = NSTextField()
    private let targetManufacturerField = NSTextField()
    private let targetProductField = NSTextField()
    private let targetTransportField = NSTextField()
    private let targetUsagePageField = NSTextField()
    private let targetUsageField = NSTextField()
    private let requireTargetCheck = NSButton(checkboxWithTitle: "対象デバイス一致を必須にする", target: nil, action: nil)
    private let dragUpPopup = NSPopUpButton()
    private let dragDownPopup = NSPopUpButton()
    private let dragLeftPopup = NSPopUpButton()
    private let dragRightPopup = NSPopUpButton()
    private let wheelPopup = NSPopUpButton()

    init(settings: NapeGestureSettings, configPath: String) {
        self.settings = settings
        self.configPath = configPath
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 900),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nape Gesture 設定"
        super.init(window: window)
        buildContent()
        populate(settings)
        window.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let window else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(label("設定ファイル: \(configPath)", fontSize: 11))
        stack.addArrangedSubview(row("ジェスチャーボタン番号", activationButtonField))
        stack.addArrangedSubview(row("対象入力の紐づけ秒", associationWindowField))
        stack.addArrangedSubview(row("デッドゾーン pt", deadZoneField))
        stack.addArrangedSubview(row("方向ロック比", directionLockField))
        stack.addArrangedSubview(row("ドラッグ感度", dragSensitivityField))
        stack.addArrangedSubview(row("ホイール感度", wheelSensitivityField))
        stack.addArrangedSubview(accelerationEnabledCheck)
        stack.addArrangedSubview(row("加速度しきい速度", accelerationThresholdField))
        stack.addArrangedSubview(row("加速度指数", accelerationExponentField))
        stack.addArrangedSubview(row("加速度最大倍率", accelerationMaximumField))
        stack.addArrangedSubview(momentumEnabledCheck)
        stack.addArrangedSubview(row("慣性開始しきい速度", momentumMinimumStartVelocityField))
        stack.addArrangedSubview(row("慣性停止速度", momentumStopVelocityField))
        stack.addArrangedSubview(row("慣性減衰率/秒", momentumDecayField))
        stack.addArrangedSubview(row("慣性フレーム間隔秒", momentumFrameIntervalField))
        stack.addArrangedSubview(row("最大ジェスチャー秒", maximumDurationField))
        stack.addArrangedSubview(row("無入力キャンセル秒", maximumInactivityField))
        stack.addArrangedSubview(row("軸ずれキャンセル比", offAxisCancelRatioField))
        stack.addArrangedSubview(row("対象 vendor ID", targetVendorIDField))
        stack.addArrangedSubview(row("対象 product ID", targetProductIDField))
        stack.addArrangedSubview(row("対象メーカーに含む文字", targetManufacturerField))
        stack.addArrangedSubview(row("対象製品名に含む文字", targetProductField))
        stack.addArrangedSubview(row("対象 transport に含む文字", targetTransportField))
        stack.addArrangedSubview(row("対象 usagePage", targetUsagePageField))
        stack.addArrangedSubview(row("対象 usage", targetUsageField))
        stack.addArrangedSubview(requireTargetCheck)
        stack.addArrangedSubview(separator())

        configurePopup(dragUpPopup)
        configurePopup(dragDownPopup)
        configurePopup(dragLeftPopup)
        configurePopup(dragRightPopup)
        configurePopup(wheelPopup)

        stack.addArrangedSubview(row("上ドラッグ", dragUpPopup))
        stack.addArrangedSubview(row("下ドラッグ", dragDownPopup))
        stack.addArrangedSubview(row("左ドラッグ", dragLeftPopup))
        stack.addArrangedSubview(row("右ドラッグ", dragRightPopup))
        stack.addArrangedSubview(row("ホイール", wheelPopup))
        stack.addArrangedSubview(separator())

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10
        buttons.addArrangedSubview(NSView())
        buttons.addArrangedSubview(button("保存して再起動", action: #selector(save)))
        buttons.addArrangedSubview(button("閉じる", action: #selector(closeWindow)))
        stack.addArrangedSubview(buttons)

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        scrollView.documentView = documentView
        rootView.addSubview(scrollView)
        window.contentView = rootView
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])
    }

    private func populate(_ settings: NapeGestureSettings) {
        activationButtonField.stringValue = String(settings.gesture.activationButton.rawValue)
        associationWindowField.stringValue = String(settings.targetDeviceAssociation.associationWindow)
        deadZoneField.stringValue = String(settings.gesture.deadZonePoints)
        directionLockField.stringValue = String(settings.gesture.directionLockRatio)
        dragSensitivityField.stringValue = String(settings.gesture.dragSensitivity)
        wheelSensitivityField.stringValue = String(settings.gesture.wheelSensitivity)
        accelerationEnabledCheck.state = settings.gesture.acceleration.isEnabled ? .on : .off
        accelerationThresholdField.stringValue = String(settings.gesture.acceleration.thresholdVelocity)
        accelerationExponentField.stringValue = String(settings.gesture.acceleration.exponent)
        accelerationMaximumField.stringValue = String(settings.gesture.acceleration.maximumMultiplier)
        momentumEnabledCheck.state = settings.gesture.momentum.isEnabled ? .on : .off
        momentumMinimumStartVelocityField.stringValue = String(settings.gesture.momentum.minimumStartVelocity)
        momentumStopVelocityField.stringValue = String(settings.gesture.momentum.stopVelocity)
        momentumDecayField.stringValue = String(settings.gesture.momentum.decayPerSecond)
        momentumFrameIntervalField.stringValue = String(settings.gesture.momentum.frameInterval)
        maximumDurationField.stringValue = String(settings.gesture.cancellation.maximumDuration)
        maximumInactivityField.stringValue = String(settings.gesture.cancellation.maximumInactivityInterval)
        offAxisCancelRatioField.stringValue = String(settings.gesture.cancellation.offAxisCancelRatio)
        let matcher = settings.targetDevices.first
        targetVendorIDField.stringValue = string(for: matcher?.vendorID)
        targetProductIDField.stringValue = string(for: matcher?.productID)
        targetManufacturerField.stringValue = matcher?.manufacturerContains ?? ""
        targetProductField.stringValue = matcher?.productContains ?? ""
        targetTransportField.stringValue = matcher?.transportContains ?? ""
        targetUsagePageField.stringValue = string(for: matcher?.primaryUsagePage)
        targetUsageField.stringValue = string(for: matcher?.primaryUsage)
        requireTargetCheck.state = settings.requireMatchingTargetDevice ? .on : .off
        select(settings.gesture.bindings.dragUp, in: dragUpPopup)
        select(settings.gesture.bindings.dragDown, in: dragDownPopup)
        select(settings.gesture.bindings.dragLeft, in: dragLeftPopup)
        select(settings.gesture.bindings.dragRight, in: dragRightPopup)
        select(settings.gesture.bindings.wheel, in: wheelPopup)
    }

    @objc private func save() {
        guard
            let activationButton = Int(activationButtonField.stringValue),
            let associationWindow = Double(associationWindowField.stringValue),
            let deadZone = Double(deadZoneField.stringValue),
            let directionLockRatio = Double(directionLockField.stringValue),
            let dragSensitivity = Double(dragSensitivityField.stringValue),
            let wheelSensitivity = Double(wheelSensitivityField.stringValue),
            let accelerationThreshold = Double(accelerationThresholdField.stringValue),
            let accelerationExponent = Double(accelerationExponentField.stringValue),
            let accelerationMaximum = Double(accelerationMaximumField.stringValue),
            let momentumMinimumStartVelocity = Double(momentumMinimumStartVelocityField.stringValue),
            let momentumStopVelocity = Double(momentumStopVelocityField.stringValue),
            let momentumDecay = Double(momentumDecayField.stringValue),
            let momentumFrameInterval = Double(momentumFrameIntervalField.stringValue),
            let maximumDuration = Double(maximumDurationField.stringValue),
            let maximumInactivity = Double(maximumInactivityField.stringValue),
            let offAxisCancelRatio = Double(offAxisCancelRatioField.stringValue)
        else {
            showError("数値項目の形式が不正です。")
            return
        }

        guard associationWindow > 0,
              deadZone >= 0,
              directionLockRatio >= 1,
              dragSensitivity > 0,
              wheelSensitivity > 0,
              accelerationThreshold >= 0,
              accelerationExponent >= 0,
              accelerationMaximum >= 1,
              momentumMinimumStartVelocity >= 0,
              momentumStopVelocity >= 0,
              momentumDecay > 0,
              momentumDecay <= 1,
              momentumFrameInterval > 0,
              maximumDuration >= 0,
              maximumInactivity >= 0,
              offAxisCancelRatio >= 0
        else {
            showError("数値項目は、デッドゾーン、加速度しきい速度、加速度指数、慣性速度、キャンセル秒数は0以上、方向ロック比と加速度最大倍率は1以上、対象入力の紐づけ秒、慣性減衰率、感度、慣性フレーム間隔は0より大きい値にしてください。慣性減衰率は1以下にしてください。")
            return
        }

        let matcher: DeviceMatcher
        do {
            matcher = DeviceMatcher(
                vendorID: try optionalInt(targetVendorIDField, name: "対象 vendor ID"),
                productID: try optionalInt(targetProductIDField, name: "対象 product ID"),
                manufacturerContains: optionalText(targetManufacturerField),
                productContains: optionalText(targetProductField),
                transportContains: optionalText(targetTransportField),
                primaryUsagePage: try optionalInt(targetUsagePageField, name: "対象 usagePage"),
                primaryUsage: try optionalInt(targetUsageField, name: "対象 usage")
            )
        } catch let error as SettingsInputError {
            showError(error.message)
            return
        } catch {
            showError("対象デバイス条件の形式が不正です。")
            return
        }

        if !matcher.hasAnyCondition && requireTargetCheck.state == .on {
            showError("対象デバイス一致を必須にする場合は、vendor ID、product ID、製品名、usage などの条件を1つ以上入力してください。")
            return
        }

        let targetDevices = matcher.hasAnyCondition ? [matcher] : []
        let updated = NapeGestureSettings(
            gesture: GestureConfiguration(
                activationButton: MouseButton(rawValue: activationButton) ?? .button4,
                deadZonePoints: deadZone,
                directionLockRatio: directionLockRatio,
                dragSensitivity: dragSensitivity,
                wheelSensitivity: wheelSensitivity,
                acceleration: GestureAccelerationConfiguration(
                    isEnabled: accelerationEnabledCheck.state == .on,
                    thresholdVelocity: accelerationThreshold,
                    exponent: accelerationExponent,
                    maximumMultiplier: accelerationMaximum
                ),
                cancellation: GestureCancellationConfiguration(
                    maximumDuration: maximumDuration,
                    maximumInactivityInterval: maximumInactivity,
                    offAxisCancelRatio: offAxisCancelRatio
                ),
                momentum: MomentumConfiguration(
                    isEnabled: momentumEnabledCheck.state == .on,
                    minimumStartVelocity: momentumMinimumStartVelocity,
                    stopVelocity: momentumStopVelocity,
                    decayPerSecond: momentumDecay,
                    frameInterval: momentumFrameInterval
                ),
                bindings: GestureBindings(
                    dragUp: selectedAction(dragUpPopup),
                    dragDown: selectedAction(dragDownPopup),
                    dragLeft: selectedAction(dragLeftPopup),
                    dragRight: selectedAction(dragRightPopup),
                    wheel: selectedAction(wheelPopup)
                )
            ),
            targetDeviceAssociation: TargetDeviceAssociationConfiguration(
                associationWindow: associationWindow
            ),
            targetDevices: targetDevices,
            requireMatchingTargetDevice: requireTargetCheck.state == .on
        )

        settings = updated
        onSave?(updated)
    }

    @objc private func closeWindow() {
        close()
    }

    private func configurePopup(_ popup: NSPopUpButton) {
        for action in GestureAction.settingsSelectableActions {
            popup.addItem(withTitle: action.rawValue)
        }
    }

    private func select(_ action: GestureAction, in popup: NSPopUpButton) {
        popup.selectItem(withTitle: action.rawValue)
    }

    private func selectedAction(_ popup: NSPopUpButton) -> GestureAction {
        GestureAction(rawValue: popup.titleOfSelectedItem ?? "") ?? .none
    }

    private func optionalText(_ field: NSTextField) -> String? {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func optionalInt(_ field: NSTextField, name: String) throws -> Int? {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        guard let integer = Int(value) else {
            throw SettingsInputError(message: "\(name) は整数で入力してください。")
        }
        return integer
    }

    private func string(for value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let titleLabel = label(title, fontSize: 13)
        titleLabel.widthAnchor.constraint(equalToConstant: 160).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(control)
        return row
    }

    private func label(_ text: String, fontSize: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: fontSize)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "設定エラー"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct SettingsInputError: Error {
    var message: String
}
