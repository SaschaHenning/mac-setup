#!/usr/bin/env bash
# =============================================================================
#  restore-secrets.sh — restore SSH keys, GPG key & dev credentials
# =============================================================================
#  Counterpart to backup-secrets.sh. Run on the NEW Mac.
#  Sets correct SSH file permissions and imports the GPG key via the portable
#  armored export (more reliable than the raw ~/.gnupg directory).
#
#  Afterwards, restore your password store: with the GPG key imported, a
#  git-synced password store (e.g. pass/gopass) just needs to be cloned again —
#  the imported key decrypts it.
#
#  USAGE:
#     chmod +x restore-secrets.sh
#     ./restore-secrets.sh                 # source: ./secrets-backup
#     ./restore-secrets.sh /Volumes/USB    # source: external drive
# =============================================================================

set -uo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

SRC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/secrets-backup}"
c_reset=$'\033[0m'; c_b=$'\033[1m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_c=$'\033[36m'
say(){ printf '%s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
have gpg || { say "${c_r}gpg missing — 'brew install gnupg'.${c_reset}"; exit 1; }
[ -d "$SRC" ] || { say "${c_r}Source not found: $SRC${c_reset}"; exit 1; }

arc="$(ls -t "$SRC"/secrets-*.tar.gz.gpg 2>/dev/null | head -1)"
[ -n "$arc" ] || { say "${c_r}No secrets-*.tar.gz.gpg in $SRC${c_reset}"; exit 1; }
say "${c_b}${c_c}Restoring secrets ← $(basename "$arc")${c_reset}"
read -rs -p "Backup password: " PP; echo
[ -n "$PP" ] || { say "${c_r}No password — aborting.${c_reset}"; exit 1; }

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT; chmod 700 "$STAGE"
say "  … decrypting & unpacking…"
if ! gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -d "$arc" 3<<<"$PP" 2>/dev/null \
      | gzip -d | tar -x -C "$STAGE"; then
  say "${c_r}✗ decryption failed (wrong password?)${c_reset}"; exit 1
fi
say "  ${c_g}✓ unpacked${c_reset}"

# --- 1) import the GPG key (the most important step) -------------------------
if [ -f "$STAGE/gpg-secret-keys.asc" ]; then
  gpg --import "$STAGE/gpg-public-keys.asc" 2>/dev/null || true
  if gpg --batch --import "$STAGE/gpg-secret-keys.asc" 2>/dev/null; then
    [ -f "$STAGE/gpg-ownertrust.txt" ] && gpg --import-ownertrust "$STAGE/gpg-ownertrust.txt" 2>/dev/null || true
    say "  ${c_g}✓ GPG key imported${c_reset}  ($(gpg --list-secret-keys --keyid-format=long 2>/dev/null | awk '/^sec/{print $2}' | head -1))"
  else say "  ${c_r}✗ GPG import failed${c_reset}"; fi
else say "  ${c_y}! no GPG export in the backup${c_reset}"; fi

# --- 2) SSH keys with correct permissions ------------------------------------
if [ -d "$STAGE/.ssh" ]; then
  if [ -d "$HOME/.ssh" ] && [ -n "$(ls -A "$HOME/.ssh" 2>/dev/null)" ]; then
    bak="$HOME/.ssh.bak-$(date +%Y%m%d-%H%M%S)"; cp -a "$HOME/.ssh" "$bak"
    say "  ${c_y}! existing ~/.ssh backed up → $(basename "$bak")${c_reset}"
  fi
  mkdir -p "$HOME/.ssh"
  cp -a "$STAGE/.ssh/." "$HOME/.ssh/"
  chmod 700 "$HOME/.ssh"
  find "$HOME/.ssh" -type f -exec chmod 600 {} \;
  find "$HOME/.ssh" -type f -name '*.pub' -exec chmod 644 {} \;
  say "  ${c_g}✓ ~/.ssh restored ($(find "$HOME/.ssh" -type f | wc -l | tr -d ' ') files, permissions set)${c_reset}"
fi

# --- 3) optional raw ~/.gnupg copy (only if the import above was not enough) --
if [ -d "$STAGE/.gnupg" ] && [ ! -s "$HOME/.gnupg/pubring.kbx" ]; then
  mkdir -p "$HOME/.gnupg"; cp -a "$STAGE/.gnupg/." "$HOME/.gnupg/" 2>/dev/null || true
  chmod 700 "$HOME/.gnupg"; find "$HOME/.gnupg" -type f -exec chmod 600 {} \; 2>/dev/null || true
  say "  ${c_g}✓ ~/.gnupg directory copied${c_reset}"
fi

# --- 4) other dev logins ------------------------------------------------------
restore_path(){ # $1 = path relative to STAGE/HOME
  local rel="$1" s="$STAGE/$1" d="$HOME/$1"
  [ -e "$s" ] || return 0
  mkdir -p "$(dirname "$d")"
  [ -e "$d" ] && cp -a "$d" "$d.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  cp -a "$s" "$d" && say "  ${c_g}✓ $rel${c_reset}"
}
for p in ".config/gh" ".codex/auth.json" ".claude.json" ".aws" ".azure" ".oci" \
         ".config/gcloud" ".npmrc" ".docker/config.json" ".kube/config" \
         "Library/Application Support/Tunnelblick/Configurations"; do
  restore_path "$p"
done

# WireGuard configs go to a safe place (import into the WireGuard app manually)
if [ -d "$STAGE/wireguard" ]; then
  wgdst="$HOME/Documents/WireGuard-Configs"; mkdir -p "$wgdst"
  cp -a "$STAGE/wireguard/." "$wgdst/" 2>/dev/null || true
  chmod 600 "$wgdst"/* 2>/dev/null || true
  say "  ${c_g}✓ WireGuard configs → $wgdst${c_reset} (import into the WireGuard app)"
fi

say ""
say "${c_g}${c_b}Done.${c_reset}"
say "Next steps:"
say "   Restore your password store — with the GPG key imported, cloning your"
say "   git-synced store (e.g. pass/gopass) is enough; the key decrypts it."
say "Test SSH:  ${c_c}ssh -T git@github.com${c_reset}"
