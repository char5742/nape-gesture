import Foundation
import NapeGestureCore

final class GestureActionExecutor {
    private let bindings: GestureBindings
    private let poster: EventPoster

    init(bindings: GestureBindings, poster: EventPoster = EventPoster()) {
        self.bindings = bindings
        self.poster = poster
    }

    func post(
        command: GestureCommand,
        completion: GestureActionDeliveryCompletionHandler? = nil
    ) -> GestureActionPostResult {
        let action = bindings.action(for: command)
        let eventCompletion = eventDeliveryCompletion(action: action, completion: completion)

        switch action {
        case .none:
            return GestureActionPostResult(action: action, postResult: .none)
        case .smoothScroll:
            return GestureActionPostResult(
                action: action,
                postResult: poster.postScroll(
                    command: command,
                    mode: .free,
                    axDelivery: .asynchronous,
                    completion: eventCompletion
                )
            )
        case .horizontalScroll:
            return GestureActionPostResult(
                action: action,
                postResult: poster.postScroll(
                    command: command,
                    mode: .horizontal,
                    axDelivery: .asynchronous,
                    completion: eventCompletion
                )
            )
        case .spaceLeft:
            return GestureActionPostResult(
                action: action,
                postResult: poster.postScroll(
                    command: command,
                    mode: .forcedHorizontal(sign: -1),
                    completion: eventCompletion
                )
            )
        case .spaceRight:
            return GestureActionPostResult(
                action: action,
                postResult: poster.postScroll(
                    command: command,
                    mode: .forcedHorizontal(sign: 1),
                    completion: eventCompletion
                )
            )
        case .missionControl:
            return postDiscrete(action: action, command: command) {
                poster.postMissionControl(delivery: .asynchronous, completion: eventCompletion)
            }
        case .pageBack:
            return postDiscrete(action: action, command: command) {
                poster.postPageBack(delivery: .asynchronous, completion: eventCompletion)
            }
        case .pageForward:
            return postDiscrete(action: action, command: command) {
                poster.postPageForward(delivery: .asynchronous, completion: eventCompletion)
            }
        case .zoomIn:
            return postDiscrete(action: action, command: command) {
                poster.postZoomIn(delivery: .asynchronous, completion: eventCompletion)
            }
        case .zoomOut:
            return postDiscrete(action: action, command: command) {
                poster.postZoomOut(delivery: .asynchronous, completion: eventCompletion)
            }
        }
    }

    func supportsMomentum(for command: GestureCommand) -> Bool {
        bindings.action(for: command).supportsMomentum
    }

    func prepareScrollTarget(synchronously: Bool = false) {
        poster.prepareAXWebScrollTarget(synchronously: synchronously)
    }

    private func eventDeliveryCompletion(
        action: GestureAction,
        completion: GestureActionDeliveryCompletionHandler?
    ) -> EventDeliveryCompletionHandler? {
        guard let completion else {
            return nil
        }
        return { eventCompletion in
            completion(
                GestureActionPostResult(action: action, postResult: eventCompletion.postResult),
                eventCompletion.startedAtNanoseconds,
                eventCompletion.finishedAtNanoseconds
            )
        }
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

typealias GestureActionDeliveryCompletionHandler = (GestureActionPostResult, UInt64, UInt64) -> Void

struct GestureActionPostResult: Equatable {
    var action: GestureAction
    var generatedEventCount: Int
    var failedEventCreationCount: Int
    var deliveryDeferred: Bool

    init(action: GestureAction, postResult: EventPostResult) {
        self.action = action
        generatedEventCount = postResult.generatedEventCount
        failedEventCreationCount = postResult.failedEventCreationCount
        deliveryDeferred = postResult.deliveryDeferred
    }
}
