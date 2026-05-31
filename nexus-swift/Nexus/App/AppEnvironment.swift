import Foundation
import AppKit

/// DI container — owns the singleton-style services used across the app.
/// AppDelegate creates one instance, then passes it to view environments and the
/// status item / popover wiring code.
@MainActor
final class AppEnvironment: ObservableObject {
    let config: ConfigService
    let pomodoroStore: PomodoroStore
    let pomodoro: PomodoroService
    let notifier: NotificationService

    init() {
        let config = ConfigService()
        let pomodoroStore = PomodoroStore()
        let notifier = NotificationService.shared
        self.config = config
        self.pomodoroStore = pomodoroStore
        self.notifier = notifier
        self.pomodoro = PomodoroService(store: pomodoroStore, config: config, notifier: notifier)
    }

    /// Initial async work that needs `await` — called from AppDelegate.applicationDidFinishLaunching.
    func bootstrap() async {
        do {
            try Paths.ensureDirectories()
        } catch {
            Log.app.error("Failed creating ~/.ea/nexus/ subdirs: \(error)")
        }
        config.bootstrap()
        notifier.setup()
        await pomodoroStore.load()
        await pomodoroStore.runArchiveSweep()
        // Now that the store is loaded, push lastSession metadata into the service.
        pomodoro.hydrateFromStore()
        Log.app.info("Bootstrap complete")
    }

    /// Final flush before terminate.
    func shutdown() async {
        await pomodoroStore.flushNow()
        Log.app.info("Shutdown flushed")
    }
}
