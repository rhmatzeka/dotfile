#!/usr/bin/env bash
# Install the dotfiles into a CLEAN Debian or Ubuntu root filesystem and check the result.
# This is how the "tested from scratch" claims in the README were produced.
#
#   tests/clean-rootfs.sh debian trixie
#   tests/clean-rootfs.sh ubuntu noble
#   tests/clean-rootfs.sh ubuntu resolute --only shell,tmux
#   tests/clean-rootfs.sh debian trixie --keep     keep the rootfs afterwards (default: delete it)
#
# Needs (on a Debian/Ubuntu host): sudo, debootstrap, systemd-container; ubuntu-keyring for Ubuntu targets.
# It builds a minimal system under /var/lib/machines, creates a normal user with sudo, runs ./install.sh as that
# user inside systemd-nspawn, then runs the same checks a person would (versions, fonts, tmux/zsh, Neovim colours).
set -uo pipefail

DISTRO="${1:-}"; CODENAME="${2:-}"
[ -n "$DISTRO" ] && [ -n "$CODENAME" ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift 2
KEEP=0; ONLY="base,shell,tmux,terminal,browsers,nvim"
while [ $# -gt 0 ]; do
  case "$1" in --keep) KEEP=1 ;; --only) shift; ONLY="${1:-}" ;; --only=*) ONLY="${1#--only=}" ;; *) echo "unknown option: $1" >&2; exit 2 ;; esac
  shift
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="/var/lib/machines/dotfiles-test-$DISTRO-$CODENAME"
case "$DISTRO" in
  debian) MIRROR=http://deb.debian.org/debian; COMPONENTS=main ;;
  ubuntu) MIRROR=http://archive.ubuntu.com/ubuntu; COMPONENTS=main,universe ;;
  *) echo "distro must be debian or ubuntu" >&2; exit 2 ;;
esac
for t in sudo debootstrap systemd-nspawn git; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 2; }; done

nspawn() { sudo systemd-nspawn -q --timezone=off -D "$ROOT" "$@"; }   # --timezone=off: tzdata cannot replace a bind-mounted /etc/localtime
cleanup() { [ "$KEEP" = 1 ] && { echo "kept: $ROOT"; return; }; sudo rm -rf "$ROOT"; }
trap cleanup EXIT

echo "== building a minimal $DISTRO $CODENAME in $ROOT"
sudo rm -rf "$ROOT"; sudo mkdir -p "$ROOT"
SCRIPT=""; [ -e "/usr/share/debootstrap/scripts/$CODENAME" ] || SCRIPT=/usr/share/debootstrap/scripts/gutsy   # newer suites reuse an old script
sudo debootstrap --variant=minbase --components="$COMPONENTS" --include=sudo,ca-certificates,curl,git,locales,gnupg \
  "$CODENAME" "$ROOT" "$MIRROR" $SCRIPT >/dev/null || { echo "debootstrap failed"; exit 1; }

nspawn --pipe /bin/bash -c 'useradd -m -s /bin/bash tester; echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester; chmod 440 /etc/sudoers.d/tester'
sudo git clone -q "$REPO" "$ROOT/home/tester/dotfile"
nspawn --pipe /bin/bash -c 'chown -R tester:tester /home/tester'

echo "== installing: $ONLY"
nspawn --user=tester --chdir=/home/tester/dotfile --setenv=HOME=/home/tester --setenv=NO_COLOR=1 --pipe \
  /bin/bash -c "./install.sh --yes --only $ONLY"
RC=$?
echo "== installer exit code: $RC"

echo "== checks"
nspawn --user=tester --chdir=/home/tester --setenv=HOME=/home/tester --setenv=TERM=xterm-256color --pipe /bin/bash -c '
export PATH=$HOME/.local/bin:$PATH
for c in zsh tmux nvim tree-sitter starship elinks; do command -v "$c" >/dev/null && printf "  %-12s %s\n" "$c" "$("$c" --version 2>&1 | head -1 | cut -c1-48)"; done
printf "  nerd font entries: %s\n" "$(fc-list | grep -ci "JetBrainsMono Nerd")"
printf "  nvim parsers: %s, mason packages: %s\n" "$(ls ~/.local/share/nvim/site/parser 2>/dev/null | wc -l)" "$(ls ~/.local/share/nvim/mason/packages 2>/dev/null | wc -l)"
' 2>&1 | grep -v 'unable to resolve host'

echo "== uninstall"
nspawn --user=tester --chdir=/home/tester/dotfile --setenv=HOME=/home/tester --setenv=NO_COLOR=1 --pipe \
  /bin/bash -c './uninstall.sh --yes 2>&1 | grep -E "removed|restored|Nothing|✖"'
exit "$RC"
