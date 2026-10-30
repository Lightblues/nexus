import { chmodSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'

export interface Config {
  server: string
  key: string
}

export const DEFAULT_SERVER = 'https://nexus.easonsi.site'

export function configPath(env: NodeJS.ProcessEnv = process.env): string {
  return env.NEXUS_CONFIG || join(env.XDG_CONFIG_HOME || join(homedir(), '.config'), 'nexus', 'config.json')
}

/** `NEXUS_URL` / `NEXUS_KEY` win over the file `nexus login` writes. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config & { source: string } {
  let file: Partial<Config> = {}
  try { file = JSON.parse(readFileSync(configPath(env), 'utf8')) } catch { /* no file yet */ }
  const server = (env.NEXUS_URL || file.server || DEFAULT_SERVER).replace(/\/+$/, '')
  const key = env.NEXUS_KEY || file.key || ''
  return { server, key, source: env.NEXUS_KEY ? 'NEXUS_KEY' : file.key ? configPath(env) : 'none' }
}

export function saveConfig(config: Config, env: NodeJS.ProcessEnv = process.env): string {
  const path = configPath(env)
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 })
  chmodSync(path, 0o600)
  return path
}

export class ApiError extends Error {
  readonly status: number
  readonly code: string
  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

export function client(config: Config, fetcher: typeof fetch = fetch) {
  async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
    if (!config.key) throw new ApiError(0, 'no_key', 'no key: run `nexus login` or set NEXUS_KEY')
    let res: Response
    try {
      res = await fetcher(`${config.server}${path}`, {
        method,
        headers: { authorization: `Bearer ${config.key}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
        body: body === undefined ? undefined : JSON.stringify(body),
      })
    } catch (error) {
      throw new ApiError(0, 'network', `cannot reach ${config.server}: ${(error as Error).message}`)
    }
    const text = await res.text()
    let data: unknown
    try { data = text ? JSON.parse(text) : null } catch { data = text }
    if (!res.ok) {
      const err = (data as { error?: { code?: string; message?: string } } | null)?.error
      throw new ApiError(res.status, err?.code ?? 'http', `${res.status} ${err?.message ?? res.statusText}`)
    }
    return data as T
  }
  return {
    server: config.server,
    get: <T>(path: string) => call<T>('GET', path),
    put: <T>(path: string, body: unknown) => call<T>('PUT', path, body),
    post: <T>(path: string, body: unknown) => call<T>('POST', path, body),
    async health(): Promise<boolean> {
      try { return (await fetcher(`${config.server}/health`)).ok } catch { return false }
    },
  }
}

export type Client = ReturnType<typeof client>
