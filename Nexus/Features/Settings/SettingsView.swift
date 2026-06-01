import SwiftUI

/// Settings GUI. Reads from ConfigService into a local `draft`, edits the draft,
/// commits all changes via Save. Eliminates per-keystroke disk writes (the cause
/// of tab-switch lag and excessive ConfigService→form rebind churn).
///
/// The draft is owned by SettingsView so navigating between sub-tabs preserves
/// in-flight edits; all sub-forms bind into the same `$draft`.
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
    @State private var draft: AppConfig = AppConfig()
    @State private var initialized = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            saveBar
            Divider()
            ScrollView { tabContent.padding(20) }
            Divider()
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !initialized {
                draft = config.config
                initialized = true
            }
        }
        // Pull in external edits (e.g., user hand-edited config.json) when
        // the user has no unsaved changes — otherwise leave their draft alone.
        .onChange(of: config.config) { newValue in
            if !isDirty {
                draft = newValue
            }
        }
    }

    private var isDirty: Bool { draft != config.config }

    // MARK: - Tab bar

    private var tabBar: some View {
        // Pill-style segmented tabs. The highlight is a RoundedRectangle inside
        // each button's bounds (not a full-width background) so it never bleeds
        // into the surrounding chrome. `.contentShape(Rectangle())` makes the
        // entire pill area click-targetable, not just the painted text+icon.
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                tabButton(t)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    private func tabButton(_ t: Tab) -> some View {
        let selected = (tab == t)
        return Button {
            tab = t
        } label: {
            HStack(spacing: 6) {
                Image(systemName: t.systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(t.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save bar

    private var saveBar: some View {
        HStack(spacing: 8) {
            Image(systemName: isDirty ? "circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(isDirty ? Color.orange : Color.green)
            Text(isDirty ? "Unsaved changes" : "Saved")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Revert") { draft = config.config }
                .controlSize(.small)
                .disabled(!isDirty)
            Button("Save") { config.save(draft) }
                .controlSize(.small)
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isDirty ? Color.orange.opacity(0.06) : Color.clear)
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .pomodoro: PomodoroSettingsForm(draft: $draft)
        case .tracker:  TrackerSettingsForm(draft: $draft)
        case .uploader: UploaderSettingsForm(draft: $draft)
        case .hotkey:   HotkeySettingsForm(draft: $draft)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").foregroundStyle(.tertiary)
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
        let url = Paths.configFile
        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            return "→ \(resolved)"
        }
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func revealInFinder() {
        let url = Paths.configFile
        let resolved = (try? URL(fileURLWithPath: FileManager.default
            .destinationOfSymbolicLink(atPath: url.path))) ?? url
        NSWorkspace.shared.activateFileViewerSelecting([resolved])
    }

    private func openInEditor() {
        NSWorkspace.shared.open(Paths.configFile)
    }
}
