import Foundation
import NapeGestureCore

final class AnalyzeHIDLogCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        guard let path = options.first, !path.hasPrefix("--") else {
            throw ToolError.missingValue("path")
        }

        let records = try loadRecords(from: path)
        let analysis = HIDInputLogAnalyzer.analyze(records)

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(analysis)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print(format(analysis))
    }

    private func loadRecords(from path: String) throws -> [HIDInputLogRecord] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let content = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()

        return try content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                let lineData = Data(line.utf8)
                return try decoder.decode(HIDInputLogRecord.self, from: lineData)
            }
    }

    private func format(_ analysis: HIDInputLogAnalysis) -> String {
        var lines = [
            "HID入力イベント数: \(analysis.totalEvents)",
            "デバイス数: \(analysis.deviceCount)",
            "usage 種類数: \(analysis.usageSummaries.count)"
        ]

        for summary in analysis.usageSummaries {
            lines.append(
                "- \(summary.device.displayName) usagePage=\(summary.usagePage) usage=\(summary.usage) "
                    + "events=\(summary.eventCount) nonZero=\(summary.nonZeroEventCount) "
                    + "integer=\(summary.integerMin)...\(summary.integerMax) "
                    + "scaled=\(summary.scaledMin)...\(summary.scaledMax) "
                    + "stableId=\(summary.device.stableID)"
            )
            lines.append(
                "  設定例: nape-gesture init-config "
                    + "--vendor-id \(summary.device.vendorID) "
                    + "--product-id \(summary.device.productID) "
                    + "--usage-page \(summary.usagePage) "
                    + "--usage \(summary.usage) "
                    + "--out nape-gesture.config.json"
            )
        }

        return lines.joined(separator: "\n")
    }
}
