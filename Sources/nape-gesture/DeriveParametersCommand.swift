import Foundation
import NapeGestureCore

struct DeriveParametersCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        guard let path = options.first, !path.hasPrefix("--") else {
            throw ToolError.missingValue("ログファイル")
        }

        let records = try InputLogFileReader.readRecords(path: path)
        let report = LogDerivedTuningAnalyzer.derive(from: records)

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print(LogDerivedTuningAnalyzer.japaneseReport(for: report))
    }
}
