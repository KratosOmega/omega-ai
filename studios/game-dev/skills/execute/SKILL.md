---
name: execute
description: Use when an approved plan exists — dispatches a fresh role agent per task with a reviewer after each; pass --inline for checkpointed inline execution.
---

# Execute

**Announce at start:** "Using game-dev:execute in subagent-driven mode." (or
"… in inline mode" when `--inline` was given).

## 0. Preconditions

Check these first, in the checkout you are in:

- `studio-state get plan` names a file that exists and `studio-state show`
  has a `plan approved` line for it; otherwise stop and point at
  `/game-dev:plan`.
- The spec and the plan are committed: `git log -1 --format=%h -- <spec path>`
  and the same for the plan path each print a hash — note both hashes. If
  either prints nothing, stop and say: "commit the spec and plan first —
  `git add <spec> <plan> .studio/ledger .studio/config.json && git commit -m 'docs: approve <topic>'`".
  A worktree is a checkout; an uncommitted spec does not travel into it.
- Nothing is staged or pending on top of that commit:
  `git status --porcelain -- <spec> <plan> .studio/ledger .studio/config.json`
  prints nothing. Uncommitted changes to the gate inputs mean the worktree
  would carry a stale plan — commit or discard them first.
- Read the plan once. Read the spec its header names; the spec is the
  authority the plan argues from.
- Run `studio-state set stage execute`. Read `task` to find where to resume:
  `3/6` means tasks 1–3 are complete; start at 4. `studio-state` keeps the
  pointer in the project's main checkout, so every call below works the same
  from inside a worktree.

Then isolate: note the current branch (`git branch --show-current`) along
with the spec's and plan's noted hashes, invoke
`superpowers:using-git-worktrees`, and in the new worktree confirm each
noted commit is in `HEAD`: `git merge-base --is-ancestor <hash> HEAD` for
the spec's hash and for the plan's hash. If either is not an ancestor, the
worktree was cut from a base that lacks the gate commits: run
`git merge --ff-only <noted branch>`; if that fails, stop and say so. Never
implement on `main` without the user's explicit consent.

## 1. Mode

**Default — subagent-driven.** Invoke
`superpowers:subagent-driven-development` and follow its loop exactly:
fresh implementer per task, task review after each, fix rounds, final
whole-branch review, ledger. The studio rules in §2–§5 layer on top of it.

**`--inline`.** Only when the user passed it. Invoke
`superpowers:executing-plans` instead and implement tasks in this session in
batches, checking in with the user between batches. You are the implementer:
before each task read the skills its role's row in §2 lists. §3, §5 and §6
still apply; §2's dispatch and §4 do not.

## 2. Who implements (subagent-driven mode)

Dispatch the implementer named by the task's `Role:` line from this table.
The studio's own role agents arrive in Plan 2; until then a role with a
godot-prompter equivalent dispatches that agent, and `level-designer`
dispatches `general-purpose`. Open every brief with the persona line — a
godot-prompter agent knows the engine, not this studio's rules.

| `Role:` | Dispatch | Persona line | Skills the brief names |
|---------|----------|--------------|------------------------|
| `game-dev:gameplay-programmer` | `godot-prompter:godot-game-dev` | You are the studio's gameplay programmer: composition over inheritance, signals up and calls down, every tunable number in a Resource, tests first. | `godot-prompter:gdscript-patterns`, `godot-prompter:state-machine`, `godot-prompter:event-bus`, `godot-prompter:resource-pattern`, `godot-prompter:component-system`, `godot-prompter:player-controller`, `godot-prompter:input-handling`, `godot-prompter:physics-system`, `godot-prompter:camera-system`, `godot-prompter:godot-testing` |
| `game-dev:architect` | `godot-prompter:godot-game-architect` | You are the studio's architect: scene tree, state machines, signal topology, Resource schemas; you leave a decision and its reason, not just code. | `godot-prompter:scene-organization`, `godot-prompter:state-machine`, `godot-prompter:event-bus`, `godot-prompter:component-system`, `godot-prompter:dependency-injection`, `godot-prompter:resource-pattern` |
| `game-dev:ui-designer` | `godot-prompter:godot-ui-designer` | You are the studio's UI designer: Control nodes only, containers over manual positioning, one Theme resource. | `godot-prompter:godot-ui`, `godot-prompter:hud-system`, `godot-prompter:responsive-ui` |
| `game-dev:feel-tuner` | `game-dev:feel-tuner` | (the agent carries it) | `game-dev:game-feel`, `godot-prompter:tween-animation`, `godot-prompter:camera-system`, `godot-prompter:animation-system`, `godot-prompter:input-handling` |
| `game-dev:tech-artist` | `game-dev:tech-artist` | (the agent carries it) | `game-dev:2d-sprite-pipeline`, `godot-prompter:2d-essentials`, `godot-prompter:assets-pipeline` |
| `game-dev:level-designer` | `general-purpose` | You are the studio's level designer: layout teaches the mechanic before it tests it; collision is authored on the tileset, not per level. | `godot-prompter:2d-essentials` |

When `.studio/config.json` sets `language: csharp`, `gameplay-programmer`
dispatches `godot-prompter:godot-csharp-engineer` instead, and the skills
column swaps too: `godot-prompter:csharp-godot` and
`godot-prompter:csharp-signals` replace `godot-prompter:gdscript-patterns`
(the engine-pattern skills — `state-machine`, `event-bus`,
`resource-pattern`, `component-system`, `player-controller`,
`input-handling`, `physics-system`, `camera-system`, `godot-testing` — carry
over unchanged).

Every brief also carries: the task text (via the skill's task-brief script),
the spec sections the task cites, the project `CLAUDE.md` architecture
rules, and the skills column above as "read these before writing code". A
stuck implementer reads `superpowers:systematic-debugging`.

## 3. Verify rules (both modes)

`Verify:` is one kind or several joined with `+` (`unit+playtest`). Every
kind listed binds the implementer:

- `unit` — the implementer follows `superpowers:test-driven-development`:
  the test named in `Files:` is written and seen to fail before the
  implementation, then passes. The test framework is the project's test
  framework (`tests` in `.studio/config.json`, default GUT). Before
  reporting, run the project's test suite: `studio-test` when it is on
  `PATH` (it arrives with the engine toolkit); otherwise the framework's
  command line from `godot-prompter:godot-testing`, headless, with the exit
  code checked.
- `playtest` — the implementer's report ends with the playtest item the task
  defined (action, expected perceptual result, what a failure looks like).
  Record it with `studio-state ledger "T<n> Playtest item: <text>"`.
- `visual` — the implementer reports what to look at and where. Record it as
  `studio-state ledger "T<n> Visual: <text>"`.

A task that introduces or changes a tunable value (a cooldown, a window, a
speed, a curve) always includes `unit`: the number is tested, the feel is
played.

## 4. Who reviews (subagent-driven mode)

The task reviewer from subagent-driven-development is dispatched as
`godot-prompter:godot-code-reviewer`, with the studio's checklist appended to
the global-constraints block it receives (Plan 2 of the studio replaces it
with the `game-dev:reviewer` agent):

- Spec compliance: every acceptance criterion the task claims is met, and
  nothing beyond the task was built.
- `godot-prompter:godot-code-review` findings.
- Composition, not inheritance, where the spec specified a component.
- Cross-system notification goes through signals; `EventBus` only where no
  ownership path exists; parent→child calls and `@export` injection are
  correct.
- No tuning literal outside a Resource.
- No per-frame `instantiate()`, `new()`, Array/Dictionary/String building, or
  `get_node()` by string in `_process` / `_physics_process`; anything else
  is a profiler question, not a review finding.
- For `unit`: the test exists, fails without the change, passes with it.

Findings are one line each, severity-tagged. The fix loop is
subagent-driven-development's.

## 5. State (both modes)

- After each task's review is clean: `studio-state set task n/N` and
  `studio-state ledger "T<n> complete <short commit range>"`.
- Every judgment call: `studio-state ledger "T<n> Ruling: <decision> — <why> — <cost if wrong>"`.
  The SDD ledger under `.superpowers/sdd/` remains the recovery map for the
  loop; the feature ledger (`.studio/ledger/<feature>.md`) carries the rulings
  the user reads.
- Every review finding that changed the code: `studio-state ledger "T<n> Review: <one line>"`.
- Commit `.studio/ledger/` with each task's commits; it is part of the
  feature and merges with it.

Stop only for the four reasons subagent-driven-development names: an
irreversible or destructive operation, a security-sensitive action, a side
effect outside the worktree (merge, push, publish), or a plan too broken to
follow. Everything else is a ruling.

## 6. Finish

When the final whole-branch review is clean:

1. **Smoke boot.** From the project root run the resolved binary headless
   and let it quit on its own: `<binary> --headless --quit-after 1 2>&1`,
   capturing both stdout and stderr — Godot prints `SCRIPT ERROR` and
   `ERROR:` to stderr. Binary: `$GODOT_PATH` if set, else the first
   `/Applications/Godot*.app/Contents/MacOS/Godot`, else `godot` on `PATH`;
   if none is found, stop and ask the user to set `GODOT_PATH` — do not set
   `stage review`. Require exit 0 and no line matching `SCRIPT ERROR` or
   `ERROR:`. A failure is a task: fix it through the loop above, re-run,
   then continue.
2. `studio-state set stage review`.
3. List every ruling you made, in order, with what it costs if wrong.
4. List every `Playtest item:` and `Visual:` line in `studio-state show`
   under **Unverified — check by hand before merging**. They were reviewed
   by reading code, not by playing; the playtest stage owns them.
5. Tell the user the next command is `/game-dev:review`. If that skill is
   not in your skill list yet, say that the review and playtest stages are
   not installed and that the branch must not be merged until the
   unverified items above are checked by hand. Do not merge, and do not
   name a merging skill.
