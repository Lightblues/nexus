import SwiftUI

/// The menu-bar popover: today's count, the ring, the session card and the actions.
struct PomodoroPopoverView: View {
    @EnvironmentObject var pomodoro: PomodoroService
    @EnvironmentObject var repo: PomodoroRepository
    /// Closes the popover and shows the main window on its Pomodoro page; set by `AppDelegate`.
    let openMainWindow: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header
            todaySummary
            ProgressRing(
                progress: pomodoro.progress,
                state: pomodoro.state,
                label: PomodoroService.formatMMSS(pomodoro.remaining)
            )
            .frame(width: 160, height: 160)
            PomodoroSessionCard()
            PomodoroActionButtons(returnStartsFocus: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 320, height: 400)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(pomodoro.state.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pomodoro.state.color)
            Spacer()
            Text("#\(repo.todayCount)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button(action: openMainWindow) {
                Image(systemName: "macwindow")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Open Main Window")
        }
    }

    /// A click opens the main window, where the history behind these numbers is.
    private var todaySummary: some View {
        Button(action: openMainWindow) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(repo.todayCount) sessions")
                        .font(.system(size: 12, weight: .medium))
                    Text("today")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.formatDuration(repo.todayDuration))
                        .font(.system(size: 12, weight: .medium))
                    Text("focused")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
