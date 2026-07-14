import AppKit
import Foundation
import NapeGestureCore

final class SettingsWindowController: NSWindowController {
    var onSave: ((NapeGestureSettings) throws -> Void)?
    var onCheckPermissions: (() -> Void)?

    private enum Pane: String, CaseIterable {
        case gestures
        case details

        var toolbarIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier("settings.\(rawValue)")
        }

        var title: String {
            switch self {
            case .gestures:
                return "Nape Gesture - ジェスチャー"
            case .details:
                return "Nape Gesture - 詳細"
            }
        }

        var toolbarLabel: String {
            switch self {
            case .gestures:
                return "ジェスチャー"
            case .details:
                return "詳細"
            }
        }

        var symbolName: String {
            switch self {
            case .gestures:
                return "hand.draw"
            case .details:
                return "slider.horizontal.3"
            }
        }

        init?(toolbarIdentifier: NSToolbarItem.Identifier) {
            self.init(rawValue: toolbarIdentifier.rawValue.replacingOccurrences(of: "settings.", with: ""))
        }
    }

    private struct FormState: Equatable {
        var systemGestureSensitivity: Double
        var associationWindow: String
        var maximumDuration: String
        var maximumInactivity: String
        var vendorID: String
        var productID: String
        var manufacturer: String
        var product: String
        var transport: String
        var usagePage: String
        var usage: String
        var requiresMatchingTarget: Bool
    }

    private static let selectedPaneDefaultsKey = "NapeGesture.Settings.selectedPane"
    private static let toolbarIdentifier = NSToolbar.Identifier("NapeGesture.Settings.Toolbar")

    private var settings: NapeGestureSettings
    private let configPath: String
    private var runtimePresentation: RuntimeStatusPresentation
    private var runtimeErrorMessage: String?
    private var selectedPane: Pane
    private var savedFormState: FormState?

    private let paneContainerView = NSView()
    private let gesturesPaneView = NSView()
    private let detailsPaneView = NSView()
    private let runtimeStatusImageView = NSImageView()
    private let runtimeStatusLabel = NSTextField(labelWithString: "")
    private let runtimeErrorLabel = NSTextField(labelWithString: "")
    private let passthroughLabel = NSTextField(wrappingLabelWithString: "")
    private let systemGestureSensitivitySlider = NSSlider(
        value: GestureConfiguration.defaultSystemGestureSensitivity,
        minValue: GestureConfiguration.minimumSystemGestureSensitivity,
        maxValue: GestureConfiguration.maximumSystemGestureSensitivity,
        target: nil,
        action: nil
    )
    private let systemGestureSensitivityValueLabel = NSTextField(labelWithString: "")
    private let applyButton = NSButton(title: "変更を適用", target: nil, action: nil)
    private let advancedDisclosureButton = NSButton(title: "詳細な識別条件", target: nil, action: nil)
    private let advancedConditionsStack = NSStackView()
    private var fixedMappingLabels: [NSTextField] = []

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

    init(
        settings: NapeGestureSettings,
        configPath: String,
        runtimePresentation: RuntimeStatusPresentation,
        runtimeErrorMessage: String?
    ) {
        self.settings = settings
        self.configPath = configPath
        self.runtimePresentation = runtimePresentation
        self.runtimeErrorMessage = runtimeErrorMessage
        self.selectedPane = Self.restoredPane()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = selectedPane.title
        window.toolbarStyle = .preference
        window.isRestorable = false
        super.init(window: window)

        configureToolbar(for: window)
        buildContent()
        let contentSize = NSSize(width: 680, height: 620)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.setContentSize(contentSize)
        populate(settings)
        updateRuntimeStatus(runtimePresentation, errorMessage: runtimeErrorMessage)
        showPane(selectedPane, persistSelection: false)
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        window.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateRuntimeStatus(
        _ presentation: RuntimeStatusPresentation,
        errorMessage: String?
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateRuntimeStatus(presentation, errorMessage: errorMessage)
            }
            return
        }

        runtimePresentation = presentation
        runtimeErrorMessage = errorMessage
        runtimeStatusLabel.stringValue = presentation.stateTitle.replacingOccurrences(
            of: "状態: ",
            with: ""
        )
        runtimeStatusLabel.setAccessibilityLabel("ランタイム状態、\(presentation.stateTitle)")

        let trimmedError = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasError = trimmedError?.isEmpty == false
        runtimeErrorLabel.stringValue = hasError ? runtimeErrorSummary(trimmedError ?? "") : ""
        runtimeErrorLabel.isHidden = !hasError
        runtimeErrorLabel.toolTip = hasError ? trimmedError : nil
        runtimeErrorLabel.setAccessibilityLabel(hasError ? "直近のエラー" : nil)
        runtimeErrorLabel.setAccessibilityValue(hasError ? trimmedError : nil)

        let appearance = runtimeAppearance(for: presentation, hasError: hasError)
        runtimeStatusImageView.image = NSImage(
            systemSymbolName: appearance.symbolName,
            accessibilityDescription: appearance.accessibilityDescription
        )
        runtimeStatusImageView.contentTintColor = appearance.color
    }

    func makeSmokeSnapshot() -> SettingsWindowSmokeSnapshot {
        let initialPane = selectedPane
        let initialAssociationWindow = associationWindowField.stringValue
        let initialSystemGestureSensitivity = systemGestureSensitivitySlider.doubleValue
        let initiallyApplyEnabled = applyButton.isEnabled
        let initialDisclosureState = advancedDisclosureButton.state
        let initiallyAdvancedConditionsHidden = advancedConditionsStack.isHidden
        let initialSettings = settings
        let initialSavedFormState = savedFormState
        let initialOnSave = onSave

        let preservedMatcher = DeviceMatcher(
            vendorID: 9_999,
            productContains: "保持対象"
        )
        let primaryMatcher = settings.targetDevices.first ?? DeviceMatcher(productContains: "Nape Pro")
        settings.targetDevices = [primaryMatcher, preservedMatcher]
        let multipleMatchersPreserved = try? makeUpdatedSettings().targetDevices.dropFirst()
            == [preservedMatcher]
        settings = initialSettings

        associationWindowField.stringValue = initialAssociationWindow + "0"
        updateApplyButtonState()
        let dirtyEditEnablesApply = applyButton.isEnabled
        onSave = { _ in throw SettingsWindowSmokeError.expectedSaveFailure }
        var saveFailureKeepsDirtyState = false
        if let attemptedSettings = try? makeUpdatedSettings() {
            let failedSaveError = commit(attemptedSettings)
            saveFailureKeepsDirtyState = failedSaveError != nil
                && applyButton.isEnabled
                && settings == initialSettings
                && savedFormState == initialSavedFormState
        }
        onSave = initialOnSave
        associationWindowField.stringValue = initialAssociationWindow
        updateApplyButtonState()
        let revertingEditDisablesApply = !applyButton.isEnabled

        let sensitivityStep = GestureConfiguration.systemGestureSensitivityStep
        if initialSystemGestureSensitivity
            <= GestureConfiguration.maximumSystemGestureSensitivity - sensitivityStep
        {
            systemGestureSensitivitySlider.doubleValue =
                initialSystemGestureSensitivity + sensitivityStep
        } else {
            systemGestureSensitivitySlider.doubleValue =
                initialSystemGestureSensitivity - sensitivityStep
        }
        systemGestureSensitivityChanged()
        let gestureSensitivityEditEnablesApply = applyButton.isEnabled
        systemGestureSensitivitySlider.doubleValue = initialSystemGestureSensitivity
        updateSystemGestureSensitivityLabel()
        updateApplyButtonState()

        advancedDisclosureButton.state = .on
        toggleAdvancedConditions()
        let disclosureExpands = !advancedConditionsStack.isHidden
        advancedDisclosureButton.state = .off
        toggleAdvancedConditions()
        let disclosureCollapses = advancedConditionsStack.isHidden

        showPane(.gestures, persistSelection: false)
        let gesturePaneSwitchesContent = !gesturesPaneView.isHidden && detailsPaneView.isHidden
        showPane(.details, persistSelection: false)
        let detailsPaneSwitchesContent = gesturesPaneView.isHidden && !detailsPaneView.isHidden

        advancedDisclosureButton.state = initialDisclosureState
        toggleAdvancedConditions()
        showPane(initialPane, persistSelection: false)

        let gestureDescendants = descendants(of: gesturesPaneView)
        let gestureSensitivitySliders = gestureDescendants.compactMap { $0 as? NSSlider }
        let gesturePaneHasForbiddenModeControl = gestureDescendants.contains { view in
            if let textField = view as? NSTextField {
                return textField.isEditable
            }
            return view is NSPopUpButton
                || view is NSSegmentedControl
                || view is NSSwitch
        }
        let detailDescendants = descendants(of: detailsPaneView)
        let detailTextFields: [NSTextField] = detailDescendants.compactMap { $0 as? NSTextField }
        let detailButtons: [NSButton] = detailDescendants.compactMap { $0 as? NSButton }

        return SettingsWindowSmokeSnapshot(
            selectedPane: selectedPane.rawValue,
            selectedToolbarItemIdentifier: window?.toolbar?.selectedItemIdentifier?.rawValue,
            windowIsResizable: window?.styleMask.contains(.resizable) ?? true,
            initiallyApplyEnabled: initiallyApplyEnabled,
            initiallyAdvancedConditionsHidden: initiallyAdvancedConditionsHidden,
            fixedMappingTexts: fixedMappingLabels.map(\.stringValue),
            passthroughText: passthroughLabel.stringValue,
            runtimeStatusText: runtimeStatusLabel.stringValue,
            runtimeStatusUsesSystemImage: runtimeStatusImageView.image != nil,
            dirtyEditEnablesApply: dirtyEditEnablesApply,
            revertingEditDisablesApply: revertingEditDisablesApply,
            disclosureExpands: disclosureExpands,
            disclosureCollapses: disclosureCollapses,
            paneSwitchesContent: gesturePaneSwitchesContent && detailsPaneSwitchesContent,
            gestureSensitivitySliderCount: gestureSensitivitySliders.count,
            gestureSensitivityPercentText: systemGestureSensitivityValueLabel.stringValue,
            gestureSensitivityEditEnablesApply: gestureSensitivityEditEnablesApply,
            gesturePaneHasForbiddenModeControl: gesturePaneHasForbiddenModeControl,
            detailsEditableTextFieldCount: detailTextFields.filter(\.isEditable).count,
            detailsCheckboxCount: detailButtons.filter { $0 === requireTargetCheck }.count,
            multipleMatchersPreserved: multipleMatchersPreserved ?? false,
            saveFailureKeepsDirtyState: saveFailureKeepsDirtyState
        )
    }

    private static func restoredPane() -> Pane {
        guard
            let rawValue = UserDefaults.standard.string(forKey: selectedPaneDefaultsKey),
            let pane = Pane(rawValue: rawValue)
        else {
            return .gestures
        }
        return pane
    }

    private func configureToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .regular
        toolbar.selectedItemIdentifier = selectedPane.toolbarIdentifier
        toolbar.centeredItemIdentifiers = Set(Pane.allCases.map(\.toolbarIdentifier))
        window.toolbar = toolbar
        window.toolbar?.isVisible = true
    }

    private func buildContent() {
        guard let window else {
            return
        }

        configureEditableControls()
        buildGesturesPane()
        buildDetailsPane()

        let rootView = NSView()
        paneContainerView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(paneContainerView)

        gesturesPaneView.translatesAutoresizingMaskIntoConstraints = false
        detailsPaneView.translatesAutoresizingMaskIntoConstraints = false
        paneContainerView.addSubview(gesturesPaneView)
        paneContainerView.addSubview(detailsPaneView)

        let footer = makeFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(footer)
        window.contentView = rootView

        NSLayoutConstraint.activate([
            paneContainerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            paneContainerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            paneContainerView.topAnchor.constraint(equalTo: rootView.topAnchor),
            paneContainerView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            gesturesPaneView.leadingAnchor.constraint(equalTo: paneContainerView.leadingAnchor),
            gesturesPaneView.trailingAnchor.constraint(equalTo: paneContainerView.trailingAnchor),
            gesturesPaneView.topAnchor.constraint(equalTo: paneContainerView.topAnchor),
            gesturesPaneView.bottomAnchor.constraint(equalTo: paneContainerView.bottomAnchor),

            detailsPaneView.leadingAnchor.constraint(equalTo: paneContainerView.leadingAnchor),
            detailsPaneView.trailingAnchor.constraint(equalTo: paneContainerView.trailingAnchor),
            detailsPaneView.topAnchor.constraint(equalTo: paneContainerView.topAnchor),
            detailsPaneView.bottomAnchor.constraint(equalTo: paneContainerView.bottomAnchor),

            footer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 78)
        ])
    }

    private func configureEditableControls() {
        let fieldLabels: [(NSTextField, String)] = [
            (associationWindowField, SettingsUIField.targetDeviceAssociationWindow.descriptor.label),
            (maximumDurationField, SettingsUIField.cancellationMaximumDuration.descriptor.label),
            (maximumInactivityField, SettingsUIField.cancellationMaximumInactivityInterval.descriptor.label),
            (targetVendorIDField, SettingsUIField.targetVendorID.descriptor.label),
            (targetProductIDField, SettingsUIField.targetProductID.descriptor.label),
            (targetManufacturerField, SettingsUIField.targetManufacturerContains.descriptor.label),
            (targetProductField, SettingsUIField.targetProductContains.descriptor.label),
            (targetTransportField, SettingsUIField.targetTransportContains.descriptor.label),
            (targetUsagePageField, SettingsUIField.targetUsagePage.descriptor.label),
            (targetUsageField, SettingsUIField.targetUsage.descriptor.label)
        ]

        for (field, accessibilityLabel) in fieldLabels {
            field.delegate = self
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.setAccessibilityLabel(accessibilityLabel)
        }

        requireTargetCheck.target = self
        requireTargetCheck.action = #selector(editableControlChanged)
        requireTargetCheck.setAccessibilityLabel(SettingsUIField.requireMatchingTargetDevice.descriptor.label)

        systemGestureSensitivitySlider.target = self
        systemGestureSensitivitySlider.action = #selector(systemGestureSensitivityChanged)
        systemGestureSensitivitySlider.isContinuous = true
        systemGestureSensitivitySlider.setAccessibilityLabel(
            SettingsUIField.systemGestureSensitivity.descriptor.label
        )

        systemGestureSensitivityValueLabel.alignment = .right
        systemGestureSensitivityValueLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .medium
        )
        systemGestureSensitivityValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        systemGestureSensitivityValueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        applyButton.target = self
        applyButton.action = #selector(save)
        applyButton.keyEquivalent = "\r"
        applyButton.isEnabled = false
        applyButton.setAccessibilityLabel("設定の変更を適用")
    }

    private func buildGesturesPane() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        gesturesPaneView.addSubview(content)

        let title = label("Nape Gesture", font: .systemFont(ofSize: 20, weight: .semibold))
        content.addArrangedSubview(title)

        let summary = secondaryLabel(
            "対象のマウス操作を、押しているボタンに対応したmacOSのトラックパッドジェスチャーへ変換します。",
            lines: 2
        )
        content.addArrangedSubview(summary)
        summary.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(18, after: summary)

        content.addArrangedSubview(sectionTitle("動作状態"))
        let runtimeRow = makeRuntimeRow()
        content.addArrangedSubview(runtimeRow)
        runtimeRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(16, after: runtimeRow)

        let runtimeSeparator = separator()
        content.addArrangedSubview(runtimeSeparator)
        runtimeSeparator.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(16, after: runtimeSeparator)

        content.addArrangedSubview(sectionTitle("固定ジェスチャー"))
        let mappings: [(SettingsUIField, String, String, String)] = [
            (
                .fixedButton3Gesture,
                "3.circle.fill",
                "マウスボタン3",
                "スクロールやスワイプとしてmacOSが解釈します。"
            ),
            (
                .fixedButton4Gesture,
                "4.circle.fill",
                "マウスボタン4",
                "SpacesやMission ControlとしてmacOSが解釈します。"
            ),
            (
                .fixedButton5Gesture,
                "5.circle.fill",
                "マウスボタン5",
                "システムピンチとしてmacOSが解釈します。"
            )
        ]

        for (index, mapping) in mappings.enumerated() {
            let row = makeMappingRow(
                field: mapping.0,
                symbolName: mapping.1,
                symbolDescription: mapping.2,
                detail: mapping.3
            )
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            if index < mappings.count - 1 {
                let mappingSeparator = separator()
                content.addArrangedSubview(mappingSeparator)
                mappingSeparator.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            } else {
                content.setCustomSpacing(12, after: row)
            }
        }

        let sensitivitySeparator = separator()
        content.addArrangedSubview(sensitivitySeparator)
        sensitivitySeparator.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(16, after: sensitivitySeparator)

        content.addArrangedSubview(sectionTitle("感度"))
        let sensitivityRow = makeSystemGestureSensitivityRow()
        content.addArrangedSubview(sensitivityRow)
        sensitivityRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(12, after: sensitivityRow)

        passthroughLabel.stringValue = "ボタン3、4、5を押していない間は、通常のマウスとして動作します。"
        passthroughLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        passthroughLabel.textColor = .secondaryLabelColor
        passthroughLabel.lineBreakMode = .byWordWrapping
        passthroughLabel.maximumNumberOfLines = 2
        content.addArrangedSubview(passthroughLabel)
        passthroughLabel.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: gesturesPaneView.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: gesturesPaneView.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: gesturesPaneView.topAnchor, constant: 18),
            content.bottomAnchor.constraint(lessThanOrEqualTo: gesturesPaneView.bottomAnchor, constant: -18)
        ])
    }

    private func makeRuntimeRow() -> NSStackView {
        runtimeStatusImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        runtimeStatusImageView.setContentHuggingPriority(.required, for: .horizontal)
        runtimeStatusImageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        runtimeStatusImageView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        runtimeStatusLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        runtimeStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        runtimeErrorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        runtimeErrorLabel.textColor = .systemRed
        runtimeErrorLabel.lineBreakMode = .byTruncatingTail
        runtimeErrorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusText = NSStackView(views: [runtimeStatusLabel, runtimeErrorLabel])
        statusText.orientation = .vertical
        statusText.alignment = .leading
        statusText.spacing = 2
        statusText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let permissionsButton = NSButton(
            title: "権限とデバイスを確認",
            target: self,
            action: #selector(checkPermissions)
        )
        permissionsButton.bezelStyle = .rounded
        permissionsButton.setAccessibilityLabel("権限と対象デバイスの状態を確認")
        permissionsButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [runtimeStatusImageView, statusText, NSView(), permissionsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        return row
    }

    private func makeMappingRow(
        field: SettingsUIField,
        symbolName: String,
        symbolDescription: String,
        detail: String
    ) -> NSStackView {
        let descriptor = field.descriptor
        let fixedValue = (descriptor.fixedValue ?? "")
            .replacingOccurrences(of: " / ", with: "／")
        let imageView = NSImageView()
        imageView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: symbolDescription
        )
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        imageView.contentTintColor = .controlAccentColor
        imageView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let mappingTitle = label(
            "\(descriptor.label)  \(fixedValue)",
            font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        )
        fixedMappingLabels.append(mappingTitle)
        let mappingDetail = secondaryLabel(detail, lines: 1)
        let text = NSStackView(views: [mappingTitle, mappingDetail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [imageView, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel("\(descriptor.label)、\(fixedValue)、\(detail)、読み取り専用")
        return row
    }

    private func makeSystemGestureSensitivityRow() -> NSStackView {
        let title = label(
            SettingsUIField.systemGestureSensitivity.descriptor.label,
            font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        )
        let detail = secondaryLabel("3本指スワイプと4本指ピンチに共通", lines: 1)
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let row = NSStackView(
            views: [text, systemGestureSensitivitySlider, systemGestureSensitivityValueLabel]
        )
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        systemGestureSensitivitySlider.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        return row
    }

    private func buildDetailsPane() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8

        content.addArrangedSubview(sectionTitle("動作保護"))
        let protectionDescription = secondaryLabel(
            "長時間または無入力になったジェスチャーを安全に終了します。0秒でキャンセルを無効にできます。",
            lines: 2
        )
        content.addArrangedSubview(protectionDescription)
        protectionDescription.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(12, after: protectionDescription)

        let protectionRows = [
            formRow(.targetDeviceAssociationWindow, control: associationWindowField, unit: "秒"),
            formRow(.cancellationMaximumDuration, control: maximumDurationField, unit: "秒"),
            formRow(.cancellationMaximumInactivityInterval, control: maximumInactivityField, unit: "秒")
        ]
        for row in protectionRows {
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        if let lastProtectionRow = protectionRows.last {
            content.setCustomSpacing(18, after: lastProtectionRow)
        }

        let groupSeparator = separator()
        content.addArrangedSubview(groupSeparator)
        groupSeparator.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(18, after: groupSeparator)

        content.addArrangedSubview(sectionTitle("対象デバイス"))
        let deviceDescription = secondaryLabel(
            "ジェスチャーへ変換するマウスを、製品名または追加条件で識別します。",
            lines: 2
        )
        content.addArrangedSubview(deviceDescription)
        deviceDescription.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(12, after: deviceDescription)

        let productRow = formRow(.targetProductContains, control: targetProductField)
        content.addArrangedSubview(productRow)
        productRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(10, after: productRow)

        content.addArrangedSubview(requireTargetCheck)
        content.setCustomSpacing(10, after: requireTargetCheck)

        advancedDisclosureButton.target = self
        advancedDisclosureButton.action = #selector(toggleAdvancedConditions)
        advancedDisclosureButton.setButtonType(.toggle)
        advancedDisclosureButton.bezelStyle = .inline
        advancedDisclosureButton.isBordered = false
        advancedDisclosureButton.image = disclosureImage(expanded: false)
        advancedDisclosureButton.imagePosition = .imageLeading
        advancedDisclosureButton.font = .systemFont(ofSize: NSFont.systemFontSize)
        advancedDisclosureButton.contentTintColor = .secondaryLabelColor
        advancedDisclosureButton.state = .off
        advancedDisclosureButton.setAccessibilityLabel("詳細な識別条件を表示")
        content.addArrangedSubview(advancedDisclosureButton)

        advancedConditionsStack.orientation = .vertical
        advancedConditionsStack.alignment = .leading
        advancedConditionsStack.spacing = 8
        advancedConditionsStack.edgeInsets = NSEdgeInsets(top: 8, left: 18, bottom: 0, right: 0)
        for row in [
            formRow(.targetVendorID, control: targetVendorIDField),
            formRow(.targetProductID, control: targetProductIDField),
            formRow(.targetManufacturerContains, control: targetManufacturerField),
            formRow(.targetTransportContains, control: targetTransportField),
            formRow(.targetUsagePage, control: targetUsagePageField),
            formRow(.targetUsage, control: targetUsageField)
        ] {
            advancedConditionsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: advancedConditionsStack.widthAnchor).isActive = true
        }
        advancedConditionsStack.isHidden = true
        content.addArrangedSubview(advancedConditionsStack)
        advancedConditionsStack.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        let scrollView = makeScrollView(containing: content)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        detailsPaneView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: detailsPaneView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: detailsPaneView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: detailsPaneView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: detailsPaneView.bottomAnchor)
        ])
    }

    private func makeScrollView(containing content: NSStackView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(content)
        scrollView.documentView = documentView

        let minimumHeight = documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        minimumHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            minimumHeight,
            content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18)
        ])
        return scrollView
    }

    private func makeFooter() -> NSView {
        let footer = NSView()
        let topSeparator = separator()
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(topSeparator)

        let restartLabel = secondaryLabel(
            "変更を適用すると設定を保存し、常駐処理を再起動します。",
            lines: 1
        )
        restartLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let pathLabel = secondaryLabel("設定ファイル: \(configPath)", lines: 1)
        pathLabel.isSelectable = true
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.toolTip = configPath
        pathLabel.setAccessibilityLabel("設定ファイル、\(configPath)")
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [restartLabel, pathLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(text)

        applyButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(applyButton)
        NSLayoutConstraint.activate([
            topSeparator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: footer.topAnchor),

            text.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            text.trailingAnchor.constraint(lessThanOrEqualTo: applyButton.leadingAnchor, constant: -18),
            text.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            applyButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24),
            applyButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            applyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112)
        ])
        return footer
    }

    private func formRow(
        _ field: SettingsUIField,
        control: NSTextField,
        unit: String? = nil
    ) -> NSStackView {
        let title = label(field.descriptor.label, font: .systemFont(ofSize: NSFont.systemFontSize))
        title.widthAnchor.constraint(equalToConstant: 220).isActive = true

        control.widthAnchor.constraint(equalToConstant: unit == nil ? 230 : 120).isActive = true
        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        if let unit {
            row.addArrangedSubview(secondaryLabel(unit, lines: 1))
        }
        row.addArrangedSubview(NSView())
        return row
    }

    private func populate(_ settings: NapeGestureSettings) {
        systemGestureSensitivitySlider.doubleValue = settings.gesture.systemGestureSensitivity
        updateSystemGestureSensitivityLabel()
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
        savedFormState = formState
        updateApplyButtonState()
    }

    private var formState: FormState {
        FormState(
            systemGestureSensitivity: systemGestureSensitivitySlider.doubleValue,
            associationWindow: associationWindowField.stringValue,
            maximumDuration: maximumDurationField.stringValue,
            maximumInactivity: maximumInactivityField.stringValue,
            vendorID: targetVendorIDField.stringValue,
            productID: targetProductIDField.stringValue,
            manufacturer: targetManufacturerField.stringValue,
            product: targetProductField.stringValue,
            transport: targetTransportField.stringValue,
            usagePage: targetUsagePageField.stringValue,
            usage: targetUsageField.stringValue,
            requiresMatchingTarget: requireTargetCheck.state == .on
        )
    }

    @objc private func save() {
        let updated: NapeGestureSettings
        do {
            updated = try makeUpdatedSettings()
        } catch let error as SettingsInputError {
            showError(error.message)
            return
        } catch {
            showError("設定を検証できません: \(error.localizedDescription)")
            return
        }

        if let error = commit(updated) {
            showError("設定を保存できません: \(error.localizedDescription)")
        }
    }

    private func makeUpdatedSettings() throws -> NapeGestureSettings {
        guard
            let associationWindow = Double(associationWindowField.stringValue),
            let maximumDuration = Double(maximumDurationField.stringValue),
            let maximumInactivity = Double(maximumInactivityField.stringValue)
        else {
            throw SettingsInputError(message: "数値項目の形式が不正です。")
        }

        let matcher = DeviceMatcher(
            vendorID: try optionalInt(targetVendorIDField, field: .targetVendorID),
            productID: try optionalInt(targetProductIDField, field: .targetProductID),
            manufacturerContains: optionalText(targetManufacturerField),
            productContains: optionalText(targetProductField),
            transportContains: optionalText(targetTransportField),
            primaryUsagePage: try optionalInt(targetUsagePageField, field: .targetUsagePage),
            primaryUsage: try optionalInt(targetUsageField, field: .targetUsage)
        )
        var targetDevices = matcher.hasAnyCondition ? [matcher] : []
        targetDevices.append(contentsOf: settings.targetDevices.dropFirst())

        let updated = NapeGestureSettings(
            gesture: GestureConfiguration(
                systemGestureSensitivity: systemGestureSensitivitySlider.doubleValue,
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
        if !issues.isEmpty {
            throw SettingsInputError(
                message: issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
            )
        }
        return updated
    }

    private func commit(_ updated: NapeGestureSettings) -> Error? {
        do {
            try onSave?(updated)
        } catch {
            return error
        }
        settings = updated
        savedFormState = formState
        updateApplyButtonState()
        return nil
    }

    @objc private func checkPermissions() {
        onCheckPermissions?()
    }

    @objc private func editableControlChanged() {
        updateApplyButtonState()
    }

    @objc private func systemGestureSensitivityChanged() {
        let step = GestureConfiguration.systemGestureSensitivityStep
        systemGestureSensitivitySlider.doubleValue =
            (systemGestureSensitivitySlider.doubleValue / step).rounded() * step
        updateSystemGestureSensitivityLabel()
        updateApplyButtonState()
    }

    private func updateSystemGestureSensitivityLabel() {
        let percent = Int((systemGestureSensitivitySlider.doubleValue * 100).rounded())
        let text = "\(percent)%"
        systemGestureSensitivityValueLabel.stringValue = text
        systemGestureSensitivityValueLabel.setAccessibilityLabel("現在の感度")
        systemGestureSensitivityValueLabel.setAccessibilityValue(text)
        systemGestureSensitivitySlider.setAccessibilityValue(text)
    }

    @objc private func toggleAdvancedConditions() {
        let isExpanded = advancedDisclosureButton.state == .on
        advancedConditionsStack.isHidden = !isExpanded
        advancedDisclosureButton.image = disclosureImage(expanded: isExpanded)
        advancedDisclosureButton.setAccessibilityLabel(
            isExpanded ? "詳細な識別条件を隠す" : "詳細な識別条件を表示"
        )
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = Pane(toolbarIdentifier: sender.itemIdentifier) else {
            return
        }
        showPane(pane, persistSelection: true)
    }

    private func showPane(_ pane: Pane, persistSelection: Bool) {
        selectedPane = pane
        gesturesPaneView.isHidden = pane != .gestures
        detailsPaneView.isHidden = pane != .details
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
        paneContainerView.layoutSubtreeIfNeeded()
        paneContainerView.needsDisplay = true
        paneContainerView.displayIfNeeded()

        if persistSelection {
            UserDefaults.standard.set(pane.rawValue, forKey: Self.selectedPaneDefaultsKey)
        }
    }

    private func updateApplyButtonState() {
        applyButton.isEnabled = savedFormState.map { $0 != formState } ?? false
    }

    private func runtimeAppearance(
        for presentation: RuntimeStatusPresentation,
        hasError: Bool
    ) -> (symbolName: String, color: NSColor, accessibilityDescription: String) {
        if hasError {
            return ("exclamationmark.circle.fill", .systemRed, "ランタイムエラー")
        }
        if presentation.stateTitle.contains("実行中") {
            return ("circle.fill", .systemGreen, "ランタイム実行中")
        }
        if presentation.stateTitle.contains("自動再試行中") {
            return ("arrow.clockwise.circle.fill", .systemOrange, "ランタイム再試行中")
        }
        if presentation.stateTitle.contains("スリープ待機中") {
            return ("moon.fill", .systemBlue, "ランタイムスリープ待機中")
        }
        return ("circle", .secondaryLabelColor, "ランタイム停止中")
    }

    private func runtimeErrorSummary(_ message: String) -> String {
        if message.contains("入力監視") || message.contains("IOHIDManager") {
            return "入力監視を確認してください"
        }
        if message.contains("アクセシビリティ") || message.contains("event tap") {
            return "アクセシビリティを確認してください"
        }
        return "常駐処理を開始できません"
    }

    private func disclosureImage(expanded: Bool) -> NSImage? {
        let image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        return image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
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

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .labelColor
        return label
    }

    private func secondaryLabel(_ text: String, lines: Int) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = lines
        label.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        return label
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold))
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "設定エラー"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = Pane(toolbarIdentifier: itemIdentifier) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.toolbarLabel
        item.paletteLabel = pane.toolbarLabel
        item.toolTip = "\(pane.toolbarLabel)設定を表示"
        item.image = NSImage(
            systemSymbolName: pane.symbolName,
            accessibilityDescription: "\(pane.toolbarLabel)設定"
        )
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateApplyButtonState()
    }
}

struct SettingsWindowSmokeSnapshot: Codable {
    var selectedPane: String
    var selectedToolbarItemIdentifier: String?
    var windowIsResizable: Bool
    var initiallyApplyEnabled: Bool
    var initiallyAdvancedConditionsHidden: Bool
    var fixedMappingTexts: [String]
    var passthroughText: String
    var runtimeStatusText: String
    var runtimeStatusUsesSystemImage: Bool
    var dirtyEditEnablesApply: Bool
    var revertingEditDisablesApply: Bool
    var disclosureExpands: Bool
    var disclosureCollapses: Bool
    var paneSwitchesContent: Bool
    var gestureSensitivitySliderCount: Int
    var gestureSensitivityPercentText: String
    var gestureSensitivityEditEnablesApply: Bool
    var gesturePaneHasForbiddenModeControl: Bool
    var detailsEditableTextFieldCount: Int
    var detailsCheckboxCount: Int
    var multipleMatchersPreserved: Bool
    var saveFailureKeepsDirtyState: Bool
}

private struct SettingsInputError: Error {
    var message: String
}

private enum SettingsWindowSmokeError: Error {
    case expectedSaveFailure
}
