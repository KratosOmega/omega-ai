# Overnight Lanes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Approved 2026-10-01

**Goal:** Autopilot takes any set of stories to a merged or reviewable
state. Stories without a plan are planned with the user, one stage per
session. Once every plan is approved, `studio-overnight start <manifest>`
runs dependency chains as parallel lanes of fresh headless sessions. The
runner itself lands each story (integration or direct) under one gate lock
per machine.

**Architecture:** Bundle 2's runner (`studio-overnight`) keeps its
single-plan path. Its unit loop becomes a function, and a sibling file
`overnight-lanes.sh`, sourced only in manifest mode, adds four pieces:
1. manifest parsing and the chain rule;
2. the lane processes;
3. the runner-owned per-story machine;
4. landings and the integration final step.

`studio-state` gains per-story selection (`STUDIO_STORY`). `studio-brief`
gives each unit exactly its inputs. `studio-gate` is the one implementation
of the machine-wide gate lock: `studio-test`, `studio-run` and the runner all
go through it. The skills change as text contracts.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2), git ≥ 2.38
(`merge-tree --write-tree`), `gh`, Claude Code ≥ 2.1.287 headless flags,
bash-as-sh tests (`tests/assert.sh`), Markdown skills.

**Spec:** `docs/game-dev/specs/2026-10-01-overnight-lanes.md`

**Cut in the scope pass:** none. The producer proposed cutting T13; it is
kept by ruling D28.

**Review policy (user CLAUDE.md, and this spec's own `Review:` rule):**
- Each task carries `Spec:` (its spec line ranges) and `Review: task|final`
  under its heading. This plan uses the format it introduces.
- A `Review: task` task gets a per-task review on Opus. A `Review: final`
  task folds into the final review.
- Minor findings are batched into the final fix wave. Every fix round goes
  to a fresh fixer.
- Re-review only after a Critical, three or more Importants, or a
  production-bug fix. Never a third pass.
- The final review is a standalone whole-branch review on Opus. Then the
  gate: `sh tests/run_all.sh`.

## Global Constraints

Copied verbatim from the spec (line numbers in parentheses). Every task's
requirements implicitly include this section.

**Milestone gate (spec 15-33):**

PROGRESS.md has no exit criterion for runner work; this feature's own, agreed
in brainstorm (criteria 1 and 2 reworded by ruling F: landings are serialized,
not ordered by manifest row):

1. `sh tests/run_all.sh` is green, including the stub-`claude` lane suite
   (both run modes, dependencies, serialized landing, a stopped lane).
2. One live run in a throwaway Godot project with three stories — one with
   no plan (planned with the user through autopilot's planning loop), one
   half-done, and one depending on the first — reaches its end state with
   no human input once the plans are approved, in each run mode: integration
   (one draft PR integration → main, nothing merged into main, one full
   gate) and direct (each story merged into main through the project's merge
   command, each dependent after its dependency); every session's first turn
   is under 90k context.
3. Autopilot in a studio never sets a session-mode `autopilot`, never starts
   a keep-awake, and never executes stories in its own session; work that
   does not fit stops with a stated reason.

**Input and platform (spec 159-165):**

As bundle 2: macOS first, POSIX `sh` (macOS `/bin/sh` is bash 3.2), Claude
Code ≥ 2.1.287 headless flags; git ≥ 2.38 (`git merge-tree --write-tree`;
preflight refuses older). Phoenix's merge command is
`.github/scripts/merge.sh <pr>` (it merges only when CI is green or its full
local gate — "Mode 2" — is green); the runner runs it, not a session.

**Feel targets (spec 167-181):**

| Target | Value | How it is checked |
|--------|-------|-------------------|
| Unit start context | task unit ≤ 60k; every other unit ≤ 90k | live run (first-turn usage in each unit's jsonl) |
| Plan or spec read whole by a task or final-review unit | 0 | unit (stub): `studio-brief` output pinned; live run: no `Read` of the plan or spec path without `offset` in task/final jsonl |
| Lanes at once | `max_lanes` (0 = one per chain) | unit (stub) |
| Sessions that carry more than one unit | 0 (complete, then forget) | unit (stub): one launch per unit |
| Claude sessions per clean landing | 0 | unit (stub) |
| Test or gate runs at once in a project, all lanes and the runner | 1 | unit (stub): overlapping lock intervals = 0 |
| Studio test runs per story | integration: 1 (finish) + 1 per repair; direct: 0 + the merge command's gate | text contract on execute §5/§7; live run: `studio-test` count per story jsonl |
| Full gates on the combined head (integration) | 1, +1 after a repair | unit (stub) |
| Runner overhead between units of a lane | ≤ 5 s | unit (stub) |
| Dependent chain start after its last dependency lands | ≤ 5 s | unit (stub) |
| Morning report on every ending, every story named | 100%, a lane crash included | unit (stub) |

**Acceptance criteria (spec 192-321), verbatim:**

1. Autopilot phase 1, in a studio, asks integration or direct and the lane
   count in one question, writes the run manifest `docs/runs/<slug>.md` and
   the pointer `.studio/run`, never sets a session-mode `autopilot`, never
   starts a keep-awake, and — once every story is planned — asks how to
   start: **autopilot starts it** (preflight runs in the foreground first; the
   detached runner inherits no variable named `CLAUDECODE`, `CLAUDE_CODE_*`,
   `OMEGA_*` or `STUDIO_*` from the chat; `studio-overnight status` exits 0
   within 10 s before phase 1 reports success, else it prints the command) or
   **print the command** (the absolute `cd '<dir>' && '<abs>' start
   <manifest>`). The environment half is stub-tested; surviving the chat's
   close or `/clear` is live-only (T1 probe and milestone run).
2. "In a studio" has one written definition, cited by every branch of the
   autopilot skill (text contract).
3. Planning loop, one stage per session: `studio-overnight next <manifest>`
   classifies each row as `brainstorm`, `plan` or `planned` from files and
   ledger lines alone and prints the one next command; brainstorm runs once
   per epic and writes one spec with a `## Stories` table naming every story
   it covers; `/game-dev:plan <id>` writes one plan for that story (header
   `Story: <id>`), then in the same session runs SDD's conflict scan and the
   question sweep into `## Decisions`, ledgers `Decisions swept <id>`, and
   prints `/clear` plus `next`'s command. Phase 1 discovery reads
   `.studio/run`, so it survives `/clear`. There is no in-session execution
   fallback in a studio. (`next`: stub; the skills: text contracts.)
4. `STUDIO_STORY=<id>` makes `studio-state` read and write only
   `.studio/stories/<id>.md` and the ledger `.studio/ledger/<id>.md`; with it
   unset every verb is byte-compatible with today (`state_test.sh`).
5. Lanes are dependency chains, built by the rule in Architecture; up to
   `max_lanes` lane processes (0 = one per chain) claim chains in order and
   run each chain's stories one after another; each story is the bundle-2
   unit loop with one fresh session per unit, then its landing.
6. A chain whose first story depends on stories in other chains starts that
   story only after every dependency has landed, from `origin/<Target>` at
   that moment; a dependency that stopped or was skipped skips the chain.
7. The runner lands a shipped story with no Claude session when the merge is
   clean — integration: a `--no-ff` merge commit built with `git merge-tree`
   and `git commit-tree`, pushed to `integration/<slug>`; direct: `gh pr
   ready` and the project's `merge_command <pr>` under the gate lock — one
   landing at a time per run. A conflict or a refused merge command launches
   one repair unit (`execute --land`), then one retry; a second failure stops
   the story.
8. A landing is idempotent: a story whose PR is already `MERGED` (direct) or
   whose branch head is already in `origin/<Target>` (integration) is
   recorded landed with the existing merge commit, with no merge, no merge
   command and no repair.
9. Integration final step, run by the runner when no lane has work, no stop
   was requested and at least one story landed: in its own worktree, merge
   `origin/main`, one PROGRESS unit, the full gate under the gate lock (one
   repair unit and one more gate on a conflict or red), push, then one draft
   PR into `main` with a section per landed story, a list of stories that did
   not land, and `[red]` when red — `gh pr edit` when that PR already exists;
   a resume with an unchanged integration head and an open PR skips it.
   Nothing is merged into `main`; the final PR is never merged by the run.
10. One gate lock per project (`STATE_ROOT/.studio/gate.lock`, `mkdir`):
    `studio-test`, `studio-run`, the runner's `merge_command` and the final
    gate each hold it, so at most one test or gate run happens at a time
    across lanes and the runner; a lock whose holder pid is dead is
    reclaimed; a holder's own children (`STUDIO_GATE_HELD`) do not re-take it.
11. Each story's code is gated once by the gate that matters: under a lane,
    the final-review unit runs no tests; integration — the finish unit's gate
    is the story's one test run (plus one per repair), and the final step's
    gate is the one full gate; direct — the finish runs no gate and the merge
    command is the landing gate. (Text contract on execute §5/§7; gate counts
    from the live run's jsonl.)
12. A task unit is given only `studio-brief task <n>`: the plan's
    `## Global Constraints` and `## Decisions`, the `### Task <n>` block, and
    the spec line ranges on that task's `Spec:` line; the final-review unit
    only `studio-brief final`: the spec's `## Acceptance criteria` (the
    story's rows when the spec has `## Stories`), the story's `## Stories`
    row, the ledger's `Ruling:` and deferred-minor lines, and the diff command
    against `origin/<Target>`. Execute §8 forbids reading the plan or spec
    whole under `--one`. A stub test pins `studio-brief`'s output on a fixture
    (task 3's text present; tasks 2 and 4, the uncited spec sections and,
    for `final`, the plan absent).
13. Every unit launch carries `--model` by unit kind from config (defaults:
    task `sonnet`, final review `opus`, finish `sonnet`, repair `opus`,
    progress `sonnet`); execute dispatches the per-task reviewer with
    `model: "opus"`.
14. Execute runs a per-task review only for a task marked `Review: task`
    (a task with no `Review:` line counts as `task`); `Review: final` tasks
    fold into the final review. The plan skill marks risky tasks (a new
    seam, cross-system, gameplay feel, data or schema, importer) `task` and
    the rest `final` (text contracts).
15. A stopped story leaves the other lanes running; the rest of its chain
    and every chain waiting on it are skipped and named in `report.md`.
16. A lane process that dies without writing a story ending, a SIGKILLed
    runner, and a Ctrl-C each end in a written ending: the runner never
    blocks on a dead lane, lanes stop launching when the stop file exists or
    the runner pid is gone, and `report.md` is written on every ending
    (stub).
17. `studio-overnight status` prints every story in manifest order: lane,
    state (`queued`, `waiting`, `running`, `landing`, `repair`, `landed`,
    `stopped`, `skipped`), unit, `task k/N`; the gate lock's holder; the
    run's spend.
18. `report.md` has the run's ending, mode, target and spend, the final PR
    (integration) or each landed merge commit (direct), one section per
    story, the resume command when not done, and a `## Cleanup` section: the
    one command that deletes the run's remote branches (`run/<slug>`, the
    integration branch, every landed story branch), to run after the final PR
    is landed. The run itself never deletes a remote branch.
19. A single-plan run without a manifest works as in bundle 2, except the
    deny-list additions (AC21) and the `run_usd` default (AC25).
20. The attended (non-autopilot) integration flow is unchanged: per-story PRs
    into the integration branch through `omega:local-merge` with the user's
    confirmation.
21. The session deny list is one data file with no mode tags: every session
    in every mode is denied `gh pr merge`, the `gh api` merge endpoint, a
    push to the default branch, and the merge program by its basename;
    `{default_branch}` with no value is a preflight refusal.
22. Every "never merge" in the omega and studio skills names `main` (the
    default branch) and states that sessions never merge in any run mode and
    that the runner lands (text contracts).
23. Under a lane, execute §0's clean-tree check names only the story's own
    ledger file, the docs come from the manifest's `Docs:` revision (fetched
    from `origin/run/<slug>`), a path checkout of docs happens only when §0
    creates the branch (an existing branch's ledger is never overwritten), and
    `git worktree add` uses `--no-track`.
24. A half-done story (an existing branch, `T<n> complete` lines, possibly a
    `final review done` or `shipped` line, possibly already merged) is seeded
    in its own worktree with `studio-state check --rebuild` under
    `STUDIO_STORY`: `task 0/N` first, then the longest contiguous run of
    completed tasks; a gap is a stated stop. Its lane resumes at its next
    unit, landing or landed; completed tasks are never re-run.
25. `overnight.run_usd` defaults to 0 (no run-wide cap) in both modes; a
    value > 0 makes each lane refuse a launch when the sum of all lanes'
    `units.tsv` costs plus `session_usd` exceeds it. `session_usd`, the
    no-progress stop and the session timeout apply as in bundle 2.
26. One launch per unit: no session the runner starts carries more than one
    task, final review, finish, repair or progress unit (stub).

**Project rules (CLAUDE.md, applied to studio tooling):**
- Composition over inheritance; decoupled systems. Cross-process signals
  are files, ledger lines and exit codes (the spec's Signals table, 368-381).
  No component writes state that another component owns (spec Ownership,
  330-344): the runner never writes studio state or the manifest, and
  `studio-state` is the only writer of studio state.
- Data in data files: deny rules in `overnight-deny.txt`, knobs in
  `.studio/config.json`, runs in the manifest. No tuning number is
  hard-coded in a skill.
- Scripts in `bin/` are self-contained (copy mode ships no `lib/`). A
  sibling file in `bin/` is allowed, as `studio-state` and
  `overnight-deny.txt` already are.
- POSIX sh only (no bash arrays, no `local`, no `[[`). Every script passes
  `sh -n` and is executable (`test_bin_syntax`).
- Tests are written first and fail before the implementation. They run
  offline: stub `claude`, `gh` and merge command, and a local bare origin.
- Write the test for any behavior that will be kept. Profile before
  optimizing; nothing here optimizes.

## Decisions

These rule on the architect's spec gaps (A1-A16 in its proposal) and on
the plan's own design choices. They bind the implementers. Each names the
spec text it overrides or makes precise. T1 appends its probe results here
as D1a-D1d.

- **D1. Probe results land here** (T1). Each probe has a predeclared
  fallback, so a failed probe never blocks a later task:
  - (a) detach: when a `nohup` + `perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV'`
    child does not survive, `--detach` is not offered, and autopilot always
    prints the command instead.
  - (b) when `BASH_*_TIMEOUT_MS` is not honoured under `-p`, execute's
    skills run `studio-test` in the background and wait for its
    notification. T14 writes both paths into §0, and the probe picks the
    default.
  - (c) when `set -m` in a background subshell gives no own process group,
    `run_unit` launches through `perl -e 'setpgrp; exec @ARGV'`.
  - (d) phoenix `merge.sh`'s behaviour is read from its source and from a
    non-merging invocation. A merging run happens only in the live run (play
    list) or on a throwaway PR the user approves.
- **D2. One crash text** (A1). Both the lane's EXIT trap and the parent's
  sweep write `stopped: lane crashed (<rc>)`, as spec 115, spec 376 and
  AC16 say. Spec 497's "lane exited" is superseded. A chain that no lane
  claimed because the run was stopped ends `skipped: run stopped`.
- **D3. An existing branch's docs are synced, not refused** (A2). This
  supersedes spec 788-790's stop on a difference. On an existing story
  branch, execute §0 under a lane runs `git checkout $STUDIO_DOCS_REV --
  <spec> <plan>`, and only when they differ commits
  `docs(<id>): plan at run docs <short sha>`. The ledger is never touched.
  The reason: a pre-lanes plan must gain `Story:`, `Spec:` and
  `## Decisions` on `run/<slug>`, so every half-done branch differs. The
  approved Docs revision is the authority.
- **D4. A fast-forward landing records the branch head** (A3). Integration
  step 0 can find no merge commit on
  `--ancestry-path origin/<Branch>..origin/<Target>`. That happens when the
  branch head was already in the target when the target was cut. Then the
  sha recorded is `git rev-parse origin/<Branch>`.
- **D5. A resumed final step is idempotent per step** (A4). Spec 122-124
  is binding:
  - step 1 keeps a reused worktree whose `HEAD` descends from
    `origin/integration/<slug>` (`merge-base --is-ancestor`); otherwise it
    switches;
  - step 2 is skipped when `git log --format=%s HEAD` contains
    `docs(progress): <slug>`;
  - the gate result is recorded in `runs/<slug>/gate` as `<sha> green|red`,
    and step 3 is skipped when it names the current `HEAD`.
- **D6. Every launch passes `--model`, single-plan included** (A5, A6).
  AC13 wins over AC19's list. The `{default_branch}` preflight refusal also
  applies in single-plan mode. `tests/overnight_test.sh`'s fixture gains a
  local bare origin with `origin/HEAD` set.
- **D7. `state_test.sh`'s existing cases are unmodified**; new cases are
  appended (A7).
- **D8. `run_usd`** is a `dec`, 0 or from 1 to 5000. A value above 0 and
  below 1 is a refusal (A8).
- **D9. `next` with no argument** reads `.studio/run`. With no pointer it
  exits 2 with `studio-overnight: no run manifest (.studio/run)`. `start`
  with no argument is bundle 2, unchanged (A9).
- **D10. "Branch exists" means local or `origin/<Branch>`** (A10). Every
  `git worktree add` uses `--no-track`. A branch that exists only on origin
  is added as `git worktree add --no-track -b <Branch> <path> origin/<Branch>`
  and is then treated as existing (D3).
- **D11. `run/<slug>` is created when the manifest is** (A11). Phase 1
  creates `run/<slug>` from `origin/<default>` and switches the phase-1
  checkout to it before any planning stage, so every brainstorm and plan
  commit lands on `run/<slug>`. The checkout must be on the default branch
  or already on `run/<slug>`. Otherwise phase 1 stops with "switch this
  checkout to `<default>` first".
- **D12. Direct mode's `## Cleanup` also names `progress/<slug>`** (A12).
- **D13. The direct progress landing is tested in T11 under AC9** (A13).
- **D14. `--detach` strips every variable with the four prefixes, with no
  exemption** (A14). `PATH` is kept, so the stubs still resolve. Its test
  needs no test hook.
- **D15. Under `STUDIO_STORY`, `check --rebuild` always applies the gap
  check,** from `task -` and from `k/N` alike (A15).
- **D16. Seeded ledger lines are re-ledgered with today's date** through
  `studio-state ledger` (A16). Every reader matches by text after the date.
- **D17. One gate-lock implementation: `studio-gate`** (deviates from the
  spec's Files table, which puts the lock in `studio-test` and
  `studio-run`).
  - `studio-gate <who> -- <cmd…>` takes `STATE_ROOT/.studio/gate.lock/`,
    runs `<cmd>` as a child with `STUDIO_GATE_HELD=<its own pid>`, and
    releases on exit. When `STUDIO_GATE_HELD` names the live holder, it
    runs `<cmd>` without locking.
  - `studio-test` and `studio-run` exec through it. The runner calls it for
    the merge command and for the final gate.
  - Rejected: three copies of the lock code (copy mode would allow it, but
    three copies drift).
  - `STUDIO_GATE_HELD` is set only for the locked child, never exported in a
    lane. The lock is free again once the child exits, so a repair unit
    started after a red merge command takes the lock itself.
- **D18. Manifest mode lives in `studios/game-dev/bin/overnight-lanes.sh`**
  (a deviation: the spec puts everything in `studio-overnight`).
  - `studio-overnight` sources it only when `start`, `next` or `status`
    sees a manifest, and only after its own helpers are defined. The file
    is executable and has a shebang; run directly, it exits 2 with
    `overnight-lanes.sh: sourced by studio-overnight`.
  - Bundle 2's loop body becomes `story_units` (T5), which both paths
    call.
  - The reason: about 2,000 lines added to a 445-line script, and a
    reviewer reading one concern per file.
- **D19. The per-story machine's record** is `RUN_DIR/stories/<id>`: one
  line, `<state>[ <detail>]`. The state is one of `queued`, `waiting`,
  `running`, `landing`, `repair`, `landed`, `stopped`, `skipped` (AC17's
  set). Only the lane that holds the story writes it, plus the parent's
  sweep (D2). Endings are `landed <sha>`, `stopped <reason>` and
  `skipped <dep or reason>`. The file is written by temp file and `mv`, so
  readers never see half a line.
- **D20. Test hook `STUDIO_OVERNIGHT_POLL_SECONDS`** (whole number, default
  5) sets the wait poll and the land-lock poll. `--help` lists it with the
  other test hooks. The gate's waiting message prints on the first wait and
  then every 60 s, and has no hook.
- **D21. `git_retry <git args…>`** retries a git call whose stderr matches
  `could not lock|cannot lock ref` three times (sleeps of 1, 2 and 4 s). It
  lives in `overnight-lanes.sh`. Every runner git call that writes (fetch,
  push, `worktree add`, `commit-tree`) goes through it.
- **D22. T1's role is `game-dev:gameplay-programmer` with
  `Verify: playtest`.** `game-dev:architect` has no Bash, and the probes
  need a shell. Each probe is written as action, expected result and
  failure.
- **D23. Unit kind → model and label.** Labels follow bundle 2's D8: `T<k>`
  uses `model_task`, `final-review` uses `model_final`, and `finish` uses
  `model_finish`. The landing repair is label `repair`, model
  `model_repair`. The final-step repair is label `final-repair`, model
  `model_repair`. The progress unit is label `progress`, model
  `model_progress`. A retry keeps its kind's model and gets bundle 2's
  `-retry` suffix.
- **D24. The `## Stories` table's `Acceptance criteria` cell** holds
  comma-separated AC numbers or ranges (`1, 3-5`). `studio-brief final`
  prints exactly those numbered items. The brainstorm skill (T16) writes
  the cell in that form.
- **D25. `lanes/<k>/current`** holds `<id> <label>` while a unit runs.
  `status` reads the unit from it.
- **D26. Manifest header comments.** A trailing ` #…` on a header line is
  stripped, as in the spec's own example (spec 452-453).
- **D27. `landed.tsv` carries a fourth column, the epoch of the landing**
  (`<id>\t<Target>\t<sha>\t<epoch>`). It extends spec 375 for the
  dependent-start timing check and the report. Task 10 defines it.
- **D28. Ruling: T13 is kept against the producer's cut.** The producer
  moved T13 (`--detach`, help, README) to the backlog: the printed command
  already reaches every milestone exit criterion. It is kept because:
  - AC1 requires the **autopilot starts it** choice, with its environment
    half stub-tested;
  - the plan skill requires every acceptance criterion to map to a task;
  - Teaching requires `--help` to state both modes.

  If D1a fails, T13 still lands the refusal path and the help text.

## AC coverage

| AC | Tasks | AC | Tasks |
|----|-------|----|-------|
| 1 | T13 (env), T17 (skill), T1 + P4 (live) | 14 | T14, T16 |
| 2 | T17 | 15 | T9, T12 |
| 3 | T7, T16, T17 | 16 | T9, T12 |
| 4 | T2 | 17 | T12 |
| 5 | T6, T8 | 18 | T12 |
| 6 | T9, T14 (base at that moment) | 19 | T5 |
| 7 | T10, T15 | 20 | T18 |
| 8 | T10 | 21 | T5, T6 |
| 9 | T11, T15 | 22 | T14, T17, T18 |
| 10 | T4, T10, T11 | 23 | T14 |
| 11 | T14, P1 (counts) | 24 | T2, T10, T17 |
| 12 | T3, T14 | 25 | T5, T8 |
| 13 | T5, T8, T14 | 26 | T8 |

Feel targets: unit start context and whole reads → P1 and T3/T14;
lanes at once → T8; sessions per unit → T8; sessions per clean landing →
T10; gate overlap → T4, T10; test runs per story → T14 and P1; full
gates → T11; runner overhead → T8; dependent start → T9; report on
every ending → T12.

## Review Focus

These are the input classes most likely to bite, most likely first. Each is
pinned by a test in the task that owns the code.

1. **A lane killed between a landing's push and its `landed.tsv` line.**
   The resume must record the landing from git or GitHub alone: no second
   merge, no repair. Test: T10 `test_lanes_land_crash_after_push`.
2. **A signal during the parent's `wait`, and a lane that dies with no
   ending.** The runner must never hang, and every story must get an
   ending. Tests: T9 `test_lanes_lane_kill9`, `test_lanes_sigint`.
3. **Two holders racing for a stale gate lock.** Exactly one wins, and the
   other waits. Test: T4 `test_gate_stale_reclaim_race`.
4. **A fork in the chain rule** (two rows depend on one). The second row
   must open a waiting chain, not append. Test: T6 `test_lanes_chain_rule`.
5. **The docs revision.** A commit in `START_DIR` mid-run must not reach a
   later story, and an existing branch's ledger must survive isolation.
   Test: T8 `test_lanes_docs_revision`.
6. **`STUDIO_STORY` unset** must leave every `studio-state` verb
   byte-for-byte as today. Test: T2 (the existing suite, unmodified).

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `studios/game-dev/bin/studio-state` | 2 | `STUDIO_STORY` selects the story file and the story-id ledger; `init`, `check --rebuild` under it |
| `studios/game-dev/hooks/guard-state.sh` | 2 | Story files are written only through `studio-state` |
| `studios/game-dev/bin/studio-brief` | 3 | Prints exactly a task or final-review unit's inputs (create) |
| `studios/game-dev/bin/studio-gate` | 4 | The machine-wide gate lock around one command (create, D17) |
| `studios/game-dev/bin/studio-test`, `studio-run` | 4 | Exec through `studio-gate` |
| `studios/game-dev/bin/studio-overnight` | 5, 6, 13 | Single-plan runner; config, deny expansion, `--model`, `story_units`; sources the lanes file; `--detach`; help |
| `studios/game-dev/bin/overnight-deny.txt` | 5 | Placeholders and the new seed rules |
| `studios/game-dev/bin/overnight-lanes.sh` | 6-12 | Manifest mode: parse, chains, `next`, lanes, waiting, landing, final step, status, report (create, D18) |
| `studios/game-dev/skills/execute/SKILL.md` | 14, 15 | §0 lane isolation, §4 `Review:`, §5/§7 under a lane, §8 `studio-brief`, §9 `--land`, §10 `--progress` |
| `studios/game-dev/skills/plan/SKILL.md`, `brainstorm/SKILL.md` | 16 | `Story:`, `Spec:`, `Review:`, the sweep after approval, `## Stories`, next command |
| `shared/omega/skills/autopilot/SKILL.md` | 17 | "In a studio", the two questions, manifest, planning loop, seeding, start choice |
| `shared/omega/skills/integration/SKILL.md`, `local-merge/SKILL.md`, `shared/omega/bin/omega-mode` | 18 | `## Autopilot run`, `repair <slug>`; the merge rule names `main` |
| `README.md` | 13 | Manifest runs, `next`, two modes, the gate lock |
| `tests/state_test.sh`, `tests/hook_test.sh` | 2 | Appended cases |
| `tests/studio_brief_test.sh` | 3 | Pinned outputs (create) |
| `tests/toolkit_test.sh` | 4 | Gate-lock cases |
| `tests/overnight_test.sh` | 5 | Single-plan regression and the deltas |
| `tests/overnight_lanes_test.sh` | 6-13 | Lanes suite (create in T6, grows per task) |
| `tests/studio_test.sh` | 14-16 | Text contracts |
| `tests/omega_contracts/{autopilot,integration,local-merge}_contract.sh`, `tests/omega_test.sh` | 17, 18 | Text contracts, `brief` |

**Order:**
- T1-T5 and T18 are independent of each other.
- The runner spine is serial, because it shares one file and one test
  file: T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13. T8 also needs T1,
  T2 and T4.
- T14 needs T3. T15 needs T14. T16 needs T7. T17 needs T7, T13 and T16.
- T13 updates the README last among the code tasks.

---

### Task 1: Live probes — detach, Bash timeouts, process groups, merge.sh
Role: game-dev:gameplay-programmer
Verify: playtest
Files: docs/game-dev/plans/2026-10-01-overnight-lanes.md (## Decisions only)
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L940-944, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L948-963
Review: final

Deliverable: a decision. Four probe results go into `## Decisions` as
D1a-D1d. Each one says what was run, what was seen, and which path
T8/T13/T14 take. The probe scripts live in the scratchpad and are never
committed. Feeds AC1 (the live half), AC7 and AC16.

**Playtest items this task produces** (each: action → expected → failure):

- **D1a detach.**
  - Action: from inside a `claude-gd` session, run
    `env CLAUDECODE=1 CLAUDE_CODE_X=1 OMEGA_X=1 STUDIO_X=1 sh probe-detach.sh`.
    The script re-execs itself as
    `nohup perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' env -u CLAUDECODE … sh probe-child.sh </dev/null >probe.log 2>&1 &`,
    with every variable named by the four prefixes unset (computed from
    `env | sed -n 's/^\(CLAUDECODE\|CLAUDE_CODE_[A-Za-z0-9_]*\|OMEGA_[A-Za-z0-9_]*\|STUDIO_[A-Za-z0-9_]*\)=.*/\1/p'`).
    The child writes `env` to `probe.env` and then appends a timestamp to
    `probe.log` every 10 s for 3 minutes. Then the user runs `/clear` and
    closes the chat window within that time.
  - Expected: `probe.log` keeps growing after the close; `probe.env` has
    none of the four prefixes; `ps -o pgid,sess` shows the child's own
    session.
  - Failure: the log stops at the close, or a prefixed variable is
    present. Then autopilot only prints the command (D1's fallback).
    The chat close needs a human. The implementer prepares the script and
    the exact steps, and the orchestrator asks the user to do the close.
- **D1b Bash timeouts under `-p`.**
  - Action:
    `BASH_DEFAULT_TIMEOUT_MS=900000 BASH_MAX_TIMEOUT_MS=900000 claude-gd -p "Run exactly this Bash command with no timeout argument and report its output: sleep 660; echo slept" --output-format stream-json --verbose --permission-mode auto`.
  - Expected: the result text contains `slept`, and the tool result shows
    no timeout.
  - Failure: the tool reports a timeout at 120 or 600 s. Then T14 makes
    the background-`studio-test` path the default.
- **D1c process group of a background-subshell launch.**
  - Action: in a real terminal (run under `script -q /dev/null sh probe-pg.sh`,
    which gives a pty when no human terminal is at hand),
    `probe-pg.sh` runs `( set -m; sleep 30 & echo "$!" > pg.child; wait ) &`
    and then prints `ps -o pid,pgid,tpgid -p <child>` and its own pgid. Then
    it sends `kill -INT -<own pgid>`.
  - Expected: the child's pgid equals its pid, differs from the probe's
    pgid, and the child survives the INT.
  - Failure: the pgids are equal, or the child died. Then `run_unit` under
    a lane launches through `perl -e 'setpgrp(0,0); exec @ARGV'` (T8).
- **D1d phoenix `merge.sh` from a non-Claude parent.**
  - Action: read
    `~/Documents/GameDev/phoenix/.github/scripts/merge.sh` in full (ask
    the user for the path when it is not there). Record the exit codes it
    can return; whether it deletes the head branch (`--delete-branch` or a
    `git push --delete`); its cwd and env assumptions (`git rev-parse`,
    `gh` auth); and whether it reads a TTY (`read`, `-t 0`). Then run
    `sh .github/scripts/merge.sh 999999` (a PR that does not exist) from a
    phoenix worktree, from a plain `sh -c` parent with `</dev/null`.
  - Expected: a non-zero exit with no merge, no prompt and no hang.
  - Failure: it blocks on stdin, or it needs a tty. Then the runner runs
    it with `</dev/null` and a timeout of `session_minutes`, and the play
    list carries a merging run. A merging run happens only in the live run,
    or on a throwaway PR when the user says yes.

- [ ] **Step 1:** Write the four probe scripts into the scratchpad, and
  run D1b, D1c and the reading half of D1d.
- [ ] **Step 2:** Hand the D1a steps to the orchestrator. It asks the user
  to do the chat close, then reads `probe.log` and `probe.env`.
- [ ] **Step 3:** Append D1a-D1d under D1 in this plan's `## Decisions`.
  Each gets one paragraph: what was run, the exact observation (exit codes,
  pgids, last log timestamp), and the path chosen.
- [ ] **Step 4: Commit.**
  `git add docs/game-dev/plans/2026-10-01-overnight-lanes.md && git commit -m "docs(plans): overnight-lanes probe results D1a-D1d"`

---

### Task 2: `studio-state` under `STUDIO_STORY`; guard-state protects story files
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-state, studios/game-dev/hooks/guard-state.sh, tests/state_test.sh, tests/hook_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L383-405, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L217-219, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L310-315
Review: task

**Risk:** data and schema. Covers AC4 and AC24's rebuild half.

**Interfaces:**
- Produces: with `STUDIO_STORY=<id>` exported (id matches
  `^[A-Za-z0-9._-]+$`), every verb behaves as today, with two paths
  swapped:
  - `STATE` is `$STATE_ROOT/.studio/stories/<id>.md`;
  - `ledger_file` is `$LEDGER_DIR/<id>.md`.

  In addition:
  - `init` creates only the story file, with the same header as
    `STATE.md`, and adds the line `.studio/stories/` to
    `$(git rev-parse --git-common-dir)/info/exclude` once;
  - every other verb on a missing story file exits 1 with
    `studio-state: no story <id>`;
  - a bad id exits 1 with `studio-state: bad STUDIO_STORY '<id>'`;
  - `check --rebuild` follows the rule below.

  With `STUDIO_STORY` unset or empty, the code path is exactly today's.
- Consumed by: T8 (the runner exports it per lane), T14 (execute under a
  lane), T17 (seeding).

`check --rebuild` under `STUDIO_STORY`:
- When `task` is `-` or empty, N is `grep -c '^### Task [0-9]' <plan>`,
  and `task 0/N` is written first.
- Then k is the longest contiguous run of `T1 … Tk complete` in the story
  ledger, and `task k/N` is written.
- A `T<m> complete` with m > k + 1 exits 1 with
  `check: ledger gap: T<k+1> missing` and writes nothing past `0/N`.
- The gap check also applies from `k/N` (D15).

- [ ] **Step 1: Write the failing tests.** Append these to
  `tests/state_test.sh` and to its `run_tests` line. D7: no existing case
  changes.

```sh
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
```

  In `tests/hook_test.sh`, add to the guard-state cases:

```sh
  printf '{"tool_input":{"file_path":"/p/.studio/stories/KAN-1.md"}}' | sh "$GUARD" 2> "$TMP/err"; st=$?
  assert_eq 2 "$st" "guard-state blocks a story state file"
```

  If `assert_missing` or `assert_not_contains` is missing from
  `tests/assert.sh`, write it beside its sibling in the same style.

- [ ] **Step 2: Run them and see them fail.**
  `sh tests/state_test.sh; sh tests/hook_test.sh`. Expected: the new cases
  FAIL, and every old case passes.
- [ ] **Step 3: Implement.**
  - Right after `STATE=…`, add:

    ```sh
    STORY="${STUDIO_STORY:-}"
    if [ -n "$STORY" ]; then
      printf '%s' "$STORY" | grep -Eq '^[A-Za-z0-9._-]+$' || { printf "studio-state: bad STUDIO_STORY '%s'\n" "$STORY" >&2; exit 1; }
      STATE="$STATE_ROOT/.studio/stories/$STORY.md"
    fi
    ```

  - `need_state`: when `STORY` is set, the message is `no story $STORY`.
  - `ledger_file`: when `STORY` is set, print `$LEDGER_DIR/$STORY.md`
    always.
  - `init`: when `STORY` is set, `mkdir -p "$STATE_ROOT/.studio/stories"`,
    write the same header block `init` writes today into `$STATE` (only
    when the file is missing), add the exclude line (`grep -qxF` first),
    and exit 0 without touching `config.json`, `ledger/` or `.gitignore`.
  - `check`: when `STORY` is set and `rebuild=1`, run the rebuild rule
    above before the generic block, and exit with its status.
  - `guard-state.sh`: add `*/.studio/stories/*.md|.studio/stories/*.md` to
    the `case`.
- [ ] **Step 4: Run.** `sh tests/state_test.sh && sh tests/hook_test.sh`,
  then `sh tests/run_all.sh`. Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/studio-state studios/game-dev/hooks/guard-state.sh tests/state_test.sh tests/hook_test.sh && git commit -m "feat(studio-state): STUDIO_STORY selects a story file and its ledger"`

---

### Task 3: `studio-brief` — a unit's exact inputs
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-brief, tests/studio_brief_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L652-671, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L257-266
Review: task

**Risk:** a new seam. The plan skill (T16) writes the format it parses, and
execute §8 (T14) reads its output. Covers AC12's tool half.

**Interfaces:**
- Produces two commands. Both are read-only, and both read `plan` and
  `spec` through the sibling `studio-state get` (so `STUDIO_STORY` is
  honoured).
  - `studio-brief task <n>` prints, in order, each part headed by one line
    `==> <file>:L<a>-<b>` followed by those lines verbatim:
    1. the plan's `## Global Constraints` section (to the next `## `);
    2. the plan's `## Decisions` section;
    3. the `### Task <n>:` block, to the next `### Task ` or `## ` heading;
    4. each range on that block's `Spec:` line. An item is
       `<path>:L<a>-<b>` or `<path>§<heading text>`, items are separated by
       `, `, and `§` resolves to the heading line through the line before
       the next heading of the same or higher level.

    Exit 1, naming the part, when a plan section, the task or a cited
    range is missing, or when a range is past the end of the file.
  - `studio-brief final` prints:
    1. the spec's `## Acceptance criteria`. When the spec has
       `## Stories`, only the numbered items listed in the story's row's
       `Acceptance criteria` cell (D24) are printed, each item through the
       line before the next `^[0-9]+\. ` or heading;
    2. the story's `## Stories` row, when the spec has the table;
    3. the story ledger's lines matching `Ruling: ` or
       `minor \(deferred\)`, headed `==> <ledger>`;
    4. the line `diff: git diff origin/<Target>...HEAD`. Target is read
       from `$STUDIO_RUN`'s `Target:` header, or else from
       `origin/HEAD`'s branch.

    `final` prints no plan text. The story id is `$STUDIO_STORY`. With no
    id and a `## Stories` table present, it exits 1 with
    `studio-brief: STUDIO_STORY not set`.

- [ ] **Step 1: Write the failing test** `tests/studio_brief_test.sh`. Its
  fixture builder writes, in a temp git repo:
  - `docs/spec.md` with headings `## Purpose` (line 3),
    `## Acceptance criteria` (items `1.` to `4.`, each two lines), a
    `## Stories` table with rows `S1 | 1, 3 | -` and `S2 | 2, 4 | S1`,
    `## Architecture` with `### Data` and `### Flow`, and `## Risks`;
  - `docs/plan.md` with `## Global Constraints`, `## Decisions`, and
    `### Task 1` to `### Task 4`. Task 3 carries
    `Spec: docs/spec.md:L3-4, docs/spec.md§### Data`. Each task holds a
    unique marker line (`MARK-T1` … `MARK-T4`). `### Data` holds
    `MARK-DATA`, `### Flow` holds `MARK-FLOW`, Purpose holds
    `MARK-PURPOSE`, and each AC holds `MARK-AC<n>`;
  - `studio-state init`, then (with `STUDIO_STORY=S1`) story init,
    `set spec`, `set plan`, and the ledger lines `Ruling: chose X`,
    `Task 2: minor (deferred): rename`, `T1 complete`;
  - a manifest file whose header holds `Target: integration/demo`,
    exported as `STUDIO_RUN`.

  Assertions:

```sh
test_brief_task() {
  out="$TMP/task3.txt"
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$out"; st=$?
  assert_eq 0 "$st" "task 3 exits 0"
  assert_contains "$out" "^==> docs/plan.md:L[0-9]*-[0-9]*$" "parts are headed with file and lines"
  assert_contains "$out" "MARK-T3" "task 3's block is present"
  assert_not_contains "$out" "MARK-T2" "task 2 is absent"
  assert_not_contains "$out" "MARK-T4" "task 4 is absent"
  assert_contains "$out" "^## Global Constraints" "global constraints present"
  assert_contains "$out" "^## Decisions" "decisions present"
  assert_contains "$out" "MARK-PURPOSE" "the L-range is present"
  assert_contains "$out" "MARK-DATA" "the § range is present"
  assert_not_contains "$out" "MARK-FLOW" "the sibling subsection is absent"
  assert_not_contains "$out" "MARK-AC1" "uncited spec sections are absent"
}
test_brief_final() {
  out="$TMP/final.txt"
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$out"; st=$?
  assert_eq 0 "$st" "final exits 0"
  assert_contains "$out" "MARK-AC1" "the story's AC 1"
  assert_contains "$out" "MARK-AC3" "the story's AC 3"
  assert_not_contains "$out" "MARK-AC2" "another story's AC is absent"
  assert_contains "$out" "| S1 |" "the story's row"
  assert_contains "$out" "Ruling: chose X" "ruling lines"
  assert_contains "$out" "minor (deferred): rename" "deferred minors"
  assert_not_contains "$out" "T1 complete" "other ledger lines are absent"
  assert_contains "$out" "^diff: git diff origin/integration/demo\.\.\.HEAD$" "the diff command"
  assert_not_contains "$out" "MARK-T" "no plan text"
}
test_brief_refusals() {
  assert_status 1 "a missing task exits 1" -- sh -c "cd '$P' && STUDIO_STORY=S1 sh '$BRIEF' task 9"
  # a task whose Spec: cites a range past EOF
  sed -i.bak 's/^Spec: docs\/spec.md:L3-4/Spec: docs\/spec.md:L3-9999/' "$P/docs/plan.md"
  assert_status 1 "a range past the end exits 1" -- sh -c "cd '$P' && STUDIO_STORY=S1 sh '$BRIEF' task 3"
  mv "$P/docs/plan.md.bak" "$P/docs/plan.md"
  assert_status 1 "final with a Stories table needs STUDIO_STORY" -- sh -c "cd '$P' && STUDIO_STORY= sh '$BRIEF' final"
  assert_status 2 "no verb is usage" -- sh "$BRIEF"
}
```

- [ ] **Step 2: Run it and see it fail.** `sh tests/studio_brief_test.sh`.
  Expected: FAIL (no such file).
- [ ] **Step 3: Implement** `studios/game-dev/bin/studio-brief` (sh,
  `set -u`, executable, with a header comment like its siblings). The core
  is one awk helper:

```sh
# section FILE HEADING_REGEX — "a b" (first, last line) of the block that
# starts at the first line matching HEADING_REGEX and ends before the next
# heading of the same or higher level; empty when absent.
section() {
  awk -v re="$2" '
    function lvl(s) { match(s, /^#+/); return RLENGTH }
    !a && $0 ~ re { a = NR; L = lvl($0); next }
    a && /^#+ / && lvl($0) <= L { print a, NR - 1; found = 1; exit }
    END { if (a && !found) print a, NR }
  ' "$1"
}
# emit FILE A B — the part header, then the lines.
emit() { printf '==> %s:L%s-%s\n' "$1" "$2" "$3"; sed -n "$2,$3p" "$1"; }
```

  - Task blocks end at the next `^### Task ` or `^## ` (they are level 3,
    so `section` with the regex `^### Task <n>:` gives the right end).
  - The `Spec:` line is the first `^Spec: ` line inside the task block.
    Split it on `, `. An item containing `§` resolves through `section`
    with `^<escaped heading>$`. An `:L<a>-<b>` item is checked against
    `wc -l`.
  - AC items: inside the AC section, the start lines of `^[0-9]+\. `
    give the item ends. Expand the cell's `3-5` ranges with a `while`
    loop.
- [ ] **Step 4: Run.** `sh tests/studio_brief_test.sh`, then
  `sh tests/run_all.sh` (`test_bin_syntax` picks up the new file).
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/studio-brief tests/studio_brief_test.sh && git commit -m "feat(studio-brief): print exactly a task or final-review unit's inputs"`

---

### Task 4: `studio-gate` — one test or gate run at a time per project
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-gate, studios/game-dev/bin/studio-test, studios/game-dev/bin/studio-run, tests/toolkit_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L628-650, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L246-250
Review: task

**Risk:** cross-system. Every lane, unit session and the runner share it.
Covers AC10's tool half. D17 explains the deviation from the spec's Files
table.

**Interfaces:**
- Produces `studio-gate <who> -- <cmd> [args…]`:
  - Lock dir: `$(studio-state root)/.studio/gate.lock/`, holding the files
    `pid` (studio-gate's own `$$`) and `who`.
  - Taking it: `mkdir`. When the lock exists and its `pid` is dead, it is
    reclaimed: `mv gate.lock gate.lock.stale.$$` (atomic; only one
    reclaimer wins), `rm -rf` the moved dir, then `mkdir` again. A
    reclaimer that loses the `mv` waits like everyone else.
  - While waiting, it prints `gate: waiting for <who> (pid <p>)` to stderr
    on the first wait and then every 60 s, and polls every 1 s.
  - It runs `<cmd>` as a child with `STUDIO_GATE_HELD=$$` exported to that
    child only, waits for it (with bundle 2's D7 loop), releases the lock
    in an EXIT/INT/TERM/HUP trap, and exits with the child's status.
  - When `STUDIO_GATE_HELD` is set and equals the `pid` in the lock, and
    that pid is alive, it does `exec <cmd>` without locking.
  - Exit 2 on usage (missing `--` or command).
- `studio-test` becomes
  `exec sh "$(dirname "$0")/studio-gate" studio-test -- sh "$(dirname "$0")/studio-dispatch" test "$@"`.
  `studio-run` follows the same pattern with `who` = `studio-run`.
  `studio-lint` is unchanged (no engine process, no `user://`).
- Consumed by: T10 (the merge command) and T11 (the final gate), both via
  `sh "$SELF_DIR/studio-gate" <who> -- …`.

- [ ] **Step 1: Write the failing tests** in `tests/toolkit_test.sh`. They
  run against a temp project with `studio-state init` and use plain `sh -c`
  commands as `<cmd>`:

```sh
GATE="$BIN/studio-gate"
gate_proj() { GP="$TMP/gate-$1"; mkdir -p "$GP"; ( cd "$GP" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && sh "$BIN/studio-state" init ) >/dev/null 2>&1; }

test_gate_no_overlap() {
  gate_proj overlap
  for i in 1 2 3; do
    ( cd "$GP" && sh "$GATE" t$i -- sh -c "echo s \$(date +%s) >> '$TMP/iv'; sleep 2; echo e \$(date +%s) >> '$TMP/iv'" ) 2>/dev/null &
  done
  wait
  # Intervals in order s e s e s e: no s follows an s.
  assert_eq "s e s e s e" "$(awk '{printf "%s%s", sep, $1; sep=" "}' "$TMP/iv")" "three holders never overlap"
  assert_missing "$GP/.studio/gate.lock" "the lock is released after the last holder"
}
test_gate_status_and_held() {
  gate_proj held
  st=0; ( cd "$GP" && sh "$GATE" x -- sh -c 'exit 7' ) 2>/dev/null || st=$?
  assert_eq 7 "$st" "the child's exit status is passed through"
  ( cd "$GP" && sh "$GATE" outer -- sh -c "sh '$GATE' inner -- sh -c 'echo \$STUDIO_GATE_HELD'" ) > "$TMP/nest" 2>&1
  assert_eq 1 "$(grep -c '^[0-9][0-9]*$' "$TMP/nest")" "a holder's child runs without re-taking the lock"
  assert_not_contains "$TMP/nest" "gate: waiting" "the nested call never waits"
  assert_status 2 "no -- is usage" -- sh "$GATE" who
}
test_gate_stale_reclaim_race() {
  gate_proj stale
  mkdir -p "$GP/.studio/gate.lock"; echo 999999 > "$GP/.studio/gate.lock/pid"; echo dead > "$GP/.studio/gate.lock/who"
  ( cd "$GP" && sh "$GATE" a -- sh -c "echo s >> '$TMP/sr'; sleep 1; echo e >> '$TMP/sr'" ) 2>/dev/null &
  ( cd "$GP" && sh "$GATE" b -- sh -c "echo s >> '$TMP/sr'; sleep 1; echo e >> '$TMP/sr'" ) 2>/dev/null &
  wait
  assert_eq "s e s e" "$(tr '\n' ' ' < "$TMP/sr" | sed 's/ $//')" "a dead holder is reclaimed once; the two do not overlap"
}
test_gate_waiting_message() {
  gate_proj msg
  ( cd "$GP" && sh "$GATE" first -- sleep 3 ) 2>/dev/null &
  sleep 1
  ( cd "$GP" && sh "$GATE" second -- true ) 2> "$TMP/gm"
  wait
  assert_contains "$TMP/gm" "^gate: waiting for first" "a waiter names the holder"
}
test_gate_wraps_test_and_run() {
  assert_contains "$BIN/studio-test" 'studio-gate" studio-test --' "studio-test goes through studio-gate"
  assert_contains "$BIN/studio-run" 'studio-gate" studio-run --' "studio-run goes through studio-gate"
}
```

  Every existing studio-test and
  studio-run case in `toolkit_test.sh` must stay green unchanged. They run
  in a project with `.studio/`, or `studio-gate` falls back as below.
- [ ] **Step 2: Run them and see them fail.** `sh tests/toolkit_test.sh`.
- [ ] **Step 3: Implement** `studio-gate`.
  - The root is `sh "$(dirname "$0")/studio-state" root`. When that
    fails, or no `.studio/` exists there, there is no project lock, so it
    does `exec "$@"` (a bare directory has nothing to protect). This keeps
    `test_test_needs_a_project` and its siblings unchanged.
  - Then wire `studio-test` and `studio-run` as above.
- [ ] **Step 4: Run.** `sh tests/toolkit_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/studio-gate studios/game-dev/bin/studio-test studios/game-dev/bin/studio-run tests/toolkit_test.sh && git commit -m "feat(studio-gate): one test or gate run at a time per project"`

---

### Task 5: Runner config, deny placeholders, `--model`, and `story_units`
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-overnight, studios/game-dev/bin/overnight-deny.txt, tests/overnight_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L699-719, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L800-806, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L875-898, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L673-681, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L293-302, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L316-319
Review: task

**Risk:** data and schema, plus a refactor of the loop that every later
runner task reuses. Covers AC19, AC21, AC25's default and range, and
AC13's single-plan half.

**Interfaces:**
- Produces, inside `studio-overnight`:
  - `cfg_str KEY DEFAULT REGEX`. It reads the quoted string value
    `"KEY": "…"` with `sed`, from the first match anywhere in
    `config.json`. When the key is absent it uses DEFAULT. A value not
    matching REGEX is a refusal naming the key. It sets the variable named
    by KEY in upper case.
  - Config calls in `preflight`:
    - `cfg max_lanes 0 0 8 int`;
    - `cfg_str model_task sonnet '^[a-z0-9.-]+$'`, and the same for
      `model_final` (default `opus`), `model_finish` (`sonnet`),
      `model_repair` (`opus`) and `model_progress` (`sonnet`);
    - `MERGE_COMMAND` from `cfg_str merge_command '' '.*'`. When it is set,
      it must contain `<pr>`, and its first word must be a file under
      `START_DIR` with the executable bit
      (`[ -f "$START_DIR/$w" ] && [ -x "$START_DIR/$w" ]`). Otherwise it
      is refused with `config merge_command: …`;
    - `cfg run_usd 0 0 5000 dec`, plus the D8 check.
  - `DEFAULT_BRANCH`, from
    `git -C "$START_DIR" symbolic-ref --short refs/remotes/origin/HEAD`
    with the `origin/` stripped. When it is empty, the refusal is
    `origin/HEAD is not set — run: git remote set-head origin --auto`.
  - `MERGE_BASENAME` is the basename of `MERGE_COMMAND`'s first word, or
    empty.
  - `deny_rules`, which prints the expanded rules one per line:
    - comments and blanks are dropped;
    - `{default_branch}` is replaced by `DEFAULT_BRANCH`;
    - `{merge_basename}` is replaced by `MERGE_BASENAME`, and a line is
      dropped when that is empty.

    `with_launch_args` reads from `deny_rules`, not from the raw file.
  - `UNIT_MODEL`, set by the caller before each launch.
    `with_launch_args` puts `--model "$UNIT_MODEL"` right after the
    prompt. The argv order is: prompt, `--model`, then bundle 2's flags,
    then `--disallowedTools` with its rules.
  - `model_for LABEL`, which strips `-retry` and maps `T*` to
    `$MODEL_TASK`, `final-review` to `$MODEL_FINAL`, `finish` to
    `$MODEL_FINISH`, `repair` and `final-repair` to `$MODEL_REPAIR`, and
    `progress` to `$MODEL_PROGRESS` (D23).
  - `run_unit N LABEL` writes its files under `$UNIT_DIR` with stem
    `$UNIT_PREFIX$N-$LABEL`, and writes `$UNIT_DIR/current`. Single-plan
    sets `UNIT_DIR="$RUN_DIR"` and `UNIT_PREFIX=""`, so its layout is
    unchanged. `row` appends to `$UNIT_DIR/units.tsv`.
  - `story_units`: bundle 2's loop body, moved out of `cmd_start`
    unchanged in behaviour. It returns with `ENDING` set to one of: `done`;
    `stopped by user`; `stop: <reason>`; `stop: run budget`;
    `no progress on <label>`; `stop: unexpected stage <s>`. It is called
    as `story_units; finish_run "$ENDING"` in single-plan mode.
    - The budget check runs only when `RUN_USD` > 0, and its spend is
      `spent_all`. Single-plan defines `spent_all` as `spent`; T8
      redefines it for lanes.
    - The stop check is `stop_requested`. Single-plan defines it as today's
      `[ -f "$STOP_FILE" ] || [ "$STOP_REQ" = 1 ]`.
- `overnight-deny.txt` gains the six seed lines from spec 707-714 under a
  comment that explains both placeholders.

- [ ] **Step 1: Update and add the tests** in `tests/overnight_test.sh`.
  - `fixture`: after `git init`, create a bare origin `"$TMP/$1.git"`,
    `git remote add origin`, `git push -q origin main`, and
    `git remote set-head origin main`, so every existing case has
    `origin/HEAD`.
  - `test_overnight_launch_argv`: the expected argv gains
    `--model` and `sonnet` as elements 3-4 (after `-p` and the prompt).
    The tail comparison reads the expanded rules: the file's rules, with
    `{default_branch}` → `main` and the `{merge_basename}` line dropped
    (no `merge_command`).
  - `test_overnight_run_budget`: set `"run_usd": 2` explicitly (the
    default is now 0).
  - `test_overnight_help`: the help text names `run_usd` with `0` and
    `0-5000`, `max_lanes`, the five `model_*` keys and `merge_command`.
  - New:

```sh
test_overnight_models_by_unit() {
  fixture models '{"overnight": {"model_final": "opus-x", "model_finish": "son.1"}}'
  scenario "stage execute; task 1/1; ledger T1 complete" "ledger final review done" "ledger shipped https://x/pr/1; stage idle"
  run_start
  assert_eq 0 "$RS_STATUS" "the run ends done"
  assert_eq sonnet "$(sed -n 4p "$CALLS/1.argv")" "a task unit gets model_task (default sonnet)"
  assert_eq opus-x "$(sed -n 4p "$CALLS/2.argv")" "the final review gets model_final"
  assert_eq son.1 "$(sed -n 4p "$CALLS/3.argv")" "the finish gets model_finish"
}
test_overnight_config_refusals_v2() {
  fixture cfgv2 '{"overnight": {"max_lanes": 9, "run_usd": 0.5, "model_task": "Sonnet 4"}, "merge_command": "missing.sh"}'
  run_start --dry-run
  assert_eq 2 "$RS_STATUS" "refused"
  assert_contains "$RS_ERR" "overnight.max_lanes" "max_lanes out of range"
  assert_contains "$RS_ERR" "run_usd" "run_usd between 0 and 1"
  assert_contains "$RS_ERR" "model_task" "a model with a space"
  assert_contains "$RS_ERR" "merge_command" "merge_command without <pr> and not an executable under the checkout"
}
test_overnight_default_branch_required() {
  fixture nohead
  git -C "$P" remote set-head origin -d >/dev/null 2>&1
  run_start --dry-run
  assert_eq 2 "$RS_STATUS" "no origin/HEAD is a refusal"
  assert_contains "$RS_ERR" "origin/HEAD is not set" "the refusal says how to fix it"
}
test_overnight_deny_merge_basename() {
  fixture denymb '{"merge_command": "scripts/merge.sh <pr>"}'
  mkdir -p "$P/scripts"; printf '#!/bin/sh\n' > "$P/scripts/merge.sh"; chmod +x "$P/scripts/merge.sh"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m m ) >/dev/null 2>&1
  run_start --dry-run
  assert_eq 0 "$RS_STATUS" "a valid merge_command passes"
  assert_contains "$RS_OUT" "'Bash(\*merge.sh\*)'" "the merge program is denied by basename"
  assert_contains "$RS_OUT" "'Bash(gh api \*pulls/\*/merge\*)'" "the merge endpoint is denied"
}
test_overnight_run_usd_default_uncapped() {
  fixture uncapped
  scenario "stage execute; task 1/1; ledger T1 complete; cost 400" "ledger final review done; cost 400" "ledger shipped u; stage idle; cost 1"
  run_start
  assert_eq 0 "$RS_STATUS" "run_usd 0 caps nothing: an \$801 run ends done"
}
```

- [ ] **Step 2: Run them and see them fail.** `sh tests/overnight_test.sh`.
- [ ] **Step 3: Implement** the interfaces above. Move the loop with
  `story_units` as a pure extraction first: run the whole suite green
  before adding any behaviour. Then add config, deny expansion and
  `--model`. Update `usage` (the config table: `run_usd 0 0-5000 (0 = no
  run-wide cap)`, the new keys) and the deny file.
- [ ] **Step 4: Run.** `sh tests/overnight_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS, every old case included.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-deny.txt tests/overnight_test.sh && git commit -m "feat(overnight): models per unit, deny placeholders, run_usd 0, story_units"`

---

### Task 6: Manifest mode — parse, chains, preflight, `--dry-run`
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/overnight-lanes.sh, studios/game-dev/bin/studio-overnight, tests/overnight_lanes_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L435-475, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L477-487, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L800-815, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L220-223
Review: task

**Risk:** a new seam (the sourced file) and a data schema (the manifest).
Covers AC5's chain rule, and AC21's refusal in manifest mode.

**Interfaces:**
- `studio-overnight start [--dry-run|--detach] <manifest>` (`--detach`
  comes in T13), `next [<manifest>]` (T7), and `status`. When a manifest
  argument is given, `studio-overnight` runs bundle 2's preflight minus
  its single-plan checks (spec, plan, stage on `STATE.md`). Then it runs
  `. "$SELF_DIR/overnight-lanes.sh"`, then `lanes_start "$@"`. With no
  manifest argument, the path is bundle 2's.
- `overnight-lanes.sh` defines:
  - `mf_load MANIFEST`. It sets `MF` (the path), `MF_SLUG` (from
    `# Run: <slug>`), `MF_MODE`, `MF_TARGET`, `MF_DOCS` and `MF_GOAL`, and
    writes `$MF_ROWS`, a TSV with one row per story:
    `id branch ticket spec plan deps`, with `deps` comma-joined without
    spaces or `-`. Before the run directory exists, `MF_ROWS` is a temp
    file under `$STATE_ROOT/.studio/tmp.$$`. `lanes_start` later copies the
    manifest to `RUN_DIR/manifest.md` and the rows to `RUN_DIR/rows.tsv`.
  - `mf_check`. It runs `refuse` once per failure and covers every item in
    spec 806-815, plus:
    - Mode must be `integration` or `direct`;
    - the Target must be `integration/<slug>` (integration) or
      `$DEFAULT_BRANCH` (direct);
    - ids must match `^[A-Za-z0-9._-]+$`.
  - `build_chains`. It writes `$CHAINS` (`RUN_DIR/chains` once the run
    directory exists), one line per chain:
    `<k>\t<waits csv or ->\t<id> <id> …`.
  - `chain_of ID`, `chain_members K`, `chain_waits K`, and
    `row_field ID FIELD`, where FIELD is one of `branch`, `ticket`, `spec`,
    `plan` and `deps`.
  - `git_retry ARGS…` (D21).
  - `story_launch_env ID`. It prints the env words of spec 686-687 for the
    story: `OMEGA_AUTOPILOT=1 STUDIO_RUN=<abs> STUDIO_STORY=<id>
    STUDIO_DOCS_REV=<sha> BASH_DEFAULT_TIMEOUT_MS=<ms>
    BASH_MAX_TIMEOUT_MS=<ms>`, where `<ms>` is `SESSION_MINUTES` × 60000.

  Run directly, it exits 2 (D18).
- `--dry-run` output:
  1. one line per chain, `chain <k>: <ids>`, or
     `chain <k> (waits on <deps>): <ids>`;
  2. one launch line per chain for its first story (`print_launch` with the
     env words and `--model` for that story's first unit label);
  3. a final line `deny: <n> rules`.

  Exit 0.

**Chain rule** (spec 479-487). This is the algorithm to implement:

```sh
build_chains() {
  awk -F'\t' '
    { id = $1; d = $6
      if (d == "" || d == "-") { open_chain(id, "-"); next }
      n = split(d, ds, ",")
      if (n == 1 && (ds[1] in chainof) && last[chainof[ds[1]]] == ds[1]) {
        k = chainof[ds[1]]; members[k] = members[k] " " id; last[k] = id; chainof[id] = k; next
      }
      open_chain(id, d) }
    function open_chain(id, w) { k = ++nc; members[k] = id; waits[k] = w; last[k] = id; chainof[id] = k }
    END { for (k = 1; k <= nc; k++) printf "%d\t%s\t%s\n", k, waits[k], members[k] }
  ' "$MF_ROWS" > "$CHAINS"
}
```

**Manifest rows** (columns found by header name, spec 446-462):

```sh
awk -F'|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  /^\|/ {
    for (i = 1; i <= NF; i++) c[i] = trim($i)
    if (!hdr) { for (i = 1; i <= NF; i++) col[c[i]] = i; if ("Story" in col) hdr = 1; next }
    if (c[2] ~ /^:?-+:?$/) next
    d = c[col["Depends on"]]; gsub(/[ \t]/, "", d); if (d == "-") d = ""
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", c[col["Story"]], c[col["Branch"]], c[col["Ticket"]], c[col["Spec"]], c[col["Plan"]], d }
' "$MF"
```

  The check that a dependency names an earlier row walks `MF_ROWS` in
  order with a "seen" set. A dependency that is not in the set refuses with
  `manifest: <id> depends on <dep>, which is not an earlier row`.

- [ ] **Step 1: Create `tests/overnight_lanes_test.sh`** with the harness
  (later tasks extend it) and this task's cases.

  Harness, part 1 (this task):
  - Globals, in the same layout as `overnight_test.sh`: `REPO_ROOT`,
    `BIN=$REPO_ROOT/studios/game-dev/bin`, `RUNNER=$BIN/studio-overnight`,
    `STATE_BIN`, `TMP`, `FAKE` (first on `PATH`); per fixture `SCEN`,
    `CALLS`, `GH` and `TMP_WT`, all exported. `calls` prints the global
    call counter (0 when none). `last_lanes_dir` is defined here too.
  - `lanes_fixture NAME MODE ROWS…`. Each ROW is `id:deps`, with `-` for
    no deps. It builds:
    - a bare origin `$TMP/NAME.git` and a clone `P=$TMP/NAME`, on `main`
      with `origin/HEAD` set;
    - `docs/game-dev/specs/2026-10-01-demo.md` with `## Acceptance criteria`
      (items 1-3) and a `## Stories` table holding every id;
    - a plan per story, `docs/game-dev/plans/2026-10-01-<id>.md`, each
      with `Story: <id>`, `## Global Constraints`, `## Decisions` and one
      `### Task 1: t` block carrying `Spec: docs/game-dev/specs/2026-10-01-demo.md:L1-2`
      and `Review: final`;
    - `studio-state init`;
    - per story, with `STUDIO_STORY=<id>`: `init`, `set spec`, `set plan`,
      ledger lines `spec approved <spec>`, `plan approved <plan>` and
      `Decisions swept <id>`, then `set stage plan` and `set task 0/1`;
    - `.studio/config.json` from `$LANES_CONFIG` (default `{}`);
    - a branch `run/demo` holding all of this, committed, pushed, and left
      checked out in `P`;
    - `Docs:` set to that commit's sha;
    - the manifest `docs/runs/demo.md` (header `Mode: MODE`, Target, Docs,
      Goal, and the table, with Branch = `<id>-b` and Ticket = `<id>`),
      committed and pushed;
    - for integration, a push of `origin/main:refs/heads/integration/demo`.

    It exports `P`, `MFP=docs/runs/demo.md`, `CALLS` and `GH` (fresh
    dirs).
  - A stub `gh`. It logs `$*` to `$GH/calls` and exits 0 for
    `auth status`. Every other verb is filled in by T10.
  - A stub `claude` and `claude-gd`, the same `--version` handling as
    `overnight_test.sh`. The session part comes in T8.
  - `run_lanes ARGS`, which runs `studio-overnight ARGS` in `$P`
    capturing `LS_STATUS`, `LS_OUT` and `LS_ERR`, with a 120 s `timeout`
    guard. macOS has no `timeout`: use a background watchdog that kills the
    runner, and fail the test when it fires.

```sh
test_lanes_chain_rule() {
  lanes_fixture chains integration A:- B:- C:A D:A E:C,B F:E
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "dry run exits 0"
  assert_contains "$LS_OUT" "^chain 1: A C$" "a single dependency on a chain's last story appends"
  assert_contains "$LS_OUT" "^chain 2: B$" "an independent row opens a chain"
  assert_contains "$LS_OUT" "^chain 3 (waits on A): D$" "a fork opens a waiting chain"
  assert_contains "$LS_OUT" "^chain 4 (waits on C,B): E F$" "two dependencies open a waiting chain; its successor appends"
  assert_contains "$LS_OUT" "STUDIO_STORY='A' " "the launch line carries the story (env words are KEY='value')"
  assert_contains "$LS_OUT" "STUDIO_DOCS_REV='[0-9a-f]\{40\}'" "and the docs revision"
  assert_contains "$LS_OUT" "BASH_MAX_TIMEOUT_MS='5400000'" "Bash timeout = session_minutes × 60000"
  assert_contains "$LS_OUT" "'--model' 'sonnet'" "the first unit's model"
  assert_contains "$LS_OUT" "Bash(git push \* main)" "the deny rules are expanded"
}
test_lanes_manifest_refusals() {
  lanes_fixture refuse direct A:- B:A
  # direct without merge_command; later-row dependency; duplicate id; a '-' cell
  printf '| C | C-b | C | - | - | D |\n| A | A-b | A | x | y | - |\n' >> "$P/$MFP"
  sed -i.bak 's/^Story: B$/Story: X/' "$P/docs/game-dev/plans/2026-10-01-B.md"; rm -f "$P"/docs/game-dev/plans/*.bak
  ( cd "$P" && git commit -qam break && git push -q origin run/demo ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  for m in "merge_command" "depends on D, which is not an earlier row" "duplicate story A" \
           "C: Spec or Plan is '-'" "B: plan has no 'Story: B' line"; do
    assert_contains "$LS_ERR" "$m" "refusal: $m"
  done
}
test_lanes_preflight_story_checks() {
  lanes_fixture pstory integration A:- B:-
  rm "$P/.studio/stories/B.md"
  printf -- '- 2026-10-01 Stop: x\n' >> "$P/.studio/ledger/A.md"
  git -C "$P" push -q origin --delete integration/demo
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "B: no story file" "a missing story file"
  assert_contains "$LS_ERR" "A: uncommitted ledger change" "a dirty story ledger in START_DIR"
  assert_contains "$LS_ERR" "origin/integration/demo does not exist" "integration branch missing"
}
test_lanes_docs_unreachable() {
  lanes_fixture docs integration A:-
  sed -i.bak 's/^Docs: .*/Docs: 0123456789abcdef0123456789abcdef01234567/' "$P/$MFP"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "Docs: .* is not on origin/run/demo" "the docs revision must be on origin"
}
test_lanes_git_too_old() {
  lanes_fixture oldgit integration A:-
  mkdir -p "$TMP/oldgit-bin"
  printf '#!/bin/sh\ncase "$1" in --version|version) echo "git version 2.30.1";; *) exec %s "$@";; esac\n' "$(command -v git)" > "$TMP/oldgit-bin/git"
  chmod +x "$TMP/oldgit-bin/git"
  PATH="$TMP/oldgit-bin:$PATH" run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "git 2.38 or newer" "git version floor"
}
test_lanes_sourced_only() {
  assert_status 2 "overnight-lanes.sh refuses to run directly" -- sh "$REPO_ROOT/studios/game-dev/bin/overnight-lanes.sh"
}
```

- [ ] **Step 2: Run them and see them fail.**
  `sh tests/overnight_lanes_test.sh`.
- [ ] **Step 3: Implement** `overnight-lanes.sh` with the functions above,
  and the dispatch in `studio-overnight`. The manifest argument is the
  first non-flag argument after `start`, or the argument to `next` or
  `status`.
  - The guard at the top of the file:
    `[ -n "${SELF_DIR:-}" ] || { echo "overnight-lanes.sh: sourced by studio-overnight" >&2; exit 2; }`.
  - Preflight fetches once with `git_retry -C "$START_DIR" fetch -q origin`
    and `… fetch -q origin run/<slug>`. Plan files are read at the docs
    revision with `git show "$MF_DOCS:<plan>"`.
  - The story checks call `STUDIO_STORY=<id> sh "$STATE_BIN" get stage`
    and `… show`. Stage must be `plan` or `execute`, or `idle` with a
    `shipped` line.
- [ ] **Step 4: Run.** `sh tests/overnight_lanes_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/overnight-lanes.sh studios/game-dev/bin/studio-overnight tests/overnight_lanes_test.sh && git commit -m "feat(overnight): manifest parse, chain rule, manifest preflight and dry run"`

---

### Task 7: `studio-overnight next` — the planning loop's next command
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/overnight-lanes.sh, studios/game-dev/bin/studio-overnight, tests/overnight_lanes_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L207-216, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L463-475
Review: final

**Risk:** mechanical. It is a pure read, and it folds into the final
review. Covers AC3's `next` half.

**Interfaces:**
- `studio-overnight next [<manifest>]`. With no argument it reads
  `.studio/run` (D9). It runs no preflight and needs no `gh` or
  `claude-gd`. It parses with `mf_load`, but the `Spec`/`Plan` cells may be
  `-`.
- Resolution of a `-` cell:
  - the spec is the one tracked `*.md` file (`git -C "$START_DIR" ls-files
    '*.md'`) that has a `## Stories` table whose first column equals the
    id;
  - the plan is the one tracked `*.md` file with a line exactly
    `Story: <id>`;
  - two matches refuse with
    `next: <id> matches two specs: <a>, <b>` (or `plans`), exit 2.

  A filled cell is used as written.
- Class, from files and ledger lines alone. The ledger is
  `START_DIR/.studio/ledger/<spec slug>.md`, where the slug is the spec's
  basename without `.md` and without a leading date (the same rule as
  `studio-state`'s `feature_slug`):
  - `brainstorm`: no spec, or no `spec approved <spec>` line;
  - `plan`: the spec is approved, but there is no plan, or no
    `plan approved <plan>` line, or no `Decisions swept <id>` line;
  - `planned`: everything else.
- Output: one line per row,
  `<id>  <class>  spec=<path or ->  plan=<path or ->`, then exactly one
  of:
  - `next: /game-dev:brainstorm <id>`, for the first row in manifest
    order whose class is `brainstorm`;
  - otherwise `next: /game-dev:plan <id>`, for the first row whose class
    is `plan`;
  - otherwise `next: /omega:autopilot`.

  Exit 0.

- [ ] **Step 1: Write the failing tests** (append to the lanes suite):

```sh
test_lanes_next() {
  LANES_CELLS=dash lanes_fixture nxt integration A:- B:A C:-
  # Make B unplanned (no Decisions swept) and C brand new (no spec row, no plan).
  # (fixture built with LANES_CELLS=dash: every Spec and Plan cell is '-')
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-A.md\n- 2026-10-01 Decisions swept A\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-B.md\n' > "$P/.studio/ledger/demo.md"
  grep -v '^| C |' "$P/docs/game-dev/specs/2026-10-01-demo.md" > "$TMP/s" && mv "$TMP/s" "$P/docs/game-dev/specs/2026-10-01-demo.md"
  rm -f "$P/docs/game-dev/plans/2026-10-01-C.md"
  ( cd "$P" && git add -A && git commit -qm planning-state ) >/dev/null 2>&1
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next exits 0"
  assert_contains "$LS_OUT" "^A  planned  spec=docs/game-dev/specs/2026-10-01-demo.md  plan=docs/game-dev/plans/2026-10-01-A.md$" "A resolved and planned"
  assert_contains "$LS_OUT" "^B  plan  " "B lacks its sweep line"
  assert_contains "$LS_OUT" "^C  brainstorm  spec=-  plan=-$" "C has no spec row"
  assert_contains "$LS_OUT" "^next: /game-dev:brainstorm C$" "brainstorm comes before plan"
  printf '%s\n' "$MFP" > "$P/.studio/run"
  run_lanes next
  assert_contains "$LS_OUT" "^next: /game-dev:brainstorm C$" "no argument reads .studio/run"
  rm "$P/.studio/run"; run_lanes next
  assert_eq 2 "$LS_STATUS" "no pointer and no argument exits 2"
  assert_contains "$LS_ERR" "no run manifest (.studio/run)" "and says why"
}
test_lanes_next_all_planned_and_ambiguous() {
  LANES_CELLS=dash lanes_fixture nxt2 integration A:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-A.md\n- 2026-10-01 Decisions swept A\n' > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^next: /omega:autopilot$" "every row planned"
  cp "$P/docs/game-dev/plans/2026-10-01-A.md" "$P/docs/game-dev/plans/2026-10-02-A2.md"
  ( cd "$P" && git add -A && git commit -qm dup ) >/dev/null 2>&1
  run_lanes next "$MFP"
  assert_eq 2 "$LS_STATUS" "two plans for one story"
  assert_contains "$LS_ERR" "A matches two plans" "the refusal names both"
}
```

  The fixture gains `LANES_CELLS=dash`, which writes `-` in every Spec and
  Plan cell, as a manifest looks while it is being planned. The fixture
  leaves the spec-slug ledger `demo.md` empty, so these tests write it
  themselves.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** `lanes_next` in `overnight-lanes.sh`, and the
  `next` verb in `studio-overnight`'s dispatch and `usage`.
- [ ] **Step 4: Run** the lanes suite, then `sh tests/run_all.sh`.
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/overnight-lanes.sh studios/game-dev/bin/studio-overnight tests/overnight_lanes_test.sh && git commit -m "feat(overnight): next classifies manifest rows and prints the one next command"`

---

### Task 8: Lanes and the per-story unit loop
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/overnight-lanes.sh, studios/game-dev/bin/studio-overnight, tests/overnight_lanes_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L489-499, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L517-536, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L541-544, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L683-697, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L267-270, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L316-321
Review: task

**Risk:** a new seam (lane processes). It needs T1's D1c result, T2 and
T6. Covers AC5, AC13's lane half, AC25's half above 0, and AC26.

**Interfaces:**
- `lanes_start` (the run path). In order:
  1. Take bundle 2's lock (same file, same reclaim) and create
     `RUN_DIR="$REPORTS/overnight-<slug>-<ts>"` with `manifest.md`,
     `rows.tsv`, `chains`, `claims/`, `stories/` and `lanes/`.
  2. Create the record dir `RECORD="$STATE_ROOT/.studio/runs/<slug>"` and
     touch `landed.tsv`.
  3. Write `stories/<id>` = `queued` for every row (D19).
  4. Arm the runner's EXIT trap, and an INT/TERM trap that does
     `: > "$STOP_FILE"`.
  5. Start `L` lanes, each as `( lane_main <k> ) &`, recording
     `LANE_PIDS`.
  6. Wait for each lane with bundle 2's D7 loop per pid. A trap
     interrupts `wait`, and the loop waits for the same pid again.
  7. The parent's sweep (T9).
  8. The final step (T11). T12 writes the report and the ending; until T12
     lands, the ending is `done` when every story is `landed`, else
     `partial`.

  `L` is the chain count when `MAX_LANES` is 0, else
  `min(MAX_LANES, chains)`.
- `lane_main K`, in a background subshell:
  - The first statements are
    `trap 'lane_exit $?' EXIT; trap 'lane_stopflag' INT TERM HUP`. Then it
    sets `LDIR=$RUN_DIR/lanes/$K` and `UNIT_DIR=$LDIR`.
  - The claim loop:
    `for c in $(seq of chain numbers): mkdir "$RUN_DIR/claims/$c" 2>/dev/null && { echo $$ > …/pid; echo $K > …/lane; run_chain $c; }`.
    The pid written is `$BASHPID`, or under `sh` a `sh -c 'echo $PPID'`
    from inside the subshell. A lane stops claiming when `lane_halt` is
    true.
  - `lane_halt` is true when the stop file exists, the runner pid is not
    alive (`kill -0 "$RUNNER_PID"`), or the lane has hit the run budget.
- `run_chain C`. For each story in the chain, in order: when the previous
  story did not end `landed`, write `skipped <prev id>` (T9 extends this to
  the whole chain). Otherwise run `run_story ID`.
- `run_story ID`:
  - export `STUDIO_STORY=ID`, then `STUDIO_RUN`, `STUDIO_DOCS_REV` and the
    `BASH_*_TIMEOUT_MS` pair;
  - set `UNIT_PREFIX="$ID-"`;
  - write `stories/ID` = `running`;
  - call `story_units` (T5). Before each launch, `UNIT_MODEL` is set from
    `model_for <label>`, and `lanes/<k>/current` is written as
    `<id> <label>` (D25);
  - on `ENDING=done` (stage `idle`, a `shipped` line), write
    `stories/ID` = `landing` and call `land_story ID`. Until T10, a stub
    writes `landed <branch head sha>` and appends to `landed.tsv`;
  - on any other ending, write `stopped <ending>`.
- In manifest mode, `story_units`' helpers change:
  - `stop_requested` is `lane_halt`;
  - `spent_all` sums column 4 of every `$RUN_DIR/lanes/*/units.tsv`;
  - when `RUN_USD` > 0 and the spend plus `SESSION_USD` exceeds it, the
    ending is `stop: run budget`, and the lane claims no more chains;
  - `state`, `feature_dir`, `ledger_of` and `snapshot` work unchanged,
    because they call `studio-state` with `STUDIO_STORY` exported.
- `start_session` under a lane, by D1c's result: either `set -m` in the
  lane subshell, or a launch through
  `perl -e 'setpgrp(0,0); exec @ARGV' claude-gd …`. The env words come from
  `story_launch_env`. `STUDIO_GATE_HELD` is never exported (D17).

**Harness, part 2** (the stub session, keyed by `STUDIO_STORY` and the
prompt):
- Global call numbering through a `mkdir "$CALLS/n.lock"` spin. Each call
  records `<n>.argv`, `<n>.story`, `<n>.prompt`, `<n>.env` (the values of
  `OMEGA_AUTOPILOT`, `STUDIO_RUN`, `STUDIO_DOCS_REV`, `STUDIO_REPAIR` and
  `STUDIO_GATE_HELD`), `<n>.t0` and `<n>.t1`.
- The scenario is `$SCEN/<id>` (unit prompts), `$SCEN/<id>.land`
  (`--land`), `$SCEN/progress` and `$SCEN/final-repair`. Line m is used on
  the story's m-th call of that kind. A missing line means `auto`.
- `auto` plays one well-behaved unit, as execute §0/§8 would:
  - with no story branch: `git fetch`, then
    `git worktree add --no-track -b <Branch> $TMP_WT/<Branch> origin/<Target>`,
    then a checkout of the docs revision's spec, plan and story ledger,
    committed, then `studio-state set branch` and `set stage execute`;
  - for a task: commit `<id>-T<k>.txt`, push, ledger `T<k> complete`
    (committed in the worktree), `set task k/N`;
  - for the final review: ledger `final review done`, committed and
    pushed;
  - for the finish:
    - integration: push, ledger `shipped <Branch>`;
    - direct: `gh pr create --draft --base main --head <Branch>`, ledger
      `shipped <url>`;

    then `set stage idle` and `set task -`.

  Other actions: `stop <reason>`; `noop`; `sleep <s>`; `hang`;
  `cost <usd>`; `exit <code>`; `gate <s>`. `gate <s>` runs
  `sh $BIN/studio-gate studio-test -- sh -c 'echo s <story> $(date +%s) >> $CALLS/gate.iv; sleep <s>; echo e <story> $(date +%s) >> $CALLS/gate.iv'`.
  The stub learns `Branch` and `Target` from `$STUDIO_RUN`'s rows and
  header, with the same awk as T6.

- [ ] **Step 1: Write the failing tests:**

```sh
test_lanes_two_independent_to_landed() {
  lanes_fixture two integration A:- B:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "both stories land (stub landing)"
  for id in A B; do
    assert_contains "$(last_lanes_dir)/stories/$id" "^landed " "$id ends landed"
    assert_eq 3 "$(grep -lx "$id" "$CALLS"/*.story | wc -l | tr -d ' ')" "$id: one launch per unit (T1, final review, finish)"
  done
  assert_eq 2 "$(ls -d "$(last_lanes_dir)"/lanes/* | wc -l | tr -d ' ')" "max_lanes 0 = one lane per chain"
}
test_lanes_max_lanes_one_serializes() {
  LANES_CONFIG='{"overnight": {"max_lanes": 1}}' lanes_fixture one integration A:- B:-
  run_lanes start "$MFP"
  assert_eq 1 "$(ls -d "$(last_lanes_dir)"/lanes/* | wc -l | tr -d ' ')" "one lane"
  # every B unit starts after every A unit ended
  a_end="$(for n in $(grep -lx A "$CALLS"/*.story | sed 's#.*/\([0-9]*\)\.story#\1#'); do cat "$CALLS/$n.t1"; done | sort -n | tail -n 1)"
  b_start="$(for n in $(grep -lx B "$CALLS"/*.story | sed 's#.*/\([0-9]*\)\.story#\1#'); do cat "$CALLS/$n.t0"; done | sort -n | head -n 1)"
  assert_eq 1 "$([ "$b_start" -ge "$a_end" ] && echo 1 || echo 0)" "the one lane runs the chains one after another"
}
test_lanes_models_and_env() {
  LANES_CONFIG='{"overnight": {"model_task": "t-m", "model_final": "f-m", "model_finish": "x-m"}}' lanes_fixture models integration A:-
  run_lanes start "$MFP"
  for pair in "1 t-m" "2 f-m" "3 x-m"; do set -- $pair
    assert_eq "$2" "$(sed -n 4p "$CALLS/$1.argv")" "call $1 runs with --model $2"
  done
  assert_contains "$CALLS/1.env" "STUDIO_RUN=.*/manifest.md" "STUDIO_RUN names the run's copy of the manifest"
  assert_contains "$CALLS/1.env" "STUDIO_DOCS_REV=[0-9a-f]\{40\}" "the docs revision"
  assert_contains "$CALLS/1.env" "STUDIO_GATE_HELD=$" "STUDIO_GATE_HELD never reaches a session"
}
test_lanes_story_stop_isolated() {
  lanes_fixture stopone integration A:- B:-
  printf 'stop broken fixture\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_eq 1 "$LS_STATUS" "a stopped story makes the run partial"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: broken fixture" "A stopped with its reason"
  assert_contains "$(last_lanes_dir)/stories/B" "^landed " "B still landed"
}
test_lanes_budget() {
  LANES_CONFIG='{"overnight": {"run_usd": 30, "session_usd": 25}}' lanes_fixture budget integration A:-
  printf 'cost 10\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: run budget" "spent 10 + 25 > 30 stops before the second launch"
  assert_eq 1 "$(calls)" "exactly one launch"
}
test_lanes_overhead() {
  lanes_fixture overhead integration A:-
  run_lanes start "$MFP"
  gap="$(( $(cat "$CALLS/2.t0") - $(cat "$CALLS/1.t1") ))"
  assert_eq 1 "$([ "$gap" -le 5 ] && echo 1 || echo 0)" "runner overhead between units ≤ 5 s (got $gap)"
}
test_lanes_docs_revision() {
  lanes_fixture docsrev integration A:- B:A
  printf 'sleep 3\n' > "$SCEN/A"
  ( cd "$P" && sleep 1 && printf 'CHANGED\n' >> docs/game-dev/plans/2026-10-01-B.md && git commit -qam mid-run ) &
  run_lanes start "$MFP"; wait
  b_wt="$(git -C "$P" worktree list --porcelain | sed -n 's/^worktree //p' | grep '/B-b$')"
  assert_not_contains "$b_wt/docs/game-dev/plans/2026-10-01-B.md" "CHANGED" "a later story reads docs from the Docs revision only"
}
```

  `last_lanes_dir` is `ls -d "$P"/.studio/reports/overnight-demo-* | tail -n 1`,
  and `calls` reads the global counter. The overhead test samples twice
  and keeps the shorter gap (studio memory: wall-clock timing tests).
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the interfaces above. Re-use `run_unit`, `row`,
  `snapshot`, `label_for` and the watchdog as they are. Only the
  launch-env words and the directory variables change.
- [ ] **Step 4: Run** the lanes suite, `sh tests/overnight_test.sh`
  (single-plan unchanged), then `sh tests/run_all.sh`. Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/overnight-lanes.sh studios/game-dev/bin/studio-overnight tests/overnight_lanes_test.sh && git commit -m "feat(overnight): lane processes run each chain's stories one fresh session per unit"`

---

### Task 9: Waiting chains, skips, crashed lanes and stops
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/overnight-lanes.sh, tests/overnight_lanes_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L106-128, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L500-516, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L224-226, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L276-282
Review: task

**Risk:** cross-system (signals across processes). Covers AC6, AC15 and
AC16's lane and runner half.

**Interfaces:**
- `wait_deps ID`. It runs before the first story of a chain whose waits
  are not `-`:
  - write `stories/ID` = `waiting`, then loop every
    `${STUDIO_OVERNIGHT_POLL_SECONDS:-5}` s (D20);
  - return 2 (stop) on `lane_halt`;
  - return 0 when every dependency has a `^<dep>\t` line in
    `$RECORD/landed.tsv`;
  - return 1 with `BLOCKER=<dep>` when a dependency's `stories/<dep>` is
    `stopped*` or `skipped*`, or when its chain is claimed
    (`claims/<k>/pid` exists), that pid is dead, and the dependency is not
    `landed`.

  A waiting story then starts from `origin/<Target>` at that moment: its
  first unit's §0 fetches, so the runner needs nothing more.
- Skip propagation, in `run_chain`:
  - a story whose predecessor did not land is written `skipped <pred id>`;
  - a chain whose first story's `wait_deps` returned 1 writes
    `skipped <BLOCKER>` for its first story, and
    `skipped <first id>` for every later story;
  - `wait_deps` returning 2 writes `skipped: run stopped` for the rest
    (D2).
- `lane_exit RC`, the lane's EXIT trap:
  - `end_session` (any live unit's process group);
  - when `CUR_STORY` is set and its `stories/` line is not an ending,
    write `stopped: lane crashed (<RC>)`, and `skipped <CUR_STORY>` for the
    rest of its chain;
  - `rmdir` the land lock when this lane holds it (T10).
- The parent's sweep, after every lane has been waited for, chain
  by chain:
  - in a claimed chain, the first story whose `stories/` line is not an
    ending gets `stopped: lane crashed (<rc of that lane>)`, and every
    later story in the chain gets `skipped <that id>`;
  - every story of an unclaimed chain gets `skipped: run stopped`.

  The parent records each lane's rc from the D7 loop.
- Stops: the runner's INT/TERM trap creates the stop file. Each lane checks
  `lane_halt` before every launch, before every landing, and on every wait
  tick, so a running unit finishes and nothing new starts. A lane whose
  runner pid is gone launches nothing more.

- [ ] **Step 1: Write the failing tests:**

```sh
test_lanes_waiting_chain_starts_after_deps() {
  lanes_fixture wait integration A:- B:- C:A,B
  printf 'sleep 2\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_POLL_SECONDS=1 run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "all three land"
  c_t0="$(cat "$CALLS/$(grep -lx C "$CALLS"/*.story | sed 's#.*/\([0-9]*\)\.story#\1#' | sort -n | head -n 1).t0")"
  last_land="$(awk -F'\t' '$1=="A"||$1=="B"{print $4}' "$P/.studio/runs/demo/landed.tsv" | sort -n | tail -n 1)"
  assert_eq 1 "$([ $((c_t0 - last_land)) -le 5 ] && echo 1 || echo 0)" "C starts within 5 s of its last dependency landing"
}
test_lanes_skip_on_stopped_dep() {
  lanes_fixture skipdep integration A:- A2:- B:A C:A,A2
  printf 'stop nope\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_POLL_SECONDS=1 run_lanes start "$MFP"
  R="$(last_lanes_dir)"
  assert_contains "$R/stories/B" "^skipped A$" "the rest of A's chain is skipped"
  assert_contains "$R/stories/C" "^skipped A$" "a chain waiting on A is skipped, naming A"
  assert_contains "$R/stories/A2" "^landed " "an unrelated chain lands"
}
test_lanes_lane_kill9() {
  lanes_fixture kill9 integration A:- B:A C:-
  printf 'hang\n' > "$SCEN/A"
  ( cd "$P" && sh "$RUNNER" start "$MFP" ) > "$TMP/k9.out" 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  lane1="$(cat "$P"/.studio/reports/overnight-demo-*/claims/1/pid)"
  kill -9 "$lane1"; pkill -9 -f "$TMP/fakebin/claude" 2>/dev/null
  wait_pid_or_fail "$RPID" 60 "the runner does not hang on a dead lane"
  R="$(last_lanes_dir)"
  assert_contains "$R/stories/A" "^stopped: lane crashed (" "the parent marks the crashed lane's story"
  assert_contains "$R/stories/B" "^skipped A$" "the rest of the dead lane's chain is skipped, naming A"
  assert_contains "$R/stories/C" "^landed " "the other lane finished"
}
test_lanes_sigint() {
  lanes_fixture sigint integration A:- B:-
  printf 'sleep 3\n' > "$SCEN/A"; printf 'sleep 3\n' > "$SCEN/B"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > "$TMP/si.out" 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/2.t0' ]" 20
  kill -INT "$RPID"
  wait_pid_or_fail "$RPID" 60 "the runner ends after SIGINT"
  assert_eq 2 "$(calls)" "the two running units finish; nothing new starts"
  assert_file "$CALLS/1.t1" "unit 1 ran to its end"
  for id in A B; do assert_contains "$(last_lanes_dir)/stories/$id" "^stopped stopped by user" "$id ends stopped by user"; done
}
test_lanes_runner_gone() {
  lanes_fixture gone integration A:-
  printf 'sleep 3\n' > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  kill -9 "$RPID"
  sleep 6
  assert_eq 1 "$(calls)" "a lane launches nothing once the runner pid is gone"
}
test_lanes_stop_file() {
  lanes_fixture stopf integration A:-
  printf 'sleep 2\n' > "$SCEN/A"
  ( cd "$P" && sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  ( cd "$P" && sh "$RUNNER" stop ) >/dev/null
  wait_pid_or_fail "$RPID" 60 "the runner ends after stop"
  assert_eq 1 "$(calls)" "the running unit finishes; nothing new starts"
}
```

  The harness gains two helpers:
  - `wait_for COND SECS` polls each second;
  - `wait_pid_or_fail PID SECS MSG` kills the pid and fails MSG when it
    is still alive after SECS.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** the lanes suite, then `sh tests/run_all.sh`.
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh && git commit -m "feat(overnight): waiting chains, skips, crashed lanes and stops end every story"`

---

### Task 10: Landing — clean merges with no session, one repair, idempotent resume
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/overnight-lanes.sh, tests/overnight_lanes_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L555-585, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L517-524, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L227-237, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L129-133
Review: task

**Risk:** cross-system. It writes to origin, and it holds the lock order.
It needs T4 and T9. Covers AC7, AC8, AC10's runner half and AC24's resume
half.

**Interfaces:**
- **D27.** A `landed.tsv` line is `<id>\t<Target>\t<sha>\t<epoch>`. It adds
  a fourth column to spec 375, read by the waiting-chain timing test and by
  the report. `record_landed ID SHA` appends the line (only when no line
  for the id exists) and writes `stories/ID` = `landed <sha>`.
- `land_story ID`. It returns 0 when landed; otherwise it writes the
  story's `stopped …` ending and returns 1.
  1. Take the land lock: `mkdir "$RUN_DIR/land.lock"` holding the lane's
     pid. Poll every `STUDIO_OVERNIGHT_POLL_SECONDS` s, and on `lane_halt`
     write `stopped stopped by user` and return 1. Lock order is always
     the land lock, then the gate lock (spec 557-560).
  2. `land_once ID`. Its return codes:
     - 0: landed, with `LAND_SHA` set;
     - 3: needs repair, with `LAND_REPAIR` = `conflict` or `red:<log>`;
     - 4: failed, with `LAND_WHY` set.
  3. On 3, the first time:
     - write `stories/ID` = `repair` and launch one repair unit. Its label
       is `repair` and its model is `model_repair` (D23). Its prompt is
       `/game-dev:execute --land`, with `STUDIO_REPAIR=$LAND_REPAIR` added
       to the env words;
     - a new `Stop:` line → `stopped stop: <reason>`;
     - a new `Repair:` line in the story ledger (`ledger_of` the feature
       checkout) → run `land_once` again;
     - neither → `stopped repair made no progress`.

     On 3 the second time, the ending is
     `stopped landing failed after repair (<conflict or red>)`.
  4. Release the land lock in every path. The lane's EXIT trap also
     releases it (T9).
- `land_once ID`, integration (spec table, the left column):
  - `git_retry -C "$START_DIR" fetch -q origin`;
  - **step 0:** when `origin/<Branch>` exists, is an ancestor of
    `origin/<Target>`, and `git show origin/<Branch>:.studio/ledger/<id>.md`
    has a `shipped` line, the story is already landed. `LAND_SHA` is the
    last line of
    `git log --merges --ancestry-path --format=%H origin/<Branch>..origin/<Target>`,
    the oldest merge on that path. When there is none, it is
    `git rev-parse origin/<Branch>` (D4). The `shipped` check keeps a
    branch with no commits of its own from counting as landed;
  - **step 1:** `tree="$(git merge-tree --write-tree origin/<Target> origin/<Branch>)"`.
    Exit 1 means conflict → return 3. Any other non-zero → return 4;
  - **step 2:** `sha="$(git commit-tree "$tree" -p origin/<Target> -p origin/<Branch> -m "Merge <Branch> (<id>) into <Target>")"`,
    then `git_retry push -q origin "$sha:refs/heads/<Target>"`. When the
    push is rejected, fetch and go back to step 0 once. A second rejection
    → return 4 with `push to <Target> rejected twice`;
  - test hook: `STUDIO_OVERNIGHT_LAND_HOOK` is shell text evaluated right
    after a successful push and before `record_landed` (D20's list);
  - no checkout is touched.
- `land_once ID`, direct (spec table, the right column):
  - **step 0:** `gh pr view <Branch> --json state,mergeCommit,isDraft,number`,
    with fields pulled out by `sed`. `MERGED` → `LAND_SHA` = the merge
    commit's oid → return 0;
  - **step 1:** `git merge-tree --write-tree origin/<default> origin/<Branch>`
    exits 1 → return 3 (`conflict`);
  - **step 2:** `gh pr ready <n>` when it is a draft. The command is
    `MERGE_COMMAND` with `<pr>` replaced by `<n>`, its first word resolved
    to `$START_DIR/<word>` (the program in `START_DIR`, never the story's
    copy). Run it as
    `( cd <story worktree or START_DIR> && sh "$SELF_DIR/studio-gate" merge -- <program> <args> ) > "$LDIR/<id>-land.log" 2>&1 < /dev/null`;
  - **step 3:** whatever the exit code, `gh pr view` again. `MERGED`, plus
    `git merge-base --is-ancestor <oid> origin/<default>` after a fetch →
    return 0. Otherwise `LAND_REPAIR=red:<abs log path>` → return 3.
- `run_story` before `story_units`: when the story is at `stage idle` with
  a `shipped` line, it goes straight to `land_story` (no unit).
- **Resume at start** (`lanes_start`, before the lanes start), for each
  row:
  - integration: step 0's confirmation;
  - direct: `gh pr view <Branch> --json state` is `MERGED`.

  A confirmed story is written `landed <sha>` and appended to `landed.tsv`
  when it is missing. Then `run_chain` skips it as landed. A story without
  confirmation starts from its studio state.
- Lock rule: the merge command is the only gate the runner holds during a
  landing, and it holds it through `studio-gate`. The repair unit is
  launched after `studio-gate` has exited, so the repair session's
  `studio-test` takes the gate lock itself (D17).

**Harness, part 3:**
- `gh` gains a full state stub:
  - PRs live as files `$GH/pr-<n>`, holding `head=`, `base=`,
    `state=OPEN|MERGED`, `draft=1|0` and `oid=`;
  - `pr create --draft --base B --head H` prints `https://gh.test/pr/<n>`;
  - `pr view <n|head> --json …` prints
    `{"state":"…","isDraft":…,"number":n,"mergeCommit":{"oid":"…"}}`;
  - `pr ready`, `pr list --head H --base B --state open --json number,url`
    (prints `[]` or one object), `pr edit <n> …` (records `--title` and
    the body file's content), and `pr create` without `--draft` (direct
    progress) are also stubbed;
  - every call is logged to `$GH/calls`.
- A stub merge program `scripts/merge.sh`, committed in the direct
  fixture:
  - it appends `s merge <epoch>` and `e merge <epoch>` around its work to
    `$CALLS/gate.iv`;
  - its outcome is the next word of `$MERGE_OUTCOMES` (default `ok`),
    using a counter file;
  - `ok` clones the bare origin to a temp dir, does
    `git merge --no-ff origin/<head>` into `main`, pushes, and writes
    `state=MERGED` and `oid=<merge sha>` to the PR file;
  - `refuse` exits 1 with no merge;
  - `MERGE_DELETES_BRANCH=1` also deletes `origin/<head>`.
- Scenario actions:
  - `conflict <file>`: the unit's task commit writes `<file>` with the
    story id as content;
  - `repair`, under `--land`: `git merge origin/<Target>`, resolved with
    `-X theirs` for the test, then commit, push, and a committed ledger
    line `Repair: merged target`;
  - `fakerepair`: writes the `Repair:` line only.

- [ ] **Step 1: Write the failing tests:**

```sh
test_lanes_land_clean_integration() {
  lanes_fixture landi integration A:- B:-
  main0="$(git -C "$P" rev-parse origin/main)"
  run_lanes start "$MFP"
  assert_eq 0 "$(grep -l -- '--land' "$CALLS"/*.argv 2>/dev/null | wc -l | tr -d ' ')" "no session for a clean landing"
  git -C "$P" fetch -q origin
  assert_eq 2 "$(git -C "$P" log --merges --format=%s origin/integration/demo | grep -c '^Merge .* into integration/demo$')" "two runner merge commits on the integration branch"
  assert_eq "$main0" "$(git -C "$P" rev-parse origin/main)" "nothing reaches main"
  assert_eq 2 "$(wc -l < "$P/.studio/runs/demo/landed.tsv" | tr -d ' ')" "two landed lines"
}
test_lanes_land_clean_direct() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}' lanes_fixture landd direct A:- B:-
  run_lanes start "$MFP"
  assert_eq 0 "$(grep -l -- '--land' "$CALLS"/*.argv 2>/dev/null | wc -l | tr -d ' ')" "no session for a clean landing"
  assert_eq 2 "$(grep -c '^pr ready ' "$GH/calls")" "each draft PR is made ready by the runner"
  assert_eq 2 "$(grep -c '^s merge' "$CALLS/gate.iv")" "the merge program ran once per story"
  git -C "$P" fetch -q origin
  for id in A B; do
    assert_status 0 "$id is in origin/main" -- git -C "$P" merge-base --is-ancestor "origin/$id-b" origin/main
  done
}
test_lanes_land_conflict_one_repair() {
  LANES_CONFIG='{"overnight": {"max_lanes": 1}}' lanes_fixture landc integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\n' > "$SCEN/B"; printf 'repair\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_eq 1 "$(grep -l -- '--land' "$CALLS"/*.argv | wc -l | tr -d ' ')" "exactly one repair unit"
  n="$(grep -l -- '--land' "$CALLS"/*.argv | sed 's#.*/\([0-9]*\)\.argv#\1#')"
  assert_contains "$CALLS/$n.env" "STUDIO_REPAIR=conflict" "the repair knows why"
  assert_eq opus "$(sed -n 4p "$CALLS/$n.argv")" "the repair runs on model_repair"
  assert_contains "$(last_lanes_dir)/stories/B" "^landed " "the retry lands"
}
test_lanes_land_second_conflict_stops() {
  LANES_CONFIG='{"overnight": {"max_lanes": 1}}' lanes_fixture landc2 integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\n' > "$SCEN/B"; printf 'fakerepair\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped landing failed after repair (conflict)" "a second conflict stops the story"
}
test_lanes_direct_refused_then_repaired() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}' lanes_fixture landr direct A:-
  printf 'repair\n' > "$SCEN/A.land"
  MERGE_OUTCOMES="refuse ok" run_lanes start "$MFP"
  n="$(grep -l -- '--land' "$CALLS"/*.argv | sed 's#.*/\([0-9]*\)\.argv#\1#')"
  assert_contains "$CALLS/$n.env" "STUDIO_REPAIR=red:.*A-land.log" "a refused merge command repairs with its log"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "the retry lands"
}
test_lanes_land_idempotent() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}' lanes_fixture idem direct A:-
  run_lanes start "$MFP"                                  # lands A
  : > "$CALLS/gate.iv"; rm -rf "$P/.studio/runs/demo"     # forget the runner's record
  MERGE_DELETES_BRANCH=0 run_lanes start "$MFP"
  assert_eq 0 "$(grep -c '^s merge' "$CALLS/gate.iv")" "a merged PR is recorded with no merge command"
  assert_contains "$P/.studio/runs/demo/landed.tsv" "^A	main	[0-9a-f]\{40\}	" "and appended to landed.tsv from GitHub alone"
}
test_lanes_land_crash_after_push() {
  lanes_fixture crashp integration A:-
  STUDIO_OVERNIGHT_LAND_HOOK='kill -9 $(sh -c "echo \$PPID")' run_lanes start "$MFP"
  run_lanes start "$MFP"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(git -C "$P" log --merges --format=%s origin/integration/demo | grep -c '^Merge A-b')" "no second merge commit"
  assert_eq 0 "$(grep -l -- '--land' "$CALLS"/*.argv 2>/dev/null | wc -l | tr -d ' ')" "no repair"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "the resume records the landing from git alone"
}
test_lanes_gate_never_overlaps() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}' lanes_fixture gate direct A:- B:- C:-
  for id in A B C; do printf 'gate 1; auto\n' > "$SCEN/$id"; done
  run_lanes start "$MFP"
  assert_eq "" "$(awk '$1=="s"{if(open)print "overlap at " $3; open=1} $1=="e"{open=0}' "$CALLS/gate.iv")" "unit tests and merge commands never overlap"
}
```

  (`gate 1; auto` makes the stub run a gated 1-second `studio-test` and
  then the normal unit. Every unit in three lanes plus three merge
  commands writes to one `gate.iv`.)
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the interfaces above, replacing T8's stub
  `land_story`.
- [ ] **Step 4: Run** the lanes suite, then `sh tests/run_all.sh`.
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh && git commit -m "feat(overnight): the runner lands stories, one repair and one retry, idempotent on resume"`

---

### Task 11: Integration final step and the direct progress landing
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/overnight-lanes.sh, tests/overnight_lanes_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L587-626, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L238-245, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L134-137
Review: task

**Risk:** cross-system. It needs T10. Covers AC9, and D13's direct
progress landing.

**Interfaces:**
- `final_step`. The runner calls it after the sweep, only when no stop was
  requested and at least one story landed.
  - In integration mode it runs `final_integration`. In direct mode it runs
    `progress_direct`. Each runs only when
    `$START_DIR/docs/game-dev/PROGRESS.md` exists at the docs revision;
    otherwise there is no progress unit.
  - It sets `FINAL_PR` (the url), `FINAL_COLOR` (`green` or `red`) and
    `FINAL_NOTE`.
- `final_integration`, in the worktree
  `W=$STATE_ROOT/.claude/worktrees/integration-<slug>`:
  - **step 0:** when `$RECORD/final` names the current
    `origin/integration/<slug>` head, and
    `gh pr list --head integration/<slug> --base main --state open`
    returns a PR, skip to the end (D5);
  - **step 1:**
    - `git_retry worktree add --detach "$W" origin/integration/<slug>`
      when `W` is missing;
    - else, after `git -C "$W" status --porcelain` is empty, keep `HEAD`
      when it descends from `origin/integration/<slug>` (D5), or else
      `switch --detach`;
    - then `git merge --no-edit origin/main`. On a conflict:
      `merge --abort`, then one final-repair unit, launched with cwd `W`,
      prompt `/omega:integration repair <slug>` and model `model_repair`.
      When the merge is still not done (`MERGE_HEAD` exists, or
      `origin/main` is not an ancestor of `HEAD`), the color is `red` and
      `FINAL_NOTE` is `origin/main does not merge cleanly`, and the step
      continues with the integration head unmerged;
  - **step 2:** unless `HEAD`'s subjects already contain
    `docs(progress): <slug>` (D5), run one progress unit with cwd `W`,
    prompt `/game-dev:execute --progress`, model `model_progress` and
    `STUDIO_RUN` in its env (no `STUDIO_STORY`);
  - **step 3:** unless `$RECORD/gate` names `HEAD` (D5), run the gate:
    `sh "$SELF_DIR/studio-gate" final-gate -- sh -c "$GATE_CMDS"` in `W`.
    - `GATE_CMDS` defaults to
      `sh '<SELF_DIR>/studio-test' && { sh '<SELF_DIR>/studio-lint'; [ $? -eq 0 ] || [ $? -eq 3 ]; } && sh '<SELF_DIR>/studio-run' --seconds 10`
      (§7 step 1's exit rules; lint exit 3 is not red). The test hook
      `STUDIO_OVERNIGHT_GATE_CMD` replaces it.
    - Red → one final-repair unit → the gate once more → still red means
      red.
    - Write `$RECORD/gate` as `<HEAD sha> green|red`;
  - **step 4:**
    `git_retry -C "$W" push origin HEAD:refs/heads/integration/<slug>`;
  - **step 5:** the PR body, written to `$RUN_DIR/final-body.md` by
    `sed` and `git show` (no session):
    - per landed story: a `## <id>` section with its spec's `## Purpose`
      at the docs revision, its ledger's `Ruling:` and `P<k> Play:` lines
      from `git show origin/<Branch>:.studio/ledger/<id>.md` (when the
      branch was deleted, from the merge sha's second parent), and its
      merge sha;
    - a `## Not landed` list of the other stories with their endings;
    - a gate line.

    The title is `<slug>: <Goal>`, prefixed `[red] ` when red. When an
    open PR exists: `gh pr edit <n> --title … --body-file …`. Otherwise:
    `gh pr create --draft --base main --head integration/<slug> --title … --body-file …`;
  - **step 6:** write `$RECORD/final` as
    `<integration head> <PR url> <green|red>`.

  Nothing is merged into `main`, and the PR is never merged.
- `progress_direct`. It runs after the last landing, when PROGRESS exists:
  - `git_retry worktree add --no-track -b progress/<slug> "$STATE_ROOT/.claude/worktrees/progress-<slug>" origin/main`.
    When the branch already exists, it is added without `-b`;
  - one progress unit there;
  - push;
  - `gh pr create --base main --head progress/<slug>` (ready, not draft);
  - land it through `land_once` steps 0-4 with the id `progress` and
    Branch `progress/<slug>`, with no repair. A refusal leaves the PR open,
    and the report names it (`FINAL_NOTE`).

- [ ] **Step 1: Write the failing tests:**

```sh
test_lanes_final_step_once() {
  lanes_fixture fin integration A:- B:-
  printf 'progress\n' > "$SCEN/progress"     # stub: append a PROGRESS line, commit "docs(progress): demo"
  STUDIO_OVERNIGHT_GATE_CMD="sh -c 'echo gate >> $CALLS/final-gates'" run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_eq 1 "$(wc -l < "$CALLS/final-gates" | tr -d ' ')" "one full gate on the combined head"
  assert_eq 1 "$(grep -c '^pr create --draft --base main --head integration/demo' "$GH/calls")" "one draft PR into main"
  assert_contains "$GH/body-1" "^## A$" "a section per landed story"
  git -C "$P" fetch -q origin
  assert_status 0 "origin/main is merged into the integration head" -- git -C "$P" merge-base --is-ancestor origin/main origin/integration/demo
  assert_eq 1 "$(git -C "$P" log --format=%s origin/integration/demo | grep -c '^docs(progress): demo$')" "one PROGRESS commit"
  # Resume with an unchanged head and the PR open: nothing more.
  run_lanes start "$MFP"
  assert_eq 1 "$(wc -l < "$CALLS/final-gates" | tr -d ' ')" "a resume at an unchanged head runs no gate"
  assert_eq 0 "$(grep -c '^pr edit ' "$GH/calls")" "and edits no PR"
}
test_lanes_final_red_after_repair() {
  lanes_fixture finred integration A:-
  printf 'noop\n' > "$SCEN/final-repair"
  STUDIO_OVERNIGHT_GATE_CMD="sh -c 'echo gate >> $CALLS/final-gates; exit 1'" run_lanes start "$MFP"
  assert_eq 2 "$(wc -l < "$CALLS/final-gates" | tr -d ' ')" "one gate, one repair, one more gate"
  assert_contains "$GH/calls" "^pr create --draft .*--title \[red\] " "a red gate still opens the draft PR, titled [red]"
}
test_lanes_final_skipped_on_stop_or_nothing_landed() {
  lanes_fixture finstop integration A:-
  printf 'stop no\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_not_contains "$GH/calls" "^pr create" "no final PR when no story landed"
}
test_lanes_direct_progress_landing() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}' lanes_fixture dprog direct A:-
  printf 'progress\n' > "$SCEN/progress"
  run_lanes start "$MFP"
  assert_contains "$GH/calls" "^pr create --base main --head progress/demo" "a ready progress PR"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(git -C "$P" log --format=%s origin/main | grep -c '^docs(progress): demo$')" "the progress entry landed on main through the merge command"
}
```

  The fixture writes `docs/game-dev/PROGRESS.md` on `main` and on
  `run/demo`. The stub gh saves each `--body-file` content as
  `$GH/body-<n>`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** the lanes suite, then `sh tests/run_all.sh`.
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh && git commit -m "feat(overnight): integration final step and the direct progress landing"`

---

### Task 12: Per-story `status`, `report.md` and run endings
Role: game-dev:gameplay-programmer
Verify: unit+visual
Files: studios/game-dev/bin/overnight-lanes.sh, studios/game-dev/bin/studio-overnight, tests/overnight_lanes_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L283-292, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L537-553
Review: task

**Risk:** the report contract (the user reads it in the morning). Covers
AC17, AC18, and AC16's report half.

**Interfaces:**
- **Run ending** (`lanes_ending`):
  - `done` when every story is `landed`, and either (integration) the
    final PR is open and green, or (direct) the progress PR landed or
    there is no PROGRESS. Then exit 0 and touch `$RECORD/done`;
  - else `partial: <n> landed, <m> stopped, <k> skipped`, exit 1;
  - else, when a stop was requested, `stopped by user`, exit 1.
  - Bundle 2's runner-error and SIGHUP endings keep working, through
    `on_exit`, which in manifest mode calls `lanes_report`.
- `lanes_status` (the `status` verb when the lock's `run=` dir has
  `manifest.md`). One line per story in manifest order:
  `<id>  lane <k|->  <state>  unit <label|->  task <k/N|->`. The lane comes
  from the claim of its chain, the state from `stories/<id>` (first word),
  the unit from `lanes/<k>/current` when it names this id, and the task
  from `STUDIO_STORY=<id> studio-state get task`. Then
  `gate: <who> (pid <p>)` or `gate: free`, then `spent: $<sum>`, then
  `pid: <runner pid>`. Exit 0. With no run: `no run`, exit 1 (as today).
- `lanes_report` writes `RUN_DIR/report.md` on every ending:
  - the head:
    `# Overnight run — <slug>`, `Ending:`, `Mode:`, `Target:`, `Spent:`,
    `Started: … · Ended: …`;
  - integration: `Final PR: <url> (<green|red>)` or `Final PR: none (<why>)`;
  - direct: `## Landed` with `<id> <sha>` per landed story, and the
    progress PR state;
  - one `## <id>` section per story in manifest order: `Ending:`,
    `Branch:`, `Landed: <sha>` or `Not landed: <why>` (a skipped story
    names its blocking dependency), a units table from
    `lanes/*/units.tsv` rows whose label starts with `<id>-`, and the
    story ledger's `Ruling:` and `P<k> Play:` lines;
  - `## Open bundle-2 PRs`: in integration mode, any open PR whose head is
    a story branch and whose base is `main`, named and never closed;
  - `## Resume`: `cd '<START_DIR>' && '<abs runner>' start <manifest>`
    when not done;
  - `## Cleanup`: one `git push origin --delete …` command naming
    `run/<slug>`, `integration/<slug>` (integration), `progress/<slug>`
    (direct, D12) and every landed story branch, under the line "Run this
    after the final PR is landed; the run itself never deletes a remote
    branch."

**Visual item this task produces:** the user reads one `report.md` from
the live run (P3 on the play list) and judges whether each story's outcome
is clear without opening a log.

- [ ] **Step 1: Write the failing tests:**

```sh
test_lanes_status_per_story() {
  lanes_fixture stat integration A:- B:A C:-
  printf 'sleep 4\n' > "$SCEN/A"
  ( cd "$P" && sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20; sleep 1
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out"; st=$?
  wait "$RPID"
  assert_eq 0 "$st" "status exits 0 during a run"
  assert_eq "A B C" "$(awk 'NR<=3{printf "%s%s", s, $1; s=" "}' "$TMP/st.out")" "stories in manifest order"
  assert_contains "$TMP/st.out" "^A  lane [12]  running  unit A T1  task " "A is running T1"
  assert_contains "$TMP/st.out" "^B  lane -  queued  " "B waits in A's chain"
  assert_contains "$TMP/st.out" "^gate: " "the gate line"
  assert_contains "$TMP/st.out" "^spent: \\$" "the spend line"
}
test_lanes_report_every_ending() {
  lanes_fixture rep integration A:- B:A C:-
  printf 'stop broke\n' > "$SCEN/A"
  run_lanes start "$MFP"
  R="$(last_lanes_dir)/report.md"
  assert_contains "$R" "^Ending: partial: 1 landed, 1 stopped, 1 skipped$" "the partial ending counts each kind"
  assert_contains "$R" "^Mode: integration$" "mode"
  assert_contains "$R" "^## A$" "a section per story"
  assert_contains "$R" "Not landed: skipped — waits on A" "a skipped story names its blocker"
  assert_contains "$R" "^## Resume$" "resume when not done"
  assert_contains "$R" "start docs/runs/demo.md$" "the resume command names the manifest"
  assert_contains "$R" "^## Cleanup$" "cleanup section"
  assert_contains "$R" "git push origin --delete run/demo integration/demo C-b" "cleanup names run, integration and landed story branches"
}
test_lanes_report_on_lane_crash() {
  lanes_fixture repcrash integration A:-
  printf 'hang\n' > "$SCEN/A"
  ( cd "$P" && sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  kill -9 "$(cat "$P"/.studio/reports/overnight-demo-*/claims/1/pid)"; pkill -9 -f "$TMP/fakebin/claude" 2>/dev/null
  wait_pid_or_fail "$RPID" 60 "the runner ends"
  assert_contains "$(last_lanes_dir)/report.md" "Not landed: stopped: lane crashed (" "the report names a lane crash"
}
test_lanes_done_marker() {
  lanes_fixture donem integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "done exits 0"
  assert_file "$P/.studio/runs/demo/done" "done writes runs/<slug>/done"
}
```

  (The C-b cleanup case runs C in its own lane to `landed`, and A's chain
  stops. The fixture has no PROGRESS, so `done` needs only the landings
  and the final PR.)
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the interfaces above. `status` dispatch: when
  the lock's run dir holds `manifest.md`, source the lanes file and call
  `lanes_status`; otherwise run bundle 2's status.
- [ ] **Step 4: Run** the lanes suite, `sh tests/overnight_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/overnight-lanes.sh studios/game-dev/bin/studio-overnight tests/overnight_lanes_test.sh && git commit -m "feat(overnight): per-story status, report.md with cleanup, run endings"`

---

### Task 13: `start --detach`, `--help`, and the README
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-overnight, tests/overnight_lanes_test.sh, README.md
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L741-746, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L194-204, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L141-157
Review: task

**Risk:** a process seam. It needs T1 (D1a) and T12. Covers AC1's
environment half.

**Interfaces:**
- `studio-overnight start --detach <manifest>`:
  1. Run the full preflight in the foreground. A refusal prints there and
     exits 2.
  2. Compute the names to strip:
     `env | sed -n 's/^\(CLAUDECODE\|CLAUDE_CODE_[A-Za-z0-9_]*\|OMEGA_[A-Za-z0-9_]*\|STUDIO_[A-Za-z0-9_]*\)=.*/\1/p'`.
     BSD sed has no `\|` in a basic regex: use `sed -nE` with `|`.
  3. Re-exec itself as
     `nohup <D1a's setsid launcher> env -u N1 -u N2 … sh "$SELF_ABS" start <manifest> </dev/null >"$RUN_LOG" 2>&1 &`.
     `RUN_LOG` is `$REPORTS/overnight-<slug>-detached-<ts>.log`, and the
     child later links it as `RUN_DIR/runner.log`. When D1a failed,
     `--detach` refuses with
     `--detach is not available on this machine — run the printed command`.
  4. Poll `studio-overnight status` for up to 10 s. Exit 0 printing
     `detached: pid <p>, log <path>` once it exits 0. Otherwise exit 1
     printing the plain command.
- `--help` states both modes and what each may and may not merge, plus
  `next`, the gate lock, the new config keys, the test hooks
  (`STUDIO_OVERNIGHT_POLL_SECONDS`, `STUDIO_OVERNIGHT_LAND_HOOK`,
  `STUDIO_OVERNIGHT_GATE_CMD`), and where `report.md` lands.
- README: the `studio-overnight` row and section gain `start <manifest>`,
  `next`, the two run modes (one line of consequence each), and the gate
  lock.

- [ ] **Step 1: Write the failing tests:**

```sh
test_lanes_detach_strips_env() {
  lanes_fixture det integration A:-
  st=0
  ( cd "$P" && env CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=x OMEGA_AUTOPILOT=1 STUDIO_STORY=Z STUDIO_X=1 \
      sh "$RUNNER" start --detach "$MFP" ) > "$TMP/det.out" 2>&1 || st=$?
  assert_eq 0 "$st" "detach reports success once status answers"
  assert_contains "$TMP/det.out" "^detached: pid [0-9]*, log " "it prints the pid and the log"
  wait_for "[ -f '$P/.studio/runs/demo/done' ]" 60
  # The stub session records its full env: none of the chat's variables arrive.
  assert_not_contains "$CALLS/1.fullenv" "^CLAUDECODE=" "CLAUDECODE stripped"
  assert_not_contains "$CALLS/1.fullenv" "^CLAUDE_CODE_ENTRYPOINT=" "CLAUDE_CODE_* stripped"
  assert_not_contains "$CALLS/1.fullenv" "^STUDIO_X=" "STUDIO_* stripped"
  assert_contains "$CALLS/1.fullenv" "^STUDIO_STORY=A$" "the runner's own STUDIO_STORY is set fresh"
}
test_lanes_detach_refusal_in_foreground() {
  lanes_fixture detr direct A:-                        # direct without merge_command
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/detr.out" 2>&1 || st=$?
  assert_eq 2 "$st" "preflight runs in the foreground"
  assert_contains "$TMP/detr.out" "merge_command" "and its refusal is shown"
}
test_lanes_help_modes() {
  sh "$RUNNER" --help > "$TMP/help"
  for t in "integration" "direct" "next" "gate lock" "max_lanes" "merge_command" "STUDIO_OVERNIGHT_POLL_SECONDS"; do
    assert_contains "$TMP/help" "$t" "help names $t"
  done
  assert_contains "$REPO_ROOT/README.md" "studio-overnight start <manifest>" "README documents manifest runs"
  assert_contains "$REPO_ROOT/README.md" "studio-overnight next" "README documents next"
}
```

  The stub session gains `env > "$CALLS/<n>.fullenv"`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the interfaces above and the README text.
- [ ] **Step 4: Run** the lanes suite, then `sh tests/run_all.sh`.
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/studio-overnight tests/overnight_lanes_test.sh README.md && git commit -m "feat(overnight): start --detach, help for both modes, README"`

---

### Task 14: Execute under a lane — §0 isolation, §4 `Review:`, §5/§7 per mode, §8 `studio-brief`
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/skills/execute/SKILL.md, tests/studio_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L778-798, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L407-410, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L641-650, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L667-671, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L251-275, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L302-309
Review: task

**Risk:** cross-system. The runner's stub sessions act out this text, and
real sessions follow it. It needs T3. Covers AC11, AC12's §8 half, AC13's
reviewer half, AC14's execute half, AC22 (execute) and AC23.

"Under a lane" means `STUDIO_STORY` and `STUDIO_RUN` are both set. Every
change below is inside an "Under a lane" paragraph, so the single-plan and
attended text stays as written (one line moves, in §6).

**Edits (each a short, self-contained paragraph):**
- **§0, under a lane, replaces the clean-tree check and isolation:**
  - the check is
    `git status --porcelain -- <spec> <plan> .studio/ledger/<id>.md .studio/config.json`;
  - `git fetch origin` and `git fetch origin run/<slug>`, each retried
    three times on `could not lock` or `cannot lock ref` (1, 2 and 4 s);
  - Target, Branch and slug are read from `$STUDIO_RUN` (header and row);
  - **branch exists** (local or `origin/<Branch>`, D10): enter its worktree
    (`studio-state worktree`, else
    `git worktree add --no-track [-b <Branch>] <path> <Branch or origin/<Branch>>`).
    Then sync the docs (D3):
    `git checkout $STUDIO_DOCS_REV -- <spec> <plan>`, and only when
    `git diff --cached --quiet` fails, commit
    `docs(<id>): plan at run docs <short sha>`. The ledger is never
    touched;
  - **new branch:**
    `git worktree add --no-track -b <Branch> <STATE_ROOT>/.claude/worktrees/<Branch with / → -> origin/<Target>`,
    `EnterWorktree path:`,
    `git checkout $STUDIO_DOCS_REV -- <spec> <plan> .studio/ledger/<id>.md`,
    commit `docs(<id>): approved plan`;
  - then `studio-state set branch <Branch>` and
    `studio-state ledger "base origin/<Target>"`. Every `git merge-base` in
    §4a, §5 and §7 uses `origin/<Target>` after a fetch, and the bare
    `<Target>` is used only for `gh pr create --base`;
  - a `studio-test` call can wait for the gate lock: the session's Bash
    timeout is raised by the runner (D1b). When D1b failed, the text says
    to run `studio-test` in the background and wait for its notification.
- **§4:** a task whose heading block has `Review: final` gets no per-task
  review; its findings fold into §5. A task with `Review: task`, or with
  no `Review:` line, is reviewed as today, and the reviewer is dispatched
  with `model: "opus"`.
- **§5 step 1, under a lane:** skipped (no fresh `studio-test` or
  `studio-lint`). The implementers ran the tests per task, and the finish
  gate covers the fix wave.
- **§6:** "merging is never done" becomes "no session merges anything in
  any run mode: nothing is merged into `main` (the default branch) by a
  session; under a lane the runner lands the story".
- **§7, under a lane:**
  - the base is `origin/<Target>`;
  - integration: step 1 runs once (the story's one test run, D17's lock
    through `studio-test`); step 3 (PROGRESS) is skipped; push, and open
    no PR; `studio-state ledger "shipped <Branch>"`;
  - direct: step 1 is skipped (the merge command is the gate); step 3 is
    skipped; open a **draft** PR into the default branch;
    `shipped <url>`;
  - then `stage idle` and `task -` as today.
- **§8, under `--one`:**
  - the orchestrator reads only `studio-brief task <n>` (a task unit) or
    `studio-brief final` (the final review), plus the files its
    implementer or reviewer reports name;
  - it never reads the plan or the spec whole, and never runs SDD's
    pre-flight conflict scan (the plan session ran it, and its rulings are
    in `## Decisions`);
  - the task brief and the per-task reviewer brief are built from that
    output.

- [ ] **Step 1: Write the failing contract test** `test_execute_lanes` in
  `tests/studio_test.sh`:

```sh
test_execute_lanes() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" 'git status --porcelain -- <spec> <plan> .studio/ledger/<id>.md .studio/config.json' "§0 under a lane checks only the story's ledger"
  assert_contains "$E" 'git worktree add --no-track -b <Branch>' "§0 creates the story branch with --no-track"
  assert_contains "$E" 'git checkout $STUDIO_DOCS_REV -- <spec> <plan> .studio/ledger/<id>.md' "a new branch takes docs and ledger from the docs revision"
  assert_contains "$E" 'docs(<id>): plan at run docs' "an existing branch syncs spec and plan, never the ledger"
  assert_contains "$E" 'base origin/<Target>' "the base is recorded as the remote target"
  assert_contains "$E" 'could not lock' "git lock retries"
  assert_contains "$E" 'Review: final' "§4 honours Review: final"
  assert_contains "$E" 'model: "opus"' "the per-task reviewer runs on Opus"
  assert_contains "$E" 'Under a lane, §5 step 1 is skipped' "the final review runs no tests under a lane"
  assert_contains "$E" 'shipped <Branch>' "integration ships by branch, no PR"
  assert_contains "$E" 'no session merges anything in any run mode' "§6 names the rule"
  assert_contains "$E" 'studio-brief task <n>' "§8 task inputs"
  assert_contains "$E" 'studio-brief final' "§8 final inputs"
  assert_contains "$E" 'never reads the plan or the spec whole' "§8 forbids whole reads"
}
```

- [ ] **Step 2: Run it and see it fail.** `sh tests/studio_test.sh`.
- [ ] **Step 3: Edit** `execute/SKILL.md` as listed. Keep every existing
  contract string. `sh tests/studio_test.sh` lists them, so run it after
  each section.
- [ ] **Step 4: Run** `sh tests/studio_test.sh`, then `sh tests/run_all.sh`.
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/skills/execute/SKILL.md tests/studio_test.sh && git commit -m "feat(execute): lane isolation, Review: tags, per-mode gates, studio-brief inputs"`

---

### Task 15: Execute §9 `--land` and §10 `--progress`
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/skills/execute/SKILL.md, tests/studio_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L575-585, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L600-604, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L618-626
Review: task

**Risk:** a new seam (the runner launches these two units). It needs T14.
Covers AC7's repair contract and AC9's progress contract.

**Text:**
- **`## 9. Landing repair (--land)`:**
  - preconditions (they replace §0's stage gate): `stage idle`, a
    `shipped` line, and `STUDIO_REPAIR` set. Otherwise `Stop:`;
  - enter the feature checkout through `studio-state worktree`;
  - `git fetch origin`, then `git merge --no-edit origin/<Target>`: merge,
    never rebase (the branch is pushed, and force-push is denied);
  - on a conflict (`STUDIO_REPAIR=conflict`), or with the red log
    (`STUDIO_REPAIR=red:<log path>`, read from that path), dispatch one
    fresh fixer (§5 step 5's owning role) with the conflict or the failing
    output;
  - the story's gate: §7 step 1, up to three runs, through `studio-test`
    (which holds the gate lock);
  - commit `fix(land): <summary>`, push, then
    `studio-state ledger "Repair: <summary>"`, committed and pushed;
  - red after three runs → `Stop: land repair red — <failing line>`;
  - it never merges into the target, and never runs the merge command;
  - one unit: end the turn.
- **`## 10. Run progress (--progress)`:**
  - cwd is the final or progress worktree, with `STUDIO_RUN` set and no
    `STUDIO_STORY`;
  - one `game-dev:producer` dispatch, briefed with the manifest at
    `$STUDIO_RUN`, and, for each landed story (`landed.tsv` in
    `<STATE_ROOT>/.studio/runs/<slug>/`), its spec's `## Purpose` and its
    story ledger read with `git show <landed sha>:.studio/ledger/<id>.md`;
  - it writes one PROGRESS entry for the run, commits
    `docs(progress): <slug>`, and ends the turn. It does not push (the
    runner pushes).

- [ ] **Step 1: Write the failing contract test:**

```sh
test_execute_land_and_progress() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" '^## 9. Landing repair (--land)' "§9 exists"
  assert_contains "$E" 'git merge --no-edit origin/<Target>' "the repair merges the target"
  assert_contains "$E" 'never rebase' "and never rebases"
  assert_contains "$E" 'STUDIO_REPAIR=red:<log path>' "a red merge command's log is read"
  assert_contains "$E" 'fix(land): <summary>' "the repair commit"
  assert_contains "$E" 'Repair: <summary>' "the ledger line the runner reads"
  assert_contains "$E" 'never runs the merge command' "the repair never lands"
  assert_contains "$E" '^## 10. Run progress (--progress)' "§10 exists"
  assert_contains "$E" 'docs(progress): <slug>' "one progress commit per run"
}
```

- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Write** §9 and §10, and add `--land` and `--progress` to
  §1's mode list.
- [ ] **Step 4: Run** `sh tests/studio_test.sh`, then `sh tests/run_all.sh`.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/skills/execute/SKILL.md tests/studio_test.sh && git commit -m "feat(execute): --land repair unit and --progress run entry"`

---

### Task 16: Plan and brainstorm — `Story:`, `Spec:`, `Review:`, the sweep, `## Stories`
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/skills/plan/SKILL.md, studios/game-dev/skills/brainstorm/SKILL.md, tests/studio_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L758-768, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L207-216, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L271-275
Review: task

**Risk:** a cross-system contract. It writes the formats that T3's and
T6/T7's parsers read. It needs T7. Covers AC3's skills half and AC14's
plan half.

**Text:**
- **Plan:**
  - invoked with an id (`/game-dev:plan <id>`), the header gains the line
    `Story: <id>`, exactly that, on its own line;
  - every task carries, under its heading beside `Role:`, `Verify:` and
    `Files:`, the line `Spec: <spec>:L<a>-<b>[, <spec>§<heading>…]` and
    the line `Review: task|final`. `task` is for a new seam,
    cross-system, gameplay feel, data or schema, or importer work; `final`
    is for the rest;
  - self-review adds: every task has a `Spec:` line whose ranges exist,
    and a `Review:` line;
  - for a manifest story (`.studio/run` names a manifest that lists the
    id), after approval and in the same session: SDD's pre-flight conflict
    scan, then the question sweep (autopilot's sweep procedure, moved
    here), both written into the plan's `## Decisions`. Then
    `studio-state ledger "Decisions swept <id>"`, a commit, then print
    `/clear`, then the command `studio-overnight next` prints. The plan
    does not print `/game-dev:execute` for a manifest story.
- **Brainstorm:**
  - invoked with an id under an active manifest, it writes one spec for
    the epic with a `## Stories` table
    (`| Story | Acceptance criteria | Depends on |`), with one row per
    manifest story the user puts in the epic;
  - the AC cell holds AC numbers or ranges (`1, 3-5`, D24);
  - it ends with `/clear` and the command `studio-overnight next` prints.

- [ ] **Step 1: Write the failing contract test:**

```sh
test_plan_brainstorm_lanes() {
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  BR="$REPO_ROOT/studios/game-dev/skills/brainstorm/SKILL.md"
  assert_contains "$PL" '^Story: <id>' "plan writes the Story: header for an id"
  assert_contains "$PL" 'Spec: <spec>:L<a>-<b>' "every task cites spec line ranges"
  assert_contains "$PL" 'Review: task|final' "every task carries a Review: tag"
  assert_contains "$PL" 'new seam, cross-system, gameplay feel, data or schema, or importer' "the risk rule for Review: task"
  assert_contains "$PL" 'Decisions swept <id>' "the sweep is ledgered per story"
  assert_contains "$PL" 'studio-overnight next' "plan prints next's command"
  assert_contains "$BR" '| Story | Acceptance criteria | Depends on |' "brainstorm writes the Stories table"
  assert_contains "$BR" 'studio-overnight next' "brainstorm prints next's command"
}
```

- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Edit** both skills.
- [ ] **Step 4: Run** `sh tests/studio_test.sh`, then `sh tests/run_all.sh`.
- [ ] **Step 5: Commit.**
  `git add studios/game-dev/skills/plan/SKILL.md studios/game-dev/skills/brainstorm/SKILL.md tests/studio_test.sh && git commit -m "feat(plan,brainstorm): Story/Spec/Review lines, sweep after approval, Stories table"`

---

### Task 17: Autopilot in a studio — questions, manifest, planning loop, seeding, start
Role: game-dev:gameplay-programmer
Verify: unit
Files: shared/omega/skills/autopilot/SKILL.md, tests/omega_contracts/autopilot_contract.sh, docs/omega/pressure/autopilot.md
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L721-757, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L411-433, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L437-445, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L141-157, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L194-206
Review: task

**Risk:** cross-system. It needs T7, T13 and T16. Covers AC1's skill half,
AC2, AC3's discovery half, AC22 and AC24's seeding half. It also covers
exit criterion 3 as text.

**Text (the "In a studio" section opens the skill; every branch cites it):**
- **Definition:** in a studio means `command -v studio-state` succeeds and
  `studio-state get stage` exits 0. In a studio, no session-mode
  `autopilot` is ever set, no keep-awake is started, and nothing executes
  stories in this session. Work that does not fit stops with a stated
  reason.
- **Phase 1 in a studio,** steps (1)-(5) from spec 727-746, with D11 (the
  run branch at manifest creation) and D16 (re-ledgered lines):
  1. discovery through `.studio/run`. A `runs/<slug>/done` pointer is
     ignored. A new run asks one `AskUserQuestion` with two questions:
     **integration or direct** (each option with its one-line consequence
     from Teaching) and **how many lanes**;
  2. `studio-overnight next <manifest>` drives the planning loop. For a
     `plan` row of an already approved spec, set `STATE.md`
     (`set stage plan`, `set spec`) first. Print `/clear`, then the
     command, and stop;
  3. every row `planned`: seeding per story (not started, or half-done:
     worktree, `git mv` of the ledger and its commit, `check --rebuild`),
     then `reset --keep-ledger`. In integration mode, create
     `integration/<slug>` on origin. Fill the Spec/Plan cells, commit, push
     `run/<slug>`, write `Docs:`, commit, push;
  4. readiness: `studio-overnight start --dry-run <manifest>`;
  5. ask how to start: **autopilot starts it**
     (`studio-overnight start --detach <manifest>`; success only when its
     own `status` check passed) or **print the command** (the absolute
     `cd '<dir>' && '<abs>' start <manifest>`). Either way, say what the
     run may merge in the chosen mode, `status` and `stop`, where
     `report.md` lands, that the chat can close, and to keep the laptop on
     power with the lid open.
- **Does not fit:** a dependency on a later or unlisted row, direct mode
  without `merge_command`, or work that is not story-shaped. The options
  always include "integration mode" and "drop the story". A story without
  a plan is never a stop.
- **Phase 2 merge rule** (AC22): no session merges anything in any run
  mode. In an integration run, nothing is merged into `main`, and the
  runner merges stories into `integration/<slug>`. In a direct run, the
  runner merges into `main` only through `merge_command`. In a single-plan
  run and in session mode, never merge into `main`.
- Removed: the in-session fallback inside a studio, the rule that story PRs
  target the integration branch under autopilot, and the sweep for
  manifest stories (it moved to plan). The single-plan path and its sweep
  stay.
- `docs/omega/pressure/autopilot.md`: the scenario text expects the two
  questions and the manifest. Recorded transcripts stay as written
  (bundle 2's D10).

- [ ] **Step 1: Extend the contract.** In
  `tests/omega_contracts/autopilot_contract.sh`, keep every assertion that
  still holds and replace any whose text this task removes. Add:

```sh
  assert_contains "$S" 'command -v studio-state' "one written definition of in a studio"
  assert_contains "$S" 'studio-state get stage. exits 0' "the definition's second half"
  assert_contains "$S" 'integration or direct' "phase 1 asks the run mode"
  assert_contains "$S" 'how many lanes' "and the lane count"
  assert_contains "$S" 'docs/runs/<slug>.md' "the run manifest"
  assert_contains "$S" '.studio/run' "the pointer"
  assert_contains "$S" 'studio-overnight next' "the planning loop is driven by next"
  assert_contains "$S" 'start --detach' "autopilot can start the run detached"
  assert_contains "$S" 'no session-mode .autopilot. is ever set' "no session mode in a studio"
  assert_contains "$S" 'no keep-awake' "no keep-awake in a studio"
  assert_contains "$S" 'no session merges anything in any run mode' "the merge rule"
  assert_contains "$S" 'nothing is merged into .main.' "the merge rule names main"
  assert_contains "$S" 'drop the story' "does-not-fit options"
  assert_not_contains "$S" 'in-session fallback' "no in-session fallback text remains"
```

  Each branch's citation is checked by counting:
  `assert_eq 1 "$([ "$(grep -c 'in a studio (see' "$S")" -ge 3 ] && echo 1 || echo 0)" "branches cite the definition"`.
  Each studio branch says "in a studio (see *In a studio*)".
- [ ] **Step 2: Run it and see it fail.** `sh tests/omega_test.sh`.
- [ ] **Step 3: Rewrite** the studio parts of the skill. The non-studio
  path stays unchanged except for the merge-rule wording.
- [ ] **Step 4: Run** `sh tests/omega_test.sh`, then `sh tests/run_all.sh`.
- [ ] **Step 5: Commit.**
  `git add shared/omega/skills/autopilot/SKILL.md tests/omega_contracts/autopilot_contract.sh docs/omega/pressure/autopilot.md && git commit -m "feat(autopilot): run manifest, planning loop, seeding and detached start in a studio"`

---

### Task 18: Integration `## Autopilot run` and `repair`; local-merge and `omega-mode brief` wording
Role: game-dev:gameplay-programmer
Verify: unit
Files: shared/omega/skills/integration/SKILL.md, shared/omega/skills/local-merge/SKILL.md, shared/omega/bin/omega-mode, tests/omega_contracts/integration_contract.sh, tests/omega_contracts/local-merge_contract.sh, tests/omega_test.sh
Spec: docs/game-dev/specs/2026-10-01-overnight-lanes.md:L769-777, docs/game-dev/specs/2026-10-01-overnight-lanes.md:L293-305
Review: final

**Risk:** mechanical (text). `repair` is short. Covers AC20 and AC22.

**Text:**
- **Integration:** `## Story flow` stays byte-for-byte unchanged (AC20).
  It gains:
  - `## Autopilot run`: in a studio run, the runner merges stories into
    `integration/<slug>`, runs the final step, and opens the one draft PR
    into `main`. No story PRs are opened, and no session merges;
  - `## repair <slug>`: in the integration worktree, resolve the
    `origin/main` merge, or fix the red gate output, with a fresh fixer,
    then commit. Never push, and never open a PR (the runner does both).
- **local-merge §5:** the autopilot paragraph becomes "When `omega-mode
  show` lists `autopilot`, skip this step: no session merges anything in
  any run mode — nothing is merged into `main` (the default branch); in an
  overnight run the runner lands stories." Then the existing comment and
  report text follows. §3 is unchanged.
- **`omega-mode` brief**, the `source=env` line: replace `never merge` with
  `no session merges anything in any run mode — nothing into main; the
  runner lands`.

- [ ] **Step 1: Write the failing tests:**
  - in `integration_contract.sh`, add
    `assert_contains "$S" '^## Autopilot run' …`,
    `assert_contains "$S" '^## .repair <slug>.' …` and
    `assert_contains "$S" 'Never push' …`. Also pin `## Story flow`
    unchanged: `assert_eq "<sha1 of today's section>" "$(sed -n '/^## Story flow/,/^## /p' "$S" | shasum | cut -c1-40)" "the attended story flow is unchanged"`,
    with the hash computed from the current file before editing;
  - in `local-merge_contract.sh`, add
    `assert_contains "$S" 'no session merges anything in any run mode' …`
    and `assert_contains "$S" 'nothing is merged into .main.' …`;
  - in `tests/omega_test.sh`, `test_mode_env_autopilot`'s expected brief
    line changes to the new text.
- [ ] **Step 2: Run them and see them fail.** `sh tests/omega_test.sh`.
- [ ] **Step 3: Edit** the three files.
- [ ] **Step 4: Run** `sh tests/omega_test.sh`, then `sh tests/run_all.sh`.
- [ ] **Step 5: Commit.**
  `git add shared/omega/skills/integration/SKILL.md shared/omega/skills/local-merge/SKILL.md shared/omega/bin/omega-mode tests/omega_contracts/integration_contract.sh tests/omega_contracts/local-merge_contract.sh tests/omega_test.sh && git commit -m "feat(omega): integration autopilot run and repair; merge rule names main"`

---

## Final gate

1. A standalone final whole-branch review on Opus against the spec and this
   plan, with this plan's Review Focus first and every `Review: final`
   task's diff included.
2. `sh tests/run_all.sh` exits 0 (exit criterion 1).
3. Exit criterion 3, as text:
   `grep -n "omega-mode set autopilot\|caffeinate\|keep-awake" shared/omega/skills/autopilot/SKILL.md`
   shows only the "never" sentences.
4. The PROGRESS entry lands with the story PR (studio memory). The finish's
   producer writes it before the PR.

## Play list (exit criterion 2 — live, needs a human)

Role agents have no Godot MCP and cannot drive a chat (studio memory), so
these are the user's:

- **P1 integration live run.**
  - Do: in a throwaway Godot project, run three stories through
    `/omega:autopilot`: one with no plan (planned through the loop), one
    half-done, and one depending on the first. Mode integration, then
    start.
  - Expect: no human input after the plans are approved; one draft PR from
    integration into `main`; nothing merged into `main`; one full gate;
    every unit's first turn under 90k (from the jsonl files); zero
    `AskUserQuestion` calls and zero permission denials after approval; no
    whole `Read` of a plan or spec in task or final units; one
    `studio-test` per story.
  - Fail looks like: a question in the chat, a merge into `main`, a second
    gate, or a context over the limit.
- **P2 direct live run.**
  - Do: the same three stories with mode direct and phoenix's
    `merge.sh`-style merge command.
  - Expect: each story merged into `main` by the merge command, with the
    dependent story after its dependency; one PROGRESS PR landed.
  - Fail looks like: a story merged out of order, or a session running the
    merge command.
- **P3 morning report.**
  - Do: read one `report.md`.
  - Expect: each story's outcome is clear without opening a log.
  - Fail looks like: you need `runner.log` or a jsonl to know what
    happened.
- **P4 detach survives the chat** (T1 D1a, live).
  - Do: choose "autopilot starts it", then close the chat.
  - Expect: `studio-overnight status` keeps answering, and the run
    finishes.
  - Fail looks like: the run dies with the chat.

## Backlog

Nothing is cut. The producer's scope pass kept T1-T12 and T14-T18 as
needed by the milestone's exit criteria. It proposed T13 for the backlog,
which is overruled by D28 (AC1 and Teaching need it).
