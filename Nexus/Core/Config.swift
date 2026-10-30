import Foundation
import GRDB
import NexusSync

/// Settings in the `settings` table of nexus.db, one row per leaf (`pomodoro.workDuration` → JSON),
/// the same keys sync uses. Edited in Settings, by sync, or by the `nexus` CLI through the server;
/// there is no config file to hand-edit.
@MainActor
final class ConfigService: ObservableObject {
    @Published private(set) var config: AppConfig = AppConfig()

    private let database: Database
    /// `config.json` from before settings lived in the database; imported once, then renamed.
    private let legacyFile: URL

    init(database: Database, legacyFile: URL = Paths.legacyConfigFile) {
        self.database = database
        self.legacyFile = legacyFile
    }

    /// Load on launch. Idempotent.
    func bootstrap() {
        do {
            var leaves = try database.queue.read { try Self.readLeaves($0) }
            if leaves.isEmpty, let imported = importLegacyFile() {
                leaves = try Self.leaves(of: imported)
                try write(leaves, over: [:])
            }
            let loaded = try Self.config(from: leaves)
            config = loaded.upgraded()
            if config != loaded { save(config, force: true) }
            Log.config.info("Config loaded (\(leaves.count) keys)")
        } catch {
            Log.config.error("Config load failed: \(error). Using defaults.")
        }
    }

    /// Persist a new config: only the leaves that changed are written.
    func save(_ newValue: AppConfig) { save(newValue, force: false) }

    private func save(_ newValue: AppConfig, force: Bool) {
        let newValue = newValue.upgraded()
        guard force || newValue != config else { return }
        do {
            let old = try database.queue.read { try Self.readLeaves($0) }
            try write(try Self.leaves(of: newValue), over: old)
            config = newValue
            Log.config.info("Config saved")
        } catch {
            Log.config.error("Config save failed: \(error)")
        }
    }

    // MARK: - Internals

    private func write(_ leaves: [String: JSONValue], over old: [String: JSONValue]) throws {
        let rows = try leaves.filter { old[$0.key] != $0.value }.map { ($0.key, try Self.text($0.value)) }
        let removed = old.keys.filter { leaves[$0] == nil }
        guard !rows.isEmpty || !removed.isEmpty else { return }
        try database.queue.write { db in
            for (key, value) in rows {
                try db.execute(sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", arguments: [key, value])
            }
            for key in removed { try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [key]) }
        }
    }

    /// Reads the pre-database `config.json` (tolerant per field) and renames it, so it is imported once.
    private func importLegacyFile() -> AppConfig? {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: legacyFile) else { return nil }
        let imported = (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
        let moved = legacyFile.deletingLastPathComponent().appendingPathComponent("config.json.imported")
        try? fm.removeItem(at: moved)
        do { try fm.moveItem(at: legacyFile, to: moved) } catch { Log.config.warn("Could not rename \(legacyFile.path): \(error)") }
        Log.config.info("Imported config.json into the database")
        return imported
    }

    nonisolated static func readLeaves(_ db: GRDB.Database) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT key, value FROM settings") {
            let text: String = row["value"]
            out[row["key"]] = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        }
        return out
    }

    nonisolated static func leaves(of config: AppConfig) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(config))
        guard case .object(let object) = value else { return [:] }
        return Settings.flatten(object)
    }

    /// Missing or mistyped leaves take their defaults (`AppConfig`'s tolerant decoding).
    nonisolated static func config(from leaves: [String: JSONValue]) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(JSONValue.object(Settings.unflatten(leaves))))
    }

    private nonisolated static func text(_ value: JSONValue) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
