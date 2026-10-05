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

Run `studio-state show` in the checkout you are in.

- In the main checkout, also run `studio-state stories` and list each story
  on one line with the checkout to continue it in. A `run` line reads
  `run in progress in <path>`, never a story to continue.
- When main is idle and a story is active elsewhere, `Next:` names
  `continue <spec> in <path>` first, then `/game-dev:brainstorm` for a new
  story.
- In a pointer-less worktree whose `show` prints the take hint, `Next:` names
  `studio-state take <spec>` (continue main's story here) or
  `/game-dev:brainstorm` (a new story), never `/game-dev:execute`.

- **Overnight run live:** `studio-overnight status` (exit 0) shows the live
  runs. Mention them in one line. A live run does not make the project busy:
  route as usual.
- **Exit 0:** parse the header fields (`stage`, `spec`, `plan`, `task`,
  `branch`, `milestone`) and the ledger lines. Then run
  `studio-state check`: on exit 1, end the state line with ` · ` followed by
  the first line of its output verbatim (it already carries its own
  `check:` prefix, e.g. `check: ledger says T3 complete but task is 2/6 —
  run check --rebuild`); offer `studio-state check --rebuild` only when that
  line says so, and only after the user agrees.
- **Exit 1 (no `.studio/`):** this project has no studio state yet.
  - If `project.godot` exists here, ask with one `AskUserQuestion` whether to
    initialise studio state in this project. On yes, run `studio-state init`
    and continue with stage `idle`. On no, continue to §3 without state;
    `/game-dev:brainstorm` runs without it and says so.
  - If there is no `project.godot`, say that this is not a Godot project. If a
    `game-dev:scaffold` skill is in your skill list, offer it; otherwise ask
    the user to create the Godot project first and come back.

If `docs/game-dev/PROGRESS.md` exists, read its first section for the current
milestone gate and its exit criteria; quote the gate name in the report.

## 2. Report, then name the next step

Print one line of state, then one line naming the next stage:

```
Stage: execute · Milestone: prototype · Spec: docs/game-dev/specs/2026-09-13-dash.md · Plan: docs/game-dev/plans/2026-09-13-dash.md · Task: 2/6 · check: ledger says T3 complete but task is 2/6 — run check --rebuild
Next: /game-dev:execute — resume at task 2 of 6
```

The next stage follows from the current one. Each stage sets `stage` to its
own name while it works, and `execute` sets `idle` when its finish
completes. `review`, `playtest` and `retro` are on-demand commands: they run
at any stage and never change it.

| `stage` | Next | Unless |
|---------|------|--------|
| `idle` | `/game-dev:brainstorm` | — |
| `brainstorm` | `/game-dev:plan` | `spec` is `-` — then the project is effectively idle: report `Stage: idle` and `Next: /game-dev:brainstorm` (a brainstorm that never reached a spec). Or the ledger has no `spec approved <path>` line for the current `spec` value — then: "spec awaiting approval; reply approve to `/game-dev:brainstorm` or re-run it" |
| `plan` | `/game-dev:execute` | the ledger has no `plan approved <path>` line for the current `plan` value — same pattern |
| `execute` | `/game-dev:execute` (resume) | `task` is `N/N` — then it resumes at the final review and finish |
| any other value (`review`, `playtest`, `ship`, `retro`: the old pipeline) | `/game-dev:brainstorm` | — report the state line as `Stage: idle (was <value>, old pipeline)` |

On demand, at any stage: `/game-dev:review [scope]`,
`/game-dev:playtest <what failed>`, `/game-dev:retro`. None of them changes
`stage`.

**Abandon / re-plan.** At any stage, when the user says the feature is
dropped or the plan is too broken to follow, confirm with one
`AskUserQuestion` (keep the ledger, or remove it), run `studio-state reset`
(`--keep-ledger` when asked), and name `/game-dev:brainstorm` as the next
command. `studio-state reset` resets this checkout's pointer only; for a
story in another checkout, say `abandon it in <path>`. On exit 4, show the
message. The `abandoned <spec>` line stays in `STATE.md`'s ledger (when a
spec was set).

If the next stage's skill is not in your skill list, say which stage it is
and that it is not installed yet. Do not improvise the stage.

## 3. Route freeform text

When the user hands you a request instead of asking for state, classify it
by what the request *is*, not by which stage the project is in:

| Request looks like | Route to |
|--------------------|----------|
| a feature, mechanic, system, enemy, level, or "add / change / remove X" | `/game-dev:brainstorm` with the text as its topic |
| "feels wrong / floaty / laggy / unresponsive / too fast / juice" | `/game-dev:playtest` with the user's text as the failure report |
| "is this done / does this match the spec / review it" | `/game-dev:review` |
| "make a plan / break this down" and a spec exists | `/game-dev:plan` |
| "build it / implement / go" and an approved plan exists | `/game-dev:execute` |
| "new game / new project" | `/game-dev:scaffold` when installed; otherwise say so |
| "what did we learn / retro / lessons" | `/game-dev:retro` |
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
  user says yes), `studio-state check --rebuild` (after the user agrees),
  `studio-state reset` (after the user confirms), and the `studio-state
  ledger` line of the bug route. A pre-#42 worktree's one-time adopt
  (studio-state AC18) may move its story into it on the router's first read.
- Always end by naming the exact command to run next, even when it is the one
  you just invoked.
