import Foundation
import AppKit

/// DI container — owns the singleton-style services used across the app.
/// AppDelegate creates one instance, then passes it to view environments and the
/// status item / popover wiring code.
@MainActor
final class AppEnvironment: ObservableObject {
    let config: ConfigService
    let database: Database
    let pomodoroRepository: PomodoroRepository
    let pomodoro: PomodoroService
    let trackerRepository: TrackerRepository
    let tracker: TrackerService
    let notifier: NotificationService
    let mainWindow: MainWindowController

    init() {
        let config = ConfigService()
        let notifier = NotificationService.shared
        // Open DB synchronously — it's tiny and we need it before anything else.
        // If this throws, we crash early with a clear message rather than silently corrupt data.
        let database: Database
        do {
            try Paths.ensureDirectories()
            database = try Database(url: Paths.dbFile)
        } catch {
            fatalError("Failed to open ~/.ea/nexus/nexus.db: \(error)")
        }
        let pomodoroRepository = PomodoroRepository(database: database)
        let trackerRepository = TrackerRepository(database: database)
        self.config = config
        self.database = database
        self.notifier = notifier
        self.pomodoroRepository = pomodoroRepository
        self.trackerRepository = trackerRepository
        self.pomodoro = PomodoroService(repository: pomodoroRepository, config: config, notifier: notifier)
        self.tracker = TrackerService(repository: trackerRepository, config: config)
        self.mainWindow = MainWindowController()
    }

    /// Initial async work that needs `await` — called from AppDelegate.applicationDidFinishLaunching.
    func bootstrap() async {
        config.bootstrap()
        notifier.setup()

        // One-shot import of legacy JSON files. Idempotent.
        _ = await LegacyMigration.runIfNeeded(db: database)

        await pomodoroRepository.refresh()
        pomodoro.hydrate()

        await trackerRepository.bootstrap()
        await tracker.bootstrap()

        mainWindow.attach(environment: self)

        Log.app.info("Bootstrap complete")
    }

    /// Final flush before terminate.
    func shutdown() async {
        // SQLite WAL is already durable on each commit; nothing to flush.
        await tracker.shutdown()
        Log.app.info("Shutdown complete")
    }
}
