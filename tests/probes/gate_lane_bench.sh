#!/bin/sh
# gate_lane_bench.sh — synthetic benchmark of the gate short lane (#71, spec §13.2).
#
# A fake long shareable holder (the fixture's stub, never real Godot or phoenix)
# runs while 20 short checks are issued beside it, one every 5 s, round-robin
# across 3 linked worktrees: 10 `studio-test --file` and 10 vitest stand-ins
# (the O10 form), each holding 3 s. The probe reads each call's wait (field 5 of
# $LR/.studio/gate.times) and prints
#   short p50 <s> p90 <s>
#   exclusive extra wait <s>
#   PASS | FAIL: <why>
#
# Usage: TMPDIR=<existing dir> gate_lane_bench.sh off|on|exclusive [HOLD_S]
#   on         lane on; the holder is the suite (LANES_SLEEP=HOLD_S, default 180).
#              PASS iff short p90 <= 5.
#   off        lane off; same load. PASS iff short p50 >= 0.4 * HOLD_S.
#   exclusive  lane on; the holder is `x -- sh -c 'sleep 60'`, plus one exclusive
#              caller arriving at t = 30 s. PASS iff the shorts wait behind the
#              holder (p50 > 5) and the exclusive caller's extra wait (its wait
#              minus the time until the holder ended) <= SHORT_SECS + 15.
# Refuses to run inside a git work tree or under ~/GameDev. Not in run_all.sh.
MODE="${1:-}"; HOLD_S="${2:-180}"
SHORT_SECS=300
case "$MODE" in on|off|exclusive) ;; *) echo "usage: $0 off|on|exclusive [HOLD_S]" >&2; exit 2 ;; esac
case "$HOLD_S" in ''|*[!0-9]*) echo "gate_lane_bench: HOLD_S must be digits" >&2; exit 2 ;; esac
[ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] || { echo "gate_lane_bench: TMPDIR must be an existing dir" >&2; exit 2; }
_here="$(cd "$(dirname "$0")" && pwd -P)" || exit 2
BIN="$(cd "$_here/../../studios/game-dev/bin" && pwd -P)" || exit 2
_home_gd="$(cd "$HOME/GameDev" 2>/dev/null && pwd -P)"
for _d in "$(pwd -P)" "$(cd "$TMPDIR" && pwd -P)"; do
  if git -C "$_d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "gate_lane_bench: refused: $_d is inside a git work tree" >&2; exit 2
  fi
  case "$_d/" in "$_home_gd"/*) echo "gate_lane_bench: refused: $_d is under ~/GameDev" >&2; exit 2 ;; esac
done

. "$_here/../gate_lanes_fixture.sh" || exit 2
TMP="$(mktemp -d "$TMPDIR/gate-lane-bench.XXXXXX")" || exit 2
POLL_FAIL=0; TESTS_RUN=0
_fail() { echo "gate_lane_bench: $*" >&2; POLL_FAIL=1; }
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

lanes_init
lanes_repo bench
L=on; [ "$MODE" = off ] && L=off
printf '{"engine": "godot4", "gate_short_lane": "%s"}\n' "$L" > "$LR/.studio/config.json"
W1="$(lanes_wt w1 "$L")"; W2="$(lanes_wt w2 "$L")"; W3="$(lanes_wt w3 "$L")"

# The holder runs in the project checkout itself, not in one of the 3 worktrees:
# a short is never admitted beside a suite of its own worktree (spec §7 same-wt).
# The holder first, then a moment for it to take the main lane.
if [ "$MODE" = exclusive ]; then
  lanes_bg hold "$LR" -- sh "$LANES_GATE" x -- sh -c 'sleep 60'
  sleep 2
else
  LANES_SLEEP="$HOLD_S"; export LANES_SLEEP
  lanes_suite hold "$LR"
  lanes_wait_mark '^s hold '
fi
LANES_SLEEP=3; export LANES_SLEEP

XC_START=""
_n=0
while [ "$_n" -lt 20 ]; do
  if [ "$MODE" = exclusive ] && [ "$_n" -eq 6 ]; then   # t = 30 s
    XC_START="$(date +%s)"; LANES_SLEEP=1; export LANES_SLEEP
    lanes_x xc "$W2"
    LANES_SLEEP=3; export LANES_SLEEP
  fi
  case $((_n % 3)) in 0) _w="$W1" ;; 1) _w="$W2" ;; *) _w="$W3" ;; esac
  if [ $((_n % 2)) -eq 0 ]; then lanes_gut "q$_n" "$_w"; else lanes_vitest "q$_n" "$_w"; fi
  _n=$((_n + 1))
  [ "$_n" -ge 20 ] || sleep 5
done

# Every call must end; a lane-off short can wait the whole hold, so the bound is
# HOLD_S + 300 s (lanes_done's 30 s is for the fixture's quick calls).
_all="hold"; _n=0
while [ "$_n" -lt 20 ]; do _all="$_all q$_n"; _n=$((_n + 1)); done
[ "$MODE" != exclusive ] || _all="$_all xc"
_i=0
for _t in $_all; do
  while [ ! -s "$TMP/rc.$_t" ] && [ "$_i" -lt $(( (HOLD_S + 300) * 10 )) ]; do sleep 0.1; _i=$((_i + 1)); done
  [ -s "$TMP/rc.$_t" ] || _fail "no end for $_t"
done

TIMES="$LR/.studio/gate.times"
[ -f "$TIMES" ] || { echo "FAIL: no gate.times at $TIMES"; exit 1; }
# Shorts are the studio-test-file and vitest rows; wait is field 5.
_waits="$(awk '$2 == "studio-test-file" || $2 == "vitest" { print $5 }' "$TIMES" | sort -n)"
_cnt="$(printf '%s\n' "$_waits" | grep -c .)"
[ "$_cnt" -ge 1 ] || { echo "FAIL: no short rows in $TIMES"; cat "$TIMES"; exit 1; }
_pct() { printf '%s\n' "$_waits" | awk -v p="$1" -v n="$_cnt" 'NR == int((p * n + 99) / 100) { print; exit }'; }
P50="$(_pct 50)"; P90="$(_pct 90)"
echo "short p50 $P50 p90 $P90 (n=$_cnt, mode=$MODE, hold=${HOLD_S}s)"

VERDICT=PASS; WHY=""
[ "$POLL_FAIL" = 0 ] || { VERDICT=FAIL; WHY="a wait timed out"; }
case "$MODE" in
  on) [ "$P90" -le 5 ] || { VERDICT=FAIL; WHY="short p90 $P90 > 5"; } ;;
  off) _min=$((HOLD_S * 4 / 10))
       [ "$P50" -ge "$_min" ] || { VERDICT=FAIL; WHY="short p50 $P50 < 0.4 x HOLD_S ($_min)"; } ;;
  exclusive)
    [ "$P50" -gt 5 ] || { VERDICT=FAIL; WHY="shorts did not wait behind the holder (p50 $P50)"; }
    # The holder is the earlier-ending x row, the exclusive caller the later one.
    _hold_end="$(awk '$2 == "x" { print $1 }' "$TIMES" | sort -n | head -n 1)"
    _xc_wait="$(awk '$2 == "x" { print $1, $5 }' "$TIMES" | sort -n | tail -n 1 | cut -d' ' -f2)"
    _base=$((_hold_end - XC_START)); [ "$_base" -ge 0 ] || _base=0
    _extra=$((_xc_wait - _base)); [ "$_extra" -ge 0 ] || _extra=0
    echo "exclusive extra wait $_extra (wait $_xc_wait, holder ended $_base s after it arrived)"
    [ "$_extra" -le $((SHORT_SECS + 15)) ] || { VERDICT=FAIL; WHY="exclusive extra wait $_extra > $((SHORT_SECS + 15))"; } ;;
esac
[ "$MODE" = exclusive ] || echo "exclusive extra wait n/a"
if [ "$VERDICT" = PASS ]; then echo PASS; exit 0; fi
echo "FAIL: $WHY"
echo "gate.times rows (epoch who hold rc wait lane class unit):"; cat "$TIMES"
exit 1
