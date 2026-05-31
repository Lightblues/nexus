import SwiftUI

/// App-level rank list with disclosure rows that expand to show top contexts
/// (file/url breakdown) sorted by duration.
struct AppRankList: View {
    let records: [WindowActivityRecord]
    let summary: [String: TimeInterval]

    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            if rankedApps.isEmpty {
                Text("No activity yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(rankedApps, id: \.self) { app in
                        appRow(app)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func appRow(_ app: String) -> some View {
        let seconds = summary[app] ?? 0
        let isExpanded = expanded.contains(app)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    if isExpanded { expanded.remove(app) } else { expanded.insert(app) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Circle().fill(TrackerColors.color(for: app)).frame(width: 8, height: 8)
                Text(app).font(.system(size: 12))
                Spacer()
                Text(formatDuration(seconds))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(formatPercent(seconds)).font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture {
                if isExpanded { expanded.remove(app) } else { expanded.insert(app) }
            }

            if isExpanded {
                ForEach(contextBreakdown(for: app), id: \.label) { entry in
                    HStack(spacing: 8) {
                        Spacer().frame(width: 24)
                        Text(entry.label)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(entry.seconds))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Derived

    private var totalSeconds: TimeInterval { summary.values.reduce(0, +) }

    private var rankedApps: [String] {
        summary.sorted { $0.value > $1.value }.map(\.key)
    }

    private struct ContextEntry { let label: String; let seconds: TimeInterval }

    private func contextBreakdown(for app: String) -> [ContextEntry] {
        var totals: [String: TimeInterval] = [:]
        for r in records where r.app == app {
            let label = r.context?.file
                ?? r.context?.domain
                ?? r.context?.url
                ?? r.context?.rawTitle
                ?? "(no detail)"
            totals[label, default: 0] += r.duration
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { ContextEntry(label: $0.key, seconds: $0.value) }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 1 { return "\(Int(seconds))s" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h\(mins % 60)m"
    }

    private func formatPercent(_ seconds: TimeInterval) -> String {
        guard totalSeconds > 0 else { return "" }
        let pct = Int((seconds / totalSeconds * 100).rounded())
        return "\(pct)%"
    }
}
