# Faster test gate: parallel, sharded, hermetic suites — Spec

Date: 2026-10-06
Status: Draft for the operator. Operator rulings 1–3 are folded in, and so are the spec falsifier's findings
(1 Critical, 6 Important, 7 Minor; see "Falsifier findings" at the end).
Story: #54 (GitHub issue). Branch `54-faster-test-gate`, off `origin/main` 6f2445b.
Classification: test infrastructure. Production scripts change only through test-only knobs that default to today's behaviour.

## Problem

`sh tests/run_all.sh` takes about 1–2 h on the operator's Mac. It runs the 27 suites one after another, because
`overnight_lanes_test.sh` (about 190 tests and 110 `sleep` calls) and `overnight_test.sh` (about 150 tests) were believed
unable to share a checkout. Those two suites take nearly all of the time. Every PR in this repo, and every autopilot
story that touches it, waits on this gate.

## Goal

Cut the gate's wall-clock time as far as possible with no loss of coverage or strength. The rules from the issue are binding:

1. No test is deleted, skipped, merged away or weakened. Each suite's assertion count stays ≥ its floor (its count on
   `origin/main`), and any exception is justified line by line in the PR.
2. Timing-behaviour tests keep real clocks. That covers timeouts, Ctrl-C/TERM, the detach 10 s window, lock contention,
   the watchdog and "under N s" checks.
3. Faster polling is allowed only in pure wait loops, each with a generous ceiling that returns early. Event waits replace
   fixed sleeps.
4. Every new test-only knob is named in its script's header and defaults to production behaviour. At least one test runs
   it at the production value.
5. The full gate stays the merge gate. The "affected suites" runner is for in-progress checks only.
6. POSIX sh. Everything passes under macOS `/bin/sh` (bash 3.2) and dash.

## Operator rulings (binding)

1. **Load-sensitive timing tests get an exclusive phase.** A suite tags these tests. The gate runs every other test in
   parallel, then runs the tagged tests with nothing else running. Thresholds stay as they are. A standalone
   `sh tests/<suite>.sh`, with no phase set, still runs every test in listed order, as today. This is the same idea as
   Bazel's `tags=["exclusive"]` and pytest-xdist's serial groups.
2. **Runner-side poll knobs are in this story.** They cover:
   - the studio-setup `timed_gate` loops;
   - the studio-gate lock wait;
   - the post-TERM reap loops (`end_session`, `unit_reap`, `lanes_end_sessions`, `tg_stop`);
   - the detach status-window poll (the window stays 10 s).

   Each knob is named in its script's header, and its default is today's value exactly. Loops that count iterations as
   seconds keep their real-clock budget. At least one test runs each knob at the production value, and timing-behaviour
   tests never set them. The existing `STUDIO_OVERNIGHT_POLL_SECONDS` is also used per test where the test does not
   assert on polling cadence, with at least one test kept at the default.
3. **`tests/run_affected.sh` is in this story.** It maps the changed files (against `origin/main` or a given base) to
   suites. Shared or unknown files map to all suites. It is never a merge gate, and it has its own tests.

## Evidence

- **Coupling audit**: a static review of every suite and bin script, plus an empirical run of 2 clones × 27 suites at
  once. Unloaded reruns split the failures three ways:
  - **C1, launch.** A suite started with `&` in a non-interactive sh starts with SIGINT ignored, and that ignore cannot
    be trapped or reset from inside the shell. It made 22 assertions fail in every SIGINT test.
  - **C2–C6, couplings.** These are broad process scans and kills:
    - C2: `pkill -f "$RUNNER start"` (lanes `:2252`);
    - C3: `pgrep -f "$RUNNER"` (lanes `:2856`, `:2206`, `:2253`);
    - C4: machine-wide `ps -A … grep 'sleep 48xx'` (studio_setup `:71`, `:113`, `:122`);
    - C5: `pgrep -f 'sleep 301'` (lanes `:2284`);
    - C6: `^sleep 483x$` scans plus `pkill -f` (lanes `:3126`, `:3178-3182`, `:4008-4014`).
  - **Load.** Under 2× load these failed: the `state_pointer` "< 2–3 s" checks, `overnight_progress`'s "baseline + 3 s"
    check, `overnight_test`'s claim-without-run-dir "< 20 s" check, sighup-while-held,
    `test_lanes_setup_preflight_refuses_linked_only` (5 FAILs, the 120 s watchdog) and
    `test_lanes_detach_timeout_no_lock_ends_child`. In the falsifier's all-alone sweep at load ~12, toolkit's
    `test_run_detects_script_errors` and `test_run_passes_scene_and_windowed` (`studio-run --seconds 1`) failed and then
    passed 3/3 alone.

  Ruled out: writes into the checkout, the real `~/.claude-gamedev/runs`, fixed temp paths, locks, pid-based liveness
  checks and machine-wide state. The old rule that overnight and lanes "must not run at the same time" is explained by
  C2 and C3 alone.
- **Runner argv (falsifier C-1).** `MFP` is relative (`docs/runs/demo.md`, lanes `:532`). A live `ps` shows the runner and
  every lane as `sh …/studios/game-dev/bin/studio-overnight start docs/runs/demo.md`, and the `--detach` child
  (`studio-overnight:1386-1388`) is the same. So no runner, lane or detached child carries the suite's `$TMP` in argv
  today, and `pgrep -f "$TMP"` alone cannot see them. R2 fixes this with a per-suite runner symlink under `$TMP`.
- **macOS `mktemp` ignores `TMPDIR`** for a bare `mktemp -d` (falsifier probe: `TMPDIR=x mktemp -d` gives
  `/var/folders/…`; the man page reads `_CS_DARWIN_USER_TEMP_DIR` first). An explicit template
  `mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"` honours it.
- **Wait audit**: every `sleep` is classed as follows:
  - A: a dead wait that can become an event;
  - B: timing under test;
  - B\*: rule 2 protects it even though an event is possible;
  - C: a poll interval;
  - D: other.

  Estimates from reading the code: class A ≈ 180 s, test-side class C ≈ 60 s, and runner-side polls reachable with knobs
  ≈ 80–120 s.
- **Fixture audit.** Template-then-copy is a GO for `lanes_fixture` and `overnight_test`'s `fixture`, keyed by the full
  argument tuple plus `git remote set-url`. It is a NO-GO for `state_*`'s `proj`, where the saving is too small (~14 s).
  Loaded-machine estimates of the build cost saved: lanes ~300–350 s, overnight ~160–190 s. Unloaded figures are about
  half that.
- **Job-control probes** (2026-10-06, scratchpad `setm-probe.sh`, `falsify/tty-probe.sh`, `falsify/ttys-probe.sh`,
  `plan-probe/setsid-setm.sh`, `plan-probe/own-group.sh`):

  | Launch | macOS `/bin/sh` | `/bin/dash` |
  |---|---|---|
  | `set -m; cmd &`, no tty | own group, INT trappable | "can't access tty; job control turned off": INT stays ignored, no own group |
  | perl `setpgrp(0,0)` launcher, no tty | own group, INT trappable | own group, INT trappable |
  | perl `setpgrp(0,0)` launcher, **with a tty**, suite runs `set -m` | fine | the job is SIGTTIN-stopped (state `T`) for ever: the gate hangs to its timeout |
  | perl `POSIX::setsid()` launcher (own session, no controlling tty) | own group and session, INT trappable; a `set -m` inside still gives its job its own group | own group and session, INT trappable, never stopped; a `set -m` inside is refused as with no tty |
  | test-side `( own_group cmd ) &` (perl: INT/QUIT default, `setpgrp`, exec), under the setsid launcher | own group, INT trappable, `$!` is the command | same |

  So run_all launches each job with `POSIX::setsid` (the form `studio-overnight --detach` already uses), and the four
  test-side `set -m` sites (state_move `:511`, overnight `:637`, lanes `:1082`, `:1103`) move to the `own_group` helper.
  Product scripts are unaffected: suites always start them as `sh <script>`, so they run under macOS `/bin/sh` whatever
  `TEST_SH` is.
- **dash on `origin/main` today** (probe 2026-10-06, `plan-probe/dash-probe.sh`, an export of 6f2445b, stdin
  `/dev/null`, no tty): `lib_test` 112/0 and `studio_setup_test` 49/0 pass; `state_move_test` fails 2 of 244
  (`test_state_mutex_single_acquisition`: "INT exits 130 got 0", "no target pointer was written"), at the `:511`
  `set -m`. The falsifier saw `test_overnight_sigint` fail 2 under dash the same way. By reading, lanes'
  `test_lanes_sigint` and `test_lanes_end_sessions_spaced_path` share the cause. This story fixes all four (the
  `own_group` helper) and runs the whole gate under dash once (acceptance 5).

The load-skewed numbers above are estimates. The real ones come from the A/B measurement (below).

## Measurement protocol (A/B, at the end)

The serial baseline taken on 2026-10-06 is **void**: the 1-minute load was 7.61 at its start (the protocol says < 4), another
worktree's lanes suite ran during it, and the falsifier's probes ran beside it at load up to ~15. Its numbers are not used.

The before/after numbers come from one A/B pair, run back to back after the final fix wave and the acceptance runs:

1. **Idle check, before each run of the pair.** `pgrep -fl '_test\.sh|run_all\.sh'` prints nothing (no suite running
   anywhere on the machine), and the 1-minute load average (`sysctl -n vm.loadavg`, field 2) is < 4. Both outputs are
   written to the measurement log with a timestamp. The plan's wait script polls every 30 s until both hold.
2. **A, the old gate.** An export of `origin/main` 6f2445b (`git archive`), with only its `tests/assert.sh` instrumented
   to append `suite<TAB>test<TAB>seconds` per test (scratchpad `baseline/repo` holds the exact two-line change), driven
   serially by the `baseline/drive.sh` form: each suite in name order, `sh <suite>`, recording seconds, exit status and
   the final `N assertions, M failed` line per suite, and the total.
3. **B, the new gate.** `sh tests/run_all.sh` in the story worktree at the default `TEST_JOBS`, started as soon as A ends
   and the idle check passes again.
4. **Watch.** A monitor samples the load and `pgrep` every 60 s during both runs. If a foreign suite appears, or the load
   stays ≥ 6 for 5 minutes, the pair is void and is run again.
5. **Report.** The PR gets: A's and B's wall time; per suite A's seconds and B's job-seconds sum; A's 20 slowest tests;
   B's exclusive-phase seconds; the serial-after time (acceptance 4); and per suite A's and B's assertion counts.

### Floors

- A suite's **floor** is its assertion count on `origin/main`. run_all's suite table carries the floors. Until the A/B
  run, the table carries provisional floors (the plan takes them from the falsifier's per-test sweep and the voided
  run's green rows, whose counts do not depend on load). The A/B run's A counts replace them before the PR, and the
  final gate runs with the A counts.
- **Counts must be deterministic.** The only timing-dependent count found is lanes `test_lanes_round_trip_two_runs`
  (`:3941-3946`): it asserts once per `*.peers` file that holds an "Other live runs" block, and how many units saw the
  other run depends on timing (1127 vs 1128 across two clones). The fix keeps every check and fixes the count: the loop
  runs over the 8 unit calls of the two stories (`story_calls S1`, `story_calls S2`; 4 each, already asserted), and for
  each call asserts "no Other live runs block, or the block names the other run". Every check the old loop made is still
  made, and a unit that wrongly names its own run still fails. The count becomes 8 + the existing "at least one unit
  saw the block" assertion. Since the old loop asserted once per seeing unit and at most 8 units exist, the new lanes
  count is ≥ any `origin/main` count, so the floor needs no exception. The PR states this line by line.
- A sharded suite's count is summed over its jobs. Final sweeps (R3) run in every partition, so the sum is never below a
  serial run's.

## Design overview

- **Before.** One loop runs `sh "$f"` for each suite in the foreground. Output streams live. The exit code is 1 if any
  suite failed, and there is no summary.
- **After.**
  - Every suite is hermetic: it scrubs inherited variables, keeps every temp file under `TMPDIR`, and scans and kills
    only processes whose argv carries its own `$TMP`, or that it holds by pid.
  - `run_tests` can run one partition of a suite: a shard of the parallel tests, or the exclusive tests.
  - `run_all.sh` runs every parallel partition in a bounded job pool. Each job gets its own session and process group,
    its own `TMPDIR` and its own log. It then runs the exclusive partitions one at a time.
  - It prints each job as one block, followed by one summary, and checks that every listed test ran exactly once and
    that every suite reached its assertion floor.
  - Separately, dead sleeps become event waits, runner polls get test-only knobs, and the two big fixtures are copied
    from templates.

The sections below are the requirements. Each one has its interface, its failure handling and its tests.

## R1. Measurement

- **`tests/assert.sh` `run_tests`.** When `TEST_TIMING_LOG` is set and non-empty, the harness appends one tab-separated
  row per test it runs:

  ```
  T  <suite>  <partition>  <idx>  <test>  <seconds>  <assertions>  <failed>
  ```

  It also appends one row per `run_tests` call, written before the first test runs (so it is there even when the
  partition selects nothing):

  ```
  L  <suite>  <partition>  <listed-count>  <final-idxs>
  ```

  `<final-idxs>` is the comma-separated idx list of the `TESTS_FINAL` tests, or `-` when there are none; run_all's
  completeness check needs it.

  - `<suite>` is `basename "$0" .sh`.
  - `<partition>` is `all`, `p<k>of<N>` or `x`.
  - `<idx>` is the test's 1-based position in the `run_tests` argument list.
  - `<seconds>` is whole seconds from `date +%s`.
  - `<assertions>` and `<failed>` are the test's deltas of `TESTS_RUN` and `TESTS_FAILED`.

  Rows are single short `>>` appends, so concurrent jobs can share one file: an `O_APPEND` write under `PIPE_BUF` is
  atomic. With the variable unset, nothing is written, as today.
- **`tests/run_all.sh`** always sets `TEST_TIMING_LOG=$TEST_LOG_DIR/timing.tsv` for its jobs. It times each job, and its
  summary prints:
  - one row per job: suite, partition, seconds, tests run, assertions, failed, verdict;
  - a total line: wall seconds, suites, jobs, assertions, failed, and the exclusive phase's seconds;
  - the slowest `TEST_SLOWEST` tests (default 20), taken from the timing log.
- **Tests (in `tests/harness_test.sh`):**
  - `test_timing_log_rows`: one `T` row per test, plus one `L` row, with correct deltas.
  - `test_timing_log_off_by_default`: no file is written when the variable is unset.
  - `test_timing_log_l_row_for_empty_partition`: a shard with no eligible tests still writes its `L` row.
  - `test_run_all_summary_and_slowest` (in `tests/run_all_test.sh`): the summary has a row for every job and the slowest
    list is sorted.

## R2. Hermetic suites

1. **Environment scrub**, in `tests/assert.sh`, at source time and before anything else. Every suite sources it near its
   top, so standalone and gate runs both get it. It unsets every variable whose name matches:

   ```
   CLAUDECODE | AI_AGENT | CLAUDE_* | OMEGA_* | STUDIO_*
   GIT_DIR | GIT_WORK_TREE | GIT_INDEX_FILE | GIT_COMMON_DIR | GIT_OBJECT_DIRECTORY
   GIT_ALTERNATE_OBJECT_DIRECTORIES | GIT_NAMESPACE
   ```

   - The names come from `env | sed -nE 's/^(…)=.*/\1/p'`, the same pattern as `studio-overnight:1353`.
     `CLAUDE_CONFIG_DIR` is also removed: a suite never uses the operator's config, and a test that needs one sets its own.
   - Kept: `TESTS_ONLY`, every `TEST_*` harness variable (R3, R4), `HOME`, `PATH`, `TMPDIR` and the locale.
   - Why: an autopilot unit exports `STUDIO_STORY`, `STUDIO_RUN_DIR`, `STUDIO_UNIT_TAG`, `STUDIO_START_DIR` and
     `OMEGA_AUTOPILOT=1` (`studio-overnight:1090-1096`). Today a gate run inside a unit inherits them. For example,
     `studio-state` would write to `.studio/stories/$STUDIO_STORY.md`.
   - The plan greps every suite for a `STUDIO_`/`OMEGA_`/`CLAUDE_` read that comes before its `. assert.sh` line. There
     must be none.
2. **Temp files stay under `TMPDIR` (falsifier I-1).** Every `mktemp` in `tests/*_test.sh`, `tests/state_fixtures.sh`
   and the stubs the suites write (lanes `:264`, `:468`, `:476`) uses an explicit template:
   `mktemp -d "${TMPDIR:-/tmp}/<suite>.XXXXXX"` (or `mktemp "${TMPDIR:-/tmp}/<name>.XXXXXX"` for a file). A bare `mktemp`
   ignores `TMPDIR` on macOS, so without this run_all's per-job `TMPDIR` would not hold the suites' temp files and its
   cleanup by path would pass vacuously. Production scripts are out of scope; `studio-adopt:19`'s bare `mktemp -d`
   escapes the per-job directory but stays correct (it removes its own dir).
3. **C1 and job control.** C1 is fixed in the runner (R4) by the `POSIX::setsid` launcher. Inside the suites, the four
   test-side `set -m` sites become the `own_group` helper from `assert.sh`:

   ```sh
   # own_group CMD… — exec CMD in a process group of its own with SIGINT/SIGQUIT at their defaults,
   # as `set -m` does for a background job, but also under dash with no tty. Call it as the last
   # command of a background subshell: `( cd "$P" && own_group sh "$RUNNER" start ) & PID=$!`.
   own_group() { exec perl -e '$SIG{INT}=$SIG{QUIT}="DEFAULT"; setpgrp(0,0); exec @ARGV or die "exec: $!\n"' "$@"; }
   ```

   `$!` is the command's pid, because the subshell execs perl and perl execs the command. The sites are state_move
   `:511`, overnight `start_bg` (`:637`), lanes `test_lanes_sigint` (`:1103`) and the spaced-path sessions (`:1082`).
4. **C2–C6: name what you kill.** The rule is that every process a suite finds or kills by pattern carries that suite's
   `$TMP` in its argv. Otherwise it is found by a recorded pid.
   - **The runner carries `$TMP` (falsifier C-1).** The lanes and overnight suites set
     `RUNNER="$TMP/bin/studio-overnight"`, a symlink to `$BIN/studio-overnight` made once per suite, and use it for every
     runner call (`STUB_RUNNER` follows). `studio-overnight` resolves the link for `SELF_DIR` (`:31-37`), so its
     siblings are still found in the real bin directory, while `SELF_ABS` keeps the link path. So the runner's argv,
     every lane's (lanes are forked subshells of the runner) and the `--detach` child's (it re-execs `SELF_ABS`) all
     carry `$TMP`. Messages that print `SELF_ABS` now print the link path; the assertions on them (lanes `:2090`,
     `:2266-2267`) compare against `$RUNNER` or a pattern ending in `/studio-overnight'`, and the plan re-checks every
     assertion that names the runner path. Unit tests that set `SELF_ABS="$BIN/studio-overnight"` themselves
     (`:3523`) are unchanged.
   - A live check pins it: `test_lanes_runner_argv_names_tmp` starts a run whose unit hangs, then asserts that
     `ps -o args= -p <pid>` contains `$TMP` for the runner, for a lane (a pid under `lanes/<k>/`) and, in a second
     part, for the `--detach` child (the pid in `detached: pid N`). It then stops both runs.
   - C2: `pkill -f "$TMP/bin/studio-overnight start"` replaces `pkill -f "$RUNNER start"`.
   - C3: `pgrep -f "$TMP"` replaces `pgrep -f '$TMP'; pgrep -f '$RUNNER'` in `detach_stop`, at `:2253` and in
     `test_lanes_no_orphans`. It is now complete: every runner, lane, detached child and stub session carries `$TMP`.
   - C4–C6: every pattern-checked sleeper becomes the marked sleeper `$TMP/bin/msleep <n>`. Checks become
     `pgrep -f "$TMP/bin/msleep <n>\$"` (anchored), and cleanup becomes `pkill -f "$TMP/bin/msleep"`. This covers:
     - studio_setup's 4801, 4802, 4811 and 4821;
     - the lanes detach child's `sleep 301 & sleep 301`, through `STUDIO_OVERNIGHT_DETACH_CHILD_CMD`;
     - lanes 4831, 4834 and 4835;
     - spaced-path 301, 302 and 303.
   - **`msleep`** is made by `mk_msleep` in `assert.sh` (falsifier M-7): a symlink `$TMP/bin/msleep` to
     `$(command -v sleep)`, then a check that `"$TMP/bin/msleep" 0` succeeds. macOS and GNU `sleep` ignore argv[0], so
     the process is a plain `sleep` whose argv[0] carries `$TMP`. A multi-call binary that dispatches on argv[0]
     (busybox) fails that check, and `mk_msleep` then writes `$TMP/bin/msleep` as a two-line perl script
     (`select(undef, undef, undef, $ARGV[0])`): one process whose argv (`perl $TMP/bin/msleep <n>`) still matches the
     anchored pattern, and which inherits an ignored TERM the way `sleep` does.
5. **Static guards** (`tests/harness_test.sh`). Each fails naming the file and line:
   - `test_no_unscoped_process_scans`: a line in `tests/*_test.sh` that runs `pgrep`, `pkill` or `ps -A` must contain
     `$TMP`, `msleep`, or a pid or group form (`-P`, `-p`, `-g`, `-$pid`, `-- -`), or carry a trailing
     `# scan-ok: <reason>` comment (falsifier M-3). The known exemptions: overnight `:773` (a tool name in a PATH
     list) and lanes `:2349` (`pgrep -f 'studio-gate studio-test'` filtered by `$CALLS` on the same line).
   - `test_mktemp_uses_tmpdir_template`: every `mktemp` call in `tests/*_test.sh` and `tests/state_fixtures.sh` has a
     `"${TMPDIR:-/tmp}/` template, or a `# scan-ok:` comment.
   - `test_suite_tmp_under_tmpdir` (live): with a PATH-shadowed `mktemp` that logs what it created, run
     `TESTS_ONLY=__none__ $TEST_SH tests/sync_test.sh` and `tests/state_guard_test.sh` (it sources `state_fixtures.sh`)
     with `TMPDIR=$TMP/td`. Every logged path is under `$TMP/td`.
6. **Tests:**
   - `test_env_scrub` (`harness_test.sh`) sources `assert.sh` in a child with these variables set:
     `STUDIO_STORY`, `STUDIO_RUN_DIR`, `OMEGA_AUTOPILOT`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CONFIG_DIR`, `CLAUDECODE`,
     `GIT_DIR`, `TESTS_ONLY` and `TEST_SHARD`. Only the last two survive.
   - `test_own_group_gives_group_and_int` (`harness_test.sh`): under `$TEST_SH`, `( own_group sh -c '<trap INT>' ) &`
     yields a pid that leads its own group and runs its INT trap.
   - `test_mk_msleep`: the marked sleeper runs, its argv matches `"$TMP/bin/msleep 1$"`, and a PATH whose `sleep` fails
     on an unknown argv[0] gets the perl form.
   - The existing suites, run in parallel by acceptance runs 1–3, are the coupling test: before the fix, C2–C6 made
     tests fail under concurrency.

## R3. Harness partitions (`tests/assert.sh`)

### Suite declarations

A suite declares the following before its `run_tests` call. All are optional.

| Name | Kind | Meaning |
|---|---|---|
| `TESTS_EXCLUSIVE="a b"` | variable | Load-sensitive tests. They run only in the exclusive phase, and are real-clock automatically. |
| `TESTS_REAL_CLOCK="c d"` | variable | Tests that must see every runner knob at its production value: rule-2 tests, plus one named carrier per knob (R7). |
| `TESTS_FINAL="e"` | variable | Sweep tests run last in every partition, e.g. `test_lanes_no_orphans`, which checks what the partition's other tests left behind. |
| `before_each` | function | If defined, `run_tests` calls it before each test. `TEST_NAME` holds the test's name. |
| `is_real_clock` | provided by `assert.sh` | Returns true when `$TEST_NAME` is in `TESTS_REAL_CLOCK` or `TESTS_EXCLUSIVE`. |

`assert.sh` also provides the shared helpers `own_group` and `mk_msleep` (R2) and `next_second` (R6).

### Environment

- `TEST_PHASE`:
  - unset or empty: every listed test, in listed order, as today (finals at their listed position, once);
  - `parallel`: this shard's eligible tests, then the finals;
  - `exclusive`: the exclusive tests in listed order, then the finals.
- `TEST_SHARD=k/N` (1 ≤ k ≤ N): used only with `TEST_PHASE=parallel`; unset means `1/1`. The eligible list is the
  listed tests minus exclusive and final tests. Shard k runs the j-th eligible test (1-based) when `(j−1) mod N = k−1`.
  Every eligible test therefore lands in exactly one shard by construction.
- `TESTS_ONLY` intersects with whatever the phase and shard select (as today when no phase is set).
- Empty values mean unset everywhere. Nested harness calls inside tests, such as `lib_test.sh:346`, pass
  `TEST_PHASE= TEST_SHARD= TEST_TIMING_LOG=`.

### Validation

Each of these fails loudly, the way an unknown test name does today. The harness adds one failed assertion with the
message shown, the run continues, and `run_tests` returns non-zero. With a bad `TEST_PHASE` or `TEST_SHARD` the
partition is unknown, so no test runs (the `L` row's partition is `bad`); with a bad tag list every selected test
still runs.

| Case | Failure message |
|---|---|
| a malformed `TEST_SHARD` (`0/3`, `4/3`, `x`, `3`) | `bad TEST_SHARD …` |
| `TEST_SHARD` set without `TEST_PHASE=parallel` | `TEST_SHARD needs TEST_PHASE=parallel` |
| an unknown `TEST_PHASE` | `bad TEST_PHASE …` |
| a name in any of the three lists that is not in the `run_tests` arguments | `TESTS_EXCLUSIVE names unknown test X` (and the same for the other lists) |
| a name that is both exclusive and final | `X is both exclusive and final` |

The list checks run in every phase, including unset, so a misspelt tag fails the standalone run too. The summary line
`N assertions, M failed` keeps its exact format.

### Tests (`harness_test.sh`)

Each test builds a throwaway suite under `$TMP` with 23 generated test functions, 3 exclusive tests and 1 final test, and
runs it in a child shell under `${TEST_SH:-sh}`.

- `test_shards_cover_every_test_once`: for N ∈ {1, 2, 3, 7, 19}, take the union over k of the shards plus the exclusive
  phase. Each eligible and exclusive test runs exactly once, and the final test runs in every partition. The check reads
  the `idx` of each `T` row.
- `test_no_phase_runs_all_in_order`: the run order is identical to the listed order, and nothing is added.
- `test_exclusive_phase_runs_only_tagged`.
- `test_bad_shard_and_phase_fail_loudly`.
- `test_misspelt_tag_fails_in_every_phase`.
- `test_tests_only_intersects_partition`.
- `test_before_each_sees_test_name`.
- `test_real_clock_includes_exclusive`.
- The existing `test_run_tests_unknown_name` (`lib_test.sh`) is kept, with its child call clearing the `TEST_*` variables.

## R4. Parallel runner (`tests/run_all.sh`, rewritten)

### Interface (all in the header)

| Variable | Default | Meaning |
|---|---|---|
| `TEST_JOBS` | max(1, ncpu − 2). ncpu is `getconf _NPROCESSORS_ONLN`, else `sysctl -n hw.ncpu`, else 1. On the operator's Mac that is 8 logical CPUs, so 6 jobs. | The number of concurrent jobs. `1` is serial mode. Anything other than a positive integer exits 2. |
| `TEST_SUITES` | all `tests/*_test.sh` | Space-separated suite names, with or without `_test.sh`. An unknown name exits 2. A partial run prints "partial run: not the merge gate". |
| `TEST_LOG_DIR` | a fresh `mktemp -d "${TMPDIR:-/tmp}/run_all.XXXXXX"`, resolved with `pwd -P` | Job logs, `timing.tsv` and `summary.tsv`. A directory run_all created itself is removed when the run is green, and kept (with its path printed) otherwise. A caller-given one is never removed, and is resolved with `pwd -P` too. |
| `TEST_SLOWEST` | 20 | Length of the slowest-tests list. |
| `TEST_JOB_TIMEOUT` | 7200 s | A job still running after this many seconds is killed (its whole group) and fails with `timed out after N s`. Today a hung suite hangs the gate forever. 7200 s is longer than today's whole serial gate. |
| `TEST_SH` | `sh` | The shell that runs each suite. The dash acceptance run uses it. |
| `RUN_ALL_SUITES_DIR` | the script's directory | Test-only: where the suites are found. |
| `RUN_ALL_TABLE` | the in-script table | Test-only: a file with the suite table, for the runner's own tests. |

### Suite table

The suite table is the one place for shard counts and assertion floors. It lives in `run_all.sh`:

```
# suite                    shards  floor
overnight_lanes_test       8       <floor>
overnight_test             4       <floor>
...one row per suite; heaviest first (this is also the launch order)...
```

- The initial shard counts are lanes 8 and overnight 4, and the plan re-tunes them from measured job times. The rule is
  that no job's expected time exceeds the total job time ÷ the default `TEST_JOBS`. Each shard pays the suite's
  top-level setup and builds its own fixture templates, and the plan measures that cost with
  `TESTS_ONLY=__none__ sh tests/<suite>.sh`.
- Floors are as in "Floors" above.
- A suite with no row runs as one job with floor 1. run_all prints a note naming it, so a new suite works at once.

### Parallel mode (`TEST_JOBS` > 1)

1. **Jobs.** For each suite in table order, then any suites not in the table:
   - a suite with shards N > 1 gives N jobs with `TEST_PHASE=parallel TEST_SHARD=k/N`;
   - any other suite gives one job with `TEST_PHASE=parallel`.

   Each job's environment adds `TMPDIR=$TEST_LOG_DIR/<job>/tmp` and `TEST_TIMING_LOG`. With R2.2's templates, every
   suite temp dir, and so every stub, fixture and runner path under it, lands under a directory run_all owns, and that
   directory is unique per job.
2. **Launch.** Each job is started in the background as:

   ```
   env … perl -MPOSIX -e '$SIG{INT}=$SIG{QUIT}="DEFAULT"; POSIX::setsid() or die "setsid: $!\n"; exec @ARGV or die "exec: $!\n"' \
     sh -c "$TEST_SH \"\$1\" > \"\$2\" 2>&1; echo \$? > \"\$3.tmp\" && mv \"\$3.tmp\" \"\$3\"" _ <suite> <log> <rcfile> &
   ```

   This fixes C1. The job has default INT, so the SIGINT tests work. It leads its own session and process group, so it
   can be stopped as a whole, and it has no controlling terminal, so a dash suite can never be stopped by SIGTTIN
   (falsifier I-2). The rc file is written to a temp name and renamed, so run_all never reads a created-but-empty rc
   file (falsifier M-2).
3. **Pool.** At most `TEST_JOBS` jobs are live at once. Every 0.2 s run_all checks each live job:
   - if its rc file exists, the job is done;
   - if `kill -0` fails and there is no rc file, the job died without a status;
   - finished jobs are reaped with `wait <pid>`.

   bash 3.2 and dash both lack `wait -n`, hence the poll. Every 60 s, run_all prints one line to stderr naming the jobs
   still running.
4. **Output.** When a job finishes, its block is printed whole: `=== <suite> [<partition>] <secs> s ===` followed by its
   log. Blocks never interleave.
5. **Exclusive phase.** After the pool drains, run_all looks for suites whose file has a line starting
   `TESTS_EXCLUSIVE=`. It runs each one, one at a time, with `TEST_PHASE=exclusive`, through the same launcher. Nothing
   else from this gate is running at that point. The exclusive phase runs even if the parallel phase failed, so one run
   reports everything.

### Serial mode (`TEST_JOBS=1`)

Today's behaviour: each suite runs whole (no `TEST_PHASE`, no shard) in the foreground, in name order, with output
streamed under `=== <file> ===`. The only additions are the timing log, the summary and the checks below. A terminal
Ctrl-C reaches the suite directly, as today. Serial mode needs no perl.

### Checks: a job is red when any of these holds

- Its exit status is not 0.
- Its log has no final `<N> assertions, <M> failed` line. This covers a suite that died or `exit 0`'d early.
- That line shows M > 0.
- It died without a status.
- It timed out.

### Checks: a suite is red when any of these holds

The suite-level checks look at the suite's `L` and `T` rows in the timing log, from every partition.

- **No `L` row** (falsifier M-6). A suite that never reached `run_tests` (it died in its top-level setup, or does not
  use the harness) is red with `no run_tests row`.
- **Listed count.** The `L` rows' listed counts differ across the suite's partitions.
- **Completeness, exactly once** (falsifier M-1). Let L be the listed count and P the number of the suite's `L` rows (one per partition that ran).
  Every idx in 1..L that is not a final test has exactly one `T` row across all partitions, and every final idx has
  exactly P rows (one per partition). A missing idx is `test <idx> never ran`; an extra is `test <idx> (<name>) ran <n>
  times`.
- **Floor.** The suite's assertions summed over its jobs are below its floor.

Every check is skipped, and the skip is printed, when `TESTS_ONLY` is set: a partial run is not a gate.

### Exit status

| Status | Meaning |
|---|---|
| 0 | every job and suite is green |
| 1 | any check failed |
| 2 | usage or table error (bad `TEST_JOBS`, unknown `TEST_SUITES` name, a table row naming a missing suite) |
| 130 / 143 / 129 | stopped by INT / TERM / HUP |

### Ctrl-C and TERM

run_all traps INT, TERM and HUP. Its jobs are in sessions of their own, so a terminal Ctrl-C reaches only run_all, which
forwards it. On a signal it:

1. sends the same signal to every live job's group (`kill -<SIG> -<pid>`; no `--`, which dash rejects). This is what a terminal Ctrl-C does to
   today's serial gate;
2. waits up to 10 s, polling every 0.2 s, for the groups to be gone;
3. sends `kill -KILL` to any group still alive;
4. runs `pkill -f "$TEST_LOG_DIR"` to catch processes a test moved into a group of its own (`own_group`, the detach
   child's `setsid`). Their argv carries the job's `$TMP` (R2.4), which is under `$TEST_LOG_DIR` (R2.2);
5. prints the finished jobs' summary marked `interrupted`, keeps the log dir and exits 128+N.

### Failure handling

- **No perl.** run_all exits 2 with `run_all: perl is required for parallel mode (TEST_JOBS=1 runs without it)`.
  studio-overnight already requires perl.
- **Cannot create the log dir.** Exit 2.
- **A job's rc file is unreadable.** The job is red, with the reason `no status`.

### Tests (`tests/run_all_test.sh`)

Each test drives `$TEST_SH tests/run_all.sh` with `RUN_ALL_SUITES_DIR` and `RUN_ALL_TABLE` pointing at fixture suites
under `$TMP`. The fixture suites are self-contained: they print the summary line and write their own `L` and `T` rows,
so these tests pin run_all's contract independently of `assert.sh`.

- `test_run_all_green_parallel`: exit 0, one contiguous block per job, a summary row per job.
- `test_run_all_red_suite_fails_gate`.
- `test_run_all_missing_summary_line_is_red`: the suite `exit 0`s halfway.
- `test_run_all_no_l_row_is_red`: the suite prints a green summary line but writes no `L` row.
- `test_run_all_below_floor_is_red`.
- `test_run_all_unran_test_is_red`: the suite's `L` row says 3 but only 2 `T` rows are written.
- `test_run_all_double_run_is_red`: an idx has two `T` rows.
- `test_run_all_respects_job_bound`: each fixture job takes an `mkdir` slot counter, and the recorded maximum is ≤ `TEST_JOBS`.
- `test_run_all_exclusive_runs_alone_after_pool`: exclusive jobs start after the last parallel job ends, and the counter
  never exceeds 1 while they run.
- `test_run_all_serial_mode_is_today`: `TEST_JOBS=1` gives name order and no `TEST_PHASE` in the suites' environment.
- `test_run_all_job_sees_trappable_int`: a fixture suite traps INT, sends INT to itself, and records that the trap ran.
  This is the C1 regression test.
- `test_run_all_job_has_own_session`: a fixture suite records `$PPID` and `ps -o pgid=,tty= -p $$`: the pgid equals
  `$PPID` (the job's `sh -c` wrapper, which perl made a session leader) and differs from run_all's, and the tty is `??` (macOS) or `?` (Linux), i.e. none. (macOS `ps -o sess=` prints 0, so it is not used.)
- `test_run_all_job_tmpdir_is_per_job`: two fixture jobs record `TMPDIR`; each is under the log dir, and they differ.
- `test_run_all_ctrl_c_cleans_up`: run_all is started through the setsid launcher, with fixture suites that each start
  `( own_group "$TMP/bin/msleep" 300 ) &` (a sleeper in a group of its own, as `start_bg` does, so only step 4 can reach
  it) and then sleep. INT is sent to run_all. Within 15 s, run_all has exited 130, `pgrep -f "$LOGDIR"` is empty, and
  the summary says `interrupted`.
- `test_run_all_job_timeout`: with `TEST_JOB_TIMEOUT=2` and a fixture suite sleeping 30 s, the job is red with `timed out`.
- `test_run_all_bad_jobs_value`.
- `test_run_all_unknown_suite`.

## R5. Exclusive phase membership

- **Criterion.** A test goes in `TESTS_EXCLUSIVE` when it does any of the following:
  - (a) asserts an upper bound on elapsed time;
  - (b) needs a short fixed sleep (≤ 3 s) in the code under test or a stub to still be running when the test acts, as
    in signal-in-window and lock-contention races;
  - (c) failed under load (the audit's 2× load run, the falsifier's sweeps, or any later loaded run) and passed alone;
  - (d) gives the code under test a short window it must beat: a timeout, deadline, `--seconds`, session limit or stub
    sleep of ≤ 6 s that the behaviour under test must finish inside (or must outlast), so CPU starvation can flip it
    (falsifier I-4: toolkit's `--seconds 1` tests).

  A lower-bound-only assertion ("waited at least N s") stays parallel, because load can only make it pass. A short
  sleep that R6 turns into an event wait no longer gives a window, so the test is classified on the code after R6.
- **Mechanical scan.** `tests/exclusive_scan.awk` lists, per test function, the lines that hint at (a), (b) or (d):
  - a: `date +%s` arithmetic compared with `-lt`/`-le`, or an "under N s" / "< N s" message;
  - b: `kill -INT|-TERM|-HUP|-QUIT|-s` sent by the test;
  - d: a literal `sleep 1`…`sleep 6` in a scenario, stub or shell-text command, `--seconds 1`…`6`, or a
    `*_SECONDS=`/`*_WAIT=`/`*_TIMEOUT=` value of 1…6.

  It prints `suite<TAB>test<TAB>flags<TAB>evidence-lines`. On 6f2445b it flags 85 tests (lanes 47, overnight 17,
  toolkit 11, studio_setup 4, state_pointer 3, state_move 1, overnight_runs 1, overnight_progress 1).
- **The ruling table lives in each suite**, directly above its `TESTS_EXCLUSIVE` line, one comment line per test:

  ```
  # exclusive-scan: <test> in  (<criterion>) <one-line reason>
  # exclusive-scan: <test> out (<flag>) <one-line reason, e.g. "sleep 3 became a release-file wait (R6)">
  ```

  `test_exclusive_scan_candidates_ruled` (`harness_test.sh`) runs the scan over every suite and fails when a flagged
  test has no ruling line, when a ruling names a test the suite does not list, when an `in` test is not in
  `TESTS_EXCLUSIVE`, or when an `out` test is. A test can also be ruled `in` without a scan flag (criterion (c)), and
  then needs its ruling line too. The PR reproduces the rulings as one table.
- **Seed list.** Ruled `in` by the audits and the falsifier. The plan confirms each against the code after R6:

  | Suite | Tests |
  |---|---|
  | overnight_progress | `test_progress_scale_with_past_rows` |
  | state_pointer | `test_state_story_writes_unchanged`, `test_state_milestone_without_main`, `test_state_every_write_holds_mutex`, `test_state_dead_holder_reaped_fast`, `test_state_init_local_is_auto_create` |
  | state_move | `test_state_mutex_single_acquisition`, `test_state_handoff_rechecks_target_under_mutex` |
  | overnight_runs | `test_mutex_stale_reap_lock_broken` |
  | hook | `test_inbox_hook_silent_outside_units` |
  | overnight | `test_overnight_overhead`, `test_overnight_timeout`, `test_overnight_inhibitor`, `test_overnight_claim_without_run_dir`, `test_inbox_lock_busy`, `test_overnight_sighup_while_held`, `test_overnight_sigterm`, `test_overnight_sigint`, `test_overnight_stop_beats_resume`, `test_overnight_resume_wins_at_deadline` |
  | lanes | `test_lanes_slot_wait_not_in_session_minutes`, `test_lanes_direct_merge_timeout`, `test_lanes_direct_merge_timeout_after_merge_lands`, `test_lanes_direct_merge_timeout_term_ignored`, `test_lanes_sigint`, `test_lanes_end_sessions_spaced_path`, `test_lanes_lock_race_single_vs_manifest`, `test_lanes_recheck_race_one_wins`, `test_lanes_heartbeat`, `test_lanes_setup_preflight_refuses_linked_only` (c), `test_lanes_detach_timeout_no_lock_ends_child` (c) |
  | studio_setup | `test_setup_timeout_ends_group`, `test_setup_timer_starts_after_lock`, `test_setup_timeout_kills_term_ignorer`, `test_setup_signal_stops_child_and_releases_lock` |
  | toolkit | `test_run_terminates_a_long_process`, `test_gate_three_reclaimers_never_overlap`, `test_gate_stale_reclaim_race`, `test_run_detects_script_errors` (c, d), `test_run_passes_scene_and_windowed` (c, d) |

- **Ruled by the plan.** The falsifier's static candidates, each with a stub sleep ≤ 3 s or a short window to act in:
  lanes `test_lanes_stop_file`, `test_lanes_runner_gone`, `test_lanes_per_run_lock_paths`,
  `test_lanes_two_runs_each_own_lock`, `test_lanes_gate_repair_halt`, `test_lanes_status_reaps_dead_runner`,
  `test_lanes_slot_cap_one_alternates`; overnight `test_overnight_status`, `test_overnight_stop_file`. Most are class A,
  so after R6 their window is a release file and they are expected `out`; the ruling line records it either way. Every
  other scan flag gets its ruling the same way.
- **Changing membership.** Moving a test out of the list needs evidence: 3 green parallel runs under load with the test
  in the parallel phase, or the R6 conversion that removed its window. Adding a test needs only the criterion.
- **Cost.** The exclusive phase is serial and is now the floor of the gate's wall time. The PR reports how long it takes.

## R6. Dead waits, test side

- **Event waits for class A.** Every class-A row of the wait audit converts, about 45 in lanes, 5 in overnight, 3 in
  studio_setup and 1 in hook. B and B\* rows are untouched (rule 2), and so are D rows apart from the run-dir second
  below. The biggest conversions are:
  - `test_lanes_round_trip_stop_one_of_two`: S2's 40 s session and S1's 8 s;
  - the 9 hold/stop-verb windows;
  - the 7 land-conflict `sleep 4` finishes;
  - `status_anywhere`, `origin_detach` and `finstop2`.
- **Stub support,** in both stub `claude`s:
  - a new action `waitexist PATH` waits until `PATH` exists (`-e`, since stop, hold and control files are empty), polling
    every 0.1 s with a 60 s ceiling;
  - a path token `@RUN@` in `waitfor`, `waitafter` and `waitexist` expands to `$STUDIO_RUN_DIR`, which `start_session`
    exports to every unit in both modes;
  - releases follow the existing `mark`/`waitafter` convention: the stub runs `waitexist $SCEN/release-<tag>`, and the
    test touches that file after its live-state asserts;
  - when a stub wait reaches its ceiling, it appends the path to `$CALLS/wait.timeout`, and every converted test adds
    `assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"`. A missed event fails instead of passing
    slowly. This adds assertions and removes none.
- **Ceiling rule.** If the original `sleep N` was followed by an absence or "not yet" assertion (a process gone, a file
  absent), the event wait polls for that state with a ceiling of exactly N. It returns early, but never allows more time
  than today, so no bound is loosened. Every other event wait (ordering, keeping a session live, waiting for a stop file)
  gets a ceiling of 60 s or more. The original sleep was only a margin there, and the assertions that follow judge the
  outcome.
- **Helper polls.** Ceilings stay the same, and the loop counts ticks: `SECS × 5` ticks of `sleep 0.2`.
  - lanes `wait_for` and `wait_pid_or_fail` (98 call sites): 1 s → 0.2 s;
  - overnight `bg_end`: 1 s → 0.2 s;
  - studio_setup's uncapped `gate.lock/pid` loop (`:78`) gets a 20 s ceiling;
  - the lanes `bggate` pid wait (`:290`) gets a 60 s ceiling.
- **New run-dir second.** The resume `sleep 1`s (class D, 6 sites) become `next_second` (in `assert.sh`): poll every
  0.1 s until `date +%s` changes, with a 3 s ceiling.
- **Fractional sleep.** Neither bash 3.2 nor dash has a `sleep` builtin, so both run `/bin/sleep`, which accepts decimals
  on macOS, GNU and busybox. The repo already relies on this in `overnight-runs.sh` (`sleep 0.1`) and in many tests.
  `$(( ))` is integer-only, so every converted loop counts ticks; none multiplies by a fraction.
- **Tests.** The converted tests themselves, with the same assertions plus the `wait.timeout` check.
  `test_stub_waitexist_and_run_token` (in lanes) checks `-e` on an empty file, `@RUN@` expansion and the timeout record
  at a 1 s ceiling. `test_next_second` (`harness_test.sh`) checks that the second changed and that it returned within 1.5 s.

## R7. Runner-side poll knobs (test-only, production default)

### Knob values

Each knob accepts only `1` (the default), `0.5`, `0.2` or `0.1`. These map to 1, 2, 5 and 10 ticks per second (TPS).

- **Iteration-counted loops.** A loop that counted seconds as iterations now runs `budget × TPS` ticks of
  `sleep <knob>`. The real-clock budget is never shorter, and at the default the loop is identical to today.
- **`date`-based loops** keep their `date +%s` test.
- **Any other value** is refused with one stderr line, `<script>: <KNOB> must be 1, 0.5, 0.2 or 0.1, got <v>`, and exit 2.
- **Read and validated once, at startup** (falsifier M-5), into script-local variables (`*_POLL`, `*_TPS`), before any
  subcommand runs. So a bad value is refused before a run starts, never mid-lane, and `--detach`'s strip of `STUDIO_*`
  (`studio-overnight:1353`) cannot lose the detach knob: the window reads the local copy.
- **Sourced alone.** `overnight-lanes.sh` is also sourced directly by a unit test (`test_lanes_end_sessions_spaced_path`),
  without `studio-overnight`'s startup. Its loops use `${REAP_POLL:-1}` and `${REAP_TPS:-1}`, so that path runs at the
  production value.

| Knob | Script (header where it is named) | Loops | Budget kept |
|---|---|---|---|
| `STUDIO_SETUP_POLL_SECONDS` | `studio-setup` (the "Test hook" header line) | `timed_gate` lock-take wait and run loop; `tg_stop` | run loop: the `date` deadline is unchanged; `tg_stop`: 5 s = 5×TPS ticks |
| `STUDIO_GATE_POLL_SECONDS` | `studio-gate` header | the lock wait (`until try_take`) | the waiting message stays every 60 s: `waited % (60×TPS)`. The post-signal loop (KILL at 10, stop at 15) is signal timing and stays as it is |
| `STUDIO_OVERNIGHT_REAP_POLL_SECONDS` | `studio-overnight` help's test-hook list; a pointer comment in `overnight-lanes.sh` | `end_session` (GRACE), `unit_reap` (max(GRACE, 20)), `lanes_end_sessions` (GRACE) | GRACE×TPS ticks, and max(GRACE, 20)×TPS for `unit_reap` |
| `STUDIO_OVERNIGHT_DETACH_POLL_SECONDS` | `studio-overnight` help's test-hook list | the detach status window | 10 s = 10×TPS ticks. The 3-iteration kill loop after the window stays as it is |

### Known effect of a sub-second knob

With a sub-second value, `timed_gate`'s whole-second `date` deadline can fire up to about 1 s earlier in real time than
with 1 s polls. This is one more reason timing tests never set the knobs.

### How suites apply them

The overnight, lanes and studio_setup suites, and toolkit if it gains non-real-clock gate tests, define:

```sh
before_each() {
  unset STUDIO_SETUP_POLL_SECONDS STUDIO_GATE_POLL_SECONDS \
        STUDIO_OVERNIGHT_REAP_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
  is_real_clock && return 0
  STUDIO_SETUP_POLL_SECONDS=0.2; STUDIO_GATE_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_REAP_POLL_SECONDS=0.2; STUDIO_OVERNIGHT_DETACH_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_POLL_SECONDS=1   # land-lock and hold polls: 5 s -> 1 s (existing knob, whole seconds)
  export STUDIO_SETUP_POLL_SECONDS STUDIO_GATE_POLL_SECONDS STUDIO_OVERNIGHT_REAP_POLL_SECONDS \
         STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
}
```

- A test that sets its own `STUDIO_OVERNIGHT_POLL_SECONDS` (the hold and waiting-chain tests) still wins.
- A test that later unsets it just runs the rest of its body at the production value.
- A test that asserts on cadence must be in `TESTS_REAL_CLOCK`.

### Production-value carriers

These are the tests in `TESTS_REAL_CLOCK` or `TESTS_EXCLUSIVE` that run each knob unset:

| Knob | Carriers |
|---|---|
| setup | `test_setup_timeout_kills_term_ignorer` (the full `tg_stop` 5 s), `test_setup_timer_starts_after_lock` |
| gate | `test_gate_no_overlap`, `test_gate_waiting_message` |
| reap | `test_overnight_kill_after_grace` (`end_session`), `test_lanes_end_sessions_spaced_path` (`lanes_end_sessions`), `test_lanes_left_gate_reaped` (`unit_reap`, added to `TESTS_REAL_CLOCK` for this) |
| detach | `test_lanes_detach_timeout_lock_held_points_at_status`, `test_lanes_detach_timeout_no_lock_ends_child` |
| `STUDIO_OVERNIGHT_POLL_SECONDS` = 5 | land lock: `test_lanes_land_conflict_one_repair` (added to `TESTS_REAL_CLOCK`); `hold_wait`: the plan adds the cheapest hold test that does not set the knob |

The rest of the rule-2 tests also go in `TESTS_REAL_CLOCK`. The plan confirms the list and makes it complete:
`test_overnight_sighup`, `test_inbox_lock_released_on_signal`, `test_lanes_sync_repair_stops`,
`test_lanes_timed_out_outcome`, `test_lanes_slot_cap_two_across_runs`, `test_lanes_gate_never_overlaps`,
`test_gate_signal_waits_for_child_then_releases`, `test_gate_signal_reaches_the_grandchild`, `test_mutex_reap_race`.

### New tests

- `test_<knob>_keeps_budget`, one per knob. Each runs the knob at 0.2 and makes a lower-bound-only assertion, so it can
  run in parallel:
  - setup: a TERM-ignoring command is not KILLed before 5 s;
  - reap: a TERM-ignoring session is not KILLed before GRACE;
  - detach: with `STUDIO_OVERNIGHT_DETACH_STATUS_CMD` set to a command that appends one line to a counter file and
    fails, and `STUDIO_OVERNIGHT_DETACH_CHILD_CMD="$TMP/bin/msleep 301"` (a child that never locks), the timeout
    message comes no sooner than 10 s, and the counter holds exactly 50 lines (10 s × 5 ticks). The window counts
    ticks, so 50 is exact under any load, and it proves the knob survived `--detach`'s `STUDIO_*` strip (M-5);
  - gate: the waiting message is not repeated within 60 s, checked with a 3 s hold.
- `test_<knob>_rejects_bad_value`, one per knob; the overnight ones assert the refusal comes before any run directory
  or lock exists.
- `test_knobs_named_in_headers` (`harness_test.sh`): each knob name appears in its script's header or help block.

## R8. Template fixtures

- **`lanes_fixture NAME MODE [ID:DEPS…]`.**
  - **Key.** The key is `cksum` of `MODE|<story args>|$LANES_CONFIG|$LANES_CELLS|$LANES_PROGRESS|$LANES_MAIN_MOVES|$LANES_TASKS|$FAKE`.
    NAME is not part of the key: per the audit, only `.git/config`'s remote URL holds it.
  - **First use of a key.** The existing body builds the fixture once, as `$TMP/tpl/l-<key>/p` with the bare repo at
    `…/p.git`. The marker `…/ok` is written only after every step succeeded.
  - **Every call.** `rm -rf "$TMP/NAME" "$TMP/NAME.git"` first (falsifier I-6: `cp -Rp` onto an existing directory
    nests the copy inside it), then `cp -Rp` the work tree and the bare repo to `$TMP/NAME` and `$TMP/NAME.git`, then run
    `git -C "$TMP/NAME" remote set-url origin "$TMP/NAME.git"`. The per-test dirs (`calls-NAME`, `gh-NAME`, `scen-NAME`,
    `wts-NAME`) are still created fresh, and the existing tail (exports, `unset LANES_*`) is unchanged.
- **`overnight_test.sh` `fixture NAME [CONFIG_JSON]`.** The same scheme, with the key `cksum` of the config JSON. The
  empty key covers its 157 calls with no config. The fixture removes `$TMP/NAME` and `$TMP/NAME.git` before it builds
  or copies, in both modes, so a reused name (`fixture hcf` twice, `:1085-1086`) always gets a fresh project with the
  second call's config. Today the second call re-inits over the first project and keeps going after a failed
  `git remote add`; the test only reads the config the second call wrote, which a fresh project also has. Its `$CALLS`
  and scenario handling is unchanged.
- **Failure.** A failed build removes the template dir and fails the test with today's "… setup failed" message. Without
  the `ok` marker a template is never reused, and the next call rebuilds it.
- **Off switch.** `LANES_FIXTURE_TEMPLATES` and `OVERNIGHT_FIXTURE_TEMPLATES` are suite-local and named in each suite's
  header. Default 1; 0 builds fresh as today. Only the equivalence tests use 0.
- **Tests:**
  - `test_lanes_fixture_copy_equals_build` covers three shapes: `A:-` integration; `A:- B:A`; and direct with
    `LANES_TASKS=2` and a config. For each it compares a copy against a fresh build:
    - `diff -r` of the two work trees, excluding `.git` but including git-ignored files such as `.studio/STATE.md`
      (falsifier M-4), after rewriting each tree's own NAME to a placeholder;
    - `git log --all --format='%T %s'`, so tree hashes are equal;
    - `git status --porcelain` is empty;
    - `git rev-parse origin/run/demo` equals `HEAD`;
    - the remote URL is `$TMP/NAME.git`;
    - `grep -rF "$TMP/tpl"` finds nothing in the copy.
  - `test_overnight_fixture_copy_equals_build`: the same checks, with and without config, plus a same-name double call
    (`fixture X '{"a":1}'` then `fixture X '{"b":2}'`): the second copy has the second config and no nested `X/X`.
  - `test_fixture_template_failed_build_not_reused`: a PATH-shadowed `git` fails `push` once.
- **Before rollout,** the plan greps both suites for `-nt`, `-newer` and sha comparisons across two fixtures. Copies
  share commit shas, so none may depend on fresh ones.

## R9. `tests/run_affected.sh` (in-progress checks only)

- **Usage:** `sh tests/run_affected.sh [--base REF] [--list]`.
  - REF defaults to `origin/main`. The script does not fetch, and it prints the base sha it used.
  - The changed files are `git diff --name-only $(git merge-base REF HEAD)` (committed, staged and unstaged, deletions
    included) plus `git ls-files --others --exclude-standard`.
  - `--list` prints `suite<TAB>reason` lines and exits 0. With no `--list`, it prints the banner
    `run_affected: in-progress check only — the merge gate is sh tests/run_all.sh` to stderr, then runs
    `TEST_SUITES="…" sh tests/run_all.sh` and exits with its status.
- **Mapping,** first match wins:
  1. `tests/assert.sh`, `tests/run_all.sh` and `lib/**` map to **all suites**.
  2. `tests/<x>_test.sh` maps to itself; `tests/run_affected.sh` maps to `run_affected_test`; `tests/exclusive_scan.awk`
     maps to `harness_test`.
  3. `docs/**` maps to the suites whose text names the file's path or its directory, and otherwise to nothing. It
     prints `no suite reads <path>`.
  4. Any other file: take the reverse-reference closure, which is a fixed point over the code files (`tests/`,
     `studios/*/bin|hooks`, `shared/*/bin|hooks`, `lib/`, `integrations/*/bin`, root `*.sh`). A file joins the closure
     when it mentions a member by repo-relative path or by basename. A generic basename (`SKILL.md`, `README.md`,
     `hooks.json`, `plugin.json`, `config.json`, `run.sh`) matches on its last two path components instead. The
     affected suites are the suites in the closure. If there are none, the file is unknown and maps to **all suites**.
  5. A missing REF, or a failed merge-base, exits 2 with `run_affected: base <REF> not found — git fetch, or pass --base`.
     No changes prints `no changes against <REF>` and exits 0.
- **Tests (`tests/run_affected_test.sh`).** They use a fixture git repo under `$TMP` with a copied `run_affected.sh`, a
  mini layout (`lib/common.sh`, `tests/assert.sh`, `tests/run_all.sh`, `tests/a_test.sh`, `tests/b_test.sh`, a
  `bin/tool` that sources `bin/lib.sh`, `docs/x.md`, `docs/y.md` named by `b_test`, and `unknown.txt`), and `--list`:
  - `test_affected_suite_change_maps_to_itself`;
  - `test_affected_shared_files_map_to_all` (`assert.sh`, `run_all.sh`, `lib/common.sh`);
  - `test_affected_sourced_lib_maps_through_closure` (`bin/lib.sh` → `bin/tool` → `a_test`);
  - `test_affected_docs_map_to_readers_or_none`;
  - `test_affected_unknown_maps_to_all`;
  - `test_affected_deleted_and_untracked_files`;
  - `test_affected_missing_base_exits_2`;
  - `test_affected_no_changes`.

## Files

- `tests/assert.sh`: the env scrub (R2), the helpers `own_group`, `mk_msleep` and `next_second`, and in `run_tests` the
  partitions, validation, `before_each`, `TEST_NAME`, `is_real_clock` and the timing log (R1, R3).
- `tests/run_all.sh`: rewritten (R4), with the suite table.
- `tests/run_affected.sh`: new (R9).
- `tests/exclusive_scan.awk`: new (R5).
- `tests/harness_test.sh`: new suite for R1, R2's guards and helpers, R3, R5's ruling check, R6's `next_second` and R7's
  header check.
- `tests/run_all_test.sh`: new suite for R4.
- `tests/run_affected_test.sh`: new suite for R9.
  The three new suites generate their fixtures under `$TMP`, so there are no new fixture files.
- `tests/lib_test.sh`: the nested `run_tests` call clears the `TEST_*` variables; its `mktemp` template.
- `tests/overnight_lanes_test.sh`:
  - the `$TMP/bin/studio-overnight` runner link and `test_lanes_runner_argv_names_tmp`;
  - C2, C3, C5 and C6; `own_group` at `:1082`/`:1103`; the stub `mktemp` templates;
  - the deterministic peers loop;
  - tags with their ruling lines;
  - `before_each`;
  - stub `waitexist`/`@RUN@`/`wait.timeout`;
  - class-A conversions, helper ticks and `next_second`;
  - the template `lanes_fixture`;
  - `test_stub_waitexist_and_run_token` and the R7 lanes tests.
- `tests/overnight_test.sh`: the runner link, `own_group` in `start_bg`, tags with ruling lines, `before_each`, stub
  support, class-A conversions, `bg_end` ticks, the template `fixture` (with the rm-first rule) and the R7 reap tests.
- `tests/studio_setup_test.sh`: C4 via `msleep`, tags with ruling lines, `before_each`, class-A conversions, the `:78`
  ceiling and the R7 setup tests.
- `tests/toolkit_test.sh`: tags with ruling lines and the R7 gate tests.
- `tests/hook_test.sh`: tags, and the class-A conversion (kill the writer after `t1`).
- `tests/state_pointer_test.sh`, `tests/state_move_test.sh` (also `own_group` at `:511`), `tests/overnight_runs_test.sh`,
  `tests/overnight_progress_test.sh`: tags with ruling lines.
- `tests/state_fixtures.sh` and every other suite that calls `mktemp`: the `${TMPDIR:-/tmp}` template.
- `studios/game-dev/bin/studio-setup`, `studio-gate`, `studio-overnight`, `overnight-lanes.sh`: the R7 knobs only.
- `README.md` (Tests section): parallel default, `TEST_JOBS`, `TEST_JOBS=1`, `run_affected.sh` (not a gate), and the tags
  and ruling lines for suite authors.
- `docs/game-dev/PROGRESS.md`: the entry, with the A/B numbers.

## Every new knob

| Knob | Where named | Default (= today) | Production-value coverage |
|---|---|---|---|
| `TEST_TIMING_LOG` | `assert.sh` header | unset: no log | every standalone run |
| `TEST_PHASE` | `assert.sh` header | unset: all tests, listed order | every standalone run; `test_no_phase_runs_all_in_order` |
| `TEST_SHARD` | `assert.sh` header | unset: `1/1` | `test_shards_cover_every_test_once` (N=1) |
| `TESTS_EXCLUSIVE`, `TESTS_REAL_CLOCK`, `TESTS_FINAL`, `before_each` | `assert.sh` header | none | standalone runs ignore the partitions |
| `TEST_JOBS` | `run_all.sh` header | ncpu − 2, min 1 (`1` = today's serial gate) | `test_run_all_serial_mode_is_today`; acceptance run 4 |
| `TEST_SUITES`, `TEST_LOG_DIR`, `TEST_SLOWEST`, `TEST_JOB_TIMEOUT`, `TEST_SH` | `run_all.sh` header | all suites; temp dir; 20; 7200 s; `sh` | the default gate run |
| `RUN_ALL_SUITES_DIR`, `RUN_ALL_TABLE` | `run_all.sh` header (test-only) | the script's dir; the in-script table | the default gate run |
| `--base`, `--list` | `run_affected.sh` header | `origin/main`; run | R9 tests |
| `STUDIO_SETUP_POLL_SECONDS` | `studio-setup` header | 1 | R7 carriers |
| `STUDIO_GATE_POLL_SECONDS` | `studio-gate` header | 1 | R7 carriers |
| `STUDIO_OVERNIGHT_REAP_POLL_SECONDS` | `studio-overnight` help, `overnight-lanes.sh` comment | 1 | R7 carriers |
| `STUDIO_OVERNIGHT_DETACH_POLL_SECONDS` | `studio-overnight` help | 1 | R7 carriers |
| `LANES_FIXTURE_TEMPLATES`, `OVERNIGHT_FIXTURE_TEMPLATES` | suite headers | 1 (templates on); 0 = fresh build as today | the equivalence tests build fresh |

The existing `STUDIO_OVERNIGHT_POLL_SECONDS` is newly set to 1 by `before_each` for non-real-clock tests. Its default of
5 keeps its R7 carriers.

## Acceptance and verification

1. **Floors.** run_all's table holds every suite's `origin/main` count (provisional until the A/B run, then A's counts).
2. **Three consecutive green full gates.** `sh tests/run_all.sh` at the default `TEST_JOBS`, with no code change between
   runs. Run 2 runs under `yes > /dev/null` × N, with N = half the logical CPUs (4 on the operator's Mac), started
   before the gate and killed after it. Any red resets the count and is root-caused (systematic debugging). It is never
   fixed by widening a threshold or retrying. If an exclusive-phase test fails only under the external load, the same
   test is run under the same load on `origin/main`'s serial gate. If it fails there too, the operator decides.
3. **Assertion counts.** Each suite's count is ≥ its floor. run_all's floor check enforces this on every run, and the
   PR shows the before/after table from the A/B pair.
4. **Serial mode.** `TEST_JOBS=1 sh tests/run_all.sh` once, green. This proves the standalone path, with every test in
   listed order and the fast knobs on. It also gives the PR the "serial after" time, which shows the non-parallel saving.
5. **dash.** `TEST_SH=dash sh tests/run_all.sh` once, the whole gate. It must be green, except for a failure that also
   happens on `origin/main` under dash (checked by running the same tests with `TESTS_ONLY` under
   `dash tests/<suite>.sh` in an export of 6f2445b). Each such pre-existing failure is listed in the PR by suite, test
   and message, and gets a follow-up GitHub issue; none is hidden, skipped or tagged away. The four known ones
   (state_move, overnight and two lanes `set -m` sites) are fixed by `own_group` in this story.
6. **Ctrl-C by hand, in a real terminal.** Start the full gate and press Ctrl-C after 2 minutes. It must return within
   15 s with exit 130, and both `pgrep -f <log dir>` and `pgrep -f "$PWD/studios/"` must be empty (no suite process and
   no product script started from this checkout survives).
7. **No production behaviour change.** `git diff origin/main -- studios shared lib '*.sh'` touches only knob reads,
   validation and tick math. Each default is today's literal, which the reviewer checks line by line, and the R7
   carriers pass at production values.
8. **A/B measurement,** as in "Measurement protocol", after 2–6.
9. **The PR reports:**
   - A vs B wall time, in total and per suite;
   - the exclusive phase's time;
   - the serial-after time;
   - the assertion table, with the lanes peers-loop change justified line by line;
   - the R5 ruling table;
   - the final shard counts;
   - the dash result and any follow-up issues.

## Implementation order

1. R1, R3 and the R2 helpers in `assert.sh` (the harness API every suite codes against), with `harness_test.sh`.
2. R4 runner with `run_all_test.sh`; R7 knobs in the four production scripts; R9 `run_affected.sh`. These do not depend
   on each other or on step 1's code, only on its documented interface.
3. Per suite: R2 hermetic fixes, R6 waits, R8 templates, `before_each`, R5 tags and rulings.
4. R2/R5 static guards in `harness_test.sh` (green only once step 3 is in).
5. Shard tuning, floors, the acceptance runs, the A/B pair, and the README and PROGRESS updates.

A parallel gate without steps 1–3 is red on every run (C1 to C3), so the parallel default only becomes the merge gate
once step 3 is integrated.

## Risks

- **Only 4 physical cores.** `getconf` reports 8 logical CPUs, so the default of 6 jobs oversubscribes the physical cores
  when suites are CPU-bound (git, fork). That caps the speedup near 4×, and timing tests under load are why the
  exclusive phase exists. `TEST_JOBS` is the override. See Falsify F4.
- **Hidden order dependence.** Sharding reorders tests. A test that relied on an earlier test's leftovers fails loudly in
  its shard and is fixed in the test. The silent case, a sweep that passes vacuously, is handled by `TESTS_FINAL`. The
  falsifier ran all 539 tests of the 25 smaller suites alone, and the exclusive-phase sets of lanes and overnight alone,
  with no order failure.
- **The orphan sweep narrows to `$TMP`.** It is complete only because every runner, lane and detached child now carries
  `$TMP` through the runner link; `test_lanes_runner_argv_names_tmp` fails if that ever stops being true.
- **Two gates on one machine.** For example, the operator's gate next to an agent's in another worktree. The other gate's
  parallel phase loads this gate's exclusive phase. This is not solved: lower `TEST_JOBS` on a shared machine.
- **The exclusive phase is serial.** Its length is now the floor of the wall time. Membership follows R5's criterion,
  the scan and its rulings.
- **Fast knobs could hide a bug that only shows at 1 s cadence.** The carriers run every knobbed loop at its production
  value.
- **Shared commit shas across template copies.** No test may depend on fresh shas. The plan greps for this (R8).
- **dash.** Suites now avoid `set -m` (`own_group`), and product scripts always run under `sh`. A dash failure found by
  acceptance 5 that also fails on `origin/main` is pre-existing; it is reported and gets a follow-up issue.
- **`TMPDIR` per job.** A production tool that ignores `TMPDIR` (`studio-adopt:19`'s bare `mktemp -d`, or a hard-coded
  `/tmp`) escapes the per-job cleanup but stays correct.

## Rejected alternatives

- **Widening load-sensitive thresholds.** This violates rule 1 and hides real regressions. Ruling 1 isolates those tests
  instead.
- **Lower global concurrency** (for example 2 jobs) to dodge load. It still is not safe for the tight thresholds, and it
  throws away most of the speedup.
- **Merging, dropping or skipping slow tests.** This violates rule 1.
- **`set -m` per job.** dash without a tty refuses job control, leaving SIGINT ignored (probe).
- **A perl `setpgrp` launcher.** With a terminal, a dash suite that runs `set -m` in a background process group is
  stopped by SIGTTIN for ever (falsifier I-2). `POSIX::setsid` gives the job no controlling terminal, so this cannot
  happen, and it has precedent in `studio-overnight --detach`.
- **Matching the runner by `$MFP` or `$P` in argv.** `MFP` is relative and `$P` is not in the runner's argv (C-1). The
  runner link puts `$TMP` there without touching production code.
- **Assertion floor = the minimum over several baselines** (the falsifier's other I-3 option). It tolerates a varying
  count instead of removing the variation; the fixed-count loop removes it.
- **Parallel suites without sharding.** The lanes suite alone sets the wall time (about 7100 s under 2× load in the audit).
- **One test per job (work stealing) or timing-weighted shard packing.** Both pay the suite setup per test or make shard
  assignment non-deterministic. Round-robin by index is deterministic, complete by construction, and easy to reproduce.
  Tuning happens through the shard counts.
- **Rewriting `timed_gate` to be event-driven** (an audit option). It changes a production code path. Ruling 2 chose
  knobs that default to today.
- **`xargs -P` or GNU parallel as the pool.** Neither gives per-job sessions with SIGINT reset, block output and floor
  checks under plain POSIX sh, and GNU parallel is not installed by default.
- **Event waits for the B\* sleeps** (signal and lock-race windows). Rule 2 keeps them on real clocks.
- **Templates for `state_*`'s `proj`.** About 14 s saved is not worth the extra code.

## Not doing

- `tests/probes/`, `tests/pressure/` and `integrations/multica/tests/run.sh`, which are not part of this gate.
- CI configuration.
- Fixing a dash failure in production code that `origin/main` already has: it is reported with a follow-up issue
  (acceptance 5).
- A machine-wide lock between concurrent gates.

## Falsify

Five claims that would sink the design if false, each with its cheapest check:

- **F1. The setsid launcher gives every job a default SIGINT, its own session and group, and no terminal,** under macOS
  `/bin/sh` and dash, with and without a tty, so the SIGINT tests pass in parallel. *Check:* `falsify/ttys-probe.sh`
  (dash, with a tty: never stopped, rc 0) and `plan-probe/setsid-setm.sh` (bash: a `set -m` inside still gives its job a
  group and a trappable INT). The plan re-runs `test_state_mutex_single_acquisition`, `test_overnight_sigint` and
  `test_lanes_sigint` through run_all under both shells once `own_group` is in.
- **F2. Apart from the `TESTS_FINAL` sweeps, no test depends on state left by an earlier test,** so a shard can run any
  subset alone. *Checked by the falsifier:* all 539 tests of the 25 smaller suites alone (only 3 load failures), and
  the lanes and overnight exclusive sets alone (49 and 30 assertions, 0 failed). Lanes and overnight shards are covered
  by acceptance runs 1–3.
- **F3. Every load-sensitive assertion is covered by R5,** so the parallel phase is green under load. *Check:* the scan
  and its rulings (R5), the observed failures in the seed list, then, before the acceptance runs, the parallel phase of
  the suites that hold timing asserts twice at `TEST_JOBS=6` with `yes` × 4. Any failure outside the list falsifies the
  claim and adds the test by criterion (c).
- **F4. The gate is mostly waiting or single-threaded, so 6 jobs on 4 physical cores cut wall time by about 3× or more.**
  *Check:* `/usr/bin/time -p` on a 20-test `TESTS_ONLY` slice of lanes and one of overnight, on an idle machine. If
  (user + sys) / real is close to 1 or above, the work is CPU-bound and the speedup is capped by cores. The plan would
  then lean on R6–R8 and set the shard counts accordingly.
- **F5. A template copy is equivalent to a fresh build for every key, including a reused name.** *Check:* the
  equivalence tests (R8), with `diff -r` over the work trees and the same-name double call; then grep both suites for
  `-nt`, `-newer` and sha comparisons across fixtures.

## Falsifier findings (2026-10-06) and where each is resolved

| # | Finding | Resolution |
|---|---|---|
| C-1 | The runner's argv holds a relative `$MFP`, not `$TMP`; `pgrep -f "$TMP"` alone was blind to runners and lanes | R2.4: `$TMP/bin/studio-overnight` runner link in lanes and overnight; `test_lanes_runner_argv_names_tmp`; re-check of runner-path assertions |
| I-1 | macOS `mktemp` ignores `TMPDIR` | R2.2: explicit `${TMPDIR:-/tmp}` templates everywhere; static and live guards (R2.5); Ctrl-C test uses an `own_group` sleeper |
| I-2 | The `setpgrp` launcher hangs dash with a tty; dash fails SIGINT tests without one | R4 launch: `POSIX::setsid`; R2.3: `own_group` replaces test-side `set -m` |
| I-3 | Lanes assertion count is timing-dependent | "Floors": the peers loop asserts a fixed 8 + 1 |
| I-4 | Seed list incomplete; criteria missed short windows | R5: criterion (d), the scan, ruling lines with a guard test, 4 observed failures added, static candidates listed for ruling |
| I-5 | The baseline was not idle | "Measurement protocol": the old numbers are void; an A/B pair on an idle machine at the end |
| I-6 | A reused fixture name breaks copy equivalence | R8: rm-first in both modes; the double-call case in the equivalence test |
| M-1 | Completeness counted distinct idx | R4: exactly one row per non-final idx, P rows per final |
| M-2 | rc file read between create and write | R4 launch: write `rc.tmp`, then `mv` |
| M-3 | Static guard false positives | R2.5: `-g` allowed; `# scan-ok:` exemption |
| M-4 | Equivalence missed ignored files | R8: `diff -r` of the work trees |
| M-5 | `--detach` strips `STUDIO_*` before the window | R7: knobs read and validated once at startup into local variables |
| M-6 | A suite with no `L` row was not red | R4: `no run_tests row` |
| M-7 | `msleep` symlink breaks under busybox | R2.4: `mk_msleep` checks the link and falls back to a perl sleeper |
