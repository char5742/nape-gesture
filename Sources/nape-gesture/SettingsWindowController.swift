import AppKit
import Foundation
import NapeGestureCore

final class SettingsWindowController: NSWindowController {
    var onSave: ((NapeGestureSettings) -> Void)?

    private var settings: NapeGestureSettings
    private let configPath: String
    private let associationWindowField = NSTextField()
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
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 700),
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
        associationWindowField.stringValue = String(settings.targetDeviceAssociation.associationWindow)
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
            let maximumDuration = Double(maximumDurationField.stringValue),
            let maximumInactivity = Double(maximumInactivityField.stringValue)
        else {
            showError("数値項目の形式が不正です。")
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

        let targetDevices = matcher.hasAnyCondition ? [matcher] : []
        let updated = NapeGestureSettings(
            gesture: GestureConfiguration(
                cancellation: GestureCancellationConfiguration(
                    maximumDuration: maximumDuration,
                    maximumInactivityInterval: maximumInactivity
                )
            ),
            targetDeviceAssociation: TargetDeviceAssociationConfiguration(
                associationWindow: associationWindow
            ),
            targetDevices: targetDevices,
            requireMatchingTargetDevice: requireTargetCheck.state == .on
        )

        let issues = SettingsValidator.issues(for: updated)
        guard issues.isEmpty else {
            showError(issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n"))
            return
        }

        settings = updated
        onSave?(updated)
    }

    @objc private func closeWindow() {
        close()
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
        case .fixedButton3Gesture, .fixedButton4Gesture, .fixedButton5Gesture:
            return label(field.descriptor.fixedValue ?? "", fontSize: 13)
        case .targetDeviceAssociationWindow:
            return associationWindowField
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
