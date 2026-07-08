import Foundation
import NapeGestureCore

struct AnalyzeLogCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        guard let path = options.first, !path.hasPrefix("--") else {
            throw ToolError.missingValue("ログファイル")
        }

        let records = try InputLogFileReader.readRecords(path: path)
        let analysis = InputLogAnalyzer.analyze(records)

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(analysis)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(InputLogAnalyzer.japaneseReport(for: analysis))
        }
    }

}
