import Foundation
import AppKit

/// Handles `nexus://command/<id>?<args>` URLs via NSAppleEventManager.
///
/// Info.plist already declares the `nexus` scheme. This class registers a
/// kAEGetURL Apple Event handler at app launch; macOS LaunchServices forwards
/// any matching URL (from `open nexus://...`, Shortcuts.app, Raycast Quicklink,
/// etc.) to that handler.
///
/// Single-instance lock isn't needed because LaunchServices automatically
/// reuses the running app for all `nexus://` URLs.
@MainActor
final class URLSchemeHandler: NSObject {
    static let shared = URLSchemeHandler()

    private override init() {}

    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        Log.app.info("URL scheme handler installed")
    }

    // MARK: - Apple Event handler

    @objc private func handle(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?
                .stringValue,
              let url = URL(string: urlString)
        else {
            Log.app.warn("Received Apple Event with no URL")
            return
        }
        dispatch(url: url)
    }

    /// Public entry — also called from AppDelegate on launch when the URL
    /// arrives before our handler is installed (rare, but possible on cold
    /// start via `open nexus://...`).
    enum Parsed: Equatable {
        case command(String)
        case notNexus
        case unsupportedHost(String?)
        case emptyID
    }

    nonisolated static func parse(_ url: URL) -> Parsed {
        guard url.scheme == "nexus" else { return .notNexus }
        guard url.host == "command" else { return .unsupportedHost(url.host) }
        // url.path is "/<id>" — strip the leading slash.
        let id = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return id.isEmpty ? .emptyID : .command(id)
    }

    func dispatch(url: URL) {
        let id: String
        switch Self.parse(url) {
        case .notNexus:
            Log.app.warn("Ignoring non-nexus URL: \(url)")
            return
        case .unsupportedHost(let host):
            Log.app.warn("Unsupported nexus URL host: \(host ?? "(nil)")")
            return
        case .emptyID:
            Log.app.warn("Empty command id in URL: \(url)")
            return
        case .command(let found):
            id = found
        }
        guard let cmd = CommandRegistry.shared.find(id: id) else {
            Log.app.warn("Unknown command: \(id)")
            return
        }
        // TODO Phase 4.x: confirm UI for `dangerous` commands triggered
        // externally. For now we just log + run.
        if cmd.dangerous {
            Log.app.warn("Running dangerous command from URL scheme: \(id)")
        }
        Task { @MainActor in
            await cmd.run()
        }
    }
}
