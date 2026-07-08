import Foundation

public struct HIDInputLogRecord: Codable, Equatable, Sendable {
    public var time: TimeInterval
    public var device: DeviceIdentity
    public var usagePage: Int
    public var usage: Int
    public var integerValue: Int
    public var scaledValue: Double
    public var logicalMin: Int
    public var logicalMax: Int
    public var physicalMin: Int
    public var physicalMax: Int

    public init(
        time: TimeInterval,
        device: DeviceIdentity,
        usagePage: Int,
        usage: Int,
        integerValue: Int,
        scaledValue: Double,
        logicalMin: Int,
        logicalMax: Int,
        physicalMin: Int,
        physicalMax: Int
    ) {
        self.time = time
        self.device = device
        self.usagePage = usagePage
        self.usage = usage
        self.integerValue = integerValue
        self.scaledValue = scaledValue
        self.logicalMin = logicalMin
        self.logicalMax = logicalMax
        self.physicalMin = physicalMin
        self.physicalMax = physicalMax
    }
}

public struct HIDInputLogAnalysis: Codable, Equatable, Sendable {
    public var totalEvents: Int
    public var deviceCount: Int
    public var usageSummaries: [HIDUsageSummary]

    public init(totalEvents: Int, deviceCount: Int, usageSummaries: [HIDUsageSummary]) {
        self.totalEvents = totalEvents
        self.deviceCount = deviceCount
        self.usageSummaries = usageSummaries
    }
}

public struct HIDUsageSummary: Codable, Equatable, Sendable {
    public var device: DeviceIdentity
    public var usagePage: Int
    public var usage: Int
    public var eventCount: Int
    public var nonZeroEventCount: Int
    public var integerMin: Int
    public var integerMax: Int
    public var scaledMin: Double
    public var scaledMax: Double
    public var firstTime: TimeInterval
    public var lastTime: TimeInterval

    public init(
        device: DeviceIdentity,
        usagePage: Int,
        usage: Int,
        eventCount: Int,
        nonZeroEventCount: Int,
        integerMin: Int,
        integerMax: Int,
        scaledMin: Double,
        scaledMax: Double,
        firstTime: TimeInterval,
        lastTime: TimeInterval
    ) {
        self.device = device
        self.usagePage = usagePage
        self.usage = usage
        self.eventCount = eventCount
        self.nonZeroEventCount = nonZeroEventCount
        self.integerMin = integerMin
        self.integerMax = integerMax
        self.scaledMin = scaledMin
        self.scaledMax = scaledMax
        self.firstTime = firstTime
        self.lastTime = lastTime
    }
}

public enum HIDInputLogAnalyzer {
    public static func analyze(_ records: [HIDInputLogRecord]) -> HIDInputLogAnalysis {
        var builders: [String: HIDUsageSummaryBuilder] = [:]
        var deviceIDs = Set<String>()

        for record in records {
            deviceIDs.insert(record.device.stableID)
            let key = [
                record.device.stableID,
                "usagePage=\(record.usagePage)",
                "usage=\(record.usage)"
            ].joined(separator: ";")

            if builders[key] == nil {
                builders[key] = HIDUsageSummaryBuilder(record: record)
            } else {
                builders[key]?.record(record)
            }
        }

        let summaries = builders.values
            .map { $0.summary }
            .sorted { lhs, rhs in
                if lhs.eventCount != rhs.eventCount {
                    return lhs.eventCount > rhs.eventCount
                }
                if lhs.device.stableID != rhs.device.stableID {
                    return lhs.device.stableID < rhs.device.stableID
                }
                if lhs.usagePage != rhs.usagePage {
                    return lhs.usagePage < rhs.usagePage
                }
                return lhs.usage < rhs.usage
            }

        return HIDInputLogAnalysis(
            totalEvents: records.count,
            deviceCount: deviceIDs.count,
            usageSummaries: summaries
        )
    }
}

private struct HIDUsageSummaryBuilder {
    private let device: DeviceIdentity
    private let usagePage: Int
    private let usage: Int
    private var eventCount: Int
    private var nonZeroEventCount: Int
    private var integerMin: Int
    private var integerMax: Int
    private var scaledMin: Double
    private var scaledMax: Double
    private var firstTime: TimeInterval
    private var lastTime: TimeInterval

    init(record: HIDInputLogRecord) {
        device = record.device
        usagePage = record.usagePage
        usage = record.usage
        eventCount = 0
        nonZeroEventCount = 0
        integerMin = record.integerValue
        integerMax = record.integerValue
        scaledMin = record.scaledValue
        scaledMax = record.scaledValue
        firstTime = record.time
        lastTime = record.time
        self.record(record)
    }

    mutating func record(_ record: HIDInputLogRecord) {
        eventCount += 1
        if record.integerValue != 0 {
            nonZeroEventCount += 1
        }
        integerMin = min(integerMin, record.integerValue)
        integerMax = max(integerMax, record.integerValue)
        scaledMin = min(scaledMin, record.scaledValue)
        scaledMax = max(scaledMax, record.scaledValue)
        firstTime = min(firstTime, record.time)
        lastTime = max(lastTime, record.time)
    }

    var summary: HIDUsageSummary {
        HIDUsageSummary(
            device: device,
            usagePage: usagePage,
            usage: usage,
            eventCount: eventCount,
            nonZeroEventCount: nonZeroEventCount,
            integerMin: integerMin,
            integerMax: integerMax,
            scaledMin: scaledMin,
            scaledMax: scaledMax,
            firstTime: firstTime,
            lastTime: lastTime
        )
    }
}
