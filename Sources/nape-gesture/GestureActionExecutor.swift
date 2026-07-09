import Foundation
import NapeGestureCore

final class GestureActionExecutor {
    private let bindings: GestureBindings
    private let poster: EventPoster

    init(bindings: GestureBindings, poster: EventPoster = EventPoster()) {
        self.bindings = bindings
        self.poster = poster
    }

    func post(command: GestureCommand) -> GestureActionPostResult {
        let action = bindings.action(for: command)

        switch action {
        case .none:
            return GestureActionPostResult(action: action, postResult: .none)
        case .smoothScroll:
            return GestureActionPostResult(action: action, postResult: poster.postScroll(command: command, mode: .free))
        case .horizontalScroll:
            return GestureActionPostResult(action: action, postResult: poster.postScroll(command: command, mode: .horizontal))
        case .spaceLeft:
            return GestureActionPostResult(
                action: action,
                postResult: poster.postScroll(command: command, mode: .forcedHorizontal(sign: -1))
            )
        case .spaceRight:
            return GestureActionPostResult(
                action: action,
                postResult: poster.postScroll(command: command, mode: .forcedHorizontal(sign: 1))
            )
        case .missionControl:
            return postDiscrete(action: action, command: command) {
                poster.postMissionControl()
            }
        case .pageBack:
            return postDiscrete(action: action, command: command) {
                poster.postPageBack()
            }
        case .pageForward:
            return postDiscrete(action: action, command: command) {
                poster.postPageForward()
            }
        case .zoomIn:
            return postDiscrete(action: action, command: command) {
                poster.postZoomIn()
            }
        case .zoomOut:
            return postDiscrete(action: action, command: command) {
                poster.postZoomOut()
            }
        }
    }

    func supportsMomentum(for command: GestureCommand) -> Bool {
        bindings.action(for: command).supportsMomentum
    }

    private func postDiscrete(
        action: GestureAction,
        command: GestureCommand,
        post: () -> EventPostResult
    ) -> GestureActionPostResult {
        switch command.kind {
        case .drag:
            if command.phase == .began {
                return GestureActionPostResult(action: action, postResult: post())
            }
        case .wheel:
            if command.phase == .began || command.phase == .changed {
                return GestureActionPostResult(action: action, postResult: post())
            }
        case .momentum:
            break
        }
        return GestureActionPostResult(action: action, postResult: .none)
    }
}

struct GestureActionPostResult: Equatable {
    var action: GestureAction
    var generatedEventCount: Int
    var failedEventCreationCount: Int

    init(action: GestureAction, postResult: EventPostResult) {
        self.action = action
        generatedEventCount = postResult.generatedEventCount
        failedEventCreationCount = postResult.failedEventCreationCount
    }
}
