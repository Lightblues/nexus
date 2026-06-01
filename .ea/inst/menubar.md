
## fix menubar click behavior
解释一下现在多次点击 Nexus 的 menubar 图标会发生什么? 多屏状态下有何变化?

我感觉现在的基本逻辑都是 OK 的. 测试下来一个不舒服的地方是:
- 当在 A 屏有 Nexus 主窗口的时候, 在 B 屏点击 menubar icon, 行为似乎不太稳定
    - 可能是第一次点击显示 popover; 第二次点击窗口聚焦到了主窗口上 (尽管 Nexus 主窗口在之前并不是我聚焦的内容, 我可能正在 vscode 中)
- 我原本预期的行为是, menubar 的操作和主窗口活动是独立的, 只能通过 "show main window" 激活主窗口
