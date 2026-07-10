import Foundation

#if !GENERATE_SCROLL_POST_RESULT_TESTING
import CoreGraphics
import NapeGestureCore

struct GenerateScrollCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        try validateOptions()

        let deltaX = try doubleValue(for: "--x", defaultValue: 0)
        let deltaY = try doubleValue(for: "--y", defaultValue: 0)
        let steps = try intValue(for: "--steps", defaultValue: 1)
        let interval = try doubleValue(for: "--interval", defaultValue: 0.008)
        let phaseOverride = try phaseValue()
        let momentumSteps = try intValue(for: "--momentum-steps", defaultValue: 0)
        let momentumDecay = try doubleValue(for: "--momentum-decay", defaultValue: 0.85)
        let momentumScale = try doubleValue(for: "--momentum-scale", defaultValue: 1.0)
        let mode = try scrollModeValue()
        let axDelivery = try axDeliveryValue()
        let targetProcessID = try targetProcessIDValue()
        let isDryRun = options.contains("--dry-run")
        let outputLogJSON = options.contains("--log-json")

        guard steps > 0 else {
            throw ToolError.invalidValue("--steps", String(steps))
        }
        guard interval.isFinite, interval > 0 else {
            throw ToolError.invalidValue("--interval", String(interval))
        }
        guard momentumSteps >= 0 else {
            throw ToolError.invalidValue("--momentum-steps", String(momentumSteps))
        }
        guard momentumDecay.isFinite, (0...1).contains(momentumDecay) else {
            throw ToolError.invalidValue("--momentum-decay", String(momentumDecay))
        }
        guard momentumScale.isFinite, momentumScale >= 0 else {
            throw ToolError.invalidValue("--momentum-scale", String(momentumScale))
        }
        guard deltaX.isFinite else {
            throw ToolError.invalidValue("--x", String(deltaX))
        }
        guard deltaY.isFinite else {
            throw ToolError.invalidValue("--y", String(deltaY))
        }

        let makeCommands: (TimeInterval) throws -> [GestureCommand] = { startTime in
            let commands = ScrollGenerationPlanner.makeCommands(
                deltaX: deltaX,
                deltaY: deltaY,
                steps: steps,
                interval: interval,
                phaseOverride: phaseOverride,
                momentumSteps: momentumSteps,
                momentumDecay: momentumDecay,
                momentumScale: momentumScale,
                startTime: startTime
            )
            guard !commands.isEmpty else {
                throw ToolError.invalidValue(
                    "generate-scroll",
                    "派生イベントが有限値ではない、timestampを起動後nanosecondsへ変換できない、または生成上限 \(ScrollGenerationPlanner.maximumCommandCount) 件を超えています。"
                )
            }
            return commands
        }

        if isDryRun {
            let commands = try makeCommands(MonotonicEventClock.nowSeconds)
            if outputLogJSON {
                try printInputLog(commands, mode: mode)
            } else {
                try printPlan(commands, mode: mode)
            }
            return
        }

        if outputLogJSON {
            throw ToolError.invalidValue("--log-json", "実イベント投稿時には使用できません。--dry-run と併用してください。")
        }

        try AccessibilityPermission.ensurePrompted()
        let commands = try makeCommands(MonotonicEventClock.nowSeconds)
        let poster = EventPoster()

        switch axDelivery {
        case .synchronous:
            try postSynchronously(
                commands,
                poster: poster,
                mode: mode,
                targetProcessID: targetProcessID,
                interval: interval
            )
        case .asynchronous:
            try postAsynchronously(
                commands,
                poster: poster,
                mode: mode,
                targetProcessID: targetProcessID,
                interval: interval
            )
        }
    }

    private func postSynchronously(
        _ commands: [GestureCommand],
        poster: EventPoster,
        mode: ScrollPostMode,
        targetProcessID: pid_t?,
        interval: TimeInterval
    ) throws {
        for (index, command) in commands.enumerated() {
            let result = poster.postScroll(
                command: command,
                mode: mode,
                axDelivery: .synchronous,
                targetProcessOverride: targetProcessID
            )
            let snapshot = GenerateScrollPostResultSnapshot(result)
            if let failure = snapshot.completedFailureDescription {
                throw postingError(["\(index + 1)件目: \(failure)"])
            }
            if index < commands.count - 1 {
                Thread.sleep(forTimeInterval: interval)
            }
        }
    }

    private func postAsynchronously(
        _ commands: [GestureCommand],
        poster: EventPoster,
        mode: ScrollPostMode,
        targetProcessID: pid_t?,
        interval: TimeInterval
    ) throws {
        let collector = GenerateScrollPostCompletionCollector()
        var expectedCompletionIndexes: Set<Int> = []
        var failures: [String] = []
        var submittedCommandCount = 0

        for (index, command) in commands.enumerated() {
            let result = poster.postScroll(
                command: command,
                mode: mode,
                axDelivery: .asynchronous,
                targetProcessOverride: targetProcessID
            ) { completion in
                collector.recordCompletion(
                    index: index,
                    result: GenerateScrollPostResultSnapshot(completion.postResult)
                )
            }
            let snapshot = GenerateScrollPostResultSnapshot(result)
            submittedCommandCount += 1

            if snapshot.deliveryDeferred {
                expectedCompletionIndexes.insert(index)
                if let failure = snapshot.submissionFailureDescription {
                    failures.append("\(index + 1)件目: deferred受付結果が不正です: \(failure)")
                }
            } else if let failure = snapshot.completedFailureDescription {
                failures.append("\(index + 1)件目: 非deferred投稿が失敗しました: \(failure)")
            }
            if !failures.isEmpty {
                break
            }
            if index < commands.count - 1 {
                Thread.sleep(forTimeInterval: interval)
            }
        }

        poster.waitForPendingAXScroll()

        failures.append(contentsOf: collector.validationFailures(
            expectedCommandIndexes: expectedCompletionIndexes
        ))
        if submittedCommandCount != commands.count {
            failures.append(
                "投稿失敗後に未投稿のコマンドがあります: submitted=\(submittedCommandCount) planned=\(commands.count)"
            )
        }
        guard failures.isEmpty else {
            throw postingError(failures)
        }
    }

    private func postingError(_ failures: [String]) -> ToolError {
        ToolError.invalidValue("generate-scroll posting", failures.joined(separator: "; "))
    }

    private func validateOptions() throws {
        let valueOptions: Set<String> = [
            "--x",
            "--y",
            "--steps",
            "--interval",
            "--phase",
            "--momentum-steps",
            "--momentum-decay",
            "--momentum-scale",
            "--mode",
            "--ax-delivery",
            "--post-to-pid"
        ]
        let flagOptions: Set<String> = ["--dry-run", "--log-json", "--json"]
        var seen: Set<String> = []
        var index = options.startIndex

        while index < options.endIndex {
            let option = options[index]
            guard valueOptions.contains(option) || flagOptions.contains(option) else {
                if option.hasPrefix("-") {
                    throw ToolError.invalidValue("generate-scroll option", "未知の option です: \(option)")
                }
                throw ToolError.invalidValue("generate-scroll positional argument", option)
            }
            guard seen.insert(option).inserted else {
                throw ToolError.invalidValue(option, "同じ option は複数回指定できません。")
            }

            index = options.index(after: index)
            guard valueOptions.contains(option) else {
                continue
            }
            guard index < options.endIndex, !options[index].hasPrefix("--") else {
                throw ToolError.missingValue(option)
            }
            index = options.index(after: index)
        }
    }

    private func doubleValue(for name: String, defaultValue: Double) throws -> Double {
        guard let index = options.firstIndex(of: name) else {
            return defaultValue
        }
        let valueIndex = options.index(after: index)
        guard valueIndex < options.endIndex else {
            throw ToolError.missingValue(name)
        }
        guard let value = Double(options[valueIndex]) else {
            throw ToolError.invalidValue(name, options[valueIndex])
        }
        return value
    }

    private func intValue(for name: String, defaultValue: Int) throws -> Int {
        guard let index = options.firstIndex(of: name) else {
            return defaultValue
        }
        let valueIndex = options.index(after: index)
        guard valueIndex < options.endIndex else {
            throw ToolError.missingValue(name)
        }
        guard let value = Int(options[valueIndex]) else {
            throw ToolError.invalidValue(name, options[valueIndex])
        }
        return value
    }

    private func phaseValue() throws -> GesturePhase? {
        guard let raw = SettingsStore.value(for: "--phase", in: options) else {
            return nil
        }
        guard raw != "auto" else {
            return nil
        }
        guard let phase = GesturePhase(rawValue: raw) else {
            throw ToolError.invalidValue("--phase", raw)
        }
        return phase
    }

    private func scrollModeValue() throws -> ScrollPostMode {
        guard let raw = SettingsStore.value(for: "--mode", in: options) else {
            return .free
        }

        switch raw {
        case "free":
            return .free
        case "horizontal":
            return .horizontal
        case "space-left":
            return .forcedHorizontal(sign: -1)
        case "space-right":
            return .forcedHorizontal(sign: 1)
        default:
            throw ToolError.invalidValue("--mode", raw)
        }
    }

    private func axDeliveryValue() throws -> AXScrollDelivery {
        guard let raw = SettingsStore.value(for: "--ax-delivery", in: options) else {
            return .synchronous
        }

        switch raw {
        case "sync", "synchronous":
            return .synchronous
        case "async", "asynchronous":
            return .asynchronous
        default:
            throw ToolError.invalidValue("--ax-delivery", raw)
        }
    }

    private func targetProcessIDValue() throws -> pid_t? {
        guard let raw = SettingsStore.value(for: "--post-to-pid", in: options) else {
            return nil
        }
        guard let value = Int(raw), (1...Int(Int32.max)).contains(value) else {
            throw ToolError.invalidValue("--post-to-pid", raw)
        }
        return pid_t(value)
    }

    private func printPlan(_ commands: [GestureCommand], mode: ScrollPostMode) throws {
        let preview = commands.enumerated().map { index, command in
            let posted = mode.deltas(for: command)
            return ScrollCommandPreview(
                index: index + 1,
                kind: command.kind,
                phase: command.phase,
                commandDeltaX: command.deltaX,
                commandDeltaY: command.deltaY,
                postedDeltaX: posted.x,
                postedDeltaY: posted.y,
                velocityX: command.velocityX,
                velocityY: command.velocityY,
                timestamp: command.timestamp
            )
        }

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preview)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        for item in preview {
            print(
                "\(item.index): kind=\(item.kind.rawValue) phase=\(item.phase.rawValue) "
                    + "commandDx=\(item.commandDeltaX) commandDy=\(item.commandDeltaY) "
                    + "postedDx=\(item.postedDeltaX) postedDy=\(item.postedDeltaY) "
                    + "vx=\(item.velocityX) vy=\(item.velocityY)"
            )
        }
    }

    private func printInputLog(_ commands: [GestureCommand], mode: ScrollPostMode) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var lines: [String] = []
        lines.reserveCapacity(commands.count)

        for command in commands {
            guard let timestamp = MonotonicEventClock.timestampNanoseconds(
                fromSecondsSinceStartup: command.timestamp
            ) else {
                throw ToolError.invalidValue("timestamp", String(command.timestamp))
            }
            let posted = mode.deltas(for: command)
            let phases = CGEventUtilities.phaseValues(for: command)
            let record = InputLogRecord(
                timestamp: timestamp,
                typeName: "scrollWheel",
                typeRaw: Int(CGEventType.scrollWheel.rawValue),
                generatedByNapeGesture: true,
                buttonNumber: 0,
                deltaX: 0,
                deltaY: 0,
                scrollDeltaX: Int64(quantize(posted.x)),
                scrollDeltaY: Int64(quantize(posted.y)),
                pointDeltaX: posted.x,
                pointDeltaY: posted.y,
                scrollPhase: phases.scroll,
                momentumPhase: phases.momentum,
                isContinuous: 1,
                keyCode: 0,
                flags: 0
            )
            let data = try encoder.encode(record)
            lines.append(String(decoding: data, as: UTF8.self))
        }
        if !lines.isEmpty {
            print(lines.joined(separator: "\n"))
        }
    }

    private func quantize(_ value: Double) -> Int32 {
        let rounded = value.rounded()
        if rounded > Double(Int32.max) {
            return Int32.max
        }
        if rounded < Double(Int32.min) {
            return Int32.min
        }
        return Int32(rounded)
    }
}

private struct ScrollCommandPreview: Codable {
    var index: Int
    var kind: GestureCommandKind
    var phase: GesturePhase
    var commandDeltaX: Double
    var commandDeltaY: Double
    var postedDeltaX: Double
    var postedDeltaY: Double
    var velocityX: Double
    var velocityY: Double
    var timestamp: TimeInterval
}
#endif

struct GenerateScrollPostResultSnapshot: Equatable {
    var generatedEventCount: Int
    var failedEventCreationCount: Int
    var deliveryDeferred: Bool

    var submissionFailureDescription: String? {
        if failedEventCreationCount != 0 {
            return "イベント作成失敗数が0ではありません: \(failedEventCreationCount)"
        }
        if generatedEventCount <= 0 {
            return "deferred受付時の生成イベント数が1以上ではありません: \(generatedEventCount)"
        }
        return nil
    }

    var completedFailureDescription: String? {
        if deliveryDeferred {
            return "配送完了結果が deferred のままです"
        }
        if failedEventCreationCount != 0 {
            return "イベント作成失敗数が0ではありません: \(failedEventCreationCount)"
        }
        if generatedEventCount < 0 {
            return "生成イベント数が負数です: \(generatedEventCount)"
        }
        return nil
    }
}

final class GenerateScrollPostCompletionCollector {
    private let lock = NSLock()
    private var completions: [Int: [GenerateScrollPostResultSnapshot]] = [:]

    func recordCompletion(index: Int, result: GenerateScrollPostResultSnapshot) {
        lock.lock()
        completions[index, default: []].append(result)
        lock.unlock()
    }

    func validationFailures(expectedCommandIndexes: Set<Int>) -> [String] {
        lock.lock()
        let completions = self.completions
        lock.unlock()

        var failures: [String] = []
        for index in expectedCommandIndexes.sorted() {
            let position = index + 1
            let completionResults = completions[index] ?? []
            if completionResults.isEmpty {
                failures.append("\(position)件目: async completion がありません")
            } else if completionResults.count > 1 {
                failures.append("\(position)件目: async completion が重複しています: \(completionResults.count)件")
            } else if let failure = completionResults[0].completedFailureDescription {
                failures.append("\(position)件目: async completion が失敗しました: \(failure)")
            }
        }

        let unexpectedIndexes = Set(completions.keys)
            .subtracting(expectedCommandIndexes)
            .sorted()
        for index in unexpectedIndexes {
            let completionCount = completions[index]?.count ?? 0
            if index >= 0 {
                failures.append(
                    "\(index + 1)件目: 非deferred投稿に completion があります: \(completionCount)件"
                )
            } else {
                failures.append("範囲外の completion があります: index=\(index)")
            }
        }
        return failures
    }
}

#if !GENERATE_SCROLL_POST_RESULT_TESTING
private extension GenerateScrollPostResultSnapshot {
    init(_ result: EventPostResult) {
        self.init(
            generatedEventCount: result.generatedEventCount,
            failedEventCreationCount: result.failedEventCreationCount,
            deliveryDeferred: result.deliveryDeferred
        )
    }
}
#endif
