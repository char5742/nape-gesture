import Foundation

public struct InputLogRecord: Codable, Equatable, Sendable {
    public var timestamp: UInt64
    public var typeName: String
    public var typeRaw: Int
    public var generatedByNapeGesture: Bool
    public var buttonNumber: Int64
    public var deltaX: Int64
    public var deltaY: Int64
    public var scrollDeltaX: Int64
    public var scrollDeltaY: Int64
    public var pointDeltaX: Double
    public var pointDeltaY: Double
    public var scrollPhase: Int64
    public var momentumPhase: Int64
    public var isContinuous: Int64
    public var keyCode: Int64
    public var flags: UInt64
    public var systemTestScenario: String?
    public var sequenceIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case typeName
        case typeRaw
        case generatedByNapeGesture
        case legacyGeneratedByMacGesture = "generatedByMacGesture"
        case buttonNumber
        case deltaX
        case deltaY
        case scrollDeltaX
        case scrollDeltaY
        case pointDeltaX
        case pointDeltaY
        case scrollPhase
        case momentumPhase
        case isContinuous
        case keyCode
        case flags
        case systemTestScenario
        case sequenceIndex
    }

    public init(
        timestamp: UInt64,
        typeName: String,
        typeRaw: Int,
        generatedByNapeGesture: Bool,
        buttonNumber: Int64,
        deltaX: Int64,
        deltaY: Int64,
        scrollDeltaX: Int64,
        scrollDeltaY: Int64,
        pointDeltaX: Double,
        pointDeltaY: Double,
        scrollPhase: Int64,
        momentumPhase: Int64,
        isContinuous: Int64,
        keyCode: Int64,
        flags: UInt64,
        systemTestScenario: String? = nil,
        sequenceIndex: Int? = nil
    ) {
        self.timestamp = timestamp
        self.typeName = typeName
        self.typeRaw = typeRaw
        self.generatedByNapeGesture = generatedByNapeGesture
        self.buttonNumber = buttonNumber
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.pointDeltaX = pointDeltaX
        self.pointDeltaY = pointDeltaY
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.isContinuous = isContinuous
        self.keyCode = keyCode
        self.flags = flags
        self.systemTestScenario = systemTestScenario
        self.sequenceIndex = sequenceIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        typeName = try container.decode(String.self, forKey: .typeName)
        typeRaw = try container.decode(Int.self, forKey: .typeRaw)
        generatedByNapeGesture = try container.decodeIfPresent(Bool.self, forKey: .generatedByNapeGesture)
            ?? container.decodeIfPresent(Bool.self, forKey: .legacyGeneratedByMacGesture)
            ?? false
        buttonNumber = try container.decode(Int64.self, forKey: .buttonNumber)
        deltaX = try container.decode(Int64.self, forKey: .deltaX)
        deltaY = try container.decode(Int64.self, forKey: .deltaY)
        scrollDeltaX = try container.decode(Int64.self, forKey: .scrollDeltaX)
        scrollDeltaY = try container.decode(Int64.self, forKey: .scrollDeltaY)
        pointDeltaX = try container.decode(Double.self, forKey: .pointDeltaX)
        pointDeltaY = try container.decode(Double.self, forKey: .pointDeltaY)
        scrollPhase = try container.decode(Int64.self, forKey: .scrollPhase)
        momentumPhase = try container.decode(Int64.self, forKey: .momentumPhase)
        isContinuous = try container.decode(Int64.self, forKey: .isContinuous)
        keyCode = try container.decode(Int64.self, forKey: .keyCode)
        flags = try container.decode(UInt64.self, forKey: .flags)
        systemTestScenario = try container.decodeIfPresent(String.self, forKey: .systemTestScenario)
        sequenceIndex = try container.decodeIfPresent(Int.self, forKey: .sequenceIndex)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(typeName, forKey: .typeName)
        try container.encode(typeRaw, forKey: .typeRaw)
        try container.encode(generatedByNapeGesture, forKey: .generatedByNapeGesture)
        try container.encode(buttonNumber, forKey: .buttonNumber)
        try container.encode(deltaX, forKey: .deltaX)
        try container.encode(deltaY, forKey: .deltaY)
        try container.encode(scrollDeltaX, forKey: .scrollDeltaX)
        try container.encode(scrollDeltaY, forKey: .scrollDeltaY)
        try container.encode(pointDeltaX, forKey: .pointDeltaX)
        try container.encode(pointDeltaY, forKey: .pointDeltaY)
        try container.encode(scrollPhase, forKey: .scrollPhase)
        try container.encode(momentumPhase, forKey: .momentumPhase)
        try container.encode(isContinuous, forKey: .isContinuous)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(flags, forKey: .flags)
        try container.encodeIfPresent(systemTestScenario, forKey: .systemTestScenario)
        try container.encodeIfPresent(sequenceIndex, forKey: .sequenceIndex)
    }
}

public struct LogAnalysis: Codable, Equatable, Sendable {
    public var totalEvents: Int
    public var generatedEvents: Int
    public var unmarkedMoveEvents: Int
    public var unmarkedScrollEvents: Int
    public var unmarkedClickEvents: Int
    public var unmarkedClickDownEvents: Int
    public var unmarkedClickUpEvents: Int
    public var unmarkedDragEvents: Int
    public var unmarkedWheelEvents: Int
    public var moveEvents: Int
    public var scrollEvents: Int
    public var buttonEvents: Int
    public var keyEvents: Int
    public var generatedKeyEvents: Int
    public var unmarkedKeyEvents: Int
    public var generatedScrollEvents: Int
    public var preciseScrollEvents: Int
    public var preciseScrollRatio: Double
    public var momentumScrollEvents: Int
    public var positiveHorizontalScrollEvents: Int
    public var negativeHorizontalScrollEvents: Int
    public var zeroHorizontalScrollEvents: Int
    public var scrollDeltaXTotal: Int64
    public var scrollDeltaYTotal: Int64
    public var pointDeltaXTotal: Double
    public var pointDeltaYTotal: Double
    public var maximumMoveMagnitude: Double
    public var p95MoveMagnitude: Double
    public var p99MoveMagnitude: Double
    public var suggestedDeadZonePoints: Double
    public var buttonCounts: [String: Int]
    public var keyCounts: [String: Int]
    public var keySignatureCounts: [String: Int]
    public var scrollPhaseCounts: [String: Int]
    public var momentumPhaseCounts: [String: Int]

    public init(
        totalEvents: Int,
        generatedEvents: Int,
        unmarkedMoveEvents: Int,
        unmarkedScrollEvents: Int,
        unmarkedClickEvents: Int,
        unmarkedClickDownEvents: Int,
        unmarkedClickUpEvents: Int,
        unmarkedDragEvents: Int,
        unmarkedWheelEvents: Int,
        moveEvents: Int,
        scrollEvents: Int,
        buttonEvents: Int,
        keyEvents: Int,
        generatedKeyEvents: Int,
        unmarkedKeyEvents: Int,
        generatedScrollEvents: Int,
        preciseScrollEvents: Int,
        preciseScrollRatio: Double,
        momentumScrollEvents: Int,
        positiveHorizontalScrollEvents: Int,
        negativeHorizontalScrollEvents: Int,
        zeroHorizontalScrollEvents: Int,
        scrollDeltaXTotal: Int64,
        scrollDeltaYTotal: Int64,
        pointDeltaXTotal: Double,
        pointDeltaYTotal: Double,
        maximumMoveMagnitude: Double,
        p95MoveMagnitude: Double,
        p99MoveMagnitude: Double,
        suggestedDeadZonePoints: Double,
        buttonCounts: [String: Int],
        keyCounts: [String: Int],
        keySignatureCounts: [String: Int],
        scrollPhaseCounts: [String: Int],
        momentumPhaseCounts: [String: Int]
    ) {
        self.totalEvents = totalEvents
        self.generatedEvents = generatedEvents
        self.unmarkedMoveEvents = unmarkedMoveEvents
        self.unmarkedScrollEvents = unmarkedScrollEvents
        self.unmarkedClickEvents = unmarkedClickEvents
        self.unmarkedClickDownEvents = unmarkedClickDownEvents
        self.unmarkedClickUpEvents = unmarkedClickUpEvents
        self.unmarkedDragEvents = unmarkedDragEvents
        self.unmarkedWheelEvents = unmarkedWheelEvents
        self.moveEvents = moveEvents
        self.scrollEvents = scrollEvents
        self.buttonEvents = buttonEvents
        self.keyEvents = keyEvents
        self.generatedKeyEvents = generatedKeyEvents
        self.unmarkedKeyEvents = unmarkedKeyEvents
        self.generatedScrollEvents = generatedScrollEvents
        self.preciseScrollEvents = preciseScrollEvents
        self.preciseScrollRatio = preciseScrollRatio
        self.momentumScrollEvents = momentumScrollEvents
        self.positiveHorizontalScrollEvents = positiveHorizontalScrollEvents
        self.negativeHorizontalScrollEvents = negativeHorizontalScrollEvents
        self.zeroHorizontalScrollEvents = zeroHorizontalScrollEvents
        self.scrollDeltaXTotal = scrollDeltaXTotal
        self.scrollDeltaYTotal = scrollDeltaYTotal
        self.pointDeltaXTotal = pointDeltaXTotal
        self.pointDeltaYTotal = pointDeltaYTotal
        self.maximumMoveMagnitude = maximumMoveMagnitude
        self.p95MoveMagnitude = p95MoveMagnitude
        self.p99MoveMagnitude = p99MoveMagnitude
        self.suggestedDeadZonePoints = suggestedDeadZonePoints
        self.buttonCounts = buttonCounts
        self.keyCounts = keyCounts
        self.keySignatureCounts = keySignatureCounts
        self.scrollPhaseCounts = scrollPhaseCounts
        self.momentumPhaseCounts = momentumPhaseCounts
    }

    public var unmarkedPassthroughInputEvents: Int {
        unmarkedMoveEvents + unmarkedScrollEvents
    }

    public var hasUnmarkedClick: Bool {
        unmarkedClickDownEvents > 0 && unmarkedClickUpEvents > 0
    }

    public var hasUnmarkedClickDragWheel: Bool {
        hasUnmarkedClick && unmarkedDragEvents > 0 && unmarkedWheelEvents > 0
    }
}

public enum InputLogAnalyzer {
    public static func analyze(_ records: [InputLogRecord]) -> LogAnalysis {
        let moveRecords = records.filter(\.isMoveEvent)
        let scrollRecords = records.filter(\.isScrollEvent)
        let buttonRecords = records.filter(\.isButtonEvent)
        let keyRecords = records.filter(\.isKeyEvent)
        let unmarkedMoveRecords = moveRecords.filter { !$0.generatedByNapeGesture }
        let unmarkedScrollRecords = scrollRecords.filter { !$0.generatedByNapeGesture }
        let generatedScrollRecords = scrollRecords.filter(\.generatedByNapeGesture)
        let generatedKeyRecords = keyRecords.filter(\.generatedByNapeGesture)
        let unmarkedKeyRecords = keyRecords.filter { !$0.generatedByNapeGesture }
        let unmarkedClickRecords = records.filter { !$0.generatedByNapeGesture && $0.isNormalClickEvent }
        let unmarkedClickDownRecords = records.filter { !$0.generatedByNapeGesture && $0.isNormalClickDownEvent }
        let unmarkedClickUpRecords = records.filter { !$0.generatedByNapeGesture && $0.isNormalClickUpEvent }
        let unmarkedDragRecords = records.filter { !$0.generatedByNapeGesture && $0.isNormalDragEvent }
        let unmarkedWheelRecords = records.filter { !$0.generatedByNapeGesture && $0.isWheelEvent }
        let magnitudes = moveRecords
            .map { hypot(Double($0.deltaX), Double($0.deltaY)) }
            .sorted()

        let p95 = percentile(magnitudes, fraction: 0.95)
        let p99 = percentile(magnitudes, fraction: 0.99)
        let maxMagnitude = magnitudes.last ?? 0
        let suggestedDeadZone = max(4, ceil(p95 * 1.5))
        let preciseScrollEvents = scrollRecords.filter { $0.isContinuous != 0 || $0.pointDeltaX != 0 || $0.pointDeltaY != 0 }.count
        let horizontalScrollDeltas = scrollRecords.map(horizontalScrollDelta)

        return LogAnalysis(
            totalEvents: records.count,
            generatedEvents: records.filter(\.generatedByNapeGesture).count,
            unmarkedMoveEvents: unmarkedMoveRecords.count,
            unmarkedScrollEvents: unmarkedScrollRecords.count,
            unmarkedClickEvents: unmarkedClickRecords.count,
            unmarkedClickDownEvents: unmarkedClickDownRecords.count,
            unmarkedClickUpEvents: unmarkedClickUpRecords.count,
            unmarkedDragEvents: unmarkedDragRecords.count,
            unmarkedWheelEvents: unmarkedWheelRecords.count,
            moveEvents: moveRecords.count,
            scrollEvents: scrollRecords.count,
            buttonEvents: buttonRecords.count,
            keyEvents: keyRecords.count,
            generatedKeyEvents: generatedKeyRecords.count,
            unmarkedKeyEvents: unmarkedKeyRecords.count,
            generatedScrollEvents: generatedScrollRecords.count,
            preciseScrollEvents: preciseScrollEvents,
            preciseScrollRatio: ratio(numerator: preciseScrollEvents, denominator: scrollRecords.count),
            momentumScrollEvents: scrollRecords.filter { $0.momentumPhase != 0 }.count,
            positiveHorizontalScrollEvents: horizontalScrollDeltas.filter { $0 > 0 }.count,
            negativeHorizontalScrollEvents: horizontalScrollDeltas.filter { $0 < 0 }.count,
            zeroHorizontalScrollEvents: horizontalScrollDeltas.filter { $0 == 0 }.count,
            scrollDeltaXTotal: saturatingSum(scrollRecords.map(\.scrollDeltaX)),
            scrollDeltaYTotal: saturatingSum(scrollRecords.map(\.scrollDeltaY)),
            pointDeltaXTotal: scrollRecords.reduce(0) { $0 + $1.pointDeltaX },
            pointDeltaYTotal: scrollRecords.reduce(0) { $0 + $1.pointDeltaY },
            maximumMoveMagnitude: maxMagnitude,
            p95MoveMagnitude: p95,
            p99MoveMagnitude: p99,
            suggestedDeadZonePoints: suggestedDeadZone,
            buttonCounts: counts(buttonRecords.map { String($0.buttonNumber) }),
            keyCounts: counts(keyRecords.map { "\($0.typeName):\($0.keyCode)" }),
            keySignatureCounts: counts(keyRecords.map(keySignature)),
            scrollPhaseCounts: counts(scrollRecords.map { String($0.scrollPhase) }),
            momentumPhaseCounts: counts(scrollRecords.map { String($0.momentumPhase) })
        )
    }

    public static func japaneseReport(for analysis: LogAnalysis) -> String {
        """
        ログ解析結果
        総イベント数: \(analysis.totalEvents)
        生成イベント数: \(analysis.generatedEvents)
        未生成の移動イベント数: \(analysis.unmarkedMoveEvents)
        未生成のスクロールイベント数: \(analysis.unmarkedScrollEvents)
        未生成の通常クリック数: \(analysis.unmarkedClickEvents)
        未生成の通常クリックdown数: \(analysis.unmarkedClickDownEvents)
        未生成の通常クリックup数: \(analysis.unmarkedClickUpEvents)
        未生成の通常ドラッグ数: \(analysis.unmarkedDragEvents)
        未生成の通常ホイール数: \(analysis.unmarkedWheelEvents)
        移動イベント数: \(analysis.moveEvents)
        スクロールイベント数: \(analysis.scrollEvents)
        ボタンイベント数: \(analysis.buttonEvents)
        キーイベント数: \(analysis.keyEvents)
        生成キーイベント数: \(analysis.generatedKeyEvents)
        未生成キーイベント数: \(analysis.unmarkedKeyEvents)
        生成スクロールイベント数: \(analysis.generatedScrollEvents)
        precise/continuous スクロール数: \(analysis.preciseScrollEvents)
        precise/continuous 率: \(format(analysis.preciseScrollRatio * 100))%
        momentum スクロール数: \(analysis.momentumScrollEvents)
        水平スクロール方向数: positive=\(analysis.positiveHorizontalScrollEvents), negative=\(analysis.negativeHorizontalScrollEvents), zero=\(analysis.zeroHorizontalScrollEvents)
        scrollDelta 合計: x=\(analysis.scrollDeltaXTotal), y=\(analysis.scrollDeltaYTotal)
        pointDelta 合計: x=\(format(analysis.pointDeltaXTotal)), y=\(format(analysis.pointDeltaYTotal))
        最大移動量: \(format(analysis.maximumMoveMagnitude)) pt
        移動量 p95: \(format(analysis.p95MoveMagnitude)) pt
        移動量 p99: \(format(analysis.p99MoveMagnitude)) pt
        推奨 deadZonePoints: \(format(analysis.suggestedDeadZonePoints)) pt
        ボタン出現数: \(formatCounts(analysis.buttonCounts))
        キー出現数: \(formatCounts(analysis.keyCounts))
        キー署名出現数: \(formatCounts(analysis.keySignatureCounts))
        scrollPhase 出現数: \(formatCounts(analysis.scrollPhaseCounts))
        momentumPhase 出現数: \(formatCounts(analysis.momentumPhaseCounts))
        """
    }

    private static func saturatingSum(_ values: [Int64]) -> Int64 {
        var total: Int64 = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            if overflow {
                return value >= 0 ? Int64.max : Int64.min
            }
            total = next
        }
        return total
    }

    private static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard !sortedValues.isEmpty else {
            return 0
        }
        let clamped = min(max(fraction, 0), 1)
        let index = Int((Double(sortedValues.count - 1) * clamped).rounded())
        return sortedValues[index]
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for value in values {
            result[value, default: 0] += 1
        }
        return result
    }

    private static func horizontalScrollDelta(_ record: InputLogRecord) -> Double {
        if record.pointDeltaX != 0 {
            return record.pointDeltaX
        }
        return Double(record.scrollDeltaX)
    }

    private static func keySignature(_ record: InputLogRecord) -> String {
        let marker = record.generatedByNapeGesture ? "generated" : "unmarked"
        return "\(marker):\(record.typeName):\(record.keyCode):\(record.flags)"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
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

    private static func ratio(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else {
            return 0
        }
        return Double(numerator) / Double(denominator)
    }
}

public struct GeneratedScrollLogEvaluation: Codable, Equatable, Sendable {
    public var passed: Bool
    public var failures: [String]

    public init(passed: Bool, failures: [String]) {
        self.passed = passed
        self.failures = failures
    }
}

public enum GeneratedScrollExpectedDirection: String, Codable, Equatable, Sendable {
    case positiveX = "positive-x"
    case negativeX = "negative-x"

    fileprivate var sign: Int {
        switch self {
        case .positiveX:
            return 1
        case .negativeX:
            return -1
        }
    }
}

public enum GeneratedScrollExpectedPhaseMode: String, Codable, Equatable, Sendable {
    case auto
}

public struct GeneratedScrollLogExpectation: Codable, Equatable, Sendable {
    public var direction: GeneratedScrollExpectedDirection
    public var normalEventCount: Int
    public var momentumEventCount: Int
    public var normalXTotal: Double
    public var phaseMode: GeneratedScrollExpectedPhaseMode

    public init(
        direction: GeneratedScrollExpectedDirection,
        normalEventCount: Int,
        momentumEventCount: Int,
        normalXTotal: Double,
        phaseMode: GeneratedScrollExpectedPhaseMode
    ) {
        self.direction = direction
        self.normalEventCount = normalEventCount
        self.momentumEventCount = momentumEventCount
        self.normalXTotal = normalXTotal
        self.phaseMode = phaseMode
    }
}

public enum GeneratedScrollLogAssertion {
    private static let phaseBegan: Int64 = 1
    private static let phaseChanged: Int64 = 4
    private static let phaseEnded: Int64 = 8

    public static func evaluate(
        _ records: [InputLogRecord],
        expectation: GeneratedScrollLogExpectation
    ) -> GeneratedScrollLogEvaluation {
        var failures = expectationFailures(expectation)
        guard failures.isEmpty, let expectedRecordCount = expectedRecordCount(expectation) else {
            return GeneratedScrollLogEvaluation(passed: false, failures: failures)
        }

        if records.isEmpty {
            failures.append("生成スクロールログが空です。")
            return GeneratedScrollLogEvaluation(passed: false, failures: failures)
        }

        if records.contains(where: { !$0.isScrollEvent }) {
            failures.append("scrollWheel 以外のイベントが混在しています。")
        }
        if records.contains(where: { !$0.generatedByNapeGesture }) {
            failures.append("Nape Gesture 生成マークのないイベントが混在しています。")
        }
        if let invalidContinuous = records.firstIndex(where: { $0.isContinuous != 1 }) {
            failures.append("isContinuous が 1 ではない record があります。index=\(invalidContinuous)、実際=\(records[invalidContinuous].isContinuous)。")
        }
        if !timestampsAreStrictlyIncreasing(records) {
            failures.append("timestamp が厳密増加していません。同一 timestamp と順序逆転は許可しません。")
        }
        if containsDuplicateRecord(records) {
            failures.append("同一 record がイベント sequence に重複しています。")
        }
        if records.contains(where: { $0.systemTestScenario != nil }) {
            failures.append("generate-scroll ログに systemTestScenario が混在しています。")
        }
        if records.contains(where: { $0.sequenceIndex != nil }) {
            failures.append("generate-scroll ログに system-test 用の sequenceIndex が混在しています。")
        }
        if let mixedPhase = records.firstIndex(where: { $0.scrollPhase != 0 && $0.momentumPhase != 0 }) {
            failures.append("scrollPhase と momentumPhase が同じ record に混在しています。index=\(mixedPhase)。")
        }
        if let missingPhase = records.firstIndex(where: { $0.scrollPhase == 0 && $0.momentumPhase == 0 }) {
            failures.append("scrollPhase と momentumPhase の両方がない record があります。index=\(missingPhase)。")
        }
        if let unknownPhase = records.firstIndex(where: { !hasSupportedAutoPhase($0) }) {
            let record = records[unknownPhase]
            failures.append(
                "phase mode auto で未対応または未知の phase があります。index=\(unknownPhase)、scrollPhase=\(record.scrollPhase)、momentumPhase=\(record.momentumPhase)。"
            )
        }

        let normalEventCount = records.filter { $0.scrollPhase != 0 && $0.momentumPhase == 0 }.count
        if normalEventCount != expectation.normalEventCount {
            failures.append("通常イベント件数が期待値と一致しません。期待=\(expectation.normalEventCount)、実際=\(normalEventCount)。")
        }
        let momentumEventCount = records.filter { $0.scrollPhase == 0 && $0.momentumPhase == phaseChanged }.count
        if momentumEventCount != expectation.momentumEventCount {
            failures.append("momentum changed イベント件数が期待値と一致しません。期待=\(expectation.momentumEventCount)、実際=\(momentumEventCount)。")
        }
        if records.count != expectedRecordCount {
            failures.append("全イベント件数が期待値と一致しません。期待=\(expectedRecordCount)、実際=\(records.count)。")
        }

        failures.append(contentsOf: autoPhaseFailures(records, expectation: expectation))
        failures.append(contentsOf: directionAndAmountFailures(records, expectation: expectation))

        let momentumEndIndices = records.indices.filter {
            records[$0].scrollPhase == 0 && records[$0].momentumPhase == phaseEnded
        }
        let expectedMomentumEndCount = expectation.momentumEventCount > 0 ? 1 : 0
        if momentumEndIndices.count != expectedMomentumEndCount {
            failures.append(
                "momentum ended-zero record 件数が期待値と一致しません。期待=\(expectedMomentumEndCount)、実際=\(momentumEndIndices.count)。"
            )
        }
        if expectedMomentumEndCount == 1, let momentumEndIndex = momentumEndIndices.first {
            if momentumEndIndex != records.index(before: records.endIndex) {
                failures.append("momentum ended-zero record は最終 record でなければなりません。終了後 tail は許可しません。")
            }
            if !hasZeroDelta(records[momentumEndIndex]) {
                failures.append("momentum ended record がゼロ delta ではありません。index=\(momentumEndIndex)。")
            }
        }

        return GeneratedScrollLogEvaluation(passed: failures.isEmpty, failures: failures)
    }

    private static func expectationFailures(_ expectation: GeneratedScrollLogExpectation) -> [String] {
        var failures: [String] = []
        if expectation.normalEventCount < 1 {
            failures.append("phase mode auto の通常イベント件数は 1 以上でなければなりません。")
        }
        if expectation.momentumEventCount < 0 {
            failures.append("phase mode auto の momentum イベント件数は 0 以上でなければなりません。")
        }
        if !expectation.normalXTotal.isFinite || expectation.normalXTotal == 0 {
            failures.append("期待する通常 X 合計量は有限の非ゼロ値でなければなりません。")
        } else if sign(expectation.normalXTotal) != expectation.direction.sign {
            failures.append("期待方向と通常 X 合計量の符号が一致していません。")
        }
        if expectedNormalScrollTotal(expectation) == nil {
            failures.append("通常区間の量子化済み scrollDeltaX 合計を Int64 の範囲で表現できません。")
        }
        if expectedRecordCount(expectation) == nil {
            failures.append("期待イベント件数の合計が Int の範囲を超えています。")
        }
        return failures
    }

    private static func expectedRecordCount(_ expectation: GeneratedScrollLogExpectation) -> Int? {
        let (movementCount, movementOverflow) = expectation.normalEventCount.addingReportingOverflow(expectation.momentumEventCount)
        guard !movementOverflow else {
            return nil
        }
        guard expectation.momentumEventCount > 0 else {
            return movementCount
        }
        let (recordCount, terminalOverflow) = movementCount.addingReportingOverflow(1)
        return terminalOverflow ? nil : recordCount
    }

    private static func autoPhaseFailures(
        _ records: [InputLogRecord],
        expectation: GeneratedScrollLogExpectation
    ) -> [String] {
        guard expectation.phaseMode == .auto,
              let expectedCount = expectedRecordCount(expectation) else {
            return []
        }

        let comparableCount = min(records.count, expectedCount)
        for index in 0..<comparableCount {
            let expectedPhases = expectedAutoPhases(index: index, expectation: expectation)
            let record = records[index]
            if record.scrollPhase != expectedPhases.scroll || record.momentumPhase != expectedPhases.momentum {
                return [
                    "phase mode auto の状態列が一致しません。index=\(index)、期待=(scroll:\(expectedPhases.scroll), momentum:\(expectedPhases.momentum))、実際=(scroll:\(record.scrollPhase), momentum:\(record.momentumPhase))。"
                ]
            }
        }
        return []
    }

    private static func expectedAutoPhases(
        index: Int,
        expectation: GeneratedScrollLogExpectation
    ) -> (scroll: Int64, momentum: Int64) {
        if index < expectation.normalEventCount {
            if expectation.normalEventCount == 1 {
                return (phaseChanged, 0)
            }
            if index == 0 {
                return (phaseBegan, 0)
            }
            if index == expectation.normalEventCount - 1 {
                return (phaseEnded, 0)
            }
            return (phaseChanged, 0)
        }
        if index < expectation.normalEventCount + expectation.momentumEventCount {
            return (0, phaseChanged)
        }
        return (0, phaseEnded)
    }

    private static func directionAndAmountFailures(
        _ records: [InputLogRecord],
        expectation: GeneratedScrollLogExpectation
    ) -> [String] {
        var failures: [String] = []
        var reportedVerticalDelta = false
        var reportedSignMismatch = false
        var reportedDirectionMismatch = false
        var reportedAmountMismatch = false

        for (index, record) in records.enumerated() {
            if !reportedVerticalDelta && (record.pointDeltaY != 0 || record.scrollDeltaY != 0) {
                failures.append("期待方向は X 軸ですが Y delta が非ゼロです。index=\(index)。")
                reportedVerticalDelta = true
            }
            if !reportedAmountMismatch && quantizedPointDelta(record.pointDeltaX) != record.scrollDeltaX {
                failures.append("pointDeltaX と scrollDeltaX の量子化量が一致しません。index=\(index)、point=\(record.pointDeltaX)、scroll=\(record.scrollDeltaX)。")
                reportedAmountMismatch = true
            }
            if record.pointDeltaX != 0 {
                if !reportedSignMismatch,
                   record.scrollDeltaX != 0,
                   sign(record.pointDeltaX) != sign(record.scrollDeltaX) {
                    failures.append("pointDeltaX と scrollDeltaX の符号が一致しません。index=\(index)。")
                    reportedSignMismatch = true
                }
                if !reportedDirectionMismatch && sign(record.pointDeltaX) != expectation.direction.sign {
                    failures.append("非ゼロイベントの X 方向が期待方向 \(expectation.direction.rawValue) と一致しません。index=\(index)。")
                    reportedDirectionMismatch = true
                }
                if !reportedDirectionMismatch,
                   record.scrollDeltaX != 0,
                   sign(record.scrollDeltaX) != expectation.direction.sign {
                    failures.append("非ゼロイベントの X 方向が期待方向 \(expectation.direction.rawValue) と一致しません。index=\(index)。")
                    reportedDirectionMismatch = true
                }
            }
        }

        let normalRecords = records.prefix(min(records.count, expectation.normalEventCount))
        let expectedNormalPointDelta = expectation.normalXTotal / Double(expectation.normalEventCount)
        if let invalidNormalIndex = normalRecords.firstIndex(where: {
            !approximatelyEqual($0.pointDeltaX, expectedNormalPointDelta)
        }) {
            failures.append(
                "通常区間の pointDeltaX が per-step 期待量と一致しません。index=\(invalidNormalIndex)、期待=\(expectedNormalPointDelta)、実際=\(records[invalidNormalIndex].pointDeltaX)。"
            )
        }
        let pointTotal = normalRecords.reduce(0.0) { $0 + $1.pointDeltaX }
        if !approximatelyEqual(pointTotal, expectation.normalXTotal) {
            failures.append("通常区間の pointDeltaX 合計が期待量と一致しません。期待=\(expectation.normalXTotal)、実際=\(pointTotal)。")
        }
        if let expectedScrollTotal = expectedNormalScrollTotal(expectation) {
            let scrollTotal = scrollDeltaXTotal(normalRecords)
            if let scrollTotal, scrollTotal != expectedScrollTotal {
                failures.append("通常区間の scrollDeltaX 合計が期待量と一致しません。期待=\(expectedScrollTotal)、実際=\(scrollTotal)。")
            } else if scrollTotal == nil {
                failures.append("通常区間の scrollDeltaX 合計が Int64 の範囲を超えています。")
            }
        }

        return failures
    }

    private static func hasSupportedAutoPhase(_ record: InputLogRecord) -> Bool {
        let supportedScrollPhases: Set<Int64> = [0, phaseBegan, phaseChanged, phaseEnded]
        let supportedMomentumPhases: Set<Int64> = [0, phaseChanged, phaseEnded]
        return supportedScrollPhases.contains(record.scrollPhase)
            && supportedMomentumPhases.contains(record.momentumPhase)
    }

    private static func timestampsAreStrictlyIncreasing(_ records: [InputLogRecord]) -> Bool {
        zip(records, records.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp }
    }

    private static func containsDuplicateRecord(_ records: [InputLogRecord]) -> Bool {
        guard records.count > 1 else {
            return false
        }
        for index in 0..<(records.count - 1) where records[(index + 1)...].contains(records[index]) {
            return true
        }
        return false
    }

    private static func hasZeroDelta(_ record: InputLogRecord) -> Bool {
        record.scrollDeltaX == 0
            && record.scrollDeltaY == 0
            && record.pointDeltaX == 0
            && record.pointDeltaY == 0
    }

    private static func sign(_ value: Double) -> Int {
        value > 0 ? 1 : -1
    }

    private static func sign(_ value: Int64) -> Int {
        value > 0 ? 1 : -1
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(1e-9, abs(rhs) * 1e-9)
    }

    private static func expectedNormalScrollTotal(_ expectation: GeneratedScrollLogExpectation) -> Int64? {
        guard expectation.normalEventCount > 0,
              let perStep = quantizedPointDelta(expectation.normalXTotal / Double(expectation.normalEventCount)),
              let count = Int64(exactly: expectation.normalEventCount) else {
            return nil
        }
        let (total, overflow) = perStep.multipliedReportingOverflow(by: count)
        return overflow ? nil : total
    }

    private static func scrollDeltaXTotal(_ records: ArraySlice<InputLogRecord>) -> Int64? {
        var total: Int64 = 0
        for record in records {
            let (next, overflow) = total.addingReportingOverflow(record.scrollDeltaX)
            guard !overflow else {
                return nil
            }
            total = next
        }
        return total
    }

    private static func quantizedPointDelta(_ value: Double) -> Int64? {
        guard value.isFinite else {
            return nil
        }
        let rounded = value.rounded()
        if rounded > Double(Int32.max) {
            return Int64(Int32.max)
        }
        if rounded < Double(Int32.min) {
            return Int64(Int32.min)
        }
        return Int64(rounded)
    }
}

public struct LogComparison: Codable, Equatable, Sendable {
    public var baseline: LogAnalysis
    public var candidate: LogAnalysis
    public var totalEventDelta: Int
    public var generatedEventDelta: Int
    public var scrollEventDelta: Int
    public var keyEventDelta: Int
    public var preciseScrollRatioDelta: Double
    public var p95MoveMagnitudeDelta: Double
    public var p99MoveMagnitudeDelta: Double
    public var scrollDeltaXTotalDelta: Int64
    public var scrollDeltaYTotalDelta: Int64
    public var pointDeltaXTotalDelta: Double
    public var pointDeltaYTotalDelta: Double
    public var scrollPhaseDelta: [String: Int]
    public var momentumPhaseDelta: [String: Int]
    public var keyDelta: [String: Int]
    public var findings: [String]

    public init(
        baseline: LogAnalysis,
        candidate: LogAnalysis,
        totalEventDelta: Int,
        generatedEventDelta: Int,
        scrollEventDelta: Int,
        keyEventDelta: Int,
        preciseScrollRatioDelta: Double,
        p95MoveMagnitudeDelta: Double,
        p99MoveMagnitudeDelta: Double,
        scrollDeltaXTotalDelta: Int64,
        scrollDeltaYTotalDelta: Int64,
        pointDeltaXTotalDelta: Double,
        pointDeltaYTotalDelta: Double,
        scrollPhaseDelta: [String: Int],
        momentumPhaseDelta: [String: Int],
        keyDelta: [String: Int],
        findings: [String]
    ) {
        self.baseline = baseline
        self.candidate = candidate
        self.totalEventDelta = totalEventDelta
        self.generatedEventDelta = generatedEventDelta
        self.scrollEventDelta = scrollEventDelta
        self.keyEventDelta = keyEventDelta
        self.preciseScrollRatioDelta = preciseScrollRatioDelta
        self.p95MoveMagnitudeDelta = p95MoveMagnitudeDelta
        self.p99MoveMagnitudeDelta = p99MoveMagnitudeDelta
        self.scrollDeltaXTotalDelta = scrollDeltaXTotalDelta
        self.scrollDeltaYTotalDelta = scrollDeltaYTotalDelta
        self.pointDeltaXTotalDelta = pointDeltaXTotalDelta
        self.pointDeltaYTotalDelta = pointDeltaYTotalDelta
        self.scrollPhaseDelta = scrollPhaseDelta
        self.momentumPhaseDelta = momentumPhaseDelta
        self.keyDelta = keyDelta
        self.findings = findings
    }
}

public extension InputLogAnalyzer {
    static func compare(baseline baselineRecords: [InputLogRecord], candidate candidateRecords: [InputLogRecord]) -> LogComparison {
        let baseline = analyze(baselineRecords)
        let candidate = analyze(candidateRecords)
        let scrollPhaseDelta = deltaCounts(baseline.scrollPhaseCounts, candidate.scrollPhaseCounts)
        let momentumPhaseDelta = deltaCounts(baseline.momentumPhaseCounts, candidate.momentumPhaseCounts)
        let keyDelta = deltaCounts(baseline.keyCounts, candidate.keyCounts)

        return LogComparison(
            baseline: baseline,
            candidate: candidate,
            totalEventDelta: candidate.totalEvents - baseline.totalEvents,
            generatedEventDelta: candidate.generatedEvents - baseline.generatedEvents,
            scrollEventDelta: candidate.scrollEvents - baseline.scrollEvents,
            keyEventDelta: candidate.keyEvents - baseline.keyEvents,
            preciseScrollRatioDelta: candidate.preciseScrollRatio - baseline.preciseScrollRatio,
            p95MoveMagnitudeDelta: candidate.p95MoveMagnitude - baseline.p95MoveMagnitude,
            p99MoveMagnitudeDelta: candidate.p99MoveMagnitude - baseline.p99MoveMagnitude,
            scrollDeltaXTotalDelta: candidate.scrollDeltaXTotal - baseline.scrollDeltaXTotal,
            scrollDeltaYTotalDelta: candidate.scrollDeltaYTotal - baseline.scrollDeltaYTotal,
            pointDeltaXTotalDelta: candidate.pointDeltaXTotal - baseline.pointDeltaXTotal,
            pointDeltaYTotalDelta: candidate.pointDeltaYTotal - baseline.pointDeltaYTotal,
            scrollPhaseDelta: scrollPhaseDelta,
            momentumPhaseDelta: momentumPhaseDelta,
            keyDelta: keyDelta,
            findings: findings(
                baseline: baseline,
                candidate: candidate,
                scrollPhaseDelta: scrollPhaseDelta,
                momentumPhaseDelta: momentumPhaseDelta,
                keyDelta: keyDelta
            )
        )
    }

    static func japaneseReport(for comparison: LogComparison) -> String {
        """
        ログ比較結果
        baseline: events=\(comparison.baseline.totalEvents), scroll=\(comparison.baseline.scrollEvents), precise率=\(formatPercent(comparison.baseline.preciseScrollRatio))
        candidate: events=\(comparison.candidate.totalEvents), scroll=\(comparison.candidate.scrollEvents), precise率=\(formatPercent(comparison.candidate.preciseScrollRatio))
        総イベント数差: \(formatSigned(comparison.totalEventDelta))
        生成イベント数差: \(formatSigned(comparison.generatedEventDelta))
        スクロールイベント数差: \(formatSigned(comparison.scrollEventDelta))
        キーイベント数差: \(formatSigned(comparison.keyEventDelta))
        precise/continuous 率差: \(formatSignedPercent(comparison.preciseScrollRatioDelta))
        移動量 p95 差: \(formatSigned(comparison.p95MoveMagnitudeDelta)) pt
        移動量 p99 差: \(formatSigned(comparison.p99MoveMagnitudeDelta)) pt
        scrollDelta 合計差: x=\(formatSigned(comparison.scrollDeltaXTotalDelta)), y=\(formatSigned(comparison.scrollDeltaYTotalDelta))
        pointDelta 合計差: x=\(formatSigned(comparison.pointDeltaXTotalDelta)), y=\(formatSigned(comparison.pointDeltaYTotalDelta))
        scrollPhase 差: \(formatCounts(comparison.scrollPhaseDelta))
        momentumPhase 差: \(formatCounts(comparison.momentumPhaseDelta))
        キー差: \(formatCounts(comparison.keyDelta))
        所見: \(comparison.findings.isEmpty ? "大きな差分は検出されませんでした。" : comparison.findings.joined(separator: " / "))
        """
    }

    private static func deltaCounts(_ baseline: [String: Int], _ candidate: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for key in Set(baseline.keys).union(candidate.keys) {
            let delta = (candidate[key] ?? 0) - (baseline[key] ?? 0)
            if delta != 0 {
                result[key] = delta
            }
        }
        return result
    }

    private static func findings(
        baseline: LogAnalysis,
        candidate: LogAnalysis,
        scrollPhaseDelta: [String: Int],
        momentumPhaseDelta: [String: Int],
        keyDelta: [String: Int]
    ) -> [String] {
        var result: [String] = []
        if baseline.generatedEvents == 0, candidate.generatedEvents > 0 {
            result.append("candidate には NapeGesture 生成イベントが含まれています。")
        }
        if candidate.scrollEvents != baseline.scrollEvents {
            result.append("スクロールイベント数が baseline と異なります。")
        }
        if candidate.preciseScrollRatio + 0.1 < baseline.preciseScrollRatio {
            result.append("precise/continuous スクロール率が 10ポイント以上低下しています。")
        }
        if !scrollPhaseDelta.isEmpty {
            result.append("scrollPhase 分布が異なります。")
        }
        if !momentumPhaseDelta.isEmpty {
            result.append("momentumPhase 分布が異なります。")
        }
        if !keyDelta.isEmpty {
            result.append("キーイベント分布が異なります。")
        }
        return result
    }

    private static func formatSigned(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    private static func formatSigned(_ value: Int64) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    private static func formatSigned(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return value >= 0 ? "+\(formatted)" : formatted
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }

    private static func formatSignedPercent(_ value: Double) -> String {
        let formatted = String(format: "%.2f%%", value * 100)
        return value >= 0 ? "+\(formatted)" : formatted
    }
}

public extension InputLogRecord {
    var isMoveEvent: Bool {
        typeName == "mouseMoved"
            || typeName == "leftMouseDragged"
            || typeName == "rightMouseDragged"
            || typeName == "otherMouseDragged"
    }

    var isScrollEvent: Bool {
        typeName == "scrollWheel"
    }

    var isButtonEvent: Bool {
        typeName == "leftMouseDown"
            || typeName == "leftMouseUp"
            || typeName == "rightMouseDown"
            || typeName == "rightMouseUp"
            || typeName == "otherMouseDown"
            || typeName == "otherMouseUp"
    }

    var isNormalClickEvent: Bool {
        isNormalClickDownEvent || isNormalClickUpEvent
    }

    var isNormalClickDownEvent: Bool {
        typeName == "leftMouseDown" || typeName == "rightMouseDown"
    }

    var isNormalClickUpEvent: Bool {
        typeName == "leftMouseUp" || typeName == "rightMouseUp"
    }

    var isNormalDragEvent: Bool {
        typeName == "leftMouseDragged" || typeName == "rightMouseDragged"
    }

    var isWheelEvent: Bool {
        isScrollEvent
    }

    var isKeyEvent: Bool {
        typeName == "keyDown" || typeName == "keyUp"
    }
}
