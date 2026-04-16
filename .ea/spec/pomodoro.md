# Pomodoro Timer

## Features
- Standard pomodoro cycle: Focus → Short Break → Focus → Long Break (configurable)
- Project/tag/task metadata per work session
- Daily count auto-reset (loads from history on new day)
- System notification on completion
- Statistics dashboard (activity calendar, weekly chart, daily timeline)

## State Machine
```
Idle → Running → Paused → Finished
                    ↘ Finished (early)
```

Actions per state:
- **Running (work)**: Pause, Finish Early, Exit
- **Running (break)**: Skip, Exit
- **Paused**: Resume, Finish Early, Exit
- **Finished**: Start next (break/work), Exit

## Session Metadata
- `project`: High-level grouping (orthogonal to tags, like Linear.app)
- `tags[]`: Cross-cutting labels
- `task`: Free-text description (optional)
- New session defaults to last session's project/tags/task

## UI (Popup)

### Layout
```
[← Back]  [Focus]  [#7]
┌─────────────────────────┐
│  7 sessions  │  2h 31m  │  ← clickable → main window
└─────────────────────────┘
      ┌──────────┐
      │  --:--   │          ← progress ring
      └──────────┘
┌─────────────────────────┐
│ projectName · tag1, tag2│  ← clickable → edit modal
└─────────────────────────┘
      [Start Focus]
```

### Edit Modal (shared for idle + running/paused)
- Project selector + inline "New" input
- Tags: scrollable chip list (`maxHeight: 100px`) + "Add tag" input
- Task: single-line text input
- **Esc** key or click backdrop to close
- Compact font sizes (11px labels, 11px inputs/tags, 14px title)

## Statistics (MainWindow → Statistics tab)

### Visualization
- **Activity Calendar**: GitHub-style heatmap (`react-activity-calendar`), uses full history including archived sessions
- **Weekly Bar Chart**: Last 7 days, hours focused (`recharts`)
- **Daily Timeline**: Horizontal bar 00:00-24:00, work=accent/break=green, tooltip with time range
- **Session List**: Editable records per day (project/tags/task/time)

## Config (`config.yaml`)
```yaml
pomodoro:
  workDuration: 25
  shortBreakDuration: 5
  longBreakDuration: 15
  sessionsBeforeLongBreak: 4
  projects: [{ name: 'default', color: '#3B82F6' }]
  tags: ['work', 'study', 'personal']
  showPopoverOnComplete: true
```

## Data Storage
- Active sessions: `~/.ea/nexus/data.json` (via electron-store)
- Archived sessions: `~/.ea/nexus/archive/pomodoro-{YYYY}.json`
- Archive threshold: 90 days
- Deduplication by session ID on archive merge
