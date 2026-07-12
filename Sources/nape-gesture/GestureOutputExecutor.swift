import Foundation
import NapeGestureCore
import NapeGestureProductOutput

final class GestureOutputExecutor {
    private let coordinator: ProductGestureSessionCoordinator

    init(
        enabledModes: Set<TrackpadGestureMode>,
        output: any ProductGestureOutput = TrackpadGestureOutputAdapter(),
        sessionSequence: TrackpadOutputSessionSequence = TrackpadOutputSessionSequence()
    ) {
        coordinator = ProductGestureSessionCoordinator(
            enabledModes: enabledModes,
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
                    "設定中のmodeに必要なproduct output familyが未対応です: \(names)"
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
    ) -> GestureOutputPostResult {
        let post = coordinator.post(command: command, continuation: continuation)
        return GestureOutputPostResult(
            mode: post.mode,
            family: post.family,
            productResult: post.result
        )
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

struct GestureOutputPostResult: Equatable {
    var mode: TrackpadGestureMode
    var family: TrackpadOutputEventFamily?
    var generatedEventCount: Int
    var failedEventCreationCount: Int
    var outputFailure: ProductGestureOutputFailure?

    init(mode: TrackpadGestureMode, family: TrackpadOutputEventFamily? = nil) {
        self.mode = mode
        self.family = family
        generatedEventCount = 0
        failedEventCreationCount = 0
        outputFailure = nil
    }

    init(
        mode: TrackpadGestureMode,
        family: TrackpadOutputEventFamily?,
        productResult: ProductGestureOutputResult
    ) {
        self.mode = mode
        self.family = family
        generatedEventCount = productResult.generatedEventCount
        failedEventCreationCount = productResult.failedEventCreationCount
        outputFailure = productResult.failure
    }
}
