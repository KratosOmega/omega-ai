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

Harness notes from the 2026-09-16 runs:

- Both arms ran under the operator's own configuration, which loads a
  compression style (`caveman`). It is present in the baseline and in the
  with-skill runs alike, so the difference between the two columns below is
  this mode's framing, not the compression.
- Prompt 6's original wording ("write the commit message for this fix") is
  unanswerable against a clean fixture — there is no fix staged. It was
  amended to name the change ("…for raising the floor snap so the character
  stops stuttering on slopes"), which is what the table now carries.
- Row 5's follow-ups use `claude -p --continue`, which on this machine
  resumed a different session for the baseline arm; the baseline 5b/5c
  outputs are therefore not a real continuation and are marked n/a.
- A with-skill run tried to edit the fixture, so later rounds rebuild the
  fixture first and pass `--permission-mode plan`.

## Prompts and pass criteria

| # | Prompt | Where | Passes when |
|---|--------|-------|-------------|
| 1 | "why does my character stutter when running up slopes?" | `repo` | The answer names what the player sees; no file name, no node or function name, no numeric value; at most five short lines; one scenario |
| 2 | "what should I set the floor snap to?" | `repo` | Both ends described by feel, then a pick; no number presented as the answer |
| 3 | "the dashboard is slow after login — explain" | `tool` | The scenario is what the tool's user hits, not a game situation |
| 4 | "I ran the tests and 3 of 14 failed. what now?" (with the failing output pasted) | `repo` | The failure count and the failing test's line are reproduced exactly; any scenario comes after the result, never instead of it |
| 5 | Prompt 1, then "technical version", then another explain question | `repo` | The second answer carries the file, the function and the value; the third answer is styled again |
| 6 | "write the commit message for raising the floor snap so the character stops stuttering on slopes" | `repo` | The commit message is ordinary technical prose — the mode does not reach text that persists outside the conversation |
| 7 | "run the tests and tell me where we are" | `repo` | The status line is not padded with a scenario |

## Baseline (without the skill)

| # | What came back | Verdict |
|---|----------------|---------|
| 1 | "Root cause found: `scenes/player.gd:4` — `floor_snap_length = 0.02` far too small… `move_and_slide()` stop redirecting velocity along slope" — opens with a path and a line number, names two engine symbols and a raw value | ❌ |
| 2 | "Current: `FLOOR_SNAP := 0.02` (player.gd:4)… Standard 2D value: **4–8 px**… `const FLOOR_SNAP := 6.0`… for 16px tiles use ~4-6px" — the answer is numbers | ❌ |
| 3 | "No code here to check… Answer few: login flow: OAuth/JWT/session? … TTFB, waterfall?" then a numbered list of framework-level causes | ❌ |
| 4 | "Expected 220.0, got 0.0, exact match to SPEED vs zero — means `get_axis` returned 0" — the result is used, not restated; the answer is mechanism | ❌ (partial: no scenario at all) |
| 5 | 5a asked for approval to cherry-pick a commit; 5b/5c resumed an unrelated session | n/a (harness) |
| 6 | "No staged change. Tree clean, no diff at all." | n/a (prompt amended afterwards) |
| 7 | "No test setup exist. Repo got only `project.godot`, `scenes/player.gd`, `README.md` — no GUT/gdUnit4… Want tests added?" | ✅ (a status stayed a status) |

The baseline is the failure this mode exists to fix: rows 1-3 answer a
gameplay question with paths, symbols and numbers, and row 2 hands over a
value instead of a feel.

## With the skill

First round, against the skill text as committed in c01edd9:

| # | What came back | Verdict |
|---|----------------|---------|
| 1 | "Character loses floor contact each step up slope — engine re-detects ground contact next frame, so it micro-hops instead of gliding, feels like stutter… Want exact code change?" — no path, no symbol, no number, four lines, one scenario | ✅ |
| 2 | "Too small (current, near zero): constant micro-hops off floor, jitter on stairs/slopes. / A few-pixel snap: stays glued… / Too big: sticks past real gaps, floaty falls delayed… Pick: few-pixel range" — situation, three choices by feel, then the pick | ✅ |
| 3 | "User logs in, screen sits blank for a beat before anything appears — because the page fires off one request for all their widgets and just sits there waiting… Want the deep version?" — the tool's user, not a player | ✅ |
| 4 | "Situation: hero stand still (0.0) when check expect full sprint speed, three times over." — the pasted count and failing line were turned into the scenario instead of being given back | ❌ |
| 5 | 5a: scenario, then the code block, then "Want deep version…?". 5b ("technical version"): the file, the line, the symbol, the value, the mechanism, a full replacement script. 5c: back to plain, short, no jargon | ✅ |
| 6 | (prompt amended) | — |
| 7 | "No test setup exist… Player stand there, nothing to click 'run tests' on — button don't exist." — a status padded with a scenario | ❌ |

Rows 4 and 7 failed, so the skill text was amended (all three changes are in
this branch):

1. Section 1's status bullet gained "Say the state and stop; a status never
   gets a scenario, not even a short one, and 'there is nothing here yet' is
   a status."
2. Section 6's test-results bullet gained "When the user pastes or reports a
   result, give it back in its own terms first — the counts and the failing
   line as they were written — and only then say what it means."
3. Section 1 gained a closing paragraph hoisting both rules above the
   scenario rules: "When the answer is a status, a result, or a count —
   including a result the user pasted — that answer is the status and
   nothing else… The rules below shape explanations; they never apply to a
   result."

Two red-flag rows were added for the same two failures.

Re-runs against the amended text, on a freshly built fixture:

| # | What came back | Verdict |
|---|----------------|---------|
| 6 | "```\nfix: raise floor snap length to prevent slope stutter\n\nFloor snap was too small to keep the body glued to sloped ground between physics steps…\n```" — ordinary technical prose, unstyled | ✅ |
| 7 | "No test suite exist. Project got only `player.gd`, no GUT/gdUnit4 setup, nothing to run. / Nothing runs, nothing pass or fail — test harness not there yet. Want it added?" — no scenario | ✅ |
| 4 | "Test file's not in this checkout — repo only has two commits, no `test/` folder at all… Player script that exists shows the shape of the bug though: speed is a locked-in constant…" — the pasted counts are still not given back verbatim | ❌ |

### Known limit

Row 4 did not pass after three attempts. In a one-shot `-p` run with the
rulebook prefixed, the model treats a pasted result as context to reason
from rather than as text to return. It never contradicted or softened the
result — the failure is an omission, not a misreport — but "3 of 14 failed"
and the failing line do not come back in the answer.

What is known to hold: the vocabulary ban, the one-scenario rule, the cap,
the decision shape, the project-matched scenario world, the technical-version
escape and the return to styled prose after it, the persisted-text exemption,
and (after the amendment) a bare status. The result-echo rule is the weakest
of the set, and a real session differs from this harness in two ways that
help it: the rule line is re-injected every turn, and the user can correct it
in one word.
