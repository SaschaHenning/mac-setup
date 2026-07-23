#!/usr/bin/env bash
# =============================================================================
#  backup-secrets.sh — back up SSH keys, GPG key & dev credentials ENCRYPTED
# =============================================================================
#  ⚠️  Run this NOW — BEFORE wiping the machine!  SSH private keys and your
#      GPG key are UNRECOVERABLE once the Mac is reinstalled.
#      Your GPG key also decrypts your password store — without it a
#      (git-synced) password store is worthless.
#
#  Backs up (encrypted with GPG AES256 + ONE password):
#     • ~/.ssh            (all private/public keys, config, known_hosts)
#     • ~/.gnupg          + a portable armored secret-key export + ownertrust
#     • optional dev logins (gh, codex, aws, azure, npm, docker, kube) —
#       convenient, but you could also just log in again
#
#  USAGE:
#     chmod +x backup-secrets.sh
#     ./backup-secrets.sh                 # target: the folder next to this script
#     ./backup-secrets.sh /Volumes/USB    # target: external drive (even safer)
# =============================================================================

set -uo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

DEST="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/secrets-backup}"
mkdir -p "$DEST"; chmod 700 "$DEST"

c_reset=$'\033[0m'; c_b=$'\033[1m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_c=$'\033[36m'
say(){ printf '%s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
have gpg || { say "${c_r}gpg missing — 'brew install gnupg'.${c_reset}"; exit 1; }

say "${c_b}${c_c}Backing up secrets → $DEST${c_reset}"
say "${c_y}Choose a strong password (then store it in your password manager!). Without it the backup is worthless.${c_reset}"
read -rs -p "Password: " PP; echo
read -rs -p "Repeat password: " PP2; echo
[ -n "$PP" ] && [ "$PP" = "$PP2" ] || { say "${c_r}Passwords empty/mismatch — aborting.${c_reset}"; exit 1; }
enc(){ gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 --symmetric --cipher-algo AES256 -o "$1" 3<<<"$PP"; }

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
chmod 700 "$STAGE"

# --- 1) portable GPG export (the most reliable restore path) ------------------
if gpg --list-secret-keys >/dev/null 2>&1 && [ -n "$(gpg --list-secret-keys 2>/dev/null)" ]; then
  gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 --armor \
      --export-secret-keys -o "$STAGE/gpg-secret-keys.asc" 3<<<"$PP" 2>/dev/null || \
      gpg --armor --export-secret-keys -o "$STAGE/gpg-secret-keys.asc" 2>/dev/null || true
  gpg --export-ownertrust > "$STAGE/gpg-ownertrust.txt" 2>/dev/null || true
  gpg --armor --export -o "$STAGE/gpg-public-keys.asc" 2>/dev/null || true
  say "  ${c_g}✓ GPG key exported portably${c_reset}"
else say "  ${c_y}! no GPG secret key found${c_reset}"; fi

# --- 2) collect directories/files --------------------------------------------
# label|path (relative to HOME)
TARGETS=(
  "ssh|.ssh"
  "gnupg|.gnupg"
  "gh|.config/gh"
  "codex-auth|.codex/auth.json"
  "claude-json|.claude.json"
  "aws|.aws"
  "azure|.azure"
  "oci|.oci"
  "gcloud|.config/gcloud"
  "npmrc|.npmrc"
  "docker-cfg|.docker/config.json"
  "kube|.kube/config"
  "tunnelblick|Library/Application Support/Tunnelblick/Configurations"
)
INCLUDE=()
MAN="$DEST/secrets-manifest.txt"
{ echo "# Secrets backup — $(date '+%Y-%m-%d %H:%M') — Host: $(hostname)"; echo; } > "$MAN"
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r _ rel <<<"$entry"
  src="$HOME/$rel"
  if [ -e "$src" ]; then
    INCLUDE+=("$rel"); say "  + $rel"; echo "## $rel" >> "$MAN"
    find "$src" -maxdepth 2 \( -name '.DS_Store' -o -name '*.swp' -o -name 'S.*' \) -prune -o -type f -print 2>/dev/null \
      | sed "s|$HOME/||;s|^|   |" >> "$MAN"
  fi
done
[ "${#INCLUDE[@]}" -gt 0 ] || { say "${c_r}Nothing found — aborting.${c_reset}"; exit 1; }

# WireGuard configs (often sitting loose in ~/Downloads) — they contain private keys
wgn=0
shopt -s nullglob
for wg in "$HOME"/Downloads/wg*.conf "$HOME"/Downloads/*.conf; do
  if grep -qi '\[Interface\]' "$wg" 2>/dev/null; then
    mkdir -p "$STAGE/wireguard"; cp -a "$wg" "$STAGE/wireguard/"; wgn=$((wgn+1))
  fi
done
shopt -u nullglob
[ "$wgn" -gt 0 ] && { say "  + $wgn WireGuard config(s) from ~/Downloads"; echo "## wireguard ($wgn configs)" >> "$MAN"; }

# --- 3) encrypted archive (keys + GPG export) --------------------------------
out="$DEST/secrets-$(date +%Y%m%d-%H%M%S).tar.gz.gpg"
say "  … packing & encrypting → $(basename "$out")"
# Excludes: caches/sockets/junk
if ( COPYFILE_DISABLE=1 tar -c \
      --exclude='.DS_Store' --exclude='*.swp' --exclude='*/S.*' \
      --exclude='*/.gnupg/*.lock' --exclude='*/.ssh/agent' \
      -C "$HOME" "${INCLUDE[@]}" -C "$STAGE" . 2>/dev/null | gzip | enc "$out" ); then
  chmod 600 "$out"
  say "  ${c_g}✓ $(du -sh "$out" | cut -f1) → $out${c_reset}"
else say "  ${c_r}✗ packing failed${c_reset}"; exit 1; fi

say ""
say "${c_g}${c_b}Done.${c_reset}"
say "${c_y}➜ Store the password in your password manager NOW (e.g. 'Secrets backup GPG').${c_reset}"
say "${c_y}➜ A git-synced password store comes back after the GPG import on the new Mac.${c_reset}"
say "➜ Restore with:  ./restore-secrets.sh"
say "${c_r}⚠ This file contains private keys. Cloud storage adds no extra encryption — the GPG protection is all there is. Use a strong password!${c_reset}"
