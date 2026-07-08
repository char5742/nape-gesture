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
        let flags = CGEventFlags(rawValue: record.flags)
        return flags.contains(.maskCommand)
            && flags.contains(.maskControl)
            && flags.contains(.maskAlternate)
    }

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
