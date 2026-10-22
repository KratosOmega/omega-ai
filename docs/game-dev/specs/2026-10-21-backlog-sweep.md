# Backlog sweep: six stories from live-run bugs — Design

Date: 2026-10-21
Status: Design. Not a plan: interfaces and formats are fixed here, and the code is left to the builder.
Story: #83 (umbrella issue). Integration branch `integration/backlog-2026-10-21`, cut from `origin/main`
cfe29ff. Each story branches off the integration branch and merges back into it.
Binding inputs: the operator's decisions and the controller's rulings of 2026-10-21 (the scratchpad
`fixall/decisions.md`), and two triage reports read at cfe29ff. Every file:line below was re-read at
cfe29ff for this spec. Where triage was wrong, the code wins, and §9 records the correction.
Classification: mixed. S1, S2 and S4 are runner and harness fixes. S3 changes a hook that runs in every
session. S5 adds a new unit kind and a new config key, and changes when the overnight runner holds. S6
is skill text only.

Paths: `L` = `studios/game-dev/bin/overnight-lanes.sh`, `O` = `studios/game-dev/bin/studio-overnight`,
`T` = `tests/overnight_lanes_test.sh`, `OT` = `tests/overnight_test.sh`, `X` =
`studios/game-dev/skills/execute/SKILL.md`. Paths without a prefix are relative to the repo root.

## 1. Intent and why

The backlog is made of real bugs found in live phoenix runs, not wishlist items. The worst one is
**#82**. #71 added `test_engine_args` so that GUT runs at `--fixed-fps 60`, but the final gate never
sees that key. Every run with fixed FPS on therefore runs its final `studio-test` wall-paced, and goes
red at its last step. bashful-bat-bite (2026-10-21) opened its final PR [red] with 24 tick-exact
failures. The same head, with the key visible, was 25033/0 green.

The other stories follow the same pattern: a run that should have finished needed a person.

- #69: a task-unit stop holds the run for a bug that one debug session would find.
- #81: a run that must land in a feature branch can't say so.
- #60: units run the project's test script outside the gate, so `status` says `gate: free` during a
  45-minute suite.
- #14: a default-branch run's final review gets an empty diff.
- #78, #76 and #32: load-flaky tests turn the merge gate red with no real fault.
- #63: a watchdog can outlive its lane and signal a reused process group.

## 2. Goals, non-goals, anti-goals

**Goals**

- G1. Every gate and test that the runner launches itself sees the run's config keys (#82).
- G2. A manifest can name the final PR's base. Without the field, nothing changes (#81).
- G3. Every test the sweep touches asserts on work or events, never on wall time under load (#78, #76, #32).
- G4. The merge gate's floors are exact counts, maintained by a helper, and full runs on one machine
  serialize on a built-in lock (#64).
- G5. A bare call to the project's gate script is denied with a message that names the gated
  alternatives. The guard also sees `sh -c`, `"$(…)"` and backticks (#60, #63-3).
- G6. A unit watchdog never outlives its lane, and never signals once its parent is gone (#63-1).
- G7. A task-unit stop that names no human-owned category gets one debug-repair unit before it holds
  (#69).
- G8. A default-branch run reviews the commits it made (#14).

**Non-goals**

- Any phoenix change: no `merge.sh`, no `run-tests.sh` self-gating (#60 option C), no phoenix config.
- Debug repair for single-plan (non-manifest) runs. `story_gate_loop` is lanes-only today, and so is
  this.
- #73's skip-on-unrelated-push design. The operator chose to keep refusing (§8).
- #74's preflight token. Closed as won't-fix (§8).
- The interactive Plan 2 Task 16 run (#6): folded into a later live check.
- `studio-setup`'s own config fallback (`TOP`, else `STATE_ROOT`; `bin/studio-setup:68`), which ignores
  `STUDIO_START_DIR`. Recorded as a follow-up (§10). It is not #82.

**Anti-goals: the design fails if any of these happens**

- A1. **A behaviour change when no new config is set.** A project without `Final base:` and without
  `test_engine_args`/`gate_short_lane`/`user_dir`, and whose `gate_command` is unset, behaves byte for
  byte as at cfe29ff: argv, report lines, status lines and endings. The deliberate exceptions, each
  decided by the operator or ruled by the controller:
  - `stop_repairs` defaults to 1;
  - the Stop-category skill text;
  - the gate-script guard, which acts only when `gate_command` is set;
  - the test harness's exact floors and suite lock.
- A2. **A loosened bound sold as a flake fix.** Each flaky test gets a deterministic assertion of the
  same property. Raising a hang guard is allowed only where the guard asserts nothing about speed
  (`status_per_story`, ruled).
- A3. **Touching phoenix.** No file outside this repo changes, and phoenix's checkout is never read for
  writing.
- A4. **A Stop-line format that blinds an existing reader.** Every reader greps `^- [0-9-]* Stop: `
  (O:799, O:810, L:680, L:701, L:972). The category goes after `Stop: `, never before it (§7, F6).

## 3. Global constraints

- POSIX sh only, and clean under dash (`TEST_SH=dash`). No bashisms, no `local`, and no `$BASHPID`
  (bash 3.2 has none: use the `sleep & ps -o ppid= -p $!` idiom from `bin/studio-gate:403-413`).
- Opt-in config keys default to today's behaviour (A1). New keys are validated by the existing `cfg`
  helpers (O:109-119), and a bad value is a preflight refusal.
- After S2 merges, the `run_all.sh` floors are exact. Every later story runs
  `sh tests/run_all.sh --update-floors` after it rebases on the integration branch, and commits the table
  with its tests.
- Hand-run suites use a scratch cwd outside every repo and an explicit, existing `TMPDIR` (a missing
  `TMPDIR` once made a suite `rm -rf` a worktree). Long suites run as one background run plus its
  notification, never as stacked poll shells.
- No reinstall. The operator signals it after the merge.
- Landing is mode 2. Each story merges into the integration branch. Then one PR goes from integration
  into main. A local full gate (`tests/run_all.sh` under sh and under `TEST_SH=dash`, under the
  heavy-suite lock, never during a phoenix final gate) runs before `gh pr merge --admin --squash`.

## 4. S1 runner — `issue-82-runner-config` (#82, #81, #73 docs)

### 4.1 #82: the runner's own launches see the run's config

**Problem.** `final_gate` (L:1727-1730) runs `( cd "$FINAL_W" && exec sh "$SELF_DIR/studio-gate"
final-gate -- sh -c "$_fg_c" )` with no `STUDIO_START_DIR`. `studio_cfg` (`bin/gate-class.sh:22-32`,
byte-identical in `engines/godot/cfg.sh:8-18`) reads a key from `<git top>/.studio/config.json`, and only
when that file lacks the key, from `$STUDIO_START_DIR/.studio/config.json`. The autopilot writes the #71
keys in the run worktree only, and `FINAL_W` (the integration worktree) has no such keys. So
`engines/godot/test.sh:43` (`test_engine_args`), `bin/studio-gate:63,127` (`gate_short_lane`) and
`engines/godot/isolate.sh:28` (`user_dir`) all read empty. The only export in the tree is the unit
launch at O:1321.

**Audit of every gate, test or setup launch by the runner (cfe29ff):**

| Site | What | Sees `STUDIO_START_DIR` today | After S1 |
|---|---|---|---|
| O:1321 | unit sessions (`claude-gd`) | yes, explicit | unchanged |
| L:1729 | `studio-gate final-gate` (studio-test/lint/run, then `studio-setup gate`) | **no** | yes |
| L:637 | direct `land_once_direct`: `studio-gate merge -- <merge_command>` | **no** (wider than #82 says) | yes |
| L:1856, L:1953 | `studio-setup` (worktree_setup) in `FINAL_W` | no; harmless (setup is exclusive, and setup reads its own config) | yes |
| O:1952 | setup preflight `studio-setup` in `SP_W` | no; harmless | yes |

**Design (ruled).** In O, right after `START_DIR` becomes final, export it once:

```sh
START_DIR="$(sh "$STATE_BIN" root --work 2>/dev/null || true)"     # O:564, unchanged
STUDIO_START_DIR="$START_DIR"; export STUDIO_START_DIR             # new
```

- The detached child is a fresh `sh studio-overnight start`, so it passes O:564 again and exports there.
- `detach_start` unsets every `STUDIO_*` at O:1655-1657 and re-derives `START_DIR` at O:1659. It
  re-exports on the line after O:1659, so the parent's `lanes_start --check` sees the same value.
- `status_reap_dead` (O:2116) and `lanes_reap_at` (L:1541) set `START_DIR` to another run's recorded dir
  inside a subshell. They launch no gate, so a stale export there is harmless. The builder confirms
  that `lanes_reap` launches nothing gated and records it in a comment.
- O:1321's explicit export stays: a unit must get the value even if a later edit moves the global one.
- `studio_cfg` prefers the tree's own config per key, so the export never overrides a key the
  integration worktree sets itself.

**Secondary (`RECORD/done`, ruled: leave it).** `lanes_finish` (L:1473-1477) writes `done` only on the
ending `done`. `lanes_ending` (L:1317-1327) requires `final_ok` (L:1307-1311): integration needs a green
final PR. A red final PR gives `partial … final PR red` and no `done` **by design**: a resume re-runs the
final step (step 0, L:1814-1822) and may turn it green. The only change is a comment on `lanes_finish`
that says this, and that the operator marks `done` by hand after landing a red final PR. The existing
test `test_lanes_report_every_ending` keeps asserting the no-`done` case.

**Failure modes.**
- `START_DIR` empty (`root --work` failed): the export is empty, and `studio_cfg` ignores an empty value
  (`-n` check). The behaviour is today's.
- A bad `test_engine_args` in the run's config now also makes the final gate exit 1, naming the key
  (`test.sh:44`). Units already fail the same way, so this is not new.

**Acceptance (T):**
- `test_lanes_final_gate_sees_run_config`: the run worktree's config has `"test_engine_args":
  "--fixed-fps 60"` and `FINAL_W` has none. `use_gate` records `${STUDIO_START_DIR:-unset}`, and
  `studio_cfg test_engine_args` evaluated from `FINAL_W`, into `$CALLS/fg.env`. Both equal the run's
  start dir and `--fixed-fps 60`.
- `test_lanes_direct_land_sees_run_config`: the direct-mode merge stub records `STUDIO_START_DIR` = the
  run's start dir.
- `test_lanes_unit_env_unchanged`: a unit's `fullenv` `STUDIO_START_DIR` line is byte-identical to
  today's.
- `test_lanes_detach_child_exports_start_dir`: under `STUDIO_OVERNIGHT_DETACH_CHILD_CMD`, the child sees
  the variable although the parent stripped `STUDIO_*`.

### 4.2 #81: `Final base:` manifest field

**Problem.** The final PR's base is hard-coded to `$DEFAULT_BRANCH`:
- L:1736: `final_pr_open --base`;
- L:1915: the integration `gh pr create`;
- L:1810: `_fi_m=origin/$DEFAULT_BRANCH`, what the final step merges in;
- L:783: the story sync refs;
- L:230: the refusal text.

bashful-bat-bite had to land in `KAN-1650-bashful-bat-tuners`. Its PR was retargeted by hand, and the
operator merged it, because the classifier denies a raw commit-tree push merge.

**Grammar.** An optional header line, read by `mf_header` (L:35-37):

```
Final base: <branch>     # optional; integration mode only; default: the default branch
```

- The value is a branch name that passes `git check-ref-format --branch`.
- It must not be `integration/<slug>`, `run/<slug>` or anything under `progress/`.
- It must exist as `refs/remotes/origin/<branch>` after mf_check's fetch (L:209).
- A value equal to the default branch is the same as no field, byte for byte.
- `Final base:` with `Mode: direct` is refused: `manifest: Final base: is for Mode integration only
  (direct lands on the default branch)`.
- A missing branch is refused: `manifest: Final base: origin/<b> does not exist (push it, or drop the
  field)`.
- A story's `Branch` equal to the base is refused by L:178's rule. Its text gains `or the run's Final
  base`.

**Variables.** `MF_BASE` is set in `mf_load` (L:45-55) and again in `lanes_load_run` (L:1485-1490):
`MF_BASE="$(mf_header 'Final base')"; [ -n "$MF_BASE" ] || MF_BASE="$DEFAULT_BRANCH"`.
`lanes_load_run` sets `DEFAULT_BRANCH` at L:1491-1494, so it parses `MF_BASE` after that.

**Touch points, and what stays.**

| Site | Change |
|---|---|
| L:1734-1741 `final_pr_open BRANCH [BASE]` | the second arg defaults to `$DEFAULT_BRANCH` |
| L:1819 (step 0), L:1910, L:1915 | pass `$MF_BASE` / `--base "$MF_BASE"` |
| L:1810 `_fi_m` | `origin/$MF_BASE`: the final step syncs integration with the base (ruled) |
| L:783 sync refs | `[ "$MF_TARGET" = "$MF_BASE" ] \|\| _sy_refs="$_sy_refs origin/$MF_BASE"` |
| L:230 refusal | `create it from origin/$MF_BASE and push it` |
| L:1401 report | `Final PR: <url> (<color>) into <b>`, only when `MF_BASE` ≠ default |
| `lanes_status_lines` (L:1559+) | one `final base: <b>` line, only when non-default |
| O help (~L:406-414) and `shared/omega/skills/autopilot/SKILL.md:97-99,166` | document the field; the integration branch is pushed from `origin/<Final base or default>` |
| **unchanged** | L:1449 (bundle-2 story PRs into the default branch), L:619/652 and `land_once_direct`, `progress_direct` L:1946/1967, `ids_default_branch` (story-id uniqueness ignores the base, ruled) |

**Failure modes.**
- The base is deleted mid-run: the final step's fetch leaves `origin/<b>` unresolved. Step 1's
  `merge-tree` and `gh pr create` fail and end `no final PR`, as with any red step.
- The field is changed between start and resume: `RECORD/final`'s PR no longer matches step 0's lookup,
  so a second PR would be opened. The builder adds the base as a fourth field of `RECORD/final`, and step
  0 refuses when it differs (`final base changed since the last final step (<old> → <new>) — close PR
  <url> or restore the field`).
- With no field, every argv and line is byte-identical (A1, and acceptance below).

**Acceptance (T):**
- `test_lanes_final_base_absent_identical`: `gh` calls and report bytes equal a cfe29ff golden for a
  1-story run.
- `test_lanes_final_base_opens_pr_into_it`: with `Final base: feat/x` on origin, `gh` sees
  `pr list … --base feat/x` and `pr create --draft --base feat/x`. The final step merges `origin/feat/x`.
  The report and status name `feat/x`.
- `test_lanes_final_base_missing_refused`: a dry run exits 2 with the missing-branch text.
- `test_lanes_final_base_direct_refused`: the field plus `Mode: direct` refuses.
- `test_lanes_final_base_story_branch_refused`.
- `test_lanes_final_base_sync_uses_base`: the sync check merges `origin/feat/x`, not `origin/main`.
- `test_lanes_final_base_changed_on_resume_refused`.
- The autopilot contract (`tests/omega_contracts/autopilot_contract.sh`) asserts the new template line.

### 4.3 #73 docs (no code)

The refusal at O:1925-1929 stays. One paragraph goes in O's `start --detach` help (O:299-312) and one
bullet in the README Overnight section (README.md:127-129). Text:

> In direct mode the setup check is tied to `origin/<Target>`, the default branch. A push to it during
> the check (15–20 min) makes the child refuse with "origin/<Target> moved since start --detach checked
> it". Re-run `start --detach`, start in the foreground, or use integration mode, where only the run
> pushes its Target.

**Files (S1):** L, O, `shared/omega/skills/autopilot/SKILL.md`, X (§7 step 4: the PR base is "the run's
Final base when set" in lane wording only), README.md, T, `tests/omega_contracts/autopilot_contract.sh`,
`docs/game-dev/overnight-events.md` (if status/report lines are listed there).

## 5. S2 tests — `issue-64-test-harness` (#78, #76, #32, #64)

S2 merges first. It changes the merge gate itself.

### 5.1 #78: two load-flaky lanes tests

- `test_lanes_left_gate_reaped` (T:2637-2656). Drop `_t0`/`_secs` and the `-lt 60` assertion (T:2651).
  The retry's own gate is the `gate.times` row whose field 8 (`tag`) ends in `-A-T1-retry` and whose
  field 4 (`rc`) is 0. Assert:
  - exactly one such row;
  - its **field 5** (`wait`, seconds; `bin/studio-gate:526` writes `epoch who hold rc wait lane class
    tag`) is `-lt 30`.
  The existing reaped-message, lock-free and no-survivor assertions stay. The message must not match
  the exclusive scan's `a` pattern (`tests/exclusive_scan.awk:28`: no "under N s"). Once the test has no
  other window, drop it from `TESTS_EXCLUSIVE` (T:4855).
- `test_lanes_status_per_story` (T:2190-2215): `wait_pid_or_fail "$RPID" 60` → `180` (T:2197). It is a
  hang guard and asserts nothing about speed (ruled).

### 5.2 #76: `test_progress_scale_with_past_rows` counts work

Replace the `date +%s` budget (`tests/overnight_progress_test.sh:167-188`) with a spawn count:

- A shim dir `$TMP/shim` goes first on `PATH` for the `st` calls. It holds one wrapper per external
  command that `status` runs (the builder lists them from one `sh -x` trace of `st`). Each wrapper is
  `printf x >> "$TMP/spawns"; exec <absolute real path> "$@"`.
- Run `st` with no history and count bytes (`N0`). Add the 30 × 100 rows, run `st` again (`N1`). Assert
  `N1 - N0 <= D`. D is the delta measured at cfe29ff plus 10, written in the test's comment with the
  measured value. A per-row spawn regression adds thousands; reading all 30 runs instead of 20 adds
  10 × k.
- Keep `assert_contains … "rough: 2000 past units"` (P:189). Delete `_t0/_tb/_fast`, the
  `TESTS_EXCLUSIVE` line (P:237) and its `exclusive-scan:` comment (P:236), because the test no longer
  has a window.

### 5.3 #32: Multica install self-test flake

In `integrations/multica/tests/install_test.sh:340-354`:
- The second `inst`'s assertion message includes `$(cat "$TMP/err")`, so a recurrence names the step.
- The stub's self-test is independent of wall time: `tests/stub-launchctl:95` `timeout=20` → `120`, and
  this test sets `OMEGA_MULTICA_SELFTEST_WAIT=30` around both `inst` calls, then restores 10 (the
  `inst_env_wait` pattern, :391).

The gate for this item is `integrations/multica/tests/run.sh`, which is not part of `run_all.sh`.

### 5.4 #64 items

**Item 2: exact floors and `--update-floors`.**

- `checks()` (tests/run_all.sh:262-280): `asum[s] < floor[s]` → `asum[s] != floor[s]`. The message is
  `<s>: <n> assertions, floor <f> (floors are exact — run sh tests/run_all.sh --update-floors after a
  deliberate change)`.
- A suite with no table row (today "one job, floor 1", :127) is red in a full run, with `<s>: no floors
  row — run --update-floors`. In a partial run it stays a note.
- Each run that reaches `checks` writes the counts file `$(git rev-parse --absolute-git-dir)/run-all-counts.tsv`.
  Each worktree has its own git dir, so worktrees never clobber each other's file. The format, one line
  per suite in this run:

  ```
  # run-all-counts v1 head=<sha> tree=<cksum of `git status --porcelain -- . ':!tests/run_all.sh'`> sh=<TEST_SH>
  <suite>\t<assertions>\t<ok|red>
  ```

  `red` means the suite failed a check other than the floor.
- `sh tests/run_all.sh --update-floors` runs no suites. It:
  - refuses (exit 2) when there is no file, when `head` or `tree` differs from now (`counts are from
    another tree — re-run the suites`), or when a listed suite is `red`;
  - otherwise rewrites the floor column of each listed suite in the heredoc table (:44-79), and appends
    a `<suite> 1 <n>` row for a listed suite that has none;
  - leaves the shard counts and the row order as they are;
  - prints one `<suite>: <old> → <new>` line per change and exits 0.
  A partial run updates only its suites.
- Floor counts must match under sh and dash, serial and parallel. If any suite differs, the builder makes
  its assertion count unconditional before exact mode lands (F13).

**Item 5: the built-in heavy-suite lock.** It is taken by a full run only: `PARTIAL=0` and
`TEST_NO_LOCK` unset.

- Path: `<git common dir>/heavy-suite.lock/`, with the common dir from `git rev-parse
  --path-format=absolute --git-common-dir`. Outside a git repo the lock is skipped, with one note.
- Acquire: `mkdir` the dir, then write `owner` atomically (to `owner.$$`, then `mv`). The owner file is
  key=value lines:

  ```
  label=<TEST_LOCK_LABEL, else $USER@<basename of the worktree>>
  pid=<run_all's $$>
  started=<UTC ISO-8601>
  host=<hostname -s>
  cwd=<pwd -P>
  ```

- On `mkdir` failure, read `owner`:
  - **Stale**, and taken over (rm `owner`, `rmdir`, retry `mkdir`; a lost race just waits again): same
    `host`, and `kill -0 pid` fails or `ps -o args= -p pid` does not contain `run_all.sh`.
  - **Live** otherwise. That includes a different host, a lock with **no** `owner` file, and a
    **legacy hand-made owner file**: `owner:`/`since:`/`what:` lines with no `pid=`, as the 10-09 and
    10-19 plans wrote it. A lock with no pid can't be checked, so it is never taken over. A crash
    between `mkdir` and `mv` leaves the no-owner state, which the operator clears with `rmdir`.
  - The waiting line prints whichever format it finds. For the new format it prints
    `label`/`pid`/`started`/`host`; for a legacy file it prints the `owner:`/`since:`/`what:` values;
    otherwise it says "no owner file".
- **Hand locking is retired (ruled 2026-10-21).** Sessions stop taking the lock by hand before
  `run_all.sh`: run_all takes it itself. A session that still holds a hand lock (a run already in
  flight) runs `TEST_NO_LOCK=1 sh tests/run_all.sh` so it doesn't wait on its own lock. The README,
  and the cross-session rule in the plans, say "run_all.sh takes the lock; never mkdir it by hand".
- Wait, never refuse. Print `run_all: waiting for the heavy-suite lock — held by <label> (pid <p>,
  since <started>, host <h>)` once, or `… — held by a lock with no owner file (rmdir <path> once its
  holder is done)`. Then print `run_all: still waiting (<n> min)` every 5 min. Poll every 5 s.
- Release: on every exit path (normal, `on_signal`, die after acquisition), remove `owner` and the dir,
  but only when `owner`'s pid is `$$`.
- Once it holds the lock, run_all exports `TEST_NO_LOCK=1` to its jobs, so a suite that runs `run_all.sh`
  nested (run_all_test, harness_test) never waits on its parent. `tests/run_affected.sh` exports
  `TEST_NO_LOCK=1` before both `exec`s (:174-180), so it never takes the lock (ruled).

**The other items:**
- **Item 1:** `tests/exclusive_scan.awk:19-20` tracks `<<'X'`, `<<X` and `<<-X` and skips lines up to
  the delimiter, so a column-0 `}` in a heredoc no longer ends the test.
- **Item 3:** run `sh tests/run_affected.sh --list` in a scratch clone with each of `bin/studio-gate`,
  `bin/godot-cmd.awk` and `bin/overnight-lanes.sh` touched. Add an explicit mapping (:121-131) only for a
  hub whose list misses a suite that tests it. Otherwise close the item with §8's note.
- **Item 4:** `bin/studio-adopt:19` becomes `TMPD="$(mktemp -d "${TMPDIR:-/tmp}/studio-adopt.XXXXXX")" ||
  { echo "studio-adopt: cannot create a temp dir under ${TMPDIR:-/tmp}" >&2; exit 2; }`.
- **Item 6:** the operator runs the serial `TEST_JOBS=1` gate in a quiet window. It is documented in §8
  and does not block the merge.
- **Item 7:** the stub's `waitfor`/`waitexist` and `bggate` waits (T:295-300, :310, :368) use an epoch
  deadline. `STUB_WAIT_SECONDS` defaults to 60, and `STUB_WAIT_TICKS` stays as an alias (ticks/10) until
  no caller sets it.
- **Item 8:** two tests: a same-name double `lanes_fixture` call, and a bare origin with
  `LANES_FIXTURE_TEMPLATES=0`.
- **Item 9:** extract `lf_key` (T:568-569). The hand-built key at T:4781 calls it.
- **Item 10:** rebalance the lanes shard count from the sweep's own full-gate `logs/timing.tsv`, as the
  last S commit before the final gate. Otherwise leave it.

**Acceptance (S2):**
- `tests/run_all_test.sh`:
  - `test_run_all_floor_exact_above` and `…_below`: both are red with the new message;
  - `test_run_all_norow_red_full`;
  - `test_run_all_counts_file_written`;
  - `test_run_all_update_floors_rewrites`: only the floor column changes, `git diff` shows only those
    lines, and a new suite gets a row;
  - `test_run_all_update_floors_refuses_stale_tree`, `…_refuses_red_suite` and `…_refuses_no_file`;
  - `test_run_all_lock_waits_and_names_holder`: a live owner (a `sleep` in a fake run_all argv) makes the
    second run print the holder line and start after release, an event wait;
  - `test_run_all_lock_takes_over_dead_pid`;
  - `test_run_all_lock_ownerless_waits`;
  - `test_run_all_lock_legacy_owner_waits`: a hand-made `owner:/since:/what:` file is never taken over, and its values are printed;
  - `test_run_all_lock_released_on_signal`;
  - `test_run_all_lock_skipped_partial_and_no_lock`;
  - `test_run_all_jobs_inherit_no_lock`.
- `tests/run_affected_test.sh`: `test_run_affected_sets_no_lock`.
- `tests/harness_test.sh`: `test_exclusive_scan_heredoc_brace`.
- `tests/studio_adopt_test.sh`: `test_adopt_mktemp_fails_closed` (TMPDIR is a missing dir: exit 2, no
  write).
- T: the #78 rewrites, `test_lanes_fixture_same_name_twice`, `test_lanes_fixture_bare_origin_fresh`.
- P: the #76 rewrite.
- Multica: `install_test.sh` green 10× in a row with 4 concurrent copies (a manual record in the PR, not a
  test).
- The full gate is green under sh and dash at the S2 head, with `--update-floors` a no-op afterwards.

**Files (S2):** `tests/run_all.sh`, `tests/run_affected.sh`, `tests/exclusive_scan.awk`, T,
`tests/overnight_progress_test.sh`, `tests/run_all_test.sh`, `tests/run_affected_test.sh`,
`tests/harness_test.sh`, `tests/studio_adopt_test.sh`, `studios/game-dev/bin/studio-adopt`,
`integrations/multica/tests/{install_test.sh,stub-launchctl}`, README.md (the gate paragraph: exact floors,
the lock, `TEST_NO_LOCK`).

## 6. S3 guard — `issue-60-gate-bypass-guard` (#60, #63 item 3, #67)

### 6.1 #60: deny a bare run of the project's gate script

**Problem.** `hooks/godot-guard.sh` and `bin/godot-cmd.awk` act only when a simple command's first word
is Godot (awk:234-235). `json_main` also returns at once when the command text lacks `godot`
(awk:83). So `.github/scripts/run-tests.sh > /tmp/gate.log 2>&1` (phoenix kan-1540, 2026-10-08) runs
with no lock, no cap, no `gate.times` row, and no idle exemption.

**Which script.** `gate_command` is read the way `studio-setup gate` reads it (`bin/studio-setup:68-69,87`:
the flat `"gate_command": "…"` string, first match). The hook looks in this order, and the first
non-empty value wins:
1. `<git top>/.studio/config.json`;
2. `$STUDIO_START_DIR/.studio/config.json`;
3. the main worktree's (`dirname` of `git rev-parse --path-format=absolute --git-common-dir`).

The **gate script** `G` is the first word of the value. When that word is `sh`, `bash`, `zsh` or
`dash`, `G` is the first word after it that does not start with `-`. Quotes are removed. `G` is guarded
only when it contains `/` or ends in `.sh`. `npm test` or `make check` guard nothing (no false denials
of `npm`).

**Matching (json mode only).** The hook passes `-v gs="$G"` to the awk. `json_main` returns early only
when the text holds neither `godot` nor `basename(G)`. In `check()`, after the existing
assignment/keyword/wrapper skip (awk:226-233), let `W` be the first word, quotes removed, a leading `./`
stripped. Verdict `g` when either:
- `basename(W) == basename(G)`; or
- `W` is `sh`, `bash`, `zsh`, `dash`, `.` or `source`, its options contain neither `-c` (handled by the
  recursion, §6.2) nor `-n` (a syntax check), and the next non-option word matches as above.

A call whose first word is anything else is never `g`: `cat G`, `grep x G`, `bash -n G`, `studio-gate
<who> -- G`, `studio-test`, `studio-setup gate`. That is how "wrapped by studio-gate, studio-setup gate or
studio-test" is decided (a first-word model, the same as the Godot verdicts). `out=hook` prints `g` in
the verdict line (order `b c g a`). Its segment is line 3, cut and escaped like line 2.

**Message** (one sentence, then the existing `_use` line):

> game-dev: refused a direct run of the project's gate script `<G>` (gate_command): outside the gate it
> skips the lock, the run cap and gate.times, and status shows the gate free while it runs. Run the suite
> with studio-test, one file with studio-test --file <tests/unit/x.gd>, or the project gate as
> studio-gate <who> -- <segment> (keep any cd/env before it).

**Fail open.** Every one of these exits 0 and prints nothing for `g`: a missing config, an unreadable
file, `git` failing, an empty or unguarded `G`, or an awk error. The Godot verdicts keep their own paths.
The hook runs on every Bash call, so the config read costs at most one `git rev-parse` plus one `sed`.
The builder measures 100 hook calls before and after and records the median delta in the PR. The budget
is +15 ms.

### 6.2 #63 item 3: follow `sh -c`, double-quoted `$(…)` and backticks (ruled scope)

Correction (F9): an **unquoted** `$(…)` is already caught, because `(` and `)` are separators in
`parse()` (awk:211). A probe at cfe29ff denied `x=$(godot --headless -s a.gd)` as `c`. The gaps are:
- `"$(…)"` inside double quotes;
- backticks, quoted or not;
- `sh|bash|zsh|dash -c STR`, including `-lc`, `-ec` and other clusters that contain `c`.

Design, in **json mode only**: the brief's md mode and its rewrite stay unchanged, so the rewrite never
has to place a nested segment.
- `check()` queues nested texts, and `parse()` drains the queue after the outer text. awk's `w[]` and
  `nw` are global, so recursion in place would corrupt the outer command:
  - for `sh|bash|zsh|dash` with a `-c` option, the word after it is queued;
  - while scanning, `parse()` records each `` `…` `` body, and each `$(…)` body inside double quotes
    (balanced parentheses, with quotes tracked inside), and queues it.
- Depth cap 3. Deeper texts are ignored (fail open).
- A nested text's segments come from the nested string (`CSRC` is the nested text). The hook's
  `c`-retry text is the inner segment.
- No recursion into a word after a first word that is not a shell. `studio-gate x -- sh -c 'godot -s
  a.gd'` stays allowed: the gate runs it.

### 6.3 #67 items (triage-B, verified at cfe29ff; the choices are ruled)

| Item | Site | Change |
|---|---|---|
| hook exits before reading stdin | `hooks/godot-guard.sh:21-22` | `cat` first, then the detector check |
| `\b \f \uXXXX` decode | awk:63-74 `unesc` | `b`→\010, `f`→\014, `\u00XX` (ASCII) → the byte; others kept literally |
| heredoc body inside a md fence flagged | awk:92-96 | while a `<<` is open, join fenced lines up to the delimiter before `parse` |
| `$ ` prompt | awk md fence | strip one leading `$ ` (after the indent) only at the start of a fenced line |
| CRLF `\` continuation (O1) | awk:126 `cont`, the join | strip one trailing `\r` first |
| blockquote `>` in a wrapped span (O2) | awk:103 | strip a leading `>[ ]?` on continuation lines |
| retry drops a leading `cd`/env | guard `_c` text | append "(keep any cd/env before it)" |
| prose inside backticks rewritten | `bin/studio-brief:108` | accept; one sentence in the studio-brief header |
| studio-brief ignores its symlink | `bin/studio-brief:69` | the `readlink` loop from `bin/studio-dispatch:34-40` |
| read-only brief | `bin/studio-brief:337` `cp -p` | `[ -w "$_rf" ]` first: `studio-brief: warning: <f> is not writable — not rewritten` |
| a symlinked brief replaced by a file (N3) | `:344` `mv -f` | resolve the link target first and rewrite the target |
| test order dependence | `tests/studio_brief_test.sh:597` | make the test self-contained |
| empty denied command | `O:1483` | `${_dn_c:--}` |
| comment grammar | `O:1090` | "count it and keep the first one's id" |
| `allow_rules` in the header, missing file silent | `L:1-12`, `O:179-181`, `L:424` | header line; a dry run or start warns on stderr `allow file <path> missing — units get no allow rules` (a warning, not a failure) |
| `land_repair` header | `L:656-666` | add the permission-route note sentence |
| untested endings | `OT:2455-2475` | add `sync-repair`, `timed-out`, `stalled` and `gate-repair-stop` to the denied-note loop |

N1 (stray backtick pairing follows CommonMark) is documented, not changed. The probe item (rule fast-path
in auto mode) is a live check, out of scope.

**Acceptance (`tests/hook_test.sh` unless named):**
- `test_guard_gate_script_denied`: `.github/scripts/run-tests.sh > /tmp/g.log 2>&1; echo $?`, `sh
  .github/scripts/run-tests.sh`, `./run-tests.sh` from `.github/scripts`, `bash run-tests.sh`, `.
  run-tests.sh`. Each one is denied, and the reason contains `studio-test --file` and `studio-gate`.
- `test_guard_gate_script_allowed`: `studio-gate t -- .github/scripts/run-tests.sh`, `studio-setup gate`,
  `studio-test`, `cat …/run-tests.sh`, `grep x run-tests.sh`, `bash -n run-tests.sh`, `vim run-tests.sh`.
- `test_guard_gate_command_sources`: the top config, then `STUDIO_START_DIR`, then the main worktree; an
  unguarded `npm test` denies nothing.
- `test_guard_gate_fail_open`: an unreadable config, no git, an empty value.
- `test_guard_sh_c_recursion`: `sh -c "godot -s a.gd"`, `bash -lc 'godot --import'` and `sh -c "sh -c
  'godot -s x'"` are `c`. `studio-gate x -- sh -c 'godot -s a.gd'` is allowed. Depth 4 is clean.
- `test_guard_quoted_subst_and_backticks`: `echo "$(godot -s a.gd)"`, `` echo `godot -s a.gd` `` and
  `` x="`godot --import`" `` are `c`. Unquoted `$(…)` is unchanged.
- `test_guard_md_mode_unchanged`: every existing studio_brief_test rewrite golden is byte-identical.
- `test_guard_reads_stdin_without_detector`, `test_guard_unesc_bf_u`.
- `tests/studio_brief_test.sh`: heredoc in a fence, `$ ` prompt, CRLF continuation, blockquote span,
  symlinked studio-brief, read-only brief message, symlinked brief stays a link.
- OT: `test_overnight_denied_note_empty_command`, the extended ending loop.
- `test_overnight_allow_file_missing_warns`.

**Files (S3):** `hooks/godot-guard.sh`, `bin/godot-cmd.awk`, `bin/studio-brief`, O (three one-line
edits), L (header and comment only), `tests/hook_test.sh`, `tests/studio_brief_test.sh`, OT, README.md
(the guard's row).

## 7. S4 watchdog — `issue-63-watchdog` (#63 items 1, 2, 4, 5)

### 7.1 Item 1: the watchdog is tracked from birth, and dies with its lane

**Problem.** `run_unit` forks the watchdog at O:1380-1401. The **parent** writes `$LDIR/wpid` after the
fork (O:1404). A lane SIGKILLed in that window leaves a watchdog nobody tracks. The watchdog never
checks its parent, and at the deadline it signals `-$CPID` (O:1396-1399), which may be a reused pgid
by then. With `idle_minutes 0` it naps once, all the way to the deadline (O:1384). `merge_wait`'s
watchdog (L:574-583) has the same shape. It sleeps the whole session in one nap.

Correction (F23): inside a lane, `$$` is the **runner's** pid, not the lane's. Lanes are `( lane_main
"$_k" ) &` subshells (L:2058), and the lane's pid is `LANE_PID` (L:1046). A "parent is `$$`" check
copied from studio-gate would be wrong under lanes.

**Liveness rules.** These apply to both watchdogs, through one helper `wd_parent_ok` in O, also used by
L:
1. At start, before anything else: the trap is installed, then `sleep 0 & _k=$!; _me=$(ps -o ppid= -p
   $_k)` (its own pid) and `_pp0=$(ps -o ppid= -p $_me)` (its parent at birth), then `wait $_k`.
2. Under a lane (`LDIR` set), the watchdog writes `_me` to `$LDIR/wpid.$_me`, then `mv -f` to
   `$LDIR/wpid`. The parent's write at O:1404 stays. It is the same pid, so there is no conflict. The
   parent's `rm -f` (O:1416) runs only after the parent's `wait` on the watchdog, so a self-write never
   follows the removal.
3. The parent is alive iff `kill -0 $_pp0` succeeds, and `ps -o ppid= -p $_me` is empty or equals
   `_pp0`. An empty ps read counts as alive, as in studio-gate (:405-410): a transient ps failure must not
   leave a hung session unbounded.
4. The check runs after every nap, and again immediately before each `kill -TERM` and `kill -KILL`. On
   failure the watchdog exits 0 and signals nothing.
5. Naps are at most `_poll` (`STUDIO_OVERNIGHT_IDLE_POLL_SECONDS`, default 30), with or without the idle
   check. `merge_wait` naps at most 30 s, with a test seam `STUDIO_OVERNIGHT_WD_POLL_SECONDS`.
6. Teardown: `kill "$WPID"` becomes `wd_end "$WPID"`: `kill -TERM "$WPID"; pkill -TERM -P "$WPID"`, then
   `wait`. Ending its `sleep` child makes the watchdog's `wait "$_sp"` return at once, so the teardown
   never waits out a nap. The same applies to `merge_wait` (L:590) and `lanes_end_sessions` (L:1192-1195,
   the TERM half only).

**Failure modes.** A reparented watchdog exits, and the lane's session is then ended by
`lanes_end_sessions` (cpid) as today. A watchdog that dies before it writes `wpid` signals nothing. When
ps fails, the watchdog stays: the cap must not fail open.

### 7.2 Item 2: anchored gate exemption

O:1128's `cfull[i] ~ /studio-(test|run|setup|gate)/` matches any mention of the name. The new rule, in
the same awk: split `cfull[i]` quote-aware (single and double quotes) at `;`, `&`, `|`, `(`, `)` and
newlines. For each segment, skip leading blanks, `NAME=value` words, the wrappers `env` (with its
options), `exec`, `command`, `time`, `nohup`, `nice [-n N]` and `timeout|gtimeout [opts] N`, then one
`sh|bash|dash|zsh` with options. Remove quotes from the next word. The call is exempt iff its basename
matches `^studio-(test|run|setup|gate)$`.

- Exempt: `cd d && studio-test`, `sh /x/bin/studio-gate t -- …`, `"$S/studio-test" --file a.gd`, `env
  A=1 studio-run --seconds 10`, `timeout 600 studio-test`.
- Not exempt: `grep studio-test x`, `echo "run studio-test"`, `cat bin/studio-gate`, `vim studio-run`.

### 7.3 Item 4: close it, plus one test

`live_gates` (O:1203-1213) already requires a live pid whose `ps args` contain `studio-gate`. Add
`test_overnight_idle_dead_gate_registration`: a `gate.units/<tag>/<dead pid>` file does not exempt the
unit. It ends `stalled`.

### 7.4 Item 5: close it, with a note

The #59 plan is `docs/game-dev/plans/2026-10-07-overnight-hardening.md`, not `2026-10-08-*` (F10).
Neither it nor PR #61's body names what "A2 minor 8" covered. PR #61 says only "A2 minor 8: coverage
gaps, skipped". Comment in §8.

**Acceptance (OT unless named):**
- `test_overnight_watchdog_writes_own_wpid`: a fake slow parent write (seam), and `lanes/K/wpid` exists
  once the watchdog has started.
- `test_overnight_watchdog_exits_when_reparented`: SIGKILL the lane right after the unit starts. Within
  one poll (seam 1 s; an event wait on the pid's disappearance with a 60 s hang guard), the watchdog is
  gone. A marker command at its deadline proves it signalled nothing.
- `test_overnight_watchdog_rechecks_before_kill`: at the deadline seam the parent is gone, so no TERM is
  sent.
- `test_overnight_watchdog_idle_off_still_polls`.
- `test_overnight_teardown_ends_nap`: poll seam 600 s. The run finishes under its usual 120 s guard. Not
  a timing bound: a teardown that waited out the nap trips the hang guard.
- T: `test_lanes_merge_wait_watchdog_reparent`.
- `test_overnight_idle_exemption_anchored`: the exempt and non-exempt tables above, through
  `open_calls … gate` on a fixture JSONL.
- `test_overnight_idle_dead_gate_registration`.

**Files (S4):** O (run_unit's watchdog, open_calls's gate rule, one helper), L (`merge_wait`, and the
`lanes_end_sessions` TERM half), OT, T, `tests/fixtures/overnight-open-calls.jsonl` (new rows).

## 8. S5 stop repair — `issue-69-stop-repair` (#69)

### 8.1 Problem

KAN-1598's T8 stopped on "twin reactive cook not byte-identical … needs a human ruling … or relaxing the
assertion". The cause was an ordinary leaked-state bug, which one triage step finds. Today a task unit's
new `Stop:` goes straight to `holdable` (O:928-940). The only repairable stop is `stop: gate red — `
(`story_gate_loop`, L:1095-1107). Item 1 of #69 (engine args) was done by #71. Items 2-4 are open.

### 8.2 The Stop line and its categories

Format, unchanged in its prefix (A4, F6):

```
- <date> Stop: [<category>] <reason>
```

- `<category>` is exactly one of `taste`, `scope`, `perm`, `env`, `human`: lowercase, in brackets,
  followed by one space. All five are **human-owned**:

  | Category | Meaning |
  |---|---|
  | `taste` | a design or feel call only a person can make |
  | `scope` | the spec or plan conflicts with itself or the code, or the work exceeds the story |
  | `perm` | it needs a permission, a credential, or an action no run may take (merge, force-push, secrets) |
  | `env` | the machine or the toolchain is broken (Godot or GUT missing, disk, gh auth, `studio-test` exit 2/3) |
  | `human` | any other decision that needs a person, named in the reason |

- The runner holds a single source of truth, `STOP_HUMAN_CATS="taste scope perm env human"` (L). The
  execute skill lists the same five, and a contract test greps both.
- Skill rules (X "Every stop", §8; the operator decided them):
  - every Stop a unit composes names one human-owned category;
  - "can't find the cause", "nondeterminism" and "flaky" are not stop reasons;
  - relaxing, skipping or loosening a check is never the offered fix;
  - fixing the root cause is always in scope.
- The fixed-text stops X already prescribes keep their exact text, and the runner classifies them by
  prefix: `gate red — `, `gate timed out — `, `gate repair red — `, `land repair red — `, `sync repair red
  — `, `worktree setup`, `adopt sync — `, `check — `.
- The printed-message hard stops (X :716, :902, :981: `Stop: <the printed message>` for `studio-test`
  exit 2/3 and `studio-run` exit 2) become `Stop: [env] <the printed message>`.
- **A legacy or uncategorised Stop** (no bracket, or an unknown word such as `[bug]`) is **not**
  human-owned. It is repairable, under the cap (ruled).

### 8.3 When a debug repair runs

`stop_repairable` is true iff all of these hold:

1. `_rs_srep < STOP_REPAIRS`. `_rs_srep` counts every debug-repair unit of the story, those after a
   resume included. It is set to 0 once in `run_story`, next to `_rs_rep` (L:1130).
2. `${ENDING%% \[permission-route — *}` equals `STOP_ENDING`: the ending is a unit's new Stop line, not a
   runner-made `stop: …` (`unexpected stage`, `run budget`, a `story_resolve` failure).
3. `STOP_SRC = feature` and `isolated`: the conditions under which `holdable` would hold it.
4. `STOP_LABEL` matches `T[0-9]*` with an optional `-retry`: a task unit. `story_units` (O:1615) sets
   `STOP_LABEL="$_base"` wherever it sets ENDING from a new Stop (one assignment; single-plan mode
   ignores it). **Every unit launch resets `STOP_LABEL=""` first** (ruled 2026-10-21, from the builder
   check), so the Stop of a debug-repair unit, a gate-repair unit or a plan-stage unit never carries a
   stale `T<n>` label.
4a. The story's stage is `execute` at the time of the Stop (`studio-state show` stage). A plan-stage
    unit is also labelled `T1` by `label_for`, but it is never repairable (ruled).
4b. **Never a repair of a repair (ruled).** A Stop written by a `debug-repair` unit holds the story,
    whatever its category. `STOP_REPAIRS` > 1 allows that many repairs of *distinct* task-unit stops
    in one story. It never chains a repair on a repair's own Stop.
5. `UNIT_DENY_NOTE` is empty. A unit that hit a classifier denial is treated as `perm`, because a repair
   would hit the same denial (the issue lists permission-route as human-owned).
6. The reason (`${STOP_ENDING#stop: }`) does not start with `[<c>] ` for any `c` in `STOP_HUMAN_CATS`.
7. The reason does not start with any fixed-text prefix in §8.2.

### 8.4 The runner loop

`story_gate_loop` (L:1095-1107) becomes one repair loop with two arms. The gate arm is unchanged
byte for byte:

```sh
story_gate_loop() {
  while :; do
    case "$ENDING" in
      "stop: gate red — "*)
        if [ "$_rs_rep" -ge "$GATE_REPAIRS" ]; then …unchanged…; break; fi
        op_boundary "$1" || break; _rs_rep=$((_rs_rep + 1)); gate_repair "$1" || break; story_units ;;
      "stop: "*)
        stop_repairable || break
        op_boundary "$1" || break; _rs_srep=$((_rs_srep + 1)); stop_repair "$1" || break; story_units ;;
      *) break ;;
    esac
  done
}
```

- With `stop_repairs 0`, condition 1 always fails, the loop breaks, and `ENDING` is unchanged: today's
  behaviour, byte for byte (A1).
- A debug repair that succeeds feeds `story_units`, which may then end `stop: gate red — `. The same loop
  then takes the gate arm. The two counters are independent.
- The hold loop's resume path (L:1141-1146: `last_stop_gate_red` → gate repair) is unchanged. A resumed
  non-gate stop goes straight to `story_units` as today. A later new stop can get a debug repair only
  if the cap is not used.
- **Direct and integration modes** behave the same: `run_story` is common to both. Single-plan runs have
  no `story_gate_loop`, so they are unchanged.

### 8.5 `stop_repair ID` (L, next to `gate_repair`, mirroring L:721-746)

- Its preconditions are the same as gate_repair's: `lane_halt` → halt reason; `run_budget_out` → `stop:
  run budget`.
- `story_write "$1" debug-repair`; then `snapshot`; count the feature ledger's `^- [0-9-]* Repair: stop —
  ` lines (`_sr_b`).
- `PROMPT="/game-dev:execute --debug-repair"`. `LAUNCH_ENV` adds `STUDIO_REPAIR=$(sq "stop:$STOP_LABEL")`.
- `run_unit "$n" debug-repair`. The model is `model_repair`: `model_for` (O:225) adds `debug-repair`. The
  session cap is `session_minutes`, as for every unit. Restore `PROMPT`/`LAUNCH_ENV`.
- Outcomes:

  | What happened | Row | Return | ENDING |
  |---|---|---|---|
  | a new Stop line | `stop` | 1 | `$STOP_ENDING$UNIT_DENY_NOTE`, holdable as any feature stop |
  | `_sr_a > _sr_b` (progress) | `progress` | 0 | `story_write running` |
  | timed out | `timed out` | 1 | `debug repair timed out (session_minutes N) — after <reason>$UNIT_DENY_NOTE` |
  | stalled | `stalled` | 1 | `debug repair stalled<stall_note> — after <reason>$UNIT_DENY_NOTE` |
  | none of these | its outcome | 1 | `debug repair made no progress<orphan_note> — after <reason>$UNIT_DENY_NOTE` |

  `<reason>` is the original stop's reason.
- **"No progress"** means no new `Repair: stop — ` line and no new Stop line. A commit without the ledger
  line is no progress, as in gate_repair.
- `holdable` (O:936-937) adds `"debug repair made no progress"*|"debug repair timed out"*|"debug repair
  stalled"*` to its `isolated` list. These are globs: today's exact `"gate repair made no progress"`
  pattern misses an orphan note, which is out of scope here (§10).

**New unit kind, everywhere unit kinds are listed:**
- `model_for` O:225;
- `story_units_table` L:1359's label regex;
- the live-story states in `bin/studio-adopt:697`, which **must** include `debug-repair`, or adopt would
  treat a story mid-repair as not live;
- `integrations/multica/bridge/mirror.py:14-16` `STATUS` (`debug-repair` → `in_progress`; an unknown
  state only logs a warning today, mirror.py:470);
- `bin/overnight-progress.sh:10`'s comment;
- `hooks/operator-inbox.sh:109` ("in a --land, --gate-repair or --debug-repair unit");
- `docs/game-dev/overnight-events.md`;
- O `--help`.

### 8.6 Config

```
cfg stop_repairs 1 0 3 int          # O, after `cfg gate_repairs` (O:665)
```

Help line, after O:444-446:

```
  stop_repairs         1     0-3      lanes: debug-repair units per story before a task unit's Stop:
                                    that names no human-owned category holds (taste, scope, perm,
                                    env, human); each is followed by the unit loop again;
                                    0 = such a stop holds at once
```

### 8.7 The `--debug-repair` mode (X, new §12, modelled on §11 :935-993)

- Mode list (X:328-333): `--debug-repair`, the debug-repair unit (§12), launched under a lane when a
  task unit's Stop names no human-owned category.
- Launch: from the start checkout, with the story's env and `STUDIO_REPAIR=stop:<label>`. It bypasses
  §0's stage gate, and these preconditions replace it. A miss is a `Stop: [human] debug repair —
  <precondition>` line.
- **Enter the feature checkout** first, then record operator messages.
- **Preconditions:**
  - `stage execute`;
  - no `shipped` line;
  - the latest `Stop:` line names no human-owned category and is not a fixed-text stop;
  - `STUDIO_REPAIR` starts with `stop:`.
- **Diagnose:** invoke `superpowers:systematic-debugging` with the Stop line, the task's plan section and
  the failing output. When a determinism failure is in play, use the triage recipe: compare the twins
  across processes and within one process. They match across processes but differ within one → a reset
  the runner misses. They differ across processes → wall clock, RNG or instance ids.
- **Fix:** dispatch one fresh fixer (§5 step 5's owning role) with the root cause. It commits
  `fix(stop): <summary>`. Relaxing, skipping or loosening a check is never the fix.
- **Verify** what failed, the way §11 does: `studio-test --file …` for the failing files (gate-routed,
  foreground, `timeout` `$BASH_MAX_TIMEOUT_MS`), up to three rounds. Never the whole gate.
- **Record:** `studio-state ledger "Repair: stop — <root cause>; <fix>"`, commit the ledger
  (`chore(studio): debug repair`), then push the story branch.
- **No root cause, or the cause needs a person:** `Stop: [<category>] debug repair — <what was ruled
  out>; <the decision needed>`, committed, with a human-owned category (`human` when no other fits).
- It never ships or lands, changes no `stage` or `task`, and never merges. One unit: end the turn.

### 8.8 Plan sweep rule (`studios/game-dev/skills/plan/SKILL.md` §7, step 2, :229-236)

Add: "A `## Decisions` clause of the form 'stop (the run) if X', where X is a defect (a failing test, a
mismatch, nondeterminism) and not a decision, is itself a finding. Rewrite it as 'diagnose X; stop only
if Y', where Y is a human-owned decision. Example: 'if twin cooks differ at --fixed-fps 60, stop' becomes
'find the leaked state; stop only if cook N also differs between processes'."

### 8.8a Failure modes

- A repair unit that crashes or is killed: the outcome row says so, and the ending holds (isolated).
- A repair that "fixes" by weakening a test: there is no runner check for this. The skill rule and the
  final review (§5 step 3 sees `fix(stop)` commits) are the guard, and a `fix(stop)` commit joins §5 step
  2's verify-prior-fixes regex (`fix\((T[0-9]+|final|gate|stop|review|B[0-9]+)\)`).
- A unit that writes an unknown category on purpose: it is repairable once, then it holds. The cost is
  one opus session, bounded by `session_minutes` and the run budget check.

**Acceptance (T unless named):**
- `test_lanes_stop_repair_then_lands`: T1 writes an uncategorised Stop; one `debug-repair` unit writes
  `Repair: stop — …`; the T1 retry finishes; A lands. Rows: `stop`, `progress`. Its prompt is
  `--debug-repair`, `STUDIO_REPAIR='stop:T1'`, and the model is `model_repair`.
- `test_lanes_stop_repair_human_category_holds`: each of the 5 categories holds at once, with no
  debug-repair unit.
- `test_lanes_stop_repair_fixed_text_holds`: `gate timed out — …` and `worktree setup failed …` are not
  repaired. `gate red — ` still gets the gate repair.
- `test_lanes_stop_repair_no_progress_holds`, `…_timed_out_holds` and `…_stopped_holds`: each ending
  text matches the table, and the story holds.
- `test_lanes_stop_repairs_zero_today`: with `stop_repairs 0`, the ending, `units.tsv`, events and
  report are byte-identical to a cfe29ff golden.
- `test_lanes_stop_repair_cap_across_resume`: once used, a stop after a resume holds at once.
- `test_lanes_stop_repair_then_gate_red`: a successful debug repair, then a red finish, gets the gate
  arm, and the counters are independent.
- `test_lanes_stop_repair_skips_denied_unit`: a unit with a permission-route note holds at once.
- `test_lanes_stop_repair_non_task_unit`: a `final-review` Stop holds at once.
- `test_lanes_stop_repair_direct_mode`.
- `test_lanes_stop_repair_never_chains`: with `stop_repairs 3`, the debug-repair unit's own uncategorised Stop holds at once, with no second repair.
- `test_lanes_stop_repair_plan_stage_holds`: a plan-stage unit's Stop (labelled `T1` by `label_for`) holds at once.
- OT: `test_overnight_stop_repairs_config` (default 1; 0-3; `4`/`x` refused; the help line).
- `tests/studio_adopt_test.sh`: `test_adopt_refuses_story_in_debug_repair`.
- `integrations/multica/tests/test_mirror_runs.py`: `debug-repair` maps to `in_progress`.
- `tests/studio_test.sh` contract greps:
  - X lists the five categories in this order;
  - X says relaxing a check is never the fix;
  - X §12 exists with its preconditions and the `Repair: stop — ` line;
  - the plan skill has the "diagnose X; stop only if Y" rule;
  - the category list in X equals `STOP_HUMAN_CATS` in L.

**Files (S5):** L, O, X, `studios/game-dev/skills/plan/SKILL.md`, `studios/game-dev/bin/studio-adopt`,
`studios/game-dev/bin/overnight-progress.sh` (comment), `studios/game-dev/hooks/operator-inbox.sh`,
`integrations/multica/bridge/mirror.py`, `integrations/multica/README.md:225`,
`docs/game-dev/overnight-events.md`, T, OT, `tests/studio_test.sh`, `tests/studio_adopt_test.sh`,
`integrations/multica/tests/test_mirror_runs.py`.

## 9. S6 execute — `issue-14-default-branch-base` (#14)

**Problem.** On the consent path (X:214-215 "never implement on `main` without the user's explicit
consent"; in place, X:228-232), the noted branch is the default branch. Then:
- "The base" (X:253-259) is `main`, and `git merge-base main HEAD` = HEAD;
- §4a rule 3's production-bug test (X:479), §5 step 2's verify-prior-fixes list (X:505-509) and the final
  review package `<merge-base>..HEAD` (X:515-516) are all empty;
- the review skill (`skills/review/SKILL.md:76-79,100-101,148`) has the same gap. Playtest uses no
  merge-base.

**Design (decided: keep the consent path and fix it).**
- §0 (c), the line that records the base (X:236-237): when the noted branch is the default branch and
  `git branch --show-current` is the default branch (the in-place path), capture `sha=$(git rev-parse
  HEAD)` **before** the ledger commit. Then write both lines in that one commit:
  `studio-state ledger "base <noted branch>" && studio-state ledger "base-commit <sha>" && git add
  .studio/ledger && git commit -m "chore(studio): ledger"`.
  - The format is `- <date> base-commit <40 or 64 hex>`, one per run, last one wins.
  - `<sha>..HEAD` includes the chore commit, which is harmless: §5's list keeps only `fix(…)` commits.
- **`<merge-base>` definition** (X:253-259, "The base"): when the feature ledger has a `base-commit`
  line, `<merge-base>` is its sha, everywhere X says `git merge-base <base> HEAD` (§4a, §5, §7).
  Otherwise it is `git merge-base <base> HEAD` as today. The review skill's scope (:76-79) and its
  verify-prior-fixes start (:100) use the same rule. Its report-only rule on the default branch (:69-70)
  is unchanged.
- **Resume without the line** (a default-branch run begun before S6), in the same (c) step that writes a
  missing `base` line:
  - with a `T<n> complete a..b` line: the first such line's `a` (`git rev-parse "a"`; `a` may be
    `<first>^1`);
  - else, with the sync's `T<k+1> in progress: <first>..<last>`: `<first>^1`;
  - else `HEAD`.
  It is written and committed as above.
- **Readers.** No code reads a `base` or `base-commit` ledger line. The grep at cfe29ff finds only
  `adopt-base ` readers (`studio-adopt:564,820`, `L:355`, `studio-state:583`), and those never match
  `base-commit`. No ledger parser rejects unknown line types. A contract test pins this, so a future
  reader can't match `base` loosely.

**Failure modes.** A user who switched branches in place mid-run: the sha is still an ancestor. If it is
not (a rewritten history), `git log <sha>..HEAD` fails. X says: stop and say "base-commit <sha> is not an
ancestor of HEAD — fix the ledger line or restart". The run never falls back silently to an empty range.

**Acceptance (`tests/studio_test.sh`):**
- `test_execute_default_branch_records_base_commit`: X §0 (c) has the `base-commit` line and its
  condition.
- `test_execute_merge_base_uses_base_commit`: §4a, §5 and §7 define `<merge-base>` through it.
- `test_execute_resume_rebuilds_base_commit`: the three fallbacks, in order.
- `test_review_scope_uses_base_commit`.
- `test_no_reader_matches_base_commit`: no `bin/` or `hooks/` grep pattern matches `base-commit`.
- Operator acceptance (not a builder task): one pressure scenario on the slim fixture (`tests/pressure/`)
  checked out on main. Its final-review brief lists a non-empty range. It runs with #6's live check.

**Files (S6):** X, `studios/game-dev/skills/review/SKILL.md`, `tests/studio_test.sh`.

## 10. Docs-only closures (comments posted after the integration PR merges)

**#6** (retitle: "Whole-studio smoke test: interactive slim-pipeline run (with #71's live checks)").
Fix `docs/game-dev/plans/2026-09-13-plan-2-quality-loop.md:3021` (`skills 12` → `skills 11`) and
`docs/game-dev/PROGRESS.md:517` (`8 → 12` → `8 → 11`), and point the PROGRESS.md:12 row at #6. Leave the
issue open. Comment:

> Updated in the backlog sweep (#83). Step 3 has been done since 2026-09-16 (PROGRESS.md:496-513). The
> doctor's skill count is 11 (brainstorm, plan, execute, review, playtest, retro, studio, and four domain
> skills), not 12; the plan line and PROGRESS note are corrected. What's left is the human-driven
> interactive run (Steps 4–5). It's now the whole-studio smoke test, and runs with #71's remaining live
> checks. A builder can't do it, because it needs `/clear` between stages, a `claude-gd` login and a real
> PR. Before it runs, re-check that KAN-1257's premise still holds in phoenix.

**#73** (close). Comment:

> Keeping the refusal (operator decision, 2026-10-21). In direct mode the setup check is tied to
> `origin/<Target>`, the default branch, so a push to it during the 15–20 min check makes the detached
> child refuse. Skipping on an "unrelated" push would mean deciding which paths are setup inputs, and a
> wrong guess skips a safety check. The behaviour and the workaround are now in `studio-overnight --help`
> (`start --detach`) and the README: re-run `start --detach`, start in the foreground, or use integration
> mode, where only the run pushes its Target. Landed in #83.

**#74** (close, won't fix). Comment:

> Closing as won't-fix (backlog sweep #83). Only about 1 s of the child's checks could be skipped (60–70
> of ~1,800 spawns), against ~7 s CPU in a 300 s window, under 0.4%. The token would add a trust
> boundary the child must believe, plus a stale-token bug class. Reopen if the child's pre-lock wall time
> at real load gets near `STUDIO_OVERNIGHT_DETACH_WAIT_SECONDS`.

**#63 item 4** (in #63's closing comment, after S4):

> Item 4: no change needed. `live_gates` (studio-overnight:1203-1213) already counts a registration only
> when its pid is live and its `ps` args contain `studio-gate`, so a SIGKILLed gate's leftover entry
> exempts nothing. `test_overnight_idle_dead_gate_registration` now pins this. What's left (a reused pid
> that is itself another studio-gate) is bounded by the session cap.

**#63 item 5:**

> Item 5: closed without a change. "A2 review minor 8" can't be identified. Neither the #59 plan
> (docs/game-dev/plans/2026-10-07-overnight-hardening.md) nor PR #61 says what it covered, beyond
> "coverage gaps, skipped". The idle watchdog now has tests for stall, the gate-call exemption (anchored
> in #83), off/refusals, default seams, until-commands and dead gate registrations. Reopen with the gap
> named if one turns up.

**#64 item 3** (when `--list` shows no gap):

> Item 3: no change needed. run_affected already maps `tests/assert.sh`, `tests/run_all.sh` and `lib/*`
> to every suite explicitly (run_affected.sh:123,130). A `--list` with `bin/studio-gate`,
> `bin/godot-cmd.awk` and `bin/overnight-lanes.sh` each touched selected every suite that tests them,
> through the reference closure. (If a gap was found, the comment names the hub and the mapping added.)

**#64 item 6:**

> Item 6: the sweep's final gate ran green under sh and `TEST_SH=dash` (logs in the #83 PR). The serial
> `TEST_JOBS=1` full gate is an operator task, run in a quiet window with no overnight run live and
> under the heavy-suite lock. Run `TEST_JOBS=1 sh tests/run_all.sh` and post the summary here. It doesn't
> block a merge.

**Follow-ups to file** (not in this sweep):
- `studio-setup` ignores `STUDIO_START_DIR` when it reads `gate_command`/`worktree_setup`
  (`bin/studio-setup:68`).
- `holdable`'s exact `"gate repair made no progress"` (O:937) misses an ending that carries an orphan
  note.

## 11. Merge order and overlap plan

1. **S2 first, alone.** Floors become exact. Every later story rebases on it and runs `--update-floors`.
2. **Then S3, S4 and S6 in parallel.** Each is in its own worktree off the integration head after S2.
   - S3: hooks, awk, `studio-brief` and `hook_test`. Its edits in O and L are one-liners away from the
     others.
   - S4: O's `run_unit` region (1355-1420, 1128) and L's `merge_wait` (568-592).
   - S6: skills only.
   - The only shared file is `tests/run_all.sh`'s table. Merge them one at a time. After each merge the
     next story rebases, re-runs its affected suites, runs `--update-floors` and commits. A floors-table
     conflict is resolved by taking the integration side and running `--update-floors` again. A
     hand-merge of counts is never correct.
3. **S1 next.** It touches O at 564 and 1659 and the help, L in many small regions, T, and X §7 step 4.
   It can start in parallel with step 2 and merge after S4 (both edit O/L, in different hunks).
4. **S5 last.** It is the largest, and it edits L (`story_gate_loop`, near `gate_repair`), O (config,
   `holdable`, `model_for`, `story_units`), X (Every stop, new §12; S1 and S6 also edit X) and T/OT. It
   rebases on everything. It needs per-task Opus review: it is a new seam and changes the unit
   accounting.
5. **Shard rebalance** (#64 item 10) is the last S2-style commit on the integration branch, from the
   final gate's `timing.tsv`. Then the final full gate runs under sh and dash, followed by the admin
   merge.

Per-task review on Opus: S2's lock and floors (the merge gate itself), S3's #60 and recursion (a hook
on every call), S4's watchdog (process lifecycle), S5's runner loop and skill mode. S1's #82 export and
S6 fold into the final whole-branch review.

## 12. Falsified assumptions

| # | Assumption | Verdict | Evidence at cfe29ff |
|---|---|---|---|
| F1 | `STUDIO_START_DIR` is exported only at O:1321 | true | grep finds O:1321 and the two readers only |
| F2 | one export at O:564 covers the run | true, adjusted | the detached child re-runs O:564, but the parent strips `STUDIO_*` (O:1655-1657) and re-derives at O:1659 without export → re-export there |
| F3 | `final_gate` is at L:1727-1730 and the land is at L:637 | true | read |
| F4 | the report's "into main" text (L:1449) is the final PR | **false** | L:1443-1452 lists the bundle-2 *story* PRs into the default branch; it stays. The final PR line is L:1401 |
| F5 | story sync merges the default branch (L:783) | true | so integration-mode sync must use `MF_BASE` |
| F6 | a `Stop[cat]:` marker is safe | **false** | every reader greps `^- [0-9-]* Stop: ` (O:799, O:810, L:680, L:701, L:972), so the marker goes after it: `Stop: [cat] …` |
| F7 | only `stop: gate red` is repairable | true | L:1097, O:936-937 |
| F8 | the `gate.times` wait is field 6 (triage) | **false** | `bin/studio-gate:526`: epoch who hold rc **wait** lane class tag, so wait is field 5 and tag is field 8 |
| F9 | `$( )` bypasses the guard (#63-3) | **partly false** | unquoted `$(…)` is split at `(` (awk:211); a probe denied it. The gaps are `"$(…)"`, backticks and `sh -c` |
| F10 | the A2 review is in `docs/game-dev/plans/2026-10-08-*` | **false** | the #59 plan is `2026-10-07-overnight-hardening.md`; neither it nor PR #61 lists minor 8's content |
| F11 | the guard can add a gate-script check in `check()` alone | **false** | `json_main` returns before parsing unless the text contains `godot` (awk:83); the early return must also admit `basename(G)` |
| F12 | `studio_cfg` falls back per key | true | cfg.sh:11-17 |
| F13 | assertion counts are equal under sh/dash and serial/parallel | unverified | `jq` branches in hook_test (:59ff) change values, not counts (spot-checked); S2's gate under both shells proves or fixes it before exact mode lands |
| F14 | `--update-floors` can read the last run's log dir | **false** | `TEST_LOG_DIR` defaults to a temp dir removed when green (run_all.sh:17-18,330), so the counts file persists in the git dir |
| F15 | run_affected is separate from run_all | **false** | it `exec`s run_all (:176,:180), so it must export `TEST_NO_LOCK=1` or it takes the lock |
| F16 | a new unit state is harmless elsewhere | **false** | `studio-adopt:697`'s live-state list would miss `debug-repair` (adopt mid-repair); mirror.py:14-16 would log warnings |
| F17 | no reader matches `base-commit` | true | only `adopt-base ` patterns exist (studio-adopt:564,820; L:355; studio-state:583) |
| F18 | the review skill needs the #14 fix | true | review SKILL:76-79,100-101,148; playtest has no merge-base |
| F19 | a red final PR leaving no `done` is by design | true | L:1307-1327, L:1477; step 0 L:1814-1822 re-runs it |
| F20 | the #73 refusal is at O:1927-1930 | true (±2) | O:1925-1929 |
| F21 | the doctor's skill count is 11 | true | `studios/game-dev/skills/` has 11 dirs |
| F22 | #32 fails at :351 | true | the second `inst` in `install_test.sh:340-354`; the stub's `timeout=20` at stub-launchctl:95 |
| F23 | the watchdog can compare its parent with `$$` | **false** | in a lane, `$$` is the runner (lanes are `( lane_main ) &`, L:2058; `LANE_PID` at L:1046), so it records its birth parent instead |
| F24 | with idle off the watchdog naps to the deadline | true | O:1384; `merge_wait` always does (L:575) |
| F25 | `gate_command` is read from the tree, else the state root | true | `bin/studio-setup:68-69` |
| F26 | the anti-goal "no change without new config" holds for every story | **false** | `stop_repairs` defaults to 1 (the operator's decision), and the guard acts on the existing `gate_command`; both are listed as deliberate exceptions in A1 |

## 13. Left to the builder

- The list of wrapped commands for #76's spawn shim, and D's measured value.
- Whether `wd_parent_ok` lives in O or in a small sourced file, and the exact seam names for S4's tests.
- The quote-aware split for S4 item 2: awk inline in `open_calls`, or shared with godot-cmd.awk (the
  author leans inline, since the detectors' contracts differ).
- How `parse()` records nested `$(…)` and backtick bodies (positions or text), within §6.2's rules.
- Whether `RECORD/final`'s fourth field (#81) needs a migration for a record written by cfe29ff (the
  author leans: a 3-field record means the default base).
- The hook's latency measurement method, and its result in the PR.
- Splitting each story into tasks. Plans carry files, interfaces, test names and acceptance checks, with
  full code only for: the lock, the counts-file guard, `stop_repairable`/`stop_repair`, the watchdog
  liveness, and the awk `g` verdict and recursion.
- Each story's PR body records the falsified rows it relied on, re-checked at its own base.
