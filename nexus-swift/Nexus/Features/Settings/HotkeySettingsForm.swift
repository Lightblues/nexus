import SwiftUI

struct HotkeySettingsForm: View {
    @EnvironmentObject var config: ConfigService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            paletteSection
            generalSection
        }
        .frame(maxWidth: 540, alignment: .leading)
    }

    private var paletteSection: some View {
        SettingsSection(title: "Command Palette") {
            FieldRow(label: "Shortcut") {
                TextField("CommandOrControl+Shift+Space",
                          text: bind(\.hotkey.palette))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            Text("Modifier list separated by `+`. Use `CommandOrControl` for cross-platform-style shortcuts. Avoid `Cmd+Space` (Spotlight) and `Option+Space` (Raycast).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "Startup") {
            Toggle("Launch Nexus at login",
                   isOn: bind(\.ui.openAtLogin))
            Text("Registers Nexus with macOS Login Items. Takes effect immediately.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
