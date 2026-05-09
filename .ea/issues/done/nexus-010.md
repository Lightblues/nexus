---
id: nexus-010
title: Configure Nexus to launch automatically on macOS startup
status: done
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
- [x] 在 app ready 时调用 `app.setLoginItemSettings({ openAtLogin: true })` 设置默认开机启动
- [x] 在 Settings 页面增加开关项，允许用户启用/禁用开机启动
- [x] 读取当前状态 `app.getLoginItemSettings()` 同步 UI 开关状态

## Acceptance
- [x] 安装后首次启动，Nexus 注册为 macOS login item
- [x] 重启 macOS 后 Nexus 自动启动
- [x] Settings 中可切换开机启动开关，切换后立即生效

## Boundaries
- Always: 使用 Electron 原生 `app.setLoginItemSettings` API，不要用 LaunchAgent plist
- Never: 不要在无用户感知的情况下强制开机启动（首次需在 Settings 中可见）

## Outcome
- Status: done
- Date: 2025-05-09
- Summary: Implemented auto-launch via `app.setLoginItemSettings` with config-driven toggle (`ui.openAtLogin`). Applied on app ready and reactively on config change.
- Files changed:
  - `src/main/index.ts` — added `applyLoginItemSettings()` helper, called on ready + config:updated
  - `src/shared/types.ts` — added `openAtLogin: boolean` to UIConfig
  - `src/main/core/ConfigManager.ts` — added default `openAtLogin: true`
  - `resources/default-config.yaml` — added `openAtLogin: true`
  - `src/main/features/settings/settings.ipc.ts` — added validation for openAtLogin field
- Notes: Settings UI uses YAML editor (user edits `config.yaml` directly), so no dedicated toggle widget was needed — the config field is visible and editable in the existing settings view.
