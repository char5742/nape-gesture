import Foundation
import NapeGestureCore
import NapeGestureProductOutput

final class GestureActionExecutor {
    private let bindings: GestureBindings
    private let output: any ProductGestureOutput

    init(
        bindings: GestureBindings,
        output: any ProductGestureOutput = TrackpadGestureOutputAdapter()
    ) {
        self.bindings = bindings
        self.output = output
    }

    func ensureOutputAvailable() throws {
        switch output.capability.status {
        case .supported:
            return
        case .unsupported:
            throw ToolError.trackpadOutputContractUnavailable(
                output.capability.reason ?? "trackpad output contractが未対応です。"
            )
        case .contractMismatch:
            throw ToolError.trackpadOutputContractMismatch(
                output.capability.reason ?? "trackpad output contractが現在のOSと一致しません。"
            )
        }
    }

    func post(command: GestureCommand) -> GestureActionPostResult {
        let action = bindings.action(for: command)

        guard action != .none else {
            return GestureActionPostResult(action: action)
        }
        return GestureActionPostResult(
            action: action,
            productResult: output.post(action: action, command: command)
        )
    }

    func supportsMomentum(for command: GestureCommand) -> Bool {
        output.supportsMomentum(for: bindings.action(for: command))
    }

    func cancelAll() {
        output.cancelAll()
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
