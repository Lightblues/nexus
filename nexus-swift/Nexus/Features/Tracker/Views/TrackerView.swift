import SwiftUI
import Charts

struct TrackerView: View {
    @EnvironmentObject var store: TrackerStore
    @EnvironmentObject var service: TrackerService

    @State private var selectedDate: Date = Date()
    @State private var data: DailyTrackerData = DailyTrackerData(date: TrackerStore.todayString())
    @State private var isLoading = false

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
                        AppUsageDonut(summary: data.meta.appSummary)
                            .frame(width: 280, height: 280)
                        AppRankList(records: data.records, summary: data.meta.appSummary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
        }
        .task(id: TrackerStore.dateString(selectedDate)) { await loadSelectedDay() }
        .onReceive(store.$today) { freshToday in
            // If user is viewing today, update live as new records flush.
            if isViewingToday { data = freshToday }
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
            Text(formatTotal(data.meta.totalActiveTime))
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

    // MARK: - Status banner

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

    // MARK: - Timeline + sections

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TrackerTimeline(records: data.records, day: selectedDate)
                .frame(height: 60)
        }
    }

    // MARK: - Data load

    private var isViewingToday: Bool {
        TrackerStore.dateString(selectedDate) == TrackerStore.todayString()
    }

    private func loadSelectedDay() async {
        isLoading = true
        defer { isLoading = false }
        let key = TrackerStore.dateString(selectedDate)
        if let loaded = await store.dailyData(for: key) {
            data = loaded
        } else {
            data = DailyTrackerData(date: key)
        }
    }

    private func formatTotal(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 { return "\(mins)m total" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h total" : "\(h)h \(m)m total"
    }
}
