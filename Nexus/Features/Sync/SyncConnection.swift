import Foundation
import NexusSync

/// This Mac's sync connection, kept in `sync.json` (mode 0600) next to `config.json`
/// but outside it, so syncing settings never overwrites another Mac's connection.
struct SyncConnection: Codable, Equatable {
    static let defaultServer = "https://nexus.easonsi.site"

    var enabled = false
    var server = defaultServer
    var key = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        server = (try? c.decode(String.self, forKey: .server)) ?? Self.defaultServer
        key = (try? c.decode(String.self, forKey: .key)) ?? ""
    }

    /// The server URL without a trailing slash, or nil when it is not an http(s) URL.
    var serverURL: URL? {
        var s = server.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { return nil }
        return url
    }

    /// Ready to sync: switched on, with a key and a valid server.
    var isActive: Bool { enabled && !key.isEmpty && serverURL != nil }

    static func load() -> SyncConnection {
        guard let data = try? Data(contentsOf: Paths.syncFile) else { return SyncConnection() }
        do { return try JSONDecoder().decode(SyncConnection.self, from: data) } catch {
            Log.sync.error("sync.json unreadable, sync stays off: \(error)")
            return SyncConnection()
        }
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = Paths.syncFile
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// `SettingsStore` over `ConfigService`: the whole `AppConfig` as one JSON object.
struct ConfigSettingsStore: SettingsStore {
    let config: ConfigService

    func load() async throws -> [String: JSONValue] {
        let current = await MainActor.run { config.config }
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(current))
        guard case .object(let object) = value else { return [:] }
        return object
    }

    func save(_ settings: [String: JSONValue]) async throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(JSONValue.object(settings)))
        await MainActor.run { config.save(decoded) }
    }
}
