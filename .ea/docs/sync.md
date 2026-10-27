# Sync

Settings, pomodoro data, and tracker records follow the user across Macs. Each Mac pushes its changes to the nexus server and pulls what the others wrote. The server also serves the export feed other apps read (the protocol in sonar's `.ea/docs/export.md`). Decision: SADR-016.

```
MBP  ─┐                                         ┌─ intake (export feed, read key)
      ├─ HTTPS /api/sync/* (NEXUS_KEY) ── nexus server ── Postgres (db nexus): records
mini ─┘                                         │
```

Server code: `services/server` (TypeScript on Node ≥ 22.18, Postgres). The Swift client is nexus-017; it uses only the contract on this page. Upload history and upload paths do not sync yet.

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
