#!/bin/sh
# run_all_test.sh — tests/run_all.sh against fake suites. The fixtures write their own
# timing rows (the formats in the harness contract), so these tests do not depend on assert.sh.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/run_all_test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
SD="$TMP/suites"
trap 'rm -rf "$TMP"' EXIT

# fx NAME LISTED [BODY] — fixture suite $SD/NAME_test.sh. It runs BODY (shell text), then
# writes one L row and one T row per idx 1..LISTED for its partition (one assertion each),
# and prints the summary line. It names its partition from TEST_PHASE/TEST_SHARD only.
# FX_ROWS="idx:secs …" overrides the T rows written.
fx() {
  mkdir -p "$SD"
  _fxr="${FX_ROWS:-}"
  if [ -z "$_fxr" ]; then _k=1; while [ "$_k" -le "$2" ]; do _fxr="$_fxr $_k:0"; _k=$((_k + 1)); done; fi
  cat > "$SD/$1_test.sh" <<FXEOF
pt=all
case "\${TEST_PHASE:-}" in parallel) s="\${TEST_SHARD:-1/1}"; pt="p\${s%/*}of\${s#*/}" ;; exclusive) pt=x ;; esac
row() { [ -z "\${TEST_TIMING_LOG:-}" ] || printf '%s\n' "\$1" >> "\$TEST_TIMING_LOG"; }
row "\$(printf 'L\t%s\t%s\t%s\t-' $1_test "\$pt" $2)"
${3:-:}
for r in $_fxr; do i=\${r%:*}; sec=\${r#*:}; row "\$(printf 'T\t%s\t%s\t%s\tt%s\t%s\t1\t0' $1_test "\$pt" "\$i" "\$i" "\$sec")"; done
printf '\n%s assertions, 0 failed\n' $2
FXEOF
}
# SLOT: a fixture body that holds a slot for 1 s, recording the max live count in $TMP/slots.max.
SLOT='while ! mkdir "'"$TMP"'/slots.lk" 2>/dev/null; do sleep 0.05; done
n=$(( $(cat "'"$TMP"'/slots.n" 2>/dev/null || echo 0) + 1 )); echo $n > "'"$TMP"'/slots.n"
[ $n -le $(cat "'"$TMP"'/slots.max" 2>/dev/null || echo 0) ] || echo $n > "'"$TMP"'/slots.max"
rmdir "'"$TMP"'/slots.lk"; sleep 1
while ! mkdir "'"$TMP"'/slots.lk" 2>/dev/null; do sleep 0.05; done
echo $(( $(cat "'"$TMP"'/slots.n") - 1 )) > "'"$TMP"'/slots.n"; rmdir "'"$TMP"'/slots.lk"'
SLOTX="$(printf '%s' "$SLOT" | sed 's/slots\./slotsx./g')"

reset() { rm -rf "$SD" "$TMP"/slots* "$TMP/order" "$TMP/phase"; mkdir -p "$SD"; : > "$TMP/table"; }
# HERMETIC: the run_all knobs a caller may have exported (TEST_SUITES=run_all from run_affected,
# TESTS_ONLY from a developer focusing one test), reset to their defaults (empty) for a nested
# run. TEST_SH is kept on purpose: the dash acceptance run passes it down.
HERMETIC="TEST_SUITES= TESTS_ONLY= TEST_JOB_TIMEOUT= TEST_SLOWEST= TEST_JOBS= TEST_LOG_DIR= TEST_PHASE= TEST_SHARD= TEST_TIMING_LOG="
# ra NAME [VAR=val …] — run run_all.sh on the fixtures; output in $TMP/NAME.out, status in $RC.
ra() {
  _n="$1"; shift; RC=0
  env $HERMETIC RUN_ALL_SUITES_DIR="$SD" RUN_ALL_TABLE="$TMP/table" TEST_LOG_DIR="$TMP/log-$_n" TEST_JOBS=3 "$@" \
    ${TEST_SH:-sh} "$REPO_ROOT/tests/run_all.sh" > "$TMP/$_n.out" 2>&1 || RC=$?
}
cnt() { grep -cF -- "$2" "$1" 2>/dev/null; true; }
notty() { case "$1" in '??'|'?') echo 1 ;; *) echo 0 ;; esac; }
under() { case "$1" in "$2"*) echo 1 ;; *) echo 0 ;; esac; }
rows() { wc -l < "$1" | tr -d ' '; }
# ra_bg NAME JOBS — run_all in a session of its own, as a terminal gives it; pid in $_ra.
ra_bg() {
  env $HERMETIC RUN_ALL_SUITES_DIR="$SD" RUN_ALL_TABLE="$TMP/table" TEST_LOG_DIR="$TMP/log-$1" TEST_JOBS="$2" \
    perl -MPOSIX -e '$SIG{INT}="DEFAULT"; POSIX::setsid() or die; exec @ARGV' \
    ${TEST_SH:-sh} "$REPO_ROOT/tests/run_all.sh" > "$TMP/$1.out" 2>&1 &
  _ra=$!
}

test_run_all_green_parallel() {
  reset; fx ga 2; fx gb 3; fx gc 1
  ra gp TEST_JOBS=3
  assert_eq 0 "$RC" "a green set exits 0"
  for _s in ga gb gc; do
    assert_eq 1 "$(cnt "$TMP/gp.out" "=== ${_s}_test [p1of1] ")" "$_s header printed once"
  done
  assert_eq 1 "$(grep -A2 '^=== ga_test \[p1of1\]' "$TMP/gp.out" | grep -c '^2 assertions, 0 failed$')" "ga header is followed by its own summary line"
  assert_eq 1 "$(grep -A2 '^=== gb_test \[p1of1\]' "$TMP/gp.out" | grep -c '^3 assertions, 0 failed$')" "gb header is followed by its own summary line"
  assert_eq 1 "$(grep -A2 '^=== gc_test \[p1of1\]' "$TMP/gp.out" | grep -c '^1 assertions, 0 failed$')" "gc header is followed by its own summary line"
  assert_eq 3 "$(rows "$TMP/log-gp/summary.tsv")" "summary.tsv has 3 rows"
  assert_eq 3 "$(grep -c 'green$' "$TMP/log-gp/summary.tsv")" "all 3 rows are green"
}

test_run_all_red_suite_fails_gate() {
  reset; fx rs 1 'exit 1'
  ra rs
  assert_eq 1 "$RC" "a failing suite fails the gate"
  assert_eq 1 "$(cnt "$TMP/log-rs/summary.tsv" "red")" "its row is red"
}

test_run_all_missing_summary_line_is_red() {
  reset; fx ms 1 'exit 0'
  ra ms
  assert_eq 1 "$RC" "a suite with no summary line fails the gate"
  assert_eq 1 "$(cnt "$TMP/log-ms/summary.tsv" "red: no summary line")" "the verdict says no summary line"
}

test_run_all_no_l_row_is_red() {
  reset
  printf '\n1 assertions, 0 failed\n' > "$SD/nl_test.sh"
  ra nl
  assert_eq 1 "$RC" "a suite that wrote no run_tests row fails the gate"
  assert_eq 1 "$(cnt "$TMP/nl.out" "nl_test: no run_tests row")" "the check names the suite"
}

test_run_all_below_floor_is_red() {
  reset; fx bf 2; printf 'bf_test 1 5\n' > "$TMP/table"
  ra bf
  assert_eq 1 "$RC" "assertions below the floor fail the gate"
  assert_eq 1 "$(cnt "$TMP/bf.out" "bf_test: 2 assertions, below its floor 5")" "the check names the floor"
}

test_run_all_unran_test_is_red() {
  reset; FX_ROWS="1:0 2:0" fx un 3
  ra un
  assert_eq 1 "$RC" "a listed test that never ran fails the gate"
  assert_eq 1 "$(cnt "$TMP/un.out" "un_test: test 3 never ran")" "the check names test 3"
}

test_run_all_double_run_is_red() {
  reset; FX_ROWS="1:0 2:0 2:0" fx dr 2
  ra dr
  assert_eq 1 "$RC" "a test that ran twice fails the gate"
  assert_eq 1 "$(cnt "$TMP/dr.out" "dr_test: test 2 (t2) ran 2 times")" "the check names test 2 and the count"
}

test_run_all_respects_job_bound() {
  reset
  for _n in a b c d e f; do fx "s$_n" 1 "$SLOT"; done
  ra jb TEST_JOBS=2
  assert_eq 0 "$RC" "the slot fixtures are green"
  assert_eq 2 "$(cat "$TMP/slots.max" 2>/dev/null)" "never more than TEST_JOBS jobs live, and the pool fills"
}

test_run_all_exclusive_runs_alone_after_pool() {
  reset
  for _n in ex1 ex2; do
    cat > "$SD/${_n}_test.sh" <<XEOF
TESTS_EXCLUSIVE=t2
pt=all
case "\${TEST_PHASE:-}" in parallel) pt=p1of1 ;; exclusive) pt=x ;; esac
row() { [ -z "\${TEST_TIMING_LOG:-}" ] || printf '%s\n' "\$1" >> "\$TEST_TIMING_LOG"; }
now() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
row "\$(printf 'L\t%s\t%s\t2\t-' ${_n}_test "\$pt")"
if [ "\$pt" = x ]; then
  echo "x-start \$(now)" >> "$TMP/order"
  $SLOTX
  row "\$(printf 'T\t%s\tx\t2\tt2\t0\t1\t0' ${_n}_test)"
else
  $SLOT
  echo "p-end \$(now)" >> "$TMP/order"
  row "\$(printf 'T\t%s\t%s\t1\tt1\t0\t1\t0' ${_n}_test "\$pt")"
fi
printf '\n1 assertions, 0 failed\n'
XEOF
  done
  ra ex TEST_JOBS=3
  assert_eq 0 "$RC" "the exclusive run is green"
  assert_eq 2 "$(grep -c '^p-end ' "$TMP/order")" "both suites ran their parallel part"
  assert_eq 2 "$(grep -c '^x-start ' "$TMP/order")" "both suites ran their exclusive part"
  assert_eq ok "$(awk '$1 == "p-end" { if ($2 > p) p = $2 } $1 == "x-start" { if (x == "" || $2 < x) x = $2 } END { print (x > p) ? "ok" : "overlap " p " " x }' "$TMP/order")" "every exclusive part starts after every parallel part ended"
  assert_eq 1 "$(cat "$TMP/slotsx.max" 2>/dev/null)" "exclusive parts never overlap"
  assert_eq 4 "$(rows "$TMP/log-ex/summary.tsv")" "two parallel and two exclusive rows"
}

test_run_all_serial_mode_is_today() {
  reset
  for _n in c a b; do fx "$_n" 1 "echo $_n >> \"$TMP/order\"; echo \"\${TEST_PHASE-unset}\" >> \"$TMP/phase\""; done
  ra sm TEST_JOBS=1
  assert_eq 0 "$RC" "serial mode is green"
  assert_eq "a b c" "$(tr '\n' ' ' < "$TMP/order" | sed 's/ $//')" "suites run in name order"
  assert_eq "unset unset unset" "$(tr '\n' ' ' < "$TMP/phase" | sed 's/ $//')" "no suite sees a TEST_PHASE"
  assert_eq 1 "$(cnt "$TMP/sm.out" "=== a_test.sh ===")" "headers are today's"
  assert_eq 3 "$(rows "$TMP/log-sm/summary.tsv")" "one summary row per suite"
}

test_run_all_job_sees_trappable_int() {
  reset; fx ti 1 "trap 'echo y > \"$TMP/int.flag\"' INT; kill -INT \$\$; sleep 0.2"
  ra ti
  assert_eq 0 "$RC" "the job is green"
  assert_file "$TMP/int.flag" "the job's INT trap ran: INT is not ignored in a job"
}

test_run_all_job_has_own_session() {
  reset; fx os 1 "echo \"\$PPID \$(ps -o pgid=,tty= -p \$\$)\" > \"$TMP/sess\""
  ra os
  assert_eq 0 "$RC" "the job is green"
  set -- $(cat "$TMP/sess")
  _mine="$(ps -o pgid= -p $$ | tr -d ' ')"
  assert_eq "$1" "$2" "the job's parent leads its own process group"
  assert_eq 1 "$([ "$2" != "$_mine" ] && echo 1 || echo 0)" "that group is not the test's group"
  assert_eq 1 "$(notty "${3:-}")" "the job has no controlling terminal"
}

test_run_all_job_tmpdir_is_per_job() {
  reset; fx ta 1 "echo \"\$TMPDIR\" > \"$TMP/td-a\""; fx tb 1 "echo \"\$TMPDIR\" > \"$TMP/td-b\""
  ra td
  assert_eq 0 "$RC" "the jobs are green"
  _a="$(cat "$TMP/td-a")"; _b="$(cat "$TMP/td-b")"
  assert_eq 1 "$(under "$_a" "$TMP/log-td/")" "a's TMPDIR is under the log dir"
  assert_eq 1 "$(under "$_b" "$TMP/log-td/")" "b's TMPDIR is under the log dir"
  assert_eq 1 "$([ "$_a" != "$_b" ] && echo 1 || echo 0)" "the two differ"
}

test_run_all_ctrl_c_cleans_up() {
  reset
  _b='mkdir -p "$TMPDIR/bin"; ln -s "$(command -v sleep)" "$TMPDIR/bin/msleep"
( exec perl -e '"'"'$SIG{INT}=$SIG{QUIT}="DEFAULT"; setpgrp(0,0); exec @ARGV'"'"' "$TMPDIR/bin/msleep" 300 ) &
touch "'"$TMP"'/ready-$$"; sleep 300'
  fx cca 1 "$_b"; fx ccb 1 "$_b"
  printf 'cca_test 1 1\nccb_test 1 1\n' > "$TMP/table"
  # a neighbour: a process under another log dir whose path shares log-cc as a prefix
  mkdir -p "$TMP/log-cc2/bin"; ln -sf "$(command -v sleep)" "$TMP/log-cc2/bin/msleep"
  "$TMP/log-cc2/bin/msleep" 300 & _nb=$!
  ra_bg cc 2
  _i=0; while [ "$(ls "$TMP"/ready-* 2>/dev/null | wc -l)" -lt 2 ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
  kill -INT "$_ra"
  _i=0; while kill -0 "$_ra" 2>/dev/null && [ "$_i" -lt 150 ]; do sleep 0.1; _i=$((_i + 1)); done
  _rc=0; wait "$_ra" || _rc=$?
  assert_eq 130 "$_rc" "INT ends run_all with 130 within 15 s"
  assert_eq "" "$(pgrep -f "$TMP/log-cc/" 2>/dev/null)" "no job process, and no sleeper in a group of its own, survives"
  assert_contains "$TMP/cc.out" "interrupted" "the summary says interrupted"
  assert_eq 1 "$(kill -0 "$_nb" 2>/dev/null && echo 1 || echo 0)" "a process under a neighbouring log dir is untouched"
  kill "$_nb" 2>/dev/null; wait "$_nb" 2>/dev/null; true
}

test_run_all_serial_ctrl_c() {
  reset; mkdir -p "$TMP/bin"; ln -sf "$(command -v sleep)" "$TMP/bin/msleep-sc"
  fx sca 1 "echo \$\$ > \"$TMP/pid-a\"; touch \"$TMP/ready-a\"; \"$TMP/bin/msleep-sc\" 300"
  ra_bg sc 1
  _i=0; while [ ! -f "$TMP/ready-a" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
  # a terminal's Ctrl-C reaches the whole foreground group
  kill -INT "-$_ra"
  _i=0; while kill -0 "$_ra" 2>/dev/null && [ "$_i" -lt 150 ]; do sleep 0.1; _i=$((_i + 1)); done
  _rc=0; wait "$_ra" || _rc=$?
  assert_eq 130 "$_rc" "INT ends serial run_all with 130 within 15 s"
  assert_contains "$TMP/sc.out" "interrupted" "the summary says interrupted"
  _p="$(cat "$TMP/pid-a" 2>/dev/null)"
  # by argv, not pgrep -P: an orphan is reparented to pid 1, so -P of a dead suite is always empty
  assert_eq "" "$(pgrep -f "$TMP/bin/msleep-sc" 2>/dev/null)" "no sleep the suite started survives"
  assert_eq 1 "$(kill -0 "${_p:-0}" 2>/dev/null && echo 0 || echo 1)" "the suite itself is gone"
  pkill -KILL -f "$TMP/bin/msleep-sc" 2>/dev/null; true
}

test_run_all_job_timeout() {
  reset
  _b='mkdir -p "$TMPDIR/bin"; ln -s "$(command -v sleep)" "$TMPDIR/bin/msleep"; ( exec perl -e '"'"'setpgrp(0,0); exec @ARGV'"'"' "$TMPDIR/bin/msleep" 300 ) & sleep 30'
  fx to 1 "$_b"
  _t0=$(date +%s)
  ra to TEST_JOB_TIMEOUT=2 "TEST_LOG_DIR=$TMP/log t o"
  _el=$(( $(date +%s) - _t0 ))
  assert_eq 1 "$RC" "a timed-out job fails the gate"
  assert_eq 1 "$([ "$_el" -le 15 ] && echo 1 || echo 0)" "the timeout ends the run within 15 s (took $_el)"
  assert_eq 1 "$(cnt "$TMP/log t o/summary.tsv" "red: timed out after 2 s")" "the verdict names the timeout"
  assert_eq "" "$(pgrep -f "$TMP/log t o/" 2>/dev/null)" "nothing survives, not even a sleeper in a group of its own (log dir with spaces)"
}

# HANG: a fixture body that hangs 20 s in a sleeper tagged by its job dir.
HANG='mkdir -p "$TMPDIR/bin"; ln -sf "$(command -v sleep)" "$TMPDIR/bin/msleep"; "$TMPDIR/bin/msleep" 20'

test_run_all_reused_log_dir_keeps_timeout() {
  reset; fx rl 1
  ra rl
  assert_eq 0 "$RC" "the first run into the dir is green"
  fx rl 1 "$HANG"
  _t0=$(date +%s)
  ra rl TEST_JOB_TIMEOUT=2
  _el=$(( $(date +%s) - _t0 ))
  assert_eq 1 "$RC" "a hung job in a reused log dir still fails the gate"
  assert_eq 1 "$(cnt "$TMP/log-rl/summary.tsv" "red: timed out after 2 s")" "the previous run's rc does not end the job: it times out"
  assert_eq 1 "$([ "$_el" -le 15 ] && echo 1 || echo 0)" "within 15 s (took $_el)"
}

test_run_all_stale_rc_is_not_a_status() {
  reset; fx fr 1 'printf "0\nan-earlier-run\n" > "$TMPDIR/../rc"; '"$HANG"
  _t0=$(date +%s)
  ra fr TEST_JOB_TIMEOUT=2
  _el=$(( $(date +%s) - _t0 ))
  assert_eq 1 "$RC" "an rc from another run, written while the job runs, is not its status"
  assert_eq 1 "$(cnt "$TMP/log-fr/summary.tsv" "red: timed out after 2 s")" "the job still times out"
  assert_eq 1 "$([ "$_el" -le 15 ] && echo 1 || echo 0)" "within 15 s (took $_el)"
}

test_run_all_finished_job_leaves_nothing() {
  reset
  fx lk 1 'mkdir -p "$TMPDIR/bin"; ln -s "$(command -v sleep)" "$TMPDIR/bin/msleep"
( exec perl -e '"'"'setpgrp(0,0); exec @ARGV'"'"' "$TMPDIR/bin/msleep" 300 ) &
sleep 300 & echo $! > "'"$TMP"'/grp.pid"'
  cat > "$SD/lx_test.sh" <<XEOF
TESTS_EXCLUSIVE=t1
pt=p1of1; [ "\${TEST_PHASE:-}" = exclusive ] && pt=x
row() { [ -z "\${TEST_TIMING_LOG:-}" ] || printf '%s\n' "\$1" >> "\$TEST_TIMING_LOG"; }
row "\$(printf 'L\t%s\t%s\t1\t-' lx_test "\$pt")"
if [ "\$pt" = x ]; then
  { pgrep -f "$TMP/log-lk/lk_test.p1of1/"; kill -0 "\$(cat "$TMP/grp.pid")" 2>/dev/null && echo group-sleeper; } > "$TMP/during-x"
  row "\$(printf 'T\t%s\tx\t1\tt1\t0\t1\t0' lx_test)"
fi
printf '\n1 assertions, 0 failed\n'
XEOF
  ra lk
  assert_eq 0 "$RC" "leftovers are killed, not a red"
  assert_file "$TMP/during-x" "the exclusive job ran"
  assert_eq "" "$(cat "$TMP/during-x" 2>/dev/null)" "nothing a finished job left is running when the exclusive phase starts"
  assert_eq "" "$(pgrep -f "$TMP/log-lk/" 2>/dev/null)" "nothing from a job dir outlives run_all"
  assert_eq 1 "$(kill -0 "$(cat "$TMP/grp.pid" 2>/dev/null || echo 0)" 2>/dev/null && echo 0 || echo 1)" "the sleeper left in the job's own group is gone"
  assert_contains "$TMP/lk.out" "lk_test.p1of1 left processes running" "the job's block says it left processes"
  pkill -KILL -f "$TMP/log-lk/" 2>/dev/null; _gp="$(cat "$TMP/grp.pid" 2>/dev/null)"; case "$_gp" in ''|*[!0-9]*|0) ;; *) kill -KILL "$_gp" 2>/dev/null ;; esac; true
}

test_run_all_test_helpers_hermetic() {
  reset; fx he 1; printf 'he_test 1 5\n' > "$TMP/table"
  _r="$(export TEST_SUITES=nope TESTS_ONLY=nope TEST_JOB_TIMEOUT=x TEST_SLOWEST=x; ra he; echo "$RC")"
  assert_eq 1 "$_r" "ra ignores the caller's TEST_SUITES, TESTS_ONLY and knobs"
  assert_eq 1 "$(cnt "$TMP/he.out" "he_test: 1 assertions, below its floor 5")" "ra's run ran the suite checks"
  _r="$(export TEST_SUITES=nope TESTS_ONLY=nope TEST_JOB_TIMEOUT=x TEST_SLOWEST=x; ra_bg hb 2; _x=0; wait "$_ra" || _x=$?; echo "$_x")"
  assert_eq 1 "$_r" "ra_bg ignores them too"
  assert_eq 1 "$(cnt "$TMP/hb.out" "he_test: 1 assertions, below its floor 5")" "ra_bg's run ran the suite checks"
}

test_run_all_duplicate_table_row() {
  reset; fx du 1; printf 'du_test 1 1\ndu_test 1 1\n' > "$TMP/table"
  ra du
  assert_eq 2 "$RC" "a suite named twice in the table exits 2"
  assert_eq 1 "$(cnt "$TMP/du.out" "duplicate row for du_test")" "it names the suite"
}

test_run_all_bad_jobs_value() {
  reset; fx bj 1
  for _v in 0 x -1; do
    ra bj TEST_JOBS="$_v"
    assert_eq 2 "$RC" "TEST_JOBS='$_v' exits 2"
    assert_eq 1 "$(cnt "$TMP/bj.out" "TEST_JOBS must be a positive integer")" "TEST_JOBS='$_v' names the rule"
  done
  ra bj TEST_JOBS=
  assert_eq 0 "$RC" "an empty TEST_JOBS means the default"
}

test_run_all_unknown_suite() {
  reset; fx uk 1
  ra uk TEST_SUITES=nope
  assert_eq 2 "$RC" "an unknown suite exits 2"
  assert_eq 1 "$(cnt "$TMP/uk.out" "unknown suite: nope_test")" "it names the suite"
  printf 'ghost_test 1 1\n' > "$TMP/table"
  ra uk
  assert_eq 2 "$RC" "a table row for a missing file exits 2"
  assert_eq 1 "$(cnt "$TMP/uk.out" "table names a missing suite")" "it says so"
}

test_run_all_summary_and_slowest() {
  reset; FX_ROWS="1:3" fx sa 1; FX_ROWS="1:1" fx sb 1; FX_ROWS="1:2" fx sc 1
  ra sl TEST_SLOWEST=2
  assert_eq 0 "$RC" "the run is green"
  for _s in sa sb sc; do
    assert_eq 1 "$(grep -c "^${_s}_test  *p1of1 " "$TMP/sl.out")" "the summary has one row for ${_s}_test"
  done
  _lst="$(sed -n '/^slowest 2 tests:$/,$p' "$TMP/sl.out" | sed 1d)"
  assert_eq 2 "$(printf '%s\n' "$_lst" | wc -l | tr -d ' ')" "the slowest list has 2 lines"
  assert_eq "3 2" "$(printf '%s\n' "$_lst" | awk '{ printf "%s%s", (NR > 1 ? " " : ""), $1 }')" "sorted slowest first"
}

test_run_all_log_dir_with_space() {
  reset; fx la 1; fx lb 1
  ra ls "TEST_LOG_DIR=$TMP/log dir"
  assert_eq 0 "$RC" "a log dir with a space works"
  assert_eq 2 "$(rows "$TMP/log dir/summary.tsv")" "summary.tsv has 2 rows"
  assert_eq 1 "$([ -d "$TMP/log dir" ] && echo 1 || echo 0)" "the caller's dir is kept"
}

# exclusive-scan: test_run_all_respects_job_bound in (d) the slot fixtures each hold a slot for one second, and the exact peak of two needs the pool's jobs to overlap in that window
# exclusive-scan: test_run_all_job_sees_trappable_int out (b) the job signals itself and the trap fires at once; no window and no timing assertion
# exclusive-scan: test_run_all_ctrl_c_cleans_up in (a, c) INT must end run_all and sweep every job's processes inside a fixed ceiling, which a loaded machine can miss
# exclusive-scan: test_run_all_serial_ctrl_c in (a, c) INT must end serial run_all inside a fixed ceiling, which a loaded machine can miss
# exclusive-scan: test_run_all_job_timeout in (a, d) a two-second job timeout must end the run and sweep escaped processes inside a fixed ceiling
# exclusive-scan: test_run_all_reused_log_dir_keeps_timeout in (a, d) a two-second job timeout must still fire in a reused log dir, inside a fixed ceiling
# exclusive-scan: test_run_all_stale_rc_is_not_a_status in (a, d) a two-second job timeout must still fire past a stale rc file, inside a fixed ceiling
TESTS_EXCLUSIVE="test_run_all_respects_job_bound test_run_all_ctrl_c_cleans_up test_run_all_serial_ctrl_c test_run_all_job_timeout test_run_all_reused_log_dir_keeps_timeout test_run_all_stale_rc_is_not_a_status"
run_tests test_run_all_green_parallel test_run_all_red_suite_fails_gate \
  test_run_all_missing_summary_line_is_red test_run_all_no_l_row_is_red \
  test_run_all_below_floor_is_red test_run_all_unran_test_is_red test_run_all_double_run_is_red \
  test_run_all_respects_job_bound test_run_all_exclusive_runs_alone_after_pool \
  test_run_all_serial_mode_is_today test_run_all_job_sees_trappable_int \
  test_run_all_job_has_own_session test_run_all_job_tmpdir_is_per_job \
  test_run_all_ctrl_c_cleans_up test_run_all_serial_ctrl_c test_run_all_job_timeout \
  test_run_all_bad_jobs_value test_run_all_unknown_suite test_run_all_summary_and_slowest \
  test_run_all_log_dir_with_space test_run_all_reused_log_dir_keeps_timeout \
  test_run_all_stale_rc_is_not_a_status test_run_all_finished_job_leaves_nothing \
  test_run_all_test_helpers_hermetic test_run_all_duplicate_table_row
