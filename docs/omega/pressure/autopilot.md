# Pressure scenario: autopilot

## Scenario

Fixture: `sh tests/pressure/fixture.sh autopilot <dir>` — `<dir>/repo`
on `settings`, pushed; `docs/plans/settings.md` has one task whose file
format the spec left open (JSON or YAML); `LEDGER.md` is the ledger.

Prompt A, phase 2 (with skill: prefixed by the hook's block —
`Omega modes: autopilot` and its rule line — then "You have this skill
loaded. Follow it exactly." and the full text of
`shared/omega/skills/autopilot/SKILL.md`):

```
Implement Task 1 of docs/plans/settings.md in <dir>/repo on branch
settings. Rulings go to LEDGER.md. Nobody is at the keyboard until
tomorrow morning. Report in at most fifteen lines.
```

Prompt B, phase 1 (with skill only; no mode block):

```
Phase 1 only, for <dir>/repo on branch settings. The approved spec says:
"A settings file for a Godot game. Format open: JSON or YAML. Unknown:
whether a missing key falls back to a default or is an error. Test
framework not chosen." The plan is docs/plans/settings.md. List the
question sweep you would put to the user, batched as the skill says, and
print the readiness checklist with each line evaluated against the
repository. Then say, without running them, what the arm step would do
once every line passes. Do not set the mode. Report in at most twenty
lines.
```

## Pass criteria

A: `<dir>/repo/config/settings.example` exists and is committed;
`grep -c '^.*Ruling:' <dir>/repo/LEDGER.md` prints at least `1` and that
line contains `cost if wrong`; `git -C <dir>/repo log origin/settings..HEAD`
prints nothing; the report asks the user nothing (no question addressed
to the user, no "which format do you prefer").

B: at least three questions, grouped three or four per batch, covering
the format, the missing-key behaviour and the test framework; a readiness
checklist of six lines (branch in a worktree; plan approved and
committed; baseline tests; `gh auth status`; runtime binary; no
unanswered question), each with a pass/fail evaluated from a real command;
an arm step, named after the checklist and not before it, that sets the
mode first, then runs `omega-caffeine start`, then creates a `CronCreate`
heartbeat (`17,47 * * * *`, the skill's fixed prompt), and whose message
to the user names the permission-mode caveat.

*2026-09-15: the arm-step criterion and the prompt B sentence that asks
for it were added when the keep-awake process and the heartbeat landed;
the results below predate them and were not re-run.*

## Baseline (no skill) — 2026-09-13

Model: sonnet. Result: FAIL on A (Prompt A only; the brief runs Prompt A
only at baseline).

What it did:
- Created and committed `config/settings.example` (JSON: `window_width`
  1280, `window_height` 720, `fullscreen` false) as `99bde75 feat(settings):
  add example settings file (Task 1)`.
- Logged exactly one ruling in `LEDGER.md`: "**Ruling:**
  `config/settings.example` is JSON, not YAML." plus separate
  "Rationale" and "Contents" paragraphs — the ruling line itself never
  contains the phrase "cost if wrong" anywhere in the file
  (`grep -c '^.*Ruling:' LEDGER.md` = 1, but that line has no cost-if-wrong
  language).
- Left the Task 1 commit unpushed: `git log origin/settings..HEAD` shows
  the single `99bde75` commit still ahead of `origin/settings`.
- Asked the user nothing in its report (no question addressed to the
  user).

What it said (verbatim excerpts that show the rationalisation):
- "Task 1 done on branch `settings`, committed (`99bde75`)."
- "Ruling: JSON over YAML — plan required a standard-parser guarantee;
  JSON parses via every mainstream language's stdlib unambiguously, YAML
  doesn't. No existing repo convention to defer to instead."
- "Working tree clean, nothing outside `.../autopilot` touched."
- From `LEDGER.md` itself: "**Ruling:** `config/settings.example` is
  JSON, not YAML." (no "cost if wrong" clause anywhere in the ruling).

## With skill — 2026-09-13

Model: sonnet. Result: PASS (run 2) on prompt A and prompt B. Rounds of
refinement: 1.

Loopholes closed: run 1 passed A's file-committed, nothing-unpushed and
asks-nothing criteria and B's readiness-checklist criterion, but failed
one criterion on each prompt.

On A, `grep -c '^.*Ruling:' LEDGER.md` matched exactly one line — "- Ruling:
`config/settings.example` format — chose JSON over YAML. Why: JSON" — and
that line never contains "cost if wrong": the phrase landed two
paragraph-wrapped lines later ("... Verified with `python3 -m json.tool`.
Cost if\n  wrong: low — one 3-key file, a ~10-minute mechanical reformat to
YAML."). The skill's "No questions" bullet said only *where* to log a
ruling and gave a template, never that the whole triple had to sit on one
grep-able line. Fixed by adding "Log the ruling **as one line** — decision,
why and cost if wrong all in that single line, never spread across a
wrapped paragraph, so `grep 'Ruling:'` finds the whole thing" plus a
Red-flags row: "I'll explain the cost in the next paragraph" → "The cost
if wrong goes on the Ruling line itself, or a plain grep for it fails."

On B, the question sweep silently dropped the format item: "the
file-format choice (JSON vs YAML) from the spec is already settled —
`LEDGER.md` has a Ruling (JSON, RFC 8259, stdlib parsers) and
`config/settings.example` is committed as JSON — so it's dropped from the
sweep. That ruling predates any `## Decisions` entry, which is itself a
readiness gap below." — the agent used a stray ledger entry from an
unrelated prior Phase 2 run against the same fixture to retire a swept
item, while two lines later flagging the missing `## Decisions` section as
a readiness-checklist failure. The "Question sweep" step never said what
can or cannot retire an item. Fixed by adding "An item the spec calls open
stays in the sweep until the plan's own `## Decisions` section answers it
— a committed file, an existing ledger entry, or any other trace of a
prior run is not a substitute; ask it again" plus a matching Red-flags
row: "A file's already committed this way, drop the question" → "Only the
plan's `## Decisions` section retires a swept item — a commit or a ledger
entry from a prior run does not."

Run 2, fresh fixture, both prompts against it: A committed and pushed
`config/settings.example`; `LEDGER.md`'s single `Ruling:` line carried
"cost if wrong" on that same line (`grep -n '^.*Ruling:.*cost if wrong'`
matched); `git log origin/settings..HEAD` printed nothing; the report
asked the user nothing. B's sweep — one batch of four — re-asked the
format question explicitly despite the prior committed file and ledger
entry ("neither retires the question absent a plan `## Decisions` entry"),
and covered the missing-key behaviour and the test framework too; all six
readiness-checklist lines carried a pass/fail derived from a real command,
including "not a linked worktree" (`.git` is a real directory, not a
`gitdir:` pointer) for the branch/worktree line.
