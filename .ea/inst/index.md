# Notes
[todo]
- p0
    - [ ] ai: daily report
- basic
    - [ ] CLAUDE: 项目调研的临时文件放到 .tmp 目录, 避免污染 repo
    - [x] ci: github actions
    - [ ] 修复应用图标
    - [x] macOS多屏幕的时候, 点击跳到了第一块屏幕 (不是物理上多块屏幕, 而是 Desktop 1/2)
    - [ ] 快捷键体系
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
- uploader
    - feat: 将 github+jsdelivr 作为图床使用; 支持自定义文件名&路径
    - feat: 上传时自动压缩; 支持 jpg & png
- palette
    - [x] 全局快捷键 (palette): 类似 Raycast. 1} 使用 Ctl+Space 作为激活键; 2} UI 参考 Raycast 的 command palette; 3) 功能: 作为各个 url schema 入口
- 迁移到 Swift
    - [x] Pomodoro
    - [x] Tracker
    - [x] Palette
    - [x] Uploader

[notes]
- key files
    - config: `~/.ea/nexus/config.json`
    - log: ~/.ea/nexus/logs/main.log
