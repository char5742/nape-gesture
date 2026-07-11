import AppKit
import CoreGraphics
import Foundation
import NapeGestureCore

public struct TrackpadDriverEventHostIssue: Codable, Equatable {
    public var captureIndex: UInt64?
    public var field: String
    public var message: String
}

public struct TrackpadDriverEventHostAnalysis: Codable, Equatable {
    public var passed: Bool
    public var eventCount: Int
    public var reconstructedEventCount: Int
    public var issues: [TrackpadDriverEventHostIssue]
    public var rawFieldDifferences: [TrackpadDriverEventHostIssue]

}

public enum TrackpadDriverEventHostAnalyzer {
    public static func analyze(records: [TrackpadDriverEventLog]) -> TrackpadDriverEventHostAnalysis {
        guard supportsRawFieldScan else {
            return TrackpadDriverEventHostAnalysis(
                passed: false,
                eventCount: records.count,
                reconstructedEventCount: 0,
                issues: [
                    TrackpadDriverEventHostIssue(
                        captureIndex: nil,
                        field: "rawFields",
                        message: "この環境のCGEventField表現ではraw fieldの再構築検証を安全に実行できません。"
                    )
                ],
                rawFieldDifferences: []
            )
        }

        var reconstructedEventCount = 0
        var issues: [TrackpadDriverEventHostIssue] = []
        var rawFieldDifferences: [TrackpadDriverEventHostIssue] = []
        for record in records {
            guard let serializedEventBase64 = record.serializedEventBase64,
                  let data = Data(base64Encoded: serializedEventBase64),
                  !data.isEmpty
            else {
                append(
                    record: record,
                    field: "serializedEventBase64",
                    message: "serialized eventをBase64から復元できません。",
                    to: &issues
                )
                continue
            }
            guard let event = CGEvent(withDataAllocator: nil, data: data as CFData) else {
                append(
                    record: record,
                    field: "serializedEventBase64",
                    message: "CoreGraphicsがserialized event dataをCGEventとして再構築できません。",
                    to: &issues
                )
                continue
            }

            reconstructedEventCount += 1
            compareIdentity(record: record, event: event, issues: &issues)
            compareNamedFields(record: record, event: event, issues: &issues)
            compareRawFields(
                record: record,
                event: event,
                differences: &rawFieldDifferences
            )
        }

        return TrackpadDriverEventHostAnalysis(
            passed: issues.isEmpty && reconstructedEventCount == records.count,
            eventCount: records.count,
            reconstructedEventCount: reconstructedEventCount,
            issues: issues,
            rawFieldDifferences: rawFieldDifferences
        )
    }

    private static func compareIdentity(
        record: TrackpadDriverEventLog,
        event: CGEvent,
        issues: inout [TrackpadDriverEventHostIssue]
    ) {
        compare(
            record: record,
            field: "typeRaw",
            expected: String(record.typeRaw),
            actual: String(event.type.rawValue),
            issues: &issues
        )
        compare(
            record: record,
            field: "typeName",
            expected: record.typeName,
            actual: stableTypeName(event.type),
            issues: &issues
        )
        compare(
            record: record,
            field: "timestamp",
            expected: String(record.timestamp),
            actual: String(event.timestamp),
            issues: &issues
        )
        compare(
            record: record,
            field: "flags",
            expected: String(record.flags),
            actual: String(event.flags.rawValue),
            issues: &issues
        )

        if let expectedSubtype = record.eventSubtype {
            let actualSubtype = NSEvent(cgEvent: event).map { Int64($0.subtype.rawValue) }
            compare(
                record: record,
                field: "eventSubtype",
                expected: String(expectedSubtype),
                actual: actualSubtype.map(String.init) ?? "null",
                issues: &issues
            )
        }
    }

    private static func compareNamedFields(
        record: TrackpadDriverEventLog,
        event: CGEvent,
        issues: inout [TrackpadDriverEventHostIssue]
    ) {
        let integerFields: [(String, Int64, CGEventField)] = [
            ("scrollDeltaX", record.scrollDeltaX, .scrollWheelEventDeltaAxis2),
            ("scrollDeltaY", record.scrollDeltaY, .scrollWheelEventDeltaAxis1),
            ("scrollDeltaZ", record.scrollDeltaZ, .scrollWheelEventDeltaAxis3),
            ("scrollPhase", record.scrollPhase, .scrollWheelEventScrollPhase),
            ("momentumPhase", record.momentumPhase, .scrollWheelEventMomentumPhase),
            ("isContinuous", record.isContinuous, .scrollWheelEventIsContinuous),
            ("sourceUserData", record.sourceUserData, .eventSourceUserData)
        ]
        for (name, expected, field) in integerFields {
            compare(
                record: record,
                field: name,
                expected: String(expected),
                actual: String(event.getIntegerValueField(field)),
                issues: &issues
            )
        }

        let doubleFields: [(String, UInt64, CGEventField)] = [
            ("scrollFixedDeltaXBitPattern", record.scrollFixedDeltaXBitPattern, .scrollWheelEventFixedPtDeltaAxis2),
            ("scrollFixedDeltaYBitPattern", record.scrollFixedDeltaYBitPattern, .scrollWheelEventFixedPtDeltaAxis1),
            ("scrollFixedDeltaZBitPattern", record.scrollFixedDeltaZBitPattern, .scrollWheelEventFixedPtDeltaAxis3),
            ("scrollPointDeltaXBitPattern", record.scrollPointDeltaXBitPattern, .scrollWheelEventPointDeltaAxis2),
            ("scrollPointDeltaYBitPattern", record.scrollPointDeltaYBitPattern, .scrollWheelEventPointDeltaAxis1),
            ("scrollPointDeltaZBitPattern", record.scrollPointDeltaZBitPattern, .scrollWheelEventPointDeltaAxis3)
        ]
        for (name, expected, field) in doubleFields {
            compare(
                record: record,
                field: name,
                expected: String(expected),
                actual: String(event.getDoubleValueField(field).bitPattern),
                issues: &issues
            )
        }
    }

    private static func compareRawFields(
        record: TrackpadDriverEventLog,
        event: CGEvent,
        differences: inout [TrackpadDriverEventHostIssue]
    ) {
        for rawField in record.rawFields {
            guard (TrackpadDriverEventLog.rawFieldScanLowerBound...TrackpadDriverEventLog.maximumRawFieldNumber)
                .contains(rawField.fieldNumber)
            else {
                continue
            }
            let field = rawEventField(fieldNumber: rawField.fieldNumber)
            compare(
                record: record,
                field: "rawFields[\(rawField.fieldNumber)].integerValue",
                expected: rawField.integerValue.map(String.init) ?? "null",
                actual: String(event.getIntegerValueField(field)),
                issues: &differences
            )
            compare(
                record: record,
                field: "rawFields[\(rawField.fieldNumber)].doubleBitPattern",
                expected: String(rawField.doubleBitPattern),
                actual: String(event.getDoubleValueField(field).bitPattern),
                issues: &differences
            )
        }
    }

    private static func compare(
        record: TrackpadDriverEventLog,
        field: String,
        expected: String,
        actual: String,
        issues: inout [TrackpadDriverEventHostIssue]
    ) {
        guard expected != actual else {
            return
        }
        append(
            record: record,
            field: field,
            message: "JSON recordとserialized eventが一致しません。expected=\(expected) actual=\(actual)",
            to: &issues
        )
    }

    private static func append(
        record: TrackpadDriverEventLog,
        field: String,
        message: String,
        to issues: inout [TrackpadDriverEventHostIssue]
    ) {
        issues.append(
            TrackpadDriverEventHostIssue(
                captureIndex: record.captureIndex,
                field: field,
                message: message
            )
        )
    }

    private static var supportsRawFieldScan: Bool {
        MemoryLayout<CGEventField>.size == MemoryLayout<UInt32>.size
    }

    private static func rawEventField(fieldNumber: Int) -> CGEventField {
        unsafeBitCast(UInt32(fieldNumber), to: CGEventField.self)
    }

    private static func stableTypeName(_ type: CGEventType) -> String {
        switch type {
        case .null:
            "null"
        case .leftMouseDown:
            "leftMouseDown"
        case .leftMouseUp:
            "leftMouseUp"
        case .rightMouseDown:
            "rightMouseDown"
        case .rightMouseUp:
            "rightMouseUp"
        case .mouseMoved:
            "mouseMoved"
        case .leftMouseDragged:
            "leftMouseDragged"
        case .rightMouseDragged:
            "rightMouseDragged"
        case .keyDown:
            "keyDown"
        case .keyUp:
            "keyUp"
        case .flagsChanged:
            "flagsChanged"
        case .scrollWheel:
            "scrollWheel"
        case .tabletPointer:
            "tabletPointer"
        case .tabletProximity:
            "tabletProximity"
        case .otherMouseDown:
            "otherMouseDown"
        case .otherMouseUp:
            "otherMouseUp"
        case .otherMouseDragged:
            "otherMouseDragged"
        default:
            "raw-\(type.rawValue)"
        }
    }
}
