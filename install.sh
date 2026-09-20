#!/usr/bin/env bash
# rhmatzeka/dotfile - installer entry point.
#
#   bash <(curl -fsSL https://dotfiles.rahmateka.my.id)
#   bash <(curl -fsSL https://dotfiles.rahmateka.my.id) --dry-run --all
#
# `bash <(...)` instead of `curl | bash` keeps the terminal attached, so the menu and sudo prompts work.
# This file only detects the OS, fetches the repository to ~/.dotfiles and hands over to the
# installer for that platform. Everything it will do is printed first; --dry-run changes nothing.
set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/rhmatzeka/dotfile.git}"
BRANCH="${DOTFILES_BRANCH:-main}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

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
PLATFORM=""
case "$(uname -s)" in
  Darwin)
    bad "macOS is not supported yet."
    say "Only Debian/Ubuntu is implemented and tested. Contributions for other systems are welcome:"
    say "https://github.com/rhmatzeka/dotfile/issues"
    exit 1 ;;
  Linux)
    ids=" $(. /etc/os-release 2>/dev/null; printf '%s %s' "${ID:-}" "${ID_LIKE:-}") "
    case "$ids" in
      *" debian "*|*" ubuntu "*) PLATFORM=debian ;;
      *) bad "This Linux distribution is not supported yet (found:$ids)."
         say "Only Debian/Ubuntu is implemented and tested."
         exit 1 ;;
    esac ;;
  *) bad "Unsupported OS: $(uname -s)"; exit 1 ;;
esac
good "Detected: Linux / $PLATFORM"

# --- where does the repository live? ------------------------------------------
# Run from a checkout (bash ./install.sh)? Use it as is. Run through curl? Fetch it to ~/.dotfiles.
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ] && [ -f "$(dirname "$SELF")/linux/$PLATFORM/install.sh" ] && [ -z "${DOTFILES_FORCE_CLONE:-}" ]; then
  DOTFILES_DIR="$(cd "$(dirname "$SELF")" && pwd)"
  good "Using this checkout: $DOTFILES_DIR"
else
  if ! command -v git >/dev/null 2>&1; then
    say "git is needed to fetch the repository."
    command -v sudo >/dev/null 2>&1 || { bad "git and sudo are both missing; install git first."; exit 1; }
    sudo apt-get update && sudo apt-get install -y git
  fi
  if [ -d "$DOTFILES_DIR/.git" ]; then
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
TARGET="$DOTFILES_DIR/linux/$PLATFORM/$ACTION.sh"
[ -f "$TARGET" ] || { bad "Missing $TARGET"; exit 1; }
printf '\n'
exec bash "$TARGET" "$@"
