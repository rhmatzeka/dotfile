#!/usr/bin/env bash
# Hyprland + Caelestia shell on Debian 13 (trixie), x86_64.
#
# Why this is long: Caelestia's shell needs Qt >= 6.11, and Debian 13 ships Qt 6.8. So Qt is built from
# source into /opt/qt-6.11.2 (only the modules Caelestia needs), then quickshell and the shell are built
# against it. Every step is idempotent: a marker file in /opt/qt-6.11.2 records what is done, so a
# re-run after an interruption resumes instead of starting over. Expect 1-2 hours the first time.
#
# Versions are pinned to a combination that was built and started successfully on 2026-09-19.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$HERE/../.." && pwd)}"
# shellcheck source=../../lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"
C="$DOTFILES_DIR/config"

QT_VER=6.11.2
PREFIX=/opt/qt-6.11.2
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/rhmatzeka-dotfiles/build"
GNU=/usr/local/lib/x86_64-linux-gnu

REF_QUICKSHELL=c6a516096dd84d5255b409482eb4bf740b952f88
REF_M3SHAPES=8a6fe8961749887d677700b6508e0c9249968b7e
REF_LIBCAVA=f03278ef9e5e7948fb206453d2f02758f8db216c
REF_SHELL=d999d4878ee4cec134168e60d913714566a8cfa6
REF_CLI=79441d09c156919bd53fca502ce3113088342b91
WAYLAND_TAG=1.26.0
SASS_VER=1.104.1

done_marker() { printf '%s/.done-%s' "$PREFIX" "$1"; }
is_done()     { [ -e "$(done_marker "$1")" ]; }
mark_done()   { [ "$DRY_RUN" = 1 ] || touch "$(done_marker "$1")"; }

jobs() { # parallel jobs: one per 2 GB of RAM, at most the CPU count, at least 1
  local mem cpu j; mem=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo); cpu=$(nproc)
  j=$(( mem / 2 )); [ "$j" -lt 1 ] && j=1; [ "$j" -gt "$cpu" ] && j=$cpu; printf '%s' "$j"
}

env_build() { # environment every source build below uses
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$GNU/pkgconfig:${PKG_CONFIG_PATH:-}"
  export PATH="$PREFIX/bin:$PATH"
}

# ------------------------------------------------------------- preflight ----
preflight() {
  [ "$(os_field ID)" = debian ] && [ "$(os_field VERSION_CODENAME)" = trixie ] \
    || die "The desktop component supports Debian 13 (trixie) only; this is $(os_field PRETTY_NAME)."
  [ "$(uname -m)" = x86_64 ] || die "The pinned binaries are for x86_64 only (this is $(uname -m))."
  local mem; mem=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo)
  [ "$mem" -ge 6 ] || warn "Only ${mem} GB of RAM: building Qt may run out of memory. Close other programs and expect it to be slow."
  df -Pk "$HOME" | awk 'NR==2 && $4 < 15*1048576 {exit 1}' || warn "Less than 15 GB free: the build needs about 10 GB."
  need_sudo
  info "Qt will be built with $(jobs) parallel job(s). Sources and build files go to ${BUILD/#$HOME/~} (safe to delete afterwards)."
}

# --------------------------------------------------------------- packages ----
enable_backports() {
  if grep -rqs 'trixie-backports' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then ok "trixie-backports already enabled"; return 0; fi
  info "enabling trixie-backports (Hyprland is only packaged there)"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would add /etc/apt/sources.list.d/trixie-backports.list"; return 0; fi
  echo "deb http://deb.debian.org/debian trixie-backports main" | "${SUDO[@]}" tee /etc/apt/sources.list.d/trixie-backports.list >/dev/null
  # shellcheck disable=SC2034  # read by apt_update_once in lib/common.sh
  APT_UPDATED=0; apt_update_once
}

install_packages() {
  apt_need git cmake ninja-build meson pkg-config build-essential curl unzip xz-utils \
    ddcutil brightnessctl cava lm-sensors libsensors-dev libaubio-dev libpipewire-0.3-dev libqalculate-dev \
    libvulkan-dev libfontconfig-dev libfreetype-dev libharfbuzz-dev libicu-dev libdbus-1-dev libssl-dev \
    libwayland-dev libegl-dev libgles-dev libgl-dev libpng-dev libjpeg-dev zlib1g-dev libpcre2-dev \
    libdouble-conversion-dev libb2-dev libzstd-dev libinput-dev libmtdev-dev libudev-dev libcli11-dev \
    libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev libjemalloc-dev spirv-tools glslang-tools \
    libtiff-dev libwebp-dev libsqlite3-dev libffi-dev libxml2-dev libexpat1-dev libgbm-dev libdrm-dev \
    libfftw3-dev libiniparser-dev libpulse-dev libasound2-dev libncursesw5-dev \
    mesa-vulkan-drivers vulkan-tools fish swappy libnotify-bin grim slurp wl-clipboard cliphist fuzzel \
    python3-pip pipx python3-build python3-installer python3-hatchling python3-hatch-vcs \
    mate-polkit-bin xdg-desktop-portal-gtk power-profiles-daemon network-manager fonts-jetbrains-mono
  apt_need_from trixie-backports hyprland xdg-desktop-portal-hyprland hyprland-guiutils wayland-protocols libxkbcommon-dev
}

# ------------------------------------------------------------------ Qt ----
qt_src() { # qt_src MODULE  -> path to the unpacked source, downloading it if needed
  local m="$1" dir="$BUILD/qt/$1-everywhere-src-$QT_VER"
  if [ ! -d "$dir" ]; then
    mkdir -p "$BUILD/qt"
    info "downloading $m $QT_VER"
    curl -fsSL --retry 3 "https://download.qt.io/official_releases/qt/${QT_VER%.*}/$QT_VER/submodules/$m-everywhere-src-$QT_VER.tar.xz" \
      | tar -xJ -C "$BUILD/qt"
  fi
  printf '%s' "$dir"
}

build_qt() {
  local m all=(qtbase qtshadertools qtdeclarative qtsvg qtimageformats qtwayland) todo=()
  for m in "${all[@]}"; do is_done "$m" || todo+=("$m"); done
  if [ ${#todo[@]} -eq 0 ]; then ok "Qt $QT_VER already built in $PREFIX"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would build Qt $QT_VER modules: ${todo[*]} into $PREFIX (1-2 hours)"; return 0; fi
  "${SUDO[@]}" mkdir -p "$PREFIX" && "${SUDO[@]}" chown "$USER" "$PREFIX"
  env_build
  local j; j=$(jobs)
  for m in "${todo[@]}"; do
    step "Qt: $m"
    local src b="$BUILD/qt/build-$m"; src=$(qt_src "$m"); rm -rf "$b"
    if [ "$m" = qtbase ]; then
      cmake -S "$src" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
        -DFEATURE_xcb=OFF -DFEATURE_printsupport=OFF -DFEATURE_cups=OFF -DFEATURE_gtk3=OFF \
        -DFEATURE_system_sqlite=ON -DFEATURE_sql_mysql=OFF -DFEATURE_sql_psql=OFF -DFEATURE_sql_odbc=OFF \
        -DFEATURE_eglfs=OFF -DFEATURE_linuxfb=OFF -DFEATURE_vulkan=ON
    else
      cmake -S "$src" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF
    fi
    cmake --build "$b" -j"$j" && cmake --install "$b" && mark_done "$m" && rm -rf "$b"
  done
}

build_wayland() { # Qt 6.11's wayland module needs libwayland >= 1.24, Debian has 1.23
  if is_done libwayland; then ok "libwayland $WAYLAND_TAG already built"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would build libwayland $WAYLAND_TAG into $PREFIX"; return 0; fi
  step "libwayland $WAYLAND_TAG"; env_build
  git_clone https://gitlab.freedesktop.org/wayland/wayland.git "$BUILD/wayland" "$WAYLAND_TAG"
  ( cd "$BUILD/wayland" && rm -rf build \
    && meson setup build --prefix="$PREFIX" --libdir=lib -Ddocumentation=false -Dtests=false -Ddtd_validation=false \
    && ninja -C build && ninja -C build install ) && mark_done libwayland
}

build_libcava() {
  if [ -e "$GNU/libcava.so" ]; then ok "libcava already installed"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would build libcava"; return 0; fi
  step "libcava"
  git_clone https://github.com/LukashonakV/cava.git "$BUILD/libcava" "$REF_LIBCAVA"
  ( cd "$BUILD/libcava" && rm -rf build \
    && meson setup build --prefix=/usr/local -Dbuild_target=lib -Doutput_sdl=disabled -Doutput_sdl_glsl=disabled \
    && ninja -C build && "${SUDO[@]}" ninja -C build install && "${SUDO[@]}" ldconfig )
}

cmake_project() { # cmake_project NAME SRC EXTRA-CMAKE-ARGS...   (configure, build, install into $PREFIX)
  local name="$1" src="$2"; shift 2
  local b="$BUILD/build-$name"; rm -rf "$b"
  cmake -S "$src" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" "$@" \
    && cmake --build "$b" -j"$(jobs)" && cmake --install "$b"
}

build_quickshell() {
  if is_done quickshell && [ -x "$PREFIX/bin/qs" ]; then ok "quickshell already built"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would build quickshell ($REF_QUICKSHELL)"; return 0; fi
  step "quickshell"; env_build
  git_clone https://git.outfoxxed.me/quickshell/quickshell.git "$BUILD/quickshell" "$REF_QUICKSHELL"
  cmake_project quickshell "$BUILD/quickshell" -DCMAKE_INSTALL_RPATH="$PREFIX/lib" -DINSTALL_QML_PREFIX=qml \
    -DX11=OFF -DCRASH_HANDLER=OFF -DDISTRIBUTOR="rhmatzeka/dotfile" && mark_done quickshell
}

build_m3shapes() {
  if is_done m3shapes; then ok "m3shapes already built"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would build m3shapes"; return 0; fi
  step "m3shapes"; env_build
  git_clone https://github.com/soramanew/m3shapes.git "$BUILD/m3shapes" "$REF_M3SHAPES"
  cmake_project m3shapes "$BUILD/m3shapes" \
    && ln -sfn "$PREFIX/lib/qt6/qml/M3Shapes" "$PREFIX/qml/M3Shapes" && mark_done m3shapes
}

build_shell() {
  if is_done caelestia-shell && [ -f "$HOME/.config/quickshell/caelestia/shell.qml" ]; then ok "caelestia-shell already built"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would build caelestia-shell ($REF_SHELL)"; return 0; fi
  step "caelestia-shell"; env_build
  git_clone https://github.com/caelestia-dots/shell.git "$BUILD/caelestia-shell" "$REF_SHELL"
  mkdir -p "$HOME/.config/quickshell/caelestia"
  cmake_project caelestia-shell "$BUILD/caelestia-shell" \
    -DCMAKE_INSTALL_RPATH="$PREFIX/lib;$GNU" -DINSTALL_LIBDIR=lib/caelestia -DINSTALL_QMLDIR=qml \
    -DINSTALL_QSCONFDIR="$HOME/.config/quickshell/caelestia" \
    && "${SUDO[@]}" ln -sfn "$PREFIX/lib/caelestia" /usr/lib/caelestia && mark_done caelestia-shell
}

install_qs_wrapper() { # the shell and the caelestia CLI both call plain `qs`; this makes it find the local Qt
  local w=/usr/local/bin/qs
  if [ -x "$w" ] && grep -q "$PREFIX" "$w" 2>/dev/null; then ok "qs wrapper already in place"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would write $w"; return 0; fi
  "${SUDO[@]}" tee "$w" >/dev/null <<E
#!/bin/sh
# Run quickshell from the local Qt $QT_VER build (needed by caelestia-shell)
export QT_PLUGIN_PATH=$PREFIX/plugins
export QML_IMPORT_PATH=$PREFIX/qml
export CAELESTIA_LIB_DIR=$PREFIX/lib/caelestia
exec $PREFIX/bin/qs "\$@"
E
  "${SUDO[@]}" chmod +x "$w"
  ok "wrote $w"
}

install_cli() {
  if have caelestia && python3 -c 'import materialyoucolor' 2>/dev/null; then ok "caelestia CLI already installed"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would build and install caelestia-cli ($REF_CLI)"; return 0; fi
  step "caelestia CLI"
  git_clone https://github.com/caelestia-dots/cli.git "$BUILD/caelestia-cli" "$REF_CLI"
  ( cd "$BUILD/caelestia-cli" && rm -rf dist && python3 -m build --wheel --no-isolation \
    && "${SUDO[@]}" python3 -m installer --prefix /usr dist/*.whl \
    && "${SUDO[@]}" install -Dm644 completions/caelestia.fish /usr/share/fish/vendor_completions.d/caelestia.fish )
  # Python dependency missing from Debian; installed for this user only
  python3 -m pip install --user --break-system-packages materialyoucolor
}

install_sass() {
  if have sass; then ok "sass already installed"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would install dart-sass $SASS_VER"; return 0; fi
  step "dart-sass $SASS_VER"
  local tmp; tmp="$(mktemp)"
  fetch "https://github.com/sass/dart-sass/releases/download/$SASS_VER/dart-sass-$SASS_VER-linux-x64.tar.gz" "$tmp"
  "${SUDO[@]}" mkdir -p /opt/dart-sass && "${SUDO[@]}" tar -xzf "$tmp" -C /opt/dart-sass --strip-components=1 && rm -f "$tmp"
  "${SUDO[@]}" ln -sfn /opt/dart-sass/sass /usr/local/bin/sass
}

install_fonts() { # Material Symbols (the shell's icons), Rubik and CaskaydiaCove Nerd Font
  local d="$HOME/.local/share/fonts/caelestia"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would install Material Symbols, Rubik and CaskaydiaCove fonts"; return 0; fi
  mkdir -p "$d"
  [ -e "$d/MaterialSymbolsRounded.ttf" ] || fetch "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" "$d/MaterialSymbolsRounded.ttf"
  [ -e "$d/Rubik.ttf" ] || fetch "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf" "$d/Rubik.ttf"
  if ! ls "$d"/CaskaydiaCoveNerdFont-*.ttf >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    fetch "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.tar.xz" "$tmp" \
      && tar -xJf "$tmp" -C "$d" --wildcards 'CaskaydiaCoveNerdFont-*.ttf' && rm -f "$tmp"
  fi
  fc-cache -f >/dev/null 2>&1; ok "fonts installed"
}

install_dots() { # the upstream Hyprland config, cloned here (it is not redistributed by this repo), then our overrides on top
  local up="$HOME/.local/share/rhmatzeka-dotfiles/caelestia-dots"
  git_clone https://github.com/caelestia-dots/caelestia.git "$up"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would copy Caelestia's hypr/ config to ~/.config/hypr (existing one is backed up)"
  elif [ ! -e "$HOME/.config/hypr/.rhmatzeka-dotfiles" ]; then
    if [ -e "$HOME/.config/hypr" ]; then
      mkdir -p "$BACKUP_ROOT/$STAMP/.config"; mv "$HOME/.config/hypr" "$BACKUP_ROOT/$STAMP/.config/hypr"
      info "backed up ~/.config/hypr -> ${BACKUP_ROOT/#$HOME/~}/$STAMP/.config/hypr"
    fi
    mkdir -p "$HOME/.config/hypr" && cp -r "$up/hypr/." "$HOME/.config/hypr/" && : >"$HOME/.config/hypr/.rhmatzeka-dotfiles"
    ok "installed the Caelestia Hyprland config"
  else ok "Caelestia Hyprland config already in place"; fi
  for f in hypr-user.lua hypr-vars.lua shell.json; do backup_and_link "$C/caelestia/$f" "$HOME/.config/caelestia/$f"; done
}

finish() {
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  ensure_local_bin_in_path; export PATH="/usr/local/bin:$PATH"
  if have caelestia && [ ! -f "${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/scheme.json" ]; then
    caelestia scheme set -n caelestia >/dev/null 2>&1 || warn "could not set the default colour scheme; run: caelestia scheme set -n caelestia"
  fi
  ok "Desktop installed. Log out and pick the \"Hyprland\" session at the login screen."
  info "The shell starts by itself; if it does not, run: caelestia shell -d"
}

# ------------------------------------------------------------------ main ----
preflight
step "Packages"; enable_backports; install_packages
build_qt; build_wayland; build_libcava; build_quickshell; build_m3shapes; build_shell
install_qs_wrapper; install_cli; install_sass; install_fonts
step "Configuration"; install_dots
finish
