import CoreGraphics
import Foundation
import NapeGestureCore
import NapeGestureProductOutput

private var failures: [String] = []

private final class EventCollector {
    var events: [CGEvent] = []
    var postedTrace: [ProductGestureOutputPostedEventTrace] = []
}

private final class InjectedPostSink {
    let collector: EventCollector
    private(set) var attempt = 0
    private var failureAttempt: Int?

    init(collector: EventCollector) {
        self.collector = collector
    }

    func configure(failureAttempt: Int?) {
        attempt = 0
        self.failureAttempt = failureAttempt
    }

    func post(_ event: CGEvent) -> Bool {
        attempt += 1
        if attempt == failureAttempt {
            return false
        }
        collector.events.append(event)
        return true
    }
}

private final class PermissiveProductOutput: ProductGestureOutput {
    let capability: ProductGestureOutputCapability
    private(set) var postedEvents: [TrackpadOutputSessionEvent] = []
    private(set) var resetCount = 0

    init(capability: ProductGestureOutputCapability) {
        self.capability = capability
    }

    func supports(_ family: TrackpadOutputEventFamily) -> Bool {
        capability.isSupported && capability.supportedFamilies.contains(family)
    }

    func post(_ event: TrackpadOutputSessionEvent) -> ProductGestureOutputResult {
        postedEvents.append(event)
        return ProductGestureOutputResult(generatedEventCount: 1, failedEventCreationCount: 0)
    }

    func reset() {
        resetCount += 1
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

private func rawField(_ number: Int) -> CGEventField {
    unsafeBitCast(UInt32(number), to: CGEventField.self)
}

private func contractData() -> Data {
    let path = "Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json"
    guard let data = FileManager.default.contents(atPath: path) else {
        fatalError("contract fixtureを読み込めません: \(path)")
    }
    return data
}

private func modelData() -> Data {
    let path = "Fixtures/trackpad-contract/25F80/scroll-output-model.json"
    guard let data = FileManager.default.contents(atPath: path) else {
        fatalError("output model fixtureを読み込めません: \(path)")
    }
    return data
}

private func identity25F80() -> ProductGestureOutputSystemIdentity {
    guard let identity = ProductGestureOutputSystemIdentity(
        osVersion: "26.5.1",
        osBuild: "25F80"
    ) else {
        fatalError("25F80 identityを構成できません")
    }
    return identity
}

private func productTraceContext() -> ProductGestureOutputTraceContext {
    guard let context = ProductGestureOutputTraceContext(
        captureRunToken: "00000000-0000-0000-0000-000000000119",
        scenarioID: "issue-119-product-output-tests",
        repoHeadSHA: String(repeating: "a", count: 40),
        executableSHA256: String(repeating: "b", count: 64)
    ) else {
        fatalError("product output trace contextを構成できません")
    }
    return context
}

private func scrollPayload(
    deltaX: Double,
    deltaY: Double,
    velocityX: Double = 0,
    velocityY: Double = 0
) -> TrackpadOutputPayload {
    .scroll(
        deltaX: deltaX,
        deltaY: deltaY,
        velocityX: velocityX,
        velocityY: velocityY
    )
}

private func inputEvent(
    sessionID: UInt64,
    order: UInt64,
    phase: TrackpadOutputInputPhase,
    continuation: TrackpadOutputContinuation? = nil,
    deltaX: Double,
    deltaY: Double,
    timestamp: MonotonicEventTimestamp = MonotonicEventClock.now
) -> TrackpadOutputSessionEvent {
    .input(
        TrackpadOutputInputFrame(
            sessionID: TrackpadOutputSessionID(rawValue: sessionID),
            captureOrder: order,
            timestamp: timestamp,
            phase: phase,
            continuation: continuation,
            payload: scrollPayload(deltaX: deltaX, deltaY: deltaY)
        )
    )
}

private func momentumEvent(
    sessionID: UInt64,
    order: UInt64,
    phase: TrackpadOutputMomentumPhase,
    deltaX: Double,
    deltaY: Double
) -> TrackpadOutputSessionEvent {
    .momentum(
        TrackpadOutputMomentumFrame(
            sessionID: TrackpadOutputSessionID(rawValue: sessionID),
            captureOrder: order,
            timestamp: MonotonicEventClock.now,
            phase: phase,
            payload: scrollPayload(deltaX: deltaX, deltaY: deltaY)
        )
    )
}

private func cancellationEvent(
    sessionID: UInt64,
    order: UInt64,
    reason: TrackpadOutputCancellationReason,
    timestamp: MonotonicEventTimestamp = MonotonicEventClock.now
) -> TrackpadOutputSessionEvent {
    .cancellation(
        TrackpadOutputCancellationFrame(
            sessionID: TrackpadOutputSessionID(rawValue: sessionID),
            captureOrder: order,
            timestamp: timestamp,
            family: .scroll,
            reason: reason,
            payload: scrollPayload(deltaX: 0, deltaY: 0)
        )
    )
}

private func makeAdapter(
    collector: EventCollector,
    baseEventFactory: @escaping ProductBaseEventFactory = { CGEvent(source: nil) }
) -> TrackpadGestureOutputAdapter {
    TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        traceContext: productTraceContext(),
        baseEventFactory: baseEventFactory,
        postEvent: { event in
            collector.events.append(event)
            return true
        },
        postedEventObserver: { collector.postedTrace.append($0) }
    )
}

private func makeInjectedAdapter(
    sink: InjectedPostSink,
    traceCollector: EventCollector? = nil
) -> TrackpadGestureOutputAdapter {
    TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        traceContext: traceCollector == nil ? nil : productTraceContext(),
        postEvent: sink.post,
        postedEventObserver: traceCollector.map { collector in
            { collector.postedTrace.append($0) }
        }
    )
}

private func assertInputCancellationBatch(_ events: [CGEvent], label: String) {
    expect(events.count == 3, "\(label)を3 eventで閉じる: \(events.count)")
    guard events.count == 3 else {
        return
    }
    expect(events.map { $0.type.rawValue } == [22, 29, 29], "\(label)をscroll、envelope、companionの順で投稿する")
    expect(events[0].getIntegerValueField(rawField(99)) == 4, "\(label)のscroll phaseをendedにする")
    expect(events[1].getIntegerValueField(rawField(132)) == 4, "\(label)のenvelope phaseをendedにする")
    expect(events[2].getIntegerValueField(rawField(132)) == 4, "\(label)のcompanion phaseをendedにする")
    expect(events.dropFirst().allSatisfy { $0.timestamp == events[0].timestamp }, "\(label)の3 eventを同一timestampにする")
    assertPositiveZeroTerminal(events[0], label: label)
}

private func assertPositiveZeroTerminal(_ event: CGEvent, label: String) {
    let integerFields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventDeltaAxis3
    ]
    let doubleFields: [CGEventField] = [
        .scrollWheelEventFixedPtDeltaAxis1,
        .scrollWheelEventFixedPtDeltaAxis2,
        .scrollWheelEventFixedPtDeltaAxis3,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventPointDeltaAxis2,
        .scrollWheelEventPointDeltaAxis3
    ]
    expect(integerFields.allSatisfy { event.getIntegerValueField($0) == 0 }, "\(label)のinteger terminal deltaが0ではない")
    expect(
        doubleFields.allSatisfy {
            event.getDoubleValueField($0).bitPattern == Double(0.0).bitPattern
        },
        "\(label)のfixed/point terminal deltaが+0.0ではない"
    )
}

private func testLifecycleAndFields() {
    let collector = EventCollector()
    let adapter = makeAdapter(collector: collector)
    expect(adapter.capability.isSupported, "25F80 contractをsupportedとして検証する")
    expect(adapter.supports(.scroll), "scroll familyを対応扱いする")
    expect(TrackpadOutputEventFamily.allCases.allSatisfy(adapter.supports), "25F80で4 familyを対応扱いする")

    let results = [
        adapter.post(inputEvent(sessionID: 1, order: 0, phase: .began, deltaX: 12, deltaY: -8)),
        adapter.post(inputEvent(sessionID: 1, order: 1, phase: .changed, deltaX: 24, deltaY: -16)),
        adapter.post(inputEvent(sessionID: 1, order: 2, phase: .ended, continuation: .momentum, deltaX: 0, deltaY: 0)),
        adapter.post(momentumEvent(sessionID: 1, order: 3, phase: .began, deltaX: 8, deltaY: -4)),
        adapter.post(momentumEvent(sessionID: 1, order: 4, phase: .continued, deltaX: 4, deltaY: -2)),
        adapter.post(momentumEvent(sessionID: 1, order: 5, phase: .ended, deltaX: 0, deltaY: 0))
    ]
    expect(results.map(\.generatedEventCount) == [3, 3, 3, 1, 1, 1], "inputは3 event、momentumは1 eventを完全生成する: \(results)")
    expect(results.allSatisfy { $0.failure == nil }, "正常lifecycleをfailureにしない: \(results)")
    let events = collector.events
    expect(events.count == 12, "scroll/momentum lifecycleの全eventを投稿する")
    expect(collector.postedTrace.count == events.count, "全成功投稿にpost traceを1件ずつ残す")
    expect(
        events.allSatisfy {
            $0.getIntegerValueField(rawField(39)) == 0
                && $0.getIntegerValueField(rawField(40)) == 0
        },
        "post closureが受け取る投稿前eventのraw field 39/40を全件0にする"
    )
    expect(
        collector.postedTrace.enumerated().allSatisfy {
            $0.element.postIndex == UInt64($0.offset)
                && $0.element.sessionID == TrackpadOutputSessionID(rawValue: 1)
                && $0.element.family == .scroll
                && $0.element.delivery == .systemWide
        },
        "post traceへ連続index、session、family、systemWide配送を固定する"
    )
    let expectedTraceContext = productTraceContext()
    expect(
        collector.postedTrace.allSatisfy {
            $0.schemaVersion == ProductGestureOutputPostedEventTrace.currentSchemaVersion
                && $0.captureRunToken == expectedTraceContext.captureRunToken
                && $0.scenarioID == expectedTraceContext.scenarioID
                && $0.repoHeadSHA == expectedTraceContext.repoHeadSHA
                && $0.executableSHA256 == expectedTraceContext.executableSHA256
                && $0.prePostTargetProcessSerialNumber == 0
                && $0.prePostTargetUnixProcessID == 0
        },
        "schema 2 traceへcontextとpost直前のraw 39/40を記録する"
    )

    guard events.count == 12 else {
        return
    }

    let expectedTypes: [UInt32] = [22, 29, 29, 22, 29, 29, 22, 29, 29, 22, 22, 22]
    expect(events.map { $0.type.rawValue } == expectedTypes, "type22 -> envelope -> companionとmomentum type22の順序を守る")
    expect(events[0].getIntegerValueField(rawField(99)) == 1, "scroll began phaseを1にする")
    expect(events[3].getIntegerValueField(rawField(99)) == 2, "scroll changed phaseを2にする")
    expect(events[6].getIntegerValueField(rawField(99)) == 4, "scroll ended phaseを4にする")
    expect(events[9].getIntegerValueField(rawField(123)) == 1, "momentum began phaseを1にする")
    expect(events[10].getIntegerValueField(rawField(123)) == 2, "momentum continued phaseを2にする")
    expect(events[11].getIntegerValueField(rawField(123)) == 3, "momentum ended phaseを3にする")
    expect(events.filter { $0.type.rawValue == 22 }.allSatisfy { $0.getIntegerValueField(rawField(88)) == 1 }, "全type22をcontinuousにする")

    let envelope = events[1]
    let companion = events[2]
    expect(envelope.timestamp == companion.timestamp, "envelopeとcompanionを同一timestampにする")
    expect(envelope.getIntegerValueField(rawField(110)) == 0, "envelope classifierを0にする")
    expect(companion.getIntegerValueField(rawField(110)) == 6, "companion classifierを6にする")
    expect(companion.getIntegerValueField(rawField(132)) == 1, "companion phaseをscrollと一致させる")
    expect(companion.getIntegerValueField(rawField(135)) == 1, "companion constant 135を1にする")
    let xMotion = Float(12)
    let yMotion = Float(-8)
    expect([113, 114, 116, 118].allSatisfy { companion.getDoubleValueField(rawField($0)) == Double(xMotion) }, "companion X double aliasを一致させる")
    expect([115, 117, 164].allSatisfy { companion.getIntegerValueField(rawField($0)) == Int64(xMotion.bitPattern) }, "companion X Float aliasを一致させる")
    expect([119, 139].allSatisfy { companion.getDoubleValueField(rawField($0)) == Double(yMotion) }, "companion Y double aliasを一致させる")
    expect([123, 165].allSatisfy { companion.getIntegerValueField(rawField($0)) == Int64(yMotion.bitPattern) }, "companion Y Float aliasを一致させる")
    assertPositiveZeroTerminal(events[6], label: "scroll ended")
    assertPositiveZeroTerminal(events[11], label: "momentum ended")
}

private func testCancellationStates() {
    let inputCollector = EventCollector()
    let inputAdapter = makeAdapter(collector: inputCollector)
    _ = inputAdapter.post(inputEvent(sessionID: 2, order: 0, phase: .began, deltaX: 5, deltaY: 0))
    let inputCancellation = inputAdapter.post(cancellationEvent(sessionID: 2, order: 1, reason: .killSwitch))
    expect(inputCancellation.generatedEventCount == 3, "input active cancelはscroll ended + companionで閉じる: \(inputCancellation)")
    if inputCollector.events.count > 3 {
        assertPositiveZeroTerminal(inputCollector.events[3], label: "input cancel")
    }

    let waitingCollector = EventCollector()
    let waitingAdapter = makeAdapter(collector: waitingCollector)
    _ = waitingAdapter.post(inputEvent(sessionID: 3, order: 0, phase: .began, deltaX: 5, deltaY: 0))
    _ = waitingAdapter.post(inputEvent(sessionID: 3, order: 1, phase: .ended, continuation: .momentum, deltaX: 0, deltaY: 0))
    let waitingCancellation = waitingAdapter.post(cancellationEvent(sessionID: 3, order: 2, reason: .runtimeStop))
    expect(waitingCancellation.generatedEventCount == 0, "awaiting momentumは既にscroll ended済みなので重複terminalを出さない")

    let momentumCollector = EventCollector()
    let momentumAdapter = makeAdapter(collector: momentumCollector)
    _ = momentumAdapter.post(inputEvent(sessionID: 4, order: 0, phase: .began, deltaX: 5, deltaY: 0))
    _ = momentumAdapter.post(inputEvent(sessionID: 4, order: 1, phase: .ended, continuation: .momentum, deltaX: 0, deltaY: 0))
    _ = momentumAdapter.post(momentumEvent(sessionID: 4, order: 2, phase: .began, deltaX: 3, deltaY: 0))
    let momentumCancellation = momentumAdapter.post(cancellationEvent(sessionID: 4, order: 3, reason: .inputLifecycle))
    expect(momentumCancellation.generatedEventCount == 1, "momentum active cancelはmomentum endedで閉じる: \(momentumCancellation)")
    expect(momentumCollector.events.last?.getIntegerValueField(rawField(123)) == 3, "cancel時のmomentum phaseを3にする")
    if let terminal = momentumCollector.events.last {
        assertPositiveZeroTerminal(terminal, label: "momentum cancel")
    }
}

private func testFailClosedPaths() {
    var modified = contractData()
    modified.append(0x0A)
    let mismatch = TrackpadGestureOutputAdapter(
        contractData: modified,
        systemIdentity: identity25F80()
    )
    expect(mismatch.capability.status == .contractMismatch, "fixture byte改変をcontract mismatchにする")
    expect(!mismatch.supports(.scroll), "改変fixtureではscrollを有効化しない")

    var modifiedModel = modelData()
    modifiedModel.append(0x0A)
    let modelMismatch = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        modelData: modifiedModel,
        systemIdentity: identity25F80()
    )
    expect(modelMismatch.capability.status == .contractMismatch, "output model byte改変をcontract mismatchにする")
    expect(!modelMismatch.supports(.scroll), "改変output modelではscrollを有効化しない")

    var postedAfterCreationFailure = 0
    let creationFailure = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        baseEventFactory: { nil },
        postEvent: { _ in
            postedAfterCreationFailure += 1
            return true
        }
    )
    let creationResult = creationFailure.post(
        inputEvent(sessionID: 10, order: 0, phase: .began, deltaX: 5, deltaY: 0)
    )
    expect(creationResult.failure == .eventCreationFailed, "3 event batchの一部作成失敗を明示する")
    expect(postedAfterCreationFailure == 0, "batch全件作成前には1件も投稿しない")

    var postAttempts = 0
    let postFailure = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        postEvent: { _ in
            postAttempts += 1
            return postAttempts != 2
        }
    )
    let postResult = postFailure.post(
        inputEvent(sessionID: 11, order: 0, phase: .began, deltaX: 5, deltaY: 0)
    )
    expect(postResult.failure == .eventPostFailed, "投稿失敗を成功扱いしない: \(postResult)")
    expect(postResult.generatedEventCount == 1, "投稿済みevent数を正確に返す: \(postResult)")

    let invalidCollector = EventCollector()
    let invalidSession = makeAdapter(collector: invalidCollector)
    let invalidResult = invalidSession.post(
        inputEvent(sessionID: 12, order: 0, phase: .changed, deltaX: 5, deltaY: 0)
    )
    expect(invalidResult.failure == .invalidSession, "beganなしchangedを拒否する")
    expect(invalidCollector.events.isEmpty, "不正sessionではeventを投稿しない")
}

private func testExplicitResourceOverridesFailClosed() {
    let missingPath = "/dev/null/nape-gesture-resource"
    let contract = TrackpadGestureOutputResources.loadContractData(
        environment: ["NAPE_GESTURE_TRACKPAD_CONTRACT": missingPath],
        currentDirectoryPath: FileManager.default.currentDirectoryPath
    )
    expect(contract == nil, "不正な明示contract pathからrepo fixtureへfallbackしない")
    expect(
        TrackpadGestureOutputResources.loadContractData(
            environment: ["NAPE_GESTURE_TRACKPAD_CONTRACT": ""]
        ) == nil,
        "空の明示contract pathからrepo fixtureへfallbackしない"
    )

    let model = TrackpadGestureOutputResources.loadModelData(
        environment: ["NAPE_GESTURE_TRACKPAD_OUTPUT_MODEL": missingPath],
        currentDirectoryPath: FileManager.default.currentDirectoryPath
    )
    expect(model == nil, "不正な明示model pathからrepo fixtureへfallbackしない")
    expect(
        TrackpadGestureOutputResources.loadModelData(
            environment: ["NAPE_GESTURE_TRACKPAD_OUTPUT_MODEL": ""]
        ) == nil,
        "空の明示model pathからrepo fixtureへfallbackしない"
    )

    expect(
        TrackpadGestureOutputResources.loadContractData(environment: [:]) == contractData(),
        "明示overrideがなければrepo contract fixtureを読み込む"
    )
    expect(
        TrackpadGestureOutputResources.loadModelData(environment: [:]) == modelData(),
        "明示overrideがなければrepo model fixtureを読み込む"
    )
}

private func testChangedCreationFailureRecovery() {
    let collector = EventCollector()
    var shouldCreateBaseEvent = true
    let adapter = makeAdapter(
        collector: collector,
        baseEventFactory: {
            shouldCreateBaseEvent ? CGEvent(source: nil) : nil
        }
    )

    let began = adapter.post(
        inputEvent(sessionID: 13, order: 0, phase: .began, deltaX: 8, deltaY: -6)
    )
    expect(began.failure == nil, "復旧テストのbeganを成功させる: \(began)")
    expect(began.generatedEventCount == 3, "復旧テストのbeganで3 eventを投稿する: \(began)")
    expect(collector.events.count == 3, "復旧テストのbegan投稿数を3件にする")

    shouldCreateBaseEvent = false
    let postCountBeforeFailure = collector.events.count
    let traceCountBeforeFailure = collector.postedTrace.count
    let changed = adapter.post(
        inputEvent(sessionID: 13, order: 1, phase: .changed, deltaX: 16, deltaY: -12)
    )
    expect(changed.failure == .eventCreationFailed, "changed batch作成失敗を明示する: \(changed)")
    expect(changed.generatedEventCount == 0, "changed batch作成失敗frameの生成済みevent数を0にする: \(changed)")
    expect(changed.failedEventCreationCount == 1, "changed batch作成失敗を1件記録する: \(changed)")
    expect(collector.events.count == postCountBeforeFailure, "changed batch作成失敗frameでは1件も投稿しない")
    expect(collector.postedTrace.count == traceCountBeforeFailure, "changed batch作成失敗frameではpost traceも増やさない")

    shouldCreateBaseEvent = true
    let cancellation = adapter.post(
        cancellationEvent(sessionID: 13, order: 1, reason: .outputFailure)
    )
    expect(cancellation.failure == nil, "factory復旧後のoutputFailure cancellationを成功させる: \(cancellation)")
    expect(cancellation.generatedEventCount == 3, "outputFailure cancellationで3 eventを投稿する: \(cancellation)")
    expect(collector.events.count == postCountBeforeFailure + 3, "失敗frameを飛ばしてcancellationの3 eventだけを追加する")
    assertInputCancellationBatch(Array(collector.events.suffix(3)), label: "adapter outputFailure cancellation")

    let repeatedCancellation = adapter.post(
        cancellationEvent(sessionID: 13, order: 2, reason: .outputFailure)
    )
    expect(repeatedCancellation.failure == .invalidSession, "cancellation後のadapter sessionを閉じる")
    expect(collector.events.count == postCountBeforeFailure + 3, "閉じたsessionへの再cancellationでは投稿しない")
}

private func testChangedValidationAndPostFailureRecovery() {
    let invalidCollector = EventCollector()
    let invalidAdapter = makeAdapter(collector: invalidCollector)
    _ = invalidAdapter.post(
        inputEvent(sessionID: 14, order: 0, phase: .began, deltaX: 8, deltaY: -6)
    )
    let invalidChanged = invalidAdapter.post(
        inputEvent(sessionID: 14, order: 2, phase: .changed, deltaX: 16, deltaY: -12)
    )
    expect(invalidChanged.failure == .invalidSession, "captureOrder不正changedを拒否する")
    let invalidCancellation = invalidAdapter.post(
        cancellationEvent(sessionID: 14, order: 1, reason: .outputFailure)
    )
    expect(invalidCancellation.failure == nil, "不正changed後も既存sessionをcancelできる")
    expect(invalidCancellation.generatedEventCount == 3, "不正changed後を3 event terminalで閉じる")
    assertInputCancellationBatch(
        Array(invalidCollector.events.suffix(3)),
        label: "invalid changed cancellation"
    )

    let postCollector = EventCollector()
    var failChangedSecondPost = false
    var changedPostAttempt = 0
    let postAdapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        traceContext: productTraceContext(),
        postEvent: { event in
            if failChangedSecondPost {
                changedPostAttempt += 1
                if changedPostAttempt == 2 {
                    return false
                }
            }
            postCollector.events.append(event)
            return true
        },
        postedEventObserver: { postCollector.postedTrace.append($0) }
    )
    _ = postAdapter.post(
        inputEvent(sessionID: 15, order: 0, phase: .began, deltaX: 8, deltaY: -6)
    )
    failChangedSecondPost = true
    let failedPost = postAdapter.post(
        inputEvent(sessionID: 15, order: 1, phase: .changed, deltaX: 16, deltaY: -12)
    )
    expect(failedPost.failure == .eventPostFailed, "changed途中の投稿失敗を明示する")
    expect(failedPost.generatedEventCount == 1, "changed途中までの成功投稿数を保持する")
    failChangedSecondPost = false
    let postCancellation = postAdapter.post(
        cancellationEvent(sessionID: 15, order: 1, reason: .outputFailure)
    )
    expect(postCancellation.failure == nil, "changed投稿失敗後も既存sessionをcancelできる")
    expect(postCancellation.generatedEventCount == 3, "changed投稿失敗後を3 event terminalで閉じる")
    assertInputCancellationBatch(
        Array(postCollector.events.suffix(3)),
        label: "changed post failure cancellation"
    )
}

private func testSessionCoordinatorProducesFixedTwoDimensionalScrollAndMomentum() {
    let collector = EventCollector()
    let adapter = makeAdapter(collector: collector)
    let coordinator = ProductGestureSessionCoordinator(output: adapter)
    expect(coordinator.unsupportedRequiredFamilies.isEmpty, "固定drag/scroll familyの起動前capability検査を通る")

    let began = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 20,
            deltaY: -40,
            velocityX: 200,
            velocityY: -400,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    let ended = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .ended,
            direction: nil,
            deltaX: 0,
            deltaY: 0,
            velocityX: 0,
            velocityY: -400,
            timestamp: MonotonicEventClock.nowSeconds
        ),
        continuation: .momentum
    )
    let momentumBegan = coordinator.post(
        command: GestureCommand(
            kind: .momentum,
            phase: .momentum,
            direction: nil,
            deltaX: 2,
            deltaY: -4,
            velocityX: 150,
            velocityY: -300,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    let momentumEnded = coordinator.post(
        command: GestureCommand(
            kind: .momentum,
            phase: .ended,
            direction: nil,
            deltaX: 0,
            deltaY: 0,
            velocityX: 0,
            velocityY: 0,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )

    expect([began.action, ended.action, momentumBegan.action, momentumEnded.action].allSatisfy { $0 == .smoothScroll }, "wheel由来momentumまでactive actionをsmoothScrollへ固定する")
    expect([began.result, ended.result, momentumBegan.result, momentumEnded.result].allSatisfy { $0.failure == nil }, "2D scroll lifecycleをsession coordinatorで完結する")
    guard collector.events.count == 8 else {
        failures.append("2D scroll coordinator lifecycleのevent数が8ではない: \(collector.events.count)")
        return
    }
    let inputScroll = collector.events[0]
    let inputCompanion = collector.events[2]
    let firstMomentum = collector.events[6]
    expect(inputScroll.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) != 0, "2D wheel inputのY point deltaを保持する")
    expect(inputScroll.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) != 0, "2D wheel inputのX point deltaを保持する")
    expect(inputCompanion.getDoubleValueField(rawField(113)) == 20, "2D companionのX motionを保持する")
    expect(inputCompanion.getDoubleValueField(rawField(119)) == -40, "2D companionのY motionを保持する")
    expect(firstMomentum.getIntegerValueField(rawField(123)) == 1, "最初のmomentum commandをbeganへ変換する")
    expect(firstMomentum.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) != 0, "momentumのY deltaを維持する")
    expect(firstMomentum.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) != 0, "momentumのX deltaを維持する")

    let fixedCoordinator = ProductGestureSessionCoordinator(output: makeAdapter(collector: EventCollector()))
    expect(fixedCoordinator.unsupportedRequiredFamilies.isEmpty, "固定出力の全familyを起動可能にする")
}

private func candidateInputEvent(
    sessionID: UInt64,
    order: UInt64,
    phase: TrackpadOutputInputPhase,
    payload: TrackpadOutputPayload
) -> TrackpadOutputSessionEvent {
    .input(
        TrackpadOutputInputFrame(
            sessionID: TrackpadOutputSessionID(rawValue: sessionID),
            captureOrder: order,
            timestamp: MonotonicEventClock.now,
            phase: phase,
            continuation: phase == .ended ? .complete : nil,
            terminalDecision: phase == .ended ? .commit : (phase == .cancelled ? .cancel : nil),
            payload: payload
        )
    )
}

private func testCandidateGestureFamilies() {
    let collector = EventCollector()
    let adapter = makeAdapter(collector: collector)
    let posts: [TrackpadOutputSessionEvent] = [
        candidateInputEvent(
            sessionID: 120,
            order: 0,
            phase: .began,
            payload: .dockSwipe(axis: .horizontal, progress: 0.1, velocity: 0.5)
        ),
        candidateInputEvent(
            sessionID: 120,
            order: 1,
            phase: .changed,
            payload: .dockSwipe(axis: .horizontal, progress: 0.6, velocity: 1.2)
        ),
        candidateInputEvent(
            sessionID: 120,
            order: 2,
            phase: .ended,
            payload: .dockSwipe(axis: .horizontal, progress: 0, velocity: 0)
        ),
        candidateInputEvent(
            sessionID: 121,
            order: 0,
            phase: .began,
            payload: .navigationSwipe(direction: .left, progress: -0.1, velocity: -0.5)
        ),
        candidateInputEvent(
            sessionID: 121,
            order: 1,
            phase: .changed,
            payload: .navigationSwipe(direction: .left, progress: -0.7, velocity: -1.4)
        ),
        candidateInputEvent(
            sessionID: 121,
            order: 2,
            phase: .ended,
            payload: .navigationSwipe(direction: .left, progress: 0, velocity: 0)
        ),
        candidateInputEvent(
            sessionID: 122,
            order: 0,
            phase: .began,
            payload: .magnification(progress: 0.1, scaleDelta: 0.03, velocity: 0.2)
        ),
        candidateInputEvent(
            sessionID: 122,
            order: 1,
            phase: .changed,
            payload: .magnification(progress: 0.5, scaleDelta: 0.08, velocity: 0.4)
        ),
        candidateInputEvent(
            sessionID: 122,
            order: 2,
            phase: .ended,
            payload: .magnification(progress: 0, scaleDelta: 0, velocity: 0)
        )
    ]
    let results = posts.map(adapter.post)
    expect(results.allSatisfy { $0.failure == nil && $0.generatedEventCount == 1 }, "3 candidate familyを各1 eventで投稿する")
    guard collector.events.count == 9 else {
        failures.append("candidate familyのevent数が9ではない: \(collector.events.count) results=\(results)")
        return
    }
    expect(collector.events.map { $0.type.rawValue } == [29, 29, 29, 30, 30, 30, 29, 29, 29], "candidate familyのevent typeを固定する")
    expect(collector.events.prefix(3).allSatisfy { $0.getIntegerValueField(rawField(110)) == 32 }, "DockSwipe classifierを32にする")
    expect(collector.events[3..<6].allSatisfy { $0.getIntegerValueField(rawField(110)) == 23 }, "NavigationSwipe classifierを23にする")
    expect(collector.events.suffix(3).allSatisfy { $0.getIntegerValueField(rawField(110)) == 8 }, "magnification classifierを8にする")
    expect(collector.events.map { $0.getIntegerValueField(rawField(132)) } == [1, 2, 4, 1, 2, 4, 1, 2, 4], "candidate lifecycle phaseをbegan/changed/endedにする")
    expect(collector.events[2].getIntegerValueField(rawField(143)) == 0, "DockSwipe terminal activeを0にする")
    expect(collector.events[4].getDoubleValueField(rawField(124)) < 0, "NavigationSwipe leftのprogressを負にする")
    expect(collector.events[7].getDoubleValueField(rawField(113)) > 0, "zoom-inのscale fieldを正にする")
    expect(collector.events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == NapeGestureGeneratedEventMarker.value }, "全candidate eventへ生成markerを付ける")
    expect(collector.events.allSatisfy { $0.getIntegerValueField(rawField(55)) == Int64($0.type.rawValue) }, "candidate eventのcontract type field 55を一致させる")
    expect(collector.events.allSatisfy { $0.getIntegerValueField(rawField(58)) == Int64($0.timestamp) }, "candidate eventのcontract timestamp field 58を一致させる")
    expect(Set(collector.postedTrace.map(\.family)) == [.dockSwipe, .navigationSwipe, .magnification], "traceへ3 familyを記録する")
}

private func testCoordinatorFixesDragAxisAndSessionAcrossDirectionReversal() {
    let capability = makeAdapter(collector: EventCollector()).capability
    let output = PermissiveProductOutput(capability: capability)
    let coordinator = ProductGestureSessionCoordinator(
        output: output,
        sessionSequence: TrackpadOutputSessionSequence(startingAt: 144)
    )
    let commands = [
        GestureCommand(
            mode: .spacesAndMissionControl,
            kind: .drag,
            phase: .began,
            direction: .right,
            deltaX: 60,
            deltaY: 10,
            velocityX: 600,
            velocityY: 100,
            timestamp: MonotonicEventClock.nowSeconds
        ),
        GestureCommand(
            mode: .spacesAndMissionControl,
            kind: .drag,
            phase: .changed,
            direction: .left,
            deltaX: -30,
            deltaY: 90,
            velocityX: -300,
            velocityY: 900,
            timestamp: MonotonicEventClock.nowSeconds
        ),
        GestureCommand(
            mode: .spacesAndMissionControl,
            kind: .drag,
            phase: .ended,
            direction: .left,
            deltaX: -5,
            deltaY: 120,
            velocityX: -50,
            velocityY: 1_200,
            timestamp: MonotonicEventClock.nowSeconds
        )
    ]
    let results = commands.map { coordinator.post(command: $0) }
    expect(results.allSatisfy { $0.action == .dockSwipe }, "drag actionをDockSwipeへ固定する")
    expect(results.allSatisfy { $0.result.failure == nil }, "方向反転を含むdrag sessionを完結する")

    let frames = output.postedEvents.compactMap { event -> TrackpadOutputInputFrame? in
        guard case let .input(frame) = event else { return nil }
        return frame
    }
    expect(frames.count == 3, "drag lifecycleを3 input frameとして投稿する")
    expect(Set(frames.map(\.sessionID)).count == 1, "方向反転後も同一session IDを維持する")
    expect(frames.first?.sessionID == TrackpadOutputSessionID(rawValue: 144), "指定sequenceのsession IDを使用する")
    expect(frames.map(\.captureOrder) == [0, 1, 2], "方向反転後もcapture orderを連続させる")
    expect(frames.allSatisfy { $0.payload.family == .dockSwipe }, "drag familyをDockSwipeへ固定する")
    let payloads = frames.compactMap { frame -> (TrackpadOutputAxis, Double)? in
        guard case let .dockSwipe(axis, progress, _) = frame.payload else { return nil }
        return (axis, progress)
    }
    expect(payloads.count == 3, "全drag frameをDockSwipe payloadにする")
    expect(payloads.allSatisfy { $0.0 == .horizontal }, "開始時の優勢軸をsession中固定する")
    expect(payloads.dropFirst().allSatisfy { $0.1 < 0 }, "方向反転後は固定軸上の負方向progressを保持する")
}

private func testCoordinatorRoutesButtonModesWithoutDirectionBindings() {
    let capability = makeAdapter(collector: EventCollector()).capability

    let scrollOutput = PermissiveProductOutput(capability: capability)
    let scrollCoordinator = ProductGestureSessionCoordinator(output: scrollOutput)
    let scrollPost = scrollCoordinator.post(
        command: GestureCommand(
            mode: .scrollAndNavigate,
            kind: .drag,
            phase: .began,
            direction: .right,
            deltaX: 12,
            deltaY: -8,
            velocityX: 120,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(scrollPost.action == .smoothScroll, "Scroll & Navigate modeをscroll familyへ接続する")
    let scrollFamily = scrollOutput.postedEvents.compactMap { event -> TrackpadOutputEventFamily? in
        guard case let .input(frame) = event else { return nil }
        return frame.payload.family
    }.first
    expect(scrollFamily == .scroll, "mouse moveの2次元deltaをscroll payloadへ渡す")

    let zoomOutput = PermissiveProductOutput(capability: capability)
    let zoomCoordinator = ProductGestureSessionCoordinator(output: zoomOutput)
    let zoomPost = zoomCoordinator.post(
        command: GestureCommand(
            mode: .zoom,
            kind: .drag,
            phase: .began,
            direction: .up,
            deltaX: 0,
            deltaY: -20,
            velocityX: 0,
            velocityY: -200,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(zoomPost.action == .magnification, "Zoom modeをmagnification familyへ接続する")
    let zoomFamily = zoomOutput.postedEvents.compactMap { event -> TrackpadOutputEventFamily? in
        guard case let .input(frame) = event else { return nil }
        return frame.payload.family
    }.first
    expect(zoomFamily == .magnification, "mouse moveをmagnification payloadへ渡す")
}

private func testCoordinatorChangedCreationFailureRecovery() {
    let collector = EventCollector()
    var shouldCreateBaseEvent = true
    let adapter = makeAdapter(
        collector: collector,
        baseEventFactory: {
            shouldCreateBaseEvent ? CGEvent(source: nil) : nil
        }
    )
    let coordinator = ProductGestureSessionCoordinator(output: adapter)

    let began = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 4,
            deltaY: -8,
            velocityX: 40,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(began.result.failure == nil, "coordinator復旧テストのbeganを成功させる: \(began.result)")
    expect(began.result.generatedEventCount == 3, "coordinator復旧テストのbeganで3 eventを投稿する")

    shouldCreateBaseEvent = false
    let postCountBeforeFailure = collector.events.count
    let changed = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .changed,
            direction: nil,
            deltaX: 8,
            deltaY: -16,
            velocityX: 80,
            velocityY: -160,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(changed.result.failure == .eventCreationFailed, "coordinator経由のchanged batch作成失敗を明示する: \(changed.result)")
    expect(changed.result.generatedEventCount == 0, "coordinator経由の失敗frameでは生成済みevent数を0にする")
    expect(collector.events.count == postCountBeforeFailure, "coordinator経由の失敗frameでは1件も投稿しない")

    shouldCreateBaseEvent = true
    let cancellation = coordinator.cancelActive(
        reason: .outputFailure,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "coordinatorが保持したsessionをoutputFailure cancellationで閉じる: \(cancellation)")
    expect(cancellation.generatedEventCount == 3, "coordinatorのoutputFailure cancellationで3 eventを投稿する")
    expect(collector.events.count == postCountBeforeFailure + 3, "coordinator復旧時はcancellationの3 eventだけを追加する")
    assertInputCancellationBatch(Array(collector.events.suffix(3)), label: "coordinator outputFailure cancellation")

    let repeatedCancellation = coordinator.cancelActive(
        reason: .outputFailure,
        at: MonotonicEventClock.nowSeconds
    )
    expect(repeatedCancellation.failure == nil, "閉じたcoordinator sessionの再cancellationを失敗扱いしない")
    expect(repeatedCancellation.generatedEventCount == 0, "閉じたcoordinator sessionの再cancellationでは投稿しない")
}

private func testCoordinatorPreservesActiveActionAcrossChangedCommandKind() {
    let output = PermissiveProductOutput(
        capability: makeAdapter(collector: EventCollector()).capability
    )
    let coordinator = ProductGestureSessionCoordinator(output: output)
    let began = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(began.result.failure == nil, "action不一致復旧テストのbeganを成功させる")

    let changed = coordinator.post(
        command: GestureCommand(
            kind: .drag,
            phase: .changed,
            direction: .up,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(changed.action == .smoothScroll, "後続command kindにかかわらず開始時actionを維持する")
    expect(changed.result.failure == nil, "開始時actionでchangedを継続する")
    guard output.postedEvents.count == 2,
          case let .input(beganFrame) = output.postedEvents[0],
          case let .input(changedFrame) = output.postedEvents[1]
    else {
        failures.append("active action継続検査のinput frameが2件ではない")
        return
    }
    expect(changedFrame.sessionID == beganFrame.sessionID, "command kind変更後も同一session IDを維持する")
    expect(changedFrame.captureOrder == 1, "command kind変更後もcapture orderを連続させる")
    expect(changedFrame.payload.family == .scroll, "開始時のscroll familyを維持する")

    let cancellation = coordinator.cancelActive(
        reason: .inputLifecycle,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "action継続後もactive sessionをcancelできる")
    expect(cancellation.generatedEventCount == 1, "permissive outputへcancellationを1 frame渡す")
}

private func testCoordinatorInvalidPhasePreservesCancellation() {
    let collector = EventCollector()
    let coordinator = ProductGestureSessionCoordinator(output: makeAdapter(collector: collector))
    _ = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    let invalid = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .momentum,
            direction: nil,
            deltaX: 0,
            deltaY: -4,
            velocityX: 0,
            velocityY: -40,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(invalid.result.failure == .invalidSession, "input commandのmomentum phaseを拒否する")
    let cancellation = coordinator.cancelActive(
        reason: .inputLifecycle,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "不正phase後もactive sessionをcancelできる")
    expect(cancellation.generatedEventCount == 3, "不正phase後を3 event terminalで閉じる")
    assertInputCancellationBatch(
        Array(collector.events.suffix(3)),
        label: "coordinator invalid phase cancellation"
    )
}

private func testCoordinatorValidatesTransitionBeforeOutput() {
    let capabilitySource = makeAdapter(collector: EventCollector())
    let output = PermissiveProductOutput(capability: capabilitySource.capability)
    let coordinator = ProductGestureSessionCoordinator(output: output)
    let now = MonotonicEventClock.nowSeconds
    _ = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: now
        )
    )
    _ = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .ended,
            direction: nil,
            deltaX: 0,
            deltaY: 0,
            velocityX: 0,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        ),
        continuation: .momentum
    )
    expect(output.postedEvents.count == 2, "検査前提のinput lifecycleをoutputへ渡す")

    let invalid = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .changed,
            direction: nil,
            deltaX: 0,
            deltaY: -4,
            velocityX: 0,
            velocityY: -40,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(invalid.result.failure == .invalidSession, "awaiting momentum中のinput changedを拒否する")
    expect(output.postedEvents.count == 2, "不正遷移をoutputへ渡す前に拒否する")

    let cancellation = coordinator.cancelActive(
        reason: .inputLifecycle,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "投稿前拒否後もactive sessionをcancelできる")
}

private func testCoordinatorRetriesFailedCancellation() {
    let collector = EventCollector()
    var shouldCreateBaseEvent = true
    let coordinator = ProductGestureSessionCoordinator(
        output: makeAdapter(
            collector: collector,
            baseEventFactory: {
                shouldCreateBaseEvent ? CGEvent(source: nil) : nil
            }
        )
    )
    _ = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )

    let invalidTimestamp = coordinator.cancelActive(reason: .outputFailure, at: .nan)
    expect(invalidTimestamp.failure == .invalidSession, "不正timestampのcancelを拒否する")

    shouldCreateBaseEvent = false
    let failedCancellation = coordinator.cancelActive(
        reason: .outputFailure,
        at: MonotonicEventClock.nowSeconds
    )
    expect(failedCancellation.failure == .eventCreationFailed, "cancel batch作成失敗を明示する")
    expect(failedCancellation.generatedEventCount == 0, "cancel batch作成失敗時は投稿しない")

    shouldCreateBaseEvent = true
    let retry = coordinator.cancelActive(
        reason: .outputFailure,
        at: MonotonicEventClock.nowSeconds
    )
    expect(retry.failure == nil, "失敗したcancelを同じactive sessionへ再試行できる")
    expect(retry.generatedEventCount == 3, "再試行cancelを3 event terminalで閉じる")
    assertInputCancellationBatch(
        Array(collector.events.suffix(3)),
        label: "coordinator retried cancellation"
    )
}

private func testPartialBeganAndChangedCanBeCancelled() {
    for failureAttempt in [2, 3] {
        let beganCollector = EventCollector()
        let beganSink = InjectedPostSink(collector: beganCollector)
        beganSink.configure(failureAttempt: failureAttempt)
        let beganAdapter = makeInjectedAdapter(
            sink: beganSink,
            traceCollector: beganCollector
        )
        let began = beganAdapter.post(
            inputEvent(
                sessionID: UInt64(100 + failureAttempt),
                order: 0,
                phase: .began,
                deltaX: 7,
                deltaY: -5
            )
        )
        expect(began.failure == .eventPostFailed, "beganの\(failureAttempt)件目post失敗を明示する")
        expect(
            began.generatedEventCount == failureAttempt - 1,
            "beganの\(failureAttempt)件目までの成功数を保持する: \(began)"
        )
        beganSink.configure(failureAttempt: nil)
        let beganCancellation = beganAdapter.post(
            cancellationEvent(
                sessionID: UInt64(100 + failureAttempt),
                order: 0,
                reason: .outputFailure
            )
        )
        expect(beganCancellation.failure == nil, "途中beganをcancelで閉じる: \(beganCancellation)")
        expect(beganCancellation.generatedEventCount == 3, "途中beganへ補償terminal 3件を投稿する")
        assertInputCancellationBatch(
            Array(beganCollector.events.suffix(3)),
            label: "partial began \(failureAttempt) cancellation"
        )
        expect(
            beganCollector.postedTrace.map(\.postIndex)
                == Array(0..<UInt64(beganCollector.postedTrace.count)),
            "途中beganからcancelへ切り替えてもpostIndexを欠番にしない"
        )
        let beganEventCount = beganCollector.events.count
        let repeatedBeganCancellation = beganAdapter.post(
            cancellationEvent(
                sessionID: UInt64(100 + failureAttempt),
                order: 1,
                reason: .outputFailure
            )
        )
        expect(repeatedBeganCancellation.failure == .invalidSession, "途中began cancel後のsessionを閉じる")
        expect(beganCollector.events.count == beganEventCount, "閉じたbegan sessionのterminalを重複させない")

        let changedCollector = EventCollector()
        let changedSink = InjectedPostSink(collector: changedCollector)
        changedSink.configure(failureAttempt: nil)
        let changedAdapter = makeInjectedAdapter(
            sink: changedSink,
            traceCollector: changedCollector
        )
        let sessionID = UInt64(110 + failureAttempt)
        _ = changedAdapter.post(
            inputEvent(
                sessionID: sessionID,
                order: 0,
                phase: .began,
                deltaX: 7,
                deltaY: -5
            )
        )
        changedSink.configure(failureAttempt: failureAttempt)
        let changed = changedAdapter.post(
            inputEvent(
                sessionID: sessionID,
                order: 1,
                phase: .changed,
                deltaX: 14,
                deltaY: -10
            )
        )
        expect(changed.failure == .eventPostFailed, "changedの\(failureAttempt)件目post失敗を明示する")
        expect(
            changed.generatedEventCount == failureAttempt - 1,
            "changedの\(failureAttempt)件目までの成功数を保持する: \(changed)"
        )
        changedSink.configure(failureAttempt: nil)
        let changedCancellation = changedAdapter.post(
            cancellationEvent(sessionID: sessionID, order: 1, reason: .outputFailure)
        )
        expect(changedCancellation.failure == nil, "途中changedをcancelで閉じる: \(changedCancellation)")
        expect(changedCancellation.generatedEventCount == 3, "途中changedへ補償terminal 3件を投稿する")
        assertInputCancellationBatch(
            Array(changedCollector.events.suffix(3)),
            label: "partial changed \(failureAttempt) cancellation"
        )
        expect(
            changedCollector.postedTrace.map(\.postIndex)
                == Array(0..<UInt64(changedCollector.postedTrace.count)),
            "途中changedからcancelへ切り替えてもpostIndexを欠番にしない"
        )
    }
}

private func testPartialTerminalRetriesWithoutDuplicates() {
    for failureAttempt in [2, 3] {
        let collector = EventCollector()
        let sink = InjectedPostSink(collector: collector)
        sink.configure(failureAttempt: nil)
        let adapter = makeInjectedAdapter(sink: sink)
        let sessionID = UInt64(120 + failureAttempt)
        _ = adapter.post(
            inputEvent(
                sessionID: sessionID,
                order: 0,
                phase: .began,
                deltaX: 9,
                deltaY: -6
            )
        )

        sink.configure(failureAttempt: failureAttempt)
        let firstCancellation = adapter.post(
            cancellationEvent(sessionID: sessionID, order: 1, reason: .outputFailure)
        )
        expect(firstCancellation.failure == .eventPostFailed, "terminalの\(failureAttempt)件目post失敗を明示する")
        expect(
            firstCancellation.generatedEventCount == failureAttempt - 1,
            "terminal失敗前の成功数を保持する: \(firstCancellation)"
        )

        sink.configure(failureAttempt: nil)
        let retry = adapter.post(
            cancellationEvent(sessionID: sessionID, order: 1, reason: .outputFailure)
        )
        expect(retry.failure == nil, "terminalの\(failureAttempt)件目から再開する: \(retry)")
        expect(
            retry.generatedEventCount == 4 - failureAttempt,
            "terminal再試行で未投稿分だけ投稿する: \(retry)"
        )
        let terminalEvents = Array(collector.events.dropFirst(3))
        assertInputCancellationBatch(
            terminalEvents,
            label: "retried terminal \(failureAttempt)"
        )
        expect(
            terminalEvents.count == 3,
            "terminal再試行で投稿済みeventを重複させない: \(terminalEvents.count)"
        )
    }
}

private func testPartialBatchBlocksOtherSessionUntilResolved() {
    let collector = EventCollector()
    let sink = InjectedPostSink(collector: collector)
    sink.configure(failureAttempt: 2)
    let adapter = makeInjectedAdapter(sink: sink, traceCollector: collector)

    let firstEvent = inputEvent(
        sessionID: 150,
        order: 0,
        phase: .began,
        deltaX: 8,
        deltaY: -5
    )
    let partial = adapter.post(firstEvent)
    expect(partial.failure == .eventPostFailed, "部分投稿失敗を検査前提として生成する")
    expect(partial.generatedEventCount == 1, "部分投稿失敗前の1件だけを記録する")

    sink.configure(failureAttempt: nil)
    let otherSession = adapter.post(
        inputEvent(sessionID: 151, order: 0, phase: .began, deltaX: 4, deltaY: -3)
    )
    expect(otherSession.failure == .invalidSession, "未完了batch中は別sessionを拒否する")
    expect(collector.events.count == 1, "別session拒否でeventを追加しない")

    let retry = adapter.post(firstEvent)
    expect(retry.failure == nil, "未完了batchを同一eventで再開する")
    expect(retry.generatedEventCount == 2, "未投稿の2件だけを再送する")
    expect(
        collector.postedTrace.map(\.postIndex) == [0, 1, 2],
        "部分投稿と再送のpostIndexを実投稿順で連続させる"
    )

    let cancellation = adapter.post(
        cancellationEvent(sessionID: 150, order: 1, reason: .outputFailure)
    )
    expect(cancellation.failure == nil, "再送完了後の旧sessionを閉じる")
    let nextSession = adapter.post(
        inputEvent(sessionID: 151, order: 0, phase: .began, deltaX: 4, deltaY: -3)
    )
    expect(nextSession.failure == nil, "未完了batch解消後は別sessionを開始できる")
    expect(
        collector.postedTrace.map(\.postIndex) == Array(0..<UInt64(collector.postedTrace.count)),
        "session切替後もpostIndexを実投稿順で連続させる"
    )
}

private func testExternalClosureReentryIsRejected() {
    let postCollector = EventCollector()
    var postAdapter: TrackpadGestureOutputAdapter!
    var postReentryResult: ProductGestureOutputResult?
    var didReenterPost = false
    postAdapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        postEvent: { event in
            if !didReenterPost {
                didReenterPost = true
                postReentryResult = postAdapter.post(
                    inputEvent(
                        sessionID: 131,
                        order: 0,
                        phase: .began,
                        deltaX: 1,
                        deltaY: -1
                    )
                )
            }
            postCollector.events.append(event)
            return true
        }
    )
    let outerPost = postAdapter.post(
        inputEvent(
            sessionID: 130,
            order: 0,
            phase: .began,
            deltaX: 5,
            deltaY: -3
        )
    )
    expect(outerPost.failure == nil, "postEventからの再入拒否後も外側batchを完了する")
    expect(postReentryResult?.failure == .invalidSession, "postEventからの再入を明示拒否する")
    expect(postCollector.events.count == 3, "postEvent再入で別sessionを投稿しない")

    let observerCollector = EventCollector()
    var observerAdapter: TrackpadGestureOutputAdapter!
    var observerReentryResult: ProductGestureOutputResult?
    var didReenterObserver = false
    observerAdapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        traceContext: productTraceContext(),
        postEvent: { event in
            observerCollector.events.append(event)
            return true
        },
        postedEventObserver: { trace in
            observerCollector.postedTrace.append(trace)
            if !didReenterObserver {
                didReenterObserver = true
                observerReentryResult = observerAdapter.post(
                    inputEvent(
                        sessionID: 133,
                        order: 0,
                        phase: .began,
                        deltaX: 1,
                        deltaY: -1
                    )
                )
            }
        }
    )
    let outerObserver = observerAdapter.post(
        inputEvent(
            sessionID: 132,
            order: 0,
            phase: .began,
            deltaX: 5,
            deltaY: -3
        )
    )
    expect(outerObserver.failure == nil, "observerからの再入拒否後も外側batchを完了する")
    expect(observerReentryResult?.failure == .invalidSession, "observerからの再入を明示拒否する")
    expect(observerCollector.events.count == 3, "observer再入で別sessionを投稿しない")
    expect(observerCollector.postedTrace.count == 3, "observer再入後も外側traceを全件記録する")
}

private func testReentrantResetAbortsWithoutLosingPartialSession() {
    let postCollector = EventCollector()
    var postAdapter: TrackpadGestureOutputAdapter!
    var didResetFromPost = false
    postAdapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        postEvent: { event in
            postCollector.events.append(event)
            if !didResetFromPost {
                didResetFromPost = true
                postAdapter.reset()
            }
            return true
        }
    )
    let postResult = postAdapter.post(
        inputEvent(sessionID: 134, order: 0, phase: .began, deltaX: 5, deltaY: -3)
    )
    expect(postResult.failure == .eventPostFailed, "postEvent中のresetで外側batchを成功扱いしない")
    expect(postResult.generatedEventCount == 1, "postEvent中のresetまでに投稿した1件を保持する")
    let postCancellation = postAdapter.post(
        cancellationEvent(sessionID: 134, order: 0, reason: .outputFailure)
    )
    expect(postCancellation.failure == nil, "postEvent中reset後も部分sessionをcancelできる")
    expect(postCancellation.generatedEventCount == 3, "postEvent中reset後をterminal 3件で閉じる")

    let observerCollector = EventCollector()
    var observerAdapter: TrackpadGestureOutputAdapter!
    var didResetFromObserver = false
    observerAdapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        traceContext: productTraceContext(),
        postEvent: { event in
            observerCollector.events.append(event)
            return true
        },
        postedEventObserver: { trace in
            observerCollector.postedTrace.append(trace)
            if !didResetFromObserver {
                didResetFromObserver = true
                observerAdapter.reset()
            }
        }
    )
    let observerResult = observerAdapter.post(
        inputEvent(sessionID: 135, order: 0, phase: .began, deltaX: 5, deltaY: -3)
    )
    expect(observerResult.failure == .eventPostFailed, "observer中のresetで外側batchを成功扱いしない")
    expect(observerResult.generatedEventCount == 1, "observer中のresetまでの投稿数を保持する")
    let observerCancellation = observerAdapter.post(
        cancellationEvent(sessionID: 135, order: 0, reason: .outputFailure)
    )
    expect(observerCancellation.failure == nil, "observer中reset後も部分sessionをcancelできる")
    expect(
        observerCollector.postedTrace.map(\.postIndex)
            == Array(0..<UInt64(observerCollector.postedTrace.count)),
        "observer中reset後のcancelまでtrace indexを連続させる"
    )
}

private func testPartialBatchRejectsRegressiveCancellationTimestamp() {
    let collector = EventCollector()
    let sink = InjectedPostSink(collector: collector)
    sink.configure(failureAttempt: nil)
    let adapter = makeInjectedAdapter(sink: sink)
    let sessionID: UInt64 = 136
    _ = adapter.post(
        inputEvent(sessionID: sessionID, order: 0, phase: .began, deltaX: 5, deltaY: -3)
    )
    let cancellationTimestamp = MonotonicEventClock.now
    Thread.sleep(forTimeInterval: 0.001)
    sink.configure(failureAttempt: 2)
    let partial = adapter.post(
        inputEvent(sessionID: sessionID, order: 1, phase: .changed, deltaX: 8, deltaY: -5)
    )
    expect(partial.failure == .eventPostFailed, "timestamp検査用changedを部分投稿状態にする")

    sink.configure(failureAttempt: nil)
    let regressive = adapter.post(
        cancellationEvent(
            sessionID: sessionID,
            order: 1,
            reason: .outputFailure,
            timestamp: cancellationTimestamp
        )
    )
    expect(regressive.failure == .invalidSession, "部分投稿済みsourceより古いcancel timestampを拒否する")
    let valid = adapter.post(
        cancellationEvent(sessionID: sessionID, order: 1, reason: .outputFailure)
    )
    expect(valid.failure == nil, "timestamp拒否後も新しいcancelで部分sessionを閉じる")
}

private func testRejectedBeganDoesNotResetAnotherCoordinatorSession() {
    let collector = EventCollector()
    let sink = InjectedPostSink(collector: collector)
    sink.configure(failureAttempt: 2)
    let sharedAdapter = makeInjectedAdapter(sink: sink)
    let first = ProductGestureSessionCoordinator(
        output: sharedAdapter,
        sessionSequence: TrackpadOutputSessionSequence(startingAt: 160)
    )
    let second = ProductGestureSessionCoordinator(
        output: sharedAdapter,
        sessionSequence: TrackpadOutputSessionSequence(startingAt: 161)
    )
    let firstBegan = first.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(firstBegan.result.failure == .eventPostFailed, "共有adapterの先行sessionを部分投稿状態にする")

    sink.configure(failureAttempt: nil)
    let rejected = second.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -4,
            velocityX: 0,
            velocityY: -40,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(rejected.result.failure == .invalidSession, "未完了batch中の別coordinator beganを拒否する")
    let cancellation = first.cancelActive(
        reason: .outputFailure,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "別coordinator拒否後も先行sessionをcancelできる")
    expect(cancellation.generatedEventCount == 3, "先行部分sessionをterminal 3件で閉じる")
}

private func testTraceContextAndPostIndexFailClosed() {
    var missingContextPostAttempts = 0
    var missingContextObserved = false
    let missingContextAdapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        postEvent: { _ in
            missingContextPostAttempts += 1
            return true
        },
        postedEventObserver: { _ in missingContextObserved = true }
    )
    let missingContext = missingContextAdapter.post(
        inputEvent(
            sessionID: 140,
            order: 0,
            phase: .began,
            deltaX: 4,
            deltaY: -2
        )
    )
    expect(missingContext.failure == .eventCreationFailed, "observer context欠落をfail closedにする")
    expect(missingContext.failedEventCreationCount == 1, "observer context欠落を生成失敗1件とする")
    expect(missingContextPostAttempts == 0, "observer context欠落時はpostEventを呼ばない")
    expect(!missingContextObserved, "observer context欠落時はobserverを呼ばない")

    var overflowPostAttempts = 0
    let overflowAdapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        systemIdentity: identity25F80(),
        postEvent: { _ in
            overflowPostAttempts += 1
            return true
        },
        initialPostIndex: UInt64.max - 1
    )
    let overflowEvent = inputEvent(
        sessionID: 141,
        order: 0,
        phase: .began,
        deltaX: 4,
        deltaY: -2
    )
    let overflow = overflowAdapter.post(overflowEvent)
    expect(overflow.failure == .eventPostFailed, "batch前のpostIndex overflowを明示する")
    expect(overflow.generatedEventCount == 0, "postIndex overflow時は無投稿にする")
    expect(overflowPostAttempts == 0, "postIndex overflow時はpostEventを呼ばない")
    let overflowRetry = overflowAdapter.post(overflowEvent)
    expect(overflowRetry.failure == .eventPostFailed, "overflow後もsessionとindexを未変更のままにする")
    expect(overflowPostAttempts == 0, "overflow再試行でも無投稿を保つ")
    let changedAfterOverflow = overflowAdapter.post(
        inputEvent(
            sessionID: 141,
            order: 0,
            phase: .changed,
            deltaX: 4,
            deltaY: -2
        )
    )
    expect(changedAfterOverflow.failure == .invalidSession, "overflowしたbeganでsessionを開始しない")
}

private func testOddSymmetricQuantizationOnBothAxes() {
    let positiveCollector = EventCollector()
    let negativeCollector = EventCollector()
    let positive = makeAdapter(collector: positiveCollector).post(
        inputEvent(
            sessionID: 150,
            order: 0,
            phase: .began,
            deltaX: 12.345_678,
            deltaY: 7.891_234
        )
    )
    let negative = makeAdapter(collector: negativeCollector).post(
        inputEvent(
            sessionID: 151,
            order: 0,
            phase: .began,
            deltaX: -12.345_678,
            deltaY: -7.891_234
        )
    )
    expect(positive.failure == nil && negative.failure == nil, "odd対称検査の正負batchを投稿する")
    guard positiveCollector.events.count == 3, negativeCollector.events.count == 3 else {
        failures.append("odd対称検査のevent数が3件ではない")
        return
    }

    let positiveScroll = positiveCollector.events[0]
    let negativeScroll = negativeCollector.events[0]
    let axes: [(String, CGEventField, CGEventField, CGEventField)] = [
        (
            "Y",
            .scrollWheelEventDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis1,
            .scrollWheelEventPointDeltaAxis1
        ),
        (
            "X",
            .scrollWheelEventDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis2,
            .scrollWheelEventPointDeltaAxis2
        )
    ]
    for (label, lineField, fixedField, pointField) in axes {
        let positiveLine = positiveScroll.getIntegerValueField(lineField)
        let negativeLine = negativeScroll.getIntegerValueField(lineField)
        expect(negativeLine == -positiveLine, "\(label)軸line量子化をodd対称にする")

        let positiveFixed = positiveScroll.getDoubleValueField(fixedField)
        let negativeFixed = negativeScroll.getDoubleValueField(fixedField)
        expect(
            negativeFixed.bitPattern == (-positiveFixed).bitPattern,
            "\(label)軸fixed-point量子化をbit単位でodd対称にする"
        )

        let positivePoint = positiveScroll.getDoubleValueField(pointField)
        let negativePoint = negativeScroll.getDoubleValueField(pointField)
        expect(
            negativePoint.bitPattern == (-positivePoint).bitPattern,
            "\(label)軸point量子化をbit単位でodd対称にする"
        )
    }

    let positiveCompanion = positiveCollector.events[2]
    let negativeCompanion = negativeCollector.events[2]
    for (label, fields) in [("X", [113, 114, 116, 118]), ("Y", [119, 139])] {
        expect(
            fields.allSatisfy {
                let value = positiveCompanion.getDoubleValueField(rawField($0))
                let opposite = negativeCompanion.getDoubleValueField(rawField($0))
                return opposite.bitPattern == (-value).bitPattern
            },
            "\(label)軸gesture double aliasをbit単位でodd対称にする"
        )
    }
    for (label, fields) in [("X", [115, 117, 164]), ("Y", [123, 165])] {
        expect(
            fields.allSatisfy {
                let value = UInt32(
                    truncatingIfNeeded: positiveCompanion.getIntegerValueField(rawField($0))
                )
                let opposite = UInt32(
                    truncatingIfNeeded: negativeCompanion.getIntegerValueField(rawField($0))
                )
                return opposite == value ^ 0x8000_0000
            },
            "\(label)軸gesture Float aliasをbit単位でodd対称にする"
        )
    }
}

private func testActiveSessionRejectsEveryNewBegan() {
    let collector = EventCollector()
    let coordinator = ProductGestureSessionCoordinator(output: makeAdapter(collector: collector))
    let beganAt = MonotonicEventClock.nowSeconds
    let began = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: beganAt
        )
    )
    expect(began.result.failure == nil, "active began拒否検査の旧sessionを開始する")
    let eventCountBeforeRejection = collector.events.count

    let noneBegan = coordinator.post(
        command: GestureCommand(
            kind: .drag,
            phase: .began,
            direction: .up,
            deltaX: 0,
            deltaY: -4,
            velocityX: 0,
            velocityY: -40,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(noneBegan.action == .smoothScroll, "active中の新規beganでも既存actionを返す")
    expect(noneBegan.result.failure == .invalidSession, "active中の別kind beganを成功扱いしない")

    let mappedBegan = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -4,
            velocityX: 0,
            velocityY: -40,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(mappedBegan.result.failure == .invalidSession, "active中の通常beganも拒否する")
    expect(collector.events.count == eventCountBeforeRejection, "active中のbegan拒否でeventを投稿しない")

    let cancellation = coordinator.cancelActive(
        reason: .inputLifecycle,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "began拒否後も旧sessionをcancelできる")
    assertInputCancellationBatch(
        Array(collector.events.suffix(3)),
        label: "active began rejection cancellation"
    )
}

private func testCancellationTimestampRegressionIsNormalized() {
    let collector = EventCollector()
    let coordinator = ProductGestureSessionCoordinator(output: makeAdapter(collector: collector))
    let beganAt = MonotonicEventClock.nowSeconds
    let began = coordinator.post(
        command: GestureCommand(
            kind: .wheel,
            phase: .began,
            direction: nil,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: beganAt
        )
    )
    expect(began.result.failure == nil, "timestamp逆行検査のsessionを開始する")
    guard let beganTimestamp = collector.events.first?.timestamp else {
        failures.append("timestamp逆行検査のbegan eventがありません")
        return
    }

    let cancellation = coordinator.cancelActive(
        reason: .outputFailure,
        at: max(0, beganAt - 1)
    )
    expect(cancellation.failure == nil, "逆行cancel timestampをlast timestamp以上へ正規化する: \(cancellation)")
    expect(cancellation.generatedEventCount == 3, "正規化したcancelでterminal 3件を投稿する")
    expect(
        collector.events.suffix(3).allSatisfy { $0.timestamp >= beganTimestamp },
        "cancel terminal timestampを旧sessionのlast timestamp以上にする"
    )
}

private func testCoordinatorClosesPartialBeganAndRetriesPartialCancellation() {
    for failureAttempt in [2, 3] {
        let beganCollector = EventCollector()
        let beganSink = InjectedPostSink(collector: beganCollector)
        beganSink.configure(failureAttempt: failureAttempt)
        let beganCoordinator = ProductGestureSessionCoordinator(output: makeInjectedAdapter(sink: beganSink))
        let beganAt = MonotonicEventClock.nowSeconds
        let partialBegan = beganCoordinator.post(
            command: GestureCommand(
                kind: .wheel,
                phase: .began,
                direction: nil,
                deltaX: 0,
                deltaY: -8,
                velocityX: 0,
                velocityY: -80,
                timestamp: beganAt
            )
        )
        expect(partialBegan.result.failure == .eventPostFailed, "coordinator beganの\(failureAttempt)件目失敗を明示する")
        expect(
            partialBegan.result.generatedEventCount == failureAttempt - 1,
            "coordinatorが途中beganの投稿数を保持する"
        )
        beganSink.configure(failureAttempt: nil)
        let beganCancellation = beganCoordinator.cancelActive(
            reason: .outputFailure,
            at: max(0, beganAt - 1)
        )
        expect(beganCancellation.failure == nil, "coordinatorが途中beganをcancelで閉じる")
        expect(beganCancellation.generatedEventCount == 3, "coordinatorの途中began cancelを3件で閉じる")
        assertInputCancellationBatch(
            Array(beganCollector.events.suffix(3)),
            label: "coordinator partial began \(failureAttempt) cancellation"
        )

        let terminalCollector = EventCollector()
        let terminalSink = InjectedPostSink(collector: terminalCollector)
        terminalSink.configure(failureAttempt: nil)
        let terminalCoordinator = ProductGestureSessionCoordinator(output: makeInjectedAdapter(sink: terminalSink))
        let terminalBeganAt = MonotonicEventClock.nowSeconds
        _ = terminalCoordinator.post(
            command: GestureCommand(
                kind: .wheel,
                phase: .began,
                direction: nil,
                deltaX: 0,
                deltaY: -8,
                velocityX: 0,
                velocityY: -80,
                timestamp: terminalBeganAt
            )
        )
        terminalSink.configure(failureAttempt: failureAttempt)
        let partialCancellation = terminalCoordinator.cancelActive(
            reason: .outputFailure,
            at: MonotonicEventClock.nowSeconds
        )
        expect(partialCancellation.failure == .eventPostFailed, "coordinator terminalの\(failureAttempt)件目失敗を明示する")
        expect(
            partialCancellation.generatedEventCount == failureAttempt - 1,
            "coordinatorが途中terminalの投稿数を保持する"
        )
        terminalSink.configure(failureAttempt: nil)
        let retriedCancellation = terminalCoordinator.cancelActive(
            reason: .outputFailure,
            at: max(0, terminalBeganAt - 1)
        )
        expect(retriedCancellation.failure == nil, "coordinatorがterminalの未投稿offsetから再開する")
        expect(
            retriedCancellation.generatedEventCount == 4 - failureAttempt,
            "coordinator terminal再試行で未投稿分だけ投稿する"
        )
        let terminalEvents = Array(terminalCollector.events.dropFirst(3))
        assertInputCancellationBatch(
            terminalEvents,
            label: "coordinator retried terminal \(failureAttempt)"
        )
        expect(terminalEvents.count == 3, "coordinatorのterminal再試行を3件に固定する")
        let afterClosed = terminalCoordinator.cancelActive(
            reason: .outputFailure,
            at: MonotonicEventClock.nowSeconds
        )
        expect(afterClosed.failure == nil && afterClosed.generatedEventCount == 0, "再試行成功後のcoordinator sessionを閉じる")
    }
}

testLifecycleAndFields()
testCancellationStates()
testFailClosedPaths()
testExplicitResourceOverridesFailClosed()
testChangedCreationFailureRecovery()
testChangedValidationAndPostFailureRecovery()
testSessionCoordinatorProducesFixedTwoDimensionalScrollAndMomentum()
testCandidateGestureFamilies()
testCoordinatorFixesDragAxisAndSessionAcrossDirectionReversal()
testCoordinatorRoutesButtonModesWithoutDirectionBindings()
testCoordinatorChangedCreationFailureRecovery()
testCoordinatorPreservesActiveActionAcrossChangedCommandKind()
testCoordinatorInvalidPhasePreservesCancellation()
testCoordinatorValidatesTransitionBeforeOutput()
testCoordinatorRetriesFailedCancellation()
testPartialBeganAndChangedCanBeCancelled()
testPartialTerminalRetriesWithoutDuplicates()
testPartialBatchBlocksOtherSessionUntilResolved()
testExternalClosureReentryIsRejected()
testReentrantResetAbortsWithoutLosingPartialSession()
testPartialBatchRejectsRegressiveCancellationTimestamp()
testRejectedBeganDoesNotResetAnotherCoordinatorSession()
testTraceContextAndPostIndexFailClosed()
testOddSymmetricQuantizationOnBothAxes()
testActiveSessionRejectsEveryNewBegan()
testCancellationTimestampRegressionIsNormalized()
testCoordinatorClosesPartialBeganAndRetriesPartialCancellation()

if failures.isEmpty {
    print("product output tests passed")
} else {
    failures.forEach { FileHandle.standardError.write(Data(("FAIL: \($0)\n").utf8)) }
    exit(1)
}
