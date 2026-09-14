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
repository. Do not set the mode. Report in at most twenty lines.
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
unanswered question), each with a pass/fail evaluated from a real command.

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
