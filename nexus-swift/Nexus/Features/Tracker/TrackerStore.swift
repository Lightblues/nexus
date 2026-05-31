import Foundation

/// Per-day file storage for tracker records. Mirrors `TrackerDataManager.ts`.
/// Buffer in memory; flush periodically + on shutdown.
@MainActor
final class TrackerStore: ObservableObject {
    @Published private(set) var today: DailyTrackerData

    /// In-memory buffer of records not yet written to disk.
    private var buffer: [WindowActivityRecord] = []
    private var currentDateString: String

    /// Cache of loaded daily data (read by UI for date pickers).
    private var dailyCache: [String: DailyTrackerData] = [:]

    private static let maxBufferSize = 100

    init() {
        let today = TrackerStore.todayString()
        self.currentDateString = today
        self.today = DailyTrackerData(date: today)
    }

    // MARK: - Public

    func bootstrap() async {
        currentDateString = Self.todayString()
        if let loaded = await loadDaily(date: currentDateString) {
            today = loaded
            dailyCache[currentDateString] = loaded
        }
    }

    /// Add a fresh record. If the day rolled over, flush old buffer first.
    func addRecord(_ record: WindowActivityRecord) async {
        let recordDate = Self.dateString(record.startTime)
        if recordDate != currentDateString {
            await flush()
            currentDateString = recordDate
        }
        buffer.append(record)
        if buffer.count >= Self.maxBufferSize {
            await flush()
        }
    }

    /// Update the most recent buffered record's endTime. Used by merge.
    /// Returns true if the buffer had a record to update.
    @discardableResult
    func extendLastRecord(to endTime: Date) -> Bool {
        guard !buffer.isEmpty else { return false }
        var last = buffer[buffer.count - 1]
        last.endTime = endTime
        last.duration = endTime.timeIntervalSince(last.startTime)
        buffer[buffer.count - 1] = last
        return true
    }

    /// Peek the last buffered record without modifying it.
    var lastRecord: WindowActivityRecord? { buffer.last }

    /// Flush buffer to disk, grouped by date. Updates the published `today` snapshot.
    func flush() async {
        guard !buffer.isEmpty else { return }

        // Group by start-date string
        var byDate: [String: [WindowActivityRecord]] = [:]
        for r in buffer {
            byDate[Self.dateString(r.startTime), default: []].append(r)
        }
        buffer.removeAll(keepingCapacity: true)

        for (date, records) in byDate {
            var daily = await loadDaily(date: date) ?? DailyTrackerData(date: date)
            daily.records.append(contentsOf: records)
            recomputeMeta(&daily)
            await write(daily)
            dailyCache[date] = daily
            if date == currentDateString {
                today = daily
            }
        }
    }

    /// Read a day's data on demand (for the UI date picker).
    func dailyData(for date: String) async -> DailyTrackerData? {
        if let cached = dailyCache[date] { return cached }
        if let loaded = await loadDaily(date: date) {
            dailyCache[date] = loaded
            return loaded
        }
        return nil
    }

    // MARK: - Internals

    /// One DataStore per date. Cheap to construct; we don't keep them long-lived
    /// because each writes to a different URL.
    private func storeFor(date: String) -> DataStore<DailyTrackerData> {
        DataStore<DailyTrackerData>(url: Paths.trackerFile(date: date))
    }

    private func loadDaily(date: String) async -> DailyTrackerData? {
        let store = storeFor(date: date)
        do {
            return try await store.load()
        } catch {
            Log.tracker.warn("Failed loading tracker file for \(date): \(error)")
            return nil
        }
    }

    private func write(_ daily: DailyTrackerData) async {
        let store = storeFor(date: daily.date)
        await store.write(daily)
        await store.flushNow()  // tracker files are small + already debounced via flush() cadence
    }

    private func recomputeMeta(_ daily: inout DailyTrackerData) {
        var total: TimeInterval = 0
        var summary: [String: TimeInterval] = [:]
        for r in daily.records {
            total += r.duration
            summary[r.app, default: 0] += r.duration
        }
        daily.meta = TrackerDayMeta(totalActiveTime: total, appSummary: summary)
    }

    // MARK: - Date helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func todayString() -> String { dateString(Date()) }
    static func dateString(_ date: Date) -> String { dateFormatter.string(from: date) }
}
