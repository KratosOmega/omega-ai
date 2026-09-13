#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
# Physical path: git prints physical paths, and the tool's root resolution
# is compared against $TMP textually.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
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

# Skills quote the ledger text, but an unquoted call must not silently keep
# only the first word, and a value or text is data: a backslash sequence in a
# path must land as typed, and a newline inside ledger text must not split
# the entry into two lines (the ledger is one line per entry).
test_state_ledger_keeps_all_words() {
  P="$(fresh_project words)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  today="$(date +%Y-%m-%d)"
  assert_status 0 "ledger accepts unquoted words" -- \
    sh -c "cd '$P' && sh '$STATE_BIN' ledger T2 complete abc123..def456"
  assert_eq "- $today T2 complete abc123..def456" "$(tail -n 1 "$P/.studio/STATE.md")" \
    "unquoted multi-word text is kept whole"
}

test_state_ledger_folds_newlines() {
  P="$(fresh_project fold)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  today="$(date +%Y-%m-%d)"
  before="$(wc -l < "$P/.studio/STATE.md" | tr -d ' ')"
  ( cd "$P" && sh "$STATE_BIN" ledger "$(printf 'T3 Ruling: first line\nsecond line')" )
  assert_eq "$((before + 1))" "$(wc -l < "$P/.studio/STATE.md" | tr -d ' ')" \
    "a ledger entry with an embedded newline adds exactly one line"
  assert_eq "- $today T3 Ruling: first line second line" "$(tail -n 1 "$P/.studio/STATE.md")" \
    "the newline is folded to a space"
}

test_state_set_keeps_backslashes() {
  P="$(fresh_project backslash)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_status 0 "set accepts a value with a backslash sequence" -- \
    sh -c "cd '$P' && sh '$STATE_BIN' set spec 'docs\\nested.md'"
  assert_eq 'docs\nested.md' "$(cd "$P" && sh "$STATE_BIN" get spec)" \
    "a backslash-n in a value is stored literally, not as a newline"
  assert_eq "1" "$(grep -c '^spec: ' "$P/.studio/STATE.md")" "the header line is not split"
  assert_eq "plan: -" "$(sed -n '5p' "$P/.studio/STATE.md")" "the following header line is undisturbed"
}

test_state_show() {
  P="$(fresh_project show)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" show ) > "$TMP/show.out"
  assert_contains "$TMP/show.out" "^milestone: prototype" "show prints the file"
}

# The pointer lives in the main checkout: a linked worktree of the project
# edits the same STATE.md, so execute on a feature branch and the router in
# main see one stage. The gitignore line keeps the pointer out of commits.
test_state_resolves_to_main_checkout() {
  P="$(fresh_project wt)"
  ( cd "$P" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init ) 2>/dev/null
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && git worktree add -q "$TMP/wt-linked" -b feature ) >/dev/null 2>&1
  assert_eq "$P" "$(cd "$TMP/wt-linked" && sh "$STATE_BIN" root)" "root from a worktree is the main checkout"
  assert_eq "$TMP/wt-linked" "$(cd "$TMP/wt-linked" && sh "$STATE_BIN" root --work)" "root --work is the worktree"
  assert_eq "$P" "$(cd "$P" && sh "$STATE_BIN" root --work)" "root --work in main is main"
  assert_status 0 "set from a worktree succeeds" -- sh -c "cd '$TMP/wt-linked' && sh '$STATE_BIN' set stage execute"
  assert_eq "execute" "$(cd "$P" && sh "$STATE_BIN" get stage)" "the main checkout's STATE.md carries the change"
  assert_missing "$TMP/wt-linked/.studio/STATE.md" "the worktree holds no copy of the pointer"
  assert_contains "$P/.gitignore" "^\.studio/STATE\.md$" "init gitignores the pointer"
  P2="$(fresh_project nogit)"
  assert_eq "$P2" "$(cd "$P2" && sh "$STATE_BIN" root)" "outside git the root is the current directory"
}

test_state_init_writes_config_ledger_and_gitignore_once() {
  P="$(fresh_project gi)"
  ( cd "$P" && git init -q ) 2>/dev/null
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_file "$P/.studio/config.json" "init writes config.json"
  assert_contains "$P/.studio/config.json" '"engine": "godot4"' "config.json carries the studio defaults"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -d "$P/.studio/ledger" ]; then _pass "init creates the ledger directory"; else _fail "init creates the ledger directory"; fi
  assert_status 1 "init refuses to overwrite an existing state" -- sh -c "cd '$P' && sh '$STATE_BIN' init"
  printf '{ "engine": "godot4", "tests": "gdunit4" }\n' > "$P/.studio/config.json"
  rm "$P/.studio/STATE.md"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_eq "1" "$(grep -c '^\.studio/STATE\.md$' "$P/.gitignore")" "the gitignore line is added once"
  assert_contains "$P/.studio/config.json" "gdunit4" "an existing config.json is kept"
  P3="$(fresh_project gi-nogit)"
  ( cd "$P3" && sh "$STATE_BIN" init >/dev/null )
  assert_missing "$P3/.gitignore" "outside git no .gitignore is written"
}

# A pre-existing gitignore without a trailing newline must not run its last
# line together with the appended pointer line.
test_state_init_gitignore_appends_safely() {
  P="$(fresh_project gi-nl)"
  ( cd "$P" && git init -q ) 2>/dev/null
  printf 'node_modules' > "$P/.gitignore"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_eq "2" "$(wc -l < "$P/.gitignore" | tr -d ' ')" \
    "a missing trailing newline does not merge the two gitignore lines"
  assert_eq "1" "$(grep -c '^node_modules$' "$P/.gitignore")" \
    "the pre-existing rule survives intact"
  assert_eq "1" "$(grep -c '^\.studio/STATE\.md$' "$P/.gitignore")" \
    "the pointer line is appended on its own line"
}

# git noise (e.g. "fatal: not a git repository") must never reach stderr for
# an ordinary non-repo project, and a leaked GIT_DIR from the caller's
# environment must not make the tool believe it is inside a repository.
test_state_root_outside_git_is_quiet() {
  P="$(fresh_project quiet)"
  assert_status 0 "root exits 0 outside git" -- \
    sh -c "cd '$P' && unset GIT_DIR GIT_WORK_TREE; sh '$STATE_BIN' root"
  ( cd "$P" && unset GIT_DIR GIT_WORK_TREE; sh "$STATE_BIN" root >"$TMP/quiet.out" 2>"$TMP/quiet.err" )
  assert_eq "$P" "$(cat "$TMP/quiet.out")" "root prints the current directory outside git"
  assert_eq "0" "$(wc -c < "$TMP/quiet.err" | tr -d ' ')" "root prints no git noise to stderr outside git"
}

# set used to exit 0 and write nothing when the header line was gone, so a
# hand-edited STATE.md silently lost every later write.
test_state_set_hardening() {
  P="$(fresh_project harden)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  grep -v '^spec: ' "$P/.studio/STATE.md" > "$P/damaged" && mv "$P/damaged" "$P/.studio/STATE.md"
  status=0
  ( cd "$P" && sh "$STATE_BIN" set spec docs/x.md ) > /dev/null 2> "$P/set.err" || status=$?
  assert_eq "1" "$status" "set fails when the key's header line is absent"
  assert_contains "$P/set.err" "no 'spec:' line" "set names the missing header"

  P="$(fresh_project harden2)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" set spec "$(printf 'a\nstage: hacked')" )
  assert_eq "1" "$(grep -c '^stage: ' "$P/.studio/STATE.md")" "a newline in a value cannot inject a header line"
  assert_eq "a stage: hacked" "$(cd "$P" && sh "$STATE_BIN" get spec)" "the newline is folded to a space"
  assert_status 1 "set rejects extra arguments" -- sh -c "cd '$P' && sh '$STATE_BIN' set spec docs/my spec.md"
  assert_eq "a stage: hacked" "$(cd "$P" && sh "$STATE_BIN" get spec)" "a rejected set changes nothing"
  assert_status 1 "set task rejects a value that is not n/N" -- sh -c "cd '$P' && sh '$STATE_BIN' set task three"
  assert_status 0 "set task accepts n/N" -- sh -c "cd '$P' && sh '$STATE_BIN' set task 2/5"
  assert_status 0 "set task accepts -" -- sh -c "cd '$P' && sh '$STATE_BIN' set task -"
}

run_tests test_state_needs_init test_state_init test_state_get_set test_state_validation \
  test_state_ledger test_state_ledger_keeps_all_words test_state_ledger_folds_newlines \
  test_state_set_keeps_backslashes test_state_show test_state_resolves_to_main_checkout \
  test_state_init_writes_config_ledger_and_gitignore_once test_state_init_gitignore_appends_safely \
  test_state_root_outside_git_is_quiet \
  test_state_set_hardening
