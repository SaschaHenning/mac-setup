#!/usr/bin/env bash
# =============================================================================
#  restore.sh — macOS bootstrap after a clean install
# =============================================================================
#  Sets up a freshly installed Mac from your Brewfile + optional config.
#  Idempotent: safe to run multiple times, only does what is missing.
#
#  USAGE:
#     cd /path/to/mac-setup
#     ./restore.sh
#
#  Reads two files next to this script:
#     Brewfile            — your app/tool list (generate with ./backup-apps.sh)
#     restore.config.sh   — optional personal config (copy from
#                           restore.config.example.sh; git-ignored)
#
#  MANUAL prerequisites no script can automate (the script prompts at the
#  right moments):
#     1. App Store: sign in (needed for `mas` apps)
#     2. GitHub: gh auth login (needed for private config repos)
#     3. Import your GPG key (see restore-secrets.sh)
#     4. Grant Terminal the "App Management" permission (System Settings →
#        Privacy & Security). Without it, casks whose installer modifies the
#        app bundle (e.g. parallels) fail even with a correct sudo password:
#        chown as root returns "Operation not permitted" and brew rolls the
#        app back.
# =============================================================================

set -uo pipefail

# ---- Configuration -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/Brewfile"
LOG="$SCRIPT_DIR/restore-$(date +%Y%m%d-%H%M%S).log"

# Defaults — override any of these in restore.config.sh
ESSENTIAL_FORMULAE=(git gh jq ripgrep)
ESSENTIAL_CASKS=()
INSTALL_RUNTIMES=1        # nvm/node LTS, bun, uv
NPM_GLOBALS=()
BUN_GLOBALS=()
CONFIG_REPOS=()           # "https://github.com/you/repo.git|$HOME/Code/repo"
SETUP_SCRIPTS=()          # scripts to run after cloning (absolute paths)
DOTFILES_SOURCE=""        # chezmoi source dir, e.g. "$HOME/Code/dotfiles"
GUI_INSTALLER_APPS=()     # "App Name|cask-name" for casks that only stage a GUI installer
LOGIN_ITEM_APPS=()        # menu-bar apps to launch + add as login items, e.g. (Shottr)

if [ -f "$SCRIPT_DIR/restore.config.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/restore.config.sh"
fi

# =============================================================================
#  Helpers
# =============================================================================
c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'
c_blue=$'\033[34m'; c_red=$'\033[31m'; c_cyan=$'\033[36m'
say()   { printf '%s\n' "$*" | tee -a "$LOG"; }
head_() { say ""; say "${c_bold}${c_blue}==> $*${c_reset}"; }
ok()    { say "${c_green}  ✓ $*${c_reset}"; }
warn()  { say "${c_yellow}  ! $*${c_reset}"; }
err()   { say "${c_red}  ✗ $*${c_reset}"; }
have()  { command -v "$1" >/dev/null 2>&1; }
pause_enter() { read -r -p "   ↳ ${1:-Continue with ENTER, Ctrl-C to abort} " _ || true; }

say "${c_bold}${c_cyan}"
say "  ╔══════════════════════════════════════════════════════════╗"
say "  ║   Mac-Setup Restore  —  $(date '+%Y-%m-%d %H:%M')                    ║"
say "  ╚══════════════════════════════════════════════════════════╝"
say "${c_reset}Log: $LOG"

# =============================================================================
#  0. Preflight
# =============================================================================
head_ "0. Preflight"
[ "$(uname -s)" = "Darwin" ] || { err "macOS only."; exit 1; }
ok "macOS $(sw_vers -productVersion)  ($(uname -m))"
[ -f "$BREWFILE" ] || { err "Brewfile not found next to restore.sh ($BREWFILE) — generate one with ./backup-apps.sh on your old Mac."; exit 1; }
ok "Brewfile found"

# "App Management" TCC permission: without it, casks whose installer modifies
# the app bundle in /Applications (e.g. parallels: inittool chown as root →
# "Operation not permitted") fail DESPITE a correct sudo password, and brew
# rolls the app back. Not queryable via CLI, so we can only point at it.
if grep -q '^cask "parallels"' "$BREWFILE" && [ ! -d "/Applications/Parallels Desktop.app" ]; then
  warn "Your Terminal needs the 'App Management' permission (otherwise e.g. the parallels cask fails):"
  say  "     System Settings → Privacy & Security → App Management → enable your Terminal,"
  say  "     then FULLY quit the Terminal (Cmd+Q) and re-run this script."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles" 2>/dev/null || true
  pause_enter "Permission granted (or deliberately skipped)? ENTER"
fi

# =============================================================================
#  1. Xcode Command Line Tools (git/compiler — prerequisite for everything)
# =============================================================================
head_ "1. Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "already installed ($(xcode-select -p))"
else
  warn "installing Command Line Tools — a dialog will open…"
  xcode-select --install || true
  say "   Wait until the installation dialog finishes."
  pause_enter "Done? ENTER to continue"
fi

# =============================================================================
#  2. Homebrew
# =============================================================================
head_ "2. Homebrew"
if have brew; then
  ok "already installed ($(brew --version | head -1))"
else
  warn "installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOG"
fi
# put brew on PATH (Apple Silicon / Intel)
if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
have brew || { err "brew not on PATH — open a new terminal and re-run."; exit 1; }
ok "brew ready"

# =============================================================================
#  PHASE A — daily-driver essentials first (Mac usable within minutes)
# =============================================================================
head_ "A. Essential apps first"
if [ "${#ESSENTIAL_FORMULAE[@]}" -gt 0 ]; then
  say "   CLI: ${ESSENTIAL_FORMULAE[*]}"
  for f in "${ESSENTIAL_FORMULAE[@]}"; do
    if brew list --formula --versions "$f" >/dev/null 2>&1; then ok "$f (present)"
    else say "   → brew install $f"; brew install "$f" >>"$LOG" 2>&1 && ok "$f" || err "$f failed (see log)"; fi
  done
fi
if [ "${#ESSENTIAL_CASKS[@]}" -gt 0 ]; then
  say "   Apps: ${ESSENTIAL_CASKS[*]}"
  for c in "${ESSENTIAL_CASKS[@]}"; do
    if brew list --cask --versions "$c" >/dev/null 2>&1; then ok "$c (present)"
    else say "   → brew install --cask $c"; brew install --cask "$c" >>"$LOG" 2>&1 && ok "$c" || err "$c failed (see log)"; fi
  done
fi

# ---- A.1 Runtimes: nvm + node(LTS), bun, uv ---------------------------------
if [ "$INSTALL_RUNTIMES" = "1" ]; then
  head_ "A.1 Runtimes: node (nvm), bun, uv"
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    warn "installing nvm…"
    PROFILE=/dev/null bash -c \
      "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash" >>"$LOG" 2>&1 || true
  fi
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  if have nvm; then
    nvm install --lts >>"$LOG" 2>&1 && nvm alias default 'lts/*' >>"$LOG" 2>&1
    ok "node $(node -v 2>/dev/null) via nvm (LTS)"
  else warn "nvm not loaded — install node manually later"; fi
  if have bun; then ok "bun $(bun --version)"
  else warn "installing bun…"; curl -fsSL https://bun.sh/install | bash >>"$LOG" 2>&1 || true
       export PATH="$HOME/.bun/bin:$PATH"; have bun && ok "bun $(bun --version)"; fi
  if have uv; then ok "uv $(uv --version)"
  else warn "installing uv…"; curl -LsSf https://astral.sh/uv/install.sh | sh >>"$LOG" 2>&1 || true
       export PATH="$HOME/.local/bin:$PATH"; have uv && ok "uv $(uv --version)"; fi
fi

# ---- A.2 Global CLI packages -------------------------------------------------
if [ "${#NPM_GLOBALS[@]}" -gt 0 ] || [ "${#BUN_GLOBALS[@]}" -gt 0 ]; then
  head_ "A.2 Global CLI packages"
  if [ "${#NPM_GLOBALS[@]}" -gt 0 ]; then
    if have npm; then
      for g in "${NPM_GLOBALS[@]}"; do
        npm ls -g --depth=0 "$g" >/dev/null 2>&1 || { say "   → npm i -g $g"; npm install -g "$g" >>"$LOG" 2>&1 || true; }
      done
      ok "npm globals: ${NPM_GLOBALS[*]}"
    else warn "npm missing — set up nvm/node first, then re-run"; fi
  fi
  if [ "${#BUN_GLOBALS[@]}" -gt 0 ] && have bun; then
    for g in "${BUN_GLOBALS[@]}"; do
      bun pm ls -g 2>/dev/null | grep -q "$g" || { say "   → bun add -g $g"; bun add -g "$g" >>"$LOG" 2>&1 || true; }
    done
    ok "bun globals: ${BUN_GLOBALS[*]}"
  fi
fi

# =============================================================================
#  PHASE B — everything else via Brewfile (formulae, casks, VS Code, mas)
# =============================================================================
head_ "B. Remaining software via Brewfile"
say "   ${c_yellow}App Store apps (mas): please sign in to the App Store NOW.${c_reset}"
if have mas; then
  # 'mas account' was removed from current mas versions ("Unexpected argument")
  # — the sign-in state is no longer queryable, so we can only prompt.
  acct="$(mas account 2>/dev/null)" || acct=""
  if [ -n "$acct" ]; then ok "App Store: signed in as $acct"
  else warn "App Store sign-in not verifiable or missing — mas lines will fail (everything else proceeds)."
       pause_enter "App Store opened & signed in? ENTER (or skip)"; fi
fi

# Tap trust (Homebrew feature, 2026): untrusted taps are otherwise IGNORED
# entirely ("Homebrew is currently ignoring formulae, casks and commands from
# these taps") — your Brewfile's tap lines would silently do nothing.
BF_TAPS="$(awk -F'"' '/^tap "/ {print $2}' "$BREWFILE" | xargs)"
if [ -n "$BF_TAPS" ]; then
  # shellcheck disable=SC2086  # word splitting intended
  if brew trust $BF_TAPS >>"$LOG" 2>&1; then ok "taps trusted: $BF_TAPS"
  else warn "brew trust unavailable/failed (older Homebrew? see log)"; fi
fi

say "   → brew bundle (this can take a while)…"
# Notes from the field:
#  - '--no-lock' no longer exists in current Homebrew and used to abort the
#    WHOLE bundle run with 'Error: invalid option'. Run without flags.
#  - sudo casks (Docker Desktop, Parallels, Zoom, …) and App Store apps need a
#    real interactive terminal (tty) for the password/login prompt — in a
#    non-interactive run exactly those fail and are listed at the end.
brew bundle install --file="$BREWFILE" 2>&1 | tee -a "$LOG" || warn "brew bundle finished with warnings (see log) — usually individual mas/cask lines (password/App Store needed)"
ok "Brewfile processed"

# ---- B.1 Cask/mas follow-ups -------------------------------------------------
head_ "B.1 Cask/mas follow-ups"
# Some casks only stage a GUI installer in the Caskroom — the actual install
# has to be clicked through once (admin password). Example: parallels-toolbox.
if [ "${#GUI_INSTALLER_APPS[@]}" -gt 0 ]; then
  CASKROOM="$(brew --caskroom 2>/dev/null || echo /opt/homebrew/Caskroom)"
  for entry in "${GUI_INSTALLER_APPS[@]}"; do
    IFS='|' read -r appname caskname <<<"$entry"
    if [ ! -d "/Applications/$appname.app" ]; then
      installer="$(ls -d "$CASKROOM/$caskname"/*/Install*.app 2>/dev/null | tail -1)"
      if [ -n "$installer" ]; then
        warn "$appname not installed yet — opening its installer (click through)…"
        open "$installer" || true
      fi
    else ok "$appname installed"; fi
  done
fi
# Menu-bar apps: launch + add as login item — otherwise they appear "gone"
# after a restore even though they are installed.
if [ "${#LOGIN_ITEM_APPS[@]}" -gt 0 ]; then
  for app in "${LOGIN_ITEM_APPS[@]}"; do
    [ -d "/Applications/$app.app" ] || continue
    open -g -a "$app" 2>/dev/null || true
    osascript -e "tell application \"System Events\" to if not (exists login item \"$app\") then make login item at end with properties {path:\"/Applications/$app.app\", hidden:false}" >/dev/null 2>&1 \
      && ok "$app launched + login item set" || warn "$app: could not set login item (Automation permission for System Events?)"
  done
fi
# mas gaps: apps your Apple account has NEVER downloaded before cannot be
# installed by mas ("No apps found for ADAM ID") — they must be fetched once
# via the App Store UI. Open the product pages so it is one click each.
missing_mas="$(brew bundle check --file="$BREWFILE" --verbose 2>/dev/null | grep '^→ App ' || true)"
if [ -n "$missing_mas" ]; then
  warn "Missing App Store apps — opening their product pages, click 'Get' once for each:"
  say "$missing_mas"
  while IFS= read -r line; do
    app="$(printf '%s' "$line" | sed -E 's/^→ App (.*) needs to be installed or updated\.$/\1/')"
    id="$(awk -F'id: ' -v a="$app" '$0 ~ ("^mas \"" a "\"") {print $2}' "$BREWFILE" | tr -d ' ')"
    [ -n "$id" ] && { open "macappstore://apps.apple.com/app/id$id" 2>/dev/null || true; sleep 1; }
  done <<<"$missing_mas"
fi

# =============================================================================
#  C. Personal config repos + setup scripts (all optional, from config)
# =============================================================================
if [ "${#CONFIG_REPOS[@]}" -gt 0 ]; then
  head_ "C. Config repos & personal setup"
  if have gh; then
    if gh auth status >/dev/null 2>&1; then ok "GitHub: signed in"
    else warn "GitHub login needed (for private repos)…"; gh auth login || warn "gh auth skipped"; fi
    # IMPORTANT: clone via HTTPS + gh token. Otherwise git tries SSH — but your
    # SSH keys arrive later from the secrets backup (restore-secrets.sh), so on
    # a first run every clone would fail with "Permission denied (publickey)".
    gh config set git_protocol https >/dev/null 2>&1 || true
    gh auth setup-git >/dev/null 2>&1 || warn "gh auth setup-git skipped"
  fi
  clone_repo() { # $1=url $2=destination
    local url="$1" dst="$2" name; name="$(basename "$dst")"
    if [ -d "$dst/.git" ]; then ok "$name (already cloned) — git pull"; git -C "$dst" pull --ff-only >>"$LOG" 2>&1 || warn "$name pull skipped"
    else say "   → clone $name"; mkdir -p "$(dirname "$dst")"; git clone "$url" "$dst" >>"$LOG" 2>&1 && ok "$name cloned" || err "$name clone failed (auth?)"; fi
  }
  for entry in "${CONFIG_REPOS[@]}"; do
    IFS='|' read -r url dst <<<"$entry"
    clone_repo "$url" "$dst"
  done
  if [ "${#SETUP_SCRIPTS[@]}" -gt 0 ]; then
    for s in "${SETUP_SCRIPTS[@]}"; do
      if [ -x "$s" ]; then say "   → $s"; ( "$s" ) >>"$LOG" 2>&1 && ok "$(basename "$s")" || warn "$(basename "$s") finished with warnings (see log)"
      else warn "$s not found/executable"; fi
    done
  fi
fi

# ---- C.1 Dotfiles (chezmoi, optional) ---------------------------------------
if [ -n "$DOTFILES_SOURCE" ]; then
  head_ "C.1 Dotfiles (chezmoi)"
  if have chezmoi && [ -d "$DOTFILES_SOURCE" ]; then
    chezmoi init --source="$DOTFILES_SOURCE" >>"$LOG" 2>&1 || true
    # ~/.ssh is DELIBERATELY excluded: SSH config/keys come from the encrypted
    # secrets backup (restore-secrets.sh), not from dotfiles — a repo version
    # is usually older and would loosen 600 permissions.
    DF_TARGETS=()
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      case "$t" in .ssh|.ssh/*) continue;; esac
      DF_TARGETS+=("$HOME/$t")
    done < <(chezmoi managed --include=files --source="$DOTFILES_SOURCE" 2>/dev/null)
    if [ "${#DF_TARGETS[@]}" -gt 0 ]; then
      say "   Preview of dotfile changes (dry-run, without ~/.ssh):"
      chezmoi apply --dry-run --verbose --source="$DOTFILES_SOURCE" "${DF_TARGETS[@]}" 2>&1 | tee -a "$LOG" | head -30 || true
      warn "chezmoi apply will overwrite these dotfiles (NOT ~/.ssh). Apply now?"
      read -r -p "   ↳ 'y' to apply, anything else skips: " ans || true
      [ "${ans:-}" = "y" ] && { chezmoi apply --source="$DOTFILES_SOURCE" "${DF_TARGETS[@]}" >>"$LOG" 2>&1 && ok "dotfiles applied (without ~/.ssh)"; } || warn "chezmoi apply skipped"
    else warn "chezmoi: no applicable targets found"; fi
  else warn "chezmoi/dotfiles not ready — later: chezmoi init --source=$DOTFILES_SOURCE --apply"; fi
fi

# =============================================================================
#  D. Remaining manual steps
# =============================================================================
head_ "D. Still manual"
say "   ${c_yellow}1) Secrets (SSH + GPG):${c_reset} restore from the encrypted backup —"
say "      ./restore-secrets.sh"
say "   ${c_yellow}2) App Store:${c_reset} if skipped above — sign in and run 'brew bundle' again for the mas apps."
say "   ${c_yellow}3) Vendor apps without a cask:${c_reset} see your manual-apps.md (generated by backup-apps.sh)."
say "   ${c_yellow}4) Browser profiles:${c_reset} start+quit each browser once, then:"
say "      ./restore-browser-profiles.sh"

# =============================================================================
#  Done
# =============================================================================
head_ "Done 🎉"
ok "Base system set up. Open a new terminal so all PATH changes take effect."
say "   Full log: $LOG"
say "   Recommended afterwards:  brew doctor   &&   brew bundle check --file=\"$BREWFILE\""
