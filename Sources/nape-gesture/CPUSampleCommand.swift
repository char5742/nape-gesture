import Darwin
import Foundation

struct CPUSampleCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let pid = try intValue("--pid")
        let expectedExecutablePath = try SettingsStore.requiredValue(
            for: "--expected-executable",
            in: options
        )
        let duration = try doubleValue("--duration", defaultValue: 30)
        let interval = try doubleValue("--interval", defaultValue: 1)
        let mode = try CPUSampleMode(raw: SettingsStore.value(for: "--mode", in: options) ?? "idle")
        let report = try CPUSampler.sample(
            pid: pid,
            expectedExecutablePath: expectedExecutablePath,
            duration: duration,
            interval: interval,
            mode: mode
        )

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
        expectedExecutablePath rawExpectedExecutablePath: String,
        duration: TimeInterval,
        interval: TimeInterval,
        mode: CPUSampleMode
    ) throws -> CPUSampleReport {
        let expectedExecutablePath = try ProcessIdentityResolver.expectedExecutablePath(
            rawExpectedExecutablePath
        )
        let initialIdentity = try ProcessIdentityResolver.snapshot(pid: pid)
        let command = try processCommand(pid: pid)
        let requestedSamples = max(1, Int(ceil(duration / interval)))
        let start = Date()
        var samples: [CPUSample] = []
        var processExitedEarly = false
        var executableIdentityMatched = initialIdentity.resolvedExecutablePath == expectedExecutablePath
        var processIdentityStable = true
        var resolvedExecutablePath = initialIdentity.resolvedExecutablePath
        var identityFailureDescription: String?

        if !executableIdentityMatched {
            identityFailureDescription = "指定 PID \(pid) の実行ファイルが期待値と一致しません。expected=\(expectedExecutablePath), resolved=\(initialIdentity.resolvedExecutablePath)"
        }

        for index in 0..<requestedSamples {
            guard executableIdentityMatched else {
                break
            }
            if index > 0 {
                Thread.sleep(forTimeInterval: interval)
            }

            guard let identityBeforeSample = inspectIdentity(
                pid: pid,
                expectedExecutablePath: expectedExecutablePath,
                initialIdentity: initialIdentity,
                sampleNumber: index + 1,
                phase: "採取前",
                processExitedEarly: &processExitedEarly,
                executableIdentityMatched: &executableIdentityMatched,
                processIdentityStable: &processIdentityStable,
                resolvedExecutablePath: &resolvedExecutablePath,
                failureDescription: &identityFailureDescription
            ) else {
                break
            }

            guard let cpu = try cpuPercent(pid: pid) else {
                processExitedEarly = true
                executableIdentityMatched = false
                processIdentityStable = false
                identityFailureDescription = "sample \(index + 1) の CPU 使用率を取得できませんでした。対象プロセスが終了したか PID が再利用された可能性があります。"
                break
            }

            guard let identityAfterSample = inspectIdentity(
                pid: pid,
                expectedExecutablePath: expectedExecutablePath,
                initialIdentity: initialIdentity,
                sampleNumber: index + 1,
                phase: "採取後",
                processExitedEarly: &processExitedEarly,
                executableIdentityMatched: &executableIdentityMatched,
                processIdentityStable: &processIdentityStable,
                resolvedExecutablePath: &resolvedExecutablePath,
                failureDescription: &identityFailureDescription
            ) else {
                break
            }

            guard identityBeforeSample == identityAfterSample else {
                executableIdentityMatched = false
                processIdentityStable = false
                identityFailureDescription = identityChangeDescription(
                    pid: pid,
                    sampleNumber: index + 1,
                    phase: "CPU 採取中",
                    expectedExecutablePath: expectedExecutablePath,
                    initialIdentity: identityBeforeSample,
                    observedIdentity: identityAfterSample
                )
                break
            }

            samples.append(
                CPUSample(
                    timestampUnixSeconds: Date().timeIntervalSince1970,
                    cpuPercentOfOneCore: cpu,
                    resolvedExecutablePath: identityAfterSample.resolvedExecutablePath,
                    processStartToken: identityAfterSample.processStartToken,
                    executableIdentityMatched: true
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
            passed: !samples.isEmpty
                && !processExitedEarly
                && executableIdentityMatched
                && processIdentityStable
                && average <= mode.averageLimitPercentOfOneCore,
            failureDescription: failureDescription(
                mode: mode,
                average: average,
                samples: samples,
                processExitedEarly: processExitedEarly,
                identityFailureDescription: identityFailureDescription
            )
        )

        return CPUSampleReport(
            schemaVersion: 1,
            measurementKind: "processCpuSampling",
            measurementScope: "指定 PID を ps の %CPU で周期サンプルした常駐 CPU 使用率。イベントタップ遅延、AppKit 受信、画面反映は含みません。",
            includesEventTapAndPosting: false,
            pid: pid,
            processCommand: command,
            expectedExecutablePath: expectedExecutablePath,
            resolvedExecutablePath: resolvedExecutablePath,
            executableIdentityMatched: executableIdentityMatched,
            processStartToken: initialIdentity.processStartToken,
            processIdentityStable: processIdentityStable,
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
        processExitedEarly: Bool,
        identityFailureDescription: String?
    ) -> String? {
        if let identityFailureDescription {
            return identityFailureDescription
        }
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

    private static func inspectIdentity(
        pid: Int,
        expectedExecutablePath: String,
        initialIdentity: ProcessIdentitySnapshot,
        sampleNumber: Int,
        phase: String,
        processExitedEarly: inout Bool,
        executableIdentityMatched: inout Bool,
        processIdentityStable: inout Bool,
        resolvedExecutablePath: inout String,
        failureDescription: inout String?
    ) -> ProcessIdentitySnapshot? {
        let observedIdentity: ProcessIdentitySnapshot
        do {
            observedIdentity = try ProcessIdentityResolver.snapshot(pid: pid)
        } catch {
            processExitedEarly = !ProcessIdentityResolver.processIsAlive(pid: pid)
            executableIdentityMatched = false
            processIdentityStable = false
            failureDescription = "sample \(sampleNumber) \(phase)に PID \(pid) の実行主体を再確認できませんでした。\(error.localizedDescription)"
            return nil
        }

        resolvedExecutablePath = observedIdentity.resolvedExecutablePath
        guard observedIdentity == initialIdentity,
              observedIdentity.resolvedExecutablePath == expectedExecutablePath else {
            executableIdentityMatched = false
            processIdentityStable = false
            failureDescription = identityChangeDescription(
                pid: pid,
                sampleNumber: sampleNumber,
                phase: phase,
                expectedExecutablePath: expectedExecutablePath,
                initialIdentity: initialIdentity,
                observedIdentity: observedIdentity
            )
            return nil
        }

        return observedIdentity
    }

    private static func identityChangeDescription(
        pid: Int,
        sampleNumber: Int,
        phase: String,
        expectedExecutablePath: String,
        initialIdentity: ProcessIdentitySnapshot,
        observedIdentity: ProcessIdentitySnapshot
    ) -> String {
        if observedIdentity.processStartToken != initialIdentity.processStartToken {
            return "sample \(sampleNumber) \(phase)に PID \(pid) の開始トークンが変化しました。PID 再利用の可能性があるため証跡として採用できません。initial=\(initialIdentity.processStartToken), observed=\(observedIdentity.processStartToken)"
        }
        return "sample \(sampleNumber) \(phase)に PID \(pid) の実行ファイルが変化しました。expected=\(expectedExecutablePath), resolved=\(observedIdentity.resolvedExecutablePath)"
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

private struct ProcessIdentitySnapshot: Equatable {
    let resolvedExecutablePath: String
    let processStartToken: String
}

private enum ProcessIdentityResolver {
    static func expectedExecutablePath(_ rawPath: String) throws -> String {
        let path = canonicalPath(rawPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ToolError.invalidValue(
                "--expected-executable",
                "実行ファイルが存在しません: \(rawPath)"
            )
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw ToolError.invalidValue(
                "--expected-executable",
                "実行可能なファイルではありません: \(rawPath)"
            )
        }
        return path
    }

    static func snapshot(pid: Int) throws -> ProcessIdentitySnapshot {
        let startTokenBeforePath = try processStartToken(pid: pid)
        let executablePath = try resolvedExecutablePath(pid: pid)
        let startTokenAfterPath = try processStartToken(pid: pid)

        guard startTokenBeforePath == startTokenAfterPath else {
            throw ProcessIdentityInspectionError.changedDuringInspection(
                pid: pid,
                initialToken: startTokenBeforePath,
                observedToken: startTokenAfterPath
            )
        }

        return ProcessIdentitySnapshot(
            resolvedExecutablePath: executablePath,
            processStartToken: startTokenAfterPath
        )
    }

    static func processIsAlive(pid: Int) -> Bool {
        errno = 0
        if kill(Int32(pid), 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func resolvedExecutablePath(pid: Int) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        errno = 0
        let result = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        let errorCode = errno
        guard result > 0 else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "実行ファイルパス取得",
                errorCode: errorCode
            )
        }
        return canonicalPath(String(cString: buffer))
    }

    private static func processStartToken(pid: Int) throws -> String {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, pointer, expectedSize)
        }
        let errorCode = errno
        guard result == expectedSize, info.pbi_pid == UInt32(pid) else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "開始時刻取得",
                errorCode: errorCode
            )
        }
        return "pid=\(pid);start=\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
    }

    private static func canonicalPath(_ rawPath: String) -> String {
        let currentDirectoryURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        return URL(fileURLWithPath: rawPath, relativeTo: currentDirectoryURL)
            .absoluteURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}

private enum ProcessIdentityInspectionError: LocalizedError {
    case unavailable(pid: Int, operation: String, errorCode: Int32)
    case changedDuringInspection(pid: Int, initialToken: String, observedToken: String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(pid, operation, errorCode):
            let detail: String
            if errorCode == 0 {
                detail = "errno を取得できませんでした"
            } else {
                detail = "\(String(cString: strerror(errorCode))) (errno=\(errorCode))"
            }
            return "PID \(pid) の \(operation)に失敗しました: \(detail)"
        case let .changedDuringInspection(pid, initialToken, observedToken):
            return "PID \(pid) の同一性確認中に開始トークンが変化しました。initial=\(initialToken), observed=\(observedToken)"
        }
    }
}

private struct CPUSampleReport: Encodable {
    let schemaVersion: Int
    let measurementKind: String
    let measurementScope: String
    let includesEventTapAndPosting: Bool
    let pid: Int
    let processCommand: String
    let expectedExecutablePath: String
    let resolvedExecutablePath: String
    let executableIdentityMatched: Bool
    let processStartToken: String
    let processIdentityStable: Bool
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
    let resolvedExecutablePath: String
    let processStartToken: String
    let executableIdentityMatched: Bool
}

private struct CPUSampleBaseline: Encodable {
    let mode: CPUSampleMode
    let averageLimitPercentOfOneCore: Double
    let passed: Bool
    let failureDescription: String?
}

private enum CPUSampleFormatter {
    static func format(_ report: CPUSampleReport) -> String {
        let failureLine = report.baseline.failureDescription.map {
            "\n不合格理由: \($0)"
        } ?? ""
        return """
        常駐 CPU 使用率サンプル
        スキーマ版: \(report.schemaVersion)
        測定種別: \(report.measurementKind)
        PID: \(report.pid)
        コマンド: \(report.processCommand)
        期待実行ファイル: \(report.expectedExecutablePath)
        解決実行ファイル: \(report.resolvedExecutablePath)
        実行ファイル一致: \(report.executableIdentityMatched ? "はい" : "いいえ")
        開始トークン: \(report.processStartToken)
        実行主体固定: \(report.processIdentityStable ? "はい" : "いいえ")
        サンプル数: \(report.sampleCount)
        要求 duration: \(formatSeconds(report.requestedDurationSeconds)) 秒
        実測 duration: \(formatSeconds(report.actualDurationSeconds)) 秒
        interval: \(formatSeconds(report.sampleIntervalSeconds)) 秒
        平均 CPU: \(formatPercent(report.averagePercentOfOneCore)) % / 1 core
        最大 CPU: \(formatPercent(report.maximumPercentOfOneCore)) % / 1 core
        基準 mode: \(report.baseline.mode.rawValue)
        基準平均 CPU: \(formatPercent(report.baseline.averageLimitPercentOfOneCore)) % / 1 core
        基準判定: \(report.baseline.passed ? "合格" : "不合格")\(failureLine)
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
