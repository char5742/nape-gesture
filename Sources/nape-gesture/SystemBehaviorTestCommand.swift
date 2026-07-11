import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore

private extension SystemBehaviorPostResultSnapshot {
    init(_ result: EventPostResult) {
        self.init(
            generatedEventCount: result.generatedEventCount,
            failedEventCreationCount: result.failedEventCreationCount
        )
    }
}

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
              nape-gesture system-test run --scenario gesture-drag --dry-run --log-json
              nape-gesture system-test run --scenario mission-control --dry-run
            """
        )
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
        let now = MonotonicEventClock.nowSeconds

        switch plan.scenario {
        case .spaceLeft:
            try postScrollCommands(
                try makeHorizontalCommands(sign: -1, plan: plan, now: now),
                poster: poster,
                mode: .forcedHorizontal(sign: -1),
                interval: plan.interval
            )
        case .spaceRight:
            try postScrollCommands(
                try makeHorizontalCommands(sign: 1, plan: plan, now: now),
                poster: poster,
                mode: .forcedHorizontal(sign: 1),
                interval: plan.interval
            )
        case .horizontalScroll:
            try postScrollCommands(
                try makeHorizontalCommands(sign: 1, plan: plan, now: now),
                poster: poster,
                mode: .horizontal,
                interval: plan.interval
            )
        case .missionControl:
            try requireSuccessfulPost(poster.postMissionControl(timestamp: now))
        case .pageBack:
            try requireSuccessfulPost(poster.postPageBack(timestamp: now))
        case .pageForward:
            try requireSuccessfulPost(poster.postPageForward(timestamp: now))
        case .zoomIn:
            try requireSuccessfulPost(poster.postZoomIn(timestamp: now))
        case .zoomOut:
            try requireSuccessfulPost(poster.postZoomOut(timestamp: now))
        case .killSwitch:
            try postUnmarkedInputEvents(unmarkedInputEvents(for: plan, startTime: now), to: nil)
        case .gestureDrag, .gestureWheel, .gestureWheelThenKillSwitch, .normalAfterRelease:
            try postUnmarkedInputEvents(unmarkedInputEvents(for: plan, startTime: now), to: plan.postToPid)
        }
    }

    private func makeHorizontalCommands(
        sign: Int,
        plan: SystemTestPlan,
        now: TimeInterval
    ) throws -> [GestureCommand] {
        let perStep = plan.amount / Double(plan.steps)
        let velocity = perStep / max(plan.interval, 0.001)
        guard perStep.isFinite, velocity.isFinite else {
            throw ToolError.invalidValue(
                "system-test plan",
                "派生したスクロール量または速度が有限値ではありません。"
            )
        }
        var commands: [GestureCommand] = []
        commands.reserveCapacity(plan.steps)

        for index in 0..<plan.steps {
            let phase: GesturePhase
            if index == 0 {
                phase = .began
            } else if index == plan.steps - 1 {
                phase = .ended
            } else {
                phase = .changed
            }

            let timestamp = now + Double(index) * plan.interval
            guard timestamp.isFinite else {
                throw ToolError.invalidValue(
                    "system-test plan",
                    "派生した timestamp が有限値ではありません。"
                )
            }
            let command = GestureCommand(
                kind: .drag,
                phase: phase,
                direction: sign < 0 ? .left : .right,
                deltaX: Double(sign) * perStep,
                deltaY: 0,
                velocityX: Double(sign) * velocity,
                velocityY: 0,
                timestamp: timestamp
            )

            commands.append(command)
        }

        guard MonotonicEventClock.validatedTimestampSequenceNanosecondsForPosting(
            fromSecondsSinceStartup: commands.map(\.timestamp)
        ) != nil else {
            throw ToolError.invalidValue(
                "CGEvent timestamp",
                "現在の起動後単調時刻から60秒以内のイベント列を生成できませんでした。"
            )
        }
        return commands
    }

    private func postScrollCommands(
        _ commands: [GestureCommand],
        poster: EventPoster,
        mode: ScrollPostMode,
        interval: TimeInterval
    ) throws {
        var results: [SystemBehaviorPostResultSnapshot] = []
        results.reserveCapacity(commands.count)

        for (index, command) in commands.enumerated() {
            let result = SystemBehaviorPostResultSnapshot(
                poster.postScroll(command: command, mode: mode, axDelivery: .synchronous)
            )
            if result.failedEventCreationCount > 0 {
                try requireSuccessfulPost(result)
            }
            results.append(result)
            if index < commands.count - 1 {
                Thread.sleep(forTimeInterval: interval)
            }
        }

        // 端到達や一時的な noChange は系列内で起こり得る。系列全体で1件も配送できない場合だけ失敗する。
        try requireSuccessfulPost(.combined(results))
    }

    private func requireSuccessfulPost(_ result: EventPostResult) throws {
        try requireSuccessfulPost(SystemBehaviorPostResultSnapshot(result))
    }

    private func requireSuccessfulPost(_ result: SystemBehaviorPostResultSnapshot) throws {
        let status = result.status
        guard let failureName = status.failureName,
              let failureDescription = status.failureDescription
        else {
            return
        }
        throw ToolError.invalidValue(failureName, failureDescription)
    }

    private func writeLogJSON(for plan: SystemTestPlan, to outputPath: String?) throws {
        let records = try logRecords(for: plan, startTime: MonotonicEventClock.nowSeconds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try records.map { record -> String in
            let data = try encoder.encode(record)
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

    private func logRecords(for plan: SystemTestPlan, startTime: TimeInterval) throws -> [InputLogRecord] {
        let records: [InputLogRecord]
        switch plan.scenario {
        case .spaceLeft:
            records = try makeHorizontalCommands(sign: -1, plan: plan, now: startTime)
                .map { try scrollRecord(command: $0, mode: .forcedHorizontal(sign: -1)) }
        case .spaceRight:
            records = try makeHorizontalCommands(sign: 1, plan: plan, now: startTime)
                .map { try scrollRecord(command: $0, mode: .forcedHorizontal(sign: 1)) }
        case .horizontalScroll:
            records = try makeHorizontalCommands(sign: 1, plan: plan, now: startTime)
                .map { try scrollRecord(command: $0, mode: .horizontal) }
        case .missionControl:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl, startTime: startTime)
        case .pageBack:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_LeftBracket), flags: .maskCommand, startTime: startTime)
        case .pageForward:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_RightBracket), flags: .maskCommand, startTime: startTime)
        case .zoomIn:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: [.maskCommand, .maskShift], startTime: startTime)
        case .zoomOut:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand, startTime: startTime)
        case .killSwitch:
            records = try unmarkedInputEvents(for: plan, startTime: startTime).map { try $0.logRecord() }
        case .gestureDrag, .gestureWheel, .gestureWheelThenKillSwitch, .normalAfterRelease:
            records = try unmarkedInputEvents(for: plan, startTime: startTime).map { try $0.logRecord() }
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

    private func scrollRecord(command: GestureCommand, mode: ScrollPostMode) throws -> InputLogRecord {
        let posted = mode.deltas(for: command)
        let phases = CGEventUtilities.phaseValues(for: command)
        return InputLogRecord(
            timestamp: try timestamp(command.timestamp),
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
    ) throws -> [InputLogRecord] {
        let sequence = ShortcutEventSequence.keyEvents(keyCode: keyCode, flags: flags)
        return try sequence.enumerated().map { offset, shortcutEvent in
            try keyRecord(
                typeName: shortcutEvent.typeName,
                type: shortcutEvent.type,
                keyCode: shortcutEvent.keyCode,
                flags: shortcutEvent.flags,
                time: startTime + Double(offset) * ShortcutEventSequence.interEventDelay,
                generatedByNapeGesture: generatedByNapeGesture
            )
        }
    }

    private func keyRecord(
        typeName: String,
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        time: TimeInterval,
        generatedByNapeGesture: Bool
    ) throws -> InputLogRecord {
        return InputLogRecord(
            timestamp: try timestamp(time),
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

    private func postUnmarkedInputEvents(_ events: [UnmarkedInputEvent], to pid: pid_t?) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
        guard let timestamps = MonotonicEventClock.validatedTimestampSequenceNanosecondsForPosting(
            fromSecondsSinceStartup: events.map(\.time)
        ) else {
            throw ToolError.invalidValue(
                "CGEvent timestamp",
                "現在の起動後単調時刻から60秒以内のイベント列を生成できませんでした。"
            )
        }

        var cursorPosition = currentPointerLocation()
        var preparedEvents: [(time: TimeInterval, event: CGEvent)] = []
        preparedEvents.reserveCapacity(events.count)

        for (plannedEvent, timestamp) in zip(events, timestamps) {
            guard let event = plannedEvent.makeCGEvent(
                source: source,
                cursorPosition: &cursorPosition,
                timestampNanoseconds: timestamp
            ) else {
                throw ToolError.invalidValue(
                    "CGEvent",
                    "イベント列を投稿前に全件生成できませんでした。"
                )
            }
            preparedEvents.append((time: plannedEvent.time, event: event))
        }

        var previousTime: TimeInterval?
        for preparedEvent in preparedEvents {
            if let previousTime {
                Thread.sleep(forTimeInterval: max(preparedEvent.time - previousTime, 0))
            }
            post(preparedEvent.event, to: pid)
            previousTime = preparedEvent.time
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

    private func timestamp(_ time: TimeInterval) throws -> UInt64 {
        guard let timestamp = MonotonicEventClock.timestampNanoseconds(
            fromSecondsSinceStartup: time
        ) else {
            throw ToolError.invalidValue("timestamp", String(time))
        }
        return timestamp
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

        switch target {
        case .finder:
            try activateApplication(bundleIdentifier: "com.apple.finder", displayName: "Finder")
        case .safari:
            try activateApplication(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        }
    }

    private func activateApplication(bundleIdentifier: String, displayName: String) throws {
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            activateRunningApplication(bundleIdentifier: bundleIdentifier)
        } else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw ToolError.targetApplicationNotFound(displayName)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            activateRunningApplication(bundleIdentifier: bundleIdentifier)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        throw ToolError.invalidValue("--target", "\(displayName) を前面化できませんでした。")
    }

    private func activateRunningApplication(bundleIdentifier: String) {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleIdentifier }?
            .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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
        guard let value = Double(raw), value.isFinite, value > 0 else {
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

private struct SystemTestPlan {
    private static let maximumStepCount = 256
    private static let maximumSequenceDuration: TimeInterval = 30

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

        guard steps <= Self.maximumStepCount else {
            throw ToolError.invalidValue(
                "--steps",
                "最大値は \(Self.maximumStepCount) です: \(steps)"
            )
        }
        guard interval <= Self.maximumSequenceDuration else {
            throw ToolError.invalidValue(
                "--interval",
                "最大値は \(Self.maximumSequenceDuration) 秒です: \(interval)"
            )
        }
        let sequenceDuration = Double(scenario.maximumTimestampIntervalCount(steps: steps)) * interval
        guard sequenceDuration.isFinite, sequenceDuration <= Self.maximumSequenceDuration else {
            throw ToolError.invalidValue(
                "system-test plan",
                "イベント列の最大時間は \(Self.maximumSequenceDuration) 秒です: \(sequenceDuration)"
            )
        }
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

private enum SystemTestScenario: String {
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
        case .gestureDrag,
             .gestureWheel,
             .gestureWheelThenKillSwitch,
             .normalAfterRelease:
            return true
        case .spaceLeft,
             .spaceRight,
             .horizontalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut,
             .killSwitch:
            return false
        }
    }

    func maximumTimestampIntervalCount(steps: Int) -> Int {
        switch self {
        case .spaceLeft, .spaceRight, .horizontalScroll:
            return max(steps - 1, 0)
        case .missionControl, .pageBack, .pageForward, .zoomIn, .zoomOut:
            return 0
        case .killSwitch:
            return 1
        case .gestureDrag, .gestureWheel:
            return steps + 1
        case .gestureWheelThenKillSwitch:
            return steps + 3
        case .normalAfterRelease:
            return steps + 7
        }
    }
}

private enum SystemTestTarget: String {
    case finder
    case safari
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

    func logRecord() throws -> InputLogRecord {
        guard let timestamp = MonotonicEventClock.timestampNanoseconds(
            fromSecondsSinceStartup: time
        ) else {
            throw ToolError.invalidValue("timestamp", String(time))
        }
        return InputLogRecord(
            timestamp: timestamp,
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

    func makeCGEvent(
        source: CGEventSource?,
        cursorPosition: inout CGPoint,
        timestampNanoseconds: UInt64
    ) -> CGEvent? {
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
            event?.location = cursorPosition
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

        guard let event else {
            return nil
        }
        event.timestamp = CGEventTimestamp(timestampNanoseconds)
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
