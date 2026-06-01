## feat: palette
继续实现 palette
```sh
键盘:
- ↑/↓ 选择
- Enter 执行
- Esc 关闭(不切走当前 app 焦点)

URL Scheme — 任何地方都能跑(终端 / Shortcuts / Raycast Quicklink / AI agent):
open "nexus://command/pomodoro.start"
open "nexus://command/window.openStats"
open "nexus://command/window.openSettings"
open "nexus://command/pomodoro.toggle"

# 关键设计
1. Pomodoro toggle 实时 subtitle——palette 打开时,pomodoro.toggle 行动态显示 running · 12:34 · click to pause 或 paused · 03:21 · click to resume,因为 subtitle 是闭包,每次渲染都重新计算。
2. Panel 不抢焦点——按 Ctrl+Space 召出 palette,你当前在写的代码窗口仍然保持 active(observable: 关掉 palette 不会让 Nexus 变前台)。
3. dangerous 标志已埋——pomodoro.exit、app.quit 标记为 dangerous。当前从 URL scheme 触发只 log warning,UI 确认对话框是 Phase 4.x 的扩展点。
4. Config 热重载——Settings 改了 hotkey 字段,Save 后立即重新注册新键(无需重启 App)。
5. 依赖弱引用——所有 Command 闭包都用 [weak service] / [weak mainWindow],registry 不会环引用。
```
优化交互: 目前在 palette 激活状态, 用鼠标点击外部区域无法将其取消掉

## palette state machine
确认另一个 palette 的体验问题:
- 当 Pomodoro 为暂停状态, 我发现 "Pomodoro: Pause" 选项无法被选中, 没有蓝色聚焦的状态显示出来 -- 这是有意设计吗?
- 如果是状态机的话, 无法选中的命令是不是可以隐藏掉?

目前显示这样的, 前两两个 Pomodoro 命令可以选中 (键盘移动, 浅蓝色); 但是键盘下键无法激活 "finish early" 这个选项



