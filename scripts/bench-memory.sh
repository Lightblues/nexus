#!/usr/bin/env bash
# bench-memory.sh — Snapshot macOS process memory using the same fields
# Activity Monitor uses (Physical footprint), not the misleading RSS.
#
# Usage:
#   ./scripts/bench-memory.sh                 # auto-finds running Nexus.app(s) + Electron variant
#   ./scripts/bench-memory.sh <pid> [pid...]  # explicit pids
#   ./scripts/bench-memory.sh --launch /path/to/Nexus.app
#                                             # launch, wait, measure, kill
#   ./scripts/bench-memory.sh --compare       # bench Swift Release + installed Electron side by side
#
# Why footprint not RSS?
#   RSS counts read-only library pages shared with every other app on the
#   system (SwiftUI, AppKit, libsystem...). That's not "Nexus's cost". The
#   `Physical footprint` field in vmmap excludes shared mappings — it's what
#   Activity Monitor reports and what Apple uses to size apps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ANSI colors (skip if not a tty)
if [[ -t 1 ]]; then
  BOLD='\033[1m'; DIM='\033[2m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; RESET='\033[0m'
else
  BOLD=''; DIM=''; GREEN=''; YELLOW=''; CYAN=''; RESET=''
fi

# -------- helpers --------

human_kb() {
  # Input: KB (integer). Output: "12 MB" / "1.2 GB"
  awk -v k="$1" 'BEGIN {
    if (k >= 1024*1024) printf "%.1f GB", k/1024/1024
    else if (k >= 1024) printf "%.1f MB", k/1024
    else printf "%d KB", k
  }'
}

# Parse "60.0M" / "1.2G" / "204K" → KB integer
parse_vmmap_size() {
  awk -v s="$1" 'BEGIN {
    n = s + 0
    if (s ~ /[Gg]/) printf "%d", n*1024*1024
    else if (s ~ /[Mm]/) printf "%d", n*1024
    else if (s ~ /[Kk]/) printf "%d", n
    else printf "%d", n/1024  # bytes
  }'
}

# vmmap --summary <pid> → footprint_kb peak_kb
read_footprint() {
  local pid="$1"
  local out
  out=$(/usr/bin/vmmap --summary "$pid" 2>/dev/null) || return 1
  local fp peak
  fp=$(echo "$out" | awk '/^Physical footprint:/ {print $3; exit}')
  peak=$(echo "$out" | awk '/^Physical footprint \(peak\):/ {print $4; exit}')
  if [[ -z "$fp" ]]; then return 1; fi
  echo "$(parse_vmmap_size "$fp") $(parse_vmmap_size "${peak:-$fp}")"
}

# ps for a pid → "rss_kb cpu_pct elapsed comm"
read_ps() {
  local pid="$1"
  ps -o rss=,%cpu=,etime=,comm= -p "$pid" 2>/dev/null | awk '{
    rss=$1; cpu=$2; etime=$3
    $1=$2=$3=""; sub(/^ +/,""); print rss, cpu, etime, $0
  }'
}

bench_pid() {
  local pid="$1"
  local label="${2:-pid $pid}"

  if ! kill -0 "$pid" 2>/dev/null; then
    printf "${YELLOW}skip${RESET}  %s (pid %s not running)\n" "$label" "$pid"
    return
  fi

  local ps_line; ps_line=$(read_ps "$pid") || { echo "skip $label (ps failed)"; return; }
  local rss_kb cpu etime comm
  read -r rss_kb cpu etime comm <<< "$ps_line"

  local fp_line; fp_line=$(read_footprint "$pid" || true)
  local fp_kb peak_kb
  if [[ -n "$fp_line" ]]; then
    read -r fp_kb peak_kb <<< "$fp_line"
  else
    fp_kb="?"; peak_kb="?"
  fi

  printf "  ${CYAN}%-8s${RESET} pid=%s  comm=%s\n" "$label" "$pid" "$(basename "$comm")"
  printf "    footprint     ${GREEN}${BOLD}%s${RESET}  ${DIM}(peak %s)${RESET}\n" \
    "$([[ $fp_kb == ? ]] && echo "?" || human_kb "$fp_kb")" \
    "$([[ $peak_kb == ? ]] && echo "?" || human_kb "$peak_kb")"
  printf "    rss           %s  ${DIM}(includes shared lib pages — overstates cost)${RESET}\n" \
    "$(human_kb "$rss_kb")"
  printf "    cpu           %s%%   uptime  %s\n" "$cpu" "$etime"
  echo
  # Echo machine-readable line on fd 3 if available (used by aggregate)
  if { true >&3; } 2>/dev/null; then
    echo "$label $pid $fp_kb $peak_kb $rss_kb $cpu" >&3
  fi
}

bundle_size() {
  local app="$1"
  if [[ ! -d "$app" ]]; then echo "(missing)"; return; fi
  du -sh "$app" 2>/dev/null | awk '{print $1}'
}

# Sum footprints across pids (KB) — for multi-process apps like Electron
sum_footprints() {
  local total=0
  for pid in "$@"; do
    local fp_line; fp_line=$(read_footprint "$pid" || true)
    if [[ -n "$fp_line" ]]; then
      local fp_kb _peak
      read -r fp_kb _peak <<< "$fp_line"
      total=$((total + fp_kb))
    fi
  done
  echo "$total"
}

# -------- modes --------

mode_auto() {
  echo -e "${BOLD}== Nexus memory benchmark ==${RESET}"
  echo

  # Swift Nexus: any running binary inside Nexus.app whose path looks like ours.
  local swift_pids
  swift_pids=$(pgrep -f "Nexus.app/Contents/MacOS/Nexus" || true)
  swift_pids=$(echo "$swift_pids" | grep -v "Helper" || true)

  local electron_pids
  # Electron version exposes a "Nexus Helper" pattern, single MacOS/Nexus + helpers.
  electron_pids=$(pgrep -f "/Applications/Nexus.app" || true)

  if [[ -z "$swift_pids" && -z "$electron_pids" ]]; then
    echo -e "${YELLOW}No Nexus processes running.${RESET}"
    echo "Hint: launch from Xcode (⌘R) or pass --launch /path/to/Nexus.app"
    return 1
  fi

  if [[ -n "$swift_pids" ]]; then
    echo -e "${BOLD}Swift Nexus${RESET}"
    while read -r pid; do
      [[ -z "$pid" ]] && continue
      bench_pid "$pid" "swift"
    done <<< "$swift_pids"
  fi

  if [[ -n "$electron_pids" ]]; then
    echo -e "${BOLD}Electron Nexus${RESET}  ${DIM}(installed in /Applications)${RESET}"
    local main_pid
    main_pid=$(echo "$electron_pids" | head -n1)
    bench_pid "$main_pid" "main"
    # Also gather helpers, summarised
    local helpers
    helpers=$(pgrep -f "Nexus Helper" || true)
    if [[ -n "$helpers" ]]; then
      while read -r pid; do
        [[ -z "$pid" ]] && continue
        local kind
        kind=$(ps -p "$pid" -o command= 2>/dev/null | grep -oE 'Renderer|GPU|Plugin|Network|Helper' | head -n1)
        bench_pid "$pid" "$(echo "${kind:-helper}" | tr '[:upper:]' '[:lower:]')"
      done <<< "$helpers"
      local total
      total=$(sum_footprints $electron_pids $helpers)
      echo -e "    ${BOLD}total footprint  $(human_kb "$total")${RESET}  (sum across $((1+$(echo "$helpers" | wc -l | tr -d ' '))) processes)"
      echo
    fi
  fi
}

mode_launch() {
  local app="$1"
  if [[ ! -d "$app" ]]; then
    echo "Error: app not found: $app" >&2; exit 2
  fi
  local bin="$app/Contents/MacOS/$(basename "$app" .app)"
  if [[ ! -x "$bin" ]]; then
    echo "Error: missing executable inside bundle: $bin" >&2; exit 2
  fi
  echo -e "${BOLD}Launching${RESET} $app"
  "$bin" >/tmp/nexus-bench.log 2>&1 &
  local pid=$!
  trap "kill $pid 2>/dev/null || true" EXIT
  echo "  pid=$pid  warming up 5s..."
  sleep 5
  echo "  bundle    $(bundle_size "$app")"
  echo
  bench_pid "$pid" "launched"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  trap - EXIT
}

mode_compare() {
  echo -e "${BOLD}== Side-by-side: Swift Release vs Electron ==${RESET}"
  echo

  # 1. Build Swift Release if not already
  local rel="/tmp/nexus-release/Build/Products/Release/Nexus.app"
  if [[ ! -d "$rel" ]]; then
    echo "Building Swift Release..."
    (cd "$PROJECT_DIR" && xcodebuild -project Nexus.xcodeproj -scheme Nexus \
        -configuration Release -destination 'platform=macOS' \
        -derivedDataPath /tmp/nexus-release build) >/dev/null
  fi
  echo -e "${BOLD}Swift Nexus (Release)${RESET}"
  echo "  bundle    $(bundle_size "$rel")"
  echo
  local bin="$rel/Contents/MacOS/Nexus"
  "$bin" >/tmp/nexus-bench-swift.log 2>&1 &
  local sp=$!
  trap "kill $sp 2>/dev/null || true" EXIT
  sleep 5
  bench_pid "$sp" "swift"
  kill "$sp" 2>/dev/null || true
  wait "$sp" 2>/dev/null || true
  trap - EXIT
  echo

  # 2. Electron — only if installed and currently running.
  if [[ -d /Applications/Nexus.app ]] && pgrep -fq "/Applications/Nexus.app/Contents/MacOS/Nexus"; then
    echo -e "${BOLD}Electron Nexus (currently running)${RESET}"
    echo "  bundle    $(bundle_size /Applications/Nexus.app)"
    echo
    mode_auto_electron_only
  else
    echo -e "${DIM}Electron Nexus not running — skip. Install + launch /Applications/Nexus.app to compare.${RESET}"
  fi
}

mode_auto_electron_only() {
  local main_pid; main_pid=$(pgrep -f "/Applications/Nexus.app/Contents/MacOS/Nexus" | head -n1)
  bench_pid "$main_pid" "main"
  local helpers; helpers=$(pgrep -f "Nexus Helper" || true)
  if [[ -n "$helpers" ]]; then
    while read -r pid; do
      [[ -z "$pid" ]] && continue
      local kind; kind=$(ps -p "$pid" -o command= 2>/dev/null | grep -oE 'Renderer|GPU|Plugin|Network' | head -n1)
      bench_pid "$pid" "$(echo "${kind:-helper}" | tr '[:upper:]' '[:lower:]')"
    done <<< "$helpers"
    local total; total=$(sum_footprints $main_pid $helpers)
    echo -e "    ${BOLD}total footprint  $(human_kb "$total")${RESET}"
  fi
}

# -------- entrypoint --------

case "${1:-}" in
  --launch)
    [[ -z "${2:-}" ]] && { echo "usage: $0 --launch /path/to/Nexus.app" >&2; exit 1; }
    mode_launch "$2"
    ;;
  --compare)
    mode_compare
    ;;
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# *//'
    ;;
  "")
    mode_auto
    ;;
  *)
    # Treat as explicit pid list
    echo -e "${BOLD}== Nexus memory benchmark ==${RESET}\n"
    for pid in "$@"; do
      bench_pid "$pid"
    done
    ;;
esac
