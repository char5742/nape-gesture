import AppKit
import Foundation

private let bundleIdentifier = "com.openai.codex"

guard CommandLine.arguments.count == 2 else {
    fputs("使用方法: swift scripts/set-codex-host-visibility.swift <hide|activate|status>\n", stderr)
    exit(2)
}

guard let application = NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleIdentifier)
    .first
else {
    fputs("Codex applicationを取得できませんでした。\n", stderr)
    exit(1)
}

let operation = CommandLine.arguments[1]
switch operation {
case "hide":
    _ = application.hide()
case "activate":
    _ = application.activate(options: [.activateAllWindows])
case "status":
    break
default:
    fputs("未知の操作です: \(operation)\n", stderr)
    exit(2)
}

if operation != "status" {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}

let report: [String: Any] = [
    "schemaVersion": 1,
    "bundleIdentifier": bundleIdentifier,
    "processId": application.processIdentifier,
    "isHidden": application.isHidden,
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))

if operation == "hide", !application.isHidden {
    fputs("Codex applicationを非表示にできませんでした。\n", stderr)
    exit(1)
}
if operation == "activate", application.isHidden {
    fputs("Codex applicationを再表示できませんでした。\n", stderr)
    exit(1)
}
