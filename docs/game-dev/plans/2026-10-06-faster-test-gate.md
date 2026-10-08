# Faster Test Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `sh tests/run_all.sh` runs every suite in a bounded parallel job pool (sharding the two big suites), then the load-sensitive tests alone. It loses no test and no assertion, and it cuts the gate's wall time as far as it can.

**Architecture:** The harness (`tests/assert.sh`) gains partitions (`TEST_PHASE`, `TEST_SHARD`, `TESTS_EXCLUSIVE`, `TESTS_FINAL`), a timing log of `L`/`T` rows, an env scrub and three helpers. A rewritten `tests/run_all.sh` starts each job in its own session (`POSIX::setsid`), with its own `TMPDIR` and log. It prints each job as one block, then a summary, and fails a suite that missed a test, ran one twice or fell below its assertion floor. Every suite becomes hermetic: it scans and kills only processes whose argv carries its own `$TMP`, through a runner symlink and a marked sleeper. Dead sleeps become event waits, four production poll loops get test-only knobs that default to today, and the two big fixtures are copied from templates.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2, and `dash`), perl (already required by studio-overnight), awk, git. No new dependencies.

**Spec:** `docs/game-dev/specs/2026-10-06-faster-test-gate.md` (R1–R9, Acceptance 1–9). Executors read the spec and this plan.

Story: #54 (GitHub issue). Branch `54-faster-test-gate` (omega-ai has no Jira). **Base:** origin/main 6f2445b. Line numbers are at that commit: relocate each one with its `grep -n` before editing.

## Global Constraints

- POSIX sh only. Everything must pass under macOS `/bin/sh` (bash 3.2) and `dash`. `$(( ))` is integer-only, so every fractional wait counts ticks. A group kill is `kill -SIG "-$pgid"` and a group probe is `kill -0 "-$pgid"`, **never with `--`**: dash rejects `kill -- -N` (probe, see Falsify P1).
- Rule 1: no test is deleted, skipped, merged away or weakened. Each suite's assertion count must be ≥ its floor (its count on `origin/main`).
- Rule 2: timing-behaviour tests keep real clocks. They never set the runner knobs, and they are in `TESTS_REAL_CLOCK` or `TESTS_EXCLUSIVE`.
- Rule 3: faster polling only in pure wait loops, each with a ceiling that returns early. Event waits replace fixed sleeps. Ceiling rule (R6): when the old `sleep N` was followed by an absence or "not yet" assertion, the ceiling is exactly N. Every other event wait gets a ceiling of 60 s or more.
- Rule 4: every new knob is named in its script's header and defaults to today's literal value. At least one test runs each knob at the production value.
- Rule 5: the full gate stays the merge gate. `run_affected.sh` is for in-progress checks only.
- Knob values: `1` (default), `0.5`, `0.2` and `0.1`, which are 1, 2, 5 and 10 ticks per second. Any other value fails with `<script>: <KNOB> must be 1, 0.5, 0.2 or 0.1, got <v>` and exit 2. Each knob is read once, at startup.
- Every `mktemp` in `tests/` uses `mktemp -d "${TMPDIR:-/tmp}/<suite>.XXXXXX"` (or `mktemp "${TMPDIR:-/tmp}/<name>.XXXXXX"` for a file).
- Every process a suite finds or kills by pattern carries `$TMP` in its argv. Otherwise the suite finds it by a recorded pid.
- The harness's private names start with `__rt_`. No suite may use that prefix (lanes already uses `_rt_cfg`).
- Production scripts (`studios/`, `shared/`, `lib/`) change only through the four R7 knobs: their reads, their validation and their tick math.
- Implementers run only their own suites, never two heavy suites at once and never the full gate. The heavy suites are `overnight_lanes_test` and `overnight_test`; a whole run of either goes through `$SP/heavy.sh` (T0). The integrated full gate runs once, after the final fix wave.
- No pushing. No `install.sh`. No reinstall or pull into the main checkout. Never use a bare `git stash`.

## Decisions

- **D1 — Group kills without `--`.** run_all, `stop_group` and any new test code use `kill -SIG "-$pgid"`. The spec's R4 step 1 was amended to say so (spec commit 47d7067). The existing production `kill -TERM -- "-$_dpid"` in `studio-overnight` stays: product scripts always run under `sh`.
- **D2 — Harness prefix `__rt_`.** `run_tests` keeps its state in `__rt_*` variables and re-derives the test name and index from its loop word after each test, so a test that reuses `_t`, `_rt_cfg` or any other name cannot corrupt the timing rows. `test_harness_private_names_unused` (T1) greps for the prefix.
- **D3 — The gate knob's budget test uses a 13 s hold, not 3 s.** At 0.2 s ticks, a wrong `waited % 60` repeats the waiting message after 12 s, so a 3 s hold cannot tell wrong tick math from right. A 13 s hold expects exactly 1 line. It is a lower bound in spirit: under load the waiter polls less often and prints no more lines, so the test stays parallel-safe.
- **D4 — A job timeout also sweeps the job's escaped processes.** After killing a timed-out job's group, `stop_group` runs `pkill -f "$LOGDIR/<job>/"`. This catches processes the suite put in a group of their own (`own_group`, the detach child's `setsid`). The spec only says this for Ctrl-C; a timeout leaks the same way. It is pinned in `test_run_all_job_timeout` (Review Focus 1).
- **D5 — `TEST_JOB_TIMEOUT` applies only in parallel mode.** Serial mode (`TEST_JOBS=1`) is today's gate, with no timeout.
- **D6 — run_all exports `TEST_SH` to every job,** so `harness_test.sh`'s child runs use the dash shell in the dash acceptance run.
- **D7 — Knob validation placement.**
  - studio-setup: after the verb parse, so `--help` works with any value.
  - studio-gate: after its usage check, before `ROOT=`.
  - studio-overnight: after the `--help` case and before `START_DIR=`, so a bad value is refused before any run directory or lock exists.
  - overnight-lanes.sh reads no environment of its own. Its loops use `${REAP_POLL:-1}`/`${REAP_TPS:-1}`, so its loops run at the production value when it is sourced alone.
- **D8 — Knob test names.**
  - setup: `test_setup_poll_keeps_budget` and `test_setup_poll_rejects_bad_value` (studio_setup_test).
  - gate: `test_gate_poll_keeps_budget` and `test_gate_poll_rejects_bad_value` (toolkit_test).
  - reap: `test_overnight_reap_poll_keeps_budget` and `test_overnight_reap_poll_rejects_bad_value` (overnight_test).
  - detach: `test_lanes_detach_poll_keeps_budget` and `test_lanes_detach_poll_rejects_bad_value` (overnight_lanes_test).
- **D9 — `STUDIO_OVERNIGHT_POLL_SECONDS` carriers at 5 s.** It has three loops:
  - the single-plan hold wait (`studio-overnight:851`): new `test_overnight_hold_default_poll` (T7, `TESTS_REAL_CLOCK`);
  - the land lock (`overnight-lanes.sh:836`): `test_lanes_land_conflict_one_repair` (`TESTS_REAL_CLOCK`);
  - the waiting-chain wait (`overnight-lanes.sh:1004`): T6 names the cheapest existing test whose chain waits on a dependency without setting the knob and adds it to `TESTS_REAL_CLOCK`. If no such test exists, T6 adds `test_lanes_wait_deps_default_poll`.
- **D10 — Release files.** Lanes stub sessions wait on `$SCEN/release-<tag>`. The overnight stub has no scenario dir, so its sessions wait on `$CALLS/release-<tag>`. In both stubs a release is `waitexist <path>`, and the test runs `: > <path>` after its live-state asserts.
- **D11 — The overnight fixture fails loudly.** Today `fixture` hides every error, and a failed `git remote add` on a reused name goes unnoticed. With rm-first (R8), the build runs under `set -e`. A failure removes the template and adds `_fail "fixture NAME: setup failed"`, the same wording as `lanes_fixture`. A new `test_overnight_fixture_failed_build_not_reused` pins it.
- **D12 — `run_affected` docs matching.** "Names the file's directory" means the directory path appears as a whole path. The pattern is the regex `<dir>/?([^A-Za-z0-9_./-]|$)`, so `docs/y.md` does not name the directory `docs` of `docs/x.md`. Changed files come from `git diff --name-only --no-renames`, so a rename lists both paths (Review Focus 5).
- **D13 — Seeds first, rulings with R6.** Each W2 suite task sets `TESTS_EXCLUSIVE` to the spec's seed list at once (the seeds are already ruled `in`). Ruling lines, and any changes the scan forces, come in the task that does that suite's R6 conversions:
  - W2 for studio_setup and the small timing suites;
  - W3 for overnight;
  - W4 for lanes.

  The guard test that requires them, `test_exclusive_scan_candidates_ruled`, lands in W5.
- **D14 — New suites' floors.** `harness_test`, `run_all_test` and `run_affected_test` have no table row until F3. run_all runs them as single jobs with floor 1 and prints a note. F3 adds their rows, with floors taken from the first green integrated gate.
- **D15 — T5's detach budget test uses a plain `sleep 309` child.** The no-lock window kills the child's group, so the test scans for nothing. T6 converts it to `$TMP/bin/msleep 309` with the other C5/C6 sleepers.

## Review Focus

1. **A job that times out with descendants in their own group** (an `own_group` runner, a setsid'd detach child). The person expects the timeout to leave nothing running. It is pinned by T2's `test_run_all_job_timeout`, whose fixture starts an `own_group` msleep under its job `TMPDIR` and asserts that `pgrep -f "$LOGDIR"` is empty afterwards (D4).
2. **Ctrl-C in serial mode (`TEST_JOBS=1`).** The person expects today's behaviour: the suite stops, run_all prints a summary marked interrupted and exits 130, and no suite process survives. It is pinned by T2's `test_run_all_serial_ctrl_c`.
3. **A developer's shell with a stale `TEST_PHASE`/`TEST_SHARD` exported.** Their "standalone" `sh tests/x_test.sh` would quietly run a subset. When a phase is set, `run_tests` prints `partition <part>` as its first line, so the subset is visible. It is pinned by T1's `test_partition_named_in_output`.
4. **`TEST_LOG_DIR` with a space in its path.** The launch, the rc rename and the `pkill -f` sweep must all quote it. It is pinned by T2's `test_run_all_log_dir_with_space`.
5. **A renamed file in `run_affected`.** With rename detection on, `git diff --name-only` lists only the new path, and the old path's readers are missed. It is pinned by T3's `test_affected_rename_counts_both_paths` (D12).

## Execution model

- **Subagent-driven, maximum parallelism.** Tasks are grouped into waves. Tasks in one wave touch disjoint files (tests included), so they run at once.
  - Worktrees: at a wave's start the controller makes one worktree per task, off the story branch's tip. Each is named `.claude/worktrees/54-T<n>`, on branch `54-T<n>`.
  - Integration: the controller cherry-picks each task's commits onto `54-faster-test-gate` in task-id order. Files are disjoint, so a conflict means a task broke scope: stop and ask.
  - Cleanup: a task's worktree is removed once its commits are on the story branch.
- **Models.** Implementers run on Sonnet (the floor: Haiku ignores per-task worktrees). Per-task reviews of tasks tagged **risky**, and the final whole-branch review, run on Opus. **mech** tasks fold into the final review.
- **Briefs.**
  - Each brief quotes its task section of this plan, by line range (not the plan path).
  - It also carries the Global Constraints, the Shared interfaces section and the spec sections the task names.
  - A brief reads code by `grep -n`, then the whole function or region; never a whole-file `cat` of a big suite.
  - A hand-back is 1.5k chars or less; the full report goes to `$SP/reports/T<n>.md`.
- **Fix rounds.**
  - A fix round goes to a fresh fixer, given the findings and the diff range. A finished implementer is never revived.
  - Minor findings batch into the final fix wave.
  - Re-review only after a Critical, 3+ Importants or a production-bug fix. Never a third pass.
- **Wave integration check** (controller, after each wave's cherry-picks). Light suites only, one at a time:
  - after W1: `sh tests/harness_test.sh && sh tests/run_all_test.sh && sh tests/run_affected_test.sh && sh tests/lib_test.sh`;
  - after W2 to W5: each touched light suite, standalone.

  Heavy suites are checked only inside their own tasks.
- `$SP` is the session scratchpad. The controller passes its absolute path in every brief.

### Wave/task table

| Wave | Task | Title | Touches | Risk |
|---|---|---|---|---|
| — | T0 | Preflight: base, floors, heavy lock | (no repo files) | — |
| 1 | T1 | Harness core | `tests/assert.sh`, `tests/harness_test.sh` (new), `tests/lib_test.sh`, `tests/exclusive_scan.awk` (new) | risky (new seam) |
| 1 | T2 | Parallel runner | `tests/run_all.sh`, `tests/run_all_test.sh` (new) | risky (new seam, timing) |
| 1 | T3 | Affected-suites runner | `tests/run_affected.sh` (new), `tests/run_affected_test.sh` (new) | risky (new seam) |
| 1 | T4 | Setup and gate poll knobs | `studios/game-dev/bin/studio-setup`, `studios/game-dev/bin/studio-gate`, `tests/studio_setup_test.sh`, `tests/toolkit_test.sh` | risky (cross-system, timing) |
| 1 | T5 | Reap and detach poll knobs | `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-lanes.sh`, `tests/overnight_test.sh`, `tests/overnight_lanes_test.sh` | risky (cross-system, timing) |
| 2 | T6 | Lanes suite hermetic | `tests/overnight_lanes_test.sh` | risky (cross-system) |
| 2 | T7 | Overnight suite hermetic | `tests/overnight_test.sh` | risky (cross-system) |
| 2 | T8 | studio_setup suite: hermetic, waits, tags | `tests/studio_setup_test.sh` | risky (timing) |
| 2 | T9 | `mktemp` templates, mechanical suites | `tests/{install,omega,overnight_sessions,sdd_script,state,studio_adopt,studio_brief,studio_env,studio_event,studio_peers,studio,sync}_test.sh`, `tests/state_fixtures.sh` | mech |
| 2 | T10 | Small timing suites: tags, rulings, hook wait, own_group | `tests/{toolkit,hook,state_pointer,state_move,overnight_runs,overnight_progress}_test.sh` | risky (timing) |
| 3 | T11 | Lanes event waits (R6) | `tests/overnight_lanes_test.sh` | risky (timing) |
| 3 | T12 | Overnight waits, templates, rulings | `tests/overnight_test.sh` | risky (timing, data) |
| 4 | T13 | Lanes templates and rulings | `tests/overnight_lanes_test.sh` | risky (data) |
| 4 | T14 | README Tests section | `README.md` | mech |
| 5 | T15 | Static guards and ruling check | `tests/harness_test.sh` | mech |
| end | F1–F8, T16 | Review, fix wave, full gate, acceptance, A/B, floors, PROGRESS, follow-ups | see each | — |

## Shared interfaces

These names and formats are fixed. Every task codes against them.

**Harness environment** (named in the `assert.sh` header; empty means unset):

| Name | Set by | Meaning |
|---|---|---|
| `TEST_PHASE` | run_all, tests | unset: all tests in listed order · `parallel` · `exclusive` |
| `TEST_SHARD` | run_all, tests | `k/N`, only with `parallel`; unset = `1/1` |
| `TEST_TIMING_LOG` | run_all, tests | absolute path; append `L`/`T` rows |
| `TESTS_ONLY` | developer, tests | intersected with the partition |
| `TEST_SH` | run_all (exported to jobs) | the shell for nested suite runs in `harness_test.sh` (`${TEST_SH:-sh}`) |
| `TEST_NAME` | `run_tests` | the running test's name, set before `before_each` |

**Suite declarations** (before `run_tests`): `TESTS_EXCLUSIVE="…"`, `TESTS_REAL_CLOCK="…"`, `TESTS_FINAL="…"`, and an optional function `before_each`.

**`assert.sh` functions:**

- `is_real_clock`: status 0 when `$TEST_NAME` is in `TESTS_REAL_CLOCK` or `TESTS_EXCLUSIVE`.
- `own_group CMD…`: `exec`s CMD in a group of its own, with INT and QUIT at their defaults. It must be the last command of a `( … ) &` subshell; `$!` is then CMD's pid.
- `mk_msleep`: needs `$TMP`. It makes `$TMP/bin/msleep`, a symlink to `sleep`, or a perl sleeper when the symlink fails `msleep 0`. It returns non-zero if neither works.
- `next_second`: returns once `date +%s` has changed, polling every 0.1 s with a 3 s ceiling.

**Timing rows** (tab-separated, one `>>` append each):

```
L  <suite>  <part>  <listed-count>  <final-idxs: comma list, or ->
T  <suite>  <part>  <idx>  <test>  <seconds>  <assertions>  <failed>
```

- `<suite>` is `basename "$0" .sh`, e.g. `overnight_lanes_test`.
- `<part>` is `all` (no phase), `p<k>of<N>` (parallel; unsharded is `p1of1`), `x` (exclusive) or `bad` (bad phase or shard).
- `<idx>` is the 1-based position in the `run_tests` arguments.

**run_all:**

- Environment: `TEST_JOBS`, `TEST_SUITES`, `TEST_LOG_DIR`, `TEST_SLOWEST`, `TEST_JOB_TIMEOUT`, `TEST_SH`, and the test-only `RUN_ALL_SUITES_DIR` and `RUN_ALL_TABLE`.
- Job id: `<suite>` in serial mode, otherwise `<suite>.<part>`.
- Job dir: `$LOGDIR/<job>/` holds `tmp/` (the job's `TMPDIR`), `log`, `rc`, `pid`, `t0` and `meta` (`<suite> <part>`).
- `summary.tsv` row: `suite part secs tests assertions failed verdict`. The verdict is `green` or `red: <reason>`.
- Table row: `<suite> <shards> <floor>`. `#` starts a comment.

**Knob locals** (each validated at startup):

| Knob | Script | Locals |
|---|---|---|
| `STUDIO_SETUP_POLL_SECONDS` | studio-setup | `SETUP_POLL`, `SETUP_TPS` |
| `STUDIO_GATE_POLL_SECONDS` | studio-gate | `GATE_POLL`, `GATE_TPS` |
| `STUDIO_OVERNIGHT_REAP_POLL_SECONDS` | studio-overnight, read by overnight-lanes.sh | `REAP_POLL`, `REAP_TPS` |
| `STUDIO_OVERNIGHT_DETACH_POLL_SECONDS` | studio-overnight | `DETACH_POLL`, `DETACH_TPS` |

**Stub actions:**

- `waitexist PATH`: waits until `-e PATH`, polling every 0.1 s, at most 600 ticks.
- `@RUN@` in a `waitfor`/`waitafter`/`waitexist` path expands to `$STUDIO_RUN_DIR`.
- A stub wait that reaches its ceiling appends its path to `$CALLS/wait.timeout`.

**Fixture templates:**

- Switches: `LANES_FIXTURE_TEMPLATES` and `OVERNIGHT_FIXTURE_TEMPLATES`, default 1; 0 builds fresh.
- Layout: `$TMP/tpl/l-<key>/{p,p.git,ok}` for lanes and `$TMP/tpl/o-<key>/{p,p.git,ok}` for overnight.
- `<key>` is `cksum` output with its space turned into `-`.

**Exclusive scan:**

- `awk -f tests/exclusive_scan.awk tests/X_test.sh…` prints `suite<TAB>test<TAB>flags<TAB>evidence`. Flags are from `abd`; evidence is `flag:line` pairs.
- A ruling line sits directly above the suite's `TESTS_EXCLUSIVE=` line:
  `# exclusive-scan: <test> in|out (<criterion or flag>) <reason>`.

**Exemption comment:** a trailing `# scan-ok: <reason>` on a `pgrep`/`pkill`/`ps -A`/`mktemp` line.

## File Structure

- `tests/assert.sh` holds the env scrub, the helpers, `run_tests` partitions and validation, and the timing rows (T1).
- `tests/harness_test.sh` is new. T1 adds the R1, R3 and helper tests; T15 adds the static guards, the ruling check and the knob-header check.
- `tests/exclusive_scan.awk` is new: the R5 mechanical scan (T1).
- `tests/run_all.sh` is rewritten, and `tests/run_all_test.sh` is new (T2). F3 and F6 edit the table.
- `tests/run_affected.sh` and `tests/run_affected_test.sh` are new (T3).
- The four production scripts get the R7 knobs only (T4, T5).
- The suites change per the wave table.
- `README.md` Tests section (T14). `docs/game-dev/PROGRESS.md` entry (T16).

---

### Task 0: Preflight — base, floors, heavy lock (controller, inline)

Risk: — . No repo files.

- [ ] **Step 1: Base check.** Run `git fetch -q origin && git rev-parse origin/main`. If it is not 6f2445b, rebase `54-faster-test-gate` onto it, re-run the floor counts below for the suites that changed, and relocate this plan's anchors.
- [ ] **Step 2: Overnight floor.** Read `$SP/plan-probe/count-overnight_test.log`. It is the 6f2445b export run alone, started during planning. Take the number from its last line, `N assertions, M failed`. If the file is missing or the run is not finished, run it alone:
  `sh "$SP/heavy.sh" "$SP/plan-probe/count-overnight_test.log" sh -c 'cd "$SP/plan-probe/repo" && sh tests/overnight_test.sh'`.
  Measured during planning: **1132 assertions, 0 failed** (6f2445b, run alone). Re-measure only if origin/main moved.
- [ ] **Step 3: Write `$SP/heavy.sh`:**

```sh
#!/bin/sh
# heavy.sh LOG CMD… — run CMD (a whole heavy suite) holding $SP/heavy.lock, so at most one
# heavy suite runs on this machine at a time; output to LOG, then "rc=<n>". Run it in the
# background and wait for its notification.
L="$(cd "$(dirname "$0")" && pwd)/heavy.lock"
until mkdir "$L" 2>/dev/null; do sleep 10; done
trap 'rmdir "$L"' EXIT
trap 'exit 130' INT TERM
log="$1"; shift
"$@" > "$log" 2>&1; rc=$?
echo "rc=$rc" >> "$log"
exit "$rc"
```

- [ ] **Step 4: Early-env check (R2.1).** Run `for f in tests/*_test.sh; do a=$(grep -n 'assert.sh"' "$f" | head -1 | cut -d: -f1); grep -n 'STUDIO_\|OMEGA_\|CLAUDE' "$f" | awk -F: -v a="$a" '$1 < a'; done`. Already run while planning: the only hits are comment lines (omega_test :5, sdd_script_test :3, studio_env_test :3). Record "none" in `$SP/reports/T0.md`.
- [ ] **Step 5: Provisional floors** (from the falsifier's all-alone sweep and the voided run's green rows; these counts do not depend on load). They go into T2's brief:

| suite | floor | suite | floor | suite | floor |
|---|---|---|---|---|---|
| overnight_lanes_test | 1128 | studio_adopt_test | 306 | state_guard_test | 66 |
| overnight_test | 1132 | install_test | 369 | overnight_progress_test | 39 |
| studio_test | 661 | hook_test | 287 | overnight_runs_test | 41 |
| omega_test | 503 | state_test | 245 | studio_env_test | 43 |
| state_move_test | 244 | state_pointer_test | 179 | studio_event_test | 38 |
| toolkit_test | 175 | lib_test | 112 | overnight_sessions_test | 23 |
| studio_brief_test | 111 | state_stories_test | 105 | studio_peers_test | 23 |
| studio_setup_test | 49 | sdd_script_test | 22 | pointer_skills_omega_test | 16 |
| pointer_skills_route_test | 15 | pointer_skills_execute_test | 14 | sync_test | 8 |

Lanes is 1128, the higher of the two observed counts (1127 and 1128; spec "Floors"). T6's peers loop makes the new count ≥ 1128.

---

## Wave 1

### Task 1: Harness core

Risk: **risky** (new seam). Review: task (Opus).

**Touches:** `tests/assert.sh`, `tests/harness_test.sh` (new), `tests/lib_test.sh`, `tests/exclusive_scan.awk` (new).

**Interfaces:**
- Produces: everything under "Shared interfaces → Harness environment, Suite declarations, assert.sh functions, Timing rows", plus `tests/exclusive_scan.awk`.
- Consumes: nothing new.

**Tests** (in `harness_test.sh`, all in its `run_tests` list):
- R1: `test_timing_log_rows`, `test_timing_log_off_by_default`, `test_timing_log_l_row_for_empty_partition`.
- R3: `test_shards_cover_every_test_once`, `test_no_phase_runs_all_in_order`, `test_exclusive_phase_runs_only_tagged`, `test_bad_shard_and_phase_fail_loudly`, `test_misspelt_tag_fails_in_every_phase`, `test_tests_only_intersects_partition`, `test_before_each_sees_test_name`, `test_real_clock_includes_exclusive`, `test_partition_named_in_output` (Review Focus 3).
- R2 and helpers: `test_env_scrub`, `test_own_group_gives_group_and_int`, `test_mk_msleep`, `test_next_second`, `test_harness_private_names_unused`.
- R5: `test_exclusive_scan_flags_fixture`.
- lib_test keeps `test_run_tests_unknown_name`. Its child call adds `TEST_PHASE= TEST_SHARD= TEST_TIMING_LOG=`, and its `mktemp` takes the template.

**Acceptance:**
```sh
sh tests/harness_test.sh && dash tests/harness_test.sh
TEST_SH=dash dash tests/harness_test.sh
sh tests/lib_test.sh && dash tests/lib_test.sh
sh tests/sync_test.sh | tail -n 1                                  # "8 assertions, 0 failed" (unchanged standalone)
TEST_PHASE=parallel TEST_SHARD=2/3 sh tests/state_guard_test.sh | head -n 1   # "partition p2of3"
```

- [ ] **Step 1: Write `harness_test.sh` with every test above, failing.** It has the usual suite header, `TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/harness_test.XXXXXX")" && pwd -P)"` and `trap 'rm -rf "$TMP"' EXIT`. Use these helpers:

```sh
# gen_suite FILE — 23 tests t01..t23 (one passing assertion each); t05 t12 t19
# exclusive; t08 final. EXTRA (optional 2nd arg) is shell text placed before run_tests.
gen_suite() {
  { printf '. "%s/tests/assert.sh"\n' "$REPO_ROOT"
    _g=1; while [ "$_g" -le 23 ]; do
      printf 't%02d() { assert_eq 1 1 t%02d; }\n' "$_g" "$_g"; _g=$((_g + 1)); done
    printf 'TESTS_EXCLUSIVE="t05 t12 t19"\nTESTS_FINAL="t08"\n%s\nrun_tests' "${2:-}"
    _g=1; while [ "$_g" -le 23 ]; do printf ' t%02d' "$_g"; _g=$((_g + 1)); done; printf '\n'
  } > "$1"
}
# child PHASE SHARD LOG FILE [ONLY] — FILE under ${TEST_SH:-sh} with exactly these harness
# variables (an outer run_all job's own TEST_* never leak in); stdout+stderr to FILE.out.
child() {
  ( cd "$TMP" && TESTS_ONLY="${5:-}" TEST_PHASE="$1" TEST_SHARD="$2" TEST_TIMING_LOG="$3" \
      ${TEST_SH:-sh} "$4" ) > "$4.out" 2>&1
}
```

`test_shards_cover_every_test_once` (the core property):

```sh
test_shards_cover_every_test_once() {
  gen_suite "$TMP/cov_test.sh"
  for _n in 1 2 3 7 19; do
    _log="$TMP/cov-$_n.tsv"; : > "$_log"; _k=1
    while [ "$_k" -le "$_n" ]; do child parallel "$_k/$_n" "$_log" "$TMP/cov_test.sh"; _k=$((_k + 1)); done
    child exclusive "" "$_log" "$TMP/cov_test.sh"
    _bad="$(awk -F'\t' -v p=$((_n + 1)) '$1 == "T" { c[$4]++ }
      END { for (i = 1; i <= 23; i++) { w = (i == 8) ? p : 1; if (c[i] + 0 != w) printf "%d:%d ", i, c[i] } }' "$_log")"
    assert_eq "" "$_bad" "N=$_n: each test once, the final (idx 8) once per partition"
    assert_eq "$((_n + 1))" "$(grep -c '^L	' "$_log")" "N=$_n: one L row per partition"
    _lastok="$(awk -F'\t' '$1 == "T" { last[$3] = $4 } END { for (p in last) if (last[p] != 8) print p }' "$_log")"
    assert_eq "" "$_lastok" "N=$_n: the final runs last in every partition"
  done
}
```

The other tests, one line each (use `gen_suite` and `child`):
- `test_no_phase_runs_all_in_order`: the T rows' idx sequence is exactly `1 … 23` (t08 at position 8), and the L row is `L cov_test all 23 8`.
- `test_exclusive_phase_runs_only_tagged`: the idx sequence is `5 12 19 8`.
- `test_bad_shard_and_phase_fail_loudly`: for `0/3 4/3 x 3 1/2/3 08/9 1/0` with `parallel`, for `1/2` with no phase, and for phase `serial`:
  - exit status ≠ 0;
  - the output holds `FAIL bad TEST_SHARD`, `FAIL TEST_SHARD needs TEST_PHASE=parallel` or `FAIL bad TEST_PHASE`;
  - the L row's part is `bad`, and there are no T rows.
- `test_misspelt_tag_fails_in_every_phase`: with `TESTS_REAL_CLOCK="t99"` appended, every phase (`""`, `parallel 1/1`, `exclusive`) exits ≠ 0 and prints `FAIL TESTS_REAL_CLOCK names unknown test t99`. With `TESTS_FINAL="t05"` it prints `FAIL t05 is both exclusive and final`.
- `test_tests_only_intersects_partition`: `ONLY="t01 t02 t05 t08"` with `parallel 1/2` runs exactly idx `1 8`. idx 2 is in shard 2, idx 5 is exclusive and idx 8 is the final.
- `test_before_each_sees_test_name`: EXTRA `before_each() { echo "$TEST_NAME" >> "$TMP/be.log"; }`. `be.log` equals the run order.
- `test_real_clock_includes_exclusive`: EXTRA sets `TESTS_REAL_CLOCK=t01` and `before_each` logs `$TEST_NAME $(is_real_clock && echo rc || echo fast)`. t01 and t05 are `rc`; t02 is `fast`.
- `test_partition_named_in_output`: with `parallel 2/3` the first output line is `partition p2of3`; with no phase there is no such line.
- `test_timing_log_rows`: a no-phase run gives 23 T rows, each `… 1 0` for assertions and failed. A suite whose t03 fails one assertion gives `… 1 1` on idx 3.
- `test_timing_log_off_by_default`: with `TEST_TIMING_LOG=` the `$TMP` listing is unchanged apart from `cov_test.sh.out`.
- `test_timing_log_l_row_for_empty_partition`: a suite with no `TESTS_EXCLUSIVE` and no finals, in phase `exclusive`, writes exactly one L row and no T row.
- `test_env_scrub`:
  - run `env STUDIO_STORY=s STUDIO_RUN_DIR=r OMEGA_AUTOPILOT=1 CLAUDE_CODE_SESSION_ID=c CLAUDE_CONFIG_DIR=d CLAUDECODE=1 GIT_DIR=g TESTS_ONLY=t TEST_SHARD=1/2 ${TEST_SH:-sh} -c '. "$1/tests/assert.sh"; env' sh "$REPO_ROOT"`;
  - keep only the lines matching `grep -E '^(STUDIO_STORY|STUDIO_RUN_DIR|OMEGA_AUTOPILOT|CLAUDE_CODE_SESSION_ID|CLAUDE_CONFIG_DIR|CLAUDECODE|GIT_DIR|TESTS_ONLY|TEST_SHARD)='`, then the names, sorted;
  - the result is exactly `TESTS_ONLY TEST_SHARD`.
- `test_own_group_gives_group_and_int`:
  - start `( own_group ${TEST_SH:-sh} -c 'trap "echo t > \"\$1\"; exit 7" INT; while :; do sleep 0.1; done' sh "$TMP/og.flag" ) & _p=$!`;
  - poll up to 5 s for `ps -o pgid= -p $_p` to equal `$_p`, then assert it;
  - `kill -INT "$_p"`; `wait` gives 7, and `og.flag` exists.
- `test_mk_msleep`, part 1: after `mk_msleep`, start `"$TMP/bin/msleep" 3 &`. Within 2 s, `pgrep -f "$TMP/bin/msleep 3\$"` gives its pid. Kill it.
- `test_mk_msleep`, part 2:
  - in a subshell, put a fake `sleep` at the front of PATH: `case "${0##*/}" in sleep) exec /bin/sleep "$@";; *) exit 1;; esac`;
  - set `TMP=$TMP/m2` and call `mk_msleep`;
  - then `$TMP/m2/bin/msleep` starts with `#!`, and `"$TMP/m2/bin/msleep" 0` exits 0.
- `test_next_second`:
  - take `t0` from `perl -MTime::HiRes=time -e 'printf "%.3f", time'`;
  - `next_second`, then read t1 the same way;
  - `date +%s` has moved past the second it read at the start;
  - `t1 - t0 < 1.5` (awk compare).
- `test_harness_private_names_unused`: `grep -l '__rt_' tests/*_test.sh tests/state_fixtures.sh | grep -v harness_test.sh` is empty.
- `test_exclusive_scan_flags_fixture`: a fixture suite has five functions:
  - `test_a` with `[ $(( $(date +%s) - _t )) -le 5 ]`;
  - `test_b` with `kill -INT "$p"`;
  - `test_c` with `printf 'sleep 2\n' > "$SCEN/A"`;
  - `test_d` with `--seconds 1`;
  - `test_e`, clean.

  The scan's output is exactly four rows, with flags `a`, `b`, `d` and `d`.

- [ ] **Step 2: Run it to verify it fails.** `sh tests/harness_test.sh` → FAIL lines ("no test function", missing helpers).
- [ ] **Step 3: Implement `assert.sh`.** Its first lines, after `#!/bin/sh`, are the header and then the scrub:

```sh
# Assertion helpers and a minimal test runner. Sourced by test files.
#
# On source: unsets CLAUDECODE, AI_AGENT, CLAUDE_*, OMEGA_*, STUDIO_* and GIT_DIR,
# GIT_WORK_TREE, GIT_INDEX_FILE, GIT_COMMON_DIR, GIT_OBJECT_DIRECTORY,
# GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_NAMESPACE (a suite never inherits an
# autopilot unit's or a repo's context). TESTS_ONLY and TEST_* are kept.
# Environment (empty = unset):
#   TESTS_ONLY="a b"  run only these (intersected with the partition)
#   TEST_PHASE        unset: every test in listed order · parallel: this shard,
#                     then TESTS_FINAL · exclusive: TESTS_EXCLUSIVE, then TESTS_FINAL
#   TEST_SHARD=k/N    with TEST_PHASE=parallel: eligible test j runs when (j-1) mod N = k-1
#   TEST_TIMING_LOG   append an L row per run_tests call and a T row per test
# Suite declarations before run_tests: TESTS_EXCLUSIVE, TESTS_REAL_CLOCK, TESTS_FINAL
# (space-separated test names) and an optional before_each function (TEST_NAME is set).
# Helpers: is_real_clock, own_group CMD…, mk_msleep, next_second.
for __rt_v in $(env | sed -nE 's/^(CLAUDECODE|AI_AGENT|CLAUDE_[A-Za-z0-9_]*|OMEGA_[A-Za-z0-9_]*|STUDIO_[A-Za-z0-9_]*|GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_COMMON_DIR|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_NAMESPACE)=.*/\1/p'); do
  unset "$__rt_v"
done
```

Keep the existing assertion helpers as they are. Add the helpers:

```sh
# own_group CMD… — exec CMD in a process group of its own with SIGINT/SIGQUIT at their
# defaults (what `set -m` gives a background job, but also under dash with no tty). The last
# command of a background subshell: `( cd "$P" && own_group sh "$RUNNER" start ) & PID=$!`.
own_group() { exec perl -e '$SIG{INT}=$SIG{QUIT}="DEFAULT"; setpgrp(0,0); exec @ARGV or die "exec: $!\n"' "$@"; }
# mk_msleep — $TMP/bin/msleep: a sleep whose argv carries $TMP (pgrep -f "$TMP/bin/msleep N$").
# A symlink to sleep, or, where sleep dispatches on argv[0] (busybox), a perl sleeper.
mk_msleep() {
  mkdir -p "$TMP/bin" || return 1
  rm -f "$TMP/bin/msleep"
  ln -s "$(command -v sleep)" "$TMP/bin/msleep" && "$TMP/bin/msleep" 0 2>/dev/null && return 0
  rm -f "$TMP/bin/msleep"
  printf '#!/usr/bin/env perl\nselect(undef, undef, undef, $ARGV[0]);\n' > "$TMP/bin/msleep" \
    && chmod +x "$TMP/bin/msleep" && "$TMP/bin/msleep" 0
}
# next_second — return once `date +%s` has moved on (a new run-dir name); 3 s ceiling.
next_second() {
  __rt_ns=$(date +%s); __rt_ni=0
  while [ "$(date +%s)" = "$__rt_ns" ] && [ "$__rt_ni" -lt 30 ]; do sleep 0.1; __rt_ni=$((__rt_ni + 1)); done
}
```

Replace `run_tests` with the partition logic below. This is the hard part, so it is given in full:

```sh
__rt_in() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
__rt_row() { [ -z "${TEST_TIMING_LOG:-}" ] || printf '%s\n' "$1" >> "$TEST_TIMING_LOG"; }
__rt_failv() { TESTS_RUN=$((TESTS_RUN + 1)); _fail "$1"; }
is_real_clock() { __rt_in "${TEST_NAME:-}" "${TESTS_REAL_CLOCK:-} ${TESTS_EXCLUSIVE:-}"; }

# run_tests NAME… — see the header. Fails loudly on a bad phase/shard (no test runs) or a
# tag naming an unlisted test (every selected test still runs); a listed name that is not a
# function fails too, so a test can never drop out of a suite silently.
run_tests() {
  __rt_suite="$(basename "$0" .sh)"; __rt_ph="${TEST_PHASE:-}"; __rt_sh="${TEST_SHARD:-}"
  __rt_k=1; __rt_n=1; __rt_bad=""
  case "$__rt_ph" in
    ''|parallel|exclusive) ;;
    *) __rt_bad="bad TEST_PHASE '$__rt_ph' (want parallel or exclusive)" ;;
  esac
  if [ -z "$__rt_bad" ] && [ -n "$__rt_sh" ]; then
    if [ "$__rt_ph" != parallel ]; then
      __rt_bad="TEST_SHARD needs TEST_PHASE=parallel"
    else
      __rt_k="${__rt_sh%%/*}"; __rt_n="${__rt_sh#*/}"
      case "$__rt_k/$__rt_n" in
        */*/*|*[!0-9/]*|/*|*/|0*|*/0*) __rt_bad="bad TEST_SHARD '$__rt_sh' (want k/N with 1 <= k <= N)" ;;
        *) [ "$__rt_k" -le "$__rt_n" ] || __rt_bad="bad TEST_SHARD '$__rt_sh' (want k/N with 1 <= k <= N)" ;;
      esac
    fi
  fi
  if [ -n "$__rt_bad" ]; then __rt_part=bad
  elif [ "$__rt_ph" = parallel ]; then __rt_part="p${__rt_k}of${__rt_n}"
  elif [ "$__rt_ph" = exclusive ]; then __rt_part=x
  else __rt_part=all; fi
  [ -z "$__rt_ph" ] || printf 'partition %s\n' "$__rt_part"
  [ -z "$__rt_bad" ] || __rt_failv "$__rt_bad"
  for __rt_v in TESTS_EXCLUSIVE TESTS_REAL_CLOCK TESTS_FINAL; do
    eval "__rt_l=\${$__rt_v:-}"
    for __rt_w in $__rt_l; do
      __rt_in "$__rt_w" "$*" || __rt_failv "$__rt_v names unknown test $__rt_w"
    done
  done
  for __rt_w in ${TESTS_EXCLUSIVE:-}; do
    if __rt_in "$__rt_w" "${TESTS_FINAL:-}"; then __rt_failv "$__rt_w is both exclusive and final"; fi
  done
  # Selection: "idx:name" words. A phase runs the finals after its own tests.
  __rt_sel=""; __rt_fsel=""; __rt_fin=""; __rt_i=0; __rt_j=0
  for __rt_t in "$@"; do
    __rt_i=$((__rt_i + 1))
    if __rt_in "$__rt_t" "${TESTS_FINAL:-}"; then
      __rt_fin="$__rt_fin${__rt_fin:+,}$__rt_i"; __rt_fsel="$__rt_fsel $__rt_i:$__rt_t"
      [ -z "$__rt_ph" ] || continue
    fi
    [ -z "$__rt_bad" ] || continue
    case "$__rt_ph" in
      '') __rt_sel="$__rt_sel $__rt_i:$__rt_t" ;;
      exclusive)
        if __rt_in "$__rt_t" "${TESTS_EXCLUSIVE:-}"; then __rt_sel="$__rt_sel $__rt_i:$__rt_t"; fi ;;
      parallel)
        if ! __rt_in "$__rt_t" "${TESTS_EXCLUSIVE:-}"; then
          __rt_j=$((__rt_j + 1))
          if [ $(( (__rt_j - 1) % __rt_n )) -eq $((__rt_k - 1)) ]; then __rt_sel="$__rt_sel $__rt_i:$__rt_t"; fi
        fi ;;
    esac
  done
  if [ -n "$__rt_ph" ] && [ -z "$__rt_bad" ]; then __rt_sel="$__rt_sel$__rt_fsel"; fi
  __rt_row "$(printf 'L\t%s\t%s\t%s\t%s' "$__rt_suite" "$__rt_part" "$#" "${__rt_fin:--}")"
  for __rt_e in $__rt_sel; do
    __rt_t="${__rt_e#*:}"
    if [ -n "${TESTS_ONLY:-}" ] && ! __rt_in "$__rt_t" "$TESTS_ONLY"; then continue; fi
    printf '%s\n' "$__rt_t"
    TEST_NAME="$__rt_t"
    __rt_r0=$TESTS_RUN; __rt_f0=$TESTS_FAILED; __rt_s0=$(date +%s)
    case "$(type before_each 2>/dev/null)" in *function*) before_each ;; esac
    case "$(type "$__rt_t" 2>/dev/null)" in
      *function*) "$__rt_t" ;;
      *) __rt_failv "no test function $__rt_t" ;;
    esac
    __rt_row "$(printf 'T\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$__rt_suite" "$__rt_part" "${__rt_e%%:*}" "${__rt_e#*:}" \
      $(( $(date +%s) - __rt_s0 )) $((TESTS_RUN - __rt_r0)) $((TESTS_FAILED - __rt_f0)))"
  done
  printf '\n%s assertions, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
```

`case "$__rt_k/$__rt_n"` rejects:
- non-digits;
- an extra `/` (`1/2/3` gives n=`2/3`);
- an empty side;
- leading zeros, so `$(( ))` never sees octal (`08`).

Without a `/`, k=n=the whole value, and a phase-less shard is caught earlier. A single `3` gives `3/3`. **Reject it too:** add `case "$__rt_sh" in */*) ;; *) __rt_bad=… ;; esac` before the split.

- [ ] **Step 4: `exclusive_scan.awk`.** Copy `$SP/plan-probe/excl-scan.awk` and keep its header. On 6f2445b it flags 85 tests: lanes 47, overnight 17, toolkit 11, studio_setup 4, state_pointer 3, and 1 each in state_move, overnight_runs and overnight_progress. Check with `awk -f tests/exclusive_scan.awk tests/*_test.sh | wc -l`: 85 at this point, since no suite has changed yet.
- [ ] **Step 5: lib_test.**
  - `:7`: `TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lib_test.XXXXXX")" && pwd -P)"`.
  - `:346`: `TESTS_ONLY='' TEST_PHASE= TEST_SHARD= TEST_TIMING_LOG= sh -c …`.
- [ ] **Step 6: Run the acceptance commands.** Expected: all green, and `sync_test` still prints `8 assertions, 0 failed`.
- [ ] **Step 7: Commit:** `git add tests/assert.sh tests/harness_test.sh tests/lib_test.sh tests/exclusive_scan.awk && git commit -m "test(harness): partitions, timing rows, env scrub, own_group/mk_msleep/next_second (#54)"`.

---

### Task 2: Parallel runner

Risk: **risky** (new seam, timing). Review: task (Opus).

**Touches:** `tests/run_all.sh` (rewritten), `tests/run_all_test.sh` (new).

**Interfaces:**
- Consumes: the timing-row formats and the `TEST_*` names (Shared interfaces). It does **not** source T1's code. Its fixture suites write their own rows.
- Produces: the run_all environment, job dir layout, `summary.tsv` and exit codes. The suite table's format is `<suite> <shards> <floor>`, edited later by F3 and F6.

**Tests** (in `run_all_test.sh`):
- spec R4: `test_run_all_green_parallel`, `test_run_all_red_suite_fails_gate`, `test_run_all_missing_summary_line_is_red`, `test_run_all_no_l_row_is_red`, `test_run_all_below_floor_is_red`, `test_run_all_unran_test_is_red`, `test_run_all_double_run_is_red`, `test_run_all_respects_job_bound`, `test_run_all_exclusive_runs_alone_after_pool`, `test_run_all_serial_mode_is_today`, `test_run_all_job_sees_trappable_int`, `test_run_all_job_has_own_session`, `test_run_all_job_tmpdir_is_per_job`, `test_run_all_ctrl_c_cleans_up`, `test_run_all_job_timeout` (with D4's escaped sleeper), `test_run_all_bad_jobs_value`, `test_run_all_unknown_suite`;
- spec R1: `test_run_all_summary_and_slowest`;
- Review Focus: `test_run_all_serial_ctrl_c`, `test_run_all_log_dir_with_space`.

**Acceptance:**
```sh
sh tests/run_all_test.sh
TEST_SH=dash dash tests/run_all_test.sh
```
A real-suite smoke, such as `TEST_SUITES=sync sh tests/run_all.sh`, is expected to be red in this worktree (`no run_tests row`), because T1's harness is not in yet. The controller runs it after the W1 integration.

- [ ] **Step 1: Write `run_all_test.sh`, failing.** Fixture suites live in `$SD="$TMP/suites"` and the table in `$TMP/table`. Each test runs `RUN_ALL_SUITES_DIR="$SD" RUN_ALL_TABLE="$TMP/table" TEST_LOG_DIR="$TMP/log-<t>" ${TEST_SH:-sh} "$REPO_ROOT/tests/run_all.sh"`, with stdout and stderr to a file. Fixture generator:

```sh
# fx NAME LISTED [BODY] — fixture suite $SD/NAME_test.sh. It runs BODY (shell text), then
# writes one L row and one T row per idx 1..LISTED for its partition (one assertion each),
# and prints the summary line. It names its partition from TEST_PHASE/TEST_SHARD only.
fx() {
  mkdir -p "$SD"
  cat > "$SD/$1_test.sh" <<EOF
pt=all
case "\${TEST_PHASE:-}" in parallel) s="\${TEST_SHARD:-1/1}"; pt="p\${s%/*}of\${s#*/}" ;; exclusive) pt=x ;; esac
row() { [ -z "\${TEST_TIMING_LOG:-}" ] || printf '%s\n' "\$1" >> "\$TEST_TIMING_LOG"; }
row "\$(printf 'L\t%s\t%s\t%s\t-' $1_test "\$pt" $2)"
${3:-:}
i=1; while [ "\$i" -le $2 ]; do row "\$(printf 'T\t%s\t%s\t%s\tt%s\t0\t1\t0' $1_test "\$pt" "\$i" "\$i")"; i=\$((i + 1)); done
printf '\n%s assertions, 0 failed\n' $2
EOF
}
# slot BODY text: a fixture that holds a slot for 1 s, recording the max live count in $TMP/slots.
SLOT='while ! mkdir "'"$TMP"'/slots.lk" 2>/dev/null; do sleep 0.05; done
n=$(( $(cat "'"$TMP"'/slots.n" 2>/dev/null || echo 0) + 1 )); echo $n > "'"$TMP"'/slots.n"
[ $n -le $(cat "'"$TMP"'/slots.max" 2>/dev/null || echo 0) ] || echo $n > "'"$TMP"'/slots.max"
rmdir "'"$TMP"'/slots.lk"; sleep 1
while ! mkdir "'"$TMP"'/slots.lk" 2>/dev/null; do sleep 0.05; done
echo $(( $(cat "'"$TMP"'/slots.n") - 1 )) > "'"$TMP"'/slots.n"; rmdir "'"$TMP"'/slots.lk"'
```

What each test does:
- `test_run_all_green_parallel`: three fixtures, `TEST_JOBS=3`.
  - exit 0;
  - each `=== <suite> [p1of1] N s ===` header appears once, followed straight away by that fixture's own summary line (no interleaving);
  - `summary.tsv` has 3 green rows.
- `test_run_all_red_suite_fails_gate`: a BODY of `exit 1` before the summary → exit 1, `red`.
- `test_run_all_missing_summary_line_is_red`: a BODY of `exit 0` → `red: no summary line`.
- `test_run_all_no_l_row_is_red`: a hand-written fixture that prints a green summary and writes no rows → `no run_tests row`.
- `test_run_all_below_floor_is_red`: table floor 5, `fx a 2` → `below its floor 5`.
- `test_run_all_unran_test_is_red`: a fixture whose L row says 3 but writes T rows for idx 1–2 → `test 3 never ran`.
- `test_run_all_double_run_is_red`: an extra T row for idx 2 → `test 2 (t2) ran 2 times`.
- `test_run_all_respects_job_bound`: 6 fixtures with BODY `$SLOT`, `TEST_JOBS=2` → `slots.max` is exactly 2.
- `test_run_all_exclusive_runs_alone_after_pool`:
  - two fixture files carry a `TESTS_EXCLUSIVE=t2` line. In phase `x` their BODY appends `x-start <epoch.ms>` to `$TMP/order` and runs `$SLOT`. In the parallel phase they append `p-end <epoch.ms>` after `$SLOT`.
  - Write them by hand; each fixture emits T rows only for the idx that belongs to its partition (idx 2 in `x`, idx 1 in `p1of1`).
  - Every `x-start` is later than every `p-end`, and `slots.max` stays ≤ 1 during x.
- `test_run_all_serial_mode_is_today`: `TEST_JOBS=1`.
  - The order file gets the suite names in name order.
  - Each fixture writes `${TEST_PHASE-unset}` and gets `unset`.
  - The headers are `=== <name>_test.sh ===`.
- `test_run_all_job_sees_trappable_int`: BODY `trap 'echo y > "$TMP/int.flag"' INT; kill -INT $$; sleep 0.2` → `int.flag` exists and the job is green.
- `test_run_all_job_has_own_session`:
  - BODY `echo "$PPID $(ps -o pgid=,tty= -p $$)" > "$TMP/sess"`;
  - fields 1 and 2 are equal and differ from `ps -o pgid= -p $$` of the test shell;
  - field 3 is `??` or `?`.
- `test_run_all_job_tmpdir_is_per_job`: two fixtures with BODY `echo "$TMPDIR" > "$TMP/td-<name>"` → each is under `$TMP/log-…/` and the two differ.
- `test_run_all_ctrl_c_cleans_up`: see the code below.
- `test_run_all_serial_ctrl_c`: the same as ctrl_c with `TEST_JOBS=1`, one fixture with BODY `touch "$TMP/ready-a"; sleep 300`. After INT: exit 130, `interrupted` in the output, and no `sleep 300` left under `pgrep -P` of the fixture. Record its pid in BODY with `echo $$ > "$TMP/pid-a"`, then `pgrep -P "$(cat "$TMP/pid-a")"` is empty and `kill -0` of that pid fails.
- `test_run_all_job_timeout`:
  - `TEST_JOB_TIMEOUT=2`;
  - BODY `mkdir -p "$TMPDIR/bin"; ln -s "$(command -v sleep)" "$TMPDIR/bin/msleep"; ( exec perl -e 'setpgrp(0,0); exec @ARGV' "$TMPDIR/bin/msleep" 300 ) & sleep 30`;
  - within 15 s: `red: timed out after 2 s`, exit 1, and `pgrep -f "$TMP/log-to"` is empty (D4).
- `test_run_all_bad_jobs_value`: `TEST_JOBS=0`, `x`, `-1` and `''` → exit 2 and `TEST_JOBS must be a positive integer`. An empty `TEST_JOBS` means the default, so assert exit 0 for `''`.
- `test_run_all_unknown_suite`: `TEST_SUITES=nope` → exit 2 and `unknown suite: nope_test`. A table row for a missing file → exit 2 and `table names a missing suite`.
- `test_run_all_summary_and_slowest`:
  - fixtures whose T rows carry seconds 3, 1 and 2 (an `fx` variant), with `TEST_SLOWEST=2`;
  - the summary has one row per job;
  - the slowest list has 2 lines, sorted 3 then 2.
- `test_run_all_log_dir_with_space`: `TEST_LOG_DIR="$TMP/log dir"` with two green fixtures → exit 0, and `"$TMP/log dir/summary.tsv"` has 2 rows. The dir is kept, since the caller gave it.

`test_run_all_ctrl_c_cleans_up` (the hard one):

```sh
test_run_all_ctrl_c_cleans_up() {
  _b='mkdir -p "$TMPDIR/bin"; ln -s "$(command -v sleep)" "$TMPDIR/bin/msleep"
( exec perl -e '"'"'$SIG{INT}=$SIG{QUIT}="DEFAULT"; setpgrp(0,0); exec @ARGV'"'"' "$TMPDIR/bin/msleep" 300 ) &
touch "'"$TMP"'/ready-$$"; sleep 300'
  fx cca 1 "$_b"; fx ccb 1 "$_b"
  printf 'cca_test 1 1\nccb_test 1 1\n' > "$TMP/table"
  RUN_ALL_SUITES_DIR="$SD" RUN_ALL_TABLE="$TMP/table" TEST_LOG_DIR="$TMP/log-cc" TEST_JOBS=2 \
    perl -MPOSIX -e '$SIG{INT}="DEFAULT"; POSIX::setsid() or die; exec @ARGV' \
    ${TEST_SH:-sh} "$REPO_ROOT/tests/run_all.sh" > "$TMP/cc.out" 2>&1 &
  _ra=$!
  _i=0; while [ "$(ls "$TMP"/ready-* 2>/dev/null | wc -l)" -lt 2 ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
  kill -INT "$_ra"
  _i=0; while kill -0 "$_ra" 2>/dev/null && [ "$_i" -lt 150 ]; do sleep 0.1; _i=$((_i + 1)); done
  _rc=0; wait "$_ra" || _rc=$?
  assert_eq 130 "$_rc" "INT ends run_all with 130 within 15 s"
  assert_eq "" "$(pgrep -f "$TMP/log-cc" 2>/dev/null)" "no job process, and no sleeper in a group of its own, survives"
  assert_contains "$TMP/cc.out" "interrupted" "the summary says interrupted"
}
```

- [ ] **Step 2: Run it to verify it fails.** Today's 10-line run_all has no table, pool or summary.
- [ ] **Step 3: Implement `run_all.sh`.** This is the hard part, given in full:

```sh
#!/bin/sh
# run_all.sh — the merge gate: every tests/*_test.sh suite.
#
# Parallel (default): each suite, or each shard of a sharded suite, is one job in a pool of
# at most TEST_JOBS, in a session and process group of its own (POSIX::setsid), with its own
# TMPDIR and log; then the TESTS_EXCLUSIVE tests of each suite that has them run alone. Each
# job's output is printed whole when it ends, then a summary and the slowest tests. A job is
# red on a non-zero exit, a missing or failing summary line, no status or a timeout; a suite
# is red when it wrote no run_tests row, a listed test did not run exactly once (finals once
# per partition), or its assertions are below its floor in the table below.
#
#   TEST_JOBS         concurrent jobs; default max(1, ncpu - 2). 1 = serial mode: today's
#                     gate (each suite whole, in name order, output streamed; no perl)
#   TEST_SUITES       space-separated suite names (with or without _test.sh); default all.
#                     A partial run is not the merge gate.
#   TEST_LOG_DIR      job logs, timing.tsv, summary.tsv; default a new temp dir, removed
#                     when the run is green
#   TEST_SLOWEST      length of the slowest-tests list (20)
#   TEST_JOB_TIMEOUT  seconds before a parallel job's group is killed (7200)
#   TEST_SH           the shell that runs each suite (sh); the dash acceptance run sets dash
#   RUN_ALL_SUITES_DIR, RUN_ALL_TABLE — test-only: the suites dir; a table file
# Exit: 0 green · 1 a check failed · 2 usage or table error · 128+N on INT/TERM/HUP.
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SDIR="${RUN_ALL_SUITES_DIR:-$SELF_DIR}"
TEST_SH="${TEST_SH:-sh}"; TEST_SLOWEST="${TEST_SLOWEST:-20}"; TIMEOUT="${TEST_JOB_TIMEOUT:-7200}"
unset TEST_PHASE TEST_SHARD TEST_TIMING_LOG

die2() { printf 'run_all: %s\n' "$*" >&2; exit 2; }
posint() { case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
ncpu() { _c="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"; posint "$_c" || _c=1; echo "$_c"; }

# The suite table: shard counts and assertion floors (each suite's count on origin/main).
# Heaviest first: this is also the launch order. A suite with no row runs as one job, floor 1.
table() {
  if [ -n "${RUN_ALL_TABLE:-}" ]; then cat "$RUN_ALL_TABLE"; return; fi
  cat <<'EOF'
# suite                      shards  floor
overnight_lanes_test         8       1128
overnight_test               4       1132
toolkit_test                 1       175
studio_adopt_test            1       306
install_test                 1       369
studio_setup_test            1       49
hook_test                    1       287
studio_test                  1       661
state_test                   1       245
omega_test                   1       503
state_move_test              1       244
state_pointer_test           1       179
studio_brief_test            1       111
lib_test                     1       112
state_stories_test           1       105
overnight_progress_test      1       39
sdd_script_test              1       22
studio_env_test              1       43
overnight_runs_test          1       41
state_guard_test             1       66
studio_peers_test            1       23
studio_event_test            1       38
overnight_sessions_test      1       23
sync_test                    1       8
pointer_skills_route_test    1       15
pointer_skills_omega_test    1       16
pointer_skills_execute_test  1       14
EOF
}

[ -n "${TEST_JOBS:-}" ] || { TEST_JOBS=$(( $(ncpu) - 2 )); [ "$TEST_JOBS" -ge 1 ] || TEST_JOBS=1; }
posint "$TEST_JOBS" || die2 "TEST_JOBS must be a positive integer, got '$TEST_JOBS'"
posint "$TIMEOUT" || die2 "TEST_JOB_TIMEOUT must be a positive integer, got '$TIMEOUT'"
posint "$TEST_SLOWEST" || die2 "TEST_SLOWEST must be a positive integer, got '$TEST_SLOWEST'"
command -v "$TEST_SH" >/dev/null 2>&1 || die2 "TEST_SH '$TEST_SH' not found"
[ "$TEST_JOBS" = 1 ] || command -v perl >/dev/null 2>&1 \
  || die2 "perl is required for parallel mode (TEST_JOBS=1 runs without it)"

TABLE="$(table | awk '/^[[:space:]]*(#|$)/ { next }
  NF != 3 || $2 !~ /^[1-9][0-9]*$/ || $3 !~ /^[0-9]+$/ { print "BAD row " NR ": " $0; next }
  { print $1, $2, $3 }')"
case "$TABLE" in *"BAD row"*) die2 "table $(printf '%s\n' "$TABLE" | grep '^BAD' | head -n 1 | sed 's/^BAD //')" ;; esac
for _s in $(printf '%s\n' "$TABLE" | awk '{ print $1 }'); do
  [ -f "$SDIR/$_s.sh" ] || die2 "table names a missing suite: $_s"
done
row_of() { printf '%s\n' "$TABLE" | awk -v s="$1" -v c="$2" '$1 == s { print $c; f = 1 } END { if (!f) print 1 }'; }

ALL=""; for _f in "$SDIR"/*_test.sh; do [ -f "$_f" ] && ALL="$ALL $(basename "$_f" .sh)"; done
PARTIAL=0; SEL="$ALL"
if [ -n "${TEST_SUITES:-}" ]; then
  PARTIAL=1; _want=""
  for _s in $TEST_SUITES; do
    _s="${_s%.sh}"; _s="${_s%_test}_test"
    [ -f "$SDIR/$_s.sh" ] || die2 "unknown suite: $_s"
    _want="$_want $_s"
  done
  SEL=""; for _s in $ALL; do in_list "$_s" "$_want" && SEL="$SEL $_s"; done
fi
ORDER=""; for _s in $(printf '%s\n' "$TABLE" | awk '{ print $1 }'); do in_list "$_s" "$SEL" && ORDER="$ORDER $_s"; done
NOROW=""; for _s in $SEL; do in_list "$_s" "$ORDER" || { ORDER="$ORDER $_s"; NOROW="$NOROW $_s"; }; done

if [ -n "${TEST_LOG_DIR:-}" ]; then
  mkdir -p "$TEST_LOG_DIR" 2>/dev/null && LOGDIR="$(cd "$TEST_LOG_DIR" && pwd -P)" \
    || die2 "cannot create TEST_LOG_DIR $TEST_LOG_DIR"
  OWN_LOG=0
else
  LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/run_all.XXXXXX" 2>/dev/null)" && LOGDIR="$(cd "$LOGDIR" && pwd -P)" \
    || die2 "cannot create a log dir"
  OWN_LOG=1
fi
: > "$LOGDIR/timing.tsv"; : > "$LOGDIR/summary.tsv"; : > "$LOGDIR/floors.tsv"
for _s in $ORDER; do printf '%s\t%s\n' "$_s" "$(row_of "$_s" 3)" >> "$LOGDIR/floors.tsv"; done
for _s in $NOROW; do echo "run_all: $_s has no table row: one job, floor 1"; done

LIVE=""; QUEUE=""; RED=0; XSECS=0; SUITE_RED=""; T_START=$(date +%s)
PERL_LAUNCH='$SIG{INT}=$SIG{QUIT}="DEFAULT"; POSIX::setsid() or die "setsid: $!\n"; exec @ARGV or die "exec: $!\n"'
alive() { kill -0 "$1" 2>/dev/null || return 1; case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*|'') return 1 ;; esac; }
count() { echo $#; }

# launch JOB SUITE PHASE SHARD PART — one parallel job: own session and group, own TMPDIR.
launch() {
  _d="$LOGDIR/$1"; mkdir -p "$_d/tmp"
  printf '%s %s\n' "$2" "$5" > "$_d/meta"; date +%s > "$_d/t0"
  env TMPDIR="$_d/tmp" TEST_TIMING_LOG="$LOGDIR/timing.tsv" TEST_PHASE="$3" TEST_SHARD="$4" TEST_SH="$TEST_SH" \
    perl -MPOSIX -e "$PERL_LAUNCH" \
    sh -c "$TEST_SH \"\$1\" > \"\$2\" 2>&1 < /dev/null; echo \$? > \"\$3.tmp\" && mv \"\$3.tmp\" \"\$3\"" \
    _ "$SDIR/$2.sh" "$_d/log" "$_d/rc" &
  printf '%s\n' "$!" > "$_d/pid"
  LIVE="$LIVE $1"
}
# finish JOB REASON [quiet] — one summary row; print the job's block unless quiet.
finish() {
  _d="$LOGDIR/$1"; _why="$2"; read -r _s _pt < "$_d/meta"
  _secs=$(( $(date +%s) - $(cat "$_d/t0") ))
  _rc="$(cat "$_d/rc" 2>/dev/null)"
  _sum="$(grep -E '^[0-9]+ assertions, [0-9]+ failed$' "$_d/log" 2>/dev/null | tail -n 1)"
  _a="${_sum%% *}"; _f="$(printf '%s\n' "$_sum" | sed -n 's/^.* assertions, \([0-9]*\) failed$/\1/p')"
  _nt="$(awk -F'\t' -v s="$_s" -v p="$_pt" '$1 == "T" && $2 == s && $3 == p { n++ } END { print n + 0 }' "$LOGDIR/timing.tsv")"
  if [ -z "$_why" ]; then
    if [ -z "$_rc" ]; then _why="no status"
    elif [ -z "$_sum" ]; then _why="no summary line"
    elif [ "$_f" != 0 ]; then _why="$_f failed"
    elif [ "$_rc" != 0 ]; then _why="exit $_rc"
    fi
  fi
  if [ -z "$_why" ]; then _v=green; else _v="red: $_why"; RED=1; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_s" "$_pt" "$_secs" "$_nt" "${_a:-0}" "${_f:-0}" "$_v" >> "$LOGDIR/summary.tsv"
  [ "${3:-}" = quiet ] || { printf '\n=== %s [%s] %s s ===\n' "$_s" "$_pt" "$_secs"; cat "$_d/log"; }
}
# stop_group PID JOB — TERM the job's group, KILL it after 5 s, then sweep what escaped it (D4).
stop_group() {
  kill -TERM "-$1" 2>/dev/null; _sg=0
  while kill -0 "-$1" 2>/dev/null && [ "$_sg" -lt 25 ]; do sleep 0.2; _sg=$((_sg + 1)); done
  kill -KILL "-$1" 2>/dev/null
  pkill -f "$LOGDIR/$2/" 2>/dev/null
}
# pool MAX — run the QUEUE words "job|suite|phase|shard|part" with at most MAX jobs live.
pool() {
  _pmax="$1"; _plast=$(date +%s)
  while [ -n "$QUEUE" ] || [ -n "$LIVE" ]; do
    _keep=""
    for _j in $LIVE; do
      _d="$LOGDIR/$_j"; _p="$(cat "$_d/pid")"
      if [ -f "$_d/rc" ]; then wait "$_p" 2>/dev/null; finish "$_j" ""
      elif ! alive "$_p"; then
        wait "$_p" 2>/dev/null
        if [ -f "$_d/rc" ]; then finish "$_j" ""; else finish "$_j" "no status"; fi
      elif [ $(( $(date +%s) - $(cat "$_d/t0") )) -ge "$TIMEOUT" ]; then
        stop_group "$_p" "$_j"; wait "$_p" 2>/dev/null; finish "$_j" "timed out after $TIMEOUT s"
      else _keep="$_keep $_j"; fi
    done
    LIVE="$_keep"
    while [ -n "$QUEUE" ] && [ "$(count $LIVE)" -lt "$_pmax" ]; do
      set -- $QUEUE; _q="$1"; shift; QUEUE="$*"
      _oifs="$IFS"; IFS='|'; set -- $_q; IFS="$_oifs"
      launch "$1" "$2" "$3" "$4" "$5"
    done
    if [ $(( $(date +%s) - _plast )) -ge 60 ]; then
      printf 'run_all: still running:%s\n' "$LIVE" >&2; _plast=$(date +%s)
    fi
    if [ -n "$QUEUE" ] || [ -n "$LIVE" ]; then sleep 0.2; fi
  done
}
parallel_mode() {
  for _s in $ORDER; do
    _n="$(row_of "$_s" 2)"
    if [ "$_n" -gt 1 ]; then
      _k=1; while [ "$_k" -le "$_n" ]; do
        QUEUE="$QUEUE $_s.p${_k}of$_n|$_s|parallel|$_k/$_n|p${_k}of$_n"; _k=$((_k + 1)); done
    else QUEUE="$QUEUE $_s.p1of1|$_s|parallel||p1of1"; fi
  done
  pool "$TEST_JOBS"
  _x0=$(date +%s)
  for _s in $ORDER; do
    if grep -q '^TESTS_EXCLUSIVE=' "$SDIR/$_s.sh"; then QUEUE="$QUEUE $_s.x|$_s|exclusive||x"; fi
  done
  pool 1
  XSECS=$(( $(date +%s) - _x0 ))
}
serial_mode() {
  for _s in $SEL; do
    _d="$LOGDIR/$_s"; mkdir -p "$_d"; date +%s > "$_d/t0"; printf '%s all\n' "$_s" > "$_d/meta"
    printf '\n=== %s ===\n' "$_s.sh"
    { TEST_TIMING_LOG="$LOGDIR/timing.tsv" "$TEST_SH" "$SDIR/$_s.sh"; echo $? > "$_d/rc"; } 2>&1 | tee "$_d/log"
    finish "$_s" "" quiet
  done
}
# checks — one line per red suite: no L row, differing listed counts, a test not run exactly
# once (finals once per partition), or assertions below the floor.
checks() {
  awk -F'\t' '
    FILENAME ~ /floors\.tsv$/ { floor[$1] = $2; next }
    FILENAME ~ /summary\.tsv$/ { ran[$1] = 1; asum[$1] += $5; next }
    $1 == "L" { if (($2 in nl) && listed[$2] != $4) diff[$2] = 1
                nl[$2]++; listed[$2] = $4; fin[$2] = $5; next }
    $1 == "T" { k = $2 SUBSEP $4; cnt[k]++; name[k] = $5; next }
    END {
      for (s in ran) {
        if (!(s in nl)) { print s ": no run_tests row"; continue }
        if (s in diff) print s ": listed counts differ across partitions"
        split("", isf)
        if (fin[s] != "-") { n = split(fin[s], fa, ","); for (i = 1; i <= n; i++) isf[fa[i]] = 1 }
        for (i = 1; i <= listed[s]; i++) {
          k = s SUBSEP i; want = (i in isf) ? nl[s] : 1; got = cnt[k] + 0
          if (got == 0) print s ": test " i " never ran"
          else if (got != want) print s ": test " i " (" name[k] ") ran " got " times"
        }
        if (asum[s] < floor[s]) print s ": " asum[s] " assertions, below its floor " floor[s]
      }
    }' "$LOGDIR/floors.tsv" "$LOGDIR/summary.tsv" "$LOGDIR/timing.tsv" | sort
}
summary() {
  printf '\n=== summary%s ===\n' "${1:+ ($1)}"
  awk -F'\t' '{ printf "%-30s %-8s %6s s %5s tests %6s assertions %4s failed  %s\n", $1, $2, $3, $4, $5, $6, $7 }' "$LOGDIR/summary.tsv"
  [ -z "$SUITE_RED" ] || printf '%s\n' "$SUITE_RED" | sed 's/^/RED /'
  awk -F'\t' -v w=$(( $(date +%s) - T_START )) -v x="$XSECS" '
    { s[$1] = 1; j++; a += $5; f += $6 }
    END { n = 0; for (k in s) n++
          printf "total: %s s wall, %d suites, %d jobs, %d assertions, %d failed, exclusive phase %s s\n", w, n, j, a, f, x }' "$LOGDIR/summary.tsv"
  printf 'slowest %s tests:\n' "$TEST_SLOWEST"
  awk -F'\t' '$1 == "T" { printf "%s\t%s\t%s\t%s\n", $6, $2, $3, $5 }' "$LOGDIR/timing.tsv" \
    | sort -t "$(printf '\t')" -k1,1nr | head -n "$TEST_SLOWEST" \
    | awk -F'\t' '{ printf "  %5s s  %s [%s] %s\n", $1, $2, $3, $4 }'
}
# on_signal N NAME — forward to every live job's group, wait 10 s, KILL, sweep the log dir.
on_signal() {
  trap '' INT TERM HUP
  for _j in $LIVE; do kill -"$2" "-$(cat "$LOGDIR/$_j/pid")" 2>/dev/null; done
  _w=0
  while [ "$_w" -lt 50 ]; do
    _any=0
    for _j in $LIVE; do kill -0 "-$(cat "$LOGDIR/$_j/pid")" 2>/dev/null && _any=1; done
    [ "$_any" = 1 ] || break
    sleep 0.2; _w=$((_w + 1))
  done
  for _j in $LIVE; do kill -KILL "-$(cat "$LOGDIR/$_j/pid")" 2>/dev/null; done
  pkill -f "$LOGDIR" 2>/dev/null
  for _j in $LIVE; do wait "$(cat "$LOGDIR/$_j/pid")" 2>/dev/null; finish "$_j" interrupted; done
  summary interrupted
  printf 'run_all: interrupted — logs kept in %s\n' "$LOGDIR" >&2
  exit $(( 128 + $1 ))
}
trap 'on_signal 2 INT' INT; trap 'on_signal 15 TERM' TERM; trap 'on_signal 1 HUP' HUP

if [ "$TEST_JOBS" = 1 ]; then serial_mode; else parallel_mode; fi
if [ -n "${TESTS_ONLY:-}" ]; then
  echo "run_all: TESTS_ONLY is set — suite checks skipped (a partial run is not a gate)"
else
  SUITE_RED="$(checks)"; [ -z "$SUITE_RED" ] || RED=1
fi
summary
[ "$PARTIAL" = 0 ] || echo "run_all: partial run (TEST_SUITES) — not the merge gate"
if [ "$RED" = 0 ]; then [ "$OWN_LOG" = 0 ] || rm -rf "$LOGDIR"; exit 0; fi
echo "run_all: logs kept in $LOGDIR"
exit 1
```

Notes for the implementer:
- In serial mode, a terminal Ctrl-C reaches the foreground suite and run_all together, as today. `on_signal` then finds `LIVE` empty and prints the interrupted summary.
- Keep the 0.2 s poll. Neither bash 3.2 nor dash has `wait -n`.
- The overnight floor 1132 was measured in T0 Step 2.
- [ ] **Step 4: Run the acceptance commands.** Both runs must be green.
- [ ] **Step 5: Commit:** `git add tests/run_all.sh tests/run_all_test.sh && git commit -m "test(run_all): parallel job pool, exclusive phase, summary and suite checks (#54)"`.

---

### Task 3: Affected-suites runner

Risk: **risky** (new seam). Review: task (Opus).

**Touches:** `tests/run_affected.sh` (new), `tests/run_affected_test.sh` (new).

**Interfaces:**
- Consumes: `tests/run_all.sh`'s `TEST_SUITES` (by contract; the tests use `--list` and never run it).
- Produces: `sh tests/run_affected.sh [--base REF] [--list]`.
  - `--list` prints `suite<TAB>reason` lines and exits 0. The base sha goes to stderr as `run_affected: base <REF> <sha>`.
  - Without `--list`, it prints the banner `run_affected: in-progress check only — the merge gate is sh tests/run_all.sh` to stderr, then `exec`s `TEST_SUITES="…" sh tests/run_all.sh`. When every suite is affected, it runs run_all without `TEST_SUITES`.

**Tests** (in `run_affected_test.sh`):
- spec R9: `test_affected_suite_change_maps_to_itself`, `test_affected_shared_files_map_to_all`, `test_affected_sourced_lib_maps_through_closure`, `test_affected_docs_map_to_readers_or_none`, `test_affected_unknown_maps_to_all`, `test_affected_deleted_and_untracked_files`, `test_affected_missing_base_exits_2`, `test_affected_no_changes`;
- Review Focus 5: `test_affected_rename_counts_both_paths`.

**Acceptance:** `sh tests/run_affected_test.sh && dash tests/run_affected_test.sh`, and in the worktree `sh tests/run_affected.sh --list` (it lists the suites this task touched).

- [ ] **Step 1: Write the failing tests.**
  - A `repo NAME` helper builds `$TMP/NAME`: a git repo on `main` with an `origin` remote (a bare repo) holding the R9 mini layout, committed and pushed. It then copies the real `run_affected.sh` to `tests/run_affected.sh` in it.
  - The mini layout:
    - `lib/common.sh`, `tests/assert.sh`, `tests/run_all.sh`;
    - `tests/a_test.sh` (mentions `bin/tool`), `tests/b_test.sh` (mentions `docs/y.md`);
    - `bin/tool` (sources `bin/lib.sh`), `bin/lib.sh`;
    - `docs/x.md`, `docs/y.md`, `unknown.txt`.
  - Each test edits files, runs `( cd "$R" && ${TEST_SH:-sh} tests/run_affected.sh --list )`, and asserts the exact sorted suite column.
  - "All suites" means every `tests/*_test.sh` in the fixture: `a_test b_test`.
  - The cases:
    - `rename`: `git mv bin/lib.sh bin/lib2.sh`, committed on a branch → `a_test` (through the old path, D12);
    - `missing base`: `--base nope` → exit 2 with the R9 message;
    - `no changes`: `no changes against origin/main` and exit 0;
    - `deleted and untracked`: deleting `bin/lib.sh` (unstaged) maps to `a_test`; a new untracked `tests/c_test.sh` maps to `c_test`.
- [ ] **Step 2: Run them to verify they fail.**
- [ ] **Step 3: Implement.**
  - Changed files: `git diff --name-only --no-renames "$(git merge-base "$REF" HEAD)"` plus `git ls-files --others --exclude-standard`, de-duplicated. If REF is missing or the merge-base fails → exit 2 with `run_affected: base <REF> not found — git fetch, or pass --base`.
  - The R9 mapping, first match wins:
    - **rule 1:** `tests/assert.sh`, `tests/run_all.sh` and `lib/*` map to all suites;
    - **rule 2:** `tests/<x>_test.sh` maps to itself; `tests/run_affected.sh` maps to `run_affected_test`; `tests/exclusive_scan.awk` maps to `harness_test`;
    - **rule 3:** `docs/**` uses D12's regex over `tests/*_test.sh`, or prints `no suite reads <path>` to stderr;
    - **rule 4:** any other file goes through the closure below;
    - none of these: all suites.
  - The closure is a fixed point over the code files:
    - the code files are `git ls-files` restricted to `tests/`, `studios/*/bin/`, `studios/*/hooks/`, `shared/*/bin/`, `shared/*/hooks/`, `lib/`, `integrations/*/bin/` and repo-root `*.sh`;
    - start from the changed file;
    - each round, any code file containing (`grep -lF`) a member's repo-relative path, or its key, joins;
    - a member's key is its basename, or its last two path components when the basename is one of `SKILL.md README.md hooks.json plugin.json config.json run.sh`;
    - the affected suites are the closure's `tests/*_test.sh` members. An empty set means unknown, which maps to all suites.
  - Reasons: `itself`, `shared: <file>`, `reads <doc>`, `via <file>`, `unknown: <file>`.
- [ ] **Step 4: Run the acceptance commands.**
- [ ] **Step 5: Commit:** `git add tests/run_affected.sh tests/run_affected_test.sh && git commit -m "test(run_affected): changed files to suites, in-progress only (#54)"`.

---

### Task 4: Setup and gate poll knobs

Risk: **risky** (cross-system production change, timing). Review: task (Opus).

**Touches:** `studios/game-dev/bin/studio-setup`, `studios/game-dev/bin/studio-gate`, `tests/studio_setup_test.sh` (new tests only), `tests/toolkit_test.sh` (new tests only).

**Interfaces:**
- Produces: `STUDIO_SETUP_POLL_SECONDS` → `SETUP_POLL`/`SETUP_TPS`; `STUDIO_GATE_POLL_SECONDS` → `GATE_POLL`/`GATE_TPS` (Shared interfaces).
- Consumes: nothing new.

**Tests:**
- `test_setup_poll_keeps_budget`, `test_setup_poll_rejects_bad_value` (studio_setup_test);
- `test_gate_poll_keeps_budget`, `test_gate_poll_rejects_bad_value` (toolkit_test).
- The carriers (`test_setup_timeout_kills_term_ignorer`, `test_setup_timer_starts_after_lock`, `test_gate_no_overlap`, `test_gate_waiting_message`) are unchanged and must stay green with the knobs unset.

**Acceptance:**
```sh
sh tests/studio_setup_test.sh
TESTS_ONLY="test_gate_poll_keeps_budget test_gate_poll_rejects_bad_value test_gate_no_overlap test_gate_waiting_message" sh tests/toolkit_test.sh
sh tests/toolkit_test.sh
git diff origin/main -- studios | grep '^[-+][^-+]'    # knob reads, validation and tick math only
```

- [ ] **Step 1: Write the four tests, failing.**
  - `test_setup_poll_keeps_budget`:
    - `proj kb '{ "worktree_setup": "sh ign.sh" }'`, with `ign.sh` = `trap '' TERM` and then `sleep 4822`;
    - set `STUDIO_SETUP_TIMEOUT_SECONDS=1 STUDIO_SETUP_POLL_SECONDS=0.2`;
    - `_t0=$(date +%s); setup "$P"; _el=$(( $(date +%s) - _t0 ))`;
    - assert exit 1 with `exit 124`, and `_el -ge 5` (tg_stop's 5 s survives the 0.2 s ticks; lower bound only).
    - (T8 later converts `sleep 4822` to msleep.)
  - `test_setup_poll_rejects_bad_value`: with `STUDIO_SETUP_POLL_SECONDS=0.3`, `setup "$P"` exits 2 with `studio-setup: STUDIO_SETUP_POLL_SECONDS must be 1, 0.5, 0.2 or 0.1, got 0.3`, and no `gate.lock` is left.
  - `test_gate_poll_keeps_budget` (D3):
    - in a studio project, hold the gate with `sh "$GATE" holder -- sleep 13 &`;
    - after the lock's `pid` file appears, run `STUDIO_GATE_POLL_SECONDS=0.2 sh "$GATE" waiter -- true 2> "$TMP/gw.err"`;
    - exactly 1 line of `gate: waiting for` (with `% 60`, unscaled, there would be 2);
    - the waiter exits 0 once the holder is done.
  - `test_gate_poll_rejects_bad_value`: `STUDIO_GATE_POLL_SECONDS=2 sh "$GATE" x -- true` → exit 2 and the message.
- [ ] **Step 2: Run them to verify they fail.** Today the knob is ignored: setup runs green with 0.3, and the gate never refuses.
- [ ] **Step 3: Implement the tick math** (the hard part). In studio-setup, after the verb `case` (D7):

```sh
# STUDIO_SETUP_POLL_SECONDS (test hook): the poll of timed_gate's lock wait, run loop and
# tg_stop; 1 (default), 0.5, 0.2 or 0.1. Budgets stay in real seconds: tg_stop waits 5 s
# = 5 x SETUP_TPS ticks; the run loop's deadline is `date`-based.
case "${STUDIO_SETUP_POLL_SECONDS:-1}" in
  1) SETUP_POLL=1; SETUP_TPS=1 ;;     0.5) SETUP_POLL=0.5; SETUP_TPS=2 ;;
  0.2) SETUP_POLL=0.2; SETUP_TPS=5 ;; 0.1) SETUP_POLL=0.1; SETUP_TPS=10 ;;
  *) printf 'studio-setup: STUDIO_SETUP_POLL_SECONDS must be 1, 0.5, 0.2 or 0.1, got %s\n' "$STUDIO_SETUP_POLL_SECONDS" >&2; exit 2 ;;
esac
```

  - `tg_stop`: `while kill -0 "$_tg" 2>/dev/null && [ "$_n" -lt $((5 * SETUP_TPS)) ]; do sleep "$SETUP_POLL"; _n=$((_n + 1)); done`.
  - In `timed_gate`, the lock-take wait and the run loop use `sleep "$SETUP_POLL"`. Both are otherwise unchanged.
  - Header: below `# Test hook: STUDIO_SETUP_TIMEOUT_SECONDS …` add `# Test hook: STUDIO_SETUP_POLL_SECONDS (1, 0.5, 0.2 or 0.1; default 1) — the poll of the lock wait, run loop and TERM grace; budgets stay in seconds.`

  In studio-gate, after `shift 2`:

```sh
case "${STUDIO_GATE_POLL_SECONDS:-1}" in
  1) GATE_POLL=1; GATE_TPS=1 ;;     0.5) GATE_POLL=0.5; GATE_TPS=2 ;;
  0.2) GATE_POLL=0.2; GATE_TPS=5 ;; 0.1) GATE_POLL=0.1; GATE_TPS=10 ;;
  *) printf 'studio-gate: STUDIO_GATE_POLL_SECONDS must be 1, 0.5, 0.2 or 0.1, got %s\n' "$STUDIO_GATE_POLL_SECONDS" >&2; exit 2 ;;
esac
```

  - The lock wait: `if [ $((waited % (60 * GATE_TPS))) -eq 0 ]; then …` and `sleep "$GATE_POLL"`.
  - The post-signal loop (KILL at 10, stop at 15) is not touched.
  - Header line: `# Test hook: STUDIO_GATE_POLL_SECONDS (1, 0.5, 0.2 or 0.1; default 1) — the lock wait's poll; the waiting message stays every 60 s.`
- [ ] **Step 4: Run the acceptance commands.**
- [ ] **Step 5: Commit:** `git add studios/game-dev/bin/studio-setup studios/game-dev/bin/studio-gate tests/studio_setup_test.sh tests/toolkit_test.sh && git commit -m "feat(studio-setup,studio-gate): test-only poll knobs, production default (#54)"`.

---

### Task 5: Reap and detach poll knobs

Risk: **risky** (cross-system production change, timing). Review: task (Opus).

**Touches:** `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-lanes.sh`, `tests/overnight_test.sh` (new tests only), `tests/overnight_lanes_test.sh` (new tests only).

**Interfaces:**
- Produces:
  - `STUDIO_OVERNIGHT_REAP_POLL_SECONDS` → `REAP_POLL`/`REAP_TPS`, used by `end_session`, `unit_reap` and `lanes_end_sessions`;
  - `STUDIO_OVERNIGHT_DETACH_POLL_SECONDS` → `DETACH_POLL`/`DETACH_TPS`, used by the `detach_start` window.

**Tests:**
- `test_overnight_reap_poll_keeps_budget`, `test_overnight_reap_poll_rejects_bad_value` (overnight_test);
- `test_lanes_detach_poll_keeps_budget`, `test_lanes_detach_poll_rejects_bad_value` (overnight_lanes_test).

**Acceptance:** each line runs the heavy suite as a `TESTS_ONLY` slice (not whole), one at a time:
```sh
TESTS_ONLY="test_overnight_reap_poll_keeps_budget test_overnight_reap_poll_rejects_bad_value test_overnight_kill_after_grace test_overnight_help" sh tests/overnight_test.sh
TESTS_ONLY="test_lanes_detach_poll_keeps_budget test_lanes_detach_poll_rejects_bad_value test_lanes_detach_timeout_lock_held_points_at_status test_lanes_detach_timeout_no_lock_ends_child test_lanes_end_sessions_spaced_path test_lanes_left_gate_reaped" sh tests/overnight_lanes_test.sh
```
Relocate the help test's exact name with `grep -n '^test_overnight_help' tests/overnight_test.sh`.

- [ ] **Step 1: Write the four tests, failing.**
  - `test_overnight_reap_poll_keeps_budget`:
    - copy `test_overnight_kill_after_grace`'s setup (`kill_grace_seconds` 5, two `ignoreterm; hang` sessions, `STUDIO_OVERNIGHT_SESSION_SECONDS=1`) and add `STUDIO_OVERNIGHT_REAP_POLL_SECONDS=0.2`;
    - time `run_start`;
    - assert 2 calls, and elapsed `≥ 10` (two graces of 5 s, still whole at 0.2 s ticks);
    - unset both knobs after.
  - `test_overnight_reap_poll_rejects_bad_value`:
    - fixture, then `STUDIO_OVERNIGHT_REAP_POLL_SECONDS=0.3 sh "$RUNNER" start` in `$P` → exit 2 and `studio-overnight: STUDIO_OVERNIGHT_REAP_POLL_SECONDS must be 1, 0.5, 0.2 or 0.1, got 0.3`;
    - `$P/.studio/overnight.lock` and `"$P"/.studio/reports/overnight-*` do not exist (the refusal comes before any run dir or lock);
    - `calls` is 0.
  - `test_lanes_detach_poll_keeps_budget` (D15):

```sh
test_lanes_detach_poll_keeps_budget() {
  lanes_fixture dpk integration A:-
  : > "$TMP/dpk.count"
  STUDIO_OVERNIGHT_DETACH_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_DETACH_STATUS_CMD="echo x >> '$TMP/dpk.count'; false"
  STUDIO_OVERNIGHT_DETACH_CHILD_CMD="sleep 309"
  export STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_STATUS_CMD STUDIO_OVERNIGHT_DETACH_CHILD_CMD
  _t0=$(date +%s); st=0
  ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/dpk.out" 2>&1 || st=$?
  _el=$(( $(date +%s) - _t0 ))
  unset STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_STATUS_CMD STUDIO_OVERNIGHT_DETACH_CHILD_CMD
  assert_eq 1 "$st" "the window times out: the child never took the lock"
  assert_contains "$TMP/dpk.out" "never took the lock" "the no-lock message"
  assert_eq 1 "$([ "$_el" -ge 10 ] && echo 1 || echo 0)" "the window still lasts 10 s at a 0.2 s poll (${_el}s)"
  assert_eq 50 "$(wc -l < "$TMP/dpk.count" | tr -d ' ')" "the status check ran 10 s x 5 ticks: the knob survived --detach's STUDIO_* strip"
}
```

  - `test_lanes_detach_poll_rejects_bad_value`: `STUDIO_OVERNIGHT_DETACH_POLL_SECONDS=1.0 sh "$RUNNER" start --detach "$MFP"` → exit 2 and the message; no `$P/.studio/runs/demo/lock`, and no `detached:` line.
- [ ] **Step 2: Run them to verify they fail.**
- [ ] **Step 3: Implement.** In studio-overnight, right after the `case "${1:-}" in --help|-h) … esac` block, before `START_DIR=` (D7):

```sh
# poll_knob NAME VALUE — sets _pk_poll/_pk_tps for a test-only poll knob (1, 0.5, 0.2 or 0.1),
# or refuses: read once, here, so a bad value never reaches a run, and --detach's STUDIO_*
# strip cannot drop the detach window's value (it reads the locals).
poll_knob() {
  case "${2:-1}" in
    1) _pk_poll=1; _pk_tps=1 ;;     0.5) _pk_poll=0.5; _pk_tps=2 ;;
    0.2) _pk_poll=0.2; _pk_tps=5 ;; 0.1) _pk_poll=0.1; _pk_tps=10 ;;
    *) say "$1 must be 1, 0.5, 0.2 or 0.1, got $2"; exit 2 ;;
  esac
}
poll_knob STUDIO_OVERNIGHT_REAP_POLL_SECONDS "${STUDIO_OVERNIGHT_REAP_POLL_SECONDS:-}"; REAP_POLL=$_pk_poll; REAP_TPS=$_pk_tps
poll_knob STUDIO_OVERNIGHT_DETACH_POLL_SECONDS "${STUDIO_OVERNIGHT_DETACH_POLL_SECONDS:-}"; DETACH_POLL=$_pk_poll; DETACH_TPS=$_pk_tps
```

  - `end_session`: `[ "$_g" -lt $(( ${GRACE:-30} * REAP_TPS )) ]` and `sleep "$REAP_POLL"`.
  - `unit_reap`: after `_ur_max` is computed, `_ur_max=$((_ur_max * REAP_TPS))`, and `sleep "$REAP_POLL"`.
  - Detach window: `while [ "$_di" -lt $((10 * DETACH_TPS)) ]; do … sleep "$DETACH_POLL"; _di=$((_di + 1)); done`. The 3-iteration kill loop after it is not touched.
  - Help, under "Test hooks":

```
  STUDIO_OVERNIGHT_REAP_POLL_SECONDS — test hook: the poll while a TERMed
                     session or gate is given its grace: 1 (default), 0.5,
                     0.2 or 0.1; the grace stays in seconds
  STUDIO_OVERNIGHT_DETACH_POLL_SECONDS — test hook: the poll of --detach's
                     10 s status window: 1 (default), 0.5, 0.2 or 0.1
```

  - In overnight-lanes.sh, `lanes_end_sessions`: `[ "$_es_g" -lt $(( ${GRACE:-30} * ${REAP_TPS:-1} )) ]` and `sleep "${REAP_POLL:-1}"`.
  - Pointer comment above it: `# Its poll is STUDIO_OVERNIGHT_REAP_POLL_SECONDS (studio-overnight's help), read at startup into REAP_POLL/REAP_TPS; sourced alone (a unit test), the 1 s default applies.`
- [ ] **Step 4: Run the acceptance commands.**
- [ ] **Step 5: Commit:** `git add studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh tests/overnight_test.sh tests/overnight_lanes_test.sh && git commit -m "feat(studio-overnight): test-only reap and detach poll knobs, production default (#54)"`.

---

## Wave 2

Every W2 task builds on W1, integrated: T1's API, and T4/T5's knobs.

### Task 6: Lanes suite hermetic

Risk: **risky** (cross-system). Review: task (Opus).

**Touches:** `tests/overnight_lanes_test.sh`.

**Interfaces:**
- Consumes: `own_group`, `mk_msleep`, `before_each`/`is_real_clock`, `TESTS_EXCLUSIVE`/`TESTS_REAL_CLOCK`/`TESTS_FINAL` (T1), and the four knobs (T4, T5).
- Produces: `RUNNER="$TMP/bin/studio-overnight"`, a symlink; `$TMP/bin/msleep`; the lanes partition lists.

**Tests:**
- new: `test_lanes_runner_argv_names_tmp`;
- changed in place: `test_lanes_round_trip_two_runs` (the I-3 peers loop), `test_lanes_no_orphans`, `test_lanes_sigint`, `test_lanes_end_sessions_spaced_path`, `test_lanes_detach_timeout_no_lock_ends_child`, `test_lanes_detach_poll_keeps_budget`, `test_lanes_setup_preflight_interrupt_cleans`, and every test with a 483x sleeper;
- if D9 needs one, `test_lanes_wait_deps_default_poll`.

**Acceptance:**
- Slice: `TESTS_ONLY="test_lanes_runner_argv_names_tmp test_lanes_round_trip_two_runs test_lanes_sigint test_lanes_end_sessions_spaced_path test_lanes_detach_timeout_no_lock_ends_child test_lanes_detach_poll_keeps_budget test_lanes_setup_preflight_interrupt_cleans test_lanes_no_orphans" sh tests/overnight_lanes_test.sh`.
- The same slice under `dash`.
- Then the whole suite once, in the background, through `sh "$SP/heavy.sh" "$SP/reports/T6-lanes.log" sh tests/overnight_lanes_test.sh`. Green, and the count must be ≥ 1128.
- Then `TEST_PHASE=exclusive sh tests/overnight_lanes_test.sh` and `TEST_PHASE=parallel TEST_SHARD=3/8 sh tests/overnight_lanes_test.sh`, through `heavy.sh`.

- [ ] **Step 1: Runner link and temp dir.**
  - Move `TMP=` above `RUNNER=`. Use `TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/overnight_lanes_test.XXXXXX")" && pwd -P)"`.
  - Then `mkdir -p "$TMP/bin" && ln -s "$BIN/studio-overnight" "$TMP/bin/studio-overnight" && mk_msleep || { echo "lanes: setup failed" >&2; exit 1; }`, and `RUNNER="$TMP/bin/studio-overnight"`.
  - `STUB_RUNNER="$RUNNER"` (`:501`) follows unchanged.
  - Grep for every other `studio-overnight` path the suite spells out: `grep -n 'BIN/studio-overnight\|bin/studio-overnight' tests/overnight_lanes_test.sh`.
    - Calls go through `$RUNNER`.
    - Assertions on printed runner paths (`:2090`, `:2266-2267`) compare against `$RUNNER`.
    - Unit tests that set `SELF_ABS="$BIN/studio-overnight"` themselves (`:3523`) stay.
- [ ] **Step 2: Stub temp files.** In the stub heredocs (`:264`, `:468`, `:476`), each `mktemp` becomes `mktemp "${TMPDIR:-/tmp}/lanes-stub.XXXXXX"`. Inside a quoted heredoc this stays literal, which is right: the stub expands it at run time.
- [ ] **Step 3: C2, C3, C5, C6** (spec R2.4):
  - C2 (`:2252`): `pkill -f "$TMP/bin/studio-overnight start"`.
  - C3: `detach_stop`'s second wait, `:2253` and `test_lanes_no_orphans` become `pgrep -f "$TMP"` alone. Drop the `pgrep -f "$RUNNER"` half; with the link it is a subset.
  - C5: the `--detach` child at `:2277` becomes `"$TMP/bin/msleep 301 & $TMP/bin/msleep 301"`. Its check at `:2284` becomes `pgrep -f "$TMP/bin/msleep 301\$"`.
  - D15: T5's `sleep 309` becomes `$TMP/bin/msleep 309`.
  - C6: every 483x setup command in a config JSON (4831, 4834, 4835) becomes `$TMP/bin/msleep 483x`. Its scans become `pgrep -f "$TMP/bin/msleep 483x\$"`, and its cleanup `pkill -f "$TMP/bin/msleep"`. Relocate with `grep -n '483[0-9]' tests/overnight_lanes_test.sh`.
  - Add the trailing `# scan-ok: filtered by $CALLS on the same line` to `:2349`.
- [ ] **Step 4: own_group.**
  - Spaced path (`:1082`): `( own_group "$TMP/bin/msleep" 301 ) & _c1=$!; ( own_group "$TMP/bin/msleep" 302 ) & _c2=$!`, then `"$TMP/bin/msleep" 303 & _w1=$!`.
  - `test_lanes_sigint` (`:1103-1106`): `( cd "$P" && own_group sh "$RUNNER" start "$MFP" ) > "$TMP/si.out" 2>&1 & RPID=$!`. Remove the `set -m`/`set +m` lines.
- [ ] **Step 5: The I-3 peers loop** (`:3941-3946`). Replace it with:

```sh
  _seen=0
  for _pn in $(story_calls S1) $(story_calls S2); do
    case "$(cat "$CALLS/$_pn.story")" in S1) _other=beta ;; *) _other=alpha ;; esac
    _ok=1
    if grep -q '^Other live runs$' "$CALLS/$_pn.peers" 2>/dev/null; then
      _seen=$((_seen + 1)); grep -q "$_other" "$CALLS/$_pn.peers" || _ok=0
    fi
    assert_eq 1 "$_ok" "call $_pn: no Other live runs block, or it names the other run ($_other)"
  done
```

  Keep the existing `at least one unit saw the Other live runs block` assertion after the loop. The loop asserts exactly 8 times, because `story_calls` gives 4 per story and both counts are already asserted above.
- [ ] **Step 6: Helper ticks** (R6). Both keep their ceilings and count ticks:
  - `wait_for`: `while ! eval "$1" && [ "$_wf_i" -lt $(( $2 * 5 )) ]; do sleep 0.2; …`;
  - `wait_pid_or_fail`: `[ "$_wp_i" -lt $(( $2 * 5 )) ]` with `sleep 0.2`, and its failure text still says `after $2 s`.
  - In the stub's `bggate` pid wait (`:290`), add a ceiling: `_bi=0; while [ ! -s "$CALLS/bggate.pid" ] && [ "$_bi" -lt 600 ]; do sleep 0.1; _bi=$((_bi + 1)); done`.
- [ ] **Step 7: Partitions.** Directly above `run_tests`:
  - `TESTS_EXCLUSIVE` = the spec's lanes seed list, all 11 tests.
  - `TESTS_FINAL="test_lanes_no_orphans"`.
  - `TESTS_REAL_CLOCK`:
    - the rule-2 tests: `test_lanes_sync_repair_stops`, `test_lanes_timed_out_outcome`, `test_lanes_slot_cap_two_across_runs`, `test_lanes_gate_never_overlaps`;
    - the carriers: `test_lanes_left_gate_reaped`, `test_lanes_land_conflict_one_repair`, `test_lanes_detach_timeout_lock_held_points_at_status`;
    - D9's wait-deps carrier.

    Leave out `test_lanes_end_sessions_spaced_path` and `test_lanes_detach_timeout_no_lock_ends_child`: they are already exclusive.
  - Add the R7 `before_each` (spec R7, "How suites apply them") verbatim.
  - For D9: `grep -n 'STUDIO_OVERNIGHT_POLL_SECONDS' tests/overnight_lanes_test.sh` lists the tests that set the knob. Pick the cheapest test with a `B:A`-style dependency that does not set it, e.g. `test_lanes_dep_waits_for_landing` if it exists; relocate with `grep -n '^test_.*dep' …`. If none exists, add `test_lanes_wait_deps_default_poll`: `lanes_fixture wdd integration A:- B:A`, `run_lanes start "$MFP"`, assert both stories `landed` and B's first `t0` ≥ A's landing time.
- [ ] **Step 8: `test_lanes_runner_argv_names_tmp`.**

```sh
test_lanes_runner_argv_names_tmp() {
  lanes_fixture argv integration A:-
  printf 'hang\n' > "$SCEN/A"
  lanes_bg
  wait_for "[ -f '$CALLS/1.t0' ]" 30
  _lane="$(cat "$(last_lanes_dir)/claims/1/pid" 2>/dev/null)"
  ps -o args= -p "$RPID" > "$TMP/argv.runner" 2>/dev/null; ps -o args= -p "${_lane:-0}" > "$TMP/argv.lane" 2>/dev/null
  assert_contains "$TMP/argv.runner" "$TMP/bin/studio-overnight start" "the runner's argv carries \$TMP"
  assert_contains "$TMP/argv.lane" "$TMP/bin/studio-overnight start" "a lane's argv carries \$TMP"
  kill -TERM "$RPID"; wait_pid_or_fail "$RPID" 60 "the attached run ends on TERM"
  lanes_fixture argv2 integration A:-
  printf 'hang\n' > "$SCEN/A"
  ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/argv.det" 2>&1
  _dp="$(sed -n 's/^detached: pid \([0-9]*\),.*/\1/p' "$TMP/argv.det")"
  ps -o args= -p "${_dp:-0}" > "$TMP/argv.child" 2>/dev/null
  assert_contains "$TMP/argv.child" "$TMP/bin/studio-overnight start" "the --detach child's argv carries \$TMP"
  [ -z "$_dp" ] || kill -TERM "$_dp" 2>/dev/null
  wait_for "[ ! -f '$P/.studio/runs/demo/lock' ]" 60
  wait_for "[ -z \"\$(pgrep -f '$TMP/bin/studio-overnight')\" ]" 20
}
```

  `lanes_bg` (`:2553`) starts a plain background runner, so TERM, not INT, ends it.
- [ ] **Step 9: Run the acceptance commands.** The whole-suite run's last line must be ≥ 1128 assertions, 0 failed.
- [ ] **Step 10: Commit:** `git add tests/overnight_lanes_test.sh && git commit -m "test(lanes): runner link, scoped scans, own_group, fixed peers count, partitions (#54)"`.

---

### Task 7: Overnight suite hermetic

Risk: **risky** (cross-system). Review: task (Opus).

**Touches:** `tests/overnight_test.sh`.

**Interfaces:**
- Consumes: T1's API and T5's reap knob.
- Produces: `RUNNER="$TMP/bin/studio-overnight"`, the overnight partition lists and `test_overnight_hold_default_poll`.

**Tests:**
- new: `test_overnight_hold_default_poll`;
- changed in place: every `start_bg` user (`own_group`), every `bg_end` user (ticks).

**Acceptance:**
- Slice: `TESTS_ONLY="test_overnight_sigint test_overnight_sigterm test_overnight_sighup test_overnight_hold_default_poll test_overnight_stop_file test_overnight_kill_after_grace" sh tests/overnight_test.sh`, then under `dash`.
- The whole suite once through `heavy.sh`. It must be green, with the count ≥ the T0 floor.
- Then `TEST_PHASE=exclusive` once through `heavy.sh`.

- [ ] **Step 1: Runner link and temp dir.** Same as T6 Step 1: `TMP` above `RUNNER` (`:10-12`), with `mktemp -d "${TMPDIR:-/tmp}/overnight_test.XXXXXX"`, the `$TMP/bin/studio-overnight` link and `mk_msleep`. Check every printed-runner-path assertion with `grep -n 'studios/game-dev/bin/studio-overnight\|RUNNER' tests/overnight_test.sh`.
- [ ] **Step 2: `start_bg` with `own_group`:**

```sh
start_bg() {
  ( cd "$P" && own_group sh "$RUNNER" start "$@" ) > "$TMP/bg.out" 2> "$TMP/bg.err" &
  RPID=$!
}
```

  Its comment says why: the runner must not start with SIGINT ignored, and `set -m` does not work under dash with no tty.
- [ ] **Step 3: `bg_end` ticks.** `while bg_alive && [ "$_be_i" -lt $(( $1 * 5 )) ]; do sleep 0.2; …`. The failure text still says `after $1 s`.
- [ ] **Step 4: Scans.** `:738` (`pgrep -g`) and `:849-858` (`pgrep -P`) are pid forms and stay. Add `# scan-ok: a tool name in a PATH list` at the end of `:773`.
- [ ] **Step 5: Partitions.**
  - `TESTS_EXCLUSIVE` = the spec's 10 overnight seeds.
  - `TESTS_REAL_CLOCK="test_overnight_kill_after_grace test_overnight_sighup test_inbox_lock_released_on_signal test_overnight_hold_default_poll"`.
  - No finals: overnight has no sweep test.
  - The R7 `before_each` verbatim.
- [ ] **Step 6: `test_overnight_hold_default_poll`** (D9). This is the `studio-overnight:851` hold wait at the production 5 s poll.
  - `holds_on 3`, then `unset STUDIO_OVERNIGHT_POLL_SECONDS`.
  - A fixture whose scenario holds, modelled on the cheapest existing single-plan hold test: `grep -n 'holds_on' tests/overnight_test.sh`, and use the shortest.
  - Time it: the run ends, and elapsed is ≥ 5 (one full 5 s poll; lower bound).
  - `holds_off` after.
- [ ] **Step 7: Run the acceptance commands.**
- [ ] **Step 8: Commit:** `git add tests/overnight_test.sh && git commit -m "test(overnight): runner link, own_group start_bg, bg_end ticks, partitions (#54)"`.

---

### Task 8: studio_setup suite — hermetic, waits, tags

Risk: **risky** (timing). Review: task (Opus).

**Touches:** `tests/studio_setup_test.sh`.

**Interfaces:**
- Consumes: T1's API and the setup knob (T4).
- Produces: its partition lists and ruling lines.

**Tests:** changed in place: `test_setup_timeout_ends_group`, `test_setup_signal_stops_child_and_releases_lock`, `test_setup_timeout_kills_term_ignorer`, `test_setup_timer_starts_after_lock`, and T4's `test_setup_poll_keeps_budget` (its `sleep 4822` becomes msleep).

**Acceptance:** `sh tests/studio_setup_test.sh`, `dash tests/studio_setup_test.sh`, `TEST_PHASE=parallel sh tests/studio_setup_test.sh`, `TEST_PHASE=exclusive sh tests/studio_setup_test.sh`, and `awk -f tests/exclusive_scan.awk tests/studio_setup_test.sh`. Every flagged test has a ruling line.

- [ ] **Step 1: Temp dir.** `:10`: `mktemp -d "${TMPDIR:-/tmp}/studio_setup_test.XXXXXX"`. Then `mk_msleep || exit 1`.
- [ ] **Step 2: C4.**
  - Every config's `sleep 48xx` (4801, 4802, 4811, 4821, 4822) becomes `$TMP/bin/msleep 48xx`. The JSON holds the expanded absolute path, which has no backslash.
  - Each `ps -A -o args= | grep -c '^sleep 48xx$'` becomes `pgrep -f "$TMP/bin/msleep 48xx\$" | wc -l | tr -d ' '`.
  - Relocate with `grep -n '48[0-9][0-9]' tests/studio_setup_test.sh`.
- [ ] **Step 3: Class-A waits** (audit rows; at 6f2445b):
  - `:70`: `sleep 1`, then "no sleep 480[12]" → poll for absence, ceiling exactly 1 s (10 × 0.1).
  - `:109`: `sleep 1` before the TERM → poll until `pgrep -f "$TMP/bin/msleep 4811\$"` finds it, ceiling 60 s (600 × 0.1).
  - `:112`: `sleep 1`, then "no sleep 4811" → poll for absence, ceiling 1 s.
  - `:78`: the uncapped `gate.lock/pid` loop gets a 20 s ceiling (100 × 0.2).
- [ ] **Step 4: Partitions and rulings.**
  - `TESTS_EXCLUSIVE` = the 4 seeds. `TESTS_REAL_CLOCK=""`: both setup carriers are already exclusive.
  - The R7 `before_each`.
  - Above `TESTS_EXCLUSIVE=`, one `# exclusive-scan:` line per scanned test (4), with criterion (a), (b) or (d) and a reason.
- [ ] **Step 5: Run the acceptance commands.**
- [ ] **Step 6: Commit:** `git add tests/studio_setup_test.sh && git commit -m "test(studio_setup): marked sleepers, event waits, partitions and rulings (#54)"`.

---

### Task 9: `mktemp` templates, mechanical suites

Risk: **mech** (folds into the final review).

**Touches:** `tests/install_test.sh`, `tests/omega_test.sh`, `tests/overnight_sessions_test.sh`, `tests/sdd_script_test.sh`, `tests/state_test.sh`, `tests/studio_adopt_test.sh`, `tests/studio_brief_test.sh`, `tests/studio_env_test.sh`, `tests/studio_event_test.sh`, `tests/studio_peers_test.sh`, `tests/studio_test.sh`, `tests/sync_test.sh`, `tests/state_fixtures.sh`.

**Interfaces:** none.

**Tests:** the existing suites, unchanged in count.

**Acceptance:**
- `for s in install omega overnight_sessions sdd_script state studio_adopt studio_brief studio_env studio_event studio_peers studio sync state_guard; do sh tests/${s}_test.sh | tail -n 1; done`. Each count equals its T0 floor with 0 failed; state_guard is included because it sources `state_fixtures.sh`.
- `grep -n 'mktemp' <the touched files> | grep -v 'TMPDIR:-/tmp'` is empty.

- [ ] **Step 1:** In each file, `mktemp -d` → `mktemp -d "${TMPDIR:-/tmp}/<suite>.XXXXXX"`, where `<suite>` is the file's basename without `.sh`. For `state_fixtures.sh` use `state_fixtures`. A file `mktemp` becomes `mktemp "${TMPDIR:-/tmp}/<suite>.XXXXXX"`.
- [ ] **Step 2:** Run the acceptance commands.
- [ ] **Step 3: Commit:** `git add <the 13 files> && git commit -m "test: temp dirs honour TMPDIR in every suite (#54)"`.

---

### Task 10: Small timing suites — tags, rulings, hook wait, own_group

Risk: **risky** (timing). Review: task (Opus).

**Touches:** `tests/toolkit_test.sh`, `tests/hook_test.sh`, `tests/state_pointer_test.sh`, `tests/state_move_test.sh`, `tests/overnight_runs_test.sh`, `tests/overnight_progress_test.sh`.

**Interfaces:** consumes T1's API.

**Tests:** changed in place: `test_inbox_hook_silent_outside_units` (hook) and `test_state_mutex_single_acquisition` (state_move).

**Acceptance:**
- For each of the six suites: `sh`, `dash`, `TEST_PHASE=parallel` and `TEST_PHASE=exclusive`. Green, with counts ≥ their floors (the phases' counts summed).
- `awk -f tests/exclusive_scan.awk` over the six: every flagged test has a ruling line.

- [ ] **Step 1: Temp dirs.** `mktemp -d "${TMPDIR:-/tmp}/<suite>.XXXXXX"` in toolkit, overnight_runs and overnight_progress.
- [ ] **Step 2: state_move `:511`.** Replace it with `( cd "$P" && STUDIO_STATE_TEST_SEAM=pause3 own_group sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1 & _hp=$!`. This fixes the dash failure (spec Evidence: dash on origin/main). Check with `dash tests/state_move_test.sh` (244 or more, 0 failed).
- [ ] **Step 3: hook class-A** (`:433`). The `sleep 3` writer holding a fifo: after the hook has returned and `t1` is taken, `kill "$_w"` the writer before `wait "$_w"`. The "returns at once" assertion is unchanged.
- [ ] **Step 4: Partitions and rulings.**
  - `TESTS_EXCLUSIVE` per the spec's seed list:
    - toolkit: 5;
    - hook: 1;
    - state_pointer: 5;
    - state_move: 2;
    - overnight_runs: 1;
    - overnight_progress: 1.
  - `TESTS_REAL_CLOCK`:
    - toolkit: `test_gate_no_overlap test_gate_waiting_message test_gate_signal_waits_for_child_then_releases test_gate_signal_reaches_the_grandchild`;
    - overnight_runs: `test_mutex_reap_race`.
  - Ruling lines for every scan flag: toolkit 11, state_pointer 3, state_move 1, overnight_runs 1 and overnight_progress 1. Also one line for each seed with no flag (criterion c), e.g. hook's.
  - No `before_each` here. These suites set no runner knobs; toolkit's gate tests are real-clock carriers.
- [ ] **Step 5:** Run the acceptance commands.
- [ ] **Step 6: Commit:** `git add <the 6 files> && git commit -m "test: exclusive/real-clock tags and rulings; own_group in state_move; hook writer wait (#54)"`.

---

## Wave 3

### Task 11: Lanes event waits (R6)

Risk: **risky** (timing). Review: task (Opus).

**Touches:** `tests/overnight_lanes_test.sh`.

**Interfaces:**
- Consumes: `next_second` (T1); `$SCEN`, `$CALLS`, `STUDIO_RUN_DIR` (exported to every unit by `start_session`).
- Produces: the stub actions `waitexist` and `@RUN@`, and `$CALLS/wait.timeout` (Shared interfaces).

**Tests:**
- new: `test_stub_waitexist_and_run_token`;
- changed in place: every class-A row below. Each keeps its assertions and adds `assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"`.

**Acceptance:**
- Slice: `TESTS_ONLY="test_stub_waitexist_and_run_token <every converted test>"` under `sh`, then under `dash`.
- The whole suite once through `heavy.sh`. Record its seconds next to T6's run.
- `TEST_PHASE=exclusive` once through `heavy.sh`.

- [ ] **Step 1: Stub support.**
  - In the stub's action `case`, add next to `waitfor`:

```sh
    "waitexist "*)    _wf="$(printf '%s' "${act#waitexist }" | sed "s#@RUN@#${STUDIO_RUN_DIR:-@RUN@}#g")"; _wi=0
                      while [ ! -e "$_wf" ] && [ "$_wi" -lt 600 ]; do sleep 0.1; _wi=$((_wi + 1)); done
                      [ -e "$_wf" ] || echo "$_wf" >> "$CALLS/wait.timeout" ;;
```

  - `waitfor` and `waitafter` get the same `@RUN@` expansion and the same timeout record (`[ -s "$_wf" ] || echo … >> "$CALLS/wait.timeout"`).
  - `test_stub_waitexist_and_run_token` drives the stub directly, with `CALLS`, `STUDIO_RUN_DIR` and a scenario line set:
    - `waitexist @RUN@/x` against an existing **empty** file returns at once;
    - a 1 s ceiling (a test-only `STUB_WAIT_TICKS=10` the stub reads as `${STUB_WAIT_TICKS:-600}`) on a missing path appends that path, expanded, to `wait.timeout`.
- [ ] **Step 2: The class-A conversions.**
  - Releases are `waitexist $SCEN/release-<tag>`, with the test's `: > "$SCEN/release-<tag>"` after its live-state asserts (D10). Control files use `@RUN@/control/<ID>.<verb>`.
  - The ceiling rule: an absence check that followed the old sleep polls with a ceiling of exactly the old N; every other wait has a 60 s ceiling.
  - Rows at 6f2445b (relocate each one):

| line | test | old sleep | becomes |
|---|---|---|---|
| 939 | budget_sums_all_lanes | A `sleep 6`, B `sleep 3` | B: waitfor A's T1 row in `@RUN@/units.tsv`; A: wait until `@RUN@/stories/B` reads `stopped` |
| 966, 967 | docs_revision | A `sleep 3`; bg `sleep 1` | A: waitexist the marker the bg commit writes after `git commit`; bg: wait for `$P/.studio/runs/demo/lock` |
| 1087, 1092 | end_sessions_spaced_path | `sleep 1` ×2 | poll until `pid_live` is false, ceiling 1 s each (absence) |
| 1124 | runner_gone | A `sleep 3` | release after `kill -9 $RPID` |
| 1139 | stop_file | A `sleep 2` | waitexist `$P/.studio/runs/demo/stop` |
| 1204, 1221, 1231, 1236, 1677, 2658, 2664 | land-conflict family | B finish `sleep 4` | waitfor `$P/.studio/runs/demo/landed.tsv` |
| 1371 | land_lock_reclaim | B `sleep 4` | wait until A's lane pid is dead and `land.lock` is left |
| 1527 | gate_repair_halt (×2) | `sleep 3` in A.gate | waitexist `runs/demo/stop` |
| 1819 | final_skipped_on_stop (finstop2) | B `sleep 8` | waitexist `runs/demo/stop` |
| 2049, 2051 | status_per_story | A `sleep 4`; `sleep 1` | release after `status`; wait until C's chain is claimed and A's `unit.now` exists |
| 2147, 2173 | status_reaps_dead_runner ×2 | A `sleep 3` | release after `kill -9` |
| 2283 | detach_timeout_no_lock_ends_child | `sleep 1` before the scan | poll until `pgrep -f "$TMP/bin/msleep 301\$"` is empty, ceiling 1 s (absence) |
| 2297 | origin_detach | `sleep 8` | waitexist `runs/demo/stop` |
| 2402, 2404, 2418 | status_anywhere | A `sleep 8`; `sleep 1`; B `sleep 6` | releases after the "live elsewhere" asserts; wait until the activity is in the unit's stream log |
| 2673 | stop_queued_story | A `sleep 4` | waitexist `@RUN@/control/B.stop` |
| 2686 | stop_running_story | A `sleep 4` | waitexist `@RUN@/control/A.stop` |
| 2697 | stop_waiting_story | A, B `sleep 8` | wait until `@RUN@/stories/C` = `stopped by operator` (keep the "before A lands" assert) |
| 2712 | hold_waiting_story… | A `sleep 4` | waitexist `@RUN@/control/C.hold` |
| 2727 | hold_running_then_resume | A `sleep 4` | waitexist `@RUN@/control/A.hold` |
| 2779 | stop_at_done_never_lands | finish `sleep 5` | waitexist `@RUN@/control/A.stop` |
| 2791 | stop_held_by_operator | `sleep 4` | waitexist `@RUN@/control/A.hold` |
| 2804 | stop_pending_never_holds | unit 2 `sleep 4` | waitexist `@RUN@/control/A.stop` |
| 2843 | hold_during_last_unit… | finish `sleep 5` | waitexist `@RUN@/control/A.hold` |
| 3125 | setup_preflight_interrupt_cleans | `sleep 1` | poll until no `$TMP/bin/msleep 4831`, ceiling 1 s (absence) |
| 3296 | per_run_lock_paths | A `sleep 3` | waitexist `runs/demo/stop` |
| 3320 | two_runs_each_own_lock | `sleep 3` ×2 | release after the status asserts |
| 3436 | reap_resume_line_run_worktree | `sleep 1` after the pkill | poll until `pgrep -f "$TMP/fakebin/claude"` is empty, ceiling 1 s (absence) |
| 3689 | slot_cap_one_alternates | A `sleep 6` | wait until alpha's lane is queued (a `sessions/wait/*` entry); the 1 s units stay (B) |
| 3726 | slot_stop_ends_wait | A `sleep 4` | waitexist `runs/demo/stop` |
| 3784, 3790 | slot_released_every_exit | `sleep 3` ×2 | waitexist `runs/demo/stop` |
| 3807 | slot_wait_not_in_session_minutes | A `sleep 3` | wait for B's `lanes/<k>/slotwait` |
| 3843 | session_wait_event_and_status | A `sleep 4` | release after `status` |
| 3953 | round_trip_stop_one_of_two | S1 `sleep 8`, S2 `sleep 40` | S1: waitexist `$P/.studio/runs/alpha/stop`; S2: waitexist `…/runs/beta/stop` |

- [ ] **Step 3: `next_second`.** The six resume `sleep 1`s (`:1357`, `:1407`, `:1733`, `:1803`, `:2006`, `:2180`) become `next_second`.
- [ ] **Step 4:** Run the acceptance commands. Every converted test passes, and no `wait.timeout` exists.
- [ ] **Step 5: Commit:** `git add tests/overnight_lanes_test.sh && git commit -m "test(lanes): event waits for dead sleeps, stub waitexist/@RUN@, next_second (#54)"`.

---

### Task 12: Overnight waits, templates, rulings

Risk: **risky** (timing, data). Review: task (Opus).

**Touches:** `tests/overnight_test.sh`.

**Interfaces:**
- Consumes: `next_second` (T1); `OVERNIGHT_FIXTURE_TEMPLATES`.
- Produces: the overnight stub's `waitexist`/`@RUN@`/`wait.timeout`, the template `fixture` and the overnight ruling lines.

**Tests:**
- new: `test_overnight_fixture_copy_equals_build`, `test_overnight_fixture_failed_build_not_reused` (D11);
- changed in place: the 5 class-A rows.

**Acceptance:**
- Slice: `TESTS_ONLY="test_overnight_fixture_copy_equals_build test_overnight_fixture_failed_build_not_reused test_overnight_stop_file test_overnight_status test_status_reads_persisted_spec test_single_plan_ignores_new_story_in_start"` under `sh`, then under `dash`.
- The whole suite once through `heavy.sh`, and once more through `heavy.sh` with `OVERNIGHT_FIXTURE_TEMPLATES=0`. Both are green with equal counts.
- `TEST_PHASE=exclusive` once through `heavy.sh`.

- [ ] **Step 1: Stub support.** Add a `"waitexist "*)` action to the overnight stub's `case` (`:46`), with `@RUN@` expansion and the `wait.timeout` record, as in T11 Step 1. Releases are `$CALLS/release-<tag>` (D10).
- [ ] **Step 2: Class-A conversions** (at 6f2445b):
  - `:703` stop_file: scen `sleep 2` → `waitexist $P/.studio/overnight.stop`.
  - `:870` status: scen 2 `sleep 3` → `waitexist $P/.studio/overnight.stop`.
  - `:2165` and `:2170` srp/srp2: scen `sleep 3` → `waitexist $CALLS/release-srp`, touched after `verb status`. The 0.2 s loop at `:2172` stays (class C, 10 s ceiling).
  - `:2179` single_plan_ignores_new_story_in_start: → a release touched after the test has written the new story and its Stop.

  Each test adds `assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"`.
- [ ] **Step 3: The template fixture** (the hard part). Replace `fixture` (`:106-123`) with:

```sh
# OVERNIGHT_FIXTURE_TEMPLATES (suite-local): 1 (default) builds each config's project once
# under $TMP/tpl/o-<key>/ and copies it per call; 0 builds fresh every call, as before.
OVERNIGHT_FIXTURE_TEMPLATES="${OVERNIGHT_FIXTURE_TEMPLATES:-1}"
# fixture_build DIR ORIGIN [CONFIG_JSON] — the fixture project at DIR, its bare origin at
# ORIGIN; status non-zero on any failed step.
fixture_build() {
  rm -rf "$1" "$2"; mkdir -p "$1/docs" && git init -q --bare "$2" || return 1
  ( set -e; cd "$1"
    git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git remote add origin "$2" && git push -q origin main && git remote set-head origin main
    sh "$STATE_BIN" init >/dev/null
    [ -z "${3:-}" ] || printf '%s\n' "$3" > .studio/config.json
    printf '# Spec\n' > docs/spec.md
    printf '# Plan\n\n## Decisions\n\n- none\n' > docs/plan.md
    sh "$STATE_BIN" set spec docs/spec.md; sh "$STATE_BIN" set plan docs/plan.md
    sh "$STATE_BIN" set stage plan
    sh "$STATE_BIN" ledger "spec approved docs/spec.md"
    sh "$STATE_BIN" ledger "plan approved docs/plan.md"
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m fixture ) >/dev/null 2>&1
}
# fixture NAME [CONFIG_JSON] — a committed project at stage plan with an approved spec and
# plan (with ## Decisions); fresh $CALLS and scenario. A reused NAME is always a fresh project.
fixture() {
  P="$TMP/$1"; CALLS="$TMP/calls-$1"; TMP_WT="$TMP/wts-$1"
  OVERNIGHT_SCENARIO="$TMP/scenario-$1"
  export CALLS TMP_WT OVERNIGHT_SCENARIO
  rm -rf "$P" "$TMP/$1.git" "$CALLS" "$TMP_WT"
  mkdir -p "$CALLS" "$TMP_WT"; : > "$OVERNIGHT_SCENARIO"
  if [ "$OVERNIGHT_FIXTURE_TEMPLATES" = 0 ]; then
    fixture_build "$P" "$TMP/$1.git" "${2:-}" || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "fixture $1: setup failed"; }
    return 0
  fi
  _fx_t="$TMP/tpl/o-$(printf '%s' "${2:-}" | cksum | tr ' ' -)"
  if [ ! -f "$_fx_t/ok" ]; then
    if fixture_build "$_fx_t/p" "$_fx_t/p.git" "${2:-}"; then : > "$_fx_t/ok"; else rm -rf "$_fx_t"; fi
  fi
  if [ -f "$_fx_t/ok" ] && cp -Rp "$_fx_t/p" "$P" && cp -Rp "$_fx_t/p.git" "$TMP/$1.git" \
       && git -C "$P" remote set-url origin "$TMP/$1.git"; then
    return 0
  fi
  TESTS_RUN=$((TESTS_RUN + 1)); _fail "fixture $1: setup failed"
}
```

  Before relying on it, run with `OVERNIGHT_FIXTURE_TEMPLATES=0` and confirm no test reports `setup failed`. `set -e` must not trip on a step that used to fail quietly; if one does, find out why before going on.
- [ ] **Step 4: Equivalence tests.**
  - `test_overnight_fixture_copy_equals_build`, for each config in `''` and `'{"overnight": {"kill_grace_seconds": 5}}'`:
    - `fixture eqA "$cfg"` (a copy), then `OVERNIGHT_FIXTURE_TEMPLATES=0 fixture eqB "$cfg"` (a fresh build);
    - `diff -r -x .git` of the two trees is empty, after `sed` turns each tree's own name into `@N@` in any file that holds it;
    - `git -C X log --all --format='%T %s'` is equal for both;
    - `git status --porcelain` is empty in both;
    - `git -C eqA remote get-url origin` is `$TMP/eqA.git`;
    - `grep -rF "$TMP/tpl" "$TMP/eqA"` finds nothing;
    - the same-name double call: `fixture X '{"a":1}'`, then `fixture X '{"b":2}'` → `X/.studio/config.json` is `{"b":2}`, and `X/X` does not exist.
  - `test_overnight_fixture_failed_build_not_reused`:
    - put a fake `git` on PATH that fails the first `push` (a counter file) and passes through otherwise;
    - `fixture fb1 '{"t":1}'` reports `fixture fb1: setup failed` and leaves no `ok`. Count the expected failure with `TESTS_FAILED=$((TESTS_FAILED - 1))` after asserting it;
    - a second `fixture fb2 '{"t":1}'` builds afresh and succeeds.
- [ ] **Step 5: Shared-sha check** (spec R8). Run `grep -n '\-nt \|-newer\|rev-parse.*\$P.*rev-parse\|%ct\|%cd\|--since' tests/overnight_test.sh`. Any test that compares shas, commit times or mtimes across two fixtures, or between a fixture and the run's start, either builds fresh (`OVERNIGHT_FIXTURE_TEMPLATES=0` around its own fixture call) or is shown not to depend on it. Record the result in `$SP/reports/T12.md`.
- [ ] **Step 6: Rulings.**
  - Run `awk -f tests/exclusive_scan.awk tests/overnight_test.sh` (17 rows at 6f2445b).
  - Add one `# exclusive-scan:` line per flagged test above `TESTS_EXCLUSIVE=`, judged on the code after Step 2.
  - Rule the static candidates `test_overnight_status` and `test_overnight_stop_file`; they are expected `out`, because their window is now an event.
  - Adjust `TESTS_EXCLUSIVE` to match the `in` rulings.
- [ ] **Step 7:** Run the acceptance commands.
- [ ] **Step 8: Commit:** `git add tests/overnight_test.sh && git commit -m "test(overnight): event waits, template fixture, exclusive rulings (#54)"`.

---

## Wave 4

### Task 13: Lanes templates and rulings

Risk: **risky** (data). Review: task (Opus).

**Touches:** `tests/overnight_lanes_test.sh`.

**Interfaces:**
- Consumes: `LANES_*` fixture variables and `$FAKE`.
- Produces: the template `lanes_fixture`, `LANES_FIXTURE_TEMPLATES` and the lanes ruling lines.

**Tests:** new: `test_lanes_fixture_copy_equals_build`, `test_fixture_template_failed_build_not_reused`.

**Acceptance:**
- Slice: `TESTS_ONLY="test_lanes_fixture_copy_equals_build test_fixture_template_failed_build_not_reused"` under `sh`, then under `dash`.
- The whole suite twice through `heavy.sh`: once at the default, once with `LANES_FIXTURE_TEMPLATES=0`. Both green with equal counts; record both times.
- `TEST_PHASE=exclusive` once through `heavy.sh`.

- [ ] **Step 1: The template fixture** (the hard part).
  - Keep the comment block above `lanes_fixture` (`:510-527`), and add: `LANES_FIXTURE_TEMPLATES (suite-local): 1 (default) builds each key once under $TMP/tpl/l-<key>/ and copies it; 0 builds fresh every call.`
  - Move today's body, from `git init -q --bare` through the end of the `( set -e … )` subshell, into `lf_build`. It builds at `$1`, with its bare origin at `$2` and MODE `$3`; its rows are the rest.
  - Inside the moved body, `cd "$P"` becomes `cd "$1"` and `"$TMP/$_lf_name.git"` becomes `"$2"`. Everything else stays word for word.

```sh
LANES_FIXTURE_TEMPLATES="${LANES_FIXTURE_TEMPLATES:-1}"
lf_failed() { TESTS_RUN=$((TESTS_RUN + 1)); _fail "lanes_fixture $_lf_name: setup failed"; }
lanes_fixture() {
  _lf_name="$1"; _lf_mode="$2"; shift 2
  P="$TMP/$_lf_name"; CALLS="$TMP/calls-$_lf_name"; GH="$TMP/gh-$_lf_name"; TMP_WT="$TMP/wts-$_lf_name"
  SCEN="$TMP/scen-$_lf_name"
  MFP=docs/runs/demo.md
  export P MFP CALLS GH TMP_WT SCEN
  rm -rf "$P" "$CALLS" "$GH" "$TMP_WT" "$SCEN" "$TMP/$_lf_name.git"
  mkdir -p "$CALLS" "$GH" "$TMP_WT" "$SCEN"
  if [ "$LANES_FIXTURE_TEMPLATES" = 0 ]; then
    lf_build "$P" "$TMP/$_lf_name.git" "$_lf_mode" "$@" || lf_failed
  else
    _lf_t="$TMP/tpl/l-$(printf '%s|' "$_lf_mode" "$@" "${LANES_CONFIG:-}" "${LANES_CELLS:-}" "${LANES_PROGRESS:-}" \
      "${LANES_MAIN_MOVES:-}" "${LANES_TASKS:-}" "$FAKE" | cksum | tr ' ' -)"
    if [ ! -f "$_lf_t/ok" ]; then
      if lf_build "$_lf_t/p" "$_lf_t/p.git" "$_lf_mode" "$@"; then : > "$_lf_t/ok"; else rm -rf "$_lf_t"; fi
    fi
    if [ -f "$_lf_t/ok" ] && cp -Rp "$_lf_t/p" "$P" && cp -Rp "$_lf_t/p.git" "$TMP/$_lf_name.git" \
         && git -C "$P" remote set-url origin "$TMP/$_lf_name.git"; then :; else lf_failed; fi
  fi
  unset LANES_CONFIG LANES_CELLS LANES_PROGRESS LANES_MAIN_MOVES LANES_TASKS
}
# lf_build DIR ORIGIN MODE ROW… — the fixture body as before, at DIR with its bare origin at ORIGIN.
lf_build() {
  _lb_dir="$1"; _lb_origin="$2"; _lf_mode="$3"; shift 3
  rm -rf "$_lb_dir" "$_lb_origin"; mkdir -p "$_lb_dir" && git init -q --bare "$_lb_origin" || return 1
  _lf_cfg="${LANES_CONFIG:-}"; [ -n "$_lf_cfg" ] || _lf_cfg='{}'
  # … the rest of today's body, verbatim, with cd "$_lb_dir" and "$_lb_origin" …
  ( set -e
    cd "$_lb_dir"
    # (today's lines :548-597)
  ) >/dev/null 2>&1
}
```

  `rm -rf` comes before `cp -Rp` (falsifier I-6: `cp -Rp` onto an existing directory nests the copy inside it). The final `unset` of the `LANES_*` variables is unchanged.
- [ ] **Step 2: Equivalence tests.**
  - `test_lanes_fixture_copy_equals_build` covers three shapes: `integration A:-`; `integration A:- B:A`; and `direct A:-` with `LANES_TASKS=2` and `LANES_CONFIG='{"overnight": {"max_lanes": 2}}'`. Set the `LANES_*` variables before each of the two calls, since `lanes_fixture` unsets them. Each shape gets the checks from T12 Step 4:
    - `diff -r -x .git` after the name-to-placeholder rewrite (it includes git-ignored files such as `.studio/STATE.md`);
    - `git log --all --format='%T %s'`;
    - an empty `git status --porcelain`;
    - `git rev-parse origin/run/demo` = `HEAD`;
    - the remote URL;
    - no `$TMP/tpl` in the copy.
  - `test_fixture_template_failed_build_not_reused`: as T12's failed-build test, with `lanes_fixture`.
- [ ] **Step 3: Shared-sha check.** The same grep as T12 Step 5, over the lanes suite. Record the result.
- [ ] **Step 4: Rulings.**
  - Run `awk -f tests/exclusive_scan.awk tests/overnight_lanes_test.sh` (47 rows at 6f2445b; more if T5, T6 and T11 added flagged tests). Every row gets a ruling line, judged on the code after T11.
  - The static candidates must each get a line: `test_lanes_stop_file`, `test_lanes_runner_gone`, `test_lanes_per_run_lock_paths`, `test_lanes_two_runs_each_own_lock`, `test_lanes_gate_repair_halt`, `test_lanes_status_reaps_dead_runner`, `test_lanes_slot_cap_one_alternates`.
  - So must the seeds with criterion (c): `test_lanes_setup_preflight_refuses_linked_only` and `test_lanes_detach_timeout_no_lock_ends_child`.
  - Adjust `TESTS_EXCLUSIVE` to the `in` rulings. Moving a seed `out` needs the spec's evidence: the R6 conversion that removed its window, named in the ruling.
- [ ] **Step 5:** Run the acceptance commands.
- [ ] **Step 6: Commit:** `git add tests/overnight_lanes_test.sh && git commit -m "test(lanes): template fixture, exclusive rulings (#54)"`.

### Task 14: README Tests section

Risk: **mech**.

**Touches:** `README.md` (the `## Tests` section only, `:342-346`).

**Acceptance:** `grep -n 'TEST_JOBS\|run_affected\|TESTS_EXCLUSIVE\|exclusive-scan' README.md` shows the new text.

- [ ] **Step 1:** Rewrite the section to cover:
  - `sh tests/run_all.sh`, the merge gate: parallel by default, with `TEST_JOBS` jobs (default ncpu − 2);
  - `TEST_JOBS=1`, today's serial gate;
  - `TEST_SUITES`, `TESTS_ONLY` and `TEST_SH=dash`;
  - what the summary shows and when a run is red (a job, completeness, floor);
  - `sh tests/run_affected.sh [--base REF] [--list]`, for in-progress checks only, never a gate;
  - for suite authors: `TESTS_EXCLUSIVE` (R5's criterion), `TESTS_REAL_CLOCK`, `TESTS_FINAL`, `before_each`, the `# exclusive-scan:` ruling lines, `# scan-ok:`, `$TMP/bin/msleep`, `own_group`, the `${TMPDIR:-/tmp}` mktemp rule, and that the floors live in run_all's table;
  - two gates on one machine load each other's exclusive phase; lower `TEST_JOBS`.

  About 30 lines.
- [ ] **Step 2: Commit:** `git add README.md && git commit -m "docs(readme): parallel test gate, run_affected, suite tags (#54)"`.

---

## Wave 5

### Task 15: Static guards and ruling check

Risk: **mech** (folds into the final review).

**Touches:** `tests/harness_test.sh`.

**Tests:** `test_no_unscoped_process_scans`, `test_mktemp_uses_tmpdir_template`, `test_suite_tmp_under_tmpdir`, `test_exclusive_scan_candidates_ruled`, `test_knobs_named_in_headers`.

**Acceptance:** `sh tests/harness_test.sh && dash tests/harness_test.sh`. Green on the integrated W1–W4 branch.

- [ ] **Step 1: Write the five tests** (spec R2.5, R5, R7). Each prints `file:line` for every offender.
  - `test_no_unscoped_process_scans`:
    - `grep -nE '(^|[^a-z])(pgrep|pkill|ps -A)' tests/*_test.sh`, minus comment-only lines;
    - a line passes if it contains `$TMP`, `msleep`, `-P `, `-p `, `-g `, `"-$`, `-- -` or `# scan-ok:`;
    - the offender list must be empty.
  - `test_mktemp_uses_tmpdir_template`: every `mktemp` line in `tests/*_test.sh` and `tests/state_fixtures.sh` (code, not comments) contains `"${TMPDIR:-/tmp}/` or `# scan-ok:`.
  - `test_suite_tmp_under_tmpdir`:
    - a PATH-shadowed `mktemp` in `$TMP/shadow` logs `"$@"` and its result to `$TMP/mk.log`, then runs the real one;
    - run `TESTS_ONLY=__none__ TMPDIR="$TMP/td" ${TEST_SH:-sh} tests/sync_test.sh` and `tests/state_guard_test.sh`;
    - every logged path starts with `$TMP/td/`.
    - (`__none__` is not listed, so no test runs, and run_tests reports nothing about it.)
  - `test_exclusive_scan_candidates_ruled`, for each suite:
    - scan rows = `awk -f tests/exclusive_scan.awk`;
    - rulings = `sed -n 's/^# exclusive-scan: \([^ ]*\) \(in\|out\) .*/\1 \2/p'` (use `grep -E` plus `awk`; BRE `\|` is not portable);
    - `TESTS_EXCLUSIVE` = its `^TESTS_EXCLUSIVE=` line, evaluated in a subshell with `eval`;
    - fail on: a flagged test with no ruling; a ruling for a test the suite does not list in `run_tests`; an `in` test missing from `TESTS_EXCLUSIVE`; an `out` test in it; a `TESTS_EXCLUSIVE` test with no `in` ruling.
  - `test_knobs_named_in_headers`:
    - `STUDIO_SETUP_POLL_SECONDS` is in `sed -n '1,40p' studio-setup`;
    - `STUDIO_GATE_POLL_SECONDS` is in `sed -n '1,30p' studio-gate`;
    - both overnight knobs are in `sh studio-overnight --help`;
    - `STUDIO_OVERNIGHT_REAP_POLL_SECONDS` is in `overnight-lanes.sh`;
    - `TEST_PHASE`, `TEST_SHARD` and `TEST_TIMING_LOG` are in the `assert.sh` header;
    - `TEST_JOBS`, `TEST_SUITES`, `TEST_LOG_DIR`, `TEST_SLOWEST`, `TEST_JOB_TIMEOUT`, `TEST_SH`, `RUN_ALL_SUITES_DIR` and `RUN_ALL_TABLE` are in the `run_all.sh` header;
    - `LANES_FIXTURE_TEMPLATES` and `OVERNIGHT_FIXTURE_TEMPLATES` are in their suites.
- [ ] **Step 2:** Run them. A red result names a leftover in another suite's file; T15 must not edit that file. Report it, and the controller sends it to the final fix wave.
- [ ] **Step 3: Commit:** `git add tests/harness_test.sh && git commit -m "test(harness): static guards for scans and temp dirs, ruling and knob-header checks (#54)"`.

---

## Final steps

- [ ] **F1 — Final whole-branch review (Opus, standalone).**
  - It covers `git diff origin/main...54-faster-test-gate`, against the spec and this plan's Review Focus.
  - It checks Acceptance 7 line by line: production diffs are knob reads, validation and tick math only, and every default equals today's literal.
  - It checks that no test was removed or weakened (rule 1): `git diff origin/main -- tests | grep '^-.*assert_'`, with every removed assertion line matched by a replacement.
  - Its findings go to `$SP/reports/final-review.md`.
- [ ] **F2 — Fix wave.**
  - Fresh fixers, grouped by disjoint files, given the findings and the diff range. This includes T15's leftovers and every batched Minor.
  - Re-review only after a Critical, 3+ Importants or a production-bug fix.
- [ ] **F3 — Integrated full gate, once.**
  - Run `sh "$SP/heavy.sh" "$SP/reports/gate-1.log" env TEST_LOG_DIR="$SP/gate-1" sh tests/run_all.sh` at the default `TEST_JOBS`.
  - If it is red, root-cause it (systematic debugging), fix it and rerun. Never widen a threshold or retry.
  - When it is green:
    - **New suites' floors (D14):** add rows for `harness_test`, `run_all_test` and `run_affected_test`, each with its assertion sum from `summary.tsv`.
    - **Shard tuning (spec R4):**
      - total = the sum of `summary.tsv` seconds; target = total ÷ `TEST_JOBS`;
      - measure each sharded suite's setup cost with `TESTS_ONLY=__none__ sh tests/<suite>.sh`, timed;
      - set each sharded suite's N to the smallest N whose expected job time, (suite seconds − setup) ÷ N + setup, is ≤ target;
      - re-order the table rows by suite seconds, descending.
    - Commit: `git commit -m "test(run_all): tuned shard counts, new suites' floors (#54)" tests/run_all.sh`.
- [ ] **F4 — Acceptance runs** (spec Acceptance 2–6). Each run goes through `heavy.sh` with its own `TEST_LOG_DIR`, and its log is kept.
  1. **Pre-check (spec Falsify F3).** The parallel phase of the suites with timing asserts, twice, at `TEST_JOBS=6` under `yes > /dev/null` × 4:
     `TEST_SUITES="overnight_lanes overnight studio_setup toolkit hook state_pointer state_move overnight_runs overnight_progress" sh tests/run_all.sh`.
     Any failure outside `TESTS_EXCLUSIVE` adds that test by criterion (c), with its ruling line, then reruns.
  2. **Three consecutive green full gates.** No code change between them. Run 2 is under `yes > /dev/null` × 4, started before the gate and killed after it. Any red resets the count and is root-caused. If an exclusive-phase test fails only under that load, run the same test under the same load on the 6f2445b export's serial gate (`$SP/baseline/repo`). If it fails there too, the operator decides.
  3. **`TEST_SH=dash sh tests/run_all.sh` once.** For each failure, run the same test with `TESTS_ONLY` under `dash tests/<suite>.sh` in `$SP/plan-probe/repo` (the 6f2445b export). A failure that happens there too is pre-existing: list it for F8. Any other failure is fixed now.
  4. **`TEST_JOBS=1 sh tests/run_all.sh` once.** Record its wall time (the serial-after time).
  5. **Ctrl-C, scripted.** Start the full gate through the setsid launcher, send INT after 120 s, and assert all of these within 15 s:
     - exit 130;
     - `pgrep -f "$LOGDIR"` is empty;
     - `pgrep -f "$PWD/studios/"` is empty.

     The operator's real-terminal Ctrl-C (spec Acceptance 6) is listed in the PR checklist for them.
- [ ] **F5 — A/B idle measurement** (spec "Measurement protocol").
  - **Idle check before each run.** Wait until `pgrep -fl '_test\.sh|run_all\.sh'` prints nothing and the 1-minute load (`sysctl -n vm.loadavg`, field 2) is < 4. The wait polls every 30 s, in the form of `$SP/baseline/wait.sh`. Append both outputs, timestamped, to `$SP/ab/measure.log`.
  - **A, the old gate.**
    - `$SP/baseline/repo` is the 6f2445b export, with the two-line `TIMING_LOG` instrumentation in its `tests/assert.sh`.
    - If that directory is gone, rebuild it: `git archive 6f2445b | tar -x -C "$SP/baseline/repo"`, then re-apply the two lines. Add `_ts=$(date +%s)` before the test call in `run_tests`, and after it add `[ -n "${TIMING_LOG:-}" ] && printf '%s\t%s\t%s\n' "$(basename "$0")" "$_t" "$(( $(date +%s) - _ts ))" >> "$TIMING_LOG"`.
    - Drive it serially with `$SP/baseline/drive.sh`, after clearing its old outputs.
  - **B, the new gate.** `sh tests/run_all.sh` at the default `TEST_JOBS`, with `TEST_LOG_DIR="$SP/ab/B"`, started as soon as A ends and the idle check passes again.
  - **Watch.** A monitor samples the load and `pgrep -fl '_test\.sh'` every 60 s during both runs. If a foreign suite appears, or the load stays ≥ 6 for 5 minutes, the pair is void and runs again.
  - **Report**, to `$SP/ab/report.md`:
    - A's and B's wall time;
    - per suite, A's seconds and B's job-seconds sum;
    - A's 20 slowest tests;
    - B's exclusive-phase seconds;
    - the serial-after time from F4;
    - per suite, A's and B's assertion counts.
- [ ] **F6 — Floors to A's counts.**
  - Replace the table's provisional floors with A's per-suite counts. For lanes, keep 1128 if A's count is lower, since 1127 vs 1128 is the timing-dependent count the peers loop removed.
  - If any floor changed, run one more full gate (green). That is the final gate.
  - Commit: `git commit -m "test(run_all): floors from the origin/main A/B run (#54)" tests/run_all.sh`.
- [ ] **T16 — PROGRESS entry** (mech; touches `docs/game-dev/PROGRESS.md`).
  - Add a `### 2026-10-06 — Faster test gate (#54)` entry at the top of `## Log`, in the style of the #49 entry.
  - It covers: what changed (harness partitions, the parallel runner, hermetic suites, event waits, knobs, templates and run_affected); the A vs B wall time; the exclusive phase's time; the serial-after time; the final shard counts; and the dash result.
  - Commit: `git commit -m "docs(progress): faster test gate (#54)" docs/game-dev/PROGRESS.md`.
- [ ] **F7 — The PR body** (written for the operator, not pushed by this plan). It carries the spec's Acceptance 9 list:
  - A vs B, in total and per suite;
  - the exclusive phase's time;
  - the serial-after time;
  - the assertion table, with the lanes peers-loop change justified line by line (spec "Floors");
  - the R5 ruling table, collected from every suite's `# exclusive-scan:` lines;
  - the final shard counts;
  - the dash result and the follow-up issue numbers;
  - the operator's manual Ctrl-C check.
- [ ] **F8 — Follow-up issues** (`gh issue create`, one per item, each linked from the PR):
  - each pre-existing dash failure from F4.3, with its suite, test and message;
  - `studio-adopt:19`'s bare `mktemp -d` escapes the per-job TMPDIR (production, out of scope here);
  - no machine-wide lock between two concurrent gates (spec "Not doing");
  - any reviewer finding deferred as out of scope.

  Then remove every task worktree whose branch is on the story branch, and record what is left, and why.

## Falsify

The five assumptions in this plan most likely to be wrong were each checked cheaply on 2026-10-06, on this machine.

| # | Assumption | Check | Result | Plan change |
|---|---|---|---|---|
| P1 | run_all can stop a job's group with `kill -SIG -- -PGID` under both shells | `$SP/plan-probe/killgroup.sh`: a setsid'd `sleep`, signalled from `sh -c` and from `dash -c` | **False for `--`**: dash says "Illegal number: -". `kill -TERM "-$pgid"` and `kill -0 "-$pgid"` work in both | D1 and every kill in T2's code use no `--`. Spec R4 step 1 amended (47d7067) |
| P2 | The harness's own variable names cannot collide with a suite's | `grep -n '_rt_' tests/*.sh` | **False**: lanes `:3875-3878` uses `_rt_cfg` | D2: the `__rt_` prefix, the name and idx re-derived after each test, `test_harness_private_names_unused`. `grep -c '__rt' tests/*.sh` is all 0 |
| P3 | The job-session test can read the session id with `ps -o sess=` | `$SP/plan-probe/zombie.sh` on macOS | **False**: `sess=` prints 0 | `test_run_all_job_has_own_session` asserts pgid == `$PPID` (the setsid'd wrapper) and tty `??`/`?` (spec R4 amended earlier) |
| P4 | The spec's gate budget test ("not repeated within 60 s, checked with a 3 s hold") catches wrong tick math | Arithmetic: at 0.2 s ticks an unscaled `waited % 60` repeats after 12 s | **False**: a 3 s hold passes with or without the fix | D3: `test_gate_poll_keeps_budget` holds 13 s and expects exactly 1 waiting line |
| P5 | The runner symlink puts `$TMP` in every runner, lane and detach argv without breaking the liveness checks | `grep -n 'studio-overnight' studio-overnight overnight-runs.sh`: the liveness greps (`studio-overnight:248`, `:1057`; `overnight-runs.sh:15`) match on the basename; `SELF_DIR` resolves links in a loop (`:31-37`) and `SELF_ABS` keeps the link path, which the detach child re-execs | **Holds** | None. `test_lanes_runner_argv_names_tmp` (T6) pins it live |

Also checked, and holding:
- **The pool's design.**
  - `type f` prints "function" in both shells (`f is a shell function` in dash, `f is a function` in bash), so the `before_each` probe works.
  - Both shells reap background children themselves: `kill -0` then sees a finished job as gone, and `wait PID` still returns its status. That is why the rc file, not `wait`, is the source of truth (`zombie.sh`).
- **The scan runs under macOS awk.** `exclusive_scan.awk` flags 85 tests on 6f2445b (`excl-scan.tsv`).
- **CPUs.** `getconf _NPROCESSORS_ONLN` is 8 and `hw.physicalcpu` is 4, so the default `TEST_JOBS` is 6 (spec Risks: Only 4 physical cores).

## Self-review

- **Spec coverage:**
  - R1: T1 and T2.
  - R2: T1 (scrub and helpers), T6–T10 (per suite), T15 (guards).
  - R3: T1.
  - R4: T2, F3.
  - R5: T1 (awk); T8, T10, T12 and T13 (rulings); T15 (check).
  - R6: T1 (`next_second`), T6/T7 (helper ticks), T8, T10, T11, T12.
  - R7: T4 and T5 (knobs); T6, T7 and T8 (`before_each`, carriers); T15 (headers).
  - R8: T12, T13.
  - R9: T3.
  - Acceptance 1: F3, F6. Acceptance 2–6: F4. Acceptance 7: F1. Acceptance 8: F5. Acceptance 9: F7.
  - Files: T14, T16.
- **Placeholders:** none. The overnight floor (1132) was measured during planning (T0 Step 2).
- **Names:** knob locals, row formats, the job layout and the test names are used the same way in every task.
- **Review Focus:** each of the five lines has its test in the owning task (T1, T2, T3).
