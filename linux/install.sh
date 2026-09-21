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
pkg_detect || { fail "This Linux distribution is not supported yet (Debian/Ubuntu, Arch, Fedora and openSUSE families are)."; exit 1; }

C="$DOTFILES_DIR/config"
ARCH="$(uname -m)"

COMPONENTS=(base shell tmux nvim terminal browsers apps web rust)
[ "$PKG_FAMILY" = debian ] && COMPONENTS+=(desktop)
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

list_components() {
  local c mark
  for c in "${COMPONENTS[@]}"; do
    mark=" "; for d in "${DEFAULTS[@]}"; do [ "$c" = "$d" ] && mark="*"; done
    printf '  %s %-9s %s\n' "$mark" "$c" "${DESC[$c]}"
  done
  printf '\n  * = selected by default\n'
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
    --list)       list_components; exit 0 ;;
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
  local c ans n
  if [ "$ALL" = 1 ]; then SELECTED=("${COMPONENTS[@]}"); return; fi
  if [ -n "$ONLY" ]; then
    IFS=',' read -ra SELECTED <<<"$ONLY"
    for c in "${SELECTED[@]}"; do
      if [ "$c" = desktop ] && [ "$PKG_FAMILY" != debian ]; then
        die "the desktop component (Hyprland + Caelestia) is only implemented for Debian 13 so far; on Arch/Fedora/openSUSE install Hyprland from your repositories and follow https://github.com/caelestia-dots/caelestia"
      fi
      [[ " ${COMPONENTS[*]} " == *" $c "* ]] || die "unknown component: $c (see --list)"
    done
    return
  fi
  if [ "$ASSUME_YES" = 1 ] || ! interactive; then SELECTED=("${DEFAULTS[@]}"); return; fi
  printf '\n  Components:\n\n'
  n=1; for c in "${COMPONENTS[@]}"; do
    local mark=" "; for d in "${DEFAULTS[@]}"; do [ "$c" = "$d" ] && mark="*"; done
    printf '   %d. [%s] %-9s %s\n' "$n" "$mark" "$c" "${DESC[$c]}"; n=$((n+1))
  done
  printf '\n  Pick numbers (e.g. "1 2 4"), "a" for all, Enter for the defaults (*), "q" to quit: ' >&2
  read -r ans </dev/tty || ans=""
  case "$ans" in
    "") SELECTED=("${DEFAULTS[@]}") ;;
    a|A) SELECTED=("${COMPONENTS[@]}") ;;
    q|Q) info "Nothing installed."; exit 0 ;;
    *) for n in ${ans//,/ }; do
         [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#COMPONENTS[@]}" ] || die "not a valid choice: $n"
         SELECTED+=("${COMPONENTS[$((n-1))]}")
       done ;;
  esac
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
  git_clone https://github.com/ohmyzsh/ohmyzsh "$HOME/.oh-my-zsh"
  git_clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  git_clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  backup_and_link "$C/zsh/zshrc" "$HOME/.zshrc"
  backup_and_link "$C/starship/starship.toml" "$HOME/.config/starship.toml"
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

  # the NvChad starter, unless the user already has an nvim config of their own
  local cfg="$HOME/.config/nvim" marker="$HOME/.config/nvim/.rhmatzeka-dotfiles"
  if [ -e "$cfg" ] && [ ! -e "$marker" ]; then
    warn "an nvim config already exists at ~/.config/nvim: leaving it untouched."
    warn "Add $C/nvim/dotfiles.lua to its lua/plugins/ if you want the extra parsers/LSP."
    return 0
  fi
  if [ ! -e "$cfg" ]; then
    info "cloning the NvChad starter"
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would clone NvChad/starter"
    else git clone -q --depth 1 https://github.com/NvChad/starter "$cfg" && rm -rf "$cfg/.git" && : >"$marker"; fi
  fi
  [ "$DRY_RUN" = 1 ] || mkdir -p "$cfg/lua/plugins"
  backup_and_link "$C/nvim/dotfiles.lua" "$cfg/lua/plugins/dotfiles.lua"

  [ "$DRY_RUN" = 1 ] && { info "[dry-run] would sync plugins, build tree-sitter parsers and install LSP servers"; return 0; }
  info "syncing plugins (first run, a minute or two)"
  timeout 600 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || warn "plugin sync reported a problem; it will retry when you open nvim"
  info "building tree-sitter parsers"
  timeout 600 nvim --headless "+Lazy load nvim-treesitter" "+lua local ok,e=pcall(function() require('nvim-treesitter').install(dofile(vim.fn.stdpath('config')..'/lua/plugins/dotfiles.lua')[1].opts.ensure_installed):wait(540000) end) if not ok then print(e) end" +qa >/dev/null 2>&1 \
    || warn "parser build reported a problem; check :checkhealth nvim-treesitter"
  info "installing LSP servers and formatters (Mason)"
  timeout 900 nvim --headless "+Lazy load mason.nvim" "+MasonInstall $(paste -sd' ' "$C/nvim/mason-packages")" "+qall" >/dev/null 2>&1 \
    || warn "Mason reported a problem; run :Mason inside nvim to see which package failed"
  ok "Neovim is ready"
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
  # elinks saves into the current directory by default; point it at the Downloads folder (absolute path, this file is per machine)
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would write ~/.config/elinks/local.conf (download folder)"
  else
    mkdir -p "$HOME/.config/elinks" "$(downloads_dir)"
    printf '## written by rhmatzeka/dotfile: where elinks saves downloads\nset document.download.directory = "%s/"\n' "$(downloads_dir)" >"$HOME/.config/elinks/local.conf"
  fi
  backup_and_link "$C/elinks/elinks.conf" "$HOME/.config/elinks/elinks.conf"
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
  pkg_optional rclone jq
  local f
  for f in "$C"/applications/*.desktop; do
    backup_and_link "$f" "$HOME/.local/share/applications/$(basename "$f")"
  done
  [ "$DRY_RUN" = 1 ] || { have update-desktop-database && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null; true; }
  pkg_optional evince vlc gimp
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
  if have rustup || [ -x "$HOME/.cargo/bin/rustup" ]; then
    ok "rustup already installed"
  elif [ "$DRY_RUN" = 1 ]; then info "[dry-run] would run the official rustup installer (rustup.rs)"
  else
    info "running the official rustup installer (stable toolchain, no changes to your shell files)"
    curl -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile default \
      || { fail "rustup installer failed"; return 1; }
  fi
  if [ "$DRY_RUN" != 1 ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    rustup component add rust-analyzer clippy rustfmt >/dev/null 2>&1 || warn "could not add rust-analyzer/clippy/rustfmt"
    ok "$(rustc --version 2>/dev/null)"
  fi
  info "\$HOME/.cargo/bin must be on your PATH (the zsh config from this repo does that)."
}

comp_desktop() {
  step "Desktop: Hyprland + Caelestia"
  bash "$HERE/debian/desktop.sh"
}

# ----------------------------------------------------------------- main ----
preflight
select_components
[ "${#SELECTED[@]}" -gt 0 ] || { info "Nothing selected."; exit 0; }
printf '\n  Installing: %s\n' "${SELECTED[*]}"
[ "$DRY_RUN" = 1 ] || confirm "Continue?" y || { info "Cancelled."; exit 0; }

# keep components in canonical order, run each in its own subshell so one failure does not stop the rest
OK=(); FAILED=()
for c in "${COMPONENTS[@]}"; do
  [[ " ${SELECTED[*]} " == *" $c "* ]] || continue
  # NOT inside `if (...)`: bash ignores `set -e` in a condition context, which would let a failed apt run
  # carry on and be reported as success. A plain subshell followed by $? keeps errexit active inside it.
  ( set -e; "comp_$c" )
  rc=$?
  if [ "$rc" -eq 0 ]; then OK+=("$c"); else FAILED+=("$c"); fail "component failed (exit $rc): $c"; fi
done

printf '\n'
[ ${#OK[@]} -gt 0 ]     && ok "Done: ${OK[*]}"
[ ${#FAILED[@]} -gt 0 ] && fail "Failed: ${FAILED[*]} (run again with --only ${FAILED[*]// /,} after fixing the cause)"
if [ "$DRY_RUN" != 1 ] && [ ${#OK[@]} -gt 0 ]; then
  [[ " ${OK[*]} " == *" shell "* ]] && info "Open a new terminal, or run: exec zsh"
  [[ " ${OK[*]} " == *" desktop "* ]] && info "Log out and choose the Hyprland session."
  [ -d "$BACKUP_ROOT/$STAMP" ] && info "Files that were replaced are in ${BACKUP_ROOT/#$HOME/~}/$STAMP"
fi
[ ${#FAILED[@]} -eq 0 ]
