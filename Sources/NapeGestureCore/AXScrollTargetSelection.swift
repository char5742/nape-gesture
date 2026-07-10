import Foundation

public enum AXScrollAxis: String, CaseIterable, Hashable, Sendable {
    case horizontal
    case vertical
}

public struct AXScrollTargetFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0, y: Double = 0, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum AXScrollClippingEvidence: Equatable, Sendable {
    case notApplicable
    case inspected(clippedAxes: Set<AXScrollAxis>)
    case unavailable
}

public enum AXScrollClippingInspector {
    public static func inspect(
        containerFrame: AXScrollTargetFrame?,
        childFrames: [AXScrollTargetFrame?]?,
        requestedAxes: Set<AXScrollAxis>
    ) -> AXScrollClippingEvidence {
        guard let containerFrame,
              isUsable(containerFrame),
              let childFrames
        else {
            return .unavailable
        }

        var clippedAxes: Set<AXScrollAxis> = []
        for optionalChildFrame in childFrames {
            guard let childFrame = optionalChildFrame,
                  isUsable(childFrame)
            else {
                return .unavailable
            }
            for axis in requestedAxes where isClipped(
                childFrame,
                by: containerFrame,
                on: axis
            ) {
                clippedAxes.insert(axis)
            }
        }
        return .inspected(clippedAxes: clippedAxes)
    }

    private static func isUsable(_ frame: AXScrollTargetFrame) -> Bool {
        frame.x.isFinite
            && frame.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width >= 0
            && frame.height >= 0
            && (frame.x + frame.width).isFinite
            && (frame.y + frame.height).isFinite
    }

    private static func isClipped(
        _ child: AXScrollTargetFrame,
        by container: AXScrollTargetFrame,
        on axis: AXScrollAxis
    ) -> Bool {
        switch axis {
        case .horizontal:
            return child.x < container.x - 1
                || child.x + child.width > container.x + container.width + 1
        case .vertical:
            return child.y < container.y - 1
                || child.y + child.height > container.y + container.height + 1
        }
    }
}

public struct AXScrollTargetNode: Sendable {
    public var role: String
    public var scrollbarAxes: Set<AXScrollAxis>
    public var clippingEvidence: AXScrollClippingEvidence

    public init(
        role: String,
        scrollbarAxes: Set<AXScrollAxis> = [],
        clippingEvidence: AXScrollClippingEvidence = .notApplicable
    ) {
        self.role = role
        self.scrollbarAxes = scrollbarAxes
        self.clippingEvidence = clippingEvidence
    }
}

public enum AXScrollTargetBlockReason: Equatable, Sendable {
    case ambiguousDescendant
    case descendantInformationUnavailable
    case nearestContainerMissingScrollbars
    case nearestWebAreaContainerUnavailable
}

public enum AXScrollTargetSelection: Equatable, Sendable {
    case target(nodeIndex: Int, axes: Set<AXScrollAxis>)
    case blocked(AXScrollTargetBlockReason)
    case notFound
}

public enum AXScrollTargetSelector {
    public static func select(
        nodes: [AXScrollTargetNode],
        requestedAxes: Set<AXScrollAxis>
    ) -> AXScrollTargetSelection {
        guard !requestedAxes.isEmpty,
              let webAreaIndex = nodes.firstIndex(where: { $0.role == "AXWebArea" })
        else {
            return .notFound
        }

        for index in nodes.indices where index < webAreaIndex {
            guard isExplicitScrollContainer(nodes[index]) else {
                continue
            }
            return selection(
                of: nodes[index],
                at: index,
                requestedAxes: requestedAxes
            )
        }

        switch descendantAmbiguity(
            nodes: nodes,
            before: webAreaIndex,
            requestedAxes: requestedAxes
        ) {
        case .ambiguous:
            return .blocked(.ambiguousDescendant)
        case .unavailable:
            return .blocked(.descendantInformationUnavailable)
        case .none:
            break
        }

        if !nodes[webAreaIndex].scrollbarAxes.isEmpty {
            return selection(
                of: nodes[webAreaIndex],
                at: webAreaIndex,
                requestedAxes: requestedAxes
            )
        }

        for index in nodes.indices where index > webAreaIndex {
            let node = nodes[index]
            if node.role == "AXWebArea" {
                return .blocked(.nearestWebAreaContainerUnavailable)
            }
            if isExplicitScrollContainer(node) {
                return selection(of: node, at: index, requestedAxes: requestedAxes)
            }
        }
        return .blocked(.nearestWebAreaContainerUnavailable)
    }

    private static func selection(
        of node: AXScrollTargetNode,
        at index: Int,
        requestedAxes: Set<AXScrollAxis>
    ) -> AXScrollTargetSelection {
        let availableAxes = requestedAxes.intersection(node.scrollbarAxes)
        guard !availableAxes.isEmpty else {
            return .blocked(.nearestContainerMissingScrollbars)
        }
        return .target(nodeIndex: index, axes: availableAxes)
    }

    private static func isExplicitScrollContainer(_ node: AXScrollTargetNode) -> Bool {
        node.role == "AXScrollArea" || !node.scrollbarAxes.isEmpty
    }

    private static func descendantAmbiguity(
        nodes: [AXScrollTargetNode],
        before webAreaIndex: Int,
        requestedAxes: Set<AXScrollAxis>
    ) -> DescendantAmbiguity {
        guard webAreaIndex > 0 else {
            return .none
        }

        for node in nodes[..<webAreaIndex] where roleMayContainNestedScroll(node.role) {
            switch node.clippingEvidence {
            case let .inspected(clippedAxes):
                if !clippedAxes.isDisjoint(with: requestedAxes) {
                    return .ambiguous
                }
            case .notApplicable, .unavailable:
                return .unavailable
            }
        }
        return .none
    }

    private static func roleMayContainNestedScroll(_ role: String) -> Bool {
        switch role {
        case "AXGroup", "AXList", "AXOutline", "AXTable", "AXTextArea":
            return true
        default:
            return false
        }
    }

    private enum DescendantAmbiguity {
        case none
        case ambiguous
        case unavailable
    }
}

public enum AXScrollDeliveryOutcome: Equatable, Sendable {
    case applied
    case noChange
    case blocked
    case notHandled
    case partiallyApplied

    public var shouldPostCGEventFallback: Bool {
        self == .notHandled
    }

    public var deliveredActionCount: Int {
        switch self {
        case .applied, .partiallyApplied:
            return 1
        case .noChange, .blocked, .notHandled:
            return 0
        }
    }
}

public struct AXScrollTargetCacheKey: Equatable, Hashable, Sendable {
    public var processID: Int32
    public var windowNumber: UInt32?
    public var pointX: Double
    public var pointY: Double
    public var targetIdentity: Int

    public init(
        processID: Int32,
        windowNumber: UInt32?,
        pointX: Double,
        pointY: Double,
        targetIdentity: Int
    ) {
        self.processID = processID
        self.windowNumber = windowNumber
        self.pointX = pointX
        self.pointY = pointY
        self.targetIdentity = targetIdentity
    }
}

public struct AXScrollValueRequest: Equatable, Sendable {
    public var axis: AXScrollAxis
    public var delta: Double

    public init(axis: AXScrollAxis, delta: Double) {
        self.axis = axis
        self.delta = delta
    }
}

public struct AXScrollValueUpdate: Equatable, Sendable {
    public var axis: AXScrollAxis
    public var currentValue: Double
    public var nextValue: Double

    public init(axis: AXScrollAxis, currentValue: Double, nextValue: Double) {
        self.axis = axis
        self.currentValue = currentValue
        self.nextValue = nextValue
    }
}

public enum AXScrollValuePlan: Equatable, Sendable {
    case updates([AXScrollValueUpdate])
    case noChange
    case unavailable
}

public enum AXScrollValuePlanner {
    public static func plan(
        requests: [AXScrollValueRequest],
        currentValues: [AXScrollAxis: Double],
        scale: Double
    ) -> AXScrollValuePlan {
        guard !requests.isEmpty, scale.isFinite, scale > 0 else {
            return .unavailable
        }

        var seenAxes: Set<AXScrollAxis> = []
        var updates: [AXScrollValueUpdate] = []
        for request in requests {
            guard request.delta.isFinite,
                  seenAxes.insert(request.axis).inserted,
                  let currentValue = currentValues[request.axis],
                  currentValue.isFinite
            else {
                return .unavailable
            }
            let nextValue = min(max(currentValue + request.delta / scale, 0), 1)
            if nextValue != currentValue {
                updates.append(
                    AXScrollValueUpdate(
                        axis: request.axis,
                        currentValue: currentValue,
                        nextValue: nextValue
                    )
                )
            }
        }
        return updates.isEmpty ? .noChange : .updates(updates)
    }
}
