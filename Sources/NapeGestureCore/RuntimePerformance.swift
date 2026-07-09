import Foundation

public enum RuntimePerformanceSource: String, Codable, Equatable, Sendable {
    case eventTap
    case momentumTimer
}

public struct RuntimePerformanceRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var operationID: String
    public var source: RuntimePerformanceSource
    public var action: GestureAction
    public var commandKind: GestureCommandKind
    public var commandPhase: GesturePhase
    public var commandTimestamp: TimeInterval
    public var inputEventTimestampNanoseconds: UInt64?
    public var tapCallbackStartedAtNanoseconds: UInt64
    public var recognizerFinishedAtNanoseconds: UInt64
    public var postStartedAtNanoseconds: UInt64
    public var postFinishedAtNanoseconds: UInt64
    public var generatedEventCount: Int
    public var failedEventCreationCount: Int
    public var suppressedOriginal: Bool

    public init(
        schemaVersion: Int = RuntimePerformanceRecord.currentSchemaVersion,
        operationID: String,
        source: RuntimePerformanceSource,
        action: GestureAction,
        commandKind: GestureCommandKind,
        commandPhase: GesturePhase,
        commandTimestamp: TimeInterval,
        inputEventTimestampNanoseconds: UInt64?,
        tapCallbackStartedAtNanoseconds: UInt64,
        recognizerFinishedAtNanoseconds: UInt64,
        postStartedAtNanoseconds: UInt64,
        postFinishedAtNanoseconds: UInt64,
        generatedEventCount: Int,
        failedEventCreationCount: Int,
        suppressedOriginal: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.source = source
        self.action = action
        self.commandKind = commandKind
        self.commandPhase = commandPhase
        self.commandTimestamp = commandTimestamp
        self.inputEventTimestampNanoseconds = inputEventTimestampNanoseconds
        self.tapCallbackStartedAtNanoseconds = tapCallbackStartedAtNanoseconds
        self.recognizerFinishedAtNanoseconds = recognizerFinishedAtNanoseconds
        self.postStartedAtNanoseconds = postStartedAtNanoseconds
        self.postFinishedAtNanoseconds = postFinishedAtNanoseconds
        self.generatedEventCount = generatedEventCount
        self.failedEventCreationCount = failedEventCreationCount
        self.suppressedOriginal = suppressedOriginal
    }
}

public struct RuntimePerformanceReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var measurementKind: String
    public var measurementScope: String
    public var includesEventTapAndPosting: Bool
    public var recordCount: Int
    public var postedRecordCount: Int
    public var eventTapPostedRecordCount: Int
    public var missingPostRecordCount: Int
    public var generatedEventCount: Int
    public var failedEventCreationCount: Int
    public var sourceCounts: [String: Int]
    public var actionCounts: [String: Int]
    public var tapToFirstPostNanoseconds: RuntimePerformanceDistribution
    public var tapToPostFinishedNanoseconds: RuntimePerformanceDistribution
    public var recognizerNanoseconds: RuntimePerformanceDistribution
    public var postingNanoseconds: RuntimePerformanceDistribution
}

public struct RuntimePerformanceDistribution: Codable, Equatable, Sendable {
    public var measurement: String
    public var sampleUnit: String
    public var sampleCount: Int
    public var minimumNanoseconds: Double
    public var p50Nanoseconds: Double
    public var p95Nanoseconds: Double
    public var p99Nanoseconds: Double
    public var maximumNanoseconds: Double

    public init(measurement: String, sampleUnit: String, samples: [Double]) {
        let sorted = samples.sorted()
        self.measurement = measurement
        self.sampleUnit = sampleUnit
        sampleCount = sorted.count
        minimumNanoseconds = sorted.first ?? 0
        p50Nanoseconds = Self.percentile(0.50, sorted: sorted)
        p95Nanoseconds = Self.percentile(0.95, sorted: sorted)
        p99Nanoseconds = Self.percentile(0.99, sorted: sorted)
        maximumNanoseconds = sorted.last ?? 0
    }

    private static func percentile(_ percentile: Double, sorted: [Double]) -> Double {
        guard !sorted.isEmpty else {
            return 0
        }
        let rank = Int(ceil(percentile * Double(sorted.count))) - 1
        return sorted[max(0, min(rank, sorted.count - 1))]
    }
}

public enum RuntimePerformanceAnalyzer {
    public static let measurementKind = "runtimeTapToPost"

    public static func analyze(records: [RuntimePerformanceRecord]) -> RuntimePerformanceReport {
        let postedRecords = records.filter { $0.generatedEventCount > 0 }
        let eventTapPostedRecords = postedRecords.filter { $0.source == .eventTap }

        return RuntimePerformanceReport(
            schemaVersion: 1,
            measurementKind: measurementKind,
            measurementScope: "event tap callback、認識処理、CGEvent 投稿直前/直後まで。AppKit 受信と画面反映は含みません。",
            includesEventTapAndPosting: true,
            recordCount: records.count,
            postedRecordCount: postedRecords.count,
            eventTapPostedRecordCount: eventTapPostedRecords.count,
            missingPostRecordCount: records.count - postedRecords.count,
            generatedEventCount: records.reduce(0) { $0 + $1.generatedEventCount },
            failedEventCreationCount: records.reduce(0) { $0 + $1.failedEventCreationCount },
            sourceCounts: counts(records.map { $0.source.rawValue }),
            actionCounts: counts(records.map { $0.action.rawValue }),
            tapToFirstPostNanoseconds: RuntimePerformanceDistribution(
                measurement: "tapCallbackToPostStartNanoseconds",
                sampleUnit: "command",
                samples: eventTapPostedRecords.map {
                    positiveDifference($0.postStartedAtNanoseconds, $0.tapCallbackStartedAtNanoseconds)
                }
            ),
            tapToPostFinishedNanoseconds: RuntimePerformanceDistribution(
                measurement: "tapCallbackToPostFinishedNanoseconds",
                sampleUnit: "command",
                samples: eventTapPostedRecords.map {
                    positiveDifference($0.postFinishedAtNanoseconds, $0.tapCallbackStartedAtNanoseconds)
                }
            ),
            recognizerNanoseconds: RuntimePerformanceDistribution(
                measurement: "recognizerNanoseconds",
                sampleUnit: "command",
                samples: records.map {
                    positiveDifference($0.recognizerFinishedAtNanoseconds, $0.tapCallbackStartedAtNanoseconds)
                }
            ),
            postingNanoseconds: RuntimePerformanceDistribution(
                measurement: "postingNanoseconds",
                sampleUnit: "command",
                samples: postedRecords.map {
                    positiveDifference($0.postFinishedAtNanoseconds, $0.postStartedAtNanoseconds)
                }
            )
        )
    }

    public static func evaluate(
        _ report: RuntimePerformanceReport,
        thresholds: RuntimePerformanceThresholds = .default
    ) -> RuntimePerformanceEvaluation {
        var failures: [RuntimePerformanceFailure] = []

        if report.measurementKind != measurementKind {
            failures.append(
                RuntimePerformanceFailure(
                    item: "measurementKind",
                    expected: measurementKind,
                    actual: report.measurementKind
                )
            )
        }

        if !report.includesEventTapAndPosting {
            failures.append(
                RuntimePerformanceFailure(
                    item: "includesEventTapAndPosting",
                    expected: "true",
                    actual: "false"
                )
            )
        }

        if thresholds.requiresPostedEvents && report.generatedEventCount == 0 {
            failures.append(
                RuntimePerformanceFailure(
                    item: "generatedEventCount",
                    expected: "1 以上",
                    actual: String(report.generatedEventCount)
                )
            )
        }

        if thresholds.requiresPostedEvents && report.eventTapPostedRecordCount == 0 {
            failures.append(
                RuntimePerformanceFailure(
                    item: "eventTapPostedRecordCount",
                    expected: "1 以上",
                    actual: String(report.eventTapPostedRecordCount)
                )
            )
        }

        appendMaximumFailure(
            item: "missingPostRecordCount",
            actual: Double(report.missingPostRecordCount),
            maximum: 0,
            failures: &failures
        )
        appendMaximumFailure(
            item: "failedEventCreationCount",
            actual: Double(report.failedEventCreationCount),
            maximum: 0,
            failures: &failures
        )
        appendMaximumFailure(
            item: "tapToFirstPostNanoseconds.p95Nanoseconds",
            actual: report.tapToFirstPostNanoseconds.p95Nanoseconds,
            maximum: thresholds.maximumTapToFirstPostP95Nanoseconds,
            failures: &failures
        )
        appendMaximumFailure(
            item: "tapToFirstPostNanoseconds.p99Nanoseconds",
            actual: report.tapToFirstPostNanoseconds.p99Nanoseconds,
            maximum: thresholds.maximumTapToFirstPostP99Nanoseconds,
            failures: &failures
        )
        appendMaximumFailure(
            item: "tapToPostFinishedNanoseconds.p95Nanoseconds",
            actual: report.tapToPostFinishedNanoseconds.p95Nanoseconds,
            maximum: thresholds.maximumTapToPostFinishedP95Nanoseconds,
            failures: &failures
        )
        appendMaximumFailure(
            item: "tapToPostFinishedNanoseconds.p99Nanoseconds",
            actual: report.tapToPostFinishedNanoseconds.p99Nanoseconds,
            maximum: thresholds.maximumTapToPostFinishedP99Nanoseconds,
            failures: &failures
        )

        return RuntimePerformanceEvaluation(failures: failures)
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { result, value in
            result[value, default: 0] += 1
        }
    }

    private static func positiveDifference(_ lhs: UInt64, _ rhs: UInt64) -> Double {
        guard lhs >= rhs else {
            return 0
        }
        return Double(lhs - rhs)
    }

    private static func appendMaximumFailure(
        item: String,
        actual: Double,
        maximum: Double,
        failures: inout [RuntimePerformanceFailure]
    ) {
        guard actual > maximum else {
            return
        }
        failures.append(
            RuntimePerformanceFailure(
                item: item,
                expected: "\(format(maximum)) 以下",
                actual: format(actual)
            )
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

public struct RuntimePerformanceThresholds: Equatable, Sendable {
    public var requiresPostedEvents: Bool
    public var maximumTapToFirstPostP95Nanoseconds: Double
    public var maximumTapToFirstPostP99Nanoseconds: Double
    public var maximumTapToPostFinishedP95Nanoseconds: Double
    public var maximumTapToPostFinishedP99Nanoseconds: Double

    public init(
        requiresPostedEvents: Bool,
        maximumTapToFirstPostP95Nanoseconds: Double,
        maximumTapToFirstPostP99Nanoseconds: Double,
        maximumTapToPostFinishedP95Nanoseconds: Double,
        maximumTapToPostFinishedP99Nanoseconds: Double
    ) {
        self.requiresPostedEvents = requiresPostedEvents
        self.maximumTapToFirstPostP95Nanoseconds = maximumTapToFirstPostP95Nanoseconds
        self.maximumTapToFirstPostP99Nanoseconds = maximumTapToFirstPostP99Nanoseconds
        self.maximumTapToPostFinishedP95Nanoseconds = maximumTapToPostFinishedP95Nanoseconds
        self.maximumTapToPostFinishedP99Nanoseconds = maximumTapToPostFinishedP99Nanoseconds
    }

    public static let `default` = RuntimePerformanceThresholds(
        requiresPostedEvents: true,
        maximumTapToFirstPostP95Nanoseconds: 8_000_000,
        maximumTapToFirstPostP99Nanoseconds: 16_000_000,
        maximumTapToPostFinishedP95Nanoseconds: 8_000_000,
        maximumTapToPostFinishedP99Nanoseconds: 16_000_000
    )
}

public struct RuntimePerformanceEvaluation: Equatable, Sendable {
    public var failures: [RuntimePerformanceFailure]

    public var passed: Bool {
        failures.isEmpty
    }

    public var failureDescription: String {
        failures
            .map { "- \($0.item): expected \($0.expected), actual \($0.actual)" }
            .joined(separator: "\n")
    }
}

public struct RuntimePerformanceFailure: Equatable, Sendable {
    public var item: String
    public var expected: String
    public var actual: String
}
