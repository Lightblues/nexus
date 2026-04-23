import { app } from 'electron'
import { URL } from 'url'
import { commandRegistry } from './CommandRegistry'
import { logger } from './Logger'

const SCHEME = 'nexus'

/**
 * Handle URLs like:
 *   nexus://command/pomodoro.toggle
 *   nexus://command/pomodoro.start?project=work&task=review+PRs
 */
class UrlSchemeHandler {
  register(): void {
    // Install protocol client (dev helper — production registration is in Info.plist).
    // In dev Electron is the wrapping executable, so we pass argv[1] to make it unique.
    if (process.defaultApp && process.argv.length >= 2) {
      app.setAsDefaultProtocolClient(SCHEME, process.execPath, [
        process.argv[1]
      ])
    } else {
      app.setAsDefaultProtocolClient(SCHEME)
    }

    // macOS — fires when another process calls `open nexus://...`
    app.on('open-url', (event, url) => {
      event.preventDefault()
      this.handle(url).catch((err) =>
        logger.error('open-url handler failed', { url, err })
      )
    })

    // Windows / Linux (and cold-start on macOS) — second instance via argv
    app.on('second-instance', (_event, argv) => {
      const urlArg = argv.find((a) => a.startsWith(`${SCHEME}://`))
      if (urlArg) {
        this.handle(urlArg).catch((err) =>
          logger.error('second-instance handler failed', { url: urlArg, err })
        )
      }
    })

    // Cold start on Windows/Linux — URL comes in via argv
    const coldStartUrl = process.argv.find((a) => a.startsWith(`${SCHEME}://`))
    if (coldStartUrl) {
      app.whenReady().then(() => {
        this.handle(coldStartUrl).catch((err) =>
          logger.error('cold-start handler failed', { url: coldStartUrl, err })
        )
      })
    }

    logger.info('URL scheme registered', { scheme: SCHEME })
  }

  async handle(rawUrl: string): Promise<void> {
    let url: URL
    try {
      url = new URL(rawUrl)
    } catch {
      logger.warn('Malformed nexus URL', { rawUrl })
      return
    }
    if (url.protocol !== `${SCHEME}:`) return

    // nexus://command/<id>  →  host='command', pathname='/<id>'
    const host = url.host
    const pathParts = url.pathname.replace(/^\/+/, '').split('/').filter(Boolean)

    if (host === 'command' && pathParts.length > 0) {
      const id = pathParts.join('.')
      const args: Record<string, string> = {}
      url.searchParams.forEach((v, k) => (args[k] = v))
      const result = await commandRegistry.execute(id, {
        source: 'url-scheme',
        args
      })
      logger.info('URL-scheme command dispatched', { id, result })
      return
    }

    logger.warn('Unsupported nexus URL shape', { rawUrl })
  }
}

export const urlSchemeHandler = new UrlSchemeHandler()
