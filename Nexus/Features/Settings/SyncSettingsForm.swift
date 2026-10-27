import SwiftUI

/// Sync connection: saved to `sync.json` on its own (not through the config draft),
/// because it is local to this Mac and never syncs.
struct SyncSettingsForm: View {
    @EnvironmentObject var sync: SyncCoordinator
    @State private var server = ""
    @State private var key = ""
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            connectionSection
            statusSection
        }
        .frame(maxWidth: 540, alignment: .leading)
        .onAppear {
            server = sync.connection.server
            key = sync.connection.key
        }
    }

    private var isEdited: Bool { server != sync.connection.server || key != sync.connection.key }

    private var connectionSection: some View {
        SettingsSection(title: "Server") {
            Toggle("Sync settings, pomodoro and tracker data", isOn: Binding(
                get: { sync.connection.enabled },
                set: { on in apply { $0.enabled = on } }))
            FieldRow(label: "Server") {
                TextField(SyncConnection.defaultServer, text: $server)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            FieldRow(label: "Key") {
                SecureField("NEXUS_KEY", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            HStack(spacing: 8) {
                Button("Save Connection") {
                    apply { $0.server = server.trimmingCharacters(in: .whitespaces); $0.key = key.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                .controlSize(.small)
                .disabled(!isEdited)
                Button("Revert") { server = sync.connection.server; key = sync.connection.key }
                    .controlSize(.small)
                    .disabled(!isEdited)
            }
            if let saveError {
                Text(saveError).font(.system(size: 11)).foregroundStyle(.red)
            }
            Text("Stored in `sync.json` on this Mac only. Every other setting, including the uploader token, syncs to the server. The first sync takes the server's settings over this Mac's.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusSection: some View {
        SettingsSection(title: "Status") {
            HStack(spacing: 8) {
                Image(systemName: statusIcon.name).foregroundStyle(statusIcon.color)
                Text(statusText).font(.system(size: 12))
                Spacer()
                if sync.isSyncing { ProgressView().controlSize(.small) }
                Button("Sync Now") { sync.syncNow() }
                    .controlSize(.small)
                    .disabled(!sync.connection.isActive || sync.isSyncing)
            }
            if let error = sync.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: String {
        let c = sync.connection
        if !c.enabled { return "Off" }
        if c.key.isEmpty { return "Add the key to start syncing" }
        if c.serverURL == nil { return "The server is not an http(s) URL" }
        if sync.isSyncing { return "Syncing…" }
        guard let at = sync.lastAttempt else { return "Waiting for the first sync" }
        let when = at.formatted(date: .omitted, time: .standard)
        guard let r = sync.lastReport else { return "Failed at \(when)" }
        return "Synced at \(when): pushed \(r.pushed), pulled \(r.pulled), stale \(r.stale)"
    }

    private var statusIcon: (name: String, color: Color) {
        if !sync.connection.isActive { return ("icloud.slash", .secondary) }
        if sync.lastError != nil { return ("exclamationmark.icloud", .orange) }
        return ("checkmark.icloud", .green)
    }

    private func apply(_ edit: (inout SyncConnection) -> Void) {
        var next = sync.connection
        edit(&next)
        do { try sync.update(next); saveError = nil }
        catch { saveError = "Could not save sync.json: \(error.localizedDescription)" }
    }
}
