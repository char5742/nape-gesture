import Foundation

public enum TrackpadGestureMode: String, Equatable, Sendable, CaseIterable {
    case none
    case twoFingerSwipe
    case systemSwipe
    case pinch

    public var displayName: String {
        switch self {
        case .none: "通常"
        case .twoFingerSwipe: "2本指スクロール / スワイプ"
        case .systemSwipe: "システムスワイプ"
        case .pinch: "ピンチ"
        }
    }
}

extension TrackpadGestureMode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case Self.none.rawValue:
            self = .none
        case Self.twoFingerSwipe.rawValue, "scrollAndNavigate":
            self = .twoFingerSwipe
        case Self.systemSwipe.rawValue, "spacesAndMissionControl":
            self = .systemSwipe
        case Self.pinch.rawValue, "zoom":
            self = .pinch
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "未対応のtrackpad gesture modeです: \(rawValue)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
