import Foundation
import NapeGestureCore
import NapeGestureProductOutput

@discardableResult
func expect(
    _ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file,
    line: UInt = #line
) -> Bool {
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

func expectThrows(
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line,
    _ operation: () throws -> Void
) {
    do {
        try operation()
        fputs("失敗: \(message) (\(file):\(line))\n", stderr)
        failures += 1
    } catch {}
}

func expectNoThrow(
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line,
    _ operation: () throws -> Void
) {
    do {
        try operation()
    } catch {
        fputs("失敗: \(message)。error=\(error) (\(file):\(line))\n", stderr)
        failures += 1
    }
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
    failedEventCreationCount: Int = 0,
    gestureClass: FixedGestureClass = .twoFingerScrollSwipe,
    sourceKind: GestureInputSourceKind = .move,
    inputPhase: FixedGestureInputPhase? = nil
) -> RuntimePerformanceRecord {
    let base = UInt64(1_000_000_000 + index * 100_000_000)
    return RuntimePerformanceRecord(
        operationID: "\(source.rawValue)-\(index)",
        source: source,
        gestureClass: gestureClass,
        outputFamily: gestureClass == .twoFingerScrollSwipe
            ? .scroll
            : (gestureClass == .threeFingerSystemSwipe ? .dockSwipe : .dockSwipePinch),
        sourceKind: sourceKind,
        inputPhase: inputPhase ?? (index == 0 ? .began : .changed),
        commandTimestampNanoseconds: base - 2_000,
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

func testMouseButtonRejectsUnsupportedNumbers() {
    expect(MouseButton(buttonNumber: 3) == .button3, "button 3を正規化する")
    expect(MouseButton(buttonNumber: 5) == .button5, "button 5を正規化する")
    expect(MouseButton(buttonNumber: 6) == nil, "button 6以降をbutton 3へ誤変換しない")
    expect(MouseButton(buttonNumber: -1) == nil, "負のbutton番号を拒否する")
}

func testOtherMouseButtonInputRejectsUnsupportedNumbers() {
    expect(
        RawInputEvent.otherMouseButton(buttonNumber: 3, isDown: true, time: 1)
            == .buttonDown(button: .button3, time: 1),
        "otherMouseDownのbutton 3を入力へ変換する"
    )
    expect(
        RawInputEvent.otherMouseButton(buttonNumber: 5, isDown: false, time: 2)
            == .buttonUp(button: .button5, time: 2),
        "otherMouseUpのbutton 5を入力へ変換する"
    )
    expect(
        RawInputEvent.otherMouseButton(buttonNumber: 6, isDown: true, time: 3) == nil,
        "未知のotherMouseDownをgesture入力へ変換しない"
    )
    expect(
        RawInputEvent.otherMouseButton(buttonNumber: 6, isDown: false, time: 4) == nil,
        "未知のotherMouseUpをgesture入力へ変換しない"
    )
}

func testTrackpadGestureModesDescribeInputSeries() {
    expect(
        TrackpadGestureMode.allCases == [.none, .twoFingerSwipe, .systemSwipe, .pinch],
        "設定UIのmodeを入力系列の4択に限定する"
    )
    expect(TrackpadGestureMode.none.displayName == "通常", "未押下時と同じ通常mouse modeを表示する")
    expect(
        TrackpadGestureMode.twoFingerSwipe.displayName == "2本指スクロール / スワイプ",
        "2本指入力系列をOS/App結果名で表示しない"
    )
    expect(
        TrackpadGestureMode.systemSwipe.displayName == "システムスワイプ",
        "3本指相当の入力系列を特定のOS結果名で表示しない"
    )
    expect(
        TrackpadGestureMode.pinch.displayName == "ピンチ",
        "pinch入力系列をZoom結果名で表示しない"
    )
}

func testActivationButtonSuppressesOriginalInputBeforeThreshold() {
    var recognizer = GestureRecognizer(configuration: .default)

    let down = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let smallMove = recognizer.handle(.move(deltaX: 2, deltaY: 1, time: 1.01))

    expect(down.shouldSuppressOriginal, "ジェスチャーボタン押下は抑制する")
    expect(smallMove.shouldSuppressOriginal, "デッドゾーン内の移動も抑制する")
    expect(smallMove.commands.isEmpty, "デッドゾーン内ではジェスチャーを開始しない")
}

func testDragBeginsAfterDeadZoneWithDominantDirection() {
    var recognizer = GestureRecognizer(configuration: GestureConfiguration(deadZonePoints: 5))

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let decision = recognizer.handle(.move(deltaX: -7, deltaY: 1, time: 1.02))

    expect(decision.shouldSuppressOriginal, "ジェスチャー成立後も元イベントを抑制する")
    expect(decision.commands.count == 1, "開始コマンドを1つ出す")
    expect(decision.commands.first?.kind == .drag, "ドラッグジェスチャーとして扱う")
    expect(decision.commands.first?.phase == .began, "開始フェーズを出す")
    expect(decision.commands.first?.direction == .left, "開始時の支配方向を左として通知する")
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
                maximumInactivityInterval: 0
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
                maximumInactivityInterval: 0
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
                maximumInactivityInterval: 0.05
            )
        )
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    _ = recognizer.handle(.move(deltaX: 4, deltaY: 0, time: 1.01))
    let decision = recognizer.handle(.move(deltaX: 1, deltaY: 0, time: 1.2))

    expect(decision.commands.first?.phase == .cancelled, "無入力時間を超えた次の入力でキャンセルする")
    expect(recognizer.isIdle, "無入力キャンセル後は idle に戻る")
}

func testDragContinuesAcrossDirectionAndAxisChanges() {
    var recognizer = GestureRecognizer(
        configuration: GestureConfiguration(
            deadZonePoints: 3,
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0,
                maximumInactivityInterval: 0
            )
        )
    )

    _ = recognizer.handle(.buttonDown(button: .button4, time: 1))
    let began = recognizer.handle(.move(deltaX: 10, deltaY: 0, time: 1.01))
    let vertical = recognizer.handle(.move(deltaX: 0, deltaY: 8, time: 1.02))
    let reversed = recognizer.handle(.move(deltaX: -12, deltaY: -3, time: 1.03))
    let ended = recognizer.handle(.buttonUp(button: .button4, time: 1.04))

    expect(began.commands.first?.phase == .began, "最初の移動でドラッグを開始する")
    expect(vertical.commands.first?.phase == .changed, "途中で軸が変わっても同じドラッグを継続する")
    expect(vertical.commands.first?.kind == .drag, "軸変更後もドラッグ種別を維持する")
    expect(reversed.commands.first?.phase == .changed, "途中で方向が反転してもキャンセルしない")
    expect(reversed.commands.first?.kind == .drag, "方向反転後もドラッグ種別を維持する")
    expect(ended.commands.first?.phase == .ended, "方向と軸の変更後も通常終了する")
    expect(recognizer.isIdle, "ドラッグ終了後は idle に戻る")
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
        mode: .pinch,
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
    expect(first?.mode == .pinch, "慣性コマンドへ開始元のmodeを継承する")
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

func testMouseHIDInterfaceExcludesCompositeSiblingInterfaces() {
    let mouse = DeviceIdentity(
        manufacturer: "Example",
        product: "Composite Input",
        vendorID: 123,
        productID: 456,
        transport: "USB",
        primaryUsagePage: 1,
        primaryUsage: 2
    )
    let keyboard = DeviceIdentity(
        manufacturer: "Example",
        product: "Composite Input",
        vendorID: 123,
        productID: 456,
        transport: "USB",
        primaryUsagePage: 1,
        primaryUsage: 6
    )
    let pointer = DeviceIdentity(
        manufacturer: "Example",
        product: "Composite Input",
        vendorID: 123,
        productID: 456,
        transport: "USB",
        primaryUsagePage: 1,
        primaryUsage: 1
    )
    let vendorDefined = DeviceIdentity(
        manufacturer: "Example",
        product: "Composite Input",
        vendorID: 123,
        productID: 456,
        transport: "USB",
        primaryUsagePage: 0xFF00,
        primaryUsage: 1
    )
    let matcher = DeviceMatcher(productContains: "composite")

    let matched = MouseHIDInterface.matching(
        in: [mouse, pointer, keyboard, vendorDefined],
        matchers: [matcher]
    )
    let unconfigured = MouseHIDInterface.matching(
        in: [mouse, pointer, keyboard, vendorDefined],
        matchers: []
    )

    expect(mouse.isMouseInterface, "Generic Desktop / Mouseをマウスインターフェースとして扱う")
    expect(!pointer.isMouseInterface, "Generic Desktop / Pointerをマウスインターフェースに含めない")
    expect(!keyboard.isMouseInterface, "同じ物理機器のkeyboardインターフェースを除外する")
    expect(!vendorDefined.isMouseInterface, "同じ物理機器のvendor-definedインターフェースを除外する")
    expect(matcher.matches(keyboard), "製品名だけの条件では複合HIDの兄弟インターフェースも一致する")
    expect(matcher.matchesMouseInterface(mouse), "対象条件に一致するマウスインターフェースを受理する")
    expect(!matcher.matchesMouseInterface(keyboard), "対象条件が同じでもkeyboardインターフェースを受理しない")
    expect(matched == [mouse], "複合HID機器からマウスインターフェースだけを選択する")
    expect(unconfigured == [mouse], "対象条件が空でもマウスインターフェースだけを選択する")
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
    expect(
        evaluation.mismatches.contains {
            $0.field == "productID" && $0.expected == "999" && $0.actual == "456"
        }, "数値条件の不一致を記録する")
    expect(
        evaluation.mismatches.contains { $0.field == "transport" && $0.relation == "contains" },
        "contains 条件の不一致を記録する")
}

func testDeviceMatcherConditionPresenceIgnoresEmptyText() {
    expect(!DeviceMatcher(productContains: "").hasAnyCondition, "空文字の製品名条件は未指定として扱う")
    expect(!DeviceMatcher(productContains: "   ").hasAnyCondition, "空白だけの製品名条件は未指定として扱う")
    expect(DeviceMatcher(vendorID: 123).hasAnyCondition, "vendorID があれば条件ありとして扱う")
    expect(
        DeviceMatcher(primaryUsagePage: 1, primaryUsage: 2).hasAnyCondition, "usage 条件があれば条件ありとして扱う"
    )
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
    expect(
        !DeviceMatcher(productContains: "   ").matches(device), "空白条件だけの matcher は全デバイス一致として扱わない")
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
          "cancellation" : {
            "maximumDuration" : 10,
            "maximumInactivityInterval" : 2,
            "offAxisCancelRatio" : 0.5
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
    let reencoded = configuration.flatMap { try? JSONEncoder().encode($0) }
    let reencodedText = reencoded.map { String(decoding: $0, as: UTF8.self) } ?? ""

    expect(configuration?.mode(for: .button3) == .twoFingerSwipe, "旧設定に依存せずbutton 3を2本指へ固定する")
    expect(configuration?.mode(for: .button4) == .systemSwipe, "旧設定に依存せずbutton 4を3本指へ固定する")
    expect(configuration?.mode(for: .button5) == .pinch, "旧設定に依存せずbutton 5をピンチへ固定する")
    expect(SettingsValidator.migrationIssues(for: configuration.map {
        NapeGestureSettings(
            gesture: $0,
            targetDevices: [DeviceMatcher(productContains: "Nape Pro")]
        )
    } ?? .template).isEmpty, "有効な旧設定を完全に検証できる")
    expect(!reencodedText.contains("activationButton"), "再エンコード時は旧activationButtonを除去する")
    expect(!reencodedText.contains("bindings"), "再エンコード時は廃止済み bindings を除去する")
    expect(!reencodedText.contains("directionLockRatio"), "再エンコード時は廃止済み directionLockRatio を除去する")
    expect(!reencodedText.contains("offAxisCancelRatio"), "再エンコード時は廃止済み offAxisCancelRatio を除去する")
    expect(!reencodedText.contains("deadZonePoints"), "再エンコード時は旧dead zoneを除去する")
    expect(!reencodedText.contains("Sensitivity"), "再エンコード時は旧感度を除去する")
    expect(!reencodedText.contains("acceleration"), "再エンコード時は旧加速度を除去する")
    expect(!reencodedText.contains("momentum"), "再エンコード時は旧momentumを除去する")
}

func testGestureConfigurationMigratesResultNamedModes() {
    let json = """
        {
          "button3Mode": "scrollAndNavigate",
          "button4Mode": "spacesAndMissionControl",
          "button5Mode": "zoom"
        }
        """

    let configuration = try? JSONDecoder().decode(GestureConfiguration.self, from: Data(json.utf8))
    let encoded = configuration.flatMap { try? JSONEncoder().encode($0) }
    let encodedText = encoded.map { String(decoding: $0, as: UTF8.self) } ?? ""

    expect(configuration?.mode(for: .button3) == .twoFingerSwipe, "旧mode値に依存せずbutton 3を固定する")
    expect(configuration?.mode(for: .button4) == .systemSwipe, "旧mode値に依存せずbutton 4を固定する")
    expect(configuration?.mode(for: .button5) == .pinch, "旧mode値に依存せずbutton 5を固定する")
    expect(!encodedText.contains("button3Mode"), "保存時はbutton 3 modeを除去する")
    expect(!encodedText.contains("button4Mode"), "保存時はbutton 4 modeを除去する")
    expect(!encodedText.contains("button5Mode"), "保存時はbutton 5 modeを除去する")
    expect(!encodedText.contains("scrollAndNavigate"), "旧結果名modeを再保存しない")
    expect(!encodedText.contains("spacesAndMissionControl"), "旧システム結果名modeを再保存しない")
    expect(!encodedText.contains("\"zoom\""), "旧Zoom modeを再保存しない")
}

func testSettingsMigrationDetectsOnlyDeprecatedGestureKeys() {
    let oldJSON = Data(
        """
        {
          "gesture": {
            "activationButton": 4,
            "bindings": { "dragUp": "missionControl" },
            "cancellation": { "offAxisCancelRatio": 2.5 }
          }
        }
        """.utf8)
    let currentJSON = Data(
        """
        {
          "gesture": {
            "cancellation": {
              "maximumDuration": 10,
              "maximumInactivityInterval": 2
            }
          }
        }
        """.utf8)

    expect(
        (try? SettingsMigration.requiresCanonicalRewrite(in: oldJSON)) == true,
        "旧方向別gesture設定をmigration対象として検出する"
    )
    expect(
        (try? SettingsMigration.requiresCanonicalRewrite(in: currentJSON)) == false,
        "現行gesture設定を不要にmigrationしない"
    )

    let legacyModeJSON = Data(
        """
        {
          "gesture": {
            "button3Mode": "scrollAndNavigate",
            "button4Mode": "spacesAndMissionControl",
            "button5Mode": "zoom"
          }
        }
        """.utf8
    )
    expect(
        (try? SettingsMigration.requiresCanonicalRewrite(in: legacyModeJSON)) == true,
        "旧結果名mode値だけの設定もcanonical再保存対象にする"
    )
}

func testGestureConfigurationUsesFixedButtonMapping() {
    let configuration = GestureConfiguration.default

    expect(configuration.mode(for: .button3) == .twoFingerSwipe, "button 3は2本指スクロール / スワイプ固定")
    expect(configuration.mode(for: .button4) == .systemSwipe, "button 4は3本指システムスワイプ固定")
    expect(configuration.mode(for: .button5) == .pinch, "button 5はピンチ固定")
    expect(configuration.mode(for: .left) == .none, "通常ボタンにはtrackpad gesture modeを割り当てない")
    expect(configuration.enabledButtons == [.button3, .button4, .button5], "固定buttonを無効化できない")
}

func testRecognizerFixesButtonModeForSessionAndWaitsForMatchingRelease() {
    let configuration = GestureConfiguration(
        deadZonePoints: 1
    )
    var recognizer = GestureRecognizer(configuration: configuration)

    _ = recognizer.handle(.buttonDown(button: .button5, time: 1))
    let began = recognizer.handle(.move(deltaX: 2, deltaY: 0, time: 1.01))
    let unrelatedRelease = recognizer.handle(.buttonUp(button: .button4, time: 1.02))
    let changed = recognizer.handle(.move(deltaX: 1, deltaY: 0, time: 1.03))
    let ended = recognizer.handle(.buttonUp(button: .button5, time: 1.04))

    expect(began.commands.first?.mode == .pinch, "押下ボタンのmodeを開始コマンドへ固定する")
    expect(!unrelatedRelease.shouldSuppressOriginal, "別ボタンの解放は通過させる")
    expect(changed.commands.first?.mode == .pinch, "セッション中は押下時のmodeを維持する")
    expect(ended.commands.first?.mode == .pinch, "対応ボタンの終了コマンドにもmodeを維持する")
    expect(recognizer.isIdle, "対応ボタンの解放でのみセッションを終了する")
}

func testLegacyNoneModesCannotDisableFixedButtons() {
    let json = Data(
        """
        {
          "button3Mode": "none",
          "button4Mode": "none",
          "button5Mode": "none"
        }
        """.utf8
    )
    let configuration = try? JSONDecoder().decode(GestureConfiguration.self, from: json)
    let encoded = configuration.flatMap { try? JSONEncoder().encode($0) }
    let encodedText = encoded.map { String(decoding: $0, as: UTF8.self) } ?? ""

    expect(configuration?.mode(for: .button3) == .twoFingerSwipe, "旧noneでもbutton 3を無効化しない")
    expect(configuration?.mode(for: .button4) == .systemSwipe, "旧noneでもbutton 4を無効化しない")
    expect(configuration?.mode(for: .button5) == .pinch, "旧noneでもbutton 5を無効化しない")
    expect(!encodedText.contains("none"), "旧none modeをcanonical設定へ再保存しない")
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

func testSettingsValidatorSeparatesCanonicalAndLegacyGestureValues() {
    let settings = NapeGestureSettings(
        gesture: GestureConfiguration(
            deadZonePoints: -1,
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
                maximumInactivityInterval: -1
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

    let canonicalPaths = Set(SettingsValidator.issues(for: settings).map(\.path))
    let migrationPaths = Set(SettingsValidator.migrationIssues(for: settings).map(\.path))

    expect(canonicalPaths.contains("gesture.cancellation.maximumDuration"), "負の最大継続時間を拒否する")
    expect(canonicalPaths.contains("gesture.cancellation.maximumInactivityInterval"), "負の無入力時間を拒否する")
    expect(!canonicalPaths.contains("gesture.deadZonePoints"), "canonical検証へ旧dead zoneを含めない")
    expect(!canonicalPaths.contains("gesture.acceleration.thresholdVelocity"), "canonical検証へ旧加速度を含めない")
    expect(!canonicalPaths.contains("gesture.momentum.minimumStartVelocity"), "canonical検証へ旧momentumを含めない")
    expect(migrationPaths.contains("gesture.deadZonePoints"), "移行前に負のデッドゾーンを拒否する")
    expect(migrationPaths.contains("gesture.dragSensitivity"), "移行前に0以下のドラッグ感度を拒否する")
    expect(migrationPaths.contains("gesture.wheelSensitivity"), "移行前に0以下のホイール感度を拒否する")
    expect(migrationPaths.contains("gesture.acceleration.thresholdVelocity"), "移行前に負の加速度しきい値を拒否する")
    expect(migrationPaths.contains("gesture.acceleration.exponent"), "移行前に負の加速度指数を拒否する")
    expect(migrationPaths.contains("gesture.acceleration.maximumMultiplier"), "移行前に1未満の加速度最大倍率を拒否する")
    expect(migrationPaths.contains("gesture.momentum.minimumStartVelocity"), "移行前に負の慣性開始速度を拒否する")
    expect(migrationPaths.contains("gesture.momentum.stopVelocity"), "移行前に負の慣性停止速度を拒否する")
    expect(migrationPaths.contains("gesture.momentum.decayPerSecond"), "移行前に範囲外の慣性減衰率を拒否する")
    expect(migrationPaths.contains("gesture.momentum.frameInterval"), "移行前に0以下の慣性フレーム間隔を拒否する")
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
            DeviceMatcher(),
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
        ),
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

func testTrackpadDriverEventLogRoundTrips() {
    let metadata = TrackpadDriverEventLogMetadata(
        osVersion: "26.0.0",
        osBuild: "25A123",
        scenarioID: "two-finger-scroll",
        deviceLabel: "built-in-trackpad",
        repoHeadSHA: String(repeating: "a", count: 40)
    )
    let serializedEvent = Data([1, 2, 3, 4])
    let record = TrackpadDriverEventLog(
        metadata: metadata,
        captureIndex: 17,
        timestamp: 987_654_321,
        typeRaw: 29,
        typeName: "raw-29",
        eventSubtype: 2,
        flags: 1_048_576,
        scrollDeltaX: -2,
        scrollDeltaY: 3,
        scrollDeltaZ: 4,
        scrollFixedDeltaX: -2.5,
        scrollFixedDeltaY: 3.5,
        scrollFixedDeltaZ: 4.5,
        scrollPointDeltaX: -20,
        scrollPointDeltaY: 30,
        scrollPointDeltaZ: 40,
        scrollPhase: 2,
        momentumPhase: 8,
        isContinuous: 1,
        sourceUserData: 1234,
        rawFields: [
            TrackpadDriverRawField(
                fieldNumber: 42,
                integerValue: 1234,
                doubleValue: 1234,
                doubleBitPattern: Double(1234).bitPattern
            ),
            TrackpadDriverRawField(
                fieldNumber: 99,
                integerValue: 2,
                doubleValue: 2,
                doubleBitPattern: Double(2).bitPattern
            ),
        ],
        serializedEventBase64: serializedEvent.base64EncodedString()
    )
    let encoded = try? JSONEncoder().encode(record)
    let decoded = encoded.flatMap {
        try? JSONDecoder().decode(TrackpadDriverEventLog.self, from: $0)
    }
    let decodedSerializedEvent = decoded?.serializedEventBase64.flatMap { Data(base64Encoded: $0) }

    expect(decoded == record, "トラックパッド診断イベントを JSON round-trip する")
    expect(
        decoded?.schemaVersion == TrackpadDriverEventLog.currentSchemaVersion,
        "現行 schemaVersion を保持する")
    expect(decoded?.metadata == metadata, "OS・logger・scenario・device・repo metadata を保持する")
    expect(
        decoded?.metadata?.loggerVersion == TrackpadDriverEventLogMetadata.currentLoggerVersion,
        "logger version を保持する"
    )
    expect(decoded?.captureIndex == 17, "captureIndex を保持する")
    expect(decoded?.eventSubtype == 2, "取得可能なevent subtypeを保持する")
    expect(decodedSerializedEvent == serializedEvent, "serializedEventBase64から正本event dataを復元できる")
    expect(
        decoded?.rawFieldScanUpperBound == TrackpadDriverEventLog.maximumRawFieldNumber,
        "raw field scan 上限を保持する"
    )
}

func testTrackpadDriverEventLogDecodesLegacyRecordWithDefaults() {
    let json = """
        {
          "timestamp": 123,
          "typeRaw": 30,
          "typeName": "raw-30",
          "flags": 256,
          "scrollDeltaY": -3,
          "rawFields": {
            "42": { "integerValue": 7 }
          }
        }
        """

    let record = try? JSONDecoder().decode(TrackpadDriverEventLog.self, from: Data(json.utf8))

    expect(record?.schemaVersion == 0, "schemaVersion 導入前の診断ログを schema 0 として読む")
    expect(record?.metadata == nil, "旧診断ログにないmetadataを推測しない")
    expect(record?.captureIndex == nil, "旧診断ログにないcaptureIndexを推測しない")
    expect(record?.eventSubtype == nil, "旧診断ログにないevent subtypeを推測しない")
    expect(record?.scrollDeltaY == -3, "旧診断ログに存在する公開 scroll 値を読む")
    expect(record?.scrollFixedDeltaY == 0, "旧診断ログにない fixed delta は 0 へ補完する")
    expect(record?.scrollPointDeltaY == 0, "旧診断ログにない point delta は 0 へ補完する")
    expect(record?.sourceUserData == 0, "旧診断ログにない source userData は 0 へ補完する")
    expect(record?.rawFieldScanUpperBound == nil, "旧診断ログにない raw field scan 上限を推測しない")
    expect(record?.rawField(number: 42)?.integerValue == 7, "旧診断ログの raw field map を保持する")
    expect(record?.serializedEventBase64 == nil, "旧診断ログにない serialized event は nil とする")
}

func testTrackpadDriverEventLogRawFieldsUseStableNumericOrder() {
    let fieldNumbers = Array(
        TrackpadDriverEventLog.rawFieldScanLowerBound...TrackpadDriverEventLog.maximumRawFieldNumber
    )
    let rawFields = fieldNumbers.map { fieldNumber in
        let integerValue: Int64 = fieldNumber == 29 ? 7 : 0
        let doubleValue: Double = fieldNumber == 29 ? -1.25 : 0
        return TrackpadDriverRawField(
            fieldNumber: fieldNumber,
            integerValue: integerValue,
            doubleValue: doubleValue,
            doubleBitPattern: doubleValue.bitPattern
        )
    }
    let record = TrackpadDriverEventLog(
        metadata: TrackpadDriverEventLogMetadata(osVersion: "26.0.0", osBuild: "25A123"),
        captureIndex: 0,
        timestamp: 1,
        typeRaw: 31,
        typeName: "raw-31",
        eventSubtype: 0,
        rawFields: rawFields
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try? encoder.encode(record)
    let decoded = encoded.flatMap {
        try? JSONDecoder().decode(TrackpadDriverEventLog.self, from: $0)
    }
    let reencoded = decoded.flatMap { try? encoder.encode($0) }
    let decodedFieldNumbers = decoded?.rawFields.map(\.fieldNumber) ?? []

    expect(decoded?.rawFields.count == 256, "raw field 0...255を全件保持する")
    expect(decodedFieldNumbers == fieldNumbers, "raw fieldをfieldNumberの数値昇順で保持する")
    expect(decoded?.rawField(number: 0)?.integerValue == 0, "integer fieldのzero値を捨てない")
    expect(decoded?.rawField(number: 0)?.doubleValue == 0, "double fieldのzero値を捨てない")
    expect(
        decoded?.rawField(number: 0)?.doubleBitPattern == Double(0).bitPattern,
        "double fieldのzero bit patternを保持する")
    expect(
        decoded?.metadata?.rawFieldScanPolicy
            == TrackpadDriverEventLogMetadata.allRawFieldValuesPolicy,
        "全raw field値をzero込みで保存するpolicyを明示する"
    )
    expect(encoded == reencoded, "ordered raw field arrayを安定して再エンコードする")
}

func testTrackpadDriverEventLogPreservesNonFiniteNamedDoubleBitPatterns() {
    let record = TrackpadDriverEventLog(
        timestamp: 1,
        typeRaw: 22,
        typeName: "scrollWheel",
        scrollFixedDeltaX: nil,
        scrollFixedDeltaXBitPattern: Double.nan.bitPattern,
        scrollPointDeltaY: nil,
        scrollPointDeltaYBitPattern: Double.infinity.bitPattern
    )
    let encoded = try? JSONEncoder().encode(record)
    let decoded = encoded.flatMap {
        try? JSONDecoder().decode(TrackpadDriverEventLog.self, from: $0)
    }

    expect(encoded != nil, "非有限named doubleでもJSON encodeを失敗させない")
    expect(decoded?.scrollFixedDeltaX == nil, "NaNの有限値を捏造しない")
    expect(decoded?.scrollFixedDeltaXBitPattern == Double.nan.bitPattern, "NaNのbit patternを保持する")
    expect(decoded?.scrollPointDeltaY == nil, "infinityの有限値を捏造しない")
    expect(
        decoded?.scrollPointDeltaYBitPattern == Double.infinity.bitPattern,
        "infinityのbit patternを保持する")
}

func testTrackpadDriverEventLogJSONLinesPreserveCaptureOrder() {
    let metadata = TrackpadDriverEventLogMetadata(
        osVersion: "26.0.0",
        osBuild: "25A123",
        scenarioID: "ordered-capture",
        deviceLabel: "built-in-trackpad",
        repoHeadSHA: String(repeating: "b", count: 40)
    )
    var records: [TrackpadDriverEventLog] = []
    for index in 0..<3 {
        let serializedEventBase64 = Data([UInt8(index)]).base64EncodedString()
        let record = TrackpadDriverEventLog(
            metadata: metadata,
            captureIndex: UInt64(index),
            timestamp: UInt64(1_000 + index),
            typeRaw: 29 + index,
            typeName: "raw-\(29 + index)",
            eventSubtype: Int64(index),
            serializedEventBase64: serializedEventBase64
        )
        records.append(record)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let lines: [Data] = records.compactMap { record in
        try? encoder.encode(record)
    }
    let decoded: [TrackpadDriverEventLog] = lines.compactMap { line in
        try? JSONDecoder().decode(TrackpadDriverEventLog.self, from: line)
    }
    let captureIndices = decoded.compactMap { $0.captureIndex }
    let timestamps = decoded.map { $0.timestamp }

    expect(lines.count == records.count, "各captureを1行のJSON Linesとしてencodeする")
    expect(captureIndices == [0, 1, 2], "captureIndex順をJSON Linesで保持する")
    expect(timestamps == [1_000, 1_001, 1_002], "capture順とevent timestampの対応を保持する")
    expect(decoded.allSatisfy { $0.metadata == metadata }, "各eventへ同一run metadataを保存する")
    expect(
        decoded.allSatisfy {
            $0.metadata?.canonicalEventRepresentation
                == TrackpadDriverEventLogMetadata.defaultCanonicalEventRepresentation
        },
        "serializedEventBase64を各eventの正本として明示する"
    )
}

func monotonicTimestamp(_ nanosecondsSinceStartup: UInt64) -> MonotonicEventTimestamp {
    guard
        let timestamp = MonotonicEventClock.timestamp(
            nanosecondsSinceStartup: nanosecondsSinceStartup
        )
    else {
        fatalError("test timestampが現在bootのuptimeを超えています。")
    }
    return timestamp
}

func makeTrackpadScrollInputEvent(
    sessionID: TrackpadOutputSessionID,
    captureOrder: UInt64,
    timestamp: UInt64,
    phase: TrackpadOutputInputPhase,
    continuation: TrackpadOutputContinuation? = nil
) -> TrackpadOutputSessionEvent {
    .input(
        TrackpadOutputInputFrame(
            sessionID: sessionID,
            captureOrder: captureOrder,
            timestamp: monotonicTimestamp(timestamp),
            phase: phase,
            continuation: continuation,
            payload: .scroll(deltaX: 1, deltaY: -2, velocityX: 10, velocityY: -20)
        )
    )
}

func makeTrackpadScrollMomentumEvent(
    sessionID: TrackpadOutputSessionID,
    captureOrder: UInt64,
    timestamp: UInt64,
    phase: TrackpadOutputMomentumPhase
) -> TrackpadOutputSessionEvent {
    .momentum(
        TrackpadOutputMomentumFrame(
            sessionID: sessionID,
            captureOrder: captureOrder,
            timestamp: monotonicTimestamp(timestamp),
            phase: phase,
            payload: .scroll(deltaX: 0.5, deltaY: -1, velocityX: 5, velocityY: -10)
        )
    )
}

func makeTrackpadCancellationEvent(
    sessionID: TrackpadOutputSessionID,
    captureOrder: UInt64,
    timestamp: UInt64,
    family: TrackpadOutputEventFamily,
    reason: TrackpadOutputCancellationReason,
    payload: TrackpadOutputPayload?
) -> TrackpadOutputSessionEvent {
    .cancellation(
        TrackpadOutputCancellationFrame(
            sessionID: sessionID,
            captureOrder: captureOrder,
            timestamp: monotonicTimestamp(timestamp),
            family: family,
            reason: reason,
            payload: payload
        )
    )
}

func testMonotonicEventClockUsesStartupNanoseconds() {
    let timestamp: UInt64 = 1_234_567
    let seconds = MonotonicEventClock.seconds(fromTimestampNanoseconds: timestamp)
    let roundTripped = MonotonicEventClock.timestamp(fromSecondsSinceStartup: seconds)

    expectApproximatelyEqual(seconds, 0.001234567, "起動後ナノ秒を起動後秒へ変換する")
    expect(
        roundTripped.map { abs(Int64($0.nanosecondsSinceStartup) - Int64(timestamp)) <= 1 } == true,
        "起動後秒をナノ秒へ戻す"
    )
    expect(
        MonotonicEventClock.timestamp(fromSecondsSinceStartup: -1) == nil,
        "負の時刻を起動後時刻へ変換しない"
    )
    expect(
        MonotonicEventClock.timestamp(fromSecondsSinceStartup: .infinity) == nil,
        "非有限時刻を起動後時刻へ変換しない"
    )
    expect(
        MonotonicEventClock.timestamp(fromSecondsSinceStartup: 1_700_000_000) == nil,
        "Unix epoch秒を現在bootの起動後時刻として受理しない"
    )
    expect(
        MonotonicEventClock.timestamp(
            nanosecondsSinceStartup: 1_700_000_000_000_000_000
        ) == nil,
        "Unix epochナノ秒からMonotonicEventTimestampを作らない"
    )
    expectApproximatelyEqual(
        MonotonicEventClock.elapsedSeconds(from: 4.5, to: 5),
        0.5,
        "単調時刻の経過秒を計算する"
    )
    expect(MonotonicEventClock.elapsedSeconds(from: 5, to: 4.5) == nil, "時刻逆行を拒否する")
    expect(MonotonicEventClock.now.nanosecondsSinceStartup > 0, "共通clockが起動後時刻を返す")
}

func testTrackpadOutputSessionSequenceDoesNotReuseIDs() {
    let sequence = TrackpadOutputSessionSequence(startingAt: 7)
    let first = try? sequence.next()
    let second = try? sequence.next()

    expect(first == TrackpadOutputSessionID(rawValue: 7), "session sequenceの開始IDを保持する")
    expect(second == TrackpadOutputSessionID(rawValue: 8), "session sequenceを単調増加させる")

    let finalSequence = TrackpadOutputSessionSequence(startingAt: UInt64.max)
    let finalID = try? finalSequence.next()
    var exhaustion: TrackpadOutputSessionSequenceError?
    do {
        _ = try finalSequence.next()
    } catch let error as TrackpadOutputSessionSequenceError {
        exhaustion = error
    } catch {
        expect(false, "session sequence枯渇時に別種errorを返さない")
    }
    expect(finalID == TrackpadOutputSessionID(rawValue: UInt64.max), "最大session IDを一度だけ返す")
    expect(exhaustion == .exhausted, "session IDをoverflowして再利用しない")
}

func testTrackpadOutputSessionSequenceIsUniqueAcrossConcurrentCallers() {
    let sequence = TrackpadOutputSessionSequence(startingAt: 1)
    let resultLock = NSLock()
    let group = DispatchGroup()
    let queue = DispatchQueue(
        label: "trackpad-output-session-sequence-test", attributes: .concurrent)
    var rawValues: [UInt64] = []

    for _ in 0..<1_000 {
        group.enter()
        queue.async {
            let rawValue = try? sequence.next().rawValue
            resultLock.lock()
            if let rawValue {
                rawValues.append(rawValue)
            }
            resultLock.unlock()
            group.leave()
        }
    }
    group.wait()

    expect(rawValues.count == 1_000, "並列callerへ全session IDを返す")
    expect(Set(rawValues).count == 1_000, "並列caller間でsession IDを再利用しない")
    expect(rawValues.min() == 1 && rawValues.max() == 1_000, "session IDを欠落なく発行する")
}

func testTrackpadOutputSessionSeparatesInputAndMomentumLifecycles() {
    let sessionID = TrackpadOutputSessionID(rawValue: 42)
    var machine = TrackpadOutputSessionMachine(sessionID: sessionID, family: .scroll)

    do {
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: sessionID,
                captureOrder: 0,
                timestamp: 100,
                phase: .began
            )
        )
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: sessionID,
                captureOrder: 1,
                timestamp: 101,
                phase: .changed
            )
        )
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: sessionID,
                captureOrder: 2,
                timestamp: 102,
                phase: .ended,
                continuation: .momentum
            )
        )
        expect(machine.state == .awaitingMomentum, "input ended後にmomentum開始待ちを明示する")

        try machine.accept(
            makeTrackpadScrollMomentumEvent(
                sessionID: sessionID,
                captureOrder: 3,
                timestamp: 102,
                phase: .began
            )
        )
        try machine.accept(
            makeTrackpadScrollMomentumEvent(
                sessionID: sessionID,
                captureOrder: 4,
                timestamp: 103,
                phase: .continued
            )
        )
        try machine.accept(
            makeTrackpadScrollMomentumEvent(
                sessionID: sessionID,
                captureOrder: 5,
                timestamp: 104,
                phase: .ended
            )
        )
    } catch {
        expect(false, "正しいinput / momentum lifecycleを受理する: \(error)")
    }

    let terminal = try? machine.requireTerminal()
    expect(terminal?.kind == .momentumEnded, "momentum endedをsession terminalとして保持する")
    expect(terminal?.finalPayload?.family == .scroll, "momentum terminalに最終scroll payloadを保持する")
    expect(machine.lastCaptureOrder == 5, "session全体でcapture orderを保持する")
    expect(
        machine.lastTimestamp == monotonicTimestamp(104),
        "inputとmomentumで同じ起動後時刻domainを使う"
    )
}

func testTrackpadOutputSessionPreservesGestureProgressAndDecision() {
    let sessionID = TrackpadOutputSessionID(rawValue: 50)
    var machine = TrackpadOutputSessionMachine(sessionID: sessionID, family: .dockSwipe)
    let began = TrackpadOutputSessionEvent.input(
        TrackpadOutputInputFrame(
            sessionID: sessionID,
            captureOrder: 0,
            timestamp: monotonicTimestamp(200),
            phase: .began,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: 0.1,
                motionX: -0.2,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        )
    )
    let ended = TrackpadOutputSessionEvent.input(
        TrackpadOutputInputFrame(
            sessionID: sessionID,
            captureOrder: 1,
            timestamp: monotonicTimestamp(201),
            phase: .ended,
            continuation: .complete,
            terminalDecision: .commit,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: 0.9,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: -2.5,
                terminalVelocityY: 0
            )
        )
    )

    do {
        try machine.accept(began)
        try machine.accept(ended)
    } catch {
        expect(false, "DockSwipeのprogress / terminalを受理する: \(error)")
    }

    let terminal = try? machine.requireTerminal()
    expect(terminal?.kind == .inputEnded, "gesture input endedをterminalとして保持する")
    expect(terminal?.decision == .commit, "gestureのcommit判断を保持する")
    expect(terminal?.finalPayload?.family == .dockSwipe, "gesture terminalに最終payloadを保持する")
    if case .input(let endedFrame) = ended,
        case .dockSwipe(
            let axis,
            let progress,
            _,
            _,
            let terminalVelocityX,
            _
        ) = endedFrame.payload
    {
        expect(axis == .horizontal, "DockSwipeの軸を保持する")
        expectApproximatelyEqual(progress, 0.9, "終了時progressを保持する")
        expectApproximatelyEqual(terminalVelocityX, -2.5, "終了時velocityを保持する")
    } else {
        expect(false, "DockSwipe payloadを別familyへ変換しない")
    }

    let encoded = try? JSONEncoder().encode(ended)
    let decoded = encoded.flatMap {
        try? JSONDecoder().decode(TrackpadOutputSessionEvent.self, from: $0)
    }
    expect(decoded == ended, "session eventをJSON round-tripする")
}

func testTrackpadOutputSessionSupportsDockSwipeClasses() {
    let dockID = TrackpadOutputSessionID(rawValue: 55)
    var dockMachine = TrackpadOutputSessionMachine(sessionID: dockID, family: .dockSwipe)
    let dockEvents: [TrackpadOutputSessionEvent] = [
        .input(
            TrackpadOutputInputFrame(
                sessionID: dockID,
                captureOrder: 0,
                timestamp: monotonicTimestamp(250),
                phase: .began,
                payload: .dockSwipe(
                    axis: .horizontal,
                    progress: 0,
                    motionX: 0,
                    motionY: 0,
                    terminalVelocityX: 0,
                    terminalVelocityY: 0
                )
            )
        ),
        .input(
            TrackpadOutputInputFrame(
                sessionID: dockID,
                captureOrder: 1,
                timestamp: monotonicTimestamp(251),
                phase: .ended,
                continuation: .complete,
                terminalDecision: .commit,
                payload: .dockSwipe(
                    axis: .horizontal,
                    progress: 1,
                    motionX: 0,
                    motionY: 0,
                    terminalVelocityX: 2,
                    terminalVelocityY: 0
                )
            )
        ),
    ]
    for event in dockEvents {
        do {
            try dockMachine.accept(event)
        } catch {
            expect(false, "DockSwipeの正常sessionを受理する: \(error)")
        }
    }
    expect((try? dockMachine.requireTerminal())?.decision == .commit, "DockSwipeのcommitを保持する")

    let pinchID = TrackpadOutputSessionID(rawValue: 56)
    var pinchMachine = TrackpadOutputSessionMachine(
        sessionID: pinchID,
        family: .dockSwipePinch
    )
    let pinchEvents: [TrackpadOutputSessionEvent] = [
        .input(
            TrackpadOutputInputFrame(
                sessionID: pinchID,
                captureOrder: 0,
                timestamp: monotonicTimestamp(260),
                phase: .began,
                payload: .dockSwipePinch(progress: 0, motion: 0, terminalVelocity: 0)
            )
        ),
        .input(
            TrackpadOutputInputFrame(
                sessionID: pinchID,
                captureOrder: 1,
                timestamp: monotonicTimestamp(261),
                phase: .changed,
                payload: .dockSwipePinch(progress: 0.5, motion: 0.1, terminalVelocity: 0)
            )
        ),
        .input(
            TrackpadOutputInputFrame(
                sessionID: pinchID,
                captureOrder: 2,
                timestamp: monotonicTimestamp(262),
                phase: .ended,
                continuation: .complete,
                terminalDecision: .cancel,
                payload: .dockSwipePinch(progress: 0.5, motion: 0, terminalVelocity: 0.2)
            )
        ),
    ]
    for event in pinchEvents {
        do {
            try pinchMachine.accept(event)
        } catch {
            expect(false, "DockSwipe pinchの正常sessionを受理する: \(error)")
        }
    }
    expect(
        (try? pinchMachine.requireTerminal())?.decision == .cancel,
        "DockSwipe pinchのcancelを保持する")
}

func testTrackpadOutputSessionEventCodableCoversEveryEventKind() {
    let sessionID = TrackpadOutputSessionID(rawValue: 57)
    let events: [TrackpadOutputSessionEvent] = [
        makeTrackpadScrollInputEvent(
            sessionID: sessionID,
            captureOrder: 0,
            timestamp: 270,
            phase: .began
        ),
        makeTrackpadScrollMomentumEvent(
            sessionID: sessionID,
            captureOrder: 1,
            timestamp: 271,
            phase: .continued
        ),
        makeTrackpadCancellationEvent(
            sessionID: sessionID,
            captureOrder: 2,
            timestamp: 272,
            family: .scroll,
            reason: .runtimeStop,
            payload: .scroll(deltaX: 0, deltaY: 0, velocityX: 0, velocityY: 0)
        ),
    ]

    for event in events {
        let encoded = try? JSONEncoder().encode(event)
        let decoded = encoded.flatMap {
            try? JSONDecoder().decode(TrackpadOutputSessionEvent.self, from: $0)
        }
        expect(decoded == event, "input / momentum / cancellationの各event kindをJSON round-tripする")
    }
}

func testTrackpadOutputSessionRejectsInvalidOrderAndDoubleTerminalAtomically() {
    let sessionID = TrackpadOutputSessionID(rawValue: 60)
    var machine = TrackpadOutputSessionMachine(sessionID: sessionID, family: .scroll)
    var receivedError: TrackpadOutputSessionError?

    do {
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: sessionID,
                captureOrder: 0,
                timestamp: 300,
                phase: .changed
            )
        )
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .invalidTransition(state: .awaitingInput, event: .input(.changed)),
        "began前のchangedを拒否する"
    )
    expect(machine.lastCaptureOrder == nil, "拒否eventでcapture orderを進めない")

    try? machine.accept(
        makeTrackpadScrollInputEvent(
            sessionID: sessionID,
            captureOrder: 0,
            timestamp: 300,
            phase: .began
        )
    )

    receivedError = nil
    do {
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: sessionID,
                captureOrder: 2,
                timestamp: 301,
                phase: .changed
            )
        )
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(receivedError == .invalidCaptureOrder(expected: 1, actual: 2), "capture order欠落を拒否する")
    expect(machine.lastCaptureOrder == 0, "順序違反でaccepted stateを変更しない")

    receivedError = nil
    do {
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: sessionID,
                captureOrder: 1,
                timestamp: 299,
                phase: .changed
            )
        )
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError
            == .timestampRegression(
                previous: monotonicTimestamp(300),
                actual: monotonicTimestamp(299)
            ),
        "session内の時刻逆行を拒否する"
    )
    expect(machine.lastCaptureOrder == 0, "時刻違反でcapture orderを消費しない")

    try? machine.accept(
        makeTrackpadScrollInputEvent(
            sessionID: sessionID,
            captureOrder: 1,
            timestamp: 301,
            phase: .ended,
            continuation: .complete
        )
    )
    let terminal = try? machine.requireTerminal()
    receivedError = nil
    do {
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: sessionID,
                captureOrder: 2,
                timestamp: 302,
                phase: .ended,
                continuation: .complete
            )
        )
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == terminal.map { .terminalAlreadyReached($0) },
        "二重terminalを拒否する"
    )
    expect(machine.lastCaptureOrder == 1, "二重terminalでsessionを変更しない")
}

func testTrackpadOutputSessionRejectsStuckAndInvalidFamilyMetadata() {
    let scrollID = TrackpadOutputSessionID(rawValue: 70)
    var scrollMachine = TrackpadOutputSessionMachine(sessionID: scrollID, family: .scroll)
    try? scrollMachine.accept(
        makeTrackpadScrollInputEvent(
            sessionID: scrollID,
            captureOrder: 0,
            timestamp: 400,
            phase: .began
        )
    )
    try? scrollMachine.accept(
        makeTrackpadScrollInputEvent(
            sessionID: scrollID,
            captureOrder: 1,
            timestamp: 401,
            phase: .ended,
            continuation: .momentum
        )
    )

    var receivedError: TrackpadOutputSessionError?
    do {
        _ = try scrollMachine.requireTerminal()
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .sessionIncomplete(.awaitingMomentum), "momentum未開始のstuck sessionを完了扱いにしない"
    )

    receivedError = nil
    do {
        try scrollMachine.accept(
            makeTrackpadScrollMomentumEvent(
                sessionID: scrollID,
                captureOrder: 2,
                timestamp: 402,
                phase: .continued
            )
        )
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .invalidTransition(state: .awaitingMomentum, event: .momentum(.continued)),
        "momentum began前のcontinuedを拒否する"
    )

    let dockID = TrackpadOutputSessionID(rawValue: 71)
    var dockMachine = TrackpadOutputSessionMachine(sessionID: dockID, family: .dockSwipe)
    let dockBegan = TrackpadOutputSessionEvent.input(
        TrackpadOutputInputFrame(
            sessionID: dockID,
            captureOrder: 0,
            timestamp: monotonicTimestamp(500),
            phase: .began,
            payload: .dockSwipe(
                axis: .vertical,
                progress: 0,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        )
    )
    let dockEndedWithoutDecision = TrackpadOutputSessionEvent.input(
        TrackpadOutputInputFrame(
            sessionID: dockID,
            captureOrder: 1,
            timestamp: monotonicTimestamp(501),
            phase: .ended,
            continuation: .complete,
            payload: .dockSwipe(
                axis: .vertical,
                progress: 1,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 3
            )
        )
    )
    try? dockMachine.accept(dockBegan)
    receivedError = nil
    do {
        try dockMachine.accept(dockEndedWithoutDecision)
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .invalidInputMetadata(phase: .ended),
        "gesture terminalのcommit / cancel欠落を拒否する"
    )
    expect(dockMachine.state == .inputActive, "metadata違反でgesture stateをterminalにしない")

    let nonFinite = TrackpadOutputSessionEvent.input(
        TrackpadOutputInputFrame(
            sessionID: dockID,
            captureOrder: 1,
            timestamp: monotonicTimestamp(501),
            phase: .changed,
            payload: .dockSwipe(
                axis: .vertical,
                progress: .nan,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        )
    )
    receivedError = nil
    do {
        try dockMachine.accept(nonFinite)
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(receivedError == .nonFinitePayload, "非有限progressを拒否する")
    expect(dockMachine.lastCaptureOrder == 0, "非有限payloadでcapture orderを消費しない")
}

func testTrackpadOutputSessionCancelsEveryNonterminalState() {
    let awaitingInputID = TrackpadOutputSessionID(rawValue: 80)
    var awaitingInput = TrackpadOutputSessionMachine(sessionID: awaitingInputID, family: .scroll)
    try? awaitingInput.accept(
        makeTrackpadCancellationEvent(
            sessionID: awaitingInputID,
            captureOrder: 0,
            timestamp: 600,
            family: .scroll,
            reason: .runtimeStop,
            payload: nil
        )
    )
    let awaitingInputTerminal = try? awaitingInput.requireTerminal()
    expect(awaitingInputTerminal?.kind == .sessionCancelled, "input開始前のsessionを明示cancelできる")
    expect(awaitingInputTerminal?.cancellationReason == .runtimeStop, "runtime停止理由を保持する")
    expect(awaitingInputTerminal?.finalPayload == nil, "input開始前のcancelで存在しないpayloadを捏造しない")

    let inputActiveID = TrackpadOutputSessionID(rawValue: 81)
    var inputActive = TrackpadOutputSessionMachine(sessionID: inputActiveID, family: .dockSwipe)
    try? inputActive.accept(
        .input(
            TrackpadOutputInputFrame(
                sessionID: inputActiveID,
                captureOrder: 0,
                timestamp: monotonicTimestamp(610),
                phase: .began,
                payload: .dockSwipe(
                    axis: .vertical,
                    progress: 0,
                    motionX: 0,
                    motionY: 0,
                    terminalVelocityX: 0,
                    terminalVelocityY: 0
                )
            )
        )
    )
    let missingPayloadCancellation = makeTrackpadCancellationEvent(
        sessionID: inputActiveID,
        captureOrder: 1,
        timestamp: 611,
        family: .dockSwipe,
        reason: .killSwitch,
        payload: nil
    )
    var receivedError: TrackpadOutputSessionError?
    do {
        try inputActive.accept(missingPayloadCancellation)
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .cancellationPayloadRequired(state: .inputActive),
        "active sessionのcancelに最終payloadを必須にする"
    )
    expect(inputActive.lastCaptureOrder == 0, "cancel payload欠落でorderを消費しない")

    let dockCancellation = makeTrackpadCancellationEvent(
        sessionID: inputActiveID,
        captureOrder: 1,
        timestamp: 611,
        family: .dockSwipe,
        reason: .killSwitch,
        payload: .dockSwipe(
            axis: .vertical,
            progress: 0,
            motionX: 0,
            motionY: 0,
            terminalVelocityX: 0,
            terminalVelocityY: 0
        )
    )
    try? inputActive.accept(dockCancellation)
    let dockTerminal = try? inputActive.requireTerminal()
    expect(dockTerminal?.cancellationReason == .killSwitch, "input activeをkill switchで閉じる")
    expect(
        dockTerminal?.finalPayload?.family == .dockSwipe,
        "DockSwipe cancelにaxis / progress / velocity payloadを保持する")

    let awaitingMomentumID = TrackpadOutputSessionID(rawValue: 82)
    var awaitingMomentum = TrackpadOutputSessionMachine(
        sessionID: awaitingMomentumID, family: .scroll)
    try? awaitingMomentum.accept(
        makeTrackpadScrollInputEvent(
            sessionID: awaitingMomentumID,
            captureOrder: 0,
            timestamp: 620,
            phase: .began
        )
    )
    try? awaitingMomentum.accept(
        makeTrackpadScrollInputEvent(
            sessionID: awaitingMomentumID,
            captureOrder: 1,
            timestamp: 621,
            phase: .ended,
            continuation: .momentum
        )
    )
    try? awaitingMomentum.accept(
        makeTrackpadCancellationEvent(
            sessionID: awaitingMomentumID,
            captureOrder: 2,
            timestamp: 622,
            family: .scroll,
            reason: .systemSleep,
            payload: .scroll(deltaX: 0, deltaY: 0, velocityX: 10, velocityY: -20)
        )
    )
    let awaitingMomentumTerminal = try? awaitingMomentum.requireTerminal()
    expect(awaitingMomentumTerminal?.cancellationReason == .systemSleep, "momentum待ちをsleepで閉じる")
    expect(
        awaitingMomentumTerminal?.finalPayload?.family == .scroll,
        "momentum待ちcancelに最終scroll payloadを保持する")

    let momentumActiveID = TrackpadOutputSessionID(rawValue: 83)
    var momentumActive = TrackpadOutputSessionMachine(sessionID: momentumActiveID, family: .scroll)
    try? momentumActive.accept(
        makeTrackpadScrollInputEvent(
            sessionID: momentumActiveID,
            captureOrder: 0,
            timestamp: 630,
            phase: .began
        )
    )
    try? momentumActive.accept(
        makeTrackpadScrollInputEvent(
            sessionID: momentumActiveID,
            captureOrder: 1,
            timestamp: 631,
            phase: .ended,
            continuation: .momentum
        )
    )
    try? momentumActive.accept(
        makeTrackpadScrollMomentumEvent(
            sessionID: momentumActiveID,
            captureOrder: 2,
            timestamp: 632,
            phase: .began
        )
    )
    let cancellation = makeTrackpadCancellationEvent(
        sessionID: momentumActiveID,
        captureOrder: 3,
        timestamp: 633,
        family: .scroll,
        reason: .outputFailure,
        payload: .scroll(deltaX: 0, deltaY: 0, velocityX: 5, velocityY: -10)
    )
    try? momentumActive.accept(cancellation)
    let momentumTerminal = try? momentumActive.requireTerminal()
    expect(
        momentumTerminal?.cancellationReason == .outputFailure, "momentum activeをoutput failureで閉じる"
    )
    expect(
        momentumTerminal?.finalPayload?.family == .scroll, "momentum cancelに最終scroll payloadを保持する")
    let encoded = try? JSONEncoder().encode(cancellation)
    let decoded = encoded.flatMap {
        try? JSONDecoder().decode(TrackpadOutputSessionEvent.self, from: $0)
    }
    expect(decoded == cancellation, "session cancellationをJSON round-tripする")
    let dockEncoded = try? JSONEncoder().encode(dockCancellation)
    expect(encoded != dockEncoded, "familyが異なるcancellationを同一表現にしない")
}

func testTrackpadOutputSessionRejectsSessionAndFamilyMixing() {
    let sessionID = TrackpadOutputSessionID(rawValue: 90)
    var machine = TrackpadOutputSessionMachine(sessionID: sessionID, family: .scroll)
    let wrongSessionID = TrackpadOutputSessionID(rawValue: 91)
    var receivedError: TrackpadOutputSessionError?

    do {
        try machine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: wrongSessionID,
                captureOrder: 0,
                timestamp: 700,
                phase: .began
            )
        )
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .sessionIDMismatch(expected: sessionID, actual: wrongSessionID),
        "別session IDのevent混入を拒否する"
    )

    let wrongFamily = TrackpadOutputSessionEvent.input(
        TrackpadOutputInputFrame(
            sessionID: sessionID,
            captureOrder: 0,
            timestamp: monotonicTimestamp(700),
            phase: .began,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: 0,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        )
    )
    receivedError = nil
    do {
        try machine.accept(wrongFamily)
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .familyMismatch(expected: .scroll, actual: .dockSwipe),
        "session途中のevent family混入を拒否する"
    )
    expect(machine.state == .awaitingInput, "identity違反でsession stateを変更しない")

    let mismatchedCancellationPayload = makeTrackpadCancellationEvent(
        sessionID: sessionID,
        captureOrder: 0,
        timestamp: 700,
        family: .scroll,
        reason: .runtimeStop,
        payload: .dockSwipe(
            axis: .horizontal,
            progress: 0,
            motionX: 0,
            motionY: 0,
            terminalVelocityX: 0,
            terminalVelocityY: 0
        )
    )
    receivedError = nil
    do {
        try machine.accept(mismatchedCancellationPayload)
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .familyMismatch(expected: .scroll, actual: .dockSwipe),
        "cancellationの明示familyとpayload familyの不一致を拒否する"
    )
    expect(machine.lastCaptureOrder == nil, "cancellation family違反でorderを消費しない")
}

func testTrackpadOutputSessionRejectsFutureBootTimeAndPreterminalOrderExhaustion() {
    let epochJSON = """
        {"nanosecondsSinceStartup":1700000000000000000}
        """
    let decodedEpoch = try? JSONDecoder().decode(
        MonotonicEventTimestamp.self,
        from: Data(epochJSON.utf8)
    )
    let decodedID = TrackpadOutputSessionID(rawValue: 97)
    var decodedMachine = TrackpadOutputSessionMachine(sessionID: decodedID, family: .scroll)
    var decodedTimestampRejected = false
    if let decodedEpoch {
        let decodedEvent = TrackpadOutputSessionEvent.input(
            TrackpadOutputInputFrame(
                sessionID: decodedID,
                captureOrder: 0,
                timestamp: decodedEpoch,
                phase: .began,
                payload: .scroll(deltaX: 0, deltaY: 0, velocityX: 0, velocityY: 0)
            )
        )
        do {
            try decodedMachine.accept(decodedEvent)
        } catch TrackpadOutputSessionError.timestampOutsideCurrentBoot {
            decodedTimestampRejected = true
        } catch {}
    }
    expect(decodedEpoch != nil, "過去ログのtimestamp値をlosslessにdecodeする")
    expect(decodedTimestampRejected, "decodeした未検証timestampをlive sessionで再検証する")
    expect(decodedMachine.state == .awaitingInput, "decode値のboot違反でstateを変更しない")

    let boundedID = TrackpadOutputSessionID(rawValue: 96)
    var boundedMachine = TrackpadOutputSessionMachine(
        sessionID: boundedID,
        family: .scroll,
        maximumCaptureOrder: 1
    )
    try? boundedMachine.accept(
        makeTrackpadScrollInputEvent(
            sessionID: boundedID,
            captureOrder: 0,
            timestamp: 900,
            phase: .began
        )
    )
    var receivedError: TrackpadOutputSessionError?
    do {
        try boundedMachine.accept(
            makeTrackpadScrollInputEvent(
                sessionID: boundedID,
                captureOrder: 1,
                timestamp: 901,
                phase: .changed
            )
        )
    } catch let error as TrackpadOutputSessionError {
        receivedError = error
    } catch {}
    expect(
        receivedError == .captureOrderExhaustedBeforeTerminal(maximum: 1),
        "最終orderをnonterminal eventで消費しない"
    )
    expect(boundedMachine.lastCaptureOrder == 0, "order上限違反でaccepted stateを変更しない")
    try? boundedMachine.accept(
        makeTrackpadScrollInputEvent(
            sessionID: boundedID,
            captureOrder: 1,
            timestamp: 901,
            phase: .ended,
            continuation: .complete
        )
    )
    expect(
        (try? boundedMachine.requireTerminal())?.kind == .inputEnded,
        "最終orderをterminal eventには使用できる")
}

func testMomentumTerminatesOnBackwardMonotonicTime() {
    var engine = MomentumEngine(
        configuration: MomentumConfiguration(
            minimumStartVelocity: 1,
            stopVelocity: 0.1,
            decayPerSecond: 0.9,
            frameInterval: 0.01
        )
    )
    engine.start(
        from: GestureCommand(
            kind: .drag,
            phase: .ended,
            direction: .right,
            deltaX: 0,
            deltaY: 0,
            velocityX: 10,
            velocityY: 0,
            timestamp: 10
        )
    )

    let terminal = engine.tick(at: 9.9)
    expect(terminal?.phase == .ended, "時刻逆行時もmomentum terminalを返す")
    expect(terminal?.timestamp == 10, "時刻逆行値をterminal timestampへ使わない")
    expect(engine.state == .idle, "時刻逆行時はmomentumを停止する")

    engine.start(
        from: GestureCommand(
            kind: .drag,
            phase: .ended,
            direction: .right,
            deltaX: 0,
            deltaY: 0,
            velocityX: 10,
            velocityY: 0,
            timestamp: 10
        )
    )
    let epochTickTerminal = engine.tick(at: 1_700_000_000)
    expect(epochTickTerminal?.phase == .ended, "Unix epoch tickでもmomentum terminalを返す")
    expect(epochTickTerminal?.timestamp == 10, "Unix epoch tickをterminal timestampへ使わない")
    expect(engine.state == .idle, "Unix epoch tickでmomentumを停止する")

    engine.start(
        from: GestureCommand(
            kind: .drag,
            phase: .ended,
            direction: .right,
            deltaX: 0,
            deltaY: 0,
            velocityX: 10,
            velocityY: 0,
            timestamp: .nan
        )
    )
    expect(engine.state == .idle, "非有限timestampからmomentumを開始しない")

    engine.start(
        from: GestureCommand(
            kind: .drag,
            phase: .ended,
            direction: .right,
            deltaX: 0,
            deltaY: 0,
            velocityX: 10,
            velocityY: 0,
            timestamp: 1_700_000_000
        )
    )
    expect(engine.state == .idle, "Unix epoch timestampからmomentumを開始しない")

    engine.start(
        from: GestureCommand(
            kind: .drag,
            phase: .ended,
            direction: .right,
            deltaX: 0,
            deltaY: 0,
            velocityX: .infinity,
            velocityY: 0,
            timestamp: 10
        )
    )
    expect(engine.state == .idle, "非有限velocityからmomentumを開始しない")
}

func testProductGestureOutputFailsClosedWithoutVerifiedContract() {
    let adapter = TrackpadGestureOutputAdapter(contractData: nil)
    let sessionID = TrackpadOutputSessionID(rawValue: 1)
    let event = TrackpadOutputSessionEvent.input(
        TrackpadOutputInputFrame(
            sessionID: sessionID,
            captureOrder: 0,
            timestamp: MonotonicEventClock.now,
            phase: .began,
            payload: .scroll(deltaX: 10, deltaY: 0, velocityX: 100, velocityY: 0)
        )
    )
    let result = adapter.post(event)

    expect(adapter.capability.unsupportedReason != nil, "未検証contractをsupportedとして扱わない")
    expect(result.generatedEventCount == 0, "未検証contractではeventを生成しない")
    expect(result.failedEventCreationCount == 0, "未検証contractをevent作成失敗と混同しない")
    expect(result.failure == .unsupported, "未検証contractを明示的なunsupportedとして返す")
    expect(!adapter.supports(.scroll), "未検証contractではscroll familyを対応扱いしない")
}

func testProductGestureOutputRequiresRegisteredFixtureAndInfersFailures() {
    expect(
        ProductGestureOutputCapability.registeredFixtureCount == 1,
        "25F80 fixture registrationをCoreの単一registryから参照する"
    )
    expect(
        OperatingSystemDiagnosticIdentity.current() != nil,
        "診断表示用の現在macOS version/buildを取得できる"
    )

    let creationFailure = ProductGestureOutputResult(
        generatedEventCount: 1,
        failedEventCreationCount: 1
    )
    expect(
        creationFailure.failure == .eventCreationFailed,
        "failedEventCreationCountがあればfailure省略時もterminal failureへ変換する"
    )

    let invalidCount = ProductGestureOutputResult(
        generatedEventCount: -1,
        failedEventCreationCount: -1
    )
    expect(invalidCount.generatedEventCount == 0, "負の生成event数を保持しない")
    expect(invalidCount.failedEventCreationCount == 0, "負の作成失敗数を保持しない")
    expect(invalidCount.failure == .eventCreationFailed, "負のevent countを成功扱いにしない")
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
        ),
    ]

    let analysis = InputLogAnalyzer.analyze(candidate)
    let comparison = InputLogAnalyzer.compare(baseline: baseline, candidate: candidate)

    expect(analysis.keyEvents == 2, "キーイベント数を数える")
    expect(analysis.generatedKeyEvents == 2, "生成キーイベント数を数える")
    expect(analysis.unmarkedKeyEvents == 0, "未生成キーイベント数を数える")
    expect(analysis.keyCounts["keyDown:126"] == 1, "keyDown と keyCode を集計する")
    expect(analysis.keyCounts["keyUp:126"] == 1, "keyUp と keyCode を集計する")
    expect(
        analysis.keySignatureCounts["generated:keyDown:126:262144"] == 1,
        "生成 marker と flags を含むキー署名を集計する")
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
        ),
    ]

    let analysis = InputLogAnalyzer.analyze(records)

    expect(analysis.keyEvents == 2, "未生成キーイベント自体はキーとして数える")
    expect(analysis.unmarkedKeyEvents == 2, "未生成キーイベント数を数える")
    expect(analysis.unmarkedPassthroughInputEvents == 0, "キルスイッチなどの未生成キーだけでは通常入力通過扱いにしない")
}

func testInputLogAnalyzerCountsNormalClickDragAndWheelSeparately() {
    let records = [
        makeInputLogRecord(timestamp: 1, typeName: "otherMouseDown", buttonNumber: 4),
        makeInputLogRecord(timestamp: 2, typeName: "otherMouseUp", buttonNumber: 4),
        makeInputLogRecord(timestamp: 3, typeName: "leftMouseDown"),
        makeInputLogRecord(timestamp: 4, typeName: "leftMouseUp"),
        makeInputLogRecord(timestamp: 5, typeName: "leftMouseDragged", deltaX: 8),
        makeInputLogRecord(timestamp: 6, typeName: "scrollWheel", scrollDeltaY: -20),
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
        (1_064_000_000, 8),
    ]
    let moveRecords = moveSamples.map { timestamp, deltaX in
        makeInputLogRecord(
            timestamp: timestamp,
            typeName: "mouseMoved",
            deltaX: deltaX
        )
    }
    let scrollSamples:
        [(
            timestamp: UInt64,
            pointDeltaY: Double,
            scrollDeltaY: Int64,
            scrollPhase: Int64,
            momentumPhase: Int64
        )] = [
            (2_000_000_000, -24.0, -240, 1, 0),
            (2_016_000_000, -20.0, -200, 2, 0),
            (2_032_000_000, -16.0, -160, 2, 0),
            (2_048_000_000, -12.0, -120, 0, 1),
            (2_064_000_000, -11.52, -115, 0, 2),
            (2_080_000_000, -11.06, -111, 0, 2),
            (2_096_000_000, -10.62, -106, 0, 4),
        ]
    let scrollRecords = scrollSamples.map {
        timestamp, pointDeltaY, scrollDeltaY, scrollPhase, momentumPhase in
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
    expectApproximatelyEqual(
        report.suggestedAcceleration?.thresholdVelocity, 375, "移動速度 p75 を加速度しきい値候補にする")
    expect(report.momentumVelocitySamples.count == 3, "慣性速度サンプルを momentumPhase 区間から作る")
    expectApproximatelyEqual(
        report.suggestedMomentum?.minimumStartVelocity, 1_250,
        "active scroll と momentum の速度分布から慣性開始速度を出す")
    expectApproximatelyEqual(
        report.suggestedMomentum?.frameInterval, 0.016, "スクロール間隔 p50 を frameInterval 候補にする")
    expect((report.suggestedMomentum?.decayPerSecond ?? 0) > 0.05, "減衰率候補は 0 より大きい")
    expect((report.suggestedMomentum?.decayPerSecond ?? 1) < 0.10, "減衰率候補は合成ログの減衰に近い")
    expect(report.warnings.isEmpty, "十分なサンプルがある場合は未導出警告を出さない")
    expect(report.hasCompleteTuningEvidence, "候補と警告なしのログは完了証跡として扱える")
}

func testLogDerivedTuningAnalyzerReportsMissingSamples() {
    let report = LogDerivedTuningAnalyzer.derive(from: [])

    expect(report.suggestedAcceleration == nil, "移動速度が足りない場合は加速度候補を出さない")
    expect(report.suggestedMomentum == nil, "慣性速度が足りない場合は慣性候補を出さない")
    expect(
        report.warnings.contains { $0.contains("acceleration.thresholdVelocity") }, "加速度未導出理由を残す")
    expect(report.warnings.contains { $0.contains("momentum") }, "慣性未導出理由を残す")
    expect(!report.hasCompleteTuningEvidence, "未導出があるログは完了証跡として扱わない")
    expect(
        report.completeTuningEvidenceFailures.contains { $0.contains("入力イベント") }, "完了証跡に足りない理由を列挙する"
    )
}

func testLogDerivedTuningAnalyzerRejectsSyntheticTimestampAsCompleteEvidence() {
    let records: [InputLogRecord] = [
        makeInputLogRecord(timestamp: 1, typeName: "mouseMoved", deltaX: 1),
        makeInputLogRecord(timestamp: 2, typeName: "mouseMoved", deltaX: 2),
        makeInputLogRecord(timestamp: 3, typeName: "mouseMoved", deltaX: 3),
        makeInputLogRecord(
            timestamp: 10, typeName: "scrollWheel", scrollDeltaY: -30, pointDeltaY: -30,
            scrollPhase: 1),
        makeInputLogRecord(
            timestamp: 11, typeName: "scrollWheel", scrollDeltaY: -24, pointDeltaY: -24,
            scrollPhase: 2),
        makeInputLogRecord(
            timestamp: 12, typeName: "scrollWheel", scrollDeltaY: -18, pointDeltaY: -18,
            momentumPhase: 1),
        makeInputLogRecord(
            timestamp: 13, typeName: "scrollWheel", scrollDeltaY: -12, pointDeltaY: -12,
            momentumPhase: 2),
        makeInputLogRecord(
            timestamp: 14, typeName: "scrollWheel", scrollDeltaY: -8, pointDeltaY: -8,
            momentumPhase: 2),
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
        ),
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
        makeHIDRecord(time: 3.0, usagePage: 1, usage: 56),
    ]
    let eventRecords = [
        makeInputLogRecord(timestamp: 1_500_000_000, typeName: "mouseMoved"),
        makeInputLogRecord(timestamp: 2_050_000_000, typeName: "mouseMoved"),
        makeInputLogRecord(timestamp: 2_350_000_000, typeName: "scrollWheel"),
        makeInputLogRecord(
            timestamp: 2_060_000_000, typeName: "mouseMoved", generatedByNapeGesture: true),
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
    expect(
        analysis.suggestedAssociationWindowSeconds >= analysis.p99TimeDifferenceSeconds,
        "推奨 associationWindow は p99 以上にする")
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
    expectApproximatelyEqual(
        analysis.matches.first?.timeDifferenceSeconds, 0.02, "release の時刻差秒を算出する")
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
    expectApproximatelyEqual(
        analysis.matches.first?.timeDifferenceSeconds, 0.02, "HID とイベントタップの絶対時刻差を算出する")
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
    expect(
        analysis.matches.first?.expectedHIDUsages.contains("GenericDesktop:Wheel") == true,
        "期待 HID usage を matches に残す")
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
    expect(
        analysis.matches.first?.expectedHIDUsages == ["GenericDesktop:Wheel"],
        "scrollWheel の期待 usage は runtime と同じ GenericDesktop:Wheel に限定する")
    expect(!analysis.hasValidAssociationWindowEvidence, "AC Pan だけのログは有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerRejectsButtonUsageMismatch() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, usagePage: 9, usage: 4)
        ],
        eventTapRecords: [
            makeInputLogRecord(
                timestamp: 2_010_000_000, typeName: "otherMouseDown", buttonNumber: 4)
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(analysis.hidCandidateEventCount == 0, "異なる HID button usage をボタン候補として採用しない")
    expect(analysis.incompatibleHIDCandidateEventCount == 1, "ボタン usage 不一致を非互換 HID 近傍として数える")
    expect(
        analysis.matches.first?.expectedHIDUsages == ["Button:5"],
        "buttonNumber に対応する HID usage だけを期待値に残す")
    expect(!analysis.hasValidAssociationWindowEvidence, "ボタン usage 不一致は有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerAcceptsCanonicalButtonUsageMapping() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, usagePage: 9, usage: 1),
            makeHIDRecord(time: 2.1, usagePage: 9, usage: 2),
        ],
        eventTapRecords: [
            makeInputLogRecord(
                timestamp: 2_010_000_000, typeName: "leftMouseDown", buttonNumber: 0),
            makeInputLogRecord(
                timestamp: 2_110_000_000, typeName: "rightMouseDown", buttonNumber: 1),
        ],
        associationWindowSeconds: 0.12,
        targetStableID: sampleDeviceIdentity().stableID
    )

    expect(
        analysis.hidCandidateEventCount == 2, "CGEvent buttonNumber + 1 の HID Button usage を採用する")
    expect(analysis.missingHIDCandidateEventCount == 0, "canonical な button usage を候補なしにしない")
    expect(
        analysis.hasValidAssociationWindowEvidence, "対象デバイスの canonical な button usage は有効な証跡として扱う")
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
    expect(
        analysis.matches.first?.nearestTargetMismatchHID?.device.stableID
            == secondaryDeviceIdentity().stableID, "対象外の近傍 HID を matches に残す")
    expect(!analysis.hasValidAssociationWindowEvidence, "対象外デバイス単体のログは有効な紐づけ証跡として扱わない")
}

func testInputAssociationAnalyzerRejectsCloserNonTargetHIDDevice() {
    let analysis = InputAssociationAnalyzer.analyze(
        hidRecords: [
            makeHIDRecord(time: 2.0, device: sampleDeviceIdentity(), usagePage: 1, usage: 48),
            makeHIDRecord(time: 2.1, device: secondaryDeviceIdentity(), usagePage: 1, usage: 48),
        ],
        eventTapRecords: [
            makeInputLogRecord(timestamp: 2_010_000_000, typeName: "mouseMoved"),
            makeInputLogRecord(timestamp: 2_110_000_000, typeName: "mouseMoved"),
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

    expect(
        commands.map(\.phase) == [.began, .changed, .ended], "複数ステップでは began/changed/ended を生成する")
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
        ScrollEventPhaseEncoder.encode(command: normalEnded)
            == ScrollEventPhaseEncoding(scrollPhase: .ended, momentumPhase: nil),
        "通常スクロールの ended は scrollPhase だけに出す"
    )
    expect(
        ScrollEventPhaseEncoder.encode(command: momentumChanged)
            == ScrollEventPhaseEncoding(scrollPhase: nil, momentumPhase: .changed),
        "慣性中は momentumPhase changed として出す"
    )
    expect(
        ScrollEventPhaseEncoder.encode(command: momentumEnded)
            == ScrollEventPhaseEncoding(scrollPhase: nil, momentumPhase: .ended),
        "慣性終了は momentumPhase ended として出す"
    )
}

func testTargetDeviceGateOnlyHandlesRecentTargetActivity() {
    var gate = TargetDeviceGateState(
        configuration: TargetDeviceGateConfiguration(
            gestureButtons: [.button3, .button4, .button5],
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
            gestureButtons: [.button3, .button4, .button5],
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
        gesture: GestureConfiguration(),
        targetDeviceAssociation: TargetDeviceAssociationConfiguration(associationWindow: 0.04),
        targetDevices: [DeviceMatcher(productContains: "Nape Pro")],
        requireMatchingTargetDevice: true
    )
    let configuration = TargetDeviceGateConfiguration(settings: settings)
    var gate = TargetDeviceGateState(configuration: configuration)

    gate.record(.pointer(deltaX: 1, deltaY: 0, time: 2))

    expect(configuration.gestureButtons == [.center, .button3, .button4], "実機配送値の固定ジェスチャーボタンを gate に反映する")
    expect(configuration.associationWindow == 0.04, "設定の対象入力紐づけ秒を gate に反映する")
    expect(gate.shouldHandle(.buttonDown(button: .center, time: 2.03)), "設定した紐づけ秒以内の入力を処理する")
    expect(!gate.shouldHandle(.buttonDown(button: .center, time: 2.05)), "設定した紐づけ秒を超えた入力は処理しない")
}

func testTargetDeviceGatePassesThroughNonTargetClickDragAndWheel() {
    var gate = TargetDeviceGateState(
        configuration: TargetDeviceGateConfiguration(
            gestureButtons: [.button3, .button4, .button5],
            associationWindow: 0.05
        )
    )

    expect(!gate.shouldHandle(.buttonDown(button: .left, time: 1)), "対象入力がない通常クリック押下は処理しない")
    expect(!gate.shouldHandle(.buttonUp(button: .left, time: 1.01)), "対象入力がない通常クリック解放は処理しない")
    expect(!gate.shouldHandle(.move(deltaX: 12, deltaY: 0, time: 1.02)), "対象入力がない通常ドラッグは処理しない")
    expect(!gate.shouldHandle(.wheel(deltaX: 0, deltaY: -4, time: 1.03)), "対象入力がない通常ホイールは処理しない")

    gate.record(.pointer(deltaX: 1, deltaY: 0, time: 2))

    expect(!gate.shouldHandle(.buttonDown(button: .left, time: 2.10)), "紐づけ秒を超えた対象外クリック押下は処理しない")
    expect(
        !gate.shouldHandle(.buttonDown(button: .button4, time: 2.10)),
        "紐づけ秒を超えた対象外ジェスチャーボタン押下は処理しない")
    expect(
        !gate.shouldHandle(.buttonUp(button: .button4, time: 2.10)), "紐づけ秒を超えた対象外ジェスチャーボタン解放は処理しない")
    expect(!gate.shouldHandle(.move(deltaX: 8, deltaY: 1, time: 2.11)), "紐づけ秒を超えた対象外ドラッグは処理しない")
    expect(!gate.shouldHandle(.wheel(deltaX: 0, deltaY: -6, time: 2.12)), "紐づけ秒を超えた対象外ホイールは処理しない")
}

func testSettingsUIFieldCatalogCoversEditableSettings() {
    let descriptors = SettingsUIField.descriptors
    let descriptorFields = descriptors.map(\.field)
    let labels = descriptors.map(\.label)
    let paths = descriptors.compactMap(\.settingsPath)
    let requiredPaths: Set<String> = [
        "targetDeviceAssociation.associationWindow",
        "gesture.cancellation.maximumDuration",
        "gesture.cancellation.maximumInactivityInterval",
        "targetDevices[0].vendorID",
        "targetDevices[0].productID",
        "targetDevices[0].manufacturerContains",
        "targetDevices[0].productContains",
        "targetDevices[0].transportContains",
        "targetDevices[0].primaryUsagePage",
        "targetDevices[0].primaryUsage",
        "requireMatchingTargetDevice",
    ]

    expect(descriptorFields == SettingsUIField.allCases, "設定UIフィールド catalog は全ケースを順序通り公開する")
    expect(Set(labels).count == labels.count, "設定UIフィールドの表示名は重複しない")
    expect(Set(paths).count == paths.count, "設定UIフィールドの設定パスは重複しない")
    expect(Set(paths) == requiredPaths, "設定UIは安全設定の編集対象パスだけを網羅する")
    let fixedDescriptors = descriptors.filter { $0.valueSource == .fixedProductMapping }
    expect(fixedDescriptors.count == 3, "固定button対応を3件表示する")
    expect(fixedDescriptors.allSatisfy { !$0.isEditable }, "固定button対応を編集不能にする")
    expect(fixedDescriptors.allSatisfy { $0.settingsPath == nil }, "固定button対応を設定値として保存しない")
    expect(
        fixedDescriptors.map(\.fixedValue) == [
            "2本指スクロール / スワイプ",
            "3本指システムスワイプ",
            "4本指システムピンチ",
        ],
        "固定button対応を読み取り専用の表示値として公開する"
    )
    let forbiddenTerms = ["mode", "sensitivity", "deadzone", "acceleration", "momentum", "application"]
    expect(
        descriptors.allSatisfy { descriptor in
            forbiddenTerms.allSatisfy { term in
                !descriptor.field.rawValue.localizedCaseInsensitiveContains(term)
                    && !(descriptor.settingsPath?.localizedCaseInsensitiveContains(term) ?? false)
            }
        },
        "設定UI catalog にmode、tuning、アプリ別設定を含めない"
    )
    expect(
        descriptors.allSatisfy { !$0.label.contains("アプリ") },
        "設定UI catalog にアプリ別設定ラベルを含めない"
    )
}

func testSettingsUIFieldCatalogKindsAndSections() {
    let descriptorsByField = Dictionary(
        uniqueKeysWithValues: SettingsUIField.descriptors.map { ($0.field, $0) })
    let numberFields: Set<SettingsUIField> = [
        .targetDeviceAssociationWindow,
        .cancellationMaximumDuration,
        .cancellationMaximumInactivityInterval,
        .targetVendorID,
        .targetProductID,
        .targetUsagePage,
        .targetUsage,
    ]
    let textFields: Set<SettingsUIField> = [
        .targetManufacturerContains,
        .targetProductContains,
        .targetTransportContains,
    ]
    let checkboxFields: Set<SettingsUIField> = [
        .requireMatchingTargetDevice,
    ]
    let readOnlyFields: Set<SettingsUIField> = [
        .fixedButton3Gesture,
        .fixedButton4Gesture,
        .fixedButton5Gesture,
    ]
    for field in numberFields {
        expect(
            descriptorsByField[field]?.controlKind == .numberTextField,
            "\(field.rawValue) は数値入力として扱う")
    }
    for field in textFields {
        expect(descriptorsByField[field]?.controlKind == .textField, "\(field.rawValue) は文字入力として扱う")
    }
    for field in checkboxFields {
        expect(
            descriptorsByField[field]?.controlKind == .checkbox, "\(field.rawValue) はチェックボックスとして扱う")
    }
    for field in readOnlyFields {
        expect(descriptorsByField[field]?.controlKind == .readOnlyText, "\(field.rawValue) は読み取り専用表示にする")
        expect(
            descriptorsByField[field]?.section == .fixedMapping, "\(field.rawValue) は固定対応sectionに置く")
    }
    expect(
        descriptorsByField[.cancellationMaximumDuration]?.section == .cancellation,
        "キャンセル条件は cancellation section に置く")
    expect(
        descriptorsByField[.targetVendorID]?.section == .targetDevice,
        "対象デバイス条件は targetDevice section に置く")
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
    expect(presentation.keepsStatusMenu, "メニューバーの常駐 UI を維持する")
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
        .targetDeviceNotFound,
    ]

    for failure in recoverableFailures {
        var state = RuntimeRecoveryState()
        _ = state.recordRuntimeFailure(failure, at: 10)
        let retry = state.retryIfReady(at: 10)

        expect(state.autoRetryEnabled, "自動復旧可能な失敗後も自動再試行は有効なままにする: \(failure)")
        expect(retry.shouldStartRuntime, "自動復旧可能な失敗は自動再試行対象にする: \(failure)")
    }
}

func testRuntimeRecoveryDoesNotRetryNonRetryableFailures() {
    let nonRetryableFailures: [RuntimeRecoveryFailureKind] = [
        .invalidSettings,
        .targetDeviceMatcherMissing,
        .outputContractUnsupported,
        .outputContractMismatch,
        .outputPostingFailed,
        .unrecoverable,
    ]

    for failure in nonRetryableFailures {
        var state = RuntimeRecoveryState()
        _ = state.recordRuntimeFailure(failure, at: 10)
        let retry = state.retryIfReady(at: 10)

        expect(state.pendingRetry == nil, "非retryable失敗は自動再試行予定を作らない: \(failure)")
        expect(!retry.shouldStartRuntime, "非retryable失敗は自動再試行しない: \(failure)")
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
    expect(
        state.mode
            == .starting(
                reason: .automaticRetry(.runtimeFailure(.hidAccessUnavailable)), requestedAt: 10),
        "再試行開始理由を保持する")
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
    expect(
        state.mode == .starting(reason: .automaticRetry(.wake), requestedAt: 20),
        "wake 由来の自動再試行として開始する"
    )
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
    expect(
        state.mode == .starting(reason: .automaticRetry(.wake), requestedAt: 21.5),
        "wake 由来の自動再試行として開始する")
}

func testRuntimeRecoveryKeepsWakeRetryWhenSleepNotificationRepeats() {
    var state = RuntimeRecoveryState()
    state.recordRuntimeStarted()

    _ = state.handleWillSleep(at: 10)
    _ = state.handleWillSleep(at: 10.1)
    _ = state.handleDidWake(at: 20, retryDelay: 1)
    let retry = state.retryIfReady(at: 21)

    expect(retry.shouldStartRuntime, "sleep 通知が重複しても wake 後再試行対象を維持する")
    expect(
        state.mode == .starting(reason: .automaticRetry(.wake), requestedAt: 21),
        "重複 sleep 後も wake 由来の自動再試行として開始する")
}

func testRuntimeStatusPresenterShowsRunningAndStoppedStates() {
    let running = RuntimeStatusPresenter.present(
        isRuntimeRunning: true, recoveryState: RuntimeRecoveryState())

    var stoppedState = RuntimeRecoveryState()
    _ = stoppedState.requestManualStop(at: 1)
    let stopped = RuntimeStatusPresenter.present(
        isRuntimeRunning: false, recoveryState: stoppedState)

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
    let retryPresentation = RuntimeStatusPresenter.present(
        isRuntimeRunning: false, recoveryState: retryState)

    var sleepState = RuntimeRecoveryState()
    sleepState.recordRuntimeStarted()
    _ = sleepState.handleWillSleep(at: 20)
    let sleepPresentation = RuntimeStatusPresenter.present(
        isRuntimeRunning: false, recoveryState: sleepState)

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
        permissionTargetDescription:
            "/Applications/NapeGesture.app (bundle ID: dev.char5742.nape-gesture)"
    )

    expect(presentation.permissionTargetDescription.contains("NapeGesture.app"), "権限付与対象を表示する")
    expect(presentation.accessibility.serviceTitle == "アクセシビリティ", "アクセシビリティの表示名を固定する")
    expect(presentation.accessibility.statusTitle == "未許可", "アクセシビリティ未許可を表示する")
    expect(presentation.accessibility.shouldOpenSettings, "アクセシビリティ未許可時は設定を開く導線を出す")
    expect(presentation.accessibility.settingsButtonTitle == "アクセシビリティ設定を開く", "アクセシビリティ設定ボタン名を固定する")
    expect(
        presentation.accessibility.settingsURLString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "アクセシビリティの System Settings URL を固定する"
    )

    expect(presentation.inputMonitoring.serviceTitle == "入力監視", "入力監視の表示名を固定する")
    expect(presentation.inputMonitoring.statusTitle == "未許可または開始失敗", "入力監視未許可を表示する")
    expect(presentation.inputMonitoring.shouldOpenSettings, "入力監視未許可時は設定を開く導線を出す")
    expect(presentation.inputMonitoring.settingsButtonTitle == "入力監視設定を開く", "入力監視設定ボタン名を固定する")
    expect(
        presentation.inputMonitoring.settingsURLString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
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
    expect(
        report.gestureClassCounts == ["twoFingerScrollSwipe": 20],
        "性能reportを固定gesture class単位で集計する"
    )
    expect(report.outputFamilyCounts == ["scroll": 20], "性能reportを実出力family単位で集計する")
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

func testRuntimePerformanceRecordEncodesFixedGestureContract() {
    let json = """
        {
          "schemaVersion": 3,
          "operationID": "fixed-scroll",
          "source": "eventTap",
          "gestureClass": "twoFingerScrollSwipe",
          "outputFamily": "scroll",
          "sourceKind": "move",
          "inputPhase": "changed",
          "commandTimestampNanoseconds": 9,
          "inputEventTimestampNanoseconds": 10,
          "tapCallbackStartedAtNanoseconds": 11,
          "recognizerFinishedAtNanoseconds": 12,
          "postStartedAtNanoseconds": 13,
          "postFinishedAtNanoseconds": 14,
          "generatedEventCount": 1,
          "failedEventCreationCount": 0,
          "suppressedOriginal": true
        }
        """

    let record = try? JSONDecoder().decode(RuntimePerformanceRecord.self, from: Data(json.utf8))
    let encoded = record.flatMap { try? JSONEncoder().encode($0) }
    let encodedText = encoded.map { String(decoding: $0, as: UTF8.self) } ?? ""

    expect(record?.gestureClass == .twoFingerScrollSwipe, "固定gesture classを保持する")
    expect(record?.outputFamily == .scroll, "実出力familyを保持する")
    expect(record?.sourceKind == .move, "source kindを保持する")
    expect(record?.inputPhase == .changed, "入力phaseを保持する")
    expect(record?.commandTimestampNanoseconds == 9, "exact timestampを保持する")
    expect(
        record?.schemaVersion == RuntimePerformanceRecord.currentSchemaVersion,
        "旧性能recordを現行schemaへ移行する")
    expect(encodedText.contains("twoFingerScrollSwipe"), "再保存時はgesture classを記録する")
    expect(encodedText.contains("outputFamily"), "再保存時は実出力familyを記録する")
    expect(!encodedText.contains("\"mode\""), "性能recordへ旧modeを記録しない")
}

func testRuntimePerformanceRecordDoesNotInferMissingOutputFamily() {
    let json = """
        {
          "schemaVersion": 3,
          "operationID": "missing-family",
          "source": "eventTap",
          "gestureClass": "twoFingerScrollSwipe",
          "sourceKind": "buttonDown",
          "inputPhase": "began",
          "commandTimestampNanoseconds": 9,
          "inputEventTimestampNanoseconds": 10,
          "tapCallbackStartedAtNanoseconds": 11,
          "recognizerFinishedAtNanoseconds": 12,
          "postStartedAtNanoseconds": 13,
          "postFinishedAtNanoseconds": 14,
          "generatedEventCount": 0,
          "failedEventCreationCount": 1,
          "suppressedOriginal": true
        }
        """

    let record = try? JSONDecoder().decode(RuntimePerformanceRecord.self, from: Data(json.utf8))

    expect(record?.gestureClass == .twoFingerScrollSwipe, "schema 3のgesture classを保持する")
    expect(record?.outputFamily == nil, "欠落した実出力familyをgesture classから推測しない")
}

func testRuntimePerformanceRecordRejectsMismatchedSchemaShape() {
    let schema3WithLegacyMode = """
        {
          "schemaVersion": 3,
          "operationID": "schema3-mode",
          "source": "eventTap",
          "mode": "twoFingerSwipe",
          "sourceKind": "buttonDown",
          "inputPhase": "began",
          "commandTimestampNanoseconds": 9,
          "tapCallbackStartedAtNanoseconds": 11,
          "recognizerFinishedAtNanoseconds": 12,
          "postStartedAtNanoseconds": 13,
          "postFinishedAtNanoseconds": 14,
          "generatedEventCount": 1,
          "failedEventCreationCount": 0,
          "suppressedOriginal": true
        }
        """
    let futureSchema = schema3WithLegacyMode.replacingOccurrences(
        of: "\"schemaVersion\": 3",
        with: "\"schemaVersion\": 4"
    )

    expectThrows("schema 3で旧modeだけのrecordを受理しない") {
        _ = try JSONDecoder().decode(
            RuntimePerformanceRecord.self,
            from: Data(schema3WithLegacyMode.utf8)
        )
    }
    expectThrows("未知のruntime performance schemaを現行schemaとして解釈しない") {
        _ = try JSONDecoder().decode(
            RuntimePerformanceRecord.self,
            from: Data(futureSchema.utf8)
        )
    }
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
        ),
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

func testRuntimePerformanceAnalyzerAllowsDeferredRecognizedGestureStart() {
    let records = [
        makeRuntimePerformanceRecord(
            index: 1,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            generatedEventCount: 0,
            gestureClass: .threeFingerSystemSwipe,
            sourceKind: .buttonDown,
            inputPhase: .began
        ),
        makeRuntimePerformanceRecord(
            index: 2,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            generatedEventCount: 0,
            gestureClass: .threeFingerSystemSwipe,
            sourceKind: .move,
            inputPhase: .changed
        ),
        makeRuntimePerformanceRecord(
            index: 3,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            gestureClass: .threeFingerSystemSwipe,
            sourceKind: .move,
            inputPhase: .changed
        ),
        makeRuntimePerformanceRecord(
            index: 4,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            gestureClass: .threeFingerSystemSwipe,
            sourceKind: .buttonUp,
            inputPhase: .ended
        ),
    ]

    let report = RuntimePerformanceAnalyzer.analyze(records: records)
    let evaluation = RuntimePerformanceAnalyzer.evaluate(report)

    expect(report.postedRecordCount == 2, "遅延開始前の空batchを投稿数へ含めない")
    expect(report.missingPostRecordCount == 0, "軸確定前の空batchを投稿欠落と扱わない")
    expect(evaluation.passed, "認識済みgestureの正規の遅延開始を性能基準で許容する")
}

func testRuntimePerformanceAnalyzerRejectsMissingPostAfterGestureStarted() {
    let records = [
        makeRuntimePerformanceRecord(
            index: 1,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            generatedEventCount: 0,
            gestureClass: .pinch,
            sourceKind: .buttonDown,
            inputPhase: .began
        ),
        makeRuntimePerformanceRecord(
            index: 2,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            gestureClass: .pinch,
            sourceKind: .move,
            inputPhase: .changed
        ),
        makeRuntimePerformanceRecord(
            index: 3,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            generatedEventCount: 0,
            gestureClass: .pinch,
            sourceKind: .move,
            inputPhase: .changed
        ),
        makeRuntimePerformanceRecord(
            index: 4,
            tapToPostStartNanoseconds: 1_000,
            tapToPostFinishedNanoseconds: 2_000,
            gestureClass: .pinch,
            sourceKind: .buttonUp,
            inputPhase: .ended
        ),
    ]

    let report = RuntimePerformanceAnalyzer.analyze(records: records)
    let evaluation = RuntimePerformanceAnalyzer.evaluate(report)

    expect(report.missingPostRecordCount == 1, "gesture開始後の空batchを投稿欠落として数える")
    expect(!evaluation.passed, "gesture開始後の投稿欠落を性能基準で失敗にする")
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
    expect(
        report.tapToFirstPostNanoseconds.sampleCount == 0, "momentum timer の投稿を tap-to-post 分布に混ぜない"
    )
    expect(!evaluation.passed, "momentum timer だけでは tap-to-post 証跡として合格しない")
    expect(failedItems.contains("eventTapPostedRecordCount"), "event tap 由来投稿がないことを基準違反にする")
}

func exactTimestamp(_ nanoseconds: UInt64) -> MonotonicEventTimestamp {
    MonotonicEventTimestamp(nanosecondsSinceStartup: nanoseconds)
}

func testFixedButtonToGestureClassMapping() {
    expect(FixedGestureClass(activationButton: .button3) == .twoFingerScrollSwipe, "button 3を2本指scroll classへ固定する")
    expect(FixedGestureClass(activationButton: .button4) == .threeFingerSystemSwipe, "button 4を3本指system swipe classへ固定する")
    expect(FixedGestureClass(activationButton: .center) == .pinch, "button 5の実配送値をpinch classへ固定する")
    expect(FixedGestureClass(activationButton: .left) == nil, "左buttonをtrackpad入力へ変換しない")
    expect(FixedGestureClass(activationButton: .right) == nil, "右buttonをtrackpad入力へ変換しない")
    expect(FixedGestureClass(activationButton: .button5) == nil, "対象外のCG buttonNumber 5を変換しない")
    expect(FixedGestureClass.pinch.logicalButtonNumber == 5, "pinch classのユーザー向けbutton番号を5として保持する")
}

func testFixedGestureRecognizerPreservesEverySourceSample() {
    var recognizer = FixedGestureInputRecognizer(
        cancellation: GestureCancellationConfiguration(
            maximumDuration: 0,
            maximumInactivityInterval: 0
        ),
        sessionSequence: TrackpadOutputSessionSequence(startingAt: 41)
    )

    let began = recognizer.handle(
        .buttonDown(button: .button4, timestamp: exactTimestamp(1_000))
    )
    let move = recognizer.handle(
        .move(deltaX: 1.25, deltaY: -2.5, timestamp: exactTimestamp(1_007))
    )
    let zeroMove = recognizer.handle(
        .move(deltaX: 0, deltaY: 0, timestamp: exactTimestamp(1_009))
    )
    let wheel = recognizer.handle(
        .wheel(deltaX: -3.75, deltaY: 4.5, timestamp: exactTimestamp(1_012))
    )
    let ended = recognizer.handle(
        .buttonUp(button: .button4, timestamp: exactTimestamp(1_020))
    )

    let commands = [began, move, zeroMove, wheel, ended].flatMap(\.commands)
    expect(commands.count == 5, "buttonと全move/wheel sampleとreleaseを1対1でcommandへ変換する")
    expect(commands.map(\.captureOrder) == [0, 1, 2, 3, 4], "capture orderを欠落なく保持する")
    expect(commands.allSatisfy { $0.sessionID == TrackpadOutputSessionID(rawValue: 41) }, "同一session IDを維持する")
    expect(commands.allSatisfy { $0.sourceButton == .button4 }, "source buttonをsession中に固定する")
    expect(commands.allSatisfy { $0.gestureClass == .threeFingerSystemSwipe }, "gesture classをsession中に固定する")
    expect(commands.map(\.timestamp) == [1_000, 1_007, 1_009, 1_012, 1_020].map(exactTimestamp), "source timestampをnanosecond単位で保持する")
    expect(move.commands.first?.deltaX.bitPattern == 1.25.bitPattern, "move X量をbit単位で保持する")
    expect(move.commands.first?.deltaY.bitPattern == (-2.5).bitPattern, "move Y量をbit単位で保持する")
    expect(zeroMove.commands.count == 1, "zero delta sampleも破棄しない")
    expect(wheel.commands.first?.sourceKind == .wheel, "wheel source kindを保持する")
    expect(wheel.commands.first?.deltaX.bitPattern == (-3.75).bitPattern, "wheel X量をbit単位で保持する")
    expect(wheel.commands.first?.deltaY.bitPattern == 4.5.bitPattern, "wheel Y量をbit単位で保持する")
    expect(ended.commands.first?.phase == .ended, "対応releaseで一度だけendedを生成する")
    expect(recognizer.isIdle, "terminal後にidleへ戻る")
}

func testFixedGestureRecognizerDiffersOnlyByFixedIdentity() {
    func commands(
        button: MouseButton,
        sessionID: UInt64
    ) -> [FixedGestureInputCommand] {
        var recognizer = FixedGestureInputRecognizer(
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0,
                maximumInactivityInterval: 0
            ),
            sessionSequence: TrackpadOutputSessionSequence(startingAt: sessionID)
        )
        return [
            recognizer.handle(.buttonDown(button: button, timestamp: exactTimestamp(10))),
            recognizer.handle(.move(deltaX: 2, deltaY: -3, timestamp: exactTimestamp(20))),
            recognizer.handle(.wheel(deltaX: -5, deltaY: 7, timestamp: exactTimestamp(30))),
            recognizer.handle(.buttonUp(button: button, timestamp: exactTimestamp(40))),
        ].flatMap(\.commands)
    }

    let button3 = commands(button: .button3, sessionID: 1)
    let button4 = commands(button: .button4, sessionID: 2)
    let button5 = commands(button: .center, sessionID: 3)

    expect(button3.map(\.gestureClass) == Array(repeating: .twoFingerScrollSwipe, count: 4), "button 3列を2本指scroll classへ固定する")
    expect(button4.map(\.gestureClass) == Array(repeating: .threeFingerSystemSwipe, count: 4), "button 4列を3本指system swipe classへ固定する")
    expect(button5.map(\.gestureClass) == Array(repeating: .pinch, count: 4), "button 5列をpinch classへ固定する")

    func commonShape(_ command: FixedGestureInputCommand) -> String {
        [
            String(command.captureOrder),
            String(command.timestamp.nanosecondsSinceStartup),
            command.sourceKind.rawValue,
            command.phase.rawValue,
            String(command.deltaX.bitPattern),
            String(command.deltaY.bitPattern),
        ].joined(separator: ":")
    }
    expect(button3.map(commonShape) == button4.map(commonShape), "button 3と4で入力列の変換原則を変えない")
    expect(button4.map(commonShape) == button5.map(commonShape), "button 4と5で入力列の変換原則を変えない")
}

func testFixedGestureRecognizerDoesNotSwitchOnAdditionalButton() {
    var recognizer = FixedGestureInputRecognizer(
        cancellation: GestureCancellationConfiguration(
            maximumDuration: 0,
            maximumInactivityInterval: 0
        )
    )
    let began = recognizer.handle(
        .buttonDown(button: .button3, timestamp: exactTimestamp(10))
    )
    let additionalDown = recognizer.handle(
        .buttonDown(button: .button5, timestamp: exactTimestamp(11))
    )
    let move = recognizer.handle(
        .move(deltaX: 9, deltaY: -4, timestamp: exactTimestamp(12))
    )
    let additionalUp = recognizer.handle(
        .buttonUp(button: .button5, timestamp: exactTimestamp(13))
    )
    let ended = recognizer.handle(
        .buttonUp(button: .button3, timestamp: exactTimestamp(14))
    )

    expect(began.commands.first?.gestureClass == .twoFingerScrollSwipe, "開始buttonでgesture classを確定する")
    expect(!additionalDown.shouldSuppressOriginal, "session中の追加button downを別sessionへ変換しない")
    expect(additionalDown.commands.isEmpty, "追加buttonでcommandを生成しない")
    expect(move.commands.first?.gestureClass == .twoFingerScrollSwipe, "追加button後も元gesture classを維持する")
    expect(move.commands.first?.captureOrder == 1, "追加buttonをcapture orderへ混入させない")
    expect(!additionalUp.shouldSuppressOriginal, "追加button upを通常入力として通過させる")
    expect(ended.commands.first?.captureOrder == 2, "元button releaseで同じsessionを終了する")
}

func testFixedGestureRecognizerFailsClosedOnTimestampRegression() {
    var recognizer = FixedGestureInputRecognizer(
        cancellation: GestureCancellationConfiguration(
            maximumDuration: 0,
            maximumInactivityInterval: 0
        )
    )
    _ = recognizer.handle(.buttonDown(button: .center, timestamp: exactTimestamp(100)))
    _ = recognizer.handle(.move(deltaX: 1, deltaY: 2, timestamp: exactTimestamp(120)))
    let regressed = recognizer.handle(
        .wheel(deltaX: 3, deltaY: 4, timestamp: exactTimestamp(119))
    )
    let release = recognizer.handle(
        .buttonUp(button: .center, timestamp: exactTimestamp(130))
    )

    expect(regressed.shouldSuppressOriginal, "timestamp逆行sampleを通常mouseへ漏らさない")
    expect(regressed.commands.isEmpty, "timestamp逆行sampleから出力commandを作らない")
    expect(
        regressed.failure
            == .timestampRegression(previous: exactTimestamp(120), actual: exactTimestamp(119)),
        "timestamp逆行を構造化failureにする"
    )
    expect(recognizer.isIdle, "timestamp逆行後はactive sessionを残さない")
    expect(release.shouldSuppressOriginal, "抑制済みdownに対応するreleaseを一度だけ抑制する")
    expect(recognizer.pendingReleaseButton == nil, "対応release後にpending状態を消す")
}

func testFixedGestureRecognizerCancelsExpiredSessionWithoutDroppingCurrentInput() {
    var recognizer = FixedGestureInputRecognizer(
        cancellation: GestureCancellationConfiguration(
            maximumDuration: 0,
            maximumInactivityInterval: 0.000_000_010
        )
    )
    _ = recognizer.handle(.buttonDown(button: .button4, timestamp: exactTimestamp(100)))
    let expired = recognizer.handle(
        .move(deltaX: 4, deltaY: 5, timestamp: exactTimestamp(111))
    )
    let release = recognizer.handle(
        .buttonUp(button: .button4, timestamp: exactTimestamp(120))
    )

    expect(expired.shouldSuppressOriginal, "timeoutを検出した現在sampleを通常mouseへ漏らさない")
    expect(expired.commands.count == 2, "timeoutを検出した現在sampleとcancel terminalを両方生成する")
    expect(expired.commands[0].phase == .changed, "timeoutを検出した現在sampleを先に保持する")
    expect(expired.commands[0].deltaX == 4 && expired.commands[0].deltaY == 5, "timeout sampleのX/Y量を保持する")
    expect(expired.commands[1].phase == .cancelled, "timeout後にactive sessionをcancel terminalへ収束させる")
    expect(expired.commands.map(\.captureOrder) == [1, 2], "sampleとcancelで連続capture orderを使う")
    expect(release.shouldSuppressOriginal, "抑制済みactivation downのreleaseだけは後から抑制する")
}

func testFixedGestureSessionMachineEnforcesIdentityOrderAndSingleTerminal() {
    let sessionID = TrackpadOutputSessionID(rawValue: 77)
    func command(
        order: UInt64,
        timestamp: UInt64,
        sourceKind: GestureInputSourceKind,
        phase: FixedGestureInputPhase,
        deltaX: Double = 0,
        deltaY: Double = 0,
        gestureClass: FixedGestureClass = .pinch
    ) -> FixedGestureInputCommand {
        FixedGestureInputCommand(
            sessionID: sessionID,
            sourceButton: .center,
            gestureClass: gestureClass,
            captureOrder: order,
            timestamp: exactTimestamp(timestamp),
            sourceKind: sourceKind,
            phase: phase,
            deltaX: deltaX,
            deltaY: deltaY
        )
    }

    var machine = FixedGestureSessionMachine(
        sessionID: sessionID,
        sourceButton: .center,
        gestureClass: .pinch
    )
    expectNoThrow("fixed gesture session beginを受理する") {
        try machine.accept(command(order: 0, timestamp: 10, sourceKind: .buttonDown, phase: .began))
    }
    let stateBeforeMismatch = machine.state
    expectThrows("session途中のgesture class変更を拒否する") {
        try machine.accept(
            command(
                order: 1,
                timestamp: 11,
                sourceKind: .move,
                phase: .changed,
                deltaX: 1,
                gestureClass: .threeFingerSystemSwipe
            )
        )
    }
    expect(machine.state == stateBeforeMismatch, "拒否したgesture class変更でstateを進めない")
    expect(machine.lastCaptureOrder == 0, "拒否したcommandでcapture orderを進めない")
    expectNoThrow("move sampleを受理する") {
        try machine.accept(
            command(
                order: 1,
                timestamp: 12,
                sourceKind: .move,
                phase: .changed,
                deltaX: -2,
                deltaY: 3
            )
        )
    }
    expectNoThrow("wheel sampleを同じsessionで受理する") {
        try machine.accept(
            command(
                order: 2,
                timestamp: 13,
                sourceKind: .wheel,
                phase: .changed,
                deltaX: 4,
                deltaY: -5
            )
        )
    }
    expectNoThrow("対応release terminalを受理する") {
        try machine.accept(command(order: 3, timestamp: 14, sourceKind: .buttonUp, phase: .ended))
    }
    expect((try? machine.requireTerminal())?.phase == .ended, "terminalを構造化して保持する")
    expectThrows("二重terminalを拒否する") {
        try machine.accept(command(order: 4, timestamp: 15, sourceKind: .buttonUp, phase: .ended))
    }
}

testFixedButtonToGestureClassMapping()
testFixedGestureRecognizerPreservesEverySourceSample()
testFixedGestureRecognizerDiffersOnlyByFixedIdentity()
testFixedGestureRecognizerDoesNotSwitchOnAdditionalButton()
testFixedGestureRecognizerFailsClosedOnTimestampRegression()
testFixedGestureRecognizerCancelsExpiredSessionWithoutDroppingCurrentInput()
testFixedGestureSessionMachineEnforcesIdentityOrderAndSingleTerminal()
testPassesThroughWhenActivationButtonIsNotPressed()
testMouseButtonRejectsUnsupportedNumbers()
testOtherMouseButtonInputRejectsUnsupportedNumbers()
testTrackpadGestureModesDescribeInputSeries()
testActivationButtonSuppressesOriginalInputBeforeThreshold()
testDragBeginsAfterDeadZoneWithDominantDirection()
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
testDragContinuesAcrossDirectionAndAxisChanges()
testWheelGestureIsScopedToActivationButton()
testMomentumDoesNotStartBelowMinimumVelocity()
testMomentumDecaysAndEventuallyEnds()
testDeviceMatcherMatchesConfiguredDevice()
testDeviceMatcherMatchesUsageWhenConfigured()
testMouseHIDInterfaceExcludesCompositeSiblingInterfaces()
testDeviceMatcherEvaluationReportsMatchedAndMismatchedConditions()
testDeviceMatcherConditionPresenceIgnoresEmptyText()
testDeviceMatcherWithoutConditionsDoesNotMatchEverything()
testDeviceIdentityEncodesStableID()
testGestureConfigurationDecodesOldJSONWithDefaults()
testGestureConfigurationMigratesResultNamedModes()
testSettingsMigrationDetectsOnlyDeprecatedGestureKeys()
testGestureConfigurationUsesFixedButtonMapping()
testRecognizerFixesButtonModeForSessionAndWaitsForMatchingRelease()
testLegacyNoneModesCannotDisableFixedButtons()
testNapeGestureSettingsDecodesOldJSONWithDefaultAssociationWindow()
testSettingsValidatorAcceptsTemplateSettings()
testSettingsValidatorSeparatesCanonicalAndLegacyGestureValues()
testSettingsValidatorRejectsInvalidTargetDeviceAssociationWindow()
testSettingsValidatorRejectsMissingRequiredTargetMatcher()
testSettingsValidatorRejectsInvalidTargetMatcherValues()
testInputLogAnalyzerSuggestsDeadZone()
testInputLogRecordDecodesLegacyGeneratedField()
testInputLogRecordEncodesSystemTestMetadataWhenPresent()
testTrackpadDriverEventLogRoundTrips()
testTrackpadDriverEventLogDecodesLegacyRecordWithDefaults()
testTrackpadDriverEventLogRawFieldsUseStableNumericOrder()
testTrackpadDriverEventLogPreservesNonFiniteNamedDoubleBitPatterns()
testTrackpadDriverEventLogJSONLinesPreserveCaptureOrder()
testMonotonicEventClockUsesStartupNanoseconds()
testTrackpadOutputSessionSequenceDoesNotReuseIDs()
testTrackpadOutputSessionSequenceIsUniqueAcrossConcurrentCallers()
testTrackpadOutputSessionSeparatesInputAndMomentumLifecycles()
testTrackpadOutputSessionPreservesGestureProgressAndDecision()
testTrackpadOutputSessionSupportsDockSwipeClasses()
testTrackpadOutputSessionEventCodableCoversEveryEventKind()
testTrackpadOutputSessionRejectsInvalidOrderAndDoubleTerminalAtomically()
testTrackpadOutputSessionRejectsStuckAndInvalidFamilyMetadata()
testTrackpadOutputSessionCancelsEveryNonterminalState()
testTrackpadOutputSessionRejectsSessionAndFamilyMixing()
testTrackpadOutputSessionRejectsFutureBootTimeAndPreterminalOrderExhaustion()
testMomentumTerminatesOnBackwardMonotonicTime()
testProductGestureOutputFailsClosedWithoutVerifiedContract()
testProductGestureOutputRequiresRegisteredFixtureAndInfersFailures()
runTrackpadDriverEventAnalyzerTests()
runTrackpadDriverEventCaptureManifestTests()
runTrackpadOutputProvenanceTests()
runTrackpadPhysicalObservationFixtureTests()
runTrackpadScrollMomentumContractAnalyzerTests()
testInputLogAnalyzerComparesBaselineAndCandidate()
testInputLogAnalyzerCountsKeyEvents()
testInputLogAnalyzerDoesNotTreatUnmarkedKeysAsPassthroughInput()
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
testRuntimeRecoveryDoesNotRetryNonRetryableFailures()
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
testRuntimePerformanceRecordEncodesFixedGestureContract()
testRuntimePerformanceRecordDoesNotInferMissingOutputFamily()
testRuntimePerformanceRecordRejectsMismatchedSchemaShape()
testRuntimePerformanceAnalyzerRejectsMissingAndSlowPosts()
testRuntimePerformanceAnalyzerAllowsDeferredRecognizedGestureStart()
testRuntimePerformanceAnalyzerRejectsMissingPostAfterGestureStarted()
testRuntimePerformanceAnalyzerDoesNotTreatMomentumAsTapToPost()
runStabilityRegressionTests()

if failures == 0 {
    print("すべてのコアテストに成功しました。")
} else {
    fputs("\(failures) 件のコアテストが失敗しました。\n", stderr)
    exit(1)
}
