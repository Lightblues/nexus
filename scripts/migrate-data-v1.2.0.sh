#!/usr/bin/env bash
# migrate-data-v1.2.0.sh — One-shot move from Nexus's pre-v1.2.0 data layout
# (everything under ~/.ea/nexus/) into standard macOS locations.
#
# Run BEFORE first launching v1.2.0:
#   ./scripts/migrate-data-v1.2.0.sh
#
# This script:
#   - quits any running Nexus
#   - moves config.json + nexus.db (+ -wal, -shm) → ~/Library/Application Support/site.easonsi.nexus/
#   - drops the old uploader/cache/ (thumbnails regenerate on next upload)
#   - drops the old logs/ (OSLog history is independent)
#   - drops legacy JSON files already imported into nexus.db (data.json, tracker/, archive/, uploader.json)
#   - archives the old root as ~/.ea/nexus.pre-v1.2.0-bak-<timestamp>/
#   - clears Electron-era residue from ~/Library/Application Support/nexus/ and ~/Library/Logs/nexus/
#
# Idempotent: re-runs cleanly when there's nothing left to move.

set -euo pipefail

OLD="$HOME/.ea/nexus"
SUPPORT="$HOME/Library/Application Support/site.easonsi.nexus"
CACHES="$HOME/Library/Caches/site.easonsi.nexus"
LOGS="$HOME/Library/Logs/site.easonsi.nexus"
TS=$(date +%Y%m%d-%H%M%S)
BAK="$HOME/.ea/nexus.pre-v1.2.0-bak-$TS"

cyan() { printf '\033[36m%s\033[0m\n' "$1"; }
green() { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }
gray() { printf '\033[90m  · %s\033[0m\n' "$1"; }

cyan "==> Quitting any running Nexus"
pkill -f "/Applications/Nexus.app/Contents/MacOS/Nexus" 2>/dev/null || true
pkill -f "DerivedData/Nexus-.*/Build/Products/.*/Nexus.app/Contents/MacOS/Nexus" 2>/dev/null || true
sleep 0.3

# Already migrated? Detect by checking the new location for a populated db.
if [[ -f "$SUPPORT/nexus.db" && ! -d "$OLD" ]]; then
  green "Already on v1.2.0 layout — nothing to do."
  echo "  Application Support: $SUPPORT"
  exit 0
fi

if [[ ! -d "$OLD" ]]; then
  green "No legacy data at $OLD — fresh install."
  mkdir -p "$SUPPORT" "$CACHES" "$LOGS"
  exit 0
fi

cyan "==> Creating destination directories"
mkdir -p "$SUPPORT" "$CACHES" "$LOGS"
green "$SUPPORT"
green "$CACHES"
green "$LOGS"

cyan "==> Moving user-critical files (config + db) to Application Support"
for f in config.json nexus.db nexus.db-wal nexus.db-shm; do
  if [[ -e "$OLD/$f" || -L "$OLD/$f" ]]; then
    # `mv` preserves symlinks (so Mackup chains pointing at config.json keep working).
    mv -v "$OLD/$f" "$SUPPORT/$f"
  else
    gray "skip $f (not present)"
  fi
done

cyan "==> Archiving the old root"
mv -v "$OLD" "$BAK"
green "Old data archived: $BAK"
echo
gray "  This directory contains: legacy JSON files (data.json, tracker/, archive/,"
gray "  uploader.json, uploader/cache/) that were already imported into nexus.db"
gray "  by an earlier run, plus log mirrors. Safe to delete after verifying the"
gray "  new install boots and your data looks right:"
gray "    rm -rf '$BAK'"

cyan "==> Cleaning Electron-era residue (if any)"
for stray in "$HOME/Library/Application Support/nexus" "$HOME/Library/Logs/nexus"; do
  if [[ -d "$stray" ]]; then
    target="${stray}.electron-bak-$TS"
    mv -v "$stray" "$target"
    green "Renamed: $target"
  fi
done

echo
green "Migration complete."
echo
echo "  Launch Nexus:   open /Applications/Nexus.app"
echo "  Inspect data:   open '$SUPPORT'"
echo "  Tail log:       tail -f '$LOGS/main.log'"
