# Preflight `worktree_setup` Before Start — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `studio-overnight start` (plain, manifest, and `--detach`) runs `worktree_setup` once in a scratch linked worktree before anything launches, and refuses to start when it fails.

**Architecture:** One helper family in `studio-overnight` (`setup_preflight BRANCH`, `sp_remove`, `sp_sweep`, `sp_interrupt`) adds a detached linked worktree at `origin/<BRANCH>` under `$STATE_ROOT/.claude/worktrees/setup-preflight-<pid>`. It runs the real `studio-setup` there (so the gate lock, timeout, log and marker are the runner's own), copies the log out to `.studio/reports/setup-preflight-<stamp>.log` on failure, and removes the worktree on every path. The single-plan start calls it with the default branch; `lanes_start` calls it with the manifest's Target. `--detach` runs it in the foreground through a new internal `lanes_start --check` mode and hands the checked commit to the child, which skips a second run.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2, Linux `dash`), git ≥ 2.38. No new dependencies.

**Spec:** `docs/game-dev/specs/2026-10-05-setup-preflight.md` (R1–R5).

Story: #49 (GitHub issue). Branch `49-preflight-worktree-setup` (omega-ai has no Jira). **Base:** 81691ab (origin/main). Line numbers are at that commit; relocate each with its `grep -n`.

## Global Constraints

- POSIX sh only; must run under macOS `/bin/sh` (bash 3.2) and `dash`.
- The scratch worktree is a *linked* worktree (`git worktree add`), never the main checkout.
- It goes through `studio-setup` (same gate lock, same `worktree_setup_minutes` timeout). No second implementation of the setup run.
- Unset `worktree_setup`: no output, no worktree, no fetch.
- Refusals exit 2 (studio-overnight's "refused" status) and print the setup command's exit code and a log path that still exists after the scratch worktree is gone.
- The scratch worktree never survives `start`: removed on success, failure, refusal and interrupt; a SIGKILLed start's leftover is swept by the next start.
- Phoenix is not changed.
- Review policy: per-task Opus review for T1 and T2 (new seam, cross-process signal handling); final whole-branch review on Opus; re-review only after a Critical, 3+ Importants or a production-bug fix.
- `tests/overnight_test.sh` and `tests/overnight_lanes_test.sh` must not run at the same time in one checkout. The integrated full gate (`sh tests/run_all.sh`) runs once, after the final fix wave.

## Decisions

- **R3 — `--dry-run` does not run the setup.** It prints one stdout line: `worktree_setup: start checks it once in a scratch linked worktree off origin/<B> before launch (up to <N> min); --dry-run does not run it`. Why: the dry run is the cheap, side-effect-free readiness check the operator runs repeatedly (and `--detach` itself calls it); running the setup there would take the gate lock, add a worktree and cost up to `worktree_setup_minutes` per call, and `start` already refuses at the one moment that matters — before launch, with the operator present.
- **D1 — Base.** Manifest runs: `origin/<Target>` (`MF_TARGET`): every story's new branch is cut from `origin/<Target>` (execute SKILL.md:117), so the scratch tree has the files and `.studio/config.json` the first story will see. Single-plan runs: `origin/<default branch>`. The helper fetches that one branch first (`git fetch -q origin <B>`).
- **D2 — Location.** `$STATE_ROOT/.claude/worktrees/setup-preflight-$$`, the same directory and depth as the runner's own worktrees, so a setup script that uses relative paths sees the same layout. `run_excludes` is called first so the directory never shows as untracked.
- **D3 — The log.** studio-setup writes its log under the worktree it runs in (`.studio/reports/setup-<stamp>.log`, relative to that tree). The helper copies it to `$STATE_ROOT/.studio/reports/setup-preflight-<stamp>-<pid>.log` before removing the worktree, and the refusal names the copy.
- **D4 — Signals.** The helper runs studio-setup in the background and `wait`s, with an INT/TERM/HUP trap that TERMs studio-setup (whose own TERM trap stops the command's process group and frees the gate lock), waits for it, removes the worktree and exits 2. Reason: a non-interactive shell's background job has SIGINT ignored and cannot re-trap it (checked on this machine: the child's `trap … INT` never fires), and a foreground child would delay our trap until a 30-minute setup ended.
- **D5 — Detach.** `detach_start` replaces its `lanes_start --dry-run` call with `lanes_start --check`, which does the manifest checks plus the setup preflight and prints only the checked commit (empty when the setup is unset) on stdout. The child gets `STUDIO_OVERNIGHT_SETUP_CHECKED=<sha>` (set explicitly after the env strip, as `STUDIO_RUN_ORIGIN` is). `setup_preflight` skips when that variable equals the base's commit; any other value (Target moved meanwhile) runs the check again.
- **D6 — Messages** (all through `say`, i.e. stderr with the `studio-overnight: ` prefix):
  - running: `worktree_setup: checking it once in a scratch linked worktree off origin/<B> before launch — up to <N> min (worktree_setup_minutes), longer while another run holds the gate lock`
  - green: `worktree_setup: green in a linked worktree`
  - red (studio-setup exit 1): `worktree_setup failed in a linked worktree — exit <n> — log <copied path> — a story's worktree is linked too (.git is a file there): fix the command, then start again` ; when `<n>` is 124 the exit part reads `exit 124 (timed out after worktree_setup_minutes)`.
  - bad config (studio-setup exit 2): `worktree_setup check: <studio-setup's stderr line>`
  - anything else: `worktree_setup check ended with exit <rc> — <its last stderr line, or "no output">`
  - interrupt: `worktree_setup check interrupted — nothing started`

## Review Focus

1. **Ctrl-C / TERM during a long setup** — the operator expects `start` to stop promptly, kill the setup's processes, release the gate lock and leave no scratch worktree. Pinned by `test_lanes_setup_preflight_interrupt_cleans` (T1).
2. **A start SIGKILLed mid-check** leaves `setup-preflight-<pid>`; the next start must sweep it, not fail on `worktree add`. Pinned by `test_lanes_setup_preflight_sweeps_stale` (T1).
3. **The failure log must outlive the scratch worktree** — a refusal naming a deleted path is useless. Pinned in `test_lanes_setup_preflight_refuses_linked_only` (asserts the named file exists).
4. **Detach must run the check once, in the foreground** — a child that re-ran a 30-minute setup would blow detach's 10 s status window and be killed. Pinned by `test_lanes_detach_setup_preflight_runs_once` (T2) and the sha binding by `test_lanes_setup_checked_env_binds_to_sha` (T2).
5. **Story-level setup failures must still hold the story** (a setup that passes at start but fails later, e.g. on a story's own branch). `test_lanes_setup_fail_holds` is rewritten to fail only outside the scratch path (T1), so that path stays covered.

## File Structure

- Modify `studios/game-dev/bin/studio-overnight` — the helper family; the single-plan call and dry-run note in `cmd_start`; `detach_start`'s check call and child env; usage text (`start`, `--detach`, config `worktree_setup`, Environment).
- Modify `studios/game-dev/bin/overnight-lanes.sh` — `lanes_start`: the preflight call before `lanes_run`, the dry-run note, the `--check` mode.
- Modify `tests/overnight_lanes_test.sh`, `tests/overnight_test.sh` — new tests; `test_lanes_setup_fail_holds` rewritten; `run_tests` lists.
- Modify `docs/game-dev/PROGRESS.md` — one entry (T2).

---

### Task 1: `setup_preflight` — plain and manifest start, dry-run note, help text

Review: task (Opus). Touches: `studio-overnight`, `overnight-lanes.sh`, both overnight suites.

**Interfaces:**
- Produces (in `studio-overnight`): `setup_preflight BRANCH` (returns 0 when unset/green/already checked; otherwise exits 2), globals `SP_W` (scratch path or empty), `SP_PID`, `SP_SHA` (the checked commit after a green or skipped-by-env run; empty when unset); `setup_preflight_note BRANCH` (the dry-run stdout line; silent when unset); `sp_remove`, `sp_sweep`, `sp_interrupt`.
- Consumes: `WORKTREE_SETUP`, `WORKTREE_SETUP_MINUTES` (set by `preflight`'s `cfg_nobs`/`cfg`, `studio-overnight:541-543`), `START_DIR`, `STATE_ROOT`, `REPORTS`, `SELF_DIR`, `say`, `run_excludes` (:1545), `DEFAULT_BRANCH`, `MF_TARGET`.

Anchors: `grep -n '^run_excludes()\|^cmd_start()\|^  preflight$\|with_launch_args print_launch' studios/game-dev/bin/studio-overnight`; `grep -n '^lanes_start()\|lanes_dry_run$\|^  lanes_run$' studios/game-dev/bin/overnight-lanes.sh`; `grep -n '^test_lanes_setup_fail_holds\|^run_tests' tests/overnight_lanes_test.sh`.

- [ ] **Step 1: Write the failing lanes tests** (in `tests/overnight_lanes_test.sh`, near `test_lanes_setup_fail_holds`, and add every name to the `run_tests` list — an unknown name fails the suite):

```sh
# #49: the preflight's scratch worktrees in $P (empty when none).
pf_wts() { git -C "$P" worktree list --porcelain | sed -n 's/^worktree //p' | grep '/setup-preflight-'; ls -d "$P"/.claude/worktrees/setup-preflight-* 2>/dev/null; }

test_lanes_setup_preflight_refuses_linked_only() {
  LANES_CONFIG='{"worktree_setup": "[ -d .git ]"}'; export LANES_CONFIG
  lanes_fixture pfr integration A:-
  assert_eq 0 "$( cd "$P" && [ -d .git ] && echo 0 || echo 1)" "the fixture's setup passes in the main checkout"
  run_lanes start "$MFP"
  assert_eq 2 "$LS_STATUS" "a setup that fails in a linked worktree refuses start"
  assert_contains "$LS_ERR" "worktree_setup: checking it once in a scratch linked worktree off origin/integration/demo before launch — up to 20 min" "the running line names the base and the cap"
  assert_contains "$LS_ERR" "worktree_setup failed in a linked worktree — exit 1 — log $P/.studio/reports/setup-preflight-[0-9-]*\.log" "the refusal names the exit and the log"
  _pl="$(sed -n 's/.* — log \([^ ]*\.log\) — .*/\1/p' "$LS_ERR" | head -n 1)"
  assert_eq 1 "$([ -f "$_pl" ] && echo 1 || echo 0)" "the named log exists after the scratch worktree is gone"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
  assert_eq 0 "$(calls)" "no unit ran"
  assert_missing "$P/.studio/runs/demo/lock" "no run lock was taken"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
}
test_lanes_setup_preflight_pass_launches() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) [ -f .git ] && echo pf >> '"$TMP"'/pf-ran;; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-ran"
  lanes_fixture pfp integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "a green preflight launches the run"
  assert_eq 1 "$(wc -l < "$TMP/pf-ran" | tr -d ' ')" "the setup ran once, in a linked worktree (.git is a file)"
  assert_contains "$LS_ERR" "worktree_setup: green in a linked worktree" "the green line"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: done$" "the run ends done"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
}
test_lanes_setup_preflight_unset_silent() {
  lanes_fixture pfu integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run ends done"
  assert_not_contains "$LS_ERR" "worktree_setup" "unset: no preflight line"
  assert_eq "" "$(pf_wts)" "none at all"
}
test_lanes_setup_preflight_dry_run_skips() {
  LANES_CONFIG='{"worktree_setup": "[ -d .git ]"}'; export LANES_CONFIG
  lanes_fixture pfd integration A:-
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "the dry run does not run the setup, so it passes"
  assert_contains "$LS_OUT" "^worktree_setup: start checks it once in a scratch linked worktree off origin/integration/demo before launch (up to 20 min); --dry-run does not run it$" "it says start will"
  assert_eq 0 "$(ls "$P"/.studio/reports/setup-* 2>/dev/null | wc -l | tr -d ' ')" "no setup log"
  assert_eq "" "$(pf_wts)" "no scratch worktree"
}
test_lanes_setup_preflight_interrupt_cleans() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) : > '"$TMP"'/pf-int; sleep 4831;; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-int"
  lanes_fixture pfi integration A:-
  lanes_bg
  wait_for "[ -f '$TMP/pf-int' ]" 60
  kill -TERM "$RPID"
  wait_pid_or_fail "$RPID" 20 "TERM during the check ends start promptly"
  assert_eq 2 "$WP_STATUS" "exit 2: nothing started"
  assert_contains "$TMP/lbg.err" "worktree_setup check interrupted — nothing started" "it says so"
  sleep 1
  assert_eq 0 "$(ps -A -o args= | grep -c '^sleep 4831$')" "the setup's processes are gone"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
  assert_eq 0 "$(calls)" "no unit ran"
}
test_lanes_setup_preflight_sweeps_stale() {
  LANES_CONFIG='{"worktree_setup": "true"}'; export LANES_CONFIG
  lanes_fixture pfs integration A:-
  mkdir -p "$P/.claude/worktrees"
  git -C "$P" worktree add -q --detach "$P/.claude/worktrees/setup-preflight-999999" HEAD
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "a dead start's leftover does not block the next start"
  assert_eq "" "$(pf_wts)" "and it is swept"
}
```

Rewrite `test_lanes_setup_fail_holds` so its setup still fails in the story's worktree but passes the preflight (the story-level path stays covered):

```sh
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) ;; *) exit 5;; esac"}'; export LANES_CONFIG
```

- [ ] **Step 2: Write the failing single-plan test** (in `tests/overnight_test.sh`, added to its `run_tests` list):

```sh
test_overnight_setup_preflight_single() {
  fixture pfs1 '{"worktree_setup": "[ -d .git ]"}'
  done_scenario; run_start
  assert_eq 2 "$RS_STATUS" "single-plan: a setup that fails in a linked worktree refuses start"
  assert_contains "$RS_ERR" "off origin/main before launch" "the base is the default branch"
  assert_contains "$RS_ERR" "worktree_setup failed in a linked worktree — exit 1 — log " "the refusal"
  assert_eq 0 "$(calls)" "no unit ran"
  assert_eq "" "$(ls -d "$P"/.claude/worktrees/setup-preflight-* 2>/dev/null)" "no scratch worktree"
  fixture pfs2 '{"worktree_setup": "[ -f .git ]"}'
  done_scenario; run_start
  assert_eq 0 "$RS_STATUS" "a green check launches the single-plan run"
  assert_contains "$RS_ERR" "worktree_setup: green in a linked worktree" "the green line"
  assert_eq "" "$(ls -d "$P"/.claude/worktrees/setup-preflight-* 2>/dev/null)" "no scratch worktree"
}
test_overnight_help_setup_preflight() {
  sh "$RUNNER" --help > "$TMP/help-pf.txt" 2>&1
  assert_contains "$TMP/help-pf.txt" "Preflighted: start runs it once in a scratch linked" "help: worktree_setup says it is preflighted"
}
```

- [ ] **Step 3: Run them and see them fail.**
`TESTS_ONLY="test_lanes_setup_preflight_refuses_linked_only test_lanes_setup_preflight_pass_launches test_lanes_setup_preflight_unset_silent test_lanes_setup_preflight_dry_run_skips test_lanes_setup_preflight_interrupt_cleans test_lanes_setup_preflight_sweeps_stale test_lanes_setup_fail_holds" sh tests/overnight_lanes_test.sh` (`run_tests`, `tests/assert.sh:68`, filters on `TESTS_ONLY`). Expected: the refusal/running-line/dry-run assertions fail; `test_lanes_setup_fail_holds` passes already. Then `TESTS_ONLY="test_overnight_setup_preflight_single test_overnight_help_setup_preflight" sh tests/overnight_test.sh`.

- [ ] **Step 4: Implement the helper** in `studio-overnight`, after `run_excludes()`:

```sh
# setup_preflight BRANCH — #49: worktree_setup once, through studio-setup (its
# gate lock, timeout, log and marker), in a scratch linked worktree at
# origin/BRANCH, so a command that breaks only where .git is a file is refused
# here and not by the first story at night. Silent when unset; skipped when
# STUDIO_OVERNIGHT_SETUP_CHECKED names the base's commit (--detach's child).
# Green: SP_SHA is the commit, the worktree is gone. Anything else: the
# worktree is gone and start exits 2 (refused).
SP_W=""; SP_PID=""; SP_SHA=""
setup_preflight() {
  [ -n "${WORKTREE_SETUP:-}" ] || return 0
  git -C "$START_DIR" fetch -q origin "$1" 2>/dev/null \
    || { say "worktree_setup check: git fetch origin $1 failed"; exit 2; }
  SP_SHA="$(git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/$1^{commit}" 2>/dev/null)" \
    || { say "worktree_setup check: no origin/$1"; exit 2; }
  [ "${STUDIO_OVERNIGHT_SETUP_CHECKED:-}" != "$SP_SHA" ] || return 0
  sp_sweep
  run_excludes
  SP_W="$STATE_ROOT/.claude/worktrees/setup-preflight-$$"
  if ! { mkdir -p "$(dirname "$SP_W")" \
         && git -C "$START_DIR" worktree add -q --detach "$SP_W" "$SP_SHA" >/dev/null 2>&1; }; then
    sp_remove; say "worktree_setup check: cannot add the scratch worktree $SP_W"; exit 2
  fi
  say "worktree_setup: checking it once in a scratch linked worktree off origin/$1 before launch — up to ${WORKTREE_SETUP_MINUTES:-20} min (worktree_setup_minutes), longer while another run holds the gate lock"
  _sp_ef="$(mktemp "${TMPDIR:-/tmp}/setup-preflight.XXXXXX")" || { sp_remove; say "worktree_setup check: mktemp failed"; exit 2; }
  trap 'sp_interrupt' INT TERM HUP
  # Background + wait: a trapped signal interrupts wait at once (D4).
  ( cd "$SP_W" && exec sh "$SELF_DIR/studio-setup" ) > /dev/null 2> "$_sp_ef" &
  SP_PID=$!
  _sp_rc=0; wait "$SP_PID" || _sp_rc=$?
  trap - INT TERM HUP
  SP_PID=""
  _sp_l="$(tail -n 1 "$_sp_ef" 2>/dev/null)"; rm -f "$_sp_ef"
  if [ "$_sp_rc" -eq 0 ]; then sp_remove; say "worktree_setup: green in a linked worktree"; return 0; fi
  _sp_log=""
  case "$_sp_l" in
    *" — log "*)
      mkdir -p "$REPORTS" && { [ -f "$REPORTS/.gitignore" ] || printf '*\n' > "$REPORTS/.gitignore"; }
      _sp_log="$REPORTS/setup-preflight-$(date +%Y%m%d-%H%M%S)-$$.log"
      cp "$SP_W/${_sp_l##* — log }" "$_sp_log" 2>/dev/null || _sp_log="" ;;
  esac
  sp_remove
  case "$_sp_rc" in
    1) _sp_n="$(printf '%s\n' "$_sp_l" | sed -n 's/^worktree setup failed — exit \([0-9]*\) — .*/\1/p')"
       [ "$_sp_n" != 124 ] || _sp_n="124 (timed out after worktree_setup_minutes)"
       say "worktree_setup failed in a linked worktree — exit ${_sp_n:-?} — log ${_sp_log:-unavailable} — a story's worktree is linked too (.git is a file there): fix the command, then start again" ;;
    2) say "worktree_setup check: ${_sp_l:-studio-setup refused the config}" ;;
    *) say "worktree_setup check ended with exit $_sp_rc — ${_sp_l:-no output}" ;;
  esac
  SP_SHA=""
  exit 2
}
# setup_preflight_note BRANCH — the dry run's one line (R3): start checks it, the dry run does not.
setup_preflight_note() {
  [ -n "${WORKTREE_SETUP:-}" ] || return 0
  echo "worktree_setup: start checks it once in a scratch linked worktree off origin/$1 before launch (up to ${WORKTREE_SETUP_MINUTES:-20} min); --dry-run does not run it"
}
# sp_remove — the scratch worktree, gone (a plain rm and a prune when git refuses).
sp_remove() {
  [ -n "$SP_W" ] || return 0
  git -C "$START_DIR" worktree remove --force "$SP_W" >/dev/null 2>&1 \
    || { rm -rf "$SP_W"; git -C "$START_DIR" worktree prune >/dev/null 2>&1; }
  SP_W=""
}
# sp_sweep — a dead start's scratch worktrees (setup-preflight-<pid>, pid not running).
sp_sweep() {
  for _sw in "$STATE_ROOT"/.claude/worktrees/setup-preflight-*; do
    [ -d "$_sw" ] || continue
    _swp="${_sw##*-}"
    case "$_swp" in ''|*[!0-9]*) continue ;; esac
    ! kill -0 "$_swp" 2>/dev/null || continue
    SP_W="$_sw"; sp_remove
  done
}
# sp_interrupt — INT/TERM/HUP during the check: stop studio-setup (TERM — its
# own trap ends the command's group and frees the gate lock), drop the worktree.
sp_interrupt() {
  trap '' INT TERM HUP
  if [ -n "$SP_PID" ]; then kill -TERM "$SP_PID" 2>/dev/null; wait "$SP_PID" 2>/dev/null; fi
  sp_remove
  say "worktree_setup check interrupted — nothing started"
  exit 2
}
```

Note: the `( cd … && exec sh studio-setup )` subshell exec's, so `SP_PID` is studio-setup's own pid and the TERM reaches its trap.

- [ ] **Step 5: Wire the callers.**
  - `cmd_start` single-plan path (`studio-overnight` after `preflight`, ~l.1431): in the dry-run branch, `setup_preflight_note "$DEFAULT_BRANCH"` before `with_launch_args print_launch`; after the dry-run branch and before `RUN_DIR=…`, `setup_preflight "$DEFAULT_BRANCH"`.
  - `lanes_start` (`overnight-lanes.sh:1977-1998`): in the dry-run branch, `setup_preflight_note "$MF_TARGET"` before `lanes_dry_run`; after it, `setup_preflight "$MF_TARGET"` before `lanes_run`. (lanes_start's EXIT trap `lanes_on_exit` already cleans `MF_TMP` on the helper's `exit 2`.)

- [ ] **Step 6: Help text** (`usage()` in `studio-overnight`): replace the `worktree_setup` config lines (:380-381) with
```
  worktree_setup       ""             command run once per new worktree under the gate lock
                                    (studio-setup); no backslash. Unset = nothing runs.
                                    Preflighted: start runs it once in a scratch linked
                                    worktree off the run's base and refuses on a failure
                                    (exit code and log shown); --dry-run only says so
```
and add to the `start [--dry-run]` paragraph: `When worktree_setup is set, start first checks it in a scratch linked worktree (see Config).`

- [ ] **Step 7: Run the new and the touched tests; they pass.** Then the setup-adjacent lanes tests: `test_lanes_setup_fail_final_red test_lanes_setup_silent_fail_final_red test_lanes_setup_fail_path_specials test_lanes_direct_setup_fail_note test_lanes_final_stop_before_setup` and `sh tests/studio_setup_test.sh`. Then the whole `tests/overnight_lanes_test.sh`, then (not concurrently) the whole `tests/overnight_test.sh`.

- [ ] **Step 8: Commit** — `git commit -m 'feat(overnight): preflight worktree_setup in a scratch linked worktree before start (#49)' -- studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh tests/overnight_test.sh`

Acceptance: R1 (plain and manifest), R2, R3, R4, R5 all pinned by the tests above.

---

### Task 2: `--detach` — check once in the foreground, the child skips; PROGRESS

Review: task (Opus). Touches: `studio-overnight`, `overnight-lanes.sh`, `tests/overnight_lanes_test.sh`, `docs/game-dev/PROGRESS.md`. Depends on T1.

**Interfaces:**
- Consumes: `setup_preflight`, `SP_SHA` (T1).
- Produces: `lanes_start --check MANIFEST` — the manifest checks plus `setup_preflight "$MF_TARGET"`; stdout is exactly `SP_SHA` plus a newline (an empty line when the setup is unset); exit 0, or 2 on any refusal. `STUDIO_OVERNIGHT_SETUP_CHECKED` (documented in usage's Environment section).

Anchors: `grep -n 'lanes_start --dry-run "\$_dm"\|perl -MPOSIX' studios/game-dev/bin/studio-overnight` (1344, 1361, 1363); `grep -n 'STUDIO_RUN_ORIGIN —' studios/game-dev/bin/studio-overnight`.

- [ ] **Step 1: Failing tests** (`tests/overnight_lanes_test.sh`, added to `run_tests`):

```sh
test_lanes_detach_setup_preflight_refused() {
  LANES_CONFIG='{"worktree_setup": "[ -d .git ]"}'; export LANES_CONFIG
  lanes_fixture pfdr integration A:-
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/pfdr.out" 2>&1 || st=$?
  assert_eq 2 "$st" "detach: the check runs in the foreground and refuses"
  assert_contains "$TMP/pfdr.out" "worktree_setup failed in a linked worktree — exit 1 — log " "the refusal is shown"
  assert_not_contains "$TMP/pfdr.out" "^detached:" "no child was started"
  assert_eq 0 "$(calls)" "no unit ran"
  assert_eq "" "$(pf_wts)" "no scratch worktree"
}
test_lanes_detach_setup_preflight_runs_once() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) echo pf >> '"$TMP"'/pf-det;; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-det"
  lanes_fixture pfdo integration A:-
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/pfdo.out" 2>&1 || st=$?
  assert_eq 0 "$st" "a green check detaches"
  assert_contains "$TMP/pfdo.out" "worktree_setup: checking it once" "the running line is in the foreground output"
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  detach_stop
  assert_eq 1 "$(wc -l < "$TMP/pf-det" | tr -d ' ')" "the setup ran once: the child skipped it"
  assert_eq "" "$(pf_wts)" "no scratch worktree"
}
test_lanes_setup_checked_env_binds_to_sha() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) echo pf >> '"$TMP"'/pf-env;; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-env"
  lanes_fixture pfe integration A:-
  STUDIO_OVERNIGHT_SETUP_CHECKED=0000000000000000000000000000000000000000; export STUDIO_OVERNIGHT_SETUP_CHECKED
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_SETUP_CHECKED
  assert_eq 1 "$(wc -l < "$TMP/pf-env" | tr -d ' ')" "a value that is not the base's commit runs the check"
  rm -f "$TMP/pf-env"
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) echo pf >> '"$TMP"'/pf-env;; esac"}'; export LANES_CONFIG
  lanes_fixture pfe2 integration A:-
  STUDIO_OVERNIGHT_SETUP_CHECKED="$(git -C "$P" ls-remote origin refs/heads/integration/demo | cut -f1)"; export STUDIO_OVERNIGHT_SETUP_CHECKED
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_SETUP_CHECKED
  assert_eq 0 "$LS_STATUS" "the run ends done"
  assert_missing "$TMP/pf-env" "the base's own commit skips the check"
}
```
(`lanes_fixture` unsets every `LANES_*`, so the second fixture sets `LANES_CONFIG` again.)

- [ ] **Step 2: Run; they fail** (detach currently never runs the setup in the foreground; the child would run it — `pf-det` would hold 1 line from the child, but `checking it once` is absent from `pfdo.out`, and the refused test exits 0 or 1 instead of 2).

- [ ] **Step 3: `lanes_start --check`.** In `lanes_start`'s argument loop add `--check) _ls_chk=1 ;;` (init `_ls_chk=0`). After `build_chains` and before the dry-run branch:
```sh
  if [ "$_ls_chk" -eq 1 ]; then
    setup_preflight "$MF_TARGET"
    printf '%s\n' "$SP_SHA"
    exit 0
  fi
```
Header comment: `lanes_start [--dry-run | --check] MANIFEST` — `--check` (detach's foreground step): the manifest checks and the setup preflight; prints the checked commit only.

- [ ] **Step 4: `detach_start`.** Replace
`( . "$SELF_DIR/overnight-lanes.sh"; lanes_start --dry-run "$_dm" ) > /dev/null || exit 2`
with
```sh
  _dck="$( . "$SELF_DIR/overnight-lanes.sh"; lanes_start --check "$_dm" )" || exit 2
```
and in both `nohup env …` child launches add `${_dck:+"STUDIO_OVERNIGHT_SETUP_CHECKED=$_dck"}` next to the `STUDIO_RUN_ORIGIN` word. Update the `detach_start` header comment: the foreground step now includes the worktree_setup check, whose commit the child gets so it does not run it again.

- [ ] **Step 5: Usage.** In the `start --detach <manifest>` paragraph: `preflight (worktree_setup's check included) runs in the foreground`. In Environment, after `STUDIO_RUN_ORIGIN`:
```
  STUDIO_OVERNIGHT_SETUP_CHECKED — set by --detach for its child: the commit the
                     foreground worktree_setup check passed at; start skips the
                     check when it names the base's commit. Never set it yourself
```

- [ ] **Step 6: PROGRESS.** Add a dated entry to `docs/game-dev/PROGRESS.md` in its existing style (read its last entry first): #49 — `start` checks `worktree_setup` in a scratch linked worktree before launch; refuses with exit and log; `--dry-run` only says so; phoenix's 2026-10-05 incident as the reason.

- [ ] **Step 7: Run** the three new tests, the detach tests (`grep -n '^test_lanes_detach' tests/overnight_lanes_test.sh`), `test_lanes_origin_detach test_lanes_origin_detach_refused`, then the whole lanes suite. Then `sh integrations/multica/tests/readme_test.sh` (it pins the `start --detach` wording).

- [ ] **Step 8: Commit** — `git commit -m 'feat(overnight): --detach checks worktree_setup in the foreground; the child skips it (#49)' -- studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh docs/game-dev/PROGRESS.md`

Acceptance: R1's "detached or not"; Review Focus 4.

---

### Task 3: Final whole-branch review, fix wave, gate, PR

- [ ] Standalone whole-branch review on Opus over `81691ab..HEAD` against the spec and this plan.
- [ ] One fresh fixer for the findings (minors batched); re-review only per the Global Constraints rule.
- [ ] Full gate once on the integrated branch: `sh tests/run_all.sh` and `sh integrations/multica/tests/run_all.sh` (or that directory's runner — check its name).
- [ ] PR `Closes #49`, body with the R3 decision and its reason; merge once green (operator's standing merge authority for omega-ai). Do not reinstall or pull into the main checkout while an overnight run is live — check `studio-overnight status` first; otherwise leave the reinstall as a noted follow-up.

## Falsify — load-bearing claims at 81691ab

1. Story worktrees are cut from `origin/<Target>` — `studios/game-dev/skills/execute/SKILL.md:117` (`git worktree add --no-track -b <Branch> … origin/<Target>`). If false, D1's base is wrong.
2. studio-setup's failure line is `worktree setup failed — exit <n> — log <path>` with `<path>` relative to the tree it ran in — `studio-setup:157-164`. If false, D3's copy fails (the refusal then says `log unavailable`, the test catches it).
3. studio-setup traps TERM and stops the command's process group, then exits 143 — `studio-setup:109-118,124-126`. If false, D4's interrupt leaves the setup running (the interrupt test catches it).
4. A non-interactive shell's background job ignores SIGINT and cannot re-trap it — checked on this machine (`sh -c 'trap … INT; kill -INT $$' &` never ran its trap). Hence TERM, not INT, in `sp_interrupt`.
5. `detach_start` strips every `STUDIO_*` before the foreground preflight (`studio-overnight:1338-1340`), so a stray `STUDIO_OVERNIGHT_SETUP_CHECKED` in the chat cannot skip the detached check; only the explicit `env` word sets it.
6. The lanes stub's `auto` runs the real `studio-setup` in each story worktree (`tests/overnight_lanes_test.sh:112-115`), and story worktrees sit under `$TMP_WT`, not `.claude/worktrees/setup-preflight-*` — so `test_lanes_setup_fail_holds`' rewritten `case` still fails there.
7. `git worktree remove --force` removes a linked worktree holding untracked and ignored files — checked on this machine (git 2.x, exit 0, directory gone).
8. `lanes_start` has an EXIT trap (`lanes_on_exit`) before `mf_check` (`overnight-lanes.sh:1985`), so the helper's `exit 2` cleans `MF_TMP`.
