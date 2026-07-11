import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore

public typealias DiagnosticScrollEventFactory = (
    _ source: CGEventSource?,
    _ wheel1: Int32,
    _ wheel2: Int32
) -> CGEvent?
public typealias DiagnosticKeyEventFactory = (
    _ source: CGEventSource?,
    _ keyCode: CGKeyCode,
    _ keyDown: Bool
) -> CGEvent?
public typealias DiagnosticEventPostOperation = (_ event: CGEvent) -> Bool

public enum DiagnosticEventReleaseDomain: Hashable {
    case scroll
    case momentum
    case mouseButton(Int64)
    case key(Int64)
}

public struct DiagnosticPreparedEvent {
    public var event: CGEvent
    public var delayAfterPrevious: TimeInterval
    public var opensReleaseDomains: Set<DiagnosticEventReleaseDomain>
    public var closesReleaseDomains: Set<DiagnosticEventReleaseDomain>

    public init(
        event: CGEvent,
        delayAfterPrevious: TimeInterval,
        opensReleaseDomains: Set<DiagnosticEventReleaseDomain> = [],
        closesReleaseDomains: Set<DiagnosticEventReleaseDomain> = []
    ) {
        self.event = event
        self.delayAfterPrevious = delayAfterPrevious
        self.opensReleaseDomains = opensReleaseDomains
        self.closesReleaseDomains = closesReleaseDomains
    }
}

public final class DiagnosticEventPoster {
    private let source: CGEventSource?
    private let nowTimestampNanoseconds: () -> UInt64
    private let sleep: (TimeInterval) -> Void
    private let scrollEventFactory: DiagnosticScrollEventFactory
    private let keyEventFactory: DiagnosticKeyEventFactory
    private let postEvent: DiagnosticEventPostOperation

    public init(
        nowTimestampNanoseconds: @escaping () -> UInt64 = {
            MonotonicEventClock.nowTimestampNanoseconds
        },
        sleep: @escaping (TimeInterval) -> Void = { interval in
            Thread.sleep(forTimeInterval: interval)
        },
        scrollEventFactory: @escaping DiagnosticScrollEventFactory = { source, wheel1, wheel2 in
            CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: wheel1,
                wheel2: wheel2,
                wheel3: 0
            )
        },
        keyEventFactory: @escaping DiagnosticKeyEventFactory = { source, keyCode, keyDown in
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
        },
        postEvent: @escaping DiagnosticEventPostOperation = { event in
            event.post(tap: .cghidEventTap)
            return true
        }
    ) {
        source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
        self.nowTimestampNanoseconds = nowTimestampNanoseconds
        self.sleep = sleep
        self.scrollEventFactory = scrollEventFactory
        self.keyEventFactory = keyEventFactory
        self.postEvent = postEvent
    }

    @discardableResult
    public func postScroll(
        command: GestureCommand,
        mode: ScrollPostMode
    ) -> DiagnosticEventPostResult {
        let postingTimestamp = nowTimestampNanoseconds()
        guard Self.validatedTimestampNanoseconds(
            fromSecondsSinceStartup: command.timestamp,
            notAfter: postingTimestamp
        ) != nil,
            let event = makeUnstampedScrollEvent(command: command, mode: mode)
        else {
            return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }

        event.timestamp = CGEventTimestamp(postingTimestamp)
        guard postEvent(event) else {
            return DiagnosticEventPostResult(
                generatedEventCount: 0,
                failedEventCreationCount: 0,
                failedEventPostCount: 1
            )
        }
        return DiagnosticEventPostResult(generatedEventCount: 1, failedEventCreationCount: 0)
    }

    @discardableResult
    public func postScrollSequence(
        commands: [GestureCommand],
        mode: ScrollPostMode,
        interval: TimeInterval
    ) -> DiagnosticEventPostResult {
        guard !commands.isEmpty else {
            return .none
        }
        let postingReference = nowTimestampNanoseconds()
        guard Self.validatedTimestampNanoseconds(
            fromSecondsSinceStartup: commands[0].timestamp,
            notAfter: postingReference
        ) != nil,
            Self.hasNondecreasingTimestamps(commands)
        else {
            return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }

        let completedCommands = Self.terminallyCompleteScrollCommands(
            commands,
            interval: interval
        )
        guard !completedCommands.isEmpty else {
            return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }

        var preparedEvents: [DiagnosticPreparedEvent] = []
        preparedEvents.reserveCapacity(completedCommands.count)
        for (index, command) in completedCommands.enumerated() {
            guard let event = makeUnstampedScrollEvent(command: command, mode: mode) else {
                return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
            }
            let domains = Self.releaseDomains(for: command)
            preparedEvents.append(
                DiagnosticPreparedEvent(
                    event: event,
                    delayAfterPrevious: index == 0 ? 0 : interval,
                    opensReleaseDomains: domains.opens,
                    closesReleaseDomains: domains.closes
                )
            )
        }

        return postPreparedSequence(preparedEvents)
    }

    public func makeScrollEvent(command: GestureCommand, mode: ScrollPostMode) -> CGEvent? {
        guard let timestamp = MonotonicEventClock.timestamp(
            fromSecondsSinceStartup: command.timestamp
        ), let event = makeUnstampedScrollEvent(command: command, mode: mode) else {
            return nil
        }
        event.timestamp = CGEventTimestamp(timestamp.nanosecondsSinceStartup)
        return event
    }

    @discardableResult
    public func postPreparedSequence(
        _ preparedEvents: [DiagnosticPreparedEvent]
    ) -> DiagnosticEventPostResult {
        guard preparedEvents.allSatisfy({
            $0.delayAfterPrevious.isFinite && $0.delayAfterPrevious >= 0
        }) else {
            return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }

        var activeDomains: Set<DiagnosticEventReleaseDomain> = []
        var generatedEventCount = 0
        var failedEventPostCount = 0
        var terminalEventCount = 0

        for (index, preparedEvent) in preparedEvents.enumerated() {
            if preparedEvent.delayAfterPrevious > 0 {
                sleep(preparedEvent.delayAfterPrevious)
            }

            guard postPreparedEvent(preparedEvent) else {
                failedEventPostCount += 1
                recoverReleaseDomains(
                    &activeDomains,
                    from: preparedEvents[index...],
                    generatedEventCount: &generatedEventCount,
                    failedEventPostCount: &failedEventPostCount,
                    terminalEventCount: &terminalEventCount
                )
                return DiagnosticEventPostResult(
                    generatedEventCount: generatedEventCount,
                    failedEventCreationCount: 0,
                    failedEventPostCount: failedEventPostCount,
                    terminalEventCount: terminalEventCount,
                    unreleasedEventDomainCount: activeDomains.count
                )
            }

            generatedEventCount += 1
            if !preparedEvent.closesReleaseDomains.isEmpty {
                terminalEventCount += 1
            }
            update(
                activeDomains: &activeDomains,
                afterPosting: preparedEvent
            )
        }

        return DiagnosticEventPostResult(
            generatedEventCount: generatedEventCount,
            failedEventCreationCount: 0,
            failedEventPostCount: 0,
            terminalEventCount: terminalEventCount,
            unreleasedEventDomainCount: activeDomains.count
        )
    }

    @discardableResult
    public func postMissionControl() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl)
    }

    @discardableResult
    public func postPageBack() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand)
    }

    @discardableResult
    public func postPageForward() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand)
    }

    @discardableResult
    public func postZoomIn() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand)
    }

    @discardableResult
    public func postZoomOut() -> DiagnosticEventPostResult {
        postKeyShortcut(keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand)
    }

    public static func terminallyCompleteScrollCommands(
        _ commands: [GestureCommand],
        interval: TimeInterval
    ) -> [GestureCommand] {
        guard !commands.isEmpty,
              interval.isFinite,
              interval > 0,
              commands.allSatisfy(isFiniteCommand),
              hasNondecreasingTimestamps(commands)
        else {
            return []
        }

        let startTime = commands[0].timestamp
        var activeDomains: Set<DiagnosticEventReleaseDomain> = []
        var completed: [GestureCommand] = []
        completed.reserveCapacity(commands.count + 2)

        for command in commands {
            let domains = releaseDomains(for: command)
            for openingDomain in domains.opens {
                guard let conflictingDomain = conflictingDomain(for: openingDomain),
                      activeDomains.contains(conflictingDomain)
                else {
                    continue
                }
                completed.append(terminalCommand(for: conflictingDomain, basedOn: command))
                activeDomains.remove(conflictingDomain)
            }

            completed.append(command)
            activeDomains.subtract(domains.closes)
            activeDomains.formUnion(domains.opens)
        }

        if activeDomains.contains(.momentum), let reference = completed.last {
            completed.append(terminalCommand(for: .momentum, basedOn: reference))
            activeDomains.remove(.momentum)
        }
        if activeDomains.contains(.scroll), let reference = completed.last {
            completed.append(terminalCommand(for: .scroll, basedOn: reference))
        }

        for index in completed.indices {
            let timestamp = startTime + Double(index) * interval
            guard timestamp.isFinite, timestamp >= 0 else {
                return []
            }
            completed[index].timestamp = timestamp
        }
        return completed
    }

    private func postKeyShortcut(
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> DiagnosticEventPostResult {
        let specifications = [true, false]
        var preparedEvents: [DiagnosticPreparedEvent] = []
        preparedEvents.reserveCapacity(specifications.count)

        for keyDown in specifications {
            guard let event = keyEventFactory(source, keyCode, keyDown) else {
                return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
            }
            setGeneratedMarker(on: event)
            event.flags = flags
            guard validateKeyEvent(
                event,
                keyCode: keyCode,
                keyDown: keyDown,
                flags: flags
            ) else {
                return DiagnosticEventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
            }

            let domain = DiagnosticEventReleaseDomain.key(Int64(keyCode))
            preparedEvents.append(
                DiagnosticPreparedEvent(
                    event: event,
                    delayAfterPrevious: 0,
                    opensReleaseDomains: keyDown ? [domain] : [],
                    closesReleaseDomains: keyDown ? [] : [domain]
                )
            )
        }

        return postPreparedSequence(preparedEvents)
    }

    private func makeUnstampedScrollEvent(
        command: GestureCommand,
        mode: ScrollPostMode
    ) -> CGEvent? {
        guard Self.isFiniteCommand(command) else {
            return nil
        }

        let deltas = mode.deltas(for: command)
        guard deltas.x.isFinite, deltas.y.isFinite else {
            return nil
        }
        let wheel1 = quantize(deltas.y)
        let wheel2 = quantize(deltas.x)

        guard let event = scrollEventFactory(source, wheel1, wheel2) else {
            return nil
        }

        setGeneratedMarker(on: event)
        let phases = phaseValues(for: command)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phases.scroll)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phases.momentum)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        return event
    }

    private func validateKeyEvent(
        _ event: CGEvent,
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) -> Bool {
        event.type == (keyDown ? .keyDown : .keyUp)
            && event.getIntegerValueField(.keyboardEventKeycode) == Int64(keyCode)
            && event.flags == flags
            && event.getIntegerValueField(.eventSourceUserData) == NapeGestureGeneratedEventMarker.value
    }

    private func postPreparedEvent(_ preparedEvent: DiagnosticPreparedEvent) -> Bool {
        let postingTimestamp = nowTimestampNanoseconds()
        preparedEvent.event.timestamp = CGEventTimestamp(postingTimestamp)
        return postEvent(preparedEvent.event)
    }

    private func recoverReleaseDomains(
        _ activeDomains: inout Set<DiagnosticEventReleaseDomain>,
        from remainingEvents: ArraySlice<DiagnosticPreparedEvent>,
        generatedEventCount: inout Int,
        failedEventPostCount: inout Int,
        terminalEventCount: inout Int
    ) {
        guard !activeDomains.isEmpty else {
            return
        }

        for preparedEvent in remainingEvents {
            guard !activeDomains.isDisjoint(with: preparedEvent.closesReleaseDomains) else {
                continue
            }
            if postPreparedEvent(preparedEvent) {
                generatedEventCount += 1
                terminalEventCount += 1
                update(activeDomains: &activeDomains, afterPosting: preparedEvent)
            } else {
                failedEventPostCount += 1
            }
            if activeDomains.isEmpty {
                return
            }
        }
    }

    private func update(
        activeDomains: inout Set<DiagnosticEventReleaseDomain>,
        afterPosting preparedEvent: DiagnosticPreparedEvent
    ) {
        activeDomains.subtract(preparedEvent.closesReleaseDomains)
        activeDomains.formUnion(preparedEvent.opensReleaseDomains)
    }

    private func setGeneratedMarker(on event: CGEvent) {
        event.setIntegerValueField(
            .eventSourceUserData,
            value: NapeGestureGeneratedEventMarker.value
        )
    }

    private func phaseValues(for command: GestureCommand) -> (scroll: Int64, momentum: Int64) {
        let encoding = ScrollEventPhaseEncoder.encode(command: command)
        return (
            scroll: phaseValue(for: encoding.scrollPhase),
            momentum: phaseValue(for: encoding.momentumPhase)
        )
    }

    private func phaseValue(for phase: GesturePhase?) -> Int64 {
        guard let phase else {
            return 0
        }
        switch phase {
        case .began:
            return Int64(NSEvent.Phase.began.rawValue)
        case .changed, .momentum:
            return Int64(NSEvent.Phase.changed.rawValue)
        case .ended:
            return Int64(NSEvent.Phase.ended.rawValue)
        case .cancelled:
            return Int64(NSEvent.Phase.cancelled.rawValue)
        }
    }

    private static func releaseDomains(
        for command: GestureCommand
    ) -> (
        opens: Set<DiagnosticEventReleaseDomain>,
        closes: Set<DiagnosticEventReleaseDomain>
    ) {
        let encoding = ScrollEventPhaseEncoder.encode(command: command)
        var opens: Set<DiagnosticEventReleaseDomain> = []
        var closes: Set<DiagnosticEventReleaseDomain> = []
        updateDomains(for: encoding.scrollPhase, domain: .scroll, opens: &opens, closes: &closes)
        updateDomains(for: encoding.momentumPhase, domain: .momentum, opens: &opens, closes: &closes)
        return (opens, closes)
    }

    private static func updateDomains(
        for phase: GesturePhase?,
        domain: DiagnosticEventReleaseDomain,
        opens: inout Set<DiagnosticEventReleaseDomain>,
        closes: inout Set<DiagnosticEventReleaseDomain>
    ) {
        switch phase {
        case .began, .changed, .momentum:
            opens.insert(domain)
        case .ended, .cancelled:
            closes.insert(domain)
        case nil:
            break
        }
    }

    private static func conflictingDomain(
        for domain: DiagnosticEventReleaseDomain
    ) -> DiagnosticEventReleaseDomain? {
        switch domain {
        case .scroll:
            return .momentum
        case .momentum:
            return .scroll
        case .mouseButton, .key:
            return nil
        }
    }

    private static func terminalCommand(
        for domain: DiagnosticEventReleaseDomain,
        basedOn command: GestureCommand
    ) -> GestureCommand {
        GestureCommand(
            kind: domain == .momentum ? .momentum : (command.kind == .momentum ? .wheel : command.kind),
            phase: .ended,
            direction: command.direction,
            deltaX: 0,
            deltaY: 0,
            velocityX: 0,
            velocityY: 0,
            timestamp: command.timestamp
        )
    }

    private static func isFiniteCommand(_ command: GestureCommand) -> Bool {
        command.timestamp.isFinite
            && command.timestamp >= 0
            && command.deltaX.isFinite
            && command.deltaY.isFinite
            && command.velocityX.isFinite
            && command.velocityY.isFinite
    }

    private static func hasNondecreasingTimestamps(_ commands: [GestureCommand]) -> Bool {
        zip(commands, commands.dropFirst()).allSatisfy { pair in
            pair.0.timestamp <= pair.1.timestamp
        }
    }

    private static func validatedTimestampNanoseconds(
        fromSecondsSinceStartup seconds: TimeInterval,
        notAfter referenceTimestampNanoseconds: UInt64
    ) -> UInt64? {
        let maximumSafelyConvertibleSeconds = TimeInterval(
            UInt64.max / MonotonicEventClock.nanosecondsPerSecond
        )
        guard seconds.isFinite,
              seconds >= 0,
              seconds <= maximumSafelyConvertibleSeconds
        else {
            return nil
        }
        let timestamp = UInt64(
            (seconds * TimeInterval(MonotonicEventClock.nanosecondsPerSecond)).rounded()
        )
        return timestamp <= referenceTimestampNanoseconds ? timestamp : nil
    }

    private func quantize(_ value: Double) -> Int32 {
        let rounded = value.rounded()
        if rounded > Double(Int32.max) {
            return Int32.max
        }
        if rounded < Double(Int32.min) {
            return Int32.min
        }
        return Int32(rounded)
    }
}

public struct DiagnosticEventPostResult: Equatable {
    public var generatedEventCount: Int
    public var failedEventCreationCount: Int
    public var failedEventPostCount: Int
    public var terminalEventCount: Int
    public var unreleasedEventDomainCount: Int

    public init(
        generatedEventCount: Int,
        failedEventCreationCount: Int,
        failedEventPostCount: Int = 0,
        terminalEventCount: Int = 0,
        unreleasedEventDomainCount: Int = 0
    ) {
        self.generatedEventCount = generatedEventCount
        self.failedEventCreationCount = failedEventCreationCount
        self.failedEventPostCount = failedEventPostCount
        self.terminalEventCount = terminalEventCount
        self.unreleasedEventDomainCount = unreleasedEventDomainCount
    }

    public static let none = DiagnosticEventPostResult(
        generatedEventCount: 0,
        failedEventCreationCount: 0
    )

    public var completedSuccessfully: Bool {
        failedEventCreationCount == 0
            && failedEventPostCount == 0
            && unreleasedEventDomainCount == 0
    }
}

public enum ScrollPostMode: Equatable {
    case free
    case horizontal
    case forcedHorizontal(sign: Int)

    public func deltas(for command: GestureCommand) -> (x: Double, y: Double) {
        switch self {
        case .free:
            return (normalizeZero(command.deltaX), normalizeZero(command.deltaY))
        case .horizontal:
            let x = command.deltaX != 0 ? command.deltaX : command.deltaY
            return (normalizeZero(x), 0)
        case let .forcedHorizontal(sign):
            let magnitude = max(abs(command.deltaX), abs(command.deltaY))
            return (normalizeZero(Double(sign) * magnitude), 0)
        }
    }

    private func normalizeZero(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }
}
