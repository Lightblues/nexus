import { app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'

class PathManager {
  private _eaDir: string

  constructor() {
    this._eaDir = path.join(os.homedir(), '.ea', 'nexus')
  }

  get eaDir(): string {
    return this._eaDir
  }

  get configPath(): string {
    return path.join(this._eaDir, 'config.yaml')
  }

  get dataPath(): string {
    return path.join(this._eaDir, 'data.json')
  }

  get logsDir(): string {
    return path.join(this._eaDir, 'logs')
  }

  ensureDirectories(): void {
    fs.mkdirSync(this._eaDir, { recursive: true })
    fs.mkdirSync(this.logsDir, { recursive: true })
  }

  getResourcePath(filename: string): string {
    if (app.isPackaged) {
      return path.join(process.resourcesPath, filename)
    }
    return path.join(__dirname, '../../resources', filename)
  }
}

export const pathManager = new PathManager()
