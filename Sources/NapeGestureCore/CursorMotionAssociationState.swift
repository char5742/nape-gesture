/// mouse移動とcursor位置の連動状態を、OS API呼び出しの成否と同期して保持する。
public struct CursorMotionAssociationState: Equatable, Sendable {
    public private(set) var isSuppressed: Bool

    public init(isSuppressed: Bool = false) {
        self.isSuppressed = isSuppressed
    }

    @discardableResult
    public mutating func suppress(
        using setAssociationEnabled: (Bool) -> Bool
    ) -> Bool {
        guard !isSuppressed else {
            return true
        }
        guard setAssociationEnabled(false) else {
            return false
        }
        isSuppressed = true
        return true
    }

    @discardableResult
    public mutating func restore(
        force: Bool = false,
        using setAssociationEnabled: (Bool) -> Bool
    ) -> Bool {
        guard force || isSuppressed else {
            return true
        }
        guard setAssociationEnabled(true) else {
            return false
        }
        isSuppressed = false
        return true
    }
}
