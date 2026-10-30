import assert from 'node:assert/strict'
import { test } from 'node:test'
import { KEY, READ, boot, type Exported, type Pulled } from './helpers.ts'

const MIDNIGHT = Date.UTC(2026, 9, 29, 16) / 1000
const tracker = (id: string, start: number, seconds: number, extra: Record<string, unknown> = {}) => ({
  kind: 'tracker_record', id, updatedAt: 1,
  body: { startTime: start, endTime: start + seconds, duration: seconds, app: 'Code', bundleId: 'com.microsoft.VSCode', title: 'a.ts — nexus', ...extra },
})
const work = (id: string, start: number) => ({
  kind: 'pomodoro_session', id, updatedAt: 1,
  body: { kind: 'work', startTime: start, endTime: start + 1500, duration: 1500, project: 'nexus', task: 'days', completedFully: true, tags: [] },
})

type Summary = { day: string; activeSeconds: number; categories: { category: string; seconds: number }[]; pomodoro: { work: number }; devices: string[] }

test('pushes rebuild the touched days; summaries export but never sync', async () => {
  const server = await boot()
  try {
    await server.push('mbp', [tracker('t1', MIDNIGHT + 60, 1200), work('p1', MIDNIGHT + 60), tracker('lock', MIDNIGHT + 2000, 600, { app: 'loginwindow', bundleId: 'com.apple.loginwindow' })])
    await server.settle()

    const day = await (await server.get('/api/days/2026-10-30', READ)).json() as Summary
    assert.deepEqual([day.activeSeconds, day.pomodoro.work, day.devices], [1200, 1, ['mbp']])
    const list = await (await server.get('/api/days?from=2026-10-01&to=2026-10-31', READ)).json() as { days: Summary[] }
    assert.deepEqual(list.days.map(d => [d.day, d.activeSeconds]), [['2026-10-30', 1200]])

    const records = await (await server.get('/api/days/2026-10-30/records', READ)).json() as { activities: { id: string; project: string }[]; sessions: unknown[] }
    assert.deepEqual(records.activities.map(a => [a.id, a.project]), [['t1', 'nexus']])
    assert.equal(records.sessions.length, 1)

    const exported = await (await server.get('/export/changes?kinds=day_summary', READ)).json() as Exported
    assert.deepEqual(exported.items.map(i => i.id), ['2026-10-30'])
    const pulled = await server.pullAll() as Pulled
    assert.ok(pulled.records.every(r => r.kind !== 'day_summary'), 'Macs never pull summaries')
    assert.equal((await server.get('/api/sync/pull?kinds=day_summary')).status, 400)
    const forged = await server.push('mbp', [{ kind: 'day_summary', id: '2026-10-30', updatedAt: 9e12, body: {} }])
    assert.equal(forged[0].error, 'unknown_kind')
    assert.equal((await server.post('/api/sync/push', { device: 'server', items: [] })).status, 400)

    // Deleting the row empties the day: its stored summary is rewritten, not left stale.
    await server.push('mbp', [{ kind: 'tracker_record', id: 't1', updatedAt: 2, deleted: true }, { kind: 'pomodoro_session', id: 'p1', updatedAt: 2, deleted: true }])
    await server.settle()
    const emptied = await (await server.get('/api/days?from=2026-10-30&to=2026-10-30', READ)).json() as { days: Summary[] }
    assert.deepEqual(emptied.days.map(d => [d.activeSeconds, d.pomodoro.work]), [[0, 0]])

    assert.equal((await server.get('/api/days/2026-02-30', READ)).status, 400)
    assert.equal((await server.get('/api/days?from=2026-10-31&to=2026-10-01', READ)).status, 400)
    await server.post('/api/sync/push', { device: 'mbp', deviceName: 'Eason MacBook Pro', items: [] })
    await server.post('/api/sync/push', { device: 'mbp', items: [] })
    const devices = await (await server.get('/api/devices', READ)).json() as { devices: { device: string; name: string; trackerRecords: number }[] }
    assert.deepEqual(devices.devices.map(d => [d.device, d.name, d.trackerRecords]), [['mbp', 'Eason MacBook Pro', 1]], 'a push without a name keeps the last one')
  } finally {
    await server.stop()
  }
})

test('category rules are the write key\'s to change and rebuild every summary', async () => {
  const server = await boot()
  try {
    await server.push('mbp', [tracker('t1', MIDNIGHT + 60, 1200)])
    await server.settle()
    const put = (rules: unknown, key = KEY) => fetch(`${server.base}/api/categories`, {
      method: 'PUT', headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' }, body: JSON.stringify({ rules }),
    })
    assert.equal((await put({ apps: { Code: 'notes' } }, READ)).status, 403)
    assert.equal((await put({ apps: { Code: 3 } })).status, 400)
    assert.equal((await put({ bundleIds: { 'com.microsoft.VSCode': 'notes' } })).status, 200)
    const list = await (await server.get('/api/days?from=2026-10-30&to=2026-10-30', READ)).json() as { days: Summary[] }
    assert.deepEqual(list.days[0].categories, [{ category: 'notes', seconds: 1200 }])
    const got = await (await server.get('/api/categories', READ)).json() as { rules: unknown }
    assert.deepEqual(got.rules, { bundleIds: { 'com.microsoft.VSCode': 'notes' } })
  } finally {
    await server.stop()
  }
})

test('settings read back with secrets masked, and only with the write key', async () => {
  const server = await boot()
  try {
    await server.push('mbp', [
      { kind: 'setting', id: 'uploader.github.token', updatedAt: 1, body: { value: 'ghp_secret' } },
      { kind: 'setting', id: 'hotkey.palette', updatedAt: 1, body: { value: 'cmd+shift+space' } },
    ])
    assert.equal((await server.get('/api/settings', READ)).status, 403)
    const { settings } = await (await server.get('/api/settings')).json() as { settings: Record<string, unknown> }
    assert.deepEqual(settings, { 'hotkey.palette': 'cmd+shift+space', 'uploader.github.token': '<set, 10 chars>' })
  } finally {
    await server.stop()
  }
})

test('the web app is served without a key; only its own files', async () => {
  const server = await boot()
  try {
    const page = async (path: string) => { const res = await fetch(`${server.base}${path}`); return [res.status, res.headers.get('content-type'), await res.text()] as const }
    const [status, type, html] = await page('/')
    assert.deepEqual([status, type], [200, 'text/html; charset=utf-8'])
    assert.match(html, /brew install --cask lightblues\/tap\/nexus/)
    assert.match((await page('/app/day/2026-10-30/records'))[2], /<script type="module" src="\/app.js">/)
    assert.match((await page('/login'))[2], /name="key"/)
    assert.equal((await page('/sw.js'))[1], 'text/javascript; charset=utf-8')
    assert.equal((await page('/manifest.webmanifest'))[1], 'application/manifest+json')
    assert.equal((await page('/../package.json'))[0], 404)
    assert.equal((await page('/nope.html'))[0], 404)
    assert.equal((await page('/api/me'))[0], 401)
  } finally {
    await server.stop()
  }
})

test('a key logs the browser in to a read-only session', async () => {
  const server = await boot()
  try {
    const login = (key: string) => fetch(`${server.base}/login`, { method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `key=${encodeURIComponent(key)}` })
    const bad = await login('nope')
    assert.deepEqual([bad.status, bad.headers.get('location'), bad.headers.get('set-cookie')], [303, '/login?error=1', null])

    const ok = await login(KEY)
    assert.equal(ok.headers.get('location'), '/app')
    const cookie = ok.headers.get('set-cookie')!.split(';')[0]
    assert.ok(!cookie.includes(KEY))
    const asBrowser = (path: string, init: RequestInit = {}) => fetch(`${server.base}${path}`, { ...init, headers: { cookie, ...(init.headers ?? {}) } })
    const me = await (await asBrowser('/api/me')).json() as { user: string; access: string }
    assert.deepEqual([me.user, me.access], ['owner', 'read'])
    assert.equal((await asBrowser('/api/settings')).status, 403, 'a session from the write key still only reads')
    assert.equal((await asBrowser('/api/sync/status')).status, 403)

    await asBrowser('/logout', { method: 'POST', redirect: 'manual' })
    assert.equal((await asBrowser('/api/me')).status, 401)
  } finally {
    await server.stop()
  }
})
