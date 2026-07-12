import Dispatch
import Foundation

/// Decodeは過去ログの値を保持し、live利用時のboot整合性はsession machineが再検証します。
public struct MonotonicEventTimestamp: Codable, Comparable, Equatable, Hashable, Sendable {
    public let nanosecondsSinceStartup: UInt64

    public init(nanosecondsSinceStartup: UInt64) {
        self.nanosecondsSinceStartup = nanosecondsSinceStartup
    }

    fileprivate init(uncheckedNanosecondsSinceStartup nanosecondsSinceStartup: UInt64) {
        self.nanosecondsSinceStartup = nanosecondsSinceStartup
    }

    public var secondsSinceStartup: TimeInterval {
        MonotonicEventClock.seconds(fromTimestampNanoseconds: nanosecondsSinceStartup)
    }

    public static func < (lhs: MonotonicEventTimestamp, rhs: MonotonicEventTimestamp) -> Bool {
        lhs.nanosecondsSinceStartup < rhs.nanosecondsSinceStartup
    }
}

public enum MonotonicEventClock {
    public static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    public static var now: MonotonicEventTimestamp {
        MonotonicEventTimestamp(
            uncheckedNanosecondsSinceStartup: DispatchTime.now().uptimeNanoseconds
        )
    }

    public static var nowTimestampNanoseconds: UInt64 {
        now.nanosecondsSinceStartup
    }

    public static var nowSeconds: TimeInterval {
        now.secondsSinceStartup
    }

    public static func seconds(fromTimestampNanoseconds timestamp: UInt64) -> TimeInterval {
        TimeInterval(timestamp) / TimeInterval(nanosecondsPerSecond)
    }

    public static func timestamp(nanosecondsSinceStartup: UInt64) -> MonotonicEventTimestamp? {
        validatedTimestamp(nanosecondsSinceStartup: nanosecondsSinceStartup, notAfter: now)
    }

    private static func validatedTimestamp(
        nanosecondsSinceStartup: UInt64,
        notAfter reference: MonotonicEventTimestamp
    ) -> MonotonicEventTimestamp? {
        guard nanosecondsSinceStartup <= reference.nanosecondsSinceStartup else {
            return nil
        }
        return MonotonicEventTimestamp(
            uncheckedNanosecondsSinceStartup: nanosecondsSinceStartup
        )
    }

    public static func timestamp(fromSecondsSinceStartup seconds: TimeInterval) -> MonotonicEventTimestamp? {
        let maximumSafelyConvertibleSeconds = TimeInterval(UInt64.max / nanosecondsPerSecond)
        guard seconds.isFinite,
              seconds >= 0,
              seconds <= maximumSafelyConvertibleSeconds
        else {
            return nil
        }

        let nanoseconds = UInt64((seconds * TimeInterval(nanosecondsPerSecond)).rounded())
        return validatedTimestamp(nanosecondsSinceStartup: nanoseconds, notAfter: now)
    }

    public static func elapsedSeconds(from start: TimeInterval, to end: TimeInterval) -> TimeInterval? {
        guard start.isFinite, end.isFinite else {
            return nil
        }

        let elapsed = end - start
        return elapsed.isFinite && elapsed >= 0 ? elapsed : nil
    }
}
