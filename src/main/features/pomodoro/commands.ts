import { commandRegistry } from '../../core'
import { pomodoroService } from './PomodoroService'

/**
 * Register pomodoro-related palette / URL-scheme commands.
 *
 * Commands are thin wrappers over PomodoroService — the Service is the source of
 * truth, commands are just an alternative invocation surface (palette, URL scheme).
 */
export function registerPomodoroCommands(): void {
  const fmtRemaining = (): string | undefined => {
    const s = pomodoroService.getStatus()
    if (s.state === 'idle' || s.state === 'finished') return undefined
    const m = Math.floor(s.remainingSeconds / 60)
    const sec = s.remainingSeconds % 60
    const pad = (n: number) => n.toString().padStart(2, '0')
    return `${s.state} · ${pad(m)}:${pad(sec)}`
  }

  commandRegistry.registerMany([
    // Smart toggle: single entry point that does the right thing for the current state.
    {
      id: 'pomodoro.toggle',
      title: 'Pomodoro: Start / Pause',
      group: 'Pomodoro',
      keywords: ['focus', 'timer', 'start', 'pause', 'resume'],
      subtitle: () => {
        const s = pomodoroService.getStatus()
        switch (s.state) {
          case 'idle':
            return 'Start a focus session'
          case 'running':
            return fmtRemaining() + ' · click to pause'
          case 'paused':
            return fmtRemaining() + ' · click to resume'
          case 'finished':
            return 'Session finished — open popup to choose next'
        }
      },
      run: () => {
        const s = pomodoroService.getStatus()
        if (s.state === 'idle') {
          pomodoroService.start()
          return { message: 'Focus started' }
        }
        if (s.state === 'running') {
          pomodoroService.pause()
          return { message: 'Paused' }
        }
        if (s.state === 'paused') {
          pomodoroService.resume()
          return { message: 'Resumed' }
        }
        return { message: 'Session finished — open popup', closePalette: false }
      }
    },

    {
      id: 'pomodoro.start',
      title: 'Pomodoro: Start Focus',
      group: 'Pomodoro',
      keywords: ['focus', 'begin', 'work'],
      when: () => pomodoroService.getStatus().state === 'idle',
      run: () => {
        pomodoroService.start()
        return { message: 'Focus started' }
      }
    },

    {
      id: 'pomodoro.pause',
      title: 'Pomodoro: Pause',
      group: 'Pomodoro',
      keywords: ['stop', 'hold'],
      when: () => pomodoroService.getStatus().state === 'running',
      subtitle: fmtRemaining,
      run: () => {
        pomodoroService.pause()
        return { message: 'Paused' }
      }
    },

    {
      id: 'pomodoro.resume',
      title: 'Pomodoro: Resume',
      group: 'Pomodoro',
      keywords: ['continue', 'unpause'],
      when: () => pomodoroService.getStatus().state === 'paused',
      subtitle: fmtRemaining,
      run: () => {
        pomodoroService.resume()
        return { message: 'Resumed' }
      }
    },

    {
      id: 'pomodoro.finishEarly',
      title: 'Pomodoro: Finish Early',
      group: 'Pomodoro',
      keywords: ['end', 'complete'],
      when: () => {
        const s = pomodoroService.getStatus()
        return (
          (s.state === 'running' || s.state === 'paused') &&
          s.sessionType === 'work'
        )
      },
      run: () => {
        pomodoroService.finishEarly()
        return { message: 'Session finished early' }
      }
    },

    {
      id: 'pomodoro.exit',
      title: 'Pomodoro: Exit (discard)',
      group: 'Pomodoro',
      keywords: ['cancel', 'discard', 'stop'],
      when: () => pomodoroService.getStatus().state !== 'idle',
      dangerous: true,
      run: () => {
        pomodoroService.exit()
        return { message: 'Session discarded' }
      }
    }
  ])
}
