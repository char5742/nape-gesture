import CoreGraphics
import Foundation
import NapeGestureCore
import NapeGestureProductOutput

final class NapeGestureDaemon {
    private var recognizer: FixedGestureInputRecognizer
    private let outputExecutor: GestureOutputExecutor
    private let targetGate: SharedTargetDeviceGate?
    private let hidInputMonitor: HIDInputMonitor?
    private let performanceRecorder: RuntimePerformanceRecording?
    private let onTerminalFailure: ((Error) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var safetyState = RuntimeSafetyState()
    private var performanceOperationSequence = 0
    private var terminalError: Error?
    private var cursorAnchorState = CursorAnchorState()
    private let warpCursor: (CGPoint) -> CGError

    init(
        cancellation: GestureCancellationConfiguration,
        systemGestureSensitivity: Double = GestureConfiguration.defaultSystemGestureSensitivity,
        targetGate: SharedTargetDeviceGate? = nil,
        hidInputMonitor: HIDInputMonitor? = nil,
        performanceRecorder: RuntimePerformanceRecording? = nil,
        productOutput: any ProductGestureOutput = TrackpadGestureOutputAdapter(),
        warpCursor: @escaping (CGPoint) -> CGError = { position in
            CGWarpMouseCursorPosition(position)
        },
        onTerminalFailure: ((Error) -> Void)? = nil
    ) {
        recognizer = FixedGestureInputRecognizer(cancellation: cancellation)
        outputExecutor = GestureOutputExecutor(
            output: productOutput,
            systemGestureSensitivity: systemGestureSensitivity
        )
        self.targetGate = targetGate
        self.hidInputMonitor = hidInputMonitor
        self.performanceRecorder = performanceRecorder
        self.warpCursor = warpCursor
        self.onTerminalFailure = onTerminalFailure
    }

    deinit {
        _ = stop()
        hidInputMonitor?.stop()
    }

    func run() throws {
        try start()
        writeOperationalLog("nape-gesture を開始しました。停止するには Ctrl-C を押してください。")
        writeOperationalLog("固定操作: button 3 = 2本指スクロール / スワイプ、button 4 = 3本指システムスワイプ、button 5 = 4本指システムピンチ")
        writeOperationalLog("キルスイッチ: \(KillSwitchShortcut.displayName)")
        CFRunLoopRun()
        if let terminalError {
            throw terminalError
        }
    }

    func start() throws {
        terminalError = nil
        try outputExecutor.ensureOutputAvailable()
        try AccessibilityPermission.ensurePrompted()
        cursorAnchorState.clear()

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

    @discardableResult
    func stop() -> Error? {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        let cancellation = outputExecutor.cancelActive(
            reason: .runtimeStop,
            timestamp: MonotonicEventClock.now
        )
        cursorAnchorState.clear()
        guard let failure = cancellation.failure else {
            return nil
        }
        let error = ToolError.trackpadOutputPostingFailed(failure.rawValue)
        if terminalError == nil {
            terminalError = error
            writeOperationalLog(error.localizedDescription)
        }
        return error
    }

    fileprivate func handle(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let callbackStartedAt = performanceRecorder == nil
            ? 0
            : MonotonicEventClock.nowTimestampNanoseconds

        guard terminalError == nil else {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let timestamp = MonotonicEventTimestamp(
                nanosecondsSinceStartup: event.timestamp
            )
            cancelForTapInterruption(timestamp: timestamp)
            if terminalError == nil, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if CGEventUtilities.isGeneratedByThisTool(event) {
            return Unmanaged.passUnretained(event)
        }

        let exactTimestamp = MonotonicEventTimestamp(
            nanosecondsSinceStartup: event.timestamp
        )
        if KillSwitchShortcut.matches(type: type, event: event) {
            let decision = emergencyStop(timestamp: exactTimestamp)
            return decision.shouldSuppressOriginalEvent ? nil : Unmanaged.passUnretained(event)
        }

        guard let rawInput = CGEventUtilities.rawInput(from: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        let safetyDecision = safetyState.inputDecision(rawInput)
        guard safetyDecision.shouldProcessGestureInput else {
            return safetyDecision.shouldSuppressOriginalEvent
                ? nil
                : Unmanaged.passUnretained(event)
        }
        if let targetGate, !targetGate.shouldHandle(rawInput) {
            return Unmanaged.passUnretained(event)
        }
        guard let input = CGEventUtilities.fixedGestureInput(from: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        let decision = recognizer.handle(input)
        if let failure = decision.failure {
            _ = outputExecutor.cancelActive(
                reason: .inputLifecycle,
                timestamp: exactTimestamp
            )
            transitionToTerminalFailure(
                ToolError.trackpadOutputPostingFailed(
                    "fixed gesture input contract: \(String(describing: failure))"
                )
            )
            return decision.shouldSuppressOriginal ? nil : Unmanaged.passUnretained(event)
        }

        let performanceContext = performanceRecorder.map { _ in
            RuntimePerformanceContext(
                operationID: nextPerformanceOperationID(source: .eventTap),
                inputEventTimestampNanoseconds: event.timestamp,
                tapCallbackStartedAtNanoseconds: callbackStartedAt,
                recognizerFinishedAtNanoseconds: MonotonicEventClock.nowTimestampNanoseconds,
                suppressedOriginal: decision.shouldSuppressOriginal
            )
        }
        guard post(
            commands: decision.commands,
            sourceCursorLocation: event.location,
            performanceContext: performanceContext
        ) else {
            return decision.shouldSuppressOriginal ? nil : Unmanaged.passUnretained(event)
        }
        return decision.shouldSuppressOriginal ? nil : Unmanaged.passUnretained(event)
    }

    @discardableResult
    private func post(
        commands: [FixedGestureInputCommand],
        sourceCursorLocation: CGPoint? = nil,
        performanceContext: RuntimePerformanceContext? = nil
    ) -> Bool {
        for command in commands {
            if let error = prepareCursorForOutput(
                command: command,
                sourceCursorLocation: sourceCursorLocation
            ) {
                transitionToTerminalFailure(error)
                return false
            }

            let shouldRecord = performanceContext != nil
            let postStartedAt = shouldRecord
                ? MonotonicEventClock.nowTimestampNanoseconds
                : 0
            let result = outputExecutor.post(command: command)
            let postFinishedAt = shouldRecord
                ? MonotonicEventClock.nowTimestampNanoseconds
                : 0
            recordRuntimePerformance(
                command: command,
                postResult: result,
                context: performanceContext,
                postStartedAtNanoseconds: postStartedAt,
                postFinishedAtNanoseconds: postFinishedAt
            )

            let failure = result.outputFailure
                ?? (result.failedEventCreationCount > 0 ? .eventCreationFailed : nil)
            if let failure {
                let context = [
                    "failure=\(failure.rawValue)",
                    "class=\(command.gestureClass.rawValue)",
                    "family=\(result.family.rawValue)",
                    "source=\(command.sourceKind.rawValue)",
                    "phase=\(command.phase.rawValue)",
                    "captureOrder=\(command.captureOrder)",
                    result.failureDetails,
                ].compactMap { $0 }.joined(separator: " ")
                transitionToTerminalFailure(
                    ToolError.trackpadOutputPostingFailed(context)
                )
                return false
            }

            do {
                try cursorAnchorState.complete(command)
            } catch {
                transitionToTerminalFailure(error)
                return false
            }
        }
        return true
    }

    private func emergencyStop(
        timestamp: MonotonicEventTimestamp
    ) -> RuntimeSafetyDecision {
        let decision = safetyState.stopForKillSwitch(
            at: timestamp.secondsSinceStartup,
            suppressingReleaseOf: recognizer.activeButton
        )
        if decision.shouldCancelGesture {
            let cancelDecision = recognizer.handle(.cancel(timestamp: timestamp))
            _ = post(commands: cancelDecision.commands)
        }
        let cancellation = outputExecutor.cancelActive(
            reason: .killSwitch,
            timestamp: timestamp
        )
        if let failure = cancellation.failure {
            transitionToTerminalFailure(failure)
        }
        cursorAnchorState.clear()
        if decision.didEnterStoppedState {
            writeOperationalLog("キルスイッチによりジェスチャーを無効化しました。再開するには常駐UIの停止/開始、またはプロセス再起動を行ってください。")
        }
        return decision
    }

    private func transitionToTerminalFailure(_ failure: ProductGestureOutputFailure) {
        transitionToTerminalFailure(
            ToolError.trackpadOutputPostingFailed(failure.rawValue)
        )
    }

    private func transitionToTerminalFailure(_ error: Error) {
        cursorAnchorState.clear()
        guard terminalError == nil else {
            return
        }
        terminalError = error
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        _ = outputExecutor.cancelActive(
            reason: .outputFailure,
            timestamp: MonotonicEventClock.now
        )
        writeOperationalLog(error.localizedDescription)

        if let onTerminalFailure {
            DispatchQueue.main.async {
                onTerminalFailure(error)
            }
        } else {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    private func recordRuntimePerformance(
        command: FixedGestureInputCommand,
        postResult: GestureOutputPostResult,
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
                source: .eventTap,
                gestureClass: command.gestureClass,
                outputFamily: postResult.family,
                sourceKind: command.sourceKind,
                inputPhase: command.phase,
                commandTimestampNanoseconds: command.timestamp.nanosecondsSinceStartup,
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

    private func prepareCursorForOutput(
        command: FixedGestureInputCommand,
        sourceCursorLocation: CGPoint?
    ) -> Error? {
        let sourcePosition = sourceCursorLocation.map {
            CursorAnchorPosition(x: Double($0.x), y: Double($0.y))
        }
        do {
            try cursorAnchorState.prepareAndWarp(
                for: command,
                sourcePosition: sourcePosition,
                using: { position in
                    let result = warpCursor(CGPoint(x: position.x, y: position.y))
                    guard result == .success else {
                        let context = command.phase == .began ? "gesture開始時" : "move取得後"
                        throw ToolError.trackpadOutputPostingFailed(
                            "\(context)にcursor anchorへ戻せませんでした。CGError=\(result.rawValue)"
                        )
                    }
                }
            )
        } catch {
            if let toolError = error as? ToolError {
                return toolError
            }
            return ToolError.trackpadOutputPostingFailed(error.localizedDescription)
        }
        return nil
    }

    private func cancelForTapInterruption(
        timestamp: MonotonicEventTimestamp
    ) {
        if recognizer.activeSession != nil {
            let decision = recognizer.handle(.cancel(timestamp: timestamp))
            _ = post(commands: decision.commands)
        }
        let cancellation = outputExecutor.cancelActive(
            reason: .inputLifecycle,
            timestamp: timestamp
        )
        if let failure = cancellation.failure {
            transitionToTerminalFailure(failure)
            return
        }
        cursorAnchorState.clear()
    }

    private func writeOperationalLog(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}

private struct RuntimePerformanceContext {
    let operationID: String
    let inputEventTimestampNanoseconds: UInt64?
    let tapCallbackStartedAtNanoseconds: UInt64
    let recognizerFinishedAtNanoseconds: UInt64
    let suppressedOriginal: Bool
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let daemon = Unmanaged<NapeGestureDaemon>.fromOpaque(userInfo).takeUnretainedValue()
    return daemon.handle(proxy: proxy, type: type, event: event)
}
