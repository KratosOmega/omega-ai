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

# init_repo DIR — a git repository with one empty commit and studio state.
init_repo() {
  mkdir -p "$1"
  ( cd "$1" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init ) >/dev/null 2>&1
  ( cd "$1" && sh "$STATE_BIN" init >/dev/null )
}

# wt_run DIR — `studio-state worktree` from DIR: stdout in $TMP/wt.out,
# stderr in $TMP/wt.err, its second line in $TMP/wt.cmd, status in WT_STATUS.
wt_run() {
  WT_STATUS=0
  ( cd "$1" && sh "$STATE_BIN" worktree ) > "$TMP/wt.out" 2> "$TMP/wt.err" || WT_STATUS=$?
  sed -n 2p "$TMP/wt.err" > "$TMP/wt.cmd"
}

# legacy_state DIR STAGE — a STATE.md from before this change: STAGE as the
# stage, the inert last_playtest line, no branch line.
legacy_state() {
  mkdir -p "$1/.studio/ledger"
  printf '# Studio State\n\nstage: %s\nspec: -\nplan: -\ntask: 8/8\nlast_playtest: docs/x.md\nmilestone: prototype\n\n## Ledger\n\n' \
    "$2" > "$1/.studio/STATE.md"
}

# drop_line FILE PATTERN — remove the lines matching PATTERN, the way a
# damaged or pre-change STATE.md lacks them.
drop_line() {
  grep -v -- "$2" "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
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
  assert_not_contains "$P/.studio/STATE.md" "^last_playtest:" "init writes no last_playtest line"
  assert_contains "$P/.studio/STATE.md" "^branch: -" "branch starts empty"
  assert_eq "branch: -" "$(sed -n '/^task: /{n;p;}' "$P/.studio/STATE.md")" "branch sits right after task"
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

# Rulings belong to the feature, not to a single slot edited on every
# branch: one ledger file per spec, committed with the feature's branch.
test_state_feature_ledger() {
  P="$(fresh_project fl)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  today="$(date +%Y-%m-%d)"
  ( cd "$P" && sh "$STATE_BIN" ledger "idle note" )
  assert_contains "$P/.studio/STATE.md" "^- $today idle note" "with no spec the ledger line goes to STATE.md"
  ( cd "$P" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-player-dash.md )
  ( cd "$P" && sh "$STATE_BIN" ledger "spec written docs/game-dev/specs/2026-09-13-player-dash.md" )
  assert_file "$P/.studio/ledger/player-dash.md" "with a spec the ledger line goes to the feature file"
  assert_contains "$P/.studio/ledger/player-dash.md" "^- $today spec written" "the feature ledger line is dated"
  assert_contains "$P/.studio/ledger/player-dash.md" "^# Ledger — player-dash" "the feature ledger has a title"
  assert_not_contains "$P/.studio/STATE.md" "spec written" "STATE.md does not carry feature lines"
  ( cd "$P" && sh "$STATE_BIN" show ) > "$TMP/fl-show.out"
  assert_contains "$TMP/fl-show.out" "^stage: idle" "show prints the pointer"
  assert_contains "$TMP/fl-show.out" "^## Feature ledger: player-dash" "show names the feature ledger"
  assert_contains "$TMP/fl-show.out" "spec written" "show prints the feature ledger"
}

test_state_ledger_per_branch() {
  P="$(fresh_project fb)"
  ( cd "$P" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init ) 2>/dev/null
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-a.md && sh "$STATE_BIN" ledger "A1" )
  ( cd "$P" && git worktree add -q "$TMP/fb-linked" -b b ) >/dev/null 2>&1
  ( cd "$TMP/fb-linked" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-b.md && sh "$STATE_BIN" ledger "B1" )
  assert_file "$P/.studio/ledger/a.md" "feature a's ledger is in the main checkout"
  assert_file "$TMP/fb-linked/.studio/ledger/b.md" "feature b's ledger is in the worktree"
  assert_missing "$P/.studio/ledger/b.md" "feature b's ledger is not in the main checkout"
  assert_eq "docs/game-dev/specs/2026-09-13-b.md" "$(cd "$P" && sh "$STATE_BIN" get spec)" "the pointer is shared"
}

test_state_check() {
  P="$(fresh_project chk)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  assert_status 0 "check passes on a fresh state" -- sh -c "cd '$P' && sh '$STATE_BIN' check"
  ( cd "$P" && sh "$STATE_BIN" set spec docs/game-dev/specs/2026-09-13-dash.md )
  status=0
  ( cd "$P" && sh "$STATE_BIN" check ) > "$TMP/chk.out" 2>&1 || status=$?
  assert_eq "1" "$status" "check fails when the spec file is missing"
  assert_contains "$TMP/chk.out" "spec file missing: docs/game-dev/specs/2026-09-13-dash.md" "check names the missing spec"
  mkdir -p "$P/docs/game-dev/specs" "$P/docs/game-dev/plans"
  printf '# spec\n' > "$P/docs/game-dev/specs/2026-09-13-dash.md"
  printf '# plan\n' > "$P/docs/game-dev/plans/2026-09-13-dash.md"
  ( cd "$P" && sh "$STATE_BIN" set plan docs/game-dev/plans/2026-09-13-dash.md && sh "$STATE_BIN" set task 2/5 )
  assert_status 0 "check passes with files present and no ledger" -- sh -c "cd '$P' && sh '$STATE_BIN' check"
  ( cd "$P" && sh "$STATE_BIN" ledger "T1 complete abc..def" && sh "$STATE_BIN" ledger "T3 complete def..fed" )
  status=0
  ( cd "$P" && sh "$STATE_BIN" check ) > "$TMP/chk2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "check fails when the ledger is ahead of task"
  assert_contains "$TMP/chk2.out" "ledger says T3 complete but task is 2/5" "check explains the mismatch"
  assert_status 0 "check --rebuild succeeds" -- sh -c "cd '$P' && sh '$STATE_BIN' check --rebuild"
  assert_eq "3/5" "$(cd "$P" && sh "$STATE_BIN" get task)" "check --rebuild sets task from the ledger"
  assert_status 1 "check --rebuild rejects a trailing word" -- sh -c "cd '$P' && sh '$STATE_BIN' check --rebuild garbage"
  ( cd "$P" && sh "$STATE_BIN" set task 4/5 )
  ( cd "$P" && sh "$STATE_BIN" check ) > "$TMP/chk3.out" 2>&1
  assert_contains "$TMP/chk3.out" "note" "a ledger behind task is a note, not a failure"
  ( cd "$P" && sh "$STATE_BIN" set task 6/5 )
  assert_status 1 "check fails when n > N" -- sh -c "cd '$P' && sh '$STATE_BIN' check"
}

test_state_reset() {
  P="$(fresh_project rst)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && sh "$STATE_BIN" set stage plan && sh "$STATE_BIN" set spec docs/s/2026-09-13-dash.md \
      && sh "$STATE_BIN" set plan docs/p/2026-09-13-dash.md && sh "$STATE_BIN" set task 1/3 \
      && sh "$STATE_BIN" ledger "T1 complete x" )
  assert_file "$P/.studio/ledger/dash.md" "the feature ledger exists before reset"
  assert_status 0 "reset succeeds" -- sh -c "cd '$P' && sh '$STATE_BIN' reset"
  assert_eq "idle" "$(cd "$P" && sh "$STATE_BIN" get stage)" "reset returns to idle"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get spec)" "reset clears spec"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get plan)" "reset clears plan"
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get task)" "reset clears task"
  assert_missing "$P/.studio/ledger/dash.md" "reset removes the feature ledger"
  assert_contains "$P/.studio/STATE.md" "abandoned docs/s/2026-09-13-dash.md" "reset records the abandoned spec"
  ( cd "$P" && sh "$STATE_BIN" set spec docs/s/2026-09-13-keep.md && sh "$STATE_BIN" ledger "K1" )
  ( cd "$P" && sh "$STATE_BIN" reset --keep-ledger )
  assert_file "$P/.studio/ledger/keep.md" "reset --keep-ledger keeps the feature ledger"
  ( cd "$P" && sh "$STATE_BIN" set spec docs/s/2026-09-13-guard.md && sh "$STATE_BIN" ledger "G1" )
  assert_status 1 "reset --keep-ledger rejects a trailing word" -- \
    sh -c "cd '$P' && sh '$STATE_BIN' reset --keep-ledger garbage"
  assert_eq "docs/s/2026-09-13-guard.md" "$(cd "$P" && sh "$STATE_BIN" get spec)" \
    "a rejected reset --keep-ledger leaves the pointer untouched"
  assert_file "$P/.studio/ledger/guard.md" "a rejected reset --keep-ledger leaves the feature ledger untouched"
  assert_status 1 "reset rejects an unknown flag" -- sh -c "cd '$P' && sh '$STATE_BIN' reset --nope"
}

test_state_stage_list() {
  P="$(fresh_project stages)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  for s in idle brainstorm plan execute; do
    assert_status 0 "set stage accepts $s" -- sh -c "cd '$P' && sh '$STATE_BIN' set stage $s"
  done
  # Removed stages come from the loop variable (the deleted name split), so
  # test_no_ship_references never matches this file's own lines.
  for s in review playtest 'sh''ip' retro; do
    status=0
    ( cd "$P" && sh "$STATE_BIN" set stage "$s" ) > /dev/null 2> "$P/stage.err" || status=$?
    assert_eq "1" "$status" "set stage rejects the removed stage $s"
    assert_contains "$P/stage.err" "stage must be one of: idle brainstorm plan execute" "the error lists the four stages ($s)"
  done
  assert_eq "execute" "$(cd "$P" && sh "$STATE_BIN" get stage)" "a rejected stage leaves the last accepted one"
  assert_status 1 "get last_playtest is an unknown key" -- sh -c "cd '$P' && sh '$STATE_BIN' get last_playtest"
  assert_status 1 "set last_playtest is an unknown key" -- sh -c "cd '$P' && sh '$STATE_BIN' set last_playtest x"
}

test_state_legacy_file() {
  P="$(fresh_project legacy)"
  legacy_state "$P" retro
  assert_eq "retro" "$(cd "$P" && sh "$STATE_BIN" get stage)" "get stage returns an old value unchanged"
  assert_eq "" "$(cd "$P" && sh "$STATE_BIN" get branch)" "get branch prints nothing without the line"
  assert_status 1 "worktree exits 1 without a branch line" -- sh -c "cd '$P' && sh '$STATE_BIN' worktree"
  mkdir -p "$P/docs" && printf '# spec\n' > "$P/docs/2026-09-01-dash.md"
  assert_status 0 "set spec works on a legacy file" -- sh -c "cd '$P' && sh '$STATE_BIN' set spec docs/2026-09-01-dash.md"
  assert_status 0 "set task works on a legacy file" -- sh -c "cd '$P' && sh '$STATE_BIN' set task 2/8"
  assert_status 0 "ledger works on a legacy file" -- sh -c "cd '$P' && sh '$STATE_BIN' ledger 'T1 complete a..b'"
  assert_status 0 "check works on a legacy file" -- sh -c "cd '$P' && sh '$STATE_BIN' check"
  assert_contains "$P/.studio/STATE.md" "^last_playtest: docs/x.md" "the inert last_playtest line survives"
  assert_status 0 "set stage idle replaces an old value" -- sh -c "cd '$P' && sh '$STATE_BIN' set stage idle"
  assert_eq "idle" "$(cd "$P" && sh "$STATE_BIN" get stage)" "the old value is gone"
}

test_state_branch_key() {
  P="$(fresh_project branch)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null && sh "$STATE_BIN" set branch feat/x )
  assert_eq "feat/x" "$(cd "$P" && sh "$STATE_BIN" get branch)" "set branch round-trips"
  ( cd "$P" && sh "$STATE_BIN" reset >/dev/null )
  assert_eq "-" "$(cd "$P" && sh "$STATE_BIN" get branch)" "reset clears branch"

  P="$(fresh_project branch-missing)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  drop_line "$P/.studio/STATE.md" '^branch: '
  assert_status 0 "set branch inserts a missing line" -- sh -c "cd '$P' && sh '$STATE_BIN' set branch feat/x"
  assert_eq "branch: feat/x" "$(sed -n '/^task: /{n;p;}' "$P/.studio/STATE.md")" "the line lands right after task"
  assert_eq "1" "$(grep -c '^branch: ' "$P/.studio/STATE.md")" "exactly one branch line"

  P="$(fresh_project branch-reset)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  drop_line "$P/.studio/STATE.md" '^branch: '
  assert_status 0 "reset inserts a missing branch line" -- sh -c "cd '$P' && sh '$STATE_BIN' reset"
  assert_eq "branch: -" "$(sed -n '/^task: /{n;p;}' "$P/.studio/STATE.md")" "reset leaves branch: - after task"

  P="$(fresh_project branch-damaged)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  drop_line "$P/.studio/STATE.md" '^branch: '
  drop_line "$P/.studio/STATE.md" '^task: '
  status=0
  ( cd "$P" && sh "$STATE_BIN" set branch feat/x ) > /dev/null 2> "$P/set.err" || status=$?
  assert_eq "1" "$status" "set branch fails without a task line either"
  assert_contains "$P/set.err" "no 'task:' line" "the error names task:"
}

# Review focus 5: the insert path stores a value literally — '&' and '\1'
# are replacement metacharacters to sed.
test_state_branch_insert_is_literal() {
  P="$(fresh_project branch-meta)"
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  drop_line "$P/.studio/STATE.md" '^branch: '
  ( cd "$P" && sh "$STATE_BIN" set branch 'feat/a&b\1' )
  assert_eq 'feat/a&b\1' "$(cd "$P" && sh "$STATE_BIN" get branch)" "an inserted value keeps & and \\1"
}

test_state_worktree() {
  P="$(fresh_project wtree)"
  init_repo "$P"
  wt_run "$P"
  assert_eq "1" "$WT_STATUS" "worktree exits 1 when branch is -"
  assert_eq "" "$(cat "$TMP/wt.out")" "stdout is empty when branch is -"
  assert_eq "studio-state: no feature branch recorded" "$(cat "$TMP/wt.err")" "stderr says no branch is recorded"

  ( cd "$P" && sh "$STATE_BIN" set branch nope )
  wt_run "$P"
  assert_eq "1" "$WT_STATUS" "worktree exits 1 when the branch does not exist"
  assert_eq "" "$(cat "$TMP/wt.out")" "stdout is empty when the branch does not exist"
  assert_eq "studio-state: branch nope no longer exists" "$(cat "$TMP/wt.err")" "stderr names the missing branch"

  ( cd "$P" && git worktree add -q "$TMP/wt-f" -b feat/f ) >/dev/null 2>&1
  WT_F="$(cd "$TMP/wt-f" && pwd -P)"
  ( cd "$P" && sh "$STATE_BIN" set branch feat/f )
  wt_run "$P"
  assert_eq "0" "$WT_STATUS" "worktree exits 0 from the main checkout"
  assert_eq "$WT_F" "$(cat "$TMP/wt.out")" "stdout is the worktree's physical path"
  wt_run "$TMP/wt-f"
  assert_eq "0" "$WT_STATUS" "worktree exits 0 from inside the worktree"
  assert_eq "$WT_F" "$(cat "$TMP/wt.out")" "the same path from inside the worktree"

  ( cd "$P" && git branch feat/g ) >/dev/null 2>&1
  ( cd "$P" && sh "$STATE_BIN" set branch feat/g )
  wt_run "$P"
  assert_eq "3" "$WT_STATUS" "worktree exits 3 when no worktree has the branch"
  assert_eq "" "$(cat "$TMP/wt.out")" "stdout is empty at exit 3"
  assert_eq "2" "$(wc -l < "$TMP/wt.err" | tr -d ' ')" "stderr is exactly two lines"
  assert_eq "studio-state: no worktree has feat/g checked out" "$(sed -n 1p "$TMP/wt.err")" "line 1 names the branch"
  assert_contains "$TMP/wt.cmd" "^git worktree add" "line 2 is the git worktree add command"
  assert_contains "$TMP/wt.cmd" ".claude/worktrees/feat-g" "line 2 targets .claude/worktrees/<branch with - for />"
  assert_contains "$TMP/wt.cmd" "feat/g" "line 2 names the branch"
  ( cd "$P" && sh -c "$(cat "$TMP/wt.cmd")" ) >/dev/null 2>&1
  wt_run "$P"
  assert_eq "0" "$WT_STATUS" "after the printed command, worktree exits 0"
  assert_eq "$P/.claude/worktrees/feat-g" "$(cat "$TMP/wt.out")" "stdout is the new worktree"

  rm -rf "$TMP/wt-f"
  ( cd "$P" && sh "$STATE_BIN" set branch feat/f )
  wt_run "$P"
  assert_eq "3" "$WT_STATUS" "a worktree directory removed by hand (prunable entry) exits 3"
  assert_eq "" "$(cat "$TMP/wt.out")" "stdout is empty for a prunable entry"
  assert_contains "$TMP/wt.cmd" "^git worktree prune && git worktree add" "line 2 prunes the stale entry first"
  ( cd "$P" && sh -c "$(cat "$TMP/wt.cmd")" ) >/dev/null 2>&1
  wt_run "$P"
  assert_eq "0" "$WT_STATUS" "the printed prune-and-add command works"

  ( cd "$P" && git worktree add -q "$TMP/wt-h" -b feat/h && git worktree lock "$TMP/wt-h" ) >/dev/null 2>&1
  rm -rf "$TMP/wt-h"
  ( cd "$P" && sh "$STATE_BIN" set branch feat/h )
  wt_run "$P"
  assert_eq "3" "$WT_STATUS" "a locked worktree whose directory is gone exits 3"
  assert_eq "" "$(cat "$TMP/wt.out")" "stdout is empty for a locked entry"
  assert_contains "$TMP/wt.cmd" "^git worktree unlock" "line 2 unlocks the locked entry first"
  assert_contains "$TMP/wt.cmd" "&& git worktree prune && git worktree add" "then prunes, then adds"
  ( cd "$P" && sh -c "$(cat "$TMP/wt.cmd")" ) >/dev/null 2>&1
  wt_run "$P"
  assert_eq "0" "$WT_STATUS" "the printed unlock-prune-add command works"
}

# Review focus 1, 2 and 4: a branch whose name prefixes another, a branch
# checked out in the main checkout, and a main checkout path with a space.
test_state_worktree_edges() {
  P="$(fresh_project wtedge)"
  init_repo "$P"
  ( cd "$P" && git branch feat/p && git worktree add -q "$TMP/wt-p2" -b feat/p-2 ) >/dev/null 2>&1
  ( cd "$P" && sh "$STATE_BIN" set branch feat/p )
  wt_run "$P"
  assert_eq "3" "$WT_STATUS" "a worktree for feat/p-2 is not one for feat/p"
  ( cd "$P" && sh "$STATE_BIN" set branch feat/p-2 )
  wt_run "$P"
  assert_eq "$(cd "$TMP/wt-p2" && pwd -P)" "$(cat "$TMP/wt.out")" "feat/p-2 finds its own worktree"

  ( cd "$P" && git switch -q feat/p ) >/dev/null 2>&1
  ( cd "$P" && sh "$STATE_BIN" set branch feat/p )
  wt_run "$P"
  assert_eq "0" "$WT_STATUS" "a branch checked out in the main checkout is found"
  assert_eq "$P" "$(cat "$TMP/wt.out")" "stdout is the main checkout"

  P="$TMP/with space/proj"
  init_repo "$P"
  ( cd "$P" && git branch feat/s ) >/dev/null 2>&1
  ( cd "$P" && sh "$STATE_BIN" set branch feat/s )
  wt_run "$P"
  assert_eq "3" "$WT_STATUS" "exit 3 under a main checkout path with a space"
  ( cd "$P" && sh -c "$(cat "$TMP/wt.cmd")" ) >/dev/null 2>&1
  wt_run "$P"
  assert_eq "0" "$WT_STATUS" "the printed command runs despite the space"
  assert_eq "$P/.claude/worktrees/feat-s" "$(cat "$TMP/wt.out")" "stdout is the path, unquoted"
}

test_state_story_init_and_isolation() {
  P="$TMP/story-iso"; mkdir -p "$P"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    sh "$STATE_BIN" init >/dev/null ) >/dev/null 2>&1
  cp "$P/.studio/STATE.md" "$TMP/state-before.md"
  ( cd "$P" && STUDIO_STORY=A sh "$STATE_BIN" init ) >/dev/null 2>&1
  assert_file "$P/.studio/stories/A.md" "init under STUDIO_STORY creates the story file"
  assert_eq 1 "$(grep -c '^\.studio/stories/$' "$P/.git/info/exclude")" "stories/ excluded once"
  ( cd "$P" && STUDIO_STORY=A sh "$STATE_BIN" init ) >/dev/null 2>&1
  assert_eq 1 "$(grep -c '^\.studio/stories/$' "$P/.git/info/exclude")" "a second init adds no second line"
  ( cd "$P" && STUDIO_STORY=B sh "$STATE_BIN" init ) >/dev/null 2>&1
  ( cd "$P" && STUDIO_STORY=A sh "$STATE_BIN" set stage plan
              STUDIO_STORY=B sh "$STATE_BIN" set stage execute
              STUDIO_STORY=A sh "$STATE_BIN" set spec docs/s.md
              STUDIO_STORY=A sh "$STATE_BIN" ledger "plan approved docs/a.md"
              STUDIO_STORY=B sh "$STATE_BIN" set spec docs/s.md
              STUDIO_STORY=B sh "$STATE_BIN" ledger "plan approved docs/b.md" ) >/dev/null 2>&1
  assert_eq plan "$(cd "$P" && STUDIO_STORY=A sh "$STATE_BIN" get stage)" "A keeps its stage"
  assert_eq execute "$(cd "$P" && STUDIO_STORY=B sh "$STATE_BIN" get stage)" "B keeps its stage"
  assert_contains "$P/.studio/ledger/A.md" "plan approved docs/a.md" "A's ledger is keyed by story id"
  assert_not_contains "$P/.studio/ledger/A.md" "docs/b.md" "B's line never reaches A's ledger"
  assert_missing "$P/.studio/ledger/s.md" "no spec-slug ledger under STUDIO_STORY"
  assert_eq "" "$(diff "$TMP/state-before.md" "$P/.studio/STATE.md")" "STATE.md untouched by story verbs"
  assert_status 1 "a missing story file is refused" -- sh -c "cd '$P' && STUDIO_STORY=C sh '$STATE_BIN' get stage"
  ( cd "$P" && STUDIO_STORY=C sh "$STATE_BIN" get stage ) 2> "$TMP/err" || true
  assert_contains "$TMP/err" "no story C" "the refusal names the story"
  assert_status 1 "a bad id is refused" -- sh -c "cd '$P' && STUDIO_STORY='a/b' sh '$STATE_BIN' get stage"
  assert_eq idle "$(cd "$P" && STUDIO_STORY= sh "$STATE_BIN" get stage)" "empty STUDIO_STORY is today's path"
}

test_state_story_rebuild() {
  P="$TMP/story-rb"; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    sh "$STATE_BIN" init
    printf '# P\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md
    export STUDIO_STORY=R; sh "$STATE_BIN" init
    sh "$STATE_BIN" set plan docs/p.md; sh "$STATE_BIN" set spec docs/s.md
    sh "$STATE_BIN" ledger "T1 complete"; sh "$STATE_BIN" ledger "T2 complete" ) >/dev/null 2>&1
  ( cd "$P" && STUDIO_STORY=R sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq 2/3 "$(cd "$P" && STUDIO_STORY=R sh "$STATE_BIN" get task)" "from task -: 0/N, then the contiguous run"
  ( cd "$P" && STUDIO_STORY=R sh "$STATE_BIN" set task - && STUDIO_STORY=R sh "$STATE_BIN" ledger "T4 complete" ) >/dev/null 2>&1
  printf '\n### Task 4: d\n' >> "$P/docs/p.md"
  ( cd "$P" && STUDIO_STORY=R sh "$STATE_BIN" ledger "T1 complete" ) >/dev/null 2>&1
  st=0; ( cd "$P" && STUDIO_STORY=R sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "a gap exits 1"
  assert_contains "$TMP/out" "ledger gap: T3 missing" "the gap is named"
  assert_eq 0/4 "$(cd "$P" && STUDIO_STORY=R sh "$STATE_BIN" get task)" "nothing past 0/N on a gap"
}

test_state_story_gap_from_k_of_n() {
  P="$TMP/story-gap"; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    printf '# P\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md
    export STUDIO_STORY=G; sh "$STATE_BIN" init
    sh "$STATE_BIN" set plan docs/p.md; sh "$STATE_BIN" set task 1/3
    sh "$STATE_BIN" ledger "T1 complete"; sh "$STATE_BIN" ledger "T3 complete" ) >/dev/null 2>&1
  st=0; ( cd "$P" && STUDIO_STORY=G sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "D15: a gap from k/N exits 1"
  assert_contains "$TMP/out" "ledger gap: T2 missing" "D15: the gap is named from k/N"
}

run_tests test_state_needs_init test_state_init test_state_get_set test_state_validation \
  test_state_ledger test_state_ledger_keeps_all_words test_state_ledger_folds_newlines \
  test_state_set_keeps_backslashes test_state_show test_state_resolves_to_main_checkout \
  test_state_init_writes_config_ledger_and_gitignore_once test_state_init_gitignore_appends_safely \
  test_state_root_outside_git_is_quiet \
  test_state_set_hardening \
  test_state_feature_ledger test_state_ledger_per_branch test_state_check test_state_reset \
  test_state_stage_list test_state_legacy_file test_state_branch_key \
  test_state_branch_insert_is_literal test_state_worktree test_state_worktree_edges \
  test_state_story_init_and_isolation test_state_story_rebuild test_state_story_gap_from_k_of_n
