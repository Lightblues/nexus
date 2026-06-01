import Foundation

/// Top-level routes inside the main window. Maps onto the Electron hash router
/// (`#/stats`, `#/tracker`, `#/settings`).
enum MainRoute: String, CaseIterable, Identifiable {
    case stats
    case tracker
    case uploader
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stats:    return "Statistics"
        case .tracker:  return "Time Tracker"
        case .uploader: return "Image Uploader"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .stats:    return "chart.bar.fill"
        case .tracker:  return "clock.fill"
        case .uploader: return "photo.on.rectangle"
        case .settings: return "gearshape.fill"
        }
    }
}
