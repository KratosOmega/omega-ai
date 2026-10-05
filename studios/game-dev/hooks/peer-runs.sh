#!/bin/sh
# peer-runs.sh — SessionStart (startup|compact) hook (#39 AC22). In a
# manifest unit session (STUDIO_UNIT_TAG, STUDIO_RUN_DIR with rows.tsv) it
# prints the `Other live runs` block: studio-peers' runs, up to 40 of their
# unfinished-task files and `and N more`, then the peers rule. Nothing when
# no other run is live or outside a unit. Exits 0 on every path; errors go
# to <run dir>/hook.log.
trap 'exit 0' EXIT
[ -n "${STUDIO_UNIT_TAG:-}" ] && [ -n "${STUDIO_RUN_DIR:-}" ] && [ -f "$STUDIO_RUN_DIR/rows.tsv" ] || exit 0
exec 2>> "$STUDIO_RUN_DIR/hook.log"
cat > /dev/null 2>&1 || true
HERE="$(cd "$(dirname "$0")" && pwd)"; PEERS="$HERE/../bin/studio-peers"
MAX=40
RUNS="$(sh "$PEERS" --exclude "$STUDIO_RUN_DIR")" || exit 0
[ -n "$(printf '%s' "$RUNS" | tr -d ' \n')" ] || exit 0
FILES="$(sh "$PEERS" --exclude "$STUDIO_RUN_DIR" --files | grep -v ': unreadable$')"
N="$(printf '%s\n' "$FILES" | grep -c .)"
printf 'Other live runs\n\n%s\n' "$RUNS"
if [ "$N" -gt 0 ]; then
  printf '\nFiles their unfinished tasks change:\n'
  printf '%s\n' "$FILES" | grep . | head -n "$MAX" | sed 's/^/  /'
  [ "$N" -le "$MAX" ] || printf '  and %s more\n' "$((N - MAX))"
fi
printf '\n%s\n' "These files are being changed by another live run. Do not edit them beyond what your task needs; if your task needs to, keep the change minimal and name each such file in your report."
