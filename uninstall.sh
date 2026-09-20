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

# Started through curl: fetch the installer from the repository itself (works even without the short domain).
URL="${DOTFILES_INSTALL_URL:-https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP" || { echo "  ✖ could not download $URL" >&2; exit 1; }
bash "$TMP" --uninstall "$@"
