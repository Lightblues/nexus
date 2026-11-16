import AppKit
import SwiftUI

/// Pieces shared by the menu-bar popover and the Pomodoro page of the main window,
/// so both drive `PomodoroService` the same way.

extension PomodoroState {
    var title: String {
        switch self {
        case .idle: return "Ready"
        case .running(let k, _, _): return k.title
        case .paused(let k, _, _): return "\(k.title) (paused)"
        case .finished(let k, _, _): return "\(k.title) ✓"
        }
    }

    var color: Color {
        switch self {
        case .running(let kind, _, _) where kind != .work: return .green
        case .running: return .accentColor
        case .paused: return .orange
        case .finished: return .green
        case .idle: return .secondary
        }
    }
}

extension SessionKind {
    var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

extension PomodoroService {
    /// Share of the current session done, 0...1.
    var progress: Double {
        switch state {
        case .running(_, _, let total), .paused(_, _, let total):
            guard total > 0 else { return 0 }
            return min(1, max(0, 1 - remaining / total))
        case .finished: return 1
        case .idle: return 0
        }
    }
}

/// Project and tags for the next or current session; a click opens the editor sheet.
struct PomodoroSessionCard: View {
    @EnvironmentObject var pomodoro: PomodoroService
    @EnvironmentObject var repo: PomodoroRepository
    @State private var showEditor = false

    var body: some View {
        Button(action: {
            // The sheet's TextFields need key focus. Activate here and only here, so opening
            // the popover never takes focus from the app in front (pitfalls §3.4).
            NSApp.activate(ignoringOtherApps: true)
            showEditor = true
        }) {
            HStack(spacing: 6) {
                Text(pomodoro.draftMetadata.project ?? "default")
                    .font(.system(size: 11, weight: .medium))
                if !pomodoro.draftMetadata.tags.isEmpty {
                    Text("·").foregroundStyle(.secondary).font(.system(size: 11))
                    Text(pomodoro.draftMetadata.tags.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditor) {
            EditSessionModal(metadata: pomodoro.draftMetadata) { meta in
                Task { await pomodoro.updateDraftMetadata(meta) }
                showEditor = false
            } onCancel: {
                showEditor = false
            }
            .environmentObject(repo)
        }
    }
}

/// Start / Pause / Resume / Finish / Skip / Exit for the current state.
struct PomodoroActionButtons: View {
    @EnvironmentObject var pomodoro: PomodoroService
    /// Return starts focus. Only the popover sets it: it is opened on purpose, and nothing
    /// in it takes text, while the main window has other controls.
    var returnStartsFocus = false

    var body: some View {
        switch pomodoro.state {
        case .idle, .finished:
            Button(action: { pomodoro.start(kind: .work) }) {
                Text("Start Focus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(returnStartsFocus ? KeyboardShortcut(.return, modifiers: []) : nil)

        case .running(let kind, _, _):
            HStack(spacing: 8) {
                Button("Pause") { pomodoro.pause() }
                    .frame(maxWidth: .infinity)
                if kind == .work {
                    Button("Finish") { Task { await pomodoro.finishEarly() } }
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Skip") { pomodoro.skipBreak() }
                        .frame(maxWidth: .infinity)
                }
                Button("Exit") { pomodoro.exit() }
                    .frame(maxWidth: .infinity)
            }

        case .paused:
            HStack(spacing: 8) {
                Button("Resume") { pomodoro.resume() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Finish") { Task { await pomodoro.finishEarly() } }
                    .frame(maxWidth: .infinity)
                Button("Exit") { pomodoro.exit() }
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let state: PomodoroState
    let label: String
    var lineWidth: CGFloat = 8
    var fontSize: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(state.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: progress)
            VStack(spacing: 2) {
                Text(state == .idle ? "--:--" : label)
                    .font(.system(size: fontSize, weight: .light, design: .rounded))
                    .monospacedDigit()
                if case .finished = state {
                    Text("Finished")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
