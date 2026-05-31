import SwiftUI

/// App share visualization. macOS 13 doesn't have Charts.SectorMark, so we draw a
/// proper donut with `Canvas`. Same data shape as the spec's donut chart.
struct AppUsageDonut: View {
    let summary: [String: TimeInterval]

    private struct Slice: Identifiable {
        let id = UUID()
        let app: String
        let seconds: TimeInterval
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("App share")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            ZStack {
                if total > 0 {
                    Canvas { context, size in
                        drawDonut(context: context, size: size)
                    }
                } else {
                    Circle().stroke(.quaternary, lineWidth: 24)
                }

                VStack(spacing: 2) {
                    Text(formatTotal(total))
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                    Text(total > 0 ? "today" : "no activity")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            legend
        }
    }

    // MARK: - Drawing

    private func drawDonut(context: GraphicsContext, size: CGSize) {
        let outer = min(size.width, size.height) / 2 - 2
        let inner = outer * 0.62
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var startAngle = Angle.degrees(-90)
        for slice in slices {
            let frac = slice.seconds / total
            let endAngle = startAngle + .degrees(360 * frac)
            var path = Path()
            path.addArc(center: center, radius: outer, startAngle: startAngle,
                        endAngle: endAngle, clockwise: false)
            path.addArc(center: center, radius: inner, startAngle: endAngle,
                        endAngle: startAngle, clockwise: true)
            path.closeSubpath()
            context.fill(path, with: .color(TrackerColors.color(for: slice.app)))
            startAngle = endAngle
        }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(slices) { s in
                HStack(spacing: 6) {
                    Circle().fill(TrackerColors.color(for: s.app)).frame(width: 8, height: 8)
                    Text(s.app)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Text(formatTotal(s.seconds))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Slicing

    private var slices: [Slice] {
        let sorted = summary.map { Slice(app: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
        let topN = 6
        if sorted.count <= topN { return sorted }
        let head = Array(sorted.prefix(topN))
        let other = sorted.dropFirst(topN).map(\.seconds).reduce(0, +)
        return head + [Slice(app: "Other", seconds: other)]
    }

    private var total: TimeInterval { summary.values.reduce(0, +) }

    private func formatTotal(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 1 { return "\(Int(seconds))s" }
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}
