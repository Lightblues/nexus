/** Shapes as the server's /api returns them (services/server/src/summary.ts). */
export interface DaySummary {
  day: string; tz: string; activeSeconds: number; first: number | null; last: number | null
  categories: { category: string; seconds: number }[]
  apps: { app: string; category: string; seconds: number }[]
  projects: { project: string; seconds: number }[]
  domains: { domain: string; category: string; seconds: number }[]
  blocks: { start: number; end: number; category: string; label: string; seconds: number }[]
  pomodoro: {
    work: number; workSeconds: number; completed: number
    projects: { project: string; seconds: number; sessions: number }[]
    sessions?: { start: number; end: number; kind: string; project: string | null; task: string | null; completed: boolean }[]
  }
  devices: string[]
}

export interface Activity {
  id: string; device: string; start: number; end: number; seconds: number; app: string; bundleId: string | null
  category: string; project: string | null; file: string | null; domain: string | null; url: string | null; title: string | null
}

export interface Device { device: string; name: string | null; firstPush: number; lastPush: number; trackerRecords: number; pomodoroSessions: number; lastActivity: number | null }

export function duration(seconds: number): string {
  const m = Math.round(seconds / 60)
  if (m < 60) return `${m}m`
  return `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}m`
}

export function clock(seconds: number | null, tz: string): string {
  if (seconds == null) return '--:--'
  return new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(seconds * 1000)
}

export function stamp(ms: number | null, tz: string): string {
  if (ms == null) return '-'
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
    .formatToParts(ms).filter(x => x.type !== 'literal').map(x => [x.type, x.value]))
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}`
}

const weekday = (day: string) => new Date(`${day}T12:00:00Z`).toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' })

function list<T extends { seconds: number }>(rows: T[], name: (r: T) => string, limit = 8, note: (r: T) => string = () => ''): string {
  const shown = rows.filter(r => r.seconds >= 60).slice(0, limit)
  return shown.length ? shown.map(r => `${name(r)} ${duration(r.seconds)}${note(r)}`).join(' · ') : '-'
}

export function formatDay(s: DaySummary): string {
  const total = s.activeSeconds || 1
  const lines = [
    `${s.day} ${weekday(s.day)} · ${duration(s.activeSeconds)} active · ${s.pomodoro.work} pomodoros (${duration(s.pomodoro.workSeconds)})`
      + (s.first ? ` · ${clock(s.first, s.tz)}–${clock(s.last, s.tz)}` : '') + ` · ${s.devices.length} Mac${s.devices.length === 1 ? '' : 's'}`,
    `Categories  ${list(s.categories, c => c.category, 8, c => c.seconds / total >= 0.05 ? ` (${Math.round(c.seconds / total * 100)}%)` : '')}`,
    `Projects    ${list(s.projects, p => p.project)}`,
    `Apps        ${list(s.apps, a => a.app)}`,
    `Sites       ${list(s.domains, d => d.domain)}`,
  ]
  if (s.blocks.length) {
    lines.push('Blocks')
    for (const b of s.blocks) lines.push(`  ${clock(b.start, s.tz)}–${clock(b.end, s.tz)}  ${b.category.padEnd(13)} ${b.label}  ${duration(b.seconds)}`)
  }
  const sessions = s.pomodoro.sessions ?? []
  if (sessions.length) {
    lines.push('Pomodoros')
    for (const p of sessions) lines.push(`  ${clock(p.start, s.tz)}–${clock(p.end, s.tz)}  ${p.kind.padEnd(10)} ${[p.project, p.task].filter(Boolean).join(' / ')}${p.completed ? '' : '  (stopped)'}`)
  }
  return lines.join('\n')
}

export function formatDays(days: DaySummary[]): string {
  if (!days.length) return 'No summaries in this range.'
  const rows = days.map(d => `${d.day} ${weekday(d.day)}  ${duration(d.activeSeconds).padStart(7)}  ${String(d.pomodoro.work).padStart(2)} pomo  ${list(d.categories, c => c.category, 3)}`)
  const active = days.reduce((n, d) => n + d.activeSeconds, 0), pomos = days.reduce((n, d) => n + d.pomodoro.work, 0)
  return [...rows, `${days.length} days · ${duration(active)} active · ${pomos} pomodoros`].join('\n')
}

export function formatActivities(rows: Activity[], tz: string): string {
  if (!rows.length) return 'No activity rows.'
  return rows.map(a => `${clock(a.start, tz)}  ${duration(a.seconds).padStart(6)}  ${a.category.padEnd(13)} ${a.app}${a.project ? ` · ${a.project}` : a.domain ? ` · ${a.domain}` : ''}${a.file || a.title ? ` · ${(a.file ?? a.title ?? '').slice(0, 80)}` : ''}`).join('\n')
}

export function formatDevices(devices: Device[], tz: string): string {
  if (!devices.length) return 'No devices have pushed yet.'
  return devices.map(d => `${(d.name ?? '(unnamed)').padEnd(24)} ${d.device.slice(0, 8)}  last push ${stamp(d.lastPush, tz)}  last activity ${stamp(d.lastActivity == null ? null : d.lastActivity * 1000, tz)}  ${d.trackerRecords} rows  ${d.pomodoroSessions} sessions`).join('\n')
}
