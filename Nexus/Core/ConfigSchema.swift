import Foundation

/// The app's settings; stored as leaves in nexus.db (`ConfigService`) and synced per leaf.
///
/// All structs use Codable with explicit `init(from:)` so that *any* missing field
/// falls back to its default value: a leaf added in a newer version, or one a sync
/// from an older version never sent, decodes to its default.
struct AppConfig: Codable, Equatable {
    var pomodoro: PomodoroConfig = .init()
    var ui: UIConfig = .init()
    var tracker: TrackerConfig = .init()
    var hotkey: HotkeyConfig = .init()
    var uploader: UploaderConfig = .init()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pomodoro = (try? c.decode(PomodoroConfig.self, forKey: .pomodoro)) ?? .init()
        ui       = (try? c.decode(UIConfig.self, forKey: .ui))       ?? .init()
        tracker  = (try? c.decode(TrackerConfig.self, forKey: .tracker)) ?? .init()
        hotkey   = (try? c.decode(HotkeyConfig.self, forKey: .hotkey)) ?? .init()
        uploader = (try? c.decode(UploaderConfig.self, forKey: .uploader)) ?? .init()
    }

    /// Rewrites values that were defaults in an older version to today's defaults.
    func upgraded() -> AppConfig {
        var out = self
        if out.tracker.enrichApps == TrackerConfig.legacyEnrichApps { out.tracker.enrichApps = TrackerConfig.defaultEnrichApps }
        return out
    }
}

struct PomodoroConfig: Codable, Equatable {
    var workDuration: Int = 25                     // minutes
    var shortBreakDuration: Int = 5
    var longBreakDuration: Int = 15
    var sessionsBeforeLongBreak: Int = 4
    var showPopoverOnComplete: Bool = false
    var autoStartBreak: Bool = true
    var autoStartBreakDelay: Int = 3               // seconds
    var confettiOnComplete: Bool = true

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workDuration = (try? c.decode(Int.self, forKey: .workDuration)) ?? 25
        shortBreakDuration = (try? c.decode(Int.self, forKey: .shortBreakDuration)) ?? 5
        longBreakDuration = (try? c.decode(Int.self, forKey: .longBreakDuration)) ?? 15
        sessionsBeforeLongBreak = (try? c.decode(Int.self, forKey: .sessionsBeforeLongBreak)) ?? 4
        showPopoverOnComplete = (try? c.decode(Bool.self, forKey: .showPopoverOnComplete)) ?? false
        autoStartBreak = (try? c.decode(Bool.self, forKey: .autoStartBreak)) ?? true
        autoStartBreakDelay = (try? c.decode(Int.self, forKey: .autoStartBreakDelay)) ?? 3
        confettiOnComplete = (try? c.decode(Bool.self, forKey: .confettiOnComplete)) ?? true
    }
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

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windowWidth = (try? c.decode(Int.self, forKey: .windowWidth)) ?? 320
        windowHeight = (try? c.decode(Int.self, forKey: .windowHeight)) ?? 400
        openAtLogin = (try? c.decode(Bool.self, forKey: .openAtLogin)) ?? true
    }
}

struct TrackerConfig: Codable, Equatable {
    var enabled: Bool = true
    var pollInterval: Int = 5
    var idleThreshold: Int = 120
    var recordTitle: Bool = false
    var enrichApps: [String] = TrackerConfig.defaultEnrichApps

    /// Every app `ContextEnricher` knows how to enrich, by the name the probe reports.
    static let defaultEnrichApps = ["Code", "Code - Insiders", "Cursor", "Google Chrome", "Google Chrome Beta", "Safari", "Arc"]
    /// The default before v1.3.2, when the editors and browsers above were enriched regardless of the list.
    static let legacyEnrichApps = ["Code", "Google Chrome"]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        pollInterval = (try? c.decode(Int.self, forKey: .pollInterval)) ?? 5
        idleThreshold = (try? c.decode(Int.self, forKey: .idleThreshold)) ?? 120
        recordTitle = (try? c.decode(Bool.self, forKey: .recordTitle)) ?? false
        enrichApps = (try? c.decode([String].self, forKey: .enrichApps)) ?? TrackerConfig.defaultEnrichApps
    }
}

struct HotkeyConfig: Codable, Equatable {
    var palette: String = "CommandOrControl+Shift+Space"

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        palette = (try? c.decode(String.self, forKey: .palette)) ?? "CommandOrControl+Shift+Space"
    }
}

struct UploaderConfig: Codable, Equatable {
    var enabled: Bool = true
    var github: GitHubConfig = .init()
    var cdn: CDNConfig = .init()
    var compress: CompressConfig = .init()
    var defaultPath: String = "upload"
    var cacheThumbnails: Bool = true

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        github = (try? c.decode(GitHubConfig.self, forKey: .github)) ?? .init()
        cdn = (try? c.decode(CDNConfig.self, forKey: .cdn)) ?? .init()
        compress = (try? c.decode(CompressConfig.self, forKey: .compress)) ?? .init()
        defaultPath = (try? c.decode(String.self, forKey: .defaultPath)) ?? "upload"
        cacheThumbnails = (try? c.decode(Bool.self, forKey: .cacheThumbnails)) ?? true
    }
}

struct GitHubConfig: Codable, Equatable {
    var token: String = ""
    var owner: String = ""
    var repo: String = ""
    var branch: String = "main"

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = (try? c.decode(String.self, forKey: .token)) ?? ""
        owner = (try? c.decode(String.self, forKey: .owner)) ?? ""
        repo = (try? c.decode(String.self, forKey: .repo)) ?? ""
        branch = (try? c.decode(String.self, forKey: .branch)) ?? "main"
    }
}

struct CDNConfig: Codable, Equatable {
    var baseUrl: String = "https://cdn.jsdelivr.net/gh"

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseUrl = (try? c.decode(String.self, forKey: .baseUrl)) ?? "https://cdn.jsdelivr.net/gh"
    }
}

struct CompressConfig: Codable, Equatable {
    var quality: Int = 80
    var defaultFormat: String = "auto"

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quality = (try? c.decode(Int.self, forKey: .quality)) ?? 80
        defaultFormat = (try? c.decode(String.self, forKey: .defaultFormat)) ?? "auto"
    }
}
