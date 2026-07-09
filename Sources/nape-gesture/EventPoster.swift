import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import NapeGestureCore

final class EventPoster {
    // AX scrollbar はピクセル幅ではなく 0...1 の正規化値を公開するため、過剰移動を避ける保守的な換算にする。
    private let axWebScrollScale = 3_200.0
    private let axMessagingTimeout: Float = 0.02
    private let axPrepareBudgetNanoseconds: UInt64 = 40_000_000
    private let axSearchBudgetNanoseconds: UInt64 = 120_000_000
    private let axAsyncMaximumLatencyNanoseconds: UInt64 = 160_000_000
    private let axCacheLifetimeNanoseconds: UInt64 = 250_000_000
    private let axMissCacheLifetimeNanoseconds: UInt64 = 500_000_000
    private let windowTargetCacheLifetimeNanoseconds: UInt64 = 500_000_000
    private let axScrollQueue = DispatchQueue(label: "dev.char5742.nape-gesture.ax-scroll")
    private let source: CGEventSource?
    private var cachedWindowTarget: CachedWindowTarget?
    private var cachedAXWebScrollTarget: CachedAXWebScrollTarget?
    private var axWebScrollMisses: [AXWebScrollMissKey: UInt64] = [:]

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
    }

    func waitForPendingAXScroll() {
        axScrollQueue.sync {}
    }

    func prepareAXWebScrollTarget(synchronously: Bool = false) {
        let point = currentPointerLocation()
        guard let target = windowTargetUnderPointer(at: point) else {
            return
        }

        let prepare = {
            let deadline = self.monotonicNanoseconds() + self.axPrepareBudgetNanoseconds
            for axis in [AXWebScrollAxis.horizontal, .vertical] {
                guard self.hasAXTimeRemaining(until: deadline) else {
                    break
                }
                _ = self.axWebScrollUpdates(
                    for: [AXWebScrollRequest(axis: axis, delta: 0)],
                    at: point,
                    targetProcessID: target.processID,
                    targetWindowNumber: target.windowNumber,
                    deadline: deadline
                )
            }
        }

        if synchronously {
            axScrollQueue.sync(execute: prepare)
        } else {
            axScrollQueue.async(execute: prepare)
        }
    }

    @discardableResult
    func postScroll(
        command: GestureCommand,
        mode: ScrollPostMode,
        axDelivery: AXScrollDelivery = .asynchronous,
        targetProcessOverride: pid_t? = nil,
        completion: EventDeliveryCompletionHandler? = nil
    ) -> EventPostResult {
        guard let context = makeScrollEventContext(
            command: command,
            mode: mode,
            targetProcessOverride: targetProcessOverride
        ) else {
            return EventPostResult(generatedEventCount: 0, failedEventCreationCount: 1)
        }
        let event = context.event
        let targetUnderPointer = context.targetUnderPointer
        let targetProcessID = targetProcessOverride
            ?? targetProcessID(for: mode, targetUnderPointer: targetUnderPointer)
        let operation = ScrollDeliveryOperation(
            requests: axWebScrollRequests(for: command, mode: mode),
            point: event.location,
            targetProcessID: targetProcessID,
            targetWindowNumber: targetUnderPointer?.windowNumber,
            fallbackEvent: event,
            fallbackMode: mode
        )

        guard !operation.requests.isEmpty else {
            postCGScrollEvent(event, mode: mode, targetProcessID: targetProcessID)
            return EventPostResult(generatedEventCount: 1, failedEventCreationCount: 0)
        }

        switch axDelivery {
        case .synchronous:
            axScrollQueue.sync {
                deliverScroll(operation, enqueuedAtNanoseconds: nil)
            }
        case .asynchronous:
            let enqueuedAtNanoseconds = monotonicNanoseconds()
            axScrollQueue.async {
                let startedAtNanoseconds = self.monotonicNanoseconds()
                self.deliverScroll(operation, enqueuedAtNanoseconds: enqueuedAtNanoseconds)
                completion?(
                    EventDeliveryCompletion(
                        postResult: EventPostResult(generatedEventCount: 1, failedEventCreationCount: 0),
                        startedAtNanoseconds: startedAtNanoseconds,
                        finishedAtNanoseconds: self.monotonicNanoseconds()
                    )
                )
            }
        }
        return EventPostResult(
            generatedEventCount: 1,
            failedEventCreationCount: 0,
            deliveryDeferred: axDelivery == .asynchronous
        )
    }

    private func deliverScroll(
        _ operation: ScrollDeliveryOperation,
        enqueuedAtNanoseconds: UInt64?
    ) {
        guard !operation.requests.isEmpty else {
            postCGScrollEvent(
                operation.fallbackEvent,
                mode: operation.fallbackMode,
                targetProcessID: operation.targetProcessID
            )
            return
        }

        let now = monotonicNanoseconds()
        let deadline: UInt64
        if let enqueuedAtNanoseconds {
            let maximumDeadline = enqueuedAtNanoseconds + axAsyncMaximumLatencyNanoseconds
            guard now < maximumDeadline else {
                postCGScrollEvent(
                    operation.fallbackEvent,
                    mode: operation.fallbackMode,
                    targetProcessID: operation.targetProcessID
                )
                return
            }
            deadline = min(maximumDeadline, now + axSearchBudgetNanoseconds)
        } else {
            deadline = now + axSearchBudgetNanoseconds
        }

        if postAXWebScrollIfNeeded(
            requests: operation.requests,
            at: operation.point,
            targetProcessID: operation.targetProcessID,
            targetWindowNumber: operation.targetWindowNumber,
            deadline: deadline
        ) {
            return
        }
        postCGScrollEvent(
            operation.fallbackEvent,
            mode: operation.fallbackMode,
            targetProcessID: operation.targetProcessID
        )
    }

    private func postCGScrollEvent(_ event: CGEvent, mode: ScrollPostMode, targetProcessID: pid_t?) {
        if let pid = targetProcessID {
            event.postToPid(pid)
        } else {
            event.post(tap: postTap(for: mode))
        }
    }

    func makeScrollEvent(command: GestureCommand, mode: ScrollPostMode) -> CGEvent? {
        makeScrollEventContext(command: command, mode: mode, targetProcessOverride: nil)?.event
    }

    private func makeScrollEventContext(
        command: GestureCommand,
        mode: ScrollPostMode,
        targetProcessOverride: pid_t?
    ) -> ScrollEventContext? {
        let deltas = mode.deltas(for: command)
        let wheel1 = quantize(deltas.y)
        let wheel2 = quantize(deltas.x)

        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheel1,
            wheel2: wheel2,
            wheel3: 0
        ) else {
            return nil
        }

        CGEventUtilities.setGeneratedMarker(on: event)
        let phases = CGEventUtilities.phaseValues(for: command)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phases.scroll)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phases.momentum)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltas.y)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: deltas.x)
        let pointerLocation = currentPointerLocation()
        event.location = pointerLocation
        let targetUnderPointer = mode.usesPointerWindowTarget || targetProcessOverride != nil
            ? windowTargetUnderPointer(at: pointerLocation, processID: targetProcessOverride)
            : nil
        if let target = targetUnderPointer {
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointer,
                value: Int64(target.windowNumber)
            )
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                value: Int64(target.windowNumber)
            )
        }

        event.timestamp = CGEventTimestamp(max(command.timestamp, 0) * 1_000_000_000)
        return ScrollEventContext(event: event, targetUnderPointer: targetUnderPointer)
    }

    @discardableResult
    func postMissionControl(
        delivery: AXScrollDelivery = .synchronous,
        completion: EventDeliveryCompletionHandler? = nil
    ) -> EventPostResult {
        postKeyShortcut(
            keyCode: CGKeyCode(kVK_UpArrow),
            flags: .maskControl,
            delivery: delivery,
            completion: completion
        )
    }

    @discardableResult
    func postPageBack(
        delivery: AXScrollDelivery = .synchronous,
        completion: EventDeliveryCompletionHandler? = nil
    ) -> EventPostResult {
        postKeyShortcut(
            keyCode: CGKeyCode(kVK_ANSI_LeftBracket),
            flags: .maskCommand,
            delivery: delivery,
            completion: completion
        )
    }

    @discardableResult
    func postPageForward(
        delivery: AXScrollDelivery = .synchronous,
        completion: EventDeliveryCompletionHandler? = nil
    ) -> EventPostResult {
        postKeyShortcut(
            keyCode: CGKeyCode(kVK_ANSI_RightBracket),
            flags: .maskCommand,
            delivery: delivery,
            completion: completion
        )
    }

    @discardableResult
    func postZoomIn(
        delivery: AXScrollDelivery = .synchronous,
        completion: EventDeliveryCompletionHandler? = nil
    ) -> EventPostResult {
        postKeyShortcut(
            keyCode: CGKeyCode(kVK_ANSI_Equal),
            flags: [.maskCommand, .maskShift],
            delivery: delivery,
            completion: completion
        )
    }

    @discardableResult
    func postZoomOut(
        delivery: AXScrollDelivery = .synchronous,
        completion: EventDeliveryCompletionHandler? = nil
    ) -> EventPostResult {
        postKeyShortcut(
            keyCode: CGKeyCode(kVK_ANSI_Minus),
            flags: .maskCommand,
            delivery: delivery,
            completion: completion
        )
    }

    private func postKeyShortcut(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        delivery: AXScrollDelivery,
        completion: EventDeliveryCompletionHandler?
    ) -> EventPostResult {
        let sequence = ShortcutEventSequence.keyEvents(keyCode: keyCode, flags: flags)
        let rawEvents = sequence.map { shortcutEvent in
            makeKeyEvent(
                keyCode: shortcutEvent.keyCode,
                keyDown: shortcutEvent.isKeyDown,
                flags: shortcutEvent.flags
            )
        }
        guard rawEvents.allSatisfy({ $0 != nil }) else {
            return EventPostResult(
                generatedEventCount: 0,
                failedEventCreationCount: rawEvents.filter { $0 == nil }.count
            )
        }
        let events = rawEvents.compactMap { $0 }
        events.forEach(CGEventUtilities.setGeneratedMarker)

        switch delivery {
        case .synchronous:
            axScrollQueue.sync {
                postKeyEvents(events)
            }
        case .asynchronous:
            axScrollQueue.async {
                let startedAtNanoseconds = self.monotonicNanoseconds()
                self.postKeyEvents(events)
                completion?(
                    EventDeliveryCompletion(
                        postResult: EventPostResult(
                            generatedEventCount: events.count,
                            failedEventCreationCount: 0
                        ),
                        startedAtNanoseconds: startedAtNanoseconds,
                        finishedAtNanoseconds: self.monotonicNanoseconds()
                    )
                )
            }
        }

        return EventPostResult(
            generatedEventCount: events.count,
            failedEventCreationCount: rawEvents.count - events.count,
            deliveryDeferred: delivery == .asynchronous
        )
    }

    private func postKeyEvents(_ events: [CGEvent]) {
        for (index, event) in events.enumerated() {
            event.post(tap: .cgSessionEventTap)
            if index < events.count - 1 {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }

    private func makeKeyEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
        event?.flags = flags
        return event
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

    private func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func monotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private func postTap(for mode: ScrollPostMode) -> CGEventTapLocation {
        switch mode {
        case .free, .horizontal:
            return .cgSessionEventTap
        case .forcedHorizontal:
            return .cghidEventTap
        }
    }

    private func targetProcessID(for mode: ScrollPostMode, targetUnderPointer: WindowTarget?) -> pid_t? {
        switch mode {
        case .free, .horizontal:
            return targetUnderPointer?.processID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        case .forcedHorizontal:
            return nil
        }
    }

    private func windowTargetUnderPointer(at point: CGPoint, processID: pid_t? = nil) -> WindowTarget? {
        let cacheKey = WindowTargetCacheKey(processID: processID)
        let now = monotonicNanoseconds()
        if let cachedWindowTarget,
           cachedWindowTarget.key == cacheKey,
           now >= cachedWindowTarget.resolvedAtNanoseconds,
           now - cachedWindowTarget.resolvedAtNanoseconds <= windowTargetCacheLifetimeNanoseconds,
           cachedWindowTarget.bounds.contains(point) {
            return cachedWindowTarget.target
        }
        cachedWindowTarget = nil

        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let descriptions = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var resolvedTarget: WindowTarget?
        var resolvedBounds: CGRect?
        for description in descriptions {
            guard let layer = description[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let ownerPID = pidValue(description[kCGWindowOwnerPID as String]),
                  let windowNumber = windowNumberValue(description[kCGWindowNumber as String]),
                  let bounds = description[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  processID == nil || processID == ownerPID,
                  rect.contains(point)
            else {
                continue
            }
            resolvedTarget = WindowTarget(processID: ownerPID, windowNumber: windowNumber)
            resolvedBounds = rect
            break
        }

        if let resolvedTarget, let resolvedBounds {
            cachedWindowTarget = CachedWindowTarget(
                key: cacheKey,
                target: resolvedTarget,
                bounds: resolvedBounds,
                resolvedAtNanoseconds: now
            )
        }
        return resolvedTarget
    }

    private func axWebScrollRequests(for command: GestureCommand, mode: ScrollPostMode) -> [AXWebScrollRequest] {
        guard mode.usesAXWebScrollFallback else {
            return []
        }

        let deltas = mode.deltas(for: command)
        var requests: [AXWebScrollRequest] = []

        if mode.usesAXWebHorizontalScrollFallback, deltas.x != 0 {
            requests.append(AXWebScrollRequest(axis: .horizontal, delta: deltas.x))
        }
        if mode.usesAXWebVerticalScrollFallback, deltas.y != 0 {
            requests.append(AXWebScrollRequest(axis: .vertical, delta: deltas.y))
        }

        return requests
    }

    private func postAXWebScrollIfNeeded(
        requests: [AXWebScrollRequest],
        at point: CGPoint,
        targetProcessID: pid_t?,
        targetWindowNumber: UInt32?,
        deadline: UInt64
    ) -> Bool {
        guard let updates = axWebScrollUpdates(
            for: requests,
            at: point,
            targetProcessID: targetProcessID,
            targetWindowNumber: targetWindowNumber,
            deadline: deadline
        )
        else {
            return false
        }

        var appliedUpdates: [AXWebScrollUpdate] = []
        for update in updates {
            guard hasAXTimeRemaining(until: deadline),
                  AXUIElementSetAttributeValue(
                update.scrollBar,
                kAXValueAttribute as CFString,
                NSNumber(value: update.nextValue) as CFTypeRef
            ) == .success else {
                cachedAXWebScrollTarget = nil
                let didRollback = rollbackAXWebScrollUpdates(appliedUpdates)
                // 部分適用を戻せない場合は CGEvent を重ねない。
                return !didRollback
            }
            appliedUpdates.append(update)
        }

        if var cachedAXWebScrollTarget {
            for update in updates {
                cachedAXWebScrollTarget.values[update.axis] = update.nextValue
            }
            cachedAXWebScrollTarget.lastUsedAtNanoseconds = monotonicNanoseconds()
            self.cachedAXWebScrollTarget = cachedAXWebScrollTarget
        }

        return true
    }

    private func rollbackAXWebScrollUpdates(_ updates: [AXWebScrollUpdate]) -> Bool {
        var succeeded = true
        for update in updates.reversed() {
            if AXUIElementSetAttributeValue(
                update.scrollBar,
                kAXValueAttribute as CFString,
                NSNumber(value: update.currentValue) as CFTypeRef
            ) != .success {
                succeeded = false
            }
        }
        return succeeded
    }

    private func axWebScrollUpdates(
        for requests: [AXWebScrollRequest],
        at point: CGPoint,
        targetProcessID: pid_t?,
        targetWindowNumber: UInt32?,
        deadline: UInt64
    ) -> [AXWebScrollUpdate]? {
        let cacheKey = targetProcessID.map {
            AXWebScrollCacheKey(
                processID: $0,
                windowNumber: targetWindowNumber,
                pointX: point.x,
                pointY: point.y
            )
        }
        let requestedAxes = Set(requests.map(\.axis))

        let now = monotonicNanoseconds()
        axWebScrollMisses = axWebScrollMisses.filter { _, missedAt in
            now >= missedAt && now - missedAt <= axMissCacheLifetimeNanoseconds
        }
        if let cacheKey,
           var cachedAXWebScrollTarget,
           cachedAXWebScrollTarget.key == cacheKey,
           requestedAxes.allSatisfy({ cachedAXWebScrollTarget.scrollBars[$0] != nil }) {
            let cacheAge = now >= cachedAXWebScrollTarget.lastUsedAtNanoseconds
                ? now - cachedAXWebScrollTarget.lastUsedAtNanoseconds
                : UInt64.max
            if cacheAge <= axCacheLifetimeNanoseconds {
                cachedAXWebScrollTarget.lastUsedAtNanoseconds = now
                self.cachedAXWebScrollTarget = cachedAXWebScrollTarget
                return makeAXWebScrollUpdates(
                    for: requests,
                    scrollBars: cachedAXWebScrollTarget.scrollBars,
                    currentValues: cachedAXWebScrollTarget.values
                )
            }
            if let refreshedValues = axWebScrollValues(
                for: requestedAxes,
                scrollBars: cachedAXWebScrollTarget.scrollBars,
                deadline: deadline
            ) {
                cachedAXWebScrollTarget.values.merge(refreshedValues) { _, refreshed in refreshed }
                cachedAXWebScrollTarget.lastUsedAtNanoseconds = now
                self.cachedAXWebScrollTarget = cachedAXWebScrollTarget
                return makeAXWebScrollUpdates(
                    for: requests,
                    scrollBars: cachedAXWebScrollTarget.scrollBars,
                    currentValues: cachedAXWebScrollTarget.values
                )
            }
            self.cachedAXWebScrollTarget = nil
        } else if let cacheKey,
                  let cachedAXWebScrollTarget,
                  cachedAXWebScrollTarget.key != cacheKey {
            self.cachedAXWebScrollTarget = nil
        }

        var scrollBars = cacheKey == cachedAXWebScrollTarget?.key
            ? cachedAXWebScrollTarget?.scrollBars ?? [:]
            : [:]
        for request in requests where scrollBars[request.axis] == nil {
            let missKey = cacheKey.map { AXWebScrollMissKey(target: $0, axis: request.axis) }
            if let missKey,
               let missedAt = axWebScrollMisses[missKey],
               now >= missedAt,
               now - missedAt <= axMissCacheLifetimeNanoseconds {
                return nil
            }
            if let missKey {
                axWebScrollMisses.removeValue(forKey: missKey)
            }
            guard hasAXTimeRemaining(until: deadline) else {
                return nil
            }
            switch webContentAXScrollBarUnderPointer(
                axis: request.axis,
                at: point,
                targetProcessID: targetProcessID,
                deadline: deadline
            ) {
            case let .found(scrollBar):
                scrollBars[request.axis] = scrollBar
            case .notFound:
                if let missKey {
                    axWebScrollMisses[missKey] = monotonicNanoseconds()
                }
                return nil
            case .unavailable:
                return nil
            }
        }

        guard let currentValues = axWebScrollValues(
            for: requestedAxes,
            scrollBars: scrollBars,
            deadline: deadline
        ) else {
            return nil
        }
        if let cacheKey {
            var combined = cachedAXWebScrollTarget?.key == cacheKey
                ? cachedAXWebScrollTarget
                : nil
            if combined == nil {
                combined = CachedAXWebScrollTarget(
                    key: cacheKey,
                    scrollBars: [:],
                    values: [:],
                    lastUsedAtNanoseconds: now
                )
            }
            combined?.scrollBars.merge(scrollBars) { _, resolved in resolved }
            combined?.values.merge(currentValues) { _, refreshed in refreshed }
            combined?.lastUsedAtNanoseconds = now
            cachedAXWebScrollTarget = combined
        }
        return makeAXWebScrollUpdates(
            for: requests,
            scrollBars: scrollBars,
            currentValues: currentValues
        )
    }

    private func axWebScrollValues(
        for axes: Set<AXWebScrollAxis>,
        scrollBars: [AXWebScrollAxis: AXUIElement],
        deadline: UInt64
    ) -> [AXWebScrollAxis: Double]? {
        var values: [AXWebScrollAxis: Double] = [:]
        for axis in axes {
            guard hasAXTimeRemaining(until: deadline),
                  let scrollBar = scrollBars[axis],
                  let currentValue = axNumericAttribute(
                      scrollBar,
                      kAXValueAttribute as CFString,
                      deadline: deadline
                  )
            else {
                return nil
            }
            values[axis] = currentValue
        }
        return values
    }

    private func makeAXWebScrollUpdates(
        for requests: [AXWebScrollRequest],
        scrollBars: [AXWebScrollAxis: AXUIElement],
        currentValues: [AXWebScrollAxis: Double]
    ) -> [AXWebScrollUpdate]? {
        var updates: [AXWebScrollUpdate] = []
        for request in requests {
            guard let currentValue = currentValues[request.axis] else {
                return nil
            }
            let nextValue = clampedUnitValue(currentValue + request.delta / axWebScrollScale)
            if nextValue != currentValue {
                guard let scrollBar = scrollBars[request.axis] else {
                    return nil
                }
                updates.append(
                    AXWebScrollUpdate(
                        axis: request.axis,
                        scrollBar: scrollBar,
                        currentValue: currentValue,
                        nextValue: nextValue
                    )
                )
            }
        }
        return updates
    }

    private func webContentAXScrollBarUnderPointer(
        axis: AXWebScrollAxis,
        at point: CGPoint,
        targetProcessID: pid_t?,
        deadline: UInt64
    ) -> AXWebScrollLookupResult {
        guard hasAXTimeRemaining(until: deadline) else {
            return .unavailable
        }
        var roots: [AXUIElement] = []
        if let targetProcessID {
            let application = AXUIElementCreateApplication(targetProcessID)
            applyAXMessagingTimeout(to: application)
            var applicationElement: AXUIElement?
            let applicationHitTestResult = AXUIElementCopyElementAtPosition(
                application,
                Float(point.x),
                Float(point.y),
                &applicationElement
            )
            if applicationHitTestResult == .success,
               let applicationElement {
                applyAXMessagingTimeout(to: applicationElement)
                if let scrollBar = webContentAXScrollBarByAscending(
                    from: applicationElement,
                    axis: axis,
                    deadline: deadline
                ) {
                    return .found(scrollBar)
                }
                return hasAXTimeRemaining(until: deadline) ? .notFound : .unavailable
            }

            if let window = axWindow(containing: point, in: application, deadline: deadline) {
                roots.append(window)
            } else {
                roots.append(application)
            }
        } else {
            let systemWideElement = AXUIElementCreateSystemWide()
            applyAXMessagingTimeout(to: systemWideElement)
            var rawElement: AXUIElement?
            if AXUIElementCopyElementAtPosition(
                systemWideElement,
                Float(point.x),
                Float(point.y),
                &rawElement
            ) == .success,
               let rawElement {
                applyAXMessagingTimeout(to: rawElement)
                if let scrollBar = webContentAXScrollBarByAscending(
                    from: rawElement,
                    axis: axis,
                    deadline: deadline
                ) {
                    return .found(scrollBar)
                }
                return hasAXTimeRemaining(until: deadline) ? .notFound : .unavailable
            }
            return .unavailable
        }

        for root in roots {
            guard hasAXTimeRemaining(until: deadline) else {
                return .unavailable
            }
            applyAXMessagingTimeout(to: root)
            if let scrollBar = webContentAXScrollBarByAscending(from: root, axis: axis, deadline: deadline) {
                return .found(scrollBar)
            }
            if let scrollBar = webContentAXScrollBarByDescending(
                from: root,
                axis: axis,
                at: point,
                deadline: deadline
            ) {
                return .found(scrollBar)
            }
        }

        return hasAXTimeRemaining(until: deadline) ? .notFound : .unavailable
    }

    private func axWindow(
        containing point: CGPoint,
        in application: AXUIElement,
        deadline: UInt64
    ) -> AXUIElement? {
        let windows = axElementArrayAttribute(
            application,
            kAXWindowsAttribute as CFString,
            deadline: deadline
        )
        return windows.first { window in
            guard hasAXTimeRemaining(until: deadline) else {
                return false
            }
            let frame = axFrameAttribute(window, deadline: deadline)
            return frame?.contains(point) == true
        }
    }

    private func webContentAXScrollBarByAscending(
        from rawElement: AXUIElement?,
        axis: AXWebScrollAxis,
        deadline: UInt64
    ) -> AXUIElement? {
        var current = rawElement
        var foundWebArea = false
        for _ in 0..<12 {
            guard hasAXTimeRemaining(until: deadline), let element = current else {
                return nil
            }
            applyAXMessagingTimeout(to: element)
            let role = axStringAttribute(element, kAXRoleAttribute as CFString, deadline: deadline)
            if role == "AXWebArea" {
                foundWebArea = true
            }
            if foundWebArea,
               let scrollBar = axElementAttribute(element, axis.attribute, deadline: deadline) {
                return scrollBar
            }
            current = axElementAttribute(element, kAXParentAttribute as CFString, deadline: deadline)
        }

        return nil
    }

    private func webContentAXScrollBarByDescending(
        from root: AXUIElement,
        axis: AXWebScrollAxis,
        at point: CGPoint,
        deadline: UInt64
    ) -> AXUIElement? {
        var stack = [root]
        var visitedCount = 0
        while let element = stack.popLast(), visitedCount < 160 {
            guard hasAXTimeRemaining(until: deadline) else {
                return nil
            }
            visitedCount += 1
            applyAXMessagingTimeout(to: element)
            if let frame = axFrameAttribute(element, deadline: deadline),
               !frame.isEmpty,
               !frame.contains(point) {
                continue
            }
            let role = axStringAttribute(element, kAXRoleAttribute as CFString, deadline: deadline)

            if role == "AXWebArea" {
                if let scrollBar = webContentAXScrollBar(
                    forWebArea: element,
                    axis: axis,
                    deadline: deadline
                ) {
                    return scrollBar
                }
            }

            let children = axElementArrayAttribute(
                element,
                kAXChildrenAttribute as CFString,
                deadline: deadline
            )
            stack.append(contentsOf: children.reversed())
        }

        return nil
    }

    private func webContentAXScrollBar(
        forWebArea webArea: AXUIElement,
        axis: AXWebScrollAxis,
        deadline: UInt64
    ) -> AXUIElement? {
        guard hasAXTimeRemaining(until: deadline) else {
            return nil
        }
        if let scrollBar = axElementAttribute(webArea, axis.attribute, deadline: deadline) {
            return scrollBar
        }
        guard let parent = axElementAttribute(
            webArea,
            kAXParentAttribute as CFString,
            deadline: deadline
        ) else {
            return nil
        }
        if let scrollBar = axElementAttribute(parent, axis.attribute, deadline: deadline) {
            return scrollBar
        }
        return axScrollBarDescendant(axis: axis, from: parent, deadline: deadline)
    }

    private func axScrollBarDescendant(
        axis: AXWebScrollAxis,
        from root: AXUIElement,
        deadline: UInt64
    ) -> AXUIElement? {
        var stack = [root]
        var visitedCount = 0
        while let element = stack.popLast(), visitedCount < 64 {
            guard hasAXTimeRemaining(until: deadline) else {
                return nil
            }
            visitedCount += 1
            applyAXMessagingTimeout(to: element)
            if axStringAttribute(element, kAXRoleAttribute as CFString, deadline: deadline) == "AXScrollBar",
               axis.matchesScrollBar(
                   orientation: axStringAttribute(
                       element,
                       kAXOrientationAttribute as CFString,
                       deadline: deadline
                   ),
                   frame: axFrameAttribute(element, deadline: deadline)
               ) {
                return element
            }
            stack.append(
                contentsOf: axElementArrayAttribute(
                    element,
                    kAXChildrenAttribute as CFString,
                    deadline: deadline
                ).reversed()
            )
        }
        return nil
    }

    private func applyAXMessagingTimeout(to element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
    }

    private func hasAXTimeRemaining(until deadline: UInt64) -> Bool {
        monotonicNanoseconds() < deadline
    }

    private func axElementAttribute(
        _ element: AXUIElement,
        _ attribute: CFString,
        deadline: UInt64
    ) -> AXUIElement? {
        guard hasAXTimeRemaining(until: deadline) else {
            return nil
        }
        applyAXMessagingTimeout(to: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let result = (value as! AXUIElement)
        applyAXMessagingTimeout(to: result)
        return result
    }

    private func axElementArrayAttribute(
        _ element: AXUIElement,
        _ attribute: CFString,
        deadline: UInt64
    ) -> [AXUIElement] {
        guard hasAXTimeRemaining(until: deadline) else {
            return []
        }
        applyAXMessagingTimeout(to: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let values = value as? [AXUIElement]
        else {
            return []
        }
        values.forEach(applyAXMessagingTimeout)
        return values
    }

    private func axNumericAttribute(
        _ element: AXUIElement,
        _ attribute: CFString,
        deadline: UInt64
    ) -> Double? {
        guard hasAXTimeRemaining(until: deadline) else {
            return nil
        }
        applyAXMessagingTimeout(to: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        return nil
    }

    private func axStringAttribute(
        _ element: AXUIElement,
        _ attribute: CFString,
        deadline: UInt64
    ) -> String? {
        guard hasAXTimeRemaining(until: deadline) else {
            return nil
        }
        applyAXMessagingTimeout(to: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else {
            return nil
        }
        return value as? String
    }

    private func axFrameAttribute(_ element: AXUIElement, deadline: UInt64) -> CGRect? {
        guard let position = axCGPointAttribute(
            element,
            kAXPositionAttribute as CFString,
            deadline: deadline
        ),
              let size = axCGSizeAttribute(
                  element,
                  kAXSizeAttribute as CFString,
                  deadline: deadline
              )
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func axCGPointAttribute(
        _ element: AXUIElement,
        _ attribute: CFString,
        deadline: UInt64
    ) -> CGPoint? {
        guard hasAXTimeRemaining(until: deadline) else {
            return nil
        }
        applyAXMessagingTimeout(to: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgPoint
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func axCGSizeAttribute(
        _ element: AXUIElement,
        _ attribute: CFString,
        deadline: UInt64
    ) -> CGSize? {
        guard hasAXTimeRemaining(until: deadline) else {
            return nil
        }
        applyAXMessagingTimeout(to: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgSize
        else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func clampedUnitValue(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func pidValue(_ raw: Any?) -> pid_t? {
        if let value = raw as? pid_t {
            return value
        }
        if let value = raw as? Int {
            return pid_t(value)
        }
        return nil
    }

    private func windowNumberValue(_ raw: Any?) -> UInt32? {
        if let value = raw as? UInt32 {
            return value
        }
        if let value = raw as? Int, value >= 0 {
            return UInt32(value)
        }
        return nil
    }
}

private struct ScrollDeliveryOperation {
    var requests: [AXWebScrollRequest]
    var point: CGPoint
    var targetProcessID: pid_t?
    var targetWindowNumber: UInt32?
    var fallbackEvent: CGEvent
    var fallbackMode: ScrollPostMode
}

private struct AXWebScrollCacheKey: Hashable {
    var processID: pid_t
    var windowNumber: UInt32?
    var pointX: Double
    var pointY: Double
}

private struct AXWebScrollMissKey: Hashable {
    var target: AXWebScrollCacheKey
    var axis: AXWebScrollAxis
}

private struct CachedAXWebScrollTarget {
    var key: AXWebScrollCacheKey
    var scrollBars: [AXWebScrollAxis: AXUIElement]
    var values: [AXWebScrollAxis: Double]
    var lastUsedAtNanoseconds: UInt64
}

private struct ScrollEventContext {
    var event: CGEvent
    var targetUnderPointer: WindowTarget?
}

private struct WindowTargetCacheKey: Hashable {
    var processID: pid_t?
}

private struct CachedWindowTarget {
    var key: WindowTargetCacheKey
    var target: WindowTarget
    var bounds: CGRect
    var resolvedAtNanoseconds: UInt64
}

private struct WindowTarget {
    var processID: pid_t
    var windowNumber: UInt32
}

enum AXScrollDelivery: Equatable {
    case synchronous
    case asynchronous
}

private enum AXWebScrollAxis: Hashable {
    case horizontal
    case vertical

    var attribute: CFString {
        switch self {
        case .horizontal:
            return kAXHorizontalScrollBarAttribute as CFString
        case .vertical:
            return kAXVerticalScrollBarAttribute as CFString
        }
    }

    func matchesScrollBar(orientation: String?, frame: CGRect?) -> Bool {
        switch (self, orientation) {
        case (.horizontal, "AXHorizontalOrientation"), (.vertical, "AXVerticalOrientation"):
            return true
        case (_, .some):
            return false
        case (.horizontal, nil):
            return frame.map { $0.width >= $0.height } ?? false
        case (.vertical, nil):
            return frame.map { $0.height > $0.width } ?? false
        }
    }
}

private enum AXWebScrollLookupResult {
    case found(AXUIElement)
    case notFound
    case unavailable
}

private struct AXWebScrollRequest {
    var axis: AXWebScrollAxis
    var delta: Double
}

private struct AXWebScrollUpdate {
    var axis: AXWebScrollAxis
    var scrollBar: AXUIElement
    var currentValue: Double
    var nextValue: Double
}

typealias EventDeliveryCompletionHandler = (EventDeliveryCompletion) -> Void

struct EventDeliveryCompletion {
    var postResult: EventPostResult
    var startedAtNanoseconds: UInt64
    var finishedAtNanoseconds: UInt64
}

struct EventPostResult: Equatable {
    var generatedEventCount: Int
    var failedEventCreationCount: Int
    var deliveryDeferred: Bool

    init(
        generatedEventCount: Int,
        failedEventCreationCount: Int,
        deliveryDeferred: Bool = false
    ) {
        self.generatedEventCount = generatedEventCount
        self.failedEventCreationCount = failedEventCreationCount
        self.deliveryDeferred = deliveryDeferred
    }

    static let none = EventPostResult(generatedEventCount: 0, failedEventCreationCount: 0)
}

enum ScrollPostMode: Equatable {
    case free
    case horizontal
    case forcedHorizontal(sign: Int)

    func deltas(for command: GestureCommand) -> (x: Double, y: Double) {
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

    var usesAXWebScrollFallback: Bool {
        switch self {
        case .free, .horizontal:
            return true
        case .forcedHorizontal:
            return false
        }
    }

    var usesPointerWindowTarget: Bool {
        switch self {
        case .free, .horizontal:
            return true
        case .forcedHorizontal:
            return false
        }
    }

    var usesAXWebHorizontalScrollFallback: Bool {
        switch self {
        case .free, .horizontal:
            return true
        case .forcedHorizontal:
            return false
        }
    }

    var usesAXWebVerticalScrollFallback: Bool {
        switch self {
        case .free:
            return true
        case .horizontal, .forcedHorizontal:
            return false
        }
    }
}
