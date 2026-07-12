import CoreGraphics
import Foundation
import NapeGestureCore

public typealias ProductScrollEventFactory = (
    _ wheel1: Int32,
    _ wheel2: Int32
) -> CGEvent?
public typealias ProductBaseEventFactory = () -> CGEvent?
public typealias ProductEventPostOperation = (_ event: CGEvent) -> Bool
public typealias ProductPostedEventObserver = (
    _ trace: ProductGestureOutputPostedEventTrace
) -> Void

public enum TrackpadGestureOutputResources {
    public static let contractRelativePath = "TrackpadContracts/25F80/scroll-momentum-contract.json"
    public static let modelRelativePath = "TrackpadContracts/25F80/scroll-output-model.json"
    public static let dockSwipeTemplatesRelativePath =
        "TrackpadContracts/25F80/recognized-dockswipe-templates.json"
    public static let repositoryContractRelativePath =
        "Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json"
    public static let repositoryModelRelativePath =
        "Fixtures/trackpad-contract/25F80/scroll-output-model.json"
    public static let repositoryDockSwipeTemplatesRelativePath =
        "Fixtures/trackpad-contract/25F80/recognized-dockswipe-templates.json"

    public static func loadContractData(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> Data? {
        loadData(
            explicitPath: environment["NAPE_GESTURE_TRACKPAD_CONTRACT"],
            bundleRelativePath: contractRelativePath,
            repositoryRelativePath: repositoryContractRelativePath,
            bundle: bundle,
            currentDirectoryPath: currentDirectoryPath
        )
    }

    public static func loadModelData(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> Data? {
        loadData(
            explicitPath: environment["NAPE_GESTURE_TRACKPAD_OUTPUT_MODEL"],
            bundleRelativePath: modelRelativePath,
            repositoryRelativePath: repositoryModelRelativePath,
            bundle: bundle,
            currentDirectoryPath: currentDirectoryPath
        )
    }

    public static func loadDockSwipeTemplateData(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> Data? {
        loadData(
            explicitPath: environment["NAPE_GESTURE_DOCKSWIPE_TEMPLATES"],
            bundleRelativePath: dockSwipeTemplatesRelativePath,
            repositoryRelativePath: repositoryDockSwipeTemplatesRelativePath,
            bundle: bundle,
            currentDirectoryPath: currentDirectoryPath
        )
    }

    private static func loadData(
        explicitPath: String?,
        bundleRelativePath: String,
        repositoryRelativePath: String,
        bundle: Bundle,
        currentDirectoryPath: String
    ) -> Data? {
        let fileManager = FileManager.default
        if let explicitPath {
            let url = URL(fileURLWithPath: explicitPath)
            guard fileManager.isReadableFile(atPath: url.path),
                let data = try? Data(contentsOf: url),
                !data.isEmpty
            else {
                return nil
            }
            return data
        }

        var candidates: [URL] = []
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleRelativePath))
        }
        candidates.append(
            URL(fileURLWithPath: currentDirectoryPath)
                .appendingPathComponent(repositoryRelativePath)
        )
        for url in candidates where fileManager.isReadableFile(atPath: url.path) {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }
}

public final class TrackpadScrollCGEventBuilder {
    private let contract: TrackpadScrollMomentumContractFixture
    private let scrollEventFactory: ProductScrollEventFactory
    private let baseEventFactory: ProductBaseEventFactory

    public static var supportsRawFieldLayout: Bool {
        MemoryLayout<CGEventField>.size == MemoryLayout<UInt32>.size
    }

    public init(
        contract: TrackpadScrollMomentumContractFixture,
        scrollEventFactory: @escaping ProductScrollEventFactory = { wheel1, wheel2 in
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: wheel1,
                wheel2: wheel2,
                wheel3: 0
            )
        },
        baseEventFactory: @escaping ProductBaseEventFactory = {
            CGEvent(source: nil)
        }
    ) {
        self.contract = contract
        self.scrollEventFactory = scrollEventFactory
        self.baseEventFactory = baseEventFactory
    }

    public func makeEvent(from specification: TrackpadScrollPreparedEvent) -> CGEvent? {
        guard Self.supportsRawFieldLayout else {
            return nil
        }
        let event: CGEvent?
        switch specification.kind {
        case .scroll:
            event = makeScrollEvent(from: specification)
        case .envelope:
            event = makeCompanionEvent(
                from: specification,
                classifier: contract.scrollCompanion.envelopeClassifierValue
            )
        case .companion:
            event = makeCompanionEvent(
                from: specification,
                classifier: contract.scrollCompanion.classifierValue
            )
        }
        guard let event, event.data != nil, validate(event, specification: specification) else {
            return nil
        }
        return event
    }

    private func makeScrollEvent(
        from specification: TrackpadScrollPreparedEvent
    ) -> CGEvent? {
        guard let wheel1 = int32(specification.deltaY.point),
            let wheel2 = int32(specification.deltaX.point),
            let event = scrollEventFactory(wheel1, wheel2)
        else {
            return nil
        }
        configureCommon(
            event,
            typeRaw: contract.scroll.eventTypeRaw,
            timestamp: specification.timestamp
        )
        setScrollDeltas(event, specification: specification)
        event.setIntegerValueField(
            rawField(contract.scroll.continuousRawField),
            value: contract.scroll.continuousValue
        )
        event.setIntegerValueField(
            rawField(contract.scroll.phaseRawField),
            value: specification.scrollPhase
        )
        event.setIntegerValueField(
            rawField(contract.momentum.phaseRawField),
            value: specification.momentumPhase
        )
        event.setIntegerValueField(rawField(contract.scrollCompanion.classifierRawField), value: 0)
        event.setIntegerValueField(rawField(124), value: 0)
        event.setIntegerValueField(rawField(contract.scrollCompanion.phaseRawField), value: 0)
        event.setIntegerValueField(rawField(135), value: 0)
        return event
    }

    private func makeCompanionEvent(
        from specification: TrackpadScrollPreparedEvent,
        classifier: Int64
    ) -> CGEvent? {
        guard let event = baseEventFactory(),
            let eventType = CGEventType(rawValue: UInt32(contract.scrollCompanion.eventTypeRaw))
        else {
            return nil
        }
        event.type = eventType
        configureCommon(
            event,
            typeRaw: contract.scrollCompanion.eventTypeRaw,
            timestamp: specification.timestamp
        )
        event.setIntegerValueField(rawField(contract.scroll.continuousRawField), value: 0)
        event.setIntegerValueField(rawField(contract.scroll.phaseRawField), value: 0)
        event.setIntegerValueField(
            rawField(contract.scrollCompanion.classifierRawField),
            value: classifier
        )
        for (fieldText, value) in contract.scrollCompanion.constantRawFields {
            guard let field = Int(fieldText) else {
                return nil
            }
            event.setIntegerValueField(rawField(field), value: value)
        }
        event.setIntegerValueField(
            rawField(contract.scrollCompanion.phaseRawField),
            value: specification.companionPhase
        )
        event.setIntegerValueField(
            rawField(135), value: classifier == contract.scrollCompanion.classifierValue ? 1 : 0)
        setMotionAliases(
            event,
            xMotion: specification.deltaX.gesture,
            yMotion: specification.deltaY.gesture
        )
        return event
    }

    private func configureCommon(
        _ event: CGEvent,
        typeRaw: Int,
        timestamp: MonotonicEventTimestamp
    ) {
        event.timestamp = CGEventTimestamp(timestamp.nanosecondsSinceStartup)
        event.setIntegerValueField(rawField(39), value: 0)
        event.setIntegerValueField(rawField(40), value: 0)
        event.setIntegerValueField(
            .eventSourceUserData,
            value: NapeGestureGeneratedEventMarker.value
        )
        event.setIntegerValueField(
            rawField(contract.common.typeRawField),
            value: Int64(typeRaw)
        )
        event.setIntegerValueField(
            rawField(contract.common.timestampRawField),
            value: Int64(timestamp.nanosecondsSinceStartup)
        )
    }

    private func setScrollDeltas(
        _ event: CGEvent,
        specification: TrackpadScrollPreparedEvent
    ) {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: specification.deltaY.line)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: specification.deltaX.line)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis3, value: 0)
        event.setDoubleValueField(
            .scrollWheelEventFixedPtDeltaAxis1, value: specification.deltaY.fixed)
        event.setDoubleValueField(
            .scrollWheelEventFixedPtDeltaAxis2, value: specification.deltaX.fixed)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3, value: 0.0)
        event.setDoubleValueField(
            .scrollWheelEventPointDeltaAxis1, value: specification.deltaY.point)
        event.setDoubleValueField(
            .scrollWheelEventPointDeltaAxis2, value: specification.deltaX.point)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis3, value: 0.0)
    }

    private func setMotionAliases(
        _ event: CGEvent,
        xMotion: Float,
        yMotion: Float
    ) {
        for field in contract.scrollCompanion.xMotionDoubleFields {
            event.setDoubleValueField(rawField(field), value: Double(xMotion))
        }
        for field in contract.scrollCompanion.xMotionFloatBitFields {
            event.setIntegerValueField(rawField(field), value: Int64(UInt64(xMotion.bitPattern)))
        }
        for field in contract.scrollCompanion.yMotionDoubleFields {
            event.setDoubleValueField(rawField(field), value: Double(yMotion))
        }
        for field in contract.scrollCompanion.yMotionFloatBitFields {
            event.setIntegerValueField(rawField(field), value: Int64(UInt64(yMotion.bitPattern)))
        }
    }

    private func validate(
        _ event: CGEvent,
        specification: TrackpadScrollPreparedEvent
    ) -> Bool {
        let expectedType: Int
        switch specification.kind {
        case .scroll:
            expectedType = contract.scroll.eventTypeRaw
        case .envelope, .companion:
            expectedType = contract.scrollCompanion.eventTypeRaw
        }
        guard event.type.rawValue == UInt32(expectedType),
            event.timestamp == specification.timestamp.nanosecondsSinceStartup,
            event.getIntegerValueField(rawField(39)) == 0,
            event.getIntegerValueField(rawField(40)) == 0,
            event.getIntegerValueField(.eventSourceUserData)
                == NapeGestureGeneratedEventMarker.value,
            event.getIntegerValueField(rawField(contract.common.typeRawField)) == expectedType,
            event.getIntegerValueField(rawField(contract.common.timestampRawField))
                == Int64(specification.timestamp.nanosecondsSinceStartup)
        else {
            return false
        }

        switch specification.kind {
        case .scroll:
            return validateScroll(event, specification: specification)
        case .envelope:
            return validateCompanion(
                event,
                specification: specification,
                classifier: contract.scrollCompanion.envelopeClassifierValue
            )
        case .companion:
            return validateCompanion(
                event,
                specification: specification,
                classifier: contract.scrollCompanion.classifierValue
            )
        }
    }

    private func validateScroll(
        _ event: CGEvent,
        specification: TrackpadScrollPreparedEvent
    ) -> Bool {
        event.getIntegerValueField(rawField(contract.scroll.continuousRawField))
            == contract.scroll.continuousValue
            && event.getIntegerValueField(rawField(contract.scroll.phaseRawField))
                == specification.scrollPhase
            && event.getIntegerValueField(rawField(contract.momentum.phaseRawField))
                == specification.momentumPhase
            && event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == specification.deltaY.line
            && event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == specification.deltaX.line
            && event.getIntegerValueField(.scrollWheelEventDeltaAxis3) == 0
            && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1).bitPattern
                == specification.deltaY.fixed.bitPattern
            && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2).bitPattern
                == specification.deltaX.fixed.bitPattern
            && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3).bitPattern
                == Double(0.0).bitPattern
            && event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1).bitPattern
                == specification.deltaY.point.bitPattern
            && event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2).bitPattern
                == specification.deltaX.point.bitPattern
            && event.getDoubleValueField(.scrollWheelEventPointDeltaAxis3).bitPattern
                == Double(0.0).bitPattern
    }

    private func validateCompanion(
        _ event: CGEvent,
        specification: TrackpadScrollPreparedEvent,
        classifier: Int64
    ) -> Bool {
        guard
            event.getIntegerValueField(rawField(contract.scrollCompanion.classifierRawField))
                == classifier,
            event.getIntegerValueField(rawField(contract.scrollCompanion.phaseRawField))
                == specification.companionPhase,
            event.getIntegerValueField(rawField(135))
                == (classifier == contract.scrollCompanion.classifierValue ? 1 : 0)
        else {
            return false
        }
        if classifier == contract.scrollCompanion.classifierValue {
            for (fieldText, value) in contract.scrollCompanion.constantRawFields {
                guard let field = Int(fieldText),
                    event.getIntegerValueField(rawField(field)) == value
                else {
                    return false
                }
            }
        }
        return validateMotionAliases(
            event,
            doubleFields: contract.scrollCompanion.xMotionDoubleFields,
            bitFields: contract.scrollCompanion.xMotionFloatBitFields,
            expected: specification.deltaX.gesture
        )
            && validateMotionAliases(
                event,
                doubleFields: contract.scrollCompanion.yMotionDoubleFields,
                bitFields: contract.scrollCompanion.yMotionFloatBitFields,
                expected: specification.deltaY.gesture
            )
    }

    private func validateMotionAliases(
        _ event: CGEvent,
        doubleFields: [Int],
        bitFields: [Int],
        expected: Float
    ) -> Bool {
        doubleFields.allSatisfy {
            event.getDoubleValueField(rawField($0)).bitPattern == Double(expected).bitPattern
        }
            && bitFields.allSatisfy {
                event.getIntegerValueField(rawField($0)) == Int64(UInt64(expected.bitPattern))
            }
    }

    private func int32(_ value: Double) -> Int32? {
        guard value.isFinite,
            value >= Double(Int32.min),
            value <= Double(Int32.max)
        else {
            return nil
        }
        return Int32(value.rounded())
    }

    private func rawField(_ number: Int) -> CGEventField {
        unsafeBitCast(UInt32(number), to: CGEventField.self)
    }
}

public final class TrackpadGestureOutputAdapter: ProductGestureOutput {
    private struct SessionRecord {
        var machine: TrackpadOutputSessionMachine
        var inFlight: InFlightBatch?
        var gesturePolarity: RecognizedDockSwipeTemplatePolarity?

        init(
            machine: TrackpadOutputSessionMachine,
            inFlight: InFlightBatch?,
            gesturePolarity: RecognizedDockSwipeTemplatePolarity? = nil
        ) {
            self.machine = machine
            self.inFlight = inFlight
            self.gesturePolarity = gesturePolarity
        }
    }

    private struct InFlightBatch {
        var sourceEvent: TrackpadOutputSessionEvent
        var candidateMachine: TrackpadOutputSessionMachine
        var specifications: [TrackpadScrollPreparedEvent]
        var events: [CGEvent]
        var firstPostIndex: UInt64
        var nextOffset: Int
        var emitsTerminalBatch: Bool
    }

    public let capability: ProductGestureOutputCapability

    private let model: TrackpadScrollOutputModel?
    private let builder: TrackpadScrollCGEventBuilder?
    private let gestureBuilder: TrackpadGestureCandidateCGEventBuilder?
    private let postEvent: ProductEventPostOperation
    private let postedEventObserver: ProductPostedEventObserver?
    private let traceContext: ProductGestureOutputTraceContext?
    private let lock = NSLock()
    private var sessions: [TrackpadOutputSessionID: SessionRecord] = [:]
    private var nextPostIndex: UInt64
    private var isPosting = false
    private var resetRequested = false

    public convenience init() {
        self.init(
            contractData: TrackpadGestureOutputResources.loadContractData(),
            modelData: TrackpadGestureOutputResources.loadModelData(),
            dockSwipeTemplateData: TrackpadGestureOutputResources.loadDockSwipeTemplateData()
        )
    }

    public init(
        contractData: Data?,
        modelData: Data? = TrackpadGestureOutputResources.loadModelData(),
        dockSwipeTemplateData: Data? = TrackpadGestureOutputResources.loadDockSwipeTemplateData(),
        systemIdentity: ProductGestureOutputSystemIdentity? = .current(),
        traceContext: ProductGestureOutputTraceContext? = nil,
        scrollEventFactory: @escaping ProductScrollEventFactory = { wheel1, wheel2 in
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: wheel1,
                wheel2: wheel2,
                wheel3: 0
            )
        },
        baseEventFactory: @escaping ProductBaseEventFactory = {
            CGEvent(source: nil)
        },
        postEvent: @escaping ProductEventPostOperation = { event in
            event.post(tap: .cghidEventTap)
            return true
        },
        postedEventObserver: ProductPostedEventObserver? = nil,
        initialPostIndex: UInt64 = 0
    ) {
        self.postEvent = postEvent
        self.postedEventObserver = postedEventObserver
        self.traceContext = traceContext
        nextPostIndex = initialPostIndex
        guard let contractData else {
            capability = .unsupported(
                reason: "trackpad output contract resourceが見つかりません。"
            )
            model = nil
            builder = nil
            gestureBuilder = nil
            return
        }

        let validatedCapability = ProductGestureOutputCapability.validated(
            fixtureData: contractData,
            systemIdentity: systemIdentity
        )
        guard validatedCapability.isSupported,
            let verifiedContract = validatedCapability.contract,
            let document = TrackpadScrollMomentumContractDocumentReader.read(data: contractData)
                .document,
            let modelData,
            let registeredModel = TrackpadScrollOutputModelFixtureReader.read(
                modelData: modelData,
                contract: verifiedContract
            ),
            let dockSwipeTemplateData,
            let recognizedGestureAdapter = RecognizedGestureIOHIDCompatibilityAdapter(
                fixtureData: dockSwipeTemplateData,
                contract: verifiedContract
            ),
            TrackpadScrollCGEventBuilder.supportsRawFieldLayout,
            let outputModel = try? TrackpadScrollOutputModel(
                contract: document.fixture,
                parameters: registeredModel.parameters
            )
        else {
            if !validatedCapability.isSupported {
                capability = validatedCapability
            } else if modelData == nil {
                capability = .unsupported(reason: "trackpad scroll output model resourceが見つかりません。")
            } else if dockSwipeTemplateData == nil {
                capability = .unsupported(reason: "DockSwipe template resourceが見つかりません。")
            } else if !TrackpadScrollCGEventBuilder.supportsRawFieldLayout {
                capability = .unsupported(
                    reason: "この環境では25F80 raw CGEvent field layoutを安全に構成できません。")
            } else {
                capability = .contractMismatch(
                    contract: validatedCapability.contract,
                    reason: "trackpad scroll output modelまたはDockSwipe templateのidentity、SHA、OS contractが登録値と一致しません。"
                )
            }
            model = nil
            builder = nil
            gestureBuilder = nil
            return
        }

        capability = validatedCapability
        model = outputModel
        builder = TrackpadScrollCGEventBuilder(
            contract: document.fixture,
            scrollEventFactory: scrollEventFactory,
            baseEventFactory: baseEventFactory
        )
        gestureBuilder = TrackpadGestureCandidateCGEventBuilder(
            contract: document.fixture,
            compatibilityAdapter: recognizedGestureAdapter
        )
    }

    public func supports(_ family: TrackpadOutputEventFamily) -> Bool {
        guard capability.isSupported, capability.supportedFamilies.contains(family) else {
            return false
        }
        switch family {
        case .scroll:
            return model != nil && builder != nil
        case .dockSwipe, .dockSwipePinch:
            return gestureBuilder != nil
        }
    }

    public func post(_ event: TrackpadOutputSessionEvent) -> ProductGestureOutputResult {
        lock.lock()
        guard !isPosting else {
            lock.unlock()
            return .rejected(.invalidSession)
        }

        if let capabilityFailure = capability.failure {
            lock.unlock()
            return .rejected(capabilityFailure)
        }
        isPosting = true
        lock.unlock()

        defer { finishPosting() }
        return postValidated(event)
    }

    public func reset() {
        lock.lock()
        if isPosting {
            resetRequested = true
        } else {
            sessions.removeAll()
        }
        lock.unlock()
    }

    private func finishPosting() {
        lock.lock()
        resetRequested = false
        isPosting = false
        lock.unlock()
    }

    private func postingAbortRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return resetRequested
    }

    private func postValidated(
        _ event: TrackpadOutputSessionEvent
    ) -> ProductGestureOutputResult {
        guard supports(event.family) else {
            return .rejected(.unsupported)
        }
        guard postedEventObserver == nil || traceContext != nil else {
            return eventCreationFailure("posted event observerにtrace contextがありません。")
        }
        if event.family != .scroll {
            return postCandidateGesture(event)
        }
        guard let model, let builder else {
            return .rejected(.unsupported)
        }

        // 予約済みpostIndexと実投稿順を一致させるため、部分投稿の解消までは
        // 別sessionへ切り替えない。
        guard
            !sessions.contains(where: {
                $0.key != event.sessionID && $0.value.inFlight != nil
            })
        else {
            return .rejected(.invalidSession)
        }

        if let record = sessions[event.sessionID], let inFlight = record.inFlight {
            if isRetry(event, of: inFlight.sourceEvent) {
                return deliver(
                    inFlight,
                    baselineMachine: record.machine,
                    rollbackRecord: record
                )
            }
            guard case .cancellation = event else {
                return .rejected(.invalidSession)
            }
            return cancel(
                event, replacing: inFlight, record: record, model: model, builder: builder)
        }

        let existingRecord = sessions[event.sessionID]
        let machine: TrackpadOutputSessionMachine
        if let existingRecord {
            machine = existingRecord.machine
        } else if case .input(let frame) = event, frame.phase == .began {
            machine = TrackpadOutputSessionMachine(
                sessionID: event.sessionID,
                family: event.family,
                initialCaptureOrder: event.captureOrder
            )
        } else {
            return .rejected(.invalidSession)
        }

        return makeAndDeliverBatch(
            event,
            baselineMachine: machine,
            modelPreviousState: machine.state,
            rollbackRecord: existingRecord,
            model: model,
            builder: builder
        )
    }

    private func postCandidateGesture(
        _ event: TrackpadOutputSessionEvent
    ) -> ProductGestureOutputResult {
        guard let gestureBuilder else {
            return eventCreationFailure("gesture builderがありません。")
        }
        guard let specification = TrackpadGestureCandidatePreparedEvent(event) else {
            return eventCreationFailure("gesture specificationを構成できません。")
        }

        let existing = sessions[event.sessionID]
        var machine: TrackpadOutputSessionMachine
        let polarity: RecognizedDockSwipeTemplatePolarity
        if let existing {
            guard existing.inFlight == nil, let existingPolarity = existing.gesturePolarity else {
                return .rejected(.invalidSession)
            }
            machine = existing.machine
            polarity = existingPolarity
        } else if case .input(let frame) = event, frame.phase == .began {
            guard let initialPolarity = Self.gesturePolarity(for: specification.payload) else {
                return eventCreationFailure("gesture開始時の進行方向を確定できません。")
            }
            machine = TrackpadOutputSessionMachine(
                sessionID: event.sessionID,
                family: event.family,
                initialCaptureOrder: event.captureOrder
            )
            polarity = initialPolarity
        } else {
            return .rejected(.invalidSession)
        }
        do {
            try machine.accept(event)
        } catch {
            return .rejected(.invalidSession)
        }
        guard let preparedEvent = gestureBuilder.makeEvent(
            from: specification,
            polarity: polarity
        ) else {
            return eventCreationFailure(
                "gesture eventを構成できません。family=\(event.family.rawValue) phase=\(specification.phase)"
            )
        }

        let processSerialNumber = preparedEvent.getIntegerValueField(rawField(39))
        let unixProcessID = preparedEvent.getIntegerValueField(rawField(40))
        guard processSerialNumber == 0, unixProcessID == 0 else {
            return eventCreationFailure("gesture eventに対象process情報が混入しました。")
        }
        let nextIndex = nextPostIndex.addingReportingOverflow(1)
        guard !nextIndex.overflow else {
            return .rejected(.eventPostFailed)
        }
        let trace: ProductGestureOutputPostedEventTrace?
        if let traceContext, postedEventObserver != nil {
            trace = ProductGestureOutputPostedEventTrace(
                postIndex: nextPostIndex,
                sessionID: event.sessionID,
                family: event.family,
                eventTimestamp: UInt64(preparedEvent.timestamp),
                eventTypeRaw: Int(preparedEvent.type.rawValue),
                delivery: .systemWide,
                eventKind: .gesture,
                traceContext: traceContext,
                prePostTargetProcessSerialNumber: processSerialNumber,
                prePostTargetUnixProcessID: unixProcessID
            )
        } else {
            trace = nil
        }
        guard postEvent(preparedEvent) else {
            return .rejected(.eventPostFailed)
        }
        nextPostIndex = nextIndex.partialValue
        if case .terminal = machine.state {
            sessions.removeValue(forKey: event.sessionID)
        } else {
            sessions[event.sessionID] = SessionRecord(
                machine: machine,
                inFlight: nil,
                gesturePolarity: polarity
            )
        }
        if let trace {
            postedEventObserver?(trace)
        }
        return ProductGestureOutputResult(
            generatedEventCount: 1,
            failedEventCreationCount: 0
        )
    }

    private static func gesturePolarity(
        for payload: TrackpadOutputPayload
    ) -> RecognizedDockSwipeTemplatePolarity? {
        let value: Double
        switch payload {
        case let .dockSwipe(_, progress, motionX, motionY, terminalVelocityX, _):
            value = firstNonzero(progress, motionX, motionY, terminalVelocityX)
        case let .dockSwipePinch(progress, motion, terminalVelocity):
            value = firstNonzero(progress, motion, terminalVelocity)
        case .scroll:
            return nil
        }
        guard value.isFinite, value != 0 else {
            return nil
        }
        return value > 0 ? .positive : .negative
    }

    private static func firstNonzero(_ values: Double...) -> Double {
        values.first(where: { $0 != 0 }) ?? 0
    }

    private func cancel(
        _ cancellation: TrackpadOutputSessionEvent,
        replacing inFlight: InFlightBatch,
        record: SessionRecord,
        model: TrackpadScrollOutputModel,
        builder: TrackpadScrollCGEventBuilder
    ) -> ProductGestureOutputResult {
        if inFlight.emitsTerminalBatch {
            let resumed = deliver(
                inFlight,
                baselineMachine: record.machine,
                rollbackRecord: record
            )
            guard resumed.failure == nil,
                let remainingRecord = sessions[cancellation.sessionID]
            else {
                return resumed
            }
            guard
                let followup = cancellationAfterCompletedTerminalBatch(
                    cancellation,
                    machine: remainingRecord.machine
                )
            else {
                return ProductGestureOutputResult(
                    generatedEventCount: resumed.generatedEventCount,
                    failedEventCreationCount: 0,
                    failure: .invalidSession
                )
            }
            let followupResult = makeAndDeliverBatch(
                followup,
                baselineMachine: remainingRecord.machine,
                modelPreviousState: remainingRecord.machine.state,
                rollbackRecord: remainingRecord,
                model: model,
                builder: builder
            )
            return combining(resumed, with: followupResult)
        }

        guard cancellation.timestamp >= inFlight.sourceEvent.timestamp else {
            return .rejected(.invalidSession)
        }

        return makeAndDeliverBatch(
            cancellation,
            baselineMachine: record.machine,
            modelPreviousState: inFlight.candidateMachine.state,
            rollbackRecord: record,
            model: model,
            builder: builder
        )
    }

    private func makeAndDeliverBatch(
        _ event: TrackpadOutputSessionEvent,
        baselineMachine: TrackpadOutputSessionMachine,
        modelPreviousState: TrackpadOutputSessionState,
        rollbackRecord: SessionRecord?,
        model: TrackpadScrollOutputModel,
        builder: TrackpadScrollCGEventBuilder
    ) -> ProductGestureOutputResult {
        var candidateMachine = baselineMachine
        do {
            try candidateMachine.accept(event)
        } catch {
            return .rejected(.invalidSession)
        }

        let specifications: [TrackpadScrollPreparedEvent]
        do {
            specifications = try model.prepare(
                event: event,
                previousState: modelPreviousState
            )
        } catch {
            return eventCreationFailure("scroll model.prepare: \(String(describing: error))")
        }
        var events: [CGEvent] = []
        events.reserveCapacity(specifications.count)
        for (index, specification) in specifications.enumerated() {
            guard let preparedEvent = builder.makeEvent(from: specification) else {
                return eventCreationFailure(
                    "scroll event builder: index=\(index) kind=\(String(describing: specification.kind)) deltaX=\(specification.deltaX) deltaY=\(specification.deltaY)"
                )
            }
            events.append(preparedEvent)
        }
        guard let firstPostIndex = preflightPostIndexes(count: events.count) else {
            return .rejected(.eventPostFailed)
        }

        return deliver(
            InFlightBatch(
                sourceEvent: event,
                candidateMachine: candidateMachine,
                specifications: specifications,
                events: events,
                firstPostIndex: firstPostIndex,
                nextOffset: 0,
                emitsTerminalBatch: emitsTerminalBatch(event)
            ),
            baselineMachine: baselineMachine,
            rollbackRecord: rollbackRecord
        )
    }

    private func deliver(
        _ pendingBatch: InFlightBatch,
        baselineMachine: TrackpadOutputSessionMachine,
        rollbackRecord: SessionRecord?
    ) -> ProductGestureOutputResult {
        var batch = pendingBatch
        var generatedEventCount = 0

        while batch.nextOffset < batch.events.count {
            if postingAbortRequested() {
                preserveFailedBatch(
                    batch,
                    baselineMachine: baselineMachine,
                    rollbackRecord: rollbackRecord
                )
                return ProductGestureOutputResult(
                    generatedEventCount: generatedEventCount,
                    failedEventCreationCount: 0,
                    failure: .eventPostFailed
                )
            }
            let offset = batch.nextOffset
            let preparedEvent = batch.events[offset]
            let specification = batch.specifications[offset]
            let processSerialNumber = preparedEvent.getIntegerValueField(rawField(39))
            let unixProcessID = preparedEvent.getIntegerValueField(rawField(40))
            guard processSerialNumber == 0, unixProcessID == 0 else {
                preserveFailedBatch(
                    batch,
                    baselineMachine: baselineMachine,
                    rollbackRecord: rollbackRecord
                )
                return ProductGestureOutputResult(
                    generatedEventCount: generatedEventCount,
                    failedEventCreationCount: 1,
                    failure: .eventCreationFailed
                )
            }

            let postIndexResult = batch.firstPostIndex.addingReportingOverflow(
                UInt64(offset)
            )
            let nextIndexResult = nextPostIndex.addingReportingOverflow(1)
            guard !postIndexResult.overflow,
                postIndexResult.partialValue == nextPostIndex,
                !nextIndexResult.overflow
            else {
                preserveFailedBatch(
                    batch,
                    baselineMachine: baselineMachine,
                    rollbackRecord: rollbackRecord
                )
                return ProductGestureOutputResult(
                    generatedEventCount: generatedEventCount,
                    failedEventCreationCount: 0,
                    failure: .eventPostFailed
                )
            }

            let trace: ProductGestureOutputPostedEventTrace?
            if postedEventObserver != nil {
                guard let traceContext else {
                    preserveFailedBatch(
                        batch,
                        baselineMachine: baselineMachine,
                        rollbackRecord: rollbackRecord
                    )
                    return ProductGestureOutputResult(
                        generatedEventCount: generatedEventCount,
                        failedEventCreationCount: 1,
                        failure: .eventCreationFailed
                    )
                }
                trace = ProductGestureOutputPostedEventTrace(
                    postIndex: postIndexResult.partialValue,
                    sessionID: batch.sourceEvent.sessionID,
                    family: batch.sourceEvent.family,
                    eventTimestamp: UInt64(preparedEvent.timestamp),
                    eventTypeRaw: Int(preparedEvent.type.rawValue),
                    delivery: .systemWide,
                    eventKind: specification.kind == .scroll ? .scroll : .gesture,
                    traceContext: traceContext,
                    prePostTargetProcessSerialNumber: processSerialNumber,
                    prePostTargetUnixProcessID: unixProcessID
                )
            } else {
                trace = nil
            }

            guard postEvent(preparedEvent) else {
                preserveFailedBatch(
                    batch,
                    baselineMachine: baselineMachine,
                    rollbackRecord: rollbackRecord
                )
                return ProductGestureOutputResult(
                    generatedEventCount: generatedEventCount,
                    failedEventCreationCount: 0,
                    failure: .eventPostFailed
                )
            }

            nextPostIndex = nextIndexResult.partialValue
            batch.nextOffset += 1
            generatedEventCount += 1
            if let trace {
                postedEventObserver?(trace)
            }
            if postingAbortRequested() {
                preserveFailedBatch(
                    batch,
                    baselineMachine: baselineMachine,
                    rollbackRecord: rollbackRecord
                )
                return ProductGestureOutputResult(
                    generatedEventCount: generatedEventCount,
                    failedEventCreationCount: 0,
                    failure: .eventPostFailed
                )
            }
        }

        if case .terminal = batch.candidateMachine.state {
            sessions.removeValue(forKey: batch.sourceEvent.sessionID)
        } else {
            sessions[batch.sourceEvent.sessionID] = SessionRecord(
                machine: batch.candidateMachine,
                inFlight: nil
            )
        }
        return ProductGestureOutputResult(
            generatedEventCount: generatedEventCount,
            failedEventCreationCount: 0
        )
    }

    private func preserveFailedBatch(
        _ batch: InFlightBatch,
        baselineMachine: TrackpadOutputSessionMachine,
        rollbackRecord: SessionRecord?
    ) {
        if batch.nextOffset == 0 {
            if let rollbackRecord {
                sessions[batch.sourceEvent.sessionID] = rollbackRecord
            } else {
                sessions.removeValue(forKey: batch.sourceEvent.sessionID)
            }
            return
        }
        sessions[batch.sourceEvent.sessionID] = SessionRecord(
            machine: baselineMachine,
            inFlight: batch
        )
    }

    private func preflightPostIndexes(count: Int) -> UInt64? {
        guard let count = UInt64(exactly: count) else {
            return nil
        }
        let firstPostIndex = nextPostIndex
        let reservation = firstPostIndex.addingReportingOverflow(count)
        guard !reservation.overflow else {
            return nil
        }
        return firstPostIndex
    }

    private func cancellationAfterCompletedTerminalBatch(
        _ event: TrackpadOutputSessionEvent,
        machine: TrackpadOutputSessionMachine
    ) -> TrackpadOutputSessionEvent? {
        guard case .cancellation(let frame) = event,
            let lastCaptureOrder = machine.lastCaptureOrder
        else {
            return nil
        }
        let nextCaptureOrder = lastCaptureOrder.addingReportingOverflow(1)
        guard !nextCaptureOrder.overflow else {
            return nil
        }
        let timestamp = max(frame.timestamp, machine.lastTimestamp ?? frame.timestamp)
        return .cancellation(
            TrackpadOutputCancellationFrame(
                sessionID: machine.sessionID,
                captureOrder: nextCaptureOrder.partialValue,
                timestamp: timestamp,
                family: machine.family,
                reason: frame.reason,
                payload: machine.lastPayload ?? frame.payload
            )
        )
    }

    private func isRetry(
        _ event: TrackpadOutputSessionEvent,
        of pendingEvent: TrackpadOutputSessionEvent
    ) -> Bool {
        if event == pendingEvent {
            return true
        }
        guard case .cancellation(let eventFrame) = event,
            case .cancellation(let pendingFrame) = pendingEvent
        else {
            return false
        }
        return eventFrame.sessionID == pendingFrame.sessionID
            && eventFrame.captureOrder == pendingFrame.captureOrder
            && eventFrame.family == pendingFrame.family
            && eventFrame.reason == pendingFrame.reason
            && eventFrame.payload == pendingFrame.payload
    }

    private func emitsTerminalBatch(_ event: TrackpadOutputSessionEvent) -> Bool {
        switch event {
        case .input(let frame):
            frame.phase == .ended || frame.phase == .cancelled
        case .momentum(let frame):
            frame.phase == .ended
        case .cancellation:
            true
        }
    }

    private func eventCreationFailure(_ details: String) -> ProductGestureOutputResult {
        ProductGestureOutputResult(
            generatedEventCount: 0,
            failedEventCreationCount: 1,
            failure: .eventCreationFailed,
            failureDetails: details
        )
    }

    private func combining(
        _ prefix: ProductGestureOutputResult,
        with suffix: ProductGestureOutputResult
    ) -> ProductGestureOutputResult {
        ProductGestureOutputResult(
            generatedEventCount: prefix.generatedEventCount + suffix.generatedEventCount,
            failedEventCreationCount: prefix.failedEventCreationCount
                + suffix.failedEventCreationCount,
            failure: suffix.failure,
            failureDetails: suffix.failureDetails ?? prefix.failureDetails
        )
    }

    private func rawField(_ number: Int) -> CGEventField {
        unsafeBitCast(UInt32(number), to: CGEventField.self)
    }
}
