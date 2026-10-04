#!/bin/sh
# P2 sub-issue creation — run by hand in Terminal.app (not a Claude session);
# spends 1 model session (a failing probe can add a wakeup or two).
# Writes to the real workspace: creates "[probe] P2 parent" assigned to
# gd-probe (starts 1 run), "[probe] P2 child A" and "[probe] P2 child B"
# (todo, unassigned, under the parent); at the end unassigns the parent
# (no --no-start: the CLI refuses it with --unassign). All three go to $RES/cleanup.txt.
# Writes locally: $RES/results.txt, $RES/cleanup.txt, $RES/p2-runs.json
# (redacted). Takes up to ~10 min plus 2 min.
# Usage: sh p2-subissue.sh
. "$(dirname "$0")/lib.sh"
need_agent

PID_="$(printf '%s' 'Reply `ok` and finish. Do nothing else.' \
  | mc issue create --title "[probe] P2 parent" --allow-duplicate --assignee-id "$AID" --description-stdin --output json | pj get identifier)"
[ -n "$PID_" ] || die "parent create returned no identifier"
cleanup_add issue "$PID_"

# Child A while the parent's run is active.
_t=0
while [ "$_t" -lt 120 ]; do
  [ "$(mc issue runs "$PID_" --active --output json | pj count)" = 1 ] && break
  sleep 5; _t=$((_t + 5))
done
[ "$(mc issue runs "$PID_" --active --output json | pj count)" = 1 ] && _act=active || _act="not-seen-active"
A="$(mc issue create --title "[probe] P2 child A" --parent "$PID_" --status todo --output json | pj get identifier)"
[ -n "$A" ] && cleanup_add issue "$A"
record "P2 child A" "created $A (parent run: $_act)"

if ! wait_idle "$PID_" 600; then
  record "P2 parent run" "fail: still active after 10 min"
else
  N="$(mc issue runs "$PID_" --output json | pj count)"
  B="$(mc issue create --title "[probe] P2 child B" --parent "$PID_" --status todo --output json | pj get identifier)"
  [ -n "$B" ] && cleanup_add issue "$B"
  echo "child B $B created with N=$N runs; waiting 120 s"
  sleep 120
  RUNS="$(mc issue runs "$PID_" --output json)"
  N2="$(printf '%s' "$RUNS" | pj count)"
  ACT="$(mc issue runs "$PID_" --active --output json | pj count)"
  printf '%s' "$RUNS" | pj redact > "$RES/p2-runs.json"
  TRIG=no
  printf '%s' "$RUNS" | grep -Eiq 'sub-?issue|child' && TRIG=yes
  if [ "$N2" = "$N" ] && [ "$ACT" = 0 ] && [ "$TRIG" = no ]; then
    record "P2 sub-issue wakeup" "pass: runs $N -> $N2, active $ACT, no sub-issue trigger"
  else
    record "P2 sub-issue wakeup" "fail: runs $N -> $N2, active $ACT, sub-issue trigger text: $TRIG (see $RES/p2-runs.json)"
  fi
fi

# Last: cleanup's closing of the children must not wake the parent.
# P2 run (2026-10-04): the CLI refuses --no-start with --unassign, and an
# unassign starts no run.
unverified "issue assign --unassign" mc issue assign "$PID_" --unassign
echo "NOTE: if any run keeps appearing on $PID_, unassign it in the web UI at once."
