import AppKit
import CoreGraphics
import Foundation
import NapeGestureCore

public enum TrackpadDriverEventSnapshotError: LocalizedError, Equatable {
    case unsupportedEventFieldLayout
    case serializedEventUnavailable(captureIndex: UInt64)

    public var errorDescription: String? {
        switch self {
        case .unsupportedEventFieldLayout:
            return "この環境のCGEventField表現ではraw field 0...255を安全に取得できません。"
        case let .serializedEventUnavailable(captureIndex):
            return "CGEventのserialized dataを取得できません。captureIndex=\(captureIndex)"
        }
    }
}

public enum TrackpadDriverEventSnapshotFactory {
    public static var supportsRawFieldScan: Bool {
        MemoryLayout<CGEventField>.size == MemoryLayout<UInt32>.size
    }

    public static func makeRecord(
        event: CGEvent,
        observedType: CGEventType? = nil,
        captureIndex: UInt64,
        metadata: TrackpadDriverEventLogMetadata
    ) throws -> TrackpadDriverEventLog {
        guard supportsRawFieldScan else {
            throw TrackpadDriverEventSnapshotError.unsupportedEventFieldLayout
        }
        guard let serializedData = event.data else {
            throw TrackpadDriverEventSnapshotError.serializedEventUnavailable(
                captureIndex: captureIndex
            )
        }

        let type = observedType ?? event.type
        let fixedDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let fixedDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedDeltaZ = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3)
        let pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pointDeltaZ = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis3)

        return TrackpadDriverEventLog(
            metadata: metadata,
            captureIndex: captureIndex,
            timestamp: event.timestamp,
            typeRaw: Int(type.rawValue),
            typeName: stableTypeName(type),
            eventSubtype: safeEventSubtype(event: event, observedType: type),
            flags: event.flags.rawValue,
            scrollDeltaX: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            scrollDeltaY: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            scrollDeltaZ: event.getIntegerValueField(.scrollWheelEventDeltaAxis3),
            scrollFixedDeltaX: finiteValue(fixedDeltaX),
            scrollFixedDeltaXBitPattern: fixedDeltaX.bitPattern,
            scrollFixedDeltaY: finiteValue(fixedDeltaY),
            scrollFixedDeltaYBitPattern: fixedDeltaY.bitPattern,
            scrollFixedDeltaZ: finiteValue(fixedDeltaZ),
            scrollFixedDeltaZBitPattern: fixedDeltaZ.bitPattern,
            scrollPointDeltaX: finiteValue(pointDeltaX),
            scrollPointDeltaXBitPattern: pointDeltaX.bitPattern,
            scrollPointDeltaY: finiteValue(pointDeltaY),
            scrollPointDeltaYBitPattern: pointDeltaY.bitPattern,
            scrollPointDeltaZ: finiteValue(pointDeltaZ),
            scrollPointDeltaZBitPattern: pointDeltaZ.bitPattern,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData),
            rawFields: rawFields(event: event),
            serializedEventBase64: (serializedData as Data).base64EncodedString()
        )
    }

    private static func rawFields(event: CGEvent) -> [TrackpadDriverRawField] {
        (TrackpadDriverEventLog.rawFieldScanLowerBound...TrackpadDriverEventLog.maximumRawFieldNumber)
            .map { fieldNumber in
                let field = rawEventField(fieldNumber: fieldNumber)
                let integerValue = event.getIntegerValueField(field)
                let doubleValue = event.getDoubleValueField(field)
                return TrackpadDriverRawField(
                    fieldNumber: fieldNumber,
                    integerValue: integerValue,
                    doubleValue: finiteValue(doubleValue),
                    doubleBitPattern: doubleValue.bitPattern
                )
            }
    }

    private static func finiteValue(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    private static func safeEventSubtype(
        event: CGEvent,
        observedType: CGEventType
    ) -> Int64? {
        let appKitType = NSEvent.EventType(rawValue: UInt(observedType.rawValue))
        switch appKitType {
        case .appKitDefined, .systemDefined, .applicationDefined, .periodic:
            return NSEvent(cgEvent: event).map { Int64($0.subtype.rawValue) }
        default:
            return nil
        }
    }

    private static func rawEventField(fieldNumber: Int) -> CGEventField {
        unsafeBitCast(UInt32(fieldNumber), to: CGEventField.self)
    }

    private static func stableTypeName(_ type: CGEventType) -> String {
        switch type {
        case .null:
            return "null"
        case .leftMouseDown:
            return "leftMouseDown"
        case .leftMouseUp:
            return "leftMouseUp"
        case .rightMouseDown:
            return "rightMouseDown"
        case .rightMouseUp:
            return "rightMouseUp"
        case .mouseMoved:
            return "mouseMoved"
        case .leftMouseDragged:
            return "leftMouseDragged"
        case .rightMouseDragged:
            return "rightMouseDragged"
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        case .flagsChanged:
            return "flagsChanged"
        case .scrollWheel:
            return "scrollWheel"
        case .tabletPointer:
            return "tabletPointer"
        case .tabletProximity:
            return "tabletProximity"
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .otherMouseDragged:
            return "otherMouseDragged"
        default:
            return "raw-\(type.rawValue)"
        }
    }
}
