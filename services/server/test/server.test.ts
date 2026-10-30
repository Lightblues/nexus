import assert from 'node:assert/strict'
import { test } from 'node:test'
import { MAX_BODY_BYTES, MAX_PUSH_ITEMS, OWNER, addKey, addUser, listUsers, migrate, openStore } from '../src/store.ts'
import { KEY, READ, boot, pgliteDb, type Exported, type Pulled } from './helpers.ts'

const setting = (id: string, updatedAt: number, value: unknown) => ({ kind: 'setting', id, updatedAt, body: { value } })
const session = (id: string, updatedAt: number, tags: string[] = []) => ({
  kind: 'pomodoro_session', id, updatedAt,
  body: { kind: 'work', startTime: 1761530000, endTime: 1761531500, duration: 1500, project: 'nexus', task: 'sync', completedFully: true, tags },
})
const tracker = (uid: string, updatedAt: number, app = 'Code') => ({
  kind: 'tracker_record', id: uid, updatedAt, body: { startTime: 1761530000, endTime: 1761530060, duration: 60, app, bundleId: null, title: null },
})

test('each key opens only its own door', async () => {
  const server = await boot()
  try {
    assert.deepEqual(await (await server.get('/health', '')).json(), { ok: true })
    assert.equal((await server.get('/api/sync/pull', '')).status, 401)
    assert.equal((await server.get('/api/sync/pull', 'nope')).status, 401)
    assert.equal((await server.get('/export/kinds', '')).status, 401)
    assert.equal((await server.post('/api/sync/push', { device: 'mbp', items: [] }, READ)).status, 403)
    assert.equal((await server.get('/api/sync/pull', READ)).status, 403)
    assert.equal((await server.get('/api/sync/status', READ)).status, 403)
    assert.equal((await server.get('/export/changes', READ)).status, 200)
    assert.equal((await server.get('/export/changes', KEY)).status, 200)
    assert.equal((await server.get('/api/sync/pull')).status, 200)
    assert.equal((await server.get('/api/sync/nope')).status, 404)
    assert.equal((await server.get('/nope')).status, 404)
  } finally {
    await server.stop()
  }
})

test('two devices push and pull and converge', async () => {
  const server = await boot()
  try {
    const mbp = await server.push('mbp', [setting('pomodoro.workDuration', 100, 50), session('s1', 100, ['deep']), tracker('u1', 100)])
    assert.ok(mbp.every(r => r.rev && !r.stale && !r.error))
    const mini = await server.push('mini', [
      { kind: 'pomodoro_project', id: 'nexus', updatedAt: 110, body: { color: '#ff0000', createdAt: 1761530000 } },
      { kind: 'pomodoro_tag', id: 'deep', updatedAt: 110, body: { createdAt: 1761530000 } },
      tracker('u2', 110, 'Safari'),
    ])
    assert.ok(mini.every(r => r.rev))

    const onMbp = await server.pullAll()
    const onMini = await server.pullAll()
    assert.deepEqual(onMbp, onMini)
    assert.deepEqual(onMbp.records.map(r => `${r.kind}/${r.id}`), [
      'setting/pomodoro.workDuration', 'pomodoro_session/s1', 'tracker_record/u1', 'pomodoro_project/nexus', 'pomodoro_tag/deep', 'tracker_record/u2',
    ])
    assert.deepEqual(onMbp.records.map(r => r.device), ['mbp', 'mbp', 'mbp', 'mini', 'mini', 'mini'])
    assert.deepEqual((onMbp.records[1].body as { tags: string[] }).tags, ['deep'])

    const edit = await server.push('mini', [setting('pomodoro.workDuration', 200, 45)])
    const after = await server.pullAll(onMbp.cursor)
    assert.deepEqual(after.records.map(r => [r.id, r.rev, r.body]), [['pomodoro.workDuration', edit[0].rev, { value: 45 }]])
    assert.equal(after.cursor, edit[0].rev)

    const kinds = await server.pullAll(0, 'tracker_record,pomodoro_tag')
    assert.deepEqual(kinds.records.map(r => r.id), ['u1', 'deep', 'u2'])
    assert.equal((await server.get('/api/sync/pull?kinds=upload')).status, 400)
    assert.equal((await server.get('/api/sync/pull?since=-1')).status, 400)

    const empty = await (await server.get(`/api/sync/pull?since=${after.cursor}`)).json() as Pulled
    assert.deepEqual(empty, { records: [], cursor: after.cursor, more: false })

    const status = await (await server.get('/api/sync/status')).json() as { rev: number; kinds: Record<string, { records: number; deleted: number }> }
    assert.equal(status.rev, edit[0].rev)
    assert.deepEqual(status.kinds, {
      setting: { records: 1, deleted: 0 },
      pomodoro_session: { records: 1, deleted: 0 },
      pomodoro_project: { records: 1, deleted: 0 },
      pomodoro_tag: { records: 1, deleted: 0 },
      tracker_record: { records: 2, deleted: 0 },
    })
  } finally {
    await server.stop()
  }
})

test('last write wins by updatedAt; an older or tied write gets the stored record back', async () => {
  const server = await boot()
  try {
    const [first] = await server.push('mbp', [setting('uploader.github.token', 100, 'ghp_a')])
    const [older] = await server.push('mini', [setting('uploader.github.token', 50, 'ghp_b')])
    assert.equal(older.rev, undefined)
    assert.deepEqual(older.stale, { kind: 'setting', id: 'uploader.github.token', rev: first.rev, updatedAt: 100, deleted: false, device: 'mbp', body: { value: 'ghp_a' } })
    const [tied] = await server.push('mini', [setting('uploader.github.token', 100, 'ghp_c')])
    assert.deepEqual(tied.stale?.body, { value: 'ghp_a' })
    const [newer] = await server.push('mini', [setting('uploader.github.token', 101, 'ghp_d')])
    assert.ok(newer.rev! > first.rev!)
    assert.equal(newer.stale, undefined)
    const { records } = await server.pullAll()
    assert.deepEqual(records.map(r => [r.body, r.device]), [[{ value: 'ghp_d' }, 'mini']])
  } finally {
    await server.stop()
  }
})

test('a delete is a tombstone that syncs, exports, and loses to a newer write only', async () => {
  const server = await boot()
  try {
    await server.push('mbp', [session('s1', 100), { kind: 'pomodoro_tag', id: 'gone', updatedAt: 100, deleted: true }])
    const [del] = await server.push('mini', [{ kind: 'pomodoro_session', id: 's1', updatedAt: 200, deleted: true, body: { ignored: true } }])
    assert.ok(del.rev)
    const { records } = await server.pullAll()
    assert.deepEqual(records.map(r => [r.id, r.deleted, r.body]), [['gone', true, null], ['s1', true, null]])

    const [late] = await server.push('mbp', [session('s1', 150)])
    assert.equal(late.stale?.deleted, true)
    const exported = await (await server.get('/export/changes', READ)).json() as Exported
    assert.deepEqual(exported.items.map(i => [i.id, i.deleted, i.data]), [['gone', true, null], ['s1', true, null]])

    const [back] = await server.push('mbp', [session('s1', 300)])
    assert.ok(back.rev! > del.rev!)
    const status = await (await server.get('/api/sync/status')).json() as { kinds: Record<string, { records: number; deleted: number }> }
    assert.deepEqual(status.kinds.pomodoro_session, { records: 1, deleted: 0 })
    assert.deepEqual(status.kinds.pomodoro_tag, { records: 0, deleted: 1 })
  } finally {
    await server.stop()
  }
})

test('a pull page stops at 256 KB but always carries one record', async () => {
  const server = await boot()
  try {
    const big = 'x'.repeat(60_000)
    await server.push('mbp', ['a', 'b', 'c', 'd', 'e', 'f'].map(id => ({ kind: 'tracker_record', id, updatedAt: 1, body: { title: big } })))
    const first = await (await server.get('/api/sync/pull')).json() as Pulled
    assert.deepEqual(first.records.map(r => r.id), ['a', 'b', 'c', 'd'])
    assert.equal(first.more, true)
    const second = await (await server.get(`/api/sync/pull?since=${first.cursor}`)).json() as Pulled
    assert.deepEqual(second.records.map(r => r.id), ['e', 'f'])
    assert.equal(second.more, false)
  } finally {
    await server.stop()
  }

  const db = pgliteDb()
  await migrate(db)
  const store = openStore(db)
  await store.push(OWNER, 'mbp', ['a', 'b'].map(id => ({ kind: 'pomodoro_tag', id, updatedAt: 1, body: { createdAt: 1 } })))
  const tiny = await store.pull(OWNER, 0, undefined, 10)
  assert.deepEqual(tiny.records.map(r => r.id), ['a'])
  assert.equal(tiny.more, true)
  await db.close()
})

test('limits and bad items are refused per item or per request', async () => {
  const server = await boot()
  try {
    const results = await server.push('mbp', [
      tracker('ok', 1),
      { kind: 'upload', id: 'x', updatedAt: 1, body: {} },
      { kind: 'tracker_record', id: '', updatedAt: 1, body: {} },
      { kind: 'tracker_record', id: 'y'.repeat(201), updatedAt: 1, body: {} },
      { kind: 'tracker_record', id: 't', updatedAt: 1.5, body: {} },
      { kind: 'tracker_record', id: 't', body: {} },
      { kind: 'tracker_record', id: 't', updatedAt: 1, body: 'text' },
      { kind: 'setting', id: 'ui.windowWidth', updatedAt: 1, body: { width: 320 } },
      { kind: 'tracker_record', id: 'big', updatedAt: 1, body: { title: 'x'.repeat(MAX_BODY_BYTES) } },
      'nonsense',
    ])
    assert.deepEqual(results.map(r => r.error), [
      undefined, 'unknown_kind', 'invalid_id', 'invalid_id', 'invalid_updated_at', 'invalid_updated_at', 'invalid_body', 'invalid_body', 'too_large', 'invalid',
    ])
    assert.ok(results[0].rev)
    assert.deepEqual(results[1], { kind: 'upload', id: 'x', error: 'unknown_kind' })

    const many = Array.from({ length: MAX_PUSH_ITEMS + 1 }, (_, i) => ({ kind: 'pomodoro_tag', id: `t${i}`, updatedAt: 1, body: {} }))
    const tooMany = await server.post('/api/sync/push', { device: 'mbp', items: many })
    assert.equal(tooMany.status, 413)
    assert.equal((await tooMany.json() as { error: { code: string } }).error.code, 'too_many_items')
    const atCap = await server.push('mbp', many.slice(0, MAX_PUSH_ITEMS))
    assert.equal(atCap.filter(r => r.rev).length, MAX_PUSH_ITEMS)

    const huge = Array.from({ length: 20 }, (_, i) => tracker(`h${i}`, 1, 'x'.repeat(60_000)))
    const tooBig = await server.post('/api/sync/push', { device: 'mbp', items: huge })
    assert.equal(tooBig.status, 413)
    assert.equal((await tooBig.json() as { error: { code: string } }).error.code, 'too_large')

    assert.equal((await server.post('/api/sync/push', { items: [] })).status, 400)
    assert.equal((await server.post('/api/sync/push', { device: 'mbp' })).status, 400)
    assert.equal((await server.post('/api/sync/push', '{nope')).status, 400)
    assert.equal((await server.post('/api/sync/push', '[]')).status, 400)
  } finally {
    await server.stop()
  }
})

test('export pages every exported kind in rev order and never serves settings', async () => {
  const server = await boot()
  try {
    await server.push('mbp', [
      session('s1', 1, ['deep']),
      setting('uploader.github.token', 1, 'ghp_secret'),
      { kind: 'pomodoro_project', id: 'nexus', updatedAt: 1, body: { color: '#00f', createdAt: 1 } },
      { kind: 'pomodoro_tag', id: 'deep', updatedAt: 1, body: { createdAt: 1 } },
      tracker('u1', 1),
    ])
    await server.push('mini', [session('s1', 2, ['deep', 'flow'])])

    const kinds = await (await server.get('/export/kinds', READ)).json() as { app: string; kinds: { kind: string; description: string }[] }
    assert.equal(kinds.app, 'nexus')
    assert.deepEqual(kinds.kinds.map(k => k.kind), ['pomodoro_session', 'pomodoro_project', 'pomodoro_tag', 'tracker_record', 'day_summary'])

    const seen: Exported['items'] = []
    let cursor = ''
    let pages = 0
    for (;;) {
      const page = await (await server.get(`/export/changes?limit=2${cursor ? `&since=${cursor}` : ''}`, READ)).json() as Exported
      assert.equal(typeof page.cursor, 'string')
      seen.push(...page.items)
      cursor = page.cursor
      pages += 1
      if (!page.more) break
    }
    assert.equal(pages, 2)
    assert.deepEqual(seen.map(i => `${i.kind}/${i.id}`), ['pomodoro_project/nexus', 'pomodoro_tag/deep', 'tracker_record/u1', 'pomodoro_session/s1'])
    assert.deepEqual((seen[3].data as { tags: string[] }).tags, ['deep', 'flow'])
    assert.equal(JSON.stringify(seen).includes('ghp_secret'), false)

    const filtered = await (await server.get('/export/changes?kinds=tracker_record,setting,bogus', READ)).json() as Exported
    assert.deepEqual(filtered.items.map(i => i.id), ['u1'])
    const empty = await (await server.get(`/export/changes?since=${cursor}`, READ)).json() as Exported
    assert.deepEqual(empty, { items: [], cursor, more: false })
    assert.equal((await server.get('/export/changes?since=x', READ)).status, 400)
  } finally {
    await server.stop()
  }
})

test('each user syncs and exports only its own records', async () => {
  const db = pgliteDb()
  const server = await boot(db)
  try {
    const other = await addUser(db, 'guest')
    const otherKey = await addKey(db, other.id, 'write', 'guest mac')
    const otherRead = await addKey(db, other.id, 'read')

    await server.push('mbp', [setting('pomodoro.workDuration', 1, 25), tracker('same-uid', 1, 'Code')])
    const pushed = await server.push('guest-mac', [setting('pomodoro.workDuration', 1, 50), tracker('same-uid', 1, 'Xcode')], otherKey)
    assert.ok(pushed.every(r => r.rev && !r.stale), 'the same kind and id is a separate record per user')

    const mine = await server.pullAll()
    const theirs = await server.pullAll(0, '', otherKey)
    assert.deepEqual(mine.records.map(r => (r.body as { value?: unknown; app?: string }).value ?? (r.body as { app: string }).app), [25, 'Code'])
    assert.deepEqual(theirs.records.map(r => (r.body as { value?: unknown; app?: string }).value ?? (r.body as { app: string }).app), [50, 'Xcode'])

    const status = await (await server.get('/api/sync/status', otherKey)).json() as { rev: number; kinds: Record<string, { records: number }> }
    assert.equal(status.kinds.tracker_record.records, 1)
    assert.equal(status.rev, theirs.cursor)

    const exported = await (await server.get('/export/changes', otherRead)).json() as Exported
    assert.deepEqual(exported.items.map(i => (i.data as { app: string }).app), ['Xcode'])
    assert.equal((await server.get('/api/sync/pull', otherRead)).status, 403)

    const users = await listUsers(db)
    assert.deepEqual(users.map(u => [u.id, u.keys, u.records]), [[OWNER, 2, 2], [other.id, 2, 2]])
  } finally {
    await server.stop()
  }
})

test('a database from before users is migrated to the owner, and env keys follow the environment', async () => {
  const db = pgliteDb()
  await db.query(`
    CREATE SEQUENCE record_rev;
    CREATE TABLE records (kind text NOT NULL, id text NOT NULL, rev bigint NOT NULL, updated_at bigint NOT NULL, device text NOT NULL,
      deleted boolean NOT NULL DEFAULT false, body jsonb, PRIMARY KEY (kind, id));
    CREATE INDEX records_rev ON records (rev);
    INSERT INTO records VALUES ('setting', 'ui.theme', nextval('record_rev'), 1, 'mbp', false, '{"value": "dark"}');
  `)
  const first = await boot(db)
  const before = await first.pullAll()
  assert.deepEqual(before.records.map(r => [r.kind, r.id, r.rev]), [['setting', 'ui.theme', 1]])
  const [written] = await first.push('mbp', [setting('ui.theme', 2, 'light')])
  assert.equal(written.rev, 2, 'the rev sequence carries on')
  await first.stop()

  const db2 = pgliteDb()
  const a = await boot({ ...db2, close: async () => {} })
  await a.push('mbp', [setting('x', 1, 1)])
  await a.stop()
  const reopened = await boot(db2, 'rotated-key', '')
  try {
    assert.equal((await reopened.get('/api/sync/status')).status, 401, 'the old NEXUS_KEY stops working')
    assert.equal((await reopened.get('/export/changes', READ)).status, 401, 'an unset NEXUS_READ_KEY is dropped')
    assert.equal((await reopened.pullAll(0, '', 'rotated-key')).records.length, 1)
  } finally {
    await reopened.stop()
  }
})
