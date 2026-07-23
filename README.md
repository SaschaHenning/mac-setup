# mac-setup

Back up a Mac before a clean install and restore the full setup on a new one:
apps (Homebrew + App Store), encrypted secrets (SSH/GPG/dev logins), and full
browser profiles including active sessions. Everything is plain bash — no
frameworks, no daemons, works on the stock macOS bash 3.2.

**Why:** Migration Assistant copies too much (old cruft), cloud sync copies too
little (browser sync does not carry session cookies, and nothing carries your
SSH/GPG keys). These scripts capture exactly the state that is painful to lose,
encrypt what is sensitive, and replay it on a fresh machine.

## Workflow

### On the OLD Mac (before wiping)

```
./backup-apps.sh                   # Brewfile + manual-apps.md
./backup-secrets.sh                # SSH, GPG, dev logins → encrypted archive
./cleanup-browser-caches.sh        # OPTIONAL: shrink profiles by deleting regenerable caches
./backup-browser-profiles.sh       # Edge/Edge Beta/Chrome profiles + Safe Storage keys
./verify-backups.sh                # PROVE the password decrypts every archive
```

Then store the whole folder in iCloud Drive or on a USB drive. If it syncs to
the cloud, wait until every upload has finished (no cloud-with-arrow icons in
Finder) before wiping the Mac.

The cache cleanup step is optional: `backup-browser-profiles.sh` excludes
caches from the archive either way, but cleaning first shrinks the on-disk
profiles, speeds up the packing pass, and keeps full-disk backups (Time
Machine, cloud sync) smaller. It deletes only regenerable caches — never
cookies, logins, storage or profiles. `backup-browser-profiles.sh` offers it
interactively, or run it non-interactively with `--clean`:

```
./backup-browser-profiles.sh --clean
```

### On the NEW Mac

```
./restore.sh                   # Homebrew, Brewfile, runtimes, config repos, dotfiles
./restore-secrets.sh           # GPG import, ~/.ssh with correct permissions, dev logins
./restore-browser-profiles.sh  # after starting+quitting each browser once
```

`restore.sh` is idempotent — re-run it as often as needed; it only does what is
missing. Copy `restore.config.example.sh` to `restore.config.sh` to personalize
it (essential apps, config repos, dotfiles, login items).

## Manual prerequisites

Four things no script can automate (restore.sh prompts at the right moments):

1. **App Store sign-in** — required for `mas` (App Store) apps.
2. **`gh auth login`** — required to clone private config repos.
3. **GPG key import** — done by `restore-secrets.sh`; your encrypted backups
   and your password store depend on it.
4. **Terminal "App Management" permission** (System Settings → Privacy &
   Security → App Management) — without it some casks fail. See below.

## Troubleshooting / field notes

Collected from a real migration — these are the things that actually bite:

- **App Management TCC:** casks whose installer modifies the app bundle (e.g.
  `parallels`) fail with `chown … Operation not permitted` **as root, despite a
  correct sudo password**, and brew rolls the app back. Fix: System Settings →
  Privacy & Security → App Management → enable your terminal app, then **fully
  quit the terminal (Cmd+Q)** and re-run. A new window is not enough.
- **Homebrew tap trust (2026):** untrusted taps are silently ignored
  ("Homebrew is currently ignoring formulae, casks and commands from these
  taps") — the tap lines in your Brewfile would do nothing. `restore.sh` runs
  `brew trust` on all Brewfile taps before bundling.
- **`mas account` is gone:** current `mas` versions removed the `account`
  subcommand ("Unexpected argument"), so App Store sign-in can no longer be
  verified from the CLI — the script can only prompt you.
- **mas "No apps found for ADAM ID …":** the app has never been fetched by
  this Apple account. `mas` cannot do the first-time "purchase" — you must
  click "Get" once in the App Store UI. `restore.sh` opens the product pages
  for every missing mas app so it is one click each.
- **`brew bundle --no-lock` no longer exists** and aborts the whole bundle
  run with `Error: invalid option`. Run `brew bundle install` without flags.
- **Installer-only casks:** some casks (e.g. `parallels-toolbox`) only stage
  an "Install ….app" in the Caskroom — the actual installation must be clicked
  through once. `restore.sh` opens the staged installer if the app is missing.
- **Menu-bar apps look "gone" after restore:** they are installed but neither
  running nor set to launch at login. `restore.sh` launches the apps listed in
  `LOGIN_ITEM_APPS` (e.g. Shottr) and registers them as login items.
- **Clone config repos via HTTPS + gh token**, not SSH: your SSH keys arrive
  only later with the secrets restore, so on a first run every SSH clone would
  fail with `Permission denied (publickey)`. `restore.sh` sets
  `gh config set git_protocol https` and `gh auth setup-git`.

## Security notes

- Secrets and browser profiles are encrypted with **GPG symmetric AES256** and
  a single password you choose. Verify it with `./verify-backups.sh` **before**
  wiping the old Mac — a wrong password discovered afterwards is fatal.
- What leaves the machine is only the encrypted `*.gpg` archives (plus two
  plaintext manifests listing file *names*, never contents). iCloud/USB add no
  encryption of their own — the GPG password is the entire protection, so make
  it strong and store it in your password manager.
- The backup archives contain private keys and live session cookies. Treat the
  backup folder itself as a secret; delete it once the new Mac is verified.
- The generated `Brewfile`, `manual-apps.md` and your `restore.config.sh` are
  git-ignored — this repo stays generic, your machine specifics stay local.

## Files

| Script | Runs on | Purpose |
|---|---|---|
| `backup-apps.sh` | old Mac | Brewfile dump + list of manually installed apps |
| `backup-secrets.sh` | old Mac | SSH/GPG/dev logins → encrypted archive |
| `backup-browser-profiles.sh` | old Mac | browser profiles + Safe Storage keychain keys, encrypted |
| `verify-backups.sh` | old Mac | test-decrypt every archive (writes nothing) |
| `cleanup-browser-caches.sh` | any | delete only regenerable browser caches |
| `restore.sh` | new Mac | full bootstrap: brew, Brewfile, runtimes, repos, dotfiles |
| `restore-secrets.sh` | new Mac | GPG import, ~/.ssh permissions, dev logins |
| `restore-browser-profiles.sh` | new Mac | Safe Storage keys + profiles back in place |

## License

MIT — see [LICENSE](LICENSE).
