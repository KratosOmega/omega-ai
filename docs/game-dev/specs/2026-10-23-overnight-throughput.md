# Overnight throughput on the Mac mini: parallel tracks, required tools, machine-tuned caps, checkpoint suites, isolation-safe commands — design

Status: Draft (awaiting operator approval).
Branch: `feat/overnight-throughput`, worktree `../omega-ai-throughput`, off `origin/main` d5183d2.
Issues: none filed yet (the operator decides).
Source: the 2026-10-23 review of autopilot's overnight run (phoenix run `overnight-bat-sonic-rings-20261022-224317`,
the 43 story ledgers, about 22 run manifests, `.studio/gate.times`). The review ranked seven findings. This
design covers ranks 1, 2 (the part #90-#92 does not cover), 5, 6 and 7. Ranks 3 (GUT sharding) and 4 (a counting
gate semaphore) are out of scope.

## Intent

The studio moved from a 4-core Intel i7-7700HQ MacBook to an M6 Mac mini (12 cores, 32 GB). The full phoenix GUT
suite went from a median of 20 min to about 4.5 min. The overnight run did not get faster in proportion, because it
does not use the machine:

- **One lane.** About 20 of 22 runs were one story, or two or three stories chained. KAN-1723 was 58 tasks in one
  6,153-line plan, run one task at a time. A hold stops the only lane, so the machine idles.
- **Environment holds.** 7.4 h of the 16.2 h run were a hold. Two of the run's three holds were environment gaps on
  the new machine: a gh token without `workflow` scope (#90 fixes that) and a missing `ffmpeg`. The same unit also
  had to rebuild a Python 3.9 venv on 3.12.
- **Caps from the old machine.** vitest is held to `--maxWorkers=2` everywhere. Its directory runs took 150-210 s.
  The gate cap is min(60, session_minutes/2), so 60 min for phoenix: 13 times the suite.
- **The full suite runs late.** "The whole suite runs only at the finish" made sense at 20 min. The ledgers hold
  13 `Stop: gate red` lines and 12 gate-repair units. Each one is a breakage that a full suite would have caught at
  the task that caused it.
- **Refused command forms.** In 29 units, Claude Code's worktree isolation refused 170 commands (about 17 min of
  retries). Several of them were forms the execute skill itself prescribes: `bash "$(sdd-script …)"` and
  `git checkout $STUDIO_DOCS_REV -- …`.

The goal is more finished stories per night with the same quality bar. Every gate, reviewer and test that runs today
still runs.

## Goals

1. **Parallel tracks (rank 1).** A big manifest story whose tasks fall into independent tracks is planned as several
   sibling stories that run in their own lanes. A run with one chain says so before it starts, and offers a backfill
   story.
2. **Required tools (rank 2, remainder).** A plan, and a project, can name the tools and minimum versions their tasks
   need. `start`, `--dry-run` and `--detach` refuse a run whose machine lacks one, before any unit launches.
3. **Caps tuned to the machine (rank 5).** vitest worker counts and the gate run cap come from the machine and its
   measured history, not from constants set for the old laptop. On a 4-core machine the result is today's values.
4. **Checkpoint suite (rank 6).** While the suite is cheap, a lane runs the full suite every K completed tasks, and
   repairs a red checkpoint before the next task builds on it.
5. **Isolation-safe forms (rank 7).** No command a skill prescribes is refused by worktree isolation, and every
   brief tells subagents which shell forms the isolation refuses.

## Non-goals

- GUT sharding (rank 3) and replacing the single gate lock with a counting semaphore (rank 4).
- The push gaps #90, #91 and #92 (branch `fix/overnight-push-gaps`, another session's work).
- Cucumber `--parallel`, which is phoenix's own `npm run test:functional`, not this repository. It is a follow-up
  for phoenix (a story the studio itself can run).
- Task-level parallelism inside one story. The `task k/N` pointer stays a counter.

## Anti-goals (failure even if it works)

- Any weaker gate: a skipped reviewer, a skipped finish gate, fewer tests, or a red suite that ships.
- A change in behaviour on a slow machine that nobody asked for. On the old 4-core laptop with phoenix's measured
  times, every new automatic value works out to today's value, or is off. An automatic value comes from the
  machine's core count or from the project's own measured `gate.times`, never from a constant tuned for one
  machine. A project whose suite is fast gets the faster behaviour on any machine, because it measured it.
- A split that makes two parallel stories edit the same file, or one story use an interface another story is still
  building.
- A new way for a run to hold overnight on something the preflight could have checked.

## Constraints

- POSIX sh. Everything passes under macOS `/bin/sh` (bash 3.2) and dash, with `LC_COLLATE=C` as the scripts already
  set.
- Every new config key is listed in `studio-overnight --help`'s Config block with its default and range, and is
  checked the way `cfg` checks the others: a value out of range or not a number is a refusal.
- Skill wording is pinned by the existing contract and pointer tests (`tests/omega_contracts/`,
  `tests/pointer_skills_*`, `tests/studio_test.sh`). Every wording change updates its pin.
- `tests/run_all.sh` stays green. The PR merges only after every active overnight run has ended, followed by a
  reinstall, because a live run reads the plugin while it runs.
- Rebase onto `main` once the push-gaps PR (#90-#92) lands, before implementing. Conflicts are expected in
  `studio-overnight`'s `preflight()` and in execute §7 and §8.

## Part A — Parallel tracks (rank 1)

### A1. Task dependencies in the plan: `After:`

A plan task may carry `After: T<a>[, T<b>…]` beside `Role:`, `Verify:`, `Files:`, `Spec:` and `Review:`. It names the
earlier tasks whose code, data or interface this task needs. Shared files are not listed there; A2 finds those
itself.

- `studio-brief validate` checks it: every named task exists above `## Backlog` and comes before this one. A forward
  or unknown reference fails the plan, naming the line.
- `/game-dev:plan` §2 documents the line. For a manifest story, §7's SDD pre-flight conflict scan (files two tasks
  both write, an interface one task assumes another changes) moves to §6, before `studio-brief tracks` runs. It
  writes each interface finding as an `After:` line, as well as recording it in `## Decisions`. Then the split sees
  every known dependency. §7 keeps the question sweep. Designer's call: the reviewer found that §7 runs after
  approval, which would be too late for the split.
- A cross-sibling dependency found after a split (by §7's sweep, or by a later review) is never written as `After:`,
  which `validate` would refuse. It becomes a manifest Depends on between the two siblings: the later sibling
  depends on the earlier one. That serializes them, which is safe.
- A plan without `After:` lines stays valid: its tracks then come from shared files alone.

### A2. `studio-brief tracks <plan>`

A new read-only subcommand. It takes the tasks above `## Backlog` and joins two tasks when they share a `Files:`
path, or when either names the other on `After:`. It prints the connected components, smallest task number first:

```
tracks: 2
track 1: T1 T2 T5 T6 — 4 tasks — files: scripts/a.gd, tests/unit/test_a.gd, …
track 2: T3 T4 T7 — 3 tasks — files: web-tools/tuning/x.js, …
```

It exits 0, or 2 for a missing plan or bad usage. Same input, same output: the order is deterministic.

### A3. The split at the plan gate (manifest stories only)

Run in `/game-dev:plan` §6, before the approval stop, only when `.studio/run` names a manifest that lists this
story.

1. Run `studio-brief tracks <plan>`. Propose a split when it prints at least two tracks with at least 3 tasks each.
   Fold tracks smaller than that into the track they share an acceptance criterion with, or into track 1.
2. Every acceptance criterion is assigned to the track whose tasks implement it. The planner judges this from the
   tasks' `Spec:` citations and their text; it is not computed.
   - A **feature AC** that tasks in two tracks both implement ties those tracks: they become one track. Two stories
     that each own half of one feature are never produced.
   - A **cross-cutting AC** that no single task implements and that holds for the whole change goes to **every**
     sibling, and does not tie tracks. Examples: "the suite is green", "no regressions", "a PROGRESS entry".
   - The original's `## Stories` row is narrowed to track 1's ACs, and each sibling gets its own row. When the spec
     has no `## Stories` table, the split creates one with every sibling's row, since `studio-brief final` reads it
     (`studio-brief:440`). Designer's call.
3. The approval stop gains one line and one more reply:
   `Plan at <path>: N tasks, K cut to backlog. Splits into S stories that run in parallel: <id> (T…), <id>-2 (T…), ….
   Reply **approve** (split), **approve one** (keep one story), or name the task to change.`
   `approve one` keeps today's behaviour exactly.
4. On **approve**, the plan session, in the run worktree:
   - Track 1 keeps the story's id, branch and plan file. Each other track `k` gets id `<id>-<k>`, checked with
     `studio-overnight check-id`. A taken id takes the suggestion check-id prints. It also gets branch `<Branch>-<k>`
     and plan file `<plan stem>-<k>.md`.
   - Each plan holds its own track's tasks, renumbered 1..m in their original order, titles kept, `After:`
     references renumbered. It has its own `Story:` line, and the same header, Global Constraints and
     `## Decisions` as the original. Its Acceptance criteria are its track's ACs. Tasks of other tracks are not
     listed, and no backlog task is duplicated: the backlog stays with track 1.
   - The manifest gains one row per new story, directly after the original. Ticket and Spec are the same as the
     original's. Depends on is the original's own Depends on: siblings do not depend on each other. A later row
     that depended on the original now depends on the original and every sibling.
   - The spec's `## Stories` table gains the rows, with each story's AC numbers.
   - The spec-slug ledger records `plan approved <plan>` for every plan. §7's sweep then runs once for the whole
     split: the questions are asked once, and each plan's `## Decisions` gets the answers. `Decisions swept <id>` is
     recorded for every id.
   - Each new id gets `STUDIO_STORY=<id> studio-state init`. Everything is committed on `run/<slug>` in one
     `docs(plans): approve <topic> (split S)` commit.
5. `studio-overnight next` then classifies every new row `planned`. Autopilot step 3's overlap check (from #89)
   runs over the siblings like any other parallel pair. If the split worked, it finds no overlap.

### A4. One chain warns, and backfill is offered

- **One lane in effect** means that at most one story can run at a time: the run has one chain, or
  `max_lanes` is 1, or it is a single-plan run. Chains that only wait on each other are not analysed: the chain count
  and `max_lanes` decide. Designer's call.
- In that case `studio-overnight start`, `--dry-run` and `--detach` print one line (stdout, never a refusal):
  `one lane: a hold idles this run until you answer; add an independent story to keep the machine busy`.
- Autopilot offers the backfill **in step 3, before the first seed**, after the overlap check. The check uses the
  same rule over the manifest rows, so nothing is seeded twice and `Docs:` is written once. The offer is one
  `AskUserQuestion`: **add a backfill story** returns to step 1's story list for one new row with Depends on `-`,
  then the planning loop for that row only, then step 3 again from the top for all rows; **run as is** goes on.
  Step 3's seeding already writes each row once per pass, and a half-done row's `task` is never reset. Designer's
  call: the reviewer found that step 5 comes after seeding and the `Docs:` commit.

## Part B — Required tools (rank 2, remainder)

### B1. What declares a requirement

- A plan header line `Requires: <item>[, <item>…]`. `/game-dev:plan` §2: list every executable a task runs that is
  not `sh`, `git`, `gh`, a studio verb or the engine binary, with a minimum version when the plan relies on a newer
  feature (`python3>=3.10` for `int | None`).
- A project-wide `.studio/config.json` top-level key `"requires": ["ffmpeg", "python3>=3.10"]`, for tools every
  story of the project needs. It is read from the main checkout's config (`STATE_ROOT`), as `max_sessions` is.
- An item is `<name>` or `<name>>=<X.Y[.Z]>`. `<name>` matches `^[A-Za-z0-9._/+-]+$`. A name with a `/` is a path
  relative to the worktree root (`.venv/bin/python>=3.10`).
- `studio-brief validate` checks the header's syntax. The preflight checks the config key's syntax and refuses a bad
  item: `config requires: bad item <item>`.

### B2. The check

`preflight()` runs it in every mode, over the project's list plus each plan's (single-plan: the plan; manifest: every
row's plan):

- A bare name: `command -v <name>`, under the PATH the sessions will have (the runner's PATH, which the shim built).
- A version: `<name> --version` with a 10 s cap, stdout and stderr together. The first `[0-9]+\.[0-9]+(\.[0-9]+)?`
  token is the version, compared numerically field by field.
- A path item: when `worktree_setup` is configured, `start` and `--detach` check it in the preflight's scratch
  worktree after the setup has run there, because that is what a new story worktree will look like. Both do so in
  the foreground, before anything detaches, so a refusal is seen at once. `--dry-run` never runs the setup
  (`studio-overnight:2007-2010`). It checks path items in the start checkout and prints
  `requires <item>: checked in the start checkout; start re-checks it after worktree_setup`. Without
  `worktree_setup`, every mode checks the start checkout. Designer's call.
- Refusals, through `refuse` (exit 2), one line per miss, naming the source:
  `requires ffmpeg (plan docs/game-dev/plans/x.md): not on PATH` ·
  `requires python3>=3.10 (config): found 3.9.6`.
  A version that cannot be parsed is a warning, not a refusal: `requires python3>=3.10: cannot read a version from
  'python3 --version' — check it by hand`.
- Each pass prints one stdout line beside `env_line`: `requires: ffmpeg 7.1, python3 3.12.7`.
- Autopilot's readiness checklist names the check inside its `--dry-run` line. There is no new checklist line.

## Part C — Caps tuned to the machine (rank 5)

### C1. `studio-vitest` and `studio-tsc`

Two new verbs in `studios/game-dev/bin/`, so no skill writes `cd <node dir> && studio-gate …` again:

- `studio-vitest [--dir <node dir>] [-t <pattern>] [<file or dir>…]`. It changes into the node dir inside the
  script, then execs `studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=<W> <args…>`.
  - **W is 2** when there is at least one positional and every positional is an existing file, of any number. Such
    a run stays short-lane eligible exactly as today, by `gate-class.sh`'s unchanged whitelist, which puts no limit
    on the file count (`gate-class.sh:105-118`). Any test file list is classed today as it is.
  - **Otherwise W is `node_workers`**: any directory, or no positional (the whole suite). Such a run is already
    exclusive in the main lane today, so more workers slow no one else.
- `studio-tsc [--dir <node dir>]` execs `studio-gate tsc -- npx tsc --noEmit` from the node dir.
- The node dir is `--dir`, else `.studio/config.json` `node_dir`, else `.` when it holds `package.json`. Otherwise
  exit 2 with `studio-vitest: no node dir — set node_dir in .studio/config.json or pass --dir`. The verbs pass the
  gate's exit codes through (124 included).
- **`node_workers`**: a top-level `.studio/config.json` key, an integer 1-32 or `"auto"` (the default).
  `auto` = max(2, physical cores / 2), from the same core probe the gate's load check already uses
  (`gate-class.sh`). That is 2 on the old 4-core laptop (today's value) and 6 on the mini.
- The plan skill §2, the execute briefs (§2) and autopilot's adopt rule (step 1a.4) write `studio-vitest <file>…` and
  `studio-tsc` in place of the `cd … && studio-gate …` forms. The runner's allow list (`overnight-allow.txt`) gains
  both verbs. The old forms keep working.

### C2. A learned gate run cap

Today a gate-routed command in a runner session is capped at `STUDIO_GATE_MINUTES` = min(60, session_minutes/2). On
the mini, a hung suite then burns up to an hour before the gate kills it.

- `studio-gate` learns a per-`who` cap. When `STUDIO_GATE_MINUTES` is set (runner sessions only; interactive use is
  unchanged), and `gate.times` holds at least 5 rows for this `who` with rc 0 in the `main` lane: cap =
  clamp(ceil(F × p95 hold / 60), 15, STUDIO_GATE_MINUTES) minutes. F is `overnight.gate_cap_factor`.
- **`gate_cap_factor`**: `overnight` key, integer 0-10, default 4; 0 turns the learned cap off. With phoenix's
  current numbers that is about 20 min for `studio-test` (p95 about 290 s). `functional` has only 2 rc-0 rows, so it
  keeps today's cap until it has 5.
- The 15 min floor covers a first import (24-130 s on phoenix) and any cold-cache run. The short slot's own 5-min cap
  is unchanged. `setup` is never capped, as today.
- When the learned cap fires, the 124 message names it: `gate: <who> ran past its learned cap of N min (F × p95 of
  the last M runs) — stopped`. Execute's handling of exit 124 is unchanged.
- The preflight prints the learned caps it would apply, and names each `who` still on the default:
  `gate caps: studio-test 20 min (×4 p95); default 60 min for functional, vitest (fewer than 5 runs)`.

## Part D — Checkpoint suite (rank 6)

### D1. When it runs

- **`suite_every`**: `overnight` key, integer 0-20 or `"auto"` (the default). `auto` = 4 when the median hold of the
  last 10 rc-0 `studio-test` rows in `gate.times` is at most 8 min, else 0 (off). Fewer than 3 such rows also gives
  0. The runner resolves the value once at start, prints `suite checkpoint: every 4 tasks (median suite 4.5 min)`
  (or `off — …`), and exports `STUDIO_SUITE_EVERY` into every **manifest** story's launch env.
  On the old laptop (median 20 min) auto is off.
- **Manifest runs only.** A single-plan run has no gate-repair loop (`studio-overnight:1757-1820`; `gate_repairs` is
  lanes-only, `:446`), so a red checkpoint there would be a new way to hold. The runner never sets
  `STUDIO_SUITE_EVERY` for a single-plan run, and the preflight prints `suite checkpoint: off — single-plan run`.
  Designer's call: the reviewer found the single-plan path has no repair.
- In a task unit (execute §8, `--one`), after the task is complete and its §6 writes are committed: when
  `STUDIO_SUITE_EVERY` = K > 0, the task's `Verify:` has no `suite`, and the story ledger holds at least K
  `T<n> complete` lines since its last `suite green` line (or since its `base` line), the unit runs `studio-test` in
  the foreground, as §0 says the gate runs.
- Every whole-suite run that a task already makes (`Verify: suite`) records the same line when green, so it also
  resets the count: `studio-state ledger "suite green T<n> <full sha>"`.

### D2. A red checkpoint

1. One fresh fixer, with §4a rule 2's brief, the failing tests' output, and the range since the last `suite green`
   line. Its role is this task's `Role:`. It commits `fix(suite): <summary>`.
2. It verifies with `studio-test --file` on the failing files, up to two rounds.
3. Then `studio-test` once more. Green: `suite green T<n> <sha>`, commit, push, end the unit.
4. Still red: `studio-state ledger "Stop: gate red — checkpoint after T<n> — <failing line>"`, committed as stops
   are. The runner's existing gate-repair loop takes it. `story_gate_loop` matches `stop: gate red — `, and §11's
   preconditions (stage execute, no shipped line, the latest Stop is gate red) hold in the middle of a story. The
   repair counts against the same `gate_repairs` budget. After the repair, `story_units` resumes at the next task
   (`task` already counts this one).
5. The task stays complete throughout: its own tests passed and it was reviewed. A checkpoint never re-opens it.

- §5 step 2's verify-prior-fixes pattern gains `suite`: `fix\((T[0-9]+|final|gate|review|suite|B[0-9]+)\)`. The final
  reviewer checks that each checkpoint fix closed its failure.
- The finish gate is unchanged: it still runs the whole gate once.
- The builder confirms `story_units` and `gate_repair` behave as described in the middle of a story with an
  `overnight_lanes_test.sh` fixture. If they do not, the runner change that makes them do so is part of this work.

## Part E — Isolation-safe command forms (rank 7)

Claude Code's worktree isolation refuses, in an isolated session's Bash call (measured, 170 refusals):

- a compound command (`;`, `|`, `&&`) that runs git;
- `$(…)` or a variable that feeds git, or a `bash` that runs computed text;
- `cd` to a computed directory before git;
- an unquoted variable where a command option may stand.

### E1. Verbs for the forms the skills prescribe

- `sdd-run [--skill <skill>] <name> [args…]`: resolves the script exactly as `sdd-script` does, then
  `exec bash <script> args…`. Every `bash "$(sdd-script …)" …` in the skills becomes `sdd-run … …`. `sdd-script`
  stays.
- `studio-docs-sync [--new] [<extra path>…]`: execute §0's docs sync. It reads `STUDIO_DOCS_REV`, the spec and plan
  from `studio-state`, and the plan's `Context:` header. Then it runs
  `git checkout <rev> -- <spec> <plan> [<ledger> with --new] <Context paths> <extra>` and commits only when something
  is staged: `docs(<id>): plan at run docs <short sha>`, or with `--new` `docs(<id>): approved plan`. It exits 1
  with git's message on a failure, and 2 on usage or a missing `STUDIO_DOCS_REV`. Execute §0's four
  `git checkout $STUDIO_DOCS_REV -- …` forms become this verb.
- `studio-state ledger "adopt-base $(git rev-parse HEAD)"` and every other `$(…)`-inside-a-git-or-ledger form the
  skills prescribe becomes two calls (read the value, then write it), or a verb flag where one exists.
- **Compound git forms.** Every `git add … && git commit …` (and any other `&&`, `;` or `|` chain with git) that the
  execute, plan, autopilot, review, playtest and retro skills prescribe becomes separate calls, written as numbered
  steps: run `git add …`, then run `git commit …`. Execute alone has them at lines 236, 552, 662, 810, 858 and 983.
  The meaning is unchanged: a failed `git add` stops before the commit, as `&&` did. The builder lists each rewrite
  in the PR, and every pin these rewrites break is updated. Designer's call: Goal 5 covers them, so they are in
  scope.

### E2. The shell-form rule in every brief

Execute §2 adds this line, verbatim, to every implementer, fixer and reviewer brief under a lane, and §0 applies it
to the orchestrator:

> Worktree isolation refuses some shell forms. Run git as one plain command per Bash call. Never `cd <dir> &&`
> before a command: the shell starts in the worktree, so use `git -C`, `npm --prefix`, or a verb's `--dir`. No
> `$(…)` or `$VAR` in a git command: write the value. Write and edit files with the Write and Edit tools, not
> heredocs or inline scripts.

### E3. A guard against regressions

A contract test fails when a skill or agent file under `studios/` or `shared/omega/` prescribes
`bash "$(sdd-script`, `git checkout $STUDIO_DOCS_REV`, `cd <node dir> && studio-gate`, or a backticked command that
chains `git` with `&&`, `;` or `|`.

## What is left to the builder

- Task order and file layout. Each new verb is its own script with a header comment in the house style.
- The exact `cfg` plumbing for the new keys, and how `"auto"` is parsed beside the integer range.
- Which existing test suite each test lives in.
- How `studio-brief tracks` normalizes `Files:` paths (the same as `validate` does for `Spec:`).

## Calls the designer made (for the operator to check)

1. The split happens at the **plan gate**, not in brainstorm or autopilot's story list, because tracks are only
   visible once tasks and files exist. `approve one` keeps today's single story.
2. Siblings share the spec and the ticket. Their ids are `<id>-<k>`, branches `<Branch>-<k>`, plans
   `<stem>-<k>.md`.
3. An AC that two tracks both implement merges those tracks. Correctness wins over parallelism.
4. The minimum track size for a split is 3 tasks. It is not a config key.
5. Backfill is an offer in autopilot step 3, before seeding, never automatic. "One lane in effect" is one chain,
   `max_lanes` 1, or a single-plan run.
6. `requires` checks refuse a missing tool or one too old. An unreadable version only warns.
7. `node_workers` auto is max(2, physical cores / 2). The short-lane whitelist does not change.
8. The learned gate cap is factor 4, floor 15 min, runner sessions only.
9. `suite_every` auto is every 4 tasks when the median suite is at most 8 min, **in manifest runs only**. A red
   checkpoint gets one inline fix and then the existing gate-repair loop, sharing its budget.
10. Cucumber `--parallel` is a phoenix follow-up, not in this repository.
11. For a manifest story, the conflict scan moves from plan §7 to §6, before the split. A cross-sibling dependency
    found later becomes a manifest Depends on.
12. A cross-cutting AC goes to every sibling. Only a feature AC ties tracks.
13. Every compound git command the skills prescribe is split into separate calls (Part E).

## Acceptance criteria

1. `studio-brief validate` fails a plan whose `After:` names a later or unknown task, and passes one without
   `After:` lines.
2. `studio-brief tracks` on a fixture plan with two file-disjoint groups prints `tracks: 2` and both groups. One
   `After:` across the groups prints `tracks: 1`. The output is identical on a second run.
3. The plan skill text holds the split step, the `approve` / `approve one` replies, the AC-tie rule and the sibling
   naming. Pinned by a contract test.
4. A manifest fixture whose story was split into `<id>` and `<id>-2`: `studio-overnight next` classifies both
   `planned`, and `--dry-run` shows two chains.
5. `--dry-run` prints the `one lane:` line, and still exits 0, for a one-chain manifest, for a two-chain manifest
   with `max_lanes` 1, and for a single-plan run. A two-chain manifest with `max_lanes` 0 does not print it.
6. The autopilot skill offers **add a backfill story** in step 3, before the first seed, under the same rule. Pinned.
7. A plan with `Requires: nosuchtool-xyz` makes `start`, `--dry-run` and `--detach` exit 2 naming the tool and the
   plan. No unit or run dir is created.
8. `Requires: sh>=999` refuses with the found version. A stub tool whose `--version` prints no number warns and
   passes. A config `requires` item behaves the same, naming `(config)`. A bad item is a refusal.
9. With `worktree_setup` configured, `start` checks a path item in the scratch worktree after setup. `--dry-run`
   checks it in the start checkout and prints the re-check note.
10. `studio-vitest a.test.ts`, and the same with five files, run the gate with `--maxWorkers=2` and are classed
    `short` by `studio-gate --classify`. `studio-vitest tests/dir` and a bare `studio-vitest` run with
    `--maxWorkers=<node_workers>` and are exclusive.
    A missing node dir exits 2 with the message.
11. `node_workers: "auto"` gives 2 on a stubbed 4-core machine and 6 on a stubbed 12-core one. An out-of-range value
    is a refusal.
12. With 5 or more rc-0 rows of `who` X in `gate.times` and `STUDIO_GATE_MINUTES` set, the gate's cap is
    clamp(ceil(4 × p95 / 60), 15, STUDIO_GATE_MINUTES). A run past it exits 124 with the learned-cap message. With
    fewer rows, or `gate_cap_factor` 0, or no `STUDIO_GATE_MINUTES`, behaviour is today's.
13. `suite_every: "auto"` resolves to 4 with a fixture median of 4.5 min and to 0 with 20 min, and the preflight
    prints the line. `STUDIO_SUITE_EVERY` is in a lane story's launch env, and never in a single-plan run's.
14. The execute skill text holds the checkpoint rule, the `suite green` line, the red-checkpoint steps, the
    `fix(suite)` pattern and the `Stop: gate red — checkpoint after T<n>` form. Pinned.
15. A lane fixture whose task unit writes `Stop: gate red — checkpoint after T2 — …` at task 2/4 runs one gate-repair
    unit, then a task unit for T3 (not T2 again), and never a finish in between.
16. `sdd-run review-package <args>` runs the same script `sdd-script review-package` names, with the arguments.
    `studio-docs-sync` commits only when something changed, and `--new` adds the ledger.
17. The regression contract (E3) finds none of the refused forms in `studios/` or `shared/omega/`, compound git
    chains included, and the E2 sentence is in execute §2. Pinned.
18. `studio-overnight --help` lists `suite_every`, `gate_cap_factor`, and the top-level `node_workers`, `node_dir`
    and `requires`. `tests/run_all.sh` is green, and `docs/game-dev/PROGRESS.md` has the entry.
19. The plan skill runs the conflict scan in §6 before `studio-brief tracks` for a manifest story, and a dependency
    across siblings found later becomes a manifest Depends on. Pinned.
