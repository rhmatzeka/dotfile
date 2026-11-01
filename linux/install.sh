#!/usr/bin/env bash
# Linux installer (Debian/Ubuntu, Arch, Fedora, openSUSE), split into components you can pick from a menu.
#
#   ./install.sh                 interactive menu
#   ./install.sh --all           every component, including the desktop (long: it builds Qt from source)
#   ./install.sh --only shell,nvim
#   ./install.sh --dry-run       show what would happen, change nothing
#   ./install.sh --yes           no questions; answer each with its default
#   ./install.sh --list          list the components
#
# Normally started through the top-level install.sh (which also fetches the repository).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=../lib/pkg.sh
. "$DOTFILES_DIR/lib/pkg.sh"
# shellcheck source=../lib/menu.sh
. "$DOTFILES_DIR/lib/menu.sh"
# shellcheck source=../lib/parts.sh
. "$DOTFILES_DIR/lib/parts.sh"
pkg_detect || { fail "This Linux distribution is not supported yet (Debian/Ubuntu, Arch, Fedora and openSUSE families are)."; exit 1; }

C="$DOTFILES_DIR/config"
ARCH="$(uname -m)"

COMPONENTS=(base shell tmux nvim terminal browsers apps web rust)
MENU_OFF=()
# shellcheck disable=SC2034  # MENU_* are read by lib/menu.sh
if [ "$PKG_FAMILY" = debian ]; then COMPONENTS+=(desktop)
else MENU_OFF=("desktop|Hyprland + Caelestia: only implemented for Debian 13 so far; install Hyprland from your repositories and follow https://github.com/caelestia-dots/caelestia")
fi
declare -A DESC=(
  [base]="Base packages and the JetBrainsMono Nerd Font"
  [shell]="zsh + Oh My Zsh + starship prompt"
  [tmux]="tmux with a cyan/Dracula theme"
  [nvim]="Neovim (NvChad) with tree-sitter parsers and LSP servers"
  [terminal]="Ghostty config (Vim-style keys, dark theme)"
  [browsers]="Terminal browsers: Browsh (Firefox in the terminal), elinks, w3m"
  [apps]="Microsoft Word/Excel/PowerPoint/Outlook/OneDrive (365 web apps in their own window), PDF viewer, VLC, GIMP"
  [web]="Web development: PHP, Composer, MariaDB, Apache, phpMyAdmin (services stay off unless you say yes)"
  [rust]="Rust toolchain via rustup (rustc, cargo, clippy, rustfmt, rust-analyzer)"
  [desktop]="Hyprland + Caelestia shell (Debian 13 only; builds Qt 6.11 from source, 1-2 hours)"
)
DEFAULTS=(base shell tmux nvim terminal)
# the everyday apps are big and pointless on a server: pre-select them only when a graphical session is running
[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && DEFAULTS+=(apps)

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# for lib/menu.sh
# shellcheck disable=SC2034
MENU_TITLE="Linux / $PKG_FAMILY"
# shellcheck disable=SC2034
MENU_ITEMS=("${COMPONENTS[@]}")
# shellcheck disable=SC2034
MENU_DEFAULTS=("${DEFAULTS[@]}")
menu_desc() { printf '%s' "${DESC[$1]}"; }
menu_status() {
  case "$1" in
    base)     fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd" && have rg && have fzf && echo installed ;;
    shell)    linked_here "$HOME/.zshrc" && [ -d "$HOME/.oh-my-zsh" ] && echo installed ;;
    tmux)     linked_here "$HOME/.config/tmux/tmux.conf" && have tmux && echo installed ;;
    nvim)     linked_here "$HOME/.config/nvim/lua/plugins/dotfiles.lua" && have nvim && echo installed ;;
    terminal) linked_here "$HOME/.config/ghostty/config.ghostty" && echo installed ;;
    browsers) have elinks && have w3m && echo installed ;;
    apps)     linked_here "$HOME/.local/bin/m365" && echo installed ;;
    web)      have php && { have mariadb || have mysql; } && echo installed ;;
    rust)     { have rustup || [ -x "$HOME/.cargo/bin/rustup" ]; } && echo installed ;;
    desktop)  [ -e "$HOME/.config/hypr/.rhmatzeka-dotfiles" ] && have qs && echo installed ;;
  esac
  return 0
}
menu_note() {
  case "$1" in
    nvim)    echo "about 500 MB (Node.js, parsers and LSP servers), 5-15 minutes" ;;
    apps)    echo "about 600 MB (Chromium if you have no Chrome/Brave/Edge, VLC, GIMP)" ;;
    web)     echo "about 300 MB; services stay off unless you say yes" ;;
    rust)    echo "about 1 GB (toolchain in ~/.rustup)" ;;
    desktop) echo "1-2 hours: builds Qt 6.11 from source, about 5 GB of disk while building" ;;
  esac
  return 0
}

# ------------------------------------------------------------ arguments ----
SELECTED=(); ALL=0; ONLY=""
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

# ------------------------------------------------------------ preflight ----
preflight() {
  [ "$(uname -s)" = Linux ] || die "This installer is for Linux."
  [ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root: sudo is called only where needed."
  [ "$DRY_RUN" = 1 ] && info "DRY RUN: nothing will be changed."
  ensure_local_bin_in_path
}

select_components() {
  # shellcheck disable=SC2034  # read by run_selected (lib/menu.sh)
  if [ "$ALL" = 1 ]; then SELECTED=("${COMPONENTS[@]}"); return; fi
  if [ -n "$ONLY" ]; then menu_from_list "$ONLY"; return; fi
  menu_choose
}

# ------------------------------------------------------------ helpers ----
download_bin() { # download_bin URL DEST   (a .gz is unpacked; result is made executable)
  local url="$1" dest="$2"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would download $url -> ${dest/#$HOME/~}"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  case "$url" in
    *.gz) curl -fsSL --retry 3 "$url" | gunzip >"$dest" ;;
    *)    curl -fsSL --retry 3 -o "$dest" "$url" ;;
  esac || { fail "download failed: $url"; return 1; }
  chmod +x "$dest"
}

arch_tag() { # arch_tag x64-name arm64-name
  case "$ARCH" in x86_64|amd64) printf '%s' "$1" ;; aarch64|arm64) printf '%s' "$2" ;; *) return 1 ;; esac
}

nerd_font() { # nerd_font Name   e.g. JetBrainsMono  (the .tar.xz is ~7 MB, the .zip ~128 MB)
  local name="$1" dir="$HOME/.local/share/fonts/${1}Nerd"
  if fc-list 2>/dev/null | grep -qi "$name Nerd"; then ok "font already present: $name Nerd Font"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would install the $name Nerd Font"; return 0; fi
  local tmp; tmp="$(mktemp)"
  fetch "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$name.tar.xz" "$tmp" || return 1
  mkdir -p "$dir" && tar -xJf "$tmp" -C "$dir" && rm -f "$tmp"
  fc-cache -f >/dev/null 2>&1
  ok "installed $name Nerd Font"
}

# The folder downloads should go to: the XDG one (it can be localised, e.g. "Unduhan"), else ~/Downloads.
downloads_dir() {
  local d=""
  have xdg-user-dir && d="$(xdg-user-dir DOWNLOAD 2>/dev/null)"
  case "$d" in ""|"$HOME"|"$HOME/") d="$HOME/Downloads" ;; esac
  printf '%s' "$d"
}

# Thunar: put "Open with Microsoft 365" in the right-click menu of PDF and Office files (custom action, one entry in uca.xml)
add_thunar_action() {
  local uca="$HOME/.config/Thunar/uca.xml" snip="$C/thunar/m365-action.xml"
  have thunar || return 0
  [ -f "$snip" ] || return 0
  if [ -f "$uca" ] && grep -q 'm365-open' "$uca"; then ok "Thunar right-click entry already present"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would add the Thunar right-click entry"; return 0; fi
  mkdir -p "$HOME/.config/Thunar"
  if [ -f "$uca" ]; then
    mkdir -p "$BACKUP_ROOT/$STAMP/.config/Thunar" && cp -p "$uca" "$BACKUP_ROOT/$STAMP/.config/Thunar/uca.xml"
    awk -v snip="$snip" '/<\/actions>/ { while ((getline line < snip) > 0) print line } { print }' "$uca" >"$uca.new" && mv "$uca.new" "$uca"
  else
    { printf '<?xml version="1.0" encoding="UTF-8"?>\n<actions>\n'; cat "$snip"; printf '</actions>\n'; } >"$uca"
  fi
  ok "Thunar: right-click > Open with Microsoft 365 (restart Thunar to see it)"
}

# Distribution quirks and services for the web stack.
web_post_install() {
  [ "$DRY_RUN" = 1 ] && { info "[dry-run] would finish the PHP/MariaDB/Apache setup"; return 0; }
  need_sudo
  case "$PKG_FAMILY" in
    arch) # the Arch php package ships its modules disabled, and MariaDB needs its data directory created once
      if [ -f /etc/php/php.ini ]; then
        local e; for e in mysqli pdo_mysql gd intl zip iconv; do
          "${SUDO[@]}" sed -i "s/^;extension=$e\$/extension=$e/" /etc/php/php.ini
        done
      fi
      [ -d /var/lib/mysql/mysql ] || "${SUDO[@]}" mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql >/dev/null 2>&1 \
        || warn "could not initialise the MariaDB data directory"
      ;;
  esac
  local mysvc=mariadb websvc=apache2
  case "$PKG_FAMILY" in arch|fedora) websvc=httpd ;; esac
  if have systemctl && [ -d /run/systemd/system ] && confirm "Start MariaDB and Apache now and at every boot? (Apache listens on port 80)" n; then
    "${SUDO[@]}" systemctl enable --now "$mysvc" "$websvc" || warn "could not start the services; start them by hand"
  else
    info "Services were not started. Start them with: sudo systemctl enable --now $mysvc $websvc"
  fi
}

# ----------------------------------------------------------- components ----
comp_base() {
  step "Base packages"
  pkg_need git curl wget unzip xz ca-certificates buildtools fontconfig jq fzf ripgrep htop
  pkg_optional eza zoxide trash-cli fastfetch btop xdg-user-dirs
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would make sure the Downloads folder exists"
  else
    have xdg-user-dirs-update && xdg-user-dirs-update 2>/dev/null
    mkdir -p "$(downloads_dir)" && ok "downloads folder: $(downloads_dir | sed "s|^$HOME|~|")"
  fi
  nerd_font JetBrainsMono
}

comp_shell() {
  step "Shell: zsh + Oh My Zsh + starship"
  pkg_need zsh git curl
  pkg_optional starship
  if ! have starship; then
    info "starship is not in this release's repositories: using the official installer (into ~/.local/bin)"
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would run the starship installer"
    else mkdir -p "$HOME/.local/bin" && curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" >/dev/null || return 1; fi
  fi
  shell_configs
  if [ "$(basename "${SHELL:-}")" != zsh ] && confirm "Make zsh your default login shell?" n; then
    have chsh || pkg_optional chsh
    run chsh -s "$(command -v zsh)" "$USER"
  fi
}

comp_tmux() {
  step "tmux"
  pkg_need tmux
  backup_and_link "$C/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
}

comp_nvim() {
  step "Neovim (NvChad)"
  pkg_need git curl unzip nodejs npm buildtools
  local v

  # tree-sitter CLI: recent nvim-treesitter builds parsers with it (Debian's package is too old)
  v="$(tree-sitter --version 2>/dev/null | awk '{print $2}')" || v=""   # `|| v=""`: with pipefail+errexit a missing tool would abort here
  if [ -z "$v" ] || ! version_ge "$v" 0.25.0; then
    local t; t="$(arch_tag x64 arm64)" || { fail "unsupported CPU: $ARCH"; return 1; }
    info "installing the tree-sitter CLI into ~/.local/bin"
    download_bin "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-$t.gz" "$HOME/.local/bin/tree-sitter" || return 1
  else ok "tree-sitter CLI $v"; fi

  # Neovim >= 0.12 (NvChad's current tree-sitter integration needs it)
  v="$(nvim --version 2>/dev/null | sed -n '1s/.*v\([0-9.]*\).*/\1/p')" || v=""
  if [ -z "$v" ] || ! version_ge "$v" 0.12.0; then
    local t; t="$(arch_tag x86_64 arm64)" || { fail "unsupported CPU: $ARCH"; return 1; }
    info "installing Neovim (latest release) into ~/.local/opt/nvim"
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would download the Neovim tarball"
    else
      local tmp; tmp="$(mktemp)"
      fetch "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$t.tar.gz" "$tmp" || return 1
      rm -rf "$HOME/.local/opt/nvim" && mkdir -p "$HOME/.local/opt/nvim" "$HOME/.local/bin"
      tar -xzf "$tmp" -C "$HOME/.local/opt/nvim" --strip-components=1 && rm -f "$tmp"
      ln -sfn "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
    fi
  else ok "Neovim $v"; fi

  nvchad_setup
}

comp_terminal() {
  step "Terminal: Ghostty config"
  pkg_need zsh
  backup_and_link "$C/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
  [ "$PKG_FAMILY" = arch ] && pkg_optional ghostty
  if ! have ghostty; then
    warn "Ghostty itself is not installed (no distribution package here); see https://ghostty.org/docs/install/binary"
    warn "The config is in place and will be used once you install it."
  fi
}

comp_browsers() {
  step "Terminal browsers"
  pkg_need elinks w3m
  elinks_configs "$(downloads_dir)"
  pkg_optional firefox
  if ! pkg_have firefox; then warn "Firefox is unavailable here, so Browsh is skipped (elinks and w3m still work)."; return 0; fi
  local t; t="$(arch_tag amd64 arm64)" || { fail "unsupported CPU: $ARCH"; return 1; }
  if [ ! -x "$HOME/.local/opt/browsh/browsh" ]; then
    download_bin "https://github.com/browsh-org/browsh/releases/download/v1.8.2/browsh_1.8.2_linux_$t" "$HOME/.local/opt/browsh/browsh" || return 1
  else ok "Browsh already installed"; fi
  [ "$DRY_RUN" = 1 ] || { mkdir -p "$HOME/.local/bin"; ln -sfn "$HOME/.local/opt/browsh/browsh" "$HOME/.local/bin/browsh"; }
  backup_and_link "$DOTFILES_DIR/bin/firefox-for-browsh" "$HOME/.local/opt/browsh/firefox-for-browsh"
  backup_and_link "$DOTFILES_DIR/bin/web" "$HOME/.local/bin/web"
  info "use it with:  web https://example.com   (Ctrl+Q quits)"
}

comp_apps() {
  step "Everyday apps: Microsoft 365 web apps, PDF viewer, VLC, GIMP"
  # Microsoft Office has no native Linux version: use Microsoft's own web apps in a dedicated browser window.
  local b
  for b in google-chrome-stable google-chrome chromium chromium-browser brave-browser microsoft-edge; do have "$b" && break; b=""; done
  if [ -z "$b" ]; then info "no Chromium-based browser found: installing Chromium for the app windows"; pkg_need chromium || return 1; fi
  backup_and_link "$DOTFILES_DIR/bin/m365" "$HOME/.local/bin/m365"
  backup_and_link "$DOTFILES_DIR/bin/m365-open" "$HOME/.local/bin/m365-open"
  pkg_optional rclone jq python-venv
  # PDF -> .docx converter for "Open with Microsoft 365" (Word on the web cannot open PDFs); kept in its own virtualenv
  local venv="${XDG_DATA_HOME:-$HOME/.local/share}/rhmatzeka-tools/pdf2docx-venv"
  if [ -x "$venv/bin/pdf2docx" ]; then ok "pdf2docx already installed"
  elif [ "$DRY_RUN" = 1 ]; then info "[dry-run] would install pdf2docx into a virtualenv"
  elif have python3 && python3 -m venv "$venv" >/dev/null 2>&1; then
    "$venv/bin/pip" install -q pdf2docx >/dev/null 2>&1 && ok "pdf2docx installed (PDF conversion)" \
      || warn "could not install pdf2docx; PDFs cannot be converted for Word (everything else works)"
  else warn "python3 venv is unavailable; PDFs cannot be converted for Word (everything else works)"; fi
  local f
  for f in "$C"/applications/*.desktop; do
    backup_and_link "$f" "$HOME/.local/share/applications/$(basename "$f")"
  done
  [ "$DRY_RUN" = 1 ] || { have update-desktop-database && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null; true; }
  pkg_optional evince vlc gimp
  add_thunar_action
  info "Word, Excel, PowerPoint, Outlook and OneDrive are now in your app menu (sign in with your Microsoft account)."
  info "Local files: right-click a .docx/.xlsx/.pptx > Open with Microsoft 365 (uploads it to your OneDrive). First run: m365-open --login"
  if [ "$DRY_RUN" != 1 ] && have xdg-mime \
     && confirm "Make 'Open with Microsoft 365' the default for .docx/.xlsx/.pptx (double-click)? This replaces your current default" n; then
    local m
    for m in application/vnd.openxmlformats-officedocument.wordprocessingml.document application/msword \
             application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/vnd.ms-excel \
             application/vnd.openxmlformats-officedocument.presentationml.presentation application/vnd.ms-powerpoint; do
      xdg-mime default microsoft-open-with.desktop "$m"
    done
    ok "double-clicking Office files now opens them in Microsoft 365"
    if confirm "Also for PDF files? Every PDF you open is then converted and uploaded to your OneDrive (you can undo it: xdg-mime default <your PDF viewer>.desktop application/pdf)" n; then
      xdg-mime default microsoft-open-with.desktop application/pdf && ok "double-clicking a PDF now opens it in Word"
    fi
  fi
}

comp_web() {
  step "Web development: PHP, Composer, MariaDB, Apache, phpMyAdmin"
  if [ "$PKG_FAMILY" = debian ] && [ "$DRY_RUN" != 1 ]; then   # phpMyAdmin would otherwise ask questions and try to create a database
    need_sudo
    printf '%s\n' "phpmyadmin phpmyadmin/dbconfig-install boolean false" "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" \
      | "${SUDO[@]}" debconf-set-selections
  fi
  pkg_need php composer mariadb apache
  pkg_optional phpmyadmin
  web_post_install
  info "MariaDB uses your Linux user via the unix socket (sudo mysql). No password was set anywhere."
}

comp_rust() {
  step "Rust (rustup)"
  pkg_need curl ca-certificates buildtools
  rustup_setup
}

comp_desktop() {
  step "Desktop: Hyprland + Caelestia"
  bash "$HERE/debian/desktop.sh"
}

# ----------------------------------------------------------------- main ----
preflight
select_components
menu_confirm || { info "Cancelled."; exit 0; }

run_selected
if [ "$DRY_RUN" != 1 ] && [ ${#OK[@]} -gt 0 ]; then
  [[ " ${OK[*]} " == *" shell "* ]] && info "Open a new terminal, or run: exec zsh"
  [[ " ${OK[*]} " == *" desktop "* ]] && info "Log out and choose the Hyprland session."
  [ -d "$BACKUP_ROOT/$STAMP" ] && info "Files that were replaced are in ${BACKUP_ROOT/#$HOME/~}/$STAMP"
fi
[ ${#FAILED[@]} -eq 0 ]
