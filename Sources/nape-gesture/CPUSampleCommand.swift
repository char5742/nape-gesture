import Darwin
import Foundation

struct CPUSampleCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let configuration = try CPUSampleCommandOptions(options: options)
        let report = try CPUSampler.sample(
            pid: configuration.pid,
            expectedExecutablePath: configuration.expectedExecutablePath,
            duration: configuration.duration,
            interval: configuration.interval,
            mode: configuration.mode,
            readyFilePath: configuration.readyFilePath
        )

        let output: String
        if configuration.outputsJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            output = String(decoding: data, as: UTF8.self) + "\n"
        } else {
            output = CPUSampleFormatter.format(report)
        }

        try write(output, to: configuration.outputPath)

        if configuration.assertsBaseline {
            if report.baseline.passed {
                fputs("常駐 CPU 使用率基準: 合格\n", stderr)
            } else {
                throw CPUSampleBaselineAssertionError(message: report.baseline.failureDescription ?? "CPU 基準を満たしていません。")
            }
        }
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

private struct CPUSampleCommandOptions {
    private static let valueOptionNames: Set<String> = [
        "--pid",
        "--expected-executable",
        "--duration",
        "--interval",
        "--mode",
        "--out",
        "--ready-file"
    ]
    private static let flagOptionNames: Set<String> = [
        "--json",
        "--assert-baseline"
    ]

    let pid: pid_t
    let expectedExecutablePath: String
    let duration: TimeInterval
    let interval: TimeInterval
    let mode: CPUSampleMode
    let outputPath: String?
    let readyFilePath: String?
    let outputsJSON: Bool
    let assertsBaseline: Bool

    init(options: [String]) throws {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var index = 0

        while index < options.count {
            let option = options[index]
            if Self.valueOptionNames.contains(option) {
                guard values[option] == nil else {
                    throw ToolError.invalidValue(option, "重複して指定されています")
                }
                let valueIndex = index + 1
                guard valueIndex < options.count,
                      !options[valueIndex].hasPrefix("--") else {
                    throw ToolError.missingValue(option)
                }
                values[option] = options[valueIndex]
                index += 2
                continue
            }
            if Self.flagOptionNames.contains(option) {
                guard flags.insert(option).inserted else {
                    throw ToolError.invalidValue(option, "重複して指定されています")
                }
                index += 1
                continue
            }
            throw ToolError.invalidValue("sample-cpu option", option)
        }

        let rawPID = try Self.requiredValue("--pid", values: values)
        guard let pid = pid_t(rawPID), pid > 0 else {
            throw ToolError.invalidValue("--pid", rawPID)
        }
        let expectedExecutablePath = try Self.requiredValue(
            "--expected-executable",
            values: values
        )
        let rawDuration = values["--duration"] ?? "30"
        let duration = try Self.positiveFiniteDouble("--duration", raw: rawDuration)
        let rawInterval = values["--interval"] ?? "1"
        let interval = try Self.positiveFiniteDouble("--interval", raw: rawInterval)
        try CPUSampleLimits.validate(
            duration: duration,
            interval: interval,
            rawDuration: rawDuration,
            rawInterval: rawInterval
        )

        let outputPath = values["--out"]
        let readyFilePath = values["--ready-file"]
        if let outputPath, let readyFilePath,
           CPUSamplePathIdentity.mayReferToSameFile(outputPath, readyFilePath) {
            throw ToolError.invalidValue(
                "--ready-file",
                "--out と同じパスは指定できません: \(readyFilePath)"
            )
        }

        self.pid = pid
        self.expectedExecutablePath = expectedExecutablePath
        self.duration = duration
        self.interval = interval
        mode = try CPUSampleMode(raw: values["--mode"] ?? "idle")
        self.outputPath = outputPath
        self.readyFilePath = readyFilePath
        outputsJSON = flags.contains("--json")
        assertsBaseline = flags.contains("--assert-baseline")
    }

    private static func requiredValue(
        _ name: String,
        values: [String: String]
    ) throws -> String {
        guard let value = values[name] else {
            throw ToolError.missingValue(name)
        }
        return value
    }

    private static func positiveFiniteDouble(_ name: String, raw: String) throws -> Double {
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }
}

private enum CPUSamplePathIdentity {
    private static let maximumSymbolicLinkResolutionCount = 64

    static func mayReferToSameFile(_ firstPath: String, _ secondPath: String) -> Bool {
        guard let firstIdentity = conservativeIdentity(firstPath),
              let secondIdentity = conservativeIdentity(secondPath) else {
            return true
        }
        return firstIdentity == secondIdentity
    }

    private static func conservativeIdentity(_ rawPath: String) -> String? {
        guard let resolvedPath = resolvePathComponents(rawPath) else {
            return nil
        }
        return resolvedPath
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static func resolvePathComponents(_ rawPath: String) -> String? {
        var pendingComponents: ArraySlice<String>
        if rawPath.hasPrefix("/") {
            pendingComponents = ArraySlice(pathComponents(rawPath))
        } else {
            pendingComponents = ArraySlice(
                pathComponents(FileManager.default.currentDirectoryPath)
                    + pathComponents(rawPath)
            )
        }

        var resolvedComponents: [String] = []
        var symbolicLinkResolutionCount = 0

        while let component = pendingComponents.first {
            pendingComponents = pendingComponents.dropFirst()

            switch component {
            case ".":
                continue
            case "..":
                if !resolvedComponents.isEmpty {
                    resolvedComponents.removeLast()
                }
                continue
            default:
                break
            }

            let candidatePath = absolutePath(resolvedComponents + [component])
            var fileStatus = stat()
            errno = 0
            if lstat(candidatePath, &fileStatus) == 0 {
                if (fileStatus.st_mode & S_IFMT) == S_IFLNK {
                    guard symbolicLinkResolutionCount < maximumSymbolicLinkResolutionCount,
                          let destination = try? FileManager.default.destinationOfSymbolicLink(
                              atPath: candidatePath
                          ) else {
                        return nil
                    }
                    symbolicLinkResolutionCount += 1
                    if destination.hasPrefix("/") {
                        resolvedComponents.removeAll(keepingCapacity: true)
                    }
                    pendingComponents = ArraySlice(
                        pathComponents(destination) + pendingComponents
                    )
                    continue
                }
            } else if errno != ENOENT && errno != ENOTDIR {
                return nil
            }

            resolvedComponents.append(component)
        }

        return absolutePath(resolvedComponents)
    }

    private static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func absolutePath(_ components: [String]) -> String {
        components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }
}

private enum CPUSampleLimits {
    static let maximumDurationSeconds = 86_400
    static let maximumSampleCount = 100_000

    static func validate(
        duration: TimeInterval,
        interval: TimeInterval,
        rawDuration: String,
        rawInterval: String
    ) throws {
        guard duration <= TimeInterval(maximumDurationSeconds) else {
            throw ToolError.invalidValue(
                "--duration",
                "\(rawDuration)（上限は \(maximumDurationSeconds) 秒です）"
            )
        }

        let ratio = duration / interval
        guard ratio.isFinite else {
            throw ToolError.invalidValue(
                "--duration / --interval",
                "有限な比率ではありません: duration=\(rawDuration), interval=\(rawInterval)"
            )
        }
        let estimatedSampleCount = ceil(ratio) + 1
        guard estimatedSampleCount <= Double(maximumSampleCount) else {
            throw ToolError.invalidValue(
                "--duration / --interval",
                "推定 sample 数が上限 \(maximumSampleCount) を超えます: duration=\(rawDuration), interval=\(rawInterval)"
            )
        }
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
        pid: pid_t,
        expectedExecutablePath rawExpectedExecutablePath: String,
        duration: TimeInterval,
        interval: TimeInterval,
        mode: CPUSampleMode,
        readyFilePath: String?
    ) throws -> CPUSampleReport {
        let expectedExecutablePath = try ProcessIdentityResolver.expectedExecutablePath(
            rawExpectedExecutablePath
        )
        let initialIdentity = try ProcessIdentityResolver.snapshot(pid: pid)
        let command = try processCommand(pid: pid)

        let processInfo = ProcessInfo.processInfo
        let startUptime = processInfo.systemUptime
        let deadlineUptime = startUptime + duration
        var nextSampleUptime = startUptime
        var samples: [CPUSample] = []
        var processExitedEarly = false
        var executableIdentityMatched = initialIdentity.resolvedExecutablePath == expectedExecutablePath
        var processIdentityStable = true
        var resolvedExecutablePath = initialIdentity.resolvedExecutablePath
        var identityFailureDescription: String?
        var requestedDurationReached = false
        var sampleNumber = 0

        if !executableIdentityMatched {
            identityFailureDescription = "指定 PID \(pid) の実行ファイルが期待値と一致しません。expected=\(expectedExecutablePath), resolved=\(initialIdentity.resolvedExecutablePath)"
        }

        while samples.count < CPUSampleLimits.maximumSampleCount {
            guard executableIdentityMatched else {
                break
            }
            sleepUntil(nextSampleUptime, processInfo: processInfo)
            sampleNumber += 1

            guard let identityBeforeSample = inspectIdentity(
                pid: pid,
                expectedExecutablePath: expectedExecutablePath,
                initialIdentity: initialIdentity,
                sampleNumber: sampleNumber,
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
                identityFailureDescription = "sample \(sampleNumber) の CPU 使用率を取得できませんでした。対象プロセスが終了したか PID が再利用された可能性があります。"
                break
            }

            guard let identityAfterSample = inspectIdentity(
                pid: pid,
                expectedExecutablePath: expectedExecutablePath,
                initialIdentity: initialIdentity,
                sampleNumber: sampleNumber,
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
                    sampleNumber: sampleNumber,
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
                    processIDVersion: identityAfterSample.processIDVersion,
                    executableIdentityMatched: true
                )
            )

            if samples.count == 1 {
                try CPUSampleReadyFileWriter.write(
                    path: readyFilePath,
                    pid: pid,
                    identity: identityAfterSample,
                    completedSampleCount: samples.count
                )
            }

            let sampleCompletedUptime = processInfo.systemUptime
            let elapsedUptime = max(0, sampleCompletedUptime - startUptime)
            if samples.count >= 2,
               sampleCompletedUptime >= deadlineUptime,
               elapsedUptime >= duration {
                requestedDurationReached = true
                break
            }
            nextSampleUptime = min(sampleCompletedUptime + interval, deadlineUptime)
        }

        let actualDuration = max(0, processInfo.systemUptime - startUptime)
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
                && requestedDurationReached
                && actualDuration >= duration
                && average <= mode.averageLimitPercentOfOneCore,
            failureDescription: failureDescription(
                mode: mode,
                average: average,
                samples: samples,
                processExitedEarly: processExitedEarly,
                identityFailureDescription: identityFailureDescription,
                requestedDuration: duration,
                actualDuration: actualDuration,
                requestedDurationReached: requestedDurationReached
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
            processIDVersion: initialIdentity.processIDVersion,
            processIdentityStable: processIdentityStable,
            requestedDurationSeconds: duration,
            sampleIntervalSeconds: interval,
            actualDurationSeconds: actualDuration,
            requestedDurationReached: requestedDurationReached,
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
        identityFailureDescription: String?,
        requestedDuration: TimeInterval,
        actualDuration: TimeInterval,
        requestedDurationReached: Bool
    ) -> String? {
        var failures: [String] = []
        if let identityFailureDescription {
            failures.append(identityFailureDescription)
        }
        if samples.isEmpty {
            failures.append("CPU 使用率サンプルがありません。PID とプロセス寿命を確認してください。")
        }
        if processExitedEarly, identityFailureDescription == nil {
            failures.append("測定中に対象プロセスが終了しました。常駐 CPU 証跡として採用できません。")
        }
        if !requestedDurationReached {
            failures.append(
                "要求 duration \(format(requestedDuration)) 秒の deadline 到達後に最終 sample を採取できませんでした。actual=\(format(actualDuration)) 秒"
            )
        }
        if average > mode.averageLimitPercentOfOneCore {
            failures.append(
                "\(mode.description) 平均 CPU 使用率 \(format(average))% が基準 \(format(mode.averageLimitPercentOfOneCore))% を超えています。"
            )
        }
        return failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private static func sleepUntil(
        _ deadlineUptime: TimeInterval,
        processInfo: ProcessInfo
    ) {
        while true {
            let remaining = deadlineUptime - processInfo.systemUptime
            guard remaining > 0 else {
                return
            }
            Thread.sleep(forTimeInterval: remaining)
        }
    }

    private static func inspectIdentity(
        pid: pid_t,
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
        pid: pid_t,
        sampleNumber: Int,
        phase: String,
        expectedExecutablePath: String,
        initialIdentity: ProcessIdentitySnapshot,
        observedIdentity: ProcessIdentitySnapshot
    ) -> String {
        if observedIdentity.processStartToken != initialIdentity.processStartToken {
            return "sample \(sampleNumber) \(phase)に PID \(pid) の開始トークンが変化しました。PID 再利用の可能性があるため証跡として採用できません。initial=\(initialIdentity.processStartToken), observed=\(observedIdentity.processStartToken)"
        }
        if observedIdentity.processIDVersion != initialIdentity.processIDVersion {
            return "sample \(sampleNumber) \(phase)に PID \(pid) の pidversion が変化しました。同一 PID で exec または posix_spawn が発生したため証跡として採用できません。initial=\(initialIdentity.processIDVersion), observed=\(observedIdentity.processIDVersion)"
        }
        return "sample \(sampleNumber) \(phase)に PID \(pid) の実行ファイルパスが変化しました。expected=\(expectedExecutablePath), resolved=\(observedIdentity.resolvedExecutablePath)"
    }

    private static func cpuPercent(pid: pid_t) throws -> Double? {
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

    private static func processCommand(pid: pid_t) throws -> String {
        let output = try runPS(pid: pid, column: "comm=")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.invalidValue("--pid", "プロセスが見つかりません: \(pid)")
        }
        return trimmed
    }

    private static func runPS(pid: pid_t, column: String) throws -> String {
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
    let processIDVersion: Int32
}

private enum CPUSampleReadyFileWriter {
    static func write(
        path: String?,
        pid: pid_t,
        identity: ProcessIdentitySnapshot,
        completedSampleCount: Int
    ) throws {
        guard let path else {
            return
        }

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let record = CPUSampleReadyRecord(
            schemaVersion: 1,
            ready: true,
            pid: pid,
            processStartToken: identity.processStartToken,
            processIDVersion: identity.processIDVersion,
            resolvedExecutablePath: identity.resolvedExecutablePath,
            completedSampleCount: completedSampleCount,
            timestampUnixSeconds: Date().timeIntervalSince1970
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try data.write(to: temporaryURL, options: .atomic)
        errno = 0
        let result = temporaryURL.path.withCString { sourcePath in
            url.path.withCString { destinationPath in
                renamex_np(
                    sourcePath,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        let errorCode = errno
        guard result == 0 else {
            if errorCode == EEXIST {
                throw ToolError.invalidValue(
                    "--ready-file",
                    "既に存在するため排他的に公開できません: \(path)"
                )
            }
            throw CPUSampleReadyFilePublicationError(
                path: path,
                errorCode: errorCode
            )
        }
    }
}

private struct CPUSampleReadyRecord: Encodable {
    let schemaVersion: Int
    let ready: Bool
    let pid: pid_t
    let processStartToken: String
    let processIDVersion: Int32
    let resolvedExecutablePath: String
    let completedSampleCount: Int
    let timestampUnixSeconds: Double
}

private struct CPUSampleReadyFilePublicationError: LocalizedError {
    let path: String
    let errorCode: Int32

    var errorDescription: String? {
        let detail: String
        if errorCode == 0 {
            detail = "errno を取得できませんでした"
        } else {
            detail = "\(String(cString: strerror(errorCode))) (errno=\(errorCode))"
        }
        return "ready-file を排他的に公開できませんでした: \(path): \(detail)"
    }
}

private struct ProcessAuditIdentity: Equatable {
    let pid: pid_t
    let processIDVersion: Int32
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

    static func snapshot(pid: pid_t) throws -> ProcessIdentitySnapshot {
        let auditIdentityBeforePath = try processAuditIdentity(pid: pid)
        let startTokenBeforePath = try processStartToken(pid: pid)
        let executablePath = try resolvedExecutablePath(pid: pid)
        let startTokenAfterPath = try processStartToken(pid: pid)
        let auditIdentityAfterPath = try processAuditIdentity(pid: pid)

        guard startTokenBeforePath == startTokenAfterPath else {
            throw ProcessIdentityInspectionError.startTokenChangedDuringInspection(
                pid: pid,
                initialToken: startTokenBeforePath,
                observedToken: startTokenAfterPath
            )
        }
        guard auditIdentityBeforePath.processIDVersion == auditIdentityAfterPath.processIDVersion else {
            throw ProcessIdentityInspectionError.processIDVersionChangedDuringInspection(
                pid: pid,
                initialVersion: auditIdentityBeforePath.processIDVersion,
                observedVersion: auditIdentityAfterPath.processIDVersion
            )
        }

        return ProcessIdentitySnapshot(
            resolvedExecutablePath: executablePath,
            processStartToken: startTokenAfterPath,
            processIDVersion: auditIdentityAfterPath.processIDVersion
        )
    }

    static func processIsAlive(pid: pid_t) -> Bool {
        errno = 0
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func processAuditIdentity(pid: pid_t) throws -> ProcessAuditIdentity {
        let selfTask = mach_task_self_
        var taskPort: mach_port_name_t = 0
        let taskNameResult = task_name_for_pid(selfTask, pid, &taskPort)
        defer {
            if taskPort != 0 {
                _ = mach_port_deallocate(selfTask, taskPort)
            }
        }

        guard taskNameResult == KERN_SUCCESS else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "audit token 用 task port 取得",
                detail: machErrorDetail(taskNameResult)
            )
        }
        guard taskPort != 0 else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "audit token 用 task port 取得",
                detail: "MACH_PORT_NULL が返されました"
            )
        }

        var auditToken = audit_token_t()
        let expectedCount = mach_msg_type_number_t(
            MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size
        )
        var count = expectedCount
        let taskInfoResult = withUnsafeMutablePointer(to: &auditToken) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(expectedCount)) { infoPointer in
                task_info(
                    taskPort,
                    task_flavor_t(TASK_AUDIT_TOKEN),
                    infoPointer,
                    &count
                )
            }
        }
        guard taskInfoResult == KERN_SUCCESS else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "audit token 取得",
                detail: machErrorDetail(taskInfoResult)
            )
        }
        guard count == expectedCount else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "audit token 取得",
                detail: "返却要素数が不正です: expected=\(expectedCount), actual=\(count)"
            )
        }

        let observedPID = audit_token_to_pid(auditToken)
        guard observedPID == pid else {
            throw ProcessIdentityInspectionError.auditTokenPIDMismatch(
                requestedPID: pid,
                observedPID: observedPID
            )
        }
        return ProcessAuditIdentity(
            pid: observedPID,
            processIDVersion: audit_token_to_pidversion(auditToken)
        )
    }

    private static func resolvedExecutablePath(pid: pid_t) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        errno = 0
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let errorCode = errno
        guard result > 0 else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "実行ファイルパス取得",
                detail: posixErrorDetail(errorCode)
            )
        }
        return canonicalPath(String(cString: buffer))
    }

    private static func processStartToken(pid: pid_t) throws -> String {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, expectedSize)
        }
        let errorCode = errno
        guard result == expectedSize, info.pbi_pid == UInt32(bitPattern: pid) else {
            throw ProcessIdentityInspectionError.unavailable(
                pid: pid,
                operation: "開始時刻取得",
                detail: posixErrorDetail(errorCode)
            )
        }
        return "pid=\(pid);start=\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
    }

    private static func posixErrorDetail(_ errorCode: Int32) -> String {
        guard errorCode != 0 else {
            return "errno を取得できませんでした"
        }
        return "\(String(cString: strerror(errorCode))) (errno=\(errorCode))"
    }

    private static func machErrorDetail(_ result: kern_return_t) -> String {
        guard let message = mach_error_string(result) else {
            return "kern_return=\(result)"
        }
        return "\(String(cString: message)) (kern_return=\(result))"
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
    case unavailable(pid: pid_t, operation: String, detail: String)
    case auditTokenPIDMismatch(requestedPID: pid_t, observedPID: pid_t)
    case startTokenChangedDuringInspection(pid: pid_t, initialToken: String, observedToken: String)
    case processIDVersionChangedDuringInspection(pid: pid_t, initialVersion: Int32, observedVersion: Int32)

    var errorDescription: String? {
        switch self {
        case let .unavailable(pid, operation, detail):
            return "PID \(pid) の \(operation)に失敗しました: \(detail)"
        case let .auditTokenPIDMismatch(requestedPID, observedPID):
            return "PID \(requestedPID) の audit token が別 PID を示しました。observed=\(observedPID)"
        case let .startTokenChangedDuringInspection(pid, initialToken, observedToken):
            return "PID \(pid) の同一性確認中に開始トークンが変化しました。initial=\(initialToken), observed=\(observedToken)"
        case let .processIDVersionChangedDuringInspection(pid, initialVersion, observedVersion):
            return "PID \(pid) の同一性確認中に pidversion が変化しました。exec または posix_spawn が発生しました。initial=\(initialVersion), observed=\(observedVersion)"
        }
    }
}

private struct CPUSampleReport: Encodable {
    let schemaVersion: Int
    let measurementKind: String
    let measurementScope: String
    let includesEventTapAndPosting: Bool
    let pid: pid_t
    let processCommand: String
    let expectedExecutablePath: String
    let resolvedExecutablePath: String
    let executableIdentityMatched: Bool
    let processStartToken: String
    let processIDVersion: Int32
    let processIdentityStable: Bool
    let requestedDurationSeconds: Double
    let sampleIntervalSeconds: Double
    let actualDurationSeconds: Double
    let requestedDurationReached: Bool
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
    let processIDVersion: Int32
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
        pidversion: \(report.processIDVersion)
        実行主体固定: \(report.processIdentityStable ? "はい" : "いいえ")
        サンプル数: \(report.sampleCount)
        要求 duration: \(formatSeconds(report.requestedDurationSeconds)) 秒
        実測 duration: \(formatSeconds(report.actualDurationSeconds)) 秒
        duration 到達後 sample: \(report.requestedDurationReached ? "はい" : "いいえ")
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
