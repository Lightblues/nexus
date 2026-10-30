import { createHash, randomBytes } from 'node:crypto'
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

/** The user that existed before there were users; `NEXUS_KEY` and `NEXUS_READ_KEY` belong to it. */
export const OWNER = 'owner'

export type Access = 'write' | 'read'

export interface User {
  id: string
  name: string
  createdAt: number
}

export async function migrate(db: Db): Promise<void> {
  await db.query(`
    CREATE SEQUENCE IF NOT EXISTS record_rev;
    CREATE TABLE IF NOT EXISTS users (
      id text PRIMARY KEY,
      name text NOT NULL,
      created_at bigint NOT NULL
    );
    INSERT INTO users (id, name, created_at) VALUES ('${OWNER}', '${OWNER}', ${Date.now()}) ON CONFLICT (id) DO NOTHING;
    CREATE TABLE IF NOT EXISTS keys (
      hash text PRIMARY KEY,
      user_id text NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      access text NOT NULL CHECK (access IN ('write', 'read')),
      label text NOT NULL DEFAULT '',
      source text NOT NULL DEFAULT 'db' CHECK (source IN ('db', 'env')),
      created_at bigint NOT NULL
    );
    CREATE TABLE IF NOT EXISTS records (
      user_id text NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      kind text NOT NULL,
      id text NOT NULL,
      rev bigint NOT NULL,
      updated_at bigint NOT NULL,
      device text NOT NULL,
      deleted boolean NOT NULL DEFAULT false,
      body jsonb,
      PRIMARY KEY (user_id, kind, id)
    );
  `)
  // Databases from before users: their records belong to the owner.
  const { rows } = await db.query(`SELECT 1 FROM information_schema.columns WHERE table_name = 'records' AND column_name = 'user_id'`)
  if (!rows.length) {
    await db.tx(async query => {
      await query(`ALTER TABLE records ADD COLUMN user_id text NOT NULL DEFAULT '${OWNER}' REFERENCES users (id) ON DELETE CASCADE`)
      await query('ALTER TABLE records ALTER COLUMN user_id DROP DEFAULT')
      await query('ALTER TABLE records DROP CONSTRAINT records_pkey')
      await query('ALTER TABLE records ADD PRIMARY KEY (user_id, kind, id)')
      await query('DROP INDEX IF EXISTS records_rev')
    })
  }
  await db.query('CREATE INDEX IF NOT EXISTS records_user_rev ON records (user_id, rev)')
}

export function hashKey(key: string): string {
  return createHash('sha256').update(key).digest('hex')
}

/** Makes the keys from the environment the owner's env keys, dropping env keys no longer set. */
export async function syncEnvKeys(db: Db, keys: { write: string; read?: string }): Promise<void> {
  await db.tx(async query => {
    await query(`DELETE FROM keys WHERE source = 'env'`)
    const add = (key: string, access: Access) => query(
      `INSERT INTO keys (hash, user_id, access, label, source, created_at) VALUES ($1, $2, $3, $4, 'env', $5)`,
      [hashKey(key), OWNER, access, `NEXUS_${access === 'write' ? '' : 'READ_'}KEY`, Date.now()],
    )
    await add(keys.write, 'write')
    if (keys.read) await add(keys.read, 'read')
  })
}

export async function authenticate(db: Db, key: string): Promise<{ user: string; access: Access } | null> {
  if (!key) return null
  const { rows } = await db.query<{ user_id: string; access: Access }>('SELECT user_id, access FROM keys WHERE hash = $1', [hashKey(key)])
  return rows[0] ? { user: rows[0].user_id, access: rows[0].access } : null
}

export async function addUser(db: Db, name: string): Promise<User> {
  const user = { id: `u_${randomBytes(6).toString('hex')}`, name, createdAt: Date.now() }
  await db.query('INSERT INTO users (id, name, created_at) VALUES ($1, $2, $3)', [user.id, user.name, user.createdAt])
  return user
}

export async function listUsers(db: Db): Promise<(User & { keys: number; records: number })[]> {
  const { rows } = await db.query<{ id: string; name: string; created_at: number; keys: number; records: number }>(`
    SELECT u.id, u.name, u.created_at::float8 AS created_at,
      (SELECT count(*) FROM keys k WHERE k.user_id = u.id)::int AS keys,
      (SELECT count(*) FROM records r WHERE r.user_id = u.id)::int AS records
    FROM users u ORDER BY u.created_at`)
  return rows.map(r => ({ id: r.id, name: r.name, createdAt: Number(r.created_at), keys: r.keys, records: r.records }))
}

/** A new random key for the user; only its hash is stored, so the caller must hand the key over now. */
export async function addKey(db: Db, user: string, access: Access, label = ''): Promise<string> {
  const key = `nx_${randomBytes(24).toString('base64url')}`
  await db.query(
    `INSERT INTO keys (hash, user_id, access, label, source, created_at) VALUES ($1, $2, $3, $4, 'db', $5)`,
    [hashKey(key), user, access, label, Date.now()],
  )
  return key
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

/** Every read and write is scoped to one user; the rev sequence is shared, so a user's cursor skips other users' revs. */
export function openStore(db: Db) {
  async function page(user: string, since: number, kinds: readonly string[], rows: number, maxBytes: number): Promise<Page> {
    const found = await db.query<Row>(
      `SELECT ${COLUMNS} FROM records WHERE user_id = $1 AND rev > $2 AND kind = ANY($3) ORDER BY rev LIMIT $4`,
      [user, since, kinds, rows + 1],
    )
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
    async push(user: string, device: string, items: unknown[]): Promise<PushResult[]> {
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
          const { rows } = await query<Row>(`SELECT ${COLUMNS} FROM records WHERE user_id = $1 AND kind = $2 AND id = $3`, [user, item.kind, item.id])
          const current = rows[0] ? toRecord(rows[0]) : undefined
          if (current && item.updatedAt <= current.updatedAt) {
            results[at].stale = current
            continue
          }
          const saved = await query<{ rev: number }>(
            `INSERT INTO records (user_id, kind, id, rev, updated_at, device, deleted, body)
             VALUES ($1, $2, $3, nextval('record_rev'), $4, $5, $6, $7::jsonb)
             ON CONFLICT (user_id, kind, id) DO UPDATE SET rev = excluded.rev, updated_at = excluded.updated_at, device = excluded.device, deleted = excluded.deleted, body = excluded.body
             RETURNING rev::float8 AS rev`,
            [user, item.kind, item.id, item.updatedAt, device, item.deleted === true, item.json],
          )
          results[at].rev = Number(saved.rows[0].rev)
        }
      })
      return results
    },

    /** Records written after `since`, oldest first; a page stops at `maxBytes` but always carries one record. */
    pull(user: string, since: number, kinds: readonly string[] = KINDS, maxBytes = PULL_PAGE_BYTES): Promise<Page> {
      return page(user, since, kinds, PULL_PAGE_ROWS, maxBytes)
    },

    async status(user: string): Promise<{ rev: number; kinds: Record<string, { records: number; deleted: number }> }> {
      const counts = await db.query<{ kind: string; live: number; deleted: number }>(
        `SELECT kind, count(*) FILTER (WHERE NOT deleted)::int AS live, count(*) FILTER (WHERE deleted)::int AS deleted FROM records WHERE user_id = $1 GROUP BY kind`,
        [user],
      )
      const latest = await db.query<{ rev: number }>('SELECT coalesce(max(rev), 0)::float8 AS rev FROM records WHERE user_id = $1', [user])
      const kinds = Object.fromEntries(KINDS.map(kind => [kind, { records: 0, deleted: 0 }]))
      for (const row of counts.rows) kinds[row.kind] = { records: Number(row.live), deleted: Number(row.deleted) }
      return { rev: Number(latest.rows[0]?.rev ?? 0), kinds }
    },

    async exportChanges(user: string, since: number, kinds: string[], limit = 100): Promise<{ items: ExportItem[]; cursor: string; more: boolean }> {
      const allowed = kinds.length ? kinds.filter(kind => kind in EXPORT_KINDS) : Object.keys(EXPORT_KINDS)
      const found = await page(user, since, allowed, limit, PULL_PAGE_BYTES)
      return {
        items: found.records.map(rec => ({ kind: rec.kind, id: rec.id, updatedAt: rec.updatedAt, deleted: rec.deleted, data: rec.deleted ? null : rec.body })),
        cursor: String(found.cursor),
        more: found.more,
      }
    },
  }
}

export type Store = ReturnType<typeof openStore>
