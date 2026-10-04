# Autopilot adopts outside work — Spec

Date: 2026-10-04
Status: Approved (operator, 2026-10-04; spec falsifier findings folded in)
Milestone: Plan 3 — Content (studio tooling; follows overnight lanes, #19, the operator channel, #27, and Multica, #28)
Classification: architectural

Issue: #35.

Today `/omega:autopilot` runs only stories that the studio planned itself:
- a spec and a plan written by `/game-dev:brainstorm` and `/game-dev:plan`;
- approval lines in the studio ledger;
- for a half-done story, `T<n> complete` lines in the story's studio ledger.

Work planned and partly built outside the studio, for example with superpowers in regular Claude, has none of these, so the runner's preflight refuses it. This spec lets autopilot **adopt** such a story. It converts the plan into the studio format while keeping the original, takes the finished work from evidence, and sends a story with open gaps into the existing planning loop.

The story branch stays the single source of truth, so the operator can switch between the standard way (regular Claude and superpowers' subagent-driven development, SDD) and an overnight run, as often as they like.

## Milestone gate

1. `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh` are green. The existing suites keep every assertion; the new cases are listed in Test strategy.
2. A fixture round trip, as a lanes test with stubbed units:
   - a 6-task story with 3 tasks done the standard way (an SDD ledger for the original plan) is adopted and seeded at `3/6`;
   - a run completes T4, and a stub unit then writes `Stop:` so the run ends with the story held;
   - `studio-adopt sync` by hand shows Task 4 complete in the original plan's SDD view;
   - a standard-mode T5 is added as one commit plus an SDD claim;
   - the next run's first unit (execute §0's sync) accepts T5, and that run runs only T6, then the final review and the finish.
3. Live, on a real epic that was planned outside the studio (the operator runs the steps that need their machine):
   - a fully planned, not-started story is adopted, passes `--dry-run`, is started from a Multica issue assigned to the game-dev agent, and lands on `integration/<slug>`;
   - a story stopped mid-task is adopted and resumes its part-done task from the commits already on its branch.

## Purpose

- Run any story overnight, whoever planned it, without re-planning work whose decisions are already made.
- Keep the standard way usable on the same story: progress made overnight is visible to the standard way, and progress made the standard way is visible to the next night.
- Send a story with open questions to the existing planning loop instead of guessing.

## Core-loop delta

n/a — studio tooling, no game loop.

## Player verbs

- Added: `studio-adopt inspect|seed|sync <story> [options]` (Architecture).
- Changed: `/omega:autopilot` phase 1 asks each story's **source plan** and gains the adopt branch (AC1–AC9).
- Added config: `worktree_setup`, `worktree_setup_minutes` and `gate_command` in `.studio/config.json`.
- Added plan header: `Context:`. Added plan section for converted plans: `## Acceptance criteria`.

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- Every failure stops in a visible place with the reason and the way out. No step guesses, and none applies part of a change (Architecture → Failure handling).
- A mismatch between the ledger and the branch never auto-repairs. The operator corrects the line, or re-adopts with `studio-adopt seed --reset` after a history rewrite.

## Teaching

- `studio-adopt --help` gives each verb, its exit codes and an example.
- The autopilot skill's adopt branch explains each step as it runs it.
- The Multica README's Nightly workflow gains "or point autopilot at an existing plan" in step 1.
- `report.md` prints, for each adopted story, how to switch back to the standard way (AC22).

## Input and platform

macOS and Linux, POSIX `sh`, as the runner today. No new dependencies.

## Feel targets

- Adopting one fully planned story takes the operator a few minutes: one sorting confirmation, one approval, one built-work answer.
- `studio-adopt inspect` and `sync` finish in seconds on a branch with hundreds of commits.

## References

- `2026-10-01-overnight-lanes.md`: manifests, chains, the planning loop (`next`), and seeding half-done stories (autopilot phase 1 step 3).
- `2026-10-03-overnight-operator-channel.md`: holds and events (schema v1, `docs/game-dev/overnight-events.md`).
- `2026-10-03-multica-integration.md`: the bridge mirrors events; unit `label` and held `why` are free text.
- superpowers 6.4.1 `subagent-driven-development/scripts/sdd-workspace`:
  - one workspace per plan at `<worktree root>/.superpowers/sdd/<plan basename>/`, git-ignored, owned by a `plan-path` marker holding the plan's repo-relative path; a collision adds the parent directory name, then a counter; SDD deletes it after a clean final review;
  - the progress ledger is `<workspace>/progress.md`, whose first line is `# SDD ledger — plan: <plan path>`, with one `Task <N>: complete (commits <range>, review clean)` line per finished task, where the range is `<HEAD before the task>..<HEAD after>`.
- Brainstorm rulings, 2026-10-04 (operator):
  - keep both plans;
  - the built-work check is asked per story;
  - the autopilot session converts;
  - hooks are in scope;
  - both views are written, with automatic sync at start;
  - tasks stay 1:1, with commit cross-checks;
  - integration mode lands adopted stories as is;
  - the story branch is the single source of truth (plan, then apply; reconcile; never auto-repair).

## Acceptance criteria

Autopilot: sorting and conversion

1. Phase 1's story-list question also asks each story's **source plan** (a path, or `-` for none) and its **source spec** (a path, or `-`).
   - A story with source plan `-` is a fresh story, unchanged from today.
   - A path must be repo-relative, normalized (no `./`, no `..`) and tracked (`git ls-files --error-unmatch`); otherwise the answer is refused and asked again.
   - For each story with a source plan, the session ledgers `source <plan> spec <spec or ->` into `.studio/ledger/<id>.md` (with `STUDIO_STORY=<id>`), committed on `run/<slug>` with the manifest. These facts survive `/clear` and step 3.
2. For each story with a source plan, the session runs `studio-adopt inspect` (AC8), then the **gap check**, and shows the result per story as `adopt` or `plan: <gaps>`. Gaps are:
   - a task without concrete files or acceptance checks;
   - a `TBD`, `TODO`, open question or undecided option;
   - no spec, and the plan's tasks name no authority for their requirements;
   - no acceptance criteria can be gathered from the source spec or the tasks' acceptance checks (the final review needs them, AC4).

   The operator confirms or overrides each story in one `AskUserQuestion` (batched, at most 4 stories per question). The verdict is ledgered as `verdict adopt` or `verdict plan` into `<id>.md`.
3. A `plan` story:
   - with a source spec, the session approves that spec through `/game-dev:plan`'s existing one-word gate (it records `spec approved <spec>` and sets the source spec's `Status:`, a tracked repo doc, committed on `run/<slug>`), then runs `/game-dev:plan <id>` seeded with the original plan and inspect's output;
   - without one, it runs `/game-dev:brainstorm <id>` seeded with the original plan and inspect's output.

   The seeding tells the planner: tasks 1..k keep the original's titles and boundaries, unchanged and marked finished; planning covers task k+1 onward. Its branch and finished work are kept. Once planned, step 3 ledgers `adopted <original> -> <new plan>` into `<id>.md`, and the story is seeded as half-done (AC9); seed refuses a new plan whose tasks 1..k don't carry the original's titles.
4. An `adopt` story is **converted**: the session writes a new plan at `docs/game-dev/plans/<date>-<id>.md` and never edits the original. The converted plan has:
   - `Story: <id>`, `Source: <original plan path>`, and `Status: Draft (awaiting approval)`;
   - `## Global Constraints`, carried over from the original, plus AC21's `studio-gate` rule;
   - `## Decisions`, gathered from the original's rulings, decisions and any rulings file or handoff it links, plus the rulings on the conflict scan below;
   - `## Acceptance criteria`, gathered from the source spec's acceptance or success criteria, else from the tasks' acceptance checks;
   - tasks **1:1 with the original**: the same count, numbers, titles and boundaries, in the same order, above `## Backlog`.
     - Each task has a `Spec:` line in `studio-brief`'s existing format: `<source spec>:L<a>-<b>` for the spec lines it implements, or, with no spec, `<original>:L<a>-<b>` for the original task's own block (its heading up to the line before the next `### ` heading). The original is never edited, so the range stays valid.
     - Each task has a `Review:` line, set by `/game-dev:plan`'s rule (`task` for a new seam, cross-system work, gameplay feel, data or schema, or importer work; `final` for the rest).
   - an optional `Context:` line (AC18).

   Before showing it, the session runs SDD's pre-flight conflict scan (pairs of tasks sharing a file or an interface) over tasks k+1..N, and checks that every file those tasks modify exists at the story branch tip (or `origin/<default>` for a not-started story). Each finding is ruled with the operator and written to `## Decisions`.
5. The session shows the conversion side by side: task count, titles paired 1:1, what was added, and the conflict-scan rulings. The operator approves it in one word. Then, per story, in this order:
   1. `studio-state set spec <spec>`, where `<spec>` is the source spec, or the original plan when there is none;
   2. the manifest row's Spec and Plan cells are set to `<spec>` and the converted plan, byte-identical to the paths ledgered below;
   3. the converted plan and the manifest are committed on `run/<slug>`, so `next_match` and `Docs:` see the plan;
   4. without `STUDIO_STORY`, into the spec's slug ledger (the file `next` reads): `spec approved <spec>`, `plan approved <converted plan>`, and `Decisions swept <id>` after asking any question the conversion surfaced;
   5. with `STUDIO_STORY=<id>`, into `<id>.md`: `adopted <original> -> <converted plan>`.

   `next` then classifies the row as `planned` from its filled cells.
6. Git-ignored files the original or its handoff names as required reading (for example SDD carry rules) are listed to the operator. Once confirmed, they are copied to `docs/game-dev/adopted/<id>/`, committed on `run/<slug>`, and named in `Context:`.
7. When inspect shows k ≥ 1 or part-done commits, the session asks once per story: **check the built work?** A yes ledgers `check requested` into `<id>.md`.

Evidence and seeding

8. `studio-adopt inspect <id> --branch <Branch> --plan <original> [--base <sha>]` prints the evidence and exits 0 when it is clean. It is read-only and runs from any checkout of the repo. The evidence:
   - the SDD workspaces whose `plan-path` names the original, in every tree of `git worktree list --porcelain`, and the tree each was found in;
   - the finished tasks, each with its verified range (AC10b's rules);
   - `k/N`;
   - the base (Architecture → Base);
   - part-done commits (AC11);
   - mismatches.

   A mismatch exits 1, and the session stops adopting that story with inspect's message. With no branch, the story is not started: `k = 0`, clean. With no workspace and no counted commits past the base, also `k = 0`, clean. With no workspace and counted commits: exit 1, `work on <Branch> past <base7> but no SDD ledger for <plan> in any worktree — restore it, or write one in SDD's format, and inspect again`.
9. At seeding (autopilot step 3, the half-done path, after step 3.2's re-key and before `studio-state check --rebuild`), `studio-adopt seed <id>` runs in the story worktree. It reads the original and the converted plan from `<id>.md`'s `adopted` line (in the start checkout, `$STATE_ROOT`), re-runs inspect's checks, and:
   - checks that the converted plan's tasks 1..k carry the original's titles (exit 1 naming the first that differs);
   - writes, into the story branch's `.studio/ledger/<id>.md`: `source …`, `adopted …`, `adopt-base <full sha>`, one `T<n> complete <full sha>..<full sha>` per verified finished task, the standard-mode rulings and parked findings (AC10f), and `check requested` when ledgered;
   - commits `chore(studio): ledger (adopt)`.

   The existing `check --rebuild` then sets `task k/N`. Running seed a second time adds nothing (each line is written only when absent).

   `studio-adopt seed <id> --reset`, after a history rewrite that inspect reports, appends `adopt reset <HEAD sha>` and then seeds afresh from the current evidence. Every reader of `T<n> complete` and `adopt-base` lines (`studio-adopt`, and `studio-state check` with and without `--rebuild`) ignores those lines when they come before the last `adopt reset` line.

   A not-started adopted story has no seed: execute §0's new-branch path copies `<id>.md` (with its `source`, `adopted` and `check requested` lines) from `Docs:`, then ledgers `adopt-base <HEAD>` right after its `base origin/<Target>` line.

Sync

10. `studio-adopt sync <id>` runs in a checkout of the story branch:
    - **(a) Preconditions:**
      - the checkout is on the story branch;
      - not behind `origin/<Branch>`: fast-forward it when it is behind, and exit 1 when it has diverged;
      - the project's live run (`.studio/overnight.lock`, as `studio-overnight status` reads it) does not have the story running or held: otherwise exit 1 with `story <id> is in a live run — /hold it or wait for it to end`. The run's own unit is exempt: `STUDIO_RUN` is set, `STUDIO_STORY` equals `<id>`, and `STUDIO_RUN_DIR` equals the live run's directory.
    - **(b) Verify the truth.** The truth lines are those after the last `adopt reset`. A `T<n> complete` line's range is its last whitespace-separated token, `<a>..<b>`; each side must resolve to exactly one commit (`git rev-parse --verify --quiet <tok>^{commit}`), so an unknown or ambiguous short sha is a mismatch. For each `n`:
      - `a` is an ancestor of `b`, `a ≠ b`, and `git rev-list --first-parent a..b` holds at least one commit touching a path outside `.studio/`;
      - `b` is an ancestor of `HEAD`;
      - for n > 1, task n-1's `b` is `a` or an ancestor of it; for n = 1, the `adopt-base` sha is `a` or an ancestor of it;
      - numbers run 1..k with no gaps; two lines for one task must resolve to the same range.

      Any failure exits 1, naming the line and the commit. A history rewrite fails here and says `history of <Branch> was rewritten after T<n> — re-adopt: studio-adopt seed <id> --reset`.
    - **(c) Accept claims.** Read the `Task <N>: complete (commits …)` lines of every SDD workspace for the **original** plan, in every tree of `git worktree list --porcelain`. A claim's range is the first and last 7–40 hex tokens in its `commits …` text that each resolve to exactly one commit; a claim with no such token is a mismatch. Workspaces are merged by task number; two different ranges for one task are a mismatch.
      - For N ≤ k, the claim's end must resolve to the truth's end; a different one is a mismatch.
      - For N > k, claims are taken in order k+1, k+2, … and each must pass (b)'s rules. A gap or a failure rejects every new claim, and sync exits 1 without changing the ledger.
      - Accepted claims become `T<n> complete <full sha>..<full sha>` lines, committed as one `chore(studio): ledger (sync)` commit, and `<Branch>` is pushed (with execute §0's git lock retry).
    - **(d) Regenerate the views** in the current tree:
      - studio `task k/N` (`studio-state check --rebuild`);
      - the SDD progress ledgers of the original plan and of the converted plan, each in its workspace (found by `plan-path`, created by superpowers' rule when absent, with `.superpowers/sdd/.gitignore` containing `*`): the identity line naming that plan, then one `Task <n>: complete (commits <a>..<b>, review clean)` per truth task, then every other line the old file had (parked, rulings, fix rounds, and lines for later tasks), in their old order.
    - **(e) Landed note:** when the start checkout's machine-local `.studio/runs/<slug>/landed.tsv` records the story, the original's view gains `Landed: integration/<slug> at <sha> — continue dependent stories from there`. With no such record, no note.
    - **(f) Rulings carried:** each SDD line for a task ≤ k that is a parked finding is ledgered once as `minor (deferred) T<n>: <text> (standard mode)`, and each line with a `Ruling:` as `T<n> Ruling: <text>`, so both final reviews see them (`studio-brief final` reads these lines).
    - **(g) Report:** the tasks accepted, `k` before and after, the lines kept, the trees read, or `already in sync`; then exit 0.
11. **Part-done work** is the commits of `git rev-list --first-parent <T_k end, or adopt-base for k = 0>..HEAD`, leaving out:
    - a merge whose second parent is reachable from `origin/<default>` or `origin/<Target>` (the whole merge is left out);
    - commits touching only `.studio/`;
    - commits touching only the spec, the original plan, the converted plan and the `Context:` paths (the lane's docs syncs);
    - commits inside a `check done <range>`;
    - commits whose subject starts `fix(final`, `fix(gate`, `fix(review` or `docs(progress`.

    For k < N, inspect and sync report them as `T<k+1> in progress: <first>..<last>`; for k = N, as `post-task commits: <first>..<last>`. Neither is a mismatch.
12. Sync runs:
    - in autopilot's readiness step, for every story with an `adopted` line (from the story worktree, or skipped with a note for a not-started story);
    - in every overnight unit of a story whose feature ledger has an `adopted` line, at execute §0 after the worktree is entered and set up (AC19) and before *Where to start* reads `task`. This is the "automatic sync at start": standard-mode progress made since the last unit is picked up whether the run was started by autopilot, by the printed command or from Multica. A sync exit 1 becomes `Stop: adopt sync — <its stderr line>`, written and committed in the feature checkout, which holds the story;
    - by the operator, by hand, before continuing the standard way (the report prints the command, AC22).

Overnight units

13. **Check unit.** A story whose feature ledger has `check requested` and no `check done` gets one unit labelled `check`, before any other unit of the story (so at k = N it runs before `final-review`):
    - it runs the gates (`studio-test`, and `gate_command` when set);
    - it reviews the finished range (`adopt-base`..T`k`'s end) against tasks 1..k with the final-review rubric, from `studio-brief check`;
    - it fixes what it finds in that unit, recording each fix as `check Ruling: <decision> — <why> — <cost if wrong>`;
    - it ledgers `check done <range of its fix commits, or none>`.

    A problem it cannot fix writes `Stop: check — <reason>`, committed in the feature checkout, which holds the story. `k` never changes in a check unit.
14. **Runner support for the check unit** (`studio-overnight`):
    - `snapshot` adds `chk=<count of check done lines>` to `SIG`, so a check unit that ledgers `check done` counts as progress;
    - `label_for` returns `check` when the feature ledger has `check requested` and no `check done`, ahead of its other rules;
    - `model_for check` uses the final-review model (`MODEL_FINAL`);
    - the preflight's `gate_room_check` warning covers the check unit as it covers the finish.
15. **Execute §8 "Which unit"** gains the check case ahead of the task case: `check requested` without `check done` is the check unit. The prompt stays `/game-dev:execute --one`.
16. **Part-done task.** The brief for T`k+1` of an adopted story says: `commits already on the branch for this task: <first>..<last> — check and finish them; do not start over`.
17. **Briefs** (`studio-brief`):
    - `Spec:` items keep today's two formats; AC4 writes only those.
    - `final`: the acceptance criteria come from the spec's `## Acceptance criteria`; when the spec has none, from the state's plan's `## Acceptance criteria`; with neither, it fails as today.
    - a new `check <k>` verb prints tasks 1..k's `Spec:` items (as `task` does), the range `adopt-base`..T`k`'s end, the plan's `## Global Constraints`, `## Decisions` and `## Acceptance criteria`.
18. **`Context:`** is a plan header line of comma-separated repo-relative paths.
    - `studio-brief` appends each file, under `## Context files`, to every brief it builds (`task`, `final`, `check`), up to 12,000 characters in total. Past the cap it lists the remaining paths under `Read these as well:`.
    - Execute §0's lane docs sync checks out `<spec> <plan> <Context paths>` from `$STUDIO_DOCS_REV`, on both the branch-exists and the new-branch paths, so the files are in the story worktree where `studio-brief` reads them.
    - The manifest preflight refuses a `Context:` path missing from the `Docs:` revision: `<id>: Context file <path> is not in Docs: <sha>`.

Project hooks

19. **`worktree_setup`** (a string): a command line that the new script `studio-setup` runs from a worktree's root.
    - It runs under `studio-gate setup -- sh -c '<command>'`, timed by `worktree_setup_minutes` (default 20, range 1–120). The timer starts once the gate lock is held; a timeout ends the command's process group.
    - Its log goes to `.studio/reports/setup-<stamp>.log`.
    - On success it writes the marker `$(git rev-parse --git-dir)/studio-setup.done` holding a hash of the command. `studio-setup` is a no-op when the marker matches, so every entry path can call it: a re-made worktree has a new git dir and no marker, and a changed command runs again.
    - Called from: execute §0 on every entry into a feature checkout (lane and single-plan), after `studio-state set branch` and the `base` line; and the runner's final integration, after it adds the final-gate worktree and the progress worktree.
    - A non-zero exit or a timeout in execute §0 writes `Stop: worktree setup failed — exit <n> — log <path>`, committed in the feature checkout, which holds the story under a lane. In the final integration it counts as a red final gate, with the setup log named.
    - `studio-gate` keeps the last 50 `.studio/gate.times` lines per `who`, so `setup` lines never push out `studio-test` lines.
20. **`gate_command`** (a string): the project's full gate. It runs after `studio-test`, under `studio-gate gate -- sh -c '<command>'`, at each story's finish gate (lane and single-plan), in the check unit, and at the run's final integration gate. Direct mode runs no finish gate today (its merge command is the gate) and does not run it either.
    - Its log goes to `.studio/reports/gate-<stamp>.log`. A non-zero exit is a red gate: `Stop: gate red — gate_command exit <n> — log <path>`.
    - The runner's gate-repair unit gets `STUDIO_REPAIR=gate:<the log the Stop names>`, falling back to the newest `studio-test` log when the Stop names none; execute §11 verifies with the command that failed.
    - What follows a red gate is today's rule for each context: a lane finish gets the gate-repair rounds, then a hold; a single-plan finish gets three `fix(gate)` rounds, then a draft PR; the final integration gets one final-repair, then a red PR.
    - `gate_room_check` sums the slowest of the last 10 `studio-test` entries and the slowest of the last 10 `gate` entries.
    - It adds to the engine gates and replaces none of them.
21. Heavy commands that a converted plan's tasks run (a test-tag run, a store write) are wrapped by the units in `studio-gate <who> -- <cmd>`. The conversion writes this rule into `## Global Constraints`. No new code.

Report and Multica

22. `report.md` gains, for each adopted story:
    - not landed: `Adopted from <original plan>. To continue the standard way: cd <story worktree> && <absolute path>/studio-adopt sync <id>` (the absolute path, as `## Resume` prints it, because regular Claude has no studio `PATH`);
    - landed: `Adopted from <original plan>; landed on integration/<slug> — continue dependent stories from there` (cleanup deletes the landed story branch).
23. The game-dev agent's instructions (`integrations/multica/agent-instructions.md`) gain: `For adopted stories, include the report's studio-adopt line in your summary.`
24. No new event types. The check unit is reported through the existing `unit_started` and `unit_ended` events with `label` `check`; a failed `worktree_setup` or `adopt sync` through the existing `story_state` `held` with its `why`.
25. Execute §6 writes `T<n> complete <full sha>..<full sha>` from now on; existing short-sha lines still parse (AC10b).

## Architecture

### Before / after

- Before: autopilot runs studio-planned stories only. A half-done story must already carry studio ledger lines. Superpowers' SDD ledger is scratch that the studio rebuilds from its own ledger and never reads.
- After: autopilot adopts outside stories. The studio ledger on the story branch is the one record. Superpowers' SDD ledgers become views the studio regenerates, plus the only way standard-mode progress enters the record, through verified claims.

### Source of truth and views

- **Truth:** the story branch, meaning its commits and its committed `.studio/ledger/<id>.md`:
  - `source <plan> spec <spec>`, `verdict adopt|plan`, `adopted <original> -> <converted>`;
  - `adopt-base <sha>`, `adopt reset <sha>`;
  - `T<n> complete <a>..<b>`;
  - `check requested`, `check done <range or none>`;
  - the existing lines (`base <branch>` stays the PR base branch and is never read as a commit).
- **Views:** the studio's `task k/N`, and the SDD progress ledgers of the original and the converted plan. Views are regenerated from the truth and never read as truth, except the original plan's SDD claims, which pass AC10(c).
- **When each side syncs:** the night's first unit of each adopted story syncs (AC12), so the night sees standard-mode work; the operator syncs by hand in the morning (AC22), so the standard way sees the night's work.

### Files

- `studios/game-dev/bin/studio-adopt` (new): `inspect`, `seed`, `sync`.
- `studios/game-dev/bin/studio-setup` (new): runs `worktree_setup`, with the marker.
- `studios/game-dev/bin/studio-brief`: the `final` acceptance-criteria fallback, the `check` verb, the `Context:` appendix.
- `studios/game-dev/bin/studio-state`: `T<n> complete` lines before the last `adopt reset` are ignored by `check` and `check --rebuild`.
- `studios/game-dev/bin/studio-gate`: the `gate.times` window kept per `who`.
- `studios/game-dev/bin/studio-overnight`: `snapshot` and `SIG`, `label_for`, `model_for` (the check unit); `gate_room_check`; the gate-repair log choice; the config keys.
- `studios/game-dev/bin/overnight-lanes.sh`:
  - the `Context:` preflight refusal;
  - `studio-setup` after the final-gate and progress worktree adds;
  - `gate_command` at the final gate;
  - the report lines (AC22).
- `studios/game-dev/skills/execute/SKILL.md`:
  - §0: `studio-setup` on every entry; `studio-adopt sync` for adopted stories; the Context paths in the docs sync; `adopt-base` on the new-branch path;
  - §6: full-sha ranges;
  - §7: `gate_command` at the finish gate;
  - §8: the check case, and the check unit's steps;
  - §11: verifying with the failing command;
  - the part-done brief line.
- `shared/omega/skills/autopilot/SKILL.md`: the source-plan question, the gap check, conversion with the conflict scan, approval, `inspect`, `seed` in step 3's half-done path, `adopted` for `plan` stories in step 3, sync at readiness.
- `integrations/multica/agent-instructions.md`, and the Multica README's Nightly workflow.
- Tests: `tests/studio_adopt_test.sh` and `tests/studio_setup_test.sh` (new), plus additions to `tests/studio_brief_test.sh`, `tests/studio_state_test.sh`, `tests/studio_gate_test.sh`, `tests/overnight_lanes_test.sh`, the single-plan runner tests and the skill contract tests.

### `studio-adopt`

```
studio-adopt inspect <id> --branch <Branch> --plan <original> [--base <sha>]
studio-adopt seed    <id> [--reset]        # in the story checkout
studio-adopt sync    <id>                  # in a checkout of the story branch
Exit: 0 clean / in sync · 1 a mismatch or a refused precondition (one stderr line naming it) · 2 usage
```

- **Base** (inspect and seed): `--base`, else the fork point, the first commit on `<Branch>`'s first-parent chain that is reachable from `origin/<default>`. Seed writes it as `adopt-base <full sha>`; a not-started story gets it from execute §0 (AC9). After that, only the `adopt-base` line is read; `base` lines never are.
- **Ranges:** truth lines by AC10(b), claims by AC10(c). `studio-adopt` writes full shas only.
- **Workspaces:** found by `plan-path` in every tree of `git worktree list --porcelain`; views are written only in the current tree.
- **Atomic writes:** each SDD view is written to a temp file and moved into place. Ledger lines are appended through `studio-state ledger`, and each seed or sync makes at most one commit.

### Failure handling

| Failure | Where | Result |
|---|---|---|
| Source plan has gaps | Gap check | `plan` story → the planning loop |
| Claim ≠ commits; a gap; an empty range | inspect / sync | Exit 1, naming the line and commit; correct it |
| History rewritten | inspect / sync | Exit 1; re-adopt with `seed --reset` |
| Work but no SDD ledger | inspect | Exit 1; restore or write the ledger |
| Re-planned tasks 1..k changed | seed | Exit 1, naming the task |
| Branch diverged | sync (a) | Exit 1 |
| Story in a live run (not its own unit) | sync (a) | Exit 1: hold it or wait |
| Sync fails inside a unit | execute §0 | `Stop: adopt sync`, held |
| Converted plan fails the preflight | `--dry-run` at readiness | Shown at the desk |
| `Context:` file missing from `Docs:` | Preflight | Refused |
| `worktree_setup` fails or times out | execute §0 / final integration | `Stop:`, held / red final gate |
| `gate_command` red | Finish / check / final gate | Today's repair rule for that context |
| Check unit can't fix a finding | Overnight | `Stop: check`, held |

### Rejected alternatives

- **Skill-only adoption:** sync exactness (ranges, ordering, forward only) can't rest on prose.
- **Adoption inside the runner:** it puts judgment (conversion) in the unattended part, and breaks approve-before-night.
- **Two ledgers kept in sync by merging:** the dual-write problem. Replaced by one truth with views.
- **Restructuring tasks for studio fit:** breaks the 1:1 mapping that lets either side resume.
- **A new "stack" landing mode:** integration mode ends in the same place (one PR, merged by the operator) and needs no new runner code. It can be added later.
- **Sync after every task in a unit:** the unit's own lines are already the truth; syncing at the start of each unit (AC12) is enough for the night, and the morning's sync by hand is enough for the standard way.
- **Teaching `next` to read `adopted` lines:** filling the manifest cells (AC5) uses `next` as it is.

## Tuning knobs

- `worktree_setup_minutes` (default 20).
- The `Context:` cap (12,000 characters).

## Assets and audio

n/a.

## Test strategy

- **`studio-adopt`, against fixture git repos:**
  - a clean chain;
  - main merged between T2 and T3 (accepted), and a lane unit's `base origin/<Target>` line present (ignored);
  - a rewritten history (a rebased branch), then `seed --reset`;
  - a claim end ≠ truth; a gap claim; out-of-order claims; an empty-range claim; an ambiguous short sha;
  - all-or-nothing on a bad claim;
  - part-done detection leaving out `.studio/`-only commits, merges from main, docs syncs, check fixes and `fix(final)` commits; `post-task commits` at k = N;
  - a second seed or sync is a no-op;
  - other lines kept in the views; rulings and parked findings carried (AC10f);
  - the landed note from a fixture `landed.tsv`;
  - the live-run refusal (a fake lock and run dir) and the own-unit exemption;
  - diverged and behind branches;
  - workspace lookup by `plan-path` across two worktrees, including a collision name and conflicting claims;
  - no workspace, with and without commits;
  - a re-planned story whose task 2 title changed (seed refuses).
- **`studio-setup`:** runs under the gate lock; timer starts after the lock; timeout ends the group; non-zero exit; log written; marker skip and rerun on a changed command; skipped when unset.
- **`studio-brief`:** the `Context:` appendix and cap; `final` taking the plan's acceptance criteria; the `check` verb; an `<original>:L<a>-<b>` item.
- **`studio-state`:** `check --rebuild` ignores T lines before `adopt reset`.
- **`studio-gate`:** `setup` lines don't push out `studio-test` lines.
- **Lanes:**
  - `next` prints `planned` for an adopted row whose Spec cell is a superpowers spec, and for one whose Spec cell is the original plan;
  - an adopted story seeded at `3/6` runs T4–T6, then the final review and finish;
  - a check unit runs first when requested (label `check`, final-review model, counted as progress), and none after `check done`;
  - a sync exit 1 in a unit and a setup failure each end `held`;
  - `gate_command` at the finish and final gates, and a red `gate_command` handing its own log to gate repair;
  - the `Context:` preflight refusal; the report lines;
  - the round trip (Milestone gate 2).
- **Skill contract tests:** the autopilot adopt branch's steps and phrases (the source-plan question, the gap check, 1:1 conversion, the conflict scan, the AC5 order, `adopted`, `inspect`, `seed`, sync at readiness); execute's §0 setup and sync calls, the Context docs sync, `adopt-base`, §6 full shas, §8 check case and part-done line, §11.

## Risks

- **Conversion quality.** A converted plan can drop a constraint. The side-by-side view and the operator's approval are the check, and the original stays as the authority behind `Spec:` lines.
- **Unusual SDD ledgers.** Hand-written or odd SDD ledgers may not parse. Inspect refuses them and names the line; it never guesses.
- **Concurrent writers.** Standard-mode work during a live run on the same story is refused only at sync. Nothing stops the operator from committing to the branch meanwhile; the next unit's sync catches a diverged branch and holds the story.
- **Superpowers changing its workspace rule.** The lookup follows 6.4.1. If the rule changes, sync could write a view that regular Claude doesn't read. Mitigation: the contract test pins the rule, and the README names the version.
- **The SDD workspace is machine-local scratch.** Claims made on another machine, or deleted by SDD after its final review, can't be read; inspect and sync say so rather than guess.

## Not doing

- Adoption from the Multica board: it needs approval, and Multica sessions are headless.
- A "stack" landing mode.
- Machine-specific rules in carry files.
- Jira transitions.
- Restructuring adopted plans.
