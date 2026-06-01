import SwiftUI
import AppKit

/// One row in the recent-uploads list. Loads its own thumbnail (from the
/// repository's cache directory) if available, falls back to a placeholder.
///
/// Trailing actions (left → right):
///   - clicking the thumbnail opens an in-app preview overlay (Quick-Look-ish)
///   - "Open in GitHub" jumps to the file's blob page on github.com
///   - "Open in browser" jumps to the CDN URL (jsdelivr / etc) in default browser
///   - "Copy URL" copies the CDN URL to clipboard
///   - "Trash" removes from local history (does NOT delete from GitHub)
struct UploadHistoryRow: View {
    let record: UploadRecord
    let thumbnailURL: URL?
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?
    @State private var showPreview = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { showPreview = true }) {
                thumb
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Preview \(record.filename)")

            VStack(alignment: .leading, spacing: 2) {
                Text(record.filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.path?.isEmpty == false ? record.path! : "root")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timeAgo(record.timestamp))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // GitHub blob page (only if v4 columns are populated)
            if let ghURL = record.githubURL {
                Button { NSWorkspace.shared.open(ghURL) } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Open in GitHub: \(ghURL.absoluteString)")
            }

            // CDN URL (jsdelivr / etc)
            Button(action: openCDN) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Open CDN URL: \(record.cdnUrl)")

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Copy CDN URL")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from history (does not delete from GitHub)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .task(id: thumbnailURL?.path) { await loadThumbnail() }
        .sheet(isPresented: $showPreview) {
            UploadPreviewSheet(record: record,
                               thumbnailURL: thumbnailURL,
                               onClose: { showPreview = false })
        }
    }

    @ViewBuilder
    private var thumb: some View {
        if let nsImage = thumbnail {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(.tertiary)
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadThumbnail() async {
        guard let url = thumbnailURL else { thumbnail = nil; return }
        // Read off the main thread; NSImage(contentsOf:) is light but blocking.
        let img = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        thumbnail = img
    }

    private func openCDN() {
        guard let url = URL(string: record.cdnUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }
}

/// In-app full-size preview. Loads the *CDN* URL (the actual uploaded image)
/// rather than the local thumbnail, so the user sees what their links
/// resolve to. Falls back to local thumbnail if network fetch fails.
private struct UploadPreviewSheet: View {
    let record: UploadRecord
    let thumbnailURL: URL?
    let onClose: () -> Void

    @State private var image: NSImage?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.filename)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(record.width) × \(record.height) · \(formatBytes(record.compressedSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color.black.opacity(0.05)
            if loading {
                ProgressView().controlSize(.large)
            } else if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    Text(loadError ?? "Could not load preview")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("CDN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(record.cdnUrl)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button {
                if let u = URL(string: record.cdnUrl) { NSWorkspace.shared.open(u) }
            } label: {
                Label("Open CDN", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            if let gh = record.githubURL {
                Button { NSWorkspace.shared.open(gh) } label: {
                    Label("Open in GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func load() async {
        // Try CDN first (what the user's links actually resolve to). Falls
        // back to local thumbnail if the network call fails — typically a
        // jsdelivr propagation delay on a brand-new upload.
        if let url = URL(string: record.cdnUrl),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let img = NSImage(data: data) {
            self.image = img
            self.loading = false
            return
        }
        if let local = thumbnailURL,
           let img = NSImage(contentsOf: local) {
            self.image = img
            self.loading = false
            self.loadError = "CDN unreachable — showing local thumbnail"
            return
        }
        self.loadError = "Could not load image from CDN or local cache"
        self.loading = false
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
