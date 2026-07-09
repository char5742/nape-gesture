import Foundation

/// キルスイッチ発火後に、通常入力を通過させながらジェスチャー処理だけを止める純粋状態。
public struct RuntimeSafetyState: Equatable, Sendable {
    public private(set) var mode: RuntimeSafetyMode
    public private(set) var buttonsSuppressedUntilRelease: Set<MouseButton>

    public init(
        mode: RuntimeSafetyMode = .enabled,
        buttonsSuppressedUntilRelease: Set<MouseButton> = []
    ) {
        self.mode = mode
        self.buttonsSuppressedUntilRelease = buttonsSuppressedUntilRelease
    }

    public var isEnabled: Bool {
        mode == .enabled
    }

    public func regularInputDecision() -> RuntimeSafetyDecision {
        RuntimeSafetyDecision(
            shouldProcessGestureInput: isEnabled,
            shouldSuppressOriginalEvent: false,
            shouldCancelGesture: false,
            shouldCancelMomentum: false,
            didEnterStoppedState: false
        )
    }

    @discardableResult
    public mutating func stopForKillSwitch(at time: TimeInterval) -> RuntimeSafetyDecision {
        stopForKillSwitch(at: time, suppressingReleaseOf: nil)
    }

    @discardableResult
    public mutating func stopForKillSwitch(
        at time: TimeInterval,
        suppressingReleaseOf button: MouseButton?
    ) -> RuntimeSafetyDecision {
        let didEnterStoppedState = isEnabled
        if didEnterStoppedState {
            mode = .stopped(reason: .killSwitch, stoppedAt: time)
            if let button {
                buttonsSuppressedUntilRelease.insert(button)
            }
        }

        return RuntimeSafetyDecision(
            shouldProcessGestureInput: false,
            shouldSuppressOriginalEvent: true,
            shouldCancelGesture: didEnterStoppedState,
            shouldCancelMomentum: didEnterStoppedState,
            didEnterStoppedState: didEnterStoppedState
        )
    }

    public mutating func inputDecision(_ event: RawInputEvent) -> RuntimeSafetyDecision {
        guard !isEnabled else {
            return regularInputDecision()
        }

        if case let .buttonUp(button, _) = event,
           buttonsSuppressedUntilRelease.remove(button) != nil {
            return RuntimeSafetyDecision(
                shouldProcessGestureInput: false,
                shouldSuppressOriginalEvent: true,
                shouldCancelGesture: false,
                shouldCancelMomentum: false,
                didEnterStoppedState: false
            )
        }

        return regularInputDecision()
    }

    public mutating func reset() {
        mode = .enabled
        buttonsSuppressedUntilRelease.removeAll()
    }
}

public enum RuntimeSafetyMode: Equatable, Sendable {
    case enabled
    case stopped(reason: RuntimeSafetyStopReason, stoppedAt: TimeInterval)
}

public enum RuntimeSafetyStopReason: String, Codable, Equatable, Sendable {
    case killSwitch
}

public struct RuntimeSafetyDecision: Equatable, Sendable {
    public var shouldProcessGestureInput: Bool
    public var shouldSuppressOriginalEvent: Bool
    public var shouldCancelGesture: Bool
    public var shouldCancelMomentum: Bool
    public var didEnterStoppedState: Bool

    public init(
        shouldProcessGestureInput: Bool,
        shouldSuppressOriginalEvent: Bool,
        shouldCancelGesture: Bool,
        shouldCancelMomentum: Bool,
        didEnterStoppedState: Bool
    ) {
        self.shouldProcessGestureInput = shouldProcessGestureInput
        self.shouldSuppressOriginalEvent = shouldSuppressOriginalEvent
        self.shouldCancelGesture = shouldCancelGesture
        self.shouldCancelMomentum = shouldCancelMomentum
        self.didEnterStoppedState = didEnterStoppedState
    }
}
