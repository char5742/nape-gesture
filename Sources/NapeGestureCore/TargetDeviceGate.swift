import Foundation

public struct TargetDeviceGateConfiguration: Codable, Equatable, Sendable {
    public var activationButton: MouseButton
    public var associationWindow: TimeInterval

    public init(
        activationButton: MouseButton,
        associationWindow: TimeInterval = TargetDeviceAssociationConfiguration.defaultAssociationWindow
    ) {
        self.activationButton = activationButton
        self.associationWindow = associationWindow
    }

    public init(settings: NapeGestureSettings) {
        self.init(
            activationButton: settings.gesture.activationButton,
            associationWindow: settings.targetDeviceAssociation.associationWindow
        )
    }
}

public struct TargetDeviceAssociationConfiguration: Codable, Equatable, Sendable {
    public static let defaultAssociationWindow: TimeInterval = 0.12

    public var associationWindow: TimeInterval

    public init(
        associationWindow: TimeInterval = Self.defaultAssociationWindow
    ) {
        self.associationWindow = associationWindow
    }

    public static let `default` = TargetDeviceAssociationConfiguration()
}

public enum TargetDeviceActivity: Equatable, Sendable {
    case buttonDown(button: MouseButton, time: TimeInterval)
    case buttonUp(button: MouseButton, time: TimeInterval)
    case pointer(deltaX: Double, deltaY: Double, time: TimeInterval)
    case wheel(deltaX: Double, deltaY: Double, time: TimeInterval)

    public var time: TimeInterval {
        switch self {
        case let .buttonDown(_, time),
             let .buttonUp(_, time),
             let .pointer(_, _, time),
             let .wheel(_, _, time):
            return time
        }
    }
}

public struct TargetDeviceGateRecordDecision: Equatable, Sendable {
    public var shouldCancelGesture: Bool

    public init(shouldCancelGesture: Bool) {
        self.shouldCancelGesture = shouldCancelGesture
    }
}

public struct TargetDeviceGateDecision: Equatable, Sendable {
    public var shouldHandle: Bool
    public var shouldCancelGesture: Bool

    public init(shouldHandle: Bool, shouldCancelGesture: Bool) {
        self.shouldHandle = shouldHandle
        self.shouldCancelGesture = shouldCancelGesture
    }
}

public struct TargetDeviceGateState: Equatable, Sendable {
    public private(set) var activeButtons: Set<MouseButton> = []
    public private(set) var lastTargetActivityTime: TimeInterval?
    public private(set) var isWaitingForActivationButtonRelease = false

    public var lastTargetActivationButtonDownTime: TimeInterval? {
        activationButtonDownChannel.targetCandidates.last
    }

    public var lastTargetPointerActivityTime: TimeInterval? {
        pointerChannel.targetCandidates.last
    }

    public var lastTargetWheelActivityTime: TimeInterval? {
        wheelChannel.targetCandidates.last
    }

    private var activationButtonDownChannel = AssociationChannelState()
    private var activationButtonUpChannel = AssociationChannelState()
    private var pointerChannel = AssociationChannelState()
    private var wheelChannel = AssociationChannelState()
    private let configuration: TargetDeviceGateConfiguration

    public init(configuration: TargetDeviceGateConfiguration) {
        self.configuration = configuration
    }

    @discardableResult
    public mutating func record(
        _ activity: TargetDeviceActivity,
        isTargetDevice: Bool = true
    ) -> TargetDeviceGateRecordDecision {
        guard let kind = associationKind(for: activity) else {
            if isTargetDevice {
                updateTargetButtonState(for: activity)
                lastTargetActivityTime = activity.time
                return TargetDeviceGateRecordDecision(shouldCancelGesture: false)
            }

            if isWaitingForActivationButtonRelease {
                cancelActiveAssociationPreservingQuarantine()
            }
            return TargetDeviceGateRecordDecision(shouldCancelGesture: isButtonActivity(activity))
        }

        if isTargetDevice {
            updateTargetButtonState(for: activity)
            lastTargetActivityTime = activity.time
            if kind == .activationButtonDown {
                activationButtonUpChannel.clearTargetCandidates()
            }

            let recorded = recordTargetCandidate(kind, at: activity.time)
            if !recorded {
                if isWaitingForActivationButtonRelease {
                    cancelActiveAssociationPreservingQuarantine()
                }
                return TargetDeviceGateRecordDecision(shouldCancelGesture: true)
            }
            return TargetDeviceGateRecordDecision(shouldCancelGesture: false)
        }

        recordNonTargetActivity(kind, at: activity.time)
        if isWaitingForActivationButtonRelease {
            cancelActiveAssociationPreservingQuarantine()
        }
        return TargetDeviceGateRecordDecision(shouldCancelGesture: true)
    }

    public mutating func decision(for event: RawInputEvent) -> TargetDeviceGateDecision {
        switch event {
        case let .buttonDown(button, time):
            guard button == configuration.activationButton else {
                return passThroughDecision()
            }
            let match = activationButtonDownChannel.consume(
                eventTime: time,
                associationWindow: configuration.associationWindow
            )
            guard match == .target else {
                return decisionForUnmatchedInput(match)
            }
            isWaitingForActivationButtonRelease = true
            return TargetDeviceGateDecision(shouldHandle: true, shouldCancelGesture: false)

        case let .buttonUp(button, time):
            guard button == configuration.activationButton,
                  isWaitingForActivationButtonRelease else {
                return passThroughDecision()
            }
            let match = activationButtonUpChannel.consume(
                eventTime: time,
                associationWindow: configuration.associationWindow
            )
            guard match == .target else {
                cancelActiveAssociationPreservingQuarantine()
                return TargetDeviceGateDecision(shouldHandle: false, shouldCancelGesture: true)
            }
            isWaitingForActivationButtonRelease = false
            return TargetDeviceGateDecision(shouldHandle: true, shouldCancelGesture: false)

        case let .move(_, _, time):
            return decisionForUnmatchedInput(
                pointerChannel.consume(
                    eventTime: time,
                    associationWindow: configuration.associationWindow
                ),
                handlesTarget: true
            )

        case let .wheel(_, _, time):
            return decisionForUnmatchedInput(
                wheelChannel.consume(
                    eventTime: time,
                    associationWindow: configuration.associationWindow
                ),
                handlesTarget: true
            )

        case .cancel:
            reset()
            return TargetDeviceGateDecision(shouldHandle: true, shouldCancelGesture: false)
        }
    }

    public mutating func shouldHandle(_ event: RawInputEvent) -> Bool {
        decision(for: event).shouldHandle
    }

    public mutating func reset() {
        activeButtons.removeAll()
        lastTargetActivityTime = nil
        activationButtonDownChannel.reset()
        activationButtonUpChannel.reset()
        pointerChannel.reset()
        wheelChannel.reset()
        isWaitingForActivationButtonRelease = false
    }

    private mutating func updateTargetButtonState(for activity: TargetDeviceActivity) {
        switch activity {
        case let .buttonDown(button, _):
            activeButtons.insert(button)
        case let .buttonUp(button, _):
            activeButtons.remove(button)
        case .pointer, .wheel:
            break
        }
    }

    private func associationKind(for activity: TargetDeviceActivity) -> AssociationKind? {
        switch activity {
        case let .buttonDown(button, _):
            return button == configuration.activationButton ? .activationButtonDown : nil
        case let .buttonUp(button, _):
            return button == configuration.activationButton ? .activationButtonUp : nil
        case .pointer:
            return .pointer
        case .wheel:
            return .wheel
        }
    }

    private func isButtonActivity(_ activity: TargetDeviceActivity) -> Bool {
        switch activity {
        case .buttonDown, .buttonUp:
            return true
        case .pointer, .wheel:
            return false
        }
    }

    private mutating func recordTargetCandidate(_ kind: AssociationKind, at time: TimeInterval) -> Bool {
        switch kind {
        case .activationButtonDown:
            return activationButtonDownChannel.recordTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        case .activationButtonUp:
            return activationButtonUpChannel.recordTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        case .pointer:
            return pointerChannel.recordTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        case .wheel:
            return wheelChannel.recordTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        }
    }

    private mutating func recordNonTargetActivity(_ kind: AssociationKind, at time: TimeInterval) {
        switch kind {
        case .activationButtonDown:
            activationButtonDownChannel.recordNonTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        case .activationButtonUp:
            activationButtonUpChannel.recordNonTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        case .pointer:
            pointerChannel.recordNonTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        case .wheel:
            wheelChannel.recordNonTarget(
                at: time,
                associationWindow: configuration.associationWindow
            )
        }
    }

    private mutating func decisionForUnmatchedInput(
        _ match: AssociationMatch,
        handlesTarget: Bool = false
    ) -> TargetDeviceGateDecision {
        if match == .target, handlesTarget {
            return TargetDeviceGateDecision(shouldHandle: true, shouldCancelGesture: false)
        }
        guard match == .ambiguous else {
            return passThroughDecision()
        }

        if isWaitingForActivationButtonRelease {
            cancelActiveAssociationPreservingQuarantine()
        }
        return TargetDeviceGateDecision(shouldHandle: false, shouldCancelGesture: true)
    }

    private func passThroughDecision() -> TargetDeviceGateDecision {
        TargetDeviceGateDecision(shouldHandle: false, shouldCancelGesture: false)
    }

    private mutating func cancelActiveAssociationPreservingQuarantine() {
        activeButtons.removeAll()
        activationButtonDownChannel.clearTargetCandidates()
        activationButtonUpChannel.clearTargetCandidates()
        pointerChannel.clearTargetCandidates()
        wheelChannel.clearTargetCandidates()
        isWaitingForActivationButtonRelease = false
    }

    private enum AssociationKind {
        case activationButtonDown
        case activationButtonUp
        case pointer
        case wheel
    }
}

private enum AssociationMatch: Equatable {
    case target
    case passThrough
    case ambiguous
}

private struct AssociationChannelState: Equatable, Sendable {
    private static let maximumCandidateCount = 32

    private(set) var targetCandidates: [TimeInterval] = []
    private var quarantineStart: TimeInterval?
    private var quarantineEnd: TimeInterval?

    mutating func recordTarget(at time: TimeInterval, associationWindow: TimeInterval) -> Bool {
        expireQuarantine(before: time)
        guard !isQuarantined(at: time) else {
            return false
        }

        targetCandidates.removeAll { candidate in
            time - candidate > associationWindow
        }

        if targetCandidates.contains(time) {
            return true
        }
        targetCandidates.append(time)
        targetCandidates.sort()

        guard targetCandidates.count <= Self.maximumCandidateCount else {
            targetCandidates.removeAll()
            extendQuarantine(from: time, associationWindow: associationWindow)
            return false
        }
        return true
    }

    mutating func recordNonTarget(at time: TimeInterval, associationWindow: TimeInterval) {
        targetCandidates.removeAll()
        extendQuarantine(from: time, associationWindow: associationWindow)
    }

    mutating func consume(
        eventTime: TimeInterval,
        associationWindow: TimeInterval
    ) -> AssociationMatch {
        expireQuarantine(before: eventTime)
        if isQuarantined(at: eventTime) {
            return .ambiguous
        }

        targetCandidates.removeAll { candidate in
            eventTime - candidate > associationWindow
        }

        guard let lastEligibleIndex = targetCandidates.lastIndex(where: { candidate in
            let elapsed = eventTime - candidate
            return elapsed >= 0 && elapsed <= associationWindow
        }) else {
            return .passThrough
        }

        targetCandidates.removeFirst(lastEligibleIndex + 1)
        return .target
    }

    mutating func clearTargetCandidates() {
        targetCandidates.removeAll()
    }

    mutating func reset() {
        targetCandidates.removeAll()
        quarantineStart = nil
        quarantineEnd = nil
    }

    private mutating func extendQuarantine(from time: TimeInterval, associationWindow: TimeInterval) {
        let end = time + associationWindow
        if let currentEnd = quarantineEnd, time <= currentEnd {
            quarantineStart = min(quarantineStart ?? time, time)
            quarantineEnd = max(currentEnd, end)
        } else {
            quarantineStart = time
            quarantineEnd = end
        }
    }

    private mutating func expireQuarantine(before time: TimeInterval) {
        guard let quarantineEnd, time > quarantineEnd else {
            return
        }
        quarantineStart = nil
        self.quarantineEnd = nil
    }

    private func isQuarantined(at time: TimeInterval) -> Bool {
        guard let quarantineStart, let quarantineEnd else {
            return false
        }
        return time >= quarantineStart && time <= quarantineEnd
    }
}
