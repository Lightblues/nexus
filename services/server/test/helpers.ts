import assert from 'node:assert/strict'
import { PGlite } from '@electric-sql/pglite'
import { startServer } from '../src/server.ts'
import type { Db, PushResult, StoredRecord } from '../src/store.ts'

export const KEY = 'write-key'
export const READ = 'read-key'

export function pgliteDb(): Db {
  const pg = new PGlite()
  const wrap = (q: { query: PGlite['query']; exec: PGlite['exec'] }) => async (text: string, params?: unknown[]) => {
    if (params?.length) return await q.query(text, params) as never
    const results = await q.exec(text)
    return { rows: results.at(-1)?.rows ?? [] } as never
  }
  return {
    query: wrap(pg),
    tx: fn => pg.transaction(tx => fn(wrap(tx as never))),
    close: () => pg.close(),
  }
}

export type Pulled = { records: StoredRecord[]; cursor: number; more: boolean }
export type Exported = { items: { kind: string; id: string; updatedAt: number; deleted: boolean; data: unknown }[]; cursor: string; more: boolean }

export async function boot(db = pgliteDb(), key = KEY, readKey = READ) {
  const server = await startServer({ key, readKey, host: '127.0.0.1', port: 0, db, tz: 'Asia/Shanghai', rebuildDelayMs: 600_000 })
  const base = `http://127.0.0.1:${server.port}`
  const headers = (key: string) => ({ authorization: `Bearer ${key}`, 'content-type': 'application/json' })
  return {
    base,
    get: (path: string, key = KEY) => fetch(`${base}${path}`, { headers: key ? headers(key) : {} }),
    post: (path: string, body: unknown, key = KEY) =>
      fetch(`${base}${path}`, { method: 'POST', headers: headers(key), body: typeof body === 'string' ? body : JSON.stringify(body) }),
    async push(device: string, items: unknown[], key = KEY): Promise<PushResult[]> {
      const res = await this.post('/api/sync/push', { device, items }, key)
      assert.equal(res.status, 200)
      return (await res.json() as { results: PushResult[] }).results
    },
    async pullAll(since = 0, kinds = '', key = KEY): Promise<Pulled> {
      const records: StoredRecord[] = []
      let cursor = since
      for (;;) {
        const page = await (await this.get(`/api/sync/pull?since=${cursor}${kinds ? `&kinds=${kinds}` : ''}`, key)).json() as Pulled
        records.push(...page.records)
        cursor = page.cursor
        if (!page.more) return { records, cursor, more: false }
      }
    },
    settle: () => server.settle(),
    stop: () => server.close(),
  }
}
