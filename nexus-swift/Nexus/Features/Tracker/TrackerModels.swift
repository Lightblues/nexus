import Foundation

/// Optional context attached to a window observation. Some fields only populated for
/// apps in the enrichment whitelist.
struct ActivityContext: Codable, Equatable {
    var project: String?       // e.g. VSCode project name
    var file: String?          // filename or page title
    var url: String?           // browser URL
    var domain: String?        // extracted hostname
    var rawTitle: String?      // original window title (AI fallback)

    var isEmpty: Bool {
        project == nil && file == nil && url == nil && domain == nil && rawTitle == nil
    }
}

/// One window-activity span. `endTime` is updated when the user stays on the same
/// app+file (merge); a different app+file finalizes the previous record and starts a
/// new one.
struct WindowActivityRecord: Codable, Equatable {
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval     // seconds, derived: endTime - startTime
    var app: String
    var bundleId: String?
    var title: String?             // only set when config.recordTitle == true
    var context: ActivityContext?
}

/// In-memory probe result from AX. Not persisted directly — gets enriched +
/// transformed into `WindowActivityRecord`.
struct ActiveProbe: Equatable {
    var app: String                // friendly name (BUNDLE_TO_APP_NAME map applied)
    var bundleId: String?
    var title: String?
    var url: String?               // populated by enricher for browsers
}
