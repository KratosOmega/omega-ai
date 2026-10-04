#!/bin/sh
# P3 detach stand-in runner (P3 + P4) — self-contained: sources nothing. The
# driver p34-detach-env.sh copies it to $RES/p3/ (outside ~/Documents) and the
# gd-probe agent runs `sh $RES/p3/p3-detach.sh launch` from a Multica task.
# Not run by hand. Writes only into its own directory: pid, heartbeat.log,
# registry-entry (never under ~/.claude-gamedev/runs/). Nothing in Multica.
#   launch  read STUDIO_RUN_ORIGIN first (as cmd_start does, R52), then start
#           `child` detached the way studio-overnight --detach does
#   child   write a registry-form entry, then a heartbeat every 10 s, 15 min
D="$(cd "$(dirname "$0")" && pwd -P)"

# origin_ok VALUE — AC1a's rule (R53), copied: 1-200 bytes of A-Za-z0-9._:-,
# no newline.
origin_ok() {
  case "$1" in *'
'*) return 1 ;; esac
  printf '%s\n' "$1" | LC_ALL=C grep -Eq '^[A-Za-z0-9._:-]{1,200}$'
}

case "${1:-}" in
  launch)
    _o="${STUDIO_RUN_ORIGIN:-}"
    unset STUDIO_RUN_ORIGIN
    nohup env ${_o:+"STUDIO_RUN_ORIGIN=$_o"} perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' sh "$D/p3-detach.sh" child </dev/null >>"$D/heartbeat.log" 2>&1 &
    printf '%s\n' "$!" > "$D/pid"
    echo "launched $!"
    ;;
  child)
    _o="${STUDIO_RUN_ORIGIN:-}"
    {
      printf 'root=%s\n' "$D"
      printf 'run=probe-p3\n'
      printf 'pid=%s\n' "$$"
      printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      [ -z "$_o" ] || ! origin_ok "$_o" || printf 'origin=%s\n' "$_o"
    } > "$D/registry-entry"
    _i=0
    while [ "$_i" -lt 90 ]; do
      date -u +%s
      sleep 10
      _i=$((_i + 1))
    done
    ;;
  *)
    echo "usage: p3-detach.sh launch|child" >&2
    exit 2
    ;;
esac
