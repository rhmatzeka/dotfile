#!/usr/bin/env bash
# Install the dotfiles into a CLEAN Debian, Ubuntu, Arch, Fedora or openSUSE root filesystem and check the result.
# This is how the "tested from scratch" claims in the README were produced.
#
#   tests/clean-rootfs.sh debian trixie
#   tests/clean-rootfs.sh ubuntu noble
#   tests/clean-rootfs.sh ubuntu resolute --only shell,tmux
#   tests/clean-rootfs.sh arch latest
#   tests/clean-rootfs.sh fedora 44
#   tests/clean-rootfs.sh opensuse tumbleweed
#   tests/clean-rootfs.sh debian trixie --keep     keep the rootfs afterwards (default: delete it)
#
# Needs: sudo, systemd-container (systemd-nspawn), git, curl, tar, python3; debootstrap (+ ubuntu-keyring) for
# Debian/Ubuntu targets; zstd for Arch. Arch, Fedora and openSUSE start from their official root filesystem images.
# It builds a minimal system under /var/lib/machines, creates a normal user with sudo, runs ./install.sh as that
# user inside systemd-nspawn, then runs the same checks a person would (versions, fonts, tmux/zsh, Neovim colours).
set -uo pipefail

DISTRO="${1:-}"; CODENAME="${2:-}"
[ -n "$DISTRO" ] && [ -n "$CODENAME" ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift 2
KEEP=0; ONLY="base,shell,tmux,terminal,browsers,nvim,apps"
while [ $# -gt 0 ]; do
  case "$1" in --keep) KEEP=1 ;; --only) shift; ONLY="${1:-}" ;; --only=*) ONLY="${1#--only=}" ;; *) echo "unknown option: $1" >&2; exit 2 ;; esac
  shift
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="/var/lib/machines/dotfiles-test-$DISTRO-$CODENAME"
case "$DISTRO" in
  debian) MIRROR=http://deb.debian.org/debian; COMPONENTS=main ;;
  ubuntu) MIRROR=http://archive.ubuntu.com/ubuntu; COMPONENTS=main,universe ;;
  arch|fedora|opensuse) ;;
  *) echo "distro must be debian, ubuntu, arch, fedora or opensuse" >&2; exit 2 ;;
esac
for t in sudo systemd-nspawn git curl; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 2; }; done
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-tests"; mkdir -p "$CACHE"

nspawn() { sudo systemd-nspawn -q --timezone=off -D "$ROOT" "$@"; }   # --timezone=off: tzdata cannot replace a bind-mounted /etc/localtime
cleanup() { [ "$KEEP" = 1 ] && { echo "kept: $ROOT"; return; }; sudo rm -rf "$ROOT"; }
trap cleanup EXIT

echo "== building a minimal $DISTRO $CODENAME in $ROOT"
sudo rm -rf "$ROOT"; sudo mkdir -p "$ROOT"

# unpack an OCI image (Fedora's official container tarball): every layer, in order, into $ROOT
unpack_oci() {
  local tmp; tmp="$(mktemp -d)"; tar -xf "$1" -C "$tmp"
  python3 - "$tmp" <<'PY' | while read -r layer; do sudo tar -xf "$tmp/$layer" -C "$ROOT"; done
import json, sys, os
d = sys.argv[1]
def blob(digest): return os.path.join("blobs", digest.replace(":", "/"))
idx = json.load(open(os.path.join(d, "index.json")))
man = json.load(open(os.path.join(d, blob(idx["manifests"][0]["digest"]))))
if "layers" not in man:  # image index -> first manifest
    man = json.load(open(os.path.join(d, blob(man["manifests"][0]["digest"]))))
for l in man["layers"]: print(blob(l["digest"]))
PY
  rm -rf "$tmp"
}

case "$DISTRO" in
  debian|ubuntu)
    command -v debootstrap >/dev/null || { echo "missing tool: debootstrap" >&2; exit 2; }
    SCRIPT=""; [ -e "/usr/share/debootstrap/scripts/$CODENAME" ] || SCRIPT=/usr/share/debootstrap/scripts/gutsy   # newer suites reuse an old script
    sudo debootstrap --variant=minbase --components="$COMPONENTS" --include=sudo,ca-certificates,curl,git,locales,gnupg \
      "$CODENAME" "$ROOT" "$MIRROR" $SCRIPT >/dev/null || { echo "debootstrap failed"; exit 1; } ;;
  arch)
    F="$CACHE/archlinux-bootstrap-x86_64.tar.zst"
    [ -s "$F" ] || curl -fL --retry 3 -o "$F" https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.zst || exit 1
    sudo tar --zstd -xf "$F" -C "$ROOT" --strip-components=1 || exit 1
    sudo sed -i 's/^#Server = https:\/\/geo.mirror/Server = https:\/\/geo.mirror/' "$ROOT/etc/pacman.d/mirrorlist"
    nspawn --pipe /bin/bash -c 'pacman-key --init >/dev/null 2>&1 && pacman-key --populate archlinux >/dev/null 2>&1 && pacman -Syu --noconfirm sudo git curl >/dev/null' || { echo "arch prep failed"; exit 1; } ;;
  fedora)
    F="$CACHE/fedora-$CODENAME.oci.tar.xz"
    [ -s "$F" ] || curl -fL --retry 3 -o "$F" "https://dl.fedoraproject.org/pub/fedora/linux/releases/$CODENAME/Container/x86_64/images/$(curl -s "https://dl.fedoraproject.org/pub/fedora/linux/releases/$CODENAME/Container/x86_64/images/" | grep -o "Fedora-Container-Base-Generic-$CODENAME-[0-9.]*x86_64.oci.tar.xz" | head -1)" || exit 1
    unpack_oci "$F"
    nspawn --pipe /bin/bash -c 'dnf install -y sudo git curl >/dev/null' || { echo "fedora prep failed"; exit 1; } ;;
  opensuse)
    F="$CACHE/opensuse-tumbleweed.tar.xz"
    [ -s "$F" ] || curl -fL -C - --retry 8 --retry-all-errors --retry-delay 3 -o "$F" https://download.opensuse.org/tumbleweed/appliances/opensuse-tumbleweed-image.x86_64-lxc.tar.xz || exit 1
    sudo tar -xf "$F" -C "$ROOT" || exit 1
    nspawn --pipe /bin/bash -c 'zypper --non-interactive --gpg-auto-import-keys refresh >/dev/null && zypper --non-interactive install sudo git curl >/dev/null' || { echo "opensuse prep failed"; exit 1; } ;;
esac

nspawn --pipe /bin/bash -c 'useradd -m -s /bin/bash tester; echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester; chmod 440 /etc/sudoers.d/tester'
# copy the working tree (not `git clone`, which would test only what is already committed)
sudo mkdir -p "$ROOT/home/tester/dotfile" && sudo tar -C "$REPO" --exclude=.git -cf - . | sudo tar -C "$ROOT/home/tester/dotfile" -xf -
nspawn --pipe /bin/bash -c 'chown -R tester:tester /home/tester'

echo "== installing: $ONLY"
nspawn --user=tester --chdir=/home/tester/dotfile --setenv=HOME=/home/tester --setenv=NO_COLOR=1 --pipe \
  /bin/bash -c "./install.sh --yes --only $ONLY"
RC=$?
echo "== installer exit code: $RC"

echo "== checks"
nspawn --user=tester --chdir=/home/tester --setenv=HOME=/home/tester --setenv=TERM=xterm-256color --pipe /bin/bash -c '
export PATH=$HOME/.local/bin:$HOME/.cargo/bin:$PATH
for c in zsh tmux nvim tree-sitter starship elinks php composer mariadb rustc cargo rust-analyzer; do v="--version"; [ "$c" = tmux ] && v="-V"; command -v "$c" >/dev/null && printf "  %-12s %s\n" "$c" "$("$c" $v 2>&1 | head -1 | cut -c1-48)"; done
printf "  nerd font entries: %s\n" "$(fc-list | grep -ci "JetBrainsMono Nerd")"
printf "  nvim parsers: %s, mason packages: %s\n" "$(ls ~/.local/share/nvim/site/parser 2>/dev/null | wc -l)" "$(ls ~/.local/share/nvim/mason/packages 2>/dev/null | wc -l)"
' 2>&1 | grep -v 'unable to resolve host'

echo "== uninstall"
nspawn --user=tester --chdir=/home/tester/dotfile --setenv=HOME=/home/tester --setenv=NO_COLOR=1 --pipe \
  /bin/bash -c './uninstall.sh --yes 2>&1 | grep -E "removed|restored|Nothing|✖"'
exit "$RC"
