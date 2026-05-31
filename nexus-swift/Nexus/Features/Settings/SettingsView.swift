import SwiftUI

/// Settings GUI. Reads from ConfigService, edits a draft @State, saves on commit.
/// All field mutations call `service.save(draft)` which atomically rewrites
/// ~/.ea/nexus/config.json and triggers the file-watcher hot-reload path
/// (watcher's reload is suppressed for this self-write — see Config.swift).
///
/// Bottom toolbar gives access to the raw JSON file: "Reveal in Finder" follows
/// the symlink (so users on mackup land in the backup dir directly) and "Open
/// in Editor" launches the user's default `.json` handler.
struct SettingsView: View {
    @EnvironmentObject var config: ConfigService

    enum Tab: String, CaseIterable, Identifiable {
        case pomodoro, tracker, uploader, hotkey
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pomodoro: return "Pomodoro"
            case .tracker:  return "Tracker"
            case .uploader: return "Uploader"
            case .hotkey:   return "Hotkey"
            }
        }
        var systemImage: String {
            switch self {
            case .pomodoro: return "timer"
            case .tracker:  return "clock"
            case .uploader: return "arrow.up.circle"
            case .hotkey:   return "keyboard"
            }
        }
    }
    @State private var tab: Tab = .pomodoro

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView { tabContent.padding(20) }
            Divider()
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.systemImage)
                        Text(t.title)
                    }
                    .font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                    .foregroundStyle(tab == t ? Color.accentColor : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(tab == t ? Color.accentColor.opacity(0.10) : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .pomodoro: PomodoroSettingsForm()
        case .tracker:  TrackerSettingsForm()
        case .uploader: UploaderSettingsForm()
        case .hotkey:   HotkeySettingsForm()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tertiary)
            Text("config.json")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(displayPath)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Reveal in Finder") { revealInFinder() }
                .controlSize(.small)
            Button("Open in Editor") { openInEditor() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var displayPath: String {
        // Show the resolved target path so mackup users see the backup location;
        // useful confirmation that the symlink works.
        let url = Paths.configFile
        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            return "→ \(resolved)"
        }
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func revealInFinder() {
        // Resolve symlink before revealing — so we land on the real file in the
        // mackup backup dir, not the symlink itself.
        let url = Paths.configFile
        let resolved = (try? URL(fileURLWithPath: FileManager.default
            .destinationOfSymbolicLink(atPath: url.path))) ?? url
        NSWorkspace.shared.activateFileViewerSelecting([resolved])
    }

    private func openInEditor() {
        NSWorkspace.shared.open(Paths.configFile)
    }
}
