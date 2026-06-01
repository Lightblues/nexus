import Foundation

/// JSON-backed config service with hot-reload via DispatchSourceFileSystemObject.
/// Reads from `~/Library/Application Support/site.easonsi.nexus/config.json`; on
/// missing file, copies the bundled default-config.json. Provides save() for the
/// Settings GUI.
@MainActor
final class ConfigService: ObservableObject {
    @Published private(set) var config: AppConfig = AppConfig()

    private var fileSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    /// Set true while we're writing the file ourselves, so the file watcher
    /// doesn't immediately trigger a reload that races with our write.
    private var suppressNextReload = false

    init() {}

    /// Load on launch + start watching the file. Idempotent.
    func bootstrap() {
        ensureConfigFileExists()
        load()
        startWatching()
    }

    func reloadNow() { load() }

    /// Persist a new config value and write to disk atomically.
    /// Triggers the next file-watcher event but suppresses its reload to avoid
    /// re-decoding what we just encoded.
    /// On mackup symlinks, follows the link so the real backed-up file gets
    /// updated (replaceItemAt would replace the link itself).
    func save(_ newValue: AppConfig) {
        guard newValue != config else { return }
        config = newValue
        do {
            let data = try Self.encoder.encode(newValue)
            suppressNextReload = true
            let url = Paths.configFile
            let target = (try? URL(fileURLWithPath: FileManager.default
                .destinationOfSymbolicLink(atPath: url.path))) ?? url
            try data.write(to: target, options: .atomic)
            Log.config.info("Config saved")
        } catch {
            Log.config.error("Config save failed: \(error)")
            suppressNextReload = false
        }
    }

    // MARK: - Internals

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private func ensureConfigFileExists() {
        let fm = FileManager.default
        let url = Paths.configFile
        if fm.fileExists(atPath: url.path) { return }
        guard let bundled = Bundle.main.url(forResource: "default-config", withExtension: "json") else {
            Log.config.warn("default-config.json not found in bundle; writing minimal defaults")
            try? Self.encoder.encode(AppConfig()).write(to: url)
            return
        }
        do {
            try fm.copyItem(at: bundled, to: url)
            Log.config.info("Seeded config.json from bundled defaults")
        } catch {
            Log.config.error("Failed seeding config.json: \(error)")
        }
    }

    private func load() {
        let url = Paths.configFile
        do {
            let data = try Data(contentsOf: url)
            let loaded = try Self.decoder.decode(AppConfig.self, from: data)
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
        if suppressNextReload {
            suppressNextReload = false
            return
        }
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
