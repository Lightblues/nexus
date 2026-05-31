import Foundation

/// Mirrors `config.yaml` schema. See ../resources/default-config.yaml or
/// ../.ea/spec/swift/architecture.md.
struct AppConfig: Codable, Equatable {
    var pomodoro: PomodoroConfig = .init()
    var ui: UIConfig = .init()
    var tracker: TrackerConfig = .init()
    var hotkey: HotkeyConfig = .init()
    var uploader: UploaderConfig = .init()
}

struct PomodoroConfig: Codable, Equatable {
    var workDuration: Int = 25                     // minutes
    var shortBreakDuration: Int = 5
    var longBreakDuration: Int = 15
    var sessionsBeforeLongBreak: Int = 4
    var projects: [ProjectConfig] = [.init(name: "default", color: "#3B82F6")]
    var tags: [String] = ["work", "study", "personal"]
    var showPopoverOnComplete: Bool = false
    var autoStartBreak: Bool = true
    var autoStartBreakDelay: Int = 3               // seconds
    var confettiOnComplete: Bool = true
}

struct ProjectConfig: Codable, Equatable, Identifiable {
    var name: String
    var color: String
    var id: String { name }
}

struct UIConfig: Codable, Equatable {
    var windowWidth: Int = 320
    var windowHeight: Int = 400
    var openAtLogin: Bool = true
}

struct TrackerConfig: Codable, Equatable {
    var enabled: Bool = true
    var pollInterval: Int = 5
    var idleThreshold: Int = 120
    var recordTitle: Bool = false
    var enrichApps: [String] = ["Code", "Google Chrome"]
}

struct HotkeyConfig: Codable, Equatable {
    var palette: String = "CommandOrControl+Shift+Space"
}

struct UploaderConfig: Codable, Equatable {
    var enabled: Bool = true
    var github: GitHubConfig = .init()
    var cdn: CDNConfig = .init()
    var compress: CompressConfig = .init()
    var defaultPath: String = "upload"
    var cacheThumbnails: Bool = true
}

struct GitHubConfig: Codable, Equatable {
    var token: String = ""
    var owner: String = ""
    var repo: String = ""
    var branch: String = "main"
}

struct CDNConfig: Codable, Equatable {
    var baseUrl: String = "https://cdn.jsdelivr.net/gh"
}

struct CompressConfig: Codable, Equatable {
    var quality: Int = 80
    var defaultFormat: String = "auto"
}
