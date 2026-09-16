# game-dev Studio — Progress

An evolution log for the game-dev studio in omega-ai. Newest entry first.
Specs live in `specs/`, implementation plans in `plans/`, and the HTML of every
approval page in `artifacts/`.

## Milestones

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | `profiles/` → `studios/`, plugin packaging, shim with `--plugin-dir`, installer/doctor/tests, session hook, `docs/game-dev/`, `.studio/STATE.md`, skills `studio` `brainstorm` `plan` `execute` | delivered — exit criterion (Task 12 manual run) pending |
| 2 — Quality loop | Ten role agents, skills `review` `playtest` `ship` `retro`, `bin/` verbs with the Godot adapter, optional `godot-mcp`, doctor delegation check | delivered — exit criterion (Task 16 manual run) pending |
| 3 — Content | `scaffold` and template project, domain skills (migrate four, add `vertical-slice` `tuning-data` `milestone-gates`), `PROGRESS.md` conventions, `general` studio parity, skill pressure tests | planned |

## Log

### 2026-09-15 — Plan 2 (Quality loop) delivered

- Ten role agents under `studios/game-dev/agents/`; `2d-art-pipeline` and
  `game-feel-tuner` migrated to `tech-artist` and `feel-tuner`.
- Stage skills `review`, `playtest`, `ship`, `retro`; `execute`,
  `brainstorm` and `plan` now dispatch the studio's own agents.
- `studio-test`, `studio-run`, `studio-lint` through `studio-dispatch` and
  the Godot adapter in `engines/godot/`.
- Optional `godot-mcp` registration inside the config root; doctor reports
  the engine, the MCP server, and resolves every delegated skill and agent.
- Plan: `plans/2026-09-13-plan-2-quality-loop.md`. The Plan 2 exit
  criterion (Task 16 manual run) is a manual verification pass; it has not
  been run yet.
- Task 16 Steps 1-2 (reinstall, doctor) verified 2026-09-15: reinstall
  registered `godot-mcp` inside the config root and nowhere else
  (`grep -c godot ~/.claude-gamedev/.claude.json` = 12; `grep -c godot-mcp
  ~/.claude.json` = 0; manifest's last line `mcp godot`); doctor exits 0
  with `superpowers: 8 of 8 resolved`, `godot-prompter: 35 of 35
  resolved`, the engine at
  `/Applications/Godot_mono.app/Contents/MacOS/Godot`, `mcp: godot
  registered`, `shim on PATH: yes`, `leakage: none`.
- Task 16 Step 3 verified 2026-09-16, in a throwaway worktree of the
  phoenix Godot project (Godot 4.6.3 mono, GUT 9.6.0), branch
  `KAN-1257-dash-freeze-timescale`: `studio-test` →
  `studio-test: 15737 passed, 0 failed`, exit 0, confirmed independently
  against the JUnit XML the adapter wrote (`<testsuites name="GutTests"
  failures="0" tests="15737">`); `studio-run --seconds 5` → the engine
  banner (`Godot Engine v4.6.3.stable.mono.official.7d41c59c4`) then
  `studio-run: clean (5s, .studio/reports/run-20260916-002530.log)`, exit
  0; `studio-lint` → `studio-lint: gdtoolkit is not installed. Install it
  with: pip install "gdtoolkit==4.*"`, exit 3 — the documented path, since
  `gdlint`/`gdformat` are absent on this machine; `studio-test` with
  `addons/gut` temporarily moved aside → printed the `Install:` line
  verbatim from `engines/godot/GUIDE.md`, exit 3, as documented,
  `addons/gut` then restored.
- Finding: on a project this size the run is slow — `studio-test` took
  roughly 46 minutes of wall clock (started 23:39, reports written 00:25)
  because the Godot adapter runs `-gdir=res://tests -ginclude_subdirs`,
  which sweeps phoenix's `e2e` suite as well as its unit tests, on a cold
  `.godot/` import cache. Step 3's wording assumes a quick summary line;
  that holds for a small project, not for a large one — an observation
  about the verb's cost on a large project, not a defect.
- Task 16's own text carried four stale or impossible expectations, now
  corrected in commit `81e6c217b40a15a6464025c799319fb271ee93b8`: the
  doctor's skill count (8 → 12), the spec heading count (eight → the
  brainstorm template's own headings, really 18), an unmentioned
  `studio-state init` gate in a fresh project, and — the one that would
  actually have blocked a verifier — a closing check that read the eight
  ledger phrases out of `.studio/STATE.md`, when `studio-state` writes
  them to `.studio/ledger/<feature>.md` whenever a spec is set and
  `retro` clears the spec before the check runs.
- Step 4 (the artifact §5 session through `claude-gd`) and Step 5 remain
  outstanding, so the Plan 2 exit criterion is not yet met.

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
