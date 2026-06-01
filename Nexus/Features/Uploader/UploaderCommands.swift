import Foundation
import AppKit

@MainActor
enum UploaderCommands {
    static func register(service: UploaderService, mainWindow: MainWindowController) {
        let registry = CommandRegistry.shared
        let g = "Uploader"

        registry.register(Command(
            id: "uploader.open",
            title: "Uploader: Open",
            group: g,
            keywords: ["upload", "image", "github", "cdn"],
            subtitle: { [weak service] in
                guard let service else { return nil }
                return service.isConfigured ? "ready" : "not configured — set GitHub token in Settings"
            },
            run: { [weak mainWindow] in
                mainWindow?.show(route: .uploader)
            }
        ))

        registry.register(Command(
            id: "uploader.uploadClipboard",
            title: "Uploader: Upload Clipboard Image",
            group: g,
            keywords: ["paste", "screenshot", "clipboard"],
            when: { [weak service] in
                guard let service else { return false }
                return service.isConfigured && service.clipboardImage() != nil
            },
            subtitle: { [weak service] in
                guard let service else { return nil }
                if !service.isConfigured { return "not configured" }
                return service.clipboardImage() == nil ? "no image in clipboard" : "ready"
            },
            run: { [weak service, weak mainWindow] in
                guard let service else { return }
                guard let data = service.clipboardImage() else {
                    Log.uploader.warn("uploadClipboard: no image in pasteboard")
                    return
                }
                // Stash as pending and route to MainWindow's uploader view —
                // user still confirms quality / format / filename / path
                // before the actual PUT. Same flow as a tray-icon drop.
                let stamp = isoStamp()
                service.setPending(PendingImage(data: data, filename: "clipboard-\(stamp).png"))
                mainWindow?.show(route: .uploader)
            }
        ))
    }

    private static func isoStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
