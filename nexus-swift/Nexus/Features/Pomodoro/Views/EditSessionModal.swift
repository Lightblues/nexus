import SwiftUI

/// Shared editor for both idle and running/paused states (ADR-007).
struct EditSessionModal: View {
    @EnvironmentObject var repo: PomodoroRepository
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
                            ForEach(repo.projects) { p in
                                Text(p.name).tag(Optional(p.name))
                            }
                            // Allow keeping a custom project not in catalog:
                            if let cur = working.project,
                               !repo.projects.contains(where: { $0.name == cur }) {
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
        let configured = repo.tagCatalog
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

