import SwiftUI

/// Shared editor for both idle and running/paused states (ADR-007).
struct EditSessionModal: View {
    @EnvironmentObject var config: ConfigService
    @State private var working: SessionMetadata
    @State private var newProjectMode = false
    @State private var newProjectName = ""
    @State private var newTagText = ""

    let onSave: (SessionMetadata) -> Void
    let onCancel: () -> Void

    init(metadata: SessionMetadata,
         onSave: @escaping (SessionMetadata) -> Void,
         onCancel: @escaping () -> Void) {
        self._working = State(initialValue: metadata)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session")
                .font(.system(size: 14, weight: .semibold))

            // Project
            Group {
                Text("Project").font(.system(size: 11)).foregroundStyle(.secondary)
                if newProjectMode {
                    HStack {
                        TextField("New project", text: $newProjectName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        Button("Add") {
                            let trimmed = newProjectName.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { working.project = trimmed }
                            newProjectMode = false
                            newProjectName = ""
                        }
                        Button("Cancel") {
                            newProjectMode = false
                            newProjectName = ""
                        }
                    }
                } else {
                    HStack {
                        Picker("", selection: $working.project) {
                            ForEach(config.config.pomodoro.projects) { p in
                                Text(p.name).tag(Optional(p.name))
                            }
                            // Allow keeping a custom project not in config:
                            if let cur = working.project,
                               !config.config.pomodoro.projects.contains(where: { $0.name == cur }) {
                                Text(cur).tag(Optional(cur))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Button("New") { newProjectMode = true }
                    }
                }
            }

            // Tags
            Group {
                Text("Tags").font(.system(size: 11)).foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    FlowLayout(spacing: 6) {
                        ForEach(allTagOptions, id: \.self) { tag in
                            TagChip(
                                title: tag,
                                selected: working.tags.contains(tag),
                                onToggle: { toggleTag(tag) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 100)
                HStack {
                    TextField("Add tag", text: $newTagText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit(addNewTag)
                    Button("Add", action: addNewTag)
                        .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            // Task
            Group {
                Text("Task").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("What are you working on?",
                          text: Binding(get: { working.task ?? "" },
                                        set: { working.task = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(working) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var allTagOptions: [String] {
        let configured = config.config.pomodoro.tags
        let extras = working.tags.filter { !configured.contains($0) }
        return configured + extras
    }

    private func toggleTag(_ tag: String) {
        if let idx = working.tags.firstIndex(of: tag) {
            working.tags.remove(at: idx)
        } else {
            working.tags.append(tag)
        }
    }

    private func addNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !working.tags.contains(trimmed) else { return }
        working.tags.append(trimmed)
        newTagText = ""
    }
}

private struct TagChip: View {
    let title: String
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text(title)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.quinary),
                            in: Capsule())
                .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// Simple wrapping flow layout for tag chips (macOS 13+ compatible).
private struct FlowLayout: Layout {
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
