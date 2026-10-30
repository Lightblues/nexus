# nexus server

Sync and export for Nexus. Each Mac pushes and pulls records over HTTP; other apps read `/export/*`.

Spec (record kinds, HTTP contract, merge rule, deploy): [`.ea/docs/sync.md`](../../.ea/docs/sync.md).

```bash
npm install
npm test           # in-memory PGlite
npx tsc -p .       # type check
npm run admin -- users              # users, keys, records (reads .env)
npm run admin -- add-user <name>    # a new user and its first write key, printed once
NEXUS_KEY=… NEXUS_READ_KEY=… NEXUS_DATABASE_URL=postgres://nexus:…@127.0.0.1:5432/nexus npm start
```

| Env | Default | Notes |
|---|---|---|
| `NEXUS_KEY` | required | The owner's bearer for every route |
| `NEXUS_READ_KEY` | empty | The owner's bearer for reads only: `/export/*`, the read API, web login |
| `NEXUS_DATABASE_URL` | required | Postgres; the schema is created on start |
| `NEXUS_HOST` / `NEXUS_PORT` | `127.0.0.1` / `33033` | Put TLS in front |
| `NEXUS_TZ` | `Asia/Shanghai` | IANA zone whose midnights split days |

The server also serves the web app from `web/` (`/`, `/login`, `/app`; `.ea/docs/web.md`) and builds day summaries (`.ea/docs/sync.md` → Day summaries).

Node 22.18 or newer runs the `.ts` files directly. Units and nginx config for the deploy are in `deploy/`.

## Deploy

Live at `https://nexus.easonsi.site` (deployed 2026-10-27).

- **cpu host**: `nexus.service` runs this directory with `.env` (not committed) and listens on `127.0.0.1:33033`. Port 33032 belongs to etho. Postgres is the database `nexus` in the shared container.
- **Tunnel**: `ssh-tunnel-tx04-33033.service` on the cpu host publishes `127.0.0.1:33033` on tx04.
- **tx04**: nginx serves `nexus.easonsi.site` with `deploy/nexus.nginx.conf`, TLS from certbot (copied back from tx04 with its certbot blocks), and proxies to `127.0.0.1:33033`.
- **Check**: `/health` returns 200, and keyed routes return 401 without a key.

```bash
sudo cp deploy/nexus.service deploy/ssh-tunnel-tx04-33033.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now nexus ssh-tunnel-tx04-33033
sudo systemctl restart nexus        # after pulling new server code
curl -s https://nexus.easonsi.site/health
```
