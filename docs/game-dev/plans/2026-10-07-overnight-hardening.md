# Overnight Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A unit can lose at most one bounded command to a hang. A hang is noticed in minutes rather than hours. The two hand-built calls that sank phoenix T7 are refused before they run: a raw headless Godot, and a bare `EnterWorktree`. Plan review catches a malformed `Spec:` item.

**Architecture:** The work falls into five lanes, each touching its own set of files.
- **Runner (A).**
  - A1: one helper (`session_caps`/`caps_env` in `studio-overnight`) gives every session the same three caps: single-plan units, lane units, the final unit and repairs.
  - A2: an idle check is folded into `run_unit`'s existing watchdog process. It uses the same `.ended` claim, plus a new `open_calls` reader of the stream-json log.
- **Gate (B).**
  - B1: `studio-gate` times the command it runs, once it holds the lock.
  - B2: `studio-test --file` builds the probe-proven GUT file form through `engines/godot/test.sh`.
  - B3: checks that form live, once, in a throwaway project.
- **Hooks (C).** Two new self-contained PreToolUse hooks: `godot-guard.sh` on `Bash` and `worktree-guard.sh` on `EnterWorktree`. One sentence changes in `autopilot-guard.sh`.
- **Brief (D).** One `spec_item` parser in `studio-brief`, shared by `task` and a new `validate` verb. The plan skill's self-review runs `validate`.
- **Skill text (E).** The execute skill and `gameplay-programmer` say the R7 rules.

**Tech Stack:**
- POSIX sh (macOS `/bin/sh` = bash 3.2, Linux `dash`), with awk and sed.
- The plain-sh suites `tests/*_test.sh` with `tests/assert.sh` (`run_tests`, and `TESTS_ONLY="a b"` to pick tests).
- Godot 4.6.3 mono with GUT 9.6.0, for the B3 live probe only.
- No new dependencies. No jq or python in a hook.

**Spec:** `docs/game-dev/specs/2026-10-07-overnight-hardening.md` (R1–R7, AC1–AC12).

Story: #59 (GitHub issue; supersedes #43). Branch `59-overnight-hardening`. omega-ai has no Jira. **Base:** 1796538. Line numbers are as of that commit; relocate each one with its `grep -n` anchor.

## Global Constraints

Quoted from the spec. Do not change them.

- **Command cap.** `CMD_MIN = min(45, SESSION_MINUTES / 3)` (integer minutes) → `BASH_DEFAULT_TIMEOUT_MS = CMD_MIN × 60000`.
- **Ceiling.** `BASH_MAX_TIMEOUT_MS` stays `SESSION_MINUTES × 60000`.
- **Gate run cap.** `GATE_MIN = min(60, SESSION_MINUTES / 2)` is exported to the session as `STUDIO_GATE_MINUTES`.
  - At 180 min the caps are 2700000 / 10800000 / 60. At 90 min they are 1800000 / 5400000 / 45.
  - The gate prints `gate: <who> ran past <n> min — stopped` to stderr, records rc 124 in `gate.times`, and exits 124.
  - "Unset, empty or 0 means no cap." "`who` `setup` is exempt." "Re-entry (`STUDIO_GATE_HELD`) adds no second timer." The timer starts "**once it holds the lock** (waiting does not count)". Escalation is TERM to the process group, then KILL after the existing grace (10 s).
- **`overnight.idle_minutes`.** "int, default 20, range 0–120, where 0 turns the watchdog off".
  - Test seams: `STUDIO_OVERNIGHT_IDLE_SECONDS` replaces `idle_minutes × 60`. `STUDIO_OVERNIGHT_IDLE_POLL_SECONDS` sets the check interval (default 30).
  - The outcome is `stalled`. The event is `unit_stalled` with `story`, `unit`, `label`, `idle_min`, `command`.
  - The ending is `stalled on <base> (no output for <N> min: <command>)`. The units.tsv timed_out column "stays the session-cap flag (0 for a stall)".
- **Gate-routed verbs.** These are `studio-test`, `studio-run`, `studio-setup` and `studio-gate`. The idle exemption matches an open Bash call's command against `studio-(test|run|setup|gate)`, or a non-empty `.studio/gate.units/<tag>/`.
- **studio-test exit codes.** 0 pass · 1 failures / 0 tests / nonzero engine · 2 no Godot · 3 no GUT · **4** missing test file, with `studio-test: no such test file <path>`, before Godot starts · **124** gate run cap.
  - The file run's gate `who` is `studio-test-file`. The full suite keeps `studio-test`.
- **Hooks.** POSIX sh with sed/awk, "no jq or python, so the hooks stay self-contained".
  - Deny with the `permissionDecision: deny` JSON, as `autopilot-guard.sh` does.
  - Always exit 0, so a parse problem never blocks a call.
  - Hook files are executable: `test_bin_syntax` requires `sh -n` and `-x`.
- **No install into `~/.claude-gamedev`.** No sync or deploy, and no pull into the main checkout. "A phoenix run is live, and the operator installs."
- **POSIX sh only.** No `local`. Function variables carry a per-function prefix (`_sc_`, `_oc_`, `_si_`, …).
- **Suite isolation.** `tests/overnight_test.sh` and `tests/overnight_lanes_test.sh` never run at the same time in one checkout. Parallel tasks run in separate worktrees, each running only its affected suites. The full gate runs once, on the integrated branch.
- **Review policy.**
  - Per-task Opus review for A1, A2, B1, C1 and D1 (new seam, cross-system, or a parser).
  - B2, C2 and E1 fold into the final review. B3 is a live check, not a code task.
  - A standalone whole-branch Opus review always runs at the end.
  - Re-review only after a Critical, 3 or more Importants, or a production-bug fix. Never run a third pass.

## Execution shape (maximum parallelism)

| Task | Depends on | Wave | Review | Files (hunks) |
|------|------------|------|--------|---------------|
| A1 caps helper + env everywhere + GATE_MIN warning | — | 1 | task (Opus) | `studio-overnight` (top vars, new helpers, `gate_room_check`, `print_launch`, `start_session`, preflight, help row); `overnight-lanes.sh` (`story_launch_env`, `run_story`, `final_unit`); `overnight_test.sh` (stub `.caps`, help list, 1 test); `overnight_lanes_test.sh` (3 tests); `README.md` overnight bullet |
| A2 idle watchdog | A1 | 2 | task (Opus) | `studio-overnight` (`cfg`/seams, `open_calls`, `run_unit`, `unit_outcome`, `stall_note`, `story_units`, `holdable`, `activity` verb, help); `overnight-lanes.sh` (3 repair endings); `overnight_test.sh` (stub `emit`/`gatereg`, 5 tests, help + events lists); `overnight_lanes_test.sh` (1 test, 1 loop case); new `tests/fixtures/overnight-open-calls.jsonl`; `docs/game-dev/overnight-events.md`; `README.md` overnight bullet |
| B1 studio-gate run timer | — | 1 | task (Opus) | `studio-gate` (header, timer, `release`, after the wait loop); `toolkit_test.sh` (5 gate tests) |
| B2 `studio-test --file` | B1 | 2 | final | `studio-test`; `engines/godot/test.sh`; `engines/godot/GUIDE.md`; `README.md` row :95; `toolkit_test.sh` (5 tests) |
| B3 AC10 live probe | B2 | 3 | — (live) | new `tests/probes/studio_test_file_probe.sh` |
| C1 godot-guard | — | 1 | task (Opus) | new `hooks/godot-guard.sh`; `hooks/hooks.json`; `hook_test.sh` (5 tests) |
| C2 worktree-guard + autopilot text | C1 | 2 | final | new `hooks/worktree-guard.sh`; `hooks/hooks.json`; `hooks/autopilot-guard.sh` :57; `hook_test.sh` (4 tests + 1 assertion) |
| D1 Spec items, `validate` | — | 1 | task (Opus) | `studio-brief` (header, usage, `spec_item`, `emit_task`, `validate`); `skills/plan/SKILL.md` (:74-77, :151-156); `studio_brief_test.sh` (6 tests); `studio_test.sh` (`test_plan_brainstorm_lanes` :684-688) |
| E1 skill text | — | 1 | final | `skills/execute/SKILL.md` (:116-118, :143-161, :273-276, §2 :341-346); `agents/gameplay-programmer.md` (:34-36); `studio_test.sh` (2 new tests near :576) |
| F final review, fix wave, gate, PR | all | 4 | — | `docs/game-dev/PROGRESS.md` |

**Waves.**
- Wave 1 runs A1, B1, C1, D1 and E1 concurrently. Each runs in its own worktree off the story branch at this plan's commit.
- Wave 2 runs A2, B2 and C2. Each starts from its lane's wave-1 commit, either in the same lane worktree or in a fresh one with the predecessor cherry-picked.
- Each lane is integrated onto the story branch by cherry-pick, in the order A, B, C, D, E.

**Shared files.** Only these are touched by more than one lane, always in disjoint hunks:
- `README.md`: A1 and A2 edit the Overnight runs bullet at :152-163. B2 edits the `studio-test` table row at :95.
- `tests/studio_test.sh`: D1 edits `test_plan_brainstorm_lanes` (:678-690). E1 adds new functions after `test_execute_lane_gate_foreground` (:576-596) and appends their names to that file's `run_tests` line. The cherry-pick of the second lane may need a trivial merge on the `run_tests` line.

Within a lane, tasks run in sequence, because they share a file:
- A1 then A2 share `studio-overnight` and both overnight suites.
- B1 then B2 share `toolkit_test.sh`.
- C1 then C2 share `hooks.json` and `hook_test.sh`.

## Decisions

- **D1 — Where the caps live.** `session_caps` and `caps_env` live in `studio-overnight`, because the single-plan path never sources `overnight-lanes.sh`. The lanes file calls them.
  - Single-plan default launch words become `$(caps_env) OMEGA_AUTOPILOT=1`, with the caps first. This keeps the literal `OMEGA_AUTOPILOT=1 claude-gd -p '/game-dev:execute --one'` that `tests/overnight_test.sh:302` and `:517` assert.
- **D2 — The runner's own gates are never capped.** `studio-overnight` runs `unset STUDIO_GATE_MINUTES` beside `LAUNCH_ENV=""` (:27). `run_story` keeps exporting only `BASH_*`.
  - Without this, the runner's merge (`studio-gate merge`, lanes :635) and final gate (`studio-gate final-gate`, :1713) would inherit a cap from an operator shell. `STUDIO_GATE_MINUTES` reaches sessions only through `LAUNCH_ENV`.
  - Repairs reuse the story's `LAUNCH_ENV`, so they inherit the caps with no change.
- **D3 — Normalized minutes.** `cfg` accepts `090`, and `$((090 / 3))` is an octal error in the shell. Preflight re-reads `SESSION_MINUTES` and `IDLE_MINUTES` through `awk '{print $1+0}'` right after their `cfg` calls.
- **D4 — One watchdog process.** The idle check runs inside `run_unit`'s existing watchdog subshell as a poll loop.
  - Each nap is `min(time left, poll)` when the idle check is on, else the time left. There is still one `WPID`, so `LDIR/wpid`, `lanes_end_sessions` and the teardown are unchanged.
  - Idle means the log's byte count (`wc -c`) is unchanged across polls since the last growth. The first poll records the size.
- **D5 — Stall marker without races.** The watchdog first writes `<stem>.ended.stall` (`idle_min=` and `command=`), then makes the claim `mkdir <stem>.ended`.
  - Winning the claim, it `mv`s the file to `<stem>.ended/stalled`. Losing, it removes the file and exits.
  - When the runner loses the claim, it kills and reaps the watchdog first, then reads `ended/stalled`, else `ended.stall`. Either one present means a stall; neither means a session-cap kill.
  - Both `rmdir "$_claim"` calls (:1148, :1179) become `rm -rf "$_claim" "$_claim.stall"`, because `rmdir` fails on a non-empty claim.
- **D6 — "The first open call"** is the **newest** open call. That is the innermost one: a subagent's hung Bash rather than the `Agent` call around it.
  - `open_calls` prints open calls newest first. The ending and the event use line 1, else `-`.
- **D7 — N in a stall ending** is `IDLE_MINUTES`, the config value, even when the seconds seam drives the clock. This follows the precedent of `timed out on X (session_minutes N)` under `STUDIO_OVERNIGHT_SESSION_SECONDS`.
- **D8 — `held_line` is safe.** Verified at :882-885. It removes `${r% until *}` and takes `${r##* until }`: the shortest suffix and the longest prefix, so it splits on the **last** ` until `. `state_event` (:735) does the same.
  - A command containing ` until ` (for example `until false; do sleep 1; done`) is pinned by a test (Review Focus 2).
- **D9 — The GATE_MIN warning** is a separate `say` line starting `warning: gate run cap:`. It must not start with `warning: the slowest`, because `test_lanes_gate_room_warning` asserts that text is absent for small gates.
  - Trigger: `max(slowest of the last 10 studio-test, slowest of the last 10 gate) × 1.2 > GATE_MIN`.
  - When the needed minutes N (that × 1.2, rounded up) are 60 or less, it names `overnight.session_minutes` ≥ `2 × N`. Above 60 it says the cap tops out at 60 min.
  - `studio-test-file` lines are never read, because the awk matches `$2 == "studio-test"` exactly.
- **D10 — The gate timer escalates by itself.** The existing wait loop (`studio-gate` :199-204) never ends while a TERM-ignoring child lives. Its straggler KILL (:205-214) only runs after the loop.
  - So the timer process sends `ALRM` to the gate shell, which TERMs the targets through `on_signal 124`. It then sleeps 10 s and KILLs the child's targets itself.
  - The gate kills the timer the moment the wait loop ends, and `release` kills it too. The timer's stdout and stderr are `/dev/null`, so a caller's `$( … )` never waits on it.
- **D11 — studio-test argument rules.**
  - `--file` takes a comma list and is repeatable. `--file=LIST` is accepted too.
  - Each item is trimmed of spaces, and empty items are skipped. A leading `res://` or `./` is stripped. An absolute path under the project (`pwd -P` or `$PWD`) is made relative. Duplicates are dropped.
  - Each item must be an existing file under the project. Otherwise the exit is 4 with the spec's message: missing, absolute outside the project, a `..` component, or a directory.
  - A single positional that is an existing file means `--file`.
  - Misuse exits **4** with a usage line, never 2, because execute reads 2 as "no Godot". Misuse means `--file` with no value, `--file` mixed with a positional, or no item left after trimming.
  - The existence check runs in `studio-test` before the gate, so nothing waits for the lock to report a typo. `test.sh` re-checks.
- **D12 — `validate` paths.** `studio-brief` changes directory to `studio-state root --work` (:99) before any verb runs.
  - `validate` resolves the **plan path** against the caller's directory, captured before that `cd`.
  - `Spec:` item paths resolve from the work root, as `task` does.
  - Bad items go to stderr as `studio-brief: task <n>: <error>`. The ok line goes to stdout.
  - A plan with no `### Task` block is an error (exit 1).
- **D13 — `L<a>-<b>` with a > b** reports `bad range in Spec: item '<item>'`. Today it says "past the end", which is misleading. The other error texts are kept as they are.
- **D14 — The worktree guard's path source.** The guard reads the exit-3 path from the second stderr line of `studio-state worktree`, `[<prefix>]git worktree add '<path>' '<br>'` (`studio-state` :649-650), with `sed`.
  - The fallback branch is `studio-state get branch`. The root is `studio-state root`.
  - The path is JSON-escaped (`\` and `"`) before it goes into the deny reason.
- **D15 — The Godot guard's command splitter** is quote-aware. A `;` or `&&` inside quotes does not split. So `echo "a; Godot --headless --path ."` is allowed.
  - It also skips the shell keywords `if then else elif do while until ! { (` in front of a command.

## Review Focus

1. **A gate call whose command is longer than 120 characters must still exempt the unit.** For example, a long absolute `cd` before `studio-test`. The rendered open call is cut to 120 characters, so the exemption must match the full command. Pinned by `test_overnight_idle_spares_gate_call` (A2), whose fixture puts `studio-test` past character 120, and by `test_overnight_open_calls` (A2, `gate` mode on the long line).
2. **A stalled ending whose command contains ` until `** must still hold, show and resume. This covers `held_line`, `state_event`, and the report's `(held …)` suffix. Pinned by `test_overnight_stall_holds_with_until_command` (A2).
3. **The gate cap against a command that ignores TERM.** The run must end about 10 s after the cap with 124. A command that ends before the cap keeps its own status, returns at once (the timer never holds the caller's pipe), and never records 124. Pinned by `test_gate_run_cap_kills_a_term_ignorer` and `test_gate_run_cap_no_false_stop` (B1).
4. **Godot guard inputs.** Each of these is pinned by `test_godot_guard_denies_headless_boot` / `test_godot_guard_allows` (C1):
   - a quoted path with spaces;
   - JSON `\"` inside the command;
   - a `\n`-separated second line;
   - `timeout 5 godot …`;
   - `env A=1 Godot_mono …`;
   - a `;` inside quotes (allowed);
   - `echo "Godot --headless --path ."` (allowed).
5. **`--file` path forms.** These are pinned by `test_test_file_path_forms` (B2):
   - an absolute path inside the project (accepted, made relative);
   - one outside it (4);
   - `res://` and `./` prefixes;
   - spaces after commas;
   - a duplicate (passed once);
   - `../` (4).
   - The AC9 item `<spec>:L144` (the phoenix incident) is pinned by `test_brief_single_line_item` (D1).

## File Structure

- Create:
  - `studios/game-dev/hooks/godot-guard.sh` (C1, `chmod +x`).
  - `studios/game-dev/hooks/worktree-guard.sh` (C2, `chmod +x`).
  - `tests/fixtures/overnight-open-calls.jsonl` (A2).
  - `tests/probes/studio_test_file_probe.sh` (B3, `chmod +x`; not run by `run_all.sh`, which runs `*_test.sh` only).
- Modify `studios/game-dev/bin/studio-overnight` (A1, A2), `studios/game-dev/bin/overnight-lanes.sh` (A1, A2) and `studios/game-dev/bin/studio-gate` (B1).
- Modify `studios/game-dev/bin/studio-test`, `studios/game-dev/engines/godot/test.sh` and `studios/game-dev/engines/godot/GUIDE.md` (B2).
- Modify `studios/game-dev/hooks/hooks.json` (C1, C2) and `studios/game-dev/hooks/autopilot-guard.sh` (C2).
- Modify `studios/game-dev/bin/studio-brief` and `studios/game-dev/skills/plan/SKILL.md` (D1).
- Modify `studios/game-dev/skills/execute/SKILL.md` and `studios/game-dev/agents/gameplay-programmer.md` (E1).
- Modify `docs/game-dev/overnight-events.md` (A2), `README.md` (A1, A2, B2) and `docs/game-dev/PROGRESS.md` (F).
- Modify the test suites:
  - `tests/overnight_test.sh` and `tests/overnight_lanes_test.sh` (A1, A2);
  - `tests/toolkit_test.sh` (B1, B2);
  - `tests/hook_test.sh` (C1, C2);
  - `tests/studio_brief_test.sh` (D1);
  - `tests/studio_test.sh` (D1, E1).

---

### Task A1: Caps helper, caps in every session, GATE_MIN warning (R1, AC1)

Review: task (Opus). Wave 1. Lane A.

**Files:**
- Modify `studios/game-dev/bin/studio-overnight`:
  - the top vars at :27;
  - new helpers above `gate_room_check` (:604);
  - `gate_room_check` (:611-628);
  - `print_launch` (:239-243);
  - `start_session` (:1104-1114);
  - preflight (:580-588);
  - the help `session_minutes` row (:394-397).
- Modify `studios/game-dev/bin/overnight-lanes.sh`:
  - `story_launch_env` (:383-392);
  - `run_story` (:1104-1106);
  - `final_unit` (:1673-1674).
- Modify `tests/overnight_test.sh`:
  - the stub (after the `.env` line, :34);
  - `test_overnight_help` (:230-235);
  - a new test;
  - `run_tests` (:2208).
- Modify `tests/overnight_lanes_test.sh`: three new tests, plus `run_tests` (:4245).
- Modify `README.md`: the Overnight runs bullet (:152-163).

**Interfaces:**
- **Produces**, which A2, B1 and F rely on:
  - `session_caps` sets `CMD_MIN GATE_MIN CMD_MS MAX_MS` from `${SESSION_MINUTES:-90}`.
  - `caps_env` prints `BASH_DEFAULT_TIMEOUT_MS='<CMD_MS>' BASH_MAX_TIMEOUT_MS='<MAX_MS>' STUDIO_GATE_MINUTES='<GATE_MIN>'` with `sq` quoting and no trailing newline.
  - Sessions get the env vars `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS` and `STUDIO_GATE_MINUTES`.
  - The stderr warning line `studio-overnight: warning: gate run cap: …`.
- **Consumes:** `sq`, `say`, `SESSION_MINUTES` (set by `cfg`), and `STATE_ROOT`.

Anchors:
- `grep -n '^LAUNCH_ENV=""\|^print_launch()\|^start_session()\|^gate_room_check()\|cfg session_minutes\|^  session_minutes' studios/game-dev/bin/studio-overnight`
- `grep -n '^story_launch_env()\|BASH_DEFAULT_TIMEOUT_MS=\$((SESSION_MINUTES\|_fu_ms=' studios/game-dev/bin/overnight-lanes.sh`
- `grep -n 'printf .%s\\n. "\${OMEGA_AUTOPILOT:-unset}"' tests/overnight_test.sh`

- [ ] **Step 1: Stub records the caps.** In `tests/overnight_test.sh`'s stub, after the `.env` line (:34):

```sh
printf '%s %s %s\n' "${BASH_DEFAULT_TIMEOUT_MS:-unset}" "${BASH_MAX_TIMEOUT_MS:-unset}" "${STUDIO_GATE_MINUTES:-unset}" > "$CALLS/$n.caps"
```

The lanes stub already records `env > "$CALLS/$n.fullenv"` (`overnight_lanes_test.sh:174`), so it needs no change.

- [ ] **Step 2: Failing tests.** `tests/overnight_test.sh`, added to `run_tests`:

```sh
# #59 AC1: single-plan units get the command caps; the default is 90.
test_overnight_unit_caps() {
  fixture caps180 '{ "overnight": { "session_minutes": 180 } }'
  scenario "cost 1" "cost 1"
  run_start
  assert_eq "2700000 10800000 60" "$(cat "$CALLS/1.caps")" "180: command cap 45 min, ceiling 180 min, gate cap 60"
  assert_eq "2700000 10800000 60" "$(cat "$CALLS/2.caps")" "the retry too"
  fixture caps90
  scenario "cost 1" "cost 1"
  run_start
  assert_eq "1800000 5400000 45" "$(cat "$CALLS/1.caps")" "90 (default): 30 / 90 / 45"
  run_start --dry-run
  assert_contains "$RS_OUT" "BASH_DEFAULT_TIMEOUT_MS='1800000' BASH_MAX_TIMEOUT_MS='5400000' STUDIO_GATE_MINUTES='45' OMEGA_AUTOPILOT=1 claude-gd -p '/game-dev:execute --one'" "the dry-run line carries the caps before OMEGA_AUTOPILOT"
}
```

Extend `test_overnight_help`'s `for w in` list with `"STUDIO_GATE_MINUTES" "min(45, session_minutes/3)" "min(60, session_minutes/2)"`.

`tests/overnight_lanes_test.sh`, added to `run_tests` near `test_lanes_gate_room_warning`:

```sh
# #59 AC1: every lane unit and the final unit get the caps.
test_lanes_unit_caps() {
  for _uc in 180:2700000:10800000:60 90:1800000:5400000:45; do
    _m="${_uc%%:*}"; _r="${_uc#*:}"; _d="${_r%%:*}"; _r="${_r#*:}"; _x="${_r%%:*}"; _g="${_r#*:}"
    LANES_PROGRESS=1; LANES_CONFIG="{\"overnight\": {\"session_minutes\": $_m}}"; export LANES_PROGRESS LANES_CONFIG
    lanes_fixture "caps$_m" integration A:-
    printf 'progress\n' > "$SCEN/progress"
    run_lanes start "$MFP"
    _n=0
    for _f in "$CALLS"/*.fullenv; do
      _n=$((_n + 1))
      assert_contains "$_f" "^BASH_DEFAULT_TIMEOUT_MS=$_d\$" "$_m: $(basename "$_f") command cap"
      assert_contains "$_f" "^BASH_MAX_TIMEOUT_MS=$_x\$" "$_m: $(basename "$_f") ceiling"
      assert_contains "$_f" "^STUDIO_GATE_MINUTES=$_g\$" "$_m: $(basename "$_f") gate cap"
    done
    assert_eq 1 "$([ "$_n" -ge 2 ] && echo 1 || echo 0)" "$_m: a story unit and the final unit were launched"
  done
}
# #59 D2: the runner's own merge and final gate never run under a gate cap,
# even when the operator's shell exports one.
test_lanes_runner_gates_uncapped() {
  LANES_PROGRESS=1; export LANES_PROGRESS
  lanes_fixture uncap integration A:-
  printf 'progress\n' > "$SCEN/progress"
  use_gate "env | grep '^STUDIO_GATE_MINUTES=' >> '$CALLS/gate-env'; echo gate >> '$CALLS/final-gates'"
  STUDIO_GATE_MINUTES=1; export STUDIO_GATE_MINUTES
  run_lanes start "$MFP"; unset STUDIO_GATE_MINUTES; use_gate true
  assert_eq 1 "$(final_gates)" "the final gate ran"
  assert_eq "" "$(cat "$CALLS/gate-env" 2>/dev/null)" "with no STUDIO_GATE_MINUTES"
}
# #59 D9: the gate run cap warning (max × 1.2 against GATE_MIN).
test_lanes_gate_cap_warning() {
  lanes_fixture gcw integration A:-
  printf '1 studio-test 3000 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "a warning, not a refusal"
  assert_contains "$LS_ERR" "warning: gate run cap: .*took 50 min.*gate run cap of 45 min.*set overnight.session_minutes to at least 120" "50 min × 1.2 = 60 > 45: raise session_minutes to 2 × 60"
  printf '1 gate 4000 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_contains "$LS_ERR" "warning: gate run cap: .*tops out at 60 min" "a run that needs more than 60 min names the ceiling"
  printf '1 studio-test-file 9000 0\n2 studio-test 600 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_not_contains "$LS_ERR" "warning: gate run cap" "file runs are not read; a 10-minute suite fits 45"
}
```

`use_gate`, `final_gates`, `LANES_PROGRESS` and `$SCEN/progress` are the existing fixture knobs used by `test_lanes_final_step_once` (:1726). Reset `LANES_PROGRESS`/`LANES_CONFIG` the way neighbouring tests do (`unset` after the run, if the suite does not reset them in `lanes_fixture`; check :529-545).

- [ ] **Step 3: Run; they fail.**
  - `TESTS_ONLY="test_overnight_unit_caps test_overnight_help" sh tests/overnight_test.sh`. It fails because `.caps` says `unset unset unset` and the help list is missing.
  - Then, not concurrently, `TESTS_ONLY="test_lanes_unit_caps test_lanes_runner_gates_uncapped test_lanes_gate_cap_warning" sh tests/overnight_lanes_test.sh`. It fails on `BASH_DEFAULT_TIMEOUT_MS=10800000`, no `STUDIO_GATE_MINUTES`, and no warning. `uncapped` passes already: it guards D2.

- [ ] **Step 4: Implement.**
  - At the top of `studio-overnight`, after `LAUNCH_ENV=""; UNIT_CWD=""; LDIR=""` (:27):

```sh
# #59 D2: the runner's own gates (merge, final gate) are never capped; a
# session gets STUDIO_GATE_MINUTES only through its launch words.
unset STUDIO_GATE_MINUTES
```

  - Above `gate_room_check`:

```sh
# session_caps — #59 R1: the command caps of every runner-launched session,
# from SESSION_MINUTES (default 90): CMD_MIN = min(45, S/3) and GATE_MIN =
# min(60, S/2) (integer minutes), CMD_MS = CMD_MIN × 60000 (Bash calls with no
# timeout), MAX_MS = S × 60000 (the ceiling gate-routed calls request).
session_caps() {
  _sc_s="${SESSION_MINUTES:-90}"
  CMD_MIN=$((_sc_s / 3)); [ "$CMD_MIN" -le 45 ] || CMD_MIN=45
  GATE_MIN=$((_sc_s / 2)); [ "$GATE_MIN" -le 60 ] || GATE_MIN=60
  CMD_MS=$((CMD_MIN * 60000)); MAX_MS=$((_sc_s * 60000))
}
# caps_env — the caps as launch env words, each KEY='value' (sq).
caps_env() {
  session_caps
  printf 'BASH_DEFAULT_TIMEOUT_MS=%s BASH_MAX_TIMEOUT_MS=%s STUDIO_GATE_MINUTES=%s' \
    "$(sq "$CMD_MS")" "$(sq "$MAX_MS")" "$(sq "$GATE_MIN")"
}
```

  - Preflight, right after `cfg session_minutes 90 10 480 int` (D3): `SESSION_MINUTES="$(printf '%s\n' "$SESSION_MINUTES" | awk '{ print $1 + 0 }')"`.
  - `gate_room_check`: after `_gr_g` is computed and **before** the `[ "$_gr_s" -gt 0 ] … || return 0` early return (D9):

```sh
  # #59 R1: studio-gate stops a run past GATE_MIN (exit 124): warn when the
  # slowest recent studio-test or gate run × 1.2 does not fit it.
  session_caps
  _gr_m=$(( ${_gr_t:-0} > ${_gr_g:-0} ? ${_gr_t:-0} : ${_gr_g:-0} ))
  if [ "$_gr_m" -gt 0 ] && [ $((_gr_m * 12)) -gt $((GATE_MIN * 600)) ]; then
    _gr_cn=$(( (_gr_m * 12 / 10 + 59) / 60 ))
    if [ "$_gr_cn" -le 60 ]; then _gr_fix="set overnight.session_minutes to at least $((_gr_cn * 2)) in .studio/config.json"
    else _gr_fix="the cap tops out at 60 min (session_minutes 120 or more): speed up or split the suite"; fi
    say "warning: gate run cap: the slowest recent studio-test or gate run took $(( (_gr_m + 59) / 60 )) min; × 1.2 is past the gate run cap of $GATE_MIN min (min(60, session_minutes/2)) — $_gr_fix (studio-gate stops a run past the cap, exit 124)"
  fi
```

  - `print_launch` and `start_session`: replace `${LAUNCH_ENV:-OMEGA_AUTOPILOT=1}` with `${LAUNCH_ENV:-$(caps_env) OMEGA_AUTOPILOT=1}` (D1). Update `print_launch`'s comment.
  - `overnight-lanes.sh`:
    - `story_launch_env`: drop `_ms` and print `… STUDIO_DOCS_REV=%s %s` with `"$(caps_env)"` in place of the two `BASH_*` words. Update its comment: the caps come from `caps_env`, see `studio-overnight`.
    - `run_story` :1104 becomes `session_caps; BASH_DEFAULT_TIMEOUT_MS="$CMD_MS"; BASH_MAX_TIMEOUT_MS="$MAX_MS"`. The export line is unchanged, with no `STUDIO_GATE_MINUTES` (D2).
    - `final_unit` :1673-1674: drop `_fu_ms` and use `… STUDIO_DOCS_REV=$(sq "$MF_DOCS") $(caps_env)${3:+ $3}`.
  - Help `session_minutes` row (:394-397) becomes:

```
  session_minutes      90    10-480   wall-clock cap per session (and per merge command).
                                    It sets each session's command caps: a Bash call with
                                    no timeout gets min(45, session_minutes/3) min
                                    (BASH_DEFAULT_TIMEOUT_MS); BASH_MAX_TIMEOUT_MS is the
                                    whole session; studio-gate stops a gate run (studio-test,
                                    studio-run, studio-setup) past min(60, session_minutes/2)
                                    min (STUDIO_GATE_MINUTES, exit 124). The preflight warns
                                    when the slowest recent studio-test (.studio/gate.times)
                                    × 1.2 + 10 min exceeds the session, or × 1.2 the gate cap.
```

  - README Overnight runs bullet (:152-163): replace "with the runner's raised timeout (`session_minutes`)" with a sentence giving the three caps and their formulas. Add that the preflight also warns when a gate run would not fit the gate cap.

- [ ] **Step 5: Run; they pass.**
  - The Step 3 commands.
  - Then the neighbours: `TESTS_ONLY="test_overnight_dry_run test_overnight_timeout test_overnight_kill_after_grace" sh tests/overnight_test.sh`.
  - Then, not concurrently, `TESTS_ONLY="test_lanes_chain_rule test_lanes_gate_room_warning test_lanes_gate_times_non_integer test_lanes_final_step_once test_lanes_unit_env_run_dir test_lanes_sync_repair_stops" sh tests/overnight_lanes_test.sh`.
  - Then the whole of both suites, one after the other.

- [ ] **Step 6: Commit.** `git commit -m 'feat(overnight): per-command caps from session_minutes for every session (#59)' -- studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh tests/overnight_test.sh tests/overnight_lanes_test.sh README.md`

---

### Task A2: Idle watchdog, `open_calls`, `stalled` (R2, AC3–AC5)

Review: task (Opus). Wave 2. Lane A, after A1.

**Files:**
- Modify `studios/game-dev/bin/studio-overnight`:
  - preflight (after `cfg kill_grace_seconds`, :587-588);
  - a new `open_calls` after `unit_activity` (:945);
  - `run_unit` (:1134-1185);
  - `unit_outcome` (:1197-1201);
  - a new `stall_note` beside `orphan_note` (:1204);
  - `story_units` ending (:1343-1344) and its header comment (:1308);
  - `holdable` (:817);
  - the `activity)` dispatch (:1995-1997);
  - help: a config row after `session_minutes`, and two test hooks in the list at :444-474.
- Modify `studios/game-dev/bin/overnight-lanes.sh`: the endings at :685-686 (land repair), :732-733 (gate repair) and :833-834 (sync repair), and their comments at :712 and :807.
- Create `tests/fixtures/overnight-open-calls.jsonl`.
- Modify `tests/overnight_test.sh`: the stub (`emit`, `gatereg`), 5 tests, the help list, the events loop (:262), and `run_tests`.
- Modify `tests/overnight_lanes_test.sh`: a new `test_lanes_stalled_outcome`, a `stall` case in `test_lanes_sync_repair_stops` (:1665), and `run_tests`.
- Modify `docs/game-dev/overnight-events.md`: a `unit_stalled` row, and `stalled` in the `unit_ended` row (:102).
- Modify `README.md`: the Overnight runs bullet. Say that a unit silent for `idle_minutes` outside a gate is recorded `stalled`.

**Interfaces:**
- **Consumes:** A1's `session_caps`; `cfg`, `refuse`, `run_event`, `row`, `GRACE`, `STATE_ROOT`, `UNIT_TAG`, `UNIT_DIR`, `UNIT_STEM` and `CPID`.
- **Produces:**
  - `IDLE_MINUTES` (set by `cfg idle_minutes 20 0 120 int`, normalized per D3).
  - `open_calls JSONL [gate]`. List mode prints the open calls newest first, rendered and cut to 120 characters. Gate mode prints `gate` when an open Bash call's full command matches `studio-(test|run|setup|gate)`, else nothing. It always exits 0.
  - Globals after `run_unit`: `UNIT_STALLED` (0/1), `UNIT_STALL_MIN`, `UNIT_STALL_CMD`.
  - `unit_outcome` → `stalled`.
  - `stall_note` → ` (no output for <N> min: <command>)`, with a leading space.
  - Event `unit_stalled story unit label idle_min:=<n> command=<text>`.
  - Verb `studio-overnight activity --open <jsonl>`, which prints `open_calls` list mode.
  - Endings:
    - `stalled on <base> (no output for <N> min: <cmd>)`
    - `stopped repair stalled (…)`
    - `gate repair stalled (…)`
    - `sync repair: stalled (…)`

Anchors:
- `grep -n 'cfg kill_grace_seconds\|^unit_activity()\|^run_unit()\|^unit_outcome()\|^orphan_note()\|timed out on \$_base\|"gate repair timed out"\*\|^  activity)' studios/game-dev/bin/studio-overnight`
- `grep -n 'timed out (session_minutes' studios/game-dev/bin/overnight-lanes.sh`
- `grep -n '"sleep "\*)\|^    hang)\|for e in run_started' tests/overnight_test.sh`

- [ ] **Step 1: Stub actions and fixture.**
  - In `tests/overnight_test.sh`'s stub `case`, beside `"sleep "*)`, add:

```sh
    # emit FILE: stream-json lines on stdout, i.e. into the unit's log (#59).
    "emit "*)     cat "${act#emit }" ;;
    # gatereg: register a gate under this unit's tag, as studio-gate does.
    gatereg)      mkdir -p "$root/.studio/gate.units/$STUDIO_UNIT_TAG" && : > "$root/.studio/gate.units/$STUDIO_UNIT_TAG/$$" ;;
```

  - The fixture `tests/fixtures/overnight-open-calls.jsonl` has five lines:
    - an init line;
    - an open `Agent` call `toolu_A` (`subagent_type` `game-dev:gameplay-programmer`, `description` `T7 implement`);
    - inside it (`"parent_tool_use_id":"toolu_A"`), a Bash call `toolu_B1` `ls`;
    - the result for `toolu_B1` (`"tool_use_id":"toolu_B1"`);
    - an open Bash call `toolu_B2`, whose command is `cd /Users/dev/GameDev/proj/phoenix/.claude/worktrees/kan-1540-greater-slime-av-integration-lane-1-story-s1-retry-two && studio-test --file tests/unit/test_vfx_span_player_creature.gd`. Here `studio-test` starts after character 120. Guard this in the test.

    Use the exact shape `{"type":"assistant","parent_tool_use_id":"toolu_A","message":{"content":[{"type":"tool_use","id":"toolu_B2","name":"Bash","input":{"command":"…"}}]}}`. `unit_activity` matches `"type":"tool_use","id":"…","name":"…"` in that order.

- [ ] **Step 2: Failing tests** in `tests/overnight_test.sh` (and `run_tests`):

```sh
# #59 R2: open (unanswered) calls, newest first; gate mode reads the full command.
test_overnight_open_calls() {
  F="$REPO_ROOT/tests/fixtures/overnight-open-calls.jsonl"
  assert_eq 1 "$(awk '/toolu_B2/ { print (index($0, "studio-test") > 160) }' "$F")" "fixture: studio-test sits past the 120-char cut"
  sh "$RUNNER" activity --open "$F" > "$TMP/oc.out"
  assert_eq 2 "$(grep -c . "$TMP/oc.out")" "two open calls: B1 was answered"
  assert_contains "$TMP/oc.out" '^Bash: cd /Users/dev/GameDev/proj/phoenix/' "newest first: the subagent's hung Bash"
  assert_eq 120 "$(head -n 1 "$TMP/oc.out" | awk '{ print length($0) <= 122 ? 120 : length($0) }')" "cut to 120 characters (… counted as one)"
  assert_eq 'gameplay-programmer · "T7 implement"' "$(sed -n 2p "$TMP/oc.out")" "then the Agent call, rendered as unit_activity does"
  printf '%s\n' '{"type":"system","subtype":"init"}' > "$TMP/oc0.jsonl"
  assert_eq "" "$(sh "$RUNNER" activity --open "$TMP/oc0.jsonl")" "no tool call: nothing"
}
```

The cut is `cut(s, 120)` = 119 bytes + `…`. Its byte length depends on awk's locale, so the test only bounds it. The implementer may tighten this to `assert_contains … '…$'`.

Gate mode is tested through the watchdog (AC4) and through `open_calls` directly. The suite runs the runner as a command, so add a hidden test hook verb `activity --open-gate <jsonl>` that prints `open_calls F gate`; or test it only through AC4. Pick one and note it in the commit body.

```sh
# stall_log FILE CMD — a session log: init, then one open Bash call running CMD.
stall_log() {
  printf '%s\n' '{"type":"system","subtype":"init"}' \
    "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"Bash\",\"input\":{\"command\":\"$2\"}}]}}" > "$1"
}
idle_on() {   # idle_on IDLE POLL [SESSION] — seconds seams for the next run
  STUDIO_OVERNIGHT_IDLE_SECONDS="$1"; STUDIO_OVERNIGHT_IDLE_POLL_SECONDS="$2"; STUDIO_OVERNIGHT_SESSION_SECONDS="${3:-30}"
  export STUDIO_OVERNIGHT_IDLE_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS STUDIO_OVERNIGHT_SESSION_SECONDS
}
idle_off() { unset STUDIO_OVERNIGHT_IDLE_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS STUDIO_OVERNIGHT_SESSION_SECONDS; }

# AC3: a silent session with an open plain command ends as stalled, long before the cap.
test_overnight_idle_stall() {
  fixture stall '{ "overnight": { "retries": 0 } }'
  stall_log "$TMP/stall.jsonl" "sleep 999"
  scenario "emit $TMP/stall.jsonl; hang"
  idle_on 2 1 30; _t0=$(date +%s); run_start; idle_off
  R="$(last_run_dir)"
  assert_eq 1 "$([ $(( $(date +%s) - _t0 )) -lt 20 ] && echo 1 || echo 0)" "ended by the idle watchdog, well before the 30 s cap"
  assert_eq "stalled" "$(awk -F'\t' 'NR == 1 { print $7 }' "$R/units.tsv")" "outcome stalled"
  assert_eq 0 "$(awk -F'\t' 'NR == 1 { print $6 }' "$R/units.tsv")" "timed_out stays the session-cap flag"
  assert_contains "$R/events.jsonl" '"event":"unit_stalled",.*"idle_min":20,"command":"Bash: sleep 999"' "unit_stalled names the open command"
  assert_contains "$R/report.md" '^Ending: stalled on T1 (no output for 20 min: Bash: sleep 999)$' "the ending"
}
# AC4 + Review Focus 1: an open gate-routed call (past the cut) or a registered gate is never stalled.
test_overnight_idle_spares_gate_call() {
  _long="cd /Users/dev/GameDev/proj/phoenix/.claude/worktrees/kan-1540-greater-slime-av-integration-lane-1-story-s1-retry-two && studio-test --file tests/unit/test_x.gd"
  fixture spare '{ "overnight": { "retries": 0 } }'
  stall_log "$TMP/gate.jsonl" "$_long"
  scenario "emit $TMP/gate.jsonl; hang"
  idle_on 1 1 6; run_start; idle_off
  R="$(last_run_dir)"
  assert_eq "timed out" "$(awk -F'\t' 'NR == 1 { print $7 }' "$R/units.tsv")" "the session cap ends it, not the idle watchdog"
  assert_not_contains "$R/events.jsonl" '"unit_stalled"' "no stall"
  fixture spare2 '{ "overnight": { "retries": 0 } }'
  stall_log "$TMP/plain.jsonl" "sleep 999"
  scenario "emit $TMP/plain.jsonl; gatereg; hang"
  idle_on 1 1 6; run_start; idle_off
  assert_eq "timed out" "$(awk -F'\t' 'NR == 1 { print $7 }' "$(last_run_dir)/units.tsv")" "a gate registered under the unit's tag exempts it"
}
# AC5: 0 turns it off; bad values are refused.
test_overnight_idle_off_and_refusals() {
  fixture idleoff '{ "overnight": { "retries": 0, "idle_minutes": 0 } }'
  stall_log "$TMP/off.jsonl" "sleep 999"
  scenario "emit $TMP/off.jsonl; hang"
  idle_on 1 1 5; run_start; idle_off
  assert_eq "timed out" "$(awk -F'\t' 'NR == 1 { print $7 }' "$(last_run_dir)/units.tsv")" "idle_minutes 0: the watchdog is off even with the seconds seam set"
  fixture idlebad '{ "overnight": { "idle_minutes": 121 } }'
  refuse_case "idle_minutes 121" "config overnight.idle_minutes must be from 0 to 120, got 121"
  fixture idleseam; STUDIO_OVERNIGHT_IDLE_SECONDS=abc; export STUDIO_OVERNIGHT_IDLE_SECONDS
  refuse_case "bad idle seam" "STUDIO_OVERNIGHT_IDLE_SECONDS must be a whole number"; unset STUDIO_OVERNIGHT_IDLE_SECONDS
  fixture pollseam; STUDIO_OVERNIGHT_IDLE_POLL_SECONDS=0; export STUDIO_OVERNIGHT_IDLE_POLL_SECONDS
  refuse_case "zero poll seam" "STUDIO_OVERNIGHT_IDLE_POLL_SECONDS must be a whole number"; unset STUDIO_OVERNIGHT_IDLE_POLL_SECONDS
}
# Review Focus 2: a stalled command containing " until " holds, shows and ends intact.
test_overnight_stall_holds_with_until_command() {
  fixture sthold; holds_on 3
  stall_log "$TMP/until.jsonl" "until false; do sleep 1; done"
  scenario "$ISO1" "emit $TMP/until.jsonl; hang" "emit $TMP/until.jsonl; hang"
  idle_on 2 1 30; start_bg; wait_held 30; idle_off
  assert_contains "$R/control/-.held" '^held stalled on T2 (no output for 20 min: Bash: until false; do sleep 1; done) until 20[0-9-]*T[0-9:]*Z$' "the held record keeps the command"
  verb status
  assert_contains "$V_OUT" '^held — stalled on T2 (no output for 20 min: Bash: until false; do sleep 1; done) — until [0-9][0-9]:[0-9][0-9] — say / resume / stop -$' "held_line splits on the last ' until '"
  assert_contains "$R/events.jsonl" '"state":"held","why":"stalled on T2 (no output for 20 min: Bash: until false; do sleep 1; done)","until":"20' "story_state too"
  bg_end 30 "the hold deadline ends the run"
  assert_contains "$R/report.md" '^Ending: stalled on T2 (no output for 20 min: Bash: until false; do sleep 1; done) (held 0h0m, no reply)$' "the report keeps it"
  holds_off
}
```

  - `bg_end`, `verb`, `V_OUT`, `wait_held`, `start_bg` and `ISO1` are existing helpers (:636-660, :1558-1570). Check `bg_end`'s signature at its definition. The scenario's stage and branch come from `ISO1`. The `;` inside the command lives in the emitted file, never in the scenario line, which the stub splits on `;`.
  - Help list: add `"idle_minutes .*0-120" "STUDIO_OVERNIGHT_IDLE_SECONDS — test hook" "STUDIO_OVERNIGHT_IDLE_POLL_SECONDS — test hook"`. Events loop (:262): add `unit_stalled`.

`tests/overnight_lanes_test.sh`:

```sh
test_lanes_stalled_outcome() {
  LANES_CONFIG='{"overnight": {"kill_grace_seconds": 5}}'; export LANES_CONFIG
  lanes_fixture stl integration A:-
  printf '%s\n' '{"type":"system","subtype":"init"}' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"sleep 999"}}]}}' > "$TMP/stl.jsonl"
  printf 'emit %s; hang\nemit %s; hang\n' "$TMP/stl.jsonl" "$TMP/stl.jsonl" > "$SCEN/A"
  STUDIO_OVERNIGHT_IDLE_SECONDS=2 STUDIO_OVERNIGHT_IDLE_POLL_SECONDS=1 STUDIO_OVERNIGHT_SESSION_SECONDS=60
  export STUDIO_OVERNIGHT_IDLE_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS STUDIO_OVERNIGHT_SESSION_SECONDS
  run_lanes start "$MFP"; unset STUDIO_OVERNIGHT_IDLE_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS STUDIO_OVERNIGHT_SESSION_SECONDS
  R="$(last_lanes_dir)"
  assert_eq "stalled|stalled" "$(cut -f7 "$R/lanes/1/units.tsv" | paste -sd'|' -)" "both units stalled"
  assert_eq "0|0" "$(cut -f6 "$R/lanes/1/units.tsv" | paste -sd'|' -)" "not session-capped"
  assert_contains "$R/stories/A" '^stopped stalled on T1 (no output for 20 min: Bash: sleep 999)$' "the ending"
  assert_eq 2 "$(grep -c '"event":"unit_stalled"' "$R/events.jsonl")" "one unit_stalled per unit"
}
```

In `test_lanes_sync_repair_stops` (:1665), add `stall` to `for _sr in stop noop hang`. Its case is `printf 'emit %s; hang\n' "$TMP/stl2.jsonl" > "$SCEN/A.sync"`, with the same two-line log written first and `_want="stalled (no output for 20 min: Bash: sleep 999)"`. Export the idle seams (2/1) and `STUDIO_OVERNIGHT_SESSION_SECONDS=60` for that case only, and unset them after `run_lanes`.

- [ ] **Step 3: Run; they fail.**
  - `TESTS_ONLY="test_overnight_open_calls test_overnight_idle_stall test_overnight_idle_spares_gate_call test_overnight_idle_off_and_refusals test_overnight_stall_holds_with_until_command test_overnight_help test_events_contract_doc" sh tests/overnight_test.sh`.
    - `activity --open` is a usage error, so open_calls fails.
    - The stall tests run to the 30 s cap, giving `timed out`.
    - The seams and `idle_minutes` are accepted, so the refusals fail.
    - Help and events: missing rows.
  - Then, not concurrently, `TESTS_ONLY="test_lanes_stalled_outcome test_lanes_sync_repair_stops" sh tests/overnight_lanes_test.sh`.

- [ ] **Step 4: Implement.**
  - **Preflight**, after `GRACE=` (:588):

```sh
  cfg idle_minutes 20 0 120 int
  IDLE_MINUTES="$(printf '%s\n' "$IDLE_MINUTES" | awk '{ print $1 + 0 }')"   # D3
  for _pf_v in STUDIO_OVERNIGHT_IDLE_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS; do
    eval "_pf_x=\${$_pf_v:-1}"
    case "$_pf_x" in ''|*[!0-9]*) refuse "$_pf_v must be a whole number of seconds (1 or more), got $_pf_x" ;;
      *) [ "$_pf_x" -ge 1 ] || refuse "$_pf_v must be a whole number of seconds (1 or more), got $_pf_x" ;; esac
  done
```

  - **`open_calls`**, after `unit_activity`. It reuses `unit_activity`'s `val`, `cut` and `closed[]` logic verbatim:

```sh
# open_calls JSONL [gate] — #59 R2: the session's open (unanswered) tool_use
# calls, newest first, one per line, rendered as unit_activity renders a tool
# (Agent/Task: `<type> · "<description>"`; Bash: `Bash: <command>`; a file
# tool: its file name; Grep/Glob: the pattern; else the tool name), newlines
# and tabs flattened, cut to 120 chars. `gate`: prints `gate` when an open
# Bash call's FULL command runs a gate-routed verb (never the cut text).
open_calls() {
  [ -s "$1" ] || return 0
  awk -v mode="${2:-list}" '
    function val(s, k,   re, v) {
      re = "\"" k "\":\"([^\"\\\\]|\\\\.)*\""
      if (!match(s, re)) return ""
      v = substr(s, RSTART + length(k) + 4, RLENGTH - length(k) - 5)
      gsub(/\\n/, " ", v); gsub(/\\t/, " ", v); gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v)
      return v
    }
    function cut(s, n) { return length(s) > n ? substr(s, 1, n - 1) "…" : s }
    {
      l = $0
      while (match(l, /"tool_use_id":"[^"]*"/)) { closed[substr(l, RSTART + 15, RLENGTH - 16)] = 1; l = substr(l, RSTART + RLENGTH) }
      l = $0
      while (match(l, /"type":"tool_use","id":"[^"]*","name":"[^"]*"/)) {
        head = substr(l, RSTART, RLENGTH); l = substr(l, RSTART + RLENGTH)
        id = head; sub(/^"type":"tool_use","id":"/, "", id); sub(/".*/, "", id)
        nm = head; sub(/.*"name":"/, "", nm); sub(/"$/, "", nm)
        inp = l; if (match(inp, /"type":"tool_use"/)) inp = substr(inp, 1, RSTART - 1)
        full = ""
        if (nm == "Agent" || nm == "Task") {
          t = val(inp, "subagent_type"); sub(/^.*:/, "", t); if (t == "") t = "agent"
          txt = t " · \"" val(inp, "description") "\""
        } else {
          if (nm == "Bash") { d = val(inp, "command"); full = d }
          else if (nm ~ /^(Read|Edit|Write|NotebookEdit)$/) { d = val(inp, "file_path"); sub(/.*\//, "", d) }
          else if (nm ~ /^(Grep|Glob)$/) d = val(inp, "pattern")
          else d = ""
          txt = (d == "") ? nm : nm ": " d
        }
        n++; cid[n] = id; ctxt[n] = txt; cfull[n] = full
      }
    }
    END {
      for (i = n; i >= 1; i--) {
        if (cid[i] in closed) continue
        if (mode == "gate") { if (cfull[i] ~ /studio-(test|run|setup|gate)/) { print "gate"; exit } ; continue }
        s = ctxt[i]; gsub(/[\t\r\n]/, " ", s); print cut(s, 120)
      }
    }' "$1" 2>/dev/null
  return 0
}
```

  - **`run_unit`**: replace the lines from `_secs=` (:1147) through `WPID=$!` (:1164) with the following. Keep the existing comment block, extended with the idle rule.

```sh
  _secs="${STUDIO_OVERNIGHT_SESSION_SECONDS:-$((SESSION_MINUTES * 60))}"
  _idle=""; [ "${IDLE_MINUTES:-0}" -eq 0 ] || _idle="${STUDIO_OVERNIGHT_IDLE_SECONDS:-$((IDLE_MINUTES * 60))}"
  _poll="${STUDIO_OVERNIGHT_IDLE_POLL_SECONDS:-30}"
  _log="$UNIT_DIR/$UNIT_STEM.jsonl"; _greg="$STATE_ROOT/.studio/gate.units/$UNIT_TAG"
  _claim="$UNIT_DIR/$UNIT_STEM.ended"; rm -rf "$_claim" "$_claim.stall"
  # Idle (#59 R2): every _poll s the watchdog compares the log's size; once
  # it has not grown for _idle s, and the unit has no registered gate and no
  # open gate-routed Bash call, it stages `.ended.stall`, takes the claim and
  # moves the marker inside it (D5), then ends the session as the cap does.
  ( _sp=; _why=; trap 'kill $_sp 2>/dev/null; exit 0' TERM
    _end=$(( $(date +%s) + _secs )); _sz=""; _quiet=$(date +%s)
    while :; do
      _left=$(( _end - $(date +%s) )); [ "$_left" -gt 0 ] || break
      _nap="$_left"; [ -z "$_idle" ] || [ "$_nap" -le "$_poll" ] || _nap="$_poll"
      sleep "$_nap" & _sp=$!; wait "$_sp"
      [ -n "$_idle" ] || continue
      _s="$(wc -c < "$_log" 2>/dev/null | tr -d ' ')"; _now=$(date +%s)
      if [ "${_s:-0}" != "$_sz" ]; then _sz="${_s:-0}"; _quiet="$_now"; continue; fi
      [ $((_now - _quiet)) -ge "$_idle" ] || continue
      [ -z "$(ls -A "$_greg" 2>/dev/null)" ] || continue
      [ -z "$(open_calls "$_log" gate)" ] || continue
      _oc="$(open_calls "$_log" | head -n 1)"
      printf 'idle_min=%s\ncommand=%s\n' "$IDLE_MINUTES" "${_oc:--}" > "$_claim.stall"
      if mkdir "$_claim" 2>/dev/null; then mv -f "$_claim.stall" "$_claim/stalled"
      else rm -f "$_claim.stall"; [ ! -d "$_claim" ] || exit 0; fi
      _why=stall; break
    done
    # Lost only to the runner's claim (the dir exists); a mkdir failing for
    # any other reason (run dir gone, disk full) still ends a hung session.
    [ "$_why" = stall ] || mkdir "$_claim" 2>/dev/null || [ ! -d "$_claim" ] || exit 0
    kill -TERM -"$CPID" 2>/dev/null || { pkill -TERM -P "$CPID"; kill -TERM "$CPID"; }
    sleep "$GRACE" & _sp=$!; wait "$_sp"
    kill -KILL -"$CPID" 2>/dev/null || { pkill -KILL -P "$CPID"; kill -KILL "$CPID"; }
  ) > /dev/null 2>&1 &
  WPID=$!
```

    Then replace :1175-1179, from `UNIT_EXIT="$_st"; UNIT_TIMED_OUT=0` to `rmdir "$_claim"`:

```sh
  UNIT_EXIT="$_st"; UNIT_TIMED_OUT=0; UNIT_STALLED=0; UNIT_STALL_MIN=""; UNIT_STALL_CMD=""
  _won=1; mkdir "$_claim" 2>/dev/null || _won=0
  kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
  WPID=""; [ -z "${LDIR:-}" ] || rm -f "$LDIR/wpid"   # reaped: never signal a pid number since reused
  if [ "$_won" = 0 ]; then
    # The watchdog won: a stall when its marker is in (or staged beside) the claim, else the cap.
    _sf="$_claim/stalled"; [ -f "$_sf" ] || _sf="$_claim.stall"
    if [ -f "$_sf" ]; then
      UNIT_STALLED=1
      UNIT_STALL_MIN="$(sed -n 's/^idle_min=//p' "$_sf" | head -n 1)"
      UNIT_STALL_CMD="$(sed -n 's/^command=//p' "$_sf" | head -n 1)"
    else UNIT_TIMED_OUT=1; fi
  fi
  rm -rf "$_claim" "$_claim.stall"
  [ "$UNIT_STALLED" = 0 ] || run_event unit_stalled "story=${CUR_ID:--}" "unit=$UNIT_TAG" "label=$2" "idle_min:=${UNIT_STALL_MIN:-0}" "command=${UNIT_STALL_CMD:--}"
```

  - **`unit_outcome`**: add `elif [ "${UNIT_STALLED:-0}" = 1 ]; then echo stalled` after the timed-out branch, and update the comment.
  - **`stall_note`**, beside `orphan_note`: `stall_note() { printf ' (no output for %s min: %s)' "${UNIT_STALL_MIN:-$IDLE_MINUTES}" "${UNIT_STALL_CMD:--}"; }`
  - **`story_units`**: before the final `else`, add `elif [ "$_out" = stalled ]; then ENDING="stalled on $_base$(stall_note)"`, and add the form to the header comment (:1308).
  - **`holdable`** (:817): add `|"stalled on "*|"gate repair stalled"*` to the isolated-only list.
  - **The three lanes repairs**: turn each two-way `if … != "timed out"` into a three-way `case`. For example, sync becomes:

```sh
  case "$_sr_o" in
    "timed out") row "$n" sync-repair "timed out"; ENDING="sync repair: timed out (session_minutes $SESSION_MINUTES)" ;;
    stalled) row "$n" sync-repair stalled; ENDING="sync repair: stalled$(stall_note)" ;;
    *) row "$n" sync-repair "$_sr_o"; ENDING="sync repair: no progress$(orphan_note "$_sr_o")" ;;
  esac
```

    The land repair becomes `story_write "$1" "stopped repair stalled$(stall_note)"`. The gate repair becomes `ENDING="gate repair stalled$(stall_note)"`. Update the two comments.
  - **`activity)` dispatch**:

```sh
  activity)
    if [ "${2:-}" = --open ]; then [ "$#" -eq 3 ] && [ -f "$3" ] || { usage >&2; exit 2; }; open_calls "$3"; exit 0; fi
    [ "$#" -eq 2 ] && [ -f "$2" ] || { usage >&2; exit 2; }
    unit_activity "$2"; exit 0 ;;
```

  - **Help.** Add a config row after `session_minutes`:

```
  idle_minutes         20    0-120    end a unit whose session log has not grown for this
                                    long (outcome stalled), unless it waits on or runs a
                                    gate (studio-test, studio-run, studio-setup, studio-gate);
                                    0 = off
```

    Add two test hooks in the list:

```
  STUDIO_OVERNIGHT_IDLE_SECONDS — test hook: whole seconds that replace
                     idle_minutes × 60 (idle_minutes 0 still turns the check off)
  STUDIO_OVERNIGHT_IDLE_POLL_SECONDS — test hook: whole seconds between idle
                     checks (default 30)
```

  - **Events doc.**
    - In the `unit_ended` row, add `stalled` to the outcomes.
    - New row after it: `` | `unit_stalled` | `story`, `unit`, `label`, `idle_min`, `command` | `idle_min` is a number (overnight.idle_minutes); `command` is the newest open tool call, rendered as the status activity is and cut to 120 chars, or `-`; written just before that unit's `unit_ended` (whose outcome is `stalled`, or `progress` when the unit moved the state) | ``

- [ ] **Step 5: Run; they pass.**
  - The Step 3 commands.
  - Then the regressions: `TESTS_ONLY="test_overnight_timeout test_overnight_kill_after_grace test_overnight_orphaned_holds_after_isolation test_overnight_hold_on_feature_stop" sh tests/overnight_test.sh`.
  - Then `TESTS_ONLY="test_lanes_timed_out_outcome test_lanes_heartbeat test_lanes_activity_verb" sh tests/overnight_lanes_test.sh`.
  - Then both whole suites, one after the other. Run `test_overnight_stall_holds_with_until_command` and `test_overnight_idle_stall` three times each (timing).

- [ ] **Step 6: Commit.** `git commit -m 'feat(overnight): idle watchdog — a silent unit ends as stalled; open_calls (#59)' -- studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh tests/overnight_test.sh tests/overnight_lanes_test.sh tests/fixtures/overnight-open-calls.jsonl docs/game-dev/overnight-events.md README.md`. Add the fixture first with `git add`.

---

### Task B1: studio-gate run timer (R1 gate cap, AC2)

Review: task (Opus). Wave 1. Lane B.

**Files:**
- Modify `studios/game-dev/bin/studio-gate`:
  - the header (:21-26);
  - before the traps (:175);
  - `release` (around :112);
  - after `set +m` (:196);
  - after the wait loop (:204);
  - after the straggler block (:214).
- Modify `tests/toolkit_test.sh`: 5 tests near the gate tests (:722-870), plus `run_tests` (:872).

**Interfaces:**
- **Consumes:**
  - env `STUDIO_GATE_MINUTES` (a whole number; empty, unset or 0 means off);
  - the test seam `STUDIO_GATE_SECONDS`, which replaces `minutes × 60`, read only when the cap is on;
  - the existing `alive`, `targets`, `on_signal`, `RUNNING`, `CHILD`, `SIGSTATUS` and `WHO`.
- **Produces:**
  - exit 124;
  - stderr `gate: <who> ran past <n> min — stopped` (n = `STUDIO_GATE_MINUTES`);
  - a `gate.times` line `<epoch> <who> <s> 124`.

Anchors: `grep -n '^release()\|^on_signal()\|^trap release EXIT\|^set +m\|^  alive "\$CHILD" || break\|^RUNNING=0' studios/game-dev/bin/studio-gate`

- [ ] **Step 1: Failing tests** in `tests/toolkit_test.sh` (and `run_tests`):

```sh
# #59 AC2: STUDIO_GATE_MINUTES caps the run once the lock is held.
gate_capped() {   # gate_capped MIN SECS WHO CMD… — run the gate capped; GC_ST, GC_SECS, $TMP/gc.err
  _gc_m="$1"; _gc_s="$2"; _gc_w="$3"; shift 3
  _gc_t0=$(date +%s); GC_ST=0
  ( cd "$GP" && STUDIO_GATE_MINUTES="$_gc_m" STUDIO_GATE_SECONDS="$_gc_s" sh "$GATE" "$_gc_w" -- "$@" ) > "$TMP/gc.out" 2> "$TMP/gc.err" || GC_ST=$?
  GC_SECS=$(( $(date +%s) - _gc_t0 ))
}
test_gate_run_cap_stops_a_long_run() {
  gate_proj cap1
  gate_capped 1 1 t sleep 30
  assert_eq 124 "$GC_ST" "a run past the cap exits 124"
  assert_eq 1 "$([ "$GC_SECS" -lt 8 ] && echo 1 || echo 0)" "stopped at the cap, not after 30 s"
  assert_contains "$TMP/gc.err" '^gate: t ran past 1 min — stopped$' "names who and the minutes"
  assert_contains "$GP/.studio/gate.times" '^[0-9]* t [0-9]* 124$' "gate.times records 124"
  assert_missing "$GP/.studio/gate.lock" "the lock is released"
}
test_gate_run_cap_excludes_lock_wait() {
  gate_proj cap2
  ( cd "$GP" && sh "$GATE" holder -- sleep 4 ) 2>/dev/null &
  _h=$!; sleep 1
  gate_capped 1 3 waiter sleep 1
  wait "$_h"
  assert_eq 0 "$GC_ST" "3 s of lock wait plus a 1 s run is not past a 3 s cap"
}
test_gate_run_cap_off_unset_zero_and_setup() {
  gate_proj cap3
  ( cd "$GP" && STUDIO_GATE_SECONDS=1 sh "$GATE" t -- sleep 2 ) 2>/dev/null; assert_eq 0 "$?" "unset: no cap (the seam alone does nothing)"
  gate_capped "" 1 t sleep 2; assert_eq 0 "$GC_ST" "empty: no cap"
  gate_capped 0 1 t sleep 2; assert_eq 0 "$GC_ST" "0: no cap"
  gate_capped 1 1 setup sleep 2; assert_eq 0 "$GC_ST" "who setup is exempt"
}
# Review Focus 3: TERM ignored → KILL ~10 s after the cap; still 124.
test_gate_run_cap_kills_a_term_ignorer() {
  gate_proj cap4
  gate_capped 1 1 t sh -c 'trap "" TERM; while :; do sleep 1; done'
  assert_eq 124 "$GC_ST" "killed, still reported as the cap"
  assert_eq 1 "$([ "$GC_SECS" -ge 9 ] && [ "$GC_SECS" -lt 20 ] && echo 1 || echo 0)" "KILL after the 10 s grace ($GC_SECS s)"
  assert_missing "$GP/.studio/gate.lock" "the lock is released"
}
# Review Focus 3: a run that ends first keeps its status and returns at once.
test_gate_run_cap_no_false_stop() {
  gate_proj cap5
  _o="$(cd "$GP" && STUDIO_GATE_MINUTES=1 STUDIO_GATE_SECONDS=5 sh "$GATE" t -- sh -c 'echo hi; exit 3' 2>/dev/null)"; _st=$?
  assert_eq 3 "$_st" "the command's own status"
  assert_eq hi "$_o" "its output"
  gate_capped 1 5 t true
  assert_eq 1 "$([ "$GC_SECS" -lt 3 ] && echo 1 || echo 0)" "the timer does not hold the caller ($GC_SECS s)"
  assert_not_contains "$GP/.studio/gate.times" ' 124$' "no 124 recorded"
  assert_not_contains "$TMP/gc.err" 'ran past' "no stop message"
}
```

- [ ] **Step 2: Run; they fail.** `TESTS_ONLY="test_gate_run_cap_stops_a_long_run test_gate_run_cap_excludes_lock_wait test_gate_run_cap_off_unset_zero_and_setup test_gate_run_cap_kills_a_term_ignorer test_gate_run_cap_no_false_stop" sh tests/toolkit_test.sh`. Today there is no cap, so the `stops` and `kills` tests run for 30 s and forever. Guard while red by running with `timeout 120`.

- [ ] **Step 3: Implement.**
  - **Header**:
    - `Exit:` adds `· 124 when STUDIO_GATE_MINUTES stopped the run`.
    - Add a paragraph: the run cap (#59 R1), who `setup` is exempt, re-entry `exec`s before any timer, and the `STUDIO_GATE_SECONDS` test seam.
  - **Before the traps** (:175):

```sh
# Run cap (#59 R1): STUDIO_GATE_MINUTES (a whole number; unset/empty/0 = off;
# who `setup` exempt — worktree_setup has its own timer). The timer starts
# once the lock is held. At the cap it sends us ALRM: TERM to the targets
# (on_signal 124); 10 s later it KILLs them itself, since the wait loop below
# never ends while a TERM-ignoring child lives. STUDIO_GATE_SECONDS (tests)
# replaces minutes × 60. Re-entry exec'd above, so a nested gate adds none.
CAP_SECS=""; CAPPED=0; TIMER=""
case "${STUDIO_GATE_MINUTES:-}" in
  ''|*[!0-9]*) ;;
  *) if [ "$STUDIO_GATE_MINUTES" -gt 0 ] && [ "$WHO" != setup ]; then
       CAP_SECS="${STUDIO_GATE_SECONDS:-$((STUDIO_GATE_MINUTES * 60))}"
       case "$CAP_SECS" in ''|*[!0-9]*) CAP_SECS="" ;; esac
     fi ;;
esac
on_cap() { if [ "$RUNNING" = 1 ] && alive "$CHILD"; then CAPPED=1; on_signal 124; fi; }
[ -z "$CAP_SECS" ] || trap on_cap ALRM
```

  - **`release`**: first line `[ -z "${TIMER:-}" ] || kill "$TIMER" 2>/dev/null`.
  - **After `set +m`**:

```sh
if [ -n "$CAP_SECS" ]; then
  ( _sp=; trap 'kill $_sp 2>/dev/null; exit 0' TERM
    sleep "$CAP_SECS" & _sp=$!; wait "$_sp"
    kill -ALRM $$ 2>/dev/null || exit 0
    sleep 10 & _sp=$!; wait "$_sp"
    kill -KILL $(targets "$CHILD") 2>/dev/null
  ) > /dev/null 2>&1 &
  TIMER=$!
fi
```

  - **Right after the `while … wait "$CHILD" … done` loop**: `if [ -n "$TIMER" ]; then kill "$TIMER" 2>/dev/null; wait "$TIMER" 2>/dev/null; TIMER=""; fi`
  - **After the straggler block, before `RUNNING=0`**: `[ "$CAPPED" = 0 ] || printf 'gate: %s ran past %s min — stopped\n' "$WHO" "$STUDIO_GATE_MINUTES" >&2`. `gate.times` already writes `${SIGSTATUS:-$rc}` = 124, and the exit is `SIGSTATUS`.

  `$$` in the timer subshell is the gate shell's pid in both bash and dash. `wait` returns when a trapped signal arrives, and the loop re-checks `alive "$CHILD"`.

- [ ] **Step 4: Run; they pass.** Run the Step 2 command. Then the whole of `sh tests/toolkit_test.sh` (the gate tests at :722-870 must stay green). Run `test_gate_run_cap_kills_a_term_ignorer` under `dash` as well when available: `TESTS_ONLY=… dash tests/toolkit_test.sh`.

- [ ] **Step 5: Commit.** `git commit -m 'feat(gate): STUDIO_GATE_MINUTES stops a run past the cap, exit 124 (#59)' -- studios/game-dev/bin/studio-gate tests/toolkit_test.sh`

---

### Task B2: `studio-test --file` (R3, AC6)

Review: final (folds into the final review). Wave 2. Lane B, after B1.

**Files:**
- Modify `studios/game-dev/bin/studio-test`. The file is 9 lines, all rewritten except the last `exec` line, which must keep the literal `studio-gate" studio-test --` (`test_gate_wraps_test_and_run`, `toolkit_test.sh:855`).
- Modify `studios/game-dev/engines/godot/test.sh`: the header (:1-13) and the target block (:42-58).
- Modify `studios/game-dev/engines/godot/GUIDE.md`: the `test.sh` verb row (:24).
- Modify `README.md`: the `studio-test [PATH]` row (:95). Add `--file` and exit `4 missing test file · 124 gate cap`.
- Modify `tests/toolkit_test.sh`: 5 tests near `test_test_targets_a_file` (:229), plus `run_tests`.

**Interfaces:**
- **Produces:**
  - CLI `studio-test --file <a>[,<b>…] [--file …]`, and `--file=<list>`.
  - Exit 4 with `studio-test: no such test file <path>`, or with the usage line `usage: studio-test [PATH] | --file <test.gd>[,<test.gd>…] [--file …] | --slowest [N]`.
  - The gate `who` is `studio-test-file`.
  - The adapter contract `test.sh --file <a>,<b>` gets relative, deduped, existing paths.
- **Consumes:** `studio-gate` (B1 caps it), `studio-dispatch`, and the godot stub (`toolkit_test.sh:25-91`).

Anchors:
- `grep -n 'studio-gate" studio-test --' studios/game-dev/bin/studio-test`
- `grep -n '^target=\|^\[ -z "\$gutconfig" \] || set --' studios/game-dev/engines/godot/test.sh`
- `grep -n '^| .studio-test \[PATH\]' README.md`

- [ ] **Step 1: Failing tests** in `tests/toolkit_test.sh` (and `run_tests`):

```sh
# #59 AC6: --file runs exactly the named scripts; -gconfig only with -gdir=.
test_test_file_runs_named_files() {
  P="$(fresh_project files)"; with_gut "$P"; mkdir -p "$P/tests/unit"
  : > "$P/tests/unit/a.gd"; : > "$P/tests/unit/b.gd"
  with_gutconfig "$P" .gutconfig.json '["res://tests/unit"]'
  for _form in "--file tests/unit/a.gd,tests/unit/b.gd" "--file tests/unit/a.gd --file tests/unit/b.gd"; do
    rm -f "$P"/.studio/reports/test-*.log
    # shellcheck disable=SC2086
    verb "$P" studio-test $_form
    assert_eq 0 "$(cat "$TMP/status")" "$_form: passes"
    assert_contains "$(last_log "$P")" "-s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gdir= -gtest=res://tests/unit/a.gd,res://tests/unit/b.gd -gexit" "$_form: the probe's file form"
  done
  rm -f "$P/.gutconfig.json" "$P"/.studio/reports/test-*.log
  verb "$P" studio-test --file tests/unit/a.gd,tests/unit/b.gd
  assert_contains "$(last_log "$P")" "-gtest=res://tests/unit/a.gd,res://tests/unit/b.gd" "no config: the file list alone"
  assert_not_contains "$(last_log "$P")" "\-gconfig\|-gdir=" "no -gconfig, no -gdir="
}
test_test_file_missing_exits_4() {
  P="$(fresh_project missing)"; with_gut "$P"; mkdir -p "$P/tests/unit"; : > "$P/tests/unit/a.gd"
  verb "$P" studio-test --file tests/unit/a.gd,tests/unit/nope.gd
  assert_eq 4 "$(cat "$TMP/status")" "a missing file exits 4"
  assert_contains "$TMP/out" '^studio-test: no such test file tests/unit/nope.gd$' "names it"
  assert_eq "" "$(ls "$P"/.studio/reports/test-*.log 2>/dev/null)" "before Godot starts"
}
# Review Focus 5.
test_test_file_path_forms() {
  P="$(fresh_project forms)"; with_gut "$P"; mkdir -p "$P/tests/unit"; : > "$P/tests/unit/a.gd"; : > "$P/tests/unit/b.gd"
  verb "$P" studio-test --file "res://tests/unit/a.gd, ./tests/unit/b.gd,,$(cd "$P" && pwd -P)/tests/unit/a.gd"
  assert_eq 0 "$(cat "$TMP/status")" "res://, ./, spaces, an empty item and an absolute path inside the project are accepted"
  assert_contains "$(last_log "$P")" "-gtest=res://tests/unit/a.gd,res://tests/unit/b.gd -gexit" "normalized and deduped"
  : > "$TMP/outside.gd"
  verb "$P" studio-test --file "$TMP/outside.gd"; assert_eq 4 "$(cat "$TMP/status")" "an absolute path outside the project exits 4"
  verb "$P" studio-test --file ../forms/tests/unit/a.gd; assert_eq 4 "$(cat "$TMP/status")" "a .. path exits 4"
  verb "$P" studio-test --file tests/unit; assert_eq 4 "$(cat "$TMP/status")" "a directory is not a test file"
}
test_test_file_misuse_exits_4() {
  P="$(fresh_project misuse)"; with_gut "$P"; mkdir -p "$P/tests/unit"; : > "$P/tests/unit/a.gd"
  verb "$P" studio-test --file; assert_eq 4 "$(cat "$TMP/status")" "--file with no value"
  assert_contains "$TMP/out" '^usage: studio-test ' "prints usage"
  verb "$P" studio-test --file tests/unit/a.gd tests/unit; assert_eq 4 "$(cat "$TMP/status")" "--file mixed with a positional"
  verb "$P" studio-test --file " , "; assert_eq 4 "$(cat "$TMP/status")" "no item left"
}
test_test_file_through_gate() {
  P="$(fresh_project gated)"; with_gut "$P"; mkdir -p "$P/tests/unit" "$P/.studio"; : > "$P/tests/unit/a.gd"
  verb "$P" studio-test tests/unit/a.gd
  assert_contains "$P/.studio/gate.times" '^[0-9]* studio-test-file [0-9]* 0$' "a positional file is a file run, timed as studio-test-file"
  STUB_FAILS=1 verb "$P" studio-test --file tests/unit/a.gd
  assert_eq 1 "$(cat "$TMP/status")" "a failing test exits 1"
  assert_not_contains "$P/.studio/gate.times" ' studio-test [0-9]' "no full-suite line"
}
```

Check two things against the helpers:
- whether `STUB_FAILS=1 verb …` reaches the stub (`verb` reads `${STUB_FAILS:-0}`, `:111-114`);
- whether `fresh_project` is a git repo. Outside git, `studio-state root` falls back to `pwd -P`, so `.studio/` is enough for the gate.

Adjust the `assert_contains` patterns to `assert.sh`'s grep flavour: escape a leading `-` as the existing tests do (`"\-gtest=…"`).

- [ ] **Step 2: Run; they fail.** `TESTS_ONLY="test_test_file_runs_named_files test_test_file_missing_exits_4 test_test_file_path_forms test_test_file_misuse_exits_4 test_test_file_through_gate test_test_targets_a_file test_gate_wraps_test_and_run" sh tests/toolkit_test.sh`. Today `--file` reaches `test.sh` as a positional and becomes `-gdir=res://--file`.

- [ ] **Step 3: Implement.** The new `studio-test`, in full:

```sh
#!/bin/sh
# studio-test [PATH] — run the project's test suite through the engine adapter,
# one run at a time per project (studio-gate, who studio-test).
# studio-test --file A.gd[,B.gd…] [--file C.gd…] — only those GUT scripts
# (#59 R3), timed apart as who studio-test-file. A path is relative to the
# project root (the current directory); a leading ./ or res:// and the
# project's own absolute prefix are stripped; duplicates run once. A single
# positional that is an existing file means --file.
# studio-test --slowest [N] — the slowest files and tests of the last run's
# report; it only reads a file, so it never waits for the gate.
# Exit: the adapter's (0 pass · 1 fail · 2 no Godot · 3 no GUT) · 4 a missing
# test file or a misused --file (never 2: execute reads 2 as "no Godot") ·
# 124 the gate run cap (STUDIO_GATE_MINUTES).
case "${1:-}" in
  --slowest) shift; exec sh "$(dirname "$0")/studio-dispatch" slowest "$@" ;;
esac
ft_usage() { printf 'usage: studio-test [PATH] | --file <test.gd>[,<test.gd>…] [--file …] | --slowest [N]\n' >&2; exit 4; }
ft_missing() { printf 'studio-test: no such test file %s\n' "$1" >&2; exit 4; }
if [ "$#" -eq 1 ] && [ -f "$1" ]; then set -- --file "$1"; fi
case "${1:-}" in
  --file|--file=*)
    _ft_rp="$(pwd -P)"; _ft_rl="$PWD"; _ft_list=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --file) [ "$#" -ge 2 ] || ft_usage; _ft_v="$2"; shift 2 ;;
        --file=*) _ft_v="${1#--file=}"; shift ;;
        *) ft_usage ;;
      esac
      _ft_ifs="$IFS"; IFS=,; set -f
      for _ft_p in $_ft_v; do
        IFS="$_ft_ifs"
        _ft_p="$(printf '%s' "$_ft_p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -n "$_ft_p" ] || continue
        _ft_p="${_ft_p#res://}"; _ft_p="${_ft_p#./}"
        case "$_ft_p" in
          "$_ft_rp"/*) _ft_p="${_ft_p#"$_ft_rp"/}" ;;
          "$_ft_rl"/*) _ft_p="${_ft_p#"$_ft_rl"/}" ;;
        esac
        case "/$_ft_p/" in //*|*/../*) ft_missing "$_ft_p" ;; esac
        [ -f "$_ft_p" ] || ft_missing "$_ft_p"
        case ",$_ft_list," in *",$_ft_p,"*) ;; *) _ft_list="${_ft_list:+$_ft_list,}$_ft_p" ;; esac
      done
      IFS="$_ft_ifs"; set +f
    done
    [ -n "$_ft_list" ] || ft_usage
    exec sh "$(dirname "$0")/studio-gate" studio-test-file -- sh "$(dirname "$0")/studio-dispatch" test --file "$_ft_list" ;;
esac
exec sh "$(dirname "$0")/studio-gate" studio-test -- sh "$(dirname "$0")/studio-dispatch" test "$@"
```

`case "/$_ft_p/" in //*` catches a path that is still absolute after stripping. `*/../*` catches any `..` component.

In `test.sh`, replace `target="${1:-}"` through the `fi` of the target block (:47-58) with:

```sh
target="${1:-}"
if [ "$target" = --file ]; then
  # File run (#59 R3). Probe 2026-10-07, GUT 9.6.0: GUT auto-loads
  # res://.gutconfig.json even without -gconfig, and the config's dirs run as
  # well unless -gdir= empties them. So with a config the file form is always
  # -gconfig + -gdir= + -gtest (comma list); never "simplify" it by dropping
  # -gconfig — that runs the whole suite. See the spec
  # docs/game-dev/specs/2026-10-07-overnight-hardening.md (Probe).
  _tf=""; _tf_ifs="$IFS"; IFS=,; set -f
  for _tf_p in ${2:-}; do
    IFS="$_tf_ifs"
    [ -f "$PROJECT/$_tf_p" ] || { echo "studio-test: no such test file $_tf_p" >&2; exit 4; }
    _tf="${_tf:+$_tf,}res://$_tf_p"
  done
  IFS="$_tf_ifs"; set +f
  [ -n "$_tf" ] || { echo "studio-test: --file needs a test file" >&2; exit 4; }
  set -- "-gtest=$_tf"
  [ -z "$gutconfig" ] || set -- "-gdir=" "$@"
else
  target="${target#./}"
  target="${target%/}"
  … the existing if/elif/else unchanged …
fi
```

The existing `[ -z "$gutconfig" ] || set -- "-gconfig=res://$gutconfig" "$@"` then prepends `-gconfig`, giving `-gconfig=… -gdir= -gtest=…`. Header:
- add `--file LIST` (a comma list of project-relative files; exit 4 when one is missing);
- add exit `4`.

GUIDE.md `test.sh` row: add `` `test.sh --file A,B` → `-gdir= -gtest=res://A,res://B` (with `-gconfig` only beside `-gdir=`) ``, and note the probe.

- [ ] **Step 4: Run; they pass.** Run the Step 2 command, then the whole of `sh tests/toolkit_test.sh`.

- [ ] **Step 5: Commit.** `git commit -m 'feat(test): studio-test --file runs only the named GUT scripts (#59)' -- studios/game-dev/bin/studio-test studios/game-dev/engines/godot/test.sh studios/game-dev/engines/godot/GUIDE.md README.md tests/toolkit_test.sh`

---

### Task B3: AC10 live probe (real Godot + GUT, never phoenix)

Review: — (a live check; its output goes into the PR body). Wave 3. Lane B, after B2. Run it in the lane-B worktree or on the integrated branch.

**Files:** create `tests/probes/studio_test_file_probe.sh` (`chmod +x`). It is not a `*_test.sh` file, so `run_all.sh` never runs it.

**Interfaces:** `studio_test_file_probe.sh <project-dir>`. It needs `GODOT_PATH`. It prints `PASS: …` and exits 0, or prints `FAIL: …` and exits 1.

- [ ] **Step 1: Write the probe.** It runs `cd "$1" && mkdir -p .studio && timeout 300 sh <repo>/studios/game-dev/bin/studio-test --file tests/unit/test_a.gd,tests/e2e/test_c.gd`. It reads the newest `.studio/reports/test-*.log` and checks these:
  - `RAN_A` and `RAN_C` are present;
  - `RAN_B` is absent;
  - `PRE_RAN` and `POST_RAN` are present;
  - the log's `stub`-free command line shows `-gdir= -gtest=res://tests/unit/test_a.gd,res://tests/e2e/test_c.gd`;
  - `.studio/gate.times` has a `studio-test-file` line;
  - the exit is 0.

  `<repo>` is `$(cd "$(dirname "$0")/../.." && pwd)`. The header names the project shape it expects:
  - a GUT addon copied from phoenix;
  - `.gutconfig.json` with `dirs` and pre/post scripts that print the markers;
  - three test scripts that print `RAN_A`, `RAN_B` and `RAN_C`.

- [ ] **Step 2: Run it once.** Use the throwaway project `/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/c430b7fd-309d-4011-a075-a814470954d1/scratchpad/gutprobe`.
  - It is not a git repo, and its `.gutconfig.json` has `dirs` `res://tests/unit` and `res://tests/e2e`, `include_subdirs`, and pre/post scripts printing `PRE_RAN`/`POST_RAN`. It was built for the spec probe.
  - If it is gone, rebuild it in the scratchpad with that shape: copy `addons/gut` from phoenix; read only, never run anything in phoenix.
  - Command: `GODOT_PATH=/Applications/Godot_mono.app/Contents/MacOS/Godot sh tests/probes/studio_test_file_probe.sh <gutprobe>`.
  - Expected result: `PASS`.
  - **On FAIL**, stop and report with the log. The comma `-gtest` form is the spec's one unproven assumption (R3 last bullet). Do not change B2's command form without a decision from the caller.

- [ ] **Step 3: Commit** the probe: `git commit -m 'test(probe): studio-test --file live check against real GUT (#59 AC10)' -- tests/probes/studio_test_file_probe.sh`. Keep the PASS output for the PR body.

---

### Task C1: godot-guard hook (R4, AC7)

Review: task (Opus). Wave 1. Lane C.

**Files:**
- Create `studios/game-dev/hooks/godot-guard.sh` (`chmod +x`).
- Modify `studios/game-dev/hooks/hooks.json`: a new `PreToolUse` entry, after the `Agent|Task|Bash|Monitor` entry.
- Modify `tests/hook_test.sh`: a `GODOT_GUARD=` var beside `AUTOPILOT_GUARD` (:45), a helper, 5 tests, and `run_tests` (:872).

**Interfaces:**
- **Consumes:** PreToolUse JSON on stdin (`tool_input.command`, JSON-escaped).
- **Produces:**
  - On deny, one line of JSON on stdout: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<fixed text>"}}`.
  - Nothing on allow.
  - Always exit 0.
- **hooks.json entry:**

```json
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/godot-guard.sh\""
          }
        ]
      }
```

Anchors: `grep -n '^AUTOPILOT_GUARD=\|^ptu_in()\|^assert_denied()\|^assert_allowed()\|^run_tests' tests/hook_test.sh`

- [ ] **Step 1: Failing tests** in `tests/hook_test.sh` (and `run_tests`). `assert_denied` and `assert_allowed` read `$TMP/ap.out`, so the helper writes there:

```sh
GODOT_GUARD="$STUDIO_DIR/hooks/godot-guard.sh"
# godot_guard INPUT_JSON — run the Godot guard on a Bash call; asserts exit 0; stdout in $TMP/ap.out.
godot_guard() {
  ptu_in Bash "$1" > "$TMP/gg.in"; _gst=0
  sh "$GODOT_GUARD" < "$TMP/gg.in" > "$TMP/ap.out" 2> "$TMP/ap.err" || _gst=$?
  assert_eq 0 "$_gst" "the Godot guard exits 0"
}
test_godot_guard_registered() {
  assert_file "$GODOT_GUARD" "godot-guard.sh exists"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/godot-guard.sh' "hooks.json runs it from the plugin root"
  if command -v jq >/dev/null 2>&1; then
    assert_eq Bash "$(jq -r '.hooks.PreToolUse[] | select(.hooks[0].command | contains("godot-guard")) | .matcher' "$STUDIO_DIR/hooks/hooks.json")" "on Bash"
  fi
}
# AC7 denied (a) + Review Focus 4.
test_godot_guard_denies_headless_boot() {
  for c in \
    'Godot --headless --import . ; Godot --headless --path . -gtest=res://tests/unit/test_vfx_span_player_creature.gd' \
    'cd x && Godot --headless --path . -gtest=res://a.gd' \
    '\"/Applications/Godot 4.app/Contents/MacOS/Godot\" --headless --path .' \
    '$GODOT --headless --path .' \
    '\"${GODOT_BIN}\" --path .' \
    'A=1 godot4 --path .' \
    'cd x\nGodot_mono --headless --path .' \
    'timeout 5 godot --headless --path .' \
    'env FOO=1 Godot_v4.3-stable_linux.x86_64 --path . 2>&1 | tail -5'; do
    godot_guard "{\"command\":\"$c\"}"
    assert_denied "denied: $c"
    assert_contains "$TMP/ap.out" 'studio-test --file' "the reason names studio-test --file ($c)"
  done
}
# AC7 denied (b).
test_godot_guard_denies_hand_built_gut() {
  godot_guard '{"command":"Godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://a.gd -gexit"}'
  assert_denied "a hand-built GUT run"
  assert_contains "$TMP/ap.out" 'gut_cmdln' "the reason names the case"
}
# AC7 allowed + Review Focus 4.
test_godot_guard_allows() {
  for c in \
    'Godot --headless --path . -s other.gd' \
    'Godot --headless --path . --import' \
    'Godot --version' \
    'Godot --headless --path . --export-release Mac out.dmg' \
    'Godot --headless --path . --quit-after 5' \
    'Godot -e --path .' \
    'studio-test --file tests/unit/x.gd' \
    'echo \"Godot --headless --path .\"' \
    'echo \"a; Godot --headless --path .\"' \
    'grep -r godot --path' \
    'ls -la'; do
    godot_guard "{\"command\":\"$c\"}"
    assert_allowed "allowed: $c"
  done
}
test_godot_guard_never_blocks_on_bad_input() {
  for raw in '' 'not json' '{"tool_name":"Bash"}' '{"tool_input":{"command":"Godot \"unterminated'; do
    _gst=0; printf '%s' "$raw" | sh "$GODOT_GUARD" > "$TMP/ap.out" 2>/dev/null || _gst=$?
    assert_eq 0 "$_gst" "exit 0 on bad input ($raw)"
    assert_allowed "and no decision ($raw)"
  done
}
```

`ptu_in` prints its second argument through `%s`, so `\"` and `\n` reach the hook as JSON escapes, which is what Claude Code sends. In the `$GODOT` case, the single-quoted `$` is kept literal.

- [ ] **Step 2: Run; they fail.** `TESTS_ONLY="test_godot_guard_registered test_godot_guard_denies_headless_boot test_godot_guard_denies_hand_built_gut test_godot_guard_allows test_godot_guard_never_blocks_on_bad_input" sh tests/hook_test.sh`. There is no hook file yet.

- [ ] **Step 3: Implement** `godot-guard.sh` (complete):

```sh
#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher Bash), active in every
# session (#59 R4). Refuses a hand-built Godot call that the gate verbs exist
# to replace: phoenix T7 (2026-10-07) ran `Godot --headless --path . -gtest=…`
# without `-s gut_cmdln.gd`; Godot booted the main scene headless, never
# exited, and the unit lost 3 hours. Denied, per simple command:
#   (a) a Godot invocation with --path or --headless and none of -s, --script,
#       --import, -e, --editor, --export*, --version, --doctool, --quit,
#       --quit-after, --help, -h (a headless boot never exits);
#   (b) a Godot invocation that names gut_cmdln (a hand-built GUT run skips
#       the gate lock, and without -gdir= runs the whole suite).
# A Godot invocation is a first word (quotes removed; after NAME=value
# assignments and the wrappers env, exec, command, time, nice, timeout <n>)
# whose basename starts with "godot" in any case, or a $GODOT…/${GODOT…}
# variable. The command is JSON-unescaped, then split quote-aware at ; && ||
# | & ( ) and newlines. The engine adapters run Godot inside their own
# scripts, which this hook never sees.
#
# Exit 0 on every path and print nothing to allow: a parse problem never
# blocks a call. Self-contained on purpose (no jq, no python, no lib/).
trap 'exit 0' EXIT

input="$(cat 2>/dev/null || true)"
[ -n "${input:-}" ] || exit 0

verdict="$(printf '%s' "$input" | tr '\n' ' ' | awk '
  function unesc(s,   o, c, i, n) {
    o = ""; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "\\" && i < n) {
        i++; c = substr(s, i, 1)
        if (c == "n" || c == "r") c = "\n"; else if (c == "t") c = "\t"
      }
      o = o c
    }
    return o
  }
  function flush() { if (inw) { nw++; w[nw] = cur }; cur = ""; inw = 0 }
  function endcmd() { flush(); if (nw) check(); nw = 0; split("", w) }
  function check(   i, j, t, b, hp, ok) {
    i = 1
    while (i <= nw) {
      t = w[i]
      if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t == "!" || t == "{" || t == "if" || t == "then" || t == "else" || t == "elif" || t == "do" || t == "while" || t == "until") { i++; continue }
      if (t == "env") { i++; while (i <= nw && (w[i] ~ /^-/ || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++; continue }
      if (t == "exec" || t == "command" || t == "time") { i++; while (i <= nw && w[i] ~ /^-/) i++; continue }
      if (t == "nice") { i++; if (w[i] == "-n") i += 2; else while (i <= nw && w[i] ~ /^-/) i++; continue }
      if (t == "timeout") { i++; while (i <= nw && w[i] ~ /^-/) { if (w[i] == "-s" || w[i] == "-k") i++; i++ }; i++; continue }
      break
    }
    if (i > nw) return
    b = w[i]; sub(/.*\//, "", b); b = tolower(b)
    if (b !~ /^godot/ && w[i] !~ /^\$\{?GODOT/) return
    hp = 0; ok = 0
    for (j = i + 1; j <= nw; j++) {
      t = w[j]
      if (t ~ /gut_cmdln/) { verdict = "b"; return }
      if (t == "--headless" || t == "--path" || t ~ /^--path=/) hp = 1
      if (t == "-s" || t == "--script" || t == "--import" || t == "-e" || t == "--editor" || t ~ /^--export/ || t == "--version" || t == "--doctool" || t == "--quit" || t == "--quit-after" || t == "--help" || t == "-h") ok = 1
    }
    if (hp && !ok && verdict == "") verdict = "a"
  }
  {
    re = "\"command\"[ \t]*:[ \t]*\"([^\"\\\\]|\\\\.)*\""
    if (!match($0, re)) exit
    raw = substr($0, RSTART, RLENGTH); sub(/^"command"[ \t]*:[ \t]*"/, "", raw); raw = substr(raw, 1, length(raw) - 1)
    cmd = unesc(raw); n = length(cmd); q = ""; cur = ""; inw = 0; nw = 0; verdict = ""
    for (k = 1; k <= n; k++) {
      c = substr(cmd, k, 1)
      if (q == "\x27") { if (c == "\x27") q = ""; else cur = cur c; continue }
      if (q == "\"") {
        if (c == "\\" && k < n) { k++; cur = cur substr(cmd, k, 1); continue }
        if (c == "\"") q = ""; else cur = cur c
        continue
      }
      if (c == "\\" && k < n) { k++; cur = cur substr(cmd, k, 1); inw = 1; continue }
      if (c == "\x27" || c == "\"") { q = c; inw = 1; continue }
      if (c == ";" || c == "&" || c == "|" || c == "\n" || c == "(" || c == ")") { endcmd(); if (verdict == "b") break; continue }
      if (c == " " || c == "\t") { flush(); continue }
      cur = cur c; inw = 1
    }
    endcmd()
    print verdict
    exit
  }' 2>/dev/null)"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}
_use="Run a test file with studio-test --file <tests/unit/x.gd> (repeatable), the suite with studio-test, the game with studio-run."
case "${verdict:-}" in
  a) deny "game-dev: refused a raw headless Godot command (--path or --headless without -s, --import, --export, --version or --quit): it boots the main scene and never exits. $_use" ;;
  b) deny "game-dev: refused a hand-built GUT run (gut_cmdln): it skips the gate lock that keeps Godot runs one at a time across lanes, and without -gdir= it runs the whole suite. $_use" ;;
esac
exit 0
```

Check the escape handling: `"\x27"` (a single quote) works in one-true-awk, gawk and mawk. If one of them refuses it, pass `-v sq="'"` and compare with `sq`. Do that, and note it in the commit, if `test_godot_guard_allows` fails under `dash`/`mawk` on Linux CI.

The deny texts are fixed strings with no `"` or `\`, so they need no JSON escaping.

  - Then add the hooks.json entry and `chmod +x studios/game-dev/hooks/godot-guard.sh`.

- [ ] **Step 4: Run; they pass.** Run the Step 2 command, then `sh tests/hook_test.sh`. Then `TESTS_ONLY="test_bin_syntax" sh tests/studio_test.sh`, which checks that the new hook parses and is executable.

- [ ] **Step 5: Commit.** `git add studios/game-dev/hooks/godot-guard.sh && git commit -m 'feat(hooks): godot-guard refuses a raw headless Godot or a hand-built GUT run (#59)' -- studios/game-dev/hooks/godot-guard.sh studios/game-dev/hooks/hooks.json tests/hook_test.sh`

---

### Task C2: worktree-guard hook; autopilot-guard background text (R5, R7, AC8)

Review: final (folds into the final review). Wave 2. Lane C, after C1.

**Files:**
- Create `studios/game-dev/hooks/worktree-guard.sh` (`chmod +x`).
- Modify `studios/game-dev/hooks/hooks.json`: a new `PreToolUse` entry with matcher `EnterWorktree`, in the same shape as C1's.
- Modify `studios/game-dev/hooks/autopilot-guard.sh`: line :57, the Bash denial.
- Modify `tests/hook_test.sh`: 4 tests, one more assertion in `test_autopilot_guard_bash_and_monitor` (:523), and `run_tests`.

**Interfaces:**
- **Consumes:**
  - env `STUDIO_STORY`;
  - PreToolUse JSON (`tool_input.path`);
  - `studio-state worktree`: exit 0 prints the path; exit 3 prints, on stderr line 2, `[<prefix>]git worktree add '<path>' '<br>'`;
  - `studio-state root` and `studio-state get branch`.
- **Produces:**
  - a deny with reason `game-dev: in a story session EnterWorktree needs path: — a bare call creates a stray worktree. Use path: <P>.`;
  - nothing on allow;
  - always exit 0.

Anchors:
- `grep -n 'with timeout set to' studios/game-dev/hooks/autopilot-guard.sh`
- `grep -n '^test_autopilot_guard_bash_and_monitor' tests/hook_test.sh`
- `grep -n "printf '%sgit worktree add" studios/game-dev/bin/studio-state`

- [ ] **Step 1: Failing tests** in `tests/hook_test.sh` (and `run_tests`):

```sh
WT_GUARD="$STUDIO_DIR/hooks/worktree-guard.sh"
STATE_BIN_H="$STUDIO_DIR/bin/studio-state"
# wt_proj NAME — a git repo with studio state; story S1's branch feat/x recorded. Sets Q.
wt_proj() {
  Q="$TMP/wt-$1"; mkdir -p "$Q"
  ( cd "$Q" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i \
    && sh "$STATE_BIN_H" init && STUDIO_STORY=S1 sh "$STATE_BIN_H" set branch feat/x ) >/dev/null 2>&1
  Q="$(cd "$Q" && pwd -P)"
}
# wt_guard STORY|- AUTOPILOT|- INPUT_JSON — run the guard in $Q; stdout in $TMP/ap.out; asserts exit 0.
wt_guard() {
  ptu_in EnterWorktree "$3" > "$TMP/wg.in"; _wst=0
  ( cd "$Q" && unset STUDIO_STORY OMEGA_AUTOPILOT
    [ "$1" = - ] || { STUDIO_STORY="$1"; export STUDIO_STORY; }
    [ "$2" = - ] || { OMEGA_AUTOPILOT="$2"; export OMEGA_AUTOPILOT; }
    sh "$WT_GUARD" < "$TMP/wg.in" ) > "$TMP/ap.out" 2> "$TMP/ap.err" || _wst=$?
  assert_eq 0 "$_wst" "the worktree guard exits 0"
}
test_worktree_guard_registered() {
  assert_file "$WT_GUARD" "worktree-guard.sh exists"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/worktree-guard.sh' "registered from the plugin root"
  if command -v jq >/dev/null 2>&1; then
    assert_eq EnterWorktree "$(jq -r '.hooks.PreToolUse[] | select(.hooks[0].command | contains("worktree-guard")) | .matcher' "$STUDIO_DIR/hooks/hooks.json")" "on EnterWorktree"
  fi
}
# AC8 denied / allowed in a story session.
test_worktree_guard_denies_bare_calls_in_story() {
  wt_proj story
  for j in '{}' '{"name":"x"}' '{"path":""}'; do
    wt_guard S1 - "$j"; assert_denied "STUDIO_STORY=S1: $j is denied"
    assert_contains "$TMP/ap.out" 'path:' "the reason says path: ($j)"
  done
  wt_guard S1 1 '{"path":"/x"}'; assert_allowed "a path is allowed"
}
# R5's three sources for the named path.
test_worktree_guard_names_the_story_worktree() {
  wt_proj names
  ( cd "$Q" && git branch feat/x ) >/dev/null 2>&1
  wt_guard S1 - '{}'
  assert_contains "$TMP/ap.out" "path: $Q/.claude/worktrees/feat-x" "exit 3: the path studio-state suggests"
  ( cd "$Q" && git worktree add -q "$TMP/wt-names-live" feat/x ) >/dev/null 2>&1
  wt_guard S1 - '{}'
  assert_contains "$TMP/ap.out" "path: $(cd "$TMP/wt-names-live" && pwd -P)" "exit 0: the live worktree"
  wt_proj gone
  wt_guard S1 - '{}'
  assert_contains "$TMP/ap.out" "path: $Q/.claude/worktrees/feat-x" "no branch yet (exit 1): the execute §0 rule"
}
# AC8: off outside story sessions.
test_worktree_guard_off_outside_stories() {
  wt_proj off
  for j in '{}' '{"name":"x"}'; do
    wt_guard - 1 "$j"; assert_allowed "OMEGA_AUTOPILOT=1 only: $j is allowed"
    wt_guard - - "$j"; assert_allowed "neither variable: $j is allowed"
  done
}
```

Before relying on `wt_proj`, verify its setup by hand once in the scratchpad:
- `STUDIO_STORY=S1 studio-state set branch feat/x` succeeds with no story ledger;
- with the branch absent, `worktree` exits 1 (`branch feat/x no longer exists`);
- after `git branch feat/x`, it exits 3 and suggests `<root>/.claude/worktrees/feat-x`.

If `set branch` needs more state, use what `tests/state_stories_test.sh` does to make a story pointer, and keep the three exit paths.

In `test_autopilot_guard_bash_and_monitor`, after the 'foreground' assertion, add `assert_contains "$TMP/ap.out" 'only on gate-routed commands' "timeout goes only on gate-routed commands (#59 R7)"`.

- [ ] **Step 2: Run; they fail.** `TESTS_ONLY="test_worktree_guard_registered test_worktree_guard_denies_bare_calls_in_story test_worktree_guard_names_the_story_worktree test_worktree_guard_off_outside_stories test_autopilot_guard_bash_and_monitor" sh tests/hook_test.sh`

- [ ] **Step 3: Implement** `worktree-guard.sh` (complete):

```sh
#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher EnterWorktree), #59 R5.
# In a story session (STUDIO_STORY set: an overnight lane unit) the story's
# worktree already exists or has a known path, so EnterWorktree must name it
# with `path:`. A bare call (or `name:` alone) creates a stray worktree:
# phoenix S1 T7's retry (2026-10-07) made one, could not remove it, and ended
# with no progress. Outside story sessions every call is allowed: a
# single-plan unit's isolation step creates its worktree with a name or none.
# The reason names the story worktree: `studio-state worktree` (exit 0), else
# the path it suggests (exit 3), else execute §0's rule
# <root>/.claude/worktrees/<branch with / → ->.
# Exit 0 on every path and print nothing to allow. Self-contained (no jq).
trap 'exit 0' EXIT

[ -n "${STUDIO_STORY:-}" ] || exit 0
input="$(cat 2>/dev/null || true)"
flat="$(printf '%s' "${input:-}" | tr '\n\t' '  ')"
# A non-empty "path" (a key named exactly path; "transcript_path" does not match).
printf '%s' "${flat:-}" | grep -q '"path"[[:space:]]*:[[:space:]]*"[^"]' && exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
ST="$HERE/../bin/studio-state"
P="$(sh "$ST" worktree 2>/dev/null)" || P=""
if [ -z "$P" ]; then
  P="$(sh "$ST" worktree 2>&1 >/dev/null | sed -n "s/.*git worktree add '\([^']*\)'.*/\1/p" | head -n 1)"
fi
if [ -z "$P" ]; then
  _r="$(sh "$ST" root 2>/dev/null)"; _b="$(sh "$ST" get branch 2>/dev/null)"
  case "$_b" in ''|-) ;; *) [ -z "$_r" ] || P="$_r/.claude/worktrees/$(printf '%s' "$_b" | tr '/' '-')" ;; esac
fi
[ -n "$P" ] || P="<the story worktree: run studio-state worktree>"
P="$(printf '%s' "$P" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
  "game-dev: in a story session EnterWorktree needs path: — a bare call creates a stray worktree. Use path: $P."
exit 0
```

`studio-state` exits 0 only with a path on stdout. Check that `P` from `$(… worktree 2>/dev/null) || P=""` keeps the stdout of exit 0 and is empty otherwise. In the exit-3 case, the first command's stdout is empty and the second picks the path from stderr.

  - `autopilot-guard.sh` :57: replace `Run it in the foreground (no run_in_background, no &) with timeout set to \$BASH_MAX_TIMEOUT_MS.` with `Run it in the foreground (no run_in_background, no &); pass timeout: \$BASH_MAX_TIMEOUT_MS only on gate-routed commands (studio-test, studio-run, studio-setup, studio-gate), and let every other command keep the default cap.`
  - Add the hooks.json entry and run `chmod +x`.

- [ ] **Step 4: Run; they pass.** Run the Step 2 command, then `sh tests/hook_test.sh`, then `TESTS_ONLY="test_bin_syntax" sh tests/studio_test.sh`. If `jq` is present, also run `jq -e . studios/game-dev/hooks/hooks.json`.

- [ ] **Step 5: Commit.** `git add studios/game-dev/hooks/worktree-guard.sh && git commit -m 'feat(hooks): worktree-guard — a story session enters its worktree by path (#59)' -- studios/game-dev/hooks/worktree-guard.sh studios/game-dev/hooks/hooks.json studios/game-dev/hooks/autopilot-guard.sh tests/hook_test.sh`

---

### Task D1: Spec items `L<a>`, shared parser, `studio-brief validate` (R6, AC9)

Review: task (Opus). Wave 1. Lane D.

**Files:**
- Modify `studios/game-dev/bin/studio-brief`:
  - the header (:1-39), which points at the plan skill for the item format;
  - `usage` (:45-48);
  - a new `spec_item` and `plan_tasks` after `emit` (:67);
  - the `CALLER_PWD` capture before :99;
  - `emit_task`'s item loop (:128-157);
  - a new `validate)` branch in the verb `case` (:205).
- Modify `studios/game-dev/skills/plan/SKILL.md`: the Spec rule (:74-77) and the self-review (:151-156).
- Modify `tests/studio_brief_test.sh`: 5 tests, `test_brief_usage_names_check`, and `run_tests` (:352).
- Modify `tests/studio_test.sh`: `test_plan_brainstorm_lanes` (:684-688).

**Interfaces:**
- **Produces:**
  - `spec_item ITEM`. On success it returns 0 and sets `SI_FILE SI_A SI_B`. On failure it returns 1 and sets `SI_ERR`. Errors:
    - `spec <f> not found (Spec: item '<item>')`;
    - `bad range in Spec: item '<item>'`, for non-numeric or a > b;
    - `range <item> is past the end of <f> (<n> lines)`;
    - `heading '<h>' not found in <f>`;
    - `cannot parse Spec: item '<item>'`.
  - `plan_tasks PLAN` prints the task numbers of `### Task <n>:` headings outside fences.
  - `studio-brief validate <plan>` exits:
    - 0, printing `studio-brief: <T> tasks, <I> Spec items ok`;
    - 1, printing `studio-brief: task <n>: <error>` and `studio-brief: task <n>: no Spec: line` on stderr, or `studio-brief: no ### Task blocks in <plan>`;
    - 2 for a missing plan (`studio-brief: plan <path> not found`) or bad usage.
- **Consumes:** `section`, `emit`, `fail`, and the `cd "$WORK"` at :99.

Anchors: `grep -n '^usage()\|^emit()\|^WORK=\|^emit_task()\|^  \*:L\[0-9\]\|^case "\$verb" in\|^task)$' studios/game-dev/bin/studio-brief`

- [ ] **Step 1: Failing tests** in `tests/studio_brief_test.sh` (and `run_tests`). `build_fixture DIR` writes `docs/spec.md` (32 lines; its headings include `### Data`) and `docs/plan.md`.

```sh
# AC9 + Review Focus 5: an L<a> item is one line.
test_brief_single_line_item() {
  Q="$TMP/projl"; build_fixture "$Q"
  sed -i.bak 's#^Spec: docs/spec.md:L3-4$#Spec: docs/spec.md:L3#' "$Q/docs/plan.md"; rm -f "$Q/docs/plan.md.bak"
  ( cd "$Q" && sh "$STATE_BIN" init && sh "$STATE_BIN" set plan docs/plan.md ) >/dev/null 2>&1
  brief_in "$Q" task 1 > "$TMP/l.out"; st=$?
  assert_eq 0 "$st" "task accepts <spec>:L3"
  assert_contains "$TMP/l.out" '^==> docs/spec.md:L3-3$' "read as L3-3"
  assert_eq "$(sed -n 3p "$Q/docs/spec.md")" "$(sed -n '/^==> docs\/spec.md:L3-3$/{n;p;}' "$TMP/l.out")" "emits line 3"
}
test_brief_validate_good_plan() {
  Q="$TMP/projv"; build_fixture "$Q"
  # Tasks 2 and 4 have no Spec: line in the fixture — give them one.
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/v.out" 2> "$TMP/v.err"; st=$?
  assert_eq 0 "$st" "a good plan passes"
  assert_contains "$TMP/v.out" '^studio-brief: 4 tasks, 5 Spec items ok$' "counts tasks and items"
}
# AC9: every problem in one run.
test_brief_validate_reports_all() {
  Q="$TMP/projbad"; mkdir -p "$Q/docs"; printf 'l1\nl2\n# H\nl4\n' > "$Q/docs/s.md"
  cat > "$Q/docs/plan.md" <<'PLAN'
# Plan
### Task 1: a
Spec: docs/s.md L2
### Task 2: b
Spec: docs/s.md:L5-3
### Task 3: c
Spec: docs/none.md:L1
### Task 4: d
Spec: docs/s.md:L3-9
### Task 5: e
Spec: docs/s.md§# Missing
### Task 6: f
no spec here
### Task 7: g
Spec: docs/s.md:L144, docs/s.md:L1-2, docs/s.md§# H
PLAN
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/b.out" 2> "$TMP/b.err"; st=$?
  assert_eq 1 "$st" "exit 1"
  assert_contains "$TMP/b.err" "^studio-brief: task 1: cannot parse Spec: item 'docs/s.md L2'$" "unparseable"
  assert_contains "$TMP/b.err" "^studio-brief: task 2: bad range in Spec: item 'docs/s.md:L5-3'$" "a > b"
  assert_contains "$TMP/b.err" "^studio-brief: task 3: spec docs/none.md not found" "missing file"
  assert_contains "$TMP/b.err" "^studio-brief: task 4: range .* is past the end of docs/s.md (4 lines)$" "past EOF"
  assert_contains "$TMP/b.err" "^studio-brief: task 5: heading '# Missing' not found in docs/s.md$" "missing heading"
  assert_contains "$TMP/b.err" "^studio-brief: task 6: no Spec: line$" "no Spec: line"
  assert_contains "$TMP/b.err" "^studio-brief: task 7: range .*L144.* is past the end" "the phoenix L144 item parses, then fails only on range"
  assert_eq 7 "$(grep -c '^studio-brief: task ' "$TMP/b.err")" "one line per problem, nothing for good items"
  assert_eq "" "$(cat "$TMP/b.out")" "no ok line"
}
test_brief_validate_missing_plan_and_no_state() {
  Q="$TMP/projns"; mkdir -p "$Q"
  ( cd "$Q" && sh "$BRIEF" validate nope.md ) > /dev/null 2> "$TMP/n.err"; st=$?
  assert_eq 2 "$st" "a missing plan exits 2"
  assert_contains "$TMP/n.err" "plan nope.md not found" "names it"
  Q="$TMP/projns2"; build_fixture "$Q"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > /dev/null 2>&1; st=$?
  assert_eq 1 "$st" "no studio state needed (the fixture plan's tasks 2 and 4 lack Spec:)"
}
# D12: the plan path is the caller's; Spec paths are the work root's.
test_brief_validate_relative_to_caller() {
  Q="$TMP/projrel"; build_fixture "$Q"
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  ( cd "$Q/docs" && sh "$BRIEF" validate plan.md ) > /dev/null 2>&1; st=$?
  assert_eq 0 "$st" "from docs/: plan.md is found, docs/spec.md resolves from the root"
}
```

  - In `test_brief_usage_names_check`, add `assert_contains "$TMP/u.err" "validate <plan>" "usage names validate"`.
  - Check the fixture's Task 3 line `Spec: docs/spec.md:L3-4, docs/spec.md§### Data` and Task 1's `L3-4` against `build_fixture`. The good-plan count is 1 + 1 + 2 + 1 = 5. Fix the expected number if the fixture differs.
  - In `tests/studio_test.sh` `test_plan_brainstorm_lanes`:
    - keep :684 `'Spec: <spec>:L<a>-<b>'` and :685 `'§<heading>'` (the new text keeps both);
    - add `assert_contains "$PL" '`<spec>:L<a>` — one line' "one-line items"`;
    - replace :688 with `assert_contains "$PL" 'run `studio-brief validate <plan path>`' "self-review validates the Spec: items"`;
    - add an order check that `studio-brief validate` comes before `studio-state set plan`, as other order checks in that file do with `grep -n`.

- [ ] **Step 2: Run; they fail.** `TESTS_ONLY="test_brief_single_line_item test_brief_validate_good_plan test_brief_validate_reports_all test_brief_validate_missing_plan_and_no_state test_brief_validate_relative_to_caller test_brief_usage_names_check" sh tests/studio_brief_test.sh`. Then `TESTS_ONLY=test_plan_brainstorm_lanes sh tests/studio_test.sh`.

- [ ] **Step 3: Implement.**

```sh
# spec_item ITEM — one Spec: item (the format: skills/plan/SKILL.md, the
# Spec-line rule). Paths resolve from the current directory. Sets SI_FILE,
# SI_A, SI_B (a line range; a heading gives its block) and returns 0, or sets
# SI_ERR and returns 1 — never exits, so validate can collect every error.
spec_item() {
  SI_FILE=""; SI_A=""; SI_B=""; SI_ERR=""
  case "$1" in
    *§*)
      SI_FILE="${1%%§*}"; _si_h="${1#*§}"
      [ -f "$SI_FILE" ] || { SI_ERR="spec $SI_FILE not found (Spec: item '$1')"; return 1; }
      _si_r="$(section "$SI_FILE" "$_si_h" 1)"
      [ -n "$_si_r" ] || { SI_ERR="heading '$_si_h' not found in $SI_FILE"; return 1; }
      SI_A="${_si_r% *}"; SI_B="${_si_r#* }" ;;
    *:L*)
      SI_FILE="${1%:L*}"; _si_g="${1##*:L}"
      case "$_si_g" in *-*) SI_A="${_si_g%%-*}"; SI_B="${_si_g#*-}" ;; *) SI_A="$_si_g"; SI_B="$_si_g" ;; esac
      case "$SI_A/$SI_B" in */|/*|*[!0-9/]*) SI_ERR="bad range in Spec: item '$1'"; return 1 ;; esac
      { [ "$SI_A" -ge 1 ] && [ "$SI_A" -le "$SI_B" ]; } || { SI_ERR="bad range in Spec: item '$1'"; return 1; }
      [ -f "$SI_FILE" ] || { SI_ERR="spec $SI_FILE not found (Spec: item '$1')"; return 1; }
      _si_t="$(wc -l < "$SI_FILE" | tr -d ' ')"
      [ -n "$(tail -c1 "$SI_FILE")" ] && _si_t=$((_si_t + 1))   # a final line without a newline counts
      [ "$SI_B" -le "$_si_t" ] || { SI_ERR="range $1 is past the end of $SI_FILE ($_si_t lines)"; return 1; } ;;
    *) SI_ERR="cannot parse Spec: item '$1'"; return 1 ;;
  esac
  return 0
}
# plan_tasks PLAN — the numbers of its `### Task <n>:` headings, outside fences, in order.
plan_tasks() {
  awk '/^```/ { f = !f; next } !f && /^### Task [0-9]+:/ { s = $3; sub(/:.*/, "", s); print s }' "$1"
}
```

  - **`range` text.** Keep today's wording: `range $item is past the end…`. Today's `$item` is the whole item, so use `range $1 is past the end of …` to stay identical.
  - **Caller dir.** Before :99, add `CALLER_PWD="$(pwd -P)"`.
  - **`emit_task` loop.** The body becomes `spec_item "$item" || fail "$SI_ERR"; emit "$SI_FILE" "$SI_A" "$SI_B"`. Keep the `IFS` handling and the `, ` split as they are.
  - **`usage`.** It becomes `usage: studio-brief task <n> | final | check <k> | validate <plan>`.
  - **The `validate)` branch**:

```sh
validate)
  [ $# -eq 2 ] || usage
  case "$2" in /*) vplan="$2" ;; *) vplan="$CALLER_PWD/$2" ;; esac
  [ -f "$vplan" ] || { printf 'studio-brief: plan %s not found\n' "$2" >&2; exit 2; }
  _vt=0; _vi=0; _vbad=0
  for _vn in $(plan_tasks "$vplan"); do
    _vt=$((_vt + 1))
    _vr="$(section "$vplan" "### Task $_vn:" 0)"
    _vs="$(sed -n "${_vr% *},${_vr#* }p" "$vplan" | sed -n 's/^Spec: //p' | head -n 1)"
    if [ -z "$_vs" ]; then printf 'studio-brief: task %s: no Spec: line\n' "$_vn" >&2; _vbad=1; continue; fi
    _vitems="$(printf '%s\n' "$_vs" | sed 's/, /\
/g')"
    _vifs="$IFS"; IFS='
'
    for _vit in $_vitems; do
      IFS="$_vifs"; _vi=$((_vi + 1))
      spec_item "$_vit" || { printf 'studio-brief: task %s: %s\n' "$_vn" "$SI_ERR" >&2; _vbad=1; }
      IFS='
'
    done
    IFS="$_vifs"
  done
  [ "$_vt" -gt 0 ] || { printf 'studio-brief: no ### Task blocks in %s\n' "$2" >&2; exit 1; }
  [ "$_vbad" = 0 ] || exit 1
  printf 'studio-brief: %s tasks, %s Spec items ok\n' "$_vt" "$_vi"
  ;;
```

  - **Header.** Replace the format restatements at :5-10 with one line: "Spec: items — the format is the plan skill's Spec-line rule (`skills/plan/SKILL.md`)". Add the `validate` verb with its exit codes. The `==> <file>:L<a>-<b>` part header stays: it is output, not input.
  - **plan SKILL.md, the Spec rule** (:74-77):

```
  - `Spec: <item>[, <item>…]` cites the spec lines the task implements; items
    are separated by `, `. An item is one of:
    - `<spec>:L<a>-<b>` — lines a to b (`Spec: <spec>:L<a>-<b>`, the usual form);
    - `<spec>:L<a>` — one line, the same as `L<a>-<a>`;
    - `<spec>§<heading>` — a heading line exactly as written in the spec,
      including its `#`s.
    The lines must exist: `studio-brief validate` checks them (§6).
```

  - **plan SKILL.md, the self-review** (:155-156): change "every task has a `Spec:` line whose ranges exist, and a `Review:` line." to "every task has a `Spec:` line and a `Review:` line. Then run `studio-brief validate <plan path>` and fix the plan until it exits 0: it checks every task's `Spec:` items (the file, the range, the heading) the way execute's brief will read them." This goes before the paragraph that runs `studio-state set plan`.

- [ ] **Step 4: Run; they pass.** Run the Step 2 commands. Then the whole of `sh tests/studio_brief_test.sh`, then `sh tests/studio_test.sh`, then `sh tests/omega_test.sh`, which sources `omega_contracts/`. `autopilot_contract.sh:112`'s `<original>:L<a>-<b>` must stay untouched.

- [ ] **Step 5: Commit.** `git commit -m 'feat(brief): L<a> Spec items and studio-brief validate; plan self-review runs it (#59)' -- studios/game-dev/bin/studio-brief studios/game-dev/skills/plan/SKILL.md tests/studio_brief_test.sh tests/studio_test.sh`

---

### Task E1: Execute skill and gameplay-programmer text (R7, AC11)

Review: final (folds into the final review). Wave 1. Lane E.

**Files:**
- Modify `studios/game-dev/skills/execute/SKILL.md`:
  - :116-118, the new-branch `EnterWorktree` line;
  - :143-161, the §0 gate bullet;
  - a new bullet after it;
  - :273-276, the resume `EnterWorktree`;
  - §2, after :341-346.
- Modify `studios/game-dev/agents/gameplay-programmer.md`: :34-36.
- Modify `tests/studio_test.sh`: 2 new tests after `test_execute_lane_gate_foreground` (:596), plus `run_tests`.

**Interfaces:**
- **Consumes** the names other lanes produce:
  - `studio-test --file <test file>` and exit 124 (B);
  - `STUDIO_GATE_MINUTES`, `idle_minutes` and `stalled` (A);
  - `godot-guard.sh` and `worktree-guard.sh` (C).
- **Literals that must stay** (`studio_test.sh` :565, :588-592, :595, :305, :627, :635):
  - `as foreground Bash calls with \`timeout\` set to \`$BASH_MAX_TIMEOUT_MS\``;
  - `**The gate runs in the foreground.** Run \`studio-test\` and \`studio-run\``;
  - `no \`&\` inside the command, no Monitor or notification`;
  - `` `tests/probes/bash_timeout_probe.sh` (2026-10-02) ``;
  - `Stop: gate timed out — <command> ran past <n> min`;
  - §7's `` `studio-test` and `studio-run` each run as a foreground Bash call with `timeout` set to `$BASH_MAX_TIMEOUT_MS` ``;
  - §2's verbatim brief line, which appears exactly once;
  - `studio-test <path>`.
- **Rule** (`test_execute_lane_gate_foreground`): no line may pair `studio-test`/`studio-run` with `background` unless the line also contains `never` or `moved to the background`.

Anchors:
- `grep -n "then \`EnterWorktree\` with \`path:\`\|whole session's minutes\|call \`EnterWorktree\` with\|carries this line$\|^verbatim (§0" studios/game-dev/skills/execute/SKILL.md`
- `grep -n 'studio-test <test file>' studios/game-dev/agents/gameplay-programmer.md`

- [ ] **Step 1: Failing tests** in `tests/studio_test.sh` (and `run_tests`):

```sh
# #59 R7: one bounded command per hang; file runs and gate timeouts by rule.
test_execute_command_caps_text() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_not_contains "$E" "whole session's minutes" "the old sentence is gone"
  for lit in 'studio-test --file <test file>' 'Never build a Godot or GUT command by hand' \
    'only on gate-routed commands' 'every other command keeps the default cap' \
    'the tool that stops background tasks' 'exits 124' 'min(45, `session_minutes`/3)' \
    'min(60, `session_minutes`/2)' '`stalled`' 'godot-guard.sh' 'worktree-guard.sh'; do
    assert_contains "$E" "$lit" "execute says: $lit"
  done
  assert_eq 2 "$(grep -c 'worktree-guard.sh' "$E")" "both EnterWorktree path: places name the hook"
}
test_agent_gameplay_programmer_file_runs() {
  A="$REPO_ROOT/studios/game-dev/agents/gameplay-programmer.md"
  for lit in 'studio-test --file <test file>' 'Never build a Godot or GUT command by hand' \
    'only on gate-routed commands' 'the tool that stops background tasks' 'exits 124'; do
    assert_contains "$A" "$lit" "gameplay-programmer says: $lit"
  done
}
```

`assert_contains` greps with BRE. Escape `[`, `*` and `.` only if a literal needs it; `(`, `)` and `` ` `` are literal in BRE.

- [ ] **Step 2: Run; they fail.** `TESTS_ONLY="test_execute_command_caps_text test_agent_gameplay_programmer_file_runs test_execute_lane_gate_foreground" sh tests/studio_test.sh`. The first two fail; the third passes.

- [ ] **Step 3: Edit the text.**
  - **§0 gate bullet** (:143-161). Keep every listed literal. Replace the last two sentences, from "Usually the session cap ends the unit first (the `timeout` is the whole session's minutes)" through "Either way the runner ends any gate the unit leaves behind.", with:

    > Every command is bounded (the runner sets these from `session_minutes`): a Bash call with no `timeout` gets min(45, `session_minutes`/3) minutes (`BASH_DEFAULT_TIMEOUT_MS`), and `studio-gate` stops a gate-routed command that runs past min(60, `session_minutes`/2) minutes (`STUDIO_GATE_MINUTES`); it then exits 124. A gate-routed command that exits 124 is a timed-out gate as well: the same `Stop: gate timed out — <command> ran past <n> min` line, then end the turn. A unit whose log stays silent for `idle_minutes` outside a gate is ended and recorded `stalled`. Either way the runner ends any gate the unit leaves behind. §2 carries this rule into every subagent brief.

  - **A new bullet after it:**

    > - **Pass `timeout` only on gate-routed commands.** `timeout: $BASH_MAX_TIMEOUT_MS` goes on `studio-test`, `studio-run`, `studio-setup` and `studio-gate` calls only; every other command keeps the default cap. A non-gate command that its timeout moved to the background is hung: stop it with the tool that stops background tasks (TaskStop) and do not wait for it. Run a single test file with `studio-test --file <test file>` (repeatable; a comma list works too). Never build a Godot or GUT command by hand: the studio's `godot-guard.sh` hook refuses a raw headless Godot and a hand-built `gut_cmdln` run.

    Check each wrapped line against the background rule. The sentence with "moved to the background" carries its own exemption; keep it and any `studio-test` mention off the same line unless the line has "moved to the background".
  - **The two `EnterWorktree` `path:` places.**
    - At :117, after "then `EnterWorktree` with `path:`", insert "(in a story session the studio's `worktree-guard.sh` hook refuses a call without `path:` — a bare call creates a stray worktree)".
    - At :274-275, after "call `EnterWorktree` with `path: <it>`", insert "(`worktree-guard.sh` refuses a bare call in a story session)".
  - **§2**, after the verbatim line paragraph (:341-346), add:

    > Every implementer and fixer brief also carries: "run one test file with `studio-test --file <test file>`; never build a Godot or GUT command by hand; pass `timeout` only on gate-routed commands; a gate-routed command that exits 124 is `Stop: gate timed out`".

  - **gameplay-programmer.md :34-36.**
    - Step 2 becomes "Run `studio-test --file <test file>` and paste the failing summary line."
    - After step 3, add a paragraph: "Never build a Godot or GUT command by hand (the studio's hook refuses one). Pass `timeout: $BASH_MAX_TIMEOUT_MS` only on gate-routed commands (`studio-test`, `studio-run`, `studio-setup`, `studio-gate`); every other command keeps the default cap. A command that its timeout moved to the background is hung: stop it with the tool that stops background tasks, and do not wait for it. A `studio-test` that exits 124 ran past the gate run cap: report it verbatim as `gate timed out — <command> ran past <n> min`; it exits 124."

- [ ] **Step 4: Run; they pass.** Run the Step 2 command. Then `sh tests/studio_test.sh`, `sh tests/pointer_skills_execute_test.sh` and `sh tests/omega_test.sh` (AC11).

- [ ] **Step 5: Commit.** `git commit -m 'docs(skills): execute and gameplay-programmer — file runs, gate-only timeouts, exit 124, guards (#59)' -- studios/game-dev/skills/execute/SKILL.md studios/game-dev/agents/gameplay-programmer.md tests/studio_test.sh`

---

### Task F: Integration, final whole-branch review, fix wave, full gate, PR

- [ ] **Integrate.** Cherry-pick each lane's commits onto `59-overnight-hardening`, in the order A1, A2, B1, B2, B3, C1, C2, D1, E1. The only expected conflict is the `run_tests` line of `tests/studio_test.sh` (D1 and E1); keep both name lists. Remove each implementer's worktree once its commits are on the story branch.
- [ ] **PROGRESS.** Add a dated entry at the top of `docs/game-dev/PROGRESS.md`, in its existing style: `### 2026-10-07 — Overnight hardening (#59)`. It covers:
  - the T7 loss;
  - the caps;
  - the idle watchdog and `stalled`;
  - `studio-test --file` (with B3's PASS);
  - the two hooks;
  - `L<a>` and `studio-brief validate`;
  - the spec and plan paths.

  Commit `docs(progress): overnight hardening (#59)`.
- [ ] **Final review.** A standalone whole-branch review on Opus over `1796538..HEAD`, against the spec and this plan. B2, C2 and E1 get their only review here. Point the reviewer at the Review Focus list and Decisions D2, D5 and D10.
- [ ] **Fix wave.** One fresh fixer takes the findings and the diff range, with minor findings batched. Re-review only per the Global Constraints rule.
- [ ] **Full gate**, once, on the integrated branch:
  - `sh tests/run_all.sh` (AC12);
  - then `sh integrations/multica/tests/run.sh`.
  - Build a fresh worktree's git-ignored setup before running, if the suites need any.
- [ ] **PR.** Open the PR with `Closes #59` and `Supersedes #43`.
  - The body covers D2 (the runner's gates are uncapped), D5 (the claim marker), D9 (the new warning line), and B3's live probe output (AC10).
  - Do not install, sync or pull into the main checkout or `~/.claude-gamedev`: a phoenix run is live, and the operator installs.
  - Merge once green, under the standing omega-ai merge authority, and only via the PR. Leave the reinstall as a noted follow-up for the operator.
- [ ] **Clean up.** Remove the story worktree once the PR has merged, unless the user keeps it.

## Acceptance checklist

| AC | What | Task | Tests |
|----|------|------|-------|
| AC1 | Caps: lanes 180 → 2700000/10800000/60, 90 → 1800000/5400000/45; single-plan and final unit get the same | A1 | `test_lanes_unit_caps`, `test_overnight_unit_caps` (+ `test_lanes_runner_gates_uncapped`, `test_lanes_gate_cap_warning`) |
| AC2 | Gate cap: 124, `ran past`, rc 124; lock wait excluded; unset/0/setup uncapped; seconds seam | B1 | `test_gate_run_cap_stops_a_long_run`, `test_gate_run_cap_excludes_lock_wait`, `test_gate_run_cap_off_unset_zero_and_setup`, `test_gate_run_cap_kills_a_term_ignorer`, `test_gate_run_cap_no_false_stop` |
| AC3 | Silent session + open `sleep` → `stalled`, `unit_stalled` names it, `stalled on T1 (…)`, holdable | A2 | `test_overnight_idle_stall`, `test_overnight_stall_holds_with_until_command`, `test_lanes_stalled_outcome`, `test_lanes_sync_repair_stops` (stall) |
| AC4 | Open `studio-test` call → not stalled; the session cap ends it `timed out` | A2 | `test_overnight_idle_spares_gate_call`, `test_overnight_open_calls` |
| AC5 | `idle_minutes` 0 off; preflight refuses bad values | A2 | `test_overnight_idle_off_and_refusals` |
| AC6 | `--file a,b` and `--file a --file b` → `-s … -gconfig=… -gdir= -gtest=res://a,res://b -gexit`; no config → neither; missing → 4 before Godot; gate who `studio-test-file`; failing → 1 | B2 | `test_test_file_runs_named_files`, `test_test_file_missing_exits_4`, `test_test_file_through_gate`, `test_test_file_path_forms`, `test_test_file_misuse_exits_4` |
| AC7 | Godot guard denies and allows (the spec's lists); registered | C1 | `test_godot_guard_denies_headless_boot`, `test_godot_guard_denies_hand_built_gut`, `test_godot_guard_allows`, `test_godot_guard_registered`, `test_godot_guard_never_blocks_on_bad_input` |
| AC8 | Worktree guard: denied with `path:` under `STUDIO_STORY`; allowed otherwise; registered | C2 | `test_worktree_guard_denies_bare_calls_in_story`, `test_worktree_guard_names_the_story_worktree`, `test_worktree_guard_off_outside_stories`, `test_worktree_guard_registered` |
| AC9 | `task` accepts `L3`; `validate` good → 0; all six errors in one run → 1; missing plan → 2 | D1 | `test_brief_single_line_item`, `test_brief_validate_good_plan`, `test_brief_validate_reports_all`, `test_brief_validate_missing_plan_and_no_state`, `test_brief_validate_relative_to_caller` |
| AC10 | Live: two files, exactly those plus pre/post | B3 | `tests/probes/studio_test_file_probe.sh` PASS (in the PR body) |
| AC11 | Pointer and contract suites pass with the new text | D1, E1 | `test_execute_command_caps_text`, `test_agent_gameplay_programmer_file_runs`, `test_plan_brainstorm_lanes`, `pointer_skills_execute_test.sh`, `omega_test.sh` |
| AC12 | `sh tests/run_all.sh` passes | F | the full gate |

## Falsify pass

Every anchor in this plan was checked at 1796538 by `grep -n` or a read of the whole function. The corrections it forced:

1. **The `.ended` claim's `rmdir`** (:1148, :1179) cannot remove a claim with a marker inside it. Both become `rm -rf "$_claim" "$_claim.stall"` (D5).
2. **Lane repairs** (land :663, gate :715, sync :809) launch through the story's `LAUNCH_ENV`. They inherit the caps from `story_launch_env` with no edit of their own. Only their endings change (A2).
3. **Single-plan launch words.** `tests/overnight_test.sh:302` and `:517` assert the literal `OMEGA_AUTOPILOT=1 claude-gd -p '/game-dev:execute --one'`, so the caps go **before** `OMEGA_AUTOPILOT=1` (D1).
4. **The overnight_test.sh fake `claude` has no `emit` action**, and it records only `OMEGA_AUTOPILOT` (`.env`), not the whole environment. A2 adds `emit` and `gatereg`, and A1 adds a `.caps` file. The lanes stub already has `emit` (:292) and `fullenv` (:174).
5. **`gate_room_check`'s `return 0` paths** come before any new check could run. The GATE_MIN warning goes before them. Its text must not start `warning: the slowest`, which `test_lanes_gate_room_warning` asserts absent for small gates (D9).
6. **`STUDIO_GATE_MINUTES` must never be in the runner's own environment.** The merge (lanes :635) and the final gate (:1713) run `studio-gate` from the runner. So the runner `unset`s it, and `run_story` exports only `BASH_*` (D2).
7. **Hook files must be executable.** `test_bin_syntax` (`studio_test.sh:108`) checks `-x` as well as `sh -n`. Both new hooks get `chmod +x` (C1, C2).
8. **`test_gate_wraps_test_and_run`** greps `studio-test` for `studio-gate" studio-test --`. The rewritten `studio-test` keeps that exact last line (B2).
9. **`studio-brief` changes directory to `studio-state root --work`** (:99) before any verb. `validate` captures `CALLER_PWD` first, so a relative plan path is the caller's (D12).
10. **`studio-gate`'s wait loop** (:199-204) loops until the child is dead, so the straggler KILL (:205-214) is unreachable while a TERM-ignoring child lives. The cap timer KILLs by itself after 10 s (D10).
11. **`held_line`** (:882-885) and `state_event` (:735) already split on the **last** ` until `. No change is needed; a test pins it (D8).
12. **A stall marker written after the claim** could be missed by a runner that loses the claim in between. It is staged as `.ended.stall` first, then moved inside the claim (D5).
13. **`cfg` accepts a leading zero** (`090`), and shell arithmetic then reads it as octal. `SESSION_MINUTES` and `IDLE_MINUTES` are normalized (D3).
14. **The spec's "`studio-test` misuse"** is not given an exit code. 2 would read as "no Godot" in execute (R3), so it is 4 (D11).
15. **`unit_activity`'s `closed[]` regex** `"tool_use_id":"…"` does not match `"parent_tool_use_id":"…"`, because the `_` before it is not a `"`. So a subagent's lines never close their parent `Agent` call. The fixture pins this (A2).
