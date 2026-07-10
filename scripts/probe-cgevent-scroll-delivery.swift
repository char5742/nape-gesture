import AppKit
import CoreGraphics
import Foundation

enum ProbeVariant: String, CaseIterable {
    case pidHIDFullMarked = "pid-hid-full-marked"
    case pidHIDFullUnmarked = "pid-hid-full-unmarked"
    case pidCombinedFullUnmarked = "pid-combined-full-unmarked"
    case hidTapHIDFullMarked = "hidtap-hid-full-marked"
    case hidTapHIDFullUnmarked = "hidtap-hid-full-unmarked"
    case hidTapCombinedFullUnmarked = "hidtap-combined-full-unmarked"
    case sessionTapCombinedFullUnmarked = "sessiontap-combined-full-unmarked"
    case annotatedTapCombinedFullUnmarked = "annotatedtap-combined-full-unmarked"
    case hidTapHIDMinimalUnmarked = "hidtap-hid-minimal-unmarked"
    case hidTapHIDLineUnmarked = "hidtap-hid-line-unmarked"

    var sourceState: CGEventSourceStateID {
        switch self {
        case .pidCombinedFullUnmarked,
             .hidTapCombinedFullUnmarked,
             .sessionTapCombinedFullUnmarked,
             .annotatedTapCombinedFullUnmarked:
            return .combinedSessionState
        default:
            return .hidSystemState
        }
    }

    var units: CGScrollEventUnit {
        self == .hidTapHIDLineUnmarked ? .line : .pixel
    }

    var usesFullFields: Bool {
        switch self {
        case .hidTapHIDMinimalUnmarked, .hidTapHIDLineUnmarked:
            return false
        default:
            return true
        }
    }

    var usesGeneratedMarker: Bool {
        self == .pidHIDFullMarked || self == .hidTapHIDFullMarked
    }
}

struct ProbeReport: Encodable {
    var variant: String
    var processID: Int32
    var sourceState: String
    var units: String
    var destination: String
    var usesFullFields: Bool
    var usesGeneratedMarker: Bool
    var pointerX: Double
    var pointerY: Double
    var windowNumber: UInt32?
}

func windowNumber(at point: CGPoint, processID: pid_t) -> UInt32? {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    guard let descriptions = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for description in descriptions {
        guard let layer = description[kCGWindowLayer as String] as? Int,
              layer == 0,
              let ownerPID = description[kCGWindowOwnerPID as String] as? pid_t,
              ownerPID == processID,
              let rawWindowNumber = description[kCGWindowNumber as String] as? UInt32,
              let bounds = description[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              frame.contains(point)
        else {
            continue
        }
        return rawWindowNumber
    }
    return nil
}

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let variant = ProbeVariant(rawValue: arguments[1]),
      let rawPID = Int32(arguments[2]),
      rawPID > 0
else {
    let variants = ProbeVariant.allCases.map(\.rawValue).joined(separator: ", ")
    fputs("使い方: swift scripts/probe-cgevent-scroll-delivery.swift <variant> <PID>\n", stderr)
    fputs("variant: \(variants)\n", stderr)
    exit(2)
}

let processID = pid_t(rawPID)
let source = CGEventSource(stateID: variant.sourceState)
source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)
let wheelDelta: Int32 = variant.units == .line ? 8 : 800
guard let event = CGEvent(
    scrollWheelEvent2Source: source,
    units: variant.units,
    wheelCount: 2,
    wheel1: wheelDelta,
    wheel2: 0,
    wheel3: 0
) else {
    fputs("scrollWheel CGEvent を作成できませんでした。\n", stderr)
    exit(1)
}

let point = CGEvent(source: nil)?.location ?? .zero
let targetWindowNumber = windowNumber(at: point, processID: processID)
event.location = point
if variant.usesFullFields {
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(NSEvent.Phase.changed.rawValue))
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 800)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
    if let targetWindowNumber {
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(targetWindowNumber))
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            value: Int64(targetWindowNumber)
        )
    }
}
if variant.usesGeneratedMarker {
    event.setIntegerValueField(.eventSourceUserData, value: 0x4D_47_53_54)
}

let destination: String
switch variant {
case .pidHIDFullMarked, .pidHIDFullUnmarked, .pidCombinedFullUnmarked:
    event.postToPid(processID)
    destination = "process"
case .hidTapHIDFullMarked,
     .hidTapHIDFullUnmarked,
     .hidTapCombinedFullUnmarked,
     .hidTapHIDMinimalUnmarked,
     .hidTapHIDLineUnmarked:
    event.post(tap: .cghidEventTap)
    destination = "cghidEventTap"
case .sessionTapCombinedFullUnmarked:
    event.post(tap: .cgSessionEventTap)
    destination = "cgSessionEventTap"
case .annotatedTapCombinedFullUnmarked:
    event.post(tap: .cgAnnotatedSessionEventTap)
    destination = "cgAnnotatedSessionEventTap"
}

let report = ProbeReport(
    variant: variant.rawValue,
    processID: rawPID,
    sourceState: variant.sourceState == .hidSystemState ? "hidSystemState" : "combinedSessionState",
    units: variant.units == .line ? "line" : "pixel",
    destination: destination,
    usesFullFields: variant.usesFullFields,
    usesGeneratedMarker: variant.usesGeneratedMarker,
    pointerX: point.x,
    pointerY: point.y,
    windowNumber: targetWindowNumber
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(report)
print(String(decoding: data, as: UTF8.self))
