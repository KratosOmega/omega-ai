#!/bin/sh
# overnight-sessions.sh (#39): the project-wide session cap — mkdir slots, a
# FIFO wait queue, owner-checked release and reclaim of dead owners.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/overnight_sessions_test.XXXXXX")" && pwd -P)"; trap '{ kill $DUMMIES; wait; } 2>/dev/null; rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
DUMMIES=""
. "$REPO_ROOT/studios/game-dev/bin/overnight-runs.sh"
. "$REPO_ROOT/studios/game-dev/bin/overnight-sessions.sh"
# live_dummy — a live pid whose args name studio-overnight (DUMMY).
live_dummy() { sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; DUMMIES="$DUMMIES $DUMMY"; }
dead_pid() { sh -c ':' & wait $!; DEAD=$!; }
# proj NAME CAP — STATE_ROOT with config max_sessions CAP; sess_init.
proj() { STATE_ROOT="$TMP/$1"; mkdir -p "$STATE_ROOT/.studio"
  printf '{"overnight": {"max_sessions": %s}}\n' "$2" > "$STATE_ROOT/.studio/config.json"
  SESS_START_CAP=6; SESS_RUN="$TMP/run-$1"; sess_init; }

test_sess_fifo_oldest_waiter_only() {
  proj fifo 1; live_dummy; L1="$DUMMY"; live_dummy; L2="$DUMMY"; live_dummy; L3="$DUMMY"
  SESS_ME="$L1"; sess_enqueue S1 u1; sess_try u1; assert_eq 0 $? "first in line takes the one slot"; S_L1="$SESS_SLOT"
  SESS_ME="$L2"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S2 u2; W2="$SESS_WAIT"
  SESS_ME="$L3"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S3 u3; W3="$SESS_WAIT"
  SESS_ME="$L1"; SESS_SLOT="$S_L1"; sess_release
  SESS_ME="$L3"; SESS_WAIT="$W3"; sess_try u3; assert_eq 1 $? "a younger waiter never takes a free slot"
  SESS_ME="$L2"; SESS_WAIT="$W2"; sess_try u2; assert_eq 0 $? "the oldest waiter takes it"
  assert_eq "$L2" "$(runs_kv lane "$STATE_ROOT/.studio/sessions/$SESS_SLOT/owner")" "owner names the lane"
  assert_missing "$W2" "the taker left the queue"
}
test_sess_cap_respected() {
  proj cap 2; live_dummy; A="$DUMMY"; live_dummy; B="$DUMMY"; live_dummy; C="$DUMMY"
  for _l in "$A" "$B" "$C"; do SESS_ME="$_l"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; eval "R_$_l=\$?"; done
  eval "assert_eq 0 \$R_$A 'slot 1'"; eval "assert_eq 0 \$R_$B 'slot 2'"; eval "assert_eq 1 \$R_$C 'cap 2: the third waits'"
  assert_eq 2 "$(sess_live_count)" "two live"
}
test_sess_cap_lowered_no_new_take() {
  proj lower 3; live_dummy; A="$DUMMY"; live_dummy; B="$DUMMY"; live_dummy; C="$DUMMY"
  for _l in "$A" "$B"; do SESS_ME="$_l"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; done
  printf '{"overnight": {"max_sessions": 1}}\n' > "$STATE_ROOT/.studio/config.json"
  SESS_ME="$C"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u
  assert_eq 1 $? "live 2 > cap 1: no take (D21)"; assert_eq 2 "$(sess_live_count)" "live slots are never revoked"
}
test_sess_release_owner_checked() {
  proj late 1; live_dummy; A="$DUMMY"; live_dummy; B="$DUMMY"
  SESS_ME="$A"; sess_enqueue S u; sess_try u; SA="$SESS_SLOT"
  kill "$A"; wait "$A" 2>/dev/null                                 # A dies; B reclaims and takes the slot
  SESS_ME="$B"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; assert_eq 0 $? "reclaimed and retaken"
  SESS_ME="$A"; SESS_SLOT="$SA"; sess_release                     # a late release in A's name
  assert_eq "$B" "$(runs_kv lane "$STATE_ROOT/.studio/sessions/$SA/owner")" "a late release leaves the other lane's slot"
}
test_sess_reclaim_dead_owner_and_ownerless() {
  proj reclaim 1; dead_pid; mkdir -p "$STATE_ROOT/.studio/sessions/1"
  printf 'lane=%s\nsession=\nrun=x\nunit=u\n' "$DEAD" > "$STATE_ROOT/.studio/sessions/1/owner"
  live_dummy; SESS_ME="$DUMMY"; sess_enqueue S u; sess_try u; assert_eq 0 $? "a dead owner's slot is reclaimed by liveness"
  proj ownerless 1; mkdir -p "$STATE_ROOT/.studio/sessions/1"
  SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; assert_eq 0 $? "a slot with no owner file is reclaimed (D20)"
}
test_sess_owner_live_by_session_pid() {
  proj sesslive 1; dead_pid; sh -c 'sleep 60; :' claude >/dev/null 2>&1 & CL=$!; DUMMIES="$DUMMIES $CL"
  mkdir -p "$STATE_ROOT/.studio/sessions/1"
  printf 'lane=%s\nsession=%s\nrun=x\nunit=u\n' "$DEAD" "$CL" > "$STATE_ROOT/.studio/sessions/1/owner"
  live_dummy; SESS_ME="$DUMMY"; sess_enqueue S u; sess_try u
  assert_eq 1 $? "a dead lane whose session still runs keeps its slot"
}
test_sess_reclaim_dead_waiter() {
  proj waiter 1; dead_pid; mkdir -p "$STATE_ROOT/.studio/sessions/wait"
  : > "$STATE_ROOT/.studio/sessions/wait/1000000000000000000-$DEAD"
  live_dummy; SESS_ME="$DUMMY"; sess_enqueue S u; sess_try u
  assert_eq 0 $? "a dead waiter at the head is dropped, the next one serves"
}
test_sess_wait_key_monotonic() {
  proj keys 1; live_dummy; SESS_ME="$DUMMY"
  sess_enqueue S u; K1="${SESS_WAIT##*/}"; SESS_WAIT=""; sess_enqueue S u; K2="${SESS_WAIT##*/}"
  _k1="${K1%-*}"; assert_eq 19 "${#_k1}" "19-digit key (D3)"
  [ "${K2%-*}" -gt "${K1%-*}" ]; assert_eq 0 $? "strictly increasing within one second"
}
test_sess_drop_owner() {
  proj drop 2; live_dummy; A="$DUMMY"; SESS_ME="$A"; sess_enqueue S u; sess_try u; SESS_WAIT=""; sess_enqueue S u
  SESS_ME=$$; sess_drop_owner "$A"
  assert_eq 0 "$(sess_live_count)" "the dead lane's slot is gone"
  assert_eq "" "$(ls "$STATE_ROOT/.studio/sessions/wait" | grep -- "-$A\$")" "and its wait entry"
}
test_sess_cap_config_fallback() {
  proj fb 1; printf '{"overnight": {"max_sessions": "x"}}\n' > "$STATE_ROOT/.studio/config.json"; SESS_START_CAP=3
  assert_eq 3 "$(sess_cap)" "invalid at runtime: the start's value"
  printf '{"overnight": {"max_sessions": 9}}\n' > "$STATE_ROOT/.studio/config.json"
  assert_eq 3 "$(sess_cap)" "out of range: the start's value"
}

run_tests test_sess_fifo_oldest_waiter_only test_sess_cap_respected test_sess_cap_lowered_no_new_take \
  test_sess_release_owner_checked test_sess_reclaim_dead_owner_and_ownerless test_sess_owner_live_by_session_pid \
  test_sess_reclaim_dead_waiter test_sess_wait_key_monotonic test_sess_drop_owner test_sess_cap_config_fallback
