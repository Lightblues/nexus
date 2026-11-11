import SwiftUI

/// Memory watch: notifications on memory pressure and baton machine events (SADR-021).
struct MemorySettingsForm: View {
    @Binding var draft: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Memory Watch") {
                Toggle("Watch memory pressure", isOn: $draft.memory.enabled)
                FieldRow(label: "Notify at") {
                    Picker("", selection: $draft.memory.notifyLevel) {
                        Text("Warning or critical").tag(MemoryLevel.warn)
                        Text("Critical only").tag(MemoryLevel.critical)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .disabled(!draft.memory.enabled)
                }
                Text("When macOS reports memory pressure, Nexus names the apps using the most memory, at most once every 15 minutes unless pressure turns critical or a new app takes the top spot. It only informs: it never quits or kills a process.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsSection(title: "Events for baton") {
                Toggle("Write memory events", isOn: $draft.memory.writeEvents)
                    .disabled(!draft.memory.enabled)
                Text("While pressure lasts, a line every 10 seconds goes to ~/.baton/machine-events/<date>.jsonl (process names and memory figures only, kept 7 days). baton reads them when it next reaches this Mac; nothing is sent over the network.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 540, alignment: .leading)
    }
}
