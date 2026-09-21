# shellcheck shell=bash
# Shared helpers for the installers. Source this file; do not execute it.
#
# Conventions
#   DRY_RUN=1     print what would happen, change nothing
#   ASSUME_YES=1  answer every question with its default (never turns a "no" default into a "yes")
#   Every symlink we create is recorded in a manifest so uninstall can undo exactly that, and any file
#   we would replace is moved to ~/.dotfiles-backup/<timestamp>/ first.

DOTFILES_DIR="${DOTFILES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rhmatzeka-dotfile}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rhmatzeka-dotfiles"
MANIFEST="$STATE_DIR/links.tsv"
BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
STAMP="${DOTFILES_STAMP:-$(date +%Y%m%d-%H%M%S)}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

# ---------------------------------------------------------------- output ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_CYAN=$'\033[38;2;0;217;255m'; C_GREEN=$'\033[38;2;80;250;123m'; C_PINK=$'\033[38;2;255;121;198m'
  C_RED=$'\033[38;2;255;85;85m'; C_YELLOW=$'\033[38;2;241;250;140m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_CYAN=""; C_GREEN=""; C_PINK=""; C_RED=""; C_YELLOW=""; C_DIM=""; C_BOLD=""; C_OFF=""
fi

step() { printf '\n%s  == %s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_OFF"; }
ok()   { printf '  %s✔%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
info() { printf '  %s▸%s %s\n' "$C_CYAN" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
fail() { printf '  %s✖%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { fail "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# run CMD...  -> executes, or just prints under DRY_RUN
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_OFF" "$*"
  else
    "$@"
  fi
}

# interactive  -> 0 when a person can answer: stdin is a terminal, or /dev/tty can really be opened
interactive() { [ -t 0 ] || { : </dev/tty; } 2>/dev/null; }

# confirm "question" [y|n]  -> 0 for yes. Without a terminal, or with --yes, the default answer is used.
confirm() {
  local q="$1" def="${2:-n}" ans hint="[y/N]"
  [ "$def" = y ] && hint="[Y/n]"
  if [ "$ASSUME_YES" = 1 ] || ! interactive; then
    [ "$def" = y ]; return
  fi
  printf '  %s?%s %s %s ' "$C_PINK" "$C_OFF" "$q" "$hint" >&2
  read -r ans </dev/tty || ans=""
  case "${ans:-$def}" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ------------------------------------------------------------------ sudo ----
SUDO=()
need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then SUDO=(); return 0; fi
  have sudo || die "sudo is required for this step, but it is not installed."
  SUDO=(sudo)
}

# ------------------------------------------------------------------- apt ----
APT_UPDATED=0
apt_update_once() {
  [ "$APT_UPDATED" = 1 ] && return 0
  need_sudo
  run "${SUDO[@]}" apt-get update
  APT_UPDATED=1
}

# pkg_installed PKG  -> 0 only when dpkg says "ii" (fully installed). `dpkg -s` also succeeds for packages that are
# merely unpacked or half-configured after a failed run, which would hide the failure.
pkg_installed() { dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" 2>/dev/null | grep -q '^ii'; }

# apt_need pkg...   install only what is missing (release: default suite)
apt_need() {
  local missing=() p
  for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
  if [ ${#missing[@]} -eq 0 ]; then ok "already installed: $*"; return 0; fi
  need_sudo; apt_update_once
  info "apt install: ${missing[*]}"
  run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# apt_need_from SUITE pkg...   e.g. apt_need_from trixie-backports hyprland
apt_need_from() {
  local suite="$1"; shift
  need_sudo; apt_update_once
  info "apt install -t $suite: $*"
  run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -t "$suite" "$@"
}

# apt_optional pkg...   install the ones this release has; warn about the rest instead of failing
apt_optional() {
  local p cand
  for p in "$@"; do
    cand="$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')"
    if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then warn "not available on this release, skipped: $p"
    else apt_need "$p" || warn "could not install $p (optional, continuing)"; fi
  done
}

# ----------------------------------------------------------------- files ----
# backup_and_link SRC DST
backup_and_link() {
  local src="$1" dst="$2" backup=""
  [ -e "$src" ] || { warn "missing in repo, skipped: $src"; return 0; }
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then ok "already linked: ${dst/#$HOME/~}"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then
    if [ -e "$dst" ] || [ -L "$dst" ]; then info "[dry-run] would back up ${dst/#$HOME/~} and link it to the repo"
    else info "[dry-run] would link ${dst/#$HOME/~}"; fi
    return 0
  fi
  mkdir -p "$(dirname "$dst")" "$STATE_DIR"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    backup="$BACKUP_ROOT/$STAMP/${dst#"$HOME"/}"
    mkdir -p "$(dirname "$backup")"
    mv "$dst" "$backup"
    info "backed up ${dst/#$HOME/~} -> ${backup/#$HOME/~}"
  fi
  ln -sfn "$src" "$dst"
  printf '%s\t%s\t%s\n' "$dst" "$src" "$backup" >>"$MANIFEST"
  ok "linked ${dst/#$HOME/~}"
}

# fetch URL DEST   (curl with retries; creates parent dir)
fetch() {
  local url="$1" dest="$2"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would download $url"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  # fail instead of hanging forever: give up if the connection stalls (under 1 KB/s for 60 s)
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --speed-limit 1024 --speed-time 60 -o "$dest" "$url" \
    || { fail "download failed: $url"; return 1; }
}

# git_clone URL DEST [REF]  -> clone once; if it exists, leave it alone
git_clone() {
  local url="$1" dest="$2" ref="${3:-}"
  if [ -d "$dest/.git" ]; then ok "already cloned: ${dest/#$HOME/~}"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would clone $url"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  if [ -n "$ref" ]; then
    git clone -q "$url" "$dest" && git -C "$dest" checkout -q "$ref"
  else
    git clone -q --depth 1 "$url" "$dest"
  fi
}

# version_ge A B  -> 0 when A >= B (dotted numbers)
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# os_field NAME  -> value from /etc/os-release
os_field() { ( . /etc/os-release 2>/dev/null && eval "printf '%s' \"\${$1:-}\"" ); }

# Path helpers so scripts can be tested against a different HOME.
ensure_local_bin_in_path() {
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
}
