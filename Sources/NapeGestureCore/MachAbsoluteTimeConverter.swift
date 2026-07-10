import Foundation

public enum MachAbsoluteTimeConverter {
    public static func seconds(
        ticks: UInt64,
        numerator: UInt32,
        denominator: UInt32
    ) -> TimeInterval {
        precondition(denominator > 0, "Mach timebase denominator must be positive")
        return Double(ticks) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}
