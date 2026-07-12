import AppKit
import Foundation
import NapeGestureCore

final class SettingsWindowController: NSWindowController {
    var onSave: ((NapeGestureSettings) -> Void)?

    private var settings: NapeGestureSettings
    private let configPath: String
    private let button3ModePopup = NSPopUpButton()
    private let button4ModePopup = NSPopUpButton()
    private let button5ModePopup = NSPopUpButton()
    private let associationWindowField = NSTextField()
    private let deadZoneField = NSTextField()
    private let dragSensitivityField = NSTextField()
    private let wheelSensitivityField = NSTextField()
    private let accelerationEnabledCheck = NSButton(
        checkboxWithTitle: SettingsUIField.accelerationEnabled.descriptor.label,
        target: nil,
        action: nil
    )
    private let accelerationThresholdField = NSTextField()
    private let accelerationExponentField = NSTextField()
    private let accelerationMaximumField = NSTextField()
    private let momentumEnabledCheck = NSButton(
        checkboxWithTitle: SettingsUIField.momentumEnabled.descriptor.label,
        target: nil,
        action: nil
    )
    private let momentumMinimumStartVelocityField = NSTextField()
    private let momentumStopVelocityField = NSTextField()
    private let momentumDecayField = NSTextField()
    private let momentumFrameIntervalField = NSTextField()
    private let maximumDurationField = NSTextField()
    private let maximumInactivityField = NSTextField()
    private let targetVendorIDField = NSTextField()
    private let targetProductIDField = NSTextField()
    private let targetManufacturerField = NSTextField()
    private let targetProductField = NSTextField()
    private let targetTransportField = NSTextField()
    private let targetUsagePageField = NSTextField()
    private let targetUsageField = NSTextField()
    private let requireTargetCheck = NSButton(
        checkboxWithTitle: SettingsUIField.requireMatchingTargetDevice.descriptor.label,
        target: nil,
        action: nil
    )

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
        configureModePopup(button3ModePopup)
        configureModePopup(button4ModePopup)
        configureModePopup(button5ModePopup)
        for field in SettingsUIField.allCases {
            let control = control(for: field)
            if field.descriptor.controlKind == .checkbox {
                stack.addArrangedSubview(control)
            } else {
                stack.addArrangedSubview(settingsRow(field, control))
            }
        }
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
        select(settings.gesture.button3Mode, in: button3ModePopup)
        select(settings.gesture.button4Mode, in: button4ModePopup)
        select(settings.gesture.button5Mode, in: button5ModePopup)
        associationWindowField.stringValue = String(settings.targetDeviceAssociation.associationWindow)
        deadZoneField.stringValue = String(settings.gesture.deadZonePoints)
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
        let matcher = settings.targetDevices.first
        targetVendorIDField.stringValue = string(for: matcher?.vendorID)
        targetProductIDField.stringValue = string(for: matcher?.productID)
        targetManufacturerField.stringValue = matcher?.manufacturerContains ?? ""
        targetProductField.stringValue = matcher?.productContains ?? ""
        targetTransportField.stringValue = matcher?.transportContains ?? ""
        targetUsagePageField.stringValue = string(for: matcher?.primaryUsagePage)
        targetUsageField.stringValue = string(for: matcher?.primaryUsage)
        requireTargetCheck.state = settings.requireMatchingTargetDevice ? .on : .off
    }

    @objc private func save() {
        guard
            let associationWindow = Double(associationWindowField.stringValue),
            let deadZone = Double(deadZoneField.stringValue),
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
            let maximumInactivity = Double(maximumInactivityField.stringValue)
        else {
            showError("数値項目の形式が不正です。")
            return
        }

        guard associationWindow > 0,
              deadZone >= 0,
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
              maximumInactivity >= 0
        else {
            showError("数値項目は、デッドゾーン、加速度しきい速度、加速度指数、慣性速度、キャンセル秒数は0以上、加速度最大倍率は1以上、対象入力の紐づけ秒、慣性減衰率、感度、慣性フレーム間隔は0より大きい値にしてください。慣性減衰率は1以下にしてください。")
            return
        }

        let matcher: DeviceMatcher
        do {
            matcher = DeviceMatcher(
                vendorID: try optionalInt(targetVendorIDField, field: .targetVendorID),
                productID: try optionalInt(targetProductIDField, field: .targetProductID),
                manufacturerContains: optionalText(targetManufacturerField),
                productContains: optionalText(targetProductField),
                transportContains: optionalText(targetTransportField),
                primaryUsagePage: try optionalInt(targetUsagePageField, field: .targetUsagePage),
                primaryUsage: try optionalInt(targetUsageField, field: .targetUsage)
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
                button3Mode: selectedMode(button3ModePopup),
                button4Mode: selectedMode(button4ModePopup),
                button5Mode: selectedMode(button5ModePopup),
                deadZonePoints: deadZone,
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
                    maximumInactivityInterval: maximumInactivity
                ),
                momentum: MomentumConfiguration(
                    isEnabled: momentumEnabledCheck.state == .on,
                    minimumStartVelocity: momentumMinimumStartVelocity,
                    stopVelocity: momentumStopVelocity,
                    decayPerSecond: momentumDecay,
                    frameInterval: momentumFrameInterval
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

    private func configureModePopup(_ popup: NSPopUpButton) {
        for mode in TrackpadGestureMode.allCases {
            popup.addItem(withTitle: mode.displayName)
            popup.lastItem?.representedObject = mode.rawValue
        }
    }

    private func select(_ mode: TrackpadGestureMode, in popup: NSPopUpButton) {
        popup.selectItem(withTitle: mode.displayName)
    }

    private func selectedMode(_ popup: NSPopUpButton) -> TrackpadGestureMode {
        guard let rawValue = popup.selectedItem?.representedObject as? String else {
            return .none
        }
        return TrackpadGestureMode(rawValue: rawValue) ?? .none
    }

    private func optionalText(_ field: NSTextField) -> String? {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func optionalInt(_ field: NSTextField, field uiField: SettingsUIField) throws -> Int? {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        guard let integer = Int(value) else {
            throw SettingsInputError(message: "\(uiField.descriptor.label) は整数で入力してください。")
        }
        return integer
    }

    private func string(for value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private func settingsRow(_ field: SettingsUIField, _ control: NSView) -> NSStackView {
        row(field.descriptor.label, control)
    }

    private func control(for field: SettingsUIField) -> NSView {
        switch field {
        case .button3Mode:
            return button3ModePopup
        case .button4Mode:
            return button4ModePopup
        case .button5Mode:
            return button5ModePopup
        case .targetDeviceAssociationWindow:
            return associationWindowField
        case .deadZonePoints:
            return deadZoneField
        case .dragSensitivity:
            return dragSensitivityField
        case .wheelSensitivity:
            return wheelSensitivityField
        case .accelerationEnabled:
            return accelerationEnabledCheck
        case .accelerationThresholdVelocity:
            return accelerationThresholdField
        case .accelerationExponent:
            return accelerationExponentField
        case .accelerationMaximumMultiplier:
            return accelerationMaximumField
        case .momentumEnabled:
            return momentumEnabledCheck
        case .momentumMinimumStartVelocity:
            return momentumMinimumStartVelocityField
        case .momentumStopVelocity:
            return momentumStopVelocityField
        case .momentumDecayPerSecond:
            return momentumDecayField
        case .momentumFrameInterval:
            return momentumFrameIntervalField
        case .cancellationMaximumDuration:
            return maximumDurationField
        case .cancellationMaximumInactivityInterval:
            return maximumInactivityField
        case .targetVendorID:
            return targetVendorIDField
        case .targetProductID:
            return targetProductIDField
        case .targetManufacturerContains:
            return targetManufacturerField
        case .targetProductContains:
            return targetProductField
        case .targetTransportContains:
            return targetTransportField
        case .targetUsagePage:
            return targetUsagePageField
        case .targetUsage:
            return targetUsageField
        case .requireMatchingTargetDevice:
            return requireTargetCheck
        }
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
