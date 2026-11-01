#!/usr/bin/env bash
# Undo what install.sh linked on macOS. The undo logic is the same as on Linux (it only reads the record of links
# the installer made), so this hands over to linux/uninstall.sh, which is kept bash 3.2 compatible for that reason.
#
#   ./uninstall.sh             interactive
#   ./uninstall.sh --dry-run   show what would happen
#   ./uninstall.sh --yes       no questions
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$HERE/.." && pwd)}"
exec "${BASH:-bash}" "$DOTFILES_DIR/linux/uninstall.sh" "$@"
