import CoreGraphics
import Foundation
import NapeGestureCore

struct GenerateScrollCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let deltaX = try doubleValue(for: "--x", defaultValue: 0)
        let deltaY = try doubleValue(for: "--y", defaultValue: 0)
        let steps = try intValue(for: "--steps", defaultValue: 1)
        let interval = try doubleValue(for: "--interval", defaultValue: 0.008)
        let phaseOverride = try phaseValue()
        let momentumSteps = try intValue(for: "--momentum-steps", defaultValue: 0)
        let momentumDecay = try doubleValue(for: "--momentum-decay", defaultValue: 0.85)
        let momentumScale = try doubleValue(for: "--momentum-scale", defaultValue: 1.0)
        let mode = try scrollModeValue()
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

        let commands = ScrollGenerationPlanner.makeCommands(
            deltaX: deltaX,
            deltaY: deltaY,
            steps: steps,
            interval: interval,
            phaseOverride: phaseOverride,
            momentumSteps: momentumSteps,
            momentumDecay: momentumDecay,
            momentumScale: momentumScale,
            startTime: MonotonicEventClock.nowSeconds
        )
        guard !commands.isEmpty else {
            throw ToolError.invalidValue(
                "generate-scroll",
                "派生イベントが有限値ではない、timestampを起動後nanosecondsへ変換できない、または生成上限 \(ScrollGenerationPlanner.maximumCommandCount) 件を超えています。"
            )
        }

        if isDryRun {
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
        let poster = EventPoster()
        for (index, command) in commands.enumerated() {
            poster.postScroll(command: command, mode: mode)
            if index < commands.count - 1 {
                Thread.sleep(forTimeInterval: interval)
            }
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
