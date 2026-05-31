import Foundation
import Yams

/// YAML-backed config service with hot-reload via DispatchSourceFileSystemObject.
/// Mirrors Electron `ConfigManager.ts`. Reads from ~/.ea/nexus/config.yaml; on
/// missing file, copies the bundled default-config.yaml to that location.
@MainActor
final class ConfigService: ObservableObject {
    @Published private(set) var config: AppConfig = AppConfig()

    private var fileSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?

    init() {}

    /// Load on launch + start watching the file. Idempotent.
    func bootstrap() {
        ensureConfigFileExists()
        load()
        startWatching()
    }

    func reloadNow() { load() }

    // MARK: - Internals

    private func ensureConfigFileExists() {
        let fm = FileManager.default
        let url = Paths.configFile
        if fm.fileExists(atPath: url.path) { return }
        guard let bundled = Bundle.main.url(forResource: "default-config", withExtension: "yaml") else {
            Log.config.warn("default-config.yaml not found in bundle; writing minimal defaults")
            try? "".write(to: url, atomically: true, encoding: .utf8)
            return
        }
        do {
            try fm.copyItem(at: bundled, to: url)
            Log.config.info("Seeded config.yaml from bundled defaults")
        } catch {
            Log.config.error("Failed seeding config.yaml: \(error)")
        }
    }

    private func load() {
        let url = Paths.configFile
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let loaded = try YAMLDecoder().decode(AppConfig.self, from: text)
            self.config = loaded
            Log.config.info("Config loaded")
        } catch {
            Log.config.error("Config load failed: \(error). Using last good / defaults.")
        }
    }

    private func startWatching() {
        let url = Paths.configFile
        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else {
            Log.config.warn("Cannot open config for watching: \(url.path)")
            return
        }
        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        self.fileSource = source
    }

    private func scheduleReload() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.load()
            // If watcher target was deleted/renamed, restart.
            if !FileManager.default.fileExists(atPath: Paths.configFile.path) {
                self.fileSource?.cancel()
                self.fileSource = nil
                self.ensureConfigFileExists()
                self.startWatching()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
    }

    deinit {
        fileSource?.cancel()
    }
}
