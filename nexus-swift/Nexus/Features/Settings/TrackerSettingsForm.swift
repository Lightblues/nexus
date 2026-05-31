import SwiftUI

struct TrackerSettingsForm: View {
    @EnvironmentObject var config: ConfigService
    @EnvironmentObject var trackerService: TrackerService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            statusSection
            behaviorSection
            enrichSection
            privacySection
        }
        .frame(maxWidth: 540, alignment: .leading)
    }

    private var statusSection: some View {
        SettingsSection(title: "Status") {
            HStack(spacing: 8) {
                statusIndicator
                Spacer()
                if trackerService.status == .waitingForPermission {
                    Button("Open Accessibility Settings") {
                        Permissions.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
            }
            if trackerService.status == .waitingForPermission {
                Text("Tracker reads the focused-window title via the Accessibility API. Without permission the tracker stays paused; once granted, it resumes within 2 seconds.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusLabel).font(.system(size: 12, weight: .medium))
        }
    }

    private var statusLabel: String {
        switch trackerService.status {
        case .stopped: return "Disabled"
        case .running: return "Tracking"
        case .idle: return "Paused (user idle)"
        case .waitingForPermission: return "Needs Accessibility permission"
        }
    }

    private var statusColor: Color {
        switch trackerService.status {
        case .stopped: return .secondary
        case .running: return .green
        case .idle: return .orange
        case .waitingForPermission: return .red
        }
    }

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            Toggle("Enable tracker", isOn: bind(\.tracker.enabled))
            FieldRow(label: "Poll interval") {
                Stepper(value: bind(\.tracker.pollInterval), in: 1...60) {
                    Text("\(config.config.tracker.pollInterval) sec")
                        .monospacedDigit()
                }
                .labelsHidden()
            }
            FieldRow(label: "Idle threshold") {
                Stepper(value: bind(\.tracker.idleThreshold), in: 30...600, step: 10) {
                    Text("\(config.config.tracker.idleThreshold) sec")
                        .monospacedDigit()
                }
                .labelsHidden()
            }
            Text("If no keyboard or mouse activity for this duration, the tracker pauses recording.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var enrichSection: some View {
        SettingsSection(title: "Context Enrichment Whitelist") {
            Text("Apps in this list get extra context tracking — VSCode/Cursor parse the file and project name, and browsers fetch the active tab URL via Apple Events. Other apps record only the bundle id and window title.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StringListEditor(
                items: config.config.tracker.enrichApps,
                placeholder: "App name (e.g. \"Code\", \"Google Chrome\")",
                onChange: { newList in
                    var draft = config.config
                    draft.tracker.enrichApps = newList
                    config.save(draft)
                }
            )
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            Toggle("Record raw window titles",
                   isOn: bind(\.tracker.recordTitle))
            Text("When enabled, the original window title is stored alongside each record. Useful for debugging — disabled by default since titles can leak PII.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

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
