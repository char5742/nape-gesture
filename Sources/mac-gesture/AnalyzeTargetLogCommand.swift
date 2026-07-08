import Foundation

struct AnalyzeTargetLogCommand {
    private let options: [String]

    init(options: [String]) {
        self.options = options
    }

    func run() throws {
        guard let path = options.first else {
            throw ToolError.missingValue("target-log path")
        }

        let records = try loadRecords(from: path)
        let analysis = TargetEventLogAnalyzer.analyze(records)

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(analysis)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(TargetEventLogAnalyzer.japaneseReport(for: analysis))
        }
    }

    private func loadRecords(from path: String) throws -> [TargetEventRecord] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = JSONDecoder()
        var records: [TargetEventRecord] = []

        for (index, line) in text.split(separator: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            guard let data = trimmed.data(using: .utf8) else {
                throw ToolError.invalidValue("target-log \(index + 1) 行目", String(trimmed))
            }

            do {
                records.append(try decoder.decode(TargetEventRecord.self, from: data))
            } catch {
                throw ToolError.invalidValue("target-log \(index + 1) 行目", error.localizedDescription)
            }
        }

        return records
    }
}

struct TargetEventLogAnalysis: Codable, Equatable {
    var totalEvents: Int
    var scrollEvents: Int
    var preciseScrollEvents: Int
    var swipeEvents: Int
    var magnifyEvents: Int
    var rotateEvents: Int
    var mouseEvents: Int
    var scrollingDeltaXTotal: Double
    var scrollingDeltaYTotal: Double
    var deltaXTotal: Double
    var deltaYTotal: Double
    var magnificationTotal: Double
    var rotationTotal: Double
    var eventCounts: [String: Int]
    var phaseCounts: [String: Int]
    var momentumPhaseCounts: [String: Int]
}

enum TargetEventLogAnalyzer {
    static func analyze(_ records: [TargetEventRecord]) -> TargetEventLogAnalysis {
        let scrollRecords = records.filter { $0.name == "scrollWheel" }
        let swipeRecords = records.filter { $0.name == "swipe" }
        let magnifyRecords = records.filter { $0.name == "magnify" }
        let rotateRecords = records.filter { $0.name == "rotate" }
        let mouseRecords = records.filter {
            $0.name == "mouseDown"
                || $0.name == "mouseUp"
                || $0.name == "mouseDragged"
                || $0.name == "otherMouseDown"
                || $0.name == "otherMouseUp"
                || $0.name == "otherMouseDragged"
        }

        return TargetEventLogAnalysis(
            totalEvents: records.count,
            scrollEvents: scrollRecords.count,
            preciseScrollEvents: scrollRecords.filter(\.hasPreciseScrollingDeltas).count,
            swipeEvents: swipeRecords.count,
            magnifyEvents: magnifyRecords.count,
            rotateEvents: rotateRecords.count,
            mouseEvents: mouseRecords.count,
            scrollingDeltaXTotal: scrollRecords.reduce(0) { $0 + $1.scrollingDeltaX },
            scrollingDeltaYTotal: scrollRecords.reduce(0) { $0 + $1.scrollingDeltaY },
            deltaXTotal: records.reduce(0) { $0 + $1.deltaX },
            deltaYTotal: records.reduce(0) { $0 + $1.deltaY },
            magnificationTotal: magnifyRecords.reduce(0) { $0 + $1.magnification },
            rotationTotal: rotateRecords.reduce(0) { $0 + $1.rotation },
            eventCounts: counts(records.map(\.name)),
            phaseCounts: counts(records.map { String($0.phase) }),
            momentumPhaseCounts: counts(scrollRecords.map { String($0.momentumPhase) })
        )
    }

    static func japaneseReport(for analysis: TargetEventLogAnalysis) -> String {
        """
        Targetログ解析結果
        総イベント数: \(analysis.totalEvents)
        scrollWheel: \(analysis.scrollEvents)
        precise scrollWheel: \(analysis.preciseScrollEvents)
        swipe: \(analysis.swipeEvents)
        magnify: \(analysis.magnifyEvents)
        rotate: \(analysis.rotateEvents)
        mouse系: \(analysis.mouseEvents)
        scrollingDelta 合計: x=\(format(analysis.scrollingDeltaXTotal)), y=\(format(analysis.scrollingDeltaYTotal))
        delta 合計: x=\(format(analysis.deltaXTotal)), y=\(format(analysis.deltaYTotal))
        magnification 合計: \(format(analysis.magnificationTotal))
        rotation 合計: \(format(analysis.rotationTotal))
        イベント出現数: \(formatCounts(analysis.eventCounts))
        phase 出現数: \(formatCounts(analysis.phaseCounts))
        momentumPhase 出現数: \(formatCounts(analysis.momentumPhaseCounts))
        """
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for value in values {
            result[value, default: 0] += 1
        }
        return result
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatCounts(_ counts: [String: Int]) -> String {
        if counts.isEmpty {
            return "-"
        }
        return counts
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}
