import SwiftUI
import AppKit

/// Drop zone — accepts file URLs or pasteboard image bytes via SwiftUI .onDrop.
/// Tapping it opens an NSOpenPanel as fallback for users who'd rather click.
/// Mirrors DropZone.tsx, including the "paste from clipboard" inline link.
struct DropZoneView: View {
    let disabled: Bool
    let onSelect: (Data, String) -> Void
    let onPasteClipboard: () -> Void

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Drop or Click to Select")
                .font(.system(size: 13, weight: .medium))
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
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                onSelect(data, url.lastPathComponent)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        // Prefer fileURL — gives us the original filename. Fall back to raw
        // image bytes (e.g. drag from a browser).
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async {
                    onSelect(data, url.lastPathComponent)
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier("public.image") {
            provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                guard let data else { return }
                DispatchQueue.main.async {
                    let stamp = Self.timestamp()
                    onSelect(data, "dropped-\(stamp).png")
                }
            }
            return true
        }
        return false
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
