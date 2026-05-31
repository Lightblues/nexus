import Foundation

enum SessionKind: String, Codable, Equatable, CaseIterable {
    case work
    case shortBreak
    case longBreak
}

struct SessionMetadata: Codable, Equatable {
    var project: String?
    var tags: [String] = []
    var task: String?

    static let empty = SessionMetadata()
}

struct SessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: SessionKind
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval         // seconds
    var project: String?
    var tags: [String]
    var task: String?
    var completedFully: Bool
}

struct PomodoroMeta: Codable, Equatable {
    var lastSession: SessionMetadata = .empty
    var sessionsSinceLongBreak: Int = 0
}

struct PomodoroData: Codable, Equatable {
    var sessions: [SessionRecord] = []
    var meta: PomodoroMeta = .init()
    var schemaVersion: Int = 1
}

/// View-state-friendly enum the popover binds to.
enum PomodoroState: Equatable {
    case idle
    case running(kind: SessionKind, startedAt: Date, totalDuration: TimeInterval)
    case paused(kind: SessionKind, elapsedAtPause: TimeInterval, totalDuration: TimeInterval)
    case finished(kind: SessionKind, completedFully: Bool, autoNextAt: Date?)

    var kind: SessionKind? {
        switch self {
        case .idle: return nil
        case .running(let k, _, _), .paused(let k, _, _), .finished(let k, _, _): return k
        }
    }

    var isWork: Bool { kind == .work }
    var isRunning: Bool {
        if case .running = self { return true } else { return false }
    }
    var isPaused: Bool {
        if case .paused = self { return true } else { return false }
    }
}
