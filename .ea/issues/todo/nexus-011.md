---
id: nexus-011
title: Persist and restore main window position and size across sessions
status: todo
priority: medium
estimate: S
labels: [feature, ux, macos]
---

## Objective
记住主窗口的位置和尺寸，再次打开时恢复到上次关闭时的状态，避免用户每次重新调整窗口布局。

## Context
- `src/main/index.ts` — BrowserWindow 创建逻辑
- `src/main/core/PathManager.ts` — 数据目录管理（`~/.ea/nexus/`）
- Electron API: `win.getBounds()`, `win.on('resize')`, `win.on('move')`, `screen.getDisplayMatching()`
- 持久化位置: `~/.ea/nexus/window-state.json`

## Tasks
- [ ] 创建 window state 管理模块：读取/写入 `{ x, y, width, height, isMaximized }` 到 `~/.ea/nexus/window-state.json`
- [ ] 在 main window 的 `resize`、`move`、`close` 事件上 debounce 保存 bounds
- [ ] 创建 BrowserWindow 时读取已保存的 state 作为初始参数
- [ ] 处理边界 case：保存位置超出当前可用屏幕时 fallback 到默认居中
- [ ] 处理最大化状态：存储 `isMaximized` 标志，恢复时先设 bounds 再 maximize

## Acceptance
- [ ] 关闭主窗口后重新打开，窗口出现在上次的位置和尺寸
- [ ] 拔掉外接显示器后启动，窗口不会出现在不可见区域
- [ ] 首次启动（无记录）使用合理默认值居中显示

## Boundaries
- Always: 使用已有的 `~/.ea/nexus/` 数据目录，不引入额外依赖
- Always: debounce 写入（避免频繁 IO）
- Never: 不要持久化 palette/popup 等非主窗口的状态
