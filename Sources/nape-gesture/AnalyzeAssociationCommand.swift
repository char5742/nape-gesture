import Foundation
import NapeGestureCore

struct AnalyzeAssociationCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let positional = positionalArguments()
        guard positional.count >= 2 else {
            throw ToolError.missingValue("HIDログとイベントログ")
        }

        let window = try windowValue()
        let hidRecords = try loadHIDRecords(from: positional[0])
        let eventRecords = try InputLogFileReader.readRecords(path: positional[1])
        let analysis = InputAssociationAnalyzer.analyze(
            hidRecords: hidRecords,
            eventTapRecords: eventRecords,
            associationWindowSeconds: window
        )
        let assertValidWindow = options.contains("--assert-valid-window")

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(analysis)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(format(analysis, window: window))
        }

        if assertValidWindow && !analysis.hasValidAssociationWindowEvidence {
            fflush(stdout)
            throw AssociationWindowAssertionError(analysis: analysis, window: window)
        }
    }

    private func positionalArguments() -> [String] {
        var result: [String] = []
        var index = 0
        while index < options.count {
            let option = options[index]
            if option == "--window" {
                index += 2
                continue
            }
            if option.hasPrefix("--") {
                index += 1
                continue
            }
            result.append(option)
            index += 1
        }
        return result
    }

    private func windowValue() throws -> TimeInterval {
        guard options.contains("--window") else {
            return TargetDeviceAssociationConfiguration.defaultAssociationWindow
        }
        let raw = try SettingsStore.requiredValue(for: "--window", in: options)
        guard let value = TimeInterval(raw), value > 0 else {
            throw ToolError.invalidValue("--window", raw)
        }
        return value
    }

    private func loadHIDRecords(from path: String) throws -> [HIDInputLogRecord] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let content = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()

        return try content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                try decoder.decode(HIDInputLogRecord.self, from: Data(line.utf8))
            }
    }

    private func format(_ analysis: InputAssociationAnalysis, window: TimeInterval) -> String {
        var lines = [
            "HID / イベントタップ紐づけ解析",
            "associationWindow: \(format(window)) 秒",
            "HIDログ総数: \(analysis.totalHIDEvents)",
            "イベントタップログ総数: \(analysis.totalEventTapEvents)",
            "解析対象イベントタップ数: \(analysis.analyzedEventTapEvents)",
            "生成イベント除外数: \(analysis.excludedGeneratedEventTapEvents)",
            "互換HID候補あり数: \(analysis.hidCandidateEventCount)",
            "互換HID候補なし数: \(analysis.missingHIDCandidateEventCount)",
            "非互換HID近傍数: \(analysis.incompatibleHIDCandidateEventCount)",
            "採用HIDデバイス数: \(analysis.matchedHIDDeviceIDs.count)",
            "associationWindow内: \(analysis.withinWindowCount)",
            "associationWindow外: \(analysis.outsideWindowCount)",
            "最大時刻差: \(format(analysis.maximumTimeDifferenceSeconds)) 秒",
            "p95時刻差: \(format(analysis.p95TimeDifferenceSeconds)) 秒",
            "p99時刻差: \(format(analysis.p99TimeDifferenceSeconds)) 秒",
            "推奨associationWindow: \(format(analysis.suggestedAssociationWindowSeconds)) 秒"
        ]

        if analysis.missingHIDCandidateEventCount > 0 {
            lines.append("所見: 一致候補になる互換 HID 入力がないイベントタップ入力があります。ログの同時取得範囲、対象デバイス条件、HID usage を確認してください。")
        }
        if analysis.incompatibleHIDCandidateEventCount > 0 {
            lines.append("所見: 近い HID 入力はありますが、イベントタップ入力の種別と HID usage が一致しない入力があります。button / axis / wheel の記録を確認してください。")
        }
        if analysis.matchedHIDDeviceIDs.count > 1 {
            lines.append("所見: 複数の HID デバイスが採用されています。対象デバイスだけに絞った HID ログで取り直してください。")
        }
        if analysis.outsideWindowCount > 0 {
            lines.append("所見: 現在の associationWindow 外に出るイベントタップ入力があります。実機ログを根拠に associationWindow を調整してください。")
        }
        if analysis.hasValidAssociationWindowEvidence {
            lines.append("所見: 解析対象のイベントタップ入力は現在の associationWindow 内に収まっています。")
        }

        return lines.joined(separator: "\n")
    }

    private func format(_ value: TimeInterval) -> String {
        String(format: "%.4f", value)
    }
}

struct AssociationWindowAssertionError: LocalizedError {
    var analysis: InputAssociationAnalysis
    var window: TimeInterval

    var errorDescription: String? {
        if analysis.analyzedEventTapEvents == 0 {
            return "associationWindow を検証できるイベントタップ入力がありません。対象デバイス操作を含むログを指定してください。"
        }
        return "associationWindow \(String(format: "%.4f", window)) 秒の検証に失敗しました。互換HID候補なし \(analysis.missingHIDCandidateEventCount) 件、非互換HID近傍 \(analysis.incompatibleHIDCandidateEventCount) 件、採用HIDデバイス \(analysis.matchedHIDDeviceIDs.count) 件、window外 \(analysis.outsideWindowCount) 件です。`analyze-association <hid-log> <event-log> --window <秒> --json` で matches を確認してください。"
    }
}
