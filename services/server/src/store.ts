import pg from 'pg'

export const MAX_BODY_BYTES = 64 * 1024
export const MAX_PUSH_ITEMS = 1000
export const MAX_PUSH_BYTES = 1024 * 1024
export const PULL_PAGE_BYTES = 256 * 1024
const PULL_PAGE_ROWS = 1000
const MAX_ID_LENGTH = 200
/** Key of the transaction-scoped advisory lock every write takes before drawing a rev. */
const WRITE_LOCK = 0x6e6578

export const KINDS = ['setting', 'pomodoro_session', 'pomodoro_project', 'pomodoro_tag', 'tracker_record'] as const
export type Kind = typeof KINDS[number]
/** Kinds other apps may read through /export. Settings hold the uploader's GitHub token and never leave the sync path. */
export const EXPORT_KINDS: Record<string, string> = {
  pomodoro_session: 'One pomodoro session: kind (work, shortBreak, longBreak), start and end time (unix seconds), duration, project, task, whether it ran fully, and its tags.',
  pomodoro_project: 'A pomodoro project, by name, with its display color.',
  pomodoro_tag: 'A tag name in the pomodoro tag catalog.',
  tracker_record: 'One stretch of time in a foreground app: start and end time (unix seconds), duration, app, bundle id, window title, and context (project, file, URL, domain).',
}

type Query = <R = Record<string, unknown>>(text: string, params?: unknown[]) => Promise<{ rows: R[] }>

export interface Db {
  query: Query
  tx<T>(fn: (query: Query) => Promise<T>): Promise<T>
  close(): Promise<void>
}

export function pgDb(url: string): Db {
  const pool = new pg.Pool({ connectionString: url, max: 4 })
  return {
    query: (text, params) => pool.query(text, params as unknown[]) as never,
    async tx(fn) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        const out = await fn((text, params) => client.query(text, params as unknown[]) as never)
        await client.query('COMMIT')
        return out
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {})
        throw error
      } finally {
        client.release()
      }
    },
    close: () => pool.end(),
  }
}

export interface PushItem {
  kind: string
  id: string
  /** Unix epoch milliseconds of the edit on the device. */
  updatedAt: number
  deleted?: boolean
  body?: unknown
}

export interface StoredRecord {
  kind: string
  id: string
  rev: number
  updatedAt: number
  deleted: boolean
  /** The device whose write this is. */
  device: string
  body: unknown
}

export interface PushResult {
  kind: string
  id: string
  /** Set when the write was accepted. */
  rev?: number
  /** The stored record, when it is as new as or newer than the write; the device applies it instead. */
  stale?: StoredRecord
  error?: string
}

export interface Page {
  records: StoredRecord[]
  cursor: number
  more: boolean
}

export interface ExportItem {
  kind: string
  id: string
  updatedAt: number
  deleted: boolean
  data: unknown
}

interface Row {
  kind: string
  id: string
  rev: number
  updated_at: number
  deleted: boolean
  device: string
  body: unknown
}

const COLUMNS = 'kind, id, rev::float8 AS rev, updated_at::float8 AS updated_at, deleted, device, body'

export async function migrate(db: Db): Promise<void> {
  await db.query(`
    CREATE SEQUENCE IF NOT EXISTS record_rev;
    CREATE TABLE IF NOT EXISTS records (
      kind text NOT NULL,
      id text NOT NULL,
      rev bigint NOT NULL,
      updated_at bigint NOT NULL,
      device text NOT NULL,
      deleted boolean NOT NULL DEFAULT false,
      body jsonb,
      PRIMARY KEY (kind, id)
    );
    CREATE INDEX IF NOT EXISTS records_rev ON records (rev);
  `)
}

export function isKind(kind: string): kind is Kind {
  return (KINDS as readonly string[]).includes(kind)
}

function toRecord(row: Row): StoredRecord {
  return { kind: row.kind, id: row.id, rev: Number(row.rev), updatedAt: Number(row.updated_at), deleted: row.deleted, device: row.device, body: row.body }
}

/** A valid write with its body serialized, or the error code for the item. */
function check(item: unknown): (PushItem & { json: string | null }) | string {
  if (!item || typeof item !== 'object') return 'invalid'
  const { kind, id, updatedAt, deleted, body } = item as Record<string, unknown>
  if (typeof kind !== 'string' || !isKind(kind)) return 'unknown_kind'
  if (typeof id !== 'string' || !id || id.length > MAX_ID_LENGTH) return 'invalid_id'
  if (typeof updatedAt !== 'number' || !Number.isSafeInteger(updatedAt) || updatedAt < 0) return 'invalid_updated_at'
  if (deleted !== undefined && typeof deleted !== 'boolean') return 'invalid'
  if (deleted) return { kind, id, updatedAt, deleted: true, json: null }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'invalid_body'
  if (kind === 'setting' && !('value' in body)) return 'invalid_body'
  const json = JSON.stringify(body)
  if (Buffer.byteLength(json) > MAX_BODY_BYTES) return 'too_large'
  return { kind, id, updatedAt, deleted: false, body, json }
}

function headOf(item: unknown): { kind: string; id: string } {
  const { kind, id } = (item && typeof item === 'object' ? item : {}) as Record<string, unknown>
  return { kind: typeof kind === 'string' ? kind : '', id: typeof id === 'string' ? id : '' }
}

export function openStore(db: Db) {
  async function page(since: number, kinds: readonly string[], rows: number, maxBytes: number): Promise<Page> {
    const found = await db.query<Row>(`SELECT ${COLUMNS} FROM records WHERE rev > $1 AND kind = ANY($2) ORDER BY rev LIMIT $3`, [since, kinds, rows + 1])
    const records: StoredRecord[] = []
    let bytes = 0
    for (const row of found.rows.slice(0, rows)) {
      const record = toRecord(row)
      const size = Buffer.byteLength(JSON.stringify(record))
      if (records.length && bytes + size > maxBytes) break
      records.push(record)
      bytes += size
    }
    return { records, cursor: records.at(-1)?.rev ?? since, more: found.rows.length > records.length }
  }

  return {
    /** Last write wins per record by `updatedAt`; on a tie the stored copy stays. */
    async push(device: string, items: unknown[]): Promise<PushResult[]> {
      const results: PushResult[] = items.map(headOf)
      const writes: { at: number; item: PushItem & { json: string | null } }[] = []
      items.forEach((item, at) => {
        const checked = check(item)
        if (typeof checked === 'string') results[at].error = checked
        else writes.push({ at, item: checked })
      })
      if (!writes.length) return results

      await db.tx(async query => {
        // Revs must commit in the order they are drawn, or a reader whose cursor passed a later rev skips an earlier one.
        await query('SELECT pg_advisory_xact_lock($1)', [WRITE_LOCK])
        for (const { at, item } of writes) {
          const { rows } = await query<Row>(`SELECT ${COLUMNS} FROM records WHERE kind = $1 AND id = $2`, [item.kind, item.id])
          const current = rows[0] ? toRecord(rows[0]) : undefined
          if (current && item.updatedAt <= current.updatedAt) {
            results[at].stale = current
            continue
          }
          const saved = await query<{ rev: number }>(
            `INSERT INTO records (kind, id, rev, updated_at, device, deleted, body)
             VALUES ($1, $2, nextval('record_rev'), $3, $4, $5, $6::jsonb)
             ON CONFLICT (kind, id) DO UPDATE SET rev = excluded.rev, updated_at = excluded.updated_at, device = excluded.device, deleted = excluded.deleted, body = excluded.body
             RETURNING rev::float8 AS rev`,
            [item.kind, item.id, item.updatedAt, device, item.deleted === true, item.json],
          )
          results[at].rev = Number(saved.rows[0].rev)
        }
      })
      return results
    },

    /** Records written after `since`, oldest first; a page stops at `maxBytes` but always carries one record. */
    pull(since: number, kinds: readonly string[] = KINDS, maxBytes = PULL_PAGE_BYTES): Promise<Page> {
      return page(since, kinds, PULL_PAGE_ROWS, maxBytes)
    },

    async status(): Promise<{ rev: number; kinds: Record<string, { records: number; deleted: number }> }> {
      const counts = await db.query<{ kind: string; live: number; deleted: number }>(
        `SELECT kind, count(*) FILTER (WHERE NOT deleted)::int AS live, count(*) FILTER (WHERE deleted)::int AS deleted FROM records GROUP BY kind`,
      )
      const latest = await db.query<{ rev: number }>('SELECT coalesce(max(rev), 0)::float8 AS rev FROM records')
      const kinds = Object.fromEntries(KINDS.map(kind => [kind, { records: 0, deleted: 0 }]))
      for (const row of counts.rows) kinds[row.kind] = { records: Number(row.live), deleted: Number(row.deleted) }
      return { rev: Number(latest.rows[0]?.rev ?? 0), kinds }
    },

    async exportChanges(since: number, kinds: string[], limit = 100): Promise<{ items: ExportItem[]; cursor: string; more: boolean }> {
      const allowed = kinds.length ? kinds.filter(kind => kind in EXPORT_KINDS) : Object.keys(EXPORT_KINDS)
      const found = await page(since, allowed, limit, PULL_PAGE_BYTES)
      return {
        items: found.records.map(rec => ({ kind: rec.kind, id: rec.id, updatedAt: rec.updatedAt, deleted: rec.deleted, data: rec.deleted ? null : rec.body })),
        cursor: String(found.cursor),
        more: found.more,
      }
    },
  }
}

export type Store = ReturnType<typeof openStore>
