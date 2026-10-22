import Foundation

/// Loads and saves AppConfig as JSON in ~/Library/Application Support/KeyBindingApp/config.json.
enum ConfigStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeyBindingApp", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data).sanitized()
        } catch {
            NSLog("KeyBindingApp: cannot read config, starting empty: \(error)")
            // Keep the unreadable file instead of overwriting it silently.
            let backup = directory.appendingPathComponent("config.broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return AppConfig()
        }
    }

    static func save(_ config: AppConfig) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encode(config).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("KeyBindingApp: cannot save config: \(error)")
        }
    }

    static func encode(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }
}
