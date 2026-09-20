#!/usr/bin/env bash
# Undo what install.sh linked, and put back the files it replaced (from ~/.dotfiles-backup).
#
#   ./uninstall.sh             interactive
#   ./uninstall.sh --dry-run   show what would happen
#   ./uninstall.sh --yes       no questions
#
# It only removes symlinks that still point into this repository. Packages, fonts, Oh My Zsh, the NvChad
# clone and anything built under /opt are left alone; the list at the end says how to remove them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$HERE/../.." && pwd)}"
# shellcheck source=../../lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

# shellcheck disable=SC2034  # ASSUME_YES / DRY_RUN are read by helpers in lib/common.sh
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

[ -s "$MANIFEST" ] || { info "Nothing to undo: no record of installed links at ${MANIFEST/#$HOME/~}."; exit 0; }
step "Links recorded by the installer"
awk -F'\t' '{print "   " $1}' "$MANIFEST" | sed "s|$HOME|~|"
confirm "Remove these links and restore your original files?" y || { info "Cancelled."; exit 0; }

removed=0; restored=0; skipped=0
# newest first, so nested links go before their parents
while IFS=$'\t' read -r dst src backup; do
  [ -n "$dst" ] || continue
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    run rm -f "$dst"; removed=$((removed+1))
    if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
      run mkdir -p "$(dirname "$dst")"; run mv "$backup" "$dst"; restored=$((restored+1))
      ok "restored ${dst/#$HOME/~}"
    else ok "removed ${dst/#$HOME/~}"; fi
  else
    warn "left alone (changed since install): ${dst/#$HOME/~}"; skipped=$((skipped+1))
  fi
done < <(tac "$MANIFEST")

if [ "$DRY_RUN" != 1 ]; then rm -f "$MANIFEST"; rmdir "$STATE_DIR" 2>/dev/null || true; fi
printf '\n'; ok "$removed link(s) removed, $restored original file(s) restored, $skipped skipped."

step "Not removed (delete by hand if you want them gone)"
cat <<MSG
   ~/.oh-my-zsh            Oh My Zsh and its plugins
   ~/.config/nvim          the NvChad starter (only if it has a .rhmatzeka-dotfiles marker), ~/.local/share/nvim
   ~/.local/opt/browsh     Browsh, ~/.local/opt/nvim, ~/.local/bin/{tree-sitter,starship,browsh,nvim}
   ~/.config/hypr          the Caelestia Hyprland config (only if it has a .rhmatzeka-dotfiles marker)
   /opt/qt-6.11.2, /opt/dart-sass, /usr/local/bin/{qs,sass,caelestia}   the desktop build (sudo rm -rf)
   apt packages, fonts in ~/.local/share/fonts
MSG
