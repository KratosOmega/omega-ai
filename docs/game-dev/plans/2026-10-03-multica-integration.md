# Multica Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Draft — awaiting user review

**Goal:** Make Multica the remote cockpit for the studio: a Multica agent
starts game-dev work (including detached overnight runs) in the project, a
launchd bridge mirrors each run as a Run issue with one sub-issue per story,
and comment commands (`/say`, `/hold`, `/resume`, `/stop`, …) steer the run
through the #27 verbs. The core gains one read-only verb, `deny-rules`, and
one optional registry line, `origin=` (copied from `STUDIO_RUN_ORIGIN`),
which tells the bridge which Multica task started a run.

**Architecture:** Everything Multica-specific lives in `integrations/multica/`.
Two POSIX `sh` wrappers (`claude-multica`, `omega-multica-agent`) are the
Multica runtimes. A Python 3.9+ standard-library bridge (`multica-bridge`,
package `bridge/`) polls the run registry and each run's `events.jsonl`,
writes to Multica only through one CLI adapter (`multica_cli.py`), and calls
the core only through `studio-overnight` verbs with an argument list. An
offline stub CLI (`tests/stub-multica`) holds a fake board, so every test runs
without the network or model calls. `install.sh`/`uninstall.sh` set up
Multica (properties, runtime profiles, agent) and the launchd agent.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2), Python 3.9 standard
library (`unittest`, `subprocess`, `fcntl`, `json`, `logging`), Multica CLI
0.6.1, launchd, macOS Keychain (`security`), `osascript`.

**Spec:** `docs/game-dev/specs/2026-10-03-multica-integration.md` (revision 4,
approved; commit dae9e8d, plus 1f2c1b4: P4 on stand-ins, gate step 4.2
checks `origin=`). Depends on `docs/game-dev/specs/2026-10-03-overnight-operator-channel.md`
(revision 4, amendments A1–A3 included).

**Story:** #28 (GitHub issue). Branch `worktree-issue-28-multica`.

**Review policy (user CLAUDE.md):**
- Each task carries `Spec:` (its spec line ranges) and `Review: task|final`
  under its heading.
- A `Review: task` task gets a per-task review on Opus (`model: "opus"`). A
  `Review: final` task folds into the final review.
- Minor findings are batched into the final fix wave. Every fix round goes to
  a fresh fixer given the findings and the diff range.
- Re-review only after a Critical, three or more Importants, or a
  production-bug fix. Never a third pass.
- The final review is a standalone whole-branch review on Opus, never folded
  into the last task review. Then the full gate.

## Prerequisite — #27 is merged first

#27 (operator channel) is implemented and merged to `main` before any task
here starts. This plan plans no #27 work except AC1 (`deny-rules`) and AC1a
(the registry's `origin=` line), which the #28 spec owns. Before Task 1 the controller runs, in the worktree:

```sh
git fetch origin
git merge --no-edit origin/main          # on worktree-issue-28-multica
test -f docs/game-dev/overnight-events.md || echo "MISSING: #27 contract doc"
test -x studios/game-dev/bin/studio-event || echo "MISSING: studio-event"
sh studios/game-dev/bin/studio-overnight --help | grep -q -- '--run' || echo "MISSING: --run (A1)"
sh studios/game-dev/bin/studio-overnight --help | grep -q 'say' || echo "MISSING: say verb"
( cd "$(mktemp -d)" && sh "$OLDPWD/studios/game-dev/bin/studio-overnight" say --run nope S1 -- hi; echo "exit $?" )
#   expected: one line containing "run nope is not live", then "exit 1" (A1)
sh tests/run_all.sh                       # green on the merged base
```

Any `MISSING:` line, or an exit other than 1, stops the plan: #27 has not
landed. Line numbers this plan cites inside `studio-overnight` and
`tests/overnight_test.sh` are from the pre-#27 file; each is also given as a
`grep -n` anchor, which the implementer uses after the merge.

## Global Constraints

Copied verbatim from the spec (line numbers in parentheses). Every task's
requirements implicitly include this section.

**Milestone gate (spec 21-50):**

1. `sh tests/run_all.sh` is green, including the new `deny-rules` and
   `origin=` cases.
2. `sh integrations/multica/tests/run.sh` is green. It uses a stub `multica`
   CLI and fixture runs; it never reaches the network or spends model calls.
3. The plan's first task runs the open probes (Open probes) and records the
   results in this spec's References before any bridge code is written; a
   failed probe sends the design back for revision.
4. One live check on this Mac against workspace `omega-alpha`, in a
   throwaway Godot project under `~/Documents` with an approved two-story
   manifest:
   1. `install.sh` sets up the properties, both runtimes, the game-dev agent
      and the bridge. The only manual steps are creating the API token and
      the macOS file-access grants install names. `multica-bridge status`
      reports no file-access error.
   2. An issue "Tonight: probe" assigned to the game-dev agent asks for the
      run; the agent runs `studio-overnight start --detach <manifest>`, and
      the runner keeps going after the agent's task ends.
   3. The board shows "Run <name>" under that issue, one sub-issue per story,
      statuses that follow the run, and a comment per unit start and end.
   4. A `/say` posted from the phone's browser on a story issue gets a ✓
      reply and a "message delivered" comment; `/hold` then `/resume` on the
      other story hold and resume it.
   5. The run ends; the Run issue reads Done with the ending and report path,
      and the game-dev agent posts its run summary on the request issue.
   6. `multica issue runs` on the request issue lists the run the operator
      started and exactly one "sub-issues closed" wakeup; no bridge comment
      or status change started any other run.

**Input and platform (spec 109-115):**

macOS (launchd) for the bridge service; the bridge itself is portable Python
3.9+ standard library. Wrappers are POSIX `sh`. Multica CLI 0.6.x (bundled
with the desktop app at
`/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica`).
Multica Cloud Free plan; self-hosting is a `server_url` change.

**Feel targets (spec 117-121):**

- A comment command gets its ✓/✗ reply within one poll (`poll_seconds`,
  default 15 s) plus the core verb's time.
- A run event reaches the board within one poll.

**Tuning knobs (spec 700-704):** `poll_seconds`; the stale-command age (10
min); the reply cut (1000 characters); backoff cap (300 s); permanent-error
attempts (3); the request-issue resolution limit (5 min); the self-test
interval (10 min). Each is one named constant in the module that owns it
(`STALE_SECONDS`, `REPLY_CUT`, `BACKOFF_CAP`, `PERMANENT_ATTEMPTS`,
`REQUEST_LIMIT_SECONDS`, `SELFTEST_INTERVAL`); `poll_seconds` is config.

**Platform and harness facts this plan relies on (checked in Falsify):**
- macOS `/bin/sh` is bash 3.2: no arrays, no `local`, no `[[`; a
  `while … done <<EOF` loop runs in the current shell; `eval "set -- …"`
  with `sq`-quoted words keeps argument order and special characters.
- Python floor 3.9 (the launchd interpreter is `/usr/bin/python3` = 3.9.6;
  `python3` on `PATH` is Homebrew 3.14). Every bridge module starts with
  `from __future__ import annotations`; no `match`, no runtime `X | Y`
  unions, no `datetime.fromisoformat` on `Z` timestamps (3.9 rejects them),
  no `datetime.utcfromtimestamp` (deprecated, warns on 3.12+).
- `tests/assert.sh`: `assert_contains FILE PATTERN MSG` greps a **file**
  (BRE); shell tests write outputs to files first.
- `tests/run_all.sh` runs `tests/*_test.sh` only.

**Project rules (user CLAUDE.md, applied to studio tooling):**
- Decoupled systems: the core never names Multica; the bridge reads the
  core's public files (registry, `events.jsonl`) and calls its public verbs.
  Multica is reached only through `multica_cli.py`.
- Data in data files: deny rules in `multica-deny.txt`, the session context
  in `agent-context.md`, the agent's instructions in `agent-instructions.md`,
  settings in `~/.claude-gamedev/multica/config`.
- Tests first, offline: stub `multica`, `claude`, `claude-gd`,
  `studio-overnight`, `security`, `launchctl`, `osascript`.
- Every `sh` file passes `sh -n` and every entry point is executable.
- Token values never appear in argv, logs, replies, state or a core verb's
  environment.

## Decisions

Rulings where the spec is silent or needs an exact value. They bind the
implementers. Task 1 appends its probe results as D1a–D1g.

- **R1. #27 first.** See Prerequisite. The plan's only core edits are AC1
  and AC1a, both in Task 2.
- **R2. `tests/run_all.sh` does not call `integrations/multica/tests/run.sh`.**
  The milestone gate lists them as separate steps; the core never names
  Multica; deleting `integrations/multica/` must leave the core suite green.
  Every integration task's verify step runs both suites.
- **R3. Test interpreter = the launchd interpreter.** `tests/run.sh` runs the
  Python tests under `/usr/bin/python3` when it reports ≥ 3.9 (3.9.6 here, the
  floor), else `python3`; `OMEGA_MULTICA_TEST_PY` overrides. It runs
  `unittest discover` only when a `test_*.py` exists (3.12+ exits 5 on "no
  tests").
- **R4. Install interpreter default `/usr/bin/python3`.** AC6.1 records the
  real path of the interpreter binary; the Homebrew `python3` resolves into a
  `Cellar/<version>` path that changes on every upgrade and would void the
  file-access grant. `--python <path>` overrides. P6 confirms which path the
  grant must name.
- **R5. `bridge/service.py` holds the poll loop, backoff, self-test, status
  and logging setup;** `bin/multica-bridge` is a thin launcher (the spec's
  Files table names only the entry point; the logic must be importable by
  `unittest`).
- **R6. `bridge/installjson.py`** parses Multica JSON for `install.sh` and
  `uninstall.sh` (sh has no `jq`). One subcommand per question (Task 10).
- **R7. `integrations/multica/agent-instructions.md`** holds AC6.8's agent
  instructions as data; `install.sh` passes its text to `--instructions`.
- **R8. `~/.claude-gamedev/multica/status.json`** (written by `run`/`once`):
  `last_ok_poll`, `cli_version`, `failures`, `outage_since`. `status` reads it;
  the spec's State tree gains this one file.
- **R9. The stub finds its board** in `$STUB_MULTICA_DIR`, else
  `<directory of argv[0] as invoked>/stub-state`. The adapter's fresh
  environment (AC30) carries no test variables, so Python tests put a symlink
  to the stub at `<tmp>/cli/multica` and its board at `<tmp>/cli/stub-state`.
- **R10. `install.sh` flags:** `--workspace-id ID` (required unless the config
  has one), `--server-url URL`, `--roots P1,P2`, `--cli PATH`, `--python
  PATH`, `--daemon-id ID`, `--agent NAME --project PATH` (together),
  `--new-token`, `--poll-seconds N`, `--help`. A re-run keeps every config
  value it is not given.
- **R11. Keychain:** service `omega-multica-bridge`, account `id -un`. An
  existing item is not re-prompted unless `--new-token`.
- **R12. Created issues** are unassigned, unstaged, `--status todo`, with
  `--allow-duplicate` (Run and story issues alike; lookup-before-create is
  the duplicate guard).
- **R13. Lookups by property:** Run issue = `--property omega_run=<key>
  --property omega_story=__none__`; story issue = `--property omega_run=<key>
  --property omega_story=<story>`. P7 checks `__none__`; if it fails, the
  adapter filters the `omega_run` rows client-side by the `properties` map,
  using the property ids from `property list` (fallback F7c).
- **R14. Terminal status** = key `done` or `cancelled`, or `status_category`
  `done`/`closed`. Every other status (including `backlog`, `in_review` and
  custom ones) is non-terminal.
- **R15. Reconcile rules (AC14.4), in order:** repair-stopped → nothing;
  hands-off → nothing; current == intended → success (`last_set` = it);
  current terminal → stop repairing + one note; intended terminal and
  `last_set` == intended (so someone reopened it) → stop repairing + one note;
  a story closure while the Run issue is hands-off → held back; re-read the
  assignee (`issue get`) → hands-off now → nothing; else `issue status <id>
  <intended> --no-start`.
- **R16. Event routing.** Single-plan runs (`run_started.mode == "single"` or
  story `-`): every story-scoped event goes to the Run issue, no prefix;
  `story_state` sets the Run issue's status only for non-terminal states
  (`landed`/`stopped`/`skipped` post their comment only; `run_ended` closes).
  A manifest story whose issue could not be created: its comments go to the
  Run issue prefixed `studio: [<story>] …` and its status changes are not
  applied (the comment carries them).
- **R17. Per-event write progress.** An event's writes are keyed (`create`,
  `status`, `comment`); each success is saved before the next write, so a
  retry repeats only the writes that did not succeed. `run_ended` posts its
  comment before closing the Run issue (closing wakes the agent, which reads
  that comment).
- **R18. Permanent failures** are counted per event offset; the third failing
  poll skips the event with one note on the Run issue: `studio: skipped
  <event> (story <s>) after 3 failed attempts: <error>`.
- **R19. A log that shrank below the saved offset, or a vanished run dir,**
  retires the run with one note on the Run issue (`studio: event log
  replaced or removed — mirroring stopped`).
- **R20. A Run issue that goes missing is not recreated;** its writes follow
  AC27 (log only — the note has nowhere to go).
- **R21. Workdir name → issue.** `<workdir>/..` is named
  `<issue in lower case>-<12 hex>`; the identifier is the part before the
  last `-<12 hex>`, upper-cased (`omeg-4-6d25f8ec1ce3` → `OMEG-4`). The hex
  suffix is not compared with the task id: Multica reuses one workdir for
  every task on an issue (probe log: three tasks in `omeg-4-6d25f8ec1ce3`).
- **R22. The agent for the assignee search** is the link file's `agent=`;
  without it, no search (the runner's environment cannot be read: spec
  References 16).
- **R23. Command text.** CRLF and CR become LF; the command is the first
  non-blank line with leading blanks removed; text is the rest of the comment
  after the word, stripped at both ends, inner newlines kept. Text after
  `/hold`, `/resume`, `/said` and a story `/stop` is ignored, except a
  `/stop` whose first word is `run`.
- **R24. Reply body.** ✓: the verb's stdout; ✗: its stderr; cut to 1000
  characters plus `…` when cut; an empty body becomes `done` (✓) or `exit
  <n>` (✗); a timeout appends `timed out after 30 s`.
- **R25. Every reply goes through the journal** (✓/✗, wrong-place, too old,
  near-miss, ⚠). A re-post first lists the issue's comments since the command
  and skips the post when a comment under the same thread root already holds
  that exact (sanitized) reply — a timed-out post that did apply is not
  doubled.
- **R26. Journal crash cases follow AC23** (spec rev 4 test strategy, spec
  763-766, says the same). The tests pin AC23: crash before the core call → ⚠;
  crash after the core returned but before `result` was saved → ⚠; crash
  after the reply was posted but before `done` → no second reply (R25's check).
- **R27. Core verb calls** exec the configured `studio_overnight` path
  directly with an argument list, `cwd` = the run's root, `stdin` /dev/null,
  `start_new_session=True`, environment = the bridge's minus every
  `MULTICA_*`; on timeout `killpg(SIGKILL)`.
- **R28. `--since`** = (newest seen `created_at` − 60 s), floored to whole
  seconds, UTC `Z`; for a new issue, its `created_at` floored.
- **R29. Backoff.** After k consecutive failed polls the next delay is
  `min(poll_seconds × 2^k, 300)`; success resets it. "Delayed" = first failed
  poll to the next successful poll > 300 s; `<n>` = that span rounded to
  minutes.
- **R30. Notifications** (`osascript -e 'display notification …'`) carry
  fixed text only, once per outage kind (token rejected; Keychain locked or
  item missing; Run issue create failed for `<run>`).
- **R31. Self-test targets:** the `studio_overnight` file (read 1 byte), each
  configured root's `.studio/` (`roots` empty → the roots of the live registry
  entries), and the token (`user profile get` `id` == `operator_member_id`)
  — spec rev 4 AC26 now says exactly this.
  `PermissionError` → kind `file-access`; missing path → `missing`; token →
  `token`; Keychain → `keychain`; transient → `network`.
- **R32. Exit codes.** `once`: 0 after a poll (errors are logged), 1 when the
  lock is held or the config cannot load. `selftest`: 0 ok, 1 not ok.
  `status`: 0. `run`: never returns normally.
- **R33. Daemon choice (AC6.7, spec rev 4).** The CLI cannot name the local
  daemon with the operator's token and an empty `HOME` (`daemon status` reads
  a local profile). `install.sh` takes `runtime list` rows with the profile's
  `profile_id` and `status` `online`; if exactly one daemon serves them it is
  used, if several, `--daemon-id` is required (exit 1 naming the choice). If
  P7's `runtime list` fixture carries a host name field, Task 10 matches it to
  `scutil --get LocalHostName` instead.
- **R34. Re-running `install.sh`.** The lib copy, config and plist are
  rewritten only when their content differs; the agent is booted out and in
  only when the plist changed. Install always deletes `selftest.json` and
  restarts the job (`launchctl kickstart -k`), so the 30 s wait reads a fresh
  self-test.
- **R35. `uninstall.sh`** reads the token and does the `--profiles` bound-agent
  check before removing anything; a refusal leaves the install intact.
- **R36. Probe issues** cannot be archived from CLI 0.6.1 (no `issue
  archive`): cleanup cancels them with `--no-start` and the user archives them
  in the web UI.
- **R37. Wrappers** resolve the repo as `<real bin dir>/../../..` through
  symlinks, source the sibling `bin/wrapper-lib.sh` (not executable; `sh -n`
  checked), and let `deny-rules`' stderr notes through to their stderr.
- **R38. `deny-rules`:** `--dir` that is not a directory, a missing value,
  or any other argument → exit 2. Notes (stderr):
  `studio-overnight: deny-rules: no origin/HEAD in <dir> — rules using {default_branch} dropped`
  and `studio-overnight: deny-rules: no merge_command in <dir>/.studio/config.json — rules using {merge_basename} dropped`.
- **R39. `omega-multica-agent`:** resolves deny rules before any side effect;
  a `MULTICA_TASK_ID` with characters outside `[A-Za-z0-9-]` gets a warning,
  no link file and no `STUDIO_RUN_ORIGIN`; a failure to write `.omega-context.md` exits 1 (the launch
  would fail on the missing file). The context file ends with a line
  `Multica workdir: <workdir>`.
- **R40. Catch-up comment:** `studio: while assigned: <s1> → <s2> …, <n>
  unit events` (`no state changes` when none). Unit events = every comment
  held back on that issue. When the held changes include the run's end, the
  catch-up posts the held `run_ended` comment first, then the catch-up line,
  then sets Done (R17's order: the agent woken by Done reads the comment).
- **R41. Retired runs:** the key is appended to `retired`; the state file
  moves to `state/retired/<key>.json`.
- **R42. CLI call timeout** 60 s (`CLI_TIMEOUT`); a timeout is transient.
- **R43. Commands on hands-off issues** are read (cursor and seen ids
  advance) but never run, so a command posted while an agent was assigned is
  not run later.
- **R44. Config errors.** A missing file, a missing required key, an unknown
  key, a line without `=`, or `poll_seconds` outside 5–300 is a
  `ConfigError` naming the key. `studio_overnight` defaults to
  `<checkout>/studios/game-dev/bin/studio-overnight` only when the bridge runs
  from a checkout; `install.sh` always writes it.
- **R45. launchd `PATH`** = `$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`
  (expanded at install time). The bridge's own CLI calls still use
  `PATH=/usr/bin:/bin` (AC30); the launchd `PATH` only serves the core
  verbs the bridge runs.
- **R46. Test hooks** (environment, read once at import or start; production
  never sets them): `OMEGA_MULTICA_SECURITY` (default `/usr/bin/security`),
  `OMEGA_MULTICA_OSASCRIPT` (`/usr/bin/osascript`),
  `OMEGA_MULTICA_LAUNCHCTL` (`/bin/launchctl`),
  `OMEGA_MULTICA_RUNTIME_WAIT` (60), `OMEGA_MULTICA_SELFTEST_WAIT` (30). The
  stub CLI is chosen by `--cli` / config `cli`, never by a hook.
- **R47. Two deny rules beyond AC5's eight:** `Bash(*MULTICA_TOKEN=*)` (an
  agent setting its own token inline) and `Bash(*multica*--server-url*)` (an
  agent pointing the CLI at another server). Both are in
  `multica-deny.txt`; AC5's list is a floor, not a ceiling.
- **R48. Wrapper symlinks.** `install.sh` creates or replaces
  `~/.local/bin/<wrapper>` only when it is absent or already a symlink into
  an `integrations/multica/bin/` directory; a regular file or a symlink
  elsewhere exits 1 naming it. `uninstall.sh` removes only such symlinks.
- **R49. An agent with the requested name** — active or archived — is not
  created again (AC6.8 "skipped"); an archived one prints `agent <name> is
  archived — unarchive it in Multica or choose another --agent name`.
- **R50. Runtime profile command names** are the bare wrapper names
  (`omega-multica-agent`, `claude-multica`), resolved by the daemon on its
  `PATH`, unless D1a (P1) recorded that the daemon needs an absolute path;
  then `install.sh` passes `$HOME/.local/bin/<name>`.
- **R51. AC1a lives in Task 2** (renamed "Core: `deny-rules` and the
  registry's `origin=` line"), not a task of its own: both are small,
  tool-neutral `studio-overnight` edits with core tests, and one per-task
  Opus review of the only core diff is cheaper than two and sees the whole
  core change at once.
- **R52. How `origin=` survives `--detach`.** `detach_start` unsets every
  `STUDIO_*` variable before it re-execs (read: `studio-overnight`
  `detach_start`, the `env | sed … STUDIO_[A-Za-z0-9_]*` loop), so the
  variable alone would never reach the child's `reg_write`. `cmd_start`
  therefore reads `STUDIO_RUN_ORIGIN` once, first thing, into the shell
  variable `RUN_ORIGIN` (cleared, with the one AC1a warning, when the value
  fails the rule), and unsets the environment variable, so no unit session
  inherits it. `detach_start` passes a valid value to the re-exec'd child
  explicitly (`nohup env ${RUN_ORIGIN:+"STUDIO_RUN_ORIGIN=$RUN_ORIGIN"} perl
  …`, after the strip); the child's `cmd_start` reads it again. An invalid
  value is warned about once, in the foreground, and never passed on.
  `reg_write` adds `origin=<RUN_ORIGIN>` after `started=` when it is
  non-empty; `reg_end` already appends `ended=` and moves the whole file to
  `runs/last`, so the line is kept with no change there.
- **R53. The AC1a value rule** is a function `origin_ok`: no newline, and
  `printf '%s\n' "$v" | LC_ALL=C grep -Eq '^[A-Za-z0-9._:-]{1,200}$'`
  (`LC_ALL=C` so ranges are ASCII and length is bytes). The warning is
  `studio-overnight: STUDIO_RUN_ORIGIN ignored — use 1-200 characters from
  A-Z a-z 0-9 . _ : -` (through `say`, stderr). The help text lists
  `STUDIO_RUN_ORIGIN` under a new `Environment:` heading (not under the
  test hooks, which `--detach` strips).
- **R54. Where the `origin=` tests live.** Single-plan attached runs:
  `tests/overnight_test.sh` (its `fixture`/`run_start`). Manifest runs,
  attached and `--detach`: `tests/overnight_lanes_test.sh`, which owns the
  lanes fixture and every existing `--detach` test (`test_lanes_detach_*`,
  `detach_stop`). Both files already set `HOME=$TMP/home`, so the registry
  is `$HOME/.claude-gamedev/runs`.
- **R55. The bridge's reading of `origin`.** `read_registry` returns the
  entry's `origin` (or `None`); adoption stores it in the run state.
  `request.task` = the text after a leading `multica:` when that text
  matches `[A-Za-z0-9-]+`; any other value (absent, another prefix, a bad
  id) → `request.state = "none"` at adoption (no request issue, AC9).
  `runner_env`, `PS_ENV` and `tests/stub-ps` are not built.
- **R56. P4 runs on stand-ins.** P4 (spec 204-209) needs AC1a and AC3.6,
  which T2 and T3 build after T1. T1's P4 therefore uses the P3 stand-in
  runner (it does what R52 does: read `STUDIO_RUN_ORIGIN`, pass it
  through `nohup env … perl setsid`, write `origin=` if valid) and the P1
  probe wrapper (it exports the variable as AC3.6 will). What P4 proves is
  the part no unit test can: the variable survives Claude Code's Bash
  tool and the daemon's process tree. The real chain is pinned by T2's
  `test_lanes_origin_detach` and the live gate step 4.2 (Final gate,
  manual check 2). Spec 1f2c1b4 adopts this (P4, spec 204-209).
- **D1a. P1 (agent session).** Pending: the operator's run is in progress.
  Default in use: the file-flag form, `--append-system-prompt-file <ctx>` in
  `bin/omega-multica-agent`. If P1 shows the flag is not honoured, the swap is the
  one `eval "set -- ..."` line (the commented inline form) plus one assertion in
  `wrappers_test.sh`. Runtime profiles use the bare command names (R50); if P1
  shows the daemon needs an absolute path, change `command-names.sh`
  (uninstall matches on the basename).
- **D1b. P2 (sub-issue under an agent-assigned issue): pass.** No run starts.
  Side finding: `issue assign --unassign` takes no `--no-start`; the adapter and
  the stub never send the pair.
- **D1c. P3 (detached runner outlives the task).** Pending (the operator's run).
  Default in use: the core's `--detach` re-exec stays as built. A fail goes to
  the user as a spec ruling.
- **D1d. P4 (origin survives the Bash tool and the re-exec).** Pending (the
  operator's run). Default in use: the primary design with the no-origin path as
  the fallback (R55, R56). The live gate step 4.2 checks the real chain.
- **D1e. P5 (Multica.app `~/Documents` prompt).** Not run: the operator's
  projects are under `~/GameDev/proj`, outside `~/Documents`. Default in use:
  `install.sh`'s `P5_TEXT`; the README quotes it (readme_test compares them) and
  documents the caveat.
- **D1f. P6 (launchd python and `~/Documents`).** Not run, same reason. Default
  in use: install records the interpreter's real path (`PY_REAL`, one line in
  `install.sh`) and the self-test reports `file-access` with that path.
- **D1g. P7 (CLI shapes).** All recorded; see spec References 23. Code
  consequences, all built: envelope keys (`has_more`, `issues`, `limit`,
  `offset`, `total`) and bare lists; `properties` keyed by id; `__none__` works
  (no client-side fallback needed); replies nest; `--since` is inclusive
  (de-duplicate by id); `Z` timestamps; exit codes 2, 3, 4, 5 and 1 as in the
  spec; no code path for a host-named runtime key. The fixtures are synthetic,
  written by hand from these shapes (repo is public).
- **D1h.** omega-multica-agent skips a CLAUDE.md that is any symlink or has a link count > 1 and prints a warning (final review M1; defense against copying a credential into the system prompt).

## AC coverage

| AC | Tasks | AC | Tasks |
|----|-------|----|-------|
| 1, 1a | T2 | 16 | T5 (parse), T6 |
| 2 | T3 | 17 | T4 (adapter), T6, T7 |
| 3 | T3 (T1 P1; 3.6 also T1 P4) | 18 | T4 |
| 4 | T3 | 19 | T4 |
| 5 | T3 | 20 | T8 |
| 6 | T10 (T1 P5, P6) | 21 | T5 (call), T8 |
| 7 | T10 | 22 | T8 |
| 8 | T5 (liveness), T6 | 23 | T8 |
| 9 | T2 (`origin=`), T5 (registry `origin`, link), T6 (T1 P4) | 24 | T8 |
| 10 | T6 (T1 P2) | 25 | T8 |
| 11 | T5 (reader), T6 | 26 | T9 |
| 12 | T6 | 27 | T6 (per event), T9 (backoff) |
| 13 | T6 | 28 | T4 (Keychain read), T9 |
| 14 | T7 | 29 | T9 |
| 15 | T6 | 30 | T4 |

Teaching → T11. Open probes → T1. Milestone gate step 4 → Final gate.
Feel targets → T9's end-to-end test (one `once` per event and per command).

## Review Focus

The input classes most likely to bite, most likely first. Each is pinned by a
test in the task that owns the code.

1. **A phone browser's comment:** CRLF line endings, a leading blank line, a
   `/say` whose text holds emoji, CJK and a line starting with `/`. The
   command must parse, and the text reach the core byte-exact. Tests: T8
   `test_command_crlf_and_leading_blank_lines`, `test_unicode_text_roundtrip`.
2. **The event log replaced under the bridge** (run dir removed, or a file
   shorter than the saved offset). The bridge must not replay or skip
   silently. Test: T6 `test_event_log_shrunk_or_vanished_retires`.
3. **Two projects with the same run dir basename.** Run keys differ by the
   root hash, and each verb runs from its own root. Tests: T6
   `test_same_basename_two_roots`, T8 `test_verb_runs_in_its_own_root`.
4. **A runner pid reused by an unrelated process** after the runner died. The
   run must count as gone, not live. Test: T5 `test_pid_reused_by_other_process`.
5. **Server timestamps** with `Z`, `+00:00`, 0–9 fraction digits, and the
   `--since` argument built from them on Python 3.9. Tests: T5
   `test_parse_ts_variants`, T8 `test_since_format`.

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `integrations/multica/probes/lib.sh`, `p1-agent-session.sh` … `p7-fixtures.sh`, `p1-agent-wrapper`, `p1-context.md`, `p3-detach.sh`, `p6_check.py`, `pj.py` | 1 | The open probes, run by hand |
| `integrations/multica/tests/fixtures/cli/*.json`, `fixtures/cli/errors/*.txt` | 1 | Recorded (redacted) CLI output the stub and adapter are pinned to |
| `docs/game-dev/specs/2026-10-03-multica-integration.md` (References) | 1 | Probe results 17–23 |
| `studios/game-dev/bin/studio-overnight` | 2 | `deny-rules [--dir]` verb; `deny_rules` drops empty-`{default_branch}` lines; `origin=` registry line (`origin_ok`, `RUN_ORIGIN`, `reg_write`, `detach_start`); help |
| `tests/overnight_test.sh` | 2 | `deny-rules` cases; single-plan `origin=` cases |
| `tests/overnight_lanes_test.sh` | 2 | Manifest `origin=` cases, attached and `--detach` |
| `docs/game-dev/overnight-events.md` | 2 | Lists `deny-rules` with the verbs; documents the registry's `origin=` line |
| `integrations/multica/bin/claude-multica` | 3 | Mode 2 wrapper |
| `integrations/multica/bin/omega-multica-agent` | 3 | Mode 3 wrapper |
| `integrations/multica/bin/wrapper-lib.sh` | 3 | Shared wrapper functions (repo paths, `deny_list`, `deny_words`, `die`) |
| `integrations/multica/multica-deny.txt` | 3 | Credential and identity deny rules |
| `integrations/multica/agent-context.md` | 3 | Context appended to mode-3 sessions |
| `integrations/multica/tests/run.sh` | 3 | The integration gate |
| `integrations/multica/tests/wrappers_test.sh` | 3 | Wrapper and probe-script cases |
| `integrations/multica/tests/stub-multica` | 4 | Offline CLI with a fake board, call log, fault injection |
| `integrations/multica/tests/stub-security` | 4 (grows 10) | Keychain stand-in |
| `integrations/multica/bridge/__init__.py` | 4 | Package marker |
| `integrations/multica/bridge/config.py` | 4 | Config parsing and validation |
| `integrations/multica/bridge/multica_cli.py` | 4 | The only CLI caller: env, sanitizer, prefix, error classes, Keychain read |
| `integrations/multica/tests/bridgetest.py` | 4 (grows 5-6) | Shared test fixtures (temp HOME, board, runs, stubs) |
| `integrations/multica/tests/test_cli.py`, `test_config.py` | 4 | Adapter, sanitizer, classifier, stub conformance |
| `integrations/multica/bridge/state.py` | 5 | Paths, per-run state, atomic writes, retired keys, timestamps |
| `integrations/multica/bridge/studio.py` | 5 | Registry (with `origin`), liveness, link files, event reader, core verb calls |
| `integrations/multica/tests/stub-studio-overnight` | 5 | Verb stand-in |
| `integrations/multica/tests/test_state.py`, `test_studio.py` | 5 | |
| `integrations/multica/bridge/mirror.py` | 6, 7 | Adoption, request issue, Run/story issues, event mapping; intended status, hands-off, repair |
| `integrations/multica/tests/test_mirror_runs.py` | 6 | |
| `integrations/multica/tests/test_mirror_status.py` | 7 | |
| `integrations/multica/bridge/commands.py` | 8 | Cursor, author filter, parsing, journal, replies |
| `integrations/multica/tests/test_commands.py` | 8 | |
| `integrations/multica/bridge/service.py` | 9 | Poll loop, lock, backoff, auth, self-test, status, logging |
| `integrations/multica/bin/multica-bridge` | 9 | Entry point `run`/`once`/`selftest`/`status` |
| `integrations/multica/tests/test_service.py`, `test_end_to_end.py` | 9 | |
| `integrations/multica/bridge/installjson.py` | 10 | JSON questions for install/uninstall |
| `integrations/multica/install.sh`, `uninstall.sh` | 10 | AC6, AC7 |
| `integrations/multica/agent-instructions.md` | 10 | AC6.8 instructions |
| `integrations/multica/launchd/ai.omega.multica-bridge.plist.in` | 10 | The launchd template |
| `integrations/multica/tests/install_test.sh`, `test_installjson.py`, `stub-launchctl` | 10 | Install/uninstall cases; launchctl stand-in that runs the real self-test |
| `integrations/multica/README.md`, `tests/readme_test.sh` | 11 | Teaching and its contract |

**Order:** T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11, serial.
T1 must be first (gate step 3) and feeds T4's fixtures. T3 needs T2's verb.
T5–T10 need T4's stub and adapter. T7 and T8 need T6's issue map. T9 needs
T6–T8. T10 needs T3 (wrappers) and T9 (self-test). T11 documents T10's flags.

---

### Task 1: Open probes P1–P7 and the recorded CLI fixtures
Files: integrations/multica/probes/lib.sh, integrations/multica/probes/pj.py, integrations/multica/probes/p1-agent-session.sh, integrations/multica/probes/p1-agent-wrapper, integrations/multica/probes/p1-context.md, integrations/multica/probes/p2-subissue.sh, integrations/multica/probes/p3-detach.sh, integrations/multica/probes/p34-detach-env.sh, integrations/multica/probes/p5-documents.sh, integrations/multica/probes/p6-launchd.sh, integrations/multica/probes/p6_check.py, integrations/multica/probes/p7-fixtures.sh, integrations/multica/tests/fixtures/cli/*.json, integrations/multica/tests/fixtures/cli/errors/*, docs/game-dev/specs/2026-10-03-multica-integration.md (References, after item 16 at :185-188), docs/game-dev/plans/2026-10-03-multica-integration.md (## Decisions only)
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L195-217, docs/game-dev/specs/2026-10-03-multica-integration.md:L123-193, docs/game-dev/specs/2026-10-03-multica-integration.md:L37-40
Review: final

Deliverable: seven probe results, recorded before any bridge code exists
(gate step 3). The implementer writes the scripts; **the user or the
controller runs them by hand** in Terminal.app (not in a Claude session:
they write to the real workspace, and P1–P4 spend model calls on it).
Each result becomes a numbered References item (17–23) in
the spec and a D1a–D1g paragraph under `## Decisions` here: what was run,
what was seen (exit codes, field names, identifiers), and which path the
later tasks take.

**A failed probe stops the plan.** The controller takes the result and the
fallback below to the user for a spec ruling; later tasks start only after
that ruling is folded into the spec and this plan.

**Reusable workspace artifacts** (from the feasibility probes; never
recreated): agent `gd-probe`; a probe custom runtime profile (its id is
passed as `MULTICA_PROBE_RUNTIME_PROFILE`); issues OMEG-2..OMEG-9 (OMEG-4
holds three past runs); properties `omega_run`, `omega_story` (they stay
for the product). New probe issues are titled `[probe] …` and listed in
`~/.claude-gamedev/multica/probes/cleanup.txt` for the Final gate cleanup.

**Security rules for every probe script:** the CLI is always called as
`"$M" --profile "$PROFILE" --workspace-id "$WS" …` (the CLI reads its own
profile); no script reads, copies or prints any file under `~/.multica/`,
any token, or any `MULTICA_TOKEN` value; error captures pass through
`redact` (below) before they are written.

**`probes/lib.sh`** (sourced by every probe; full code):

```sh
# lib.sh — shared by the #28 open probes. Sourced, never executed.
M="${MULTICA_CLI:-/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica}"
PROFILE="${MULTICA_PROBE_PROFILE:-desktop-api.multica.ai}"
WS="${MULTICA_PROBE_WORKSPACE:?set MULTICA_PROBE_WORKSPACE to your workspace id}"
SERVER="${MULTICA_PROBE_SERVER:-https://api.multica.ai}"
PROBE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RES="${MULTICA_PROBE_RESULTS:-$HOME/.claude-gamedev/multica/probes}"
mkdir -p "$RES"
mc() { "$M" --profile "$PROFILE" --workspace-id "$WS" "$@"; }
pj() { /usr/bin/python3 "$PROBE_DIR/pj.py" "$@"; }
# redact — token-shaped strings and e-mail addresses out of stdin.
redact() { sed -E 's/(mul|mat)_[A-Za-z0-9_-]+/<token>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+/operator@example.com/g'; }
record() {
  printf '%s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$RES/results.txt"
  printf '%s: %s\n' "$1" "$2"
}
cleanup_add() { printf '%s %s\n' "$1" "$2" >> "$RES/cleanup.txt"; }   # KIND ID
confirm() { printf '%s [y/N] ' "$1"; read -r _a; [ "$_a" = y ]; }
# wait_idle ISSUE MAX_SECONDS — until `issue runs --active` lists nothing.
wait_idle() {
  _wi=0
  while [ "$_wi" -lt "$2" ]; do
    [ "$(mc issue runs "$1" --active --output json | pj count)" = 0 ] && return 0
    sleep 10; _wi=$((_wi + 10))
  done
  return 1
}
```

**`probes/pj.py`** (3.9 standard library; full contract): reads JSON on
stdin. `get PATH` prints the value at a dotted path (`identifier`,
`0.id`, `issues.0.id`; a dict or list prints as JSON), exit 1 when absent.
`count` prints the number of rows (a list, or the first list value of an
envelope object). `rows FIELD` prints FIELD of each row, one per line.
`keys` prints the top-level keys (or `<list>`). `redact` prints the JSON
with every string matching `(mul|mat)_[A-Za-z0-9_-]+` replaced by
`<token>`, every `email` value by `operator@example.com`, every
`custom_env` value by `{}` and every `avatar_url` by `""`.
`find FIELD VALUE OUTFIELD` prints OUTFIELD of the first row whose FIELD
equals VALUE.

**The probes** (each: script → action → expected → fallback if it fails):

- **P7 fixtures** (`p7-fixtures.sh`, run first; writes to the real board,
  only `[probe]` issues).
  - Action: into `$RES/fixtures/` (every file through `redact` or
    `pj redact`):
    - `version.json` (`"$M" version --output json`), `user-profile.json`;
    - `issue-create-run.json`: a top-level `[probe] fixture run` with
      `--status todo --property omega_run=probe-fixture --allow-duplicate
      --description-stdin`; `issue-create-story.json`: `[probe] fixture S1`
      under it with `--property omega_run=probe-fixture --property
      omega_story=S1`;
    - `issue-get.json` (the story); `issue-list-run.json` (`--property
      omega_run=probe-fixture --limit 100`); `issue-list-none.json` (adds
      `--property omega_story=__none__`); `issue-list-page.json`
      (`--limit 1`, to see `has_more`); `issue-list-assignee.json`
      (`--assignee-id <gd-probe id> --sort created_at --direction desc
      --limit 20`);
    - on the run issue (unassigned, so no run starts — References 10):
      `comment-add.json` (`issue comment add --content-stdin`, text
      `studio: probe fixture root`), `comment-reply.json` (`--parent
      <root>`), `comment-reply2.json` (`--parent <reply>`),
      `comment-list.json`, `comment-list-since.json` (`--since` = the
      root's `created_at`);
    - `issue-runs.json` (`issue runs OMEG-4 --output json`);
      `issue-status.json` (story → `in_progress` with `--no-start`);
    - `runtime-list.json`, `runtime-profile-list.json`, `agent-list.json`,
      `property-list.json` (`--include-archived`), `daemon-status.json`;
    - `errors/<name>.txt` (stderr) and `errors/<name>.exit` for:
      `not-found` (`issue get OMEG-999999`); `unauthorized` (`env -i
      PATH=/usr/bin:/bin HOME=<empty dir> MULTICA_TOKEN=mul_probe_bogus
      MULTICA_SERVER_URL=$SERVER MULTICA_WORKSPACE_ID=$WS "$M" issue get
      OMEG-2 --output json`); `no-token` (the same without
      `MULTICA_TOKEN`); `unreachable` (the same with
      `MULTICA_SERVER_URL=http://127.0.0.1:9`); `duplicate` (create
      `[probe] fixture run` again, top level, without `--allow-duplicate`;
      if it succeeds the new identifier goes to `cleanup.txt` and the
      result says so); `bad-status` (`issue status <story> nosuch
      --no-start`).
    - Both fixture issues are then set `cancelled` with `--no-start` and
      listed in `cleanup.txt`.
  - Records: `P7a runs fields` (the keys of an `issue-runs.json` row; pass
    = `id`, `started_at`, `completed_at` present); `P7b reply nesting`
    (`nested` when reply2's `parent_id` is the reply, `flattened` when it
    is the root); `P7c none filter` (pass = `issue-list-none.json` holds
    exactly the run issue); `P7d timestamp form` (one `created_at` value
    verbatim); `P7e since` (`strict` when the root is absent from
    `comment-list-since.json`, else `inclusive`); `P7f list envelope`
    (`pj keys` of the list outputs); `P7g runtime rows` (keys of a
    `runtime-list.json` row, and whether any field names the host);
    `P7h error texts` (first line and exit of each `errors/*`).
  - Fallbacks: P7c fails → R13's client-side filter (T4 `find_issues`
    filters `omega_run` rows by the `properties` map, using the ids from
    `property list`). Nested or flattened replies → no code
    change: a reply goes under the command's `parent_id` (else the
    command), AC22's rule, a valid place either way; the stub follows
    D1g. `inclusive` since → no change (de-duplication
    by id). Envelope or field names differ → T4's stub and adapter use
    the recorded names (D1g lists them). Missing `started_at` /
    `completed_at` → P3 compares the heartbeat with the time `wait_idle`
    saw the run leave `running` instead; recorded in D1g.
  - Then the controller copies `$RES/fixtures/` into
    `integrations/multica/tests/fixtures/cli/` after checking
    `grep -rEl '(mul|mat)_[A-Za-z0-9]' integrations/multica/tests/fixtures/cli`
    prints nothing and every `email` reads `operator@example.com`.
- **P2 sub-issue creation** (`p2-subissue.sh`).
  - Action: create `[probe] P2 parent` assigned to `gd-probe`
    (`--assignee-id`), description "Reply `ok` and finish. Do nothing
    else." While its run is active (`issue runs --active` count 1), create
    `[probe] P2 child A` under it (`--status todo`, unassigned, no
    `--stage`). `wait_idle` (10 min), then note the run count N; create
    `[probe] P2 child B` the same way; wait 120 s; read the run count and
    the active list again.
  - Expected: the count is still N and nothing is active; the parent's
    runs list no row whose trigger names a sub-issue.
  - Then: `issue assign <parent> --unassign --no-start` (so cleanup's
    closing of the children cannot wake it), and all three go to
    `cleanup.txt`.
  - Fallback (fail): the Run issue is created top-level with the request
    identifier in its description, and the summary wakeup is dropped
    (T6 `ensure_run_issue`, T10 `agent-instructions.md`, T11 README) —
    needs a spec ruling (operator ruling of revision 3 changes).
- **P1 agent session** (`p1-agent-session.sh`, `p1-agent-wrapper`,
  `p1-context.md`).
  - Setup by the script: a throwaway project `$HOME/omega-probe-p1`
    (outside `~/Documents`: `git init`, `studio-state init`, one commit);
    copies `p1-agent-wrapper` to `~/.local/bin/omega-probe-agent` (a copy,
    so it is outside `~/Documents`); `runtime profile update
    $MULTICA_PROBE_RUNTIME_PROFILE --command-name omega-probe-agent`;
    `agent env set <gd-probe> --custom-env-stdin` with
    `{"OMEGA_PROJECT": "$HOME/omega-probe-p1"}`; waits 30 s for the
    daemon's profile refresh.
  - `p1-agent-wrapper` mimics AC3: `--version` → `claude-gd --version`;
    records its argv and cwd (never env) in `$RES/p1-calls.log`; mimics
    AC3.6: when `MULTICA_TASK_ID` is set, exports
    `STUDIO_RUN_ORIGIN=multica:$MULTICA_TASK_ID` (used by P4); writes
    `<workdir>/.omega-context.md` = `<workdir>/CLAUDE.md` + `p1-context.md`
    (installed beside it as `~/.local/bin/omega-probe-context.md`); `cd
    "$OMEGA_PROJECT"`; `exec claude-gd --disallowedTools
    'Read(~/.multica/**)' --append-system-prompt-file <ctx> --add-dir
    <workdir> "$@"`. `p1-context.md` holds the AC3.5 text (as T3's
    `agent-context.md` will) plus the canary rule "Start every comment
    you post with `CANARY-7Q`".
  - Action: create `[probe] P1 session` assigned to `gd-probe`:
    "Run `pwd` and `git status --porcelain`. Write both outputs to a file
    under your Multica workdir and post it with `multica issue comment
    add <this issue> --content-file <file> --allow-external-file`. Then
    finish." `wait_idle` (15 min).
  - Expected (recorded one by one): an agent comment starting
    `CANARY-7Q` (the appended context was read); a comment whose `pwd` is
    `$HOME/omega-probe-p1` (cwd is the project); `git -C
    $HOME/omega-probe-p1 status --porcelain` empty (project left clean);
    the comment posted through `--content-file` (Multica's workflow
    followed); the daemon's final agent comment present (References 5).
  - Fallback: canary missing → `omega-multica-agent` passes the context
    inline with `--append-system-prompt "<text>"` (T3; AC3.7 names the
    file flag, so a spec ruling). Project dirty or workflow ignored →
    `agent-context.md` gets the missing rule spelled out (T3) and P1 is
    re-run once; still failing → spec ruling.
- **P3 + P4 detach, and the run's origin** (`p3-detach.sh`,
  `p34-detach-env.sh`). P4 is folded into P3's run (spec rev 4).
  - `p3-detach.sh launch` (copied by the driver to `$RES/p3/`, outside
    `~/Documents`) is a stand-in runner. It reads `STUDIO_RUN_ORIGIN` before
    anything else (as `cmd_start` does, R52), then starts itself as the
    child the same way `studio-overnight --detach` does, passing the value
    explicitly through the strip: `nohup env
    ${_o:+"STUDIO_RUN_ORIGIN=$_o"} perl -MPOSIX -e 'POSIX::setsid(); exec
    @ARGV' sh "$RES/p3/p3-detach.sh" child </dev/null
    >>"$RES/p3/heartbeat.log" 2>&1 &`, writes `$!` to `$RES/p3/pid`,
    prints `launched <pid>`. `child` writes its own registry-form entry
    `$RES/p3/registry-entry` (`root=`, `run=`, `pid=`, `started=` and, when
    the value passes AC1a's rule — `origin_ok`, R53, copied into the
    script — `origin=<value>`; this file is never under
    `~/.claude-gamedev/runs/`, so no bridge or `status` sees it), then
    appends `date -u +%s` every 10 s for 15 minutes.
  - Action (driver, in Terminal.app): checks the P1 wrapper is still the
    `gd-probe` runtime's command (P1 setup), creates `[probe] P3 detach`
    assigned to `gd-probe` ("Run exactly `sh $RES/p3/p3-detach.sh
    launch`, post its output, then finish"), `wait_idle`, records the
    run's `id` and `completed_at` (from `issue runs`), waits 60 s.
  - Expected: P3 — `kill -0 $(cat pid)` succeeds and `heartbeat.log` has
    lines later than `completed_at`. P4 — `registry-entry` has the line
    `origin=multica:<that run's id>` (the variable the wrapper exported
    survived Claude Code's Bash tool and the detach re-exec).
  - Then the driver kills the child.
  - What P4 does not cover, and where it is covered: the real
    `studio-overnight start --detach` carrying the value into the real
    registry is core code pinned by T2's `test_lanes_origin_detach`; the
    whole chain (`omega-multica-agent` → agent → `start --detach` →
    registry → bridge) is the live gate step 4.2 (Final gate, manual
    check 2).
  - Fallback P3: the game-dev agent posts the exact start command for the
    operator, or starts it through `launchctl submit` (spec ruling; T10
    instructions, T11 README). Fallback P4 (no `origin=` line, or another
    task id): runs started by agents get no request issue — the Run issue
    is top level, AC9's existing path, no code change — and the result
    goes to the user for a spec ruling (gate step 3) before T5.
- **P5 Multica.app and `~/Documents`** (`p5-documents.sh`, interactive).
  - Setup: project `$HOME/Documents/omega-probe-p5` (git, `studio-state
    init`); a wrapper copy at `$HOME/Documents/omega-probe-p5/.probe/omega-probe-agent`
    with `~/.local/bin/omega-probe-agent` re-pointed as a symlink to it
    (the real wrappers are symlinks into the repo under `~/Documents`, so
    the daemon's `--version` check reads a `~/Documents` file too); agent
    env `OMEGA_PROJECT` → the P5 project. If System Settings → Privacy &
    Security → Files and Folders already lists Multica with Documents
    access, the script says so and asks whether the user wants to reset
    it for the observation (`tccutil reset SystemPolicyDocumentsFolder
    <bundle id>` — the user's call; skipped otherwise).
  - Action: `runtime list` (is the probe runtime online after the
    change?); create `[probe] P5 documents` assigned to `gd-probe` ("Run
    `ls` and `git status --porcelain`, post the output"). The user
    watches for a prompt; `confirm` asks what it named (Multica.app, the
    daemon binary, `sh`, `claude`); after granting, `issue rerun` and
    `wait_idle`.
  - Expected: one prompt naming Multica.app; the runtime stays online;
    after the grant the run posts the listing.
  - Fallback: the prompt names another binary → install's final text and
    the README name that binary (T10, T11); nothing grantable → the README
    tells users to keep projects outside `~/Documents` and install warns
    when a root is under it (T10, T11; spec ruling).
- **P6 launchd python** (`p6-launchd.sh`, `p6_check.py`).
  - `p6_check.py <project>` (copied to `$RES/p6/`) writes
    `$RES/p6/out-<label>.json`: `ok`, `error`, `sys.executable`,
    `os.path.realpath(sys.executable)`; it lists `<project>/.studio`.
  - Action: for label `shim` (`/usr/bin/python3`) and label `real` (the
    real path `/usr/bin/python3` reports), write
    `~/Library/LaunchAgents/ai.omega.multica-probe-p6.plist` running
    `<python> $RES/p6/p6_check.py $HOME/Documents/omega-probe-p5`,
    `launchctl bootstrap gui/$(id -u)`, wait 10 s, `launchctl bootout`,
    read the output. Before any grant, then after the user grants the
    path the prompt or the Files and Folders pane names, then again.
  - Expected: before — `ok: false` with `Operation not permitted`, and
    the script itself ran (code outside `~/Documents` loads without a
    grant); after — `ok: true`.
  - Fallback: the grant only sticks for one of the two paths → R4's
    default and AC6.10's printed path use that one (T10, R4 amended);
    neither works without Full Disk Access → install and the README name
    Full Disk Access (T10, T11); nothing works → spec ruling.

**Run order:** P7, P2, P1, P3/P4, P5, P6 (P7 needs no agent run; P2 before
P1 so a surprise wakeup is seen on a plain issue; P5 and P6 change system
grants last).

- [ ] **Step 1: Write the scripts.** All of the above into
  `integrations/multica/probes/` (`chmod 755` the `.sh` files and
  `p1-agent-wrapper`). Each script starts with a comment naming its probe,
  that it is run by hand, and what it writes to the real workspace.
- [ ] **Step 2: Check they parse.**
  Run: `for f in integrations/multica/probes/*.sh integrations/multica/probes/p1-agent-wrapper; do sh -n "$f" || echo "BAD $f"; done; /usr/bin/python3 -m py_compile integrations/multica/probes/pj.py integrations/multica/probes/p6_check.py && echo ok`
  Expected: `ok`, no `BAD` line. (`py_compile` writes `__pycache__`;
  delete it before committing.)
- [ ] **Step 3: Hand the run to the controller.** The controller gives the
  user the run order and the one-time inputs
  (`MULTICA_PROBE_RUNTIME_PROFILE`, the `gd-probe` agent id from `agent
  list`), then reads `$RES/results.txt` and each probe's output.
- [ ] **Step 4: Record.** Append References items 17–23 (P1…P7, one each:
  date, what was run, the observation) after item 16 of the spec, and
  D1a (P1) … D1g (P7) under `## Decisions` in this plan, each naming the
  path taken (pass, or the fallback and its ruling). Copy the redacted
  fixtures into `integrations/multica/tests/fixtures/cli/` (with
  `errors/`).
  Where the results are recorded (final fix wave, 2026-10-04): the spec's last
  section, "References (continued): open probe results 17-23", holds the P7 and P2
  outcomes and marks P1, P3, P4 pending (operator run in progress) and P5, P6 not
  run (the operator's projects are outside `~/Documents`). D1a-D1g, with the
  defaults in use, are at the end of `## Decisions` above. No cited spec line
  moved: the new section is appended after the last one.
- [ ] **Step 5: Gate.** Any failed probe: stop; the controller takes the
  result and its fallback to the user. Continue only on all-pass, or
  after the ruling is folded into the spec and this plan.
- [ ] **Step 6: Commit.**

```bash
git add integrations/multica/probes integrations/multica/tests/fixtures \
  docs/game-dev/specs/2026-10-03-multica-integration.md \
  docs/game-dev/plans/2026-10-03-multica-integration.md
git commit -m "test(multica): open probes P1-P7, results and CLI fixtures (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 2: Core — `studio-overnight deny-rules [--dir]` and the registry's `origin=` line
Files: studios/game-dev/bin/studio-overnight (`deny_rules` at :76-84 — `grep -n '^deny_rules()'`; `usage` at :136-250 — `grep -n '^usage()'`; `reg_write` at :576-584 — `grep -n '^reg_write()'`; `detach_start` at :784-846 — `grep -n '^detach_start()'`; `cmd_start` at :849 — `grep -n '^cmd_start()'`; final dispatch at :1089-1121 — `grep -n '^case "\$1" in'`), tests/overnight_test.sh (help test at :110-123; `run_tests` list at :669-688), tests/overnight_lanes_test.sh (`detach_stop` at :1827 — `grep -n '^detach_stop()'`; `run_tests` list at :2069-2096), docs/game-dev/overnight-events.md (the verbs section; the registry paragraph)
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L242-262, docs/game-dev/specs/2026-10-03-multica-integration.md:L712-718, docs/game-dev/specs/2026-10-03-multica-integration.md:L553-557
Review: task

**Interfaces:**
- Consumes: `DENY_FILE`, `STATE_BIN`, `say`, `cfg_str`, `sub_escape`,
  `deny_rules`, `usage` (all in `studio-overnight`, pre-dispatch).
- Produces: `studio-overnight deny-rules [--dir <path>]` — stdout one rule
  per line (file order, placeholders expanded); stderr notes (R38 text);
  exit 0 / 1 (missing or rule-less deny file) / 2 (usage, non-directory).
  T3's wrappers call it as `sh <studio-overnight> deny-rules --dir <dir>`.
- Produces (AC1a, R52–R54): `start` (every mode) reads
  `STUDIO_RUN_ORIGIN`; the registry entry `~/.claude-gamedev/runs/<run
  dir>-<pid>` gains `origin=<value>` after `started=` when the value is
  valid; `runs/last` keeps it. Shell functions `origin_ok VALUE` and
  `origin_take`; shell variable `RUN_ORIGIN`. T5's `read_registry` reads
  the line; T3's `omega-multica-agent` sets the variable.

- [ ] **Step 1: Write the failing tests** in `tests/overnight_test.sh`
  (after `test_overnight_deny_merge_basename`), and add them to the
  `run_tests` list:

```sh
# dr DIR [ARGS] — deny-rules from DIR; stdout dr.out, stderr dr.err, exit DR_STATUS.
dr() {
  _d="$1"; shift; DR_STATUS=0
  ( cd "$_d" && sh "$RUNNER" deny-rules "$@" ) > "$TMP/dr.out" 2> "$TMP/dr.err" || DR_STATUS=$?
}
DENY_SRC="$REPO_ROOT/studios/game-dev/bin/overnight-deny.txt"
test_overnight_deny_rules_basic() {
  fixture drb '{"merge_command": "scripts/merge.sh <pr>"}'
  dr "$P"
  assert_eq 0 "$DR_STATUS" "deny-rules exits 0 in a project"
  assert_eq "$(grep -Evc '^[[:space:]]*(#|$)' "$DENY_SRC")" "$(grep -c . "$TMP/dr.out")" "every rule printed once"
  assert_contains "$TMP/dr.out" '^Bash(git push \* main)$' "{default_branch} expanded from origin/HEAD"
  assert_contains "$TMP/dr.out" '^Bash(\*merge\.sh\*)$' "{merge_basename} is the first word's basename"
  assert_not_contains "$TMP/dr.out" '{' "no placeholder left"
  assert_eq "" "$(cat "$TMP/dr.err")" "no notes when both values exist"
}
test_overnight_deny_rules_no_origin_head() {
  fixture drh; git -C "$P" remote set-head origin -d >/dev/null 2>&1
  dr "$P"
  assert_eq 0 "$DR_STATUS" "no origin/HEAD still exits 0"
  assert_not_contains "$TMP/dr.out" 'git push \* {default_branch}' "no raw placeholder"
  assert_not_contains "$TMP/dr.out" '^Bash(git push \* )$' "no rule with an empty branch"
  assert_eq "$(grep -v '^#' "$DENY_SRC" | grep . | grep -v '{default_branch}' | grep -vc '{merge_basename}')" \
    "$(grep -c . "$TMP/dr.out")" "only placeholder-free rules remain"
  assert_contains "$TMP/dr.err" 'deny-rules: no origin/HEAD in .* rules using {default_branch} dropped' "one note for {default_branch}"
  assert_contains "$TMP/dr.err" 'rules using {merge_basename} dropped' "one note for {merge_basename}"
  assert_eq 2 "$(grep -c . "$TMP/dr.err")" "exactly one note per dropped placeholder"
}
test_overnight_deny_rules_merge_basename() {
  fixture drm
  dr "$P"
  assert_eq 0 "$DR_STATUS" "no merge_command still exits 0"
  assert_eq "$(grep -v '^#' "$DENY_SRC" | grep . | grep -vc '{merge_basename}')" \
    "$(grep -c . "$TMP/dr.out")" "only the {merge_basename} rule is dropped"
  assert_contains "$TMP/dr.err" 'no merge_command in .*config.json .* rules using {merge_basename} dropped' "one note naming the config"
  assert_eq 1 "$(grep -c . "$TMP/dr.err")" "no {default_branch} note when origin/HEAD is set"
}
test_overnight_deny_rules_dir() {
  fixture drd; mkdir -p "$TMP/elsewhere"
  dr "$TMP/elsewhere" --dir "$P"
  assert_eq 0 "$DR_STATUS" "--dir works from another directory"
  assert_contains "$TMP/dr.out" '^Bash(git push \* main)$' "values come from --dir, not the cwd"
  dr "$TMP/elsewhere" --dir="$P/docs"
  assert_contains "$TMP/dr.out" '^Bash(git push \* main)$' "--dir=PATH form, a subdirectory resolves to the work root"
}
test_overnight_deny_rules_outside_git() {
  mkdir -p "$TMP/plain"
  dr "$TMP/plain"
  assert_eq 0 "$DR_STATUS" "outside git and outside a studio project: exit 0"
  assert_eq 2 "$(grep -c . "$TMP/dr.err")" "two notes"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -e "$TMP/plain/.studio" ]; then _fail "deny-rules writes nothing"; else _pass "deny-rules writes nothing"; fi
}
test_overnight_deny_rules_empty_file() {
  mkdir -p "$TMP/drcopy"; cp -R "$REPO_ROOT/studios/game-dev/bin/." "$TMP/drcopy/"
  printf '# only a comment\n\n' > "$TMP/drcopy/overnight-deny.txt"
  st=0; ( cd "$TMP" && sh "$TMP/drcopy/studio-overnight" deny-rules ) >/dev/null 2>"$TMP/dr.err" || st=$?
  assert_eq 1 "$st" "a deny file with no rules exits 1"
  rm -f "$TMP/drcopy/overnight-deny.txt"
  st=0; ( cd "$TMP" && sh "$TMP/drcopy/studio-overnight" deny-rules ) >/dev/null 2>&1 || st=$?
  assert_eq 1 "$st" "a missing deny file exits 1"
}
test_overnight_deny_rules_usage() {
  fixture dru
  dr "$P" --bogus;            assert_eq 2 "$DR_STATUS" "an unknown argument exits 2"
  dr "$P" --dir;              assert_eq 2 "$DR_STATUS" "--dir without a value exits 2"
  dr "$P" --dir "$TMP/nope";  assert_eq 2 "$DR_STATUS" "--dir that is not a directory exits 2"
}
test_overnight_deny_rules_match_launch() {
  fixture drl; done_scenario; run_start
  awk 'p { print; p = 0 } /^--disallowedTools$/ { p = 1 }' "$CALLS/1.argv" > "$TMP/launch-rules.txt"
  dr "$P"
  assert_eq "$(cat "$TMP/launch-rules.txt")" "$(cat "$TMP/dr.out")" "deny-rules prints exactly the unit's rules"
}
```

  AC1a, single-plan (same file, same `run_tests` list):

```sh
REGL="$HOME/.claude-gamedev/runs/last"
# reg_keys FILE — the entry's keys in order, space-separated.
reg_keys() { sed 's/=.*//' "$1" | tr '\n' ' ' | sed 's/ $//'; }
test_overnight_origin_written() {
  fixture org; done_scenario; rm -f "$REGL"
  STUDIO_RUN_ORIGIN="multica:0b5f-12ab"; export STUDIO_RUN_ORIGIN
  run_start; unset STUDIO_RUN_ORIGIN
  assert_eq 0 "$RS_STATUS" "the run ends normally"
  assert_contains "$REGL" '^origin=multica:0b5f-12ab$' "origin= written and kept in runs/last"
  assert_eq "root start run pid started origin ended" "$(reg_keys "$REGL")" "origin= follows started=, ended= is last"
  assert_not_contains "$RS_ERR" 'STUDIO_RUN_ORIGIN ignored' "a valid value draws no warning"
}
test_overnight_origin_absent_without_variable() {
  fixture orn; done_scenario; rm -f "$REGL"; unset STUDIO_RUN_ORIGIN
  run_start
  assert_eq "root start run pid started ended" "$(reg_keys "$REGL")" "without the variable the entry is unchanged"
  STUDIO_RUN_ORIGIN=""; export STUDIO_RUN_ORIGIN
  fixture ore; done_scenario; rm -f "$REGL"; run_start; unset STUDIO_RUN_ORIGIN
  assert_not_contains "$REGL" '^origin=' "an empty variable writes no line"
  assert_not_contains "$RS_ERR" 'STUDIO_RUN_ORIGIN' "and no warning"
}
test_overnight_origin_refused() {
  long="$(printf '%0201d' 0 | tr 0 a)"; i=0
  for v in "has space" "a/b" "a
b" "$long" "héllo"; do
    i=$((i + 1)); fixture "orr$i"; done_scenario; rm -f "$REGL"
    STUDIO_RUN_ORIGIN="$v"; export STUDIO_RUN_ORIGIN; run_start; unset STUDIO_RUN_ORIGIN
    assert_eq 0 "$RS_STATUS" "a refused origin still runs ($i)"
    assert_not_contains "$REGL" '^origin=' "no origin= line ($i)"
    assert_eq 1 "$(grep -c 'STUDIO_RUN_ORIGIN ignored' "$RS_ERR")" "exactly one warning ($i)"
  done
  fixture or200; done_scenario; rm -f "$REGL"
  STUDIO_RUN_ORIGIN="${long%a}"; export STUDIO_RUN_ORIGIN; run_start; unset STUDIO_RUN_ORIGIN
  assert_contains "$REGL" "^origin=${long%a}$" "200 bytes is accepted"
}
```

  AC1a, manifest mode, attached and `--detach` — in
  `tests/overnight_lanes_test.sh` after `test_lanes_detach_timeout_no_lock_ends_child`
  and in its `run_tests` list (R54; `REG` is set at :1913 — move that line
  above the new tests if they come first in the file):

```sh
test_lanes_origin_attached() {
  lanes_fixture ora integration A:-
  rm -f "$HOME/.claude-gamedev/runs/last"
  STUDIO_RUN_ORIGIN="multica:task-a1"; export STUDIO_RUN_ORIGIN
  run_lanes start "$MFP"; unset STUDIO_RUN_ORIGIN
  assert_eq 0 "$LS_STATUS" "the manifest run lands A"
  assert_contains "$HOME/.claude-gamedev/runs/last" '^origin=multica:task-a1$' "manifest mode writes origin=, kept in runs/last"
  assert_not_contains "$CALLS/1.fullenv" '^STUDIO_RUN_ORIGIN=' "no unit session inherits the variable"
}
test_lanes_origin_detach() {
  lanes_fixture ord integration A:-
  printf 'emit %s; sleep 8\n' "$ACT" > "$SCEN/A"
  st=0
  ( cd "$P" && env STUDIO_RUN_ORIGIN=multica:task-d1 sh "$RUNNER" start --detach "$MFP" ) > "$TMP/det.out" 2>&1 || st=$?
  assert_eq 0 "$st" "detach starts"
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  _e="$(ls -t "$HOME"/.claude-gamedev/runs/overnight-demo-* 2>/dev/null | head -n 1)"
  assert_contains "$_e" '^origin=multica:task-d1$' "--detach carries origin= through its STUDIO_* strip"
  assert_not_contains "$CALLS/1.fullenv" '^STUDIO_RUN_ORIGIN=' "the detached run's unit does not inherit it"
  detach_stop
  assert_contains "$HOME/.claude-gamedev/runs/last" '^origin=multica:task-d1$' "kept in runs/last"
}
test_lanes_origin_detach_refused() {
  lanes_fixture odr integration A:-
  st=0
  ( cd "$P" && env 'STUDIO_RUN_ORIGIN=bad value' sh "$RUNNER" start --detach "$MFP" ) > "$TMP/det.out" 2>&1 || st=$?
  assert_eq 0 "$st" "a refused origin still starts the run"
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  _e="$(ls -t "$HOME"/.claude-gamedev/runs/overnight-demo-* 2>/dev/null | head -n 1)"
  assert_not_contains "$_e" '^origin=' "no origin= line"
  _dl="$(ls -t "$P"/.studio/reports/overnight-demo-detached-*.log | head -n 1)"
  assert_eq 1 "$(cat "$TMP/det.out" "$_dl" | grep -c 'STUDIO_RUN_ORIGIN ignored')" "one warning, in the foreground only"
  detach_stop
}
```

  In `test_overnight_help`, add
  `"deny-rules \[--dir"` and `"STUDIO_RUN_ORIGIN"` to the `for w in` list, and two assertions
  `assert_contains "$REPO_ROOT/docs/game-dev/overnight-events.md" "deny-rules" "the contract doc lists deny-rules"`,
  `assert_contains "$REPO_ROOT/docs/game-dev/overnight-events.md" "origin=" "the contract doc documents origin="`.
- [ ] **Step 2: Run them to see them fail.**
  Run: `TESTS_ONLY="test_overnight_help test_overnight_deny_rules_basic test_overnight_deny_rules_usage test_overnight_origin_written" sh tests/overnight_test.sh`
  Expected: FAIL — `deny-rules` is an unknown verb (exit 2 from `usage`),
  help lacks it, `runs/last` has no `origin=` line.
  Run: `TESTS_ONLY="test_lanes_origin_detach" sh tests/overnight_lanes_test.sh`
  Expected: FAIL — the registry entry has no `origin=` line.
- [ ] **Step 3: Implement.** In `deny_rules`, add before the
  `{merge_basename}` case:
  `case "$_r" in *'{default_branch}'*) [ -n "${DEFAULT_BRANCH:-}" ] || continue ;; esac`
  and update its comment ("a line needing an empty `{default_branch}` or
  `{merge_basename}` is dropped"). Add after `deny_rules`:

```sh
# cmd_deny_rules [--dir PATH] — the deny rules a unit would get for the
# project at PATH (default: here), one per line (AC1 of #28). Reads no run
# state; works outside git. Notes for dropped placeholders go to stderr.
cmd_deny_rules() {
  _dd="."
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; _dd="$2"; shift 2 ;;
      --dir=*) _dd="${1#--dir=}"; shift ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  [ -n "$_dd" ] && [ -d "$_dd" ] || { say "deny-rules: not a directory: $_dd"; exit 2; }
  if [ ! -f "$DENY_FILE" ] || ! grep -Evq '^[[:space:]]*(#|$)' "$DENY_FILE"; then
    say "deny-rules: $DENY_FILE: no deny rules"; exit 1
  fi
  _dw="$(cd "$_dd" && sh "$STATE_BIN" root --work 2>/dev/null)" || _dw=""
  [ -n "$_dw" ] || _dw="$(cd "$_dd" && pwd -P)"
  DEFAULT_BRANCH="$(git -C "$_dw" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || DEFAULT_BRANCH=""
  DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
  CONFIG="$_dw/.studio/config.json"
  MERGE_COMMAND=""; cfg_str merge_command '' '.*'
  MERGE_BASENAME=""
  [ -z "$MERGE_COMMAND" ] || MERGE_BASENAME="$(basename "${MERGE_COMMAND%% *}")"
  _live="$(grep -Ev '^[[:space:]]*#' "$DENY_FILE")"
  if [ -z "$DEFAULT_BRANCH" ] && printf '%s\n' "$_live" | grep -q '{default_branch}'; then
    say "deny-rules: no origin/HEAD in $_dw — rules using {default_branch} dropped"
  fi
  if [ -z "$MERGE_BASENAME" ] && printf '%s\n' "$_live" | grep -q '{merge_basename}'; then
    say "deny-rules: no merge_command in $CONFIG — rules using {merge_basename} dropped"
  fi
  deny_rules
  exit 0
}
```

  In the final dispatch add `deny-rules) shift; cmd_deny_rules "$@" ;;`
  before `*)`. In `usage`, add `| deny-rules [--dir <path>]` to the
  synopsis line and a paragraph: "deny-rules [--dir <path>]  print the
  deny rules a unit would get for the project at <path> (default: here),
  one per line; notes on stderr for placeholders with no value; reads no
  run state". In `docs/game-dev/overnight-events.md`, add `deny-rules`
  to the verbs list with its exit codes (0, 1 missing or rule-less deny
  file, 2 usage) and "reads no run state; not a run verb, takes no
  `--run`".

  AC1a (R52, R53) — add after `reg_get`:

```sh
# origin_ok VALUE — AC1a's rule for the registry's origin= value: 1-200
# bytes of A-Z a-z 0-9 . _ : - and no newline. The core never interprets it.
origin_ok() {
  case "$1" in *'
'*) return 1 ;; esac
  printf '%s\n' "$1" | LC_ALL=C grep -Eq '^[A-Za-z0-9._:-]{1,200}$'
}
# origin_take — STUDIO_RUN_ORIGIN, read once, into RUN_ORIGIN (cleared with
# one warning when it fails origin_ok), then dropped from the environment so
# no unit session inherits it.
origin_take() {
  RUN_ORIGIN="${STUDIO_RUN_ORIGIN:-}"
  unset STUDIO_RUN_ORIGIN 2>/dev/null || true
  if [ -n "$RUN_ORIGIN" ] && ! origin_ok "$RUN_ORIGIN"; then
    say "STUDIO_RUN_ORIGIN ignored — use 1-200 characters from A-Z a-z 0-9 . _ : -"
    RUN_ORIGIN=""
  fi
}
```

  `cmd_start`: `origin_take` as its first line (before the argument loop,
  so `--detach`, `--dry-run`, manifest and single-plan all pass through
  it). `reg_write`: the entry's write becomes

```sh
  { printf 'root=%s\nstart=%s\nrun=%s\npid=%s\nstarted=%s\n' "$STATE_ROOT" "$START_DIR" "$RUN_DIR" "$$" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -z "${RUN_ORIGIN:-}" ] || printf 'origin=%s\n' "$RUN_ORIGIN"; } > "$REG_ENTRY" 2>/dev/null || REG_ENTRY=""
```

  `detach_start`: both `nohup perl -MPOSIX …` lines become `nohup env
  ${RUN_ORIGIN:+"STUDIO_RUN_ORIGIN=$RUN_ORIGIN"} perl -MPOSIX …` (the
  `STUDIO_*` strip above them is unchanged; the comment gains "except a
  valid STUDIO_RUN_ORIGIN, passed on explicitly (AC1a)"). `reg_end` is
  unchanged (it appends `ended=` and moves the whole file). `usage`: an
  `Environment:` paragraph before the test hooks — "STUDIO_RUN_ORIGIN —
  optional tag (1-200 characters from A-Z a-z 0-9 . _ : -) written as
  origin= in this run's registry entry; the runner never interprets it
  and does not pass it to unit sessions". `overnight-events.md`, in the
  registry paragraph: "An entry may also hold `origin=<value>`, copied
  from `STUDIO_RUN_ORIGIN` at start (AC1a of #28: 1–200 characters of
  A-Z a-z 0-9 . _ : -, else left out with a warning); it stays when the
  entry moves to `runs/last`; the core never interprets it."
- [ ] **Step 4: Run the tests.**
  Run: `sh tests/overnight_test.sh && sh tests/overnight_lanes_test.sh`
  Expected: PASS, including `test_lanes_detach_strips_env` (the strip is
  unchanged), `test_overnight_launch_argv` and
  `test_overnight_deny_merge_basename` unchanged (the runner's launch
  arguments are unchanged: its preflight refuses an empty default branch).
- [ ] **Step 5: Whole core gate.**
  Run: `sh tests/run_all.sh`
  Expected: exit 0.
- [ ] **Step 6: Commit.**

```bash
git add studios/game-dev/bin/studio-overnight tests/overnight_test.sh tests/overnight_lanes_test.sh docs/game-dev/overnight-events.md
git commit -m "feat(overnight): deny-rules verb and the registry's origin= line (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 3: The two wrappers, the deny list, the session context, and the integration gate
Files: integrations/multica/bin/claude-multica, integrations/multica/bin/omega-multica-agent, integrations/multica/bin/wrapper-lib.sh, integrations/multica/multica-deny.txt, integrations/multica/agent-context.md, integrations/multica/tests/run.sh, integrations/multica/tests/wrappers_test.sh, integrations/multica/.gitignore
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L266-301, docs/game-dev/specs/2026-10-03-multica-integration.md:L594-604, docs/game-dev/specs/2026-10-03-multica-integration.md:L720-729, docs/game-dev/specs/2026-10-03-multica-integration.md:L61-73
Review: task

**Interfaces:**
- Consumes: `studio-overnight deny-rules --dir <dir>` (T2);
  `studio-state root`; D1a (P1's path: file flag or inline context).
- Produces: `claude-multica [args…]`, `omega-multica-agent [args…]` (the
  runtimes' commands, AC2/AC3); the link file
  `~/.claude-gamedev/multica/links/<task id>` with lines `root=`, `task=`,
  `agent=`, `workdir=`, `written=` (read by T5 `studio.read_link`);
  `STUDIO_RUN_ORIGIN=multica:<MULTICA_TASK_ID>` exported to the session
  (AC3.6; T2's `start` turns it into the registry's `origin=` line);
  `<workdir>/.omega-context.md`; `integrations/multica/tests/run.sh` (the
  integration gate every later task extends); the stub-recorder convention
  below (reused by T10's `install_test.sh`).

**`bin/wrapper-lib.sh`** (sourced; full code — the quoting is the hard
part, checked by trial in Falsify #35):

```sh
# wrapper-lib.sh — sourced by claude-multica and omega-multica-agent (never
# run). The caller sets $self (its own real path, symlinks resolved) and
# $WRAPPER (its name) first. Defines paths and functions only.
WRAPPER_BIN="$(cd "$(dirname "$self")" && pwd -P)"
MULTICA_DIR="$(cd "$WRAPPER_BIN/.." && pwd -P)"
REPO="$(cd "$MULTICA_DIR/../.." && pwd -P)"
SO="$REPO/studios/game-dev/bin/studio-overnight"
STATE_BIN="$REPO/studios/game-dev/bin/studio-state"
MULTICA_DENY="$MULTICA_DIR/multica-deny.txt"
AGENT_CONTEXT="$MULTICA_DIR/agent-context.md"
die() { printf '%s: %s\n' "$WRAPPER" "$*" >&2; exit 1; }
# sq TEXT — TEXT as one single-quoted shell word.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# deny_list DIR — the core's rules for DIR, then multica-deny.txt's; one per
# line. Returns 1 with ONE line on stderr when deny-rules fails or prints
# nothing; on success deny-rules' notes are passed to stderr.
deny_list() {
  _dl_err="$(mktemp "${TMPDIR:-/tmp}/omega-deny.XXXXXX")" || { printf '%s: cannot make a temp file\n' "$WRAPPER" >&2; return 1; }
  _dl_core="$(sh "$SO" deny-rules --dir "$1" 2>"$_dl_err")"; _dl_st=$?
  if [ "$_dl_st" -ne 0 ]; then
    printf '%s: deny-rules failed (exit %s) for %s: %s\n' "$WRAPPER" "$_dl_st" "$1" "$(tail -n 1 "$_dl_err")" >&2
    rm -f "$_dl_err"; return 1
  fi
  cat "$_dl_err" >&2; rm -f "$_dl_err"
  [ -n "$_dl_core" ] || { printf '%s: deny-rules printed no rules for %s\n' "$WRAPPER" "$1" >&2; return 1; }
  [ -f "$MULTICA_DENY" ] || { printf '%s: missing %s\n' "$WRAPPER" "$MULTICA_DENY" >&2; return 1; }
  printf '%s\n' "$_dl_core"
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$MULTICA_DENY" | grep -Ev '^(#|$)'
}
# deny_words DIR — deny_list as words for eval: --disallowedTools 'rule' …
deny_words() {
  _dw_list="$(deny_list "$1")" || return 1
  _dw_out=""
  while IFS= read -r _dw_r; do
    [ -n "$_dw_r" ] || continue
    _dw_out="$_dw_out --disallowedTools $(sq "$_dw_r")"
  done <<EOT
$_dw_list
EOT
  printf '%s' "$_dw_out"
}
```

**`bin/claude-multica`** (full code):

```sh
#!/bin/sh
# claude-multica — the "claude (multica)" runtime (mode 2): your normal
# claude, plus the core's and Multica's deny rules. Multica's cwd and env
# pass through unchanged.
self="$0"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
WRAPPER=claude-multica
. "$(cd "$(dirname "$self")" && pwd -P)/wrapper-lib.sh"
[ "${1:-}" = "--version" ] && exec claude --version
words="$(deny_words "$PWD")" || exit 1
eval "set -- $words \"\$@\""
exec claude "$@"
```

**`bin/omega-multica-agent`** (order is the contract; full code except
the two messages already fixed by R39):

```sh
#!/bin/sh
# omega-multica-agent — the "omega game-dev" runtime (mode 3): claude-gd in
# OMEGA_PROJECT with Multica's context appended and the deny rules.
self="$0"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
WRAPPER=omega-multica-agent
. "$(cd "$(dirname "$self")" && pwd -P)/wrapper-lib.sh"
[ "${1:-}" = "--version" ] && exec claude-gd --version
[ -n "${OMEGA_PROJECT:-}" ] || die "OMEGA_PROJECT is not set — set it in the Multica agent's environment"
[ -d "$OMEGA_PROJECT" ] || die "OMEGA_PROJECT is not a directory: $OMEGA_PROJECT"
PROJECT_ROOT="$(cd "$OMEGA_PROJECT" && sh "$STATE_BIN" root 2>/dev/null)"
[ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT/.studio" ] \
  || die "no .studio/ at the studio root of $OMEGA_PROJECT — run studio-state init there"
WORKDIR="$(pwd -P)"
words="$(deny_words "$OMEGA_PROJECT")" || exit 1
LINKS="$HOME/.claude-gamedev/multica/links"
if [ -n "${MULTICA_TASK_ID:-}" ]; then
  case "$MULTICA_TASK_ID" in
    *[!A-Za-z0-9-]*) printf '%s: warning: MULTICA_TASK_ID has unexpected characters; no link file\n' "$WRAPPER" >&2 ;;
    *)
      STUDIO_RUN_ORIGIN="multica:$MULTICA_TASK_ID"; export STUDIO_RUN_ORIGIN   # AC3.6 → AC1a
      _lt="$LINKS/.$MULTICA_TASK_ID.$$"
      if mkdir -p "$LINKS" 2>/dev/null \
         && printf 'root=%s\ntask=%s\nagent=%s\nworkdir=%s\nwritten=%s\n' "$PROJECT_ROOT" "$MULTICA_TASK_ID" \
              "${MULTICA_AGENT_ID:-}" "$WORKDIR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_lt" 2>/dev/null \
         && mv -f "$_lt" "$LINKS/$MULTICA_TASK_ID" 2>/dev/null; then :; else
        rm -f "$_lt" 2>/dev/null
        printf '%s: warning: could not write the link file %s\n' "$WRAPPER" "$LINKS/$MULTICA_TASK_ID" >&2
      fi ;;
  esac
fi
CTX="$WORKDIR/.omega-context.md"
{ if [ -f "$WORKDIR/CLAUDE.md" ]; then cat "$WORKDIR/CLAUDE.md"; printf '\n'; fi
  cat "$AGENT_CONTEXT"
  printf '\nMultica workdir: %s\n' "$WORKDIR"
} > "$CTX.tmp.$$" 2>/dev/null && mv -f "$CTX.tmp.$$" "$CTX" 2>/dev/null \
  || { rm -f "$CTX.tmp.$$" 2>/dev/null; die "cannot write $CTX"; }
cd "$OMEGA_PROJECT" || die "cannot cd to $OMEGA_PROJECT"
eval "set -- $words --append-system-prompt-file $(sq "$CTX") --add-dir $(sq "$WORKDIR") \"\$@\""
exec claude-gd "$@"
```

  (If D1a chose the inline fallback, the `eval` line passes
  `--append-system-prompt $(sq "$(cat "$CTX")")` instead and the test
  below asserts that form; the context file is still written.)

**`multica-deny.txt`** — a header comment (what it is, that it is a
deterrent and not a sandbox, spec Risks), then exactly these rules (AC5)
plus the two references 4 and 7 imply:

```
Read(~/.multica/**)
Bash(*.multica/profiles*)
Bash(*multica*--profile*)
Bash(*multica login*)
Bash(*multica auth*)
Bash(*multica setup*)
Bash(*multica config*)
Bash(*multica workspace switch*)
Bash(*MULTICA_TOKEN=*)
Bash(*multica*--server-url*)
```

**`agent-context.md`** — short, imperative (it is appended to every mode-3
system prompt): your working directory is the game project (`git status`
there must stay clean of Multica files); scratch files and comment bodies
go under the Multica workdir named on the last line only, posted with
`multica issue comment add <issue> --content-file <path>
--allow-external-file`; start overnight runs only with
`studio-overnight start --detach <manifest>` (never a single-plan
`start`); never read `~/.multica` or pass `--profile`; the `studio:`
comments on this board come from the bridge.

**`tests/run.sh`** (full code):

```sh
#!/bin/sh
# The Multica integration's gate (milestone gate step 2): every
# *_test.sh here, then the Python unittest suite, offline.
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"
PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
status=0
for t in "$HERE"/*_test.sh; do
  [ -f "$t" ] || continue
  printf '\n=== %s ===\n' "$(basename "$t")"
  sh "$t" || status=1
done
PY="${OMEGA_MULTICA_TEST_PY:-}"
if [ -z "$PY" ]; then
  if /usr/bin/python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then PY=/usr/bin/python3; else PY=python3; fi
fi
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || { echo "run.sh: $PY is older than Python 3.9"; exit 1; }
if ls "$HERE"/test_*.py >/dev/null 2>&1; then
  printf '\n=== python unittest (%s) ===\n' "$("$PY" --version 2>&1)"
  ( cd "$HERE" && "$PY" -m unittest discover -s . -p 'test_*.py' -t . ) || status=1
fi
exit "$status"
```

`integrations/multica/.gitignore`: `__pycache__/`.

**Stub-recorder convention** (in `wrappers_test.sh`; T10 reuses it): a
`$FAKE` dir first on `PATH` holds `claude` and `claude-gd`, each:
`n=$(( $(cat "$REC/count" 2>/dev/null || echo 0) + 1 ))`, argv one element
per line to `$REC/<name>.$n.argv`, `pwd -P` to `$REC/<name>.$n.pwd`, `env |
grep -E '^(MULTICA_|OMEGA_|STUDIO_RUN_ORIGIN=|KEEP_ME=)' | sort` to `$REC/<name>.$n.env`;
`--version` prints `2.1.288 (Claude Code)`. Test values are fakes
(`MULTICA_TOKEN=mat_fake_for_tests`).

- [ ] **Step 1: Write the failing tests** — `wrappers_test.sh` sources
  `tests/assert.sh` from the repo root (`REPO_ROOT` =
  `$(cd "$(dirname "$0")/../../.." && pwd -P)`), builds `$TMP` with the
  fake bin, a studio project `$TMP/proj` (git with a bare origin and
  `remote set-head origin main`, `studio-state init`, committed), and a
  Multica-like workdir `$TMP/ws/omeg-4-6d25f8ec1ce3/workdir` (not git).
  Helper `mini_repo NAME` copies `studios/game-dev/bin/` and
  `integrations/multica/{bin,multica-deny.txt,agent-context.md}` into
  `$TMP/NAME/` with the same layout, for the failure cases. Tests (run
  through `run_tests`):
  - `test_cm_version_passthrough` — `claude-multica --version --x` →
    one `claude` call, argv exactly `--version`.
  - `test_cm_argv_order` — from the workdir with Multica's real argv
    (`-p --output-format stream-json --input-format stream-json --verbose
    --permission-mode bypassPermissions --disallowedTools
    AskUserQuestion`): the recorded argv is `--disallowedTools` + rule,
    for every line of `deny-rules --dir <workdir>` then every rule of
    `multica-deny.txt`, then Multica's argv unchanged; cwd = the
    workdir; env lines identical to the caller's (`MULTICA_TOKEN`,
    `KEEP_ME`).
  - `test_agent_version_no_project` — `env -u OMEGA_PROJECT
    omega-multica-agent --version` → exit 0, `claude-gd` argv exactly
    `--version`, no link file, no context file.
  - `test_agent_project_unset`, `test_agent_project_missing`,
    `test_agent_project_not_studio` (a plain dir) — exit 1, exactly one
    stderr line (`grep -c .` = 1), no `claude-gd` call, no link file.
  - `test_agent_link_file` — `MULTICA_TASK_ID=01a102e8-d4ad-7157-ac66-6d25f8ec1ce3`,
    `MULTICA_AGENT_ID=0a1b2c3d-agent`: the link file has exactly the five
    keys; `root=` = `studio-state root` of the project; `workdir=` =
    the workdir's `pwd -P`; `written=` matches
    `^written=[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9:]\{8\}Z$`; no
    `.`-prefixed temp file left in `links/`.
  - `test_agent_link_write_fails_warns` — `links` exists as a plain file
    → one `warning:` line on stderr, the session still launches.
  - `test_agent_bad_task_id` — `MULTICA_TASK_ID='../x'` → warning, no file
    anywhere under `~/.claude-gamedev/multica/`, no `STUDIO_RUN_ORIGIN` in
    the recorded env, launches.
  - `test_agent_exports_run_origin` — with `MULTICA_TASK_ID=01a102e8-d4ad-7157-ac66-6d25f8ec1ce3`
    the recorded env has exactly
    `STUDIO_RUN_ORIGIN=multica:01a102e8-d4ad-7157-ac66-6d25f8ec1ce3`;
    without `MULTICA_TASK_ID` it has no `STUDIO_RUN_ORIGIN` line;
    `claude-multica` with a task id sets none either (AC3.6 is mode 3
    only).
  - `test_agent_context_with_claude_md` — workdir `CLAUDE.md` holds
    `MULTICA-CTX`; `.omega-context.md` = that file, a blank line,
    `agent-context.md`, a blank line, `Multica workdir: <workdir>`
    (compared with `cmp` against an expected file built the same way).
  - `test_agent_context_without_claude_md` — `agent-context.md` then the
    workdir line.
  - `test_agent_context_write_fails` — workdir `chmod 555` → exit 1, one
    stderr line, no launch.
  - `test_agent_argv_order` — `claude-gd` argv: the deny pairs for
    `deny-rules --dir <project>` then `multica-deny.txt`, then
    `--append-system-prompt-file`, `<workdir>/.omega-context.md`,
    `--add-dir`, `<workdir>`, then Multica's argv; cwd = the project's
    `pwd -P`.
  - `test_agent_rules_for_project_not_workdir` — the argv holds
    `Bash(git push * main)` (the project has origin/HEAD; the workdir does
    not).
  - `test_agent_keeps_multica_env` — `MULTICA_TOKEN`, `MULTICA_TASK_ID`,
    `MULTICA_AGENT_ID`, `MULTICA_DAEMON_PORT`, `MULTICA_SERVER_URL` all
    reach `claude-gd` unchanged.
  - `test_deny_failure_blocks_launch` — `mini_repo` with a comment-only
    `overnight-deny.txt`: both wrappers exit 1, one stderr line naming
    `deny-rules failed`, no stub call.
  - `test_deny_empty_blocks_launch` — `mini_repo` whose
    `studio-overnight` is replaced by `#!/bin/sh\nexit 0`: both exit 1
    (`printed no rules`), no stub call.
  - `test_started_through_symlink` — `$TMP/lbin/omega-multica-agent` and
    `claude-multica` symlinks to the repo copies (and a symlink to that
    symlink): both launch with the full deny list.
  - `test_rule_quoting_survives` — `mini_repo` whose `multica-deny.txt`
    adds the rule `Bash(it's $HOME `x` "q")`: it reaches `claude`
    byte-exact as one element.
  - `test_multica_deny_rules_ac5` — each AC5 rule is a line of
    `multica-deny.txt` (`grep -Fxq`).
  - `test_scripts_parse` — `sh -n` passes for `bin/claude-multica`,
    `bin/omega-multica-agent`, `bin/wrapper-lib.sh`, `tests/run.sh`,
    every `probes/*.sh` and `probes/p1-agent-wrapper`; the two wrappers,
    `tests/run.sh` and the probe `.sh` files are executable;
    `wrapper-lib.sh` is not.
- [ ] **Step 2: Run them to see them fail.**
  Run: `sh integrations/multica/tests/wrappers_test.sh`
  Expected: FAIL — the wrappers do not exist.
- [ ] **Step 3: Implement** the files above; `chmod 755` the two wrappers
  and `tests/run.sh`.
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0 (`run.sh` runs `wrappers_test.sh`; no Python
  tests yet, so it skips unittest).
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/bin integrations/multica/multica-deny.txt integrations/multica/agent-context.md \
  integrations/multica/tests/run.sh integrations/multica/tests/wrappers_test.sh integrations/multica/.gitignore
git commit -m "feat(multica): claude-multica and omega-multica-agent wrappers (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 4: The stub CLI, the CLI adapter and the config
Files: integrations/multica/tests/stub-multica, integrations/multica/bridge/__init__.py, integrations/multica/bridge/config.py, integrations/multica/bridge/multica_cli.py, integrations/multica/tests/bridgetest.py, integrations/multica/tests/test_cli.py, integrations/multica/tests/test_config.py, integrations/multica/tests/stub-security
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L439-445, docs/game-dev/specs/2026-10-03-multica-integration.md:L458-463, docs/game-dev/specs/2026-10-03-multica-integration.md:L521-534, docs/game-dev/specs/2026-10-03-multica-integration.md:L577-592, docs/game-dev/specs/2026-10-03-multica-integration.md:L745-748
Review: task

**Interfaces:**
- Consumes: T1's fixtures (`tests/fixtures/cli/*.json`, `errors/*.txt`)
  and D1g (envelope keys, field names, `__none__` result, reply nesting).
- Produces (later tasks use these names exactly):
  - `bridge.config`: `ConfigError(Exception)`; `Config` with attributes
    `server_url: str`, `workspace_id: str`, `operator_member_id: str`,
    `roots: list[str]`, `poll_seconds: int`, `cli: str`,
    `studio_overnight: str`; `load(path: str) -> Config`;
    `DESKTOP_CLI` (the bundled path).
  - `bridge.multica_cli`: constants `CLI_TIMEOUT = 60`, `PREFIX =
    "studio: "`, `KEYCHAIN_SERVICE = "omega-multica-bridge"`, `SECURITY`;
    exceptions `CliError(Exception)` (`.stderr`, `.code`),
    `TransientError(CliError)`, `AuthError(CliError)`,
    `PermanentError(CliError)`, `NotFoundError(PermanentError)`,
    `KeychainError(Exception)` (`.kind` ∈ `missing`, `locked`, `error`,
    `empty`), `ForbiddenWrite(Exception)`; functions `sanitize(text: str)
    -> str`, `classify(code: int, stderr: str, timed_out: bool = False) ->
    CliError`, `rows(obj) -> list`, `read_token(account: str | None =
    None) -> str`; `RedactFilter(logging.Filter)` (`__init__(self,
    secrets: list[str])`); class `Cli(cfg: Config, token: str, cli_home:
    str, log: logging.Logger)` with attribute `forbidden: set[str]` and
    methods `call(args: list[str], stdin: str | None = None, parse: bool
    = True)`, `version() -> dict`, `profile() -> dict`, `run_issues(run_key:
    str) -> list[dict]` (paged), `find_issues(run_key: str, story: str |
    None) -> list[dict]`, `assigned_issues(agent_id: str) -> list[dict]`,
    `get_issue(ident: str) -> dict`, `issue_runs(ident: str) ->
    list[dict]`, `create_issue(title: str, description: str, parent: str |
    None, props: dict[str, str]) -> dict`, `set_status(ident: str,
    status: str) -> dict`, `add_comment(ident: str, text: str, parent: str
    | None = None) -> dict`, `list_comments(ident: str, since: str) ->
    list[dict]`.
  - `tests/stub-multica` (contract below) and `bridgetest.Board`,
    `bridgetest.BridgeCase`, constants `OPERATOR = "m-op"`, `TOKEN =
    "mul_testtoken123456"`, `WS = "ws-test"`.

**`tests/stub-multica` contract** (Python 3.9, executable, `#!/usr/bin/env
python3`; the adapter's `PATH=/usr/bin:/bin` finds `/usr/bin/python3`).

- **Where its state lives:** `$STUB_MULTICA_DIR`, else `<directory of
  argv[0] as invoked>/stub-state` (R9; `sys.argv[0]` is the symlink path,
  not resolved). Files: `board.json` (the workspace), `calls.jsonl` (one
  line per call: `argv` without argv[0], `stdin`, `cwd`, `env` = the
  values of `MULTICA_TOKEN`, `MULTICA_SERVER_URL`, `MULTICA_WORKSPACE_ID`,
  `MULTICA_DAEMON_PORT`, `MULTICA_TASK_ID`, `HOME`, `PATH` that are set,
  `exit`), `faults.json` (injected failures), `errors/<name>.txt`
  (optional real texts, copied from the P7 fixtures by `Board`).
- **Exit codes:** 0 ok (JSON on stdout when `--output json`, else the line
  `TABLE OUTPUT` so a missing `--output json` fails loudly); 1 API error
  (text on stderr); 2 usage (unknown command, unknown flag, missing
  argument, `--limit` outside 1–100, `--output` on `runtime profile
  delete`).
- **Global flags** anywhere in argv: `--profile V`, `--server-url V`,
  `--workspace-id V`, `--output V`, `--debug`.
- **Auth:** every command except `version`: unset or empty
  `MULTICA_TOKEN` → exit 1 with `errors/no-token.txt`; a value other
  than `board.token` → exit 1 with `errors/unauthorized.txt`.
- **Faults:** `faults.json` is a list of rules `{cmd, contains, count,
  exit, stderr, stdout, apply, sleep}`. The first rule whose `cmd` equals
  the command words (`"issue comment add"`) and whose optional `contains`
  is a substring of the space-joined argv, with `count` ≠ 0, fires:
  sleeps `sleep` seconds (default 0); when `apply` is true, performs the
  command's effect first (a write that "timed out" but landed); prints
  `stdout` (default empty) and `stderr`; exits `exit` (default 1);
  decrements `count` (default 1; −1 = forever) and saves the file.
- **Commands** (flags not listed are usage errors):

| command | value flags / bool flags / positionals | effect and stdout |
|---|---|---|
| `version` | – / – / 0 | `{"version": board.version, …}` (keys of `version.json`) |
| `user profile get` | – / – / 0 | `board.user` |
| `issue create` | `--title --description --parent --status --assignee-id --property`(repeatable) / `--description-stdin --allow-duplicate` / 0 | missing title → 2; unknown parent → not-found; unknown property name or a `__none__` value → 1; an active (non-terminal, not deleted) issue with the same title and the same parent and no `--allow-duplicate` → 1 with `errors/duplicate.txt`; new issue `{id: "iss-N", identifier: "OMEG-N", number, title, description, status (default "backlog"), status_category, assignee_type, assignee_id, parent_issue_id, created_at, updated_at, properties: {property id: value}}` |
| `issue get <id>` | – / – / 1 | the issue by identifier or id; deleted or unknown → not-found |
| `issue list` | `--property --assignee-id --sort --direction --limit --offset --status` / – / 0 | `--property Name=Value` matched by name (any case) or id; `__none__` = unset; repeats of one property = ANY, different properties = ALL; deleted issues never listed; `--sort created_at` with `--direction`; `--limit` default 50; stdout the envelope `issue-list-run.json` has (D1g; default `{"issues": [...], "has_more": bool}`) |
| `issue status <id> <key>` | – / `--no-start` / 2 | unknown key → 1 with `errors/bad-status.txt`; sets `status`, `status_category`, `updated_at`; stdout the issue |
| `issue runs <id>` | – / `--active` / 1 | `board.runs[identifier]` (rows shaped like `issue-runs.json`); `--active` keeps `queued`, `dispatched`, `running` |
| `issue comment add <id>` | `--parent --content` / `--content-stdin` / 1 | unknown issue → not-found; `--parent` not a comment of that issue → 1; new comment `{id: "cm-N", issue_id, parent_id, content, author_type: "member", author_id: board.user.id, created_at}` |
| `issue comment list <id>` | `--since` / – / 1 | the issue's comments created strictly after `--since` (or as D1g's P7e records), oldest first, in `comment-list.json`'s shape |
| `property list` | – / `--include-archived` / 0 | `board.properties` (archived ones only with the flag) |
| `property create` | `--name --type --description` / – / 0 | `board.role` not `owner`/`admin` → 1 with `errors/forbidden.txt`; an existing name → 1 |
| `runtime list` | – / – / 0 | `board.runtimes` |
| `runtime profile list` | – / – / 0 | `board.runtime_profiles` |
| `runtime profile create` | `--display-name --command-name --protocol-family` / – / 0 | new `{id: "rp-N", display_name, command_name, protocol_family, enabled: true}`; when `board.auto_runtime`, also appends `{id: "rt-N", name, profile_id, daemon_id: board.daemon_id, status: "online"}` to `board.runtimes` |
| `runtime profile delete <id>` | – / – / 1 (no `--output`) | removes it; `Deleted runtime profile <id>` on stderr, nothing on stdout |
| `agent list` | – / `--include-archived` / 0 | `board.agents` (archived only with the flag) |
| `agent create` | `--name --runtime-id --max-concurrent-tasks --instructions` / `--custom-env-stdin` / 0 | stdin parsed as a JSON object (else 1); new `{id: "ag-N", name, runtime_id, max_concurrent_tasks, instructions, custom_env: {k: "****"}, archived: false}` |

- **Clock:** `created_at`/`updated_at` = `board.now` (epoch seconds; when
  null, `time.time()`) plus `seq` microseconds, so two writes in one test
  never share a timestamp; printed in P7d's form (default
  `%Y-%m-%dT%H:%M:%S.%fZ`).

The skeleton (full code for the mechanics; handlers follow the table):

```python
#!/usr/bin/env python3
"""stub-multica: offline stand-in for the Multica CLI 0.6.x (#28 tests). See
the contract in docs/game-dev/plans/2026-10-03-multica-integration.md, Task 4."""
from __future__ import annotations

import fcntl
import json
import os
import sys
import time
from datetime import datetime, timezone

ENV_KEYS = ("MULTICA_TOKEN", "MULTICA_SERVER_URL", "MULTICA_WORKSPACE_ID",
            "MULTICA_DAEMON_PORT", "MULTICA_TASK_ID", "HOME", "PATH")
GLOBAL_VALUE = ("--profile", "--server-url", "--workspace-id", "--output")
GLOBAL_BOOL = ("--debug",)
DEFAULT_ERRORS = {
    "no-token": "Error: not authenticated: run `multica login` or set MULTICA_TOKEN",
    "unauthorized": "Error: 401 Unauthorized: invalid token",
    "not-found": "Error: 404 Not Found: not found",
    "duplicate": "Error: Active duplicate issue exists: {ident} {title}",
    "bad-status": "Error: unknown status \"{status}\"",
    "forbidden": "Error: 403 Forbidden: workspace owner or admin required",
}
SPEC = {  # command words: (value flags, bool flags, positional count)
    ("version",): ((), (), 0),
    ("user", "profile", "get"): ((), (), 0),
    ("issue", "create"): (("--title", "--description", "--parent", "--status", "--assignee-id", "--property"),
                          ("--description-stdin", "--allow-duplicate"), 0),
    ("issue", "get"): ((), (), 1),
    ("issue", "list"): (("--property", "--assignee-id", "--sort", "--direction", "--limit", "--offset", "--status"), (), 0),
    ("issue", "status"): ((), ("--no-start",), 2),
    ("issue", "runs"): ((), ("--active",), 1),
    ("issue", "comment", "add"): (("--parent", "--content"), ("--content-stdin",), 1),
    ("issue", "comment", "list"): (("--since",), (), 1),
    ("property", "list"): ((), ("--include-archived",), 0),
    ("property", "create"): (("--name", "--type", "--description"), (), 0),
    ("runtime", "list"): ((), (), 0),
    ("runtime", "profile", "list"): ((), (), 0),
    ("runtime", "profile", "create"): (("--display-name", "--command-name", "--protocol-family"), (), 0),
    ("runtime", "profile", "delete"): ((), (), 1),
    ("agent", "list"): ((), ("--include-archived",), 0),
    ("agent", "create"): (("--name", "--runtime-id", "--max-concurrent-tasks", "--instructions"), ("--custom-env-stdin",), 0),
}
REPEATABLE = ("--property",)
NO_OUTPUT = (("runtime", "profile", "delete"),)


class Exit(Exception):
    def __init__(self, code, out="", err=""):
        super().__init__(code)
        self.code, self.out, self.err = code, out, err


def state_dir():
    return os.environ.get("STUB_MULTICA_DIR") or os.path.join(
        os.path.dirname(os.path.abspath(sys.argv[0])), "stub-state")


def error_text(d, name, **kw):
    try:
        with open(os.path.join(d, "errors", name + ".txt"), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return DEFAULT_ERRORS[name].format(**kw)


def parse(argv):
    """-> (words, values, bools, positionals, output). Global flags may sit anywhere."""
    toks, output, has_output, i = [], "table", False, 0
    while i < len(argv):
        a = argv[i]
        name, eq, val = a.partition("=")
        if name in GLOBAL_VALUE:
            if not eq:
                if i + 1 >= len(argv):
                    raise Exit(2, err="Error: flag needs an argument: " + name)
                val, i = argv[i + 1], i + 1
            if name == "--output":
                output, has_output = val, True
        elif a not in GLOBAL_BOOL:
            toks.append(a)
        i += 1
    words = next((tuple(toks[:n]) for n in (3, 2, 1) if tuple(toks[:n]) in SPEC), None)
    if words is None:
        raise Exit(2, err="Error: unknown command: " + " ".join(toks[:3]))
    if has_output and words in NO_OUTPUT:
        raise Exit(2, err="Error: unknown flag: --output")
    vflags, bflags, npos = SPEC[words]
    values, bools, pos, rest, j = {}, set(), [], toks[len(words):], 0
    while j < len(rest):
        a = rest[j]
        name, eq, val = a.partition("=")
        if name in vflags:
            if not eq:
                if j + 1 >= len(rest):
                    raise Exit(2, err="Error: flag needs an argument: " + name)
                val, j = rest[j + 1], j + 1
            if name in REPEATABLE:
                values.setdefault(name, []).append(val)
            else:
                values[name] = val
        elif a in bflags:
            bools.add(a)
        elif a.startswith("-") and a != "-":
            raise Exit(2, err="Error: unknown flag: " + name)
        else:
            pos.append(a)
        j += 1
    if len(pos) != npos:
        raise Exit(2, err="Error: accepts %d arg(s), received %d" % (npos, len(pos)))
    return words, values, bools, pos, output


def main():
    d = state_dir()
    stdin = "" if sys.stdin is None or sys.stdin.isatty() else sys.stdin.read()
    rec = {"argv": sys.argv[1:], "stdin": stdin, "cwd": os.getcwd(),
           "env": {k: os.environ[k] for k in ENV_KEYS if k in os.environ}}
    code, out, err = 0, "", ""
    lock = open(os.path.join(d, ".lock"), "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        board = json.load(open(os.path.join(d, "board.json"), encoding="utf-8"))
        try:
            words, values, bools, pos, output = parse(sys.argv[1:])
            if words != ("version",):
                tok = os.environ.get("MULTICA_TOKEN", "")
                if not tok:
                    raise Exit(1, err=error_text(d, "no-token"))
                if tok != board["token"]:
                    raise Exit(1, err=error_text(d, "unauthorized"))
            fault = take_fault(d, words, sys.argv[1:])
            if fault and fault.get("sleep"):
                time.sleep(fault["sleep"])
            if fault and not fault.get("apply"):
                raise Exit(fault.get("exit", 1), fault.get("stdout", ""), fault.get("stderr", ""))
            result = HANDLERS[words](board, d, values, bools, pos, stdin)
            save(d, board)
            if fault:
                raise Exit(fault.get("exit", 1), fault.get("stdout", ""), fault.get("stderr", ""))
            if result is not None:
                out = json.dumps(result) if output == "json" else "TABLE OUTPUT"
        except Exit as e:
            code, out, err = e.code, e.out, e.err
    finally:
        rec["exit"] = code
        with open(os.path.join(d, "calls.jsonl"), "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")
        fcntl.flock(lock, fcntl.LOCK_UN)
    if out:
        sys.stdout.write(out + "\n")
    if err:
        sys.stderr.write(err + "\n")
    sys.exit(code)
```

  The rest of the file: `take_fault(d, words, argv) -> dict | None` (the Faults rule),
  `save(d, board)` (temp file + `os.replace`), `now(board) -> str`
  (the Clock rule; uses `datetime.fromtimestamp(t, timezone.utc)`, never
  `utcfromtimestamp`) and the `HANDLERS` dict (one function per table
  row) complete the file. The stub is tested by
  `test_stub_conformance` (below), so its own behaviour is pinned.

**`bridge/multica_cli.py`** — full code for the hard parts:

```python
from __future__ import annotations

import json
import logging
import os
import pwd
import re
import subprocess

CLI_TIMEOUT = 60
PREFIX = "studio: "
KEYCHAIN_SERVICE = "omega-multica-bridge"
SECURITY = os.environ.get("OMEGA_MULTICA_SECURITY", "/usr/bin/security")   # test hook (R46)
_ENVELOPE_KEYS = ("issues", "comments", "runs", "data", "items", "rows")
_MENTION = re.compile(r"mention:", re.IGNORECASE)
_TICKS = re.compile(r"`{3,}")
_AUTH = re.compile(r"(?i)\b401\b|unauthori[sz]ed|invalid (?:api )?token|token (?:is )?(?:expired|revoked|invalid)"
                   r"|not authenticated|not logged in")
_NOT_FOUND = re.compile(r"(?i)\b404\b|not found|no such issue|\barchived\b|\bdeleted\b")
_TRANSIENT = re.compile(r"(?i)\b429\b|too many requests|rate.?limit|\b50[0-4]\b|bad gateway|service unavailable"
                        r"|gateway timeout|internal server error|timed? ?out|timeout|connection refused"
                        r"|connection reset|no such host|network is unreachable|unexpected eof|temporar"
                        r"|retryable|dial tcp")
_TOKEN_RE = re.compile(r"\b(?:mul|mat)_[A-Za-z0-9_-]{6,}")


class CliError(Exception):
    def __init__(self, message: str, stderr: str = "", code: int | None = None):
        super().__init__(message)
        self.stderr, self.code = stderr, code


class TransientError(CliError): pass
class AuthError(CliError): pass
class PermanentError(CliError): pass
class NotFoundError(PermanentError): pass
class ForbiddenWrite(Exception): pass


class KeychainError(Exception):
    def __init__(self, kind: str, message: str):
        super().__init__(message)
        self.kind = kind


def sanitize(text: str) -> str:
    """AC18: no mention can form, and no html or mermaid fence can open."""
    text = _MENTION.sub("no-mention:", text)
    text = text.replace("@", "＠")
    return _TICKS.sub(lambda m: "​".join(m.group(0)), text)


def classify(code: int, stderr: str, timed_out: bool = False) -> CliError:
    first = (stderr.strip().splitlines() or [""])[0][:300]
    if timed_out:
        return TransientError("timed out after %d s" % CLI_TIMEOUT, stderr, code)
    if _AUTH.search(stderr):
        return AuthError(first, stderr, code)
    if _NOT_FOUND.search(stderr):
        return NotFoundError(first, stderr, code)
    if _TRANSIENT.search(stderr):
        return TransientError(first, stderr, code)
    return PermanentError(first or "exit %s" % code, stderr, code)


def rows(obj) -> list:
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for k in _ENVELOPE_KEYS:
            if isinstance(obj.get(k), list):
                return obj[k]
    return []


def read_token(account: str | None = None) -> str:
    account = account or pwd.getpwuid(os.getuid()).pw_name      # `id -un` (R11)
    try:
        r = subprocess.run([SECURITY, "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise KeychainError("error", "cannot read the Keychain: %s" % e)
    if r.returncode == 44:
        raise KeychainError("missing", "no Keychain item %s for %s — run install.sh" % (KEYCHAIN_SERVICE, account))
    if r.returncode != 0:
        raise KeychainError("locked", "the Keychain refused (exit %d) — is it locked?" % r.returncode)
    token = r.stdout.strip()
    if not token:
        raise KeychainError("empty", "the Keychain item is empty — run install.sh --new-token")
    return token


class RedactFilter(logging.Filter):
    """AC29: no token value reaches a log handler."""
    def __init__(self, secrets: list[str]):
        super().__init__()
        self.secrets = [s for s in secrets if s]

    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        for s in self.secrets:
            msg = msg.replace(s, "<token>")
        record.msg, record.args = _TOKEN_RE.sub("<token>", msg), None
        return True


class Cli:
    def __init__(self, cfg, token: str, cli_home: str, log: logging.Logger):
        self.cfg, self.token, self.cli_home, self.log = cfg, token, cli_home, log
        self.forbidden: set[str] = set()     # the request issue (AC17)

    def call(self, args: list[str], stdin: str | None = None, parse: bool = True):
        if not self.token:
            raise KeychainError("empty", "refusing to call the Multica CLI with an empty token")
        os.makedirs(self.cli_home, mode=0o700, exist_ok=True)
        argv = [self.cfg.cli] + list(args) + (["--output", "json"] if parse else [])
        env = {"MULTICA_TOKEN": self.token, "MULTICA_SERVER_URL": self.cfg.server_url,
               "MULTICA_WORKSPACE_ID": self.cfg.workspace_id, "HOME": self.cli_home, "PATH": "/usr/bin:/bin"}
        kw = {"input": stdin} if stdin is not None else {"stdin": subprocess.DEVNULL}
        try:
            r = subprocess.run(argv, capture_output=True, encoding="utf-8", errors="replace",
                               env=env, timeout=CLI_TIMEOUT, **kw)
        except subprocess.TimeoutExpired:
            raise classify(-1, "", timed_out=True)
        except OSError as e:
            raise PermanentError("cannot run %s: %s" % (self.cfg.cli, e))
        if r.stderr.strip():
            self.log.debug("multica %s: %s", " ".join(args[:3]), r.stderr.strip()[:500])
        if r.returncode != 0:
            raise classify(r.returncode, r.stderr)
        if not parse:
            return None
        try:
            return json.loads(r.stdout)
        except ValueError:
            raise PermanentError("output of multica %s is not JSON" % " ".join(args[:3]))
```

  The helper methods are thin and build exactly these argv (each then gets
  `--output json` from `call`):
  - `version`: `version`; `profile`: `user profile get`;
  - `run_issues(k)`: `issue list --property omega_run=<k> --limit 100
    --offset <o>`, looping while the envelope's `has_more` is true (`o`
    advances by the rows returned);
  - `find_issues(k, None)`: `issue list --property omega_run=<k>
    --property omega_story=__none__ --limit 100`; `find_issues(k, s)`:
    the same with `omega_story=<s>` (if D1g says `__none__` failed:
    `run_issues(k)` filtered by the `properties` map, using the ids of
    `omega_run`/`omega_story` from `property list`, cached per `Cli`);
  - `assigned_issues(a)`: `issue list --assignee-id <a> --sort created_at
    --direction desc --limit 20` (one page);
  - `get_issue(i)`: `issue get <i>`; `issue_runs(i)`: `issue runs <i>`,
    through `rows`;
  - `create_issue(t, d, p, props)`: `issue create --title <sanitize(t)>
    --status todo --allow-duplicate --description-stdin [--parent <p>]
    --property <k>=<v> …` with stdin `sanitize(d)` (R12; property values
    raw);
  - `set_status(i, s)`: `ForbiddenWrite` when `i in self.forbidden`;
    `issue status <i> <s> --no-start`;
  - `add_comment(i, text, parent)`: `ForbiddenWrite` when forbidden;
    `ValueError` unless `text.startswith(PREFIX)`; `issue comment add <i>
    --content-stdin [--parent <parent>]` with stdin `sanitize(text)`;
  - `list_comments(i, since)`: `issue comment list <i> --since <since>`,
    through `rows`.

**`bridge/config.py`**: `key=value` lines; blank lines and `#` lines
skipped; whitespace around key and value stripped. Keys and defaults as
spec 581-589. `roots` is split on `,`, each stripped, empties dropped.
`poll_seconds` must be an integer 5–300. `cli` defaults to `DESKTOP_CLI`
when that file exists, else `shutil.which("multica")`, else
`DESKTOP_CLI`. `studio_overnight` defaults to
`<checkout>/studios/game-dev/bin/studio-overnight` only when
`os.path.dirname(__file__)/../../../studios` exists (a checkout), else it
is required. Every error is `ConfigError("<path>: <key>: <why>")` (R44).

**`tests/stub-security`** (sh): `find-generic-password -s S -a A -w`
prints `$STUB_SECURITY_DIR/<S>-<A>` or exits 44 when absent;
`$STUB_SECURITY_DIR/locked` present → exit 36; `add-generic-password -s
S -a A -U -w` with no value reads one line from stdin into the file
(the real one prompts twice on the terminal); `delete-generic-password`
removes it (44 when absent). Every call's argv is appended to
`$STUB_SECURITY_DIR/calls`.

**`tests/bridgetest.py`** (grows in T5–T9): puts `integrations/multica`
on `sys.path`; `Board(cli_dir)` creates `cli_dir/multica` → symlink to
`stub-multica`, `cli_dir/stub-state/board.json` with the defaults
(`token TOKEN`, `role owner`, `auto_runtime true`, `daemon_id
"daemon-1"`, `version "0.6.1"`, `user {id OPERATOR, name "Operator",
email "operator@example.com"}`, properties `omega_run` and `omega_story`
(type text), empty lists elsewhere, `now null`), and copies
`fixtures/cli/errors/*.txt` into `stub-state/errors/`. Methods:
`data()`, `save(d)`, `add_issue(title, status="todo", parent=None,
props=None, assignee=None, created_at=None) -> str`, `issue(ident) ->
dict`, `assign(ident, kind, aid)` (`kind` `agent`/`squad`/`member`/
`None`), `set_status(ident, status)`, `remove_issue(ident)`,
`add_comment(ident, content, author_type="member", author_id=OPERATOR,
parent=None, at=None) -> str`, `comments(ident) -> list`,
`add_run(ident, run_id, started_at, completed_at=None, status="completed")`,
`calls(prefix: str = "") -> list[dict]` (calls whose argv starts with the
prefix words), `reset_calls()`, `fault(cmd, **rule)`, `set_now(epoch)`.
`BridgeCase(unittest.TestCase)`: `setUp` makes `self.tmp`, `self.home`,
`self.board = Board(self.tmp + "/cli")`, writes `self.cfg_path` with
`cli`, `server_url=http://stub.invalid`, `workspace_id=WS`,
`operator_member_id=OPERATOR`, `studio_overnight=<tests>/stub-studio-overnight`
(T5 adds it), and sets `self.cfg = config.load(self.cfg_path)`,
`self.cli = Cli(self.cfg, TOKEN, self.home + "/.claude-gamedev/multica/cli-home", log)`;
`tearDown` removes `self.tmp`.

- [ ] **Step 1: Write the failing tests.**
  `test_config.py` — `ConfigTest`: `test_defaults`,
  `test_required_missing`, `test_unknown_key`, `test_line_without_equals`,
  `test_poll_seconds_range` (4 and 301 refused; 5 and 300 ok),
  `test_roots_split_and_strip`, `test_comments_and_blank_lines`.
  `test_cli.py` — `CliTest(BridgeCase)`:
  - `test_env_is_exactly_five_keys` — with `MULTICA_DAEMON_PORT` and
    `MULTICA_TASK_ID` set in `os.environ`, the recorded `env` is exactly
    `MULTICA_TOKEN`=TOKEN, `MULTICA_SERVER_URL`, `MULTICA_WORKSPACE_ID`
    from the config, `HOME` = the cli-home (exists, empty after the
    call), `PATH=/usr/bin:/bin`;
  - `test_output_json_appended`, `test_stdin_devnull_without_input`;
  - `test_empty_token_refused_without_call` — `Cli(…, "")` raises
    `KeychainError` (kind `empty`); `calls.jsonl` absent;
  - `test_sanitize_spec_cases` — `[x](mention://agent/ab12)`,
    `[x](MENTION://all/all)`, `[r]: mention://member/1`, `@name`, an
    ```` ```html ```` fence and a four-backtick run: no output contains
    `mention:` without the `no-` before it (case-insensitive), any `@`,
    or three consecutive backticks;
  - `test_sanitize_reaches_title_description_comment` — via the stub's
    recorded argv/stdin; `test_property_values_not_sanitized`
    (`omega_story=a@b` stays);
  - `test_comment_requires_prefix` — `ValueError`, no call;
  - `test_request_issue_writes_forbidden` — `set_status`/`add_comment`
    on a `forbidden` identifier raise `ForbiddenWrite` with no call;
    `create_issue(parent=<it>)` works;
  - `test_status_calls_pass_no_start`;
  - `test_classify_recorded_errors` — each `fixtures/cli/errors/<n>.txt`
    with its `.exit`: `unauthorized`, `no-token` → `AuthError`;
    `not-found` → `NotFoundError`; `unreachable` → `TransientError`;
    `duplicate`, `bad-status` → `PermanentError` (not `NotFoundError`);
  - `test_classify_defaults` — `429 Too Many Requests`, `502 Bad Gateway`,
    `retryable` → transient; `OMEG-500 not found` → not-found (not
    transient);
  - `test_timeout_is_transient` — a fault with `sleep: 3` and
    `multica_cli.CLI_TIMEOUT` patched to 1;
  - `test_usage_exit_2_is_permanent`, `test_non_json_is_permanent`;
  - `test_rows_envelopes` — list, `{"issues": …}`, `{"comments": …}`,
    other → `[]`;
  - `test_run_issues_pages_on_has_more` — 150 issues → two calls,
    `--offset 0` then `--offset 100`, 150 rows;
  - `test_find_issues_none_filter` — a Run issue (`omega_run` only) and a
    story issue: `find_issues(k, None)` returns only the Run issue;
    `find_issues(k, "1")` only the story `1`;
  - `test_read_token_ok_missing_locked` — `SECURITY` patched to
    `stub-security`: ok; exit 44 → kind `missing`; `locked` → `locked`;
  - `test_redact_filter` — a log line holding TOKEN and `mat_abcdef123`
    reaches the handler as `<token>`;
  - `test_stub_conformance` — for each JSON fixture, the stub's answer to
    the same command has the same top-level keys (or both lists), and its
    rows carry every key the bridge reads (`identifier`, `status`,
    `status_category`, `assignee_type`, `assignee_id`, `created_at`,
    `parent_issue_id`, `properties` for issues; `id`, `parent_id`,
    `author_type`, `author_id`, `content`, `created_at` for comments;
    `id`, `started_at`, `completed_at` for runs; `profile_id`,
    `daemon_id`, `status` for runtimes);
  - `test_no_deprecated_calls` — no `bridge/*.py` contains
    `utcfromtimestamp`, `utcnow` or `fromisoformat`, and each starts with
    `from __future__ import annotations` (after its docstring).
- [ ] **Step 2: Run them to see them fail.**
  Run: `cd integrations/multica/tests && /usr/bin/python3 -m unittest test_config test_cli`
  Expected: FAIL — `ModuleNotFoundError: bridge`.
- [ ] **Step 3: Implement** `stub-multica` (`chmod 755`), `stub-security`
  (`chmod 755`), `bridge/__init__.py` (docstring only), `config.py`,
  `multica_cli.py`, `bridgetest.py`.
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0; unittest reports the new tests OK under
  `/usr/bin/python3` (3.9.6). Also run
  `OMEGA_MULTICA_TEST_PY=python3 sh integrations/multica/tests/run.sh`
  (Homebrew 3.14) — exit 0.
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/bridge integrations/multica/tests
git commit -m "feat(multica): CLI adapter, config, and the offline stub CLI (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 5: Run state and the studio side (registry with `origin`, liveness, links, event reader, verb calls)
Files: integrations/multica/bridge/state.py, integrations/multica/bridge/studio.py, integrations/multica/tests/stub-studio-overnight, integrations/multica/tests/bridgetest.py, integrations/multica/tests/test_state.py, integrations/multica/tests/test_studio.py
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L358-380, docs/game-dev/specs/2026-10-03-multica-integration.md:L393-397, docs/game-dev/specs/2026-10-03-multica-integration.md:L429-433, docs/game-dev/specs/2026-10-03-multica-integration.md:L453-457, docs/game-dev/specs/2026-10-03-multica-integration.md:L594-627
Review: task

**Interfaces:**
- Consumes: the registry format (`studio-overnight` `reg_write`:
  `root=`, `start=`, `run=`, `pid=`, `started=`, and T2's optional
  `origin=`; file
  `~/.claude-gamedev/runs/overnight-*`, ended runs in `runs/last`); the
  link file (T3); the #27 event schema v1; D1d (P4: the `origin=` line).
- Produces:
  - `bridge.state`: `Paths(home: str)` with attributes `home`, `base`, `config`,
    `lock`, `selftest`, `status`, `lib`, `cli_home`, `links`, `state_dir`,
    `retired_dir`, `retired_file`, `log`; `atomic_write_json(path: str,
    data) -> None` (temp in the same dir, `fsync`, `os.replace`, mode
    0600); `read_json(path: str, default=None)`; `run_key(run_dir: str,
    root: str) -> str`; `new_run_state(key: str, entry: dict, now: float)
    -> dict` (schema below); `load_run(paths, key) -> dict | None`;
    `save_run(paths, st: dict) -> None`; `tracked_keys(paths) ->
    list[str]`; `load_retired(paths) -> set[str]`; `retire(paths, st:
    dict) -> None` (R41); `bridge_lock(paths, blocking: bool)` (a context
    manager over `fcntl.flock` on `bridge.lock`; raises `LockBusy` when
    non-blocking and held); `LockBusy(Exception)`; `parse_ts(s: str) ->
    float`; `fmt_since(t: float) -> str`; `iso_now(t: float) -> str`;
    `Ctx(cfg, paths, cli, log, notify, now=time.time)` (a plain holder
    with those attributes; `notify(kind: str, text: str) -> None`).
  - `bridge.studio`: `VERB_TIMEOUT = 30`; `KNOWN_EVENTS: frozenset`; `LogShrunk(Exception)`;
    `read_registry(home: str) -> list[dict]` (keys `file`, `root`,
    `start`, `run`, `pid`, `started`, and `origin` — the raw value, `None`
    when the line is absent; R55); `origin_task(origin: str | None) -> str
    | None` (the text after a leading `multica:` when it fully matches
    `[A-Za-z0-9-]+`, else None; `new_run_state` uses it to fill
    `request.task`, with `request.state` `"none"` when it is None);
    `runner_live(pid) -> bool`;
    `read_link(paths, task_id: str) -> dict | None`;
    `delete_link(paths, task_id: str) -> None`; `prune_links(paths, now:
    float) -> None`; `issue_from_workdir(workdir: str) -> str | None`;
    `read_lines(path: str, offset: int) -> list[tuple[int, int, bytes]]`
    (start, end, line without `\n`; complete lines only; raises
    `FileNotFoundError`, and `LogShrunk` when the size is below `offset`);
    `unread_count(path: str, offset: int) -> int`; `parse_event(line:
    bytes) -> tuple[str, dict | None]` (`"ok"`, `"bad"`, `"unknown"`,
    `"version"`); `call_verb(path: str, root: str, args: list[str],
    timeout: float | None = None) -> tuple[int, str, str, bool]` (exit,
    stdout, stderr, timed_out).
  - `tests/stub-studio-overnight`, and in `bridgetest`:
    `make_project(tmp, name) -> str` (a root with `.studio/reports/`),
    `Run` (`make_run(home, root, basename="overnight-20261003-2214",
    live=True, origin=None) -> Run` (`origin` given → the entry gets an
    `origin=<value>` line after `started=`, as T2's `reg_write` writes it); attributes `root`,
    `run_dir`, `events`, `pid`, `entry`; methods `append(*events)`,
    `append_raw(text: str)`, `end_entry()` (moves the entry to
    `runs/last`), `kill()`), and `ev(event: str, **fields) -> dict`
    (adds `v` 1, `ts`, `run`).

**Run state schema** (`state/<run key>.json`, one dict; `new_run_state`
fills every key):

```python
{
  "key": "overnight-20261003-2214-1a2b3c4d", "pid": 4242, "started": "2026-10-03T22:14:05Z",
  "origin": "multica:01a102e8-d4ad-7157-ac66-6d25f8ec1ce3",     # the entry's origin= value, or None
  "root": "/Users/…/my-game", "run_dir": "/Users/…/.studio/reports/overnight-20261003-2214",
  "adopted_at": 1791000000.0,
  "request": {"state": "pending", "task": "01a102e8-d4ad-7157-ac66-6d25f8ec1ce3", "issue": None,
              "since": 1791000000.0},          # task = studio.origin_task(origin); None → state "none"
  "run_issue": None, "mode": None,                        # mode: "single" | "manifest"
  "stories": {}, "story_desc": {}, "story_failed": [], "story_recreated": [],
  "offset": 0, "pending": None,                           # {"offset", "done": [write keys], "fails", "error"}
  "intended": {}, "last_set": {}, "hands_off": [], "held_back": {},   # ident → status
  "repair_stopped": [], "catchup": {},                    # ident → {"changes": [...], "units": n, "run_ended": bool}
  "cursors": {}, "cursor_ts": {}, "seen": {},             # ident → since str / newest float / {cid: ts}
  "posted": [], "clock_offset": 0.0, "journal": {},
  "ended": False, "gone_polls": 0, "retire_after_catchup": False, "retired": False,
}
```

**`parse_ts`** (full code; Review Focus 5):

```python
_TS = re.compile(r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})?$")

def parse_ts(s: str) -> float:
    m = _TS.match(s.strip())
    if not m:
        raise ValueError("bad timestamp: %r" % s)
    y, mo, d, h, mi, se, frac, tz = m.groups()
    t = datetime(int(y), int(mo), int(d), int(h), int(mi), int(se), tzinfo=timezone.utc).timestamp()
    if frac:
        t += int(frac.ljust(9, "0")) / 1e9
    if tz and tz != "Z":
        sign = 1 if tz[0] == "+" else -1
        t -= sign * (int(tz[1:3]) * 3600 + int(tz[-2:]) * 60)
    return t

def fmt_since(t: float) -> str:
    return datetime.fromtimestamp(math.floor(t), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
```

**`call_verb`** (full code; R27):

```python
def call_verb(path, root, args, timeout=None):
    env = {k: v for k, v in os.environ.items() if not k.startswith("MULTICA_")}
    p = subprocess.Popen([path] + list(args), cwd=root, env=env, stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        out, err = p.communicate(timeout=timeout if timeout is not None else VERB_TIMEOUT)
        timed_out = False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = p.communicate()
        timed_out = True
    return (p.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace"), timed_out)
```

**`runner_live`**: `os.kill(pid, 0)` (`PermissionError` = alive but not
ours → False) and `ps -o args= -p <pid>` contains `studio-overnight` (the
core's `reg_live`). **`read_registry`**: each `overnight-*` file (and
never `last`) as `key=value` lines, first value per key; an entry
without `root`, `run` or an integer `pid` is skipped (logged at debug);
`origin` is returned as written (the bridge, not the reader, decides what
it means — R55).
**`issue_from_workdir`**: `name = basename(dirname(workdir))`; match
`^([a-z0-9]+-\d+)-[0-9a-f]{12}$` (case-insensitive); return the group
upper-cased, else None (R21). **`read_link`**: `key=value` lines; None
when missing or without `task=`. **`prune_links`**: deletes link files
whose `written=` (else mtime) is more than 24 h before `now`.
**`parse_event`**: not JSON or not an object → `bad`; `v` an int > 1 →
`version`; `event` not in `KNOWN_EVENTS` (`run_started`, `story_listed`,
`story_state`, `unit_started`, `unit_ended`, `message_queued`,
`message_delivered`, `message_requeued`, `control`, `run_ended`) →
`unknown`; else `ok`.

**`tests/stub-studio-overnight`** (sh): `n` counter in `$STUB_SO_DIR`;
writes `n.argv` (each element followed by a NUL byte: `printf '%s\0' "$@"`, so text with newlines round-trips), `n.pwd` (`pwd -P`), `n.env` (`env
| grep '^MULTICA_' | sort`, usually empty), `n.ids` (`$$` and `ps -o
pgid= -p $$`), `n.stdin` (`cat` with a 1 s cap: `head -c 100`). Its
behaviour comes from `$STUB_SO_DIR/<verb>.script` (verb = first argument)
else `$STUB_SO_DIR/default.script`, else prints `ok` and exits 0. Script
lines: `out TEXT`, `err TEXT`, `exit N`, `sleep N`, `spawn` (starts
`sleep 300 &` and writes its pid to `grandchild.pid`).

- [ ] **Step 1: Write the failing tests.**
  `test_state.py` — `StateTest`: `test_parse_ts_variants` (`…05Z`,
  `…05.1Z`, `…05.123456789Z`, `…05+00:00`, `…05.5-07:00`, `…05+0200`, no
  zone; all equal the expected epoch; `"yesterday"` and `""` raise
  `ValueError`), `test_fmt_since_floors_to_utc_z`, `test_run_key_format`
  (`<basename>-<8 hex>`; the same basename under two roots gives two
  keys), `test_atomic_write_leaves_no_temp_and_is_0600`,
  `test_retire_moves_state_and_appends_key`,
  `test_lock_busy_when_held` (a child Python process holds the lock;
  `bridge_lock(paths, blocking=False)` raises `LockBusy`),
  `test_new_run_state_has_every_key`.
  `test_studio.py` — `StudioTest(BridgeCase)`:
  `test_read_registry_parses_and_skips_malformed`,
  `test_runner_live_for_studio_dummy`,
  `test_pid_reused_by_other_process` (Review Focus 4: a live `sleep 60`
  whose args lack `studio-overnight` → False; a reaped pid → False),
  `test_origin_task` (`multica:01a1-x` → `01a1-x`; `None`, `""`,
  `other:x`, `multica:`, `MULTICA:x`, `multica:a.b`, `multica:a:b` →
  None), `test_new_run_state_request_from_origin` (with → `pending` and
  the task; without → `none`),
  `test_read_registry_origin` (an entry with `origin=multica:t-1` →
  `"multica:t-1"`; without the line → `None`; an entry whose `origin=`
  is `other:x` → `"other:x"` unchanged), `test_read_link_and_prune`,
  `test_issue_from_workdir` (`…/omeg-4-6d25f8ec1ce3/workdir` → `OMEG-4`;
  `ab2-17-…` → `AB2-17`; no hex suffix → None),
  `test_read_lines_complete_only` (a torn tail is not returned; offsets
  are bytes with a multi-byte UTF-8 line before), `test_read_lines_shrunk`
  (`LogShrunk`), `test_parse_event_kinds`, `test_call_verb_argv_cwd_env`
  (argv exact, cwd the root, no `MULTICA_*` even though the test sets
  `MULTICA_TOKEN` in `os.environ`, stdin empty, pgid == pid),
  `test_call_verb_timeout_kills_group` (`spawn` then `sleep 60`;
  `VERB_TIMEOUT` patched to 2; returns `timed_out` True within 5 s;
  the grandchild pid is gone).
- [ ] **Step 2: Run them to see them fail.**
  Run: `cd integrations/multica/tests && /usr/bin/python3 -m unittest test_state test_studio`
  Expected: FAIL — `ImportError` for `bridge.state`.
- [ ] **Step 3: Implement** the two modules, the two stubs (`chmod 755`)
  and the `bridgetest` additions (`Run` keeps a list of live dummies and
  kills them in `tearDown`; the dummy is `sh -c 'sleep 600; :'
  studio-overnight`, as the core's `live_dummy`).
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0.
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/bridge/state.py integrations/multica/bridge/studio.py integrations/multica/tests
git commit -m "feat(multica): run state and the studio side of the bridge (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 6: Mirror part 1 — adoption, the request issue, Run and story issues, event mapping
Files: integrations/multica/bridge/mirror.py, integrations/multica/tests/bridgetest.py, integrations/multica/tests/test_mirror_runs.py
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L358-405, docs/game-dev/specs/2026-10-03-multica-integration.md:L429-445, docs/game-dev/specs/2026-10-03-multica-integration.md:L500-512, docs/game-dev/specs/2026-10-03-multica-integration.md:L629-667, docs/game-dev/specs/2026-10-03-multica-integration.md:L730-749
Review: task

**Interfaces:**
- Consumes: T4 `Cli` and its exceptions, `sanitize`; T5 `state.*`,
  `studio.*`, `Ctx`; D1b (P2) and D1d (P4: `origin=`).
- Produces (`bridge.mirror`): constants `STATUS` (story state → status
  key), `TERMINAL_STATUS = ("done", "cancelled")`, `TERMINAL_CATEGORIES`
  (R14, names as D1g records), `REQUEST_LIMIT_SECONDS = 300`,
  `PERMANENT_ATTEMPTS = 3`, `GONE_POLLS = 3`, `LOG_GONE` (the R19 note);
  `cost(usd) -> str`; `event_writes(st: dict, ev: dict) -> list[tuple[str,
  str, str]]` (pure); `adopt(ctx) -> list[str]`; `resolve_request(ctx,
  st) -> None`; `ensure_run_issue(ctx, st) -> bool`;
  `ensure_story_issue(ctx, st, story: str, description: str) -> None`;
  `apply_events(ctx, st) -> None`; `set_intended(ctx, st, ident: str,
  status: str) -> None`; `write_status(ctx, st, ident: str) -> None`;
  `post_comment(ctx, st, ident: str, text: str, parent: str | None = None,
  count_held: bool = True) -> dict | None` (None = held back, T7);
  `note(ctx, st, text: str) -> None` (a comment on the Run issue);
  `retire(ctx, st) -> None`; `check_end_or_gone(ctx, st) -> None`;
  `poll_run(ctx, st) -> None`; `poll_runs(ctx) -> None` (adopt, prune
  links, then every tracked run; a `TransientError`/`AuthError` propagates
  after the run's state is saved). `ctx.rows: dict[str, dict]` is the
  per-poll issue cache (T7 fills it; empty in T6).
  - `bridgetest`: `MirrorCase(BridgeCase)` with `self.ctx` (a `Ctx`
    whose `notify` appends to `self.notes`), `poll()` (=
    `mirror.poll_runs(self.ctx)`), `run_issue(run) -> dict` and
    `story_issue(run, story) -> dict` (board lookups by property),
    `comments_on(ident) -> list[str]`, `status_calls() -> list[list[str]]`.

**`event_writes`** (full code — the mapping table, R16, AC12/AC13):

```python
STATUS = {"queued": "todo", "waiting": "todo", "running": "in_progress", "repair": "in_progress",
          "gate-repair": "in_progress", "landing": "in_progress", "held": "blocked",
          "landed": "done", "stopped": "cancelled", "skipped": "cancelled"}
TERMINAL_STATUS = ("done", "cancelled")


def cost(usd) -> str:
    try:
        return "$%.2f" % float(usd)
    except (TypeError, ValueError):
        return "cost unknown"


def event_writes(st, ev):
    """The writes one event asks for, in order, as (kind, target, value):
    kind "status" (value: status key), "comment" (value: the full text) or
    "story" (value: the story issue's description). target is "run" or a
    story id. Pure: reads st, writes nothing."""
    e, s = ev.get("event"), str(ev.get("story", "-"))
    single = st.get("mode") == "single" or s == "-"
    routed = s in st["story_failed"]              # AC12: its issue could not be made
    tgt = "run" if (single or routed) else s
    pre = "studio: [%s] " % s if routed else "studio: "

    def say(text):
        return ("comment", tgt, pre + text)

    if e == "run_started":
        return [("status", "run", "in_progress"), ("comment", "run", "studio: run started (%s)" % ev.get("mode", "?"))]
    if e == "story_listed":
        if single:
            return []
        deps = ev.get("depends") or []
        chain = ev.get("chain")
        chain = ", ".join(map(str, chain)) if isinstance(chain, list) else str(chain or "-")
        return [("story", s, "Story %s of run %s. Chain: %s. Depends on: %s." % (
            s, os.path.basename(st["run_dir"]), chain, ", ".join(map(str, deps)) or "none"))]
    if e == "story_state":
        out, state_ = [], ev.get("state")
        status = STATUS.get(state_)
        if status and not routed and not (tgt == "run" and status in TERMINAL_STATUS):
            out.append(("status", tgt, status))
        if state_ == "held":
            out.append(say("held: %s — until %s — /say, /resume or /stop" % (ev.get("why", "?"), ev.get("until", "?"))))
        elif state_ in ("stopped", "skipped"):
            out.append(say("%s: %s" % (state_, ev.get("why", "?"))))
        return out
    if e == "unit_started":
        return [say("unit %s (%s) started" % (ev.get("unit"), ev.get("label")))]
    if e == "unit_ended":
        return [say("unit %s (%s) ended: %s, %s" % (ev.get("unit"), ev.get("label"), ev.get("outcome"), cost(ev.get("usd"))))]
    if e == "message_queued":
        return [say("message %s queued (%s)" % (ev.get("id"), ev.get("scope")))]
    if e == "message_delivered":
        return [say("message %s delivered to unit %s" % (ev.get("id"), ev.get("unit")))]
    if e == "message_requeued":
        return [say("message %s not recorded by unit %s; requeued (%s)" % (ev.get("id"), ev.get("unit"), ev.get("requeues")))]
    if e == "control":
        return [say("%s by operator" % ev.get("action"))]
    if e == "run_ended":   # comment first: closing wakes the agent, which reads it (R17)
        return [("comment", "run", "studio: run ended: %s — report: %s" % (ev.get("ending"), ev.get("report"))),
                ("status", "run", "done")]
    return []
```

**`apply_events` and the per-event progress** (full code — R11, R17,
R18, R19, AC16, AC27):

```python
def _events_path(st):
    return os.path.join(st["run_dir"], "events.jsonl")


def apply_events(ctx, st):
    try:
        lines = studio.read_lines(_events_path(st), st["offset"])
    except FileNotFoundError:
        if not os.path.isdir(st["run_dir"]):
            note(ctx, st, LOG_GONE)
            retire(ctx, st)
        return
    except studio.LogShrunk:
        note(ctx, st, LOG_GONE)
        retire(ctx, st)
        return
    for start, end, raw in lines:
        kind, ev = studio.parse_event(raw)
        if kind == "version":
            note(ctx, st, "studio: event log version %s is newer than this bridge reads (1) — mirroring stopped" % ev.get("v"))
            retire(ctx, st)
            return
        if kind in ("bad", "unknown"):
            ctx.log.warning("run %s: skipped %s event line at byte %d", st["key"], kind, start)
        else:
            if ev["event"] == "run_started":
                st["mode"] = "single" if ev.get("mode") == "single" else "manifest"
            if ev["event"] == "story_state" and ev.get("state") not in STATUS:
                ctx.log.warning("run %s: unknown story state %r left the status unchanged", st["key"], ev.get("state"))
            if not _apply_one(ctx, st, start, ev):
                return                                    # retried on the next poll
            if ev["event"] == "run_ended":
                st["ended"] = True
        st["offset"], st["pending"] = end, None
        state.save_run(ctx.paths, st)


def _apply_one(ctx, st, offset, ev):
    """True when the event is finished (all writes done, or skipped)."""
    p = st["pending"]
    if not p or p["offset"] != offset:
        p = st["pending"] = {"offset": offset, "done": [], "fails": 0, "error": ""}
    try:
        for i, w in enumerate(event_writes(st, ev)):
            if i in p["done"]:
                continue
            _do_write(ctx, st, w)                         # TransientError propagates
            p["done"].append(i)
            state.save_run(ctx.paths, st)
        return True
    except mc.PermanentError as e:
        p["fails"] += 1
        p["error"] = str(e)
        state.save_run(ctx.paths, st)
        if p["fails"] < PERMANENT_ATTEMPTS:
            return False
        ctx.log.error("run %s: skipped %s after %d failed polls: %s", st["key"], ev.get("event"), p["fails"], e)
        note(ctx, st, "studio: skipped %s (story %s) after %d failed attempts: %s"
             % (ev.get("event"), ev.get("story", "-"), PERMANENT_ATTEMPTS, e))
        return True
```

  `_do_write(ctx, st, (kind, tgt, value))`: `story` →
  `ensure_story_issue(ctx, st, tgt, value)`; otherwise `ident` =
  `st["run_issue"]` for `run`, else `st["stories"].get(tgt)` (a story
  with no issue yet — its `story_listed` was skipped — goes to the Run
  issue with the `[<story>]` prefix and no status); `status` →
  `set_intended`; `comment` → `post_comment`. A `NotFoundError` on a
  story issue whose story is not yet in `story_recreated`: append it,
  drop `stories[tgt]`, call `ensure_story_issue(ctx, st, tgt,
  st["story_desc"][tgt])` and retry the write once (AC12's "recreated at
  most once"); otherwise re-raise.

**`resolve_request`** (full code — AC9, R21, R22, R55):

```python
def resolve_request(ctx, st):
    rq = st["request"]
    if rq["state"] != "pending":
        return
    link = studio.read_link(ctx.paths, rq["task"])
    agent = (link or {}).get("agent")
    tried = set()
    try:
        found = None
        first = studio.issue_from_workdir((link or {}).get("workdir", ""))
        if first:
            tried.add(first)
            found = _confirm(ctx, first, rq["task"])
        if not found and agent:
            for row in ctx.cli.assigned_issues(agent):
                ident = row.get("identifier")
                if ident and ident not in tried:
                    tried.add(ident)
                    found = _confirm(ctx, ident, rq["task"])
                    if found:
                        break
    except mc.TransientError:
        if ctx.now() - rq["since"] > REQUEST_LIMIT_SECONDS:
            ctx.log.warning("run %s: request issue unresolved after 5 min; Run issue goes top level", st["key"])
            rq["state"] = "none"
        return
    rq["state"], rq["issue"] = ("found", found) if found else ("none", None)
    if link:
        studio.delete_link(ctx.paths, rq["task"])


def _confirm(ctx, ident, task):
    try:
        return ident if any(r.get("id") == task for r in ctx.cli.issue_runs(ident)) else None
    except mc.PermanentError:          # includes NotFoundError: an unconfirmed candidate
        return None
```

  `adopt` (AC8): reads `studio.read_registry(ctx.paths.home)`; skips an
  entry whose `root` is not in `cfg.roots` (when set), whose runner is not
  live, or whose key is tracked or retired; else writes
  `new_run_state(key, entry, now)`, which stores the entry's `origin`
  and fills `request` from `studio.origin_task(origin)` (None →
  `request.state = "none"`: no request issue, AC9).
  `ensure_run_issue` (AC10): `find_issues(key, None)` → reuse the first
  row; else `create_issue("Run " + basename, <description: run dir, root,
  key, "comment /stop run to stop it">, parent=request issue,
  {"omega_run": key})`; a `PermanentError` with a parent → once more with
  `parent=None`; a second failure (or a first one without a parent) →
  log, `ctx.notify("create", "omega bridge: could not create the Run
  issue for <basename>")`, `retire`, return False. On success set
  `intended[run]`/`last_set[run]` to `todo`. `ensure_story_issue` (AC12):
  stores `story_desc[story]`; `find_issues(key, story)` → reuse; else
  `create_issue(story, description, parent=run issue, {"omega_run": key,
  "omega_story": story})`; a `PermanentError` → append to `story_failed`
  and `note` "studio: [<story>] its issue could not be created (<error>);
  its events go here". `post_comment` (T6 form): `t0 = ctx.now()`; `c =
  ctx.cli.add_comment(ident, text, parent)`; append `c["id"]` to `posted`
  (keep the last 500); `clock_offset = parse_ts(c["created_at"]) - t0`
  (AC24); return `c`. `write_status` (T6 form): skip when `last_set[ident]
  == intended[ident]`, else `set_status` and record `last_set`.
  `check_end_or_gone` (AC15): `ended` → `retire` (T7 adds the hands-off
  wait); else `runner_live(st["pid"])` resets `gone_polls`; not live →
  `gone_polls += 1`; at `GONE_POLLS` → `note` "studio: runner gone, no
  clean end — see `studio-overnight status`" and `retire`. `poll_run`
  order: forbid the request issue on `ctx.cli` → `resolve_request` (still
  `pending` → save, return) → `ensure_run_issue` → (T7: `refresh`,
  `reconcile`) → `apply_events` → (T8: `commands.poll_commands`) →
  `check_end_or_gone` → save unless retired.

- [ ] **Step 1: Write the failing tests** — `test_mirror_runs.py`,
  `MirrorRunsTest(MirrorCase)`:
  - `test_adopt_live_only` (a dead entry and a live one: one key),
    `test_adopt_respects_roots`, `test_retired_never_readopted`,
    `test_stored_pid_after_entry_moves_to_last` (`end_entry()` while the
    dummy lives: still polled; after `kill()`, the gone count runs on the
    stored pid);
  - `test_same_basename_two_roots` (Review Focus 3: two projects, one run
    dir basename → two keys, two Run issues, each story issue under its
    own Run issue);
  - `test_request_from_link_confirmed` (the run made with
    `origin="multica:<task>"`; link workdir `omeg-4-…`,
    `issue runs OMEG-4` holds the task id → Run issue `--parent OMEG-4`;
    the link file is deleted);
  - `test_request_link_refuted_then_assignee_search` (OMEG-4's runs lack
    the id; OMEG-9, assigned to the agent, has it → parent OMEG-9);
  - `test_request_origin_absent_or_foreign_top_level` (no `origin=`,
    `origin=other:x`, `origin=multica:a.b` → no `issue runs` call, a
    top-level Run issue), `test_request_no_match_top_level`;
  - `test_request_transient_then_fallback_after_5min` (a forever fault on
    `issue runs`; `ctx.now` advanced 299 s → no Run issue; 301 s → a
    top-level Run issue);
  - `test_old_links_pruned` (a link `written=` 25 h ago is deleted);
  - `test_run_issue_lookup_reuses` (an existing issue with the property:
    no `issue create`);
  - `test_run_issue_create_args` (argv holds `--title`, `Run <basename>`,
    `--status todo`, `--allow-duplicate`, `--property omega_run=<key>`,
    `--description-stdin`, no `--assignee-id`, no `--stage`);
  - `test_run_issue_parent_create_fails_retries_top_level`,
    `test_run_issue_both_fail_retires_and_notifies`;
  - `test_story_listed_creates_story_issue` (stories `A` and `1`: title,
    parent, both properties, description names chain and dependencies);
  - `test_story_create_failure_routes_to_run_issue` (one note; that
    story's later comments on the Run issue prefixed `studio: [A] `; no
    status call for it);
  - `test_story_issue_missing_recreated_once` (`remove_issue` → a new
    issue; removed again → three failing polls then the skip note);
  - `test_event_mapping_rows` (one `subTest` per table row of spec
    632-646: the status call and the exact comment text);
  - `test_usd_unknown` (`usd` null, `""`, `"n/a"` → `cost unknown`;
    `1.5` → `$1.50`);
  - `test_single_plan_routes_to_run_issue` (story `-`: no story issues;
    `held` → Run issue `blocked`; `landed` → no status call; `run_ended`
    → `done`);
  - `test_every_comment_prefixed` (every `issue comment add` stdin starts
    `studio: `);
  - `test_torn_last_line_kept` (`append_raw` half a line: not applied;
    completed: applied once);
  - `test_offset_kept_after_transient` (a fault on `issue comment add`
    with a 503 text → `TransientError` out of `poll()`; the offset is
    unchanged; next poll applies it);
  - `test_partial_event_progress_not_repeated` (`run_ended`: comment ok,
    status fails transient; next poll → one status call, the comment not
    re-posted);
  - `test_permanent_failure_skipped_after_three_polls` (one note naming
    the event; the next event then applies);
  - `test_runner_gone_after_two_more_polls` (kill: polls 1 and 2 no
    comment, poll 3 the comment, retired; statuses untouched);
  - `test_unknown_event_and_bad_line_skipped`;
  - `test_version_2_stops_and_retires`;
  - `test_event_log_shrunk_or_vanished_retires` (Review Focus 2: a log
    truncated below the offset → `LOG_GONE` note, retired, nothing
    replayed; a second run whose run dir is removed → the same);
  - `test_run_ended_comment_before_done`;
  - `test_no_start_on_every_status_call`;
  - `test_request_issue_never_written` (no `issue status`/`issue comment
    add` call names the request issue);
  - `test_sanitizer_on_relayed_fields` (`why` and `report` holding
    `[x](mention://agent/1)`, `@all`, a ```` ```mermaid ```` fence →
    sanitized in the stub's recorded stdin).
- [ ] **Step 2: Run them to see them fail.**
  Run: `cd integrations/multica/tests && /usr/bin/python3 -m unittest test_mirror_runs`
  Expected: FAIL — `ImportError: bridge.mirror`.
- [ ] **Step 3: Implement** `mirror.py` and the `bridgetest` additions.
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0.
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/bridge/mirror.py integrations/multica/tests
git commit -m "feat(multica): mirror runs as Run and story issues (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 7: Mirror part 2 — intended status, hands-off, catch-up and repair
Files: integrations/multica/bridge/mirror.py (`post_comment`, `write_status`, `poll_run`, `check_end_or_gone` from T6; new `refresh`, `reconcile`, `catch_up`, `hands_off_now`, `is_hands_off`, `is_terminal`, `stop_repair`), integrations/multica/tests/test_mirror_status.py
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L406-428, docs/game-dev/specs/2026-10-03-multica-integration.md:L437-438, docs/game-dev/specs/2026-10-03-multica-integration.md:L735-740, docs/game-dev/specs/2026-10-03-multica-integration.md:L804-809
Review: task

**Interfaces:**
- Consumes: T6 (`st` keys `intended`, `last_set`, `hands_off`,
  `held_back`, `repair_stopped`, `catchup`, `retire_after_catchup`;
  `post_comment`, `write_status`, `note`, `retire`); `Cli.run_issues`,
  `Cli.get_issue`.
- Produces: `is_hands_off(row: dict) -> bool` (`assignee_type` is
  `agent` or `squad`); `is_terminal(row: dict) -> bool` (R14);
  `refresh(ctx, st) -> None` (one paged `issue list` per run per poll →
  `ctx.rows`; hands-off transitions); `hands_off_now(ctx, st, ident) ->
  bool` (the AC14.1 re-read); `reconcile(ctx, st) -> None`;
  `catch_up(ctx, st, ident) -> None`; `stop_repair(ctx, st, ident, why:
  str) -> None`. `post_comment` now returns None when the issue is
  hands-off (counting the comment for catch-up when `count_held`).

**`write_status` with the reconcile rules** (full code — R15):

```python
def is_terminal(row):
    return row.get("status") in TERMINAL_STATUS or row.get("status_category") in TERMINAL_CATEGORIES


def write_status(ctx, st, ident):
    intended = st["intended"].get(ident)
    if intended is None or ident in st["repair_stopped"]:
        return
    if ident in st["hands_off"]:
        _held_change(st, ident, intended)
        return
    row = ctx.rows.get(ident)
    if row is not None and row.get("status") == intended:
        st["last_set"][ident] = intended                      # AC14.4: applied, even after a timeout
        return
    if row is not None and is_terminal(row):
        stop_repair(ctx, st, ident, "%s was set to %s by someone else" % (ident, row.get("status")))
        return
    if row is not None and intended in TERMINAL_STATUS and st["last_set"].get(ident) == intended:
        stop_repair(ctx, st, ident, "%s was reopened by someone else" % ident)
        return
    if (intended in TERMINAL_STATUS and ident != st["run_issue"]
            and st["run_issue"] in st["hands_off"]):
        st["held_back"][ident] = intended                     # AC14.2
        return
    if hands_off_now(ctx, st, ident):                         # AC14.1 re-read
        _held_change(st, ident, intended)
        return
    ctx.cli.set_status(ident, intended)
    st["last_set"][ident] = intended
    if row is not None:
        row["status"] = intended


def _held_change(st, ident, status):
    cu = st["catchup"].setdefault(ident, {"changes": [], "units": 0, "run_ended": ""})
    if not cu["changes"] or cu["changes"][-1] != status:
        cu["changes"].append(status)


def stop_repair(ctx, st, ident, why):
    st["repair_stopped"].append(ident)
    note(ctx, st, "studio: %s — the bridge leaves its status alone from now on" % why)
```

  `hands_off_now`: `ident in st["hands_off"]` → True; else
  `ctx.cli.get_issue(ident)` (stored in `ctx.rows`), and when
  `is_hands_off` → append to `hands_off`, True. `post_comment` (final
  form): `hands_off_now` → when `count_held`: a text starting `studio: run
  ended:` is kept in `catchup[ident]["run_ended"]`, any other adds 1 to
  `catchup[ident]["units"]`; return None. Otherwise as in T6.
  `refresh`: `rows = ctx.cli.run_issues(st["key"])` (`--limit 100`, paged
  on `has_more`; one call per page); `ctx.rows` = rows by identifier; for
  each mirrored identifier (the Run issue and `stories` values): newly
  hands-off → append; was hands-off and is not now → `catch_up`.
  `reconcile`: `write_status` for every identifier in `intended` (the
  rules skip repair-stopped, hands-off and held-back ones).
  `catch_up(ident)` (R40): remove from `hands_off`; pop its `catchup`
  record; post `studio: while assigned: <s1> → <s2> …, <n> unit events`
  (`no state changes` when none); post the held `run ended` text if any;
  `write_status(ident)`; when `ident` is the Run issue, `write_status` for
  each `held_back` story and clear `held_back`, then `retire` when
  `retire_after_catchup`. `check_end_or_gone`: with `ended` and the Run
  issue hands-off → `retire_after_catchup = True` instead of retiring.
  `poll_run` gains `refresh(ctx, st)` and `reconcile(ctx, st)` between
  `ensure_run_issue` and `apply_events`.

- [ ] **Step 1: Write the failing tests** — `test_mirror_status.py`,
  `MirrorStatusTest(MirrorCase)`:
  - `test_one_list_per_run_per_poll_paged` (120 mirrored issues → two
    `issue list` calls per poll, `--offset 0` and `100`);
  - `test_agent_assigned_story_gets_zero_writes` (no `issue status` or
    `issue comment add` call names it while assigned, through a `held`,
    two units and `landed`);
  - `test_squad_assignee_is_hands_off`, `test_member_assignee_is_not`;
  - `test_assignee_appears_between_list_and_write` (the test wraps
    `mirror.refresh` so the real one runs and then
    `self.board.assign(<story issue>, "agent", "ag-1")`; the next write's
    `issue get` re-read finds the agent, and no `issue status` or `issue
    comment add` call names that issue);
  - `test_run_issue_hands_off_holds_story_closures` (`landed` while the
    Run issue is assigned → story stays `in_progress` on the board; on
    unassign → `done`);
  - `test_catch_up_on_unassign` (one comment `studio: while assigned:
    in_progress → blocked, 2 unit events`, then the status call);
  - `test_run_ended_while_hands_off_retired_after_catch_up` (not retired
    while assigned; on unassign: catch-up, the `run ended` comment, then
    `done`, then retired);
  - `test_non_terminal_drag_set_back` (operator drags to `todo` → set
    back to `in_progress` with `--no-start`);
  - `test_done_by_someone_else_left_alone_with_note` (one note; no
    further status calls for it, even after more events);
  - `test_reopen_left_alone_with_note`;
  - `test_timed_out_write_found_applied_counts_success` (fault on `issue
    status` with `apply: true` and a timeout text; next poll: no second
    `issue status` call, the event completes);
  - `test_custom_status_is_non_terminal` (current `in_review` → set back);
  - `test_no_start_on_every_status_call` (every `issue status` call in
    this file's runs carries `--no-start`).
- [ ] **Step 2: Run them to see them fail.**
  Run: `cd integrations/multica/tests && /usr/bin/python3 -m unittest test_mirror_status`
  Expected: FAIL — writes reach assigned issues; no catch-up comment.
- [ ] **Step 3: Implement** the functions above.
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0 (T6's tests unchanged and green).
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/bridge/mirror.py integrations/multica/tests/test_mirror_status.py
git commit -m "feat(multica): intended statuses, hands-off issues, catch-up and repair (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 8: Comment commands — cursor, author filter, parsing, journal, replies
Files: integrations/multica/bridge/commands.py, integrations/multica/bridge/mirror.py (`poll_run`: the commands step), integrations/multica/tests/test_commands.py
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L450-496, docs/game-dev/specs/2026-10-03-multica-integration.md:L750-766
Review: task

**Interfaces:**
- Consumes: `ctx.rows` and `st["hands_off"]` (T7), `mirror.post_comment(…,
  count_held=False)`, `studio.call_verb`, `state.parse_ts`,
  `state.fmt_since`, `Cli.list_comments`, `mc.sanitize`, `mc.PREFIX`;
  the #27 verbs with A1/A2 (`--run`, text after `--`).
- Produces (`bridge.commands`): `COMMANDS`, `STALE_SECONDS = 600`,
  `REPLY_CUT = 1000`, `OVERLAP_SECONDS = 60`, `WARN`, `HELP`;
  `parse(content: str) -> tuple[str | None, str | None]`;
  `plan_call(word: str, text: str, where: str, story: str | None, single:
  bool, basename: str) -> tuple[str, object]` (`("call", argv)`,
  `("reply", text)` or `("ignore", None)`); `near_miss(word: str) -> bool`;
  `format_reply(code: int, out: str, err: str, timed_out: bool) -> str`;
  `recover_journal(ctx, st) -> None`; `poll_commands(ctx, st) -> None`.
  `mirror.poll_run` calls `commands.poll_commands(ctx, st)` after
  `apply_events` (imported inside the function: `commands` imports
  `mirror`).

**Parsing and the call table** (full code — R23, AC21, AC25):

```python
"""Comment commands on Multica issues → core verbs (#28, AC20–AC25)."""
from __future__ import annotations

import os
import re

from bridge import mirror, state, studio
from bridge import multica_cli as mc

STALE_SECONDS = 600
REPLY_CUT = 1000
OVERLAP_SECONDS = 60
COMMANDS = ("say", "unit", "hold", "resume", "stop", "unsay", "said")
WARN = "studio: ⚠ may or may not have applied — check `/said` or the board"
HELP = ("studio: commands — on a story issue: /say <text>, /unit <text>, /hold, /resume, /stop, "
        "/unsay <id>, /said; on the Run issue: /stop run (a single-plan run takes every command there)")
_WORD = re.compile(r"(\S*)(.*)", re.S)


def parse(content):
    lines = content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    for i, line in enumerate(lines):
        if line.strip():
            first = line.lstrip()
            break
    else:
        return None, None
    if not first.startswith("/"):
        return None, None
    word, tail = _WORD.match(first[1:]).groups()
    return word.lower(), "\n".join([tail] + lines[i + 1:]).strip()


def _lev(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def near_miss(word):
    return bool(word) and word not in COMMANDS and any(_lev(word, c) <= 2 for c in COMMANDS)


def plan_call(word, text, where, story, single, basename):
    tok = text.split()[0] if text.split() else ""
    run_cmd = word == "stop" and tok.lower() == "run"
    if where == "story" or single:
        s = story if where == "story" else "-"
        if run_cmd:
            if where == "story":
                return "reply", "studio: ✗ /stop run works on the Run issue; /stop here stops this story"
            return "call", ["stop", "--run", basename]
        if word in ("say", "unit"):
            if not text:
                return "reply", "studio: ✗ usage: /%s <text>" % word
            return "call", ["say", "--run", basename, s] + (["--unit"] if word == "unit" else []) + ["--", text]
        if word in ("hold", "resume", "stop", "said"):
            return "call", [word, "--run", basename, s]
        if word == "unsay":
            if not re.fullmatch(r"[0-9]+", tok):
                return "reply", "studio: ✗ usage: /unsay <id> — the id is the number /said lists"
            return "call", ["unsay", "--run", basename, s, tok]
    else:
        if run_cmd:
            return "call", ["stop", "--run", basename]
        if word == "stop":
            return "reply", "studio: ✗ on the Run issue use /stop run; /stop on a story issue stops that story"
        if word in COMMANDS:
            return "reply", "studio: ✗ /%s goes on the story's own issue" % word
    if near_miss(word):
        return "reply", HELP
    return "ignore", None


def format_reply(code, out, err, timed_out):
    ok = code == 0 and not timed_out
    body = (out if ok else err).strip()
    if timed_out:
        body = (body + "\n" if body else "") + "timed out after %d s" % studio.VERB_TIMEOUT
    if not body:
        body = "done" if ok else "exit %d" % code
    if len(body) > REPLY_CUT:
        body = body[:REPLY_CUT] + "…"
    return ("studio: ✓ " if ok else "studio: ✗ ") + body
```

**Reading comments and the journal** (full code — AC20, AC22–AC24,
R25, R43):

```python
def poll_commands(ctx, st):
    recover_journal(ctx, st)
    base = os.path.basename(st["run_dir"])
    targets = [(st["run_issue"], "run", None)] + [(i, "story", s) for s, i in st["stories"].items()]
    for ident, where, story in targets:
        row = ctx.rows.get(ident)
        if row is not None:
            _poll_issue(ctx, st, ident, row, where, story, base)


def _ts(c, default):
    try:
        return state.parse_ts(c["created_at"])
    except (KeyError, TypeError, ValueError):
        return default


def _poll_issue(ctx, st, ident, row, where, story, base):
    created = state.parse_ts(row["created_at"])
    since = st["cursors"].get(ident) or state.fmt_since(created)
    newest = st["cursor_ts"].get(ident, created)
    seen = st["seen"].setdefault(ident, {})
    for c in sorted(ctx.cli.list_comments(ident, since), key=lambda c: _ts(c, newest)):
        cid = c.get("id")
        if not cid or cid in seen:
            continue
        ts = _ts(c, newest)
        seen[cid], newest = ts, max(newest, ts)
        if ident in st["hands_off"] or cid in st["journal"] or not _actionable(ctx, st, c):
            continue                                      # R43: read, never acted on
        word, text = parse(c.get("content") or "")
        if word is None:
            continue
        kind, val = plan_call(word, text, where, story, st["mode"] == "single", base)
        if kind == "ignore":
            continue
        if ctx.now() + st["clock_offset"] - ts > STALE_SECONDS:    # AC24, server clock
            kind, val = "reply", "studio: ✗ too old, repost"
        _run(ctx, st, ident, c, kind, val)
    st["cursor_ts"][ident] = newest
    st["cursors"][ident] = state.fmt_since(newest - OVERLAP_SECONDS)
    st["seen"][ident] = {k: v for k, v in seen.items() if v >= newest - 2 * OVERLAP_SECONDS}


def _actionable(ctx, st, c):
    return (c.get("author_type") == "member" and c.get("author_id") == ctx.cfg.operator_member_id
            and c.get("id") not in st["posted"] and not (c.get("content") or "").startswith(mc.PREFIX))


def _run(ctx, st, ident, c, kind, val):
    cid = c["id"]
    entry = {"issue": ident, "parent": c.get("parent_id") or cid, "at": ctx.now(),
             "created_at": c.get("created_at"), "attempts": 0}
    if kind == "call":
        st["journal"][cid] = dict(entry, state="running")
        state.save_run(ctx.paths, st)                     # AC23.1: before the core runs
        code, out, err, timed_out = studio.call_verb(ctx.cfg.studio_overnight, st["root"], val)
        reply = format_reply(code, out, err, timed_out)
    else:
        reply = val
    st["journal"][cid] = dict(entry, state="result", reply=reply)
    state.save_run(ctx.paths, st)                         # AC23.2
    _post(ctx, st, cid)


def _post(ctx, st, cid):
    e = st["journal"][cid]
    if e["attempts"] and _already_posted(ctx, e):         # R25
        e["state"] = "done"
        state.save_run(ctx.paths, st)
        return
    e["attempts"] += 1
    state.save_run(ctx.paths, st)
    try:
        posted = mirror.post_comment(ctx, st, e["issue"], e["reply"], parent=e["parent"], count_held=False)
    except mc.PermanentError as err:
        ctx.log.error("run %s: reply to %s not posted: %s", st["key"], cid, err)
        if e["attempts"] >= mirror.PERMANENT_ATTEMPTS:
            e["state"] = "done"
        state.save_run(ctx.paths, st)
        return
    if posted is not None:                                # None: hands-off now, kept for later
        e["state"] = "done"
        state.save_run(ctx.paths, st)


def _already_posted(ctx, e):
    t = _ts({"created_at": e.get("created_at")}, e["at"])
    want = mc.sanitize(e["reply"])
    return any(c.get("parent_id") == e["parent"] and c.get("content") == want
               for c in ctx.cli.list_comments(e["issue"], state.fmt_since(t - OVERLAP_SECONDS)))


def recover_journal(ctx, st):
    for cid, e in list(st["journal"].items()):
        if e["state"] == "running":                       # AC23.4: never run again
            e.update(state="result", reply=WARN)
            state.save_run(ctx.paths, st)
        if e["state"] == "result":                        # AC23.3: re-post, never re-run
            _post(ctx, st, cid)
    cutoff = ctx.now() - 86400
    st["journal"] = {k: v for k, v in st["journal"].items() if v["state"] != "done" or v["at"] >= cutoff}
```

- [ ] **Step 1: Write the failing tests** — `test_commands.py`:
  `ParseTest(unittest.TestCase)`:
  - `test_command_crlf_and_leading_blank_lines` (Review Focus 1:
    `"\r\n\r\n  /SAY  hello\r\nworld\r\n"` → `("say", "hello\nworld")`);
  - `test_plain_text_and_inner_slash_ignored`
    (`"hi\n/stop run"` → `(None, None)`);
  - `test_plan_call_table` (one `subTest` per AC21 row and every R23
    case: story `/say`, `/unit`, `/hold x` (text ignored), `/resume`,
    `/stop`, `/unsay 3`, `/said`; Run issue `/stop run`, `/STOP RUN`;
    single-plan Run issue: `/say t` → story `-`, bare `/stop` → `stop
    --run <b> -`; each wrong-place and malformed form → its ✗ text:
    empty `/say`, empty `/unit`, `/unsay x`, `/unsay ３` (a full-width
    digit), `/hold` on a manifest Run issue, `/stop run` on a story issue,
    bare `/stop` on a manifest Run issue);
  - `test_text_with_shell_characters_is_one_argument` (`$HOME`,
    backticks, both quotes, a newline, a leading `-n`, `--run x`,
    `--unit` → the argv's last element, after `--`, byte-exact);
  - `test_near_miss` (`/sya`, `/hodl`, `/stp` → HELP; `/deploy`, `/` and
    plain text → ignore);
  - `test_format_reply` (✓ stdout; ✗ stderr; cut at 1000 plus `…`;
    empty → `done` / `exit 3`; timeout → ✗ with `timed out after 30 s`).
  `CommandsTest(MirrorCase)` (a live run with stories A and B, polled once
  so the issues exist):
  - `test_say_reaches_core_and_replies_threaded` (stub verb argv `say
    --run <b> A -- hello`; cwd the run's root; reply `studio: ✓ ok` with
    `--parent <command id>`; a command that is itself a reply → `--parent`
    = its `parent_id`);
  - `test_verb_runs_in_its_own_root` (Review Focus 3: two runs with one
    basename; `/hold` on each run's story B → two verb calls, each `pwd`
    its own root, each `--run <b>`);
  - `test_unicode_text_roundtrip` (Review Focus 1: `/say héllo 🎮 世界`
    plus a second line `/stop run` → one `say` call whose text element is
    exactly `héllo 🎮 世界\n/stop run`; no `stop` call);
  - `test_author_filter` (agent author, another member, a comment the
    bridge posted, and an operator comment starting `studio: ` holding
    `/stop run` → no verb call);
  - `test_first_cursor_is_issue_created_at`, `test_cursor_overlap_and_dedup`
    (the second poll's `--since` is newest − 60 s floored; a comment seen
    twice runs once);
  - `test_since_format` (Review Focus 5: every recorded `--since` matches
    `^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$` while the board's `created_at`
    carries 6 fraction digits);
  - `test_hands_off_issue_commands_never_run` (assigned → read, not run;
    unassigned → still not run on later polls);
  - `test_reply_post_fails_then_reposted_once` (fault on `issue comment
    add` with a 503 text: one verb call; next poll the reply posted; still
    one verb call);
  - `test_crash_before_core_call_gives_warn` (patch `studio.call_verb` to
    raise `KeyboardInterrupt` after the `running` save; a fresh `Ctx`
    polls → ⚠ reply; the stub verb log has no call);
  - `test_crash_after_core_before_result_gives_warn` (patch
    `commands.format_reply` to raise; next poll → ⚠; one verb call);
  - `test_crash_after_reply_before_done_no_second_reply` (patch
    `mirror.post_comment` to post then raise; next poll → no second
    reply on the board; R26);
  - `test_stale_command_uses_clock_offset` (server 1 h behind local:
    after the bridge's own first comment, a command 5 min old on the
    server clock runs; one 11 min old gets `studio: ✗ too old, repost`
    and no verb call);
  - `test_timeout_kills_group_and_replies` (`say.script` = `spawn` +
    `sleep 60`; `studio.VERB_TIMEOUT` patched to 2 → ✗ reply ending
    `timed out after 2 s`; the grandchild is gone);
  - `test_reply_cut_and_sanitized` (a 3000-character stdout holding
    `@all` and `mention://member/1` → reply ≤ `len("studio: ✓ ") + 1001`
    characters, no `@`, `no-mention:`);
  - `test_journal_pruned_after_a_day`.
- [ ] **Step 2: Run them to see them fail.**
  Run: `cd integrations/multica/tests && /usr/bin/python3 -m unittest test_commands`
  Expected: FAIL — `ImportError: bridge.commands`.
- [ ] **Step 3: Implement** `commands.py`; add the step to
  `mirror.poll_run`.
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0.
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/bridge/commands.py integrations/multica/bridge/mirror.py integrations/multica/tests/test_commands.py
git commit -m "feat(multica): comment commands with an at-most-once journal (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 9: The service — `multica-bridge run|once|selftest|status`, lock, backoff, auth, logs
Files: integrations/multica/bridge/service.py, integrations/multica/bin/multica-bridge, integrations/multica/tests/test_service.py, integrations/multica/tests/test_end_to_end.py, integrations/multica/tests/wrappers_test.sh (`test_scripts_parse`: `multica-bridge` is executable)
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L500-534, docs/game-dev/specs/2026-10-03-multica-integration.md:L606-627, docs/game-dev/specs/2026-10-03-multica-integration.md:L652-667, docs/game-dev/specs/2026-10-03-multica-integration.md:L767-781, docs/game-dev/specs/2026-10-03-multica-integration.md:L117-121
Review: task

**Interfaces:**
- Consumes: everything in `bridge/` (T4–T8).
- Produces: `bin/multica-bridge` (argv `run`, `once`, `selftest`,
  `status`; exit codes R32); `bridge.service`: `BACKOFF_CAP = 300`,
  `AUTH_RETRY = 300`, `SELFTEST_INTERVAL = 600`, `DELAYED_NOTE_AFTER =
  300`, `OSASCRIPT` (default `/usr/bin/osascript`, test hook
  `OMEGA_MULTICA_OSASCRIPT`), `next_delay(poll: int, failures: int) ->
  int`, `setup_logging(paths) -> logging.Logger`, `class Service(home:
  str, log: logging.Logger | None = None)` with `poll_once() -> str`
  (`"ok"`, `"transient"`, `"auth"`, `"keychain"`, `"config"`),
  `selftest() -> dict`, `status_text() -> str`, `run() -> None`;
  `main(argv: list[str]) -> int`. Files: `selftest.json` (`ok`, `error`,
  `kind`, `interpreter`, `checked_at`, `checked`) — T10 reads it;
  `status.json` (R8).

**`poll_once`** (full code — AC26–AC28, R29, R30):

```python
"""multica-bridge service: poll loop, lock, backoff, auth, self-test, status (#28, R5)."""
from __future__ import annotations

import logging
import os
import subprocess
import sys
import time
from logging.handlers import RotatingFileHandler

from bridge import config, mirror, state, studio
from bridge import multica_cli as mc

BACKOFF_CAP = 300
AUTH_RETRY = 300
SELFTEST_INTERVAL = 600
DELAYED_NOTE_AFTER = 300
OSASCRIPT = os.environ.get("OMEGA_MULTICA_OSASCRIPT", "/usr/bin/osascript")   # test hook (R46)


def next_delay(poll, failures):
    return min(poll * (2 ** failures), BACKOFF_CAP) if failures else poll


class Service:
    def __init__(self, home, log=None):
        self.paths = state.Paths(home)
        self.log = log or setup_logging(self.paths)
        self.st = state.read_json(self.paths.status, None) or {
            "last_ok_poll": None, "cli_version": None, "failures": 0, "outage_since": None,
            "notified": [], "auth_until": 0}

    def notify(self, kind, text):
        if kind in self.st["notified"]:
            return                                        # once per outage (R30)
        self.st["notified"].append(kind)
        safe = text.replace("\\", "").replace('"', "'")
        try:
            subprocess.run([OSASCRIPT, "-e", 'display notification "%s" with title "omega multica bridge"' % safe],
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as e:
            self.log.warning("notification failed: %s", e)

    def poll_once(self):
        try:
            cfg = config.load(self.paths.config)
        except config.ConfigError as e:
            self.log.error("%s", e)
            return "config"
        now = time.time()
        if self.st["auth_until"] > now:
            return "auth"
        try:
            token = mc.read_token()
        except mc.KeychainError as e:                     # AC28: never a call without a token
            self.log.error("Keychain (%s): %s", e.kind, e)
            self.notify("keychain", "omega bridge: cannot read its Multica token from the Keychain")
            self._save()
            return "keychain"
        _set_secrets(self.log, [token])
        ctx = state.Ctx(cfg, self.paths, mc.Cli(cfg, token, self.paths.cli_home, self.log), self.log, self.notify)
        try:
            if not self.st["cli_version"]:
                self.st["cli_version"] = ctx.cli.version().get("version")
            mirror.poll_runs(ctx)
            outage = self.st["outage_since"]
            if outage and now - outage > DELAYED_NOTE_AFTER:
                self._delayed_notes(ctx, outage, int(round((now - outage) / 60.0)))
        except mc.AuthError as e:
            self.log.error("Multica rejected the token: %s", e)
            self.notify("auth", "omega bridge: Multica rejected its token — run install.sh --new-token")
            self.st["auth_until"] = now + AUTH_RETRY
            self._save()
            return "auth"
        except mc.TransientError as e:
            self.log.warning("Multica unreachable (%d failed polls): %s", self.st["failures"] + 1, e)
            self.st["failures"] += 1
            self.st["outage_since"] = self.st["outage_since"] or now
            self._save()
            return "transient"
        self.st.update(failures=0, outage_since=None, notified=[], auth_until=0,
                       last_ok_poll=state.iso_now(time.time()))
        self._save()
        return "ok"
```

  `_delayed_notes(ctx, outage, n)`: for each tracked run with a Run issue
  whose `delayed_for` (default None) is not `outage`: `mirror.post_comment(ctx,
  st, run_issue, "studio: board was delayed %d min" % n)`, then
  `st["delayed_for"] = outage`, save (a transient error mid-way leaves the
  rest for the next poll, never doubles). `_save()` writes `status.json`
  atomically. `_set_secrets(log, secrets)` sets the `RedactFilter`'s
  secrets on every handler. `setup_logging(paths)`: creates `paths.base`
  (0700) and `cli_home`; logger `multica-bridge`, INFO, `propagate =
  False`, one `RotatingFileHandler(paths.log, maxBytes=1_000_000,
  backupCount=5, encoding="utf-8")` with a `RedactFilter([])`, added once.
  `selftest()` (R31): `{"ok": False, "error": None, "kind": None,
  "interpreter": os.path.realpath(sys.executable), "checked_at": …,
  "checked": []}`; reads 1 byte of `cfg.studio_overnight`; lists each
  root's `.studio/` (`cfg.roots`, else the roots of live registry
  entries); `read_token()`; `Cli.profile()["id"] == operator_member_id`;
  `PermissionError` → `file-access` (error names the path and the
  interpreter), `FileNotFoundError` → `missing`, `ConfigError` →
  `config`, `KeychainError` → `keychain`, `AuthError` or an id mismatch →
  `token`, `TransientError` → `network`, other `CliError` → `cli`; writes
  `selftest.json` atomically. `run()`: self-test at start and every
  `SELFTEST_INTERVAL`; each poll under `state.bridge_lock(self.paths, blocking=True)`; an
  unexpected exception is logged with its traceback and counted as a
  failed poll; sleeps `AUTH_RETRY` after `"auth"`, else
  `next_delay(poll_seconds, failures)` (`poll_seconds` 15 when the config
  cannot load). `status_text()` (reads only): `cli: <version|unknown>`,
  `selftest: ok (<at>)` or `selftest: <kind>: <error> (<at>)` or
  `selftest: not run`, `last poll: <at|never>`, then one line per tracked
  run `run <key>: <Run issue|no Run issue yet>, <n> unread events`
  (`studio.unread_count`), or `no tracked runs`. `main`: unknown argv →
  usage on stderr, 2; `status` → `Service(home, log=<a logger with a
  NullHandler>)` (writes nothing), print, 0; `selftest` → print the JSON,
  0 if ok else 1; `once` → `state.bridge_lock(paths, blocking=False)`; `LockBusy` →
  stderr "multica-bridge: another bridge holds the lock", 1; `"config"`
  → 1; an unexpected exception → traceback on stderr, 1; else 0; `run` →
  `Service(home).run()`.

**`bin/multica-bridge`** (full code):

```python
#!/usr/bin/env python3
"""multica-bridge run|once|selftest|status — the omega-ai Multica bridge (#28)."""
import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
for _p in (HERE, os.path.dirname(HERE)):           # lib/ copy, or the repo checkout
    if os.path.isdir(os.path.join(_p, "bridge")):
        sys.path.insert(0, _p)
        break
from bridge import service  # noqa: E402

sys.exit(service.main(sys.argv[1:]))
```

- [ ] **Step 1: Write the failing tests.**
  `test_service.py` — `ServiceTest(MirrorCase)` (security stubbed through
  `multica_cli.SECURITY`, osascript through `service.OSASCRIPT` = a stub
  that appends its argv to a file):
  - `test_next_delay` (15, 30, 60, 120, 240, 300, 300; reset after ok);
  - `test_transient_counts_and_resets` (a forever 503 fault → `transient`
    ×3, `failures` 3; fault removed → `ok`, `failures` 0);
  - `test_delayed_note_after_long_outage` (time patched: first failure at
    t, recovery at t+360 → one `studio: board was delayed 6 min` per Run
    issue; a second `ok` poll posts none);
  - `test_no_delayed_note_for_short_outage` (recovery at t+200);
  - `test_auth_error_notifies_once_and_waits` (an unauthorized fault →
    `auth`, one osascript call; the next poll within 300 s makes no CLI
    call and no second notification; after 300 s it retries);
  - `test_keychain_locked_reported_separately_no_cli_call` (`locked` →
    `keychain`, one notification naming the Keychain, `calls.jsonl`
    absent);
  - `test_token_never_in_logs_state_or_verb_env` (after a full run with a
    command: TOKEN appears in no file under `~/.claude-gamedev/multica/`
    and in no `n.env` of the stub verb);
  - `test_selftest_ok`, `test_selftest_file_access_error` (a root's
    `.studio` `chmod 000` → `kind` `file-access`, the error names the
    path; restored in `finally`), `test_selftest_token_mismatch`,
    `test_selftest_roots_empty_uses_live_runs`;
  - `test_status_prints_and_writes_nothing` (snapshot of names and
    mtimes under the state dir unchanged; output has `cli:`,
    `selftest:`, `last poll:`, the run line with its Run issue and
    unread count);
  - `test_once_refused_while_lock_held` (a child holds `bridge.lock`;
    `bin/multica-bridge once` with `HOME` set exits 1);
  - `test_log_rotation_settings` (the handler's `maxBytes` 1_000_000 and
    `backupCount` 5).
  `test_end_to_end.py` — `EndToEndTest(MirrorCase)`: the bridge as a
  subprocess (`[sys.executable, bin/multica-bridge, "once"]`, env `HOME`,
  `OMEGA_MULTICA_SECURITY`, `STUB_SECURITY_DIR`, `OMEGA_MULTICA_OSASCRIPT=/usr/bin/true`,
  `STUB_SO_DIR`); one live run, events appended between `once` calls, a
  stub verb; the script: `run_started` + two `story_listed` → once →
  Run issue and two story issues; A `running` + `unit_started` → once →
  A `in_progress` and its comment; the operator's `/say hello` on A →
  once → verb `say --run <b> A -- hello` and a ✓ reply;
  `message_queued`/`message_delivered` → once → both comments; `/hold`
  on B → once → `hold --run <b> B` ✓; B `held` → once → `blocked` and the
  held comment; `/resume` on B → once → ✓; `run_ended` → once → the
  comment then `done`; once → the run retired. Assert each event and
  each command shows on the board after exactly one `once` (feel
  targets).
- [ ] **Step 2: Run them to see them fail.**
  Run: `cd integrations/multica/tests && /usr/bin/python3 -m unittest test_service test_end_to_end`
  Expected: FAIL — `ImportError: bridge.service`.
- [ ] **Step 3: Implement** `service.py` and `bin/multica-bridge`
  (`chmod 755`); add `bin/multica-bridge` to `test_scripts_parse`'s
  executable list (it is Python: checked with `py_compile`, not `sh -n`).
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0.
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/bridge/service.py integrations/multica/bin/multica-bridge integrations/multica/tests
git commit -m "feat(multica): multica-bridge service with lock, backoff and self-test (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 10: `install.sh`, `uninstall.sh`, the launchd agent and the agent instructions
Files: integrations/multica/install.sh, integrations/multica/uninstall.sh, integrations/multica/bridge/installjson.py, integrations/multica/launchd/ai.omega.multica-bridge.plist.in, integrations/multica/agent-instructions.md, integrations/multica/tests/stub-launchctl, integrations/multica/tests/stub-security (find without `-w`), integrations/multica/tests/install_test.sh, integrations/multica/tests/test_installjson.py
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L305-354, docs/game-dev/specs/2026-10-03-multica-integration.md:L577-592, docs/game-dev/specs/2026-10-03-multica-integration.md:L30-36
Review: task

**Interfaces:**
- Consumes: `bin/claude-multica`, `bin/omega-multica-agent` (T3);
  `bin/multica-bridge` and `bridge/` (T4–T9; `selftest.json` keys `ok`,
  `kind`, `error`, `interpreter`); `bridge.multica_cli.rows`;
  `tests/stub-multica`, `tests/stub-security`, `bridgetest.Board` (T4);
  the stub-recorder convention (T3); `studios/game-dev/bin/studio-state
  root` (prints the pointer root of the cwd); D1a (P1: command-name form,
  R50), D1e (P5: the Multica.app `~/Documents` step text), D1f (P6: which
  interpreter path the grant names), D1g (P7: `runtime list` fields; R33).
- Produces: `install.sh` (flags R10; exit 0 installed, 1 a failed step
  named on stderr, 2 usage); `uninstall.sh [--profiles] [--purge]
  [--help]` (exit 0, 1 refused, 2 usage); `python3 -m
  bridge.installjson <question> …` (below); the launchd label
  `ai.omega.multica-bridge`; files under `~/.claude-gamedev/multica/`:
  `config`, `lib/bin/multica-bridge`, `lib/bridge/*.py`, `launchd.out`,
  `launchd.err`; `~/Library/LaunchAgents/ai.omega.multica-bridge.plist`.

**`bridge/installjson.py`** (full code — R6; JSON in on stdin unless a
file argument is named; one answer on stdout; never prints a token
because no CLI output it reads carries one):

```python
"""JSON questions for install.sh / uninstall.sh (#28, R6). Python 3.9, stdlib only."""
from __future__ import annotations

import json
import sys
from xml.sax.saxutils import escape

from bridge.multica_cli import rows


def _load(src=None):
    if src is None:
        return json.load(sys.stdin)
    with open(src, encoding="utf-8") as f:
        return json.load(f)


def get(key):
    v = _load().get(key)
    if v in (None, ""):
        raise SystemExit("installjson: no %r in the CLI's answer" % key)
    return str(v)


def property_state(name):
    for p in rows(_load()):
        if p.get("name") == name:
            if p.get("archived") or p.get("archived_at"):
                return "archived"
            return "ok" if p.get("type") == "text" else "wrong-type:%s" % p.get("type")
    return "absent"


def profile_for_command(cmd):
    return "\n".join(p["id"] for p in rows(_load()) if p.get("command_name") == cmd)


def _online(rt):
    return rt.get("status") == "online"


def daemons(*profiles):
    rts = [r for r in rows(_load()) if _online(r)]
    sets = [{r.get("daemon_id") for r in rts if r.get("profile_id") == p} for p in profiles]
    both = set.intersection(*sets) if sets else set()
    return "\n".join(sorted(d for d in both if d))


def runtime_for(profile, daemon):
    return "\n".join(r["id"] for r in rows(_load())
                     if _online(r) and r.get("profile_id") == profile and r.get("daemon_id") == daemon)


def agent_state(name):
    for a in rows(_load()):
        if a.get("name") == name:
            return "archived" if a.get("archived") or a.get("archived_at") else "active"
    return "absent"


def bound_agents(agents_file, runtimes_file, *profiles):
    rts = {r["id"] for r in rows(_load(runtimes_file)) if r.get("profile_id") in profiles}
    return "\n".join(sorted(a["name"] for a in rows(_load(agents_file))
                            if a.get("runtime_id") in rts and not (a.get("archived") or a.get("archived_at"))))


def selftest_kind(path):
    d = _load(path)
    if d.get("ok"):
        return "ok"
    return "\t".join(str(d.get(k) or "") for k in ("kind", "error", "interpreter")).replace("\n", " ")


def json_env(key, value):
    return json.dumps({key: value})


def plist(template, interpreter, lib, base, home, path):
    with open(template, encoding="utf-8") as f:
        text = f.read()
    for k, v in (("@INTERPRETER@", interpreter), ("@LIB@", lib), ("@BASE@", base),
                 ("@HOME@", home), ("@PATH@", path)):
        text = text.replace(k, escape(v))
    return text.rstrip("\n")


QUESTIONS = {"get": get, "property-state": property_state, "profile-for-command": profile_for_command,
             "daemons": daemons, "runtime-for": runtime_for, "agent-state": agent_state,
             "bound-agents": bound_agents, "selftest-kind": selftest_kind, "json-env": json_env,
             "plist": plist}


def main(argv):
    if not argv or argv[0] not in QUESTIONS:
        sys.stderr.write("usage: installjson %s …\n" % "|".join(QUESTIONS))
        return 2
    try:
        out = QUESTIONS[argv[0]](*argv[1:])
    except (ValueError, OSError, KeyError, TypeError) as e:
        sys.stderr.write("installjson %s: %s\n" % (argv[0], e))
        return 1
    if out:
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

**`launchd/ai.omega.multica-bridge.plist.in`** (full):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>ai.omega.multica-bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>@INTERPRETER@</string>
    <string>@LIB@/bin/multica-bridge</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>@PATH@</string>
    <key>HOME</key><string>@HOME@</string>
  </dict>
  <key>StandardOutPath</key><string>@BASE@/launchd.out</string>
  <key>StandardErrorPath</key><string>@BASE@/launchd.err</string>
</dict>
</plist>
```

**`install.sh` helpers** (full code — the parts that carry the token):

```sh
#!/bin/sh
# install.sh — set up the omega-ai Multica integration on this Mac (#28).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$HERE/../.." && pwd -P)"
BASE="$HOME/.claude-gamedev/multica"
CLI_HOME="$BASE/cli-home"
LABEL=ai.omega.multica-bridge
SERVICE=omega-multica-bridge
ACCOUNT="$(id -un)"
SECURITY="${OMEGA_MULTICA_SECURITY:-/usr/bin/security}"
LAUNCHCTL="${OMEGA_MULTICA_LAUNCHCTL:-/bin/launchctl}"
DESKTOP_CLI=/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica
TOKEN=

die() { printf 'install: %s\n' "$*" >&2; exit 1; }

# The only way install.sh runs the Multica CLI: a subshell with no inherited
# MULTICA_* variables, the operator's token in the environment (never argv),
# an empty HOME so no local profile is read, and JSON output.
mcli_plain() {
  (
    for v in $(env | sed -n 's/^\(MULTICA_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
    MULTICA_TOKEN="$TOKEN"; MULTICA_SERVER_URL="$SERVER_URL"; MULTICA_WORKSPACE_ID="$WORKSPACE_ID"
    HOME="$CLI_HOME"; PATH=/usr/bin:/bin
    export MULTICA_TOKEN MULTICA_SERVER_URL MULTICA_WORKSPACE_ID HOME PATH
    exec "$CLI" "$@"
  )
}
mcli() { mcli_plain "$@" --output json; }
ij() { PYTHONPATH="$HERE" PYTHONDONTWRITEBYTECODE=1 "$PY" -m bridge.installjson "$@"; }

read_token() {   # prints nothing; sets TOKEN or dies
  TOKEN="$("$SECURITY" find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null)" ||
    die "cannot read the token from the Keychain (item $SERVICE / $ACCOUNT) — is the Keychain locked?"
  [ -n "$TOKEN" ] || die "the Keychain item $SERVICE / $ACCOUNT is empty — run install.sh --new-token"
}

ensure_token() {
  if [ "$NEW_TOKEN" = 1 ] || ! "$SECURITY" find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
    echo "Paste your Multica API token at the Keychain prompt (it is not shown):"
    "$SECURITY" add-generic-password -s "$SERVICE" -a "$ACCOUNT" -U -w ||
      die "step 2 (token): the Keychain did not store the token"
  fi
  read_token
}
```

**`install.sh` steps** (prose binds the order; each failure is `die
"step <n> (<name>): <why>"`):
1. **Arguments** (R10): `--workspace-id`, `--server-url`, `--roots`,
   `--cli`, `--python`, `--daemon-id`, `--agent`, `--project`,
   `--poll-seconds`, `--new-token`, `--help`; a missing value, an unknown
   flag, or only one of `--agent`/`--project` → usage on stderr, exit 2.
   Values not given come from the existing config (`sed -n
   's/^<key>=//p'`), then the defaults (spec Config table).
   `workspace_id` still empty → exit 2 naming `--workspace-id`.
2. **Step 1 (prerequisites):** `PY` = `--python`, else `/usr/bin/python3`
   (R4); `"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 9))'`
   fails → die `step 1 (python): <PY> is not Python 3.9 or newer`;
   `PY_REAL` = `"$PY" -c 'import os, sys;
   print(os.path.realpath(sys.executable))'`. `CLI` = `--cli`, else config
   `cli`, else `$DESKTOP_CLI` when executable, else `command -v multica`;
   none → die naming Multica.app. `command -v claude-gd` empty → die `step
   1 (claude-gd): not on PATH — install omega-ai first`.
3. **Step 2 (token):** `ensure_token`. **Step 3:** `mcli user profile
   get` fails → die `step 3 (token check): Multica rejected the token —
   run install.sh --new-token` (the CLI's stderr is not echoed: it may
   quote the request); `OPERATOR=$(… | ij get id)`.
4. **Step 4 (config):** each `--roots` item → `(cd "$item" &&
   "$REPO/studios/game-dev/bin/studio-state" root)` (failure → die naming
   the root); the file is written as the seven `key=value` lines in the
   Config table's order, with `studio_overnight=$REPO/studios/game-dev/bin/studio-overnight`;
   written (temp file in `$BASE`, `chmod 600`, `mv`) only when its text
   differs (R34). `$BASE` and `$CLI_HOME` are created `chmod 700`.
5. **Step 5 (properties):** `mcli property list --include-archived` once
   into a temp file; for `omega_run` then `omega_story`: `ij
   property-state` → `ok` nothing; `archived` → die `step 5 (properties):
   <name> is archived — unarchive it in Multica`; `wrong-type:<t>` → die
   `… <name> exists with type <t>, not text`; `absent` → `mcli property
   create --name <name> --type text`, failure → die `step 5 (properties):
   could not create <name> — you must be a workspace owner or admin`.
6. **Step 6 (wrappers):** R48 for `claude-multica` and
   `omega-multica-agent` (`mkdir -p ~/.local/bin`; `ln -sfn
   "$HERE/bin/<w>" "$HOME/.local/bin/<w>"` only when the link differs).
7. **Step 7 (runtimes):** for (`omega game-dev`, `omega-multica-agent`)
   and (`claude (multica)`, `claude-multica`): `mcli runtime profile list
   | ij profile-for-command <cmd>` (R50) → the first id, else `mcli runtime
   profile create --display-name <name> --command-name <cmd>
   --protocol-family claude | ij get id`. Then the wait (below).
8. **Step 8 (agent),** only with `--agent`: `--project` must be a
   directory (`PROJECT=$(cd … && pwd -P)`); `mcli agent list
   --include-archived | ij agent-state <name>` → `active`: print `agent
   <name> exists — skipped`; `archived`: R49 text, continue; `absent`: `ij
   json-env OMEGA_PROJECT "$PROJECT" | mcli agent create --name <name>
   --runtime-id "$RT_OMEGA" --max-concurrent-tasks 1 --instructions "$(cat
   "$HERE/agent-instructions.md")" --custom-env-stdin`.
9. **Step 9 (service):** build `$BASE/lib.new/bin/multica-bridge` and
   `$BASE/lib.new/bridge/*.py` (copies, no `__pycache__`); `diff -r
   "$BASE/lib" "$BASE/lib.new"` differs or `lib` absent → replace `lib`,
   else remove `lib.new`. `ij plist "$HERE/launchd/$LABEL.plist.in"
   "$PY_REAL" "$BASE/lib" "$BASE" "$HOME" "<R45 PATH>"` into a temp file;
   `plutil -lint -s` it; when it differs from
   `~/Library/LaunchAgents/$LABEL.plist`, replace it and `"$LAUNCHCTL"
   bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true`; then when
   `"$LAUNCHCTL" print "gui/$(id -u)/$LABEL" >/dev/null 2>&1` fails,
   `"$LAUNCHCTL" bootstrap "gui/$(id -u)" <plist>` (failure → die). Then
   `rm -f "$BASE/selftest.json"` and `"$LAUNCHCTL" kickstart -k
   "gui/$(id -u)/$LABEL"` (R34).
10. **Step 10 (self-test):** print the P5 step (D1e's text; default:
    `One-time step: System Settings → Privacy & Security → Files and
    Folders → Multica → turn on "Documents Folder" (needed for projects
    under ~/Documents).`), then the wait (below).

**The two waits** (full code):

```sh
wait_runtimes() {   # sets DAEMON and RT_OMEGA or dies
  limit="${OMEGA_MULTICA_RUNTIME_WAIT:-60}"; waited=0
  while :; do
    mcli runtime list > "$TMPD/rt.json" || die "step 7 (runtimes): runtime list failed"
    if [ -n "$DAEMON_ID" ]; then
      ids="$(ij daemons "$P_OMEGA" "$P_CLAUDE" < "$TMPD/rt.json" | grep -Fx -- "$DAEMON_ID" || true)"
    else
      ids="$(ij daemons "$P_OMEGA" "$P_CLAUDE" < "$TMPD/rt.json")"
    fi
    n="$(printf '%s' "$ids" | grep -c . || true)"
    if [ "$n" = 1 ]; then
      DAEMON="$ids"
      RT_OMEGA="$(ij runtime-for "$P_OMEGA" "$DAEMON" < "$TMPD/rt.json" | sed -n 1p)"
      return 0
    fi
    [ "$n" -gt 1 ] && die "step 7 (runtimes): several daemons serve both profiles: $(printf '%s' "$ids" | tr '\n' ' ')— re-run with --daemon-id <one of them>"
    [ "$waited" -ge "$limit" ] && die "step 7 (runtimes): no online runtime for \"omega game-dev\" and \"claude (multica)\" after $limit s — restart the Multica daemon (quit and reopen Multica.app, or run: multica daemon restart), then re-run install.sh"
    sleep 2; waited=$((waited + 2))
  done
}

wait_selftest() {
  limit="${OMEGA_MULTICA_SELFTEST_WAIT:-30}"; waited=0
  while [ ! -s "$BASE/selftest.json" ]; do
    [ "$waited" -ge "$limit" ] && die "step 10 (self-test): the bridge wrote no self-test in $limit s — see $BASE/bridge.log and $BASE/launchd.err"
    sleep 1; waited=$((waited + 1))
  done
  res="$(ij selftest-kind "$BASE/selftest.json")" || die "step 10 (self-test): unreadable $BASE/selftest.json"
  [ "$res" = ok ] && { echo "install: the bridge is running and its self-test passed"; return 0; }
  kind="$(printf '%s' "$res" | cut -f1)"; err="$(printf '%s' "$res" | cut -f2)"; interp="$(printf '%s' "$res" | cut -f3)"
  if [ "$kind" = file-access ]; then
    printf 'install: the bridge cannot read your files: %s\n' "$err" >&2
    printf 'Grant access to this program: %s\n' "$interp" >&2
    printf 'System Settings → Privacy & Security → Files and Folders (or Full Disk Access) → add it, then run: launchctl kickstart -k gui/%s/%s\n' "$(id -u)" "$LABEL" >&2
    exit 1
  fi
  die "step 10 (self-test): $kind: $err"
}
```

`TMPD=$(mktemp -d)` with `trap 'rm -rf "$TMPD"' EXIT`; no file under
`TMPD` ever holds the token.

**`uninstall.sh`** (prose — R35, AC7): flags `--profiles`, `--purge`,
`--help` (else exit 2). Shares `die`, `mcli_plain`, `mcli`, `ij`,
`read_token` (copied, not sourced: each script stands alone). With
`--profiles`, first (nothing removed yet): `read_token` (failure → exit
1); the config gives `CLI`, `SERVER_URL`, `WORKSPACE_ID`; `PY`
=`/usr/bin/python3`; profile ids via `profile-for-command` for both
command names; `mcli agent list > agents.json`, `mcli runtime list >
rt.json`; `ij bound-agents agents.json rt.json <ids>` non-empty → for
each name `uninstall: archive agent <name> in Multica first` on stderr,
exit 1. Then: `"$LAUNCHCTL" bootout gui/<uid>/<label>` (errors ignored),
remove the plist; remove each `~/.local/bin` wrapper link that R48 says is
ours; `rm -rf "$BASE/lib"`; `"$SECURITY" delete-generic-password -s
omega-multica-bridge -a <user>` (exit 44 ignored); with `--profiles`,
`mcli_plain runtime profile delete <id>` for each id found (no
`--output`: the command takes none); with `--purge`, `rm -rf "$BASE"`.
Prints one line per removed thing.

**`agent-instructions.md`** (full text, R7):

```text
You run omega-ai's game-dev studio for this project through `claude-gd`.

- Start an overnight run only with: studio-overnight start --detach <approved manifest>
  Never start a single-plan overnight run and never start one without --detach:
  the run must outlive your task.
- After starting a run, reply with the run name and stop. The board shows its
  progress; the operator steers it with comments.
- When you are woken because the sub-issues closed, read the Run issue's last
  comment (ending and report path), read that report, and post a short summary
  of the run on this issue: what landed, what stopped and why, what needs the
  operator.
- Never change the status of a Run issue or a story issue, and never post
  comments that start with "studio: " — those belong to the bridge.
```

**`tests/stub-launchctl`** (Python 3.9, executable): appends its argv as
one JSON line to `$STUB_LAUNCHCTL_DIR/calls`; `print gui/<uid>/<label>` →
exit 0 when `$STUB_LAUNCHCTL_DIR/loaded` exists, else 113; `bootstrap
gui/<uid> <plist>` → copies the plist to `$STUB_LAUNCHCTL_DIR/loaded`,
exit 0; `bootout gui/<uid>/<label>` → removes `loaded`, exit 0 (3 when
absent); `kickstart -k gui/<uid>/<label>` → by `$STUB_LAUNCHCTL_DIR/mode`
(default `selftest`): `selftest` reads `loaded` with `plistlib`, runs
`ProgramArguments[:-1] + ["selftest"]` with `EnvironmentVariables` plus
every `OMEGA_MULTICA_*` and `STUB_*` variable of its own environment,
waits for it (timeout 20 s); `file-access` writes `{"ok": false, "kind":
"file-access", "error": "Operation not permitted: <HOME>/Documents/p/.studio",
"interpreter": "/Library/Developer/CommandLineTools/usr/bin/python3"}`
to `$HOME/.claude-gamedev/multica/selftest.json`; `none` writes nothing.

**`tests/stub-security` change:** `find-generic-password -s S -a A`
without `-w` prints nothing and exits 0 when the item exists, 44 when not.

- [ ] **Step 1: Write the failing tests.**
  `test_installjson.py` — `InstallJsonTest(unittest.TestCase)` (each
  question fed the P7 fixtures where they exist, else literal JSON):
  `test_property_state` (absent, ok, archived, wrong-type),
  `test_profile_for_command`, `test_daemons_needs_both_profiles_online`
  (an offline runtime and a runtime of one profile only are not counted;
  two daemons → two lines), `test_runtime_for`, `test_agent_state`,
  `test_bound_agents_skips_archived`, `test_selftest_kind_tabs_and_newlines`,
  `test_json_env_escapes` (a path with `"` and `\` round-trips through
  `json.loads`), `test_plist_escapes_and_lints` (a HOME holding `&` and
  `<` → `plistlib.loads` gives the exact strings back), `test_usage_exit_2`.
  `install_test.sh` (sources `tests/assert.sh`; `$TMP/home` as `HOME`;
  `$FAKE` first on `PATH` with a recorder `claude-gd`; a stub board made by
  `"$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import
  bridgetest; bridgetest.Board(sys.argv[2])' "$TESTS" "$TMP/cli"`;
  `OMEGA_MULTICA_SECURITY="$TESTS/stub-security"`,
  `STUB_SECURITY_DIR`, `OMEGA_MULTICA_LAUNCHCTL="$TESTS/stub-launchctl"`,
  `STUB_LAUNCHCTL_DIR`, `OMEGA_MULTICA_RUNTIME_WAIT=4`,
  `OMEGA_MULTICA_SELFTEST_WAIT=10`; base flags `--workspace-id ws-test
  --cli "$TMP/cli/multica" --python "$PY"`; the token reaches the stub
  security on stdin: `printf '%s\n' mul_testtoken123456 | sh install.sh …`):
  - `test_install_fresh` — exit 0; the two properties, the two profiles
    and their runtimes exist on the board; `config` holds the seven keys,
    `operator_member_id=m-op`, mode 600; both wrapper links point into
    `integrations/multica/bin/`; `lib/bin/multica-bridge` and
    `lib/bridge/service.py` exist; `loaded` lints with `plutil`, its
    `ProgramArguments[0]` is `PY`'s real path, `KeepAlive` true, `HOME`
    and the R45 `PATH`; the self-test (real, through the copied lib) passed;
    the P5 line was printed;
  - `test_install_token_never_in_argv_files_or_output` — the token string
    is in no `calls.jsonl` argv, no stub-launchctl call, no file under
    `$TMP/home` except the stub Keychain's own item file, and not in
    install's stdout or stderr;
  - `test_install_rerun_changes_nothing` — second run exit 0; no
    `property create`, `runtime profile create` or `agent create` call;
    no `bootout`/`bootstrap`; one `kickstart`; config and plist mtimes
    unchanged;
  - `test_install_token_prompt_once` — the second run makes no
    `add-generic-password` call; `test_install_new_token` — `--new-token`
    makes one;
  - `test_install_token_rejected` — the stub board's token differs → exit
    1, stderr names step 3 and `--new-token`, no config written;
  - `test_install_property_archived_refused`,
    `test_install_property_wrong_type_refused`,
    `test_install_not_admin_refused` (board `role` `member` → exit 1
    naming step 5 and "owner or admin");
  - `test_install_runtime_wait_times_out` (`auto_runtime` false → exit 1
    after about 4 s, stderr has `multica daemon restart`);
  - `test_install_multiple_daemons_needs_daemon_id` (two online runtimes
    per profile on `daemon-1` and `daemon-2` → exit 1 naming both;
    `--daemon-id daemon-2` → exit 0 and the agent's `--runtime-id` is
    the `daemon-2` runtime);
  - `test_install_agent_args` (`--agent gd --project "$TMP/proj"` →
    `agent create` argv has `--runtime-id <omega runtime>`,
    `--max-concurrent-tasks 1`, `--instructions` equal to
    `agent-instructions.md`'s text, `--custom-env-stdin`; stdin is
    `{"OMEGA_PROJECT": "<real path>"}`; a rerun → `agent gd exists —
    skipped`; `test_install_agent_archived_skipped`);
  - `test_install_selftest_file_access_reported` (mode `file-access` →
    exit 1; stderr has the interpreter path and "Files and Folders");
  - `test_install_selftest_timeout` (mode `none`,
    `OMEGA_MULTICA_SELFTEST_WAIT=2` → exit 1 naming `bridge.log`);
  - `test_install_python_too_old` (`--python "$FAKE/oldpy"`, a script that
    exits 1 → exit 1 naming step 1; nothing written under `$TMP/home`);
  - `test_install_foreign_symlink_refused` (R48: `~/.local/bin/claude-multica`
    a regular file → exit 1 naming it; the file is untouched);
  - `test_install_usage` (`--agent` without `--project` → 2; `--bogus` →
    2; no workspace id → 2);
  - `test_uninstall_removes` (after an install: exit 0; no plist, no
    links, no `lib/`, a `delete-generic-password` call; `config` and
    `state/` kept; the stub board calls since the install hold no write);
  - `test_uninstall_profiles_refused_while_bound` (an agent bound to the
    omega runtime → exit 1 with `archive agent gd in Multica first`;
    plist, links, lib and Keychain item all still present);
  - `test_uninstall_profiles_deletes` (no bound agent → two `runtime
    profile delete` calls without `--output`);
  - `test_uninstall_purge` (`--purge` → `~/.claude-gamedev/multica`
    gone);
  - `test_uninstall_never_writes_issues_agents_properties` (every
    uninstall run's board calls are among `user profile get`, `runtime
    profile list`, `agent list`, `runtime list`, `runtime profile
    delete`).
- [ ] **Step 2: Run them to see them fail.**
  Run: `sh integrations/multica/tests/install_test.sh; cd integrations/multica/tests && /usr/bin/python3 -m unittest test_installjson`
  Expected: FAIL — `install.sh: No such file`; `ModuleNotFoundError:
  bridge.installjson`.
- [ ] **Step 3: Implement** the files above; `chmod 755` `install.sh`,
  `uninstall.sh`, `tests/stub-launchctl`; add `install.sh`,
  `uninstall.sh` to `test_scripts_parse` (`sh -n`).
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0.
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/install.sh integrations/multica/uninstall.sh integrations/multica/bridge/installjson.py integrations/multica/launchd integrations/multica/agent-instructions.md integrations/multica/tests
git commit -m "feat(multica): install and uninstall with Keychain token and launchd agent (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 11: README and its contract test
Files: integrations/multica/README.md, integrations/multica/tests/readme_test.sh
Spec: docs/game-dev/specs/2026-10-03-multica-integration.md:L99-107, docs/game-dev/specs/2026-10-03-multica-integration.md:L61-73, docs/game-dev/specs/2026-10-03-multica-integration.md:L784-819
Review: final

**Interfaces:**
- Consumes: T10's flags and exit texts; T8's command table (AC21) and
  replies; T9's `status` output; the spec's Risks.
- Produces: `README.md` with these `##` sections in order: `Modes`,
  `Install`, `File-access grants`, `Commands`, `What the board shows`,
  `Troubleshooting`, `Known risks`, `Uninstall and swapping Multica out`.

- [ ] **Step 1: Write the failing test** — `readme_test.sh` (sources
  `tests/assert.sh`; `R=integrations/multica/README.md`):
  - `test_readme_sections` — each `## <name>` above present, in order
    (`grep -n` line numbers ascending);
  - `test_readme_teaching_phrases` — each fixed string (`grep -F`):
    `claude-gd`, `claude-multica`, `omega-multica-agent`, `install.sh
    --workspace-id`, `--new-token`, `--agent`, `--project`, `uninstall.sh
    --profiles`, `--purge`, `Files and Folders`, `Full Disk Access`,
    `Documents Folder`, `multica-bridge status`, `/say`, `/unit`,
    `/hold`, `/resume`, `/stop`, `/stop run`, `/unsay`, `/said`,
    `edited comments are not re-read`, `finished runs get no reply`,
    `assigned to an agent are ignored`, `studio-overnight start --detach`,
    `delete the integrations/multica folder`;
  - `test_readme_flags_match_install` — every `--flag` in `install.sh
    --help` output appears in the README.
- [ ] **Step 2: Run it to see it fail.**
  Run: `sh integrations/multica/tests/readme_test.sh`
  Expected: FAIL — README missing.
- [ ] **Step 3: Write `README.md`.** Modes: the spec's Modes table and
  "only manifest runs detach". Install: prerequisites (Multica.app,
  `claude-gd`, an API token created in Multica → Settings → API tokens),
  the command with every flag, what each step does, re-running. Grants:
  the interpreter path install prints and the System Settings pane; the
  Multica.app `Documents Folder` switch (D1e). Commands: the AC21 table
  verbatim in substance, ✓/✗/⚠ replies, the 10-minute staleness, and the
  three sentences the test pins. Board: Run issue, story sub-issues,
  status mapping table (from `mirror.STATUS`), `studio: ` comments,
  hands-off while assigned and the catch-up line. Troubleshooting:
  `multica-bridge status`, `bridge.log`, `launchd.err`, `--new-token`.
  Known risks: the spec's Risks list, one line each. Swapping out:
  `uninstall.sh --profiles --purge`, then delete the integrations/multica
  folder; the core keeps working (mode 1).
- [ ] **Step 4: Run the gate.**
  Run: `sh integrations/multica/tests/run.sh && sh tests/run_all.sh`
  Expected: both exit 0.
- [ ] **Step 5: Commit.**

```bash
git add integrations/multica/README.md integrations/multica/tests/readme_test.sh
git commit -m "docs(multica): README — modes, install, grants, commands, risks (#28)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

## Final gate

Run after Task 11, in this order.

**1. Whole-branch review (Opus, standalone).** Dispatch a fresh reviewer
with `model: "opus"` on `git diff origin/main...HEAD`. Its brief:

- Read the spec (`docs/game-dev/specs/2026-10-03-multica-integration.md`)
  and this plan's Global Constraints, Decisions (R1–R56, D1a–D1g), Review
  Focus and Falsify sections.
- For AC1, AC1a and AC2–AC30 write one line each: `ACn met: <file:line or test name>`
  or `ACn unmet: <what is missing>`; the same for each Global Constraint,
  each Review Focus item (name the test that pins it), each Decision the
  diff could contradict, and each Falsify row marked UNVERIFIED (say
  whether the code still holds if the claim is false).
- Check, by reading, never by running anything that writes: no token in
  argv, logs, state, test fixtures or any verb's environment; every CLI
  call goes through `multica_cli.Cli` (`grep -rn "subprocess" bridge/`
  lists only `multica_cli.py`, `studio.py`, `service.py`); no `multica`
  write targets the request issue; the core (`studios/`, `tests/`)
  changed only as T2 lists (`deny-rules`, `origin_ok`/`origin_take`,
  `reg_write`'s `origin=` line, `detach_start`'s pass-through, help and
  the contract doc; the `STUDIO_*` strip itself unchanged); no `fromisoformat`, `utcnow`,
  `utcfromtimestamp`; every module starts with `from __future__ import
  annotations`.
- Findings as `path:line: Critical|Important|Minor: problem. fix.`; the
  full report to a file, a hand-back of 1.5k characters or less.

Fixes go to a fresh fixer given the findings and the diff range; each fix
is a `fix(final): …` commit with the trailers. Re-review only after a
Critical, three or more Importants, or a production-bug fix; never a third
pass.

**2. Full milestone gate** (automated steps):

```sh
sh tests/run_all.sh
sh integrations/multica/tests/run.sh
OMEGA_MULTICA_TEST_PY=python3 sh integrations/multica/tests/run.sh
```

Expected: all three exit 0 (the third runs the suite on the Homebrew
3.14 interpreter as well as the 3.9.6 floor).

**3. Manual checks** (milestone gate step 4; the user runs them, the
controller records the results in the story):

| # | Who | When | What | Pass |
|---|-----|------|------|------|
| 1 | User | After the review fixes land | Create a Multica API token (Settings → API tokens); in a throwaway Godot project under `~/Documents` with an approved two-story manifest: `sh integrations/multica/install.sh --workspace-id <omega-alpha id> --agent "omega game-dev" --project <project>` | exit 0; the only manual steps were the token and the grants install named; `multica-bridge status` shows `selftest: ok` |
| 2 | User | After 1 | Create "Tonight: probe", assign it to the game-dev agent, ask for the run | The agent runs `studio-overnight start --detach <manifest>`; `studio-overnight status` shows the runner alive after the agent's task ends; `grep -h '^origin=' ~/.claude-gamedev/runs/overnight-*` prints `origin=multica:<the request's task id>` (milestone gate step 4.2, spec L37-40: AC1a + AC3.6 end to end) |
| 3 | User | During the run | Watch the board | "Run <name>" under the request issue; one sub-issue per story; statuses follow the run; a comment per unit start and end |
| 4 | User (phone browser) | During the run | `/say hello` on story A; `/hold` then `/resume` on story B | ✓ reply and a "message delivered" comment; B holds and resumes |
| 5 | User | At the run's end | Read the Run issue and the request issue | Run issue Done with the ending and the report path; the agent's run summary on the request issue |
| 6 | User | After 5 | `multica issue runs <request issue>` | The operator's run plus exactly one "sub-issues closed" wakeup; no other run |
| 7 | User | After 6 | Probe cleanup (below) | Every item gone or cancelled; properties kept |

**4. Probe cleanup** (the controller runs the CLI steps after the user
approves them; the user does the web-UI step):

- `multica issue status <id> cancelled --no-start` for each probe issue
  (OMEG-2 … OMEG-9 and any created by P2/P7), then archive them in the
  web UI (R36: the 0.6.1 CLI has no archive).
- Archive the agent `gd-probe` in the web UI (no CLI archive verb), then
  `multica runtime profile delete <probe profile id>`.
- Remove `~/.local/bin/omega-probe-agent`,
  `~/.local/bin/omega-probe-context.md`, `~/.claude-gamedev/multica/probes/`, the P6
  plist (`launchctl bootout gui/$(id -u)/ai.omega.multica-probe-p6`, then
  delete `~/Library/LaunchAgents/ai.omega.multica-probe-p6.plist`), and
  the throwaway projects `~/omega-probe-p1` and
  `~/Documents/omega-probe-p5`.
- Keep the properties `omega_run` and `omega_story` (install reuses them).
- `git worktree` and branch cleanup per the workflow once the PR merges.

---

## Falsify

### Claims

| # | Claim | How checked | Result |
|---|-------|-------------|--------|
| 1 | Spec line ranges cited in Global Constraints, Decisions and every task's `Spec:` line | rev 3 ranges remapped to rev 4 (dae9e8d) by a line diff (`remap.py`), then to 1f2c1b4 (+1 after L39, P4 203-206 → 204-209, +3 after; `remap5.py`), then spot-checked by printing each range's first and last line; T2's AC1 range widened to take in 1a (L242-262), T1's gate range set to 4.2 (L37-40) | FIXED |
| 2 | `studio-overnight` anchors (`deny_rules` :76-84, usage :136-250, registry :560-591, `reg_write` :576-584, `detach_start` :784-846, `cmd_start` :849, dispatch :1089-1121) | `grep -n` on the pre-#27 file; T2 re-locates by `grep -n` after #27 lands | OK (lines move with #27 — the plan gives the grep) |
| 3 | `overnight-deny.txt` has 32 rules, 4 with `{default_branch}`, 1 with `{merge_basename}` | `grep -c` | OK |
| 4 | `tests/run_all.sh` runs every `tests/*_test.sh` and nothing else | read the file | OK — R2 holds without an edit |
| 5 | `tests/assert.sh` gives `_pass`/`_fail` and `run_tests` | read the file | FIXED (T2 snippets used the wrong counter; rewritten) |
| 6 | Python floor: `/usr/bin/python3` is 3.9.6, real path in CommandLineTools | `/usr/bin/python3 --version`; `realpath` | OK |
| 7 | Every plan Python block compiles on 3.9.6 | `check_blocks.py` under `/usr/bin/python3` | OK |
| 8 | 3.9 `datetime.fromisoformat` rejects `Z` and 9 fraction digits | trial on 3.9.6 | OK — `parse_ts` uses a regex |
| 9 | `parse_ts` handles `Z`, `+00:00`, `-07:00`, `+0200`, 0–9 fraction digits, no offset | `check_blocks.py` trial | OK |
| 10 | `unittest discover` with no tests exits 5 on 3.12+ | trial on 3.14 | OK — `run.sh` guards it |
| 11 | `security find-generic-password` exits 44 when the item is missing | trial with a made-up service name | OK |
| 12 | `ps -o args= -p <pid>` shows the runner's argv for `reg_live` | read `studio-overnight` | OK |
| 13 | CLI 0.6.1: `issue comment add <id> --content-stdin [--parent]`, `issue comment list <id> --since` | `--help` | OK |
| 14 | `issue create` has `--description-stdin`, `--property` (repeatable), `--allow-duplicate`, no `--no-start` | `--help` | OK |
| 15 | `issue status <id> <key> --no-start`; status keys | `--help` | OK |
| 16 | `issue list --property Name=Value`, `__none__`, ANY/ALL semantics, `--limit 1-100`, `has_more` | `--help` text | OK (P7 confirms `__none__` live) |
| 17 | `issue assign --unassign --no-start`; `issue runs [--active]` | `--help` | OK |
| 18 | `runtime profile create --display-name --command-name --protocol-family`; `delete` takes no `--output` | `--help` | OK |
| 19 | `agent create --name --runtime-id --custom-env-stdin --max-concurrent-tasks --instructions` | `--help` | OK |
| 20 | `property list --include-archived`; `property create --name --type` | `--help` | OK |
| 21 | Global flags `--profile`, `--server-url`, `--workspace-id`, `--debug`; env `MULTICA_TOKEN` honoured | `--help`; P7 confirms the env token | OK |
| 22 | bash 3.2 `printf '%s\0'` writes NUL-separated argv with spaces, newlines, empty and `$`/backtick elements intact | `trial/nul.sh` + `od -c` | OK |
| 23 | `sanitize` removes `@`, mention links in any case, and fences | `check_blocks.py` trial | OK |
| 24 | `classify` order AUTH → NOT_FOUND → TRANSIENT on sample texts | `check_blocks.py` trial | OK (texts are stand-ins; see 31) |
| 25 | The stub's `parse` accepts the adapter's argv and rejects unknown flags, `--output` on profile delete, missing positionals | `check_blocks.py` trial | FIXED (first draft was broken) |
| 26 | Multica reuses one workdir per issue (`<issue>-<12 hex>`) | probe log (three tasks, one workdir) | OK — R21 |
| 27 | The plist template filled by `installjson plist` (values with `&`, `<`) parses back exactly and passes `plutil -lint` | `trial5.py` on 3.9.6 | OK |
| 28 | `studio-state root` prints the cwd's pointer root and needs no `.studio/` | read `studio-state` :148-153 | OK |
| 29 | `plutil` and `scutil` exist at `/usr/bin` / `/usr/sbin` | `which` | OK |
| 30 | `start --detach` would drop `STUDIO_RUN_ORIGIN` unless passed on: `detach_start` unsets every `STUDIO_*` variable before its `perl setsid` re-exec, and the re-exec'd child's `cmd_start` → `acquire_run_lock` → `reg_write` is what writes the registry (both modes, D18) | read `studio-overnight` `detach_start` (the `env \| sed -nE … STUDIO_[A-Za-z0-9_]*` unset loop, then `nohup perl … sh "$SELF_ABS" start`), `acquire_run_lock`, `reg_write`; `tests/overnight_lanes_test.sh` `test_lanes_detach_strips_env` asserts `STUDIO_X` is stripped | OK — R52 passes it explicitly; T2's `test_lanes_origin_detach` pins it |
| 31 | Real 5xx / 429 / network error texts of CLI 0.6.1 | none recorded yet | UNVERIFIED — P7 records `fixtures/cli/errors/*.txt`; stub defaults until then |
| 32 | `runtime list` / `daemon status` JSON shapes (`profile_id`, `daemon_id`, `status`, any host field) | `--help` only | UNVERIFIED — P7 fixture; R33 |
| 33 | `status_category` names for done/cancelled | none | UNVERIFIED — P7 (D1g); R14 uses keys first |
| 34 | `issue comment list --since` is never folded and returns replies | `--help` | UNVERIFIED for replies — P7 (D1g nested replies) |
| 35 | `wrapper-lib.sh` `deny_words` + `eval` keep each rule (spaces, quotes, `*`) as one argument under bash 3.2 `sh` | `trial/eval.sh` | OK |
| 37 | `origin_ok` accepts `multica:<uuid>`, `a.b_c:d-e` and 200 bytes; refuses 201 bytes, a space, `/`, a newline, empty, non-ASCII, `;`, `$(…)`; `env ${RUN_ORIGIN:+"STUDIO_RUN_ORIGIN=$RUN_ORIGIN"} perl -MPOSIX … setsid` hands the value to the child, and nothing when empty; the `{ printf …; [ -z ] \|\| printf …; }` group exits 0 without an origin | `trial/origin.sh` under `/bin/sh` (bash 3.2) | OK |
| 38 | Claude Code's Bash tool passes an exported `STUDIO_RUN_ORIGIN` from the wrapper's session to the commands the agent runs | none yet | UNVERIFIED — P4 (T1) decides; fallback: no request issue + spec ruling |
| 36 | T8 `parse`/`plan_call`/`format_reply` give the AC21 table (incl. single-plan `/stop` → story `-`, full-width digit rejected, near misses) and T10 `installjson` answers (`daemons` needs both profiles online) | `trial5.py` on 3.9.6 | FIXED (the commands block lacked its constants; added) |

### Task order

- T1 before any bridge code (gate step 3); its fixtures feed T4's stub
  conformance test. Moving T1 later breaks `test_stub_conformance`.
- T2 before T3: the wrappers call `deny-rules`; T3's tests run the real
  verb. T1's P4 does not need T2 or T3: it uses the P3 stand-in runner and
  the P1 probe wrapper, each carrying its own copy of the rule (R56).
- T2 before T5: `read_registry` and `bridgetest.make_run(origin=…)`
  follow the `origin=` line format T2 writes.
- T4 before T5–T10: every Python test uses the stub board and the adapter.
- T5 before T6: adoption needs the registry reader and liveness.
- T6 before T7 and T8: both read the issue map and `post_comment`.
- T7 before T8: commands skip hands-off issues (`st["hands_off"]`) and
  `post_comment` returns None for held comments.
- T9 after T8: `poll_once` runs the whole `poll_runs`.
- T10 after T9: the install test runs the real self-test through the
  copied lib.
- T11 last: it checks `install.sh --help`.
No task consumes a name a later task produces (checked against each
Interfaces block).

### Self-review: AC → task

| AC | Where it is built | Test that proves it |
|----|-------------------|---------------------|
| 1 | T2 | `test_overnight_deny_rules_*` |
| 1a | T2 | `test_overnight_origin_*`, `test_lanes_origin_*` |
| 2, 4, 5 | T3 | `wrappers_test.sh` `test_cm_*`, deny-list cases |
| 3 | T3 (P1, P4 in T1) | `test_agent_*` (3.6: `test_agent_exports_run_origin`) |
| 6, 7 | T10 | `test_install_*`, `test_uninstall_*` |
| 8, 9 | T5, T6 | `test_adopt_*`, `test_pid_reused_by_other_process`, `test_origin_task`, `test_read_registry_origin`, `test_request_*` |
| 10–13, 15, 16 | T6 | `test_mirror_runs.py` |
| 14 | T7 | `test_mirror_status.py` |
| 17–19, 30 | T4 | `test_cli.py` |
| 20–25 | T8 | `test_commands.py` |
| 26–29 | T9 | `test_service.py`, `test_end_to_end.py` |
| Teaching | T11 | `readme_test.sh` |
| Gate 1–3 | T1–T11, Final gate 2 | the suites |
| Gate 4 | Final gate 3 | manual table |

### Placeholder scan

`grep -nE 'TBD|TODO|implement later|fill in|similar to Task|\.\.\.'` over
the plan: four hits, none a placeholder — two JSON shapes written
`[...]` (the stub's list envelope, the run-state `catchup` comment), the
`origin/main...HEAD` diff range, and this scan line. `…` in prose stands
for values the same step names, never for missing design.

### Spec defects

Defects 1–4 of the first plan draft are resolved in spec revision 4
(dae9e8d) and defect 5 in 1f2c1b4; the plan cites the fixed text.

1. Journal crash cases: the test strategy now matches AC23 (spec
   763-766); R26 unchanged.
2. AC6.7 daemon choice: AC6.7 now says the CLI cannot name the local
   daemon and install takes `--daemon-id` when several serve a profile
   (spec 323-329); R33 unchanged.
3. AC26 self-test targets: now the `studio_overnight` file, each
   configured root's `.studio/`, or with `roots` empty each live registry
   entry's root, and the token (spec 500-506); R31 unchanged.
4. P4 / F4: replaced by AC1a's `origin=` registry line (spec 255-262),
   AC3.6 (spec 286-287), AC9 (spec 368-…), References 16 (spec 185-188)
   and the new rejected alternative (spec 685-686). F4 and `runner_env`
   are gone from the plan (R55).

5. P4 timing: P4 needed AC1a and AC3.6, which T2 and T3 build after T1.
   Resolved in 1f2c1b4: P4 now runs on stand-ins (spec 204-209, matching
   R56) and milestone gate step 4.2 checks the real
   `origin=multica:<task id>` line (spec 37-40; Final gate, manual
   check 2).
