---
name: plan
description: Use when an approved spec exists and needs an implementation plan — writes role-tagged, verify-tagged tasks, runs the producer scope pass, and waits for approval.
---

# Plan

**Announce at start:** "Using game-dev:plan to write the implementation plan."

## 0. Preconditions

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

  - `Spec: <spec>:L<a>-<b>[, <spec>:L<c>-<d>][, <spec>§<heading>]` cites the
    spec lines the task implements; items are separated by `, `. `§<heading>`
    names a heading line exactly as written in the spec, including its `#`s.
    The lines must exist.
  - `Review: task|final` says whether execute reviews the task by itself.
    `task` is for new seam, cross-system, gameplay feel, data or schema, or importer work; `final` is for the rest, which
    folds into the final review.
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

Run the writing-plans self-review (spec coverage, placeholder scan, name
consistency). Additionally check: every acceptance criterion in the spec maps
to a task; every `Verify: unit` task names a test file; every
`Verify: playtest` task states its playtest item; every task has
a `Spec:` line whose ranges exist, and a `Review:` line.

Then run `studio-state set stage plan`, `studio-state set plan <plan path>`,
`studio-state set task 0/N` (N = number of tasks outside the backlog), and
`studio-state ledger "plan written <plan path>"`. On exit 4 from any of these
state writes: stop and show the message. **Stop** with:

> Plan at `<path>`: N tasks, K cut to backlog. Reply **approve**, or name the
> task to change.

On approval: change the plan's `Status:` line to `Approved`, run
`studio-state ledger "plan approved <plan path>"`, then commit the plan, the
spec and the state that must travel with them into the execution worktree —
`git add <spec path> <plan path> .studio/ledger .studio/config.json && git commit -m "docs(plans): approve <topic>"`
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
4. Run `studio-overnight check-id <id>` there first (its Plan, Ticket and
   slug come from the worktree's `.studio/run`). On a non-zero exit, print
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

1. SDD's pre-flight conflict scan: the plan's tasks against each other and
   against the code on the default branch, for files two tasks both write,
   and an interface one task assumes another changes. Write each finding
   and its resolution into the plan's `## Decisions`.
   Always add the section after Global Constraints when absent, writing `none` when it is empty.
2. The question sweep (autopilot's sweep procedure, moved here). Read the
   approved spec and plan and list every decision the implementation could
   still meet: naming, error handling, test depth, tie-breaks between two
   acceptable patterns, what to do when a tool is missing, which of two
   libraries. An item the spec calls open stays in the sweep until
   `## Decisions` answers it; a committed file or a prior ledger entry is not
   a substitute. Ask all of them, three or four per `AskUserQuestion`, until
   none is left, and write each answer into `## Decisions`.
3. Run `studio-state ledger "Decisions swept <id>"`, then commit the plan and
   `.studio/ledger`: `git add <plan path> .studio/ledger && git commit -m "docs(plans): sweep <id>"`.
4. Print `/clear`, then the command `studio-overnight next` prints. The plan
   does not print `/game-dev:execute` for a manifest story. Do not invoke
   anything yourself.
