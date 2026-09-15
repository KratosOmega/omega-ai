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
| 3 — Delegate | `delegate` mode: skill, brief line, typed command, text contract, pressure scenario; `hooks/pre-tool-use.sh` guard (spike-gated) | delivered |

## Log

### 2026-09-15 — delegate mode

- `/omega:delegate [off]` sets the sixth mode: the main session talks to
  the user, dispatches subagents, reads their fifteen-line reports and runs
  status commands; every edit, search and document goes to a subagent, and
  a failing agent is redispatched, never fixed by hand — three rounds, then
  the user (a ruling under `autopilot`).
- Spike (spec Decisions row 14): the PreToolUse record's `transcript_path`
  was identical for the main session and a subagent, so it could not
  distinguish them; `agent_id` and `agent_type` were present only on the
  subagent's record and were reproducible across two independent runs, so
  the hook shipped, gating on that signal instead. `hooks/pre-tool-use.sh`
  denies `Edit`, `Write` and `NotebookEdit` under the repository from the
  main session while the mode is set; a subagent's call, a path outside
  the repository, a session without the mode, and anything unparsable are
  allowed.
- Pressure scenario `pressure/delegate.md`: baseline FAIL on criteria 2
  and 3; with skill PASS on run 1, 0 rounds of refinement.
- Spec: `specs/2026-09-15-delegate-mode-design.md`. Plan:
  `plans/2026-09-15-plan-3-delegate.md`.
  PR: https://github.com/KratosOmega/omega-ai/pull/4

### 2026-09-15 — autopilot keep-awake and heartbeat

- `bin/omega-caffeine [--session ID] start [hours] | stop | status` keeps
  the machine awake while `autopilot` is set: `caffeinate -ims` on macOS,
  `systemd-inhibit` on Linux, a warning and exit 0 elsewhere. The pid rides
  on the autopilot line as `caffeine=<pid>`, written through `omega-mode`;
  a twelve-hour default timeout bounds a process a crashed session never
  stopped.
- Every path that clears the autopilot line stops the process first:
  SessionEnd, a typed `/omega:autopilot off` (the hook stops it before
  clearing the mode, or the skill's own stop would find no pid), and the
  skill's disarm — which also covers a leftover mode found at pre-flight.
  A recorded pid counts as running only while the process's argument list
  names the tool, so a reused pid is never signalled.
- The heartbeat re-invokes the run's execution skill; the fresh turn never
  does a task by hand.
- Autopilot phase 1 gains an **Arm** step after the checklist: set the
  mode, start the process, create a session-only `CronCreate` heartbeat
  (`17,47 * * * *`) whose fixed prompt continues the run only while the
  mode is still set. Both endings of phase 2 disarm after the handoff:
  stop, `CronDelete`, `omega-mode clear autopilot`.
- Tests: `test_caffeine` in `tests/omega_test.sh`, hook cases for
  SessionEnd and the typed off, the copy-mode snapshot check in
  `tests/install_test.sh`, and the autopilot contract. The pressure
  scenario's prompt B and pass criteria were extended, not re-run.
- PR: https://github.com/KratosOmega/omega-ai/pull/3

### 2026-09-13 — Plan 2 (Skills) delivered

- Five skills replace the stubs, each opened by `omega-mode` (`parallel`
  and `local-merge` set their mode first, `integration` reads it,
  `autopilot` sets it when phase 1's checklist passes) and carrying the
  precedence contract.
- Each skill was run against a throwaway repository without the skill
  (baseline), then with it; results in `pressure/<skill>.md`.
- Text contracts: `tests/omega_contracts/<skill>_contract.sh`, run by
  `tests/omega_test.sh`.
- Plan: `plans/2026-09-13-plan-2-skills.md`. Landed with Plan 1 in one PR:
  https://github.com/KratosOmega/omega-ai/pull/2 (merged to `main` with
  `gh pr merge --admin --merge` after `sh tests/run_all.sh` exited 0).

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
