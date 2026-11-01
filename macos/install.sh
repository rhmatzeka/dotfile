#!/usr/bin/env bash
# macOS installer (beta): the terminal setup and the developer tools, split into components you pick from a menu.
#
#   ./install.sh                 interactive menu
#   ./install.sh --all           every component that works on macOS
#   ./install.sh --only shell,nvim
#   ./install.sh --dry-run       show what would happen, change nothing
#   ./install.sh --yes           no questions; answer each with its default
#   ./install.sh --list          list the components
#
# Normally started through the top-level install.sh (which also fetches the repository).
# Written for the bash 3.2 that ships with macOS: no associative arrays, no bare "${a[@]}" of an empty array.
# Packages come from Homebrew, which is installed first when it is missing. The Linux-only parts (the Hyprland
# desktop, the Microsoft 365 web-app launchers) are listed in the menu but cannot be selected.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=../lib/menu.sh
. "$DOTFILES_DIR/lib/menu.sh"
# shellcheck source=../lib/parts.sh
. "$DOTFILES_DIR/lib/parts.sh"

C="$DOTFILES_DIR/config"
ARCH="$(uname -m)"

# shellcheck disable=SC2034  # MENU_* are read by lib/menu.sh
MENU_TITLE="macOS (beta)"
MENU_ITEMS=(base shell tmux nvim terminal browsers web rust)
# shellcheck disable=SC2034
MENU_DEFAULTS=(base shell tmux nvim terminal)
# shellcheck disable=SC2034
MENU_OFF=(
  "desktop|Hyprland + Caelestia desktop (Linux only)"
  "apps|Microsoft 365 web-app launchers, Thunar menu (Linux only; on a Mac install Office from the App Store)"
)

menu_desc() {
  case "$1" in
    base)     echo "Homebrew, git, ripgrep, fzf, eza, zoxide and the JetBrainsMono Nerd Font" ;;
    shell)    echo "zsh + Oh My Zsh + starship prompt" ;;
    tmux)     echo "tmux with a cyan/Dracula theme" ;;
    nvim)     echo "Neovim (NvChad) with tree-sitter parsers and LSP servers" ;;
    terminal) echo "Ghostty + its config (Vim-style keys, dark theme)" ;;
    browsers) echo "Terminal browsers: elinks, w3m" ;;
    web)      echo "Web development: PHP, Composer, MariaDB, phpMyAdmin (services stay off unless you say yes)" ;;
    rust)     echo "Rust toolchain via rustup (rustc, cargo, clippy, rustfmt, rust-analyzer)" ;;
  esac
}

menu_status() {
  case "$1" in
    base)     find_brew && have rg && have fzf && font_present && echo installed ;;
    shell)    linked_here "$HOME/.zshrc" && [ -d "$HOME/.oh-my-zsh" ] && echo installed ;;
    tmux)     linked_here "$HOME/.config/tmux/tmux.conf" && have tmux && echo installed ;;
    nvim)     linked_here "$HOME/.config/nvim/lua/plugins/dotfiles.lua" && have nvim && echo installed ;;
    terminal) linked_here "$HOME/.config/ghostty/config.ghostty" && ghostty_app >/dev/null && echo installed ;;
    browsers) have elinks && have w3m && echo installed ;;
    web)      have php && { have mariadb || have mysql; } && echo installed ;;
    rust)     { have rustup || [ -x "$HOME/.cargo/bin/rustup" ]; } && echo installed ;;
  esac
  return 0
}

menu_note() {
  case "$1" in
    nvim)    echo "about 500 MB (Node.js, parsers and LSP servers), 5-15 minutes" ;;
    web)     echo "about 400 MB; MariaDB stays off unless you say yes" ;;
    rust)    echo "about 1 GB (toolchain in ~/.rustup)" ;;
  esac
  return 0
}

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ------------------------------------------------------------ arguments ----
ALL=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)     ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --all)        ALL=1 ;;
    --only)       shift; ONLY="${1:-}" ;;
    --only=*)     ONLY="${1#--only=}" ;;
    --list)       menu_list; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done
export DRY_RUN ASSUME_YES

# ------------------------------------------------------------- Homebrew ----
BREW=""
find_brew() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && { BREW="$b"; return 0; }; done
  have brew && { BREW="$(command -v brew)"; return 0; }
  return 1
}

ensure_brew() {
  if find_brew; then eval "$("$BREW" shellenv)"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would install Homebrew (brew.sh)"; BREW=brew; return 0; fi
  info "installing Homebrew from brew.sh (it asks for your password, and installs the Xcode Command Line Tools if needed)"
  local script; script="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || { fail "could not download the Homebrew installer"; return 1; }
  if interactive && [ "$ASSUME_YES" != 1 ]; then /bin/bash -c "$script" <"$DOTFILES_TTY"
  else NONINTERACTIVE=1 /bin/bash -c "$script" </dev/null; fi || { fail "the Homebrew installer failed"; return 1; }
  find_brew || { fail "Homebrew was installed but brew is not where it should be (/opt/homebrew or /usr/local)"; return 1; }
  eval "$("$BREW" shellenv)"
  ok "Homebrew $("$BREW" --version | head -n1)"
}

brew_has()      { [ -n "$BREW" ] && "$BREW" list --formula "$1" >/dev/null 2>&1; }
brew_has_cask() { [ -n "$BREW" ] && "$BREW" list --cask "$1" >/dev/null 2>&1; }

# brew_need formula...   install what is missing (fails if something cannot be installed)
brew_need() {
  local missing=() f
  ensure_brew || return 1
  for f in "$@"; do brew_has "$f" || missing+=("$f"); done
  if [ ${#missing[@]} -eq 0 ]; then ok "already installed: $*"; return 0; fi
  info "brew install: ${missing[*]}"
  run "$BREW" install "${missing[@]}"
}

# brew_optional formula...   try each one; warn instead of failing
brew_optional() {
  local f
  ensure_brew || return 1
  for f in "$@"; do
    brew_has "$f" && continue
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would try: brew install $f"; continue; fi
    "$BREW" install "$f" >/dev/null 2>&1 && ok "installed $f" || warn "not available or could not install, skipped: $f"
  done
  return 0
}

# cask_need cask   (apps and fonts)
cask_need() {
  ensure_brew || return 1
  if brew_has_cask "$1"; then ok "already installed: $1"; return 0; fi
  info "brew install --cask $1"
  run "$BREW" install --cask "$1"
}

font_present() { ls "$HOME"/Library/Fonts/JetBrainsMonoNerd* /Library/Fonts/JetBrainsMonoNerd* >/dev/null 2>&1; }
ghostty_app() {
  local a
  for a in /Applications/Ghostty.app "$HOME/Applications/Ghostty.app"; do [ -d "$a" ] && { printf '%s' "$a"; return 0; }; done
  return 1
}

# ------------------------------------------------------------ preflight ----
preflight() {
  [ "$(uname -s)" = Darwin ] || die "This installer is for macOS (use linux/install.sh on Linux)."
  [ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root: Homebrew refuses to run as root."
  case "$ARCH" in arm64|x86_64) ;; *) die "unsupported CPU: $ARCH" ;; esac
  [ "$DRY_RUN" = 1 ] && info "DRY RUN: nothing will be changed."
  ensure_local_bin_in_path
}

# ----------------------------------------------------------- components ----
comp_base() {
  step "Base: Homebrew, command-line tools, Nerd Font"
  ensure_brew || return 1
  brew_need git curl wget jq fzf ripgrep
  brew_optional eza zoxide fastfetch btop htop
  if font_present; then ok "font already present: JetBrainsMono Nerd Font"
  else cask_need font-jetbrains-mono-nerd-font; fi
}

comp_shell() {
  step "Shell: zsh + Oh My Zsh + starship"
  brew_need starship git
  shell_configs
  # zsh has been the macOS default since Catalina; offer it only if this account was switched to something else
  if [ "$(basename "${SHELL:-}")" != zsh ] && confirm "Make zsh your default login shell?" n; then
    run chsh -s /bin/zsh
  fi
}

comp_tmux() {
  step "tmux"
  brew_need tmux
  backup_and_link "$C/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
}

comp_nvim() {
  step "Neovim (NvChad)"
  brew_need neovim node ripgrep git
  # tree-sitter CLI: nvim-treesitter builds the parsers with it (Homebrew calls the CLI formula tree-sitter-cli)
  brew_optional tree-sitter-cli
  if ! have tree-sitter && [ ! -x "$HOME/.local/bin/tree-sitter" ]; then
    local t=x64; [ "$ARCH" = arm64 ] && t=arm64
    info "installing the tree-sitter CLI into ~/.local/bin"
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would download tree-sitter-macos-$t.gz"
    else
      local tmp; tmp="$(mktemp)"
      fetch "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-macos-$t.gz" "$tmp" || return 1
      mkdir -p "$HOME/.local/bin" && gunzip -c "$tmp" >"$HOME/.local/bin/tree-sitter" && chmod +x "$HOME/.local/bin/tree-sitter" && rm -f "$tmp"
    fi
  fi
  nvchad_setup
}

comp_terminal() {
  step "Terminal: Ghostty"
  # Ghostty on macOS reads ~/.config/ghostty/config.ghostty as well as its ~/Library location
  backup_and_link "$C/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
  if ghostty_app >/dev/null; then ok "Ghostty already installed: $(ghostty_app)"
  else cask_need ghostty; fi
  info "Open Ghostty from Launchpad or Spotlight; it starts zsh with this setup."
}

comp_browsers() {
  step "Terminal browsers"
  brew_need w3m
  brew_optional elinks
  elinks_configs "$HOME/Downloads"
  info "Browsh (Firefox inside the terminal) is set up on Linux only."
}

comp_web() {
  step "Web development: PHP, Composer, MariaDB, phpMyAdmin"
  brew_need php composer mariadb
  brew_optional phpmyadmin
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would offer to start MariaDB"
  elif confirm "Start MariaDB now and at every login (brew services)?" n; then
    "$BREW" services start mariadb || warn "could not start MariaDB; start it with: brew services start mariadb"
  else
    info "MariaDB was not started. Start it with: brew services start mariadb"
  fi
  info "MariaDB lets your macOS user in without a password (run: mariadb). No password was set anywhere."
  [ -n "$BREW" ] && info "phpMyAdmin: php -S localhost:8080 -t \"$("$BREW" --prefix 2>/dev/null)/share/phpmyadmin\"  then open http://localhost:8080"
  return 0
}

comp_rust() {
  step "Rust (rustup)"
  rustup_setup
}

# ----------------------------------------------------------------- main ----
preflight
# shellcheck disable=SC2034  # read by run_selected (lib/menu.sh)
if [ "$ALL" = 1 ]; then SELECTED=("${MENU_ITEMS[@]}")
elif [ -n "$ONLY" ]; then menu_from_list "$ONLY"
else menu_choose; fi
[ "${#SELECTED[@]}" -gt 0 ] && ! find_brew && info "Homebrew is not installed yet: it is installed first (brew.sh, asks for your password once)."
menu_confirm || { info "Cancelled."; exit 0; }

run_selected
if [ "$DRY_RUN" != 1 ] && [ ${#OK[@]} -gt 0 ]; then
  in_list shell "${OK[@]}" && info "Open a new terminal window (or run: exec zsh) to load the new shell."
  [ -d "$BACKUP_ROOT/$STAMP" ] && info "Files that were replaced are in ${BACKUP_ROOT/#$HOME/~}/$STAMP"
fi
[ ${#FAILED[@]} -eq 0 ]
