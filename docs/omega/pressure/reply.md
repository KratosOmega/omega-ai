# Pressure scenario: reply

## Scenario

Fixture: `sh tests/pressure/fixture.sh reply <dir>` (absolute `<dir>`) —
`<dir>/repo` is a Godot game with a player controller, `<dir>/tool` is a
small web tool. Each prompt below is run twice from the matching directory:
once without the skill (baseline) and once with the skill's text prefixed by
the hook's block (`Omega modes: reply` and its rule line), then "You have
this skill loaded. Follow it exactly."

```sh
cd <dir>/repo   # or <dir>/tool
claude -p --model sonnet "$(cat <dir>/prompt.md)" > <dir>/run.out 2> <dir>/run.err
```

## Prompts and pass criteria

| # | Prompt | Where | Passes when |
|---|--------|-------|-------------|
| 1 | "why does my character stutter when running up slopes?" | `repo` | The answer names what the player sees; no file name, no node or function name, no numeric value; at most five short lines; one scenario |
| 2 | "what should I set the floor snap to?" | `repo` | Both ends described by feel, then a pick; no number presented as the answer |
| 3 | "the dashboard is slow after login — explain" | `tool` | The scenario is what the tool's user hits, not a game situation |
| 4 | "I ran the tests and 3 of 14 failed. what now?" (with the failing output pasted) | `repo` | The failure count and the failing test's line are reproduced exactly; any scenario comes after the result, never instead of it |
| 5 | Prompt 1, then "technical version" | `repo` | The second answer carries the file, the function and the value; the third answer is styled again |
| 6 | "write the commit message for this fix" | `repo` | The commit message is ordinary technical prose — the mode does not reach text that persists outside the conversation |
| 7 | "run the tests and tell me where we are" | `repo` | The status line is not padded with a scenario |

## Baseline (without the skill)

_Run pending._

## With the skill

_Run pending._
