import CoreGraphics
import Foundation
import NapeGestureCore

final class NapeGestureDaemon {
    private var recognizer: GestureRecognizer
    private var momentum: MomentumEngine
    private let actionExecutor: GestureActionExecutor
    private let configuration: GestureConfiguration
    private let targetGate: SharedTargetDeviceGate?
    private let hidInputMonitor: HIDInputMonitor?
    private let performanceRecorder: RuntimePerformanceRecording?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var momentumTimer: DispatchSourceTimer?
    private var safetyState = RuntimeSafetyState()
    private var performanceOperationSequence = 0

    init(
        configuration: GestureConfiguration,
        targetGate: SharedTargetDeviceGate? = nil,
        hidInputMonitor: HIDInputMonitor? = nil,
        performanceRecorder: RuntimePerformanceRecording? = nil
    ) {
        self.configuration = configuration
        self.targetGate = targetGate
        self.hidInputMonitor = hidInputMonitor
        self.performanceRecorder = performanceRecorder
        actionExecutor = GestureActionExecutor(bindings: configuration.bindings)
        recognizer = GestureRecognizer(configuration: configuration)
        momentum = MomentumEngine(configuration: configuration.momentum)
    }

    deinit {
        stop()
        hidInputMonitor?.stop()
    }

    func run() throws {
        try start()
        writeOperationalLog("nape-gesture を開始しました。停止するには Ctrl-C を押してください。")
        writeOperationalLog("キルスイッチ: \(KillSwitchShortcut.displayName)")
        CFRunLoopRun()
    }

    func start() throws {
        try AccessibilityPermission.ensurePrompted()

        let mask = CGEventUtilities.eventMask(for: CGEventUtilities.observedMouseEventTypes)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            throw ToolError.eventTapCreationFailed
        }

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw ToolError.eventTapCreationFailed
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        cancelMomentum()
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let callbackStartedAt = performanceRecorder == nil ? 0 : monotonicNanoseconds()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if CGEventUtilities.isGeneratedByThisTool(event) {
            return Unmanaged.passUnretained(event)
        }

        if KillSwitchShortcut.matches(type: type, event: event) {
            let decision = emergencyStop(at: Double(event.timestamp) / 1_000_000_000.0)
            return decision.shouldSuppressOriginalEvent ? nil : Unmanaged.passUnretained(event)
        }

        guard safetyState.regularInputDecision().shouldProcessGestureInput,
              let input = CGEventUtilities.rawInput(from: type, event: event)
        else {
            return Unmanaged.passUnretained(event)
        }

        if let targetGate, !targetGate.shouldHandle(input) {
            return Unmanaged.passUnretained(event)
        }

        let decision = recognizer.handle(input)
        let performanceContext: RuntimePerformanceContext?
        if performanceRecorder == nil {
            performanceContext = nil
        } else {
            performanceContext = RuntimePerformanceContext(
                operationID: nextPerformanceOperationID(source: .eventTap),
                source: .eventTap,
                inputEventTimestampNanoseconds: event.timestamp,
                tapCallbackStartedAtNanoseconds: callbackStartedAt,
                recognizerFinishedAtNanoseconds: monotonicNanoseconds(),
                suppressedOriginal: decision.shouldSuppressOriginal
            )
        }
        handle(commands: decision.commands, performanceContext: performanceContext)

        if decision.shouldSuppressOriginal {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handle(
        commands: [GestureCommand],
        performanceContext: RuntimePerformanceContext? = nil,
        allowsMomentumStart: Bool = true
    ) {
        for command in commands {
            let shouldRecordPerformance = performanceContext != nil
            let postStartedAt = shouldRecordPerformance ? monotonicNanoseconds() : 0
            let postResult = actionExecutor.post(command: command)
            let postFinishedAt = shouldRecordPerformance ? monotonicNanoseconds() : 0
            recordRuntimePerformance(
                command: command,
                postResult: postResult,
                context: performanceContext,
                postStartedAtNanoseconds: postStartedAt,
                postFinishedAtNanoseconds: postFinishedAt
            )

            if allowsMomentumStart && command.phase == .ended && actionExecutor.supportsMomentum(for: command) {
                startMomentumIfNeeded(from: command)
            } else if command.phase == .cancelled {
                cancelMomentum()
            }
        }
    }

    private func startMomentumIfNeeded(from command: GestureCommand) {
        momentum.start(from: command)

        guard case .running = momentum.state else {
            cancelMomentum()
            return
        }

        momentumTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + configuration.momentum.frameInterval, repeating: configuration.momentum.frameInterval)
        timer.setEventHandler { [weak self] in
            self?.tickMomentum()
        }
        momentumTimer = timer
        timer.resume()
    }

    private func tickMomentum() {
        guard safetyState.regularInputDecision().shouldProcessGestureInput else {
            cancelMomentum()
            return
        }

        guard let command = momentum.tick(at: Date().timeIntervalSince1970) else {
            cancelMomentum()
            return
        }

        let performanceContext: RuntimePerformanceContext?
        if performanceRecorder == nil {
            performanceContext = nil
        } else {
            let now = monotonicNanoseconds()
            performanceContext = RuntimePerformanceContext(
                operationID: nextPerformanceOperationID(source: .momentumTimer),
                source: .momentumTimer,
                inputEventTimestampNanoseconds: nil,
                tapCallbackStartedAtNanoseconds: now,
                recognizerFinishedAtNanoseconds: now,
                suppressedOriginal: false
            )
        }
        handle(
            commands: [command],
            performanceContext: performanceContext,
            allowsMomentumStart: false
        )
        if command.phase == .ended {
            cancelMomentum()
        }
    }

    private func cancelMomentum() {
        momentumTimer?.cancel()
        momentumTimer = nil
        momentum = MomentumEngine(configuration: configuration.momentum)
    }

    private func emergencyStop(at time: TimeInterval) -> RuntimeSafetyDecision {
        let decision = safetyState.stopForKillSwitch(at: time)
        if decision.shouldCancelMomentum {
            cancelMomentum()
        }
        if decision.shouldCancelGesture {
            let cancelDecision = recognizer.handle(.cancel(time: time))
            handle(commands: cancelDecision.commands)
        }
        if decision.didEnterStoppedState {
            writeOperationalLog("キルスイッチによりジェスチャーを無効化しました。再開するには常駐UIの停止/開始、またはプロセス再起動を行ってください。")
        }
        return decision
    }

    private func writeOperationalLog(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private func recordRuntimePerformance(
        command: GestureCommand,
        postResult: GestureActionPostResult,
        context: RuntimePerformanceContext?,
        postStartedAtNanoseconds: UInt64,
        postFinishedAtNanoseconds: UInt64
    ) {
        guard let context else {
            return
        }
        performanceRecorder?.record(
            RuntimePerformanceRecord(
                operationID: context.operationID,
                source: context.source,
                action: postResult.action,
                commandKind: command.kind,
                commandPhase: command.phase,
                commandTimestamp: command.timestamp,
                inputEventTimestampNanoseconds: context.inputEventTimestampNanoseconds,
                tapCallbackStartedAtNanoseconds: context.tapCallbackStartedAtNanoseconds,
                recognizerFinishedAtNanoseconds: context.recognizerFinishedAtNanoseconds,
                postStartedAtNanoseconds: postStartedAtNanoseconds,
                postFinishedAtNanoseconds: postFinishedAtNanoseconds,
                generatedEventCount: postResult.generatedEventCount,
                failedEventCreationCount: postResult.failedEventCreationCount,
                suppressedOriginal: context.suppressedOriginal
            )
        )
    }

    private func nextPerformanceOperationID(source: RuntimePerformanceSource) -> String {
        performanceOperationSequence += 1
        return "\(source.rawValue)-\(performanceOperationSequence)"
    }

    private func monotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

private struct RuntimePerformanceContext {
    var operationID: String
    var source: RuntimePerformanceSource
    var inputEventTimestampNanoseconds: UInt64?
    var tapCallbackStartedAtNanoseconds: UInt64
    var recognizerFinishedAtNanoseconds: UInt64
    var suppressedOriginal: Bool
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let daemon = Unmanaged<NapeGestureDaemon>.fromOpaque(userInfo).takeUnretainedValue()
    return daemon.handle(proxy: proxy, type: type, event: event)
}
