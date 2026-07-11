import Foundation

public enum StrictJSONDocumentError: LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case invalidJSON(byteOffset: Int, details: String)
    case topLevelValueIsNotObject

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "JSON documentが有効なUTF-8ではありません。"
        case let .invalidJSON(byteOffset, details):
            return "JSON documentが不正です。byteOffset=\(byteOffset) details=\(details)"
        case .topLevelValueIsNotObject:
            return "JSON documentのtop-level値はobjectである必要があります。"
        }
    }
}

public enum StrictJSONDocumentParser {
    public static func parseObject(data: Data) throws -> LosslessJSONObject {
        guard String(data: data, encoding: .utf8) != nil else {
            throw StrictJSONDocumentError.invalidUTF8
        }

        var parser = LosslessJSONParser(data: data)
        let value: LosslessJSONValue
        do {
            value = try parser.parse()
        } catch let error as LosslessJSONParser.ParseError {
            throw StrictJSONDocumentError.invalidJSON(
                byteOffset: error.byteOffset,
                details: error.detail
            )
        } catch {
            throw StrictJSONDocumentError.invalidJSON(
                byteOffset: 0,
                details: error.localizedDescription
            )
        }

        guard let object = value.objectValue else {
            throw StrictJSONDocumentError.topLevelValueIsNotObject
        }
        return object
    }
}
