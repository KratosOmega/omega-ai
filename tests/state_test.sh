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

# root is the main checkout from a linked worktree, but the stage pointer is
# per checkout (#42): a linked worktree's first write creates its own
# STATE.md and the main one is untouched. The gitignore line keeps the
# main pointer out of commits.
test_state_resolves_to_main_checkout() {
  P="$(fresh_project wt)"
  ( cd "$P" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init ) 2>/dev/null
  ( cd "$P" && sh "$STATE_BIN" init >/dev/null )
  ( cd "$P" && git worktree add -q "$TMP/wt-linked" -b feature ) >/dev/null 2>&1
  assert_eq "$P" "$(cd "$TMP/wt-linked" && sh "$STATE_BIN" root)" "root from a worktree is the main checkout"
  assert_eq "$TMP/wt-linked" "$(cd "$TMP/wt-linked" && sh "$STATE_BIN" root --work)" "root --work is the worktree"
  assert_eq "$P" "$(cd "$P" && sh "$STATE_BIN" root --work)" "root --work in main is main"
  _main_before="$(cat "$P/.studio/STATE.md")"
  assert_status 0 "set from a worktree succeeds" -- sh -c "cd '$TMP/wt-linked' && sh '$STATE_BIN' set stage execute"
  assert_eq "idle" "$(cd "$P" && sh "$STATE_BIN" get stage)" "the main checkout's STATE.md does not carry the change (#42 AC6)"
  assert_eq "$_main_before" "$(cat "$P/.studio/STATE.md")" "the main pointer is unchanged"
  assert_contains "$TMP/wt-linked/.studio/STATE.md" '^stage: execute$' "the worktree's write creates its own pointer"
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
  assert_eq "docs/game-dev/specs/2026-09-13-a.md" "$(cd "$P" && sh "$STATE_BIN" get spec)" "the pointer is not shared (#42 AC6)"
  assert_eq "docs/game-dev/specs/2026-09-13-b.md" "$(cd "$TMP/fb-linked" && sh "$STATE_BIN" get spec)" "the worktree reads its own spec"
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
  assert_eq "1" "$WT_STATUS" "worktree exits 1 from inside a pointer-less worktree (#42 AC3)"
  assert_eq "studio-state: no feature branch recorded" "$(cat "$TMP/wt.err")" "it has no feature branch recorded"

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

# Final fix wave: check --rebuild from task - counts only the ### Task
# headings above ## Backlog (a producer cut keeps its heading there).
test_state_story_rebuild_skips_backlog() {
  P="$TMP/story-bl"; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    printf '# P\n\n### Task 1: a\n\n### Task 2: b\n\n## Backlog\n\n### Task 3: c\n\n### Task 4: d\n' > docs/p.md
    export STUDIO_STORY=BL; sh "$STATE_BIN" init
    sh "$STATE_BIN" set plan docs/p.md; sh "$STATE_BIN" set spec docs/s.md
    sh "$STATE_BIN" ledger "T1 complete" ) >/dev/null 2>&1
  ( cd "$P" && STUDIO_STORY=BL sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq 1/2 "$(cd "$P" && STUDIO_STORY=BL sh "$STATE_BIN" get task)" "N counts only the tasks above ## Backlog"
}

# #35 AC9: T lines before the last `adopt reset` are not the truth.
test_state_check_ignores_before_adopt_reset() {
  P="$TMP/story-reset"; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    printf '# P\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md
    export STUDIO_STORY=RS; sh "$STATE_BIN" init
    sh "$STATE_BIN" set plan docs/p.md; sh "$STATE_BIN" set task 0/3
    sh "$STATE_BIN" ledger "T1 complete aaaa..bbbb"; sh "$STATE_BIN" ledger "T2 complete bbbb..cccc"
    sh "$STATE_BIN" ledger "T3 complete cccc..dddd"
    sh "$STATE_BIN" ledger "adopt reset 0123456789abcdef0123456789abcdef01234567"
    sh "$STATE_BIN" ledger "T1 complete eeee..ffff" ) >/dev/null 2>&1
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq 1/3 "$(cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" get task)" "rebuild counts only the lines after the last adopt reset"
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" set task 3/3 ) >/dev/null 2>&1
  st=0; ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" check ) > "$TMP/out" 2>&1 || st=$?
  assert_contains "$TMP/out" "note — ledger has T1 complete, task is 3/3" "plain check reads the highest T line after the reset too"
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" ledger "adopt reset 1111111111111111111111111111111111111111" ) >/dev/null 2>&1
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" set task 0/3 && STUDIO_STORY=RS sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq 0/3 "$(cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" get task)" "the last reset wins: nothing after it"
}

# #39 fixture: a project P (main checkout, studio-state init, one commit) and a
# linked run worktree RW on run/x under P/.claude/worktrees/run-x.
BIN="$REPO_ROOT/studios/game-dev/bin"
rw_fixture() {
  P="$TMP/rw-$1"; RW="$P/.claude/worktrees/run-x"; rm -rf "$P"; mkdir -p "$P"
  ( cd "$P" && git init -q -b main && sh "$STATE_BIN" init >/dev/null \
      && git add -A && git -c user.name=t -c user.email=t@t commit -qm init \
      && git worktree add -q -b run/x "$RW" ) >/dev/null 2>&1
}
test_state_root_from_run_worktree() {
  rw_fixture root
  assert_eq "$P" "$(cd "$RW" && sh "$STATE_BIN" root)" "root is the main checkout from a run worktree"
  assert_eq "$RW" "$(cd "$RW" && sh "$STATE_BIN" root --work)" "--work is the run worktree"
}
test_state_init_local_creates_pointer() {
  rw_fixture local
  ( cd "$RW" && sh "$STATE_BIN" init --local ) > "$TMP/out" 2>&1
  assert_file "$RW/.studio/STATE.md" "the local pointer exists"
  assert_contains "$RW/.studio/STATE.md" '^stage: idle$' "stage idle"
  assert_contains "$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude" '^\.studio/STATE\.md$' "kept out of git (D41)"
  assert_eq "" "$(git -C "$RW" status --porcelain)" "no untracked noise"
  assert_not_contains "$RW/.studio/STATE.md" '^milestone:' "a local pointer has no milestone line (#42 AC10)"
}
test_state_init_local_refusals() {
  rw_fixture refuse
  st=0; ( cd "$P" && sh "$STATE_BIN" init --local ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "refused in the main checkout"
  assert_contains "$TMP/out" "init --local: the main checkout" "says why"
  ( cd "$RW" && sh "$STATE_BIN" init --local ) >/dev/null 2>&1
  st=0; ( cd "$RW" && sh "$STATE_BIN" init --local ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "refused when the checkout already has one"
}
test_state_local_pointer_auto_created() {
  rw_fixture present
  ( cd "$RW" && sh "$STATE_BIN" set stage brainstorm ) >/dev/null 2>&1
  assert_contains "$RW/.studio/STATE.md" '^stage: brainstorm$' "no local pointer: RW's write creates RW's pointer (#42 AC6)"
  assert_contains "$P/.studio/STATE.md" '^stage: idle$' "P stays idle"
  rm -f "$RW/.studio/STATE.md"
  ( cd "$RW" && sh "$STATE_BIN" init --local && sh "$STATE_BIN" set stage plan ) >/dev/null 2>&1
  assert_contains "$RW/.studio/STATE.md" '^stage: plan$' "with one: the local pointer"
  assert_eq idle "$(cd "$P" && sh "$STATE_BIN" get stage)" "the main checkout reads its own"
  rm -f "$RW/.studio/STATE.md"
  ( cd "$P" && sh "$STATE_BIN" set stage execute ) >/dev/null 2>&1
  assert_eq idle "$(cd "$RW" && sh "$STATE_BIN" get stage)" "pointer removed: reads idle again, not the root's STATE.md"
}
test_state_run_worktree_leaves_main_state() {
  rw_fixture untouched
  _before="$(cat "$P/.studio/STATE.md")"
  ( cd "$RW" && sh "$STATE_BIN" init --local && sh "$STATE_BIN" set stage brainstorm \
      && sh "$STATE_BIN" set spec docs/s.md && sh "$STATE_BIN" ledger "spec approved docs/s.md" ) >/dev/null 2>&1
  assert_eq "$_before" "$(cat "$P/.studio/STATE.md")" "stage writes in a run worktree leave the main STATE.md"
}
test_state_story_state_stays_at_root() {
  rw_fixture story
  ( cd "$RW" && sh "$STATE_BIN" init --local && STUDIO_STORY=S1 sh "$STATE_BIN" init \
      && STUDIO_STORY=S1 sh "$STATE_BIN" set task 1/3 ) >/dev/null 2>&1
  assert_contains "$P/.studio/stories/S1.md" '^task: 1/3$' "STUDIO_STORY state is at <root>"
  assert_missing "$RW/.studio/stories" "never in the run worktree"
}
test_state_gate_lock_from_run_worktree() {
  rw_fixture gate
  ( cd "$RW" && sh "$BIN/studio-gate" studio-test -- sh -c "test -d '$P/.studio/gate.lock' && echo held" ) > "$TMP/out" 2>&1
  assert_contains "$TMP/out" '^held$' "studio-gate locks <main>/.studio/gate.lock from a run worktree"
  assert_missing "$RW/.studio/gate.lock" "and nothing in the run worktree"
}

test_state_rebuild_refuses_unseeded_adopted() {
  P="$TMP/story-ad"; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    sh "$STATE_BIN" init
    printf '# P\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md
    export STUDIO_STORY=AD; sh "$STATE_BIN" init
    sh "$STATE_BIN" set plan docs/p.md; sh "$STATE_BIN" set task 0/3; sh "$STATE_BIN" set branch AD-b
    sh "$STATE_BIN" ledger "adopted docs/o.md -> docs/p.md"
    git worktree add -q -b AD-b "$TMP/story-ad-wt" ) >/dev/null 2>&1
  W="$TMP/story-ad-wt"
  st=0; ( cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "unseeded adopted story: check --rebuild exits 1"
  assert_contains "$TMP/out" "AD is adopted ($P/.studio/ledger/AD.md) but $W/.studio/ledger/AD.md has no adopt-base line" "names both ledgers"
  assert_contains "$TMP/out" "studio-adopt seed AD" "and the fix"
  assert_eq 0/3 "$(cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" get task)" "task untouched"
  st=0; ( cd "$P" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "from the checkout holding the adopted line too"
  ( cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" ledger "adopt-base 0123456789abcdef0123456789abcdef01234567" \
      && STUDIO_STORY=AD sh "$STATE_BIN" ledger "T1 complete aaaa..bbbb" ) >/dev/null 2>&1
  st=0; ( cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 0 "$st" "seeded (adopt-base): the rebuild runs"
  assert_eq 1/3 "$(cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" get task)" "and counts the seeded tasks"
  ( cd "$P" && STUDIO_STORY=AD sh "$STATE_BIN" set task 0/3 && STUDIO_STORY=AD sh "$STATE_BIN" set branch - ) >/dev/null 2>&1
  st=0; ( cd "$P" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 0 "$st" "a not-started adopted story (branch -) rebuilds as before"
}

run_tests test_state_rebuild_refuses_unseeded_adopted test_state_check_ignores_before_adopt_reset test_state_needs_init test_state_init test_state_get_set test_state_validation \
  test_state_ledger test_state_ledger_keeps_all_words test_state_ledger_folds_newlines \
  test_state_set_keeps_backslashes test_state_show test_state_resolves_to_main_checkout \
  test_state_init_writes_config_ledger_and_gitignore_once test_state_init_gitignore_appends_safely \
  test_state_root_outside_git_is_quiet \
  test_state_set_hardening \
  test_state_feature_ledger test_state_ledger_per_branch test_state_check test_state_reset \
  test_state_stage_list test_state_legacy_file test_state_branch_key \
  test_state_branch_insert_is_literal test_state_worktree test_state_worktree_edges \
  test_state_story_init_and_isolation test_state_story_rebuild test_state_story_gap_from_k_of_n test_state_story_rebuild_skips_backlog \
  test_state_root_from_run_worktree test_state_init_local_creates_pointer test_state_init_local_refusals \
  test_state_local_pointer_auto_created test_state_run_worktree_leaves_main_state \
  test_state_story_state_stays_at_root test_state_gate_lock_from_run_worktree
