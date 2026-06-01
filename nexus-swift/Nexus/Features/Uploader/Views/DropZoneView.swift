import SwiftUI
import AppKit

/// Drop zone — accepts file URLs or pasteboard image bytes.
///
/// Implementation note: SwiftUI's `.onDrop(of:isTargeted:)` runs the
/// pasteboard through a *type-promotion* layer that, for plain image files
/// like PNG/JPG dragged from Finder, advertises only `public.image` /
/// `public.png` etc. — the `public.file-url` type ID is NOT in the
/// `NSItemProvider.registeredTypeIdentifiers`. Without that we can't recover
/// the original filename and have to invent one ("dropped-….png").
///
/// AppKit's `registerForDraggedTypes(_:)` route reads the underlying
/// `NSPasteboard` directly and DOES expose the file URLs (they're always
/// there for Finder drops), which is what `StatusItemDropView` already uses.
/// To get behavior parity between menu-bar drop and in-window drop, we wrap
/// an AppKit `NSView` via `NSViewRepresentable` here too.
///
/// The visual chrome (icon, dashed border, hover highlight) stays in
/// SwiftUI; we just overlay an invisible AppKit drop receiver on top of it.
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
        ZStack {
            // Visual chrome
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

            // AppKit drop receiver overlay. Doesn't capture clicks (uses
            // hitTest = nil for points where it has no business), so the
            // SwiftUI Button above still works for the click-to-pick path.
            DropReceiver(
                isDragging: $isDragging,
                disabled: disabled,
                onDrop: handleDropPayloads,
                onClickToOpen: { if !disabled { openFilePanel() } }
            )
        }
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

    private func handleDropPayloads(_ payloads: [(Data, String)]) {
        guard !payloads.isEmpty else { return }
        let capped = Array(payloads.prefix(Self.maxBatch))
        if payloads.count > Self.maxBatch {
            Log.uploader.warn("drop had \(payloads.count) items, only first \(Self.maxBatch) accepted")
        }
        let imgs: [DroppedImage] = capped.map { (data: $0.0, filename: $0.1) }
        onSelect(imgs)
    }
}

// MARK: - AppKit drop receiver overlay

/// Thin NSViewRepresentable that bridges AppKit drag events into SwiftUI.
/// Mirrors `StatusItemDropView`'s pasteboard-reading logic exactly so the
/// two drop entry points behave the same way.
private struct DropReceiver: NSViewRepresentable {
    @Binding var isDragging: Bool
    let disabled: Bool
    let onDrop: ([(Data, String)]) -> Void
    let onClickToOpen: () -> Void

    func makeNSView(context: Context) -> ReceiverView {
        let v = ReceiverView()
        v.onIsDraggingChange = { dragging in
            DispatchQueue.main.async { isDragging = dragging }
        }
        v.onDrop = { payloads in
            DispatchQueue.main.async { onDrop(payloads) }
        }
        v.onClickToOpen = { onClickToOpen() }
        v.disabled = disabled
        return v
    }

    func updateNSView(_ v: ReceiverView, context: Context) {
        v.disabled = disabled
        v.onIsDraggingChange = { dragging in
            DispatchQueue.main.async { isDragging = dragging }
        }
        v.onDrop = { payloads in
            DispatchQueue.main.async { onDrop(payloads) }
        }
        v.onClickToOpen = { onClickToOpen() }
    }

    final class ReceiverView: NSView {
        var disabled: Bool = false
        var onIsDraggingChange: ((Bool) -> Void)?
        var onDrop: (([(Data, String)]) -> Void)?
        /// Click anywhere on the (non-button) drop area opens the file panel.
        /// SwiftUI Buttons inside our parent ZStack still work — they sit
        /// above us in z-order and consume their own clicks before reaching
        /// here (we only see clicks on empty area).
        var onClickToOpen: (() -> Void)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL, .png, .tiff])
        }
        required init?(coder: NSCoder) { fatalError() }

        // We want to receive clicks on empty area but NOT swallow clicks on
        // SwiftUI buttons that sit above us. SwiftUI's hit testing already
        // handles that correctly because the button's NSHostingView is in
        // front of us in the ZStack — clicks there never reach this view's
        // mouseDown.
        override func mouseDown(with event: NSEvent) {
            if !disabled { onClickToOpen?() }
        }

        // MARK: drag destination

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard !disabled, hasUsableImage(in: sender) else { return [] }
            onIsDraggingChange?(true)
            return .copy
        }
        override func draggingExited(_ sender: NSDraggingInfo?) {
            onIsDraggingChange?(false)
        }
        override func draggingEnded(_ sender: NSDraggingInfo) {
            onIsDraggingChange?(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { onIsDraggingChange?(false) }
            guard !disabled else { return false }
            let pb = sender.draggingPasteboard

            // Multi-file drop: collect every image URL in pasteboard order.
            // This is the path that preserves original filenames. Same as
            // StatusItemDropView.
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                let images = urls.filter { isImageURL($0) }
                if !images.isEmpty {
                    let payloads: [(Data, String)] = images.compactMap { url in
                        guard let data = try? Data(contentsOf: url) else { return nil }
                        return (data, url.lastPathComponent)
                    }
                    if !payloads.isEmpty { onDrop?(payloads); return true }
                }
            }
            // Fallback: raw bytes (browser drag, screenshot pasteboard).
            if let data = pb.data(forType: .png) {
                onDrop?([(data, "dropped-\(Self.timestamp()).png")])
                return true
            }
            if let tiff = pb.data(forType: .tiff),
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                onDrop?([(png, "dropped-\(Self.timestamp()).png")])
                return true
            }
            return false
        }

        // MARK: helpers

        private func hasUsableImage(in info: NSDraggingInfo) -> Bool {
            let pb = info.draggingPasteboard
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               urls.contains(where: { isImageURL($0) }) {
                return true
            }
            return pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil
        }

        private func isImageURL(_ url: URL) -> Bool {
            let exts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]
            return exts.contains(url.pathExtension.lowercased())
        }

        private static func timestamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: Date())
        }
    }
}
