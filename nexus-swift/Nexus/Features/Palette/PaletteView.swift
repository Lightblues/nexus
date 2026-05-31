import SwiftUI
import AppKit

/// Palette UI: search field, scored result list, keyboard navigation.
/// Listens for `.paletteDidShow` to refocus + reset query when the panel is
/// summoned (because the panel doesn't get re-created across show/hide).
struct PaletteView: View {
    @EnvironmentObject var registry: CommandRegistry

    @State private var query: String = ""
    @State private var selection: Int = 0
    @FocusState private var searchFocused: Bool

    let onDismiss: () -> Void

    private var matches: [Command] {
        let pool = registry.applicable()
        return PaletteSearch.score(pool, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if matches.isEmpty {
                emptyState
            } else {
                resultList
            }
            Divider()
            footer
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.tertiary.opacity(0.5), lineWidth: 0.5)
        )
        .onAppear {
            searchFocused = true
            selection = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .paletteDidShow)) { _ in
            query = ""
            selection = 0
            searchFocused = true
        }
        .onChange(of: query) { _ in selection = 0 }
        // Hidden buttons own keyboard shortcuts. SwiftUI's macOS-13 .onKeyPress
        // doesn't exist; this is the standard workaround.
        .background(keyboardCommands)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 16))
            TextField("Search Nexus…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($searchFocused)
                .onSubmit(runSelected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Result list

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { idx, cmd in
                        CommandRow(cmd: cmd, isSelected: idx == selection)
                            .id(idx)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = idx
                                runSelected()
                            }
                            .onHover { hovering in
                                if hovering { selection = idx }
                            }
                    }
                }
            }
            .frame(maxHeight: 320)
            .onChange(of: selection) { newValue in
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No commands match \"\(query)\"")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 200)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "house")
                .foregroundStyle(.tertiary)
                .font(.system(size: 11))
            Text("Nexus")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            footerHint(label: "Run", key: "↵")
            footerHint(label: "Navigate", key: "↑↓")
            footerHint(label: "Close", key: "esc")
            Text("\(matches.count) result\(matches.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footerHint(label: String, key: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Keyboard

    private var keyboardCommands: some View {
        // Three invisible buttons whose .keyboardShortcut() captures arrow keys
        // + Esc anywhere within the view. `.return` is handled by TextField's
        // .onSubmit so we don't shadow the search field's enter behavior.
        ZStack {
            Button("") { moveSelection(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
            Button("") { moveSelection(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
            Button("") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .accessibilityHidden(true)
    }

    private func moveSelection(by delta: Int) {
        guard !matches.isEmpty else { return }
        let next = selection + delta
        if next < 0 { selection = matches.count - 1 }
        else if next >= matches.count { selection = 0 }
        else { selection = next }
    }

    private func runSelected() {
        guard matches.indices.contains(selection) else { return }
        let cmd = matches[selection]
        onDismiss()
        Task { @MainActor in
            await cmd.run()
        }
    }
}

private struct CommandRow: View {
    let cmd: Command
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.system(size: 13))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(cmd.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                if let sub = cmd.subtitle() {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let group = cmd.group {
                Text(group)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quinary, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }

    private var icon: String {
        // Map id prefix → SF symbol. Keeps row visually scannable.
        if cmd.id.hasPrefix("pomodoro.") { return "timer" }
        if cmd.id.hasPrefix("tracker.")  { return "clock" }
        if cmd.id.hasPrefix("window.")   { return "macwindow" }
        if cmd.id.hasPrefix("app.")      { return "gearshape" }
        return "command"
    }
}
