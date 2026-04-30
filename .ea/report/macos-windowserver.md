# Nexus Tracker — macOS WindowServer 拖累问题诊断与修复方案

> Date: 2026-04-30
> Affected: `src/main/features/tracker/TrackerService.ts`
> Severity: 🔴 High — 在 macOS 上长时间运行后会引发系统级拖放失效

## 摘要

Nexus 的 Auto-Tracker 通过 `osascript` 轮询当前活跃窗口与浏览器 URL。其 AppleScript 实现路径**底层会触发 macOS Accessibility 框架(`universalaccessd` + `AccessibilityUIServer`)的同步查询**,在以下条件叠加时会引发**整个系统的 WindowServer 事件投递管道阻塞**,表现为**全局拖放失效(松开鼠标 drop 不触发)、焦点切换迟钝、可能波及任意 GUI App**。

复现条件:
1. Nexus tracker 启用(默认 5s 轮询)
2. 前台 App 是浏览器(Chrome / Safari / Arc),且浏览器主线程偶尔较忙
3. 持续运行 30 分钟到几小时

修复方向:**消除并发的 AppleScript 调用 + 缓存重复查询 + 收紧超时**,可以让 Nexus 在不破坏系统的前提下安全启用。

---

## 复现的实际症状(2026-04-29 现场记录)

- 拖文件到任意 App,松开鼠标后 drop 不触发,鼠标和触控板都一样
- `WindowServer` 持续 50%+ CPU
- WindowServer 日志:
  - `Clearing datagram buffer for cid 0x1c94df. Data count: 16692. clientMayIgnoreEvents: 1` —— 持续刷,事件队列长期 > 16384 上限
  - `pid 90610 failed to act on a ping it dequeued before timing out` —— 每 10s 一次,稳定持续
- 注销重登可临时恢复;再用一会儿复发

cid `0x1c94df` 反查得到的进程是 `/usr/sbin/universalaccessd`(Apple 的 Accessibility 守护)。但 kill 它让 launchd 重新拉起后,新实例**几秒内又被同样的 ping 失败模式淹没** —— 说明有外部输入持续撞 universalaccessd。

最终通过逐个关闭"系统设置 → 隐私与安全 → 辅助功能"列表里授权的 App 缩小,发现关闭 **Nexus 后系统恢复正常**。

---

## 根因分析

### 路径

```
Nexus tick (every 5s)
  ↓
osascript -e 'tell application "System Events" ... set frontApp to first application process whose frontmost is true ...'
  ↓
osascript 进程启动 → 通过 appleeventsd 给 System Events 发 Apple Event
  ↓
System Events 处理"frontmost is true"过滤器 → 枚举所有进程 → 对每个进程查询 AX 属性
  ↓
universalaccessd / AccessibilityUIServer 同步处理 AX 查询
  ↓
返回 → osascript 退出 → Nexus 拿到结果

如果是浏览器:
  ↓
osascript -e 'tell application "Google Chrome" to return URL of active tab of front window'
  ↓
Apple Event 投递给 Chrome 主线程
  ↓
Chrome 主线程在跑 V8 / 渲染,可能延迟 500ms - 2s 才响应
```

### 雪崩条件

正常情况下,5s 轮询一次 AppleScript,即使每次 ~500ms,也只是 10% 的占空比。问题出在以下几个**并发放大器**同时存在:

1. **`setInterval` 不等上一次 tick 完成**(`TrackerService.ts:204-206`)
   ```ts
   private startPolling(intervalSeconds: number): void {
     this.pollTimer = setInterval(() => this.tick(), intervalSeconds * 1000)
   }
   ```
   当目标 App 偶尔慢(浏览器 GC、VSCode 跑 TypeScript)导致单次 tick 超过 5s 时,**第二个 tick 启动而第一个还在跑**。

2. **每次 tick 都查浏览器 URL,即使前台没变**(`TrackerService.ts:106-119`)
   ```ts
   async function getActiveWindowSafe(): Promise<GetWindowResult> {
     const win = await getActiveWindowAppleScript()
     if (!win) return {}
     if (win.bundleId) {
       const url = await getBrowserUrl(win.bundleId)  // ← 每 5s 都查
       ...
     }
   }
   ```
   即便用户连续 1 小时盯着同一个浏览器标签,每 5s 仍会去 Apple Event 浏览器拿 URL。

3. **AppleScript 用了重路径**(`TrackerService.ts:40`)
   ```applescript
   tell application "System Events"
     set frontApp to first application process whose frontmost is true
   ```
   这个 filter 表达式的语义是"枚举所有 application process,逐个查 frontmost 属性,选第一个为 true 的"。每次都走 AX 全树扫描。

4. **超时偏宽松**(`TrackerService.ts:53, 94`)
   - 主查询 3s,URL 查询 2s。组合起来一次 tick 最差 5s,正好等于轮询周期 → 没有缓冲。

### 雪崩展开

- t=0s tick 1 启动,osascript A 跑 AppleScript-1
- t=0.1s osascript A 卡在 AX 树查询(universalaccessd 忙)
- t=5s tick 2 启动,osascript B 跑 AppleScript-1
- t=5.1s osascript B **也**等 universalaccessd
- t=10s tick 3 启动 → 三个 osascript 同时在等 universalaccessd
- universalaccessd 主线程串行处理 → 队列在 WindowServer 的 event tap 这一侧堆积
- WindowServer 给 universalaccessd 的 datagram buffer(cid 0x1c94df)撑到 16384+
- WindowServer 开始**丢**给 universalaccessd 的事件,以及拖动期间的 mouseUp 协调消息
- 拖放协议握手失败 → 用户感知:松手没反应

### 为什么 logout/重启能修

- 注销销毁当前用户的所有进程,包括 Nexus
- launchd 重启 universalaccessd
- 一切归零

### 为什么 kill universalaccessd 不能修

- launchd 立刻拉新实例
- 新实例起来后,Nexus 的下一次 tick 立刻又开始撞它
- 数秒内重新进入雪崩状态

---

## 代码级问题清单(`src/main/features/tracker/TrackerService.ts`)

### 🔴 P0 — `tick` 没有 in-flight 互斥(导致并发 osascript 雪崩)

**位置:L204-206 + L215-251**

```ts
private startPolling(intervalSeconds: number): void {
  this.pollTimer = setInterval(() => this.tick(), intervalSeconds * 1000)
}

private async tick(): Promise<void> {
  // ... async work, but no guard against re-entry
}
```

**修复:**
```ts
private tickInFlight = false

private async tick(): Promise<void> {
  if (this.tickInFlight) {
    logger.debug('Tracker tick skipped: previous still running')
    return
  }
  this.tickInFlight = true
  try {
    // existing body
  } finally {
    this.tickInFlight = false
  }
}
```

收益:**直接消除并发 osascript 堆积**,这是雪崩的必要条件。

---

### 🔴 P0 — 浏览器 URL 重复查询(放大 osascript 调用 ~80%)

**位置:L106-119**

```ts
async function getActiveWindowSafe(): Promise<GetWindowResult> {
  const win = await getActiveWindowAppleScript()
  if (!win) return {}
  if (win.bundleId) {
    const url = await getBrowserUrl(win.bundleId)  // ← 不该每次都调
    if (url) return { window: { ...win, url } }
  }
  return { window: win }
}
```

URL 只在切换标签或窗口时变化 —— 而切换标签会改变 `win.title`(因为标题变了)。所以**用 `(bundleId, title)` 做 cache key 即可**。

**修复(把 cache 放到 TrackerService 实例上):**

```ts
// In TrackerService class:
private urlCache: { bundleId: string; title?: string; url?: string } | null = null

private async getActiveWindow(): Promise<GetWindowResult> {
  const win = await getActiveWindowAppleScript()
  if (!win) return {}

  // Only browsers need URL enrichment
  const isBrowser = win.bundleId && (
    win.bundleId.includes('Chrome') ||
    win.bundleId === 'com.apple.Safari' ||
    win.bundleId === 'company.thebrowser.Browser'
  )
  if (!isBrowser) return { window: win }

  // Reuse cached URL if app+title unchanged
  if (
    this.urlCache &&
    this.urlCache.bundleId === win.bundleId &&
    this.urlCache.title === win.title &&
    this.urlCache.url
  ) {
    return { window: { ...win, url: this.urlCache.url } }
  }

  // Title changed (or first time) → re-fetch
  const url = await getBrowserUrl(win.bundleId!)
  this.urlCache = { bundleId: win.bundleId!, title: win.title, url }
  return url ? { window: { ...win, url } } : { window: win }
}
```

> 注意:这把 `getActiveWindowSafe` 从顶层函数改为类方法以使用 `this.urlCache`。也可以把 cache 改成模块级 `let` 变量,但实例化更干净。

收益:**每 5s 砍掉一次浏览器 osascript 调用**(只要标题没变),典型场景下 osascript 调用量减少 ~80%。

---

### 🟡 P1 — 收紧 osascript 超时

**位置:L53, L94**

```ts
const { stdout } = await execFileAsync('osascript', ['-e', script], { timeout: 3000 })  // L53
const { stdout } = await execFileAsync('osascript', ['-e', script], { timeout: 2000 })  // L94
```

3s + 2s = 5s,正好等于默认 pollInterval,等于一次卡住能阻塞下一个完整周期。

**修复:**
```ts
{ timeout: 1500 }   // L53 — 主查询
{ timeout: 1000 }   // L94 — URL 查询
```

如果 1.5s 没回 → 这次 tick 就当失败,等下一次。比让它阻塞下一个 tick 好。

---

### 🟡 P1 — AppleScript 用了重路径

**位置:L39-51**

```applescript
tell application "System Events"
  set frontApp to first application process whose frontmost is true
  ...
  set winTitle to name of front window of frontApp
end tell
```

`first application process whose frontmost is true` 会枚举所有进程并对每个查 AX 属性。

**轻量替代(不需要 AX 树扫描):**

```applescript
-- 拿 frontmost App 的 bundle id 和 name(走 LaunchServices,不走 AX)
set frontApp to (path to frontmost application as text)
tell application "System Events"
  set bundleId to bundle identifier of (path to frontmost application)
  set appName to name of (path to frontmost application)
  -- 仍然需要 System Events 拿窗口标题,但不再 filter 全进程列表
  set proc to first process whose bundle identifier is bundleId
  try
    set winTitle to name of front window of proc
  on error
    set winTitle to ""
  end try
end tell
return appName & "|||" & bundleId & "|||" & winTitle
```

或者完全脱离 AppleScript,用 `lsappinfo`(LaunchServices CLI):

```bash
# 拿 frontmost 的 bundleId(零 AX 开销)
lsappinfo info -only bundleID `lsappinfo front`
# 输出:"kCFBundleIdentifierKey"="com.google.Chrome"
```

**最优解:写个 native addon 用 `NSWorkspace.shared.frontmostApplication`,事件驱动 + 零 AX**。Electron 生态里 `active-win` (`get-windows`) 包就是这么做的:

```ts
import activeWindow from 'active-win'  // 或 get-windows
const win = await activeWindow()  // 走 native, 不用 osascript
```

`active-win` 在 macOS 上用 Swift binary,跨过 AppleScript 直接调 NSWorkspace + AX 的轻量接口。**强烈推荐**。

---

### 🟢 P2 — 可观测性不足

目前没有任何关于 tick 健康度的 metric / log。建议加:

```ts
private tickStats = { total: 0, skipped: 0, failed: 0, slowestMs: 0 }

private async tick(): Promise<void> {
  if (this.tickInFlight) {
    this.tickStats.skipped++
    return
  }
  this.tickInFlight = true
  const start = Date.now()
  try {
    // ...
  } catch (e) {
    this.tickStats.failed++
  } finally {
    const dur = Date.now() - start
    if (dur > this.tickStats.slowestMs) this.tickStats.slowestMs = dur
    this.tickStats.total++
    this.tickInFlight = false

    // Warn on cumulative slowness
    if (dur > 2000) {
      logger.warn('Tracker tick slow', { durationMs: dur, app: ??? })
    }
  }
}
```

并在状态接口里暴露这些数字 —— 用户/开发者就能看到 tracker 是不是在反复 skip。

---

## 推荐实施顺序

| 阶段 | 改动 | 预期效果 | 工作量 |
|---|---|---|---|
| 1 | P0-1 互斥锁 + P0-2 URL 缓存 | 80%+ 缓解,可日常启用 | 30 分钟 |
| 2 | P1 收紧超时 + AppleScript 轻量化 | 进一步降低尾部延迟 | 1 小时 |
| 3 | 切换到 `active-win` / native addon | 彻底脱离 AX,根治 | 2-3 小时 |
| 4 | P2 可观测性 | 长期监控 | 30 分钟 |

阶段 1 做完就可以在公司 Mac 上长期开启 Nexus 不破坏系统,阶段 3 是长期正解。

---

## 验证方法

实施改动后,跑下列脚本验证 1 小时内不再产生雪崩:

```bash
# 启动 Nexus,正常使用 1 小时,然后:

# 1. WindowServer CPU 应保持 < 25%(双屏基线)
ps -eo pid,user,%cpu,comm | awk '$4=="WindowServer"' | awk '{print $3}'

# 2. 过去 5 分钟内 buffer-clearing 应接近 0
/usr/bin/log show --last 5m --predicate \
  'process == "WindowServer" AND eventMessage CONTAINS "Clearing datagram buffer"' --info | wc -l
# 健康:< 5    病态:> 50

# 3. 过去 5 分钟内 ping fail 分布应分散
/usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS "failed to act on a ping"' --info \
  | grep -oE "pid [0-9]+" | sort | uniq -c | sort -rn | head
# 健康:每个 PID < 5 次    病态:某个 PID > 20 次

# 4. universalaccessd 健康
ps -p $(pgrep universalaccessd) -o pid,etime,%cpu,comm
# 健康:%cpu < 5,etime 与登录时间一致
# 病态:被反复重启(etime 短)或 %cpu 高
```

如果阶段 1 之后跑这套指标都健康,可以放心日常开启 tracker。

---

## 附录:相关 macOS 内部知识

### AppleScript 是否走 AX

是。`System Events` 是 macOS 内部一个特殊的 AppleScript 接收方,它本身的 process / window / UI element 查询能力**就是建立在 AX framework 之上**。所以"用 AppleScript 不走 AX"是常见误解。

具体来说:
- `application process` / `window` / `UI element` → AX
- `frontmost`, `name` of process → 部分走 AX,部分走 NSWorkspace
- 给具体 App 发 Apple Event(如 Chrome / Safari)→ 不走 AX,但走 appleeventsd 投递到目标 App 主线程

要避开 AX,要么**完全不用 System Events**(改用直接 Apple Event 给具体 App),要么**用 native API**(NSWorkspace、CGWindowList)。

### WindowServer datagram buffer 上限

观察到的 16384 / 16692 / 16400 等数字都贴近 16384,这是 SkyLight 内部对每个 cid(connection id)的 ring buffer 容量。一旦一个客户端的事件队列触到这个上限,WS 会清空 buffer 并标记 client 为"slow consumer"。

### `clientMayIgnoreEvents` 含义

flag = 1 表示客户端通过 `CGSSetConnectionProperty` 告诉 WS"我可能不消费某些事件,你可以丢"。被动 event tap(CGEventTap with passive listener)默认就是这个状态。

意味着 WS 在丢事件时**不会等这个客户端 ack**,但客户端如果消费太慢,buffer 仍会爆 —— 这就是 universalaccessd 的情况。

---

## 2026-04-30 复核: Nexus 修复仍必要,但不能解释全部复现

用户新增事实:
- 昨晚功能恢复,退出 Nexus 后未再启动
- 今天重新开机后,拖放失效再次出现
- 因此需要把本报告的范围限定为:解释 2026-04-29 当时 Nexus 参与的复现链路,而不是宣称 Nexus 是唯一系统根因

实时复核结果:
- `Nexus` / `osascript` 当前无残留进程
- `WindowServer` 当前仍约 54% CPU
- WindowServer 仍持续刷 `Clearing datagram buffer`
- 本次 `failed to act on a ping` 集中在:
  - `PID 70997 /usr/sbin/universalaccessd`
  - `PID 72886 Discord Helper (Renderer)`
  - `PID 95158 /usr/libexec/studentd`
- 本次高频 buffer cid 反查样例:
  - `0x169c6f -> PID 40272 contentlinkingd` (`/System/Library/PrivateFrameworks/Synapse.framework/Support/contentlinkingd`)
  - `0xdc0e3 -> PID 71208 Cursor Helper (GPU)`

结论修正:
- Nexus 的 `TrackerService.ts` 仍有明确代码级风险:无 tick 互斥、重复 AppleScript URL 查询、超时与周期相等、System Events AX 重路径
- 这些修复仍应实施,否则 Nexus 开启后会放大 WindowServer/AX 压力
- 但 2026-04-30 的当前坏状态不是由 Nexus 直接造成;系统还有独立触发链路

对 Nexus 的下一步要求:
1. 不只做 P0 互斥和缓存,应优先移除 AppleScript 主路径,改 native active-window 实现
2. Tracker 状态页要暴露 tick duration / skipped / failed / last app,否则无法在系统异常时自证清白
3. 启动时不要做 3 次连续 `getActiveWindowSafe()` 测试;这会在刚登录系统负载最高时额外敲 AX
4. 在 macOS 上默认把 tracker 设为 opt-in,至少在 26.4.1 环境下如此

系统侧继续排查顺序:
1. 退出 Discord,观察 2-3 分钟 WindowServer 日志是否下降
2. 退出 Cursor/VSCode 或至少减少多窗口/GPU helper,观察 `Cursor Helper (GPU)` cid 是否停止爆
3. 暂停 AltTab 等窗口管理/事件监听工具
4. 检查 Apple Intelligence/Synapse 相关的 `contentlinkingd`
5. 如果仍复现,再看 `studentd` 与企业管控/iOA/QQPCMgr 是否有交互
