import Carbon.HIToolbox
import CoreGraphics

enum ShortcutEventSequence {
    static func keyEvents(keyCode: CGKeyCode, flags: CGEventFlags) -> [ShortcutKeyEvent] {
        let modifiers = shortcutModifiers(for: flags)
        var events: [ShortcutKeyEvent] = []
        var activeFlags = CGEventFlags()

        for modifier in modifiers {
            activeFlags.insert(modifier.flag)
            events.append(ShortcutKeyEvent(type: .keyDown, keyCode: modifier.keyCode, flags: activeFlags))
        }

        events.append(ShortcutKeyEvent(type: .keyDown, keyCode: keyCode, flags: flags))
        events.append(ShortcutKeyEvent(type: .keyUp, keyCode: keyCode, flags: flags))

        for modifier in modifiers.reversed() {
            activeFlags.remove(modifier.flag)
            events.append(ShortcutKeyEvent(type: .keyUp, keyCode: modifier.keyCode, flags: activeFlags))
        }

        return events
    }

    private static func shortcutModifiers(for flags: CGEventFlags) -> [ShortcutModifier] {
        let candidates = [
            ShortcutModifier(flag: .maskControl, keyCode: CGKeyCode(kVK_Control)),
            ShortcutModifier(flag: .maskAlternate, keyCode: CGKeyCode(kVK_Option)),
            ShortcutModifier(flag: .maskCommand, keyCode: CGKeyCode(kVK_Command)),
            ShortcutModifier(flag: .maskShift, keyCode: CGKeyCode(kVK_Shift))
        ]
        return candidates.filter { flags.contains($0.flag) }
    }
}

struct ShortcutKeyEvent: Equatable {
    var type: CGEventType
    var keyCode: CGKeyCode
    var flags: CGEventFlags

    var typeName: String {
        switch type {
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        default:
            return "unknown"
        }
    }

    var isKeyDown: Bool {
        type == .keyDown
    }
}

private struct ShortcutModifier {
    var flag: CGEventFlags
    var keyCode: CGKeyCode
}
