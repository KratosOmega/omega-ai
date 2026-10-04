# Autopilot adopts outside work — Spec

Date: 2026-10-04
Status: Draft (awaiting approval)
Milestone: Plan 3 — Content (studio tooling; follows overnight lanes, #19, the operator channel, #27, and Multica, #28)
Classification: architectural

Issue: #35.

Today `/omega:autopilot` runs only stories that the studio planned itself:
- a spec and a plan written by `/game-dev:brainstorm` and `/game-dev:plan`;
- approval lines in the studio ledger;
- for a half-done story, `T<n> complete` lines in the story's studio ledger.

Work planned and partly built outside the studio, for example with superpowers in regular Claude, has none of these, so the runner's preflight refuses it. This spec lets autopilot **adopt** such a story. It converts the plan into the studio format while keeping the original, takes the finished work from evidence, and sends a story with open gaps into the existing planning loop.

The story branch stays the single source of truth, so the operator can switch between the standard way (regular Claude and superpowers' subagent-driven development) and an overnight run, as often as they like.

## Milestone gate

1. `sh tests/run_all.sh` is green. The existing suites keep every assertion; the new cases are listed in Test strategy.
2. A fixture round trip in a throwaway Godot project:
   - a 6-task story with 3 tasks done the standard way is adopted;
   - an overnight run completes T4;
   - `studio-adopt sync` shows Task 4 complete in the SDD view;
   - a standard-mode T5 is accepted at the next start;
   - that run runs only T6, then the final review and the finish.
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
- Added plan header: `Context:`.

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- Every failure stops in a visible place with the reason and the way out. No step guesses, and none applies part of a change (Architecture → Failure handling).
- A mismatch between the ledger and the branch never auto-repairs. The operator corrects the line or re-adopts the story.

## Teaching

- `studio-adopt --help` gives each verb, its exit codes and an example.
- The autopilot skill's adopt branch explains each step as it runs it.
- The Multica README's Nightly workflow gains "or point autopilot at an existing plan" in step 1.
- `report.md` prints the `studio-adopt sync <story>` command for each adopted story, so the morning summary says how to switch back to the standard way.

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
  - one workspace per plan at `.superpowers/sdd/<plan basename>/`, owned by a `plan-path` marker holding the plan's repo-relative path; a collision adds the parent directory name, then a counter;
  - the progress ledger is `<workspace>/progress.md`, whose first line is `# SDD ledger — plan: <plan path>`, with one `Task <N>: complete (commits <range>, review clean)` line per finished task.
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

1. Phase 1's story-list question also asks each story's **source plan** (a path, or `-` for none) and its source spec (a path, or `-`).
   - A story with source plan `-` is a fresh story, unchanged from today.
2. For each story with a source plan, the session runs the **gap check** and shows the result per story as `adopt` or `plan: <gaps>`. Gaps are:
   - a task without concrete files or acceptance checks;
   - a `TBD`, `TODO`, open question or undecided option;
   - no spec, and the plan's tasks name no authority for their requirements.

   The operator confirms or overrides each story in one `AskUserQuestion` (batched, at most 4 stories per question).
3. A `plan` story:
   - with a source spec, the session approves that spec through `/game-dev:plan`'s existing one-word gate (it records `spec approved <spec>`), then runs `/game-dev:plan <id>` seeded with the original plan as input;
   - without one, it runs `/game-dev:brainstorm <id>` seeded with the original plan.

   Its branch and finished work are kept, and it is seeded as half-done (AC9) once planned.
4. An `adopt` story is **converted**: the session writes a new plan at `docs/game-dev/plans/<date>-<id>.md` and never edits the original. The converted plan has:
   - `Story: <id>`, `Source: <original plan path>`, and `Status: Draft (awaiting approval)`;
   - `## Global Constraints`, carried over from the original;
   - `## Decisions`, gathered from the original's rulings, decisions and any rulings file or handoff it links;
   - tasks **1:1 with the original**: the same count, numbers, titles and boundaries, in the same order, above `## Backlog`.
     - Each task has a `Spec:` line, pointing at the source spec's lines, or at the original plan's task heading (`<original>:<line>`) when there is no spec.
     - Each task has a `Review:` line, set by `/game-dev:plan`'s rule (`task` for a new seam, cross-system work, gameplay feel, data or schema, or importer work; `final` for the rest).
   - an optional `Context:` line (AC15).
5. The session shows the conversion side by side: task count, titles paired 1:1, and what was added. The operator approves it in one word. Then, through `studio-state ledger` in the spec's slug ledger (the file `next` reads):
   - `spec approved <spec>`, where `<spec>` is the source spec, or the original plan when there is none;
   - `plan approved <converted plan>`;
   - `adopted <original plan> -> <converted plan>`;
   - `Decisions swept <id>`, after asking any question the conversion surfaced.

   `next` then classifies the row as `planned`.
6. Git-ignored files the original or its handoff names as required reading (for example SDD carry rules) are listed to the operator. Once confirmed, they are copied to `docs/game-dev/adopted/<id>/`, committed on `run/<slug>`, and named in `Context:`.
7. The session asks once per adopted story: **check the built work?** A yes ledgers `check requested` (AC13).

Evidence and seeding

8. Before conversion, `studio-adopt inspect <id> --branch <Branch> --plan <original> [--base <ref>]` prints the evidence and exits 0 when it is clean. It is read-only. The evidence:
   - the SDD workspace (found by `plan-path`);
   - the finished tasks, each with its verified range;
   - `k/N`;
   - the base;
   - a part-done task (AC11);
   - mismatches.

   A mismatch exits 1, and the session stops adopting that story with inspect's message.
9. At seeding (autopilot step 3, the half-done path), before `studio-state check --rebuild` runs in the story worktree, `studio-adopt seed <id> --plan <original>` runs there. It:
   - writes one `T<n> complete <range>` line per verified finished task into the story branch's `.studio/ledger/<id>.md`;
   - writes the `adopted` line and, when asked for, `check requested`;
   - commits `chore(studio): ledger (adopt)`.

   The existing `check --rebuild` then sets `task k/N`. Running seed a second time adds nothing.

Sync

10. `studio-adopt sync <id>` runs in the story's checkout:
    - **(a) Preconditions:**
      - the checkout is on the story branch;
      - not behind `origin/<Branch>`: fast-forward it when it is behind, and exit 1 when it has diverged;
      - no live run has the story running or held: exit 1 with `story <id> is in a live run — /hold it or wait for it to end`.
    - **(b) Verify the truth:** every `T<n> complete <range>` line in the committed ledger must have
      - its end commit an ancestor of `HEAD`;
      - its range starting after task n-1's end (the end of n-1 is an ancestor of the start of n), or after the `base` for n = 1;
      - numbers running 1..k with no gaps.

      Any failure exits 1, naming the line and the commit.
    - **(c) Accept claims:** read the SDD view's `Task <N>: complete (commits …)` lines.
      - For N ≤ k, the claim's end commit must equal the truth's; a different one is a mismatch.
      - For N > k, claims are taken in order k+1, k+2, … and each must pass (b)'s chain rule. A gap or a failure rejects every new claim, and sync exits 1 without changing the ledger.
      - Accepted claims become `T<n> complete <range>` lines, committed as `chore(studio): ledger (sync)` and pushed.
    - **(d) Regenerate the views:**
      - studio `task k/N` (`check --rebuild`);
      - the SDD view: its identity line naming the **original** plan, then one `Task <n>: complete (commits <range>, review clean)` per truth line. Lines that mention only tasks after k are kept unchanged, in order, after them.
      - once the story has landed (a `shipped` or landed record): the line `Landed: integration/<slug> at <sha> — continue dependent stories from there`.
    - **(e) Report:** the tasks accepted, `k` before and after, the lines kept, or `already in sync`; then exit 0.
11. **Part-done work.** Commits on the branch after the last finished task's end, ignoring merges from the base or `origin/<Target>` and commits that touch only `.studio/`. Inspect and sync report them as `T<k+1> in progress: <first>..<last>`. That is not a mismatch.
12. Sync runs:
    - in autopilot's readiness step, for every adopted story;
    - in an overnight unit, after execute §6 records `T<n> complete`, before the push, for a story whose ledger has an `adopted` line;
    - by the operator, by hand.

Overnight units

13. **Check unit.** A story whose ledger has `check requested` and no `check done` gets a unit labelled `check` before its next task unit:
    - it runs the gates (`studio-test`, and `gate_command` when set);
    - it reviews the finished range (base .. T`k`'s end) against tasks 1..k, with the final-review rubric;
    - it fixes what it finds in that unit, recording each fix as `Ruling:`;
    - it ledgers `check done <range or none>`.

    A problem it cannot fix holds the story, with the reason. `k` never changes in a check unit.
14. **Part-done task.** The brief for T`k+1` of an adopted story says: `commits already on the branch for this task: <first>..<last> — check and finish them; do not start over`.
15. **`Context:`** is a plan header line of comma-separated repo-relative paths.
    - `studio-brief` appends each file, under `## Context files`, to every brief it builds (task, final review, finish, check), up to 12,000 characters in total. Past the cap it lists the remaining paths under `Read these as well:`.
    - The manifest preflight refuses a `Context:` path missing from the `Docs:` revision: `<id>: Context file <path> is not in Docs: <sha>`.

Project hooks

16. **`worktree_setup`** (a string): a command line that the new script `studio-setup` runs from a new story worktree's root.
    - It runs under `studio-gate setup -- sh -c '<command>'`.
    - It is timed by `worktree_setup_minutes` (default 20, range 1–120); a timeout ends the command's process group.
    - Its log goes to `.studio/reports/setup-<stamp>.log`.
    - Execute §0 calls `studio-setup` right after it creates a worktree, including one re-made after loss (exit 3), and never when resuming into an existing worktree.
    - A non-zero exit or a timeout stops the unit with `Stop: worktree setup failed — <command> exit <n> — log <path>`, which holds the story (as any stop rule does).
17. **`gate_command`** (a string): the project's full gate. It runs after the engine gates, under `studio-gate gate -- sh -c '<command>'`, at each story's finish gate and at the run's final integration gate.
    - A non-zero exit counts as a red gate: the existing gate-repair rounds, then a hold.
    - Its times go to `.studio/gate.times`, so the preflight's `session_minutes` check covers it.
    - It adds to the engine gates and replaces none of them.
18. Heavy commands that a converted plan's tasks run (a test-tag run, a store write) are wrapped by the units in `studio-gate <who> -- <cmd>`. The conversion writes this rule into `## Global Constraints`. No new code.

Report and Multica

19. `report.md` gains, for each adopted story: `Adopted from <original plan>. To continue the standard way: cd <checkout> && studio-adopt sync <id>`.
20. The game-dev agent's instructions (`integrations/multica/agent-instructions.md`) gain: `For adopted stories, include the report's studio-adopt sync line in your summary.`
21. No new event types. The check unit is reported through the existing `unit_started` and `unit_ended` events with `label` `check`, and a failed `worktree_setup` through the existing `story_state` `held` with its `why`.

## Architecture

### Before / after

- Before: autopilot runs studio-planned stories only. A half-done story must already carry studio ledger lines. Superpowers' SDD ledger is scratch that the studio rebuilds from its own ledger and never reads.
- After: autopilot adopts outside stories. The studio ledger on the story branch is the one record. Superpowers' SDD ledger becomes a view the studio regenerates, plus the only way standard-mode progress enters the record, through verified claims.

### Source of truth and views

- **Truth:** the story branch, meaning its commits and its committed `.studio/ledger/<id>.md`:
  - `base <ref>`;
  - `T<n> complete <range>`;
  - `adopted <original> -> <converted>`;
  - `check requested`, `check done <range or none>`;
  - the existing lines.
- **Views:** the studio's `task k/N`, and the SDD progress ledger of the **original** plan. Views are regenerated from the truth and never read as truth, except the SDD view's new claims, which pass AC10(c).

### Files

- `studios/game-dev/bin/studio-adopt` (new): `inspect`, `seed`, `sync`.
- `studios/game-dev/bin/studio-setup` (new): runs `worktree_setup`.
- `studios/game-dev/bin/studio-brief`: the `Context:` appendix (AC15).
- `studios/game-dev/bin/overnight-lanes.sh`:
  - the `Context:` preflight refusal;
  - selecting the check unit (AC13);
  - `gate_command` at the final gate;
  - the report line (AC19).
- `studios/game-dev/bin/studio-overnight`: the single-plan counterparts where they apply, and the config keys.
- `studios/game-dev/skills/execute/SKILL.md`:
  - §0 calls `studio-setup`;
  - §6 calls `studio-adopt sync` for adopted stories;
  - the check mode;
  - the part-done brief line;
  - `gate_command` at the finish gate.
- `shared/omega/skills/autopilot/SKILL.md`: the source-plan question, the gap check, conversion, approval, `inspect`, and `seed` inside step 3's half-done path; sync at readiness.
- `integrations/multica/agent-instructions.md`, and the Multica README's Nightly workflow.
- Tests: `tests/studio_adopt_test.sh` and `tests/studio_setup_test.sh` (new), plus additions to `tests/studio_brief_test.sh`, `tests/overnight_lanes_test.sh` and the skill contract tests.

### `studio-adopt`

```
studio-adopt inspect <id> --branch <Branch> --plan <original> [--base <ref>]
studio-adopt seed    <id> --plan <original>          # in the story checkout
studio-adopt sync    <id>                            # in the story checkout
Exit: 0 clean / in sync · 1 a mismatch or a refused precondition (one stderr line naming it) · 2 usage
```

- **Base:**
  1. `--base`, else the ledger's last `base` line;
  2. else the merge-base with `origin/<default>`.
- **Ranges** in claims: the first and last 7–40 hex tokens in the `commits …` text. A single token is both start and end. A claim with no token is a mismatch.
- **Finding the workspace:** the `.superpowers/sdd/*/plan-path` whose content equals the original's repo-relative path. With none, sync creates the workspace by superpowers' rule (`<basename>`, then `<basename>-<parent>`, then a counter) and writes `plan-path`, with `.superpowers/sdd/.gitignore` containing `*`.
- **Atomic writes:** the SDD view is written to a temp file and moved into place. Ledger lines are appended through `studio-state ledger`, and the commit is one commit per sync.

### Failure handling

| Failure | Where | Result |
|---|---|---|
| Source plan has gaps | Gap check | `plan` story → the planning loop |
| Claim ≠ commits; history rewritten; a gap | inspect / sync | Exit 1, naming the line and commit; correct it or re-adopt |
| Branch diverged | sync (a) | Exit 1 |
| Story in a live run | sync (a) | Exit 1: hold it or wait |
| Converted plan fails the preflight | `--dry-run` at readiness | Shown at the desk |
| `Context:` file missing from `Docs:` | Preflight | Refused |
| `worktree_setup` fails or times out | Overnight | `Stop:`, which holds the story |
| `gate_command` red | Finish / final gate | Gate-repair rounds, then held |
| Check unit can't fix a finding | Overnight | Held, with the reason |

### Rejected alternatives

- **Skill-only adoption:** sync exactness (ranges, ordering, forward only) can't rest on prose.
- **Adoption inside the runner:** it puts judgment (conversion) in the unattended part, and breaks approve-before-night.
- **Two ledgers kept in sync by merging:** the dual-write problem. Replaced by one truth with views.
- **Restructuring tasks for studio fit:** breaks the 1:1 mapping that lets either side resume.
- **A new "stack" landing mode:** integration mode ends in the same place (one PR, merged by the operator) and needs no new runner code. It can be added later.

## Tuning knobs

- `worktree_setup_minutes` (default 20).
- The `Context:` cap (12,000 characters).

## Assets and audio

n/a.

## Test strategy

- **`studio-adopt`, against fixture git repos:**
  - a clean chain;
  - a rewritten history (a rebased branch);
  - a claim end ≠ truth;
  - a gap claim;
  - out-of-order claims;
  - all-or-nothing on a bad claim;
  - part-done detection ignoring `.studio/`-only commits and merges;
  - a second seed or sync is a no-op;
  - mid-task lines kept in the view;
  - the landed note;
  - the live-run refusal (a fake registry entry);
  - diverged and behind branches;
  - workspace lookup by `plan-path`, including a collision name.
- **`studio-setup`:** runs under the gate lock; timeout ends the group; non-zero exit; log written; skipped when unset.
- **`studio-brief`:** the `Context:` appendix; the cap; preflight refusal for a missing path.
- **Lanes:** an adopted story seeded at `3/6` runs T4–T6, then the final review and finish; a check unit before T4 when requested, and none after `check done`; `gate_command` at the finish and final gates; the report line.
- **Skill contract tests:** the autopilot adopt branch's steps and phrases (the source-plan question, the gap check, 1:1 conversion, `adopted`, `inspect`, `seed`, sync at readiness); execute's §0 setup call, §6 sync call, check mode and part-done line.
- **The round trip** (Milestone gate 2), as a lanes test with stubbed units.

## Risks

- **Conversion quality.** A converted plan can drop a constraint. The side-by-side view and the operator's approval are the check, and the original stays as the authority behind `Spec:` lines.
- **Unusual SDD ledgers.** Hand-written or odd SDD ledgers may not parse. Inspect refuses them and names the line; it never guesses.
- **Concurrent writers.** Standard-mode work during a live run on the same story is refused only at sync. Nothing stops the operator from committing to the branch meanwhile, and the next sync's chain check catches it.
- **Superpowers changing its workspace rule.** The lookup follows 6.4.1. If the rule changes, sync could write a view that regular Claude doesn't read. Mitigation: the contract test pins the rule, and the README names the version.

## Not doing

- Adoption from the Multica board: it needs approval, and Multica sessions are headless.
- A "stack" landing mode.
- Machine-specific rules in carry files.
- Jira transitions.
- Restructuring adopted plans.
