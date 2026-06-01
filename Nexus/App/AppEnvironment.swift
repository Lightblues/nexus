import Foundation
import AppKit
import Combine

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
    let uploaderRepository: UploaderRepository
    let uploader: UploaderService
    let notifier: NotificationService
    let mainWindow: MainWindowController
    let palette: PaletteController

    init() {
        let config = ConfigService()
        let notifier = NotificationService.shared
        let database: Database
        do {
            try Paths.ensureDirectories()
            database = try Database(url: Paths.dbFile)
        } catch {
            fatalError("Failed to open nexus.db at \(Paths.dbFile.path): \(error)")
        }
        let pomodoroRepository = PomodoroRepository(database: database)
        let trackerRepository = TrackerRepository(database: database)
        let uploaderRepository = UploaderRepository(database: database)
        self.config = config
        self.database = database
        self.notifier = notifier
        self.pomodoroRepository = pomodoroRepository
        self.trackerRepository = trackerRepository
        self.uploaderRepository = uploaderRepository
        self.pomodoro = PomodoroService(repository: pomodoroRepository, config: config, notifier: notifier)
        self.tracker = TrackerService(repository: trackerRepository, config: config)
        self.uploader = UploaderService(repository: uploaderRepository, config: config)
        self.mainWindow = MainWindowController()
        self.palette = PaletteController()
    }

    /// Initial async work that needs `await` — called from AppDelegate.applicationDidFinishLaunching.
    func bootstrap() async {
        config.bootstrap()
        notifier.setup()

        // After session data is in DB, populate project + tag catalogs.
        await CatalogMigration.runIfNeeded(db: database)

        await pomodoroRepository.refresh()
        pomodoro.hydrate()

        await trackerRepository.bootstrap()
        await tracker.bootstrap()
        await uploader.bootstrap()

        mainWindow.attach(environment: self)
        palette.attach(environment: self)

        // Register palette + URL-scheme commands. Order doesn't matter; each
        // call is idempotent (registry replaces by id).
        PomodoroCommands.register(service: pomodoro)
        TrackerCommands.register(service: tracker, mainWindow: mainWindow)
        UploaderCommands.register(service: uploader, mainWindow: mainWindow)
        WindowCommands.register(mainWindow: mainWindow)
        AppCommands.register()

        // URL scheme handler — listens for `nexus://command/<id>` from
        // Shortcuts.app, terminal `open`, Raycast Quicklink, etc.
        URLSchemeHandler.shared.install()

        // Global hotkey for the palette. Re-bound below on config change.
        installHotkey()
        // Re-install on config.hotkey.palette change.
        config.$config
            .map(\.hotkey.palette)
            .removeDuplicates()
            .dropFirst()  // skip initial value (already installed above)
            .sink { [weak self] _ in self?.installHotkey() }
            .store(in: &cancellables)

        Log.app.info("Bootstrap complete")
    }

    private func installHotkey() {
        HotKey.shared.set(combo: config.config.hotkey.palette) { [weak self] in
            self?.palette.toggle()
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    /// Final flush before terminate.
    func shutdown() async {
        // SQLite WAL is already durable on each commit; nothing to flush.
        await tracker.shutdown()
        Log.app.info("Shutdown complete")
    }
}
