import SwiftUI

/// Sidebar nav + content host. Sections group related routes for visual scannability.
///
/// We bind `columnVisibility` to local state so the sidebar can be programmatically
/// shown again — important because users can drag the sidebar to zero width, after
/// which `NavigationSplitView` alone doesn't give a way back. Our toolbar button
/// flips this state, and ⌃⌘S works as a keyboard shortcut.
struct MainWindowView: View {
    @State private var route: MainRoute = .stats
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            List(selection: $route) {
                Section("Activity") {
                    sidebarItem(.stats)
                    sidebarItem(.tracker)
                }
                Section("Configuration") {
                    sidebarItem(.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            content
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: toggleSidebar) {
                            Image(systemName: "sidebar.left")
                        }
                        .help("Toggle Sidebar")
                        .keyboardShortcut("s", modifiers: [.command, .control])
                    }
                }
        }
        .navigationTitle(route.label)
        .frame(minWidth: 700, minHeight: 400)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .stats:    StatsView()
        case .tracker:  TrackerView()
        case .settings: SettingsView()
        }
    }

    private func sidebarItem(_ r: MainRoute) -> some View {
        NavigationLink(value: r) {
            Label(r.label, systemImage: r.systemImage)
        }
    }

    /// Toggle the sidebar with animation.
    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch sidebarVisibility {
            case .detailOnly:
                sidebarVisibility = .all
            default:
                sidebarVisibility = .detailOnly
            }
        }
    }
}
