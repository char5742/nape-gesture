import Foundation
import NapeGestureCore

protocol RuntimePerformanceRecording: AnyObject {
    func record(_ record: RuntimePerformanceRecord)
}

final class RuntimePerformanceLogWriter: RuntimePerformanceRecording {
    static let environmentKey = "NAPE_RUNTIME_PERFORMANCE_LOG"

    private let path: String
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    private let lock = NSLock()

    private init(path: String, fileHandle: FileHandle) {
        self.path = path
        self.fileHandle = fileHandle
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    deinit {
        try? fileHandle.close()
    }

    static func make(path explicitPath: String?) throws -> RuntimePerformanceLogWriter? {
        let rawPath = explicitPath ?? ProcessInfo.processInfo.environment[environmentKey]
        guard let rawPath, !rawPath.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: rawPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        return RuntimePerformanceLogWriter(path: rawPath, fileHandle: handle)
    }

    func record(_ record: RuntimePerformanceRecord) {
        lock.lock()
        defer {
            lock.unlock()
        }

        do {
            let data = try encoder.encode(record)
            fileHandle.write(data)
            fileHandle.write(Data([0x0A]))
        } catch {
            fputs("runtime performance log を書き込めません: \(path): \(error.localizedDescription)\n", stderr)
        }
    }
}
