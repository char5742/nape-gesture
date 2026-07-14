import CoreGraphics
import Foundation
import NapeGestureCore
import NapeGestureProductOutput

private final class StabilityAssertions {
    private(set) var failures: [String] = []

    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }
}

private final class StabilityPostSink {
    private(set) var attemptedEvents: [CGEvent] = []
    private(set) var acceptedEvents: [CGEvent] = []
    private var relativeAttempt = 0
    private var failureAttempt: Int?

    func configure(failureAttempt: Int?) {
        relativeAttempt = 0
        self.failureAttempt = failureAttempt
    }

    func post(_ event: CGEvent) -> Bool {
        relativeAttempt += 1
        attemptedEvents.append(event)
        if relativeAttempt == failureAttempt {
            return false
        }
        // fakeはeventを記録するだけで、実OSへのCGEvent.postは行わない。
        acceptedEvents.append(event)
        return true
    }
}

private final class StabilityTraceCollector {
    private(set) var traces: [ProductGestureOutputPostedEventTrace] = []

    func observe(_ trace: ProductGestureOutputPostedEventTrace) {
        traces.append(trace)
    }
}

private final class StabilityBaseEventFactory {
    private var relativeCall = 0
    private var failureCall: Int?

    func configure(failureCall: Int?) {
        relativeCall = 0
        self.failureCall = failureCall
    }

    func make() -> CGEvent? {
        relativeCall += 1
        if relativeCall == failureCall {
            return nil
        }
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        event.setIntegerValueField(stabilityRawField(39), value: 9_001)
        event.setIntegerValueField(stabilityRawField(40), value: 9_002)
        return event
    }
}

private final class StabilityRecordingProductOutput: ProductGestureOutput {
    let capability: ProductGestureOutputCapability
    private(set) var events: [TrackpadOutputSessionEvent] = []
    private(set) var resetCount = 0

    init(capability: ProductGestureOutputCapability) {
        self.capability = capability
    }

    func supports(_ family: TrackpadOutputEventFamily) -> Bool {
        capability.isSupported && capability.supportedFamilies.contains(family)
    }

    func post(_ event: TrackpadOutputSessionEvent) -> ProductGestureOutputResult {
        events.append(event)
        return ProductGestureOutputResult(
            generatedEventCount: 1,
            failedEventCreationCount: 0
        )
    }

    func reset() {
        resetCount += 1
    }
}

private enum StabilityFixtures {
    static let contract = read(
        "Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json"
    )
    static let model = read(
        "Fixtures/trackpad-contract/25F80/scroll-output-model.json"
    )
    static let dockSwipeTemplates = read(
        "Fixtures/trackpad-contract/25F80/recognized-dockswipe-templates.json"
    )

    private static func read(_ path: String) -> Data {
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else {
            fatalError("安定性テストfixtureを読み込めません: \(path)")
        }
        return data
    }
}

private func stabilityIdentity25F80() -> ProductGestureOutputSystemIdentity {
    guard
        let identity = ProductGestureOutputSystemIdentity(
            osVersion: "26.5.1",
            osBuild: "25F80"
        )
    else {
        fatalError("安定性テスト用25F80 identityを構成できません")
    }
    return identity
}

private func stabilityTraceContext() -> ProductGestureOutputTraceContext {
    guard
        let context = ProductGestureOutputTraceContext(
            captureRunToken: "00000000-0000-0000-0000-000000000214",
            scenarioID: "product-output-stability-regression",
            repoHeadSHA: String(repeating: "c", count: 40),
            executableSHA256: String(repeating: "d", count: 64)
        )
    else {
        fatalError("安定性テスト用trace contextを構成できません")
    }
    return context
}

private func stabilityRawField(_ number: Int) -> CGEventField {
    unsafeBitCast(UInt32(number), to: CGEventField.self)
}

private func stabilityTimestamp(_ nanoseconds: UInt64) -> MonotonicEventTimestamp {
    MonotonicEventTimestamp(nanosecondsSinceStartup: nanoseconds)
}

private func stabilityInputEvent(
    sessionID: UInt64,
    captureOrder: UInt64,
    timestamp: UInt64,
    phase: TrackpadOutputInputPhase,
    payload: TrackpadOutputPayload
) -> TrackpadOutputSessionEvent {
    let continuation: TrackpadOutputContinuation? = phase == .ended ? .complete : nil
    let terminalDecision: TrackpadOutputTerminalDecision?
    if payload.family == .scroll {
        terminalDecision = nil
    } else {
        switch phase {
        case .ended:
            terminalDecision = .commit
        case .cancelled:
            terminalDecision = .cancel
        case .began, .changed:
            terminalDecision = nil
        }
    }
    return .input(
        TrackpadOutputInputFrame(
            sessionID: TrackpadOutputSessionID(rawValue: sessionID),
            captureOrder: captureOrder,
            timestamp: stabilityTimestamp(timestamp),
            phase: phase,
            continuation: continuation,
            terminalDecision: terminalDecision,
            payload: payload
        )
    )
}

private func stabilityScrollPayload(
    deltaX: Double,
    deltaY: Double
) -> TrackpadOutputPayload {
    .scroll(
        deltaX: deltaX,
        deltaY: deltaY,
        velocityX: 0,
        velocityY: 0
    )
}

private func makeStabilityAdapter(
    sink: StabilityPostSink,
    traceCollector: StabilityTraceCollector,
    baseEventFactory: @escaping ProductBaseEventFactory = { CGEvent(source: nil) }
) -> TrackpadGestureOutputAdapter {
    TrackpadGestureOutputAdapter(
        contractData: StabilityFixtures.contract,
        modelData: StabilityFixtures.model,
        dockSwipeTemplateData: StabilityFixtures.dockSwipeTemplates,
        systemIdentity: stabilityIdentity25F80(),
        traceContext: stabilityTraceContext(),
        scrollEventFactory: { wheel1, wheel2 in
            guard
                let event = CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .pixel,
                    wheelCount: 2,
                    wheel1: wheel1,
                    wheel2: wheel2,
                    wheel3: 0
                )
            else {
                return nil
            }
            event.setIntegerValueField(stabilityRawField(39), value: 8_001)
            event.setIntegerValueField(stabilityRawField(40), value: 8_002)
            return event
        },
        baseEventFactory: baseEventFactory,
        postEvent: sink.post,
        postedEventObserver: traceCollector.observe
    )
}

private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) <= 0.000_001
}

private func testLifecycleGranularityDirectionAndBoundary(
    _ assertions: StabilityAssertions
) {
    let sink = StabilityPostSink()
    let baseFactory = StabilityBaseEventFactory()
    let traceCollector = StabilityTraceCollector()
    let adapter = makeStabilityAdapter(
        sink: sink,
        traceCollector: traceCollector,
        baseEventFactory: baseFactory.make
    )

    let scrollTimestamps: [UInt64] = [1_000_000, 1_000_011, 1_000_029]
    let scrollEvents = [
        stabilityInputEvent(
            sessionID: 3_000,
            captureOrder: 40,
            timestamp: scrollTimestamps[0],
            phase: .began,
            payload: stabilityScrollPayload(deltaX: 12, deltaY: -8)
        ),
        stabilityInputEvent(
            sessionID: 3_000,
            captureOrder: 41,
            timestamp: scrollTimestamps[1],
            phase: .changed,
            payload: stabilityScrollPayload(deltaX: -7, deltaY: 11)
        ),
        stabilityInputEvent(
            sessionID: 3_000,
            captureOrder: 42,
            timestamp: scrollTimestamps[2],
            phase: .ended,
            payload: stabilityScrollPayload(deltaX: 0, deltaY: 0)
        ),
    ]
    let scrollResults = scrollEvents.map(adapter.post)
    assertions.expect(
        scrollResults.allSatisfy {
            $0.failure == nil && $0.generatedEventCount == 3
        },
        "scrollの各source sampleを1 scroll eventと付随2 eventの完全batchにする"
    )

    let dockTimestamps: [UInt64] = [2_000_000, 2_000_017, 2_000_031]
    let dockEvents = [
        stabilityInputEvent(
            sessionID: 3_001,
            captureOrder: 70,
            timestamp: dockTimestamps[0],
            phase: .began,
            payload: .dockSwipe(
                axis: .vertical,
                progress: -0.1,
                motionX: 0,
                motionY: -0.1,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        ),
        stabilityInputEvent(
            sessionID: 3_001,
            captureOrder: 71,
            timestamp: dockTimestamps[1],
            phase: .changed,
            payload: .dockSwipe(
                axis: .vertical,
                progress: -0.4,
                motionX: 0,
                motionY: -0.3,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        ),
        stabilityInputEvent(
            sessionID: 3_001,
            captureOrder: 72,
            timestamp: dockTimestamps[2],
            phase: .cancelled,
            payload: .dockSwipe(
                axis: .vertical,
                progress: -0.4,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: -0.75
            )
        ),
    ]
    let dockResults = dockEvents.map(adapter.post)
    assertions.expect(
        dockResults.allSatisfy {
            $0.failure == nil && $0.generatedEventCount == 1
        },
        "DockSwipeの各source sampleを欠落・重複なしの1 eventにする"
    )

    let pinchTimestamps: [UInt64] = [3_000_000, 3_000_013, 3_000_037]
    let pinchEvents = [
        stabilityInputEvent(
            sessionID: 3_002,
            captureOrder: 90,
            timestamp: pinchTimestamps[0],
            phase: .began,
            payload: .dockSwipePinch(
                progress: 0.1,
                motion: 0.1,
                terminalVelocity: 0
            )
        ),
        stabilityInputEvent(
            sessionID: 3_002,
            captureOrder: 91,
            timestamp: pinchTimestamps[1],
            phase: .changed,
            payload: .dockSwipePinch(
                progress: 0.35,
                motion: 0.25,
                terminalVelocity: 0
            )
        ),
        stabilityInputEvent(
            sessionID: 3_002,
            captureOrder: 92,
            timestamp: pinchTimestamps[2],
            phase: .ended,
            payload: .dockSwipePinch(
                progress: 0.35,
                motion: 0,
                terminalVelocity: 0.6
            )
        ),
    ]
    let pinchResults = pinchEvents.map(adapter.post)
    assertions.expect(
        pinchResults.allSatisfy {
            $0.failure == nil && $0.generatedEventCount == 1
        },
        "DockSwipe pinchの各source sampleを欠落・重複なしの1 eventにする"
    )

    let accepted = sink.acceptedEvents
    assertions.expect(accepted.count == 15, "3 familyの生成event総数を15件に固定する")
    guard accepted.count == 15 else {
        return
    }

    let generatedScrollEvents = Array(accepted[0..<9])
    for index in scrollTimestamps.indices {
        let lowerBound = index * 3
        let batch = Array(generatedScrollEvents[lowerBound..<(lowerBound + 3)])
        assertions.expect(
            batch.filter { $0.type.rawValue == 22 }.count == 1,
            "scroll sample \(index)からscroll eventをちょうど1件生成する"
        )
        assertions.expect(
            batch.map { $0.type.rawValue } == [22, 29, 29],
            "scroll sample \(index)のcontract batch順を保持する"
        )
        assertions.expect(
            batch.allSatisfy { $0.timestamp == scrollTimestamps[index] },
            "scroll sample \(index)のtimestampをbatch全件へ保持する"
        )
    }
    assertions.expect(
        [generatedScrollEvents[0], generatedScrollEvents[3], generatedScrollEvents[6]]
            .map { $0.getIntegerValueField(stabilityRawField(99)) } == [1, 2, 4],
        "scroll phaseをbegan/changed/endedの順で保持する"
    )
    assertions.expect(
        generatedScrollEvents[0].getDoubleValueField(.scrollWheelEventPointDeltaAxis2) > 0
            && generatedScrollEvents[0].getDoubleValueField(.scrollWheelEventPointDeltaAxis1) < 0,
        "scroll beganのX正方向・Y負方向を保持する"
    )
    assertions.expect(
        generatedScrollEvents[3].getDoubleValueField(.scrollWheelEventPointDeltaAxis2) < 0
            && generatedScrollEvents[3].getDoubleValueField(.scrollWheelEventPointDeltaAxis1) > 0,
        "scroll changedの方向反転符号を保持する"
    )
    assertions.expect(
        generatedScrollEvents[2].getDoubleValueField(stabilityRawField(113)) > 0
            && generatedScrollEvents[2].getDoubleValueField(stabilityRawField(119)) < 0
            && generatedScrollEvents[5].getDoubleValueField(stabilityRawField(113)) < 0
            && generatedScrollEvents[5].getDoubleValueField(stabilityRawField(119)) > 0,
        "scroll companionへ各sampleのX/Y符号をそのまま保持する"
    )

    let generatedDockEvents = Array(accepted[9..<12])
    assertions.expect(
        generatedDockEvents.map { $0.getIntegerValueField(stabilityRawField(132)) }
            == [1, 2, 8],
        "DockSwipe phaseをbegan/changed/cancelledの順で保持する"
    )
    assertions.expect(
        generatedDockEvents.map(\.timestamp) == dockTimestamps,
        "DockSwipeのsample timestampを1 eventずつ保持する"
    )
    assertions.expect(
        approximatelyEqual(
            generatedDockEvents[1].getDoubleValueField(stabilityRawField(124)),
            0.4
        )
            && approximatelyEqual(
                generatedDockEvents[1].getDoubleValueField(stabilityRawField(126)),
                0.3
            )
            && approximatelyEqual(
                generatedDockEvents[2].getDoubleValueField(stabilityRawField(130)),
                0.75
            ),
        "負方向vertical DockSwipeのprogress・motion・terminal velocity符号を保持する"
    )

    let generatedPinchEvents = Array(accepted[12..<15])
    assertions.expect(
        generatedPinchEvents.map { $0.getIntegerValueField(stabilityRawField(132)) }
            == [1, 2, 4],
        "DockSwipe pinch phaseをbegan/changed/endedの順で保持する"
    )
    assertions.expect(
        generatedPinchEvents.map(\.timestamp) == pinchTimestamps,
        "DockSwipe pinchのsample timestampを1 eventずつ保持する"
    )
    assertions.expect(
        approximatelyEqual(
            generatedPinchEvents[1].getDoubleValueField(stabilityRawField(124)),
            -0.35
        )
            && approximatelyEqual(
                generatedPinchEvents[2].getDoubleValueField(stabilityRawField(131)),
                -0.6
            ),
        "正方向pinchのprogressとterminal velocity符号を保持する"
    )

    assertions.expect(
        accepted.allSatisfy {
            $0.getIntegerValueField(stabilityRawField(39)) == 0
                && $0.getIntegerValueField(stabilityRawField(40)) == 0
        },
        "注入factoryの対象process値を消去してsystem-wide投稿境界へ渡す"
    )
    assertions.expect(
        traceCollector.traces.count == accepted.count,
        "fake sinkが受理したeventだけに1件ずつtraceを残す"
    )
    assertions.expect(
        traceCollector.traces.map(\.postIndex)
            == Array(0..<UInt64(traceCollector.traces.count)),
        "3 familyをまたいでpost indexを実投稿順に連続させる"
    )
    assertions.expect(
        traceCollector.traces.enumerated().allSatisfy { index, trace in
            trace.delivery == .systemWide
                && trace.eventTimestamp == UInt64(accepted[index].timestamp)
                && trace.prePostTargetProcessSerialNumber == 0
                && trace.prePostTargetUnixProcessID == 0
        },
        "traceへsystem-wide境界・timestamp・対象process未指定を記録する"
    )
}

private func testOrderingSessionAndClassMismatchRecovery(
    _ assertions: StabilityAssertions
) {
    let sink = StabilityPostSink()
    let traceCollector = StabilityTraceCollector()
    let adapter = makeStabilityAdapter(sink: sink, traceCollector: traceCollector)
    let sessionID: UInt64 = 3_100

    let began = stabilityInputEvent(
        sessionID: sessionID,
        captureOrder: 100,
        timestamp: 4_000_000,
        phase: .began,
        payload: .dockSwipe(
            axis: .horizontal,
            progress: -0.1,
            motionX: -0.1,
            motionY: 0,
            terminalVelocityX: 0,
            terminalVelocityY: 0
        )
    )
    assertions.expect(adapter.post(began).failure == nil, "mismatch検査用DockSwipeを開始する")
    let acceptedBeforeRejections = sink.acceptedEvents.count

    let skippedOrder = adapter.post(
        stabilityInputEvent(
            sessionID: sessionID,
            captureOrder: 102,
            timestamp: 4_000_020,
            phase: .changed,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: -0.2,
                motionX: -0.1,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        )
    )
    assertions.expect(skippedOrder.failure == .invalidSession, "DockSwipeのcapture order飛びを拒否する")

    let regressiveTimestamp = adapter.post(
        stabilityInputEvent(
            sessionID: sessionID,
            captureOrder: 101,
            timestamp: 3_999_999,
            phase: .changed,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: -0.2,
                motionX: -0.1,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        )
    )
    assertions.expect(
        regressiveTimestamp.failure == .invalidSession,
        "DockSwipeのtimestamp逆行を拒否する"
    )

    let wrongClass = adapter.post(
        stabilityInputEvent(
            sessionID: sessionID,
            captureOrder: 101,
            timestamp: 4_000_010,
            phase: .changed,
            payload: .dockSwipePinch(
                progress: -0.2,
                motion: -0.1,
                terminalVelocity: 0
            )
        )
    )
    assertions.expect(
        wrongClass.failure == .invalidSession,
        "active DockSwipe sessionへのDockSwipe pinch class混入を拒否する"
    )

    let wrongSession = adapter.post(
        stabilityInputEvent(
            sessionID: sessionID + 1,
            captureOrder: 101,
            timestamp: 4_000_010,
            phase: .changed,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: -0.2,
                motionX: -0.1,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        )
    )
    assertions.expect(
        wrongSession.failure == .invalidSession,
        "beganのない別session changedを拒否する"
    )
    assertions.expect(
        sink.acceptedEvents.count == acceptedBeforeRejections,
        "順序・timestamp・session・class拒否ではeventを投稿しない"
    )

    let validChanged = stabilityInputEvent(
        sessionID: sessionID,
        captureOrder: 101,
        timestamp: 4_000_010,
        phase: .changed,
        payload: .dockSwipe(
            axis: .horizontal,
            progress: -0.3,
            motionX: -0.2,
            motionY: 0,
            terminalVelocityX: 0,
            terminalVelocityY: 0
        )
    )
    let validEnded = stabilityInputEvent(
        sessionID: sessionID,
        captureOrder: 102,
        timestamp: 4_000_030,
        phase: .ended,
        payload: .dockSwipe(
            axis: .horizontal,
            progress: -0.3,
            motionX: 0,
            motionY: 0,
            terminalVelocityX: -0.8,
            terminalVelocityY: 0
        )
    )
    assertions.expect(
        adapter.post(validChanged).failure == nil && adapter.post(validEnded).failure == nil,
        "拒否された入力後も正しいcapture orderからDockSwipeを完結する"
    )
    assertions.expect(
        sink.acceptedEvents.map { $0.getIntegerValueField(stabilityRawField(132)) }
            == [1, 2, 4],
        "mismatch拒否で正規DockSwipe lifecycleを欠落・重複させない"
    )

    let capability = ProductGestureOutputCapability.validated(
        fixtureData: StabilityFixtures.contract,
        systemIdentity: stabilityIdentity25F80()
    )
    let output = StabilityRecordingProductOutput(capability: capability)
    let coordinator = FixedGestureProductSessionCoordinator(output: output)
    let fixedSessionID = TrackpadOutputSessionID(rawValue: 3_200)
    let fixedBegan = FixedGestureInputCommand(
        sessionID: fixedSessionID,
        sourceButton: .button4,
        gestureClass: .threeFingerSystemSwipe,
        captureOrder: 0,
        timestamp: stabilityTimestamp(5_000_000),
        sourceKind: .buttonDown,
        phase: .began,
        deltaX: 0,
        deltaY: 0
    )
    assertions.expect(
        coordinator.post(fixedBegan).result.failure == nil,
        "fixed coordinatorの3本指sessionを開始する"
    )

    let wrongFixedClass = FixedGestureInputCommand(
        sessionID: fixedSessionID,
        sourceButton: .button4,
        gestureClass: .pinch,
        captureOrder: 1,
        timestamp: stabilityTimestamp(5_000_010),
        sourceKind: .move,
        phase: .changed,
        deltaX: 12,
        deltaY: 0
    )
    assertions.expect(
        coordinator.post(wrongFixedClass).result.failure == .invalidSession,
        "fixed sessionへのgesture class差し替えを拒否する"
    )

    let wrongFixedSession = FixedGestureInputCommand(
        sessionID: TrackpadOutputSessionID(rawValue: 3_201),
        sourceButton: .button4,
        gestureClass: .threeFingerSystemSwipe,
        captureOrder: 1,
        timestamp: stabilityTimestamp(5_000_010),
        sourceKind: .move,
        phase: .changed,
        deltaX: 12,
        deltaY: 0
    )
    assertions.expect(
        coordinator.post(wrongFixedSession).result.failure == .invalidSession,
        "fixed coordinatorのactive session ID差し替えを拒否する"
    )

    let wrongFixedButton = FixedGestureInputCommand(
        sessionID: fixedSessionID,
        sourceButton: .button3,
        gestureClass: .threeFingerSystemSwipe,
        captureOrder: 1,
        timestamp: stabilityTimestamp(5_000_010),
        sourceKind: .move,
        phase: .changed,
        deltaX: 12,
        deltaY: 0
    )
    assertions.expect(
        coordinator.post(wrongFixedButton).result.failure == .invalidSession,
        "fixed coordinatorのsource button差し替えを拒否する"
    )
    assertions.expect(output.events.isEmpty, "fixed mismatch拒否時にProductOutputへ投稿しない")

    let fixedChanged = FixedGestureInputCommand(
        sessionID: fixedSessionID,
        sourceButton: .button4,
        gestureClass: .threeFingerSystemSwipe,
        captureOrder: 1,
        timestamp: stabilityTimestamp(5_000_010),
        sourceKind: .move,
        phase: .changed,
        deltaX: 30,
        deltaY: 0
    )
    let fixedEnded = FixedGestureInputCommand(
        sessionID: fixedSessionID,
        sourceButton: .button4,
        gestureClass: .threeFingerSystemSwipe,
        captureOrder: 2,
        timestamp: stabilityTimestamp(5_000_025),
        sourceKind: .buttonUp,
        phase: .ended,
        deltaX: 0,
        deltaY: 0
    )
    assertions.expect(
        coordinator.post(fixedChanged).result.failure == nil
            && coordinator.post(fixedEnded).result.failure == nil,
        "fixed mismatch拒否後も元sessionを正しいclassで完結する"
    )
    assertions.expect(
        output.events.map(\.captureOrder) == [1, 2]
            && output.events.map(\.timestamp)
                == [stabilityTimestamp(5_000_010), stabilityTimestamp(5_000_025)]
            && output.events.allSatisfy {
                $0.sessionID == fixedSessionID && $0.family == .dockSwipe
            },
        "fixed mismatch拒否後も1 sample 1 event・order・timestamp・classを保持する"
    )
}

private func testScrollCreationAndPartialPostRecovery(
    _ assertions: StabilityAssertions
) {
    let creationSink = StabilityPostSink()
    let baseFactory = StabilityBaseEventFactory()
    let creationTraceCollector = StabilityTraceCollector()
    let creationAdapter = makeStabilityAdapter(
        sink: creationSink,
        traceCollector: creationTraceCollector,
        baseEventFactory: baseFactory.make
    )
    let creationBegan = stabilityInputEvent(
        sessionID: 3_300,
        captureOrder: 0,
        timestamp: 6_000_000,
        phase: .began,
        payload: stabilityScrollPayload(deltaX: 8, deltaY: -5)
    )
    let creationChanged = stabilityInputEvent(
        sessionID: 3_300,
        captureOrder: 1,
        timestamp: 6_000_010,
        phase: .changed,
        payload: stabilityScrollPayload(deltaX: -6, deltaY: 9)
    )
    let creationEnded = stabilityInputEvent(
        sessionID: 3_300,
        captureOrder: 2,
        timestamp: 6_000_020,
        phase: .ended,
        payload: stabilityScrollPayload(deltaX: 0, deltaY: 0)
    )
    assertions.expect(
        creationAdapter.post(creationBegan).failure == nil,
        "作成途中失敗検査用scrollを開始する"
    )
    let acceptedBeforeCreationFailure = creationSink.acceptedEvents.count
    let attemptsBeforeCreationFailure = creationSink.attemptedEvents.count
    let tracesBeforeCreationFailure = creationTraceCollector.traces.count
    baseFactory.configure(failureCall: 2)
    let creationFailure = creationAdapter.post(creationChanged)
    assertions.expect(
        creationFailure.failure == .eventCreationFailed
            && creationFailure.generatedEventCount == 0
            && creationFailure.failedEventCreationCount == 1,
        "scroll changedの3件目構築失敗を部分成功にしない"
    )
    assertions.expect(
            creationSink.acceptedEvents.count == acceptedBeforeCreationFailure
            && creationSink.attemptedEvents.count == attemptsBeforeCreationFailure
            && creationTraceCollector.traces.count == tracesBeforeCreationFailure,
        "scroll batch全件構築前はpost closureとtraceを一度も進めない"
    )

    baseFactory.configure(failureCall: nil)
    let creationRetry = creationAdapter.post(creationChanged)
    let creationTerminal = creationAdapter.post(creationEnded)
    assertions.expect(
        creationRetry.failure == nil && creationRetry.generatedEventCount == 3,
        "構築失敗した同一changed sampleを同じorderから再試行する"
    )
    assertions.expect(
        creationTerminal.failure == nil && creationTerminal.generatedEventCount == 3,
        "構築失敗から復旧したscroll sessionをterminalまで閉じる"
    )
    assertions.expect(
        creationSink.acceptedEvents.filter { $0.type.rawValue == 22 }
            .map { $0.getIntegerValueField(stabilityRawField(99)) } == [1, 2, 4],
        "構築失敗sampleの再試行でscroll eventを重複させない"
    )
    assertions.expect(
        creationTraceCollector.traces.map(\.postIndex)
            == Array(0..<UInt64(creationTraceCollector.traces.count)),
        "構築失敗をpost indexの欠番にしない"
    )

    let postSink = StabilityPostSink()
    let postTraceCollector = StabilityTraceCollector()
    let postAdapter = makeStabilityAdapter(
        sink: postSink,
        traceCollector: postTraceCollector
    )
    let postBegan = stabilityInputEvent(
        sessionID: 3_301,
        captureOrder: 10,
        timestamp: 7_000_000,
        phase: .began,
        payload: stabilityScrollPayload(deltaX: 7, deltaY: -4)
    )
    let postChanged = stabilityInputEvent(
        sessionID: 3_301,
        captureOrder: 11,
        timestamp: 7_000_010,
        phase: .changed,
        payload: stabilityScrollPayload(deltaX: -9, deltaY: 6)
    )
    let postEnded = stabilityInputEvent(
        sessionID: 3_301,
        captureOrder: 12,
        timestamp: 7_000_020,
        phase: .ended,
        payload: stabilityScrollPayload(deltaX: 0, deltaY: 0)
    )
    assertions.expect(postAdapter.post(postBegan).failure == nil, "部分投稿検査用scrollを開始する")
    postSink.configure(failureAttempt: 2)
    let partialPost = postAdapter.post(postChanged)
    assertions.expect(
        partialPost.failure == .eventPostFailed
            && partialPost.generatedEventCount == 1,
        "scroll changedの2件目post失敗までの成功数を1件にする"
    )
    assertions.expect(
        postSink.acceptedEvents.count == 4 && postTraceCollector.traces.count == 4,
        "部分投稿失敗では実際に受理されたeventとtraceだけを残す"
    )

    postSink.configure(failureAttempt: nil)
    let partialRetry = postAdapter.post(postChanged)
    let postTerminal = postAdapter.post(postEnded)
    assertions.expect(
        partialRetry.failure == nil && partialRetry.generatedEventCount == 2,
        "同一changed sample再試行で未投稿の2件だけを再開する"
    )
    assertions.expect(
        postTerminal.failure == nil && postTerminal.generatedEventCount == 3,
        "部分投稿復旧後のscroll terminalを完全投稿する"
    )
    assertions.expect(
        postSink.acceptedEvents.count == 9
            && postSink.acceptedEvents.filter { $0.type.rawValue == 22 }
                .map { $0.getIntegerValueField(stabilityRawField(99)) } == [1, 2, 4],
        "部分投稿再試行で投稿済みscroll eventを重複させない"
    )
    assertions.expect(
        postTraceCollector.traces.map(\.postIndex)
            == Array(0..<UInt64(postTraceCollector.traces.count)),
        "部分投稿失敗と再試行をまたいでpost indexを連続させる"
    )
}

private func testRecognizedGestureTerminalRecovery(
    _ assertions: StabilityAssertions
) {
    struct RecoveryCase {
        let label: String
        let sessionID: UInt64
        let beganPayload: TrackpadOutputPayload
        let changedPayload: TrackpadOutputPayload
        let terminalPhase: TrackpadOutputInputPhase
        let terminalPayload: TrackpadOutputPayload
        let expectedTerminalPhase: Int64
        let zeroDirectionPayload: TrackpadOutputPayload
    }

    let cases = [
        RecoveryCase(
            label: "DockSwipe",
            sessionID: 3_400,
            beganPayload: .dockSwipe(
                axis: .horizontal,
                progress: -0.1,
                motionX: -0.1,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            ),
            changedPayload: .dockSwipe(
                axis: .horizontal,
                progress: -0.4,
                motionX: -0.3,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            ),
            terminalPhase: .cancelled,
            terminalPayload: .dockSwipe(
                axis: .horizontal,
                progress: -0.4,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: -0.9,
                terminalVelocityY: 0
            ),
            expectedTerminalPhase: 8,
            zeroDirectionPayload: .dockSwipe(
                axis: .horizontal,
                progress: 0,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        ),
        RecoveryCase(
            label: "DockSwipe pinch",
            sessionID: 3_401,
            beganPayload: .dockSwipePinch(
                progress: 0.1,
                motion: 0.1,
                terminalVelocity: 0
            ),
            changedPayload: .dockSwipePinch(
                progress: 0.45,
                motion: 0.35,
                terminalVelocity: 0
            ),
            terminalPhase: .ended,
            terminalPayload: .dockSwipePinch(
                progress: 0.45,
                motion: 0,
                terminalVelocity: 0.7
            ),
            expectedTerminalPhase: 4,
            zeroDirectionPayload: .dockSwipePinch(
                progress: 0,
                motion: 0,
                terminalVelocity: 0
            )
        ),
    ]

    for (index, item) in cases.enumerated() {
        let sink = StabilityPostSink()
        let traceCollector = StabilityTraceCollector()
        let adapter = makeStabilityAdapter(
            sink: sink,
            traceCollector: traceCollector
        )
        let timestampBase = UInt64(8_000_000 + index * 100_000)
        let zeroDirection = stabilityInputEvent(
            sessionID: item.sessionID,
            captureOrder: 20,
            timestamp: timestampBase,
            phase: .began,
            payload: item.zeroDirectionPayload
        )
        let creationFailure = adapter.post(zeroDirection)
        assertions.expect(
            creationFailure.failure == .eventCreationFailed
                && creationFailure.generatedEventCount == 0,
            "\(item.label)の方向未確定beganを作成失敗として拒否する"
        )
        assertions.expect(
            sink.attemptedEvents.isEmpty && traceCollector.traces.isEmpty,
            "\(item.label)の作成失敗ではpost closureとtraceを進めない"
        )

        let began = stabilityInputEvent(
            sessionID: item.sessionID,
            captureOrder: 20,
            timestamp: timestampBase,
            phase: .began,
            payload: item.beganPayload
        )
        let changed = stabilityInputEvent(
            sessionID: item.sessionID,
            captureOrder: 21,
            timestamp: timestampBase + 10,
            phase: .changed,
            payload: item.changedPayload
        )
        let terminal = stabilityInputEvent(
            sessionID: item.sessionID,
            captureOrder: 22,
            timestamp: timestampBase + 20,
            phase: item.terminalPhase,
            payload: item.terminalPayload
        )
        assertions.expect(
            adapter.post(began).failure == nil && adapter.post(changed).failure == nil,
            "\(item.label)を作成失敗後の同じsession/orderから開始する"
        )

        sink.configure(failureAttempt: 1)
        let failedTerminal = adapter.post(terminal)
        assertions.expect(
            failedTerminal.failure == .eventPostFailed
                && failedTerminal.generatedEventCount == 0,
            "\(item.label) terminalのpost失敗を成功扱いしない"
        )
        assertions.expect(
            sink.acceptedEvents.count == 2 && traceCollector.traces.count == 2,
            "\(item.label) terminal失敗では成功eventとtraceを増やさない"
        )

        sink.configure(failureAttempt: nil)
        let retry = adapter.post(terminal)
        assertions.expect(
            retry.failure == nil && retry.generatedEventCount == 1,
            "\(item.label) terminalを同一sampleで再試行する"
        )
        assertions.expect(
            sink.acceptedEvents.count == 3
                && sink.acceptedEvents.last?.getIntegerValueField(stabilityRawField(132))
                    == item.expectedTerminalPhase,
            "\(item.label) terminal再試行を1 eventだけ投稿する"
        )
        assertions.expect(
            traceCollector.traces.map(\.postIndex) == [0, 1, 2]
                && traceCollector.traces.last?.eventTimestamp == timestampBase + 20,
            "\(item.label) terminal失敗をtrace欠番にせずtimestampを保持する"
        )

        let acceptedBeforeRepeatedTerminal = sink.acceptedEvents.count
        let repeatedTerminal = adapter.post(terminal)
        assertions.expect(
            repeatedTerminal.failure == .invalidSession,
            "\(item.label) terminal成功後の重複再投稿を拒否する"
        )
        assertions.expect(
            sink.acceptedEvents.count == acceptedBeforeRepeatedTerminal,
            "\(item.label)の閉じたsessionからterminalを重複生成しない"
        )
    }
}

private func testUnsupportedIdentityFixtureAndHashFailClosed(
    _ assertions: StabilityAssertions
) {
    func assertFailClosed(
        label: String,
        adapter: TrackpadGestureOutputAdapter,
        sink: StabilityPostSink,
        expectedFailure: ProductGestureOutputFailure
    ) {
        assertions.expect(
            ProductGestureOutputCapability.runtimeFamilies.allSatisfy {
                !adapter.supports($0)
            },
            "\(label)では全ProductOutput familyを無効化する"
        )
        let events = [
            stabilityInputEvent(
                sessionID: 3_500,
                captureOrder: 0,
                timestamp: 9_000_000,
                phase: .began,
                payload: stabilityScrollPayload(deltaX: 4, deltaY: -3)
            ),
            stabilityInputEvent(
                sessionID: 3_501,
                captureOrder: 0,
                timestamp: 9_000_010,
                phase: .began,
                payload: .dockSwipe(
                    axis: .horizontal,
                    progress: 0.1,
                    motionX: 0.1,
                    motionY: 0,
                    terminalVelocityX: 0,
                    terminalVelocityY: 0
                )
            ),
            stabilityInputEvent(
                sessionID: 3_502,
                captureOrder: 0,
                timestamp: 9_000_020,
                phase: .began,
                payload: .dockSwipePinch(
                    progress: 0.1,
                    motion: 0.1,
                    terminalVelocity: 0
                )
            ),
        ]
        let results = events.map(adapter.post)
        assertions.expect(
            results.allSatisfy {
                $0.failure == expectedFailure && $0.generatedEventCount == 0
            },
            "\(label)では全familyを\(expectedFailure.rawValue)でfail closedにする"
        )
        assertions.expect(
            sink.attemptedEvents.isEmpty,
            "\(label)ではpost closureを1回も呼ばない"
        )
    }

    let missingSink = StabilityPostSink()
    let missingAdapter = TrackpadGestureOutputAdapter(
        contractData: nil,
        modelData: StabilityFixtures.model,
        dockSwipeTemplateData: StabilityFixtures.dockSwipeTemplates,
        systemIdentity: stabilityIdentity25F80(),
        postEvent: missingSink.post
    )
    assertions.expect(
        missingAdapter.capability.status == .unsupported,
        "contract resource欠落をunsupportedにする"
    )
    assertFailClosed(
        label: "contract resource欠落",
        adapter: missingAdapter,
        sink: missingSink,
        expectedFailure: .unsupported
    )

    guard
        let unknownIdentity = ProductGestureOutputSystemIdentity(
            osVersion: "26.5.1",
            osBuild: "25F81"
        )
    else {
        assertions.expect(false, "未知OS identityを構成できません")
        return
    }
    let osSink = StabilityPostSink()
    let osAdapter = TrackpadGestureOutputAdapter(
        contractData: StabilityFixtures.contract,
        modelData: StabilityFixtures.model,
        dockSwipeTemplateData: StabilityFixtures.dockSwipeTemplates,
        systemIdentity: unknownIdentity,
        postEvent: osSink.post
    )
    assertions.expect(
        osAdapter.capability.status == .contractMismatch,
        "未登録OS buildをcontract mismatchにする"
    )
    assertFailClosed(
        label: "未登録OS build",
        adapter: osAdapter,
        sink: osSink,
        expectedFailure: .contractMismatch
    )

    var unknownFixtureObject: [String: Any]
    do {
        guard
            let object = try JSONSerialization.jsonObject(
                with: StabilityFixtures.contract
            ) as? [String: Any]
        else {
            assertions.expect(false, "fixture ID差し替え用JSON objectを構成できません")
            return
        }
        unknownFixtureObject = object
    } catch {
        assertions.expect(false, "fixture ID差し替え用JSONを解析できません: \(error)")
        return
    }
    unknownFixtureObject["fixtureID"] = "trackpad-scroll-momentum-unknown-v1"
    let unknownFixtureData: Data
    do {
        unknownFixtureData = try JSONSerialization.data(
            withJSONObject: unknownFixtureObject,
            options: [.sortedKeys]
        )
    } catch {
        assertions.expect(false, "未登録fixture JSONを生成できません: \(error)")
        return
    }
    let unknownFixtureReport = TrackpadScrollMomentumContractDocumentReader.read(
        data: unknownFixtureData
    )
    assertions.expect(
        unknownFixtureReport.issues.contains { $0.code == .unregisteredFixture },
        "未登録fixture IDをunregistered fixtureとして識別する"
    )
    let fixtureSink = StabilityPostSink()
    let fixtureAdapter = TrackpadGestureOutputAdapter(
        contractData: unknownFixtureData,
        modelData: StabilityFixtures.model,
        dockSwipeTemplateData: StabilityFixtures.dockSwipeTemplates,
        systemIdentity: stabilityIdentity25F80(),
        postEvent: fixtureSink.post
    )
    assertions.expect(
        fixtureAdapter.capability.status == .contractMismatch,
        "未登録fixture IDをcontract mismatchにする"
    )
    assertFailClosed(
        label: "未登録fixture ID",
        adapter: fixtureAdapter,
        sink: fixtureSink,
        expectedFailure: .contractMismatch
    )

    var hashMismatchData = StabilityFixtures.contract
    hashMismatchData.append(0x0A)
    let hashMismatchReport = TrackpadScrollMomentumContractDocumentReader.read(
        data: hashMismatchData
    )
    assertions.expect(
        hashMismatchReport.issues.contains { $0.code == .fixtureRegistrationMismatch },
        "登録fixtureの1 byte差をSHA-256 registration mismatchとして識別する"
    )
    let hashSink = StabilityPostSink()
    let hashAdapter = TrackpadGestureOutputAdapter(
        contractData: hashMismatchData,
        modelData: StabilityFixtures.model,
        dockSwipeTemplateData: StabilityFixtures.dockSwipeTemplates,
        systemIdentity: stabilityIdentity25F80(),
        postEvent: hashSink.post
    )
    assertions.expect(
        hashAdapter.capability.status == .contractMismatch,
        "登録fixtureのSHA-256不一致をcontract mismatchにする"
    )
    assertFailClosed(
        label: "登録fixture SHA-256不一致",
        adapter: hashAdapter,
        sink: hashSink,
        expectedFailure: .contractMismatch
    )
}

func runStabilityRegressionTests() -> [String] {
    let assertions = StabilityAssertions()
    testLifecycleGranularityDirectionAndBoundary(assertions)
    testOrderingSessionAndClassMismatchRecovery(assertions)
    testScrollCreationAndPartialPostRecovery(assertions)
    testRecognizedGestureTerminalRecovery(assertions)
    testUnsupportedIdentityFixtureAndHashFailClosed(assertions)
    return assertions.failures
}
