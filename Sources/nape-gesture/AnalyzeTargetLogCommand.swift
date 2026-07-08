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
        let assertNoLeaks = options.contains("--assert-no-leaks")
        let assertHasUnmarkedInput = options.contains("--assert-has-unmarked-input")
        let assertHasGesture = options.contains("--assert-has-gesture")
        let assertHasGeneratedEvent = options.contains("--assert-has-generated-event")

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(analysis)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(TargetEventLogAnalyzer.japaneseReport(for: analysis))
        }

        if assertNoLeaks && !analysis.leakCandidateEvents.isEmpty {
            fflush(stdout)
            throw TargetLogLeakAssertionError(path: path, leakCandidateCount: analysis.leakCandidateEvents.count)
        }
        if assertHasUnmarkedInput && analysis.unmarkedInputEventCount == 0 {
            fflush(stdout)
            throw TargetLogMissingUnmarkedInputAssertionError(path: path)
        }
        if assertHasGesture && analysis.gestureEventCount == 0 {
            fflush(stdout)
            throw TargetLogMissingGestureAssertionError(path: path)
        }
        if assertHasGeneratedEvent && analysis.generatedEvents == 0 {
            fflush(stdout)
            throw TargetLogMissingGeneratedEventAssertionError(path: path)
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

struct TargetLogLeakAssertionError: LocalizedError {
    var path: String
    var leakCandidateCount: Int

    var errorDescription: String? {
        "target log に漏れ候補が \(leakCandidateCount) 件あります。詳細は `analyze-target-log \(path) --json` で確認してください。"
    }
}

struct TargetLogMissingUnmarkedInputAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "target log に未マーク入力がありません。通常入力通過の確認には `analyze-target-log \(path) --json` で unmarkedMouseEvents、unmarkedScrollEvents、unmarkedKeyEvents を確認してください。"
    }
}

struct TargetLogMissingGestureAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "target log に swipe / magnify / rotate がありません。Reference Target App のジェスチャー受信確認には `analyze-target-log \(path) --json` で swipeEvents、magnifyEvents、rotateEvents を確認してください。"
    }
}

struct TargetLogMissingGeneratedEventAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "target log に Nape Gesture 生成イベントがありません。ジェスチャー生成の成立確認には `analyze-target-log \(path) --json` で generatedEvents を確認してください。"
    }
}

struct TargetEventLogAnalysis: Codable, Equatable {
    var totalEvents: Int
    var generatedEvents: Int
    var unmarkedEvents: Int
    var scrollEvents: Int
    var preciseScrollEvents: Int
    var swipeEvents: Int
    var magnifyEvents: Int
    var rotateEvents: Int
    var mouseEvents: Int
    var unmarkedMouseEvents: Int
    var unmarkedScrollEvents: Int
    var unmarkedKeyEvents: Int
    var scrollingDeltaXTotal: Double
    var scrollingDeltaYTotal: Double
    var deltaXTotal: Double
    var deltaYTotal: Double
    var magnificationTotal: Double
    var rotationTotal: Double
    var eventCounts: [String: Int]
    var phaseCounts: [String: Int]
    var momentumPhaseCounts: [String: Int]
    var leakCandidateEvents: [TargetEventRecord]
    var leakCandidateCounts: [String: Int]

    var unmarkedInputEventCount: Int {
        unmarkedMouseEvents + unmarkedScrollEvents + unmarkedKeyEvents
    }

    var gestureEventCount: Int {
        swipeEvents + magnifyEvents + rotateEvents
    }
}

enum TargetEventLogAnalyzer {
    static func analyze(_ records: [TargetEventRecord]) -> TargetEventLogAnalysis {
        let scrollRecords = records.filter { $0.name == "scrollWheel" }
        let swipeRecords = records.filter { $0.name == "swipe" }
        let magnifyRecords = records.filter { $0.name == "magnify" }
        let rotateRecords = records.filter { $0.name == "rotate" }
        let mouseRecords = records.filter(isMouseEvent)
        let generatedRecords = records.filter(\.generatedByNapeGesture)
        let unmarkedRecords = records.filter { !$0.generatedByNapeGesture }
        let unmarkedMouseRecords = unmarkedRecords.filter(isMouseEvent)
        let unmarkedScrollRecords = unmarkedRecords.filter(isScrollEvent)
        let unmarkedKeyRecords = unmarkedRecords.filter(isKeyEvent)
        let leakCandidateRecords = unmarkedRecords.filter(isLeakCandidate)

        return TargetEventLogAnalysis(
            totalEvents: records.count,
            generatedEvents: generatedRecords.count,
            unmarkedEvents: unmarkedRecords.count,
            scrollEvents: scrollRecords.count,
            preciseScrollEvents: scrollRecords.filter(\.hasPreciseScrollingDeltas).count,
            swipeEvents: swipeRecords.count,
            magnifyEvents: magnifyRecords.count,
            rotateEvents: rotateRecords.count,
            mouseEvents: mouseRecords.count,
            unmarkedMouseEvents: unmarkedMouseRecords.count,
            unmarkedScrollEvents: unmarkedScrollRecords.count,
            unmarkedKeyEvents: unmarkedKeyRecords.count,
            scrollingDeltaXTotal: scrollRecords.reduce(0) { $0 + $1.scrollingDeltaX },
            scrollingDeltaYTotal: scrollRecords.reduce(0) { $0 + $1.scrollingDeltaY },
            deltaXTotal: records.reduce(0) { $0 + $1.deltaX },
            deltaYTotal: records.reduce(0) { $0 + $1.deltaY },
            magnificationTotal: magnifyRecords.reduce(0) { $0 + $1.magnification },
            rotationTotal: rotateRecords.reduce(0) { $0 + $1.rotation },
            eventCounts: counts(records.map(\.name)),
            phaseCounts: counts(records.map { String($0.phase) }),
            momentumPhaseCounts: counts(scrollRecords.map { String($0.momentumPhase) }),
            leakCandidateEvents: leakCandidateRecords,
            leakCandidateCounts: counts(leakCandidateRecords.map(\.name))
        )
    }

    static func japaneseReport(for analysis: TargetEventLogAnalysis) -> String {
        """
        Targetログ解析結果
        総イベント数: \(analysis.totalEvents)
        Nape Gesture生成イベント: \(analysis.generatedEvents)
        未マークイベント: \(analysis.unmarkedEvents)
        scrollWheel: \(analysis.scrollEvents)
        precise scrollWheel: \(analysis.preciseScrollEvents)
        swipe: \(analysis.swipeEvents)
        magnify: \(analysis.magnifyEvents)
        rotate: \(analysis.rotateEvents)
        mouse系: \(analysis.mouseEvents)
        未マークmouse系: \(analysis.unmarkedMouseEvents)
        未マークscroll系: \(analysis.unmarkedScrollEvents)
        未マークkey系: \(analysis.unmarkedKeyEvents)
        漏れ候補: \(analysis.leakCandidateEvents.count)
        漏れ候補出現数: \(formatCounts(analysis.leakCandidateCounts))
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

    private static func isLeakCandidate(_ record: TargetEventRecord) -> Bool {
        isMouseEvent(record) || isScrollEvent(record) || isKeyEvent(record)
    }

    private static func isMouseEvent(_ record: TargetEventRecord) -> Bool {
        switch record.name {
        case "mouseDown",
             "mouseUp",
             "rightMouseDown",
             "rightMouseUp",
             "otherMouseDown",
             "otherMouseUp",
             "mouseMoved",
             "mouseDragged",
             "rightMouseDragged",
             "otherMouseDragged":
            return true
        default:
            return false
        }
    }

    private static func isScrollEvent(_ record: TargetEventRecord) -> Bool {
        record.name == "scrollWheel"
    }

    private static func isKeyEvent(_ record: TargetEventRecord) -> Bool {
        record.name == "keyDown" || record.name == "keyUp"
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
