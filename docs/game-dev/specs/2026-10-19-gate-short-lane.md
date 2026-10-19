# Gate short lane: short checks no longer wait behind a whole-suite run — Design

Date: 2026-10-19
Status: Design, for the operator's review. Not a plan: interfaces are sketched, and the code is left to the builder.
Story: #71 (GitHub issue). It includes #69 item 1 (studio-test takes the project's engine args). Branch
`issue-71-gate-short-lane`, off `origin/main` 18fd2e0.
Classification: architectural. It changes the gate's concurrency contract (one lock becomes a main lane plus one
short slot), adds two project config keys to the Godot adapter and one to the gate, and changes the planning rule
for how task units test.

## 1. What happened, and the numbers

On 2026-10-19 at about 10:51 CDT, phoenix unit KAN-1623 held `.studio/gate.lock` with a whole-suite `studio-test`
for **32.8 min**. A one-file `studio-test --file tests/unit/test_telegraph_integration.gd` (24 s of work) waited
**32.9 min** behind it, and a two-file targeted `vitest run` (about 25 s) waited **30.5 min**. The machine was at
load about 3 of 8 cores, with 80% of memory free. The same pattern happened four more times that day.

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
| The same suite at `--fixed-fps 60` (phoenix `merge.sh`) | about **150 s** |
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
   Phoenix runs at `--fixed-fps 60`, as its `merge.sh` does. That makes the whole suite frame-paced (about 150 s
   instead of 20–33 min). It also removes the wall-clock reds that differ between `studio-test` and `merge.sh`
   (#69's T8 hold).
2. **Give short checks their own slot.** One short slot runs beside a whole-suite `studio-test`, and only beside
   one. It admits only checks proven short and isolated from that suite. Nothing ever runs beside a final gate.

Lever 1 alone shrinks the blocking hold about 8×. Lever 2 removes the remaining wait behind whole suites. The 12%
of short-call wait spent behind final gates stays. That is deliberate (anti-goal 2).

## 3. Goals, non-goals, anti-goals

**Goals**

- G1. A short check never waits behind a whole-suite `studio-test` when it is admissible to the short slot. That
  means a whitelisted verb, isolation in effect, load under the threshold, no exclusive waiter, and a different
  worktree from the suite's.
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
- Any change in phoenix beyond its `.studio/config.json` keys (§13, which is a dependency for the user to approve).

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

### Orchestrator calls (the builder may refine them, with a recorded reason)

- O1. Classification is a whitelist by verb and argv. Anything unrecognised is exclusive, so the gate fails
  closed. The main-lane holder records its class in the lock dir: `shareable` is a whole-suite `studio-test`;
  `exclusive` is everything else, including run-tests.sh, merge.sh, studio-run, setup and unknown commands.
- O2. Admission to the short slot also requires two things:
  - for a GUT check, per-worktree `user://` isolation is in effect (otherwise it falls back to the main lane);
  - the 1-min load average is below a threshold (ncpu − 2).

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

### Author calls (made in this design; the builder may refine them with a recorded reason)

- D1. **The lane is opt-in per project.** It is on only when `"gate_short_lane": "on"` is in the caller's
  worktree `.studio/config.json`. A whole-suite holder records `shareable` only when its own worktree has the lane
  on; otherwise it records `exclusive`. Reason: A5, and a controlled rollout, so an install changes nothing until
  phoenix's config commit lands.
- D2. **`user://` isolation is opt-in** through `"user_dir": "per-worktree"`, which the Godot adapter reads. It is
  written lazily by `studio-test` (through the adapter) before the gate is called. It is never written in the
  main checkout, never over a foreign `override.cfg`, and never where `override.cfg` is tracked. Reason:
  override.cfg moves `user://` for *every* Godot launch in that worktree, so a project has to choose it (§8).
- D3. **No two holders in one worktree, in any lane.** The lock dirs record `wt`. Two Godot runs in one worktree
  race on `.godot/` and on the report stamp. Two vitests race on vite's results cache.
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
  characters allowed are checked, and so are the words (§5).
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
- D13. **An unreadable load average means no short lane.** The threshold is max(1, ncpu − 2).
- D14. **The measurement script is committed** as `tests/probes/gate_wait_measure.py`, updated to read the new
  columns (§11).

## 5. R1 — studio-test passes the project's engine args (#69 item 1)

**Config.** Add a top-level flat string to `.studio/config.json`, the same file `studio-dispatch` reads `engine`
from (the current directory's):

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
- These words are refused: `-s`, `--script`, `--path`, `-e`, `--editor`, `--import`, `--` and anything after
  them. The adapter owns those.
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
| short / node | vitest: `npx [--no-install] vitest run …` or `[./]node_modules/.bin/vitest run …`. It needs **exactly one** worker cap, `--maxWorkers=1` or `--maxWorkers=2`, and optionally `--minWorkers=1`. It needs **at least one** positional, and **every** positional is an existing regular file relative to cwd. The only other options allowed are `--reporter=<word>`, `--silent`, `--no-color`, and `-t <pattern>` / `--testNamePattern=<pattern>`. |
| short / node | tsc: `npx [--no-install] tsc --noEmit` or `[./]node_modules/.bin/tsc --noEmit`. The only options allowed are `-p <file>` / `--project <file>` and `--pretty false`. `-b` / `--build` and `--watch` are not allowed. |
| short / node | eslint: `npx [--no-install] eslint <file>…` or the `node_modules/.bin` form. Every positional is an existing regular file. The only options allowed are `--max-warnings <n>` and `--format <word>`. |
| exclusive | **everything else**. That includes: `sh -c …` (final-gate, studio-setup's gate and setup); `merge.sh`; `run-tests.sh`; `studio-dispatch run` (studio-run); `studio-dispatch test --file` with 4 or more files; `npm …` (scripts are opaque); `env`/`VAR=` prefixes; `studio-gate godot -- …`; vitest with no cap, a cap above 2, a directory or a glob; and any unknown command. |

Notes:

- A vitest positional is a filter, not a path. A substring can match more than one file. Requiring every
  positional to be an existing file keeps the run narrow, and the cap and the 5-min kill bound the rest.
- Today's phoenix convention, `studio-gate vitest -- npx vitest run <path>`, has no worker cap. It stays exclusive,
  and only the new text (§9) makes it short. That is fail-closed by design.
- The builder must probe `--maxWorkers=2` without `--minWorkers` in a scratch vitest 2.1.9 project. Older vitests
  refused a max below the default min. If 2.1.9 refuses it too, the text and the whitelist require
  `--minWorkers=1` as well.

## 7. R3 — the lane state model

### State (all under `STATE_ROOT/.studio/`, already excluded by `.studio/gate.*`)

| Path | Meaning | Files |
|---|---|---|
| `gate.lock/` | The main lane. Its meaning is unchanged for every existing reader (studio-setup `:133-136`, `gate_line`, the tests). | `pid`, `who`, `unit`, `since` (as today), plus **`class`** (`shareable` / `short` / `exclusive`) and **`wt`** (the caller's worktree top level, `pwd -P`) |
| `gate.short/` | The one short slot. | `pid`, `who`, `unit`, `since`, `wt`, `class` = `short` |
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

Definitions:

- *main free*: no live `gate.lock/` pid (`kill -0`; stale or pidless is reclaimed as today).
- *slot free*: no live `gate.short/` pid (D10 liveness; stale is reclaimed).
- *X waiting*: there is a live `gate.wantx/` entry other than the caller's own (D10; stale entries are removed).
- *same-wt*: the caller's `wt` equals the `wt` of a live holder in either lane.
- *main class*: the `class` of the live `gate.lock/` holder. A missing class counts as `exclusive` (D11).

| Caller | Takes MAIN when | Takes SHORT when |
|---|---|---|
| exclusive | main free **and** slot free | never |
| shareable | main free **and** not X waiting **and** not same-wt | never |
| short | main free **and** not X waiting **and** not same-wt, but only when it cannot take SHORT (the slot is preferred, so the main lane stays free for a suite or an exclusive) | **all** of these: lane on (D1); slot free; not X waiting; main class ∈ {none, `shareable`, `short`}; not same-wt; isolation in effect when the check is `gut` (§8); 1-min load < max(1, ncpu − 2) (D13) |

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
  keep lane-off projects identical to today. The author leans towards "only when on", for A5.

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
  | `same worktree` | a holder is in the caller's worktree |
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

- the worktree's config says `"user_dir": "per-worktree"` (D2);
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

## 9. R5 — how a unit reaches the short lane

- **GUT.** The unit does what it already does: `studio-test --file a.gd[,b.gd,c.gd]`. Calls of up to 3 files are
  short-eligible. A call of 4 or more files is still correct, but it waits for the main lane.
- **vitest / tsc / eslint.** These are gated today only by convention (plan Global Constraints, ledger directives,
  autopilot SKILL `:119`), and no hook or allow rule is needed. The minimal entry point is the existing wrapper
  with the whitelisted argv:

  ```
  studio-gate vitest -- npx vitest run --maxWorkers=2 tests/a.test.ts tests/b.test.ts
  studio-gate tsc -- npx tsc --noEmit
  ```

  Units run these through the auto-mode classifier today, and phoenix's `gate.times` shows 50 rows each for
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
- The existing tests that anchor on `… <rc>$` (`test_gate_unit_registration_and_times`,
  `test_gate_times_window_per_who`) are updated to the new shape. The update is deliberate and strengthens them:
  they also assert the new fields.
- Readers must accept rows of 4 fields (history) and of 8.

**Retention (D9).** Keep a row if it is among the newest 50 for its `who` **or** is younger than 14 days, with a
cap of the newest 20000 lines overall. The rewrite (cat + awk + temp + mv) is done under the reclaim mutex. If the
mutex cannot be taken within about 5 s, the gate falls back to today's unlocked write and never blocks its own
release. The existing tests use epoch-1 rows, which stay subject to the 50-per-`who` rule.

**Lock dirs.** They gain `class` and `wt` (§7). `gate_line` in studio-overnight, which is not #70's ground, keeps
its first line exactly (`gate: free` or `gate: <who> (pid <p>) for <t>[, unit <u>]`). Two tests assert
`^gate: free$`. When the slot is held, it adds a second line:
`gate short lane: <who> (pid <p>) for <t>[, unit <u>]`.

## 11. R7 — the planning rule (text changes)

Where the text says how units test today, and what each place changes to:

| Place | Today | Change |
|---|---|---|
| `studios/game-dev/skills/execute/SKILL.md` §3, `unit` bullet (`:390-396`) | "Before reporting, the implementer runs `studio-test` and pastes its summary line." | "Before reporting, the implementer runs `studio-test --file` on every test file the task created or changed (calls of up to three files each take the short lane), and pastes each summary line. The whole suite (`studio-test`) runs at the finish gate, or before reporting when the task's `Verify:` includes `suite`." |
| execute §3: a new bullet after `visual` | — | "`suite` — the implementer also runs the whole suite (`studio-test`) before reporting and pastes its summary line." |
| execute §4a rule 2, the fixer brief (`:461-463`) | "run the task's tests — the `Verify: unit` test files the task names, then `studio-test` —" | "run the task's tests — `studio-test --file` on the test files the task and the fix touched, then `studio-test` only when the task's `Verify:` includes `suite` —" |
| execute §2, the implementer/fixer brief line (`:380-383`) | names `studio-test --file` for one file | It appends: "a targeted vitest runs as `studio-gate vitest -- npx vitest run --maxWorkers=2 <file>…`, tsc as `studio-gate tsc -- npx tsc --noEmit`; the whole suite runs only when `Verify:` includes `suite`". |
| execute §5 step 1 and its brief text (`:491-493`, `:522-525`) | "the implementers ran the tests per task" | "the implementers ran each task's touched tests" (still true). The finish gate's whole suite is unchanged. |
| `studios/game-dev/agents/gameplay-programmer.md`, Method step 3 (`:35`) and the playtest/visual paragraph (`:49-50`) | "Run `studio-test` for the whole suite"; "run `studio-test` to prove nothing regressed" | "Run `studio-test --file` on every test file the task touched (up to three per call); run the whole suite only when `Verify:` includes `suite`". For playtest/visual-only tasks with no touched test file, no GUT run happens at the task: the finish gate covers it. |
| `studios/game-dev/skills/plan/SKILL.md` §4 Verify (`:119-140`) | the kinds `unit`, `playtest`, `visual` | Add `suite`: "the task changes a seam whose effects reach tests it does not touch (an autoload, a shared base script, the GUT config or its hooks, project settings, an importer's output): the implementer runs the whole suite before reporting." Add one sentence: "Without `suite`, a task's tests are the files it touches; the whole suite runs at the finish gate." |
| plan SKILL §2 (`:84-90`) | "tests as `studio-test` or `studio-test --file <test file>`" | It appends: "targeted vitest as `studio-gate vitest -- npx vitest run --maxWorkers=2 <file>…`". |
| `shared/omega/skills/autopilot/SKILL.md:119` (adopted plans' Global Constraints) | "heavy commands … wrapped as `studio-gate <who> -- <cmd>`" | Add the vitest and tsc short-lane forms in the same sentence. |
| `bin/studio-brief` | It carries plan text verbatim and says nothing on how units test. | **No change.** Plans already in flight keep their own Global Constraints. That is the "overridable" part of U3. |
| `README.md` gate paragraph (`:149-151`, `:173-176`) | "One gate lock per project … only one test or gate run at a time" | It describes the main lane plus the short slot, the three config keys, and the new `gate.times` columns. |

The pointer-skills tests (`tests/pointer_skills_*`) that pin skill text are updated with the text.

## 12. Constraints

- **POSIX sh.** Everything runs under macOS `/bin/sh` (bash 3.2) and dash. There are no arrays, no `BASHPID`, no
  `local`, and no GNU-only flags. `stat` and `sysctl` differ between platforms, so wrap them.
- **Load and CPU.** On macOS, use `sysctl -n vm.loadavg` (`{ 1m 5m 15m }`) and `sysctl -n hw.ncpu`. On Linux, use
  `/proc/loadavg` and `getconf _NPROCESSORS_ONLN`. Anything unreadable means no short lane (D13). The test-only
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

## 13. Acceptance

1. **Tests for every lane rule** (toolkit_test.sh unless named; stubs only):
   - **classify.** A table through `studio-gate --classify --`. It covers every whitelisted form and its near
     misses:
     - 3 files vs 4;
     - vitest with no cap, with `--maxWorkers=3`, with a directory or a glob;
     - tsc with `-b`;
     - `npm test`, `sh -c`, `env X=1 …`, `merge.sh`, `run-tests.sh`, `studio-dispatch run`, an unknown command.

     A whole suite is shareable with the lane on and exclusive with it off.
   - **beside shareable.** While a stub whole suite holds the main lane, a short file run in another worktree
     completes. Recorded intervals overlap. Its row has lane `short` and a wait under 3 s.
   - **never beside exclusive.** While `x -- sleep` holds the main lane, a short check waits until release.
     Its intervals do not overlap and its lane is `main:beside exclusive`.
   - **drain and no starvation.** With a short check in the slot, an exclusive caller waits. A second short check
     that arrives after the exclusive caller registered is not admitted. The exclusive caller runs before it, and
     never overlaps the slot.
   - **three-way no-overlap.** Exclusive, shareable and short callers under contention: no exclusive interval ever
     overlaps any other interval. This extends `test_gate_three_reclaimers_never_overlap`.
   - **same worktree.** A short check from the suite's own worktree goes to the main lane (`same worktree`).
   - **isolation.** Without `override.cfg`, a GUT short check goes to the main lane (`iso`), while vitest in the
     same state takes the slot.
   - **load.** `STUDIO_GATE_LOADAVG=99` refuses the slot, `0` admits, and an unreadable value refuses.
   - **lane off.** With no key, a short check waits behind a whole suite exactly as today: the same rows apart
     from the new fields.
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
     - `"tests": "gut"` and `engine` are still read.
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
   - Editor-bake probe: in a worktree with our `override.cfg`, a `--headless --script` that calls
     `ProjectSettings.save()` leaves `project.godot` without `use_custom_user_dir`. If it bakes, stop and redesign
     before rollout. `--check` already refuses a project.godot that sets it.

4. **No new flaky reds (live, phoenix quiet, `.git/heavy-suite.lock` held).**
   - Setup: a phoenix linked worktree with the three keys set locally and uncommitted. This is an acceptance
     worktree, not a run's. The whole-suite `studio-test` runs at fixed fps 3× solo, then 3× with a loop of
     short-lane checks beside it in a second worktree: a GUT file run (≤ 3 files, including
     `test_settings_cfg_isolation.gd` and `test_placeholder_icon.gd`, the `user://`-sensitive ones) and a targeted
     vitest with `--maxWorkers=2`.
   - Pass: the union of reds across the 3 solo runs equals the union across the 3 runs with the lane in use, and
     every with-lane row shows lane `short`.
   - If the 3 solo runs disagree among themselves, the comparison is void. The differing test is reported as a
     phoenix flake (as `test_nav_region_baker` was in 2026-10-02-studio-test-speed-findings.md) and is re-run.

5. **The full gate with isolation.** `studio-setup gate` (run-tests.sh) in an opted-in phoenix linked worktree, solo,
   has the same red set as in a non-opted-in one. That proves the CI-like fresh `user://` breaks nothing.

6. **No suites during a final gate.** Over the first live runs, no `gate.times` row of lane `short` overlaps a
   row of class `exclusive` in time. The script checks this.

7. **Before/after wait per verb.** `python3 -I tests/probes/gate_wait_measure.py --since <install day> --validate`.
   - It is extended to accept 4- or 8-field rows, prefer field 5 over inference, attribute blockers per lane (a slot
     holder never blocks the main lane), and print per-lane counts of short-eligible calls by reason.
   - Before: the §1 baseline (14 days to 10-19). After: the first live runs after install, plus benchmark 2.
   - Pass:
     - minutes that short calls spend behind whole-suite holds, per 100 short calls, fall by ≥ 80% (before:
       3077 min / 3187 short calls ≈ 97 per 100);
     - in lane-on worktrees, at least one short-eligible call ran in the slot (A3), and no single refusal reason
       accounts for most short-eligible calls without an explanation in the PR;
     - the waits behind final gates are reported separately and are expected to be unchanged (A2).

## 14. Rollout

1. Build and review in this worktree. The full repo gate `sh tests/run_all.sh` runs under `.git/heavy-suite.lock`.
   Then a PR.
2. **Install only by merging the PR.** The memory rule: never reinstall or pull into the main checkout while a
   phoenix run is live. Install when phoenix is quiet, so that no old-version gate process is alive (old gates know
   nothing of the slot; D11 covers only the reverse direction).
3. **Phoenix needs a config commit. This is a dependency for the user to approve.** What was found:
   - `.studio/config.json` is **tracked on phoenix's run branches**: `run/combat-vfx-library`'s index lists it,
     phoenix's `info/exclude` has `!.studio/config.json`, and studio-overnight refuses an uncommitted one.
   - It is **absent from the phoenix main checkout**: not in the working tree, and not in the `main` index.
   - Whether `origin/main` carries it was not verified; git commands against phoenix were blocked from this
     session.
   - So the three keys (`"test_engine_args": "--fixed-fps 60"`, `"user_dir": "per-worktree"`,
     `"gate_short_lane": "on"`) need a phoenix commit wherever new runs take their config from. That is the run
     branch the autopilot creates (it merges `max_lanes` into that file today), or phoenix `main` if the file
     lives there. Live run branches pick the keys up only when they are committed there.
   - Until the commit, phoenix behaves exactly as today, even after install (A5).
4. Run acceptance steps 3–5 when phoenix is quiet. Commit the phoenix config. Then measure (step 7) after the first
   live runs.
5. **Rollback.** Remove the keys in phoenix. That gives today's behaviour, with the new `gate.times` columns kept
   (harmless).

## 15. Risks

| Risk | Mitigation |
|---|---|
| Load-sensitive GUT tests (`Time.get_ticks_msec`) still flake beside a short check, even at fixed fps. | The load threshold, the worker cap, ≤ 3 files and the 5-min kill. Acceptance 4 is the gate, and if it fails the lane stays off in phoenix. |
| The fresh per-worktree `user://` turns a test red that relied on the developer's `user://` files. | Acceptance 5. Phoenix's sandboxes and its CI already run on a fresh `user://`. |
| The editor bakes `use_custom_user_dir` into `project.godot` (unverified). | Probe in acceptance 3. `--check` refuses it, and a baked line shows in `git status`. |
| D5's priority reorders exclusive callers ahead of waiting suites. | A bounded change. It is visible in the after-measurement, and the builder may scope it to lane-on (§7). |
| A demoted re-run wastes up to 5 min. | It is logged (`main:demoted`). If the measurement shows many demotions, tighten the whitelist. |
| The `gate.times` rewrite under the mutex adds a little mutex hold time. | Bounded at about 20 ms. A 5 s fallback means the gate never blocks its release. |
| Two short checks with identical stamps in one worktree. | Forbidden by D3. |
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

## 17. Left to the builder

- Inline vs a sourced `bin/gate-class.sh`, and confirming that install ships it.
- Comparing `studio-dispatch` identity portably.
- The vitest `--minWorkers` probe (§6), and whether eslint stays in the whitelist.
- Whether D5 applies only when the lane is on (the author leans yes).
- The demote file's exact path and contents.
- Whether to print one `gate: got the <lane> lane after <n> min` line when wait ≥ 60 s.
- The fixed-fps probe in acceptance 3.
- Linux verification of `override.cfg` (until then `--check` refuses on non-Darwin).
- The exact rotation awk.
- The 1-h sweep guard.
- The test-only seams `STUDIO_GATE_LOADAVG`, `STUDIO_GATE_SHORT_SECONDS` and `STUDIO_GODOT_USER_ROOT`, each named in
  its script header with a production-default carrier test.
- Splitting the work into tasks. Per-task review is mandatory for the gate state model (new seam), isolate.sh
  (data/cross-system) and the classifier. The skill text and README fold into the final review.

## 18. Falsify

A spec falsifier and the planner should try to break these claims before the plan is approved:

1. No interleaving of polls, releases, crashes (SIGKILL at any line) or pid reuse lets an exclusive holder overlap
   any other holder, or wedges the slot for longer than the cap + 15 s while its gate is dead.
2. Every exclusive caller eventually runs while short checks keep arriving (D5 plus the wantx block).
3. The whitelist admits nothing that can saturate the CPU or start `vite preview`, cucumber, Godot `--import`, a
   build, or a second Godot in one worktree.
4. With no keys set, every argv, row prefix, stderr line and exit status is today's (A5). The single deliberate
   exception is the appended `gate.times` fields.
5. `test_engine_args` cannot inject an option that changes what GUT runs, or where it runs.
6. Nothing writes `override.cfg` in a main checkout, over a foreign or tracked file, or deletes a live worktree's
   user dir.
7. A short-cap kill or a demotion never surfaces as exit 124 unless `STUDIO_GATE_MINUTES` ≤ 5.
8. `.studio/config.json` tracking in phoenix is as stated in §14.3. Recheck against `origin/main`.

## 19. Open questions for the user

1. **The phoenix config commit (§14.3).** Do you approve committing the three keys? Where should they go: phoenix
   `main`, or the run branches at autopilot setup?
2. **Opt-in.** The author made the lane and the `user://` isolation opt-in per project (D1, D2), with no change
   anywhere until phoenix sets them. Is that what you want, or should they be on by default?
3. **Exclusive priority (D5).** While an exclusive caller (a final gate, merge or setup) waits, it goes ahead of
   waiting suites and short checks. Is that acceptable?
