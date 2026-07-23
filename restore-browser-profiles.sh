#!/usr/bin/env bash
# =============================================================================
#  restore-browser-profiles.sh — restore Edge/Chrome profiles
# =============================================================================
#  Counterpart to backup-browser-profiles.sh. Run on the NEW Mac, AFTER the
#  browser has been installed and started+quit ONCE (so the folder structure
#  and the keychain entry exist).
#
#  Order:
#    1) install the browser via restore.sh/Brewfile
#    2) start the browser once, then quit it completely (⌘Q)
#    3) run this script  →  enter the password
#    4) start the browser — profiles & logins are back
#
#  USAGE:
#     chmod +x restore-browser-profiles.sh
#     ./restore-browser-profiles.sh                 # source: ./browser-backup
#     ./restore-browser-profiles.sh /Volumes/USB    # source: external drive
# =============================================================================

set -uo pipefail

SRC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/browser-backup}"
APPSUP="$HOME/Library/Application Support"

# label | subfolder | keychain service | keychain account | process pattern (main binary)
BROWSERS=(
  "Edge|Microsoft Edge|Microsoft Edge Safe Storage|Microsoft Edge|Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  "Edge-Beta|Microsoft Edge Beta|Microsoft Edge Beta Safe Storage|Microsoft Edge Beta|Microsoft Edge Beta.app/Contents/MacOS/Microsoft Edge Beta"
  "Chrome|Google/Chrome|Chrome Safe Storage|Chrome|Google Chrome.app/Contents/MacOS/Google Chrome"
)

c_reset=$'\033[0m'; c_b=$'\033[1m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_c=$'\033[36m'
say(){ printf '%s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
have gpg || { say "${c_r}gpg missing — 'brew install gnupg'.${c_reset}"; exit 1; }
[ -d "$SRC" ] || { say "${c_r}Source not found: $SRC${c_reset}"; exit 1; }

say "${c_b}${c_c}Restoring browser profiles ← $SRC${c_reset}"
read -rs -p "Backup password: " PP; echo
[ -n "$PP" ] || { say "${c_r}No password — aborting.${c_reset}"; exit 1; }
gpg_dec(){ gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$1" 3<<<"$PP" 2>/dev/null; }

for entry in "${BROWSERS[@]}"; do
  IFS='|' read -r label sub svc acct procpat <<<"$entry"
  arc="$SRC/$label-profiles.tar.gz.gpg"
  [ -f "$arc" ] || { say "  ${c_y}– no backup for $label${c_reset}"; continue; }

  say "${c_b}==> $label${c_reset}"
  # browser (main process) quit?
  if pgrep -f "$procpat" >/dev/null 2>&1; then
    say "  ${c_y}! $label is running — please quit it COMPLETELY (⌘Q).${c_reset}"
    read -r -p "     quit? ENTER: " _ || true
  fi

  # 1) write the Safe Storage key back into the keychain (-U = update)
  if [ -f "$SRC/$label.safestorage.gpg" ]; then
    if key=$(gpg_dec "$SRC/$label.safestorage.gpg") && [ -n "$key" ]; then
      security add-generic-password -U -a "$acct" -s "$svc" -w "$key" 2>/dev/null \
        && say "  ${c_g}✓ Safe Storage key set in keychain${c_reset}" \
        || say "  ${c_y}! keychain update failed (confirm manually if prompted)${c_reset}"
    else say "  ${c_r}✗ key decryption failed (wrong password?)${c_reset}"; fi
  else
    say "  ${c_y}! no Safe Storage key in the backup — cookies/passwords may not be decryptable${c_reset}"
  fi

  # 2) set the existing profile aside, then unpack the backup
  dir="$APPSUP/$sub"
  if [ -d "$dir" ]; then
    bak="$dir.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$dir" "$bak" && say "  ${c_g}✓ previous profile → $(basename "$bak")${c_reset}"
  fi
  mkdir -p "$APPSUP"
  say "  … decrypting & unpacking profiles…"
  if gpg_dec "$arc" | gzip -d | tar -x -C "$APPSUP"; then
    say "  ${c_g}✓ $label restored${c_reset}"
  else
    say "  ${c_r}✗ unpacking failed — the previous profile is still at *.bak-*${c_reset}"
  fi
done

say ""
say "${c_g}${c_b}Done.${c_reset} Start the browsers now — profiles, cookies and logins should be back."
say "${c_y}Note:${c_reset} on first start you may need to confirm keychain access with your Mac password."
say "If anything is missing: the set-aside *.bak-* profile is still there."
