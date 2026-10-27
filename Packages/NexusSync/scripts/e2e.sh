#!/usr/bin/env bash
# Two in-memory databases sync through the real services/server on a throwaway Postgres.
# Needs docker, node >= 22.18, and `npm install` done in services/server. The key is random and never printed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PG_PORT="${PG_PORT:-55433}"
PG_NAME="nexussync-e2e-pg"
LOG="$(mktemp)"
export NEXUS_E2E_KEY="$(openssl rand -hex 24)"

cleanup() {
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
  docker rm -f "$PG_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker rm -f "$PG_NAME" >/dev/null 2>&1 || true
docker run -d --name "$PG_NAME" -e POSTGRES_PASSWORD=e2e -e POSTGRES_DB=nexus -p "127.0.0.1:$PG_PORT:5432" postgres:17 >/dev/null
until docker exec "$PG_NAME" pg_isready -h 127.0.0.1 -U postgres -d nexus >/dev/null 2>&1; do sleep 0.5; done

# Port 0: the server picks a free port and logs it.
(cd "$ROOT/services/server" && NEXUS_KEY="$NEXUS_E2E_KEY" NEXUS_PORT=0 \
  NEXUS_DATABASE_URL="postgres://postgres:e2e@127.0.0.1:$PG_PORT/nexus" exec node src/main.ts) >"$LOG" 2>&1 &
SERVER_PID=$!
for _ in $(seq 60); do grep -q '^\[nexus-server\] http://' "$LOG" && break; kill -0 "$SERVER_PID" 2>/dev/null || break; sleep 0.5; done
export NEXUS_E2E_URL="$(grep -o 'http://127.0.0.1:[0-9]*' "$LOG" | head -1)"
[[ -n "$NEXUS_E2E_URL" ]] && curl -sf "$NEXUS_E2E_URL/health" >/dev/null || { cat "$LOG"; exit 1; }

docker run --rm --network host -e NEXUS_E2E_URL -e NEXUS_E2E_KEY -v "$ROOT":/w -w /w/Packages/NexusSync swift:6.1-noble \
  bash -c "apt-get -qq update && apt-get -qq install -y libsqlite3-dev >/dev/null && swift test --filter ServerE2ETests" \
  || { echo "--- server log"; cat "$LOG"; exit 1; }
echo "--- server log"
cat "$LOG"
