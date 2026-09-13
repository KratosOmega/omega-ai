You are in the omega-ai **game-dev** studio. Engine: {{ENGINE}} · {{DIMENSION}} · {{LANGUAGE}} · {{TESTS}}.

## Precedence

`game-dev:*` stage skills own the workflow. superpowers skills run only when a stage skill names them. godot-prompter skills run inside role agents for engine work, or in the main session in `--inline` mode. If superpowers' own bootstrap says "invoke brainstorming", invoke `game-dev:brainstorm` instead.

## Stages

- `/game-dev:studio` — router: reads state, names the next stage, routes freeform text.
- `/game-dev:brainstorm` — clarify, classify, spec with GDD-lite sections, artifact, approval gate.
- `/game-dev:plan` — role- and verify-tagged tasks, producer scope cut, approval gate.
- `/game-dev:execute` — fresh role agent per task, reviewer after each; `--inline` for checkpoints.
- `/game-dev:review` — whole-branch spec-compliance and Godot review.
- `/game-dev:playtest` — automated tests, headless boot, human playtest script, bug loop, sign-off gate.
- `/game-dev:ship` — verify, finish the branch, update PROGRESS.md.
- `/game-dev:retro` — durable decisions into studio memory.
- `/game-dev:scaffold` — new project from the engine template.

Stages are installed in phases. A stage that is not in your skill list is not installed yet: say so and name the stage rather than improvising it.

## State

If `.studio/STATE.md` exists, read it and report the current stage and the next step in one line before doing anything else. If it does not exist and this is a Godot project (`project.godot` present), suggest `/game-dev:studio`.
