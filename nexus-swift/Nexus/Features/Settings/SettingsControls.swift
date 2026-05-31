import SwiftUI

/// Common visual primitives used by all SettingsForm pages.

/// Section card with a heading + content stack.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Standard label + control row, label fixed-width for visual alignment.
struct FieldRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 180, alignment: .leading)
            control()
            Spacer()
        }
    }
}

/// Explicit number display + stepper. Native macOS Stepper hides its label by
/// design — putting the number in a sibling Text gives users the actual value.
struct NumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String = ""
    var width: CGFloat = 56

    var body: some View {
        HStack(spacing: 6) {
            Text(suffix.isEmpty ? "\(value)" : "\(value) \(suffix)")
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: width, alignment: .leading)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}


/// Editor for an array of strings (used for tags + enrichApps). Items render
/// as removable chips. New entries via inline TextField.
struct StringListEditor: View {
    let items: [String]
    let placeholder: String
    let onChange: ([String]) -> Void

    @State private var newEntry = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    chip(item)
                }
            }
            HStack(spacing: 6) {
                TextField(placeholder, text: $newEntry)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(submit)
                Button("Add", action: submit)
                    .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func chip(_ item: String) -> some View {
        HStack(spacing: 4) {
            Text(item).font(.system(size: 11))
            Button {
                onChange(items.filter { $0 != item })
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.tertiary.opacity(0.4), in: Capsule())
    }

    private func submit() {
        let trimmed = newEntry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !items.contains(trimmed) else { return }
        onChange(items + [trimmed])
        newEntry = ""
    }
}

/// Wrapping flow layout. Same as the one used in EditSessionModal — extracted
/// here so both Settings and Pomodoro popover can share it.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if rows.last! + s.width > width {
                totalHeight += rowHeight + spacing
                rows.append(0)
                rowHeight = 0
            }
            rows[rows.count - 1] += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width.isFinite ? width : 320, height: max(totalHeight, 28))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// Color from a "#RRGGBB" hex string.
extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xff) / 255.0
        let g = Double((v >> 8) & 0xff) / 255.0
        let b = Double(v & 0xff) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
