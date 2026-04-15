### Project: EA Nexus (macOS Menu Bar Agent)

## 1. Project Overview
**EA Nexus** is a modular, macOS-native efficiency toolkit residing in the Menu Bar.
The initial release (MVP) focuses on a **Pomodoro Timer**, but the architecture must support future pluggable modules (e.g., Image Uploader, Notes).

- **Platform**: macOS (optimized for Menu Bar interaction).
- **Project Root**: `packages/nexus`
- **Data/Config Path**: `~/.ea/nexus/`
- **Tech Stack**: Electron + Vite + React + TypeScript.
- **Architecture**: "Main-Process-as-Source-of-Truth" with a Modular Feature structure.
- **UX Pattern**: "Tray Popover" (Menubar Icon -> Click -> Floating Frameless Window).

## Core Specifications

### Data & Configuration Strategy
**Requirement**:
Use a unified directory `~/.ea/nexus/` for all app persistence. Separate user-editable config from machine-generated data.

**1. Directory Setup (`src/main/core/PathManager.ts`)**
- **Logic**:
    - Identify the Home Directory (`os.homedir()`).
    - Target Path: `path.join(os.homedir(), '.ea', 'nexus')`.
    - On App launch, `fs.mkdirSync(targetPath, { recursive: true })` to ensure it exists.

**2. Configuration Engine (`src/main/core/ConfigManager.ts`)**
- **File**: `~/.ea/nexus/config.yaml`
- **Library**: Install `js-yaml` (npm install js-yaml @types/js-yaml).
- **Features**:
    - **Load**: Read file -> `yaml.load()`. If file keeps missing, copy a `default-config.yaml` from resources.
    - **Watch**: Use `fs.watch()` on this file. If you edit it with Vim/VSCode while the app is running, the app should emit a `config:updated` event to reload settings instantly (Hot Reload!).

**3. Data Storage (`src/main/core/DataManager.ts`)**
- **File**: `~/.ea/nexus/data.json`
- **Library**: `electron-store` or `lowdb`.
- **Setup**: Configure the store to point explicitly to the custom path defined in PathManager.
- **Content**:
    - `stats.pomodoro.totalSessions` (Number)
    - `stats.pomodoro.history` (Array of objects)

**4. Logging (`src/main/core/Logger.ts`)**
- **Library**: `electron-log`.
- **Setup**:
    - `log.transports.file.resolvePathFn = () => path.join(PathManager.eaDir, 'logs/main.log');`

### Main Window Layout
The MainWindow provides a unified interface with sidebar navigation for accessing different features.

- **Layout**:
    - **Sidebar** (180px): Fixed left panel with app title and navigation items
    - **Content Area**: Flexible area that displays the selected view
- **Navigation Items**:
    - Statistics (📊): Pomodoro statistics dashboard
    - Settings (⚙️): Configuration editor
- **Routing**: Hash-based (`#/stats`, `#/settings`)
- **Window**: 900x600 default, 700x400 minimum

### Settings Editor
In-app configuration editing via Monaco YAML editor.

- **File**: `~/.ea/nexus/config.yaml`
- **Features**:
    - Monaco editor with YAML syntax highlighting
    - Real-time validation against `AppConfig` schema
    - Status indicator (saved/unsaved/error)
    - Hot-reload via existing `fs.watch` mechanism
- **IPC Handlers** (`src/main/features/settings/settings.ipc.ts`):
    - `config:read-raw`: Returns raw YAML content
    - `config:validate`: Validates YAML against schema
    - `config:write-raw`: Validates and writes config
    - `window:open-settings`: Opens MainWindow with settings view
- **Access**: Dashboard Settings card → Opens MainWindow at `/settings`

### Tray & Popover Logic (`TrayManager` & `PopupWindow`)
- **Visuals**:
    - **Icon**: Static generic icon (e.g., `🤖` or a simple geometric shape).
    - **Title**: Dynamic text next to the icon.
        - *Idle*: Empty string `''`.
        - *Pomodoro Running*: Time string `' 24:59'` (Note the leading space for padding).
- **Interaction**:
    - **Left Click**: Toggle the Popover Window.
    - **Right Click**: Show a native context menu with the following items:
        - **Show Main Window**: Opens the MainWindow (statistics dashboard).
        - **About**: Display app information.
        - **Quit**: Exit the application.
- **Positioning Algorithm**:
    - On click, calculate the `x` and `y` coordinates to center the window immediately below the Tray Icon.
    - Formula: `x = trayBounds.x + (trayBounds.width / 2) - (windowWidth / 2)`.
    - Formula: `y = trayBounds.y + trayBounds.height` (Ensure y_offset handles the macOS bar height).
- **Blur Behavior**:
    - When the user clicks anywhere else on the screen (window `blur` event), the window must automatically hide.

### Pomodoro Timer
A Pomodoro technique implementation with project/tag tracking and statistics.

- features
    - 标准番茄钟流程: 专注 -> 短休 -> 专注 -> 长休 (各参数可配置)
    - UI: MenuBar 交互
    - 统计体系 (Statistics)
    - 项目体系: 包括 project, tags, task 等元数据
    - 每日计数重置: `completedSessions` 每天自动从当日历史记录加载，跨天自动归零
- 状态机 (交互逻辑): `Idle` -> `Running` -> `Paused` -> `Finished`
    - 对于某一状态, 他们在运行中分别可交互:
        - Running/Paused: Pause/Resume, Finish Early, Exit
        - Finished: Start (next break), Exit
        - Short/Long Break: Skip (next work), Exit
    - 通知逻辑:
        - macOS系统消息: 完成是发送消息, 点击跳转popup
        - popover功能: 通过 `showPopoverOnComplete` 参数配置
- 项目体系
    - 对于某一段 Work 时间, 可分配到某一 project; 另外可增加 tags 来进行划分. project/tags 体系正交 (参考 Linear.app 的设计)
    - 对于某一段 Work 时间, 可填写 task 描述 (可选)
    - 新建番茄钟时，默认复用上一轮的 project, tags, task，减少用户心智负担
- 统计体系
    - 交互: 在popover上展示今日专注数量&总时间, 点击之后关闭popover跳转到主窗口;
    - 可视化统计指标: 方案见下

Visualization Components (Dashboard View)
- **Card A: The Streak (GitHub Style)**
    - Use `react-activity-calendar`.
    - Map data to date strings (`yyyy-mm-dd`) and count levels (0-4).
- **Card B: The Weekly Bar**
    - Simple Bar Chart using `Recharts`.
    - X-Axis: Last 7 days. Y-Axis: Hours focused.
- **Card C: The Daily Timeline (The "Gantt")**
    - **Visualization**: A horizontal stacked bar chart where the X-axis is time (00:00 to 24:00).
    - **Segments**:
        - Render `Work` segments in Red (or Accent Color).
        - Render `Break` segments in Green.
        - Render `Idle` gaps as transparent or gray.
    - **Tooltip**: "10:00 AM - 10:25 AM (Focus)".

### Image Uploader (图床)
Image hosting service with compression and GitHub integration.

**Features**:
- 剪切板/文件拖拽上传
- 图片压缩 (类似 TinyPNG/Squoosh) 使用 sharp
- 上传到 GitHub 公开仓库
- 自定义路径支持（下拉选择最近路径）
- 历史记录管理
- **拖拽到 menubar icon 快速上传** (类似 uPic)

**UI Layout** (Popup View):
```
┌─────────────────────────────────────────────┐
│ ← 🖼️ Image Uploader                        │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │ ← Scrollable Container
│ │  🖼️ Drop or Click to Select             │ │
│ │     or paste from clipboard             │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ [Preview Image] (click to view full-size)   │
│ 1920x1080 · PNG → JPEG                      │
│ 1.2MB → 320KB (73.3% smaller)               │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Quality:  [━━━━━━━━━━] 80               │ │
│ │ Format:   [Auto ▼] (WebP/JPEG/PNG)      │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ Path: [wiki/my-article/    ▼]               │
│      (autocomplete with recent paths)       │
│ Filename: [screenshot-2026-01-28.jpg  ]     │
│                          [Upload]           │
│                                             │
│ ─────────── Recent Uploads ───────────      │
│ [🖼️] image1.png      5m ago [📋]           │
│      upload                                 │
└─────────────────────────────────────────────┘
```

**Data Structure**:
```typescript
interface UploadRecord {
  id: string                    // UUID
  filename: string              // 最终文件名
  originalName: string          // 原始文件名
  timestamp: string             // ISO 8601
  originalSize: number          // bytes
  compressedSize: number        // bytes
  width: number
  height: number
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  path: string                  // GitHub 路径 (e.g., "wiki/my-article")
  cdnUrl: string                // CDN 链接
  sha: string                   // GitHub blob SHA
}

interface UploaderData {
  version: 1
  recentPaths: string[]         // 最近使用的路径
  history: UploadRecord[]       // 按时间倒序
}
```

**Storage**:
- Data: `~/.ea/nexus/uploader.json`
- Thumbnail Cache: `~/.ea/nexus/uploader/cache/{id}.webp` (200px WebP)
- Auto-cleanup: Keep thumbnails for last 100 records only

**Configuration** (`config.yaml`):
```yaml
uploader:
  enabled: true
  github:
    token: "ghp_xxxx"           # Personal Access Token (repo scope)
    owner: "lightblues"
    repo: "assets"              # 公开仓库
    branch: "main"
  cdn:
    baseUrl: "https://cdn.jsdelivr.net/gh"
    # Final URL: {baseUrl}/{owner}/{repo}@{branch}/{path}/{filename}
  compress:
    quality: 80                 # JPEG/WebP 质量 (1-100)
    defaultFormat: "auto"       # 'auto' | 'webp' | 'jpeg' | 'png'
  defaultPath: "upload"         # 默认上传路径
  cacheThumbnails: true         # 是否缓存缩略图 (200px WebP)
```

**IPC Handlers** (`src/main/features/uploader/uploader.ipc.ts`):
- `uploader:get-config`: 获取配置
- `uploader:get-pending-image`: 获取待处理图片（从 tray 拖拽）
- `uploader:get-clipboard-image`: 获取剪切板图片 → `{ buffer, format, width, height }`
- `uploader:get-image-meta`: 获取图片元数据
- `uploader:compress`: 压缩图片 → `{ buffer, originalSize, compressedSize, width, height, outputFormat }`
- `uploader:upload`: 上传到 GitHub → `{ success, cdnUrl, sha, record }`
- `uploader:delete`: 删除远程图片 (by record ID)
- `uploader:get-history`: 获取上传历史
- `uploader:get-recent-paths`: 获取最近使用的路径
- `uploader:copy-url`: 复制 URL 到剪切板
- `uploader:get-thumbnail`: 获取缩略图 (200px WebP) → `number[] | null`
- **Event** `uploader:image-dropped`: 图片拖拽到 tray 事件

**Upload Flow**:
```
方式1: 在 Popup 中上传
  用户粘贴/拖拽图片到 DropZone
       ↓
  renderer 读取为 ArrayBuffer
       ↓
  显示预览 + Meta (宽高、格式、大小)
       ↓
  用户选择路径、文件名
       ↓
  点击 Upload
       ↓
  [Main] sharp 压缩 (如果启用)
       ↓
  [Main] GitHub API 上传
       ↓
  生成 CDN URL
       ↓
  保存到历史记录
       ↓
  复制 URL 到剪切板 + 通知

方式2: 拖拽到 menubar icon 快速上传
  用户拖拽图片到 menubar icon
       ↓
  [Main] TrayManager 捕获 drop-files 事件
       ↓
  读取文件 → 存储到 UploaderService.pendingImage
       ↓
  触发 Popup 显示，切换到 uploader view
       ↓
  UploaderView 挂载时调用 getPendingImage()
       ↓
  自动加载图片预览
       ↓
  用户调整路径/文件名后点击 Upload
```

**GitHub Workflow 配置** (私有仓库同步时保留图床文件):
```yaml
# .github/workflows/sync-assets.yml
name: Sync Assets

on:
  push:
    branches: [main]
    paths: ['assets/**']
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout private repo
        uses: actions/checkout@v4
        with:
          path: private

      - name: Checkout public repo
        uses: actions/checkout@v4
        with:
          repository: lightblues/assets
          token: ${{ secrets.DEPLOY_TOKEN }}
          path: public

      - name: Merge assets (preserve public-only files)
        run: |
          rsync -av private/assets/ public/

      - name: Push to public repo
        run: |
          cd public
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add -A
          git diff --staged --quiet || git commit -m "Sync assets from private repo"
          git push
```

**Dependencies**:
```json
{
  "sharp": "^0.33.0",
  "@octokit/rest": "^20.0.0",
  "uuid": "^9.0.0"
}
```

**Build Configuration** (`electron.vite.config.ts`):
- Sharp 必须在 `rollupOptions.external` 中声明，避免打包 native module
- 使用 `external: ['sharp']` 配置

**Compression Algorithm** (`ImageCompressor.ts`):

Smart format selection based on image characteristics:

```typescript
compressImage(buffer, quality, outputFormat: 'auto' | 'webp' | 'jpeg' | 'png')

// Auto mode logic:
if (outputFormat === 'auto') {
  if (format === 'gif') {
    // Preserve GIF (animation support)
    return original
  } else if (hasAlpha) {
    // Try WebP first
    webpBuffer = sharp(buffer).webp({ quality, effort: 6 })
    // If WebP is larger than original, use optimized PNG
    if (webpBuffer.length < originalSize) {
      return webpBuffer  // WebP
    } else {
      return sharp(buffer).png({ compressionLevel: 9, palette: true })
    }
  } else {
    // No transparency: compare JPEG mozjpeg vs WebP
    [jpegBuffer, webpBuffer] = await Promise.all([
      sharp(buffer).jpeg({ quality, mozjpeg: true }),
      sharp(buffer).webp({ quality, effort: 6 })
    ])
    return jpegBuffer.length <= webpBuffer.length ? jpegBuffer : webpBuffer
  }
}
```

**Optimization Rationale**:
- GIF preserved for animation support
- Alpha channels: WebP best, PNG fallback if WebP inflation occurs
- No alpha: mozjpeg vs WebP, pick smallest
- Manual format selection for user override

**UI Enhancements**:

1. **Compression Controls**:
   - Quality slider (1-100, default 80)
   - Format selector: Auto/WebP/JPEG/PNG
   - Real-time re-compression on quality/format change
   - Auto filename extension update based on output format

2. **Image Preview**:
   - Click-to-preview full-size modal
   - Shows size comparison: `1.2MB → 320KB (73% ↓)`
   - Displays format change: `PNG → JPEG`
   - Modal with dark backdrop, click-outside-to-close

3. **Thumbnail Caching**:
   - Storage: `~/.ea/nexus/uploader/cache/{id}.webp`
   - Size: 200px max dimension, WebP quality 80
   - Generated async during `addRecord()`
   - Auto-cleanup: Keep only last 100 records
   - Lazy loading in UploadHistory with emoji fallback

**Implementation Notes**:
- TrayManager 继承 EventEmitter，监听 `drop-files` 事件
- UploaderService 使用 `pendingImage` 临时存储拖拽到 tray 的图片
- UploaderView 挂载时通过 `getPendingImage()` 获取待处理图片
- DropZone 使用原生 div 而非 Card 组件以支持 drag events
- 所有文本使用 `color: 'var(--text-primary)'` 确保可见性
- Content 使用 `overflow: auto` 支持滚动
- `useEffect` 监听 `[image?.buffer, quality, outputFormat]` 触发实时重压缩
- UploaderDataManager.addRecord() 改为 async 支持缩略图生成
- ThumbnailImage 组件从缓存加载缩略图，失败则显示 🖼️ emoji

### Auto-Tracker (Time Tracking)
Automatic time tracking based on active window monitoring. Independent from Pomodoro, stored separately.

**Features**:
- Background window tracking using **AppleScript** via `osascript` (no external binary)
- Browser URL extraction via app-specific AppleScript (Chrome, Safari, Arc)
- Idle detection via Electron `powerMonitor.getSystemIdleTime()`
- Per-day JSON file storage for performance
- Activity record merging (consecutive identical file/app merge into one record)
- App-specific context enrichment (VSCode project/file, Browser URL/domain)
- Does NOT prevent macOS sleep (no `powerSaveBlocker`)

**Why AppleScript instead of `get-windows`**:
- `get-windows` uses a standalone Swift binary that requires its own Accessibility permission entry
- In production builds, this causes repeated permission prompts (macOS treats each binary separately)
- AppleScript via `osascript` inherits the main Electron app's Accessibility permission
- No additional binaries to package or manage

**Data Structure**:
```typescript
interface ActivityContext {
  project?: string   // 项目名 (High level)
  file?: string      // 文件名/页面标题 (Granular level)
  url?: string       // 浏览器 URL
  domain?: string    // 域名 (github.com), 方便饼图统计
  rawTitle?: string  // 原始标题作为兜底，AI 分析时可读取
}

interface WindowActivityRecord {
  startTime: string  // ISO 8601
  endTime: string
  duration: number   // seconds
  app: string        // App name (e.g., "Code", "Google Chrome")
  bundleId?: string  // macOS bundle ID
  context?: ActivityContext
}

interface DailyTrackerData {
  date: string       // "YYYY-MM-DD"
  version: 1
  records: WindowActivityRecord[]
  meta: {
    totalActiveTime: number           // seconds
    appSummary: Record<string, number> // app -> seconds
  }
}
```

**Storage**: `~/.ea/nexus/tracker/YYYY-MM-DD.json`
- One file per day for performance
- Buffer in memory, flush every 5 minutes or on shutdown
- Meta summary updated on each flush for quick aggregation

**Configuration** (`config.yaml`):
```yaml
tracker:
  enabled: true
  pollInterval: 5      # seconds between polls
  idleThreshold: 120   # seconds before considered idle
  recordTitle: false   # privacy: don't record window titles
  enrichApps:          # apps to extract context from
    - Code
    - Google Chrome
```

**Context Enrichment**:
- **VSCode**: Parse title `"filename — project-name"` → `file`, `project`
- **Browser**: Use AppleScript to get URL from Chrome/Safari/Arc → extract `domain`, use title as `file`
- **All enriched apps**: Preserve `rawTitle` for AI analysis fallback

**Merge Algorithm**:
- Poll every `pollInterval` seconds
- Skip if `idleTime >= idleThreshold`
- Compare by `app` + `context.file` (granular tracking)
- Same activity: update `endTime` of last record
- Different activity: finalize last record, create new one

**IPC Handlers** (`src/main/features/tracker/tracker.ipc.ts`):
- `tracker:get-status`: Returns `{ enabled, running }`
- `tracker:get-day`: Get records for a specific date
- `tracker:get-date-range`: Get records for date range
- `tracker:get-summary`: Get app usage summary for date range

**Visualization** (`src/renderer/src/features/tracker/`):

TrackerView 页面，类似 Apple Screen Time，包含以下组件：

- **TrackerTimeline**: 24 小时时间线
    - 水平条形图，X 轴为时间 (00:00 - 24:00)
    - 每个 activity segment 按 APP 着色
    - Tooltip 显示: 时间段、APP 名、时长、context (project/file/domain)
    - 颜色映射: 常见 APP 使用固定颜色，其他 APP 使用哈希算法生成

- **AppUsageChart**: 环形图
    - 显示 Top 5 APP 使用占比，其余归入 "Other"
    - 中心显示总活跃时间
    - 悬停显示 APP 名、时长、百分比

- **AppRankList**: APP 排名列表 (类似 Screen Time)
    - 按使用时长降序排列
    - 显示进度条表示相对占比
    - 时长格式: "2h 30m"
    - 可展开显示 context 细分 (project/domain 分布)

- **布局**:
```
┌─────────────────────────────────────────┐
│ Time Tracker                 [日期选择] │
├─────────────────────────────────────────┤
│ Timeline (00:00 ────────────── 24:00)   │
├─────────────────────────────────────────┤
│ ┌───────────────┐ ┌───────────────────┐ │
│ │  环形图        │ │  APP 排名列表     │ │
│ └───────────────┘ └───────────────────┘ │
└─────────────────────────────────────────┘
```

- **导航**: MainWindow 侧边栏添加 Tracker 入口 (⏱️)，路由 `/tracker`

## Impl

### Directory Structure
The project must use a modular structure to separate "Core Infrastructure" from "Business Logic". (for reference)

```sh
src/
├── main/
│   ├── core/                   # Infrastructure
│   │   ├── index.ts
│   │   ├── ConfigManager.ts    # `AppConfig`, `ConfigManager`
│   │   ├── DataManager.ts      # `SessionRecord`, `AppData`, `DataManager`, etc
│   │   ├── PathManager.ts      # `PathManager`
│   │   ├── TrayManager.ts      # Handles Icon, Title updates, Click events
│   │   ├── PopupWindow.ts      # Frameless popover window for tray
│   │   ├── MainWindow.ts       # Standard window for stats dashboard
│   │   └── Logger.ts           # Wrapper for electron-log
│   ├── features/               # Feature Modules (Back-end Logic)
│   │   ├── pomodoro/
│   │   │   ├── index.ts
│   │   │   ├── PomodoroService.ts  # Timer logic, State Machine
│   │   │   ├── pomodoro.ipc.ts     # Pomodoro IPC handlers
│   │   │   ├── StatsService.ts     # Statistics aggregation
│   │   │   └── stats.ipc.ts        # Stats IPC handlers
│   │   ├── tracker/
│   │   │   ├── index.ts
│   │   │   ├── types.ts            # ActivityContext, WindowActivityRecord, etc.
│   │   │   ├── TrackerService.ts   # Polling loop, idle detection, merging
│   │   │   ├── TrackerDataManager.ts # Per-day file storage, buffer/flush
│   │   │   └── tracker.ipc.ts      # Tracker IPC handlers
│   │   ├── settings/
│   │   │   ├── index.ts
│   │   │   └── settings.ipc.ts     # Config read/write/validate IPC
│   │   ├── uploader/
│   │   │   ├── index.ts
│   │   │   ├── types.ts               # UploadRecord, UploaderData, CompressResult
│   │   │   ├── UploaderService.ts     # Core upload logic, pending image
│   │   │   ├── UploaderDataManager.ts # JSON storage + cache management
│   │   │   ├── ImageCompressor.ts     # Smart compression, thumbnail generation
│   │   │   ├── GitHubUploader.ts      # Octokit GitHub API
│   │   │   └── uploader.ipc.ts        # IPC handlers
│   │   └── (future_features)/
│   └── index.ts                # Entry point: Initialize Core -> Initialize Features
├── preload/
│   └── index.ts                # Preload API (pomodoro, stats, window, config)
├── renderer/
│   └── src/
│       ├── env.d.ts            # Window.api type declarations for renderer
│       ├── components/         # Shared UI (Button, Card, Icon)
│       ├── features/           # Feature UI Modules
│       │   ├── dashboard/      # The Main Menu (Grid view of tools)
│       │   ├── main/           # MainWindow Layout
│       │   │   └── MainWindowLayout.tsx  # Sidebar + content area
│       │   ├── pomodoro/       # The Timer View
│       │   ├── settings/       # Settings Editor
│       │   │   └── SettingsView.tsx      # Monaco YAML editor
│       │   ├── stats/          # Pomodoro Statistics Dashboard
│       │   │   ├── StatsView.tsx
│       │   │   ├── ActivityCalendar.tsx
│       │   │   ├── WeeklyChart.tsx
│       │   │   └── DailyTimeline.tsx
│       │   ├── tracker/        # Time Tracker Statistics
│       │   │   ├── index.ts
│       │   │   ├── TrackerView.tsx       # Main view
│       │   │   ├── TrackerTimeline.tsx   # 24h timeline
│       │   │   ├── AppUsageChart.tsx     # Donut chart
│       │   │   └── AppRankList.tsx       # Ranked list
│       │   └── uploader/       # Image Uploader
│       │       ├── index.ts
│       │       ├── UploaderView.tsx      # Main view (quality/format controls)
│       │       ├── DropZone.tsx          # Native div for drag & paste
│       │       ├── ImagePreview.tsx      # Click-to-preview modal
│       │       └── UploadHistory.tsx     # Thumbnail loading component
│       └── App.tsx             # Router/View Switcher (hash-based routing)
```
