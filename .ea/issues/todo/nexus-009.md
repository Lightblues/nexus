---
schema_version: 1
id: nexus-009
title: Correct the README's claim that first launch migrates data
status: todo
priority: high
estimate: S
labels: [docs, readme, metadata, doc-drift]
isolation: local
delivery: none
---

## Objective
Rewrite the README's data paragraph so it says the v1.2.0 path move is the one-shot
`./scripts/migrate-data-v1.2.0.sh` run before first launch, instead of promising an
in-app auto-migration that no longer exists — and fix the four adjacent drift rows
Phase 03 folded into this one (`README.md`'s dead `.ea/spec/swift/` links and
pre-v1.2.0 data path, `.ea/project.yaml`'s Electron stack line, and `spec.md`'s
SADR index).

## Context
- `README.md:57-61` — the "## Data" section, and the primary defect. Line 59 reads
  verbatim `User data lives at \`~/.ea/nexus/\` (config, SQLite databases, log mirror).`
  (gap-analysis D-03) and lines 60-61 read verbatim `Schema-compatible with the Electron
  build's data files — first launch` / `auto-migrates legacy JSON stores.` (D-04). The
  first is the pre-v1.2.0 path; the second promises an in-app migration that was deleted.
- `.ea/spec/migration.md:162-165` — "### One-shot script (no in-app migration code)" and
  "`scripts/migrate-data-v1.2.0.sh` is the canonical migration. Run **before** launching
  v1.2.0 for the first time". This is the normative statement the README must match,
  including the ordering.
- `.ea/spec/migration.md:186-194` — "### Why the script and not in-app code", whose
  `:188-190` says "Previous Electron→Swift migration code lived in `LegacyMigration.swift`.
  That code is **deleted in v1.2.0**". This is why the README's claim is false rather
  than merely stale.
- `.ea/spec/migration.md:156-160` — the new-path table (`~/Library/Application Support/
  site.easonsi.nexus/`, `~/Library/Caches/...`, `~/Library/Logs/...`) that D-03's
  replacement text must carry.
- `.ea/spec/decisions.md:333-334` — `## SADR-015: Adopt standard macOS data layout`,
  `**Status**: Accepted (v1.2.0)`. The decision record behind the move.
- `CLAUDE.md:15` — the repository's own correct statement: names the three
  `~/Library/...` locations and says "run `./scripts/migrate-data-v1.2.0.sh` once before
  first launch". The README should not say anything different.
- `.ea/spec/spec.md:45` — the quick-reference *Data dir* row already carries the
  post-v1.2.0 value plus the SADR-015 pointer, which is what makes `spec.md` internally
  inconsistent with its own module index at `:33` (D-05).
- `README.md:6` — verbatim `See [\`.ea/spec/swift/\`](.ea/spec/swift/) for the full
  architecture and decision` (D-02). `test -e .ea/spec/swift` exits 1; the directory does
  not exist.
- `README.md:42` — verbatim `Mirrors [\`.ea/spec/swift/architecture.md\`](.ea/spec/swift/architecture.md):`
  (D-02). Same nonexistent directory.
- `.ea/spec/` — the active spec directory. `ls` lists `spec.md`, `architecture.md`,
  `decisions.md`, `pomodoro.md`, `tracker.md`, `uploader.md`, `palette.md`,
  `migration.md`, `pitfalls.md`, `legacy-electron-issues.md` and `legacy-electron/`.
  There is no `swift/` subdirectory, so both README links are dead.
- `.ea/spec/decisions.md:327` — "`.ea/spec/swift/` remains the active spec" is prose
  *inside* SADR text, not a link. It is out of scope: editing it would rewrite a
  decision record rather than fix a link.
- `.ea/project.yaml:9` — verbatim `stack: [typescript, electron, react]` (D-01). The
  repository is Swift: `CLAUDE.md:5` ("Native AppKit + SwiftUI single-binary app") and
  `project.yml:35-36` (exactly one target, `Nexus`, of type `application`) with GRDB as
  the only SwiftPM package (`project.yml:31-34`). The Electron sources live only at the
  `legacy/electron` tag (`CLAUDE.md:7`).
- `.ea/spec/spec.md:33` — verbatim `| [decisions.md](decisions.md) | Swift ADRs
  (SADR-001 .. SADR-014). Cross-references \`legacy-electron/decisions.md\` for the
  original ADR-NNN entries |` (D-05). The range is one short.
- `.ea/spec/decisions.md:333` — `## SADR-015: Adopt standard macOS data layout` is the
  last SADR heading (`grep -n "^## SADR-" .ea/spec/decisions.md | tail -1`), so
  `SADR-001 .. SADR-015` is the value `spec.md:33` must carry. `spec.md:45` on the same
  page already cites SADR-015, so the file contradicts itself.
- `.ea/report/gap-analysis.md` §3 D-01…D-05 — the five findings; §"Folded into a
  candidate row" records that D-01, D-02, D-03 and D-05 are fixed in the same pass as
  D-04.
- `.ea/runs.sh:1-5` and `:19` — D-06 (the pnpm / Electron command list, and a `--zap`
  comment naming `~/.ea/nexus`). Phase 03 recorded it as drift but folded it into no
  candidate row and did not list it under `## Not worth an issue`, so it is **out of
  scope here** and is raised in `Ask:` so the gap does not get lost.

## Tasks
- [ ] Rewrite `README.md:59` to name the post-v1.2.0 locations — `~/Library/Application Support/site.easonsi.nexus/` for config and databases, `~/Library/Caches/site.easonsi.nexus/` for thumbnails, `~/Library/Logs/site.easonsi.nexus/` for the log mirror — matching `.ea/spec/spec.md:45` and `CLAUDE.md:15`
- [ ] Replace `README.md:60-61` with the one-shot migration contract: the path move is `./scripts/migrate-data-v1.2.0.sh`, run once **before** the first v1.2.0 launch, and there is no in-app migration because `LegacyMigration.swift` was deleted in v1.2.0
- [ ] Repoint the two dead spec links: `README.md:6` → [`.ea/spec/`](.ea/spec/) and `README.md:42` → [`.ea/spec/architecture.md`](.ea/spec/architecture.md)
- [ ] Correct `.ea/project.yaml:9` from `stack: [typescript, electron, react]` to the actual stack — `swift`, `swiftui`, `appkit` (GRDB is the only SwiftPM dependency, so it does not belong in `stack`)
- [ ] Bump the SADR range in `.ea/spec/spec.md:33` from `SADR-001 .. SADR-014` to `SADR-001 .. SADR-015`, leaving the rest of that table row intact
- [ ] Leave `.ea/spec/decisions.md:327` unchanged — it is historical SADR prose, not a link
- [ ] Leave `.ea/runs.sh` unchanged in this issue (see `Ask:`)

## Acceptance
- [ ] `grep -n "spec/swift" README.md` returns nothing, and both README spec links resolve (`test -e .ea/spec` and `test -e .ea/spec/architecture.md` both exit 0)
- [ ] `grep -n "~/.ea/nexus" README.md` returns nothing
- [ ] `grep -ni "auto-migrat" README.md` returns nothing, and `grep -n "migrate-data-v1.2.0.sh" README.md` matches the Data section
- [ ] `sed -n '9p' .ea/project.yaml` contains none of `typescript`, `electron` or `react`, and does name the Swift stack
- [ ] `sed -n '33p' .ea/spec/spec.md` contains `SADR-001 .. SADR-015`, and that range equals the last SADR heading in `.ea/spec/decisions.md`
- [ ] `README.md`, `.ea/project.yaml` and `.ea/spec/spec.md` agree with `CLAUDE.md:15` on where data lives and how it moves
- [ ] The README still says the app is schema-compatible with the Electron data files only if that remains true; `.ea/spec/migration.md:186-194` says the Electron JSON stores are not read by the Swift app, so the compatibility claim is removed or qualified rather than left as-is
- [ ] Nothing edited here is contradicted by a command run in this repository

## Boundaries
- Always: take the migration wording from `.ea/spec/migration.md:162-165` instead of paraphrasing, so the README and the spec cannot drift apart again
- Always: state that the script runs *before* the first v1.2.0 launch — the ordering is the part a reader can get wrong, and it is what `CLAUDE.md:15` says
- Never: reintroduce a promise of in-app migration; `LegacyMigration.swift` is deleted and no code path reads `~/.ea/nexus/` any more
- Never: edit SADR text in `.ea/spec/decisions.md` to fix a link or a range — SADR-015 records a decision at a point in time, and `spec.md:33` is the index that tracks it
- Never: widen this into a general README rewrite. The scope is the five Phase 03 rows named above; anything else is a separate decision
- Ask: whether to also fix `.ea/runs.sh` (D-06) in this pass. It is stale (`pnpm install`, `pnpm build:mac  # dist/Nexus-0.3.5-arm64.dmg`, and a `--zap` comment listing `~/.ea/nexus`), but Phase 03 gave it no owner: it is neither folded into this row nor listed under `## Not worth an issue`
- Ask: whether `README.md:47` (the `Core/` comment still naming `DataStore`, which has no call site — gap-analysis T-10) and `README.md:52` (labelling `Palette/` as the "⌘K command palette" while `default-config.json:25` sets `hotkey.palette` to `CommandOrControl+Shift+Space`) should ride along. Both were found while verifying this issue and neither is a Phase 03 drift entry
