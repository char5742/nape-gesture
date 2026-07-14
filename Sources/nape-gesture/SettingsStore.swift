import Darwin
import Foundation
import NapeGestureCore

enum SettingsStore {
    private static let processLock = NSLock()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func load(from options: [String]) throws -> NapeGestureSettings {
        guard options.contains("--config") else {
            return .default
        }
        let path = try requiredValue(for: "--config", in: options)
        return try load(fromPath: path)
    }

    static func loadRuntimeSettings(from options: [String], validate: Bool = true) throws -> (settings: NapeGestureSettings, path: String) {
        let path = try configPath(from: options)
        let settings = try loadOrCreateDefault(at: path)
        if validate {
            try validateSettings(settings)
        }
        return (settings, path)
    }

    static func configPath(from options: [String]) throws -> String {
        if options.contains("--config") {
            return try requiredValue(for: "--config", in: options)
        }
        return defaultConfigPath()
    }

    static func load(fromPath path: String) throws -> NapeGestureSettings {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(NapeGestureSettings.self, from: data)
    }

    static func loadOrCreateDefault(at path: String) throws -> NapeGestureSettings {
        let url = URL(fileURLWithPath: path)
        return try withExclusiveLock(for: url) {
            if FileManager.default.fileExists(atPath: path) {
                let data = try Data(contentsOf: url)
                let settings = try decoder.decode(NapeGestureSettings.self, from: data)
                guard try SettingsMigration.requiresCanonicalRewrite(in: data) else {
                    return settings
                }

                try validateMigrationSettings(settings)
                let canonicalData = try encoder.encode(settings)
                let canonicalSettings = try decoder.decode(
                    NapeGestureSettings.self,
                    from: canonicalData
                )
                try validateSettings(canonicalSettings)
                guard try !SettingsMigration.requiresCanonicalRewrite(in: canonicalData) else {
                    throw ToolError.invalidSettings([
                        SettingsValidationIssue(
                            path: "settings",
                            message: "canonical設定に廃止済み項目が残っています。"
                        )
                    ])
                }
                try write(canonicalData, to: url)
                return canonicalSettings
            }
            let settings = NapeGestureSettings.template
            try validateSettings(settings)
            try write(encoder.encode(settings), to: url)
            return settings
        }
    }

    static func writeTemplate(to path: String) throws {
        try write(NapeGestureSettings.template, to: path)
    }

    static func write(_ settings: NapeGestureSettings, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try withExclusiveLock(for: url) {
            try validateSettings(settings)
            let data = try encoder.encode(settings)
            try write(data, to: url)
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func withExclusiveLock<T>(
        for url: URL,
        _ body: () throws -> T
    ) throws -> T {
        processLock.lock()
        defer { processLock.unlock() }

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let lockURL = URL(fileURLWithPath: url.path + ".lock")
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw posixError(operation: "設定lock fileを開けません", path: lockURL.path)
        }
        var fileLock = Darwin.flock()
        fileLock.l_type = Int16(F_WRLCK)
        fileLock.l_whence = Int16(SEEK_SET)
        var lockResult: Int32
        repeat {
            lockResult = Darwin.fcntl(descriptor, F_SETLKW, &fileLock)
        } while lockResult == -1 && errno == EINTR
        guard lockResult == 0 else {
            let error = posixError(operation: "設定lockを取得できません", path: lockURL.path)
            Darwin.close(descriptor)
            throw error
        }
        defer {
            fileLock.l_type = Int16(F_UNLCK)
            _ = Darwin.fcntl(descriptor, F_SETLK, &fileLock)
            _ = Darwin.close(descriptor)
        }
        return try body()
    }

    private static func posixError(operation: String, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [
                NSLocalizedDescriptionKey: "\(operation): \(path)"
            ]
        )
    }

    static func defaultConfigPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("NapeGesture", isDirectory: true)
            .appendingPathComponent("config.json")
            .path
    }

    static func templateString() throws -> String {
        try string(for: NapeGestureSettings.template)
    }

    static func string(for settings: NapeGestureSettings) throws -> String {
        let data = try encoder.encode(settings)
        return String(decoding: data, as: UTF8.self)
    }

    static func value(for name: String, in options: [String]) -> String? {
        guard let index = options.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = options.index(after: index)
        guard valueIndex < options.endIndex else {
            return nil
        }
        return options[valueIndex]
    }

    static func requiredValue(for name: String, in options: [String]) throws -> String {
        guard let value = value(for: name, in: options) else {
            throw ToolError.missingValue(name)
        }
        return value
    }

    static func validateSettings(_ settings: NapeGestureSettings) throws {
        let issues = SettingsValidator.issues(for: settings)
        guard issues.isEmpty else {
            throw ToolError.invalidSettings(issues)
        }
    }

    private static func validateMigrationSettings(
        _ settings: NapeGestureSettings
    ) throws {
        let issues = SettingsValidator.migrationIssues(for: settings)
        guard issues.isEmpty else {
            throw ToolError.invalidSettings(issues)
        }
    }
}
