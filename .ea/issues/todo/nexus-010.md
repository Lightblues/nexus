---
id: nexus-010
title: Configure Nexus to launch automatically on macOS startup
status: todo
priority: high
estimate: S
labels: [feature, infra, macos]
---

## Objective
Nexus 作为常驻个人工具应在开机时自动启动，避免每次手动打开。利用 Electron 的 login item API 实现 macOS 开机自启。

## Context
- `src/main/index.ts` — main process entry point
- `electron-builder` config in `package.json` or `electron-builder.yml`
- Electron API: `app.setLoginItemSettings({ openAtLogin: true })`
- macOS login items 机制（Launch Services 注册）

## Tasks
- [ ] 在 app ready 时调用 `app.setLoginItemSettings({ openAtLogin: true })` 设置默认开机启动
- [ ] 在 Settings 页面增加开关项，允许用户启用/禁用开机启动
- [ ] 读取当前状态 `app.getLoginItemSettings()` 同步 UI 开关状态

## Acceptance
- [ ] 安装后首次启动，Nexus 注册为 macOS login item
- [ ] 重启 macOS 后 Nexus 自动启动
- [ ] Settings 中可切换开机启动开关，切换后立即生效

## Boundaries
- Always: 使用 Electron 原生 `app.setLoginItemSettings` API，不要用 LaunchAgent plist
- Never: 不要在无用户感知的情况下强制开机启动（首次需在 Settings 中可见）
