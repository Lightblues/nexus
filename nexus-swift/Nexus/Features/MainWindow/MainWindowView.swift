import SwiftUI

/// Sidebar nav + content host. Stats and Settings show placeholders until the next phases.
struct MainWindowView: View {
    @State private var route: MainRoute = .stats

    var body: some View {
        NavigationSplitView {
            List(MainRoute.allCases, selection: $route) { r in
                NavigationLink(value: r) {
                    Label(r.label, systemImage: r.systemImage)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch route {
            case .stats:
                StatsView()
            case .tracker:
                TrackerView()
            case .settings:
                SettingsView()
            }
        }
        .navigationTitle(route.label)
        .frame(minWidth: 700, minHeight: 400)
    }
}

private struct ComingSoonView: View {
    let title: String
    let note: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title).font(.title2).bold()
            Text(note)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
