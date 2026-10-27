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

### 2026-10-27 — Automatic run cleanup: a run whose work is confirmed merged closes itself

- Incident (phoenix, 2026-10-27): three runs stayed open as "Resume <slug>" options although all their work had merged into main. m59-copy-rect (PR #1983) and bat-swoop-refine (PR #2009) were landed by hand, so `landed.tsv` stayed empty; mob-group-attacks landed both stories through the runner, but its progress PR failed its gate and #1989 was landed by hand. Only `lanes_finish done` and `runs_settle` (a merged final PR, integration mode only) wrote `done`, so a direct-mode run finished by hand never closed. Even clean runs left their remote branches (story, `run/`, `progress/`, `integration/`), their worktrees, their story pointers, and their Jira issues at To Do (KAN-1739 after a clean wasp-tuner-sync). The report's `## Cleanup` only printed a `git push origin --delete …` line to paste, and the autopilot skill reached Jira only through the Atlassian MCP, while phoenix reaches it through `~/.local/bin/acli`. Plan `plans/2026-10-27-run-cleanup.md`.
- Confirmation (D1): a row is merged when its `landed.tsv` sha is an ancestor of `origin/<Target>`, or when the branch has a MERGED PR into `<Target>` whose merge commit is (squash-aware; the `landed.tsv` line is backfilled from that PR). Integration mode also needs the final PR merged; direct mode (with PROGRESS.md) needs the `docs(progress): <slug>` commit on the target, a row whose landing changed PROGRESS.md (a story's finish writes its own entry: m59-copy-rect, bat-swoop-refine), or the progress PR merged. Always checked against a fresh fetch.
- Cleanup (new `studios/game-dev/bin/overnight-cleanup.sh`, runner shell code, never an agent session): marks the record `done`; removes the run's clean worktrees (run, story, `progress-<slug>`) and their local branches, keeping a dirty one (D9); deletes the run's remote branches, `run/<slug>` after pushing the tag `run-archive/<slug>-<tip12>` (D3); moves each story's Jira issue to Done through `acli` with a comment naming the PR and merge sha, keeping a ticket that an unfinished run shares or that has open children (D7); sets each Multica mirror to done; archives `.studio/stories/<id>.md` into `.studio/stories/done/` (D5). An archived record touches only its story rows (D6). Every step is best effort and idempotent (markers in `.studio/runs/<slug>/`: `cleaned`, `cleanup.state`, `cleanup.log`, `cleanup.tried`; D8), and each external call is capped at `timeout_seconds` (D11).
- Remote deletion is on by default (D4): run-owned names only, after a fresh fetch, only when the tip is in the base (D2), never with an open PR. Agent units still may not delete a remote branch (`overnight-deny.txt` unchanged).
- Triggers: the end of a done run (`lanes_finish done`), the settle sweep of `studio-overnight start` and `status` (retried after `retry_minutes`), and the new `studio-overnight settle [<slug>|--all] [--dry-run]` (`--dry-run` fetches, prints `would:` lines and writes nothing; D12). Config: the `cleanup` object of `.studio/config.json` (D10). The report's `## Cleanup` now says what was done and what is left.
- Skill and docs: the autopilot skill's start message says the runner itself cleans up once every story is confirmed merged, that `studio-overnight settle <slug>` does it after a hand landing, and that a dirty worktree is kept; sessions still never delete a remote branch. Phase 1's Jira story comment goes through `acli` first (`acli jira workitem comment create`), the Atlassian MCP second. README documents the `cleanup` keys and the report section. Tests: `tests/overnight_cleanup_test.sh` (`test_direct_runner_landed`, `test_direct_hand_landed_backfill`, `test_unmerged_story_untouched`, `test_integration_final_merged_or_open`, `test_direct_progress_required`, `test_direct_progress_in_story_landing`, `test_live_run_skipped`, `test_steps_*`, `test_settle_cli`), `tests/overnight_lanes_test.sh` (`test_lanes_direct_progress_landing`, `test_lanes_final_step_once`, `test_lanes_report_every_ending`), and the autopilot contract's `test_autopilot_start_from_run_worktree` and `test_autopilot_jira_acli`.
- Acceptance (phoenix, `settle --all --dry-run`): it names the leftover branches of m59-copy-rect, bat-swoop-refine and mob-group-attacks (each `run/<slug>` tagged first), and the Jira moves of KAN-1730 and KAN-1734…1739. KAN-1723 is kept open by the three done runs that share it while the archived `bat-sonic-followups` record is not done; that record, its four rows merged by hand, is now confirmed and closes KAN-1723 itself. OMEG-144 (a Multica key) is skipped as no Jira issue.
- Final review fixes: a hand-landed row's PR must have the branch's current tip as its head and must have merged after the run's Docs revision (a reused branch's old PR confirmed nothing); a branch another live or not-done record lists, a live run's start dir and the run being started are left alone; a branch's tip is checked before its worktree goes; the progress subject is searched after Docs only; a Jira status in the done category counts as done; `--dry-run` takes no mutex; a sweep fetches once.
- Unchanged: `overnight-deny.txt`; the run never closes a PR; the main checkout is never removed; "No tracker" handling in phase 1; archiving a done record under a UTC timestamp when its slug is reused.

### 2026-10-26 — A unit knows its deadline, a capped task hands off its checkpoint, and a task capped twice reaches a person (defects 1-11)

- Incident (phoenix bat-bite-vfx, story KAN-1723-5, Multica OMEG-131/OMEG-132; mob-group-attacks, OMEG-134): 5 of the story's 16 units were killed at the 90-minute cap, on T2 (twice), T3 (once) and T12 (twice). T2's work was done but uncommitted, and its retry started cold and re-measured. T12's was not done; unit 15 committed a real fix and was still recorded `timed out`. All five logged `usd` null (7.5 h of sessions unpriced), and the operator unstuck both tasks by hand with `say` + `resume`, then had to `unsay` the T2 handoff, which contradicted T12 and used up `directive_chars`. In mob-group-attacks (direct mode) the finish ran no full gate, so merge.sh's first full run went red at landing and spent the story's one landing repair; the machine's omega-ai checkout was also 8 commits behind a fix the run needed. Spec `specs/2026-10-26-unit-deadline-and-carryover.md`, plan `plans/2026-10-26-unit-deadline-and-carryover.md`.
- Fix 1 (carry-over): a task unit near its cap commits its green fixes, writes `T<n> checkpoint: done …; left …; next …` (`final-review checkpoint:` for the final review) and ends. `studio-brief task` shows the newest one, via the shared `bin/checkpoint.awk`; the hold message carries it. A unit that wrote none gets a runner fallback note built from git and the killed transcript. A capped unit that pushed commits of its own is the new outcome `partial` (progress, resets `noprog`); a stall is never a cap; a ledger-only sync commit is not progress. Tests: `test_lanes_checkpoint_reaches_retry`, `test_lanes_commit_then_killed_is_partial`, `test_overnight_partial_resets_noprog`, `test_overnight_unpushed_commit_stays_timed_out`, `test_overnight_stall_past_wrap_not_capped`, `test_overnight_docs_sync_commit_not_partial`, `test_lanes_fallback_note_without_checkpoint`, `test_lanes_checkpoint_judged_in_own_checkout`, `test_brief_task_checkpoint_part`, `test_brief_checkpoint_unesc_and_cut`, `test_brief_missing_checkpoint_awk`, `test_skill_execute_checkpoint`.
- Fix 2 (deadline): every unit kind gets `STUDIO_UNIT_DEADLINE` and `STUDIO_UNIT_WRAP_AT` (deadline less `max(600, secs/6)` s, at most half the session). New `bin/studio-deadline` (`fits <gate>|agent`); the operator-inbox hook tells the session and its subagents to wrap up at the wrap time; execute §0 starts no gate or subagent that does not fit, §4a commits each green fix as it lands. The Step 1 probe `tests/probes/deadline_notice_probe.sh` ran once: PASS, a subagent receives a PostToolUse hook's `additionalContext`. Tests: `test_overnight_deadline_exported`, `test_overnight_deadline_small_session`, `test_lanes_deadline_every_unit_kind`, `test_overnight_wrap_capped_unit`, `test_deadline_left_and_wrap`, `test_deadline_fits_from_history`, `test_deadline_fits_few_rows`, `test_deadline_fits_agent`, `test_deadline_outside_a_unit`, `test_inbox_wrap_notice_once`, `test_inbox_wrap_notice_subagent`, `test_inbox_wrap_notice_compact_reshows`, `test_skill_execute_deadline`.
- Fix 3 (cost): a killed unit's `usd` is estimated from its transcript with per-model prices (`bin/model-prices.tsv`, calibrated per model, default factor 1.3; minutes x $/min when the transcript is empty), flagged `usd_est` in events and `cost_src` in units.tsv (col 8; col 9 `capped`), and counted in the run's spend. Tests: `test_overnight_cost_estimate_killed_unit`, `test_overnight_cost_estimate_helpers`, `test_overnight_cost_estimate_calibrated`, `test_overnight_cost_estimate_empty_transcript`, `test_lanes_report_cost_estimate`.
- Fix 4 (bound): `overnight.task_timeouts` (default 2, range 1-5). A task capped that many times holds with `timed out on T<n> (session_minutes N; <k> capped units) — checkpoint: …` and launches no further retry; `resume` runs one more capped unit; the Multica hold comment names the checkpoint and `/say --task`. Tests: `test_lanes_bound_holds_with_checkpoint`, `test_lanes_bound_resume_one_more`, `test_lanes_partial_counts_toward_bound`, `test_lanes_stop_capped_holds_with_note`, `test_overnight_bound_single_plan`, Multica `test_hold_body_timed_out_task`.
- Fix 5 (plan time): the plan skill's self-review splits a task whose verify does not fit half a session or that loops unbounded (T12 is the worked example). Test: `test_skill_plan_fits_the_session`.
- Fix 6 (`--help`): the usage heredoc no longer expands `$CMD`; `--help` exits 0 with empty stderr and documents the deadline variables, `task_timeouts`, `say --task/--file/-` and `studio-deadline`. Tests: `test_help_exits_clean`, `test_overnight_help`.
- Fix 7 (subagent timeout): the brief carries "pass `timeout` only on gate-routed commands" with the why (a raised timeout lets a hung non-gate command outlive its cap). Test: `test_skill_execute_deadline`.
- Fix 8 (directives): `say --task [T<n>]` lasts until the story's task pointer passes that task (the runner's own handoffs use it); `say --file <path>` and `say -` deliver multi-line text verbatim. Tests: `test_channel_say_task_scope_retires`, `test_channel_say_task_bare_resolves_current`, `test_channel_say_task_refusals`, `test_channel_say_file_verbatim`, `test_channel_say_stdin`, `test_requeue_task_directive_recorded`, `test_requeue_stale_task_not_delivered`, `test_brief_task_directive_scoped`, Multica `test_commands.py` (`/say --task`).
- Fix 9 (direct mode): the finish gate of execute §7 runs in direct mode too (a red is `Stop: gate red`, repaired by `gate_repairs`), and the preflight warns when `merge_command` is set and `gate_command` is not. Tests: `test_lanes_direct_gate_red_repairs`, `test_lanes_preflight_direct_gate_warn`.
- Fix 10 (stale runner): `start` and `--dry-run` warn when the runner's own git checkout is behind its upstream on `studios/game-dev`; they never pull. Test: `test_preflight_runner_behind_warns`.
- Fix 11 (story worktree setup): verified by a test that a fresh story worktree runs the project's `worktree_setup` (#104); no fix needed. Test: `test_setup_fresh_story_worktree_runs_setup`.
- Done-when checks: unit killed after a checkpoint, retry brief holds it = `test_lanes_checkpoint_reaches_retry`; commit then killed = progress = `test_lanes_commit_then_killed_is_partial`; capped N times holds with the checkpoint, no retry = `test_lanes_bound_holds_with_checkpoint`; spend non-null and counted = `test_overnight_cost_estimate_killed_unit`, `test_lanes_report_cost_estimate`; deadline in every unit kind, help and SKILL = `test_lanes_deadline_every_unit_kind`, `test_overnight_help`, `test_skill_execute_deadline`; task-scoped directive retires, `--file` verbatim = `test_channel_say_task_scope_retires`, `test_channel_say_file_verbatim`; defects 9, 10, 11 = the tests above; `--help` clean = `test_help_exits_clean`.
- Final-review fixes: the suites never fetch the real runner checkout's origin (test hook `STUDIO_OVERNIGHT_RUNNER_CHECK=0`, set by `tests/assert.sh`, passed to `--detach`'s child); `.studio/cost.calib` is excluded from git (`cost_calib_save` and `run_excludes`); a capped unit is `partial` when at least one of its own commits is on `origin/<branch>`, a later one unpushed (D2); a gate repair's `Stop: gate repair out of time — …` counts as gate red for the hold's resume, which repairs again (and reads the gate red Stop's log); the Multica unit comment and report.md's `Spent:` total mark an estimate `≈`. Tests: `test_preflight_runner_behind_warns`, `test_lanes_detach_strips_env`, `test_overnight_cost_estimate_helpers`, `test_overnight_cost_estimate_calibrated`, `test_lanes_excludes_before_lock`, `test_overnight_partly_pushed_capped_is_partial`, `test_lanes_partly_pushed_is_partial`, `test_lanes_resume_after_gate_repair_out_of_time`, `test_execute_gate_repair`, `test_overnight_cost_counts_toward_budget`, `test_lanes_report_cost_estimate`, Multica `test_usd_estimate_marked`.
- Unchanged: the 90-minute default cap and the gate caps; a stall (idle watchdog) keeps its `stalled` ending and never counts as a cap; units.tsv columns 1-7; `noprog` and `retries` for uncapped units; hold/resume; `studio-adopt sync`'s `in progress` line (the checkpoint keyword is new and avoids it); phoenix's config (the operator sets `gate_command` after the live runs end).

### 2026-10-24 — Go/no-go spikes run at plan time, and the preflight checks them

- Incident (phoenix m59-copy-rect, Multica OMEG-128/OMEG-129): the first Risk in story KAN-1723-4's spec said the double offset might cover the camera transform too. The spec named the cheapest check, a scratch windowed camera check (AC 5), and said to run it first. AC 5 made a failure a BLOCK that sends the story back to brainstorm, with no fallback. The plan was approved and queued without running it. T1 ran the check and it failed on both drivers (18432 of 24576 px black), so the story was held until a human ruled. The check takes ~3 min and runs unattended (a windowed Godot run through `studio-gate`). The runner and the unit behaved correctly: the gap was that a cheap, automatable go/no-go check ran after approval, not before.
- Plan §6: a **go/no-go spike** is a check whose acceptance criterion makes a failure a BLOCK or a return to brainstorm, and that is cheap and runs unattended from scratch files with no committed code. A windowed run through `studio-gate godot -- …` counts as unattended. Each spike's task carries `Spike: AC<n> — <command>` (§2). The plan runs it before the approval stop and ledgers `spike T<n> pass|fail <plan path>`. On a fail the plan revises the spec with the user instead of asking for approval. A change at the stop runs a renumbered or new spike again, and a split re-records each spike line whose plan or task number changed (track 1 included). A failed spike sets the spec back to draft, and plan §0 then waits for brainstorm to re-approve it.
- Brainstorm: the spec's **Risks** name the go/no-go check for such a criterion, and say whether it runs unattended; if it does, the plan runs it.
- Preflight: `start`, `--dry-run` and the manifest preflight read each `Spike:` task above `## Backlog` of a story at stage `plan`. When its last `spike T<n> … <plan>` ledger line is missing or a fail they print a warning, or refuse with `overnight.spike_check: "refuse"`. A story already at `execute` is not checked. Autopilot re-ledgers spike lines into each story's ledger with the approval lines, and its readiness checklist fails on a spike warning and says how to close the gap.
- Unchanged: the runner's hold/resume, and execute's check of a spike task (it still runs at execute time).

### 2026-10-23 — A pinned-reference mismatch blocks and carries on; the preflight checks tools; done follows a hand merge (#94, #95, #82)

- Incident (phoenix bat-sonic-rings, Mac.lan): plan Task 46 said a difference "BLOCKS". The execute skill knew only `Stop:`, so the unit wrote `Stop: T46 BLOCK ...` and the lane held ~1 h until an operator sent `say` + `resume`. T34 held for a missing ffmpeg and a `.venv` built on python 3.9; `start` and `--dry-run` caught neither. #82: `final_gate` ran without `STUDIO_START_DIR`, and a final PR merged by hand left the record without `done`.
- Fix 1 (#94): execute 6a defines a Block (a check against a pinned reference): mark only the failing assertions pending with `BLOCKED ...`, append to the blocks file, write a ledger `Block:` line, complete the task as progress. Never edit the reference. `studio-brief task` gains a `blocks:` line; `studio-brief final` prints `Block:` lines. The PR body gets `## Blocks`; the runner lists Blocks in `report.md` and the final PR body.
- Fix 2 (#95): `required_tools` in `.studio/config.json`. `start`, `--dry-run` and `--detach` refuse a missing, too old or non-running tool with its hint. Path entries are checked after `worktree_setup`. A path `cmd` may not hold `..`; `version_args` takes only letters, digits, blanks and `. _ = + / : , -`. No key, no change.
- Fix 3 (#82): the runner exports `STUDIO_START_DIR` to every gate it launches, and `runs_settle` marks a record `done` when its final PR was merged by hand.
- Limits: no existing stop became a block; no per-plan tool list yet; `required_tools` is matched at any depth of config.json, not only top level (parked: a nested key of that name is improbable); a fake Block that the final fix wave un-pends keeps its ledger line, so the final PR body still lists it; the wave's Ruling line explains it (parked).
- Install is pending: install after #93 lands and pid 10051 has exited.

### 2026-10-23 — Overnight throughput: parallel tracks, machine-sized caps, checkpoint suites, plain git forms

- Why: the studio moved from a 4-core i7-7700HQ MacBook to an M6 Mac mini (12 cores, 32 GB). The full phoenix GUT suite fell from a 20 min median to about 4.5 min, but the overnight run did not speed up in proportion. In the measured run (16.2 h wall) 7.4 h were a hold, about 20 of 22 runs were one story or a short chain, vitest was held to `--maxWorkers=2` (directory runs took 150-210 s), the gate cap was 60 min (13 times the suite), the ledgers held 13 `Stop: gate red` lines and 12 gate-repair units, and in 29 units worktree isolation refused 170 commands (about 17 min of retries). Every gate, reviewer and test that ran before still runs.
- Tracks (Tasks 1-3): the plan gets `After:` lines, `studio-brief tracks <plan>` reports the independent tracks (a `Files:` path written two ways joins one track; fenced headings are ignored), and the plan skill splits a manifest story into sibling stories `<id>-<k>` that run in their own lanes (`approve one` keeps today's single story). A run with one chain says so before it starts and offers a backfill story.
- Caps (Tasks 4-5): `studio-vitest` and `studio-tsc` replace `cd <node dir> && studio-gate vitest …`. `node_workers` is sized to the machine (a 4-core machine gets today's value, and a bad value is refused in the preflight); `node_dir` only picks the node project dir. The gate run cap is learned from `gate.times` (`gate_cap_factor`, well-formed 8-field rows only; any other line is skipped and the fallback is today's cap).
- Checkpoints (Task 6): while the suite is cheap, a lane run (a manifest run, never a single-plan run) runs the full suite every K completed tasks (`suite_every`) and repairs a red checkpoint before the next task builds on it. The finish gate still runs the whole gate once. The preflight prints three new readout lines, `one lane:`, `gate caps:` and `suite checkpoint:`.
- Plain forms (Tasks 7-8): `sdd-run` and `studio-docs-sync` replace `bash "$(sdd-script …)"` and `git checkout $STUDIO_DOCS_REV -- …` (`sdd-run` refuses a skill or script name that is empty, holds a `/`, or is `.` or `..`). Every remaining chained or `$(…)` git form in the skills (`git add … && git commit …`, `adopt-base $(git rev-parse HEAD)`, the integration and parallel cleanup chains) is now numbered separate calls, a failed `git add` still stopping before the commit. Execute §2 puts the shell-form rule in every implementer, fixer and reviewer brief under a lane, and §0 applies it to the orchestrator. The contract `tests/omega_contracts/isolation_forms_contract.sh` scans every `*.md` under `studios/` and `shared/omega/` and names file:line for any such form.
- Install is pending: merge and reinstall (`install.sh`) after the active overnight runs end.

### 2026-10-23 — A run that cannot push stops at once; holds remind (#90, #91, #92)

- Incident (phoenix bat-sonic-rings, Mac.lan): the gh token on the new machine had scopes `gist, read:org, repo`, no `workflow`. Unit T19 edited `.github/workflows/web-tools-tests.yml`, and GitHub refuses a push that touches a workflow file without that scope.
- `start --dry-run` and `--detach` both passed. T19-T30 (12 units, ~8 h) each wrote `Ruling: push rejected …` and went on, as the execute skill said to; 50 commits stayed local, and the runner counted every unit as `progress`.
- T31 wrote `Stop: push rejected …`; the hold reached Multica only, and nobody saw it for 4 idle hours.
- Fix 1 (#90): the preflight reads the gh token's scopes. A token without `workflow`, on a repo with `.github/workflows`, when gh is git's credential helper for an https push host, is refused (otherwise a warning line is printed): `gh auth refresh -h <host> -s workflow`.
- Fix 2 (#91): under `--one`, a rejected push is a `Stop: push rejected — <git's last error line>`, never a `Ruling:`. The runner backs it up: a unit whose work is not on origin ends held, not progress, with `stop: push not on origin — <branch> <local sha> vs origin <sha or "none">` (or `— <branch> fetch failed` when origin cannot be reached).
- Fix 3 (#92): the runner itself raises a macOS banner when a hold starts, and once more when 25% of the hold is left (2 h before an 8 h hold ends), with a new `hold_reminder` event (see `overnight-events.md`). The bridge turns `hold_reminder` into a reminder notice on the Run issue and the kickoff issue, so the kickoff agent wakes a second time.
- Limits:
  - No @-mention: every bridge comment uses the operator's own token, so it would be a self-mention that Multica is not expected to notify (and needs an AC18 carve-out). The agent-assigned kickoff (#85) stays the wake path.
  - On a Mac where the #85 bridge also runs, the hold banner can show twice (runner and bridge).
  - An old bridge skips `hold_reminder` with one warning log line until it is reinstalled.
- Note: kickoff texts should resolve the project path on the target machine (OMEG-118 carried `/Users/xinli/...` from the other laptop). Follow-up.
- Install is pending: merge and reinstall once every active overnight run has ended.

### 2026-10-23 — Direct merge is recommended; runs are planned for parallel lanes

- Autopilot's mode question lists **direct** first, marked Recommended: each story merges into `main` on its own once done. Without `merge_command`, integration stays first and recommended.
- A new **dependencies** question: **maximize parallelism** (recommended) proposes the smallest Depends on set, so independent stories get their own lanes; **chain** is the old one-after-another layout. Under maximize, `0` lanes (one per chain) is recommended.
- Before seeding, an overlap check compares the `Files:` of every pair of stories that would run in parallel. Each pair sharing a file asks to add a dependency or keep parallel.
- Brainstorm's `## Stories` Depends on copies the manifest's.
- Unchanged: the gate lock still runs one test or gate at a time (plus the short slot). Measured on phoenix 2026-10-22, one lane held the gate ~52% of the time, so lanes beyond ~2 queue on it; gate slots are a separate follow-up.

### 2026-10-22 — Holds reach the operator; plans measure before approval (#85, #86)

- #85: a hold used to be silent on the phone. In a manifest run the Run issue now goes Blocked while any story is held and back to In Progress when none is.
- The bridge posts a `studio: [notify only]` notice on the request issue through `Cli.add_notice` (it bypasses `_guard` and is content-checked for the marker instead); the Run issue gets a plain `studio: story B held: …` comment through the normal comment path (single-plan runs: only today's `held:` line). Status and assignee stay forbidden (AC17 exception).
- Limit: an unassigned (queued) kickoff wakes no agent, so the notice there has no one-line reply; the macOS banner is then the only alert.
- The README, the agent text and the deny rules were updated to match.
- #86: the plan skill (`studios/game-dev/skills/plan/SKILL.md` section 6, b640c6c) now requires plan-time probes: measure before the plan is approved.
- Install is pending: a phoenix run is live, so nothing is reinstalled yet.

### 2026-10-20 — Short checks no longer wait behind a whole-suite run (#71)

- Incident, measured over 14 days of phoenix overnight runs: 191 of 3187 short gate calls waited
  behind a long hold, 4317 min in all, 66% of gate queue time. The gate ran one command at a time.
- Three opt-in keys (none set means argv and behaviour match main):
  - `test_engine_args: "--fixed-fps 60"`: GUT tests stop depending on CPU load (~2x faster).
  - `gate_short_lane: "on"`: one whitelisted short check may run beside a shareable whole-suite run.
  - `user_dir: "per-worktree"`: `isolate.sh` writes an untracked `override.cfg`, so worktrees stop sharing user://.
- One short slot, admitted under the mutex by the fail-closed `bin/gate-class.sh` plus a load check.
  It never runs beside an exclusive holder, a waiting exclusive blocks new entries, and the slot
  has a 5-min cap, after which the check is re-run once in the main lane.
- The gate scrubs a leaked user_dir setting from `project.godot` and fails the run (sticky across
  a re-run); `hooks/lanes-guard.sh` refuses a commit carrying it.
- Synthetic bench (`tests/probes/gate_lane_bench.sh`, 180 s hold): short wait p50 170 s to 0 s.
- Fixed the dash `kill --` test helper (four #70 detach tests failed under dash). Follow-up #78:
  two load-flaky lanes tests.
- Spec `specs/2026-10-19-gate-short-lane.md`; plan `plans/2026-10-19-gate-short-lane.md`.
- Installed 2026-10-20 at d99a31e together with #70/#57/#72 (PR #77). The Multica bridge was re-installed (ensure_end_wake live), and the `omega phoenix` agent instructions were refreshed with `agent update`. 
- Manual acceptance §13.3 passed 2026-10-20 in a throwaway Godot 4.6 project:
  - concurrent `--file` runs kept separate user:// values;
  - 120 physics frames took 17 ms with fixed FPS vs 1884 ms without;
  - the leak was scrubbed and failed the run, and lanes-guard denied the commit;
  - the slot took a short check beside a shareable suite with 0 s wait, and waited behind an exclusive holder.
  Editor-mode launches still create an empty `app_userdata/<name>/objectdb_snapshots/` (README known limits).
  Open: §13.4-13.5 (the no-new-flaky-reds check and the isolated full gate in phoenix) and §13.6-13.7 (the live wait measure after the first runs).

### 2026-10-19 — `start --detach` survives a large manifest; fast id checks (#70, #57)

- Incident: every `start --detach` of phoenix combat-vfx-library (7 stories, 132 units) was
  killed. The detached child spent ~21 s in its checks before taking the run lock, and the
  parent allowed it 10 s. Each attempt also cost a ~15 min worktree_setup check first.
- Profile: no check was quadratic in stories or units. `ids_check` cost stories × (run records
  + integration refs), and both of those grow with every run.
  - `ids_index`: one index per mf_check, one awk per id; records reach awk on stdin.
  - ids_check went from 8.9 s to 1.0 s, and mf_load + mf_check from 14.2 s to 6.0 s CPU (fetch
    stubbed, load ~4).
  - The output is byte-identical on 117 phoenix and 896 edge cases.
  - mf_check reads the stage from the `show` output it already captured.
- `--detach` now waits on a wall-clock deadline, 300 s by default
  (`STUDIO_OVERNIGHT_DETACH_WAIT_SECONDS`, test hook). Success requires, in this order:
  - the child holds the lock;
  - `$run/manifest.path` exists (written after lock_recheck);
  - status answers.
  A child that exits, or is a zombie, ends the wait at once.
- The preflight token was dropped. A sound token skips only checks worth ~1 s; the ids, conflict,
  remote and studio-state checks must re-run in the child. Tracked in #74. Follow-ups: #73
  (direct mode + SETUP_CHECKED) and #76 (a load-sensitive progress test, red on main too).
- Spec `specs/2026-10-19-detach-lock-window.md`; plan `plans/2026-10-19-detach-lock-window.md`.

### 2026-10-19 — A queued kickoff wakes when its run ends (#72)

- Incident: OMEG-92 (phoenix combat-vfx-library) was queued (unassigned, started by a wakeup
  rule), so nobody woke it when its Run issue OMEG-101 closed: no summary, PR or merge, and the
  queue stalled. It was fixed by hand with an `--until-issue-state ended` rule.
- The bridge now arms that rule itself (`ensure_end_wake`, right after `refresh`) when the
  request issue is not agent-assigned or the Run issue is not its sub-issue. It runs once per run
  (`end_wake` in the run state, saved as soon as the create returns) and skips an existing
  matching rule. A failure leaves one Run-issue note with the hand command.
- `create_wakeup` is the AC17 carve-out: the one unguarded write on a request issue. Comments and
  statuses stay forbidden.
- README: "Queue a run behind another" (the queue recipe); agent instructions cover the Run-issue wake.
- Spec `specs/2026-10-19-queued-kickoff-wake-design.md`; plan `plans/2026-10-19-queued-kickoff-wake.md`.

### 2026-10-09 — Bare Godot runs go through the gate (#66)

- Incident: phoenix run kan-1496, unit 2-KAN-1496-T1, ran a bare
  `/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://tools/web_tools_importer.gd 2>&1 | tail -5`.
  The auto-mode classifier denied it and then every later Bash call; the run held.
- R1: godot-guard verdict c refuses unwrapped `-s`/`--script`/`--import` runs and
  names `studio-gate godot -- <segment>`. The shared detector `bin/godot-cmd.awk`
  (json and md modes) serves godot-guard and studio-brief; md mode handles fences
  per CommonMark, `\`-continued fenced lines and hard-wrapped spans.
- R3: runner sessions get `--allowedTools` from `bin/overnight-allow.txt`:
  `studio-test`, `studio-run`, and `studio-gate godot --` with the Godot.app,
  Godot_mono.app, `Godot` and `godot` binaries. Probe (Claude Code 2.1.296):
  `$GODOT*` rules never matched, so they are dropped; hook denials do not count
  toward auto mode's consecutive-denial limit; piped wrapped calls still reach
  the classifier.
- R4: `studio-brief rewrite` (stdin, or `<file>` in place) rewrites task, check and
  final output, and `validate` refuses bare forms. The execute skill rewrites
  task-brief's file; the plan skill writes the gated form.
- R5: a non-done unit ending gets ` [permission-route — denied: <command> (+n more)]`
  in status and report.md.
- Rollout check PASS: a bare call was refused, the gated retry ran, no classifier
  denials. Follow-ups: #67.
- Spec `specs/2026-10-09-godot-classifier-route.md`; plan
  `plans/2026-10-09-godot-classifier-route.md`.

### 2026-10-07 — Unique story ids (#56)

- Why: phoenix's new run reused the id `S1`, and its `S1` inherited KAN-1499's
  shipped ledger (`.studio/ledger/S1.md` on main: plan approved, T1-T2 complete,
  shipped), so the story would have resumed at task 2 of 2 on another story's plan.
- `studio-overnight check-id <id> [--plan] [--ticket] [--slug] [--branch]` says whether an
  id is free (0), taken (1, one line per reason and a suggested id) or misused
  (2). An id is taken by a ledger on the default branch that is not this story's
  own, a ledger on another run's integration branch, another run's record
  (live, stopped, done or archived) that lists it on another branch (a half-done
  story carried into a new run on its own branch keeps its id), or a plan on the default
  branch with `Story: <id>`. Ids compare case-insensitively; it never fetches.
- autopilot proposes `KAN-<n>` (the ticket) or `<slug>-S<n>` and checks each with
  `check-id`; brainstorm and plan check before writing; `next` and `start`
  (`--dry-run` and `--detach` included) refuse a reused id before anything
  inherits a dead story's ledger.
- `next` matches ledger lines whole (`Decisions swept S10` no longer satisfies `S1`).
- A run's record (`.studio/runs/<slug>/`) now keeps the run's `rows.tsv`, so a
  done run still names its ids.
- Spec `specs/2026-10-07-unique-story-ids.md`; plan `plans/2026-10-07-unique-story-ids.md`.

### 2026-10-06 — Reinstall keeps your settings.json keys (#53)

- A reinstall used to back up a differing `settings.json` and replace it with
  the studio template, so top-level keys Claude Code or the user added (such as
  `agentPushNotifEnabled`) were lost; three reinstalls dropped it.
- `install.sh` now merges with python3's stdlib `json`: the template's keys win
  with the template's values, every other top-level key is kept, in its order,
  and named in one line.
- A backup is made only when a template-owned value changes, so a file that
  differs only by kept keys or formatting no longer piles up `.bak` files.
- python3 is optional: with none, or a file that is not a JSON object, the
  template is installed as is and a warning names the backup. A symlinked
  `settings.json` is never merged from.

### 2026-10-06 — Preflight worktree_setup before start (#49)

- `studio-overnight start` runs the project's `worktree_setup` once in a scratch
  linked worktree off `origin/<target>` before launching, through `studio-setup`
  (same gate lock and timeout). A command that breaks only where `.git` is a file
  is refused with exit 2, the setup's exit code and a log that outlives the
  scratch worktree. The scratch worktree never survives `start` (interrupts and a
  killed start included). `--dry-run` only says that start will check; it does not
  run the setup. `start --detach` checks once in the foreground and hands the
  checked commit to the child (`STUDIO_OVERNIGHT_SETUP_CHECKED`), which skips it.
- Why: phoenix's 2026-10-05 incident — a `worktree_setup` that worked in the main
  checkout failed in a story's linked worktree, and the overnight run found out
  only when its first story ran.

### 2026-10-06 — Adopted story starts from its own run worktree (#50)

- Root cause. The 10-05 `no adopted line` (with Target `integration/other`) came
  from the pre-#45 `studio-adopt` installed at the time. The same symptom had two
  latent paths still on main:
  - a run worktree without `.studio/run` (git-excluded, so it is lost when the
    worktree is re-created) made `start_checkout` fall back silently to the main
    checkout, i.e. another live run's ledger, Target and manifest;
  - an `adopted` line ledgered from the main checkout instead of the run worktree.
- `start_checkout` is now one lookup, in tiers:
  1. a `run/*` worktree (the main checkout included) whose `.studio/run` manifest
     lists the story;
  2. else a `run/*` worktree with no `.studio/run` whose committed
     `docs/runs/<slug>.md` lists it, with a one-line `note:`;
  3. else refuse with `no run worktree found for <id>: looked for …; checked: …`
     when the main checkout is on another run, or when a `run/*` worktree's ledger
     holds the story's `adopted` line (a pointer naming a missing manifest shows
     as `.studio/run → missing <file>`);
  4. else, with no run involved (a manual adopt), the main checkout as before.

  Two hits in one tier still refuse. The Target and manifest come from the
  checkout that was resolved, and `inspect` reads plans from it too.
- Seed's and sync's `no adopted line` / `no ledger` refusals name the ledger read,
  the start checkout and any other ledger holding the `adopted` line.
- Restart guard: `STUDIO_STORY=<id> studio-state check --rebuild` refuses an
  adopted, started story whose ledger here has no `adopt-base` line, so it can
  never be reset to task 1. Run `studio-adopt seed <id>` there first.
- Start readiness: `studio-overnight start`, `--dry-run` and `--detach` refuse
  (exit 2) when the start checkout has no `.studio/run`, or one that does not
  name this run's manifest (a missing file or another `# Run:` slug), and when an
  adopted story whose branch exists has no `adopt-base` (the hint names its
  worktree, or `the <Branch> worktree` when that is gone). A story whose branch is
  gone after landing, or not started yet, is skipped.
- Autopilot: discovery lists a `run/*` worktree that lost its pointer (committed
  manifest present) and re-creates the pointer on resume; `adopted` is ledgered
  from the run worktree, never the main checkout; seeding waits for the run
  worktree's `.studio/run`; a failed seed stops; the readiness checklist names
  the new dry-run checks.
- Recovery for a run worktree that lost its pointer, in that worktree:
  `printf '%s\n' docs/runs/<slug>.md > .studio/run`.
- Behaviour change: a manual adopt (no run) while another run holds the main
  checkout now refuses at tier 3 instead of using that run's ledger and Target.
  Set `STUDIO_START_DIR` to the checkout holding the story's `adopted` line.
- Reinstall only after the PR merges, and only when `studio-overnight status`
  shows no live run; never pull into the main checkout during a live run.
- Plan: `plans/2026-10-06-adopt-run-worktree.md`; no separate spec (issue #50).

### 2026-10-05 — A stage pointer per checkout (#42)

- Each checkout holds its own stage pointer at `<work root>/.studio/STATE.md`; a
  pointer-less linked worktree has no story and reads idle. A story planned in the
  main checkout moves to its execute worktree with `studio-state handoff` (or
  `studio-state take <spec>` from a worktree made by hand); `studio-state stories`
  lists every checkout's story, so review, playtest and retro from main find it.
  The overnight runner follows a story that moved. Exit 4 refuses a story switch
  in a checkout; `--force` is the user's call.
- Recovery for a worktree whose state was clobbered before the upgrade (it reads
  idle), or a finished story whose main pointer was overwritten (no `handed` line,
  so `stories` cannot see it and review from main asks): re-seed it with
  `studio-state set spec`, `set plan`, `set stage`, `set task 0/<N>`, then
  `studio-state check --rebuild`.
- Not preventable: a pre-#42 `studio-state` run by path from a stale dev worktree
  (the 2026-10-05 trigger was the #39 worktree's bin) still writes the main
  pointer. Such worktrees pick up the new resolution when rebased.
- The per-machine phoenix note
  `~/.claude-gamedev/projects/-Users-xinli-GameDev-proj-phoenix/memory/studio-state-is-shared-across-stories.md`
  (and its `_practice` copies) can be deleted once this lands and is reinstalled.
- Reinstall only when `studio-overnight status` shows no live run.

### 2026-10-05 — Concurrent runs (#39)

- Several manifest runs can be live in one project. Each holds its own lock at
  `.studio/runs/<slug>/lock`; a same-root registry entry is dropped only when its
  runner is not live. `status --run`, `watch --run` and `stop --run <slug>` act on
  one run, `stop --all` on every run, and the channel verbs resolve the run by
  `--run`, then by the story in `rows.tsv`, then by the only live run.
- `overnight.max_sessions` (default 6, range 1-8) caps headless sessions across
  the project; a unit that finds no slot waits in a FIFO queue and logs a
  `session_wait` event. Before each task a story syncs with moved targets
  (`story_synced`; a failed merge runs a `sync-repair` unit).
- The events contract gains `story_synced` and `session_wait` and a rewritten
  "Finding a run". The Multica bridge mirrors `story_synced` as a comment, maps
  `sync-repair` to in progress, ignores `session_wait`, and mirrors two live runs
  of one root.
- Plan: `plans/2026-10-04-concurrent-runs.md`; spec:
  `specs/2026-10-04-concurrent-runs.md`.

### 2026-10-04 — Multica integration (#28)

- A bridge service mirrors live overnight runs onto a Multica board, so a run can
  be watched and steered from a phone browser. It reads the core's public files
  (`events.jsonl` and the run registry) and calls its public verbs; the core never
  names Multica. A "Run" issue (under the request issue that asked for the run) and
  one sub-issue per manifest story carry statuses and `studio: ` comments. The bridge
  stays hands-off on an issue while an agent is assigned and posts one catch-up
  comment afterward.
- The operator posts commands as comments: `/say`, `/unit`, `/hold`, `/resume`,
  `/stop`, `/unsay`, `/said` (and `/stop run`). Only the operator's own comments
  count. The bridge replies in a threaded comment starting with a check mark, a
  cross or a warning sign.
- `integrations/multica/` holds the installer (`install.sh`, `uninstall.sh`), the
  launchd service, the README, and two wrappers: `claude-multica` (mode 2: normal
  `claude` plus the deny list) and `omega-multica-agent` (mode 3: `claude-gd` in the
  project with Multica's context). Install keeps the API token in the Keychain only,
  links `claude-multica`, `omega-multica-agent` and `multica-bridge` into
  `~/.local/bin`, and fails visibly when macOS blocks the bridge from the project's
  files.
- Core changes, all small: `studio-overnight deny-rules` prints the rules for a
  project, and a run's registry entry may carry an `origin=` line (from
  `STUDIO_RUN_ORIGIN`) that ties it to its request issue.
- The final review's fixes landed: one run's failure (a file-access block, a
  malformed row) no longer stops mirroring the others, and a run that keeps failing
  gets one note; a skipped event still sets its status; CLAUDE.md that is a symlink
  or hard link is not copied into the agent context.
- Probe results are in the spec ("References (continued)", items 17-23) and
  D1a-D1g in the plan: P1, P2, P3, P4 and P7 ran and passed. P5 and P6 were not
  run because the projects live outside `~/Documents`, so the plan's defaults are
  in use. Finding from P1: a per-machine `runtime profile set-path` override beats
  the profile's command, and command changes need a daemon restart (`multica
  daemon restart --profile <name>`; the app has no restart button); README and
  install now say so.
- The live install check (spec milestone gate step 4) passed on 2026-10-04
  (spec References item 24). Say, resume, the end-of-run Done status and the
  single "sub-issues closed" wakeup all worked. The deviations: the test project
  was outside `~/Documents`, hold and resume were exercised on stories the
  studio held itself, and no final PR opened because the origin was local.

### 2026-10-04 — Overnight operator channel (#27)

- An operator can talk to a live overnight run. `studio-overnight say <story>
  -- <text>` queues a message, `said` lists messages and their states, and
  `unsay` retires one. `hold`, `resume` and `stop <story>` control a story.
  Every verb takes `--run <run>`; outside a project, `--run` is required.
- `hooks/operator-inbox.sh` (SessionStart and PostToolUse) delivers a queued
  message into the running unit's session at its next tool call. A message
  scoped to a story becomes a `Directive <n>:` line in the feature ledger, and
  `studio-brief` prints the story's active directives.
- A no-progress ending, a rule stop after isolation, or the directive cap now
  holds the story for up to `hold_minutes` (default 480) instead of ending it.
  The held line reads `held <why> until <UTC>`; `resume` runs the next unit,
  and a resume after a red finish gate runs a gate repair first. Lanes hold
  per story, and dependents wait while a dependency is held. Landing never
  holds, and a `stop` written during the last unit stops the story before it
  lands.
- Every run writes `events.jsonl` (schema v1, ten events).
  `docs/game-dev/overnight-events.md` is the contract #28's Multica bridge
  reads: fields and enum values may be added within v1, never renamed or
  removed.
- `tests/probes/hook_delivery_probe.sh` re-checks the three hook-delivery
  behaviours the channel relies on, using two haiku sessions. `doctor.sh`
  prints the last pass: 2026-10-04 on Claude Code 2.1.289.
- Still for the operator: a live Godot run with two stories, one held and
  resumed with a directive (plan M3–M5).

### 2026-10-03 — overnight: no background subagents in a -p unit

- Two phoenix `mob-composer-parity` units (4-S3-T3, 6-S3-T4) ended `noprog`
  at 10.7 min. Each main session dispatched its implementer as a background
  `Agent` (the build's default) and ended its turn to wait for the report. A
  `-p` session ends with its turn, and print mode killed the subagent 600 s
  later along with the `studio-test` it was running. The foreground-gate
  rule from 2026-10-02 was kept, but it covered only Bash and Monitor, not
  the dispatch. Each death spent the task's only retry.
- `hooks/autopilot-guard.sh` (PreToolUse, `Agent|Task|Bash|Monitor`) denies,
  under `OMEGA_AUTOPILOT=1` only, an `Agent`/`Task` call whose
  `run_in_background` is not `false`, a `Bash` call with
  `run_in_background: true`, and every `Monitor` call. The deny reason says
  how to re-issue the call. The execute skill's §0 has a matching rule.
- The runner records such a unit `orphaned` (from print mode's "Background
  tasks still running after 600s" line in the unit's `.err`), and a
  no-progress ending gains `(orphaned: …)`. It still counts as no progress.

### 2026-10-03 — studio-test speed (#22)

- The 75-minute phoenix suite was our bug. `test.sh` never passed `-gconfig`,
  so phoenix's `tests/.gutconfig.json` hooks never ran under `studio-test`.
  Those hooks keep the 7.9 MB humanoid rig loaded (KAN-919), pin the locale
  and isolate Inventory leaks. Each actor-building test reparsed the rig, at
  3–4 s a time. `studio-test` now passes the project's config: the full suite
  went from 4,485 s to 847 s, with the hooks' isolation back.
- The overnight `studio-test 472 1` was a segfault. A lane's first import was
  cut off, and the old check (import only when `.godot/` is absent) ran the
  suite on the half-built cache. `studio-test` and `studio-run` now check every
  import product and its `.md5` sidecar, which Godot writes only after a file's
  import finishes. They re-import, and stop only when the import itself fails;
  products still missing after an import that succeeded are a warning. A crash
  is reported with the script it was running, or as one at shutdown.
- `studio-test --slowest [N]` reports where the suite's time goes.
- Sharding is deferred: 4 shards were 2.9× faster with no swap, but phoenix has
  an order-dependent test and a flaky one that only fail sharded. Tiers are
  dropped: the fast tier was 51% of the full run. Numbers and verdicts:
  `specs/2026-10-02-studio-test-speed-findings.md`.

### 2026-10-02 — Overnight lanes repair a red gate

- In a lane, a story's finish runs the full gate once. A red gate used to
  stop the story and skip every story that depended on it. In one incident,
  a 121-character doc line halted a phoenix run at 85 minutes. Now
  `Stop: gate red — …` is the one repairable stop. The runner launches a
  `gate-repair` unit (`/game-dev:execute --gate-repair`, model_repair,
  `STUDIO_REPAIR=gate:<studio-test log>`), which fixes the failure and
  re-runs only the failing test files. Its `Repair: gate — …` line makes the
  runner launch a fresh finish, which runs the full gate again.
  `overnight.gate_repairs` (default 2, 0-3) bounds it. Past the cap the
  story ends `stopped gate red after <n> repairs — <line>`.
- A stop written twice with the same text on the same day is now detected:
  `snapshot` numbers each Stop line's occurrences within its ledger instead
  of de-duplicating them.
- The execute skill's final review makes every gate-enforced finding (line
  length, docs budgets, any `tests/` check) must-fix, and refuses an "it is
  not under that test" claim until the test has been run. That ruling was
  the root cause of the incident.
- Plan: `plans/2026-10-02-overnight-gate-repair.md`.

### 2026-10-02 — Overnight foreground gate and status anywhere

- The finish unit never ran its tests: under a lane, the execute skill told
  the session to run `studio-test` in the background and wait for the
  notice, and a headless `-p` session ends when its turn ends, so the notice
  never came and the job was orphaned holding the gate lock. Sessions now
  run `studio-test` and `studio-run` in the foreground with
  `timeout = $BASH_MAX_TIMEOUT_MS`; `tests/probes/bash_timeout_probe.sh`
  showed a `-p` foreground call honours a raised cap past 10 minutes.
- `studio-gate` registers each gate under its unit's tag
  (`.studio/gate.units/`), and the runner ends any gate a unit leaves
  behind. A watchdog-ended unit with no progress is recorded `timed out`.
  `.studio/gate.times` logs gate durations; preflight warns when the
  slowest recent `studio-test` would not fit `session_minutes`.
- `studio-overnight status` works from any directory through a user-level
  run registry (`~/.claude-gamedev/runs/`), shows each running unit's last
  tool call or subagent and the gate holder, and reads an ended run as one
  line with its report and resume command. `watch` repeats it; a foreground
  `start` prints a heartbeat. The installer puts `studio-overnight` on
  `PATH` (studio.json `commands`).

### 2026-10-02 — Overnight lanes (issue #19)

- `studio-overnight start` runs a manifest of stories as parallel
  dependency-chain lanes; a dependent never starts before its dependency
  has landed.
- The runner lands stories itself, serialized: integration mode ends in one
  draft PR integration → main (nothing merged into main, one full gate);
  direct mode merges each story through the project's merge command.
- `studio-gate` takes a machine-wide gate lock so lanes never run two
  engine gates at once; `studio-brief` and `studio-state` (`STUDIO_STORY`)
  give each lane's sessions their own story state.
- `studio-overnight next` is the planning loop for stories with no plan;
  `start --detach` outlives the chat, and `status` and `report.md` are
  per story.
- Skill contracts rewritten: execute, plan, brainstorm, autopilot and
  integration. Autopilot in a studio never runs stories in its own session
  and never starts a keep-awake.
- Live probes: D1a detach PASS (log unbroken after the window closed; env
  scrub widened to every `CLAUDE_*` and `AI_AGENT`, `CLAUDE_CONFIG_DIR`
  kept). D1b inconclusive (harness blocks a bare `sleep`), so background
  `studio-test` is the default. D1c a `set -m` subshell gets its own group.
  D1d phoenix `merge.sh` never reads a TTY and fails fast.
- Review rulings: the merge command runs under `session_minutes`, and a
  timeout stops the story unless its PR already merged (the first ruling
  had no timeout); D3 kept over spec 788-790 (an existing story branch's
  spec and plan are synced from the run's Docs revision, not a stop); one
  final repair unit at most; a red lane gate never ships and a lane story
  is not retried by fix rounds.
- Gate: `sh tests/run_all.sh` green (2,615 assertions, 0 failed).
- 56 deferred minor review findings are listed in the PR for a follow-up
  issue.
- Play before merging: 4 items pending (P1 integration live run; P2 direct
  live run; P3 the morning report; P4 detach survives the chat).
- Branch `worktree-issue-19-autopilot-integration`. Spec
  `specs/2026-10-01-overnight-lanes.md`, plan
  `plans/2026-10-01-overnight-lanes.md`.

### 2026-10-01 — Overnight runner (issue #17)

- `studio-overnight start` runs an approved plan from a plain terminal:
  one fresh `claude -p` session per unit (each task, final review, finish),
  ends in a draft PR, and writes `units.tsv` and a morning `report.md`
  (how the run ended, cost, rulings to check, play list, PR, resume).
- Autopilot prints the runner command instead of driving the session;
  `omega-caffeine` and the `CronCreate` heartbeat are retired.
- Live probe on 2.1.287 (D1-D6): slash commands expand under `-p`;
  `EnterWorktree` works; deny rules hold, including mid-command wildcards
  (`git push * --force*`); `total_cost_usd` is present; a unit starts at
  about 39k context; Ctrl-C aborted a backgrounded session, so the launch
  uses `set -m`.
- D7: the spec's wait loop was wrong (a second `wait` on a reaped child
  returns 127), so the status is read inside the loop.
- Review fixes: a watchdog teardown race marked every unit `timed_out`; a
  `mkdir` claim on `.ended` fixes it. Beyond the spec, SIGHUP ends the live
  session group before unlocking. A stop before isolation writes its
  `Stop:` line in the launch checkout and is never committed.
- Gate: `sh tests/run_all.sh` green (1,803+ assertions, 0 failed).
- Play before merging: 2 items pending (P1 live two-task run to a draft
  PR; P2 the morning report answers everything without opening a log).
- Branch `worktree-issue-17-overnight-runner`. Spec
  `specs/2026-10-01-overnight-runner.md`, plan
  `plans/2026-10-01-overnight-runner.md`.

### 2026-10-01 — Slim pipeline (issue #9)

- The stage chain is `idle → brainstorm → plan → execute → idle`, with a
  `/clear` between stages. `review`, `playtest` and `retro` are on-demand
  commands that never change `stage`. The last stage of the old pipeline is
  deleted, and execute's finish opens the PR.
- `studio-state`: a `branch` key, four stages, and `worktree` (exit 0 prints
  the feature's checkout; exit 3 prints the command that recreates it).
- Execute: B2 fix rounds (a fresh fixer per round, a re-review only after a
  Critical, 3+ Importants or a production-bug fix, never a third pass), a
  standalone final review on Opus, and a finish that gates, writes the play
  list, records PROGRESS and opens a ready PR without merging.
- `stage-guard.sh` (`UserPromptSubmit`) warns when a session that already ran
  one stage is used to start another.
- Rollout checks: M2 passed on Claude Code 2.1.287 (the second stage typed
  in one session drew one warning line and was not blocked; recorded in
  `docs/game-dev/pressure/slim-pipeline.md`); M3 passed (phoenix's router
  prints `Stage: idle (was retro, old pipeline)` and `Next:
  /game-dev:brainstorm`); M4 done (issue #6 describes the new chain). The
  pressure scenarios in `docs/game-dev/pressure/slim-pipeline.md` are not
  yet run; `claude-gd` logs in again, so they are unblocked.
- Spec `specs/2026-10-01-slim-pipeline-design.md`, plan
  `plans/2026-10-01-slim-pipeline.md`.

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
