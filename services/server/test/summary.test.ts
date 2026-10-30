import assert from 'node:assert/strict'
import { test } from 'node:test'
import { MAX_ROW_SECONDS, activity, categorize, dayBounds, dayOf, daysTouched, parseEditorTitle, summarizeDay, type TrackerBody } from '../src/summary.ts'

const TZ = 'Asia/Shanghai'
/** 2026-10-30 00:00 in Shanghai. */
const MIDNIGHT = Date.UTC(2026, 9, 29, 16) / 1000
const row = (start: number, seconds: number, extra: Partial<TrackerBody> = {}): TrackerBody =>
  ({ startTime: start, endTime: start + seconds, duration: seconds, app: 'Code', bundleId: 'com.microsoft.VSCode', title: null, ...extra })

test('days follow the configured zone, including across DST', () => {
  assert.equal(dayOf(MIDNIGHT, TZ), '2026-10-30')
  assert.equal(dayOf(MIDNIGHT - 1, TZ), '2026-10-29')
  assert.deepEqual(dayBounds('2026-10-30', TZ), [MIDNIGHT, MIDNIGHT + 86400])
  const [from, to] = dayBounds('2026-11-01', 'America/New_York')
  assert.equal(to - from, 25 * 3600, 'the day clocks fall back has 25 hours')
  assert.equal(dayOf(from, 'America/New_York'), '2026-11-01')
  assert.deepEqual(daysTouched({ startTime: MIDNIGHT - 60, endTime: MIDNIGHT + 60 }, TZ), ['2026-10-29', '2026-10-30'])
  assert.deepEqual(daysTouched({}, TZ), [])
})

test('cleaning drops the lock screen, caps old rows, names Electron apps, and reparses editor projects', () => {
  assert.equal(activity('a', 'mbp', row(MIDNIGHT, 600, { app: 'loginwindow', bundleId: 'com.apple.loginwindow' })), null)
  assert.equal(activity('a', 'mbp', row(MIDNIGHT, 0)), null)
  assert.equal(activity('a', 'mbp', row(MIDNIGHT, 5 * 3600))!.seconds, MAX_ROW_SECONDS)
  assert.equal(activity('a', 'mbp', row(MIDNIGHT, 60, { app: 'Electron', bundleId: 'com.google.antigravity' }))!.app, 'Antigravity')

  const code = activity('a', 'mbp', row(MIDNIGHT, 60, { title: '● main.ts — nexus (Workspace) — Lightweight', contextProject: 'Lightweight' }))!
  assert.deepEqual([code.project, code.file, code.category], ['nexus', 'main.ts', 'coding'])
  assert.deepEqual(parseEditorTitle('Welcome'), { file: 'Welcome', project: null })
})

test('categories: domain beats app, user rules beat defaults, unknown is other', () => {
  const chrome = { app: 'Google Chrome', bundleId: 'com.google.Chrome' }
  assert.equal(categorize({ ...chrome, domain: 'bilibili.com' }), 'entertainment')
  assert.equal(categorize({ ...chrome, domain: 'm.bilibili.com' }), 'entertainment', 'subdomains match')
  assert.equal(categorize({ ...chrome, domain: 'example.org' }), 'browsing')
  assert.equal(categorize({ ...chrome, domain: 'example.org' }, { domains: { 'example.org': 'reading' } }), 'reading')
  assert.equal(categorize({ app: 'Code', bundleId: 'com.microsoft.VSCode', domain: null }, { apps: { code: 'notes' } }), 'notes', 'app names match case-insensitively')
  assert.equal(categorize({ app: 'Mystery', bundleId: null, domain: null }), 'other')
})

test('a day summary clips to the day, counts overlapping Macs once, and builds blocks and pomodoro totals', () => {
  const acts = [
    activity('y', 'mbp', row(MIDNIGHT - 600, 1200, { title: 'a.ts — nexus' }))!,
    activity('a', 'mbp', row(MIDNIGHT + 600, 900, { title: 'a.ts — nexus' }))!,
    activity('b', 'mini', row(MIDNIGHT + 1200, 600, { title: 'b.ts — nexus' }))!,
    activity('c', 'mbp', row(MIDNIGHT + 1500, 1800, { app: 'Google Chrome', bundleId: 'com.google.Chrome', contextDomain: 'www.bilibili.com' }))!,
  ]
  const sessions = [
    { kind: 'work', startTime: MIDNIGHT + 600, endTime: MIDNIGHT + 2100, duration: 1500, project: 'nexus', task: 'summary', completedFully: true },
    { kind: 'shortBreak', startTime: MIDNIGHT + 2100, endTime: MIDNIGHT + 2400, duration: 300, project: 'nexus', task: null, completedFully: true },
    { kind: 'work', startTime: MIDNIGHT - 3000, endTime: MIDNIGHT - 1500, duration: 1500, project: 'yesterday', completedFully: true },
  ]
  const s = summarizeDay('2026-10-30', TZ, acts, sessions)
  // 600 s of the row from before midnight; 600..1500 Code; 1500..1800 the rest of mini's row; 1800..3300 Chrome (overlap with mini dropped).
  assert.equal(s.activeSeconds, 600 + 900 + 300 + 1500)
  assert.deepEqual(s.categories, [{ category: 'coding', seconds: 1800 }, { category: 'entertainment', seconds: 1500 }])
  assert.deepEqual(s.domains, [{ domain: 'bilibili.com', category: 'entertainment', seconds: 1500 }])
  assert.deepEqual(s.projects, [{ project: 'nexus', seconds: 1800 }])
  assert.equal(s.first, MIDNIGHT)
  assert.deepEqual(s.blocks.map(b => [b.category, b.label, b.seconds]), [['coding', 'nexus', 1800], ['entertainment', 'bilibili.com', 1500]])
  assert.deepEqual([s.pomodoro.work, s.pomodoro.workSeconds, s.pomodoro.completed], [1, 1500, 1])
  assert.deepEqual(s.pomodoro.projects, [{ project: 'nexus', seconds: 1500, sessions: 1 }])
  assert.equal(s.pomodoro.sessions.length, 2)
  assert.deepEqual(s.devices, ['mbp', 'mini'])
})
