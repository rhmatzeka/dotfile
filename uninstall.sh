#!/usr/bin/env bash
# Undo what install.sh linked (your original files come back from ~/.dotfiles-backup).
#
#   bash <(curl -fsSL https://dotfiles.rahmateka.my.id/uninstall.sh)
#
# Packages, fonts and anything built under /opt are left alone; the uninstaller lists them at the end.
set -euo pipefail

SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ] && [ -f "$(dirname "$SELF")/install.sh" ]; then
  exec bash "$(dirname "$SELF")/install.sh" --uninstall "$@"
fi
exec bash <(curl -fsSL "${DOTFILES_INSTALL_URL:-https://dotfiles.rahmateka.my.id}") --uninstall "$@"
