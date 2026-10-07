# Overnight hardening — no single command or bad call can sink a unit — Spec

Story: #59 (GitHub issue). Supersedes #43 (stall watchdog). Status: design
approved in chat (operator, 2026-10-07); written spec pending review.
Classification: architectural (runner timing contract, two new hooks, a new
studio-test mode, and a Spec-item format shared by the plan skill and
studio-brief).

## What happened (phoenix, 2026-10-07)

Run `overnight-kan-1540-greater-slime-av-20261007-084545`, story S1, task T7.
Report dir: `phoenix/.studio/reports/overnight-kan-1540-greater-slime-av-20261007-084545/`.

1. **One command ate the unit.** `lanes/1/7-S1-T7.jsonl`: the implementer ran
   `Godot --headless --import . ; Godot --headless --path . -gtest=res://tests/unit/test_vfx_span_player_creature.gd`
   with no `-s addons/gut/gut_cmdln.gd`. Godot booted the main scene headless
   and never exited. The runner sets `BASH_DEFAULT_TIMEOUT_MS` and
   `BASH_MAX_TIMEOUT_MS` to the whole session (`session_minutes` 180 → 3 h;
   `overnight-lanes.sh` `run_story`, `story_launch_env`, `final_unit`), so the
   command ran until the session cap: unit 19:43 → 22:43, outcome `timed out`,
   Bash exit 137.
2. **A bare EnterWorktree stranded the retry.** `lanes/1/8-S1-T7-retry.jsonl`:
   the retry called `EnterWorktree` with `input: {}`, creating a stray worktree
   (`.claude/worktrees/proud-fluttering-sonnet`), then tried to remove it.
   Auto mode correctly blocked the removal; after three denials the session
   lost Bash and ended `noprog`; the runner held the story ("no progress on T7").
3. **A malformed Spec item passed plan review.** `studio-brief` rejected a plan
   item written `<spec>:L144` (`cannot parse Spec: item`). The plan skill's
   self-review checks Spec lines by eye only.

**Probe (2026-10-07, GUT 9.6.0, throwaway project with phoenix's GUT addon and
a `.gutconfig.json` with `dirs` and pre/post-run scripts):**

| Command | Files run | pre/post hooks | Exit |
|---|---|---|---|
| `-s gut_cmdln.gd -gconfig=… -gdir= -gtest=a -gexit` | a only | yes | 0 (1 on a failing test) |
| same, no `-gdir=` | all | yes | 0 |
| `-s gut_cmdln.gd -gtest=a -gexit` (no `-gconfig`) | all | yes | 0 |
| no `-s` | none — never exits | — | killed |

GUT auto-loads `res://.gutconfig.json` even without `-gconfig`, and the config's
`dirs` take over unless `-gdir=` empties them. So the single-file form that
works is the one `engines/godot/test.sh` already builds for a positional file;
dropping `-gconfig` does **not** narrow the run.

## Goal

A unit can lose at most one bounded command to a hang, a hang is detected in
minutes rather than hours, and the two hand-built calls that caused this loss
(a raw headless Godot, a bare `EnterWorktree`) are refused before they run.
Plan-time review catches the Spec item that brief-time parsing would reject.

## Requirements

### R1. Per-command time caps derived from the session

- The runner derives two caps from `SESSION_MINUTES` (integer minutes,
  integer division):
  - **command cap** `CMD_MIN = min(45, SESSION_MINUTES / 3)` →
    `BASH_DEFAULT_TIMEOUT_MS = CMD_MIN × 60000`. Any Bash call that does not
    pass `timeout` gets this.
  - **gate cap** `GATE_MIN = min(90, 2 × SESSION_MINUTES / 3)` →
    `BASH_MAX_TIMEOUT_MS = GATE_MIN × 60000`. The ceiling a call may request
    with `timeout`; the execute skill requests it only for gate-routed
    commands (`studio-test`, `studio-gate`, `studio-run`, `studio-lint`).
- Why these numbers: a full phoenix gate takes 15–35 min under load. At
  phoenix's 180-min session the command cap is 45 min, so a gate still fits
  even when called without `timeout`; the gate cap is 90 min, which fits one
  wait behind another lane's gate (≤35) plus its own run (≤35) with margin,
  and leaves half the session for recovery. At the default 90-min session the
  caps are 30/60. Both are always strictly below the session cap.
- One helper computes the pair; every runner-launched `claude` session uses
  it: single-plan units (today they set neither variable), lane story units,
  the final unit, and repair/gate-repair/sync-repair sessions. The three
  existing `SESSION_MINUTES * 60000` sites are replaced.
- Documented in `studio-overnight --help` (Config: `session_minutes` row) and
  README's overnight section.

### R2. Idle watchdog (`overnight.idle_minutes`)

- New config `overnight.idle_minutes`, int, default 20, range 0–120; 0 turns
  the watchdog off. Read with `cfg` in `preflight` like the other keys. Test
  seams: `STUDIO_OVERNIGHT_IDLE_SECONDS` (replaces `idle_minutes × 60`) and
  `STUDIO_OVERNIGHT_IDLE_POLL_SECONDS` (check interval, default 30); both
  listed in `--help` with the other seams.
- **Idle** means the session's stream-json log (`<stem>.jsonl`) has not grown.
  Subagent tool calls stream into the parent log (`parent_tool_use_id`; 390
  such lines in T5's log), so a working subagent is not idle.
- **Gate exemption.** The idle clock does not fire while the session has an
  open (unanswered) Bash `tool_use` whose command invokes `studio-test`,
  `studio-gate`, `studio-run` or `studio-lint`, or while the unit is
  registered as a gate holder (`.studio/gate.units/<tag>/`). Those calls are
  bounded by the gate cap (R1). A gate wait is covered by the open-command
  rule, since a waiter is not yet registered.
- **On a stall** (idle ≥ the limit, not exempt): the watchdog ends the session
  through the same single-claim path as the session-cap watchdog (the
  `.ended` mkdir claim, TERM to the process group, KILL after `GRACE`), so
  exactly one of {session cap, idle watchdog, normal exit} ends a unit. It
  emits `unit_stalled` with `story`, `unit`, `label`, `idle_min`, and
  `command` (the open tool call as `unit_activity` renders it, ≤200 chars;
  `-` if none). The unit's outcome is `stalled`.
- **Retry and hold.** `stalled` is handled like `timed out`: a stalled unit
  that moved the state signature is `progress`; otherwise it counts toward
  `retries`; past them the ending is
  `stalled on <base> (no output for <N> min: <command>)`, which `holdable`
  holds. Repair sessions mirror their `… timed out` endings with
  `… stalled (…)`.
- The watchdog runs wherever the session-cap watchdog runs for a `claude`
  session. A unit waiting for a session slot has no session and is not
  watched.
- `docs/game-dev/overnight-events.md` documents `unit_stalled` and the
  `stalled` outcome; `--help` documents `idle_minutes`.
- #43's CPU signal is dropped: T7's hung Godot was a busy loop, which a
  "no CPU" test would have missed.

### R3. `studio-test --file`

- `studio-test --file <path>` runs only the named GUT script(s). `--file` is
  repeatable and takes a comma list (`--file a.gd,b.gd --file c.gd`). A path
  is relative to the project root; a leading `./` or `res://` is stripped.
- It goes through `studio-gate` exactly like the full run, and its exit code
  follows the existing rules (GUT failures or a nonzero engine status → 1;
  0 tests → 1; no Godot 2; no GUT 3).
- A named file that does not exist → exit 2 with
  `studio-test: no such test file <path>`, before Godot starts.
- Command built (proven by the probe): `-s addons/gut/gut_cmdln.gd`, then
  `-gconfig=res://<cfg>` and `-gdir=` when the project has a GUT config, then
  `-gtest=res://<a>[,res://<b>…]`, `-gexit`, `-gjunit_xml_file=…`. Never
  `-gconfig` without `-gdir=`. A comment cites the probe so the form is not
  "simplified" later.
- A positional file argument (`studio-test tests/unit/x.gd`) keeps working
  and means `--file tests/unit/x.gd`. A positional directory is unchanged.
- The multi-file form (`-gdir=` + comma `-gtest`) is checked once against real
  GUT in the throwaway probe project before merge (AC9).

### R4. Godot guard hook (every game-dev session)

- New `studios/game-dev/hooks/godot-guard.sh`, registered in
  `hooks/hooks.json` as a `PreToolUse` hook on `Bash`. It is active in every
  game-dev session, interactive or unattended.
- POSIX sh with sed/awk, no jq or python (the hooks stay self-contained).
  Denies with the `permissionDecision: deny` JSON (as `autopilot-guard.sh`
  does) and always exits 0, so a parse problem never blocks a call.
- It splits the command into simple commands at `;`, `&&`, `||`, `|`, `&`
  and newlines. In each, it skips leading `NAME=value` assignments and the
  wrappers `env`, `exec`, `command`, `time`, `nice`, `timeout <n>`. The first
  word, with quotes removed, is a **Godot invocation** when its basename
  matches `godot*` case-insensitively (`Godot`, `Godot_mono`, `godot4`,
  `Godot_v4.3-stable_linux.x86_64`), including a quoted path with spaces, or
  when it is a `$GODOT…`/`${GODOT…}` variable.
- A Godot invocation is **refused** when it has `--path` or `--headless` and
  none of these tokens: `-s`, `--script`, `--import`, `-e`, `--editor`,
  `--export-release`, `--export-debug`, `--export-pack` (any `--export*`),
  `--version`, `--doctool`, `--quit`, `--quit-after`, `--help`, `-h`.
- Refusal message (one line): a headless Godot call without `-s` boots the
  main scene and never exits; run one test file with
  `studio-test --file <tests/unit/x.gd>` (repeatable), the suite with
  `studio-test`, the game with `studio-run`.
- Commands whose first word is not Godot (`echo "Godot --headless --path ."`,
  `grep -r godot --path`) are allowed.

### R5. EnterWorktree guard in story sessions

- New `studios/game-dev/hooks/worktree-guard.sh`, `PreToolUse` on
  `EnterWorktree`. When `STUDIO_STORY` is non-empty or `OMEGA_AUTOPILOT=1`,
  a call whose `tool_input` has no non-empty `path` is denied (a `name`
  alone is denied too: it creates a new worktree). Outside story sessions
  every call is allowed.
- The message names the story worktree: the output of
  `sh "$CLAUDE_PLUGIN_ROOT/bin/studio-state" worktree` when it exits 0 (the
  existing worktree), else the path it suggests (exit 3), else the rule from
  execute §0 (`<STATE_ROOT>/.claude/worktrees/<Branch with / → ->`). Text:
  in a story session `EnterWorktree` needs `path:` — a bare call creates a
  stray worktree; use `path: <P>`.
- Same deny mechanics as R4. The execute skill's two "`EnterWorktree` with
  `path:`" places note that the hook enforces it.

### R6. Spec items: `L<a>` accepted; `studio-brief validate`

- Format, documented once in `studios/game-dev/skills/plan/SKILL.md` (the
  Spec-line rule): `Spec: <item>[, <item>…]`, an item being
  `<path>:L<a>-<b>`, `<path>:L<a>` (one line, the same as `L<a>-<a>`), or
  `<path>§<heading as written>`. The studio-brief header comment and the
  autopilot skill point at it instead of restating it; contract tests that
  assert the literal text follow.
- `studio-brief` parses items with one function shared by `task` and the new
  `validate` verb. `L<a>` is read as `L<a>-<a>`. `a > b`, a non-numeric
  bound, a missing file, a range past the end, or a heading not found exactly
  is an error.
- `studio-brief validate <plan-file>` needs no studio state. It checks every
  task block's first `Spec:` line (same task-block rules as `task`), resolving
  paths from the current directory as `task` does. It prints
  `studio-brief: task <n>: <error>` for each bad item and for a task with no
  `Spec:` line, then exits 1; otherwise it prints
  `studio-brief: <T> tasks, <I> Spec items ok` and exits 0. A missing plan
  file → exit 2.
- The plan skill's self-review runs `studio-brief validate <plan>` and fixes
  the plan until it exits 0, before `studio-state set plan`.

### R7. Skill and brief text

- The execute skill and `agents/gameplay-programmer.md` name
  `studio-test --file <test file>` for a single test file, and say: never
  build a Godot or GUT command by hand; pass `timeout` only to gate-routed
  commands; other commands keep the default cap.
- No other skill names a raw Godot line (verified: none does today).

## Non-goals

- No install, sync or deploy into `~/.claude-gamedev` (a phoenix run is live;
  the operator installs).
- No CPU sampling (#43's design), no flag-then-kill two-stage stall.
- No hook that clamps a model-requested `timeout`; the idle watchdog bounds a
  silent non-gate command instead.

## Acceptance criteria

Each has a test that fails before the change and passes after, in the repo's
sh test suites (`tests/*_test.sh`, `assert.sh`).

- AC1 (R1) A lanes unit at `session_minutes` 180 launches with
  `BASH_DEFAULT_TIMEOUT_MS=2700000` and `BASH_MAX_TIMEOUT_MS=5400000`; at 90,
  1800000/3600000; a single-plan unit gets the same pair; so does the final
  unit.
- AC2 (R2) A unit whose fake session writes its init line and then hangs
  silently is ended by the idle watchdog well before the session cap:
  outcome `stalled`, a `unit_stalled` event naming the open command, and
  (no progress, retries exhausted) ending `stalled on T1 (…)`.
- AC3 (R2) A silent unit with an open `studio-test` Bash call is not ended by
  the idle watchdog (the session cap ends it instead).
- AC4 (R2) `idle_minutes` 0 disables the watchdog; a bad value is refused
  in preflight.
- AC5 (R3) `studio-test --file a.gd,b.gd` and `--file a.gd --file b.gd` pass
  `-s addons/gut/gut_cmdln.gd -gconfig=… -gdir= -gtest=res://a.gd,res://b.gd
  -gexit` to Godot when a config exists, and no `-gconfig`/`-gdir=` when
  none does; a missing file exits 2 before Godot runs; the run goes through
  the gate; a failing test exits 1.
- AC6 (R4) The exact T7 command, a `cd x && Godot --headless --path . …`
  chain, a quoted path with spaces, `$GODOT --headless --path .`, and
  `A=1 godot4 --path .` are denied; with `-s`, `--import`, `--version`,
  `--export-release`, `--quit-after 5`, `-e`, plus `studio-test --file x`,
  `echo "Godot --headless --path ."`, and a non-Godot command, they are
  allowed. The hook is registered in hooks.json.
- AC7 (R5) `EnterWorktree {}` and `{"name":"x"}` are denied with
  `STUDIO_STORY=S1` and with `OMEGA_AUTOPILOT=1`; the message contains
  `path:`; `{"path":"/x"}` is allowed; with neither variable set, `{}` is
  allowed. Registered in hooks.json.
- AC8 (R6) `task` accepts `<spec>:L3` and emits line 3; `validate` passes a
  good plan, and reports each of: unparseable item, `L5-3`, missing file,
  past-EOF range, missing heading, task without `Spec:` (exit 1); missing
  plan file exits 2.
- AC9 (R3) Live check, once, in a throwaway project with phoenix's GUT addon
  (never in phoenix): `studio-test --file` with two files runs exactly those
  two and the pre/post scripts.
- AC10 The full gate `sh tests/run_all.sh` passes.
