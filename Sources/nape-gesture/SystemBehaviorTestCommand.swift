import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore
import NapeGestureDiagnosticOutput
import NapeGestureProductOutput

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
                  --direction left|right で生成delta方向を選べます。

              vertical-scroll
                  smoothScroll相当の垂直scroll / companion / momentum列を生成します。
                  --direction up|down で生成delta方向を選べます。

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
        let productTraceOutputPath = value("--product-trace-out", in: options)
        let productRunToken = value("--product-run-token", in: options)
        let productRepoHeadSHA = value("--product-repo-head-sha", in: options)
        let directionValue = value("--direction", in: options)
            ?? (scenario == .verticalScroll ? "up" : "right")
        let scrollSign: Int
        switch scenario {
        case .horizontalScroll:
            guard ["left", "right"].contains(directionValue) else {
                throw ToolError.invalidValue("--direction", directionValue)
            }
            scrollSign = directionValue == "left" ? -1 : 1
        case .verticalScroll:
            guard ["up", "down"].contains(directionValue) else {
                throw ToolError.invalidValue("--direction", directionValue)
            }
            scrollSign = directionValue == "up" ? -1 : 1
        default:
            if options.contains("--direction") {
                throw ToolError.invalidValue(
                    "--direction",
                    "horizontal-scrollまたはvertical-scroll scenarioでだけ指定できます。"
                )
            }
            scrollSign = 1
        }
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
        if productTraceOutputPath != nil,
           dryRun || ![.horizontalScroll, .verticalScroll].contains(scenario)
        {
            throw ToolError.invalidValue(
                "--product-trace-out",
                "実投稿するhorizontal-scrollまたはvertical-scroll scenarioでだけ指定できます。"
            )
        }
        let productTraceContext: ProductGestureOutputTraceContext?
        if productTraceOutputPath != nil {
            guard let productRunToken,
                  UUID(uuidString: productRunToken)?.uuidString.lowercased() == productRunToken
            else {
                throw ToolError.invalidValue(
                    "--product-run-token",
                    "--product-trace-outではcaptureと共通のcanonical lowercase UUIDが必要です。"
                )
            }
            guard let productRepoHeadSHA,
                  Self.isCanonicalGitObjectID(productRepoHeadSHA),
                  let scenarioID = scenario.productEvidenceScenarioID,
                  let context = ProductGestureOutputTraceContext(
                    captureRunToken: productRunToken,
                    scenarioID: scenarioID,
                    repoHeadSHA: productRepoHeadSHA,
                    executableSHA256: try TrackpadDriverEventLogger.runningExecutableSHA256()
                  )
            else {
                throw ToolError.invalidValue(
                    "--product-repo-head-sha",
                    "--product-trace-outでは完全なlowercase Git object IDが必要です。"
                )
            }
            productTraceContext = context
        } else {
            if productRunToken != nil || productRepoHeadSHA != nil {
                throw ToolError.invalidValue(
                    "product trace identity",
                    "--product-run-token / --product-repo-head-shaは--product-trace-outと併用してください。"
                )
            }
            productTraceContext = nil
        }

        print(plan.description)
        if dryRun {
            print("dry-run のためイベントは生成しません。")
            return
        }

        if let productTraceOutputPath {
            try prepareProductTraceOutput(path: productTraceOutputPath)
        }

        try AccessibilityPermission.ensurePrompted()
        try activateTargetIfNeeded(plan.target)
        Thread.sleep(forTimeInterval: 0.5)
        try execute(
            plan,
            productTraceOutputPath: productTraceOutputPath,
            productTraceContext: productTraceContext,
            scrollSign: scrollSign
        )
        print("シナリオを実行しました。`nape-gesture log` または画面挙動で差分を確認してください。")
    }

    private func execute(
        _ plan: SystemTestPlan,
        productTraceOutputPath: String?,
        productTraceContext: ProductGestureOutputTraceContext?,
        scrollSign: Int
    ) throws {
        let poster = DiagnosticEventPoster()
        let now = MonotonicEventClock.nowSeconds

        switch plan.scenario {
        case .spaceLeft:
            try postScrollCommands(
                makeHorizontalCommands(sign: -1, plan: plan, now: now),
                poster: poster,
                mode: .forcedHorizontal(sign: -1),
                interval: plan.interval
            )
        case .spaceRight:
            try postScrollCommands(
                makeHorizontalCommands(sign: 1, plan: plan, now: now),
                poster: poster,
                mode: .forcedHorizontal(sign: 1),
                interval: plan.interval
            )
        case .horizontalScroll:
            try postProductScrollCommands(
                makeHorizontalCommands(sign: scrollSign, plan: plan, now: now),
                interval: plan.interval,
                traceOutputPath: productTraceOutputPath,
                traceContext: productTraceContext
            )
        case .verticalScroll:
            try postProductScrollCommands(
                makeVerticalCommands(sign: scrollSign, plan: plan, now: now),
                interval: plan.interval,
                traceOutputPath: productTraceOutputPath,
                traceContext: productTraceContext
            )
        case .missionControl:
            try requireSuccessfulPost(poster.postMissionControl())
        case .pageBack:
            try requireSuccessfulPost(poster.postPageBack())
        case .pageForward:
            try requireSuccessfulPost(poster.postPageForward())
        case .zoomIn:
            try requireSuccessfulPost(poster.postZoomIn())
        case .zoomOut:
            try requireSuccessfulPost(poster.postZoomOut())
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

        return DiagnosticEventPoster.terminallyCompleteScrollCommands(
            commands,
            interval: plan.interval
        )
    }

    private func makeVerticalCommands(
        sign: Int,
        plan: SystemTestPlan,
        now: TimeInterval
    ) -> [GestureCommand] {
        let perStep = plan.amount / Double(plan.steps)
        let commands = (0..<plan.steps).map { index in
            let phase: GesturePhase
            if index == 0 {
                phase = .began
            } else if index == plan.steps - 1 {
                phase = .ended
            } else {
                phase = .changed
            }
            return GestureCommand(
                kind: .drag,
                phase: phase,
                direction: sign < 0 ? .up : .down,
                deltaX: 0,
                deltaY: Double(sign) * perStep,
                velocityX: 0,
                velocityY: Double(sign) * perStep / max(plan.interval, 0.001),
                timestamp: now + Double(index) * plan.interval
            )
        }
        return DiagnosticEventPoster.terminallyCompleteScrollCommands(
            commands,
            interval: plan.interval
        )
    }

    private func postScrollCommands(
        _ commands: [GestureCommand],
        poster: DiagnosticEventPoster,
        mode: ScrollPostMode,
        interval: TimeInterval
    ) throws {
        let result = poster.postScrollSequence(
            commands: commands,
            mode: mode,
            interval: interval
        )
        try requireSuccessfulPost(result)
        guard result.generatedEventCount == commands.count else {
            throw ToolError.invalidValue("CGEvent sequence", "期待件数のscroll eventを投稿できませんでした。")
        }
    }

    private func postProductScrollCommands(
        _ commands: [GestureCommand],
        interval: TimeInterval,
        traceOutputPath: String?,
        traceContext: ProductGestureOutputTraceContext?
    ) throws {
        guard let firstCommand = commands.first else {
            throw ToolError.invalidValue("product scroll command", "入力列が空です。")
        }
        var postedTrace: [ProductGestureOutputPostedEventTrace] = []
        let traceObserver: ProductPostedEventObserver? = traceOutputPath == nil
            ? nil
            : { postedTrace.append($0) }
        let adapter = TrackpadGestureOutputAdapter(
            contractData: TrackpadGestureOutputResources.loadContractData(),
            modelData: TrackpadGestureOutputResources.loadModelData(),
            traceContext: traceContext,
            postedEventObserver: traceObserver
        )
        guard adapter.supports(.scroll) else {
            throw ToolError.trackpadOutputContractUnavailable(
                adapter.capability.reason ?? "trackpad scroll product outputが未対応です。"
            )
        }

        let action: GestureAction = firstCommand.deltaX == 0
            ? .smoothScroll
            : .horizontalScroll
        let coordinator = ProductGestureSessionCoordinator(
            bindings: GestureBindings(
                dragUp: action,
                dragDown: action,
                dragLeft: action,
                dragRight: action,
                wheel: action
            ),
            output: adapter
        )
        guard coordinator.unsupportedRequiredFamilies.isEmpty else {
            throw ToolError.trackpadOutputContractUnavailable(
                "product scroll scenarioが要求するevent familyを出力できません。"
            )
        }

        func failAfterClosingSession(_ reason: String) throws -> Never {
            var cancellation = coordinator.cancelActive(
                reason: .outputFailure,
                at: MonotonicEventClock.nowSeconds
            )
            var retryCount = 0
            while cancellation.failure != nil && retryCount < 2 {
                retryCount += 1
                cancellation = coordinator.cancelActive(
                    reason: .outputFailure,
                    at: MonotonicEventClock.nowSeconds
                )
            }
            guard cancellation.failure == nil else {
                throw ToolError.trackpadOutputPostingFailed(
                    "\(reason); cancellation_failed=\(cancellation.failure?.rawValue ?? "unknown")"
                )
            }
            throw ToolError.trackpadOutputPostingFailed(reason)
        }

        for (index, command) in commands.enumerated() {
            if index > 0 {
                Thread.sleep(forTimeInterval: interval)
            }
            guard command.kind != .momentum, command.phase != .momentum else {
                try failAfterClosingSession("input列へmomentum commandを混在できません。")
            }
            var postingCommand = command
            postingCommand.timestamp = MonotonicEventClock.nowSeconds
            let post = coordinator.post(
                command: postingCommand,
                continuation: postingCommand.phase == .ended ? .momentum : nil
            )
            guard post.action == action,
                  post.result.failure == nil,
                  post.result.failedEventCreationCount == 0,
                  post.result.generatedEventCount == 3
            else {
                try failAfterClosingSession(
                    post.result.failure?.rawValue ?? "incomplete_product_scroll_batch"
                )
            }
        }

        let reference = commands.dropLast().last ?? firstCommand
        let momentumDeltas = [0.6, 0.3]
        for (index, scale) in momentumDeltas.enumerated() {
            Thread.sleep(forTimeInterval: interval)
            let post = coordinator.post(
                command: GestureCommand(
                    kind: .momentum,
                    phase: .momentum,
                    direction: reference.direction,
                    deltaX: reference.deltaX * scale,
                    deltaY: reference.deltaY * scale,
                    velocityX: reference.velocityX * scale,
                    velocityY: reference.velocityY * scale,
                    timestamp: MonotonicEventClock.nowSeconds
                )
            )
            guard post.action == action,
                  post.result.failure == nil,
                  post.result.failedEventCreationCount == 0,
                  post.result.generatedEventCount == 1
            else {
                try failAfterClosingSession(
                    post.result.failure?.rawValue
                        ?? "incomplete_product_momentum_batch_\(index)"
                )
            }
        }
        Thread.sleep(forTimeInterval: interval)
        let terminal = coordinator.post(
            command: GestureCommand(
                kind: .momentum,
                phase: .ended,
                direction: reference.direction,
                deltaX: 0,
                deltaY: 0,
                velocityX: 0,
                velocityY: 0,
                timestamp: MonotonicEventClock.nowSeconds
            )
        )
        guard terminal.action == action,
              terminal.result.failure == nil,
              terminal.result.failedEventCreationCount == 0,
              terminal.result.generatedEventCount == 1
        else {
            try failAfterClosingSession(
                terminal.result.failure?.rawValue ?? "missing_product_momentum_terminal"
            )
        }
        if let traceOutputPath {
            try writeProductPostedTrace(postedTrace, to: traceOutputPath)
        }
    }

    private func writeProductPostedTrace(
        _ trace: [ProductGestureOutputPostedEventTrace],
        to path: String
    ) throws {
        guard !trace.isEmpty,
              trace.enumerated().allSatisfy({ $0.element.postIndex == UInt64($0.offset) })
        else {
            throw ToolError.invalidValue(
                "product posted trace",
                "投稿順が0始まり連続ではありません。"
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for record in trace {
            data.append(try encoder.encode(record))
            data.append(0x0A)
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func prepareProductTraceOutput(path: String) throws {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return
        }
        guard !isDirectory.boolValue else {
            throw ToolError.invalidValue(
                "--product-trace-out",
                "出力先がdirectoryです: \(path)"
            )
        }
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw ToolError.invalidValue(
                "--product-trace-out",
                "既存traceを除去できません: \(error.localizedDescription)"
            )
        }
    }

    private func requireSuccessfulPost(_ result: DiagnosticEventPostResult) throws {
        guard result.completedSuccessfully, result.generatedEventCount > 0 else {
            throw ToolError.invalidValue(
                "CGEvent sequence",
                "event作成または投稿に失敗し、release / terminalへ完全収束できませんでした。"
            )
        }
    }

    private func writeLogJSON(for plan: SystemTestPlan, to outputPath: String?) throws {
        let now = MonotonicEventClock.now
        let roundingMargin = 2 / TimeInterval(MonotonicEventClock.nanosecondsPerSecond)
        guard plan.maximumPlannedOffset + roundingMargin <= now.secondsSinceStartup else {
            throw ToolError.invalidValue(
                "timestamp",
                "system-testのoffsetが現在bootの起動後時刻上限を超えます。"
            )
        }
        let startTime = now.secondsSinceStartup - plan.maximumPlannedOffset - roundingMargin
        let records = try logRecords(for: plan, startTime: startTime)
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
        case .verticalScroll:
            records = try makeVerticalCommands(sign: -1, plan: plan, now: startTime)
                .map { try scrollRecord(command: $0, mode: .free) }
        case .missionControl:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl, startTime: startTime)
        case .pageBack:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand, startTime: startTime)
        case .pageForward:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand, startTime: startTime)
        case .zoomIn:
            records = try shortcutRecords(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand, startTime: startTime)
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
        [
            try keyRecord(
                typeName: "keyDown",
                type: .keyDown,
                keyCode: keyCode,
                flags: flags,
                time: startTime,
                generatedByNapeGesture: generatedByNapeGesture
            ),
            try keyRecord(
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
    ) throws -> InputLogRecord {
        InputLogRecord(
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
             .verticalScroll,
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
        guard !events.isEmpty,
              events.allSatisfy({ $0.time.isFinite && $0.time >= 0 }),
              zip(events, events.dropFirst()).allSatisfy({ pair in
                  pair.0.time <= pair.1.time
              })
        else {
            throw ToolError.invalidValue("CGEvent sequence", "未マーク入力列の時刻順序が不正です。")
        }

        let source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
        var cursorPosition = currentPointerLocation()
        var previousTime: TimeInterval?
        var preparedEvents: [DiagnosticPreparedEvent] = []
        preparedEvents.reserveCapacity(events.count)

        for plannedEvent in events {
            guard let event = plannedEvent.makeCGEvent(source: source, cursorPosition: &cursorPosition) else {
                throw ToolError.invalidValue(
                    "CGEvent sequence",
                    "イベント列を投稿前に全件生成できませんでした。"
                )
            }
            let domains = plannedEvent.releaseDomains
            preparedEvents.append(
                DiagnosticPreparedEvent(
                    event: event,
                    delayAfterPrevious: previousTime.map { plannedEvent.time - $0 } ?? 0,
                    opensReleaseDomains: domains.opens,
                    closesReleaseDomains: domains.closes
                )
            )
            previousTime = plannedEvent.time
        }

        let poster = DiagnosticEventPoster(postEvent: { event in
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cghidEventTap)
            }
            return true
        })
        let result = poster.postPreparedSequence(preparedEvents)
        try requireSuccessfulPost(result)
        guard result.generatedEventCount == preparedEvents.count else {
            throw ToolError.invalidValue("CGEvent sequence", "期待件数の未マーク入力を投稿できませんでした。")
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
        guard let timestamp = MonotonicEventClock.timestamp(fromSecondsSinceStartup: time) else {
            throw ToolError.invalidValue("timestamp", "現在boot内の起動後時刻ではありません: \(time)")
        }
        return timestamp.nanosecondsSinceStartup
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

    private static func isCanonicalGitObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
        }
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

    var maximumPlannedOffset: TimeInterval {
        let intervalCount: TimeInterval
        switch scenario {
        case .spaceLeft, .spaceRight, .horizontalScroll, .verticalScroll:
            intervalCount = steps == 1 ? 1 : max(Double(steps) - 1, 0)
        case .missionControl, .pageBack, .pageForward, .zoomIn, .zoomOut:
            return 0.01
        case .killSwitch:
            intervalCount = 1
        case .gestureDrag, .gestureWheel:
            intervalCount = Double(steps) + 1
        case .gestureWheelThenKillSwitch:
            intervalCount = Double(steps) + 3
        case .normalAfterRelease:
            intervalCount = Double(steps) + 7
        }
        return intervalCount * interval
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

private enum SystemTestScenario: String {
    case spaceLeft = "space-left"
    case spaceRight = "space-right"
    case horizontalScroll = "horizontal-scroll"
    case verticalScroll = "vertical-scroll"
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
             .verticalScroll,
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
             .verticalScroll,
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
             .verticalScroll,
             .missionControl,
             .pageBack,
             .pageForward,
             .zoomIn,
             .zoomOut,
             .killSwitch:
            return false
        }
    }

    var productEvidenceScenarioID: String? {
        switch self {
        case .horizontalScroll:
            "pure-trackpad-horizontal-scroll"
        case .verticalScroll:
            "pure-trackpad-vertical-scroll"
        case .spaceLeft,
             .spaceRight,
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
            nil
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
        guard let timestamp = MonotonicEventClock.timestamp(fromSecondsSinceStartup: time) else {
            throw ToolError.invalidValue("timestamp", "現在boot内の起動後時刻ではありません: \(time)")
        }
        return InputLogRecord(
            timestamp: timestamp.nanosecondsSinceStartup,
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

        guard let event else {
            return nil
        }
        return event
    }

    var releaseDomains: (
        opens: Set<DiagnosticEventReleaseDomain>,
        closes: Set<DiagnosticEventReleaseDomain>
    ) {
        switch type {
        case .keyDown:
            return ([.key(keyCode)], [])
        case .keyUp:
            return ([], [.key(keyCode)])
        case .leftMouseDown:
            return ([.mouseButton(0)], [])
        case .leftMouseUp:
            return ([], [.mouseButton(0)])
        case .rightMouseDown:
            return ([.mouseButton(1)], [])
        case .rightMouseUp:
            return ([], [.mouseButton(1)])
        case .otherMouseDown:
            return ([.mouseButton(buttonNumber)], [])
        case .otherMouseUp:
            return ([], [.mouseButton(buttonNumber)])
        default:
            return ([], [])
        }
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
