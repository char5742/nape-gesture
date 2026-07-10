import Dispatch
import Foundation

public enum MonotonicEventClock {
    public static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    public static let maximumPostingSkewSeconds: TimeInterval = 60

    public static var nowTimestampNanoseconds: UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    public static var nowSeconds: TimeInterval {
        seconds(fromTimestampNanoseconds: nowTimestampNanoseconds)
    }

    public static func seconds(fromTimestampNanoseconds timestamp: UInt64) -> TimeInterval {
        TimeInterval(timestamp) / TimeInterval(nanosecondsPerSecond)
    }

    public static func timestampNanoseconds(fromSecondsSinceStartup seconds: TimeInterval) -> UInt64? {
        let maximumConvertibleSeconds = TimeInterval(UInt64.max / nanosecondsPerSecond)
        guard seconds.isFinite, seconds >= 0, seconds <= maximumConvertibleSeconds else {
            return nil
        }
        return UInt64((seconds * TimeInterval(nanosecondsPerSecond)).rounded())
    }

    public static func isNear(
        timestampNanoseconds: UInt64,
        referenceTimestampNanoseconds: UInt64,
        maximumDifferenceSeconds: TimeInterval = maximumPostingSkewSeconds
    ) -> Bool {
        guard let maximumDifferenceNanoseconds = Self.timestampNanoseconds(
            fromSecondsSinceStartup: maximumDifferenceSeconds
        ) else {
            return false
        }
        let difference = timestampNanoseconds >= referenceTimestampNanoseconds
            ? timestampNanoseconds - referenceTimestampNanoseconds
            : referenceTimestampNanoseconds - timestampNanoseconds
        return difference <= maximumDifferenceNanoseconds
    }

    public static func validatedTimestampNanosecondsForPosting(
        fromSecondsSinceStartup seconds: TimeInterval,
        referenceTimestampNanoseconds: UInt64 = nowTimestampNanoseconds,
        maximumDifferenceSeconds: TimeInterval = maximumPostingSkewSeconds
    ) -> UInt64? {
        guard let timestamp = timestampNanoseconds(fromSecondsSinceStartup: seconds),
              isNear(
                timestampNanoseconds: timestamp,
                referenceTimestampNanoseconds: referenceTimestampNanoseconds,
                maximumDifferenceSeconds: maximumDifferenceSeconds
              )
        else {
            return nil
        }
        return timestamp
    }

    public static func validatedTimestampSequenceNanosecondsForPosting(
        fromSecondsSinceStartup values: [TimeInterval],
        referenceTimestampNanoseconds: UInt64 = nowTimestampNanoseconds,
        maximumDifferenceSeconds: TimeInterval = maximumPostingSkewSeconds
    ) -> [UInt64]? {
        var timestamps: [UInt64] = []
        timestamps.reserveCapacity(values.count)
        for value in values {
            guard let timestamp = validatedTimestampNanosecondsForPosting(
                fromSecondsSinceStartup: value,
                referenceTimestampNanoseconds: referenceTimestampNanoseconds,
                maximumDifferenceSeconds: maximumDifferenceSeconds
            ) else {
                return nil
            }
            timestamps.append(timestamp)
        }
        return timestamps
    }

    public static func elapsed(
        from start: TimeInterval,
        to end: TimeInterval,
        maximum maximumElapsed: TimeInterval
    ) -> TimeInterval? {
        guard start.isFinite,
              end.isFinite,
              maximumElapsed.isFinite,
              maximumElapsed >= 0
        else {
            return nil
        }
        let elapsed = end - start
        guard elapsed.isFinite, elapsed >= 0, elapsed <= maximumElapsed else {
            return nil
        }
        return elapsed
    }
}
