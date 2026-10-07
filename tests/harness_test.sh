#!/bin/sh
# Tests for the harness itself (tests/assert.sh): partitions, timing rows, env scrub, helpers.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/harness_test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# gen_suite FILE — 23 tests t01..t23 (one passing assertion each); t05 t12 t19
# exclusive; t08 final. EXTRA (optional 2nd arg) is shell text placed before run_tests.
gen_suite() {
  { printf '. "%s/tests/assert.sh"\n' "$REPO_ROOT"
    _g=1; while [ "$_g" -le 23 ]; do
      printf 't%02d() { assert_eq 1 1 t%02d; }\n' "$_g" "$_g"; _g=$((_g + 1)); done
    printf 'TESTS_EXCLUSIVE="t05 t12 t19"\nTESTS_FINAL="t08"\n%s\nrun_tests' "${2:-}"
    _g=1; while [ "$_g" -le 23 ]; do printf ' t%02d' "$_g"; _g=$((_g + 1)); done; printf '\n'
  } > "$1"
}
# child PHASE SHARD LOG FILE [ONLY] — FILE under ${TEST_SH:-sh} with exactly these harness
# variables (an outer run_all job's own TEST_* never leak in); stdout+stderr to FILE.out.
child() {
  ( cd "$TMP" && TESTS_ONLY="${5:-}" TEST_PHASE="$1" TEST_SHARD="$2" TEST_TIMING_LOG="$3" \
      ${TEST_SH:-sh} "$4" ) > "$4.out" 2>&1
}
# idxs LOG — the T rows' idx column, space separated, in file order.
idxs() { awk -F'\t' '$1 == "T" { printf "%s%s", (n++ ? " " : ""), $4 }' "$1"; }
# nonzero RC — "1" when RC is not 0.
nonzero() { if [ "$1" -ne 0 ]; then echo 1; else echo 0; fi; }

test_shards_cover_every_test_once() {
  gen_suite "$TMP/cov_test.sh"
  for _n in 1 2 3 7 19; do
    _log="$TMP/cov-$_n.tsv"; : > "$_log"; _k=1
    while [ "$_k" -le "$_n" ]; do child parallel "$_k/$_n" "$_log" "$TMP/cov_test.sh"; _k=$((_k + 1)); done
    child exclusive "" "$_log" "$TMP/cov_test.sh"
    _bad="$(awk -F'\t' -v p=$((_n + 1)) '$1 == "T" { c[$4]++ }
      END { for (i = 1; i <= 23; i++) { w = (i == 8) ? p : 1; if (c[i] + 0 != w) printf "%d:%d ", i, c[i] } }' "$_log")"
    assert_eq "" "$_bad" "N=$_n: each test once, the final (idx 8) once per partition"
    assert_eq "$((_n + 1))" "$(grep -c '^L	' "$_log")" "N=$_n: one L row per partition"
    _lastok="$(awk -F'\t' '$1 == "T" { last[$3] = $4 } END { for (p in last) if (last[p] != 8) print p }' "$_log")"
    assert_eq "" "$_lastok" "N=$_n: the final runs last in every partition"
  done
}

test_no_phase_runs_all_in_order() {
  gen_suite "$TMP/all_test.sh"; _log="$TMP/all.tsv"; : > "$_log"
  child "" "" "$_log" "$TMP/all_test.sh"
  _want=""; _g=1; while [ "$_g" -le 23 ]; do _want="$_want${_want:+ }$_g"; _g=$((_g + 1)); done
  assert_eq "$_want" "$(idxs "$_log")" "no phase: idx 1..23 in listed order (t08 at 8)"
  assert_eq "$(printf 'L\tall_test\tall\t23\t8')" "$(grep '^L	' "$_log")" "no phase: the L row"
}

test_exclusive_phase_runs_only_tagged() {
  gen_suite "$TMP/ex_test.sh"; _log="$TMP/ex.tsv"; : > "$_log"
  child exclusive "" "$_log" "$TMP/ex_test.sh"
  assert_eq "5 12 19 8" "$(idxs "$_log")" "exclusive phase: the tagged tests, then the final"
}

test_bad_shard_and_phase_fail_loudly() {
  gen_suite "$TMP/bad_test.sh"
  for _s in 0/3 4/3 x 3 1/2/3 08/9 1/0; do
    _log="$TMP/bad.tsv"; : > "$_log"; _rc=0
    child parallel "$_s" "$_log" "$TMP/bad_test.sh" || _rc=$?
    assert_eq 1 "$(nonzero "$_rc")" "shard '$_s': exit status is not 0"
    assert_contains "$TMP/bad_test.sh.out" "FAIL bad TEST_SHARD" "shard '$_s': named in the output"
    assert_eq "bad" "$(awk -F'\t' '$1 == "L" { print $3 }' "$_log")" "shard '$_s': the L row's part is bad"
    assert_eq "" "$(idxs "$_log")" "shard '$_s': no test ran"
  done
  _log="$TMP/bad.tsv"; : > "$_log"; _rc=0
  child "" "1/2" "$_log" "$TMP/bad_test.sh" || _rc=$?
  assert_eq 1 "$(nonzero "$_rc")" "a shard without a phase: exit status is not 0"
  assert_contains "$TMP/bad_test.sh.out" "FAIL TEST_SHARD needs TEST_PHASE=parallel" "a shard without a phase: named"
  assert_eq "bad" "$(awk -F'\t' '$1 == "L" { print $3 }' "$_log")" "a shard without a phase: the L row's part is bad"
  assert_eq "" "$(idxs "$_log")" "a shard without a phase: no test ran"
  _log="$TMP/bad.tsv"; : > "$_log"; _rc=0
  child serial "" "$_log" "$TMP/bad_test.sh" || _rc=$?
  assert_eq 1 "$(nonzero "$_rc")" "phase serial: exit status is not 0"
  assert_contains "$TMP/bad_test.sh.out" "FAIL bad TEST_PHASE" "phase serial: named"
  assert_eq "bad" "$(awk -F'\t' '$1 == "L" { print $3 }' "$_log")" "phase serial: the L row's part is bad"
  assert_eq "" "$(idxs "$_log")" "phase serial: no test ran"
}

test_misspelt_tag_fails_in_every_phase() {
  gen_suite "$TMP/tag_test.sh" 'TESTS_REAL_CLOCK="t99"'
  for _ph in "" "parallel 1/1" "exclusive"; do
    _rc=0; _p="${_ph%% *}"; _sh=""; [ "$_p" = "$_ph" ] || _sh="${_ph#* }"
    child "$_p" "$_sh" "" "$TMP/tag_test.sh" || _rc=$?
    assert_eq 1 "$(nonzero "$_rc")" "phase '$_ph': exit status is not 0"
    assert_contains "$TMP/tag_test.sh.out" "FAIL TESTS_REAL_CLOCK names unknown test t99" "phase '$_ph': the tag is named"
  done
  gen_suite "$TMP/tag2_test.sh" 'TESTS_FINAL="t05"'
  _rc=0; child "" "" "" "$TMP/tag2_test.sh" || _rc=$?
  assert_eq 1 "$(nonzero "$_rc")" "exclusive and final: exit status is not 0"
  assert_contains "$TMP/tag2_test.sh.out" "FAIL t05 is both exclusive and final" "exclusive and final: named"
}

test_tests_only_intersects_partition() {
  gen_suite "$TMP/only_test.sh"; _log="$TMP/only.tsv"; : > "$_log"
  child parallel 1/2 "$_log" "$TMP/only_test.sh" "t01 t02 t05 t08"
  assert_eq "1 8" "$(idxs "$_log")" "TESTS_ONLY keeps only the partition's share (t02 is shard 2, t05 exclusive)"
}

test_before_each_sees_test_name() {
  rm -f "$TMP/be.log"
  gen_suite "$TMP/be_test.sh" 'before_each() { echo "$TEST_NAME" >> "'"$TMP"'/be.log"; }'
  child "" "" "" "$TMP/be_test.sh"
  _want="$(_g=1; while [ "$_g" -le 23 ]; do printf 't%02d\n' "$_g"; _g=$((_g + 1)); done)"
  assert_eq "$_want" "$(cat "$TMP/be.log")" "before_each saw each test's name, in run order"
}

test_real_clock_includes_exclusive() {
  rm -f "$TMP/rc.log"
  gen_suite "$TMP/rc_test.sh" 'TESTS_REAL_CLOCK=t01
before_each() { echo "$TEST_NAME $(is_real_clock && echo rc || echo fast)" >> "'"$TMP"'/rc.log"; }'
  child "" "" "" "$TMP/rc_test.sh"
  assert_contains "$TMP/rc.log" "^t01 rc$" "a TESTS_REAL_CLOCK test is real-clock"
  assert_contains "$TMP/rc.log" "^t05 rc$" "an exclusive test is real-clock"
  assert_contains "$TMP/rc.log" "^t02 fast$" "any other test is not"
}

test_partition_named_in_output() {
  gen_suite "$TMP/pn_test.sh"
  child parallel 2/3 "" "$TMP/pn_test.sh"
  assert_eq "partition p2of3" "$(head -n 1 "$TMP/pn_test.sh.out")" "a phase names its partition first"
  child "" "" "" "$TMP/pn_test.sh"
  assert_not_contains "$TMP/pn_test.sh.out" "^partition" "no phase prints no partition line"
}

test_timing_log_rows() {
  gen_suite "$TMP/tr_test.sh"; _log="$TMP/tr.tsv"; : > "$_log"
  child "" "" "$_log" "$TMP/tr_test.sh"
  assert_eq 23 "$(awk -F'\t' '$1 == "T" && $7 == 1 && $8 == 0' "$_log" | wc -l | tr -d ' ')" \
    "23 T rows, each with 1 assertion and 0 failed"
  assert_eq 23 "$(awk -F'\t' '$1 == "T" && $2 == "tr_test" && $3 == "all" && $5 == sprintf("t%02d", $4)' "$_log" | wc -l | tr -d ' ')" \
    "each T row names suite, part, idx and test"
  gen_suite "$TMP/tf_test.sh" 't03() { assert_eq 1 2 t03; }'; _log="$TMP/tf.tsv"; : > "$_log"
  child "" "" "$_log" "$TMP/tf_test.sh" || true
  assert_eq "1 1" "$(awk -F'\t' '$1 == "T" && $4 == 3 { print $7, $8 }' "$_log")" "a failing assertion shows as 1 1 on idx 3"
}

test_timing_log_off_by_default() {
  gen_suite "$TMP/off_test.sh"
  _before="$(ls "$TMP")"
  child "" "" "" "$TMP/off_test.sh"
  assert_eq "$_before" "$(ls "$TMP" | grep -v '^off_test.sh.out$')" "TEST_TIMING_LOG empty: no file is written"
}

test_timing_log_l_row_for_empty_partition() {
  gen_suite "$TMP/em_test.sh" 'TESTS_EXCLUSIVE=""; TESTS_FINAL=""'; _log="$TMP/em.tsv"; : > "$_log"
  child exclusive "" "$_log" "$TMP/em_test.sh"
  assert_eq 1 "$(grep -c '^L	' "$_log")" "an empty partition writes one L row"
  assert_eq 0 "$(grep -c '^T	' "$_log")" "an empty partition writes no T row"
}

test_env_scrub() {
  _out="$(env STUDIO_STORY=s STUDIO_RUN_DIR=r OMEGA_AUTOPILOT=1 CLAUDE_CODE_SESSION_ID=c CLAUDE_CONFIG_DIR=d \
    CLAUDECODE=1 GIT_DIR=g TESTS_ONLY=t TEST_SHARD=1/2 ${TEST_SH:-sh} -c '. "$1/tests/assert.sh"; env' sh "$REPO_ROOT" \
    | grep -E '^(STUDIO_STORY|STUDIO_RUN_DIR|OMEGA_AUTOPILOT|CLAUDE_CODE_SESSION_ID|CLAUDE_CONFIG_DIR|CLAUDECODE|GIT_DIR|TESTS_ONLY|TEST_SHARD)=' \
    | sed 's/=.*//' | sort | tr '\n' ' ')"
  assert_eq "TESTS_ONLY TEST_SHARD " "$_out" "sourcing scrubs context variables and keeps TESTS_ONLY and TEST_*"
}

# og_start FLAG — an own_group sh in the background that traps INT (writes FLAG, exit 7)
# and touches FLAG.ready once the trap is set; its pid is OG_PID.
og_start() {
  ( own_group ${TEST_SH:-sh} -c 'trap ": > \"\$1\"; exit 7" INT; : > "$1.ready"; while :; do sleep 0.1; done' sh "$1" ) &
  OG_PID=$!
}
test_own_group_gives_group_and_int() {
  og_start "$TMP/og.flag"; _p=$OG_PID; _i=0
  while [ "$_i" -lt 50 ]; do
    [ "$(ps -o pgid= -p "$_p" 2>/dev/null | tr -d ' ')" = "$_p" ] && [ -e "$TMP/og.flag.ready" ] && break
    sleep 0.1; _i=$((_i + 1))
  done
  assert_eq "$_p" "$(ps -o pgid= -p "$_p" 2>/dev/null | tr -d ' ')" "own_group puts the command in a group of its own"
  kill -INT "$_p"; _rc=0; wait "$_p" || _rc=$?
  assert_eq 7 "$_rc" "SIGINT reaches the command at its default disposition (trap ran, exit 7)"
  assert_file "$TMP/og.flag" "the INT trap ran"
}

test_mk_msleep() {
  _rc=0; mk_msleep || _rc=$?
  assert_eq 0 "$_rc" "mk_msleep succeeds"
  "$TMP/bin/msleep" 3 &
  _p=$!; _found=""; _i=0
  while [ "$_i" -lt 20 ] && [ -z "$_found" ]; do
    _found="$(pgrep -f "$TMP/bin/msleep 3\$" | head -n 1)"
    [ -n "$_found" ] || sleep 0.1
    _i=$((_i + 1))
  done
  assert_eq "$_p" "$_found" "pgrep -f finds msleep by its \$TMP path"
  kill "$_p" 2>/dev/null; wait "$_p" 2>/dev/null || true
  mkdir -p "$TMP/fakebin"
  printf '#!/bin/sh\ncase "${0##*/}" in sleep) exec /bin/sleep "$@";; *) exit 1;; esac\n' > "$TMP/fakebin/sleep"
  chmod +x "$TMP/fakebin/sleep"
  _rc=0; ( PATH="$TMP/fakebin:$PATH"; TMP="$TMP/m2"; mk_msleep ) || _rc=$?
  assert_eq 0 "$_rc" "the fallback mk_msleep succeeds"
  assert_eq "#!" "$(head -c 2 "$TMP/m2/bin/msleep")" "where sleep dispatches on argv[0], msleep is a script"
  assert_status 0 "the fallback msleep runs" -- "$TMP/m2/bin/msleep" 0
}

test_next_second() {
  _s0=$(date +%s)
  _t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  next_second
  _t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  _s1=$(date +%s)
  assert_eq 1 "$(if [ "$_s1" -gt "$_s0" ]; then echo 1; else echo 0; fi)" "date +%s has moved past the starting second"
  assert_eq 1 "$(awk -v a="$_t0" -v b="$_t1" 'BEGIN { print (b - a < 1.5) ? 1 : 0 }')" "next_second returns within 1.5 s"
}

test_harness_private_names_unused() {
  assert_eq "" "$(cd "$REPO_ROOT" && grep -l '__rt_' tests/*_test.sh tests/state_fixtures.sh | grep -v harness_test.sh)" \
    "no suite uses the harness's __rt_ prefix"
}

# gen_scan_fixture FILE — five test functions for the exclusive scan. Each heredoc line
# carries a "|" prefix (stripped on write) so the line-based scan never sees a column-0
# test_ header in this file.
gen_scan_fixture() {
  sed 's/^|//' > "$1" <<'FIX'
|test_a() {
|  [ $(( $(date +%s) - _t )) -le 5 ]
|}
|test_b() {
|  kill -INT "$p"
|}
|test_c() {
|  printf 'sleep 2\n' > "$SCEN/A"
|}
|test_d() {
|  run --seconds 1
|}
|test_e() {
|  assert_eq 1 1 clean
|}
FIX
}
test_exclusive_scan_flags_fixture() {
  gen_scan_fixture "$TMP/scan_test.sh"
  assert_eq "a b d d " "$(awk -f "$REPO_ROOT/tests/exclusive_scan.awk" "$TMP/scan_test.sh" | awk -F'\t' '{ printf "%s ", $3 }')" \
    "the scan flags a, b, d, d and leaves the clean test alone"
  assert_eq "" "$(awk -f "$REPO_ROOT/tests/exclusive_scan.awk" "$REPO_ROOT/tests/harness_test.sh" | awk -F'\t' '$2 ~ /^test_[a-e]$/ { print $2 }')" \
    "the scan reports no fixture rows (test_a..test_e) for harness_test.sh itself"
}

# exclusive-scan: test_next_second in (a) asserts elapsed < 1.5 s
# exclusive-scan: test_own_group_gives_group_and_int out (b) the SIGINT goes to a private sh the test started in its own group, never to the harness's group, and nothing else's timing is at stake
TESTS_EXCLUSIVE="test_next_second"
run_tests test_shards_cover_every_test_once test_no_phase_runs_all_in_order \
  test_exclusive_phase_runs_only_tagged test_bad_shard_and_phase_fail_loudly \
  test_misspelt_tag_fails_in_every_phase test_tests_only_intersects_partition \
  test_before_each_sees_test_name test_real_clock_includes_exclusive \
  test_partition_named_in_output test_timing_log_rows test_timing_log_off_by_default \
  test_timing_log_l_row_for_empty_partition test_env_scrub test_own_group_gives_group_and_int \
  test_mk_msleep test_next_second test_harness_private_names_unused \
  test_exclusive_scan_flags_fixture
