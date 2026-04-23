import { logger } from './Logger'
import type { CommandItem } from '@shared/types'

export type CommandSource = 'palette' | 'url-scheme' | 'hotkey' | 'internal'

export interface CommandContext {
  source: CommandSource
  args?: Record<string, unknown>
}

export interface CommandResult {
  /** Human-readable toast-style message. Undefined = silent success. */
  message?: string
  /** Whether palette should close after execution. Default true. */
  closePalette?: boolean
}

export interface CommandDefinition {
  id: string
  title: string
  /** Static or dynamic subtitle; dynamic form lets commands show live state (timer remaining, etc.). */
  subtitle?: string | (() => string | undefined)
  group?: string
  icon?: string
  keywords?: string[]
  /** Confirmation gate for destructive commands when invoked via URL scheme. */
  dangerous?: boolean
  /** When-clause: return false to hide the command in the current context. */
  when?: () => boolean
  run: (ctx: CommandContext) => Promise<CommandResult | void> | CommandResult | void
}

class CommandRegistry {
  private commands = new Map<string, CommandDefinition>()

  register(cmd: CommandDefinition): void {
    if (this.commands.has(cmd.id)) {
      logger.warn('Command id already registered, overwriting', { id: cmd.id })
    }
    this.commands.set(cmd.id, cmd)
  }

  registerMany(cmds: CommandDefinition[]): void {
    for (const cmd of cmds) this.register(cmd)
  }

  /** Visible commands for the current context (applies `when` filter). */
  list(): CommandItem[] {
    const items: CommandItem[] = []
    for (const cmd of this.commands.values()) {
      if (cmd.when && !cmd.when()) continue
      items.push(this.toItem(cmd))
    }
    return items
  }

  /** All commands regardless of `when`, used by URL scheme (caller decides context). */
  listAll(): CommandItem[] {
    return Array.from(this.commands.values()).map((c) => this.toItem(c))
  }

  get(id: string): CommandDefinition | undefined {
    return this.commands.get(id)
  }

  async execute(id: string, ctx: CommandContext): Promise<CommandResult> {
    const cmd = this.commands.get(id)
    if (!cmd) {
      logger.warn('Command not found', { id })
      return { message: `Unknown command: ${id}`, closePalette: false }
    }
    if (cmd.when && !cmd.when()) {
      logger.info('Command skipped (when=false)', { id })
      return { message: `Command unavailable: ${cmd.title}`, closePalette: false }
    }
    try {
      logger.info('Command executing', { id, source: ctx.source })
      const out = await cmd.run(ctx)
      return out || { closePalette: true }
    } catch (err) {
      logger.error('Command failed', { id, err })
      return { message: `Failed: ${cmd.title}`, closePalette: false }
    }
  }

  private toItem(cmd: CommandDefinition): CommandItem {
    const subtitle =
      typeof cmd.subtitle === 'function' ? cmd.subtitle() : cmd.subtitle
    return {
      id: cmd.id,
      title: cmd.title,
      subtitle,
      group: cmd.group,
      icon: cmd.icon,
      keywords: cmd.keywords,
      dangerous: cmd.dangerous
    }
  }
}

export const commandRegistry = new CommandRegistry()
