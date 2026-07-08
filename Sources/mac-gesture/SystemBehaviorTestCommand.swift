import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MacGestureCore

struct SystemBehaviorTestCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let subcommand = options.first ?? "list"
        let rest = Array(options.dropFirst())

        switch subcommand {
        case "list":
            printScenarios()
        case "run":
            try runScenario(options: rest)
        default:
            throw ToolError.unknownCommand("system-test \(subcommand)")
        }
    }

    private func printScenarios() {
        print(
            """
            system-test scenarios

              space-left
                  水平ピクセルスクロールを左Spaces方向として連続生成します。

              space-right
                  水平ピクセルスクロールを右Spaces方向として連続生成します。

              mission-control
                  Mission Control相当のアクションを生成します。

              page-back
                  ページ戻る相当のアクションを生成します。

              page-forward
                  ページ進む相当のアクションを生成します。

              zoom-in
                  ズームイン相当のアクションを生成します。

              zoom-out
                  ズームアウト相当のアクションを生成します。

            例:
              mac-gesture system-test run --scenario space-left --target finder --amount 1800 --steps 36
              mac-gesture system-test run --scenario mission-control --dry-run
            """
        )
    }

    private func runScenario(options: [String]) throws {
        let scenario = try requiredValue("--scenario", in: options)
        let target = value("--target", in: options)
        let dryRun = options.contains("--dry-run")
        let outputLogJSON = options.contains("--log-json")
        let outputPath = value("--out", in: options)
        let amount = try doubleValue("--amount", in: options, defaultValue: 1600)
        let steps = try intValue("--steps", in: options, defaultValue: 32)
        let interval = try doubleValue("--interval", in: options, defaultValue: 0.008)
        let plan = try SystemTestPlan(
            scenario: scenario,
            target: target,
            amount: amount,
            steps: steps,
            interval: interval
        )

        if outputLogJSON {
            guard dryRun else {
                throw ToolError.invalidValue("--log-json", "--dry-run と併用してください。")
            }
            try writeLogJSON(for: plan, to: outputPath)
            return
        }

        if let outputPath {
            throw ToolError.invalidValue("--out", "--log-json と併用してください: \(outputPath)")
        }

        print(plan.description)
        if dryRun {
            print("dry-run のためイベントは生成しません。")
            return
        }

        try AccessibilityPermission.ensurePrompted()
        try activateTargetIfNeeded(plan.target)
        Thread.sleep(forTimeInterval: 0.5)
        try execute(plan)
        print("シナリオを実行しました。`mac-gesture log` または画面挙動で差分を確認してください。")
    }

    private func execute(_ plan: SystemTestPlan) throws {
        let poster = EventPoster()
        let now = Date().timeIntervalSince1970

        switch plan.scenario {
        case .spaceLeft:
            postHorizontalCommands(makeHorizontalCommands(sign: -1, plan: plan, now: now), poster: poster, interval: plan.interval)
        case .spaceRight:
            postHorizontalCommands(makeHorizontalCommands(sign: 1, plan: plan, now: now), poster: poster, interval: plan.interval)
        case .missionControl:
            poster.postMissionControl()
        case .pageBack:
            poster.postPageBack()
        case .pageForward:
            poster.postPageForward()
        case .zoomIn:
            poster.postZoomIn()
        case .zoomOut:
            poster.postZoomOut()
        }
    }

    private func makeHorizontalCommands(
        sign: Int,
        plan: SystemTestPlan,
        now: TimeInterval
    ) -> [GestureCommand] {
        let perStep = plan.amount / Double(plan.steps)
        var commands: [GestureCommand] = []

        for index in 0..<plan.steps {
            let phase: GesturePhase
            if index == 0 {
                phase = .began
            } else if index == plan.steps - 1 {
                phase = .ended
            } else {
                phase = .changed
            }

            let command = GestureCommand(
                kind: .drag,
                phase: phase,
                direction: sign < 0 ? .left : .right,
                deltaX: Double(sign) * perStep,
                deltaY: 0,
                velocityX: Double(sign) * perStep / max(plan.interval, 0.001),
                velocityY: 0,
                timestamp: now + Double(index) * plan.interval
            )

            commands.append(command)
        }

        return commands
    }

    private func postHorizontalCommands(_ commands: [GestureCommand], poster: EventPoster, interval: TimeInterval) {
        for command in commands {
            poster.postScroll(command: command, mode: .free)
            Thread.sleep(forTimeInterval: interval)
        }
    }

    private func writeLogJSON(for plan: SystemTestPlan, to outputPath: String?) throws {
        let records = logRecords(for: plan, startTime: Date().timeIntervalSince1970)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = records.compactMap { record -> String? in
            guard let data = try? encoder.encode(record) else {
                return nil
            }
            return String(decoding: data, as: UTF8.self)
        }
        let output = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")

        if let outputPath {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try output.write(to: url, atomically: true, encoding: .utf8)
            fputs("system-test JSON Linesを書き出しました: \(outputPath)\n", stderr)
        } else {
            print(output, terminator: "")
        }
    }

    private func logRecords(for plan: SystemTestPlan, startTime: TimeInterval) -> [InputLogRecord] {
        switch plan.scenario {
        case .spaceLeft:
            return makeHorizontalCommands(sign: -1, plan: plan, now: startTime)
                .map { scrollRecord(command: $0, mode: .free) }
        case .spaceRight:
            return makeHorizontalCommands(sign: 1, plan: plan, now: startTime)
                .map { scrollRecord(command: $0, mode: .free) }
        case .missionControl:
            return shortcutRecords(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl, startTime: startTime)
        case .pageBack:
            return shortcutRecords(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand, startTime: startTime)
        case .pageForward:
            return shortcutRecords(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand, startTime: startTime)
        case .zoomIn:
            return shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand, startTime: startTime)
        case .zoomOut:
            return shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand, startTime: startTime)
        }
    }

    private func scrollRecord(command: GestureCommand, mode: ScrollPostMode) -> InputLogRecord {
        let posted = mode.deltas(for: command)
        let phases = CGEventUtilities.phaseValues(for: command)
        return InputLogRecord(
            timestamp: timestamp(command.timestamp),
            typeName: "scrollWheel",
            typeRaw: Int(CGEventType.scrollWheel.rawValue),
            generatedByMacGesture: true,
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
    }

    private func shortcutRecords(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        startTime: TimeInterval
    ) -> [InputLogRecord] {
        [
            keyRecord(typeName: "keyDown", type: .keyDown, keyCode: keyCode, flags: flags, time: startTime),
            keyRecord(typeName: "keyUp", type: .keyUp, keyCode: keyCode, flags: flags, time: startTime + 0.01)
        ]
    }

    private func keyRecord(
        typeName: String,
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        time: TimeInterval
    ) -> InputLogRecord {
        InputLogRecord(
            timestamp: timestamp(time),
            typeName: typeName,
            typeRaw: Int(type.rawValue),
            generatedByMacGesture: true,
            buttonNumber: 0,
            deltaX: 0,
            deltaY: 0,
            scrollDeltaX: 0,
            scrollDeltaY: 0,
            pointDeltaX: 0,
            pointDeltaY: 0,
            scrollPhase: 0,
            momentumPhase: 0,
            isContinuous: 0,
            keyCode: Int64(keyCode),
            flags: flags.rawValue
        )
    }

    private func timestamp(_ time: TimeInterval) -> UInt64 {
        UInt64(max(time, 0) * 1_000_000_000)
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

    private func activateTargetIfNeeded(_ target: SystemTestTarget?) throws {
        guard let target else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        switch target {
        case .finder:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
                throw ToolError.targetApplicationNotFound("Finder")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case .safari:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
                throw ToolError.targetApplicationNotFound("Safari")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    private func value(_ name: String, in options: [String]) -> String? {
        SettingsStore.value(for: name, in: options)
    }

    private func requiredValue(_ name: String, in options: [String]) throws -> String {
        try SettingsStore.requiredValue(for: name, in: options)
    }

    private func doubleValue(_ name: String, in options: [String], defaultValue: Double) throws -> Double {
        guard options.contains(name) else {
            return defaultValue
        }
        let raw = try requiredValue(name, in: options)
        guard let value = Double(raw), value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func intValue(_ name: String, in options: [String], defaultValue: Int) throws -> Int {
        guard options.contains(name) else {
            return defaultValue
        }
        let raw = try requiredValue(name, in: options)
        guard let value = Int(raw), value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }
}

private struct SystemTestPlan {
    var scenario: SystemTestScenario
    var target: SystemTestTarget?
    var amount: Double
    var steps: Int
    var interval: TimeInterval

    init(
        scenario: String,
        target: String?,
        amount: Double,
        steps: Int,
        interval: TimeInterval
    ) throws {
        guard let scenario = SystemTestScenario(rawValue: scenario) else {
            throw ToolError.invalidValue("--scenario", scenario)
        }
        self.scenario = scenario

        if let target {
            guard let parsedTarget = SystemTestTarget(rawValue: target) else {
                throw ToolError.invalidValue("--target", target)
            }
            self.target = parsedTarget
        } else {
            self.target = nil
        }

        self.amount = amount
        self.steps = steps
        self.interval = interval
    }

    var description: String {
        [
            "system-test plan",
            "scenario=\(scenario.rawValue)",
            "target=\(target?.rawValue ?? "none")",
            "amount=\(amount)",
            "steps=\(steps)",
            "interval=\(interval)"
        ].joined(separator: "\n")
    }
}

private enum SystemTestScenario: String {
    case spaceLeft = "space-left"
    case spaceRight = "space-right"
    case missionControl = "mission-control"
    case pageBack = "page-back"
    case pageForward = "page-forward"
    case zoomIn = "zoom-in"
    case zoomOut = "zoom-out"
}

private enum SystemTestTarget: String {
    case finder
    case safari
}
