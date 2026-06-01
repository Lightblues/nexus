import Foundation

/// Registers Pomodoro-related commands with the shared CommandRegistry.
/// Commands close over the service so subtitles can read live state.
@MainActor
enum PomodoroCommands {
    static func register(service: PomodoroService) {
        let registry = CommandRegistry.shared
        let g = "Pomodoro"

        registry.register(Command(
            id: "pomodoro.toggle",
            title: { [weak service] in
                // Title tracks the action the user will trigger next,
                // so 'Pomodoro: Pause' shows up while running etc.
                guard let service else { return "Pomodoro: Toggle" }
                switch service.state {
                case .idle:                 return "Pomodoro: Start Focus"
                case .running:              return "Pomodoro: Pause"
                case .paused:               return "Pomodoro: Resume"
                case .finished:             return "Pomodoro: Start Next"
                }
            },
            group: g,
            keywords: ["focus", "start", "pause", "resume", "toggle"],
            when: { true },
            subtitle: { [weak service] in
                guard let service else { return nil }
                switch service.state {
                case .idle:
                    return "idle · ↵ to start"
                case .running(_, _, _):
                    return "running · \(PomodoroService.formatMMSS(service.remaining))"
                case .paused(_, let elapsed, let total):
                    let remain = max(0, total - elapsed)
                    return "paused · \(PomodoroService.formatMMSS(remain))"
                case .finished:
                    return "finished · ↵ to start next"
                }
            },
            run: { [weak service] in
                guard let service else { return }
                switch service.state {
                case .idle:                 service.start(kind: .work)
                case .running:              service.pause()
                case .paused:               service.resume()
                case .finished:             service.start(kind: .work)
                }
            }
        ))

        registry.register(Command(
            id: "pomodoro.start",
            title: "Pomodoro: Start Focus",
            group: g,
            keywords: ["work", "begin"],
            when: { [weak service] in
                guard let service else { return false }
                if case .idle = service.state { return true }
                if case .finished = service.state { return true }
                return false
            },
            run: { [weak service] in service?.start(kind: .work) }
        ))

        registry.register(Command(
            id: "pomodoro.pause",
            title: "Pomodoro: Pause",
            group: g,
            when: { [weak service] in
                guard let service else { return false }
                if case .running = service.state { return true }
                return false
            },
            run: { [weak service] in service?.pause() }
        ))

        registry.register(Command(
            id: "pomodoro.resume",
            title: "Pomodoro: Resume",
            group: g,
            when: { [weak service] in
                guard let service else { return false }
                if case .paused = service.state { return true }
                return false
            },
            run: { [weak service] in service?.resume() }
        ))

        registry.register(Command(
            id: "pomodoro.finishEarly",
            title: "Pomodoro: Finish Early",
            group: g,
            keywords: ["stop", "end"],
            when: { [weak service] in
                guard let service else { return false }
                switch service.state {
                case .running(let kind, _, _) where kind == .work: return true
                case .paused(let kind, _, _) where kind == .work: return true
                default: return false
                }
            },
            run: { [weak service] in
                guard let service else { return }
                await service.finishEarly()
            }
        ))

        registry.register(Command(
            id: "pomodoro.exit",
            title: "Pomodoro: Exit Session",
            group: g,
            keywords: ["abort", "discard"],
            dangerous: true,
            when: { [weak service] in
                guard let service else { return false }
                switch service.state {
                case .running, .paused: return true
                default: return false
                }
            },
            run: { [weak service] in service?.exit() }
        ))
    }
}
