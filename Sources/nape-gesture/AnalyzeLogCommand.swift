import AppKit
import Carbon.HIToolbox
import CoreGraphics
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
        let assertHasUnmarkedPassthroughInput = options.contains("--assert-has-unmarked-passthrough-input")
        let assertHasUnmarkedClick = options.contains("--assert-has-unmarked-click")
        let assertHasUnmarkedDrag = options.contains("--assert-has-unmarked-drag")
        let assertHasUnmarkedWheel = options.contains("--assert-has-unmarked-wheel")
        let assertHasUnmarkedClickDragWheel = options.contains("--assert-has-unmarked-click-drag-wheel")
        let assertKillSwitchShortcut = options.contains("--assert-kill-switch-shortcut")
        let assertGestureBeforeKillSwitch = options.contains("--assert-gesture-before-kill-switch")
        let assertGeneratedScrollLog = options.contains("--assert-generated-scroll-log")
            || options.contains("--assert-generated-scroll")
        let systemScenario = try Self.systemScenarioAssertion(in: options)

        if options.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(analysis)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(InputLogAnalyzer.japaneseReport(for: analysis))
        }

        if assertHasUnmarkedPassthroughInput && analysis.unmarkedPassthroughInputEvents == 0 {
            fflush(stdout)
            throw InputLogMissingUnmarkedPassthroughInputAssertionError(path: path)
        }
        if assertHasUnmarkedClick && !analysis.hasUnmarkedClick {
            fflush(stdout)
            throw InputLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常クリック", analysis: analysis)
        }
        if assertHasUnmarkedDrag && analysis.unmarkedDragEvents == 0 {
            fflush(stdout)
            throw InputLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常ドラッグ", analysis: analysis)
        }
        if assertHasUnmarkedWheel && analysis.unmarkedWheelEvents == 0 {
            fflush(stdout)
            throw InputLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常ホイール", analysis: analysis)
        }
        if assertHasUnmarkedClickDragWheel && !analysis.hasUnmarkedClickDragWheel {
            fflush(stdout)
            throw InputLogMissingUnmarkedNormalInputKindAssertionError(path: path, kind: "通常クリック / 通常ドラッグ / 通常ホイール", analysis: analysis)
        }
        if assertKillSwitchShortcut && !Self.hasKillSwitchShortcut(records) {
            fflush(stdout)
            throw InputLogMissingKillSwitchShortcutAssertionError(path: path)
        }
        if assertGestureBeforeKillSwitch && !Self.hasGestureBeforeKillSwitch(records) {
            fflush(stdout)
            throw InputLogMissingGestureBeforeKillSwitchAssertionError(path: path)
        }
        if assertGeneratedScrollLog {
            let evaluation = GeneratedScrollLogAssertion.evaluate(records)
            if !evaluation.passed {
                fflush(stdout)
                throw InputLogGeneratedScrollAssertionError(path: path, failures: evaluation.failures)
            }
        }
        if let systemScenario {
            let failures = Self.systemScenarioFailures(for: systemScenario, records: records, analysis: analysis)
            if !failures.isEmpty {
                fflush(stdout)
                throw InputLogSystemScenarioAssertionError(
                    path: path,
                    scenario: systemScenario.rawValue,
                    failures: failures
                )
            }
        }
    }

    private static func systemScenarioAssertion(in options: [String]) throws -> SystemLogScenario? {
        guard options.contains("--assert-system-scenario") else {
            return nil
        }
        let rawValue = try SettingsStore.requiredValue(for: "--assert-system-scenario", in: options)
        guard let scenario = SystemLogScenario(rawValue: rawValue) else {
            throw ToolError.invalidValue("--assert-system-scenario", rawValue)
        }
        return scenario
    }

    private static func systemScenarioFailures(
        for scenario: SystemLogScenario,
        records: [InputLogRecord],
        analysis: LogAnalysis
    ) -> [String] {
        var failures = systemMetadataFailures(records: records, scenario: scenario)

        switch scenario {
        case .spaceLeft:
            failures.append(contentsOf: horizontalScrollFailures(records: records, expectedSign: -1, scenario: scenario))
        case .spaceRight, .horizontalScroll:
            failures.append(contentsOf: horizontalScrollFailures(records: records, expectedSign: 1, scenario: scenario))
        case .missionControl:
            failures.append(contentsOf: generatedShortcutFailures(records: records, keyCode: CGKeyCode(kVK_UpArrow), flags: .maskControl))
        case .pageBack:
            failures.append(contentsOf: generatedShortcutFailures(records: records, keyCode: CGKeyCode(kVK_LeftArrow), flags: .maskCommand))
        case .pageForward:
            failures.append(contentsOf: generatedShortcutFailures(records: records, keyCode: CGKeyCode(kVK_RightArrow), flags: .maskCommand))
        case .zoomIn:
            failures.append(contentsOf: generatedShortcutFailures(records: records, keyCode: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand))
        case .zoomOut:
            failures.append(contentsOf: generatedShortcutFailures(records: records, keyCode: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand))
        case .killSwitch:
            failures.append(contentsOf: shortcutFailures(
                records: records,
                keyCode: CGKeyCode(kVK_ANSI_G),
                flags: [.maskControl, .maskAlternate, .maskCommand],
                generatedByNapeGesture: false
            ))
        case .gestureDrag:
            failures.append(contentsOf: unmarkedGestureFailures(records: records, analysis: analysis, requiresDrag: true, requiresWheel: false))
        case .gestureWheel:
            failures.append(contentsOf: unmarkedGestureFailures(records: records, analysis: analysis, requiresDrag: false, requiresWheel: true))
        case .gestureWheelThenKillSwitch:
            failures.append(contentsOf: unmarkedGestureFailures(records: records, analysis: analysis, requiresDrag: false, requiresWheel: true))
            if !hasKillSwitchShortcut(records) {
                failures.append("未生成の Control + Option + Command + G keyDown / keyUp がありません。")
            }
            if !hasGestureBeforeKillSwitch(records) {
                failures.append("キルスイッチ前に未生成の activation button 押下とジェスチャー入力がありません。")
            }
        case .normalAfterRelease:
            failures.append(contentsOf: unmarkedActivationButtonFailures(records: records))
            if analysis.unmarkedMoveEvents == 0 {
                failures.append("activation button 解放後の未生成移動イベントがありません。")
            }
            if !analysis.hasUnmarkedClickDragWheel {
                failures.append("activation button 解放後の通常クリック / 通常ドラッグ / 通常ホイールが揃っていません。")
            }
            if analysis.generatedEvents > 0 {
                failures.append("通常入力通過シナリオに Nape Gesture 生成イベントが混在しています。")
            }
        }

        return failures
    }

    private static func systemMetadataFailures(
        records: [InputLogRecord],
        scenario: SystemLogScenario
    ) -> [String] {
        var failures: [String] = []
        if records.isEmpty {
            failures.append("system-test dry-run レコードがありません。")
            return failures
        }
        let scenarioMismatches = records.filter { $0.systemTestScenario != scenario.rawValue }
        if !scenarioMismatches.isEmpty {
            failures.append("systemTestScenario が \(scenario.rawValue) ではないレコードが \(scenarioMismatches.count) 件あります。")
        }
        let sequenceMismatches = records.enumerated().filter { index, record in
            record.sequenceIndex != index
        }
        if !sequenceMismatches.isEmpty {
            failures.append("sequenceIndex がログ順序と一致しないレコードが \(sequenceMismatches.count) 件あります。")
        }
        return failures
    }

    private static func horizontalScrollFailures(
        records: [InputLogRecord],
        expectedSign: Int,
        scenario: SystemLogScenario
    ) -> [String] {
        let scrollRecords = records.filter(\.isScrollEvent)
        var failures: [String] = []

        if scrollRecords.isEmpty {
            failures.append("scrollWheel イベントがありません。")
            return failures
        }
        if scrollRecords.count != records.count {
            failures.append("scrollWheel 以外のイベントが混在しています。")
        }
        if scrollRecords.contains(where: { !$0.generatedByNapeGesture }) {
            failures.append("Nape Gesture 生成マークのない scrollWheel が混在しています。")
        }
        if scrollRecords.contains(where: { $0.isContinuous == 0 }) {
            failures.append("continuous/precise ではない scrollWheel が混在しています。")
        }
        if scrollRecords.contains(where: { $0.pointDeltaY != 0 || $0.scrollDeltaY != 0 }) {
            failures.append("水平シナリオに垂直 delta が混在しています。")
        }
        if scrollRecords.contains(where: { $0.momentumPhase != 0 }) {
            failures.append("dry-run の水平シナリオに momentumPhase が混在しています。")
        }

        for record in scrollRecords {
            let horizontalDelta = record.pointDeltaX != 0 ? record.pointDeltaX : Double(record.scrollDeltaX)
            if expectedSign < 0, horizontalDelta >= 0 {
                failures.append("\(scenario.rawValue) の水平 delta に左方向ではない値が含まれています。")
                break
            }
            if expectedSign > 0, horizontalDelta <= 0 {
                failures.append("\(scenario.rawValue) の水平 delta に右方向ではない値が含まれています。")
                break
            }
        }

        let phases = Set(scrollRecords.map(\.scrollPhase))
        if !phases.contains(Int64(NSEvent.Phase.began.rawValue)) {
            failures.append("scrollPhase に began がありません。")
        }
        if !phases.contains(Int64(NSEvent.Phase.ended.rawValue)) {
            failures.append("scrollPhase に ended がありません。")
        }
        if scrollRecords.count > 2, !phases.contains(Int64(NSEvent.Phase.changed.rawValue)) {
            failures.append("複数 step の scrollPhase に changed がありません。")
        }
        if !timestampsAreMonotonic(scrollRecords) {
            failures.append("scrollWheel の timestamp が単調増加していません。")
        }

        return failures
    }

    private static func generatedShortcutFailures(
        records: [InputLogRecord],
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> [String] {
        shortcutFailures(records: records, keyCode: keyCode, flags: flags, generatedByNapeGesture: true)
    }

    private static func shortcutFailures(
        records: [InputLogRecord],
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        generatedByNapeGesture: Bool
    ) -> [String] {
        let matchingRecords = records.filter {
            $0.isKeyEvent
                && $0.keyCode == Int64(keyCode)
                && hasExactShortcutFlags($0.flags, flags)
                && $0.generatedByNapeGesture == generatedByNapeGesture
        }
        var failures: [String] = []

        if records.count != matchingRecords.count {
            failures.append("期待した keyCode / modifier / generated marker 以外のイベントが混在しています。")
        }
        if matchingRecords.count != 2 {
            failures.append("期待 shortcut は keyDown / keyUp の2イベントだけで構成される必要があります。")
        }
        if !matchingRecords.contains(where: { $0.typeName == "keyDown" }) {
            failures.append("期待 shortcut の keyDown がありません。")
        }
        if !matchingRecords.contains(where: { $0.typeName == "keyUp" }) {
            failures.append("期待 shortcut の keyUp がありません。")
        }
        if !timestampsAreMonotonic(matchingRecords) {
            failures.append("shortcut key event の timestamp が単調増加していません。")
        }

        return failures
    }

    private static func unmarkedGestureFailures(
        records: [InputLogRecord],
        analysis: LogAnalysis,
        requiresDrag: Bool,
        requiresWheel: Bool
    ) -> [String] {
        var failures = unmarkedActivationButtonFailures(records: records)
        if requiresDrag, !hasUnmarkedActivationButtonDrag(records: records) {
            failures.append("未生成の activation button 押下中ドラッグがありません。")
        }
        if requiresWheel, analysis.unmarkedWheelEvents == 0 {
            failures.append("未生成の activation button 押下中ホイールがありません。")
        }
        if analysis.generatedEvents > 0 {
            failures.append("未生成入力シナリオに Nape Gesture 生成イベントが混在しています。")
        }
        if !timestampsAreMonotonic(records) {
            failures.append("未生成入力イベントの timestamp が単調増加していません。")
        }
        return failures
    }

    private static func hasUnmarkedActivationButtonDrag(records: [InputLogRecord]) -> Bool {
        let activationButtonNumber = Int64(GestureConfiguration.default.activationButton.rawValue)
        return records.contains {
            !$0.generatedByNapeGesture
                && $0.typeName == "otherMouseDragged"
                && $0.buttonNumber == activationButtonNumber
        }
    }

    private static func unmarkedActivationButtonFailures(records: [InputLogRecord]) -> [String] {
        let activationButtonNumber = Int64(GestureConfiguration.default.activationButton.rawValue)
        var failures: [String] = []
        if !records.contains(where: {
            !$0.generatedByNapeGesture
                && $0.typeName == "otherMouseDown"
                && $0.buttonNumber == activationButtonNumber
        }) {
            failures.append("未生成の activation button down がありません。")
        }
        if !records.contains(where: {
            !$0.generatedByNapeGesture
                && $0.typeName == "otherMouseUp"
                && $0.buttonNumber == activationButtonNumber
        }) {
            failures.append("未生成の activation button up がありません。")
        }
        return failures
    }

    private static func timestampsAreMonotonic(_ records: [InputLogRecord]) -> Bool {
        zip(records, records.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp }
    }

    private static func hasExactShortcutFlags(_ rawFlags: UInt64, _ expected: CGEventFlags) -> Bool {
        let modifierMask = CGEventFlags.maskCommand.rawValue
            | CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskShift.rawValue
        return (rawFlags & modifierMask) == expected.rawValue
    }

    private static func hasKillSwitchShortcut(_ records: [InputLogRecord]) -> Bool {
        let matchingRecords = records.filter(isKillSwitchShortcutRecord)

        return matchingRecords.contains { $0.typeName == "keyDown" }
            && matchingRecords.contains { $0.typeName == "keyUp" }
    }

    private static func hasGestureBeforeKillSwitch(_ records: [InputLogRecord]) -> Bool {
        guard hasKillSwitchShortcut(records),
              let killSwitchTime = records
                .filter({ $0.typeName == "keyDown" && isKillSwitchShortcutRecord($0) })
                .map(\.timestamp)
                .min()
        else {
            return false
        }

        let recordsBeforeKillSwitch = records.filter {
            !$0.generatedByNapeGesture && $0.timestamp < killSwitchTime
        }
        let hasActivationButtonDown = recordsBeforeKillSwitch.contains {
            $0.typeName == "otherMouseDown"
        }
        let hasGestureInput = recordsBeforeKillSwitch.contains {
            $0.isMoveEvent || $0.isScrollEvent
        }

        return hasActivationButtonDown && hasGestureInput
    }

    private static func isKillSwitchShortcutRecord(_ record: InputLogRecord) -> Bool {
        guard !record.generatedByNapeGesture, record.keyCode == 5 else {
            return false
        }
        return hasExactShortcutFlags(record.flags, [.maskCommand, .maskControl, .maskAlternate])
    }

}

private enum SystemLogScenario: String {
    case spaceLeft = "space-left"
    case spaceRight = "space-right"
    case horizontalScroll = "horizontal-scroll"
    case missionControl = "mission-control"
    case pageBack = "page-back"
    case pageForward = "page-forward"
    case zoomIn = "zoom-in"
    case zoomOut = "zoom-out"
    case killSwitch = "kill-switch"
    case gestureDrag = "gesture-drag"
    case gestureWheel = "gesture-wheel"
    case gestureWheelThenKillSwitch = "gesture-wheel-then-kill-switch"
    case normalAfterRelease = "normal-after-release"
}

struct InputLogMissingUnmarkedPassthroughInputAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "input log に未生成の移動またはスクロールがありません。通常入力通過の前段確認には `analyze-log \(path) --json --assert-has-unmarked-passthrough-input` で unmarkedMoveEvents または unmarkedScrollEvents を確認してください。"
    }
}

struct InputLogMissingUnmarkedNormalInputKindAssertionError: LocalizedError {
    var path: String
    var kind: String
    var analysis: LogAnalysis

    var errorDescription: String? {
        "input log に未生成の\(kind)がありません。`analyze-log \(path) --json` で unmarkedClickDownEvents=\(analysis.unmarkedClickDownEvents)、unmarkedClickUpEvents=\(analysis.unmarkedClickUpEvents)、unmarkedDragEvents=\(analysis.unmarkedDragEvents)、unmarkedWheelEvents=\(analysis.unmarkedWheelEvents) を確認してください。"
    }
}

struct InputLogMissingKillSwitchShortcutAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "input log に未生成の Control + Option + Command + G keyDown / keyUp がありません。キルスイッチ dry-run の確認には `analyze-log \(path) --json --assert-kill-switch-shortcut` を使ってください。"
    }
}

struct InputLogMissingGestureBeforeKillSwitchAssertionError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "input log にキルスイッチ前の未生成ジェスチャー入力がありません。暴走中停止 dry-run の確認には `analyze-log \(path) --json --assert-kill-switch-shortcut --assert-gesture-before-kill-switch` を使ってください。"
    }
}

struct InputLogSystemScenarioAssertionError: LocalizedError {
    var path: String
    var scenario: String
    var failures: [String]

    var errorDescription: String? {
        let details = failures.map { "- \($0)" }.joined(separator: "\n")
        return """
        input log は system-test \(scenario) の期待イベント列を満たしていません。
        \(details)
        `nape-gesture system-test run --scenario \(scenario) --dry-run --log-json --out \(path)` の出力を確認してください。
        """
    }
}

struct InputLogGeneratedScrollAssertionError: LocalizedError {
    var path: String
    var failures: [String]

    var errorDescription: String? {
        let details = failures.map { "- \($0)" }.joined(separator: "\n")
        return """
        input log は generate-scroll の生成スクロールログ条件を満たしていません。
        \(details)
        `nape-gesture generate-scroll --dry-run --log-json` の出力を確認してください: \(path)
        """
    }
}
