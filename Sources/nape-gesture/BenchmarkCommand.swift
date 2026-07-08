import Darwin
import Foundation
import NapeGestureCore

struct BenchmarkCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let events = try intValue("--events", defaultValue: 200_000)
        guard events > 0 else {
            throw ToolError.invalidValue("--events", String(events))
        }
        let report = BenchmarkRunner.run(events: events)
        let shouldAssertBaseline = options.contains("--assert-baseline")

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(format(report))
        }

        if shouldAssertBaseline {
            let evaluation = BenchmarkBaseline.evaluate(report)
            if evaluation.passed {
                fputs("純粋ロジック benchmark 基準: 合格\n", stderr)
            } else {
                throw ToolError.benchmarkBaselineFailed(evaluation.failureDescription)
            }
        }
    }

    private func intValue(_ name: String, defaultValue: Int) throws -> Int {
        guard options.contains(name) else {
            return defaultValue
        }
        let raw = try SettingsStore.requiredValue(for: name, in: options)
        guard let value = Int(raw) else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func format(_ report: BenchmarkReport) -> String {
        BenchmarkFormatter.format(report)
    }
}

enum BenchmarkRunner {
    private static let recognizerSampleBatchSize = 256
    private static let scrollPlannerSampleBatchSize = 16

    static func run(events: Int) -> BenchmarkReport {
        let recognizer = runRecognizerBenchmark(eventCount: events)
        let planner = runPlannerBenchmark(iterations: max(events / 64, 1))
        let reviewMetrics = BenchmarkReviewMetrics(
            totalWallClockSeconds: recognizer.wallClockSeconds + planner.wallClockSeconds,
            totalCpuSeconds: recognizer.cpuSeconds + planner.cpuSeconds,
            recognizerCpuNanosecondsPerEvent: recognizer.cpuNanosecondsPerEvent,
            scrollPlannerCpuNanosecondsPerCommand: planner.cpuNanosecondsPerCommand,
            recognizerP95NanosecondsPerEvent: recognizer.sampledNanosecondsPerEvent.p95Nanoseconds,
            recognizerP99NanosecondsPerEvent: recognizer.sampledNanosecondsPerEvent.p99Nanoseconds,
            scrollPlannerP95NanosecondsPerCommand: planner.sampledNanosecondsPerCommand.p95Nanoseconds,
            scrollPlannerP99NanosecondsPerCommand: planner.sampledNanosecondsPerCommand.p99Nanoseconds
        )
        return BenchmarkReport(
            schemaVersion: 3,
            measurementKind: "pureLogic",
            measurementScope: "GestureRecognizer と ScrollGenerationPlanner のインプロセス処理。イベントタップ、IOHID、CGEvent 投稿、AppKit 受信、画面反映は含みません。",
            includesEventTapAndPosting: false,
            rawInputEvents: events,
            recognizer: recognizer,
            scrollPlanner: planner,
            reviewMetrics: reviewMetrics,
            note: "イベントタップ、IOHID、実イベント投稿を含まない純粋ロジックの目安です。"
        )
    }

    private static func runRecognizerBenchmark(eventCount: Int) -> RecognizerBenchmarkReport {
        var recognizer = GestureRecognizer(
            configuration: GestureConfiguration(
                deadZonePoints: 3,
                acceleration: GestureAccelerationConfiguration(
                    isEnabled: true,
                    thresholdVelocity: 500,
                    exponent: 1.2,
                    maximumMultiplier: 3
                )
            )
        )
        var commandCount = 0
        var suppressedCount = 0
        var batchSamples: [Double] = []
        let startCPU = CPUTime.current()
        let start = DispatchTime.now().uptimeNanoseconds
        var batchStart = start
        var batchEventCount = 0

        for index in 0..<eventCount {
            let cycle = index % 12
            let time = Double(index) * 0.001
            let event: RawInputEvent

            switch cycle {
            case 0:
                event = .buttonDown(button: .button4, time: time)
            case 1...10:
                event = .move(deltaX: 2, deltaY: cycle % 3 == 0 ? 1 : 0, time: time)
            default:
                event = .buttonUp(button: .button4, time: time)
            }

            let decision = recognizer.handle(event)
            commandCount += decision.commands.count
            if decision.shouldSuppressOriginal {
                suppressedCount += 1
            }

            batchEventCount += 1
            if batchEventCount == recognizerSampleBatchSize {
                let batchEnd = DispatchTime.now().uptimeNanoseconds
                appendSample(
                    from: batchStart,
                    to: batchEnd,
                    unitCount: batchEventCount,
                    samples: &batchSamples
                )
                batchStart = batchEnd
                batchEventCount = 0
            }
        }

        if batchEventCount > 0 {
            appendSample(
                from: batchStart,
                to: DispatchTime.now().uptimeNanoseconds,
                unitCount: batchEventCount,
                samples: &batchSamples
            )
        }

        let elapsed = seconds(fromNanoseconds: DispatchTime.now().uptimeNanoseconds - start)
        let cpu = CPUTime.current() - startCPU
        return RecognizerBenchmarkReport(
            wallClockSeconds: elapsed,
            cpuSeconds: cpu.total,
            cpuPercentOfOneCore: percent(cpu.total, elapsed),
            eventsPerSecond: rate(Double(eventCount), elapsed),
            averageNanosecondsPerEvent: elapsed * 1_000_000_000 / Double(eventCount),
            cpuNanosecondsPerEvent: cpu.total * 1_000_000_000 / Double(eventCount),
            sampledNanosecondsPerEvent: BenchmarkLatencyDistribution(
                measurement: "recognizer.batchWallClockNanosecondsPerEvent",
                sampleUnit: "event",
                batchSize: recognizerSampleBatchSize,
                samples: batchSamples
            ),
            commandsProduced: commandCount,
            suppressedOriginalEvents: suppressedCount
        )
    }

    private static func runPlannerBenchmark(iterations: Int) -> ScrollPlannerBenchmarkReport {
        var commandCount = 0
        var batchCommandCount = 0
        var batchIterationCount = 0
        var batchSamples: [Double] = []
        let startCPU = CPUTime.current()
        let start = DispatchTime.now().uptimeNanoseconds
        var batchStart = start

        for index in 0..<iterations {
            let commands = ScrollGenerationPlanner.makeCommands(
                deltaX: index % 2 == 0 ? 1200 : 0,
                deltaY: index % 2 == 0 ? 0 : -480,
                steps: 24,
                interval: 0.008,
                phaseOverride: nil,
                momentumSteps: 12,
                momentumDecay: 0.85,
                momentumScale: 1.0,
                startTime: Double(index)
            )
            commandCount += commands.count
            batchCommandCount += commands.count
            batchIterationCount += 1

            if batchIterationCount == scrollPlannerSampleBatchSize {
                let batchEnd = DispatchTime.now().uptimeNanoseconds
                appendSample(
                    from: batchStart,
                    to: batchEnd,
                    unitCount: batchCommandCount,
                    samples: &batchSamples
                )
                batchStart = batchEnd
                batchCommandCount = 0
                batchIterationCount = 0
            }
        }

        if batchCommandCount > 0 {
            appendSample(
                from: batchStart,
                to: DispatchTime.now().uptimeNanoseconds,
                unitCount: batchCommandCount,
                samples: &batchSamples
            )
        }

        let elapsed = seconds(fromNanoseconds: DispatchTime.now().uptimeNanoseconds - start)
        let cpu = CPUTime.current() - startCPU
        let commandTotal = Double(commandCount)
        return ScrollPlannerBenchmarkReport(
            iterations: iterations,
            commandsProduced: commandCount,
            wallClockSeconds: elapsed,
            cpuSeconds: cpu.total,
            cpuPercentOfOneCore: percent(cpu.total, elapsed),
            commandsPerSecond: rate(commandTotal, elapsed),
            averageNanosecondsPerCommand: averageNanoseconds(elapsed, commandTotal),
            cpuNanosecondsPerCommand: averageNanoseconds(cpu.total, commandTotal),
            sampledNanosecondsPerCommand: BenchmarkLatencyDistribution(
                measurement: "scrollPlanner.batchWallClockNanosecondsPerCommand",
                sampleUnit: "command",
                batchSize: scrollPlannerSampleBatchSize,
                samples: batchSamples
            ),
            commandsPerIteration: Double(commandCount) / Double(iterations)
        )
    }

    private static func appendSample(
        from start: UInt64,
        to end: UInt64,
        unitCount: Int,
        samples: inout [Double]
    ) {
        guard unitCount > 0 else {
            return
        }
        samples.append(Double(end - start) / Double(unitCount))
    }

    private static func seconds(fromNanoseconds value: UInt64) -> Double {
        Double(value) / 1_000_000_000
    }

    private static func rate(_ count: Double, _ seconds: Double) -> Double {
        guard seconds > 0 else {
            return 0
        }
        return count / seconds
    }

    private static func percent(_ cpuSeconds: Double, _ wallClockSeconds: Double) -> Double {
        guard wallClockSeconds > 0 else {
            return 0
        }
        return cpuSeconds / wallClockSeconds * 100
    }

    private static func averageNanoseconds(_ seconds: Double, _ count: Double) -> Double {
        guard count > 0 else {
            return 0
        }
        return seconds * 1_000_000_000 / count
    }
}

enum BenchmarkFormatter {
    static func format(_ report: BenchmarkReport) -> String {
        """
        ベンチマーク結果
        スキーマ版: \(report.schemaVersion)
        測定種別: \(report.measurementKind)
        測定範囲: \(report.measurementScope)
        イベントタップから投稿までを含む: \(report.includesEventTapAndPosting ? "はい" : "いいえ")
        認識器イベント数: \(report.rawInputEvents)
        認識器 wall: \(formatSeconds(report.recognizer.wallClockSeconds)) 秒
        認識器 CPU: \(formatSeconds(report.recognizer.cpuSeconds)) 秒
        認識器 CPU 使用率目安: \(formatPercent(report.recognizer.cpuPercentOfOneCore)) % / 1 core
        認識器処理速度: \(formatRate(report.recognizer.eventsPerSecond)) events/sec
        認識器平均処理時間: \(formatNanoseconds(report.recognizer.averageNanosecondsPerEvent)) ns/event
        認識器 CPU コスト: \(formatNanoseconds(report.recognizer.cpuNanosecondsPerEvent)) ns/event
        認識器 batch p95: \(formatNanoseconds(report.recognizer.sampledNanosecondsPerEvent.p95Nanoseconds)) ns/event
        認識器 batch p99: \(formatNanoseconds(report.recognizer.sampledNanosecondsPerEvent.p99Nanoseconds)) ns/event
        生成コマンド数: \(report.recognizer.commandsProduced)
        元イベント抑制数: \(report.recognizer.suppressedOriginalEvents)
        スクロール計画回数: \(report.scrollPlanner.iterations)
        スクロール計画コマンド数: \(report.scrollPlanner.commandsProduced)
        スクロール計画 wall: \(formatSeconds(report.scrollPlanner.wallClockSeconds)) 秒
        スクロール計画 CPU: \(formatSeconds(report.scrollPlanner.cpuSeconds)) 秒
        スクロール計画 CPU 使用率目安: \(formatPercent(report.scrollPlanner.cpuPercentOfOneCore)) % / 1 core
        スクロール計画処理速度: \(formatRate(report.scrollPlanner.commandsPerSecond)) commands/sec
        スクロール計画平均処理時間: \(formatNanoseconds(report.scrollPlanner.averageNanosecondsPerCommand)) ns/command
        スクロール計画 CPU コスト: \(formatNanoseconds(report.scrollPlanner.cpuNanosecondsPerCommand)) ns/command
        スクロール計画 batch p95: \(formatNanoseconds(report.scrollPlanner.sampledNanosecondsPerCommand.p95Nanoseconds)) ns/command
        スクロール計画 batch p99: \(formatNanoseconds(report.scrollPlanner.sampledNanosecondsPerCommand.p99Nanoseconds)) ns/command
        スクロール計画コマンド数/回: \(formatDouble(report.scrollPlanner.commandsPerIteration))
        合計 wall: \(formatSeconds(report.reviewMetrics.totalWallClockSeconds)) 秒
        合計 CPU: \(formatSeconds(report.reviewMetrics.totalCpuSeconds)) 秒
        合計 CPU 使用率目安: \(formatPercent(report.reviewMetrics.totalCpuPercentOfOneCore)) % / 1 core
        注記: \(report.note)
        """
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func formatRate(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private static func formatNanoseconds(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func formatDouble(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct BenchmarkReport: Codable {
    var schemaVersion: Int
    var measurementKind: String
    var measurementScope: String
    var includesEventTapAndPosting: Bool
    var rawInputEvents: Int
    var recognizer: RecognizerBenchmarkReport
    var scrollPlanner: ScrollPlannerBenchmarkReport
    var reviewMetrics: BenchmarkReviewMetrics
    var note: String
}

struct RecognizerBenchmarkReport: Codable {
    var wallClockSeconds: Double
    var cpuSeconds: Double
    var cpuPercentOfOneCore: Double
    var eventsPerSecond: Double
    var averageNanosecondsPerEvent: Double
    var cpuNanosecondsPerEvent: Double
    var sampledNanosecondsPerEvent: BenchmarkLatencyDistribution
    var commandsProduced: Int
    var suppressedOriginalEvents: Int
}

struct ScrollPlannerBenchmarkReport: Codable {
    var iterations: Int
    var commandsProduced: Int
    var wallClockSeconds: Double
    var cpuSeconds: Double
    var cpuPercentOfOneCore: Double
    var commandsPerSecond: Double
    var averageNanosecondsPerCommand: Double
    var cpuNanosecondsPerCommand: Double
    var sampledNanosecondsPerCommand: BenchmarkLatencyDistribution
    var commandsPerIteration: Double
}

struct BenchmarkLatencyDistribution: Codable {
    var measurement: String
    var sampleUnit: String
    var sampleCount: Int
    var batchSize: Int
    var minimumNanoseconds: Double
    var p50Nanoseconds: Double
    var p95Nanoseconds: Double
    var p99Nanoseconds: Double
    var maximumNanoseconds: Double

    init(
        measurement: String,
        sampleUnit: String,
        batchSize: Int,
        samples: [Double]
    ) {
        let sorted = samples.sorted()
        self.measurement = measurement
        self.sampleUnit = sampleUnit
        self.sampleCount = sorted.count
        self.batchSize = batchSize
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

struct BenchmarkReviewMetrics: Codable {
    var totalWallClockSeconds: Double
    var totalCpuSeconds: Double
    var totalCpuPercentOfOneCore: Double
    var recognizerCpuNanosecondsPerEvent: Double
    var scrollPlannerCpuNanosecondsPerCommand: Double
    var recognizerP95NanosecondsPerEvent: Double
    var recognizerP99NanosecondsPerEvent: Double
    var scrollPlannerP95NanosecondsPerCommand: Double
    var scrollPlannerP99NanosecondsPerCommand: Double

    init(
        totalWallClockSeconds: Double,
        totalCpuSeconds: Double,
        recognizerCpuNanosecondsPerEvent: Double,
        scrollPlannerCpuNanosecondsPerCommand: Double,
        recognizerP95NanosecondsPerEvent: Double,
        recognizerP99NanosecondsPerEvent: Double,
        scrollPlannerP95NanosecondsPerCommand: Double,
        scrollPlannerP99NanosecondsPerCommand: Double
    ) {
        self.totalWallClockSeconds = totalWallClockSeconds
        self.totalCpuSeconds = totalCpuSeconds
        self.totalCpuPercentOfOneCore = totalWallClockSeconds > 0
            ? totalCpuSeconds / totalWallClockSeconds * 100
            : 0
        self.recognizerCpuNanosecondsPerEvent = recognizerCpuNanosecondsPerEvent
        self.scrollPlannerCpuNanosecondsPerCommand = scrollPlannerCpuNanosecondsPerCommand
        self.recognizerP95NanosecondsPerEvent = recognizerP95NanosecondsPerEvent
        self.recognizerP99NanosecondsPerEvent = recognizerP99NanosecondsPerEvent
        self.scrollPlannerP95NanosecondsPerCommand = scrollPlannerP95NanosecondsPerCommand
        self.scrollPlannerP99NanosecondsPerCommand = scrollPlannerP99NanosecondsPerCommand
    }
}

enum BenchmarkBaseline {
    static let expectedMeasurementKind = "pureLogic"
    static let expectedIncludesEventTapAndPosting = false
    static let maximumRecognizerAverageNanosecondsPerEvent = 2_000.0
    static let maximumRecognizerCpuNanosecondsPerEvent = 2_000.0
    static let maximumScrollPlannerAverageNanosecondsPerCommand = 2_000.0
    static let maximumScrollPlannerCpuNanosecondsPerCommand = 2_000.0
    static let maximumRecognizerP95NanosecondsPerEvent = 50_000.0
    static let maximumRecognizerP99NanosecondsPerEvent = 250_000.0
    static let maximumScrollPlannerP95NanosecondsPerCommand = 50_000.0
    static let maximumScrollPlannerP99NanosecondsPerCommand = 250_000.0

    static func evaluate(_ report: BenchmarkReport) -> BenchmarkBaselineEvaluation {
        var failures: [BenchmarkBaselineFailure] = []

        if report.measurementKind != expectedMeasurementKind {
            failures.append(
                BenchmarkBaselineFailure(
                    item: "measurementKind",
                    expected: expectedMeasurementKind,
                    actual: report.measurementKind
                )
            )
        }

        if report.includesEventTapAndPosting != expectedIncludesEventTapAndPosting {
            failures.append(
                BenchmarkBaselineFailure(
                    item: "includesEventTapAndPosting",
                    expected: String(expectedIncludesEventTapAndPosting),
                    actual: String(report.includesEventTapAndPosting)
                )
            )
        }

        appendMaximumFailure(
            item: "recognizer.averageNanosecondsPerEvent",
            actual: report.recognizer.averageNanosecondsPerEvent,
            maximum: maximumRecognizerAverageNanosecondsPerEvent,
            failures: &failures
        )
        appendMaximumFailure(
            item: "recognizer.cpuNanosecondsPerEvent",
            actual: report.recognizer.cpuNanosecondsPerEvent,
            maximum: maximumRecognizerCpuNanosecondsPerEvent,
            failures: &failures
        )
        appendMaximumFailure(
            item: "recognizer.sampledNanosecondsPerEvent.p95Nanoseconds",
            actual: report.recognizer.sampledNanosecondsPerEvent.p95Nanoseconds,
            maximum: maximumRecognizerP95NanosecondsPerEvent,
            failures: &failures
        )
        appendMaximumFailure(
            item: "recognizer.sampledNanosecondsPerEvent.p99Nanoseconds",
            actual: report.recognizer.sampledNanosecondsPerEvent.p99Nanoseconds,
            maximum: maximumRecognizerP99NanosecondsPerEvent,
            failures: &failures
        )
        appendMaximumFailure(
            item: "scrollPlanner.averageNanosecondsPerCommand",
            actual: report.scrollPlanner.averageNanosecondsPerCommand,
            maximum: maximumScrollPlannerAverageNanosecondsPerCommand,
            failures: &failures
        )
        appendMaximumFailure(
            item: "scrollPlanner.cpuNanosecondsPerCommand",
            actual: report.scrollPlanner.cpuNanosecondsPerCommand,
            maximum: maximumScrollPlannerCpuNanosecondsPerCommand,
            failures: &failures
        )
        appendMaximumFailure(
            item: "scrollPlanner.sampledNanosecondsPerCommand.p95Nanoseconds",
            actual: report.scrollPlanner.sampledNanosecondsPerCommand.p95Nanoseconds,
            maximum: maximumScrollPlannerP95NanosecondsPerCommand,
            failures: &failures
        )
        appendMaximumFailure(
            item: "scrollPlanner.sampledNanosecondsPerCommand.p99Nanoseconds",
            actual: report.scrollPlanner.sampledNanosecondsPerCommand.p99Nanoseconds,
            maximum: maximumScrollPlannerP99NanosecondsPerCommand,
            failures: &failures
        )

        return BenchmarkBaselineEvaluation(failures: failures)
    }

    private static func appendMaximumFailure(
        item: String,
        actual: Double,
        maximum: Double,
        failures: inout [BenchmarkBaselineFailure]
    ) {
        guard actual > maximum else {
            return
        }
        failures.append(
            BenchmarkBaselineFailure(
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

struct BenchmarkBaselineEvaluation {
    var failures: [BenchmarkBaselineFailure]

    var passed: Bool {
        failures.isEmpty
    }

    var failureDescription: String {
        failures
            .map { "- \($0.item): expected \($0.expected), actual \($0.actual)" }
            .joined(separator: "\n")
    }
}

struct BenchmarkBaselineFailure {
    var item: String
    var expected: String
    var actual: String
}

private struct CPUTime {
    var user: Double
    var system: Double

    var total: Double {
        user + system
    }

    static func current() -> CPUTime {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return CPUTime(
            user: seconds(usage.ru_utime),
            system: seconds(usage.ru_stime)
        )
    }

    private static func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }

    static func - (lhs: CPUTime, rhs: CPUTime) -> CPUTime {
        CPUTime(user: lhs.user - rhs.user, system: lhs.system - rhs.system)
    }
}
