#!/bin/sh
# run.sh [--scene RES_PATH] [--seconds N] [--windowed] — boot the project (or
# one scene) for N seconds and scan the log for script errors. Invoked by
# studio-dispatch from the project root.
#
# Exit: 0 clean · 1 script errors, bad usage, or not a project · 2 no Godot
# binary. The full log is .studio/reports/run-<stamp>.log; error lines are
# echoed first, then the last 40 lines. macOS has no timeout(1), so the
# engine is started in the background, slept on, and sent TERM.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(pwd -P)"
SCENE=""
DURATION=10
HEADLESS="--headless"

usage() {
  echo "usage: studio-run [--scene RES_PATH] [--seconds N] [--windowed]" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scene)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      SCENE="$2"; shift 2 ;;
    --seconds)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$2" in ''|*[!0-9]*) usage ;; esac
      DURATION="$2"; shift 2 ;;
    --windowed) HEADLESS=""; shift ;;
    *) usage ;;
  esac
done

if [ ! -f "$PROJECT/project.godot" ]; then
  echo "studio-run: no project.godot in $PROJECT — run from the project root" >&2
  exit 1
fi

GODOT="$(sh "$HERE/resolve.sh")" || exit 2

mkdir -p "$PROJECT/.studio/reports"
stamp="$(date +%Y%m%d-%H%M%S)"
log_rel=".studio/reports/run-$stamp.log"
log="$PROJECT/$log_rel"

# A project the editor has never opened has no .godot/ (and so no
# global_script_class_cache.cfg); import once so class_name lookups resolve.
if [ ! -d "$PROJECT/.godot" ]; then
  "$GODOT" --headless --path "$PROJECT" --import >>"$log" 2>&1 || true
fi

# Build the argument list without word-splitting a scene path.
set -- --path "$PROJECT"
[ -n "$HEADLESS" ] && set -- "$HEADLESS" "$@"
[ -n "$SCENE" ] && set -- "$@" "$SCENE"

"$GODOT" "$@" >> "$log" 2>&1 &
pid=$!
# If studio-run itself is interrupted (Ctrl-C, a CI timeout) during the
# sleep below, terminate the child instead of orphaning it.
trap 'kill -TERM "$pid" 2>/dev/null; exit 130' INT TERM HUP
sleep "$DURATION"
kill -TERM "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
trap - INT TERM HUP

errors="$(grep -nE 'SCRIPT ERROR|ERROR:|Parser Error' "$log" || true)"
if [ -n "$errors" ]; then
  printf '%s\n' "$errors"
  count="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
  printf 'studio-run: %s error line(s) in %s\n' "$count" "$log_rel"
  tail -n 40 "$log"
  exit 1
fi

tail -n 40 "$log"
printf 'studio-run: clean (%ss, %s)\n' "$DURATION" "$log_rel"
