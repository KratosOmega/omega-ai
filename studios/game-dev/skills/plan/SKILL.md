---
name: plan
description: Use when an approved spec exists and needs an implementation plan — writes role-tagged, verify-tagged tasks, runs the producer scope pass, and waits for approval.
---

# Plan

**Announce at start:** "Using game-dev:plan to write the implementation plan."

## 0. Preconditions

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
- Every task carries two extra lines directly under its heading:

  ```markdown
  ### Task 3: Input action and buffer window
  Role: game-dev:gameplay-programmer
  Verify: unit+playtest
  Files: src/player/dash_state.gd, tests/unit/test_dash_input.gd
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
`Verify: playtest` task states its playtest item.

Then run `studio-state set stage plan`, `studio-state set plan <plan path>`,
`studio-state set task 0/N` (N = number of tasks outside the backlog), and
`studio-state ledger "plan written <plan path>"`. **Stop** with:

> Plan at `<path>`: N tasks, K cut to backlog. Reply **approve**, or name the
> task to change.

On approval: change the plan's `Status:` line to `Approved`, run
`studio-state ledger "plan approved <plan path>"`, then commit the plan, the
spec and the state that must travel with them into the execution worktree —
`git add <spec path> <plan path> .studio/ledger .studio/config.json && git commit -m "docs(plans): approve <topic>"`
(a no-op for an already-committed, unchanged spec; it captures the spec
approved in §0) —
and tell the user the next command is `/game-dev:execute` (subagent-driven by
default; `--inline` for checkpointed execution in this session). Do not invoke
it yourself.
