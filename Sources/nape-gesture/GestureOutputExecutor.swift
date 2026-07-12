import NapeGestureCore
import NapeGestureProductOutput

final class GestureOutputExecutor {
    private let coordinator: FixedGestureProductSessionCoordinator

    init(output: any ProductGestureOutput = TrackpadGestureOutputAdapter()) {
        coordinator = FixedGestureProductSessionCoordinator(output: output)
    }

    func ensureOutputAvailable() throws {
        switch coordinator.capability.status {
        case .supported:
            let unsupported = coordinator.unsupportedRequiredFamilies
            guard unsupported.isEmpty else {
                let names = unsupported.map(\.rawValue).sorted().joined(separator: ", ")
                throw ToolError.trackpadOutputContractUnavailable(
                    "固定gesture classに必要なproduct output familyが未対応です: \(names)"
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

    func post(command: FixedGestureInputCommand) -> GestureOutputPostResult {
        let post = coordinator.post(command)
        return GestureOutputPostResult(
            gestureClass: post.gestureClass,
            family: post.family,
            productResult: post.result
        )
    }

    @discardableResult
    func cancelActive(
        reason: TrackpadOutputCancellationReason,
        timestamp: MonotonicEventTimestamp
    ) -> ProductGestureOutputResult {
        coordinator.cancelActive(reason: reason, timestamp: timestamp)
    }

    func reset() {
        coordinator.reset()
    }
}

struct GestureOutputPostResult: Equatable {
    var gestureClass: FixedGestureClass
    var family: TrackpadOutputEventFamily
    var generatedEventCount: Int
    var failedEventCreationCount: Int
    var outputFailure: ProductGestureOutputFailure?
    var failureDetails: String?

    init(
        gestureClass: FixedGestureClass,
        family: TrackpadOutputEventFamily,
        productResult: ProductGestureOutputResult
    ) {
        self.gestureClass = gestureClass
        self.family = family
        generatedEventCount = productResult.generatedEventCount
        failedEventCreationCount = productResult.failedEventCreationCount
        outputFailure = productResult.failure
        failureDetails = productResult.failureDetails
    }
}
