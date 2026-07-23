# Adapt this toolkit with an AI assistant

Your Mac almost certainly runs different apps, browsers and tools than the
author's. Every personal choice lives in two git-ignored files (`Brewfile`,
`restore.config.sh`) — the scripts themselves are generic. If you use an AI
coding assistant that can run commands on your Mac (Claude Code, Codex CLI,
or similar), you can let it explain the principle and tailor the toolkit to
your setup instead of editing everything by hand.

Copy the prompt below into your assistant **inside a clone of this repo**.

---

## Prompt: understand & adapt (run on your CURRENT Mac)

```text
I want to use this repo (a macOS backup & restore toolkit) for MY Mac, which
likely uses different apps than the author's. Work through the following, ask
me only when a decision is genuinely mine:

1. UNDERSTAND: Read README.md and every *.sh script. Summarize in a few
   sentences how the toolkit works: what is backed up (apps list, encrypted
   secrets, encrypted browser profiles), what restore.sh does on a fresh Mac,
   and which parts are personal config (Brewfile, restore.config.sh) versus
   generic engine.

2. INVENTORY MY MAC: Run ./backup-apps.sh, then review the generated Brewfile
   and manual-apps.md with me. Flag apps that look obsolete so I can prune the
   list — a reinstall is the best moment to drop dead weight.

3. TAILOR THE CONFIG: Create restore.config.sh from
   restore.config.example.sh, filled in for me:
   - ESSENTIAL_FORMULAE/ESSENTIAL_CASKS: the handful of daily-driver tools I
     need first (ask me to pick from the Brewfile).
   - INSTALL_RUNTIMES / NPM_GLOBALS / BUN_GLOBALS: match what I actually use.
   - CONFIG_REPOS / SETUP_SCRIPTS / DOTFILES_SOURCE: my dotfiles or config
     repos, if I have any.
   - GUI_INSTALLER_APPS: casks on my machine whose Caskroom entry only stages
     an "Install *.app" (check for them).
   - LOGIN_ITEM_APPS: my menu-bar apps that must auto-start after a restore.

4. BROWSER MATRIX: The backup/restore/cleanup scripts cover Microsoft Edge,
   Edge Beta and Google Chrome. Check which browsers I actually use. For other
   CHROMIUM-based browsers (Brave, Vivaldi, Arc, Chromium, …), extend the
   BROWSERS arrays in backup-browser-profiles.sh, restore-browser-profiles.sh
   and cleanup-browser-caches.sh — each entry needs the Application Support
   subfolder, the "... Safe Storage" keychain service/account, and the main
   binary path. Firefox and Safari store data differently and are NOT covered;
   tell me clearly if I rely on them.

5. DRY-RUN THE BACKUP: Walk me through backup-secrets.sh and
   backup-browser-profiles.sh (offer the optional cache cleanup), then run
   ./verify-backups.sh and confirm every archive decrypts. Remind me to store
   the password in my password manager and, if the folder syncs to a cloud,
   to wait for uploads to finish before wiping anything.

SAFETY RULES: Never print key material, passwords or decrypted archive
contents into the chat. Never upload backups anywhere. Do not delete anything
except via cleanup-browser-caches.sh. If a check fails, stop and explain
instead of improvising.
```

---

## Prompt: restore (run on the NEW Mac)

```text
This repo plus my backup folder (Brewfile, restore.config.sh, secrets-backup/,
browser-backup/) are on this freshly installed Mac. Read README.md, then guide
me through restore.sh → restore-secrets.sh → restore-browser-profiles.sh.
Handle the four manual prerequisites at the right moments (App Store sign-in,
gh auth login, GPG key import, Terminal "App Management" permission — see the
troubleshooting notes in README.md). Afterwards run
`brew bundle check --file=Brewfile` and report what is still missing and why.
Same safety rules: no secrets in the chat, stop and explain on failures.
```
