import AppKit

/// Invisible overlay attached to an NSStatusBarButton to receive image drops.
/// Sized to match the button so it covers exactly the icon's hit area.
///
/// We don't subclass NSStatusBarButton itself (private superclass internals
/// would need replicating). Instead we:
///   - register this NSView for fileURL + image drag types
///   - forward `draggingEntered/Exited/performDragOperation` to a callback
///   - let mouse-down events fall through to the underlying button by NOT
///     consuming them in `mouseDown(with:)`. The button's click handling
///     keeps working unchanged.
///
/// On a successful drop we call `onImagesDropped([(data, filename)])` on the
/// main thread and the AppDelegate routes the bytes into UploaderService.
/// Multi-image drops mirror the in-window DropZone behavior — Finder lets
/// users drag a multi-selection in one gesture, all of them should land in
/// the uploader's batch.
final class StatusItemDropView: NSView {
    /// Called with the full list of dropped images, in drop order.
    private let onImagesDropped: ([(Data, String)]) -> Void
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, onImagesDropped: @escaping ([(Data, String)]) -> Void) {
        self.onImagesDropped = onImagesDropped
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) { fatalError() }

    // Mouse events: don't intercept. Returning nil from hitTest sends clicks
    // to whatever's behind us (the NSStatusBarButton).
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Returning nil makes us "transparent" to clicks — the button below
        // handles them normally. But we still receive drag events because
        // those go through registerForDraggedTypes, not hitTest.
        return nil
    }

    // MARK: - Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasUsableImage(in: sender) else { return [] }
        isHovered = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHovered = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isHovered = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { isHovered = false }
        let pb = sender.draggingPasteboard

        // Multi-file drop from Finder: collect every image URL in the drop,
        // not just the first. Drop order is preserved because
        // `readObjects(forClasses:)` returns the array in pasteboard order.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let images = urls.filter { isImageURL($0) }
            if !images.isEmpty {
                let payloads: [(Data, String)] = images.compactMap { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return (data, url.lastPathComponent)
                }
                if !payloads.isEmpty {
                    DispatchQueue.main.async { self.onImagesDropped(payloads) }
                    return true
                }
            }
        }
        // Fallback: raw bytes from a browser/screenshot pasteboard. Single
        // image — pasteboard image data is one frame, no multi-image form.
        if let data = pb.data(forType: .png) {
            DispatchQueue.main.async {
                self.onImagesDropped([(data, "dropped-\(Self.timestamp()).png")])
            }
            return true
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            DispatchQueue.main.async {
                self.onImagesDropped([(png, "dropped-\(Self.timestamp()).png")])
            }
            return true
        }
        return false
    }

    // MARK: - Visual feedback

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovered else { return }
        // Subtle accent ring while a draggable image is hovering — gives
        // users feedback that the icon is a valid drop target.
        let inset = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    // MARK: - Helpers

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
