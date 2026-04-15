import { EventEmitter } from 'events'
import { configManager, dataManager, logger, trayManager, type SessionRecord } from '../../core'

export type TimerState = 'idle' | 'running' | 'paused' | 'finished'
export type SessionType = 'work' | 'shortBreak' | 'longBreak'

export interface PomodoroSession {
  type: SessionType
  project?: string
  tags?: string[]
  task?: string
}

export interface PomodoroStatus {
  state: TimerState
  sessionType: SessionType
  remainingSeconds: number
  totalSeconds: number
  completedSessions: number
  currentSession?: PomodoroSession
}

export interface NextActionOption {
  action: 'startBreak' | 'startWork' | 'exit'
  label: string
  sessionType?: SessionType
}

class PomodoroService extends EventEmitter {
  private state: TimerState = 'idle'
  private sessionType: SessionType = 'work'
  private remainingSeconds = 0
  private totalSeconds = 0
  private completedSessions = 0
  private timer: NodeJS.Timeout | null = null
  private sessionStartTime: Date | null = null
  private currentSession: PomodoroSession | null = null
  private lastResetDate: string = ''
  private initialized = false

  start(session?: PomodoroSession): void {
    if (this.state === 'running') return

    this.checkAndResetDaily()

    const config = configManager.get().pomodoro
    this.currentSession = session || { type: 'work' }
    this.sessionType = this.currentSession.type

    switch (this.sessionType) {
      case 'work':
        this.totalSeconds = config.workDuration * 60
        break
      case 'shortBreak':
        this.totalSeconds = config.shortBreakDuration * 60
        break
      case 'longBreak':
        this.totalSeconds = config.longBreakDuration * 60
        break
    }

    this.remainingSeconds = this.totalSeconds
    this.sessionStartTime = new Date()
    this.state = 'running'
    this.startTimer()
    this.emitStatus()
    logger.info('Pomodoro started', { type: this.sessionType })
  }

  pause(): void {
    if (this.state !== 'running') return
    this.stopTimer()
    this.state = 'paused'
    this.emitStatus()
    logger.info('Pomodoro paused')
  }

  resume(): void {
    if (this.state !== 'paused') return
    this.state = 'running'
    this.startTimer()
    this.emitStatus()
    logger.info('Pomodoro resumed')
  }

  // Finish current session early (record and trigger finished state)
  finishEarly(): void {
    if (this.state === 'idle' || this.state === 'finished') return
    if (this.sessionType !== 'work') return // Only for work sessions
    this.stopTimer()
    this.recordSession('early')
    if (this.sessionType === 'work') {
      this.completedSessions++
    }
    this.state = 'finished'
    trayManager.setTitle('')
    this.emitStatus()
    this.emit('finished', this.sessionType)
    logger.info('Pomodoro finished early', { type: this.sessionType })
  }

  // Exit without recording (discard current session)
  exit(): void {
    if (this.state === 'idle') return
    this.stopTimer()
    this.state = 'idle'
    this.remainingSeconds = 0
    this.currentSession = null
    this.sessionStartTime = null
    trayManager.setTitle('')
    this.emitStatus()
    logger.info('Pomodoro exited')
  }

  // Skip break and immediately start next work session
  skipBreak(): void {
    if (this.sessionType === 'work') return
    this.stopTimer()
    this.recordSession('skipped')
    trayManager.setTitle('')
    // Preserve project/tags before resetting
    const project = this.currentSession?.project
    const tags = this.currentSession?.tags
    // Reset state to allow start()
    this.state = 'idle'
    this.currentSession = null
    // Immediately start next work session
    logger.info('Break skipped, starting work')
    this.start({ type: 'work', project, tags })
  }

  getStatus(): PomodoroStatus {
    this.checkAndResetDaily()
    return {
      state: this.state,
      sessionType: this.sessionType,
      remainingSeconds: this.remainingSeconds,
      totalSeconds: this.totalSeconds,
      completedSessions: this.completedSessions,
      currentSession: this.currentSession || undefined
    }
  }

  private startTimer(): void {
    this.timer = setInterval(() => {
      this.remainingSeconds--
      this.updateTrayTitle()
      this.emit('tick', this.remainingSeconds)

      if (this.remainingSeconds <= 0) {
        this.onTimerComplete()
      }
    }, 1000)
  }

  private stopTimer(): void {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  private onTimerComplete(): void {
    this.stopTimer()
    this.recordSession('normal')

    if (this.sessionType === 'work') {
      this.completedSessions++
    }

    this.state = 'finished'
    trayManager.setTitle('')
    this.emitStatus()
    this.emit('finished', this.sessionType)
    logger.info('Pomodoro finished', { type: this.sessionType })
  }

  private recordSession(completionType: 'normal' | 'early' | 'skipped'): void {
    if (!this.sessionStartTime) return

    const elapsed = this.totalSeconds - this.remainingSeconds
    const record: SessionRecord = {
      id: Date.now().toString(),
      startTime: this.sessionStartTime.toISOString(),
      endTime: new Date().toISOString(),
      duration: Math.round(elapsed / 60),
      type: this.sessionType,
      completionType,
      project: this.currentSession?.project,
      tags: this.currentSession?.tags,
      task: this.currentSession?.task
    }
    dataManager.addSession(record)
  }

  private updateTrayTitle(): void {
    const minutes = Math.floor(this.remainingSeconds / 60)
    const seconds = this.remainingSeconds % 60
    const title = ` ${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
    trayManager.setTitle(title)
  }

  private emitStatus(): void {
    this.emit('status', this.getStatus())
  }

  getNextSessionType(): SessionType {
    if (this.sessionType !== 'work') {
      return 'work'
    }
    const config = configManager.get().pomodoro
    if (this.completedSessions > 0 && this.completedSessions % config.sessionsBeforeLongBreak === 0) {
      return 'longBreak'
    }
    return 'shortBreak'
  }

  getNextOptions(): NextActionOption[] {
    if (this.sessionType === 'work') {
      const nextBreak = this.getNextSessionType()
      const breakLabel = nextBreak === 'longBreak' ? 'Start Long Break' : 'Start Short Break'
      return [
        { action: 'startBreak', label: breakLabel, sessionType: nextBreak },
        { action: 'exit', label: 'Exit' }
      ]
    } else {
      return [
        { action: 'startWork', label: 'Start Focus', sessionType: 'work' },
        { action: 'exit', label: 'Exit' }
      ]
    }
  }

  updateCurrentSession(updates: Partial<PomodoroSession>): void {
    if (!this.currentSession || this.state === 'idle') return
    this.currentSession = { ...this.currentSession, ...updates }
    this.emitStatus()
    logger.info('Session updated', { updates })
  }

  private getToday(): string {
    return new Date().toISOString().split('T')[0]
  }

  private checkAndResetDaily(): void {
    const today = this.getToday()
    if (!this.initialized) {
      // First time initialization
      this.initialized = true
      this.lastResetDate = today
      this.completedSessions = this.getTodayCompletedCount()
      logger.info('PomodoroService initialized', { date: today, todayCount: this.completedSessions })
    } else if (this.lastResetDate !== today) {
      // New day: reset counter and load today's actual count
      this.lastResetDate = today
      this.completedSessions = this.getTodayCompletedCount()
      logger.info('Daily reset', { date: today, todayCount: this.completedSessions })
    }
  }

  private getTodayCompletedCount(): number {
    const today = this.getToday()
    const stats = dataManager.getStats()
    return stats.history.filter(
      (s) => s.type === 'work' && s.completionType !== 'skipped' && s.startTime.startsWith(today)
    ).length
  }
}

export const pomodoroService = new PomodoroService()
