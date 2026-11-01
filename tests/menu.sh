#!/usr/bin/env bash
# Drive the component checklist with scripted answers (DOTFILES_TTY = a file of answers) in dry-run mode and check
# what it picks. Runs with whatever bash starts it: CI runs it with /bin/bash 3.2 on macOS.
#
#   tests/menu.sh
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" NO_COLOR=1; mkdir -p "$HOME"
fails=0

pick() { # pick "answers" "expected Will install line" [extra text that must appear]
  printf '%b' "$1" >"$TMP/answers"
  out="$(DOTFILES_TTY="$TMP/answers" "${BASH:-bash}" "$REPO/install.sh" --dry-run 2>&1)"
  if printf '%s\n' "$out" | grep -qF "Will install: $2" && { [ -z "${3:-}" ] || printf '%s\n' "$out" | grep -qF "$3"; }; then
    echo "ok   answers=$(printf '%s' "$1" | tr '\n' ' ')-> $2"
  else
    echo "FAIL answers=$(printf '%s' "$1" | tr '\n' ' ')expected: $2 ${3:+/ $3}"; printf '%s\n' "$out" | tail -25; fails=$((fails+1))
  fi
}

pick 'n\n2\n\n'          'shell'                       # none, then check #2
pick 'n\n2 3,4\n\n'      'shell tmux nvim'             # several numbers on one line, commas or spaces
pick 'n\ntmux\n\n'       'tmux'                        # by name
pick 'n\n2\n2\n3\n\n'    'tmux'                        # toggling twice unchecks
pick 'n\n99\n3\n\n'      'tmux' 'not a valid choice: 99'
if [ "$(uname -s)" = Darwin ]; then
  pick 'n\ndesktop\n2\n\n' 'shell' 'desktop is not available here'
  pick 'a\n\n'             'base shell tmux nvim terminal browsers web rust' 'skipped: desktop apps'
  "${BASH:-bash}" "$REPO/install.sh" --dry-run --only desktop >/dev/null 2>&1 && { echo "FAIL --only desktop was accepted on macOS"; fails=$((fails+1)); } || echo "ok   --only desktop refused on macOS"
fi
printf 'q\n' >"$TMP/answers"
DOTFILES_TTY="$TMP/answers" "${BASH:-bash}" "$REPO/install.sh" --dry-run 2>&1 | grep -q "Nothing installed" && echo "ok   q quits" || { echo "FAIL q"; fails=$((fails+1)); }
[ "$fails" -eq 0 ] && echo "all menu checks passed" || { echo "$fails menu check(s) failed"; exit 1; }
