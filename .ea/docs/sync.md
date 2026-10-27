# Sync

Settings, pomodoro data, and tracker records follow the user across Macs. Each Mac pushes its changes to the nexus server and pulls what the others wrote. The server also serves the export feed other apps read (the protocol in sonar's `.ea/docs/export.md`). Decision: SADR-016.

```
MBP  ─┐                                         ┌─ intake (export feed, read key)
      ├─ HTTPS /api/sync/* (NEXUS_KEY) ── nexus server ── Postgres (db nexus): records
mini ─┘                                         │
```

Server code: `services/server` (TypeScript on Node ≥ 22.18, Postgres). Client code: `Packages/NexusSync` ([Swift client](#swift-client)); it uses only the contract on this page. Upload history and upload paths do not sync yet.

## What syncs

One record per row, keyed by `(kind, id)`. Bodies are JSON objects; the server checks only that a body is an object (and that a `setting` has `value`), so the field lists below are the contract between Macs.

| Kind | Local source | Id | Body |
|---|---|---|---|
| `setting` | `config.json` (`AppConfig`) | dotted key path of a leaf, e.g. `pomodoro.workDuration`, `uploader.github.token`, `tracker.enrichApps` | `{ value }`. An array is one leaf |
| `pomodoro_session` | `pomodoro_sessions` + `pomodoro_session_tags` | the session's text `id` | `{ kind, startTime, endTime, duration, project, task, completedFully, tags }`; `tags` is the session's tag names |
| `pomodoro_project` | `pomodoro_projects` | `name` | `{ color, createdAt }` |
| `pomodoro_tag` | `pomodoro_tag_catalog` | `name` | `{ createdAt }` |
| `tracker_record` | `tracker_records` | the record's UUID `uid` (the client adds and backfills it; autoincrement ids collide across Macs) | `{ startTime, endTime, duration, app, bundleId, title, contextProject, contextFile, contextUrl, contextDomain, contextRawTitle }` |

Times inside bodies keep the local units (unix seconds). `updatedAt` on a record is unix milliseconds of the edit on the Mac that made it. Absent optional columns are `null`. A project or tag rename is a delete of the old name and a new record; sessions refer to projects by name, as they do locally.

Settings sync whole, with no whitelist; the uploader's GitHub token is a setting and syncs too, so it is stored in plaintext on the server and in its backups (HTTPS protects the wire). Settings are never exported.

## Merge rule

- **Last write wins** per record by `updatedAt`. A write whose `updatedAt` is greater than the stored one replaces it. On a tie the stored copy stays.
- **Stale answer.** A write that loses is not stored; its result carries `stale`, the stored record, and the Mac applies it locally.
- **Tombstones.** A delete is pushed as `deleted: true` (no body) and stored as a record with `deleted: true, body: null`, so other Macs learn about it. A later write with a newer `updatedAt` brings the record back; an older one gets the tombstone as `stale`.
- **Order.** Every accepted write takes the next `rev` from one sequence. Writes take one transaction-scoped advisory lock before drawing a rev, so revs commit in order and a reader past a cursor never misses a write behind it.

## Client rules (nexus-017)

- Each Mac has a stable `device` id (≤ 80 characters) and keeps the `cursor` of its last pull.
- **Pull** from the cursor until `more` is false. Apply each record by `(kind, id)` unless the local copy has an unsent edit with a newer `updatedAt`; that edit is pushed and the server decides. A record from this Mac's own push is applied harmlessly.
- **Push** every local change since the last push: the whole current record with a fresh `updatedAt`, or a tombstone for a deleted row. Changing a session's tags pushes the session. Apply every `stale` record in the results; leave items with an `error` unsent and log them.
- **First contact** (no cursor yet, or a different server URL): pull everything first. For settings the server's value wins per key, so a new Mac does not overwrite shared settings with its defaults; keys the server lacks are then pushed, and later local changes push as usual. For the other kinds, local records the server lacks are pushed, and a record on both sides is settled by the merge rule.

## Swift client

`Packages/NexusSync`: a SwiftPM package (tools 5.9, macOS 13, GRDB 7 only, no AppKit/SwiftUI) that builds and tests on Linux. Decision: SADR-017.

| File | Content |
|---|---|
| `NexusSync.swift` | `NexusSync.registerMigrations(_:)`: migration `sync_v1` and the triggers |
| `Records.swift` | `SyncRecord`, `PushResult`, `PullPage`; `RecordKind`, the row ↔ body mapping for each table kind |
| `Settings.swift` | `SettingsStore` protocol; flattening `config.json` to dotted keys |
| `SyncClient.swift` | `SyncAPI` protocol; `SyncClient` (base URL, key, injectable `URLSession`) |
| `SyncEngine.swift` | `SyncEngine` actor: `sync()`, `deviceID()` |

**Schema** (`sync_v1`, registered after the app's own migrations):
- `tracker_records.uid` (unique index), filled for existing rows by the migration and for new rows by the insert trigger. `lastInsertedRowID` is unaffected.
- `sync_outbox (kind, id, updated_at)`: one row per record with an unsent local change; `updated_at` is the trigger's clock (unix ms) at the latest edit.
- `sync_state (key, value)`: `device`, `cursor`, `server` (the URL of the last first contact), and `applying` while a remote change is written.
- `sync_settings (key, value, updated_at)`: the last-synced value of every setting key (JSON text).
- Insert, update, and delete triggers on `pomodoro_sessions`, `pomodoro_session_tags` (enqueues the session), `pomodoro_projects`, `pomodoro_tag_catalog`, and `tracker_records` upsert into `sync_outbox` unless `applying` is set. An update enqueues the old key too, so a rename pushes a tombstone for the old name.

**`sync()`**:
1. First contact (`sync_state.server` ≠ the client's base URL): clear `sync_settings`, pull from 0 with settings forced to the server's values, then queue every local row the server did not send.
2. Push settings whose flattened value differs from `sync_settings` (`updatedAt` = now), then the outbox in batches of ≤ 500 items and ≤ 256 KB, each item the whole current row or a tombstone when the row is gone. An accepted item leaves the outbox only if it was not edited again meanwhile; a `stale` answer is applied; an `error` item stays and is listed in `SyncReport.failed`.
3. Pull from the cursor until `more` is false; each page is applied in one write together with its cursor and settings snapshot. A record loses to an outbox entry with a newer `updatedAt`; a setting is skipped when its local value differs from the snapshot (an edit not yet pushed). Pulled settings are written through `SettingsStore.save` before the page commits.

Any thrown error (network, HTTP status, cancellation) leaves the outbox and the cursor where the last committed page put them; the next `sync()` resumes. Settings are never pushed as tombstones: a key missing locally is one this app version does not know.

**Wiring in the app** (nexus-018, `Nexus/Features/Sync/`):
- `Migrator.migrator` calls `NexusSync.registerMigrations(&m)` after the app's own migrations.
- **Connection** (`SyncConnection`): `enabled` (default off), `server` (default `https://nexus.easonsi.site`), `key`, in `sync.json` (mode 0600) next to `config.json`. It is not part of `AppConfig`, so it never syncs and a first contact cannot overwrite another Mac's connection. This Mac's sync state (`device`, `cursor`, `server`) stays in `sync_state`.
- `ConfigSettingsStore`: `load` encodes `ConfigService.config` to a JSON object, `save` decodes it into `AppConfig` and calls `ConfigService.save` on the main actor. Every `AppConfig` key syncs, hotkey and window size included.
- `SyncCoordinator` (main actor) owns one `SyncEngine(db: database.queue, api: SyncClient(baseURL:key:), settings:)`, created only while the connection is enabled with a key and a valid URL; with sync off there is no engine and no network. It runs `sync()` after bootstrap, every 5 minutes, 10 s after the Mac wakes, and 5 s after the last edit (debounced) to pomodoro tables (`DatabaseRegionObservation`) or `config`. Tracker records change every poll, so they ride the 5-minute timer. One sync at a time; an edit during a sync (including the sync's own writes) schedules one follow-up. A failed sync backs off (30 s doubling to 30 min; edits and wake wait for it, "Sync now" does not) and shows in the status, never as an alert.
- After a sync that pulled or got `stale` records, `PomodoroRepository.refresh()` and `TrackerRepository.reload()` update the published projections.
- `TrackerRepository` keeps the uid of the last row it inserted in `sync_state` (`tracker_last_uid`, written in the insert's transaction) and extends that row after a relaunch; with no remembered uid it falls back to the highest `id` only while the database has never synced (no `server` in `sync_state`).
- **Settings → Sync**: the switch (applies at once), server and key (secure field, saved with "Save Connection"), "Sync now", and the last result (time; pushed / pulled / stale, or the error and refused items).

A fresh Mac seeds the default project and tags before its first sync; those rows are newer local edits, so they win over the server's copies under the merge rule (only `createdAt` changes).

**Tests**: XCTest with the app's v1–v4 schema copied into `Tests/NexusSyncTests/Fixture.swift` and an in-memory fake server that follows this page.

```bash
docker run --rm -v "$PWD":/w -w /w/Packages/NexusSync swift:6.1-noble \
  bash -c "apt-get -qq update && apt-get -qq install -y libsqlite3-dev && swift test"
./Packages/NexusSync/scripts/e2e.sh   # two databases through the real server on a throwaway Postgres
```

## HTTP

Every route except `GET /health` needs `Authorization: Bearer <key>`. `NEXUS_KEY` opens every route; `NEXUS_READ_KEY` opens `/export/*` only. No key or a wrong key is 401; the read key on `/api/sync/*` is 403. Errors are `{ error: { code, message } }`.

`GET /health` → `{ ok: true }`.

`POST /api/sync/push`

```json
{ "device": "mbp", "items": [{ "kind": "setting", "id": "pomodoro.workDuration", "updatedAt": 1761550000000, "deleted": false, "body": { "value": 30 } }] }
```

→ `{ "results": [{ "kind", "id", "rev"?, "stale"?, "error"? }] }`, one per item in order. `rev` is set when the write was stored; `stale` is the stored record when it won; `error` is a per-item code:

| Code | Item |
|---|---|
| `unknown_kind` | `kind` is not one of the five above |
| `invalid_id` | `id` empty, not a string, or over 200 characters |
| `invalid_updated_at` | `updatedAt` missing, negative, or not an integer |
| `invalid_body` | a live record whose body is not an object, or a `setting` without `value` |
| `too_large` | body over 64 KB of JSON |
| `invalid` | the item is not an object, or `deleted` is not a boolean |

Request errors: 400 `invalid_json` (body not a JSON object), 400 `invalid_params` (`device` missing or over 80 characters, `items` not an array), 413 `too_many_items` (over 1000 items), 413 `too_large` (request over 1 MB). A server error is 500 and nothing from that push is stored; retry it whole.

`GET /api/sync/pull?since=<cursor>&kinds=<a,b>` → `{ "records": [{ "kind", "id", "rev", "updatedAt", "deleted", "device", "body" }], "cursor": <number>, "more": <bool> }`. Oldest rev first. `since` defaults to 0; `kinds` (optional) filters, and an unknown kind is 400 `unknown_kind`. A page stops before 256 KB of records but always carries at least one; `more: true` means pull again now. An empty page returns `since` as the cursor. A bad `since` is 400 `invalid_params`.

`GET /api/sync/status` → `{ "rev": <latest rev, 0 when empty>, "kinds": { "<kind>": { "records": <live>, "deleted": <tombstones> } } }`, every kind listed.

`GET /export/kinds` → `{ "app": "nexus", "kinds": [{ "kind", "description" }] }`: `pomodoro_session`, `pomodoro_project`, `pomodoro_tag`, `tracker_record`.

`GET /export/changes?since=<cursor>&kinds=<a,b>&limit=<n>` → `{ "items": [{ "kind", "id", "updatedAt", "deleted", "data" }], "cursor": "<string>", "more": <bool> }`, in rev order. The cursor is opaque (a rev today). `kinds` filters to exported kinds and ignores the rest (so `setting` returns nothing); `limit` defaults to 100, max 500, and a page also stops before 256 KB. A delete is `deleted: true, data: null`. A bad `since` is 400.

## Server

`services/server/README.md` has run and test commands.

| Env | Default | Notes |
|---|---|---|
| `NEXUS_KEY` | required | Bearer for every route; each Mac holds it |
| `NEXUS_READ_KEY` | empty | Bearer for `/export/*` only (intake). Must differ from `NEXUS_KEY` |
| `NEXUS_DATABASE_URL` | required | Postgres; the schema is created on start |
| `NEXUS_HOST` / `NEXUS_PORT` | `127.0.0.1` / `33033` | Put TLS in front (33032 is etho's) |

Table: `records (kind, id, rev, updated_at, device, deleted, body jsonb, PRIMARY KEY (kind, id))`, an index on `rev`, and the sequence `record_rev`. Logs carry device ids and counts, never keys or bodies.

Deploy (same setup as iris): `nexus.service` on the cpu host from this repo with `services/server/.env` (not committed); Postgres database and role `nexus` in the shared container; a reverse SSH tunnel (`ssh-tunnel-tx04-33033.service`) publishes `127.0.0.1:33033` on tx04, where nginx serves `https://nexus.easonsi.site` with certbot TLS. Unit and nginx files, and the deploy steps: `services/server/` (`deploy/`, README).
