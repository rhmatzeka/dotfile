# shellcheck shell=bash
# Package-manager layer: one set of generic names, mapped per distribution family.
# Source lib/common.sh first, then this file.
#
#   PKG_FAMILY   debian | arch | fedora | suse     (set by pkg_detect)
#   pkg_need     generic-name...   install what is missing (fails if something cannot be installed)
#   pkg_optional generic-name...   try each one; warn instead of failing
#   pkg_have     generic-name      0 when installed
#
# Adding a distribution family = a case in pkg_detect, pm_is_installed, pm_install and pm_names.

PKG_FAMILY=""

pkg_detect() {
  local ids
  ids=" $(os_field ID) $(os_field ID_LIKE) "
  case "$ids" in
    *" debian "*|*" ubuntu "*)                       PKG_FAMILY=debian ;;
    *" arch "*)                                      PKG_FAMILY=arch ;;
    *" fedora "*|*" rhel "*|*" centos "*)            PKG_FAMILY=fedora ;;
    *" suse "*|*" opensuse "*|*" sles "*)            PKG_FAMILY=suse ;;
    *) return 1 ;;
  esac
}

# generic name -> the package name(s) this family uses (space separated; empty = nothing to install)
pm_names() {
  case "$1" in
    xz)         [ "$PKG_FAMILY" = debian ] && echo xz-utils || echo xz ;;
    buildtools) case "$PKG_FAMILY" in debian) echo build-essential ;; arch) echo base-devel ;; *) echo "gcc gcc-c++ make" ;; esac ;;
    firefox)    case "$PKG_FAMILY" in debian) echo firefox-esr ;; suse) echo MozillaFirefox ;; *) echo firefox ;; esac ;;
    nodejs)     [ "$PKG_FAMILY" = suse ] && echo nodejs-default || echo nodejs ;;
    npm)        [ "$PKG_FAMILY" = suse ] && echo npm-default || echo npm ;;
    chsh)       [ "$PKG_FAMILY" = fedora ] && echo util-linux-user ;;
    php)        case "$PKG_FAMILY" in
                  debian) echo "php-cli php-mysql php-mbstring php-xml php-curl php-zip php-gd php-intl" ;;
                  arch)   echo "php php-gd" ;;
                  fedora) echo "php-cli php-mysqlnd php-mbstring php-xml php-gd php-intl php-pecl-zip" ;;
                  suse)   echo "php8 php8-cli php8-mysql php8-mbstring php8-curl php8-zip php8-gd php8-intl php8-xmlreader php8-xmlwriter php8-dom php8-openssl php8-pdo" ;;
                esac ;;
    composer)   [ "$PKG_FAMILY" = suse ] && echo php-composer2 || echo composer ;;
    mariadb)    case "$PKG_FAMILY" in debian) echo mariadb-server ;; fedora) echo mariadb-server ;; *) echo mariadb ;; esac ;;
    apache)     case "$PKG_FAMILY" in
                  debian) echo "apache2 libapache2-mod-php" ;;
                  arch)   echo "apache php-apache" ;;
                  fedora) echo "httpd php" ;;
                  suse)   echo "apache2 apache2-mod_php8" ;;
                esac ;;
    phpmyadmin) case "$PKG_FAMILY" in fedora|suse) echo phpMyAdmin ;; *) echo phpmyadmin ;; esac ;;
    *)          echo "$1" ;;
  esac
}

pm_is_installed() {
  case "$PKG_FAMILY" in
    debian) pkg_installed "$1" ;;
    arch)   pacman -Qq "$1" >/dev/null 2>&1 ;;
    fedora|suse) rpm -q --quiet "$1" ;;
  esac
}

PM_REFRESHED=0
pm_refresh_once() {
  [ "$PM_REFRESHED" = 1 ] && return 0
  need_sudo
  case "$PKG_FAMILY" in
    debian) apt_update_once ;;
    suse)   run "${SUDO[@]}" zypper --non-interactive --gpg-auto-import-keys refresh ;;
    *)      : ;;   # pacman and dnf are not refreshed here (see the README note about Arch: keep the system up to date)
  esac
  PM_REFRESHED=1
}

pm_install() { # real package names
  need_sudo; pm_refresh_once
  case "$PKG_FAMILY" in
    debian) run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    arch)   run "${SUDO[@]}" pacman -S --needed --noconfirm "$@" ;;
    fedora) run "${SUDO[@]}" dnf install -y "$@" ;;
    suse)   run "${SUDO[@]}" zypper --non-interactive install --no-recommends "$@" ;;
  esac
}

pkg_have() { local p; for p in $(pm_names "$1"); do pm_is_installed "$p" || return 1; done; }

pkg_need() {
  local missing=() g p
  for g in "$@"; do for p in $(pm_names "$g"); do pm_is_installed "$p" || missing+=("$p"); done; done
  if [ ${#missing[@]} -eq 0 ]; then ok "already installed: $*"; return 0; fi
  info "$PKG_FAMILY install: ${missing[*]}"
  pm_install "${missing[@]}"
}

pkg_optional() {
  local g p
  for g in "$@"; do
    for p in $(pm_names "$g"); do
      pm_is_installed "$p" && continue
      if [ "$PKG_FAMILY" = debian ]; then
        local cand; cand="$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')"
        if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then warn "not available on this release, skipped: $p"; continue; fi
      fi
      pm_install "$p" >/dev/null 2>&1 || warn "not available or could not install, skipped: $p"
      [ "$DRY_RUN" = 1 ] && info "[dry-run] would try to install $p"
    done
  done
  return 0
}
