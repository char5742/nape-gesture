import Foundation
import NapeGestureCore

enum InputLogFileReader {
    static func readRecords(path: String) throws -> [InputLogRecord] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = JSONDecoder()
        var records: [InputLogRecord] = []

        for (index, line) in text.split(separator: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            guard let data = trimmed.data(using: .utf8) else {
                throw ToolError.invalidValue("ログ \(index + 1) 行目", String(trimmed))
            }

            do {
                records.append(try decoder.decode(InputLogRecord.self, from: data))
            } catch {
                throw ToolError.invalidValue("ログ \(index + 1) 行目", error.localizedDescription)
            }
        }

        return records
    }
}
