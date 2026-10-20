# Gate short lane: short checks no longer wait behind a whole-suite run — Design

Date: 2026-10-19
Status: Design, revised after the spec falsifier (2026-10-19): the user's answers are U5–U8 and the review rulings
O7–O16. Not a plan: interfaces are sketched, and the code is left to the builder.
Story: #71 (GitHub issue). It includes #69 item 1 (studio-test takes the project's engine args). Branch
`issue-71-gate-short-lane`, off `origin/main` 18fd2e0.
Classification: architectural. It changes the gate's concurrency contract (one lock becomes a main lane plus one
short slot), adds two project config keys to the Godot adapter and one to the gate (merged into run branches by
the autopilot), adds a guard that keeps the lane's `user://` path out of commits, and changes the planning rule for
how task units test.

## 1. What happened, and the numbers

On 2026-10-19 at about 10:51 CDT, phoenix unit KAN-1623 held `.studio/gate.lock` with a whole-suite `studio-test`
for **32.8 min**. A one-file `studio-test --file tests/unit/test_telegraph_integration.gd` (24 s of work) waited
**32.9 min** behind it, and a two-file targeted `vitest run` (about 25 s) waited **30.5 min**. The machine (Intel i7-7700HQ, 4 physical / 8 logical
cores) was at load about 3, with 80% of memory free. The same pattern happened four more times that day.

Measured over 14 days (10-05 to 10-19, phoenix overnight sessions, from the scratchpad measurement
`gate-wait-report.md`, script `gate-wait-measure.py`):

| Fact | Number |
|---|---|
| Total queue time, all gated calls | 6562 min (about 109 h), over 3795 calls |
| Short calls (hold < 2 min) that waited behind a hold > 10 min | 191 calls, **4317 min = 66% of all queue time** |
| Short-call minutes spent behind a whole-suite `studio-test` | 3077 (71% of those 4317) |
| Short-call minutes spent behind run-tests.sh / merge.sh / final gate | 499 (12%) |
| Short calls killed by a Bash timeout while waiting, then re-queued | 23 calls, 285 min wasted |
| Whole-suite `studio-test` | 417 runs, hold p50 **20 min**, p90 **31 min** (wall-paced) |
| The same suite at `--fixed-fps 60`, on this machine (phoenix run-tests.sh GUT logs, 10-17) | **816 s and 1002 s**, about 2× faster. The ~120 s in run-tests.sh's comment is a 6P+12E-core Mac. |
| 2026-10-19 alone | 648 queue-min; 483 of them were short calls behind long holds, 427 behind whole suites |

Other findings:

- **studio-gate records no wait time.** `gate.times` holds `<epoch> <who> <hold> <rc>` only. The report had to
  rebuild waits from Claude transcripts. It also keeps only the newest 50 lines per `who`, so busy labels go
  back only 1–3 days.
- The median gated call never waits. The cost is all in the tail, and the tail is head-of-line blocking: a
  20-second check sits behind a 30-minute hold that it shares nothing with.

## 2. Intent

The fix is a standard one. Industry schedulers give short jobs their own slot or priority class, so they do not
wait behind long batch jobs. Bazel's `exclusive` tag, CI runners' "small" pools and OS schedulers' interactive
classes all work this way. Only the jobs that are proven safe to overlap get to run alongside each other.

Two levers together:

1. **Make the long hold shorter (#69 item 1).** `studio-test` runs GUT with the project's configured engine args.
   Phoenix runs at `--fixed-fps 60`, as its `merge.sh` does. That makes the whole suite frame-paced: 816–1002 s on
   this machine instead of 20–33 min. It also removes the wall-clock reds that differ between `studio-test` and
   `merge.sh` (#69's T8 hold).
2. **Give short checks their own slot.** One short slot runs beside a whole-suite `studio-test`, and only beside
   one. It admits only checks proven short and isolated from that suite. Nothing ever runs beside a final gate.

Lever 1 alone shrinks the blocking hold about **2×** here (≈ 30 → 14–17 min), not more: suite holds stay long, so
Lever 2 carries most of the gain, and acceptance 7 is defined so that Lever 1 alone cannot pass it. The 12% of
short-call wait spent behind final gates stays. That is deliberate (anti-goal 2).

## 3. Goals, non-goals, anti-goals

**Goals**

- G1. A short check never waits behind a whole-suite `studio-test` when it is admissible to the short slot. That
  means a whitelisted verb, isolation in effect, load under the threshold, no exclusive waiter, and, for a GUT
  check, a different worktree from the suite's (a node check may share it, O14).
- G2. `studio-test` (whole suite, directory and `--file`) passes the project's configured engine args to Godot.
  Phoenix gets `--fixed-fps 60`.
- G3. GUT runs in different linked worktrees never share `user://`.
- G4. `gate.times` records the wait and the lane for every gated run, so before/after can be measured exactly.
- G5. Per-task units stop running the whole suite by default.
- G6. Every lane rule has an automated test (fake Godot, temp repos, POSIX sh).

**Non-goals**

- Sharding the suite, or running more than one short slot.
- #60 (units that run `run-tests.sh` directly and bypass the gate).
- Bash-timeout re-queues (285 min over 14 days). This is a follow-up (§16).
- New PreToolUse hooks that auto-gate vitest or tsc. The short lane is reachable through the existing convention
  `studio-gate <who> -- <cmd>` (§9).
- Engine args for `studio-run` (`run.sh`). #69 asked for `studio-test` only.
- Any change in phoenix beyond the three `.studio/config.json` keys the autopilot merges into run branches (U7). No
  phoenix `main` commit, and no change to phoenix's own git hooks.

**Anti-goals: the design fails if any of these happens**

- A1. **A new flaky red in a full gate.** That covers a whole-suite `studio-test`, run-tests.sh or merge.sh that
  goes red only because a short check ran beside it, or only because of the new `user://` directory.
- A2. **A final gate that shares the machine.** run-tests.sh, merge.sh, final-gate, setup, studio-run and every
  unknown command stay exclusive. Nothing is admitted beside them, and they wait for the short slot to drain.
- A3. **A silent fallback that hides a dead lane.** A short-eligible check that is refused the short slot says why
  on stderr and records the reason in `gate.times`. The after-measurement fails if the slot is never used.
- A4. **A starved final gate.** An exclusive waiter blocks new short admissions and gets the main lane next.
- A5. **A changed default for other projects.** Without the new config keys, every project behaves exactly as
  today: one lock, wall-paced GUT, the shared `user://`.
- A6. **The lane's `user://` path in a commit.** `config/use_custom_user_dir` or a
  `config/custom_user_dir_name="…-lanes/…"` line in a tracked `project.godot` would move `user://` for every
  checkout once merged, the developer's game included. No gated run and no studio-driven commit may carry it (O7).

## 4. Decisions

### User decisions (binding)

- U1. #69 item 1 is in this story. `studio-test` (whole suite and single file) runs GUT with the project's
  configured engine args, so phoenix runs at `--fixed-fps 60` like its merge.sh. It stays compatible with
  phoenix's flat `"tests": "gut"` config and with the flat-key `field()` reader. Projects without the key behave
  exactly as today.
- U2. The short lane has **one** slot. It admits only these short verbs:
  - `studio-test-file` with ≤ 3 files;
  - vitest with explicit file arguments and a worker cap;
  - tsc / lint.

  A run in the slot is killed after 5 min. The slot may run beside a whole-suite `studio-test`. **Nothing** runs
  beside run-tests.sh / merge.sh (the final gate) or any other exclusive holder.
- U3. The planning rule: per-task units verify with `studio-test --file` on the tests they touched. The whole suite
  runs at the lane gate, or when a task's plan says so explicitly. This is a default the plan can override, and no
  hook enforces it.
- U4. The live acceptance run happens whenever phoenix is quiet (no live run). It is coordinated with the other
  omega-ai sessions through `.git/heavy-suite.lock`. Until then, acceptance rests on automated tests plus a
  throwaway Godot project.

The user's answers to the review's open questions (2026-10-19, binding):

- U5. **GUT single-file checks stay on the short lane**, behind the `project.godot` leak check and the commit guard
  (O7).
- U6. **The planning rule is unchanged** (U3): per-task units verify the tests they touched with `studio-test
  --file`; the whole suite runs at the lane gate, or when the task's plan says so. A default, overridable.
- U7. **Phoenix's keys come from the autopilot.** At run setup it merges the three keys into the run branch's
  `.studio/config.json` the same way it merges `overnight.max_lanes` (autopilot SKILL `:73-107`), and commits them
  with the manifest. There is no phoenix `main` commit. It takes effect from the next run started after install;
  live runs keep today's behaviour.
- U8. **Opt-in per project** (D1, D2 stand). A project without the keys behaves exactly as today.

### Orchestrator calls (the builder may refine them, with a recorded reason)

- O1. Classification is a whitelist by verb and argv. Anything unrecognised is exclusive, so the gate fails
  closed. The main-lane holder records its class in the lock dir: `shareable` is a whole-suite `studio-test`;
  `exclusive` is everything else, including run-tests.sh, merge.sh, studio-run, setup and unknown commands.
- O2. Admission to the short slot also requires two things:
  - for a GUT check, per-worktree `user://` isolation is in effect (otherwise it falls back to the main lane);
  - the 1-min load average is below a threshold computed from physical cores (O9).

  An exclusive waiter blocks new short admissions and waits for the slot to drain. When the main lane is free, a
  short check may take either lane.
- O3. `user://` isolation is a per-worktree `override.cfg` in the project root of linked worktrees, excluded via
  `.git/info/exclude`. It has been verified on macOS. The author decides where it is written and how stale
  directories are cleaned up (decided in §8).
- O4. `gate.times` gains a wait-seconds column and a lane column, appended so that existing readers keep working.
  The measurement script reads them for the after-measurement.
- O5. Avoid #70's files. This story must not change studio-overnight's `detach_start`, `preflight`,
  `setup_preflight` or the usage env block, overnight-lanes.sh's `lanes_start`, `mf_check` or `mf_conflicts`, or
  overnight-ids.sh. Reading or touching `gate_room_check` is allowed. (It lives in studio-overnight `:696-735`, not
  in overnight-lanes.sh. This design needs no change to it.)
- O6. Out of scope: #60, Bash-timeout re-queues (a follow-up), and vitest/tsc auto-gating hooks unless the short
  lane would be unreachable without them. It is reachable without them (§9).

Orchestrator rulings on the review (2026-10-19, after the spec falsifier; its finding ids in brackets):

- O7. **`project.godot` leak guard** [A5, Critical]. Probe: with our `override.cfg`, a `--headless -s` script calling
  `ProjectSettings.save()` wrote `config/use_custom_user_dir=true` and `config/custom_user_dir_name="<p>-lanes/<id>"`
  into `project.godot`; `--import` and `-e --quit` did not. The editor calls `save()` on any Project Settings,
  autoload, plugin or input-map edit. So:
  - after every gated Godot-capable run in an opted-in linked worktree, the gate checks the tracked `project.godot`;
    if it gained those keys, the gate removes those lines and fails closed (§8, *Leak guard*);
  - a commit guard refuses any studio-driven commit that would add them (§8, *Commit guard*).
- O8. **D5 stands.** A waiting exclusive caller blocks new short admissions. Measured cost [B2]: 7 of 99 (7%)
  short-eligible calls that started during a > 10-min suite hold found an exclusive caller already waiting.
- O9. **CPU** [B1]. A short-lane command runs under `nice -n 10`. The load threshold is computed from physical cores
  (`sysctl -n hw.physicalcpu`, 4 here), not `hw.ncpu` (8). The exact rule is the builder's, justified in the PR
  against the measured baseline (1-min load ≈ 5 with two live runs and a wall-paced suite at 12% CPU) and a
  CPU-bound fixed-fps suite (≈ one more core, so ≈ 6). A rule that refuses at that baseline leaves the lane dead.
- O10. **vitest form** [A2, A3]. Short-lane vitest is `npx vitest run --minWorkers=1 --maxWorkers=2 <file>…`, run
  from the project's node directory (phoenix: `web-tools/`). vitest 2.1.9 passes `minThreads = max(ncpu − 1, 1)`
  (7) unless `--minWorkers` is given, and tinypool 1.1.1 then throws `minThreads and maxThreads must not conflict`:
  `--maxWorkers=2` alone fails red. Lane-on and worktree identity come from `git rev-parse --show-toplevel`, never
  the cwd. vitest wrapped in `sh -c` stays exclusive. Known limit: in the baseline, 272 of 706 targeted-vitest calls
  (39%) and 82 of 178 tsc calls used `sh -c`.
- O11. **`test_engine_args` is an allowlist** [A4], not a denylist. At least `--fixed-fps <N>`; the builder may add
  clearly safe pacing or driver flags, each with a value check and a test (§5).
- O12. **All ten `… <rc>$`-anchored tests are updated** [A7], and every rewrite keeps its assertion meaningful;
  `toolkit_test.sh:1020` would otherwise become vacuously true (§10).
- O13. **Flake acceptance** [B3] is a 20× paired run of the wall-clock-sensitive subset plus a 3× paired whole suite.
  Any new red, or an inconclusive or void run, fails closed (acceptance 4).
- O14. **D3 is relaxed** (builder question 3). A node check (vitest, tsc, eslint) may take the slot beside a GUT
  suite or GUT check even in the same worktree: they share no state. A second Godot process in one worktree, or a
  second node check, still goes to the main lane.
- O15. **The speed claim is corrected** [A1] (§1, §2): fixed-fps is about 2× on this machine, not 8×. Acceptance 7
  is restated per verb as a share of recoverable wait, computed from the baseline, that Lever 1 alone cannot meet.
- O16. **Known limits** [A6, A8].
  - argv classification cannot see the environment or test contents. A vitest file that starts `vite preview`
    in-process (`tests/server/tuner-route-vite.test.ts`, ephemeral port), one that spawns real Godot when
    `AI_RUNNER_SMOKE=1` is set before `studio-gate`, and a GUT file that `OS.execute`s a child Godot
    (`test_ai_long_fight_job.gd`) can reach the slot. `nice`, the 5-min cap and the load gate bound them. The builder
    may refuse the slot when `AI_RUNNER_SMOKE` is set, or keep such files out of the short-lane load in
    acceptance 4; otherwise it is a documented limit.
  - A SIGKILLed gate leaves its child's process group running (studio-gate runs it under `set -m`), and the slot is
    then reclaimed beside that orphan, as the main lock is today. The README documents the cleanup
    (`kill -TERM -<pgid>`); recording the child pgid in the lock dirs and checking it on reclaim is a follow-up.

### Author calls (made in this design; the builder may refine them with a recorded reason)

- D1. **The lane is opt-in per project.** It is on only when `"gate_short_lane": "on"` is in `.studio/config.json`
  at the caller's worktree top level (`git rev-parse --show-toplevel`, then `pwd -P`; never the cwd, since vitest
  runs from `web-tools/`), or in the run's config (D15). A whole-suite holder records `shareable` only when its own worktree has the lane on;
  otherwise it records `exclusive`. Reason: A5, and a controlled rollout, so an install changes nothing until a run
  branch carries the keys (U7).
- D2. **`user://` isolation is opt-in** through `"user_dir": "per-worktree"`, which the Godot adapter reads. It is
  written lazily by `studio-test` (through the adapter) before the gate is called. It is never written in the
  main checkout, never over a foreign `override.cfg`, and never where `override.cfg` is tracked. Reason:
  override.cfg moves `user://` for *every* Godot launch in that worktree, so a project has to choose it (§8).
- D3. **No two Godot holders and no two node holders in one worktree, in any lane** (relaxed by O14). The lock
  dirs record `wt` (the git top level, as D1) and `kind` (`godot` or `node`). Two Godot runs in one worktree race
  on `.godot/` and on the report stamp. Two vitests race on vite's results cache. A node check beside a Godot run
  in the same worktree shares nothing, so it may hold the slot.
- D4. **A run that passes the 5-min short cap is re-run once in the main lane**, not exited with 124. Exit 124 means
  `Stop: gate timed out` to every unit (execute §0), so a cap kill in the short slot must never look like one.
  When `STUDIO_GATE_MINUTES` ≤ 5, the normal run cap applies and gives 124 as today. The adapter also has a
  **demote** hand-off for work that turns out not to be short, such as an import (§7).
- D5. **A registered exclusive waiter reserves the main lane.** While one is registered, no shareable or short
  caller takes the main lane either. Without this, a suite could take the main lane while the slot drains, and
  a final gate could wait suite after suite.
- D6. **A short check that takes the main lane keeps today's main-lane semantics**: the `STUDIO_GATE_MINUTES` cap
  only, with no 5-min kill. The 5-min cap belongs to the slot.
- D7. **Engine args are a flat string key**, `"test_engine_args": "--fixed-fps 60"`, split on blanks. The
  characters are checked, and every word must be on an allowlist (O11, §5).
- D8. **Classification looks at argv only.** The free-form `who` label is never trusted. `studio-gate --classify -- <cmd…>`
  prints the class and takes no lock (for tests and for the operator).
- D9. **gate.times keeps 14 days.** It keeps the newest 50 rows per `who` *or* any row younger than 14 days, with
  a hard cap of 20000 lines. It is rewritten under the reclaim mutex so that concurrent lanes do not lose rows.
  Reason: the after-measurement needs exact rows for more than a day.
- D10. **The new state uses a stronger liveness check.** For the short slot and the exclusive-waiter entries, a
  pid is live only if `kill -0` succeeds *and* `ps` shows `studio-gate` in its args. A reused pid can then never
  wedge the slot. `gate.lock` keeps its plain `kill -0` rule, which other readers rely on.
- D11. **A live main holder with no `class` file counts as exclusive.** That covers an old-version gate, and a
  taker caught between its `mkdir` and its write.
- D12. **The planning override is a new `Verify:` kind, `suite`.** `Verify: unit+suite` means the implementer runs
  the whole suite before reporting.
- D13. **An unreadable load average or core count means no short lane.** The threshold comes from physical cores
  (O9).
- D14. **The measurement script is committed** as `tests/probes/gate_wait_measure.py`, updated to read the new
  columns (§11).
- D15. **The three keys fall back to the run's config** (found while applying U7). Each key is read from
  `.studio/config.json` at the caller's git top level; when that file lacks the key and `STUDIO_START_DIR` is set
  (the runner exports it to every unit, studio-overnight `:1284-1292`), from `$STUDIO_START_DIR/.studio/config.json`,
  the run worktree's. Reason: units run in story worktrees, which have no config of their own (§14.3), so a
  run-branch-only key would never reach them. This touches no overnight file. A hand session in a story worktree
  has no `STUDIO_START_DIR` and so stays lane-off (A5).

## 5. R1 — studio-test passes the project's engine args (#69 item 1)

**Config.** Add a top-level flat string to `.studio/config.json`, read at the git top level with the run fallback
(D15):

```json
{ "engine": "godot4", "tests": "gut", "test_engine_args": "--fixed-fps 60", … }
```

- The flat-key `field()` sed reads it. Phoenix's `"tests": "gut"` is untouched, and the key name cannot collide
  with it.
- An absent or empty key gives today's command line byte for byte.
- `cfg_raw`, `cfg_str` and `cfg_get` match `"<key>"` with its quotes. So no existing key is a substring match of
  it, and it is not a substring match of any existing key.

**Command.** `engines/godot/test.sh` reads the key with the same sed as `field()`. test.sh is self-contained and
has no `field()` of its own. It puts the words between `--headless` and `--path`, before `-s`:

```
"$GODOT" --headless <test_engine_args…> --path "$PROJECT" -s addons/gut/gut_cmdln.gd <selection…> -gexit -gjunit_xml_file=…
```

**Scope.**

- Every test.sh run uses the args: the whole suite, a directory and `--file`.
- `ensure_import` does not. `--import` is not a GUT run.
- `run.sh` does not (non-goal).

**Validation.**

- The value may hold only `A-Za-z0-9`, space and `._=:,/-`.
- Words are split with `set -f`, so they are never globbed.
- **Allowlist (O11).** Every word must be a known-safe flag with a checked value: at least `--fixed-fps <N>`, `N` an
  integer 1–1000. The builder may add clearly safe pacing or driver flags (for example `--audio-driver Dummy`,
  `--verbose`), each with its value check and a test. Everything else is refused. A denylist cannot work: Godot
  4.6.3 `--help` lists `--main-pack`, `--main-loop`, `--scene`, `--quit-after`, `--check-only`, `--export-*`,
  `--write-movie`, `--log-file` and a bare `res://` positional, all inside the charset, each changing what runs or
  where it writes. The value is project-committed config, so this guards against accidents, not attackers.
- A bad value exits **1** with `studio-test: test_engine_args in .studio/config.json: <why> — got <value>`.
  It does not exit 2, because execute reads 2 as "no Godot".

**Docs.** GUIDE.md's `test.sh` row and the README gate paragraph name the key.

## 6. R2 — classification (argv whitelist)

The classifier is a pure function from the gate's argv and cwd to a class: `short`, `shareable` or `exclusive`.
For `short`, it also says whether the check needs `user://` isolation (`gut`) or not (`node`). It lives in a new
sourced sibling, `bin/gate-class.sh`, following the overnight-*.sh precedent. The builder confirms that install
ships it.

| Class | argv form (after `studio-gate <who> --`) |
|---|---|
| short / gut | `sh <studio-dispatch> test --file <list>`, where `<list>` has 1–3 comma-separated entries and nothing follows. `<studio-dispatch>` is the same file as `$SELF_DIR/studio-dispatch` (compared after `pwd -P` resolution). This is the exact argv `studio-test` builds. |
| shareable | `sh <studio-dispatch> test` with no argument, or one directory argument. That is a whole-suite or directory `studio-test`. It is only shareable when the lane is on in its worktree (D1); otherwise it is exclusive. |
| short / node | vitest: `npx [--no-install] vitest run …` or `[./]node_modules/.bin/vitest run …`, run from the project's node directory (phoenix: `web-tools/`). It needs **exactly** `--minWorkers=1` and one cap, `--maxWorkers=1` or `--maxWorkers=2` (O10). It needs **at least one** positional, and **every** positional is an existing regular file relative to cwd. The only other options allowed are `--reporter=<word>`, `--silent`, `--no-color`, and `-t <pattern>` / `--testNamePattern=<pattern>`. |
| short / node | tsc: `npx [--no-install] tsc --noEmit` or `[./]node_modules/.bin/tsc --noEmit`. The only options allowed are `-p <file>` / `--project <file>` and `--pretty false`. `-b` / `--build` and `--watch` are not allowed. |
| short / node | eslint: `npx [--no-install] eslint <file>…` or the `node_modules/.bin` form. Every positional is an existing regular file. The only options allowed are `--max-warnings <n>` and `--format <word>`. |
| exclusive | **everything else**. That includes: `sh -c …` (final-gate, studio-setup's gate and setup, and any `sh -c "cd web-tools && …"` vitest or tsc); `merge.sh`; `run-tests.sh`; `studio-dispatch run` (studio-run); `studio-dispatch test --file` with 4 or more files; `npm …` (scripts are opaque); `env`/`VAR=` prefixes; `studio-gate godot -- …`; vitest with no cap, no `--minWorkers=1`, a cap above 2, a directory or a glob; and any unknown command. |

Notes:

- A vitest positional is a filter, not a path. A substring can match more than one file. Requiring every
  positional to be an existing file keeps the run narrow, and the cap and the 5-min kill bound the rest.
- Today's phoenix convention, `studio-gate vitest -- npx vitest run <path>`, has no worker cap. It stays exclusive,
  and only the new text (§9) makes it short. That is fail-closed by design.
- Probed (falsifier, phoenix's vitest 2.1.9 / tinypool 1.1.1, `pool: "threads"`): `--maxWorkers=2` alone exits 1
  with `options.minThreads and options.maxThreads must not conflict` and runs no test; with `--minWorkers=1` it
  passes. Hence the required pair (O10).
- The positional check is relative to the cwd (`web-tools/`), but lane-on and `wt` come from the git top level
  (D1, D3). A cwd-relative config read would leave the lane off for every vitest.

## 7. R3 — the lane state model

### State (all under `STATE_ROOT/.studio/`, already excluded by `.studio/gate.*`)

| Path | Meaning | Files |
|---|---|---|
| `gate.lock/` | The main lane. Its meaning is unchanged for every existing reader (studio-setup `:133-136`, `gate_line`, the tests). | `pid`, `who`, `unit`, `since` (as today), plus **`class`** (`shareable` / `short` / `exclusive`), **`kind`** (`godot` / `node`; exclusive holders `godot`) and **`wt`** (`git rev-parse --show-toplevel`, then `pwd -P`) |
| `gate.short/` | The one short slot. | `pid`, `who`, `unit`, `since`, `wt`, `kind`, `class` = `short` |
| `gate.wantx/<pid>` | One file per waiting exclusive caller. The file holds `since` and `who`. | — |
| `gate.lock.mutex` | The existing reclaim mutex. It now guards all three paths above and the `gate.times` rewrite. | symlink → owner pid |

Every write to `gate.lock/`, `gate.short/` or `gate.wantx/` happens under the mutex. The exception is a live
owner's own release (a rename aside, as today). Takers write `class` and `wt` before they drop the mutex.

### Lanes a caller can be in

```
            ┌──────────── waiting (polls every GATE_POLL, re-evaluates admission) ─────────────┐
 request ──►│ exclusive: registered in gate.wantx/<pid>                                         │
            │ shareable / short: not registered                                                 │
            └──┬─────────────────────────────┬──────────────────────────────────────┬────────────┘
               ▼                             ▼                                      ▼
        holds MAIN (class X)      holds SHORT (short only, 5-min cap)    demoted: back to waiting,
               │                             │  cap or demote marker ─────►  main lane only, once
               ▼                             ▼
            release                       release
```

### Admission (evaluated under the mutex on every poll)

The static facts (class, kind, `wt`, lane-on, `isolate --check`, the core count) are computed once before the
wait loop; only the lock state and the load are read on each poll (falsifier B5).

Definitions:

- *main free*: no live `gate.lock/` pid (`kill -0`; stale or pidless is reclaimed as today).
- *slot free*: no live `gate.short/` pid (D10 liveness; stale is reclaimed).
- *X waiting*: there is a live `gate.wantx/` entry other than the caller's own (D10; stale entries are removed).
- *same-wt*: a live holder in either lane has the caller's `wt` **and** the caller's `kind` (D3, O14). A node
  check beside a Godot holder in its own worktree is not same-wt.
- *main class*: the `class` of the live `gate.lock/` holder. A missing class counts as `exclusive` (D11).

| Caller | Takes MAIN when | Takes SHORT when |
|---|---|---|
| exclusive | main free **and** slot free | never |
| shareable | main free **and** not X waiting **and** not same-wt | never |
| short | main free **and** not X waiting **and** not same-wt, but only when it cannot take SHORT (the slot is preferred, so the main lane stays free for a suite or an exclusive) | **all** of these: lane on (D1); slot free; not X waiting; main class ∈ {none, `shareable`, `short`}; not same-wt; isolation in effect when the check is `gut` (§8); 1-min load under the physical-core threshold (O9, D13) |

Consequences:

- Nothing ever runs beside an exclusive holder. An exclusive caller needs both lanes empty, and while it holds
  the main lane the short slot admits nobody (main class `exclusive`).
- The final gate is not starved. Once it registers, the slot admits no newcomers. The slot drains within the
  5-min cap plus the 10 s KILL grace. The main lane is reserved for exclusive callers (D5). Among several
  exclusive callers it is the same poll race as today.
- A short check whose short admission fails is not stuck. It keeps polling for either lane, and the reason is
  reported (anti-goal A3).
- With the lane off (no key), a short check's only path is the main lane, so behaviour equals today. The
  exceptions are D5's priority and the new records. D5 still applies: an exclusive waiter is registered even
  with the lane off, so its priority holds.
- The builder must decide one point and record it: whether D5 should apply only when the lane is on. That would
  keep lane-off projects identical to today. The author leans towards "only when on", for A5 (U8).
- A slot holder's command runs as `nice -n 10 <cmd…>` (O9), so Godot, vitest workers and tsc yield CPU to the suite.
  The main lane, including a short check that took it and a demoted re-run, is never niced (D6).

### Reporting what the waiter sees

- The 60-second line keeps its prefix exactly: `gate: waiting for <who> (pid <p>)`. Tests and the measurement
  script match it.
  - An exclusive caller blocked only by the slot names the slot's holder:
    `gate: waiting for <who> (pid <p>, short lane)`.
  - A short-eligible caller appends its refusal reason on the same line: `; short lane: <reason>`.
- Reasons:

  | reason | meaning |
  |---|---|
  | `off` | lane off |
  | `iso` | isolation not in effect |
  | `load <l>/<t>` | load too high |
  | `exclusive waiting` | an exclusive caller is waiting |
  | `beside <class>` | main class is not shareable |
  | `same worktree` | a holder of the caller's kind is in the caller's worktree |
  | `slot busy` | the slot is taken |

- A short-eligible caller prints its reason as soon as it is first refused, without waiting for the first
  60-second tick. So a dead lane shows in the first second of output.
- A slot holder whose `since` is older than the cap + 60 s, and is still live, adds
  `(short lane past its cap — stuck?)` to the waiting line. Nobody kills it. That matches today's main-lock
  policy: only its own timer, its signals and the runner's `unit_reap` end a gate.

### Re-entry (`STUDIO_GATE_HELD`)

- A nested `studio-gate` execs without locking when `STUDIO_GATE_HELD` names the live pid in **either**
  `gate.lock/pid` or `gate.short/pid`. A nested call under a slot holder runs inside that holder's 5-min cap. In
  practice the whitelist argvs never nest a gate.
- The final gate's nested `studio-test` / `studio-run` / `studio-setup gate` still re-enter the exclusive
  `final-gate` holder, as today.
- The child's environment also gets `STUDIO_GATE_LANE=main|short`. In the slot it also gets
  `STUDIO_GATE_DEMOTE=<path>`, a file under `STATE_ROOT/.studio/gate.short.demote.<gatepid>`.

### Caps

- **Main lane: unchanged.** `STUDIO_GATE_MINUTES`, with the timer starting at acquisition, `setup` exempt, exit
  124. That includes a short check that took the main lane (D6).
- **Slot: the cap is min(5 min, `STUDIO_GATE_MINUTES` when set).** The timer starts when the slot is taken.
  - **When the 5-min cap is the binding one**:
    1. The gate TERMs the child's group, as the run cap does, and KILLs after 10 s.
    2. It prints `gate: <who> ran past the short lane's 5 min — stopped; running it again in the main lane`.
    3. It writes the attempt's `gate.times` row (rc 124, lane `short`).
    4. It releases the slot and goes back to waiting as a **main-lane-only** caller.
    5. It runs the command again. The exit status is the re-run's.
    6. The re-run's row has lane `main:demoted`.

    It re-runs once only. The re-run cannot be demoted, and it gets its own `STUDIO_GATE_MINUTES` timer.
  - **When `STUDIO_GATE_MINUTES` ≤ 5**, the run cap is the binding one. That is exit 124 and no re-run, exactly
    as today. The main lane could not have finished it either.
  - A signal (INT/TERM/HUP) during a slot run is forwarded as today. It exits 128+n, with no re-run.
- **The demote hand-off.** A slot child that finds it needs the main lane touches `$STUDIO_GATE_DEMOTE` and
  exits. The gate sees the file, removes it, logs the attempt (lane `short`, rc as it exited) and re-runs the
  command in the main lane once, as above. The stderr line is
  `gate: <who> needs the main lane (<reason from the file>) — waiting for it`.
  - test.sh uses this when `ensure_import` would import while `STUDIO_GATE_LANE=short`. An import is a heavy,
    multi-threaded Godot run that does not belong beside a suite.
  - The builder may find other uses and record them.
- Test-only seam: `STUDIO_GATE_SHORT_SECONDS` (default 300). It applies only to the slot. It is named in the
  header, defaults to production, and at least one test reads the default (as
  `test_gate_run_cap_production_seconds` does).

### Stale handling

| Thing | Stale when | Who clears it |
|---|---|---|
| `gate.lock/` | The pid is dead or missing (today's rule). | Any taker, under the mutex. |
| `gate.short/` | The pid is dead or missing, **or** the pid is alive but not a `studio-gate` (D10). | Any taker, under the mutex. |
| `gate.wantx/<pid>` | As for `gate.short/`. | Any caller evaluating admission, under the mutex. Its owner removes it on taking the main lane and in its EXIT trap. |
| `gate.short.demote.*` | Its gate pid is not live. | The owner on every path. Any taker sweeps orphans. |

`unit_reap` already TERMs and KILLs every gate registered under the unit's tag, waiting or holding. Short-slot
gates register in `gate.units/` the same way, so the reaper covers them with no change.

## 8. R4 — `user://` isolation per linked worktree

**Mechanism** (verified 2026-10-19 on macOS, Godot 4.6.3 mono, with a throwaway project): `override.cfg` in the
project root.

```
; omega-ai studio-test: per-worktree user:// (#71). Generated; never commit.
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="<project>-lanes/<id>"
```

- `<project>` is `config/name` from `project.godot`, reduced to `[A-Za-z0-9._-]` (`godot-project` when empty).
- `<id>` is the linked worktree's admin dir name, the basename of `git rev-parse --git-dir`, which is
  `.git/worktrees/<id>`.
- On macOS the dir is `~/Library/Application Support/<project>-lanes/<id>`.
- It moves only `user://`; the import cache is already per worktree.
- These do not work on macOS: XDG vars (ignored), a `HOME` override (it breaks git, npm and git-lfs config for
  children), and a CLI flag (none exists).

**Where it is written: lazily, by `studio-test`.** A new adapter verb, `engines/godot/isolate.sh`, is reached as
`studio-dispatch isolate`. `studio-test` calls it before it execs the gate, for whole-suite, directory and
`--file` runs. It is idempotent and costs a few ms. It writes only when all of these hold:

- the config says `"user_dir": "per-worktree"` (D2, read as D15);
- the top level is a **linked** worktree, not `STATE_ROOT`'s main checkout. The developer's editor and game live
  in the main checkout, and nothing is ever written there;
- `override.cfg` is absent, or present with the marker line (it is ours and gets rewritten only when the name
  changed);
- `override.cfg` is not tracked (`git ls-files --error-unmatch` fails).

It adds `/<project-root-relative>/override.cfg` to the common `info/exclude` once, as studio-gate does for
`.studio/gate.*`. A foreign or tracked `override.cfg` is never touched. Isolation is then not in effect, and the
waiting line says so (`iso`).

Why not at worktree setup: worktrees are made by many paths (EnterWorktree, `studio-state worktree`, the runner's
lanes, by hand), and live worktrees would never get it. `setup_preflight` is also #70's ground (O5). The lazy write
covers every worktree, from the first `studio-test` after install onward.

**"Isolation in effect"** is `studio-dispatch isolate --check`. It writes nothing, and exit 0 means in effect:

- a linked worktree;
- our `override.cfg`, naming this worktree's `<id>`;
- `project.godot` does not itself set `use_custom_user_dir`.

Any other exit or a missing adapter means not in effect (fail closed). The classifier calls it for `gut` short
checks only.

**Platform.**

- macOS is verified.
- On Linux the custom dir lands under `${XDG_DATA_HOME:-~/.local/share}`. That is unverified, so `--check` returns
  "not in effect" on non-Darwin until a builder probe verifies it. GUT checks then use the main lane there.

**Stale directories.**

- `isolate.sh` (in ensure mode) sweeps `<data root>/<project>-lanes/` at most once a day. The stamp is
  `STATE_ROOT/.studio/gate.isolate-sweep`, which the existing exclude glob already covers.
- It removes a child dir only when all of these hold:
  - it is a real directory (never a symlink);
  - its parent is exactly that `-lanes` dir;
  - its name is not in `ls <git-common-dir>/worktrees/`;
  - its mtime is more than 1 h old.
- It does nothing outside that dir, and never sweeps on a platform it does not know.
- A worktree that is re-created under the same name inherits its old dir until the next sweep after its removal.
  That is accepted, because phoenix's tests sandbox their own files (§12).

**What else moves.** Every Godot launch in an opted-in linked worktree gets the per-worktree `user://`:

- studio-run;
- tool `--script` runs;
- `--import`;
- run-tests.sh in that worktree (that includes the run's final gate, whose nested `studio-test` writes it);
- an editor opened there.

That is CI-like (phoenix's pre-run hook already expects "CI (fresh user://)"). Acceptance step 5 proves the full
gate stays green with it.

**Leak guard (O7, A6).** Verified: with our `override.cfg` present, `ProjectSettings.save()` writes the two keys into
`project.godot`; `--import` and `-e --quit` do not. Phoenix's own GDScript calls `save()` only in
`addons/gut/cli/change_project_warnings.gd`; the editor calls it on any settings, autoload, plugin or input-map edit.

- A new adapter mode, `studio-dispatch isolate --scrub`, runs in the gate after the child exits and **before
  release**, for every gated run in an opted-in linked worktree except a node short check. It is cheap (one grep).
- It looks at the tracked `project.godot` for `config/use_custom_user_dir=` or a
  `config/custom_user_dir_name="<project>-lanes/…"` line that `HEAD`'s `project.godot` does not have.
- Found: it deletes exactly those lines (the rest of the file is left as the run wrote it, so `git status` still
  shows any other change), prints
  `gate: project.godot gained the per-worktree user:// setting (<keys>) — removed; this run is not trusted`,
  and the gate exits **1** when the command passed (a failing status is kept). Never 124, never 2. The row records
  the status the gate returns.
- A `project.godot` that sets the keys in `HEAD` is the project's own choice: `--scrub` leaves it alone, and
  `isolate --check` already reports isolation not in effect there.

**Commit guard (O7, A6).** The hook point is a new PreToolUse Bash hook, `studios/game-dev/hooks/lanes-guard.sh`,
registered in `hooks/hooks.json` beside `godot-guard.sh`. Every studio commit (units, fixers, runner sessions) is
a Claude Bash call, so this covers them all.

- On a command that runs `git … commit`, it resolves the target worktree (`git -C <cd target or cwd> rev-parse
  --show-toplevel`), and denies the call when that worktree's `project.godot`, in the index or the working tree,
  has a lanes line from the list above that `HEAD` lacks. The message names the fix: `studio-dispatch isolate
  --scrub`, then commit.
- Like `godot-guard.sh`, it exits 0 and prints nothing on every parse problem, and never blocks any other command.
- Rejected hook points:
  - a git `pre-commit` hook: phoenix sets `core.hooksPath` to its own `.git/hooks`, installed by
    `tools/git-hooks/install.sh` and shared by every worktree; writing there changes phoenix-owned hooks;
  - the runner's landing checks: `mf_check` is #70's ground (O5), overnight-lanes.sh is outside this story's files
    (§12), and a session-only story never lands through the runner.
- Known limit: a commit typed by hand in a terminal, in an opted-in linked worktree, is covered only by the next
  gated run's scrub. A line in phoenix's own pre-commit hook would close it; that is a phoenix change and a
  follow-up for the user (§16).

## 9. R5 — how a unit reaches the short lane

- **GUT.** The unit does what it already does: `studio-test --file a.gd[,b.gd,c.gd]`. Calls of up to 3 files are
  short-eligible. A call of 4 or more files is still correct, but it waits for the main lane.
- **vitest / tsc / eslint.** These are gated today only by convention (plan Global Constraints, ledger directives,
  autopilot SKILL `:119`), and no hook or allow rule is needed. The minimal entry point is the existing wrapper
  with the whitelisted argv:

  ```
  cd web-tools && studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts tests/b.test.ts
  cd web-tools && studio-gate tsc -- npx tsc --noEmit
  ```

  The `cd` is outside the gate, never an `sh -c` inside it: `studio-gate … -- sh -c "cd web-tools && …"` is
  exclusive (O10). Units run these through the auto-mode classifier today, and phoenix's `gate.times` shows 50 rows each for
  `vitest` and `tsc`. Adding allow rules (`overnight-allow.txt`) is a follow-up, not part of this story. Allow
  rules are a least-privilege surface.

## 10. R6 — records

**`gate.times` row.** It is appended, so fields 1–4 are unchanged:

```
<epoch> <who> <hold s> <rc> <wait s> <lane> <class> <unit|->
```

- `wait` is the time from the gate's start (taken before the first `try_take`) to acquisition. A demoted re-run's
  row counts its wait from the demotion.
- `lane` is one of:
  - `main`;
  - `short`;
  - `main:<reason>`, for a short-eligible caller that ran in the main lane. The reason is the last refusal at
    acquisition, or `demoted`.
- `class` is the classifier's result.
- `unit` is `STUDIO_UNIT_TAG`, or `-` when empty.

Compatibility:

- `gate_room_check` reads only `$2` and `$3`, so it needs no change.
- Ten existing assertions anchor on `… <rc>$` and are updated to the new shape (O12). Each rewrite matches the rc
  as field 4 (for example `awk '$2 == "t" && $4 == 124'`) and also asserts the new fields, so it stays meaningful:

  | File:line | Test | Asserts |
  |---|---|---|
  | toolkit_test.sh:290 | `test_test_file_through_gate` | `studio-test-file … 0` |
  | toolkit_test.sh:305 | `test_test_file_several_positionals` | `studio-test-file … 0` |
  | toolkit_test.sh:878 | `test_gate_signal_waits_for_child_then_releases` | `sig … 143` |
  | toolkit_test.sh:940 | `test_gate_unit_registration_and_times` | `studio-test … 0` |
  | toolkit_test.sh:961 | `test_gate_times_window_per_who` | `setup … 0` |
  | toolkit_test.sh:983 | `test_gate_run_cap_stops_a_long_run` | `t … 124` |
  | toolkit_test.sh:1020 | `test_gate_run_cap_no_false_stop` | `assert_not_contains ' 124$'`. **With 8 fields this passes vacuously**, silently weakening the "no false 124" proof that D4 rests on. It becomes "no row has `$4 == 124`", plus a positive check that the run's row exists. |
  | toolkit_test.sh:1041 | `test_gate_run_cap_production_seconds` | `prodcap … 0` |
  | studio_setup_test.sh:64 | `test_setup_runs_under_lock_and_logs` | `setup … 0` |
  | studio_setup_test.sh:123 | `test_setup_gate_green_and_red` | `gate … 0` |

- Readers must accept rows of 4 fields (history) and of 8.

**Retention (D9).** Keep a row if it is among the newest 50 for its `who` **or** is younger than 14 days, with a
cap of the newest 20000 lines overall. The rewrite (cat + awk + temp + mv) is done under the reclaim mutex. If the
mutex cannot be taken within about 5 s, the gate falls back to today's unlocked write and never blocks its own
release. The existing tests use epoch-1 rows, which stay subject to the 50-per-`who` rule.

**Lock dirs.** They gain `class` and `wt` (§7). `gate_line` in studio-overnight, which is not #70's ground, keeps
its first line exactly (`gate: free` or `gate: <who> (pid <p>) for <t>[, unit <u>]`). Two tests assert
`^gate: free$`. When the slot is held, it adds a second line:
`gate short lane: <who> (pid <p>) for <t>[, unit <u>]`.

## 11. R7 — the planning rule and the autopilot merge (text changes)

Where the text says how units test today, and what each place changes to. `<vitest form>` below is
`cd <node dir> && studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2 <file>…` (phoenix's node dir
is `web-tools/`), and `<tsc form>` is `cd <node dir> && studio-gate tsc -- npx tsc --noEmit`.

| Place | Today | Change |
|---|---|---|
| `studios/game-dev/skills/execute/SKILL.md` §3, `unit` bullet (`:390-396`) | "Before reporting, the implementer runs `studio-test` and pastes its summary line." | "Before reporting, the implementer runs `studio-test --file` on every test file the task created or changed (calls of up to three files each take the short lane), and pastes each summary line. The whole suite (`studio-test`) runs at the finish gate, or before reporting when the task's `Verify:` includes `suite`." |
| execute §3: a new bullet after `visual` | — | "`suite` — the implementer also runs the whole suite (`studio-test`) before reporting and pastes its summary line." |
| execute §4a rule 2, the fixer brief (`:461-463`) | "run the task's tests — the `Verify: unit` test files the task names, then `studio-test` —" | "run the task's tests — `studio-test --file` on the test files the task and the fix touched, then `studio-test` only when the task's `Verify:` includes `suite` —" |
| execute §2, the implementer/fixer brief line (`:380-383`) | names `studio-test --file` for one file | It appends: "a targeted vitest runs as `<vitest form>`, tsc as `<tsc form>` — the `cd` outside the gate, never `sh -c` inside it; the whole suite runs only when `Verify:` includes `suite`". |
| execute §5 step 1 and its brief text (`:491-493`, `:522-525`) | "the implementers ran the tests per task" | "the implementers ran each task's touched tests" (still true). The finish gate's whole suite is unchanged. |
| `studios/game-dev/agents/gameplay-programmer.md`, Method step 3 (`:35`) and the playtest/visual paragraph (`:49-50`) | "Run `studio-test` for the whole suite"; "run `studio-test` to prove nothing regressed" | "Run `studio-test --file` on every test file the task touched (up to three per call); run the whole suite only when `Verify:` includes `suite`". For playtest/visual-only tasks with no touched test file, no GUT run happens at the task: the finish gate covers it. |
| `studios/game-dev/skills/plan/SKILL.md` §4 Verify (`:119-140`) | the kinds `unit`, `playtest`, `visual` | Add `suite`: "the task changes a seam whose effects reach tests it does not touch (an autoload, a shared base script, the GUT config or its hooks, project settings, an importer's output): the implementer runs the whole suite before reporting." Add one sentence: "Without `suite`, a task's tests are the files it touches; the whole suite runs at the finish gate." |
| plan SKILL §2 (`:84-90`) | "tests as `studio-test` or `studio-test --file <test file>`" | It appends: "targeted vitest as `<vitest form>`". |
| `shared/omega/skills/autopilot/SKILL.md:119` (adopted plans' Global Constraints) | "heavy commands … wrapped as `studio-gate <who> -- <cmd>`" | Add the vitest and tsc short-lane forms in the same sentence. |
| `shared/omega/skills/autopilot/SKILL.md:73-107` (run setup: the lane count, merged into the run worktree's `.studio/config.json` and committed with the manifest) | merges `overnight.max_lanes` only | **U7.** The same `python3 -c` merge also sets `test_engine_args`, `user_dir` and `gate_short_lane` when the project is opted in, keeping every other key; with no file it writes them beside `overnight`. The manifest commit already adds `.studio/config.json`. The opt-in source is the builder's call (§17); the default is one more question in the same `AskUserQuestion` as the lane count, asked only for a `godot4` project, its option "on" naming the three values. Tests: `tests/omega_contracts/autopilot_contract.sh` pins the merge text (next to its `max_lanes` assertions at `:65-76`), and a test runs the one-liner on a fixture config: the keys are set, `merge_command` and `overnight` are kept, a second run is idempotent, and "off" leaves the file byte-identical. |
| `bin/studio-brief` | It carries plan text verbatim and says nothing on how units test. | **No change.** Plans already in flight keep their own Global Constraints. That is the "overridable" part of U3. |
| `README.md` gate paragraph (`:149-151`, `:173-176`) | "One gate lock per project … only one test or gate run at a time" | It describes the main lane plus the short slot, the three config keys, the new `gate.times` columns, the leak and commit guards, and the cleanup after a SIGKILLed gate (O16). |

The pointer-skills tests (`tests/pointer_skills_*`) that pin skill text are updated with the text.

## 12. Constraints

- **POSIX sh.** Everything runs under macOS `/bin/sh` (bash 3.2) and dash. There are no arrays, no `BASHPID`, no
  `local`, and no GNU-only flags. `stat` and `sysctl` differ between platforms, so wrap them.
- **Load and CPU.** On macOS, use `sysctl -n vm.loadavg` (`{ 1m 5m 15m }`) and `sysctl -n hw.physicalcpu` (O9).
  On Linux, use `/proc/loadavg` and the count of distinct (`physical id`, `core id`) pairs in `/proc/cpuinfo`.
  Anything unreadable means no short lane (D13). The test-only
  seam `STUDIO_GATE_LOADAVG` gives the 1-minute value; it is named in the header, and the default reads the
  system.
- **Harness conventions** (`tests/assert.sh`, README "Tests"):
  - use `mk_tmp` and `rm_tmp`;
  - use the fake Godot stub (`GODOT_PATH=$GODOT_STUB`; the `STUB_SLEEP` and `STUB_FAILS` knobs);
  - use `gate_proj`, plus a new helper that adds linked worktrees to the temp repo;
  - scope `pgrep` and `pkill` to `$TMP`;
  - tag tests that bound elapsed time or beat windows `TESTS_EXCLUSIVE`, with `exclusive-scan` rulings;
  - raise the floors in `run_all.sh` (toolkit_test 175, studio_test 674, and any other suite that gains
    assertions);
  - name each new knob in its script's header (harness_test `:483`).
- **Tests never run real Godot or phoenix.** The throwaway Godot project and the phoenix runs are acceptance
  steps by hand (§13).
- **Hand-run suites** run from a scratch cwd with an existing `TMPDIR` (memory rule). The repo gate is
  `sh tests/run_all.sh`, run under `.git/heavy-suite.lock`.
- **Files to avoid** (#70, O5). The only change in studio-overnight is `gate_line`. overnight-lanes.sh and
  overnight-ids.sh do not change: final-gate and merge are already `exclusive` by argv.
- **Files that do change**, beyond §5–§11: `studios/game-dev/hooks/lanes-guard.sh` (new) and `hooks/hooks.json`
  (the commit guard, §8), and `engines/godot/isolate.sh`'s `--scrub` mode.

## 13. Acceptance

1. **Tests for every lane rule** (toolkit_test.sh unless named; stubs only):
   - **classify.** A table through `studio-gate --classify --`. It covers every whitelisted form and its near
     misses:
     - 3 files vs 4;
     - vitest with no cap, with `--maxWorkers=2` but no `--minWorkers=1`, with `--maxWorkers=3`, with a directory
       or a glob;
     - `sh -c "cd web-tools && npx vitest run …"` (exclusive) vs the same run with the `cd` outside the gate;
     - tsc with `-b`;
     - `npm test`, `sh -c`, `env X=1 …`, `merge.sh`, `run-tests.sh`, `studio-dispatch run`, an unknown command.

     A whole suite is shareable with the lane on and exclusive with it off. A vitest gated from a subdirectory
     (`web-tools/`) reads lane-on and `wt` from the git top level.
   - **beside shareable.** While a stub whole suite holds the main lane, a short file run in another worktree
     completes. Recorded intervals overlap. Its row has lane `short` and a wait under 3 s.
   - **never beside exclusive.** While `x -- sleep` holds the main lane, a short check waits until release.
     Its intervals do not overlap and its lane is `main:beside exclusive`.
   - **drain and no starvation.** With a short check in the slot, an exclusive caller waits. A second short check
     that arrives after the exclusive caller registered is not admitted. The exclusive caller runs before it, and
     never overlaps the slot.
   - **three-way no-overlap.** Exclusive, shareable and short callers under contention: no exclusive interval ever
     overlaps any other interval. This extends `test_gate_three_reclaimers_never_overlap`.
   - **same worktree.** A GUT short check from the suite's own worktree goes to the main lane (`same worktree`).
     A vitest from that worktree's `web-tools/` takes the slot beside the suite (O14). A second vitest in that
     worktree while one holds the slot does not.
   - **isolation.** Without `override.cfg`, a GUT short check goes to the main lane (`iso`), while vitest in the
     same state takes the slot.
   - **load.** `STUDIO_GATE_LOADAVG=99` refuses the slot, `0` admits, and an unreadable value refuses. The
     threshold follows the physical-core count (through a test seam), not `hw.ncpu`.
   - **nice.** A slot run's stub sees a niceness 10 above the gate's; a main-lane run, a short check that took the
     main lane and a demoted re-run see the gate's own.
   - **lane off.** With no key, a short check waits behind a whole suite exactly as today: the same rows apart
     from the new fields.
   - **run fallback (D15).** Keys only in `$STUDIO_START_DIR/.studio/config.json` reach a story worktree with no
     config (lane on, engine args passed, isolation written); a key in the story worktree's own config wins; with
     `STUDIO_START_DIR` unset the story worktree is lane-off.
   - **stale.**
     - A dead or pidless `gate.short/` is reclaimed.
     - A `gate.short/` naming a live pid that is not a gate (`sleep`) is reclaimed.
     - A dead `gate.wantx/<pid>` is removed and does not block admission.
     - A live main holder with no `class` blocks the slot.
   - **short cap.** `STUDIO_GATE_SHORT_SECONDS=2` on a stub that sleeps 5 s. The stderr line appears, the command
     runs a second time in the main lane, the rows are `short 124` then `main:demoted`, and the exit status is the
     re-run's. With `STUDIO_GATE_MINUTES=1` and `STUDIO_GATE_SECONDS` below the short cap, the result is 124 with
     no re-run. A production-default carrier test reads the default.
   - **demote.** A child that touches `$STUDIO_GATE_DEMOTE` is re-run in the main lane once. A demoted re-run
     cannot be demoted again.
   - **re-entry.** A nested gate under a slot holder execs (no wait, no row). The main-lane re-entry tests are
     unchanged.
   - **signals.** INT/TERM during a slot run is forwarded, the slot is released, the exit is 128+n and there is
     no re-run.
   - **units.** A slot gate registers under `gate.units/<tag>`, and `unit_reap` ends it (overnight_test).
   - **records.**
     - The 8-field row shape is right.
     - A file of 4-field rows is kept and read.
     - `gate_room_check` gives the same result over a mixed file.
     - The 14-day retention holds.
     - Two gates finishing together lose no row.
   - **messages.**
     - The waiting prefix is unchanged.
     - The reason is printed at once for a refused short-eligible caller.
     - An exclusive caller names a slot holder `(…, short lane)`.
     - With the main lane free and the slot busy, `gate_line`'s first line is still exactly `gate: free`, and a
       second line names the slot holder.
   - **engine args** (studio_test / toolkit).
     - The stub records `--headless --fixed-fps 60 --path …` before `-s`, for the whole suite and for `--file`.
     - With no key, the argv is byte-identical to today's (golden).
     - A bad value (a quote, `;`, `-s`, `--path`) exits 1 and names the key.
     - Allowlist: `--fixed-fps 60` passes; `--fixed-fps` with no value, `0`, `abc`, and every flag the falsifier
       listed (`--main-pack x`, `--scene x`, `--quit-after 1`, `--write-movie x`, `--log-file x`, a bare
       `res://x.tscn`) exit 1.
     - `"tests": "gut"` and `engine` are still read.
   - **rc anchors.** Each of the ten rewritten assertions (§10) fails against a planted row of the wrong rc; the
     `:1020` rewrite fails when a `124` row is planted in the 8-field shape.
   - **leak guard.** With the stub "engine" appending the two lanes lines to a tracked `project.godot` in an
     opted-in linked worktree: the lines are gone after the gate, the stderr line appears, and the exit is 1 for a
     passing command (the failing status is kept for a failing one). A `project.godot` whose `HEAD` sets the keys
     is left alone. A lane-off project and the main checkout are never scrubbed.
   - **commit guard** (hook_test). `git commit` (also `git -C <wt> commit -am`, and after `cd <wt> &&`) is denied
     when the index or working tree adds a lanes line; allowed when the lines are absent or in `HEAD`; any other
     command and any malformed input print nothing.
   - **isolate.sh.**
     - It writes only in a linked worktree with the key, and never in the main checkout.
     - It never overwrites a foreign or tracked `override.cfg`.
     - The exclude line is added once, and a repeat run is idempotent.
     - `--check` passes and fails as specified.
     - The sweep removes only dirs of dead ids and older than 1 h, respects the daily stamp and never follows a
       symlink. A fake data root is used through a test seam, `STUDIO_GODOT_USER_ROOT`.

2. **Synthetic benchmark** (by hand, scratch dir, stub engine, no phoenix).
   - Setup: a temp repo with the lane on and 3 linked worktrees. A whole-suite `studio-test` holder (`STUB_SLEEP=180`)
     runs, and 20 short calls (`studio-test --file`, 10 targeted-vitest stand-ins) start every 5 s across the
     worktrees.
   - Run it with the lane off, then on. Report the waits from `gate.times` field 5.
   - Pass:
     - lane on, short p90 wait ≤ 5 s;
     - lane off, p50 ≈ the remaining hold;
     - an exclusive-holder variant shows lane-on shorts waiting (exclusivity kept);
     - the exclusive caller's extra wait for the drain is ≤ the short cap + 15 s.

3. **Throwaway Godot project** (real Godot, GUT copied in, under the scratchpad; not phoenix).
   - Two linked worktrees with `"user_dir": "per-worktree"`. Concurrent GUT file runs, each writing and re-reading a
     fixed `user://probe.cfg`, never see each other's value.
   - The default `app_userdata/<name>` dir is untouched.
   - A test run with `test_engine_args` proves fixed fps reached the engine. The builder picks the probe, for
     example 120 physics frames finishing in well under 2 s of wall time.
   - Leak guard, real engine: in a worktree with our `override.cfg`, a gated `--headless -s` script that calls
     `ProjectSettings.save()` bakes the keys (as the falsifier saw); the gate removes them, prints its line and exits
     1, and `git diff -- project.godot` shows no lanes line. Before the scrub, `lanes-guard.sh` fed a `git commit -am`
     as hook input denies it. `--import` and `-e --quit` leave `project.godot` unchanged (re-confirmed).

4. **No new flaky reds (live, phoenix quiet, `.git/heavy-suite.lock` held; O13).**
   - Setup: a phoenix linked worktree with the three keys set locally and uncommitted. This is an acceptance
     worktree, not a run's. The *lane load* is a continuous loop of short-lane checks in a second worktree: a GUT
     file run (≤ 3 files, including `test_settings_cfg_isolation.gd` and `test_placeholder_icon.gd`, the
     `user://`-sensitive ones) and a targeted vitest in the O10 form.
   - (a) **The wall-clock-sensitive subset**, 20× solo, then 20× with the lane load beside it. The subset is every
     test file that reads wall time in an assertion or a deadline loop (`Time.get_ticks_*`, `OS.get_ticks_*`,
     deadline `while` loops). The falsifier's list is the floor: `test_vfx_clock.gd`, `test_death_mark_player.gd`,
     `test_spawn_art_reads.gd`, `test_area_record_prefetch.gd`, `test_loading_animal_prefetch.gd`, the users of
     `helpers/hitbox_window_harness.gd` and the audio-service gap tests. The builder greps for the full set and
     records it in the PR. Each run is at fixed fps and must hold the main lane as `shareable`, so the lane load can
     run in the slot beside it: a `--file` list of 4+ files is `exclusive`, so the builder picks the form (for
     example a directory run over a scratch directory holding the subset) and records it.
   - (b) **The whole suite** at fixed fps, 3× solo, then 3× with the lane load beside it.
   - Pass, for (a) and (b) each: no test is red in any with-lane run that is green in every solo run, and every
     with-lane row shows lane `short` for the load.
   - **Fail closed.** A new red fails. A test that is red in some but not all solo runs makes the comparison
     inconclusive for it, and a run that crashes, times out or shows no lane-`short` load rows is void; either
     fails too. It is reported (as `test_nav_region_baker` was in 2026-10-02-studio-test-speed-findings.md), and the
     lane stays off in phoenix until the flake is fixed or quarantined in phoenix and the step passes on a re-run.
   - Budget: (b) is 6 suite runs ≈ 90–100 min on this machine at 816–1002 s each; (a) is 40 subset runs.

5. **The full gate with isolation.** `studio-setup gate` (run-tests.sh) in an opted-in phoenix linked worktree, solo,
   has the same red set as in a non-opted-in one. That proves the CI-like fresh `user://` breaks nothing.

6. **No suites during a final gate.** Over the first live runs, no `gate.times` row of lane `short` overlaps a
   row of class `exclusive` in time. The script checks this.

7. **Before/after wait per verb.** `python3 -I tests/probes/gate_wait_measure.py --since <install day> --validate`.
   - It is extended to accept 4- or 8-field rows, prefer field 5 over inference, attribute blockers per lane (a slot
     holder never blocks the main lane), and print per-lane counts of short-eligible calls by reason.
   - Before: the §1 baseline (14 days to 10-19). After: the first live runs after install, plus benchmark 2.
   - **Metric: recovered share, per verb (O15).** Take each call of a short verb (studio-test-file, targeted
     vitest, tsc/lint; every form, `sh -c` included) that arrives while a whole-suite `studio-test` from a lane-on
     worktree holds the main lane. *Exposure* = that suite's release − the call's arrival (arrival = epoch − hold −
     wait). *Waited* = min(the call's acquisition, that release) − arrival. Recovered share = 1 − Σ waited /
     Σ exposure.
   - **Why this metric.** Under one lock a call that arrives during a hold waits it out, so Lever 1 alone scores 0.
     The old metric, short-call minutes behind whole suites per 100 short calls, grows with the square of the hold
     (arrivals ∝ hold, and each waits half a hold on average), so Lever 1's 2× alone would cut it by about 75%. It
     is still printed, but not judged.
   - **Ceiling and targets (the computation).** The baseline was replayed under this design's rules, with each
     call's worktree taken from its transcript `cwd`. A minute a short call spent behind a > 10-min suite hold is
     recoverable unless: its argv is not short-eligible (`--file` with 4+ files; vitest or tsc inside `sh -c`; a
     lint other than tsc or eslint); it is a GUT check in the suite's own worktree (D3, O14: 0 min found, since a
     session's calls are serial); or an exclusive caller was already waiting (D5, O8). The load gate and demotions
     are not modelled. The total is 2449 min, not §1's 3077, because only these three verbs count and only the
     overlap of each wait with a suite hold is taken.

     | Verb | Behind-suite min | Recoverable | Ceiling | Main loss | Target |
     |---|---:|---:|---:|---|---:|
     | studio-test-file | 1528 | 1214 | 79% | 4+ files 294 min; D5 21 | **≥ 55%** |
     | targeted vitest | 777 | 325 | 42% | `sh -c` 427 min; D5 25 | **≥ 30%** |
     | tsc / lint | 144 | 123 | 85% | other lint 21 | **≥ 60%** |
     | all three | 2449 | 1661 | 68% | | **≥ 50%** |

     Target = 0.75 × ceiling, rounded down to 5%. The 25% margin is for load-gate refusals (O9) and demotions,
     which the replay cannot see. The ceiling counts `sh -c` calls as lost at today's habits (39% of targeted-vitest
     calls, 55% of their minutes); the §11 text should shrink that, which can only raise the share.
   - Pass:
     - every verb with ≥ 30 exposure-minutes in the after window meets its target (a verb under 30 is reported,
       not judged), and so does the all-three row;
     - in lane-on worktrees, at least one short-eligible call ran in the slot (A3), and no single refusal reason
       accounts for most short-eligible calls without an explanation in the PR;
     - the waits behind final gates are reported separately and are expected to be unchanged (A2).

**Errata (implementation).** Where the built gate differs from the text above:

- (a) Under §7 the slot is preferred, so the `gate.times` row of a short run beside an exclusive waiter or holder reads lane `short`.
- (b) A GUT short from the shareable suite's own worktree waits for the suite, then takes the slot. `main:same-worktree` is therefore unreachable.
- (c) The tests whose names end in `_gut_goes_main` now assert that the GUT short takes the slot. Their names are historical.
- (d) §8 amendment: the gate's leak scrub runs after every run in an opted-in linked worktree, except a node check. A vitest, tsc or lint run is never scrubbed, because it never launches Godot, and a scrub could race a same-worktree Godot save.

## 14. Rollout

1. Build and review in this worktree. The full repo gate `sh tests/run_all.sh` runs under `.git/heavy-suite.lock`.
   Then a PR.
2. **Install only by merging the PR.** The memory rule: never reinstall or pull into the main checkout while a
   phoenix run is live. Install when phoenix is quiet, so that no old-version gate process is alive (old gates know
   nothing of the slot; D11 covers only the reverse direction).
3. **Phoenix gets its keys from the autopilot (U7).** No phoenix `main` commit. What was found:
   - `.studio/config.json` is **tracked on phoenix's run branches**: `run/combat-vfx-library`'s index lists it,
     phoenix's `info/exclude` has `!.studio/config.json`, and studio-overnight refuses an uncommitted one.
   - It is **absent from the phoenix main checkout** (working tree and `main` index); `origin/main` is unverified.
     U7 makes that moot: the autopilot merges into whatever file the run worktree has, or writes one.
   - The three keys (`"test_engine_args": "--fixed-fps 60"`, `"user_dir": "per-worktree"`,
     `"gate_short_lane": "on"`) are merged at run setup and committed with the manifest (§11).
   - Story worktrees do **not** carry them: story branches are cut from `origin/<Target>`, and execute §0 checks out
     only the spec, plan and ledger from the run's docs commit. Phoenix's story and integration worktrees have no
     `.studio/config.json` today (only the `run-*` worktrees do). Units reach the keys through the run fallback
     (D15).
   - It takes effect from the **next run started after install**. Live runs, and any run whose operator answers
     "off", behave exactly as today (A5).
4. Run acceptance steps 3–5 when phoenix is quiet. Only then answer "on" at the next run's setup. Then measure
   (step 7) after the first live runs.
5. **Rollback.** Answer "off" at the next run's setup, or remove the keys from a run branch's config. That gives
   today's behaviour, with the new `gate.times` columns kept (harmless).

## 15. Risks

| Risk | Mitigation |
|---|---|
| Load-sensitive GUT tests (`Time.get_ticks_msec`) still flake beside a short check, even at fixed fps. | `nice -n 10`, the load threshold, the worker cap, ≤ 3 files and the 5-min kill. Acceptance 4 (20× subset, 3× suite, fail closed) is the gate; if it fails the lane stays off in phoenix. |
| The fresh per-worktree `user://` turns a test red that relied on the developer's `user://` files. | Acceptance 5. Phoenix's sandboxes and its CI already run on a fresh `user://`. |
| The editor or a test bakes `use_custom_user_dir` into `project.godot` (**verified**: `ProjectSettings.save()` does). | The leak guard scrubs it after every gated run and fails the run; the commit guard refuses a studio commit carrying it (§8). A hand commit in a terminal is the remaining gap (§16). |
| The load gate refuses whenever a suite runs (baseline load ≈ 5 on 4 physical cores), so the lane is dead. | O9's rule is justified against that baseline; the `load` reason is printed and counted (A3), and acceptance 7 fails on a dead lane. |
| Units keep the `sh -c "cd web-tools && …"` habit, so vitest stays exclusive. | The §11 text names the direct form; acceptance 7's vitest target already assumes today's habits. |
| D5's priority reorders exclusive callers ahead of waiting suites. | A bounded change. It is visible in the after-measurement, and the builder may scope it to lane-on (§7). |
| A demoted re-run wastes up to 5 min. | It is logged (`main:demoted`). If the measurement shows many demotions, tighten the whitelist. |
| The `gate.times` rewrite under the mutex adds a little mutex hold time. | Bounded at about 20 ms. A 5 s fallback means the gate never blocks its release. |
| Two Godot runs with identical report stamps in one worktree. | Forbidden by D3; a node check beside a Godot run writes no Godot report (O14). |
| An `npm run build` beside a functional suite in the same worktree. | Exclusive, because `npm` is opaque. |

## 16. Rejected alternatives and follow-ups

- **Shards of the whole suite.** Deferred in #22: there were order-dependent shard-only failures.
- **A `HOME` override per lane.** It breaks git, git-lfs and npm config for children, and caused shard-only
  failures before.
- **Classifying by the `who` label.** The label is free text, so `vitest` could wrap `npm test`.
- **Exiting 124 on the short cap.** Every unit would read it as `Stop: gate timed out`.
- **Two or more short slots.** The user decided on one (U2). Revisit with the after-data.
- **On by default.** That breaks A5 and makes rollout depend on install timing.
- **Follow-ups (not in this story):**
  - Bash-timeout re-queues: a gate-aware timeout, or not counting the wait.
  - Allow rules for the short-lane vitest and tsc forms in `overnight-allow.txt`.
  - #60.
  - A `studio-test --file` form taking more than 3 files that splits itself into short calls.
  - Record each holder's child pgid in the lock dirs and treat a lane as busy while that group lives (O16, A8).
  - A lanes-line check in phoenix's own pre-commit hook, for hand commits (§8). A phoenix change: the user's call.
  - Refusing the slot on a configured env denylist (`AI_RUNNER_SMOKE`), if the builder does not do it here (O16).

## 17. Left to the builder

- Inline vs a sourced `bin/gate-class.sh`, and confirming that install ships it.
- Comparing `studio-dispatch` identity portably.
- Whether eslint stays in the whitelist. (The vitest probe is done: `--minWorkers=1` is required, O10.)
- Whether D5 applies only when the lane is on (the author leans yes).
- **The load rule (O9):** the exact threshold from `hw.physicalcpu`, justified in the PR against a load sample
  taken during a fixed-fps suite with two live runs; whether a config key may override it.
- **The engine-args allowlist (O11):** flags beyond `--fixed-fps`, each with a value check and a test.
- **The opt-in source for U7:** the default is one more autopilot setup question for `godot4` projects (§11).
- The leak guard's exact line patterns, and whether `--scrub` also runs at `studio-test`'s start (cheap, and it
  catches an editor bake before the run rather than after).
- How acceptance 4(a)'s subset run holds the main lane as `shareable`, and the recorded subset list.
- Folding the acceptance-7 replay (worktree from transcript `cwd`, the ceiling rules) into
  `tests/probes/gate_wait_measure.py` as a `--ceiling` mode, so the targets can be re-derived.
- The demote file's exact path and contents.
- Whether to print one `gate: got the <lane> lane after <n> min` line when wait ≥ 60 s.
- The fixed-fps probe in acceptance 3.
- Linux verification of `override.cfg` (until then `--check` refuses on non-Darwin).
- The exact rotation awk.
- The 1-h sweep guard.
- The falsifier's remaining minors, each addressed or recorded with a reason: B2 (bound a waiting shareable caller
  under D5, e.g. FIFO by `since`), B4 (a shareable suite's own `ensure_import` beside the slot), B6 (the common
  `info/exclude` line also hides a developer's untracked `override.cfg` in the main checkout), B7 (key the
  `-lanes` dir by a hash of the git common dir, so two clones never sweep each other), B8 (lane-off exceptions:
  D9 retention, `studio-dispatch isolate` printing `no adapter` for other engines), B9 (D10 should match
  `sh <path>/studio-gate ` at the start of `ps` args).
- The test-only seams `STUDIO_GATE_LOADAVG`, `STUDIO_GATE_SHORT_SECONDS`, `STUDIO_GODOT_USER_ROOT` and the
  physical-core seam, each named in its script header with a production-default carrier test.
- Splitting the work into tasks. Per-task review is mandatory for the gate state model (new seam), isolate.sh and
  the leak guard (data/cross-system), the commit guard hook, and the classifier. The skill text, the autopilot
  merge and README fold into the final review.

## 18. Falsify

A spec falsifier and the planner should try to break these claims before the plan is approved:

1. Barring SIGKILL of a holding gate (O16), no interleaving of polls, releases, crashes or pid reuse lets an
   exclusive holder overlap any other holder, or wedges the slot for longer than the cap + 15 s while its gate is
   dead.
2. Every exclusive caller eventually runs while short checks keep arriving (D5 plus the wantx block).
3. The whitelist admits, by argv, nothing that can start cucumber, Godot `--import`, a build, a second Godot in one
   worktree or two node checks in one worktree. Test contents and env are outside argv; what they can start is
   bounded by `nice`, the cap and the load gate (O16).
4. With no keys set, every argv, row prefix, stderr line and exit status is today's (A5). The single deliberate
   exception is the appended `gate.times` fields (and the falsifier's B8 list, which the builder closes or records).
5. Every word `test_engine_args` accepts is on the allowlist; nothing else reaches Godot.
6. Nothing writes `override.cfg` in a main checkout, over a foreign or tracked file, or deletes a live worktree's
   user dir.
7. A short-cap kill or a demotion never surfaces as exit 124 unless `STUDIO_GATE_MINUTES` ≤ 5.
8. No gated run in an opted-in worktree ends with a lanes line in `project.godot` that `HEAD` lacks, and no
   studio commit adds one (A6).
9. The three keys reach every unit of an opted-in run, in story worktrees too (D15), and nothing outside a run.

## 19. The user's answers (2026-10-19)

The open questions are answered; the decisions are U5–U8 (§4).

1. **Where phoenix's keys go.** The autopilot merges them into each run branch's config at setup and commits them;
   no phoenix `main` commit (U7). Units reach them through the run fallback (D15).
2. **Opt-in.** Yes, per project; a project without the keys behaves exactly as today (U8).
3. **GUT single-file checks on the short lane.** Yes, behind the leak check and the commit guard (U5, O7).
4. **The planning rule.** Unchanged (U6). Exclusive priority (D5) stands as an orchestrator call (O8).
