import Foundation
import NapeGestureCore

struct CompareLogCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let paths = options.filter { !$0.hasPrefix("--") }
        guard paths.count >= 2 else {
            throw ToolError.missingValue("baseline と candidate のログファイル")
        }

        let baselineRecords = try InputLogFileReader.readRecords(path: paths[0])
        let candidateRecords = try InputLogFileReader.readRecords(path: paths[1])
        let comparison = InputLogAnalyzer.compare(
            baseline: baselineRecords,
            candidate: candidateRecords
        )

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(comparison)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print(InputLogAnalyzer.japaneseReport(for: comparison))
    }
}
