import Foundation

public enum HIDTargetActivityMapper {
    public static let genericDesktopUsagePage = 0x01
    public static let buttonUsagePage = 0x09
    public static let xUsage = 0x30
    public static let yUsage = 0x31
    public static let wheelUsage = 0x38

    public static func activity(
        usagePage: Int,
        usage: Int,
        integerValue: Int,
        time: TimeInterval
    ) -> TargetDeviceActivity? {
        if usagePage == buttonUsagePage, let button = MouseButton(hidButtonUsage: usage) {
            if integerValue != 0 {
                return .buttonDown(button: button, time: time)
            }
            return .buttonUp(button: button, time: time)
        }

        guard usagePage == genericDesktopUsagePage, integerValue != 0 else {
            return nil
        }

        switch usage {
        case xUsage:
            return .pointer(deltaX: Double(integerValue), deltaY: 0, time: time)
        case yUsage:
            return .pointer(deltaX: 0, deltaY: Double(integerValue), time: time)
        case wheelUsage:
            return .wheel(deltaX: 0, deltaY: Double(integerValue), time: time)
        default:
            return nil
        }
    }
}
