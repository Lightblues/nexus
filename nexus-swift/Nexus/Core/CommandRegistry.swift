import Foundation

/// One palette / URL-scheme command. The same struct backs both the search UI
/// and the `nexus://command/<id>` handler — registry is read-only by both
/// consumers (mirrors Electron ADR-009).
///
/// `title`, `subtitle`, and `when` are all closures so they reflect live state
/// without re-registration. Examples:
///   pomodoro.toggle's title  reads PomodoroService.state to show "Pause" vs "Resume"
///   pomodoro.toggle's subtitle reads .remaining each call
struct Command: Identifiable {
    let id: String                          // e.g. "pomodoro.toggle"
    let title: @MainActor () -> String
    let group: String?
    let keywords: [String]
    let dangerous: Bool
    let when: @MainActor () -> Bool
    let subtitle: @MainActor () -> String?
    let run: @MainActor () async -> Void

    /// Static-title convenience init — most commands have a fixed label.
    init(id: String,
         title: String,
         group: String? = nil,
         keywords: [String] = [],
         dangerous: Bool = false,
         when: @escaping @MainActor () -> Bool = { true },
         subtitle: @escaping @MainActor () -> String? = { nil },
         run: @escaping @MainActor () async -> Void) {
        self.init(id: id,
                  title: { title },
                  group: group,
                  keywords: keywords,
                  dangerous: dangerous,
                  when: when,
                  subtitle: subtitle,
                  run: run)
    }

    /// Dynamic-title init — for commands whose label depends on live state
    /// (e.g. a "Pause / Resume" toggle whose label reflects the current state).
    init(id: String,
         title: @escaping @MainActor () -> String,
         group: String? = nil,
         keywords: [String] = [],
         dangerous: Bool = false,
         when: @escaping @MainActor () -> Bool = { true },
         subtitle: @escaping @MainActor () -> String? = { nil },
         run: @escaping @MainActor () async -> Void) {
        self.id = id
        self.title = title
        self.group = group
        self.keywords = keywords
        self.dangerous = dangerous
        self.when = when
        self.subtitle = subtitle
        self.run = run
    }
}

/// Single source of truth for all registered commands. Features call
/// `register(_:)` from their own *Commands.swift module on bootstrap.
@MainActor
final class CommandRegistry: ObservableObject {
    static let shared = CommandRegistry()

    @Published private(set) var commands: [Command] = []

    private init() {}

    func register(_ command: Command) {
        // Replace if same id already registered (idempotent across reloads).
        if let idx = commands.firstIndex(where: { $0.id == command.id }) {
            commands[idx] = command
        } else {
            commands.append(command)
        }
    }

    func registerMany(_ commands: [Command]) {
        for c in commands { register(c) }
    }

    /// Commands whose `when` predicate evaluates true right now.
    /// Note: this re-runs every call — predicates should be cheap.
    func applicable() -> [Command] {
        commands.filter { $0.when() }
    }

    func find(id: String) -> Command? {
        commands.first(where: { $0.id == id })
    }
}
