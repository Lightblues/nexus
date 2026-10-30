#!/usr/bin/env bash
# ci-checks.sh — Unit tests, and checks on what build-mac.sh produced. Run on a Mac (CI or local).
#
#   ./scripts/ci-checks.sh unit     # xcodebuild test (NexusTests); assert the suite left no app data behind (nexus-013)
#   ./scripts/ci-checks.sh launch   # start build/export/Nexus.app, assert alive + launch banner (nexus-003)
#   ./scripts/ci-checks.sh dmg      # mount dist/Nexus-*.dmg, assert the drag-install layout (nexus-012)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${RUNNER_TEMP:-/tmp}"

unit() {
  local data="$HOME/Library/Application Support/site.easonsi.nexus" log="$TMP/nexus-unit.log"
  local had_data=0
  [[ -e "$data" ]] && had_data=1
  (cd "$PROJECT_DIR" && xcodegen generate >/dev/null)
  if ! xcodebuild -project "$PROJECT_DIR/Nexus.xcodeproj" -scheme Nexus -destination 'platform=macOS' \
    ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO test >"$log" 2>&1; then
    grep -E "error:|failed|Failing tests" "$log" || tail -50 "$log"
    echo "Unit tests failed (full log: $log)"; exit 1
  fi
  grep -E "Executed [0-9]+ tests?" "$log" | tail -1
  if [[ $had_data == 0 && -e "$data" ]]; then
    echo "The test run created $data:"; ls -la "$data"; exit 1
  fi
  echo "Unit tests passed"
}

launch() {
  local app="$PROJECT_DIR/build/export/Nexus.app" log="$HOME/Library/Logs/site.easonsi.nexus/main.log"
  local out="$TMP/nexus-launch.out" wait_s="${LAUNCH_WAIT:-10}"
  [[ -x "$app/Contents/MacOS/Nexus" ]] || { echo "No exported app at $app"; exit 1; }
  if ! launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
    echo "No GUI (aqua) session for uid $(id -u): cannot launch a menu bar app here; this is not a crash"
    exit 1
  fi
  if pgrep -f "Nexus.app/Contents/MacOS/Nexus" >/dev/null; then
    echo "Another Nexus is running; a second instance would exit"; exit 1
  fi
  local before=0
  [[ -f "$log" ]] && before=$(wc -l < "$log")

  "$app/Contents/MacOS/Nexus" >"$out" 2>&1 &
  local pid=$!
  trap "kill $pid 2>/dev/null || true; sleep 1; kill -9 $pid 2>/dev/null || true" EXIT
  sleep "$wait_s"

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Nexus exited within ${wait_s}s of launch. Output:"; cat "$out"
    echo "--- main.log (tail)"; [[ -f "$log" ]] && tail -20 "$log"
    exit 1
  fi
  if ! [[ -f "$log" ]] || ! tail -n +"$((before + 1))" "$log" | grep -q "===== Launched Nexus v.*pid=$pid"; then
    echo "Nexus is running but wrote no launch banner to $log. Output:"; cat "$out"
    [[ -f "$log" ]] && tail -20 "$log"
    exit 1
  fi
  tail -n +"$((before + 1))" "$log" | grep "===== Launched Nexus"
  echo "Launch check passed (pid $pid alive after ${wait_s}s)"
}

dmg() {
  local dmg
  dmg=$(ls -t "$PROJECT_DIR"/dist/Nexus-*.dmg 2>/dev/null | head -1)
  [[ -n "$dmg" ]] || { echo "No dist/Nexus-*.dmg"; exit 1; }
  local plist mount
  plist=$(hdiutil attach "$dmg" -nobrowse -readonly -plist) || { echo "Cannot attach $dmg"; exit 1; }
  mount=$(echo "$plist" | python3 -c '
import plistlib, sys
for e in plistlib.loads(sys.stdin.buffer.read()).get("system-entities", []):
    if "mount-point" in e: print(e["mount-point"]); break
')
  [[ -n "$mount" && -d "$mount" ]] || { echo "No mount point for $dmg"; exit 1; }
  trap "hdiutil detach '$mount' -quiet >/dev/null 2>&1 || hdiutil detach '$mount' -force -quiet || true" EXIT
  local ok=1
  [[ -d "$mount/Nexus.app" ]] || { echo "Missing Nexus.app in $dmg"; ok=0; }
  [[ -L "$mount/Applications" && "$(readlink "$mount/Applications")" == /Applications ]] \
    || { echo "Missing Applications symlink in $dmg"; ok=0; }
  if [[ $ok == 0 ]]; then ls -la "$mount"; exit 1; fi
  echo "DMG check passed: $(basename "$dmg")"
}

case "${1:-}" in
  unit) unit ;;
  launch) launch ;;
  dmg) dmg ;;
  *) echo "usage: $0 unit|launch|dmg"; exit 2 ;;
esac
