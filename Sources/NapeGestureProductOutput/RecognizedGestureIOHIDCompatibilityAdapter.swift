import CoreGraphics
import Darwin
import Foundation
import IOKit
import NapeGestureCore

enum RecognizedGestureIOHIDPayload: Equatable, Sendable {
    case dockSwipe(
        motion: UInt32,
        phase: Int64,
        progress: Double,
        positionX: Double,
        positionY: Double,
        terminalVelocityX: Double,
        terminalVelocityY: Double,
        terminalVelocityZ: Double
    )
}

private struct RecognizedDockSwipeTemplateDocument: Decodable {
    struct SourceLogSHA256: Decodable {
        let horizontal: String
        let vertical: String
    }

    struct PhaseTemplates: Decodable {
        let began: String
        let changed: String
        let ended: String
    }

    struct SignedTemplates: Decodable {
        let positive: PhaseTemplates
        let negative: PhaseTemplates
    }

    struct Templates: Decodable {
        let horizontal: SignedTemplates
        let vertical: SignedTemplates
    }

    let schemaVersion: Int
    let fixtureID: String
    let contractID: String
    let osVersion: String
    let osBuild: String
    let sourceLogSHA256: SourceLogSHA256
    let templates: Templates
}

enum RecognizedDockSwipeTemplatePolarity: CaseIterable, Sendable {
    case positive
    case negative
}

private struct RecognizedDockSwipeTemplates {
    enum Axis: CaseIterable {
        case horizontal
        case vertical

        var motion: UInt32 {
            switch self {
            case .horizontal: 1
            case .vertical: 2
            }
        }
    }

    private struct PhaseData {
        let began: Data
        let changed: Data
        let ended: Data

        func data(for phase: Int64) -> Data? {
            switch phase {
            case 1: began
            case 2: changed
            case 4, 8: ended
            default: nil
            }
        }
    }

    static let registeredFixtureSHA256 =
        "852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6"

    private let horizontalPositive: PhaseData
    private let horizontalNegative: PhaseData
    private let verticalPositive: PhaseData
    private let verticalNegative: PhaseData

    init?(data: Data, contract: VerifiedProductGestureOutputContract) {
        guard
            TrackpadDriverEventCaptureManifest.sha256HexDigest(of: data)
                == Self.registeredFixtureSHA256,
            let document = try? JSONDecoder().decode(
                RecognizedDockSwipeTemplateDocument.self,
                from: data
            ),
            document.schemaVersion == 2,
            document.fixtureID == "recognized-dockswipe-templates-25F80-v2",
            document.contractID == "recognized-dockswipe-template-v2",
            document.osVersion == contract.osVersion,
            document.osBuild == contract.osBuild,
            Self.isCanonicalSHA256(document.sourceLogSHA256.horizontal),
            Self.isCanonicalSHA256(document.sourceLogSHA256.vertical),
            let horizontalPositive = Self.phaseData(
                document.templates.horizontal.positive,
                polarity: .positive
            ),
            let horizontalNegative = Self.phaseData(
                document.templates.horizontal.negative,
                polarity: .negative
            ),
            let verticalPositive = Self.phaseData(
                document.templates.vertical.positive,
                polarity: .positive
            ),
            let verticalNegative = Self.phaseData(
                document.templates.vertical.negative,
                polarity: .negative
            )
        else {
            return nil
        }

        self.horizontalPositive = horizontalPositive
        self.horizontalNegative = horizontalNegative
        self.verticalPositive = verticalPositive
        self.verticalNegative = verticalNegative
    }

    func data(
        axis: Axis,
        polarity: RecognizedDockSwipeTemplatePolarity,
        phase: Int64
    ) -> Data? {
        switch (axis, polarity) {
        case (.horizontal, .positive): horizontalPositive.data(for: phase)
        case (.horizontal, .negative): horizontalNegative.data(for: phase)
        case (.vertical, .positive): verticalPositive.data(for: phase)
        case (.vertical, .negative): verticalNegative.data(for: phase)
        }
    }

    private static func phaseData(
        _ templates: RecognizedDockSwipeTemplateDocument.PhaseTemplates,
        polarity: RecognizedDockSwipeTemplatePolarity
    ) -> PhaseData? {
        guard
            let began = eventData(templates.began, phase: 1, polarity: polarity),
            let changed = eventData(templates.changed, phase: 2, polarity: polarity),
            let ended = eventData(templates.ended, phase: 4, polarity: polarity)
        else {
            return nil
        }
        return PhaseData(began: began, changed: changed, ended: ended)
    }

    private static func eventData(
        _ encoded: String,
        phase: Int64,
        polarity: RecognizedDockSwipeTemplatePolarity
    ) -> Data? {
        guard
            let data = Data(base64Encoded: encoded),
            data.base64EncodedString() == encoded,
            let event = CGEvent(withDataAllocator: nil, data: data as CFData),
            event.type.rawValue == 30,
            event.getIntegerValueField(rawField(55)) == 30,
            event.getIntegerValueField(rawField(110)) == 23,
            event.getIntegerValueField(rawField(132)) == phase,
            event.getIntegerValueField(rawField(134)) == phase,
            hasExpectedProgressPolarity(event, polarity: polarity)
        else {
            return nil
        }
        return data
    }

    private static func hasExpectedProgressPolarity(
        _ event: CGEvent,
        polarity: RecognizedDockSwipeTemplatePolarity
    ) -> Bool {
        let encodedProgress = event.getDoubleValueField(rawField(124))
        switch polarity {
        case .positive: return encodedProgress < 0
        case .negative: return encodedProgress > 0
        }
    }

    private static func rawField(_ number: Int) -> CGEventField {
        unsafeBitCast(UInt32(number), to: CGEventField.self)
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
        }
    }
}

final class RecognizedGestureIOHIDCompatibilityAdapter {
    private typealias CopyIOHIDEvent = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> Unmanaged<CFTypeRef>?
    private typealias SetTimestamp = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64
    ) -> Void
    private typealias SetSenderID = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64
    ) -> Void
    private typealias SetEventFlags = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt32
    ) -> Void
    private typealias SetIntegerValue = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt32,
        Int64
    ) -> Void
    private typealias SetFloatValue = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt32,
        Double
    ) -> Void
    private typealias GetIntegerValue = @convention(c) (
        UnsafeRawPointer?,
        UInt32
    ) -> Int64
    private typealias GetFloatValue = @convention(c) (
        UnsafeRawPointer?,
        UInt32
    ) -> Double
    private typealias GetPhase = @convention(c) (
        UnsafeRawPointer?
    ) -> UInt32
    private typealias GetType = @convention(c) (
        UnsafeRawPointer?
    ) -> UInt32
    private typealias GetChildren = @convention(c) (
        UnsafeRawPointer?
    ) -> Unmanaged<CFArray>?

    private static let ioKitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"
    private static let coreGraphicsPath =
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    private static let dockSwipeType: UInt32 = 23
    private static let velocityType: UInt32 = 9
    private static let dockSwipeMaskField: UInt32 = dockSwipeType << 16
    private static let dockSwipeMotionField = dockSwipeMaskField + 1
    private static let dockSwipeProgressField = dockSwipeMaskField + 2
    private static let dockSwipePositionXField = dockSwipeMaskField + 3
    private static let dockSwipePositionYField = dockSwipeMaskField + 4
    private static let dockSwipeFlavorField = dockSwipeMaskField + 5
    private static let dockSwipePositionZField = dockSwipeMaskField + 6
    private static let velocityXField: UInt32 = velocityType << 16
    private static let velocityYField = velocityXField + 1
    private static let velocityZField = velocityXField + 2

    private let ioKitHandle: UnsafeMutableRawPointer
    private let coreGraphicsHandle: UnsafeMutableRawPointer
    private let copyIOHIDEvent: CopyIOHIDEvent
    private let setTimestamp: SetTimestamp
    private let setSenderID: SetSenderID
    private let setEventFlags: SetEventFlags
    private let setIntegerValue: SetIntegerValue
    private let setFloatValue: SetFloatValue
    private let getIntegerValue: GetIntegerValue
    private let getFloatValue: GetFloatValue
    private let getPhase: GetPhase
    private let getType: GetType
    private let getChildren: GetChildren
    private let templates: RecognizedDockSwipeTemplates
    private let senderID: UInt64?
    private let timebase: mach_timebase_info_data_t

    init?(fixtureData: Data, contract: VerifiedProductGestureOutputContract) {
        guard let templates = RecognizedDockSwipeTemplates(data: fixtureData, contract: contract),
              let ioKitHandle = dlopen(Self.ioKitPath, RTLD_NOW | RTLD_LOCAL),
              let coreGraphicsHandle = dlopen(Self.coreGraphicsPath, RTLD_NOW | RTLD_LOCAL)
        else {
            return nil
        }
        guard
            let copySymbol = dlsym(coreGraphicsHandle, "CGEventCopyIOHIDEvent"),
            let setTimestampSymbol = dlsym(ioKitHandle, "IOHIDEventSetTimeStamp"),
            let setSenderIDSymbol = dlsym(ioKitHandle, "IOHIDEventSetSenderID"),
            let setEventFlagsSymbol = dlsym(ioKitHandle, "IOHIDEventSetEventFlags"),
            let setIntegerSymbol = dlsym(ioKitHandle, "IOHIDEventSetIntegerValue"),
            let setFloatSymbol = dlsym(ioKitHandle, "IOHIDEventSetFloatValue"),
            let getIntegerSymbol = dlsym(ioKitHandle, "IOHIDEventGetIntegerValue"),
            let getFloatSymbol = dlsym(ioKitHandle, "IOHIDEventGetFloatValue"),
            let getPhaseSymbol = dlsym(ioKitHandle, "IOHIDEventGetPhase"),
            let getTypeSymbol = dlsym(ioKitHandle, "IOHIDEventGetType"),
            let getChildrenSymbol = dlsym(ioKitHandle, "IOHIDEventGetChildren")
        else {
            dlclose(coreGraphicsHandle)
            dlclose(ioKitHandle)
            return nil
        }

        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS,
              timebase.numer > 0,
              timebase.denom > 0
        else {
            dlclose(coreGraphicsHandle)
            dlclose(ioKitHandle)
            return nil
        }

        let copyIOHIDEvent: CopyIOHIDEvent = unsafeBitCast(
            copySymbol,
            to: CopyIOHIDEvent.self
        )
        let setTimestamp: SetTimestamp = unsafeBitCast(setTimestampSymbol, to: SetTimestamp.self)
        let setSenderID: SetSenderID = unsafeBitCast(setSenderIDSymbol, to: SetSenderID.self)
        let setEventFlags: SetEventFlags = unsafeBitCast(
            setEventFlagsSymbol,
            to: SetEventFlags.self
        )
        let setIntegerValue: SetIntegerValue = unsafeBitCast(
            setIntegerSymbol,
            to: SetIntegerValue.self
        )
        let setFloatValue: SetFloatValue = unsafeBitCast(
            setFloatSymbol,
            to: SetFloatValue.self
        )
        let getIntegerValue: GetIntegerValue = unsafeBitCast(
            getIntegerSymbol,
            to: GetIntegerValue.self
        )
        let getFloatValue: GetFloatValue = unsafeBitCast(
            getFloatSymbol,
            to: GetFloatValue.self
        )
        let getPhase: GetPhase = unsafeBitCast(getPhaseSymbol, to: GetPhase.self)
        let getType: GetType = unsafeBitCast(getTypeSymbol, to: GetType.self)
        let getChildren: GetChildren = unsafeBitCast(getChildrenSymbol, to: GetChildren.self)
        guard Self.validateTemplateIOHIDContracts(
            templates,
            copyIOHIDEvent: copyIOHIDEvent,
            getIntegerValue: getIntegerValue,
            getFloatValue: getFloatValue,
            getPhase: getPhase,
            getType: getType,
            getChildren: getChildren
        ) else {
            dlclose(coreGraphicsHandle)
            dlclose(ioKitHandle)
            return nil
        }

        let senderID = Self.resolveTrackpadSenderID()
        self.templates = templates
        self.ioKitHandle = ioKitHandle
        self.coreGraphicsHandle = coreGraphicsHandle
        self.copyIOHIDEvent = copyIOHIDEvent
        self.setTimestamp = setTimestamp
        self.setSenderID = setSenderID
        self.setEventFlags = setEventFlags
        self.setIntegerValue = setIntegerValue
        self.setFloatValue = setFloatValue
        self.getIntegerValue = getIntegerValue
        self.getFloatValue = getFloatValue
        self.getPhase = getPhase
        self.getType = getType
        self.getChildren = getChildren
        self.senderID = senderID
        self.timebase = timebase
    }

    deinit {
        dlclose(coreGraphicsHandle)
        dlclose(ioKitHandle)
    }

    func makeEvent(
        payload: RecognizedGestureIOHIDPayload,
        timestamp: MonotonicEventTimestamp,
        polarity: RecognizedDockSwipeTemplatePolarity
    ) -> CGEvent? {
        guard case let .dockSwipe(
            motion,
            phase,
            progress,
            positionX,
            positionY,
            terminalVelocityX,
            terminalVelocityY,
            terminalVelocityZ
        ) = payload,
            let options = Self.options(for: phase),
            [
                progress,
                positionX,
                positionY,
                terminalVelocityX,
                terminalVelocityY,
                terminalVelocityZ,
            ].allSatisfy(\.isFinite),
            let templateAxis = Self.templateAxis(for: motion),
            let templateData = templates.data(
                axis: templateAxis,
                polarity: polarity,
                phase: phase
            ),
            let event = CGEvent(withDataAllocator: nil, data: templateData as CFData),
            let absoluteTimestamp = absoluteTimestamp(
                fromNanoseconds: timestamp.nanosecondsSinceStartup
            ),
            let hidEvent = copyIOHIDEvent(
                Unmanaged.passUnretained(event).toOpaque()
            )?.takeRetainedValue()
        else {
            return nil
        }

        let hidPointer = Unmanaged.passUnretained(hidEvent).toOpaque()
        guard getType(hidPointer) == Self.dockSwipeType else {
            return nil
        }
        setTimestamp(hidPointer, absoluteTimestamp)
        if let senderID {
            setSenderID(hidPointer, senderID)
        }
        setEventFlags(hidPointer, options)
        setIntegerValue(hidPointer, Self.dockSwipeMaskField, 0)
        setIntegerValue(hidPointer, Self.dockSwipeMotionField, Int64(motion))
        setIntegerValue(hidPointer, Self.dockSwipeFlavorField, 3)
        setFloatValue(hidPointer, Self.dockSwipeProgressField, progress)
        setFloatValue(hidPointer, Self.dockSwipePositionXField, positionX)
        setFloatValue(hidPointer, Self.dockSwipePositionYField, positionY)
        setFloatValue(hidPointer, Self.dockSwipePositionZField, 0)

        if phase == 4 || phase == 8 {
            guard updateTerminalVelocity(
                parent: hidPointer,
                timestamp: absoluteTimestamp,
                x: terminalVelocityX,
                y: terminalVelocityY,
                z: terminalVelocityZ
            ) else {
                return nil
            }
        }

        configureCGEvent(
            event,
            phase: phase,
            timestamp: timestamp,
            progress: progress,
            positionX: positionX,
            positionY: positionY,
            terminalVelocityX: terminalVelocityX,
            terminalVelocityY: terminalVelocityY,
            terminalVelocityZ: terminalVelocityZ
        )

        guard event.data != nil,
              event.type.rawValue == 30,
              event.timestamp == timestamp.nanosecondsSinceStartup,
              event.getIntegerValueField(rawField(110)) == 23,
              event.getIntegerValueField(rawField(132)) == phase,
              event.getIntegerValueField(rawField(134)) == phase,
              event.getIntegerValueField(.eventSourceUserData)
                == NapeGestureGeneratedEventMarker.value,
              getPhase(hidPointer) == UInt32(phase),
              getIntegerValue(hidPointer, Self.dockSwipeMotionField) == Int64(motion),
              abs(getFloatValue(hidPointer, Self.dockSwipeProgressField) - progress)
                <= 1.0 / 65_536.0
        else {
            return nil
        }
        return event
    }

    private func updateTerminalVelocity(
        parent: UnsafeMutableRawPointer,
        timestamp: UInt64,
        x: Double,
        y: Double,
        z: Double
    ) -> Bool {
        guard let children = getChildren(parent)?.takeUnretainedValue(),
              CFArrayGetCount(children) == 1,
              let rawChild = CFArrayGetValueAtIndex(children, 0)
        else {
            return false
        }
        let child = UnsafeMutableRawPointer(mutating: rawChild)
        guard getType(child) == Self.velocityType else {
            return false
        }
        setTimestamp(child, timestamp)
        if let senderID {
            setSenderID(child, senderID)
        }
        setFloatValue(child, Self.velocityXField, x)
        setFloatValue(child, Self.velocityYField, y)
        setFloatValue(child, Self.velocityZField, z)
        return true
    }

    private func configureCGEvent(
        _ event: CGEvent,
        phase: Int64,
        timestamp: MonotonicEventTimestamp,
        progress: Double,
        positionX: Double,
        positionY: Double,
        terminalVelocityX: Double,
        terminalVelocityY: Double,
        terminalVelocityZ: Double
    ) {
        event.type = CGEventType(rawValue: 30)!
        event.timestamp = timestamp.nanosecondsSinceStartup
        event.setIntegerValueField(.eventSourceUserData, value: NapeGestureGeneratedEventMarker.value)
        event.setIntegerValueField(rawField(39), value: 0)
        event.setIntegerValueField(rawField(40), value: 0)
        event.setIntegerValueField(rawField(55), value: 30)
        event.setIntegerValueField(
            rawField(58),
            value: Int64(timestamp.nanosecondsSinceStartup)
        )
        event.setIntegerValueField(rawField(110), value: 23)
        event.setIntegerValueField(rawField(132), value: phase)
        event.setIntegerValueField(rawField(134), value: phase)
        event.setDoubleValueField(rawField(124), value: -progress)
        event.setDoubleValueField(rawField(125), value: -positionX)
        event.setDoubleValueField(rawField(126), value: -positionY)
        event.setIntegerValueField(
            rawField(135),
            value: Int64(UInt64(Float(-progress).bitPattern))
        )
        event.setIntegerValueField(rawField(136), value: 1)
        event.setIntegerValueField(rawField(138), value: 3)
        event.setDoubleValueField(rawField(129), value: -terminalVelocityX)
        event.setDoubleValueField(rawField(130), value: -terminalVelocityY)
        event.setDoubleValueField(rawField(131), value: -terminalVelocityZ)
    }

    private func absoluteTimestamp(fromNanoseconds nanoseconds: UInt64) -> UInt64? {
        let product = nanoseconds.multipliedFullWidth(by: UInt64(timebase.denom))
        let divisor = UInt64(timebase.numer)
        guard product.high < divisor else {
            return nil
        }
        return divisor.dividingFullWidth(product).quotient
    }

    private static func options(for phase: Int64) -> UInt32? {
        switch phase {
        case 1: 0x0100_0000
        case 2: 0x0200_0000
        case 4: 0x0400_0000
        case 8: 0x0800_0000
        default: nil
        }
    }

    private static func templateAxis(for motion: UInt32) -> RecognizedDockSwipeTemplates.Axis? {
        switch motion {
        case 1: .horizontal
        case 2, 4: .vertical
        default: nil
        }
    }

    private static func validateTemplateIOHIDContracts(
        _ templates: RecognizedDockSwipeTemplates,
        copyIOHIDEvent: CopyIOHIDEvent,
        getIntegerValue: GetIntegerValue,
        getFloatValue: GetFloatValue,
        getPhase: GetPhase,
        getType: GetType,
        getChildren: GetChildren
    ) -> Bool {
        for axis in RecognizedDockSwipeTemplates.Axis.allCases {
            for polarity in RecognizedDockSwipeTemplatePolarity.allCases {
                for phase: Int64 in [1, 2, 4] {
                    guard let data = templates.data(
                        axis: axis,
                        polarity: polarity,
                        phase: phase
                    ),
                        let event = CGEvent(withDataAllocator: nil, data: data as CFData),
                        let hidEvent = copyIOHIDEvent(
                            Unmanaged.passUnretained(event).toOpaque()
                        )?.takeRetainedValue()
                    else {
                        return false
                    }
                    let pointer = Unmanaged.passUnretained(hidEvent).toOpaque()
                    let progress = getFloatValue(pointer, dockSwipeProgressField)
                    guard getType(pointer) == dockSwipeType,
                          getPhase(pointer) == UInt32(phase),
                          getIntegerValue(pointer, dockSwipeMotionField) == Int64(axis.motion),
                          (polarity == .positive ? progress > 0 : progress < 0)
                    else {
                        return false
                    }
                    if phase == 4 {
                        guard let children = getChildren(pointer)?.takeUnretainedValue(),
                              CFArrayGetCount(children) == 1,
                              let child = CFArrayGetValueAtIndex(children, 0),
                              getType(child) == velocityType
                        else {
                            return false
                        }
                    }
                }
            }
        }
        return true
    }

    private func rawField(_ number: Int) -> CGEventField {
        unsafeBitCast(UInt32(number), to: CGEventField.self)
    }

    private static func resolveTrackpadSenderID() -> UInt64? {
        guard let matching = IOServiceMatching("AppleMultitouchDevice") else {
            return nil
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            == KERN_SUCCESS
        else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var fallback: UInt64?
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }
            defer { IOObjectRelease(service) }

            var registryEntryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryEntryID) == KERN_SUCCESS,
                  registryEntryID != 0
            else {
                continue
            }
            fallback = fallback ?? registryEntryID

            let property = IORegistryEntryCreateCFProperty(
                service,
                "MT Built-In" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
            if property as? Bool == true {
                return registryEntryID
            }
        }
        return fallback
    }
}
