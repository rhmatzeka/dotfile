#!/usr/bin/env bash
# rhmatzeka/dotfile - installer entry point.
#
#   bash <(curl -fsSL https://dotfiles.rahmateka.my.id)
#   bash <(curl -fsSL https://dotfiles.rahmateka.my.id) --dry-run --all
#
# `bash <(...)` instead of `curl | bash` keeps the terminal attached, so the menu and sudo prompts work.
# This file only detects the distribution family, fetches the repository to ~/.local/share/rhmatzeka-dotfile and hands over to the
# installer for that platform. Everything it will do is printed first; --dry-run changes nothing.
set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/rhmatzeka/dotfile.git}"
BRANCH="${DOTFILES_BRANCH:-main}"
# Not ~/.dotfiles: many people keep their own dotfiles repository there and we must never pull into it.
DOTFILES_DIR="${DOTFILES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rhmatzeka-dotfile}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  CY=$'\033[38;2;0;217;255m'; GR=$'\033[38;2;80;250;123m'; RD=$'\033[38;2;255;85;85m'; DM=$'\033[2m'; BD=$'\033[1m'; OFF=$'\033[0m'
else
  CY=""; GR=""; RD=""; DM=""; BD=""; OFF=""
fi
say()  { printf '  %s▸%s %s\n' "$CY" "$OFF" "$*"; }
good() { printf '  %s✔%s %s\n' "$GR" "$OFF" "$*"; }
bad()  { printf '  %s✖%s %s\n' "$RD" "$OFF" "$*" >&2; }

ACTION=install
if [ "${1:-}" = "--uninstall" ]; then ACTION=uninstall; shift; fi

printf '\n%s%s  dotfiles %s%s\n' "$BD" "$CY" "$ACTION" "$OFF"
printf '%s  https://github.com/rhmatzeka/dotfile%s\n\n' "$DM" "$OFF"

# --- which OS? ---------------------------------------------------------------
# Only Linux families are implemented: debian (Debian, Ubuntu, Mint...), arch (Arch, Manjaro, EndeavourOS...),
# fedora (Fedora, RHEL-likes), suse (openSUSE). The real work is in linux/install.sh; this only says hello.
FAMILY=""
case "$(uname -s)" in
  Darwin)
    bad "macOS is not supported yet."
    say "Supported: Debian/Ubuntu, Arch, Fedora and openSUSE families. Contributions are welcome:"
    say "https://github.com/rhmatzeka/dotfile/issues"
    exit 1 ;;
  Linux)
    ids=" $(. /etc/os-release 2>/dev/null; printf '%s %s' "${ID:-}" "${ID_LIKE:-}") "
    case "$ids" in
      *" debian "*|*" ubuntu "*)              FAMILY=debian ;;
      *" arch "*)                             FAMILY=arch ;;
      *" fedora "*|*" rhel "*|*" centos "*)   FAMILY=fedora ;;
      *" suse "*|*" opensuse "*|*" sles "*)   FAMILY=suse ;;
      *) bad "This Linux distribution is not supported yet (found:$ids)."
         say "Supported: Debian/Ubuntu, Arch, Fedora and openSUSE families."
         exit 1 ;;
    esac ;;
  *) bad "Unsupported OS: $(uname -s)"; exit 1 ;;
esac
good "Detected: Linux / $FAMILY family"

# --- where does the repository live? ------------------------------------------
# Run from a checkout (bash ./install.sh)? Use it as is. Run through curl? Fetch it to ~/.local/share/rhmatzeka-dotfile.
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ] && [ -f "$(dirname "$SELF")/linux/install.sh" ] && [ -z "${DOTFILES_FORCE_CLONE:-}" ]; then
  DOTFILES_DIR="$(cd "$(dirname "$SELF")" && pwd)"
  good "Using this checkout: $DOTFILES_DIR"
else
  if ! command -v git >/dev/null 2>&1; then
    say "git is needed to fetch the repository."
    command -v sudo >/dev/null 2>&1 || { bad "git and sudo are both missing; install git first."; exit 1; }
    case "$FAMILY" in
      debian) sudo apt-get update && sudo apt-get install -y git ;;
      arch)   sudo pacman -S --needed --noconfirm git ;;
      fedora) sudo dnf install -y git ;;
      suse)   sudo zypper --non-interactive install git ;;
    esac
  fi
  if [ -d "$DOTFILES_DIR/.git" ]; then
    origin="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || true)"
    case "${origin%.git}" in
      "${REPO_URL%.git}") ;;
      *) bad "$DOTFILES_DIR is a git repository of something else (origin: ${origin:-none}); not touching it."
         say "Set DOTFILES_DIR to another directory and run again."; exit 1 ;;
    esac
    say "Updating $DOTFILES_DIR"
    if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then
      say "Local changes found in $DOTFILES_DIR: leaving them untouched and not updating."
    else
      git -C "$DOTFILES_DIR" fetch -q origin "$BRANCH" && git -C "$DOTFILES_DIR" checkout -q "$BRANCH" && git -C "$DOTFILES_DIR" pull -q --ff-only origin "$BRANCH" \
        || say "Could not fast-forward; continuing with what is already there."
    fi
  else
    say "Fetching $REPO_URL -> $DOTFILES_DIR"
    git clone -q --branch "$BRANCH" "$REPO_URL" "$DOTFILES_DIR"
  fi
fi

export DOTFILES_DIR
TARGET="$DOTFILES_DIR/linux/$ACTION.sh"
[ -f "$TARGET" ] || { bad "Missing $TARGET"; exit 1; }
printf '\n'
exec bash "$TARGET" "$@"
