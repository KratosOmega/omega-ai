# A Stage Pointer per Checkout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Draft (2026-10-05; two rulings needed, see "Rulings needed" at the end)

**Goal:** Give every checkout its own stage pointer. A linked worktree with no
pointer reads "no story in this checkout". A story crosses checkouts only by a
locked, self-healing move (`handoff`, `take`, or the one-time `adopt`).
`milestone` stays project-wide. `stories` lets the main checkout find every live
story, and the single-plan overnight runner follows its story into the worktree.

**Architecture:**
- `studios/game-dev/bin/studio-state` gains:
  - per-checkout resolution;
  - auto-create through the one `init --local` function;
  - the project-wide `milestone`;
  - one mutex (`<root>/.studio/state.mutex`) on every non-STUDIO_STORY write. It is taken through the shared `mx_take`/`mx_drop` in `overnight-runs.sh`, sourced, never copied;
  - the moves (`handoff`, `take`, restore, adopt), with a `handing` intent line and self-heal;
  - the story-switch guard with `--force` and exit 4;
  - `stories`, and `worktree`'s candidate rule.
- `studio-overnight` gains `story_dir()`. Its `state()`, `feature_dir()`, unit cwd, Resume line and channel ledger read through it.
- The hooks and seven skills change text only. Pins live in per-task test files so that wave-mates stay disjoint.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2, Linux `dash`), git ≥ 2.38, BSD/GNU sed and awk. No new dependencies.

**Spec:** `docs/game-dev/specs/2026-10-05-per-story-pointer.md` (approved 2026-10-05, including D1). Cited as `AC<n>`. Its file:line references point at #39's branch (0286a47). Every target below is re-anchored at this plan's base.

Story: #42 (GitHub issue). Branch `issue-42-per-story-pointer`. omega-ai has no Jira, so the branch carries no `KAN-` prefix.

**Base:** 3994275, which is origin/main with #39 and #41 merged. Line numbers below are taken at that commit. Relocate each one with its `grep -n` pattern.

**Prerequisite met:** #39 merged the race-free reap. `mx_take` (`overnight-runs.sh:97-107`) reaps through `mx_reap` (:108-125), which works under a `mkdir "$1.reap"` lock, re-checks the same dead pid, and breaks a reap lock older than 5 s. #39's regression `test_mutex_reap_race` is at `tests/overnight_runs_test.sh:119`. The spec's contingency ("#42's first task fixes `mx_take`") therefore does not apply. #42 reuses `mx_take` by sourcing it. Task 1 only adds the stale-reap-lock test that the spec says the plan must name (AC27).

**Review policy (user CLAUDE.md):**
- Each task carries `Spec:`, `Review: task|final`, `Wave:` and `Touches:` under its heading.
- `Review: task` means a per-task review on Opus (`model: "opus"`). These go to the risky seams: studio-state resolution and lock (T2), the guard (T3), the moves and self-heal (T4), stories/worktree (T5), and the runner follow (T11).
- Mechanical skill-text, hook, pin and memory tasks are `Review: final`.
- Minor findings are batched into the final fix wave. Every fix round goes to a fresh fixer, given the findings and the diff range.
- Re-review only after a Critical, three or more Importants, or a production-bug fix. Never a third pass.
- The final review is a standalone whole-branch review on Opus (T13), then the full gate.
- One task = one implementer.
  - The implementers of one wave run in parallel inside the story worktree, and their Touches are disjoint, tests included.
  - Each implementer commits only its own paths: `git commit -m '<msg>' -- <paths>`.
  - Hand-backs are 1.5k characters or less, with the full report in a file.
- Suites:
  - Each task runs the suites it names. `tests/overnight_test.sh` and `tests/overnight_lanes_test.sh` never run at the same time: only T12 (wave 3) runs lanes, and only T11 (wave 5) runs overnight.
  - The integrated full gate runs once, after the final fix wave.

---

## Prerequisites — re-run the anchor greps

Before a task edits a file, its implementer re-runs the greps for the anchors it touches. Earlier waves move the lines, so trust the pattern, not the number.

```sh
SS=studios/game-dev/bin/studio-state; SO=studios/game-dev/bin/studio-overnight
CH=studios/game-dev/bin/overnight-channel.sh; RN=studios/game-dev/bin/overnight-runs.sh
grep -n '^_wt=\|^STATE="\$STATE_ROOT\|^LINKED=\|^STORY=' "$SS"                 # 40 54 60 61
grep -n '^usage()\|^fail()\|^write_idle_state()\|^need_state()' "$SS"           # 72 77 86 102
grep -n '^write_field()\|^set_field()\|^set_branch()\|^field()\|^ledger_file()' "$SS"  # 114 126 134 156 168
grep -n '^  init)\|^  get)\|^  set)\|^  show)\|^  ledger)\|^  check)\|^  reset)\|^  worktree)' "$SS"  # 191 245 251 270 279 293 364 382
grep -n '^mx_take()\|^mx_reap()\|^mx_drop()\|^runs_kv()' "$RN"                  # 99 113 127 9
grep -n '^state()\|^take_lock()\|^START_DIR=\|^preflight()' "$SO"               # 40 199 401 415
grep -n '^ledger_of()\|^feature_dir()\|^snapshot()\|^reg_write()\|^start_session()' "$SO"  # 547 550 560 976 1002
grep -n '^write_report()\|## Resume\|^story_units()\|^single_status()\|^project_status()' "$SO"  # 1108 1132 1212 1527 1565
grep -n '^chan_find_run()\|^chan_ledger()' "$CH"                                # 105 186
grep -n 'get stage\|Studio state: stage' studios/game-dev/hooks/session-start.sh # 20 94
grep -n '"branch "\*)\|"wtledger "\*)' tests/overnight_test.sh                   # 50 53
grep -n 'porcelain\|git clean -fdq' studios/game-dev/bin/overnight-lanes.sh | sed -n '1,40p'  # FINAL_W check 1612, clean 1616
```

---

## Global Constraints

These are the spec's values, verbatim. A task that touches one of them uses it exactly.

**Paths:**
- main pointer: `<root>/.studio/STATE.md`;
- local pointer: `<work root>/.studio/STATE.md`;
- mutex: `<root>/.studio/state.mutex` (AC27);
- exclude lines, appended once each to `<common git dir>/info/exclude` with the missing-final-newline repair: `.studio/STATE.md` and `.studio/state.mutex`.

**Move records** (Terms): TAB-separated `key=value` fields, with `path=` always last:
- `- <date> handing<TAB>spec=<spec><TAB>plan=<plan><TAB>branch=<branch><TAB>path=<path>`
- `- <date> handed<TAB>…` (the same fields; adopt adds `via=adopt` before `path=`)
- `- <date> void<TAB>…<TAB>reason=<why><TAB>path=<path>`
- other lines: `- <date> restored <spec> from the handed line` and `- <date> forced <key>=<value> over <old spec> (stage <s>)`. A forced move uses `handoff` as the key.

**Exit codes:**
- 0 ok;
- 1 as today;
- 3 `worktree`: the branch exists, unchecked;
- 4 refused. The usage text and header `Exit:` line read: `4 refused: a story switch in this checkout, a story write after the story moved away, or a take/handoff onto another story or the wrong spec (--force overrides where stated)`.

**Fixed texts** (quote exactly):
- `(no story in this checkout)` — `show` in a pointer-less worktree (AC3);
- `no story in this checkout` — `reset` and `check --rebuild` there (AC7);
- `studio-state: no feature branch recorded`;
- `init --local: <path> already exists`;
- `studio-state: this is a linked worktree — its stage pointer is created on its first write; to create it now, run studio-state init --local` (AC9);
- `studio-state: no main pointer — run studio-state init in <root>` (AC11);
- `studio-state: <path> is tracked by git — a tracked STATE.md is never a stage pointer; run git rm --cached .studio/STATE.md on this branch` (AC4);
- `handed <spec> to <path>` (AC12);
- AC15:
  - `studio-state: <path> has a detached HEAD — check out the story's branch there first`;
  - `studio-state: a TAB in <field> cannot be recorded`;
  - `studio-state: <path> holds story <spec slug> (stage <s>) — finish or reset it there first, or pass --force`;
  - `studio-state: <spec slug> is in both <path> (stage <s>) and the main checkout (stage <s>) — reset it in one of them, or pass --force`;
- AC16:
  - `<spec> is already in this checkout`;
  - `studio-state: the main checkout's story is <main spec>, not <spec>`;
  - `studio-state: <spec> is being executed in <path> — continue it there`;
- AC21:
  - `studio-state: this checkout's story is on <branch>, which is checked out in <other> — switch this checkout back to <branch>`;
  - `studio-state: this checkout's story is on <branch>, but <current branch, or a detached HEAD> is checked out here — switch this checkout back to <branch>`;
- AC22:
  - `studio-state: <n> stories fit — choose one:` and the candidate lines `<path>\t<branch>\t<spec>\t<state>`;
  - the removed form `<path>\t<branch>\t<spec>\tremoved\t<command>`, where the command is `git worktree add <path> <branch> && (cd <path> && studio-state take <spec>)`;
- AC24:
  - `studio-state: this checkout is on story <spec slug> (stage <s>, task <t>) — finish or reset it first, start the new story in its own worktree (EnterWorktree), or pass --force`;
  - `studio-state: this checkout holds no story — <spec> moved to <path> on <date>; continue it there, start a new story with /game-dev:brainstorm, or pass --force`;
- AC27 and AC14:
  - `studio-state: <root>/.studio/state.mutex is busy (pid <p>)`;
  - `studio-state: a hand-off to <path> is pending and <root>/.studio/state.mutex is busy (pid <p>) — showing unhealed state`;
- AC20: `studio-state: git worktree list failed`;
- AC28's take hint: ` · the main checkout's story <spec> (stage <s>) — if no session is working on it in <main checkout>, studio-state take <spec> continues it here`. The adoptable form ends `— it moves here on the first studio-state call`;
- AC38: `stop: ambiguous story <spec>`, `stop: story <spec> not found`, and `story <spec> not found` (status).

**Environment knobs:**
- `STUDIO_STATE_FORCE=1` (AC25);
- `STUDIO_STATE_NO_ADOPT=1` (AC19), which suppresses adopt and self-heal;
- test-only `STUDIO_STATE_TEST_SEAM` = `kill3|kill4|pause3` (this plan's seam for AC13; see T4).

**Platform and process:**
- POSIX `sh` (bash 3.2), BSD tools. No `date +%N`. No `\t` inside sed brackets; awk regexes may use `\t`.
- **`mx_take` is called only in an `if`/`||` context.** studio-state runs `set -eu`, and under `set -e` a failing `var="$(readlink …)"` inside `mx_take` exits the script. In bash 3.2 sh this was verified to exit outside an `||` context and to continue inside one.
- **Never prefix an environment assignment to a shell function in a test** (`X=1 st …`). bash in POSIX mode keeps such assignments after the call. Use `( cd D && X=1 sh "$STATE_BIN" … )`.
- **Signals in tests:** a background job that a non-interactive shell starts ignores SIGINT, and the trap cannot undo that (verified on this machine). A test that sends `INT` starts the job under `set -m`, with `exec`:
  `set -m; ( cd "$D" && exec env STUDIO_STATE_TEST_SEAM=pause3 sh "$STATE_BIN" handoff "$WE" ) & pid=$!; set +m`.
- Timing asserts take the minimum of two samples (studio memory `wall-clock-timing-tests-min-of-two.md`).
- Tests follow `tests/assert.sh`. They run offline in `mktemp -d` dirs with physical paths (`pwd -P`). No new file goes under `studios/*/bin/`. The shared fixture file `tests/state_fixtures.sh` is not a `*_test.sh` file, so `run_all.sh` does not run it.
- A waiting mutex costs about 10 s (100 × 0.1 s in `mx_take`). Every test that waits runs its waiting calls as parallel background jobs. No knob shortens the wait.

---

## Decisions (plan-level; none changes the spec's design)

- **Sourcing, not copying (AC27).**
  - studio-state resolves its own path through symlinks, as `studio-overnight:27-33` does. Its `st_lock` then sources `"$SELF_DIR/overnight-runs.sh"` the first time it needs the lock.
  - Reads never source it. A missing file fails only a write, with `studio-state: missing <dir>/overnight-runs.sh — reinstall the studio`.
  - `overnight-runs.sh` defines functions only (checked), and the overnight test's deny-bin copy (`tests/overnight_test.sh:370`) already carries it.
- **Pins in per-task files.**
  - The new skill pins keep the spec's test names. They live in `tests/pointer_skills_route_test.sh` (T7), `tests/pointer_skills_execute_test.sh` (T8) and `tests/pointer_skills_omega_test.sh` (T10). T9 alone edits `tests/studio_test.sh`.
  - New state tests live in `tests/state_pointer_test.sh` (T2), `tests/state_guard_test.sh` (T3), `tests/state_move_test.sh` (T4) and `tests/state_stories_test.sh` (T5). All of them source `tests/state_fixtures.sh` (T2 creates it, and T4 and T5 may extend it).
  - Only one studio-state task runs per wave, so these shared state files never have two writers at once.
- **Intermediate red.**
  - From T2 until T11, `tests/overnight_test.sh` is expected red. Its stub's `branch` action writes main's `branch` and then `wtledger` writes into a pointer-less worktree.
  - From T4 onward, adopt moves that story and the runner then reads an idle main.
  - T11 rewrites the stub and adds the follow. No task before T11 runs that suite.
- **Gap fills** (the spec is silent; each is the narrowest reading, listed for veto):
  - G1: adopt under a busy mutex exits 1 with the AC27 busy message, for reads too. Adopt is a write. The "a busy mutex never fails a read" rule covers the heal only.
  - G2: restore needs the plan file in this checkout. Without it, it exits 1 with `studio-state: plan file missing: <plan> — restore needs the plan in this checkout`.
  - G3: a forced move keeps the target's own `## Ledger` lines, then writes the `forced` line, then the `handed` line.
  - G4: when a re-run of `handoff <path>` finds that self-heal just completed a move to that same path, it prints `handed <spec> to <path>` and exits 0.
  - G5: the `forced` line of an overridden story-less write names the moved spec (from the newest `handed` line).
  - G6: in `worktree`'s candidate list, the state column of main's recorded-branch candidate (AC22 bullet 2) is the `stories` state of main's row, else `recorded`.
  - G7: `take` prints AC12's `handed <spec> to <path>`. Adopt prints nothing, because its read's output must stay clean.

---

## AC coverage

| AC | Task(s) | Tests / pins |
|---|---|---|
| 1 | T2 | `test_state_main_checkout_unchanged` |
| 2 | T2 | `test_state_two_worktrees_independent` |
| 3 | T2 (reads), T4 (hint), T5 (`worktree`) | `test_state_pointerless_reads_idle`, `test_state_no_main_pointer_exits_1` |
| 4 | T2 (auto-create), T4 (take/handoff) | `test_state_tracked_pointer_refused` |
| 5 | T2 | `test_state_story_writes_unchanged` |
| 6 | T2 | `test_state_two_worktrees_independent`, `test_state_worktree_write_leaves_main_untouched`, `test_state_new_story_seeds_idle`, `test_state_ledger_auto_creates`, `test_state_auto_create_race`, `test_state_exclude_newline_repair` |
| 7 | T2 | `test_state_reset_pointerless_noop` |
| 8 | T2 | `test_state_init_local_is_auto_create` |
| 9 | T2 | `test_state_init_in_linked_worktree` |
| 10 | T2 | `test_state_milestone_is_project_wide` |
| 11 | T2 | `test_state_milestone_without_main` |
| 12 | T4 | `test_state_handoff_moves_story`, `test_state_move_record_parse` |
| 13 | T4 | `test_state_handoff_order_and_self_heal` |
| 14 | T4 | `test_state_handoff_order_and_self_heal`, `test_state_self_heal_ignores_completed_handoff`, `test_state_self_heal_scope`, `test_state_every_write_holds_mutex` (pending part) |
| 15 | T4 | `test_state_handoff_refusals`, `test_state_move_record_parse` |
| 16 | T4 | `test_state_take_after_stop_before_handoff`, `test_state_take_main_planned_story`, `test_state_take_refusals`, `test_state_take_hint_under_stale_branch` |
| 17 | T4, T5 (offer) | `test_state_take_restores_removed_worktree`, `test_state_take_restores_renamed_branch`, `test_state_move_record_parse` |
| 18 | T4 | `test_state_adopt_legacy_execute`, `test_state_adopt_legacy_finished`, `test_state_adopt_skips_next_story`, `test_state_take_hint_under_stale_branch` |
| 19 | T4 (knob), T6 (hook), T10 (omega SKILL) | `test_state_handoff_order_and_self_heal` (NO_ADOPT part), `test_session_start_never_writes`, `test_skill_omega_handoff_no_adopt` |
| 20 | T5 | `test_state_stories_lists_live_pointers`, `test_state_stories_marks_run_worktrees`, `test_state_stories_branch_rename`, `test_state_review_from_main_finds_worktree_born_story` |
| 21 | T5 | `test_state_worktree_from_local_pointer`, `test_state_stories_branch_rename` |
| 22 | T5 | `test_state_worktree_candidates_from_main`, `test_state_worktree_main_execute_no_branch`, `test_state_worktree_legacy_main_branch`, `test_state_worktree_no_resurrect`, `test_state_take_restores_removed_worktree` (offer part), changed `test_state_worktree`/`_edges` |
| 23 | T5 | `test_state_story_writes_unchanged` (worktree under STUDIO_STORY) |
| 24 | T3, T4 (after-take test) | `test_state_story_switch_guard`, `test_state_story_switch_exempt_in_run_worktree`, `test_state_storyless_write_after_handed_line`, `test_state_write_after_take_refused` |
| 25 | T3, T4 | `test_state_force_override`, `test_state_handoff_refusals`, `test_state_take_refusals`, `test_state_write_after_take_refused` |
| 26 | T3 (code), T5 (text) | `test_state_exit_codes_documented` |
| 27 | T1, T2, T4 | `test_mutex_stale_reap_lock_broken`, `test_state_mutex_reap_race`, `test_state_parallel_local_writes_keep_both`, `test_state_every_write_holds_mutex`, `test_state_milestone_without_main`, `test_state_mutex_serialises_moves`, `test_state_mutex_single_acquisition` |
| 28 | T4 (`show`), T6 (hook) | `test_state_take_after_stop_before_handoff`, `test_state_take_hint_under_stale_branch`, `test_session_start_stage_per_checkout`, `test_session_start_take_hint` |
| 29 | T6 | `test_skill_bootstrap_stage_line` (in `hook_test.sh`) |
| 30 | T7 | `test_skill_router_lists_stories`, `test_skill_router_run_lines_and_adopt_note` |
| 31 | T7 | `test_skill_brainstorm_tests_pointer_not_file`, `test_skill_brainstorm_revise_same_story` |
| 32 | T7 | `test_skill_plan_take_hint` |
| 33 | T8 | `test_skill_execute_handoff_at_isolation`, `test_skill_execute_resume_via_stories` |
| 34 | T9 | `test_skill_review_playtest_ask_candidates` |
| 35 | T9 | `test_skill_retro_resolves_story`, changed `test_retro_contract` |
| 36 | T10 | `test_skill_autopilot_no_force` |
| 37 | T5 | `test_state_exit_codes_documented` (header and usage) |
| 38 | T11 | `test_single_plan_follows_story_after_unit_1`, `_resume_line_names_story_worktree`, `_ambiguous_story_stops`, `_preflight_names_story`, `test_channel_ledger_follows_story`, `test_single_plan_rerun_after_stop_before_handoff`, `test_single_plan_in_place_keeps_main_pointer`, `test_single_plan_story_not_found_stops`, `test_status_reads_persisted_spec`, `test_progress_task_follows_story` |
| 39 | T11 | `test_single_plan_from_story_worktree` |
| 40 | T2 (milestone under STORY), T12 | `test_state_milestone_is_project_wide`, `test_lanes_final_unit_stop_pointer_invisible` |
| 41 | T2, T5 | `test_state_agent_worktree_isolated` |
| 42 | T2 | `test_state_legacy_pointer_resolves` |
| 43 | T2, T4, T5 | the ten rows' named tests (main_checkout_unchanged, adopt_legacy_execute, adopt_legacy_finished, adopt_skips_next_story, take_hint_under_stale_branch, take_main_planned_story, new_story_seeds_idle, worktree_candidates_from_main, the lanes and overnight suites, milestone_is_project_wide) |
| 44 | T10 | final review |
| 45 | T10, T13 (PR body) | final review |
| 46 | T10, T13 (PR body) | final review |

## Review Focus

These are the five failure modes most likely to bite a user that no single task's tests cover end to end. Each line's test is added to the task that owns the code.

1. **A Bash-tool timeout kills a `studio-state set` holding the mutex.** The next write anywhere in the project must reap the dead link at once, never wait 10 s. T2 adds `test_state_dead_holder_reaped_fast`, asserting the next `set` finishes in under 2 s.
2. **A user runs `/game-dev:execute` in the main checkout after the story moved.** The router and §0 must point at the worktree, never re-plan. T8's `test_skill_execute_resume_via_stories` pins §0, and T5's round trip asserts `stories` from P lists WE.
3. **A worktree path or spec with spaces or `(`** survives every move record and every candidate line. T4/T5 `test_state_move_record_parse` covers handoff, take, `stories`, `worktree` and restore.
4. **The hook in an adoptable or pending-heal worktree** must never write. T6 `test_session_start_never_writes` checks byte-identity of both pointers and of `info/exclude`.
5. **A runner reading an unrelated new story in P after hand-off.** T11 `test_single_plan_ignores_new_story_in_start` has P start story T with a `Stop:` line in T's ledger while the run continues in WE: the run does not stop. This depends on Ruling R2.

---

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `studios/game-dev/bin/studio-state` | resolution, auto-create, milestone, lock, guard, moves, self-heal, stories, worktree, header/usage | T2, T3, T4, T5 |
| `studios/game-dev/bin/studio-overnight` | `story_dir()`, persisted `spec=`, follow in `state()`/`feature_dir()`/`snapshot`/unit cwd/Resume/status/preflight | T11 |
| `studios/game-dev/bin/overnight-channel.sh` | `chan_ledger` through `story_dir` | T11 |
| `studios/game-dev/hooks/session-start.sh`, `hooks/bootstrap.md` | per-checkout stage line, take hint, NO_ADOPT | T6 |
| `studios/game-dev/skills/{studio,brainstorm,plan}/SKILL.md` | router `stories`, §0 tests, revise, plan take hint | T7 |
| `studios/game-dev/skills/execute/SKILL.md` | §0 `stories`, resume-from-worktree `take`, (a) any other exit 1, (c) `handoff`, base on every resume, milestone note | T8 |
| `studios/game-dev/skills/{review,playtest,retro}/SKILL.md` | candidate list, removed candidate, retro question | T9 |
| `shared/omega/skills/handoff/SKILL.md` | NO_ADOPT on its reads | T10 |
| `studios/game-dev/memory/stage-pointer-is-per-checkout.md` (new), `memory/MEMORY.md`, `docs/game-dev/PROGRESS.md` | AC44-AC46 | T10 |
| `tests/state_fixtures.sh` (new) | shared state fixtures | T2 (T4, T5 extend) |
| `tests/state_pointer_test.sh`, `state_guard_test.sh`, `state_move_test.sh`, `state_stories_test.sh` (new) | studio-state behaviour | T2, T3, T4, T5 |
| `tests/state_test.sh` | changed existing asserts | T2, T5 |
| `tests/overnight_runs_test.sh` | stale reap lock | T1 |
| `tests/hook_test.sh` | hook tests, bootstrap pin | T6 |
| `tests/pointer_skills_{route,execute,omega}_test.sh` (new), `tests/studio_test.sh` | skill pins | T7, T8, T10, T9 |
| `tests/overnight_test.sh`, `tests/overnight_progress_test.sh` | stub, follow tests | T11 |
| `tests/overnight_lanes_test.sh` | AC40 pin | T12 |

---

## Tasks

Wave order: W0 T1 · W1 T2, T7, T8 · W2 T3, T9, T10 · W3 T4, T12 · W4 T5, T6 · W5 T11 · W6 T13 (final review → fix wave → gate → PR).

### Task 1: Baseline and the stale reap-lock test

Spec: AC27 (L267-268), Milestone gate 1 (L24) · Review: final · Wave: 0 · Touches: `tests/overnight_runs_test.sh`

**Interfaces:**
- Consumes: `mx_take`, `mx_reap` (`overnight-runs.sh:97-125`).
- Produces: the baseline record `.superpowers/sdd/2026-10-05-per-story-pointer/baseline.md` (untracked), listing each suite's pass/fail at 3994275.

- [ ] **Step 1: Baseline.** Run `sh tests/run_all.sh > $SCRATCH/base.log 2>&1; echo $?` and `sh integrations/multica/tests/run.sh`. Record each file's result in `baseline.md`. A red suite at base is listed, not fixed. No wave-1 task starts until this file exists.
- [ ] **Step 2: Sourcing probe.** Run `sh -c 'set -eu; . studios/game-dev/bin/overnight-runs.sh; mx_take /tmp/x.$$ $$ || exit 9; mx_drop /tmp/x.$$ $$; echo ok'`. Expect `ok`. Record the result in `baseline.md`.
- [ ] **Step 3: Write the failing test**, then insert `test_mutex_stale_reap_lock_broken` into the `run_tests` list.

```sh
# AC27 (f3-N2): a reap lock left by a reaper killed mid-reap (older than 5 s)
# is broken, so a dead holder's link is still reaped and the take succeeds.
test_mutex_stale_reap_lock_broken() {
  M="$TMP/stale.mutex"; rm -rf "$M" "$M.reap"
  sh -c 'exit 0' & _d=$!; wait "$_d"
  ln -s "$_d" "$M"; mkdir "$M.reap"
  touch -t "$(date -v-1M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-1 min' +%Y%m%d%H%M.%S)" "$M.reap"
  _t0=$(date +%s)
  if mx_take "$M" $$; then _ok=0; else _ok=1; fi
  assert_eq 0 "$_ok" "the take succeeds past a stale reap lock"
  assert_eq "$$" "$(readlink "$M")" "the mutex names the taker"
  assert_missing "$M.reap" "the stale reap lock is gone"
  [ $(( $(date +%s) - _t0 )) -lt 5 ] && _pass "no long wait" || _fail "no long wait"
  TESTS_RUN=$((TESTS_RUN + 1)); mx_drop "$M" $$
}
```

- [ ] **Step 4:** Run `sh tests/overnight_runs_test.sh`. Expect PASS: the reap code is already in place, so this test pins behaviour that exists. If it fails, stop and report. Do not change `overnight-runs.sh`.
- [ ] **Step 5: Commit.** `git commit -m 'test(runs): pin the stale reap-lock break (#42)' -- tests/overnight_runs_test.sh`

---

### Task 2: studio-state — resolution, auto-create, milestone, the lock

Spec: AC1-AC11, AC27 (lock on writes, exclude, traps, no-`.studio` case), AC40 (milestone under STUDIO_STORY), AC41, AC42, AC43 rows 1/7/10 (L142-176, L265-274, L318-345) · Review: task (Opus) · Wave: 1 · Touches: `studios/game-dev/bin/studio-state`, `tests/state_fixtures.sh` (new), `tests/state_pointer_test.sh` (new), `tests/state_test.sh`

**Interfaces:**
- Produces, in studio-state:
  - globals `MAIN`, `LOCAL`, `LINKED`, `TRACKED`, `POINTERLESS`, `SELF_DIR`, `TAB`, `LOCKED`, `MUTEX`, `FORCE` (always `0` here; T3 parses it);
  - functions:
    - `st_lock` (0 when held or not needed, 1 on timeout);
    - `lock_or_fail`, `mutex_pid`, `exclude_once LINE`, `make_local_pointer DIR`, `auto_create`;
    - `main_milestone`, `milestone_view FILE`, `hdr FILE KEY`, `slug_of SPEC`, `today`;
    - `pre_verb VERB`, an empty hook that T4 fills;
    - `write_idle_state FILE [nomilestone]`.
- Produces, in `tests/state_fixtures.sh`: `proj NAME`, `wt NAME BRANCH` (sets `W`), `st DIR ARGS…`, `st_rc DIR ARGS…` (sets `ST_RC`, with output in `$TMP/st.out` and `$TMP/st.err`), `g`, `sum FILE`, `plan_in_p [SPEC]`, `hold_mutex`, `release_mutex`, `dead_mutex`, `wait_all`.

**Resolution** (replaces :49-65; keep :40-48):

```sh
# The pointer's own path, through symlinks, so st_lock can source the shared
# mutex beside it (overnight-runs.sh; AC27: reused, never copied).
_self="$0"
while [ -L "$_self" ]; do _l="$(readlink "$_self")"
  case "$_l" in /*) _self="$_l" ;; *) _self="$(dirname "$_self")/$_l" ;; esac
done
SELF_DIR="$(cd "$(dirname "$_self")" && pwd -P)"
TAB="$(printf '\t')"
# #42 AC1-AC5: every checkout resolves only its own stage pointer.
# - the main checkout: <root>/.studio/STATE.md (MAIN);
# - a linked worktree: <work root>/.studio/STATE.md (LOCAL) when it exists and git
#   does not track it (AC4); otherwise the checkout is pointer-less, reads idle,
#   and its first write creates LOCAL (AC6);
# - STUDIO_STORY: <root>/.studio/stories/<id>.md, unchanged (AC5).
MAIN="$STATE_ROOT/.studio/STATE.md"
LOCAL="$WORK_ROOT/.studio/STATE.md"
_gd="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
_gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
LINKED=0; [ -z "$_gd" ] || [ "$_gd" = "$_gcd" ] || LINKED=1
TRACKED=0; POINTERLESS=0; STATE="$MAIN"
if [ "$LINKED" = 1 ]; then
  STATE="$LOCAL"
  if ( cd "$WORK_ROOT" && git ls-files --error-unmatch .studio/STATE.md ) >/dev/null 2>&1; then TRACKED=1; fi
  if [ ! -f "$LOCAL" ] || [ "$TRACKED" = 1 ]; then POINTERLESS=1; fi
fi
STORY="${STUDIO_STORY:-}"
if [ -n "$STORY" ]; then
  printf '%s' "$STORY" | grep -Eq '^[A-Za-z0-9._-]+$' || { printf "studio-state: bad STUDIO_STORY '%s'\n" "$STORY" >&2; exit 1; }
  STATE="$STATE_ROOT/.studio/stories/$STORY.md"; POINTERLESS=0
fi
FORCE=0
```

**Lock and shared helpers** (new, after `fail`):

```sh
today() { date +%Y-%m-%d; }
hdr() { sed -n "s/^$2: //p" "$1" 2>/dev/null | head -n 1; }
slug_of() { basename "$1" | sed -e 's/\.md$//' -e 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//'; }
# exclude_once LINE — append LINE to <common git dir>/info/exclude once,
# repairing a missing final newline first (#39's rule, now shared).
exclude_once() {
  [ -n "$_gcd" ] || return 0
  mkdir -p "$_gcd/info" || fail "cannot create $_gcd/info"
  grep -qxF "$1" "$_gcd/info/exclude" 2>/dev/null && return 0
  if [ -s "$_gcd/info/exclude" ] && [ -n "$(tail -c 1 "$_gcd/info/exclude")" ]; then printf '\n' >> "$_gcd/info/exclude"; fi
  printf '%s\n' "$1" >> "$_gcd/info/exclude"
}
# st_lock — AC27: take <root>/.studio/state.mutex once per invocation. 0 when
# held (now or already) or when <root>/.studio is missing (f3-N3: nothing to
# race, nothing created); 1 when mx_take times out. The traps release it on
# every exit; INT and TERM then exit 130/143, so a write never resumes unlocked.
LOCKED=0; MUTEX="$STATE_ROOT/.studio/state.mutex"
st_lock() {
  [ "$LOCKED" = 0 ] || return 0
  [ -d "$STATE_ROOT/.studio" ] || return 0
  [ -f "$SELF_DIR/overnight-runs.sh" ] || fail "missing $SELF_DIR/overnight-runs.sh — reinstall the studio"
  . "$SELF_DIR/overnight-runs.sh"
  trap 'mx_drop "$MUTEX" $$' EXIT
  trap 'mx_drop "$MUTEX" $$; exit 130' INT
  trap 'mx_drop "$MUTEX" $$; exit 143' TERM
  if mx_take "$MUTEX" $$; then LOCKED=1; exclude_once .studio/state.mutex; return 0; fi
  return 1
}
mutex_pid() { readlink "$MUTEX" 2>/dev/null || printf '?'; }
lock_or_fail() { st_lock || fail "$MUTEX is busy (pid $(mutex_pid))"; }
# make_local_pointer DIR — AC6/AC8, the one function behind init --local and
# auto-create: the idle template without a milestone line, written to a temp
# file and hard-linked into place (never clobbers; a lost race keeps the winner's).
make_local_pointer() {
  mkdir -p "$1/.studio" || fail "cannot create $1/.studio"
  _mk="$1/.studio/STATE.md.tmp.$$"
  write_idle_state "$_mk" nomilestone || fail "cannot write $_mk"
  ln "$_mk" "$1/.studio/STATE.md" 2>/dev/null || true
  rm -f "$_mk"
  [ -f "$1/.studio/STATE.md" ] || fail "cannot create $1/.studio/STATE.md"
  exclude_once .studio/STATE.md
}
auto_create() {
  [ "$TRACKED" = 0 ] || fail "$LOCAL is tracked by git — a tracked STATE.md is never a stage pointer; run git rm --cached .studio/STATE.md on this branch"
  make_local_pointer "$WORK_ROOT"; STATE="$LOCAL"; POINTERLESS=0
}
main_milestone() { if [ -f "$MAIN" ]; then hdr "$MAIN" milestone; else printf 'prototype\n'; fi; }
# milestone_view FILE — FILE with every header milestone line dropped and
# main's milestone printed after branch: (else after task:) — AC10's show.
milestone_view() {
  _mvk=task; grep -q '^branch: ' "$1" && _mvk=branch     # legacy pointers have no branch: line
  ST_MS="$(main_milestone)" ST_K="$_mvk" awk '
    /^## Ledger/ { inl = 1 }
    !inl && /^milestone: / { next }
    { print }
    !inl && !done && index($0, ENVIRON["ST_K"] ": ") == 1 { print "milestone: " ENVIRON["ST_MS"]; done = 1 }' "$1"
}
```

`test_state_legacy_pointer_resolves` pins the legacy (no `branch:`) case.

**Verb changes:**
- `write_idle_state FILE [nomilestone]` writes the `milestone: prototype` line only without the second argument. Callers:
  - the main `init` keeps the line;
  - `init` under STUDIO_STORY and `make_local_pointer` pass `nomilestone`.
- `need_state`: for a pointer-less worktree, fail as today when `MAIN` is missing (AC3's last line); otherwise pass.
- `field KEY`: when `POINTERLESS=1`, print `idle` for `stage` and `-` otherwise.
- `pre_verb VERB` is an empty function, called first in `get`, `set`, `show`, `ledger`, `check`, `reset` and `worktree` (T4 fills it).
- `get milestone` → `main_milestone`, from every checkout and under STUDIO_STORY.
- `set`:
  - `set milestone` validates, then requires `MAIN`; without it, `studio-state: no main pointer — run studio-state init in <root>`.
  - Then `lock_or_fail`, then `STATE="$MAIN"`, then `set_field milestone`. This holds under STUDIO_STORY too, and never auto-creates.
  - Every other key: with STUDIO_STORY set, as today and unlocked. Otherwise `lock_or_fail`; then `auto_create` when pointer-less; then the write.
- `ledger`: unlocked with STUDIO_STORY set; otherwise `lock_or_fail`, then `auto_create` when pointer-less.
- `reset` and `check --rebuild`:
  - pointer-less: print `no story in this checkout`, exit 0, write nothing;
  - otherwise `lock_or_fail` (unless STUDIO_STORY) before the first write.
- `check` (pointer-less) prints `check: ok`.
- `show`:
  - pointer-less: print the idle header with main's milestone (`write_idle_state` to stdout, then `milestone_view`), then `(no story in this checkout)`, then exit;
  - otherwise print `milestone_view "$STATE"` in place of `cat "$STATE"`. The feature-ledger part is unchanged.
- `init`:
  - in a linked worktree whose `MAIN` exists, fail with the AC9 text;
  - otherwise it creates `MAIN` (use `$MAIN`, not `$STATE`). `.gitignore`, `config.json` and the ledger dir are as today.
- `init --local`:
  - the refusals are as today, except the second-call text, which becomes `init --local: <path> already exists`;
  - then `st_lock || fail …` (a no-op without `<root>/.studio`), then `make_local_pointer "$WORK_ROOT"`, then today's message.
- `worktree`, pointer-less: `fail "no feature branch recorded"` (AC3; T5 replaces the verb).

**Fixtures** (`tests/state_fixtures.sh`, new):

```sh
# tests/state_fixtures.sh — sourced by tests/state_*_test.sh (#42); not a test file.
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
g() { git -c user.name=t -c user.email=t@t "$@"; }
st() { _std="$1"; shift; ( cd "$_std" && sh "$STATE_BIN" "$@" ); }
st_rc() { _std="$1"; shift; ST_RC=0; ( cd "$_std" && sh "$STATE_BIN" "$@" ) > "$TMP/st.out" 2> "$TMP/st.err" || ST_RC=$?; }
sum() { cksum < "$1" 2>/dev/null || echo none; }
# proj NAME — main checkout P on main: studio-state init, docs/s.md, docs/t.md and a
# three-task docs/p.md, all committed.
proj() {
  P="$TMP/$1"; rm -rf "$P" "$P"-*; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && sh "$STATE_BIN" init >/dev/null \
    && printf '# S\n' > docs/s.md && printf '# T\n' > docs/t.md \
    && printf '# Plan\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md \
    && git add -A && g commit -qm init ) >/dev/null 2>&1
}
# wt NAME BRANCH — linked worktree $P-NAME on a new BRANCH; sets W.
wt() { W="$P-$1"; git -C "$P" worktree add -q -b "$2" "$W" >/dev/null 2>&1; }
# plan_in_p [SPEC] — P brainstorms and plans SPEC (default docs/s.md), task 0/3.
plan_in_p() { for _a in "stage brainstorm" "spec ${1:-docs/s.md}" "stage plan" "plan docs/p.md" "task 0/3"; do
  st "$P" set $_a >/dev/null 2>&1; done; }
hold_mutex() { sleep 120 & HOLD_PID=$!; ln -s "$HOLD_PID" "$P/.studio/state.mutex"; }
release_mutex() { kill "$HOLD_PID" 2>/dev/null; wait "$HOLD_PID" 2>/dev/null; rm -f "$P/.studio/state.mutex"; }
dead_mutex() { sh -c 'exit 0' & _dm=$!; wait "$_dm"; ln -sfn "$_dm" "$P/.studio/state.mutex"; }
```

- [ ] **Step 1: Write the failing tests** in `tests/state_pointer_test.sh`. The header is `#!/bin/sh`, `set -u`, `REPO_ROOT`, `. tests/assert.sh` and `. tests/state_fixtures.sh`, with `run_tests …` at the end. The asserts are below; the hard ones are given in full.
  - `test_state_main_checkout_unchanged` (AC1, 43): in P, `set stage brainstorm`, `set spec docs/s.md`, `get spec`, `show` (has `milestone: prototype`), `ledger x` (lands in `.studio/ledger/s.md`) and `reset` all behave as in `state_test.sh`; no `$P/.studio/state.mutex` is left after any of them.
  - `test_state_two_worktrees_independent` (AC2, 6): see the code below.
  - `test_state_pointerless_reads_idle` (AC3): P at `plan` with S (`plan_in_p`); `wt c feat/c`. Then:
    - in WC: `get stage` = `idle`; `get spec`, `plan`, `task` and `branch` = `-`; `get milestone` = P's milestone;
    - `show` has `^stage: idle$`, `^milestone: prototype$` and the line `(no story in this checkout)`;
    - `check` prints `check: ok`; `worktree` exits 1 with `no feature branch recorded`;
    - `$W/.studio/STATE.md` is missing, and `sum` of P is unchanged.
  - `test_state_no_main_pointer_exits_1` (AC3): `rm "$P/.studio/STATE.md"`; WC's `get stage` exits 1 with `run 'studio-state init'`.
  - `test_state_worktree_write_leaves_main_untouched` (AC6): P's `sum` is unchanged across WA's `set stage brainstorm`, `ledger y` and `reset`; WA's file shows `stage: brainstorm` before the reset.
  - `test_state_new_story_seeds_idle` (AC6, 10, 43): WC's `set stage brainstorm` writes `spec: -`, `plan: -`, `task: -` and `branch: -`, and the file has no `^milestone:` line.
  - `test_state_ledger_auto_creates` (AC6): WC's `ledger "Bug: x"` creates the file, with the line under `## Ledger`.
  - `test_state_auto_create_race` (AC6, 27): see the code below.
  - `test_state_parallel_local_writes_keep_both` (AC27): see the code below.
  - `test_state_exclude_newline_repair` (AC6): `printf 'x' > "$(git -C "$P" rev-parse --git-common-dir)/info/exclude"`; WC's first write leaves the lines `x` and `.studio/STATE.md`.
  - `test_state_reset_pointerless_noop` (AC7): `reset` and `check --rebuild` in WC print `no story in this checkout`, exit 0, and WC has no `.studio/STATE.md`.
  - `test_state_init_local_is_auto_create` (AC8):
    - WA's `init --local` file equals WB's auto-created one, after `reset`'s ledger is stripped — compare the header lines only;
    - a second `init --local` exits 1 matching `init --local: .* already exists`;
    - the main-checkout and STUDIO_STORY refusals hold.
  - `test_state_init_in_linked_worktree` (AC9): `init` in WC exits 1 with `studio-state init --local`; in a fresh non-repo dir, `init` still works.
  - `test_state_tracked_pointer_refused` (AC4, 5):
    - on WT's branch, `printf '...' > .studio/STATE.md`, `git add -f .studio/STATE.md` and commit;
    - WT's `get stage` = `idle`;
    - `set stage brainstorm` exits 1 with `git rm --cached .studio/STATE.md`;
    - `STUDIO_STORY=S1 init` then `STUDIO_STORY=S1 set task 1/2` in WT exit 0.
    - T4 appends the `take` and `handoff` asserts.
  - `test_state_story_writes_unchanged` (AC5, 23): under `STUDIO_STORY=S1` in WA, `init`, `set task 1/2`, `ledger x` and `check --rebuild` act on `$P/.studio/stories/S1.md` as today; no `state.mutex` link is created while a `hold_mutex` is in place (each call returns in under 2 s).
  - `test_state_milestone_is_project_wide` (AC10, 40, 42): the spec's asserts, as listed (spec L520).
  - `test_state_milestone_without_main` (AC11, 27): see the code below.
  - `test_state_every_write_holds_mutex` (AC10, 27): see the code below. T4 appends the pending-heal part.
  - `test_state_dead_holder_reaped_fast` (Review Focus 1): `dead_mutex`, then P's `set stage brainstorm` finishes in under 2 s (min of two) and leaves no link.
  - `test_state_mutex_reap_race` (AC27): see the code below.
  - `test_state_agent_worktree_isolated` (AC41):
    - `git -C "$P" worktree add -q -b agent-abc "$P/.claude/worktrees/agent-abc"`, with P at `execute`;
    - it reads `idle`; its `set stage brainstorm` leaves P's `sum` unchanged;
    - `git worktree remove` (no `--force`) succeeds, and its file is gone.
    - T5 appends "`stories` drops it".
  - `test_state_legacy_pointer_resolves` (AC42): a `legacy_state`-style main pointer without `branch:` gets `get stage`, `set branch feat/x` (inserted after `task:`) and `show` (milestone after `task:`); a `#39`-style local pointer with `milestone: prototype` and main at `alpha` reads `alpha`.

```sh
test_state_two_worktrees_independent() {
  proj two; wt a feat/a; WA="$W"; wt b feat/b; WB="$W"
  st "$WA" set stage brainstorm >/dev/null; st "$WA" set spec docs/s.md >/dev/null
  st "$WB" set stage brainstorm >/dev/null; st "$WB" set spec docs/t.md >/dev/null
  assert_eq docs/s.md "$(st "$WA" get spec)" "WA reads its own spec"
  assert_eq docs/t.md "$(st "$WB" get spec)" "WB reads its own spec"
  assert_file "$WA/.studio/STATE.md" "WA's pointer exists"; assert_file "$WB/.studio/STATE.md" "WB's pointer exists"
  assert_eq "" "$(git -C "$WA" status --porcelain)" "WA's git status stays clean"
  assert_eq "" "$(git -C "$WB" status --porcelain)" "WB's git status stays clean"
  assert_eq 1 "$(grep -cxF .studio/STATE.md "$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude")" "one exclude line"
  assert_eq idle "$(st "$P" get stage)" "P is untouched"
}
test_state_auto_create_race() {
  proj race; _r=1
  while [ "$_r" -le 5 ]; do
    wt "c$_r" "feat/c$_r"
    ( cd "$W" && sh "$STATE_BIN" set spec docs/s.md ) > "$TMP/a.out" 2>&1 & _p1=$!
    ( cd "$W" && sh "$STATE_BIN" set plan docs/p.md ) > "$TMP/b.out" 2>&1 & _p2=$!
    _s1=0; wait "$_p1" || _s1=$?; _s2=0; wait "$_p2" || _s2=$?
    assert_eq "0 0" "$_s1 $_s2" "round $_r: both first writes exit 0"
    assert_eq "docs/s.md docs/p.md" "$(st "$W" get spec) $(st "$W" get plan)" "round $_r: both values land"
    _r=$((_r + 1))
  done
  assert_eq 1 "$(grep -cxF .studio/STATE.md "$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude")" "the exclude line once"
}
test_state_parallel_local_writes_keep_both() {
  proj par; wt a feat/a; st "$W" set stage brainstorm >/dev/null; _r=1; _bad=0
  while [ "$_r" -le 20 ]; do
    ( cd "$W" && sh "$STATE_BIN" set spec "docs/s$_r.md" ) >/dev/null 2>&1 & _p1=$!
    ( cd "$W" && sh "$STATE_BIN" set plan "docs/p$_r.md" ) >/dev/null 2>&1 & _p2=$!
    wait "$_p1"; wait "$_p2"
    [ "$(st "$W" get spec) $(st "$W" get plan)" = "docs/s$_r.md docs/p$_r.md" ] || _bad=$((_bad + 1))
    _r=$((_r + 1))
  done
  assert_eq 0 "$_bad" "20 rounds of a parallel spec/plan pair keep both values (f2-I6)"
}
test_state_milestone_without_main() {
  _M="$TMP/nomain"; rm -rf "$_M"; mkdir -p "$_M"
  ( cd "$_M" && git init -q -b main && g commit -q --allow-empty -m i && git worktree add -q -b run/x "$_M-rw" ) >/dev/null 2>&1
  st "$_M-rw" init --local >/dev/null
  assert_eq prototype "$(st "$_M-rw" get milestone)" "no main pointer: prototype"
  st_rc "$_M-rw" set milestone alpha
  assert_eq 1 "$ST_RC" "set milestone exits 1"; assert_contains "$TMP/st.err" "no main pointer — run studio-state init in" "names init"
  _t0=$(date +%s)
  st "$_M-rw" set stage brainstorm >/dev/null; st "$_M-rw" ledger x >/dev/null; st "$_M-rw" reset >/dev/null
  [ $(( $(date +%s) - _t0 )) -lt 3 ] && _pass "local writes never wait" || _fail "local writes never wait"; TESTS_RUN=$((TESTS_RUN + 1))
  assert_missing "$_M/.studio" "no <root>/.studio is created (f3-N3)"
}
test_state_every_write_holds_mutex() {
  proj ewh; wt a feat/a; WA="$W"; st "$WA" set stage brainstorm >/dev/null; hold_mutex
  ( cd "$P" && sh "$STATE_BIN" set stage brainstorm ) > /dev/null 2> "$TMP/e1" & _a=$!
  ( cd "$WA" && sh "$STATE_BIN" set spec docs/s.md ) > /dev/null 2> "$TMP/e2" & _b=$!
  ( cd "$WA" && sh "$STATE_BIN" ledger x ) > /dev/null 2> "$TMP/e3" & _c=$!
  ( cd "$WA" && sh "$STATE_BIN" set milestone alpha ) > /dev/null 2> "$TMP/e4" & _d=$!
  _t0=$(date +%s)
  ( cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" init && STUDIO_STORY=S1 sh "$STATE_BIN" set task 1/2 ) >/dev/null 2>&1
  st "$P" get stage >/dev/null; st "$WA" show >/dev/null
  [ $(( $(date +%s) - _t0 )) -lt 3 ] && _pass "STUDIO_STORY writes and reads do not wait" || _fail "STUDIO_STORY writes and reads do not wait"
  TESTS_RUN=$((TESTS_RUN + 1))
  for _j in "$_a:1" "$_b:2" "$_c:3" "$_d:4"; do
    _s=0; wait "${_j%%:*}" || _s=$?
    assert_eq 1 "$_s" "write ${_j#*:} exits 1 after the timeout"
    assert_contains "$TMP/e${_j#*:}" "state.mutex is busy (pid $HOLD_PID)" "write ${_j#*:} names the holder"
  done
  release_mutex
}
test_state_mutex_reap_race() {
  proj reap; _r=1
  while [ "$_r" -le 20 ]; do
    dead_mutex; _i=1; _pids=""
    while [ "$_i" -le 6 ]; do ( cd "$P" && sh "$STATE_BIN" ledger "L$_i-$_r" ) >/dev/null 2>&1 & _pids="$_pids $!"; _i=$((_i + 1)); done
    for _q in $_pids; do wait "$_q"; done
    _r=$((_r + 1))
  done
  assert_eq 120 "$(grep -c '^- [0-9-]* L[0-9]*-[0-9]*$' "$P/.studio/STATE.md")" "all 120 lines land"
  assert_eq 120 "$(grep '^- [0-9-]* L' "$P/.studio/STATE.md" | sort -u | wc -l | tr -d ' ')" "each exactly once"
  assert_missing "$P/.studio/state.mutex.reap" "no reap directory is left"
}
```

- [ ] **Step 2: Change the existing tests** in `tests/state_test.sh`:
  - `test_state_resolves_to_main_checkout` (:171): keep the `root` asserts. Invert "the main checkout's STATE.md carries the change" and "the worktree holds no copy": the worktree write creates its own pointer, and the main pointer is unchanged.
  - `test_state_ledger_per_branch` (:276): invert the last assert, "the pointer is shared" (AC6).
  - `test_state_init_local_creates_pointer` (:621): add `assert_not_contains "$RW/.studio/STATE.md" '^milestone:'`.
  - `test_state_local_pointer_only_when_present` (:638): rename it to `test_state_local_pointer_auto_created`. Its first assert becomes "RW's write creates RW's pointer; P stays idle". Its last assert (pointer removed) becomes "reads idle again" (`get stage` = `idle`, from a pointer-less RW). Update `run_tests`.
- [ ] **Step 3:** Run `sh tests/state_pointer_test.sh` and `sh tests/state_test.sh`. Expect FAIL on the new asserts.
- [ ] **Step 4: Implement** the resolution, helpers and verb changes above.
- [ ] **Step 5: Run.** `sh tests/state_pointer_test.sh; sh tests/state_test.sh; sh tests/hook_test.sh; sh tests/studio_brief_test.sh; sh tests/studio_setup_test.sh; sh tests/studio_adopt_test.sh; sh tests/studio_peers_test.sh; sh tests/studio_test.sh` (the last one for `test_bin_syntax`). All PASS. Do not run the overnight or lanes suites (see Decisions, Intermediate red).
- [ ] **Step 6: Commit.** `git commit -m 'feat(studio-state): per-checkout pointer, auto-create, project-wide milestone, state.mutex (#42)' -- studios/game-dev/bin/studio-state tests/state_fixtures.sh tests/state_pointer_test.sh tests/state_test.sh`

---

### Task 3: studio-state — the story-switch guard, `--force`, exit 4

Spec: AC24-AC26 (L254-263) · Review: task (Opus) · Wave: 2 · Touches: `studios/game-dev/bin/studio-state`, `tests/state_guard_test.sh` (new)

**Interfaces:**
- Consumes (T2): `lock_or_fail`, `hdr`, `slug_of`, `today`, `TAB`, `POINTERLESS`, `FORCE`.
- Produces:
  - `newest_rec FILE KINDS [SPEC]`;
  - `rec_get LINE KEY`;
  - `refuse4 MSG…` (stderr `studio-state: MSG`, exit 4);
  - `guard_set KEY VALUE`, which exits 4 or returns, with `FORCED_LINE` set when an override was needed;
  - the `--force` parsing: `set --force KEY VALUE` here. `take --force`/`handoff --force` are reserved for T4, which reuses `FORCE`.
  - `FORCE` is 1 when `--force` is given or `STUDIO_STATE_FORCE=1`.

```sh
refuse4() { printf 'studio-state: %s\n' "$*" >&2; exit 4; }
# rec_get LINE KEY — a move record's KEY= value (TAB-separated fields; path= last).
rec_get() { printf '%s\n' "$1" | tr '\t' '\n' | sed -n "s/^$2=//p" | head -n 1; }
# newest_rec FILE KINDS [SPEC] — FILE's newest `## Ledger` line whose kind (its
# third word) is in KINDS ("handed|abandoned|restored"); with SPEC, only move
# records with spec=SPEC. Values travel through the environment (no awk -v escapes).
newest_rec() {
  ST_KINDS="$2" ST_SPEC="${3:-}" awk -F'\t' '
    BEGIN { n = split(ENVIRON["ST_KINDS"], k, "|"); for (i = 1; i <= n; i++) want[k[i]] = 1 }
    /^## Ledger/ { inl = 1; next }
    inl && /^- / { split($1, w, " "); if (!(w[3] in want)) next
                   if (ENVIRON["ST_SPEC"] != "" && $2 != "spec=" ENVIRON["ST_SPEC"]) next
                   last = $0 }
    END { if (last != "") print last }' "$1" 2>/dev/null
}
# guard_set KEY VALUE — AC24 on this checkout's pointer (STUDIO_STORY unset, no
# .studio/run here). Refuses with exit 4, or returns with FORCED_LINE set when
# --force / STUDIO_STATE_FORCE=1 overrode a refusal (AC25).
guard_set() {
  FORCED_LINE=""
  [ -z "$STORY" ] && [ ! -e "$WORK_ROOT/.studio/run" ] && [ "$POINTERLESS" = 0 ] || return 0
  _gs="$(field stage)"; _gp="$(field spec)"; _gt="$(field task)"; _msg=""; _over="$_gp"
  case "$1" in
    stage) if [ "$2" = brainstorm ]; then case "$_gs" in plan|execute) _msg=switch ;; esac; fi ;;
    spec) case "$_gp" in -|''|"$2") ;; *)
            case "$_gs" in plan|execute) _msg=switch ;;
              brainstorm) printf 'studio-state: replacing spec %s with %s at stage brainstorm\n' "$_gp" "$2" >&2 ;; esac ;; esac ;;
  esac
  if [ -z "$_msg" ] && [ "${_gp:--}" = - ] && [ "$2" != - ]; then
    case "$1:$2" in stage:plan|stage:execute|plan:*|task:*)
      _gl="$(newest_rec "$STATE" 'handed|abandoned|restored')"
      case "$_gl" in "- "*" handed$TAB"*) _msg=moved; _over="$(rec_get "$_gl" spec)" ;; esac ;;
    esac
  fi
  [ -n "$_msg" ] || return 0
  if [ "$FORCE" = 1 ]; then FORCED_LINE="- $(today) forced $1=$2 over $_over (stage $_gs)"; return 0; fi
  if [ "$_msg" = switch ]; then
    refuse4 "this checkout is on story $(slug_of "$_gp") (stage $_gs, task $_gt) — finish or reset it first, start the new story in its own worktree (EnterWorktree), or pass --force"
  fi
  _gd="$(printf '%s\n' "$_gl" | cut -d' ' -f2)"
  refuse4 "this checkout holds no story — $(rec_get "$_gl" spec) moved to $(rec_get "$_gl" path) on $_gd; continue it there, start a new story with /game-dev:brainstorm, or pass --force"
}
```

`set` order: parse `--force` → validate → `lock_or_fail` → `guard_set` (on the resolved pointer; a pointer-less one never refuses) → `auto_create` when pointer-less → `[ -z "$FORCED_LINE" ] || printf '%s\n' "$FORCED_LINE" >> "$STATE"` → write. `--force` anywhere but `set --force KEY VALUE` is `usage`. The usage line and the `Exit:` header line gain the Global Constraints exit-4 text here. T5 rewrites the rest of the header.

- [ ] **Step 1: Write the failing tests** in `tests/state_guard_test.sh`:
  - `test_state_story_switch_guard` (AC24). In P, then again in WA:
    - at `plan` with spec A (`docs/s.md`), `set spec docs/t.md` and `set stage brainstorm` exit 4. stderr equals exactly `studio-state: this checkout is on story s (stage plan, task 0/3) — finish or reset it first, start the new story in its own worktree (EnterWorktree), or pass --force`. The `sum` is unchanged;
    - `set spec docs/s.md` exits 0;
    - at `brainstorm`, `set spec docs/t.md` exits 0 with stderr naming `docs/s.md`.
  - `test_state_story_switch_exempt_in_run_worktree` (AC24): with `touch "$W/.studio/run"`, at `plan`, `set stage brainstorm` and `set spec docs/t.md` exit 0.
  - `test_state_force_override` (AC25):
    - `set --force spec docs/t.md` at `plan` exits 0 and writes exactly one `forced spec=docs/t.md over docs/s.md (stage plan)` line;
    - `( cd P && STUDIO_STATE_FORCE=1 sh "$STATE_BIN" set stage brainstorm )` writes one `forced stage=brainstorm` line;
    - `set --force task 0/3` at `brainstorm` writes no `forced` line (nothing was refused);
    - `set spec --force x` and `get --force spec` exit 1 with the usage text.
  - `test_state_storyless_write_after_handed_line` (AC24, f3-N6). Append by hand to P's `## Ledger` the line `- 2026-10-05 handed<TAB>spec=docs/s.md<TAB>plan=docs/p.md<TAB>branch=feat/x<TAB>path=/w x`. Then:
    - `set stage plan`, `set stage execute`, `set plan docs/p.md` and `set task 0/3` exit 4, each with exactly `studio-state: this checkout holds no story — docs/s.md moved to /w x on 2026-10-05; continue it there, start a new story with /game-dev:brainstorm, or pass --force`;
    - `set task -` and `set branch -` exit 0;
    - after `set stage brainstorm`, `set spec docs/t.md`, `reset` (a newest `abandoned` line), the four writes are accepted;
    - a pointer whose newest such line is `restored` accepts them.
- [ ] **Step 2:** Run `sh tests/state_guard_test.sh`. Expect FAIL.
- [ ] **Step 3:** Implement as above.
- [ ] **Step 4:** Run `sh tests/state_guard_test.sh; sh tests/state_pointer_test.sh; sh tests/state_test.sh`. Expect PASS. `state_test.sh` :80/:86/:548-592 set keys without a `handed` line and must stay green.
- [ ] **Step 5: Commit.** `git commit -m 'feat(studio-state): story-switch guard, --force and exit 4 (#42)' -- studios/game-dev/bin/studio-state tests/state_guard_test.sh`

---

### Task 4: studio-state — handoff, take, restore, adopt, self-heal, the take hint

Spec: AC12-AC19, AC28 (the `show` part), AC4 (moves), AC43 rows 2-6 (L178-225, L278) · Review: task (Opus) · Wave: 3 · Touches: `studios/game-dev/bin/studio-state`, `tests/state_move_test.sh` (new), `tests/state_fixtures.sh`, `tests/state_pointer_test.sh`

**Interfaces:**
- Consumes (T2, T3): `st_lock`, `lock_or_fail`, `exclude_once`, `hdr`, `slug_of`, `today`, `TAB`, `newest_rec`, `rec_get`, `refuse4`, `FORCE`, `pre_verb`.
- Produces (T5 and T11 rely on these):
  - `wt_records` (TSV `path<TAB>branch|-<TAB>live`, main first; returns 1 on a git failure);
  - `phys DIR`, `is_live_linked PATH`, `branch_at PATH`, `tracked_at PATH`, `finished_at PATH SPEC`;
  - `other_live_with_branch BR` (the path of a live linked worktree other than this one, or empty);
  - `load_main` (sets `M_STAGE M_SPEC M_PLAN M_TASK M_BRANCH`);
  - `heal_pending read|write` (sets `HEALED_PATH`, `HEALED_SPEC`);
  - `move_story TARGET MODE VIA` (MODE `handoff|take|adopt`);
  - `adopt_conditions`, `adoptable`, `maybe_adopt`, `take_hint`;
  - `plan_task_count FILE`, `ledger_k FILE` (factored out of the STUDIO_STORY rebuild, :302-320; behaviour unchanged).
- Verbs: `handoff [--force] <path>`, `take [--force] <spec>`.
- Test seam: `STUDIO_STATE_TEST_SEAM=kill3|kill4|pause3`, via `test_seam N`.
- `pre_verb VERB` now runs `heal_pending read`, or `heal_pending write` for a writing verb, in the main checkout (`LINKED=0`), and `maybe_adopt` in a linked worktree.

**The hard parts, in full:**

```sh
# wt_records — one line per `git worktree list --porcelain` entry, main first:
# "<path><TAB><branch, or - when detached><TAB><1 live, 0 prunable>". 1 on a git failure.
wt_records() {
  _wl="$(git worktree list --porcelain 2>/dev/null)" && [ -n "$_wl" ] || return 1
  printf '%s\n' "$_wl" | awk '
    function flush() { if (p != "") printf "%s\t%s\t%d\n", p, (b == "" ? "-" : b), (pr ? 0 : 1); p = ""; b = ""; pr = 0 }
    /^worktree / { flush(); p = substr($0, 10); next }
    /^branch refs\/heads\// { b = substr($0, 19); next }
    /^prunable( |$)/ { pr = 1; next }
    END { flush() }'
}
phys() { ( cd "$1" 2>/dev/null && pwd -P ); }
# is_live_linked PATH — PATH is a live, existing linked worktree of this repository (not the main checkout).
is_live_linked() {
  _ip="$(phys "$1")" && [ -n "$_ip" ] || return 1
  wt_records | awk -F'\t' 'NR > 1 && $3 == 1 { print $1 }' | while IFS= read -r _iw; do
    [ "$(phys "$_iw")" = "$_ip" ] && { echo hit; break; }; done | grep -q hit
}
branch_at() { _bp="$(phys "$1")"; wt_records | while IFS="$TAB" read -r _w _b _l; do
  [ "$(phys "$_w")" = "$_bp" ] && { printf '%s\n' "$_b"; break; }; done; }
tracked_at() { git -C "$1" ls-files --error-unmatch .studio/STATE.md >/dev/null 2>&1; }
finished_at() { [ "${2:--}" != - ] && grep -q '^- [0-9-]* shipped ' "$1/.studio/ledger/$(slug_of "$2").md" 2>/dev/null; }
load_main() { M_STAGE="$(hdr "$MAIN" stage)"; M_SPEC="$(hdr "$MAIN" spec)"; M_PLAN="$(hdr "$MAIN" plan)"
              M_TASK="$(hdr "$MAIN" task)"; M_BRANCH="$(hdr "$MAIN" branch)"; }
test_seam() { case "${STUDIO_STATE_TEST_SEAM:-}" in "kill$1") kill -9 $$ ;; "pause$1") sleep 30 & wait $! ;; esac; }

# main_idle_to OUT — AC12/AC13 step 5: MAIN with the story header cleared
# (stage idle, spec/plan/task/branch -, milestone kept) and this move's
# `handing` line rewritten to `handed`; every other ledger line kept (D1).
main_idle_to() {
  awk -F'\t' -v OFS='\t' '
    BEGIN { v["stage"] = "idle"; v["spec"] = "-"; v["plan"] = "-"; v["task"] = "-"; v["branch"] = "-" }
    /^## Ledger/ { inl = 1 }
    !inl && /^[a-z_]+: / { k = $0; sub(/:.*/, "", k); if (k in v) { print k ": " v[k]; next } }
    inl && !done && /^- [0-9-]+ handing\t/ { sub(/ handing$/, " handed", $1); done = 1 }
    { print }' "$MAIN" > "$1" || return 1
  grep -q '^branch: ' "$1" || { awk '{ print } !d && /^task: / { print "branch: -"; d = 1 }' "$1" > "$1.b" && mv "$1.b" "$1"; }
}
finish_main() { _mi="$MAIN.tmp.$$"; main_idle_to "$_mi" && mv "$_mi" "$MAIN"; }
# rewrite_handing KIND [REASON] — the one `handing` line becomes KIND (handed |
# void); a REASON goes in as reason= just before path=. One tmp + mv.
rewrite_handing() {
  _rt="$MAIN.tmp.$$"
  ST_NEW="$1" ST_WHY="${2:-}" awk -F'\t' -v OFS='\t' '
    !done && /^- [0-9-]+ handing\t/ { sub(/ handing$/, " " ENVIRON["ST_NEW"], $1)
      if (ENVIRON["ST_WHY"] != "") $NF = "reason=" ENVIRON["ST_WHY"] OFS $NF; done = 1 }
    { print }' "$MAIN" > "$_rt" && mv "$_rt" "$MAIN"
}
# target_write DIR REC — AC13 step 4: DIR's pointer is main's story header with
# DIR's git branch, then DIR's own `## Ledger` lines (f2-M7; G3), then
# FORCED_LINE when set, then "- <date> handed<TAB>REC". tmp + ln when absent
# (never clobbers), tmp + mv over an existing one that move_checks re-read.
target_write() {
  _tf="$1/.studio/STATE.md"; _tt="$_tf.tmp.$$"
  mkdir -p "$1/.studio" || fail "cannot create $1/.studio"
  { printf '# Studio State\n\nstage: %s\nspec: %s\nplan: %s\ntask: %s\nbranch: %s\n\n## Ledger\n\n' \
        "$M_STAGE" "$M_SPEC" "$M_PLAN" "$M_TASK" "$(branch_at "$1")"
    [ ! -f "$_tf" ] || awk '/^## Ledger/ { f = 1; next } f && /^- /' "$_tf"
    [ -z "${FORCED_LINE:-}" ] || printf '%s\n' "$FORCED_LINE"
    printf -- '- %s handed%s%s\n' "$(today)" "$TAB" "$2"
  } > "$_tt" || fail "cannot write $_tt"
  if [ -f "$_tf" ]; then mv "$_tt" "$_tf"
  else ln "$_tt" "$_tf" 2>/dev/null || { rm -f "$_tt"; fail "$_tf appeared during the move — run the command again"; }
       rm -f "$_tt"; fi
  exclude_once .studio/STATE.md
}
# move_checks TARGET MODE — AC15 (and AC4) under the mutex. Exits 1 or 4; sets M_*, FORCED_LINE.
move_checks() {
  load_main; FORCED_LINE=""
  if [ "$2" = handoff ]; then [ "$M_STAGE" != idle ] || fail "the main checkout has no story to hand off (stage idle)"; fi
  case "$M_SPEC" in ''|-) fail "the main checkout has no story to hand off" ;; esac
  tracked_at "$1" && fail "$1/.studio/STATE.md is tracked by git — a tracked STATE.md is never a stage pointer; run git rm --cached .studio/STATE.md on this branch"
  [ "$(branch_at "$1")" != - ] || fail "$1 has a detached HEAD — check out the story's branch there first"
  case "$M_SPEC" in *"$TAB"*) fail "a TAB in spec cannot be recorded" ;; esac
  case "$M_PLAN" in *"$TAB"*) fail "a TAB in plan cannot be recorded" ;; esac
  case "$1" in *"$TAB"*) fail "a TAB in path cannot be recorded" ;; esac
  _tf="$1/.studio/STATE.md"; [ -f "$_tf" ] || return 0
  _ts="$(hdr "$_tf" stage)"; _tp="$(hdr "$_tf" spec)"
  [ "$_ts" != idle ] || ! finished_at "$1" "$_tp" || _ts=idle-finished
  [ "$_ts" != idle ] || return 0
  _ts="${_ts%-finished}"
  if [ "$FORCE" = 1 ]; then FORCED_LINE="- $(today) forced handoff=$1 over $_tp (stage $_ts)"; return 0; fi
  if [ "$_tp" = "$M_SPEC" ]; then
    refuse4 "$(slug_of "$_tp") is in both $1 (stage $_ts) and the main checkout (stage $M_STAGE) — reset it in one of them, or pass --force"
  fi
  refuse4 "$1 holds story $(slug_of "$_tp") (stage $_ts) — finish or reset it there first, or pass --force"
}
# move_story TARGET MODE VIA — AC13: steps 1-6 for handoff, take and adopt. The
# caller has resolved TARGET to a physical live linked worktree.
move_story() {
  lock_or_fail                                   # 1 (no-op when already held)
  heal_pending write                             # 2: heal, then the checks
  move_checks "$1" "$2"
  _rec="spec=$M_SPEC${TAB}plan=$M_PLAN${TAB}branch=$(branch_at "$1")${TAB}${3:+via=$3$TAB}path=$1"
  printf -- '- %s handing%s%s\n' "$(today)" "$TAB" "$_rec" >> "$MAIN"   # 3: the intent
  test_seam 3
  target_write "$1" "$_rec"                      # 4
  test_seam 4
  finish_main                                    # 5: one tmp + mv, handing → handed
}                                                # 6: the EXIT trap releases the mutex

# heal_pending read|write — AC14. A move is incomplete exactly when MAIN holds a
# `handing` line. Detect without the lock, re-read under it. A read whose lock
# times out reports on stderr and continues unhealed (f3-N8); a write fails.
HEALED_PATH=""; HEALED_SPEC=""
heal_pending() {
  [ -z "$STORY" ] && [ -z "${STUDIO_STATE_NO_ADOPT:-}" ] && [ -f "$MAIN" ] || return 0
  _hl="$(newest_rec "$MAIN" handing)"; [ -n "$_hl" ] || return 0
  if ! st_lock; then
    [ "$1" = read ] || fail "$MUTEX is busy (pid $(mutex_pid))"
    printf 'studio-state: a hand-off to %s is pending and %s is busy (pid %s) — showing unhealed state\n' \
      "$(rec_get "$_hl" path)" "$MUTEX" "$(mutex_pid)" >&2
    return 0
  fi
  _hl="$(newest_rec "$MAIN" handing)"; [ -n "$_hl" ] || return 0
  _hs="$(rec_get "$_hl" spec)"; _hw="$(rec_get "$_hl" path)"; load_main; _why=""
  if ! is_live_linked "$_hw"; then _why="worktree gone"
  elif tracked_at "$_hw"; then _why="target STATE.md is tracked"
  elif [ "$(branch_at "$_hw")" = - ]; then _why="detached HEAD"
  else
    _tf="$_hw/.studio/STATE.md"; _tp="$(hdr "$_tf" spec)"
    if [ -f "$_tf" ] && [ "$_tp" = "$_hs" ]; then          # target holds S: step 5 only
      if [ "$M_SPEC" = "$_hs" ]; then finish_main; else rewrite_handing handed; fi
      HEALED_PATH="$_hw"; HEALED_SPEC="$_hs"; return 0
    fi
    if [ "$M_SPEC" = "$_hs" ] && { [ ! -f "$_tf" ] || { [ "$(hdr "$_tf" stage)" = idle ] && ! finished_at "$_hw" "$_tp"; }; }; then
      FORCED_LINE=""; target_write "$_hw" "$(printf '%s\n' "$_hl" | cut -f2-)"; finish_main   # steps 4, 5
      HEALED_PATH="$_hw"; HEALED_SPEC="$_hs"; return 0
    fi
    if [ "$M_SPEC" != "$_hs" ]; then _why="main no longer holds $(slug_of "$_hs")"; else _why="target holds $(slug_of "$_tp")"; fi
  fi
  rewrite_handing void "$_why"                                   # roll back: main keeps its story
}

# adopt_conditions — AC18's state test (no env checks; take_hint reuses it).
adopt_conditions() {
  [ "$POINTERLESS" = 1 ] && [ "$TRACKED" = 0 ] && [ -z "$STORY" ] && [ -f "$MAIN" ] || return 1
  _ab="$(hdr "$MAIN" branch)"; case "$_ab" in ''|-) return 1 ;; esac
  [ "$_ab" = "$(git branch --show-current 2>/dev/null)" ] || return 1
  case "$(hdr "$MAIN" stage)" in
    execute) return 0 ;;
    idle) _as="$(hdr "$MAIN" spec)"; [ "${_as:--}" != - ] && [ -f "$LEDGER_DIR/$(slug_of "$_as").md" ] ;;
    *) return 1 ;;
  esac
}
adoptable() { [ -z "${STUDIO_STATE_NO_ADOPT:-}" ] && adopt_conditions; }
# maybe_adopt — AC18, before a pointer-resolving verb in a linked worktree. Silent (G7).
maybe_adopt() {
  adoptable || return 0
  lock_or_fail                                   # G1: a busy mutex fails the call
  heal_pending write
  adoptable || return 0                          # re-checked under the mutex
  FORCE=0; move_story "$(phys "$WORK_ROOT")" adopt adopt
  STATE="$LOCAL"; POINTERLESS=0
}
# take_hint — AC28's hint for this pointer-less checkout, or nothing.
take_hint() {
  [ "$POINTERLESS" = 1 ] && [ -z "$STORY" ] && [ -f "$MAIN" ] || return 0
  case "$WORK_ROOT" in */.claude/worktrees/agent-*) return 0 ;; esac
  load_main; [ "${M_STAGE:-idle}" != idle ] || return 0
  case "$M_SPEC" in ''|-) return 0 ;; /*) _hf="$M_SPEC" ;; *) _hf="$WORK_ROOT/$M_SPEC" ;; esac
  [ -f "$_hf" ] || return 0
  if [ "$M_STAGE" = execute ] && [ -n "$(other_live_with_branch "$M_BRANCH")" ]; then return 0; fi
  if adopt_conditions; then
    printf "the main checkout's story %s (stage %s) — it moves here on the first studio-state call\n" "$M_SPEC" "$M_STAGE"
  else
    printf "the main checkout's story %s (stage %s) — if no session is working on it in %s, studio-state take %s continues it here\n" \
      "$M_SPEC" "$M_STAGE" "$STATE_ROOT" "$M_SPEC"
  fi
}
```

**Verbs:**
- `handoff [--force] <path>`:
  1. `[ -z "$STORY" ] || fail "handoff cannot be combined with STUDIO_STORY"`; `[ -f "$MAIN" ] || fail …`; `_t="$(phys "$path")"`, and `is_live_linked "$_t"` or `fail "$path is not a live linked worktree of this repository"`.
  2. `lock_or_fail`, `heal_pending write`.
  3. G4: if `HEALED_PATH = _t` and `hdr "$_t/.studio/STATE.md" spec = HEALED_SPEC`, print `handed <spec> to <path>` and exit 0.
  4. `move_story "$_t" handoff ""`, then print `handed <spec> to <_t>`.
- `take [--force] <spec>`:
  1. Refuse STUDIO_STORY (exit 1). Refuse the main checkout with `fail "take runs in a linked worktree — the main checkout already holds its story"`. Require `MAIN`.
  2. `lock_or_fail`, `heal_pending write`, `load_main`. `_here` is LOCAL's spec when not pointer-less.
  3. If `_here = spec`:
     - when `M_SPEC ≠ spec`, print `<spec> is already in this checkout` and exit 0;
     - otherwise, unless `FORCE`, `refuse4` the AC15 both-checkouts text.
  4. If `M_SPEC ≠ spec`, run `restore_story spec` (below). It exits 0 or refuses with the non-overridable `the main checkout's story is <M_SPEC>, not <spec>`.
  5. If `M_STAGE = execute` and `other_live_with_branch "$M_BRANCH"` is non-empty, `refuse4 "<spec> is being executed in <path> — continue it there"`. FORCE is ignored here.
  6. Pointer-less and `TRACKED=1` → the AC4 `fail`.
  7. `move_story "$(phys "$WORK_ROOT")" take ""`, then print `handed <spec> to <path>`.
- `restore_story SPEC` (AC17):
  1. `_rl="$(newest_rec "$MAIN" handed "$SPEC")"`. When it is empty → the non-overridable refusal.
  2. `_rp`, `_rb` and `_rpl` are its `path`, `branch` and `plan`. `_cur` is `git branch --show-current`, which must be non-empty: `fail` with the detached text otherwise.
  3. When `_rp` is a live linked worktree whose `phys` differs from this one's → refusal.
  4. Accept when `_rb = _cur`, or when `refs/heads/$_rb` is missing and `$LEDGER_DIR/<slug>.md` exists; otherwise refusal.
  5. The AC15 target check on this checkout (`move_checks`'s target part, with FORCE and FORCED_LINE).
  6. `_pf` is the plan file under WORK_ROOT. When it is missing, `fail "plan file missing: <plan> — restore needs the plan in this checkout"` (G2).
  7. `N=$(plan_task_count "$_pf")`; `k=$(ledger_k "$LEDGER_DIR/<slug>.md")` (the contiguous `T<n> complete` count); `stage` is `idle` when that ledger has a `shipped` line, else `execute`.
  8. Write LOCAL by tmp + `ln` (or `mv` over an idle one): the header `stage/spec/plan/task k/N/branch _cur`, this pointer's old ledger lines, FORCED_LINE, then `- <date> restored <spec> from the handed line`.
  9. Print `restored <spec> from the handed line` and exit 0. The main pointer is unchanged.
- `show` in a pointer-less worktree also prints `take_hint` after `(no story in this checkout)`.
- `stories`, `worktree` and the remaining header text are T5's.

- [ ] **Step 1: Write the failing tests** in `tests/state_move_test.sh`. The fixture is `proj` + `plan_in_p`, with `st "$P" set stage execute` where a test needs `execute`.
  - `test_state_handoff_moves_story` (AC12, f2-I9, f2-M7): see the code below.
  - `test_state_handoff_order_and_self_heal` (AC13, 14, 19): see the code below.
  - `test_state_self_heal_ignores_completed_handoff` (AC14, f2-I2b). Hand S to WE. Then:
    - `st "$WE" reset`, then `git -C "$P" worktree remove "$WE"` (no `--force`);
    - `plan_in_p` (re-plans S in P), then `git -C "$P" worktree add -q "$WE" feat/e`;
    - P's `get stage` and `show` leave `sum` unchanged;
    - `handoff "$WE"` then exits 0;
    - a P with a hand-appended `handed` line naming main's current spec changes nothing on `get stage`.
  - `test_state_self_heal_scope` (AC14, f2-M3): with a hand-appended pending `handing` line to a live WE, `root`, `root --work` and `studio-state bogus` (usage, exit 1) leave every `sum` unchanged; `get stage` then heals.
  - `test_state_move_record_parse` (AC12, 15, 17, f2-M2):
    - spec `docs/a b to (c).md` (committed) and a worktree at `"$P-w x"`; `handoff` moves it;
    - the main `handed` line's `rec_get` fields round-trip, checked by `sed` on the file;
    - `take` of that spec restores it after removal (T5 adds the `stories` and `worktree` asserts);
    - `printf 'docs/a\tb.md'` as the spec → `handoff` exits 1 with `a TAB in spec cannot be recorded`.
  - `test_state_handoff_refusals` (AC15, 25): the spec's asserts (L527).
    - exit 1 under STUDIO_STORY, to P, to `/tmp`, from an idle P, and to a detached worktree (`git -C "$W" checkout -q --detach`);
    - exit 4 onto WA holding A (stderr `holds story t (stage plan)`), and onto WF finished (stage idle, spec, `shipped` line in WF's ledger);
    - `--force` moves it and writes one `forced handoff=` line in the target;
    - P at `plan` with S and WS holding S (`set --force`) → exit 4 with `is in both`, and no `handing` line in P.
  - `test_state_take_after_stop_before_handoff` (AC16, 28, 33): P at `execute` with S, `task 0/3` and `branch -`; WE pointer-less on `feat/s`.
    - WE's `show` ends with `if no session is working on it in $P, studio-state take docs/s.md continues it here`;
    - `take docs/s.md` → WE `execute`, S, p, `0/3`, `branch feat/s`; P idle with `branch -` and one `handed` line.
  - `test_state_take_main_planned_story` (AC16, 43): P at `plan`, `branch -`; WX's `take docs/s.md` moves it; WX's `set stage execute` leaves P's `sum` unchanged.
  - `test_state_take_refusals` (AC16, 25): the spec's asserts (L530), including `take --force docs/s.md` in WA holding A → moves, with a `forced` line, and the both-checkouts exit 4.
  - `test_state_write_after_take_refused` (AC24, 25): the spec's asserts (L531), run with a real `take` from WX.
  - `test_state_take_restores_removed_worktree` (AC17):
    - hand off to WE; `st "$WE" ledger "T1 complete a..b"` and `T2`; commit WE's ledger on feat/e; `git -C "$P" worktree remove "$WE"`;
    - then `git -C "$P" worktree add -q "$WE" feat/e && st "$WE" take docs/s.md` → `execute`, S, p, `branch feat/e`, `task 2/3`, plus a `restored docs/s.md from the handed line` line, with P's `sum` unchanged;
    - with a committed `shipped` line, the restored stage is `idle`.
    - T5 adds the `worktree` offer assert.
  - `test_state_take_restores_renamed_branch` (AC17, f2-M1): the spec's asserts (L533).
  - `test_state_adopt_legacy_execute` (AC18, 43): P at `execute` with `branch feat/e` and WE on feat/e. WE's first `get plan` prints `docs/p.md` (adopt is silent: stdout is exactly that line). WE holds S; P is idle with one `handed` line containing `via=adopt`.
  - `test_state_adopt_legacy_finished` (AC18, 43): P idle with spec S, `branch feat/e` and `$WE/.studio/ledger/s.md` present → adopts. Without the ledger file → no adopt (P's `sum` unchanged).
  - `test_state_adopt_skips_next_story` (AC18, 43): P at `brainstorm`, then at `plan`, spec T, stale `branch feat/e`, with WE on feat/e → WE's `get stage` = `idle`, and P's `sum` is unchanged.
  - `test_state_take_hint_under_stale_branch` (AC16, 18, 28): the spec's asserts (L538).
  - `test_state_mutex_serialises_moves` (AC27): with `hold_mutex`, `handoff` exits 1 after the timeout naming `$HOLD_PID`; after `dead_mutex`, it succeeds.
  - `test_state_mutex_single_acquisition` (AC27, f2-M4, f2-M5, f3-N4): see the code below.
  - In `tests/state_pointer_test.sh`:
    - extend `test_state_tracked_pointer_refused`: `take` and `handoff` into WT exit 1 naming `git rm --cached`;
    - extend `test_state_every_write_holds_mutex` with the pending part: a hand-appended `handing` line to a live WE plus `hold_mutex` → P's `get stage` and `show` (run in the background, in parallel) exit 0 after the wait, print `execute`, the unhealed stage, and have stderr `showing unhealed state`.

```sh
test_state_handoff_moves_story() {
  proj hm; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  printf -- '- 2026-10-01 Bug: x\n- 2026-10-01 abandoned docs/old.md\n' >> "$P/.studio/STATE.md"
  _ms="$(st "$P" get milestone)"
  st_rc "$P" handoff "$WE"
  assert_eq 0 "$ST_RC" "handoff exits 0"; assert_contains "$TMP/st.out" "^handed docs/s.md to $WE$" "prints the move"
  assert_eq "execute docs/s.md docs/p.md 0/3 feat/e" \
    "$(for k in stage spec plan task branch; do st "$WE" get $k; done | tr '\n' ' ' | sed 's/ $//')" "WE holds the story"
  assert_eq 1 "$(grep -c '^- ' "$WE/.studio/STATE.md")" "WE's ledger holds only the handed line"
  assert_eq "idle - - - -" "$(for k in stage spec plan task branch; do st "$P" get $k; done | tr '\n' ' ' | sed 's/ $//')" "P is idle"
  assert_eq "$_ms" "$(st "$P" get milestone)" "milestone kept"
  assert_contains "$P/.studio/STATE.md" "Bug: x" "main keeps its notes (D1)"
  assert_contains "$P/.studio/STATE.md" "abandoned docs/old.md" "and its abandoned line"
  assert_eq 1 "$(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "the move reads handed in main"
  assert_eq 0 "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md")" "no handing line left"
  # f2-M7: an idle target's own ledger lines stay, before the handed line.
  proj hm2; plan_in_p; wt e feat/e; WE="$W"; st "$WE" ledger "Bug: y" >/dev/null
  st "$P" handoff "$WE" >/dev/null 2>&1
  assert_eq "Bug: y|handed" "$(sed -n 's/^- [0-9-]* \(Bug: y\)$/\1/p; s/^- [0-9-]* \(handed\)\t.*/\1/p' "$WE/.studio/STATE.md" | tr '\n' '|' | sed 's/|$//')" "Bug: y kept before handed"
}
test_state_handoff_order_and_self_heal() {
  proj ho; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  assert_eq 1 "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md")" "kill after step 3: the intent line"
  assert_missing "$WE/.studio/STATE.md" "kill after step 3: no target yet"
  _b="$(sum "$P/.studio/STATE.md")"
  ( cd "$P" && STUDIO_STATE_NO_ADOPT=1 sh "$STATE_BIN" get stage ) >/dev/null 2>&1
  assert_eq "$_b" "$(sum "$P/.studio/STATE.md")" "NO_ADOPT suppresses the heal (AC19)"
  assert_eq idle "$(st "$P" get stage)" "the next P read completes the move"
  assert_eq docs/s.md "$(st "$WE" get spec)" "the target holds S"
  assert_eq "0 1" "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md") $(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "one handed, no handing"
  # kill after step 4; the target advances first; the heal runs step 5 only (f2-I2c).
  proj ho4; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill4 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  st "$WE" set task 2/3 >/dev/null; _wl="$(grep -c '^- ' "$WE/.studio/STATE.md")"
  st "$P" get stage >/dev/null
  assert_eq 2/3 "$(st "$WE" get task)" "the target's progress is kept"
  assert_eq "$_wl" "$(grep -c '^- ' "$WE/.studio/STATE.md")" "no ledger line added to the target"
  assert_eq idle "$(st "$P" get stage)" "P idle"
  # worktree gone after step 3: one void line, then nothing (f2-I2a).
  proj hov; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  git -C "$P" worktree remove "$WE" >/dev/null 2>&1
  st "$P" get stage >/dev/null; st "$P" show >/dev/null
  assert_eq 1 "$(grep -c "$(printf ' void\t.*reason=worktree gone\tpath=')" "$P/.studio/STATE.md")" "one void line"
  assert_eq execute "$(st "$P" get stage)" "main keeps its story"
  # a re-run of the same handoff heals first: no second record (f2-M13; G4).
  proj hor; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  st_rc "$P" handoff "$WE"
  assert_eq 0 "$ST_RC" "the re-run exits 0"
  assert_eq "0 1" "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md") $(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "no second record"
}
test_state_mutex_single_acquisition() {
  proj sa; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  printf -- '- 2026-10-05 handing\tspec=docs/s.md\tplan=docs/p.md\tbranch=feat/e\tpath=%s\n' "$WE" >> "$P/.studio/STATE.md"
  _t0=$(date +%s); st "$P" handoff "$WE" >/dev/null 2>&1
  [ $(( $(date +%s) - _t0 )) -lt 2 ] && _pass "heal + move in one acquisition" || _fail "heal + move in one acquisition"; TESTS_RUN=$((TESTS_RUN + 1))
  _x="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  assert_eq 1 "$(grep -cxF .studio/state.mutex "$_x")" "state.mutex excluded once"
  dead_mutex; assert_eq "" "$(git -C "$P" status --porcelain)" "a dangling link never shows in git status"
  # INT during a paused move: exit 130, no link, no target pointer.
  proj si; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  set -m; ( cd "$P" && exec env STUDIO_STATE_TEST_SEAM=pause3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1 & _hp=$!; set +m
  _i=0; while [ ! -L "$P/.studio/state.mutex" ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
  sleep 0.3; kill -INT "$_hp"; _s=0; wait "$_hp" || _s=$?
  assert_eq 130 "$_s" "INT exits 130"
  assert_missing "$P/.studio/state.mutex" "the trap released the mutex"
  assert_missing "$WE/.studio/STATE.md" "no target pointer was written"
  # adopt + its write, and a restore, each in one acquisition.
  proj sa2; plan_in_p; wt e feat/e; st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null
  _t0=$(date +%s); st "$W" set task 1/3 >/dev/null 2>&1
  [ $(( $(date +%s) - _t0 )) -lt 2 ] && _pass "adopt then set: one acquisition" || _fail "adopt then set: one acquisition"; TESTS_RUN=$((TESTS_RUN + 1))
  assert_eq 1/3 "$(st "$W" get task)" "the adopted story took the write"
}
```
- [ ] **Step 2:** Run `sh tests/state_move_test.sh`. Expect FAIL.
- [ ] **Step 3:** Implement the functions and verbs above. Wire `pre_verb`:

```sh
pre_verb() {   # VERB — AC14 heal in the main checkout; AC18 adopt in a linked worktree.
  [ -z "$STORY" ] || return 0
  case "$1" in get|show|worktree) _pm=read ;; check) _pm="${2:-read}" ;; *) _pm=write ;; esac
  if [ "$LINKED" = 0 ]; then heal_pending "$_pm"; else maybe_adopt; fi
}
```

  `check` passes `write` when `--rebuild` is given.
- [ ] **Step 4:** Run `sh tests/state_move_test.sh; sh tests/state_pointer_test.sh; sh tests/state_guard_test.sh; sh tests/state_test.sh`. Expect PASS.
- [ ] **Step 5: Commit.** `git commit -m 'feat(studio-state): handoff, take, restore, adopt and self-heal (#42)' -- studios/game-dev/bin/studio-state tests/state_move_test.sh tests/state_fixtures.sh tests/state_pointer_test.sh`

---

### Task 5: studio-state — `stories`, `worktree`, header and usage, the round trip

Spec: AC20-AC23, AC26 (text), AC37, AC41, Milestone gate 2 (L24-32, L227-250, L304) · Review: task (Opus) · Wave: 4 · Touches: `studios/game-dev/bin/studio-state`, `tests/state_stories_test.sh` (new), `tests/state_test.sh`, `tests/state_move_test.sh`, `tests/state_pointer_test.sh`, `tests/state_fixtures.sh`

**Interfaces:**
- Consumes (T4): `wt_records`, `phys`, `is_live_linked`, `branch_at`, `tracked_at`, `finished_at`, `heal_pending`, `newest_rec`, `rec_get`, `other_live_with_branch`, `shq`.
- Produces:
  - verb `stories` (AC20 TSV, six fields; exit 1 on a git failure);
  - `story_lines` (the same rows plus an internal seventh field, `main|local`);
  - `wt_branch BR` (today's :385-424 body, unchanged, now a function);
  - `stale_prefix BR`, `default_branch`, `wt_local`, `wt_main`, `offer_removed ROWS`.
- T11 consumes `stories`' output format only.

```sh
# story_row PATH BRANCH FILE ROLE — one row when FILE's story is active,
# finished or a run's (AC20 Terms), else nothing.
story_row() {
  _ss="$(hdr "$3" stage)"; _sp="$(hdr "$3" spec)"; _sk="$(hdr "$3" task)"
  if [ -e "$1/.studio/run" ]; then _sx=run
  elif [ "${_ss:-idle}" != idle ]; then _sx=active
  elif finished_at "$1" "$_sp"; then _sx=finished
  else return 0; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${_ss:-idle}" "${_sp:--}" "${_sk:--}" "$_sx" "$4"
}
# story_lines — AC20: main's row (at the live worktree holding main's branch
# when main is at execute or idle with a branch; brainstorm/plan ignore a
# stale branch), then each live linked worktree's local pointer in git order.
story_lines() {
  _recs="$(wt_records)" || fail "git worktree list failed"
  _ms="$(hdr "$MAIN" stage)"; _mb="$(hdr "$MAIN" branch)"; _mp="$STATE_ROOT"
  _mpb="$(printf '%s\n' "$_recs" | head -n 1 | cut -f2)"
  case "$_ms:$_mb" in execute:-|execute:|idle:-|idle:) ;;
    execute:*|idle:*)
      _hit="$(printf '%s\n' "$_recs" | ST_B="$_mb" awk -F'\t' '$2 == ENVIRON["ST_B"] && $3 == 1 { print $1; exit }')"
      if [ -n "$_hit" ] && [ -d "$_hit" ]; then _mp="$_hit"; _mpb="$_mb"; fi ;;
  esac
  story_row "$_mp" "$_mpb" "$MAIN" main
  printf '%s\n' "$_recs" | sed 1d | while IFS="$TAB" read -r _p _b _l; do
    [ "$_l" = 1 ] && [ -d "$_p" ] && [ -f "$_p/.studio/STATE.md" ] || continue
    tracked_at "$_p" && continue
    story_row "$_p" "$_b" "$_p/.studio/STATE.md" local
  done
}
# wt_main — AC22, `worktree` from the main checkout (STUDIO_STORY unset).
wt_main() {
  _ms="$(field stage)"; _mb="$(field branch)"
  [ "$_ms" != execute ] || wt_branch "$_mb"                       # f2-C1: only main's own story
  _rows="$(story_lines)" || exit 1
  _c="$(printf '%s\n' "$_rows" | awk -F'\t' '$7 == "local" && $6 != "run" && ($3 == "execute" || $6 == "finished") { print $1 "\t" $2 "\t" $4 "\t" $6 }')"
  if [ "$_ms" = idle ] && [ "${_mb:--}" != - ]; then
    _bp="$(wt_records | ST_B="$_mb" awk -F'\t' '$2 == ENVIRON["ST_B"] && $3 == 1 { print $1; exit }')"
    if [ -n "$_bp" ] && [ -d "$_bp" ]; then
      _st="$(printf '%s\n' "$_rows" | awk -F'\t' '$7 == "main" { print $6 }')"
      _c="$(printf '%s\n%s\t%s\t%s\t%s\n' "$_c" "$_bp" "$_mb" "$(field spec)" "${_st:-recorded}")"
    fi
  fi
  _c="$(printf '%s\n' "$_c" | awk -F'\t' 'NF && !seen[$1]++')"
  _n="$(printf '%s\n' "$_c" | grep -c .)" || true
  if [ "$_n" -eq 1 ]; then printf '%s\n' "$_c" | cut -f1; exit 0; fi
  if [ "$_n" -gt 1 ]; then printf 'studio-state: %s stories fit — choose one:\n%s\n' "$_n" "$_c" >&2; exit 1; fi
  if [ "$_ms" = idle ] && [ "${_mb:--}" != - ]; then wt_branch "$_mb"; fi   # exit 3, or "no longer exists"
  offer_removed "$_rows"
  fail "no feature branch recorded"
}
# offer_removed ROWS — AC22's last rule: main's newest handed line, offered once
# as a question (exit 1), when its worktree is gone, its branch exists unmerged,
# and no live pointer (main's included) holds its spec. Returns when not offered.
offer_removed() {
  _hl="$(newest_rec "$MAIN" handed)"; [ -n "$_hl" ] || return 0
  _hp="$(rec_get "$_hl" path)"; _hb="$(rec_get "$_hl" branch)"; _hs="$(rec_get "$_hl" spec)"
  ! is_live_linked "$_hp" || return 0
  git show-ref --verify --quiet "refs/heads/$_hb" 2>/dev/null || return 0
  _db="$(default_branch)"
  if [ -n "$_db" ] && git merge-base --is-ancestor "$_hb" "$_db" 2>/dev/null; then return 0; fi
  [ "$(field spec)" != "$_hs" ] || return 0
  printf '%s\n' "$1" | ST_S="$_hs" awk -F'\t' '$4 == ENVIRON["ST_S"] { f = 1 } END { exit !f }' && return 0
  printf 'studio-state: 1 story fits — choose one:\n%s\t%s\t%s\tremoved\t%sgit worktree add %s %s && (cd %s && studio-state take %s)\n' \
    "$_hp" "$_hb" "$_hs" "$(stale_prefix "$_hb")" "$(shq "$_hp")" "$(shq "$_hb")" "$(shq "$_hp")" "$(shq "$_hs")" >&2
  exit 1
}
# wt_local — AC21, `worktree` from a local pointer.
wt_local() {
  _br="$(field branch)"; case "$_br" in ''|-) fail "no feature branch recorded" ;; esac
  _cur="$(git branch --show-current 2>/dev/null || true)"
  if [ "$_br" != "$_cur" ] && git show-ref --verify --quiet "refs/heads/$_br" 2>/dev/null; then
    _o="$(other_live_with_branch "$_br")"
    [ -z "$_o" ] || fail "this checkout's story is on $_br, which is checked out in $_o — switch this checkout back to $_br"
    fail "this checkout's story is on $_br, but ${_cur:-a detached HEAD} is checked out here — switch this checkout back to $_br"
  fi
  printf '%s\n' "$WORK_ROOT"; exit 0
}
```

The detached-HEAD message: when `_cur` is empty, the text reads `but a detached HEAD is checked out here`. `default_branch` is `git symbolic-ref --short refs/remotes/origin/HEAD` with `origin/` stripped, else the first of `main` and `master` that exists, else empty. `stale_prefix BR` is today's `_prefix` loop (:403-420), factored out and shared with `wt_branch`.

`stories` verb: `[ $# -eq 1 ] || usage`; require `MAIN` (today's exit-1 text); `heal_pending read`; `_o="$(story_lines)" || exit 1`; print `cut -f1-6` of it. `worktree` verb:
- `pre_verb worktree`;
- under STUDIO_STORY, `wt_branch "$(field branch)"` (AC23);
- in a linked worktree, pointer-less → `fail "no feature branch recorded"`, else `wt_local`;
- in the main checkout, `wt_main`.

**Header and usage** (AC37) replace :2-28. The usage line adds `stories | handoff [--force] PATH | take [--force] SPEC | set [--force] KEY VALUE`. The header describes, one line each:
- per-checkout resolution (main / local / pointer-less idle / tracked never);
- auto-create on the first write;
- `init --local`;
- the project-wide milestone;
- `handoff`, `take`, restore and adopt, under `state.mutex`, with the `handing` intent and self-heal;
- `stories` and `worktree`'s candidates;
- the story-switch guard, `--force`, `STUDIO_STATE_FORCE`, `STUDIO_STATE_NO_ADOPT`;
- `Exit: 0 · 1 · 3 · 4`, with the Global Constraints exit-4 text.

The sentence "so a linked git worktree edits the same file and one project has one stage" is removed.

- [ ] **Step 1: Write the failing tests** in `tests/state_stories_test.sh`. The assert lists are as in the spec (L539-L557):
  - `test_state_stories_lists_live_pointers`. With `git` failing (a `PATH` stub: `printf '#!/bin/sh\nexit 1\n' > $TMP/nogit/git`), `( cd P && PATH="$TMP/nogit:$PATH" sh "$STATE_BIN" stories )` exits 1 with `git worktree list failed`.
  - `test_state_stories_marks_run_worktrees`
  - `test_state_stories_branch_rename`
  - `test_state_worktree_from_local_pointer`
  - `test_state_worktree_candidates_from_main`
  - `test_state_worktree_main_execute_no_branch`
  - `test_state_worktree_legacy_main_branch`
  - `test_state_review_from_main_finds_worktree_born_story`
  - `test_state_worktree_no_resurrect`
  - `test_state_exit_codes_documented`: `usage` stderr and `sed -n 2,40p studio-state` both contain `4 refused:`, and the header no longer contains `one project has one stage`.
  - `test_state_round_trip_two_stories`: below, in full.

  Extensions:
  - `test_state_move_record_parse` (state_move_test.sh): `stories` lists the space path intact, and `worktree` offers it as `removed` with `shq`-quoted parts.
  - `test_state_take_restores_removed_worktree`: P's `worktree` exits 1 with one `removed` line whose command, run by `sh -c`, re-adds WE and takes S.
  - `test_state_agent_worktree_isolated` (state_pointer_test.sh): after removal, `stories` no longer lists the agent path.

```sh
test_state_round_trip_two_stories() {
  proj rt; plan_in_p; wt e feat/e; WE="$W"; wt a feat/a; WA="$W"
  st "$P" set branch - >/dev/null; st "$P" set stage execute >/dev/null           # execute §0 in P
  st "$WE" handoff "$WE" >/dev/null                                               # (c) inside WE
  assert_eq "execute idle -" "$(st "$WE" get stage) $(st "$P" get stage) $(st "$P" get branch)" "S moved to WE; P idle, branch -"
  assert_eq 1 "$(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "P's ledger has the handed line"
  for _a in "stage brainstorm" "spec docs/t.md" "stage plan" "plan docs/p.md" "task 0/3"; do st "$WA" set $_a >/dev/null; done
  _wa="$(sum "$WA/.studio/STATE.md")"
  st "$WE" set task 1/3 >/dev/null; st "$WE" set task 2/3 >/dev/null
  st "$WE" ledger "shipped https://x/pull/1" >/dev/null; st "$WE" set stage idle >/dev/null; st "$WE" set task - >/dev/null
  _we="$(sum "$WE/.studio/STATE.md")"
  st "$P" stories > "$TMP/rt.tsv"
  assert_contains "$TMP/rt.tsv" "^$WE	feat/e	idle	docs/s.md	-	finished$" "stories lists WE finished"
  assert_contains "$TMP/rt.tsv" "^$WA	feat/a	plan	docs/t.md	0/3	active$" "stories lists WA active"
  assert_eq "$WE" "$(st "$P" worktree)" "worktree from P prints WE (WA at plan is no candidate)"
  st_rc "$P" set stage brainstorm; assert_eq 0 "$ST_RC" "P starts story T"
  st_rc "$P" set spec docs/t.md; assert_eq 0 "$ST_RC" "P sets T's spec with WE on disk"
  assert_eq "$_wa" "$(sum "$WA/.studio/STATE.md")" "WA never changed because of S or T"
  assert_eq "$_we" "$(sum "$WE/.studio/STATE.md")" "WE never changed because of A or T"
  assert_eq docs/t.md "$(st "$P" get spec)" "P holds T, not A"
}
```

  The round-trip literals contain real TABs between fields; use `printf` to build them if the editor drops tabs. Its final assert "P's never changes because of A" is covered by P's spec being T and by `grep -c 'docs/t.md'` on P's ledger, which holds no line written from WA.
- [ ] **Step 2: Change `tests/state_test.sh` `test_state_worktree`** (:419): the two from-inside asserts (:443-445) become exit 1 with `no feature branch recorded`, because wt-f is pointer-less (AC3). Every other assert there and in `test_state_worktree_edges` (:483-510) stays. Expect them to pass through `wt_main`'s main-at-`idle` recorded-branch rule. If one fails, report it; do not edit it.
- [ ] **Step 3:** Run `sh tests/state_stories_test.sh`. Expect FAIL. Implement. Then run `sh tests/state_stories_test.sh; sh tests/state_move_test.sh; sh tests/state_pointer_test.sh; sh tests/state_guard_test.sh; sh tests/state_test.sh; sh tests/studio_test.sh`. Expect PASS.
- [ ] **Step 4: Commit.** `git commit -m 'feat(studio-state): stories, worktree candidates, header (#42)' -- studios/game-dev/bin/studio-state tests/state_stories_test.sh tests/state_test.sh tests/state_move_test.sh tests/state_pointer_test.sh tests/state_fixtures.sh`

---

### Task 6: SessionStart hook and bootstrap

Spec: AC19 (hook), AC28, AC29 (L225, L278-279) · Review: final · Wave: 4 · Touches: `studios/game-dev/hooks/session-start.sh`, `studios/game-dev/hooks/bootstrap.md`, `tests/hook_test.sh`

**Interfaces:**
- Consumes: T4's `show` hint line, which starts `the main checkout's story `, and `STUDIO_STATE_NO_ADOPT`.

**Changes:**
- **`session-start.sh`:**
  - The comment at :15-17 reads: "the config lives in the checkout the session runs in; studio-state resolves this checkout's own pointer. Both calls are best-effort and never write: `STUDIO_STATE_NO_ADOPT=1` suppresses adopt and self-heal (AC19)."
  - :20 becomes `STAGE="$(STUDIO_STATE_NO_ADOPT=1 sh "$STUDIO_STATE" get stage 2>/dev/null || true)"`.
  - Add `HINT="$(STUDIO_STATE_NO_ADOPT=1 sh "$STUDIO_STATE" show 2>/dev/null | sed -n "/^the main checkout's story /{p;q;}")"`.
  - :94 becomes `printf '\nStudio state: stage %s%s\n' "$STAGE" "${HINT:+ · $HINT}"`.
  - Keep the bash-3.2 note: no `case … )` inside `$(…)`.
- **`bootstrap.md` :27** gets AC29's text verbatim.

- [ ] **Step 1: Write the failing tests** in `hook_test.sh`, and add them to its `run_tests`:
  - `test_session_start_stage_per_checkout`: P idle and WA at `plan` print `Studio state: stage idle` from P and `Studio state: stage plan` from WA; a pointer-less WC prints `stage idle`.
  - `test_session_start_take_hint`:
    - P at `plan` with S, and a pointer-less WC holding `docs/s.md` → the context contains `if no session is working on it in` and `studio-state take docs/s.md continues it here`;
    - `$P/.claude/worktrees/agent-x` gets no hint;
    - with P also recording a stale `branch feat/e` live in WE, WC still gets the hint.
  - `test_session_start_never_writes`:
    - an adoptable WE (P at `execute`, `branch feat/e`) and a pending `handing` line;
    - after `run_hook` in WE and in P, `cksum` of P's and WE's pointers (WE's absent) and of `info/exclude` are unchanged, and no `state.mutex` link exists.
  - `test_skill_bootstrap_stage_line`: `bootstrap.md` contains `a linked worktree with no story of its own reads idle` and no longer contains `When \`.studio/STATE.md\` exists`.
  - `test_hook_reports_stage` (:277) stays green unchanged.
- [ ] **Step 2:** Run `sh tests/hook_test.sh`. Expect FAIL. Implement. Run it again. Expect PASS.
- [ ] **Step 3: Commit.** `git commit -m 'feat(hooks): per-checkout stage line and take hint, never writes (#42)' -- studios/game-dev/hooks/session-start.sh studios/game-dev/hooks/bootstrap.md tests/hook_test.sh`

---

### Task 7: Skills — router, brainstorm, plan

Spec: AC30-AC32 (L280-287) · Review: final · Wave: 1 · Touches: `studios/game-dev/skills/studio/SKILL.md`, `studios/game-dev/skills/brainstorm/SKILL.md`, `studios/game-dev/skills/plan/SKILL.md`, `tests/pointer_skills_route_test.sh` (new)

Text changes, at current anchors:
- **studio**:
  - :16 "Run `studio-state show` from the project root." → "Run `studio-state show` in the checkout you are in."
  - New lines after it:
    - in the main checkout, also run `studio-state stories` and list each story on one line with the checkout to continue it in;
    - a `run` line reads `run in progress in <path>`, never a story to continue;
    - when main is idle and a story is active elsewhere, `Next:` names `continue <spec> in <path>` first, then `/game-dev:brainstorm`;
    - in a pointer-less worktree whose `show` prints the take hint, `Next:` names `studio-state take <spec>` or `/game-dev:brainstorm`, never `/game-dev:execute`.
  - Abandon (:66-71): `studio-state reset` resets this checkout's pointer only; for a story in another checkout it names `abandon it in <path>`; on exit 4 it shows the message.
  - Rules (:104-107) add: "a pre-#42 worktree's one-time adopt (studio-state AC18) may move its story into it on the router's first read".
  - Keep the pins `studio-state check`, `studio-state reset` and `failing test`.
- **brainstorm §0** (:16-19):
  - The state test becomes "`studio-state get stage` exits 0", replacing "`.studio/STATE.md` does not exist". On exit 1 with `project.godot`, it asks to initialise as today.
  - On exit 4 from `set stage brainstorm` or `set spec`: stop, show the message, suggest EnterWorktree.
  - Before :61's `set stage brainstorm`, at `plan` it asks once: "revise `<spec>`, or start a new story in its own worktree?". On "revise" it runs `studio-state set --force stage brainstorm`.
  - At `execute` it offers no revise and stops on exit 4.
  - Keep the pin `studio-state set stage brainstorm` on one line.
- **plan §0** (:28-33):
  - In a pointer-less worktree whose `studio-state show` prints the take hint, stop with: "the main checkout's story `<spec>` is waiting: continue it in `<main checkout>`, or run `studio-state take <spec>` here".
  - :151-153: exit 4 from any state write stops and shows the message.

- [ ] **Step 1: Write the pins** in `tests/pointer_skills_route_test.sh`, then run it. Expect FAIL.
  - `test_skill_router_lists_stories`: `studio-state stories`, `in the checkout you are in`, `continue <spec> in <path>`, `abandon it in <path>`.
  - `test_skill_router_run_lines_and_adopt_note`: `run in progress in <path>`, `one-time adopt`, `never \`/game-dev:execute\``.
  - `test_skill_brainstorm_tests_pointer_not_file`: contains `studio-state get stage` exits 0, and does not contain `If \`.studio/STATE.md\` does not exist`.
  - `test_skill_brainstorm_revise_same_story`: `or start a new story in its own worktree?`, `studio-state set --force stage brainstorm`, `EnterWorktree`.
  - `test_skill_plan_take_hint`: `studio-state take <spec>` here, `is waiting`, `exit 4`.
- [ ] **Step 2:** Edit the three files. Run `sh tests/pointer_skills_route_test.sh; sh tests/studio_test.sh`. Expect PASS.
- [ ] **Step 3: Commit.** `git commit -m 'docs(skills): router, brainstorm and plan read this checkout and stories (#42)' -- studios/game-dev/skills/studio/SKILL.md studios/game-dev/skills/brainstorm/SKILL.md studios/game-dev/skills/plan/SKILL.md tests/pointer_skills_route_test.sh`

---

### Task 8: Skill — execute

Spec: AC33 (L288-298) · Review: final · Wave: 1 · Touches: `studios/game-dev/skills/execute/SKILL.md`, `tests/pointer_skills_execute_test.sh` (new)

Text changes, at current anchors (the spec's are shifted by #41):
1. :63-65 ("`studio-state` keeps the pointer in the project's main checkout, so every call below works the same from inside a worktree") → AC33's first bullet, verbatim.
2. §0, before "Which run this is" (:41): the `stories` step.
   - In the main checkout at `stage idle`, run `studio-state stories`.
   - Exactly one `active` line at `plan` or `execute` (a `run` line never counts) → **Enter the feature checkout** the Exit 0 way, and run §0 there.
   - Several → ask once.
   - None → today's stop.
   - A non-zero `stories` exit stops and shows its message.
3. §0, before its first check: **the resume from the worktree that a stop before (c) left the session in**. Use AC33's fourth bullet, with both sub-cases, verbatim in substance: `studio-state take <spec>`, then continue as **a resume that found no `branch`**; and the missing-gate-commits stop with its `git merge --ff-only` text.
4. (a) at :157-169: add the last case. **Any other exit 1** from `studio-state worktree` stops and shows its stderr; only `no feature branch recorded` isolates. Keep the pin `then do not isolate`.
5. (c) at :179-191, before its `set branch`:
   - when this run's §0 ran in the main checkout outside a lane, and `git rev-parse --show-toplevel` is not the first `worktree` line of `git worktree list --porcelain`, first run `studio-state handoff "$(git rev-parse --show-toplevel)"` inside the new worktree;
   - any non-zero exit stops and shows the message (a killed call included);
   - in place (the (b) consent at :170-171; the default-branch path at :555-558), no hand-off runs, and `set branch` writes the main pointer as today;
   - a worktree-born story runs no hand-off.
   - Keep the pins `studio-state set branch "$(git branch`, `before the fast-forward` and `ledger "base`.
6. (c)'s base: any resume whose feature ledger has no `base <branch>` line writes and commits one, after the ancestor check. The branch is the noted branch, except when the noted branch is the story's own `branch`; then it is the main checkout's current branch, or the default branch on a detached main checkout. Adjust "The base" (:193-201) to match.
7. §7 step 3 (:549): "`studio-state set milestone <next>` writes the project's milestone (the main checkout's pointer, from any checkout)".

- [ ] **Step 1: Write the pins** in `tests/pointer_skills_execute_test.sh`, then run it. Expect FAIL.
  - `test_skill_execute_handoff_at_isolation`: `studio-state handoff "$(git rev-parse --show-toplevel)"`, `is not the main checkout`, `any non-zero exit`, `no hand-off runs`, `worktree-born story`.
  - `test_skill_execute_resume_via_stories`:
    - `studio-state stories`, `a \`run\` line never counts`, `studio-state take <spec>`, `a resume that found no \`branch\``, `the gate commits are not in this worktree`;
    - `any resume whose feature ledger has no \`base`, `main checkout's current branch`, `Any other exit 1`;
    - and does not contain `keeps the pointer in the project's main checkout`.
- [ ] **Step 2:** Edit. Run `sh tests/pointer_skills_execute_test.sh; sh tests/studio_test.sh`. Expect PASS: every `test_execute_*` pin is kept, and :443's not-contains still holds.
- [ ] **Step 3: Commit.** `git commit -m 'docs(execute): hand off at isolation, resume through stories (#42)' -- studios/game-dev/skills/execute/SKILL.md tests/pointer_skills_execute_test.sh`

---

### Task 9: Skills — review, playtest, retro

Spec: AC34, AC35 (L299-302) · Review: final · Wave: 2 · Touches: `studios/game-dev/skills/review/SKILL.md`, `studios/game-dev/skills/playtest/SKILL.md`, `studios/game-dev/skills/retro/SKILL.md`, `tests/studio_test.sh`

Text changes:
- **review :27-30 and playtest :30-33 (Exit 1):** AC34's first bullet, verbatim. Keep `enter the chosen checkout the Exit 0 way`.
- **review :55-62 and playtest :50-57 (which feature):** the cause reads "this checkout's pointer moved on to the next feature". Keep the literal `pointers now name`, e.g. "this checkout's pointer moved on to the next feature: the studio pointers now name `<spec>`; …".
- **Playtest** must still not contain `AskUserQuestion` (pin :369). Write "ask the user once".
- **retro :16-35:**
  - resolve with `studio-state worktree` from the main checkout. At exit 0 it reads in place with `(cd <path> && studio-state show)`;
  - at exit 1 with candidates, it asks the user once which story — "the only question retro asks". For a `removed` candidate it reads `git show <branch>:.studio/ledger/<slug>.md` and creates no worktree;
  - exit 3 is as today;
  - :16-18 is reworded to "asks at most that one question", plus the adopt note (f2-M11).
  - Keep `studio-state worktree`, `git show`, `read only \`STATE.md\`` and `for the current stage`.
  - It must not contain `AskUserQuestion`.

- [ ] **Step 1: Edit the pins in `tests/studio_test.sh`.**
  - In `test_retro_contract` (:376-390):
    - replace :384's assert with `assert_contains "$T" "At exit 1 with candidates, ask the user once which story"`;
    - remove `'AskUserQuestion'` from :385's not-contains list;
    - add `assert_contains "$T" "the only question retro asks"`.
  - Add `test_skill_review_playtest_ask_candidates`: both files contain `more than one story fits, a removed story's worktree is offered, or none is recorded`, `run its command, then enter the path it added` and `this checkout's pointer moved on to the next feature`.
  - Add `test_skill_retro_resolves_story`: contains `(cd <path> && studio-state show)`, `\`removed\` candidate`, `creates no worktree` and `one-time adopt`.
  - Add both to `run_tests`. Run the file. Expect FAIL.
- [ ] **Step 2:** Edit the three skills. Run `sh tests/studio_test.sh`. Expect PASS.
- [ ] **Step 3: Commit.** `git commit -m 'docs(skills): review, playtest and retro choose among stories (#42)' -- studios/game-dev/skills/review/SKILL.md studios/game-dev/skills/playtest/SKILL.md studios/game-dev/skills/retro/SKILL.md tests/studio_test.sh`

---

### Task 10: omega handoff, autopilot pin, memory note, PROGRESS

Spec: AC19 (omega), AC36, AC44-AC46 (L225, L303, L349-358) · Review: final · Wave: 2 · Touches: `shared/omega/skills/handoff/SKILL.md`, `tests/pointer_skills_omega_test.sh` (new), `studios/game-dev/memory/stage-pointer-is-per-checkout.md` (new), `studios/game-dev/memory/MEMORY.md`, `docs/game-dev/PROGRESS.md`

**Changes:**
- **omega handoff :34-35, :39-41 and :83:** every `studio-state show` and `get` there runs as `STUDIO_STATE_NO_ADOPT=1 studio-state …`. Add one sentence: "with `STUDIO_STATE_NO_ADOPT=1`, so reading never moves a story (studio-state AC18)".
- **Autopilot:** no text change.
- **Memory note:** frontmatter `name: stage-pointer-is-per-checkout`, a one-line `description`, `metadata:` / `type: feedback`. The body carries AC44's five points. `MEMORY.md` gains one line in its existing format: `- [Stage pointer is per checkout](stage-pointer-is-per-checkout.md) — <hook>`.
- **PROGRESS:** a new top entry, `### 2026-10-05 — A stage pointer per checkout (#42)`. Bullets:
  - the behaviour (per-checkout pointer, moves, `stories`, the runner follow);
  - the recovery text for a clobbered worktree or an invisible finished story: `set spec`, `set plan`, `set stage`, `set task 0/<N>` and `check --rebuild` (AC43's last rows);
  - the stale-tool caveat (AC46);
  - "the per-machine phoenix note `~/.claude-gamedev/projects/-Users-xinli-GameDev-proj-phoenix/memory/studio-state-is-shared-across-stories.md` (and its `_practice` copies) can be deleted once this lands and is reinstalled";
  - "reinstall only when `studio-overnight status` shows no live run".

- [ ] **Step 1: Pins** in `tests/pointer_skills_omega_test.sh`:
  - `test_skill_omega_handoff_no_adopt`: every line of the handoff SKILL with `studio-state show` or `studio-state get` also contains `STUDIO_STATE_NO_ADOPT=1`. Check with `grep -n 'studio-state \(show\|get\)' | grep -vc NO_ADOPT` = 0, and the count of such lines ≥ 2.
  - `test_skill_autopilot_no_force`: autopilot contains `studio-state init --local`, `studio-state set stage plan` and `studio-state set spec <spec>`, and has no `--force` on any `studio-state set` line.
  - `test_memory_stage_pointer_note`: the note exists with `name: stage-pointer-is-per-checkout`, `type: feedback`, `studio-state handoff`, `studio-state take <spec>`, `studio-state stories`, `never \`--force\`` and `.superpowers/sdd/`; `MEMORY.md` links it once.
  - Run it. Expect FAIL.
- [ ] **Step 2:** Edit. Run `sh tests/pointer_skills_omega_test.sh; sh tests/omega_test.sh`. Expect PASS. If `omega_contracts/handoff_contract.sh` pins the old call text, update the pin in this task and add it to Touches.
- [ ] **Step 3: Commit.** `git commit -m 'docs: omega handoff never adopts; memory and progress for #42' -- shared/omega/skills/handoff/SKILL.md tests/pointer_skills_omega_test.sh studios/game-dev/memory/stage-pointer-is-per-checkout.md studios/game-dev/memory/MEMORY.md docs/game-dev/PROGRESS.md`

---

### Task 11: The single-plan runner follows its story

Spec: AC38, AC39 (L308-317), Test strategy `overnight_test.sh` (L579-602) · Review: task (Opus) · Wave: 5 · Touches: `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-channel.sh`, `tests/overnight_test.sh`, `tests/overnight_progress_test.sh`

**Interfaces:**
- Consumes: `studio-state stories` (six TSV fields), the `handed` move-record format, and `handoff`/`take`.
- Produces in studio-overnight:
  - `RUN_SPEC`;
  - `run_spec`;
  - `story_resolve` (sets `STORY_DIR`, `STORY_WHY`; returns 0/1 in the current shell);
  - `story_dir` (prints `STORY_DIR`, or START_DIR when unresolved);
  - `start_state` (the old `state()`).
- Lock and registry gain `spec=<spec>` for a single-plan run only. `overnight-progress.sh` needs no edit: `:80` calls `state`, which now follows.

```sh
start_state() { ( cd "$START_DIR" && sh "$STATE_BIN" "$@" ); }
# run_spec — AC38 (f2-M6): the single-plan run's spec. RUN_SPEC in the runner;
# elsewhere the lock's spec=, else its registry entry's. "" for a manifest run,
# a pre-#42 record, or spec -.
run_spec() {
  _rsp="${RUN_SPEC:-}"
  [ -n "$_rsp" ] || _rsp="$(runs_kv spec "$LOCK")"
  if [ -z "$_rsp" ]; then
    _rr="$(runs_kv run "$LOCK")"
    for _re in "${REGISTRY:-$HOME/.claude-gamedev/runs}"/overnight-* "${REGISTRY:-$HOME/.claude-gamedev/runs}/last"; do
      [ -f "$_re" ] && [ -n "$_rr" ] && [ "$(runs_kv run "$_re")" = "$_rr" ] || continue
      _rsp="$(runs_kv spec "$_re")"; break
    done
  fi
  [ "$_rsp" != - ] || _rsp=""
  printf '%s\n' "$_rsp"
}
# story_resolve — AC38: STORY_DIR, the checkout whose pointer holds the run's
# story, in the current shell. START_DIR under STUDIO_STORY or with no persisted
# spec, and while START_DIR's own spec is the run's; else the one `stories`
# line with that spec (run lines skipped); else main's newest handed line for
# it when its path is a live worktree. 1 with STORY_WHY when ambiguous or gone.
story_resolve() {
  STORY_DIR="$START_DIR"; STORY_WHY=""
  _sp="$(run_spec)"
  [ -z "${STUDIO_STORY:-}" ] && [ -n "$_sp" ] || return 0
  [ "$(start_state get spec 2>/dev/null)" != "$_sp" ] || return 0
  _hits="$(start_state stories 2>/dev/null | ST_S="$_sp" awk -F'\t' '$4 == ENVIRON["ST_S"] && $6 != "run" { print $1 }')"
  case "$(printf '%s\n' "$_hits" | grep -c .)" in
    1) STORY_DIR="$_hits"; return 0 ;;
    0) ;;
    *) STORY_WHY="ambiguous story $_sp"; return 1 ;;
  esac
  _hp="$(ST_S="$_sp" awk -F'\t' '/^## Ledger/ { f = 1; next }
          f && $1 ~ / handed$/ && $2 == "spec=" ENVIRON["ST_S"] { p = $NF } END { sub(/^path=/, "", p); print p }' \
          "$STATE_ROOT/.studio/STATE.md" 2>/dev/null)"
  if [ -n "$_hp" ] && [ -d "$_hp" ] && git -C "$START_DIR" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $_hp"; then
    STORY_DIR="$_hp"; return 0
  fi
  STORY_WHY="story $_sp not found"; return 1
}
story_dir() { story_resolve || true; printf '%s\n' "$STORY_DIR"; }
state() { _sd="$(story_dir)"; ( cd "$_sd" && sh "$STATE_BIN" "$@" ); }
```

On failure `story_resolve` leaves `STORY_DIR` at START_DIR, so `story_dir` always prints a usable directory. The handed line's path is compared with `pwd -P` paths, which is how studio-state records them.

**Wiring** (anchors at base):
- **Preflight (:415-452):** every `state` call becomes `start_state`. In the `no spec or plan set` refusal, for each `start_state stories` line with state `active`, append ` — the story is in <path>`.
- **`take_lock` (:199):** before the `( set -C …)`, set `[ -n "$RUN_SLUG" ] || RUN_SPEC="$(start_state get spec 2>/dev/null)"`. The lock text gains `spec=%s\n` when `RUN_SPEC` is non-empty.
- **`reg_write` (:976):** the same `spec=` line.
- **`feature_dir` (:550):**
  `_sd="$(story_dir)"; _w="$(cd "$_sd" && sh "$STATE_BIN" worktree 2>/dev/null)"`; fall back to `$_sd`, not START_DIR.
- **`snapshot` (:560-580):** compare `FEATURE_DIR` with `$(story_dir)`, and read `ledger_of "$(story_dir)"` for the start side (Ruling R2). Lanes are unchanged, because `story_dir` is START_DIR under STUDIO_STORY.
- **`story_units` (:1212):** first in the loop body, `story_resolve || { ENDING="stop: $STORY_WHY"; return 0; }`.
- **`start_session` (:1004):** `cd "${UNIT_CWD:-$(story_dir)}"`.
- **Resume (:1132):** `cd %s` with `$(sq "$(story_dir)")`.
- **`single_status` (:1527):** `if story_resolve; then _ss_t="$(state get task 2>/dev/null)"; else _ss_t="$STORY_WHY"; fi`. Print `task: $_ss_t`.
- **`chan_ledger` (`overnight-channel.sh:186`):** for `CH_STORY = -`, run `LOCK="$CH_LOCK"; START_DIR="$CH_START"`, then `cd "$(story_dir)"` and `show`, in place of the `worktree` lookup. The STUDIO_STORY branch is unchanged. The channel is sourced by studio-overnight, so `story_dir` is in scope (`:9`).
- The header comment at :17 ("calls its siblings studio-state") gains "the single-plan story is read where its pointer is (`story_dir`, #42)".

**Stub** (`tests/overnight_test.sh:50-53`), new actions:

```sh
    "branch "*)   b="${act#branch }"
                  git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  cd "$TMP_WT/wt-$b" && sh "$STUB_STATE_BIN" handoff "$(pwd -P)" >/dev/null 2>&1
                  sh "$STUB_STATE_BIN" set branch "$b" ;;
    "legacybranch "*) b="${act#legacybranch }"
                  git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  sh "$STUB_STATE_BIN" set branch "$b" ;;
    inplace)      git checkout -q -b feat && sh "$STUB_STATE_BIN" set branch feat ;;
    stopbeforec)  sh "$STUB_STATE_BIN" ledger "Stop: stopped before isolation" ;;
    wtcheck)      _w=0; sh "$STUB_STATE_BIN" worktree >/dev/null 2>&1 || _w=$?; echo "$_w" > "$CALLS/$n.wt" ;;
    "dupstory "*) b="${act#dupstory }"; ( git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  cd "$TMP_WT/wt-$b" && for a in "stage brainstorm" "spec docs/spec.md" "stage plan"; do sh "$STUB_STATE_BIN" set $a; done ) >/dev/null 2>&1 ;;
    "rmwt "*)     ( cd / && git -C "$root" worktree remove --force "$TMP_WT/wt-${act#rmwt }" ) >/dev/null 2>&1 ;;
```

The later actions of a `branch` line run in the worktree, because the stub `cd`s there.

- [ ] **Step 1: Rewrite the scenarios.**
  - **Unchanged text**, now meaning the real hand-off: :574 (`copied`), `ISO1` (:666) and its users, :1643, :1656, :1668, :1677, :1691 and :1767.
  - **Ruling R1, proposed:**
    - `sls` (:1565) and `pl2` (:1710) switch `branch feat` → `inplace`, keeping their asserts;
    - `sls3` (:1570) switches to `inplace`, keeping its asserts. The two-ledger tie is unreachable for a single-plan run under H; see R1.
    - Implement as ruled. If the operator has not ruled, implement the proposal and flag it in the hand-back.
  - :492 and :508 assert unit 1's cwd only, so they stay.
- [ ] **Step 2: Write the failing tests.** Hard ones in full:

```sh
test_single_plan_follows_story_after_unit_1() {
  fixture fol
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b" \
           "task 2/2; wtledger T2 complete b..c" "wtledger final review done" \
           "wtledger shipped https://x/pull/1; stage idle; task -"
  run_start
  WE="$(cd "$TMP_WT/wt-feat" && pwd -P)"
  assert_eq "$P" "$(cat "$CALLS/1.pwd")" "unit 1 starts in START_DIR"
  assert_eq "$WE" "$(cat "$CALLS/2.pwd")" "unit 2 starts in the story's worktree"
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "the run ends done"
  assert_eq idle "$(cd "$P" && sh "$STATE_BIN" get stage)" "P is idle after the hand-off"
  assert_contains "$CALLS/1.lock" "^spec=docs/spec.md$" "the lock persists the run's spec"
}
test_single_plan_rerun_after_stop_before_handoff() {
  fixture rrs
  scenario "stage execute; stopbeforec" \
           "wtcheck; branch feat; task 1/2; wtledger T1 complete a..b" \
           "task 2/2; wtledger T2 complete b..c; wtledger final review done" \
           "wtledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: stopped before isolation$" "unit 1 stops before (c)"
  ( cd "$P" && git add .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm stop ) >/dev/null 2>&1
  run_start
  assert_eq 1 "$(cat "$CALLS/2.wt")" "the re-run's worktree exits 1 (no feature branch recorded)"
  assert_eq "$(cd "$TMP_WT/wt-feat" && pwd -P)" "$(cat "$CALLS/3.pwd")" "unit 2 of the re-run runs in the story worktree"
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "and it finishes"
}
test_single_plan_story_not_found_stops() {
  fixture snf
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; rmwt feat"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: story docs/spec.md not found$" "a removed story worktree stops the run"
}
```

  The others, as asserts:
  - `test_single_plan_resume_line_names_story_worktree`: `ISO1`, then `wtledger Stop: need art` → the report's Resume line is `cd '<WE>' && '<runner>' start`.
  - `test_single_plan_ambiguous_story_stops`: `"$ISO1; dupstory dup"` → `^Ending: stop: ambiguous story docs/spec.md$`.
  - `test_single_plan_preflight_names_story`: after a full `ISO1` run that stops, `start` from P is refused with `no spec or plan set` and `— the story is in <WE>`.
  - `test_single_plan_from_story_worktree` (AC39):
    - reset P (`reset --keep-ledger`); create WA from HEAD; in WA, set stage plan, spec and plan (auto-create);
    - record `cksum` of P's pointer; run `start` from WA with a done scenario;
    - P's `cksum` is unchanged, and `1.pwd` is WA.
  - `test_single_plan_in_place_keeps_main_pointer`: `"stage execute; inplace; task 1/2; ledger T1 complete a..b"`, then a finish → `2.pwd` = P, P's `get branch` = `feat`, and P's ledger has no `handed` line.
  - `test_channel_ledger_follows_story`: during a held `ISO1` + `wtledger Stop: need art` run (`holds_on`), `verb say - x` succeeds and the channel's ledger view (the `msgs`/`list` verb that prints ledger-backed rows) shows WE's `Stop: need art`.
  - `test_status_reads_persisted_spec`:
    - `start_bg` with `"$ISO1; sleep 3"`; `status` from P prints `task: 1/2`;
    - with `"$ISO1; rmwt feat; sleep 3"`, it prints `task: story docs/spec.md not found`.
  - `test_single_plan_ignores_new_story_in_start` (Review Focus 5, R2): `"$ISO1; sleep 2"`, then `"task 2/2; …"` while the test, between units, runs in P `set stage brainstorm`, `set spec docs/other.md` and `ledger "Stop: unrelated"` → the run is not stopped by `unrelated`.
  - `overnight_progress_test.sh` `test_progress_task_follows_story`: a single-plan run dir whose lock has `spec=docs/s.md`; P is idle; a linked worktree WE holds `docs/s.md` at `task 2/3` → the progress block's task-left is computed from `2/3`. The fixtures at `spec: -` (:137, :151, :188, :195) keep their asserts.
- [ ] **Step 3:** Run `sh tests/overnight_test.sh`. Expect FAIL on the new tests. Implement.
- [ ] **Step 4:** Run `sh tests/overnight_test.sh; sh tests/overnight_progress_test.sh; sh tests/overnight_runs_test.sh; sh tests/studio_test.sh` (`test_bin_syntax`). Expect PASS. Do not run the lanes suite while these run.
- [ ] **Step 5: Commit.** `git commit -m 'feat(overnight): the single-plan runner follows its story (#42)' -- studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-channel.sh tests/overnight_test.sh tests/overnight_progress_test.sh`

---

### Task 12: Lanes pin — a final unit's Stop pointer stays invisible

Spec: AC40 (L318), Test strategy (L590) · Review: final · Wave: 3 · Touches: `tests/overnight_lanes_test.sh`

Test `test_lanes_final_unit_stop_pointer_invisible`:
- use the suite's existing final-unit fixture (grep `final_unit` in the test file for the helper);
- the final-unit stub writes `studio-state ledger "Stop: x"` in FINAL_W, with no STUDIO_STORY;
- assert that `FINAL_W/.studio/STATE.md` exists, that `git -C FINAL_W status --porcelain` is empty (lanes :1612's check), and that after `git -C FINAL_W clean -fdq` (lanes :1616) the file still exists (excluded, not untracked).

- [ ] **Step 1:** Write the test.
- [ ] **Step 2:** Run `sh tests/overnight_lanes_test.sh`. Expect PASS (T2 provides auto-create), and the whole lanes suite green. Report any lanes red, with its line.
- [ ] **Step 3: Commit.** `git commit -m 'test(lanes): a final unit Stop pointer stays out of git (#42)' -- tests/overnight_lanes_test.sh`

---

### Task 13: Final whole-branch review, fix wave, gate, PR

Review: Opus, standalone · Wave: 6

- [ ] **Step 1: Final review.**
  - Dispatch on Opus a fresh reviewer, given the spec path, this plan's path and the range `3994275..HEAD`.
  - Focus: the five Review Focus lines; AC12-AC19's crash points (read every `test_seam` site against AC13's list); the lock discipline (every write path reaches `lock_or_fail`; no `mx_take` outside an `||`/`if`; no child `studio-state` while the mutex is held; traps); AC44-AC46 text; and the gap fills G1-G7.
  - The reviewer writes its full report to `.superpowers/sdd/2026-10-05-per-story-pointer/final-review.md` and hands back 1.5k characters or less.
- [ ] **Step 2: Fix wave.** A fresh fixer gets the findings and the range. Minors are batched. Re-review only per the policy.
- [ ] **Step 3: Gate.** Run `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh`. Both green, compared with T1's `baseline.md`.
- [ ] **Step 4: PR.** `gh pr create`. The body:
  - the summary;
  - the AC list;
  - the rulings R1/R2 as ruled;
  - the gap fills G1-G7;
  - the recovery text (AC43, AC46): a worktree-born story whose worktree was removed, or a clobbered one, is recovered with `set spec`, `set plan`, `set stage`, `set task 0/<N>` and `check --rebuild`;
  - the stale-tool caveat (AC46);
  - **"Reinstall after merge, and only when `studio-overnight status` shows no live run; do not pull the main checkout while a run is live."**;
  - **"After landing and reinstalling, delete the per-machine phoenix note `~/.claude-gamedev/projects/-Users-xinli-GameDev-proj-phoenix/memory/studio-state-is-shared-across-stories.md` and its `_practice` copies."**;
  - Milestone gate step 3 as the operator's live check.
  - It ends with the session attribution lines.
- [ ] **Step 5: After merge** (operator authority: merge once the gate is green):
  - reinstall only with no live run;
  - the operator runs Milestone gate step 3 on phoenix, then deletes the phoenix note;
  - drop this worktree (`ExitWorktree remove`).

---

## Task order

| Wave | Tasks (parallel) | Suites run | Review |
|---|---|---|---|
| 0 | T1 | full baseline, `overnight_runs_test.sh` | final |
| 1 | T2 · T7 · T8 | state, hook, brief, setup, adopt, peers, studio · route pins, studio · execute pins, studio | T2 task (Opus) |
| 2 | T3 · T9 · T10 | state (guard, pointer, test) · studio · omega pins, omega | T3 task (Opus) |
| 3 | T4 · T12 | state (move, pointer, guard, test) · lanes | T4 task (Opus) |
| 4 | T5 · T6 | state (all), studio · hook | T5 task (Opus) |
| 5 | T11 | overnight, progress, runs, studio | T11 task (Opus) |
| 6 | T13 | full gate + multica | final (Opus) |

---

## Falsify — load-bearing claims about the code at 3994275

| # | Claim | Status | Evidence |
|---|---|---|---|
| 1 | studio-state's pointer resolution is :54-60 (`_gd`/`_gcd` :55-56, local at :57-58, LINKED :60) | OK | studio-state:54-60 |
| 2 | STUDIO_STORY resolution is :61-65 | OK | studio-state:61-65 |
| 3 | The header comment is :2-9, and the `Exit:` line is part of the header | FIXED | the comment runs :2-28; `Exit:` is :26-28 |
| 4 | `usage` :72-75; `write_idle_state` :86-100 includes `milestone: prototype` | OK | studio-state:72-75, :95 |
| 5 | `write_field` :114-122 writes tmp + `mv` | OK | studio-state:115-121 |
| 6 | `set_branch` :134-147 inserts `branch:` after `task:` | OK | studio-state:139-146 |
| 7 | `ledger_file` :168-172 sends lines to the feature ledger while `spec` is set | OK | studio-state:168-172 |
| 8 | `init --local` :192-203, exclude with newline repair :198-201 | OK | studio-state:192-203 |
| 9 | `init --local`'s second-call text is `init --local: <path> already exists` | OK | studio-state:195 |
| 10 | `init` :223-243 | OK | studio-state:223-243 |
| 11 | `reset` :364-381 writes `abandoned` to `$STATE` only when a spec is set | OK | studio-state:371-374 |
| 12 | `worktree` :382-425; prefix/prune :403-420; exit 3 :421-424 | OK | studio-state:382-425 |
| 13 | The STUDIO_STORY rebuild counts `### Task` above `## Backlog` | OK | studio-state:307 |
| 14 | studio-state sources nothing today; siblings source `overnight-runs.sh` via `SELF_DIR` | OK | studio-adopt:17-18; studio-overnight:27-33, :409 |
| 15 | `mx_take`/`mx_drop` are at `overnight-runs.sh:97-110` | FIXED | `mx_take` :97-107, `mx_reap` :108-125, `mx_drop` :126-127 |
| 16 | #39 merged a race-free reap (`.reap` mkdir lock, same-dead-pid re-check, stale > 5 s broken) | OK | overnight-runs.sh:113-125 |
| 17 | `test_mutex_reap_race` exists at `tests/overnight_runs_test.sh:119` | OK | :119-139 |
| 18 | A test pins the stale (> 5 s) reap lock | FIXED | none existed; T1 adds `test_mutex_stale_reap_lock_broken` |
| 19 | `overnight-runs.sh` has only function definitions at top level (safe to source) | OK | awk scan of the file: no top-level statements |
| 20 | Under `set -eu`, a failing `x="$(cmd)"` inside a function exits the script unless the call is in an `||`/`if` context | OK | verified with `sh -c` on this machine (bash 3.2) |
| 21 | A background job of a non-interactive sh ignores SIGINT unless started under `set -m` | OK | verified on this machine (`nojc` vs `jc` probe) |
| 22 | `state()` is `studio-overnight:40` | OK | :40 |
| 23 | `take_lock` writes pid/run/started/start at :201 | FIXED | :197-202 |
| 24 | `reg_write` fields at :969 | FIXED | :976-984 |
| 25 | preflight :412-430 | FIXED | :415-452 (`state get stage` :419, spec/plan :428-429, refusal :431, `state show` :434) |
| 26 | `ledger_of`/`feature_dir` :535-541 | FIXED | :547-549, :550-553 |
| 27 | snapshot :551 | FIXED | :560-580; start side `ledger_of "$START_DIR"` :577 (R2) |
| 28 | `start_session`'s unit cwd :992 | FIXED | :1004 |
| 29 | the Resume line :1104 | FIXED | :1132 |
| 30 | the loop's stage checks :1189, :1196 | FIXED | `story_units` :1221, :1229 |
| 31 | `status` `state get task` :1495; reap/report subshells :1513, :1548 | FIXED | `single_status` :1531; `status_reap_dead` :1544-1553; `project_status` block subshell :1590 |
| 32 | lanes reuse `snapshot`/`story_units`, so `story_dir` must be START_DIR under STUDIO_STORY or with no persisted spec | OK | overnight-lanes.sh:8, :76 |
| 33 | `chan_ledger` :186-192 runs `worktree` from CH_START | OK | overnight-channel.sh:186-192 (:189) |
| 34 | `chan_find_run` sets CH_LOCK and CH_START; the channel is sourced by studio-overnight | OK | overnight-channel.sh:105-158, :9 |
| 35 | `overnight-progress.sh` :66 reads STUDIO_STORY, :80 `state get task` | OK | :66, :80 |
| 36 | lanes' FINAL_W porcelain check is :1427 | FIXED | :1612; `git clean -fdq` :1616 |
| 37 | lanes final units unset STUDIO_STORY | OK | overnight-lanes.sh:1898 |
| 38 | the stub's `branch` action is :50-52 (worktree add, then `set branch` from the unit cwd) and `wtledger` :53 | OK | tests/overnight_test.sh:50-53 |
| 39 | stub actions run in the unit's cwd with no `cd` | OK | tests/overnight_test.sh:21-80 |
| 40 | the deny-bin copy carries `overnight-runs.sh` | OK | tests/overnight_test.sh:370 |
| 41 | the affected scenario lines are :574, :666, :1565, :1570, :1643, :1656, :1668, :1677, :1691, :1710, :1767 | OK | grep at base |
| 42 | :1565 (`sls`) and :1570 (`sls3`) keep their asserts after a switch to `legacybranch` | FIXED | false; adopt on the runner's `ledger_of WE` / the stub's `wtledger` moves the story → R1 |
| 43 | :1710 (`pl2`) keeps "ledger Stop: start side" with the new `branch` | FIXED | false; unit 2 runs in WE, so the stop is feature-side and holds → R1 |
| 44 | :492 and :508 assert unit 1's cwd only | OK | tests/overnight_test.sh:492, :508 |
| 45 | `overnight_progress_test.sh` `spec: -` fixtures at :135-193 | FIXED | :137, :151, :188, :195 |
| 46 | `session-start.sh` comment :15-17, calls :19-20, stage line :94 | OK | session-start.sh:15-20, :94 |
| 47 | `bootstrap.md` :27 is the State paragraph | OK | bootstrap.md:27 |
| 48 | studio SKILL :16 show, abandon :66-71, bug route :90, Rules :104-107 | OK | studio/SKILL.md |
| 49 | brainstorm §0 :16-19, `set stage brainstorm` :61, `set spec` :261 | OK | brainstorm/SKILL.md:16-19, :61, :261 |
| 50 | plan §0 spec check :28-33, writes :151-153 | OK | plan/SKILL.md |
| 51 | execute "Which run this is" :31-55 | FIXED | :41-57 (#41's block at :12-20 shifted it) |
| 52 | execute's pointer sentence :53-55 | FIXED | :63-65 |
| 53 | execute (a) :149-158; consent :160-161; (c) :169-171 | FIXED | (a) :157-169; (b) consent :170-171; (c) :179-191 |
| 54 | execute §7 step 3 :534; default-branch path :539-542 | FIXED | :549; :555-558 |
| 55 | execute `using-git-worktrees` skip :588-590 | FIXED | :603-605 |
| 56 | review :20-30, :55-62; playtest :23-33, :50-57 | FIXED | review :20-33, :55-62; playtest :23-36, :50-57 |
| 57 | retro :16-35 holds the exit-1 text the pin quotes | OK | retro :31-33; tests/studio_test.sh:384 |
| 58 | `test_retro_contract` is at :375-388 | FIXED | :376-390 (pin :384, not-contains :385) |
| 59 | playtest pins `assert_not_contains 'AskUserQuestion'` | OK | tests/studio_test.sh:369 |
| 60 | omega handoff calls `studio-state` at :34-35 and :39-41 | FIXED | also :83 (`studio-state show`); T10 covers all three |
| 61 | autopilot :81 `init --local`; `.studio/run` written at :100 before :121 and :135 | OK | autopilot/SKILL.md:81, :100, :121, :135 |
| 62 | state_test anchors :171, :276, :419 (from-inside :443-445), :483-510, :621, :629-636, :638, :80/:86, :548-592; `rw_fixture` :610 | OK | tests/state_test.sh |
| 63 | `test_state_worktree_edges` holds through AC22's main-at-idle rule | UNVERIFIED | reasoned, not run; T5 runs it and reports instead of editing |
| 64 | `hook_test.sh` `run_hook` :51, `test_hook_reports_stage` :277 | OK | tests/hook_test.sh |
| 65 | `studio_setup_test` adds a linked worktree at :50; `studio-setup` calls only `root` | OK | studio_setup_test.sh:50; studio-setup:53 |
| 66 | studio-adopt calls `root` at :79 and otherwise only under STUDIO_STORY | OK | studio-adopt:79, :453, :530, :683, :686 |
| 67 | the Multica bridge parses registry kv, so an extra `spec=` key is harmless | OK | integrations/multica/bridge/studio.py:55-61 |
| 68 | `run_all.sh` runs every `tests/*_test.sh`, so `state_fixtures.sh` is not run | OK | tests/run_all.sh |
| 69 | `test_bin_syntax` requires +x on `studios/*/bin/*` | OK | tests/studio_test.sh:108-118; no new bin file |
| 70 | `hooks.json` :5 matcher `startup\|clear\|compact` | OK | hooks.json:5 |
| 71 | execute pins kept: `new run clears`, `then do not isolate`, `ledger "base`, `studio-state set branch "$(git branch` | OK | tests/studio_test.sh:253-283 |
| 72 | review/playtest pins `pointers now name` and `enter the chosen checkout the Exit 0 way` | OK | tests/studio_test.sh:331, :364-365 |
| 73 | `/clear` re-runs SessionStart in the EnterWorktree directory | UNVERIFIED | harness behaviour (spec Open item 1); Milestone gate step 3 observes it |
| 74 | the phoenix memory note exists at the path AC45 names | UNVERIFIED | per-machine file; reading phoenix is out of bounds for this plan |

Counts: **OK 47 · FIXED 24 · UNVERIFIED 3** (74 claims).

---

## Rulings needed

Spec ACs whose premise no longer holds after #39's final merge, or that the code contradicts. None is changed silently. Each has a proposal that the plan implements unless the operator rules otherwise.

- **R1 — `sls`/`sls3`/`pl2` (Test strategy, "Existing tests that change", L602; f2-M13).**
  - The spec says :1565 (`sls`) and :1570 (`sls3`) switch to `legacybranch` and keep their asserts. They cannot.
    - Under `legacybranch`, P stays at `execute` with `branch feat`, so the first `studio-state` call in the pointer-less WE adopts the story (AC18). That is the runner's `ledger_of WE` for `sls`, and the stub's `wtledger` for `sls3`.
    - After the adopt, P is idle, and the start-ledger `Stop:` is never read.
  - `pl2` (:1710), which the spec did not list, also breaks under the new `branch`: unit 2 runs in WE, so its "start side" stop is feature-side and holds.
  - Proposed: `sls` and `pl2` → `inplace`, keeping their asserts. `sls3` → `inplace`, keeping its asserts; the two-ledger tie it was written for is unreachable for a single-plan run under H. It stays reachable under lanes, with no lanes test pinning it.
- **R2 — the runner's start-side ledger (AC38; `snapshot` :577, not listed in AC38).**
  - After a hand-off, `ledger_of "$START_DIR"` reads P's pointer.
  - P is idle, or holds a new story T that the user started there. A `Stop:` in T's ledger would stop the overnight run.
  - Proposed: `snapshot` reads `story_dir` for the start side (one ledger after the follow; START_DIR before it, under lanes, and for pre-#42 records). Pinned by `test_single_plan_ignores_new_story_in_start`.
