# Unit deadline, checkpoint carry-over and the capped-task bound — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An overnight unit knows its deadline, leaves a checkpoint the retry reads, gets credit for pushed work, and a task that keeps hitting the cap reaches a person with that checkpoint. Plus defects 3 and 5-11 of the source prompt.

**Architecture:** The runner (`studio-overnight`, `overnight-lanes.sh`) exports the deadline and judges outcomes. The PostToolUse hook nudges the session at wrap-up time. The ledger carries the agent's checkpoint, and `studio-brief` feeds it to the retry. The operator channel gains task-scoped and file-sourced directives. The skills (execute, plan) carry the agent-side rules.

**Tech Stack:** POSIX sh (macOS `/bin/sh`, BSD userland; no jq in runner code), awk, git; Python 3 for the Multica bridge; tests are the repo's sh suites (`tests/assert.sh`, `run_tests`, `TESTS_ONLY="a b"`).

**Spec:** `docs/game-dev/specs/2026-10-26-unit-deadline-and-carryover.md` (approved 2026-10-26; decisions D1-D7, calls C1-C6). Read it first.

## Global Constraints

- Work only in worktrees of branch `fix/overnight-timeout-carryover` (main worktree `../omega-ai-wt-timeout`). Never pull, merge or install into `/Users/xin/game-dev/proj/omega-ai` or `~/.claude-gamedev`. Never touch `/Users/xin/game-dev/proj/phoenix` (a live run reads the installed plugin).
- POSIX sh only in `studios/game-dev/bin` and `hooks`: no bashisms, no jq, `LC_ALL=C` where bytes matter, `set -u`-clean.
- Margin: WRAP_AT = DEADLINE − max(600, secs / 6) s, never more than secs / 2 (D3).
- `overnight.task_timeouts`: default 2, range 1-5, int (D4).
- Checkpoint ledger line: `T<n> checkpoint: done …; left …; next …` (`final-review checkpoint: …` for the final review). Never the words `in progress` (studio-adopt's).
- Task-scoped directive ledger line: `Directive <id> T<n>: <text>`. It is active while the story's task pointer k < n.
- units.tsv: columns 1-7 unchanged; col 8 `cost_src` = `result`|`estimate`; col 9 `capped` = 0|1 (C5). Never write `unknown` in col 4 again.
- New outcome word `partial` (capped unit whose own pushed commits exist, C1/C4).
- Endings keep their prefixes so existing readers (holdable, Multica bridge, tests) still match: the bound's ending is `timed out on T<n> (session_minutes N; <k> capped units) — checkpoint: <text>`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The existing suites stay green: `sh tests/run_all.sh` (or `sh tests/run_affected.sh` while iterating), `tests/omega_contracts/*`, `integrations/multica/tests/run.sh`.

## Review Focus

1. **A unit that never writes a checkpoint** (ignores the nudge, or is killed mid-gate): the runner fallback note must still reach the retry, and the hold must still name something useful. Pinned in Task 5 (`test_lanes_fallback_note_without_checkpoint`).
2. **Small `STUDIO_OVERNIGHT_SESSION_SECONDS` in existing tests** (1, 6, 10 s): WRAP_AT arithmetic must not mark ordinary short units `capped` or break the existing timeout and idle tests. Pinned in Task 1 (`test_overnight_deadline_small_session`) and by the full suites in Task 5.
3. **A resumed hold on a bounded task**: after `resume`, exactly one more capped unit runs, then it holds again. Pinned in Task 5 (`test_lanes_bound_resume_one_more`).
4. **Multi-line and quote-laden directive text** (`'`, `\`, `$`, a tab, a blank line) round-trips through `say --file` → .msg → delivery → ledger → studio-brief. Pinned in Task 3 (`test_channel_say_file_verbatim`).
5. **A killed unit with an empty or garbled transcript**: the cost estimate falls back to minutes × $/min, and is never empty, `unknown` or 0 when the run has a basis. Pinned in Task 2 (`test_overnight_cost_estimate_empty_transcript`).

## Execution order (waves; tasks in a wave run in parallel worktrees, landed in the order listed)

- Wave A: Task 1, Task 2, Task 3, Task 4.
- Wave B: Task 5 (needs 1, 2, 3), Task 6 (needs 1), Task 7 (needs 3), Task 8 (needs the names fixed here).
- Wave C: Task 9.

Every task adds its test names to its suite's `run_tests` list. Merge conflicts on that list are expected and resolved by keeping both.

---

### Task 1: Deadline exported to every unit; `studio-deadline`; `--help` stderr fix

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight` — `run_unit` (~L1665: compute `_secs` before `start_session`), `start_session` (~L1647: export the two vars), `usage()` heredoc (~L295-590: document the vars; escape `` `sh -c "$CMD"` `` at ~L551)
- Create: `studios/game-dev/bin/studio-deadline`
- Modify: `tests/overnight_test.sh` (stub records `$CALLS/$n.deadline`), `tests/overnight_lanes_test.sh` (the lanes stub records the same)
- Create: `tests/studio_deadline_test.sh`

**Interfaces:**
- Produces: env `STUDIO_UNIT_DEADLINE` (epoch s) and `STUDIO_UNIT_WRAP_AT` (epoch s) in every session that `start_session` launches (task, check, final-review, finish, land repair, gate repair, sync repair, final units). Shell vars `UNIT_DEADLINE`, `UNIT_WRAP_AT` are set in `run_unit` for the runner's own use after the unit (Task 5).
- Produces: `studio-deadline` → stdout `left <m> min · wrap at <HH:MM> (<m> min) · hard stop <HH:MM>` or `no deadline`, exit 0. `studio-deadline fits <who|agent> [<minutes>]` → exit 0 `fits: <who> ~<m> min, <m> min to wrap` / exit 1 `does not fit: <who> ~<m> min, <m> min to wrap at <HH:MM>`. The estimate is p90 × 1.2 of `gate_times_holds <STATE_ROOT>/.studio/gate.times <who>` (source `gate-times.sh`), else `<minutes>`, else `STUDIO_GATE_MINUTES / 2` with fewer than 5 rows; `agent` = `${STUDIO_DEADLINE_AGENT_MIN:-20}`. Outside a unit, `fits` exits 0 (`no deadline`).

- [ ] **Step 1: Write the failing tests.** In `overnight_test.sh`, the stub writes `printf '%s %s\n' "${STUDIO_UNIT_DEADLINE:-unset}" "${STUDIO_UNIT_WRAP_AT:-unset}" > "$CALLS/$n.deadline"`. Tests:
  - `test_overnight_deadline_exported`: a 2-unit run (`ISO1`, then a finish). For each call, deadline − t0 is within 2 s of the session seconds (`STUDIO_OVERNIGHT_SESSION_SECONDS=120`), and WRAP_AT = deadline − 60 (120/2 caps max(600, 20)).
  - `test_overnight_deadline_small_session`: `SESSION_SECONDS=1`, WRAP_AT = deadline (1/2 = 0 margin, integer).
  - `test_help_exits_clean`: `sh "$RUNNER" --help` exits 0, its stderr is empty, and stdout names `STUDIO_UNIT_DEADLINE`, `STUDIO_UNIT_WRAP_AT` and `studio-deadline`.
  - In `overnight_lanes_test.sh`, `test_lanes_deadline_every_unit_kind`: a run with a red finish gate (gate repair), a sync repair and a landing repair (reuse the fixtures of `test_lanes_gate_repair*` / `test_lanes_land_repair*`). Every `$CALLS/<n>.deadline` is non-`unset`.
  - In `studio_deadline_test.sh`: `no deadline` outside a unit; `left`/`wrap` text with fixed `STUDIO_UNIT_DEADLINE=$(( now + 3600 ))` and `WRAP_AT=$(( now + 2700 ))`; `fits studio-test` exits 0 with 6 rows of 300 s, and exits 1 when WRAP_AT is now + 300; `fits agent` exits 1 at WRAP_AT − now = 900 (20 min > 15); `fits studio-test` with 2 rows uses `STUDIO_GATE_MINUTES=60` → 30 min.
- [ ] **Step 2: Run them, expect FAIL** — `TESTS_ONLY="test_overnight_deadline_exported test_overnight_deadline_small_session test_help_exits_clean" sh tests/overnight_test.sh`; `sh tests/studio_deadline_test.sh`.
- [ ] **Step 3: Implement.** In `run_unit`, move `_secs=` above `with_launch_args start_session`; set `UNIT_DEADLINE=$((_t0 + _secs))`, margin `_mg=$((_secs / 6))`, `[ "$_mg" -ge 600 ] || _mg=600`, `[ "$_mg" -le $((_secs / 2)) ] || _mg=$((_secs / 2))`, `UNIT_WRAP_AT=$((UNIT_DEADLINE - _mg))`. Export both in `start_session`'s subshell next to `STUDIO_UNIT_TAG`. Write `studio-deadline` in the style of `studio-brief` (header comment, `usage`, `fail`).
- [ ] **Step 4: Run them, expect PASS**, then `sh tests/run_affected.sh` (or the two overnight suites in full).
- [ ] **Step 5: Commit** — `feat(overnight): every unit gets STUDIO_UNIT_DEADLINE and WRAP_AT; studio-deadline`.

### Task 2: A killed unit's cost is estimated, marked and counted

**Files:**
- Create: `studios/game-dev/bin/overnight-cost.sh` (sourced by studio-overnight, like `overnight-tools.sh`), `studios/game-dev/bin/model-prices.tsv`
- Modify: `studios/game-dev/bin/studio-overnight` — `run_unit` tail (~L1764: `UNIT_COST`), `row()` (~L1766), `write_report` (~L1802 `_unk`), the `spent` readers
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — `story_units_table`, `lanes_report` and `final_unit`'s row: the `≈` mark for estimates
- Modify: `studios/game-dev/bin/overnight-progress.sh` and any other `units.tsv` reader (`grep -rn units.tsv studios/ integrations/`): tolerate 9 columns
- Modify: `docs/game-dev/overnight-events.md` (`unit_ended` gains `usd_est`)
- Test: `tests/overnight_test.sh`

**Interfaces:**
- Produces: `cost_estimate FILE MINUTES` → prints a decimal USD (≥ 0, never empty). `UNIT_COST_SRC` = `result`|`estimate`. `row` writes 9 columns: `… $UNIT_COST $UNIT_MIN $UNIT_TIMED_OUT <outcome> $UNIT_COST_SRC ${UNIT_CAPPED:-0}`. The `unit_ended` event gains `usd_est:=true` for estimates. Task 5 sets `UNIT_CAPPED`.
- `model-prices.tsv` columns: `model input output cache_write cache_read` (USD per 1M tokens; 2026-10 Anthropic list prices; cache_write = 1.25 × input):
  ```
  claude-fable-5-1	10.00	50.00	12.50	0.25
  claude-opus-5-5	4.00	20.00	5.00	0.20
  claude-sonnet-5-5	2.00	10.00	2.50	0.20
  claude-haiku-5-5	0.10	0.50	0.125	0.01
  ```
- Algorithm (spec §6, C3): for each assistant event, dedupe by `message.id` and keep the first `usage` for input / cache_creation / cache_read. Output tokens = the bytes of all its content (text, thinking, tool_use input) across its repeats / 4. Price per `message.model`; an unknown model takes the dearest row. Calibration per model = the median of `result.modelUsage[model].costUSD ÷ naive(model)` over this run's units with a result event (≥ 3 such units), else the factor cached in `$STATE_ROOT/.studio/cost.calib` (`model factor epoch`, rewritten after each run with ≥ 3 units), else 1. No usage at all: `MINUTES` × the median $/min of this run's result units, else 0.50 $/min. awk only (no jq); a JSON field is matched by key name per line, as `cost_of` does.

- [ ] **Step 1: Write the failing tests** (`tests/fixtures/` gets two small stream-json files; the stub's `emit FILE` puts one in the unit log):
  - `test_overnight_cost_estimate_killed_unit`: scenario `stage execute; emit <fixture with 2 assistant msgs, one repeated, opus+sonnet usage>; sleep 30` under `SESSION_SECONDS=1`. units.tsv row 1 col 4 is a number > 0 equal to the hand-computed value (factor 1: no result units), col 8 `estimate`; events.jsonl `unit_ended` has `"usd_est":true`; report.md has no `cost unknown` and prints `≈`.
  - `test_overnight_cost_estimate_calibrated`: three result units (`cost 2`, each emitting a fixture whose naive cost is 1.00 and whose result `modelUsage` says 2.00), then a killed unit with naive 1.00 → col 4 = 2.00.
  - `test_overnight_cost_estimate_empty_transcript`: a killed unit that emits nothing, after one `cost 3` unit of 1 min → col 4 > 0, col 8 `estimate`.
  - `test_overnight_cost_counts_toward_budget`: `run_usd` set so the estimate pushes spent over it → the run ends `stop: run budget` before another unit.
  - Update `test_overnight_timeout` / `test_overnight_kill_after_grace` only where they assert `unknown`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `overnight-cost.sh` (`cost_estimate`, `cost_calibration`, `cost_calib_save`). In `run_unit`: `UNIT_COST="$(cost_of …)"`; when empty → `UNIT_COST_SRC=estimate; UNIT_COST="$(cost_estimate "$_log" "$UNIT_MIN")"`, else `result`. `row` appends cols 8-9; the report's cost cell shows `≈<n>` for col 8 `estimate`. Remove the `cost unknown for N unit(s)` text. Keep reading old 7-column rows.
- [ ] **Step 4: Run, expect PASS;** then both overnight suites and `tests/overnight_progress_test.sh`.
- [ ] **Step 5: Commit** — `feat(overnight): estimate a killed unit's cost from its transcript, calibrated per model`.

### Task 3: Task-scoped and file-sourced directives (CLI side)

**Files:**
- Modify: `studios/game-dev/bin/overnight-channel.sh` — `chan_args` (`--task [T<n>]`, `--file <path>`, a lone `-` = stdin), `chan_usage`, `chan_say`, `chan_list` (state `retired (T<n> done)`; task scope; the `from: runner` exclusion from the cap), `chan_next_id`, `chan_write_msg` (headers `task:`, `from:`), `msg_body` (verbatim)
- Modify: `studios/game-dev/hooks/operator-inbox.sh` — the scope switch (~L89-95: `task` is recorded like story, but as `Directive <id> T<n>: …`; `note` is shown, never recorded), `msg_body` (verbatim; the record command escapes `\` → `\\` and newline → `\n`)
- Modify: `studios/game-dev/bin/studio-overnight` — `requeue_check` (~L1187-1214: `task` scope expects `Directive <id> T<n>:`; `note` is never requeued), `usage()` (say syntax), and a new `queue_note STORY TASK TEXT` the runner uses to queue a runner-origin note (Task 5 calls it)
- Modify: `studios/game-dev/bin/studio-brief` — `directives_part` (task-scoped lines shown only while k < n; unescape `\n`/`\\`)
- Test: `tests/overnight_test.sh` (channel tests), `tests/studio_brief_test.sh`, `tests/hook_test.sh`

**Interfaces:**
- Produces CLI: `studio-overnight say <story> [--unit | --task [T<n>]] [--run <run>] (--file <path> | - | -- <text> | '<text>')`. `--unit` with `--task` → exit 2. A bare `--task` resolves k+1 from the story's `task k/N`; no `task k/N` (stage not execute, or k = N) → exit 1 `say: story <id> is not at a task — use --task T<n>`. `T<n>` with n ≤ k → exit 1 `say: T<n> is already complete`.
- Message file headers: `scope: story|unit|task|retire|note`, `task: T<n>` (task and note), `from: operator|runner`.
- `queue_note STORY T<n> TEXT` (studio-overnight, single-plan story `-` included): writes `scope: note`, `from: runner`, `task: T<n>` into the run's inbox with the next id, under the inbox lock. Delivered at the next unit's SessionStart as a block headed `RUNNER NOTE (previous attempt of T<n>)`, never recorded, never counted, never requeued. It is spent once delivered.
- Ledger: `Directive <id> T<n>: <escaped text>`. Readers take `Directive [0-9]+( T[0-9]+)?:`. Retired with no line when k ≥ n.

- [ ] **Step 1: Write the failing tests:**
  - `test_channel_say_task_scope_retires` (overnight_test.sh): a run whose unit 1 does `say --task T2 …` (a new stub action `"saytask "*`), records the delivered line as the hook prints it, and sets `task 1/3`; unit 2 sets `task 2/3`. `said` shows the directive active after unit 1, and `retired (T2 done)` after unit 2. The directive_chars count excludes it after unit 2 (a `say` that only fits without it succeeds).
  - `test_channel_say_task_bare_resolves_current`: at `task 4/12`, `say - --task -- x` writes `task: T5`.
  - `test_channel_say_task_refusals`: `--unit --task` → 2; n ≤ k → 1 with the message above.
  - `test_channel_say_file_verbatim`: a file holding `line one`, `it's $HOME \n literal`, a tab, a blank line and `last` → the .msg body equals the file byte for byte; the hook's SessionStart block prints it verbatim; the record command's ledger text round-trips through `studio-brief task` to the same bytes.
  - `test_channel_say_stdin`: `printf 'a\nb\n' | studio-overnight say - -` delivers `a\nb`.
  - `test_requeue_task_directive_recorded` / `test_requeue_note_never_requeued`.
  - studio_brief_test.sh `test_brief_task_directive_scoped`: the ledger has `Directive 3 T5: x` and `Directive 4: y`; at `task 4/9`, `studio-brief task 5` prints both; at `task 5/9`, `studio-brief task 6` prints only `y`.
  - hook_test.sh `test_inbox_note_shown_not_recorded`: a `scope: note` message is printed under `RUNNER NOTE` with no `studio-state ledger` line.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** as specified. Keep both `msg_body` copies identical (the comment says so).
- [ ] **Step 4: Run, expect PASS;** then the overnight suites, `hook_test.sh`, `studio_brief_test.sh`.
- [ ] **Step 5: Commit** — `feat(overnight): say --task scopes a directive to one task; say --file/- delivers it verbatim`.

### Task 4: Preflight warnings (direct gate, stale runner) and the story-worktree setup test

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight` — the start/`--dry-run` preflight (next to the gate run cap warning ~L960-995): `runner_behind_warn`
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — `mf_check`/manifest preflight: `direct_gate_warn`
- Test: `tests/overnight_test.sh`, `tests/overnight_lanes_test.sh`, `tests/studio_setup_test.sh` (or overnight_lanes_test.sh)

**Interfaces:**
- `runner_behind_warn`: `_rc="$(cd "$(dirname "$(readlink_f "$0")")/../../.." && git rev-parse --show-toplevel)"` (resolve symlinks with the runner's existing helper, or a POSIX loop); skip silently when it is not a work tree or has no `@{u}`. `git fetch -q` under a 15 s guard (`STUDIO_OVERNIGHT_FETCH_SECONDS`, test hook); on failure use the last fetch and append `(fetch failed; last fetch <age>)` (FETCH_HEAD mtime). Then `git rev-list --count HEAD..@{u} -- studios/game-dev`. When > 0, print `warning: runner checkout <path> is <k> commits behind <upstream> on studios/game-dev (<newest subject>) — update it before starting`. Never pulls; never refuses.
- `direct_gate_warn`: mode direct, `merge_command` set, `gate_command` unset → `warning: direct mode: merge_command's own gate is the first full run — set gate_command to that gate minus the merge (e.g. .github/scripts/run-tests.sh) so a red goes to a finish repair, not the landing`.

- [ ] **Step 1: Write the failing tests:**
  - `test_preflight_runner_behind_warns` (overnight_test.sh): copy the runner tree into a scratch git repo with a bare upstream that has one more commit touching `studios/game-dev/x` → `--dry-run` through that copy prints the warning with `1 commits behind`; a commit touching only `docs/` → no warning; a non-git copy → no warning. The test reaches the runner through the scratch repo's path, not `$REPO_ROOT`.
  - `test_lanes_preflight_direct_gate_warn` (overnight_lanes_test.sh): direct + merge_command + no gate_command → warning in the dry-run output; with gate_command set → none; integration mode → none.
  - `test_lanes_direct_gate_red_repairs` (overnight_lanes_test.sh): in direct mode, a finish unit that writes `Stop: gate red — gate_command exit 1 — log x` gets a gate-repair unit and a fresh finish (`story_gate_loop`), not a landing. If the runner gates this on integration mode anywhere, lift that guard.
  - `test_story_worktree_runs_setup` (studio_setup_test.sh): a fresh `git worktree add` of a project whose `.studio/config.json` is untracked (only in the start checkout) with `worktree_setup` = `touch setup-ran`; running `studio-setup` in the worktree with `STUDIO_START_DIR=<start>` creates `setup-ran` and does not print a skip. Run it against current code first. If it already passes (#104), keep it as the regression test and note that in the commit. If not, fix `studio-setup`'s resolution.
- [ ] **Step 2: Run, expect FAIL** (the setup test may already pass: record which).
- [ ] **Step 3: Implement** both warnings.
- [ ] **Step 4: Run, expect PASS;** then the touched suites in full.
- [ ] **Step 5: Commit** — `feat(overnight): preflight warns on a stale runner checkout and on direct mode with no gate_command`.

### Task 5: Progress, capped units, the task_timeouts bound, the checkpoint and the fallback note

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight` — `snapshot`/`story_units` (~L1925-1965), `unit_outcome` callers, `cfg` (`task_timeouts 2 1 5 int`), `usage()` config table, `holdable` comment
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — the hold hint text (`say … --task T<n>`), `story_units_table`
- Modify: `studios/game-dev/bin/studio-brief` — `checkpoint_part` for `task <n>` and `final`
- Test: `tests/overnight_lanes_test.sh`, `tests/overnight_test.sh`, `tests/studio_brief_test.sh`

**Interfaces:**
- Consumes: `UNIT_DEADLINE`, `UNIT_WRAP_AT` (Task 1); `row` columns 8-9 and `UNIT_CAPPED` (Task 2); `queue_note` (Task 3).
- Produces: `unit_commits HEAD0` → the count of the unit's own commits (C4): `git -C "$FEATURE_DIR" log --no-merges --format=%H "$HEAD0..HEAD" ^origin/<Target> -- . ':!.studio/'`, excluding subjects that start with `docs(<id>):`. It is 0 when HEAD0 was empty (no feature checkout before the unit). `UNIT_CAPPED` = 1 when `UNIT_TIMED_OUT` = 1, or the unit's end epoch ≥ `UNIT_WRAP_AT` and the label's task did not complete (SIG unchanged).
- `checkpoint_of LABEL` → the newest `<label> checkpoint: …` ledger line after the label's start (after the last `T<n-1> complete` or `base`, for `T<n>`), cut to 600 bytes; empty when none. Used by the ending, the hold text and `studio-brief`.
- `studio-brief task <n>` prints a part `==> <ledger> (checkpoint)` with that line, after the directives. `studio-brief final` does the same for `final-review`.
- Outcome rules in `story_units`, in order, after the stop/origin/done checks: SIG changed → `progress` (noprog 0). Else capped and `unit_commits` > 0 and `origin_check` → `partial` (noprog 0). Else capped → `unit_outcome` (`timed out`/`stalled`/… as today), noprog unchanged. Else → `unit_outcome`, noprog + 1 (C1). Capped units are counted per label base from `$UNIT_DIR/units.tsv` col 9 for rows whose label is `<id->base` or `<id->base-retry`, this run. The bound trips at count ≥ `TASK_TIMEOUTS`. The no-progress rule is unchanged (`noprog > RETRIES`). The bound's ending wins (C2): `timed out on <base> (session_minutes N; <k> capped units) — checkpoint: <checkpoint_of or fallback summary>`. A `no progress on …` ending appends ` — checkpoint: …` when one exists.
- Fallback note: after any task or final-review unit that did not complete its task, `queue_note <story> <base> <text>`, where text = `uncommitted: <git status --short, ≤20 lines>; unpushed: <shas+subjects>; ` plus, when this unit wrote no checkpoint line, `last words: <the last assistant text in the unit's jsonl, ≤1500 bytes>`. The hold's fallback summary is the first 300 bytes of it.
- Hold hint (both modes): `… — say <story> --task <base> -- '<done/left/next>' · resume <story>`.

- [ ] **Step 1: Write the failing tests** (lanes suite, holds on: `STUDIO_OVERNIGHT_HOLD_MINUTES` > 0 with `STUDIO_OVERNIGHT_HOLD_SECONDS` short; new stub actions: `wtcommit <file>` = commit a file in the story worktree; `checkpoint <text>` = `wtledger T<k+1> checkpoint: <text>` then commit the ledger; `lastwords <text>` = emit an assistant text event):
  - `test_lanes_checkpoint_reaches_retry` (Done-when 1): unit 1 = T1 complete; unit 2 = `checkpoint done A; left B; next C; sleep 30` under `SESSION_SECONDS=3` (killed). Unit 3's `studio-brief task 2` output (captured by a new stub action `brief <n>`) contains `T2 checkpoint: done A; left B; next C`.
  - `test_lanes_commit_then_killed_is_partial` (Done-when 2): unit 2 = `wtcommit fix.gd; pushwt; sleep 30` (killed) → units.tsv row 2 col 7 `partial`, col 6 `1`, col 9 `1`.
  - `test_lanes_bound_holds_with_checkpoint` (Done-when 3): `task_timeouts` 2; units 2-3 are killed, each with a checkpoint → the story holds after unit 3. The held why (control/<id>.held and the `story_state` held event) matches `timed out on T2 (session_minutes .*; 2 capped units) — checkpoint: done`. No unit 4 starts before `resume`.
  - `test_lanes_bound_resume_one_more`: after `resume`, unit 4 is killed again → it holds again with `3 capped units`, and no unit 5 starts.
  - `test_lanes_partial_counts_toward_bound`: two killed `partial` units → hold (the bound counts partial).
  - `test_lanes_uncapped_early_end_is_noprog`: `SESSION_SECONDS=600`; unit 2 commits, pushes and exits at once (not capped) → col 7 `noprog`; with `retries` 0 the story ends `no progress on T2`.
  - `test_lanes_fallback_note_without_checkpoint`: unit 2 = `wtfile x.gd` (uncommitted), `lastwords next I will run probe 3`, `sleep 30`, killed → unit 3's inbox block (stub action `inbox`) has `RUNNER NOTE`, `x.gd` and `next I will run probe 3`.
  - overnight_test.sh: update `test_overnight_kill_after_grace`'s expected ending to the new form (prefix `timed out on T1 (session_minutes `), and add `test_overnight_bound_single_plan` (the same bound, single-plan, holds off → the run ends with the checkpoint in report.md's Ending).
  - studio_brief_test.sh `test_brief_task_checkpoint_part`: the ledger has `T4 complete a..b`, `T5 checkpoint: old`, `T5 checkpoint: new` → `studio-brief task 5` prints only `new`; `studio-brief task 6` prints none.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** per the Interfaces. Take HEAD0 after `unit_pre`, in `$FEATURE_DIR` (empty when `FEATURE_DIR` = `START_DIR` and no branch is recorded).
- [ ] **Step 4: Run, expect PASS;** then the full `overnight_test.sh`, `overnight_lanes_test.sh`, `overnight_progress_test.sh`, `studio_brief_test.sh`, the multica suite (the held-why text reaches `notice.py`).
- [ ] **Step 5: Commit** — `feat(overnight): pushed work in a capped unit is progress; a task capped task_timeouts times holds with its checkpoint`.

### Task 6: The hook nudges at wrap-up time; the subagent probe

**Files:**
- Modify: `studios/game-dev/hooks/operator-inbox.sh`
- Create: `tests/probes/deadline_notice_probe.sh` (manual, real `claude`; not in run_all, like `bash_timeout_probe.sh`)
- Test: `tests/hook_test.sh`

**Interfaces:**
- Consumes: `STUDIO_UNIT_WRAP_AT`, `STUDIO_UNIT_DEADLINE` (Task 1).
- Behavior: before the storyless and no-inbox early exits, when `STUDIO_UNIT_WRAP_AT` is set and now ≥ it, emit once per (`STUDIO_UNIT_TAG`, agent_id or `main`) a marker under `$STUDIO_RUN_DIR/deadline/<tag>.<who>.wrap`. Main session text: `WRAP-UP (STUDIO_UNIT_WRAP_AT passed): <m> min to the hard stop at <HH:MM>. Start no gate and no subagent. Commit and push green work, write the T<n> checkpoint ledger line (execute §8), end the turn.` Subagent text: `WRAP-UP: return to the orchestrator now with what is done and what is left; start nothing new.` A second notice (`.final` marker) fires at DEADLINE − 180: `FINAL: <m> min left — commit what is green and end now.` SessionStart output is plain text; PostToolUse output is the `hookSpecificOutput.additionalContext` JSON. When there are inbox messages too, both go in one block.

- [ ] **Step 1: Write the failing tests** (hook_test.sh): `test_inbox_wrap_notice_once` (2 PostToolUse calls after WRAP_AT → the notice once); `test_inbox_wrap_notice_subagent` (input with a top-level `agent_id` → the subagent text, its own marker); `test_inbox_wrap_notice_final_unit` (no STUDIO_STORY in a manifest run → still gets it); `test_inbox_wrap_notice_before_wrap_silent`; `test_inbox_final_notice`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS;** then all of `hook_test.sh`.
- [ ] **Step 5: Write the probe** — it runs `claude-gd -p` with a plugin dir whose PostToolUse hook injects a canary into a subagent's tool calls, and asks the main session to dispatch a subagent that runs `true` twice and reports any canary it saw. Do not run it in this task (it needs a real session); Task 9 runs it once and records the result.
- [ ] **Step 6: Commit** — `feat(hooks): a wrap-up notice at STUDIO_UNIT_WRAP_AT, to the session and its subagents`.

### Task 7: Multica bridge — `/say --task`

**Files:**
- Modify: `integrations/multica/bridge/commands.py` (`plan_call`), `integrations/multica/bridge/notice.py` (`hold_body`), `integrations/multica/bridge/mirror.py` (a `message_queued` with `scope=task` mirrored as `task T<n>`), `integrations/multica/README.md`, `integrations/multica/agent-instructions.md` (when it lists commands)
- Test: `integrations/multica/tests/test_commands.py`, `test_notice.py`, `test_mirror_*.py`

**Interfaces:**
- Consumes: the Task 3 CLI.
- `/say --task T12 <text>` → `["say", "--run", basename, story, "--task", "T12", "--", text]`. A bare `/say --task <text>` → `[…, "--task", "--", text]`. `--task` with no text → reply `studio: ✗ usage: /say --task [T<n>] <text>`. A token after `--task` that does not match `T[0-9]+` is text.
- `hold_body`, when `why` starts with `timed out on T<n> `: `Multica: on <issue> post /say --task T<n> <done/left/next>, then /resume — or /stop.`, and the terminal line uses `say <story> --task T<n> --run <run> -- <text>`. Other holds are unchanged.

- [ ] **Step 1: Failing tests** for the three call shapes, the usage reply, both hold_body forms and the mirror line.
- [ ] **Step 2: Run** `sh integrations/multica/tests/run.sh` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `feat(multica): /say --task scopes a directive to one task; held timeouts suggest it`.

### Task 8: Skills — execute (deadline, checkpoint, direct finish gate, briefs) and plan (fits the session)

**Files:**
- Modify: `studios/game-dev/skills/execute/SKILL.md` — §0 (the deadline rule after the gate rule, ~L146-185), §2 (brief lines, ~L377-395), §4a (commit each green fix as it lands), §7 (Direct: step 1 as Integration; drop "Direct mode runs no finish gate", ~L874-878), §8 Inputs (the checkpoint and RUNNER NOTE lines, ~L896) and a new **Wrap-up** bullet (how to write the checkpoint), Operator messages (`task` and `note` scopes)
- Modify: `studios/game-dev/skills/plan/SKILL.md` — §6 Self-review: the **fits the session** check
- Test: `tests/pointer_skills_execute_test.sh`, a new `tests/pointer_skills_plan_test.sh` (or the existing plan pointer test if one exists: `grep -l plan/SKILL.md tests/*.sh`)

**Interfaces (exact strings the tests pin):**
- §0: `STUDIO_UNIT_WRAP_AT`, `studio-deadline fits`, `WRAP-UP`, and "end the turn".
- §2 brief line, verbatim: "Return to the orchestrator by `$STUDIO_UNIT_WRAP_AT` (`studio-deadline` prints it) with what is done and what is left. Never start a command that cannot finish by then: `studio-deadline fits <gate>` answers that. Pass `timeout` only on gate-routed commands (`studio-test`, `studio-run`, `studio-setup`, `studio-gate`); never on `sh tools/…`, `python`, `git` or any other command — a raised timeout lets a hung command outlive its cap."
- §4a: "commit each fix that passes its owning tests as it lands (and push under a lane); never batch fixes to the end of the task".
- §8 Inputs: "a `T<n> checkpoint:` part in `studio-brief task <n>`, or a `RUNNER NOTE` block, goes in the implementer's brief: `previous attempt: <text> — continue from \"next\"; do not redo \"done\" steps unless a file their evidence names has changed since`".
- §8 Wrap-up: order = commit green fixes → `studio-state ledger "T<n> checkpoint: done <steps/evidence paths>; left <steps>; next <first action>"` → `git add .studio/ledger` → `git commit -m "chore(studio): checkpoint T<n>"` → push → end the turn. A final-review unit writes `final-review checkpoint: …`. Repair units (§9, §11) write `Stop: <kind> repair out of time — done …; left …` instead.
- §7 Direct: "step 1 runs as under **Integration**"; the string "Direct mode runs no finish gate" is gone.
- plan §6: "fits the session", "session_minutes / 2", "until 0", and the T12 example (probe-to-zero loop and the clean-exit series are two tasks; a loop task names its max rounds, then a Block or a Stop).

- [ ] **Step 1: Failing pointer tests** asserting each string above (and `assert_not_contains` for the dropped sentence).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Edit the skills.** Match the surrounding voice: numbered references to sections, short imperative sentences. Keep the added text tight, since the skill is read every unit.
- [ ] **Step 4: Run, expect PASS;** then `tests/omega_contracts/*` and `tests/pressure` checks that cover these skills (`grep -l execute/SKILL tests/pressure/* tests/*.sh`).
- [ ] **Step 5: Commit** — `docs(skills): execute knows its deadline and checkpoints; direct finish runs the gate; plan splits tasks that cannot fit`.

### Task 9: Docs, the probe run, the full suite

**Files:**
- Modify: `README.md` (the overnight section: deadline, checkpoint, `task_timeouts`, `say --task/--file`), `docs/game-dev/PROGRESS.md` (a 2026-10-26 entry in the house style: incident, fixes 1-11, unchanged), `docs/game-dev/overnight-events.md` (`partial`, `usd_est`, the new held-why form), `studio-overnight --help` (anything Tasks 1-5 missed)

- [ ] **Step 1:** Run `tests/probes/deadline_notice_probe.sh` once (it spends a few cents of real session). Record the result in the probe's header comment and in SKILL.md §2's note (whether subagents receive the notice).
- [ ] **Step 2:** Write the docs. The PROGRESS entry names the Done-when checks and their tests.
- [ ] **Step 3:** `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh`: all green. Paste the summary lines in the PR body.
- [ ] **Step 4: Commit** — `docs: unit deadline and carry-over in README, PROGRESS and the event reference`.
- [ ] **Step 5:** Push the branch and open the PR (title `fix(overnight): unit deadline, checkpoint carry-over, capped-task bound (+ defects 3, 5-11)`). Do not merge, and do not install, until `studio-overnight status` shows no live run.
