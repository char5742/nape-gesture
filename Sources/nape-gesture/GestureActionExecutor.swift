import Foundation
import NapeGestureCore

final class GestureActionExecutor {
    private let bindings: GestureBindings
    private let poster: EventPoster

    init(bindings: GestureBindings, poster: EventPoster = EventPoster()) {
        self.bindings = bindings
        self.poster = poster
    }

    func post(command: GestureCommand) {
        let action = bindings.action(for: command)

        switch action {
        case .none:
            return
        case .smoothScroll:
            poster.postScroll(command: command, mode: .free)
        case .horizontalScroll:
            poster.postScroll(command: command, mode: .horizontal)
        case .spaceLeft:
            poster.postScroll(command: command, mode: .forcedHorizontal(sign: -1))
        case .spaceRight:
            poster.postScroll(command: command, mode: .forcedHorizontal(sign: 1))
        case .missionControl:
            postDiscrete(command: command) {
                poster.postMissionControl()
            }
        case .pageBack:
            postDiscrete(command: command) {
                poster.postPageBack()
            }
        case .pageForward:
            postDiscrete(command: command) {
                poster.postPageForward()
            }
        case .zoomIn:
            postDiscrete(command: command) {
                poster.postZoomIn()
            }
        case .zoomOut:
            postDiscrete(command: command) {
                poster.postZoomOut()
            }
        }
    }

    func supportsMomentum(for command: GestureCommand) -> Bool {
        bindings.action(for: command).supportsMomentum
    }

    private func postDiscrete(command: GestureCommand, action: () -> Void) {
        switch command.kind {
        case .drag:
            if command.phase == .began {
                action()
            }
        case .wheel:
            if command.phase == .began || command.phase == .changed {
                action()
            }
        case .momentum:
            return
        }
    }
}
