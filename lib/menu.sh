# shellcheck shell=bash
# The component checklist shared by the Linux and macOS installers. Source lib/common.sh first.
#
# Works with the bash 3.2 that macOS ships: no associative arrays, and no bare "${a[@]}" of a possibly empty
# array (that is an "unbound variable" error under `set -u` before bash 4.4).
#
# The installer sets, before calling menu_choose:
#   MENU_TITLE           shown at the top, e.g. "macOS (beta)"
#   MENU_ITEMS=(...)     components that can be installed on this machine, in install order
#   MENU_DEFAULTS=(...)  the ones checked at the start (minus those already installed)
#   MENU_OFF=(...)       "name|reason" for components that exist in the repo but cannot be installed here:
#                        listed separately, never selectable, skipped by "a" and refused by --only
# and defines:
#   menu_desc NAME       one-line description
#   menu_status NAME     prints a short status ("installed") when there is nothing left to do, else nothing
#   menu_note NAME       optional: a warning shown before installing it ("about 1 GB download"), else nothing
#
# Results: menu_choose and menu_from_list fill SELECTED=(...); menu_confirm shows the summary and asks once.

MENU_TITLE="${MENU_TITLE:-}"
SELECTED=()

in_list() { # in_list WORD [LIST...]
  local w="$1" x; shift
  for x in "$@"; do [ "$x" = "$w" ] && return 0; done
  return 1
}

menu_off_reason() { # menu_off_reason NAME -> prints the reason when NAME cannot be installed here
  local e
  for e in ${MENU_OFF[@]+"${MENU_OFF[@]}"}; do
    [ "${e%%|*}" = "$1" ] && { printf '%s' "${e#*|}"; return 0; }
  done
  return 1
}

# menu_from_list "a,b,c"  -> SELECTED, or exits with a clear message for an unknown or unavailable name
menu_from_list() {
  local c why list
  SELECTED=()
  list="$(printf '%s' "$1" | tr ',' ' ')"
  for c in $list; do
    if why="$(menu_off_reason "$c")"; then die "$c cannot be installed here: $why"; fi
    in_list "$c" "${MENU_ITEMS[@]}" || die "unknown component: $c (see --list)"
    in_list "$c" ${SELECTED[@]+"${SELECTED[@]}"} || SELECTED+=("$c")
  done
}

menu_list() { # for --list
  local c e mark
  for c in "${MENU_ITEMS[@]}"; do
    mark=" "; in_list "$c" ${MENU_DEFAULTS[@]+"${MENU_DEFAULTS[@]}"} && mark="*"
    printf '  %s %-9s %s\n' "$mark" "$c" "$(menu_desc "$c")"
  done
  printf '\n  * = checked by default\n'
  if [ "${#MENU_OFF[@]}" -gt 0 ]; then
    printf '\n  Not available on this system:\n'
    for e in "${MENU_OFF[@]}"; do printf '  - %-9s %s\n' "${e%%|*}" "${e#*|}"; done
  fi
}

_MENU_ON=(); _MENU_STATUS=()

_menu_draw() {
  local i c e n="${#MENU_ITEMS[@]}" box st
  [ -t 1 ] && printf '\033[H\033[2J'
  printf '\n  %sdotfiles installer%s %s%s%s\n\n' "$C_BOLD$C_CYAN" "$C_OFF" "$C_DIM" "${MENU_TITLE:+- $MENU_TITLE}" "$C_OFF"
  printf '  Choose what to install (type a number to check or uncheck it):\n\n'
  for (( i=0; i<n; i++ )); do
    c="${MENU_ITEMS[$i]}"; st=""
    [ -n "${_MENU_STATUS[$i]}" ] && st=" $C_GREEN(${_MENU_STATUS[$i]})$C_OFF"
    if [ "${_MENU_ON[$i]}" = 1 ]; then box="${C_CYAN}[x]"; else box="${C_DIM}[ ]"; fi
    printf '   %2d. %s %-9s%s %s%s%s\n' "$((i+1))" "$box" "$c" "$C_OFF" "$C_DIM" "$(menu_desc "$c")" "$C_OFF$st"
  done
  if [ "${#MENU_OFF[@]}" -gt 0 ]; then
    printf '\n  Not available on this system (cannot be selected):\n'
    for e in "${MENU_OFF[@]}"; do printf '   %s  -  %-9s %s%s\n' "$C_DIM" "${e%%|*}" "${e#*|}" "$C_OFF"; done
  fi
  printf '\n  %snumber%s check/uncheck  |  %sa%s all  |  %sn%s none  |  %sEnter%s continue  |  %sq%s quit\n' \
    "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
  [ -n "${1:-}" ] && printf '\n  %s!%s %s\n' "$C_YELLOW" "$C_OFF" "$1"
  printf '\n  > '
}

# menu_choose -> SELECTED. Without a terminal, or with --yes, it takes MENU_DEFAULTS without asking.
menu_choose() {
  local i c n="${#MENU_ITEMS[@]}" ans tok msg="" why
  SELECTED=()
  if [ "${ASSUME_YES:-0}" = 1 ] || ! interactive; then
    SELECTED=(${MENU_DEFAULTS[@]+"${MENU_DEFAULTS[@]}"}); return 0
  fi
  _MENU_ON=(); _MENU_STATUS=()
  for (( i=0; i<n; i++ )); do
    c="${MENU_ITEMS[$i]}"
    _MENU_STATUS[$i]="$(menu_status "$c" 2>/dev/null)"
    # already installed: nothing to do, so it starts unchecked (check it again to repair or update it)
    if in_list "$c" ${MENU_DEFAULTS[@]+"${MENU_DEFAULTS[@]}"} && [ -z "${_MENU_STATUS[$i]}" ]; then _MENU_ON[$i]=1; else _MENU_ON[$i]=0; fi
  done
  while :; do
    _menu_draw "$msg"; msg=""
    tty_read ans || ans=q
    case "$ans" in
      "")   break ;;
      a|A)  for (( i=0; i<n; i++ )); do _MENU_ON[$i]=1; done ;;
      n|N)  for (( i=0; i<n; i++ )); do _MENU_ON[$i]=0; done ;;
      q|Q)  printf '\n'; info "Nothing installed."; exit 0 ;;
      *)    for tok in $(printf '%s' "$ans" | tr ',' ' '); do
              i=-1
              if [[ "$tok" =~ ^[0-9]+$ ]]; then
                [ "$tok" -ge 1 ] && [ "$tok" -le "$n" ] && i=$((tok-1))
              else
                for (( c=0; c<n; c++ )); do [ "${MENU_ITEMS[$c]}" = "$tok" ] && i=$c; done
              fi
              if [ "$i" -ge 0 ]; then
                if [ "${_MENU_ON[$i]}" = 1 ]; then _MENU_ON[$i]=0; else _MENU_ON[$i]=1; fi
              elif why="$(menu_off_reason "$tok")"; then msg="$tok is not available here: $why"
              else msg="not a valid choice: $tok (use the numbers 1-$n)"
              fi
            done ;;
    esac
  done
  for (( i=0; i<n; i++ )); do [ "${_MENU_ON[$i]}" = 1 ] && SELECTED+=("${MENU_ITEMS[$i]}"); done
  printf '\n'
}

# menu_confirm -> 0 to go ahead. Lists what will be installed, the heavy parts, and what this system skips.
menu_confirm() {
  local c e note off=""
  [ "${#SELECTED[@]}" -gt 0 ] || { info "Nothing selected."; exit 0; }
  printf '\n  %sWill install:%s %s\n' "$C_BOLD" "$C_OFF" "${SELECTED[*]}"
  for c in "${SELECTED[@]}"; do
    [ -n "$(menu_status "$c" 2>/dev/null)" ] && continue   # already there: little or nothing to download
    note="$(menu_note "$c" 2>/dev/null)" || note=""
    [ -n "$note" ] && printf '    %s!%s %-9s %s\n' "$C_YELLOW" "$C_OFF" "$c" "$note"
  done
  for e in ${MENU_OFF[@]+"${MENU_OFF[@]}"}; do off="$off ${e%%|*}"; done
  [ -n "$off" ] && printf '  %sNot available here, skipped:%s%s\n' "$C_DIM" "$off" "$C_OFF"
  printf '\n'
  [ "${DRY_RUN:-0}" = 1 ] && return 0
  confirm "Continue?" y
}

# run_selected -> runs comp_<name> for each selected component, in MENU_ITEMS order, each in its own subshell so
# one failure does not stop the rest. Fills OK=(...) and FAILED=(...) and prints the result.
run_selected() {
  local c rc
  OK=(); FAILED=()
  for c in "${MENU_ITEMS[@]}"; do
    in_list "$c" ${SELECTED[@]+"${SELECTED[@]}"} || continue
    # NOT inside `if (...)`: bash ignores `set -e` in a condition context, which would let a failed package install
    # carry on and be reported as success. A plain subshell followed by $? keeps errexit active inside it.
    ( set -e; "comp_$c" )
    rc=$?
    if [ "$rc" -eq 0 ]; then OK+=("$c"); else FAILED+=("$c"); fail "component failed (exit $rc): $c"; fi
  done
  printf '\n'
  [ ${#OK[@]} -gt 0 ]     && ok "Done: ${OK[*]}"
  if [ ${#FAILED[@]} -gt 0 ]; then
    fail "Failed: ${FAILED[*]} (run again with --only $(printf '%s' "${FAILED[*]}" | tr ' ' ',') after fixing the cause)"
  fi
  return 0
}
