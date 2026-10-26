#!/bin/sh
# Suite for studios/game-dev/bin/studio-setup (#35 AC19, AC20): the project
# hooks under the gate lock. Offline; temp repos; a temp HOME.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/tests/gate_times_rows.sh"
SETUP="$REPO_ROOT/studios/game-dev/bin/studio-setup"
GATE="$REPO_ROOT/studios/game-dev/bin/studio-gate"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
mk_tmp studio_setup_test
trap 'rm_tmp "$TMP"' EXIT
mk_msleep || exit 1
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
unset STUDIO_GATE_HELD STUDIO_SETUP_TIMEOUT_SECONDS STUDIO_SETUP_POLL_SECONDS STUDIO_UNIT_TAG

# proj NAME CONFIG_JSON — $P: a committed studio project with that config.
proj() {
  P="$TMP/$1"; rm -rf "$P"; mkdir -p "$P"
  ( cd "$P" && git init -q -b main && sh "$STATE_BIN" init >/dev/null
    printf '%s\n' "$2" > .studio/config.json
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m init ) >/dev/null 2>&1
}
# setup DIR [ARGS] — studio-setup in DIR: SU_STATUS, $TMP/su.out, $TMP/su.err.
setup() { _d="$1"; shift; SU_STATUS=0; ( cd "$_d" && sh "$SETUP" "$@" ) > "$TMP/su.out" 2> "$TMP/su.err" || SU_STATUS=$?; }
# TMPRE: $TMP escaped for use inside an ERE.
# MS: the msleep path, single-quoted, for use inside generated command text (TMPDIR may hold a space).
MS="'$TMP/bin/msleep'"
TMPRE="$(printf '%s' "$TMP" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"
# count_procs N - how many processes ARE $TMP/bin/msleep N: argv exactly "$TMP/bin/msleep N", or behind
# the perl fallback's "perl ". The anchor keeps studio-gate and the sh -c wrapper, whose argv only ends
# in "msleep' N" (the path is single-quoted in the command text), from matching. N may be an ERE fragment.
count_procs() { pgrep -f "(^|perl )$TMPRE/bin/msleep $1\$" | wc -l | tr -d ' '; } # scan-ok: scoped to this run's $TMP/bin/msleep
# wait_absent N TICKS - poll every 0.1 s until no msleep N is left, at most TICKS ticks.
wait_absent() { _wa=0; while [ "$(count_procs "$1")" != 0 ] && [ "$_wa" -lt "$2" ]; do sleep 0.1; _wa=$((_wa + 1)); done; }
# wait_present N TICKS - poll every 0.1 s until an msleep N runs, at most TICKS ticks (event wait: pass 600).
wait_present() { _wp=0; while [ "$(count_procs "$1")" = 0 ] && [ "$_wp" -lt "$2" ]; do sleep 0.1; _wp=$((_wp + 1)); done; }
# R7: knobs unset at the top; non-real-clock tests poll at 0.2 s.
before_each() {
  unset STUDIO_SETUP_POLL_SECONDS STUDIO_GATE_POLL_SECONDS \
        STUDIO_OVERNIGHT_REAP_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
  is_real_clock && return 0
  STUDIO_SETUP_POLL_SECONDS=0.2; STUDIO_GATE_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_REAP_POLL_SECONDS=0.2; STUDIO_OVERNIGHT_DETACH_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_POLL_SECONDS=1
  export STUDIO_SETUP_POLL_SECONDS STUDIO_GATE_POLL_SECONDS STUDIO_OVERNIGHT_REAP_POLL_SECONDS \
         STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
}

test_setup_unset_is_silent() {
  proj un '{ "engine": "godot4" }'
  setup "$P"
  assert_eq 0 "$SU_STATUS" "no worktree_setup: exit 0"
  assert_eq "" "$(cat "$TMP/su.out" "$TMP/su.err")" "and silent"
  setup "$P" gate
  assert_eq 0 "$SU_STATUS" "no gate_command: exit 0"
}
test_setup_runs_under_lock_and_logs() {
  proj ok '{ "worktree_setup": "cat .studio/gate.lock/who > who.txt; echo ran >> ran.txt" }'
  setup "$P"
  assert_eq 0 "$SU_STATUS" "a green setup exits 0"
  assert_eq setup "$(cat "$P/who.txt")" "it ran holding the gate lock as setup"
  assert_eq 1 "$(ls "$P"/.studio/reports/setup-*.log | wc -l | tr -d ' ')" "one setup log"
  assert_contains "$P/.studio/reports/.gitignore" '^\*$' "reports are git-ignored"
  assert_eq 1 "$(gt_rows "$P/.studio/gate.times" setup 0)" "gate.times has the setup line"
  assert_contains "$P/.studio/gate.times" '^[0-9][0-9]* setup [0-9][0-9]* 0 [0-9][0-9]* [a-z][a-z:-]* [a-z][a-z]* [^ ][^ ]*$' "the row has all 8 fields"
}
test_setup_marker_skip_and_rerun() {
  proj mk '{ "worktree_setup": "echo ran >> ran.txt" }'
  setup "$P"; setup "$P"
  assert_eq 1 "$(wc -l < "$P/ran.txt" | tr -d ' ')" "the marker makes the second call a no-op"
  assert_file "$P/.git/studio-setup.done" "the marker sits in the git dir"
  printf '{ "worktree_setup": "echo again >> ran.txt" }\n' > "$P/.studio/config.json"
  setup "$P"
  assert_eq 2 "$(wc -l < "$P/ran.txt" | tr -d ' ')" "a changed command runs again"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m cfg && git worktree add -q "$TMP/mk-wt" -b wt ) >/dev/null 2>&1
  setup "$TMP/mk-wt"
  assert_file "$TMP/mk-wt/ran.txt" "a new worktree (new git dir, no marker) runs it"
}
test_setup_nonzero_exit() {
  proj nz '{ "worktree_setup": "echo boom; exit 7" }'
  setup "$P"
  assert_eq 1 "$SU_STATUS" "a red setup exits 1"
  assert_eq 1 "$(wc -l < "$TMP/su.err" | tr -d ' ')" "one stderr line"
  assert_contains "$TMP/su.err" '^worktree setup failed — exit 7 — log \.studio/reports/setup-[0-9-]*\.log$' "naming the exit and the log"
  assert_missing "$P/.git/studio-setup.done" "no marker after a failure"
  assert_contains "$(ls "$P"/.studio/reports/setup-*.log)" '^boom$' "the log holds the output"
}
test_setup_timeout_ends_group() {
  proj to '{ "worktree_setup": "'"$MS"' 4801 & '"$MS"' 4802" }'
  STUDIO_SETUP_TIMEOUT_SECONDS=2; export STUDIO_SETUP_TIMEOUT_SECONDS
  setup "$P"; unset STUDIO_SETUP_TIMEOUT_SECONDS
  assert_eq 1 "$SU_STATUS" "a timeout exits 1"
  assert_contains "$TMP/su.err" '^worktree setup failed — exit 124 — log ' "exit 124 names the timeout"
  assert_eq 1 "$(wc -l < "$TMP/su.err" | tr -d ' ')" "no job-control noise on stderr"
  wait_absent '480[12]' 10
  assert_eq 0 "$(count_procs '480[12]')" "the grandchild sleeps are gone"
  assert_contains "$(ls "$P"/.studio/reports/setup-*.log)" 'timed out after 2 s' "the log says so"
  assert_missing "$P/.studio/gate.lock" "the lock is released"
}
test_setup_timer_starts_after_lock() {
  proj tl '{ "worktree_setup": "echo ran > ran.txt" }'
  ( cd "$P" && sh "$GATE" holder -- sleep 3 ) >/dev/null 2>&1 &
  _h=$!; _i=0; while [ ! -f "$P/.studio/gate.lock/pid" ] && [ "$_i" -lt 300 ]; do sleep 0.2; _i=$((_i + 1)); done
  assert_file "$P/.studio/gate.lock/pid" "the holder took the lock within the 60 s ceiling"
  STUDIO_SETUP_TIMEOUT_SECONDS=1; export STUDIO_SETUP_TIMEOUT_SECONDS
  setup "$P"; unset STUDIO_SETUP_TIMEOUT_SECONDS; wait "$_h"
  assert_eq 0 "$SU_STATUS" "waiting 3 s for the lock is not a 1 s timeout"
  assert_file "$P/ran.txt" "the command ran once the lock was free"
}
test_setup_bad_config() {
  proj bc '{ "worktree_setup": "true", "worktree_setup_minutes": 0 }'
  setup "$P"; assert_eq 2 "$SU_STATUS" "minutes 0 is refused"
  proj bc2 '{ "worktree_setup": "true", "worktree_setup_minutes": 121 }'
  setup "$P"; assert_eq 2 "$SU_STATUS" "minutes 121 is refused"
  proj bc3 '{ "worktree_setup": "printf a\\tb" }'
  setup "$P"; assert_eq 2 "$SU_STATUS" "a backslash is refused"
  setup "$P" bogus; assert_eq 2 "$SU_STATUS" "an unknown verb is usage"
}
test_setup_gate_green_and_red() {
  proj gg '{ "gate_command": "echo gate-ok" }'
  setup "$P" gate
  assert_eq 0 "$SU_STATUS" "green gate_command exits 0"
  assert_contains "$TMP/su.out" '^gate_command: green — log \.studio/reports/gate-[0-9-]*\.log$' "names the log"
  assert_eq 1 "$(gt_rows "$P/.studio/gate.times" gate 0)" "runs as who=gate"
  assert_contains "$P/.studio/gate.times" '^[0-9][0-9]* gate [0-9][0-9]* 0 [0-9][0-9]* [a-z][a-z:-]* [a-z][a-z]* [^ ][^ ]*$' "the row has all 8 fields"
  proj gr '{ "gate_command": "echo FAIL one; exit 3" }'
  setup "$P" gate
  assert_eq 3 "$SU_STATUS" "red exits with the command's status"
  assert_contains "$TMP/su.err" '^gate_command exit 3 — log \.studio/reports/gate-[0-9-]*\.log$' "the red line"
}
test_setup_signal_stops_child_and_releases_lock() {
  proj sg '{ "worktree_setup": "'"$MS"' 4811" }'
  ( cd "$P" && exec sh "$SETUP" ) > "$TMP/sg.out" 2>&1 &
  _s=$!
  wait_present 4811 600
  assert_eq 1 "$(count_procs 4811)" "the setup command is running before TERM is sent"
  kill -TERM "$_s"; _rc=0; wait "$_s" || _rc=$?
  assert_eq 143 "$_rc" "TERM ends studio-setup with 128+15"
  wait_absent 4811 10
  assert_eq 0 "$(count_procs 4811)" "the setup command is gone"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
}
test_setup_timeout_kills_term_ignorer() {
  proj ti '{ "worktree_setup": "sh ign.sh" }'
  printf "trap '' TERM\n%s 4821\n" "$MS" > "$P/ign.sh"
  STUDIO_SETUP_TIMEOUT_SECONDS=1; export STUDIO_SETUP_TIMEOUT_SECONDS
  setup "$P"; unset STUDIO_SETUP_TIMEOUT_SECONDS
  assert_contains "$TMP/su.err" '^worktree setup failed — exit 124 — log ' "exit 124 after KILL"
  assert_eq 0 "$(count_procs 4821)" "the TERM-ignoring command is gone"
  assert_missing "$P/.studio/gate.lock" "the lock is released"
}
test_setup_quoted_minutes_refused() {
  proj qm '{ "worktree_setup": "true", "worktree_setup_minutes": "500" }'
  setup "$P"
  assert_eq 2 "$SU_STATUS" "a quoted minutes value is refused"
  assert_contains "$TMP/su.err" 'worktree_setup_minutes must be an integer 1-120' "with the bad-config message"
}
test_setup_logs_unique_per_run() {
  proj ul '{ "gate_command": "echo hi" }'
  setup "$P" gate; setup "$P" gate
  assert_eq 2 "$(ls "$P"/.studio/reports/gate-*.log | wc -l | tr -d ' ')" "two runs in one second keep two logs"
}
test_setup_gate_backslash_refused() {
  proj gb '{ "gate_command": "printf a\\tb" }'
  setup "$P" gate
  assert_eq 2 "$SU_STATUS" "a backslash in gate_command is refused"
}
test_setup_no_studio_dir() {
  P="$TMP/nostudio"; rm -rf "$P"; mkdir -p "$P"
  ( cd "$P" && git init -q -b main ) >/dev/null 2>&1
  setup "$P"
  assert_eq 0 "$SU_STATUS" "no .studio dir: exit 0"
  mkdir -p "$P/.studio"; printf '%s\n' '{ "worktree_setup": "echo ran > ran.txt" }' > "$P/.studio/config.json"
  setup "$P"
  assert_eq 0 "$SU_STATUS" "config without a state dir still runs green"
  assert_file "$P/ran.txt" "the command ran"
}
test_setup_help() {
  assert_status 0 "--help exits 0" -- sh "$SETUP" --help
  sh "$SETUP" --help > "$TMP/help.out" 2>&1
  assert_contains "$TMP/help.out" 'worktree_setup' "--help prints the usage text"
  STUDIO_SETUP_POLL_SECONDS=0.3; export STUDIO_SETUP_POLL_SECONDS
  assert_status 0 "--help exits 0 even with a bad poll value" -- sh "$SETUP" --help
  unset STUDIO_SETUP_POLL_SECONDS
}

test_setup_poll_keeps_budget() {
  proj pk '{ "worktree_setup": "sh ign.sh" }'
  # ign.sh signals "ready" only after its trap is in. A 1 s timeout (whole-second clock, 0.2 s polls) can
  # fire before that, so such an attempt proves nothing: retry it, and fail loudly if none gets ready.
  printf "trap '' TERM\n: > ready\n%s 4822\n" "$MS" > "$P/ign.sh"
  STUDIO_SETUP_TIMEOUT_SECONDS=1; STUDIO_SETUP_POLL_SECONDS=0.2; export STUDIO_SETUP_TIMEOUT_SECONDS STUDIO_SETUP_POLL_SECONDS
  _try=0
  while [ "$_try" -lt 5 ]; do
    rm -f "$P/ready"
    _t0=$(date +%s); setup "$P"; _el=$(( $(date +%s) - _t0 ))
    [ -f "$P/ready" ] && break
    _try=$((_try + 1))
  done
  unset STUDIO_SETUP_TIMEOUT_SECONDS STUDIO_SETUP_POLL_SECONDS
  assert_file "$P/ready" "the TERM-ignoring stub got its trap in before the timeout fired ($_try retries)"
  assert_eq 1 "$SU_STATUS" "a timed-out setup exits 1"
  assert_contains "$TMP/su.err" 'exit 124' "with exit 124"
  _ok=no; [ "$_el" -ge 5 ] && _ok=yes
  assert_eq yes "$_ok" "tg_stop's 5 s grace survives 0.2 s ticks (took $_el s)"
}
test_setup_poll_rejects_bad_value() {
  proj pb '{ "worktree_setup": "true" }'
  STUDIO_SETUP_POLL_SECONDS=0.3; export STUDIO_SETUP_POLL_SECONDS
  setup "$P"; unset STUDIO_SETUP_POLL_SECONDS
  assert_eq 2 "$SU_STATUS" "a bad poll value exits 2"
  assert_contains "$TMP/su.err" '^studio-setup: STUDIO_SETUP_POLL_SECONDS must be 1, 0.5, 0.2 or 0.1, got 0.3$' "naming the knob and the value"
  assert_missing "$P/.studio/gate.lock" "no lock is left"
}

# run_shape NAME START_JSON MAIN_JSON — the incident's shape (phoenix run
# bat-sonic-followups, story KAN-1723-2): a main checkout $P whose .studio/config.json
# (MAIN_JSON) is git-excluded; a run worktree $RW on run/demo with START_JSON
# committed there past the exclude (studio-overnight refuses an uncommitted one);
# a story worktree $SW on `story`, forked from main, with no config of its own.
run_shape() {
  P="$TMP/$1"; RW="$TMP/$1-run"; SW="$TMP/$1-story"; rm -rf "$P" "$RW" "$SW"; mkdir -p "$P"
  ( set -e; cd "$P"; git init -q -b main; sh "$STATE_BIN" init >/dev/null
    printf '.studio/config.json\n' >> .git/info/exclude
    git add -A; git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    printf '%s\n' "$3" > .studio/config.json
    git worktree add -q -b run/demo "$RW"; mkdir -p "$RW/.studio"
    printf '%s\n' "$2" > "$RW/.studio/config.json"
    git -C "$RW" add -f .studio/config.json; git -C "$RW" -c user.name=t -c user.email=t@t commit -q -m cfg
    git worktree add -q -b story "$SW" main ) >/dev/null 2>&1 \
    || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "run_shape $1: setup failed"; }
}
# setup_run DIR [ARGS] — setup in DIR as a unit runs it: STUDIO_START_DIR=$RW.
setup_run() { _d="$1"; shift; SU_STATUS=0
  ( cd "$_d" && STUDIO_START_DIR="$RW" && export STUDIO_START_DIR && sh "$SETUP" "$@" ) > "$TMP/su.out" 2> "$TMP/su.err" || SU_STATUS=$?; }
RAN_CMD='echo ran >> .studio/reports/ran.txt'

# The incident: the run's worktree_setup lives only in the run worktree's config;
# the story worktree has none and the main checkout's has no worktree_setup.
# Before the fix studio-setup read the tree, then the state root, and exited 0
# silently without running anything.
test_setup_run_config_reaches_story_worktree() {
  run_shape inc '{ "engine": "godot4", "test_engine_args": "--fixed-fps 60", "overnight": { "worktree_setup": "'"$RAN_CMD"'" } }' '{ "engine": "godot4" }'
  setup_run "$SW"
  assert_eq 0 "$SU_STATUS" "a green setup in the story worktree exits 0"
  assert_file "$SW/.studio/reports/ran.txt" "the run's worktree_setup ran in the story worktree"
  assert_file "$(git -C "$SW" rev-parse --absolute-git-dir)/studio-setup.done" "and left its marker in the story's git dir"
  assert_eq "$(cat "$RW/.studio/config.json")" "$(cat "$SW/.studio/config.json" 2>/dev/null)" "the run's config is seeded into the story worktree"
  assert_eq "" "$(git -C "$SW" status --porcelain 2>&1)" "the seeded copy is git-excluded: the story worktree stays clean"
  assert_eq "--fixed-fps 60" "$( cd "$SW" && unset STUDIO_START_DIR && . "$REPO_ROOT/studios/game-dev/bin/gate-class.sh" && studio_cfg test_engine_args )" \
    "a reader with no STUDIO_START_DIR (a hand session) now sees the run's keys too"
  assert_missing "$P/.studio/reports/ran.txt" "nothing ran in the main checkout"
}
# A fresh story worktree of a project whose .studio/config.json is untracked
# (only in the start checkout) runs the project's worktree_setup: the setup
# runs in the worktree, and prints no skip.
test_setup_fresh_story_worktree_runs_setup() {
  P="$TMP/fsw"; SW="$TMP/fsw-story"; rm -rf "$P" "$SW"; mkdir -p "$P"
  ( set -e; cd "$P"; git init -q -b main; sh "$STATE_BIN" init >/dev/null
    printf '.studio/config.json\n' >> .git/info/exclude
    git add -A; git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    printf '%s\n' '{ "overnight": { "worktree_setup": "touch setup-ran" } }' > .studio/config.json
    git worktree add -q -b story "$SW" main ) >/dev/null 2>&1 \
    || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "fresh story worktree: setup failed"; return 0; }
  assert_missing "$SW/.studio/config.json" "the fresh worktree has no config of its own"
  SU_STATUS=0
  ( cd "$SW" && STUDIO_START_DIR="$P" && export STUDIO_START_DIR && sh "$SETUP" ) > "$TMP/su.out" 2> "$TMP/su.err" || SU_STATUS=$?
  assert_eq 0 "$SU_STATUS" "the setup exits 0"
  assert_file "$SW/setup-ran" "worktree_setup ran in the fresh story worktree"
  assert_missing "$P/setup-ran" "and not in the start checkout"
  assert_not_contains "$TMP/su.err" "skip" "no skip is printed (stderr)"
  assert_not_contains "$TMP/su.out" "skip" "no skip is printed (stdout)"
}
# Resolution order: the tree's key, then $STUDIO_START_DIR's, then the state root's.
test_setup_resolution_order() {
  run_shape ord '{ "worktree_setup": "echo start >> .studio/reports/ran.txt" }' '{ "worktree_setup": "echo root >> .studio/reports/ran.txt", "worktree_setup_minutes": 0 }'
  mkdir -p "$SW/.studio"
  printf '%s\n' '{ "worktree_setup": "echo tree >> .studio/reports/ran.txt", "worktree_setup_minutes": 5 }' > "$SW/.studio/config.json"
  setup_run "$SW"
  assert_eq tree "$(cat "$SW/.studio/reports/ran.txt" 2>/dev/null)" "the tree's own key wins"
  assert_eq '{ "worktree_setup": "echo tree >> .studio/reports/ran.txt", "worktree_setup_minutes": 5 }' "$(cat "$SW/.studio/config.json")" "a config of the tree's own is never overwritten"
  run_shape ord2 '{ "worktree_setup": "echo start >> .studio/reports/ran.txt" }' '{ "worktree_setup": "echo root >> .studio/reports/ran.txt" }'
  setup_run "$SW"
  assert_eq start "$(cat "$SW/.studio/reports/ran.txt" 2>/dev/null)" "then the run's (STUDIO_START_DIR) before the state root's"
  run_shape ord3 '{ "engine": "godot4" }' '{ "worktree_setup": "echo root >> .studio/reports/ran.txt" }'
  setup "$SW"
  assert_eq root "$(cat "$SW/.studio/reports/ran.txt" 2>/dev/null)" "outside a run, the state root's (D8)"
  assert_missing "$SW/.studio/config.json" "and nothing is seeded outside a run"
}
# Outside a run, or in a run whose config has no worktree_setup, unset stays a silent exit 0.
test_setup_unset_in_and_out_of_run_silent() {
  run_shape us '{ "engine": "godot4" }' '{ "engine": "godot4" }'
  setup_run "$SW"
  assert_eq 0 "$SU_STATUS" "a run config without worktree_setup: exit 0"
  assert_eq "" "$(cat "$TMP/su.out" "$TMP/su.err")" "and silent"
  setup "$SW"
  assert_eq 0 "$SU_STATUS" "no STUDIO_START_DIR, no worktree_setup anywhere: exit 0"
  assert_eq "" "$(cat "$TMP/su.out" "$TMP/su.err")" "and silent"
}
# The backstop: a run whose start config sets worktree_setup, in a worktree that
# resolves none (a resolver that skips the run's config, as studio-setup did
# before), is a loud exit 2, never a silent skip.
test_setup_run_config_unresolved_fails_loud() {
  run_shape lf '{ "worktree_setup": "'"$RAN_CMD"'" }' '{ "engine": "godot4" }'
  rm -rf "$TMP/drift-bin"; cp -R "$REPO_ROOT/studios/game-dev/bin" "$TMP/drift-bin"
  sed 's/ "\${STUDIO_START_DIR:-}"//' "$REPO_ROOT/studios/game-dev/bin/gate-class.sh" > "$TMP/drift-bin/gate-class.sh"
  # No seeding either: the tree must not get the run's config by the copy.
  sed -i.bak '/\.studio\/config\.json/d' "$P/.git/info/exclude"
  SU_STATUS=0
  ( cd "$SW" && STUDIO_START_DIR="$RW" && export STUDIO_START_DIR && sh "$TMP/drift-bin/studio-setup" ) > "$TMP/su.out" 2> "$TMP/su.err" || SU_STATUS=$?
  assert_eq 2 "$SU_STATUS" "the run sets worktree_setup, the worktree resolves none: exit 2"
  assert_eq 1 "$(wc -l < "$TMP/su.err" | tr -d ' ')" "one stderr line"
  assert_contains "$TMP/su.err" "^studio-setup: the run's config sets worktree_setup .*, but this worktree resolves none — not skipping it silently$" "naming the cause"
  assert_missing "$SW/.studio/reports/ran.txt" "nothing ran"
}
# Seeding: only where git ignores the path; an unedited earlier copy follows the
# run's config; a hand-edited copy is kept.
test_setup_seed_rules() {
  run_shape sd '{ "worktree_setup": "'"$RAN_CMD"'" }' '{ "engine": "godot4" }'
  sed -i.bak '/\.studio\/config\.json/d' "$P/.git/info/exclude"
  setup_run "$SW"
  assert_eq 0 "$SU_STATUS" "not ignored: still green"
  assert_file "$SW/.studio/reports/ran.txt" "the run's command ran through the resolver"
  assert_missing "$SW/.studio/config.json" "but nothing is seeded where git would see the copy"
  assert_eq "" "$(git -C "$SW" status --porcelain 2>&1)" "the story worktree stays clean"
  run_shape sd2 '{ "worktree_setup": "'"$RAN_CMD"'" }' '{ "engine": "godot4" }'
  setup_run "$SW"
  printf '%s\n' '{ "worktree_setup": "echo v2 >> .studio/reports/ran.txt" }' > "$RW/.studio/config.json"
  setup_run "$SW"
  assert_eq "$(cat "$RW/.studio/config.json")" "$(cat "$SW/.studio/config.json")" "an unedited earlier copy follows the run's config"
  assert_eq "ran v2" "$(tr '\n' ' ' < "$SW/.studio/reports/ran.txt" | sed 's/ $//')" "and the changed command runs"
  printf '%s\n' '{ "worktree_setup": "echo mine >> .studio/reports/ran.txt" }' > "$SW/.studio/config.json"
  printf '%s\n' '{ "worktree_setup": "echo v3 >> .studio/reports/ran.txt" }' > "$RW/.studio/config.json"
  setup_run "$SW"
  assert_eq '{ "worktree_setup": "echo mine >> .studio/reports/ran.txt" }' "$(cat "$SW/.studio/config.json")" "a hand-edited copy is kept"
}

# exclusive-scan: test_setup_timeout_ends_group in (d) a two-second setup timeout the group kill must beat, then a one-second absence window
# exclusive-scan: test_setup_timer_starts_after_lock in (b) a three-second lock holder must still be running when setup starts waiting, against a one-second timeout (d)
# exclusive-scan: test_setup_signal_stops_child_and_releases_lock in (b) TERM is sent to the live setup run, and the child must disappear after a one-second absence window
# exclusive-scan: test_setup_timeout_kills_term_ignorer in (d) a one-second timeout; the TERM-ignorer must be KILLed after the full five-second grace (production poll)
# exclusive-scan: test_setup_poll_keeps_budget in (d) a one-second whole-second-clock timeout races the stub's trap, and the grace is waited at a 0.2 s poll
TESTS_EXCLUSIVE="test_setup_timeout_ends_group test_setup_timer_starts_after_lock test_setup_timeout_kills_term_ignorer test_setup_signal_stops_child_and_releases_lock test_setup_poll_keeps_budget"
TESTS_REAL_CLOCK=""
run_tests test_setup_unset_is_silent test_setup_runs_under_lock_and_logs test_setup_marker_skip_and_rerun \
  test_setup_nonzero_exit test_setup_timeout_ends_group test_setup_timer_starts_after_lock \
  test_setup_bad_config test_setup_gate_green_and_red test_setup_help \
  test_setup_signal_stops_child_and_releases_lock test_setup_timeout_kills_term_ignorer \
  test_setup_quoted_minutes_refused test_setup_logs_unique_per_run test_setup_gate_backslash_refused \
  test_setup_no_studio_dir test_setup_poll_keeps_budget test_setup_poll_rejects_bad_value \
  test_setup_run_config_reaches_story_worktree test_setup_fresh_story_worktree_runs_setup test_setup_resolution_order \
  test_setup_unset_in_and_out_of_run_silent test_setup_run_config_unresolved_fails_loud test_setup_seed_rules
