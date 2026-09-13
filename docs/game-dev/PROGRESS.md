# game-dev Studio — Progress

An evolution log for the game-dev studio in omega-ai. Newest entry first.
Specs live in `specs/`, implementation plans in `plans/`, and the HTML of every
approval page in `artifacts/`.

## Milestones

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | `profiles/` → `studios/`, plugin packaging, shim with `--plugin-dir`, installer/doctor/tests, session hook, `docs/game-dev/`, `.studio/STATE.md`, skills `studio` `brainstorm` `plan` `execute` | delivered — exit criterion (Task 12 manual run) pending |
| 2 — Quality loop | Ten role agents, skills `review` `playtest` `ship` `retro`, `bin/` verbs with the Godot adapter, optional `godot-mcp`, doctor delegation check | planned |
| 3 — Content | `scaffold` and template project, domain skills (migrate four, add `vertical-slice` `tuning-data` `milestone-gates`), `PROGRESS.md` conventions, `general` studio parity, skill pressure tests | planned |

## Log

### 2026-09-13 — Plan 1 review fixes

- Installer: input validation before reinstall, symlink-safe writes, purge
  requires a manifest, canonical target, manifest header (`mode`, `shim`),
  doctor shim identity / copy-mode inspection / stale-layout / canonical
  leak check.
- State: pointer local and resolved to the main checkout, per-feature
  ledgers committed with the branch, `studio-state check` / `reset`,
  PreToolUse guard.
- Skills: agents renamed and wired, godot-prompter agents interim, verify
  lists, smoke boot, no merge path from execute.
- Plan: `plans/2026-09-13-plan-1-review-fixes.md`. The Plan 1 exit
  criterion (spec §Success criteria 4) is a manual run from the main
  checkout after merge; it has not been run yet.

### 2026-09-13 — Plan 1 (Foundation) delivered

- `profiles/` became `studios/`; each studio is a Claude Code plugin loaded
  live through the shim's `--plugin-dir`.
- Installer, uninstaller, doctor and tests updated; reinstall cleans stale
  entries; doctor checks `requires.txt` against `settings.json` and the
  plugin cache.
- Session hook, `studio-state`, and the stage skills `studio`, `brainstorm`,
  `plan`, `execute`.
- Plan: `plans/2026-09-13-plan-1-foundation.md`.

### 2026-09-13 — Design approved

- Design reviewed and approved as an artifact:
  https://claude.ai/code/artifact/ca2bdd14-6d92-4ad8-99b6-fe455190fb0d
  (local copy: `artifacts/2026-09-13-game-studio-design.html`).
- Spec written: `specs/2026-09-13-game-studio-design.md`.
- Implementation plans written and committed:
  `plans/2026-09-13-plan-1-foundation.md` (12 tasks),
  `plans/2026-09-13-plan-2-quality-loop.md` (16 tasks),
  `plans/2026-09-13-plan-3-content.md` (12 tasks).
  Plans 2 and 3 were written in parallel from the spec and reconciled
  (GUT pin `v9.6.1`, first-run `--import` in the Godot adapter).
- Next: execute Plan 1, subagent-driven.
