import CoreGraphics
import Darwin
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

private func copiedIOHIDEventDescription(_ event: CGEvent) -> String? {
    guard let handle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_NOW | RTLD_LOCAL
    ) else {
        return nil
    }
    defer { dlclose(handle) }
    guard let symbol = dlsym(handle, "CGEventCopyIOHIDEvent") else {
        return nil
    }
    typealias CopyIOHIDEvent = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> Unmanaged<CFTypeRef>?
    let copyIOHIDEvent = unsafeBitCast(symbol, to: CopyIOHIDEvent.self)
    let eventPointer = Unmanaged.passUnretained(event).toOpaque()
    guard let hidEvent = copyIOHIDEvent(eventPointer)?.takeRetainedValue() else {
        return nil
    }
    return CFCopyDescription(hidEvent) as String
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

private func dockSwipeTemplateData() -> Data {
    let path = "Fixtures/trackpad-contract/25F80/recognized-dockswipe-templates.json"
    guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else {
        fatalError("DockSwipe template fixtureを読み込めません: \(path)")
    }
    return data
}

private func productTraceContext() -> ProductGestureOutputTraceContext {
    guard
        let context = ProductGestureOutputTraceContext(
            captureRunToken: "00000000-0000-0000-0000-000000000119",
            scenarioID: "issue-119-product-output-tests",
            repoHeadSHA: String(repeating: "a", count: 40),
            executableSHA256: String(repeating: "b", count: 64)
        )
    else {
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
        modelData: modelData(),
        dockSwipeTemplateData: dockSwipeTemplateData(),
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
        modelData: modelData(),
        dockSwipeTemplateData: dockSwipeTemplateData(),
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
    expect(
        events.map { $0.type.rawValue } == [22, 29, 29], "\(label)をscroll、envelope、companionの順で投稿する"
    )
    expect(events[0].getIntegerValueField(rawField(99)) == 4, "\(label)のscroll phaseをendedにする")
    expect(events[1].getIntegerValueField(rawField(132)) == 4, "\(label)のenvelope phaseをendedにする")
    expect(events[2].getIntegerValueField(rawField(132)) == 4, "\(label)のcompanion phaseをendedにする")
    expect(
        events.dropFirst().allSatisfy { $0.timestamp == events[0].timestamp },
        "\(label)の3 eventを同一timestampにする")
    assertPositiveZeroTerminal(events[0], label: label)
}

private func assertPositiveZeroTerminal(_ event: CGEvent, label: String) {
    let integerFields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventDeltaAxis3,
    ]
    let doubleFields: [CGEventField] = [
        .scrollWheelEventFixedPtDeltaAxis1,
        .scrollWheelEventFixedPtDeltaAxis2,
        .scrollWheelEventFixedPtDeltaAxis3,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventPointDeltaAxis2,
        .scrollWheelEventPointDeltaAxis3,
    ]
    expect(
        integerFields.allSatisfy { event.getIntegerValueField($0) == 0 },
        "\(label)のinteger terminal deltaが0ではない")
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
    expect(adapter.capability.isSupported, "登録済みcontractをhost OS buildに依存せず検証する")
    expect(adapter.supports(.scroll), "scroll familyを対応扱いする")
    expect(
        ProductGestureOutputCapability.runtimeFamilies.allSatisfy(adapter.supports),
        "製品runtimeの3 familyを対応扱いする")
    expect(adapter.supports(.dockSwipe), "明示注入したtemplateでDockSwipeを利用可能にする")
    expect(adapter.supports(.dockSwipePinch), "明示注入したtemplateでDockSwipe pinchを利用可能にする")
    expect(adapter.capability.confirmedFamilies == [.scroll], "純正contract確定familyをscrollだけに限定する")
    expect(
        adapter.capability.trialFamilies == [.dockSwipe, .dockSwipePinch],
        "試用familyをDockSwipeとDockSwipe pinchに限定する")

    let results = [
        adapter.post(inputEvent(sessionID: 1, order: 0, phase: .began, deltaX: 12, deltaY: -8)),
        adapter.post(inputEvent(sessionID: 1, order: 1, phase: .changed, deltaX: 24, deltaY: -16)),
        adapter.post(
            inputEvent(
                sessionID: 1, order: 2, phase: .ended, continuation: .momentum, deltaX: 0, deltaY: 0
            )),
        adapter.post(momentumEvent(sessionID: 1, order: 3, phase: .began, deltaX: 8, deltaY: -4)),
        adapter.post(
            momentumEvent(sessionID: 1, order: 4, phase: .continued, deltaX: 4, deltaY: -2)),
        adapter.post(momentumEvent(sessionID: 1, order: 5, phase: .ended, deltaX: 0, deltaY: 0)),
    ]
    expect(
        results.map(\.generatedEventCount) == [3, 3, 3, 1, 1, 1],
        "inputは3 event、momentumは1 eventを完全生成する: \(results)")
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
    expect(
        events.map { $0.type.rawValue } == expectedTypes,
        "type22 -> envelope -> companionとmomentum type22の順序を守る")
    expect(events[0].getIntegerValueField(rawField(99)) == 1, "scroll began phaseを1にする")
    expect(events[3].getIntegerValueField(rawField(99)) == 2, "scroll changed phaseを2にする")
    expect(events[6].getIntegerValueField(rawField(99)) == 4, "scroll ended phaseを4にする")
    expect(events[9].getIntegerValueField(rawField(123)) == 1, "momentum began phaseを1にする")
    expect(events[10].getIntegerValueField(rawField(123)) == 2, "momentum continued phaseを2にする")
    expect(events[11].getIntegerValueField(rawField(123)) == 3, "momentum ended phaseを3にする")
    expect(
        events.filter { $0.type.rawValue == 22 }.allSatisfy {
            $0.getIntegerValueField(rawField(88)) == 1
        }, "全type22をcontinuousにする")

    let envelope = events[1]
    let companion = events[2]
    expect(envelope.timestamp == companion.timestamp, "envelopeとcompanionを同一timestampにする")
    expect(envelope.getIntegerValueField(rawField(110)) == 0, "envelope classifierを0にする")
    expect(companion.getIntegerValueField(rawField(110)) == 6, "companion classifierを6にする")
    expect(companion.getIntegerValueField(rawField(132)) == 1, "companion phaseをscrollと一致させる")
    expect(companion.getIntegerValueField(rawField(135)) == 1, "companion constant 135を1にする")
    let xMotion = Float(12)
    let yMotion = Float(-8)
    expect(
        [113, 114, 116, 118].allSatisfy {
            companion.getDoubleValueField(rawField($0)) == Double(xMotion)
        }, "companion X double aliasを一致させる")
    expect(
        [115, 117, 164].allSatisfy {
            companion.getIntegerValueField(rawField($0)) == Int64(xMotion.bitPattern)
        }, "companion X Float aliasを一致させる")
    expect(
        [119, 139].allSatisfy { companion.getDoubleValueField(rawField($0)) == Double(yMotion) },
        "companion Y double aliasを一致させる")
    expect(
        [123, 165].allSatisfy {
            companion.getIntegerValueField(rawField($0)) == Int64(yMotion.bitPattern)
        }, "companion Y Float aliasを一致させる")
    assertPositiveZeroTerminal(events[6], label: "scroll ended")
    assertPositiveZeroTerminal(events[11], label: "momentum ended")
}

private func testCancellationStates() {
    let inputCollector = EventCollector()
    let inputAdapter = makeAdapter(collector: inputCollector)
    _ = inputAdapter.post(inputEvent(sessionID: 2, order: 0, phase: .began, deltaX: 5, deltaY: 0))
    let inputCancellation = inputAdapter.post(
        cancellationEvent(sessionID: 2, order: 1, reason: .killSwitch))
    expect(
        inputCancellation.generatedEventCount == 3,
        "input active cancelはscroll ended + companionで閉じる: \(inputCancellation)")
    if inputCollector.events.count > 3 {
        assertPositiveZeroTerminal(inputCollector.events[3], label: "input cancel")
    }

    let waitingCollector = EventCollector()
    let waitingAdapter = makeAdapter(collector: waitingCollector)
    _ = waitingAdapter.post(inputEvent(sessionID: 3, order: 0, phase: .began, deltaX: 5, deltaY: 0))
    _ = waitingAdapter.post(
        inputEvent(
            sessionID: 3, order: 1, phase: .ended, continuation: .momentum, deltaX: 0, deltaY: 0)
    )
    let waitingCancellation = waitingAdapter.post(
        cancellationEvent(sessionID: 3, order: 2, reason: .runtimeStop))
    expect(
        waitingCancellation.generatedEventCount == 0,
        "awaiting momentumは既にscroll ended済みなので重複terminalを出さない")

    let momentumCollector = EventCollector()
    let momentumAdapter = makeAdapter(collector: momentumCollector)
    _ = momentumAdapter.post(
        inputEvent(sessionID: 4, order: 0, phase: .began, deltaX: 5, deltaY: 0))
    _ = momentumAdapter.post(
        inputEvent(
            sessionID: 4, order: 1, phase: .ended, continuation: .momentum, deltaX: 0, deltaY: 0)
    )
    _ = momentumAdapter.post(
        momentumEvent(sessionID: 4, order: 2, phase: .began, deltaX: 3, deltaY: 0))
    let momentumCancellation = momentumAdapter.post(
        cancellationEvent(sessionID: 4, order: 3, reason: .inputLifecycle))
    expect(
        momentumCancellation.generatedEventCount == 1,
        "momentum active cancelはmomentum endedで閉じる: \(momentumCancellation)")
    expect(
        momentumCollector.events.last?.getIntegerValueField(rawField(123)) == 3,
        "cancel時のmomentum phaseを3にする")
    if let terminal = momentumCollector.events.last {
        assertPositiveZeroTerminal(terminal, label: "momentum cancel")
    }
}

private func testFailClosedPaths() {
    var modified = contractData()
    modified.append(0x0A)
    let mismatch = TrackpadGestureOutputAdapter(
        contractData: modified,
    )
    expect(mismatch.capability.status == .contractMismatch, "fixture byte改変をcontract mismatchにする")
    expect(!mismatch.supports(.scroll), "改変fixtureではscrollを有効化しない")

    var modifiedModel = modelData()
    modifiedModel.append(0x0A)
    let modelMismatch = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        modelData: modifiedModel,
    )
    expect(
        modelMismatch.capability.status == .contractMismatch,
        "output model byte改変をcontract mismatchにする"
    )
    expect(!modelMismatch.supports(.scroll), "改変output modelではscrollを有効化しない")

    var modifiedTemplate = dockSwipeTemplateData()
    modifiedTemplate[modifiedTemplate.startIndex] ^= 0x01
    var templateMismatchPostAttempts = 0
    let templateMismatch = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        modelData: modelData(),
        dockSwipeTemplateData: modifiedTemplate,
        postEvent: { _ in
            templateMismatchPostAttempts += 1
            return true
        }
    )
    expect(
        templateMismatch.capability.status == .contractMismatch,
        "DockSwipe templateの1 byte改変をcontract mismatchにする"
    )
    expect(
        templateMismatch.capability.supportedFamilies.isEmpty,
        "改変templateでは対応familyを公開しない"
    )
    expect(
        ProductGestureOutputCapability.runtimeFamilies.allSatisfy {
            !templateMismatch.supports($0)
        },
        "改変templateではscrollを含む全製品familyを無効化する"
    )
    let templateMismatchResults = [
        templateMismatch.post(
            inputEvent(sessionID: 12, order: 0, phase: .began, deltaX: 5, deltaY: 0)
        ),
        templateMismatch.post(
            candidateInputEvent(
                sessionID: 13,
                order: 0,
                phase: .began,
                payload: .dockSwipe(
                    axis: .horizontal,
                    progress: 0.1,
                    motionX: 0.1,
                    motionY: 0,
                    terminalVelocityX: 0,
                    terminalVelocityY: 0
                )
            )
        ),
        templateMismatch.post(
            candidateInputEvent(
                sessionID: 14,
                order: 0,
                phase: .began,
                payload: .dockSwipePinch(
                    progress: 0.1,
                    motion: 0.1,
                    terminalVelocity: 0
                )
            )
        ),
    ]
    expect(
        templateMismatchResults.allSatisfy {
            $0.failure == .contractMismatch && $0.generatedEventCount == 0
        },
        "改変templateでは全製品出力をcontract mismatchでfail closedにする"
    )
    expect(templateMismatchPostAttempts == 0, "改変templateでは製品eventを1件も投稿しない")

    var postedAfterCreationFailure = 0
    let creationFailure = TrackpadGestureOutputAdapter(
        contractData: contractData(),
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
    expect(
        collector.postedTrace.count == traceCountBeforeFailure,
        "changed batch作成失敗frameではpost traceも増やさない")

    shouldCreateBaseEvent = true
    let cancellation = adapter.post(
        cancellationEvent(sessionID: 13, order: 1, reason: .outputFailure)
    )
    expect(
        cancellation.failure == nil, "factory復旧後のoutputFailure cancellationを成功させる: \(cancellation)")
    expect(
        cancellation.generatedEventCount == 3,
        "outputFailure cancellationで3 eventを投稿する: \(cancellation)")
    expect(
        collector.events.count == postCountBeforeFailure + 3,
        "失敗frameを飛ばしてcancellationの3 eventだけを追加する")
    assertInputCancellationBatch(
        Array(collector.events.suffix(3)), label: "adapter outputFailure cancellation")

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
    expect(
        coordinator.unsupportedRequiredFamilies.isEmpty, "固定drag/scroll familyの起動前capability検査を通る")

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

    expect(
        [began.mode, ended.mode, momentumBegan.mode, momentumEnded.mode].allSatisfy {
            $0 == .twoFingerSwipe
        }, "wheel由来momentumまで2本指modeを維持する")
    expect(
        [began.family, ended.family, momentumBegan.family, momentumEnded.family].allSatisfy {
            $0 == .scroll
        }, "wheel由来momentumまでscroll familyを維持する")
    expect(
        [began.result, ended.result, momentumBegan.result, momentumEnded.result].allSatisfy {
            $0.failure == nil
        }, "2D scroll lifecycleをsession coordinatorで完結する")
    guard collector.events.count == 8 else {
        failures.append("2D scroll coordinator lifecycleのevent数が8ではない: \(collector.events.count)")
        return
    }
    let inputScroll = collector.events[0]
    let inputCompanion = collector.events[2]
    let firstMomentum = collector.events[6]
    expect(
        inputScroll.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) != 0,
        "2D wheel inputのY point deltaを保持する")
    expect(
        inputScroll.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) != 0,
        "2D wheel inputのX point deltaを保持する")
    expect(inputCompanion.getDoubleValueField(rawField(113)) == 20, "2D companionのX motionを保持する")
    expect(inputCompanion.getDoubleValueField(rawField(119)) == -40, "2D companionのY motionを保持する")
    expect(firstMomentum.getIntegerValueField(rawField(123)) == 1, "最初のmomentum commandをbeganへ変換する")
    expect(
        firstMomentum.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) != 0,
        "momentumのY deltaを維持する")
    expect(
        firstMomentum.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) != 0,
        "momentumのX deltaを維持する")

    let fixedCoordinator = ProductGestureSessionCoordinator(
        output: makeAdapter(collector: EventCollector()))
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
            payload: .dockSwipe(
                axis: .horizontal,
                progress: 0.1,
                motionX: 0.1,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        ),
        candidateInputEvent(
            sessionID: 120,
            order: 1,
            phase: .changed,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: 0.6,
                motionX: 0.5,
                motionY: 0,
                terminalVelocityX: 0,
                terminalVelocityY: 0
            )
        ),
        candidateInputEvent(
            sessionID: 120,
            order: 2,
            phase: .ended,
            payload: .dockSwipe(
                axis: .horizontal,
                progress: 0.6,
                motionX: 0,
                motionY: 0,
                terminalVelocityX: 1.2,
                terminalVelocityY: 0
            )
        ),
        candidateInputEvent(
            sessionID: 122,
            order: 0,
            phase: .began,
            payload: .dockSwipePinch(progress: 0.1, motion: 0.1, terminalVelocity: 0)
        ),
        candidateInputEvent(
            sessionID: 122,
            order: 1,
            phase: .changed,
            payload: .dockSwipePinch(progress: 0.5, motion: 0.4, terminalVelocity: 0)
        ),
        candidateInputEvent(
            sessionID: 122,
            order: 2,
            phase: .ended,
            payload: .dockSwipePinch(progress: 0.5, motion: 0, terminalVelocity: 0.4)
        ),
    ]
    let results = posts.map(adapter.post)
    expect(
        results.allSatisfy { $0.failure == nil && $0.generatedEventCount == 1 },
        "製品modeへ接続する2 candidate familyを各1 eventで投稿する")
    guard collector.events.count == 6 else {
        failures.append(
            "candidate familyのevent数が6ではない: \(collector.events.count) results=\(results)")
        return
    }
    expect(
        collector.events.map { $0.type.rawValue } == [30, 30, 30, 30, 30, 30],
        "candidate familyのevent typeを固定する")
    expect(
        collector.events.allSatisfy { $0.getIntegerValueField(rawField(110)) == 23 },
        "DockSwipe classifierを23にする")
    expect(
        collector.events.map { $0.getIntegerValueField(rawField(132)) } == [1, 2, 4, 1, 2, 4],
        "candidate lifecycle phaseをbegan/changed/endedにする")
    expect(
        abs(abs(collector.events[2].getDoubleValueField(rawField(124))) - 0.6) < 0.000_1,
        "DockSwipe terminalのIOHID payloadへ累積progressを保持する")
    expect(
        copiedIOHIDEventDescription(collector.events[0])?.contains("EventType:           DockSwipe") == true,
        "DockSwipe CGEventへ認識済みIOHID eventを内包する"
    )
    expect(
        copiedIOHIDEventDescription(collector.events[3])?.contains("EventType:           DockSwipe") == true,
        "4本指pinch CGEventへ認識済みDockSwipe eventを内包する"
    )
    expect(
        collector.events.allSatisfy {
            $0.getIntegerValueField(.eventSourceUserData) == NapeGestureGeneratedEventMarker.value
        }, "全candidate eventへ生成markerを付ける")
    expect(
        collector.events.allSatisfy {
            $0.getIntegerValueField(rawField(55)) == Int64($0.type.rawValue)
        }, "candidate eventのcontract type field 55を一致させる")
    expect(
        collector.events.allSatisfy {
            $0.getIntegerValueField(rawField(58)) == Int64($0.timestamp)
        },
        "candidate eventのcontract timestamp field 58を一致させる")
    expect(
        Set(collector.postedTrace.map(\.family)) == [.dockSwipe, .dockSwipePinch],
        "traceへ製品mode接続済みの2 candidate familyを記録する")
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
            mode: .systemSwipe,
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
            mode: .systemSwipe,
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
            mode: .systemSwipe,
            kind: .drag,
            phase: .ended,
            direction: .left,
            deltaX: -5,
            deltaY: 120,
            velocityX: -50,
            velocityY: 1_200,
            timestamp: MonotonicEventClock.nowSeconds
        ),
    ]
    let results = commands.map { coordinator.post(command: $0) }
    expect(
        results.allSatisfy { $0.mode == .systemSwipe && $0.family == .dockSwipe },
        "システムスワイプをDockSwipe familyへ固定する")
    expect(results.allSatisfy { $0.result.failure == nil }, "方向反転を含むdrag sessionを完結する")

    let frames = output.postedEvents.compactMap { event -> TrackpadOutputInputFrame? in
        guard case .input(let frame) = event else { return nil }
        return frame
    }
    expect(frames.count == 3, "drag lifecycleを3 input frameとして投稿する")
    expect(Set(frames.map(\.sessionID)).count == 1, "方向反転後も同一session IDを維持する")
    expect(
        frames.first?.sessionID == TrackpadOutputSessionID(rawValue: 144),
        "指定sequenceのsession IDを使用する")
    expect(frames.map(\.captureOrder) == [0, 1, 2], "方向反転後もcapture orderを連続させる")
    expect(frames.allSatisfy { $0.payload.family == .dockSwipe }, "drag familyをDockSwipeへ固定する")
    let payloads = frames.compactMap { frame -> (TrackpadOutputAxis, Double)? in
        guard case .dockSwipe(let axis, let progress, _, _, _, _) = frame.payload else {
            return nil
        }
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
            mode: .twoFingerSwipe,
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
    expect(
        scrollPost.mode == .twoFingerSwipe && scrollPost.family == .scroll,
        "2本指modeをscroll familyへ接続する"
    )
    let scrollFamily = scrollOutput.postedEvents.compactMap { event -> TrackpadOutputEventFamily? in
        guard case .input(let frame) = event else { return nil }
        return frame.payload.family
    }.first
    expect(scrollFamily == .scroll, "mouse moveの2次元deltaをscroll payloadへ渡す")

    let pinchOutput = PermissiveProductOutput(capability: capability)
    let pinchCoordinator = ProductGestureSessionCoordinator(output: pinchOutput)
    let pinchPost = pinchCoordinator.post(
        command: GestureCommand(
            mode: .pinch,
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
    expect(
        pinchPost.mode == .pinch && pinchPost.family == .dockSwipePinch,
        "ピンチmodeをDockSwipe pinch familyへ接続する")
    let pinchFamily = pinchOutput.postedEvents.compactMap { event -> TrackpadOutputEventFamily? in
        guard case .input(let frame) = event else { return nil }
        return frame.payload.family
    }.first
    expect(pinchFamily == .dockSwipePinch, "mouse moveをDockSwipe pinch payloadへ渡す")
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
    expect(
        changed.result.failure == .eventCreationFailed,
        "coordinator経由のchanged batch作成失敗を明示する: \(changed.result)")
    expect(changed.result.generatedEventCount == 0, "coordinator経由の失敗frameでは生成済みevent数を0にする")
    expect(collector.events.count == postCountBeforeFailure, "coordinator経由の失敗frameでは1件も投稿しない")

    shouldCreateBaseEvent = true
    let cancellation = coordinator.cancelActive(
        reason: .outputFailure,
        at: MonotonicEventClock.nowSeconds
    )
    expect(
        cancellation.failure == nil,
        "coordinatorが保持したsessionをoutputFailure cancellationで閉じる: \(cancellation)")
    expect(
        cancellation.generatedEventCount == 3, "coordinatorのoutputFailure cancellationで3 eventを投稿する"
    )
    expect(
        collector.events.count == postCountBeforeFailure + 3,
        "coordinator復旧時はcancellationの3 eventだけを追加する")
    assertInputCancellationBatch(
        Array(collector.events.suffix(3)), label: "coordinator outputFailure cancellation")

    let repeatedCancellation = coordinator.cancelActive(
        reason: .outputFailure,
        at: MonotonicEventClock.nowSeconds
    )
    expect(repeatedCancellation.failure == nil, "閉じたcoordinator sessionの再cancellationを失敗扱いしない")
    expect(
        repeatedCancellation.generatedEventCount == 0, "閉じたcoordinator sessionの再cancellationでは投稿しない"
    )
}

private func testCoordinatorPreservesActiveModeAcrossChangedCommandKind() {
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
    expect(began.result.failure == nil, "mode不一致復旧テストのbeganを成功させる")

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
    expect(
        changed.mode == .twoFingerSwipe && changed.family == .scroll,
        "後続command kindにかかわらず開始時modeとfamilyを維持する")
    expect(changed.result.failure == nil, "開始時modeでchangedを継続する")
    guard output.postedEvents.count == 2,
        case .input(let beganFrame) = output.postedEvents[0],
        case .input(let changedFrame) = output.postedEvents[1]
    else {
        failures.append("active mode継続検査のinput frameが2件ではない")
        return
    }
    expect(changedFrame.sessionID == beganFrame.sessionID, "command kind変更後も同一session IDを維持する")
    expect(changedFrame.captureOrder == 1, "command kind変更後もcapture orderを連続させる")
    expect(changedFrame.payload.family == .scroll, "開始時のscroll familyを維持する")

    let cancellation = coordinator.cancelActive(
        reason: .inputLifecycle,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "mode継続後もactive sessionをcancelできる")
    expect(cancellation.generatedEventCount == 1, "permissive outputへcancellationを1 frame渡す")
}

private func testCoordinatorRejectsModeChangeWithinActiveSession() {
    let output = PermissiveProductOutput(
        capability: makeAdapter(collector: EventCollector()).capability
    )
    let coordinator = ProductGestureSessionCoordinator(output: output)
    let began = coordinator.post(
        command: GestureCommand(
            mode: .twoFingerSwipe,
            kind: .drag,
            phase: .began,
            direction: .up,
            deltaX: 0,
            deltaY: -8,
            velocityX: 0,
            velocityY: -80,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(began.result.failure == nil, "mode変更拒否検査のsessionを開始する")
    let postedCount = output.postedEvents.count

    let mismatched = coordinator.post(
        command: GestureCommand(
            mode: .pinch,
            kind: .drag,
            phase: .changed,
            direction: .up,
            deltaX: 0,
            deltaY: -4,
            velocityX: 0,
            velocityY: -40,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(mismatched.mode == .pinch, "拒否結果へ実際に要求されたmodeを記録する")
    expect(mismatched.family == .dockSwipePinch, "拒否結果へ要求されたfamilyを記録する")
    expect(mismatched.result.failure == .invalidSession, "active session中のmode変更を拒否する")
    expect(output.postedEvents.count == postedCount, "mode不一致時はeventを投稿しない")

    let valid = coordinator.post(
        command: GestureCommand(
            mode: .twoFingerSwipe,
            kind: .drag,
            phase: .changed,
            direction: .up,
            deltaX: 0,
            deltaY: -4,
            velocityX: 0,
            velocityY: -40,
            timestamp: MonotonicEventClock.nowSeconds
        )
    )
    expect(valid.result.failure == nil, "mode不一致拒否後も元sessionを継続できる")

    let cancellation = coordinator.cancelActive(
        reason: .inputLifecycle,
        at: MonotonicEventClock.nowSeconds
    )
    expect(cancellation.failure == nil, "mode不一致拒否後のsessionをcancelできる")
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
        expect(
            firstCancellation.failure == .eventPostFailed, "terminalの\(failureAttempt)件目post失敗を明示する"
        )
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
        ),
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

    let conflictingBegan = coordinator.post(
        command: GestureCommand(
            mode: .pinch,
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
    expect(
        conflictingBegan.mode == .pinch && conflictingBegan.family == .dockSwipePinch,
        "active中の新規began拒否へ要求されたmodeとfamilyを返す")
    expect(
        conflictingBegan.result.failure == .invalidSession,
        "active中の別mode beganを成功扱いしない"
    )

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
    expect(
        cancellation.failure == nil, "逆行cancel timestampをlast timestamp以上へ正規化する: \(cancellation)")
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
        let beganCoordinator = ProductGestureSessionCoordinator(
            output: makeInjectedAdapter(sink: beganSink))
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
        expect(
            partialBegan.result.failure == .eventPostFailed,
            "coordinator beganの\(failureAttempt)件目失敗を明示する")
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
        let terminalCoordinator = ProductGestureSessionCoordinator(
            output: makeInjectedAdapter(sink: terminalSink))
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
        expect(
            partialCancellation.failure == .eventPostFailed,
            "coordinator terminalの\(failureAttempt)件目失敗を明示する")
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
        expect(
            afterClosed.failure == nil && afterClosed.generatedEventCount == 0,
            "再試行成功後のcoordinator sessionを閉じる")
    }
}

private func testFixedGestureClassesReachProductFamiliesWithExactOrderAndTimestamp() {
    let cases: [(MouseButton, FixedGestureClass, TrackpadOutputEventFamily)] = [
        (.button3, .twoFingerScrollSwipe, .scroll),
        (.button4, .threeFingerSystemSwipe, .dockSwipe),
        (.center, .pinch, .dockSwipePinch),
    ]

    for (index, item) in cases.enumerated() {
        let output = PermissiveProductOutput(
            capability: .validated(
                fixtureData: contractData(),
            )
        )
        let coordinator = FixedGestureProductSessionCoordinator(output: output)
        let sessionID = TrackpadOutputSessionID(rawValue: UInt64(900 + index))
        let timestamps = [
            MonotonicEventTimestamp(nanosecondsSinceStartup: 10_000),
            MonotonicEventTimestamp(nanosecondsSinceStartup: 10_007),
            MonotonicEventTimestamp(nanosecondsSinceStartup: 10_019),
        ]
        let commands = [
            FixedGestureInputCommand(
                sessionID: sessionID,
                sourceButton: item.0,
                gestureClass: item.1,
                captureOrder: 0,
                timestamp: timestamps[0],
                sourceKind: .buttonDown,
                phase: .began,
                deltaX: 0,
                deltaY: 0
            ),
            FixedGestureInputCommand(
                sessionID: sessionID,
                sourceButton: item.0,
                gestureClass: item.1,
                captureOrder: 1,
                timestamp: timestamps[1],
                sourceKind: .move,
                phase: .changed,
                deltaX: 12.5,
                deltaY: -7.25
            ),
            FixedGestureInputCommand(
                sessionID: sessionID,
                sourceButton: item.0,
                gestureClass: item.1,
                captureOrder: 2,
                timestamp: timestamps[2],
                sourceKind: .buttonUp,
                phase: .ended,
                deltaX: 0,
                deltaY: 0
            ),
        ]
        let posts = commands.map(coordinator.post)

        expect(posts.allSatisfy { $0.result.failure == nil }, "\(item.1.rawValue)をproduct outputへ投稿する")
        expect(posts.allSatisfy { $0.family == item.2 }, "\(item.1.rawValue)のfamilyを\(item.2.rawValue)へ固定する")
        let expectedOrders: [UInt64] = item.1 == .twoFingerScrollSwipe ? [0, 1, 2] : [1, 2]
        let expectedTimestamps = item.1 == .twoFingerScrollSwipe ? timestamps : Array(timestamps.dropFirst())
        expect(
            output.postedEvents.count == expectedOrders.count,
            "\(item.1.rawValue)でmove sampleとterminalを欠落・合算しない"
        )
        expect(output.postedEvents.map(\.captureOrder) == expectedOrders, "\(item.1.rawValue)のcapture orderを保持する")
        expect(output.postedEvents.map(\.timestamp) == expectedTimestamps, "\(item.1.rawValue)のexact timestampを保持する")
        expect(output.postedEvents.allSatisfy { $0.sessionID == sessionID }, "\(item.1.rawValue)のsession IDを保持する")
    }
}

private func testFixedThreeFingerDockSwipeUsesSharedSourceDeltaScale() {
    let output = PermissiveProductOutput(
        capability: .validated(
            fixtureData: contractData(),
        )
    )
    let coordinator = FixedGestureProductSessionCoordinator(output: output)
    let sessionID = TrackpadOutputSessionID(rawValue: 950)
    let interval = MonotonicEventClock.nanosecondsPerSecond
    let commands = [
        FixedGestureInputCommand(
            sessionID: sessionID,
            sourceButton: .button4,
            gestureClass: .threeFingerSystemSwipe,
            captureOrder: 0,
            timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval),
            sourceKind: .buttonDown,
            phase: .began,
            deltaX: 0,
            deltaY: 0
        ),
        FixedGestureInputCommand(
            sessionID: sessionID,
            sourceButton: .button4,
            gestureClass: .threeFingerSystemSwipe,
            captureOrder: 1,
            timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval * 2),
            sourceKind: .move,
            phase: .changed,
            deltaX: 30,
            deltaY: 0
        ),
        FixedGestureInputCommand(
            sessionID: sessionID,
            sourceButton: .button4,
            gestureClass: .threeFingerSystemSwipe,
            captureOrder: 2,
            timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval * 3),
            sourceKind: .move,
            phase: .changed,
            deltaX: 30,
            deltaY: 0
        ),
        FixedGestureInputCommand(
            sessionID: sessionID,
            sourceButton: .button4,
            gestureClass: .threeFingerSystemSwipe,
            captureOrder: 3,
            timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval * 4),
            sourceKind: .buttonUp,
            phase: .ended,
            deltaX: 0,
            deltaY: 0
        ),
    ]
    let posts = commands.map(coordinator.post)
    expect(posts.allSatisfy { $0.result.failure == nil }, "3本指DockSwipeの共通source delta scale検証入力を完結する")

    let payloads = output.postedEvents.compactMap { event -> (Double, Double)? in
        guard case .input(let frame) = event,
              case .dockSwipe(
                  let axis,
                  let progress,
                  _,
                  _,
                  let terminalVelocityX,
                  let terminalVelocityY
              ) = frame.payload
        else {
            return nil
        }
        let terminalVelocity = axis == .horizontal ? terminalVelocityX : terminalVelocityY
        return (progress, terminalVelocity)
    }
    expect(payloads.count == 3, "3本指DockSwipe lifecycleを3 eventで保持する")
    guard payloads.count == 3 else {
        return
    }
    expect(abs(payloads[0].0 - 0.05) < 0.000_001, "source delta 30を3本指DockSwipe progress 0.05へ変換する")
    expect(abs(payloads[1].0 - 0.1) < 0.000_001, "3本指DockSwipe progressを共通source delta scaleで累積する")
    expect(abs(payloads[2].0 - 0.1) < 0.000_001, "3本指DockSwipe terminalへ累積progressを保持する")
    expect(abs(payloads[2].1 - 0.05) < 0.000_001, "3本指DockSwipe terminal velocityへ共通source delta scaleを適用する")
}

private func testFixedFourFingerPinchUsesSharedSourceDeltaScale() {
    let output = PermissiveProductOutput(
        capability: .validated(
            fixtureData: contractData(),
        )
    )
    let coordinator = FixedGestureProductSessionCoordinator(output: output)
    let sessionID = TrackpadOutputSessionID(rawValue: 951)
    let interval = MonotonicEventClock.nanosecondsPerSecond

    func command(
        order: UInt64,
        sourceKind: GestureInputSourceKind,
        phase: FixedGestureInputPhase,
        deltaY: Double = 0
    ) -> FixedGestureInputCommand {
        FixedGestureInputCommand(
            sessionID: sessionID,
            sourceButton: .center,
            gestureClass: .pinch,
            captureOrder: order,
            timestamp: MonotonicEventTimestamp(
                nanosecondsSinceStartup: interval * (order + 1)
            ),
            sourceKind: sourceKind,
            phase: phase,
            deltaX: 0,
            deltaY: deltaY
        )
    }

    let posts = [
        command(order: 0, sourceKind: .buttonDown, phase: .began),
        command(order: 1, sourceKind: .move, phase: .changed, deltaY: -30),
        command(order: 2, sourceKind: .move, phase: .changed, deltaY: -30),
        command(order: 3, sourceKind: .buttonUp, phase: .ended),
    ].map(coordinator.post)
    expect(posts.allSatisfy { $0.result.failure == nil }, "4本指pinchの共通source delta scale検証入力を完結する")

    let payloads = output.postedEvents.compactMap { event -> (Double, Double)? in
        guard case .input(let frame) = event,
              case .dockSwipePinch(let progress, _, let terminalVelocity) = frame.payload
        else {
            return nil
        }
        return (progress, terminalVelocity)
    }
    expect(payloads.count == 3, "4本指pinch lifecycleを3 eventで保持する")
    guard payloads.count == 3 else {
        return
    }
    expect(abs(payloads[0].0 - 0.05) < 0.000_001, "source delta 30を4本指pinch progress 0.05へ変換する")
    expect(abs(payloads[1].0 - 0.1) < 0.000_001, "4本指pinch progressを共通source delta scaleで累積する")
    expect(abs(payloads[2].0 - 0.1) < 0.000_001, "4本指pinch terminalへ累積progressを保持する")
    expect(abs(payloads[2].1 - 0.05) < 0.000_001, "4本指pinch terminal velocityへ共通source delta scaleを適用する")
}

private func testSystemGestureSensitivityFollowsAssignedClassNotPhysicalButton() {
    func payloads(
        gestureClass: FixedGestureClass,
        sourceButton: MouseButton,
        sensitivity: Double,
        sessionID: UInt64,
        deltaX: Double,
        deltaY: Double
    ) -> [TrackpadOutputPayload] {
        let output = PermissiveProductOutput(
            capability: .validated(fixtureData: contractData())
        )
        let coordinator = FixedGestureProductSessionCoordinator(
            output: output,
            systemGestureSensitivity: sensitivity
        )
        let interval = MonotonicEventClock.nanosecondsPerSecond
        var assignments = GestureButtonAssignments.default
        switch sourceButton {
        case .button3:
            assignments.button3 = gestureClass
        case .button4:
            assignments.button4 = gestureClass
        case .center:
            assignments.button5 = gestureClass
        case .left, .right, .button5:
            expect(false, "感度テストへ未対応のsource buttonを渡さない")
            return []
        }
        var recognizer = FixedGestureInputRecognizer(
            cancellation: GestureCancellationConfiguration(
                maximumDuration: 0,
                maximumInactivityInterval: 0
            ),
            assignments: assignments,
            sessionSequence: TrackpadOutputSessionSequence(startingAt: sessionID)
        )
        let decisions = [
            recognizer.handle(
                .buttonDown(
                    button: sourceButton,
                    timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval)
                )
            ),
            recognizer.handle(
                .move(
                    deltaX: deltaX,
                    deltaY: deltaY,
                    timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval * 2)
                )
            ),
            recognizer.handle(
                .move(
                    deltaX: deltaX,
                    deltaY: deltaY,
                    timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval * 3)
                )
            ),
            recognizer.handle(
                .buttonUp(
                    button: sourceButton,
                    timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: interval * 4)
                )
            ),
        ]
        let commands = decisions.flatMap(\.commands)
        expect(commands.count == 4, "変更済み割り当ての入力列を4 commandへ変換する")
        expect(
            commands.allSatisfy {
                $0.sourceButton == sourceButton && $0.gestureClass == gestureClass
            },
            "物理buttonではなく選択classをsession全体へ保持する"
        )
        let posts = commands.map(coordinator.post)
        expect(
            posts.allSatisfy { $0.result.failure == nil },
            "感度\(sensitivity)の\(gestureClass.rawValue)入力列を完結する"
        )
        return output.postedEvents.compactMap { event in
            guard case .input(let frame) = event else {
                return nil
            }
            return frame.payload
        }
    }

    func assertDockSwipe(
        _ payloads: [TrackpadOutputPayload],
        sensitivity: Double,
        label: String
    ) {
        let values = payloads.compactMap { payload -> (
            progress: Double,
            motionX: Double,
            motionY: Double,
            terminalVelocity: Double
        )? in
            guard case let .dockSwipe(
                axis,
                progress,
                motionX,
                motionY,
                terminalVelocityX,
                terminalVelocityY
            ) = payload else {
                return nil
            }
            let terminalVelocity = axis == .horizontal
                ? terminalVelocityX : terminalVelocityY
            return (progress, motionX, motionY, terminalVelocity)
        }
        expect(values.count == 3, "\(label)のDockSwipe lifecycleを3 eventで保持する")
        guard values.count == 3 else {
            return
        }
        let unit = 0.05 * sensitivity
        expect(abs(values[0].0 - unit) < 0.000_001, "\(label)のbegan progressへ感度を1回だけ掛ける")
        expect(abs(values[1].0 - unit * 2) < 0.000_001, "\(label)の累積progressへ感度を一貫して掛ける")
        expect(abs(values[2].0 - unit * 2) < 0.000_001, "\(label)のterminal progressへ感度を保持する")
        expect(
            values.allSatisfy { abs($0.1 - unit) < 0.000_001 && abs($0.2) < 0.000_001 },
            "\(label)のmotionへ感度を一貫して掛ける"
        )
        expect(abs(values[0].3) < 0.000_001 && abs(values[1].3) < 0.000_001, "\(label)の非terminal velocityを0に保つ")
        expect(abs(values[2].3 - unit) < 0.000_001, "\(label)のterminal velocityへ感度を1回だけ掛ける")
    }

    func assertPinch(
        _ payloads: [TrackpadOutputPayload],
        sensitivity: Double,
        label: String
    ) {
        let values = payloads.compactMap { payload -> (
            progress: Double,
            motion: Double,
            terminalVelocity: Double
        )? in
            guard case let .dockSwipePinch(progress, motion, terminalVelocity) = payload else {
                return nil
            }
            return (progress, motion, terminalVelocity)
        }
        expect(values.count == 3, "\(label)のpinch lifecycleを3 eventで保持する")
        guard values.count == 3 else {
            return
        }
        let unit = 0.05 * sensitivity
        expect(abs(values[0].0 - unit) < 0.000_001, "\(label)のbegan progressへ感度を1回だけ掛ける")
        expect(abs(values[1].0 - unit * 2) < 0.000_001, "\(label)の累積progressへ感度を一貫して掛ける")
        expect(abs(values[2].0 - unit * 2) < 0.000_001, "\(label)のterminal progressへ感度を保持する")
        expect(abs(values[0].1 - unit) < 0.000_001 && abs(values[1].1 - unit) < 0.000_001, "\(label)のmotionへ感度を一貫して掛ける")
        expect(abs(values[2].1) < 0.000_001, "\(label)のterminal motionを0に保つ")
        expect(abs(values[0].2) < 0.000_001 && abs(values[1].2) < 0.000_001, "\(label)の非terminal velocityを0に保つ")
        expect(abs(values[2].2 - unit) < 0.000_001, "\(label)のterminal velocityへ感度を1回だけ掛ける")
    }

    for (index, sensitivity) in [0.25, 2.0].enumerated() {
        assertDockSwipe(
            payloads(
                gestureClass: .threeFingerSystemSwipe,
                sourceButton: .button3,
                sensitivity: sensitivity,
                sessionID: UInt64(1_100 + index),
                deltaX: 30,
                deltaY: 0
            ),
            sensitivity: sensitivity,
            label: "button 3へ割り当てた3本指・感度\(sensitivity)"
        )
        assertPinch(
            payloads(
                gestureClass: .pinch,
                sourceButton: .button4,
                sensitivity: sensitivity,
                sessionID: UInt64(1_200 + index),
                deltaX: 0,
                deltaY: -30
            ),
            sensitivity: sensitivity,
            label: "button 4へ割り当てた4本指・感度\(sensitivity)"
        )
    }

    let minimumScroll = payloads(
        gestureClass: .twoFingerScrollSwipe,
        sourceButton: .center,
        sensitivity: 0.25,
        sessionID: 1_300,
        deltaX: 30,
        deltaY: -18
    )
    let maximumScroll = payloads(
        gestureClass: .twoFingerScrollSwipe,
        sourceButton: .center,
        sensitivity: 2.0,
        sessionID: 1_301,
        deltaX: 30,
        deltaY: -18
    )
    expect(
        minimumScroll == maximumScroll,
        "論理button 5へ割り当てた2本指classには共有システムジェスチャー感度を適用しない"
    )
}

private func testFixedGestureCoordinatorClosesPartialScrollBatch() {
    func command(
        order: UInt64,
        phase: FixedGestureInputPhase,
        sourceKind: GestureInputSourceKind,
        timestamp: UInt64
    ) -> FixedGestureInputCommand {
        FixedGestureInputCommand(
            sessionID: TrackpadOutputSessionID(rawValue: 990),
            sourceButton: .button3,
            gestureClass: .twoFingerScrollSwipe,
            captureOrder: order,
            timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: timestamp),
            sourceKind: sourceKind,
            phase: phase,
            deltaX: phase == .changed ? 4 : 0,
            deltaY: phase == .changed ? -6 : 0
        )
    }

    let beganCollector = EventCollector()
    let beganSink = InjectedPostSink(collector: beganCollector)
    beganSink.configure(failureAttempt: 2)
    let beganCoordinator = FixedGestureProductSessionCoordinator(
        output: makeInjectedAdapter(sink: beganSink)
    )
    let partialBegan = beganCoordinator.post(
        command(order: 0, phase: .began, sourceKind: .buttonDown, timestamp: 10)
    )
    expect(partialBegan.result.failure == .eventPostFailed, "fixed coordinatorがpartial beganを検出する")
    expect(partialBegan.result.generatedEventCount == 1, "fixed coordinatorがpartial began投稿数を保持する")
    beganSink.configure(failureAttempt: nil)
    let cancelledBegan = beganCoordinator.cancelActive(
        reason: .outputFailure,
        timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: 11)
    )
    expect(cancelledBegan.failure == nil, "fixed coordinatorがpartial beganをcancel terminalへ収束させる")
    assertInputCancellationBatch(
        Array(beganCollector.events.suffix(3)),
        label: "fixed coordinator partial began"
    )

    let terminalCollector = EventCollector()
    let terminalSink = InjectedPostSink(collector: terminalCollector)
    terminalSink.configure(failureAttempt: nil)
    let terminalCoordinator = FixedGestureProductSessionCoordinator(
        output: makeInjectedAdapter(sink: terminalSink)
    )
    _ = terminalCoordinator.post(
        command(order: 0, phase: .began, sourceKind: .buttonDown, timestamp: 20)
    )
    terminalSink.configure(failureAttempt: 2)
    let partialTerminal = terminalCoordinator.post(
        command(order: 1, phase: .ended, sourceKind: .buttonUp, timestamp: 21)
    )
    expect(partialTerminal.result.failure == .eventPostFailed, "fixed coordinatorがpartial terminalを検出する")
    terminalSink.configure(failureAttempt: nil)
    let retriedTerminal = terminalCoordinator.cancelActive(
        reason: .outputFailure,
        timestamp: MonotonicEventTimestamp(nanosecondsSinceStartup: 22)
    )
    expect(retriedTerminal.failure == nil, "fixed coordinatorがpartial terminalの未投稿offsetを再開する")
    expect(retriedTerminal.generatedEventCount == 2, "fixed coordinatorがterminal未投稿分だけを投稿する")
}

private func testFixedScrollAcceptsMouseDeltaGrid() {
    let adapter = TrackpadGestureOutputAdapter(
        contractData: contractData(),
        modelData: modelData(),
        postEvent: { _ in true }
    )
    let coordinator = FixedGestureProductSessionCoordinator(output: adapter)
    var sessionRawValue: UInt64 = 20_000

    for deltaX in -16...16 {
        for deltaY in -16...16 {
            let sessionID = TrackpadOutputSessionID(rawValue: sessionRawValue)
            sessionRawValue += 1
            let commands = [
                FixedGestureInputCommand(
                    sessionID: sessionID,
                    sourceButton: .button3,
                    gestureClass: .twoFingerScrollSwipe,
                    captureOrder: 0,
                    timestamp: MonotonicEventClock.now,
                    sourceKind: .buttonDown,
                    phase: .began,
                    deltaX: 0,
                    deltaY: 0
                ),
                FixedGestureInputCommand(
                    sessionID: sessionID,
                    sourceButton: .button3,
                    gestureClass: .twoFingerScrollSwipe,
                    captureOrder: 1,
                    timestamp: MonotonicEventClock.now,
                    sourceKind: .move,
                    phase: .changed,
                    deltaX: Double(deltaX),
                    deltaY: Double(deltaY)
                ),
                FixedGestureInputCommand(
                    sessionID: sessionID,
                    sourceButton: .button3,
                    gestureClass: .twoFingerScrollSwipe,
                    captureOrder: 2,
                    timestamp: MonotonicEventClock.now,
                    sourceKind: .buttonUp,
                    phase: .ended,
                    deltaX: 0,
                    deltaY: 0
                ),
            ]
            for command in commands {
                let post = coordinator.post(command)
                if let failure = post.result.failure {
                    failures.append(
                        "mouse delta grid x=\(deltaX) y=\(deltaY) phase=\(command.phase.rawValue): \(failure.rawValue) \(post.result.failureDetails ?? "")"
                    )
                    coordinator.reset()
                    break
                }
            }
        }
    }
}

private func postFixedGestureSmokeIfRequested() {
    guard ProcessInfo.processInfo.environment["NAPE_GESTURE_POST_FIXED_SMOKE"] == "1" else {
        return
    }
    let adapter = TrackpadGestureOutputAdapter()
    let coordinator = FixedGestureProductSessionCoordinator(output: adapter)
    let cases: [(MouseButton, FixedGestureClass, Double, Double)] = [
        (.button3, .twoFingerScrollSwipe, -1, 0),
        (.button4, .threeFingerSystemSwipe, 0, -12),
        (.center, .pinch, 0, 10),
    ]

    for (index, item) in cases.enumerated() {
        let sessionID = TrackpadOutputSessionID(rawValue: UInt64(8_000 + index))
        var commands = [
            FixedGestureInputCommand(
                sessionID: sessionID,
                sourceButton: item.0,
                gestureClass: item.1,
                captureOrder: 0,
                timestamp: MonotonicEventClock.now,
                sourceKind: .buttonDown,
                phase: .began,
                deltaX: 0,
                deltaY: 0
            )
        ]
        commands.append(
            contentsOf: (1...6).map { order in
                FixedGestureInputCommand(
                    sessionID: sessionID,
                    sourceButton: item.0,
                    gestureClass: item.1,
                    captureOrder: UInt64(order),
                    timestamp: MonotonicEventClock.now,
                    sourceKind: .move,
                    phase: .changed,
                    deltaX: item.2,
                    deltaY: item.3
                )
            }
        )
        commands.append(
            FixedGestureInputCommand(
                sessionID: sessionID,
                sourceButton: item.0,
                gestureClass: item.1,
                captureOrder: 7,
                timestamp: MonotonicEventClock.now,
                sourceKind: .buttonUp,
                phase: .ended,
                deltaX: 0,
                deltaY: 0
            )
        )

        for command in commands {
            Thread.sleep(forTimeInterval: 0.008)
            let current = FixedGestureInputCommand(
                sessionID: command.sessionID,
                sourceButton: command.sourceButton,
                gestureClass: command.gestureClass,
                captureOrder: command.captureOrder,
                timestamp: MonotonicEventClock.now,
                sourceKind: command.sourceKind,
                phase: command.phase,
                deltaX: command.deltaX,
                deltaY: command.deltaY
            )
            let post = coordinator.post(current)
            expect(post.result.failure == nil, "system-wide smokeで\(item.1.rawValue)を投稿する")
        }
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
testCoordinatorPreservesActiveModeAcrossChangedCommandKind()
testCoordinatorRejectsModeChangeWithinActiveSession()
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
testFixedGestureClassesReachProductFamiliesWithExactOrderAndTimestamp()
testFixedThreeFingerDockSwipeUsesSharedSourceDeltaScale()
testFixedFourFingerPinchUsesSharedSourceDeltaScale()
testSystemGestureSensitivityFollowsAssignedClassNotPhysicalButton()
testFixedGestureCoordinatorClosesPartialScrollBatch()
testFixedScrollAcceptsMouseDeltaGrid()
postFixedGestureSmokeIfRequested()
failures.append(contentsOf: runStabilityRegressionTests())

if failures.isEmpty {
    print("product output tests passed")
} else {
    failures.forEach { FileHandle.standardError.write(Data(("FAIL: \($0)\n").utf8)) }
    exit(1)
}
