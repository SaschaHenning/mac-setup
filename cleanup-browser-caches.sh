#!/usr/bin/env bash
# =============================================================================
#  cleanup-browser-caches.sh — delete ONLY the caches of Edge/Chrome (safe)
# =============================================================================
#  Deletes exclusively regenerable cache directories (HTTP cache, code/GPU/
#  shader caches, service-worker CacheStorage, Crashpad). NEVER deletes:
#  cookies, Login Data, passwords, local/session storage, IndexedDB, Network/,
#  preferences, bookmarks, history, extensions, profiles.
#  The browser rebuilds the caches on its next start.
#
#  ⚠ Affected browsers must be QUIT (⌘Q) — running ones are skipped.
#
#  USAGE:
#     ./cleanup-browser-caches.sh            # deletes caches
#     ./cleanup-browser-caches.sh --dry-run  # only shows what would be freed
# =============================================================================

set -uo pipefail
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

APPSUP="$HOME/Library/Application Support"
# subfolder | precise process pattern (app binary path)
BROWSERS=(
  "Microsoft Edge|Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  "Microsoft Edge Beta|Microsoft Edge Beta.app/Contents/MacOS/Microsoft Edge Beta"
  "Google/Chrome|Google Chrome.app/Contents/MacOS/Google Chrome"
)
# Only directories with these NAMES are deleted (anywhere in the browser tree):
CACHE_NAMES=(Cache "Code Cache" GPUCache DawnCache DawnGraphiteCache DawnWebGPUCache
  GraphiteDawnCache GrShaderCache ShaderCache CacheStorage ScriptCache
  "Cache Storage" "Application Cache" component_crx_cache extensions_crx_cache Crashpad)

c_reset=$'\033[0m'; c_b=$'\033[1m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_c=$'\033[36m'
say(){ printf '%s\n' "$*"; }
kb2h(){ awk -v k="$1" 'BEGIN{u="KB";v=k; if(v>1048576){v/=1048576;u="GB"}else if(v>1024){v/=1024;u="MB"} printf "%.1f %s",v,u}'; }

lbl=""; [ "$DRY" -eq 1 ] && lbl="  (DRY-RUN)"
say "${c_b}${c_c}Cleaning up browser caches${lbl}${c_reset}"
grand=0
for entry in "${BROWSERS[@]}"; do
  IFS='|' read -r sub proc <<<"$entry"
  dir="$APPSUP/$sub"; [ -d "$dir" ] || continue
  if pgrep -f "$proc" >/dev/null 2>&1; then
    say "  ${c_y}⏭  $sub is running — skipped (please ⌘Q and retry)${c_reset}"; continue
  fi
  # find matching cache dirs (whitespace-safe, bash-3.2 compatible)
  args=(); for n in "${CACHE_NAMES[@]}"; do args+=(-o -name "$n"); done
  dirs=()
  while IFS= read -r -d '' p; do dirs+=("$p"); done \
    < <(find "$dir" -type d \( "${args[@]:1}" \) -prune -print0 2>/dev/null)
  [ "${#dirs[@]}" -eq 0 ] && { say "  ${c_g}✓ $sub: nothing to delete${c_reset}"; continue; }
  sz=$(du -sk "${dirs[@]}" 2>/dev/null | awk '{s+=$1} END{print s+0}')
  grand=$((grand+sz))
  say "  ${c_b}$sub${c_reset}: ${#dirs[@]} cache folder(s), $(kb2h "$sz")"
  if [ "$DRY" -eq 0 ]; then
    rm -rf "${dirs[@]}" 2>/dev/null && say "    ${c_g}✓ deleted${c_reset}" || say "    ${c_y}! partially not deletable${c_reset}"
  fi
done
say ""
if [ "$DRY" -eq 1 ]; then say "${c_b}Would free: $(kb2h "$grand")${c_reset} (nothing deleted — run again without --dry-run)"
else say "${c_g}${c_b}Freed: ~$(kb2h "$grand")${c_reset}. Caches are rebuilt on the next browser start."; fi
