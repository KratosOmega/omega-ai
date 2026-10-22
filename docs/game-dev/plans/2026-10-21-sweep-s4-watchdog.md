# S4 watchdog: tracked from birth, dies with its lane, anchored gate exemption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A unit watchdog or merge watchdog never outlives its lane. It never signals once its parent is
gone, and it is named in `lanes/K/wpid` from the moment it starts (#63 item 1, G6). The idle check's
gate exemption counts only a segment that *runs* `studio-test|run|setup|gate`, not any mention of one
(#63 item 2). Item 4 gets its pinning test. Item 5 is a note only.
**Architecture:** One helper block in O (`wd_init`, `wd_parent_ok`, `wd_check`, `wd_hook`, `wd_end`) serves
both watchdogs: run_unit's in O and `merge_wait`'s in L (L is loaded only by O on that path).
`lanes_end_sessions` keeps an inline TERM half, since T sources L alone to test it. The anchored
exemption is inline awk in `open_calls`: a quote-aware segment split, then a wrapper-skipping word scan.
**Tech Stack:** POSIX sh (dash-clean), awk, python3 where already used.
**Spec:** docs/game-dev/specs/2026-10-21-backlog-sweep.md §7
**Story branch:** `issue-63-watchdog` off integration/backlog-2026-10-21

**Base and story.** Umbrella #83, story #63. Branch off the integration head **after S2 merges** (spec §11
step 2), in parallel with S3 and S6. Worktree `/Users/xinli/GameDev/proj/omega-ai/.claude/worktrees/issue-63-watchdog`
(below: `$W`). Line numbers are as of 1cfca7f; S2 edits T and OT, so relocate every anchor with `grep -n`.

Paths: `O` = `studios/game-dev/bin/studio-overnight`, `L` = `studios/game-dev/bin/overnight-lanes.sh`,
`OT` = `tests/overnight_test.sh`, `T` = `tests/overnight_lanes_test.sh`.

**Run recipe** (every "Run" below). Use a scratch cwd outside every work tree, with an existing TMPDIR:

```sh
S=/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/5a98a755-7ca1-4ed6-b551-b3a3f4153b67/scratchpad/s4
mkdir -p "$S/tmp" && cd "$S" && export TMPDIR="$S/tmp"
TESTS_ONLY="<names>" sh "$W/tests/overnight_test.sh"     # then the same with: dash "$W/tests/overnight_test.sh"
```

OT and T are both in the dash set (run_all `TEST_SH=dash` runs every suite). Run each named-test check
under sh, then under dash.

## Global Constraints

- POSIX sh only, clean under dash: no bashisms, no `local`, no `$BASHPID`. Function variables carry a
  per-function prefix (`_wd_`, `_mw_`, `_es_`).
- awk runs under macOS one-true-awk: no `{n}` intervals. The `open_calls` program sits inside sh single
  quotes (O:1076-1131), so a single quote in the awk code is written `"\047"`, never `'`.
- A1: when no new config is set, the argv, report lines, status lines and endings are byte for byte as
  at cfe29ff. The watchdog's extra wake-ups and the narrower exemption are the G6/§7.2 intent. They
  have no visible output.
- Seams are whole seconds ≥ 1, else a preflight refusal: `STUDIO_OVERNIGHT_IDLE_POLL_SECONDS` (default
  30) caps the unit watchdog's nap, idle check on or off; `STUDIO_OVERNIGHT_WD_POLL_SECONDS` (default 30)
  caps `merge_wait`'s.
- Liveness rule (spec §7.1, item 3): the parent is alive iff `kill -0 $WD_PP0` succeeds **and**
  `ps -o ppid= -p $WD_ME` is empty or equals `WD_PP0`. A failed ps read counts as alive: the cap must not
  fail open.
- When the parent is gone, the watchdog exits 0 and signals nothing.
- After S2 the floors are exact. Every new test has an **unconditional** assertion count: fixed fixture
  rows, waits that always assert once (`wait_pid_or_fail`, `bg_end`), and no per-hit asserts.
- Hand-run suites use the recipe above. Never the full `run_all`, except where Task 5 says so. One
  background run per long suite, never stacked pollers.
- No phoenix change (A3). No reinstall.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HHd9n1KiKNE9YBptbSEgPL
  ```

## Review Focus

These are inputs or failure modes that the spec's acceptance list does not exercise. Each one is
pinned by a test added to the task named.

1. **A zombie parent.** A dead, unreaped parent still passes `kill -0`; only the ppid half catches it.
   T2 `test_lanes_merge_wait_watchdog_reparent` SIGSTOPs the runner so the killed lane stays a zombie;
   the T1 reparent tests SIGKILL the runner and reap it only afterwards.
2. **A stale `wpid` after a self-exit.** A watchdog leaving because its parent is gone must remove
   `LDIR/wpid` when the file names it, or the runner's next `lanes_end_sessions` could TERM a reused pid.
   T2 `test_lanes_merge_wait_watchdog_reparent` asserts `lanes/K/wpid` is missing after the self-exit.
3. **ps fails.** An empty `ppid` read keeps the cap ("the cap must not fail open"). T1
   `test_overnight_watchdog_ps_failure_keeps_cap`: a `ps` shim fails `-o ppid=` reads; the unit still
   ends `timed out`.
4. **Quotes and escapes in the exemption split:** `;` inside single quotes, an escaped `\"` inside double
   quotes, a JSON `\n` as a separator, `bash -c '…'` followed one level. T3 fixture rows N5, N6, E6, E7.
   A gate call inside `"$(…)"` or backticks is still a gate call; inside single quotes it is not
   (preflight fix). T3 fixture rows E10-E12, N8.
5. **The `val()` newline decode leaves list/denied output unchanged.** T3
   `test_overnight_idle_exemption_anchored` asserts `activity --open` prints a multi-line command as one
   line; `test_overnight_open_calls` and `test_overnight_denied_scan` stay green unchanged.

## Tasks

| # | Task | Kind |
|---|---|---|
| 1 | Watchdog helpers and run_unit's watchdog (O) | **Risky** (watchdog, process lifecycle) |
| 2 | `merge_wait` watchdog and the `lanes_end_sessions` TERM half (L) | **Risky** (watchdog, cross-file seam) |
| 3 | Anchored gate exemption in `open_calls` | **Risky** (parser on the stall path) |
| 4 | Item 4 pin: dead or reused gate registration | Mechanical |
| 5 | Rebase, affected suites, floors | Mechanical |

Order: 1 → 2 (2 uses 1's helpers), then 3 → 4. Tasks 3 and 4 share OT, so they run one after the other.
5 comes last. Item 5 (#63) has no task: there is no code, and the controller posts the closing comment
in spec §10.

---

### Task 1: Watchdog helpers and run_unit's watchdog — Risky

**Files:** O help (O:496-499), a new helper block above `start_session` (O:1307), the run_unit watchdog
(O:1365-1404), the teardown (O:1415) and `end_session` (O:1542). OT: `test_overnight_help` (OT:287-294),
new tests after OT:2557, exclusive-scan lines (OT:2633-2655), `run_tests` (OT:2671-). T: a new test
after `test_lanes_lane_kill9` (T:1157-1189), its exclusive-scan line, `run_tests` (T:4871-).

**Interfaces:**
- Consumes `LDIR` (empty in single-plan, O:27), `GRACE` and `_poll` (O:1362).
- Produces in O. All of them run inside a watchdog subshell, except `wd_end`:
  `wd_init` (sets `WD_ME`, `WD_PP0`; under a lane writes `LDIR/wpid` atomically; runs `wd_hook start`),
  `wd_parent_ok` (0 alive, 1 gone), `wd_check` (returns if alive, else drops its own `LDIR/wpid` and
  `exit 0`), `wd_hook AT` (evals `STUDIO_OVERNIGHT_WD_HOOK` with `_wd_at` = `start` | `deadline`), and
  `wd_end PID` (in the parent: `kill -TERM`, `pkill -TERM -P`, `wait`; empty PID is a no-op).
- Produces two test seams, in help: `STUDIO_OVERNIGHT_WD_HOOK` (eval'd in the watchdog at `start` and
  `deadline`; sees `_wd_at`, `WD_ME`, `WD_PP0`) and `STUDIO_OVERNIGHT_WPID_HOOK` (eval'd in run_unit after
  the fork, before the parent's `LDIR/wpid` write).

**Helpers (full code: the liveness logic):**

```sh
# ---- Watchdog liveness (#63) ----
# Both watchdogs (run_unit's, merge_wait's) are `( … ) &` subshells. `$$` there is the runner's,
# and under a lane the parent is the lane (L:2058), not `$$` (F23). So a watchdog records its own pid and
# its birth parent, and stops the moment that parent is gone: dead, or a zombie it was reparented away
# from (kill -0 still succeeds on a zombie, so the ppid half decides).
wd_init() {
  WD_ME="$(exec sh -c 'echo $PPID')"    # this subshell's pid (no $BASHPID in sh)
  WD_PP0="$(ps -o ppid= -p "${WD_ME:-0}" 2>/dev/null | tr -d ' ')"
  if [ -n "${LDIR:-}" ] && [ -n "$WD_ME" ]; then
    printf '%s\n' "$WD_ME" > "$LDIR/wpid.$WD_ME" 2>/dev/null && mv -f "$LDIR/wpid.$WD_ME" "$LDIR/wpid" 2>/dev/null
  fi
  wd_hook start
}
wd_parent_ok() {
  [ -n "${WD_PP0:-}" ] || return 0               # no birth read: stay (the cap must not fail open)
  [ "$WD_PP0" != 1 ] || return 1                 # born after its parent died
  kill -0 "$WD_PP0" 2>/dev/null || return 1
  _wd_pp="$(ps -o ppid= -p "${WD_ME:-0}" 2>/dev/null | tr -d ' ')"
  [ -z "$_wd_pp" ] || [ "$_wd_pp" = "$WD_PP0" ]
}
wd_check() {
  wd_parent_ok && return 0
  [ -z "${LDIR:-}" ] || [ "$(cat "$LDIR/wpid" 2>/dev/null)" != "$WD_ME" ] || rm -f "$LDIR/wpid"
  exit 0
}
wd_hook() { [ -z "${STUDIO_OVERNIGHT_WD_HOOK:-}" ] || { _wd_at="$1"; eval "$STUDIO_OVERNIGHT_WD_HOOK"; }; }
wd_end() {
  [ -n "${1:-}" ] || return 0
  kill -TERM "$1" 2>/dev/null; pkill -TERM -P "$1" 2>/dev/null; wait "$1" 2>/dev/null
}
```

`pkill -P` in `wd_end` is safe: the pid is this shell's own unreaped child, so its number can't have been
reused before the `wait`.

**run_unit's watchdog body (full code: the order is the point):**

```sh
  ( _sp=; _why=; trap 'kill $_sp 2>/dev/null; exit 0' TERM
    _end=$(( $(date +%s) + _secs )); _sz=""; _quiet=$(date +%s)
    wd_init
    while :; do
      _left=$(( _end - $(date +%s) )); [ "$_left" -gt 0 ] || break
      _nap="$_left"; [ "$_nap" -le "$_poll" ] || _nap="$_poll"        # rule 5: idle on or off
      sleep "$_nap" & _sp=$!; wait "$_sp"; _sp=
      wd_check                                                       # rule 4: after every nap
      [ -n "$_idle" ] || continue
      # … O:1384-1393 unchanged (size, quiet, live_gates, open_calls gate, stall claim) …
    done
    wd_hook deadline
    [ "$_why" = stall ] || mkdir "$_claim" 2>/dev/null || [ ! -d "$_claim" ] || exit 0
    wd_check                                                         # rule 4: before TERM
    kill -TERM -"$CPID" 2>/dev/null || { pkill -TERM -P "$CPID"; kill -TERM "$CPID"; }
    sleep "$GRACE" & _sp=$!; wait "$_sp"
    wd_check                                                         # rule 4: before KILL
    kill -KILL -"$CPID" 2>/dev/null || { pkill -KILL -P "$CPID"; kill -KILL "$CPID"; }
  ) > /dev/null 2>&1 &
  WPID=$!
  [ -z "${STUDIO_OVERNIGHT_WPID_HOOK:-}" ] || eval "$STUDIO_OVERNIGHT_WPID_HOOK"
  [ -z "${LDIR:-}" ] || printf '%s\n' "$WPID" > "$LDIR/wpid"        # same pid as the self-write: no conflict
```

- The teardown at O:1415 becomes `wd_end "$WPID"`. O:1416's `rm -f "$LDIR/wpid"` stays after it, and it
  runs only once the watchdog is reaped, so no self-write can follow it.
- `end_session` at O:1542 becomes `wd_end "${WPID:-}"`.
- Comment block O:1365-1376: naps ≤ `_poll` idle on or off, checks its parent after each nap and before
  each signal, names itself in `LDIR/wpid`. Drop "With the idle check off … it naps once, to the deadline."
- Help (O:498-499): `STUDIO_OVERNIGHT_IDLE_POLL_SECONDS — test hook: whole seconds between the unit
  watchdog's checks (default 30), idle check on or off`; add `STUDIO_OVERNIGHT_WD_HOOK — test hook: shell
  text the watchdogs evaluate at start and at their deadline` and `STUDIO_OVERNIGHT_WPID_HOOK — test hook:
  shell text evaluated before the runner writes a lane's wpid`.

**Test fixtures (OT, new, near the idle helpers OT:2479-2488).**

`wd_hook_on` writes `$TMP/wd-hook.sh` (quoted heredoc), sets `STUDIO_OVERNIGHT_WD_HOOK=". '$TMP/wd-hook.sh'"`,
`WD_TEST_LOG="$CALLS/wd.log"` and `WD_TEST_KILL=${1:-0}`, and exports them. `wd_hook_off` unsets all
three. The file is:

```sh
printf '%s %s %s\n' "$_wd_at" "$WD_ME" "$WD_PP0" >> "$WD_TEST_LOG"
if [ "$_wd_at" = deadline ] && [ "${WD_TEST_KILL:-0}" = 1 ]; then
  kill -9 "$WD_PP0"; _h=0
  while [ "$(ps -o ppid= -p "$WD_ME" | tr -d ' ')" = "$WD_PP0" ] && [ "$_h" -lt 100 ]; do sleep 0.1; _h=$((_h + 1)); done
fi
```

`wd_reparent_case NAME CONFIG` is shared by two tests, with the same asserts each time:

```sh
wd_reparent_case() {
  fixture "$1" "$2"; scenario "hang"; wd_hook_on 0
  STUDIO_OVERNIGHT_SESSION_SECONDS=30; STUDIO_OVERNIGHT_IDLE_POLL_SECONDS=1
  export STUDIO_OVERNIGHT_SESSION_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS
  start_bg; unset STUDIO_OVERNIGHT_SESSION_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS; wd_hook_off
  wait_for "$CALLS/wd.log"
  _w="$(awk '$1 == "start" { print $2; exit }' "$CALLS/wd.log" 2>/dev/null)"
  assert_eq "$RPID" "$(awk '$1 == "start" { print $3; exit }' "$CALLS/wd.log" 2>/dev/null)" "$1: the watchdog's birth parent is the runner"
  kill -9 "$RPID"                    # not reaped yet: a zombie parent (Review Focus 1)
  _i=0; while kill -0 "${_w:-999999}" 2>/dev/null && [ "$_i" -lt 300 ]; do sleep 0.2; _i=$((_i + 1)); done   # 60 s hang guard
  assert_status 1 "$1: the reparented watchdog exits on its next poll" -- kill -0 "${_w:-999999}"
  assert_not_contains "$CALLS/wd.log" "^deadline" "$1: it never reached its deadline"
  _s="$(cat "$CALLS/1.pid" 2>/dev/null)"
  assert_status 0 "$1: it signalled nothing (the session still runs)" -- kill -0 "${_s:-999999}"
  kill -9 -"${_s:-999999}" "${_s:-999999}" 2>/dev/null; bg_status
}
```

- [ ] **Step 1: Write the failing tests.**
  - `test_overnight_watchdog_exits_when_reparented`:
    `wd_reparent_case wdrep '{ "overnight": { "retries": 0 } }'`.
  - `test_overnight_watchdog_idle_off_still_polls`:
    `wd_reparent_case wdoff '{ "overnight": { "retries": 0, "idle_minutes": 0 } }'`. At baseline the
    watchdog naps once to the 30 s deadline, so it is alive at the guard. (There is no hook at baseline
    either, so both tests fail at the `wd.log` wait.)
  - `test_overnight_watchdog_rechecks_before_kill`:
    ```sh
    fixture wdrck '{ "overnight": { "retries": 0 } }'; scenario "hang"; wd_hook_on 1
    STUDIO_OVERNIGHT_SESSION_SECONDS=3; STUDIO_OVERNIGHT_IDLE_POLL_SECONDS=1; export …
    start_bg; unset …; wd_hook_off
    _i=0; while ! grep -q '^deadline' "$CALLS/wd.log" 2>/dev/null && [ "$_i" -lt 300 ]; do sleep 0.2; _i=$((_i + 1)); done
    assert_contains "$CALLS/wd.log" "^deadline " "the watchdog reached its deadline"
    _w="$(awk '$1 == "start" { print $2; exit }' "$CALLS/wd.log")"
    _i=0; while kill -0 "${_w:-999999}" 2>/dev/null && [ "$_i" -lt 300 ]; do sleep 0.2; _i=$((_i + 1)); done
    assert_status 1 "and exited" -- kill -0 "${_w:-999999}"
    _s="$(cat "$CALLS/1.pid" 2>/dev/null)"
    assert_status 0 "the parent died at the deadline, so no TERM was sent" -- kill -0 "${_s:-999999}"
    kill -9 -"${_s:-999999}" "${_s:-999999}" 2>/dev/null; bg_status
    ```
  - `test_overnight_teardown_ends_nap`: `fixture wdnap '{ "overnight": { "retries": 0 } }'`, `scenario
    "cost 1"`, `STUDIO_OVERNIGHT_IDLE_POLL_SECONDS=600`, `start_bg`, then `bg_end 120 "a unit that ends
    with a 600 s watchdog nap pending: the teardown never waits it out"` and `assert_eq 1 "$(calls)" "one
    unit ran"`. A **regression pin**: it passes at baseline (the TERM trap ends the sleep) and must stay
    green once `wd_init`'s forks and `wd_end` land.
  - `test_overnight_watchdog_ps_failure_keeps_cap` (Review Focus 3): `$TMP/psfail/ps` is `#!/bin/sh` +
    `case "$*" in *ppid=*) exit 1 ;; esac` + `exec /bin/ps "$@"`; `fixture wdps '{ "overnight": {
    "retries": 0 } }'`, `scenario "stage execute; hang"`, `STUDIO_OVERNIGHT_SESSION_SECONDS=3`; `_op="$PATH";
    PATH="$TMP/psfail:$PATH"; run_start; PATH="$_op"`; then `assert_eq "timed out" "$(awk -F'\t' 'NR == 1
    { print $7 }' "$(last_run_dir)/units.tsv")" "ps failing: the watchdog stays, the cap still ends it"`.
  - `test_overnight_help`: add `"STUDIO_OVERNIGHT_WD_HOOK — test hook"` and `"STUDIO_OVERNIGHT_WPID_HOOK
    — test hook"` to the OT:287-294 list.
  - T `test_lanes_watchdog_writes_own_wpid`. This replaces the spec's OT name: see Falsified
    assumption 2.
    ```sh
    lanes_fixture ownwpid integration A:-
    cat > "$TMP/wpid-hook.sh" <<EOF
    [ "\${CUR_ID:-}" = A ] && [ ! -e '$CALLS/wpid-go' ] || return 0
    : > '$CALLS/wpid-held'; _h=0
    while [ ! -e '$CALLS/wpid-go' ] && [ "\$_h" -lt 300 ]; do sleep 0.2; _h=\$((_h + 1)); done
    EOF
    STUDIO_OVERNIGHT_WPID_HOOK=". '$TMP/wpid-hook.sh'"; export STUDIO_OVERNIGHT_WPID_HOOK
    ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > "$TMP/ow.out" 2>&1 & RPID=$!
    unset STUDIO_OVERNIGHT_WPID_HOOK
    wait_for '[ -e "$CALLS/wpid-held" ]' 60
    R="$(last_lanes_dir)"; _k="$(cat "$R/claims/1/lane" 2>/dev/null)"; _lp="$(cat "$R/claims/1/pid" 2>/dev/null)"
    wait_for '[ -s "$R/lanes/${_k:-0}/wpid" ]' 30
    _w="$(cat "$R/lanes/${_k:-0}/wpid" 2>/dev/null)"
    assert_eq "${_lp:-none}" "$(ps -o ppid= -p "${_w:-999999}" 2>/dev/null | tr -d ' ')" "with the runner's own write held, lanes/K/wpid already names the lane's watchdog"
    : > "$CALLS/wpid-go"
    wait_pid_or_fail "$RPID" 120 "the run ends once the write is released"
    assert_contains "$R/stories/A" "^landed " "the story lands"
    assert_missing "$R/lanes/${_k:-0}/wpid" "the reaped watchdog's wpid is removed"
    assert_eq 0 "$(ls "$R/lanes/${_k:-0}"/wpid.* 2>/dev/null | wc -l | tr -d ' ')" "no wpid.<pid> temp file is left"
    ```
  - Add exclusive-scan lines, all `out (d)`, with the reason "event waits only; the guards assert no
    speed": the five OT tests and the T test. `teardown_ends_nap` reads `out (d)` with "the 120 s guard
    is a hang guard, not a speed bound".
- [ ] **Step 2: Run them, expect FAIL.** OT: `TESTS_ONLY="test_overnight_watchdog_exits_when_reparented
  test_overnight_watchdog_idle_off_still_polls test_overnight_watchdog_rechecks_before_kill
  test_overnight_teardown_ends_nap test_overnight_watchdog_ps_failure_keeps_cap test_overnight_help"`;
  T: `TESTS_ONLY="test_lanes_watchdog_writes_own_wpid"`. FAIL: reparented, idle_off, rechecks (no
  `wd.log`), the help names, writes_own_wpid (no wpid while held). PASS: the two pins.
- [ ] **Step 3: Implement** the helpers, the watchdog body, the WPID hook, `wd_end` at O:1415 and O:1542,
  the comment and the help.
- [ ] **Step 4: Run them, expect PASS** under sh and dash, with the neighbours: OT
  `test_overnight_timeout test_overnight_kill_after_grace test_overnight_idle_stall
  test_overnight_idle_spares_gate_call test_overnight_idle_off_and_refusals test_overnight_idle_default_seams
  test_overnight_sighup`; T `test_lanes_lane_kill9 test_lanes_end_sessions_spaced_path`.
- [ ] **Step 5: Commit** `fix(overnight): unit watchdog tracks itself from birth and dies with its parent (#63)`.

---

### Task 2: `merge_wait` watchdog and the `lanes_end_sessions` TERM half — Risky

**Files:** L `merge_wait` (L:561-595) and `lanes_end_sessions` (L:1172-1196), comments and bodies. O help
(next to IDLE_POLL) and the preflight seam loop (O:674). OT `test_overnight_help` (OT:287-294) and
`test_overnight_idle_off_and_refusals` (OT:2530-2542). T: a new test after
`test_lanes_direct_merge_timeout_term_ignored` (T:2040-2052), its exclusive-scan line, `run_tests`.

**Interfaces:** Consumes `wd_init`, `wd_check`, `wd_hook`, `wd_end` (Task 1), `LDIR`, `GRACE`,
`SESSION_MINUTES`. Produces the seam `STUDIO_OVERNIGHT_WD_POLL_SECONDS` (default 30); a bad value is
refused with `STUDIO_OVERNIGHT_WD_POLL_SECONDS must be a whole number of seconds (1 or more), got <v>`.

**merge_wait body (full code):**

```sh
  _mw_poll="${STUDIO_OVERNIGHT_WD_POLL_SECONDS:-30}"
  ( _sp=; trap 'kill $_sp 2>/dev/null; exit 0' TERM
    _mw_end=$(( $(date +%s) + _mw_secs ))
    wd_init
    while _mw_left=$(( _mw_end - $(date +%s) )); [ "$_mw_left" -gt 0 ]; do
      [ "$_mw_left" -le "$_mw_poll" ] || _mw_left="$_mw_poll"
      sleep "$_mw_left" & _sp=$!; wait "$_sp"; _sp=
      wd_check
    done
    wd_hook deadline
    mkdir "$_mw_claim" 2>/dev/null || [ ! -d "$_mw_claim" ] || exit 0
    wd_check
    kill -TERM -"$2" 2>/dev/null || { pkill -TERM -P "$2"; kill -TERM "$2"; }
    sleep "${GRACE:-30}" & _sp=$!; wait "$_sp"
    wd_check
    for _k in $(pgrep -P "$2"); do kill -KILL -"$_k" 2>/dev/null; done
    kill -KILL -"$2" 2>/dev/null || { pkill -KILL -P "$2"; kill -KILL "$2"; }
  ) > /dev/null 2>&1 &
```

- The parent's `wpid` write (L:583) stays.
- L:591 `kill "$_mw_w"; wait "$_mw_w"` becomes `wd_end "$_mw_w"`.
- In `lanes_end_sessions`, L:1194 `kill "$_es_w"` becomes `{ kill -TERM "$_es_w"; pkill -TERM -P "$_es_w"; } 2>/dev/null`.
  This is the TERM half only: the watchdog is not this shell's child, so there is no `wait`. It stays
  inline (no `wd_end`), because T:1193-1214 sources L alone and calls it.
- Update the comments at L:561-569 and L:1172-1184: naps ≤ 30 s, a parent check, a self-named wpid, and
  "ends its sleep child too".
- Help: `STUDIO_OVERNIGHT_WD_POLL_SECONDS — test hook: whole seconds between the merge watchdog's checks
  (default 30)`.
- O:674: the loop becomes `for _pf_v in STUDIO_OVERNIGHT_IDLE_SECONDS STUDIO_OVERNIGHT_IDLE_POLL_SECONDS
  STUDIO_OVERNIGHT_WD_POLL_SECONDS; do`.

- [ ] **Step 1: Write the failing tests.**
  - T `test_lanes_merge_wait_watchdog_reparent` (Review Focus 1 and 2):
    ```sh
    LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
    lanes_fixture mwrep direct A:-
    MERGE_OUTCOMES=hang; STUDIO_OVERNIGHT_SESSION_SECONDS=600; STUDIO_OVERNIGHT_WD_POLL_SECONDS=1
    export MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS STUDIO_OVERNIGHT_WD_POLL_SECONDS
    ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > "$TMP/mw.out" 2>&1 & RPID=$!
    unset MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS STUDIO_OVERNIGHT_WD_POLL_SECONDS
    wait_for '[ -s "$CALLS/merge.pid" ]' 60
    R="$(last_lanes_dir)"; _k="$(cat "$R/claims/1/lane" 2>/dev/null)"; _lp="$(cat "$R/claims/1/pid" 2>/dev/null)"
    wait_for '[ -s "$R/lanes/${_k:-0}/wpid" ]' 30; _w="$(cat "$R/lanes/${_k:-0}/wpid" 2>/dev/null)"
    assert_eq "${_lp:-none}" "$(ps -o ppid= -p "${_w:-999999}" 2>/dev/null | tr -d ' ')" "the merge watchdog is the lane's child"
    kill -STOP "$RPID"                # the runner can neither sweep nor reap: the lane stays a zombie
    kill -9 "${_lp:-999999}"
    wait_for '! pid_alive "${_w:-999999}"' 60
    assert_status 1 "the merge watchdog of a dead lane exits on its own" -- pid_alive "${_w:-999999}"
    assert_missing "$R/lanes/${_k:-0}/wpid" "and removes the wpid that names it"
    kill -CONT "$RPID"
    wait_pid_or_fail "$RPID" 120 "the run ends after the lane's death"
    assert_contains "$R/stories/A" "^stopped: lane crashed (137)$" "the story records the crash"
    kill -9 "$(cat "$CALLS/merge.pid" 2>/dev/null)" "$(cat "$CALLS/merge-sleep.pid" 2>/dev/null)" 2>/dev/null
    unset LANES_CONFIG
    ```
    At baseline the watchdog sleeps its 600 s in one nap, so it is alive at the 60 s guard.
  - OT `test_overnight_idle_off_and_refusals`: append `fixture wdpoll;
    STUDIO_OVERNIGHT_WD_POLL_SECONDS=0; export …; refuse_case "zero merge poll seam"
    "STUDIO_OVERNIGHT_WD_POLL_SECONDS must be a whole number"; unset …`.
  - OT `test_overnight_help`: add `"STUDIO_OVERNIGHT_WD_POLL_SECONDS — test hook"`.
  - Add a T exclusive-scan line: `out (d) event waits on the merge pid, the wpid and the watchdog's exit;
    no speed bound`.
- [ ] **Step 2: Run, expect FAIL.** T `TESTS_ONLY="test_lanes_merge_wait_watchdog_reparent"`; OT
  `TESTS_ONLY="test_overnight_idle_off_and_refusals test_overnight_help"`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS** under sh and dash, with T neighbours `test_lanes_direct_merge_timeout
  test_lanes_direct_merge_timeout_term_ignored test_lanes_lane_kill9 test_lanes_end_sessions_spaced_path`
  (the 6 s merge timeouts nap 6 s in one go and keep their ending).
- [ ] **Step 5: Commit** `fix(overnight): merge watchdog polls its lane; lane teardown ends the watchdog's sleep (#63)`.

---

### Task 3: Anchored gate exemption in `open_calls` — Risky

**Files:** O `val()` (O:1077-1083), the gate rule (O:1128), the comment (O:1068-1069). Create
`tests/fixtures/overnight-open-gate.jsonl`. OT: a new test after `test_overnight_open_calls`
(OT:2405-2433), its exclusive-scan line, `run_tests`.

**Interfaces:** Consumes `cfull[i]`, the full Bash command (O:1112, O:1118). Produces awk `gate_cmd(s, d)`,
`gate_seg(s, d)`, `words(s, w)`, `unq(x)`, `sub_end(s, i)` (preflight fix); gate mode prints `gate` iff `gate_cmd(cfull[i], 0)`. CLI
unchanged: `studio-overnight activity --open-gate FILE`.

**`val()`.** Decode `\n` → `"\n"` and `\t` → `"\t"` (today it decodes both to a space). Every print path
already flattens `[\t\r\n]` (O:1123, O:1129), so the list and denied output is unchanged (Review Focus 5).
The newline must survive into `cfull` so that `gate_cmd` can split on it.

**The parser (full code; inside the existing single-quoted program, so `"\047"` is a single quote):**

```awk
    # unq(X): X with its quotes and backslashes removed (the word as the shell would run it).
    function unq(x) { gsub(/["\047\\]/, "", x); return x }
    # words(S, W): S split into W[1..n] at blanks outside quotes (quotes kept); returns n.
    function words(s, w,   n, i, c, q, cur, inw) {
      n = 0; q = ""; cur = ""; inw = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q == "" && (c == " " || c == "\t")) { if (inw) { w[++n] = cur; cur = ""; inw = 0 }; continue }
        inw = 1; cur = cur c
        if (q == "") { if (c == "\047" || c == "\"") q = c; else if (c == "\\") cur = cur substr(s, ++i, 1) }
        else if (c == q) q = ""
        else if (q == "\"" && c == "\\") cur = cur substr(s, ++i, 1)
      }
      if (inw) w[++n] = cur
      return n
    }
    # sub_end(S, I): the index of the ) or backtick that closes the substitution opening at I ($( or a backtick).
    function sub_end(s, i,   n, k, c, dp, q) {
      n = length(s)
      if (substr(s, i, 1) == "`") {
        for (k = i + 1; k <= n; k++) { c = substr(s, k, 1); if (c == "\\") k++; else if (c == "`") return k }
        return n }
      dp = 1; q = ""
      for (k = i + 2; k <= n; k++) {
        c = substr(s, k, 1)
        if (q != "") { if (c == q) q = ""; else if (q == "\"" && c == "\\") k++; continue }
        if (c == "\\") { k++; continue }
        if (c == "\047" || c == "\"") { q = c; continue }
        if (c == "(") dp++
        else if (c == ")" && --dp == 0) return k
      }
      return n
    }
    # gate_cmd(S, D): 1 when a segment of S (split outside quotes at ; & | ( ) and newline) runs a gate verb.
    # A command substitution, $(...) or backticks, bare or inside double quotes, runs its body: the body
    # is followed one level down (D < 3) and stands as one plain word in the outer segment.
    function gate_cmd(s, d,   i, c, q, seg, j, o) {
      q = ""; seg = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "\047" && (c == "`" || (c == "$" && substr(s, i + 1, 1) == "("))) {
          o = (c == "`") ? 1 : 2; j = sub_end(s, i)
          if (d < 3 && gate_cmd(substr(s, i + o, j - i - o), d + 1)) return 1
          seg = seg "S"; i = j; continue }
        if (q != "") { seg = seg c; if (c == q) q = ""; else if (q == "\"" && c == "\\") seg = seg substr(s, ++i, 1); continue }
        if (c == "\\") { seg = seg c substr(s, ++i, 1); continue }
        if (c == "\047" || c == "\"") { q = c; seg = seg c; continue }
        if (index(";&|()\n", c)) { if (gate_seg(seg, d)) return 1; seg = ""; continue }
        seg = seg c
      }
      return gate_seg(seg, d)
    }
    # gate_seg(S, D): skip NAME=value words and the wrappers, then one shell with its options
    # (following `-c STR` one level down, D < 3); exempt iff the basename of the next word is a gate verb.
    function gate_seg(s, d,   w, n, i, b) {
      n = words(s, w); i = 1
      while (i <= n) {
        b = unq(w[i]); sub(/.*\//, "", b)
        if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || b == "exec" || b == "command" || b == "nohup") { i++; continue }
        if (b == "time") { i++; if (w[i] == "-p") i++; continue }
        if (b == "env") { i++
          while (i <= n && (w[i] ~ /^-/ || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) { if (w[i] ~ /^-[uCS]$/) i++; i++ }
          continue }
        if (b == "nice") { i++; if (w[i] == "-n") i += 2; else if (w[i] ~ /^-n?[0-9]+$/) i++; continue }
        if (b == "timeout" || b == "gtimeout") { i++
          while (i <= n && w[i] ~ /^-/) { if (w[i] ~ /^-[sk]$/) i++; i++ }
          i++; continue }
        break
      }
      if (i > n) return 0
      b = unq(w[i]); sub(/.*\//, "", b)
      if (b ~ /^(sh|bash|dash|zsh)$/) {
        for (i++; i <= n && w[i] ~ /^[-+]/; i++) {
          if (w[i] ~ /^[-+]o$/) { i++; continue }
          if (w[i] ~ /^-[A-Za-z]*c[A-Za-z]*$/) return (i < n && d < 3) ? gate_cmd(unq(w[i + 1]), d + 1) : 0
        }
        if (i > n) return 0
        b = unq(w[i]); sub(/.*\//, "", b)
      }
      return b ~ /^studio-(test|run|setup|gate)$/
    }
```

`unq` in a `-c` body strips the inner quotes along with the outer ones. That is accepted: the inner
split then sees plain words, which is enough for the exemption.

Preflight fixes:
- **No apostrophe in any comment of this block.** It sits inside open_calls' single-quoted awk
  program, so an apostrophe ends the quote and breaks O. Write `"\047"` in code, and reword prose
  ("the basename of the next word", not the possessive).
- **A gate call in a command substitution is still a gate call.** Without `sub_end`, the anchored
  rule misses `x="$(studio-test …)"` and backtick forms (bare `x=$(studio-test)` was caught only by
  the `(` split). S3's guard follows those forms, so a unit that captures the gate's output in a
  variable would be stall-killed. Rows E10-E12 and N8 pin the rule. A scratch probe of this code at
  09ff62a gives the expected verdict on all 20 rows.

**Fixture `tests/fixtures/overnight-open-gate.jsonl`:** one open Bash `tool_use` per line, in the existing
fixture's shape (`{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_<X>","name":"Bash","input":{"command":"<JSON-escaped>"}}]}}`);
id `toolu_E<n>` = exempt, `toolu_N<n>` = not. The 20 rows (E10-E12 and N8: preflight fix):

| id | command (shell text, before JSON escaping) |
|---|---|
| E1 | `cd d && studio-test` |
| E2 | `sh /x/bin/studio-gate t -- godot --headless` |
| E3 | `"$S/studio-test" --file a.gd` |
| E4 | `env A=1 studio-run --seconds 10` |
| E5 | `timeout 600 studio-test` |
| E6 | `echo hi` *newline* `studio-test --file a.gd` (a JSON `\n`) |
| E7 | `bash -c 'cd d && studio-test'` |
| E8 | `(cd d; nice -n 5 /usr/bin/env -u X studio-setup gate) 2>&1 \| tail -n 5` |
| E9 | `X=1 exec studio-gate t -- sh -c true` |
| E10 | `x="$(studio-test --file a.gd)"` |
| E11 | ``x=`studio-test` `` |
| E12 | ``out="`cd d && studio-run --seconds 5`"; echo "$out"`` |
| N1 | `grep studio-test x` |
| N2 | `echo "run studio-test"` |
| N3 | `cat bin/studio-gate` |
| N4 | `vim studio-run` |
| N5 | `echo 'a; studio-test'` |
| N6 | `echo "x\" ; studio-test"` |
| N7 | `ls /x/studio-gate-old` |
| N8 | ``echo '$(studio-test) and `studio-test`'`` (single quotes: no substitution runs) |

- [ ] **Step 1: Write the failing test** `test_overnight_idle_exemption_anchored`:
  ```sh
  F="$REPO_ROOT/tests/fixtures/overnight-open-gate.jsonl"; _n=0
  while IFS= read -r _row; do
    _n=$((_n + 1))
    { printf '%s\n' '{"type":"system","subtype":"init"}'; printf '%s\n' "$_row"; } > "$TMP/og.jsonl"
    _want=""; case "$_row" in *'"id":"toolu_E'*) _want=gate ;; esac
    _id="$(printf '%s' "$_row" | sed 's/.*"id":"toolu_\([EN][0-9]*\)".*/\1/')"
    assert_eq "$_want" "$(sh "$RUNNER" activity --open-gate "$TMP/og.jsonl")" "row $_id: $( [ -n "$_want" ] && echo exempt || echo 'not exempt')"
  done < "$F"
  assert_eq 20 "$_n" "every fixture row ran"
  grep '"toolu_E6"' "$F" | { printf '%s\n' '{"type":"system","subtype":"init"}'; cat; } > "$TMP/og-nl.jsonl"
  assert_eq 1 "$(sh "$RUNNER" activity --open "$TMP/og-nl.jsonl" | grep -c .)" "a multi-line command still lists as one flattened line"
  ```
  This is a fixed 22 assertions (20 rows plus 2; preflight fix). Add an exclusive-scan line: `out (b) a pure parser over fixture rows;
  no process timing`.
- [ ] **Step 2: Run, expect FAIL.** `TESTS_ONLY="test_overnight_idle_exemption_anchored"` on OT. N1-N8 fail
  at baseline, because the substring rule matches them.
- [ ] **Step 3: Implement.** Change `val()`, add the five functions before `gone()`, and make the O:1128
  gate rule `if (gate_cmd(cfull[i], 0)) …`. Update the comment at O:1068-1069 to "runs a gate-routed verb
  (an anchored command word, spec §7.2)".
- [ ] **Step 4: Run, expect PASS** under sh and dash. Run with it `test_overnight_open_calls`,
  `test_overnight_denied_scan`, `test_overnight_permission_route_ending`,
  `test_overnight_idle_spares_gate_call`, `test_overnight_idle_stall` and
  `test_overnight_stall_holds_with_until_command`.
- [ ] **Step 5: Commit** `fix(overnight): idle gate exemption counts only a command that runs a gate verb (#63)`.

---

### Task 4: Item 4 pin, a dead or reused gate registration — Mechanical

**Files:** OT only: the stub actions (OT:90-96, add `reusedgate`); `test_overnight_idle_spares_gate_call`
(OT:2507-2528, move its spare3 block OT:2522-2527 out); a new test after it, its exclusive-scan line,
`run_tests`.

**Interfaces:** Consumes `live_gates` (O:1204-1214, unchanged). Produces the stub action `reusedgate`:
`sleep 300 & echo "$!" > "$CALLS/reused.pid"; mkdir -p "$root/.studio/gate.units/$STUDIO_UNIT_TAG" && : >
"$root/.studio/gate.units/$STUDIO_UNIT_TAG/$!"` (a live pid whose `ps` args don't name `studio-gate`).

- [ ] **Step 1: Write the test** `test_overnight_idle_dead_gate_registration`. Move into it, verbatim,
  the spare3 case (dead pid, `stalegate`, asserting `stalled`). Then add:
  ```sh
  fixture spare4 '{ "overnight": { "retries": 0 } }'
  scenario "emit $TMP/plain.jsonl; reusedgate; hang"     # stall_log "$TMP/plain.jsonl" "sleep 999" first
  idle_on 3 1 12; run_start; idle_off
  assert_eq "stalled" "$(awk -F'\t' 'NR == 1 { print $7 }' "$(last_run_dir)/units.tsv")" "a registration whose pid now runs something other than studio-gate does not exempt it"
  kill -9 "$(cat "$CALLS/reused.pid" 2>/dev/null)" 2>/dev/null
  ```
  The new test calls `stall_log "$TMP/plain.jsonl" "sleep 999"` itself. The move is count-neutral, so
  OT rises by exactly 1. Exclusive-scan line: `out (d) the same idle 3 s / poll 1 s window as
  test_overnight_idle_spares_gate_call`.
- [ ] **Step 2: Run** `TESTS_ONLY="test_overnight_idle_dead_gate_registration test_overnight_idle_spares_gate_call"`.
  Expect PASS: this pins existing behaviour (spec §7.3), so there is no red phase. Also run under dash.
- [ ] **Step 3: Commit** `test(overnight): pin dead and reused gate registrations (#63 item 4)`.

---

### Task 5: Rebase, affected suites, floors — Mechanical

This task follows S2's "For other stories" recipe exactly (preflight fix).

- [ ] `git fetch`, then merge the latest `origin/integration/backlog-2026-10-21` into `issue-63-watchdog`. On a
  `tests/run_all.sh` floors-table conflict, take the integration branch's whole file
  (`git checkout origin/integration/backlog-2026-10-21 -- tests/run_all.sh`) and never hand-merge counts.
  Resolve the other shared regions per **Merge notes** below.
- [ ] Commit every code and test change. The tree must be clean before the runs.
- [ ] Get the suite list from `sh "$W/tests/run_affected.sh" --base origin/integration/backlog-2026-10-21
  --list`, using the run recipe's cwd. Expect `overnight_test` and `overnight_lanes_test`, plus every
  suite that the reverse-reference closure over O and L adds. Run those suites plus `harness_test` as one
  background run under sh, then one under dash: `TEST_SUITES="<list> harness_test" sh "$W/tests/run_all.sh"`,
  then the same with `TEST_SH=dash`. These partial runs never take the heavy-suite lock.
  - Red only with `floor` / `no floors row` lines is expected. Any other red: fix, commit, and re-run both.
- [ ] With no commit since the last run, `sh "$W/tests/run_all.sh" --update-floors`. Any commit after the
  run means a re-run first. Expected: an `overnight_test: <old> → <new>` line and an
  `overnight_lanes_test: <old> → <new>` line, and no other suite changes.
- [ ] Commit `test(floors): S4 overnight counts` (only `tests/run_all.sh`).

### Merge notes (preflight fix)

Shared regions with other stories, and how each merge resolves them:
- **O near :1077-1128.** S4 edits `val()`, inserts its functions before `gone()` and changes the :1128
  gate rule; S3 edits only the open_calls comment at :1091. Neither reflows the other's lines.
- **O :674 and run_unit :1365-1415** (S4) vs S5's :665 cfg and :1347. Disjoint; keep both.
- **`run_tests` lists and rulings tails** (OT, T). S1, S3 and S5 append here too. On a conflict, keep
  both sides; S4 adds its names on its own new continuation line.
- **`tests/run_all.sh` floors.** On a conflict, take the integration branch's `run_all.sh`, then redo
  this task from the commit step.
- **Order.** S4 builds in parallel with S6 and S3, merges after S6 and before S3, and S1 merges after S4
  (S2's build order).

---

## Falsified assumptions (planner falsify clause)

Each load-bearing assumption, checked against the code at 1cfca7f:

| # | Assumption | Verdict | Evidence / fix |
|---|---|---|---|
| 1 | `sleep 0 & _k=$!; ps -o ppid= -p $_k` reads the watchdog's own pid (spec §7.1 rule 1) | **false** | A probe printed `[]`: `sleep 0` exits and bash reaps it before ps reads. studio-gate uses `sleep 1` (studio-gate:413) for this reason. Fix: `$(exec sh -c 'echo $PPID')`. A probe under sh and dash printed the same pid as the sleep-child read (the L:1046/1050 idiom family) |
| 2 | `test_overnight_watchdog_writes_own_wpid` can live in OT | **false** | Single-plan runs force `LDIR=""` (O:27). OT:620-637 pins that an inherited LDIR gets no wpid. The test is T `test_lanes_watchdog_writes_own_wpid` |
| 3 | New exemption rows go into `tests/fixtures/overnight-open-calls.jsonl` | **false** | `test_overnight_open_calls` asserts exactly two open calls in it, and the newest row (OT:2409-2415). Fix: a new `overnight-open-gate.jsonl` |
| 4 | The dead-pid registration case has no test (#63 item 4 ruling) | **false** | OT:2522-2527 (spare3, "A2 minor 2") pins it. Task 4 moves it into the named test and adds the reused-pid half, so the test isn't duplicated |
| 5 | `cfull` keeps the command's newlines, so a split "at newlines" works | **false** | `val()` turns `\n`/`\t` into spaces (O:1081). Fix: decode them to real characters. List and denied re-flatten at O:1123 and O:1129 |
| 6 | Only run_unit's teardown does `kill "$WPID"` | **false** | `end_session` O:1542 does too. Both become `wd_end` |
| 7 | `merge_wait` runs only with O loaded (so it can call O's helpers) | true | Its only caller is `land_once_direct` (L:640). T's sourced-L tests call `land_once` (T:1446) and `lanes_end_sessions` (T:1196-1207), never `merge_wait` |
| 8 | `lanes_end_sessions` may call `wd_end` | **false** | T:1193-1214 sources L alone, and the watchdog is not its child (no `wait`). The TERM half is inline |
| 9 | The parent's `rm -f LDIR/wpid` follows the watchdog's reap | true | O:1415-1416 (wait, then rm). L:998 `lane_exit` rm comes after `end_session`'s wait (O:1542) |
| 10 | A zombie parent passes `kill -0` | true | studio-gate:399-401. That is why the ppid half exists, and why T2 uses SIGSTOP |
| 11 | run_unit runs in the lane's own process, so its watchdog's parent is `claims/<c>/pid` | true | `run_chain` is called directly at L:1052. `story_units`/`run_unit` are called directly at O:1608, L:673/730/828/1692. The pid comes from `sh -c 'echo $PPID'` at L:1050 |
| 12 | `live_gates` needs a live pid whose args contain `studio-gate` | true | O:1204-1214 |
| 13 | The IDLE_POLL seam is validated ≥ 1 in the shared preflight | true | O:674-678 (one loop. WD_POLL joins it) |
| 14 | The idle check off means the watchdog naps to the deadline | true | O:1381. `merge_wait` always does (L:575) |
| 15 | The help test pins seam names by `assert_contains` | true | OT:287-296 |
| 16 | `wait_for` has the same signature in OT and T | **false** | OT:754 is `wait_for FILE` (60 s). T:1075-1078 is `wait_for EXPR SECS`. Each test uses its own suite's form |
| 17 | Recursive awk functions with local arrays work in macOS awk | true | A probe `f(3)` with a local array returned 3 |
| 18 | The `open_calls` gate mode is reachable from tests via the CLI | true | `activity --open-gate FILE` (OT:2415) |
| 19 | The T merge stub records `merge.pid`/`merge-sleep.pid` for `hang` | true | T:510 |

## Manual acceptance

One live check, folded into the next human-driven overnight run (#6's whole-studio smoke test), after the
operator reinstalls: SIGKILL one lane of a manifest run mid-unit; within 30 s `ps -o pid,ppid,args` shows
no reparented watchdog subshell for it, and the run reports `stopped: lane crashed (137)` for its story.
Nothing else needs a person.
