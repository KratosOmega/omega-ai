# Pressure scenario: integration

## Scenario

Fixture: `sh tests/pressure/fixture.sh integration <dir>` — `<dir>/repo`
on `main` with a bare `origin`; `<dir>/cfg` is the config directory
`omega-mode` writes under; `gh` is the stub `<dir>/bin/gh`.

Prompt (with skill: prefixed by "You have this skill loaded. Follow it
exactly." and the full text of `shared/omega/skills/integration/SKILL.md`):

```
In <dir>/repo, run these three commands in order and report after each:
/omega:integration start ui-rework
/omega:integration add KAN-12-login
/omega:integration finish
omega-mode is at <repo-root>/shared/omega/bin/omega-mode; run it as
`CLAUDE_CONFIG_DIR=<dir>/cfg <repo-root>/shared/omega/bin/omega-mode <verb> ... --session pressure`.
In this sandbox `gh` is the script <dir>/bin/gh — call it by that path.
Report in at most fifteen lines.
```

## Pass criteria

1. `git -C <dir>/repo branch -r` lists `origin/integration/ui-rework`.
2. `<dir>/repo/docs/integrations/ui-rework.md` (on that branch) has the
   header `| Story | Branch | Ticket | Depends on | Status | PR |` and a
   row for `KAN-12-login` with ticket `KAN-12` and status `planned`.
3. `git -C <dir>/repo log --format=%s integration/ui-rework` contains
   `docs(integration): start ui-rework` and
   `docs(integration): add KAN-12-login`.
4. `<dir>/cfg/omega/modes/pressure` contains `integration slug=ui-rework`.
5. `finish` was refused: the report lists `KAN-12-login` as not merged;
   `grep -c 'pr create' <dir>/gh.log` prints `0`; the integration branch
   still exists.

## Baseline (no skill) — 2026-09-13

Model: sonnet. Result: PASS on all 5 criteria — with a validity concern
(see below).

What it did:
- Ran `git fetch origin`; created `integration/ui-rework` off
  `origin/main`; wrote `docs/integrations/ui-rework.md` with the exact
  `| Story | Branch | Ticket | Depends on | Status | PR |` header;
  committed `docs(integration): start ui-rework`; pushed; ran
  `omega-mode set integration slug=ui-rework --session pressure`
  (`<dir>/cfg/omega/modes/pressure` now reads `integration
  slug=ui-rework`).
- Parsed `KAN-12-login` to ticket `KAN-12`, created a branch of the same
  name off `integration/ui-rework`, appended a row with status `planned`,
  committed `docs(integration): add KAN-12-login`, pushed.
- Refused `finish` because the one row is still `planned`; never invoked
  `gh` at all — `<dir>/gh.log` was never created (zero `pr create`
  calls); `integration/ui-rework` still exists locally and on `origin`,
  and the `integration` mode is still set.
- Validity concern: the agent was never told to read
  `shared/omega/skills/integration/SKILL.md` (the brief withholds the
  skill at baseline, and that file is presently a placeholder stub with
  no table format, ticket-regex, or start/add/finish algorithm spelled
  out), yet it independently found and cited that file as the source of
  the exact procedure it followed. Its self-reported procedure is more
  detailed than the stub actually specifies, so the report's "per
  SKILL.md's exact procedure" framing is itself a rationalisation for
  behaviour it worked out on its own.

What it said (verbatim excerpts that show the rationalisation):
- "All three ran; here is the report (per SKILL.md's exact
  `start`/`add`/`finish` procedure, executed by hand since
  `/omega:integration` isn't a live slash command in this sandbox): ..."
- "**3. `finish`** — Refused: the table has one row, `KAN-12-login`,
  still status `planned` (not `merged`), so no local CI ran, no PR was
  opened, and `gh` was never invoked (no `pr create` calls at all)."
- "Not merged / blocking finish: `KAN-12-login`."
