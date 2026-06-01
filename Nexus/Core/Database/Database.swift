import Foundation
import GRDB

/// SQLite-backed storage for Pomodoro + Tracker data.
/// Single shared `DatabaseQueue` lives at
/// `~/Library/Application Support/site.easonsi.nexus/nexus.db` (WAL mode).
/// All repositories take this as their dependency.
final class Database: @unchecked Sendable {
    let queue: DatabaseQueue

    init(url: URL) throws {
        var config = Configuration()
        // WAL mode = concurrent reads while writes happen, single-writer.
        // Tracker writes every 5s, Stats reads on demand — they don't conflict.
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try Migrator.migrator.migrate(queue)
        self.queue = queue
    }

    /// Async read helper. Use this from `@MainActor` services to avoid blocking UI.
    func read<T: Sendable>(_ block: @escaping @Sendable (GRDB.Database) throws -> T) async throws -> T {
        try await queue.read(block)
    }

    /// Async write helper.
    func write<T: Sendable>(_ block: @escaping @Sendable (GRDB.Database) throws -> T) async throws -> T {
        try await queue.write(block)
    }
}
