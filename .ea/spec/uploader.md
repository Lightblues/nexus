# Image Uploader

Image hosting with compression and GitHub integration.

## Features
- Clipboard paste / file drag-and-drop / tray icon drop
- Smart compression (sharp): auto format selection, quality control
- Upload to GitHub public repo → jsDelivr CDN URL
- Custom path support (recent paths autocomplete)
- Upload history with thumbnail cache
- URL auto-copied to clipboard on upload

## Upload Flow
```
方式1: Popup 中上传
  粘贴/拖拽图片 → 预览 + meta → 调整路径/文件名 → Upload
  → sharp 压缩 → GitHub API → CDN URL → 复制到剪贴板

方式2: 拖拽到 menubar icon
  拖拽文件 → TrayManager drop-files → pendingImage
  → 弹出 Popup → UploaderView 加载 pendingImage → 预览 → Upload
```

## UI (Popup)
```
┌─────────────────────────────────────────────┐
│ ← 🖼️ Image Uploader                        │
├─────────────────────────────────────────────┤
│  [Drop Zone: drag / click / paste]          │
│                                             │
│  [Preview] 1920x1080 PNG → JPEG             │
│            1.2MB → 320KB (73% ↓)            │
│                                             │
│  ▸ Compression (35% saved)  ← collapsed     │
│    Quality: [━━━━━━━━] 80   ← expanded      │
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

Compression controls default collapsed behind "▸ Compression" toggle with savings percentage. Expand to adjust quality/format.

## Compression Algorithm (`ImageCompressor.ts`)
```
auto mode:
  GIF → preserve (animation)
  has alpha → try WebP, fallback to optimized PNG if WebP inflates
  no alpha → compare mozjpeg vs WebP, pick smaller
```

## Data Structure
```typescript
interface UploadRecord {
  id: string; filename: string; originalName: string
  timestamp: string; originalSize: number; compressedSize: number
  width: number; height: number; format: 'png' | 'jpeg' | 'webp' | 'gif'
  path: string; cdnUrl: string; sha: string
}
```

## Storage
- Data: `~/.ea/nexus/uploader.json`
- Thumbnail cache: `~/.ea/nexus/uploader/cache/{id}.webp` (200px WebP)
- Auto-cleanup: keep last 100 thumbnails

## Config (`config.yaml`)
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
