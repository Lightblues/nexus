# Notes
[todo]
- p0
    - [ ] ai: daily report
- basic
    - [ ] CLAUDE: 项目调研的临时文件放到 .tmp 目录, 避免污染 repo
    - [x] ci: github actions
- macos
    - 应用图标 @Resources/icon-source.png
    - [x] menubar 体验: Pomodoro & 拖拽上传
    - config: 仍采用 `config.json` 存储, @~/Library/Preferences/site.easonsi.nexus.plist 👍
    - [ ] 标准化开发: app data & logs?
- pomodoro | 番茄钟
    - UI: 支持 edit 页面 (tags, projects)
    - 通知设计: 
    - [x] workflow: 番茄钟使用流程 -- setup auto break & `confetti`
    - [ ] feat: pomodoro data -> Notion database
    - [x] fix: pomodoro 默认 task description 和前轮一致
- tracker
    - [x] tracker: 基于 `get-windows` 的实现
    - [x] tracker: view * stat
    - [x] tracker: fix permission error -- changed to ApplyScript
    - [x] 修复统计错误 (com.microsoft.VSCode 被统计成 app=Electron)
- uploader | 图床
    - feat: 将 github+jsdelivr 作为图床使用; 支持自定义文件名&路径
    - feat: 上传时自动压缩; 支持 jpg & png
- palette
    - [x] 全局快捷键 (palette): 类似 Raycast. 1} 使用 `Ctl+Space` 作为激活键; 2} UI 参考 Raycast 的 command palette; 3) 功能: 作为各个 url schema 入口
- 迁移到 Swift
    - [x] Pomodoro
    - [x] Tracker
    - [x] Palette
    - [x] Uploader

[notes]
- key files
    - config: `~/.ea/nexus/config.json`
    - log: ~/.ea/nexus/logs/main.log
