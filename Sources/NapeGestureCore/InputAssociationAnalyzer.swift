import Foundation

public struct InputAssociationEventMatch: Codable, Equatable, Sendable {
    public var event: InputLogRecord
    public var hid: HIDInputLogRecord?
    public var timeDifferenceSeconds: TimeInterval?
    public var isWithinWindow: Bool
    public var expectedHIDUsages: [String]
    public var nearestIncompatibleHID: HIDInputLogRecord?
    public var nearestIncompatibleTimeDifferenceSeconds: TimeInterval?
    public var nearestTargetMismatchHID: HIDInputLogRecord?
    public var nearestTargetMismatchTimeDifferenceSeconds: TimeInterval?

    public init(
        event: InputLogRecord,
        hid: HIDInputLogRecord?,
        timeDifferenceSeconds: TimeInterval?,
        isWithinWindow: Bool,
        expectedHIDUsages: [String] = [],
        nearestIncompatibleHID: HIDInputLogRecord? = nil,
        nearestIncompatibleTimeDifferenceSeconds: TimeInterval? = nil,
        nearestTargetMismatchHID: HIDInputLogRecord? = nil,
        nearestTargetMismatchTimeDifferenceSeconds: TimeInterval? = nil
    ) {
        self.event = event
        self.hid = hid
        self.timeDifferenceSeconds = timeDifferenceSeconds
        self.isWithinWindow = isWithinWindow
        self.expectedHIDUsages = expectedHIDUsages
        self.nearestIncompatibleHID = nearestIncompatibleHID
        self.nearestIncompatibleTimeDifferenceSeconds = nearestIncompatibleTimeDifferenceSeconds
        self.nearestTargetMismatchHID = nearestTargetMismatchHID
        self.nearestTargetMismatchTimeDifferenceSeconds = nearestTargetMismatchTimeDifferenceSeconds
    }
}

public struct InputAssociationAnalysis: Codable, Equatable, Sendable {
    public var targetStableID: String?
    public var totalHIDEvents: Int
    public var totalEventTapEvents: Int
    public var analyzedEventTapEvents: Int
    public var excludedGeneratedEventTapEvents: Int
    public var hidCandidateEventCount: Int
    public var missingHIDCandidateEventCount: Int
    public var incompatibleHIDCandidateEventCount: Int
    public var targetHIDDeviceMismatchEventCount: Int
    public var matchedHIDDeviceIDs: [String]
    public var maximumTimeDifferenceSeconds: TimeInterval
    public var p95TimeDifferenceSeconds: TimeInterval
    public var p99TimeDifferenceSeconds: TimeInterval
    public var withinWindowCount: Int
    public var outsideWindowCount: Int
    public var suggestedAssociationWindowSeconds: TimeInterval
    public var matches: [InputAssociationEventMatch]

    public init(
        targetStableID: String? = nil,
        totalHIDEvents: Int,
        totalEventTapEvents: Int,
        analyzedEventTapEvents: Int,
        excludedGeneratedEventTapEvents: Int,
        hidCandidateEventCount: Int,
        missingHIDCandidateEventCount: Int,
        incompatibleHIDCandidateEventCount: Int = 0,
        targetHIDDeviceMismatchEventCount: Int = 0,
        matchedHIDDeviceIDs: [String] = [],
        maximumTimeDifferenceSeconds: TimeInterval,
        p95TimeDifferenceSeconds: TimeInterval,
        p99TimeDifferenceSeconds: TimeInterval,
        withinWindowCount: Int,
        outsideWindowCount: Int,
        suggestedAssociationWindowSeconds: TimeInterval,
        matches: [InputAssociationEventMatch]
    ) {
        self.targetStableID = targetStableID
        self.totalHIDEvents = totalHIDEvents
        self.totalEventTapEvents = totalEventTapEvents
        self.analyzedEventTapEvents = analyzedEventTapEvents
        self.excludedGeneratedEventTapEvents = excludedGeneratedEventTapEvents
        self.hidCandidateEventCount = hidCandidateEventCount
        self.missingHIDCandidateEventCount = missingHIDCandidateEventCount
        self.incompatibleHIDCandidateEventCount = incompatibleHIDCandidateEventCount
        self.targetHIDDeviceMismatchEventCount = targetHIDDeviceMismatchEventCount
        self.matchedHIDDeviceIDs = matchedHIDDeviceIDs
        self.maximumTimeDifferenceSeconds = maximumTimeDifferenceSeconds
        self.p95TimeDifferenceSeconds = p95TimeDifferenceSeconds
        self.p99TimeDifferenceSeconds = p99TimeDifferenceSeconds
        self.withinWindowCount = withinWindowCount
        self.outsideWindowCount = outsideWindowCount
        self.suggestedAssociationWindowSeconds = suggestedAssociationWindowSeconds
        self.matches = matches
    }

    public var hasValidAssociationWindowEvidence: Bool {
        guard let targetStableID else {
            return false
        }
        return analyzedEventTapEvents > 0
            && missingHIDCandidateEventCount == 0
            && incompatibleHIDCandidateEventCount == 0
            && targetHIDDeviceMismatchEventCount == 0
            && outsideWindowCount == 0
            && matchedHIDDeviceIDs == [targetStableID]
    }
}

public enum InputAssociationAnalyzer {
    public static func analyze(
        hidRecords: [HIDInputLogRecord],
        eventTapRecords: [InputLogRecord],
        associationWindowSeconds: TimeInterval,
        targetStableID: String? = nil
    ) -> InputAssociationAnalysis {
        let sortedHIDRecords = hidRecords.sorted { $0.time < $1.time }
        let targetEvents = eventTapRecords.filter(\.isAssociationTargetEvent)
        let generatedTargetEvents = eventTapRecords.filter { $0.generatedByNapeGesture && $0.isRawInputEvent }
        let matches = targetEvents.map { event -> InputAssociationEventMatch in
            let eventTime = event.associationTimestampSeconds
            let expectedHIDUsages = expectedHIDUsageDescriptions(for: event)
            let usageCompatibleRecords = sortedHIDRecords.filter { isUsageCompatible($0, with: event) }
            let targetCompatibleRecords = usageCompatibleRecords.filter { record in
                targetStableID.map { record.device.stableID == $0 } ?? true
            }
            let nearestTargetMismatchHID = targetStableID.flatMap { targetStableID in
                usageCompatibleRecords.last { record in
                    record.device.stableID != targetStableID
                        && isWithinAssociationWindow(
                            recordTime: record.time,
                            eventTime: eventTime,
                            associationWindowSeconds: associationWindowSeconds
                        )
                }
            }

            guard let hid = latestHIDRecord(atOrBefore: eventTime, in: targetCompatibleRecords) else {
                let nearestIncompatibleHID = usageCompatibleRecords.isEmpty
                    ? sortedHIDRecords.last { record in
                        isWithinAssociationWindow(
                            recordTime: record.time,
                            eventTime: eventTime,
                            associationWindowSeconds: associationWindowSeconds
                        )
                    }
                    : nil
                return InputAssociationEventMatch(
                    event: event,
                    hid: nil,
                    timeDifferenceSeconds: nil,
                    isWithinWindow: false,
                    expectedHIDUsages: expectedHIDUsages,
                    nearestIncompatibleHID: nearestIncompatibleHID,
                    nearestIncompatibleTimeDifferenceSeconds: nearestIncompatibleHID.map { eventTime - $0.time },
                    nearestTargetMismatchHID: nearestTargetMismatchHID,
                    nearestTargetMismatchTimeDifferenceSeconds: nearestTargetMismatchHID.map { eventTime - $0.time }
                )
            }

            let timeDifference = eventTime - hid.time
            return InputAssociationEventMatch(
                event: event,
                hid: hid,
                timeDifferenceSeconds: timeDifference,
                isWithinWindow: timeDifference <= associationWindowSeconds,
                expectedHIDUsages: expectedHIDUsages,
                nearestTargetMismatchHID: nearestTargetMismatchHID,
                nearestTargetMismatchTimeDifferenceSeconds: nearestTargetMismatchHID.map { eventTime - $0.time }
            )
        }

        let timeDifferences = matches.compactMap(\.timeDifferenceSeconds).sorted()
        let hidCandidateEventCount = timeDifferences.count
        let incompatibleHIDCandidateEventCount = matches.filter { match in
            match.hid == nil && match.nearestIncompatibleHID != nil
        }.count
        let targetHIDDeviceMismatchEventCount = matches.filter { match in
            match.nearestTargetMismatchHID != nil
        }.count
        let matchedHIDDeviceIDs = Array(Set(matches.compactMap { $0.hid?.device.stableID })).sorted()
        let withinWindowCount = matches.filter(\.isWithinWindow).count
        let outsideWindowCount = matches.filter { match in
            match.timeDifferenceSeconds != nil && !match.isWithinWindow
        }.count
        let p99TimeDifferenceSeconds = percentile(timeDifferences, fraction: 0.99)

        return InputAssociationAnalysis(
            targetStableID: targetStableID,
            totalHIDEvents: hidRecords.count,
            totalEventTapEvents: eventTapRecords.count,
            analyzedEventTapEvents: targetEvents.count,
            excludedGeneratedEventTapEvents: generatedTargetEvents.count,
            hidCandidateEventCount: hidCandidateEventCount,
            missingHIDCandidateEventCount: matches.count - hidCandidateEventCount,
            incompatibleHIDCandidateEventCount: incompatibleHIDCandidateEventCount,
            targetHIDDeviceMismatchEventCount: targetHIDDeviceMismatchEventCount,
            matchedHIDDeviceIDs: matchedHIDDeviceIDs,
            maximumTimeDifferenceSeconds: timeDifferences.last ?? 0,
            p95TimeDifferenceSeconds: percentile(timeDifferences, fraction: 0.95),
            p99TimeDifferenceSeconds: p99TimeDifferenceSeconds,
            withinWindowCount: withinWindowCount,
            outsideWindowCount: outsideWindowCount,
            suggestedAssociationWindowSeconds: suggestedAssociationWindow(forP99: p99TimeDifferenceSeconds),
            matches: matches
        )
    }

    public static func timestampSeconds(fromEventTimestamp timestamp: UInt64) -> TimeInterval {
        if timestamp >= 1_000_000_000 {
            return TimeInterval(timestamp) / 1_000_000_000
        }
        return TimeInterval(timestamp)
    }

    private static func latestHIDRecord(
        atOrBefore time: TimeInterval,
        in records: [HIDInputLogRecord]
    ) -> HIDInputLogRecord? {
        var lowerBound = 0
        var upperBound = records.count

        while lowerBound < upperBound {
            let index = (lowerBound + upperBound) / 2
            if records[index].time <= time {
                lowerBound = index + 1
            } else {
                upperBound = index
            }
        }

        return lowerBound > 0 ? records[lowerBound - 1] : nil
    }

    private static func isWithinAssociationWindow(
        recordTime: TimeInterval,
        eventTime: TimeInterval,
        associationWindowSeconds: TimeInterval
    ) -> Bool {
        let elapsed = eventTime - recordTime
        return elapsed >= 0 && elapsed <= associationWindowSeconds
    }

    private static func isUsageCompatible(_ hid: HIDInputLogRecord, with event: InputLogRecord) -> Bool {
        if event.isButtonEvent {
            return hid.usagePage == 9 && expectedButtonUsages(for: event).contains(hid.usage)
        }
        if event.isScrollEvent {
            return hid.usagePage == 1 && hid.usage == 56
        }
        if event.isMoveEvent {
            return hid.usagePage == 1 && (hid.usage == 48 || hid.usage == 49)
        }
        return false
    }

    private static func expectedHIDUsageDescriptions(for event: InputLogRecord) -> [String] {
        if event.isButtonEvent {
            return expectedButtonUsages(for: event)
                .sorted()
                .map { "Button:\($0)" }
        }
        if event.isScrollEvent {
            return ["GenericDesktop:Wheel"]
        }
        if event.isMoveEvent {
            return ["GenericDesktop:X", "GenericDesktop:Y"]
        }
        return []
    }

    private static func expectedButtonUsages(for event: InputLogRecord) -> Set<Int> {
        let buttonNumber = max(Int(event.buttonNumber), 0)
        return [buttonNumber + 1]
    }

    private static func percentile(_ sortedValues: [TimeInterval], fraction: Double) -> TimeInterval {
        guard !sortedValues.isEmpty else {
            return 0
        }
        let clamped = min(max(fraction, 0), 1)
        let index = Int((Double(sortedValues.count - 1) * clamped).rounded())
        return sortedValues[index]
    }

    private static func suggestedAssociationWindow(forP99 p99: TimeInterval) -> TimeInterval {
        guard p99 > 0 else {
            return 0
        }
        return max(p99 + 0.01, p99 * 1.2)
    }
}

public extension InputLogRecord {
    var associationTimestampSeconds: TimeInterval {
        InputAssociationAnalyzer.timestampSeconds(fromEventTimestamp: timestamp)
    }

    var isAssociationTargetEvent: Bool {
        !generatedByNapeGesture && isRawInputEvent
    }

    var isRawInputEvent: Bool {
        isMoveEvent || isButtonEvent || isScrollEvent
    }
}
