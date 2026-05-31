import SwiftUI

struct PomodoroPopoverView: View {
    @EnvironmentObject var pomodoro: PomodoroService
    @EnvironmentObject var repo: PomodoroRepository
    @EnvironmentObject var config: ConfigService

    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 12) {
            header
            todaySummary
            ProgressRing(
                progress: progress,
                state: pomodoro.state,
                label: PomodoroService.formatMMSS(pomodoro.remaining)
            )
            .frame(width: 160, height: 160)
            sessionInfoCard
            actionButtons
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 320, height: 400)
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

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text(stateLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(stateColor)
            Spacer()
            Text("#\(todayCount)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var todaySummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(todayCount) sessions")
                    .font(.system(size: 12, weight: .medium))
                Text("today")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(todayDuration))
                    .font(.system(size: 12, weight: .medium))
                Text("focused")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var sessionInfoCard: some View {
        Button(action: { showEditor = true }) {
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
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch pomodoro.state {
        case .idle, .finished:
            Button(action: { pomodoro.start(kind: .work) }) {
                Text("Start Focus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])

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

    // MARK: - Derived state

    private var todayCount: Int { repo.todayCount }
    private var todayDuration: TimeInterval { repo.todayDuration }

    private var progress: Double {
        switch pomodoro.state {
        case .running(_, _, let total), .paused(_, _, let total):
            guard total > 0 else { return 0 }
            return min(1, max(0, 1 - pomodoro.remaining / total))
        case .finished:
            return 1
        case .idle:
            return 0
        }
    }

    private var stateLabel: String {
        switch pomodoro.state {
        case .idle: return "Ready"
        case .running(let k, _, _): return label(for: k)
        case .paused(let k, _, _): return "\(label(for: k)) (paused)"
        case .finished(let k, _, _): return "\(label(for: k)) ✓"
        }
    }

    private func label(for kind: SessionKind) -> String {
        switch kind {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    private var stateColor: Color {
        switch pomodoro.state {
        case .running(let kind, _, _) where kind != .work: return .green
        case .running: return .accentColor
        case .paused: return .orange
        case .finished: return .green
        case .idle: return .secondary
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

private struct ProgressRing: View {
    let progress: Double
    let state: PomodoroState
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: progress)
            VStack(spacing: 2) {
                Text(displayLabel)
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .monospacedDigit()
                if case .finished = state {
                    Text("Finished")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var displayLabel: String {
        if case .idle = state { return "--:--" }
        return label
    }

    private var ringColor: Color {
        switch state {
        case .running(let kind, _, _) where kind != .work: return .green
        case .running: return .accentColor
        case .paused: return .orange
        case .finished: return .green
        case .idle: return .secondary
        }
    }
}
