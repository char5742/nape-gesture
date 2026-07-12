import Foundation

public enum TrackpadGestureMode: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case scrollAndNavigate
    case spacesAndMissionControl
    case zoom

    public var displayName: String {
        switch self {
        case .none: "通常"
        case .scrollAndNavigate: "Scroll & Navigate"
        case .spacesAndMissionControl: "Spaces & Mission Control"
        case .zoom: "Zoom"
        }
    }
}

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
    case magnification

    public var supportsMomentum: Bool {
        switch self {
        case .smoothScroll, .horizontalScroll:
            return true
        case .none, .missionControl, .spaceLeft, .spaceRight,
             .pageBack, .pageForward, .zoomIn, .zoomOut, .dockSwipe, .magnification:
            return false
        }
    }
}
