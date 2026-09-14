---
name: brainstorm
description: Use when starting any game feature, system, or new game before code is written — clarifies intent in batched questions, classifies scope, writes a spec with GDD-lite sections, renders it as an artifact, and waits for approval.
---

# Brainstorm

**Announce at start:** "Using game-dev:brainstorm to turn this into an approved spec."

No code, no engine files opened for editing, no plan, until the user has
approved a spec. That gate scales down with the task — a bounded change gets
a short spec — but it never disappears.

## 0. State

- If `.studio/STATE.md` does not exist and `project.godot` does, ask once
  whether to initialise studio state; on yes run `studio-state init`. On no,
  or when there is no `project.godot`, continue without state and skip every
  `studio-state` call in this skill.
- If `studio-state get spec` names a file and the ledger has no matching
  `spec approved` line, tell the user an unapproved spec already exists and
  ask whether to continue it or start a new one.

## 1. Read the project

Before the first question, read what exists: `docs/game-dev/PROGRESS.md`
when the project has one (the milestone gate and its exit criteria), the
newest files in `docs/game-dev/specs/` and `docs/game-dev/playtests/`, the
project `CLAUDE.md`, and the part of the scene tree or scripts the request
touches. When the request touches controls, movement, camera or feedback,
invoke `game-dev:game-feel`.

## 2. Classify, and say so

- **Spike** — a feasibility question. Present the question and what you will
  try in two or three sentences, get a nod, find out, report a
  recommendation. No spec.
- **Bounded** — a change to a flow that already exists in this project (one
  new verb on an existing controller, a tuning pass, a new enemy on an
  existing spawner). Short questions, a short spec, the same gate.
- **Architectural** — a new system, a new game, or a change to how systems
  talk to each other. Full process below.

For **bounded** and **architectural** work run `studio-state set stage
brainstorm` now; a spike leaves the stage where it was.

When in doubt, take the heavier path. Hidden complexity found mid-way
upgrades the path; say so.

## 3. Ask in batches

Ask three or four related questions per `AskUserQuestion`, each written as a
decision brief: the question, what is at stake if it is answered wrong, your
recommendation, and the options. Cover, in this order, only what the request
leaves open:

1. **Player intent** — what the player is trying to do when this is used,
   and in which ten-second loop it appears.
2. **Verbs** — which player verbs are added, changed, or removed.
3. **Feel targets in real units** — distance in tiles, duration in seconds,
   input latency in frames at 60 fps, forgiveness windows in seconds,
   cooldowns, a reference game if the user has one.
4. **Scope** — what this must prove for the current milestone gate, and what
   is explicitly not being done. When the project has no `PROGRESS.md`, ask
   here which gate this is (prototype, vertical slice, alpha, beta, gold)
   and its two or three exit criteria; they go into the spec's **Milestone
   gate** section and the plan's scope pass cuts against them.
5. **Engine constraints** — existing state machine, event bus, Resources,
   and tests the change must fit.
6. **Test strategy** — which behaviour can be unit-tested (numbers, state
   transitions, cooldowns, collisions) and which can only be judged by
   playing (readability, snappiness, timing).

Read free-text answers carefully; they often override the offered options.

## 4. Approaches

For bounded and architectural work, propose two or three approaches with
trade-offs and lead with your recommendation. One `AskUserQuestion`. YAGNI:
cut anything the milestone gate does not need before you present.

For the architectural path, dispatch two subagents with the draft spec:

- `game-dev:game-designer`, briefed: "Write the **Design** section: core
  loop, mechanics and what each adds to the loop, progression as new
  decisions, difficulty and how the player learns it. Use
  `game-dev:game-design-doc` and `game-dev:core-loop-design`. State your
  assumptions about the target player; list open questions for me; write no
  engine files."
- `godot-prompter:godot-game-architect`, opened with the persona line "You
  are the studio's architect: scene tree, state machines, signal topology,
  Resource schemas; you leave a decision and its reason, not just code."
  and briefed: "Write the **Architecture** section: scene tree, state
  machine changes, signals and event-bus topics, Resource schemas. Read
  `godot-prompter:scene-organization`, `godot-prompter:state-machine`,
  `godot-prompter:event-bus`, `godot-prompter:component-system` and
  `godot-prompter:resource-pattern`. Composition over inheritance; signals
  up, calls down, the event bus only where no ownership path exists; every
  tunable number in a Resource. Write the section only; write no plan file."

Fold their sections into the spec; put the designer's open questions to the
user in the next batch.

## 5. Write the spec

Save to `docs/game-dev/specs/YYYY-MM-DD-<topic>.md` in the game project
(create the directory if needed). Use these top-level headings, in this
order, and no others — except that the **Design** section may nest
`game-dev:game-design-doc`'s own headings (Pitch, Core loop, Player verbs,
Progression, Failure, Scope) when folding in the designer's document rather
than dropping them:

```markdown
# <Feature> — Spec

Date: YYYY-MM-DD
Status: Draft (awaiting approval)
Milestone: <gate name>
Classification: bounded | architectural

## Milestone gate
The gate this serves and its exit criteria — copied from `PROGRESS.md` when
the project has one, otherwise as answered in step 3.

## Purpose
One paragraph: what the player gets and why it serves the current gate.

## Core-loop delta
What changes in the ten-second loop. "None" is a valid answer; say it.

## Player verbs
- Added: …
- Changed: …
- Removed: …

## Design
Core loop, mechanics, progression, difficulty — from `game-dev:game-designer`
(architectural), or `n/a` (bounded).

## Failure and recovery
What failing looks like, what it costs the player, how they get back in.
"None" is a valid answer; say it.

## Teaching
How the player learns this: where it is first needed, what the level or UI
does to show it.

## Input and platform
Input device and target platform the feel targets assume (keyboard, gamepad,
touch; 60 fps desktop, Steam Deck, mobile).

## Feel targets
| Target | Value | How it is checked |
|--------|-------|-------------------|
| Dash distance | 3 tiles in 0.15 s | unit |
| Input latency | ≤ 2 frames at 60 fps | playtest |

## References
Games or scenes that do this well, and what to take from each. `n/a` when none.

## Acceptance criteria
Numbered, each one testable by a unit test or a playtest item.

## Architecture
Scene tree changes, state machine changes, signals / event-bus topics,
Resource schemas, files to create or modify.

## Tuning knobs
The Resource fields this feature exposes: name, unit, default, range. Every
number in Feel targets appears here.

## Assets and audio
Sprites, animations, sounds this needs, and who makes them. `n/a` when none.

## Test strategy
- Unit (the project's test framework): which behaviours, which test files.
- Playtest: which criteria, what a pass looks like, what a fail looks like.
- Visual: what the user looks at with no automated check.

## Risks
What could sink this and the cheapest way to find out early. `n/a` when none.

## Not doing
An explicit list. Anything cut in step 4 goes here with a one-line reason.
```

Every section states a decision. A section that reads as a possibility is
not finished. A bounded spec writes `n/a` in a section that does not apply
rather than dropping it.

## 6. Render the artifact

Write an HTML rendering of the spec to
`docs/game-dev/artifacts/YYYY-MM-DD-<topic>.html` (same stem as the spec)
and publish it with the Artifact tool (favicon 🎮; title is the feature
name). Load the `artifact-design` skill before writing the page. The page
carries every section of the spec; add a diagram only where the architecture
section has one worth drawing (a state machine, an event flow). If the
Artifact tool is unavailable, say so and present the markdown instead — the
gate does not depend on the page.

## 7. Gate

Run `studio-state set spec <spec path>` and
`studio-state ledger "spec written <spec path>"`. Then **stop** with:

> Spec at `<path>`, artifact at `<url>`. Reply **approve**, or name the
> section to change.

Revise on request and re-render. On approval: change the spec's `Status:` to
`Approved` and commit it — `git add <spec path> && git commit -m
"docs(specs): approve <topic>"` — then run `studio-state ledger "spec
approved <spec path>"`, and tell the user the next command is
`/game-dev:plan`. Do not invoke it yourself.
