import Foundation

/// Persistence for Pomodoro sessions.
/// - Active sessions live in ~/.ea/nexus/data.json (Codable, debounced writes)
/// - Sessions older than 90 days move to ~/.ea/nexus/archive/pomodoro-{YYYY}.json on launch
/// - getAllSessions() merges active + archived for the activity calendar
@MainActor
final class PomodoroStore: ObservableObject {
    @Published private(set) var data: PomodoroData = .init()

    private let store = DataStore<PomodoroData>(url: Paths.dataFile)
    private let archiveStore: (Int) -> DataStore<[SessionRecord]> = { year in
        DataStore<[SessionRecord]>(url: Paths.archiveFile(year: year))
    }

    private static let archiveDays: TimeInterval = 90 * 86_400

    func load() async {
        do {
            if let loaded = try await store.load() {
                self.data = loaded
            }
        } catch {
            Log.pomodoro.error("Failed loading data.json: \(error). Starting empty.")
        }
    }

    /// Move sessions older than 90 days into per-year archive files. ADR-004.
    func runArchiveSweep() async {
        let cutoff = Date(timeIntervalSinceNow: -Self.archiveDays)
        let (toArchive, toKeep) = data.sessions.partition { $0.endTime < cutoff }
        guard !toArchive.isEmpty else { return }

        // Group by year
        var grouped: [Int: [SessionRecord]] = [:]
        let calendar = Calendar(identifier: .gregorian)
        for s in toArchive {
            let y = calendar.component(.year, from: s.startTime)
            grouped[y, default: []].append(s)
        }
        for (year, sessions) in grouped {
            let archive = archiveStore(year)
            var existing = (try? await archive.load()) ?? []
            let existingIds = Set(existing.map(\.id))
            let merged = existing + sessions.filter { !existingIds.contains($0.id) }
            await archive.write(merged)
            await archive.flushNow()
            existing.removeAll()  // free
        }
        data.sessions = toKeep
        await store.write(data)
        Log.pomodoro.info("Archived \(toArchive.count) sessions across \(grouped.count) year(s)")
    }

    func append(_ record: SessionRecord) async {
        data.sessions.append(record)
        await store.write(data)
    }

    func update(_ record: SessionRecord) async {
        guard let idx = data.sessions.firstIndex(where: { $0.id == record.id }) else { return }
        data.sessions[idx] = record
        await store.write(data)
    }

    func updateMeta(_ transform: (inout PomodoroMeta) -> Void) async {
        transform(&data.meta)
        await store.write(data)
    }

    /// Sessions for a single calendar day (active store only — fast path for daily UI).
    func sessions(on day: Date) -> [SessionRecord] {
        let cal = Calendar(identifier: .gregorian)
        return data.sessions.filter { cal.isDate($0.startTime, inSameDayAs: day) }
    }

    /// Active + archived merged. Used by the activity calendar.
    func allSessions() async -> [SessionRecord] {
        var all = data.sessions
        let years = Set(all.map { Calendar.current.component(.year, from: $0.startTime) })
        // Pull in archive files for the past N years (we just check the directory).
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: Paths.archiveDir,
                includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("pomodoro-") {
                let yearString = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "pomodoro-", with: "")
                guard let year = Int(yearString), !years.contains(year) else { continue }
                let archive = archiveStore(year)
                if let arr = try? await archive.load() {
                    all.append(contentsOf: arr)
                }
            }
        } catch {
            // Archive dir doesn't exist yet; harmless on fresh install.
        }
        return all.sorted { $0.startTime < $1.startTime }
    }

    /// Force flush to disk. Call from applicationWillTerminate.
    func flushNow() async {
        await store.flushNow()
    }
}

// MARK: - Helpers

private extension Array {
    /// Splits into (matching, remaining) preserving order.
    func partition(_ pred: (Element) -> Bool) -> (matching: [Element], remaining: [Element]) {
        var m: [Element] = []
        var r: [Element] = []
        for e in self {
            if pred(e) { m.append(e) } else { r.append(e) }
        }
        return (m, r)
    }
}
