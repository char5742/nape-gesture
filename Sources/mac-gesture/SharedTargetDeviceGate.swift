import Foundation
import MacGestureCore

final class SharedTargetDeviceGate {
    private let lock = NSLock()
    private var state: TargetDeviceGateState

    init(configuration: TargetDeviceGateConfiguration) {
        state = TargetDeviceGateState(configuration: configuration)
    }

    func record(_ activity: TargetDeviceActivity) {
        lock.lock()
        state.record(activity)
        lock.unlock()
    }

    func shouldHandle(_ event: RawInputEvent) -> Bool {
        lock.lock()
        let result = state.shouldHandle(event)
        lock.unlock()
        return result
    }
}
