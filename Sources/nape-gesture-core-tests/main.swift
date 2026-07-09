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

func secondaryDeviceIdentity() -> DeviceIdentity {
    DeviceIdentity(
        manufacturer: "Example",
        product: "通常マウス",
        vendorID: 789,
        productID: 101,
        transport: "USB",
        primaryUsagePage: 1,
        primaryUsage: 2
    )
}

func makeHIDRecord(
    time: TimeInterval,
    device: DeviceIdentity = sampleDeviceIdentity(),
    usagePage: Int = 1,
    usage: Int = 48,
    integerValue: Int = 1
) -> HIDInputLogRecord {
    HIDInputLogRecord(
        time: time,
        device: device,
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
    flags: UInt64 = 0,
    systemTestScenario: String? = nil,
    sequenceIndex: Int? = nil
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
        flags: flags,
        systemTestScenario: systemTestScenario,
        sequenceIndex: sequenceIndex
    )
}

func makeRuntimePerformanceRecord(
    index: Int,
    tapToPostStartNanoseconds: UInt64,
    tapToPostFinishedNanoseconds: UInt64,
    source: RuntimePerformanceSource = .eventTap,
    generatedEventCount: Int = 1,
    failedEventCreationCount: Int = 0
) -> RuntimePerformanceRecord {
    let base = UInt64(1_000_000_000 + index * 100_000_000)
    return RuntimePerformanceRecord(
        operationID: "\(source.rawValue)-\(index)",
        source: source,
        action: .smoothScroll,
        commandKind: .drag,
        commandPhase: index == 0 ? .began : .changed,
        commandTimestamp: Double(index),
        inputEventTimestampNanoseconds: source == .eventTap ? base - 1_000 : nil,
        tapCallbackStartedAtNanoseconds: base,
        recognizerFinishedAtNanoseconds: base + 500_000,
        postStartedAtNanoseconds: base + tapToPostStartNanoseconds,
        postFinishedAtNanoseconds: base + tapToPostFinishedNanoseconds,
        generatedEventCount: generatedEventCount,
        failedEventCreationCount: failedEventCreationCount,
        suppressedOriginal: true
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

func testDeviceMatcherEvaluationReportsMatchedAndMismatchedConditions() {
    let device = DeviceIdentity(
        manufacturer: "Example",
        product: "Nape Pro Mouse",
        vendorID: 123,
        productID: 456,
        transport: "Bluetooth",
        primaryUsagePage: 1,
        primaryUsage: 2
    )
    let matcher = DeviceMatcher(
        vendorID: 123,
        productID: 999,
        productContains: "nape pro",
        transportContains: "usb",
        primaryUsagePage: 1
    )

    let evaluation = matcher.evaluate(device)

    expect(evaluation.conditionCount == 5, "空でない matcher 条件数を数える")
    expect(evaluation.matchedConditionCount == 3, "一致した matcher 条件数を数える")
    expect(!evaluation.isMatch, "不一致条件が残る場合は対象一致にしない")
    expect(evaluation.matchedConditions.contains("vendorID"), "一致した vendorID を記録する")
    expect(evaluation.matchedConditions.contains("product"), "一致した product contains を記録する")
    expect(evaluation.mismatches.contains { $0.field == "productID" && $0.expected == "999" && $0.actual == "456" }, "数値条件の不一致を記録する")
    expect(evaluation.mismatches.contains { $0.field == "transport" && $0.relation == "contains" }, "contains 条件の不一致を記録する")
}

func testDeviceMatcherConditionPresenceIgnoresEmptyText() {
    expect(!DeviceMatcher(productContains: "").hasAnyCondition, "空文字の製品名条件は未指定として扱う")
    expect(!DeviceMatcher(productContains: "   ").hasAnyCondition, "空白だけの製品名条件は未指定として扱う")
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
    expect(!DeviceMatcher(productContains: "   ").matches(device), "空白条件だけの matcher は全デバイス一致として扱わない")
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
    expect(analysis.unmarkedMoveEvents == 2, "未生成の移動イベント数を数える")
    expect(analysis.unmarkedScrollEvents == 0, "生成スクロールは未生成スクロールに含めない")
    expect(analysis.unmarkedPassthroughInputEvents == 2, "通常入力通過候補の未生成移動・スクロールを数える")
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

func testInputLogRecordEncodesSystemTestMetadataWhenPresent() {
    let record = makeInputLogRecord(
        timestamp: 1,
        typeName: "scrollWheel",
        generatedByNapeGesture: true,
        systemTestScenario: "space-left",
        sequenceIndex: 7
    )
    let encoded = try? JSONEncoder().encode(record)
    let encodedText = encoded.map { String(decoding: $0, as: UTF8.self) } ?? ""
    let decoded = encoded.flatMap { try? JSONDecoder().decode(InputLogRecord.self, from: $0) }

    expect(encodedText.contains("systemTestScenario"), "system-test メタ情報がある場合だけ JSON に出す")
    expect(decoded?.systemTestScenario == "space-left", "systemTestScenario を round-trip する")
    expect(decoded?.sequenceIndex == 7, "sequenceIndex を round-trip する")
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
    expect(analysis.generatedKeyEvents == 2, "生成キーイベント数を数える")
    expect(analysis.unmarkedKeyEvents == 0, "未生成キーイベント数を数える")
    expect(analysis.keyCounts["keyDown:126"] == 1, "keyDown と keyCode を集計する")
    expect(analysis.keyCounts["keyUp:126"] == 1, "keyUp と keyCode を集計する")
    expect(analysis.keySignatureCounts["generated:keyDown:126:262144"] == 1, "生成 marker と flags を含むキー署名を集計する")
    expect(comparison.keyEventDelta == 2, "キーイベント数差を出す")
    expect(comparison.keyDelta["keyDown:126"] == 1, "keyDown の差を出す")
    expect(comparison.findings.contains { $0.contains("キーイベント") }, "キーイベント差を所見に出す")
}

func testInputLogAnalyzerDoesNotTreatUnmarkedKeysAsPassthroughInput() {
    let records = [
        makeInputLogRecord(
            timestamp: 1,
            typeName: "keyDown",
            generatedByNapeGesture: false,
            keyCode: 5,
            flags: 1
        ),
        makeInputLogRecord(
            timestamp: 2,
            typeName: "keyUp",
            generatedByNapeGesture: false,
            keyCode: 5,
            flags: 1
        )
    ]

    let analysis = InputLogAnalyzer.analyze(records)

    expect(analysis.keyEvents == 2, "未生成キーイベント自体はキーとして数える")
    expect(analysis.unmarkedKeyEvents == 2, "未生成キーイベント数を数える")
    expect(analysis.unmarkedPassthroughInputEvents == 0, "キルスイッチなどの未生成キーだけでは通常入力通過扱いにしない")
}

func testGeneratedScrollLogAssertionAcceptsPhaseSeparatedMomentum() {
    let records = [
        makeInputLogRecord(
            timestamp: 1,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 40,
            pointDeltaX: 40,
            scrollPhase: 1
        ),
        makeInputLogRecord(
            timestamp: 2,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 32,
            pointDeltaX: 32,
            scrollPhase: 4
        ),
        makeInputLogRecord(
            timestamp: 3,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 24,
            pointDeltaX: 24,
            scrollPhase: 8
        ),
        makeInputLogRecord(
            timestamp: 4,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 12,
            pointDeltaX: 12,
            momentumPhase: 4
        ),
        makeInputLogRecord(
            timestamp: 5,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 0,
            scrollDeltaY: 0,
            pointDeltaX: 0,
            pointDeltaY: 0,
            momentumPhase: 8
        )
    ]

    let evaluation = GeneratedScrollLogAssertion.evaluate(records)

    expect(evaluation.passed, "通常スクロール phase と momentumPhase が分離した生成スクロールログを受理する")
    expect(evaluation.failures.isEmpty, "受理したログに失敗理由を残さない")
}

func testGeneratedScrollLogAssertionRejectsSystemTestMetadataAndPhaseMixing() {
    let records = [
        makeInputLogRecord(
            timestamp: 1,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 40,
            pointDeltaX: 40,
            scrollPhase: 1,
            momentumPhase: 4,
            systemTestScenario: "space-right",
            sequenceIndex: 0
        )
    ]

    let evaluation = GeneratedScrollLogAssertion.evaluate(records)

    expect(!evaluation.passed, "system-test メタ情報と phase 混在を含む生成スクロールログを拒否する")
    expect(evaluation.failures.contains { $0.contains("systemTestScenario") }, "systemTestScenario 混在を失敗理由に出す")
    expect(evaluation.failures.contains { $0.contains("sequenceIndex") }, "sequenceIndex 混在を失敗理由に出す")
    expect(evaluation.failures.contains { $0.contains("scrollPhase と momentumPhase") }, "phase 混在を失敗理由に出す")
}

func testGeneratedScrollLogAssertionRejectsMomentumWithoutZeroEnd() {
    let records = [
        makeInputLogRecord(
            timestamp: 1,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 40,
            pointDeltaX: 40,
            scrollPhase: 1
        ),
        makeInputLogRecord(
            timestamp: 2,
            typeName: "scrollWheel",
            generatedByNapeGesture: true,
            scrollDeltaX: 20,
            pointDeltaX: 20,
            momentumPhase: 4
        )
    ]

    let evaluation = GeneratedScrollLogAssertion.evaluate(records)

    expect(!evaluation.passed, "momentum がゼロ delta で終わらない生成スクロールログを拒否する")
    expect(evaluation.failures.contains { $0.contains("ゼロ delta") }, "momentum 終了 delta の失敗理由を出す")
}

func testInputLogAnalyzerCountsNormalClickDragAndWheelSeparately() {
    let records = [
        makeInputLogRecord(timestamp: 1, typeName: "otherMouseDown", buttonNumber: 4),
        makeInputLogRecord(timestamp: 2, typeName: "otherMouseUp", buttonNumber: 4),
        makeInputLogRecord(timestamp: 3, typeName: "leftMouseDown"),
        makeInputLogRecord(timestamp: 4, typeName: "leftMouseUp"),
        makeInputLogRecord(timestamp: 5, typeName: "leftMouseDragged", deltaX: 8),
        makeInputLogRecord(timestamp: 6, typeName: "scrollWheel", scrollDeltaY: -20)
    ]

    let analysis = InputLogAnalyzer.analyze(records)

    expect(analysis.unmarkedClickEvents == 2, "通常クリックの down/up だけを数える")
    expect(analysis.unmarkedClickDownEvents == 1, "通常クリック down を数える")
    expect(analysis.unmarkedClickUpEvents == 1, "通常クリック up を数える")
    expect(analysis.unmarkedDragEvents == 1, "通常ドラッグを数える")
    expect(analysis.unmarkedWheelEvents == 1, "通常ホイールを数える")
    expect(analysis.generatedScrollEvents == 0, "通常ホイールは生成スクロールとして扱わない")
    expect(analysis.momentumScrollEvents == 0, "momentumPhase のない通常ホイールを momentum として扱わない")
    expect(analysis.hasUnmarkedClick, "通常クリックは down/up の両方で成立する")
    expect(analysis.hasUnmarkedClickDragWheel, "通常クリック / ドラッグ / ホイールが揃う")
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
    expect(report.hasCompleteTuningEvidence, "候補と警告なしのログは完了証跡として扱える")
}

func testLogDerivedTuningAnalyzerReportsMissingSamples() {
    let report = LogDerivedTuningAnalyzer.derive(from: [])

    expect(report.suggestedAcceleration == nil, "移動速度が足りない場合は加速度候補を出さない")
    expect(report.suggestedMomentum == nil, "慣性速度が足りない場合は慣性候補を出さない")
    expect(report.warnings.contains { $0.contains("acceleration.thresholdVelocity") }, "加速度未導出理由を残す")
    expect(report.warnings.contains { $0.contains("momentum") }, "慣性未導出理由を残す")
    expect(!report.hasCompleteTuningEvidence, "未導出があるログは完了証跡として扱わない")
    expect(report.completeTuningEvidenceFailures.contains { $0.contains("入力イベント") }, "完了証跡に足りない理由を列挙する")
}

func testLogDerivedTuningAnalyzerRejectsSyntheticTimestampAsCompleteEvidence() {
    let records: [InputLogRecord] = [
        makeInputLogRecord(timestamp: 1, typeName: "mouseMoved", deltaX: 1),
        makeInputLogRecord(timestamp: 2, typeName: "mouseMoved", deltaX: 2),
        makeInputLogRecord(timestamp: 3, typeName: "mouseMoved", deltaX: 3),
        makeInputLogRecord(timestamp: 10, typeName: "scrollWheel", scrollDeltaY: -30, pointDeltaY: -30, scrollPhase: 1),
        makeInputLogRecord(timestamp: 11, typeName: "scrollWheel", scrollDeltaY: -24, pointDeltaY: -24, scrollPhase: 2),
        makeInputLogRecord(timestamp: 12, typeName: "scrollWheel", scrollDeltaY: -18, pointDeltaY: -18, momentumPhase: 1),
        makeInputLogRecord(timestamp: 13, typeName: "scrollWheel", scrollDeltaY: -12, pointDeltaY: -12, momentumPhase: 2),
        makeInputLogRecord(timestamp: 14, typeName: "scrollWheel", scrollDeltaY: -8, pointDeltaY: -8, momentumPhase: 2)
    ]

    let report = LogDerivedTuningAnalyzer.derive(from: records)

    expect(report.suggestedAcceleration != nil, "合成 timestamp でも候補自体は算出される")
    expect(report.suggestedMomentum != nil, "合成 timestamp でも慣性候補自体は算出される")
    expect(report.warnings.contains { $0.contains("timestamp") }, "合成 timestamp 警告を出す")
    expect(!report.hasCompleteTuningEvidence, "警告があるログは完了証跡として扱わない")
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
        makeHIDRecord(time: 3.0, usagePage: 1, usage: 56)
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
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.totalHIDEvents == 3, "HID ログ総数を保持する")
    expect(analysis.totalEventTapEvents == 4, "イベントタップログ総数を保持する")
    expect(analysis.analyzedEventTapEvents == 3, "未生成の mouse/button/scroll 系だけを解析対象にする")
    expect(analysis.excludedGeneratedEventTapEvents == 1, "生成済み raw input は解析対象から除外する")
    expect(analysis.hidCandidateEventCount == 3, "近い HID があるイベントタップ入力を候補ありとして数える")
    expect(analysis.missingHIDCandidateEventCount == 0, "互換 HID があれば候補なしにしない")
    expect(analysis.incompatibleHIDCandidateEventCount == 0, "互換 HID があれば非互換 HID 近傍として数えない")
    expect(analysis.targetHIDDeviceMismatchEventCount == 0, "対象外互換 HID が近くなければ mismatch として数えない")
    expect(analysis.matchedHIDDeviceIDs.count == 1, "採用した HID デバイス ID を集計する")
    expect(analysis.withinWindowCount == 1, "associationWindow 内の件数を数える")
    expect(analysis.outsideWindowCount == 2, "associationWindow 外の件数を数える")
    expect(!analysis.hasValidAssociationWindowEvidence, "window 外があれば有効な紐づけ証跡として扱わない")
    expectApproximatelyEqual(analysis.maximumTimeDifferenceSeconds, 0.65, "最大時刻差秒を出す")
    expectApproximatelyEqual(analysis.p95TimeDifferenceSeconds, 0.65, "p95 時刻差秒を出す")
    expectApproximatelyEqual(analysis.p99TimeDifferenceSeconds, 0.65, "p99 時刻差秒を出す")
    expect(analysis.suggestedAssociationWindowSeconds >= analysis.p99TimeDifferenceSeconds, "推奨 associationWindow は p99 以上にする")
}

func testInputAssociationAnalyzerCountsUnmatchedWhenHIDLogIsEmpty() {
    let eventRecords = [
        makeInputLogRecord(timestamp: 2_050_000_000, typeName: "mouseMoved")
    ]

    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [],
        eventTapRecords: eventRecords,
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 0, "HID ログが空なら候補ありにしない")
    expect(analysis.missingHIDCandidateEventCount == 1, "HID ログが空なら解析対象イベントを候補なしとして数える")
    expect(analysis.incompatibleHIDCandidateEventCount == 0, "HID ログが空なら非互換 HID 近傍として数えない")
    expect(analysis.targetHIDDeviceMismatchEventCount == 0, "HID ログが空なら対象外互換 HID 近傍として数えない")
    expect(analysis.matchedHIDDeviceIDs.isEmpty, "HID ログが空なら採用デバイス ID は空にする")
    expect(analysis.withinWindowCount == 0, "未一致イベントは associationWindow 内に数えない")
    expect(analysis.outsideWindowCount == 0, "未一致イベントは associationWindow 外にも数えない")
    expect(!analysis.hasValidAssociationWindowEvidence, "互換 HID 候補なしは有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerKeepsZeroValueHIDReleaseEvents() {
    let hidRecords = [
        makeHIDRecord(time: 10.0, usagePage: 9, usage: 5, integerValue: 0)
    ]
    let eventRecords = [
        makeInputLogRecord(timestamp: 10_020_000_000, typeName: "otherMouseUp", buttonNumber: 4)
    ]

    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: hidRecords,
        eventTapRecords: eventRecords,
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 1, "HID のゼロ値 release も一致候補として扱う")
    expect(analysis.incompatibleHIDCandidateEventCount == 0, "互換する release HID を非互換として扱わない")
    expect(analysis.withinWindowCount == 1, "release 由来のイベントタップ入力も associationWindow 内判定できる")
    expect(analysis.hasValidAssociationWindowEvidence, "候補なしも window 外もない解析対象は有効な紐づけ証跡として扱う")
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
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 1, "イベント時刻より後の近い HID も時刻差判定に使う")
    expect(analysis.withinWindowCount == 1, "前後どちらの HID でも associationWindow 内を判定する")
    expectApproximatelyEqual(analysis.matches.first?.timeDifferenceSeconds, 0.02, "HID とイベントタップの絶対時刻差を算出する")
}

func testInputAssociationAnalyzerRejectsIncompatibleHIDUsage() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, usagePage: 1, usage: 48)
        ],
        eventTapRecords: [
            makeInputLogRecord(timestamp: 2_010_000_000, typeName: "scrollWheel")
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 0, "スクロール入力に X/Y HID を候補として採用しない")
    expect(analysis.missingHIDCandidateEventCount == 1, "互換 HID がなければ候補なしとして数える")
    expect(analysis.incompatibleHIDCandidateEventCount == 1, "近傍 HID が非互換なら非互換数へ入れる")
    expect(analysis.matches.first?.nearestIncompatibleHID?.usage == 48, "非互換の近傍 HID を記録する")
    expect(analysis.matches.first?.expectedHIDUsages.contains("GenericDesktop:Wheel") == true, "期待 HID usage を matches に残す")
    expect(!analysis.hasValidAssociationWindowEvidence, "非互換 HID 近傍は有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerRejectsRuntimeUnsupportedACPan() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, usagePage: 12, usage: 568)
        ],
        eventTapRecords: [
            makeInputLogRecord(timestamp: 2_010_000_000, typeName: "scrollWheel")
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 0, "runtime が記録しない AC Pan をスクロール候補として採用しない")
    expect(analysis.incompatibleHIDCandidateEventCount == 1, "AC Pan は非互換 HID 近傍として数える")
    expect(analysis.matches.first?.expectedHIDUsages == ["GenericDesktop:Wheel"], "scrollWheel の期待 usage は runtime と同じ GenericDesktop:Wheel に限定する")
    expect(!analysis.hasValidAssociationWindowEvidence, "AC Pan だけのログは有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerRejectsButtonUsageMismatch() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, usagePage: 9, usage: 4)
        ],
        eventTapRecords: [
            makeInputLogRecord(timestamp: 2_010_000_000, typeName: "otherMouseDown", buttonNumber: 4)
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 0, "異なる HID button usage をボタン候補として採用しない")
    expect(analysis.incompatibleHIDCandidateEventCount == 1, "ボタン usage 不一致を非互換 HID 近傍として数える")
    expect(analysis.matches.first?.expectedHIDUsages == ["Button:5"], "buttonNumber に対応する HID usage だけを期待値に残す")
    expect(!analysis.hasValidAssociationWindowEvidence, "ボタン usage 不一致は有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerAcceptsCanonicalButtonUsageMapping() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, usagePage: 9, usage: 1),
            makeHIDRecord(time: 2.1, usagePage: 9, usage: 2)
        ],
        eventTapRecords: [
            makeInputLogRecord(timestamp: 2_010_000_000, typeName: "leftMouseDown", buttonNumber: 0),
            makeInputLogRecord(timestamp: 2_110_000_000, typeName: "rightMouseDown", buttonNumber: 1)
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 2, "CGEvent buttonNumber + 1 の HID Button usage を採用する")
    expect(analysis.missingHIDCandidateEventCount == 0, "canonical な button usage を候補なしにしない")
    expect(analysis.hasValidAssociationWindowEvidence, "対象デバイスの canonical な button usage は有効な証跡として扱う")
}

func testInputAssociationAnalyzerRejectsSingleNonTargetHIDDevice() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, device: secondaryDeviceIdentity(), usagePage: 1, usage: 48)
        ],
        eventTapRecords: [
            makeInputLogRecord(timestamp: 2_010_000_000, typeName: "mouseMoved")
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 0, "対象外デバイスだけなら候補として採用しない")
    expect(analysis.missingHIDCandidateEventCount == 1, "対象デバイスの互換 HID がなければ候補なしとして数える")
    expect(analysis.targetHIDDeviceMismatchEventCount == 1, "対象外の互換 HID 近傍を mismatch として数える")
    expect(analysis.matches.first?.nearestTargetMismatchHID?.device.stableID == secondaryDeviceIdentity().stableID, "対象外の近傍 HID を matches に残す")
    expect(!analysis.hasValidAssociationWindowEvidence, "対象外デバイス単体のログは有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerRejectsCloserNonTargetHIDDevice() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, device: sampleDeviceIdentity(), usagePage: 1, usage: 48),
            makeHIDRecord(time: 2.1, device: secondaryDeviceIdentity(), usagePage: 1, usage: 48)
        ],
        eventTapRecords: [
            makeInputLogRecord(timestamp: 2_010_000_000, typeName: "mouseMoved"),
            makeInputLogRecord(timestamp: 2_110_000_000, typeName: "mouseMoved")
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 2, "互換 HID があれば候補として採用する")
    expect(analysis.withinWindowCount == 2, "どちらの候補も window 内として数える")
    expect(analysis.matchedHIDDeviceIDs == [sampleDeviceIdentity().stableID], "採用 HID は対象デバイスだけに絞る")
    expect(analysis.targetHIDDeviceMismatchEventCount == 1, "より近い対象外互換 HID があれば mismatch として数える")
    expect(!analysis.hasValidAssociationWindowEvidence, "対象外互換 HID がより近いログは有効な紐づけ証跡として扱わない")
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

func testGestureActionSettingsSelectableActionsCoverAllCases() {
    let selectable = GestureAction.settingsSelectableActions
    let uniqueRawValues = Set(selectable.map(\.rawValue))

    expect(selectable == GestureAction.allCases, "設定UIの割り当て候補は GestureAction 全ケースを網羅する")
    expect(uniqueRawValues.count == selectable.count, "設定UIの割り当て候補に重複を含めない")
    expect(selectable.contains(.none), "設定UIで割り当てなしを選べる")
    expect(selectable.contains(.missionControl), "設定UIで Mission Control を選べる")
    expect(selectable.contains(.spaceLeft), "設定UIで Spaces 左移動を選べる")
    expect(selectable.contains(.spaceRight), "設定UIで Spaces 右移動を選べる")
    expect(selectable.contains(.pageBack), "設定UIでページ戻るを選べる")
    expect(selectable.contains(.pageForward), "設定UIでページ進むを選べる")
    expect(selectable.contains(.zoomIn), "設定UIでズームインを選べる")
    expect(selectable.contains(.zoomOut), "設定UIでズームアウトを選べる")
    expect(selectable.contains(.horizontalScroll), "設定UIで横スクロールを選べる")
}

func testSettingsUIFieldCatalogCoversEditableSettings() {
    let descriptors = SettingsUIField.descriptors
    let descriptorFields = descriptors.map(\.field)
    let labels = descriptors.map(\.label)
    let paths = descriptors.map(\.settingsPath)
    let requiredPaths: Set<String> = [
        "gesture.activationButton",
        "targetDeviceAssociation.associationWindow",
        "gesture.deadZonePoints",
        "gesture.directionLockRatio",
        "gesture.dragSensitivity",
        "gesture.wheelSensitivity",
        "gesture.acceleration.isEnabled",
        "gesture.acceleration.thresholdVelocity",
        "gesture.acceleration.exponent",
        "gesture.acceleration.maximumMultiplier",
        "gesture.momentum.isEnabled",
        "gesture.momentum.minimumStartVelocity",
        "gesture.momentum.stopVelocity",
        "gesture.momentum.decayPerSecond",
        "gesture.momentum.frameInterval",
        "gesture.cancellation.maximumDuration",
        "gesture.cancellation.maximumInactivityInterval",
        "gesture.cancellation.offAxisCancelRatio",
        "targetDevices[0].vendorID",
        "targetDevices[0].productID",
        "targetDevices[0].manufacturerContains",
        "targetDevices[0].productContains",
        "targetDevices[0].transportContains",
        "targetDevices[0].primaryUsagePage",
        "targetDevices[0].primaryUsage",
        "requireMatchingTargetDevice",
        "gesture.bindings.dragUp",
        "gesture.bindings.dragDown",
        "gesture.bindings.dragLeft",
        "gesture.bindings.dragRight",
        "gesture.bindings.wheel"
    ]

    expect(descriptorFields == SettingsUIField.allCases, "設定UIフィールド catalog は全ケースを順序通り公開する")
    expect(Set(labels).count == labels.count, "設定UIフィールドの表示名は重複しない")
    expect(Set(paths).count == paths.count, "設定UIフィールドの設定パスは重複しない")
    expect(Set(paths) == requiredPaths, "設定UIは完成要件の編集対象設定パスを網羅する")
    expect(
        descriptors.allSatisfy { !$0.settingsPath.localizedCaseInsensitiveContains("application") },
        "設定UI catalog にアプリ別設定パスを含めない"
    )
    expect(
        descriptors.allSatisfy { !$0.label.contains("アプリ") },
        "設定UI catalog にアプリ別設定ラベルを含めない"
    )
}

func testSettingsUIFieldCatalogKindsAndSections() {
    let descriptorsByField = Dictionary(uniqueKeysWithValues: SettingsUIField.descriptors.map { ($0.field, $0) })
    let numberFields: Set<SettingsUIField> = [
        .activationButton,
        .targetDeviceAssociationWindow,
        .deadZonePoints,
        .directionLockRatio,
        .dragSensitivity,
        .wheelSensitivity,
        .accelerationThresholdVelocity,
        .accelerationExponent,
        .accelerationMaximumMultiplier,
        .momentumMinimumStartVelocity,
        .momentumStopVelocity,
        .momentumDecayPerSecond,
        .momentumFrameInterval,
        .cancellationMaximumDuration,
        .cancellationMaximumInactivityInterval,
        .cancellationOffAxisCancelRatio,
        .targetVendorID,
        .targetProductID,
        .targetUsagePage,
        .targetUsage
    ]
    let textFields: Set<SettingsUIField> = [
        .targetManufacturerContains,
        .targetProductContains,
        .targetTransportContains
    ]
    let checkboxFields: Set<SettingsUIField> = [
        .accelerationEnabled,
        .momentumEnabled,
        .requireMatchingTargetDevice
    ]
    let actionFields: Set<SettingsUIField> = [
        .bindingDragUp,
        .bindingDragDown,
        .bindingDragLeft,
        .bindingDragRight,
        .bindingWheel
    ]

    for field in numberFields {
        expect(descriptorsByField[field]?.controlKind == .numberTextField, "\(field.rawValue) は数値入力として扱う")
    }
    for field in textFields {
        expect(descriptorsByField[field]?.controlKind == .textField, "\(field.rawValue) は文字入力として扱う")
    }
    for field in checkboxFields {
        expect(descriptorsByField[field]?.controlKind == .checkbox, "\(field.rawValue) はチェックボックスとして扱う")
    }
    for field in actionFields {
        expect(descriptorsByField[field]?.controlKind == .actionPopup, "\(field.rawValue) は割り当て popup として扱う")
        expect(
            descriptorsByField[field]?.selectableActions == GestureAction.settingsSelectableActions,
            "\(field.rawValue) は設定UIの GestureAction 候補を使う"
        )
    }

    expect(descriptorsByField[.activationButton]?.section == .gesture, "activation button は gesture section に置く")
    expect(descriptorsByField[.accelerationEnabled]?.section == .acceleration, "加速度 enable は acceleration section に置く")
    expect(descriptorsByField[.momentumEnabled]?.section == .momentum, "慣性 enable は momentum section に置く")
    expect(descriptorsByField[.cancellationMaximumDuration]?.section == .cancellation, "キャンセル条件は cancellation section に置く")
    expect(descriptorsByField[.targetVendorID]?.section == .targetDevice, "対象デバイス条件は targetDevice section に置く")
    expect(descriptorsByField[.bindingWheel]?.section == .bindings, "割り当ては bindings section に置く")
}

func testSettingsUIFieldCatalogJSONRoundTrip() {
    do {
        let data = try JSONEncoder().encode(SettingsUIField.descriptors)
        let decoded = try JSONDecoder().decode([SettingsUIFieldDescriptor].self, from: data)

        expect(decoded == SettingsUIField.descriptors, "設定UIフィールド catalog は JSON round-trip できる")
    } catch {
        expect(false, "設定UIフィールド catalog を JSON として読み書きできる: \(error)")
    }
}

func testGUIAppLaunchPresentationUsesRegularAppMode() {
    let presentation = GUIAppLaunchPresenter.regularGUIApp

    expect(presentation.activationPolicy == "regular", ".app は通常 GUI アプリとして起動する")
    expect(presentation.opensSettingsWindowOnLaunch, ".app 起動時に設定ウィンドウを開く")
    expect(presentation.reopensSettingsWindowFromDock, "Dock から再度開いたとき設定ウィンドウを再表示できる")
    expect(presentation.keepsStatusMenu, "メニューバーの NG 常駐 UI を維持する")
    expect(!presentation.bundleLSUIElement, "LSUIElement は false として Dock 表示を維持する")
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

func testRuntimeSafetyStateSuppressesPendingActivationReleaseAfterKillSwitch() {
    var state = RuntimeSafetyState()

    _ = state.stopForKillSwitch(at: 10, suppressingReleaseOf: .button4)
    let release = state.inputDecision(.buttonUp(button: .button4, time: 10.1))
    let laterClick = state.inputDecision(.buttonDown(button: .left, time: 10.2))

    expect(release.shouldSuppressOriginalEvent, "キルスイッチ時に押下中だったジェスチャーボタン解放は漏らさない")
    expect(!release.shouldProcessGestureInput, "停止後の解放はジェスチャー処理へ戻さない")
    expect(state.buttonsSuppressedUntilRelease.isEmpty, "解放を1回抑制したら pending を消す")
    expect(!laterClick.shouldSuppressOriginalEvent, "後続の通常クリックは停止状態でも通す")
    expect(!laterClick.shouldProcessGestureInput, "停止状態では後続入力をジェスチャー処理へ渡さない")
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

func testRuntimeRecoveryManualStopCancelsPendingWakeRetry() {
    var state = RuntimeRecoveryState()
    state.recordRuntimeStarted()
    _ = state.handleWillSleep(at: 10)
    _ = state.handleDidWake(at: 20, retryDelay: 5)

    let stop = state.requestManualStop(at: 21)
    let retry = state.retryIfReady(at: 25)

    expect(stop.shouldStopRuntime, "wake 後の待機中でも手動停止は runtime 停止を要求する")
    expect(!state.autoRetryEnabled, "手動停止で自動再試行を無効化する")
    expect(state.pendingRetry == nil, "手動停止で wake 後の再試行予約を破棄する")
    expect(!retry.shouldStartRuntime, "手動停止後は予約時刻を過ぎても再試行しない")
    expect(state.mode == .stopped(reason: .manualStop, stoppedAt: 21), "手動停止理由を保持する")
}

func testRuntimeRecoverySleepClearsExistingPendingRetry() {
    var state = RuntimeRecoveryState()
    _ = state.recordRuntimeFailure(.targetDeviceNotFound, at: 10)

    let sleep = state.handleWillSleep(at: 11)
    let retry = state.retryIfReady(at: 12)

    expect(sleep.shouldStopRuntime, "再試行待機中の sleep は runtime 停止を要求する")
    expect(state.pendingRetry == nil, "sleep で既存の再試行予約を破棄する")
    expect(state.isSuspendedForSleep, "sleep 後はスリープ待機として保持する")
    expect(!state.shouldShowAutoRetry, "sleep 中は自動再試行表示にしない")
    expect(!retry.shouldStartRuntime, "sleep 中は既存予約があっても再試行しない")
}

func testRuntimeRecoveryConsumesPendingRetryWhenReady() {
    var state = RuntimeRecoveryState()
    _ = state.recordRuntimeFailure(.hidAccessUnavailable, at: 10)

    let retry = state.retryIfReady(at: 10)

    expect(retry.shouldStartRuntime, "自動復旧可能な失敗は ready 時刻で再試行を開始する")
    expect(state.mode == .starting(reason: .automaticRetry(.runtimeFailure(.hidAccessUnavailable)), requestedAt: 10), "再試行開始理由を保持する")
    expect(state.pendingRetry == nil, "再試行開始時に予約を消費する")
    expect(!state.shouldShowAutoRetry, "予約消費後は自動再試行表示を消す")

    state.recordRuntimeStarted()
    expect(state.isRunning, "再試行開始後に runtime started を記録できる")
}

func testRuntimeRecoveryClampsNegativeWakeDelayToImmediateRetry() {
    var state = RuntimeRecoveryState()
    state.recordRuntimeStarted()
    _ = state.handleWillSleep(at: 10)

    _ = state.handleDidWake(at: 20, retryDelay: -1)
    let notBefore = state.pendingRetry?.notBefore
    let retry = state.retryIfReady(at: 20)

    expectApproximatelyEqual(notBefore, 20, "負の wake retryDelay は 0 に丸める")
    expect(retry.shouldStartRuntime, "負の wake retryDelay は即時再試行可能として扱う")
    expect(state.pendingRetry == nil, "即時再試行後は予約を消費する")
    expect(state.mode == .starting(reason: .automaticRetry(.wake), requestedAt: 20), "wake 由来の自動再試行として開始する")
}

func testRuntimeRecoveryDoesNotRetryAfterWakeFromInitialStop() {
    var state = RuntimeRecoveryState()

    _ = state.handleWillSleep(at: 10)
    _ = state.handleDidWake(at: 20, retryDelay: 1)
    let retry = state.retryIfReady(at: 21)

    expect(!state.shouldRetryAfterWake, "初期停止からの sleep は wake retry 対象にしない")
    expect(state.pendingRetry == nil, "初期停止からの wake は再試行予約を作らない")
    expect(!retry.shouldStartRuntime, "初期停止からの wake では自動再試行しない")
}

func testRuntimeRecoveryDoesNotRetryAfterWakeForHumanFixRequiredFailure() {
    var state = RuntimeRecoveryState()
    _ = state.recordRuntimeFailure(.invalidSettings, at: 5)

    _ = state.handleWillSleep(at: 10)
    _ = state.handleDidWake(at: 20, retryDelay: 1)
    let retry = state.retryIfReady(at: 21)

    expect(!state.shouldRetryAfterWake, "人間修正が必要な停止からの sleep は wake retry 対象にしない")
    expect(state.pendingRetry == nil, "人間修正が必要な停止からの wake は再試行予約を作らない")
    expect(!retry.shouldStartRuntime, "人間修正が必要な停止からの wake では自動再試行しない")
}

func testRuntimeRecoveryRetriesAfterWakeWhenRecoverableRetryWasPending() {
    var state = RuntimeRecoveryState()
    _ = state.recordRuntimeFailure(.targetDeviceNotFound, at: 5)

    _ = state.handleWillSleep(at: 10)
    _ = state.handleDidWake(at: 20, retryDelay: 1.5)

    expect(state.pendingRetry?.reason == .wake, "自動復旧可能な予約中の sleep は wake 後再試行に置き換える")
    expectApproximatelyEqual(state.pendingRetry?.notBefore, 21.5, "wake 後再試行の遅延を保持する")

    let retry = state.retryIfReady(at: 21.5)

    expect(retry.shouldStartRuntime, "自動復旧可能な予約中だった場合は wake 後に再試行する")
    expect(state.mode == .starting(reason: .automaticRetry(.wake), requestedAt: 21.5), "wake 由来の自動再試行として開始する")
}

func testRuntimeRecoveryKeepsWakeRetryWhenSleepNotificationRepeats() {
    var state = RuntimeRecoveryState()
    state.recordRuntimeStarted()

    _ = state.handleWillSleep(at: 10)
    _ = state.handleWillSleep(at: 10.1)
    _ = state.handleDidWake(at: 20, retryDelay: 1)
    let retry = state.retryIfReady(at: 21)

    expect(retry.shouldStartRuntime, "sleep 通知が重複しても wake 後再試行対象を維持する")
    expect(state.mode == .starting(reason: .automaticRetry(.wake), requestedAt: 21), "重複 sleep 後も wake 由来の自動再試行として開始する")
}

func testRuntimeStatusPresenterShowsRunningAndStoppedStates() {
    let running = RuntimeStatusPresenter.present(isRuntimeRunning: true, recoveryState: RuntimeRecoveryState())

    var stoppedState = RuntimeRecoveryState()
    _ = stoppedState.requestManualStop(at: 1)
    let stopped = RuntimeStatusPresenter.present(isRuntimeRunning: false, recoveryState: stoppedState)

    expect(running.stateTitle == "状態: 実行中", "実行中表示を出す")
    expect(!running.startEnabled, "実行中は開始を無効化する")
    expect(running.emergencyStopEnabled, "実行中は緊急停止を有効化する")
    expect(running.stopEnabled, "実行中は停止を有効化する")
    expect(stopped.stateTitle == "状態: 停止中", "手動停止後は停止中表示にする")
    expect(stopped.startEnabled, "停止中は開始を有効化する")
    expect(!stopped.emergencyStopEnabled, "手動停止後は緊急停止を無効化する")
    expect(!stopped.stopEnabled, "手動停止後は停止を無効化する")
}

func testRuntimeStatusPresenterShowsAutoRetryAndSleepStates() {
    var retryState = RuntimeRecoveryState()
    _ = retryState.recordRuntimeFailure(.targetDeviceNotFound, at: 10)
    let retryPresentation = RuntimeStatusPresenter.present(isRuntimeRunning: false, recoveryState: retryState)

    var sleepState = RuntimeRecoveryState()
    sleepState.recordRuntimeStarted()
    _ = sleepState.handleWillSleep(at: 20)
    let sleepPresentation = RuntimeStatusPresenter.present(isRuntimeRunning: false, recoveryState: sleepState)

    expect(retryPresentation.stateTitle == "状態: 停止中（自動再試行中）", "自動再試行中表示を出す")
    expect(retryPresentation.startEnabled, "自動再試行中でも手動開始できる")
    expect(retryPresentation.emergencyStopEnabled, "自動再試行中は緊急停止を有効化する")
    expect(retryPresentation.stopEnabled, "自動再試行中は停止を有効化する")
    expect(sleepPresentation.stateTitle == "状態: スリープ待機中", "スリープ待機中表示を自動再試行より優先する")
    expect(sleepPresentation.startEnabled, "スリープ待機中でも既存 UI と同じく開始を有効にする")
    expect(sleepPresentation.emergencyStopEnabled, "スリープ待機中は自動再試行を止められる")
    expect(sleepPresentation.stopEnabled, "スリープ待機中は停止を有効化する")
}

func testPermissionRecoveryPresenterShowsSeparatePermissionActions() {
    let presentation = PermissionRecoveryPresenter.present(
        accessibilityTrusted: false,
        inputMonitoringGranted: false,
        permissionTargetDescription: "/Applications/NapeGesture.app (bundle ID: dev.char5742.nape-gesture)"
    )

    expect(presentation.permissionTargetDescription.contains("NapeGesture.app"), "権限付与対象を表示する")
    expect(presentation.accessibility.serviceTitle == "アクセシビリティ", "アクセシビリティの表示名を固定する")
    expect(presentation.accessibility.statusTitle == "未許可", "アクセシビリティ未許可を表示する")
    expect(presentation.accessibility.shouldOpenSettings, "アクセシビリティ未許可時は設定を開く導線を出す")
    expect(presentation.accessibility.settingsButtonTitle == "アクセシビリティ設定を開く", "アクセシビリティ設定ボタン名を固定する")
    expect(
        presentation.accessibility.settingsURLString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "アクセシビリティの System Settings URL を固定する"
    )

    expect(presentation.inputMonitoring.serviceTitle == "入力監視", "入力監視の表示名を固定する")
    expect(presentation.inputMonitoring.statusTitle == "未許可または開始失敗", "入力監視未許可を表示する")
    expect(presentation.inputMonitoring.shouldOpenSettings, "入力監視未許可時は設定を開く導線を出す")
    expect(presentation.inputMonitoring.settingsButtonTitle == "入力監視設定を開く", "入力監視設定ボタン名を固定する")
    expect(
        presentation.inputMonitoring.settingsURLString == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        "入力監視の System Settings URL を固定する"
    )
    expect(presentation.restartNotice.contains("再起動"), "権限変更後の再起動案内を出す")
}

func testPermissionRecoveryPresenterDoesNotOfferGrantedActions() {
    let presentation = PermissionRecoveryPresenter.present(
        accessibilityTrusted: true,
        inputMonitoringGranted: true,
        permissionTargetDescription: "/Applications/NapeGesture.app"
    )

    expect(presentation.accessibility.statusTitle == "許可済み", "許可済みのアクセシビリティ表示を出す")
    expect(!presentation.accessibility.shouldOpenSettings, "許可済みならアクセシビリティ設定導線を必須表示しない")
    expect(presentation.inputMonitoring.statusTitle == "許可済み", "許可済みの入力監視表示を出す")
    expect(!presentation.inputMonitoring.shouldOpenSettings, "許可済みなら入力監視設定導線を必須表示しない")

    let unknown = PermissionRecoveryPresenter.present(
        accessibilityTrusted: true,
        inputMonitoringGranted: nil,
        permissionTargetDescription: "/Applications/NapeGesture.app"
    )
    expect(unknown.inputMonitoring.statusTitle == "未判定", "入力監視未判定を許可済みと混同しない")
    expect(unknown.inputMonitoring.shouldOpenSettings, "入力監視未判定時は設定導線を出す")
}

func testRuntimePerformanceAnalyzerComputesTapToPostDistributions() {
    let records = (1...20).map { index in
        makeRuntimePerformanceRecord(
            index: index,
            tapToPostStartNanoseconds: UInt64(index * 100_000),
            tapToPostFinishedNanoseconds: UInt64(index * 100_000 + 10_000)
        )
    }

    let report = RuntimePerformanceAnalyzer.analyze(records: records)
    let evaluation = RuntimePerformanceAnalyzer.evaluate(report)

    expect(report.measurementKind == "runtimeTapToPost", "runtime 性能測定種別を固定する")
    expect(report.includesEventTapAndPosting, "runtime 性能ログは event tap と投稿を含む")
    expect(report.recordCount == 20, "runtime 性能レコード数を集計する")
    expect(report.postedRecordCount == 20, "投稿ありレコード数を集計する")
    expect(report.eventTapPostedRecordCount == 20, "event tap 由来の投稿ありレコード数を集計する")
    expect(report.missingPostRecordCount == 0, "投稿なしレコードがないことを集計する")
    expect(report.generatedEventCount == 20, "生成イベント数を集計する")
    expectApproximatelyEqual(
        report.tapToFirstPostNanoseconds.p95Nanoseconds,
        1_900_000,
        "tap callback から投稿直前までの p95 を算出する"
    )
    expectApproximatelyEqual(
        report.tapToFirstPostNanoseconds.p99Nanoseconds,
        2_000_000,
        "tap callback から投稿直前までの p99 を算出する"
    )
    expectApproximatelyEqual(
        report.tapToPostFinishedNanoseconds.p95Nanoseconds,
        1_910_000,
        "tap callback から投稿完了までの p95 を算出する"
    )
    expect(evaluation.passed, "既定の runtime 性能基準内なら合格する")
}

func testRuntimePerformanceAnalyzerRejectsMissingAndSlowPosts() {
    let records = [
        makeRuntimePerformanceRecord(
            index: 1,
            tapToPostStartNanoseconds: 20_000_000,
            tapToPostFinishedNanoseconds: 21_000_000
        ),
        makeRuntimePerformanceRecord(
            index: 2,
            tapToPostStartNanoseconds: 1_000_000,
            tapToPostFinishedNanoseconds: 1_100_000,
            generatedEventCount: 0,
            failedEventCreationCount: 1
        )
    ]

    let report = RuntimePerformanceAnalyzer.analyze(records: records)
    let evaluation = RuntimePerformanceAnalyzer.evaluate(report)
    let failedItems = Set(evaluation.failures.map(\.item))

    expect(report.postedRecordCount == 1, "投稿なしレコードを postedRecordCount から除外する")
    expect(report.missingPostRecordCount == 1, "投稿なしレコードを失敗候補として集計する")
    expect(report.failedEventCreationCount == 1, "イベント作成失敗数を集計する")
    expect(!evaluation.passed, "投稿なしまたは遅延超過は runtime 性能基準で失敗する")
    expect(failedItems.contains("missingPostRecordCount"), "投稿なしレコードを基準違反にする")
    expect(failedItems.contains("failedEventCreationCount"), "イベント作成失敗を基準違反にする")
    expect(
        failedItems.contains("tapToFirstPostNanoseconds.p95Nanoseconds"),
        "tap callback から投稿直前までの p95 超過を基準違反にする"
    )
}

func testRuntimePerformanceAnalyzerDoesNotTreatMomentumAsTapToPost() {
    let records = [
        makeRuntimePerformanceRecord(
            index: 1,
            tapToPostStartNanoseconds: 1_000_000,
            tapToPostFinishedNanoseconds: 1_100_000,
            source: .momentumTimer
        )
    ]

    let report = RuntimePerformanceAnalyzer.analyze(records: records)
    let evaluation = RuntimePerformanceAnalyzer.evaluate(report)
    let failedItems = Set(evaluation.failures.map(\.item))

    expect(report.postedRecordCount == 1, "momentum timer の投稿数自体は集計する")
    expect(report.eventTapPostedRecordCount == 0, "momentum timer の投稿を event tap 由来として扱わない")
    expect(report.tapToFirstPostNanoseconds.sampleCount == 0, "momentum timer の投稿を tap-to-post 分布に混ぜない")
    expect(!evaluation.passed, "momentum timer だけでは tap-to-post 証跡として合格しない")
    expect(failedItems.contains("eventTapPostedRecordCount"), "event tap 由来投稿がないことを基準違反にする")
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
testDeviceMatcherEvaluationReportsMatchedAndMismatchedConditions()
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
testInputLogRecordEncodesSystemTestMetadataWhenPresent()
testInputLogAnalyzerComparesBaselineAndCandidate()
testInputLogAnalyzerCountsKeyEvents()
testInputLogAnalyzerDoesNotTreatUnmarkedKeysAsPassthroughInput()
testGeneratedScrollLogAssertionAcceptsPhaseSeparatedMomentum()
testGeneratedScrollLogAssertionRejectsSystemTestMetadataAndPhaseMixing()
testGeneratedScrollLogAssertionRejectsMomentumWithoutZeroEnd()
testInputLogAnalyzerCountsNormalClickDragAndWheelSeparately()
testLogDerivedTuningAnalyzerDerivesAccelerationAndMomentum()
testLogDerivedTuningAnalyzerReportsMissingSamples()
testLogDerivedTuningAnalyzerRejectsSyntheticTimestampAsCompleteEvidence()
testHIDInputLogAnalyzerGroupsByDeviceAndUsage()
testInputAssociationAnalyzerMeasuresWindowDistribution()
testInputAssociationAnalyzerCountsUnmatchedWhenHIDLogIsEmpty()
testInputAssociationAnalyzerKeepsZeroValueHIDReleaseEvents()
testInputAssociationAnalyzerUsesNearestHIDByAbsoluteTimeDifference()
testInputAssociationAnalyzerRejectsIncompatibleHIDUsage()
testInputAssociationAnalyzerRejectsRuntimeUnsupportedACPan()
testInputAssociationAnalyzerRejectsButtonUsageMismatch()
testInputAssociationAnalyzerAcceptsCanonicalButtonUsageMapping()
testInputAssociationAnalyzerRejectsSingleNonTargetHIDDevice()
testInputAssociationAnalyzerRejectsCloserNonTargetHIDDevice()
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
testGestureActionSettingsSelectableActionsCoverAllCases()
testSettingsUIFieldCatalogCoversEditableSettings()
testSettingsUIFieldCatalogKindsAndSections()
testSettingsUIFieldCatalogJSONRoundTrip()
testGUIAppLaunchPresentationUsesRegularAppMode()
testRuntimeSafetyStateStopsForKillSwitch()
testRuntimeSafetyStatePassesRegularInputAfterStop()
testRuntimeSafetyStateSuppressesPendingActivationReleaseAfterKillSwitch()
testRuntimeSafetyStateDoesNotReenableWithoutReset()
testRuntimeSafetyStateResetReenablesGestureInput()
testRuntimeRecoveryStopsBeforeSleepAndDoesNotRetryDuringSleep()
testRuntimeRecoverySchedulesDelayedWakeRetryOnlyWhenEnabled()
testRuntimeRecoveryDoesNotScheduleWakeRetryAfterManualStop()
testRuntimeRecoveryRetriesRecoverableFailures()
testRuntimeRecoveryDoesNotRetryHumanFixRequiredFailures()
testRuntimeRecoveryManualStartAndSettingsSaveReenableAutoRetry()
testRuntimeRecoveryManualStopCancelsPendingWakeRetry()
testRuntimeRecoverySleepClearsExistingPendingRetry()
testRuntimeRecoveryConsumesPendingRetryWhenReady()
testRuntimeRecoveryClampsNegativeWakeDelayToImmediateRetry()
testRuntimeRecoveryDoesNotRetryAfterWakeFromInitialStop()
testRuntimeRecoveryDoesNotRetryAfterWakeForHumanFixRequiredFailure()
testRuntimeRecoveryRetriesAfterWakeWhenRecoverableRetryWasPending()
testRuntimeRecoveryKeepsWakeRetryWhenSleepNotificationRepeats()
testRuntimeStatusPresenterShowsRunningAndStoppedStates()
testRuntimeStatusPresenterShowsAutoRetryAndSleepStates()
testPermissionRecoveryPresenterShowsSeparatePermissionActions()
testPermissionRecoveryPresenterDoesNotOfferGrantedActions()
testRuntimePerformanceAnalyzerComputesTapToPostDistributions()
testRuntimePerformanceAnalyzerRejectsMissingAndSlowPosts()
testRuntimePerformanceAnalyzerDoesNotTreatMomentumAsTapToPost()

if failures == 0 {
    print("すべてのコアテストに成功しました。")
} else {
    fputs("\(failures) 件のコアテストが失敗しました。\n", stderr)
    exit(1)
}
