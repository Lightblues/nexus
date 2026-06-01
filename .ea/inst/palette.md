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

之前的问题是什么? 原本的实现是不是没问题?
我希望也能鼠标操作, hover 行为是不是可以加回来

复现了之前的问题: 1. 使用鼠标/键盘上下选择无法激活某些选项; 2. 最后的 open settings/quit nexus 选项重复!
完整思考一下, 如何 debug?

可以了! 现在操作很直观完全符合预期, 将本次 debug 过程积累经验到 spec 体系中.
```sh
# pitfalls.md 新增/修改的内容:
┌─────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────┐
│              章节               │                                          新增                                           │
├─────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ §3.4 Menu-bar popover dragging  │ NSApp.activate(ignoringOtherApps: true) 是进程级核武器,popover 打开不应使用 — 仅在      │
│ MainWindow forward              │ sheet 等真正需要 key window 的瞬间 just-in-time 调用                                    │
├─────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ §3.5 Palette keyboard nav vs.   │ 两个并发坑合并:① 输入设备模式追踪(Spotlight/Raycast 模式),用 NSTrackingArea             │
│ mouse hover deadlock            │ 区分"光标在区域内 stationary" vs "光标在 motion";② ForEach 不要用 .id(idx) 双键给       │
│                                 │ row,会和 ForEach 自身 identity 打架                                                     │
├─────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ §4.4 "Same bundle id" silently  │ macOS 同 bundle id 第二个实例静默退出的坑;特别是 Xcode debug 进程被 lldb 持有时 kill -9 │
│ masks freshly-installed builds  │  也无效。install-local.sh 现在两边都 kill + 警告                                        │
├─────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ §5 Meta-lesson 3                │ 把这次的 debug 方法论沉淀成"UI bug 与代码不匹配时的 4 步序":先 ps、再                   │
│                                 │ mtime、再读日志、最后才读代码                                                           │
└─────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────┘
```


