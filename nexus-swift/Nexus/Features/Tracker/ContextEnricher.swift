import Foundation

/// Adds project/file/url/domain context to a probe based on app type.
/// - VSCode/Cursor: parses window title in "filename — project" form
/// - Browsers: extracts URL via cached NSAppleScript (one compile per browser)
/// - Other apps: rawTitle only
@MainActor
final class ContextEnricher {
    private static let enrichBundleIds: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.apple.Safari",
        "company.thebrowser.Browser"      // Arc
    ]

    private static let vscodeFamily: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92"
    ]

    /// Cache compiled AppleScripts so we don't pay the parse cost every poll.
    /// Key is bundle id; value is a script that returns the active tab URL.
    private var compiledScripts: [String: NSAppleScript] = [:]

    /// Set true after the first time `NSAppleEventsUsageDescription` was used.
    /// Doesn't actually inspect TCC — we just don't retry on persistent errors.
    private var appleEventsBlocked: Set<String> = []

    /// Enrich an existing probe in place. May fetch URL via Apple Events.
    func enrich(_ probe: ActiveProbe, config: TrackerConfig) -> (probe: ActiveProbe, context: ActivityContext?) {
        var probe = probe
        let shouldEnrich = (probe.bundleId.map(Self.enrichBundleIds.contains) ?? false)
            || config.enrichApps.contains(probe.app)
        guard shouldEnrich else { return (probe, nil) }

        // Browser URL
        if let bid = probe.bundleId, Self.isBrowser(bundleId: bid) {
            probe.url = fetchBrowserURL(bundleId: bid)
        }

        var ctx = ActivityContext()
        if let title = probe.title {
            ctx.rawTitle = title
        }

        // VSCode/Cursor title: "filename — project"  (em-dash separator)
        if let bid = probe.bundleId, Self.vscodeFamily.contains(bid), let title = probe.title {
            let parts = title.components(separatedBy: " — ")
            if parts.count >= 2 {
                ctx.file = parts.first?.trimmingCharacters(in: .whitespaces)
                ctx.project = parts.last?.trimmingCharacters(in: .whitespaces)
            } else if let first = parts.first {
                ctx.file = first.trimmingCharacters(in: .whitespaces)
            }
        }

        // Browser: store URL/domain, fall back to title for `file`
        if let url = probe.url, !url.isEmpty {
            ctx.url = url
            if let host = URL(string: url)?.host {
                ctx.domain = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            }
            if ctx.file == nil, let title = probe.title { ctx.file = title }
        }

        return (probe, ctx.isEmpty ? nil : ctx)
    }

    // MARK: - Internals

    private static func isBrowser(bundleId: String) -> Bool {
        bundleId.hasPrefix("com.google.Chrome")
            || bundleId == "com.apple.Safari"
            || bundleId == "company.thebrowser.Browser"
    }

    private func fetchBrowserURL(bundleId: String) -> String? {
        if appleEventsBlocked.contains(bundleId) { return nil }
        let script: NSAppleScript
        if let cached = compiledScripts[bundleId] {
            script = cached
        } else {
            guard let source = Self.urlScript(for: bundleId) else { return nil }
            guard let s = NSAppleScript(source: source) else { return nil }
            compiledScripts[bundleId] = s
            script = s
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            // -1743 = not authorized to send Apple Events; -600 = app not running.
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -1743 {
                Log.tracker.warn("Apple Events denied for \(bundleId), disabling URL enrichment")
                appleEventsBlocked.insert(bundleId)
            }
            return nil
        }
        return result.stringValue?.isEmpty == false ? result.stringValue : nil
    }

    private static func urlScript(for bundleId: String) -> String? {
        switch bundleId {
        case "com.google.Chrome", "com.google.Chrome.beta":
            return #"tell application "Google Chrome" to return URL of active tab of front window"#
        case "com.apple.Safari":
            return #"tell application "Safari" to return URL of front document"#
        case "company.thebrowser.Browser":
            return #"tell application "Arc" to return URL of active tab of front window"#
        default:
            return nil
        }
    }
}
