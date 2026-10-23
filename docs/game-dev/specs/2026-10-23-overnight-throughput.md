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
- A change in behaviour on a slow machine that nobody asked for. Every new automatic value works out to today's
  value on the old 4-core laptop, or is off.
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
- `/game-dev:plan` §2 documents the line. §7's SDD pre-flight conflict scan ("an interface one task assumes another
  changes") writes each such finding as an `After:` line, as well as recording it in `## Decisions`.
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
2. Every acceptance criterion is assigned to the track whose tasks implement it. An AC that tasks in two tracks both
   implement ties those tracks together: they become one track. Two stories that each own half of one AC are never
   produced.
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

- `studio-overnight start`, `--dry-run` and `--detach` print one line (stdout, never a refusal) when the run has
  exactly one chain: `chains: 1 — a hold idles this run until you answer; add an independent story to keep the
  machine busy`.
- Autopilot step 5 ("Ask how to start"): when `--dry-run` printed that line, the start question gains a third option
  ahead of the two existing ones, **add a backfill story**. It returns to step 1's story list and adds one row with
  Depends on `-`, then runs the planning loop for that row only. The two start options are unchanged.

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
- A path item: when `worktree_setup` is configured, it is checked in the preflight's scratch worktree after the setup
  has run there, because that is what a new story worktree will look like. Otherwise it is checked in the start
  checkout. If the setup preflight cannot hold a check, the builder moves this one to a second scratch step and says
  so in the PR.
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
  - **W is 2** when every positional is an existing file (at most 3), so the run stays short-lane eligible exactly as
    today, by `gate-class.sh`'s unchanged whitelist.
  - **Otherwise W is `node_workers`**: a directory, more than three files, or the whole suite. Such a run is
    exclusive in the main lane, so more workers slow no one else.
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
  numbers that is about 20 min for `studio-test` (p95 about 290 s) and about 32 min for `functional`.
- The 15 min floor covers a first import (24-130 s on phoenix) and any cold-cache run. The short slot's own 5-min cap
  is unchanged. `setup` is never capped, as today.
- When the learned cap fires, the 124 message names it: `gate: <who> ran past its learned cap of N min (F × p95 of
  the last M runs) — stopped`. Execute's handling of exit 124 is unchanged.
- The preflight prints the learned caps it would apply: `gate caps: studio-test 20 min, functional 32 min (×4 p95)`.

## Part D — Checkpoint suite (rank 6)

### D1. When it runs

- **`suite_every`**: `overnight` key, integer 0-20 or `"auto"` (the default). `auto` = 4 when the median hold of the
  last 10 rc-0 `studio-test` rows in `gate.times` is at most 8 min, else 0 (off). Fewer than 3 such rows also gives
  0. The runner resolves the value once at start, prints `suite checkpoint: every 4 tasks (median suite 4.5 min)`
  (or `off — …`), and exports `STUDIO_SUITE_EVERY` into every story's launch env, single-plan included.
  On the old laptop (median 20 min) auto is off.
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
  skills prescribe becomes two calls (read the value, then write it), or a verb flag where one exists. The builder
  lists each rewrite in the PR.

### E2. The shell-form rule in every brief

Execute §2 adds this line, verbatim, to every implementer, fixer and reviewer brief under a lane, and §0 applies it
to the orchestrator:

> Worktree isolation refuses some shell forms. Run git as one plain command per Bash call. Never `cd <dir> &&`
> before a command: the shell starts in the worktree, so use `git -C`, `npm --prefix`, or a verb's `--dir`. No
> `$(…)` or `$VAR` in a git command: write the value. Write and edit files with the Write and Edit tools, not
> heredocs or inline scripts.

### E3. A guard against regressions

A contract test fails when a skill or agent file under `studios/` or `shared/omega/` prescribes
`bash "$(sdd-script`, `git checkout $STUDIO_DOCS_REV`, or `cd <node dir> && studio-gate`.

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
5. Backfill is an offer at start, never automatic.
6. `requires` checks refuse a missing tool or one too old. An unreadable version only warns.
7. `node_workers` auto is max(2, physical cores / 2). The short-lane whitelist does not change.
8. The learned gate cap is factor 4, floor 15 min, runner sessions only.
9. `suite_every` auto is every 4 tasks when the median suite is at most 8 min. A red checkpoint gets one inline fix
   and then the existing gate-repair loop, sharing its budget.
10. Cucumber `--parallel` is a phoenix follow-up, not in this repository.

## Acceptance criteria

1. `studio-brief validate` fails a plan whose `After:` names a later or unknown task, and passes one without
   `After:` lines.
2. `studio-brief tracks` on a fixture plan with two file-disjoint groups prints `tracks: 2` and both groups. One
   `After:` across the groups prints `tracks: 1`. The output is identical on a second run.
3. The plan skill text holds the split step, the `approve` / `approve one` replies, the AC-tie rule and the sibling
   naming. Pinned by a contract test.
4. A manifest fixture whose story was split into `<id>` and `<id>-2`: `studio-overnight next` classifies both
   `planned`, and `--dry-run` shows two chains.
5. A one-chain manifest's `--dry-run` prints the `chains: 1` line and still exits 0. A two-chain manifest does not
   print it.
6. The autopilot skill offers **add a backfill story** when that line was printed. Pinned.
7. A plan with `Requires: nosuchtool-xyz` makes `start`, `--dry-run` and `--detach` exit 2 naming the tool and the
   plan. No unit or run dir is created.
8. `Requires: sh>=999` refuses with the found version. A stub tool whose `--version` prints no number warns and
   passes. A config `requires` item behaves the same, naming `(config)`. A bad item is a refusal.
9. With `worktree_setup` configured, a path item is checked in the scratch worktree after setup.
10. `studio-vitest a.test.ts` runs the gate with `--maxWorkers=2` and is classed `short` by
    `studio-gate --classify`. `studio-vitest tests/dir` runs with `--maxWorkers=<node_workers>` and is exclusive.
    A missing node dir exits 2 with the message.
11. `node_workers: "auto"` gives 2 on a stubbed 4-core machine and 6 on a stubbed 12-core one. An out-of-range value
    is a refusal.
12. With 5 or more rc-0 rows of `who` X in `gate.times` and `STUDIO_GATE_MINUTES` set, the gate's cap is
    clamp(ceil(4 × p95 / 60), 15, STUDIO_GATE_MINUTES). A run past it exits 124 with the learned-cap message. With
    fewer rows, or `gate_cap_factor` 0, or no `STUDIO_GATE_MINUTES`, behaviour is today's.
13. `suite_every: "auto"` resolves to 4 with a fixture median of 4.5 min and to 0 with 20 min, and the preflight
    prints the line. `STUDIO_SUITE_EVERY` is in a lane story's launch env.
14. The execute skill text holds the checkpoint rule, the `suite green` line, the red-checkpoint steps, the
    `fix(suite)` pattern and the `Stop: gate red — checkpoint after T<n>` form. Pinned.
15. A lane fixture whose task unit writes `Stop: gate red — checkpoint after T2 — …` at task 2/4 runs one gate-repair
    unit, then a task unit for T3 (not T2 again), and never a finish in between.
16. `sdd-run review-package <args>` runs the same script `sdd-script review-package` names, with the arguments.
    `studio-docs-sync` commits only when something changed, and `--new` adds the ledger.
17. The regression contract (E3) finds none of the refused forms in `studios/` or `shared/omega/`, and the E2
    sentence is in execute §2. Pinned.
18. `studio-overnight --help` lists `suite_every`, `gate_cap_factor`, and the top-level `node_workers`, `node_dir`
    and `requires`. `tests/run_all.sh` is green, and `docs/game-dev/PROGRESS.md` has the entry.
