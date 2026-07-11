import Foundation

public struct TrackpadOutputProvenanceDocument: Equatable, Sendable {
    public var line: Int
    public var rawLineData: Data
    public var rawObject: LosslessJSONObject
    public var record: TrackpadOutputProvenanceRecord

    public init(
        line: Int,
        rawLineData: Data,
        rawObject: LosslessJSONObject,
        record: TrackpadOutputProvenanceRecord
    ) {
        self.line = line
        self.rawLineData = rawLineData
        self.rawObject = rawObject
        self.record = record
    }
}

public enum TrackpadOutputProvenanceDocumentError: LocalizedError, Equatable, Sendable {
    case emptyInput
    case invalidUTF8
    case unterminatedLastRecord
    case emptyRecord(line: Int)
    case malformedRecord(line: Int, details: String)
    case typedDecodeFailed(line: Int, details: String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "provenance JSON Linesが空です。"
        case .invalidUTF8:
            return "provenance JSON Linesが有効なUTF-8ではありません。"
        case .unterminatedLastRecord:
            return "provenance JSON Linesの最終recordがLFで終端されていません。"
        case let .emptyRecord(line):
            return "provenance JSON Linesに空recordがあります。line=\(line)"
        case let .malformedRecord(line, details):
            return "provenance JSON recordが不正です。line=\(line) details=\(details)"
        case let .typedDecodeFailed(line, details):
            return "provenance JSON recordを現行schemaとしてdecodeできません。line=\(line) details=\(details)"
        }
    }
}

public enum TrackpadOutputProvenanceDocumentReader {
    public static func read(data: Data) throws -> [TrackpadOutputProvenanceDocument] {
        guard !data.isEmpty else {
            throw TrackpadOutputProvenanceDocumentError.emptyInput
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw TrackpadOutputProvenanceDocumentError.invalidUTF8
        }
        guard data.last == 0x0A else {
            throw TrackpadOutputProvenanceDocumentError.unterminatedLastRecord
        }

        let decoder = JSONDecoder()
        var documents: [TrackpadOutputProvenanceDocument] = []
        var lineStart = data.startIndex
        var line = 0
        for newlineIndex in data.indices where data[newlineIndex] == 0x0A {
            line += 1
            guard lineStart != newlineIndex else {
                throw TrackpadOutputProvenanceDocumentError.emptyRecord(line: line)
            }

            let lineData = data.subdata(in: lineStart..<newlineIndex)
            let rawObject: LosslessJSONObject
            do {
                rawObject = try StrictJSONDocumentParser.parseObject(data: lineData)
            } catch {
                throw TrackpadOutputProvenanceDocumentError.malformedRecord(
                    line: line,
                    details: error.localizedDescription
                )
            }

            let record: TrackpadOutputProvenanceRecord
            do {
                record = try decoder.decode(TrackpadOutputProvenanceRecord.self, from: lineData)
            } catch {
                throw TrackpadOutputProvenanceDocumentError.typedDecodeFailed(
                    line: line,
                    details: error.localizedDescription
                )
            }
            documents.append(
                TrackpadOutputProvenanceDocument(
                    line: line,
                    rawLineData: lineData,
                    rawObject: rawObject,
                    record: record
                )
            )
            lineStart = data.index(after: newlineIndex)
        }
        return documents
    }
}
