import SwiftUI
import NexusSync

/// Settings GUI. Reads from ConfigService into a local `draft`, edits the draft,
/// commits all changes via Save. Eliminates per-keystroke disk writes (the cause
/// of tab-switch lag and excessive ConfigService→form rebind churn).
///
/// The draft is owned by SettingsView so navigating between sub-tabs preserves
/// in-flight edits; all sub-forms bind into the same `$draft`.
struct SettingsView: View {
    @EnvironmentObject var config: ConfigService

    enum Tab: String, CaseIterable, Identifiable {
        case pomodoro, tracker, uploader, hotkey, sync
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pomodoro: return "Pomodoro"
            case .tracker:  return "Tracker"
            case .uploader: return "Uploader"
            case .hotkey:   return "Hotkey"
            case .sync:     return "Sync"
            }
        }
        var systemImage: String {
            switch self {
            case .pomodoro: return "timer"
            case .tracker:  return "clock"
            case .uploader: return "arrow.up.circle"
            case .hotkey:   return "keyboard"
            case .sync:     return "arrow.triangle.2.circlepath"
            }
        }
    }
    @State private var tab: Tab = .pomodoro
    @State private var draft: AppConfig = AppConfig()
    /// The config `draft` was taken from; the user's edits are the keys where they differ.
    @State private var base: AppConfig = AppConfig()
    @State private var initialized = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            if tab != .sync {
                saveBar
                Divider()
            }
            ScrollView { tabContent.padding(20) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !initialized {
                draft = config.config
                base = draft
                initialized = true
            }
        }
        // External changes (sync, the nexus CLI through sync) rebase the draft:
        // keys the user has not edited take the new value, edited keys keep theirs.
        .onChange(of: config.config) { newValue in
            draft = draft.rebased(from: base, onto: newValue)
            base = newValue
        }
    }

    private var isDirty: Bool { draft != base }

    /// Write only the edited keys onto the latest config, never a stale whole draft.
    private func save() {
        let merged = draft.rebased(from: base, onto: config.config)
        config.save(merged)
        draft = merged
        base = merged
    }

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
            Button("Revert") { draft = config.config; base = config.config }
                .controlSize(.small)
                .disabled(!isDirty)
            Button("Save") { save() }
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
        case .sync:     SyncSettingsForm()
        }
    }
}

extension AppConfig {
    /// `latest` with the leaves where `self` differs from `base` (the user's edits) laid on top.
    func rebased(from base: AppConfig, onto latest: AppConfig) -> AppConfig {
        guard self != base else { return latest }
        guard let mine = try? Self.leaves(self), let old = try? Self.leaves(base),
              var merged = try? Self.leaves(latest) else { return self }
        for (key, value) in mine where old[key] != value { merged[key] = value }
        let object = JSONValue.object(Settings.unflatten(merged))
        return (try? JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(object))) ?? self
    }

    private static func leaves(_ config: AppConfig) throws -> [String: JSONValue] {
        try ConfigService.leaves(of: config)
    }
}
