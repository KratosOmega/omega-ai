# omega Global Skills — Progress

An evolution log for the `omega` global plugin in omega-ai. Newest entry
first. Specs live in `specs/`, implementation plans in `plans/`.

## Stories

| Story | Scope | Plan | Status |
|-------|-------|------|--------|
| Foundation | `shared/omega` plugin manifest, `omega-mode`, the three hooks, marketplace manifest, installer and doctor changes, `tests/omega_test.sh` | 1 | delivered |
| handoff | `/omega:handoff`: safe stop, commit and push, handoff file, resume prompt | 2 | planned |
| parallel | `/omega:parallel [N]`: wave table, per-task worktrees, cherry-pick integration | 2 | planned |
| local-merge | `/omega:local-merge`: local CI, `gh pr merge --admin`, strategy detection | 2 | planned |
| integration | `/omega:integration`: integration branch, story table, finish | 2 | planned |
| autopilot | `/omega:autopilot`: question sweep, story update, unattended rules | 2 | planned |

## Log

### 2026-09-13 — Plan 1 (Foundation) delivered

- `shared/omega/` is a Claude Code plugin named `omega`; every studio shim
  passes it as a second `--plugin-dir` and puts its `bin/` on `PATH`; copy
  mode snapshots it to `<target>/omega`.
- `omega-mode` writes the per-session mode file under the config root;
  `session-start.sh`, `prompt-submit.sh` and `session-end.sh` inject the
  `Omega modes:` block, act on typed `/omega:*` commands, and delete the
  file when the session ends.
- `.claude-plugin/marketplace.json` publishes the plugin for plain `claude`.
- Five skill stubs carry their frontmatter, the `omega-mode` step and the
  precedence contract; the procedures are Plan 2.
- Plan: `plans/2026-09-13-plan-1-foundation.md`.

### 2026-09-13 — Design approved

- Spec: `specs/2026-09-13-global-skills-design.md`.
- Plans: `plans/2026-09-13-plan-1-foundation.md`,
  `plans/2026-09-13-plan-2-skills.md`.
