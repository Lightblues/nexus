/** Tracker rows and pomodoro sessions → one summary per local day. Pure; the store feeds it records. */

/** Bump to rebuild every stored summary on the next start (the rules below changed). */
export const SUMMARY_VERSION = 1

export const CATEGORIES = ['coding', 'ai', 'communication', 'meeting', 'notes', 'reading', 'entertainment', 'browsing', 'system', 'other'] as const
export type Category = typeof CATEGORIES[number]

/** First match wins: `domain`, then `bundleId`, then `app` (exact, case-insensitive). A domain matches itself and its subdomains. */
export interface CategoryRules {
  domains?: Record<string, string>
  bundleIds?: Record<string, string>
  apps?: Record<string, string>
}

export const DEFAULT_RULES: Required<CategoryRules> = {
  domains: {
    'github.com': 'coding', 'gitlab.com': 'coding', localhost: 'coding', '127.0.0.1': 'coding', 'stackoverflow.com': 'coding',
    'leetcode.cn': 'coding', 'leetcode.com': 'coding', 'console.cloud.tencent.com': 'coding', 'huggingface.co': 'coding',
    'openai.com': 'ai', 'chatgpt.com': 'ai', 'claude.ai': 'ai', 'gemini.google.com': 'ai', 'chat.deepseek.com': 'ai', 'aistudio.google.com': 'ai',
    'iwiki.woa.com': 'notes', 'doc.weixin.qq.com': 'notes', 'docs.qq.com': 'notes', 'notion.so': 'notes', 'feishu.cn': 'notes',
    'arxiv.org': 'reading', 'zhihu.com': 'reading', 'substack.com': 'reading', 'medium.com': 'reading', 'weread.qq.com': 'reading',
    'bilibili.com': 'entertainment', 'youtube.com': 'entertainment', 'douyin.com': 'entertainment', 'netflix.com': 'entertainment', 'x.com': 'entertainment', 'twitter.com': 'entertainment',
    'mail.google.com': 'communication', 'exmail.qq.com': 'communication', 'meeting.tencent.com': 'meeting', 'zoom.us': 'meeting',
  },
  bundleIds: {
    'com.microsoft.VSCode': 'coding', 'com.microsoft.VSCodeInsiders': 'coding', 'com.todesktop.230313mzl4w4u92': 'coding',
    'com.apple.dt.Xcode': 'coding', 'com.google.antigravity': 'coding', 'com.tencent.codebuddycn': 'coding',
    'com.cmuxterm.app': 'coding', 'com.mitchellh.ghostty': 'coding', 'com.apple.Terminal': 'coding', 'com.googlecode.iterm2': 'coding',
    'dev.warp.Warp-Stable': 'coding', 'sh.paseo.desktop': 'coding', 'com.jetbrains.pycharm': 'coding',
    'com.anthropic.claudefordesktop': 'ai', 'com.openai.chat': 'ai', 'com.google.GeminiMacOS': 'ai', 'com.workbuddy.workbuddy': 'ai',
    'com.tencent.WeWorkMac': 'communication', 'com.tencent.xinWeChat': 'communication', 'ru.keepcoder.Telegram': 'communication',
    'com.electron.lark': 'communication', 'com.tinyspeck.slackmacgap': 'communication', 'com.apple.mail': 'communication',
    'com.tencent.meeting': 'meeting', 'us.zoom.xos': 'meeting',
    'notion.id': 'notes', 'md.obsidian': 'notes', 'io.tana.app': 'notes', 'site.easonsi.Erudite': 'notes',
    'com.apple.Preview': 'reading', 'com.apple.iBooksX': 'reading',
    'com.apple.finder': 'system', 'com.apple.systempreferences': 'system', 'site.easonsi.nexus': 'system',
    'com.google.Chrome': 'browsing', 'com.google.Chrome.beta': 'browsing', 'com.apple.Safari': 'browsing', 'company.thebrowser.Browser': 'browsing',
  },
  apps: {
    'Feishu Meetings': 'meeting', 'Feishu': 'communication', '企业微信': 'communication', 'WeChat': 'communication', '微信': 'communication',
    'Cherry Studio': 'ai', 'Gemini': 'ai', 'Erudite': 'notes', 'Clash Party': 'system', 'System Settings': 'system',
  },
}

/** Apps that report themselves as "Electron"; the Mac app maps the first three itself since v1.3.2. */
const BUNDLE_NAMES: Record<string, string> = {
  'com.microsoft.VSCode': 'Code', 'com.microsoft.VSCodeInsiders': 'Code - Insiders', 'com.todesktop.230313mzl4w4u92': 'Cursor',
  'com.google.antigravity': 'Antigravity', 'com.tencent.codebuddycn': 'CodeBuddy', 'com.workbuddy.workbuddy': 'WorkBuddy',
}
const EDITORS = new Set(['com.microsoft.VSCode', 'com.microsoft.VSCodeInsiders', 'com.todesktop.230313mzl4w4u92'])
const LOCK_SCREEN = new Set(['com.apple.loginwindow', 'com.apple.ScreenSaver.Engine'])
/** Rows from before v1.3.2 could stretch across sleep; no single row counts for more than this. */
export const MAX_ROW_SECONDS = 3600
const BLOCK_GAP_SECONDS = 5 * 60
const BLOCK_MIN_SECONDS = 10 * 60
const TOP = 15

export interface TrackerBody {
  startTime: number; endTime: number; duration: number; app: string; bundleId?: string | null; title?: string | null
  contextProject?: string | null; contextFile?: string | null; contextUrl?: string | null; contextDomain?: string | null; contextRawTitle?: string | null
}
export interface SessionBody { kind: string; startTime: number; endTime: number; duration: number; project?: string | null; task?: string | null; completedFully?: boolean; tags?: string[] }

/** A tracker row as the summaries see it: cleaned, categorized, clipped to one day. */
export interface Activity {
  id: string; device: string; start: number; end: number; seconds: number
  app: string; bundleId: string | null; category: string
  project: string | null; file: string | null; domain: string | null; url: string | null; title: string | null
}

export interface DaySummary {
  day: string; tz: string; version: number
  activeSeconds: number; first: number | null; last: number | null
  categories: { category: string; seconds: number }[]
  apps: { app: string; category: string; seconds: number }[]
  projects: { project: string; seconds: number }[]
  domains: { domain: string; category: string; seconds: number }[]
  blocks: { start: number; end: number; category: string; label: string; seconds: number }[]
  pomodoro: {
    work: number; workSeconds: number; completed: number
    projects: { project: string; seconds: number; sessions: number }[]
    sessions: { start: number; end: number; kind: string; project: string | null; task: string | null; completed: boolean }[]
  }
  devices: string[]
}

// MARK: - Days in a time zone

const formatters = new Map<string, Intl.DateTimeFormat>()
function parts(seconds: number, tz: string): Record<string, number> {
  let f = formatters.get(tz)
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
    formatters.set(tz, f)
  }
  return Object.fromEntries(f.formatToParts(new Date(seconds * 1000)).filter(p => p.type !== 'literal').map(p => [p.type, Number(p.value)]))
}

export function dayOf(seconds: number, tz: string): string {
  const p = parts(seconds, tz)
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`
}

/** Unix seconds of local midnight starting `day`, and of the next one. */
export function dayBounds(day: string, tz: string): [number, number] {
  const start = localMidnight(day, tz)
  const [y, m, d] = day.split('-').map(Number)
  const next = new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10)
  return [start, localMidnight(next, tz)]
}

function localMidnight(day: string, tz: string): number {
  const [y, m, d] = day.split('-').map(Number)
  let guess = Date.UTC(y, m - 1, d) / 1000
  for (let i = 0; i < 2; i++) {
    const p = parts(guess, tz)
    const asUTC = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) / 1000
    guess -= asUTC - Date.UTC(y, m - 1, d) / 1000
  }
  return guess
}

export function isDay(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const [y, m, d] = value.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d)).toISOString().slice(0, 10) === value
}

/** Days a record touches, so a change to it rebuilds each. */
export function daysTouched(body: { startTime?: unknown; endTime?: unknown } | null | undefined, tz: string): string[] {
  const start = Number(body?.startTime), end = Number(body?.endTime ?? body?.startTime)
  if (!Number.isFinite(start) || start <= 0) return []
  const first = dayOf(start, tz), last = dayOf(Math.max(start, Math.min(end, start + 2 * 86400)), tz)
  return first === last ? [first] : [first, last]
}

// MARK: - Cleaning and categories

export function parseEditorTitle(title: string): { file: string | null; project: string | null } {
  const segments = title.split(' — ').map(s => s.trim()).filter(Boolean)
  if (!segments.length) return { file: null, project: null }
  const file = segments[0].replace(/^● /, '')
  if (segments.length < 2) return { file, project: null }
  return { file, project: segments[1].replace(/ \(Workspace\)$/, '') }
}

function lookup(map: Record<string, string> | undefined, key: string | null): string | undefined {
  if (!map || !key) return undefined
  if (key in map) return map[key]
  const lower = key.toLowerCase()
  for (const [k, v] of Object.entries(map)) if (k.toLowerCase() === lower) return v
  return undefined
}

function domainRule(map: Record<string, string> | undefined, domain: string | null): string | undefined {
  if (!map || !domain) return undefined
  for (let d = domain; d; d = d.includes('.') ? d.slice(d.indexOf('.') + 1) : '') {
    const hit = map[d]
    if (hit) return hit
    if (!d.includes('.')) break
  }
  return undefined
}

export function categorize(a: { app: string; bundleId: string | null; domain: string | null }, rules: CategoryRules = {}): string {
  return domainRule(rules.domains, a.domain) ?? domainRule(DEFAULT_RULES.domains, a.domain)
    ?? lookup(rules.bundleIds, a.bundleId) ?? lookup(rules.apps, a.app)
    ?? lookup(DEFAULT_RULES.bundleIds, a.bundleId) ?? lookup(DEFAULT_RULES.apps, a.app)
    ?? 'other'
}

/** A tracker row cleaned for summaries, or null when it is not activity (lock screen, empty). */
export function activity(id: string, device: string, body: TrackerBody, rules: CategoryRules = {}): Activity | null {
  const bundleId = body.bundleId && body.bundleId !== 'missing value' ? body.bundleId : null
  if (bundleId && LOCK_SCREEN.has(bundleId)) return null
  if (body.app === 'loginwindow' || body.app === 'ScreenSaverEngine') return null
  const start = Number(body.startTime)
  const end = Math.min(Number(body.endTime), start + MAX_ROW_SECONDS)
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null
  const app = (bundleId && BUNDLE_NAMES[bundleId] && (body.app === 'Electron' || !body.app)) ? BUNDLE_NAMES[bundleId] : body.app || bundleId || 'Unknown'
  let project = body.contextProject ?? null
  let file = body.contextFile ?? null
  const title = body.title ?? body.contextRawTitle ?? null
  if (bundleId && EDITORS.has(bundleId) && (body.contextRawTitle || body.title)) ({ file, project } = parseEditorTitle(body.contextRawTitle || body.title || ''))
  const domain = body.contextDomain ? body.contextDomain.replace(/^www\./, '') : null
  const out = { id, device, start, end, seconds: end - start, app, bundleId, project, file, domain, url: body.contextUrl ?? null, title, category: '' }
  out.category = categorize(out, rules)
  return out
}

// MARK: - Summaries

function clip(a: Activity, from: number, to: number): Activity | null {
  const start = Math.max(a.start, from), end = Math.min(a.end, to)
  return end > start ? { ...a, start, end, seconds: end - start } : null
}

function top<K extends string>(totals: Map<string, number>, key: K, extra?: (name: string) => Record<string, unknown>) {
  return [...totals].sort((a, b) => b[1] - a[1]).slice(0, TOP).map(([name, seconds]) => ({ [key]: name, ...(extra?.(name) ?? {}), seconds: Math.round(seconds) }))
}

function add(map: Map<string, number>, key: string | null, seconds: number) {
  if (key) map.set(key, (map.get(key) ?? 0) + seconds)
}

/** Time blocks: same-category stretches with gaps under 5 min, kept when at least 10 min long. */
function blocks(acts: Activity[]): DaySummary['blocks'] {
  const out: DaySummary['blocks'] = []
  let cur: { start: number; end: number; category: string; seconds: number; labels: Map<string, number> } | null = null
  const flush = () => {
    if (cur && cur.seconds >= BLOCK_MIN_SECONDS) {
      const label = [...cur.labels].sort((a, b) => b[1] - a[1])[0]?.[0] ?? cur.category
      out.push({ start: cur.start, end: cur.end, category: cur.category, label, seconds: Math.round(cur.seconds) })
    }
  }
  for (const a of acts) {
    if (!cur || a.category !== cur.category || a.start - cur.end > BLOCK_GAP_SECONDS) {
      flush()
      cur = { start: a.start, end: a.end, category: a.category, seconds: 0, labels: new Map() }
    }
    cur.end = Math.max(cur.end, a.end)
    cur.seconds += a.seconds
    add(cur.labels, a.project ?? a.domain ?? a.app, a.seconds)
  }
  flush()
  return out
}

/** Overlapping rows from several Macs count once: the later row only adds the time the earlier ones did not cover. */
function dedupe(acts: Activity[]): Activity[] {
  const out: Activity[] = []
  let covered = -Infinity
  for (const a of [...acts].sort((x, y) => x.start - y.start)) {
    if (a.end <= covered) continue
    const start = Math.max(a.start, covered)
    out.push(start === a.start ? a : { ...a, start, seconds: a.end - start })
    covered = Math.max(covered, a.end)
  }
  return out
}

export function summarizeDay(day: string, tz: string, rows: Activity[], sessions: SessionBody[]): DaySummary {
  const [from, to] = dayBounds(day, tz)
  const acts = dedupe(rows.map(a => clip(a, from, to)).filter((a): a is Activity => !!a))
  const cats = new Map<string, number>(), apps = new Map<string, number>(), projects = new Map<string, number>(), domains = new Map<string, number>()
  const appCat = new Map<string, string>(), domainCat = new Map<string, string>()
  for (const a of acts) {
    add(cats, a.category, a.seconds)
    add(apps, a.app, a.seconds); appCat.set(a.app, a.category)
    add(projects, a.project, a.seconds)
    if (a.domain) { add(domains, a.domain, a.seconds); domainCat.set(a.domain, a.category) }
  }
  const inDay = sessions.filter(s => s.startTime >= from && s.startTime < to).sort((a, b) => a.startTime - b.startTime)
  const work = inDay.filter(s => s.kind === 'work')
  const pomoProjects = new Map<string, { seconds: number; sessions: number }>()
  for (const s of work) {
    const key = s.project || '(none)'
    const p = pomoProjects.get(key) ?? { seconds: 0, sessions: 0 }
    p.seconds += s.duration; p.sessions += 1
    pomoProjects.set(key, p)
  }
  return {
    day, tz, version: SUMMARY_VERSION,
    activeSeconds: Math.round(acts.reduce((n, a) => n + a.seconds, 0)),
    first: acts.length ? Math.min(...acts.map(a => a.start)) : null,
    last: acts.length ? Math.max(...acts.map(a => a.end)) : null,
    categories: top(cats, 'category') as DaySummary['categories'],
    apps: top(apps, 'app', name => ({ category: appCat.get(name) })) as DaySummary['apps'],
    projects: top(projects, 'project') as DaySummary['projects'],
    domains: top(domains, 'domain', name => ({ category: domainCat.get(name) })) as DaySummary['domains'],
    blocks: blocks(acts),
    pomodoro: {
      work: work.length,
      workSeconds: work.reduce((n, s) => n + s.duration, 0),
      completed: work.filter(s => s.completedFully).length,
      projects: [...pomoProjects].sort((a, b) => b[1].seconds - a[1].seconds).map(([project, p]) => ({ project, ...p })),
      sessions: inDay.map(s => ({ start: s.startTime, end: s.endTime, kind: s.kind, project: s.project ?? null, task: s.task ?? null, completed: !!s.completedFully })),
    },
    devices: [...new Set(acts.map(a => a.device))].sort(),
  }
}
