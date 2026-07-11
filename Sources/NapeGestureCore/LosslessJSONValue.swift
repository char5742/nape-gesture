import Foundation

public struct LosslessJSONMember: Codable, Equatable, Sendable {
    public var key: String
    public var value: LosslessJSONValue

    public init(key: String, value: LosslessJSONValue) {
        self.key = key
        self.value = value
    }
}

public struct LosslessJSONObject: Codable, Equatable, Sendable {
    public var members: [LosslessJSONMember]

    public init(members: [LosslessJSONMember] = []) {
        self.members = members
    }

    public subscript(key: String) -> LosslessJSONValue? {
        value(forKey: key)
    }

    public func value(forKey key: String) -> LosslessJSONValue? {
        members.first { $0.key == key }?.value
    }

    public func contains(_ key: String) -> Bool {
        members.contains { $0.key == key }
    }

    public func filteringKeys(_ predicate: (String) -> Bool) -> LosslessJSONObject {
        LosslessJSONObject(members: members.filter { predicate($0.key) })
    }

    public func isSemanticallyEqual(to other: LosslessJSONObject) -> Bool {
        guard members.count == other.members.count else {
            return false
        }
        for member in members {
            guard let otherValue = other.value(forKey: member.key),
                  member.value.isSemanticallyEqual(to: otherValue)
            else {
                return false
            }
        }
        return true
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        members = try container.decode([LosslessJSONMember].self, forKey: .members)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(members, forKey: .members)
    }

    private enum CodingKeys: String, CodingKey {
        case members
    }
}

public indirect enum LosslessJSONValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case string(String)
    case signedInteger(Int64)
    case unsignedInteger(UInt64)
    case double(Double)
    case array([LosslessJSONValue])
    case object(LosslessJSONObject)

    public var objectValue: LosslessJSONObject? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    public var arrayValue: [LosslessJSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    public var int64Value: Int64? {
        switch self {
        case let .signedInteger(value):
            return value
        case let .unsignedInteger(value) where value <= UInt64(Int64.max):
            return Int64(value)
        default:
            return nil
        }
    }

    public var uint64Value: UInt64? {
        switch self {
        case let .signedInteger(value) where value >= 0:
            return UInt64(value)
        case let .unsignedInteger(value):
            return value
        default:
            return nil
        }
    }

    public var finiteDoubleValue: Double? {
        let value: Double
        switch self {
        case let .signedInteger(integer):
            value = Double(integer)
        case let .unsignedInteger(integer):
            value = Double(integer)
        case let .double(double):
            value = double
        default:
            return nil
        }
        return value.isFinite ? value : nil
    }

    public func isSemanticallyEqual(to other: LosslessJSONValue) -> Bool {
        switch (self, other) {
        case (.null, .null):
            return true
        case let (.boolean(lhs), .boolean(rhs)):
            return lhs == rhs
        case let (.string(lhs), .string(rhs)):
            return lhs == rhs
        case let (.signedInteger(lhs), .signedInteger(rhs)):
            return lhs == rhs
        case let (.unsignedInteger(lhs), .unsignedInteger(rhs)):
            return lhs == rhs
        case let (.double(lhs), .double(rhs)):
            return lhs.bitPattern == rhs.bitPattern
        case let (.array(lhs), .array(rhs)):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { pair in
                pair.0.isSemanticallyEqual(to: pair.1)
            }
        case let (.object(lhs), .object(rhs)):
            return lhs.isSemanticallyEqual(to: rhs)
        default:
            return false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .null:
            self = .null
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .signedInteger:
            self = .signedInteger(try container.decode(Int64.self, forKey: .signedInteger))
        case .unsignedInteger:
            self = .unsignedInteger(try container.decode(UInt64.self, forKey: .unsignedInteger))
        case .double:
            let bitPattern = try container.decode(UInt64.self, forKey: .doubleBitPattern)
            self = .double(Double(bitPattern: bitPattern))
        case .array:
            self = .array(try container.decode([LosslessJSONValue].self, forKey: .array))
        case .object:
            self = .object(try container.decode(LosslessJSONObject.self, forKey: .object))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(Kind.null, forKey: .kind)
        case let .boolean(value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .boolean)
        case let .string(value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .string)
        case let .signedInteger(value):
            try container.encode(Kind.signedInteger, forKey: .kind)
            try container.encode(value, forKey: .signedInteger)
        case let .unsignedInteger(value):
            try container.encode(Kind.unsignedInteger, forKey: .kind)
            try container.encode(value, forKey: .unsignedInteger)
        case let .double(value):
            try container.encode(Kind.double, forKey: .kind)
            try container.encode(value.bitPattern, forKey: .doubleBitPattern)
        case let .array(value):
            try container.encode(Kind.array, forKey: .kind)
            try container.encode(value, forKey: .array)
        case let .object(value):
            try container.encode(Kind.object, forKey: .kind)
            try container.encode(value, forKey: .object)
        }
    }

    private enum Kind: String, Codable {
        case null
        case boolean
        case string
        case signedInteger
        case unsignedInteger
        case double
        case array
        case object
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case boolean
        case string
        case signedInteger
        case unsignedInteger
        case doubleBitPattern
        case array
        case object
    }
}

struct LosslessJSONParser {
    struct ParseError: Error, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case unexpectedEnd
            case trailingContent
            case duplicateObjectKey(String)
            case invalidSyntax
            case integerOutOfRange
            case nestingLimitExceeded
        }

        var kind: Kind
        var byteOffset: Int
        var detail: String
    }

    private let bytes: [UInt8]
    private var index = 0
    private static let maximumNestingDepth = 128

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func parse() throws -> LosslessJSONValue {
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else {
            throw error(.trailingContent, "1行に複数のJSON値または余分な文字があります。")
        }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> LosslessJSONValue {
        guard depth <= Self.maximumNestingDepth else {
            throw error(
                .nestingLimitExceeded,
                "JSONのnesting depthが上限\(Self.maximumNestingDepth)を超えています。"
            )
        }
        guard let byte = currentByte else {
            throw error(.unexpectedEnd, "JSON値の途中で入力が終了しました。")
        }
        switch byte {
        case 0x7B:
            return .object(try parseObject(childDepth: depth + 1))
        case 0x5B:
            return .array(try parseArray(childDepth: depth + 1))
        case 0x22:
            return .string(try parseString())
        case 0x74:
            try consumeLiteral("true")
            return .boolean(true)
        case 0x66:
            try consumeLiteral("false")
            return .boolean(false)
        case 0x6E:
            try consumeLiteral("null")
            return .null
        case 0x2D, 0x30...0x39:
            return try parseNumber()
        default:
            throw error(.invalidSyntax, "JSON値として解釈できない文字です。")
        }
    }

    private mutating func parseObject(childDepth: Int) throws -> LosslessJSONObject {
        index += 1
        skipWhitespace()
        if consumeIfPresent(0x7D) {
            return LosslessJSONObject()
        }

        var members: [LosslessJSONMember] = []
        var keys: Set<String> = []
        while true {
            guard currentByte == 0x22 else {
                throw currentByte == nil
                    ? error(.unexpectedEnd, "object keyの途中で入力が終了しました。")
                    : error(.invalidSyntax, "object keyは文字列である必要があります。")
            }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw error(.duplicateObjectKey(key), "object key \"\(key)\" が重複しています。")
            }
            skipWhitespace()
            guard consumeIfPresent(0x3A) else {
                throw currentByte == nil
                    ? error(.unexpectedEnd, "object keyの後で入力が終了しました。")
                    : error(.invalidSyntax, "object keyの後に':'が必要です。")
            }
            skipWhitespace()
            members.append(
                LosslessJSONMember(
                    key: key,
                    value: try parseValue(depth: childDepth)
                )
            )
            skipWhitespace()
            if consumeIfPresent(0x7D) {
                return LosslessJSONObject(members: members)
            }
            guard consumeIfPresent(0x2C) else {
                throw currentByte == nil
                    ? error(.unexpectedEnd, "objectの途中で入力が終了しました。")
                    : error(.invalidSyntax, "object memberの間に','が必要です。")
            }
            skipWhitespace()
        }
    }

    private mutating func parseArray(childDepth: Int) throws -> [LosslessJSONValue] {
        index += 1
        skipWhitespace()
        if consumeIfPresent(0x5D) {
            return []
        }

        var values: [LosslessJSONValue] = []
        while true {
            values.append(try parseValue(depth: childDepth))
            skipWhitespace()
            if consumeIfPresent(0x5D) {
                return values
            }
            guard consumeIfPresent(0x2C) else {
                throw currentByte == nil
                    ? error(.unexpectedEnd, "arrayの途中で入力が終了しました。")
                    : error(.invalidSyntax, "array要素の間に','が必要です。")
            }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        guard consumeIfPresent(0x22) else {
            throw error(.invalidSyntax, "文字列の開始記号がありません。")
        }
        var result: [UInt8] = []
        while let byte = currentByte {
            index += 1
            switch byte {
            case 0x22:
                guard let string = String(bytes: result, encoding: .utf8) else {
                    throw error(.invalidSyntax, "文字列に不正なUTF-8があります。")
                }
                return string
            case 0x5C:
                try appendEscape(to: &result)
            case 0x00...0x1F:
                throw error(.invalidSyntax, "文字列にescapeされていない制御文字があります。")
            default:
                result.append(byte)
            }
        }
        throw error(.unexpectedEnd, "文字列の途中で入力が終了しました。")
    }

    private mutating func appendEscape(to result: inout [UInt8]) throws {
        guard let escaped = currentByte else {
            throw error(.unexpectedEnd, "escape sequenceの途中で入力が終了しました。")
        }
        index += 1
        switch escaped {
        case 0x22, 0x5C, 0x2F:
            result.append(escaped)
        case 0x62:
            result.append(0x08)
        case 0x66:
            result.append(0x0C)
        case 0x6E:
            result.append(0x0A)
        case 0x72:
            result.append(0x0D)
        case 0x74:
            result.append(0x09)
        case 0x75:
            let first = try parseUnicodeEscapeValue()
            let scalarValue: UInt32
            if (0xD800...0xDBFF).contains(first) {
                guard consumeIfPresent(0x5C), consumeIfPresent(0x75) else {
                    throw error(.invalidSyntax, "high surrogateの後にlow surrogateがありません。")
                }
                let second = try parseUnicodeEscapeValue()
                guard (0xDC00...0xDFFF).contains(second) else {
                    throw error(.invalidSyntax, "low surrogateが不正です。")
                }
                scalarValue = 0x10000
                    + (UInt32(first - 0xD800) << 10)
                    + UInt32(second - 0xDC00)
            } else {
                guard !(0xDC00...0xDFFF).contains(first) else {
                    throw error(.invalidSyntax, "low surrogateが単独で現れています。")
                }
                scalarValue = UInt32(first)
            }
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw error(.invalidSyntax, "Unicode scalarが不正です。")
            }
            result.append(contentsOf: String(scalar).utf8)
        default:
            throw error(.invalidSyntax, "未定義のescape sequenceです。")
        }
    }

    private mutating func parseUnicodeEscapeValue() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte else {
                throw error(.unexpectedEnd, "Unicode escapeの途中で入力が終了しました。")
            }
            guard let nibble = hexNibble(byte) else {
                throw error(.invalidSyntax, "Unicode escapeに16進数以外があります。")
            }
            value = (value << 4) | UInt16(nibble)
            index += 1
        }
        return value
    }

    private mutating func parseNumber() throws -> LosslessJSONValue {
        let start = index
        _ = consumeIfPresent(0x2D)
        guard let firstDigit = currentByte else {
            throw error(.unexpectedEnd, "numberの途中で入力が終了しました。")
        }
        if firstDigit == 0x30 {
            index += 1
            if let next = currentByte, isDigit(next) {
                throw error(.invalidSyntax, "numberの整数部に不要な先頭0があります。")
            }
        } else if (0x31...0x39).contains(firstDigit) {
            consumeDigits()
        } else {
            throw error(.invalidSyntax, "numberの整数部が不正です。")
        }

        var isFloatingPoint = false
        if consumeIfPresent(0x2E) {
            isFloatingPoint = true
            guard let byte = currentByte, isDigit(byte) else {
                throw currentByte == nil
                    ? error(.unexpectedEnd, "numberの小数部の途中で入力が終了しました。")
                    : error(.invalidSyntax, "小数点の後に数字が必要です。")
            }
            consumeDigits()
        }
        if currentByte == 0x65 || currentByte == 0x45 {
            isFloatingPoint = true
            index += 1
            if currentByte == 0x2B || currentByte == 0x2D {
                index += 1
            }
            guard let byte = currentByte, isDigit(byte) else {
                throw currentByte == nil
                    ? error(.unexpectedEnd, "numberの指数部の途中で入力が終了しました。")
                    : error(.invalidSyntax, "指数部に数字が必要です。")
            }
            consumeDigits()
        }

        let token = String(decoding: bytes[start..<index], as: UTF8.self)
        if isFloatingPoint {
            guard let value = Double(token), value.isFinite else {
                throw error(.invalidSyntax, "numberを有限のDoubleとして保持できません。")
            }
            return .double(value)
        }
        if token == "-0" {
            return .double(-0.0)
        }
        if token.first == "-" {
            guard let value = Int64(token) else {
                throw error(.integerOutOfRange, "負の整数がInt64の範囲外です。")
            }
            return .signedInteger(value)
        }
        if let value = Int64(token) {
            return .signedInteger(value)
        }
        guard let value = UInt64(token) else {
            throw error(.integerOutOfRange, "正の整数がUInt64の範囲外です。")
        }
        return .unsignedInteger(value)
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = Array("\(literal)".utf8)
        for expected in literalBytes {
            guard let byte = currentByte else {
                throw error(.unexpectedEnd, "literalの途中で入力が終了しました。")
            }
            guard byte == expected else {
                throw error(.invalidSyntax, "literalが不正です。")
            }
            index += 1
        }
    }

    private mutating func consumeDigits() {
        while let byte = currentByte, isDigit(byte) {
            index += 1
        }
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard currentByte == byte else {
            return false
        }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }

    private func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            return byte - 0x30
        case 0x41...0x46:
            return byte - 0x41 + 10
        case 0x61...0x66:
            return byte - 0x61 + 10
        default:
            return nil
        }
    }

    private func error(_ kind: ParseError.Kind, _ detail: String) -> ParseError {
        ParseError(kind: kind, byteOffset: index, detail: detail)
    }
}
