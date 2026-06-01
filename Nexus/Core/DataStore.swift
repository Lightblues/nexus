import Foundation

/// Generic codable JSON store with debounced atomic writes.
/// Mirrors the role of electron-store + DataManager.ts but per-feature-typed.
actor DataStore<T: Codable & Sendable> {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pending: T?
    private var flushTask: Task<Void, Never>?
    private let debounce: Duration

    init(url: URL, debounce: Duration = .milliseconds(200)) {
        self.url = url
        self.debounce = debounce
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            // Accept both ISO8601 and ISO8601-with-fractional-seconds (electron-log emits the latter).
            let str = try decoder.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: str) { return d }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let d = f2.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                debugDescription: "Cannot parse date: \(str)")
        }
        self.decoder = dec
    }

    func load() throws -> T? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }
        return try decoder.decode(T.self, from: data)
    }

    /// Buffer a write; the actual fs write happens after `debounce`.
    func write(_ value: T) {
        pending = value
        flushTask?.cancel()
        let task = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
            await self.flush()
        }
        flushTask = task
    }

    /// Force immediate flush (e.g. on app shutdown).
    func flushNow() async { await flush() }

    private func flush() async {
        guard let value = pending else { return }
        pending = nil
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let tmp = url.appendingPathExtension("tmp")
            let data = try encoder.encode(value)
            try data.write(to: tmp, options: .atomic)
            // Atomic replace
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            Log.app.error("DataStore flush failed for \(self.url.lastPathComponent): \(error)")
        }
    }
}
