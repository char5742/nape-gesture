import Darwin
import Foundation
import MacGestureCore

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

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(format(report))
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
    static func run(events: Int) -> BenchmarkReport {
        let recognizer = runRecognizerBenchmark(eventCount: events)
        let planner = runPlannerBenchmark(iterations: max(events / 64, 1))
        return BenchmarkReport(
            rawInputEvents: events,
            recognizer: recognizer,
            scrollPlanner: planner,
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
        let startCPU = CPUTime.current()
        let start = DispatchTime.now().uptimeNanoseconds

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
        }

        let elapsed = seconds(fromNanoseconds: DispatchTime.now().uptimeNanoseconds - start)
        let cpu = CPUTime.current() - startCPU
        return RecognizerBenchmarkReport(
            wallClockSeconds: elapsed,
            cpuSeconds: cpu.total,
            eventsPerSecond: rate(Double(eventCount), elapsed),
            averageNanosecondsPerEvent: elapsed * 1_000_000_000 / Double(eventCount),
            commandsProduced: commandCount,
            suppressedOriginalEvents: suppressedCount
        )
    }

    private static func runPlannerBenchmark(iterations: Int) -> ScrollPlannerBenchmarkReport {
        var commandCount = 0
        let startCPU = CPUTime.current()
        let start = DispatchTime.now().uptimeNanoseconds

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
        }

        let elapsed = seconds(fromNanoseconds: DispatchTime.now().uptimeNanoseconds - start)
        let cpu = CPUTime.current() - startCPU
        return ScrollPlannerBenchmarkReport(
            iterations: iterations,
            commandsProduced: commandCount,
            wallClockSeconds: elapsed,
            cpuSeconds: cpu.total,
            commandsPerSecond: rate(Double(commandCount), elapsed)
        )
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
}

enum BenchmarkFormatter {
    static func format(_ report: BenchmarkReport) -> String {
        """
        ベンチマーク結果
        認識器イベント数: \(report.rawInputEvents)
        認識器 wall: \(formatSeconds(report.recognizer.wallClockSeconds)) 秒
        認識器 CPU: \(formatSeconds(report.recognizer.cpuSeconds)) 秒
        認識器処理速度: \(formatRate(report.recognizer.eventsPerSecond)) events/sec
        認識器平均処理時間: \(formatNanoseconds(report.recognizer.averageNanosecondsPerEvent)) ns/event
        生成コマンド数: \(report.recognizer.commandsProduced)
        元イベント抑制数: \(report.recognizer.suppressedOriginalEvents)
        スクロール計画回数: \(report.scrollPlanner.iterations)
        スクロール計画コマンド数: \(report.scrollPlanner.commandsProduced)
        スクロール計画 wall: \(formatSeconds(report.scrollPlanner.wallClockSeconds)) 秒
        スクロール計画 CPU: \(formatSeconds(report.scrollPlanner.cpuSeconds)) 秒
        スクロール計画処理速度: \(formatRate(report.scrollPlanner.commandsPerSecond)) commands/sec
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
}

struct BenchmarkReport: Codable {
    var rawInputEvents: Int
    var recognizer: RecognizerBenchmarkReport
    var scrollPlanner: ScrollPlannerBenchmarkReport
    var note: String
}

struct RecognizerBenchmarkReport: Codable {
    var wallClockSeconds: Double
    var cpuSeconds: Double
    var eventsPerSecond: Double
    var averageNanosecondsPerEvent: Double
    var commandsProduced: Int
    var suppressedOriginalEvents: Int
}

struct ScrollPlannerBenchmarkReport: Codable {
    var iterations: Int
    var commandsProduced: Int
    var wallClockSeconds: Double
    var cpuSeconds: Double
    var commandsPerSecond: Double
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
