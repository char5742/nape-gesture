import Foundation

public enum SettingsUISection: String, Codable, Equatable, Sendable, CaseIterable {
    case gesture
    case acceleration
    case momentum
    case cancellation
    case targetDevice
    case bindings
}

public enum SettingsUIControlKind: String, Codable, Equatable, Sendable {
    case numberTextField
    case textField
    case checkbox
    case actionPopup
}

public struct SettingsUIFieldDescriptor: Codable, Equatable, Sendable {
    public var field: SettingsUIField
    public var label: String
    public var section: SettingsUISection
    public var controlKind: SettingsUIControlKind
    public var settingsPath: String
    public var selectableActions: [GestureAction]

    public init(
        field: SettingsUIField,
        label: String,
        section: SettingsUISection,
        controlKind: SettingsUIControlKind,
        settingsPath: String,
        selectableActions: [GestureAction] = []
    ) {
        self.field = field
        self.label = label
        self.section = section
        self.controlKind = controlKind
        self.settingsPath = settingsPath
        self.selectableActions = selectableActions
    }
}

public enum SettingsUIField: String, Codable, Equatable, Sendable, CaseIterable {
    case activationButton
    case targetDeviceAssociationWindow
    case deadZonePoints
    case directionLockRatio
    case dragSensitivity
    case wheelSensitivity
    case accelerationEnabled
    case accelerationThresholdVelocity
    case accelerationExponent
    case accelerationMaximumMultiplier
    case momentumEnabled
    case momentumMinimumStartVelocity
    case momentumStopVelocity
    case momentumDecayPerSecond
    case momentumFrameInterval
    case cancellationMaximumDuration
    case cancellationMaximumInactivityInterval
    case cancellationOffAxisCancelRatio
    case targetVendorID
    case targetProductID
    case targetManufacturerContains
    case targetProductContains
    case targetTransportContains
    case targetUsagePage
    case targetUsage
    case requireMatchingTargetDevice
    case bindingDragUp
    case bindingDragDown
    case bindingDragLeft
    case bindingDragRight
    case bindingWheel

    public static var descriptors: [SettingsUIFieldDescriptor] {
        allCases.map(\.descriptor)
    }

    public var descriptor: SettingsUIFieldDescriptor {
        switch self {
        case .activationButton:
            return number("ジェスチャーボタン番号", .gesture, "gesture.activationButton")
        case .targetDeviceAssociationWindow:
            return number("対象入力の紐づけ秒", .targetDevice, "targetDeviceAssociation.associationWindow")
        case .deadZonePoints:
            return number("デッドゾーン pt", .gesture, "gesture.deadZonePoints")
        case .directionLockRatio:
            return number("方向ロック比", .gesture, "gesture.directionLockRatio")
        case .dragSensitivity:
            return number("ドラッグ感度", .gesture, "gesture.dragSensitivity")
        case .wheelSensitivity:
            return number("ホイール感度", .gesture, "gesture.wheelSensitivity")
        case .accelerationEnabled:
            return checkbox("速度に応じて加速度を適用する", .acceleration, "gesture.acceleration.isEnabled")
        case .accelerationThresholdVelocity:
            return number("加速度しきい速度", .acceleration, "gesture.acceleration.thresholdVelocity")
        case .accelerationExponent:
            return number("加速度指数", .acceleration, "gesture.acceleration.exponent")
        case .accelerationMaximumMultiplier:
            return number("加速度最大倍率", .acceleration, "gesture.acceleration.maximumMultiplier")
        case .momentumEnabled:
            return checkbox("慣性スクロールを適用する", .momentum, "gesture.momentum.isEnabled")
        case .momentumMinimumStartVelocity:
            return number("慣性開始しきい速度", .momentum, "gesture.momentum.minimumStartVelocity")
        case .momentumStopVelocity:
            return number("慣性停止速度", .momentum, "gesture.momentum.stopVelocity")
        case .momentumDecayPerSecond:
            return number("慣性減衰率/秒", .momentum, "gesture.momentum.decayPerSecond")
        case .momentumFrameInterval:
            return number("慣性フレーム間隔秒", .momentum, "gesture.momentum.frameInterval")
        case .cancellationMaximumDuration:
            return number("最大ジェスチャー秒", .cancellation, "gesture.cancellation.maximumDuration")
        case .cancellationMaximumInactivityInterval:
            return number("無入力キャンセル秒", .cancellation, "gesture.cancellation.maximumInactivityInterval")
        case .cancellationOffAxisCancelRatio:
            return number("軸ずれキャンセル比", .cancellation, "gesture.cancellation.offAxisCancelRatio")
        case .targetVendorID:
            return number("対象 vendor ID", .targetDevice, "targetDevices[0].vendorID")
        case .targetProductID:
            return number("対象 product ID", .targetDevice, "targetDevices[0].productID")
        case .targetManufacturerContains:
            return text("対象メーカーに含む文字", .targetDevice, "targetDevices[0].manufacturerContains")
        case .targetProductContains:
            return text("対象製品名に含む文字", .targetDevice, "targetDevices[0].productContains")
        case .targetTransportContains:
            return text("対象 transport に含む文字", .targetDevice, "targetDevices[0].transportContains")
        case .targetUsagePage:
            return number("対象 usagePage", .targetDevice, "targetDevices[0].primaryUsagePage")
        case .targetUsage:
            return number("対象 usage", .targetDevice, "targetDevices[0].primaryUsage")
        case .requireMatchingTargetDevice:
            return checkbox("対象デバイス一致を必須にする", .targetDevice, "requireMatchingTargetDevice")
        case .bindingDragUp:
            return action("上ドラッグ", "gesture.bindings.dragUp")
        case .bindingDragDown:
            return action("下ドラッグ", "gesture.bindings.dragDown")
        case .bindingDragLeft:
            return action("左ドラッグ", "gesture.bindings.dragLeft")
        case .bindingDragRight:
            return action("右ドラッグ", "gesture.bindings.dragRight")
        case .bindingWheel:
            return action("ホイール", "gesture.bindings.wheel")
        }
    }

    private func number(
        _ label: String,
        _ section: SettingsUISection,
        _ settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        SettingsUIFieldDescriptor(
            field: self,
            label: label,
            section: section,
            controlKind: .numberTextField,
            settingsPath: settingsPath
        )
    }

    private func text(
        _ label: String,
        _ section: SettingsUISection,
        _ settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        SettingsUIFieldDescriptor(
            field: self,
            label: label,
            section: section,
            controlKind: .textField,
            settingsPath: settingsPath
        )
    }

    private func checkbox(
        _ label: String,
        _ section: SettingsUISection,
        _ settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        SettingsUIFieldDescriptor(
            field: self,
            label: label,
            section: section,
            controlKind: .checkbox,
            settingsPath: settingsPath
        )
    }

    private func action(
        _ label: String,
        _ settingsPath: String
    ) -> SettingsUIFieldDescriptor {
        SettingsUIFieldDescriptor(
            field: self,
            label: label,
            section: .bindings,
            controlKind: .actionPopup,
            settingsPath: settingsPath,
            selectableActions: GestureAction.settingsSelectableActions
        )
    }
}
