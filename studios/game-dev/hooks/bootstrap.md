You are in the omega-ai **game-dev** studio. Engine: {{ENGINE}} · {{DIMENSION}} · {{LANGUAGE}} · {{TESTS}}.

## Precedence

`game-dev:*` stage skills own the workflow. superpowers skills run only when a stage skill names them. godot-prompter skills run inside role agents for engine work, or in the main session in `--inline` mode. If superpowers' own bootstrap says "invoke brainstorming", invoke `game-dev:brainstorm` instead.

## Stages

- `/game-dev:studio` — router: reads state, names the next stage, routes freeform text.
- `/game-dev:brainstorm` — clarify, classify, spec with GDD-lite sections, artifact, approval gate.
- `/game-dev:plan` — role- and verify-tagged tasks, producer scope cut, approval gate.
- `/game-dev:execute` — fresh role agent per task, reviewer after each, standalone final review, gate, play list, PROGRESS entry, PR; `--inline` for checkpoints.
- `/game-dev:scaffold` — new project from the engine template.

The chain is idle → brainstorm → plan → execute → idle. Run each stage in a fresh session: `/clear`, then the stage command. `/clear` ends the session, and that session's omega modes (reply, delegate, autopilot and the rest) end with it; type again the ones you want.

## On demand — never changes the stage

- `/game-dev:review [scope]` — the branch (or a range) against the spec; findings fixed by fresh agents.
- `/game-dev:playtest <what failed>` — what you saw fail goes in; a bug, a fixed commit with a regression test, a push and one PR comment come out.
- `/game-dev:retro` — durable lessons from the ledger into studio memory.

A command that is not in your skill list is not installed yet: say so and name it rather than improvising it.

## State

When `.studio/STATE.md` exists, a line naming the current stage (`stage <stage>`) follows this bootstrap; `/game-dev:studio` names the next step from it. When it does not exist and this is a Godot project (`project.godot` present), `/game-dev:studio` initialises it.
