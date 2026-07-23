#!/usr/bin/env bash
# =============================================================================
#  backup-browser-profiles.sh — back up Edge/Chrome profiles ENCRYPTED
# =============================================================================
#  ⚠️  Run this NOW — BEFORE reinstalling!  Otherwise active logins/cookies/
#      passwords are gone for good. (Browser sync only covers bookmarks/
#      passwords, NOT the active session cookies.)
#
#  Per browser this backs up:
#    • all profiles (cookies, Login Data, local/session storage, IndexedDB,
#      extensions, preferences, bookmarks) — WITHOUT the fat HTTP caches
#    • the "… Safe Storage" keychain key (without it, cookies/passwords cannot
#      be decrypted on the new Mac)
#  Everything is encrypted with GPG (AES256) + ONE password. Store the password
#  in your password manager afterwards!  Without it the backup is worthless.
#
#  USAGE:
#     chmod +x backup-browser-profiles.sh
#     ./backup-browser-profiles.sh                 # target: the folder next to this script
#     ./backup-browser-profiles.sh /Volumes/USB    # target: external drive (recommended for large profiles, can be several GB)
# =============================================================================

set -uo pipefail

DEST="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/browser-backup}"
mkdir -p "$DEST"

# label | subfolder in Application Support | keychain service | keychain account | process pattern (main binary, not widgets/helpers)
BROWSERS=(
  "Edge|Microsoft Edge|Microsoft Edge Safe Storage|Microsoft Edge|Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  "Edge-Beta|Microsoft Edge Beta|Microsoft Edge Beta Safe Storage|Microsoft Edge Beta|Microsoft Edge Beta.app/Contents/MacOS/Microsoft Edge Beta"
  "Chrome|Google/Chrome|Chrome Safe Storage|Chrome|Google Chrome.app/Contents/MacOS/Google Chrome"
)

APPSUP="$HOME/Library/Application Support"
EXCLUDES=(
  --exclude='*/Cache' --exclude='*/Cache/*'
  --exclude='*/Code Cache' --exclude='*/Code Cache/*'
  --exclude='*/GPUCache' --exclude='*/GrShaderCache' --exclude='*/ShaderCache'
  --exclude='*/DawnCache' --exclude='*/DawnGraphiteCache' --exclude='*/DawnWebGPUCache' --exclude='*/GraphiteDawnCache'
  --exclude='*/Service Worker/CacheStorage' --exclude='*/Service Worker/CacheStorage/*'
  --exclude='*/Service Worker/ScriptCache' --exclude='*/Service Worker/ScriptCache/*'
  --exclude='*/Cache Storage' --exclude='*/Application Cache'
  --exclude='*/component_crx_cache' --exclude='*/extensions_crx_cache'
  --exclude='*Crashpad*' --exclude='*/blob_storage'
)

c_reset=$'\033[0m'; c_b=$'\033[1m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_c=$'\033[36m'
say(){ printf '%s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
have gpg || { say "${c_r}gpg missing — 'brew install gnupg' and retry.${c_reset}"; exit 1; }

say "${c_b}${c_c}Backing up browser profiles → $DEST${c_reset}"

# --- ask for the password ONCE -----------------------------------------------
say "${c_y}Choose a strong encryption password (then store it in your password manager!).${c_reset}"
read -rs -p "Password: " PP; echo
read -rs -p "Repeat password: " PP2; echo
[ -n "$PP" ] && [ "$PP" = "$PP2" ] || { say "${c_r}Passwords empty/mismatch — aborting.${c_reset}"; exit 1; }

MANIFEST="$DEST/backup-manifest.txt"
{ echo "# Browser profile backup — $(date '+%Y-%m-%d %H:%M')"; echo "# Host: $(hostname)"; } > "$MANIFEST"

for entry in "${BROWSERS[@]}"; do
  IFS='|' read -r label sub svc acct procpat <<<"$entry"
  dir="$APPSUP/$sub"
  [ -d "$dir" ] || { say "  ${c_y}– $label not present, skipped${c_reset}"; continue; }

  # is the browser (main process) still running? — widgets/helpers do not count
  if pgrep -f "$procpat" >/dev/null 2>&1; then
    say "  ${c_y}! $label is still running — please quit it COMPLETELY (⌘Q).${c_reset}"
    read -r -p "     quit? ENTER (or Ctrl-C): " _ || true
  fi

  say "${c_b}==> $label${c_reset}  ($(du -sh "$dir" 2>/dev/null | cut -f1) incl. cache)"

  # 1) back up the keychain Safe Storage key
  if key=$(security find-generic-password -w -s "$svc" -a "$acct" 2>/dev/null) && [ -n "$key" ]; then
    printf '%s' "$key" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
        --symmetric --cipher-algo AES256 -o "$DEST/$label.safestorage.gpg" 3<<<"$PP"
    say "  ${c_g}✓ Safe Storage key backed up${c_reset}"
  else
    say "  ${c_y}! Safe Storage key not readable (keychain prompt denied?) — cookies/passwords may not be decryptable later${c_reset}"
  fi

  # 2) profiles (without caches) → gzip → gpg
  out="$DEST/$label-profiles.tar.gz.gpg"
  say "  … packing & encrypting profiles (can take a while) → $(basename "$out")"
  if COPYFILE_DISABLE=1 tar -c "${EXCLUDES[@]}" -C "$APPSUP" "$sub" 2>/dev/null | gzip \
       | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
             --symmetric --cipher-algo AES256 -o "$out" 3<<<"$PP"; then
    say "  ${c_g}✓ $(du -sh "$out" 2>/dev/null | cut -f1) → $out${c_reset}"
  else
    say "  ${c_r}✗ packing $label failed${c_reset}"
  fi

  # manifest (profile names only, no passwords/cookies)
  { echo ""; echo "## $label ($sub)";
    python3 - "$dir/Local State" <<'PY' 2>/dev/null || true
import json,sys
try:
    ic=json.load(open(sys.argv[1])).get("profile",{}).get("info_cache",{})
    for k,v in sorted(ic.items()):
        print(f"  {k:12} {v.get('name','?')}")
except Exception: pass
PY
  } >> "$MANIFEST"
done

say ""
say "${c_g}${c_b}Done.${c_reset} Files in: $DEST"
ls -lh "$DEST" 2>/dev/null | awk 'NR>1{print "  "$5"  "$9}'
say ""
say "${c_y}➜ Store the password in your password manager NOW (e.g. 'Browser backup GPG').${c_reset}"
say "${c_y}➜ If the folder syncs to cloud storage: make sure the uploads have finished BEFORE wiping the Mac${c_reset}"
say "   (Finder → the folder must no longer show cloud-with-arrow icons)."
say "➜ Restore later with:  ./restore-browser-profiles.sh"
