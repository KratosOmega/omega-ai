#!/bin/sh
# run_all.sh — the merge gate: every tests/*_test.sh suite.
#
# Parallel (default): each suite, or each shard of a sharded suite, is one job in a pool of
# at most TEST_JOBS, in a session and process group of its own (POSIX::setsid), with its own
# TMPDIR and log; then the TESTS_EXCLUSIVE tests of each suite that has them run alone. Each
# job's output is printed whole when it ends, then a summary and the slowest tests. What a
# job leaves running when it ends (in its group, or under its job dir) is killed then. A job is
# red on a non-zero exit, a missing or failing summary line, no status or a timeout; a suite
# is red when it wrote no run_tests row, a listed test did not run exactly once (finals once
# per partition), or its assertions are below its floor in the table below.
#
#   TEST_JOBS         concurrent jobs; default max(1, ncpu - 2). 1 = serial mode: today's
#                     gate (each suite whole, in name order, output streamed; no perl)
#   TEST_SUITES       space-separated suite names (with or without _test.sh); default all.
#                     A partial run is not the merge gate.
#   TEST_LOG_DIR      job logs, timing.tsv, summary.tsv; default a new temp dir, removed
#                     when the run is green
#   TEST_SLOWEST      length of the slowest-tests list (20)
#   TEST_JOB_TIMEOUT  seconds before a parallel job's group is killed (7200)
#   TEST_SH           the shell that runs each suite (sh); the dash acceptance run sets dash
#   RUN_ALL_SUITES_DIR, RUN_ALL_TABLE — test-only: the suites dir; a table file
# Exit: 0 green · 1 a check failed · 2 usage or table error · 128+N on INT/TERM/HUP.
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SDIR="${RUN_ALL_SUITES_DIR:-$SELF_DIR}"
TEST_SH="${TEST_SH:-sh}"; TEST_SLOWEST="${TEST_SLOWEST:-20}"; TIMEOUT="${TEST_JOB_TIMEOUT:-7200}"
unset TEST_PHASE TEST_SHARD TEST_TIMING_LOG

die2() { printf 'run_all: %s\n' "$*" >&2; exit 2; }
posint() { case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
ncpu() { _c="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"; posint "$_c" || _c=1; echo "$_c"; }

# The suite table: shard counts and assertion floors (each suite's count on origin/main).
# Heaviest first: this is also the launch order. A suite with no row runs as one job, floor 1.
table() {
  if [ -n "${RUN_ALL_TABLE:-}" ]; then cat "$RUN_ALL_TABLE"; return; fi
  cat <<'EOF'
# suite                      shards  floor
overnight_lanes_test         8       1128
overnight_test               4       1132
toolkit_test                 1       175
studio_adopt_test            1       306
install_test                 1       369
studio_setup_test            1       49
hook_test                    1       287
studio_test                  1       661
state_test                   1       245
omega_test                   1       503
state_move_test              1       244
state_pointer_test           1       179
studio_brief_test            1       111
lib_test                     1       112
state_stories_test           1       105
overnight_progress_test      1       39
sdd_script_test              1       22
studio_env_test              1       43
overnight_runs_test          1       41
state_guard_test             1       66
studio_peers_test            1       23
studio_event_test            1       38
overnight_sessions_test      1       23
sync_test                    1       8
pointer_skills_route_test    1       15
pointer_skills_omega_test    1       16
pointer_skills_execute_test  1       14
EOF
}

[ -n "${TEST_JOBS:-}" ] || { TEST_JOBS=$(( $(ncpu) - 2 )); [ "$TEST_JOBS" -ge 1 ] || TEST_JOBS=1; }
posint "$TEST_JOBS" || die2 "TEST_JOBS must be a positive integer, got '$TEST_JOBS'"
posint "$TIMEOUT" || die2 "TEST_JOB_TIMEOUT must be a positive integer, got '$TIMEOUT'"
posint "$TEST_SLOWEST" || die2 "TEST_SLOWEST must be a positive integer, got '$TEST_SLOWEST'"
command -v "$TEST_SH" >/dev/null 2>&1 || die2 "TEST_SH '$TEST_SH' not found"
[ "$TEST_JOBS" = 1 ] || command -v perl >/dev/null 2>&1 \
  || die2 "perl is required for parallel mode (TEST_JOBS=1 runs without it)"

TABLE="$(table | awk '/^[[:space:]]*(#|$)/ { next }
  NF != 3 || $2 !~ /^[1-9][0-9]*$/ || $3 !~ /^[0-9]+$/ { print "BAD row " NR ": " $0; next }
  seen[$1]++ { print "BAD row " NR ": duplicate row for " $1; next }
  { print $1, $2, $3 }')"
case "$TABLE" in *"BAD row"*) die2 "table $(printf '%s\n' "$TABLE" | grep '^BAD' | head -n 1 | sed 's/^BAD //')" ;; esac
for _s in $(printf '%s\n' "$TABLE" | awk '{ print $1 }'); do
  [ -f "$SDIR/$_s.sh" ] || die2 "table names a missing suite: $_s"
done
row_of() { printf '%s\n' "$TABLE" | awk -v s="$1" -v c="$2" '$1 == s { print $c; f = 1 } END { if (!f) print 1 }'; }

ALL=""; for _f in "$SDIR"/*_test.sh; do [ -f "$_f" ] && ALL="$ALL $(basename "$_f" .sh)"; done
PARTIAL=0; SEL="$ALL"
if [ -n "${TEST_SUITES:-}" ]; then
  PARTIAL=1; _want=""
  for _s in $TEST_SUITES; do
    _s="${_s%.sh}"; _s="${_s%_test}_test"
    [ -f "$SDIR/$_s.sh" ] || die2 "unknown suite: $_s"
    _want="$_want $_s"
  done
  SEL=""; for _s in $ALL; do in_list "$_s" "$_want" && SEL="$SEL $_s"; done
fi
ORDER=""; for _s in $(printf '%s\n' "$TABLE" | awk '{ print $1 }'); do in_list "$_s" "$SEL" && ORDER="$ORDER $_s"; done
NOROW=""; for _s in $SEL; do in_list "$_s" "$ORDER" || { ORDER="$ORDER $_s"; NOROW="$NOROW $_s"; }; done

if [ -n "${TEST_LOG_DIR:-}" ]; then
  mkdir -p "$TEST_LOG_DIR" 2>/dev/null && LOGDIR="$(cd "$TEST_LOG_DIR" && pwd -P)" \
    || die2 "cannot create TEST_LOG_DIR $TEST_LOG_DIR"
  OWN_LOG=0
else
  LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/run_all.XXXXXX" 2>/dev/null)" && LOGDIR="$(cd "$LOGDIR" && pwd -P)" \
    || die2 "cannot create a log dir"
  OWN_LOG=1
fi
: > "$LOGDIR/timing.tsv"; : > "$LOGDIR/summary.tsv"; : > "$LOGDIR/floors.tsv"
for _s in $ORDER; do printf '%s\t%s\n' "$_s" "$(row_of "$_s" 3)" >> "$LOGDIR/floors.tsv"; done
for _s in $NOROW; do echo "run_all: $_s has no table row: one job, floor 1"; done

LIVE=""; QUEUE=""; RED=0; XSECS=0; SUITE_RED=""; T_START=$(date +%s)
# RUNID tags this run's rc files (line 2), so an rc left by an earlier run into a reused
# TEST_LOG_DIR, or written late by a straggler of one, is never read as a job's status.
RUNID="$$.$T_START"; LAUNCHING=""; LAUNCH_PREV=""
# Set $! before any launch: under set -u it is unbound until the first background job, and
# launch and on_signal compare it to tell whether a job had been started.
: & wait "$!"
PERL_LAUNCH='$SIG{INT}=$SIG{QUIT}="DEFAULT"; POSIX::setsid() or die "setsid: $!\n"; exec @ARGV or die "exec: $!\n"'
alive() { kill -0 "$1" 2>/dev/null || return 1; case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*|'') return 1 ;; esac; }
count() { echo $#; }
# rc_ok DIR — DIR/rc exists and this run wrote it. rc_of DIR — its status, else nothing.
rc_ok() { [ -f "$1/rc" ] && [ "$(sed -n 2p "$1/rc" 2>/dev/null)" = "$RUNID" ]; }
rc_of() { rc_ok "$1" && sed -n 1p "$1/rc"; }
# rx PATH — PATH as an extended regex that matches only itself (for pgrep/pkill -f).
rx() { printf '%s\n' "$1" | sed 's/[]\\.*^$+?(){}|[]/\\&/g'; }
# sweep JOB — TERM, then KILL, every process whose argv names the job's dir: what left the
# job's group (own_group, setsid) under its TMPDIR (D4). Waits up to 1 s after each signal.
sweep() {
  _sp="$(rx "$LOGDIR/$1/")"
  pgrep -f "$_sp" >/dev/null 2>&1 || return 0
  for _sig in TERM KILL; do
    pkill -"$_sig" -f "$_sp" 2>/dev/null; _sw=0
    while pgrep -f "$_sp" >/dev/null 2>&1 && [ "$_sw" -lt 10 ]; do sleep 0.1; _sw=$((_sw + 1)); done
  done
}
# drop JOB — remove JOB from LIVE.
drop() { _dl=""; for _x in $LIVE; do [ "$_x" = "$1" ] || _dl="$_dl $_x"; done; LIVE="$_dl"; }
# JOB_SH: the job wrapper. rc is written to a temp name and renamed (never read half-written);
# line 1 is the status, line 2 this run's RUNID.
JOB_SH='"$TEST_SH" "$1" > "$2" 2>&1 < /dev/null; _r=$?; printf "%s\n%s\n" "$_r" "$4" > "$3.tmp" && mv "$3.tmp" "$3"'

# launch JOB SUITE PHASE SHARD PART — one parallel job: own session and group, own TMPDIR.
# The job dir starts empty: nothing of a previous run into the same TEST_LOG_DIR survives.
launch() {
  _d="$LOGDIR/$1"; rm -rf "$_d"; mkdir -p "$_d/tmp"
  printf '%s %s\n' "$2" "$5" > "$_d/meta"; date +%s > "$_d/t0"
  LAUNCH_PREV="$!"; LAUNCHING="$1"
  env TMPDIR="$_d/tmp" TEST_TIMING_LOG="$LOGDIR/timing.tsv" TEST_PHASE="$3" TEST_SHARD="$4" TEST_SH="$TEST_SH" \
    perl -MPOSIX -e "$PERL_LAUNCH" \
    sh -c "$JOB_SH" _ "$SDIR/$2.sh" "$_d/log" "$_d/rc" "$RUNID" &
  printf '%s\n' "$!" > "$_d/pid"
  LIVE="$LIVE $1"; LAUNCHING=""
}
# reap PID JOB — the job has ended: wait for it, then KILL what it left behind, in its group
# or escaped from it, so nothing of a finished job runs on into the exclusive phase or past
# run_all (R4.5). Leftovers are noted in the job's log, not made red.
reap() {
  wait "$1" 2>/dev/null; _left=0
  if kill -0 "-$1" 2>/dev/null; then _left=1; kill -KILL "-$1" 2>/dev/null; fi
  if pgrep -f "$(rx "$LOGDIR/$2/")" >/dev/null 2>&1; then _left=1; sweep "$2"; fi
  [ "$_left" = 0 ] || printf '\nrun_all: %s left processes running after it ended; killed them\n' "$2" >> "$LOGDIR/$2/log"
}
# finish JOB REASON [quiet] — one summary row; print the job's block unless quiet.
# A job is finished once (the done marker), even if a signal lands mid-pool.
finish() {
  _d="$LOGDIR/$1"; _why="$2"; read -r _s _pt < "$_d/meta"
  [ ! -f "$_d/done" ] || return 0
  _secs=$(( $(date +%s) - $(cat "$_d/t0") ))
  _rc="$(rc_of "$_d")"
  _sum="$(grep -E '^[0-9]+ assertions, [0-9]+ failed$' "$_d/log" 2>/dev/null | tail -n 1)"
  _a="${_sum%% *}"; _f="$(printf '%s\n' "$_sum" | sed -n 's/^.* assertions, \([0-9]*\) failed$/\1/p')"
  _nt="$(awk -F'\t' -v s="$_s" -v p="$_pt" '$1 == "T" && $2 == s && $3 == p { n++ } END { print n + 0 }' "$LOGDIR/timing.tsv")"
  if [ -z "$_why" ]; then
    if [ -z "$_rc" ]; then _why="no status"
    elif [ -z "$_sum" ]; then _why="no summary line"
    elif [ "$_f" != 0 ]; then _why="$_f failed"
    elif [ "$_rc" != 0 ]; then _why="exit $_rc"
    fi
  fi
  if [ -z "$_why" ]; then _v=green; else _v="red: $_why"; RED=1; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_s" "$_pt" "$_secs" "$_nt" "${_a:-0}" "${_f:-0}" "$_v" >> "$LOGDIR/summary.tsv"
  : > "$_d/done"
  [ "${3:-}" = quiet ] || { printf '\n=== %s [%s] %s s ===\n' "$_s" "$_pt" "$_secs"; cat "$_d/log"; }
}
# stop_group PID JOB — TERM the job's group, KILL it after 5 s, then sweep what escaped it (D4).
stop_group() {
  kill -TERM "-$1" 2>/dev/null; _sg=0
  while kill -0 "-$1" 2>/dev/null && [ "$_sg" -lt 25 ]; do sleep 0.2; _sg=$((_sg + 1)); done
  kill -KILL "-$1" 2>/dev/null
  sweep "$2"
}
# pool MAX — run the QUEUE words "job|suite|phase|shard|part" with at most MAX jobs live.
pool() {
  _pmax="$1"; _plast=$(date +%s)
  while [ -n "$QUEUE" ] || [ -n "$LIVE" ]; do
    for _j in $LIVE; do
      _d="$LOGDIR/$_j"; _p="$(cat "$_d/pid")"
      if rc_ok "$_d"; then reap "$_p" "$_j"; finish "$_j" ""
      elif ! alive "$_p"; then
        reap "$_p" "$_j"
        if rc_ok "$_d"; then finish "$_j" ""; else finish "$_j" "no status"; fi
      elif [ $(( $(date +%s) - $(cat "$_d/t0") )) -ge "$TIMEOUT" ]; then
        stop_group "$_p" "$_j"; wait "$_p" 2>/dev/null; finish "$_j" "timed out after $TIMEOUT s"
      else continue; fi
      drop "$_j"
    done
    while [ -n "$QUEUE" ] && [ "$(count $LIVE)" -lt "$_pmax" ]; do
      set -- $QUEUE; _q="$1"; shift; QUEUE="$*"
      _oifs="$IFS"; IFS='|'; set -- $_q; IFS="$_oifs"
      launch "$1" "$2" "$3" "$4" "$5"
    done
    if [ $(( $(date +%s) - _plast )) -ge 60 ]; then
      printf 'run_all: still running:%s\n' "$LIVE" >&2; _plast=$(date +%s)
    fi
    if [ -n "$QUEUE" ] || [ -n "$LIVE" ]; then sleep 0.2; fi
  done
}
parallel_mode() {
  for _s in $ORDER; do
    _n="$(row_of "$_s" 2)"
    if [ "$_n" -gt 1 ]; then
      _k=1; while [ "$_k" -le "$_n" ]; do
        QUEUE="$QUEUE $_s.p${_k}of$_n|$_s|parallel|$_k/$_n|p${_k}of$_n"; _k=$((_k + 1)); done
    else QUEUE="$QUEUE $_s.p1of1|$_s|parallel||p1of1"; fi
  done
  pool "$TEST_JOBS"
  _x0=$(date +%s)
  for _s in $ORDER; do
    if grep -q '^TESTS_EXCLUSIVE=' "$SDIR/$_s.sh"; then QUEUE="$QUEUE $_s.x|$_s|exclusive||x"; fi
  done
  pool 1
  XSECS=$(( $(date +%s) - _x0 ))
}
serial_mode() {
  for _s in $SEL; do
    _d="$LOGDIR/$_s"; rm -rf "$_d"; mkdir -p "$_d"; date +%s > "$_d/t0"; printf '%s all\n' "$_s" > "$_d/meta"
    printf '\n=== %s ===\n' "$_s.sh"
    { TEST_TIMING_LOG="$LOGDIR/timing.tsv" "$TEST_SH" "$SDIR/$_s.sh"; printf '%s\n%s\n' "$?" "$RUNID" > "$_d/rc"; } 2>&1 | tee "$_d/log"
    finish "$_s" "" quiet
  done
}
# checks — one line per red suite: no L row, differing listed counts, a test not run exactly
# once (finals once per partition), or assertions below the floor.
checks() {
  awk -F'\t' '
    FILENAME ~ /floors\.tsv$/ { floor[$1] = $2; next }
    FILENAME ~ /summary\.tsv$/ { ran[$1] = 1; asum[$1] += $5; next }
    $1 == "L" { if (($2 in nl) && listed[$2] != $4) diff[$2] = 1
                nl[$2]++; listed[$2] = $4; fin[$2] = $5; next }
    $1 == "T" { k = $2 SUBSEP $4; cnt[k]++; name[k] = $5; next }
    END {
      for (s in ran) {
        if (!(s in nl)) { print s ": no run_tests row"; continue }
        if (s in diff) print s ": listed counts differ across partitions"
        split("", isf)
        if (fin[s] != "-") { n = split(fin[s], fa, ","); for (i = 1; i <= n; i++) isf[fa[i]] = 1 }
        for (i = 1; i <= listed[s]; i++) {
          k = s SUBSEP i; want = (i in isf) ? nl[s] : 1; got = cnt[k] + 0
          if (got == 0) print s ": test " i " never ran"
          else if (got != want) print s ": test " i " (" name[k] ") ran " got " times"
        }
        if (asum[s] < floor[s]) print s ": " asum[s] " assertions, below its floor " floor[s]
      }
    }' "$LOGDIR/floors.tsv" "$LOGDIR/summary.tsv" "$LOGDIR/timing.tsv" | sort
}
summary() {
  printf '\n=== summary%s ===\n' "${1:+ ($1)}"
  awk -F'\t' '{ printf "%-30s %-8s %6s s %5s tests %6s assertions %4s failed  %s\n", $1, $2, $3, $4, $5, $6, $7 }' "$LOGDIR/summary.tsv"
  [ -z "$SUITE_RED" ] || printf '%s\n' "$SUITE_RED" | sed 's/^/RED /'
  awk -F'\t' -v w=$(( $(date +%s) - T_START )) -v x="$XSECS" '
    { s[$1] = 1; j++; a += $5; f += $6 }
    END { n = 0; for (k in s) n++
          printf "total: %s s wall, %d suites, %d jobs, %d assertions, %d failed, exclusive phase %s s\n", w, n, j, a, f, x }' "$LOGDIR/summary.tsv"
  printf 'slowest %s tests:\n' "$TEST_SLOWEST"
  awk -F'\t' '$1 == "T" { printf "%s\t%s\t%s\t%s\n", $6, $2, $3, $5 }' "$LOGDIR/timing.tsv" \
    | sort -t "$(printf '\t')" -k1,1nr | head -n "$TEST_SLOWEST" \
    | awk -F'\t' '{ printf "  %5s s  %s [%s] %s\n", $1, $2, $3, $4 }'
}
# on_signal N NAME — forward to every live job's group, wait 10 s, KILL, sweep each job's dir.
on_signal() {
  trap '' INT TERM HUP
  for _j in $LIVE; do [ ! -f "$LOGDIR/$_j/done" ] || drop "$_j"; done
  # A signal between launch's `&` and its LIVE update: the job is $! (it differs from the
  # last background pid before the launch only once the job was started). It may not have
  # reached its setsid yet, so it also gets a pid KILL below (it is unreaped: no pid reuse).
  _late=""
  if [ -n "$LAUNCHING" ] && ! in_list "$LAUNCHING" "$LIVE" && [ "$!" != "$LAUNCH_PREV" ]; then
    printf '%s\n' "$!" > "$LOGDIR/$LAUNCHING/pid"; LIVE="$LIVE $LAUNCHING"; _late="$!"
  fi
  for _j in $LIVE; do kill -"$2" "-$(cat "$LOGDIR/$_j/pid")" 2>/dev/null; done
  _w=0
  while [ "$_w" -lt 50 ]; do
    _any=0
    for _j in $LIVE; do kill -0 "-$(cat "$LOGDIR/$_j/pid")" 2>/dev/null && _any=1; done
    [ "$_any" = 1 ] || break
    sleep 0.2; _w=$((_w + 1))
  done
  for _j in $LIVE; do kill -KILL "-$(cat "$LOGDIR/$_j/pid")" 2>/dev/null; done
  [ -z "$_late" ] || kill -KILL "$_late" 2>/dev/null
  for _j in $LIVE; do sweep "$_j"; done
  for _j in $LIVE; do wait "$(cat "$LOGDIR/$_j/pid")" 2>/dev/null; finish "$_j" interrupted; done
  summary interrupted
  printf 'run_all: interrupted — logs kept in %s\n' "$LOGDIR" >&2
  exit $(( 128 + $1 ))
}
trap 'on_signal 2 INT' INT; trap 'on_signal 15 TERM' TERM; trap 'on_signal 1 HUP' HUP

if [ "$TEST_JOBS" = 1 ]; then serial_mode; else parallel_mode; fi
if [ -n "${TESTS_ONLY:-}" ]; then
  echo "run_all: TESTS_ONLY is set — suite checks skipped (a partial run is not a gate)"
else
  SUITE_RED="$(checks)"; [ -z "$SUITE_RED" ] || RED=1
fi
summary
[ "$PARTIAL" = 0 ] || echo "run_all: partial run (TEST_SUITES) — not the merge gate"
if [ "$RED" = 0 ]; then [ "$OWN_LOG" = 0 ] || rm -rf "$LOGDIR"; exit 0; fi
echo "run_all: logs kept in $LOGDIR"
exit 1
