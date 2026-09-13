#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Every test runs in its own empty project directory.
fresh_project() {
  P="$TMP/proj-$1"
  mkdir -p "$P"
  printf '%s\n' "$P"
}

test_state_needs_init() {
  P="$(fresh_project needs)"
  assert_status 1 "get fails without .studio/" -- sh -c "cd '$P' && sh '$STATE_BIN' get stage"
  assert_status 1 "show fails without .studio/" -- sh -c "cd '$P' && sh '$STATE_BIN' show"
  assert_status 1 "set fails without .studio/" -- sh -c "cd '$P' && sh '$STATE_BIN' set stage plan"
  assert_status 1 "ledger fails without .studio/" -- sh -c "cd '$P' && sh '$STATE_BIN' ledger note"
  assert_status 1 "no subcommand is a usage error" -- sh -c "cd '$P' && sh '$STATE_BIN'"
}

test_state_init() {
  P="$(fresh_project init)"
  assert_status 0 "init succeeds in an empty project" -- sh -c "cd '$P' && sh '$STATE_BIN' init"
  assert_file "$P/.studio/STATE.md" "init creates .studio/STATE.md"
  assert_contains "$P/.studio/STATE.md" "^# Studio State" "state file has its title"
  assert_contains "$P/.studio/STATE.md" "^stage: idle" "stage starts idle"
  assert_contains "$P/.studio/STATE.md" "^spec: -" "spec starts empty"
  assert_contains "$P/.studio/STATE.md" "^plan: -" "plan starts empty"
  assert_contains "$P/.studio/STATE.md" "^task: -" "task starts empty"
  assert_contains "$P/.studio/STATE.md" "^last_playtest: -" "last_playtest starts empty"
  assert_contains "$P/.studio/STATE.md" "^milestone: prototype" "milestone starts at prototype"
  assert_contains "$P/.studio/STATE.md" "^## Ledger" "state file has a ledger section"
  assert_status 1 "init refuses to overwrite an existing state" -- sh -c "cd '$P' && sh '$STATE_BIN' init"
}

test_state_get_set() {
  P="$(fresh_project getset)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_eq "idle" "$(cd "$P" && sh "$STATE_BIN" get stage)" "get reads the stage"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get spec)" "get reads an empty value as -"
  assert_status 0 "set stage plan" -- sh -c "cd '$P' && sh '$STATE_BIN' set stage plan"
  assert_eq "plan" "$(cd "$P" && sh "$STATE_BIN" get stage)" "set changes the stage"
  assert_status 0 "set spec path" -- \
    sh -c "cd '$P' && sh '$STATE_BIN' set spec docs/game-dev/specs/2026-09-13-dash.md"
  assert_eq "docs/game-dev/specs/2026-09-13-dash.md" "$(cd "$P" && sh "$STATE_BIN" get spec)" \
    "set stores a path"
  assert_status 0 "set task n/N" -- sh -c "cd '$P' && sh '$STATE_BIN' set task 3/6"
  assert_eq "3/6" "$(cd "$P" && sh "$STATE_BIN" get task)" "set stores a task counter"
  assert_status 0 "set milestone vertical-slice" -- \
    sh -c "cd '$P' && sh '$STATE_BIN' set milestone vertical-slice"
  assert_eq "vertical-slice" "$(cd "$P" && sh "$STATE_BIN" get milestone)" "set changes the milestone"
  assert_status 0 "a value can be cleared back to -" -- sh -c "cd '$P' && sh '$STATE_BIN' set spec -"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get spec)" "cleared value reads as -"
  assert_eq "1" "$(grep -c '^stage: ' "$P/.studio/STATE.md")" "set never duplicates a field line"
}

test_state_validation() {
  P="$(fresh_project valid)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_status 1 "rejects an unknown key" -- sh -c "cd '$P' && sh '$STATE_BIN' set nope x"
  assert_status 1 "rejects an unknown key on get" -- sh -c "cd '$P' && sh '$STATE_BIN' get nope"
  assert_status 1 "rejects an unknown stage" -- sh -c "cd '$P' && sh '$STATE_BIN' set stage flying"
  assert_status 1 "rejects an unknown milestone" -- sh -c "cd '$P' && sh '$STATE_BIN' set milestone shipped"
  assert_status 1 "rejects an empty value" -- sh -c "cd '$P' && sh '$STATE_BIN' set stage"
  assert_eq "idle" "$(cd "$P" && sh "$STATE_BIN" get stage)" "a rejected set leaves the stage alone"
  assert_status 1 "rejects an unknown subcommand" -- sh -c "cd '$P' && sh '$STATE_BIN' frob"
}

test_state_ledger() {
  P="$(fresh_project ledger)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_status 0 "ledger appends" -- \
    sh -c "cd '$P' && sh '$STATE_BIN' ledger 'T3 Ruling: buffer window 0.1 s — spec said short'"
  assert_status 0 "ledger appends again" -- sh -c "cd '$P' && sh '$STATE_BIN' ledger 'T1 Review: literal moved'"
  today="$(date +%Y-%m-%d)"
  assert_contains "$P/.studio/STATE.md" "^- $today T3 Ruling: buffer window 0.1 s" "ledger line is dated"
  assert_eq "- $today T1 Review: literal moved" "$(tail -n 1 "$P/.studio/STATE.md")" \
    "ledger is append-only, newest last"
  assert_status 1 "ledger rejects empty text" -- sh -c "cd '$P' && sh '$STATE_BIN' ledger ''"
  ( cd "$P" && sh "$STATE_BIN" set stage execute >/dev/null )
  assert_eq "- $today T1 Review: literal moved" "$(tail -n 1 "$P/.studio/STATE.md")" \
    "set does not disturb the ledger"
}

test_state_show() {
  P="$(fresh_project show)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" show ) > "$TMP/show.out"
  assert_contains "$TMP/show.out" "^milestone: prototype" "show prints the file"
}

run_tests test_state_needs_init test_state_init test_state_get_set test_state_validation \
  test_state_ledger test_state_show
