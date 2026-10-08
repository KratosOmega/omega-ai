#!/bin/sh
# Tests for the harness itself (tests/assert.sh): partitions, timing rows, env scrub, helpers.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

mk_tmp harness_test
trap 'rm_tmp "$TMP"' EXIT

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

# gen_scan_fixture2 FILE — comments inside a test, and top-level lines after its closing brace.
gen_scan_fixture2() {
  sed 's/^|//' > "$1" <<'FIX'
|test_f() {
|  # exclusive-scan: test_f in (a) asserts elapsed under 5 s and sends kill -TERM
|    # sleep 2 inside --seconds 1 text
|  assert_eq 1 1 clean
|}
|# a top-level comment: kill -INT "$p" within 3 s
|kill -TERM "$q"
|run --seconds 1
|test_g() {
|  run --seconds 2 # trailing comment keeps the code flag
|}
FIX
}
test_exclusive_scan_ignores_comments_and_top_level() {
  gen_scan_fixture2 "$TMP/scan2_test.sh"
  assert_eq "test_g d " "$(awk -f "$REPO_ROOT/tests/exclusive_scan.awk" "$TMP/scan2_test.sh" | awk -F'\t' '{ printf "%s %s ", $2, $3 }')" \
    "comment lines and lines after a test's closing brace create no flag; code with a trailing comment still does"
}

# ---- static guards (spec R2.5, R5, R7). Each takes the tests dir as its parameter; the tests
# below pass ${GUARD_TESTS_DIR:-tests}. Every offender is printed as file:line.
GUARD_DIR() { printf '%s' "${GUARD_TESTS_DIR:-$REPO_ROOT/tests}"; }

# guard_unscoped_scans DIR — pgrep/pkill/ps -A lines (not comments) that name no $TMP, msleep,
# pid, group or session scope and carry no "# scan-ok:".
guard_unscoped_scans() {
  grep -nE '(^|[^a-z])(pgrep|pkill|ps -A)' "$1"/*_test.sh | awk -F: ' # scan-ok: the guard itself (an awk comment)
    { t = substr($0, length($1) + length($2) + 3)
      if (t ~ /^[ \t]*#/) next
      if (index(t, "$TMP") || index(t, "msleep") || index(t, "-P ") || index(t, "-p ") || index(t, "-g ") ||
          index(t, "\"-$") || index(t, "-- -") || index(t, "# scan-ok:")) next
      n = split($1, p, "/"); print p[n] ":" $2 }'
}

# guard_mktemp_templates DIR — mktemp command lines (not comments) without "${TMPDIR:-/tmp}/".
guard_mktemp_templates() {
  _gp='mktemp($|[)"`]| +[-"$/])'    # scan-ok: the guard's own pattern
  grep -nE "$_gp" "$1"/*_test.sh "$1"/state_fixtures.sh | awk -F: '
    { t = substr($0, length($1) + length($2) + 3)
      if (t ~ /^[ \t]*#/) next
      if (index(t, "${TMPDIR:-/tmp}/") || index(t, "# scan-ok:")) next
      n = split($1, p, "/"); print p[n] ":" $2 }'
}

test_no_unscoped_process_scans() {
  assert_eq "" "$(guard_unscoped_scans "$(GUARD_DIR)")" \
    "every pgrep/pkill/ps -A in a suite is scoped to \$TMP, a pid or a group (offenders: file:line)"
}

test_mktemp_uses_tmpdir_template() {
  assert_eq "" "$(guard_mktemp_templates "$(GUARD_DIR)")" \
    "every mktemp in a suite or state_fixtures.sh uses a \${TMPDIR:-/tmp}/ template (offenders: file:line)"
}

test_suite_tmp_under_tmpdir() {
  mkdir -p "$TMP/shadow" "$TMP/td"; : > "$TMP/mk.log"
  { printf '#!/bin/sh\n'
    printf 'out=$("%s" "$@") || exit $?\n' "$(command -v mktemp)"  # scan-ok: builds the shadow
    printf 'printf "%%s\\n" "$out" >> "%s"\n' "$TMP/mk.log"
    printf 'printf "%%s\\n" "$out"\n'
  } > "$TMP/shadow/mktemp"  # scan-ok: the shadow itself
  chmod +x "$TMP/shadow/mktemp"  # scan-ok: the shadow itself
  for _s in sync_test state_guard_test; do
    : > "$TMP/mk.log"
    ( cd "$REPO_ROOT" && env TEST_PHASE= TEST_SHARD= TEST_TIMING_LOG= TESTS_ONLY=__none__ TMPDIR="$TMP/td" \
        PATH="$TMP/shadow:$PATH" ${TEST_SH:-sh} "$REPO_ROOT/tests/$_s.sh" ) > "$TMP/$_s.out" 2>&1
    assert_eq 1 "$([ -s "$TMP/mk.log" ] && echo 1 || echo 0)" "$_s called mktemp through the shadow"
    assert_eq "" "$(grep -vF "$TMP/td/" "$TMP/mk.log" | sed "s|^|$_s: |")" "every mktemp result of $_s is under TMPDIR"
  done
}

# ---- fail closed on a temp dir that cannot be made: a bad TMP must never reach a cleanup rm
# (an unchecked `cd "$(mktemp …)"` gave TMP = the cwd, and the EXIT trap removed the checkout).

# test_suites_fail_closed_without_tmpdir — every suite in the tests dir, run from a sentinel cwd
# with TMPDIR naming a missing dir and TESTS_ONLY naming no test (so a broken guard can never
# start real work), under a 60 s alarm: it exits non-zero with mk_tmp's message, and its cwd,
# the sentinel and the missing TMPDIR are as they were (nothing made, nothing removed).
test_suites_fail_closed_without_tmpdir() {
  _fc="$TMP/failclosed"; _nx="$_fc/no-such-tmpdir"; _off=""; _msg=""; _n=0
  # a suite the static guard flags (or one sourcing a flagged state_fixtures.sh) is never run: its
  # top level could reach a raw TMP; it is an offender here and in test_suites_use_mk_tmp_and_rm_tmp
  _flg=" $(guard_raw_tmp_rm "$(GUARD_DIR)" | cut -d: -f1 | sort -u | tr '\n' ' ')"
  for _f in "$(GUARD_DIR)"/*_test.sh; do
    _s="$(basename "$_f" .sh)"; _cw="$_fc/$_s/cwd"; _n=$((_n + 1)); _rc=0
    case "$_flg" in *" $_s.sh "*) _off="$_off $_s:static-guard-flagged"; continue ;; esac
    case "$_flg" in *" state_fixtures.sh "*)
      if grep -q 'state_fixtures\.sh' "$_f"; then _off="$_off $_s:static-guard-flagged"; continue; fi ;; esac
    mkdir -p "$_cw" && : > "$_cw/sentinel"
    ( cd "$_cw" && exec env TEST_PHASE= TEST_SHARD= TEST_TIMING_LOG= TESTS_ONLY=__no_such_test__ TMPDIR="$_nx" \
        perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' 60 ${TEST_SH:-sh} "$_f" ) > "$_fc/$_s.out" 2>&1 || _rc=$?
    [ "$_rc" -ne 0 ] || _off="$_off $_s:exit-0"
    [ -d "$_cw" ] || _off="$_off $_s:cwd-removed"
    [ -f "$_cw/sentinel" ] || _off="$_off $_s:sentinel-removed"
    [ ! -d "$_cw" ] || [ "$(ls -A "$_cw")" = sentinel ] || _off="$_off $_s:cwd-littered"
    if [ -e "$_nx" ]; then _off="$_off $_s:tmpdir-made"; rm -rf "$_nx"; fi
    grep -qxF "$_s: cannot create temp dir under $_nx" "$_fc/$_s.out" || _msg="$_msg $_s"
  done
  assert_eq 1 "$([ "$_n" -gt 1 ] && echo 1 || echo 0)" "the fail-closed check found the suites ($_n)"
  assert_eq "" "$_off" "every suite exits non-zero on a missing TMPDIR and keeps its cwd and sentinel (offenders)"
  assert_eq "" "$_msg" "every suite names itself and the TMPDIR on stderr (suites without the message)"
}

# test_mk_tmp_rejects_bad_dirs — mk_tmp behind a shadow mktemp that "succeeds" with an empty
# line, ".", the cwd's path, a plain file or an existing dir outside TMPDIR: each exits 1 with
# the message, sets no TMP, and the sentinel cwd is untouched; a real mktemp gives a resolved dir
# under TMPDIR.
test_mk_tmp_rejects_bad_dirs() {
  _mk="$TMP/mkbad"; mkdir -p "$_mk/bin" "$_mk/cwd" "$_mk/td" "$_mk/elsewhere/mkbad.x"
  : > "$_mk/cwd/sentinel"; : > "$_mk/file"
  _res=""
  for _case in empty dot cwd file outside; do
    case "$_case" in
      empty) _out='' ;; dot) _out='.' ;; cwd) _out="$_mk/cwd" ;; file) _out="$_mk/file" ;;
      outside) _out="$_mk/elsewhere/mkbad.x" ;;
    esac
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$_out" > "$_mk/bin/mktemp"  # scan-ok: a shadow that lies
    chmod +x "$_mk/bin/mktemp"  # scan-ok: the shadow
    _rc=0
    ( cd "$_mk/cwd" && PATH="$_mk/bin:$PATH" TMPDIR="$_mk/td" ${TEST_SH:-sh} -c \
        '. "$1/tests/assert.sh"; mk_tmp mkbad; echo "made $TMP"' mkbad_test "$REPO_ROOT" ) > "$_mk/$_case.out" 2>&1 || _rc=$?
    _res="$_res $_case:$_rc:$(grep -c '^made ' "$_mk/$_case.out"):$(grep -cxF "mkbad_test: cannot create temp dir under $_mk/td" "$_mk/$_case.out")"
  done
  assert_eq " empty:1:0:1 dot:1:0:1 cwd:1:0:1 file:1:0:1 outside:1:0:1" "$_res" "mk_tmp exits 1 with the message on each bad dir (case:rc:made:message)"
  assert_eq "sentinel" "$(ls -A "$_mk/cwd")" "the cwd is untouched"
  _got="$(cd "$_mk/cwd" && TMPDIR="$_mk/td" ${TEST_SH:-sh} -c '. "$1/tests/assert.sh"; mk_tmp good; echo "$TMP"' sh "$REPO_ROOT")"
  case "$_got" in "$(cd "$_mk/td" && pwd -P)"/good.*) _ok=1 ;; *) _ok=0 ;; esac
  assert_eq 1 "$_ok" "a good mk_tmp gives a resolved dir under TMPDIR ($_got)"
}

# test_rm_tmp_refuses_cwd_and_ancestors — rm_tmp removes a temp dir, but refuses an empty name,
# ".", the cwd, an ancestor of the cwd and an ancestor of the dir the suite started in.
test_rm_tmp_refuses_cwd_and_ancestors() {
  _rt="$TMP/rmtmp"; mkdir -p "$_rt/a/b" "$_rt/sib" "$_rt/s/c"; : > "$_rt/a/b/keep"; : > "$_rt/s/c/keep"
  _res="$(cd "$_rt/a/b" && for _d in "" . "$_rt/a/b" "$_rt/a" "$_rt/sib" "$_rt/never"; do
      _rc=0; rm_tmp "$_d" 2>/dev/null || _rc=$?; printf '%s ' "$_rc"; done)"
  assert_eq "1 1 1 1 0 0 " "$_res" "rm_tmp: empty, ., cwd, ancestor refused; a temp dir and a missing one fine"
  assert_file "$_rt/a/b/keep" "the cwd and its ancestors survive"
  assert_missing "$_rt/sib" "rm_tmp removed the temp dir"
  _rc=0
  ( cd "$_rt/s/c" && ${TEST_SH:-sh} -c '. "$1/tests/assert.sh"; cd /; rm_tmp "$2"' sh "$REPO_ROOT" "$_rt/s" ) 2>/dev/null || _rc=$?
  assert_eq "1" "$_rc" "rm_tmp refuses an ancestor of the start dir after a cd away"
  assert_file "$_rt/s/c/keep" "the start dir survives"
  # other spellings of / and of an ancestor (checked with the private test, so nothing is removed)
  _up="$(printf '%s' "$_rt/a" | tr '[:lower:]' '[:upper:]')"
  _res="$(cd "$_rt/a/b" && for _d in // "/$_rt/a" "$_up" "$_rt/a/b/"; do
      if __rt_tmp_ok "$_d"; then printf 'ok '; else printf 'no '; fi; done)"
  assert_eq "no no no no " "$_res" "//, a //-spelled ancestor, a case variant and a cwd/ spelling are refused"
}

# test_rm_tmp_cleans_after_cd_into_tmp — a suite whose test cd's into its own TMP (the test
# functions run in the main shell) still has TMP removed by the EXIT trap: rm_tmp steps out of
# the dir mk_tmp made instead of refusing it as the cwd and leaking it.
test_rm_tmp_cleans_after_cd_into_tmp() {
  _lk="$TMP/cdin"; mkdir -p "$_lk/cwd" "$_lk/td"
  { printf '. "%s/tests/assert.sh"\n' "$REPO_ROOT"
    printf 'mk_tmp fx_test; trap '"'"'rm_tmp "$TMP"'"'"' EXIT\n'
    printf 't1() { mkdir "$TMP/x" && cd "$TMP/x" && assert_eq 1 1 t1; }\n'
    printf 'run_tests t1\n'
  } > "$_lk/fx_test.sh"
  _rc=0
  ( cd "$_lk/cwd" && env TEST_PHASE= TEST_SHARD= TEST_TIMING_LOG= TESTS_ONLY= TMPDIR="$_lk/td" \
      ${TEST_SH:-sh} "$_lk/fx_test.sh" ) > "$_lk/fx.out" 2>&1 || _rc=$?
  assert_eq "0" "$_rc" "the fixture suite passes"
  assert_eq "" "$(ls -A "$_lk/td")" "the suite's TMPDIR is left empty after it cd'd into TMP"
  assert_eq "0" "$(grep -c 'rm_tmp: refusing' "$_lk/fx.out")" "rm_tmp refused nothing"
}

# guard_raw_tmp_rm DIR — lines (not comments) that rm $TMP itself (any flags, `--`, a trailing
# slash) or assign TMP from a raw mktemp: every suite makes TMP with mk_tmp and removes it with rm_tmp.
guard_raw_tmp_rm() {
  _gp='(^|[^A-Za-z0-9_])rm( +-[A-Za-z]+)*( +--)? +"?\$\{?TMP\}?"?/?"?([^/A-Za-z0-9_"]|$)'  # scan-ok: the guard's own pattern
  _gp="$_gp"'|TMP="?\$\((cd )?"?\$\(mktemp|TMP="?\$\(mktemp'  # scan-ok: the guard's own pattern
  grep -nE "$_gp" "$1"/*_test.sh "$1"/state_fixtures.sh | awk -F: '
    { t = substr($0, length($1) + length($2) + 3)
      if (t ~ /^[ \t]*#/ || index(t, "# scan-ok:")) next
      n = split($1, p, "/"); print p[n] ":" $2 }'
}

test_suites_use_mk_tmp_and_rm_tmp() {
  assert_eq "" "$(guard_raw_tmp_rm "$(GUARD_DIR)")" \
    "no suite assigns TMP from a raw mktemp or rm -rf's \$TMP itself (offenders: file:line)"
  # the guard itself: each spelling of a raw removal of TMP is flagged; a path under TMP is not
  _gr="$TMP/rawrm"; mkdir -p "$_gr"; : > "$_gr/state_fixtures.sh"
  printf '%s\n' 'rm -rf "$TMP"' 'rm -rf "$TMP/"' 'rm -rf -- "$TMP"' 'rm -fr "$TMP"' 'rm -r -f ${TMP}' > "$_gr/x_test.sh"  # scan-ok: guard fixture
  printf '%s\n' "trap 'rm -rf \"\$TMP\"' EXIT" 'rm -rf "$TMP/x"' 'rm -rf "$TMP"/x' 'rm_tmp "$TMP"' 'rm -rf "$TMPX"' >> "$_gr/x_test.sh"
  assert_eq "1 2 3 4 5 6 " "$(guard_raw_tmp_rm "$_gr" | sed 's/^x_test.sh://' | tr '\n' ' ')" \
    "the guard flags rm -rf, a trailing slash, --, -fr, -r -f and a trap; not a path under TMP or rm_tmp"
}

# guard_exclusive_rulings DIR — the five ruling checks over every suite in DIR.
guard_exclusive_rulings() {
  for _f in "$1"/*_test.sh; do
    _b="$(basename "$_f")"
    # one tagged stream in $TMP/gr.all: S flagged test, R ruling, E TESTS_EXCLUSIVE member, L run_tests word
    awk -f "$REPO_ROOT/tests/exclusive_scan.awk" "$_f" | awk -F'\t' '{ print "S\t" $2 "\t" $4 }' > "$TMP/gr.all"
    grep -nE '^# exclusive-scan: [^ ]+ (in|out) ' "$_f" | awk -F: -v b="$_b" '{ split(substr($0, length($1) + 2), w, " "); print "R\t" w[3] "\t" w[4] "\t" b ":" $1 }' >> "$TMP/gr.all"
    # the last ^TESTS_EXCLUSIVE= line, with its backslash continuations (earlier ones sit in fixtures)
    awk '/^TESTS_EXCLUSIVE=/ { s = $0; while (s ~ /\\$/ && (getline nx) > 0) s = s "\n" nx; last = s } END { if (last != "") print last }' "$_f" > "$TMP/gr.excl.sh"
    ( TESTS_EXCLUSIVE=""; eval "$(cat "$TMP/gr.excl.sh")"; for _w in $TESTS_EXCLUSIVE; do printf 'E\t%s\n' "$_w"; done ) >> "$TMP/gr.all"
    # the words of the last run_tests call (continuation lines included)
    awk '/^run_tests/ { s = ""; seen = 1 } seen { gsub(/\\/, " "); s = s " " $0 } END { n = split(s, w, " "); for (i = 1; i <= n; i++) print "L\t" w[i] }' "$_f" >> "$TMP/gr.all"
    awk -F'\t' -v b="$_b" '
      $1 == "S" { fl[$2] = $3 }
      $1 == "R" { rv[$2] = $3; rl[$2] = $4 }
      $1 == "E" { ex[$2] = 1 }
      $1 == "L" { li[$2] = 1 }
      END {
        for (t in fl) if (!(t in rv)) print b ": flagged test " t " has no ruling (" fl[t] ")"
        for (t in rv) {
          if (!(t in li)) print rl[t] ": ruling for " t ", which run_tests does not list"
          if (rv[t] ~ /^in/ && !(t in ex)) print rl[t] ": " t " is ruled in but missing from TESTS_EXCLUSIVE"
          if (rv[t] ~ /^out/ && (t in ex)) print rl[t] ": " t " is ruled out but listed in TESTS_EXCLUSIVE"
        }
        for (t in ex) if (!(t in rv) || rv[t] !~ /^in/) print b ": " t " is in TESTS_EXCLUSIVE with no in ruling"
      }' "$TMP/gr.all"
  done | sort
}

test_exclusive_scan_candidates_ruled() {
  assert_eq "" "$(guard_exclusive_rulings "$(GUARD_DIR)")" \
    "every scan-flagged test has an in/out ruling that matches TESTS_EXCLUSIVE (offenders: file:line)"
}

# guard_knobs_named DIR — the header/help/suite checks of spec R7.
guard_knobs_named() {
  _bin="$REPO_ROOT/studios/game-dev/bin"
  _need() { # LABEL TEXT NAME…
    _lb="$1"; _tx="$2"; shift 2
    for _k in "$@"; do case "$_tx" in *"$_k"*) ;; *) printf '%s: %s is not named\n' "$_lb" "$_k" ;; esac; done
  }
  _need "studio-setup header" "$(sed -n '1,40p' "$_bin/studio-setup")" STUDIO_SETUP_POLL_SECONDS
  _need "studio-gate header" "$(sed -n '1,30p' "$_bin/studio-gate")" STUDIO_GATE_POLL_SECONDS STUDIO_GATE_SECONDS
  _need "studio-overnight --help" "$(sh "$_bin/studio-overnight" --help 2>&1)" \
    STUDIO_OVERNIGHT_REAP_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_POLL_SECONDS \
    STUDIO_OVERNIGHT_IDLE_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS
  _need "overnight-lanes.sh" "$(cat "$_bin/overnight-lanes.sh")" STUDIO_OVERNIGHT_REAP_POLL_SECONDS
  _need "assert.sh header" "$(sed -n '1,30p' "$REPO_ROOT/tests/assert.sh")" TEST_PHASE TEST_SHARD TEST_TIMING_LOG
  _need "run_all.sh header" "$(sed -n '1,30p' "$REPO_ROOT/tests/run_all.sh")" TEST_JOBS TEST_SUITES TEST_LOG_DIR \
    TEST_SLOWEST TEST_JOB_TIMEOUT TEST_SH RUN_ALL_SUITES_DIR RUN_ALL_TABLE
  _need "overnight_lanes_test.sh" "$(cat "$1/overnight_lanes_test.sh")" LANES_FIXTURE_TEMPLATES
  _need "overnight_test.sh" "$(cat "$1/overnight_test.sh")" OVERNIGHT_FIXTURE_TEMPLATES
}

test_knobs_named_in_headers() {
  assert_eq "" "$(guard_knobs_named "$(GUARD_DIR)")" "every R7 and harness knob is named where its users look"
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
  test_exclusive_scan_flags_fixture test_exclusive_scan_ignores_comments_and_top_level \
  test_no_unscoped_process_scans test_mktemp_uses_tmpdir_template test_suite_tmp_under_tmpdir \
  test_suites_fail_closed_without_tmpdir test_mk_tmp_rejects_bad_dirs test_rm_tmp_refuses_cwd_and_ancestors \
  test_rm_tmp_cleans_after_cd_into_tmp test_suites_use_mk_tmp_and_rm_tmp \
  test_exclusive_scan_candidates_ruled test_knobs_named_in_headers
