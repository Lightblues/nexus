# Image Uploader

Drop, paste, or drag-to-tray an image → smart-compress (ImageIO) → upload to a
GitHub repo via the Contents API → share the jsDelivr CDN URL. History is
persisted in GRDB.

## Pipelines

```
Pipeline A — Popover paste/drop
  Cmd+V or drop in DropZoneView
    → NSPasteboard / NSItemProvider
    → ImageBundle (Data + UTType + originalName)
    → preview (NSImage from CGImageSource thumbnail)
    → ImageCompressor.compress(bundle, options)
    → GitHubClient.upload(...)
    → cdnUrl → NSPasteboard.write
    → UploaderStore.append(record) + thumbnail cache

Pipeline B — Drop on menubar icon
  Drag enters StatusItem button drop receiver
    → DropReceiver.handleDrop(items)
    → UploaderService.pendingImage = bundle
    → showPopover()
    → UploaderPopoverView observes pendingImage on appear → goes to preview state
```

## Drop receiver on the status button

Electron's tray drop is well-known to be flaky — the Swift side uses an `NSView`
attached to `NSStatusItem.button` with explicit drag types:

```swift
final class StatusButtonDropView: NSView {
    var onDrop: (([NSItemProvider]) -> Void)?

    override func awakeFromNib() {
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
            ? .copy : .none
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let providers = sender.draggingPasteboard.pasteboardItems?.compactMap {
            // build NSItemProvider per-item
        } ?? []
        onDrop?(providers)
        return true
    }
}
```

The drop view sits on top of the icon view in the status item. The icon image is
rendered as `NSImageView` underneath; the drop view is fully transparent and
covers the same frame.

## Image Compressor (`ImageCompressor.swift`)

`auto` mode picks a format per source profile:

```
GIF → preserve (no recompress, animation)
has alpha → try WebP, fallback to optimized PNG if WebP inflates
no alpha → compare JPEG (mozjpeg-equivalent quality) vs WebP, pick smaller
```

Implementation:

```swift
enum ImageCompressor {
    static func compress(_ data: Data, ut: UTType, options: CompressOptions)
        async -> CompressionResult { ... }

    private static func encodeJPEG(_ source: CGImage, quality: Double) -> Data { ... }
    private static func encodeWebP(_ source: CGImage, quality: Double) -> Data { ... }
    private static func encodePNG(_ source: CGImage) -> Data { ... }   // optimized: 8-bit when possible
}
```

- JPEG: `CGImageDestinationCreateWithData(_, kUTTypeJPEG, ...)` with
  `kCGImageDestinationLossyCompressionQuality = quality / 100`.
- WebP: macOS 11+ supports WebP via ImageIO (`UTType.webP`). Same destination API.
- PNG optimization: drop alpha channel when fully opaque (`CGImageAlphaInfo`), use
  8-bit indexed when palette ≤ 256 colors. For deeper PNG optimization parity with
  sharp's libimagequant, link `libimagequant.dylib` later — v1 ships without it.

The CompressOptions schema is identical to Electron (`quality: 0–100`,
`format: auto | jpeg | webp | png`).

## GitHub Client (`GitHubClient.swift`)

`URLSession.shared` with a JSON encoder. Implements `PUT /repos/{owner}/{repo}/contents/{path}`
with `Authorization: token {pat}`.

```swift
struct GitHubClient {
    let token: String
    let owner: String
    let repo: String
    let branch: String

    func putContent(path: String, contentBase64: String, message: String) async throws -> PutResponse { ... }
    func headContent(path: String) async throws -> HeadResponse?    // for sha if updating
}
```

Errors map to a typed `UploaderError` enum: `.invalidToken`, `.repoNotFound`,
`.fileExistsConflict`, `.network(URLError)`. `UploaderService` translates them
into user-facing toast messages.

## CDN URL

Same shape as Electron build:
```
https://cdn.jsdelivr.net/gh/{owner}/{repo}@{branch}/{path}/{filename}
```

## Storage

- `~/.ea/nexus/uploader.json` — array of `UploadRecord` (schema below)
- `~/.ea/nexus/uploader/cache/{id}.webp` — 200px thumbnail
  - **Note**: Electron build also uses `.webp`. We keep the same filename pattern so
    cached thumbnails from the Electron build remain valid for users mid-migration.

## Recent paths

`UploaderService.recentPaths` — last 10 distinct paths used, MRU-ordered.
Persisted in `uploader.json` under `meta.recentPaths` (matches Electron).

## UI (Popover)

```
┌─────────────────────────────────────────────┐
│ ← 🖼️ Image Uploader                         │
├─────────────────────────────────────────────┤
│  [Drop Zone: drag / click / paste]          │
│                                             │
│  [Preview] 1920x1080 PNG → JPEG             │
│            1.2MB → 320KB (73% ↓)            │
│                                             │
│  ▸ Compression (35% saved)  ← collapsed     │
│    Quality: [━━━━━━━━] 80                   │
│    Format:  [Auto ▼]                        │
│                                             │
│  Path: [wiki/my-article ▼]                  │
│  Filename: [screenshot-2026-01-28.jpg]      │
│                              [Upload]       │
│                                             │
│  ─── Recent Uploads ───                     │
│  [🖼️] image1.png  5m ago  [📋]              │
└─────────────────────────────────────────────┘
```

- **DropZoneView**: `.onDrop(of: [.image, .fileURL], ...)` + `.onPasteCommand(of:)`
  for clipboard paste support.
- Compression section: `DisclosureGroup`, default collapsed (matches Electron UX).
- Path picker: `Picker` showing `recentPaths` + a "+ New path" inline `TextField`.
- Upload button is disabled while a request is in flight; shows a `ProgressView`
  next to the label.

## Commands

| ID | Action |
|---|---|
| `uploader.openPopover` | Show popover in uploader view |
| `uploader.uploadClipboard` | Read clipboard image, upload with default config |

## Config (unchanged)

```yaml
uploader:
  enabled: true
  github:
    token: "ghp_xxxx"
    owner: "lightblues"
    repo: "assets"
    branch: "main"
  cdn:
    baseUrl: "https://cdn.jsdelivr.net/gh"
  compress:
    quality: 80
    defaultFormat: "auto"
  defaultPath: "upload"
  cacheThumbnails: true
```

Token storage: keep in `config.yaml` (parity with Electron). Future improvement:
move to Keychain as an opt-in (`security` framework) — out of scope for v1.
