# `start --detach` lock window (#70) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `start --detach` starts large manifests: fast id checks, one studio-state call per story, a window that waits for the lock, and a preflight token that skips only manifest-pure checks.

**Architecture:** POSIX sh changes in `studios/game-dev/bin/{overnight-ids.sh,overnight-lanes.sh,studio-overnight}`, plus shell tests in `tests/`. Two waves: T1, T2 and T3 touch disjoint files or regions and run in parallel; T4 builds on T2 and T3.

**Tech Stack:** POSIX sh, awk, git, perl (setsid); the tests use `tests/assert.sh`.

**Spec:** `docs/game-dev/specs/2026-10-19-detach-lock-window.md`

## Global Constraints

- POSIX sh only (no bash-isms). Keep the file's comment density and naming (`_xx` locals per function).
- Every refusal and message text not named in the spec stays byte-identical.
- Test hooks are read before detach's STUDIO_* strip and documented in usage's "Test hooks" block.
- Run suites with the cwd in a scratch dir outside every repo, `TMPDIR` set to a checked-to-exist dir in the same command, and never `rm -rf` outside the scratch area.
- One suite run at a time per agent: start it with run_in_background and wait for the notification. Never stack poll loops.
- A whole test file of overnight_lanes_test.sh or overnight_ids_test.sh, or tests/run_all.sh, takes `mkdir /Users/xinli/GameDev/proj/omega-ai/.git/heavy-suite.lock` (with an owner file; remove it after), and needs `cd /tmp && studio-overnight status` to show no phoenix final gate (run-tests.sh / merge.sh) running. `TESTS_ONLY=` single-test runs need neither.
- Commit only your own files: `git commit -- <paths>`.

## Review Focus

1. The id index serves a stale view after a record changes in the same shell: `ids_index` is keyed on (STATE_ROOT, SLUG, D) and built at most once per `ids_check` call, never cached across calls (T1 test `test_ids_index_not_reused_across_calls`).
2. Equality of the ids output when one id is taken by several sources at once: rule order and first-match messages (T1 `test_ids_multi_source_manifest`).
3. A child that exits non-zero quickly while the cap is large: it must report "did not start" at once, not after 120 s (T3 `test_lanes_detach_child_exit_fast_under_long_cap`).
4. The token leaking into unit sessions or into a later `start` (T4 `test_lanes_preflight_token_not_passed_to_units`).
5. Token collisions between different manifest paths with the same bytes (T4 `test_lanes_preflight_token_binds_path`).

---

### Task 1: ids index (#57)

**Files:**
- Modify: `studios/game-dev/bin/overnight-ids.sh` (ids_reasons 61-105, ids_check 136+, ids_suggest)
- Test: `tests/overnight_ids_test.sh`

**Interfaces:**
- Produces: `ids_index SLUG D`, which sets shell variables in the caller's shell (prefix `_ix_`). The existing `ids_check`/`ids_reasons`/`ids_suggest` keep their signatures and output.
- Reference prototype (scratch, NOT to be copied blindly): `/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/9d80466c-a1b9-4721-a648-c5095a53140b/scratchpad/profile/ids-proto.sh`. Comparison harness: `diff.sh`, `diff2.sh` in the same dir.

- [ ] Step 1: add the tests below. They must PASS on the current code, since they pin behavior.
  - `test_ids_multi_source_manifest`: a manifest with three ids. One is taken by a main ledger, one by an `origin/integration/*` ledger, and one by a run record. Assert that each refusal line matches the current text exactly.
  - `test_ids_suggest_skips_record_taken_candidate`: a taken id whose first suggestion candidate is held by a run record. Assert the suggestion skips it.
  - `test_ids_index_not_reused_across_calls`: two `ids_check` calls in one shell, with a run record added between them. Assert the second call sees the record.
- [ ] Step 2: run `overnight_ids_test.sh` on the current code. Expected: all pass.
- [ ] Step 3: implement `ids_index`, and make `ids_reasons`/`ids_suggest` answer from it. Use one awk per id, with no per-id `git ls-tree` and no per-id record reads. Use `git show` only for a main ledger that matches the id, as today.
- [ ] Step 4: run `overnight_ids_test.sh` (whole file, under the lock rules) and `TESTS_ONLY` for the `test_lanes_ids_*` tests in `overnight_lanes_test.sh` (lines ~3845-4052). Expected: all pass.
- [ ] Step 5: measure. Run the profile harness's comparison, or time `ids_check` on phoenix's 7 manifest ids READ-ONLY, before and after. Report the numbers.
- [ ] Step 6: commit `-- studios/game-dev/bin/overnight-ids.sh tests/overnight_ids_test.sh`.

### Task 2: one studio-state call per story in mf_check

**Files:**
- Modify: `studios/game-dev/bin/overnight-lanes.sh`, mf_check's per-story block only (~245-271). Touch no other function. No test file edits: existing stage tests cover it.

- [ ] Step 1: read lanes:245-271 and `studio-state show`'s output format. Confirm that `show` prints the stage, in the exact form `get stage` returns.
- [ ] Step 2: take the stage from the captured `show` output. Keep each refusal's text and order.
- [ ] Step 3: run `TESTS_ONLY` over every test in `tests/overnight_lanes_test.sh` whose name or body hits the stage/ledger refusals. Find them with `grep -n "stage\|plan approved\|Decisions swept"`. Expected: pass.
- [ ] Step 4: commit `-- studios/game-dev/bin/overnight-lanes.sh`.

### Task 3: the detach window waits for the lock

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight`: detach_start (~1600-1690), the knob area (~535-547), the usage Test hooks block (~495-512), and detach_start's header comment.
- Test: `tests/overnight_lanes_test.sh` detach tests (~2354-2500) and the run_tests list (~4756+).

**Interfaces:**
- Produces: `DETACH_WAIT` (whole seconds, default 120). It is set from `STUDIO_OVERNIGHT_DETACH_WAIT_SECONDS` (whole number 1-3600, else `say` + exit 2) at the knob area, so the strip can't drop it.

- [ ] Step 1: tests.
  - `test_lanes_detach_slow_child_takes_lock`: a stand-in child (`STUDIO_OVERNIGHT_DETACH_CHILD_CMD`) that sleeps ~15 s, then writes the run lock in the format `take_lock` writes, with its own pid (the setsid'd `sh -c` is `$_dpid`), then sleeps. `STUDIO_OVERNIGHT_DETACH_STATUS_CMD=true`. Assert exit 0, `detached: pid`, and that the elapsed time is ≥ 15 s. Clean up with the existing detach_stop/end_hung helpers. Put it in the real-clock list.
  - `test_lanes_detach_child_exit_fast_under_long_cap`: the child is `exit 3` with the default cap. Assert exit 3, "did not start", elapsed < 10 s.
  - `test_lanes_detach_wait_rejects_bad_value`: values `0`, `abc`, `3601` each give exit 2.
  - Update `_timeout_lock_held_points_at_status`, `_timeout_no_lock_ends_child` and `_poll_keeps_budget` to set `STUDIO_OVERNIGHT_DETACH_WAIT_SECONDS=10`. Keep their assertions: "is live … in 10 s", "never took the lock", no survivor, ≥10 s, 50 status calls.
- [ ] Step 2: run the new and updated tests with `TESTS_ONLY`. Expected: slow_child FAILS (it is killed at 10 s); the rest fail or pass as expected.
- [ ] Step 3: implement. The loop bound is `DETACH_WAIT * DETACH_TPS`; the "is live" message names `${DETACH_WAIT} s`; and the new hook is documented in usage.
- [ ] Step 4: run `TESTS_ONLY` over every detach test (`grep -n "test_lanes_detach\|test_lanes_origin_detach\|runner_argv_names_tmp"`). Expected: pass.
- [ ] Step 5: commit `-- studios/game-dev/bin/studio-overnight tests/overnight_lanes_test.sh`.

### Task 4: preflight token (after T2 and T3 are committed)

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight`: a new `pf_token`, detach_start (take it before and after, pass it via `env`), the usage Environment block, and the start path read-and-unset.
- Modify: `studios/game-dev/bin/overnight-lanes.sh`: lanes_start/mf_check honor `PF_SKIP` (set when the token matches) by skipping exactly the spec's skippable list.
- Test: `tests/overnight_lanes_test.sh`.

**Interfaces:**
- `pf_token MANIFEST_ABS` prints a lowercase 64-hex sha-256 of `omega-pf-v1`, path, manifest bytes and config bytes, each part length-prefixed. Use `shasum -a 256` (macOS) with a `sha256sum` fallback. If neither exists it prints nothing, and an empty token never passes or matches.
- The child reads `STUDIO_OVERNIGHT_PREFLIGHT_CHECKED` once and unsets it before `preflight manifest` runs. It sets `PF_SKIP=1` only when the variable equals `pf_token` of the same absolute manifest. Messages are verbatim from the spec.

- [ ] Step 1: tests.
  - `test_lanes_detach_passes_preflight_token`: the child CMD dumps its env. Assert `STUDIO_OVERNIGHT_PREFLIGHT_CHECKED=<64 hex>` is present and equals `pf_token`.
  - `test_lanes_detach_token_dropped_when_manifest_changed`: the manifest is edited between the parent's two reads. Use a worktree_setup stub that appends to the manifest, the same way the setup-preflight tests (~4460-4540) stub studio-setup. Assert the variable is absent from the child's env.
  - `test_lanes_preflight_token_skips_static_checks`: a plain `start` with a matching token. Assert the log has `manifest checks: done by start --detach at`, and that ids_check and mf_conflicts still ran. Use a manifest whose id is taken by a run record: still refused.
  - `test_lanes_preflight_token_stale_runs_full_check`: an all-zero token. Assert `manifest changed since start --detach checked it — checking it again`, and that a static refusal (e.g. a bad slug introduced after the token was taken) still fires.
  - `test_lanes_preflight_token_binds_path`: the same bytes at a different path. Assert no skip.
  - `test_lanes_preflight_token_not_passed_to_units`: as `test_lanes_setup_checked_env_binds_to_sha` does for SETUP_CHECKED. The variable is absent from `$CALLS/1.fullenv`.
- [ ] Step 2: run them with `TESTS_ONLY`. Expected: FAIL.
- [ ] Step 3: implement. Before skipping each check, confirm (and say in the commit message) that later code reads none of its side effects.
- [ ] Step 4: run `TESTS_ONLY` over all detach, setup-checked and token tests, plus the mf_check refusal tests. Expected: pass.
- [ ] Step 5: commit.

### Final (controller)

- [ ] Whole-branch review (Opus, standalone).
- [ ] Full gate: `tests/run_all.sh` under the heavy-suite lock.
- [ ] Measure `mf_check` CPU on phoenix's combat-vfx-library manifest, read-only, the way the profile did, and record it in the PR.
- [ ] PROGRESS.md entry. Close #57 with the measurement.
