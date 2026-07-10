import AppKit
import CoreGraphics
import Foundation

struct PointerWindowStackReport: Encodable {
    var schemaVersion: Int
    var wallClockUnixSeconds: Double
    var systemUptimeSeconds: Double
    var pointer: PointRecord
    var frontmostApplication: ApplicationRecord?
    var windows: [WindowRecord]
}

struct PointRecord: Encodable {
    var x: Double
    var y: Double
}

struct ApplicationRecord: Encodable {
    var processID: Int32
    var bundleIdentifier: String?
    var localizedName: String?
}

struct WindowRecord: Encodable {
    var stackIndex: Int
    var ownerName: String?
    var ownerProcessID: Int32
    var windowNumber: UInt32
    var bounds: BoundsRecord
    var alpha: Double?
}

struct BoundsRecord: Encodable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

func integerValue<T: FixedWidthInteger>(_ value: Any?, as type: T.Type) -> T? {
    if let number = value as? NSNumber {
        return T(exactly: number.int64Value)
    }
    if let value = value as? Int {
        return T(exactly: value)
    }
    return nil
}

func runSelfTest() -> Bool {
    guard integerValue(NSNumber(value: 7), as: Int32.self) == 7,
          integerValue(7, as: UInt32.self) == 7,
          integerValue(NSNumber(value: -1), as: UInt32.self) == nil
    else {
        fputs("数値変換のself-testに失敗しました。\n", stderr)
        return false
    }

    let sample = PointerWindowStackReport(
        schemaVersion: 1,
        wallClockUnixSeconds: 1,
        systemUptimeSeconds: 2,
        pointer: PointRecord(x: 3, y: 4),
        frontmostApplication: ApplicationRecord(
            processID: 5,
            bundleIdentifier: "example.app",
            localizedName: "Example"
        ),
        windows: [
            WindowRecord(
                stackIndex: 0,
                ownerName: "Example",
                ownerProcessID: 5,
                windowNumber: 6,
                bounds: BoundsRecord(x: 0, y: 0, width: 10, height: 10),
                alpha: 1
            )
        ]
    )
    do {
        let data = try JSONEncoder().encode(sample)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["schemaVersion"] as? Int == 1,
              object?["systemUptimeSeconds"] as? Double == 2,
              let windows = object?["windows"] as? [[String: Any]],
              windows.first?["stackIndex"] as? Int == 0
        else {
            fputs("JSON schemaのself-testに失敗しました。\n", stderr)
            return false
        }
    } catch {
        fputs("JSON encodeのself-testに失敗しました: \(error)\n", stderr)
        return false
    }
    return true
}

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    guard arguments == ["--self-test"] else {
        fputs("使い方: swift scripts/capture-pointer-window-stack.swift [--self-test]\n", stderr)
        exit(2)
    }
    guard runSelfTest() else {
        exit(1)
    }
    print("ポインタ直下window stackのself-testに成功しました。")
    exit(0)
}

guard let pointerEvent = CGEvent(source: nil) else {
    fputs("Quartzポインタ位置を取得できませんでした。\n", stderr)
    exit(1)
}
let pointer = pointerEvent.location
let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let descriptions = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fputs("ポインタ直下window一覧を取得できませんでした。\n", stderr)
    exit(1)
}

var windows: [WindowRecord] = []
for (stackIndex, description) in descriptions.enumerated() {
    guard let layer = integerValue(description[kCGWindowLayer as String], as: Int.self),
          layer == 0,
          let ownerProcessID = integerValue(
              description[kCGWindowOwnerPID as String],
              as: Int32.self
          ),
          let windowNumber = integerValue(
              description[kCGWindowNumber as String],
              as: UInt32.self
          ),
          let rawBounds = description[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
          bounds.contains(pointer)
    else {
        continue
    }

    windows.append(
        WindowRecord(
            stackIndex: stackIndex,
            ownerName: description[kCGWindowOwnerName as String] as? String,
            ownerProcessID: ownerProcessID,
            windowNumber: windowNumber,
            bounds: BoundsRecord(
                x: bounds.origin.x,
                y: bounds.origin.y,
                width: bounds.width,
                height: bounds.height
            ),
            alpha: (description[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
        )
    )
}

let frontmostApplication = NSWorkspace.shared.frontmostApplication.map {
    ApplicationRecord(
        processID: $0.processIdentifier,
        bundleIdentifier: $0.bundleIdentifier,
        localizedName: $0.localizedName
    )
}
let report = PointerWindowStackReport(
    schemaVersion: 1,
    wallClockUnixSeconds: Date().timeIntervalSince1970,
    systemUptimeSeconds: ProcessInfo.processInfo.systemUptime,
    pointer: PointRecord(x: pointer.x, y: pointer.y),
    frontmostApplication: frontmostApplication,
    windows: windows
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(report)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
