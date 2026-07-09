import Foundation

struct CPUSampleCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let pid = try intValue("--pid")
        let duration = try doubleValue("--duration", defaultValue: 30)
        let interval = try doubleValue("--interval", defaultValue: 1)
        let mode = try CPUSampleMode(raw: SettingsStore.value(for: "--mode", in: options) ?? "idle")
        let report = try CPUSampler.sample(pid: pid, duration: duration, interval: interval, mode: mode)

        let output: String
        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            output = String(decoding: data, as: UTF8.self) + "\n"
        } else {
            output = CPUSampleFormatter.format(report)
        }

        try write(output, to: SettingsStore.value(for: "--out", in: options))

        if options.contains("--assert-baseline") {
            if report.baseline.passed {
                fputs("常駐 CPU 使用率基準: 合格\n", stderr)
            } else {
                throw CPUSampleBaselineAssertionError(message: report.baseline.failureDescription ?? "CPU 基準を満たしていません。")
            }
        }
    }

    private func intValue(_ name: String) throws -> Int {
        let raw = try SettingsStore.requiredValue(for: name, in: options)
        guard let value = Int(raw), value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func doubleValue(_ name: String, defaultValue: Double) throws -> Double {
        guard options.contains(name) else {
            return defaultValue
        }
        let raw = try SettingsStore.requiredValue(for: name, in: options)
        guard let value = Double(raw), value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func write(_ text: String, to outputPath: String?) throws {
        guard let outputPath else {
            print(text, terminator: "")
            return
        }

        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
        fputs("CPU 使用率サンプルを書き出しました: \(outputPath)\n", stderr)
    }
}

private enum CPUSampleMode: String, Encodable {
    case idle
    case active
    case recovery

    init(raw: String) throws {
        guard let mode = CPUSampleMode(rawValue: raw) else {
            throw ToolError.invalidValue("--mode", raw)
        }
        self = mode
    }

    var averageLimitPercentOfOneCore: Double {
        switch self {
        case .idle, .recovery:
            return 1
        case .active:
            return 15
        }
    }

    var description: String {
        switch self {
        case .idle:
            return "アイドル"
        case .active:
            return "連続ジェスチャー"
        case .recovery:
            return "操作終了後"
        }
    }
}

private enum CPUSampler {
    static func sample(
        pid: Int,
        duration: TimeInterval,
        interval: TimeInterval,
        mode: CPUSampleMode
    ) throws -> CPUSampleReport {
        let command = try processCommand(pid: pid)
        let requestedSamples = max(1, Int(ceil(duration / interval)))
        let start = Date()
        var samples: [CPUSample] = []
        var processExitedEarly = false

        for index in 0..<requestedSamples {
            if index > 0 {
                Thread.sleep(forTimeInterval: interval)
            }

            guard let cpu = try cpuPercent(pid: pid) else {
                processExitedEarly = true
                break
            }
            samples.append(
                CPUSample(
                    timestampUnixSeconds: Date().timeIntervalSince1970,
                    cpuPercentOfOneCore: cpu
                )
            )
        }

        let actualDuration = Date().timeIntervalSince(start)
        let values = samples.map(\.cpuPercentOfOneCore)
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let maximum = values.max() ?? 0
        let baseline = CPUSampleBaseline(
            mode: mode,
            averageLimitPercentOfOneCore: mode.averageLimitPercentOfOneCore,
            passed: !samples.isEmpty && !processExitedEarly && average <= mode.averageLimitPercentOfOneCore,
            failureDescription: failureDescription(
                mode: mode,
                average: average,
                samples: samples,
                processExitedEarly: processExitedEarly
            )
        )

        return CPUSampleReport(
            schemaVersion: 1,
            measurementKind: "processCpuSampling",
            measurementScope: "指定 PID を ps の %CPU で周期サンプルした常駐 CPU 使用率。イベントタップ遅延、AppKit 受信、画面反映は含みません。",
            includesEventTapAndPosting: false,
            pid: pid,
            processCommand: command,
            requestedDurationSeconds: duration,
            sampleIntervalSeconds: interval,
            actualDurationSeconds: actualDuration,
            sampleCount: samples.count,
            averagePercentOfOneCore: average,
            maximumPercentOfOneCore: maximum,
            processExitedEarly: processExitedEarly,
            baseline: baseline,
            samples: samples
        )
    }

    private static func failureDescription(
        mode: CPUSampleMode,
        average: Double,
        samples: [CPUSample],
        processExitedEarly: Bool
    ) -> String? {
        if samples.isEmpty {
            return "CPU 使用率サンプルがありません。PID とプロセス寿命を確認してください。"
        }
        if processExitedEarly {
            return "測定中に対象プロセスが終了しました。常駐 CPU 証跡として採用できません。"
        }
        if average > mode.averageLimitPercentOfOneCore {
            return "\(mode.description) 平均 CPU 使用率 \(format(average))% が基準 \(format(mode.averageLimitPercentOfOneCore))% を超えています。"
        }
        return nil
    }

    private static func cpuPercent(pid: Int) throws -> Double? {
        let output = try runPS(pid: pid, column: "%cpu=")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let value = Double(trimmed) else {
            throw ToolError.invalidValue("ps %CPU", trimmed)
        }
        return value
    }

    private static func processCommand(pid: Int) throws -> String {
        let output = try runPS(pid: pid, column: "comm=")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.invalidValue("--pid", "プロセスが見つかりません: \(pid)")
        }
        return trimmed
    }

    private static func runPS(pid: Int, column: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", column]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct CPUSampleReport: Encodable {
    let schemaVersion: Int
    let measurementKind: String
    let measurementScope: String
    let includesEventTapAndPosting: Bool
    let pid: Int
    let processCommand: String
    let requestedDurationSeconds: Double
    let sampleIntervalSeconds: Double
    let actualDurationSeconds: Double
    let sampleCount: Int
    let averagePercentOfOneCore: Double
    let maximumPercentOfOneCore: Double
    let processExitedEarly: Bool
    let baseline: CPUSampleBaseline
    let samples: [CPUSample]
}

private struct CPUSample: Encodable {
    let timestampUnixSeconds: Double
    let cpuPercentOfOneCore: Double
}

private struct CPUSampleBaseline: Encodable {
    let mode: CPUSampleMode
    let averageLimitPercentOfOneCore: Double
    let passed: Bool
    let failureDescription: String?
}

private enum CPUSampleFormatter {
    static func format(_ report: CPUSampleReport) -> String {
        """
        常駐 CPU 使用率サンプル
        スキーマ版: \(report.schemaVersion)
        測定種別: \(report.measurementKind)
        PID: \(report.pid)
        コマンド: \(report.processCommand)
        サンプル数: \(report.sampleCount)
        要求 duration: \(formatSeconds(report.requestedDurationSeconds)) 秒
        実測 duration: \(formatSeconds(report.actualDurationSeconds)) 秒
        interval: \(formatSeconds(report.sampleIntervalSeconds)) 秒
        平均 CPU: \(formatPercent(report.averagePercentOfOneCore)) % / 1 core
        最大 CPU: \(formatPercent(report.maximumPercentOfOneCore)) % / 1 core
        基準 mode: \(report.baseline.mode.rawValue)
        基準平均 CPU: \(formatPercent(report.baseline.averageLimitPercentOfOneCore)) % / 1 core
        基準判定: \(report.baseline.passed ? "合格" : "不合格")
        """
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct CPUSampleBaselineAssertionError: LocalizedError {
    var message: String

    var errorDescription: String? {
        "常駐 CPU 使用率基準を満たしていません。\n\(message)"
    }
}
