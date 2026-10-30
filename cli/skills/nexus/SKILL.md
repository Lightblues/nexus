---
name: nexus
description: >-
  Read the user's own activity from Nexus, his macOS menu bar app: how long he worked today or on any day,
  on which projects, apps and sites, his focus blocks, and his pomodoro sessions, from the nexus sync server
  through the `nexus` CLI. Also changes a synced Nexus setting (pomodoro durations, tracker options) and the
  category rules. Use when the user asks what he did today or yesterday, how much he coded, time on a project,
  a weekly review, a daily note or standup from his activity, whether his Macs are syncing, or says nexus,
  时间统计, 今天干了什么, 番茄钟, 专注时间, 周报, 日报.
---

# nexus

Nexus runs on each of the user's Macs and syncs to one server. The server cleans the tracker rows (lock screen and
idle removed, editor projects parsed from window titles), sorts them into categories, and keeps one summary per local
day. The `nexus` CLI reads that server. It never talks to a Mac, so it works from any machine with a key.

## Reading

```bash
nexus today                       # today's summary
nexus day yesterday               # or YYYY-MM-DD, or -N for N days ago
nexus days --last 7               # one line per day; --from/--to for a range
nexus records 2026-10-30          # every cleaned activity row; --category coding, --app Code
nexus devices                     # each Mac's last push and last activity
nexus doctor                      # server, key, and sync health
```

Add `--json` to any command for the server's JSON, which is better for computing totals or writing a review than
parsing text. Times are in the server's zone (`nexus doctor` prints it). A day summary has `activeSeconds`,
`categories`, `projects`, `apps`, `domains` (each with `seconds`), `blocks` (stretches of 10+ minutes in one category),
and `pomodoro` (`work` count, `workSeconds`, per-project totals, and the sessions).

What the numbers mean:

- Active time counts only when a window was in front and the user was not idle; overlapping time on two Macs counts once.
- Rows from before Nexus 1.3.2 could run across sleep, so no single old row counts for more than an hour.
- Categories: coding, ai, communication, meeting, notes, reading, entertainment, browsing, system, other.
  A site decides before its browser does (bilibili in Chrome is entertainment, an unknown site is browsing).

## Changing things (write key only)

```bash
nexus config get pomodoro          # synced settings under a prefix; secrets show only their length
nexus config set pomodoro.workDuration 50
nexus categories                   # current rules
nexus categories set rules.json    # { "domains": {"x.com": "reading"}, "apps": {"Obsidian": "notes"} }
```

`config set` pushes a setting record as device `cli`; each Mac applies it on its next sync (within five minutes).
It refuses an unknown key or a value of the wrong type unless `--force` is given. Ask the user before changing a
setting or the rules; reading needs no confirmation.

## Setup

`nexus login` reads a key on stdin and saves it to `~/.config/nexus/config.json` (mode 600). `NEXUS_URL` and
`NEXUS_KEY` override the file. A read key can do everything except the write commands above. Never print the key or
the config file; if `nexus doctor` says the key is missing or refused, ask the user to run `nexus login` themselves.
