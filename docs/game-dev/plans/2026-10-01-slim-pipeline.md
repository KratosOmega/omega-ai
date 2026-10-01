# game-dev Slim Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the game-dev studio's stage chain to `idle → brainstorm → plan →
execute → idle`. Execute gets B2 fix rounds, a standalone final review on Opus,
and a finish that opens a ready PR. `review`, `playtest` and `retro` become
on-demand commands that never change `stage`. The `ship` stage is deleted. A
`UserPromptSubmit` hook warns when a session that already ran one stage is
used to start another.

**Architecture:** `studio-state` gets a `branch` key, a four-value stage list
and a `worktree` subcommand. Every skill that has to find the feature's
checkout uses that subcommand. A new self-contained hook, `stage-guard.sh`,
reads the session transcript and prints at most one `systemMessage`; it exits
0 on every path. The remaining changes are Markdown rewrites of the stage
skills, the router, the bootstrap and two agents. Each rewrite is pinned by a
text-contract test in `tests/studio_test.sh`.

**Tech Stack:** POSIX sh, bash tests, Markdown skills/agents, Claude Code hooks JSON

**Spec:** `docs/game-dev/specs/2026-10-01-slim-pipeline-design.md`

Open questions 1, 3 and 6 were ruled as recommended. Questions 2, 4 and 5
were approved as drafted (spec 1449-1493).

**Review policy (user CLAUDE.md):**
- Risky tasks (marked **Risk: risky**) each get a per-task review on Opus.
- Mechanical tasks fold into the final review.
- Minor findings are batched into the final fix wave.
- Fix rounds go to a fresh fixer, never to the finished implementer.
- Re-review only after a Critical, 3+ Importants or a production-bug fix.
  There is never a third pass.

## Global Constraints

Lines quoted from the spec carry their line numbers. The last two lines are
rules this plan adds, marked as such.

- (spec 42-43) "It removes no gate. The spec and plan approvals stay (until bundle 3's falsifier), the per-task review stays, the tests and `Verify:` rules stay."
- (spec 44) "It never merges. Execute opens a PR; the user plays the list and merges."
- (spec 45-47) "It changes nothing outside the game-dev studio's own load path: `studios/game-dev`, `shared/omega` (loaded only by `claude-gd`), `tests/` and `docs/`. Nothing under `~/.claude` is read or written."
- (spec 98-99) "`studios/game-dev/bin/studio-state` changes in these places and nowhere else" (the table at spec 101-112).
- (spec 154-156) "Skills cannot include one another, so each skill in parentheses carries a copy, and `test_feature_checkout_copies` asserts every copy holds the same key literals."
- (spec 308-310) "**exit 0 on every path**: no `set -u` — every expansion is written `${x:-}` — and `trap 'exit 0' EXIT` near the top."
- (spec 339-340) "the hook prints nothing at all on every silent path, and on the warning path prints exactly one JSON object and nothing else."
- (spec 566-568) "The skill names that package without the `superpowers:` prefix: a prefixed name would need a `requires.txt` line"
- (spec 676-677) "a rejected push (never force-push) … Never merge."
- (spec 1047-1048) "every new function is added to its file's `run_tests` line."
- (spec 1050-1054) "a test line that names a removed stage or the ship name — an assertion of absence, or a value fed to `set stage` — spells it split (`'sh''ip'`, `'game-dev:''ship'`, `'ship'' stage'`) or takes it from a loop variable, so `test_no_ship_references` never matches the tests' own lines."
- (spec 1512-1513) "fix-commit subjects `fix(T<n>)`, `fix(final)`, `fix(gate)`, `fix(review)`, `fix(B<n>)`"
- (plan rule) Every literal a test asserts sits on **one line** of its
  Markdown file. `assert_contains` is `grep -q --`, which matches line by
  line. Where the spec's replacement text wraps a literal, rewrap it. The
  known wrap points are:
  - spec 458-459: `studio-state set branch "$(git branch`
  - spec 462-463: `before the fast-forward`
  - spec 670-671: `## Play before merging`
  - spec 185-191: `previous, finished feature` and `start the next feature on this branch anyway`
  - spec 300-301: `Next: run /clear, then /game-dev:execute`
  - spec 970-971: `no second PR is opened`
- (plan rule) Run every test file and `sh tests/run_all.sh` from the
  repository root. `run_all.sh` exits 0 at the end of every task.

## Review Focus

These are the input classes most likely to bite, most likely first. Each one
is pinned by a test in the task that owns the code.

1. **A recorded branch whose name is a prefix of another branch that has a
   worktree** (`feat/p` with no worktree, `feat/p-2` with one). Expected:
   `studio-state worktree` exits 3 for `feat/p` and never prints
   `feat/p-2`'s path, because the ref is compared whole. Test: Task 1,
   `test_state_worktree_edges`.
2. **The branch is checked out in the main checkout itself**, not in a
   linked worktree. Expected: exit 0, printing the main checkout's path.
   Test: Task 1, `test_state_worktree_edges`.
3. **Pretty-printed hook input** (spaces after the colons, one key per line)
   whose `transcript_path` contains a space. Expected: the guard still finds
   the transcript and warns. Test: Task 2, `test_stage_guard_spaced_input`.
4. **The main checkout's path contains a space.** Expected: the exit-3
   command, pasted or run with `sh -c`, creates the worktree.
   - Ruling: the printed command single-quotes each path and the branch
     (`shq`). The spec's worktree algorithm (spec 120-151) shows them
     unquoted.
   - Test: Task 1, `test_state_worktree_edges`.
5. **A branch value containing sed replacement metacharacters** (`&`, `\1`)
   inserted into a STATE.md written before the key existed. Expected: the
   value is stored literally. The insert uses awk with `ENVIRON`, not sed.
   Test: Task 1, `test_state_branch_insert_is_literal`.

## Plan rulings on spec gaps

- **R1.** Spec 115-117 say "the no-reference test in §Testing pins" the
  removal of `last_playtest`, but §Testing (1045-1246) has no such test.
  Task 9 adds `test_no_last_playtest_callers`.
- **R2.** Spec 282 places the old-stage report at `session-start.sh:86`. That
  line sits inside `escaped="$( { … } | … )"`. bash 3.2, which is this Mac's
  `/bin/sh`, cannot parse a `case` pattern's `)` inside `$(…)`. The trial
  failed with "syntax error near unexpected token `newline'". Task 5 instead
  normalises `STAGE` right after `:20`, outside the substitution. `:86` is
  unchanged.
- **R3.** §Testing lists nine `test_stage_guard_*` functions without
  "(new)", but `tests/hook_test.sh` has none of them. All twelve are written
  new in Task 2.
- **R4.** The exit-3 command is printed with each path and the branch
  single-quoted (Review Focus 4).
- **R5.** Task 3 moves the producer's edits (spec 909-922) in with execute's
  finish, so the dispatch and its contract land together. The playtester's
  edits (spec 924-936) move in with the playtest rewrite (Task 7). The
  feature-checkout copy test is introduced in Task 3, and each task that
  adds a copy extends it.

## File Structure

| File | Change | Owner task |
|------|--------|-----------|
| `studios/game-dev/bin/studio-state` | `branch` key, `STAGES` cut to four, `set_branch`, `shq`, `worktree` subcommand | 1 |
| `studios/game-dev/hooks/stage-guard.sh` | **new**, executable: the `UserPromptSubmit` warning hook | 2 |
| `studios/game-dev/hooks/hooks.json` | registers `UserPromptSubmit` → `stage-guard.sh` | 2 |
| `studios/game-dev/skills/execute/SKILL.md` | §0 run kinds and isolation, mode, §4a fix rounds, §5 final review, §6 state, §7 finish | 3 |
| `studios/game-dev/agents/producer.md` | Finish method, output contract | 3 |
| `studios/game-dev/skills/brainstorm/SKILL.md` | rewrap `:44-45`, guard bullet, `Next:` line | 4 |
| `studios/game-dev/skills/plan/SKILL.md` | guard bullet, `Next:` line | 4 |
| `studios/game-dev/skills/studio/SKILL.md` | header fields, paragraph, stage table, on-demand paragraph, freeform rows | 5 |
| `studios/game-dev/hooks/bootstrap.md` | `## Stages` replaced, `## On demand` added | 5 |
| `studios/game-dev/hooks/session-start.sh` | old stage reported as `idle (was <x>, old pipeline)` | 5 |
| `studios/game-dev/skills/review/SKILL.md` | on-demand; execute's fix rules; Opus | 6 |
| `studios/game-dev/skills/playtest/SKILL.md` | rewritten whole: free-text failure in, fixed bug and one PR comment out | 7 |
| `studios/game-dev/agents/playtester.md` | bug method only; no `Write` | 7 |
| `studios/game-dev/skills/retro/SKILL.md` | on-demand, read-only harvest | 8 |
| `studios/game-dev/skills/ship/` | **deleted** | 9 |
| `studios/game-dev/requires.txt` | `:7` deleted | 9 |
| `shared/omega/skills/local-merge/SKILL.md` | `:23-26` replaced | 9 |
| `README.md` | `:71-75` replaced | 9 |
| `shared/omega/skills/autopilot/SKILL.md` | `:33-37`, `:118-123` replaced | 10 |
| `docs/game-dev/pressure/slim-pipeline.md` | **new**: three scenarios, M2 record | 11 |
| `tests/pressure/fixture.sh` | `slim-pipeline` kind | 11 |
| `docs/game-dev/PROGRESS.md` | log entry | 11 |
| `tests/state_test.sh` | helpers, `test_state_init` changed, six new tests | 1 |
| `tests/hook_test.sh` | guard helpers, twelve guard tests (2); `test_hook_files` additions, `test_hook_reports_old_stage` (5) | 2, 5 |
| `tests/studio_test.sh` | contract tests; `test_stage_chain` rewritten | 3-9 |
| `tests/omega_contracts/autopilot_contract.sh`, `local-merge_contract.sh` | added assertions | 10, 9 |

---

### Task 1: studio-state — branch key, four stages, worktree lookup

**Risk:** risky (new seam that every later skill depends on; data/schema change to STATE.md)

**Files:**
- Modify: `studios/game-dev/bin/studio-state`. The edits are at the header
  `:9-24`, `KEYS`/`STAGES` `:48-49`, `usage` `:53`, after `set_field`
  `:85-88`, the init heredoc `:129`, `set` `:177`, `reset` `:256`, and before
  `*)` `:259`.
- Test: `tests/state_test.sh`. The edits are helpers after `:17`,
  `test_state_init` `:28-41`, new functions before `run_tests` `:312`, and
  the `run_tests` line `:312-318`.

**Interfaces:**
- Consumes: nothing new.
- Produces (every later task relies on these exact behaviours):

  | Command | Behaviour |
  |---------|-----------|
  | `studio-state set stage X` | X ∈ `idle brainstorm plan execute`. Any other value exits 1 with stderr `studio-state: stage must be one of: idle brainstorm plan execute`. |
  | `studio-state set branch VALUE` | Exits 0. On a STATE.md with no `branch:` line, it inserts `branch: VALUE` right after the first `task:` line. With no `task:` line either, it exits 1 with `studio-state: no 'task:' line in <STATE> — the file is damaged; restore the header`. |
  | `studio-state get branch` | Prints the value. On a legacy file it prints nothing and exits 0. |
  | `studio-state reset` | Leaves `branch: -`. A missing line is inserted. |
  | `studio-state get last_playtest` / `set last_playtest x` | Exit 1 (unknown key). |
  | `studio-state worktree`, exit 0 | stdout is exactly one line: the physical path of the checkout that has the recorded branch checked out. The main checkout counts. |
  | `studio-state worktree`, exit 1 | stdout is empty. stderr is one of: `studio-state: no feature branch recorded` (`-` or no line); `studio-state: branch <b> no longer exists`; `need_state`'s error when there is no `.studio/`. |
  | `studio-state worktree`, exit 3 | stdout is empty. stderr is exactly two lines. Line 1: `studio-state: no worktree has <b> checked out`. Line 2: `[git worktree unlock '<stale path>' && ][git worktree prune && ]git worktree add '<main checkout>/.claude/worktrees/<b with / → ->' '<b>'`. |
  | `init` | Writes `branch: -` right after `task: -`, and no `last_playtest` line. |

**Acceptance:** AC 2, 3, 4, 5, 6.

- [ ] **Step 1: Write the failing tests** in `tests/state_test.sh`.

Insert after `fresh_project` (after `:17`):

```sh
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
```

Replace `test_state_init` (`:28-41`) with:

```sh
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
```

Add before the `run_tests` line:

```sh
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
  assert_contains "$TMP/wt.cmd" "^git worktree prune && git worktree add" "line 2 prunes the stale entry first"
  ( cd "$P" && sh -c "$(cat "$TMP/wt.cmd")" ) >/dev/null 2>&1
  wt_run "$P"
  assert_eq "0" "$WT_STATUS" "the printed prune-and-add command works"

  ( cd "$P" && git worktree add -q "$TMP/wt-h" -b feat/h && git worktree lock "$TMP/wt-h" ) >/dev/null 2>&1
  rm -rf "$TMP/wt-h"
  ( cd "$P" && sh "$STATE_BIN" set branch feat/h )
  wt_run "$P"
  assert_eq "3" "$WT_STATUS" "a locked worktree whose directory is gone exits 3"
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
```

Replace the `run_tests` line (`:312-318`) with:

```sh
run_tests test_state_needs_init test_state_init test_state_get_set test_state_validation \
  test_state_ledger test_state_ledger_keeps_all_words test_state_ledger_folds_newlines \
  test_state_set_keeps_backslashes test_state_show test_state_resolves_to_main_checkout \
  test_state_init_writes_config_ledger_and_gitignore_once test_state_init_gitignore_appends_safely \
  test_state_root_outside_git_is_quiet \
  test_state_set_hardening \
  test_state_feature_ledger test_state_ledger_per_branch test_state_check test_state_reset \
  test_state_stage_list test_state_legacy_file test_state_branch_key \
  test_state_branch_insert_is_literal test_state_worktree test_state_worktree_edges
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/state_test.sh`
Expected: FAIL, including these lines:
- `FAIL init writes no last_playtest line (unexpected '^last_playtest:' …)`
- `FAIL branch sits right after task (expected 'branch: -', got 'last_playtest: -')`
- `FAIL set stage rejects the removed stage review (expected '1', got '0')`
- `FAIL worktree exits 1 when branch is -` …

- [ ] **Step 3: Implement** in `studios/game-dev/bin/studio-state`. These
  are exactly the places the spec's table allows (spec 101-112).

Header. After the two `reset` lines (`:19-20`), add:

```sh
#   studio-state worktree        print the worktree that has the recorded branch checked out
```

`:22-24` become:

```sh
# Keys: stage spec plan task branch milestone
# Exit: 0 ok · 1 no .studio/ (except init and root), bad key, bad value, bad
# usage, or a check that found a mismatch · 3 worktree: the branch exists but
# no worktree has it checked out
```

`:48-49` become:

```sh
KEYS="stage spec plan task branch milestone"
STAGES="idle brainstorm plan execute"
```

`usage` (`:53`): append ` | worktree` after `reset [--keep-ledger]` in the
printf format string:

```sh
  printf 'usage: studio-state root [--work] | init | show | get KEY | set KEY VALUE | ledger TEXT | check [--rebuild] | reset [--keep-ledger] | worktree\nkeys: %s\n' "$KEYS" >&2
```

After `set_field` (after its closing `}` at `:88`, before the `# field KEY`
comment), add:

```sh
# set_branch VALUE — set_field for `branch`, except that a STATE.md written
# before the key existed gains the line right after its first `task:` line.
# Every other missing header line stays set_field's damaged-file error.
set_branch() {
  if grep -q '^branch: ' "$STATE"; then
    write_field branch "$1"
    return 0
  fi
  grep -q '^task: ' "$STATE" || fail "no 'task:' line in $STATE — the file is damaged; restore the header"
  _tmp="$STATE.tmp.$$"
  STUDIO_STATE_VALUE="$1" awk '
    BEGIN { done = 0 }
    { print }
    !done && /^task: / { print "branch: " ENVIRON["STUDIO_STATE_VALUE"]; done = 1 }
  ' "$STATE" > "$_tmp"
  mv "$_tmp" "$STATE"
}

# shq WORD — WORD single-quoted for sh, so a printed command survives a path
# with spaces or quotes when it is pasted or run.
shq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
```

Init heredoc (`:129`): `last_playtest: -` becomes `branch: -`.

`set` (`:177`): `set_field "$key" "$val"` becomes:

```sh
    if [ "$key" = branch ]; then set_branch "$val"; else set_field "$key" "$val"; fi
```

`reset`: after `set_field task -` (`:256`), add:

```sh
    set_branch -
```

New case, placed after `reset`'s `;;` and before `*)`:

```sh
  worktree)
    need_state
    [ $# -eq 1 ] || usage
    br="$(field branch)"
    case "$br" in ''|-) fail "no feature branch recorded" ;; esac
    git show-ref --verify --quiet "refs/heads/$br" 2>/dev/null || fail "branch $br no longer exists"
    # One record per `git worktree list --porcelain` block that holds the
    # branch: "<prunable 0|1><TAB><locked 0|1><TAB><path>". The ref is
    # compared whole, so feat/x never matches feat/x-2.
    _tab="$(printf '\t')"
    _recs="$(git worktree list --porcelain 2>/dev/null | STUDIO_STATE_REF="refs/heads/$br" awk '
      function flush() {
        if (hit) printf "%d\t%d\t%s\n", prunable, locked, path
        hit = 0; prunable = 0; locked = 0; path = ""
      }
      /^worktree / { flush(); path = substr($0, 10); next }
      $0 == "branch " ENVIRON["STUDIO_STATE_REF"] { hit = 1; next }
      /^prunable( |$)/ { prunable = 1; next }
      /^locked( |$)/ { locked = 1; next }
      END { flush() }
    ')"
    _prefix=""
    while IFS="$_tab" read -r _pr _lk _p; do
      [ -n "$_p" ] || continue
      if [ "$_pr" = 0 ] && [ -d "$_p" ]; then
        printf '%s\n' "$_p"
        exit 0
      fi
      # A stale entry still holds the branch, and git refuses to add a second
      # worktree for it. Claude Code locks its worktrees and git never marks
      # a locked entry prunable: unlock it first, then prune.
      if [ "$_lk" = 1 ]; then
        _prefix="git worktree unlock $(shq "$_p") && git worktree prune && "
      elif [ -z "$_prefix" ]; then
        _prefix="git worktree prune && "
      fi
    done <<EOF
$_recs
EOF
    _name="$(printf '%s' "$br" | tr '/' '-')"
    printf 'studio-state: no worktree has %s checked out\n' "$br" >&2
    printf '%sgit worktree add %s %s\n' "$_prefix" "$(shq "$STATE_ROOT/.claude/worktrees/$_name")" "$(shq "$br")" >&2
    exit 3
    ;;
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `sh tests/state_test.sh && dash tests/state_test.sh`
Expected: `… assertions, 0 failed` twice. The trial run gave 80/80 under both
bash and dash.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.
  `test_bin_syntax` re-parses `studio-state` with `sh -n`.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/bin/studio-state tests/state_test.sh
git commit -m "feat(studio-state): branch key, three-stage list, worktree lookup"
```

---

### Task 2: stage-guard hook

**Risk:** risky (new hook. A non-zero exit would erase the user's prompt; it parses an input shape no live run has confirmed.)

**Files:**
- Create: `studios/game-dev/hooks/stage-guard.sh` (mode 755)
- Modify: `studios/game-dev/hooks/hooks.json`. Add the `UserPromptSubmit`
  array after `PreToolUse`.
- Test: `tests/hook_test.sh`. Add `STAGE_GUARD` after `:8`, helpers after
  `context()` (`:26`), new functions before `run_tests` (`:187`), and extend
  the `run_tests` line (`:187-190`).

**Interfaces:**
- Consumes: hook stdin JSON with `transcript_path` and `prompt`, and the
  transcript JSONL.
- Produces:
  - Exit 0 on every path.
  - stdout is empty, or exactly the one line
    `{"systemMessage":"game-dev: this session already ran /game-dev:<prior> — its context is carried into <typed>. Run /clear, then /game-dev:<typed>."}`
    (spec 391), where `<prior>`, `<typed>` ∈ `brainstorm plan execute` and
    differ.

**Acceptance:** AC 18, 19, 20.

- [ ] **Step 1: Write the failing tests** in `tests/hook_test.sh`.

After `GUARD=` (`:8`):

```sh
STAGE_GUARD="$STUDIO_DIR/hooks/stage-guard.sh"
```

After `context()` (after `:26`):

```sh
# typed_line STAGE — a transcript line for a typed /game-dev:STAGE, as
# Claude Code writes the command's envelope.
typed_line() {
  printf '{"type":"user","message":{"role":"user","content":"<command-message>game-dev:%s</command-message>\\n<command-name>/game-dev:%s</command-name>"}}\n' "$1" "$1"
}

# skill_line STAGE — a transcript line for a Skill tool call of game-dev:STAGE
# (the router invoking a stage).
skill_line() {
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Skill","input":{"skill":"game-dev:%s"}}]}}\n' "$1"
}

# guard_input FILE — run the stage guard with FILE as its stdin, as Claude
# Code would. Asserts exit 0; stdout lands in $TMP/guard.out.
guard_input() {
  _gst=0
  CLAUDE_PLUGIN_ROOT="$STUDIO_DIR" sh "$STAGE_GUARD" < "$1" > "$TMP/guard.out" 2> "$TMP/guard.err" || _gst=$?
  assert_eq "0" "$_gst" "the stage guard exits 0"
}

# run_guard PROMPT TRANSCRIPT — a UserPromptSubmit input whose prompt is
# PROMPT (JSON string content, so '\n' stays an escape) and whose
# transcript_path is TRANSCRIPT, fed to the guard.
run_guard() {
  printf '{"session_id":"s-1","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}\n' \
    "$2" "$TMP" "$1" > "$TMP/guard.in"
  guard_input "$TMP/guard.in"
}

# warning PRIOR TYPED — the exact systemMessage text (spec §3).
warning() {
  printf 'game-dev: this session already ran /game-dev:%s — its context is carried into %s. Run /clear, then /game-dev:%s.' \
    "$1" "$2" "$2"
}

# assert_warns PRIOR TYPED MSG — stdout is one JSON object whose only key is
# systemMessage, carrying the warning text.
assert_warns() {
  assert_eq "1" "$(wc -l < "$TMP/guard.out" | tr -d ' ')" "$3 (one line)"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "$(warning "$1" "$2")" "$(jq -r .systemMessage "$TMP/guard.out")" "$3"
    assert_eq "systemMessage" "$(jq -r 'keys | join(",")' "$TMP/guard.out")" "$3 (systemMessage is the only key)"
  else
    assert_eq "{\"systemMessage\":\"$(warning "$1" "$2")\"}" "$(cat "$TMP/guard.out")" "$3"
  fi
}

# assert_silent MSG — the guard printed nothing at all.
assert_silent() {
  assert_eq "" "$(cat "$TMP/guard.out")" "$1"
}
```

Before `run_tests`:

```sh
test_stage_guard_registered() {
  assert_contains "$STUDIO_DIR/hooks/hooks.json" '"UserPromptSubmit"' "hooks.json registers UserPromptSubmit"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/stage-guard.sh' \
    "hooks.json runs stage-guard.sh from the plugin root"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "hooks.json is still valid JSON" -- jq -e . "$STUDIO_DIR/hooks/hooks.json"
  fi
  assert_file "$STAGE_GUARD" "stage-guard.sh exists"
  assert_contains "$STAGE_GUARD" "trap 'exit 0' EXIT" "the guard turns every exit into exit 0"
  assert_not_contains "$STAGE_GUARD" '^[[:space:]]*set -[a-z]*u' "the guard never sets -u"
}

test_stage_guard_first_stage_silent() {
  : > "$TMP/t-empty.jsonl"
  run_guard "/game-dev:plan" "$TMP/t-empty.jsonl"
  assert_silent "a first stage in a session prints nothing"
}

test_stage_guard_warns_after_other_stage() {
  typed_line plan > "$TMP/t-plan.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-plan.jsonl"
  assert_warns plan execute "execute typed after a typed plan warns"
  skill_line plan > "$TMP/t-plan-skill.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-plan-skill.jsonl"
  assert_warns plan execute "execute typed after a Skill-tool plan warns"
}

test_stage_guard_raw_prompt_shape() {
  typed_line plan > "$TMP/t-plan.jsonl"
  run_guard "/game-dev:execute --inline" "$TMP/t-plan.jsonl"
  assert_warns plan execute "a stage command with arguments warns"
  run_guard "   /game-dev:execute" "$TMP/t-plan.jsonl"
  assert_warns plan execute "leading spaces are ignored"
  run_guard "please run /game-dev:execute" "$TMP/t-plan.jsonl"
  assert_silent "a command after other text is not a typed stage"
  run_guard "/game-dev:executes" "$TMP/t-plan.jsonl"
  assert_silent "a longer name is not a stage"
}

test_stage_guard_envelope_prompt() {
  typed_line plan > "$TMP/t-plan.jsonl"
  run_guard '<command-message>game-dev:execute</command-message>\n<command-name>/game-dev:execute</command-name>' \
    "$TMP/t-plan.jsonl"
  assert_warns plan execute "the envelope shape warns the same way"
}

test_stage_guard_names_latest_prior_stage() {
  { typed_line brainstorm; typed_line plan; } > "$TMP/t-bp.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-bp.jsonl"
  assert_warns plan execute "the most recent different stage is named"
}

test_stage_guard_same_stage_silent() {
  typed_line execute > "$TMP/t-exec.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-exec.jsonl"
  assert_silent "the same stage again prints nothing"
}

test_stage_guard_ignores_mentions() {
  {
    printf '{"type":"user","message":{"content":"- `/game-dev:plan` — role- and verify-tagged tasks, producer scope cut, approval gate.\\n- `/game-dev:execute` — fresh role agent per task"}}\n'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Spec approved; the next command is `/game-dev:plan`. A pasted <command-message>game-dev:plan</command-message> is prose too."}]}}\n'
  } > "$TMP/t-prose.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-prose.jsonl"
  assert_silent "prose mentions of a stage command do not count"
}

test_stage_guard_ordinary_prompt_silent() {
  typed_line execute > "$TMP/t-exec.jsonl"
  run_guard "keep going" "$TMP/t-exec.jsonl"
  assert_silent "an ordinary prompt prints nothing"
  run_guard "/game-dev:review" "$TMP/t-exec.jsonl"
  assert_silent "an on-demand command prints nothing"
  run_guard "/game-dev:studio" "$TMP/t-exec.jsonl"
  assert_silent "the router prints nothing"
}

test_stage_guard_scheduled_task_silent() {
  typed_line plan > "$TMP/t-plan.jsonl"
  printf '{"session_id":"s-1","transcript_path":"%s","hook_event_name":"UserPromptSubmit","prompt":"/game-dev:execute","source":"<scheduled-task name=\\"nightly\\">"}\n' \
    "$TMP/t-plan.jsonl" > "$TMP/guard-sched.in"
  guard_input "$TMP/guard-sched.in"
  assert_silent "a scheduled task is never warned"
}

test_stage_guard_no_transcript_silent() {
  printf '{"session_id":"s-1","hook_event_name":"UserPromptSubmit","prompt":"/game-dev:execute"}\n' > "$TMP/g-nokey.in"
  guard_input "$TMP/g-nokey.in"
  assert_silent "no transcript_path key prints nothing"
  run_guard "/game-dev:execute" "$TMP/no-such-transcript.jsonl"
  assert_silent "a missing transcript file prints nothing"
  : > "$TMP/g-empty.in"
  guard_input "$TMP/g-empty.in"
  assert_silent "an empty input prints nothing"
  printf 'not json /game-dev:execute\n' > "$TMP/g-text.in"
  guard_input "$TMP/g-text.in"
  assert_silent "a non-JSON input prints nothing"
}

# Review focus 3: a pretty-printed input (spaces after the colons, one key
# per line) whose transcript path holds a space still warns.
test_stage_guard_spaced_input() {
  mkdir -p "$TMP/a dir"
  typed_line plan > "$TMP/a dir/t.jsonl"
  printf '{\n  "session_id": "s-1",\n  "transcript_path": "%s",\n  "hook_event_name": "UserPromptSubmit",\n  "prompt": "/game-dev:execute"\n}\n' \
    "$TMP/a dir/t.jsonl" > "$TMP/g-pretty.in"
  guard_input "$TMP/g-pretty.in"
  assert_warns plan execute "a pretty-printed input with a spaced transcript path warns"
}
```

Replace the `run_tests` line (`:187-190`) with:

```sh
run_tests test_hook_files test_hook_output_shape test_hook_defaults_from_studio_json \
  test_hook_reads_project_config test_hook_partial_config_falls_back test_hook_escapes_json \
  test_hook_fills_config_value_with_metacharacters test_guard_state_blocks_direct_writes \
  test_hook_fails_without_bootstrap test_hook_strips_control_characters test_hook_reports_stage \
  test_stage_guard_registered test_stage_guard_first_stage_silent \
  test_stage_guard_warns_after_other_stage test_stage_guard_raw_prompt_shape \
  test_stage_guard_envelope_prompt test_stage_guard_names_latest_prior_stage \
  test_stage_guard_same_stage_silent test_stage_guard_ignores_mentions \
  test_stage_guard_ordinary_prompt_silent test_stage_guard_scheduled_task_silent \
  test_stage_guard_no_transcript_silent test_stage_guard_spaced_input
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/hook_test.sh`
Expected: FAIL, including:
- `FAIL hooks.json registers UserPromptSubmit (missing '"UserPromptSubmit"' …)`
- `FAIL stage-guard.sh exists (no regular file at …)`
- `FAIL the stage guard exits 0 (expected '0', got '127')`

- [ ] **Step 3: Implement**

Create `studios/game-dev/hooks/stage-guard.sh` with exactly this content,
then `chmod 755 studios/game-dev/hooks/stage-guard.sh`:

```sh
#!/bin/sh
# UserPromptSubmit hook for the game-dev studio. Warns — never blocks — when
# a stage command (/game-dev:brainstorm, plan or execute) is typed into a
# session that already ran a different stage: that stage's context would be
# carried into this one.
#
# Exit 0 on every path: exit 2 from a UserPromptSubmit hook blocks the prompt
# and erases it. So there is no `set -u` (an unbound variable aborts the
# shell with status 2; every expansion is written ${x:-}), and the trap below
# turns any other exit into 0. Plain stdout is added to Claude's context:
# every silent path prints nothing, and the warning path prints exactly one
# JSON object. Self-contained: a copy-mode install has no lib/.
trap 'exit 0' EXIT

# 1. The hook input.
input="$(cat 2>/dev/null || true)"

# 2. One line, the JSON escapes for newline and tab turned into spaces
#    (as shared/omega/hooks/prompt-submit.sh flattens its input).
flat="$(printf '%s' "${input:-}" | tr '\n\t' '  ' | sed -e 's/\\n/ /g' -e 's/\\t/ /g')"

# 3. The prompt's own value, up to the next '"', leading whitespace removed.
prompt_val="$(printf '%s' "${flat:-}" \
  | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
prompt_val="$(printf '%s' "${prompt_val:-}" | sed -e 's/^[[:space:]]*//')"

# 4. Unattended scheduled-task runs are never warned.
case "${flat:-}" in
  *'<scheduled-task'*) exit 0 ;;
esac

# 5. The typed stage. Raw: the text as typed (the shape Claude Code 2.1.286
#    sends). Envelope: <command-name>, after one optional <command-message>
#    (the shape some versions send).
typed="$(printf '%s\n' "${prompt_val:-}" \
  | sed -n -E 's#^/game-dev:(brainstorm|plan|execute)([[:space:]].*)?$#\1#p' | head -n 1)"
if [ -z "${typed:-}" ]; then
  envelope="$(printf '%s' "${prompt_val:-}" \
    | sed -e 's/^<command-message>[^<]*<\/command-message>[[:space:]]*//')"
  case "${envelope:-}" in
    '<command-name>'*)
      typed="$(printf '%s\n' "${envelope:-}" \
        | sed -n -E 's#^<command-name>[[:space:]]*/game-dev:(brainstorm|plan|execute)[[:space:]]*</command-name>.*#\1#p' \
        | head -n 1)" ;;
  esac
fi
[ -n "${typed:-}" ] || exit 0

# 6. The session's transcript.
transcript="$(printf '%s' "${flat:-}" \
  | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "${transcript:-}" ] && [ -f "${transcript:-}" ] && [ -r "${transcript:-}" ] || exit 0

# 7-8. Stages this session already ran, oldest first — a typed command's
#      envelope or a Skill tool call, each anchored at the start of a JSON
#      string so a prose mention never counts — minus the typed one; the
#      last is the most recent different stage.
prior="$(grep -oE '"<command-message>game-dev:(brainstorm|plan|execute)</command-message>|"<command-name>/game-dev:(brainstorm|plan|execute)</command-name>|"name":[[:space:]]*"Skill",[[:space:]]*"input":[[:space:]]*\{[[:space:]]*"skill":[[:space:]]*"game-dev:(brainstorm|plan|execute)"' \
    "${transcript:-}" 2>/dev/null \
  | sed -E 's/.*game-dev:(brainstorm|plan|execute).*/\1/' \
  | grep -vx -- "${typed:-}" | tail -n 1)"
[ -n "${prior:-}" ] || exit 0

# 9. Both names come from a fixed set: no JSON escaping needed.
printf '{"systemMessage":"game-dev: this session already ran /game-dev:%s — its context is carried into %s. Run /clear, then /game-dev:%s."}\n' \
  "${prior:-}" "${typed:-}" "${typed:-}"
exit 0
```

In `studios/game-dev/hooks/hooks.json`, change the `PreToolUse` array's
closing `]` to `],` and add after it:

```json
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/stage-guard.sh\""
          }
        ]
      }
    ]
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `sh tests/hook_test.sh && dash tests/hook_test.sh && jq -e . studios/game-dev/hooks/hooks.json >/dev/null`
Expected: `… 0 failed` twice, and jq exits 0.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.
  `test_bin_syntax` checks that `stage-guard.sh` is executable and passes
  `sh -n`.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/hooks/stage-guard.sh studios/game-dev/hooks/hooks.json tests/hook_test.sh
git commit -m "feat(hooks): stage guard warns when a session already ran another stage"
```

---

### Task 3: execute — B2 fix rounds, standalone Opus final review, finish to a ready PR (with the producer)

**Risk:** risky (gameplay-pipeline core; cross-system: state, worktrees, gh, producer agent)

**Files:**
- Modify: `studios/game-dev/skills/execute/SKILL.md`. The edits touch `:3`,
  `:11-41`, `:43-55`, `:104-126`, `:128-143` and `:145-160`; §2-§3
  (`:57-102`) stay. Each edit is listed below.
- Modify: `studios/game-dev/agents/producer.md` at `:3`, `:33-43` and
  `:58-60`.
- Test: `tests/studio_test.sh`. The edits are `:145`, a line inserted after
  `:200`, three new functions, and the `run_tests` line.

**Interfaces:**
- Consumes from Task 1:
  - `studio-state worktree` (exit 0, 1 or 3, with the stderr lines above);
  - `studio-state set branch`, `get branch`, `set stage execute|idle`.
- Produces (used by Tasks 6, 7, 8 and the router):
  - Ledger lines:
    - `base <branch>`
    - `final review done`
    - `Review: final — <Findings line>; unmet: <list or none>`
    - `P<k> Play: <item>`
    - `shipped <PR url | branch>`
    - `T<n> Ruling: parked — <finding> — <why> — <cost if wrong>`
    - `Ruling: gate red after three fix rounds — <failing command and line> — <cost if wrong>`
  - Commit subjects: `chore(studio): ledger`, `fix(T<n>)`, `fix(final)`,
    `fix(gate)`.
  - The PR body file: `"$(git rev-parse --git-dir)/game-dev-pr-body.md"`.
  - At the finish, `stage` is `idle` and `branch` keeps the feature branch
    until the next new run clears it.
  - The producer's report: `gate met: <current> → <next>` or
    `gate not met: …`.

**Acceptance:** AC 11, 12, 13, 14, part of 15 (execute's new-run guard), part of 25 (producer).

- [ ] **Step 1: Write the failing tests** in `tests/studio_test.sh`.

`:145` (`assert_contains "$S/execute/SKILL.md" "unverified" "execute lists unverified items"`) becomes:

```sh
  assert_contains "$S/execute/SKILL.md" "Play before merging" "execute hands the user a play list"
```

After `:200` (the `game-dev:reviewer` line of `test_stage_skills_dispatch_agents`), add:

```sh
  assert_contains "$S/execute/SKILL.md" 'subagent_type: "game-dev:producer"' "execute dispatches the producer at the finish"
```

Add before `run_tests`:

```sh
# Execute's slim-pipeline contract (spec §4): B2 fix rounds, the standalone
# final review on Opus, the finish to a ready PR, and isolation that records
# the feature branch and its base.
test_execute_contract() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  for lit in 'never resume or message an implementer' 'superpowers:subagent-driven-development' \
             '[Nn]ever a third' 'review-package' 'model: "opus"' 'never folded' 'Verify prior fixes' \
             'final|gate|review' 'final fix wave' 'A task is complete' 'final review done' 'studio-lint' \
             'subagent_type: "game-dev:producer"' 'gh pr create' '[-][-]draft' 'local, default branch' \
             'Play before merging' 'studio-state set stage idle' 'new run clears' \
             'studio-state set branch "$(git branch' 'before the fast-forward' 'ledger "base' \
             "from the feature's worktree" 'set task 0/' 'N/N' 'SDD ledger — plan:' \
             'Next: play the list; merge when it passes; report failures with /game-dev:playtest <what failed>; /clear before the next feature\.'; do
    assert_contains "$E" "$lit" "execute carries: $lit"
  done
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qE '3\+ Importants|three or more Importants' "$E"; then
    _pass "execute re-reviews after 3+ Importants"
  else
    _fail "execute re-reviews after 3+ Importants"
  fi
  assert_not_contains "$E" 'set stage ''review' "execute no longer hands off to a review stage"
  assert_not_contains "$E" 'a side effect outside the worktree' "execute drops the old side-effect rule"
}

# The agent contracts the slim pipeline changed. The producer records the
# finish with the play list, and has no Bash, so it runs no studio-state.
test_agent_contracts() {
  A="$REPO_ROOT/studios/game-dev/agents"
  assert_contains "$A/producer.md" 'Play before merging' "the producer's log entry carries the play list"
  assert_not_contains "$A/producer.md" 'playtest report it passed' "the producer reads no playtest report"
  assert_not_contains "$A/producer.md" 'sh''ip skill' "the producer names no deleted skill"
  assert_not_contains "$A/producer.md" 'studio-state show' "the producer runs no studio-state"
}

# Every copy of a §1 feature-checkout procedure holds its key literals: skills
# cannot include one another, so each skill that runs a procedure carries its
# own copy. The three lists name the skills that carry each procedure.
test_feature_checkout_copies() {
  S="$REPO_ROOT/studios/game-dev/skills"
  enter_leave="execute"
  guard="execute"
  default_branch="execute"
  for sk in $enter_leave; do
    for lit in 'studio-state worktree' 'EnterWorktree' 'another live session' 'ExitWorktree' '--git-common-dir'; do
      assert_contains "$S/$sk/SKILL.md" "$lit" "$sk carries the enter/leave procedure: $lit"
    done
  done
  for sk in $guard; do
    for lit in 'studio-state get branch' 'previous, finished feature' 'start the next feature on this branch anyway'; do
      assert_contains "$S/$sk/SKILL.md" "$lit" "$sk carries the finished-checkout guard: $lit"
    done
  done
  for sk in $default_branch; do
    assert_contains "$S/$sk/SKILL.md" 'refs/remotes/origin/HEAD' "$sk carries the default-branch procedure"
  done
}
```

Append `test_execute_contract test_agent_contracts test_feature_checkout_copies` to the `run_tests` line:

```sh
run_tests test_plugin_manifests test_skill_frontmatter test_agent_frontmatter \
  test_external_references_declared test_required_plugins_enabled test_bin_syntax \
  test_role_agents_exist test_stage_skill_contracts test_plan_skill_contract \
  test_brainstorm_skill_contract \
  test_studio_skill_contract test_game_dev_agent_roster test_stage_skills_dispatch_agents \
  test_stage_chain test_execute_contract test_agent_contracts test_feature_checkout_copies
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL, including:
- `FAIL execute carries: never resume or message an implementer (missing …)`
- `FAIL execute hands the user a play list`
- `FAIL execute dispatches the producer at the finish`
- `FAIL the producer's log entry carries the play list`
- `FAIL execute carries the enter/leave procedure: studio-state worktree`

- [ ] **Step 3: Implement.** The replacement text is in the spec. Write it
  in, keeping each asserted literal on one line (Global Constraints).

| Target | Replacement text (spec lines) |
|--------|-------------------------------|
| execute `:3` description | 416-419 |
| execute §0 `:11-41`. Keep the checks `:15-28` (`git log -1`). Insert "which run this is" before `:29` and rewrite isolation `:34-41`. | 421-491, with these copies: the Finished-checkout guard (182-193) on a new run before any state write; Default branch (158-160); Enter (161-168) for a resume |
| execute Mode `:45-48`, and `--inline` `:50-55` (keep the `superpowers:executing-plans` sentence) | 493-502 |
| execute §4 `:104-126`. Keep `:106-123`; `:125-126` is replaced. | 504-506 |
| execute §4a, new after §4 | 508-552 (the override at 511-514 holds `never resume or message an implementer`) |
| execute §5 Final review, new | 554-596. Name the review package without the `superpowers:` prefix (566-569). |
| execute §6 State (today's §5 `:128-143`, renumbered) | 598-611 (stop text 605-609 keeps "do not set `stage idle`") |
| execute §7 Finish replaces `:145-160` | 613-697: gate 617-638 (`superpowers:verification-before-completion`, `studio-run --seconds 10`, `SCRIPT ERROR`, `GODOT_PATH`); play list 639-647; producer 648-657; push/PR 658-677; state 678-682; Leave procedure (169-181) at 683-690; report 691-697 |
| producer `:3` description | 911-912 |
| producer `:33-43` "Ship method" becomes "Finish method" | 913-919 (it has no Bash: it reads the ledger at the brief's path) |
| producer `:58-60` output contract | 920-922 |

Literals the tests assert in execute, each on one line:
- `never resume or message an implementer`
- `superpowers:subagent-driven-development`
- `3+ Importants` (or `three or more Importants`)
- `never a third` / `Never a third`
- `review-package`
- `model: "opus"`
- `never folded`
- `Verify prior fixes`
- `final|gate|review`
- `final fix wave`
- `A task is complete`
- `final review done`
- `studio-lint`
- `subagent_type: "game-dev:producer"`
- `gh pr create`
- `--draft`
- `local, default branch`
- `Play before merging`
- `studio-state set stage idle`
- `new run clears`
- `studio-state set branch "$(git branch`
- `before the fast-forward`
- `ledger "base`
- `from the feature's worktree`
- `set task 0/`
- `N/N`
- `SDD ledger — plan:`
- the verbatim `Next:` line at spec 696
- `studio-state worktree`
- `EnterWorktree`
- `another live session`
- `ExitWorktree`
- `--git-common-dir`
- `studio-state get branch`
- `previous, finished feature`
- `start the next feature on this branch anyway`
- `refs/remotes/origin/HEAD`

Kept from today's text:
- `studio-run --seconds 10`
- `SCRIPT ERROR`
- `GODOT_PATH`
- `do not set`
- `git log -1`
- `game-dev:feel-tuner`
- `subagent_type: "game-dev:<role>"`
- `game-dev:reviewer`

Never present:
- `set stage review`
- `a side effect outside the worktree`
- `finishing-a-development-branch`
- `general-purpose`
- a prefixed `superpowers:requesting-code-review`

The last `studio-state set stage` line in the file must be the idle one.
The old `test_stage_chain` reads it until Task 5, and the new one asserts it.

In producer.md:
- The description still starts `Use when`.
- `tools:` (`:4`) is unchanged.
- The file contains `Play before merging`.
- It contains none of `playtest report it passed`, `studio-state show` or
  the ship skill's name.

- [ ] **Step 4: Run the tests and see them pass**

Run: `sh tests/studio_test.sh`
Expected: `… 0 failed`.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0. The old
  `test_stage_chain` still passes: execute's last value is `idle`, and the
  router's `idle` row is unchanged.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/skills/execute/SKILL.md studios/game-dev/agents/producer.md tests/studio_test.sh
git commit -m "feat(execute): B2 fix rounds, standalone Opus final review, finish to a ready PR"
```

---

### Task 4: brainstorm and plan — finished-checkout guard and `/clear` Next lines

**Risk:** mechanical

**Files:**
- Modify: `studios/game-dev/skills/brainstorm/SKILL.md` at `:14-22` (§0),
  `:44-45` and `:224-227`.
- Modify: `studios/game-dev/skills/plan/SKILL.md` at `:9-19` (§0) and
  `:130-132`.
- Test: `tests/studio_test.sh`. The edits are `test_brainstorm_skill_contract`,
  `test_feature_checkout_copies`'s lists, the new `test_next_lines`, and the
  `run_tests` line.

**Interfaces:**
- Consumes from Task 1: `studio-state get branch`, `studio-state set branch -`.
- Produces: brainstorm's last `studio-state set stage` value is
  `brainstorm`, on one line. Task 5's `test_stage_chain` reads it.

**Acceptance:** AC 16, part of 15 (brainstorm and plan), part of 7 (brainstorm's stage on one line).

- [ ] **Step 1: Write the failing tests.**

In `test_brainstorm_skill_contract`, add:

```sh
  assert_contains "$S/brainstorm/SKILL.md" 'studio-state set stage brainstorm' "brainstorm's stage command sits on one line"
```

In `test_feature_checkout_copies`, the two list lines become:

```sh
  guard="brainstorm plan execute"
  default_branch="brainstorm plan execute"
```

Add before `run_tests`:

```sh
# Brainstorm and plan end by printing the next command, to run after a /clear.
test_next_lines() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_contains "$S/brainstorm/SKILL.md" 'Next: run /clear, then /game-dev:plan' "brainstorm prints the /clear Next line"
  assert_contains "$S/plan/SKILL.md" 'Next: run /clear, then /game-dev:execute' "plan prints the /clear Next line"
}
```

Append `test_next_lines` to the `run_tests` line.

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL, including:
- `FAIL brainstorm's stage command sits on one line`
- `FAIL brainstorm prints the /clear Next line`
- `FAIL brainstorm carries the finished-checkout guard: studio-state get branch`

- [ ] **Step 3: Implement** using spec 287-303.
  - Brainstorm:
    - Rewrap `:44-45` so `studio-state set stage brainstorm` is on one line.
      The text is unchanged.
    - Add the guard bullet to §0. It is a copy of spec 182-193, together with
      the Default-branch procedure from spec 158-160.
    - `:224-225` becomes "and print `Next: run /clear, then /game-dev:plan`".
      `:226-227` stays.
  - Plan:
    - Add the same guard bullet to §0 (`:9-19`).
    - The sentence at `:130-131` becomes "and print `Next: run /clear, then
      /game-dev:execute` (subagent-driven by default; `--inline` for
      checkpointed execution)", with the `Next:` text on one line.
      "Do not invoke it yourself." stays.

- [ ] **Step 4: Run the tests and see them pass.** `sh tests/studio_test.sh` reports `0 failed`.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/skills/brainstorm/SKILL.md studios/game-dev/skills/plan/SKILL.md tests/studio_test.sh
git commit -m "feat(skills): finished-checkout guard and /clear Next lines"
```

---

### Task 5: router, bootstrap and session-start — the three-stage chain

**Risk:** risky (the router misroutes every user if the table drifts; session-start runs under bash 3.2)

**Files:**
- Modify: `studios/game-dev/skills/studio/SKILL.md` at `:18-19`, `:46-53`,
  `:55-64`, the new paragraph after the table, and `:84-88`.
- Modify: `studios/game-dev/hooks/bootstrap.md` at `:7-19`.
- Modify: `studios/game-dev/hooks/session-start.sh`. Insert after `:20`
  (ruling R2).
- Test: `tests/studio_test.sh`. Rewrite `test_stage_chain` together with its
  comment block (`:219-244`, shifted by the earlier tasks' insertions).
- Test: `tests/hook_test.sh`. Add to `test_hook_files`, add the new
  `test_hook_reports_old_stage`, and update the `run_tests` line.

**Interfaces:**
- Consumes:
  - `STAGES="idle brainstorm plan execute"` (Task 1);
  - execute's last stage value `idle` (Task 3);
  - brainstorm's one-line `set stage brainstorm` (Task 4).
- Produces:
  - router rows `| \`idle\` | \`/game-dev:brainstorm\` |`,
    `| \`brainstorm\` | \`/game-dev:plan\` |`, `| \`plan\` | \`/game-dev:execute\` |`,
    `| \`execute\` | \`/game-dev:execute\` (resume) |`, and the
    `any other value … old pipeline` row;
  - the session-start line `Studio state: stage idle (was <x>, old pipeline)`.

**Acceptance:** AC 7, 17, 21.

- [ ] **Step 1: Write the failing tests.**

In `tests/studio_test.sh`, replace the comment block and `test_stage_chain`
with:

```sh
# Cross-checks the router's stage table (studio/SKILL.md) against the stage
# chain idle → brainstorm → plan → execute → idle: the four rows and the
# old-pipeline row, the value each stage skill last sets (execute's is idle),
# and every value studio-state accepts. A future edit to either side that
# breaks the chain fails here instead of misrouting users.
test_stage_chain() {
  S="$REPO_ROOT/studios/game-dev/skills"
  router="$S/studio/SKILL.md"
  assert_contains "$router" '| `idle` | `/game-dev:brainstorm` |' "router routes idle to brainstorm"
  assert_contains "$router" '| `brainstorm` | `/game-dev:plan` |' "router routes brainstorm to plan"
  assert_contains "$router" '| `plan` | `/game-dev:execute` |' "router routes plan to execute"
  assert_contains "$router" '| `execute` | `/game-dev:execute`' "router resumes execute"
  assert_contains "$router" '^| any other value.*old pipeline' "router reads any other stage as the old pipeline"
  for skill in brainstorm plan execute; do
    last="$(grep -o 'studio-state set stage [a-z]*' "$S/$skill/SKILL.md" | tail -n 1 | awk '{print $NF}')"
    if [ -z "$last" ]; then
      TESTS_RUN=$((TESTS_RUN + 1))
      _fail "$skill sets a stage value on one line"
      continue
    fi
    assert_contains "$router" "^| \`$last\` |" "router has a row for stage $last (set last by $skill)"
  done
  assert_eq "idle" "$(grep -o 'studio-state set stage [a-z]*' "$S/execute/SKILL.md" | tail -n 1 | awk '{print $NF}')" \
    "execute's last stage value is idle"
  stages="$(sed -n 's/^STAGES="\(.*\)"$/\1/p' "$REPO_ROOT/studios/game-dev/bin/studio-state")"
  assert_eq "idle brainstorm plan execute" "$stages" "studio-state accepts exactly the four stages"
  for st in $stages; do
    assert_contains "$router" "^| \`$st\` |" "router has a row for stage $st"
  done
}
```

In `tests/hook_test.sh`, add at the end of `test_hook_files`:

```sh
  B="$STUDIO_DIR/hooks/bootstrap.md"
  assert_contains "$B" '/game-dev:review \[scope\]' "bootstrap lists the on-demand review"
  assert_contains "$B" '/game-dev:playtest <what failed>' "bootstrap lists the on-demand playtest"
  assert_contains "$B" '/game-dev:retro' "bootstrap lists the on-demand retro"
  assert_contains "$B" 'idle → brainstorm → plan → execute → idle' "bootstrap states the three-stage chain"
  assert_contains "$B" 'Run each stage in a fresh session: `/clear`' "bootstrap says to /clear between stages"
  assert_contains "$B" 'omega modes' "bootstrap says /clear ends the session's omega modes"
  assert_not_contains "$B" 'game-dev:''ship' "bootstrap names no deleted command"
```

Add before `run_tests`:

```sh
# A stage value the old eight-stage pipeline wrote reads as idle, the way the
# router reports it.
test_hook_reports_old_stage() {
  mkdir -p "$TMP/oldstage/.studio/ledger"
  printf '# Studio State\n\nstage: retro\nspec: -\nplan: -\ntask: -\nlast_playtest: -\nmilestone: prototype\n\n## Ledger\n\n' \
    > "$TMP/oldstage/.studio/STATE.md"
  run_hook "$TMP/oldstage"
  context "$TMP/hook.out" > "$TMP/ctx10.txt"
  assert_contains "$TMP/ctx10.txt" "Studio state: stage idle (was retro, old pipeline)" "an old stage reads as idle"
  assert_eq "" "$(cat "$TMP/hook.err")" "the hook is silent on stderr for an old stage"
}
```

Append `test_hook_reports_old_stage` to the `run_tests` line, after
`test_hook_reports_stage`.

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/studio_test.sh; sh tests/hook_test.sh`
Expected: FAIL, including:
- `FAIL router reads any other stage as the old pipeline`
- `FAIL bootstrap lists the on-demand review`
- `FAIL bootstrap states the three-stage chain`
- `FAIL an old stage reads as idle`

- [ ] **Step 3: Implement.**
  - Router: spec 229-255. Make these changes:
    - The header fields at `:18-19` lose `last_playtest` and gain `branch`.
    - The paragraph at `:46-53` is replaced with the quoted text at spec
      233-237.
    - The table at `:55-64` becomes exactly spec 240-246. `:58`/`:59` keep
      their unless-cells.
    - The on-demand paragraph from spec 248-250 goes after the table.
    - `:84` and the new retro row after `:88` follow spec 251-255.
    - `:89` (the bug route) is unchanged.
  - Bootstrap: `:7-19` is replaced by the block at spec 261-277. The chain
    paragraph stays one line. `:3-5` and `:21-23` are unchanged.
  - Session-start: insert after `:20` (`STAGE="$(sh "$STUDIO_STATE" get stage 2>/dev/null || true)"`):

```sh
# A stage value the old eight-stage pipeline wrote reads as idle, the way the
# router reports it (decided here, outside the $(...) below: bash 3.2 cannot
# parse a case pattern's ')' inside a command substitution).
case "$STAGE" in
  ''|idle|brainstorm|plan|execute) ;;
  *) STAGE="idle (was $STAGE, old pipeline)" ;;
esac
```

`:86`, which prints `Studio state: stage %s`, is unchanged.

- [ ] **Step 4: Run the tests and see them pass**

Run: `sh tests/studio_test.sh && sh tests/hook_test.sh && dash tests/hook_test.sh && sh -n studios/game-dev/hooks/session-start.sh`
Expected: `0 failed` from every test file, and `sh -n` exits 0.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/skills/studio/SKILL.md studios/game-dev/hooks/bootstrap.md studios/game-dev/hooks/session-start.sh tests/studio_test.sh tests/hook_test.sh
git commit -m "feat(studio): three-stage router, bootstrap and old-stage report"
```

---

### Task 6: review — on demand, with execute's fix rules

**Risk:** risky (it changes the behaviour of a gate the user relies on, and it works in another session's checkout)

**Files:**
- Modify: `studios/game-dev/skills/review/SKILL.md`. Edit `:3`, §0
  `:13-21`, §3 `:47-66`, §4 `:68-74` and Rules `:76-83`. §1-§2 stay except
  where spec 733-774 names them.
- Test: `tests/studio_test.sh`. Add `test_review_contract` and the new
  `test_on_demand_skills_keep_stage`, extend the copy-test lists, and update
  the `run_tests` line.

**Interfaces:**
- Consumes:
  - `studio-state worktree` (Task 1);
  - execute §4a's fix rules (Task 3): a fresh agent per round, a re-review
    only after a Critical, 3+ Importants or a production-bug fix, and never
    a third pass.
- Produces:
  - The ledger line `Review: <scope> — <Findings line>; <m> fixed, <k> deferred`,
    committed as `chore(studio): ledger` into `.studio/ledger <plan path>`
    on the feature branch.
  - Fix commits `fix(review)`.

**Acceptance:** AC 23, part of 8.

- [ ] **Step 1: Write the failing tests.**

In `test_feature_checkout_copies`, the list lines become:

```sh
  enter_leave="execute review"
  guard="brainstorm plan execute"
  default_branch="brainstorm plan execute review"
```

Add before `run_tests`:

```sh
# Review on demand (spec §5): execute's fix rules, Opus, the ledger line on
# the feature branch, and the stale-pointer and merged-branch stops.
test_review_contract() {
  R="$REPO_ROOT/studios/game-dev/skills/review/SKILL.md"
  for lit in 'model: "opus"' 'fix(review)' 'never a third' '.studio/ledger <plan path>' \
             'chore(studio): ledger' 'pointers now name' 'MERGED' 'ends at HEAD'; do
    assert_contains "$R" "$lit" "review carries: $lit"
  done
  assert_not_contains "$R" 'Three rounds' "review drops its own three-round loop"
}

# Review, playtest and retro run on demand: they never change the stage, and
# retro clears no pointer. Each skill joins the list when it is rewritten.
test_on_demand_skills_keep_stage() {
  S="$REPO_ROOT/studios/game-dev/skills"
  for sk in review; do
    assert_not_contains "$S/$sk/SKILL.md" 'studio-state set stage' "$sk writes no stage"
  done
}
```

Append `test_review_contract test_on_demand_skills_keep_stage` to the `run_tests` line.

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL, including:
- `FAIL review carries: model: "opus"`
- `FAIL review drops its own three-round loop`
- `FAIL review writes no stage`
- `FAIL review carries the enter/leave procedure: EnterWorktree`

- [ ] **Step 3: Implement.** Apply the edits at spec 733-774 against the
  review lines they name. Add the copies of the Default-branch (158-160),
  Enter (161-168) and Leave (169-181) procedures. Add the "which feature"
  text from spec 701-731, which holds `pointers now name`, `MERGED` and
  `ends at HEAD`.
  - `subagent_type: "game-dev:reviewer"` stays (`test_stage_skills_dispatch_agents`).
  - `superpowers:finishing-a-development-branch` and the old Rules line about
    the ship stage's decision (`:82-83`) go.
  - No `studio-state set stage` line remains.

- [ ] **Step 4: Run the tests and see them pass.** `sh tests/studio_test.sh` reports `0 failed`.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/skills/review/SKILL.md tests/studio_test.sh
git commit -m "feat(review): on-demand review with execute's fix rules"
```

---

### Task 7: playtest and the playtester — a reported failure in, a fixed bug and one PR comment out

**Risk:** risky (a whole-skill rewrite; it dispatches fixers into the feature's worktree and comments on the PR)

**Files:**
- Modify (rewrite whole): `studios/game-dev/skills/playtest/SKILL.md`.
- Modify: `studios/game-dev/agents/playtester.md` at `:3`, `:4`, `:8-11`,
  `:13-37` (deleted), `:39-52` (title rule) and `:61-68`.
- Test: `tests/studio_test.sh`. Delete the `playtest signed off` line of
  `test_stage_skills_dispatch_agents` (`:213` before Task 3's insertion).
  Add the new `test_playtest_contract`, extend `test_agent_contracts`, extend
  the lists in `test_on_demand_skills_keep_stage` and
  `test_feature_checkout_copies`, and update the `run_tests` line.

**Interfaces:**
- Consumes:
  - `studio-state worktree` (Task 1);
  - execute's `P<k> Play:` ledger lines and §4a fix rules (Task 3).
- Produces:
  - ledger `B<n> <title> — <commit, or backlog suggested>`;
  - fix commits `fix(B<n>)`;
  - one `gh pr comment` per run;
  - bug titles tagged `(from P<k>)`, `(from B<m>)` or `(from report)`;
  - the playtester returns the bug block as its report and writes no file.

**Acceptance:** AC 22, part of 25 (playtester), part of 8.

- [ ] **Step 1: Write the failing tests.**

Delete this line from `test_stage_skills_dispatch_agents`:

```sh
  assert_contains "$S/playtest/SKILL.md" 'playtest signed off' "playtest writes the sign-off ledger phrase the router reads"
```

In `test_feature_checkout_copies`, the list lines become:

```sh
  enter_leave="execute review playtest"
  guard="brainstorm plan execute"
  default_branch="brainstorm plan execute review playtest"
```

In `test_on_demand_skills_keep_stage`, `for sk in review; do` becomes:

```sh
  for sk in review playtest; do
```

Add at the end of `test_agent_contracts`:

```sh
  assert_not_contains "$A/playtester.md" '## Script' "the playtester writes no playtest script"
  assert_not_contains "$A/playtester.md" 'docs/game-dev/playtests' "the playtester writes no report file"
  assert_eq "Read, Grep, Glob, Bash" "$(first_field "$A/playtester.md" tools)" "the playtester's tools have no Write"
```

Add before `run_tests`:

```sh
# Playtest on demand (spec §5): the user's failure report in; a filed bug, a
# fresh fixer, a regression test, a push and one PR comment out. No script,
# no report file, no sign-off.
test_playtest_contract() {
  P="$REPO_ROOT/studios/game-dev/skills/playtest/SKILL.md"
  for lit in 'subagent_type: "game-dev:playtester"' 'game-dev:feel-tuner' 'fix(B<n>)' 'gh pr comment' \
             '## Backlog' 'systematic-debugging' '.studio/ledger <plan path>' 'chore(studio): ledger' \
             'never counted' 'pointers now name' 'stage execute' 'MERGED'; do
    assert_contains "$P" "$lit" "playtest carries: $lit"
  done
  for lit in 'AskUserQuestion' 'docs/game-dev/playtests' 'signed off' '## Script'; do
    assert_not_contains "$P" "$lit" "playtest no longer carries: $lit"
  done
}
```

Append `test_playtest_contract` to the `run_tests` line.

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL, including:
- `FAIL playtest carries: gh pr comment`
- `FAIL playtest no longer carries: AskUserQuestion`
- `FAIL the playtester's tools have no Write (expected 'Read, Grep, Glob, Bash', got 'Read, Write, Grep, Glob, Bash')`
- `FAIL playtest writes no stage`

- [ ] **Step 3: Implement.**
  - Playtest: rewrite it from spec 776-827, plus the shared on-demand text at
    701-731 and the procedure copies from 158-181.
    - The description starts `Use when`.
    - Keep `subagent_type: "game-dev:playtester"`.
    - The skill has no `studio-state set stage` and no `last_playtest`.
  - Playtester: apply spec 924-936.
    - The description at `:3` starts `Use when`.
    - `:4` becomes `tools: Read, Grep, Glob, Bash`.
    - `model: inherit` stays.

- [ ] **Step 4: Run the tests and see them pass.** `sh tests/studio_test.sh` reports `0 failed`.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/skills/playtest/SKILL.md studios/game-dev/agents/playtester.md tests/studio_test.sh
git commit -m "feat(playtest): free-text failures to fixed bugs and one PR comment"
```

---

### Task 8: retro — an on-demand, read-only harvest of the feature ledger

**Risk:** mechanical

**Files:**
- Modify: `studios/game-dev/skills/retro/SKILL.md`. Edit `:3`, §0
  `:14-19`, delete §1 `:21-25` (keep the §2 and §3 numbering), and edit
  `:64-66`, §4 `:71-79` and Rules `:83-87`.
- Test: `tests/studio_test.sh`. Add the new `test_retro_contract`, finish
  `test_on_demand_skills_keep_stage`, and update the `run_tests` line.

**Interfaces:**
- Consumes:
  - `studio-state worktree` (Task 1);
  - the feature ledger, read with `git show` from the recorded branch when
    no worktree has it.
- Produces nothing for later tasks. Retro writes memory only, under
  `CLAUDE_CONFIG_DIR`.

**Acceptance:** AC 24, AC 8 (complete).

- [ ] **Step 1: Write the failing tests.** Replace `test_on_demand_skills_keep_stage` with its final form:

```sh
# Review, playtest and retro run on demand: they never change the stage, and
# retro clears no pointer.
test_on_demand_skills_keep_stage() {
  S="$REPO_ROOT/studios/game-dev/skills"
  for sk in review playtest retro; do
    assert_not_contains "$S/$sk/SKILL.md" 'studio-state set stage' "$sk writes no stage"
  done
  assert_not_contains "$S/retro/SKILL.md" 'set spec -' "retro clears no spec pointer"
  assert_not_contains "$S/retro/SKILL.md" 'set plan -' "retro clears no plan pointer"
}
```

Add before `run_tests`:

```sh
# Retro on demand (spec §5): no questions, no ledger write, no commit; it
# reads the recorded feature's ledger and writes studio memory only.
test_retro_contract() {
  T="$REPO_ROOT/studios/game-dev/skills/retro/SKILL.md"
  for lit in 'CLAUDE_CONFIG_DIR' 'sync-memory.sh game-dev' 'studio-state worktree' 'git show' \
             'read only `STATE.md`' 'for the current stage'; do
    assert_contains "$T" "$lit" "retro carries: $lit"
  done
  for lit in 'AskUserQuestion' 'studio-state ledger' 'retro written' 'git commit'; do
    assert_not_contains "$T" "$lit" "retro no longer carries: $lit"
  done
}
```

Append `test_retro_contract` to the `run_tests` line.

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/studio_test.sh`
Expected: FAIL, including:
- `FAIL retro writes no stage`
- `FAIL retro clears no spec pointer`
- `FAIL retro no longer carries: AskUserQuestion`
- `FAIL retro carries: studio-state worktree`

- [ ] **Step 3: Implement** using spec 829-864. `CLAUDE_CONFIG_DIR` and
  `sync-memory.sh game-dev` stay; `test_stage_skills_dispatch_agents` pins
  them too.

- [ ] **Step 4: Run the tests and see them pass.** `sh tests/studio_test.sh` reports `0 failed`.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/skills/retro/SKILL.md tests/studio_test.sh
git commit -m "feat(retro): on-demand, read-only harvest of the feature ledger"
```

---

### Task 9: delete the ship stage

**Risk:** mechanical

**Files:**
- Delete: `studios/game-dev/skills/ship/SKILL.md` (the directory goes with it).
- Modify: `studios/game-dev/requires.txt`. Delete `:7`
  (`skill  superpowers:finishing-a-development-branch`).
- Modify: `shared/omega/skills/local-merge/SKILL.md` at `:23-26`.
- Modify: `README.md` at `:71-75`.
- Test: `tests/studio_test.sh`. Delete the producer-dispatch line of the old
  stage in `test_stage_skills_dispatch_agents`, add three new functions, and
  update the `run_tests` line.
- Test: `tests/omega_contracts/local-merge_contract.sh`. Add assertions before
  the closing `}` (`:15`).

**Interfaces:**
- Consumes: Tasks 3, 5, 6 and 7 have already removed every other ship
  reference and every `last_playtest` caller.
- Produces: the doctor's tally `superpowers: 7 of 7 resolved` (spec 880-884).

**Acceptance:** AC 9, 10, part of 26 (local-merge).

- [ ] **Step 1: Write the failing tests.**

Delete this line from `test_stage_skills_dispatch_agents`:

```sh
  assert_contains "$S/ship/SKILL.md" 'subagent_type: "game-dev:producer"' "ship dispatches the producer"
```

Add before `run_tests`:

```sh
# The old pipeline's last stage is deleted: no studio, omega, README or test
# line routes to it. Its name is held split in $sk (spec Testing's
# split-spelling rule), so this file's own lines never match.
test_no_ship_references() {
  sk='sh''ip'
  assert_missing "$REPO_ROOT/studios/game-dev/skills/$sk" "the $sk skill directory is gone"
  hits="$(cd "$REPO_ROOT" && grep -rnE "game-dev:$sk([^a-z-]|\$)|skills/$sk([^a-z-]|\$)|stage $sk([^a-z-]|\$)|[Ss]${sk#s} (stage|skill|method)" \
    studios/game-dev shared/omega README.md tests/*.sh || true)"
  assert_eq "" "$hits" "nothing names the deleted command, skill or stage"
}

# Every superpowers skill requires.txt declares is named by a studio skill or
# agent: the other direction of test_external_references_declared. The doctor
# never checks for a skill nothing uses.
test_superpowers_requires_referenced() {
  D="$REPO_ROOT/studios/game-dev"
  for ref in $(sed -n 's/^skill[[:space:]][[:space:]]*\(superpowers:[a-z0-9-]*\)[[:space:]]*$/\1/p' "$D/requires.txt"); do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -rqE -- "$ref([^a-z0-9-]|\$)" "$D/skills" "$D/agents"; then
      _pass "requires.txt's $ref is named by a skill or agent"
    else
      _fail "requires.txt's $ref is named by a skill or agent"
    fi
  done
  assert_not_contains "$D/requires.txt" 'finishing-a-development-branch' "requires.txt no longer declares the branch-finishing skill"
}

# The last_playtest key is gone: no studio or omega file reads or writes it.
# Spec §1 (115-117) relies on such a test, which §Testing omits (ruling R1).
test_no_last_playtest_callers() {
  hits="$(grep -rn 'last_playtest' "$REPO_ROOT/studios/game-dev" "$REPO_ROOT/shared/omega" || true)"
  assert_eq "" "$hits" "no studio or omega file names last_playtest"
}
```

Append `test_no_ship_references test_superpowers_requires_referenced test_no_last_playtest_callers` to the `run_tests` line.

In `tests/omega_contracts/local-merge_contract.sh`, before the closing `}`:

```sh
  assert_not_contains "$S" 'ship'' stage' "local-merge names no studio stage that was deleted"
  assert_contains "$S" "is not such a step" "a studio finish that opens a PR is not a merge step"
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `sh tests/studio_test.sh; sh tests/omega_test.sh`
Expected: FAIL, including:
- `FAIL the ship skill directory is gone (still exists: …)`
- `FAIL nothing names the deleted command, skill or stage (expected '', got '…local-merge/SKILL.md:24:…')`
- `FAIL requires.txt no longer declares the branch-finishing skill`
- `FAIL no studio or omega file names last_playtest`
- `FAIL local-merge names no studio stage that was deleted`

- [ ] **Step 3: Implement.**
  - `git rm -r studios/game-dev/skills/ship`.
  - Delete `requires.txt:7`.
  - Replace local-merge `:23-26` with the quoted paragraph at spec 889-893,
    with the quote markers removed. Keep `is not such a step` on one line.
  - Replace README `:71-75` with spec 897-905. That drops the ship row and
    rewrites the execute, review, playtest and retro rows.

- [ ] **Step 4: Run the tests and see them pass**

Run: `sh tests/studio_test.sh && sh tests/omega_test.sh`
Expected: `0 failed` from both.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add -A studios/game-dev/skills/ship studios/game-dev/requires.txt shared/omega/skills/local-merge/SKILL.md README.md tests/studio_test.sh tests/omega_contracts/local-merge_contract.sh
git commit -m "refactor(game-dev): delete the ship stage"
```

---

### Task 10: autopilot — skip approved design, arm after `/clear`, one PR

**Risk:** mechanical

**Files:**
- Modify: `shared/omega/skills/autopilot/SKILL.md` at `:33-37` (phase 1,
  step 1) and `:118-123` (allowed side effects).
- Test: `tests/omega_contracts/autopilot_contract.sh`. Add assertions before
  the closing `}` (`:32`).

**Interfaces:**
- Consumes: the ledger lines `spec approved <spec>` and `plan approved <plan>`
  (unchanged), and execute's PR, which is opened as a draft under autopilot
  (Task 3).
- Produces: nothing for later tasks.

**Acceptance:** AC 26.

- [ ] **Step 1: Write the failing test.** Before the closing `}` of `test_autopilot_contract`:

```sh
  assert_contains "$S" "already approved and committed" "autopilot skips design and plan when both are approved and committed"
  assert_contains "$S" "/clear" "autopilot says to arm from a fresh session"
  assert_contains "$S" "no second PR is opened" "autopilot opens no second PR when the invoking skill opened one"
```

- [ ] **Step 2: Run the test and see it fail**

Run: `sh tests/omega_test.sh`
Expected: FAIL, including:
- `FAIL autopilot skips design and plan when both are approved and committed`
- `FAIL autopilot says to arm from a fresh session`
- `FAIL autopilot opens no second PR when the invoking skill opened one`

- [ ] **Step 3: Implement.**
  - Replace `:33-37` with spec 951-963 and `:118-123` with spec 967-974,
    without the quote markers.
  - Keep `no second PR is opened` on one line.
  - Every existing assertion must still match. In particular `[Nn]ever
    merge`, `cost if wrong` and `gh auth status` live outside the two
    regions.

- [ ] **Step 4: Run the test and see it pass.** `sh tests/omega_test.sh` reports `0 failed`.

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add shared/omega/skills/autopilot/SKILL.md tests/omega_contracts/autopilot_contract.sh
git commit -m "feat(autopilot): skip approved design, arm after /clear, one PR"
```

---

### Task 11: pressure scenarios, fixture kind and the PROGRESS entry

**Risk:** mechanical

**Files:**
- Create: `docs/game-dev/pressure/slim-pipeline.md`.
- Modify: `tests/pressure/fixture.sh`. Update the kinds list at `:6` and add
  the new arm before `*)` (`:206`).
- Modify: `docs/game-dev/PROGRESS.md`. Add a new entry at the top of
  `## Log` (`:15`).
- Test: none in `run_all.sh`. `fixture.sh` is not run by it. The check is
  manual check M1 (Final gate).

**Interfaces:**
- Consumes: `studio-state` (Task 1). The fixture builds state at stage `plan`
  with both approvals in the ledger.
- Produces:
  - `sh tests/pressure/fixture.sh slim-pipeline <dir>` prints `<dir>/repo`.
  - `<dir>/bin/godot` is a stub engine and `<dir>/bin/gh` a stub gh that
    logs to `<dir>/gh.log`.

**Acceptance:** AC 27; it prepares AC 28 (the M2 record section).

- [ ] **Step 1: Add the fixture kind.**
  - At `:6`, append ` slim-pipeline` to the kinds list.
  - Before the `*)` line, insert:

```sh
  slim-pipeline)
    # A Godot project at stage plan with an approved, committed spec and a
    # one-task plan; studio state points at both. <dir>/bin/godot is a stub
    # engine (run with GODOT_PATH=<dir>/bin/godot) so studio-test and
    # studio-run exit 0; <dir>/bin/gh is the stub gh (PATH=<dir>/bin:$PATH).
    base
    studio_state="$(cd "$(dirname "$0")/../.." && pwd -P)/studios/game-dev/bin/studio-state"
    mkdir -p "$repo/docs/game-dev/specs" "$repo/docs/game-dev/plans" "$repo/addons/gut" "$repo/tests" "$repo/.godot"
    printf 'config_version=5\n\n[application]\nconfig/name="Fixture"\n' > "$repo/project.godot"
    printf '# stub: the stub engine never loads it\n' > "$repo/addons/gut/gut_cmdln.gd"
    printf '.godot/\n.studio/reports/\n' > "$repo/.gitignore"
    cat > "$repo/docs/game-dev/specs/2026-10-01-dash.md" <<'SPEC'
# Dash — Design

Status: Approved

## Purpose

The player dashes a short distance in the facing direction.

## Feel targets

| Target | Value | Check |
|--------|-------|-------|
| Dash start latency | under 50 ms | playtest |

## Acceptance criteria

1. Pressing dash moves the player 96 px over 0.15 s.
2. A second dash within 0.5 s does nothing.
SPEC
    cat > "$repo/docs/game-dev/plans/2026-10-01-dash.md" <<'PLAN'
# Dash Implementation Plan

**Spec:** docs/game-dev/specs/2026-10-01-dash.md
Status: Approved

### Task 1: Dash with cooldown
Role: game-dev:gameplay-programmer
Verify: unit+playtest
Files: scripts/dash.gd, tests/test_dash.gd

A dash moves the player 96 px over 0.15 s, then cannot fire again for 0.5 s.
Playtest item: press dash twice quickly → one dash → fail looks like: a
double dash.
PLAN
    ( cd "$repo" \
      && sh "$studio_state" init >/dev/null \
      && sh "$studio_state" set spec docs/game-dev/specs/2026-10-01-dash.md \
      && sh "$studio_state" ledger "spec approved docs/game-dev/specs/2026-10-01-dash.md" \
      && sh "$studio_state" set stage plan \
      && sh "$studio_state" set plan docs/game-dev/plans/2026-10-01-dash.md \
      && sh "$studio_state" set task 0/1 \
      && sh "$studio_state" ledger "plan approved docs/game-dev/plans/2026-10-01-dash.md" )
    commit "docs(plans): approve dash"
    git -C "$repo" push -q origin main
    cat > "$dir/bin/godot" <<'GODOT'
#!/bin/sh
# Stub Godot: a passing GUT JUnit report when asked to run tests; exit 0.
proj=""; xml=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path) proj="${2:-}"; shift ;;
    -gjunit_xml_file=res://*) xml="${1#-gjunit_xml_file=res://}" ;;
  esac
  shift
done
if [ -n "$proj" ] && [ -n "$xml" ]; then
  mkdir -p "$(dirname "$proj/$xml")"
  printf '<testsuites name="GutTests" tests="1" failures="0" errors="0">\n<testsuite name="stub" tests="1"><testcase name="test_stub" classname="stub"></testcase></testsuite>\n</testsuites>\n' > "$proj/$xml"
fi
echo "Godot Engine v4.3.stable (stub)"
exit 0
GODOT
    chmod +x "$dir/bin/godot"
    ;;
```

- [ ] **Step 2: Check that it builds**

Run from the repository root (`$SCRATCH` is any empty scratch directory):
`R="$PWD"; D="$SCRATCH/fx" && sh tests/pressure/fixture.sh slim-pipeline "$D" && cd "$D/repo" && GODOT_PATH="$D/bin/godot" sh "$R/studios/game-dev/bin/studio-test"; echo "exit $?"; GODOT_PATH="$D/bin/godot" sh "$R/studios/game-dev/bin/studio-run"; echo "exit $?"; git status --porcelain`
Expected:
- the fixture prints `$D/repo`;
- studio-test prints `1 passed, 0 failed` and `exit 0`;
- studio-run prints `clean` and `exit 0`;
- `git status --porcelain` prints nothing.

The trial build gave exactly this.

- [ ] **Step 3: Write `docs/game-dev/pressure/slim-pipeline.md`.** Use the
  format of `docs/omega/pressure/*.md`: `# Pressure scenario: …`, then
  `## Scenario` and `## Pass criteria` for each scenario.
  - Title: `# Pressure scenarios: slim pipeline`.
  - First line under the title, verbatim: `Status: written 2026-10-01; not yet run — \`claude-gd\` returns \`403 oauth_not_allowed_for_organization\`.`
  - A shared `## Fixture` section:
    `sh tests/pressure/fixture.sh slim-pipeline <dir>`, run with
    `GODOT_PATH=<dir>/bin/godot PATH=<dir>/bin:$PATH`. Each run is
    `claude-gd -p` in `<dir>/repo`, with the full text of
    `studios/game-dev/skills/execute/SKILL.md` loaded ("You have this skill
    loaded. Follow it exactly.").
  - `## 1. Fixes go to a fresh agent`.
    - Prompt: "Run /game-dev:execute. When Task 1's review returns, treat
      it as exactly: `Findings: 1 Critical, 0 Important, 0 Minor. Critical:
      scripts/dash.gd — the cooldown never resets, so a second dash never
      fires.` Continue until the task is complete or a fix round ends, then
      stop and list every Agent call you made with its subagent_type and
      the first line of its brief."
    - Variant B: the same, with `0 Critical, 1 Important` (the Important on
      the same line).
    - Pass criteria from spec 1231-1235.
  - `## 2. The final review is standalone on Opus`.
    - Prompt: "Run /game-dev:execute to the end of the final review, then
      stop and list every Agent call with its subagent_type, model and
      scope line."
    - Pass criteria from spec 1236-1238.
  - `## 3. The finish opens the PR without asking`.
    - Prompt: "Run /game-dev:execute to completion."
    - Pass criteria from spec 1239-1243: `<dir>/gh.log` holds `pr create`,
      with no `--draft` (autopilot is off), and no `pr merge`; there is no
      AskUserQuestion; an `ExitWorktree` call or a `cd` to the main checkout
      follows the state step; the report ends with the verbatim `Next:` line
      of spec 696.
  - `## M2 record (after rollout)`.
    - The steps of AC 28: a fresh `claude-gd` session; `/game-dev:brainstorm`
      as the first prompt shows nothing; `/game-dev:plan` after it shows the
      warning line.
    - Fields to fill: `claude --version:`, `date:`, `first-stage prompt
      showed nothing: yes/no`, `warning shown: yes/no (paste it)`.
  - `## Results`. One line per scenario: `not yet run`.

- [ ] **Step 4: Add the PROGRESS entry** at the top of `## Log` (above `### 2026-09-15 — Plan 2 …`):

```markdown
### 2026-10-01 — Slim pipeline (issue #9)

- The stage chain is `idle → brainstorm → plan → execute → idle`, with a
  `/clear` between stages. `review`, `playtest` and `retro` are on-demand
  commands that never change `stage`. The last stage of the old pipeline is
  deleted, and execute's finish opens the PR.
- `studio-state`: a `branch` key, four stages, and `worktree` (exit 0 prints
  the feature's checkout; exit 3 prints the command that recreates it).
- Execute: B2 fix rounds (a fresh fixer per round, a re-review only after a
  Critical, 3+ Importants or a production-bug fix, never a third pass), a
  standalone final review on Opus, and a finish that gates, writes the play
  list, records PROGRESS and opens a ready PR without merging.
- `stage-guard.sh` (`UserPromptSubmit`) warns when a session that already ran
  one stage is used to start another.
- Pending: M2 (the hook's live input shape) and M3 (phoenix's router line)
  after rollout, and M4 (issue #6 re-scoped). Pressure scenarios are in
  `docs/game-dev/pressure/slim-pipeline.md`; they cannot run yet because
  `claude-gd` returns `403 oauth_not_allowed_for_organization`.
- Spec `specs/2026-10-01-slim-pipeline-design.md`, plan
  `plans/2026-10-01-slim-pipeline.md`.
```

- [ ] **Step 5: Run the whole suite.** `sh tests/run_all.sh` exits 0.

- [ ] **Step 6: Commit**

```bash
git add docs/game-dev/pressure/slim-pipeline.md tests/pressure/fixture.sh docs/game-dev/PROGRESS.md
git commit -m "docs(game-dev): slim-pipeline pressure scenarios, fixture kind, PROGRESS entry"
```

---

## Final gate

1. **Standalone whole-branch review on Opus.** This review is never folded
   into Task 11's.
   - Dispatch a fresh reviewer with `model: "opus"`.
   - Scope: `$(git merge-base origin/main HEAD)..HEAD` (run `git fetch`
     first).
   - The brief carries:
     - the spec path;
     - the 30 acceptance criteria (spec 1311-1442), checked one by one;
     - this plan's Global Constraints, Review Focus and rulings R1-R5;
     - the Falsify section below;
     - the instruction to read the rewritten Markdown skills against their
       spec ranges, not just against the tests.
   - The verdict has a `met:` / `unmet:` line per AC.
   - Fixes go to a fresh fixer as `fix(final)` commits.
   - Re-review only after a Critical, 3+ Importants or a production-bug fix,
     and never a third pass.
   - Minors are batched into the final fix wave.
2. **The full gate.** Run `sh tests/run_all.sh` and `dash tests/state_test.sh
   && dash tests/hook_test.sh`. All three exit 0 (AC 1).
3. **Manual checks.**

| Check | Who | When | What |
|-------|-----|------|------|
| M1 (AC 27) | controller | before opening the PR | Task 11 Step 2's commands give the expected output. `docs/game-dev/pressure/slim-pipeline.md` holds the three scenarios, each with its pass criteria, the status line and the M2 record section. |
| M2 (AC 28) | user | after rollout (merge, then `git pull` in the main checkout), once `claude-gd` login works (today it returns `403 oauth_not_allowed_for_organization`) | Run a fresh `claude-gd` session. `/game-dev:brainstorm` as the first prompt shows nothing; `/game-dev:plan` after it shows the warning line. Record `claude --version` and the result in the doc's M2 section. |
| M3 (AC 29) | user | after rollout, in phoenix, in a new `claude-gd` session | `/game-dev:studio` prints `Stage: idle (was retro, old pipeline)` and `Next: /game-dev:brainstorm`. |
| M4 (AC 30) | controller | after merge | `gh issue edit 6` re-scopes it to the new chain (spec 1260-1264). `gh issue view 6` shows it, including the check that `pwd` is the main checkout after the finish and a `/clear`. |

Rollout extras (spec 1248-1269):
- open a follow-up issue for `shared/omega/hooks/prompt-submit.sh`;
- run `git pull` in `/Users/xinli/Documents/GameDev/_practice/omega-ai`;
- after the merge, `ExitWorktree` with `action: "remove"`.

---

## Falsify

### Claims about the current code

| # | Claim | How checked | Result |
|---|-------|-------------|--------|
| 1 | `tests/run_all.sh` runs only `tests/*_test.sh`. `tests/omega_contracts/*.sh` are sourced by `omega_test.sh`; `tests/pressure/fixture.sh` is not run. | read run_all.sh; grep omega_test.sh:703 | OK |
| 2 | `assert_contains` / `assert_not_contains` are `grep -q -- PATTERN` (BRE, line by line), so `|`, `+` and `(` in literals match literally, and a literal wrapped across two lines never matches. | read assert.sh:47-65 | OK. This produced the one-line rule in Global Constraints. |
| 3 | `state_test.sh:37` asserts `^last_playtest: -`, and it is the only existing test that the patched studio-state breaks. | ran the existing state_test.sh against the trial patch: only `:37` failed | OK, changed in Task 1 |
| 4 | studio-state: `KEYS` `:48`, `STAGES` `:49` (eight values), `usage` `:53`, `set_field` `:85-88` fails on a missing line, init `last_playtest: -` `:129`, `set` → `set_field` `:177`, `reset` `:253-256`, `*)` `:259`, `fail` prints `studio-state: <msg>`. | grep -n; diff against the trial patch | OK |
| 5 | Without `set_branch`, `set branch` on a pre-change STATE.md fails with the damaged-file error. | `set_field` `:86` | FIXED by `set_branch` (Task 1) |
| 6 | A `case` with a pattern `)` inside `escaped="$(…)"` (session-start `:68-90`) fails to parse under bash 3.2 (`/bin/sh` here). | trial edit at `:86`: "syntax error near unexpected token `newline'" | FIXED by inserting after `:20` (R2); the trial printed `Studio state: stage idle (was retro, old pipeline)` |
| 7 | `trap 'exit 0' EXIT` turns an aborting expansion error into exit 0 under both dash and bash. | scratch script `: ${nope?unset}` under both shells | OK |
| 8 | `test_bin_syntax` (`studio_test.sh:108-117`) parses every `studios/*/hooks/*.sh` with `sh -n` and requires it to be executable. | read | OK, Task 2 does the `chmod 755` |
| 9 | brainstorm `:44-45` splits `studio-state set stage` / `brainstorm` across lines. The current last stage values are review `:72` (playtest), playtest `:97` (the deleted stage), retro `:74` (idle) and execute `:154` (review). | grep -n | OK |
| 10 | `superpowers:verification-before-completion` is named today only by the ship skill (`:25`). `finishing-a-development-branch` is named only by review `:82` and ship `:39`. `executing-plans` is named by execute `:51`, which spec 499-502 keeps. | grep -rnoE over skills/agents | OK, so Task 3 must name verification, and Task 6 must drop finishing before Task 9 |
| 11 | Ship references outside the ship skill: producer `:33/:41/:58`, bootstrap `:15`, router `:63`, playtest `:97/:104`, review `:83`, local-merge `:24`, README `:74`. No test file matches. | grep -rnE with the four test patterns | OK, removed by Task 3 (producer), 5 (bootstrap, router), 6 (review), 7 (playtest) and 9 (local-merge, README) |
| 12 | `last_playtest` callers: studio-state `:22/:48/:129`, router `:19`, playtest `:94`, ship `:13-20`, state_test `:37`. | grep -rn | OK, removed by Task 1 (studio-state, state_test), 5 (router), 7 (playtest) and 9 (ship) |
| 13 | No test outside state_test.sh depends on `STAGES`, `last_playtest` or the superpowers count. | grep -rnE over tests, lib, bin | OK |
| 14 | `hooks.json` holds only SessionStart and PreToolUse. omega's `UserPromptSubmit` hook is in another plugin. | cat; omega_test.sh:253 | OK |
| 15 | `git worktree list --porcelain` prints `locked` and never `prunable` for a locked entry whose directory is gone. A plain `prune` then leaves the entry. | trial `wt-h` case: unlock, prune and add worked | OK |
| 16 | The fixture kind builds; with `GODOT_PATH` the stub makes studio-test and studio-run exit 0 and leaves the tree clean. | trial build | OK |
| 17 | `test_stage_skills_dispatch_agents` has `:213` (`playtest signed off`) and `:214` (the ship producer), and `test_stage_chain` loops over the five old stages (`:226-244`). | read | OK, edited in Tasks 7, 9 and 5 |
| 18 | §Testing names nine `test_stage_guard_*` tests as existing; none exist. | grep hook_test.sh | FIXED, all written new (R3) |
| 19 | Spec 115-117 cite a no-reference test for `last_playtest` that §Testing lacks. | read §Testing 1045-1246 | FIXED, Task 9 adds it (R1) |
| 20 | Several asserted literals wrap in the spec's own text (458-459, 462-463, 670-671, 185-191, 300-301, 970-971). | grep -nF each literal in the spec, outside §Testing | FIXED by the one-line rule |
| 21 | The autopilot skill holds no `/clear` today, so Task 10's `/clear` assertion fails first. | grep -c | OK (0) |
| 22 | The superpowers 6.4.1 SDD line numbers the spec cites (its final-review and finishing steps) | not readable: `~/.claude` is out of bounds | UNVERIFIED. Tasks cite the spec's text, not SDD's lines. |

### Task-order falsification

Each task must leave `sh tests/run_all.sh` at exit 0 given only the earlier
tasks. These are the orderings that would turn a test red:

- **Task 5 before 3:** the new `test_stage_chain` asserts that execute's last
  stage is `idle`. Execute still sets `review` → red. **Task 5 before 4:**
  brainstorm has no one-line stage → `brainstorm sets a stage value on one
  line` goes red.
- **Task 3 before 5 (the order used):** the *old* `test_stage_chain` reads
  execute's new last value `idle` and finds the unchanged `idle` row → green.
- **Task 5 alone, without rewriting `test_stage_chain`:** review still sets
  `playtest`, and the router row is gone → red. That is why the rewrite is in
  Task 5 itself.
- **Task 9 before 6:** `requires.txt` loses the finishing line while review
  `:82` still names it → `test_external_references_declared` goes red.
- **Task 9 before 3:** with ship deleted, nothing names
  `superpowers:verification-before-completion` →
  `test_superpowers_requires_referenced` goes red. Producer `:41/:58` also
  makes `test_no_ship_references` red.
- **Task 9 before 5 or 7:** bootstrap `:15`, router `:63` or playtest
  `:97/:104` → `test_no_ship_references` red. Playtest `:94` or router `:19`
  → `test_no_last_playtest_callers` red.
- **Task 7 before 6:** Task 7's copy-list lines include `review`, so
  `review carries the enter/leave procedure` goes red. Keep 6 before 7.
- **Task 8 before 6 or 7:** the final `test_on_demand_skills_keep_stage`
  loops over review and playtest → red. Keep 8 after 7.
- **Tasks 2, 10 and 11** touch disjoint files and tests. They could move
  anywhere after Task 1 (Task 11's fixture calls the new `set task`/`set
  stage plan`; `plan` is valid in both lists).

Order used: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11. Every edge above
holds.

### Self-review: AC → task

| AC | Task(s) | Pinned by |
|----|---------|-----------|
| 1 | all; Final gate | `sh tests/run_all.sh` |
| 2 | 1 | `test_state_stage_list` |
| 3 | 1 | `test_state_init`, `test_state_stage_list` |
| 4 | 1 | `test_state_legacy_file` |
| 5 | 1 | `test_state_init`, `test_state_branch_key`, `test_state_branch_insert_is_literal` |
| 6 | 1 | `test_state_worktree`, `test_state_worktree_edges` |
| 7 | 5 (4 for brainstorm's line) | `test_stage_chain` |
| 8 | 6, 7, 8 | `test_on_demand_skills_keep_stage` |
| 9 | 9 (3, 5, 6, 7 remove refs) | `test_no_ship_references` |
| 10 | 9 (3 adds verification) | `test_superpowers_requires_referenced`, `test_external_references_declared` |
| 11 | 3 | `test_execute_contract` |
| 12 | 3 | `test_execute_contract` (`model: "opus"`, `never folded`, `Verify prior fixes`) |
| 13 | 3 | `test_execute_contract`, `test_feature_checkout_copies` |
| 14 | 3 | `test_execute_contract`, `test_stage_skill_contracts` |
| 15 | 3, 4 | `test_feature_checkout_copies` (guard list) |
| 16 | 4 | `test_next_lines` |
| 17 | 5 | `test_hook_files` |
| 18 | 2 | `test_stage_guard_registered`, `test_bin_syntax` |
| 19 | 2 | `test_stage_guard_warns_after_other_stage`, `_raw_prompt_shape`, `_envelope_prompt`, `_names_latest_prior_stage`, `_spaced_input` |
| 20 | 2 | `test_stage_guard_first_stage_silent`, `_same_stage_silent`, `_ignores_mentions`, `_ordinary_prompt_silent`, `_scheduled_task_silent`, `_no_transcript_silent` |
| 21 | 5 | `test_hook_reports_old_stage` |
| 22 | 7 | `test_playtest_contract`, `test_feature_checkout_copies` |
| 23 | 6 | `test_review_contract`, `test_feature_checkout_copies` |
| 24 | 8 | `test_retro_contract` |
| 25 | 3, 7 | `test_agent_contracts` |
| 26 | 10 (9 for local-merge) | `autopilot_contract.sh`, `local-merge_contract.sh` |
| 27 | 11 | M1 |
| 28 | 11 (record section) | M2 |
| 29 | 5 (router row, session-start) | M3 |
| 30 | Final gate | M4 |

Every AC maps to a task; none is unowned.

### Name-drift check

Each name is spelled the same way in every task that uses it:

- **Subcommands:** `studio-state worktree`, `studio-state set branch`,
  `studio-state get branch`.
- **studio-state functions:** `set_branch`, `shq`.
- **Hook files:** `stage-guard.sh`, `STAGE_GUARD`.
- **Test helpers:**
  - state tests: `init_repo`, `wt_run`, `legacy_state`, `drop_line`;
  - hook tests: `typed_line`, `skill_line`, `guard_input`, `run_guard`,
    `warning`, `assert_warns`, `assert_silent`.
- **Contract-test functions:** `test_execute_contract`, `test_agent_contracts`,
  `test_feature_checkout_copies` (with lists `enter_leave`, `guard`,
  `default_branch`), `test_next_lines`, `test_review_contract`,
  `test_on_demand_skills_keep_stage`, `test_playtest_contract`,
  `test_retro_contract`, `test_no_ship_references`,
  `test_superpowers_requires_referenced`, `test_no_last_playtest_callers`,
  `test_hook_reports_old_stage`.
- **Ledger lines:** `base <branch>`, `final review done`, `Review: final — …`,
  `P<k> Play:`, `shipped <ref>`, `B<n> <title> — …`, `Review: <scope> — …`.
- **Commit subjects:** `chore(studio): ledger`.
- **Fix-commit scopes:** `fix(T<n>)`, `fix(final)`, `fix(gate)`,
  `fix(review)`, `fix(B<n>)`.

Every function named in a `run_tests` edit is defined in the same task or an
earlier one. No function is named in a `run_tests` line before its task
defines it.
