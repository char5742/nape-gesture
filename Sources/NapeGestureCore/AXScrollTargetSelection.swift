import Foundation

public enum AXScrollAxis: String, CaseIterable, Hashable, Sendable {
    case horizontal
    case vertical
}

public struct AXScrollTargetFrame: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct AXScrollTargetNode: Sendable {
    public var role: String
    public var frame: AXScrollTargetFrame?
    public var scrollbarAxes: Set<AXScrollAxis>
    public var clippedDescendantAxes: Set<AXScrollAxis>

    public init(
        role: String,
        frame: AXScrollTargetFrame? = nil,
        scrollbarAxes: Set<AXScrollAxis> = [],
        clippedDescendantAxes: Set<AXScrollAxis> = []
    ) {
        self.role = role
        self.frame = frame
        self.scrollbarAxes = scrollbarAxes
        self.clippedDescendantAxes = clippedDescendantAxes
    }
}

public enum AXScrollTargetBlockReason: Equatable, Sendable {
    case ambiguousDescendant
    case nearestContainerMissingScrollbars
    case nearestWebAreaContainerUnavailable
}

public enum AXScrollTargetSelection: Equatable, Sendable {
    case target(nodeIndex: Int)
    case blocked(AXScrollTargetBlockReason)
    case notFound
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
            let node = nodes[index]
            guard isExplicitScrollContainer(node) else {
                continue
            }
            return requestedAxes.isSubset(of: node.scrollbarAxes)
                ? .target(nodeIndex: index)
                : .blocked(.nearestContainerMissingScrollbars)
        }

        var containerIndex: Int?
        for index in nodes.indices where index > webAreaIndex {
            let node = nodes[index]
            if node.role == "AXWebArea" {
                return .blocked(.nearestWebAreaContainerUnavailable)
            }
            if isExplicitScrollContainer(node) {
                containerIndex = index
                break
            }
        }

        guard let containerIndex else {
            return .notFound
        }
        let container = nodes[containerIndex]
        if hasAmbiguousDescendant(
            nodes: nodes,
            before: webAreaIndex,
            webArea: nodes[webAreaIndex],
            container: container,
            requestedAxes: requestedAxes
        ) {
            return .blocked(.ambiguousDescendant)
        }
        guard requestedAxes.isSubset(of: container.scrollbarAxes) else {
            return .blocked(.nearestContainerMissingScrollbars)
        }
        return .target(nodeIndex: containerIndex)
    }

    private static func isExplicitScrollContainer(_ node: AXScrollTargetNode) -> Bool {
        node.role == "AXScrollArea" || !node.scrollbarAxes.isEmpty
    }

    private static func hasAmbiguousDescendant(
        nodes: [AXScrollTargetNode],
        before webAreaIndex: Int,
        webArea: AXScrollTargetNode,
        container: AXScrollTargetNode,
        requestedAxes: Set<AXScrollAxis>
    ) -> Bool {
        guard webAreaIndex > 0 else {
            return false
        }

        if nodes[..<webAreaIndex].contains(where: {
            !$0.clippedDescendantAxes.isDisjoint(with: requestedAxes)
        }) {
            return true
        }

        for parentIndex in 1..<webAreaIndex {
            let child = nodes[parentIndex - 1]
            let parent = nodes[parentIndex]
            guard isContainerRole(parent.role) else {
                continue
            }
            for axis in requestedAxes where extends(child.frame, beyond: parent.frame, on: axis) {
                return true
            }
        }

        for node in nodes[..<webAreaIndex] where isContainerRole(node.role) {
            for axis in requestedAxes {
                guard extends(node.frame, beyond: container.frame, on: axis) else {
                    continue
                }
                if !hasSameExtent(node.frame, as: webArea.frame, on: axis) {
                    return true
                }
            }
        }
        return false
    }

    private static func isContainerRole(_ role: String) -> Bool {
        switch role {
        case "AXGroup", "AXList", "AXOutline", "AXTable", "AXTextArea":
            return true
        default:
            return false
        }
    }

    private static func extends(
        _ child: AXScrollTargetFrame?,
        beyond parent: AXScrollTargetFrame?,
        on axis: AXScrollAxis
    ) -> Bool {
        guard let child, let parent else {
            return false
        }
        return extent(of: child, on: axis) > extent(of: parent, on: axis) + 1
    }

    private static func hasSameExtent(
        _ lhs: AXScrollTargetFrame?,
        as rhs: AXScrollTargetFrame?,
        on axis: AXScrollAxis
    ) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        return abs(extent(of: lhs, on: axis) - extent(of: rhs, on: axis)) <= 1
    }

    private static func extent(of frame: AXScrollTargetFrame, on axis: AXScrollAxis) -> Double {
        switch axis {
        case .horizontal:
            return frame.width
        case .vertical:
            return frame.height
        }
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
