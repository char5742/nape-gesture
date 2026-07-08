import Foundation

public struct LogDerivedTuningReport: Codable, Equatable, Sendable {
    public var sourceEventCount: Int
    public var moveVelocitySamples: NumericDistribution
    public var scrollMagnitudeSamples: NumericDistribution
    public var scrollIntervalSamples: NumericDistribution
    public var momentumVelocitySamples: NumericDistribution
    public var suggestedDeadZonePoints: Double
    public var suggestedAcceleration: DerivedAccelerationTuning?
    public var suggestedMomentum: DerivedMomentumTuning?
    public var warnings: [String]

    public init(
        sourceEventCount: Int,
        moveVelocitySamples: NumericDistribution,
        scrollMagnitudeSamples: NumericDistribution,
        scrollIntervalSamples: NumericDistribution,
        momentumVelocitySamples: NumericDistribution,
        suggestedDeadZonePoints: Double,
        suggestedAcceleration: DerivedAccelerationTuning?,
        suggestedMomentum: DerivedMomentumTuning?,
        warnings: [String]
    ) {
        self.sourceEventCount = sourceEventCount
        self.moveVelocitySamples = moveVelocitySamples
        self.scrollMagnitudeSamples = scrollMagnitudeSamples
        self.scrollIntervalSamples = scrollIntervalSamples
        self.momentumVelocitySamples = momentumVelocitySamples
        self.suggestedDeadZonePoints = suggestedDeadZonePoints
        self.suggestedAcceleration = suggestedAcceleration
        self.suggestedMomentum = suggestedMomentum
        self.warnings = warnings
    }

    public var hasCompleteTuningEvidence: Bool {
        completeTuningEvidenceFailures.isEmpty
    }

    public var completeTuningEvidenceFailures: [String] {
        var failures: [String] = []
        if sourceEventCount == 0 {
            failures.append("入力イベントがありません。")
        }
        if suggestedAcceleration == nil {
            failures.append("acceleration 候補が未導出です。")
        }
        if suggestedMomentum == nil {
            failures.append("momentum 候補が未導出です。")
        }
        failures.append(contentsOf: warnings.map { "警告: \($0)" })
        return failures
    }
}

public struct NumericDistribution: Codable, Equatable, Sendable {
    public var count: Int
    public var minimum: Double
    public var p50: Double
    public var p75: Double
    public var p95: Double
    public var p99: Double
    public var maximum: Double
    public var average: Double

    public init(values: [Double]) {
        let sorted = values.sorted()
        count = sorted.count
        minimum = sorted.first ?? 0
        p50 = Self.percentile(sorted, fraction: 0.50)
        p75 = Self.percentile(sorted, fraction: 0.75)
        p95 = Self.percentile(sorted, fraction: 0.95)
        p99 = Self.percentile(sorted, fraction: 0.99)
        maximum = sorted.last ?? 0
        average = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
    }

    private static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard !sortedValues.isEmpty else {
            return 0
        }
        let clamped = min(max(fraction, 0), 1)
        let index = Int((Double(sortedValues.count - 1) * clamped).rounded())
        return sortedValues[index]
    }
}

public struct DerivedAccelerationTuning: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var thresholdVelocity: Double
    public var exponent: Double
    public var maximumMultiplier: Double

    public init(
        isEnabled: Bool,
        thresholdVelocity: Double,
        exponent: Double,
        maximumMultiplier: Double
    ) {
        self.isEnabled = isEnabled
        self.thresholdVelocity = thresholdVelocity
        self.exponent = exponent
        self.maximumMultiplier = maximumMultiplier
    }
}

public struct DerivedMomentumTuning: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var minimumStartVelocity: Double
    public var stopVelocity: Double
    public var decayPerSecond: Double
    public var frameInterval: TimeInterval

    public init(
        isEnabled: Bool,
        minimumStartVelocity: Double,
        stopVelocity: Double,
        decayPerSecond: Double,
        frameInterval: TimeInterval
    ) {
        self.isEnabled = isEnabled
        self.minimumStartVelocity = minimumStartVelocity
        self.stopVelocity = stopVelocity
        self.decayPerSecond = decayPerSecond
        self.frameInterval = frameInterval
    }
}

public enum LogDerivedTuningAnalyzer {
    public static func derive(from records: [InputLogRecord]) -> LogDerivedTuningReport {
        let analysis = InputLogAnalyzer.analyze(records)
        let moveRecords = records.filter(\.isMoveEvent).sorted { $0.timestamp < $1.timestamp }
        let scrollRecords = records.filter(\.isScrollEvent).sorted { $0.timestamp < $1.timestamp }
        let moveVelocities = velocities(
            records: moveRecords,
            magnitude: { hypot(Double($0.deltaX), Double($0.deltaY)) }
        )
        let moveIntervals = intervals(records: moveRecords)
        let scrollMagnitudes = scrollRecords.map(scrollMagnitude)
        let scrollIntervals = intervals(records: scrollRecords)
        let momentumVelocities = velocities(
            records: scrollRecords.filter { $0.momentumPhase != 0 },
            magnitude: scrollMagnitude
        )
        let activeScrollVelocities = velocities(
            records: scrollRecords.filter { $0.momentumPhase == 0 && $0.scrollPhase != 0 },
            magnitude: scrollMagnitude
        )
        let moveVelocityDistribution = NumericDistribution(values: moveVelocities)
        let scrollMagnitudeDistribution = NumericDistribution(values: scrollMagnitudes)
        let scrollIntervalDistribution = NumericDistribution(values: scrollIntervals)
        let momentumVelocityDistribution = NumericDistribution(values: momentumVelocities)

        var warnings: [String] = []
        let suggestedAcceleration = accelerationTuning(
            distribution: moveVelocityDistribution,
            warnings: &warnings
        )
        let suggestedMomentum = momentumTuning(
            activeScrollVelocities: activeScrollVelocities,
            momentumVelocities: momentumVelocities,
            scrollIntervals: scrollIntervals,
            momentumRecords: scrollRecords.filter { $0.momentumPhase != 0 },
            warnings: &warnings
        )

        if (moveIntervals + scrollIntervals).contains(where: { $0 < 0.0001 }) {
            warnings.append("timestamp の差分が 0.1ms 未満です。CGEvent.timestamp 由来ではない合成ログの場合、速度推定は参考扱いにしてください。")
        }

        return LogDerivedTuningReport(
            sourceEventCount: records.count,
            moveVelocitySamples: moveVelocityDistribution,
            scrollMagnitudeSamples: scrollMagnitudeDistribution,
            scrollIntervalSamples: scrollIntervalDistribution,
            momentumVelocitySamples: momentumVelocityDistribution,
            suggestedDeadZonePoints: analysis.suggestedDeadZonePoints,
            suggestedAcceleration: suggestedAcceleration,
            suggestedMomentum: suggestedMomentum,
            warnings: warnings
        )
    }

    public static func japaneseReport(for report: LogDerivedTuningReport) -> String {
        let acceleration = report.suggestedAcceleration.map {
            "enabled=\($0.isEnabled), thresholdVelocity=\(format($0.thresholdVelocity)), exponent=\(format($0.exponent)), maximumMultiplier=\(format($0.maximumMultiplier))"
        } ?? "未導出"
        let momentum = report.suggestedMomentum.map {
            "enabled=\($0.isEnabled), minimumStartVelocity=\(format($0.minimumStartVelocity)), stopVelocity=\(format($0.stopVelocity)), decayPerSecond=\(format($0.decayPerSecond)), frameInterval=\(format($0.frameInterval))"
        } ?? "未導出"
        let warnings = report.warnings.isEmpty
            ? "-"
            : report.warnings.map { "- \($0)" }.joined(separator: "\n")

        return """
        ログ由来パラメータ再導出
        総イベント数: \(report.sourceEventCount)
        推奨 deadZonePoints: \(format(report.suggestedDeadZonePoints)) pt
        移動速度サンプル: \(formatDistribution(report.moveVelocitySamples)) pt/s
        スクロール量サンプル: \(formatDistribution(report.scrollMagnitudeSamples)) pt/event
        スクロール間隔サンプル: \(formatDistribution(report.scrollIntervalSamples)) s
        慣性速度サンプル: \(formatDistribution(report.momentumVelocitySamples)) pt/s
        推奨 acceleration: \(acceleration)
        推奨 momentum: \(momentum)
        警告:
        \(warnings)
        """
    }

    private static func accelerationTuning(
        distribution: NumericDistribution,
        warnings: inout [String]
    ) -> DerivedAccelerationTuning? {
        guard distribution.count >= 2 else {
            warnings.append("移動イベントの正の時刻差分が不足しているため acceleration.thresholdVelocity は未導出です。")
            return nil
        }

        return DerivedAccelerationTuning(
            isEnabled: true,
            thresholdVelocity: rounded(distribution.p75),
            exponent: GestureAccelerationConfiguration.default.exponent,
            maximumMultiplier: GestureAccelerationConfiguration.default.maximumMultiplier
        )
    }

    private static func momentumTuning(
        activeScrollVelocities: [Double],
        momentumVelocities: [Double],
        scrollIntervals: [TimeInterval],
        momentumRecords: [InputLogRecord],
        warnings: inout [String]
    ) -> DerivedMomentumTuning? {
        guard momentumVelocities.count >= 2 else {
            warnings.append("momentumPhase 付き scrollWheel の正の時刻差分が不足しているため momentum は未導出です。")
            return nil
        }

        let activeDistribution = NumericDistribution(values: activeScrollVelocities)
        let momentumDistribution = NumericDistribution(values: momentumVelocities)
        let intervalDistribution = NumericDistribution(values: scrollIntervals)
        let decay = estimatedDecayPerSecond(from: momentumRecords)

        return DerivedMomentumTuning(
            isEnabled: true,
            minimumStartVelocity: rounded(max(activeDistribution.p75, momentumDistribution.p95)),
            stopVelocity: rounded(max(1, momentumDistribution.p50 * 0.25)),
            decayPerSecond: decay ?? MomentumConfiguration.default.decayPerSecond,
            frameInterval: intervalDistribution.count > 0
                ? max(0.001, intervalDistribution.p50)
                : MomentumConfiguration.default.frameInterval
        )
    }

    private static func velocities(
        records: [InputLogRecord],
        magnitude: (InputLogRecord) -> Double
    ) -> [Double] {
        guard records.count >= 2 else {
            return []
        }

        var result: [Double] = []
        for index in records.indices.dropFirst() {
            guard let interval = intervalSeconds(from: records[index - 1], to: records[index]), interval > 0 else {
                continue
            }
            result.append(magnitude(records[index]) / interval)
        }
        return result
    }

    private static func intervals(records: [InputLogRecord]) -> [TimeInterval] {
        guard records.count >= 2 else {
            return []
        }

        return records.indices.dropFirst().compactMap { index in
            intervalSeconds(from: records[index - 1], to: records[index])
        }
    }

    private static func estimatedDecayPerSecond(from records: [InputLogRecord]) -> Double? {
        guard records.count >= 3 else {
            return nil
        }

        var perSecondRatios: [Double] = []
        for index in records.indices.dropFirst() {
            let previous = records[index - 1]
            let current = records[index]
            let previousMagnitude = scrollMagnitude(previous)
            let currentMagnitude = scrollMagnitude(current)
            guard previousMagnitude > 0,
                  currentMagnitude > 0,
                  currentMagnitude < previousMagnitude,
                  let interval = intervalSeconds(from: previous, to: current),
                  interval > 0
            else {
                continue
            }

            perSecondRatios.append(pow(currentMagnitude / previousMagnitude, 1 / interval))
        }

        guard !perSecondRatios.isEmpty else {
            return nil
        }

        let average = perSecondRatios.reduce(0, +) / Double(perSecondRatios.count)
        return min(max(average, 0.01), 0.99)
    }

    private static func intervalSeconds(from previous: InputLogRecord, to current: InputLogRecord) -> TimeInterval? {
        guard current.timestamp > previous.timestamp else {
            return nil
        }
        return Double(current.timestamp - previous.timestamp) / 1_000_000_000
    }

    private static func scrollMagnitude(_ record: InputLogRecord) -> Double {
        let pointMagnitude = hypot(record.pointDeltaX, record.pointDeltaY)
        if pointMagnitude > 0 {
            return pointMagnitude
        }
        return hypot(Double(record.scrollDeltaX), Double(record.scrollDeltaY))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func formatDistribution(_ distribution: NumericDistribution) -> String {
        "n=\(distribution.count), p50=\(format(distribution.p50)), p75=\(format(distribution.p75)), p95=\(format(distribution.p95)), max=\(format(distribution.maximum))"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
