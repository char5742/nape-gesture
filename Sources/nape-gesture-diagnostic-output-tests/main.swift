import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore
import NapeGestureDiagnosticOutput

private var failureCount = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failureCount += 1
        fputs("失敗: \(message)\n", stderr)
    }
}

private func approximatelyEqual(_ lhs: UInt64, _ rhs: UInt64, tolerance: UInt64 = 2) -> Bool {
    let difference = lhs >= rhs ? lhs - rhs : rhs - lhs
    return difference <= tolerance
}

private func forwardDifference(from earlier: UInt64, to later: UInt64) -> UInt64? {
    guard later >= earlier else {
        return nil
    }
    return later - earlier
}

private func makeCommand(
    kind: GestureCommandKind = .wheel,
    phase: GesturePhase = .changed,
    timestamp: TimeInterval,
    deltaX: Double = 12,
    deltaY: Double = -24
) -> GestureCommand {
    GestureCommand(
        kind: kind,
        phase: phase,
        direction: nil,
        deltaX: deltaX,
        deltaY: deltaY,
        velocityX: 0,
        velocityY: 0,
        timestamp: timestamp
    )
}

private let liveScrollEventFactory: DiagnosticScrollEventFactory = { source, wheel1, wheel2 in
    CGEvent(
        scrollWheelEvent2Source: source,
        units: .pixel,
        wheelCount: 2,
        wheel1: wheel1,
        wheel2: wheel2,
        wheel3: 0
    )
}

private let liveKeyEventFactory: DiagnosticKeyEventFactory = { source, keyCode, keyDown in
    CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
}

private struct PostedEventSnapshot {
    var type: CGEventType
    var timestamp: UInt64
    var scrollPhase: Int64
    var momentumPhase: Int64
    var keyCode: Int64

    init(_ event: CGEvent) {
        type = event.type
        timestamp = event.timestamp
        scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    }
}

private func testScrollEventUsesCurrentBootTimestamp() {
    let poster = DiagnosticEventPoster()
    let plannedTimestamp = MonotonicEventClock.now
    let event = poster.makeScrollEvent(
        command: makeCommand(timestamp: plannedTimestamp.secondsSinceStartup),
        mode: .free
    )
    let observedAt = MonotonicEventClock.nowTimestampNanoseconds

    expect(event != nil, "現在bootの起動後時刻からscroll eventを作成する")
    guard let event else {
        return
    }
    expect(event.timestamp > 0, "作成eventのtimestampが0ではない")
    expect(event.timestamp <= observedAt, "作成eventのtimestampが現在bootの未来にならない")
    expect(
        approximatelyEqual(event.timestamp, plannedTimestamp.nanosecondsSinceStartup, tolerance: 1),
        "作成eventへ検証済み起動後timestampを設定する"
    )
}

private func testPostScrollFinalizesTimestampImmediatelyBeforePosting() {
    let postingTimestamp: UInt64 = 50_000_000_000
    var postedEvents: [PostedEventSnapshot] = []
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { postingTimestamp },
        sleep: { _ in },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: liveKeyEventFactory,
        postEvent: { event in
            postedEvents.append(PostedEventSnapshot(event))
            return true
        }
    )

    let result = poster.postScroll(
        command: makeCommand(timestamp: 49),
        mode: .free
    )
    expect(result.completedSuccessfully, "scroll event投稿が成功する")
    expect(postedEvents.count == 1, "scroll eventを1件投稿する")
    expect(
        postedEvents.first?.timestamp == postingTimestamp,
        "予定時刻ではなく投稿直前の同一clock値をtimestampにする"
    )
}

private func testInvalidTimestampsFailClosed() {
    let poster = DiagnosticEventPoster()
    let invalidTimestamps: [(name: String, value: TimeInterval)] = [
        ("negative", -1),
        ("nan", .nan),
        ("positive-infinity", .infinity),
        ("negative-infinity", -.infinity),
        ("unix-epoch", 1_700_000_000),
        ("future-boot", MonotonicEventClock.nowSeconds + 60)
    ]

    for invalid in invalidTimestamps {
        let command = makeCommand(timestamp: invalid.value)
        expect(
            poster.makeScrollEvent(command: command, mode: .free) == nil,
            "\(invalid.name) timestampからeventを作成しない"
        )
        let result = poster.postScroll(command: command, mode: .free)
        expect(result.generatedEventCount == 0, "\(invalid.name) timestampを投稿しない")
        expect(result.failedEventCreationCount == 1, "\(invalid.name) timestampを作成失敗として返す")
    }
}

private func testShortcutCreationIsAtomic() {
    var creationCount = 0
    var postedEventCount = 0
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { 10 },
        sleep: { _ in },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: { source, keyCode, keyDown in
            creationCount += 1
            if creationCount == 2 {
                return nil
            }
            return liveKeyEventFactory(source, keyCode, keyDown)
        },
        postEvent: { _ in
            postedEventCount += 1
            return true
        }
    )

    let result = poster.postMissionControl()
    expect(creationCount == 2, "shortcutのdown/upを両方生成してから判定する")
    expect(result.generatedEventCount == 0, "shortcutの一方を生成できなければ0件投稿にする")
    expect(result.failedEventCreationCount == 1, "shortcutの生成失敗を返す")
    expect(postedEventCount == 0, "不完全なshortcutを部分投稿しない")
}

private func testShortcutValidationIsAtomic() {
    var creationCount = 0
    var postedEventCount = 0
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { 10 },
        sleep: { _ in },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: { source, keyCode, keyDown in
            creationCount += 1
            let generatedKeyCode = creationCount == 2 ? CGKeyCode(kVK_DownArrow) : keyCode
            return liveKeyEventFactory(source, generatedKeyCode, keyDown)
        },
        postEvent: { _ in
            postedEventCount += 1
            return true
        }
    )

    let result = poster.postMissionControl()
    expect(result.generatedEventCount == 0, "検証不一致のshortcutを0件投稿にする")
    expect(result.failedEventCreationCount == 1, "shortcutのkeyCode検証失敗を返す")
    expect(postedEventCount == 0, "検証済みdown/upが揃うまでshortcutを投稿しない")
}

private func testShortcutUsesPerPostTimestamps() {
    let timestamps: [UInt64] = [100, 101]
    var timestampIndex = 0
    var postedEvents: [PostedEventSnapshot] = []
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: {
            defer { timestampIndex += 1 }
            return timestamps[timestampIndex]
        },
        sleep: { _ in },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: liveKeyEventFactory,
        postEvent: { event in
            postedEvents.append(PostedEventSnapshot(event))
            return true
        }
    )

    let result = poster.postMissionControl()
    expect(result.completedSuccessfully, "検証済みshortcutを投稿する")
    expect(result.generatedEventCount == 2, "shortcutのdown/upを2件投稿する")
    expect(postedEvents.map(\.type) == [.keyDown, .keyUp], "shortcutをdown/up順で投稿する")
    expect(postedEvents.map(\.timestamp) == timestamps, "shortcut各eventの投稿直前clock値を使う")
    expect(result.terminalEventCount == 1, "shortcutのkeyUpをterminalとして記録する")
}

private func testShortcutPostFailureRecoversKeyUp() {
    var postAttempt = 0
    var postedEvents: [PostedEventSnapshot] = []
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { UInt64(200 + postAttempt) },
        sleep: { _ in },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: liveKeyEventFactory,
        postEvent: { event in
            postAttempt += 1
            if postAttempt == 2 {
                return false
            }
            postedEvents.append(PostedEventSnapshot(event))
            return true
        }
    )

    let result = poster.postPageBack()
    expect(result.failedEventPostCount == 1, "keyUp投稿失敗を報告する")
    expect(result.unreleasedEventDomainCount == 0, "keyUpを再投稿してactive keyを残さない")
    expect(postedEvents.map(\.type) == [.keyDown, .keyUp], "失敗後もkeyDownをkeyUpへ収束させる")
}

private func scrollCommands() -> [GestureCommand] {
    [
        makeCommand(phase: .began, timestamp: 1),
        makeCommand(phase: .changed, timestamp: 1.01),
        makeCommand(phase: .ended, timestamp: 1.02, deltaX: 0, deltaY: 0)
    ]
}

private func testScrollSequenceCreationIsAtomic() {
    var creationCount = 0
    var postedEventCount = 0
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { 2_000_000_000 },
        sleep: { _ in },
        scrollEventFactory: { source, wheel1, wheel2 in
            creationCount += 1
            if creationCount == 2 {
                return nil
            }
            return liveScrollEventFactory(source, wheel1, wheel2)
        },
        keyEventFactory: liveKeyEventFactory,
        postEvent: { _ in
            postedEventCount += 1
            return true
        }
    )

    let result = poster.postScrollSequence(commands: scrollCommands(), mode: .free, interval: 0.01)
    expect(result.failedEventCreationCount == 1, "scroll列の途中生成失敗を報告する")
    expect(result.generatedEventCount == 0, "全scroll event生成前は0件投稿にする")
    expect(postedEventCount == 0, "不完全なscroll列を部分投稿しない")
}

private func testScrollSequenceValidatesStartAndOriginalOrder() {
    let postingReference: UInt64 = 100_000_000_000
    var postedEvents: [PostedEventSnapshot] = []
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { postingReference },
        sleep: { _ in },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: liveKeyEventFactory,
        postEvent: { event in
            postedEvents.append(PostedEventSnapshot(event))
            return true
        }
    )

    let invalidStarts: [(name: String, value: TimeInterval)] = [
        ("unix-epoch", 1_700_000_000),
        ("future-start", 101)
    ]
    for invalid in invalidStarts {
        let commands = [
            makeCommand(phase: .began, timestamp: invalid.value),
            makeCommand(phase: .ended, timestamp: invalid.value + 1, deltaX: 0, deltaY: 0)
        ]
        let result = poster.postScrollSequence(commands: commands, mode: .free, interval: 1)
        expect(result.failedEventCreationCount == 1, "\(invalid.name)のsequence startを拒否する")
        expect(result.generatedEventCount == 0, "\(invalid.name)のsequenceを投稿しない")
    }
    expect(postedEvents.isEmpty, "boot外startを現在時刻へ黙って正常化しない")

    let regressingCommands = [
        makeCommand(phase: .began, timestamp: 99),
        makeCommand(phase: .ended, timestamp: 98, deltaX: 0, deltaY: 0)
    ]
    let regressionResult = poster.postScrollSequence(
        commands: regressingCommands,
        mode: .free,
        interval: 1
    )
    expect(regressionResult.failedEventCreationCount == 1, "元commandsのtimestamp回帰を拒否する")
    expect(postedEvents.isEmpty, "timestamp回帰sequenceを投稿しない")

    let futureOffsetCommands = [
        makeCommand(phase: .began, timestamp: 99),
        makeCommand(phase: .ended, timestamp: 101, deltaX: 0, deltaY: 0)
    ]
    let futureOffsetResult = poster.postScrollSequence(
        commands: futureOffsetCommands,
        mode: .free,
        interval: 2
    )
    expect(futureOffsetResult.completedSuccessfully, "有効なstartからの未来予定offsetを許可する")
    expect(futureOffsetResult.generatedEventCount == 2, "未来予定offsetを2eventとして投稿する")
    expect(
        postedEvents.map(\.timestamp) == [postingReference, postingReference],
        "後続予定時刻ではなく各投稿時referenceをstampする"
    )
}

private func testScrollPostFailureRecoversTerminal() {
    var postAttempt = 0
    var postedEvents: [PostedEventSnapshot] = []
    var sleeps: [TimeInterval] = []
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { UInt64(2_000_000_000 + postAttempt) },
        sleep: { sleeps.append($0) },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: liveKeyEventFactory,
        postEvent: { event in
            postAttempt += 1
            if postAttempt == 2 {
                return false
            }
            postedEvents.append(PostedEventSnapshot(event))
            return true
        }
    )

    let result = poster.postScrollSequence(commands: scrollCommands(), mode: .free, interval: 0.01)
    let ended = Int64(NSEvent.Phase.ended.rawValue)
    expect(result.failedEventPostCount == 1, "scroll途中投稿失敗を報告する")
    expect(result.unreleasedEventDomainCount == 0, "scroll terminal投稿後にactive domainを残さない")
    expect(postedEvents.count == 2, "失敗後は通常後続を飛ばしてterminalだけを投稿する")
    expect(postedEvents.last?.scrollPhase == ended, "scroll途中失敗をendedへ収束させる")
    expect(result.terminalEventCount == 1, "回復terminalを結果へ記録する")
    expect(sleeps == [0.01], "回復terminalには未来予定offsetのsleepを適用しない")
}

private func makeMouseEvent(type: CGEventType, button: CGMouseButton) -> CGEvent {
    CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: .zero,
        mouseButton: button
    )!
}

private func testPreparedSequenceRecoversMouseUpAndKeyUp() {
    let mouseDomain = DiagnosticEventReleaseDomain.mouseButton(3)
    let keyDomain = DiagnosticEventReleaseDomain.key(Int64(kVK_ANSI_G))
    let mouseDown = makeMouseEvent(type: .otherMouseDown, button: CGMouseButton(rawValue: 3)!)
    let keyDown = liveKeyEventFactory(nil, CGKeyCode(kVK_ANSI_G), true)!
    let ordinary = liveScrollEventFactory(nil, 1, 0)!
    let keyUp = liveKeyEventFactory(nil, CGKeyCode(kVK_ANSI_G), false)!
    let mouseUp = makeMouseEvent(type: .otherMouseUp, button: CGMouseButton(rawValue: 3)!)
    let prepared = [
        DiagnosticPreparedEvent(
            event: mouseDown,
            delayAfterPrevious: 0,
            opensReleaseDomains: [mouseDomain]
        ),
        DiagnosticPreparedEvent(
            event: keyDown,
            delayAfterPrevious: 0.01,
            opensReleaseDomains: [keyDomain]
        ),
        DiagnosticPreparedEvent(event: ordinary, delayAfterPrevious: 0.01),
        DiagnosticPreparedEvent(
            event: keyUp,
            delayAfterPrevious: 0.01,
            closesReleaseDomains: [keyDomain]
        ),
        DiagnosticPreparedEvent(
            event: mouseUp,
            delayAfterPrevious: 0.01,
            closesReleaseDomains: [mouseDomain]
        )
    ]

    var postAttempt = 0
    var postedTypes: [CGEventType] = []
    let poster = DiagnosticEventPoster(
        nowTimestampNanoseconds: { UInt64(2_000 + postAttempt) },
        sleep: { _ in },
        scrollEventFactory: liveScrollEventFactory,
        keyEventFactory: liveKeyEventFactory,
        postEvent: { event in
            postAttempt += 1
            if postAttempt == 3 {
                return false
            }
            postedTypes.append(event.type)
            return true
        }
    )

    let result = poster.postPreparedSequence(prepared)
    expect(result.failedEventPostCount == 1, "未マーク入力の途中投稿失敗を報告する")
    expect(result.unreleasedEventDomainCount == 0, "mouse/key release後にactive domainを残さない")
    expect(
        postedTypes == [.otherMouseDown, .keyDown, .keyUp, .otherMouseUp],
        "途中失敗後にkeyUpとmouseUpだけを順に投稿する"
    )
    expect(result.terminalEventCount == 2, "keyUpとmouseUpの回復投稿を記録する")
}

private struct ToolResult {
    var status: Int32
    var standardOutput: String
    var standardError: String
}

private let toolURL = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .appendingPathComponent("nape-gesture")

private func runTool(_ arguments: [String]) -> ToolResult {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = toolURL
    process.arguments = arguments
    process.standardOutput = standardOutput
    process.standardError = standardError

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        failureCount += 1
        fputs("失敗: nape-gestureを起動できません: \(error)\n", stderr)
        return ToolResult(status: -1, standardOutput: "", standardError: String(describing: error))
    }

    return ToolResult(
        status: process.terminationStatus,
        standardOutput: String(
            decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ),
        standardError: String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    )
}

private typealias JSONRecord = [String: Any]

private func parseJSONLines(_ output: String, title: String) -> [JSONRecord]? {
    var records: [JSONRecord] = []
    for (index, line) in output.split(whereSeparator: \.isNewline).enumerated() {
        do {
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
            guard let record = object as? JSONRecord else {
                throw NSError(domain: "DiagnosticOutputTests", code: 1)
            }
            records.append(record)
        } catch {
            failureCount += 1
            fputs("失敗: \(title) のJSON Lines \(index + 1)行目をdecodeできません。\n", stderr)
            return nil
        }
    }
    return records
}

private func uint64Value(_ value: Any?) -> UInt64? {
    (value as? NSNumber)?.uint64Value
}

private func intValue(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
}

private func doubleValue(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}

private func verifyTimestampContract(
    records: [JSONRecord],
    expectedCount: Int,
    expectedInterval: TimeInterval,
    observedAt: UInt64,
    title: String
) {
    expect(records.count == expectedCount, "\(title) の期待件数は\(expectedCount)件")
    let timestamps = records.compactMap { uint64Value($0["timestamp"]) }
    expect(timestamps.count == records.count, "\(title) の全recordにtimestampがある")
    guard timestamps.count == records.count, !timestamps.isEmpty else {
        return
    }
    expect(timestamps.allSatisfy { $0 > 0 && $0 <= observedAt }, "\(title) が現在boot上限を超えない")

    let expectedIntervalNanoseconds = UInt64(
        (expectedInterval * TimeInterval(MonotonicEventClock.nanosecondsPerSecond)).rounded()
    )
    for pair in zip(timestamps, timestamps.dropFirst()) {
        guard let offset = forwardDifference(from: pair.0, to: pair.1) else {
            expect(false, "\(title) のtimestampが回帰しない")
            continue
        }
        expect(
            approximatelyEqual(offset, expectedIntervalNanoseconds),
            "\(title) の隣接timestamp offsetが期待値と一致する"
        )
    }

    guard let firstTimestamp = timestamps.first,
          let lastTimestamp = timestamps.last,
          let observedOffset = forwardDifference(from: firstTimestamp, to: lastTimestamp)
    else {
        expect(false, "\(title) の系列全体timestampが回帰しない")
        return
    }
    let expectedOffset = UInt64(max(expectedCount - 1, 0)) * expectedIntervalNanoseconds
    expect(
        approximatelyEqual(observedOffset, expectedOffset, tolerance: UInt64(expectedCount + 1)),
        "\(title) の系列全体offsetが期待値と一致する"
    )
}

private func testForwardDifferenceRejectsTimestampRegression() {
    expect(forwardDifference(from: 10, to: 11) == 1, "非回帰timestampの差分を返す")
    expect(forwardDifference(from: 11, to: 10) == nil, "回帰timestampをUInt64減算しない")
}

private struct SystemScenarioExpectation {
    var name: String
    var count: Int
    var interval: TimeInterval
    var firstType: String
    var lastType: String
}

private func testAllSystemScenarioDryRuns() {
    let expectations = [
        SystemScenarioExpectation(name: "space-left", count: 32, interval: 0.008, firstType: "scrollWheel", lastType: "scrollWheel"),
        SystemScenarioExpectation(name: "space-right", count: 32, interval: 0.008, firstType: "scrollWheel", lastType: "scrollWheel"),
        SystemScenarioExpectation(name: "horizontal-scroll", count: 32, interval: 0.008, firstType: "scrollWheel", lastType: "scrollWheel"),
        SystemScenarioExpectation(name: "mission-control", count: 2, interval: 0.01, firstType: "keyDown", lastType: "keyUp"),
        SystemScenarioExpectation(name: "page-back", count: 2, interval: 0.01, firstType: "keyDown", lastType: "keyUp"),
        SystemScenarioExpectation(name: "page-forward", count: 2, interval: 0.01, firstType: "keyDown", lastType: "keyUp"),
        SystemScenarioExpectation(name: "zoom-in", count: 2, interval: 0.01, firstType: "keyDown", lastType: "keyUp"),
        SystemScenarioExpectation(name: "zoom-out", count: 2, interval: 0.01, firstType: "keyDown", lastType: "keyUp"),
        SystemScenarioExpectation(name: "kill-switch", count: 2, interval: 0.008, firstType: "keyDown", lastType: "keyUp"),
        SystemScenarioExpectation(name: "gesture-drag", count: 34, interval: 0.008, firstType: "otherMouseDown", lastType: "otherMouseUp"),
        SystemScenarioExpectation(name: "gesture-wheel", count: 34, interval: 0.008, firstType: "otherMouseDown", lastType: "otherMouseUp"),
        SystemScenarioExpectation(name: "gesture-wheel-then-kill-switch", count: 36, interval: 0.008, firstType: "otherMouseDown", lastType: "otherMouseUp"),
        SystemScenarioExpectation(name: "normal-after-release", count: 10, interval: 0.008, firstType: "otherMouseDown", lastType: "scrollWheel")
    ]

    for expectation in expectations {
        let result = runTool([
            "system-test", "run",
            "--scenario", expectation.name,
            "--dry-run", "--log-json"
        ])
        let observedAt = MonotonicEventClock.nowTimestampNanoseconds
        expect(result.status == 0, "system-test \(expectation.name) dry-runが成功する: \(result.standardError)")
        guard result.status == 0,
              let records = parseJSONLines(result.standardOutput, title: expectation.name)
        else {
            continue
        }

        verifyTimestampContract(
            records: records,
            expectedCount: expectation.count,
            expectedInterval: expectation.interval,
            observedAt: observedAt,
            title: "system-test \(expectation.name)"
        )
        expect(
            records.enumerated().allSatisfy { index, record in
                record["systemTestScenario"] as? String == expectation.name
                    && intValue(record["sequenceIndex"]) == index
            },
            "system-test \(expectation.name) のscenario metadataと順序が一致する"
        )
        expect(records.first?["typeName"] as? String == expectation.firstType, "\(expectation.name) の開始event種別")
        expect(records.last?["typeName"] as? String == expectation.lastType, "\(expectation.name) の終端event種別")

        if expectation.lastType == "scrollWheel", expectation.name != "normal-after-release" {
            let ended = Int(NSEvent.Phase.ended.rawValue)
            expect(intValue(records.last?["scrollPhase"]) == ended, "\(expectation.name) がscroll endedで完結する")
        }
        if expectation.name == "gesture-wheel-then-kill-switch" {
            expect(records.contains { $0["typeName"] as? String == "keyUp" }, "kill-switch中でもkeyUpを含む")
        }
        if expectation.name == "normal-after-release" {
            let types = records.compactMap { $0["typeName"] as? String }
            expect(types.contains("leftMouseUp"), "normal-after-releaseがleftMouseUpを含む")
            expect(types.prefix(2) == ["otherMouseDown", "otherMouseUp"], "通常入力前にactivation buttonを解放する")
        }
    }
}

private func expectedGenerateScrollCount(phase: String, includesMomentum: Bool) -> Int {
    if includesMomentum {
        return phase == "began" || phase == "changed" ? 6 : 5
    }
    return ["began", "changed", "momentum"].contains(phase) ? 3 : 2
}

private func expectedPostedDelta(mode: String) -> (x: Double, y: Double) {
    switch mode {
    case "free":
        return (6, -4)
    case "horizontal", "space-right":
        return (6, 0)
    case "space-left":
        return (-6, 0)
    default:
        return (.nan, .nan)
    }
}

private func testAllGenerateScrollPatterns() {
    let modes = ["free", "horizontal", "space-left", "space-right"]
    let phases = ["auto", "began", "changed", "ended", "cancelled", "momentum"]

    for mode in modes {
        for phase in phases {
            for includesMomentum in [false, true] {
                var arguments = [
                    "generate-scroll",
                    "--x", "12",
                    "--y", "-8",
                    "--steps", "2",
                    "--interval", "0.002",
                    "--mode", mode,
                    "--phase", phase,
                    "--dry-run", "--log-json"
                ]
                if includesMomentum {
                    arguments += [
                        "--momentum-steps", "2",
                        "--momentum-decay", "0.5",
                        "--momentum-scale", "1"
                    ]
                }

                let title = "generate-scroll \(mode)/\(phase)/momentum=\(includesMomentum)"
                let result = runTool(arguments)
                let observedAt = MonotonicEventClock.nowTimestampNanoseconds
                expect(result.status == 0, "\(title)が成功する: \(result.standardError)")
                guard result.status == 0,
                      let records = parseJSONLines(result.standardOutput, title: title)
                else {
                    continue
                }

                verifyTimestampContract(
                    records: records,
                    expectedCount: expectedGenerateScrollCount(
                        phase: phase,
                        includesMomentum: includesMomentum
                    ),
                    expectedInterval: 0.002,
                    observedAt: observedAt,
                    title: title
                )
                expect(
                    records.allSatisfy {
                        $0["typeName"] as? String == "scrollWheel"
                            && intValue($0["isContinuous"]) == 1
                    },
                    "\(title)がcontinuous scrollだけを出力する"
                )
                let expectedDelta = expectedPostedDelta(mode: mode)
                expect(
                    doubleValue(records.first?["pointDeltaX"]) == expectedDelta.x
                        && doubleValue(records.first?["pointDeltaY"]) == expectedDelta.y,
                    "\(title)のmode別deltaが一致する"
                )
                let ended = Int(NSEvent.Phase.ended.rawValue)
                let cancelled = Int(NSEvent.Phase.cancelled.rawValue)
                let lastScrollPhase = intValue(records.last?["scrollPhase"]) ?? 0
                let lastMomentumPhase = intValue(records.last?["momentumPhase"]) ?? 0
                expect(
                    [ended, cancelled].contains(lastScrollPhase)
                        || [ended, cancelled].contains(lastMomentumPhase),
                    "\(title)がscrollまたはmomentum terminalで完結する"
                )
            }
        }
    }
}

private func testDryRunRejectsCurrentBootOverflowAndOversizedCount() {
    let oversizedInterval = String(MonotonicEventClock.nowSeconds + 10)
    let generateOverflow = runTool([
        "generate-scroll",
        "--x", "1",
        "--steps", "2",
        "--interval", oversizedInterval,
        "--dry-run", "--log-json"
    ])
    expect(generateOverflow.status != 0, "generate-scrollが現在boot上限超過offsetを拒否する")
    expect(generateOverflow.standardOutput.isEmpty, "現在boot上限失敗で部分JSON Linesを出さない")

    let systemOverflow = runTool([
        "system-test", "run",
        "--scenario", "gesture-drag",
        "--interval", oversizedInterval,
        "--dry-run", "--log-json"
    ])
    expect(systemOverflow.status != 0, "system-testが現在boot上限超過offsetを拒否する")
    expect(systemOverflow.standardOutput.isEmpty, "system-test上限失敗で部分JSON Linesを出さない")

    let countOverflow = runTool([
        "generate-scroll",
        "--x", "1",
        "--steps", "100001",
        "--dry-run", "--log-json"
    ])
    expect(countOverflow.status != 0, "generate-scrollが生成件数上限超過を拒否する")
    expect(countOverflow.standardOutput.isEmpty, "件数上限失敗で部分JSON Linesを出さない")
}

testScrollEventUsesCurrentBootTimestamp()
testPostScrollFinalizesTimestampImmediatelyBeforePosting()
testInvalidTimestampsFailClosed()
testShortcutCreationIsAtomic()
testShortcutValidationIsAtomic()
testShortcutUsesPerPostTimestamps()
testShortcutPostFailureRecoversKeyUp()
testScrollSequenceCreationIsAtomic()
testScrollSequenceValidatesStartAndOriginalOrder()
testScrollPostFailureRecoversTerminal()
testPreparedSequenceRecoversMouseUpAndKeyUp()
testForwardDifferenceRejectsTimestampRegression()

expect(FileManager.default.isExecutableFile(atPath: toolURL.path), "nape-gesture実行ファイルが存在する")
if FileManager.default.isExecutableFile(atPath: toolURL.path) {
    testAllSystemScenarioDryRuns()
    testAllGenerateScrollPatterns()
    testDryRunRejectsCurrentBootOverflowAndOversizedCount()
}

if failureCount > 0 {
    fputs("diagnostic output tests failed: \(failureCount) 件\n", stderr)
    exit(1)
}

print("diagnostic output tests passed")
