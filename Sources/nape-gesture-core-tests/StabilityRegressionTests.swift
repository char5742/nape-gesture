import Foundation
import NapeGestureCore

func runStabilityRegressionTests() {
    testFixedButtonStreamsReachOneTerminalWithoutChangingSamples()
    testUnsupportedAndAdditionalButtonsDoNotPolluteNeighboringSessions()
    testCancelAndTimeoutReachOneTerminalThenRestorePassthrough()
    testManualStopWinsAcrossSleepWakeAndManualRestartRecovers()
    testDuplicateOrOutOfOrderWakeDoesNotDestroyRecoveryState()
    testCursorMotionAssociationRetriesFailedTransitionsAndRestoresStartupBaseline()
    testSettingsMigrationPreservesOperationalSettingsAndIsIdempotent()
    testUnknownLegacyModeFailsBeforeCanonicalization()
}

private func testCursorMotionAssociationRetriesFailedTransitionsAndRestoresStartupBaseline() {
    var state = CursorMotionAssociationState()
    var calls: [Bool] = []

    let failedSuppression = state.suppress { enabled in
        calls.append(enabled)
        return false
    }
    expect(!failedSuppression && !state.isSuppressed, "cursor連動停止失敗時に抑制済みと誤記録しない")

    let suppression = state.suppress { enabled in
        calls.append(enabled)
        return true
    }
    let repeatedSuppression = state.suppress { enabled in
        calls.append(enabled)
        return true
    }
    expect(suppression && repeatedSuppression && state.isSuppressed, "cursor連動停止成功後の重複停止を冪等にする")
    expect(calls == [false, false], "cursor連動停止APIを失敗retry時だけ再実行する")

    let failedRestore = state.restore { enabled in
        calls.append(enabled)
        return false
    }
    expect(!failedRestore && state.isSuppressed, "cursor連動復元失敗時に未抑制と誤記録しない")

    let restore = state.restore { enabled in
        calls.append(enabled)
        return true
    }
    let repeatedRestore = state.restore { enabled in
        calls.append(enabled)
        return true
    }
    expect(restore && repeatedRestore && !state.isSuppressed, "cursor連動復元成功後の重複復元を冪等にする")
    expect(calls == [false, false, true, true], "cursor連動復元APIを失敗retry時だけ再実行する")

    let startupBaseline = state.restore(force: true) { enabled in
        calls.append(enabled)
        return true
    }
    expect(startupBaseline && !state.isSuppressed, "runtime開始時にcursor連動を既知の有効状態へ戻す")
    expect(calls.last == true && calls.count == 5, "startup baseline復元ではOS APIを必ず実行する")
}

private func stabilityTimestamp(_ nanoseconds: UInt64) -> MonotonicEventTimestamp {
    MonotonicEventTimestamp(nanosecondsSinceStartup: nanoseconds)
}

private func testFixedButtonStreamsReachOneTerminalWithoutChangingSamples() {
    let scenarios: [(label: String, button: MouseButton, gestureClass: FixedGestureClass)] = [
        ("button 3", .button3, .twoFingerScrollSwipe),
        ("button 4", .button4, .threeFingerSystemSwipe),
        ("button 5", .center, .pinch),
    ]

    for (index, scenario) in scenarios.enumerated() {
        let sessionID = UInt64(100 + index)
        var recognizer = FixedGestureInputRecognizer(
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0,
                maximumInactivityInterval: 0
            ),
            sessionSequence: TrackpadOutputSessionSequence(startingAt: sessionID)
        )
        let decisions = [
            recognizer.handle(
                .buttonDown(button: scenario.button, timestamp: stabilityTimestamp(100))
            ),
            recognizer.handle(
                .move(deltaX: -1.25, deltaY: 2.5, timestamp: stabilityTimestamp(101))
            ),
            recognizer.handle(
                .wheel(deltaX: 3.75, deltaY: -4.5, timestamp: stabilityTimestamp(101))
            ),
            recognizer.handle(
                .move(deltaX: -0.0, deltaY: 0.0, timestamp: stabilityTimestamp(102))
            ),
            recognizer.handle(
                .buttonUp(button: scenario.button, timestamp: stabilityTimestamp(103))
            ),
        ]
        let commands = decisions.flatMap(\.commands)

        expect(decisions.allSatisfy(\.shouldSuppressOriginal), "\(scenario.label)の変換対象列をすべて抑制する")
        expect(commands.count == decisions.count, "\(scenario.label)のsource sampleを1対1でcommandへ変換する")
        expect(commands.map(\.captureOrder) == [0, 1, 2, 3, 4], "\(scenario.label)のcapture orderをsource順で保持する")
        expect(
            commands.map(\.timestamp) == [100, 101, 101, 102, 103].map(stabilityTimestamp),
            "\(scenario.label)のtimestampを並べ替えず保持する"
        )
        expect(
            commands.map(\.sourceKind) == [.buttonDown, .move, .wheel, .move, .buttonUp],
            "\(scenario.label)のsource kindを変換しない"
        )
        expect(
            commands.allSatisfy { $0.sessionID == TrackpadOutputSessionID(rawValue: sessionID) },
            "\(scenario.label)の全sampleを同一sessionへ所属させる"
        )
        expect(commands.allSatisfy { $0.sourceButton == scenario.button }, "\(scenario.label)のsource buttonを固定する")
        expect(commands.allSatisfy { $0.gestureClass == scenario.gestureClass }, "\(scenario.label)のGestureClassを固定する")
        if commands.count == 5 {
            expect(
                commands[1].deltaX.bitPattern == (-1.25).bitPattern
                    && commands[1].deltaY.bitPattern == 2.5.bitPattern,
                "\(scenario.label)のmove X/Y量と符号をbit単位で保持する"
            )
            expect(
                commands[2].deltaX.bitPattern == 3.75.bitPattern
                    && commands[2].deltaY.bitPattern == (-4.5).bitPattern,
                "\(scenario.label)のwheel X/Y量と符号をbit単位で保持する"
            )
            expect(
                commands[3].deltaX.bitPattern == Double(-0.0).bitPattern,
                "\(scenario.label)の負のzero sampleも正規化せず保持する"
            )
        }
        expect(
            commands.filter { $0.phase == .ended || $0.phase == .cancelled }.count == 1,
            "\(scenario.label)の入力列にterminalを1件だけ生成する"
        )

        var machine = FixedGestureSessionMachine(
            sessionID: TrackpadOutputSessionID(rawValue: sessionID),
            sourceButton: scenario.button,
            gestureClass: scenario.gestureClass
        )
        for command in commands {
            expectNoThrow("\(scenario.label)のrecognizer出力をsession machineが受理する") {
                try machine.accept(command)
            }
        }
        let terminal = try? machine.requireTerminal()
        expect(terminal?.phase == .ended, "\(scenario.label)をrelease terminalへ収束させる")
        expect(terminal?.captureOrder == 4, "\(scenario.label)のterminal capture orderを保持する")
        expect(terminal?.timestamp == stabilityTimestamp(103), "\(scenario.label)のterminal timestampを保持する")

        let repeatedRelease = recognizer.handle(
            .buttonUp(button: scenario.button, timestamp: stabilityTimestamp(104))
        )
        expect(!repeatedRelease.shouldSuppressOriginal, "\(scenario.label)の二重releaseを抑制しない")
        expect(repeatedRelease.commands.isEmpty, "\(scenario.label)の二重releaseからterminalを再生成しない")
    }
}

private func testUnsupportedAndAdditionalButtonsDoNotPolluteNeighboringSessions() {
    let unsupportedDown = RawInputEvent.otherMouseButton(
        buttonNumber: 6,
        isDown: true,
        time: 1
    )
    let unsupportedUp = RawInputEvent.otherMouseButton(
        buttonNumber: 6,
        isDown: false,
        time: 2
    )
    expect(unsupportedDown == nil && unsupportedUp == nil, "button 6以降をgesture入力へ取り込まない")

    var recognizer = FixedGestureInputRecognizer(
        cancellation: GestureCancellationConfiguration(
            maximumDuration: 0,
            maximumInactivityInterval: 0
        ),
        sessionSequence: TrackpadOutputSessionSequence(startingAt: 200)
    )
    let unsupportedCGButton = recognizer.handle(
        .buttonDown(button: .button5, timestamp: stabilityTimestamp(10))
    )
    expect(!unsupportedCGButton.shouldSuppressOriginal, "対象外のCG buttonNumber 5を通常入力として通す")
    expect(unsupportedCGButton.commands.isEmpty && recognizer.isIdle, "対象外buttonでsessionを予約しない")

    let firstBegan = recognizer.handle(
        .buttonDown(button: .button3, timestamp: stabilityTimestamp(20))
    )
    let additionalDown = recognizer.handle(
        .buttonDown(button: .button4, timestamp: stabilityTimestamp(21))
    )
    let changed = recognizer.handle(
        .move(deltaX: 7, deltaY: -8, timestamp: stabilityTimestamp(22))
    )
    let additionalUp = recognizer.handle(
        .buttonUp(button: .button4, timestamp: stabilityTimestamp(23))
    )
    let firstEnded = recognizer.handle(
        .buttonUp(button: .button3, timestamp: stabilityTimestamp(24))
    )
    let secondBegan = recognizer.handle(
        .buttonDown(button: .center, timestamp: stabilityTimestamp(30))
    )

    expect(firstBegan.commands.first?.sessionID == TrackpadOutputSessionID(rawValue: 200), "最初の対応buttonでsessionを開始する")
    expect(!additionalDown.shouldSuppressOriginal && additionalDown.commands.isEmpty, "追加button downを変換せず通す")
    expect(!additionalUp.shouldSuppressOriginal && additionalUp.commands.isEmpty, "追加button upを変換せず通す")
    expect(changed.commands.first?.captureOrder == 1, "追加buttonを元sessionのcapture orderへ数えない")
    expect(changed.commands.first?.gestureClass == .twoFingerScrollSwipe, "追加buttonで元sessionのGestureClassを変えない")
    expect(firstEnded.commands.first?.captureOrder == 2, "元buttonのreleaseで欠落なくterminalへ進める")
    expect(firstEnded.commands.first?.phase == .ended, "元buttonだけがsessionを終了する")
    expect(secondBegan.commands.first?.sessionID == TrackpadOutputSessionID(rawValue: 201), "対象外・追加button後も次sessionを一度だけ発行する")
    expect(secondBegan.commands.first?.gestureClass == .pinch, "次のbutton 5を4本指classとして開始する")
}

private func testCancelAndTimeoutReachOneTerminalThenRestorePassthrough() {
    var cancelledRecognizer = FixedGestureInputRecognizer(
        cancellation: GestureCancellationConfiguration(
            maximumDuration: 0,
            maximumInactivityInterval: 0
        ),
        sessionSequence: TrackpadOutputSessionSequence(startingAt: 300)
    )
    let began = cancelledRecognizer.handle(
        .buttonDown(button: .button3, timestamp: stabilityTimestamp(100))
    )
    let changed = cancelledRecognizer.handle(
        .move(deltaX: 1, deltaY: 2, timestamp: stabilityTimestamp(101))
    )
    let cancelled = cancelledRecognizer.handle(
        .cancel(timestamp: stabilityTimestamp(102))
    )
    let cancellationCommands = [began, changed, cancelled].flatMap(\.commands)

    expect(cancelled.commands.count == 1, "明示cancelからterminalを1件だけ生成する")
    expect(cancelled.commands.first?.phase == .cancelled, "明示cancelをcancelled terminalにする")
    expect(cancelled.commands.first?.sourceKind == .cancellation, "明示cancelのsource kindを保持する")
    expect(cancelled.commands.first?.captureOrder == 2, "明示cancelをsource列の次のcapture orderに置く")
    expect(!cancelled.shouldSuppressOriginal, "内部cancel自体を通常mouse eventとして扱わない")
    expect(cancelledRecognizer.isIdle, "明示cancel直後にactive sessionを残さない")
    expect(cancelledRecognizer.pendingReleaseButton == .button3, "抑制済みdownのreleaseだけを待機する")

    var cancelledMachine = FixedGestureSessionMachine(
        sessionID: TrackpadOutputSessionID(rawValue: 300),
        sourceButton: .button3,
        gestureClass: .twoFingerScrollSwipe
    )
    for command in cancellationCommands {
        expectNoThrow("明示cancelまでの列をsession machineが受理する") {
            try cancelledMachine.accept(command)
        }
    }
    expect((try? cancelledMachine.requireTerminal())?.phase == .cancelled, "明示cancelを単一terminalとして確定する")

    let moveAfterCancel = cancelledRecognizer.handle(
        .move(deltaX: 9, deltaY: 10, timestamp: stabilityTimestamp(103))
    )
    let additionalBegan = cancelledRecognizer.handle(
        .buttonDown(button: .button4, timestamp: stabilityTimestamp(104))
    )
    let additionalEnded = cancelledRecognizer.handle(
        .buttonUp(button: .button4, timestamp: stabilityTimestamp(105))
    )
    let pendingRelease = cancelledRecognizer.handle(
        .buttonUp(button: .button3, timestamp: stabilityTimestamp(106))
    )
    let repeatedRelease = cancelledRecognizer.handle(
        .buttonUp(button: .button3, timestamp: stabilityTimestamp(107))
    )
    let recoveredBegan = cancelledRecognizer.handle(
        .buttonDown(button: .button4, timestamp: stabilityTimestamp(108))
    )

    expect(!moveAfterCancel.shouldSuppressOriginal && moveAfterCancel.commands.isEmpty, "cancel後のmoveを通常入力へ戻す")
    expect(!additionalBegan.shouldSuppressOriginal && additionalBegan.commands.isEmpty, "release待機中の追加button downを通す")
    expect(!additionalEnded.shouldSuppressOriginal && additionalEnded.commands.isEmpty, "release待機中の追加button upを通す")
    expect(pendingRelease.shouldSuppressOriginal && pendingRelease.commands.isEmpty, "抑制済みdownの対応releaseだけを一度抑制する")
    expect(!repeatedRelease.shouldSuppressOriginal && repeatedRelease.commands.isEmpty, "対応releaseを二重抑制しない")
    expect(recoveredBegan.commands.first?.sessionID == TrackpadOutputSessionID(rawValue: 301), "対応release後に新sessionを開始できる")

    var timeoutRecognizer = FixedGestureInputRecognizer(
        cancellation: GestureCancellationConfiguration(
            maximumDuration: 0.000_000_010,
            maximumInactivityInterval: 0
        ),
        sessionSequence: TrackpadOutputSessionSequence(startingAt: 400)
    )
    let timeoutBegan = timeoutRecognizer.handle(
        .buttonDown(button: .center, timestamp: stabilityTimestamp(1_000))
    )
    let timeoutChanged = timeoutRecognizer.handle(
        .wheel(deltaX: -3, deltaY: 4, timestamp: stabilityTimestamp(1_005))
    )
    let timeoutRelease = timeoutRecognizer.handle(
        .buttonUp(button: .center, timestamp: stabilityTimestamp(1_011))
    )
    let timeoutCommands = [timeoutBegan, timeoutChanged, timeoutRelease].flatMap(\.commands)

    expect(timeoutRelease.commands.count == 1, "release時timeoutからterminalを1件だけ生成する")
    expect(timeoutRelease.commands.first?.phase == .cancelled, "最大継続時間超過のreleaseをcancelledにする")
    expect(timeoutRelease.commands.first?.sourceKind == .cancellation, "timeout terminalを通常releaseと偽らない")
    expect(timeoutRelease.commands.first?.captureOrder == 2, "timeout terminalも連続capture orderを使う")
    expect(timeoutRecognizer.pendingReleaseButton == nil, "処理済みreleaseをtimeout後に再待機しない")

    var timeoutMachine = FixedGestureSessionMachine(
        sessionID: TrackpadOutputSessionID(rawValue: 400),
        sourceButton: .center,
        gestureClass: .pinch
    )
    for command in timeoutCommands {
        expectNoThrow("release timeoutまでの列をsession machineが受理する") {
            try timeoutMachine.accept(command)
        }
    }
    expect((try? timeoutMachine.requireTerminal())?.phase == .cancelled, "release timeoutを単一terminalとして確定する")

    let timeoutMove = timeoutRecognizer.handle(
        .move(deltaX: 5, deltaY: 6, timestamp: stabilityTimestamp(1_012))
    )
    let timeoutRepeatedRelease = timeoutRecognizer.handle(
        .buttonUp(button: .center, timestamp: stabilityTimestamp(1_013))
    )
    expect(!timeoutMove.shouldSuppressOriginal && timeoutMove.commands.isEmpty, "release timeout後のmoveを通常入力へ戻す")
    expect(
        !timeoutRepeatedRelease.shouldSuppressOriginal && timeoutRepeatedRelease.commands.isEmpty,
        "release timeout後にterminalを再生成しない"
    )
}

private func testManualStopWinsAcrossSleepWakeAndManualRestartRecovers() {
    var state = RuntimeRecoveryState()
    state.recordRuntimeStarted()

    let sleep = state.handleWillSleep(at: 10)
    let stop = state.requestManualStop(at: 11)
    let wake = state.handleDidWake(at: 20, retryDelay: 2)
    let staleRetry = state.retryIfReady(at: 30)
    let isStoppedManually: Bool
    if case .stopped(reason: .manualStop, stoppedAt: _) = state.mode {
        isStoppedManually = true
    } else {
        isStoppedManually = false
    }

    expect(sleep.shouldStopRuntime && isStoppedManually, "sleep中の手動停止をwake後も優先する")
    expect(stop.shouldStopRuntime && !stop.shouldStartRuntime, "sleep中の手動停止でruntime停止を要求する")
    expect(!wake.shouldStartRuntime && !wake.shouldStopRuntime, "手動停止後のwakeでruntimeを再開しない")
    expect(!state.autoRetryEnabled, "sleep中の手動停止で自動再試行を無効化する")
    expect(state.pendingRetry == nil && !state.shouldRetryAfterWake, "sleep中の手動停止でwake予約を完全に破棄する")
    expect(!staleRetry.shouldStartRuntime, "手動停止前のwake再試行を後から復活させない")

    let manualStart = state.requestManualStart(at: 40)
    state.recordRuntimeStarted()
    _ = state.handleWillSleep(at: 50)
    _ = state.handleDidWake(at: 60, retryDelay: 2)
    let recoveredRetry = state.retryIfReady(at: 62)

    expect(manualStart.shouldStartRuntime, "明示的な手動開始で停止状態を解除する")
    expect(recoveredRetry.shouldStartRuntime, "手動再開後の次回wakeでは自動復旧する")
    expect(
        state.mode == .starting(reason: .automaticRetry(.wake), requestedAt: 62),
        "手動再開後のwake retry理由を保持する"
    )
}

private func testDuplicateOrOutOfOrderWakeDoesNotDestroyRecoveryState() {
    var runningState = RuntimeRecoveryState()
    runningState.recordRuntimeStarted()
    _ = runningState.handleDidWake(at: 5, retryDelay: 1)

    expect(runningState.isRunning, "sleepを伴わないwake通知でrunning状態を停止へ変えない")
    expect(runningState.pendingRetry == nil, "sleepを伴わないwake通知で不要なretryを作らない")

    var retryState = RuntimeRecoveryState()
    retryState.recordRuntimeStarted()
    _ = retryState.handleWillSleep(at: 10)
    _ = retryState.handleDidWake(at: 20, retryDelay: 2)
    _ = retryState.handleDidWake(at: 20.1, retryDelay: 2)
    let retainedRetry = retryState.pendingRetry
    let retry = retryState.retryIfReady(at: 22.1)

    expect(
        retainedRetry?.reason == .wake && retry.shouldStartRuntime,
        "重複wake通知で既存retryを破棄せず、遅延到達時にruntimeを再開する"
    )
}

private func testSettingsMigrationPreservesOperationalSettingsAndIsIdempotent() {
    let sourceData = Data(
        """
        {
          "applicationOverrides": { "com.example.Editor": { "enabled": false } },
          "gesture": {
            "button3Mode": "none",
            "button4Mode": "twoFingerSwipe",
            "button5Mode": "systemSwipe",
            "deadZonePoints": 12,
            "dragSensitivity": 1.5,
            "wheelSensitivity": 0.75,
            "acceleration": {
              "isEnabled": true,
              "thresholdVelocity": 800,
              "exponent": 1.1,
              "maximumMultiplier": 2
            },
            "cancellation": {
              "maximumDuration": 7.25,
              "maximumInactivityInterval": 0.75,
              "offAxisCancelRatio": 0.5
            },
            "momentum": {
              "isEnabled": true,
              "minimumStartVelocity": 120,
              "stopVelocity": 7,
              "decayPerSecond": 0.1,
              "frameInterval": 0.01
            }
          },
          "targetDeviceAssociation": { "associationWindow": 0.075 },
          "targetDevices": [
            {
              "vendorID": 1452,
              "productID": 591,
              "manufacturerContains": "Keychron",
              "productContains": "Nape Pro",
              "transportContains": "USB",
              "primaryUsagePage": 1,
              "primaryUsage": 2
            }
          ],
          "requireMatchingTargetDevice": false
        }
        """.utf8
    )
    let originalData = sourceData
    let expectedMatcher = DeviceMatcher(
        vendorID: 1452,
        productID: 591,
        manufacturerContains: "Keychron",
        productContains: "Nape Pro",
        transportContains: "USB",
        primaryUsagePage: 1,
        primaryUsage: 2
    )

    expect(
        (try? SettingsMigration.requiresCanonicalRewrite(in: sourceData)) == true,
        "旧mode、tuning、application設定をcanonical migration対象にする"
    )
    guard let decoded = try? JSONDecoder().decode(NapeGestureSettings.self, from: sourceData) else {
        expect(false, "有効な旧設定をmigration前状態としてdecodeする")
        return
    }
    expect(SettingsValidator.migrationIssues(for: decoded).isEmpty, "有効な旧設定をcanonical化前に検証する")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let canonicalData = try? encoder.encode(decoded) else {
        expect(false, "旧設定からcanonical JSONを生成する")
        return
    }
    guard let canonical = try? JSONDecoder().decode(
        NapeGestureSettings.self,
        from: canonicalData
    ) else {
        expect(false, "生成したcanonical JSONを再読込する")
        return
    }

    expect(sourceData == originalData, "migration判定とdecode中に入力原本を変更しない")
    expect(
        (try? SettingsMigration.requiresCanonicalRewrite(in: canonicalData)) == false,
        "canonical JSONから廃止済みkeyを完全に除去する"
    )
    expect(
        canonical.targetDeviceAssociation.associationWindow.bitPattern == 0.075.bitPattern,
        "canonical化で対象device紐づけ時間を保持する"
    )
    expect(canonical.targetDevices == [expectedMatcher], "canonical化で対象device条件の原本値を保持する")
    expect(!canonical.requireMatchingTargetDevice, "canonical化で対象device一致要否を保持する")
    expect(
        canonical.gesture.cancellation.maximumDuration.bitPattern == 7.25.bitPattern
            && canonical.gesture.cancellation.maximumInactivityInterval.bitPattern
                == 0.75.bitPattern,
        "canonical化で安全なcancel設定を保持する"
    )
    expect(canonical.gesture.mode(for: .button3) == .twoFingerSwipe, "旧button 3 modeに依存せず固定対応へ戻す")
    expect(canonical.gesture.mode(for: .button4) == .systemSwipe, "旧button 4 modeに依存せず固定対応へ戻す")
    expect(canonical.gesture.mode(for: .button5) == .pinch, "旧button 5 modeに依存せず固定対応へ戻す")

    let root = (try? JSONSerialization.jsonObject(with: canonicalData)) as? [String: Any]
    let gesture = root?["gesture"] as? [String: Any]
    let cancellation = gesture?["cancellation"] as? [String: Any]
    expect(
        Set(root?.keys.map { $0 } ?? [])
            == [
                "gesture",
                "targetDeviceAssociation",
                "targetDevices",
                "requireMatchingTargetDevice",
            ],
        "canonical設定を現行top-level keyだけで保存する"
    )
    expect(Set(gesture?.keys.map { $0 } ?? []) == ["cancellation"], "canonical gestureから旧modeとtuningを除去する")
    expect(
        Set(cancellation?.keys.map { $0 } ?? [])
            == ["maximumDuration", "maximumInactivityInterval"],
        "canonical cancellationから旧off-axis設定を除去する"
    )

    let secondCanonicalData = try? encoder.encode(canonical)
    expect(secondCanonicalData == canonicalData, "canonical化を繰り返しても同じJSONへ収束する")
}

private func testUnknownLegacyModeFailsBeforeCanonicalization() {
    let sourceData = Data(
        """
        {
          "gesture": {
            "button3Mode": "unknownResultMode",
            "cancellation": {
              "maximumDuration": 10,
              "maximumInactivityInterval": 2
            }
          },
          "targetDevices": [ { "productContains": "Nape Pro" } ],
          "requireMatchingTargetDevice": true
        }
        """.utf8
    )
    let originalData = sourceData
    var decodingFailed = false
    do {
        _ = try JSONDecoder().decode(NapeGestureSettings.self, from: sourceData)
    } catch {
        decodingFailed = true
    }

    expect(
        (try? SettingsMigration.requiresCanonicalRewrite(in: sourceData)) == true,
        "未知の旧modeを含む原本もmigration対象として検出する"
    )
    expect(decodingFailed, "未知の旧modeを既知のGestureClassへ推測変換せず失敗する")
    expect(sourceData == originalData, "decode失敗時に設定原本を変更しない")
}
