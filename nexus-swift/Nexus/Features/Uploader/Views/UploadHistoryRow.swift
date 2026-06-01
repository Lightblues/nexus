import SwiftUI
import AppKit

/// One row in the recent-uploads list. Loads its own thumbnail (from the
/// repository's cache directory) if available, falls back to a placeholder.
struct UploadHistoryRow: View {
    let record: UploadRecord
    let thumbnailURL: URL?
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            thumb
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))

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

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Copy URL")

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

    private func timeAgo(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }
}
