# omega Global Skills — Progress

An evolution log for the `omega` global plugin in omega-ai. Newest entry
first. Specs live in `specs/`, implementation plans in `plans/`, and the
pressure scenarios each skill was tested against — with the baseline and
the with-skill result — in `pressure/`.

## Milestones

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | `shared/omega` plugin manifest, `bin/omega-mode`, SessionStart / UserPromptSubmit / SessionEnd hooks, root `marketplace.json`, two-plugin shim in `install.sh`, `doctor.sh` global plugin line, `tests/omega_test.sh`, five skill stubs | delivered |
| 2 — Skills | `handoff`, `parallel`, `local-merge`, `integration`, `autopilot`; text contracts under `tests/omega_contracts/`; pressure scenarios under `pressure/`; README "Global skills" | delivered |

## Log

### 2026-09-13 — Plan 2 (Skills) delivered

- Five skills replace the stubs, each opened by `omega-mode set` (the mode
  skills) and carrying the precedence contract.
- Each skill was run against a throwaway repository without the skill
  (baseline), then with it; results in `pressure/<skill>.md`.
- Text contracts: `tests/omega_contracts/<skill>_contract.sh`, run by
  `tests/omega_test.sh`.
- Plan: `plans/2026-09-13-plan-2-skills.md`.

### 2026-09-13 — Plan 1 (Foundation) delivered

- `shared/omega` loads through a second `--plugin-dir` in every shim; copy
  mode snapshots it to `<target>/global`.
- `omega-mode` owns the mode file; the hooks print `Omega modes:` while any
  mode is set and clean up at session end.
- Plan: `plans/2026-09-13-plan-1-foundation.md`.

### 2026-09-13 — Design approved

- Spec: `specs/2026-09-13-global-skills-design.md` — five overlay skills
  under the `omega` prefix, loaded by every studio and installable into
  plain `claude` through the marketplace manifest.
