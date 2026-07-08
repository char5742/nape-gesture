import Foundation

public enum GestureAction: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case smoothScroll
    case horizontalScroll
    case missionControl
    case spaceLeft
    case spaceRight
    case pageBack
    case pageForward
    case zoomIn
    case zoomOut

    public static let settingsSelectableActions: [GestureAction] = allCases

    public var supportsMomentum: Bool {
        switch self {
        case .smoothScroll, .horizontalScroll, .spaceLeft, .spaceRight:
            return true
        case .none, .missionControl, .pageBack, .pageForward, .zoomIn, .zoomOut:
            return false
        }
    }
}

public struct GestureBindings: Codable, Equatable, Sendable {
    public var dragUp: GestureAction
    public var dragDown: GestureAction
    public var dragLeft: GestureAction
    public var dragRight: GestureAction
    public var wheel: GestureAction

    public init(
        dragUp: GestureAction = .missionControl,
        dragDown: GestureAction = .smoothScroll,
        dragLeft: GestureAction = .spaceLeft,
        dragRight: GestureAction = .spaceRight,
        wheel: GestureAction = .horizontalScroll
    ) {
        self.dragUp = dragUp
        self.dragDown = dragDown
        self.dragLeft = dragLeft
        self.dragRight = dragRight
        self.wheel = wheel
    }

    public static let `default` = GestureBindings()

    public func action(for command: GestureCommand) -> GestureAction {
        switch command.kind {
        case .wheel:
            return wheel
        case .drag, .momentum:
            guard let direction = command.direction else {
                return .smoothScroll
            }
            return action(for: direction)
        }
    }

    public func action(for direction: GestureDirection) -> GestureAction {
        switch direction {
        case .up:
            return dragUp
        case .down:
            return dragDown
        case .left:
            return dragLeft
        case .right:
            return dragRight
        }
    }
}
