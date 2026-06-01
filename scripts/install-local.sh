#!/usr/bin/env bash
# install-local.sh — Build + install Nexus over the existing /Applications/Nexus.app.
#
# Replaces the running Electron build (or earlier Swift build) in-place. Bundle id
# stays `site.easonsi.nexus`, so the user's Accessibility / Notification grants
# are preserved across the swap.
#
# Usage:
#   ./scripts/install-local.sh             # build then install
#   ./scripts/install-local.sh --skip-build  # if you just ran build-mac.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "${1:-}" != "--skip-build" ]]; then
  "$SCRIPT_DIR/build-mac.sh"
fi

# Locate freshly-built DMG (most recent in dist/)
DMG=$(ls -t "$PROJECT_DIR/dist"/*.dmg 2>/dev/null | head -1)
[[ -n "${DMG:-}" && -f "$DMG" ]] || { echo "No DMG in dist/. Run build-mac.sh first."; exit 1; }
echo "==> Installing from $DMG"

# Mount the DMG read-only.
# hdiutil's plain output is multiline with tab-separated columns; the mount
# path is the 3rd column on whichever row has it (volumes can have spaces in
# their name, so we extract via -plist instead of awk).
echo "==> Mounting $(basename "$DMG")"
MOUNT_OUTPUT=$(hdiutil attach "$DMG" -nobrowse -plist 2>/dev/null)
MOUNT=$(echo "$MOUNT_OUTPUT" | python3 -c '
import plistlib, sys
data = plistlib.loads(sys.stdin.buffer.read())
for entity in data.get("system-entities", []):
    if "mount-point" in entity:
        print(entity["mount-point"])
        break
')
[[ -n "$MOUNT" && -d "$MOUNT" ]] || { echo "Could not determine mount point"; exit 1; }
trap 'hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true' EXIT
SRC="$MOUNT/Nexus.app"
[[ -d "$SRC" ]] || { echo "Mounted DMG missing Nexus.app at $SRC"; ls "$MOUNT"; exit 1; }

# Quit any running Nexus first — `cp -R` over a running .app bundle on the
# same volume can succeed but leave the running process pointing at orphaned
# pages; quitting first is the safe path.
#
# We match BOTH the installed bundle AND the Xcode DerivedData debug build,
# because if you previously ran `cmd-R` in Xcode, that process is still alive
# in the menu bar and steals the bundle id slot from the freshly-installed
# Release build (same `site.easonsi.nexus` ⇒ second instance silently exits).
echo "==> Quitting running Nexus (if any)"
pkill -f "/Applications/Nexus.app/Contents/MacOS/Nexus" 2>/dev/null || true
pkill -f "DerivedData/Nexus-.*/Build/Products/.*/Nexus.app/Contents/MacOS/Nexus" 2>/dev/null || true
# Wait briefly for graceful exit
for _ in 1 2 3 4 5; do
  pgrep -f "Nexus.app/Contents/MacOS/Nexus" >/dev/null 2>&1 || break
  sleep 0.3
done
# If something's still running, it's almost certainly an Xcode debug session
# holding the process under lldb. Warn explicitly — kill -9 won't work there.
if pgrep -f "DerivedData/Nexus-.*/Build/Products/.*/Nexus.app/Contents/MacOS/Nexus" >/dev/null 2>&1; then
  echo ""
  echo "⚠️  An Xcode-launched Debug build of Nexus is still running and lldb is"
  echo "    holding it. The /Applications/Nexus.app you just installed will not"
  echo "    take over the menu bar slot until you stop the Xcode session."
  echo "    → In Xcode, press ⌘. (or Product → Stop), then re-run this script."
  echo ""
fi

# Replace the bundle.
DEST="/Applications/Nexus.app"
if [[ -d "$DEST" ]]; then
  echo "==> Removing existing $DEST"
  rm -rf "$DEST"
fi
echo "==> Copying $SRC → $DEST"
cp -R "$SRC" "$DEST"

# Strip quarantine — for ad-hoc signed apps Gatekeeper otherwise blocks first launch.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Detach DMG
hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
trap - EXIT

# Launch
echo "==> Launching"
open "$DEST"

echo ""
echo "  ✓ Installed: $DEST"
echo "  ✓ App size:  $(du -sh "$DEST" | awk '{print $1}')"
echo ""
echo "Tip: Tracker may need re-grant Accessibility in System Settings since the binary"
echo "     hash differs from the previous Electron build (same bundle id, but TCC also"
echo "     keys on signing identity). Click the menu bar icon → see if the popover"
echo "     loads, then check Settings → Tracker for any banner."
