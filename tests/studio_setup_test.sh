#!/bin/sh
# Suite for studios/game-dev/bin/studio-setup (#35 AC19, AC20): the project
# hooks under the gate lock. Offline; temp repos; a temp HOME.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
SETUP="$REPO_ROOT/studios/game-dev/bin/studio-setup"
GATE="$REPO_ROOT/studios/game-dev/bin/studio-gate"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
unset STUDIO_GATE_HELD STUDIO_SETUP_TIMEOUT_SECONDS STUDIO_UNIT_TAG

# proj NAME CONFIG_JSON — $P: a committed studio project with that config.
proj() {
  P="$TMP/$1"; rm -rf "$P"; mkdir -p "$P"
  ( cd "$P" && git init -q -b main && sh "$STATE_BIN" init >/dev/null
    printf '%s\n' "$2" > .studio/config.json
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m init ) >/dev/null 2>&1
}
# setup DIR [ARGS] — studio-setup in DIR: SU_STATUS, $TMP/su.out, $TMP/su.err.
setup() { _d="$1"; shift; SU_STATUS=0; ( cd "$_d" && sh "$SETUP" "$@" ) > "$TMP/su.out" 2> "$TMP/su.err" || SU_STATUS=$?; }

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
  assert_contains "$P/.studio/gate.times" ' setup [0-9][0-9]* 0$' "gate.times has the setup line"
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
  proj to '{ "worktree_setup": "sleep 4801 & sleep 4802" }'
  STUDIO_SETUP_TIMEOUT_SECONDS=2; export STUDIO_SETUP_TIMEOUT_SECONDS
  setup "$P"; unset STUDIO_SETUP_TIMEOUT_SECONDS
  assert_eq 1 "$SU_STATUS" "a timeout exits 1"
  assert_contains "$TMP/su.err" '^worktree setup failed — exit 124 — log ' "exit 124 names the timeout"
  assert_eq 1 "$(wc -l < "$TMP/su.err" | tr -d ' ')" "no job-control noise on stderr"
  sleep 1
  assert_eq 0 "$(ps -A -o args= | grep -c '^sleep 480[12]$')" "the grandchild sleeps are gone"
  assert_contains "$(ls "$P"/.studio/reports/setup-*.log)" 'timed out after 2 s' "the log says so"
  assert_missing "$P/.studio/gate.lock" "the lock is released"
}
test_setup_timer_starts_after_lock() {
  proj tl '{ "worktree_setup": "echo ran > ran.txt" }'
  ( cd "$P" && sh "$GATE" holder -- sleep 3 ) >/dev/null 2>&1 &
  _h=$!; while [ ! -f "$P/.studio/gate.lock/pid" ]; do sleep 1; done
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
  assert_contains "$P/.studio/gate.times" ' gate [0-9][0-9]* 0$' "runs as who=gate"
  proj gr '{ "gate_command": "echo FAIL one; exit 3" }'
  setup "$P" gate
  assert_eq 3 "$SU_STATUS" "red exits with the command's status"
  assert_contains "$TMP/su.err" '^gate_command exit 3 — log \.studio/reports/gate-[0-9-]*\.log$' "the red line"
}
test_setup_signal_stops_child_and_releases_lock() {
  proj sg '{ "worktree_setup": "sleep 4811" }'
  ( cd "$P" && exec sh "$SETUP" ) > "$TMP/sg.out" 2>&1 &
  _s=$!
  _i=0; while [ ! -f "$P/.studio/gate.lock/who" ] && [ "$_i" -lt 20 ]; do sleep 1; _i=$((_i + 1)); done
  sleep 1
  kill -TERM "$_s"; _rc=0; wait "$_s" || _rc=$?
  assert_eq 143 "$_rc" "TERM ends studio-setup with 128+15"
  sleep 1
  assert_eq 0 "$(ps -A -o args= | grep -c '^sleep 4811$')" "the setup command is gone"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
}
test_setup_timeout_kills_term_ignorer() {
  proj ti '{ "worktree_setup": "sh ign.sh" }'
  printf "trap '' TERM\nsleep 4821\n" > "$P/ign.sh"
  STUDIO_SETUP_TIMEOUT_SECONDS=1; export STUDIO_SETUP_TIMEOUT_SECONDS
  setup "$P"; unset STUDIO_SETUP_TIMEOUT_SECONDS
  assert_contains "$TMP/su.err" '^worktree setup failed — exit 124 — log ' "exit 124 after KILL"
  assert_eq 0 "$(ps -A -o args= | grep -c '^sleep 4821$')" "the TERM-ignoring command is gone"
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
}

run_tests test_setup_unset_is_silent test_setup_runs_under_lock_and_logs test_setup_marker_skip_and_rerun \
  test_setup_nonzero_exit test_setup_timeout_ends_group test_setup_timer_starts_after_lock \
  test_setup_bad_config test_setup_gate_green_and_red test_setup_help \
  test_setup_signal_stops_child_and_releases_lock test_setup_timeout_kills_term_ignorer \
  test_setup_quoted_minutes_refused test_setup_logs_unique_per_run test_setup_gate_backslash_refused \
  test_setup_no_studio_dir
