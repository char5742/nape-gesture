import Foundation

private let targetForegroundCaptureSources: Set<String> = ["sendEvent", "localMonitor", "captureView"]

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
        let assertHasUnmarkedClick = options.contains("--assert-has-unmarked-click")
        let assertHasUnmarkedDrag = options.contains("--assert-has-unmarked-drag")
        let assertHasUnmarkedWheel = options.contains("--assert-has-unmarked-wheel")
        let assertHasUnmarkedClickDragWheel = options.contains("--assert-has-unmarked-click-drag-wheel")
        let assertHasGesture = options.contains("--assert-has-gesture")
        let assertHasGeneratedEvent = options.contains("--assert-has-generated-event")
        let assertHasForegroundCapture = options.contains("--assert-has-foreground-capture")
        let assertHasGeneratedForegroundCapture = options.contains("--assert-has-generated-foreground-capture")
        let assertGeneratedForegroundScrollXPositive = options.contains("--assert-generated-foreground-scroll-x-positive")
        let assertGeneratedForegroundScrollXNegative = options.contains("--assert-generated-foreground-scroll-x-negative")
        let minimumGeneratedForegroundScrollEvents = try optionalIntValue("--assert-generated-foreground-scroll-events-at-least")
        let minimumGeneratedForegroundScrollAbsoluteX = try optionalDoubleValue("--assert-generated-foreground-scroll-abs-x-at-least")

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
        if assertHasUnmarkedClick && !analysis.hasUnmarkedClick {
            fflush(stdout)
            throw TargetLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常クリック", analysis: analysis)
        }
        if assertHasUnmarkedDrag && analysis.unmarkedDragEvents == 0 {
            fflush(stdout)
            throw TargetLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常ドラッグ", analysis: analysis)
        }
        if assertHasUnmarkedWheel && analysis.unmarkedWheelEvents == 0 {
            fflush(stdout)
            throw TargetLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常ホイール", analysis: analysis)
        }
        if assertHasUnmarkedClickDragWheel && !analysis.hasUnmarkedClickDragWheel {
            fflush(stdout)
            throw TargetLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常クリック / 通常ドラッグ / 通常ホイール", analysis: analysis)
        }
        if assertHasGesture && analysis.gestureEventCount == 0 {
            fflush(stdout)
            throw TargetLogMissingGestureAssertionError(path: path)
        }
        if assertHasGeneratedEvent && analysis.generatedEvents == 0 {
            fflush(stdout)
            throw TargetLogMissingGeneratedEventAssertionError(path: path)
        }
        if assertHasForegroundCapture && analysis.foregroundCaptureEvents == 0 {
            fflush(stdout)
            throw TargetLogMissingForegroundCaptureAssertionError(path: path)
        }
        if assertHasGeneratedForegroundCapture && analysis.generatedForegroundCaptureEvents == 0 {
            fflush(stdout)
            throw TargetLogMissingGeneratedForegroundCaptureAssertionError(path: path)
        }
        if assertGeneratedForegroundScrollXPositive && (
            analysis.canonicalGeneratedForegroundCaptureScrollingDeltaXTotal <= 0
                || analysis.canonicalGeneratedForegroundCaptureNegativeXScrollEvents > 0
        ) {
            fflush(stdout)
            throw TargetLogGeneratedForegroundScrollDirectionAssertionError(
                path: path,
                expected: "正",
                actual: analysis.canonicalGeneratedForegroundCaptureScrollingDeltaXTotal,
                positiveEvents: analysis.canonicalGeneratedForegroundCapturePositiveXScrollEvents,
                negativeEvents: analysis.canonicalGeneratedForegroundCaptureNegativeXScrollEvents
            )
        }
        if assertGeneratedForegroundScrollXNegative && (
            analysis.canonicalGeneratedForegroundCaptureScrollingDeltaXTotal >= 0
                || analysis.canonicalGeneratedForegroundCapturePositiveXScrollEvents > 0
        ) {
            fflush(stdout)
            throw TargetLogGeneratedForegroundScrollDirectionAssertionError(
                path: path,
                expected: "負",
                actual: analysis.canonicalGeneratedForegroundCaptureScrollingDeltaXTotal,
                positiveEvents: analysis.canonicalGeneratedForegroundCapturePositiveXScrollEvents,
                negativeEvents: analysis.canonicalGeneratedForegroundCaptureNegativeXScrollEvents
            )
        }
        if let minimumGeneratedForegroundScrollEvents,
           analysis.canonicalGeneratedForegroundCaptureScrollEvents < minimumGeneratedForegroundScrollEvents {
            fflush(stdout)
            throw TargetLogGeneratedForegroundScrollEventCountAssertionError(
                path: path,
                expected: minimumGeneratedForegroundScrollEvents,
                actual: analysis.canonicalGeneratedForegroundCaptureScrollEvents
            )
        }
        if let minimumGeneratedForegroundScrollAbsoluteX,
           abs(analysis.canonicalGeneratedForegroundCaptureScrollingDeltaXTotal) < minimumGeneratedForegroundScrollAbsoluteX {
            fflush(stdout)
            throw TargetLogGeneratedForegroundScrollAmountAssertionError(
                path: path,
                expected: minimumGeneratedForegroundScrollAbsoluteX,
                actual: analysis.canonicalGeneratedForegroundCaptureScrollingDeltaXTotal
            )
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

    private func optionalIntValue(_ name: String) throws -> Int? {
        guard let index = options.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = options.index(after: index)
        guard valueIndex < options.endIndex else {
            throw ToolError.missingValue(name)
        }
        let raw = options[valueIndex]
        guard let value = Int(raw), value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
    }

    private func optionalDoubleValue(_ name: String) throws -> Double? {
        guard let index = options.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = options.index(after: index)
        guard valueIndex < options.endIndex else {
            throw ToolError.missingValue(name)
        }
        let raw = options[valueIndex]
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw ToolError.invalidValue(name, raw)
        }
        return value
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

struct TargetLogMissingUnmarkedNormalInputKindAssertionError: LocalizedError {
    var path: String
    var kind: String
    var analysis: TargetEventLogAnalysis

    var errorDescription: String? {
        "target log に未マーク\(kind)がありません。`analyze-target-log \(path) --json` で unmarkedClickDownEvents=\(analysis.unmarkedClickDownEvents)、unmarkedClickUpEvents=\(analysis.unmarkedClickUpEvents)、unmarkedDragEvents=\(analysis.unmarkedDragEvents)、unmarkedWheelEvents=\(analysis.unmarkedWheelEvents) を確認してください。"
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

struct TargetLogMissingForegroundCaptureAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "target log に前面 AppKit 受信経路のイベントがありません。`analyze-target-log \(path) --json` で captureSourceCounts を確認し、globalMonitor だけの証跡を完成判定に使わないでください。"
    }
}

struct TargetLogMissingGeneratedForegroundCaptureAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "target log に前面 AppKit 受信経路へ届いた Nape Gesture 生成イベントがありません。`analyze-target-log \(path) --json` で generatedForegroundCaptureEvents と captureSourceCounts を確認してください。"
    }
}

struct TargetLogGeneratedForegroundScrollDirectionAssertionError: LocalizedError {
    var path: String
    var expected: String
    var actual: Double
    var positiveEvents: Int
    var negativeEvents: Int

    var errorDescription: String? {
        "target log の重複排除済み生成foregroundスクロールX方向が期待と違います。期待=\(expected)、合計=\(actual)、正方向イベント=\(positiveEvents)、負方向イベント=\(negativeEvents)。`analyze-target-log \(path) --json` で canonicalGeneratedForegroundCaptureScrollingDeltaXTotal と正負イベント数を確認してください。"
    }
}

struct TargetLogGeneratedForegroundScrollEventCountAssertionError: LocalizedError {
    var path: String
    var expected: Int
    var actual: Int

    var errorDescription: String? {
        "target log の重複排除済み生成foregroundスクロールイベント数が不足しています。期待=\(expected) 以上、実際=\(actual)。`analyze-target-log \(path) --json` で canonicalGeneratedForegroundCaptureScrollEvents を確認してください。"
    }
}

struct TargetLogGeneratedForegroundScrollAmountAssertionError: LocalizedError {
    var path: String
    var expected: Double
    var actual: Double

    var errorDescription: String? {
        "target log の重複排除済み生成foregroundスクロールX量が不足しています。期待=絶対値 \(expected) 以上、実際=\(actual)。`analyze-target-log \(path) --json` で canonicalGeneratedForegroundCaptureScrollingDeltaXTotal を確認してください。"
    }
}

struct TargetEventLogAnalysis: Codable, Equatable {
    var totalEvents: Int
    var generatedEvents: Int
    var unmarkedEvents: Int
    var generatedForegroundCaptureEvents: Int
    var canonicalGeneratedForegroundCaptureEvents: Int
    var canonicalGeneratedForegroundCaptureScrollEvents: Int
    var canonicalGeneratedForegroundCapturePositiveXScrollEvents: Int
    var canonicalGeneratedForegroundCaptureNegativeXScrollEvents: Int
    var scrollEvents: Int
    var preciseScrollEvents: Int
    var swipeEvents: Int
    var magnifyEvents: Int
    var rotateEvents: Int
    var mouseEvents: Int
    var unmarkedMouseEvents: Int
    var unmarkedScrollEvents: Int
    var unmarkedKeyEvents: Int
    var unmarkedClickEvents: Int
    var unmarkedClickDownEvents: Int
    var unmarkedClickUpEvents: Int
    var unmarkedDragEvents: Int
    var unmarkedWheelEvents: Int
    var scrollingDeltaXTotal: Double
    var scrollingDeltaYTotal: Double
    var canonicalGeneratedForegroundCaptureScrollingDeltaXTotal: Double
    var canonicalGeneratedForegroundCaptureScrollingDeltaYTotal: Double
    var deltaXTotal: Double
    var deltaYTotal: Double
    var magnificationTotal: Double
    var rotationTotal: Double
    var eventCounts: [String: Int]
    var phaseCounts: [String: Int]
    var momentumPhaseCounts: [String: Int]
    var captureSourceCounts: [String: Int]
    var leakCandidateEvents: [TargetEventRecord]
    var leakCandidateCounts: [String: Int]

    var unmarkedInputEventCount: Int {
        unmarkedMouseEvents + unmarkedScrollEvents + unmarkedKeyEvents
    }

    var hasUnmarkedClick: Bool {
        unmarkedClickDownEvents > 0 && unmarkedClickUpEvents > 0
    }

    var hasUnmarkedClickDragWheel: Bool {
        hasUnmarkedClick && unmarkedDragEvents > 0 && unmarkedWheelEvents > 0
    }

    var gestureEventCount: Int {
        swipeEvents + magnifyEvents + rotateEvents
    }

    var foregroundCaptureEvents: Int {
        return captureSourceCounts
            .filter { source, _ in targetForegroundCaptureSources.contains(source) }
            .map(\.value)
            .reduce(0, +)
    }
}

enum TargetEventLogAnalyzer {
    private static let foregroundCaptureSourcePriority = [
        "captureView": 0,
        "sendEvent": 1,
        "localMonitor": 2
    ]

    static func analyze(_ records: [TargetEventRecord]) -> TargetEventLogAnalysis {
        let scrollRecords = records.filter { $0.name == "scrollWheel" }
        let swipeRecords = records.filter { $0.name == "swipe" }
        let magnifyRecords = records.filter { $0.name == "magnify" }
        let rotateRecords = records.filter { $0.name == "rotate" }
        let mouseRecords = records.filter(isMouseEvent)
        let generatedRecords = records.filter(\.generatedByNapeGesture)
        let generatedForegroundCaptureRecords = generatedRecords.filter(isForegroundCapture)
        let canonicalGeneratedForegroundCaptureRecords = canonicalForegroundRecords(from: generatedForegroundCaptureRecords)
        let canonicalGeneratedForegroundCaptureScrollRecords = canonicalGeneratedForegroundCaptureRecords.filter(isScrollEvent)
        let unmarkedRecords = records.filter { !$0.generatedByNapeGesture }
        let unmarkedMouseRecords = unmarkedRecords.filter(isMouseEvent)
        let unmarkedScrollRecords = unmarkedRecords.filter(isScrollEvent)
        let unmarkedKeyRecords = unmarkedRecords.filter(isKeyEvent)
        let unmarkedClickRecords = unmarkedRecords.filter(isNormalClickEvent)
        let unmarkedClickDownRecords = unmarkedRecords.filter(isNormalClickDownEvent)
        let unmarkedClickUpRecords = unmarkedRecords.filter(isNormalClickUpEvent)
        let unmarkedDragRecords = unmarkedRecords.filter(isNormalDragEvent)
        let unmarkedWheelRecords = unmarkedRecords.filter(isWheelEvent)
        let leakCandidateRecords = unmarkedRecords.filter(isLeakCandidate)

        return TargetEventLogAnalysis(
            totalEvents: records.count,
            generatedEvents: generatedRecords.count,
            unmarkedEvents: unmarkedRecords.count,
            generatedForegroundCaptureEvents: generatedForegroundCaptureRecords.count,
            canonicalGeneratedForegroundCaptureEvents: canonicalGeneratedForegroundCaptureRecords.count,
            canonicalGeneratedForegroundCaptureScrollEvents: canonicalGeneratedForegroundCaptureScrollRecords.count,
            canonicalGeneratedForegroundCapturePositiveXScrollEvents: canonicalGeneratedForegroundCaptureScrollRecords.filter { $0.scrollingDeltaX > 0 }.count,
            canonicalGeneratedForegroundCaptureNegativeXScrollEvents: canonicalGeneratedForegroundCaptureScrollRecords.filter { $0.scrollingDeltaX < 0 }.count,
            scrollEvents: scrollRecords.count,
            preciseScrollEvents: scrollRecords.filter(\.hasPreciseScrollingDeltas).count,
            swipeEvents: swipeRecords.count,
            magnifyEvents: magnifyRecords.count,
            rotateEvents: rotateRecords.count,
            mouseEvents: mouseRecords.count,
            unmarkedMouseEvents: unmarkedMouseRecords.count,
            unmarkedScrollEvents: unmarkedScrollRecords.count,
            unmarkedKeyEvents: unmarkedKeyRecords.count,
            unmarkedClickEvents: unmarkedClickRecords.count,
            unmarkedClickDownEvents: unmarkedClickDownRecords.count,
            unmarkedClickUpEvents: unmarkedClickUpRecords.count,
            unmarkedDragEvents: unmarkedDragRecords.count,
            unmarkedWheelEvents: unmarkedWheelRecords.count,
            scrollingDeltaXTotal: scrollRecords.reduce(0) { $0 + $1.scrollingDeltaX },
            scrollingDeltaYTotal: scrollRecords.reduce(0) { $0 + $1.scrollingDeltaY },
            canonicalGeneratedForegroundCaptureScrollingDeltaXTotal: canonicalGeneratedForegroundCaptureScrollRecords.reduce(0) { $0 + $1.scrollingDeltaX },
            canonicalGeneratedForegroundCaptureScrollingDeltaYTotal: canonicalGeneratedForegroundCaptureScrollRecords.reduce(0) { $0 + $1.scrollingDeltaY },
            deltaXTotal: records.reduce(0) { $0 + $1.deltaX },
            deltaYTotal: records.reduce(0) { $0 + $1.deltaY },
            magnificationTotal: magnifyRecords.reduce(0) { $0 + $1.magnification },
            rotationTotal: rotateRecords.reduce(0) { $0 + $1.rotation },
            eventCounts: counts(records.map(\.name)),
            phaseCounts: counts(records.map { String($0.phase) }),
            momentumPhaseCounts: counts(scrollRecords.map { String($0.momentumPhase) }),
            captureSourceCounts: counts(records.map { $0.captureSource ?? "unknown" }),
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
        生成かつ前面AppKit受信: \(analysis.generatedForegroundCaptureEvents)
        生成かつ前面AppKit受信（重複排除後）: \(analysis.canonicalGeneratedForegroundCaptureEvents)
        生成foreground scrollWheel（重複排除後）: \(analysis.canonicalGeneratedForegroundCaptureScrollEvents)
        生成foreground scrollWheel X方向（重複排除後）: 正=\(analysis.canonicalGeneratedForegroundCapturePositiveXScrollEvents), 負=\(analysis.canonicalGeneratedForegroundCaptureNegativeXScrollEvents)
        scrollWheel: \(analysis.scrollEvents)
        precise scrollWheel: \(analysis.preciseScrollEvents)
        swipe: \(analysis.swipeEvents)
        magnify: \(analysis.magnifyEvents)
        rotate: \(analysis.rotateEvents)
        mouse系: \(analysis.mouseEvents)
        未マークmouse系: \(analysis.unmarkedMouseEvents)
        未マークscroll系: \(analysis.unmarkedScrollEvents)
        未マークkey系: \(analysis.unmarkedKeyEvents)
        未マーク通常クリック: \(analysis.unmarkedClickEvents)
        未マーク通常クリックdown: \(analysis.unmarkedClickDownEvents)
        未マーク通常クリックup: \(analysis.unmarkedClickUpEvents)
        未マーク通常ドラッグ: \(analysis.unmarkedDragEvents)
        未マーク通常ホイール: \(analysis.unmarkedWheelEvents)
        漏れ候補: \(analysis.leakCandidateEvents.count)
        漏れ候補出現数: \(formatCounts(analysis.leakCandidateCounts))
        scrollingDelta 合計: x=\(format(analysis.scrollingDeltaXTotal)), y=\(format(analysis.scrollingDeltaYTotal))
        生成foreground scrollingDelta 合計（重複排除後）: x=\(format(analysis.canonicalGeneratedForegroundCaptureScrollingDeltaXTotal)), y=\(format(analysis.canonicalGeneratedForegroundCaptureScrollingDeltaYTotal))
        delta 合計: x=\(format(analysis.deltaXTotal)), y=\(format(analysis.deltaYTotal))
        magnification 合計: \(format(analysis.magnificationTotal))
        rotation 合計: \(format(analysis.rotationTotal))
        イベント出現数: \(formatCounts(analysis.eventCounts))
        phase 出現数: \(formatCounts(analysis.phaseCounts))
        momentumPhase 出現数: \(formatCounts(analysis.momentumPhaseCounts))
        captureSource 出現数: \(formatCounts(analysis.captureSourceCounts))
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

    private static func canonicalForegroundRecords(from records: [TargetEventRecord]) -> [TargetEventRecord] {
        var bestRecords: [String: TargetEventRecord] = [:]

        for record in records {
            let key = eventFingerprint(for: record)
            if let current = bestRecords[key] {
                if sourcePriority(for: record) < sourcePriority(for: current) {
                    bestRecords[key] = record
                }
            } else {
                bestRecords[key] = record
            }
        }

        return bestRecords.values.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return sourcePriority(for: lhs) < sourcePriority(for: rhs)
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private static func sourcePriority(for record: TargetEventRecord) -> Int {
        guard let captureSource = record.captureSource else {
            return Int.max
        }
        return foregroundCaptureSourcePriority[captureSource] ?? Int.max
    }

    private static func eventFingerprint(for record: TargetEventRecord) -> String {
        [
            String(record.timestamp),
            record.name,
            String(record.deltaX),
            String(record.deltaY),
            String(record.scrollingDeltaX),
            String(record.scrollingDeltaY),
            String(record.phase),
            String(record.momentumPhase),
            String(record.hasPreciseScrollingDeltas),
            String(record.magnification),
            String(record.rotation),
            String(record.buttonNumber),
            String(record.clickCount),
            String(record.modifierFlags),
            record.keyCode.map(String.init) ?? "",
            String(record.generatedByNapeGesture)
        ].joined(separator: "|")
    }

    private static func isForegroundCapture(_ record: TargetEventRecord) -> Bool {
        guard let captureSource = record.captureSource else {
            return false
        }
        return targetForegroundCaptureSources.contains(captureSource)
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

    private static func isNormalClickEvent(_ record: TargetEventRecord) -> Bool {
        isNormalClickDownEvent(record) || isNormalClickUpEvent(record)
    }

    private static func isNormalClickDownEvent(_ record: TargetEventRecord) -> Bool {
        switch record.name {
        case "mouseDown",
             "rightMouseDown":
            return true
        default:
            return false
        }
    }

    private static func isNormalClickUpEvent(_ record: TargetEventRecord) -> Bool {
        switch record.name {
        case "mouseUp",
             "rightMouseUp":
            return true
        default:
            return false
        }
    }

    private static func isNormalDragEvent(_ record: TargetEventRecord) -> Bool {
        record.name == "mouseDragged" || record.name == "rightMouseDragged"
    }

    private static func isWheelEvent(_ record: TargetEventRecord) -> Bool {
        isScrollEvent(record)
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
