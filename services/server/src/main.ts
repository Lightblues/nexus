import { startServer } from './server.ts'
import { pgDb } from './store.ts'

const env = (name: string) => process.env[name]?.trim() || ''

const key = env('NEXUS_KEY')
const readKey = env('NEXUS_READ_KEY')
const databaseUrl = env('NEXUS_DATABASE_URL')
const host = env('NEXUS_HOST') || '127.0.0.1'
const port = Number(env('NEXUS_PORT') || 33033)
const tz = env('NEXUS_TZ') || 'Asia/Shanghai'
const validTz = (() => { try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return true } catch { return false } })()

const problems = [
  !key && 'NEXUS_KEY is required (the bearer key every Mac uses to push and pull)',
  !databaseUrl && 'NEXUS_DATABASE_URL is required (postgres://nexus:…@127.0.0.1:5432/nexus)',
  readKey && readKey === key && 'NEXUS_READ_KEY must differ from NEXUS_KEY (a read key cannot write)',
  !(Number.isInteger(port) && port >= 0 && port <= 65535) && 'NEXUS_PORT must be a port number',
  !validTz && `NEXUS_TZ must be an IANA time zone (got ${tz})`,
].filter(Boolean)
if (problems.length) {
  for (const problem of problems) console.error(`[nexus-server] ${problem}`)
  process.exit(1)
}

startServer({ key, readKey, host, port, tz, db: pgDb(databaseUrl) }).then(handle => {
  console.log(`[nexus-server] http://${host}:${handle.port}`)
  const stop = () => void handle.close().finally(() => process.exit(0))
  process.once('SIGTERM', stop)
  process.once('SIGINT', stop)
}).catch(error => {
  console.error('[nexus-server] failed:', (error as Error).message)
  process.exit(1)
})
