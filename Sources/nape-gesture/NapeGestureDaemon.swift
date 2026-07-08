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
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var momentumTimer: DispatchSourceTimer?
    private var safetyState = RuntimeSafetyState()

    init(
        configuration: GestureConfiguration,
        targetGate: SharedTargetDeviceGate? = nil,
        hidInputMonitor: HIDInputMonitor? = nil
    ) {
        self.configuration = configuration
        self.targetGate = targetGate
        self.hidInputMonitor = hidInputMonitor
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
        print("nape-gesture を開始しました。停止するには Ctrl-C を押してください。")
        print("キルスイッチ: \(KillSwitchShortcut.displayName)")
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
        handle(commands: decision.commands)

        if decision.shouldSuppressOriginal {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handle(commands: [GestureCommand]) {
        for command in commands {
            actionExecutor.post(command: command)

            if command.phase == .ended && actionExecutor.supportsMomentum(for: command) {
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

        actionExecutor.post(command: command)
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
            _ = recognizer.handle(.cancel(time: time))
        }
        if decision.didEnterStoppedState {
            print("キルスイッチによりジェスチャーを無効化しました。再開するには常駐UIの停止/開始、またはプロセス再起動を行ってください。")
        }
        return decision
    }
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let daemon = Unmanaged<NapeGestureDaemon>.fromOpaque(userInfo).takeUnretainedValue()
    return daemon.handle(proxy: proxy, type: type, event: event)
}
