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

private func makeCommand(timestamp: TimeInterval) -> GestureCommand {
    GestureCommand(
        kind: .wheel,
        phase: .changed,
        direction: nil,
        deltaX: 12,
        deltaY: -24,
        velocityX: 0,
        velocityY: 0,
        timestamp: timestamp
    )
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
    expect(
        event.timestamp <= observedAt,
        "作成eventのtimestampが現在bootの未来にならない"
    )
    let difference = event.timestamp >= plannedTimestamp.nanosecondsSinceStartup
        ? event.timestamp - plannedTimestamp.nanosecondsSinceStartup
        : plannedTimestamp.nanosecondsSinceStartup - event.timestamp
    expect(difference <= 1, "作成eventへ検証済み起動後timestampを設定する")
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
        expect(
            result == DiagnosticEventPostResult(
                generatedEventCount: 0,
                failedEventCreationCount: 1
            ),
            "\(invalid.name) timestampを作成失敗として返す"
        )
    }
}

testScrollEventUsesCurrentBootTimestamp()
testInvalidTimestampsFailClosed()

if failureCount > 0 {
    fputs("diagnostic output tests failed: \(failureCount) 件\n", stderr)
    exit(1)
}

print("diagnostic output tests passed")
