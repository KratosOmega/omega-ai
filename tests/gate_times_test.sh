#!/bin/sh
# Suite for studio-gate's gate.times records (#71 R6, D9): the 8-field row
# `<epoch> <who> <seconds> <rc> <wait s> <lane> <class> <unit|->`, the
# 14-day / 50-per-who / 20000-line retention, and the rewrite under the reclaim
# mutex with its unlocked fallback. Offline; temp git repos.
# Test-only knob set here: STUDIO_GATE_POLL_SECONDS (production 1), in
# test_gate_times_concurrent_no_loss only.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/tests/gate_times_rows.sh"
unset STUDIO_START_DIR STUDIO_GATE_HELD STUDIO_GATE_LANE STUDIO_GATE_DEMOTE STUDIO_UNIT_TAG \
      STUDIO_GATE_MINUTES STUDIO_GATE_SECONDS STUDIO_GATE_POLL_SECONDS
BIN="$REPO_ROOT/studios/game-dev/bin"
GATE="$BIN/studio-gate"
mk_tmp gate_times_test
trap 'rm_tmp "$TMP"' EXIT

gate_proj() { GP="$TMP/gate-$1"; mkdir -p "$GP"; ( cd "$GP" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && sh "$BIN/studio-state" init ) >/dev/null 2>&1; }
# wait_file FILE [PATTERN] — event wait (ceiling 30 s) for FILE, or for PATTERN in it.
wait_file() {
  _wf_i=0
  while [ "$_wf_i" -lt 300 ]; do
    if [ -z "${2:-}" ]; then [ -e "$1" ] && return 0; else grep -q -- "$2" "$1" 2>/dev/null && return 0; fi
    sleep 0.1; _wf_i=$((_wf_i + 1))
  done
  return 1
}
# who_rows FILE WHO — every row (any field count) whose who is WHO.
who_rows() { awk -v w="$2" '$2 == w { n++ } END { print n + 0 }' "$1" 2>/dev/null; }

test_gt_rows_rejects_wrong_rc() {
  F="$TMP/gtr.times"
  printf '1 t 2 1 0 main exclusive -\n' > "$F"
  assert_eq 0 "$(gt_rows "$F" t 0)" "an rc-1 row is not an rc-0 row"
  assert_eq 1 "$(gt_rows "$F" t 1)" "the rc-1 row counts as rc 1"
  printf '1 t 2 0\n' > "$F"
  assert_eq 0 "$(gt_rows "$F" t 0)" "a 4-field row is not an 8-field row"
  printf '1 t 2 124 0 main exclusive -\n' > "$F"
  assert_eq 1 "$(gt_rows "$F" t 124)" "a planted 124 row is seen (the no-124 check can fail)"
}

test_gate_times_row_shape() {
  gate_proj shape
  F="$GP/.studio/gate.times"
  ( cd "$GP" && STUDIO_UNIT_TAG=u1 sh "$GATE" w -- true ) >/dev/null 2>&1
  _r="$(gt_row "$F" w)"
  assert_eq 1 "$(printf '%s\n' "$_r" | grep -cE '^[0-9]+ w [0-9]+ 0 [0-9]+ main exclusive u1$')" "an 8-field row with wait, lane, class and unit ($_r)"
  ( cd "$GP" && sh "$GATE" n -- true ) >/dev/null 2>&1
  _r="$(gt_row "$F" n)"
  assert_eq 1 "$(printf '%s\n' "$_r" | grep -cE '^[0-9]+ n [0-9]+ 0 [0-9]+ main exclusive -$')" "with no unit tag field 8 is - ($_r)"
}

test_gate_times_wait_recorded() {
  gate_proj wait
  F="$GP/.studio/gate.times"
  rm -f "$TMP/h.up" "$TMP/h.go" "$TMP/w.err"
  ( cd "$GP" && sh "$GATE" h -- sh -c "touch '$TMP/h.up'; while [ ! -f '$TMP/h.go' ]; do sleep 0.1; done" ) >/dev/null 2>&1 &
  _h=$!
  wait_file "$TMP/h.up"
  assert_file "$TMP/h.up" "the holder runs inside 30 s"
  ( cd "$GP" && sh "$GATE" w -- true ) >/dev/null 2> "$TMP/w.err" &
  _w=$!
  wait_file "$TMP/w.err" 'gate: waiting'
  assert_contains "$TMP/w.err" '^gate: waiting for h ' "the waiter queues behind the holder"
  sleep 3
  touch "$TMP/h.go"
  wait "$_h"; wait "$_w"
  _ww="$(gt_row "$F" w | awk '{ print $5 }')"; _hw="$(gt_row "$F" h | awk '{ print $5 }')"
  assert_eq 1 "$([ "${_ww:-0}" -ge 3 ] && echo 1 || echo 0)" "the waiter's row records its wait of 3 s or more ($_ww)"
  # Final review I2c: one uncontended admission can pass 1 s under the full
  # gate's load, so the holder's wait is bounded by the waiter's, not by 0 or 1.
  assert_eq 1 "$([ "${_hw:-99}" -lt "${_ww:-0}" ] && echo 1 || echo 0)" "the holder's row records less wait than the waiter's ($_hw < $_ww)"
}

test_gate_times_keeps_4_field_rows() {
  gate_proj four
  F="$GP/.studio/gate.times"
  printf '5 old 3 0\n6 studio-test 9 0\n' > "$F"
  ( cd "$GP" && sh "$GATE" w -- true ) >/dev/null 2>&1
  assert_eq 1 "$(grep -cxF '5 old 3 0' "$F")" "a 4-field row is kept byte for byte"
  assert_eq 1 "$(grep -cxF '6 studio-test 9 0' "$F")" "a 4-field studio-test row is kept byte for byte"
  assert_eq 1 "$(gt_rows "$F" w 0)" "the run's 8-field row is appended"
}

test_gate_times_14_day_retention() {
  gate_proj ret
  F="$GP/.studio/gate.times"
  _now="$(date +%s)"
  awk -v t="$((_now - 86400))" 'BEGIN { for (i = 1; i <= 60; i++) print t " w 1 0 0 main exclusive -" }' > "$F"
  ( cd "$GP" && sh "$GATE" w -- true ) >/dev/null 2>&1
  assert_eq 61 "$(who_rows "$F" w)" "rows younger than 14 days are all kept, past 50 per who"
  awk -v t="$((_now - 15 * 86400))" 'BEGIN { for (i = 1; i <= 60; i++) print t " w 1 0 0 main exclusive -" }' > "$F"
  ( cd "$GP" && sh "$GATE" w -- true ) >/dev/null 2>&1
  assert_eq 50 "$(who_rows "$F" w)" "past 14 days only the newest 50 per who are kept"
}

test_gate_times_line_cap() {
  gate_proj cap
  F="$GP/.studio/gate.times"
  _now="$(date +%s)"
  awk -v t="$((_now - 60))" 'BEGIN { for (i = 1; i <= 20010; i++) print t " x" i " 1 0 0 main exclusive -" }' > "$F"
  ( cd "$GP" && sh "$GATE" w -- true ) >/dev/null 2>&1
  assert_eq 20000 "$(wc -l < "$F" | tr -d ' ')" "the file keeps at most 20000 lines"
  assert_eq 1 "$(tail -n 1 "$F" | grep -cE '^[0-9]+ w [0-9]+ 0 [0-9]+ main exclusive -$')" "the run's row is the last line"
}

# A serialization sanity check (preflight F7): ten exclusive gates append while
# each holds the one lock, so this does not prove the mutex; T7's
# test_lanes_rows_no_loss_two_lanes does, with two lanes appending at once.
test_gate_times_concurrent_no_loss() {
  gate_proj conc
  F="$GP/.studio/gate.times"
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    ( cd "$GP" && STUDIO_GATE_POLL_SECONDS=0.1 sh "$GATE" "w$_i" -- true ) >/dev/null 2>&1 &
  done
  wait
  assert_eq 10 "$(awk 'NF == 8 && $2 ~ /^w[0-9]+$/ { n++ } END { print n + 0 }' "$F")" "every one of ten gates leaves its row"
}

# Preflight C1: the foreign mutex owner is planted from inside the gated
# command (after the lock is taken), so only the gate.times rewrite meets it.
test_gate_times_mutex_fallback() {
  gate_proj mfb
  F="$GP/.studio/gate.times"
  sleep 60 & _sp=$!
  _t0="$(date +%s)"; _st=0
  ( cd "$GP" && sh "$GATE" w -- sh -c "ln -s $_sp '$GP/.studio/gate.lock.mutex'" ) >/dev/null 2>&1 || _st=$?
  _el=$(( $(date +%s) - _t0 ))
  assert_eq 0 "$_st" "the gate exits with the command's status"
  assert_eq 1 "$([ "$_el" -lt 15 ] && echo 1 || echo 0)" "a held mutex falls back to the unlocked rewrite inside 15 s ($_el s)"
  assert_eq 1 "$(gt_rows "$F" w 0)" "the row is written without the mutex"
  assert_eq "$_sp" "$(readlink "$GP/.studio/gate.lock.mutex" 2>/dev/null)" "the live owner's mutex is left untouched"
  rm -f "$GP/.studio/gate.lock.mutex"
  kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null
}

# exclusive-scan: test_gate_times_mutex_fallback in (a) asserts the fallback returns inside 15 s
TESTS_EXCLUSIVE="test_gate_times_mutex_fallback"
run_tests test_gt_rows_rejects_wrong_rc test_gate_times_row_shape test_gate_times_wait_recorded \
  test_gate_times_keeps_4_field_rows test_gate_times_14_day_retention test_gate_times_line_cap \
  test_gate_times_concurrent_no_loss test_gate_times_mutex_fallback
