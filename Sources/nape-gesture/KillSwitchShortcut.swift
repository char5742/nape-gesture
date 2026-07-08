import CoreGraphics
import Foundation

enum KillSwitchShortcut {
    static let displayName = "Control + Option + Command + G"
    static let remediation = "誤爆や暴走を感じたら Control + Option + Command + G を押してください。ジェスチャー生成と慣性を即座に停止し、再開は常駐UIの停止/開始またはプロセス再起動で行います。"

    static func matches(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else {
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        return keyCode == 5
            && flags.contains(.maskCommand)
            && flags.contains(.maskControl)
            && flags.contains(.maskAlternate)
    }
}
