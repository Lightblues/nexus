import { CATEGORIES, DEFAULT_RULES, MAX_ROW_SECONDS, SUMMARY_VERSION, activity, dayBounds, dayOf, daysTouched, summarizeDay, type Activity, type CategoryRules, type DaySummary, type SessionBody, type TrackerBody } from './summary.ts'
import type { Db, Store } from './store.ts'

const SUMMARY = 'day_summary'
/** Pushes arrive every few seconds while a Mac is active; stored summaries catch up this long after the last one. */
const REBUILD_DELAY_MS = 20_000
const SECRET_SETTING = /(token|secret|password|apiKey)$/i

/** Server-side reads of a user's data, and the stored day summaries that follow every push. */
export function openDays(db: Db, store: Store, tz: string, delayMs = REBUILD_DELAY_MS) {
  const pending = new Map<string, Set<string>>()
  let timer: NodeJS.Timeout | undefined
  let running: Promise<void> = Promise.resolve()

  async function rules(user: string): Promise<CategoryRules> {
    const { rows } = await db.query<{ rules: CategoryRules }>('SELECT rules FROM categories WHERE user_id = $1', [user])
    return rows[0]?.rules ?? {}
  }

  async function rowsOf(user: string, from: number, to: number, kind: string) {
    return (await db.query<{ id: string; device: string; body: unknown }>(
      `SELECT id, device, body FROM records WHERE user_id = $1 AND kind = $2 AND start_at >= $3 AND start_at < $4 AND NOT deleted ORDER BY start_at`,
      [user, kind, from, to],
    )).rows
  }

  async function day(user: string, dayKey: string, categoryRules?: CategoryRules): Promise<{ summary: DaySummary; activities: Activity[]; sessions: SessionBody[] }> {
    const [from, to] = dayBounds(dayKey, tz)
    const r = categoryRules ?? await rules(user)
    const tracker = await rowsOf(user, from - MAX_ROW_SECONDS, to, 'tracker_record')
    const activities = tracker.map(row => activity(row.id, row.device, row.body as TrackerBody, r)).filter((a): a is Activity => !!a && a.end > from && a.start < to)
    const sessions = (await rowsOf(user, from, to, 'pomodoro_session')).map(row => row.body as SessionBody)
    return { summary: summarizeDay(dayKey, tz, activities, sessions), activities, sessions }
  }

  async function stored(user: string, dayKey: string): Promise<DaySummary | null> {
    const { rows } = await db.query<{ body: DaySummary }>(`SELECT body FROM records WHERE user_id = $1 AND kind = $2 AND id = $3 AND NOT deleted`, [user, SUMMARY, dayKey])
    return rows[0]?.body ?? null
  }

  /** Recomputes and stores the days' summaries, writing only those that changed; empty days with nothing stored stay absent. */
  async function rebuild(user: string, days: Iterable<string>): Promise<number> {
    const r = await rules(user)
    let written = 0
    for (const dayKey of days) {
      const { summary } = await day(user, dayKey, r)
      const before = await stored(user, dayKey)
      const empty = !summary.activeSeconds && !summary.pomodoro.sessions.length
      if (!before && empty) continue
      if (before && JSON.stringify(before) === JSON.stringify(summary)) continue
      await store.putServerRecord(user, SUMMARY, dayKey, summary)
      written++
    }
    return written
  }

  /** Every day the user has data on, when the rules, version, or time zone differ from what built the stored summaries. */
  async function rebuildAllIfStale(user: string, force = false): Promise<number> {
    const state = await db.query<{ version: number; tz: string }>('SELECT version, tz FROM summary_state WHERE user_id = $1', [user])
    if (!force && state.rows[0]?.version === SUMMARY_VERSION && state.rows[0]?.tz === tz) return 0
    const span = await db.query<{ min: number | null; max: number | null }>(
      `SELECT min(start_at) AS min, max(start_at) AS max FROM records WHERE user_id = $1 AND start_at IS NOT NULL AND NOT deleted`, [user])
    const { min, max } = span.rows[0] ?? {}
    const days = new Set<string>()
    if (min != null && max != null) {
      for (let d = dayOf(Number(min), tz); d <= dayOf(Number(max), tz); d = nextDay(d)) days.add(d)
    }
    // Days whose stored summary has no data left must be rewritten empty too.
    for (const row of (await db.query<{ id: string }>(`SELECT id FROM records WHERE user_id = $1 AND kind = $2 AND NOT deleted`, [user, SUMMARY])).rows) days.add(row.id)
    const written = await rebuild(user, [...days].sort())
    await db.query(
      `INSERT INTO summary_state (user_id, version, tz) VALUES ($1, $2, $3) ON CONFLICT (user_id) DO UPDATE SET version = excluded.version, tz = excluded.tz`,
      [user, SUMMARY_VERSION, tz],
    )
    return written
  }

  function flush() {
    timer = undefined
    const jobs = [...pending]
    pending.clear()
    running = running.then(async () => {
      for (const [user, days] of jobs) {
        try {
          await rebuild(user, [...days].sort())
        } catch (error) {
          console.error(`[nexus-server] summary rebuild failed user=${user}:`, (error as Error).message)
        }
      }
    })
  }

  return {
    day,
    rebuild,
    rebuildAllIfStale,

    /** Hook for `store.push`: queues the days a written record touches. */
    changed(user: string) {
      return (kind: string, body: unknown) => {
        if (kind !== 'tracker_record' && kind !== 'pomodoro_session') return
        const set = pending.get(user) ?? new Set<string>()
        for (const d of daysTouched(body as { startTime?: unknown; endTime?: unknown }, tz)) set.add(d)
        if (!set.size) return
        pending.set(user, set)
        timer ??= setTimeout(flush, delayMs)
      }
    },

    /** Runs queued rebuilds now and resolves when every rebuild so far has finished. */
    async settle(): Promise<void> {
      if (timer) { clearTimeout(timer); flush() }
      await running
    },

    async startup(): Promise<void> {
      const users = (await db.query<{ id: string }>('SELECT id FROM users')).rows
      for (const { id } of users) {
        const written = await rebuildAllIfStale(id)
        if (written) console.log(`[nexus-server] summaries rebuilt user=${id} days=${written}`)
      }
    },

    async summaries(user: string, from: string, to: string): Promise<DaySummary[]> {
      const { rows } = await db.query<{ body: DaySummary }>(
        `SELECT body FROM records WHERE user_id = $1 AND kind = $2 AND id >= $3 AND id <= $4 AND NOT deleted ORDER BY id`,
        [user, SUMMARY, from, to],
      )
      return rows.map(r => r.body)
    },

    async devices(user: string) {
      const { rows } = await db.query<{ device: string; name: string | null; first_push: number; last_push: number; tracker: number; sessions: number; last_activity: number | null }>(`
        SELECT d.device, d.name, d.first_push::float8 AS first_push, d.last_push::float8 AS last_push,
          (SELECT count(*) FROM records r WHERE r.user_id = d.user_id AND r.device = d.device AND r.kind = 'tracker_record' AND NOT r.deleted)::int AS tracker,
          (SELECT count(*) FROM records r WHERE r.user_id = d.user_id AND r.device = d.device AND r.kind = 'pomodoro_session' AND NOT r.deleted)::int AS sessions,
          (SELECT max(r.start_at) FROM records r WHERE r.user_id = d.user_id AND r.device = d.device AND r.kind = 'tracker_record' AND NOT r.deleted) AS last_activity
        FROM devices d WHERE d.user_id = $1 ORDER BY d.last_push DESC`, [user])
      return rows.map(r => ({
        device: r.device, name: r.name, firstPush: Number(r.first_push), lastPush: Number(r.last_push),
        trackerRecords: r.tracker, pomodoroSessions: r.sessions, lastActivity: r.last_activity == null ? null : Number(r.last_activity),
      }))
    },

    async categories(user: string) {
      return { categories: CATEGORIES, rules: await rules(user), defaults: DEFAULT_RULES }
    },

    /** Replaces the user's rules and rebuilds every summary with them. */
    async setCategories(user: string, next: CategoryRules): Promise<number> {
      await db.query(
        `INSERT INTO categories (user_id, rules, updated_at) VALUES ($1, $2::jsonb, $3) ON CONFLICT (user_id) DO UPDATE SET rules = excluded.rules, updated_at = excluded.updated_at`,
        [user, JSON.stringify(next), Date.now()],
      )
      return rebuildAllIfStale(user, true)
    },

    /** The synced settings as key → value; values of secret-looking keys are replaced by a note of their length. */
    async settings(user: string): Promise<Record<string, unknown>> {
      const { rows } = await db.query<{ id: string; body: { value: unknown } }>(
        `SELECT id, body FROM records WHERE user_id = $1 AND kind = 'setting' AND NOT deleted ORDER BY id`, [user])
      return Object.fromEntries(rows.map(r => {
        const value = r.body?.value
        if (SECRET_SETTING.test(r.id) && typeof value === 'string' && value) return [r.id, `<set, ${value.length} chars>`]
        return [r.id, value]
      }))
    },
  }
}

export type Days = ReturnType<typeof openDays>

export function nextDay(day: string): string {
  const [y, m, d] = day.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10)
}

export function isRules(value: unknown): value is CategoryRules {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  return Object.entries(value).every(([k, v]) => ['domains', 'bundleIds', 'apps'].includes(k)
    && !!v && typeof v === 'object' && !Array.isArray(v)
    && Object.values(v).every(c => typeof c === 'string' && c.length > 0 && c.length <= 40))
}
