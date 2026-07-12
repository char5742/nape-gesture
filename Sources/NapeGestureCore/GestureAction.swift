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
    case dockSwipe

    public var supportsMomentum: Bool {
        switch self {
        case .smoothScroll, .horizontalScroll:
            return true
        case .none, .missionControl, .spaceLeft, .spaceRight,
             .pageBack, .pageForward, .zoomIn, .zoomOut, .dockSwipe:
            return false
        }
    }
}
