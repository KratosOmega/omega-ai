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

Ground truth (execute skill, `tests/probes/bash_timeout_probe.sh`, 2026-10-02):
a Bash call that outlives its `timeout` is **moved to the background**, not
killed; the call returns and the process keeps running. So a Bash timeout
gives the session its turn back. It does not end the process, and it must
never be what bounds a gate call (a backgrounded gate is a hard
`Stop: gate timed out`).

- **Command cap.** `CMD_MIN = min(45, SESSION_MINUTES / 3)` (integer
  minutes) → `BASH_DEFAULT_TIMEOUT_MS = CMD_MIN × 60000`. Every Bash call
  that does not pass `timeout` gets it. At phoenix's 180-min session that is
  45 min, which still fits a 15–35 min gate called without `timeout`; at the
  default 90-min session it is 30.
- **Ceiling unchanged.** `BASH_MAX_TIMEOUT_MS` stays `SESSION_MINUTES ×
  60000`. Gate-routed calls (`studio-test`, `studio-run`, `studio-setup`,
  `studio-setup gate`, `studio-gate`) keep requesting it, so a long wait for
  the gate lock behind other lanes is never moved to the background.
- **Gate run cap.** `GATE_MIN = min(60, SESSION_MINUTES / 2)` is exported
  to the session as `STUDIO_GATE_MINUTES`. `studio-gate` starts a timer
  **once it holds the lock** (waiting does not count). A command still
  running at `STUDIO_GATE_MINUTES` gets TERM to its process group, then KILL
  after the existing grace. studio-gate prints
  `gate: <who> ran past <n> min — stopped` to stderr, records rc 124 in
  `gate.times`, and exits 124. Unset, empty or 0 means no cap, which is
  today's behavior for interactive use. `who` `setup` is exempt because
  worktree_setup keeps its own `worktree_setup_minutes` timer. Re-entry
  (`STUDIO_GATE_HELD`) adds no second timer. At phoenix's 180 min this is
  60: a 35-min gate fits with 1.7× headroom, and a hung test run costs at
  most an hour, not the unit.
- `gate_room_check` also warns when the slowest recent `studio-test`
  or `gate` run × 1.2 exceeds `GATE_MIN`, naming the setting to raise.
- One helper computes `CMD_MIN`/`GATE_MIN`. Every runner-launched `claude`
  session gets `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS` and
  `STUDIO_GATE_MINUTES`: single-plan units (today they set no BASH_*
  variable), lane story units, the final unit, and the land, gate and sync
  repairs (all go through `run_unit`). The three existing
  `SESSION_MINUTES * 60000` sites (`overnight-lanes.sh` ~389, ~1104, ~1673)
  use the helper.
- Documented in `studio-overnight --help` (the `session_minutes` row) and
  README's overnight section.

### R2. Idle watchdog (`overnight.idle_minutes`)

- New config `overnight.idle_minutes`: int, default 20, range 0–120, where
  0 turns the watchdog off. It is read with `cfg` in `preflight`. Test
  seams: `STUDIO_OVERNIGHT_IDLE_SECONDS` replaces `idle_minutes × 60`, and
  `STUDIO_OVERNIGHT_IDLE_POLL_SECONDS` sets the check interval (default 30).
  `--help` lists both.
- **Idle** means the session's stream-json log (`<stem>.jsonl`) has not
  grown. Subagent tool calls stream into the parent log (`parent_tool_use_id`;
  T5's log has 390 such lines), so a working subagent is not idle.
- **Open calls.** A new function lists the session's open (unanswered)
  `tool_use` calls from the log. It reuses `unit_activity`'s `closed[]`
  logic; `unit_activity` itself shows only the last call. It renders each
  call the way `unit_activity` renders a tool, with newlines and tabs
  flattened, cut to 120 chars.
- **Gate exemption.** The idle clock does not fire while an open Bash call's
  command invokes `studio-test`, `studio-run`, `studio-setup` or
  `studio-gate`, or while the unit is registered under
  `.studio/gate.units/<tag>/`. studio-gate registers before it waits, so this
  covers lock waits. Those calls are bounded by the gate run cap (R1).
- **Ordering.** In a silent session the idle watchdog (20) fires before the
  command cap (45/30): a hung plain command ends the unit as `stalled` at
  ~20 min, rather than the 180 min T7 cost. The command cap matters when
  other activity keeps the log growing (parallel subagents) and when the
  watchdog is off. A legitimately silent non-gate command longer than
  `idle_minutes` is ended. That cost is accepted, because long work belongs
  in the gate-routed verbs.
- **On a stall** (idle ≥ the limit, not exempt), the watchdog takes the same
  `.ended` mkdir claim as the session-cap watchdog. Exactly one of {session
  cap, idle watchdog, normal exit} ends a unit. After winning the claim it
  writes `stalled` (holding `idle_min` and the open command) inside the
  claim dir, so the runner can tell a stall from a cap kill. It then sends
  TERM to the process group, and KILL after `GRACE`. It emits
  `unit_stalled` with `story`, `unit`, `label`, `idle_min` and `command`:
  the first open call, or `-` if none. The outcome is `stalled`. In
  units.tsv the timed_out column stays the session-cap flag (0 for a
  stall), and the outcome column carries `stalled`.
- **Retry and hold.** `stalled` is handled like `timed out`. A stalled unit
  that moved the state signature is `progress`. Otherwise it counts toward
  `retries`, and once they are used up the ending is
  `stalled on <base> (no output for <N> min: <command>)`. Repairs mirror
  their `… timed out` endings with `… stalled (…)`. `holdable` holds both
  forms. The command text in an ending must not break `held_line` parsing;
  the implementer checks what it splits on.
- The watchdog runs in `run_unit` alongside the session-cap watchdog.
  `merge_wait` waits on a merge command, not a session, so it is not
  watched. A unit waiting for a session slot has no session yet and is not
  watched.
- `docs/game-dev/overnight-events.md` documents `unit_stalled` and the
  `stalled` outcome.
- #43's CPU signal is dropped: T7's hung Godot was a busy loop, which a
  "no CPU" test would have missed.

### R3. `studio-test --file`

- `studio-test --file <path>` runs only the named GUT script(s). `--file` is
  repeatable and takes a comma list (`--file a.gd,b.gd --file c.gd`). A path
  is relative to the project root; a leading `./` or `res://` is stripped.
- It goes through `studio-gate` with who `studio-test-file`, so file runs
  are timed separately in `gate.times` and do not push full-suite times out
  of `gate_room_check`'s window. Exit codes follow the existing rules: GUT
  failures or a nonzero engine status → 1, 0 tests → 1, no Godot → 2,
  no GUT → 3, gate run cap → 124.
- A named file that does not exist → **exit 4** with
  `studio-test: no such test file <path>`, before Godot starts. Not 2:
  execute reads 2 as "no Godot binary" and stops.
- Command built, as proven by the probe: `-s addons/gut/gut_cmdln.gd`, then
  `-gconfig=res://<cfg>` and `-gdir=` when the project has a GUT config, then
  `-gtest=res://<a>[,res://<b>…]`, `-gexit`, `-gjunit_xml_file=…`. **In a
  file run** `-gconfig` is never passed without `-gdir=`. The full-suite form
  is unchanged: it passes `-gconfig` alone when the config names `dirs`. A
  comment cites the probe so the file form is not "simplified" later.
- A positional argument that is an existing file (`studio-test
  tests/unit/x.gd`) means `--file tests/unit/x.gd`. Any other positional
  argument (a directory or a nonexistent path) behaves as today.
- `engines/godot/GUIDE.md` documents `--file`.
- AC10 checks the multi-file form (`-gdir=` plus a comma `-gtest`) once
  against real GUT before merge.

### R4. Godot guard hook (every game-dev session)

- New `studios/game-dev/hooks/godot-guard.sh`, registered in
  `hooks/hooks.json` as a `PreToolUse` hook on `Bash`. It is active in every
  game-dev session, interactive or unattended.
- POSIX sh with sed/awk, no jq or python, so the hooks stay self-contained.
  It denies with the `permissionDecision: deny` JSON, as
  `autopilot-guard.sh` does. It always exits 0, so a parse problem never
  blocks a call.
- The command reaches the hook JSON-escaped (`\"`, `\\`, and newlines as
  `\n`). The hook unescapes these first.
- It splits the command into simple commands at `;`, `&&`, `||`, `|`, `&`
  and newlines. In each, it skips leading `NAME=value` assignments and the
  wrappers `env`, `exec`, `command`, `time`, `nice` and `timeout <n>`.
- The first word, with quotes removed, is a **Godot invocation** when either:
  - its basename matches `godot*` case-insensitively (`Godot`, `Godot_mono`,
    `godot4`, `Godot_v4.3-stable_linux.x86_64`), including a quoted path
    with spaces; or
  - it is a `$GODOT…` or `${GODOT…}` variable.
- A Godot invocation is **refused** when either:
  - **(a)** it has `--path` or `--headless` and none of these tokens: `-s`,
    `--script`, `--import`, `-e`, `--editor`, any `--export*`, `--version`,
    `--doctool`, `--quit`, `--quit-after`, `--help`, `-h`. A headless boot of
    the main scene never exits.
  - **(b)** it names `gut_cmdln`. A hand-built GUT run skips the gate lock
    that serializes Godot across lanes, and without `-gdir=` it runs the
    whole suite (see the probe).
- The refusal message is one line that names the case. It points to
  `studio-test --file <tests/unit/x.gd>` (repeatable) for test files,
  `studio-test` for the suite and `studio-run` for the game.
- A command whose first word is not Godot is allowed, for example
  `echo "Godot --headless --path ."` or `grep -r godot --path`. The engine
  adapters run Godot inside their own scripts, which the hook never sees.

### R5. EnterWorktree guard in story sessions

- New `studios/game-dev/hooks/worktree-guard.sh`, a `PreToolUse` hook on
  `EnterWorktree`. When `STUDIO_STORY` is non-empty, it denies a call whose
  `tool_input` has no non-empty `path`. A `name` alone is denied too, because
  it creates a new worktree.
- Without `STUDIO_STORY` every call is allowed, including
  `OMEGA_AUTOPILOT=1` single-plan units. Their isolation step (execute §0
  (b), `superpowers:using-git-worktrees`) legitimately creates a worktree
  with a name or with no arguments.
- The message names the story worktree, taken from the first of these that
  works:
  1. the output of `sh "$HERE/../bin/studio-state" worktree` when it exits 0
     (the bin is located the way `peer-runs.sh` does it);
  2. else the path that command suggests when it exits 3;
  3. else the rule from execute §0, `<STATE_ROOT>/.claude/worktrees/<Branch
     with / → ->`.

  Text: in a story session `EnterWorktree` needs `path:`, because a bare call
  creates a stray worktree; use `path: <P>`.
- Same deny mechanics as R4. The execute skill's two "`EnterWorktree` with
  `path:`" places note that the hook enforces it.

### R6. Spec items: `L<a>` accepted; `studio-brief validate`

- The format is documented once, in `studios/game-dev/skills/plan/SKILL.md`
  (the Spec-line rule): `Spec: <item>[, <item>…]`. An item is one of:
  - `<path>:L<a>-<b>`;
  - `<path>:L<a>`, one line, the same as `L<a>-<a>`;
  - `<path>§<heading as written>`.
- The studio-brief header comment points at the plan skill instead of
  restating the format. The autopilot skill's adopt instruction
  (`<original>:L<a>-<b>`) stays, since it does not restate the format.
  Contract assertions that quote the plan skill's text
  (`tests/studio_test.sh` ~684) follow the new wording.
- `studio-brief` parses items with one function shared by `task` and the
  new `validate` verb.
  - The function returns its error instead of exiting, so `validate` can
    collect all of them. `task` still exits 1 on the first error.
  - `L<a>` is read as `L<a>-<a>`.
  - These are errors: `a > b`, a non-numeric bound, a missing file, a range
    past the end, a heading not found exactly.
- `studio-brief validate <plan-file>` needs no studio state.
  - It checks the first `Spec:` line of every task block, using the same
    task-block rules as `task`. It resolves paths from the current directory,
    as `task` does.
  - It prints `studio-brief: task <n>: <error>` for each bad item and for
    each task with no `Spec:` line, then exits 1.
  - Otherwise it prints `studio-brief: <T> tasks, <I> Spec items ok` and
    exits 0.
  - A missing plan file exits 2.
- The plan skill's self-review runs `studio-brief validate <plan>` and fixes
  the plan until it exits 0, before `studio-state set plan`.

### R7. Skill, brief and hook text

- The execute skill and `agents/gameplay-programmer.md` say:
  - Run a single test file with `studio-test --file <test file>`.
  - Never build a Godot or GUT command by hand.
  - Pass `timeout: $BASH_MAX_TIMEOUT_MS` only to gate-routed commands;
    every other command keeps the default cap.
  - A command that its timeout moved to the background is treated as hung:
    stop it with the tool that stops background tasks, and do not wait for
    it.
  - A gate-routed command that exits 124 is `Stop: gate timed out —
    <command> ran past <n> min`, the rule that today applies to a
    backgrounded gate.
- Execute's sentence "the timeout is the whole session's minutes" is
  rewritten to describe R1.
- `autopilot-guard.sh`'s background-Bash denial now says to pass `timeout`
  only on gate-routed commands, instead of telling every command to use
  `$BASH_MAX_TIMEOUT_MS`.
- No other skill names a raw Godot line (verified: none does today).

## Non-goals

- No install, sync or deploy into `~/.claude-gamedev`. A phoenix run is live,
  and the operator installs.
- No CPU sampling (#43's design) and no two-stage flag-then-kill stall.
- No hook that clamps a model-requested `timeout`. The idle watchdog bounds a
  silent non-gate command instead.
- Adopt-converted plans (autopilot adopt) do not run `validate` here.

## Acceptance criteria

Each criterion has a test that fails before the change and passes after it,
in the repo's sh test suites (`tests/*_test.sh`, `assert.sh`). The
overnight_test.sh fake `claude` records the launched session's
`BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS` and `STUDIO_GATE_MINUTES`,
and it can emit a `tool_use` line before it hangs.

- AC1 (R1) A lanes unit at `session_minutes` 180 launches with
  `BASH_DEFAULT_TIMEOUT_MS=2700000`, `BASH_MAX_TIMEOUT_MS=10800000` and
  `STUDIO_GATE_MINUTES=60`. At 90 it launches with 1800000/5400000/45. A
  single-plan unit and the final unit get the same values.
- AC2 (R1) With `STUDIO_GATE_MINUTES` set, a gate command running past the
  cap is stopped: studio-gate exits 124, prints `ran past`, and records rc
  124. Time spent waiting for the lock does not count. When the variable is
  unset there is no cap, and who `setup` is never capped. The tests use a
  seconds seam.
- AC3 (R2) A fake session writes init plus an open Bash `tool_use`
  (`sleep …`), then hangs silently. The idle watchdog ends it well before the
  session cap, with outcome `stalled` and a `unit_stalled` event naming that
  command. With no progress and retries used up, the ending is
  `stalled on T1 (…)`, which `holdable` accepts.
- AC4 (R2) A silent session with an open `studio-test` Bash call is not ended
  by the idle watchdog. The session cap ends it instead, with `timed out`.
- AC5 (R2) `idle_minutes` 0 turns the watchdog off. Preflight refuses a bad
  value.
- AC6 (R3) When a config exists, `studio-test --file a.gd,b.gd` and
  `--file a.gd --file b.gd` both pass `-s addons/gut/gut_cmdln.gd -gconfig=…
  -gdir= -gtest=res://a.gd,res://b.gd -gexit` to Godot. When none exists,
  they pass no `-gconfig` or `-gdir=`. A missing file exits 4 before Godot
  runs. The run goes through the gate as `studio-test-file`, and a failing
  test exits 1.
- AC7 (R4) Denied:
  - the exact T7 command;
  - a `cd x && Godot --headless --path . …` chain;
  - a quoted path with spaces;
  - `$GODOT --headless --path .`;
  - `A=1 godot4 --path .`;
  - a `\n`-separated second line;
  - `Godot --headless -s addons/gut/gut_cmdln.gd …`.

  Allowed:
  - `-s other.gd`, `--import`, `--version`, `--export-release`,
    `--quit-after 5` and `-e`;
  - `studio-test --file x`;
  - `echo "Godot --headless --path ."`;
  - a non-Godot command.

  The hook is registered in hooks.json.
- AC8 (R5) With `STUDIO_STORY=S1`, `EnterWorktree {}` and `{"name":"x"}`
  are denied, with a message containing `path:`, and `{"path":"/x"}` is
  allowed. With only `OMEGA_AUTOPILOT=1`, or with neither variable set, `{}`
  and `{"name":"x"}` are allowed. The hook is registered in hooks.json.
- AC9 (R6) `task` accepts `<spec>:L3` and emits line 3. `validate` passes a
  good plan. In one run it reports all of these and exits 1: an unparseable
  item, `L5-3`, a missing file, a past-EOF range, a missing heading, and a
  task without `Spec:`. A missing plan file exits 2.
- AC10 (R3) A live check, run once in a throwaway project with phoenix's GUT
  addon (never in phoenix): `studio-test --file` with two files runs exactly
  those two plus the pre/post scripts.
- AC11 (R7) The pointer and contract suites (`pointer_skills_execute_test.sh`,
  `studio_test.sh`, `omega_contracts/`) pass with the new skill text.
- AC12 The full gate `sh tests/run_all.sh` passes.
