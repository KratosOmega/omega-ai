---
name: plan
description: Use when an approved spec exists and needs an implementation plan — writes role-tagged, verify-tagged tasks, runs the producer scope pass, and waits for approval.
---

# Plan

**Announce at start:** "Using game-dev:plan to write the implementation plan."

## 0. Preconditions

- **Invoked as `<slug>/<id>`, or as `<id>` under a manifest that lists it:**
  run that form's steps first (**`<slug>/<id>` form**, below: `<slug>/<id>`
  enters the run worktree; either way `studio-overnight check-id <id>`),
  before anything here.
- **Default branch:** `git symbolic-ref --short refs/remotes/origin/HEAD`
  without its `origin/`; without one, the first of `main` and `master` that
  exists. The main checkout is the first `worktree` line of
  `git worktree list --porcelain`.
- **Finished-checkout guard** (run it first, before any state write): when
  `studio-state get branch` names a branch (not `-`) that is not the default
  branch and equals `git branch --show-current`, stop with: "This checkout
  holds the previous, finished feature (`<branch>`). Leave it first:
  `ExitWorktree` with `action: "keep"`. When that reports no active worktree
  session, this session was launched here, and neither `ExitWorktree` nor
  `cd` outlasts the `/clear` the chain needs: quit and start `claude-gd` in
  `<main checkout>`. In the main checkout itself:
  `git switch <default branch>`.
  To start the next feature on this branch anyway, run
  `studio-state set branch -` first." Without studio state the guard is
  skipped like every other `studio-state` call.
- In a pointer-less worktree whose `studio-state show` prints the take hint,
  stop with: "the main checkout's story `<spec>` is waiting: continue it in
  `<main checkout>`, or run `studio-state take <spec>` here".
- `studio-state get spec` names a file that exists, and the ledger has a
  `spec approved` line for it. If not, stop and say the spec must be approved
  first (`/game-dev:brainstorm`). The user may approve it now in one word;
  then change the spec's `Status:` line to `Approved`, record
  `studio-state ledger "spec approved <path>"` and continue (the gate in §6
  commits the spec alongside the plan).
- Read the spec in full and the project `CLAUDE.md`. The milestone gate and
  its exit criteria come from `docs/game-dev/PROGRESS.md` when the project has
  one, otherwise from the spec's **Milestone gate** section.

## 1. Architect proposal

Dispatch `game-dev:architect` (`subagent_type: "game-dev:architect"`) with
the spec path, briefed: "Propose a task decomposition: one line per task,
the files it touches, and whether its deliverable is a decision or code."
Its proposal is a starting point, not the final plan — the task list below
is what turns it into tasks, adding, cutting or reshaping as the spec and
milestone gate require.

## 2. Format

Invoke `superpowers:writing-plans` and follow it for the header, file
structure, task structure, bite-sized steps, the no-placeholder rules, and
the self-review. Two studio rules override its defaults:

- Save the plan to `docs/game-dev/plans/YYYY-MM-DD-<topic>.md` in the game
  project, not `docs/superpowers/plans/`.
- Every task carries four lines directly under its heading, beside `Role:`,
  `Verify:` and `Files:`:

  ```markdown
  ### Task 3: Input action and buffer window
  Role: game-dev:gameplay-programmer
  Verify: unit+playtest
  Files: src/player/dash_state.gd, tests/unit/test_dash_input.gd
  Spec: docs/game-dev/specs/2026-10-01-dash.md:L40-52, docs/game-dev/specs/2026-10-01-dash.md§## Feel targets
  Review: task
  ```

  - `Spec: <item>[, <item>…]` cites the spec lines the task implements; items
    are separated by `, `. An item is one of:
    - `<spec>:L<a>-<b>` — lines a to b (`Spec: <spec>:L<a>-<b>`, the usual form);
    - `<spec>:L<a>` — one line, the same as `L<a>-<a>`;
    - `<spec>§<heading>` — a heading line exactly as written in the spec,
      including its `#`s.
    The lines must exist: `studio-brief validate` checks them (§6).
  - `Review: task|final` says whether execute reviews the task by itself.
    `task` is for new seam, cross-system, gameplay feel, data or schema, or importer work; `final` is for the rest, which
    folds into the final review.
  - `After: T<a>[, T<b>…]` is optional and sits beside `Role:`. It names the
    earlier tasks whose code, data or interface this task needs. Do not list
    shared files there; `studio-brief tracks` finds those itself.
    `studio-brief validate` fails a reference to an unknown task, to a task
    below `## Backlog`, or to this task or a later one, naming the line.
  - A step that runs Godot writes the gated form: a script or import run as
    `studio-gate godot -- <Godot command>` (e.g.
    `studio-gate godot -- Godot --headless --path . --script res://tools/x.gd`),
    tests as `studio-test` or `studio-test --file <test file>`, targeted vitest as
    `studio-vitest <file>…` and tsc as `studio-tsc` (each runs from the node dir under the gate),
    the game as `studio-run`. Never a bare Godot script/import run (`-s`, `--script`,
    `--import`): the studio's hook refuses it, and `studio-brief validate`
    fails the plan on it (§6).
- Invoked with an id (`/game-dev:plan <id>`), the plan header gains the line
  below, exactly that, on its own line:

  ```markdown
Story: <id>
  ```

The plan header's **Spec:** line points at the approved spec, and its
**Global Constraints** copy the spec's feel targets and acceptance criteria
verbatim, plus the project's architecture rules from `CLAUDE.md`. The header
also carries a `Status:` line, `Draft (awaiting approval)` until the gate.

## 3. Roles

`Role:` names who implements the task. Use exactly one of:

| Role | Give it |
|------|---------|
| `game-dev:gameplay-programmer` | GDScript logic, state machines, signals, Resources, unit tests |
| `game-dev:level-designer` | level layout, TileMapLayer authoring, pacing |
| `game-dev:tech-artist` | sprites, atlases, import settings, animation frames |
| `game-dev:feel-tuner` | input latency, forgiveness windows, acceleration, animation timing, camera, juice |
| `game-dev:ui-designer` | HUD, menus, themes, responsive layout |
| `game-dev:architect` | a task whose deliverable is a design decision or a refactor of system boundaries |

`game-dev:game-designer`, `game-dev:producer`, `game-dev:playtester` and
`game-dev:reviewer` do not implement tasks and never appear in `Role:`.

## 4. Verify

`Verify:` names how the task's deliverable is checked, and binds the
implementer. It is one kind or several joined with `+` (`unit+playtest`):

- `unit` — a test named in `Files:` is written first and fails before the
  implementation exists (`superpowers:test-driven-development` is
  mandatory). The framework is the project's (`tests` in
  `.studio/config.json`; default GUT); test files go where
  `godot-prompter:godot-testing` says the runner finds them. Use it for
  numbers, state transitions, cooldowns, collisions, signal emission,
  Resource loading.
- `playtest` — the task states, in its own text, the playtest item it will
  produce: the action, the expected perceptual result, and what a failure
  looks like. Use it for snappiness, readability, timing, camera behaviour.
- `visual` — the user looks at it; no automated check. Use it for art
  placement, UI layout, particle look.
- `suite` — the task changes a seam whose effects reach tests it does not touch
  (an autoload, a shared base script, the GUT config or its hooks, project
  settings, an importer's output): the implementer runs the whole suite
  before reporting. Without `suite`, a task's tests are the files it touches;
  the whole suite runs at the finish gate.

A task that introduces or changes a tunable value (a cooldown, a window, a
speed, a curve) always includes `unit`: the number is tested, the feel is
played. A task that mixes deliverables of different kinds is two tasks; a
task with one deliverable checked two ways is one task with two kinds.

## 5. Producer scope pass

Before saving, dispatch `game-dev:producer` (`subagent_type:
"game-dev:producer"`) with the draft plan path, the spec path, and the
milestone gate from `docs/game-dev/PROGRESS.md`. It applies this test to
every task:

1. Does the current milestone gate's exit criteria (from `PROGRESS.md`, or
   the spec's **Milestone gate** section) need this task?
2. Would the feature be playable end to end without it?

It moves every task that fails 1 and passes 2 to a `## Backlog` section at
the end of the plan with a one-line reason, and fills the header line
**Cut in the scope pass:** (or `none`). Read its report; if you disagree
with a cut, restore the task and record why with
`studio-state ledger "Ruling: kept T<n> against producer cut — <why>"`.
Vertical slice first; polish, variants and content wait.

## 6. Self-review, then gate

**Plan-time probes.** When the plan defines a measurement of engine or
tool behaviour, and a later task pins numbers from it or branches on its
result, run it now, before the approval stop:

- Run it in the planning checkout, through the gated forms
  (`studio-gate godot -- <Godot command>`, `studio-test --file <test file>`).
- Put the result in the plan as a measured input: the command and its output.
- Restore any tracked file the probe regenerates, or commit it as an input.
- The execute-time task re-measures and must equal the plan's values (a
  mismatch is a BLOCK); it never discovers them.
- Where the plan models the behaviour, port the engine's own algorithm; do
  not fit a formula.

A probe that cannot run headless at plan time (it needs a window or the
Godot MCP) stays a run task, and the plan states what happens for each
possible outcome.

Run the writing-plans self-review (spec coverage, placeholder scan, name
consistency). Additionally check: every acceptance criterion in the spec maps
to a task; every `Verify: unit` task names a test file; every
`Verify: playtest` task states its playtest item; every task has
a `Spec:` line and a `Review:` line; every plan-time probe has a measured-input block, or is a run task with every outcome stated. Then run `studio-brief validate <plan path>`
and fix the plan until it exits 0: it checks every task's `Spec:` items (the
file, the range, the heading) the way execute's brief will read them. It also fails on a bare Godot script/import run anywhere in the plan, naming the line and the gated form to write.

**Split for parallel lanes (manifest stories only).** Run this only when
`.studio/run` names a manifest that lists this story. Otherwise skip it and
use the plain stop below.

**Conflict scan first.** Before `studio-brief tracks` runs, do SDD's
pre-flight conflict scan: the plan's tasks against each other and against the
code on the default branch, for files two tasks both write, and an interface
one task assumes another changes. Write each finding and its resolution into
the plan's `## Decisions` (add the section after Global Constraints when
absent, `none` when empty). Write each interface finding as an `After:` line
too, so the split sees every known dependency. Re-run `studio-brief validate`
when you add one.

1. Run `studio-brief tracks <plan>`. Read its output: `tracks: <K>`, then one
   `track <k>: T… — <m> tasks — files: …` line per track. Propose a split when
   it prints at least two tracks with at least 3 tasks each. Fold tracks
   smaller than that into the track they share an acceptance criterion with,
   or into track 1. With no such split, skip to the plain stop. That also
   applies when folding leaves one track, and when acceptance criterion ties fold everything into one track.
   `tracks` silently isolates a task with no single-line `Files:`:
   a task shown as `files: -` must get its `Files:` line before a split is proposed.
2. Assign every acceptance criterion to the track whose tasks implement it.
   Judge this from the tasks' `Spec:` citations and their text; it is not
   computed.
   - A **feature AC** that tasks in two tracks both implement ties those tracks:
     they become one track. Never produce two stories that each own
     half of one feature.
   - A **cross-cutting AC** that no single task implements and that holds for
     the whole change goes to **every** sibling, and does not tie tracks.
     Examples: "the suite is green", "no regressions", "a PROGRESS entry".
   - The original's `## Stories` row is narrowed to track 1's ACs, and each
     sibling gets its own row. When the spec has no `## Stories` table, the
     split creates one with every sibling's row, since `studio-brief final`
     reads it.
3. Stop with the split message below instead of the plain one.
4. On **approve**, in the run worktree, in place of the single-plan approval
   below:
   - Track 1 keeps the story's id, branch and plan file. Each other track `k`
     gets id `<id>-<k>`, checked with `studio-overnight check-id`. A taken id
     takes the suggestion check-id prints. It also gets branch `<Branch>-<k>`
     and plan file `<plan stem>-<k>.md`.
   - Each plan holds its own track's tasks, renumbered 1..m in their original
     order, titles kept, `After:` references renumbered. It has its own
     `Story:` line, and the same header, Global Constraints and `## Decisions`
     as the original. Its Acceptance criteria are its track's ACs. Tasks of
     other tracks are not listed, and no backlog task is duplicated: the
     backlog stays with track 1.
   - The manifest gains one row per new story, directly after the original.
     Ticket and Spec are the original's. Depends on is the original's own
     Depends on: siblings do not depend on each other. A later row that
     depended on the original now depends on the original and every sibling.
   - The spec's `## Stories` table gains the rows, with each story's AC
     numbers.
   - Set every plan's `Status:` to `Approved`. Run
     `studio-state ledger "plan approved <plan path>"` for every plan, and
     `STUDIO_STORY=<id> studio-state init` for each new id.
   - §7's sweep runs once for the whole split: ask the questions once, write
     the answers into each plan's `## Decisions`, and record
     `Decisions swept <id>` for every id.
   - Commit everything on `run/<slug>` as one commit, as separate commands:
     `git add` the plans, the spec, the manifest and `.studio/`, then
     `git commit -m "docs(plans): approve <topic> (split <S>)"`, S being the
     number of stories.
5. `studio-overnight next` then classifies every new row `planned`.
   Autopilot step 3's overlap check runs over the siblings like any other
   parallel pair. After a split, §7 items 1-3 are done (the sweep and its
   commit ran in step 4): go to item 4. A second `git commit` with nothing
   staged exits 1, so do not run it and do not stop there.

Then run `studio-state set stage plan`, `studio-state set plan <plan path>`,
`studio-state set task 0/N` (N = number of tasks outside the backlog), and
`studio-state ledger "plan written <plan path>"`. On exit 4 from any of these
state writes: stop and show the message. **Stop** with:

> Plan at `<path>`: N tasks, K cut to backlog. Reply **approve**, or name the
> task to change.

When the split applies (step 3), stop with this instead:

> Plan at `<path>`: N tasks, K cut to backlog. Splits into S stories that run
> in parallel: `<id>` (T…), `<id>-2` (T…), ….
> Reply **approve** (split), **approve one** (keep one story), or name the task to change.

**approve one** keeps one story and takes the plain approval below exactly.

On approval: change the plan's `Status:` line to `Approved`, run
`studio-state ledger "plan approved <plan path>"`, then commit the plan, the
spec and the state that must travel with them into the execution worktree —
`git add <spec path> <plan path> .studio/ledger .studio/config.json`, then, only when it succeeded, `git commit -m "docs(plans): approve <topic>"` (two calls)
(a no-op for an already-committed, unchanged spec; it captures the spec
approved in §0).

**`<slug>/<id>` form.** Invoked as `/game-dev:plan <slug>/<id>`:

1. Find the checkout of `run/<slug>`: `git worktree list --porcelain`, the
   `worktree` whose `branch refs/heads/run/<slug>`.
2. When none holds it, stop with "no checkout holds run/<slug> —
   /omega:autopilot <slug> creates its run worktree".
3. Enter it with execute's **Enter the feature checkout** procedure
   (`EnterWorktree path:`, else `cd`), and check it with
   `git rev-parse --show-toplevel`.
4. Run `studio-overnight check-id <id>` there first (its Plan, Ticket,
   Branch and slug come from the worktree's `.studio/run`). On a non-zero exit, print
   its output and stop, before writing any file or ledger line: another
   story in this project already used the id.
5. Run `studio-state show` after entering and print it.
6. Continue as the `<id>` form under that worktree's `.studio/run`, with
   every file path absolute under it.

Invoked as `<id>` where the current checkout's `.studio/run` names a
manifest that lists it, run the same `studio-overnight check-id <id>` first,
before §0 writes anything. The bare `<id>` form keeps today's meaning in the
current checkout: outside a manifest its ledger is spec-slug keyed, and the
id is not checked.

**Not a manifest story** (no `.studio/run`, or its manifest does not list the
id): print `Next: run /clear, then /game-dev:execute` (subagent-driven by
default; `--inline` for checkpointed execution in this session). Do not
invoke it yourself.

## 7. Sweep, for a manifest story

When `.studio/run` names a manifest that lists the id, then after approval
and in the same session, before anything is printed:

1. SDD's pre-flight conflict scan already ran in §6 (**Conflict scan first**).
   A dependency between two siblings found now, by this sweep or by a later
   review, is never written as `After:`, which `studio-brief validate` would
   refuse. It becomes a manifest Depends on: the later sibling depends on the
   earlier one. Record it in that plan's `## Decisions`.
   Always add the section after Global Constraints when absent, writing `none` when it is empty.
2. The question sweep (autopilot's sweep procedure, moved here). Read the
   approved spec and plan and list every decision the implementation could
   still meet: naming, error handling, test depth, tie-breaks between two
   acceptable patterns, what to do when a tool is missing, which of two
   libraries. An item the spec calls open stays in the sweep until
   `## Decisions` answers it; a committed file or a prior ledger entry is not
   a substitute. Ask all of them, three or four per `AskUserQuestion`, each
   option with its Gains and Costs (CLAUDE.md's Decision Questions), until
   none is left, and write each answer into `## Decisions`.
3. Run `studio-state ledger "Decisions swept <id>"`, then commit the plan and
   `.studio/ledger`: `git add <plan path> .studio/ledger`, then, only when it succeeded, `git commit -m "docs(plans): sweep <id>"` (two calls).
4. Print `/clear`, then the command `studio-overnight next` prints. The plan
   does not print `/game-dev:execute` for a manifest story. Do not invoke
   anything yourself.
