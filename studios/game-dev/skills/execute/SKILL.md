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
before each task read the skills named in the role agent's `## Skills you
may call` section (`studios/game-dev/agents/<role>.md`). §3, §5 and §6
still apply; §2's dispatch and §4 do not.

## 2. Who implements (subagent-driven mode)

Dispatch the agent named by the task's `Role:` line with the Agent tool
(`subagent_type: "game-dev:<role>"` — for example
`subagent_type: "game-dev:gameplay-programmer"`). The agent carries its own
persona, rules and output contract; the brief carries only the task.

One exception: when `.studio/config.json` sets `language: csharp` and the
role is `game-dev:gameplay-programmer`, dispatch
`godot-prompter:godot-csharp-engineer` instead and prepend the project
`CLAUDE.md` architecture rules and the gameplay-programmer's output contract
to its brief, because that agent does not know the studio's report shape.

The `Role:` values are the studio's agents: `game-dev:gameplay-programmer`,
`game-dev:level-designer`, `game-dev:tech-artist`, `game-dev:feel-tuner`,
`game-dev:ui-designer`, `game-dev:architect` implement; `game-dev:game-designer`,
`game-dev:producer`, `game-dev:playtester` and `game-dev:reviewer` never
appear in `Role:`.

Every brief also carries: the task text (via the skill's task-brief script),
the spec sections the task cites, and the project `CLAUDE.md` architecture
rules. The agent's own `## Skills you may call` section (in
`agents/<role>.md`) names the skills it reads before writing code. A stuck
implementer reads `superpowers:systematic-debugging`.

## 3. Verify rules (both modes)

`Verify:` is one kind or several joined with `+` (`unit+playtest`). Every
kind listed binds the implementer:

- `unit` — the implementer follows `superpowers:test-driven-development`:
  the test named in `Files:` is written and seen to fail before the
  implementation, then passes. The test framework is the project's test
  framework (`tests` in `.studio/config.json`, default GUT). Before
  reporting, the implementer runs `studio-test` and pastes its summary
  line. Exit 2 (no engine binary) or 3 (GUT not installed) stops the task:
  report it to the user with the printed hint; do not work around it.
- `playtest` — the implementer's report ends with the playtest item the task
  defined (action, expected perceptual result, what a failure looks like).
  Record it with `studio-state ledger "T<n> Playtest item: <text>"`.
- `visual` — the implementer reports what to look at and where. Record it as
  `studio-state ledger "T<n> Visual: <text>"`.

A task that introduces or changes a tunable value (a cooldown, a window, a
speed, a curve) always includes `unit`: the number is tested, the feel is
played.

## 4. Who reviews (subagent-driven mode)

Where subagent-driven-development dispatches its task reviewer, dispatch
`game-dev:reviewer` (`subagent_type: "game-dev:reviewer"`) with the task
text, the spec sections it cites, the global-constraints block, and the
commit range. The agent carries this checklist; it is repeated here so the
orchestrator can judge the report:

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

1. **Smoke boot.** From the project root run `studio-run --seconds 5`. It
   scans the run log for `SCRIPT ERROR` and `ERROR:` and exits 1 when either
   appears, 2 when no Godot binary is found; on exit 2, stop and ask the user
   to set `GODOT_PATH` — do not set `stage review`. A failure (exit 1) is a
   task: fix it through the loop above, re-run, then continue.
2. `studio-state set stage review`.
3. List every ruling you made, in order, with what it costs if wrong.
4. List every `Playtest item:` and `Visual:` line in `studio-state show`
   under **unverified — check by hand before merging**. They were reviewed
   by reading code, not by playing; the playtest stage owns them.
5. Tell the user the next command is `/game-dev:review`. Do not merge, and
   do not name a merging skill.
