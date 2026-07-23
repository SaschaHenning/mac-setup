# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
#  restore.config.example.sh — personal configuration for restore.sh
# =============================================================================
#  Copy to restore.config.sh (git-ignored) and adjust. restore.sh sources it
#  after setting its defaults, so anything you define here overrides them.
# =============================================================================

# Installed FIRST, before the full Brewfile run — the Mac is usable in minutes.
ESSENTIAL_FORMULAE=(git gh jq ripgrep gnupg mas)
ESSENTIAL_CASKS=(visual-studio-code google-chrome)

# 1 = install nvm + node LTS, bun and uv; 0 = skip
INSTALL_RUNTIMES=1

# Global CLI packages (installed after the runtimes)
NPM_GLOBALS=(typescript)
BUN_GLOBALS=()

# Personal config repos: "clone-url|target-path" — cloned via HTTPS + gh token
# (SSH keys only arrive later with restore-secrets.sh).
CONFIG_REPOS=(
  "https://github.com/you/dotfiles.git|$HOME/Code/dotfiles"
  "https://github.com/you/my-config.git|$HOME/Code/my-config"
)

# Scripts to run after cloning (absolute paths, executable)
SETUP_SCRIPTS=(
  "$HOME/Code/my-config/setup.sh"
)

# chezmoi source directory ("" = skip dotfiles step)
DOTFILES_SOURCE="$HOME/Code/dotfiles"

# Casks that only stage a GUI installer in the Caskroom: "App Name|cask-name".
# restore.sh opens the staged installer if the app is missing.
GUI_INSTALLER_APPS=(
  "Parallels Toolbox|parallels-toolbox"
)

# Menu-bar apps to launch once and register as login items after install
LOGIN_ITEM_APPS=(
  "Shottr"
)
