import Foundation

/// Loads and saves AppConfig as JSON in ~/Library/Application Support/Shift Happens/config.json.
enum ConfigStore {
    private static var base: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }

    static var directory: URL { base.appendingPathComponent("Shift Happens", isDirectory: true) }

    /// Where versions before the rename kept their settings.
    static var oldDirectory: URL { base.appendingPathComponent("KeyBindingApp", isDirectory: true) }

    /// Moves settings from the old folder to the new one, once, if only the old one exists.
    static func migrateIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.path), fm.fileExists(atPath: oldDirectory.path) else { return }
        do {
            try fm.moveItem(at: oldDirectory, to: directory)
        } catch {
            NSLog("Shift Happens: cannot move settings from \(oldDirectory.path): \(error)")
        }
    }

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> AppConfig {
        migrateIfNeeded()
        guard let data = try? Data(contentsOf: fileURL) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data).sanitized()
        } catch {
            NSLog("Shift Happens: cannot read config, starting empty: \(error)")
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
            NSLog("Shift Happens: cannot save config: \(error)")
        }
    }

    static func encode(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }
}
