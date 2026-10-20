#!/bin/sh
# Suite for studio-gate's lane state model (#71 R3, spec §7): the main lane
# (gate.lock/), the one short slot (gate.short/), the exclusive reservation
# (gate.wantx/), admission under the reclaim mutex, D10/D11 staleness, the
# waiting line and its reasons, re-entry, signals and the lane/class rows.
# Offline; a stub studio and temp repos with linked worktrees
# (tests/gate_lanes_fixture.sh). Every order is event-driven: a run holds on a
# file, the test waits for a mark or a `gate: waiting` line, then releases.
# Test-only knobs set here (lanes_init): STUDIO_GATE_POLL_SECONDS=0.1
# (production 1), STUDIO_GATE_LOADAVG and STUDIO_GATE_PHYS_CORES (production:
# the machine is read).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/tests/gate_times_rows.sh"
unset STUDIO_START_DIR STUDIO_GATE_HELD STUDIO_GATE_LANE STUDIO_GATE_DEMOTE STUDIO_UNIT_TAG \
      STUDIO_GATE_MINUTES STUDIO_GATE_SECONDS
BIN="$REPO_ROOT/studios/game-dev/bin"
mk_tmp gate_lanes_test
trap 'rm_tmp "$TMP"' EXIT
. "$REPO_ROOT/tests/gate_lanes_fixture.sh"

before_each() { lanes_init; }

# gtf — the project's gate.times.
gtf() { printf '%s\n' "$LR/.studio/gate.times"; }
# row67 WHO — fields 6 and 7 (lane, class) of WHO's newest row.
row67() { gt_row "$(gtf)" "$1" | awk '{ print $6, $7 }'; }
# mark TAG N — field N of TAG's first start mark.
mark() { awk -v t="$1" -v n="$2" '$1 == "s" && $2 == t { print $n; exit }' "$LANES_MARKS"; }
# mark_pwd TAG — the worktree (the rest of the line after field 6) of TAG's first start mark.
mark_pwd() { awk -v t="$1" '$1 == "s" && $2 == t { sub(/^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ /, ""); print; exit }' "$LANES_MARKS"; }
# starts TAG — how many start marks TAG has.
starts() { awk -v t="$1" '$1 == "s" && $2 == t { n++ } END { print n + 0 }' "$LANES_MARKS"; }
# gone PID — true once PID is no longer a live process.
gone() { ! kill -0 "$1" 2>/dev/null; }

# exclusive-scan: test_lanes_beside_shareable out (d) order only: the short completes while the suite holds on its file
test_lanes_beside_shareable() {
  lanes_repo beside; A="$(lanes_wt A)"; B="$(lanes_wt B)"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_gut short "$B"; lanes_go short
  assert_eq 0 "$(lanes_done short)" "a GUT short in another worktree completes while the suite holds"
  assert_eq yes "$(lanes_overlap suite short)" "the short ran beside the suite"
  assert_eq "short short" "$(row67 studio-test-file)" "the short's row has lane short, class short"
  _w="$(gt_row "$(gtf)" studio-test-file | awk '{ print $5 }')"
  assert_eq 1 "$([ "${_w:-99}" -le 3 ] && echo 1 || echo 0)" "the short waited 3 s or less ($_w)"
  lanes_go suite
  assert_eq 0 "$(lanes_done suite)" "the suite exits 0"
  assert_eq "main shareable" "$(row67 studio-test)" "the suite's row has class shareable"
}

# exclusive-scan: test_lanes_never_beside_exclusive out (d) order only: event waits on marks and the waiting line
test_lanes_never_beside_exclusive() {
  lanes_repo nbx; B="$(lanes_wt B)"
  lanes_x x "$LR"; lanes_wait_mark '^s x '
  lanes_gut short "$B"; lanes_go short
  lanes_wait_err short '; short lane: beside exclusive$'
  assert_contains "$TMP/err.short" '^gate: waiting for x (pid [0-9]*); short lane: beside exclusive$' "the short names the exclusive holder and its reason"
  assert_eq 0 "$(starts short)" "the short does not start beside an exclusive holder"
  lanes_go x
  assert_eq 0 "$(lanes_done x)" "the exclusive run exits 0"
  assert_eq 0 "$(lanes_done short)" "the short runs once the exclusive holder is gone"
  assert_eq no "$(lanes_overlap x short)" "never beside an exclusive holder"
  # Recorded deviation: once main is free the short prefers the free slot (spec §7 table).
  assert_eq "short short" "$(row67 studio-test-file)" "after the holder leaves, the short takes the free slot"
}

# exclusive-scan: test_lanes_drain_and_no_starvation out (d) order only: event waits on marks, wantx and the waiting line
test_lanes_drain_and_no_starvation() {
  lanes_repo drain; B="$(lanes_wt B)"; C="$(lanes_wt C)"
  lanes_vitest S1 "$B"; lanes_wait_mark '^s S1 short '
  lanes_x X "$LR"
  lanes_wait_file "$LR/.studio/gate.wantx/*"
  _xp="$(cat "$TMP/pid.X" 2>/dev/null)"
  assert_file "$LR/.studio/gate.wantx/$_xp" "the waiting exclusive caller is registered as gate.wantx/<its pid>"
  lanes_gut S2 "$C"; lanes_go S2
  lanes_wait_err S2 '; short lane: exclusive waiting$'
  assert_contains "$TMP/err.S2" '; short lane: exclusive waiting$' "a newcomer is refused while an exclusive caller waits"
  lanes_go S1
  lanes_wait_mark '^s X '
  assert_eq 0 "$(starts S2)" "the exclusive caller starts before the newcomer"
  lanes_go X
  assert_eq 0 "$(lanes_done X)" "the exclusive run exits 0"
  assert_eq 0 "$(lanes_done S2)" "the newcomer runs after it"
  assert_eq 0 "$(lanes_done S1)" "the first short exits 0"
  assert_eq "s S1 e S1 s X e X s S2" "$(awk '{ printf "%s%s %s", sep, $1, $2; sep = " " }' "$LANES_MARKS" | cut -d' ' -f1-10)" "the slot drains, then the exclusive caller, then the newcomer"
  assert_eq "no no" "$(lanes_overlap X S1) $(lanes_overlap X S2)" "the exclusive run overlaps nothing"
  assert_missing "$LR/.studio/gate.wantx/$_xp" "the reservation is gone once it took the main lane"
}

# exclusive-scan: test_lanes_three_way_never_overlaps_exclusive out (d) order only; 1 s holds, no upper bound
test_lanes_three_way_never_overlaps_exclusive() {
  lanes_repo three; A="$(lanes_wt A)"; B="$(lanes_wt B)"; C="$(lanes_wt C)"
  LANES_SLEEP=1; export LANES_SLEEP
  lanes_x x1 "$LR"; lanes_x x2 "$LR"; lanes_suite s1 "$A"; lanes_suite s2 "$B"
  lanes_gut g1 "$B"; lanes_gut g2 "$C"; lanes_vitest v1 "$C"
  _rcs=""
  for _t in x1 x2 s1 s2 g1 g2 v1; do _rcs="$_rcs$(lanes_done "$_t") "; done
  unset LANES_SLEEP
  assert_eq "0 0 0 0 0 0 0 " "$_rcs" "all seven callers exit 0"
  assert_eq "7 7" "$(grep -c '^s ' "$LANES_MARKS") $(grep -c '^e ' "$LANES_MARKS")" "all seven ran to the end"
  _bad=""
  for _x in x1 x2; do
    for _o in x1 x2 s1 s2 g1 g2 v1; do
      [ "$_o" != "$_x" ] || continue
      [ "$(lanes_overlap "$_x" "$_o")" = no ] || _bad="$_bad $_x/$_o"
    done
  done
  assert_eq "" "$_bad" "no exclusive interval overlaps any other run"
}

# exclusive-scan: test_lanes_same_worktree_gut_goes_main out (d) order only: event waits on marks and the waiting line
test_lanes_same_worktree_gut_goes_main() {
  lanes_repo samewt; A="$(lanes_wt A)"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_gut g "$A"; lanes_go g
  lanes_wait_err g '; short lane: same worktree$'
  assert_contains "$TMP/err.g" '^gate: waiting for studio-test (pid [0-9]*); short lane: same worktree$' "a GUT short beside a suite in its own worktree is refused"
  assert_eq 0 "$(starts g)" "it does not start beside the suite"
  lanes_go suite
  assert_eq "0 0" "$(lanes_done suite) $(lanes_done g)" "both exit 0"
  assert_eq no "$(lanes_overlap suite g)" "no overlap in one worktree"
  # Recorded deviation: same-wt also bars the main lane (spec §7 table), so once
  # the suite is gone the short takes the free slot, not main:same-worktree.
  assert_eq "short short" "$(row67 studio-test-file)" "once the suite is gone it takes the free slot"
  # Beside a GUT short of its own worktree in the slot, a GUT short waits even
  # with the main lane free.
  lanes_gut g1 "$A"; lanes_wait_mark '^s g1 short '
  lanes_gut g2 "$A"; lanes_go g2
  lanes_wait_err g2 'short lane'
  assert_contains "$TMP/err.g2" '^gate: waiting for studio-test-file (pid [0-9]*, short lane); short lane: same worktree$' "a same-worktree short is refused beside the slot holder"
  assert_missing "$LR/.studio/gate.lock" "the main lane is free"
  assert_eq 0 "$(starts g2)" "and it does not take it"
  lanes_go g1
  assert_eq "0 0" "$(lanes_done g1) $(lanes_done g2)" "both exit 0"
  assert_eq no "$(lanes_overlap g1 g2)" "the two never overlap"
}

# exclusive-scan: test_lanes_node_beside_suite_same_worktree out (d) order only: the vitest completes while the suite holds
test_lanes_node_beside_suite_same_worktree() {
  lanes_repo nodewt; A="$(lanes_wt A)"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_vitest v "$A"; lanes_go v
  assert_eq 0 "$(lanes_done v)" "a vitest from the suite's own worktree completes while the suite holds"
  assert_eq yes "$(lanes_overlap suite v)" "a node check beside a Godot suite in one worktree is not same-wt (O14)"
  assert_eq "short short" "$(row67 vitest)" "its row has lane short"
  lanes_go suite
  assert_eq 0 "$(lanes_done suite)" "the suite exits 0"
}

# exclusive-scan: test_lanes_second_node_same_worktree_waits out (d) order only: event waits on marks and the waiting line
test_lanes_second_node_same_worktree_waits() {
  lanes_repo node2; A="$(lanes_wt A)"; B="$(lanes_wt B)"
  lanes_suite suite "$B"; lanes_wait_mark '^s suite '
  lanes_vitest V1 "$A"; lanes_wait_mark '^s V1 short '
  lanes_vitest V2 "$A"; lanes_go V2
  lanes_wait_err V2 '; short lane: same worktree$'
  assert_contains "$TMP/err.V2" '; short lane: same worktree$' "a second node check from the slot holder's worktree is refused"
  assert_eq 0 "$(starts V2)" "it cannot take the main lane either (the suite holds it), so it waits"
  lanes_go V1
  assert_eq "0 0" "$(lanes_done V1) $(lanes_done V2)" "both exit 0"
  assert_eq no "$(lanes_overlap V1 V2)" "the two never overlap"
  lanes_go suite
  assert_eq 0 "$(lanes_done suite)" "the suite exits 0"
}

# exclusive-scan: test_lanes_isolation_needed_for_gut out (d) order only: event waits on marks and the waiting line
test_lanes_isolation_needed_for_gut() {
  lanes_repo iso; A="$(lanes_wt A)"; B="$(lanes_wt B)"
  rm -f "$B/override.cfg"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_gut g "$B"; lanes_go g
  lanes_wait_err g '; short lane: iso$'
  assert_contains "$TMP/err.g" '^gate: waiting for studio-test (pid [0-9]*); short lane: iso$' "a GUT short without isolation is refused the slot"
  lanes_vitest v "$B"; lanes_go v
  assert_eq 0 "$(lanes_done v)" "a vitest from the same worktree still completes beside the suite"
  assert_eq short "$(mark v 3)" "the vitest took the slot"
  lanes_go suite
  assert_eq "0 0" "$(lanes_done suite) $(lanes_done g)" "the suite and the GUT short exit 0"
  assert_eq "main:iso short" "$(row67 studio-test-file)" "the GUT short ran in the main lane, row lane main:iso"
}

# exclusive-scan: test_lanes_load_gate out (d) order only: event waits on the waiting lines
test_lanes_load_gate() {
  lanes_repo load; A="$(lanes_wt A)"; B="$(lanes_wt B)"; C="$(lanes_wt C)"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  for _t in l99 labc l54 l0; do lanes_go "$_t"; done
  lanes_bg l99 "$B" -- env STUDIO_GATE_LOADAVG=99 sh "$BIN/studio-test" --file tests/unit/a.gd
  lanes_wait_err l99 'short lane: load'
  assert_contains "$TMP/err.l99" '^gate: waiting for studio-test (pid [0-9]*); short lane: load 99/8$' "a load at the threshold is refused (99/8)"
  lanes_bg labc "$B" -- env STUDIO_GATE_LOADAVG=abc sh "$BIN/studio-test" --file tests/unit/a.gd
  lanes_wait_err labc 'short lane: load'
  assert_contains "$TMP/err.labc" '; short lane: load ?/8$' "an unreadable load is refused (?/8)"
  lanes_bg l54 "$C" -- env STUDIO_GATE_PHYS_CORES=2 STUDIO_GATE_LOADAVG=5 sh "$BIN/studio-test" --file tests/unit/a.gd
  lanes_wait_err l54 'short lane: load'
  assert_contains "$TMP/err.l54" '; short lane: load 5/4$' "the threshold is 2 x the physical cores (5/4)"
  lanes_bg l0 "$C" -- env STUDIO_GATE_LOADAVG=0 sh "$BIN/studio-test" --file tests/unit/a.gd
  assert_eq 0 "$(lanes_done l0)" "a load of 0 is admitted while the suite holds"
  assert_eq short "$(mark l0 3)" "it ran in the slot"
  lanes_go suite
  assert_eq "0 0 0 0" "$(lanes_done suite) $(lanes_done l99) $(lanes_done labc) $(lanes_done l54)" "every caller exits 0"
}

# exclusive-scan: test_lanes_nice_only_in_slot out (d) order only: event waits on marks
test_lanes_nice_only_in_slot() {
  _base="$(ps -o nice= -p $$ | tr -d ' ')"
  lanes_repo nice; A="$(lanes_wt A)"; B="$(lanes_wt B)"; C="$(lanes_wt C)"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_vitest v "$B"; lanes_wait_mark '^s v '
  assert_eq "main $_base" "$(mark suite 3) $(mark suite 4)" "a suite (main lane) is not niced"
  assert_eq "short $((_base + 10))" "$(mark v 3) $(mark v 4)" "the slot run is niced by 10"
  lanes_go v; lanes_go suite
  assert_eq "0 0" "$(lanes_done v) $(lanes_done suite)" "both exit 0"
  # A short that took the main lane: refused the slot (iso) with main free.
  rm -f "$C/override.cfg"
  lanes_gut g "$C"; lanes_wait_mark '^s g '
  assert_eq "main $_base" "$(mark g 3) $(mark g 4)" "a short that took the main lane is not niced"
  lanes_go g
  assert_eq 0 "$(lanes_done g)" "the short exits 0"
  assert_eq "main:iso short" "$(row67 studio-test-file)" "it ran in the main lane"
}

# exclusive-scan: test_lanes_lane_off_is_today out (d) order only: event waits on marks and the waiting line
test_lanes_lane_off_is_today() {
  lanes_repo off; A="$(lanes_wt A off)"; B="$(lanes_wt B off)"
  printf '{"engine": "godot4"}\n' > "$LR/.studio/config.json"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_gut g "$B"; lanes_go g
  lanes_wait_err g '^gate: waiting'
  assert_eq 0 "$(starts g)" "with the lane off the short waits behind the suite"
  lanes_go suite
  assert_eq "0 0" "$(lanes_done suite) $(lanes_done g)" "both exit 0"
  assert_eq no "$(lanes_overlap suite g)" "no overlap"
  assert_eq 1 "$(grep -c '' "$TMP/err.g")" "one stderr line"
  assert_contains "$TMP/err.g" '^gate: waiting for studio-test (pid [0-9]*)$' "the waiting line is today's, byte for byte"
  assert_not_contains "$TMP/err.g" 'short lane' "no short lane reason is printed"
  assert_eq "main:off exclusive" "$(row67 studio-test-file)" "the short's row: lane main:off, class exclusive"
  assert_eq "main exclusive" "$(row67 studio-test)" "the suite's row: lane main, class exclusive"
  assert_eq 0 "$(ls "$LR/.studio" | grep -c '^gate\.short')" "no gate.short appears"
}

# exclusive-scan: test_lanes_mixed_lane_off_waiter_waits_for_drain out (d) order only: event waits on marks and the waiting line
test_lanes_mixed_lane_off_waiter_waits_for_drain() {
  lanes_repo mixed; B="$(lanes_wt B)"; C="$(lanes_wt C off)"
  lanes_vitest v "$B"; lanes_wait_mark '^s v short '
  _vp="$(cat "$TMP/pid.v" 2>/dev/null)"
  lanes_gut g "$C"; lanes_go g
  lanes_wait_err g '^gate: waiting'
  assert_missing "$LR/.studio/gate.lock" "the main lane is free"
  assert_contains "$TMP/err.g" "^gate: waiting for vitest (pid $_vp, short lane)\$" "the lane-off caller waits for the slot to drain and names its holder"
  assert_eq 0 "$(starts g)" "it is not admitted beside the slot holder"
  lanes_go v
  assert_eq "0 0" "$(lanes_done v) $(lanes_done g)" "both exit 0"
  assert_eq no "$(lanes_overlap v g)" "no overlap"
  assert_eq "main:off exclusive" "$(row67 studio-test-file)" "the lane-off short's row: lane main:off, class exclusive"
}

# exclusive-scan: test_lanes_run_fallback_turns_lane_on out (d) event waits only
test_lanes_run_fallback_turns_lane_on() {
  lanes_repo fallback; W="$(lanes_wt S)"
  rm -f "$W/.studio/config.json"
  lanes_go v1; lanes_go v2
  lanes_bg v1 "$W/web-tools" -- env STUDIO_START_DIR="$LR" sh "$LANES_GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  assert_eq 0 "$(lanes_done v1)" "the vitest exits 0"
  assert_eq short "$(mark v1 3)" "with STUDIO_START_DIR's lane on, a story worktree without the key uses the slot"
  lanes_vitest v2 "$W"
  assert_eq 0 "$(lanes_done v2)" "the vitest exits 0"
  assert_eq main "$(mark v2 3)" "without it the lane is off"
  assert_eq "main:off exclusive" "$(row67 vitest)" "row lane main:off"
}

# exclusive-scan: test_lanes_stale_slot_reclaimed out (d) event waits only
test_lanes_stale_slot_reclaimed() {
  lanes_repo stale; A="$(lanes_wt A)"
  sleep 30 & _sp=$!
  for _c in dead nopid notgate; do
    mkdir -p "$LR/.studio/gate.short"
    printf 'x\n' > "$LR/.studio/gate.short/who"
    case "$_c" in
      dead) printf '999999\n' > "$LR/.studio/gate.short/pid" ;;
      notgate) printf '%s\n' "$_sp" > "$LR/.studio/gate.short/pid" ;;
    esac
    lanes_go "v$_c"; lanes_vitest "v$_c" "$A"
    assert_eq 0 "$(lanes_done "v$_c")" "the vitest exits 0 ($_c)"
    assert_eq short "$(mark "v$_c" 3)" "a slot whose holder is $_c is reclaimed: the short runs in the slot"
    assert_missing "$LR/.studio/gate.short" "the slot is released ($_c)"
  done
  kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null
}

# exclusive-scan: test_lanes_dead_wantx_ignored out (d) event waits only
test_lanes_dead_wantx_ignored() {
  lanes_repo deadx; A="$(lanes_wt A)"
  mkdir -p "$LR/.studio/gate.wantx"; printf '1 x\n' > "$LR/.studio/gate.wantx/999999"
  lanes_go v; lanes_vitest v "$A"
  assert_eq 0 "$(lanes_done v)" "the vitest exits 0"
  assert_eq short "$(mark v 3)" "a dead reservation does not keep a short out of the slot"
  assert_missing "$LR/.studio/gate.wantx/999999" "and it is removed"
}

# exclusive-scan: test_lanes_classless_main_blocks_slot out (d) event waits only
test_lanes_classless_main_blocks_slot() {
  lanes_repo classless; A="$(lanes_wt A)"
  sleep 30 & _sp=$!
  mkdir -p "$LR/.studio/gate.lock"; printf '%s\n' "$_sp" > "$LR/.studio/gate.lock/pid"; printf 'planted\n' > "$LR/.studio/gate.lock/who"
  lanes_gut g "$A"; lanes_go g
  lanes_wait_err g 'short lane'
  assert_contains "$TMP/err.g" "^gate: waiting for planted (pid $_sp); short lane: beside exclusive\$" "a main holder with no class counts as exclusive (D11)"
  assert_eq 0 "$(starts g)" "the short waits"
  kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null
  assert_eq 0 "$(lanes_done g)" "once the holder is dead the short proceeds"
  assert_eq short "$(mark g 3)" "in the slot"
}

# exclusive-scan: test_lanes_reentry_under_slot out (d) event waits only
test_lanes_reentry_under_slot() {
  lanes_repo nest; A="$(lanes_wt A)"
  lanes_go n
  lanes_bg n "$A/web-tools" -- env LANES_NEST=1 sh "$LANES_GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  assert_eq 0 "$(lanes_done n)" "the vitest exits 0"
  assert_eq short "$(mark n 3)" "it ran in the slot"
  assert_not_contains "$TMP/err.n" 'gate: waiting' "the nested gate under the slot holder never waits"
  assert_eq 1 "$(grep -c '' "$(gtf)")" "exactly one row"
}

# exclusive-scan: test_lanes_signal_in_slot out (b) the TERM goes to a gate this test started, after its mark; no window
test_lanes_signal_in_slot() {
  lanes_repo sigslot; A="$(lanes_wt A)"
  lanes_vitest v "$A"; lanes_wait_mark '^s v short '
  _gp="$(cat "$LR/.studio/gate.short/pid" 2>/dev/null)"
  assert_eq "$(cat "$TMP/pid.v")" "$_gp" "gate.short/pid is the gate's pid"
  kill -TERM "$_gp"
  assert_eq 143 "$(lanes_done v)" "TERM to the slot holder exits 143"
  assert_missing "$LR/.studio/gate.short" "the slot is released"
  assert_eq 1 "$(starts v)" "no re-run"
  assert_eq 1 "$(gt_rows "$(gtf)" vitest 143)" "the signalled run is logged with 143"
}

# exclusive-scan: test_lanes_unit_registration_in_slot out (b) the TERM goes to a gate this test started (as unit_reap sends it); no window
test_lanes_unit_registration_in_slot() {
  lanes_repo unit; A="$(lanes_wt A)"
  lanes_bg u "$A/web-tools" -- env STUDIO_UNIT_TAG=u1 sh "$LANES_GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  lanes_wait_mark '^s u short '
  _gp="$(cat "$LR/.studio/gate.short/pid" 2>/dev/null)"
  assert_eq "$(mark u 5)" "$(cat "$LR/.studio/gate.units/u1/$_gp" 2>/dev/null)" "gate.units/u1/<gate pid> holds the slot child's pid"
  assert_eq u1 "$(cat "$LR/.studio/gate.short/unit" 2>/dev/null)" "the slot records the unit"
  kill -TERM "$_gp"
  assert_eq 143 "$(lanes_done u)" "TERM to the registered gate ends it with 143"
  assert_missing "$LR/.studio/gate.units/u1/$_gp" "the registration is removed"
}

# exclusive-scan: test_lanes_waiting_messages in (a) the reason is printed on the first poll, within 2 s
test_lanes_waiting_messages() {
  lanes_repo wmsg; A="$(lanes_wt A)"; B="$(lanes_wt B)"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_go l99
  _t0="$(date +%s)"
  lanes_bg l99 "$B" -- env STUDIO_GATE_LOADAVG=99 sh "$BIN/studio-test" --file tests/unit/a.gd
  lanes_wait_err l99 'short lane: load'
  _el=$(( $(date +%s) - _t0 ))
  assert_eq 1 "$([ "$_el" -le 2 ] && echo 1 || echo 0)" "the reason is printed on the first poll, before any 60 s tick ($_el s)"
  assert_contains "$TMP/err.l99" '^gate: waiting for [^ ]* (pid [0-9]*' "the line's prefix is unchanged"
  lanes_go suite
  assert_eq "0 0" "$(lanes_done suite) $(lanes_done l99)" "both exit 0"
  lanes_vitest v "$B"; lanes_wait_mark '^s v short '
  _vp="$(cat "$TMP/pid.v" 2>/dev/null)"
  lanes_go x1; lanes_x x1 "$LR"
  lanes_wait_err x1 '^gate: waiting'
  assert_contains "$TMP/err.x1" "^gate: waiting for vitest (pid $_vp, short lane)\$" "an exclusive caller blocked only by the slot names the slot's holder"
  printf '%s\n' "$(( $(date +%s) - 400 ))" > "$LR/.studio/gate.short/since"
  lanes_go x2; lanes_x x2 "$LR"
  lanes_wait_err x2 '^gate: waiting'
  assert_contains "$TMP/err.x2" "^gate: waiting for vitest (pid $_vp, short lane) (short lane past its cap — stuck?)\$" "a live slot holder past its cap + 60 s is flagged"
  lanes_go v
  assert_eq "0 0 0" "$(lanes_done v) $(lanes_done x1) $(lanes_done x2)" "all exit 0"
}

# exclusive-scan: test_lanes_rows_record_lane_and_class out (d) order only: event waits on marks
test_lanes_rows_record_lane_and_class() {
  lanes_repo rows; A="$(lanes_wt A)"; B="$(lanes_wt B)"; C="$(lanes_wt C)"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_go v; lanes_vitest v "$B"
  assert_eq 0 "$(lanes_done v)" "the slot run exits 0"
  lanes_go suite
  assert_eq 0 "$(lanes_done suite)" "the suite exits 0"
  rm -f "$C/override.cfg"
  lanes_go g; lanes_gut g "$C"
  assert_eq 0 "$(lanes_done g)" "the main-lane short exits 0"
  lanes_go x; lanes_x x "$LR"
  assert_eq 0 "$(lanes_done x)" "the exclusive run exits 0"
  assert_eq "main shareable" "$(row67 studio-test)" "suite: lane main, class shareable"
  assert_eq "short short" "$(row67 vitest)" "slot: lane short, class short"
  assert_eq "main:iso short" "$(row67 studio-test-file)" "main-lane short: lane main:<reason>, class short"
  assert_eq "main exclusive" "$(row67 x)" "exclusive: lane main, class exclusive"
}

# exclusive-scan: test_lanes_space_in_worktree_path out (d) order only: event waits on marks
test_lanes_space_in_worktree_path() {
  lanes_repo spaced; W="$(lanes_wt "w b")"
  lanes_gut g1 "$W"; lanes_wait_mark '^s g1 short '
  assert_eq "$W" "$(cat "$LR/.studio/gate.short/wt" 2>/dev/null)" "gate.short/wt is the spaced worktree path"
  assert_eq "$W" "$(mark_pwd g1)" "the slot run's cwd is that worktree"
  # Recorded deviation: same-wt bars both lanes (spec §7), so it waits, not main.
  lanes_gut g2 "$W"; lanes_go g2
  lanes_wait_err g2 'short lane'
  assert_contains "$TMP/err.g2" '; short lane: same worktree$' "a GUT short from the same spaced worktree is same-wt"
  assert_eq 0 "$(starts g2)" "it waits for the slot holder"
  lanes_go g1
  assert_eq "0 0" "$(lanes_done g1) $(lanes_done g2)" "both exit 0"
  assert_eq no "$(lanes_overlap g1 g2)" "the two never overlap"
}

# exclusive-scan: test_lanes_slot_holder_under_spaced_bin out (d) order only: event waits on marks and the waiting line
test_lanes_slot_holder_under_spaced_bin() {
  lanes_repo spbin; A="$(lanes_wt A)"; B="$(lanes_wt B)"; C="$(lanes_wt C)"
  mkdir -p "$TMP/a b/bin"; cp -R "$BIN/." "$TMP/a b/bin/"
  lanes_suite suite "$A"; lanes_wait_mark '^s suite '
  lanes_bg v1 "$B/web-tools" -- sh "$TMP/a b/bin/studio-gate" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
  lanes_wait_mark '^s v1 short '
  lanes_vitest v2 "$C"; lanes_go v2
  lanes_wait_err v2 'short lane'
  assert_contains "$TMP/err.v2" '; short lane: slot busy$' "a slot holder whose gate path holds a space is a live gate (D10)"
  assert_eq 0 "$(starts v2)" "the slot is not reclaimed from it"
  lanes_go v1
  assert_eq "0 0" "$(lanes_done v1) $(lanes_done v2)" "both exit 0"
  assert_eq no "$(lanes_overlap v1 v2)" "never two slot holders"
  lanes_go suite
  assert_eq 0 "$(lanes_done suite)" "the suite exits 0"
}

# Preflight F7: a suite (main) and a short (slot) end on one hold-file touch and
# append at once, five rounds; the mutex keeps every row (spec D9).
# exclusive-scan: test_lanes_rows_no_loss_two_lanes out (d) order only: event waits on marks
test_lanes_rows_no_loss_two_lanes() {
  lanes_repo noloss; A="$(lanes_wt A)"; B="$(lanes_wt B)"
  for _n in 1 2 3 4 5; do
    lanes_bg "s$_n" "$A" -- env LANES_HOLD="r$_n" sh "$BIN/studio-test"
    lanes_wait_mark "^s s$_n "
    lanes_bg "v$_n" "$B/web-tools" -- env LANES_HOLD="r$_n" sh "$LANES_GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
    lanes_wait_mark "^s v$_n short "
    lanes_go "r$_n"
    assert_eq "0 0" "$(lanes_done "s$_n") $(lanes_done "v$_n")" "round $_n: both exit 0"
  done
  assert_eq 5 "$(gt_rows "$(gtf)" studio-test 0)" "every suite row is kept"
  assert_eq 5 "$(gt_rows "$(gtf)" vitest 0)" "every slot row is kept"
}

# T2 review ruling: a TERM after the command ended (the gate.times mutex wait)
# keeps the command's status and its row; a signalled waiter's release removes
# its gate.times.<pid> temp file.
# exclusive-scan: test_lanes_signal_after_command_keeps_rc in (b) the TERM must land inside the ~5 s post-command mutex wait
test_lanes_signal_after_command_keeps_rc() {
  lanes_repo late
  sleep 60 & _sp=$!
  lanes_bg w "$LR" -- sh "$LANES_GATE" w -- sh -c "ln -s $_sp '$LR/.studio/gate.lock.mutex'; echo \$\$ > '$TMP/late.cpid'; exit 3"
  lanes_wait_file "$TMP/late.cpid"
  _lanes_poll gone "$(cat "$TMP/late.cpid")"
  sleep 1
  _gp="$(cat "$TMP/pid.w" 2>/dev/null)"
  _alive=no; kill -0 "$_gp" 2>/dev/null && _alive=yes
  assert_eq yes "$_alive" "the gate is still in its post-command mutex wait"
  kill -TERM "$_gp"
  assert_eq 3 "$(lanes_done w)" "a TERM after the command ended keeps the command's status"
  assert_eq 1 "$(gt_rows "$(gtf)" w 3)" "and its row"
  assert_eq 0 "$(ls "$LR/.studio" | grep -c '^gate\.times\.')" "no gate.times temp file is left"
  assert_missing "$LR/.studio/gate.lock" "the lock is released"
  assert_eq "$_sp" "$(readlink "$LR/.studio/gate.lock.mutex" 2>/dev/null)" "the live owner's mutex is untouched"
  rm -f "$LR/.studio/gate.lock.mutex"
  kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null
  lanes_x xh "$LR"; lanes_wait_mark '^s xh '
  lanes_bg ww "$LR" -- sh "$LANES_GATE" ww -- true
  lanes_wait_err ww '^gate: waiting'
  _wp="$(cat "$TMP/pid.ww" 2>/dev/null)"
  : > "$LR/.studio/gate.times.$_wp"
  kill -TERM "$_wp"
  assert_eq 143 "$(lanes_done ww)" "a TERM while waiting exits 143"
  assert_missing "$LR/.studio/gate.times.$_wp" "release removes the gate's gate.times.<pid>"
  lanes_go xh
  assert_eq 0 "$(lanes_done xh)" "the holder exits 0"
}

TESTS_EXCLUSIVE="test_lanes_waiting_messages test_lanes_signal_after_command_keeps_rc"
run_tests test_lanes_beside_shareable test_lanes_never_beside_exclusive test_lanes_drain_and_no_starvation \
  test_lanes_three_way_never_overlaps_exclusive test_lanes_same_worktree_gut_goes_main \
  test_lanes_node_beside_suite_same_worktree test_lanes_second_node_same_worktree_waits \
  test_lanes_isolation_needed_for_gut test_lanes_load_gate test_lanes_nice_only_in_slot \
  test_lanes_lane_off_is_today test_lanes_mixed_lane_off_waiter_waits_for_drain \
  test_lanes_run_fallback_turns_lane_on test_lanes_stale_slot_reclaimed test_lanes_dead_wantx_ignored \
  test_lanes_classless_main_blocks_slot test_lanes_reentry_under_slot test_lanes_signal_in_slot \
  test_lanes_unit_registration_in_slot test_lanes_waiting_messages test_lanes_rows_record_lane_and_class \
  test_lanes_space_in_worktree_path test_lanes_slot_holder_under_spaced_bin test_lanes_rows_no_loss_two_lanes \
  test_lanes_signal_after_command_keeps_rc
