# Automatic run cleanup — Implementation Plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax. TDD: write the failing test, see it fail, implement, see it pass, commit.

**Goal:** When every story of an overnight run is confirmed merged into its target (checked against the remote), the runner closes the record and cleans up after the run. It marks the record done, removes the worktrees and local branches, deletes the remote branches (`run/<slug>` is archived as a tag first), moves Jira and Multica issues to Done, and archives the story pointers. Every step is idempotent and best effort. It is triggered at the end of a run, in the start/status settle sweep, and by `studio-overnight settle`.

**Source prompt:** `/private/tmp/claude-501/-Users-xin-game-dev-proj-phoenix/90acad36-e4c8-462e-8946-96702f7b0ec1/scratchpad/omega-ai-run-cleanup-prompt.md` (phoenix evidence, 2026-10-27).

**Tech stack:** POSIX sh (macOS `/bin/sh`, BSD userland, no jq; `gh`'s own `-q` is allowed), awk, git ≥ 2.38. Tests are the repo's sh suites (`tests/assert.sh`, `run_tests`, `TESTS_ONLY`).

## Decisions

- **D1 Merged, squash-aware.** Phoenix squash-merges, so a branch tip is never an ancestor of `origin/main`. A row is confirmed when its `landed.tsv` sha is an ancestor of `origin/<Target>`, or when `gh pr list --head <branch> --state all` has a MERGED PR into `<Target>` whose merge commit is an ancestor of `origin/<Target>`. In the second case `landed.tsv` gets the line backfilled from that PR's merge commit. That PR's head must be `origin/<branch>`'s tip while the branch exists, and its merge commit must not be in the run's `Docs` revision, so a reused branch name's old PR does not count (final review). Direct mode with PROGRESS.md also needs the entry on the Target: a `docs(progress): <slug>` commit in `Docs..origin/<Target>`, a row's landing that changed PROGRESS.md, or the merged progress PR.
- **D2 "Tip in target" for deletions.** A branch tip T counts as in `origin/<base>` when T is an ancestor of `origin/<base>`, or a MERGED PR of that branch has `headRefOid == T` and its merge commit is an ancestor of `origin/<base>`. `<base>` is the Target in direct mode and the default branch in integration mode (the final PR's base). A branch with an OPEN PR is never deleted: the report already says the run never closes a PR.
- **D3 `run/<slug>`, tag then delete** (user decision 2026-10-27). Its tip holds planning commits that never reach main. So the runner pushes `refs/tags/run-archive/<slug>-<tip12>` at that tip, then deletes the branch. It is not deleted when the tag push fails. A local `run/<slug>` is deleted only when its tip is an ancestor of that tag.
- **D4 Remote deletion is on by default** (user decision). It touches only run-owned names (rows' branches, `run/<slug>`, `progress/<slug>`, and in integration mode the Target) and only after a fresh fetch. D2 guards it, and the commits stay reachable from the base or from the archive tag. A project opts out with `cleanup.remote_branches: "off"`.
- **D5 Story pointers are archived** (user decision). The runner appends `- <date> merged <sha> into <target> (run <slug>)` to `.studio/stories/<id>.md`, then moves it to `.studio/stories/done/<id>.md`. It is kept when another not-done, non-archived record lists the id.
- **D6b Other runs.** A branch that a live record, or another not-done record, lists is skipped; so are a live run's start dir and (outside the run's own finish) START_DIR. A branch's tip is checked before its worktree is removed. The `mf_check` sweep skips the slug being started. A record's runs are the report dirs whose rows are all its own; Multica state files must name one of them.
- **D6 Archived records** (`<slug>.<YYYYMMDDTHHMMSSZ>`, made by autopilot) touch only their story rows (branches, worktrees, pointers, Jira, Multica), never `run/`, `progress/` or `integration/` branches or the run worktree. A newer run of the same slug may own those.
- **D7 Shared Jira tickets.** A ticket moves to Done only when (a) every other record listing it has `done` and a `landed.tsv` line for that row, and (b) `parent = KEY AND statusCategory != Done` returns nothing. Otherwise it is "kept open", with the reason. If the ticket's status is already the done status, nothing is posted. Phoenix KAN-1723 is a Story shared by 7 rows across 5 records, and `bat-sonic-followups.20261025T011344Z` is not done, so it is kept open.
- **D8 Markers in `.studio/runs/<slug>/`:** `cleaned` (every enabled step finished, so sweeps skip the record), `cleanup.state` (sub-steps done: `jira-comment KEY`, `jira-done KEY`, `multica-done IDENT`; a rerun never re-posts), `cleanup.log` (each attempt's lines, appended), `cleanup.tried` (epoch; sweeps wait `cleanup.retry_minutes` between attempts), and `cleanup.mx` (symlink mutex, non-blocking; a dead owner is reaped).
- **D9 Dirty worktree.** A worktree counts as dirty when `git status --porcelain` shows anything besides `?? .studio/run` and `?? .studio/STATE.md` (runner bookkeeping; `.studio/run` is not git-excluded in phoenix). A dirty worktree is kept and reported. A clean one is removed with `git worktree remove --force` (the force only drops those two files). The main checkout is never removed.
- **D10 Config** (`.studio/config.json` in the project root, object `"cleanup"`, flat string or number values):
  `record`, `worktrees`, `remote_branches`, `jira`, `multica`, `stories` take `"on"|"off"` (default on); `jira_done_status` (default `"Done"`, the status name `acli … transition --status` takes); `jira_cli` (default `acli`, then `$HOME/.local/bin/acli`); `multica_cli` (default `multica`); `retry_minutes` (default 60); `timeout_seconds` (default 60, the cap on each external call).
  A bad value is one `left: config cleanup.<key>: …` line, and that step is skipped.
- **D11 External calls** go through `cl_exec ARGV…`: a temp script with `sq`-quoted words, run by `tools_run sh <script>` with `STUDIO_OVERNIGHT_TOOLS_SECONDS` = `timeout_seconds`. Exit 124 means timed out. `tools_run` splits on blanks, so arguments with blanks need the script.
- **D12 `--dry-run`** takes no mutex and still fetches (a read; confirmation must be against the remote). It prints `would:` lines and writes nothing else: no record files, no git refs besides the fetch, no gh/acli/multica writes. gh, acli and multica read calls are allowed.
- **D13 Output:** one head line per record, then indented `done:`/`would:`/`left:`/`skip:` lines, then a tail line (`run <slug>: cleaned up` / `run <slug>: <n> left — rerun: studio-overnight settle <slug>`). An unconfirmed record prints `run <slug>: not confirmed — <reason>`. Sweeps print only records that are confirmed. `settle` prints everything.

## Interfaces (new file `studios/game-dev/bin/overnight-cleanup.sh`, sourced by `studio-overnight` after `overnight-tools.sh`)

- `cleanup_record ROOT SLUG [--dry-run] [--self] [--due]` → stdout lines (D13). Returns 0 when cleaned (dry run: nothing would be left), 1 when not confirmed or something is left, 3 when skipped (live run without `--self`, busy mutex, not due under `--due`, already `cleaned` → prints `run <slug>: already cleaned up` and returns 0). Runs in a subshell with cwd ROOT.
- `cleanup_sweep ROOT [--dry-run]` → `cleanup_record --due` for each `.studio/runs/*/landed.tsv` record without `cleaned` that is not live. One fetch per sweep (`CL_FETCHED=1`). Prints the confirmed records' output.
- `studio-overnight settle [<slug>|--all] [--dry-run]` → bare means `--all`. Exit 0 when every named record is cleaned, 1 when any is not, 2 on usage, no project, or no record of that name.
- `lanes_finish done` → before `lanes_report`: `cleanup_record "$STATE_ROOT" "$MF_SLUG" --self > "$RUN_DIR/cleanup.out"`. `lanes_report` prints `## Cleanup` from `cleanup.out` when present. Otherwise it prints: "Nothing cleaned yet: <why>. Once every story is merged into <target>…, the next `studio-overnight start`/`status`, or `studio-overnight settle <slug>`, cleans up."
- Sweeps: `mf_check` (after its `runs_settle` loop; to stderr under `--check`), `project_status` (after its `runs_settle` loop; not under `--run`).

## Tasks

### Task 1 — confirmation and record close (controller)
**Files:** Create `studios/game-dev/bin/overnight-cleanup.sh`, `tests/overnight_cleanup_test.sh`; Modify `tests/run_all.sh` (table row).
- [ ] Fixture: a bare origin and a clone ROOT with main, run/<slug>, story branches pushed; a gh stub reading `$GH_PRS` (TSV per branch); a record `.studio/runs/<slug>/{rows.tsv,landed.tsv}` and a report dir `overnight-<slug>-<ts>/manifest.md`.
- [ ] Tests: direct mode, every row landed by the runner (confirmed, done written); a row landed by hand with empty `landed.tsv` (backfilled from the PR); an unmerged row (not confirmed, nothing written or deleted); integration mode with the final PR merged (confirmed) or open (not confirmed); direct with the progress PR not merged and no `docs(progress): <slug>` subject (not confirmed); a live run (skipped).
- [ ] Implement `cl_load`, `cl_cfg`, `cl_exec`, `cl_prs`, `cl_confirm`, the record step, and the skeleton of `cleanup_record`.

### Task 2 — the cleanup steps (controller; after Task 1)
- [ ] Tests: remote deletion of rows' branches, `progress/<slug>`, and `run/<slug>` via its archive tag; a branch whose tip moved past the merged PR head is kept; an open PR keeps its branch; a dirty worktree is kept and a clean one removed with its local branch; Jira via an acli stub (comment and transition once; a rerun posts nothing; a shared ticket with a not-done sibling record is kept; open children keep it); an acli failure or timeout is reported and the other steps still run; Multica via a stub and a bridge state file; story pointer archived; `cleaned` written only when nothing is left; `--dry-run` writes nothing (refs, record files, stub call logs show reads only); `--due` throttle; config `off` switches.
- [ ] Implement `cl_remote`, `cl_worktrees`, `cl_jira`, `cl_multica`, `cl_stories`, markers, mutex, `cleanup_sweep`.

### Task 3 — wiring (controller; after Task 2)
**Files:** `studios/game-dev/bin/studio-overnight` (source the file; `settle` dispatch and `cmd_settle`; usage text; `project_status` sweep), `studios/game-dev/bin/overnight-lanes.sh` (`mf_check` sweep, `lanes_finish`, `lanes_report` Cleanup section and header comment), `tests/overnight_lanes_test.sh` (the two existing Cleanup assertions change; a done direct run cleans up at the end), `tests/overnight_test.sh` (settle usage and exit codes).

### Task 4 — skill and docs (subagent, parallel with 1-3, own worktree)
**Files:** `shared/omega/skills/autopilot/SKILL.md` (the worktree line, the "no remote branch deleted" line, the Jira-through-MCP rule: acli first, the MCP as fallback), `tests/omega_contracts/autopilot_contract.sh` (pins), `README.md` (the report.md bullet; a `cleanup` config paragraph), `docs/game-dev/PROGRESS.md` (an entry), and `studio-overnight`'s `--help` "may not" line if it changes (`tests/overnight_test.sh:355`).

### Task 5 — acceptance (controller)
- [ ] `sh tests/run_all.sh` is green, and so are `tests/omega_contracts/*` and `integrations/multica/tests/run.sh`.
- [ ] Dry run against phoenix from the worktree's script (no install): `cd /Users/xin/game-dev/proj/phoenix && sh <wt>/studios/game-dev/bin/studio-overnight settle --all --dry-run`. It must name the remote branches of m59-copy-rect, bat-swoop-refine and mob-group-attacks, the Jira moves for KAN-1730 and KAN-1734…1739, and KAN-1723 kept open (D7).
- [ ] Final review (fresh subagent on the branch diff), then finish the branch.
