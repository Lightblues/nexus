import { readFileSync, readdirSync } from 'node:fs'
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http'
import { extname, join } from 'node:path'
import { isRules, openDays } from './days.ts'
import { EXPORT_KINDS, MAX_PUSH_BYTES, MAX_PUSH_ITEMS, SESSION_DAYS, authenticate, createSession, endSession, isKind, migrate, openStore, sessionAuth, syncEnvKeys, type Access, type Db } from './store.ts'
import { dayOf, isDay } from './summary.ts'

const MAX_DEVICE_LENGTH = 80
const MAX_RANGE_DAYS = 400
const COOKIE = 'nexus_session'
const WEB_DIR = new URL('../web/', import.meta.url).pathname
const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json', '.json': 'application/json',
}

export interface ServerOptions {
  /** The owner's bearer for every route: push, pull, status, and export. Other users' keys live in the keys table. */
  key: string
  /** The owner's bearer for reads only (export, days, devices, the web app). Empty leaves reads to the write key. */
  readKey?: string
  host: string
  port: number
  db: Db
  /** IANA zone whose midnights split days. */
  tz?: string
  /** How long stored day summaries wait after a push before catching up. */
  rebuildDelayMs?: number
}

export async function startServer(options: ServerOptions) {
  const tz = options.tz ?? 'Asia/Shanghai'
  await migrate(options.db)
  await syncEnvKeys(options.db, { write: options.key, read: options.readKey })
  const store = openStore(options.db)
  const days = openDays(options.db, store, tz, options.rebuildDelayMs)
  const web = loadWeb()

  const server = createServer((req, res) => {
    void onRequest(req, res).catch(error => {
      console.error('[nexus-server] request failed:', (error as Error).message)
      fail(res, 500, 'internal', 'internal error')
    })
  })

  await new Promise<void>((resolveListen, reject) => {
    const onError = (error: Error) => reject(error)
    server.once('error', onError)
    server.listen(options.port, options.host, () => {
      server.removeListener('error', onError)
      resolveListen()
    })
  })
  const address = server.address()
  const port = typeof address === 'object' && address ? address.port : options.port
  const startup = days.startup().catch(error => console.error('[nexus-server] summary startup failed:', (error as Error).message))

  async function onRequest(req: IncomingMessage, res: ServerResponse) {
    const url = new URL(req.url || '/', 'http://127.0.0.1')
    const route = `${req.method} ${url.pathname}`
    if (route === 'GET /health') return sendJson(res, 200, { ok: true })

    if (req.method === 'GET' && !url.pathname.startsWith('/api/') && !url.pathname.startsWith('/export/')) return serveWeb(req, res, url.pathname)
    if (route === 'POST /login') return login(req, res)
    if (route === 'POST /logout') {
      const token = cookie(req, COOKIE)
      if (token) await endSession(options.db, token)
      return redirect(res, '/', `${COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax`)
    }

    const key = bearer(req)
    // Browser sessions read only; every write goes through a key.
    const auth = key ? await authenticate(options.db, key) : await sessionAuth(options.db, cookie(req, COOKIE)).then(a => a && { ...a, access: 'read' as Access })
    if (!auth) return fail(res, 401, 'unauthorized', 'unauthorized')
    const { user, access } = auth
    const needWrite = () => fail(res, 403, 'forbidden', 'this route needs the write key')

    if (route === 'GET /export/kinds') {
      return sendJson(res, 200, { app: 'nexus', kinds: Object.entries(EXPORT_KINDS).map(([kind, description]) => ({ kind, description })) })
    }

    if (route === 'GET /export/changes') {
      const since = cursorParam(url)
      if (since === null) return fail(res, 400, 'invalid_params', 'since must be a cursor from a previous response')
      const limit = Math.min(Math.max(Number(url.searchParams.get('limit') || 100) || 100, 1), 500)
      return sendJson(res, 200, await store.exportChanges(user, since, kindsParam(url), limit))
    }

    if (route === 'GET /api/me') {
      const { rows } = await options.db.query<{ name: string }>('SELECT name FROM users WHERE id = $1', [user])
      return sendJson(res, 200, { user, name: rows[0]?.name ?? user, access, tz, today: dayOf(Date.now() / 1000, tz) })
    }

    if (route === 'GET /api/days') {
      const to = url.searchParams.get('to') || dayOf(Date.now() / 1000, tz)
      const from = url.searchParams.get('from') || shiftDay(to, -29)
      if (!isDay(from) || !isDay(to) || from > to) return fail(res, 400, 'invalid_params', 'from and to must be YYYY-MM-DD with from <= to')
      if (shiftDay(from, MAX_RANGE_DAYS) < to) return fail(res, 400, 'invalid_params', `at most ${MAX_RANGE_DAYS} days per request`)
      return sendJson(res, 200, { tz, from, to, days: await days.summaries(user, from, to) })
    }

    const dayMatch = /^\/api\/days\/(\d{4}-\d{2}-\d{2})(\/records)?$/.exec(url.pathname)
    if (req.method === 'GET' && dayMatch) {
      if (!isDay(dayMatch[1])) return fail(res, 400, 'invalid_params', 'day must be YYYY-MM-DD')
      const found = await days.day(user, dayMatch[1])
      if (!dayMatch[2]) return sendJson(res, 200, found.summary)
      return sendJson(res, 200, { day: dayMatch[1], tz, activities: found.activities, sessions: found.sessions })
    }

    if (route === 'GET /api/devices') return sendJson(res, 200, { devices: await days.devices(user) })
    if (route === 'GET /api/categories') return sendJson(res, 200, await days.categories(user))

    if (route === 'PUT /api/categories') {
      if (access !== 'write') return needWrite()
      const body = await readJson(req)
      if (typeof body === 'string' || !isRules(body.rules)) return fail(res, 400, 'invalid_params', 'body must be { rules: { domains?, bundleIds?, apps? } } mapping names to categories')
      const rebuilt = await days.setCategories(user, body.rules)
      return sendJson(res, 200, { ok: true, rebuilt })
    }

    if (route === 'POST /api/summaries/rebuild') {
      if (access !== 'write') return needWrite()
      return sendJson(res, 200, { rebuilt: await days.rebuildAllIfStale(user, true) })
    }

    if (route === 'GET /api/settings') {
      if (access !== 'write') return needWrite()
      return sendJson(res, 200, { settings: await days.settings(user) })
    }

    if (!url.pathname.startsWith('/api/sync/')) return fail(res, 404, 'not_found', url.pathname)
    if (access !== 'write') return fail(res, 403, 'forbidden', 'sync needs the write key')

    if (route === 'POST /api/sync/push') {
      const body = await readJson(req)
      if (body === 'too_large') return fail(res, 413, 'too_large', `request body over ${MAX_PUSH_BYTES} bytes`)
      if (body === 'invalid') return fail(res, 400, 'invalid_json', 'body must be a JSON object')
      const { device, items, deviceName } = body
      if (typeof device !== 'string' || !device || device.length > MAX_DEVICE_LENGTH) {
        return fail(res, 400, 'invalid_params', `device must be a string of 1 to ${MAX_DEVICE_LENGTH} characters`)
      }
      if (device === 'server') return fail(res, 400, 'invalid_params', 'device "server" is reserved')
      if (!Array.isArray(items)) return fail(res, 400, 'invalid_params', 'items must be an array')
      if (items.length > MAX_PUSH_ITEMS) return fail(res, 413, 'too_many_items', `at most ${MAX_PUSH_ITEMS} items per push`)
      const name = typeof deviceName === 'string' && deviceName.trim() ? deviceName.trim().slice(0, MAX_DEVICE_LENGTH) : undefined
      const results = await store.push(user, device, items, days.changed(user), name)
      const written = results.filter(r => r.rev !== undefined).length
      const stale = results.filter(r => r.stale).length
      console.log(`[nexus-server] push user=${user} device=${device} items=${items.length} written=${written} stale=${stale} errors=${items.length - written - stale}`)
      return sendJson(res, 200, { results })
    }

    if (route === 'GET /api/sync/pull') {
      const since = cursorParam(url)
      if (since === null) return fail(res, 400, 'invalid_params', 'since must be a cursor from a previous response')
      const kinds = kindsParam(url)
      const unknown = kinds.find(kind => !isKind(kind))
      if (unknown) return fail(res, 400, 'unknown_kind', unknown)
      return sendJson(res, 200, await store.pull(user, since, kinds.length ? kinds : undefined))
    }

    if (route === 'GET /api/sync/status') return sendJson(res, 200, await store.status(user))

    return fail(res, 404, 'not_found', url.pathname)
  }

  /** A key from the form becomes a session cookie; the key itself is never stored in the browser. */
  async function login(req: IncomingMessage, res: ServerResponse) {
    const raw = await readText(req)
    const key = raw === null ? '' : (new URLSearchParams(raw).get('key') || '').trim()
    const auth = key ? await authenticate(options.db, key) : null
    if (!auth) return redirect(res, '/login?error=1')
    const token = await createSession(options.db, auth.user, 'read')
    return redirect(res, '/app', `${COOKIE}=${token}; Path=/; Max-Age=${SESSION_DAYS * 86400}; HttpOnly; Secure; SameSite=Lax`)
  }

  function serveWeb(req: IncomingMessage, res: ServerResponse, path: string) {
    const name = path === '/' ? 'index.html'
      : path === '/login' ? 'login.html'
      : path === '/app' || path.startsWith('/app/') ? 'app.html'
      : path.slice(1)
    const file = web.get(name)
    if (!file) return fail(res, 404, 'not_found', path)
    const headers: Record<string, string> = {
      'content-type': TYPES[extname(name)] ?? 'application/octet-stream',
      'content-length': String(file.length),
      'cache-control': 'no-cache',
      'x-content-type-options': 'nosniff',
    }
    if (name.endsWith('.html')) headers['content-security-policy'] = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'"
    if (name === 'sw.js') headers['service-worker-allowed'] = '/'
    res.writeHead(200, headers)
    res.end(req.method === 'HEAD' ? undefined : file)
  }

  return {
    port,
    /** Resolves when startup summaries and queued rebuilds have finished. */
    async settle() {
      await startup
      await days.settle()
    },
    async close() {
      await new Promise<void>((resolveClose, reject) => {
        server.close(error => error ? reject(error) : resolveClose())
      })
      await startup
      await days.settle()
      await options.db.close()
    },
  }
}

/** The web app's files, read once; only these names are ever served. */
function loadWeb(): Map<string, Buffer> {
  const files = new Map<string, Buffer>()
  const walk = (dir: string, prefix: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) walk(join(dir, entry.name), `${prefix}${entry.name}/`)
      else files.set(`${prefix}${entry.name}`, readFileSync(join(dir, entry.name)))
    }
  }
  try { walk(WEB_DIR, '') } catch { /* no web directory: API only */ }
  return files
}

function shiftDay(day: string, by: number): string {
  const [y, m, d] = day.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + by)).toISOString().slice(0, 10)
}

function cursorParam(url: URL): number | null {
  const since = Number(url.searchParams.get('since') || 0)
  return Number.isSafeInteger(since) && since >= 0 ? since : null
}

function kindsParam(url: URL): string[] {
  return (url.searchParams.get('kinds') || '').split(',').map(kind => kind.trim()).filter(Boolean)
}

function bearer(req: IncomingMessage): string {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.authorization || '')
  return match?.[1] ?? ''
}

function cookie(req: IncomingMessage, name: string): string {
  for (const part of (req.headers.cookie || '').split(';')) {
    const [k, ...v] = part.trim().split('=')
    if (k === name) return v.join('=')
  }
  return ''
}

function redirect(res: ServerResponse, location: string, setCookie?: string) {
  res.writeHead(303, { location, ...(setCookie ? { 'set-cookie': setCookie } : {}) })
  res.end()
}

function sendJson(res: ServerResponse, status: number, body: unknown) {
  if (res.headersSent) return
  const payload = JSON.stringify(body)
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(payload), 'cache-control': 'no-store' })
  res.end(payload)
}

function fail(res: ServerResponse, status: number, code: string, message: string) {
  sendJson(res, status, { error: { code, message } })
}

async function readText(req: IncomingMessage): Promise<string | null> {
  const chunks: Buffer[] = []
  let size = 0
  for await (const chunk of req) {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)
    size += buf.length
    if (size <= MAX_PUSH_BYTES) chunks.push(buf)
  }
  return size > MAX_PUSH_BYTES ? null : Buffer.concat(chunks).toString('utf8')
}

/** The parsed object, or why it was refused. An oversized body is drained so the client still reads the 413. */
async function readJson(req: IncomingMessage): Promise<Record<string, unknown> | 'too_large' | 'invalid'> {
  const text = await readText(req)
  if (text === null) return 'too_large'
  try {
    const parsed = JSON.parse(text) as unknown
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : 'invalid'
  } catch {
    return 'invalid'
  }
}
