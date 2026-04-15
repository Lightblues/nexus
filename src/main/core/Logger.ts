import log from 'electron-log/main'
import * as path from 'path'
import { pathManager } from './PathManager'

class Logger {
  private initialized = false

  init(): void {
    if (this.initialized) return
    log.transports.file.resolvePathFn = () =>
      path.join(pathManager.logsDir, 'main.log')
    log.transports.file.maxSize = 5 * 1024 * 1024 // 5MB
    log.transports.console.level = 'debug'
    log.transports.file.level = 'info'
    this.initialized = true
    this.info('Logger initialized')
  }

  debug(message: string, ...args: unknown[]): void {
    log.debug(message, ...args)
  }

  info(message: string, ...args: unknown[]): void {
    log.info(message, ...args)
  }

  warn(message: string, ...args: unknown[]): void {
    log.warn(message, ...args)
  }

  error(message: string, ...args: unknown[]): void {
    log.error(message, ...args)
  }
}

export const logger = new Logger()
