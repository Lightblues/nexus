import SwiftUI

/// 24-hour horizontal bar. Each record renders as a colored segment proportional
/// to its duration; color is deterministic from the app name.
struct TrackerTimeline: View {
    let records: [WindowActivityRecord]
    let day: Date

    @State private var hoveredIndex: Int?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawHourLines(in: context, size: size)
                    drawRecords(in: context, size: size)
                }
                if let idx = hoveredIndex, records.indices.contains(idx) {
                    tooltip(for: records[idx])
                        .position(x: min(max(80, hoverPoint.x), geo.size.width - 80),
                                  y: max(28, hoverPoint.y - 28))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt):
                    hoverPoint = pt
                    hoveredIndex = recordIndex(at: pt.x, width: geo.size.width)
                case .ended:
                    hoveredIndex = nil
                }
            }
            .overlay(alignment: .bottom) {
                hourLabels(width: geo.size.width)
            }
        }
    }

    // MARK: - Drawing

    private var dayStart: Date {
        Calendar.current.startOfDay(for: day)
    }

    private func xForTime(_ date: Date, width: CGFloat) -> CGFloat {
        let elapsed = date.timeIntervalSince(dayStart)
        let frac = max(0, min(1, elapsed / 86_400))
        return CGFloat(frac) * width
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

    private func drawRecords(in context: GraphicsContext, size: CGSize) {
        let trackY: CGFloat = 4
        let trackHeight = size.height - 18
        for record in records {
            let x = xForTime(record.startTime, width: size.width)
            let endX = xForTime(record.endTime, width: size.width)
            let w = max(1, endX - x)
            let rect = CGRect(x: x, y: trackY, width: w, height: trackHeight)
            let color = TrackerColors.color(for: record.app)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
        }
    }

    private func hourLabels(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                Text("\(hour):00")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: width / 4, alignment: hour == 0 ? .leading : (hour == 24 ? .trailing : .center))
            }
        }
        .frame(width: width)
    }

    private func recordIndex(at x: CGFloat, width: CGFloat) -> Int? {
        for (i, r) in records.enumerated() {
            let startX = xForTime(r.startTime, width: width)
            let endX = xForTime(r.endTime, width: width)
            if x >= startX && x <= endX { return i }
        }
        return nil
    }

    private func tooltip(for record: WindowActivityRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.app).font(.system(size: 11, weight: .semibold))
            if let file = record.context?.file {
                Text(file).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else if let domain = record.context?.domain {
                Text(domain).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("\(formatRange(record)) · \(formatDuration(record.duration))")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 4, y: 2)
    }

    private func formatRange(_ record: WindowActivityRecord) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: record.startTime))–\(f.string(from: record.endTime))"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 1 { return "\(Int(seconds))s" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}

/// Stable, app-name-keyed color palette. Same input → same color.
enum TrackerColors {
    private static let palette: [Color] = [
        .blue, .green, .orange, .pink, .purple, .red, .teal, .indigo, .cyan, .yellow,
        .mint, .brown
    ]

    static func color(for appName: String) -> Color {
        // FNV-1a-ish hash; stable across runs.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in appName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
