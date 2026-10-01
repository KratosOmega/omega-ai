# Overnight runner — Spec

Date: 2026-10-01
Status: Approved 2026-10-01
Milestone: Plan 3 — Content (studio tooling; bundle 2 of 3 of the token/autopilot redesign)
Classification: architectural

Issue: #17 — bundle 2 of 3. Bundle 1 (#9, `2026-10-01-slim-pipeline-design.md`)
cut the chain to `idle → brainstorm → plan → execute → idle` and deferred
three things here: automatic fresh sessions, replacing autopilot's heartbeat,
and splitting execute into fresh sessions per unit. Bundle 3 is the plan
shape and the plan falsifier.

## Milestone gate

The studio's working milestone (PROGRESS.md: Plan 1 and Plan 2 delivered,
Plan 3 planned) has no exit criterion for runner work; this bundle's own exit
criteria, agreed in brainstorm:

1. `sh tests/run_all.sh` is green, including the stub-`claude` runner suite.
2. One live run of `studio-overnight start` on a two-task plan in a throwaway
   Godot project reaches a draft PR with no human input, each unit in its own
   session, and writes the morning report.
3. No in-session scheduler remains: autopilot creates no `CronCreate` job and
   `omega-caffeine` is gone.

## Purpose

An approved plan turns into a draft PR overnight without anyone at the
keyboard, and without one session dragging every earlier task's context
behind it. Today execute runs every task in one main session (469k average
context, 800k max on phoenix), and autopilot's half-hourly heartbeat lives
inside that session — a `/clear`, a crash or a closed terminal ends the run.
The runner is an outside supervisor: it starts a fresh `claude-gd -p` session
for each unit of work, reads durable state between units, and stops on its
own rules. It serves the redesign's goal (same quality, a fraction of the
spend, fewer stops) by making the main-session cost per unit roughly
constant instead of growing with the plan.

## Core-loop delta

The user's loop (the studio's "ten-second loop" is the feature loop here):
today `approve plan → /clear → arm autopilot → /game-dev:execute → (session
runs all tasks, heartbeat nudges) → morning`. After: `approve plan → /clear →
/omega:autopilot (question sweep, readiness) → run the printed
studio-overnight command → morning: read report.md, play the list, merge`.
Attended runs are unchanged: `/game-dev:execute` without `--one` still runs
the whole stage in one session.

## Player verbs

- Added: `studio-overnight start [--dry-run]`, `studio-overnight status`,
  `studio-overnight stop`; `/game-dev:execute --one`.
- Changed: `/omega:autopilot` phase 1 ends by printing the runner command
  instead of arming a heartbeat; phase 2 reaches headless sessions through
  `OMEGA_AUTOPILOT=1`.
- Removed: autopilot's `CronCreate` heartbeat; `omega-caffeine`.

## Design

n/a — studio tooling, no game loop. `game-dev:game-designer` not dispatched.

## Level

n/a

## Failure and recovery

- **A unit makes no progress** (the progress signature — `stage`, `task`,
  the feature ledger's `final review done` and `shipped` lines — is unchanged
  after the session): one retry of the same unit; a second no-progress
  session stops the run with `stop: no progress on <unit>`.
- **A hard stop** (execute's own: destructive or security-sensitive
  operation, plan too broken to follow, no Godot binary, test framework
  missing): execute under `--one` writes `studio-state ledger "Stop: <reason>"`
  and exits; the runner sees the new `Stop:` line and stops at once, no retry.
- **Budget**: a session that hits `--max-budget-usd` ends; it counts as a
  no-progress session unless the signature moved. Before each launch, when
  spent + `session_usd` > `run_usd`, the runner stops with `stop: run budget`.
- **Timeout**: a session over `session_minutes` is sent SIGTERM, then SIGKILL
  after 30 s; it counts as no progress unless the signature moved.
- **Crash or closed terminal**: the lock's pid is dead; the next
  `studio-overnight start` reclaims the stale lock and resumes from state —
  each unit is idempotent because execute's §0 resume reads `task`, the
  ledger and the branch.
- **Cost to the user**: at most one unit's work is lost (each task commits and
  pushes before its session ends). The morning report names the stop reason
  and the resume command.

## Teaching

The user learns the runner from autopilot's phase 1: its last step prints the
exact command, what the run may and may not do, and the `status` / `stop`
commands. `studio-overnight --help` lists the same. The router
(`/game-dev:studio`) names `studio-overnight status` when a lock is live.

## Input and platform

macOS (Darwin) first, POSIX `sh`; `caffeinate` when present, otherwise a
warning and the run continues (Linux: `systemd-inhibit` when present).
Claude Code ≥ 2.1.287 headless flags: `-p`, `--output-format stream-json`,
`--verbose` (required by stream-json under `-p`),
`--permission-mode auto`, `--permission-prompts none`, `--disallowedTools`,
`--max-budget-usd`.

## Feel targets

| Target | Value | How it is checked |
|--------|-------|-------------------|
| Main-session context at unit start | ≈ fresh-session baseline (≤ 90k), every unit | live run (stream-json usage of each session) |
| Main-session context at unit end, task unit | ≤ 250k | live run |
| Runner overhead between units | ≤ 5 s | unit (stub) |
| Retries per unit before stop | 1 | unit (stub) |
| Stop after `studio-overnight stop` | after the running unit, ≤ 1 unit late | unit (stub) |
| Morning report written on every ending | 100% (done, stop, budget, no progress, crash-resume) | unit (stub) |

## References

- CI runners / Kubernetes Jobs: the supervisor schedules, workers are
  stateless and idempotent over durable state.
- launchd / systemd: one scheduler, a pidfile lock, the sleep inhibitor held
  for the supervisor's lifetime (`caffeinate -i -w <pid>`, `systemd-inhibit`).
- Bundle 1's spec: execute's §0 resume and §7 finish are the units' contracts.

## Acceptance criteria

1. `studio-overnight start` refuses to start (exit 2, one line each) unless:
   the plan is approved and committed (ledger `plan approved <plan>`, clean
   `git status` on spec and plan); the plan has a `## Decisions` section;
   `stage` is `plan` or `execute`; `claude-gd` and `gh auth status` succeed;
   no live lock.
2. It runs `claude-gd -p "/game-dev:execute --one"` once per unit with
   `OMEGA_AUTOPILOT=1`, `--output-format stream-json --verbose`,
   `--permission-mode auto --permission-prompts none`,
   the deny list and `--max-budget-usd <session_usd>`, with stdout to
   `.studio/reports/overnight-<ts>/<n>-<unit>.jsonl`.
3. Under `--one`, execute runs exactly one unit — the next task, or the final
   review with its fix wave, or the finish — writes its state, commits and
   pushes, and exits; it never starts a second unit.
4. The run ends with `done` when `stage` is `idle` and the feature ledger has
   a `shipped` line.
5. A unit with an unchanged progress signature is retried once; a second
   unchanged session stops the run (`no progress`).
6. A new `Stop:` ledger line stops the run with no retry.
7. The run stops before a launch that could exceed `run_usd`; the spend is the
   sum of each session's `total_cost_usd`.
8. A session past `session_minutes` is terminated and counted.
9. `.studio/overnight.lock` holds the runner's pid; a second `start` with a
   live pid exits 2; a dead pid is reclaimed with a warning.
10. `studio-overnight stop` makes the runner exit after the running unit;
    SIGINT/SIGTERM to the runner do the same.
11. `studio-overnight status` prints run dir, unit, `task k/N`, spend so far,
    and the lock pid — or `no run` (exit 1).
12. On every ending the runner writes `report.md`: stop reason, each unit
    (name, exit, cost, minutes), every `Ruling:` line with its cost if wrong,
    the play list (`P<k> Play:` lines), the PR URL from the `shipped` line,
    and the resume command when not done.
13. The runner holds `caffeinate -i -w <runner pid>` for its lifetime when
    `caffeinate` exists.
14. `omega-mode show` prints `autopilot` when `OMEGA_AUTOPILOT=1` is set and
    no session file lists it; the hooks' mode brief includes it.
15. Autopilot phase 1 (in a studio) creates no `CronCreate` job, does not
    call `omega-caffeine`, replaces its "in a worktree" readiness line with
    `studio-overnight start --dry-run` exiting 0, and ends by printing the
    `studio-overnight start` command; `omega-caffeine` and its tests are
    deleted; no shipped path (`shared/`, `studios/`, `tests/` except the
    absence checks themselves, `README.md`, `install.sh`) mentions
    `omega-caffeine` or `CronCreate`. Dated specs, plans, pressure records
    and PROGRESS are history and keep their text.
16. The deny list blocks force-push, remote branch delete, `gh pr merge`, and
    reads of secret paths; it is data in one file, not inlined in code.

## Architecture

(from `game-dev:architect`.) Studio tooling, so the usual terms translate:
the scene tree becomes files and owners, the gameplay state machine becomes
the runner's loop, signals become the runner ↔ session contract (environment,
ledger lines, exit codes), and the `Resource` becomes `config.json`'s
`overnight` object.

**Ownership.** The runner owns the lock, the stop file, the run directory,
scheduling and `report.md`. Execute owns every piece of studio state
(`STATE.md`, the ledger, the branch, commits, the PR). The runner only reads
studio state and never writes it; the session never reads runner files.

### Before / after

```
before: claude-gd (one session, attended terminal)
          /omega:autopilot ph.1 → omega-mode set · omega-caffeine start · CronCreate
          /game-dev:execute → SDD T1..TN → §5 → §7 → omega:handoff → disarm

after:  terminal: studio-overnight start          (cwd = START_DIR; holds lock + caffeinate)
          unit 1   claude-gd -p "/game-dev:execute --one"   OMEGA_AUTOPILOT=1 → T1
          unit k   …same command…                                            → T<k>
          unit N+1 …same command…                                            → §5 + fix wave
          unit N+2 …same command…                                            → §7 finish
          report.md written from the ledger; unlock
```

### Files

| File | Action | Single responsibility |
|------|--------|-----------------------|
| `studios/game-dev/bin/studio-overnight` | create | Supervisor: `start [--dry-run]`, `status`, `stop`, `--help`. POSIX `sh`, `set -u`, house style of `studio-dispatch`. Calls its sibling `studio-state` by path (own directory resolved through symlinks, the `studio-dispatch` loop), never via `PATH` |
| `studios/game-dev/bin/overnight-deny.txt` | create | The deny list (AC16). Sibling of the runner so link and copy installs both carry it. One Claude Code permission rule per line; blank lines and `#` comments ignored. Seed: `Bash(git push --force:*)`, `Bash(git push -f:*)`, `Bash(git push --force-with-lease:*)`, `Bash(git push origin --delete:*)`, `Bash(git push --delete:*)`, `Bash(gh pr merge:*)`, `Bash(gh api -X DELETE:*)`, `Read(**/.env*)`, `Read(**/*.pem)`, `Read(**/*.key)`, `Read(~/.ssh/**)`, `Read(~/.aws/**)`, `Read(~/.config/gh/**)`. Missing or empty file: preflight refuses |
| `tests/overnight_test.sh` | create | Runner suite (picked up by `run_all.sh`'s `*_test.sh` glob; `sh` + `tests/assert.sh` like `state_test.sh`). Fake bin first on `PATH`: a stub `claude` driven by a scenario file, a two-line `claude-gd` that `exec claude "$@"`, and a stub `gh` |
| `studios/game-dev/skills/execute/SKILL.md` | modify | New `## 8. One unit (--one)`, plus one-line pointers in §0 (every stop), §1, §5 step 6 and §7 steps 6–7 |
| `shared/omega/bin/omega-mode` | modify | `OMEGA_AUTOPILOT=1` in `show` and `brief` |
| `shared/omega/hooks/session-start.sh` | modify | Drop `CAFFEINE` and the `Keep-awake:` clause from the context line |
| `shared/omega/hooks/session-end.sh` | modify | Drop the `omega-caffeine stop` call and its header mention |
| `shared/omega/hooks/prompt-submit.sh` | modify | `/omega:autopilot off` only clears the mode; drop `CAFFEINE` |
| `shared/omega/bin/omega-caffeine` | delete | — |
| `shared/omega/skills/autopilot/SKILL.md` | modify | Rewrite of `off`, phase 1 steps 3/5/6, phase 2 hard stops / completion / disarm, red flags |
| `shared/omega/skills/delegate/SKILL.md` | modify | Drop `omega-caffeine` from its list of status commands |
| `studios/game-dev/skills/studio/SKILL.md` | modify | When `.studio/overnight.lock` names a live pid, the router says `studio-overnight status` and routes nothing else |
| `README.md` | modify | Autopilot row (l.127) describes the runner hand-off; drop the `omega-caffeine` tree line (l.250); add `studio-overnight` to the studio bin tree |
| `docs/omega/pressure/autopilot.md` | modify | Pressure scenario expects the printed runner command, not a heartbeat |
| `tests/omega_test.sh` | modify | Remove the `omega-caffeine` cases, fake `caffeinate` and the `Keep-awake` assertion; add `OMEGA_AUTOPILOT` show/brief cases; add the absence check (below) |
| `tests/omega_contracts/autopilot_contract.sh` | modify | Drop the caffeine/heartbeat assertions; assert `studio-overnight start`, `source=env`, `Stop:`, and absence of `CronCreate`/`omega-caffeine` |
| `tests/install_test.sh` | modify | The copy-mode tool loop (l.145) checks `omega-mode` only |
| `tests/studio_test.sh` | modify | Text contract for execute's `--one` section |

The absence check (AC15) greps `shared/`, `studios/`, `tests/` (except the
check's own file and the contract that asserts absence), `README.md` and
`install.sh` for `omega-caffeine` and `CronCreate`. Dated specs,
`docs/*/PROGRESS.md` and this spec are history and stay as written.

### Paths the runner uses

- `STATE_ROOT` = `studio-state root` (main checkout). Holds
  `.studio/overnight.lock`, `.studio/overnight.stop` and
  `.studio/reports/overnight-<YYYYmmdd-HHMMSS>/`. On first use the runner
  writes `.studio/reports/.gitignore` (`*`) and appends
  `.studio/overnight.lock` and `.studio/overnight.stop` to
  `$(git rev-parse --git-common-dir)/info/exclude` — never to a tracked
  `.gitignore`, which would dirty the tree.
- `START_DIR` = `studio-state root --work` where `start` was run: the
  checkout holding the approved spec and plan (normally the main checkout).
  Every session is launched with cwd `START_DIR`; execute's §0 resume moves
  each session into the feature worktree itself (`EnterWorktree`).
- `FEATURE_DIR` = stdout of `studio-state worktree` run in `START_DIR` when
  it exits 0; otherwise (no branch yet, exit 1 or 3) `START_DIR`. Recomputed
  at every snapshot.
- Ledger text = the lines after `## Feature ledger: ` in `studio-state show`
  run with cwd `FEATURE_DIR` (and, for `Stop:` lines only, also with cwd
  `START_DIR`). The runner never derives the ledger file name; `studio-state`
  keeps the one slug rule.
- Config = `START_DIR/.studio/config.json`.
- Run directory: `<n>-<label>.jsonl` (stdout), `<n>-<label>.err` (stderr),
  `units.tsv` (`n label exit cost minutes timed_out outcome`), `current`
  (label of the running unit), `report.md`.

### Progress signature

Taken immediately before each launch and after each session ends:

```
SIG   = stage=<studio-state get stage>;task=<studio-state get task>;
        frd=<count of "^- [0-9-]* final review done$" in FEATURE_DIR ledger>;
        shipped=<count of "^- [0-9-]* shipped " in FEATURE_DIR ledger>
STOPS = sort -u of every "^- [0-9-]* Stop: " line in the FEATURE_DIR and
        START_DIR ledgers
```

`stage`/`task` come from `STATE.md` in the main checkout (`studio-state get`
works from any cwd). `STOPS` is a de-duplicated set, not a count, so a
committed `Stop:` line that a new worktree copies from `START_DIR` is not
new. A new stop = `comm -13 STOPS_before STOPS_after` is non-empty; its last
line's text after `Stop: ` is the reason.

**Unit label** (file names and the report only; never passed to the
session, and never a decision about which unit runs): from `SIG_before`,
`stage plan` → `T1`; `task k/N`, k < N → `T<k+1>`; `N/N`, `frd=0` →
`final-review`; `N/N`, `frd>0` → `finish`. A retry appends `-retry`.

### Runner state machine

```
PREFLIGHT ─fail→ exit 2 (one line per failure; no lock, no report)
   │ ok (--dry-run: print the launch line, exit 0)
LOCK ─live pid→ exit 2
   │ stale pid → warn "reclaiming stale lock (pid N)", remove, retake
   │ took it → run dir, rm stop file, start inhibitor
   ▼
CHECK ◄──────────────────────────────────────────────┐
   │ stop file or signal flag        → REPORT "stopped by user"
   │ stage ∉ {plan, execute}         → REPORT "stop: unexpected stage <s>"
   │ spent + session_usd > run_usd   → REPORT "stop: run budget"
   │ else snapshot SIG_before, STOPS_before
LAUNCH (claude-gd in background + watchdog)          │
WAIT ─child exits──────────────┐                     │
   │ watchdog: TERM, grace, KILL┤ timed_out=1         │
   │ INT/TERM to runner: set flag, keep waiting       │
CLASSIFY (in this order; append units.tsv row first) │
   │ new STOPS line                  → REPORT "stop: <reason>"
   │ stage idle ∧ shipped > 0        → REPORT "done"
   │ SIG changed                     → noprog=0 ─────┤
   │ noprog+1 ≤ retries              → (retry) ──────┘
   │ else                            → REPORT "no progress on <label>"
REPORT → write report.md → UNLOCK (kill inhibitor, rm lock, rm stop file)
```

- **Preflight** (AC1), each failure one line, exit 2: `studio-state show`
  has `plan approved <plan>`; `git status --porcelain -- <spec> <plan>
  .studio/ledger .studio/config.json` is empty in `START_DIR` (the same four
  paths execute's §0 checks, so a unit cannot stop on them at once); the
  plan has a `^## Decisions` line; `stage` is `plan` or `execute`;
  `command -v claude-gd` and `claude-gd --version` succeed; `gh auth status`
  succeeds; the deny file is present and non-empty; each `overnight` value
  parses and is in range; no live lock.
- **Lock** (AC9): created with `set -C` (noclobber) so two starts cannot
  both win; lines `pid=<$$>`, `run=<abs run dir>`, `started=<ISO time>`.
  Live = `kill -0 <pid>` and `ps -o args= -p <pid>` contains
  `studio-overnight`.
- **Inhibitor** (AC13): Darwin with `caffeinate` → `caffeinate -i -w $$ &`;
  Linux with `systemd-inhibit` → `systemd-inhibit --what=idle:sleep
  --why=studio-overnight sh -c 'while kill -0 <runner pid>; do sleep 60; done' &`;
  otherwise one warning line and continue.
- **Signals** (AC10): `trap 'STOP_REQ=1' INT TERM`. The session is an
  asynchronous list in a non-interactive shell, so POSIX starts it with
  SIGINT ignored and a Ctrl-C reaches only the runner. `trap … EXIT` writes
  `report.md` with `stop: runner error (exit <n>)` and unlocks when REPORT
  was not reached. SIGHUP is not trapped: a closed terminal is the
  crash path, recovered by the stale-lock rule.
- **Exit codes**: `start` 0 done · 1 any other ending · 2 refused. `status`
  0 run live · 1 `no run`. `stop` 0 stop file written · 1 `no run`.
- **`status`** (AC11) reads the lock (pid, run dir), `current`, `units.tsv`
  (spend = sum of the cost column) and `studio-state get task`.
- **`stop`** touches `STATE_ROOT/.studio/overnight.stop` when the lock is
  live; the runner checks it in CHECK, so the running unit always finishes.

### Launch line and portable timeout

```
cd "$START_DIR" && OMEGA_AUTOPILOT=1 claude-gd -p "/game-dev:execute --one" \
  --output-format stream-json --verbose \
  --permission-mode auto --permission-prompts none \
  --max-budget-usd <session_usd> \
  --disallowedTools <rule 1> <rule 2> … \
  > <n>-<label>.jsonl 2> <n>-<label>.err &
```

The prompt is the first argument and `--disallowedTools` the last option,
because the flag is variadic and would swallow a later positional. Each
deny rule is its own argv element, built with `set --` while reading the
file, so rules with spaces survive. `--verbose` is required by
`stream-json` under `-p`. The probe task's fallback prompt (Risks) replaces
only the prompt string.

macOS has no GNU `timeout`. The watchdog is a background subshell
`( sleep <secs>; : > timed_out; kill -TERM <cpid>; pkill -TERM -P <cpid>;
sleep <grace>; kill -KILL <cpid>; pkill -KILL -P <cpid> ) >/dev/null 2>&1 &`,
then `while kill -0 <cpid>; do wait <cpid>; done` (a trapped signal
interrupts `wait`; the loop re-waits). When the session ends first, the
runner kills the watchdog. `<secs>` = `session_minutes × 60`, overridden
only by `STUDIO_OVERNIGHT_SESSION_SECONDS` (test hook, documented in
`--help`). No polling, so runner overhead between units is the snapshot
cost only.

### Cost from stream-json

The last `"type":"result"` line of the session's `.jsonl` carries
`total_cost_usd`:
`grep '"type"[[:space:]]*:[[:space:]]*"result"' f | tail -n 1 | sed -n
's/.*"total_cost_usd"[[:space:]]*:[[:space:]]*\([0-9.eE+-]*\).*/\1/p'`.
Missing (no result event: killed, crashed, or subscription auth with no
cost) → `0`, and the unit's cost column reads `unknown`; the report then
says "cost unknown" next to the total. Sums and the budget comparison use
`awk` (floating point; `sh` arithmetic is integer only).

### `overnight` config (the tunables' schema)

`START_DIR/.studio/config.json`, read with the same flat `sed` scan
`studio-dispatch` uses — no `jq`, no new dependency. A number field is
`sed -n 's/.*"<key>"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' | head -n 1`;
the five key names are unique in the file, so nesting needs no parser.
Absent → default; present but outside its range or not a number →
preflight refusal naming the key (never a silent clamp).

```json
{ "overnight": { "session_usd": 25, "run_usd": 150, "session_minutes": 90,
                 "retries": 1, "kill_grace_seconds": 30 } }
```

Ranges are the Tuning knobs table. `session_minutes`, `retries` and
`kill_grace_seconds` must be integers; the two USD fields may be decimals.

### Execute `--one` contract (new §8)

- **Which unit:** exactly what §0's *Where to start* picks. `task k/N`,
  k < N → one SDD task, `T<k+1>`; `N/N` without `final review done` → §5
  whole, the fix wave included, through step 6; `N/N` with it → §7 steps
  1–6. Never more than one.
- **Cutting SDD's loop:** SDD is invoked as usual, but once the task is
  complete (§4a rule 6) and §6's writes are done — `set task n/N`, the
  `T<n> complete` line, the ledger committed — no next implementer is
  dispatched, and when n = N §5 is not started. This overrides SDD's
  instruction to continue to the next task.
- **What each unit writes:** task — the task's commits, `task n/N`, the
  `T<n>` ledger lines, then `git push -u origin <branch>`; final review —
  `fix(final)` commits, the `Review: final` and `final review done` lines
  committed, then push; finish — §7 as written (`P<k> Play:` lines, the
  PR, `shipped <url>`, `stage idle`, `task -`). A rejected push is a
  `Ruling:` line, not a stop.
- **`Stop: <reason>`:** wherever execute says "stop" — §0's preconditions
  and isolation stops, §6's hard-stop list, §7 step 1's exit 2 and exit 3 —
  under `--one` it runs `studio-state ledger "Stop: <reason>"`, then
  `git add .studio/ledger && git commit -m "chore(studio): stop"` in the
  checkout it is in (so the re-run's clean-tree check passes), then ends
  the turn. One line, reason first; the runner prints it verbatim.
- **§7 step 6 headless:** `ExitWorktree` `action: "keep"` runs as written
  (it restores the session directory; the process then exits). The
  "started in the feature worktree" note and the `Next:` line are skipped:
  there is no `/clear` and no human reading this session.
- **No handoff:** `--one` never runs `omega:handoff`; the runner's
  `report.md` is the morning report.
- `--one` with `--inline` is refused with a `Stop:` line (subagent-driven
  only).

### `OMEGA_AUTOPILOT` in omega-mode and the hooks

- `omega-mode show`: the file's lines, then `autopilot source=env` when
  `OMEGA_AUTOPILOT=1` and no file line starts with `autopilot`. With
  `OMEGA_AUTOPILOT=1`, `show` and `brief` no longer die on a missing session
  id; they print the env line alone. `set`, `clear` and `path` are
  unchanged (`clear autopilot` cannot clear the environment, by design).
- `omega-mode brief`: an `autopilot` line with `source=env` gets its own
  rule text: `autopilot (overnight runner): never AskUserQuestion — rule by
  the standards, log the ruling with its cost if wrong, continue; commit,
  push and open a draft PR, never merge; on a hard stop write Stop:
  <reason> to the ledger and end; no handoff — the runner starts the next
  session.` A session-file `autopilot` line keeps today's text.
- Hooks need no code for the variable: each runs as a child of the
  `claude` process, inherits `OMEGA_AUTOPILOT`, and already injects
  `omega-mode brief`. Their only change is the `omega-caffeine` removal.
- §7 step 4's draft rule (`omega-mode show` lists `autopilot`) therefore
  holds under the runner with no edit to §7.

### Autopilot SKILL.md rewrite (summary)

- `off`: `omega-mode clear autopilot` (and `studio-overnight stop` when a
  lock is live), then stop. The phase 1 leftover disarm is the same clear.
- Phase 1 step 3, in a studio: commit only; the first task unit pushes the
  feature branch. Outside a studio: unchanged.
- Phase 1 step 5, in a studio: the "on the feature branch, in a worktree"
  line is replaced by `studio-overnight start --dry-run` exiting 0 (it runs
  the preflight); the baseline test and engine lines stay.
- Phase 1 step 6, in a studio: set no mode. Print the absolute
  `studio-overnight start` command and the checkout to run it from, what
  the run may do (commit, push the feature branch, open a draft PR) and may
  not do (merge, force-push, delete a remote branch, destructive or
  security-sensitive operations, secrets), `status`/`stop`, where
  `report.md` lands, and that this session can now close. Outside a studio:
  `omega-mode set autopilot` and the user starts the run in this session;
  no heartbeat, no keep-awake. The "resumed session repeats steps 2–3"
  paragraph is deleted.
- Phase 2: applies while `show` lists `autopilot` from either source. Hard
  stop under `source=env`: write the `Stop:` line and end — no handoff, no
  disarm. Completion under `source=env`: the invoking skill's unit ends
  the session; the runner reports. Session-mode completion and hard stop:
  `omega:handoff`, then disarm = `omega-mode clear autopilot`.
- Red flags: the two heartbeat rows go; one row added: "I'll start the
  next task while I'm here" → under `--one`, one unit, then end.

### Rejected alternatives

- Runner computes the next task from the plan: duplicates §0's resume and
  drifts from it (ruled Approach A).
- Runner parses the session's last line for a status: the model's prose is
  not a contract; durable state is.
- Ledger path derived in the runner: a second copy of `studio-state`'s slug
  rule; `studio-state show` in `FEATURE_DIR` is the one source.
- `jq` for config and cost: a new dependency for five numbers and one field
  the existing `sed` scan reads.
- `perl -e alarm` or a polling loop for the timeout: the first is a hidden
  dependency, the second adds up to a poll interval of overhead per unit.
- Deny list inline in the runner or in the studio `settings.json`: AC16
  wants data, and `settings.json` would also deny attended sessions.
- Session-mode autopilot set by the runner: a headless session has no mode
  file until it starts, and the env variable needs no cleanup.

## Tuning knobs

`.studio/config.json`, key `overnight` (absent keys take the defaults):

| Field | Unit | Default | Range |
|-------|------|---------|-------|
| `session_usd` | USD | 25 | 1–200 |
| `run_usd` | USD | 150 | 1–2000 |
| `session_minutes` | minutes | 90 | 10–480 |
| `retries` | sessions | 1 | 0–3 |
| `kill_grace_seconds` | seconds | 30 | 5–120 |

## Assets and audio

n/a

## Test strategy

- Unit (`tests/run_all.sh`, bash): a stub `claude` first on `PATH` that, per
  scripted scenario, edits a fixture `.studio/` the way a unit would (advance
  `task`, append ledger lines, emit a stream-json `result` event with
  `total_cost_usd`). Cases: unit sequencing to `done`; retry once then stop;
  `Stop:` line stops with no retry; run budget; session timeout; lock live /
  stale; stop file; SIGINT; report contents on each ending; preflight
  refusals; `omega-mode show` under `OMEGA_AUTOPILOT=1`; no `omega-caffeine`
  or `CronCreate` reference in a shipped path (AC15); execute's `--one` contract text.
- Playtest (live, manual exit criterion 2): a two-task plan in a throwaway
  Godot project; pass = draft PR, four sessions (T1, T2, final review,
  finish) each starting near baseline context, report.md complete; fail = any
  prompt waiting, a unit run twice with progress, or no report.
- Visual: the user reads report.md and judges whether it answers "what
  happened overnight" without opening the logs.

## Risks

| Risk | Cheapest early check |
|------|----------------------|
| A plugin slash command does not invoke the skill under `-p` | First plan task: a one-line live probe `claude-gd -p "/game-dev:studio"`; fallback prompt text "Invoke the game-dev:execute skill with args --one" |
| `--permission-mode auto` denies a tool the unit needs, and the unit silently fails | The no-progress rule catches it within two sessions; the session log names the denial; the live run lists denials |
| `EnterWorktree` behaves differently in `-p` | Live probe in the same first task; execute's `cd` fallback already exists |
| `total_cost_usd` absent under subscription auth | Stub test treats a missing cost as 0 and the report says "cost unknown"; the timeout still bounds the run |
| Fresh sessions re-pay ≈62k startup per unit | Accepted: a 6-task plan costs ≈8 × 62k, against one session growing to 469k average |

## Not doing

- Driving brainstorm or plan headlessly — their approvals need a human.
- Automatic `/clear` between attended stages — bundle 1's warning hook stays.
- A shared/omega runner with a studio adapter — one user today (YAGNI).
- Skipping a stuck task and continuing — later tasks depend on earlier ones.
- launchd/cron scheduling of the runner — the user starts it; resume is a
  re-run.
- The plan falsifier and the plan shape — bundle 3.
- Model selection per unit — unchanged from bundle 1.
