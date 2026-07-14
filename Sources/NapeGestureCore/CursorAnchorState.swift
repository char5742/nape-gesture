import Foundation

public struct CursorAnchorPosition: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

public struct CursorAnchorSession: Equatable, Sendable {
    public let sessionID: TrackpadOutputSessionID
    public let sourceButton: MouseButton
    public let position: CursorAnchorPosition

    public init(
        sessionID: TrackpadOutputSessionID,
        sourceButton: MouseButton,
        position: CursorAnchorPosition
    ) {
        self.sessionID = sessionID
        self.sourceButton = sourceButton
        self.position = position
    }
}

public enum CursorAnchorStateError: Error, Equatable, Sendable {
    case invalidPosition(CursorAnchorPosition)
    case missingSourcePosition
    case invalidCommand(phase: FixedGestureInputPhase, sourceKind: GestureInputSourceKind)
    case alreadyActive(TrackpadOutputSessionID)
    case missingAnchor
    case sessionMismatch(
        expected: TrackpadOutputSessionID,
        actual: TrackpadOutputSessionID
    )
    case sourceButtonMismatch(expected: MouseButton, actual: MouseButton)
}

extension CursorAnchorStateError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidPosition(position):
            "cursor anchor座標が有限値ではありません: x=\(position.x), y=\(position.y)"
        case .missingSourcePosition:
            "gesture開始eventにcursor座標がありません。"
        case let .invalidCommand(phase, sourceKind):
            "cursor anchor処理の入力契約が不正です: phase=\(phase.rawValue), source=\(sourceKind.rawValue)"
        case let .alreadyActive(sessionID):
            "cursor anchorが既に有効です: session=\(sessionID.rawValue)"
        case .missingAnchor:
            "有効なcursor anchorがありません。"
        case let .sessionMismatch(expected, actual):
            "cursor anchorのsessionが一致しません: expected=\(expected.rawValue), actual=\(actual.rawValue)"
        case let .sourceButtonMismatch(expected, actual):
            "cursor anchorのsource buttonが一致しません: expected=\(expected.rawValue), actual=\(actual.rawValue)"
        }
    }
}

public enum CursorAnchorPreparation: Equatable, Sendable {
    case noWarp
    case warp(CursorAnchorSession)
}

/// gesture sessionと絶対cursor anchorの所有関係だけを保持する。
public struct CursorAnchorState: Equatable, Sendable {
    public private(set) var activeAnchor: CursorAnchorSession?

    public init(activeAnchor: CursorAnchorSession? = nil) {
        self.activeAnchor = activeAnchor
    }

    public var isActive: Bool {
        activeAnchor != nil
    }

    public mutating func prepare(
        for command: FixedGestureInputCommand,
        sourcePosition: CursorAnchorPosition?
    ) throws -> CursorAnchorPreparation {
        switch (command.phase, command.sourceKind) {
        case (.began, .buttonDown):
            guard let sourcePosition else {
                throw CursorAnchorStateError.missingSourcePosition
            }
            let anchor = try begin(
                sessionID: command.sessionID,
                sourceButton: command.sourceButton,
                position: sourcePosition
            )
            return .warp(anchor)
        case (.changed, .move):
            return .warp(
                try anchor(
                    sessionID: command.sessionID,
                    sourceButton: command.sourceButton
                )
            )
        case (.changed, .wheel), (.ended, .buttonUp), (.cancelled, .cancellation):
            _ = try anchor(
                sessionID: command.sessionID,
                sourceButton: command.sourceButton
            )
            return .noWarp
        default:
            throw CursorAnchorStateError.invalidCommand(
                phase: command.phase,
                sourceKind: command.sourceKind
            )
        }
    }

    public mutating func prepareAndWarp(
        for command: FixedGestureInputCommand,
        sourcePosition: CursorAnchorPosition?,
        using warp: (CursorAnchorPosition) throws -> Void
    ) throws {
        let preparation = try prepare(for: command, sourcePosition: sourcePosition)
        guard case let .warp(anchor) = preparation else {
            return
        }
        do {
            try warp(anchor.position)
        } catch {
            clear()
            throw error
        }
    }

    public mutating func complete(_ command: FixedGestureInputCommand) throws {
        guard command.phase == .ended || command.phase == .cancelled else {
            return
        }
        try end(
            sessionID: command.sessionID,
            sourceButton: command.sourceButton
        )
    }

    @discardableResult
    public mutating func begin(
        sessionID: TrackpadOutputSessionID,
        sourceButton: MouseButton,
        position: CursorAnchorPosition
    ) throws -> CursorAnchorSession {
        guard position.isFinite else {
            throw CursorAnchorStateError.invalidPosition(position)
        }
        if let activeAnchor {
            throw CursorAnchorStateError.alreadyActive(activeAnchor.sessionID)
        }

        let anchor = CursorAnchorSession(
            sessionID: sessionID,
            sourceButton: sourceButton,
            position: position
        )
        activeAnchor = anchor
        return anchor
    }

    public func anchor(
        sessionID: TrackpadOutputSessionID,
        sourceButton: MouseButton
    ) throws -> CursorAnchorSession {
        guard let activeAnchor else {
            throw CursorAnchorStateError.missingAnchor
        }
        guard activeAnchor.sessionID == sessionID else {
            throw CursorAnchorStateError.sessionMismatch(
                expected: activeAnchor.sessionID,
                actual: sessionID
            )
        }
        guard activeAnchor.sourceButton == sourceButton else {
            throw CursorAnchorStateError.sourceButtonMismatch(
                expected: activeAnchor.sourceButton,
                actual: sourceButton
            )
        }
        return activeAnchor
    }

    public mutating func end(
        sessionID: TrackpadOutputSessionID,
        sourceButton: MouseButton
    ) throws {
        _ = try anchor(sessionID: sessionID, sourceButton: sourceButton)
        activeAnchor = nil
    }

    public mutating func clear() {
        activeAnchor = nil
    }
}
