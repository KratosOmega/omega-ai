#!/bin/sh
# P3 + P4 driver — run by hand in Terminal.app (not a Claude session); spends
# 1 model session. Run P1 first (it installs the wrapper as the gd-probe
# runtime's command). Needs MULTICA_PROBE_RUNTIME_PROFILE.
# Writes to the real workspace: creates "[probe] P3 detach" assigned to
# gd-probe (starts 1 run); nothing else.
# Writes locally: $RES/p3/ (p3-detach.sh copy, pid, heartbeat.log,
# registry-entry), $RES/results.txt, $RES/cleanup.txt. Kills the child at the
# end. If this driver aborts: kill $(cat $RES/p3/pid).
# Usage: MULTICA_PROBE_RUNTIME_PROFILE=<id> sh p34-detach-env.sh
. "$(dirname "$0")/lib.sh"
need_runtime_profile
need_agent
P3="$RES/p3"

killchild() {
  [ -f "$P3/pid" ] || return 0
  kill "$(cat "$P3/pid")" 2>/dev/null
  echo "killed the P3 child (pid $(cat "$P3/pid"))"
}

mc runtime profile list --output json | grep -q omega-probe-agent \
  || die "the probe runtime's command is not omega-probe-agent: run p1-agent-session.sh first"

mkdir -p "$P3"
rm -f "$P3/pid" "$P3/heartbeat.log" "$P3/registry-entry"
cp "$PROBE_DIR/p3-detach.sh" "$P3/p3-detach.sh" && chmod 755 "$P3/p3-detach.sh" || die "cannot copy p3-detach.sh"

ID="$(printf 'Run exactly `sh %s/p3-detach.sh launch`, post its output, then finish.' "$P3" \
  | mc issue create --title "[probe] P3 detach" --assignee-id "$AID" --description-stdin --output json | pj get identifier)"
[ -n "$ID" ] || die "issue create returned no identifier"
cleanup_add issue "$ID"
echo "created $ID; waiting up to 15 min for the run"
wait_idle "$ID" 900 || { record "P3 run" "fail: still active after 15 min ($ID)"; killchild; exit 1; }
IDLE_AT="$(date +%s)"

RUNS="$(mc issue runs "$ID" --output json)"
RUNID="$(printf '%s' "$RUNS" | pj get 0.id)"
COMPLETED="$(printf '%s' "$RUNS" | pj get 0.completed_at)"
echo "run $RUNID completed_at=$COMPLETED; waiting 60 s"
sleep 60

# P3 — alive, and heartbeats later than the run's end.
if [ -n "$COMPLETED" ]; then CE="$(pj epoch "$COMPLETED")"; WHY="completed_at"
else CE="$IDLE_AT"; WHY="wait_idle time (completed_at absent)"; fi
if [ -f "$P3/pid" ] && kill -0 "$(cat "$P3/pid")" 2>/dev/null; then ALIVE=alive; else ALIVE=dead; fi
LATE="$(grep -E '^[0-9]+$' "$P3/heartbeat.log" 2>/dev/null | awk -v t="$CE" '$1 > t' | wc -l | tr -d ' ')"
if [ "$ALIVE" = alive ] && [ "$LATE" -ge 1 ]; then
  record "P3 detach" "pass: child $ALIVE, $LATE heartbeat line(s) after $WHY"
else
  record "P3 detach" "fail: child $ALIVE, $LATE heartbeat line(s) after $WHY"
fi

# P4 — the origin the wrapper exported reached the re-exec'd child.
GOT="$(grep '^origin=' "$P3/registry-entry" 2>/dev/null)"
if [ "$GOT" = "origin=multica:$RUNID" ]; then
  record "P4 origin" "pass: $GOT"
else
  record "P4 origin" "fail: registry-entry has '${GOT:-no origin= line}', expected origin=multica:$RUNID"
fi
killchild
