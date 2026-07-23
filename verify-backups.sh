#!/usr/bin/env bash
# =============================================================================
#  verify-backups.sh — checks that your password decrypts the backups
# =============================================================================
#  Test-decrypts every *.gpg to /dev/null ONLY (writes NOTHING, overwrites
#  NOTHING). With the correct password, gpg also confirms the archive's
#  integrity (MDC). So BEFORE wiping the machine you know for sure:
#  password correct + backups readable.
#
#  USAGE:
#     chmod +x verify-backups.sh
#     ./verify-backups.sh                 # checks secrets-backup/ + browser-backup/
#     ./verify-backups.sh /Volumes/USB    # additionally search there
#
#  Note: a large browser archive (several GB) takes a while — it is read fully.
# =============================================================================

set -uo pipefail
export PATH="/opt/homebrew/bin:$PATH"

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRS=("$BASE/secrets-backup" "$BASE/browser-backup")
[ -n "${1:-}" ] && DIRS+=("$1" "$1/secrets-backup" "$1/browser-backup")

c_reset=$'\033[0m'; c_b=$'\033[1m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_c=$'\033[36m'
say(){ printf '%s\n' "$*"; }
command -v gpg >/dev/null || { say "${c_r}gpg missing.${c_reset}"; exit 1; }

# collect all .gpg files
files=()
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do files+=("$f"); done \
    < <(find "$d" -maxdepth 1 -type f -name '*.gpg' -print0 2>/dev/null)
done
[ "${#files[@]}" -gt 0 ] || { say "${c_y}No *.gpg backups found. Run the backup-*.sh scripts first.${c_reset}"; exit 1; }

say "${c_b}${c_c}Backup verification — ${#files[@]} file(s)${c_reset}"
read -rs -p "Backup password: " PP; echo
[ -n "$PP" ] || { say "${c_r}No password.${c_reset}"; exit 1; }

err="$(mktemp)"; trap 'rm -f "$err"' EXIT
ok=0; bad=0; wrongpw=0
for f in "${files[@]}"; do
  name="$(basename "$f")"; sz="$(du -h "$f" 2>/dev/null | cut -f1)"
  printf '  %-40s %6s  ' "$name" "$sz"
  if gpg --batch --pinentry-mode loopback --passphrase-fd 3 -d "$f" 3<<<"$PP" >/dev/null 2>"$err"; then
    say "${c_g}✓ OK (password correct, archive intact)${c_reset}"; ok=$((ok+1))
  else
    if grep -qiE 'bad session key|decryption failed|bad passphrase' "$err"; then
      say "${c_r}✗ WRONG PASSWORD${c_reset}"; wrongpw=$((wrongpw+1))
    else
      say "${c_r}✗ error/corrupted: $(tail -1 "$err")${c_reset}"; bad=$((bad+1))
    fi
  fi
done

say ""
if [ "$wrongpw" -gt 0 ]; then
  say "${c_r}${c_b}⚠ The password does NOT match (${wrongpw}×). Do NOT wipe the Mac until this is resolved!${c_reset}"
  exit 2
elif [ "$bad" -gt 0 ]; then
  say "${c_y}${c_b}⚠ Password correct, but ${bad} file(s) corrupted — re-create the backup.${c_reset}"; exit 3
else
  say "${c_g}${c_b}✓ All good: password correct, all ${ok} backups readable.${c_reset}"
fi
