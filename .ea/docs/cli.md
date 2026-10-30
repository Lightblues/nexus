# CLI

`cli/` is `@lightblues/nexus`, the `nexus` command: a reader of the sync server for the user and his agents. It
calls the server's HTTP API only (sync.md → Read API). It never talks to a Mac and has no host model: one server,
one key.

## Commands

| Command | Route | Key |
|---|---|---|
| `today`, `day <when>` | `GET /api/days/<day>` | read |
| `days [--last N] [--from D --to D]` | `GET /api/days` | read |
| `records <when> [--category C] [--app A]` | `GET /api/days/<day>/records` | read |
| `devices` | `GET /api/devices` | read |
| `categories` / `categories set <file\|->` | `GET` / `PUT /api/categories` | read / write |
| `config get [prefix]` / `config set <key> <value>` | `GET /api/settings` / `POST /api/sync/push` | write |
| `rebuild` | `POST /api/summaries/rebuild` | write |
| `doctor` | `/health`, `/api/me`, `/api/devices`, today | read |
| `login [--server URL]` | `GET /api/me` to check the key | either |

`<when>` is `YYYY-MM-DD`, `today`, `yesterday`, or `-N`, resolved against the server's today (`/api/me`), so a
machine in another zone still asks for the right day. `--json` prints the server's JSON; text output is for people.

`config set` parses the value as JSON when it can (`50`, `true`, `["Code"]`), else takes it as a string. It refuses a
key the server has no setting for, or a value whose type differs from the current one, unless `--force`. The write
is a `setting` record with `updatedAt` now and device `cli`, so the Macs take it like an edit on another Mac.

`doctor` exits 1 when the server, the key, or auth fails. A Mac whose last push is over a day old is a `warn`, not a
failure.

## Config

`nexus login` reads the key on stdin (hidden at a terminal), checks it against `/api/me`, and writes
`{ server, key }` to `~/.config/nexus/config.json` (or `$XDG_CONFIG_HOME/nexus/`, or `NEXUS_CONFIG`) with mode 600.
`NEXUS_URL` and `NEXUS_KEY` override the file. The default server is `https://nexus.easonsi.site`.

## Skill

`cli/skills/nexus/SKILL.md` tells an agent when to use the CLI, what the numbers mean, and to ask before writing.
It ships in the npm package.

## Build and test

```bash
cd cli && npm install
npm test            # boots the real server on PGlite (services/server test helpers) and runs every command
npm run typecheck
node src/main.ts today   # from the checkout (Node 22.18+)
```

`npm pack` bundles `src/` into `dist/nexus.js` with esbuild (no runtime dependencies). Published as
`@lightblues/nexus` (0.1.0 on 2026-10-31, by hand; install with `npm install -g @lightblues/nexus`). Releases follow
the npm-publish skill; trusted publishing (`npm trust` plus a `release.yml`) is not set up yet.
