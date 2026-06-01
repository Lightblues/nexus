# Electron-era Spec (Archive)

These two files are preserved snapshots of the pre-Swift Electron implementation's
spec, retained solely so that Swift ADRs (`../decisions.md`, SADR-001..014) which
reference "ADR-009", "ADR-013", etc. resolve to a readable definition without
checking out a git tag.

| File | Purpose |
|---|---|
| `architecture.md` | Original Electron architecture — main + helper processes, IPC layer, electron-store, AppleScript polling |
| `decisions.md`    | ADR-001..013 — the original Electron architectural decisions, each cross-referenced from one or more SADRs |

The full Electron source tree (`src/`, `package.json`, `electron-builder.yml`,
etc.) is **not** here. Recover it via the annotated git tag:

```bash
git checkout legacy/electron                    # full Electron tree at v0.7.0
git checkout legacy/electron -- src/            # selective restore
```

Other Electron-era spec files (`pomodoro.md`, `tracker.md`, `uploader.md`,
`palette.md`, `changelog.md`) were dropped during the spec reorg — their content
is fully covered by the Swift versions one level up. If you need to read the
originals, `git show legacy/electron:.ea/spec/<file>.md` works.
