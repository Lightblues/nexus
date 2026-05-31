import SwiftUI
import Charts

struct TrackerView: View {
    @EnvironmentObject var repo: TrackerRepository
    @EnvironmentObject var service: TrackerService

    @State private var selectedDate: Date = Date()
    @State private var records: [WindowActivityRecord] = []
    @State private var summary: [String: TimeInterval] = [:]
    @State private var totalSeconds: TimeInterval = 0

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    statusBanner
                    timelineSection
                    Divider()
                    HStack(alignment: .top, spacing: 24) {
                        AppUsageDonut(summary: summary)
                            .frame(width: 280, height: 280)
                        AppRankList(records: records, summary: summary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
        }
        .task(id: dateKey(selectedDate)) { await loadSelectedDay() }
        .onReceive(repo.$todayRecords) { fresh in
            if isViewingToday { records = fresh }
        }
        .onReceive(repo.$todaySummary) { fresh in
            if isViewingToday {
                summary = fresh
                totalSeconds = fresh.values.reduce(0, +)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
            Spacer()
            statusPill
            Text(formatTotal(totalSeconds))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch service.status {
            case .stopped: return ("Off", .secondary)
            case .running: return ("Tracking", .green)
            case .idle: return ("Idle", .orange)
            case .waitingForPermission: return ("Needs Accessibility", .red)
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quinary, in: Capsule())
    }

    @ViewBuilder
    private var statusBanner: some View {
        if service.status == .waitingForPermission {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission required")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Tracker reads the active window title to attribute time. Grant access in System Settings → Privacy & Security → Accessibility.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Open Settings") { Permissions.openAccessibilitySettings() }
            }
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TrackerTimeline(records: records, day: selectedDate)
                .frame(height: 60)
        }
    }

    // MARK: - Data load

    private var isViewingToday: Bool {
        dateKey(selectedDate) == dateKey(Date())
    }

    private func dateKey(_ d: Date) -> String { Self.dateFormatter.string(from: d) }

    private func loadSelectedDay() async {
        records = await repo.records(on: selectedDate)
        summary = await repo.appSummary(on: selectedDate)
        totalSeconds = await repo.totalActiveTime(on: selectedDate)
    }

    private func formatTotal(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 { return "\(mins)m total" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h total" : "\(h)h \(m)m total"
    }
}
