# Overnight Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Approved 2026-10-01

**Goal:** `studio-overnight start` turns an approved plan into a draft PR
with no one at the keyboard. It runs one fresh `claude-gd -p
"/game-dev:execute --one"` session per unit of work. Autopilot's in-session
heartbeat and `omega-caffeine` are retired.

**Architecture:** `studio-overnight` is an outside supervisor written in POSIX
`sh`. It owns the lock, the stop file, the run directory and `report.md`. It
reads studio state only through its sibling `studio-state` and never writes
it. Each session is a stateless worker over that durable state. Execute's new
`--one` section runs exactly one unit (a task, the final review, or the
finish), writes state, commits, pushes and ends. The contract between the
runner and the session is the environment (`OMEGA_AUTOPILOT=1`), argv, the
ledger lines, `stage`/`task`, and stream-json `total_cost_usd`. Nothing else
crosses that line.

**Tech Stack:** POSIX sh, bash-as-sh tests (`tests/assert.sh`), Markdown
skills, Claude Code 2.1.287 headless flags

**Spec:** `docs/game-dev/specs/2026-10-01-overnight-runner.md`

**Cut in the scope pass:** none

**Review policy (user CLAUDE.md):**
- Tasks marked **Risk: risky** each get a per-task review on Opus.
- Mechanical tasks fold into the final review.
- Minor findings are batched into the final fix wave.
- Every fix round goes to a fresh fixer.
- Re-review only after a Critical, three or more Importants, or a
  production-bug fix. Never a third pass.
- A standalone final whole-branch review on Opus, then `sh tests/run_all.sh`.

## Global Constraints

Copied from the spec (line numbers in parentheses), then the project rules.

**Feel targets (spec 108-115):**

| Target | Value | How it is checked |
|--------|-------|-------------------|
| Main-session context at unit start | ≈ fresh-session baseline (≤ 90k), every unit | live run (stream-json usage of each session) |
| Main-session context at unit end, task unit | ≤ 250k | live run |
| Runner overhead between units | ≤ 5 s | unit (stub) |
| Retries per unit before stop | 1 | unit (stub) |
| Stop after `studio-overnight stop` | after the running unit, ≤ 1 unit late | unit (stub) |
| Morning report written on every ending | 100% (done, stop, budget, no progress, crash-resume) | unit (stub) |

**Acceptance criteria (spec 127-171), verbatim:**

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

**Spec rules quoted for every task:**

- (spec 181-184) "The runner only reads studio state and never writes it; the session never reads runner files."
- (spec 205) The runner is "POSIX `sh`, `set -u`, house style of `studio-dispatch`. Calls its sibling `studio-state` by path (own directory resolved through symlinks, the `studio-dispatch` loop), never via `PATH`".
- (spec 247-248) "The runner never derives the ledger file name; `studio-state` keeps the one slug rule."
- (spec 374-379) Config is read "with the same flat `sed` scan `studio-dispatch` uses — no `jq`, no new dependency … present but outside its range or not a number → preflight refusal naming the key (never a silent clamp)."
- (spec 344-348) "The prompt is the first argument and `--disallowedTools` the last option … Each deny rule is its own argv element, built with `set --` while reading the file".

**Project rules (user CLAUDE.md; bundle-1 plan conventions):**

- Data stays explicit. Tunables live in `.studio/config.json` `overnight`,
  deny rules in `overnight-deny.txt`, and neither appears as a literal in code.
- Tests are written first for behaviour we keep.
- Every literal a test asserts with `assert_contains` sits on **one line** of
  its Markdown file, because `grep -q` matches line by line.
- (plan rule) A test line that names `omega-caffeine` or `CronCreate`
  spells it split (`'omega-''caffeine'`, `'Cron''Create'`). The absence
  check then needs no exclusions (Decision D11).
- (plan rule) Run every test file, and `sh tests/run_all.sh`, from the
  repository root. `run_all.sh` exits 0 at the end of every task.
- (plan rule) A timing assertion takes the shorter of two samples (studio
  memory: wall-clock timing tests, min of two).
- Every new test function is added to its file's `run_tests` line.

## Decisions

These answer the spec's Risks table (D1-D6, from a live probe run in this
planning session on Claude Code 2.1.287) and the architect's spec gaps
(D7-D16). They bind the implementers. Autopilot's question sweep adds below.

- **D1. The prompt is the slash command `/game-dev:execute --one`.** The
  probe's `claude-gd -p "/game-dev:studio"` expanded the plugin command:
  the result was the router's `Stage: … / Next: …` report. The fallback
  prompt from Risks is not needed.
- **D2. `EnterWorktree` and `ExitWorktree action: "keep"` work under `-p`.**
  The probe created `.claude/worktrees/probe-wt`, ran in it, and exited
  keeping it. One catch: the studio's worktree guard hook refuses compound
  shell commands that name git, so a headless session splits them, as an
  attended one already does. That costs one extra tool call and is not a stop.
- **D3. The deny rules are enforced one argv element each, spaces
  included.** In the probe, `Bash(git push --force:*)` denied
  `git push --force origin HEAD:main` ("Permission to use Bash with command
  … has been denied."), and `Read(**/.env*)` denied a `.env` read. The
  result event's `permission_denials` lists both, so the report can quote
  them later (not in this plan).
- **D4. `total_cost_usd` is present** in the result event under this
  account's auth ($0.26 and $0.34 per probe). The "cost unknown" path stays
  for killed sessions.
- **D5. A fresh unit starts at ≈ 39k context**: 29,002 cache-creation plus
  10,225 cache-read tokens on the first turn. That is under the 90k target.
- **D6. A terminal Ctrl-C aborts a backgrounded session, so the runner
  launches each session in its own process group.** In the probe, SIGINT to
  the process group ended `claude -p` with `"terminal_reason":
  "aborted_streaming"`, even though the session had been started as an async
  list. Node installs its own SIGINT handler, so the spec's l.320-322
  argument does not hold. Fix: `set -m` immediately before the launch and
  `set +m` after it. Under macOS `sh` (bash 3.2) this gave the child its own
  pgid with no tty, the runner's INT trap fired, and the wait loop recovered
  the child's status. dash enables job control only with a tty: in a real
  terminal it works, and without one the child shares the runner's group
  (one warning-free fallback, accepted). `set -m` and `set +m` take
  `2>/dev/null`.
- **D7. The wait loop (fixes spec l.351-355 and the architect's G1).** The
  probe showed that a second `wait` on an already reaped child returns 127
  in bash ("pid N is not a child of this shell"). The architect's "one more
  wait" fix is therefore wrong. The status comes from inside the loop:
  ```sh
  _st=0
  while :; do
    wait "$CPID"; _st=$?
    kill -0 "$CPID" 2>/dev/null || break   # exited: $_st is its status
  done                                     # alive: a trap interrupted wait
  ```
- **D8. Unit label for `stage execute` with `task` `-`, empty or `0/N` is
  `T1`** (G3).
- **D9. A `Stop:` before isolation is not committed onto the default branch**
  (G4, spec l.406-411). Under `--one`, the `chore(studio): stop` commit runs
  only when `git branch --show-current` is not the default branch. Otherwise
  the line stays uncommitted. The runner still sees it, because it reads
  `START_DIR`'s ledger file. The re-run's preflight then refuses on the dirty
  `.studio/ledger`, which is right: a hard stop needs a human. The refusal
  line says `uncommitted ledger change — read the Stop: line, resolve it,
  commit`.
- **D10. `docs/omega/pressure/autopilot.md`** (G5). Only its scenario and
  expected-behaviour text changes. Recorded run transcripts stay as written.
- **D11. The absence check scans every listed path with no file
  exclusions** (G12). Test lines spell the two names split (Global
  Constraints), so `omega_test.sh`'s other leftovers cannot hide.
- **D12. Runner overhead gets a test** (G6): `test_overnight_overhead`, in
  Task 2.
- **D13. No grace-time test hook** (G7). The one KILL-after-grace test sets
  `kill_grace_seconds: 5` and accepts ~6 s of wall time. The only test hook
  stays `STUDIO_OVERNIGHT_SESSION_SECONDS`.
- **D14. Losing the stale-lock retake race exits 2** with
  `studio-overnight: lock taken by another start` (G8).
- **D15. The router line gets a text contract** (G9), in Task 7.
- **D16. The runner prints absolute paths** (G10). `--help`, the resume
  command in `report.md`, and autopilot's printout name the runner by the
  absolute path it was invoked as (`$(cd "$(dirname "$0")" && pwd)/$(basename "$0")`),
  because the config-root `bin/` is on `PATH` only inside a `claude-gd`
  session.
- **D17. `test_bin_syntax` skips `*.txt`.** `studios/*/bin/*` will contain
  `overnight-deny.txt`, which is data: it is neither executable nor sh.
  Task 1 adds `*.txt) continue ;;` beside `.gitkeep` in
  `tests/studio_test.sh:112`.
- **D18. The EXIT trap is armed only after the lock is taken** (G13).
  Preflight refusals write no report.

## Review Focus

These are the input classes most likely to bite, most likely first. Each is
pinned by a test in the task that owns the code.

1. **A trapped signal during `wait`** must not lose the session's exit code
   or start a second unit. Tests: Task 3 `test_overnight_sigterm` and
   `test_overnight_sigint`.
2. **A `Stop:` line copied into a new worktree from a committed ledger** is
   not new. Test: Task 2 `test_overnight_copied_stop_not_new`.
3. **A deny rule with spaces** stays one argv element, after the prompt and
   at the end of the line. Test: Task 2 `test_overnight_launch_argv`.
4. **A config value that is present but malformed** (`"retries": "two"`,
   `"session_minutes": 1.5`) is refused with the key's name, never clamped
   or defaulted. Test: Task 1 `test_overnight_config_refusals`.

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `studios/game-dev/bin/studio-overnight` | 1-4 | Supervisor: `start [--dry-run]`, `status`, `stop`, `--help` |
| `studios/game-dev/bin/overnight-deny.txt` | 1 | The deny list (data) |
| `tests/overnight_test.sh` | 1-4 | Runner suite, with the stub `claude`, `claude-gd`, `gh` and `caffeinate` |
| `tests/studio_test.sh` | 1, 5, 7 | `*.txt` skip (D17); execute `--one` contract; router contract |
| `studios/game-dev/skills/execute/SKILL.md` | 5 | `## 8. One unit (--one)` and its pointers |
| `shared/omega/bin/omega-mode` | 6 | `OMEGA_AUTOPILOT=1` in `show` and `brief` |
| `tests/omega_test.sh` | 6, 8 | env mode cases; caffeine removal; absence check |
| `shared/omega/skills/autopilot/SKILL.md` | 7 | Rewrite: runner hand-off |
| `tests/omega_contracts/autopilot_contract.sh` | 7 | New contract |
| `docs/omega/pressure/autopilot.md` | 7 | Scenario expects the runner command |
| `studios/game-dev/skills/studio/SKILL.md` | 7 | Live-lock line |
| `README.md` | 7, 8 | Autopilot row (7); bin tree (8) |
| `shared/omega/bin/omega-caffeine` | 8 | Delete |
| `shared/omega/hooks/{session-start,session-end,prompt-submit}.sh` | 8 | Drop caffeine |
| `shared/omega/skills/delegate/SKILL.md` | 8 | Drop caffeine from its status commands |
| `tests/install_test.sh` | 8 | Copy-mode loop checks `omega-mode` only |

**Order:** Tasks 1→2→3→4 are serial, because they share one file. Tasks 5
and 6 touch disjoint files and may run beside 1-4. Task 7 needs 1 (for
`--dry-run`) and 6 (for `source=env`). Task 8 is last, because the absence
check is red until 7 has rewritten autopilot.

---

### Task 1: Runner skeleton — help, config, deny list, preflight, lock, dry run
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-overnight, studios/game-dev/bin/overnight-deny.txt, tests/overnight_test.sh, tests/studio_test.sh

**Risk: risky** (new seam; config schema). Covers AC1, AC9, AC16, and the
preflight list at spec 304-311.

**Interfaces — produces (later tasks rely on these exact names):**
- Variables: `SELF_ABS`, `SELF_DIR`, `STATE_BIN`, `DENY_FILE`, `PROMPT`,
  `START_DIR`, `STATE_ROOT`, `CONFIG`, `LOCK`, `STOP_FILE`, `REPORTS`,
  `SESSION_USD`, `RUN_USD`, `SESSION_MINUTES`, `RETRIES`, `GRACE`.
- `state CMD...`: runs `sh "$STATE_BIN" CMD...` with cwd `$START_DIR`.
- `with_launch_args FN`: calls `FN "$PROMPT" --output-format stream-json
  --verbose --permission-mode auto --permission-prompts none
  --max-budget-usd "$SESSION_USD" --disallowedTools <rule>...`.
- `lock_pid`, `lock_live` (0 when live), `take_lock RUN_DIR` (0 when taken).
- `print_launch "$@"`: the dry-run line.
- The test harness in `tests/overnight_test.sh`: `fixture NAME [CONFIG_JSON]`,
  `scenario LINE...`, `run_start [ARGS]` (sets `RS_STATUS`, `RS_OUT`,
  `RS_ERR`), `calls` (number of stub sessions), the `$CALLS` directory, and
  `last_run_dir`.

- [ ] **Step 1: Write the deny file** `studios/game-dev/bin/overnight-deny.txt`
  (not executable):

```text
# Deny rules for studio-overnight sessions (AC16). One Claude Code permission
# rule per line; blank lines and lines starting with # are ignored. Each rule
# becomes one --disallowedTools argument.
Bash(git push --force:*)
Bash(git push -f:*)
Bash(git push --force-with-lease:*)
Bash(git push origin --delete:*)
Bash(git push --delete:*)
Bash(gh pr merge:*)
Bash(gh api -X DELETE:*)
Read(**/.env*)
Read(**/*.pem)
Read(**/*.key)
Read(~/.ssh/**)
Read(~/.aws/**)
Read(~/.config/gh/**)
```

- [ ] **Step 2: Add the D17 skip** in `tests/studio_test.sh:112`:
  `case "$(basename "$f")" in .gitkeep|*.txt) continue ;; esac`.

- [ ] **Step 3: Write the harness and the failing Task 1 tests** in
  `tests/overnight_test.sh`:

```sh
#!/bin/sh
# Runner suite for studios/game-dev/bin/studio-overnight. A stub `claude`
# (first on PATH) plays each session from a scenario file: one line per
# session, actions separated by ';'. Runs offline; no real claude, gh or
# caffeinate is ever called.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

RUNNER="$REPO_ROOT/studios/game-dev/bin/studio-overnight"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fakebin"
mkdir -p "$FAKE"

# The stub session. Records argv (one element per line), cwd, the
# OMEGA_AUTOPILOT value, start/end epoch seconds and a copy of the lock, then
# runs this call's scenario line.
cat > "$FAKE/claude" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  [ "${STUB_VERSION_STATUS:-0}" = 0 ] || exit "$STUB_VERSION_STATUS"
  echo "2.1.287 (Claude Code)"; exit 0
fi
n=$(( $(cat "$CALLS/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CALLS/count"
date +%s > "$CALLS/$n.t0"
for a in "$@"; do printf '%s\n' "$a"; done > "$CALLS/$n.argv"
pwd -P > "$CALLS/$n.pwd"
printf '%s\n' "${OMEGA_AUTOPILOT:-unset}" > "$CALLS/$n.env"
root="$(sh "$STUB_STATE_BIN" root)"
cp "$root/.studio/overnight.lock" "$CALLS/$n.lock" 2>/dev/null
line="$(sed -n "${n}p" "$OVERNIGHT_SCENARIO")"
cost=1; code=0
old_ifs="$IFS"; IFS=';'
set -f; set -- $line; set +f
IFS="$old_ifs"
for act in "$@"; do
  act="$(printf '%s' "$act" | sed 's/^ *//; s/ *$//')"
  case "$act" in
    "stage "*)    sh "$STUB_STATE_BIN" set stage "${act#stage }" ;;
    "task "*)     sh "$STUB_STATE_BIN" set task "${act#task }" ;;
    "ledger "*)   sh "$STUB_STATE_BIN" ledger "${act#ledger }" ;;
    "branch "*)   b="${act#branch }"
                  git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  sh "$STUB_STATE_BIN" set branch "$b" ;;
    "wtledger "*) ( cd "$(sh "$STUB_STATE_BIN" worktree)" && sh "$STUB_STATE_BIN" ledger "${act#wtledger }" ) ;;
    "cost "*)     cost="${act#cost }" ;;
    nocost)       cost="" ;;
    "sleep "*)    sleep "${act#sleep }" ;;
    ignoreterm)   trap '' TERM ;;
    hang)         while :; do sleep 1; done ;;
    rotsv)        r="$(sed -n 's/^run=//p' "$root/.studio/overnight.lock")"
                  touch "$r/units.tsv"; chmod 444 "$r/units.tsv" ;;
    "exit "*)     code="${act#exit }" ;;
  esac
done
printf '{"type":"system","subtype":"init"}\n'
[ -z "$cost" ] || printf '{"type":"result","subtype":"success","total_cost_usd":%s}\n' "$cost"
date +%s > "$CALLS/$n.t1"
exit "$code"
STUB
printf '#!/bin/sh\nexec claude "$@"\n' > "$FAKE/claude-gd"
printf '#!/bin/sh\nexit "${GH_STATUS:-0}"\n' > "$FAKE/gh"
# A fake caffeinate: records its argv, then lives until the -w pid dies.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$CALLS/caffeinate.args"\nwhile kill -0 "$3" 2>/dev/null; do sleep 1; done\n' > "$FAKE/caffeinate"
chmod +x "$FAKE"/*
export PATH="$FAKE:$PATH" STUB_STATE_BIN="$STATE_BIN"

# fixture NAME [CONFIG_JSON] — a committed project at stage plan with an
# approved spec and plan (with ## Decisions); fresh $CALLS and scenario.
fixture() {
  P="$TMP/$1"; CALLS="$TMP/calls-$1"; TMP_WT="$TMP/wts-$1"
  OVERNIGHT_SCENARIO="$TMP/scenario-$1"
  export CALLS TMP_WT OVERNIGHT_SCENARIO
  mkdir -p "$P/docs" "$CALLS" "$TMP_WT"; : > "$OVERNIGHT_SCENARIO"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    sh "$STATE_BIN" init >/dev/null
    [ -z "${2:-}" ] || printf '%s\n' "$2" > .studio/config.json
    printf '# Spec\n' > docs/spec.md
    printf '# Plan\n\n## Decisions\n\n- none\n' > docs/plan.md
    sh "$STATE_BIN" set spec docs/spec.md; sh "$STATE_BIN" set plan docs/plan.md
    sh "$STATE_BIN" set stage plan
    sh "$STATE_BIN" ledger "spec approved docs/spec.md"
    sh "$STATE_BIN" ledger "plan approved docs/plan.md"
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m fixture ) >/dev/null 2>&1
}
# scenario LINE... — one line per stub session.
scenario() { printf '%s\n' "$@" > "$OVERNIGHT_SCENARIO"; }
# run_start [ARGS] — `studio-overnight start ARGS` in $P, foreground.
run_start() {
  RS_STATUS=0
  ( cd "$P" && sh "$RUNNER" start "$@" ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  RS_OUT="$TMP/rs.out"; RS_ERR="$TMP/rs.err"
}
calls() { cat "$CALLS/count" 2>/dev/null || echo 0; }
last_run_dir() { ls -d "$P"/.studio/reports/overnight-* 2>/dev/null | tail -n 1; }
# A live process whose argv names studio-overnight (the trailing ':' stops sh
# from exec-ing sleep, which would drop the name from ps).
live_dummy() { sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; }
```

  Then the tests:

```sh
test_overnight_help() {
  out="$(sh "$RUNNER" --help 2>&1)"; st=$?
  assert_eq 0 "$st" "--help exits 0"
  printf '%s\n' "$out" > "$TMP/help.txt"
  for w in "start \[--dry-run\]" "status" "stop" "STUDIO_OVERNIGHT_SESSION_SECONDS" "overnight-deny.txt" "report.md"; do
    assert_contains "$TMP/help.txt" "$w" "help names $w"
  done
  assert_contains "$TMP/help.txt" "$RUNNER" "help names the runner by its absolute path"
}

test_overnight_dry_run() {
  fixture dry
  run_start --dry-run
  assert_eq 0 "$RS_STATUS" "dry run exits 0 when every preflight check passes"
  assert_contains "$RS_OUT" "OMEGA_AUTOPILOT=1 claude-gd -p '/game-dev:execute --one'" "dry run prints the launch line, prompt first"
  assert_contains "$RS_OUT" "'Bash(git push --force:\*)'" "a deny rule with spaces is one quoted word"
  assert_contains "$RS_OUT" "'--max-budget-usd' '25'" "session_usd defaults to 25"
  assert_missing "$P/.studio/overnight.lock" "dry run takes no lock"
  assert_missing "$P/.studio/reports" "dry run makes no run directory"
  assert_eq 0 "$(calls)" "dry run launches no session"
}

# refuse_case NAME MESSAGE-PATTERN — run start in the current fixture and
# assert a one-line refusal, exit 2, no lock, no session.
refuse_case() {
  run_start
  assert_eq 2 "$RS_STATUS" "$1: exit 2"
  assert_contains "$RS_ERR" "$2" "$1: names the failure"
  assert_eq 1 "$(grep -c . "$RS_ERR")" "$1: one line"
  assert_missing "$P/.studio/overnight.lock" "$1: no lock"
  assert_eq 0 "$(calls)" "$1: no session"
}

test_overnight_preflight_refusals() {
  fixture r1; sed -i.bak '/plan approved/d' "$P/.studio/ledger/spec.md"; rm -f "$P/.studio/ledger/spec.md.bak"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm x )
  refuse_case "no plan approved line" "plan approved"
  fixture r2; printf 'more\n' >> "$P/docs/plan.md"; refuse_case "dirty plan" "uncommitted"
  fixture r3; printf -- '- x\n' >> "$P/.studio/ledger/spec.md"; refuse_case "dirty ledger" "read the Stop: line"
  fixture r4; printf '# Plan\n' > "$P/docs/plan.md"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm x )
  refuse_case "no Decisions section" "## Decisions"
  fixture r5; ( cd "$P" && sh "$STATE_BIN" set stage idle ); refuse_case "stage idle" "stage idle"
  fixture r6; STUB_VERSION_STATUS=1; export STUB_VERSION_STATUS
  refuse_case "claude-gd --version fails" "claude-gd"; unset STUB_VERSION_STATUS
  fixture r7; GH_STATUS=1; export GH_STATUS; refuse_case "gh not authenticated" "gh auth status"; unset GH_STATUS
}

test_overnight_preflight_all_failures() {
  fixture r8; ( cd "$P" && sh "$STATE_BIN" set stage idle )
  GH_STATUS=1; export GH_STATUS; run_start; unset GH_STATUS
  assert_eq 2 "$RS_STATUS" "two failures: exit 2"
  assert_eq 2 "$(grep -c . "$RS_ERR")" "two failures: one line each"
}

test_overnight_config_refusals() {
  for bad in '"session_usd": 0' '"session_usd": 201' '"run_usd": 2001' '"session_minutes": 9' \
             '"session_minutes": 1.5' '"retries": 4' '"retries": "two"' '"kill_grace_seconds": 4'; do
    key="$(printf '%s' "$bad" | sed 's/^"\([a-z_]*\)".*/\1/')"
    fixture cfg "{ \"overnight\": { $bad } }"
    refuse_case "config $bad" "$key"
  done
  fixture cfgok '{ "overnight": { "session_usd": 2.5, "run_usd": 10, "session_minutes": 10, "retries": 0, "kill_grace_seconds": 5 } }'
  run_start --dry-run
  assert_eq 0 "$RS_STATUS" "in-range config passes, decimals allowed for USD"
  assert_contains "$RS_OUT" "'--max-budget-usd' '2.5'" "session_usd is read from config"
}

test_overnight_deny_file_required() {
  # The runner reads overnight-deny.txt beside itself: run a copy whose
  # sibling deny file holds only comments.
  fixture deny
  mkdir -p "$TMP/denybin"; cp "$RUNNER" "$STATE_BIN" "$TMP/denybin/"
  printf '# only a comment\n\n' > "$TMP/denybin/overnight-deny.txt"
  RS_STATUS=0; ( cd "$P" && sh "$TMP/denybin/studio-overnight" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 2 "$RS_STATUS" "a deny file with no rules refuses"
  assert_contains "$TMP/rs.err" "overnight-deny.txt" "the refusal names the deny file"
  rm -f "$TMP/denybin/overnight-deny.txt"
  RS_STATUS=0; ( cd "$P" && sh "$TMP/denybin/studio-overnight" start ) > /dev/null 2>&1 || RS_STATUS=$?
  assert_eq 2 "$RS_STATUS" "a missing deny file refuses"
}

test_overnight_lock() {
  fixture lock; live_dummy
  printf 'pid=%s\nrun=x\nstarted=y\n' "$DUMMY" > "$P/.studio/overnight.lock"
  refuse_case "live lock" "pid $DUMMY"
  kill "$DUMMY" 2>/dev/null; wait "$DUMMY" 2>/dev/null
  # A stale lock: the pid is dead. The run proceeds with a warning
  # (one no-progress-free session: it ships).
  scenario "stage execute; ledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_contains "$RS_ERR" "reclaiming stale lock (pid $DUMMY)" "a dead pid is reclaimed with a warning"
  assert_contains "$CALLS/1.lock" "^pid=" "the lock names the runner's pid during the run"
  assert_missing "$P/.studio/overnight.lock" "the lock is removed when the run ends"
}

test_overnight_first_use_ignores() {
  fixture ign
  scenario "stage execute; ledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_contains "$P/.studio/reports/.gitignore" "^\*$" "reports/ ignores everything in it"
  assert_contains "$P/.git/info/exclude" "^\.studio/overnight\.lock$" "the lock is excluded locally"
  assert_contains "$P/.git/info/exclude" "^\.studio/overnight\.stop$" "the stop file is excluded locally"
  assert_eq "" "$(cd "$P" && git status --porcelain -- .gitignore .studio/reports)" "no tracked file changes"
}
```

  Add `run_tests test_overnight_help test_overnight_dry_run
  test_overnight_preflight_refusals test_overnight_preflight_all_failures
  test_overnight_config_refusals test_overnight_deny_file_required` at the
  end. Later tasks append their test names to that line.

  `test_overnight_lock` and `test_overnight_first_use_ignores` are written
  now, beside the code they pin, but they need Task 2's loop to finish a
  run. Task 2 Step 1 adds them to `run_tests`, so `run_all.sh` stays green
  at the end of Task 1.

- [ ] **Step 4: Run and see it fail.**
  Run: `sh tests/overnight_test.sh`. Expected: FAIL, because there is no
  runner yet (`sh: …/studio-overnight: No such file`).

- [ ] **Step 5: Implement the skeleton** (`chmod +x`). The hard parts in
  full:

```sh
#!/bin/sh
# studio-overnight — run an approved plan to a draft PR unattended: one fresh
# `claude-gd -p "/game-dev:execute --one"` session per unit, until the
# feature ships or a stop rule fires. Reads studio state, never writes it.
#
#   studio-overnight start [--dry-run]   preflight, then run (dry run: print the launch line)
#   studio-overnight status              the live run: dir, unit, task, spend, pid
#   studio-overnight stop                end the run after the running unit
#
# Exit: start 0 done · 1 any other ending · 2 refused. status 0 live · 1 no
# run. stop 0 stop requested · 1 no run.
# Self-contained on purpose (copy mode); calls its sibling studio-state.
set -u

PROMPT="/game-dev:execute --one"
SELF_ABS="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
self="$0"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
SELF_DIR="$(cd "$(dirname "$self")" && pwd -P)"
STATE_BIN="$SELF_DIR/studio-state"
DENY_FILE="$SELF_DIR/overnight-deny.txt"

say() { printf 'studio-overnight: %s\n' "$*" >&2; }
state() { ( cd "$START_DIR" && sh "$STATE_BIN" "$@" ); }

# cfg_raw KEY — the raw token after "KEY": in config.json; empty when absent.
cfg_raw() {
  [ -f "$CONFIG" ] || return 0
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([^,}[:space:]]*\).*/\1/p' "$CONFIG" | head -n 1
}
# cfg KEY DEFAULT MIN MAX int|dec — sets the variable named by KEY's upper
# case; a present value outside the range or of the wrong kind is a refusal.
cfg() {
  _v="$(cfg_raw "$1")"
  [ -n "$_v" ] || _v="$2"
  case "$5" in
    int) printf '%s' "$_v" | grep -Eq '^[0-9]+$' ;;
    dec) printf '%s' "$_v" | grep -Eq '^[0-9]+(\.[0-9]+)?$' ;;
  esac || { refuse "config overnight.$1 must be a number from $3 to $4 ($5), got $_v"; return; }
  awk -v v="$_v" -v lo="$3" -v hi="$4" 'BEGIN { exit !(v >= lo && v <= hi) }' \
    || { refuse "config overnight.$1 must be from $3 to $4, got $_v"; return; }
  eval "$(printf '%s' "$1" | tr 'a-z' 'A-Z')=\$_v"
}
```

  `cfg` calls: `cfg session_usd 25 1 200 dec`, `cfg run_usd 150 1 2000 dec`,
  `cfg session_minutes 90 10 480 int`, `cfg retries 1 0 3 int`,
  `cfg kill_grace_seconds 30 5 120 int`. Afterwards set
  `GRACE="${KILL_GRACE_SECONDS:-30}"`.

```sh
# with_launch_args FN — FN with the session's argv: prompt first, then the
# flags, --disallowedTools last with one argument per deny rule.
with_launch_args() {
  _fn="$1"
  set -- "$PROMPT" --output-format stream-json --verbose \
    --permission-mode auto --permission-prompts none \
    --max-budget-usd "$SESSION_USD" --disallowedTools
  while IFS= read -r _r || [ -n "$_r" ]; do
    _r="$(printf '%s' "$_r" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$_r" in ''|'#'*) continue ;; esac
    set -- "$@" "$_r"
  done < "$DENY_FILE"
  "$_fn" "$@"
}
print_launch() {
  printf 'cd %s && OMEGA_AUTOPILOT=1 claude-gd -p' "'$START_DIR'"
  for _a in "$@"; do printf " '%s'" "$_a"; done
  printf '\n'
}

lock_pid() { sed -n 's/^pid=//p' "$LOCK" 2>/dev/null | head -n 1; }
lock_live() {
  _p="$(lock_pid)"
  [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null \
    && ps -o args= -p "$_p" 2>/dev/null | grep -q studio-overnight
}
# take_lock RUN_DIR — noclobber, so two starts cannot both win.
take_lock() {
  ( set -C
    printf 'pid=%s\nrun=%s\nstarted=%s\n' "$$" "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK"
  ) 2>/dev/null
}
```

  The path setup runs once, before the subcommand dispatch:
  `START_DIR="$(sh "$STATE_BIN" root --work)"`,
  `STATE_ROOT="$(sh "$STATE_BIN" root)"`,
  `CONFIG="$START_DIR/.studio/config.json"`,
  `LOCK="$STATE_ROOT/.studio/overnight.lock"`,
  `STOP_FILE="$STATE_ROOT/.studio/overnight.stop"`,
  `REPORTS="$STATE_ROOT/.studio/reports"`.

  Preflight sets `FAILED=1` through `refuse() { say "$*"; FAILED=1; }`. It
  runs every check in this order, so several failures print one line each,
  and exits 2 when `FAILED=1`:
  1. `state get stage` succeeds, otherwise `refuse "no studio state here
     (run from the project checkout)"` and exit 2 at once, since the
     remaining checks need it.
  2. `plan="$(state get plan)"`, `spec="$(state get spec)"`.
     `state show | grep -qF -- "plan approved $plan"`, otherwise
     `plan not approved: no 'plan approved <plan>' ledger line`.
  3. `git -C "$START_DIR" status --porcelain -- "$spec" "$plan"` must print
     nothing, otherwise `uncommitted spec or plan — commit them first`. The
     same command over `.studio/ledger .studio/config.json`, otherwise
     `uncommitted ledger change — read the Stop: line, resolve it, commit`
     (D9).
  4. `grep -q '^## Decisions' "$START_DIR/$plan"`, otherwise `plan has no
     ## Decisions section (run /omega:autopilot's question sweep)`.
  5. The stage is `plan` or `execute`, otherwise `stage <s>: nothing
     approved to run`.
  6. `command -v claude-gd` and `claude-gd --version`, otherwise
     `claude-gd not found or not working`.
  7. `gh auth status`, otherwise `gh auth status failed — log in first`.
  8. The deny file exists and has a rule line, otherwise
     `<DENY_FILE>: no deny rules`.
  9. The five `cfg` calls.
  10. `lock_live`, otherwise `a run is live (pid <pid>) — studio-overnight
      status`.

  `start --dry-run` runs the preflight, then `with_launch_args print_launch`,
  then exits 0.

  `start` without `--dry-run` takes the lock. When `lock_live` fails but a
  lock file exists, it prints `say "reclaiming stale lock (pid N)"`, removes
  the file, and retakes it; a failed retake is D14's exit 2. It then:
  - creates `RUN_DIR="$REPORTS/overnight-$(date +%Y%m%d-%H%M%S)"`;
  - writes `$REPORTS/.gitignore` (`*`) when absent;
  - appends `.studio/overnight.lock` and `.studio/overnight.stop` to
    `$(git -C "$START_DIR" rev-parse --path-format=absolute --git-common-dir)/info/exclude`,
    each only when `grep -qxF` finds it absent;
  - runs `rm -f "$STOP_FILE"`.

  The loop arrives in Task 2. Until then `start` writes `report.md` with
  `Ending: stop: not implemented`, unlocks and exits 1. `status` and `stop`
  print `no run` and exit 1 until Task 3 and Task 4.

  `--help` (also `-h`; no argument prints it to stderr and exits 2) prints
  the header's three verbs and starts with `usage: <SELF_ABS> start
  [--dry-run] | status | stop`. It also names `.studio/config.json`
  `overnight` with the five keys, defaults and ranges, the deny file's path
  (`$DENY_FILE`), where `report.md` lands, and
  `STUDIO_OVERNIGHT_SESSION_SECONDS — test hook: overrides session_minutes in
  seconds`.

- [ ] **Step 6: Run the suite.**
  Run: `sh tests/overnight_test.sh`. Expected: every registered test
  passes, and the live-lock refusal can be checked by hand with
  `test_overnight_lock`'s first half. Run `sh tests/studio_test.sh`.
  Expected: PASS (`test_bin_syntax` covers the new runner and skips the
  `.txt` file).

- [ ] **Step 7: Commit.**
  `git add studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-deny.txt tests/overnight_test.sh tests/studio_test.sh && git commit -m "feat(overnight): runner preflight, config, deny list and lock"`

---

### Task 2: The unit loop — launch, signature, classify, cost and budget
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-overnight, tests/overnight_test.sh

**Risk: risky** (the runner-to-session contract). Covers AC2, AC4, AC5, AC6,
AC7, the "retries" and "overhead" feel targets, and D6, D7, D8, D12.

**Interfaces:**
- Consumes everything in Task 1's list.
- Produces:
  - `snapshot STOPS_FILE`, which sets `SIG`, `SIG_STAGE`, `SIG_TASK`,
    `SIG_FRD`, `SIG_SHIPPED` and `FEATURE_DIR`;
  - `label_for` (prints the unit label from the `SIG_*` values);
  - `run_unit N LABEL`, which sets `UNIT_EXIT`, `UNIT_COST` (a number or
    `unknown`), `UNIT_MIN` and `UNIT_TIMED_OUT` (0 here; Task 3 sets it);
  - `spent` (prints the sum of units.tsv's cost column);
  - `finish_run REASON`, which writes `report.md` through the
    `write_report REASON` stub that Task 4 replaces, then unlocks, then
    exits 0 for `done` and 1 for anything else;
  - `units.tsv` columns: `n label exit cost minutes timed_out outcome`, with
    outcome one of `progress`, `noprog`, `stop` or `done`;
  - the run-dir file `current`.

- [ ] **Step 1: Write the failing tests.** Append them, together with Task
  1's `test_overnight_lock` and `test_overnight_first_use_ignores`, to the
  `run_tests` line:

```sh
# done_scenario — the four units of a two-task plan.
done_scenario() {
  scenario "stage execute; task 1/2; ledger T1 complete a..b; cost 2" \
           "task 2/2; ledger T2 complete b..c; ledger T2 Ruling: kept x — y — z; cost 2.25" \
           "ledger final review done; cost 3" \
           "ledger P1 Play: jump on the box; ledger shipped https://github.com/o/r/pull/9; stage idle; task -; cost 1"
}

test_overnight_sequence_to_done() {
  fixture done; done_scenario; run_start
  d="$(last_run_dir)"
  assert_eq 0 "$RS_STATUS" "a shipped run exits 0"
  assert_eq 4 "$(calls)" "four sessions: two tasks, final review, finish"
  for f in 1-T1 2-T2 3-final-review 4-finish; do assert_file "$d/$f.jsonl" "session log $f.jsonl"; assert_file "$d/$f.err" "stderr $f.err"; done
  assert_eq "8.25" "$(awk -F'\t' '{ s += $4 } END { print s }' "$d/units.tsv")" "spend sums each session's total_cost_usd"
  assert_eq "done" "$(awk -F'\t' 'END { print $7 }' "$d/units.tsv")" "the last unit's outcome is done"
}

test_overnight_launch_argv() {
  fixture argv; done_scenario; run_start
  a="$CALLS/1.argv"
  deny="$REPO_ROOT/studios/game-dev/bin/overnight-deny.txt"
  # claude-gd passes its argv through, so the stub sees -p, then the prompt.
  assert_eq "-p" "$(sed -n 1p "$a")" "the session runs headless (-p)"
  assert_eq "/game-dev:execute --one" "$(sed -n 2p "$a")" "the prompt is the first argument after -p (D1)"
  for f in "--output-format" "stream-json" "--verbose" "--permission-mode" "auto" "--permission-prompts" "none" "--max-budget-usd" "25"; do
    assert_contains "$a" "^$f\$" "argv has $f as its own element"
  done
  assert_contains "$a" "^Bash(git push --force:\*)\$" "a deny rule with spaces is one element"
  R="$(grep -v '^#' "$deny" | grep -c .)"
  assert_eq "$(printf -- '--disallowedTools\n'; grep -v '^#' "$deny" | grep .)" \
    "$(tail -n "$((R + 1))" "$a")" "--disallowedTools is the last option, followed by every rule in file order"
  assert_eq "1" "$(cat "$CALLS/1.env")" "OMEGA_AUTOPILOT=1 reaches the session"
  assert_eq "$P" "$(cat "$CALLS/1.pwd")" "every session starts in START_DIR"
}
```

```sh
test_overnight_retry_then_no_progress() {
  fixture retry; scenario "cost 1" "cost 1"; run_start
  d="$(last_run_dir)"
  assert_eq 1 "$RS_STATUS" "no progress exits 1"
  assert_eq 2 "$(calls)" "one retry, then stop"
  assert_file "$d/2-T1-retry.jsonl" "the retry is labelled T1-retry"
  assert_contains "$d/report.md" "no progress on T1" "the ending names the unit"
}

test_overnight_progress_resets_retry() {
  fixture reset; scenario "cost 1" "stage execute; task 1/2" "cost 1" "cost 1"; run_start
  assert_eq 4 "$(calls)" "progress resets the retry count"
  assert_contains "$(last_run_dir)/report.md" "no progress on T2" "the stuck unit is T2"
}

test_overnight_retries_zero() {
  fixture r0 '{ "overnight": { "retries": 0 } }'; scenario "cost 1"; run_start
  assert_eq 1 "$(calls)" "retries 0 stops after the first no-progress session"
}

test_overnight_stop_line() {
  fixture stopl; scenario "stage execute; ledger Stop: no Godot binary (studio-test exit 2)"; run_start
  assert_eq 1 "$RS_STATUS" "a Stop: line exits 1"
  assert_eq 1 "$(calls)" "a Stop: line is never retried"
  assert_contains "$(last_run_dir)/report.md" "stop: no Godot binary (studio-test exit 2)" "the reason is printed verbatim"
}

test_overnight_copied_stop_not_new() {
  fixture copied
  ( cd "$P" && sh "$STATE_BIN" ledger "Stop: an old reason" && git add -A && git -c user.name=t -c user.email=t@t commit -qm old ) >/dev/null
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b" \
           "wtledger Stop: fresh reason"
  run_start
  assert_eq 2 "$(calls)" "a Stop: line the new worktree copied is not new"
  assert_contains "$(last_run_dir)/report.md" "stop: fresh reason" "a Stop: line written in the feature worktree stops the run"
}

test_overnight_run_budget() {
  fixture budget '{ "overnight": { "session_usd": 2, "run_usd": 5 } }'
  scenario "stage execute; task 1/3; cost 2" "task 2/3; cost 2" "task 3/3; cost 2"; run_start
  assert_eq 2 "$(calls)" "the run stops before a launch that could pass run_usd"
  assert_contains "$(last_run_dir)/report.md" "stop: run budget" "budget is the ending"
}

test_overnight_cost_unknown() {
  fixture nocost; scenario "stage execute; task 1/1; nocost" "ledger final review done" \
    "ledger shipped https://x/pull/2; stage idle; task -"
  run_start
  assert_eq "unknown" "$(awk -F'\t' 'NR == 1 { print $4 }' "$(last_run_dir)/units.tsv")" "a session with no result event costs unknown"
}

test_overnight_unexpected_stage() {
  fixture stage; scenario "stage idle"; run_start
  assert_contains "$(last_run_dir)/report.md" "stop: unexpected stage idle" "idle without shipped stops"
}

test_overnight_overhead() {
  fixture over; done_scenario; run_start
  g1=$(( $(cat "$CALLS/2.t0") - $(cat "$CALLS/1.t1") ))
  g2=$(( $(cat "$CALLS/3.t0") - $(cat "$CALLS/2.t1") ))
  g=$g1; [ "$g2" -lt "$g" ] && g=$g2
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$g" -le 5 ]; then _pass "runner overhead between units <= 5 s (min of two: ${g}s)"; else _fail "runner overhead ${g}s > 5 s"; fi
}
```

- [ ] **Step 2: Run and see it fail.**
  Run: `sh tests/overnight_test.sh`. Expected: FAIL. `test_overnight_sequence_to_done` fails with `0 sessions`, because `start` still stops with "not implemented".

- [ ] **Step 3: Implement.** The hard parts:

```sh
# ledger_of DIR — the feature ledger's lines as `studio-state show` prints
# them from DIR (the runner never derives the ledger's file name).
ledger_of() {
  ( cd "$1" && sh "$STATE_BIN" show 2>/dev/null ) | sed -n '/^## Feature ledger: /,$p' | sed 1d
}
feature_dir() {
  _w="$(cd "$START_DIR" && sh "$STATE_BIN" worktree 2>/dev/null)"
  if [ -n "$_w" ] && [ -d "$_w" ]; then printf '%s\n' "$_w"; else printf '%s\n' "$START_DIR"; fi
}
# snapshot STOPS_FILE — the progress signature, and the de-duplicated set of
# Stop: lines from the feature and start checkouts.
snapshot() {
  FEATURE_DIR="$(feature_dir)"
  _l="$(ledger_of "$FEATURE_DIR")"
  SIG_STAGE="$(state get stage)"; SIG_TASK="$(state get task)"
  SIG_FRD="$(printf '%s\n' "$_l" | grep -c '^- [0-9-]* final review done$')"
  SIG_SHIPPED="$(printf '%s\n' "$_l" | grep -c '^- [0-9-]* shipped ')"
  SIG="stage=$SIG_STAGE;task=$SIG_TASK;frd=$SIG_FRD;shipped=$SIG_SHIPPED"
  { printf '%s\n' "$_l"; ledger_of "$START_DIR"; } | grep '^- [0-9-]* Stop: ' | sort -u > "$1"
}
# label_for — the unit's name from the SIG_* values (D8); names files only.
label_for() {
  case "$SIG_STAGE:$SIG_TASK" in
    plan:*|*:-|*:|*:0/*) echo T1; return ;;
  esac
  _k="${SIG_TASK%/*}"; _n="${SIG_TASK#*/}"
  if [ "$_k" -lt "$_n" ]; then echo "T$((_k + 1))"
  elif [ "$SIG_FRD" -eq 0 ]; then echo final-review
  else echo finish; fi
}
# cost_of FILE — total_cost_usd of the last result event; empty when none.
cost_of() {
  grep '"type"[[:space:]]*:[[:space:]]*"result"' "$1" 2>/dev/null | tail -n 1 \
    | sed -n 's/.*"total_cost_usd"[[:space:]]*:[[:space:]]*\([0-9.eE+-]*\).*/\1/p'
}
spent() { awk -F'\t' '$4 != "unknown" { s += $4 } END { printf "%.2f\n", s + 0 }' "$RUN_DIR/units.tsv" 2>/dev/null || echo 0.00; }

start_session() {
  set -m 2>/dev/null || true   # own process group: a terminal Ctrl-C reaches only the runner (D6)
  ( cd "$START_DIR" && OMEGA_AUTOPILOT=1 exec claude-gd -p "$@" ) \
    > "$RUN_DIR/$UNIT_STEM.jsonl" 2> "$RUN_DIR/$UNIT_STEM.err" < /dev/null &
  CPID=$!
  set +m 2>/dev/null || true
}
# run_unit N LABEL — one session, waited for; sets UNIT_* (D7's wait loop).
run_unit() {
  UNIT_STEM="$1-$2"; printf '%s\n' "$2" > "$RUN_DIR/current"
  _t0="$(date +%s)"
  with_launch_args start_session
  _st=0
  while :; do
    wait "$CPID"; _st=$?
    kill -0 "$CPID" 2>/dev/null || break
  done
  UNIT_EXIT="$_st"; UNIT_TIMED_OUT=0
  UNIT_MIN="$(awk -v s="$(( $(date +%s) - _t0 ))" 'BEGIN { printf "%.1f", s / 60 }')"
  UNIT_COST="$(cost_of "$RUN_DIR/$UNIT_STEM.jsonl")"; [ -n "$UNIT_COST" ] || UNIT_COST=unknown
}
row() {  # row N LABEL OUTCOME
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$UNIT_EXIT" "$UNIT_COST" "$UNIT_MIN" "$UNIT_TIMED_OUT" "$3" \
    >> "$RUN_DIR/units.tsv" || { say "cannot write $RUN_DIR/units.tsv"; exit 3; }
}
```

  The loop, after the lock (spec state machine l.286-301):

```sh
n=0; noprog=0; suffix=""; STOP_REQ=0
while :; do
  [ -f "$STOP_FILE" ] || [ "$STOP_REQ" = 1 ] && finish_run "stopped by user"
  _stage="$(state get stage)"
  case "$_stage" in plan|execute) ;; *) finish_run "stop: unexpected stage $_stage" ;; esac
  awk -v s="$(spent)" -v u="$SESSION_USD" -v r="$RUN_USD" 'BEGIN { exit !(s + u > r) }' \
    && finish_run "stop: run budget"
  snapshot "$RUN_DIR/stops.before"; _before="$SIG"; _base="$(label_for)"
  n=$((n + 1)); run_unit "$n" "$_base$suffix"
  snapshot "$RUN_DIR/stops.after"
  _new="$(comm -13 "$RUN_DIR/stops.before" "$RUN_DIR/stops.after" | tail -n 1)"
  if [ -n "$_new" ]; then row "$n" "$_base$suffix" stop; finish_run "stop: ${_new#*Stop: }"; fi
  if [ "$SIG_STAGE" = idle ] && [ "$SIG_SHIPPED" -gt 0 ]; then row "$n" "$_base$suffix" done; finish_run done; fi
  if [ "$SIG" != "$_before" ]; then row "$n" "$_base$suffix" progress; noprog=0; suffix=""; continue; fi
  row "$n" "$_base$suffix" noprog; noprog=$((noprog + 1))
  if [ "$noprog" -le "$RETRIES" ]; then suffix="-retry"; continue; fi
  finish_run "no progress on $_base"
done
```

  Task 1 left a "not implemented" stub; remove it. `write_report REASON`
  for now writes `Ending: <REASON>` as `report.md`'s first line, and Task 4
  replaces it. `finish_run` must be safe to reach from any point: it runs
  `write_report`, then `unlock` (removes the lock and the stop file), then
  exits.

- [ ] **Step 4: Run the suite.** Run `sh tests/overnight_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS, including Task 1's two
  run-dependent tests, which are now registered.

- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/studio-overnight tests/overnight_test.sh && git commit -m "feat(overnight): unit loop, progress signature, retries and budget"`

---

### Task 3: Watchdog, signals, `stop` and the sleep inhibitor
Role: game-dev:gameplay-programmer
Verify: unit
Files: studios/game-dev/bin/studio-overnight, tests/overnight_test.sh

**Risk: risky** (process lifetime and signals). Covers AC8, AC10 and AC13,
the "stop ≤ 1 unit late" feel target, and D6/D7 under signals.

**Interfaces:**
- Consumes `run_unit`, `start_session`, `CPID`, `finish_run`, `unlock`,
  `lock_live`, `STOP_FILE`, `GRACE` and `SESSION_MINUTES`.
- Produces `UNIT_TIMED_OUT=1` for a session the watchdog ended, the
  `INHIB_PID` variable (killed in `unlock`), and `studio-overnight stop`.

- [ ] **Step 1: Write the failing tests:**

```sh
# start_bg [ARGS] — the runner in the background with job control on, so it
# is not started with SIGINT ignored (POSIX ignores it for async lists in a
# non-interactive shell, and an ignored-on-entry signal cannot be trapped).
start_bg() {
  set -m 2>/dev/null
  ( cd "$P" && exec sh "$RUNNER" start "$@" ) > "$TMP/bg.out" 2> "$TMP/bg.err" &
  RPID=$!
  set +m 2>/dev/null
}
# wait_for FILE — up to 10 s.
wait_for() { _i=0; while [ ! -e "$1" ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done; }
bg_status() { BG_STATUS=0; wait "$RPID" || BG_STATUS=$?; }

test_overnight_timeout() {
  fixture tmo; scenario "stage execute; sleep 30" "cost 1"
  STUDIO_OVERNIGHT_SESSION_SECONDS=1; export STUDIO_OVERNIGHT_SESSION_SECONDS
  run_start; unset STUDIO_OVERNIGHT_SESSION_SECONDS
  assert_eq 1 "$(awk -F'\t' 'NR == 1 { print $6 }' "$(last_run_dir)/units.tsv")" "a session past its time is marked timed_out"
  assert_eq progress "$(awk -F'\t' 'NR == 1 { print $7 }' "$(last_run_dir)/units.tsv")" "a timed-out session that moved the signature counts as progress"
}

test_overnight_kill_after_grace() {
  fixture grace '{ "overnight": { "kill_grace_seconds": 5 } }'
  scenario "ignoreterm; hang" "ignoreterm; hang"
  STUDIO_OVERNIGHT_SESSION_SECONDS=1; export STUDIO_OVERNIGHT_SESSION_SECONDS
  run_start; unset STUDIO_OVERNIGHT_SESSION_SECONDS
  assert_eq 2 "$(calls)" "a session that ignores TERM is killed after the grace, and counted"
  assert_contains "$(last_run_dir)/report.md" "no progress on T1" "two killed sessions with no progress stop the run"
}

test_overnight_stop_file() {
  fixture stopf; scenario "stage execute; sleep 2; task 1/3" "task 2/3" "task 3/3"
  start_bg; wait_for "$CALLS/1.t0"
  out="$(cd "$P" && sh "$RUNNER" stop)"; st=$?
  assert_eq 0 "$st" "stop exits 0 while a run is live"
  bg_status
  assert_eq 1 "$(calls)" "the running unit finishes and no other starts"
  assert_contains "$(last_run_dir)/report.md" "stopped by user" "the ending says so"
  assert_missing "$P/.studio/overnight.stop" "the stop file is removed at the end"
}

test_overnight_sigterm() {
  fixture term; scenario "stage execute; sleep 2; task 1/3; exit 7" "task 2/3"
  start_bg; wait_for "$CALLS/1.t0"; kill -TERM "$RPID"; bg_status
  assert_eq 1 "$(calls)" "SIGTERM to the runner: the running unit finishes, then the run stops"
  assert_eq 7 "$(awk -F'\t' 'NR == 1 { print $3 }' "$(last_run_dir)/units.tsv")" "the session's exit code survives the interrupted wait"
  assert_eq 1 "$BG_STATUS" "a user stop exits 1"
}

test_overnight_sigint() {
  fixture int; scenario "stage execute; sleep 2; task 1/3" "task 2/3"
  start_bg; wait_for "$CALLS/1.t0"; kill -INT "$RPID"; bg_status
  assert_eq 1 "$(calls)" "SIGINT to the runner: the running unit finishes, then the run stops"
  assert_contains "$(last_run_dir)/report.md" "stopped by user" "SIGINT is a user stop"
}

test_overnight_stop_no_run() {
  fixture norun
  assert_status 1 "stop with no run exits 1" -- sh -c "cd '$P' && sh '$RUNNER' stop"
}

test_overnight_inhibitor() {
  [ "$(uname -s)" = Darwin ] || { printf '  skip caffeinate case (not Darwin)\n'; return 0; }
  fixture caf; done_scenario; run_start
  pid="$(sed -n 's/^pid=//p' "$CALLS/1.lock")"
  assert_eq "-i -w $pid" "$(cat "$CALLS/caffeinate.args")" "caffeinate -i -w <runner pid> is held for the run"
}

test_overnight_no_inhibitor() {
  # A PATH holding only what the runner needs, and no caffeinate or
  # systemd-inhibit.
  fixture nocaf; done_scenario
  mkdir -p "$TMP/minbin"
  for u in sh git sed awk grep sort comm date ps pkill kill sleep cat mkdir rm touch \
           head tail tr dirname basename readlink wc uname mktemp cp mv chmod env printf; do
    p="$(command -v "$u" 2>/dev/null)" && case "$p" in /*) ln -sf "$p" "$TMP/minbin/$u" ;; esac
  done
  for f in claude claude-gd gh; do ln -sf "$FAKE/$f" "$TMP/minbin/$f"; done
  RS_STATUS=0
  ( cd "$P" && PATH="$TMP/minbin" sh "$RUNNER" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 0 "$RS_STATUS" "the run continues without a sleep inhibitor"
  assert_contains "$TMP/rs.err" "no sleep inhibitor" "one warning names the missing inhibitor"
}
```

- [ ] **Step 2: Run and see it fail.** Expected: `test_overnight_timeout`
  hangs for 30 s and then fails with `timed_out` = 0. `stop` prints
  `no run`.

- [ ] **Step 3: Implement.**
  - **Watchdog** inside `run_unit`, right after `start_session`. The session
    is killed as a process group first (D6), and `pkill -P` is the fallback
    when there is no group:

```sh
  _secs="${STUDIO_OVERNIGHT_SESSION_SECONDS:-$((SESSION_MINUTES * 60))}"
  rm -f "$RUN_DIR/$UNIT_STEM.timed_out"
  ( sleep "$_secs"; : > "$RUN_DIR/$UNIT_STEM.timed_out"
    kill -TERM -"$CPID" 2>/dev/null || { pkill -TERM -P "$CPID"; kill -TERM "$CPID"; }
    sleep "$GRACE"
    kill -KILL -"$CPID" 2>/dev/null || { pkill -KILL -P "$CPID"; kill -KILL "$CPID"; }
  ) > /dev/null 2>&1 &
  WPID=$!
```

    After the wait loop, end the watchdog with `pkill -P "$WPID"; kill
    "$WPID"` (both `2>/dev/null`) and run `wait "$WPID" 2>/dev/null`. Set
    `UNIT_TIMED_OUT=1` when `$UNIT_STEM.timed_out` exists.
  - **Signals:** right after the lock, `trap 'STOP_REQ=1' INT TERM`. D7's
    loop already re-waits after a trapped signal. SIGHUP is not trapped
    (spec l.324-325).
  - **Inhibitor**, after the lock: on Darwin with `caffeinate`, run
    `caffeinate -i -w $$ >/dev/null 2>&1 &`. On Linux with `systemd-inhibit`,
    run `systemd-inhibit --what=idle:sleep --why=studio-overnight sh -c "while kill -0 $$ 2>/dev/null; do sleep 60; done" >/dev/null 2>&1 &`.
    In both cases set `INHIB_PID=$!`. Otherwise print
    `say "no sleep inhibitor (caffeinate or systemd-inhibit) — the machine may sleep; the run resumes with studio-overnight start"`.
    Check `uname -s` first. `unlock` runs `kill "$INHIB_PID"` when it is
    set.
  - **`stop`**: when `lock_live`, run `: > "$STOP_FILE"`, print
    `stop requested: the run ends after its running unit (pid <pid>)`, and
    exit 0. Otherwise print `no run` and exit 1.

- [ ] **Step 4: Run.** Run `sh tests/overnight_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS. The suite takes about 20 s longer
  (the grace test is ~12 s for two killed sessions, the timeout test ~1 s,
  three background tests ~2 s each).

- [ ] **Step 5: Commit.**
  `git add studios/game-dev/bin/studio-overnight tests/overnight_test.sh && git commit -m "feat(overnight): session timeout, user stop, signals and keep-awake"`

---

### Task 4: `report.md`, the EXIT trap and `status`
Role: game-dev:gameplay-programmer
Verify: unit+visual
Files: studios/game-dev/bin/studio-overnight, tests/overnight_test.sh

**Risk: risky** ("a report on every ending" is a feel target). Covers AC11,
AC12, D16 and D18.

**Interfaces:**
- Consumes `finish_run`, `units.tsv`, `ledger_of`, `feature_dir`, `spent`,
  `lock_pid`, `lock_live` and `SELF_ABS`.
- Produces `write_report REASON` (replaces Task 2's stub) and
  `studio-overnight status`.

- [ ] **Step 1: Write the failing tests:**

```sh
test_overnight_report_done() {
  fixture rep; done_scenario; run_start
  R="$(last_run_dir)/report.md"
  assert_contains "$R" "^Ending: done$" "report: the ending"
  assert_contains "$R" "^PR: https://github.com/o/r/pull/9$" "report: the PR URL from the shipped line"
  assert_contains "$R" "^Spent: \\\$8.25$" "report: the total spend"
  assert_contains "$R" "| 3 | final-review | 0 | 3 |" "report: one row per unit with exit and cost"
  assert_contains "$R" "T2 Ruling: kept x — y — z" "report: every Ruling: line, verbatim with its cost"
  assert_contains "$R" "P1 Play: jump on the box" "report: the play list"
  assert_not_contains "$R" "^## Resume" "report: no resume command when done"
}

test_overnight_report_not_done() {
  fixture repn; scenario "cost 1" "nocost"; run_start
  R="$(last_run_dir)/report.md"
  assert_contains "$R" "^Ending: no progress on T1$" "report: the stop reason"
  assert_contains "$R" "cost unknown" "report: an unknown cost is said next to the total"
  assert_contains "$R" "^## Resume" "report: a resume section when not done"
  assert_contains "$R" "cd '$P' && '$RUNNER' start" "report: the absolute resume command (D16)"
  assert_contains "$R" "^PR: none$" "report: no PR yet"
}

test_overnight_report_runner_error() {
  fixture err; scenario "stage execute; task 1/2; rotsv"; run_start
  R="$(last_run_dir)/report.md"
  assert_eq 1 "$RS_STATUS" "a runner error exits 1"
  assert_contains "$R" "^Ending: stop: runner error (exit 3)$" "the EXIT trap writes the report"
  assert_missing "$P/.studio/overnight.lock" "the EXIT trap unlocks"
}

test_overnight_crash_resume() {
  fixture crash; scenario "stage execute; task 1/2; sleep 30" "task 2/2" "ledger final review done" \
    "ledger shipped https://x/pull/3; stage idle; task -"
  start_bg; wait_for "$CALLS/1.t0"
  kill -KILL "$RPID"; wait "$RPID" 2>/dev/null
  # The killed runner's orphans: the stub's sleep and the watchdog's.
  pkill -KILL -f "sleep 30" 2>/dev/null; pkill -KILL -f "sleep 5400" 2>/dev/null
  assert_file "$P/.studio/overnight.lock" "a killed runner leaves its lock"
  run_start
  assert_eq 0 "$RS_STATUS" "the next start reclaims the stale lock and resumes from state"
  assert_contains "$RS_ERR" "reclaiming stale lock" "with a warning"
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "and writes the morning report"
}

test_overnight_status() {
  fixture stat; scenario "stage execute; task 1/2; cost 1.5" "sleep 3; task 2/2"
  start_bg; wait_for "$CALLS/2.t0"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out"; st=$?
  assert_eq 0 "$st" "status exits 0 while a run is live"
  assert_contains "$TMP/st.out" "^run: $P/.studio/reports/overnight-" "status: run dir"
  assert_contains "$TMP/st.out" "^unit: T2$" "status: the running unit"
  assert_contains "$TMP/st.out" "^task: 1/2$" "status: task k/N"
  assert_contains "$TMP/st.out" "^spent: \\\$1.50$" "status: spend so far"
  assert_contains "$TMP/st.out" "^pid: $RPID$" "status: the lock pid"
  ( cd "$P" && sh "$RUNNER" stop ) >/dev/null; bg_status
  assert_status 1 "status with no run exits 1" -- sh -c "cd '$P' && sh '$RUNNER' status"
  assert_eq "no run" "$(cd "$P" && sh "$RUNNER" status 2>&1)" "status prints no run"
}
```

  `test_overnight_crash_resume` reuses Task 3's `start_bg`. Its first
  scenario line sleeps 30 s, so the test kills the orphaned stub with
  `pkill -f`.

- [ ] **Step 2: Run and see it fail.** Expected: the report holds only
  `Ending:`. `status` prints `no run`.

- [ ] **Step 3: Implement.** `write_report REASON` writes
  `$RUN_DIR/report.md` from `ledger_of "$(feature_dir)"` and `units.tsv`.
  The layout (blank lines as shown; table rows from units.tsv; `(none)`
  under an empty section):

```markdown
# Overnight run — overnight-20261002-013000

Ending: done
Plan: docs/game-dev/plans/2026-10-02-x.md
Branch: KAN-7-dash
PR: https://github.com/o/r/pull/9
Spent: $8.25
Started: 2026-10-02T06:30:00Z · Ended: 2026-10-02T09:12:41Z

## Units

| # | Unit | Exit | Cost | Minutes | Timed out | Outcome |
|---|------|------|------|---------|-----------|---------|
| 1 | T1 | 0 | 2 | 41.0 | 0 | progress |

## Rulings

- 2026-10-02 T2 Ruling: kept x — y — z

## Play list

- 2026-10-02 P1 Play: jump on the box

## Resume

cd '/abs/start/dir' && '/abs/path/studio-overnight' start
```

  - `PR:` is the text after `shipped ` on the last `shipped` line, or
    `none`.
  - `Spent:` is `spent`. When any unit's cost is `unknown`, append
    ` (cost unknown for <k> unit(s))`.
  - `Branch:` comes from `state get branch`, and `Started:` from the lock.
  - Rulings are every ledger line matching `Ruling:`. The play list is every
    line matching `P[0-9]* Play:`.
  - `## Resume` is written only when the ending is not `done`.
  - The EXIT trap is set right after the lock (D18):
    `trap 'on_exit $?' EXIT`. `on_exit` does nothing once `finish_run` has
    set `REPORTED=1`. Otherwise it runs
    `write_report "stop: runner error (exit $1)"`, then `unlock`, then
    `exit 1`, so `start` keeps its "1 = any other ending" code.
  - `finish_run` sets `REPORTED=1` before it exits, and exits 0 only for
    `done`.
  - `status`: when `lock_live`, print `run:` (the lock's `run=`), `unit:`
    (the run dir's `current`), `task:` (`state get task`), `spent: $<spent>`
    and `pid:`, then exit 0. Otherwise print `no run` and exit 1. `spent`
    reads `$RUN_DIR`, so `status` sets `RUN_DIR` from the lock first.

- [ ] **Step 4: Run.** Run `sh tests/overnight_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS.

- [ ] **Step 5: Visual item for the play list:** "Read `report.md` from
  `test_overnight_report_done`'s run, or from the live run. Pass: it answers
  'what happened overnight' (how it ended, what it cost, which rulings to
  check, what to play, where the PR is, how to resume) without opening a
  `.jsonl`. Fail: you had to open a log to learn any of those."

- [ ] **Step 6: Commit.**
  `git add studios/game-dev/bin/studio-overnight tests/overnight_test.sh && git commit -m "feat(overnight): morning report, exit trap and status"`

---

### Task 5: Execute `--one` — exactly one unit per session
Role: game-dev:gameplay-programmer
Verify: unit+playtest
Files: studios/game-dev/skills/execute/SKILL.md, tests/studio_test.sh

**Risk: risky** (the session side of the contract). Covers AC3 and AC6
(session side), and D2 and D9. Can run in parallel with Tasks 1-4.

**Interfaces:** produces the session-side contract that Task 2's tests
simulate:
- task unit: `task n/N` plus `T<n> complete`;
- final review unit: `final review done`;
- finish unit: `shipped <url>`, `stage idle`, `task -`;
- any stop: `Stop: <reason>`.

- [ ] **Step 1: Write the failing contract test** `test_execute_one_contract`
  in `tests/studio_test.sh` (add it to `run_tests`):

```sh
test_execute_one_contract() {
  S="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$S" "^## 8. One unit (--one)$" "execute has the --one section"
  assert_contains "$S" "exactly one unit" "--one runs exactly one unit"
  assert_contains "$S" "no next implementer is dispatched" "--one cuts SDD's loop after one task"
  assert_contains "$S" "overrides SDD's instruction to continue to the next task" "the cut overrides SDD"
  assert_contains "$S" "git push -u origin <branch>" "a task unit pushes its branch"
  assert_contains "$S" 'studio-state ledger "Stop: <reason>"' "every stop writes a Stop: line under --one"
  assert_contains "$S" 'git commit -m "chore(studio): stop"' "the Stop: line is committed in a feature checkout"
  assert_contains "$S" "not the default branch" "a Stop: before isolation is not committed onto the default branch (D9)"
  assert_contains "$S" "A rejected push is a \`Ruling:\` line, not a stop" "a rejected push is a ruling"
  assert_contains "$S" "never runs \`omega:handoff\`" "--one writes no handoff"
  assert_contains "$S" "\`--one\` with \`--inline\` is refused" "--one is subagent-driven only"
  assert_contains "$S" "Under \`--one\`, see §8" "the sections that stop or continue point at §8"
  assert_eq 5 "$(grep -c 'Under `--one`, see §8' "$S")" "five pointers: §0, §1, §5 step 6, §7 step 6, §7 step 7"
}
```

- [ ] **Step 2: Run and see it fail.** Run `sh tests/studio_test.sh`.
  Expected: FAIL (missing `## 8. One unit (--one)`).

- [ ] **Step 3: Write §8** at the end of `execute/SKILL.md`. The text,
  wrapped so that each asserted literal stays on one line:

```markdown
## 8. One unit (--one)

`--one` is how `studio-overnight` drives this skill: one fresh headless session per unit, with `OMEGA_AUTOPILOT=1` set, so `omega-mode show` lists `autopilot source=env` and its phase 2 rules hold. Under `--one` this skill runs exactly one unit, writes its state, commits, pushes, and ends the turn.

- **Which unit:** exactly the one §0's *Where to start* picks.
  - `task k/N` with k < N: one SDD task, `T<k+1>`.
  - `N/N` without a `final review done` line: §5 as a whole, the fix wave
    included, through step 6.
  - `N/N` with that line: §7 steps 1–6.
  - Never more than one.
- **Cutting SDD's loop:** invoke SDD as §1 says. Once the task is complete
  (§4a rule 6) and §6's writes are done (`set task n/N`, the `T<n> complete`
  line, the ledger committed), no next implementer is dispatched, and when
  n = N §5 is not started. This overrides SDD's instruction to continue to the next task.
- **What each unit writes:**
  - a task: the task's commits, `task n/N`, the `T<n>` ledger lines, then
    `git push -u origin <branch>`;
  - the final review: the `fix(final)` commits, the `Review: final` and
    `final review done` lines committed, then the push;
  - the finish: §7 as written (`P<k> Play:` lines, the draft PR,
    `shipped <url>`, `stage idle`, `task -`).
  A rejected push is a `Ruling:` line, not a stop.
- **Every stop** (§0's preconditions and isolation stops, §6's hard-stop
  list, §7 step 1's exit 2 and exit 3): run
  `studio-state ledger "Stop: <reason>"`, one line, reason first. Then, only
  when `git branch --show-current` is not the default branch, commit it:
  `git add .studio/ledger && git commit -m "chore(studio): stop"`. A stop
  before isolation leaves the line uncommitted in the main checkout: a hard
  stop needs a human, and the runner reads the file either way. Then end
  the turn.
- **§7 step 6, headless:** `ExitWorktree` `action: "keep"` runs as written.
  The "started in the feature worktree" note and the `Next:` line are
  skipped, because no human reads this session.
- **No handoff:** `--one` never runs `omega:handoff`. The runner's
  `report.md` is the morning report.
- `--one` with `--inline` is refused with a `Stop:` line (subagent-driven
  only).
```

  Add the pointer `Under `--one`, see §8.` (one line, this exact text) in
  five places:
  - the end of §0's preconditions list, for every stop;
  - §1's `--inline` paragraph;
  - §5 step 6, after the commit;
  - §7 step 6;
  - §7 step 7.

  Also add `--one` to the announce line in §0's heading area:
  `(… "… one unit (--one)" when `--one` was given)`.

- [ ] **Step 4: Run.** Run `sh tests/studio_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS.

- [ ] **Step 5: Playtest item (exit criterion 2) for the play list:**
  "Make a throwaway Godot project (`/game-dev:scaffold`) with an approved
  two-task plan whose plan has `## Decisions`. Run `/omega:autopilot`, then
  the printed `studio-overnight start` from a plain terminal, and go away.
  Pass:
  - a draft PR exists;
  - `units.tsv` shows four sessions (`T1`, `T2`, `final-review`, `finish`),
    each with exit 0 and outcome `progress` or `done`;
  - each `.jsonl`'s first assistant `usage` is under 90k input tokens
    (cache creation plus cache read), and the task units end under 250k;
  - `report.md` is complete.

  Fail: any session waiting on a prompt (a `.jsonl` with a permission
  denial that the unit needed), a unit run twice although it made progress,
  or no `report.md`. Reinstall first (`./install.sh`), so the config-root
  `bin/` links `studio-overnight`."

- [ ] **Step 6: Commit.**
  `git add studios/game-dev/skills/execute/SKILL.md tests/studio_test.sh && git commit -m "feat(execute): --one runs exactly one unit for the overnight runner"`

---

### Task 6: `omega-mode` sees `OMEGA_AUTOPILOT=1`
Role: game-dev:gameplay-programmer
Verify: unit
Files: shared/omega/bin/omega-mode, tests/omega_test.sh

**Risk: risky** (a seam: the hooks' brief and execute §7 step 4's draft
rule both read it). Covers AC14. Can run in parallel with Tasks 1-4.

**Interfaces:** produces the `show` line `autopilot source=env`, and in
`brief`, the line that starts `  autopilot (overnight runner):`.

- [ ] **Step 1: Write the failing test** `test_mode_env_autopilot` (add to
  `run_tests` after `test_mode_brief`):

```sh
test_mode_env_autopilot() {
  # No session id at all: the env line alone, exit 0.
  out="$(env -u CLAUDE_CODE_SESSION_ID OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" show)"; st=$?
  assert_eq 0 "$st" "show with OMEGA_AUTOPILOT=1 and no session id exits 0"
  assert_eq "autopilot source=env" "$out" "show prints the env line"
  out="$(env -u CLAUDE_CODE_SESSION_ID OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" brief)"
  printf '%s\n' "$out" > "$TMP/env-brief.txt"
  assert_contains "$TMP/env-brief.txt" "^Omega modes: autopilot source=env$" "brief heads with the env line"
  assert_contains "$TMP/env-brief.txt" "autopilot (overnight runner): never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a draft PR, never merge; on a hard stop write Stop: <reason> to the ledger and end; no handoff — the runner starts the next session\." "brief carries the runner's rule text"
  # A session file with reply: both lines, file first.
  CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs set reply
  out="$(OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs show)"
  assert_eq "reply
autopilot source=env" "$out" "the file's lines, then the env line"
  # A session-file autopilot line wins: no duplicate, today's text.
  CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs set autopilot
  assert_eq 1 "$(OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs show | grep -c '^autopilot')" "no env line when the file lists autopilot"
  OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session envs brief > "$TMP/env-brief2.txt"
  assert_contains "$TMP/env-brief2.txt" "end with handoff" "a session-file autopilot keeps today's text"
  # Unset or not 1: nothing.
  assert_eq "" "$(env -u OMEGA_AUTOPILOT CLAUDE_CONFIG_DIR="$TMP/cfg-env" sh "$MODE" --session none show)" "no env, no file: nothing"
  assert_status 1 "without the env, a missing session id still dies" -- env -u CLAUDE_CODE_SESSION_ID -u OMEGA_AUTOPILOT sh "$MODE" show
  assert_status 1 "set still needs a session id under the env" -- env -u CLAUDE_CODE_SESSION_ID OMEGA_AUTOPILOT=1 sh "$MODE" set reply
}
```

- [ ] **Step 2: Run and see it fail.**
  Run: `sh tests/omega_test.sh`. Expected: FAIL (`no session id`).

- [ ] **Step 3: Implement** in `omega-mode`:
  - The session-id check becomes: when `SESSION` is empty and `VERB` is
    `show` or `brief` and `${OMEGA_AUTOPILOT:-}` = `1`, set `FILE=` (empty)
    and skip the id and dir checks. Otherwise everything is unchanged.
  - Add `env_line() { [ "${OMEGA_AUTOPILOT:-}" = 1 ] || return 0; [ -n "$FILE" ] && [ -f "$FILE" ] && awk '$1 == "autopilot" { f = 1 } END { exit !f }' "$FILE" && return 0; echo "autopilot source=env"; }`.
  - `mode_show` prints the file (when `FILE` is set and the file exists),
    then `env_line`.
  - `mode_brief` builds its input as `{ [ -n "$FILE" ] && cat "$FILE"
    2>/dev/null; env_line; }` into a temp variable. It returns when that is
    empty, and otherwise runs today's heads and per-line loop over it. In
    the `autopilot)` case, `_rest` = `source=env` prints:
    `  autopilot (overnight runner): never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a draft PR, never merge; on a hard stop write Stop: <reason> to the ledger and end; no handoff — the runner starts the next session.`
    Any other `_rest` keeps today's line.
  - The header comment documents `OMEGA_AUTOPILOT=1`.

- [ ] **Step 4: Run.** Run `sh tests/omega_test.sh`, then
  `sh tests/run_all.sh`. Expected: PASS. `test_mode_brief` and the hook
  tests are unchanged, because no test sets the variable.

- [ ] **Step 5: Commit.**
  `git add shared/omega/bin/omega-mode tests/omega_test.sh && git commit -m "feat(omega-mode): OMEGA_AUTOPILOT=1 lists autopilot from the environment"`

---

### Task 7: Autopilot hands off to the runner; router names a live run
Role: game-dev:gameplay-programmer
Verify: unit
Files: shared/omega/skills/autopilot/SKILL.md, tests/omega_contracts/autopilot_contract.sh, docs/omega/pressure/autopilot.md, README.md, studios/game-dev/skills/studio/SKILL.md, tests/studio_test.sh

**Risk: risky** (a behavioural contract the user meets every night). Covers
AC15 (the autopilot half), the spec's Teaching section, D10, D15 and D16.
Needs Tasks 1 and 6.

**Interfaces:**
- Consumes `studio-overnight start --dry-run` (exit 0 when ready),
  `studio-overnight status|stop`, and `omega-mode`'s `source=env`.

- [ ] **Step 1: Rewrite the contract first.** Replace
  `tests/omega_contracts/autopilot_contract.sh` with the following. The
  absence assertions use split spellings per the Global Constraints.

```sh
#!/bin/sh
# Text contract for shared/omega/skills/autopilot/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_autopilot_contract.
test_autopilot_contract() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "autopilot carries the precedence contract"
  assert_contains "$S" "[Nn]ever merge" "autopilot never merges"
  assert_contains "$S" "AskUserQuestion. is never called" "autopilot forbids AskUserQuestion in phase 2"
  assert_contains "$S" "cost if wrong" "autopilot logs rulings with their cost if wrong"
  assert_contains "$S" "## Decisions" "autopilot records the question sweep in the plan"
  assert_contains "$S" "gh auth status" "autopilot's readiness checklist checks gh"
  assert_contains "$S" "KAN-" "autopilot detects a Jira story from the branch"
  assert_contains "$S" "already approved and committed" "autopilot skips design and plan when both are approved and committed"
  assert_contains "$S" "no second PR is opened" "autopilot opens no second PR when the invoking skill opened one"
  assert_contains "$S" "studio-overnight start --dry-run" "the readiness checklist runs the runner's preflight"
  assert_contains "$S" "studio-overnight start" "phase 1 ends by printing the runner command"
  assert_contains "$S" "studio-overnight status" "the user is told how to watch the run"
  assert_contains "$S" "studio-overnight stop" "off stops a live run"
  assert_contains "$S" "source=env" "phase 2 applies under the runner's environment"
  assert_contains "$S" 'Stop: <reason>' "a hard stop under the runner writes a Stop: line"
  assert_contains "$S" "report.md" "the user is told where the morning report lands"
  assert_contains "$S" "omega-mode clear autopilot" "off and the session-mode disarm clear the mode"
  assert_contains "$S" "omega-mode set autopilot" "outside a studio the mode is set in-session"
  assert_contains "$S" "one unit, then end" "the --one red flag"
  assert_not_contains "$S" "omega-""caffeine" "no keep-awake tool remains"
  assert_not_contains "$S" "Cron""Create" "no heartbeat is armed"
  assert_not_contains "$S" "Cron""Delete" "no heartbeat is deleted"
  assert_not_contains "$S" "heartbeat" "no heartbeat at all"
  assert_not_contains "$S" "on the feature branch, in a worktree" "the worktree readiness line is replaced by the dry run"
}
```

- [ ] **Step 2: Add the router test** `test_router_overnight_lock` to
  `tests/studio_test.sh` and its `run_tests` line:

```sh
test_router_overnight_lock() {
  S="$REPO_ROOT/studios/game-dev/skills/studio/SKILL.md"
  assert_contains "$S" ".studio/overnight.lock" "the router checks the runner's lock"
  assert_contains "$S" "Overnight run in progress (pid <pid>) — studio-overnight status" "the router names status when a run is live"
  assert_contains "$S" "routes nothing else" "a live run blocks routing"
}
```

- [ ] **Step 3: Run and see it fail.** Run `sh tests/omega_test.sh` and
  `sh tests/studio_test.sh`. Expected: FAIL. The new literals are missing,
  and the absence assertions fail on the current text.

- [ ] **Step 4: Rewrite `autopilot/SKILL.md`** per spec l.440-464:
  - **`off`**: `omega-mode clear autopilot`; then, when
    `studio-overnight status` exits 0, `studio-overnight stop`; then stop.
    The phase 1 leftover disarm is the same clear.
  - **Phase 1 step 3**: in a studio, commit only, because the first task
    unit pushes the feature branch. Outside a studio it is unchanged.
  - **Phase 1 step 5**: in a studio, the "on the feature branch, in a
    worktree" line becomes "`studio-overnight start --dry-run` exits 0 (the
    runner's own preflight: plan approved and committed, `## Decisions`,
    stage, `claude-gd`, `gh`, deny list, config, no live run)". The
    baseline-test and engine lines stay.
  - **Phase 1 step 6, in a studio**: set no mode. Print:
    - the absolute command (`command -v studio-overnight` from this
      session, D16) and the checkout to run it from (`studio-state root
      --work`), as `cd '<dir>' && '<abs>' start`;
    - what the run may do: commit, push the feature branch, open a draft PR;
    - what it may not do: merge, force-push, delete a remote branch,
      destructive or security-sensitive operations, secrets;
    - `studio-overnight status` and `studio-overnight stop`;
    - that `report.md` lands in `.studio/reports/overnight-<ts>/`;
    - that this session can now close.
  - **Phase 1 step 6, outside a studio**: `omega-mode set autopilot`, and
    the user starts the run in this session. No keep-awake, no heartbeat.
  - Delete the "resumed session repeats steps 2–3" paragraph and the `/clear`
    sentence about disarming (a runner session's mode comes from the
    environment).
  - **Phase 2**: applies while `omega-mode show` lists `autopilot` from
    either source (`source=env` under the runner).
    - Hard stop under `source=env`: `studio-state ledger "Stop: <reason>"`,
      then end. No handoff, no disarm.
    - Completion under `source=env`: the invoking skill's unit ends the
      session, and the runner reports.
    - Session-mode completion and hard stop: `omega:handoff`, then
      disarm = `omega-mode clear autopilot`.
    - "Allowed side effects" says "push after every integrated task" and
      keeps the draft-PR wording.
  - **Red flags**: delete both heartbeat rows. Rewrite the "hook block
    already says autopilot" row to say clear (`omega-mode clear autopilot`)
    instead of disarm. Add the row `| "I'll start the next task while I'm
    here" | Under `--one`: one unit, then end. The runner starts the next
    session. |`.
  - Keep every literal that Step 1's positive assertions name on one line.

- [ ] **Step 5: The router.** In `studios/game-dev/skills/studio/SKILL.md`
  §1, add as the first bullet: "When `$(studio-state root)/.studio/overnight.lock`
  exists and its `pid=` is live (`kill -0`), print `Overnight run in
  progress (pid <pid>) — studio-overnight status` and stop: the router
  routes nothing else while a run holds the project."

- [ ] **Step 6: The pressure scenario** `docs/omega/pressure/autopilot.md`
  (D10): change the scenario's expected behaviour so that phase 1 ends by
  printing the `studio-overnight start` command and sets no mode in a
  studio. Recorded transcripts stay as written. **README.md l.127**: the
  autopilot row becomes "Asks every open decision up front, checks
  readiness with `studio-overnight start --dry-run`, then prints the runner
  command: one fresh headless session per unit, rulings logged, a draft PR,
  never a merge."

- [ ] **Step 7: Run.** Run `sh tests/omega_test.sh`, `sh tests/studio_test.sh`
  and `sh tests/run_all.sh`. Expected: PASS.

- [ ] **Step 8: Commit.**
  `git add shared/omega/skills/autopilot/SKILL.md tests/omega_contracts/autopilot_contract.sh docs/omega/pressure/autopilot.md README.md studios/game-dev/skills/studio/SKILL.md tests/studio_test.sh && git commit -m "feat(autopilot): hand the run to studio-overnight; router names a live run"`

---

### Task 8: Retire `omega-caffeine` and add the absence check
Role: game-dev:gameplay-programmer
Verify: unit
Files: shared/omega/bin/omega-caffeine, shared/omega/hooks/session-start.sh, shared/omega/hooks/session-end.sh, shared/omega/hooks/prompt-submit.sh, shared/omega/skills/delegate/SKILL.md, tests/omega_test.sh, tests/install_test.sh, README.md

**Risk: mechanical.** Covers AC15 (deletion and absence) and D11. Goes last.

- [ ] **Step 1: Write the failing absence check** `test_no_keepawake_or_cron`
  in `tests/omega_test.sh` (it replaces `test_caffeine` on the `run_tests`
  line):

```sh
# AC15: no shipped path names the retired keep-awake tool or the in-session
# scheduler. The names are spelled split here, so this file is scanned too.
test_no_keepawake_or_cron() {
  pat="omega-""caffeine|Cron""Create"
  hits="$(cd "$REPO_ROOT" && grep -rlE "$pat" shared studios tests README.md install.sh 2>/dev/null)"
  assert_eq "" "$hits" "no shipped path names the retired tools"
  assert_missing "$REPO_ROOT/shared/omega/bin/omega-""caffeine" "the keep-awake tool is deleted"
}
```

- [ ] **Step 2: Run and see it fail.** Run `sh tests/omega_test.sh`.
  Expected: FAIL, listing the bin file, the three hooks, `delegate/SKILL.md`,
  `omega_test.sh`, `install_test.sh` and `README.md`.

- [ ] **Step 3: Remove:**
  - `git rm shared/omega/bin/omega-caffeine`.
  - `session-start.sh`: drop `CAFFEINE=`, the ` Keep-awake: … .` clause of
    `text=`, and the header's mention.
  - `session-end.sh`: drop `CAFFEINE=`, the stop call and its comment. The
    header becomes "the ending session's mode file is deleted".
  - `prompt-submit.sh`: drop `CAFFEINE=`. `autopilot off` only runs `clear
    autopilot`; drop the comment lines about the keep-awake pid.
  - `delegate/SKILL.md:35`: drop it from the status-command list.
  - `tests/omega_test.sh`: delete `test_caffeine`, the fake `caffeinate`
    PATH and the `caffeine` helper (l.15-30, l.113-130). Delete the
    `Keep-awake` assertion (l.274) and the caffeine lines at l.416-418,
    526-527 and 627-628. Fix the header comment.
  - `tests/install_test.sh:145`: `for tool in omega-mode; do`.
  - `README.md:250`: delete the tree line. Under the game-dev studio's
    `bin/` tree, add
    `studio-overnight          overnight runner: one fresh session per unit to a draft PR`
    and `overnight-deny.txt        the runner's deny list (data)`, aligned with
    their neighbours.

- [ ] **Step 4: Run.** Run `sh tests/omega_test.sh`, `sh tests/install_test.sh`
  and `sh tests/run_all.sh`. Expected: PASS. Also run
  `grep -rnE 'omega-caffeine|CronCreate' shared studios tests README.md install.sh`.
  Expected: no output.

- [ ] **Step 5: Commit.**
  `git add -A shared tests README.md && git commit -m "refactor(omega): retire omega-caffeine; the runner holds the sleep inhibitor"`

---

## Final gate

1. Standalone final whole-branch review on Opus against the spec and this
   plan, with this plan's Review Focus first.
2. `sh tests/run_all.sh` exits 0.
3. Exit criterion 3:
   `grep -rnE 'omega-caffeine|CronCreate' shared studios tests README.md install.sh`
   prints nothing.
4. The play list carries Task 5's live run (exit criterion 2) and Task 4's
   visual item. The PROGRESS entry lands with the story PR (studio memory).

## Backlog

Nothing cut in the scope pass. Every task either serves a milestone exit
criterion directly or is needed for the live run to finish end to end.
