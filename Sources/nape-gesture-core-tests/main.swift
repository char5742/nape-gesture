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

func sampleDeviceIdentity() -> DeviceIdentity {
    DeviceIdentity(
        manufacturer: "Example",
        product: "Nape Pro Mouse",
        vendorID: 123,
        productID: 456,
        transport: "Bluetooth",
        primaryUsagePage: 1,
        primaryUsage: 2
    )
}

func makeHIDRecord(time: TimeInterval, usagePage: Int = 1, usage: Int = 48, integerValue: Int = 1) -> HIDInputLogRecord {
    HIDInputLogRecord(
        time: time,
        device: sampleDeviceIdentity(),
        usagePage: usagePage,
        usage: usage,
        integerValue: integerValue,
        scaledValue: Double(integerValue),
        logicalMin: -127,
        logicalMax: 127,
        physicalMin: -127,
        physicalMax: 127
    )
}

func makeInputLogRecord(
    timestamp: UInt64,
    typeName: String,
    generatedByNapeGesture: Bool = false,
    buttonNumber: Int64 = 0,
    deltaX: Int64? = nil,
    deltaY: Int64? = nil,
    scrollDeltaX: Int64 = 0,
    scrollDeltaY: Int64? = nil,
    pointDeltaX: Double = 0,
    pointDeltaY: Double? = nil,
    scrollPhase: Int64 = 0,
    momentumPhase: Int64 = 0,
    isContinuous: Int64? = nil,
    keyCode: Int64 = 0,
    flags: UInt64 = 0
) -> InputLogRecord {
    let hasMoveDelta = typeName == "mouseMoved" || typeName.hasSuffix("MouseDragged")

    return InputLogRecord(
        timestamp: timestamp,
        typeName: typeName,
        typeRaw: 0,
        generatedByNapeGesture: generatedByNapeGesture,
        buttonNumber: buttonNumber,
        deltaX: deltaX ?? (hasMoveDelta ? 1 : 0),
        deltaY: deltaY ?? 0,
        scrollDeltaX: scrollDeltaX,
        scrollDeltaY: scrollDeltaY ?? (typeName == "scrollWheel" ? -1 : 0),
        pointDeltaX: pointDeltaX,
        pointDeltaY: pointDeltaY ?? (typeName == "scrollWheel" ? -1 : 0),
        scrollPhase: scrollPhase,
        momentumPhase: momentumPhase,
        isContinuous: isContinuous ?? (typeName == "scrollWheel" ? 1 : 0),
        keyCode: keyCode,
        flags: flags
    )
}

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

func testArmedButtonUpBelowDeadZoneSuppressesWithoutCommand() {
    var recognizer = GestureRecognizer(configuration: GestureConfiguration(deadZonePoints: 5))

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 2, deltaY: 1, time: 1.01))
    let ended = recognizer.handle(.buttonUp(button: .button4, time: 1.02))

    expect(ended.shouldSuppressOriginal, "デッドゾーン未満でのボタン解放も抑制する")
    expect(ended.commands.isEmpty, "デッドゾーン未満でのボタン解放ではコマンドを出さない")
    expect(recognizer.isIdle, "デッドゾーン未満でのボタン解放後は idle に戻る")
}

func testActiveDragSuppressesChangedAndEndedOriginals() {
    var recognizer = GestureRecognizer(configuration: GestureConfiguration(deadZonePoints: 3))

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 4, deltaY: 0, time: 1.01))
    let changed = recognizer.handle(.move(deltaX: 2, deltaY: 0, time: 1.02))
    let ended = recognizer.handle(.buttonUp(button: .button4, time: 1.03))

    expect(changed.shouldSuppressOriginal, "ドラッグ継続中の元移動は抑制する")
    expect(changed.commands.first?.phase == .changed, "ドラッグ継続フェーズを出す")
    expect(ended.shouldSuppressOriginal, "ドラッグ終了時の元ボタン解放は抑制する")
    expect(ended.commands.first?.phase == .ended, "ドラッグ終了フェーズを出す")
    expect(recognizer.isIdle, "ドラッグ終了後は idle に戻る")
}

func testActiveWheelSuppressesChangedAndEndedOriginals() {
    var recognizer = GestureRecognizer(configuration: .default)

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.wheel(deltaX: 0, deltaY: -120, time: 1.01))
    let changed = recognizer.handle(.wheel(deltaX: 0, deltaY: -80, time: 1.02))
    let ended = recognizer.handle(.buttonUp(button: .button4, time: 1.03))

    expect(changed.shouldSuppressOriginal, "ホイール継続中の元ホイールは抑制する")
    expect(changed.commands.first?.phase == .changed, "ホイール継続フェーズを出す")
    expect(ended.shouldSuppressOriginal, "ホイール終了時の元ボタン解放は抑制する")
    expect(ended.commands.first?.phase == .ended, "ホイール終了フェーズを出す")
    expect(recognizer.isIdle, "ホイール終了後は idle に戻る")
}

func testDragSuppressesWheelWithoutLeavingDrag() {
    var recognizer = GestureRecognizer(configuration: GestureConfiguration(deadZonePoints: 3))

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 4, deltaY: 0, time: 1.01))
    let wheel = recognizer.handle(.wheel(deltaX: 0, deltaY: -120, time: 1.02))
    let changed = recognizer.handle(.move(deltaX: 1, deltaY: 0, time: 1.03))
    let ended = recognizer.handle(.buttonUp(button: .button4, time: 1.04))

    expect(wheel.shouldSuppressOriginal, "ドラッグ中に来た元ホイールは抑制する")
    expect(wheel.commands.isEmpty, "ドラッグ中のホイールでは別ジェスチャーを出さない")
    expect(changed.commands.first?.kind == .drag, "ホイール混入後もドラッグとして継続する")
    expect(changed.commands.first?.phase == .changed, "ホイール混入後もドラッグ継続フェーズを出す")
    expect(ended.commands.first?.phase == .ended, "ホイール混入後もドラッグ終了フェーズを出す")
    expect(recognizer.isIdle, "ホイール混入後の終了でも idle に戻る")
}

func testWheelSuppressesMoveWithoutLeavingWheel() {
    var recognizer = GestureRecognizer(configuration: .default)

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.wheel(deltaX: 0, deltaY: -120, time: 1.01))
    let move = recognizer.handle(.move(deltaX: 8, deltaY: 0, time: 1.02))
    let changed = recognizer.handle(.wheel(deltaX: 0, deltaY: -80, time: 1.03))
    let ended = recognizer.handle(.buttonUp(button: .button4, time: 1.04))

    expect(move.shouldSuppressOriginal, "ホイール中に来た元移動は抑制する")
    expect(move.commands.isEmpty, "ホイール中の移動では別ジェスチャーを出さない")
    expect(changed.commands.first?.kind == .wheel, "移動混入後もホイールとして継続する")
    expect(changed.commands.first?.phase == .changed, "移動混入後もホイール継続フェーズを出す")
    expect(ended.commands.first?.phase == .ended, "移動混入後もホイール終了フェーズを出す")
    expect(recognizer.isIdle, "移動混入後の終了でも idle に戻る")
}

func testInputsPassThroughAfterActivationButtonRelease() {
    var recognizer = GestureRecognizer(configuration: GestureConfiguration(deadZonePoints: 5))

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let activationUp = recognizer.handle(.buttonUp(button: .button4, time: 1.01))
    let move = recognizer.handle(.move(deltaX: 12, deltaY: 0, time: 1.02))
    let wheel = recognizer.handle(.wheel(deltaX: 0, deltaY: -120, time: 1.03))
    let nonActivationDown = recognizer.handle(.buttonDown(button: .left, time: 1.04))
    let nonActivationUp = recognizer.handle(.buttonUp(button: .left, time: 1.05))

    expect(activationUp.shouldSuppressOriginal, "ジェスチャーボタン解放自体は抑制する")
    expect(!move.shouldSuppressOriginal, "ジェスチャーボタン解放後の通常移動は通過する")
    expect(move.commands.isEmpty, "ジェスチャーボタン解放後の通常移動ではコマンドを出さない")
    expect(!wheel.shouldSuppressOriginal, "ジェスチャーボタン解放後の通常ホイールは通過する")
    expect(wheel.commands.isEmpty, "ジェスチャーボタン解放後の通常ホイールではコマンドを出さない")
    expect(!nonActivationDown.shouldSuppressOriginal, "ジェスチャーボタン解放後の非ジェスチャーボタン押下は通過する")
    expect(!nonActivationUp.shouldSuppressOriginal, "ジェスチャーボタン解放後の非ジェスチャーボタン解放は通過する")
    expect(recognizer.isIdle, "通過入力後も idle のまま")
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

func testNapeGestureSettingsDecodesOldJSONWithDefaultAssociationWindow() {
    let json = """
    {
      "gesture" : {
        "activationButton" : 4,
        "deadZonePoints" : 8,
        "directionLockRatio" : 1.35,
        "dragSensitivity" : 1,
        "wheelSensitivity" : 1
      },
      "requireMatchingTargetDevice" : true,
      "targetDevices" : [
        {
          "productContains" : "Nape Pro"
        }
      ]
    }
    """

    let settings = try? JSONDecoder().decode(NapeGestureSettings.self, from: Data(json.utf8))

    expect(
        settings?.targetDeviceAssociation.associationWindow
            == TargetDeviceAssociationConfiguration.defaultAssociationWindow,
        "古い設定JSONには既定の対象入力紐づけ秒を補う"
    )
    expect(settings?.targetDevices.first?.productContains == "Nape Pro", "古い設定JSONの対象条件を維持する")
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

func testSettingsValidatorRejectsInvalidTargetDeviceAssociationWindow() {
    let settings = NapeGestureSettings(
        gesture: .default,
        targetDeviceAssociation: TargetDeviceAssociationConfiguration(associationWindow: 0),
        targetDevices: [DeviceMatcher(productContains: "Nape Pro")],
        requireMatchingTargetDevice: true
    )

    let paths = Set(SettingsValidator.issues(for: settings).map(\.path))

    expect(paths.contains("targetDeviceAssociation.associationWindow"), "0以下の対象入力紐づけ秒を拒否する")
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

func testLogDerivedTuningAnalyzerDerivesAccelerationAndMomentum() {
    let moveSamples: [(timestamp: UInt64, deltaX: Int64)] = [
        (1_000_000_000, 1),
        (1_016_000_000, 2),
        (1_032_000_000, 4),
        (1_048_000_000, 6),
        (1_064_000_000, 8)
    ]
    let moveRecords = moveSamples.map { timestamp, deltaX in
        makeInputLogRecord(
            timestamp: timestamp,
            typeName: "mouseMoved",
            deltaX: deltaX
        )
    }
    let scrollSamples: [
        (
            timestamp: UInt64,
            pointDeltaY: Double,
            scrollDeltaY: Int64,
            scrollPhase: Int64,
            momentumPhase: Int64
        )
    ] = [
        (2_000_000_000, -24.0, -240, 1, 0),
        (2_016_000_000, -20.0, -200, 2, 0),
        (2_032_000_000, -16.0, -160, 2, 0),
        (2_048_000_000, -12.0, -120, 0, 1),
        (2_064_000_000, -11.52, -115, 0, 2),
        (2_080_000_000, -11.06, -111, 0, 2),
        (2_096_000_000, -10.62, -106, 0, 4)
    ]
    let scrollRecords = scrollSamples.map { timestamp, pointDeltaY, scrollDeltaY, scrollPhase, momentumPhase in
        makeInputLogRecord(
            timestamp: timestamp,
            typeName: "scrollWheel",
            scrollDeltaY: scrollDeltaY,
            pointDeltaY: pointDeltaY,
            scrollPhase: scrollPhase,
            momentumPhase: momentumPhase
        )
    }
    let records = moveRecords + scrollRecords

    let report = LogDerivedTuningAnalyzer.derive(from: records)

    expect(report.sourceEventCount == 12, "元ログ件数を保持する")
    expectApproximatelyEqual(report.suggestedDeadZonePoints, 12, "移動量分布から deadZone 候補を出す")
    expect(report.moveVelocitySamples.count == 4, "移動速度サンプルを正の時刻差分から作る")
    expectApproximatelyEqual(report.suggestedAcceleration?.thresholdVelocity, 375, "移動速度 p75 を加速度しきい値候補にする")
    expect(report.momentumVelocitySamples.count == 3, "慣性速度サンプルを momentumPhase 区間から作る")
    expectApproximatelyEqual(report.suggestedMomentum?.minimumStartVelocity, 1_250, "active scroll と momentum の速度分布から慣性開始速度を出す")
    expectApproximatelyEqual(report.suggestedMomentum?.frameInterval, 0.016, "スクロール間隔 p50 を frameInterval 候補にする")
    expect((report.suggestedMomentum?.decayPerSecond ?? 0) > 0.05, "減衰率候補は 0 より大きい")
    expect((report.suggestedMomentum?.decayPerSecond ?? 1) < 0.10, "減衰率候補は合成ログの減衰に近い")
    expect(report.warnings.isEmpty, "十分なサンプルがある場合は未導出警告を出さない")
}

func testLogDerivedTuningAnalyzerReportsMissingSamples() {
    let report = LogDerivedTuningAnalyzer.derive(from: [])

    expect(report.suggestedAcceleration == nil, "移動速度が足りない場合は加速度候補を出さない")
    expect(report.suggestedMomentum == nil, "慣性速度が足りない場合は慣性候補を出さない")
    expect(report.warnings.contains { $0.contains("acceleration.thresholdVelocity") }, "加速度未導出理由を残す")
    expect(report.warnings.contains { $0.contains("momentum") }, "慣性未導出理由を残す")
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

func testInputAssociationAnalyzerMeasuresWindowDistribution() {
    let hidRecords = [
        makeHIDRecord(time: 2.0),
        makeHIDRecord(time: 2.2),
        makeHIDRecord(time: 3.0)
    ]
    let eventRecords = [
        makeInputLogRecord(timestamp: 1_500_000_000, typeName: "mouseMoved"),
        makeInputLogRecord(timestamp: 2_050_000_000, typeName: "mouseMoved"),
        makeInputLogRecord(timestamp: 2_350_000_000, typeName: "scrollWheel"),
        makeInputLogRecord(timestamp: 2_060_000_000, typeName: "mouseMoved", generatedByNapeGesture: true)
    ]

    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: hidRecords,
        eventTapRecords: eventRecords,
        associationWindowSeconds: 0.12
    )

    expect(analysis.totalHIDEvents == 3, "HID ログ総数を保持する")
    expect(analysis.totalEventTapEvents == 4, "イベントタップログ総数を保持する")
    expect(analysis.analyzedEventTapEvents == 3, "未生成の mouse/button/scroll 系だけを解析対象にする")
    expect(analysis.excludedGeneratedEventTapEvents == 1, "生成済み raw input は解析対象から除外する")
    expect(analysis.hidCandidateEventCount == 3, "近い HID があるイベントタップ入力を候補ありとして数える")
    expect(analysis.missingHIDCandidateEventCount == 0, "HID ログがある場合は最も近い HID と比較する")
    expect(analysis.withinWindowCount == 1, "associationWindow 内の件数を数える")
    expect(analysis.outsideWindowCount == 2, "associationWindow 外の件数を数える")
    expectApproximatelyEqual(analysis.maximumTimeDifferenceSeconds, 0.5, "最大時刻差秒を出す")
    expectApproximatelyEqual(analysis.p95TimeDifferenceSeconds, 0.5, "p95 時刻差秒を出す")
    expectApproximatelyEqual(analysis.p99TimeDifferenceSeconds, 0.5, "p99 時刻差秒を出す")
    expect(analysis.suggestedAssociationWindowSeconds >= analysis.p99TimeDifferenceSeconds, "推奨 associationWindow は p99 以上にする")
}

func testInputAssociationAnalyzerCountsUnmatchedWhenHIDLogIsEmpty() {
    let eventRecords = [
        makeInputLogRecord(timestamp: 2_050_000_000, typeName: "mouseMoved")
    ]

    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [],
        eventTapRecords: eventRecords,
        associationWindowSeconds: 0.12
    )

    expect(analysis.hidCandidateEventCount == 0, "HID ログが空なら候補ありにしない")
    expect(analysis.missingHIDCandidateEventCount == 1, "HID ログが空なら解析対象イベントを候補なしとして数える")
    expect(analysis.withinWindowCount == 0, "未一致イベントは associationWindow 内に数えない")
    expect(analysis.outsideWindowCount == 0, "未一致イベントは associationWindow 外にも数えない")
}

func testInputAssociationAnalyzerKeepsZeroValueHIDReleaseEvents() {
    let hidRecords = [
        makeHIDRecord(time: 10.0, usagePage: 9, usage: 4, integerValue: 0)
    ]
    let eventRecords = [
        makeInputLogRecord(timestamp: 10_020_000_000, typeName: "otherMouseUp", buttonNumber: 4)
    ]

    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: hidRecords,
        eventTapRecords: eventRecords,
        associationWindowSeconds: 0.12
    )

    expect(analysis.hidCandidateEventCount == 1, "HID のゼロ値 release も一致候補として扱う")
    expect(analysis.withinWindowCount == 1, "release 由来のイベントタップ入力も associationWindow 内判定できる")
    expectApproximatelyEqual(analysis.matches.first?.timeDifferenceSeconds, 0.02, "release の時刻差秒を算出する")
}

func testInputAssociationAnalyzerUsesNearestHIDByAbsoluteTimeDifference() {
    let hidRecords = [
        makeHIDRecord(time: 5.0)
    ]
    let eventRecords = [
        makeInputLogRecord(timestamp: 4_980_000_000, typeName: "mouseMoved")
    ]

    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: hidRecords,
        eventTapRecords: eventRecords,
        associationWindowSeconds: 0.12
    )

    expect(analysis.hidCandidateEventCount == 1, "イベント時刻より後の近い HID も時刻差判定に使う")
    expect(analysis.withinWindowCount == 1, "前後どちらの HID でも associationWindow 内を判定する")
    expectApproximatelyEqual(analysis.matches.first?.timeDifferenceSeconds, 0.02, "HID とイベントタップの絶対時刻差を算出する")
}

func testInputAssociationAnalyzerAcceptsSecondAndNanosecondTimestamps() {
    expectApproximatelyEqual(
        InputAssociationAnalyzer.timestampSeconds(fromEventTimestamp: 42),
        42,
        "小さい timestamp は秒値として扱う"
    )
    expectApproximatelyEqual(
        InputAssociationAnalyzer.timestampSeconds(fromEventTimestamp: 42_500_000_000),
        42.5,
        "大きい timestamp は nanoseconds として秒へ変換する"
    )
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

func testTargetDeviceGateUsesAssociationWindowFromSettings() {
    let settings = NapeGestureSettings(
        gesture: GestureConfiguration(activationButton: .button5),
        targetDeviceAssociation: TargetDeviceAssociationConfiguration(associationWindow: 0.04),
        targetDevices: [DeviceMatcher(productContains: "Nape Pro")],
        requireMatchingTargetDevice: true
    )
    let configuration = TargetDeviceGateConfiguration(settings: settings)
    var gate = TargetDeviceGateState(configuration: configuration)

    gate.record(.pointer(deltaX: 1, deltaY: 0, time: 2))

    expect(configuration.activationButton == .button5, "設定のジェスチャーボタンを gate に反映する")
    expect(configuration.associationWindow == 0.04, "設定の対象入力紐づけ秒を gate に反映する")
    expect(gate.shouldHandle(.buttonDown(button: .button5, time: 2.03)), "設定した紐づけ秒以内の入力を処理する")
    expect(!gate.shouldHandle(.buttonDown(button: .button5, time: 2.05)), "設定した紐づけ秒を超えた入力は処理しない")
}

func testTargetDeviceGatePassesThroughNonTargetClickDragAndWheel() {
    var gate = TargetDeviceGateState(
        configuration: TargetDeviceGateConfiguration(
            activationButton: .button4,
            associationWindow: 0.05
        )
    )

    expect(!gate.shouldHandle(.buttonDown(button: .left, time: 1)), "対象入力がない通常クリック押下は処理しない")
    expect(!gate.shouldHandle(.buttonUp(button: .left, time: 1.01)), "対象入力がない通常クリック解放は処理しない")
    expect(!gate.shouldHandle(.move(deltaX: 12, deltaY: 0, time: 1.02)), "対象入力がない通常ドラッグは処理しない")
    expect(!gate.shouldHandle(.wheel(deltaX: 0, deltaY: -4, time: 1.03)), "対象入力がない通常ホイールは処理しない")

    gate.record(.pointer(deltaX: 1, deltaY: 0, time: 2))

    expect(!gate.shouldHandle(.buttonDown(button: .left, time: 2.10)), "紐づけ秒を超えた対象外クリック押下は処理しない")
    expect(!gate.shouldHandle(.buttonDown(button: .button4, time: 2.10)), "紐づけ秒を超えた対象外ジェスチャーボタン押下は処理しない")
    expect(!gate.shouldHandle(.buttonUp(button: .button4, time: 2.10)), "紐づけ秒を超えた対象外ジェスチャーボタン解放は処理しない")
    expect(!gate.shouldHandle(.move(deltaX: 8, deltaY: 1, time: 2.11)), "紐づけ秒を超えた対象外ドラッグは処理しない")
    expect(!gate.shouldHandle(.wheel(deltaX: 0, deltaY: -6, time: 2.12)), "紐づけ秒を超えた対象外ホイールは処理しない")
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

func testRuntimeRecoveryStopsBeforeSleepAndDoesNotRetryDuringSleep() {
    var state = RuntimeRecoveryState()
    state.recordRuntimeStarted()

    let sleep = state.handleWillSleep(at: 10)
    _ = state.recordRuntimeFailure(.targetDeviceNotFound, at: 10.5)
    let retry = state.retryIfReady(at: 11)

    expect(sleep.shouldStopRuntime, "スリープ前は runtime 停止を要求する")
    expect(!sleep.shouldStartRuntime, "スリープ前に runtime 開始は要求しない")
    expect(state.isSuspendedForSleep, "スリープ中として保持する")
    expect(!state.shouldShowAutoRetry, "スリープ中の自動復旧可能な失敗でも自動再試行表示にしない")
    expect(state.pendingRetry == nil, "スリープ中の自動復旧可能な失敗では自動再試行予定を作らない")
    expect(!retry.shouldStartRuntime, "スリープ中は自動再試行しない")
}

func testRuntimeRecoverySchedulesDelayedWakeRetryOnlyWhenEnabled() {
    var state = RuntimeRecoveryState()
    state.recordRuntimeStarted()
    _ = state.handleWillSleep(at: 10)

    let wake = state.handleDidWake(at: 20, retryDelay: 1.5)

    expect(!wake.shouldStartRuntime, "wake 直後は遅延再開に留める")
    expect(state.pendingRetry?.reason == .wake, "wake 後の遅延再開理由を保持する")
    expectApproximatelyEqual(state.pendingRetry?.requestedAt, 20, "wake 後の遅延再開要求時刻を保持する")
    expectApproximatelyEqual(state.pendingRetry?.notBefore, 21.5, "wake 後の遅延再開可能時刻を保持する")

    let tooEarly = state.retryIfReady(at: 21.49)
    let ready = state.retryIfReady(at: 21.5)

    expect(!tooEarly.shouldStartRuntime, "wake 遅延前は再開しない")
    expect(ready.shouldStartRuntime, "wake 遅延後は再開対象になる")
}

func testRuntimeRecoveryDoesNotScheduleWakeRetryAfterManualStop() {
    var state = RuntimeRecoveryState()
    _ = state.requestManualStop(at: 5)

    _ = state.handleWillSleep(at: 10)
    let wake = state.handleDidWake(at: 20, retryDelay: 1.5)
    let retry = state.retryIfReady(at: 30)

    expect(!wake.shouldStartRuntime, "手動停止後の wake では即時開始しない")
    expect(state.pendingRetry == nil, "手動停止後の wake は自動再試行予定を作らない")
    expect(!retry.shouldStartRuntime, "手動停止後は自動再試行しない")
}

func testRuntimeRecoveryRetriesRecoverableFailures() {
    let recoverableFailures: [RuntimeRecoveryFailureKind] = [
        .accessibilityPermissionMissing,
        .eventTapCreationFailed,
        .hidAccessUnavailable,
        .targetDeviceNotFound
    ]

    for failure in recoverableFailures {
        var state = RuntimeRecoveryState()
        _ = state.recordRuntimeFailure(failure, at: 10)
        let retry = state.retryIfReady(at: 10)

        expect(state.autoRetryEnabled, "自動復旧可能な失敗後も自動再試行は有効なままにする: \(failure)")
        expect(retry.shouldStartRuntime, "自動復旧可能な失敗は自動再試行対象にする: \(failure)")
    }
}

func testRuntimeRecoveryDoesNotRetryHumanFixRequiredFailures() {
    let humanFixRequiredFailures: [RuntimeRecoveryFailureKind] = [
        .invalidSettings,
        .targetDeviceMatcherMissing,
        .unrecoverable
    ]

    for failure in humanFixRequiredFailures {
        var state = RuntimeRecoveryState()
        _ = state.recordRuntimeFailure(failure, at: 10)
        let retry = state.retryIfReady(at: 10)

        expect(state.pendingRetry == nil, "人間の修正が必要な失敗は自動再試行予定を作らない: \(failure)")
        expect(!retry.shouldStartRuntime, "人間の修正が必要な失敗は自動再試行しない: \(failure)")
    }
}

func testRuntimeRecoveryManualStartAndSettingsSaveReenableAutoRetry() {
    var manualStartState = RuntimeRecoveryState()
    _ = manualStartState.requestManualStop(at: 1)
    let manualStart = manualStartState.requestManualStart(at: 2)
    _ = manualStartState.recordRuntimeFailure(.targetDeviceNotFound, at: 3)
    let manualRetry = manualStartState.retryIfReady(at: 3)

    var settingsSavedState = RuntimeRecoveryState()
    _ = settingsSavedState.requestManualStop(at: 1)
    let settingsSaved = settingsSavedState.recordSettingsSaved(at: 2)
    _ = settingsSavedState.recordRuntimeFailure(.hidAccessUnavailable, at: 3)
    let settingsRetry = settingsSavedState.retryIfReady(at: 3)

    expect(manualStart.shouldStartRuntime, "手動開始は runtime 開始を要求する")
    expect(manualStartState.autoRetryEnabled, "手動開始で自動再試行を再有効化する")
    expect(manualRetry.shouldStartRuntime, "手動開始後の自動復旧可能な失敗は再試行する")
    expect(settingsSaved.shouldStartRuntime, "設定保存は runtime 開始を要求する")
    expect(settingsSavedState.autoRetryEnabled, "設定保存で自動再試行を再有効化する")
    expect(settingsRetry.shouldStartRuntime, "設定保存後の自動復旧可能な失敗は再試行する")
}

testPassesThroughWhenActivationButtonIsNotPressed()
testActivationButtonSuppressesOriginalInputBeforeThreshold()
testDragBeginsAfterDeadZoneAndLocksDominantDirection()
testActiveDragEmitsChangedThenEnded()
testArmedButtonUpBelowDeadZoneSuppressesWithoutCommand()
testActiveDragSuppressesChangedAndEndedOriginals()
testActiveWheelSuppressesChangedAndEndedOriginals()
testDragSuppressesWheelWithoutLeavingDrag()
testWheelSuppressesMoveWithoutLeavingWheel()
testInputsPassThroughAfterActivationButtonRelease()
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
testNapeGestureSettingsDecodesOldJSONWithDefaultAssociationWindow()
testSettingsValidatorAcceptsTemplateSettings()
testSettingsValidatorRejectsUnsafeGestureValues()
testSettingsValidatorRejectsInvalidTargetDeviceAssociationWindow()
testSettingsValidatorRejectsMissingRequiredTargetMatcher()
testSettingsValidatorRejectsInvalidTargetMatcherValues()
testInputLogAnalyzerSuggestsDeadZone()
testInputLogRecordDecodesLegacyGeneratedField()
testInputLogAnalyzerComparesBaselineAndCandidate()
testInputLogAnalyzerCountsKeyEvents()
testLogDerivedTuningAnalyzerDerivesAccelerationAndMomentum()
testLogDerivedTuningAnalyzerReportsMissingSamples()
testHIDInputLogAnalyzerGroupsByDeviceAndUsage()
testInputAssociationAnalyzerMeasuresWindowDistribution()
testInputAssociationAnalyzerCountsUnmatchedWhenHIDLogIsEmpty()
testInputAssociationAnalyzerKeepsZeroValueHIDReleaseEvents()
testInputAssociationAnalyzerUsesNearestHIDByAbsoluteTimeDifference()
testInputAssociationAnalyzerAcceptsSecondAndNanosecondTimestamps()
testScrollGenerationPlannerAutoPhases()
testScrollGenerationPlannerPhaseOverrideAndMomentum()
testScrollEventPhaseEncoderSeparatesScrollAndMomentumPhases()
testTargetDeviceGateOnlyHandlesRecentTargetActivity()
testTargetDeviceGateKeepsHandlingWhileActivationButtonIsDown()
testTargetDeviceGateUsesAssociationWindowFromSettings()
testTargetDeviceGatePassesThroughNonTargetClickDragAndWheel()
testDefaultGestureBindingsMapSystemActions()
testGestureActionMomentumSupport()
testRuntimeSafetyStateStopsForKillSwitch()
testRuntimeSafetyStatePassesRegularInputAfterStop()
testRuntimeSafetyStateDoesNotReenableWithoutReset()
testRuntimeSafetyStateResetReenablesGestureInput()
testRuntimeRecoveryStopsBeforeSleepAndDoesNotRetryDuringSleep()
testRuntimeRecoverySchedulesDelayedWakeRetryOnlyWhenEnabled()
testRuntimeRecoveryDoesNotScheduleWakeRetryAfterManualStop()
testRuntimeRecoveryRetriesRecoverableFailures()
testRuntimeRecoveryDoesNotRetryHumanFixRequiredFailures()
testRuntimeRecoveryManualStartAndSettingsSaveReenableAutoRetry()

if failures == 0 {
    print("すべてのコアテストに成功しました。")
} else {
    fputs("\(failures) 件のコアテストが失敗しました。\n", stderr)
    exit(1)
}
