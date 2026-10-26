#!/bin/sh
# Suite for studios/game-dev/bin/studio-deadline: the unit's time left and
# whether a gate run or a subagent fits before its wrap-up time.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

DL="$REPO_ROOT/studios/game-dev/bin/studio-deadline"
mk_tmp studio_deadline_test
trap 'rm_tmp "$TMP"' EXIT

# A project (a git repo, so studio-state root is here) with an empty gate.times.
P="$TMP/proj"; mkdir -p "$P/.studio" && git init -q "$P" && : > "$P/.studio/gate.times" \
  || { printf 'studio_deadline_test: setup failed\n' >&2; exit 1; }

# hm EPOCH — the local HH:MM, as studio-deadline prints it.
hm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M; }
# rows WHO N SECS — gate.times holds exactly N well-formed main-lane rows of WHO, SECS each.
rows() {
  : > "$P/.studio/gate.times"; _ri=0
  while [ "$_ri" -lt "$2" ]; do printf '1000 %s %s 0 0 main exclusive -\n' "$1" "$3" >> "$P/.studio/gate.times"; _ri=$((_ri + 1)); done
}
# dl DEADLINE WRAP_AT ARGS… — studio-deadline ARGS in $P with the two vars
# (- leaves one unset): DL_STATUS, and its stdout in DL_OUT, stderr in DL_ERR.
dl() {
  _dd="$1"; _dw="$2"; shift 2; DL_STATUS=0
  ( cd "$P" && unset STUDIO_UNIT_DEADLINE STUDIO_UNIT_WRAP_AT
    [ "$_dd" = - ] || { STUDIO_UNIT_DEADLINE="$_dd"; export STUDIO_UNIT_DEADLINE; }
    [ "$_dw" = - ] || { STUDIO_UNIT_WRAP_AT="$_dw"; export STUDIO_UNIT_WRAP_AT; }
    exec sh "$DL" "$@" ) > "$TMP/dl.out" 2> "$TMP/dl.err" || DL_STATUS=$?
  DL_OUT="$(cat "$TMP/dl.out")"; DL_ERR="$(cat "$TMP/dl.err")"
}

test_deadline_outside_a_unit() {
  dl - -
  assert_eq "0 no deadline" "$DL_STATUS $DL_OUT" "no deadline: says so, exit 0"
  dl - - fits studio-test
  assert_eq "0 no deadline" "$DL_STATUS $DL_OUT" "fits outside a unit: exit 0, no deadline"
  dl - - fits agent
  assert_eq 0 "$DL_STATUS" "fits agent outside a unit: exit 0"
  dl soon - fits agent
  assert_eq "0 no deadline" "$DL_STATUS $DL_OUT" "a DEADLINE that is not a number is no deadline"
}
test_deadline_left_and_wrap() {
  now="$(date +%s)"; d=$((now + 3600)); w=$((now + 2700))
  dl "$d" "$w"
  assert_eq 0 "$DL_STATUS" "exit 0"
  assert_eq "left 60 min · wrap at $(hm "$w") (45 min) · hard stop $(hm "$d")" "$DL_OUT" "time left, the wrap time and the hard stop"
  assert_eq "" "$DL_ERR" "nothing on stderr"
  dl "$d" -
  assert_eq "left 60 min · wrap at $(hm "$d") (60 min) · hard stop $(hm "$d")" "$DL_OUT" "no WRAP_AT: the wrap is the deadline"
  dl $((now - 120)) $((now - 600))
  assert_eq "0 left 0 min · wrap at $(hm $((now - 600))) (0 min) · hard stop $(hm $((now - 120)))" "$DL_STATUS $DL_OUT" "past both: 0 min, never negative"
}
test_deadline_fits_from_history() {
  now="$(date +%s)"; rows studio-test 6 300
  dl $((now + 3600)) $((now + 2700)) fits studio-test
  assert_eq "0 fits: studio-test ~6 min, 45 min to wrap" "$DL_STATUS $DL_OUT" "6 rows of 300 s: p90 x 1.2 = 6 min fits in 45"
  dl $((now + 900)) $((now + 300)) fits studio-test
  assert_eq "1 does not fit: studio-test ~6 min, 5 min to wrap at $(hm $((now + 300)))" "$DL_STATUS $DL_OUT" "6 min does not fit in 5: exit 1 and why"
  dl $((now + 900)) $((now + 300)) fits studio-test 4
  assert_eq "0 fits: studio-test ~4 min, 5 min to wrap" "$DL_STATUS $DL_OUT" "<minutes> wins over 5 or more rows of history"
  dl $((now + 3600)) $((now + 2700)) fits studio-run
  assert_eq "0 fits: studio-run ~30 min, 45 min to wrap" "$DL_STATUS $DL_OUT" "another gate's rows do not count (STUDIO_GATE_MINUTES unset: 60 / 2)"
  # p90 by nearest rank over the newest 50: 10 rows, nine of 60 s and one of 3000 s -> the 9th smallest, 60 s.
  rows studio-test 9 60; printf '1000 studio-test 3000 0 0 main exclusive -\n' >> "$P/.studio/gate.times"
  dl $((now + 3600)) $((now + 2700)) fits studio-test
  assert_eq "0 fits: studio-test ~2 min, 45 min to wrap" "$DL_STATUS $DL_OUT" "p90 of 10 rows is the 9th: 60 s x 1.2 = 72 s, ~2 min"
  # A red run, a short-lane run and an old 4-field row are not history.
  rows studio-test 4 300
  printf '%s\n' '1000 studio-test 300 1 0 main exclusive -' '1000 studio-test 300 0 0 short exclusive -' '1000 studio-test 300 0' >> "$P/.studio/gate.times"
  ( STUDIO_GATE_MINUTES=60; export STUDIO_GATE_MINUTES; dl $((now + 3600)) $((now + 2700)) fits studio-test; printf '%s|%s' "$DL_STATUS" "$DL_OUT" ) > "$TMP/gh.out"
  assert_eq "0|fits: studio-test ~30 min, 45 min to wrap" "$(cat "$TMP/gh.out")" "only rc 0 main-lane 8-field rows count: 4 is too few"
}
test_deadline_fits_agent() {
  now="$(date +%s)"
  dl $((now + 1500)) $((now + 900)) fits agent
  assert_eq "1 does not fit: agent ~20 min, 15 min to wrap at $(hm $((now + 900)))" "$DL_STATUS $DL_OUT" "a subagent is 20 min: not in 15"
  dl $((now + 3600)) $((now + 2700)) fits agent
  assert_eq "0 fits: agent ~20 min, 45 min to wrap" "$DL_STATUS $DL_OUT" "20 min fits in 45"
  ( STUDIO_DEADLINE_AGENT_MIN=10; export STUDIO_DEADLINE_AGENT_MIN; dl $((now + 1500)) $((now + 900)) fits agent; printf '%s|%s' "$DL_STATUS" "$DL_OUT" ) > "$TMP/ag.out"
  assert_eq "0|fits: agent ~10 min, 15 min to wrap" "$(cat "$TMP/ag.out")" "STUDIO_DEADLINE_AGENT_MIN sets the subagent's minutes"
  for _am in 0 x 00; do
    ( STUDIO_DEADLINE_AGENT_MIN="$_am"; export STUDIO_DEADLINE_AGENT_MIN; dl $((now + 1500)) $((now + 900)) fits agent; printf '%s|%s' "$DL_STATUS" "$DL_OUT" ) > "$TMP/ag.out"
    assert_eq "1|does not fit: agent ~20 min, 15 min to wrap at $(hm $((now + 900)))" "$(cat "$TMP/ag.out")" "STUDIO_DEADLINE_AGENT_MIN=$_am is 20"
  done
  dl $((now + 1500)) $((now + 900)) fits agent 5
  assert_eq "0 fits: agent ~5 min, 15 min to wrap" "$DL_STATUS $DL_OUT" "<minutes> wins for agent: 5 fits in 15"
  dl $((now + 60)) $((now - 60)) fits agent
  assert_eq 1 "$DL_STATUS" "past WRAP_AT nothing fits"
}
test_deadline_fits_few_rows() {
  now="$(date +%s)"; rows studio-test 2 300
  ( STUDIO_GATE_MINUTES=60; export STUDIO_GATE_MINUTES
    dl $((now + 3600)) $((now + 2700)) fits studio-test; printf '%s|%s\n' "$DL_STATUS" "$DL_OUT"
    dl $((now + 3600)) $((now + 1500)) fits studio-test; printf '%s|%s\n' "$DL_STATUS" "$DL_OUT"
    dl $((now + 3600)) $((now + 1500)) fits studio-test 12; printf '%s|%s\n' "$DL_STATUS" "$DL_OUT" ) > "$TMP/few.out"
  assert_eq "0|fits: studio-test ~30 min, 45 min to wrap" "$(sed -n 1p "$TMP/few.out")" "2 rows: STUDIO_GATE_MINUTES 60 / 2 = 30 min"
  assert_eq "1|does not fit: studio-test ~30 min, 25 min to wrap at $(hm $((now + 1500)))" "$(sed -n 2p "$TMP/few.out")" "30 min does not fit in 25"
  assert_eq "0|fits: studio-test ~12 min, 25 min to wrap" "$(sed -n 3p "$TMP/few.out")" "fewer than 5 rows: <minutes> when given"
  rm -f "$P/.studio/gate.times"
  ( STUDIO_GATE_MINUTES=60; export STUDIO_GATE_MINUTES; dl $((now + 3600)) $((now + 2700)) fits studio-test; printf '%s|%s' "$DL_STATUS" "$DL_OUT" ) > "$TMP/none.out"
  assert_eq "0|fits: studio-test ~30 min, 45 min to wrap" "$(cat "$TMP/none.out")" "no gate.times at all: the same fallback"
}
test_deadline_usage() {
  now="$(date +%s)"
  for _a in "fits" "fits studio-test x" "fits studio-test 0" "bogus" "fits a b c"; do
    dl $((now + 3600)) $((now + 2700)) $_a
    assert_eq 2 "$DL_STATUS" "'$_a': usage, exit 2"
    assert_contains "$TMP/dl.err" "^usage: studio-deadline" "'$_a': the usage line on stderr"
  done
  dl - - --help
  assert_eq 0 "$DL_STATUS" "--help exits 0"
  assert_contains "$TMP/dl.out" "STUDIO_UNIT_WRAP_AT" "--help names STUDIO_UNIT_WRAP_AT"
}

run_tests test_deadline_outside_a_unit test_deadline_left_and_wrap test_deadline_fits_from_history \
  test_deadline_fits_agent test_deadline_fits_few_rows test_deadline_usage
