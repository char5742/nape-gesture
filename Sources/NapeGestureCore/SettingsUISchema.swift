import Foundation

public enum SettingsUISection: String, Codable, Equatable, Sendable, CaseIterable {
    case fixedMapping
    case gestureTuning
    case cancellation
    case targetDevice
}

public enum SettingsUIControlKind: String, Codable, Equatable, Sendable {
    case readOnlyText
    case slider
    case numberTextField
    case textField
    case checkbox
}

public enum SettingsUIValueSource: String, Codable, Equatable, Sendable {
    case fixedProductMapping
    case editableGestureSetting
    case editableSafetySetting
}

public struct SettingsUIFieldDescriptor: Codable, Equatable, Sendable {
    public var field: SettingsUIField
    public var label: String
    public var section: SettingsUISection
    public var controlKind: SettingsUIControlKind
    public var valueSource: SettingsUIValueSource
    public var isEditable: Bool
    public var settingsPath: String?
    public var fixedValue: String?

    public init(
        field: SettingsUIField,
        label: String,
        section: SettingsUISection,
        controlKind: SettingsUIControlKind,
        valueSource: SettingsUIValueSource,
        isEditable: Bool,
        settingsPath: String? = nil,
        fixedValue: String? = nil
    ) {
        self.field = field
        self.label = label
        self.section = section
        self.controlKind = controlKind
        self.valueSource = valueSource
        self.isEditable = isEditable
        self.settingsPath = settingsPath
        self.fixedValue = fixedValue
    }
}

public enum SettingsUIField: String, Codable, Equatable, Sendable, CaseIterable {
    case fixedButton3Gesture
    case fixedButton4Gesture
    case fixedButton5Gesture
    case systemGestureSensitivity
    case targetDeviceAssociationWindow
    case cancellationMaximumDuration
    case cancellationMaximumInactivityInterval
    case targetVendorID
    case targetProductID
    case targetManufacturerContains
    case targetProductContains
    case targetTransportContains
    case targetUsagePage
    case targetUsage
    case requireMatchingTargetDevice

    public static var descriptors: [SettingsUIFieldDescriptor] {
        allCases.map(\.descriptor)
    }

    public var descriptor: SettingsUIFieldDescriptor {
        switch self {
        case .fixedButton3Gesture:
            return fixed("ボタン3", "2本指スクロール / スワイプ")
        case .fixedButton4Gesture:
            return fixed("ボタン4", "3本指システムスワイプ")
        case .fixedButton5Gesture:
            return fixed("ボタン5", "4本指システムピンチ")
        case .systemGestureSensitivity:
            return SettingsUIFieldDescriptor(
                field: self,
                label: "システムジェスチャー感度",
                section: .gestureTuning,
                controlKind: .slider,
                valueSource: .editableGestureSetting,
                isEditable: true,
                settingsPath: "gesture.systemGestureSensitivity"
            )
        case .targetDeviceAssociationWindow:
            return number("入力の関連付け時間", .targetDevice, "targetDeviceAssociation.associationWindow")
        case .cancellationMaximumDuration:
            return number("最大継続時間", .cancellation, "gesture.cancellation.maximumDuration")
        case .cancellationMaximumInactivityInterval:
            return number("無操作でキャンセル", .cancellation, "gesture.cancellation.maximumInactivityInterval")
        case .targetVendorID:
            return number("Vendor ID", .targetDevice, "targetDevices[0].vendorID")
        case .targetProductID:
            return number("Product ID", .targetDevice, "targetDevices[0].productID")
        case .targetManufacturerContains:
            return text("メーカー名を含む", .targetDevice, "targetDevices[0].manufacturerContains")
        case .targetProductContains:
            return text("製品名を含む", .targetDevice, "targetDevices[0].productContains")
        case .targetTransportContains:
            return text("接続方式を含む", .targetDevice, "targetDevices[0].transportContains")
        case .targetUsagePage:
            return number("Usage Page", .targetDevice, "targetDevices[0].primaryUsagePage")
        case .targetUsage:
            return number("Usage", .targetDevice, "targetDevices[0].primaryUsage")
        case .requireMatchingTargetDevice:
            return checkbox("一致するデバイスだけで動作", .targetDevice, "requireMatchingTargetDevice")
        }
    }

    private func fixed(
        _ label: String,
        _ value: String
    ) -> SettingsUIFieldDescriptor {
        SettingsUIFieldDescriptor(
            field: self,
            label: label,
            section: .fixedMapping,
            controlKind: .readOnlyText,
            valueSource: .fixedProductMapping,
            isEditable: false,
            fixedValue: value
        )
    }

    private func number(
        _ label: String,
        _ section: SettingsUISection,
        _ settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        editable(
            label,
            section,
            controlKind: .numberTextField,
            settingsPath: settingsPath
        )
    }

    private func text(
        _ label: String,
        _ section: SettingsUISection,
        _ settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        editable(label, section, controlKind: .textField, settingsPath: settingsPath)
    }

    private func checkbox(
        _ label: String,
        _ section: SettingsUISection,
        _ settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        editable(label, section, controlKind: .checkbox, settingsPath: settingsPath)
    }

    private func editable(
        _ label: String,
        _ section: SettingsUISection,
        controlKind: SettingsUIControlKind,
        settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        SettingsUIFieldDescriptor(
            field: self,
            label: label,
            section: section,
            controlKind: controlKind,
            valueSource: .editableSafetySetting,
            isEditable: true,
            settingsPath: settingsPath
        )
    }
}
