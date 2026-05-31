import SwiftUI
import Charts

/// Stats main page. Stacks Activity Calendar (year), Weekly Bar (last 7 days),
/// Daily Timeline (selected day), and Session List (selected day).
struct StatsView: View {
    @EnvironmentObject var repo: PomodoroRepository

    @State private var selectedDate: Date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                calendarCard
                HStack(alignment: .top, spacing: 16) {
                    weeklyCard.frame(maxWidth: .infinity)
                    dailySummaryCard.frame(width: 240)
                }
                timelineCard
                sessionListCard
            }
            .padding(20)
        }
    }

    // MARK: - Activity calendar

    private var calendarCard: some View {
        StatsCard(title: "Activity") {
            ActivityCalendar(weeks: 53)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Weekly bar

    @State private var weeklyData: [WeekDay] = []

    private struct WeekDay: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let hours: Double
    }

    private var weeklyCard: some View {
        StatsCard(title: "Last 7 Days") {
            if weeklyData.allSatisfy({ $0.hours == 0 }) {
                emptyState
                    .frame(height: 180)
            } else {
                Chart(weeklyData) { d in
                    BarMark(
                        x: .value("Day", d.label),
                        y: .value("Hours", d.hours)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(3)
                    .annotation(position: .top, alignment: .center) {
                        if d.hours > 0 {
                            Text(formatHours(d.hours))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
            }
        }
        .task { await loadWeekly() }
    }

    private func loadWeekly() async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: -6, to: today)!
        let to = cal.date(byAdding: .day, value: 1, to: today)!
        let dailyHours = await repo.dailyHours(from: from, to: to)
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "EEE"
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM-dd"
        var rows: [WeekDay] = []
        for offset in 0...6 {
            let day = cal.date(byAdding: .day, value: offset - 6, to: today)!
            let key = keyFormatter.string(from: day)
            rows.append(WeekDay(date: day,
                                label: labelFormatter.string(from: day),
                                hours: dailyHours[key] ?? 0))
        }
        await MainActor.run { weeklyData = rows }
    }

    // MARK: - Daily summary

    @State private var todayCount: Int = 0
    @State private var todayHours: Double = 0

    private var dailySummaryCard: some View {
        StatsCard(title: "Today") {
            VStack(alignment: .leading, spacing: 14) {
                bigNumber(value: "\(repo.todayCount)", label: "sessions",
                          color: .accentColor)
                bigNumber(value: formatHours(repo.todayDuration / 3600),
                          label: "focused", color: .green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bigNumber(value: String, label: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Daily timeline

    @State private var daySessions: [SessionRecord] = []

    private var timelineCard: some View {
        StatsCard(title: "Daily Timeline") {
            HStack(alignment: .firstTextBaseline) {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Spacer()
                if !daySessions.isEmpty {
                    Text("\(daySessions.count) session\(daySessions.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 6)
            DailyTimelineBar(sessions: daySessions, day: selectedDate)
                .frame(height: 50)
        }
        .task(id: dayKey(selectedDate)) { await loadDay() }
    }

    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func loadDay() async {
        daySessions = await repo.sessions(on: selectedDate)
    }

    // MARK: - Session list

    private var sessionListCard: some View {
        StatsCard(title: "Sessions") {
            if daySessions.isEmpty {
                Text("No sessions on this day")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(daySessions) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No focus sessions yet")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatHours(_ hours: Double) -> String {
        if hours < 1 {
            return "\(Int((hours * 60).rounded()))m"
        }
        let h = Int(hours)
        let m = Int(((hours - Double(h)) * 60).rounded())
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}

/// Card container with a heading.
struct StatsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Single row in the session list.
struct SessionRow: View {
    let session: SessionRecord

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            kindIndicator
            Text(timeRange)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(formatDuration(session.duration))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let project = session.project {
                        Text(project)
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Text("(no project)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    if !session.tags.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.system(size: 11))
                        Text(session.tags.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let task = session.task, !task.isEmpty {
                    Text(task).font(.system(size: 11)).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !session.completedFully {
                Text("partial")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.tertiary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var timeRange: String {
        "\(Self.timeFormatter.string(from: session.startTime)) – \(Self.timeFormatter.string(from: session.endTime))"
    }

    private var kindIndicator: some View {
        Circle()
            .fill(kindColor)
            .frame(width: 8, height: 8)
    }

    private var kindColor: Color {
        switch session.kind {
        case .work: return .accentColor
        case .shortBreak: return .green
        case .longBreak: return .teal
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let mins = Int(s) / 60
        if mins < 1 { return "\(Int(s))s" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins/60)h\(mins%60)m"
    }
}

/// 24h horizontal bar showing session blocks for one day.
struct DailyTimelineBar: View {
    let sessions: [SessionRecord]
    let day: Date

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawHourLines(in: context, size: size)
                    drawSessions(in: context, size: size)
                }
            }
            .overlay(alignment: .bottom) {
                hourLabels(width: geo.size.width)
            }
        }
    }

    private var dayStart: Date {
        Calendar.current.startOfDay(for: day)
    }

    private func xForTime(_ d: Date, width: CGFloat) -> CGFloat {
        let elapsed = d.timeIntervalSince(dayStart)
        return CGFloat(max(0, min(1, elapsed / 86_400))) * width
    }

    private func drawHourLines(in context: GraphicsContext, size: CGSize) {
        var path = Path()
        for h in 0...24 {
            let x = CGFloat(h) / 24 * size.width
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height - 14))
        }
        context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 1)
    }

    private func drawSessions(in context: GraphicsContext, size: CGSize) {
        let trackY: CGFloat = 4
        let trackH = size.height - 18
        for s in sessions {
            let x = xForTime(s.startTime, width: size.width)
            let endX = xForTime(s.endTime, width: size.width)
            let w = max(2, endX - x)
            let rect = CGRect(x: x, y: trackY, width: w, height: trackH)
            let color: Color
            switch s.kind {
            case .work: color = .accentColor
            case .shortBreak: color = .green
            case .longBreak: color = .teal
            }
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color.opacity(0.85)))
        }
    }

    private func hourLabels(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                Text("\(hour):00")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: width / 4,
                           alignment: hour == 0 ? .leading : (hour == 24 ? .trailing : .center))
            }
        }
        .frame(width: width)
    }
}
