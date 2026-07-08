import Foundation
import NapeGestureCore

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) -> Bool {
    if condition() {
        return true
    }
    fputs("失敗: \(message) (\(file):\(line))\n", stderr)
    failures += 1
    return false
}

@discardableResult
func expectApproximatelyEqual(
    _ actual: Double?,
    _ expected: Double,
    tolerance: Double = 0.000001,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) -> Bool {
    guard let actual else {
        fputs("失敗: \(message)。実測値がありません (\(file):\(line))\n", stderr)
        failures += 1
        return false
    }
    if abs(actual - expected) <= tolerance {
        return true
    }
    fputs("失敗: \(message)。期待値 \(expected)、実測値 \(actual) (\(file):\(line))\n", stderr)
    failures += 1
    return false
}

var failures = 0

func testPassesThroughWhenActivationButtonIsNotPressed() {
    var recognizer = GestureRecognizer(configuration: .default)

    let decision = recognizer.handle(.move(deltaX: 20, deltaY: 0, time: 1))

    expect(!decision.shouldSuppressOriginal, "通常移動は通過する")
    expect(decision.commands.isEmpty, "通常移動ではコマンドを出さない")
    expect(recognizer.isIdle, "通常移動後も idle のまま")
}

func testActivationButtonSuppressesOriginalInputBeforeThreshold() {
    var recognizer = GestureRecognizer(configuration: .default)

    let down = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let smallMove = recognizer.handle(.move(deltaX: 2, deltaY: 1, time: 1.01))

    expect(down.shouldSuppressOriginal, "ジェスチャーボタン押下は抑制する")
    expect(smallMove.shouldSuppressOriginal, "デッドゾーン内の移動も抑制する")
    expect(smallMove.commands.isEmpty, "デッドゾーン内ではジェスチャーを開始しない")
}

func testDragBeginsAfterDeadZoneAndLocksDominantDirection() {
    var recognizer = GestureRecognizer(
        configuration: GestureConfiguration(deadZonePoints: 5, directionLockRatio: 1.2)
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let decision = recognizer.handle(.move(deltaX: -7, deltaY: 1, time: 1.02))

    expect(decision.shouldSuppressOriginal, "ジェスチャー成立後も元イベントを抑制する")
    expect(decision.commands.count == 1, "開始コマンドを1つ出す")
    expect(decision.commands.first?.kind == .drag, "ドラッグジェスチャーとして扱う")
    expect(decision.commands.first?.phase == .began, "開始フェーズを出す")
    expect(decision.commands.first?.direction == .left, "支配方向を左にロックする")
}

func testActiveDragEmitsChangedThenEnded() {
    var recognizer = GestureRecognizer(configuration: GestureConfiguration(deadZonePoints: 3))

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 4, deltaY: 0, time: 1.01))
    let changed = recognizer.handle(.move(deltaX: 2, deltaY: 0, time: 1.02))
    let ended = recognizer.handle(.buttonUp(button: .button4, time: 1.03))

    expect(changed.commands.first?.phase == .changed, "継続フェーズを出す")
    expect(ended.commands.first?.phase == .ended, "ボタン解放で終了フェーズを出す")
    expect(recognizer.isIdle, "終了後は通常状態へ戻る")
}

func testAccelerationScalesFastDragDeltas() {
    var recognizer = GestureRecognizer(
        configuration: GestureConfiguration(
            deadZonePoints: 1,
            acceleration: GestureAccelerationConfiguration(
                isEnabled: true,
                thresholdVelocity: 100,
                exponent: 1,
                maximumMultiplier: 3
            ),
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0,
                maximumInactivityInterval: 0,
                offAxisCancelRatio: 0
            )
        )
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let began = recognizer.handle(.move(deltaX: 2, deltaY: 0, time: 1.01))
    let changed = recognizer.handle(.move(deltaX: 3, deltaY: 0, time: 1.02))

    expectApproximatelyEqual(began.commands.first?.deltaX, 4, "しきい値超過分に応じて開始デルタへ加速度を適用する")
    expectApproximatelyEqual(changed.commands.first?.deltaX, 9, "最大倍率で継続デルタを丸める")
}

func testAccelerationDoesNotScaleBelowThreshold() {
    var recognizer = GestureRecognizer(
        configuration: GestureConfiguration(
            deadZonePoints: 1,
            acceleration: GestureAccelerationConfiguration(
                isEnabled: true,
                thresholdVelocity: 1_000,
                exponent: 1,
                maximumMultiplier: 3
            )
        )
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let decision = recognizer.handle(.move(deltaX: 2, deltaY: 0, time: 1.01))

    expect(decision.commands.first?.deltaX == 2, "しきい値未満では加速度を適用しない")
}

func testDragCancelsWhenMaximumDurationIsExceeded() {
    var recognizer = GestureRecognizer(
        configuration: GestureConfiguration(
            deadZonePoints: 3,
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0.05,
                maximumInactivityInterval: 0,
                offAxisCancelRatio: 0
            )
        )
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 4, deltaY: 0, time: 1.01))
    let decision = recognizer.handle(.buttonUp(button: .button4, time: 1.1))

    expect(decision.commands.first?.phase == .cancelled, "最大継続時間を超えたらキャンセル終了する")
    expect(recognizer.isIdle, "最大継続時間キャンセル後は idle に戻る")
}

func testDragCancelsWhenInactivityIsExceeded() {
    var recognizer = GestureRecognizer(
        configuration: GestureConfiguration(
            deadZonePoints: 3,
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0,
                maximumInactivityInterval: 0.05,
                offAxisCancelRatio: 0
            )
        )
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 4, deltaY: 0, time: 1.01))
    let decision = recognizer.handle(.move(deltaX: 1, deltaY: 0, time: 1.2))

    expect(decision.commands.first?.phase == .cancelled, "無入力時間を超えた次の入力でキャンセルする")
    expect(recognizer.isIdle, "無入力キャンセル後は idle に戻る")
}

func testDragCancelsWhenOffAxisMovementExceedsRatio() {
    var recognizer = GestureRecognizer(
        configuration: GestureConfiguration(
            deadZonePoints: 3,
            directionLockRatio: 1.1,
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0,
                maximumInactivityInterval: 0,
                offAxisCancelRatio: 0.5
            )
        )
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 10, deltaY: 0, time: 1.01))
    let decision = recognizer.handle(.move(deltaX: 0, deltaY: 8, time: 1.02))

    expect(decision.commands.first?.phase == .cancelled, "方向ロック後の軸ずれが比率を超えたらキャンセルする")
    expect(recognizer.isIdle, "軸ずれキャンセル後は idle に戻る")
}

func testWheelGestureIsScopedToActivationButton() {
    var recognizer = GestureRecognizer(configuration: .default)

    let normalWheel = recognizer.handle(.wheel(deltaX: 0, deltaY: -120, time: 1))
    _ = recognizer.handle(.buttonDown(button: .button4, time: 2))
    let gestureWheel = recognizer.handle(.wheel(deltaX: 0, deltaY: -120, time: 2.01))

    expect(!normalWheel.shouldSuppressOriginal, "通常ホイールは通過する")
    expect(gestureWheel.shouldSuppressOriginal, "ジェスチャーボタン中のホイールは抑制する")
    expect(gestureWheel.commands.first?.kind == .wheel, "ホイールジェスチャーを出す")
    expect(gestureWheel.commands.first?.phase == .began, "ホイール開始フェーズを出す")
}

func testMomentumDoesNotStartBelowMinimumVelocity() {
    var engine = MomentumEngine(configuration: MomentumConfiguration(minimumStartVelocity: 100))
    let command = GestureCommand(
        kind: .drag,
        phase: .ended,
        direction: .right,
        deltaX: 0,
        deltaY: 0,
        velocityX: 20,
        velocityY: 0,
        timestamp: 1
    )

    engine.start(from: command)

    expect(engine.state == .idle, "最低速度未満では慣性を開始しない")
}

func testMomentumDecaysAndEventuallyEnds() {
    var engine = MomentumEngine(
        configuration: MomentumConfiguration(
            minimumStartVelocity: 10,
            stopVelocity: 1,
            decayPerSecond: 0.01,
            frameInterval: 0.1
        )
    )
    let command = GestureCommand(
        kind: .drag,
        phase: .ended,
        direction: .right,
        deltaX: 0,
        deltaY: 0,
        velocityX: 100,
        velocityY: 0,
        timestamp: 1
    )

    engine.start(from: command)
    let first = engine.tick(at: 1.1)

    expect(first?.kind == .momentum, "慣性コマンドを出す")
    expect(first?.phase == .momentum, "慣性フェーズを出す")
    expect((first?.velocityX ?? 100) < 100, "速度が減衰する")

    var ended = false
    for step in 2...80 {
        if engine.tick(at: 1 + Double(step) * 0.1)?.phase == .ended {
            ended = true
            break
        }
    }

    expect(ended, "十分な時間後に慣性が終了する")
    expect(engine.state == .idle, "慣性終了後は idle に戻る")
}

func testDeviceMatcherMatchesConfiguredDevice() {
    let device = DeviceIdentity(
        manufacturer: "Example",
        product: "Nape Pro Mouse",
        vendorID: 123,
        productID: 456,
        transport: "Bluetooth",
        primaryUsagePage: 1,
        primaryUsage: 2
    )

    let matcher = DeviceMatcher(vendorID: 123, productContains: "nape pro")
    let nonMatcher = DeviceMatcher(vendorID: 999, productContains: "nape pro")

    expect(matcher.matches(device), "vendorID と製品名で対象デバイスに一致する")
    expect(!nonMatcher.matches(device), "vendorID が違うデバイスには一致しない")
}

func testDeviceMatcherMatchesUsageWhenConfigured() {
    let device = DeviceIdentity(
        manufacturer: "Example",
        product: "Composite Input",
        vendorID: 123,
        productID: 456,
        transport: "Bluetooth",
        primaryUsagePage: 1,
        primaryUsage: 2
    )

    let matcher = DeviceMatcher(vendorID: 123, primaryUsagePage: 1, primaryUsage: 2)
    let nonMatcher = DeviceMatcher(vendorID: 123, primaryUsagePage: 12, primaryUsage: 1)

    expect(matcher.matches(device), "usagePage と usage で対象デバイスに一致する")
    expect(!nonMatcher.matches(device), "usage 条件が違うデバイスには一致しない")
}

func testDeviceMatcherConditionPresenceIgnoresEmptyText() {
    expect(!DeviceMatcher(productContains: "").hasAnyCondition, "空文字の製品名条件は未指定として扱う")
    expect(DeviceMatcher(vendorID: 123).hasAnyCondition, "vendorID があれば条件ありとして扱う")
    expect(DeviceMatcher(primaryUsagePage: 1, primaryUsage: 2).hasAnyCondition, "usage 条件があれば条件ありとして扱う")
}

func testDeviceMatcherWithoutConditionsDoesNotMatchEverything() {
    let device = DeviceIdentity(
        manufacturer: "Example",
        product: "Nape Pro Mouse",
        vendorID: 123,
        productID: 456,
        transport: "Bluetooth",
        primaryUsagePage: 1,
        primaryUsage: 2
    )

    expect(!DeviceMatcher().matches(device), "条件なし matcher は全デバイス一致として扱わない")
    expect(!DeviceMatcher(productContains: "").matches(device), "空文字条件だけの matcher は全デバイス一致として扱わない")
}

func testDeviceIdentityEncodesStableID() {
    let device = DeviceIdentity(
        manufacturer: "Example Maker",
        product: "Nape Pro Mouse",
        vendorID: 123,
        productID: 456,
        transport: "Bluetooth",
        primaryUsagePage: 1,
        primaryUsage: 2
    )

    let data = try? JSONEncoder().encode(device)
    let json = data.map { String(decoding: $0, as: UTF8.self) } ?? ""

    expect(json.contains("\"stableID\""), "デバイス JSON に stableID を含める")
    expect(json.contains("vendor=123;product=456"), "stableID に vendor/product を含める")
}

func testGestureConfigurationDecodesOldJSONWithDefaults() {
    let json = """
    {
      "activationButton" : 4,
      "deadZonePoints" : 8,
      "directionLockRatio" : 1.35,
      "dragSensitivity" : 1,
      "wheelSensitivity" : 1,
      "bindings" : {
        "dragDown" : "smoothScroll",
        "dragLeft" : "spaceLeft",
        "dragRight" : "spaceRight",
        "dragUp" : "missionControl",
        "wheel" : "horizontalScroll"
      },
      "momentum" : {
        "decayPerSecond" : 0.08,
        "frameInterval" : 0.008333333333333333,
        "isEnabled" : true,
        "minimumStartVelocity" : 140,
        "stopVelocity" : 8
      }
    }
    """

    let configuration = try? JSONDecoder().decode(GestureConfiguration.self, from: Data(json.utf8))

    expect(configuration?.acceleration == .default, "古い設定JSONにはデフォルトの加速度設定を補う")
    expect(configuration?.cancellation == .default, "古い設定JSONにはデフォルトのキャンセル設定を補う")
    expect(configuration?.directionLockRatio == 1.35, "古い設定JSONの既存値を維持する")
}

func testSettingsValidatorAcceptsTemplateSettings() {
    expect(SettingsValidator.isValid(.template), "テンプレート設定は有効")
}

func testSettingsValidatorRejectsUnsafeGestureValues() {
    let settings = NapeGestureSettings(
        gesture: GestureConfiguration(
            deadZonePoints: -1,
            directionLockRatio: 0.5,
            dragSensitivity: 0,
            wheelSensitivity: -1,
            acceleration: GestureAccelerationConfiguration(
                isEnabled: true,
                thresholdVelocity: -1,
                exponent: -1,
                maximumMultiplier: 0
            ),
            cancellation: GestureCancellationConfiguration(
                maximumDuration: -1,
                maximumInactivityInterval: -1,
                offAxisCancelRatio: -1
            ),
            momentum: MomentumConfiguration(
                isEnabled: true,
                minimumStartVelocity: -1,
                stopVelocity: -1,
                decayPerSecond: 2,
                frameInterval: 0
            )
        ),
        targetDevices: [DeviceMatcher(productContains: "Nape Pro")],
        requireMatchingTargetDevice: true
    )

    let paths = Set(SettingsValidator.issues(for: settings).map(\.path))

    expect(paths.contains("gesture.deadZonePoints"), "負のデッドゾーンを拒否する")
    expect(paths.contains("gesture.directionLockRatio"), "1未満の方向ロック比を拒否する")
    expect(paths.contains("gesture.dragSensitivity"), "0以下のドラッグ感度を拒否する")
    expect(paths.contains("gesture.wheelSensitivity"), "0以下のホイール感度を拒否する")
    expect(paths.contains("gesture.acceleration.thresholdVelocity"), "負の加速度しきい値を拒否する")
    expect(paths.contains("gesture.acceleration.exponent"), "負の加速度指数を拒否する")
    expect(paths.contains("gesture.acceleration.maximumMultiplier"), "1未満の加速度最大倍率を拒否する")
    expect(paths.contains("gesture.cancellation.maximumDuration"), "負の最大継続時間を拒否する")
    expect(paths.contains("gesture.cancellation.maximumInactivityInterval"), "負の無入力時間を拒否する")
    expect(paths.contains("gesture.cancellation.offAxisCancelRatio"), "負の軸ずれ比を拒否する")
    expect(paths.contains("gesture.momentum.minimumStartVelocity"), "負の慣性開始速度を拒否する")
    expect(paths.contains("gesture.momentum.stopVelocity"), "負の慣性停止速度を拒否する")
    expect(paths.contains("gesture.momentum.decayPerSecond"), "範囲外の慣性減衰率を拒否する")
    expect(paths.contains("gesture.momentum.frameInterval"), "0以下の慣性フレーム間隔を拒否する")
}

func testSettingsValidatorRejectsMissingRequiredTargetMatcher() {
    let settings = NapeGestureSettings(
        gesture: .default,
        targetDevices: [],
        requireMatchingTargetDevice: true
    )

    let issues = SettingsValidator.issues(for: settings)

    expect(issues.contains { $0.path == "targetDevices" }, "対象一致必須時は空の対象条件を拒否する")
}

func testSettingsValidatorRejectsInvalidTargetMatcherValues() {
    let settings = NapeGestureSettings(
        gesture: .default,
        targetDevices: [
            DeviceMatcher(vendorID: -1),
            DeviceMatcher()
        ],
        requireMatchingTargetDevice: true
    )

    let paths = Set(SettingsValidator.issues(for: settings).map(\.path))

    expect(paths.contains("targetDevices[0].vendorID"), "負の vendorID を拒否する")
    expect(paths.contains("targetDevices[1]"), "空の対象条件を拒否する")
}

func testInputLogAnalyzerSuggestsDeadZone() {
    let records = [
        InputLogRecord(
            timestamp: 1,
            typeName: "mouseMoved",
            typeRaw: 5,
            generatedByNapeGesture: false,
            buttonNumber: 0,
            deltaX: 1,
            deltaY: 1,
            scrollDeltaX: 0,
            scrollDeltaY: 0,
            pointDeltaX: 0,
            pointDeltaY: 0,
            scrollPhase: 0,
            momentumPhase: 0,
            isContinuous: 0,
            keyCode: 0,
            flags: 0
        ),
        InputLogRecord(
            timestamp: 2,
            typeName: "otherMouseDragged",
            typeRaw: 27,
            generatedByNapeGesture: false,
            buttonNumber: 4,
            deltaX: 8,
            deltaY: 0,
            scrollDeltaX: 0,
            scrollDeltaY: 0,
            pointDeltaX: 0,
            pointDeltaY: 0,
            scrollPhase: 0,
            momentumPhase: 0,
            isContinuous: 0,
            keyCode: 0,
            flags: 0
        ),
        InputLogRecord(
            timestamp: 3,
            typeName: "scrollWheel",
            typeRaw: 22,
            generatedByNapeGesture: true,
            buttonNumber: 0,
            deltaX: 0,
            deltaY: 0,
            scrollDeltaX: 0,
            scrollDeltaY: -120,
            pointDeltaX: 0,
            pointDeltaY: -12,
            scrollPhase: 2,
            momentumPhase: 0,
            isContinuous: 1,
            keyCode: 0,
            flags: 0
        )
    ]

    let analysis = InputLogAnalyzer.analyze(records)

    expect(analysis.totalEvents == 3, "総イベント数を数える")
    expect(analysis.generatedEvents == 1, "生成イベント数を数える")
    expect(analysis.moveEvents == 2, "移動イベント数を数える")
    expect(analysis.scrollEvents == 1, "スクロールイベント数を数える")
    expect(analysis.preciseScrollEvents == 1, "precise/continuous スクロールを数える")
    expect(analysis.preciseScrollRatio == 1, "precise/continuous 率を出す")
    expect(analysis.scrollDeltaYTotal == -120, "scrollDelta 合計を出す")
    expect(analysis.pointDeltaYTotal == -12, "pointDelta 合計を出す")
    expect(analysis.suggestedDeadZonePoints >= 4, "deadZone 候補を出す")
}

func testInputLogRecordDecodesLegacyGeneratedField() {
    let json = """
    {
      "timestamp": 1,
      "typeName": "scrollWheel",
      "typeRaw": 22,
      "generatedByMacGesture": true,
      "buttonNumber": 0,
      "deltaX": 0,
      "deltaY": 0,
      "scrollDeltaX": 10,
      "scrollDeltaY": 0,
      "pointDeltaX": 10,
      "pointDeltaY": 0,
      "scrollPhase": 4,
      "momentumPhase": 0,
      "isContinuous": 1,
      "keyCode": 0,
      "flags": 0
    }
    """

    let record = try? JSONDecoder().decode(InputLogRecord.self, from: Data(json.utf8))
    let encoded = record.flatMap { try? JSONEncoder().encode($0) }
    let encodedText = encoded.map { String(decoding: $0, as: UTF8.self) } ?? ""

    expect(record?.generatedByNapeGesture == true, "旧 generatedByMacGesture フィールドを読み込む")
    expect(encodedText.contains("generatedByNapeGesture"), "エンコード時は新フィールド名を使う")
    expect(!encodedText.contains("generatedByMacGesture"), "エンコード時は旧フィールド名を出さない")
}

func testInputLogAnalyzerComparesBaselineAndCandidate() {
    let baseline = [
        InputLogRecord(
            timestamp: 1,
            typeName: "scrollWheel",
            typeRaw: 22,
            generatedByNapeGesture: false,
            buttonNumber: 0,
            deltaX: 0,
            deltaY: 0,
            scrollDeltaX: 0,
            scrollDeltaY: -120,
            pointDeltaX: 0,
            pointDeltaY: -12,
            scrollPhase: 1,
            momentumPhase: 0,
            isContinuous: 1,
            keyCode: 0,
            flags: 0
        )
    ]
    let candidate = [
        InputLogRecord(
            timestamp: 2,
            typeName: "scrollWheel",
            typeRaw: 22,
            generatedByNapeGesture: true,
            buttonNumber: 0,
            deltaX: 0,
            deltaY: 0,
            scrollDeltaX: 0,
            scrollDeltaY: -120,
            pointDeltaX: 0,
            pointDeltaY: -12,
            scrollPhase: 2,
            momentumPhase: 0,
            isContinuous: 1,
            keyCode: 0,
            flags: 0
        )
    ]

    let comparison = InputLogAnalyzer.compare(baseline: baseline, candidate: candidate)

    expect(comparison.generatedEventDelta == 1, "生成イベント数差を出す")
    expect(comparison.scrollEventDelta == 0, "スクロールイベント数差を出す")
    expect(comparison.pointDeltaYTotalDelta == 0, "pointDelta 合計差を出す")
    expect(comparison.scrollPhaseDelta["1"] == -1, "baseline 側にだけある phase 差を出す")
    expect(comparison.scrollPhaseDelta["2"] == 1, "candidate 側にだけある phase 差を出す")
    expect(comparison.findings.contains { $0.contains("生成イベント") }, "生成イベントを所見に出す")
}

func testInputLogAnalyzerCountsKeyEvents() {
    let baseline: [InputLogRecord] = []
    let candidate = [
        InputLogRecord(
            timestamp: 1,
            typeName: "keyDown",
            typeRaw: 10,
            generatedByNapeGesture: true,
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
            keyCode: 126,
            flags: 262144
        ),
        InputLogRecord(
            timestamp: 2,
            typeName: "keyUp",
            typeRaw: 11,
            generatedByNapeGesture: true,
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
            keyCode: 126,
            flags: 262144
        )
    ]

    let analysis = InputLogAnalyzer.analyze(candidate)
    let comparison = InputLogAnalyzer.compare(baseline: baseline, candidate: candidate)

    expect(analysis.keyEvents == 2, "キーイベント数を数える")
    expect(analysis.keyCounts["keyDown:126"] == 1, "keyDown と keyCode を集計する")
    expect(analysis.keyCounts["keyUp:126"] == 1, "keyUp と keyCode を集計する")
    expect(comparison.keyEventDelta == 2, "キーイベント数差を出す")
    expect(comparison.keyDelta["keyDown:126"] == 1, "keyDown の差を出す")
    expect(comparison.findings.contains { $0.contains("キーイベント") }, "キーイベント差を所見に出す")
}

func testHIDInputLogAnalyzerGroupsByDeviceAndUsage() {
    let device = DeviceIdentity(
        manufacturer: "Example",
        product: "Nape Pro Mouse",
        vendorID: 123,
        productID: 456,
        transport: "Bluetooth",
        primaryUsagePage: 1,
        primaryUsage: 2
    )
    let records = [
        HIDInputLogRecord(
            time: 1,
            device: device,
            usagePage: 1,
            usage: 48,
            integerValue: 10,
            scaledValue: 10,
            logicalMin: -127,
            logicalMax: 127,
            physicalMin: -127,
            physicalMax: 127
        ),
        HIDInputLogRecord(
            time: 1.01,
            device: device,
            usagePage: 1,
            usage: 48,
            integerValue: -4,
            scaledValue: -4,
            logicalMin: -127,
            logicalMax: 127,
            physicalMin: -127,
            physicalMax: 127
        ),
        HIDInputLogRecord(
            time: 1.02,
            device: device,
            usagePage: 9,
            usage: 4,
            integerValue: 0,
            scaledValue: 0,
            logicalMin: 0,
            logicalMax: 1,
            physicalMin: 0,
            physicalMax: 1
        )
    ]

    let analysis = HIDInputLogAnalyzer.analyze(records)
    let xSummary = analysis.usageSummaries.first { $0.usagePage == 1 && $0.usage == 48 }
    let buttonSummary = analysis.usageSummaries.first { $0.usagePage == 9 && $0.usage == 4 }

    expect(analysis.totalEvents == 3, "HID入力イベント数を数える")
    expect(analysis.deviceCount == 1, "HID入力デバイス数を数える")
    expect(analysis.usageSummaries.count == 2, "usage ごとに集計する")
    expect(xSummary?.eventCount == 2, "同じ usage のイベントをまとめる")
    expect(xSummary?.integerMin == -4, "integer 最小値を出す")
    expect(xSummary?.integerMax == 10, "integer 最大値を出す")
    expect(buttonSummary?.nonZeroEventCount == 0, "ゼロ値イベントを非ゼロとして数えない")
}

func testScrollGenerationPlannerAutoPhases() {
    let commands = ScrollGenerationPlanner.makeCommands(
        deltaX: 0,
        deltaY: -90,
        steps: 3,
        interval: 0.01,
        phaseOverride: nil,
        momentumSteps: 0,
        momentumDecay: 0.85,
        momentumScale: 1,
        startTime: 10
    )

    expect(commands.map(\.phase) == [.began, .changed, .ended], "複数ステップでは began/changed/ended を生成する")
    expect(commands.map(\.deltaY) == [-30, -30, -30], "総量をステップ数で分割する")
    expect(abs((commands.last?.timestamp ?? 0) - 10.02) < 0.000001, "interval に従って timestamp を進める")
}

func testScrollGenerationPlannerPhaseOverrideAndMomentum() {
    let commands = ScrollGenerationPlanner.makeCommands(
        deltaX: 40,
        deltaY: 0,
        steps: 2,
        interval: 0.01,
        phaseOverride: .momentum,
        momentumSteps: 2,
        momentumDecay: 0.5,
        momentumScale: 1,
        startTime: 20
    )

    expect(commands.count == 5, "通常ステップ、慣性ステップ、慣性終了を生成する")
    expect(commands[0].phase == .momentum, "任意フェーズを通常ステップに適用する")
    expect(commands[1].phase == .momentum, "任意フェーズを複数ステップに適用する")
    expect(commands[2].kind == .momentum, "慣性ステップは momentum kind にする")
    expect(commands[2].deltaX == 20, "最初の慣性量はステップ量を基準にする")
    expect(commands[3].deltaX == 10, "慣性量を decay で減衰する")
    expect(commands[4].phase == .ended, "慣性列の最後に ended を追加する")
}

func testScrollEventPhaseEncoderSeparatesScrollAndMomentumPhases() {
    let normalEnded = GestureCommand(
        kind: .wheel,
        phase: .ended,
        direction: nil,
        deltaX: 0,
        deltaY: 0,
        velocityX: 0,
        velocityY: 0,
        timestamp: 1
    )
    let momentumChanged = GestureCommand(
        kind: .momentum,
        phase: .momentum,
        direction: nil,
        deltaX: 1,
        deltaY: 0,
        velocityX: 100,
        velocityY: 0,
        timestamp: 1.01
    )
    let momentumEnded = GestureCommand(
        kind: .momentum,
        phase: .ended,
        direction: nil,
        deltaX: 0,
        deltaY: 0,
        velocityX: 0,
        velocityY: 0,
        timestamp: 1.02
    )

    expect(
        ScrollEventPhaseEncoder.encode(command: normalEnded) == ScrollEventPhaseEncoding(scrollPhase: .ended, momentumPhase: nil),
        "通常スクロールの ended は scrollPhase だけに出す"
    )
    expect(
        ScrollEventPhaseEncoder.encode(command: momentumChanged) == ScrollEventPhaseEncoding(scrollPhase: nil, momentumPhase: .changed),
        "慣性中は momentumPhase changed として出す"
    )
    expect(
        ScrollEventPhaseEncoder.encode(command: momentumEnded) == ScrollEventPhaseEncoding(scrollPhase: nil, momentumPhase: .ended),
        "慣性終了は momentumPhase ended として出す"
    )
}

func testTargetDeviceGateOnlyHandlesRecentTargetActivity() {
    var gate = TargetDeviceGateState(
        configuration: TargetDeviceGateConfiguration(
            activationButton: .button4,
            associationWindow: 0.1
        )
    )

    let unrelatedDown = RawInputEvent.buttonDown(button: .button4, time: 1)
    expect(!gate.shouldHandle(unrelatedDown), "対象デバイス入力がないボタン押下は処理しない")

    gate.record(.pointer(deltaX: 1, deltaY: 0, time: 2))
    let targetDown = RawInputEvent.buttonDown(button: .button4, time: 2.05)
    expect(gate.shouldHandle(targetDown), "対象デバイスの直近入力に続くジェスチャーボタンは処理する")

    let staleMove = RawInputEvent.move(deltaX: 4, deltaY: 0, time: 3)
    expect(!gate.shouldHandle(staleMove), "対象デバイス入力が古い移動は処理しない")
}

func testTargetDeviceGateKeepsHandlingWhileActivationButtonIsDown() {
    var gate = TargetDeviceGateState(
        configuration: TargetDeviceGateConfiguration(
            activationButton: .button4,
            associationWindow: 0.1
        )
    )

    gate.record(.buttonDown(button: .button4, time: 1))
    expect(gate.shouldHandle(.move(deltaX: 5, deltaY: 0, time: 10)), "対象デバイスのジェスチャーボタン押下中は移動を処理する")

    gate.record(.buttonUp(button: .button4, time: 10.01))
    expect(gate.shouldHandle(.buttonUp(button: .button4, time: 10.02)), "対象デバイスのボタン解放直後は終了処理を通す")
    expect(!gate.shouldHandle(.move(deltaX: 5, deltaY: 0, time: 11)), "ボタン解放後しばらく経った移動は処理しない")
}

func testDefaultGestureBindingsMapSystemActions() {
    let bindings = GestureBindings.default

    expect(bindings.action(for: .up) == .missionControl, "上方向ドラッグは Mission Control に割り当てる")
    expect(bindings.action(for: .left) == .spaceLeft, "左方向ドラッグは左Spaces移動に割り当てる")
    expect(bindings.action(for: .right) == .spaceRight, "右方向ドラッグは右Spaces移動に割り当てる")
    expect(bindings.wheel == .horizontalScroll, "ホイールは横スクロールに割り当てる")
}

func testGestureActionMomentumSupport() {
    expect(GestureAction.smoothScroll.supportsMomentum, "smoothScroll は慣性を持てる")
    expect(GestureAction.spaceLeft.supportsMomentum, "spaceLeft は連続スクロール系として慣性を持てる")
    expect(!GestureAction.missionControl.supportsMomentum, "Mission Control は離散アクションなので慣性を持たない")
    expect(!GestureAction.pageBack.supportsMomentum, "ページ戻るは離散アクションなので慣性を持たない")
}

func testRuntimeSafetyStateStopsForKillSwitch() {
    var state = RuntimeSafetyState()

    let decision = state.stopForKillSwitch(at: 10)

    expect(!state.isEnabled, "キルスイッチ発火後は無効状態になる")
    expect(state.mode == .stopped(reason: .killSwitch, stoppedAt: 10), "停止理由と時刻を保持する")
    expect(!decision.shouldProcessGestureInput, "キルスイッチ発火イベントではジェスチャー処理を進めない")
    expect(decision.shouldSuppressOriginalEvent, "キルスイッチショートカットは前面アプリへ渡さない")
    expect(decision.shouldCancelGesture, "キルスイッチ発火時に進行中ジェスチャーを停止対象にする")
    expect(decision.shouldCancelMomentum, "キルスイッチ発火時に慣性を停止対象にする")
    expect(decision.didEnterStoppedState, "初回発火は停止状態への遷移として扱う")
}

func testRuntimeSafetyStatePassesRegularInputAfterStop() {
    var state = RuntimeSafetyState()

    let beforeStop = state.regularInputDecision()
    _ = state.stopForKillSwitch(at: 10)
    let afterStop = state.regularInputDecision()

    expect(beforeStop.shouldProcessGestureInput, "停止前の通常入力はジェスチャー処理へ渡す")
    expect(!beforeStop.shouldSuppressOriginalEvent, "停止前の通常入力は安全状態だけでは抑制しない")
    expect(!afterStop.shouldProcessGestureInput, "停止後の通常入力はジェスチャー処理へ渡さない")
    expect(!afterStop.shouldSuppressOriginalEvent, "停止後の通常入力は前面アプリへ通す")
}

func testRuntimeSafetyStateDoesNotReenableWithoutReset() {
    var state = RuntimeSafetyState()

    _ = state.stopForKillSwitch(at: 10)
    _ = state.regularInputDecision()
    let repeatedKillSwitch = state.stopForKillSwitch(at: 11)

    expect(!state.isEnabled, "通常入力や再度のキルスイッチでは再有効化しない")
    expect(repeatedKillSwitch.shouldSuppressOriginalEvent, "停止済みでもキルスイッチショートカットは前面アプリへ渡さない")
    expect(!repeatedKillSwitch.shouldCancelGesture, "停止済みの再発火ではジェスチャー停止を重ねない")
    expect(!repeatedKillSwitch.shouldCancelMomentum, "停止済みの再発火では慣性停止を重ねない")
    expect(!repeatedKillSwitch.didEnterStoppedState, "停止済みの再発火は新しい停止遷移ではない")
}

func testRuntimeSafetyStateResetReenablesGestureInput() {
    var state = RuntimeSafetyState()

    _ = state.stopForKillSwitch(at: 10)
    state.reset()
    let decision = state.regularInputDecision()

    expect(state.isEnabled, "明示 reset 後は有効状態へ戻る")
    expect(decision.shouldProcessGestureInput, "明示 reset 後の通常入力はジェスチャー処理へ渡す")
    expect(!decision.shouldSuppressOriginalEvent, "明示 reset 後の通常入力は安全状態だけでは抑制しない")
}

testPassesThroughWhenActivationButtonIsNotPressed()
testActivationButtonSuppressesOriginalInputBeforeThreshold()
testDragBeginsAfterDeadZoneAndLocksDominantDirection()
testActiveDragEmitsChangedThenEnded()
testAccelerationScalesFastDragDeltas()
testAccelerationDoesNotScaleBelowThreshold()
testDragCancelsWhenMaximumDurationIsExceeded()
testDragCancelsWhenInactivityIsExceeded()
testDragCancelsWhenOffAxisMovementExceedsRatio()
testWheelGestureIsScopedToActivationButton()
testMomentumDoesNotStartBelowMinimumVelocity()
testMomentumDecaysAndEventuallyEnds()
testDeviceMatcherMatchesConfiguredDevice()
testDeviceMatcherMatchesUsageWhenConfigured()
testDeviceMatcherConditionPresenceIgnoresEmptyText()
testDeviceMatcherWithoutConditionsDoesNotMatchEverything()
testDeviceIdentityEncodesStableID()
testGestureConfigurationDecodesOldJSONWithDefaults()
testSettingsValidatorAcceptsTemplateSettings()
testSettingsValidatorRejectsUnsafeGestureValues()
testSettingsValidatorRejectsMissingRequiredTargetMatcher()
testSettingsValidatorRejectsInvalidTargetMatcherValues()
testInputLogAnalyzerSuggestsDeadZone()
testInputLogRecordDecodesLegacyGeneratedField()
testInputLogAnalyzerComparesBaselineAndCandidate()
testInputLogAnalyzerCountsKeyEvents()
testHIDInputLogAnalyzerGroupsByDeviceAndUsage()
testScrollGenerationPlannerAutoPhases()
testScrollGenerationPlannerPhaseOverrideAndMomentum()
testScrollEventPhaseEncoderSeparatesScrollAndMomentumPhases()
testTargetDeviceGateOnlyHandlesRecentTargetActivity()
testTargetDeviceGateKeepsHandlingWhileActivationButtonIsDown()
testDefaultGestureBindingsMapSystemActions()
testGestureActionMomentumSupport()
testRuntimeSafetyStateStopsForKillSwitch()
testRuntimeSafetyStatePassesRegularInputAfterStop()
testRuntimeSafetyStateDoesNotReenableWithoutReset()
testRuntimeSafetyStateResetReenablesGestureInput()

if failures == 0 {
    print("すべてのコアテストに成功しました。")
} else {
    fputs("\(failures) 件のコアテストが失敗しました。\n", stderr)
    exit(1)
}
