# S1 Runner: Run Config for the Runner's Own Launches, and `Final base:` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The runner's own gate and land launches see the run's config keys (#82). A manifest can name the final PR's base with `Final base: <branch>` (#81). The direct-mode `--detach` refusal is documented (#73, docs only).

**Architecture:**
- **#82.** `studio-overnight` exports `STUDIO_START_DIR` once, right after `START_DIR` is final (O:564). `detach_start` strips `STUDIO_*` and then exports it again (O:1659). Every child the runner starts inherits it: `final_gate`, the direct land's `studio-gate merge`, `studio-setup`. `studio_cfg`'s existing per-key fallback does the rest.
- **#81.** `MF_BASE` is parsed in `mf_load` and in `lanes_load_run`, and validated in `mf_check`. It replaces `$DEFAULT_BRANCH` at the final step's sites only:
  - `final_pr_open`;
  - the final merge;
  - `gh pr create`;
  - the story sync refs;
  - the integration-branch refusal text.
- `RECORD/final` gains a fourth field only when `MF_BASE` is not the default branch. Step 0 refuses a changed base while the old PR is open.
- A final conflict repair gets `STUDIO_FINAL_BASE`, so the integration skill merges the right ref.

**Tech Stack:** POSIX sh (dash-clean), awk, python3 where already used.
**Spec:** docs/game-dev/specs/2026-10-21-backlog-sweep.md §4 (with §1-3, §11-13)
**Story branch:** `issue-82-runner-config` off integration/backlog-2026-10-21

Paths:
- `L` = `studios/game-dev/bin/overnight-lanes.sh`
- `O` = `studios/game-dev/bin/studio-overnight`
- `T` = `tests/overnight_lanes_test.sh`
- `OT` = `tests/overnight_test.sh`
- `X` = `studios/game-dev/skills/execute/SKILL.md`
- `AP` = `shared/omega/skills/autopilot/SKILL.md`
- `IN` = `shared/omega/skills/integration/SKILL.md`

Line numbers are at 1cfca7f. Relocate each one with its `grep -n` anchor before editing, because S2/S3/S4 merge first and shift L/O/T.

`<W>` is this story's worktree, `/Users/xinli/GameDev/proj/omega-ai/.claude/worktrees/issue-82-runner-config`. `<S>` is a scratch dir outside every repo: `/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/5a98a755-7ca1-4ed6-b551-b3a3f4153b67/scratchpad/s1-run`. Run `mkdir -p <S>/tmp` once. **Run form** (abbreviated `RUN <suite> "<tests>"` below):

```sh
cd <S> && TMPDIR=<S>/tmp TESTS_ONLY="<tests>" sh   <W>/tests/<suite>.sh
cd <S> && TMPDIR=<S>/tmp TESTS_ONLY="<tests>" dash <W>/tests/<suite>.sh
```

A lanes run of more than 3 tests goes as one background run plus its notification, never as stacked pollers.

## Global Constraints

- POSIX sh only, clean under dash (`TEST_SH=dash`): no bashisms, no `local`, no `$BASHPID`. Function variables carry a per-function prefix (`_mb_`, `_fi_` …).
- A1: with no `Final base:` and none of `test_engine_args`/`gate_short_lane`/`user_dir` set, every argv, report line, status line and ending is byte-identical to the integration base.
- `Final base: <branch>` is an optional header line, read by `mf_header 'Final base'` (L:35-37: a trailing ` #…` comment and trailing blanks are stripped). It applies in integration mode only. The default is the default branch.
- A value equal to the default branch is the same as no field, byte for byte.
- Refusal texts, verbatim:
  - `manifest: Final base: is for Mode integration only (direct lands on the default branch)`
  - `manifest: Final base: origin/<b> does not exist (push it, or drop the field)`
  - `final base changed since the last final step (<old> → <new>) — close PR <url> or restore the field`
- `MF_BASE="$(mf_header 'Final base')"; [ -n "$MF_BASE" ] || MF_BASE="$DEFAULT_BRANCH"`, in `mf_load` (with `${DEFAULT_BRANCH:-}`: O runs `set -u`, O:23) and in `lanes_load_run` after L:1491-1494.
- The export, verbatim: `STUDIO_START_DIR="$START_DIR"; export STUDIO_START_DIR`. It goes after O:564 and again after O:1659. O:1321's explicit export stays.
- Unchanged:
  - L:1449 (bundle-2 story PRs into the default branch);
  - `land_once_direct` (L:619, L:652);
  - `progress_direct` (L:1946, L:1964, L:1967);
  - `ids_default_branch` (story-id uniqueness ignores the base).
- A red final PR leaves no `RECORD/done` **by design**: only a comment changes. `test_lanes_report_every_ending` keeps asserting this.
- No phoenix change, and no reinstall. Hand-run suites use a scratch cwd and an existing `TMPDIR`.
- Floors are exact after S2. Run `sh tests/run_all.sh --update-floors` only after rebasing on the integration branch (Task 6).
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HHd9n1KiKNE9YBptbSEgPL
  ```

## Review Focus

1. **A stray inherited `STUDIO_START_DIR`.** The runner may be started from a unit session or a chat that carries another run's value. The runner's own start dir must win, for units and for its own gates, and the `--detach` strip must not forward the stray value. Tests:
   - T1 `test_lanes_unit_env_unchanged` (a stray `$TMP/stray` in the runner's env);
   - T1 `test_lanes_detach_child_exports_start_dir` (a stray `$TMP/bogus` in the chat env).
2. **A final conflict repair against a non-default base.** IN :91-94 hard-codes `origin/main`. The runner's post-repair check is `merge-base --is-ancestor "$_fi_m" HEAD` (L:1847-1848), so a repair that merges main reads as unresolved, and the run goes red. Test: T3 `test_lanes_final_base_conflict_repair` (`STUDIO_FINAL_BASE=feat/x` reaches the repair; the head descends from origin/feat/x; green).
3. **A 4-field `RECORD/final` read by a 3-variable `read`.** `read -r a b c` puts `green feat/x` into the color. `final_ok` needs exactly `green` (L:1310), so a resume at an unchanged head would end `partial` instead of `done`. Test: T4 `test_lanes_final_base_resume_unchanged_is_done`.
4. **A changed base whose old PR is already closed.** It must proceed to a new PR into the new base, and not refuse forever. Test: T4 `test_lanes_final_base_changed_after_close_proceeds`.
5. **Bad and edge `Final base:` values.** Each must refuse with a precise text, or (for the default branch) be a no-op:
   - `run/demo`, `integration/demo`, `progress/x`;
   - `a..b` (not a ref);
   - `<branch>` (the template copied verbatim);
   - `main   # comment` under `Mode: direct` (equal to the default branch: no Final-base refusal).

   Test: T2 `test_lanes_final_base_bad_names_refused`.

---

### Task 1: #82 — the runner exports `STUDIO_START_DIR` — **Risky** (runner env, cross-system)

(Spec §11 lets #82 fold into the final review. Its per-task review stays optional for the controller.)

**Files:**
- Modify: `O:564-565` (export after `START_DIR=`).
- Modify: `O:1659` (re-export after the re-derive).
- Modify: `O:306-308` (help: `STUDIO_START_DIR` is set again after the strip).
- Modify: `L:1473-1477` (`lanes_finish` comment).
- Modify: `L:1531-1535` (`lanes_reap_at` comment: lanes_reap launches nothing gated).
- Test: `T:479-481` (merge stub records its env).
- Test: new tests after `test_lanes_units_get_start_dir` (T:3838-3844). Names are appended to `run_tests` (T:4871ff).

**Interfaces:**
- Consumes: `studio_cfg` (`bin/gate-class.sh:22-32`, `engines/godot/cfg.sh:8-18`). It ignores an empty `STUDIO_START_DIR` (`-n`).
- Consumes: `use_gate` (T:1829) and `STUDIO_OVERNIGHT_GATE_CMD`.
- Produces: an exported `STUDIO_START_DIR` = `START_DIR` in every process O starts. The detach child gets it from the parent's re-export.

- [ ] **Step 1: Stub edit (test-only).** In the merge stub (T:479), after its first `echo`, add `printf '%s\n' "${STUDIO_START_DIR:-unset}" >> "$CALLS/merge.start"`.
- [ ] **Step 2: Failing tests.**

```sh
test_lanes_final_gate_sees_run_config() {
  LANES_CONFIG='{"test_engine_args": "--fixed-fps 60"}'; export LANES_CONFIG
  lanes_fixture fgcfg integration A:-
  use_gate "printf 'start=%s\n' \"\${STUDIO_START_DIR:-unset}\" > '$CALLS/fg.env'; . '$BIN/../engines/godot/cfg.sh'; printf 'args=%s\ntop=%s\n' \"\$(studio_cfg test_engine_args)\" \"\$(git rev-parse --show-toplevel)\" >> '$CALLS/fg.env'"
  run_lanes start "$MFP"; use_gate true
  W="$P/.claude/worktrees/integration-demo"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_eq 0 "$(cat "$W/.studio/config.json" 2>/dev/null | grep -c test_engine_args)" "the fixture: the integration worktree has no key of its own"
  assert_contains "$CALLS/fg.env" "^top=$W\$" "the gate ran in the integration worktree"
  assert_contains "$CALLS/fg.env" "^start=$P\$" "the final gate sees STUDIO_START_DIR = the run's start dir"
  assert_contains "$CALLS/fg.env" "^args=--fixed-fps 60\$" "studio_cfg there reads the run's test_engine_args"
}
test_lanes_direct_land_sees_run_config() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture dlcfg direct A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "A lands"
  assert_eq "$P" "$(sort -u "$CALLS/merge.start" 2>/dev/null)" "studio-gate merge's program sees STUDIO_START_DIR = the run's start dir"
}
test_lanes_unit_env_unchanged() {
  lanes_fixture uenv integration A:-
  STUDIO_START_DIR="$TMP/stray"; export STUDIO_START_DIR
  use_gate "printf '%s\n' \"\$STUDIO_START_DIR\" > '$CALLS/fg.start'"
  run_lanes start "$MFP"; unset STUDIO_START_DIR; use_gate true
  assert_eq 1 "$(grep -c '^STUDIO_START_DIR=' "$CALLS/1.fullenv")" "one STUDIO_START_DIR line"
  assert_contains "$CALLS/1.fullenv" "^STUDIO_START_DIR=$P\$" "a unit's line is today's: the run's start dir, not the stray value"
  assert_eq "$P" "$(cat "$CALLS/fg.start" 2>/dev/null)" "the final gate gets the run's start dir, not the inherited one"
}
test_lanes_detach_child_exports_start_dir() {
  lanes_fixture dsd integration A:-
  export STUDIO_OVERNIGHT_DETACH_CHILD_CMD="printf '%s\n' \"\${STUDIO_START_DIR:-unset}\" > '$TMP/dsd.env'; exit 3"
  st=0; ( cd "$P" && env STUDIO_START_DIR="$TMP/bogus" sh "$RUNNER" start --detach "$MFP" ) > "$TMP/dsd.out" 2>&1 || st=$?
  unset STUDIO_OVERNIGHT_DETACH_CHILD_CMD
  assert_eq 3 "$st" "the stand-in's exit is detach's"
  assert_eq "$P" "$(cat "$TMP/dsd.env" 2>/dev/null)" "the child sees the run's start dir after the STUDIO_* strip (never the chat's)"
}
```

- [ ] **Step 3: Run, expect FAIL.**

  ```sh
  RUN overnight_lanes_test "test_lanes_final_gate_sees_run_config test_lanes_direct_land_sees_run_config test_lanes_unit_env_unchanged test_lanes_detach_child_exports_start_dir"
  ```

  Expected:
  - `start=unset`, empty `args=`;
  - `merge.start` = `unset`;
  - `fg.start` = the stray path;
  - `dsd.env` = `unset`.

  The two unit-line assertions already pass: they pin today's behaviour.
- [ ] **Step 4: Implement.**
  - **O, after :564:** a comment, then the export:

    ```sh
    # #82: every gate, test and setup this runner launches itself (final_gate,
    # the direct land's studio-gate merge, studio-setup) reads the run's config
    # keys (test_engine_args, gate_short_lane, user_dir) through studio_cfg's
    # per-key STUDIO_START_DIR fallback. Units still get it explicitly (start_session).
    STUDIO_START_DIR="$START_DIR"; export STUDIO_START_DIR
    ```
  - **O, after :1659:** the same export, with the comment `# the strip above removed it: the parent's lanes_start --check and the child see the run's value`.
  - **O help :306-308:** after `CLAUDE_CONFIG_DIR and PATH stay`, add `; STUDIO_START_DIR is set again to the run's start dir`.
  - **L `lanes_finish` comment:** a red final PR ends `partial … final PR red` and writes no `done` by design. A resume re-runs the final step (step 0), which may turn it green. An operator who lands a red final PR by hand marks the run done with `: > .studio/runs/<slug>/done`.
  - **L `lanes_reap_at` comment:** `lanes_reap` runs `lanes_sweep` and `lanes_report` only, and launches no gate. So the `STUDIO_START_DIR` this process exported (not the reaped run's `START_DIR`) is harmless here. The same holds for `status_reap_dead` (O:2116).
- [ ] **Step 5: Run, expect PASS.** Run the Step 3 command, plus these neighbours:

  ```sh
  RUN overnight_lanes_test "test_lanes_units_get_start_dir test_lanes_detach_strips_env test_lanes_final_step_once test_lanes_land_clean_direct"
  RUN overnight_test test_overnight_help
  ```
- [ ] **Step 6: Commit.** `fix(#82): the runner's own gates and lands see the run's config (STUDIO_START_DIR)`

### Task 2: #81 — parse and preflight `Final base:` — **Risky** (manifest format)

**Files:**
- Modify: `L:45-55` `mf_load` (set `MF_BASE`).
- Modify: `L:1486-1495` `lanes_load_run` (set `MF_BASE` after `DEFAULT_BRANCH`).
- Modify: `L:176-180` (story-branch rule).
- Modify: `L:228-231` (refusal text, then a call to the new `mf_base_check`).
- Test: T, new helpers next to `use_gate` (T:1828), and new tests after `test_lanes_manifest_header_refusals` (T:819-835).

**Interfaces:**
- Produces: `MF_BASE` (never empty once `DEFAULT_BRANCH` is set).
- Produces: `mf_base_check`, called from `mf_check` after the `origin/integration/<slug>` check (so after the L:216 fetch).
- Produces test helpers `base_branch NAME`, `mf_set_base VALUE` and `gnorm FILE`. They are used by Tasks 2-4.

- [ ] **Step 1: Characterization test first (passes at base; the A1 golden).**

```sh
# base_branch NAME — origin/NAME cut from origin/integration/demo plus one commit (base.txt); integration fixtures only.
base_branch() {
  ( _bb="$(mktemp -d "$TMP/base.XXXXXX")" && git clone -q "$(git -C "$P" remote get-url origin)" "$_bb/c" \
    && cd "$_bb/c" && git checkout -q -b "$1" origin/integration/demo && printf '%s\n' "$1" > base.txt \
    && git add base.txt && git commit -qm "$1: base.txt" && git push -q origin "$1" ) >/dev/null 2>&1
}
# mf_set_base VALUE — `Final base: VALUE` after Target: in $P/$MFP, committed and pushed on run/demo.
mf_set_base() {
  awk -v v="$1" '{ print } /^Target:/ { print "Final base: " v }' "$P/$MFP" > "$P/$MFP.new" && mv "$P/$MFP.new" "$P/$MFP"
  ( cd "$P" && git commit -qam "manifest: Final base" && git push -q origin run/demo ) >/dev/null 2>&1
}
# gnorm FILE — FILE with $TMP as @T@, run-dir stamps as @TS@, the Started/Ended line dropped.
gnorm() { sed -e "s#$TMP#@T@#g" -e 's#overnight-demo-[0-9-]*#overnight-demo-@TS@#g' -e '/^Started: /d' "$1"; }
test_lanes_final_base_absent_identical() {
  lanes_fixture fbabs integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_eq "$(cat <<'EOF'
<paste: gnorm "$GH/calls" captured at the base, before any #81 edit>
EOF
)" "$(gnorm "$GH/calls")" "gh argv is byte-identical with no Final base"
  assert_eq "$(cat <<'EOF'
<paste: gnorm report.md captured at the base>
EOF
)" "$(gnorm "$(last_lanes_dir)/report.md")" "report.md is byte-identical with no Final base"
  assert_contains "$P/.studio/runs/demo/final" "^[0-9a-f]* https://gh.test/pr/1 green\$" "a 3-field final record"
  assert_eq 0 "$(cat "$CALLS"/*.fullenv | grep -c '^STUDIO_FINAL_BASE=')" "no unit gets STUDIO_FINAL_BASE"
}
```

  - Capture the golden by running the test body at the story's base before editing L.
  - Read the captured bytes. They must hold `pr list --head integration/demo --base main …`, `pr create --draft --base main --head integration/demo …` and `Final PR: https://gh.test/pr/1 (green)`.
  - Paste them, then run: PASS.
  - The test stays green after Tasks 2-4.

- [ ] **Step 2: Failing tests.**
  - `test_lanes_final_base_missing_refused`: `lanes_fixture fbmiss integration A:-`, then `mf_set_base feat/none`, then `run_lanes start --dry-run "$MFP"`.
    - `assert_eq 2 "$LS_STATUS"`.
    - `assert_contains "$LS_ERR" "manifest: Final base: origin/feat/none does not exist (push it, or drop the field)"`.
  - `test_lanes_final_base_direct_refused`: `LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'`, a direct fixture, `mf_set_base feat/x` (no `base_branch`: a direct fixture has no integration/demo, and the mode refusal comes first), then a dry run.
    - Exit 2.
    - `assert_contains "$LS_ERR" "manifest: Final base: is for Mode integration only (direct lands on the default branch)"`.
  - `test_lanes_final_base_story_branch_refused`: integration, `base_branch feat/x`, `mf_set_base feat/x`, and `sed 's/^| A | A-b |/| A | feat\/x |/'` (committed as in T:787-791), then a dry run.
    - Exit 2.
    - `assert_contains "$LS_ERR" "manifest: A: branch feat/x is the default branch or the run's Target or the run's Final base — pick another"`.
    - `test_lanes_branch_default_or_target_refused` (T:773-781) keeps today's text, with no suffix.
  - `test_lanes_final_base_bad_names_refused` (Review Focus 5). For each of `run/demo`, `integration/demo`, `progress/x`, `a..b` and `<branch>`: a fresh fixture `fbbad-<k>` (k = 1..5), then `mf_set_base "$v"` and a dry run.
    - Exit 2. `LS_ERR` contains `manifest: Final base: `.
    - `run/demo`, `integration/demo` and `progress/x` match `is a run, integration or progress branch`.
    - `a..b` and `<branch>` match `is not a valid branch name`.
    - Then the direct fixture with `merge_command` and `mf_set_base 'main   # the default'`. A dry run exits 0, and `assert_not_contains "$LS_ERR" "Final base"`.
- [ ] **Step 3: Run, expect FAIL.**

  ```sh
  RUN overnight_lanes_test "test_lanes_final_base_missing_refused test_lanes_final_base_direct_refused test_lanes_final_base_story_branch_refused test_lanes_final_base_bad_names_refused test_lanes_final_base_absent_identical"
  ```

  The four refusal tests fail: no refusal, so exit 0. The golden passes.
- [ ] **Step 4: Implement.**
  - `mf_load`: after the `MF_GOAL` line, add `MF_BASE="$(mf_header 'Final base')"; [ -n "$MF_BASE" ] || MF_BASE="${DEFAULT_BRANCH:-}"`. Update its header comment to name `MF_BASE`. Do the same in `lanes_load_run`, after the `DEFAULT_BRANCH` block.
  - Story-branch rule (L:176-180): add `|| [ "$_bf_b" = "$MF_BASE" ]` to the test. Keep the text, plus the suffix `${_bf_x}`, where `_bf_x=" or the run's Final base"` only when `[ "$MF_BASE" != "$DEFAULT_BRANCH" ]`, else empty.
  - L:230: `create it from origin/$MF_BASE and push it`. It is byte-identical with no field.
  - `mf_base_check`, full:

```sh
# mf_base_check — #81: the optional `Final base:` header. A value equal to the
# default branch (or none) is no field. One refuse per failure; after mf_check's fetch.
mf_base_check() {
  [ "$MF_BASE" != "$DEFAULT_BRANCH" ] || return 0
  if [ "$MF_MODE" = direct ]; then
    refuse "manifest: Final base: is for Mode integration only (direct lands on the default branch)"; return 0
  fi
  if ! git check-ref-format --branch "$MF_BASE" >/dev/null 2>&1; then
    refuse "manifest: Final base: '$MF_BASE' is not a valid branch name"; return 0
  fi
  case "$MF_BASE" in
    integration/*|run/*|progress/*)
      refuse "manifest: Final base: $MF_BASE is a run, integration or progress branch — name the branch the run lands in"; return 0 ;;
  esac
  git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/$MF_BASE^{commit}" >/dev/null \
    || refuse "manifest: Final base: origin/$MF_BASE does not exist (push it, or drop the field)"
}
```

  Ruling: any `integration/*`, `run/*` or `progress/*` is refused, not only this slug's. A run landing into another run's machine branch is never intended.
- [ ] **Step 5: Run, expect PASS.** Run the Step 3 command, plus `test_lanes_branch_default_or_target_refused test_lanes_manifest_header_refusals test_lanes_manifest_refusals test_lanes_next test_lanes_status_dead_old_lock_not_masking`.
- [ ] **Step 6: Commit.** `feat(#81): the manifest's optional Final base: header, parsed and preflighted`

### Task 3: #81 — the final step, sync, report and status use the base — **Risky** (cross-system: runner ↔ gh ↔ integration skill)

**Files:**
- Modify: `L:1732-1741` `final_pr_open BRANCH [BASE]`.
- Modify: `L:1810` (`_fi_m`).
- Modify: `L:1819` (step 0 call).
- Modify: `L:1845` (conflict repair env).
- Modify: `L:1910` and `L:1915` (step 5).
- Modify: `L:1776-1793` (step comments: `origin/<default>` → `origin/<Final base>`).
- Modify: `L:783` (sync refs).
- Modify: `L:1401` (report).
- Modify: `L:1585-1590` `lanes_status_lines` (before `gate_line`).
- Modify: `IN:80-83, 91-94` (repair conflict text).
- Test: `T:344` (`mergemain`).
- Test: `T:328` and `T:363-364` (new `push_ref` post action, documented in the stub header near T:136-138).
- Test: `tests/omega_contracts/integration_contract.sh` (one assertion).

**Interfaces:**
- Consumes `MF_BASE` (Task 2).
- `final_pr_open BRANCH [BASE]`: `--base "${2:-$DEFAULT_BRANCH}"`. The return codes are unchanged (0 found, 1 none, 2 gh failed).
- The conflict repair's env words are `STUDIO_REPAIR=conflict`, plus ` STUDIO_FINAL_BASE=<b>` only when `MF_BASE` ≠ default.
- Report: `Final PR: <url> (<color>) into <b>` only when non-default. Status: `final base: <b>` only when non-default.

- [ ] **Step 1: Stub edits (test-only).**
  - `mergemain` merges `"origin/${STUDIO_FINAL_BASE:-main}"`.
  - New post action `push_ref <branch> <f>`: add it to T:328's post list, and add `"push_ref "*) set -- ${act#push_ref }; push_to "$1" "$2" ;;` next to T:363.
- [ ] **Step 2: Failing tests.**
  - `test_lanes_final_base_opens_pr_into_it`: `LANES_MAIN_MOVES=main.txt`, `lanes_fixture fbpr integration A:-`, `base_branch feat/x`, `mf_set_base 'feat/x   # land here'`, then `run_lanes start "$MFP"`.
    - `assert_eq 0 "$LS_STATUS"`.
    - `assert_eq 1 "$(grep -c '^pr list --head integration/demo --base feat/x ' "$GH/calls")"` (step 5's lookup).
    - `assert_eq 1 "$(grep -c '^pr create --draft --base feat/x --head integration/demo ' "$GH/calls")"`.
    - `assert_not_contains "$GH/calls" '^pr create .*--base main'`.
    - After `git -C "$P" fetch -q origin`: `assert_status 0 … git -C "$P" merge-base --is-ancestor origin/feat/x origin/integration/demo` (the final step merged the base).
    - `assert_status 1 … merge-base --is-ancestor origin/main origin/integration/demo` (not main).
    - `assert_contains report.md "^Final PR: https://gh.test/pr/1 (green) into feat/x$"`.
    - `( cd "$P" && sh "$RUNNER" status ) > "$TMP/fbst.out"`, then `assert_contains "$TMP/fbst.out" "^final base: feat/x$"`.
  - `test_lanes_final_base_sync_uses_base`: `LANES_TASKS=2`, `lanes_fixture fbsync integration A:-`, `base_branch feat/x`, `mf_set_base feat/x`. `$SCEN/A` = `push_target other.txt; push_ref feat/x base2.txt` on line 1 and `probe` on line 2.
    - `assert_eq "chore(sync): merge origin/integration/demo into A-b|chore(sync): merge origin/feat/x into A-b" "$(sync_merges A)"`.
    - `assert_contains events.jsonl '"refs":\["origin/integration/demo","origin/feat/x"\]'`.
  - `test_lanes_final_base_conflict_repair` (Review Focus 2): `lanes_fixture fbcf integration A:-`, `base_branch feat/x`, `mf_set_base feat/x`. `$SCEN/A` = `conflict shared.txt\nauto\npush_ref feat/x shared.txt`; `$SCEN/final-repair` = `mergemain`.
    - `_n="$(prompt_calls '/omega:integration repair demo')"`: exactly one call.
    - `assert_contains "$CALLS/$_n.env" "^STUDIO_REPAIR=conflict$"`.
    - `assert_contains "$CALLS/$_n.fullenv" "^STUDIO_FINAL_BASE=feat/x$"`.
    - The integration head descends from origin/feat/x. `.studio/runs/demo/final` matches ` green feat/x$`.
  - The "no `final base:` line" check goes into `test_lanes_final_base_absent_identical`: run `status` and `assert_not_contains … "^final base: "`.
  - In `integration_contract.sh`: `assert_contains "$S" 'STUDIO_FINAL_BASE' "repair merges the run's Final base when set"`.
- [ ] **Step 3: Run, expect FAIL.**

  ```sh
  RUN overnight_lanes_test "test_lanes_final_base_opens_pr_into_it test_lanes_final_base_sync_uses_base test_lanes_final_base_conflict_repair test_lanes_final_base_absent_identical"
  RUN omega_test test_skill_contracts
  ```

  Expected: `--base main` everywhere, sync merges origin/main, the repair env has no `STUDIO_FINAL_BASE`, and the contract misses the text.
- [ ] **Step 4: Implement.**
  - `final_pr_open`: the comment becomes `BRANCH [BASE] — … into BASE (default: the default branch)`, and the call uses `--base "${2:-$DEFAULT_BRANCH}"`.
  - L:1810: `_fi_m="origin/$MF_BASE"`.
  - L:1819 and L:1910: `final_pr_open "$_fi_b" "$MF_BASE"`.
  - L:1915: `--base "$MF_BASE"`.
  - L:1845: `_fi_fb=""; [ "$MF_BASE" = "$DEFAULT_BRANCH" ] || _fi_fb=" STUDIO_FINAL_BASE=$(sq "$MF_BASE")"`, then `final_unit final-repair "/omega:integration repair $MF_SLUG" "STUDIO_REPAIR=$(sq conflict)$_fi_fb"`.
  - L:783: `_sy_refs="origin/$MF_TARGET"; [ "$MF_TARGET" = "$MF_BASE" ] || _sy_refs="$_sy_refs origin/$MF_BASE"`. In direct mode `MF_BASE` = the default branch = `MF_TARGET`, so nothing changes. Update the `sync_check` header comment.
  - L:1401: when `FINAL_PR` is set and `[ "$MF_BASE" != "$DEFAULT_BRANCH" ]`, print `'Final PR: %s (%s) into %s\n'`; else today's line.
  - `lanes_status_lines`, just before `gate_line "$RUN_DIR"`: `[ "$MF_BASE" = "$DEFAULT_BRANCH" ] || printf 'final base: %s\n' "$MF_BASE"`. Add it to the function's header comment.
  - IN :80-83: "opens the one draft PR into `main` (the manifest's `Final base:` when it names one)".
  - IN :91-94 `conflict`: "Run `git merge --no-edit origin/$STUDIO_FINAL_BASE` when `STUDIO_FINAL_BASE` is set (the run's `Final base:`), else `git merge --no-edit origin/main` (the default branch)…; done means … that ref an ancestor of `HEAD`".
  - Keep `origin/main` in IN (`integration_contract.sh:13`), and never edit `## Story flow` (its shasum is pinned at :19).
- [ ] **Step 5: Run, expect PASS.** Run the Step 3 commands, plus `test_lanes_final_conflict test_lanes_final_step_once test_lanes_sync_integration_two_refs test_lanes_sync_clean_merge_no_session test_lanes_direct_progress_landing test_lanes_report_every_ending`.
- [ ] **Step 6: Commit.** `feat(#81): the final PR, final merge and story sync use the run's Final base`

### Task 4: #81 — `RECORD/final` names the base; a changed base refuses on resume — **Risky** (data format, resume)

**Files:**
- Modify: `L:1816-1823` (step 0).
- Modify: `L:1920-1923` (step 6).
- Modify: `L:1496-1503` (`lanes_load_run` read).
- Modify: `L:1793` (comment: `RECORD/final = <head> <url> <color> [<base>]`).
- Test: T, after Task 3's tests.

**Interfaces:**
- `RECORD/final` = `<head> <url> <color>` when `MF_BASE` = the default branch (as today), else `<head> <url> <color> <base>`.
- A 3-field record means the default branch. That covers records written before this change, so no migration is needed (spec §13 lean).

- [ ] **Step 1: Failing tests.**
  - `test_lanes_final_base_resume_unchanged_is_done` (Review Focus 3): `base_branch feat/x`, `mf_set_base feat/x`, and `use_gate "echo gate >> '$CALLS/final-gates'"`. Then run (done), `rm -f "$P/.studio/runs/demo/done"`, `next_second`, and run again.
    - `assert_contains .studio/runs/demo/final "^[0-9a-f]* https://gh.test/pr/1 green feat/x$"`.
    - The second run: `assert_eq 0 "$LS_STATUS"` (done, so the color parsed as `green`).
    - `assert_eq 1 "$(final_gates)"`.
    - `assert_eq 1 "$(grep -c '^pr create ' "$GH/calls")"`.
    - `use_gate true`.
  - `test_lanes_final_base_changed_on_resume_refused`: the same first run with `feat/x`, then `rm done`. Remove the line (`sed '/^Final base:/d'`, committed and pushed), `next_second`, and run again.
    - `assert_eq 1 "$LS_STATUS"`.
    - `assert_contains report.md "^Final note: .*final base changed since the last final step (feat/x → main) — close PR https://gh.test/pr/1 or restore the field"`.
    - `assert_eq 1 "$(grep -c '^pr create ' "$GH/calls")"` (no second PR).
    - `.studio/runs/demo/final` still ends ` feat/x`.
  - `test_lanes_final_base_changed_after_close_proceeds` (Review Focus 4): first run with no field (a 3-field record, PR 1 into main), then `rm done`. Then `printf 'state=CLOSED\n' >> "$GH/pr-1"`, `base_branch feat/x`, `mf_set_base feat/x`, `next_second`, and run.
    - `assert_eq 0 "$LS_STATUS"`.
    - `assert_eq 1 "$(grep -c '^pr create --draft --base feat/x ' "$GH/calls")"`.
    - The record ends `https://gh.test/pr/2 green feat/x`.
- [ ] **Step 2: Run, expect FAIL.**

  ```sh
  RUN overnight_lanes_test "test_lanes_final_base_resume_unchanged_is_done test_lanes_final_base_changed_on_resume_refused test_lanes_final_base_changed_after_close_proceeds"
  ```

  Expected:
  - a 3-field record;
  - a second PR into main where the base was removed;
  - after the close, the new PR does open (Task 3), but the record lacks the base.
- [ ] **Step 3: Implement step 0 (full).**

```sh
  if [ -f "$RECORD/final" ]; then
    _fi_rs=""; _fi_ru=""; _fi_rc=""; _fi_rbs=""
    read -r _fi_rs _fi_ru _fi_rc _fi_rbs < "$RECORD/final"
    _fi_rbs="${_fi_rbs:-$DEFAULT_BRANCH}"     # #81: a 3-field record is the default branch
    if [ "$_fi_rbs" != "$MF_BASE" ]; then
      # The base changed between runs: the old PR (into the old base) would be
      # missed by the lookup below and a second PR opened. Refuse while it is open.
      final_pr_open "$_fi_b" "$_fi_rbs"
      case $? in
        0) FINAL_COLOR=red
           final_note "final base changed since the last final step ($_fi_rbs → $MF_BASE) — close PR $FP_URL or restore the field"
           return 1 ;;
        1) ;;                                   # closed or merged: the new base gets its own PR
        *) FINAL_COLOR=red; final_note "gh pr list failed"; return 1 ;;
      esac
    elif [ "$_fi_rs" = "$_fi_h0" ] && final_pr_open "$_fi_b" "$MF_BASE" && [ "$FP_URL" = "$_fi_ru" ]; then
      FINAL_PR="$_fi_ru"; FINAL_COLOR="${_fi_rc:-red}"; final_note "unchanged since the last final step"
      return 0
    fi
  fi
```

- [ ] **Step 4: Implement step 6 and the reader.**
  - Step 6: `if [ "$MF_BASE" = "$DEFAULT_BRANCH" ]; then printf '%s %s %s\n' "$_fi_h" "$FINAL_PR" "$FINAL_COLOR"; else printf '%s %s %s %s\n' "$_fi_h" "$FINAL_PR" "$FINAL_COLOR" "$MF_BASE"; fi > "$RECORD/final"`.
  - `lanes_load_run`: `read -r _lr_s _lr_u _lr_c _lr_b < "$RECORD/final"`. `_lr_b` is unused: it only keeps the color clean.
- [ ] **Step 5: Run, expect PASS.** Run the Step 2 command, plus `test_lanes_final_base_absent_identical test_lanes_final_step_once test_lanes_final_resume_edits_pr test_lanes_final_gate_interrupted_not_recorded test_lanes_reap_names_final_pr` (T:2338ff: the reaped report reads the record through `lanes_load_run`).
- [ ] **Step 6: Commit.** `feat(#81): RECORD/final names a non-default base; a changed base refuses while its PR is open`

### Task 5: Docs and skill text — #81 field, #73 note — **Mechanical**

**Files:**
- Modify: `AP:94-104` (template line, and one sentence after the block).
- Modify: `AP:166` (integration push from the base).
- Modify: `X:703-704` (the lane note).
- Modify: `O:406-411` (help: the modes block names `Final base:`).
- Modify: `O:299-312` (help: the #73 paragraph in `start --detach`).
- Modify: `README.md:127-129` (#73 bullet).
- Modify: `README.md:137-139` (integration names `Final base:`).
- Test: `tests/omega_contracts/autopilot_contract.sh` (inside `test_autopilot_contract`, before :177).
- Test: `tests/studio_test.sh` `test_execute_lanes` (:533ff).
- Test: OT, a new `test_help_final_base_and_direct_detach` (appended to `run_tests` at OT:2671ff).
- No `docs/game-dev/overnight-events.md` change: it lists events only (:103-109), not status or report lines.

- [ ] **Step 1: Failing tests.**
  - autopilot contract:
    - `assert_contains "$S" '^ *Final base: <branch> *# optional' "the manifest template names the optional Final base"`;
    - `assert_contains "$S" 'origin/<Final base>:refs/heads/integration/<slug>' "integration is pushed from the Final base when set"`;
    - keep :56's `origin/<default>:refs/heads/integration/<slug>`.
  - studio_test `test_execute_lanes`: `assert_contains "$E" 'A manifest.s `Final base:` is the runner.s' "a lane unit never targets the Final base"`.
  - OT `test_help_final_base_and_direct_detach`:
    - `out="$(sh "$RUNNER" --help 2>&1)"`;
    - help contains `Final base: <branch>`;
    - help contains `moved since start --detach checked it`;
    - help contains `use integration mode`;
    - `assert_contains "$REPO_ROOT/README.md" 'moved since start --detach checked it'`;
    - `assert_contains "$REPO_ROOT/README.md" 'Final base:'`.
- [ ] **Step 2: Run, expect FAIL.**

  ```sh
  RUN omega_test test_skill_contracts
  RUN studio_test test_execute_lanes
  RUN overnight_test test_help_final_base_and_direct_detach
  ```
- [ ] **Step 3: Edit.**
  - **AP template**, after the `Target:` line: `Final base: <branch>         # optional (integration only): the final PR's base; omit for the default branch`.
  - **AP, after the block:** "Write `Final base:` only when the user named a branch the run must land in, other than the default branch; it must exist on origin. Without it, the final PR goes into the default branch."
  - **AP :166:** after the push command, add "(with a `Final base:`, `git push origin origin/<Final base>:refs/heads/integration/<slug>` instead)".
  - **X lane note**, after "the base is `origin/<Target>`:": "A manifest's `Final base:` is the runner's: it sets the final PR's base and what the final step merges, never a unit's base or PR."
  - **O modes block:** the integration line becomes "… one draft PR integration -> main, or into the branch an optional `Final base: <branch>` header names (integration only)…".
  - **O `start --detach` help**, a paragraph at the end. It is a single text (shared by help and README):

    > In direct mode the setup check is tied to origin/<Target>, the default branch. A push to it during the check (15–20 min) makes the child refuse with "origin/<Target> moved since start --detach checked it". Re-run start --detach, start in the foreground, or use integration mode, where only the run pushes its Target.
  - **README:** the same text as one bullet under the `--detach` bullet (:127-129). In the modes bullet (:137-139), "opens one draft PR into `main` (or into the manifest's `Final base:` branch)".
- [ ] **Step 4: Run, expect PASS.** Run the Step 2 commands, plus `RUN overnight_test "test_overnight_help test_help_names_concurrent_runs"`.
- [ ] **Step 5: Commit.** `docs(#81,#73): Final base: in the autopilot template, help and README; the direct --detach refusal and its workaround`

### Task 6: Rebase, affected suites, exact floors — **Mechanical**

- [ ] **Step 1:** `git fetch origin`, then merge the latest `origin/integration/backlog-2026-10-21` into `issue-82-runner-config`. S2, S3, S4 and S6 land first (spec §11). Resolve L/O/T conflicts by relocating the hunks with their anchors. A `tests/run_all.sh` floors conflict takes the integration side, and Step 3 recomputes it.
- [ ] **Step 2:** `cd <W> && sh tests/run_affected.sh --base origin/integration/backlog-2026-10-21 --list`. Then run it without `--list`, from `<S>` with `TMPDIR=<S>/tmp`, as one background run.
  - Expected suites: at least `overnight_lanes_test`, `overnight_test`, `omega_test`, `studio_test` and `pointer_skills_omega_test`.
  - Also run every suite the list adds (the studio-overnight closure: `overnight_runs_test`, `overnight_progress_test`, `overnight_ids_test`, `studio_adopt_test`, …).
  - Then run the same under `TEST_SH=dash`. Everything is green.
  - If `harness_test`'s exclusive scan flags a new test, add it to T's `TESTS_EXCLUSIVE`.
- [ ] **Step 3:** commit any fix. With a clean tree, run `sh tests/run_all.sh --update-floors` (spec §5.4 item 2, or the exact floor step the S2 plan defines). It rewrites the floors of the suites the last run counted. Check the diff: only the touched suites' floors change. Commit `chore(tests): exact floors for S1 (#82, #81)`.
- [ ] **Step 4:** hand back with the PR body notes: the falsified rows this story relied on, re-checked at its own base (spec §13).

## Falsified assumptions (planner falsify clause, checked at 1cfca7f)

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | `STUDIO_START_DIR` is exported only for units | true | O:1321 is the only export; the readers are gate-class.sh:27, cfg.sh:14 and studio-adopt:170-188 |
| 2 | O:564 sets `START_DIR` for every verb, and detach strips then re-derives it | true | O:564; O:1655-1659 |
| 3 | The runner's gate launches are only `final_gate` and the direct land | true | L:1729 and L:637 are the only `studio-gate` execs in L/O; studio-setup at L:1856, L:1953 and O:1952 |
| 4 | `studio_cfg` ignores an empty `STUDIO_START_DIR` and prefers the tree per key | true | gate-class.sh:22-32 (`[ -z "$_sc_v" ] && [ -n "${STUDIO_START_DIR:-}" ]`) |
| 5 | The runner never runs studio-adopt (which reads `STUDIO_START_DIR`) | true | L:1433 only prints the command in the report |
| 6 | `lanes_reap` launches nothing gated | true | L:1522-1530: `lanes_sweep`, `lanes_report` |
| 7 | FINAL_W has no run config in the fixture | true | config is committed on run/demo only (T:607, T:641); integration/demo is cut from origin/main (T:646). T1 asserts it |
| 8 | The merge program inherits studio-gate's env | true | no `unset STUDIO_START_DIR` in bin/studio-gate; it is exec'd at L:637 |
| 9 | Spec test `test_lanes_unit_env_unchanged` is new coverage | **partly false** | `test_lanes_units_get_start_dir` (T:3838-3844) already pins the line. T1's version adds the stray-value case |
| 10 | Adding a 4th field to `RECORD/final` is safe for its readers | **false** | both readers use `read -r a b c` (L:1500, L:1818), so the color becomes `green feat/x` and `final_ok` (L:1310) fails. Existing tests pin ` green$`/` red$` (T:1853, T:1896 …). → T4 reads 4 vars, and writes the field only when non-default |
| 11 | The integration repair merges whatever the runner merges | **false** | IN:91-94 hard-codes `origin/main`; the runner checks `merge-base --is-ancestor "$_fi_m" HEAD` (L:1847-1848). → T3 adds `STUDIO_FINAL_BASE` and the IN text. The spec §4.2 file list omits IN |
| 12 | X §7 step 4 has a lane PR whose base is the Final base | **false** | integration lanes open no PR (X:704-731, "opens no PR"); direct opens into the default branch (X:732-733), and the field is refused in direct. → T5 adds one clarifying sentence only |
| 13 | overnight-events.md lists status or report lines | false | events only (:103-109). → no change |
| 14 | `mf_load` always runs with `DEFAULT_BRANCH` set | **false** | `next` (L:2137) and `check-id` (O:2302) call it without preflight, under `set -u` (O:23). → `${DEFAULT_BRANCH:-}` |
| 15 | The base existence check can follow the origin fetch | true | the fetch is at L:216; the integration-branch check at L:228-231 |
| 16 | `lanes_load_run` sets `DEFAULT_BRANCH` before `MF_BASE` can use it | true | L:1491-1494 |
| 17 | The final PR line is L:1401, not L:1449 | true | spec F4; L:1443-1452 are the bundle-2 story PRs |
| 18 | The gh stub filters `pr list` by `--base` | true | T:446-455 |
| 19 | The stub records every unit's full env | true | T:188 (`env > $n.fullenv`) |
| 20 | `use_gate` text runs inside the real `studio-gate final-gate` in FINAL_W | true | L:1713-1729; default `true` at T:526 |
| 21 | The default/Target refusal text is pinned exactly | true | T:779 → the suffix is added only with a field |
| 22 | The contract pins survive the edits | true | autopilot_contract.sh:56 (`origin/<default>:refs/heads/integration/<slug>`) is kept; integration_contract.sh:13 (`origin/main`) is kept; the :19 shasum covers `## Story flow` only, which is untouched |
| 23 | The help strip text is unpinned | true | no test greps "is removed" or "PATH stay" (grep tests/) |
| 24 | `run_tests` names every test explicitly | true | T:4871ff, OT:2671ff, studio_test:854: append each new name |
| 25 | `TESTS_ONLY` selects tests | true | assert.sh:236 |
| 26 | `progress_direct` and the bundle-2 report keep the default base | true | L:1964 and L:1447 call `final_pr_open` with one arg → the default |
| 27 | The suite strips `STUDIO_*` at source, so a test sets the stray value itself | true | assert.sh:17-19 |

## Manual acceptance

- After the integration PR merges and the operator reinstalls, check the next live phoenix run with `test_engine_args` set. Its final gate's `studio-test` log has `--fixed-fps 60`: grep `RUN_DIR/final-gate.log` or the test log for `stub godot args`/`--fixed-fps`.
- A `Final base:` run's draft PR opens into that branch. This is optional: it needs a real feature-branch run (as bashful-bat-bite). It is not required for the merge.

## Self-review

- **Spec coverage.**
  - §4.1: the design → T1; every audit row is covered by the one export (O:1321 unchanged); the secondary → T1's comment; the acceptance tests → T1 (4 tests).
  - §4.2: grammar → T2; variables → T2; every touch-point row → T3 (L:1734-1741, L:1810, L:1819, L:1910, L:1915, L:783, L:1401, status) or T2 (L:230, L:178); docs → T5; unchanged rows → Global Constraints.
  - The failure modes: a changed base → T4; a deleted base → the existing red path, unchanged; an absent field → T2's golden.
  - Every acceptance test is named in T2-T4; the contract → T5.
  - §4.3 → T5.
  - §13's 4th-field migration → T4: a 3-field record means the default branch.
- **Names.** These are used alike across tasks:
  - `MF_BASE`, `mf_base_check`, `final_pr_open BRANCH [BASE]`, `STUDIO_FINAL_BASE`, `_fi_rbs`;
  - `base_branch`, `mf_set_base`, `gnorm`, `push_ref`.
- **Review Focus.** Five items, each pinned in its owning task.
- **Proportion.** Full code is given only for `mf_base_check`, step 0 and the test bodies of T1/T2. The rest is signatures and assertions.
