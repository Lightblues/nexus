import SwiftUI

/// GitHub-style heatmap of work-session counts. Reads from PomodoroRepository
/// via SQL aggregation — does not load full session rows.
///
/// The visible week range adapts to the data: minimum 12 weeks, maximum
/// `maxWeeks` (default 53). When the user has very little data, we still
/// show some context — but we don't pad to a year of empty cells.
struct ActivityCalendar: View {
    @EnvironmentObject var repo: PomodoroRepository

    /// Upper bound on weeks to render. Lower bound is fixed at 12 inside.
    var maxWeeks: Int = 53

    @State private var counts: [String: Int] = [:]
    @State private var weeks: Int = 12      // resolved at load() time
    @State private var hovered: (date: Date, count: Int)?
    @State private var hoverPoint: CGPoint = .zero

    private static let cellSize: CGFloat = 11
    private static let cellGap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                gridArea
            }
            HStack(spacing: 6) {
                Spacer()
                Text("Less").font(.system(size: 9)).foregroundStyle(.tertiary)
                ForEach(0..<5, id: \.self) { bucket in
                    cellRect(bucket: bucket)
                        .frame(width: 11, height: 11)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .task { await load() }
    }

    // MARK: - Sub-areas

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: Self.cellGap) {
            ForEach(0..<7, id: \.self) { idx in
                Text(idx % 2 == 1 ? Self.weekdayShort(idx) : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(height: Self.cellSize, alignment: .trailing)
            }
        }
        .padding(.top, 14)   // align with month labels above grid
    }

    private var gridArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            monthLabels
            grid
        }
    }

    private var monthLabels: some View {
        // One label per month, positioned at the column where the month starts.
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let weeksArray = (0..<weeks).map { i -> Date in
            cal.date(byAdding: .weekOfYear, value: -(weeks - 1 - i), to: now)!
        }
        var seenMonths: Set<Int> = []
        var labels: [(col: Int, name: String)] = []
        for (col, w) in weeksArray.enumerated() {
            let m = cal.component(.month, from: w)
            if !seenMonths.contains(m) {
                seenMonths.insert(m)
                let name = cal.shortMonthSymbols[m - 1]
                labels.append((col: col, name: name))
            }
        }
        let unitWidth = Self.cellSize + Self.cellGap
        return ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.col) { l in
                Text(l.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .offset(x: CGFloat(l.col) * unitWidth)
            }
        }
        .frame(height: 12, alignment: .topLeading)
    }

    private var grid: some View {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let unit = Self.cellSize + Self.cellGap
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(0..<weeks, id: \.self) { col in
                    let weekDate = cal.date(byAdding: .weekOfYear, value: -(weeks - 1 - col), to: now)!
                    ForEach(0..<7, id: \.self) { row in
                        if let day = Self.dateForCell(reference: weekDate, weekday: row, calendar: cal),
                           day <= now {
                            let key = Self.dayKey(day)
                            let count = counts[key] ?? 0
                            cellRect(bucket: bucket(for: count))
                                .frame(width: Self.cellSize, height: Self.cellSize)
                                .position(
                                    x: CGFloat(col) * unit + Self.cellSize / 2,
                                    y: CGFloat(row) * unit + Self.cellSize / 2
                                )
                                .onHover { hovering in
                                    if hovering {
                                        hovered = (day, count)
                                    } else if hovered?.date == day {
                                        hovered = nil
                                    }
                                }
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                tooltip(geo: geo, unit: unit)
            }
        }
        .frame(width: CGFloat(weeks) * unit, height: 7 * unit)
    }

    @ViewBuilder
    private func tooltip(geo: GeometryProxy, unit: CGFloat) -> some View {
        if let h = hovered {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateLabel(h.date)).font(.system(size: 11, weight: .semibold))
                Text("\(h.count) focus session\(h.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 4, y: 2)
            .offset(x: 0, y: -50)
        }
    }

    // MARK: - Drawing

    private func cellRect(bucket: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Self.bucketColor(bucket))
    }

    private func bucket(for count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1: return 1
        case 2...3: return 2
        case 4...5: return 3
        default: return 4
        }
    }

    private static func bucketColor(_ bucket: Int) -> Color {
        // GitHub-ish green ramp; gray for empty.
        switch bucket {
        case 0: return .gray.opacity(0.18)
        case 1: return .accentColor.opacity(0.30)
        case 2: return .accentColor.opacity(0.55)
        case 3: return .accentColor.opacity(0.80)
        default: return .accentColor
        }
    }

    // MARK: - Date helpers

    /// The cell at (weekStart, weekday) — Monday=0. Returns nil if calendar
    /// math fails (won't in practice).
    private static func dateForCell(reference: Date, weekday: Int, calendar: Calendar) -> Date? {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference
        // Calendar week starts on Sunday by default; adjust to Monday-first.
        // We want row 0 = Monday, row 6 = Sunday.
        let offset = weekday + 1   // +1 to skip Sunday at index 0
        return calendar.date(byAdding: .day, value: offset, to: weekStart)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func dayKey(_ d: Date) -> String { dayKeyFormatter.string(from: d) }

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, yyyy"
        return f
    }()
    private static func dateLabel(_ d: Date) -> String { labelFormatter.string(from: d) }

    private static func weekdayShort(_ idx: Int) -> String {
        // 0 Mon, 6 Sun
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][idx]
    }

    // MARK: - Loading

    private func load() async {
        let cal = Calendar(identifier: .gregorian)
        let to = cal.date(byAdding: .day, value: 1, to: Date())!

        // Resolve the actual span: at least 12 weeks, at most maxWeeks, but
        // long enough to cover the user's earliest session.
        let summary = await repo.dbSummary()
        let resolvedWeeks: Int
        if let first = summary.firstSession {
            let span = cal.dateComponents([.weekOfYear], from: first, to: to)
            let needed = max((span.weekOfYear ?? 0) + 1, 12)
            resolvedWeeks = min(maxWeeks, needed)
        } else {
            resolvedWeeks = 12
        }
        weeks = resolvedWeeks

        let from = cal.date(byAdding: .weekOfYear, value: -resolvedWeeks, to: to)!
        counts = await repo.dailyCounts(from: from, to: to)
    }
}
