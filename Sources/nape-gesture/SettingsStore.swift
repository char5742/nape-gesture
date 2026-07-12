import Foundation
import NapeGestureCore

enum SettingsStore {
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
        if FileManager.default.fileExists(atPath: path) {
            let data = try Data(contentsOf: url)
            let settings = try decoder.decode(NapeGestureSettings.self, from: data)
            if try SettingsMigration.containsDeprecatedGestureKeys(in: data) {
                try write(settings, to: path)
            }
            return settings
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeTemplate(to: path)
        return .template
    }

    static func writeTemplate(to path: String) throws {
        try write(NapeGestureSettings.template, to: path)
    }

    static func write(_ settings: NapeGestureSettings, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
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
}
