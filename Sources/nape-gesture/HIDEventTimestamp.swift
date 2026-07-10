import Darwin
import Foundation
import IOKit.hid
import NapeGestureCore

enum HIDEventTimestamp {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func seconds(for value: IOHIDValue) -> TimeInterval {
        MachAbsoluteTimeConverter.seconds(
            ticks: IOHIDValueGetTimeStamp(value),
            numerator: timebase.numer,
            denominator: timebase.denom
        )
    }
}
