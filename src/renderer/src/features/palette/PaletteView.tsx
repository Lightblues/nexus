import { useState, useEffect, useMemo, useRef, KeyboardEvent } from 'react'
import type { CommandItem } from '@shared/types'

/**
 * Lightweight substring-based fuzzy match. Returns a score (higher is better)
 * or -Infinity when the query doesn't match.
 *
 * Heuristics:
 *   - exact title prefix        → highest boost
 *   - query matches every char in order in title / keywords → accepted
 *   - group / subtitle are searched but weighted lower
 */
function scoreCommand(cmd: CommandItem, query: string): number {
  if (!query) return 0
  const q = query.toLowerCase()
  const title = cmd.title.toLowerCase()
  const subtitle = (cmd.subtitle || '').toLowerCase()
  const group = (cmd.group || '').toLowerCase()
  const keywordBlob = (cmd.keywords || []).join(' ').toLowerCase()

  // Exact substring wins
  if (title.includes(q)) return 100 - title.indexOf(q)
  if (group.includes(q)) return 60 - group.indexOf(q)
  if (keywordBlob.includes(q)) return 50
  if (subtitle.includes(q)) return 30

  // Subsequence fallback (type every char in order)
  const matchSubsequence = (target: string): boolean => {
    let ti = 0
    for (const ch of q) {
      ti = target.indexOf(ch, ti)
      if (ti === -1) return false
      ti++
    }
    return true
  }
  if (matchSubsequence(title)) return 15
  if (matchSubsequence(keywordBlob)) return 10

  return -Infinity
}

export default function PaletteView() {
  const [commands, setCommands] = useState<CommandItem[]>([])
  const [query, setQuery] = useState('')
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [toast, setToast] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLDivElement>(null)

  const refreshCommands = () => {
    window.api.palette.list().then((items) => {
      setCommands(items)
    })
  }

  // Initial load + refresh each time the window becomes visible.
  useEffect(() => {
    refreshCommands()
    const onFocus = () => {
      refreshCommands()
      setQuery('')
      setSelectedIndex(0)
      setToast(null)
      inputRef.current?.focus()
      inputRef.current?.select()
    }
    window.addEventListener('focus', onFocus)
    return () => window.removeEventListener('focus', onFocus)
  }, [])

  // Filter + rank
  const filtered = useMemo(() => {
    if (!query.trim()) return commands
    return commands
      .map((c) => ({ c, score: scoreCommand(c, query.trim()) }))
      .filter((x) => x.score > -Infinity)
      .sort((a, b) => b.score - a.score)
      .map((x) => x.c)
  }, [commands, query])

  // Keep selection in range when filter shrinks
  useEffect(() => {
    if (selectedIndex >= filtered.length) {
      setSelectedIndex(Math.max(0, filtered.length - 1))
    }
  }, [filtered.length, selectedIndex])

  // Scroll selected row into view
  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLDivElement>(
      `[data-idx="${selectedIndex}"]`
    )
    el?.scrollIntoView({ block: 'nearest' })
  }, [selectedIndex])

  const execute = async (cmd: CommandItem) => {
    const result = await window.api.palette.execute(cmd.id)
    if (result.message) setToast(result.message)
    // Main process closes the window when closePalette !== false
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setSelectedIndex((i) => Math.min(i + 1, filtered.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setSelectedIndex((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      const cmd = filtered[selectedIndex]
      if (cmd) execute(cmd)
    } else if (e.key === 'Escape') {
      e.preventDefault()
      window.api.palette.close()
    }
  }

  return (
    <div
      style={{
        height: '100vh',
        display: 'flex',
        flexDirection: 'column',
        background: 'var(--bg-primary)',
        borderRadius: '12px',
        border: '1px solid var(--border)',
        overflow: 'hidden',
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif'
      }}
    >
      {/* Search input */}
      <div
        style={{
          padding: '14px 18px',
          borderBottom: '1px solid var(--border)',
          flexShrink: 0
        }}
      >
        <input
          ref={inputRef}
          autoFocus
          value={query}
          onChange={(e) => {
            setQuery(e.target.value)
            setSelectedIndex(0)
          }}
          onKeyDown={handleKeyDown}
          placeholder="Search commands…"
          style={{
            width: '100%',
            border: 'none',
            outline: 'none',
            background: 'transparent',
            color: 'var(--text-primary)',
            fontSize: '18px',
            fontWeight: 400
          }}
        />
      </div>

      {/* Results list */}
      <div
        ref={listRef}
        style={{
          flex: 1,
          overflowY: 'auto',
          padding: '6px 0'
        }}
      >
        {filtered.length === 0 && (
          <div
            style={{
              padding: '24px',
              textAlign: 'center',
              color: 'var(--text-secondary)',
              fontSize: '13px'
            }}
          >
            No matching commands
          </div>
        )}

        {filtered.map((cmd, idx) => {
          const selected = idx === selectedIndex
          return (
            <div
              key={cmd.id}
              data-idx={idx}
              onMouseEnter={() => setSelectedIndex(idx)}
              onClick={() => execute(cmd)}
              style={{
                padding: '8px 18px',
                display: 'flex',
                alignItems: 'center',
                gap: '10px',
                cursor: 'pointer',
                background: selected ? 'var(--accent)' : 'transparent',
                color: selected ? 'white' : 'var(--text-primary)'
              }}
            >
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontSize: '13px',
                    fontWeight: 500,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap'
                  }}
                >
                  {cmd.title}
                </div>
                {cmd.subtitle && (
                  <div
                    style={{
                      fontSize: '11px',
                      color: selected
                        ? 'rgba(255,255,255,0.8)'
                        : 'var(--text-secondary)',
                      marginTop: '1px',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap'
                    }}
                  >
                    {cmd.subtitle}
                  </div>
                )}
              </div>
              {cmd.group && (
                <div
                  style={{
                    fontSize: '10px',
                    color: selected
                      ? 'rgba(255,255,255,0.7)'
                      : 'var(--text-secondary)',
                    flexShrink: 0,
                    textTransform: 'uppercase',
                    letterSpacing: '0.04em'
                  }}
                >
                  {cmd.group}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Footer */}
      <div
        style={{
          padding: '6px 10px 6px 12px',
          borderTop: '1px solid var(--border)',
          fontSize: '10px',
          color: 'var(--text-secondary)',
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          flexShrink: 0
        }}
      >
        {/* Home: opens the main window. Registered as `window.openMain` so
            it also appears in the list and can be invoked via URL scheme. */}
        <button
          onClick={() => window.api.palette.execute('window.openMain')}
          title="Open Main Window"
          style={{
            border: 'none',
            background: 'transparent',
            cursor: 'pointer',
            padding: '4px 6px',
            borderRadius: '4px',
            display: 'flex',
            alignItems: 'center',
            gap: '4px',
            color: 'var(--text-primary)',
            fontSize: '11px'
          }}
          onMouseEnter={(e) => (e.currentTarget.style.background = 'var(--bg-card)')}
          onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
        >
          {/* inline home svg — no extra asset dep */}
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M3 10.5 12 3l9 7.5" />
            <path d="M5 9v11a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9" />
          </svg>
          <span>Nexus</span>
        </button>

        <span style={{ flex: 1, textAlign: 'left', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {toast || `${filtered.length} command${filtered.length === 1 ? '' : 's'}`}
        </span>

        <span>↑↓ navigate · ⏎ run · esc close</span>
      </div>
    </div>
  )
}
