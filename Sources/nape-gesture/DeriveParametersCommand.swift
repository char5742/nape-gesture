import Foundation
import NapeGestureCore

struct DeriveParametersCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        guard let path = options.first(where: { !$0.hasPrefix("--") }) else {
            throw ToolError.missingValue("ログファイル")
        }
        let assertComplete = options.contains("--assert-complete")

        let records = try InputLogFileReader.readRecords(path: path)
        let report = LogDerivedTuningAnalyzer.derive(from: records)

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(LogDerivedTuningAnalyzer.japaneseReport(for: report))
        }

        if assertComplete && !report.hasCompleteTuningEvidence {
            fflush(stdout)
            throw TuningDerivationIncompleteAssertionError(
                path: path,
                failures: report.completeTuningEvidenceFailures
            )
        }
    }
}

struct TuningDerivationIncompleteAssertionError: LocalizedError {
    var path: String
    var failures: [String]

    var errorDescription: String? {
        let details = failures.map { "- \($0)" }.joined(separator: "\n")
        return """
        ログ由来パラメータの完了証跡として不足があります: \(path)
        \(details)
        """
    }
}
