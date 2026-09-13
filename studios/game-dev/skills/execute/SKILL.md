---
name: execute
description: Use when an approved plan exists — dispatches a fresh role agent per task with a reviewer after each; pass --inline for checkpointed inline execution.
---

# Execute

**Announce at start:** "Using game-dev:execute in subagent-driven mode." (or
"… in inline mode" when `--inline` was given).

## 0. Preconditions

- `studio-state get plan` names a file that exists and the ledger has a
  `plan approved` line for it; otherwise stop and point at `/game-dev:plan`.
- Read the plan once. Read the spec its header names; the spec is the
  authority the plan argues from.
- Isolation: invoke `superpowers:using-git-worktrees`. Never implement on
  `main` without the user's explicit consent.
- Run `studio-state set stage execute`. Read `task` to find where to resume:
  `3/6` means tasks 1–3 are complete; start at 4.

## 1. Mode

**Default — subagent-driven.** Invoke
`superpowers:subagent-driven-development` and follow its loop exactly:
fresh implementer per task, task review after each, fix rounds, final
whole-branch review, ledger. The studio rules in §2–§5 layer on top of it.

**`--inline`.** Only when the user passed it. Invoke
`superpowers:executing-plans` instead and implement tasks in this session in
batches, checking in with the user between batches. §3 (verify rules) and §5
(state) still apply; §2 and §4 do not.

## 2. Who implements (subagent-driven mode)

Dispatch the implementer named by the task's `Role:` line. Until the studio's
role agents ship (Plan 2 of the studio adds `game-dev:<role>` agents), use
the `general-purpose` agent and open its brief with the role's persona line:

| `Role:` | Persona line |
|---------|--------------|
| `game-dev:gameplay-programmer` | You are the studio's gameplay programmer: GDScript, composition over inheritance, systems talk through the event bus, every tunable number lives in a Resource, tests first. |
| `game-dev:level-designer` | You are the studio's level designer: layout teaches the mechanic before it tests it; collision is authored on the tileset, not per level. |
| `game-dev:tech-artist` | You are the studio's technical artist: one pixels-per-unit, nearest filtering for pixel art, atlases by draw order and lifetime, import settings versioned. |
| `game-dev:feel-tuner` | You are the studio's feel tuner: diagnose in order — input latency, forgiveness, acceleration, animation timing, camera — before adding effects; state the expected perceptual change before each edit. |
| `game-dev:ui-designer` | You are the studio's UI designer: Control nodes only, containers over manual positioning, one Theme resource. |
| `game-dev:architect` | You are the studio's architect: scene tree, state machines, signal topology, Resource schemas; you leave a decision and its reason, not just code. |

When the `game-dev:<role>` agent exists in your agent list, dispatch it
instead and drop the persona line — the agent carries it.

Every brief also carries: the task text (via the skill's task-brief script),
the spec sections the task cites, the project `CLAUDE.md` architecture
rules, and the engine-skill pointers for the role — gameplay work reads
`godot-prompter:gdscript-patterns`, `godot-prompter:state-machine`,
`godot-prompter:event-bus`, `godot-prompter:resource-pattern`; tests read
`godot-prompter:godot-testing`; a stuck implementer reads
`superpowers:systematic-debugging`.

## 3. Verify rules (both modes)

- `Verify: unit` — the implementer follows
  `superpowers:test-driven-development`: the GUT test in `Files:` is written
  and seen to fail before the implementation, then passes. Before reporting,
  run the project's test suite: `studio-test` when it is on `PATH` (it
  arrives with the engine toolkit); otherwise the GUT command line from
  `godot-prompter:godot-testing`, headless, with the exit code checked.
- `Verify: playtest` — no unit test is required. The implementer's report
  ends with the playtest item the task defined (action, expected perceptual
  result, what a failure looks like). Record it with
  `studio-state ledger "T<n> Playtest item: <text>"` so the playtest stage
  picks it up.
- `Verify: visual` — the implementer reports what to look at and where. Record
  it the same way, as `T<n> Visual: <text>`.

## 4. Who reviews (subagent-driven mode)

The task reviewer from subagent-driven-development, with the studio's
checklist appended to the global-constraints block it receives (Plan 2 of the
studio replaces this reviewer with the `game-dev:reviewer` agent):

- Spec compliance: every acceptance criterion the task claims is met, and
  nothing beyond the task was built.
- `godot-prompter:godot-code-review` findings.
- Composition, not inheritance, where the spec specified a component.
- No direct references between systems that bypass the event bus.
- No tuning literal outside a Resource.
- No per-frame allocation in `_process` or `_physics_process`.
- For `Verify: unit`: the test exists, fails without the change, passes with it.

Findings are one line each, severity-tagged. The fix loop is
subagent-driven-development's.

## 5. State (both modes)

- After each task's review is clean: `studio-state set task n/N` and
  `studio-state ledger "T<n> complete <short commit range>"`.
- Every judgment call: `studio-state ledger "T<n> Ruling: <decision> — <why> — <cost if wrong>"`.
  The SDD ledger under `.superpowers/sdd/` remains the recovery map for the
  loop; `STATE.md` carries the rulings the user reads.
- Every review finding that changed the code: `studio-state ledger "T<n> Review: <one line>"`.

Stop only for the four reasons subagent-driven-development names: an
irreversible or destructive operation, a security-sensitive action, a side
effect outside the worktree (merge, push, publish), or a plan too broken to
follow. Everything else is a ruling.

## 6. Finish

When the final whole-branch review is clean, do **not** run
`superpowers:finishing-a-development-branch` — merging is the ship stage's
decision. Instead:

1. `studio-state set stage review`.
2. List every ruling you made, in order, with what it costs if wrong.
3. Tell the user the next command is `/game-dev:review`. If that skill is not
   in your skill list yet, say so and offer
   `superpowers:finishing-a-development-branch` as the manual path.
