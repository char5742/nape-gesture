import Foundation
import NapeGestureCore
import NapeGestureProductOutput

final class GestureActionExecutor {
    private let coordinator: ProductGestureSessionCoordinator

    init(
        output: any ProductGestureOutput = TrackpadGestureOutputAdapter(),
        sessionSequence: TrackpadOutputSessionSequence = TrackpadOutputSessionSequence()
    ) {
        coordinator = ProductGestureSessionCoordinator(
            output: output,
            sessionSequence: sessionSequence
        )
    }

    func ensureOutputAvailable() throws {
        switch coordinator.capability.status {
        case .supported:
            let unsupported = coordinator.unsupportedRequiredFamilies
            guard unsupported.isEmpty else {
                let names = unsupported.map(\.rawValue).sorted().joined(separator: ", ")
                throw ToolError.trackpadOutputContractUnavailable(
                    "固定ジェスチャーに必要なproduct output familyが未対応です: \(names)"
                )
            }
        case .unsupported:
            throw ToolError.trackpadOutputContractUnavailable(
                coordinator.capability.reason ?? "trackpad output contractが未対応です。"
            )
        case .contractMismatch:
            throw ToolError.trackpadOutputContractMismatch(
                coordinator.capability.reason ?? "trackpad output contractが現在のOSと一致しません。"
            )
        }
    }

    func post(
        command: GestureCommand,
        continuation: TrackpadOutputContinuation? = nil
    ) -> GestureActionPostResult {
        let post = coordinator.post(command: command, continuation: continuation)
        return GestureActionPostResult(action: post.action, productResult: post.result)
    }

    func supportsMomentum(for command: GestureCommand) -> Bool {
        coordinator.supportsMomentum(for: command)
    }

    @discardableResult
    func cancelActive(
        reason: TrackpadOutputCancellationReason,
        at time: TimeInterval
    ) -> ProductGestureOutputResult {
        coordinator.cancelActive(reason: reason, at: time)
    }

    func reset() {
        coordinator.reset()
    }
}

struct GestureActionPostResult: Equatable {
    var action: GestureAction
    var generatedEventCount: Int
    var failedEventCreationCount: Int
    var outputFailure: ProductGestureOutputFailure?

    init(action: GestureAction) {
        self.action = action
        generatedEventCount = 0
        failedEventCreationCount = 0
        outputFailure = nil
    }

    init(action: GestureAction, productResult: ProductGestureOutputResult) {
        self.action = action
        generatedEventCount = productResult.generatedEventCount
        failedEventCreationCount = productResult.failedEventCreationCount
        outputFailure = productResult.failure
    }
}
