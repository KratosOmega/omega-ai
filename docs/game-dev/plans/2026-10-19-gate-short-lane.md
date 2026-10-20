# Gate Short Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A short check no longer waits behind a whole-suite `studio-test`: one short slot runs beside a shareable suite, `studio-test` passes the project's engine args (`--fixed-fps 60`), and every gated run records its wait and lane.

**Architecture:**
- **The classifier** is a sourced sibling, `bin/gate-class.sh`. It holds the argv whitelist, the config reader (with the run fallback, D15) and the load gate.
- **The records** live in `bin/gate-times.sh`: the 8-field row, plus 14-day retention under the reclaim mutex.
- **studio-gate** gains a second lane dir (`gate.short/`), exclusive-waiter entries (`gate.wantx/`) and one admission function evaluated under the existing mutex. The slot has a 5-min cap that re-runs the command in the main lane, a demote hand-off, and a leak scrub before release.
- **The Godot adapter** gains engine args (`test.sh`), per-worktree `user://` (`isolate.sh`), and an import demote. A PreToolUse hook refuses commits carrying the lanes lines.
- **Skill text** gets the new planning rule, and the autopilot merges the three keys into each run.

**Tech Stack:**
- POSIX sh: macOS `/bin/sh` is bash 3.2, and dash is the portability pass. Also awk and sed. No `local`, no arrays, no GNU-only flags.
- python3 is used only by the measurement probe and the autopilot one-liner.
- Suites are plain-sh `tests/*_test.sh` on `tests/assert.sh`. `TESTS_ONLY="a b"` picks tests.

**Spec:** `docs/game-dev/specs/2026-10-19-gate-short-lane.md`. It covers R1–R7, U1–U8, O1–O16, D1–D15 and acceptance §13.1–7.

**Base and story.** Story #71 (GitHub issue; omega-ai has no Jira). Branch `issue-71-gate-short-lane`, off `origin/main` 18fd2e0. Line numbers are as of 137c784. Relocate each one with its `grep -n` anchor before editing.

## Global Constraints

- **POSIX sh everywhere** (spec §12). It must run under macOS `/bin/sh` (bash 3.2) and dash.
  - No `local`, arrays or `BASHPID`. Function variables carry a per-function prefix (`_ta_`, `_ga_`, `_is_` …).
  - Wrap `stat`, `sysctl` and `/proc` reads.
  - awk must run under macOS awk (one-true-awk) and gawk. So no `{n}` intervals in awk regexes: spell them out.
- **New files in `bin/`, `engines/*/` and `hooks/` are executable and parse under `sh -n`** (`tests/studio_test.sh:108-118` `test_bin_syntax`). `lib/common.sh:202` `install_entries` ships every child of `bin/`, so the sourced siblings ship with no installer change.
- **A5: without the keys, behaviour is today's.** With no config keys the argv and the observable behaviour are byte-identical, and `gate.lock/` gains only the `class`, `kind` and `wt` files (spec §7/§10 supersede "files unchanged"). The other exceptions are the appended `gate.times` fields and the new `gate.wantx/` entries, which are invisible and git-excluded.
- **Spec errata:** see the "Errata (implementation)" note at the end of spec §13 (slot lane label, same-worktree GUT, `_gut_goes_main` names, scrub skips node checks).
- **The config keys, verbatim:**
  - `"test_engine_args": "--fixed-fps 60"`
  - `"user_dir": "per-worktree"`
  - `"gate_short_lane": "on"`

  Each is a flat string, read with `studio-dispatch`'s `field()` sed, at `git rev-parse --show-toplevel` (else `pwd -P`). When that file lacks the key, it is read from `$STUDIO_START_DIR/.studio/config.json` (D15).
- **Exit codes:**
  - A bad `test_engine_args` exits **1**, never 2.
  - A short-cap kill or a demotion never exits 124 unless the run cap binds (`STUDIO_GATE_MINUTES` ≤ 5).
  - A leak with a passing command exits **1**.
- **Exact copy** (spec §5, §7, §8, §10). Every quoted message in a task is copy: use it byte for byte.
- **Test seams.** Each defaults to production and is named in its script's header:
  - `STUDIO_GATE_SHORT_SECONDS` (default 300) in studio-gate;
  - `STUDIO_GATE_LOADAVG` and `STUDIO_GATE_PHYS_CORES` in gate-class.sh;
  - `STUDIO_GODOT_USER_ROOT` in isolate.sh.

  Each gets a production-default carrier test.
- **Files #70 owns: do not touch.**
  - studio-overnight `detach_start` (~1600-1690), the `start --detach`/preflight call site (~1715-1735), the `setup_preflight` env-token read (~1868-1885), the usage env block (~470-512) and `preflight()` (563+).
  - overnight-lanes.sh `lanes_start` (~2071-2100), `mf_check` (~164-300) and `mf_conflicts`.
  - `overnight-ids.sh`.
  - tests/overnight_lanes_test.sh: the detach tests (~2354-2500) and the setup-checked tests (~4460-4560).

  The only studio-overnight change is `gate_line` (:1131-1141).
- **Never real Godot, never phoenix in a test.** Never write in `~/GameDev/proj/phoenix`. Every suite unsets `STUDIO_START_DIR STUDIO_GATE_HELD STUDIO_GATE_LANE STUDIO_GATE_DEMOTE STUDIO_UNIT_TAG STUDIO_GATE_MINUTES STUDIO_GATE_SECONDS` at its top. A unit session's env must not turn the lane on in a suite.
- **Harness rules** (tests/assert.sh, README "Tests"):
  - use `mk_tmp`/`rm_tmp`;
  - scope `pgrep`/`pkill`/`ps` scans to `$TMP`;
  - a test that bounds elapsed time or races a window goes in `TESTS_EXCLUSIVE`, and every scan-flagged test gets a `# exclusive-scan: <test> in|out (<code>) <reason>` ruling (harness_test `test_exclusive_scan_candidates_ruled`);
  - event waits (poll for a file or mark, bounded at about 30 s) instead of sleeps wherever an order is asserted.
- **Test-running rule (every task).**
  - Run suites with cwd in a scratch dir outside every git work tree, and `TMPDIR` set in the same command to an existing dir. Never `rm -rf` outside that scratch.
  - A task runs only its own suites, never `tests/run_all.sh`.
  - Create this runner once per agent at `<your scratchpad>/71-suites/run.sh`:

    ```sh
    #!/bin/sh
    # run.sh SUITE [TEST…] — one suite from this scratch dir, TESTS_ONLY=TEST…;
    # run.sh --args SCRIPT [ARG…] — a script with its own args.
    S="$(cd "$(dirname "$0")" && pwd -P)" || exit 2
    mkdir -p "$S/tmp" && [ -d "$S/tmp" ] || { echo "run.sh: no TMPDIR" >&2; exit 2; }
    if git -C "$S" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "run.sh: refused: $S is inside a git work tree" >&2; exit 2
    fi
    cd "$S" || exit 2
    if [ "${1:-}" = --args ]; then shift; _s="$1"; shift; TMPDIR="$S/tmp" exec sh "$_s" "$@"; fi
    _s="$1"; shift
    TMPDIR="$S/tmp" TESTS_ONLY="$*" exec sh "$_s"
    ```

    Below, `<R>` is that runner and `<W>` is your worktree.
- **Heavy suites.** These run only under `/Users/xinli/GameDev/proj/omega-ai/.git/heavy-suite.lock`:
  - `tests/overnight_test.sh` and `tests/overnight_lanes_test.sh` as whole suites;
  - `tests/run_all.sh`.

  To take the lock: `mkdir` it, then write `owner: #71 <task> (omega-ai)`, `since: <UTC>`, `what: <suite>` into `owner`. To release it: `rm` the owner file, then `rmdir` the lock. If the mkdir fails, never poll and never break it: hand back "blocked on heavy-suite.lock (owner: …)". `TESTS_ONLY` runs of named tests are not heavy.
- **Commits.** One commit per task, subject `feat(T<n>): …` / `test(T<n>): …` / `docs(T<n>): …`, ending with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Paths with spaces.** On macOS the data root is `~/Library/Application Support`, and worktree paths can hold spaces too. The `wt` comparison, the exclude line, the sweep's `rm -rf` and the hook's `cd` target must all quote. Tests:
   - T8 `test_isolate_sweep_paths_with_spaces` (`STUDIO_GODOT_USER_ROOT="$TMP/App Support"`);
   - T7 `test_lanes_space_in_worktree_path` (a linked worktree named `w b`).
2. **Minified or oddly spaced `.studio/config.json`.** For example `{"engine":"godot4","gate_short_lane":"on"}` on one line, or `"gate_short_lane" : "on"`. The flat sed must still read it. Tests:
   - T1 `test_classify_minified_config`;
   - T3 `test_test_engine_args_odd_spacing` (multiple blanks inside the value are fine; a tab is refused).
3. **Stale lane env outside a gate.** A shell that inherited `STUDIO_GATE_LANE=short` and `STUDIO_GATE_DEMOTE` must never make `test.sh` skip its run and report green. test.sh demotes only when `STUDIO_GATE_DEMOTE` ends in `.$STUDIO_GATE_HELD` and that pid is alive. A demote exits 1, so a lost hand-off is red, never green. Test: T9 `test_test_stale_demote_env_imports`.
4. **A mixed project:** one worktree lane-on and another lane-off, such as a hand session in a story worktree with no `STUDIO_START_DIR`. The lane-off caller is effective-exclusive. It waits for the slot to drain and is never admitted beside a slot holder. Test: T7 `test_lanes_mixed_lane_off_waiter_waits_for_drain`.
5. **A slot child that ignores TERM at the short cap.** The main-lane re-run must not start until the stragglers loop has KILLed the first child (no two copies at once). Test: T9 `test_lanes_short_cap_term_ignorer`.

---

## Dependency graph & waves

```
W1 (parallel):  T1 classifier   T2 records   T3 engine args   T4 skill text   T5 autopilot   T6 measure probe
W2 (parallel):  T7 lane state model  (needs T1, T2)        T8 isolate.sh  (needs T3)
W3 (parallel):  T9 short cap + demote (T7)   T10 leak scrub in gate (T7, T8)   T11 commit guard (T8)   T13 bench (T7)
W4:             T12 docs, floors, knob checks (all)
Then:           final whole-branch Opus review → fix wave → full gate → manual acceptance (orchestrator)
```

Each implementer works in its own worktree, branched off the story branch at the wave's start. The orchestrator cherry-picks each task into `issue-71-gate-short-lane` at the wave's end, in task-number order. A wave starts only after the previous wave is integrated and its affected suites pass on the story branch.

**Shared files: who owns which region.** No two tasks in the same wave share a region.

| File | Owner: region |
|---|---|
| `bin/studio-gate` | **T1**: header :1-4 (the `--classify` usage line), and the new lines after :42 (source `gate-class.sh`, `--classify` branch before the usage check :44). **T2**: header :27-31 (Gate times text), :219-226 (`T_REQ`/`WAIT_S` only), :286-295 (the row write; sources `gate-times.sh` there). **T7** (W2): header :10-26 lock text, :61-62, :75-81, :83-147, :219-298 restructure. It creates the two marked stub blocks below. **T9** (W3): header knob lines :5-12, the `SHORT_SECS=` line, the `# ---- short cap and demote (T9)` block. **T10** (W3): the `# ---- leak scrub (T10)` block. |
| `engines/godot/test.sh` | **T3**: after :43 (validation), :91-92 (command). **T9**: between :88 and :89 (demote). |
| `engines/godot/import.sh` | **T9** only (new `import_needed` after `import_class_cache_missing`, :61-71). |
| `bin/studio-test`, `bin/studio-dispatch` | **T8** only. |
| `bin/studio-overnight` | **T2** only: `gate_line` :1131-1141. |
| `tests/toolkit_test.sh` | **T2**: rc anchors :290 :305 :878 :940 :961 :983 :1020 :1041, plus one source line after `GODOT_STUB=` (:88). **T3**: the `unset` at :15, new tests before `# ---- studio-gate` (:793), one continuation line after the run_tests list's last line (:1158). **T9** (W3): one test before :793 and one more continuation line. |
| `tests/studio_setup_test.sh` | **T2**: :64, :123 and its top-of-file unset/source lines. |
| `tests/overnight_test.sh` | **T2**: one new test after `test_overnight_status` (~:1014-1030) and its run_tests name. |
| `tests/overnight_lanes_test.sh` | **T2**: `test_lanes_gate_room_warning` :2729-2746 only (outside #70's regions). |
| `tests/gate_lanes_test.sh`, `tests/gate_lanes_fixture.sh` | **T7** creates both. **T9** appends a marked section to the test file. **T13** only sources the fixture. |
| `tests/isolate_test.sh` | **T8** creates it. **T10** appends a marked section. |
| `tests/hook_test.sh`, `hooks/hooks.json` | **T11**. |
| `tests/studio_test.sh`, execute/plan skills, gameplay-programmer | **T4**. |
| autopilot SKILL `:70-75, :90, :119`, `tests/omega_contracts/autopilot_contract.sh` | **T5**. |
| `README.md`, `engines/godot/GUIDE.md`, `tests/run_all.sh`, `tests/harness_test.sh` | **T12** only. |

**Review tags.** These are Risky and get a per-task Opus review: T1, T2, T3, T7, T8, T9, T10, T11 (new seam, data/schema, concurrency or cross-system). These are Mechanical and fold into the final review: T4, T5, T6, T12, T13.

---

### Task 1: Classifier and load gate — Risky

**Files:**
- Create: `studios/game-dev/bin/gate-class.sh` (sourced; executable; `sh -n` clean)
- Modify: `studios/game-dev/bin/studio-gate:1-4` (usage text) and after `:42` (source + `--classify`)
- Test: `tests/gate_class_test.sh` (new suite)

**Interfaces:**
- Produces (all in `gate-class.sh`; caller sets `GC_DISPATCH` first):
  - `cfg_field FILE KEY` → the flat string value, or empty. It is studio-dispatch `field()` verbatim.
  - `studio_cfg KEY` → the value per D15. The block runs from `# cfg-begin` to `# cfg-end` and is **byte-identical** to T3's `engines/godot/cfg.sh` block. T8's parity test enforces this.
  - `gate_wt` → `git rev-parse --show-toplevel`, else `pwd -P`, then `cd … && pwd -P`.
  - `gc_resolve PATH` → the path with every symlink resolved (studio-dispatch :28-35's loop), then `cd "$(dirname)" && pwd -P` plus `/basename`.
  - `gate_classify CMD [ARG…]` → one line: `short godot`, `short node`, `shareable godot` or `exclusive godot`. It needs `GC_DISPATCH` (the resolved `$SELF_DIR/studio-dispatch`).
  - `gate_effective CLASS LANE_ON` → CLASS when LANE_ON is 1; `exclusive` for `shareable` or `short` when it is 0.
  - `gate_phys_cores` → a positive integer, or exit 1.
  - `gate_load1` → a decimal, or exit 1.
  - `gate_load_ok` → prints `<l>/<t>`, using `?` for an unreadable side. Exit 0 iff both are readable and l < t, with t = 2 × physical cores.
- Produces in studio-gate: `studio-gate --classify -- CMD…`. It prints `<effective class> <kind> lane=<on|off> wt=<path> argv=<argv class>` and exits 0. It takes no lock and needs no `.studio/`. A malformed call prints the usage and exits 2.

**Whitelist** (spec §6 table, exact). `$1` is the command after `--`.

| Class | Accepted argv |
|---|---|
| short godot | `sh <D> test --file <list>` (or `/bin/sh` for `sh`). `gc_resolve <D>` = `GC_DISPATCH`. Exactly 5 words. `<list>` has 1–3 comma-separated non-empty entries. |
| shareable godot | `sh <D> test` (3 words), or `sh <D> test <dir>` with `[ -d <dir> ]` relative to cwd (4 words). |
| short node: vitest | `npx [--no-install] vitest run …`, `node_modules/.bin/vitest run …` or `./node_modules/.bin/vitest run …`. Exactly one `--minWorkers=1`. Exactly one of `--maxWorkers=1` or `--maxWorkers=2`. Other options only `--reporter=<[A-Za-z0-9_-]+>`, `--silent`, `--no-color`, `-t <pat>`, `--testNamePattern=<pat>`. At least one positional; each `[ -f ]` relative to cwd, contains no `*?[{`, and does not start with `-`. |
| short node: tsc | `npx [--no-install] tsc` or the two bin forms. Exactly one `--noEmit`. Other options only `-p <f>`/`--project <f>` (`[ -f <f> ]`) and `--pretty false`. No positionals. |
| short node: eslint | `npx [--no-install] eslint` or the bin forms. At least one positional, each an existing regular file (same rules as vitest). Options only `--max-warnings <digits>` and `--format <[A-Za-z0-9_-]+>`. |
| exclusive godot | everything else |

- [ ] **Step 1: Write the failing suite `tests/gate_class_test.sh`.**
  - Fixture `gc_repo NAME` → `$GR`:
    - `git init -b main` and one commit;
    - `tests/unit/{a,b,c,d}.gd`;
    - `web-tools/tests/{a,b}.test.ts`;
    - `web-tools/tsconfig.json`;
    - `web-tools/node_modules/.bin/{vitest,tsc,eslint}` (executable stubs);
    - `.studio/config.json` = `{"engine": "godot4", "gate_short_lane": "on"}`.
  - Helper: `gcl DIR CMD…` runs `( cd DIR && sh "$BIN/studio-gate" --classify -- CMD… )` into `$TMP/gc.out`. `D="$BIN/studio-dispatch"`.
  - Tests, each a table of `gcl` calls and `assert_eq` on fields 1–2 (and on `lane=` / `wt=` where named):
    - `test_classify_gut_file_runs`:
      - `sh $D test --file tests/unit/a.gd` → `short godot`;
      - `--file tests/unit/a.gd,tests/unit/b.gd,tests/unit/c.gd` → `short godot`;
      - the same with `,tests/unit/d.gd` (4 files) → `exclusive godot`;
      - `--file a.gd extra` → `exclusive`;
      - `--file ''` → `exclusive`.
    - `test_classify_whole_suite_and_dir`:
      - `sh $D test` → `shareable godot`;
      - `sh $D test tests/unit` → `shareable`;
      - `sh $D test tests/unit/a.gd` (a file, not a dir) → `exclusive`;
      - with `gate_short_lane` absent, `sh $D test` → `exclusive godot … lane=off … argv=shareable`.
    - `test_classify_dispatch_identity`:
      - a symlink `$TMP/ln/studio-dispatch -> $D` → `short`;
      - a copy `$TMP/cp/studio-dispatch` → `exclusive`.
    - `test_classify_vitest_forms` (cwd `web-tools`): each of these is `short node`:
      - `npx vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts tests/b.test.ts`;
      - `npx --no-install vitest run --minWorkers=1 --maxWorkers=1 tests/a.test.ts`;
      - `node_modules/.bin/vitest run --maxWorkers=2 --minWorkers=1 tests/a.test.ts`;
      - `./node_modules/.bin/vitest run …`;
      - `… --reporter=dot --silent --no-color -t 'a b' --testNamePattern=x tests/a.test.ts`.
    - `test_classify_vitest_near_misses`: each of these is `exclusive`:
      - no cap;
      - `--maxWorkers=2` alone;
      - `--maxWorkers=3`;
      - `--minWorkers=1` twice;
      - the directory `tests`;
      - the glob `'tests/*.test.ts'`;
      - no positional;
      - a missing file;
      - `vitest --minWorkers=1 --maxWorkers=2 tests/a.test.ts` (no `run`);
      - `--watch`;
      - `--maxWorkers 2` (space form);
      - from the top level, `sh -c "cd web-tools && npx vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts"`;
      - from the top level, the direct form with `web-tools/tests/a.test.ts` positionals → `short` (the positionals exist relative to that cwd).
    - `test_classify_tsc_forms`:
      - short: `npx tsc --noEmit`, `npx tsc --noEmit -p tsconfig.json`, `npx tsc --noEmit --pretty false`;
      - exclusive: `npx tsc`, `npx tsc -b`, `npx tsc --build`, `npx tsc --noEmit --watch`, `npx tsc --noEmit -p missing.json`.
    - `test_classify_eslint_forms`:
      - short: `npx eslint tests/a.test.ts`, `npx eslint --max-warnings 0 --format stylish tests/a.test.ts`;
      - exclusive: `npx eslint tests`, `npx eslint --fix tests/a.test.ts`.
    - `test_classify_everything_else_is_exclusive`: each of these is `exclusive godot`:
      - `npm test`, `npm run build`;
      - `env X=1 npx vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts`;
      - `./merge.sh 12`, `.github/scripts/run-tests.sh`;
      - `sh $D run --seconds 10`;
      - `Godot --headless --path . -s x.gd`;
      - `sh -c true`;
      - `foo`.
    - `test_classify_reads_lane_from_toplevel`: from `web-tools/`, the output has `lane=on` and `wt=$(cd "$GR" && pwd -P)`.
    - `test_classify_run_fallback`:
      - a linked worktree `$GR-s` with no `.studio/config.json`;
      - `STUDIO_START_DIR=$GR` → `lane=on`;
      - the story worktree's own `{"gate_short_lane": "off"}` wins → `lane=off`;
      - `STUDIO_START_DIR` unset → `lane=off`.
    - `test_classify_minified_config`: `{"engine":"godot4","gate_short_lane":"on"}` on one line, and `"gate_short_lane" : "on"` → `lane=on`.
    - `test_load_threshold_from_physical_cores`: source `gate-class.sh` in a subshell, then:
      - `STUDIO_GATE_PHYS_CORES=4 STUDIO_GATE_LOADAVG=5` → exit 0 and `5/8`;
      - `STUDIO_GATE_PHYS_CORES=2 STUDIO_GATE_LOADAVG=5` → exit 1 and `5/4`;
      - `LOADAVG=99` → exit 1;
      - `LOADAVG=0` → exit 0.
    - `test_load_unreadable_refuses`:
      - `STUDIO_GATE_LOADAVG=abc` → exit 1 and `?/8`;
      - `STUDIO_GATE_PHYS_CORES=0` and `=x` → exit 1 and `<l>/?`.
    - `test_load_production_defaults`: seams unset. On Darwin, `gate_phys_cores` = `sysctl -n hw.physicalcpu` and `gate_load1` matches `^[0-9][0-9]*(\.[0-9]*)?$`. On Linux it compares with `/proc/cpuinfo` distinct (`physical id`,`core id`) pairs. Anything else gets an `exit 1` assertion.
    - `test_classify_takes_no_lock`: in a `gate_proj`-style repo, `--classify` leaves no `gate.lock`, `gate.short`, `gate.wantx` or `gate.times`.
    - `test_classify_usage`: `studio-gate --classify` and `studio-gate --classify --` → exit 2 and the usage line.
  - Suite top: `unset STUDIO_START_DIR …` (Global Constraints), then `mk_tmp gate_class`.
- [ ] **Step 2: Run it and see it fail.** Run `sh <R> <W>/tests/gate_class_test.sh`. Expected: FAIL (no `--classify`).
- [ ] **Step 3: Implement `gate-class.sh`.**
  - The header names `STUDIO_GATE_LOADAVG` (the 1-min load, test-only) and `STUDIO_GATE_PHYS_CORES` (the physical core count, test-only) in its first 30 lines.
  - Load rule comment: t = 2 × physical cores, 8 on the 4-core i7-7700HQ. It admits the measured baseline (load ≈ 5 with two live runs and a wall-paced suite) and a CPU-bound fixed-fps suite (≈ 6). It refuses at ≥ 8, when every logical CPU is busy. There is no config override.
  - Darwin reads `sysctl -n vm.loadavg` (`{ l1 l5 l15 }`, field 2) and `sysctl -n hw.physicalcpu`. Linux reads `/proc/loadavg` field 1 and the `/proc/cpuinfo` pairs. A load must match `^[0-9]+(\.[0-9]+)?$`. The `<` comparison is `awk 'BEGIN { exit !(l + 0 < t + 0) }'`.
  - `cfg_field` and `studio_cfg` go between the markers, exactly:

    ```sh
    # cfg-begin (byte-identical in bin/gate-class.sh and engines/godot/cfg.sh; #71 D15)
    # cfg_field FILE KEY — a flat JSON string key's value (studio-dispatch field()).
    cfg_field() {
      [ -f "$1" ] || return 0
      sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
    }
    # studio_cfg KEY — KEY from .studio/config.json at the git top level (else the
    # current dir); when that file lacks it, from $STUDIO_START_DIR's (the run's).
    studio_cfg() {
      _sc_top="$(git rev-parse --show-toplevel 2>/dev/null)" || _sc_top=""
      [ -n "$_sc_top" ] || _sc_top="$(pwd -P)"
      _sc_v="$(cfg_field "$_sc_top/.studio/config.json" "$1")"
      if [ -z "$_sc_v" ] && [ -n "${STUDIO_START_DIR:-}" ]; then
        _sc_v="$(cfg_field "$STUDIO_START_DIR/.studio/config.json" "$1")"
      fi
      printf '%s\n' "$_sc_v"
    }
    # cfg-end
    ```
- [ ] **Step 4: Wire `--classify` into studio-gate.** Add the line `# studio-gate --classify -- <cmd…> — print the class the gate would give <cmd> (no lock).` to :2-4. After :42:

  ```sh
  . "$SELF_DIR/gate-class.sh"
  GC_DISPATCH="$(gc_resolve "$SELF_DIR/studio-dispatch")"
  if [ "${1:-}" = --classify ]; then
    if [ "$#" -lt 3 ] || [ "$2" != "--" ]; then
      printf 'usage: studio-gate --classify -- <cmd> [args...]\n' >&2; exit 2
    fi
    shift 2
    _ca="$(gate_classify "$@")"; _cl=0; [ "$(studio_cfg gate_short_lane)" = on ] && _cl=1
    printf '%s %s lane=%s wt=%s argv=%s\n' "$(gate_effective "${_ca% *}" "$_cl")" "${_ca#* }" \
      "$([ "$_cl" = 1 ] && echo on || echo off)" "$(gate_wt)" "${_ca% *}"
    exit 0
  fi
  ```
- [ ] **Step 5: Run it and see it pass.** Run `sh <R> <W>/tests/gate_class_test.sh`, then `sh <R> <W>/tests/toolkit_test.sh` (the gate tests are unchanged and green) and `sh <R> <W>/tests/studio_test.sh test_bin_syntax`. Then `sh <R> <W>/tests/harness_test.sh` (rulings and guards for the new suite).
- [ ] **Step 6: Commit** `feat(T1): gate classifier — argv whitelist, run-config fallback, load gate`.

### Task 2: Records — 8-field rows, retention, gate_line — Risky

**Files:**
- Create: `studios/game-dev/bin/gate-times.sh`, `tests/gate_times_rows.sh` (sourced helper, not a suite), `tests/gate_times_test.sh`
- Modify:
  - `bin/studio-gate:27-31`, `:219-226`, `:286-295`;
  - `bin/studio-overnight:1131-1141` (`gate_line`);
  - `tests/toolkit_test.sh` anchors :290 :305 :878 :940 :961 :983 :1020 :1041, plus a source line after :88;
  - `tests/studio_setup_test.sh:64`, `:123`;
  - `tests/overnight_test.sh` (a new test after `test_overnight_status`);
  - `tests/overnight_lanes_test.sh:2729-2746`.

**Interfaces:**
- Consumes: `mutex_take`/`mutex_drop`/`HAVE_MUTEX` from studio-gate (:102-116). gate-times.sh documents that its sourcing script defines them.
- Produces:
  - `gate_times_append FILE EPOCH WHO HOLD RC WAIT LANE CLASS UNIT`: appends `<epoch> <who> <hold> <rc> <wait> <lane> <class> <unit>` and applies D9.
  - `tests/gate_times_rows.sh`:
    - `gt_rows FILE WHO RC` → the count of 8-field rows with `$2==WHO && $4==RC`;
    - `gt_row FILE WHO` → the newest 8-field row of WHO.
  - studio-gate variables `T_REQ`, `WAIT_S`. T7 reuses them.
  - `gate_line` prints a second line, `gate short lane: <who> (pid <p>) for <t>[, unit <u>]`, when `gate.short/pid` is live (`kill -0`; display only).

- [ ] **Step 1: Write the failing tests.**
  - `tests/gate_times_rows.sh`:

    ```sh
    # gt_rows FILE WHO RC — 8-field gate.times rows of WHO with rc RC (#71 R6).
    gt_rows() { awk -v w="$2" -v r="$3" 'NF == 8 && $2 == w && $4 == r { n++ } END { print n + 0 }' "$1" 2>/dev/null; }
    # gt_row FILE WHO — the newest 8-field row of WHO.
    gt_row() { awk -v w="$2" 'NF == 8 && $2 == w { l = $0 } END { print l }' "$1" 2>/dev/null; }
    ```
  - The ten anchor rewrites (O12). Each becomes `assert_eq 1 "$(gt_rows F WHO RC)" "<same message>"`, plus one shape assertion per file: `assert_contains F '^[0-9][0-9]* WHO [0-9][0-9]* RC [0-9][0-9]* [a-z][a-z:-]* [a-z][a-z]* [^ ][^ ]*$'`.
    - :290 and :305 → `studio-test-file 0`;
    - :878 → `sig 143`;
    - :940 → `studio-test 0`;
    - :961 → `setup 0`;
    - :983 → `t 124`;
    - :1041 → `prodcap 0`;
    - studio_setup_test :64 → `setup 0`, :123 → `gate 0`;
    - :1020 becomes three assertions: `assert_eq 0 "$(gt_rows F t 124)" "no 124 recorded"`, `assert_eq 1 "$(gt_rows F t 3)" "the run's own row"` and `assert_eq 1 "$(gt_rows F t 0)" "the capped true run's row"`.
  - `tests/gate_times_test.sh`. Its fixture is `gate_proj` copied from toolkit_test :795:
    - `test_gt_rows_rejects_wrong_rc`:
      - a planted `1 t 2 1 0 main exclusive -` → `gt_rows F t 0` = 0 and `gt_rows F t 1` = 1;
      - a planted 4-field `1 t 2 0` → `gt_rows F t 0` = 0;
      - a planted 8-field `… t 2 124 …` → `gt_rows F t 124` = 1. This is the :1020 rewrite's failure case.
    - `test_gate_times_row_shape`: `STUDIO_UNIT_TAG=u1 sh $GATE w -- true` → `gt_row F w` matches `^[0-9]+ w [0-9]+ 0 [0-9]+ main exclusive u1$`. With no tag, field 8 is `-`.
    - `test_gate_times_wait_recorded`:
      - holder `h -- sh -c 'touch $TMP/h.up; while [ ! -f $TMP/h.go ]; do sleep 0.1; done'`;
      - wait for `h.up`, start waiter `w -- true`, wait for its `gate: waiting` line, `sleep 2`, then touch `h.go`;
      - `w`'s field 5 ≥ 2, and `h`'s field 5 is 0 or 1.
    - `test_gate_times_keeps_4_field_rows`: plant `5 old 3 0` and `6 studio-test 9 0`, run one gate → both lines are still present, byte-identical.
    - `test_gate_times_14_day_retention`:
      - 60 rows `$((now-86400)) w 1 0 0 main exclusive -` plus one run → 61 `w` rows (young rows are all kept);
      - 60 rows at `now-15*86400` plus one run → 50.
    - `test_gate_times_line_cap`: 20010 young rows with who `x$i` plus one run → `wc -l` = 20000, and the run's row is the last line.
    - `test_gate_times_concurrent_no_loss`: 10 gates `w$i -- true` in the background, then `wait` → 10 rows.
    - `test_gate_times_mutex_fallback`:
      - `sleep 60 &` gives `_sp`;
      - `ln -s $_sp $GP/.studio/gate.lock.mutex` (a live foreign owner);
      - `sh $GATE w -- true` returns in < 15 s with the row present (the unlocked fallback after about 5 s), and the mutex link is untouched;
      - kill `_sp` at the end.
      - This one is `TESTS_EXCLUSIVE`, with ruling `in (a) asserts the fallback returns inside 15 s`.
  - `tests/overnight_test.sh`, new test `test_overnight_status_short_lane`. It reuses `test_overnight_status`'s setup (relocate with `grep -n '^gate: free\$' tests/overnight_test.sh`):
    - plant `$STATE_ROOT/.studio/gate.short/{pid,who,since,unit}` with the pid of a `sleep 60 &`;
    - `st.out` contains `^gate: free$` and `^gate short lane: vitest (pid <p>) for `;
    - with the pid dead, there is no `gate short lane` line.
  - `tests/overnight_lanes_test.sh` `test_lanes_gate_room_warning`: add a second planted file that mixes 4-field and 8-field rows (`<e> studio-test 3000 0 12 main shareable -`) and assert the same warning text as the 4-field case.
- [ ] **Step 2: Run them and see them fail.**
  - `sh <R> <W>/tests/gate_times_test.sh` → FAIL;
  - `sh <R> <W>/tests/toolkit_test.sh` → the rewritten anchors FAIL;
  - `sh <R> <W>/tests/studio_setup_test.sh` → FAIL;
  - `sh <R> <W>/tests/overnight_test.sh test_overnight_status_short_lane` → FAIL;
  - `sh <R> <W>/tests/overnight_lanes_test.sh test_lanes_gate_room_warning` → PASS. gate_room_check already reads `$2`/`$3` (studio-overnight:702-708), so this pins compatibility.
- [ ] **Step 3: Implement `gate_times_append` in `bin/gate-times.sh`.**

  ```sh
  # gate_times_append FILE EPOCH WHO HOLD RC WAIT LANE CLASS UNIT — append one row and
  # keep (D9) the newest 50 rows per who OR any row younger than 14 days, then the
  # newest 20000 lines. The rewrite runs under the reclaim mutex (mutex_take /
  # mutex_drop, defined by the sourcing script) when it can be had within ~5 s;
  # otherwise unlocked, as before #71, so a release is never blocked.
  gate_times_append() {
    _ga_f="$1"; shift
    _ga_row="$*"; _ga_now="$1"; _ga_i=0; _ga_lk=0
    while [ "$_ga_i" -lt 50 ]; do
      if mutex_take; then _ga_lk=1; break; fi
      _ga_i=$((_ga_i + 1)); sleep 0.1
    done
    { [ -f "$_ga_f" ] && cat "$_ga_f"; printf '%s\n' "$_ga_row"; } | awk -v now="$_ga_now" '
      { w[NR] = $2; t[NR] = $1 + 0; l[NR] = $0 }
      END {
        for (i = NR; i >= 1; i--) keep[i] = (++c[w[i]] <= 50) || (now - t[i] < 1209600)
        n = 0; for (i = NR; i >= 1; i--) if (keep[i] && ++n > 20000) keep[i] = 0
        for (i = 1; i <= NR; i++) if (keep[i]) print l[i]
      }' > "$_ga_f.$$" 2>/dev/null && mv -f "$_ga_f.$$" "$_ga_f" 2>/dev/null
    rm -f "$_ga_f.$$"
    [ "$_ga_lk" = 0 ] || mutex_drop
  }
  ```
- [ ] **Step 4: Wire it into studio-gate.**
  - At :219, add `T_REQ="$(date +%s)"` before `waited=0`. After the loop (:226), add `WAIT_S=$(( $(date +%s) - T_REQ ))`.
  - Replace :289-295 with `. "$SELF_DIR/gate-times.sh"` and `gate_times_append "$ROOT/.studio/gate.times" "$(date +%s)" "$WHO" "$(( $(date +%s) - T0 ))" "${SIGSTATUS:-$rc}" "$WAIT_S" main exclusive "${TAG:--}"`. The placeholders `main exclusive` are T7's to replace.
  - Header :27-31: `Gate times: every command that ran appends \`<epoch> <who> <seconds> <rc> <wait s> <lane> <class> <unit|->\` (rc 128+n when a signal ended it) … keeps the newest 50 rows per who or any row younger than 14 days, at most 20000 lines`.
- [ ] **Step 5: `gate_line`.** Keep the first line exactly. Restructure so that the slot line prints after it on both paths (main free and main held):

  ```sh
  _gs="$STATE_ROOT/.studio/gate.short"; _gs_p="$(cat "$_gs/pid" 2>/dev/null)"
  if [ -n "$_gs_p" ] && kill -0 "$_gs_p" 2>/dev/null; then
    _gs_u="$(cat "$_gs/unit" 2>/dev/null)"; _gs_t="$(cat "$_gs/since" 2>/dev/null)"
    [ -z "${1:-}" ] || _gs_u="${_gs_u#"$(basename "$1")"-}"
    printf 'gate short lane: %s (pid %s)%s%s\n' "$(cat "$_gs/who" 2>/dev/null)" "$_gs_p" \
      "${_gs_t:+ for $(elapsed_since "$_gs_t")}" "${_gs_u:+, unit $_gs_u}"
  fi
  ```
- [ ] **Step 6: Run them and see them pass.** Rerun the Step 2 commands. `gate_times_test`, `toolkit_test` and `studio_setup_test` run whole. The two overnight suites run `TESTS_ONLY` only (named tests are not heavy).
- [ ] **Step 7: Commit** `feat(T2): gate.times records wait, lane, class and unit; 14-day retention under the mutex`.

### Task 3: studio-test passes the project's engine args — Risky

**Files:**
- Create: `studios/game-dev/engines/godot/cfg.sh` (sourced; executable). It holds exactly T1's `# cfg-begin` … `# cfg-end` block.
- Modify: `engines/godot/test.sh`, after :43 (validation) and :91-92 (command)
- Test: `tests/toolkit_test.sh`. Add `STUDIO_START_DIR` to the `unset` at :15. New tests go before `# ---- studio-gate` (:793), and one continuation line goes after :1158.

**Interfaces:**
- Produces: `cfg.sh` with `cfg_field`/`studio_cfg` (T8 sources it). In test.sh, `ENGINE_ARGS` holds the validated words, or is empty.

- [ ] **Step 1: Write the failing tests.** Each test writes `$P/.studio/config.json`. `fresh_project` is not a git repo, so the top level falls back to `pwd -P`. Each reads the stub's `stub godot args:` line from `$P/.studio/reports/test-*.log`.
  - `test_test_engine_args_reach_godot`: `{"engine": "godot4", "test_engine_args": "--fixed-fps 60"}`. For the whole suite, a directory, and `--file tests/unit/a.gd`, the args line matches `^stub godot args: --headless --fixed-fps 60 --path [^ ]* -s addons/gut/gut_cmdln.gd `.
  - `test_test_engine_args_absent_is_golden`: no key, then an empty key (`""`). The whole line equals today's form, `^stub godot args: --headless --path [^ ]* -s addons/gut/gut_cmdln.gd -gconfig=… -gexit -gjunit_xml_file=res://\.studio/reports/test-[0-9-]*\.xml$`. Copy the `-gconfig`/selection part from the existing `test_test_passes_the_projects_gut_config` expectations.
  - `test_test_engine_args_refuses_bad_chars`: `--fixed-fps 60;x`, `--fixed-fps \"60\"` (JSON-escaped quote), and a tab. Each exits 1. stderr matches `^studio-test: test_engine_args in .studio/config.json: .* — got `. No `stub godot args` line is written.
  - `test_test_engine_args_allowlist`:
    - `--fixed-fps 60` and `--fixed-fps 1000` pass;
    - each of these exits 1 and names the key: `--fixed-fps`, `--fixed-fps 0`, `--fixed-fps 1001`, `--fixed-fps abc`, `--fixed-fps=60`, `-s x`, `--path /tmp`, `--main-pack x`, `--scene x`, `--quit-after 1`, `--write-movie x`, `--log-file x`, `res://x.tscn`.
  - `test_test_engine_args_odd_spacing`: `"test_engine_args" : "  --fixed-fps   60 "` → the args line has `--headless --fixed-fps 60 --path`.
  - `test_test_engine_args_run_fallback`: the project has no key and `STUDIO_START_DIR=$TMP/run` has `{"test_engine_args": "--fixed-fps 30"}` → `--fixed-fps 30`. The project's own `"--fixed-fps 60"` wins over it.
  - `test_test_engine_args_not_for_import`: no `.godot/`, `STUB_IMPORT` as in `test_test_imports_when_dot_godot_is_absent` → the `--import` args line has no `--fixed-fps`.
  - `test_test_config_keys_still_read`: `{"engine": "godot4", "tests": "gut", "test_engine_args": "--fixed-fps 60"}` → the run passes. `sh "$BIN/studio-dispatch" test` still finds the godot adapter, so the `engine` key is still read.
- [ ] **Step 2: Run them and see them fail.** Run `sh <R> <W>/tests/toolkit_test.sh test_test_engine_args_reach_godot test_test_engine_args_absent_is_golden test_test_engine_args_refuses_bad_chars test_test_engine_args_allowlist test_test_engine_args_odd_spacing test_test_engine_args_run_fallback test_test_engine_args_not_for_import test_test_config_keys_still_read`. Expected: FAIL. The golden and keys tests pass already.
- [ ] **Step 3: Implement the validation in test.sh, after :43.**

  ```sh
  # #71 R1: the project's engine args (`test_engine_args`, a flat string), checked
  # against an allowlist (O11): only `--fixed-fps <1-1000>`. Exit 1, never 2.
  . "$HERE/cfg.sh"
  _ta_v="$(studio_cfg test_engine_args)"; ENGINE_ARGS=""
  _ta_bad() { printf 'studio-test: test_engine_args in .studio/config.json: %s — got %s\n' "$1" "$_ta_v" >&2; exit 1; }
  case "$_ta_v" in *[!A-Za-z0-9\ ._=:,/-]*) _ta_bad "only letters, digits, spaces and ._=:,/- are allowed" ;; esac
  set -f; _ta_want=0
  for _ta_w in $_ta_v; do
    if [ "$_ta_want" = 1 ]; then
      case "$_ta_w" in ''|*[!0-9]*) _ta_bad "--fixed-fps needs a whole number from 1 to 1000" ;; esac
      [ "${#_ta_w}" -le 4 ] && [ "$_ta_w" -ge 1 ] && [ "$_ta_w" -le 1000 ] || _ta_bad "--fixed-fps needs a whole number from 1 to 1000"
      _ta_want=0; ENGINE_ARGS="$ENGINE_ARGS --fixed-fps $_ta_w"; continue
    fi
    case "$_ta_w" in
      --fixed-fps) _ta_want=1 ;;
      *) _ta_bad "$_ta_w is not an allowed flag (allowed: --fixed-fps <N>)" ;;
    esac
  done
  set +f
  [ "$_ta_want" = 0 ] || _ta_bad "--fixed-fps needs a whole number from 1 to 1000"
  ```
- [ ] **Step 4: The command (:91).** `set -f` and `"$GODOT" --headless $ENGINE_ARGS --path "$PROJECT" -s addons/gut/gut_cmdln.gd "$@" -gexit "-gjunit_xml_file=res://$xml_rel" >> "$log" 2>&1`, then `engine_status=$?` and `set +f`. An empty unquoted `$ENGINE_ARGS` yields no word, so the argv is byte-identical. Also update the header comment of test.sh (:1-16) to name the key.
- [ ] **Step 5: Run them and see them pass.** Rerun the Step 2 command, then the whole `sh <R> <W>/tests/toolkit_test.sh` and `sh <R> <W>/tests/studio_test.sh test_bin_syntax`.
- [ ] **Step 6: Commit** `feat(T3): studio-test passes the project's test_engine_args (allowlisted --fixed-fps)`.

### Task 4: The planning rule in skill text — Mechanical

**Files:**
- Modify:
  - `studios/game-dev/skills/execute/SKILL.md` :380-383, :390-396 (plus a new `suite` bullet after `visual`), :461-463, :490-493, :522-525;
  - `studios/game-dev/skills/plan/SKILL.md` :84-90, :119-140;
  - `studios/game-dev/agents/gameplay-programmer.md` :35-37, :49-50.
- Test: `tests/studio_test.sh`, a new `test_short_lane_unit_rule_text` next to `test_execute_command_caps_text` (:611), plus its run_tests name.

**Interfaces:** none (text). `<vitest form>` = `cd <node dir> && studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2 <file>…`, and `<tsc form>` = `cd <node dir> && studio-gate tsc -- npx tsc --noEmit`.

- [ ] **Step 1: Write the failing test.**
  - On execute, `assert_contains` each of:
    - `runs \`studio-test --file\` on every test file the task created or changed`;
    - `calls of up to three files each take the short lane`;
    - `when the task's \`Verify:\` includes \`suite\``;
    - `` `suite` — the implementer also runs the whole suite``;
    - `studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2`;
    - `never \`sh -c\` inside it`;
    - `the implementers ran each task's touched tests`.
  - `assert_not_contains` execute `runs \`studio-test\` and pastes its summary`.
  - On plan, `assert_contains`:
    - `` `suite` — the task changes a seam whose effects reach tests it does not touch``;
    - `Without \`suite\`, a task's tests are the files it touches`;
    - `targeted vitest as`.
  - On gameplay-programmer, `assert_contains` `Run \`studio-test --file\` on every test file the task touched` and `run the whole suite only when \`Verify:\` includes \`suite\``.
  - The existing `test_execute_command_caps_text` and `test_agent_gameplay_programmer_file_runs` literals stay (e.g. `studio-test --file <test file>`).
- [ ] **Step 2: Run it and see it fail.** Run `sh <R> <W>/tests/studio_test.sh test_short_lane_unit_rule_text`. Expected: FAIL.
- [ ] **Step 3: Edit the text.** Use the spec §11 table rows verbatim for each place: execute §3 `unit`, the new `suite` bullet, §4a rule 2, the §2 brief line, §5 step 1 and its brief, the gameplay-programmer step 3 and its playtest/visual paragraph, plan §4 `suite` plus its sentence, and plan §2. A playtest/visual-only task with no touched test file runs no GUT at the task.
- [ ] **Step 4: Run it and see it pass.** Run `sh <R> <W>/tests/studio_test.sh`, `sh <R> <W>/tests/pointer_skills_execute_test.sh` and `sh <R> <W>/tests/pointer_skills_route_test.sh`.
- [ ] **Step 5: Commit** `docs(T4): units verify touched tests with studio-test --file; Verify kind suite`.

### Task 5: The autopilot merges the three keys — Mechanical

**Files:**
- Modify: `shared/omega/skills/autopilot/SKILL.md` :70-75 (the question and the one-liner), :90 (the run worktree step), :119 (Global Constraints)
- Test: `tests/omega_contracts/autopilot_contract.sh` (next to its `max_lanes` assertions :65-77)

**Interfaces:** the one-liner, exact, replacing the one at :75 (it keeps `every other key is kept` and `an integer from 0 to 8`):

```
python3 -c 'import json,os,sys; p=".studio/config.json"; c=json.load(open(p)) if os.path.exists(p) else {}; c.setdefault("overnight", {})["max_lanes"]=int(sys.argv[1]); sys.argv[2]=="on" and c.update({"test_engine_args": "--fixed-fps 60", "user_dir": "per-worktree", "gate_short_lane": "on"}); os.makedirs(".studio", exist_ok=True); open(p,"w").write(json.dumps(c, indent=2)+"\n")' <n> <on|off>
```

- [ ] **Step 1: Write the failing contract assertions.**
  - `assert_contains "$S"` each of:
    - `one .AskUserQuestion. with two questions` (kept);
    - `three for a .godot4. project`;
    - `short lane`;
    - `"gate_short_lane": "on"`;
    - `"user_dir": "per-worktree"`;
    - `"test_engine_args": "--fixed-fps 60"`;
    - `' <n> <on|off>`;
    - `studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2`.
  - Then a fixture run. Extract the program with `sed -n "s/.*python3 -c '\([^']*\)' <n> <on|off>.*/\1/p" "$S" | head -n 1`, then in `$TMP/ap-fx`:
    - (a) a file `{"merge_command": "./merge.sh", "overnight": {"session_minutes": 90}}` and `2 on` → `python3 -c 'import json;…'` reads `merge_command`, `overnight.session_minutes` = 90, `max_lanes` = 2 and all three keys;
    - (b) the same again → `cmp` byte-identical (idempotent);
    - (c) the output of `2 off` run once, then `2 off` again → byte-identical, and none of the three keys;
    - (d) no file and `0 on` → it writes `.studio/config.json` with `overnight.max_lanes` = 0 and the keys.
  - When `python3 -c 'import json'` fails, `_fail "python3 is needed for the autopilot merge"`. Fail closed: the skill depends on python3.
- [ ] **Step 2: Run it and see it fail.** Run `sh <R> <W>/tests/omega_test.sh test_skill_contracts`. Expected: FAIL.
- [ ] **Step 3: Edit SKILL.md.**
  - :70: `Ask one \`AskUserQuestion\` with two questions (three for a \`godot4\` project), …`.
  - Add a third bullet, **short lane** (asked only when the engine is `godot4`), with options:
    - "on" — `test_engine_args "--fixed-fps 60", user_dir "per-worktree", gate_short_lane "on"`: short checks run beside a whole suite in their own slot; GUT runs frame-paced; every story worktree gets its own `user://`;
    - "off" — today's single gate lock.
  - :75: the one-liner above, with `<on|off>` as that answer.
  - :90: `write the lane count and, when on, the short-lane keys into …`.
  - :119: append `; a targeted vitest as \`cd <node dir> && studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2 <file>…\` and tsc as \`cd <node dir> && studio-gate tsc -- npx tsc --noEmit\` (the \`cd\` outside the gate, never \`sh -c\` inside it)`.
  - The manifest commit line (`git add docs/runs/<slug>.md .studio/config.json …`) is unchanged.
- [ ] **Step 4: Run it and see it pass.** Run `sh <R> <W>/tests/omega_test.sh`.
- [ ] **Step 5: Commit** `docs(T5): autopilot merges the short-lane keys into the run config`.

### Task 6: The measurement probe — Mechanical

**Files:**
- Create: `tests/probes/gate_wait_measure.py`, from `/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/5a98a755-7ca1-4ed6-b551-b3a3f4153b67/scratchpad/gate-wait-measure.py` (655 lines; read it whole, it is the source being moved).

**Interfaces:** the CLI keeps every existing flag (`--root --days --day --since --until --validate --top --dump --transcripts`) and adds:
- `--lanes`: the after-report;
- `--check-overlap`: exit 1 if any lane-`short` row overlaps a class-`exclusive` row;
- `--selftest`.

- [ ] **Step 1: Parse both row shapes.** `load_gate_times` accepts 4 fields (as today) or 8 fields. For 8 fields, `wait=int(p[4])`, `lane`, `cls`, `unit`; acquire = rel − hold, and request = acquire − wait, exact, with no inference. The dedup key stays `(e, w, s)`.
- [ ] **Step 2: Per-lane attribution.** The holder timeline for the main lane is the rows whose lane starts with `main`. A `short` row never counts as a blocker of a main-lane call.
- [ ] **Step 3: `--lanes` report (spec §13.7).**
  - Per verb, the verbs are `studio-test-file`; `vitest`; `tsc`/`eslint`/`lint`; and all three.
  - For the calls that arrive while a `studio-test` row of class `shareable` holds main:
    - exposure = suite release − arrival (arrival = epoch − hold − wait);
    - waited = min(acquisition, release) − arrival;
    - recovered share = 1 − Σwaited/Σexposure.
  - Print the targets 55% / 30% / 60% / 50%, judged only when exposure ≥ 30 min, with PASS/FAIL/`reported`.
  - Per-lane counts of short-eligible rows by `lane` value.
  - The old metric (short-call minutes behind whole suites per 100 short calls), labelled "not judged".
  - Waits behind final gates (`final-gate`, `merge`, `gate`), reported apart.
- [ ] **Step 4: `--check-overlap`** (acceptance 6). It prints each overlapping pair.
- [ ] **Step 5: `--selftest`.**
  - It writes a synthetic `gate.times` under `tempfile.mkdtemp(dir=os.environ["TMPDIR"])` with:
    - one `studio-test` shareable hold of 600 s;
    - three `studio-test-file` short rows that waited 0;
    - one that went to main and waited the remaining 300 s (lane `main:slot-busy`);
    - one exclusive `final-gate` row and one deliberately overlapping `short` row.
  - It asserts:
    - recovered share = the hand-computed value (write the arithmetic in the test's comment);
    - the 4-field rows parse;
    - `--check-overlap` finds exactly the planted pair.
- [ ] **Step 6: Run it.**
  - `sh <R> --args /usr/bin/env python3 -I <W>/tests/probes/gate_wait_measure.py --selftest` → `selftest: ok`, exit 0.
  - `python3 -I <W>/tests/probes/gate_wait_measure.py --help` lists the new flags.
  - It never runs against phoenix in this task.
- [ ] **Step 7: Commit** `test(T6): commit the gate-wait measurement probe, 8-field rows and lane report`.

### Task 7: The lane state model in studio-gate — Risky (W2)

**Files:**
- Modify: `bin/studio-gate` :10-26 (header lock text), :61-62, :75-81, :83-147, :219-298
- Create: `tests/gate_lanes_fixture.sh` (sourced), `tests/gate_lanes_test.sh` (new suite)

**Interfaces:**
- Consumes: from T1, `gate_classify`, `gate_effective`, `gate_wt`, `studio_cfg`, `gate_load_ok`, `GC_DISPATCH`. From T2, `gate_times_append`, `T_REQ`, `WAIT_S`.
- Produces, for T9, T10 and T13:
  - lane dirs `$ROOT/.studio/gate.short/`;
  - `gate.lock/` with `class`, `kind`, `wt`;
  - `$ROOT/.studio/gate.wantx/<pid>` (`<since> <who>`);
  - `DEMOTE="$ROOT/.studio/gate.short.demote.$$"`;
  - child env `STUDIO_GATE_LANE=main|short`, plus `STUDIO_GATE_DEMOTE=$DEMOTE` in the slot only;
  - globals `LANE`, `MODE`, `CLS`, `KIND`, `WT`, `ARGV_CLS`, `HOLD_S`, `ROW_RC`, `SIGSTATUS`, `SHORT_SECS` (T7: the constant `SHORT_SECS=300`), `ATT_SECS`, `ATT_SHORT`, `SHORT_CAPPED`, `DEMOTED`.
  - Stub blocks that T9 and T10 own, with these exact markers and stub bodies:
    - `# ---- short cap and demote (T9) ----`: `lane_cap() { ATT_SECS="$CAP_SECS"; ATT_SHORT=0; }` and `lane_after_run() { return 1; }`.
    - `# ---- leak scrub (T10) ----`: `gate_scrub() { :; }`.

    Place them at least 5 unchanged lines apart.
  - Fixture API (`tests/gate_lanes_fixture.sh`):
    - `lanes_init`: the stub studio root `$LS` and the env (it exports `OMEGA_STUDIO_ROOT=$LS STUDIO_GATE_POLL_SECONDS=0.1 STUDIO_GATE_LOADAVG=0 STUDIO_GATE_PHYS_CORES=4 LANES_MARKS LANES_HOLD_DIR` and unsets the Global Constraints list);
    - `lanes_repo NAME` → `$LR`;
    - `lanes_wt NAME [on|off]` → its path;
    - `lanes_bg TAG DIR -- CMD…`;
    - `lanes_go TAG`;
    - `lanes_wait_mark REGEX`;
    - `lanes_wait_file PATH`;
    - `lanes_done TAG` → its exit status;
    - `lanes_overlap A B` → `yes`/`no`.

**Decisions (recorded; the builder's calls in the spec):**
- **Lane off ⇒ every caller is effective-exclusive** (`gate_effective`). That covers a lane-off suite (D1) and also a lane-off short check. So D5's reservation is only checked by lane-on non-exclusive callers, and a fully lane-off project behaves exactly as today (the §7 open point, U8). The rows keep the short-eligible fact as lane `main:off`.
- **Row reasons replace spaces with `-`:** `main:iso`, `main:exclusive-waiting`, `main:beside-exclusive`, `main:same-worktree`, `main:slot-busy`, `main:load`, `main:off`, `main:demoted`. With spaces the row would gain fields. stderr keeps the spec's spaced reasons.
- **`; short lane: off` is never printed**, so lane-off stderr stays byte-identical (A5).
- **The waiting line names its blocker** in this order: the main holder; else the slot holder (`, short lane`); else the reserving exclusive waiter (`, reserved`).
- There is no `got the lane after` line.
- The units test is in this suite (registration + TERM, as `unit_reap` sends it) rather than overnight_test. `unit_reap` (studio-overnight:1186-1224) is unchanged and lane-blind.

- [ ] **Step 1: Write the fixture `tests/gate_lanes_fixture.sh`.**
  - `$LS/studio.json` is `{"engine": "godot4"}`.
  - `$LS/engines/godot/test.sh` and `$LR/web-tools/node_modules/.bin/{vitest,tsc}` are all the same stub:

    ```sh
    #!/bin/sh
    # stub run: marks start (lane, niceness, worktree) and end; holds until
    # $LANES_HOLD_DIR/<tag> exists (event wait, at most 30 s) or LANES_SLEEP s.
    _t="${LANES_TAG:-t}"
    printf 's %s %s %s %s\n' "$_t" "${STUDIO_GATE_LANE:--}" "$(ps -o nice= -p $$ | tr -d ' ')" "$(pwd -P)" >> "$LANES_MARKS"
    if [ -n "${LANES_DEMOTE:-}" ] && [ -n "${STUDIO_GATE_DEMOTE:-}" ]; then
      printf '%s\n' "$LANES_DEMOTE" > "$STUDIO_GATE_DEMOTE"; printf 'e %s\n' "$_t" >> "$LANES_MARKS"; exit 1
    fi
    [ -z "${LANES_TRAP:-}" ] || trap '' TERM
    if [ -n "${LANES_SLEEP:-}" ]; then sleep "$LANES_SLEEP"
    else _i=0; while [ ! -f "$LANES_HOLD_DIR/$_t" ] && [ "$_i" -lt 300 ]; do sleep 0.1; _i=$((_i + 1)); done; fi
    printf 'e %s\n' "$_t" >> "$LANES_MARKS"
    exit "${LANES_RC:-0}"
    ```
  - `$LS/engines/godot/isolate.sh` is:

    ```sh
    #!/bin/sh
    case "${1:-}" in --check) [ -f override.cfg ] ;; *) exit 0 ;; esac
    ```
  - `lanes_repo NAME`: `git init -b main`, then commit `project.godot`, `addons/gut/gut_cmdln.gd`, `tests/unit/{a,b,c,d}.gd`, `web-tools/tests/{a,b}.test.ts` and the node stubs. Then `sh $BIN/studio-state init` and write `$LR/.studio/config.json` = `{"engine": "godot4", "gate_short_lane": "on"}`.
  - `lanes_wt NAME [on|off]`: `git -C $LR worktree add -q "$LR-wt/NAME" -b "b-NAME"`. It writes `.studio/config.json` with `gate_short_lane` per the argument (default on) and `touch override.cfg` (isolation in effect for the stub). The name may hold a space, so quote it.
  - `lanes_bg TAG DIR -- CMD…`: `( cd DIR && LANES_TAG=TAG "$@" ) > $TMP/out.TAG 2> $TMP/err.TAG; echo $? > $TMP/rc.TAG &`.
  - `lanes_wait_mark` and `lanes_wait_file` poll at 0.1 s for at most 30 s, then `_fail`.
  - `lanes_overlap A B` reads the marks file's line order: yes iff `s A` comes before `e B` and `s B` comes before `e A`.
  - Calls go through the real `sh "$BIN/studio-test" --file tests/unit/a.gd` (a GUT short), the real `sh "$BIN/studio-test"` (a suite), `sh "$BIN/studio-gate" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts` from `web-tools` (a node short), and `sh "$BIN/studio-gate" x -- sh -c '…'` (exclusive). The exclusive form writes the same marks itself.
- [ ] **Step 2: Write the failing suite `tests/gate_lanes_test.sh`.** Every order is event-driven: hold, wait for a mark or a `gate: waiting` line, then release.
  - `test_lanes_beside_shareable`:
    - a suite in wt A holds;
    - a GUT short in wt B completes while it holds;
    - `lanes_overlap suite short` = yes;
    - B's row (`gt_row`) has lane `short`, class `short`, wait ≤ 3;
    - the suite's row has class `shareable`.
  - `test_lanes_never_beside_exclusive`:
    - `x -- sh -c` holds;
    - a GUT short in B prints `; short lane: beside exclusive` and waits;
    - release → overlap = no;
    - B's row has lane `main:beside-exclusive`.
  - `test_lanes_drain_and_no_starvation`:
    - S1 (vitest in B) takes the slot;
    - exclusive X waits, and `gate.wantx/<X pid>` exists;
    - S2 (GUT short in C) arrives and prints `exclusive waiting`;
    - release S1 → X starts before S2;
    - release X → S2 runs;
    - the marks order is `s S1, e S1, s X, e X, s S2`;
    - X overlaps nothing.
  - `test_lanes_three_way_never_overlaps_exclusive`:
    - 2 exclusive, 2 suites (wt A, B) and 3 shorts (B, C, vitest), each with `LANES_SLEEP=1`, started together;
    - no exclusive interval overlaps any other, and all 7 ran;
    - ruling `out (d) order only; 1 s holds, no upper bound`.
  - `test_lanes_same_worktree_gut_goes_main`: a suite in A plus a GUT short in A → reason `same worktree`, lane `main:same-worktree`, no overlap.
  - `test_lanes_node_beside_suite_same_worktree`: a suite in A plus a vitest from `A/web-tools` → overlap yes, lane `short` (O14).
  - `test_lanes_second_node_same_worktree_waits`:
    - a suite holds in another wt and vitest V1 (A) holds the slot;
    - V2 from A prints `same worktree`;
    - V2 cannot take main either (the suite holds it), so it waits;
    - after V1 releases, V2 runs, and it never overlaps V1.
  - `test_lanes_isolation_needed_for_gut`: `rm A-wt/B/override.cfg` → a GUT short in B prints `; short lane: iso`, while a vitest in B takes the slot.
  - `test_lanes_load_gate`:
    - `STUDIO_GATE_LOADAVG=99` → a short beside a suite prints `; short lane: load 99/8`;
    - `=abc` → `load ?/8`;
    - `=0` → the slot;
    - `STUDIO_GATE_PHYS_CORES=2 STUDIO_GATE_LOADAVG=5` → refused (`5/4`).
  - `test_lanes_nice_only_in_slot`: compare against the test shell's `ps -o nice= -p $$`:
    - the slot run's mark nice = base + 10;
    - a suite (main), and a short that took main (`same worktree`), each have nice = base.
  - `test_lanes_lane_off_is_today`:
    - every worktree is `off`;
    - a GUT short waits behind a suite (no overlap);
    - stderr matches exactly `^gate: waiting for studio-test (pid [0-9]*)$`, with no `; short lane`;
    - rows: lane `main:off` for the short and `main` for the suite, both class `exclusive`;
    - `ls $LR/.studio` gains no `gate.short`.
  - `test_lanes_mixed_lane_off_waiter_waits_for_drain` (Review Focus 4):
    - vitest (wt B, on) holds the slot;
    - a GUT short from wt C (off) waits while main is free, and its stderr names `(pid <p>, short lane)`;
    - it runs only after the slot is released;
    - no overlap.
  - `test_lanes_run_fallback_turns_lane_on`: a story wt with no config plus `STUDIO_START_DIR=$LR` (lane on) → the slot is used. With it unset → `main:off`.
  - `test_lanes_stale_slot_reclaimed`. A `gate.short/` with each of these is reclaimed (the short runs in the slot):
    - a dead pid (999999);
    - no pid;
    - the live pid of a `sleep 30 &` that is not a gate (D10);
  - `test_lanes_dead_wantx_ignored`: `gate.wantx/999999` → the short takes the slot, and the file is removed.
  - `test_lanes_classless_main_blocks_slot` (D11): plant `gate.lock/{pid,who}` with the pid of a live `sleep 30` and no `class` → the short prints `beside exclusive` and waits. Kill the sleep → it proceeds.
  - `test_lanes_reentry_under_slot`: the vitest stub calls `sh $GATE inner -- true` inside its run (`LANES_NEST=1` in the stub) → no `gate: waiting`, and exactly one row.
  - `test_lanes_signal_in_slot`: TERM the slot gate pid (from `gate.short/pid`) → exit 143, `gate.short` is gone, and only one `s` mark (no re-run).
  - `test_lanes_unit_registration_in_slot`: `STUDIO_UNIT_TAG=u1` → `gate.units/u1/<gate pid>` holds the child pid. TERM to the gate (as `unit_reap` sends) ends it with 143, and the entry is removed.
  - `test_lanes_waiting_messages`:
    - the prefix `^gate: waiting for [^ ]* (pid [0-9]*` is unchanged;
    - the reason is printed on the first poll, before any 60 s tick: the line appears within 2 s, with ruling `in (a)`;
    - an exclusive caller blocked only by the slot prints `(pid <p>, short lane)`;
    - with `since` planted 400 s in the past on a live slot holder, the line has `(short lane past its cap — stuck?)`.
  - `test_lanes_rows_record_lane_and_class`: one row each for suite, slot, main-short and exclusive, with their field 6/7 values.
  - `test_lanes_space_in_worktree_path` (Review Focus 1): `lanes_wt "w b"` → the slot is used and `gate.short/wt` is that path; a same-wt GUT short from it goes to main.
  - Rulings: every test that sleeps or waits with a bound gets an `in`/`out` ruling. Only `test_lanes_waiting_messages` is `TESTS_EXCLUSIVE`.
- [ ] **Step 3: Run it and see it fail.** Run `sh <R> <W>/tests/gate_lanes_test.sh`. Expected: FAIL (no slot).
- [ ] **Step 4: Implement.** The state and admission code below is exact. Use it as written.

  ```sh
  LOCK="$ROOT/.studio/gate.lock"
  MUTEX="$LOCK.mutex"
  SLOT="$ROOT/.studio/gate.short"
  WANTX="$ROOT/.studio/gate.wantx"
  DEMOTE="$ROOT/.studio/gate.short.demote.$$"
  …
  alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
  lock_pid() { cat "$LOCK/pid" 2>/dev/null; }
  rd() { cat "$1/$2" 2>/dev/null; }
  # live_gate PID — D10: alive and its ps args name a studio-gate script, so a
  # reused pid never wedges the slot. An empty ps read counts as live: a failed
  # read must never reclaim a live holder.
  live_gate() {
    alive "$1" || return 1
    _lg="$(ps -o args= -p "$1" 2>/dev/null)"
    [ -n "$_lg" ] || return 0
    printf '%s\n' "$_lg" | awk '{ exit !($1 ~ /(^|\/)studio-gate$/ || $2 ~ /(^|\/)studio-gate$/) }'
  }

  # Re-entry: the caller holds either lane through us.
  if [ -n "${STUDIO_GATE_HELD:-}" ] && alive "$STUDIO_GATE_HELD" \
     && { [ "$(lock_pid)" = "$STUDIO_GATE_HELD" ] || [ "$(rd "$SLOT" pid)" = "$STUDIO_GATE_HELD" ]; }; then
    exec "$@"
  fi

  # Static facts (§7): computed once, never per poll.
  _gc="$(gate_classify "$@")"; ARGV_CLS="${_gc% *}"; KIND="${_gc#* }"
  WT="$(gate_wt)"
  LANE_ON=0; [ "$(studio_cfg gate_short_lane)" = on ] && LANE_ON=1
  CLS="$(gate_effective "$ARGV_CLS" "$LANE_ON")"
  ISO=1; MODE=main
  if [ "$CLS" = short ]; then
    MODE=any
    if [ "$KIND" = godot ]; then sh "$SELF_DIR/studio-dispatch" isolate --check >/dev/null 2>&1 || ISO=0; fi
  fi
  OWNED=0; OWN_DIR=""; LANE=""; REASON=""; DEMOTED=0; SHORT_SECS=300
  BLK_WHO=""; BLK_PID=""; BLK_NOTE=""; BLK_STUCK=""

  # try_admit — one attempt, under the mutex (§7 Admission). 0: we hold LANE
  # (main|short) in OWN_DIR. 1: not admitted; REASON is a short caller's refusal
  # and BLK_* name what the waiting line reports.
  try_admit() {
    mutex_take || return 1
    BLK_WHO=""; BLK_PID=""; BLK_NOTE=""; BLK_STUCK=""; REASON=""
    if [ -d "$LOCK" ]; then _h="$(rd "$LOCK" pid)"; if [ -z "$_h" ] || ! alive "$_h"; then rm -rf "$LOCK"; fi; fi
    if [ -d "$SLOT" ]; then _h="$(rd "$SLOT" pid)"; if [ -z "$_h" ] || ! live_gate "$_h"; then rm -rf "$SLOT"; fi; fi
    _xw=""
    for _f in "$WANTX"/* "$ROOT/.studio"/gate.short.demote.*; do
      [ -f "$_f" ] || continue
      case "$_f" in "$WANTX"/*) _p="${_f##*/}" ;; *) _p="${_f##*.}" ;; esac
      [ "$_p" = "$$" ] && continue
      if ! live_gate "$_p"; then rm -f "$_f"
      elif [ -z "$_xw" ]; then case "$_f" in "$WANTX"/*) _xw="$_p" ;; esac; fi
    done
    _mp="$(rd "$LOCK" pid)"; _sp="$(rd "$SLOT" pid)"; _mc=""; _same=0
    if [ -n "$_mp" ]; then
      _mc="$(rd "$LOCK" class)"; _mc="${_mc:-exclusive}"            # D11
      [ "$(rd "$LOCK" wt)" != "$WT" ] || [ "$(rd "$LOCK" kind)" != "$KIND" ] || _same=1
    fi
    if [ -n "$_sp" ]; then
      [ "$(rd "$SLOT" wt)" != "$WT" ] || [ "$(rd "$SLOT" kind)" != "$KIND" ] || _same=1
    fi
    _lane=""
    if [ "$CLS" = exclusive ]; then
      [ -n "$_mp" ] || [ -n "$_sp" ] || _lane=main
    else
      if [ "$MODE" = any ]; then
        if [ "$ISO" = 0 ]; then REASON=iso
        elif [ -n "$_xw" ]; then REASON="exclusive waiting"
        elif [ -n "$_mp" ] && [ "$_mc" != shareable ] && [ "$_mc" != short ]; then REASON="beside $_mc"
        elif [ "$_same" = 1 ]; then REASON="same worktree"
        elif [ -n "$_sp" ]; then REASON="slot busy"
        elif ! _ld="$(gate_load_ok)"; then REASON="load $_ld"
        else _lane=short; fi
      fi
      if [ -z "$_lane" ] && [ -z "$_mp" ] && [ "$_same" = 0 ] && [ -z "$_xw" ]; then _lane=main; fi
    fi
    if [ -n "$_lane" ]; then
      if [ "$_lane" = main ]; then _d="$LOCK"; else _d="$SLOT"; fi
      if mkdir "$_d" 2>/dev/null; then
        printf '%s\n' "$$" > "$_d/pid"; printf '%s\n' "$WHO" > "$_d/who"; printf '%s\n' "$TAG" > "$_d/unit"
        if [ "$_lane" = short ]; then echo short; else printf '%s\n' "$CLS"; fi > "$_d/class"
        printf '%s\n' "$KIND" > "$_d/kind"; printf '%s\n' "$WT" > "$_d/wt"; date +%s > "$_d/since"
        OWNED=1; OWN_DIR="$_d"; LANE="$_lane"; rm -f "$WANTX/$$"
        mutex_drop; return 0
      fi
    fi
    if [ "$CLS" = exclusive ] && [ ! -f "$WANTX/$$" ]; then
      mkdir -p "$WANTX" 2>/dev/null && printf '%s %s\n' "$(date +%s)" "$WHO" > "$WANTX/$$"
    fi
    if [ -n "$_mp" ]; then BLK_WHO="$(rd "$LOCK" who)"; BLK_PID="$_mp"
    elif [ -n "$_sp" ]; then BLK_WHO="$(rd "$SLOT" who)"; BLK_PID="$_sp"; BLK_NOTE=", short lane"
      _ss="$(rd "$SLOT" since)"
      case "$_ss" in ''|*[!0-9]*) ;; *) [ $(( $(date +%s) - _ss )) -le $((SHORT_SECS + 60)) ] \
        || BLK_STUCK=" (short lane past its cap — stuck?)" ;; esac
    elif [ -n "$_xw" ]; then BLK_WHO="$(cut -d' ' -f2- "$WANTX/$_xw" 2>/dev/null)"; BLK_PID="$_xw"; BLK_NOTE=", reserved"
    fi
    mutex_drop; return 1
  }
  # lane_release — give back our lane (a rename aside, as before #71).
  lane_release() {
    [ -z "${TIMER:-}" ] || kill "$TIMER" 2>/dev/null; TIMER=""
    mutex_drop
    if [ "$OWNED" = 1 ] && [ -n "$OWN_DIR" ] && [ "$(rd "$OWN_DIR" pid)" = "$$" ]; then
      mv "$OWN_DIR" "$OWN_DIR.gone.$$" 2>/dev/null && rm -rf "$OWN_DIR.gone.$$"
    fi
    OWNED=0; OWN_DIR=""
  }
  release() {
    lane_release; rm -f "$WANTX/$$" "$DEMOTE"
    if [ -n "$REG" ]; then rm -f "$REG/$$"; rmdir "$REG" 2>/dev/null; fi
  }
  ```

  - **The wait loop.** It replaces :219-226 and the rest of the main flow. The `REASON`/`SAID` rule prints a refused short caller's line on its first poll:

    ```sh
    row_lane() {
      if [ "$LANE" = short ]; then echo short
      elif [ "$DEMOTED" = 1 ]; then echo main:demoted
      elif [ "$CLS" = short ]; then printf 'main:%s\n' "$(printf '%s' "$LAST_REASON" | sed 's/ [0-9?].*//; s/ /-/g')"
      elif [ "$ARGV_CLS" = short ]; then echo main:off
      else echo main; fi
    }
    while :; do
      T_REQ="$(date +%s)"; waited=0; SAID=0
      until try_admit; do
        [ -z "$REASON" ] || LAST_REASON="$REASON"
        if [ $((waited % (60 * GATE_TPS))) -eq 0 ] || { [ -n "$REASON" ] && [ "$SAID" = 0 ]; }; then
          [ -n "$BLK_PID$BLK_WHO" ] || { BLK_WHO="$(rd "$LOCK" who)"; BLK_PID="$(lock_pid)"; }
          printf 'gate: waiting for %s (pid %s%s)%s%s\n' "$BLK_WHO" "$BLK_PID" "$BLK_NOTE" "$BLK_STUCK" \
            "${REASON:+; short lane: $REASON}" >&2
          [ -z "$REASON" ] || SAID=1
        fi
        waited=$((waited + 1)); sleep "$GATE_POLL"
      done
      [ "$LANE" = short ] || [ -n "$LAST_REASON" ] || LAST_REASON="$REASON"
      WAIT_S=$(( $(date +%s) - T_REQ ))
      run_once "$@"
      ROW_RC="${SIGSTATUS:-$rc}"
      gate_scrub
      gate_times_append "$ROOT/.studio/gate.times" "$(date +%s)" "$WHO" "$HOLD_S" "$ROW_RC" "$WAIT_S" \
        "$(row_lane)" "$([ "$LANE" = short ] && echo short || echo "$CLS")" "${TAG:--}"
      if [ "$DEMOTED" = 0 ] && lane_after_run; then lane_release; DEMOTED=1; MODE=main; continue; fi
      break
    done
    release
    exit "$ROW_RC"
    ```

    A short caller that gets main while `REASON` is `slot busy` records `main:slot-busy`. `LAST_REASON` is the refusal of the poll that admitted it. When main is free at the very first poll, `try_admit` returns 0 with `REASON` already set by the same evaluation, and the line after the loop catches it. Make `try_admit` leave `REASON` set on a main-lane admission. The code above does this, because `REASON` is set before `_lane=main`.
  - **`run_once CMD…`** is today's :231-285, moved into a function, with five changes:
    1. It resets `rc=0 SIGSTATUS="" CAPPED=0 SHORT_CAPPED=0 TARGETS="" TIMER=""` and calls `lane_cap` first.
    2. The timer uses `$ATT_SECS` in place of `$CAP_SECS`, and `trap on_cap ALRM` is set when `ATT_SECS` is non-empty.
    3. The launch is `STUDIO_GATE_HELD="$$" STUDIO_GATE_LANE=short STUDIO_GATE_DEMOTE="$DEMOTE" nice -n 10 "$@" &` in the slot, and `STUDIO_GATE_HELD="$$" STUDIO_GATE_LANE=main "$@" &` in main.
    4. It writes the `REG` child pid each attempt.
    5. It ends with `HOLD_S=$(( $(date +%s) - T0 ))`.
  - **`on_cap`** becomes `if [ "$RUNNING" = 1 ] && alive "$CHILD"; then if [ "$ATT_SHORT" = 1 ]; then SHORT_CAPPED=1; else CAPPED=1; fi; on_signal 124; fi`.
  - **The two stub blocks** with their markers (Interfaces).
  - **Header :10-26.** Describe the main lane, the slot, `gate.wantx`, D10/D11, the child env vars, and `--classify`. The knob lines at :5-9 stay within the first 30 lines.
- [ ] **Step 5: Run it and see it pass.**
  - `sh <R> <W>/tests/gate_lanes_test.sh`;
  - `sh <R> <W>/tests/toolkit_test.sh` (every pre-#71 gate test unchanged and green);
  - `sh <R> <W>/tests/gate_times_test.sh`;
  - `sh <R> <W>/tests/gate_class_test.sh`;
  - `sh <R> <W>/tests/studio_setup_test.sh`;
  - `sh <R> <W>/tests/harness_test.sh`;
  - `TEST_SH` portability: `sh <R> --args /bin/sh -c 'command -v dash >/dev/null && TMPDIR="$TMPDIR" dash <W>/tests/gate_lanes_test.sh'` (when dash exists).
- [ ] **Step 6: Commit** `feat(T7): studio-gate short slot beside a shareable suite — admission under the mutex, D5/D10/D11`.

### Task 8: `user://` isolation (`isolate.sh`) — Risky (W2)

**Files:**
- Create: `studios/game-dev/engines/godot/isolate.sh` (executable), `tests/isolate_test.sh`
- Modify:
  - `bin/studio-dispatch` (a `--has VERB` mode before `verb=` handling, :16-18);
  - `bin/studio-test` (the isolate call between :36 and :37).

**Interfaces:**
- Consumes: from T3, `engines/godot/cfg.sh` `studio_cfg`.
- Produces:
  - `studio-dispatch --has VERB` → exit 0 iff the current engine's adapter `VERB.sh` exists. It is silent on every path, with exit 1 otherwise.
  - `isolate.sh` (ensure) → always exit 0.
  - `isolate.sh --check` → 0 when isolation is in effect, 1 otherwise. It writes nothing.
  - `isolate.sh --scrub` → 0 when clean or not applicable; 3 when it removed lines (stdout: the keys, `, `-joined); 1 on an error.
  - `isolate.sh --leaks DIR` → 0 for none; 3 when found (stdout: one `<path>: <keys>` per file); 1 on an error. It never writes.
  - The patterns, an ERE with no intervals:
    - `LANES_USE_RE='^config/use_custom_user_dir='`;
    - `LANES_NAME_RE='^config/custom_user_dir_name="[^"]*-lanes(-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])?/[^"]*"[[:space:]]*$'`.

**Rules (exact):**
- **Opted in:** `studio_cfg user_dir` = `per-worktree`.
- **Linked:** `git rev-parse --path-format=absolute --git-dir` ≠ `--git-common-dir`.
- **`<id>`** = the basename of the git-dir.
- **`<project>`** = `config/name` from `project.godot`, `sed 's/[^A-Za-z0-9._-]//g'`; empty, `.` or `..` gives `godot-project`.
- **`<h8>`** = `printf '%s' "$gcd" | cksum | awk '{ printf "%08x", $1 }'` (B7: two clones never share or sweep each other's dir).
- **The name** is `<project>-lanes-<h8>/<id>`. The file:

  ```
  ; omega-ai studio-test: per-worktree user:// (#71). Generated; never commit.
  [application]
  config/use_custom_user_dir=true
  config/custom_user_dir_name="<project>-lanes-<h8>/<id>"
  ```
- **The marker** is line 1 exactly. `override.cfg` is ours iff its line 1 is the marker.
- **Ensure writes** only when opted in, linked, `project.godot` present in cwd, `override.cfg` absent or ours, and `git ls-files --error-unmatch override.cfg` failing. It rewrites only when the content differs. It adds `/<rel>/override.cfg` (rel = cwd relative to the top level; `/override.cfg` at the top) to `<gcd>/info/exclude` once (`grep -qxF`). A foreign or tracked file → one stderr note, `studio-test: override.cfg here is not studio-test's (or is tracked) — user:// stays shared; GUT short checks use the main lane`, and no write.
- **Start-scrub.** After a successful ensure, run the scrub. When it removes lines, print `studio-test: project.godot carried the per-worktree user:// setting (<keys>) — removed before the run` on stderr and continue.
- **The sweep** runs after a successful ensure only, at most daily.
  - The stamp is `<STATE_ROOT>/.studio/gate.isolate-sweep`, with STATE_ROOT = `git worktree list --porcelain | sed -n '1s/^worktree //p'`. It sweeps when the stamp is absent or `find <stamp> -mtime +0` prints. It never sweeps when `<STATE_ROOT>/.studio` is missing.
  - The data root is `$STUDIO_GODOT_USER_ROOT`, which also marks the platform known. Otherwise, on Darwin, it is `$HOME/Library/Application Support`. Otherwise there is no sweep.
  - Within `<root>/<project>-lanes-<h8>/`, it removes a child `c` only when all of these hold:
    - `[ -d "$c" ] && [ ! -L "$c" ]`;
    - its parent is exactly that dir;
    - its basename is not in `ls "$gcd/worktrees"`;
    - `find "$c" -prune -mmin +60` prints it.
  - Then it touches the stamp.
- **`--check`** passes only when all of these hold:
  - the platform is known (Darwin or the seam);
  - the worktree is linked;
  - `override.cfg` equals the expected content byte for byte (`cmp`);
  - `project.godot` has no `LANES_USE_RE` line.
- **`--scrub`** applies only when the worktree is opted in and linked. The lines are those of cwd's `project.godot` that match either pattern and are absent from `git show HEAD:./project.godot` (`grep -qxF`). It deletes exactly those lines (awk exact-line filter to a temp file, then `cat temp > project.godot` to keep the mode) and prints the keys. A `project.godot` not tracked in HEAD → 0.
- **`--leaks DIR`.** For each `git -C DIR ls-files -- project.godot '*/project.godot'`, the candidate lines are those in `git show :<p>` or the working-tree file, minus HEAD's. `LANES_NAME_RE` always counts. `LANES_USE_RE` counts only when `<dir of p>/override.cfg` is ours (marker), so a project's own custom user dir is not refused.
- The header names `STUDIO_GODOT_USER_ROOT` (test-only) in its first 40 lines.

- [ ] **Step 1: Write the failing suite `tests/isolate_test.sh`.**
  - Fixture `iso_repo NAME`:
    - `git init`;
    - commit `project.godot` (`[application]\nconfig/name="Stub Game"\n`), then `studio-state init`;
    - `iso_wt NAME` = a linked worktree with `.studio/config.json` `{"engine": "godot4", "user_dir": "per-worktree"}`.
  - Every test exports `STUDIO_GODOT_USER_ROOT=$TMP/ud-<test>` and `OMEGA_STUDIO_ROOT=$REPO_ROOT/studios/game-dev`. `ISO` = the real `isolate.sh`.
  - Tests:
    - `test_isolate_writes_in_opted_linked_worktree`:
      - the file equals the 4 lines, with name `StubGame-lanes-<h8>/<id>`;
      - `<h8>` matches `^[0-9a-f]{8}$` (grep -E);
      - `<id>` = `basename "$(git rev-parse --git-dir)"`;
      - `git status --porcelain` is empty (excluded).
    - `test_isolate_never_in_main_checkout`: with the key in the main checkout → no `override.cfg`.
    - `test_isolate_needs_the_key`: no key → no file.
    - `test_isolate_run_fallback_key`: the story worktree has no config and `STUDIO_START_DIR` = a dir with the key → written; unset → not.
    - `test_isolate_leaves_foreign_override`: `override.cfg` = `[x]\n` → byte-identical after, plus the stderr note.
    - `test_isolate_leaves_tracked_override`: a committed `override.cfg` carrying the marker → untouched.
    - `test_isolate_rewrites_ours_on_rename`: change `config/name` → the file is rewritten with the new name.
    - `test_isolate_exclude_once`: three runs → `grep -c '^/override.cfg$' <gcd>/info/exclude` = 1. A project in a subdir `game/` → `/game/override.cfg`.
    - `test_isolate_check`:
      - passes after ensure;
      - fails when the file is absent, foreign, or names another `<id>`;
      - fails when `project.godot` has `config/use_custom_user_dir=true`;
      - fails in the main checkout.
    - `test_isolate_check_refuses_unknown_platform`: `STUDIO_GODOT_USER_ROOT` unset with `uname` stubbed to `Linux` on PATH → exit 1.
    - `test_isolate_sweep_dead_old_only`:
      - in `<root>/StubGame-lanes-<h8>/`: `live` (this worktree's id), `dead-old` (`touch -t 202601010000`), `dead-new`, a regular file `f`, and a symlink `ln` → another dir with an old mtime;
      - only `dead-old` goes, and the symlink target survives.
    - `test_isolate_sweep_daily_stamp`: with a fresh stamp → nothing is removed; with the stamp `touch -t` 2 days back → sweep.
    - `test_isolate_sweep_paths_with_spaces` (Review Focus 1): `STUDIO_GODOT_USER_ROOT="$TMP/App Support"` → the sweep and write work, and nothing outside it changes.
    - `test_isolate_hash_keys_the_clone`: two clones of one origin → different `<h8>`, and clone A's sweep never touches clone B's lanes dir.
    - `test_isolate_start_scrub`: append the two lanes lines to `project.godot` (uncommitted) → ensure removes them, prints its line, exits 0.
    - `test_isolate_scrub_modes`:
      - lines HEAD lacks are removed (exit 3, stdout `config/use_custom_user_dir, config/custom_user_dir_name`) and the other edits stay;
      - lines committed in HEAD → exit 0, untouched;
      - a lane-off worktree and the main checkout → exit 0, untouched.
    - `test_isolate_leaks_lists`:
      - a staged name line → 3;
      - a working-tree-only use line with our override.cfg → 3, and without it → 0;
      - HEAD has both → 0.
    - `test_dispatch_has_verb`: `studio-dispatch --has isolate` → 0; `--has nosuch` → 1, silent; an unknown engine config → 1, silent.
    - `test_studio_test_calls_isolate`: in an opted-in wt with no GUT, `studio-test` exits 3, and `override.cfg` was written.
    - `test_cfg_parity`: `awk '/^# cfg-begin/,/^# cfg-end/'` over `bin/gate-class.sh` and over `engines/godot/cfg.sh` → identical.
- [ ] **Step 2: Run it and see it fail.** Run `sh <R> <W>/tests/isolate_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement `isolate.sh`, `--has` and the studio-test call.**
  - studio-test, between :36 and :37: `sh "$(dirname "$0")/studio-dispatch" --has isolate && sh "$(dirname "$0")/studio-dispatch" isolate`. Its status is ignored; it never blocks the run.
  - studio-dispatch `--has` runs the same root/engine/adapter resolution with every message suppressed and exits 0/1 (B8: no `no adapter` line for other engines).
- [ ] **Step 4: Run it and see it pass.** Run `sh <R> <W>/tests/isolate_test.sh`, `sh <R> <W>/tests/toolkit_test.sh` (studio-test still green: fresh projects are not linked worktrees, so isolate is a no-op) and `sh <R> <W>/tests/studio_test.sh test_bin_syntax`.
- [ ] **Step 5: Commit** `feat(T8): per-worktree user:// via override.cfg (isolate.sh) with scrub, leaks and daily sweep`.

### Task 9: The short cap, the demote hand-off, the import demote — Risky (W3)

**Files:**
- Modify:
  - `bin/studio-gate`: the header knob lines :5-12 (add `STUDIO_GATE_SHORT_SECONDS (default 300) — the short slot's cap in seconds`), the `SHORT_SECS=` line, and the `# ---- short cap and demote (T9) ----` block;
  - `engines/godot/import.sh` (`import_needed` after `import_class_cache_missing`);
  - `engines/godot/test.sh`, between :88 (`. "$HERE/import.sh"`) and :89 (`ensure_import`).
- Test: `tests/gate_lanes_test.sh` (append section `# ---- short cap and demote (T9)`), `tests/toolkit_test.sh` (two tests before :793, plus one continuation line)

**Interfaces:**
- Consumes: from T7, `LANE`, `CAP_SECS`, `SIGSTATUS`, `SHORT_CAPPED`, `DEMOTE`, `ATT_SECS`/`ATT_SHORT`, the stub signatures, and the fixture.
- Produces: `import_needed PROJECT` → 0 when `ensure_import` would import (no `.godot/`, a missing product, or no class cache).

- [ ] **Step 1: Write the failing tests.**
  - In gate_lanes_test:
    - `test_lanes_short_cap_reruns_in_main`:
      - `STUDIO_GATE_SHORT_SECONDS=2`, a vitest stub with `LANES_SLEEP=5 LANES_RC=3` beside a held suite;
      - stderr has `gate: vitest ran past the short lane's 5 min — stopped; running it again in the main lane`;
      - two `s` marks, the second with lane `main`;
      - rows: `vitest … 124 … short short` and then `… 3 … main:demoted short`;
      - exit 3.
      - It is `TESTS_EXCLUSIVE`, with ruling `in (a) a 2 s cap must fire on a 5 s run`.
    - `test_lanes_short_cap_under_run_cap_is_124`: `STUDIO_GATE_MINUTES=1 STUDIO_GATE_SECONDS=1 STUDIO_GATE_SHORT_SECONDS=2` → exit 124, one `s` mark, and the row is `124 … short`. Exclusive, ruling `in (a)`.
    - `test_lanes_short_cap_production_default`:
      - grep `STUDIO_GATE_SHORT_SECONDS:-300` in studio-gate;
      - a `LANES_SLEEP=2` slot run with the seam unset → rc 0, one `s` mark, lane `short`;
      - ruling `out (d) a 2 s run under a 300 s cap`.
    - `test_lanes_demote_reruns_once`:
      - `LANES_DEMOTE=import` on a GUT short beside a suite;
      - stderr `gate: studio-test-file needs the main lane (import) — waiting for it`;
      - rows `… 1 … short` then `… main:demoted`;
      - the rerun's mark has lane `main` and no demote file is left.
    - `test_lanes_demoted_rerun_cannot_demote`: the rerun's env has no `STUDIO_GATE_DEMOTE` (the stub records `${STUDIO_GATE_DEMOTE:-none}`), so exactly two runs happen.
    - `test_lanes_short_cap_term_ignorer` (Review Focus 5):
      - `LANES_TRAP=1 LANES_SLEEP=30 STUDIO_GATE_SHORT_SECONDS=2`;
      - the first child's pid (from its mark line, added as field 5 `$$` (`s tag lane nice pid demote pwd…`)) is dead before the second `s` mark is written;
      - exclusive, ruling `in (a) the KILL must land inside the 10-15 s straggler window`.
    - `test_lanes_demote_then_signal_no_rerun`: the stub touches demote and then sleeps. TERM the gate → exit 143, one run, and the demote file is removed.
  - In toolkit_test:
    - `test_test_demotes_an_import_in_the_short_lane`:
      - `P` with no `.godot/`; `sleep 30 &` gives `_g`;
      - `( cd "$P" && GODOT_PATH="$GODOT_STUB" STUDIO_GATE_HELD=$_g STUDIO_GATE_LANE=short STUDIO_GATE_DEMOTE="$TMP/d.$_g" sh "$STUDIO/engines/godot/test.sh" )` → exit 1;
      - `$TMP/d.$_g` holds `import`;
      - there is no `--import` args line in the log.
    - `test_test_stale_demote_env_imports` (Review Focus 3): the same, but `STUDIO_GATE_HELD` is a dead pid (or the suffix differs) → it imports and runs as usual, and no demote file is written.
- [ ] **Step 2: Run them and see them fail.** Run `sh <R> <W>/tests/gate_lanes_test.sh` and `sh <R> <W>/tests/toolkit_test.sh test_test_demotes_an_import_in_the_short_lane test_test_stale_demote_env_imports`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `SHORT_SECS="$(decimal "${STUDIO_GATE_SHORT_SECONDS:-300}")"`. A non-digit value gives 300.
  - The T9 block:

    ```sh
    # lane_cap — this attempt's cap. In the slot the 5-min cap binds unless the
    # run cap is no longer (STUDIO_GATE_MINUTES <= 5): then 124, as today (D4).
    lane_cap() {
      ATT_SECS="$CAP_SECS"; ATT_SHORT=0
      if [ "$LANE" = short ] && { [ -z "$CAP_SECS" ] || [ "$CAP_SECS" -gt "$SHORT_SECS" ]; }; then
        ATT_SECS="$SHORT_SECS"; ATT_SHORT=1
      fi
    }
    # lane_after_run — 0 when this slot attempt is re-run once in the main lane:
    # the short cap stopped it, or the child asked through $STUDIO_GATE_DEMOTE.
    # A signal (128+n) is never re-run.
    lane_after_run() {
      [ "$LANE" = short ] || return 1
      _la_why=""
      if [ -f "$DEMOTE" ]; then
        _la_why="$(head -n 1 "$DEMOTE" 2>/dev/null | tr -cd 'A-Za-z0-9 ._:/-' | cut -c1-80)"; rm -f "$DEMOTE"
      fi
      if [ "$SHORT_CAPPED" = 1 ] && [ "$SIGSTATUS" = 124 ]; then
        printf "gate: %s ran past the short lane's 5 min — stopped; running it again in the main lane\n" "$WHO" >&2
        return 0
      fi
      [ -z "$SIGSTATUS" ] || return 1
      [ -n "$_la_why" ] || return 1
      printf 'gate: %s needs the main lane (%s) — waiting for it\n' "$WHO" "$_la_why" >&2
      return 0
    }
    ```

    An empty demote file still demotes, with reason `no reason given`. Handle it with a flag, not with `_la_why` emptiness.
  - test.sh:

    ```sh
    if [ "${STUDIO_GATE_LANE:-}" = short ] && [ -n "${STUDIO_GATE_HELD:-}" ] \
       && [ "${STUDIO_GATE_DEMOTE:-}" != "${STUDIO_GATE_DEMOTE%".$STUDIO_GATE_HELD"}" ] \
       && kill -0 "$STUDIO_GATE_HELD" 2>/dev/null && import_needed "$PROJECT"; then
      printf 'import\n' > "$STUDIO_GATE_DEMOTE"
      echo "studio-test: the import cache needs an import — handing this run to the main lane" >&2
      exit 1
    fi
    ```
- [ ] **Step 4: Run them and see them pass.** Rerun the Step 2 commands, then the whole `gate_lanes_test.sh`, `toolkit_test.sh` and `harness_test.sh`.
- [ ] **Step 5: Commit** `feat(T9): short slot 5-min cap re-runs in the main lane; demote hand-off; import demote`.

### Task 10: The leak scrub in the gate — Risky (W3)

**Files:**
- Modify: `bin/studio-gate`, the `# ---- leak scrub (T10) ----` block only
- Test: `tests/isolate_test.sh` (append section `# ---- leak scrub in the gate (T10)`)

**Interfaces:**
- Consumes: from T7, `CLS`, `KIND`, `WT`, `ROW_RC`, `SELF_DIR`. From T8, `studio-dispatch --has`, and `isolate --scrub` with its exits 0/3/1.

- [ ] **Step 1: Write the failing tests.** All use an opted-in linked worktree from T8's fixture, `OMEGA_STUDIO_ROOT` = the real studio, and `sh $GATE x -- sh -c 'printf "config/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"StubGame-lanes-<h8>/<id>\"\n" >> project.godot'`.
  - `test_gate_scrub_removes_and_fails`:
    - exit 1;
    - stderr `gate: project.godot gained the per-worktree user:// setting (config/use_custom_user_dir, config/custom_user_dir_name) — removed; this run is not trusted`;
    - `git diff -- project.godot` has no lanes line;
    - the row rc is 1.
  - `test_gate_scrub_keeps_failing_status`: the same with `; exit 5` → exit 5, and the lines are removed.
  - `test_gate_scrub_leaves_head_keys`: HEAD has both lines → exit 0, untouched, and no message.
  - `test_gate_scrub_lane_off_and_main_untouched`: no `user_dir` key, and also the main checkout → lines kept and exit 0.
  - `test_gate_scrub_skips_node_short`: lane on (`gate_short_lane` on, `STUDIO_GATE_LOADAVG=0`), a `node_modules/.bin/vitest` stub that appends the lines, invoked in the slot form → exit 0 and the lines remain. That pins "except a node short check"; the commit guard still covers it.
  - `test_gate_scrub_error_fails_closed`: a stub studio root whose `isolate.sh --scrub` exits 1 → exit 1 and stderr `gate: the project.godot leak check failed (isolate --scrub exit 1) — this run is not trusted`.
- [ ] **Step 2: Run them and see them fail.** Run `sh <R> <W>/tests/isolate_test.sh`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement the T10 block.**

  ```sh
  # gate_scrub — O7: after every run in an opted-in linked worktree (isolate
  # decides), except a node short check, remove the lanes lines project.godot
  # gained and fail a passing run (exit 1; a failing status is kept).
  gate_scrub() {
    [ "$CLS" = short ] && [ "$KIND" = node ] && return 0
    ( cd "$WT" 2>/dev/null && sh "$SELF_DIR/studio-dispatch" --has isolate ) || return 0
    _gs_out="$(cd "$WT" && sh "$SELF_DIR/studio-dispatch" isolate --scrub 2>/dev/null)"; _gs_rc=$?
    case "$_gs_rc" in
      0) return 0 ;;
      3) printf 'gate: project.godot gained the per-worktree user:// setting (%s) — removed; this run is not trusted\n' "$_gs_out" >&2 ;;
      *) printf 'gate: the project.godot leak check failed (isolate --scrub exit %s) — this run is not trusted\n' "$_gs_rc" >&2 ;;
    esac
    [ "$ROW_RC" != 0 ] || ROW_RC=1
  }
  ```
- [ ] **Step 4: Run them and see them pass.** Run `sh <R> <W>/tests/isolate_test.sh`, `sh <R> <W>/tests/gate_lanes_test.sh` and `sh <R> <W>/tests/toolkit_test.sh`.
- [ ] **Step 5: Commit** `feat(T10): the gate scrubs a project.godot user:// leak before release and fails the run`.

### Task 11: The commit guard hook — Risky (W3)

**Files:**
- Create: `studios/game-dev/hooks/lanes-guard.sh` (executable)
- Modify: `studios/game-dev/hooks/hooks.json`. Add a PreToolUse entry with matcher `Bash` right after the `godot-guard.sh` entry (:51-59): `"command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/lanes-guard.sh\""`.
- Test: `tests/hook_test.sh` (new tests before its run_tests at :1136, plus their names)

**Interfaces:**
- Consumes: from T8, `engines/godot/isolate.sh --leaks DIR`, resolved as `$(dirname "$0")/../engines/godot/isolate.sh`. A missing file → exit 0.
- **Behaviour.** `trap 'exit 0' EXIT`. Prints nothing and exits 0 unless it denies.
  1. Fast path: the raw input contains no `git` or no `commit` → exit 0.
  2. Extract `cwd` (flat sed) and the `command` value (awk, unescaping `\"` and `\\`). Split the command at `;`, `&&`, `||`, `|` and newlines (`\n` in JSON).
  3. A segment `cd <p>` sets the dir for later segments. A segment `git` (or `*/git`) with options `-C <p>` (relative to the current dir), `-c <kv>` and `--no-pager`, followed by the subcommand `commit`, is a target.
  4. For each target: `top="$(git -C "$dir" rev-parse --show-toplevel)"`, then `sh "$ISO" --leaks "$top"`. Exit 3 → deny.
  5. The deny is `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<msg>"}}`, with `<msg>` = `game-dev: refused a commit: <path> gains the per-worktree user:// setting (<keys>) that HEAD lacks; merged, it would move user:// for every checkout. Run studio-dispatch isolate --scrub in that worktree, then commit.` The path and keys are JSON-escaped (`sed 's/\\/\\\\/g; s/"/\\"/g'`, as worktree-guard.sh:32 does).

- [ ] **Step 1: Write the failing tests.**
  - Helper `lg_in CWD CMD` → `{"session_id":"s","cwd":"<CWD>","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"<CMD>"}}`. `lanes_guard` runs the hook with exit-0 assertions, like `godot_guard` :874-878.
  - Fixture: an opted-in linked worktree with our override.cfg (written by running the real isolate), and a tracked `project.godot`.
  - Tests:
    - `test_lanes_guard_denies_commit_with_lanes_line`: stage a name line, then `git commit -m x` with cwd = the wt → denied, and the reason names `isolate --scrub`.
    - `test_lanes_guard_git_C_and_cd_forms`: from cwd `$TMP`, `git -C <wt> commit -m x` and `cd <wt> && git commit -m x` → both denied.
    - `test_lanes_guard_working_tree_am`: the line only in the working tree, then `git commit -am x` → denied.
    - `test_lanes_guard_allows_clean_and_head_keys`: no lanes line → allowed. The lines committed in HEAD → allowed.
    - `test_lanes_guard_ignores_other_commands`: `git status`, `echo commit`, `git log --grep commit` → no output.
    - `test_lanes_guard_malformed_input`: empty input, `{`, and a non-Bash tool → no output, exit 0.
    - `test_lanes_guard_registered`: hooks.json contains `CLAUDE_PLUGIN_ROOT}/hooks/lanes-guard.sh`. With jq present, its matcher is `Bash`.
    - `test_lanes_guard_message_is_valid_json`: with jq present, the deny output parses. A wt path with a space and a `"` in a commit message still gives valid JSON.
- [ ] **Step 2: Run them and see them fail.** Run `sh <R> <W>/tests/hook_test.sh test_lanes_guard_denies_commit_with_lanes_line test_lanes_guard_git_C_and_cd_forms test_lanes_guard_working_tree_am test_lanes_guard_registered`. Expected: FAIL.
- [ ] **Step 3: Implement the hook and register it.**
- [ ] **Step 4: Run it and see it pass.** Run `sh <R> <W>/tests/hook_test.sh` (whole), `sh <R> <W>/tests/studio_test.sh test_bin_syntax` and `sh <R> <W>/tests/install_test.sh` (the hooks snapshot).
- [ ] **Step 5: Commit** `feat(T11): lanes-guard refuses a commit that adds the per-worktree user:// lines`.

### Task 13: The synthetic benchmark probe — Mechanical (W3)

**Files:**
- Create: `tests/probes/gate_lane_bench.sh` (executable). It sources `tests/gate_lanes_fixture.sh`.

**Interfaces:** `gate_lane_bench.sh off|on|exclusive [HOLD_S]`. It needs an existing `TMPDIR` and refuses inside a git work tree or under `~/GameDev`. It prints `short p50 <s> p90 <s>`, `exclusive extra wait <s>`, and `PASS`/`FAIL` per spec §13.2.

- [ ] **Step 1: Write it.**
  - The fixture repo has the lane per mode and 3 linked worktrees.
  - The suite holder is `LANES_SLEEP=$HOLD_S` (default 180).
  - 20 short calls start every 5 s, round-robin across the worktrees: 10 `studio-test --file`, and 10 vitest stand-ins in the O10 form, each `LANES_SLEEP=3`.
  - The `exclusive` mode puts `x -- sh -c 'sleep 60'` in place of the suite holder, plus one exclusive caller arriving at t = 30 s while a short holds the slot (lane on).
  - It reads field 5 from `$LR/.studio/gate.times`.
  - Pass rules:
    - on: short p90 ≤ 5;
    - off: p50 ≥ 0.4 × HOLD_S (≈ the remaining hold);
    - exclusive: lane-on shorts wait behind the holder (p50 > 5), and the exclusive caller's extra wait ≤ `SHORT_SECS + 15`.
- [ ] **Step 2: Smoke-run it at a small hold.** Run `sh <R> --args <W>/tests/probes/gate_lane_bench.sh on 20` and `… off 20` → both print a verdict line. The full 180 s runs are acceptance 2 (manual).
- [ ] **Step 3: Commit** `test(T13): synthetic short-lane benchmark probe`.

### Task 12: Docs, floors and knob checks — Mechanical (W4)

**Files:**
- Modify:
  - `README.md` :149-151, :173-176, the Tests section :362-404 (the knobs line :399);
  - `studios/game-dev/engines/godot/GUIDE.md` :25 (the `test.sh` row) and the new `isolate.sh` row after :28;
  - `tests/run_all.sh` (the table :45-75);
  - `tests/harness_test.sh` :483 (and new `_need` lines).

- [ ] **Step 1: README.**
  - Describe the main lane plus the short slot: who may enter it (the whitelist, in short), never beside exclusive, D5.
  - Name the three config keys and the autopilot answer.
  - Give the `gate.times` 8-field row and the retention.
  - Explain `--classify`.
  - Describe the leak scrub and `lanes-guard.sh`.
  - Give the cleanup after a SIGKILLed gate: `kill -TERM -<pgid>` of the orphaned child group (O16).
  - List the known limits:
    - O16's env/test-content limits;
    - B2: a waiting shareable is not FIFO under D5;
    - B4: a shareable suite's own import beside the slot;
    - B6: the common exclude hides a developer's untracked `override.cfg` in the main checkout.
  - The `studio-test` row (`test_docs_59_wording`) stays byte-identical.
  - Add `STUDIO_GATE_SHORT_SECONDS`, `STUDIO_GATE_LOADAVG`, `STUDIO_GATE_PHYS_CORES` and `STUDIO_GODOT_USER_ROOT` to the test-knobs line.
- [ ] **Step 2: GUIDE.md.**
  - The `test.sh` row gets `godot --headless [<test_engine_args>] --path …` and the allowlist note.
  - A new row: `| \`isolate.sh [--check|--scrub|--leaks DIR]\` | per-worktree user:// for an opted-in linked worktree (\`"user_dir": "per-worktree"\`) …`.
- [ ] **Step 3: harness_test.**
  - Add `STUDIO_GATE_SHORT_SECONDS` to the studio-gate `_need`. If T7–T9 pushed any knob past line 30, widen that `sed -n '1,30p'` to `'1,45p'` and say so in the commit.
  - Add `_need "gate-class.sh header" "$(sed -n '1,30p' "$_bin/gate-class.sh")" STUDIO_GATE_LOADAVG STUDIO_GATE_PHYS_CORES`.
  - Add `_need "isolate.sh header" "$(sed -n '1,40p' "$REPO_ROOT/studios/game-dev/engines/godot/isolate.sh")" STUDIO_GODOT_USER_ROOT`.
- [ ] **Step 4: run_all.sh floors.**
  - Run each changed suite once through `<R>`: gate_lanes_test, gate_class_test, gate_times_test, isolate_test, toolkit_test, studio_test, hook_test, omega_test, studio_setup_test and harness_test. Read each `N assertions` line.
  - Add rows `gate_lanes_test 1 <N>`, `gate_class_test 1 <N>`, `gate_times_test 1 <N>` and `isolate_test 1 <N>`, placed by weight. Raise the changed suites' floors to their counts.
  - overnight_test and overnight_lanes_test gained 1 and 2 assertions in named tests. Raise their floors by exactly those counts; do not run them whole here.
- [ ] **Step 5: Run.** `sh <R> <W>/tests/harness_test.sh`, `sh <R> <W>/tests/studio_test.sh` and `sh <R> <W>/tests/run_all_test.sh`.
- [ ] **Step 6: Commit** `docs(T12): README and GUIDE for the short lane; floors and knob checks`.

---

## Final review, full gate, acceptance

- [ ] **Final whole-branch review (Opus, standalone).** Dispatch with `model: "opus"`, over `origin/main..issue-71-gate-short-lane`, with the spec and this plan. Focus:
  - spec §18 claims 1–9 against the code;
  - this plan's Review Focus;
  - A5 byte-identity with no keys;
  - #70's regions untouched (`git diff origin/main -- studios/game-dev/bin/overnight-lanes.sh studios/game-dev/bin/overnight-ids.sh` is empty, and the studio-overnight diff is `gate_line` only).

  Findings go to a fresh fixer wave; re-review only after a Critical, 3+ Importants or a production-bug fix.
- [ ] **Full gate (orchestrator, under `.git/heavy-suite.lock`).**
  - From a scratch cwd with an existing `TMPDIR`: `sh /Users/xinli/GameDev/proj/omega-ai/.claude/worktrees/issue-71-gate-short-lane/tests/run_all.sh`, then `TEST_SH=dash sh …/tests/run_all.sh` when dash is installed. Both are green, with no floor below.
  - Then the PR. Merge once green (user's merge authority).
  - Install only by merging, when phoenix is quiet.

**Manual acceptance (orchestrator; not an implementer task).** Phoenix steps run only when phoenix is quiet: no live run, per `sh studios/game-dev/bin/studio-overnight status` from phoenix's main checkout, **and** `PX/.studio/gate.lock` free. They run under `.git/heavy-suite.lock` and never during a phoenix final gate (`gate.lock/who` ∈ `final-gate`, `merge`, `gate` → stop). Each phoenix step is confirmed with the user first: it creates a phoenix linked worktree.

1. **Synthetic benchmark (§13.2).** `gate_lane_bench.sh off 180`, then `on 180`, then `exclusive 180`, in a scratch dir. Record the printed p50/p90 and the verdicts in the PR.
2. **Throwaway Godot project (§13.3).**
   - Under the scratchpad: real Godot 4.6.3, GUT copied in, two linked worktrees with `"user_dir": "per-worktree"`.
   - Concurrent `studio-test --file` runs write and re-read `user://probe.cfg` and never see each other's value. `app_userdata/<name>` is untouched.
   - Fixed-fps probe: with `"test_engine_args": "--fixed-fps 60"`, a GUT test awaiting 120 physics frames finishes in < 2 s wall.
   - Leak: a gated `--headless -s` script calling `ProjectSettings.save()` → the gate removes the lines, prints its line and exits 1. Before the scrub, `lanes-guard.sh` fed `git commit -am` denies. `--import` and `-e --quit` leave `project.godot` unchanged.
3. **No new flaky reds (§13.4, O13).**
   - In a phoenix acceptance linked worktree, set the three keys locally and leave them uncommitted.
   - Lane load: a loop in a second worktree, alternating `studio-test --file tests/…/test_settings_cfg_isolation.gd,…/test_placeholder_icon.gd` and `cd web-tools && studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2 <2 files>`.
   - (a) The wall-clock-sensitive subset: `grep -rlE 'Time\.get_ticks_|OS\.get_ticks_' tests/` plus the deadline-loop files, with the falsifier's list as the floor. Record the list. Copy it into a scratch directory and run it as a **directory** `studio-test <dir>` so it holds main as `shareable`. 20× solo, then 20× with the lane load.
   - (b) The whole suite: 3× solo, then 3× with the load.
   - Fail closed:
     - a new red fails;
     - a test red in some but not all solo runs makes the comparison inconclusive, which fails;
     - a crash, a timeout, or no lane-`short` load rows makes the run void, which fails.
   - Budget ≈ 100 min for (b).
4. **The full gate with isolation (§13.5).** `studio-setup gate` in the opted-in acceptance worktree, solo, has the same red set as in a non-opted one.
5. **After the first live runs (§13.6–7).** `python3 -I tests/probes/gate_wait_measure.py --since <install day> --lanes --check-overlap --validate`. Every verb with ≥ 30 exposure-min meets its target, and so does the all-three row. At least one slot run. No unexplained dominant refusal reason. Final-gate waits are reported apart.

---

## Falsified assumptions (planner falsify clause)

Each load-bearing assumption, checked against the code at 137c784:

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | One lock per project, rooted at the main checkout | holds | `studio-gate:57` → `studio-state:46-55` (first `git worktree list` entry) |
| 2 | Every lock-dir write except the owner's release is under the `ln -s` mutex | holds | `studio-gate:102-137`. The release is a rename aside at `:139-147` |
| 3 | The `.studio/gate.*` exclude covers `gate.short/`, `gate.wantx/`, `gate.short.demote.*` and `gate.isolate-sweep` | holds | `studio-gate:70` `grep -qxF '.studio/gate.*'` in the common `info/exclude` |
| 4 | The other `gate.lock/` readers use only `pid`/`who`/`unit`/`since` | holds | `studio-setup:133-136`, `studio-overnight:1134-1141`, toolkit tests. Hooks read none |
| 5 | studio-test builds exactly `sh <dir>/studio-dispatch test --file <one list>` | holds | `studio-test:63`. One comma list, deduped (`:56`); the suite form is `:65` |
| 6 | The dispatch path the gate sees equals `$SELF_DIR/studio-dispatch` as a string | **false in general** | studio-test uses `$(dirname "$0")` (`:63`). The gate's `SELF_DIR` is `cd … && pwd` without `-P` (`studio-gate:42`). Through an installed symlink they can differ. → T1 compares `gc_resolve` of both (symlinks resolved, `pwd -P`) |
| 7 | test.sh has no config reader of its own | holds | `engines/godot/test.sh:1-153` reads no `.studio/config.json`. → T3 adds `cfg.sh` |
| 8 | An empty engine-args value leaves the argv byte-identical | holds | An unquoted empty expansion yields zero fields (POSIX 2.6.5). Pinned by T3's golden test |
| 9 | The ten `<rc>$` anchors are where the spec says | holds | toolkit_test :290 :305 :878 :940 :961 :983 :1020 :1041; studio_setup_test :64 :123 |
| 10 | `gate_room_check` reads only `$2`/`$3` | holds | `studio-overnight:702-708` |
| 11 | Two tests pin `^gate: free$` | holds | `overnight_test.sh:1025`, `overnight_lanes_test.sh:2620` (outside #70's regions) |
| 12 | The knob check covers any header line | **false** | `harness_test.sh:483` reads only `sed -n '1,30p'` of studio-gate. → new knob lines stay at :5-12; T12 widens if needed |
| 13 | New bin/engine files need no installer change | holds | `lib/common.sh:202-206` installs every child of `bin/`. Engines/hooks ship in the plugin root. `test_bin_syntax` (`studio_test.sh:108-118`) requires `+x` and `sh -n` |
| 14 | The units under a run see the run's config through `STUDIO_START_DIR` | holds | `studio-overnight:1285-1292` exports it into every unit session |
| 15 | The autopilot merge already handles a missing config file | **false** | The `:75` one-liner calls `json.load(open(p))` and raises when absent; the skill then writes a literal instead. → T5's one-liner handles both |
| 16 | The pointer-skills suites pin the execute/agent sentences that change | **false** | `pointer_skills_execute_test.sh` pins none of them. The pins are `studio_test.sh:611-629` (`test_execute_command_caps_text`, `test_agent_gameplay_programmer_file_runs`), and none pins a replaced sentence. → T4 keeps those literals and adds its own test |
| 17 | `Verify:` kinds are validated by code (so `suite` would need a validator change) | **false** | No code matches `playtest`/`visual` in `studios/*/bin` or `shared/omega/bin`. They are prose only, so T4 is text only |
| 18 | `unit_reap` covers a slot gate unchanged | holds | `studio-overnight:1186-1224` TERMs/KILLs every pid under `gate.units/<tag>/`. The slot gate registers at the same place (`studio-gate:149-163`, `:265`) |
| 19 | The godot stub records its argv for the engine-args tests | holds | `toolkit_test.sh` stub line `printf 'stub godot args: %s\n' "$*"` |
| 20 | The autopilot contract's question assertion survives a third question | holds | `autopilot_contract.sh:44` matches `one .AskUserQuestion. with two questions`. T5 keeps that phrase and adds "(three for a `godot4` project)" |
| 21 | studio-setup's `setup`/`gate` gates are exclusive by argv | holds | `studio-setup:93` and `:128` both gate `sh -c …` |
| 22 | The final gate's nested `studio-test` re-enters | holds, with a new effect | The final-gate argv is `sh -c '{ studio-test && … } && studio-setup gate'` (overnight-lanes.sh:1722-1727). The nested studio-test now runs `isolate` (T8) before re-entering, so the run worktree gets `override.cfg` during the final gate. Spec §8 accepts this; acceptance 4 proves it |
| 23 | A failed `ps` read can be treated as "not a gate" | **rejected** | Reclaiming on an empty read would admit a second holder beside a live one. → `live_gate` treats an empty read as live (T7). A dead pid fails `kill -0` first, so no wedge |

#70 overlap: no task needs a #70 region. One soft overlap: T5 edits autopilot SKILL `:70-75`, `:90` and `:119`. The `start --detach` text #70 may touch is elsewhere in that file (contract `:76-78`), so rebase whichever lands second.

## Self-review

- **Spec coverage.**
  - R1 → T3, T12. R2 → T1. R3 → T7, T9. R4 → T8, T10, T11. R5 → T4/T5 text, and it is reachable with no hook. R6 → T2, T6. R7 → T4, T5, T12.
  - Acceptance §13.1's every bullet maps to a named test. The units bullet is moved into gate_lanes_test (recorded).
  - §13.2 → T13 plus manual; §13.3–7 → manual.
  - §17's builder calls are decided here:
    - sourced files;
    - `gc_resolve`;
    - eslint kept;
    - D5 on-only, by the effective-exclusive rule;
    - the load rule 2× physical cores, with no override;
    - allowlist `--fixed-fps` only;
    - the U7 question;
    - leak patterns and start-scrub;
    - the demote path `gate.short.demote.<pid>` holding one reason line;
    - no `got the lane` line;
    - B2/B4/B6 documented, B7 hashed, B8 closed (`--has`), B9 (`live_gate` matches `$1`/`$2`);
    - the 1-h guard via `find -mmin +60`.

    Deferred: the `--ceiling` replay mode (a follow-up), Linux `override.cfg` verification (`--check` refuses there), and the `AI_RUNNER_SMOKE` env refusal (a documented limit, O16).
- **Type consistency.** `gate_classify` prints `<class> <kind>`, used as `${_gc% *}`/`${_gc#* }` in T1 and T7. `gate_times_append` takes 9 args in T2 and T7. `ROW_RC`/`SIGSTATUS`/`LANE`/`DEMOTE` are named alike in T7, T9 and T10. The isolate exits 0/3/1 match T10 and T11. `gt_rows` is used alike in T2, T7 and T9.
- **Proportion.** Full code appears only for the mutex-protected admission and release, the retention awk, the shared config reader, the engine-args allowlist, the cap/demote decision, the scrub hook-in and the test stubs. The rest is signatures, rules and test assertions.
