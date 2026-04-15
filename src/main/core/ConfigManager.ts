import * as fs from 'fs'
import * as yaml from 'js-yaml'
import { EventEmitter } from 'events'
import { pathManager } from './PathManager'
import { logger } from './Logger'

export interface PomodoroConfig {
  workDuration: number
  shortBreakDuration: number
  longBreakDuration: number
  sessionsBeforeLongBreak: number
  projects: Array<{ name: string; color: string }>
  tags: string[]
  showPopoverOnComplete: boolean
}

export interface UIConfig {
  windowWidth: number
  windowHeight: number
}

export interface TrackerConfig {
  enabled: boolean
  pollInterval: number // seconds
  idleThreshold: number // seconds
  recordTitle: boolean
  enrichApps: string[]
}

export interface UploaderConfig {
  enabled: boolean
  github: {
    token: string
    owner: string
    repo: string
    branch: string
  }
  cdn: {
    baseUrl: string
  }
  compress: {
    quality: number
    defaultFormat: 'auto' | 'webp' | 'jpeg' | 'png'
  }
  defaultPath: string
  cacheThumbnails: boolean
}

export interface AppConfig {
  pomodoro: PomodoroConfig
  ui: UIConfig
  tracker: TrackerConfig
  uploader: UploaderConfig
}

const DEFAULT_CONFIG: AppConfig = {
  pomodoro: {
    workDuration: 25,
    shortBreakDuration: 5,
    longBreakDuration: 15,
    sessionsBeforeLongBreak: 4,
    projects: [{ name: 'default', color: '#3B82F6' }],
    tags: ['work', 'study', 'personal'],
    showPopoverOnComplete: true
  },
  ui: {
    windowWidth: 320,
    windowHeight: 400
  },
  tracker: {
    enabled: true,
    pollInterval: 5,
    idleThreshold: 120,
    recordTitle: false,
    enrichApps: ['Code', 'Google Chrome']
  },
  uploader: {
    enabled: true,
    github: {
      token: '',
      owner: '',
      repo: '',
      branch: 'main'
    },
    cdn: {
      baseUrl: 'https://cdn.jsdelivr.net/gh'
    },
    compress: {
      quality: 80,
      defaultFormat: 'auto'
    },
    defaultPath: 'upload',
    cacheThumbnails: true
  }
}

class ConfigManager extends EventEmitter {
  private config: AppConfig = DEFAULT_CONFIG
  private watcher: fs.FSWatcher | null = null
  private debounceTimer: NodeJS.Timeout | null = null

  load(): AppConfig {
    const configPath = pathManager.configPath
    if (!fs.existsSync(configPath)) {
      this.copyDefaultConfig()
    }
    try {
      const content = fs.readFileSync(configPath, 'utf-8')
      const loaded = yaml.load(content) as Partial<AppConfig>
      this.config = this.mergeWithDefaults(loaded)
      logger.info('Config loaded', { path: configPath })
    } catch (err) {
      logger.error('Failed to load config, using defaults', err)
      this.config = DEFAULT_CONFIG
    }
    return this.config
  }

  private copyDefaultConfig(): void {
    const defaultPath = pathManager.getResourcePath('default-config.yaml')
    const configPath = pathManager.configPath
    try {
      if (fs.existsSync(defaultPath)) {
        fs.copyFileSync(defaultPath, configPath)
        logger.info('Copied default config')
      } else {
        fs.writeFileSync(configPath, yaml.dump(DEFAULT_CONFIG))
        logger.info('Created default config')
      }
    } catch (err) {
      logger.error('Failed to create config file', err)
    }
  }

  private mergeWithDefaults(loaded: Partial<AppConfig>): AppConfig {
    return {
      pomodoro: { ...DEFAULT_CONFIG.pomodoro, ...loaded.pomodoro },
      ui: { ...DEFAULT_CONFIG.ui, ...loaded.ui },
      tracker: { ...DEFAULT_CONFIG.tracker, ...loaded.tracker },
      uploader: {
        ...DEFAULT_CONFIG.uploader,
        ...loaded.uploader,
        github: { ...DEFAULT_CONFIG.uploader.github, ...loaded.uploader?.github },
        cdn: { ...DEFAULT_CONFIG.uploader.cdn, ...loaded.uploader?.cdn },
        compress: { ...DEFAULT_CONFIG.uploader.compress, ...loaded.uploader?.compress }
      }
    }
  }

  get(): AppConfig {
    return this.config
  }

  watch(): void {
    const configPath = pathManager.configPath
    this.watcher = fs.watch(configPath, (eventType) => {
      if (eventType === 'change') {
        if (this.debounceTimer) clearTimeout(this.debounceTimer)
        this.debounceTimer = setTimeout(() => {
          logger.info('Config file changed, reloading')
          this.load()
          this.emit('config:updated', this.config)
        }, 300)
      }
    })
    logger.info('Watching config for changes')
  }

  stopWatching(): void {
    if (this.watcher) {
      this.watcher.close()
      this.watcher = null
    }
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }
}

export const configManager = new ConfigManager()
