import SwiftUI

/// Pomodoro section: durations, auto-break, projects, tags.
/// Edits a draft AppConfig binding owned by SettingsView. No disk writes here.
struct PomodoroSettingsForm: View {
    @Binding var draft: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            timingSection
            behaviorSection
            projectsAndTagsNote
        }
        .frame(maxWidth: 540, alignment: .leading)
    }

    // MARK: - Timing

    private var timingSection: some View {
        SettingsSection(title: "Session Lengths") {
            FieldRow(label: "Work duration") {
                NumberStepper(value: $draft.pomodoro.workDuration, range: 1...180, suffix: "min", width: 64)
            }
            FieldRow(label: "Short break") {
                NumberStepper(value: $draft.pomodoro.shortBreakDuration, range: 1...60, suffix: "min", width: 64)
            }
            FieldRow(label: "Long break") {
                NumberStepper(value: $draft.pomodoro.longBreakDuration, range: 1...120, suffix: "min", width: 64)
            }
            FieldRow(label: "Sessions before long break") {
                NumberStepper(value: $draft.pomodoro.sessionsBeforeLongBreak, range: 1...12, suffix: "", width: 32)
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            Toggle("Auto-start break after focus completes", isOn: $draft.pomodoro.autoStartBreak)
            if draft.pomodoro.autoStartBreak {
                FieldRow(label: "Auto-start delay") {
                    NumberStepper(value: $draft.pomodoro.autoStartBreakDelay,
                                  range: 0...30, suffix: "sec", width: 56)
                }
                .padding(.leading, 22)
            }
            Toggle("Show popover when focus completes", isOn: $draft.pomodoro.showPopoverOnComplete)
            Toggle("Trigger Raycast confetti on focus complete",
                   isOn: $draft.pomodoro.confettiOnComplete)
        }
    }

    // MARK: - Projects + tags handoff

    private var projectsAndTagsNote: some View {
        SettingsSection(title: "Projects & Tags") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projects and tags are stored in the database, not the config file.")
                        .font(.system(size: 12, weight: .medium))
                    Text("They appear automatically as you tag pomodoro sessions, and are managed alongside session history. Open the Pomodoro popover and click the session info card to add or rename them.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
