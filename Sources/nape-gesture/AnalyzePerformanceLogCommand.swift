import Foundation
import NapeGestureCore

struct AnalyzePerformanceLogCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        let path = try requiredPath()
        let records = try readRecords(path: path)
        let report = RuntimePerformanceAnalyzer.analyze(records: records)

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(format(report))
        }

        if options.contains("--assert-baseline") {
            let evaluation = RuntimePerformanceAnalyzer.evaluate(report)
            if evaluation.passed {
                fputs("runtime 性能基準: 合格\n", stderr)
            } else {
                throw RuntimePerformanceBaselineAssertionError(message: evaluation.failureDescription)
            }
        }
    }

    private func requiredPath() throws -> String {
        guard let path = options.first, !path.hasPrefix("--") else {
            throw ToolError.missingValue("performance log path")
        }
        return path
    }

    private func readRecords(path: String) throws -> [RuntimePerformanceRecord] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = JSONDecoder()
        var records: [RuntimePerformanceRecord] = []

        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            guard let data = trimmed.data(using: .utf8) else {
                throw ToolError.invalidValue("performance log \(index + 1) 行目", trimmed)
            }
            do {
                records.append(try decoder.decode(RuntimePerformanceRecord.self, from: data))
            } catch {
                throw ToolError.invalidValue("performance log \(index + 1) 行目", error.localizedDescription)
            }
        }

        return records
    }

    private func format(_ report: RuntimePerformanceReport) -> String {
        """
        runtime 性能ログ解析
        スキーマ版: \(report.schemaVersion)
        測定種別: \(report.measurementKind)
        測定範囲: \(report.measurementScope)
        イベントタップから投稿までを含む: \(report.includesEventTapAndPosting ? "はい" : "いいえ")
        レコード数: \(report.recordCount)
        投稿ありレコード数: \(report.postedRecordCount)
        説明不能な投稿欠落レコード数: \(report.missingPostRecordCount)
        生成イベント数: \(report.generatedEventCount)
        イベント作成失敗数: \(report.failedEventCreationCount)
        tap callback から投稿直前 p95: \(formatMilliseconds(report.tapToFirstPostNanoseconds.p95Nanoseconds)) ms
        tap callback から投稿直前 p99: \(formatMilliseconds(report.tapToFirstPostNanoseconds.p99Nanoseconds)) ms
        tap callback から投稿完了 p95: \(formatMilliseconds(report.tapToPostFinishedNanoseconds.p95Nanoseconds)) ms
        tap callback から投稿完了 p99: \(formatMilliseconds(report.tapToPostFinishedNanoseconds.p99Nanoseconds)) ms
        認識処理 p95: \(formatMilliseconds(report.recognizerNanoseconds.p95Nanoseconds)) ms
        投稿処理 p95: \(formatMilliseconds(report.postingNanoseconds.p95Nanoseconds)) ms
        """
    }

    private func formatMilliseconds(_ nanoseconds: Double) -> String {
        String(format: "%.3f", nanoseconds / 1_000_000)
    }
}

private struct RuntimePerformanceBaselineAssertionError: LocalizedError {
    var message: String

    var errorDescription: String? {
        "runtime 性能基準を満たしていません。\n\(message)"
    }
}
