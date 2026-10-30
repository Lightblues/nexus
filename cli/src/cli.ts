import { readFileSync } from 'node:fs'
import { parseArgs } from 'node:util'
import { ApiError, DEFAULT_SERVER, client, configPath, loadConfig, saveConfig, type Client } from './client.ts'
import { formatActivities, formatDay, formatDays, formatDevices, stamp, type Activity, type DaySummary, type Device } from './format.ts'

const VERSION: string = (() => {
  try { return JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version } catch { return '0.0.0' }
})()

const HELP = `nexus ${VERSION} — read your Nexus days from the sync server

Usage: nexus <command> [options]

  today                      Today's summary
  day <when>                 One day: YYYY-MM-DD, today, yesterday, or -N (N days ago)
  days [--last N] [--from D --to D]
                             One line per day (default: the last 7)
  records <when> [--category C] [--app A]
                             The cleaned activity rows of a day
  devices                    Macs (and this CLI) that pushed, with last push and last activity
  categories                 The category rules: yours over the defaults
  categories set <file|->    Replace your rules with a JSON file { domains?, bundleIds?, apps? } (write key)
  config get [prefix]        Synced settings; secrets show only their length (write key)
  config set <key> <value>   Change a synced setting; every Mac applies it on its next sync (write key)
  rebuild                    Recompute every stored day summary (write key)
  doctor                     Check the server, the key, and when each Mac last synced
  login [--server URL]       Save the server and a key (read from stdin) to ${configPath()}

Options: --json prints the server's JSON. NEXUS_URL and NEXUS_KEY override the saved config.
Server: ${DEFAULT_SERVER} unless set.`

export interface Io {
  env: NodeJS.ProcessEnv
  fetch: typeof fetch
  out: (text: string) => void
  err: (text: string) => void
  readStdin: () => Promise<string>
}

interface Me { user: string; name: string; access: 'read' | 'write'; tz: string; today: string }

function shift(day: string, by: number): string {
  const [y, m, d] = day.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + by)).toISOString().slice(0, 10)
}

/** today | yesterday | -N | YYYY-MM-DD, against the server's own today. */
export function resolveDay(when: string | undefined, today: string): string {
  if (!when || when === 'today') return today
  if (when === 'yesterday') return shift(today, -1)
  if (/^-\d+$/.test(when)) return shift(today, Number(when))
  if (/^\d{4}-\d{2}-\d{2}$/.test(when)) return when
  throw new ApiError(0, 'usage', `not a day: ${when} (YYYY-MM-DD, today, yesterday, or -N)`)
}

function parseValue(raw: string): unknown {
  try { return JSON.parse(raw) } catch { return raw }
}

const kindOf = (v: unknown) => Array.isArray(v) ? 'array' : v === null ? 'null' : typeof v

export async function run(argv: string[], io: Io): Promise<number> {
  const { values, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      json: { type: 'boolean' }, help: { type: 'boolean', short: 'h' }, version: { type: 'boolean', short: 'v' },
      last: { type: 'string' }, from: { type: 'string' }, to: { type: 'string' },
      category: { type: 'string' }, app: { type: 'string' }, server: { type: 'string' }, force: { type: 'boolean' },
    },
  })
  const [command, ...args] = positionals
  if (values.version) { io.out(VERSION); return 0 }
  if (values.help || !command || command === 'help') { io.out(HELP); return 0 }

  const config = loadConfig(io.env)
  const show = (data: unknown, text: () => string) => io.out(values.json ? JSON.stringify(data, null, 2) : text())

  try {
    if (command === 'login') {
      const server = (values.server || config.server).replace(/\/+$/, '')
      const key = (await io.readStdin()).trim()
      if (!key) throw new ApiError(0, 'usage', 'paste the key on stdin: `nexus login < keyfile` or type it and press Ctrl-D')
      const me = await client({ server, key }, io.fetch).get<Me>('/api/me')
      const path = saveConfig({ server, key }, io.env)
      io.out(`Signed in to ${server} as ${me.name} (${me.access} key). Saved to ${path}.`)
      return 0
    }

    const api = client(config, io.fetch)
    const me = () => api.get<Me>('/api/me')

    switch (command) {
      case 'today':
      case 'day': {
        const day = resolveDay(command === 'today' ? 'today' : args[0], (await me()).today)
        const s = await api.get<DaySummary>(`/api/days/${day}`)
        show(s, () => formatDay(s))
        return 0
      }
      case 'days': {
        const today = (await me()).today
        const to = values.to ? resolveDay(values.to, today) : today
        const from = values.from ? resolveDay(values.from, today) : shift(to, -(Number(values.last || 7) - 1))
        const { days } = await api.get<{ days: DaySummary[] }>(`/api/days?from=${from}&to=${to}`)
        show(days, () => formatDays(days))
        return 0
      }
      case 'records': {
        const day = resolveDay(args[0], (await me()).today)
        const res = await api.get<{ tz: string; activities: Activity[] }>(`/api/days/${day}/records`)
        const rows = res.activities.filter(a => (!values.category || a.category === values.category) && (!values.app || a.app.toLowerCase() === values.app.toLowerCase()))
        show(rows, () => formatActivities(rows, res.tz))
        return 0
      }
      case 'devices': {
        const [{ tz }, { devices }] = await Promise.all([me(), api.get<{ devices: Device[] }>('/api/devices')])
        show(devices, () => formatDevices(devices, tz))
        return 0
      }
      case 'categories': {
        if (args[0] === 'set') {
          if (!args[1]) throw new ApiError(0, 'usage', 'nexus categories set <file|->')
          const text = args[1] === '-' ? await io.readStdin() : readFileSync(args[1], 'utf8')
          const parsed = JSON.parse(text) as { rules?: unknown }
          const rules = parsed && typeof parsed === 'object' && 'rules' in parsed ? parsed.rules : parsed
          const res = await api.put<{ rebuilt: number }>('/api/categories', { rules })
          show(res, () => `Rules saved; ${res.rebuilt} day summaries changed.`)
          return 0
        }
        const res = await api.get<{ categories: string[]; rules: Record<string, Record<string, string>>; defaults: Record<string, Record<string, string>> }>('/api/categories')
        show(res, () => {
          const lines = [`Categories: ${res.categories.join(', ')}`, 'Match order: domain, then bundle id, then app name; your rules before the defaults.']
          const mine = Object.entries(res.rules).flatMap(([k, m]) => Object.entries(m).map(([n, c]) => `  ${k.padEnd(9)} ${n} → ${c}`))
          lines.push(mine.length ? 'Your rules:' : 'Your rules: none (nexus categories set <file>)', ...mine)
          lines.push(`Defaults: ${Object.values(res.defaults).reduce((n, m) => n + Object.keys(m).length, 0)} rules (--json to list)`)
          return lines.join('\n')
        })
        return 0
      }
      case 'config': {
        const { settings } = await api.get<{ settings: Record<string, unknown> }>('/api/settings')
        if (args[0] === 'get' || !args[0]) {
          const prefix = args[1] ?? ''
          const shown = Object.fromEntries(Object.entries(settings).filter(([k]) => k.startsWith(prefix)))
          show(shown, () => Object.entries(shown).map(([k, v]) => `${k} = ${JSON.stringify(v)}`).join('\n') || `No settings under "${prefix}".`)
          return 0
        }
        if (args[0] === 'set') {
          const [, key, raw] = args
          if (!key || raw === undefined) throw new ApiError(0, 'usage', 'nexus config set <key> <value>')
          const value = parseValue(raw)
          if (!values.force) {
            if (!(key in settings)) throw new ApiError(0, 'usage', `no synced setting "${key}" (see nexus config get); --force to add it`)
            const before = settings[key]
            if (kindOf(before) !== kindOf(value) && !(typeof before === 'string' && before.startsWith('<set,'))) {
              throw new ApiError(0, 'usage', `${key} holds a ${kindOf(before)}, not a ${kindOf(value)}; --force to write it anyway`)
            }
          }
          const res = await api.post<{ results: { rev?: number; stale?: unknown; error?: string }[] }>('/api/sync/push', {
            device: 'cli', deviceName: 'nexus CLI', items: [{ kind: 'setting', id: key, updatedAt: Date.now(), body: { value } }],
          })
          const [result] = res.results
          if (result?.error) throw new ApiError(0, result.error, `server refused ${key}: ${result.error}`)
          if (result?.stale) throw new ApiError(0, 'stale', `a newer edit of ${key} is already on the server; nothing changed`)
          show(res, () => `${key} = ${JSON.stringify(value)} (rev ${result?.rev}). Each Mac applies it on its next sync.`)
          return 0
        }
        throw new ApiError(0, 'usage', 'nexus config get [prefix] | nexus config set <key> <value>')
      }
      case 'rebuild': {
        const res = await api.post<{ rebuilt: number }>('/api/summaries/rebuild', {})
        show(res, () => `${res.rebuilt} day summaries changed.`)
        return 0
      }
      case 'doctor':
        return await doctor(api, config.source, io, values.json === true)
      default:
        io.err(`unknown command: ${command}\n\n${HELP}`)
        return 2
    }
  } catch (error) {
    if (error instanceof ApiError) {
      io.err(`nexus: ${error.message}${error.status === 401 ? ' (the key was refused: nexus login)' : error.status === 403 ? ' (this needs the write key)' : ''}`)
      return error.code === 'usage' ? 2 : 1
    }
    throw error
  }
}

async function doctor(api: Client, source: string, io: Io, json: boolean): Promise<number> {
  /** `warn` is worth a look but not a failure: a Mac that is off for the weekend. */
  const checks: { check: string; ok: boolean | 'warn'; detail: string }[] = []
  const add = (check: string, ok: boolean | 'warn', detail: string) => checks.push({ check, ok, detail })
  add('server', await api.health(), api.server)
  add('key', source !== 'none', source === 'none' ? 'none: run nexus login' : `from ${source}`)
  let me: Me | null = null
  try {
    me = await api.get<Me>('/api/me')
    add('auth', true, `${me.name} (${me.user}), ${me.access} key, days in ${me.tz}`)
  } catch (error) {
    add('auth', false, (error as Error).message)
  }
  if (me) {
    const { devices } = await api.get<{ devices: Device[] }>('/api/devices')
    const now = Date.now()
    for (const d of devices.filter(x => x.device !== 'cli')) {
      const hours = (now - d.lastPush) / 3_600_000
      add(`device ${d.name ?? d.device.slice(0, 8)}`, hours < 24 || 'warn', `last push ${stamp(d.lastPush, me.tz)}${hours >= 24 ? ` (${Math.round(hours / 24)} days ago)` : ''}`)
    }
    const today = await api.get<DaySummary>(`/api/days/${me.today}`)
    add('today', true, `${Math.round(today.activeSeconds / 60)} min active, ${today.pomodoro.work} pomodoros so far`)
  }
  if (json) io.out(JSON.stringify(checks, null, 2))
  else io.out(checks.map(c => `${c.ok === 'warn' ? 'warn' : c.ok ? 'ok  ' : 'FAIL'}  ${c.check.padEnd(22)} ${c.detail}`).join('\n'))
  return checks.every(c => c.ok) ? 0 : 1
}
