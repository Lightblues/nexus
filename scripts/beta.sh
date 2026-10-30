#!/usr/bin/env bash
# beta.sh — Run the rolling beta of Nexus (every push to main, SADR-018) on this Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/Lightblues/nexus/main/scripts/beta.sh | bash -s install
#
#   install     switch the cask to nexus@beta (data is kept) and install a launchd job
#               that runs `update` every 10 minutes
#   update      if the tap has a newer beta: quit Nexus, upgrade, relaunch
#   uninstall   remove the launchd job and go back to the stable cask

set -euo pipefail

LABEL="site.easonsi.nexus.beta-update"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
HOME_DIR="$HOME/Library/Application Support/site.easonsi.nexus"
SELF="$HOME_DIR/beta.sh"
LOG="$HOME/Library/Logs/site.easonsi.nexus/beta-update.log"
SCRIPT_URL="https://raw.githubusercontent.com/Lightblues/nexus/main/scripts/beta.sh"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
  HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
installed() { brew list --cask "$1" >/dev/null 2>&1; }
running() { pgrep -f "/Applications/Nexus.app/Contents/MacOS/Nexus" >/dev/null; }

quit_app() {
  running || return 0
  osascript -e 'quit app id "site.easonsi.nexus"' >/dev/null 2>&1 || true
  for _ in $(seq 20); do running || return 0; sleep 0.5; done
  pkill -f "/Applications/Nexus.app/Contents/MacOS/Nexus" || true
}

install() {
  brew tap lightblues/tap >/dev/null
  git -C "$(brew --repository lightblues/tap)" pull -q
  local was_running=0; running && was_running=1
  if installed nexus; then quit_app; brew uninstall --cask nexus; fi
  if ! installed nexus@beta; then quit_app; brew install --cask lightblues/tap/nexus@beta
  elif [[ ! -d /Applications/Nexus.app ]]; then brew reinstall --cask nexus@beta
  else brew upgrade --cask nexus@beta || true; fi

  mkdir -p "$HOME_DIR" "$(dirname "$LOG")" "$(dirname "$AGENT")"
  if [[ -f "${BASH_SOURCE[0]:-}" ]]; then cp "${BASH_SOURCE[0]}" "$SELF"
  else curl -fsSL --retry 3 --retry-all-errors "$SCRIPT_URL" -o "$SELF"; fi
  chmod 755 "$SELF"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>update</string></array>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
  [[ $was_running == 1 ]] && ! running && open -a /Applications/Nexus.app
  log "beta channel on: $(brew list --cask --versions nexus@beta); updates every 10 min, log $LOG"
}

update() {
  installed nexus@beta || { log "nexus@beta not installed"; exit 0; }
  git -C "$(brew --repository lightblues/tap)" pull -q
  if [[ ! -d /Applications/Nexus.app ]]; then
    log "Nexus.app missing; reinstalling"; brew reinstall --cask nexus@beta || log "brew reinstall exited $?"; exit 0
  fi
  [[ -n "$(brew outdated --cask --quiet nexus@beta)" ]] || exit 0
  local was_running=0; running && was_running=1
  log "upgrading $(brew list --cask --versions nexus@beta)"
  quit_app
  # Relaunch even when brew exits non-zero for something unrelated to the cask.
  brew upgrade --cask nexus@beta || log "brew upgrade exited $?"
  [[ $was_running == 1 ]] && open -a /Applications/Nexus.app
  log "now $(brew list --cask --versions nexus@beta)"
}

uninstall() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$AGENT" "$SELF"
  if installed nexus@beta; then quit_app; brew uninstall --cask nexus@beta; brew install --cask lightblues/tap/nexus; fi
  log "back on the stable cask"
}

case "${1:-}" in
  install) install ;;
  update) update ;;
  uninstall) uninstall ;;
  *) echo "usage: $0 install|update|uninstall"; exit 2 ;;
esac
