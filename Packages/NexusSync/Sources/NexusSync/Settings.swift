import Foundation

/// Where the app keeps its settings. `load` returns the whole config as a JSON object.
public protocol SettingsStore: Sendable {
    func load() async throws -> [String: JSONValue]
    func save(_ settings: [String: JSONValue]) async throws
}

/// A settings object ↔ dotted-key leaves.
public enum Settings {
    /// Leaves keyed by dotted path, e.g. `pomodoro.workDuration`. Arrays are leaves.
    public static func flatten(_ object: [String: JSONValue], prefix: String = "") -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (key, value) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if case .object(let child) = value { out.merge(flatten(child, prefix: path)) { $1 } }
            else { out[path] = value }
        }
        return out
    }

    public static func unflatten(_ leaves: [String: JSONValue]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (path, value) in leaves { set(&out, path.split(separator: ".").map(String.init)[...], value) }
        return out
    }

    private static func set(_ object: inout [String: JSONValue], _ path: ArraySlice<String>, _ value: JSONValue) {
        guard let head = path.first else { return }
        if path.count == 1 { object[head] = value; return }
        var child: [String: JSONValue] = [:]
        if case .object(let existing)? = object[head] { child = existing }
        set(&child, path.dropFirst(), value)
        object[head] = .object(child)
    }
}
