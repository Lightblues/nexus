import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, statSync, symlinkSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { KEY, READ, boot } from '../../services/server/test/helpers.ts'
import { resolveDay, run, type Io } from '../src/cli.ts'

const MIDNIGHT = Date.UTC(2026, 9, 29, 16) / 1000

function io(env: NodeJS.ProcessEnv, stdin = '') {
  const out: string[] = [], err: string[] = []
  const value: Io = { env, fetch, out: t => out.push(t), err: t => err.push(t), readStdin: async () => stdin }
  return { io: value, out, err }
}

test('days resolve against the server\'s today', () => {
  assert.equal(resolveDay(undefined, '2026-03-01'), '2026-03-01')
  assert.equal(resolveDay('yesterday', '2026-03-01'), '2026-02-28')
  assert.equal(resolveDay('-7', '2026-03-01'), '2026-02-22')
  assert.equal(resolveDay('2026-01-02', '2026-03-01'), '2026-01-02')
  assert.throws(() => resolveDay('last week', '2026-03-01'))
})

test('the CLI reads days, rows and devices, and writes settings with the write key', async () => {
  const server = await boot()
  const dir = mkdtempSync(join(tmpdir(), 'nexus-cli-'))
  const env = (key: string) => ({ NEXUS_URL: server.base, NEXUS_KEY: key, NEXUS_CONFIG: join(dir, 'none.json') })
  const cli = async (args: string[], key = KEY, stdin = '') => {
    const t = io(env(key), stdin)
    const code = await run(args, t.io)
    return { code, out: t.out.join('\n'), err: t.err.join('\n') }
  }
  try {
    await server.push('mbp', [
      { kind: 'tracker_record', id: 't1', updatedAt: 1, body: { startTime: MIDNIGHT + 3600, endTime: MIDNIGHT + 5400, duration: 1800, app: 'Code', bundleId: 'com.microsoft.VSCode', title: 'cli.ts — nexus' } },
      { kind: 'pomodoro_session', id: 'p1', updatedAt: 1, body: { kind: 'work', startTime: MIDNIGHT + 3600, endTime: MIDNIGHT + 5100, duration: 1500, project: 'nexus', task: 'cli', completedFully: true, tags: [] } },
      { kind: 'setting', id: 'pomodoro.workDuration', updatedAt: 1, body: { value: 25 } },
      { kind: 'setting', id: 'uploader.github.token', updatedAt: 1, body: { value: 'ghp_x' } },
    ])
    await server.settle()

    const day = await cli(['day', '2026-10-30'], READ)
    assert.equal(day.code, 0)
    assert.match(day.out, /^2026-10-30 Fri · 30m active · 1 pomodoros \(25m\) · 01:00–01:30 · 1 Mac/)
    assert.match(day.out, /Projects {4}nexus 30m/)
    assert.match(day.out, /01:00–01:25 {2}work +nexus \/ cli/)
    const json = JSON.parse((await cli(['day', '2026-10-30', '--json'], READ)).out)
    assert.equal(json.activeSeconds, 1800)

    assert.match((await cli(['days', '--from', '2026-10-29', '--to', '2026-10-30'], READ)).out, /2026-10-30 Fri +30m +1 pomo +coding 30m\n1 days · 30m active · 1 pomodoros/)
    assert.match((await cli(['records', '2026-10-30', '--app', 'code'], READ)).out, /01:00 +30m {2}coding +Code · nexus · cli.ts/)
    assert.equal((await cli(['records', '2026-10-30', '--category', 'ai'], READ)).out, 'No activity rows.')
    assert.match((await cli(['devices'], READ)).out, /\(unnamed\) +mbp/)

    const denied = await cli(['config', 'get'], READ)
    assert.deepEqual([denied.code, /needs the write key/.test(denied.err)], [1, true])
    const got = await cli(['config', 'get', 'uploader'])
    assert.equal(got.out, 'uploader.github.token = "<set, 5 chars>"')
    assert.equal((await cli(['config', 'set', 'pomodoro.workDuration', 'fifty'])).code, 2, 'a string for a number is refused')
    assert.equal((await cli(['config', 'set', 'pomodoro.nope', '5'])).code, 2, 'an unknown key is refused')
    const set = await cli(['config', 'set', 'pomodoro.workDuration', '50'])
    assert.match(set.out, /pomodoro.workDuration = 50 \(rev \d+\)/)
    const pulled = await server.pullAll()
    const record = pulled.records.find(r => r.id === 'pomodoro.workDuration')!
    assert.deepEqual([record.device, record.body], ['cli', { value: 50 }], 'the Macs pull the CLI\'s edit like any other')

    const doctor = await cli(['doctor'], READ)
    assert.match(doctor.out, /ok {4}auth +owner \(owner\), read key, days in Asia\/Shanghai/)
    assert.equal((await cli(['today'], 'wrong')).code, 1)
    assert.equal((await cli(['bogus'])).code, 2)

    const login = io({ NEXUS_CONFIG: join(dir, 'config.json') }, `${READ}\n`)
    assert.equal(await run(['login', '--server', server.base], login.io), 0)
    assert.deepEqual(JSON.parse(readFileSync(join(dir, 'config.json'), 'utf8')), { server: server.base, key: READ })
    assert.equal(statSync(join(dir, 'config.json')).mode & 0o777, 0o600)
    const fromFile = io({ NEXUS_CONFIG: join(dir, 'config.json') })
    assert.equal(await run(['day', '2026-10-30', '--json'], fromFile.io), 0)
  } finally {
    await server.stop()
  }
})

test('the bundled bin runs through a symlink, as npm installs it', () => {
  const cwd = new URL('..', import.meta.url).pathname
  execFileSync('node', ['scripts/bundle.mjs'], { cwd })
  const dir = mkdtempSync(join(tmpdir(), 'nexus-bin-'))
  symlinkSync(join(cwd, 'dist/nexus.js'), join(dir, 'nexus'))
  const version = JSON.parse(readFileSync(join(cwd, 'package.json'), 'utf8')).version
  assert.equal(execFileSync(join(dir, 'nexus'), ['--version'], { encoding: 'utf8' }).trim(), version)
})
