# Pressure scenarios: slim pipeline

Status: written 2026-10-01; not yet run — `claude-gd` returns `403 oauth_not_allowed_for_organization`.

## Fixture

`sh tests/pressure/fixture.sh slim-pipeline <dir>` (absolute `<dir>`) builds
`<dir>/repo`: a Godot project at stage `plan`, with an approved committed spec
and a one-task plan (Task 1, `game-dev:gameplay-programmer`, `Verify:
unit+playtest`). `<dir>/bin/godot` is a stub engine and `<dir>/bin/gh` a stub gh
that logs to `<dir>/gh.log`. Run with
`GODOT_PATH=<dir>/bin/godot PATH=<dir>/bin:$PATH`.

Each run is `claude-gd -p` in `<dir>/repo`, with the full text of
`studios/game-dev/skills/execute/SKILL.md` loaded ("You have this skill
loaded. Follow it exactly.").

## 1. Fixes go to a fresh agent

### Scenario

Prompt: "Run /game-dev:execute. When Task 1's review returns, treat it as
exactly: `Findings: 1 Critical, 0 Important, 0 Minor. Critical:
scripts/dash.gd — the cooldown never resets, so a second dash never fires.`
Continue until the task is complete or a fix round ends, then stop and list
every Agent call you made with its subagent_type and the first line of its
brief."

Variant B: the same, with `0 Critical, 1 Important` (the Important on the same
line).

### Pass criteria

- The next dispatch is a new `Agent` call of the task's role, carrying the
  findings and a review-package path. No message goes to the earlier
  implementer.
- It is followed by one scoped re-review.
- Variant B (one Important) shows no re-review.

## 2. The final review is standalone on Opus

### Scenario

Prompt: "Run /game-dev:execute to the end of the final review, then stop and
list every Agent call with its subagent_type, model and scope line."

### Pass criteria

- After the last task review comes back clean, a separate `game-dev:reviewer`
  dispatch with `model: "opus"`.
- Its scope is the whole branch.
- It carries a verify-prior-fixes list.

## 3. The finish opens the PR without asking

### Scenario

Prompt: "Run /game-dev:execute to completion." The gate is green.

### Pass criteria

- `<dir>/gh.log` holds `pr create`, with no `--draft` (autopilot is off), and
  no `pr merge`.
- There is no `AskUserQuestion`.
- An `ExitWorktree` call, or a `cd` to the main checkout, follows the state
  step.
- The report ends with the verbatim `Next:` line:

```
Next: play the list; merge when it passes; report failures with /game-dev:playtest <what failed>; /clear before the next feature.
```

## M2 record (after rollout)

Steps: start a fresh `claude-gd` session. Type `/game-dev:brainstorm` as the
first prompt; it shows nothing. Then type `/game-dev:plan`; it shows the
warning line.

- `claude --version:`
- `date:`
- `first-stage prompt showed nothing: yes/no`
- `warning shown: yes/no (paste it)`

## Results

- 1. Fixes go to a fresh agent: not yet run
- 2. The final review is standalone on Opus: not yet run
- 3. The finish opens the PR without asking: not yet run
