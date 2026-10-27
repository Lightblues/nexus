import { createHash, timingSafeEqual } from 'node:crypto'
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http'
import { EXPORT_KINDS, MAX_PUSH_BYTES, MAX_PUSH_ITEMS, isKind, migrate, openStore, type Db } from './store.ts'

const MAX_DEVICE_LENGTH = 80

export interface ServerOptions {
  /** Bearer for every route: push, pull, status, and export. */
  key: string
  /** Bearer for /export only. Empty leaves export to the write key. */
  readKey?: string
  host: string
  port: number
  db: Db
}

type Access = 'write' | 'read'

export async function startServer(options: ServerOptions) {
  await migrate(options.db)
  const store = openStore(options.db)

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

  function access(req: IncomingMessage): Access | null {
    const got = bearer(req)
    if (tokenOk(got, options.key)) return 'write'
    if (options.readKey && tokenOk(got, options.readKey)) return 'read'
    return null
  }

  async function onRequest(req: IncomingMessage, res: ServerResponse) {
    const url = new URL(req.url || '/', 'http://127.0.0.1')
    const route = `${req.method} ${url.pathname}`
    if (route === 'GET /health') return sendJson(res, 200, { ok: true })

    const level = access(req)
    if (!level) return fail(res, 401, 'unauthorized', 'unauthorized')

    if (route === 'GET /export/kinds') {
      return sendJson(res, 200, { app: 'nexus', kinds: Object.entries(EXPORT_KINDS).map(([kind, description]) => ({ kind, description })) })
    }

    if (route === 'GET /export/changes') {
      const since = cursorParam(url)
      if (since === null) return fail(res, 400, 'invalid_params', 'since must be a cursor from a previous response')
      const limit = Math.min(Math.max(Number(url.searchParams.get('limit') || 100) || 100, 1), 500)
      return sendJson(res, 200, await store.exportChanges(since, kindsParam(url), limit))
    }

    if (!url.pathname.startsWith('/api/sync/')) return fail(res, 404, 'not_found', url.pathname)
    if (level !== 'write') return fail(res, 403, 'forbidden', 'sync needs the write key')

    if (route === 'POST /api/sync/push') {
      const body = await readJson(req)
      if (body === 'too_large') return fail(res, 413, 'too_large', `request body over ${MAX_PUSH_BYTES} bytes`)
      if (body === 'invalid') return fail(res, 400, 'invalid_json', 'body must be a JSON object')
      const { device, items } = body
      if (typeof device !== 'string' || !device || device.length > MAX_DEVICE_LENGTH) {
        return fail(res, 400, 'invalid_params', `device must be a string of 1 to ${MAX_DEVICE_LENGTH} characters`)
      }
      if (!Array.isArray(items)) return fail(res, 400, 'invalid_params', 'items must be an array')
      if (items.length > MAX_PUSH_ITEMS) return fail(res, 413, 'too_many_items', `at most ${MAX_PUSH_ITEMS} items per push`)
      const results = await store.push(device, items)
      const written = results.filter(r => r.rev !== undefined).length
      const stale = results.filter(r => r.stale).length
      console.log(`[nexus-server] push device=${device} items=${items.length} written=${written} stale=${stale} errors=${items.length - written - stale}`)
      return sendJson(res, 200, { results })
    }

    if (route === 'GET /api/sync/pull') {
      const since = cursorParam(url)
      if (since === null) return fail(res, 400, 'invalid_params', 'since must be a cursor from a previous response')
      const kinds = kindsParam(url)
      const unknown = kinds.find(kind => !isKind(kind))
      if (unknown) return fail(res, 400, 'unknown_kind', unknown)
      return sendJson(res, 200, await store.pull(since, kinds.length ? kinds : undefined))
    }

    if (route === 'GET /api/sync/status') return sendJson(res, 200, await store.status())

    return fail(res, 404, 'not_found', url.pathname)
  }

  return {
    port,
    async close() {
      await new Promise<void>((resolveClose, reject) => {
        server.close(error => error ? reject(error) : resolveClose())
      })
      await options.db.close()
    },
  }
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

function tokenOk(got: string, expected: string): boolean {
  if (!got || !expected) return false
  const a = createHash('sha256').update(got).digest()
  const b = createHash('sha256').update(expected).digest()
  return timingSafeEqual(a, b)
}

function sendJson(res: ServerResponse, status: number, body: unknown) {
  if (res.headersSent) return
  const payload = JSON.stringify(body)
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(payload) })
  res.end(payload)
}

function fail(res: ServerResponse, status: number, code: string, message: string) {
  sendJson(res, status, { error: { code, message } })
}

/** The parsed object, or why it was refused. An oversized body is drained so the client still reads the 413. */
async function readJson(req: IncomingMessage): Promise<Record<string, unknown> | 'too_large' | 'invalid'> {
  const chunks: Buffer[] = []
  let size = 0
  for await (const chunk of req) {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)
    size += buf.length
    if (size <= MAX_PUSH_BYTES) chunks.push(buf)
  }
  if (size > MAX_PUSH_BYTES) return 'too_large'
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : 'invalid'
  } catch {
    return 'invalid'
  }
}
