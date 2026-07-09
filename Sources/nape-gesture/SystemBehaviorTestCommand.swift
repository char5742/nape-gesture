import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore

struct SystemBehaviorTestCommand {
    private let options: [String]
    private let killSwitchKeyCode = CGKeyCode(kVK_ANSI_G)
    private let killSwitchFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let subcommand = options.first ?? "list"
        let rest = Array(options.dropFirst())

        switch subcommand {
        case "list":
            printScenarios()
        case "readiness", "matrix":
            try printReadiness(options: rest)
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

              horizontal-scroll
                  通常の横スクロール割り当て相当の水平スクロールイベント列を生成します。

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

              kill-switch
                  キルスイッチ相当の Control + Option + Command + G を未マークのキーイベントとして生成します。

              gesture-drag
                  既定の activation button 押下、左ドラッグ、解放を未マークのマウスイベントとして生成します。

              gesture-wheel
                  既定の activation button 押下中のホイールを未マークのスクロールイベントとして生成します。

              gesture-wheel-then-kill-switch
                  既定の activation button 押下中にホイールを生成し、その最中にキルスイッチを未マークキーイベントとして生成します。

              normal-after-release
                  既定の activation button 解放後に通常の移動、左クリック、左ドラッグ、ホイールを未マークイベントとして生成します。

            例:
              nape-gesture system-test run --scenario space-left --target finder --amount 1800 --steps 36
              nape-gesture system-test run --scenario horizontal-scroll --post-to-pid <Reference Target App PID>
              nape-gesture system-test run --scenario gesture-drag --dry-run --log-json
              nape-gesture system-test run --scenario mission-control --dry-run
              nape-gesture system-test readiness --json
              nape-gesture system-test matrix --markdown --assert
            """
        )
    }

    private func printReadiness(options: [String]) throws {
        let wantsJSON = options.contains("--json")
        let wantsMarkdown = options.contains("--markdown")
        let wantsAssert = options.contains("--assert")
        if wantsJSON && wantsMarkdown {
            throw ToolError.invalidValue("--json", "--markdown と併用できません。")
        }

        let output: String
        let report = SystemTestReadinessReport.make()
        if wantsAssert {
            try report.assertValid()
        }
        if wantsJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            output = String(decoding: data, as: UTF8.self) + "\n"
        } else {
            output = report.markdown
        }

        try write(output, to: value("--out", in: options), label: "system-test readiness")
    }

    private func write(_ text: String, to outputPath: String?, label: String) throws {
        if let outputPath {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            fputs("\(label)を書き出しました: \(outputPath)\n", stderr)
        } else {
            print(text, terminator: "")
        }
    }

    private func runScenario(options: [String]) throws {
        let scenarioName = try requiredValue("--scenario", in: options)
        guard let scenario = SystemTestScenario(rawValue: scenarioName) else {
            throw ToolError.invalidValue("--scenario", scenarioName)
        }
        let target = value("--target", in: options)
        let dryRun = options.contains("--dry-run")
        let outputLogJSON = options.contains("--log-json")
        let outputPath = value("--out", in: options)
        let amount = try doubleValue("--amount", in: options, defaultValue: scenario.defaultAmount)
        let steps = try intValue("--steps", in: options, defaultValue: scenario.defaultSteps)
        let interval = try doubleValue("--interval", in: options, defaultValue: 0.008)
        let postToPid = try optionalPIDValue("--post-to-pid", in: options)
        if postToPid != nil && target != nil {
            throw ToolError.invalidValue("--post-to-pid", "--target と同時指定できません。process 直接投稿診断では Reference Target App を前面にしたまま PID だけを指定してください。")
        }
        if postToPid != nil && !scenario.supportsProcessTargetPosting {
            throw ToolError.invalidValue("--post-to-pid", "\(scenario.rawValue) は process 直接投稿診断に未対応です。")
        }
        let plan = try SystemTestPlan(
            scenario: scenario,
            target: target,
            amount: amount,
            steps: steps,
            interval: interval,
            postToPid: postToPid
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
        print("シナリオを実行しました。`nape-gesture log` または画面挙動で差分を確認してください。")
    }

    private func execute(_ plan: SystemTestPlan) throws {
        let poster = EventPoster()
        let now = Date().timeIntervalSince1970

        switch plan.scenario {
        case .spaceLeft:
            postScrollCommands(
                makeHorizontalCommands(sign: -1, plan: plan, now: now),
                poster: poster,
                mode: .forcedHorizontal(sign: -1),
                interval: plan.interval,
                targetPID: plan.postToPid
            )
        case .spaceRight:
            postScrollCommands(
                makeHorizontalCommands(sign: 1, plan: plan, now: now),
                poster: poster,
                mode: .forcedHorizontal(sign: 1),
                interval: plan.interval,
                targetPID: plan.postToPid
            )
        case .horizontalScroll:
            postScrollCommands(
                makeHorizontalCommands(sign: 1, plan: plan, now: now),
                poster: poster,
                mode: .horizontal,
                interval: plan.interval,
                targetPID: plan.postToPid
            )
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
        case .killSwitch:
            postUnmarkedInputEvents(unmarkedInputEvents(for: plan, startTime: now), to: nil)
        case .gestureDrag, .gestureWheel, .gestureWheelThenKillSwitch, .normalAfterRelease:
            postUnmarkedInputEvents(unmarkedInputEvents(for: plan, startTime: now), to: plan.postToPid)
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

    private func postScrollCommands(
        _ commands: [GestureCommand],
        poster: EventPoster,
        mode: ScrollPostMode,
        interval: TimeInterval,
        targetPID: pid_t?
    ) {
        for command in commands {
            poster.postScroll(command: command, mode: mode, to: targetPID)
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
        let records: [InputLogRecord] = switch plan.scenario {
        case .spaceLeft:
            makeHorizontalCommands(sign: -1, plan: plan, now: startTime)
                .map { scrollRecord(command: $0, mode: .forcedHorizontal(sign: -1)) }
        case .spaceRight:
            makeHorizontalCommands(sign: 1, plan: plan, now: startTime)
                .map { scrollRecord(command: $0, mode: .forcedHorizontal(sign: 1)) }
        case .horizontalScroll:
            makeHorizontalCommands(sign: 1, plan: plan, now: startTime)
                .map { scrollRecord(command: $0, mode: .horizontal) }
        case .missionControl:
            shortcutRecords(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl, startTime: startTime)
        case .pageBack:
            shortcutRecords(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand, startTime: startTime)
        case .pageForward:
            shortcutRecords(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand, startTime: startTime)
        case .zoomIn:
            shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand, startTime: startTime)
        case .zoomOut:
            shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand, startTime: startTime)
        case .killSwitch:
            unmarkedInputEvents(for: plan, startTime: startTime).map { $0.logRecord() }
        case .gestureDrag, .gestureWheel, .gestureWheelThenKillSwitch, .normalAfterRelease:
            unmarkedInputEvents(for: plan, startTime: startTime).map { $0.logRecord() }
        }
        return annotateSystemTestRecords(records, scenario: plan.scenario)
    }

    private func annotateSystemTestRecords(
        _ records: [InputLogRecord],
        scenario: SystemTestScenario
    ) -> [InputLogRecord] {
        records.enumerated().map { index, record in
            var record = record
            record.systemTestScenario = scenario.rawValue
            record.sequenceIndex = index
            return record
        }
    }

    private func scrollRecord(command: GestureCommand, mode: ScrollPostMode) -> InputLogRecord {
        let posted = mode.deltas(for: command)
        let phases = CGEventUtilities.phaseValues(for: command)
        return InputLogRecord(
            timestamp: timestamp(command.timestamp),
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
    }

    private func shortcutRecords(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        startTime: TimeInterval,
        generatedByNapeGesture: Bool = true
    ) -> [InputLogRecord] {
        [
            keyRecord(
                typeName: "keyDown",
                type: .keyDown,
                keyCode: keyCode,
                flags: flags,
                time: startTime,
                generatedByNapeGesture: generatedByNapeGesture
            ),
            keyRecord(
                typeName: "keyUp",
                type: .keyUp,
                keyCode: keyCode,
                flags: flags,
                time: startTime + 0.01,
                generatedByNapeGesture: generatedByNapeGesture
            )
        ]
    }

    private func keyRecord(
        typeName: String,
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        time: TimeInterval,
        generatedByNapeGesture: Bool
    ) -> InputLogRecord {
        InputLogRecord(
            timestamp: timestamp(time),
            typeName: typeName,
            typeRaw: Int(type.rawValue),
            generatedByNapeGesture: generatedByNapeGesture,
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

    private func unmarkedInputEvents(for plan: SystemTestPlan, startTime: TimeInterval) -> [UnmarkedInputEvent] {
        switch plan.scenario {
        case .gestureDrag:
            return unmarkedGestureDragEvents(plan: plan, startTime: startTime)
        case .gestureWheel:
            return unmarkedGestureWheelEvents(plan: plan, startTime: startTime)
        case .gestureWheelThenKillSwitch:
            return unmarkedGestureWheelThenKillSwitchEvents(plan: plan, startTime: startTime)
        case .normalAfterRelease:
            return unmarkedNormalAfterReleaseEvents(plan: plan, startTime: startTime)
        case .killSwitch:
            return unmarkedKillSwitchEvents(plan: plan, startTime: startTime)
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut:
            return []
        }
    }

    private func unmarkedKillSwitchEvents(plan: SystemTestPlan, startTime: TimeInterval) -> [UnmarkedInputEvent] {
        [
            unmarkedKeyEvent(
                type: .keyDown,
                time: startTime,
                keyCode: Int64(killSwitchKeyCode),
                flags: killSwitchFlags.rawValue
            ),
            unmarkedKeyEvent(
                type: .keyUp,
                time: startTime + plan.interval,
                keyCode: Int64(killSwitchKeyCode),
                flags: killSwitchFlags.rawValue
            )
        ]
    }

    private func unmarkedGestureDragEvents(plan: SystemTestPlan, startTime: TimeInterval) -> [UnmarkedInputEvent] {
        var events = [
            unmarkedMouseEvent(
                type: .otherMouseDown,
                time: startTime,
                buttonNumber: plan.activationButtonNumber
            )
        ]
        let deltas = quantizedDeltas(total: -plan.amount, steps: plan.steps)
        for (index, deltaX) in deltas.enumerated() {
            events.append(
                unmarkedMouseEvent(
                    type: .otherMouseDragged,
                    time: startTime + Double(index + 1) * plan.interval,
                    buttonNumber: plan.activationButtonNumber,
                    deltaX: deltaX
                )
            )
        }
        events.append(
            unmarkedMouseEvent(
                type: .otherMouseUp,
                time: startTime + Double(plan.steps + 1) * plan.interval,
                buttonNumber: plan.activationButtonNumber
            )
        )
        return events
    }

    private func unmarkedGestureWheelEvents(plan: SystemTestPlan, startTime: TimeInterval) -> [UnmarkedInputEvent] {
        var events = [
            unmarkedMouseEvent(
                type: .otherMouseDown,
                time: startTime,
                buttonNumber: plan.activationButtonNumber
            )
        ]
        let deltas = quantizedDeltas(total: -plan.amount, steps: plan.steps)
        for (index, deltaY) in deltas.enumerated() {
            events.append(
                unmarkedScrollEvent(
                    time: startTime + Double(index + 1) * plan.interval,
                    deltaY: deltaY
                )
            )
        }
        events.append(
            unmarkedMouseEvent(
                type: .otherMouseUp,
                time: startTime + Double(plan.steps + 1) * plan.interval,
                buttonNumber: plan.activationButtonNumber
            )
        )
        return events
    }

    private func unmarkedGestureWheelThenKillSwitchEvents(
        plan: SystemTestPlan,
        startTime: TimeInterval
    ) -> [UnmarkedInputEvent] {
        var events = [
            unmarkedMouseEvent(
                type: .otherMouseDown,
                time: startTime,
                buttonNumber: plan.activationButtonNumber
            )
        ]
        let deltas = quantizedDeltas(total: -plan.amount, steps: plan.steps)
        for (index, deltaY) in deltas.enumerated() {
            events.append(
                unmarkedScrollEvent(
                    time: startTime + Double(index + 1) * plan.interval,
                    deltaY: deltaY
                )
            )
        }

        let keyDownTime = startTime + Double(plan.steps + 1) * plan.interval
        events.append(
            unmarkedKeyEvent(
                type: .keyDown,
                time: keyDownTime,
                keyCode: Int64(killSwitchKeyCode),
                flags: killSwitchFlags.rawValue
            )
        )
        events.append(
            unmarkedKeyEvent(
                type: .keyUp,
                time: keyDownTime + plan.interval,
                keyCode: Int64(killSwitchKeyCode),
                flags: killSwitchFlags.rawValue
            )
        )
        events.append(
            unmarkedMouseEvent(
                type: .otherMouseUp,
                time: keyDownTime + (2 * plan.interval),
                buttonNumber: plan.activationButtonNumber
            )
        )
        return events
    }

    private func unmarkedNormalAfterReleaseEvents(plan: SystemTestPlan, startTime: TimeInterval) -> [UnmarkedInputEvent] {
        var events = [
            unmarkedMouseEvent(
                type: .otherMouseDown,
                time: startTime,
                buttonNumber: plan.activationButtonNumber
            ),
            unmarkedMouseEvent(
                type: .otherMouseUp,
                time: startTime + plan.interval,
                buttonNumber: plan.activationButtonNumber
            )
        ]
        let deltas = quantizedDeltas(total: plan.amount, steps: plan.steps)
        for (index, deltaX) in deltas.enumerated() {
            events.append(
                unmarkedMouseEvent(
                    type: .mouseMoved,
                    time: startTime + Double(index + 2) * plan.interval,
                    deltaX: deltaX
                )
            )
        }
        let clickDownTime = startTime + Double(plan.steps + 2) * plan.interval
        events.append(
            unmarkedMouseEvent(
                type: .leftMouseDown,
                time: clickDownTime
            )
        )
        events.append(
            unmarkedMouseEvent(
                type: .leftMouseUp,
                time: clickDownTime + plan.interval
            )
        )
        let dragDownTime = clickDownTime + (2 * plan.interval)
        let dragDelta = max(Int64(1), abs(quantizeInt64(plan.amount / Double(max(plan.steps, 1)))))
        events.append(
            unmarkedMouseEvent(
                type: .leftMouseDown,
                time: dragDownTime
            )
        )
        events.append(
            unmarkedMouseEvent(
                type: .leftMouseDragged,
                time: dragDownTime + plan.interval,
                deltaX: dragDelta
            )
        )
        events.append(
            unmarkedMouseEvent(
                type: .leftMouseUp,
                time: dragDownTime + (2 * plan.interval)
            )
        )
        let wheelDelta = -max(Int64(1), abs(quantizeInt64(plan.amount / Double(max(plan.steps, 1)))))
        events.append(
            unmarkedScrollEvent(
                time: dragDownTime + (3 * plan.interval),
                deltaY: wheelDelta
            )
        )
        return events
    }

    private func unmarkedMouseEvent(
        type: CGEventType,
        time: TimeInterval,
        buttonNumber: Int64 = 0,
        deltaX: Int64 = 0,
        deltaY: Int64 = 0
    ) -> UnmarkedInputEvent {
        UnmarkedInputEvent(
            type: type,
            time: time,
            buttonNumber: buttonNumber,
            deltaX: deltaX,
            deltaY: deltaY,
            scrollDeltaX: 0,
            scrollDeltaY: 0,
            pointDeltaX: 0,
            pointDeltaY: 0,
            scrollPhase: 0,
            momentumPhase: 0,
            isContinuous: 0
        )
    }

    private func unmarkedScrollEvent(time: TimeInterval, deltaY: Int64) -> UnmarkedInputEvent {
        UnmarkedInputEvent(
            type: .scrollWheel,
            time: time,
            buttonNumber: 0,
            deltaX: 0,
            deltaY: 0,
            scrollDeltaX: 0,
            scrollDeltaY: deltaY,
            pointDeltaX: 0,
            pointDeltaY: Double(deltaY),
            scrollPhase: 0,
            momentumPhase: 0,
            isContinuous: 1
        )
    }

    private func unmarkedKeyEvent(
        type: CGEventType,
        time: TimeInterval,
        keyCode: Int64,
        flags: UInt64
    ) -> UnmarkedInputEvent {
        UnmarkedInputEvent(
            type: type,
            time: time,
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
            keyCode: keyCode,
            flags: flags
        )
    }

    private func postUnmarkedInputEvents(_ events: [UnmarkedInputEvent], to pid: pid_t?) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
        var cursorPosition = currentPointerLocation()
        var previousTime: TimeInterval?

        for plannedEvent in events {
            if let previousTime {
                Thread.sleep(forTimeInterval: max(plannedEvent.time - previousTime, 0))
            }
            guard let event = plannedEvent.makeCGEvent(source: source, cursorPosition: &cursorPosition) else {
                previousTime = plannedEvent.time
                continue
            }
            post(event, to: pid)
            previousTime = plannedEvent.time
        }
    }

    private func post(_ event: CGEvent, to pid: pid_t?) {
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func quantizedDeltas(total: Double, steps: Int) -> [Int64] {
        let total = quantizeInt64(total)
        guard steps > 0 else {
            return []
        }

        let sign: Int64 = total < 0 ? -1 : 1
        let magnitude = total == Int64.min ? Int64.max : abs(total)
        let base = magnitude / Int64(steps)
        let remainder = magnitude % Int64(steps)

        return (0..<steps).map { index in
            let extra: Int64 = Int64(index) < remainder ? 1 : 0
            return sign * (base + extra)
        }
    }

    private func timestamp(_ time: TimeInterval) -> UInt64 {
        UInt64(max(time, 0) * 1_000_000_000)
    }

    private func quantizeInt64(_ value: Double) -> Int64 {
        let rounded = value.rounded()
        if rounded > Double(Int64.max) {
            return Int64.max
        }
        if rounded < Double(Int64.min) {
            return Int64.min
        }
        return Int64(rounded)
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

    private func optionalPIDValue(_ name: String, in options: [String]) throws -> pid_t? {
        guard options.contains(name) else {
            return nil
        }
        let raw = try requiredValue(name, in: options)
        guard let value = Int32(raw), value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return pid_t(value)
    }
}

private struct SystemTestReadinessReport: Encodable {
    let schemaVersion: Int
    let scope: String
    let completionState: String
    let humanWorkPolicy: String
    let summary: SystemTestReadinessSummary
    let scenarios: [SystemTestScenarioReadiness]

    static func make() -> SystemTestReadinessReport {
        let scenarios = SystemTestScenario.allCases.map { $0.readiness }
        return SystemTestReadinessReport(
            schemaVersion: 1,
            scope: "system-behavior-test-readiness",
            completionState: scenarios.contains { $0.requiresScreenBehaviorEvidence }
                ? "screen-behavior-evidence-pending"
                : "machine-evidence-complete",
            humanWorkPolicy: "人間作業は物理トラックパッド、Nape Pro 実機操作、外部アカウント操作など、CGEvent、保存済みログ、Reference Target App、computer-use で代替できない場合だけ need:human として扱う。",
            summary: SystemTestReadinessSummary(scenarios: scenarios),
            scenarios: scenarios
        )
    }

    var markdown: String {
        var lines: [String] = [
            "# System Behavior Test readiness matrix",
            "",
            "この matrix は `system-test` の各シナリオについて、先に機械で埋める証跡、画面挙動の実測待ち、人間作業ラベルの境界を同じ定義から出力する。",
            "人間作業は、物理トラックパッド、Nape Pro 実機操作、外部アカウント操作など、CGEvent、保存済みログ、Reference Target App、computer-use で代替できない場合だけ `need:human` として扱う。",
            "",
            "## Summary",
            "",
            "- schemaVersion: \(schemaVersion)",
            "- scope: `\(scope)`",
            "- completionState: `\(completionState)`",
            "- scenarioCount: \(summary.scenarioCount)",
            "- machinePreflightScenarioCount: \(summary.machinePreflightScenarioCount)",
            "- screenBehaviorPendingScenarioCount: \(summary.screenBehaviorPendingScenarioCount)",
            "- runtimeTargetEvidenceScenarioCount: \(summary.runtimeTargetEvidenceScenarioCount)",
            "- needHumanLabelScenarioCount: \(summary.needHumanLabelScenarioCount)",
            "",
            "## Matrix",
            "",
            "| シナリオ | 完成要件 | 機械証跡 | 画面挙動 / 人間作業境界 | Issue | 状態 |",
            "| --- | --- | --- | --- | --- | --- |"
        ]

        for scenario in scenarios {
            lines.append(
                [
                    scenario.scenario,
                    scenario.completionRequirement,
                    markdownCodeCell(scenario.machineEvidence),
                    markdownCell(scenario.screenBehaviorEvidence + scenario.humanWorkBoundary),
                    scenario.relatedIssues.map { "#\($0)" }.joined(separator: ", "),
                    scenario.completionState
                ]
                    .map(escapeTableCell)
                    .joined(separator: " | ")
                    .withTableBoundaries
            )
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func markdownCell(_ values: [String]) -> String {
        values.isEmpty ? "なし" : values.joined(separator: "<br>")
    }

    private func markdownCodeCell(_ values: [String]) -> String {
        values.isEmpty ? "なし" : values.map { "`\($0)`" }.joined(separator: "<br>")
    }

    private func escapeTableCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    func assertValid() throws {
        var failures: [String] = []
        let scenarioNames = Set(scenarios.map(\.scenario))
        let expectedNames = Set(SystemTestScenario.allCases.map(\.rawValue))
        let missingScenarios = expectedNames.subtracting(scenarioNames).sorted()
        let unexpectedScenarios = scenarioNames.subtracting(expectedNames).sorted()
        if !missingScenarios.isEmpty {
            failures.append("readiness にない system-test scenario: \(missingScenarios.joined(separator: ", "))")
        }
        if !unexpectedScenarios.isEmpty {
            failures.append("未知の readiness scenario: \(unexpectedScenarios.joined(separator: ", "))")
        }
        if summary.scenarioCount != SystemTestScenario.allCases.count {
            failures.append("scenarioCount が SystemTestScenario.allCases と一致しません。")
        }
        if summary.screenBehaviorPendingScenarioCount < 7 {
            failures.append("Issue #9 / #10 の画面挙動待ちシナリオ数が想定より少ないです。")
        }
        if scenarios.filter({ $0.relatedIssues.contains(9) }).isEmpty {
            failures.append("Issue #9 に紐づく scenario がありません。")
        }
        if scenarios.filter({ $0.relatedIssues.contains(10) }).isEmpty {
            failures.append("Issue #10 に紐づく scenario がありません。")
        }
        if summary.needHumanLabelScenarioCount != 0 {
            failures.append("CLI が need:human 適用を直接要求しています。人間作業は外部作業が不可避な Issue / PR に限定してください。")
        }
        for scenario in scenarios {
            if scenario.machineEvidence.isEmpty {
                failures.append("\(scenario.scenario) に機械証跡コマンドがありません。")
            }
            if scenario.requiresScreenBehaviorEvidence && scenario.screenBehaviorEvidence.isEmpty {
                failures.append("\(scenario.scenario) は画面挙動待ちなのに screenBehaviorEvidence が空です。")
            }
        }

        if !failures.isEmpty {
            throw SystemTestReadinessAssertionError(failures: failures)
        }
    }
}

private struct SystemTestReadinessSummary: Encodable {
    let scenarioCount: Int
    let machinePreflightScenarioCount: Int
    let screenBehaviorPendingScenarioCount: Int
    let runtimeTargetEvidenceScenarioCount: Int
    let needHumanLabelScenarioCount: Int

    init(scenarios: [SystemTestScenarioReadiness]) {
        scenarioCount = scenarios.count
        machinePreflightScenarioCount = scenarios.filter { !$0.machineEvidence.isEmpty }.count
        screenBehaviorPendingScenarioCount = scenarios.filter(\.requiresScreenBehaviorEvidence).count
        runtimeTargetEvidenceScenarioCount = scenarios.filter(\.requiresRuntimeTargetEvidence).count
        needHumanLabelScenarioCount = scenarios.filter(\.needHumanLabelApplies).count
    }
}

private struct SystemTestScenarioReadiness: Encodable {
    let scenario: String
    let completionRequirement: String
    let relatedIssues: [Int]
    let expectedTargets: [String]
    let eventShape: String
    let machineEvidence: [String]
    let runtimeEvidence: [String]
    let screenBehaviorEvidence: [String]
    let humanWorkBoundary: [String]
    let requiresScreenBehaviorEvidence: Bool
    let requiresRuntimeTargetEvidence: Bool
    let needHumanLabelApplies: Bool
    let completionState: String
}

private struct SystemTestReadinessAssertionError: LocalizedError {
    var failures: [String]

    var errorDescription: String? {
        let details = failures.map { "- \($0)" }.joined(separator: "\n")
        return """
        system-test readiness が完成判定 matrix として不完全です。
        \(details)
        `nape-gesture system-test readiness --json --assert` の出力定義を確認してください。
        """
    }
}

private struct SystemTestPlan {
    var scenario: SystemTestScenario
    var target: SystemTestTarget?
    var amount: Double
    var steps: Int
    var interval: TimeInterval
    var postToPid: pid_t?
    var activationButtonNumber: Int64 {
        Int64(GestureConfiguration.default.activationButton.rawValue)
    }

    init(
        scenario: SystemTestScenario,
        target: String?,
        amount: Double,
        steps: Int,
        interval: TimeInterval,
        postToPid: pid_t?
    ) throws {
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
        self.postToPid = postToPid
    }

    var description: String {
        [
            "system-test plan",
            "scenario=\(scenario.rawValue)",
            "target=\(target?.rawValue ?? "none")",
            "amount=\(amount)",
            "steps=\(steps)",
            "interval=\(interval)",
            "postToPid=\(postToPid.map(String.init) ?? "none")"
        ].joined(separator: "\n")
    }
}

private enum SystemTestScenario: String, CaseIterable {
    case spaceLeft = "space-left"
    case spaceRight = "space-right"
    case horizontalScroll = "horizontal-scroll"
    case missionControl = "mission-control"
    case pageBack = "page-back"
    case pageForward = "page-forward"
    case zoomIn = "zoom-in"
    case zoomOut = "zoom-out"
    case killSwitch = "kill-switch"
    case gestureDrag = "gesture-drag"
    case gestureWheel = "gesture-wheel"
    case gestureWheelThenKillSwitch = "gesture-wheel-then-kill-switch"
    case normalAfterRelease = "normal-after-release"

    var defaultAmount: Double {
        switch self {
        case .normalAfterRelease:
            return 24
        case .gestureWheel, .gestureWheelThenKillSwitch:
            return 240
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut,
             .killSwitch,
             .gestureDrag:
            return 1600
        }
    }

    var defaultSteps: Int {
        switch self {
        case .normalAfterRelease:
            return 2
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut,
             .killSwitch,
             .gestureDrag,
             .gestureWheel,
             .gestureWheelThenKillSwitch:
            return 32
        }
    }

    var supportsProcessTargetPosting: Bool {
        switch self {
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .gestureDrag,
             .gestureWheel,
             .gestureWheelThenKillSwitch,
             .normalAfterRelease:
            return true
        case .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut,
             .killSwitch:
            return false
        }
    }

    var readiness: SystemTestScenarioReadiness {
        let targetFlag = dryRunTarget.map { " --target \($0)" } ?? ""
        let dryRunCommand = ".build/debug/nape-gesture system-test run --scenario \(rawValue)\(targetFlag) --dry-run --log-json --out <artifact>/system-\(rawValue).jsonl"
        let analyzeCommand = ".build/debug/nape-gesture analyze-log <artifact>/system-\(rawValue).jsonl --json --assert-system-scenario \(rawValue)\(additionalAnalyzeAssertions)"
        let machineEvidence = [
            dryRunCommand,
            analyzeCommand
        ]

        return SystemTestScenarioReadiness(
            scenario: rawValue,
            completionRequirement: completionRequirement,
            relatedIssues: relatedIssues,
            expectedTargets: expectedTargets,
            eventShape: eventShape,
            machineEvidence: machineEvidence,
            runtimeEvidence: runtimeEvidence,
            screenBehaviorEvidence: screenBehaviorEvidence,
            humanWorkBoundary: humanWorkBoundary,
            requiresScreenBehaviorEvidence: requiresScreenBehaviorEvidence,
            requiresRuntimeTargetEvidence: requiresRuntimeTargetEvidence,
            needHumanLabelApplies: needHumanLabelApplies,
            completionState: completionState
        )
    }

    private var completionRequirement: String {
        switch self {
        case .spaceLeft, .spaceRight, .missionControl:
            return "Spaces / Mission Control"
        case .horizontalScroll, .pageBack, .pageForward, .zoomIn, .zoomOut:
            return "ページ戻る / 進む / ズーム / 横スクロール"
        case .killSwitch, .gestureWheelThenKillSwitch:
            return "キルスイッチ"
        case .gestureDrag, .gestureWheel:
            return "元入力抑制"
        case .normalAfterRelease:
            return "通常クリック / ドラッグ / ホイール通過"
        }
    }

    private var relatedIssues: [Int] {
        switch self {
        case .spaceLeft, .spaceRight, .missionControl:
            return [9, 16]
        case .horizontalScroll, .pageBack, .pageForward, .zoomIn, .zoomOut:
            return [10, 16]
        case .killSwitch:
            return [12, 16]
        case .gestureWheelThenKillSwitch:
            return [6, 12, 16]
        case .gestureDrag, .gestureWheel, .normalAfterRelease:
            return [6, 16]
        }
    }

    private var expectedTargets: [String] {
        switch self {
        case .spaceLeft, .spaceRight:
            return ["Finder", "Safari"]
        case .missionControl:
            return ["Finder", "Mission Control"]
        case .horizontalScroll:
            return ["横スクロール可能なビュー", "Reference Target App"]
        case .pageBack, .pageForward:
            return ["Safari"]
        case .zoomIn, .zoomOut:
            return ["Safari", "Preview などズーム可能なアプリ"]
        case .killSwitch, .gestureDrag, .gestureWheel, .gestureWheelThenKillSwitch, .normalAfterRelease:
            return ["Reference Target App"]
        }
    }

    private var eventShape: String {
        switch self {
        case .spaceLeft:
            return "生成済み水平 scrollWheel、左 Spaces 方向"
        case .spaceRight:
            return "生成済み水平 scrollWheel、右 Spaces 方向"
        case .horizontalScroll:
            return "生成済み水平 scrollWheel、通常横スクロール"
        case .missionControl:
            return "生成済み Control + 上矢印 keyDown / keyUp"
        case .pageBack:
            return "生成済み Command + 左矢印 keyDown / keyUp"
        case .pageForward:
            return "生成済み Command + 右矢印 keyDown / keyUp"
        case .zoomIn:
            return "生成済み Command + = keyDown / keyUp"
        case .zoomOut:
            return "生成済み Command + - keyDown / keyUp"
        case .killSwitch:
            return "未生成 Control + Option + Command + G keyDown / keyUp"
        case .gestureDrag:
            return "未生成 activation button 押下、ドラッグ、解放"
        case .gestureWheel:
            return "未生成 activation button 押下中のホイール、解放"
        case .gestureWheelThenKillSwitch:
            return "未生成 activation button 押下中のホイールとキルスイッチ"
        case .normalAfterRelease:
            return "activation button 解放後の未生成移動、通常クリック、通常ドラッグ、通常ホイール"
        }
    }

    private var dryRunTarget: String? {
        switch self {
        case .spaceLeft, .spaceRight:
            return "finder"
        case .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut,
             .killSwitch,
             .gestureDrag,
             .gestureWheel,
             .gestureWheelThenKillSwitch,
             .normalAfterRelease:
            return nil
        }
    }

    private var additionalAnalyzeAssertions: String {
        switch self {
        case .killSwitch:
            return " --assert-kill-switch-shortcut"
        case .gestureWheelThenKillSwitch:
            return " --assert-kill-switch-shortcut --assert-gesture-before-kill-switch"
        case .normalAfterRelease:
            return " --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel"
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut,
             .gestureDrag,
             .gestureWheel:
            return ""
        }
    }

    private var runtimeEvidence: [String] {
        switch self {
        case .gestureDrag, .gestureWheel:
            return [
                "scripts/collect-runtime-event-evidence.sh の target log",
                "analyze-target-log --assert-no-leaks --assert-has-generated-event --assert-has-foreground-capture"
            ]
        case .gestureWheelThenKillSwitch:
            return [
                "scripts/collect-runtime-event-evidence.sh の daemon 停止ログと target log",
                "analyze-target-log --assert-no-leaks --assert-has-generated-event --assert-has-foreground-capture"
            ]
        case .normalAfterRelease:
            return [
                "scripts/collect-runtime-event-evidence.sh の target log",
                "analyze-target-log --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel --assert-has-foreground-capture"
            ]
        case .killSwitch:
            return [
                "system-test run --scenario kill-switch の実投稿ログ",
                "daemon 停止ログ"
            ]
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut:
            return []
        }
    }

    private var screenBehaviorEvidence: [String] {
        switch self {
        case .spaceLeft, .spaceRight:
            return [
                "Finder / Safari 前面で Spaces が期待方向へ遷移した画面挙動証跡",
                "同じ scenario 名の CGEvent log、AppKit target log、体感差分"
            ]
        case .missionControl:
            return [
                "Mission Control が表示される画面挙動証跡",
                "純正操作ログと生成イベントログの比較"
            ]
        case .horizontalScroll:
            return [
                "横スクロール可能なビューの表示位置が期待方向へ変化した画面挙動証跡",
                "AppKit target log または対象アプリの受信ログ"
            ]
        case .pageBack:
            return ["Safari の履歴が戻る画面挙動証跡"]
        case .pageForward:
            return ["Safari の履歴が進む画面挙動証跡"]
        case .zoomIn:
            return ["対応アプリのズーム倍率が上がる画面挙動証跡"]
        case .zoomOut:
            return ["対応アプリのズーム倍率が下がる画面挙動証跡"]
        case .killSwitch,
             .gestureDrag,
             .gestureWheel,
             .gestureWheelThenKillSwitch,
             .normalAfterRelease:
            return []
        }
    }

    private var humanWorkBoundary: [String] {
        switch self {
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut:
            return [
                "まず CGEvent 実投稿、Reference Target App、computer-use の画面証跡で代替する。",
                "物理トラックパッド操作や人間の目視操作が不可避になった場合だけ need:human を付ける。"
            ]
        case .killSwitch:
            return ["物理キーボード由来まで含める場合だけ need:human を検討する。"]
        case .gestureDrag, .gestureWheel, .gestureWheelThenKillSwitch, .normalAfterRelease:
            return ["Nape Pro 実機の物理操作でしか確認できない最終差分は Issue #4 / #16 へ分離する。"]
        }
    }

    private var requiresScreenBehaviorEvidence: Bool {
        !screenBehaviorEvidence.isEmpty
    }

    private var requiresRuntimeTargetEvidence: Bool {
        !runtimeEvidence.isEmpty
    }

    private var needHumanLabelApplies: Bool {
        false
    }

    private var completionState: String {
        if requiresScreenBehaviorEvidence {
            return "画面挙動実測待ち"
        }
        if requiresRuntimeTargetEvidence {
            return "runtime target log 証跡対象"
        }
        return "機械前段証跡対象"
    }
}

private enum SystemTestTarget: String {
    case finder
    case safari
}

private extension String {
    var withTableBoundaries: String {
        "| \(self) |"
    }
}

private struct UnmarkedInputEvent {
    var type: CGEventType
    var time: TimeInterval
    var buttonNumber: Int64
    var deltaX: Int64
    var deltaY: Int64
    var scrollDeltaX: Int64
    var scrollDeltaY: Int64
    var pointDeltaX: Double
    var pointDeltaY: Double
    var scrollPhase: Int64
    var momentumPhase: Int64
    var isContinuous: Int64
    var keyCode: Int64 = 0
    var flags: UInt64 = 0

    func logRecord() -> InputLogRecord {
        InputLogRecord(
            timestamp: UInt64(max(time, 0) * 1_000_000_000),
            typeName: stableTypeName,
            typeRaw: Int(type.rawValue),
            generatedByNapeGesture: false,
            buttonNumber: buttonNumber,
            deltaX: deltaX,
            deltaY: deltaY,
            scrollDeltaX: scrollDeltaX,
            scrollDeltaY: scrollDeltaY,
            pointDeltaX: pointDeltaX,
            pointDeltaY: pointDeltaY,
            scrollPhase: scrollPhase,
            momentumPhase: momentumPhase,
            isContinuous: isContinuous,
            keyCode: keyCode,
            flags: flags
        )
    }

    func makeCGEvent(source: CGEventSource?, cursorPosition: inout CGPoint) -> CGEvent? {
        let event: CGEvent?
        if type == .keyDown || type == .keyUp {
            guard keyCode >= 0, keyCode <= Int64(UInt16.max) else {
                return nil
            }
            event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: type == .keyDown
            )
            event?.flags = CGEventFlags(rawValue: flags)
        } else if type == .scrollWheel {
            event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: int32(scrollDeltaY),
                wheel2: int32(scrollDeltaX),
                wheel3: 0
            )
            event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
            event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
            event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: isContinuous)
            event?.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY)
            event?.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaX)
        } else {
            cursorPosition.x += CGFloat(deltaX)
            cursorPosition.y += CGFloat(deltaY)
            event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: cursorPosition,
                mouseButton: mouseButton
            )
            event?.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            event?.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
            event?.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
        }

        return event
    }

    private var stableTypeName: String {
        switch type {
        case .mouseMoved:
            return "mouseMoved"
        case .leftMouseDown:
            return "leftMouseDown"
        case .leftMouseUp:
            return "leftMouseUp"
        case .leftMouseDragged:
            return "leftMouseDragged"
        case .rightMouseDown:
            return "rightMouseDown"
        case .rightMouseUp:
            return "rightMouseUp"
        case .rightMouseDragged:
            return "rightMouseDragged"
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .otherMouseDragged:
            return "otherMouseDragged"
        case .scrollWheel:
            return "scrollWheel"
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        default:
            return "raw-\(type.rawValue)"
        }
    }

    private var mouseButton: CGMouseButton {
        switch type {
        case .mouseMoved:
            return .left
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            guard buttonNumber >= 0,
                  buttonNumber <= Int64(UInt32.max),
                  let button = CGMouseButton(rawValue: UInt32(buttonNumber))
            else {
                return .center
            }
            return button
        default:
            return .center
        }
    }

    private func int32(_ value: Int64) -> Int32 {
        if value > Int64(Int32.max) {
            return Int32.max
        }
        if value < Int64(Int32.min) {
            return Int32.min
        }
        return Int32(value)
    }
}
