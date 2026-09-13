#!/bin/sh
# SessionStart hook for the game-dev studio. Prints hooks/bootstrap.md as the
# session's additional context, with the identity line filled from the
# project's .studio/config.json (falling back to the studio's own defaults).
#
# Self-contained on purpose: in copy mode the plugin root is a snapshot with
# no lib/common.sh beside it.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# field FILE KEY — value of a flat JSON string key; empty when absent.
field() {
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

# pick KEY — the project's value when it has one, else the studio default.
pick() {
  _v="$(field ".studio/config.json" "$1")"
  [ -n "$_v" ] || _v="$(field "$ROOT/studio.json" "$1")"
  printf '%s' "$_v"
}

# label VALUE — the display form of a configuration value.
label() {
  case "$1" in
    godot4) printf 'Godot 4.x' ;;
    2d) printf '2D' ;;
    3d) printf '3D' ;;
    gdscript) printf 'GDScript' ;;
    csharp) printf 'C#' ;;
    gut) printf 'GUT' ;;
    gdunit4) printf 'gdUnit4' ;;
    '') printf 'unset' ;;
    *) printf '%s' "$1" ;;
  esac
}

ENGINE="$(label "$(pick engine)")"
DIMENSION="$(label "$(pick dimension)")"
LANGUAGE="$(label "$(pick language)")"
TESTS="$(label "$(pick tests)")"

TAB="$(printf '\t')"
# Fill the identity line, then escape for a JSON string: backslash, quote,
# tab, and newlines (joined into one line by awk). Carriage returns are dropped.
escaped="$(sed -e "s/{{ENGINE}}/$ENGINE/g" \
               -e "s/{{DIMENSION}}/$DIMENSION/g" \
               -e "s/{{LANGUAGE}}/$LANGUAGE/g" \
               -e "s/{{TESTS}}/$TESTS/g" "$ROOT/hooks/bootstrap.md" \
  | tr -d '\r' \
  | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
  | awk 'BEGIN { ORS = "" } NR > 1 { printf "\\n" } { printf "%s", $0 }')"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
