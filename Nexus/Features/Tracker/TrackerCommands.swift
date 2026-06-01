import Foundation

@MainActor
enum TrackerCommands {
    static func register(service: TrackerService, mainWindow: MainWindowController) {
        let registry = CommandRegistry.shared
        let g = "Tracker"

        registry.register(Command(
            id: "tracker.openToday",
            title: "Tracker: Open Today",
            group: g,
            keywords: ["activity", "stats"],
            run: { [weak mainWindow] in
                mainWindow?.show(route: .tracker)
            }
        ))

        registry.register(Command(
            id: "tracker.toggle",
            title: "Tracker: Toggle Status",
            group: g,
            subtitle: { [weak service] in
                guard let service else { return nil }
                switch service.status {
                case .running: return "currently tracking"
                case .stopped: return "currently disabled"
                case .idle: return "user idle — paused"
                case .waitingForPermission: return "needs Accessibility"
                }
            },
            run: { [weak service] in
                // We don't expose enable/disable on the service directly;
                // for now, opening the tracker tab + accessibility settings
                // is the common case. Future: a dedicated toggle.
                _ = service
            }
        ))
    }
}
