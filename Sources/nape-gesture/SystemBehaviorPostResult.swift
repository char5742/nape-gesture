enum SystemBehaviorPostResultStatus: Equatable {
    case success
    case eventCreationFailure(count: Int)
    case noGeneratedEvents

    var failureName: String? {
        switch self {
        case .success:
            return nil
        case .eventCreationFailure:
            return "CGEvent timestamp"
        case .noGeneratedEvents:
            return "system-test posting"
        }
    }

    var failureDescription: String? {
        switch self {
        case .success:
            return nil
        case .eventCreationFailure:
            return "現在の起動後単調時刻から60秒以内の値を生成できませんでした。"
        case .noGeneratedEvents:
            return "イベントを配送できなかったか、対象に変化がなかったため、生成イベント数が0件でした。"
        }
    }
}

struct SystemBehaviorPostResultSnapshot: Equatable {
    var generatedEventCount: Int
    var failedEventCreationCount: Int

    static func combined(_ snapshots: [Self]) -> Self {
        snapshots.reduce(
            Self(generatedEventCount: 0, failedEventCreationCount: 0)
        ) { result, snapshot in
            Self(
                generatedEventCount: result.generatedEventCount + snapshot.generatedEventCount,
                failedEventCreationCount: result.failedEventCreationCount + snapshot.failedEventCreationCount
            )
        }
    }

    var status: SystemBehaviorPostResultStatus {
        if failedEventCreationCount > 0 {
            return .eventCreationFailure(count: failedEventCreationCount)
        }
        if generatedEventCount == 0 {
            return .noGeneratedEvents
        }
        return .success
    }
}
