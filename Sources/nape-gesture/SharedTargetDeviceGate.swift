import Foundation
import NapeGestureCore

final class SharedTargetDeviceGate {
    private let lock = NSLock()
    private var state: TargetDeviceGateState

    init(configuration: TargetDeviceGateConfiguration) {
        state = TargetDeviceGateState(configuration: configuration)
    }

    func record(
        _ activity: TargetDeviceActivity,
        isTargetDevice: Bool = true
    ) -> TargetDeviceGateRecordDecision {
        lock.lock()
        let result = state.record(activity, isTargetDevice: isTargetDevice)
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        state.reset()
        lock.unlock()
    }

    func decision(for event: RawInputEvent) -> TargetDeviceGateDecision {
        lock.lock()
        let result = state.decision(for: event)
        lock.unlock()
        return result
    }
}
