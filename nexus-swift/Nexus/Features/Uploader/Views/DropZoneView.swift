import SwiftUI
import AppKit

/// Drop zone — accepts file URLs or pasteboard image bytes via SwiftUI .onDrop.
/// Tapping it opens an NSOpenPanel as fallback. Up to `Self.maxBatch` images
/// per drop; extras silently dropped (we log but don't error). Mirrors
/// DropZone.tsx, plus multi-file support.
struct DropZoneView: View {
    /// Each tuple: image bytes + best-effort filename.
    typealias DroppedImage = (data: Data, filename: String)

    let disabled: Bool
    let onSelect: ([DroppedImage]) -> Void
    let onPasteClipboard: () -> Void

    /// Hard cap on a single drop — keeps the batch UI manageable and avoids
    /// loading huge folders into memory by accident.
    static let maxBatch = 10

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Drop or Click to Select")
                .font(.system(size: 13, weight: .medium))
            Text("Up to \(Self.maxBatch) images per drop")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Text("or")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(action: onPasteClipboard) {
                    Text("paste from clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
            Text("💡 Drop image on menu-bar icon for quick upload")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDragging ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
                )
        )
        .opacity(disabled ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { openFilePanel() } }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragging) { providers in
            guard !disabled else { return false }
            return handleDrop(providers: providers)
        }
    }

    // MARK: - Handlers

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            let urls = Array(panel.urls.prefix(Self.maxBatch))
            let imgs: [DroppedImage] = urls.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return (data, url.lastPathComponent)
            }
            if !imgs.isEmpty { onSelect(imgs) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Cap before doing any work — keeps drop semantics predictable.
        let capped = Array(providers.prefix(Self.maxBatch))
        if providers.count > Self.maxBatch {
            Log.uploader.warn("drop had \(providers.count) items, only first \(Self.maxBatch) accepted")
        }
        // We need to wait for all loadObject callbacks before firing onSelect
        // so the UI can build the batch in a single state transition (not 10
        // individual appends, which would re-render N times).
        let group = DispatchGroup()
        var collected: [(Int, DroppedImage)] = []   // (originalIndex, payload)
        let lock = NSLock()

        for (idx, provider) in capped.enumerated() {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    guard let url, let data = try? Data(contentsOf: url) else { return }
                    lock.lock()
                    collected.append((idx, (data, url.lastPathComponent)))
                    lock.unlock()
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    defer { group.leave() }
                    guard let data else { return }
                    let name = "dropped-\(Self.timestamp())-\(idx).png"
                    lock.lock()
                    collected.append((idx, (data, name)))
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            // Preserve the user's drop order by sorting on originalIndex.
            let ordered = collected.sorted { $0.0 < $1.0 }.map(\.1)
            if !ordered.isEmpty { onSelect(ordered) }
        }
        return true
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
