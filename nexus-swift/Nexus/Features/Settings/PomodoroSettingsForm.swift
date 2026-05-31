import SwiftUI

/// Pomodoro section: durations, auto-break, projects, tags.
/// Two-way bound to ConfigService — every change writes config.json.
struct PomodoroSettingsForm: View {
    @EnvironmentObject var config: ConfigService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            timingSection
            behaviorSection
            projectsSection
            tagsSection
        }
        .frame(maxWidth: 540, alignment: .leading)
    }

    // MARK: - Timing

    private var timingSection: some View {
        SettingsSection(title: "Session Lengths") {
            FieldRow(label: "Work duration") {
                MinutesStepper(value: bind(\.pomodoro.workDuration), range: 1...180)
            }
            FieldRow(label: "Short break") {
                MinutesStepper(value: bind(\.pomodoro.shortBreakDuration), range: 1...60)
            }
            FieldRow(label: "Long break") {
                MinutesStepper(value: bind(\.pomodoro.longBreakDuration), range: 1...120)
            }
            FieldRow(label: "Sessions before long break") {
                Stepper(value: bind(\.pomodoro.sessionsBeforeLongBreak), in: 1...12) {
                    Text("\(config.config.pomodoro.sessionsBeforeLongBreak)")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .leading)
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            Toggle("Auto-start break after focus completes", isOn: bind(\.pomodoro.autoStartBreak))
            if config.config.pomodoro.autoStartBreak {
                FieldRow(label: "Auto-start delay") {
                    Stepper(value: bind(\.pomodoro.autoStartBreakDelay), in: 0...30) {
                        Text("\(config.config.pomodoro.autoStartBreakDelay) sec")
                            .monospacedDigit()
                    }
                    .labelsHidden()
                }
                .padding(.leading, 22)
            }
            Toggle("Show popover when focus completes", isOn: bind(\.pomodoro.showPopoverOnComplete))
            Toggle("Trigger Raycast confetti on focus complete",
                   isOn: bind(\.pomodoro.confettiOnComplete))
        }
    }

    // MARK: - Projects

    private var projectsSection: some View {
        SettingsSection(title: "Projects") {
            ForEach(config.config.pomodoro.projects) { p in
                HStack(spacing: 8) {
                    ColorChip(hex: p.color)
                    Text(p.name)
                        .font(.system(size: 12))
                    Spacer()
                    Button(role: .destructive) {
                        removeProject(p)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
                .padding(.vertical, 2)
            }
            AddProjectRow(onAdd: addProject)
        }
    }

    private func addProject(name: String, color: String) {
        var draft = config.config
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              !draft.pomodoro.projects.contains(where: { $0.name == trimmedName })
        else { return }
        draft.pomodoro.projects.append(ProjectConfig(name: trimmedName, color: color))
        config.save(draft)
    }

    private func removeProject(_ p: ProjectConfig) {
        var draft = config.config
        draft.pomodoro.projects.removeAll { $0.name == p.name }
        config.save(draft)
    }

    // MARK: - Tags

    private var tagsSection: some View {
        SettingsSection(title: "Tags") {
            StringListEditor(
                items: config.config.pomodoro.tags,
                placeholder: "Add tag",
                onChange: { newList in
                    var draft = config.config
                    draft.pomodoro.tags = newList
                    config.save(draft)
                }
            )
        }
    }

    // MARK: - Binding helper

    private func bind<T>(_ keyPath: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(
            get: { config.config[keyPath: keyPath] },
            set: { newValue in
                var draft = config.config
                draft[keyPath: keyPath] = newValue
                config.save(draft)
            }
        )
    }
}

// MARK: - Subviews specific to this form

private struct MinutesStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        Stepper(value: $value, in: range) {
            Text("\(value) min")
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
        }
        .labelsHidden()
    }
}

private struct ColorChip: View {
    let hex: String
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 14, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.1)))
    }
}

private struct AddProjectRow: View {
    @State private var name = ""
    @State private var color = "#3B82F6"
    let onAdd: (String, String) -> Void

    private static let palette = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444",
                                  "#8B5CF6", "#EC4899", "#14B8A6", "#6366F1"]

    var body: some View {
        HStack(spacing: 8) {
            ColorChip(hex: color)
            TextField("New project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit(submit)
            Menu {
                ForEach(Self.palette, id: \.self) { c in
                    Button { color = c } label: {
                        HStack {
                            ColorChip(hex: c)
                            Text(c)
                        }
                    }
                }
            } label: {
                Text("Color").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("Add", action: submit)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed, color)
        name = ""
    }
}
