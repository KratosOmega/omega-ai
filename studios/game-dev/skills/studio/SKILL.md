---
name: studio
description: Use when starting a game-dev session, unsure which stage comes next, or handing freeform text to the studio — reads .studio/STATE.md and routes to the right stage skill.
---

# Studio Router

**Announce at start:** "Using game-dev:studio to route this."

This skill routes. It never designs, plans, implements, reviews or tests
anything itself — it reads the project's state, says where the project is,
names the next stage, and hands freeform requests to the right stage skill.

## 1. Read the state

Run `studio-state show` from the project root.

- **Exit 0:** parse the header fields (`stage`, `spec`, `plan`, `task`,
  `last_playtest`, `milestone`) and the ledger lines. Then run
  `studio-state check`: on exit 1 append its first line to the state line as
  `· check: <message>`; offer `studio-state check --rebuild` only when the
  message says so, and only after the user agrees.
- **Exit 1 (no `.studio/`):** this project has no studio state yet.
  - If `project.godot` exists here, ask with one `AskUserQuestion` whether to
    initialise studio state in this project. On yes, run `studio-state init`
    and continue with stage `idle`. On no, stop.
  - If there is no `project.godot`, say that this is not a Godot project. If a
    `game-dev:scaffold` skill is in your skill list, offer it; otherwise ask
    the user to create the Godot project first and come back.

If `docs/game-dev/PROGRESS.md` exists, read its first section for the current
milestone gate and its exit criteria; quote the gate name in the report.

## 2. Report, then name the next step

Print one line of state, then one line naming the next stage:

```
Stage: execute · Milestone: prototype · Spec: docs/game-dev/specs/2026-09-13-dash.md · Plan: docs/game-dev/plans/2026-09-13-dash.md · Task: 3/6
Next: /game-dev:execute — resume at task 3 of 6
```

The next stage follows from the current one:

| `stage` | Next | Unless |
|---------|------|--------|
| `idle` | `/game-dev:brainstorm` | — |
| `brainstorm` | `/game-dev:plan` | `spec` is `-` — then treat the stage as `idle` (a brainstorm that never reached a spec). Or the ledger has no `spec approved <path>` line for the current `spec` value — then: "spec awaiting approval; reply approve to `/game-dev:brainstorm` or re-run it" |
| `plan` | `/game-dev:execute` | the ledger has no `plan approved <path>` line for the current `plan` value — same pattern |
| `execute` | `/game-dev:execute` (resume) | `task` is `N/N` — then `/game-dev:review` |
| `review` | `/game-dev:playtest` | — |
| `playtest` | `/game-dev:ship` | the ledger has no `playtest signed off` line — "playtest awaiting sign-off" |
| `ship` | `/game-dev:retro` | — |
| `retro` | `/game-dev:brainstorm` | — |

**Abandon / re-plan.** At any stage, when the user says the feature is
dropped or the plan is too broken to follow, confirm with one
`AskUserQuestion` (keep the ledger, or remove it), run `studio-state reset`
(`--keep-ledger` when asked), and name `/game-dev:brainstorm` as the next
command. The `abandoned <spec>` line stays in `STATE.md`'s ledger.

If the next stage's skill is not in your skill list, say which stage it is
and that it is not installed yet. Do not improvise the stage.

## 3. Route freeform text

When the user hands you a request instead of asking for state, classify it
by what the request *is*, not by which stage the project is in:

| Request looks like | Route to |
|--------------------|----------|
| a feature, mechanic, system, enemy, level, or "add / change / remove X" | `/game-dev:brainstorm` with the text as its topic |
| "feels wrong / floaty / laggy / unresponsive / too fast / juice" | `/game-dev:playtest` — a feel pass; until that skill is installed, `game-dev:game-feel` for the diagnostic order |
| "is this done / does this match the spec / review it" | `/game-dev:review` |
| "make a plan / break this down" and a spec exists | `/game-dev:plan` |
| "build it / implement / go" and an approved plan exists | `/game-dev:execute` |
| "new game / new project" | `/game-dev:scaffold` when installed; otherwise say so |
| a bug with a repro | `superpowers:using-git-worktrees`, then a failing test that reproduces it, then `superpowers:systematic-debugging`; note the fix with `studio-state ledger "Bug: <one line> — <commit>"` |
| "abandon / drop this / start over" | the abandon step in §2 |
| anything else | answer directly; no stage applies |

A request that skips a gate is still routed to the gate. "Implement the dash
now" with no spec goes to `/game-dev:brainstorm`; say why in one sentence.

Invoke the target skill with the Skill tool and pass the user's text. Do not
paraphrase a request into a different one.

## Rules

- Never do the stage's work here. The router's whole output is the state
  line, the next-step line, and the hand-off.
- Never write to `.studio/` except through `studio-state init` (after the
  user says yes), `studio-state reset` (after the user confirms), and the
  `studio-state ledger` line of the bug route.
- Always end by naming the exact command to run next, even when it is the one
  you just invoked.
