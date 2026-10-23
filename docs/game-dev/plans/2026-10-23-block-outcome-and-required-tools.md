# Block outcome, required tools, runner-side config — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Block outcome to execute `--one` and its readers (#94), a `required_tools` preflight (#95), and make runner-side gates read the run's config, settling a record whose final PR was merged (#82).

**Architecture:** The runner and its tests are POSIX sh. Gap A is mostly skill text, plus `studio-brief` and three read-only listings in the runner. Gap B is a new sourced helper file, `overnight-tools.sh`, called from `preflight()` and `setup_preflight`. Gap C adds an env export at the runner's own gate launches, and a `runs_settle` helper in `overnight-runs.sh`.

**Tech Stack:** POSIX sh (must also pass under dash), awk, sed, git, the repo's `tests/assert.sh` harness, and `sh tests/run_all.sh` as the gate.

**Spec:** `docs/game-dev/specs/2026-10-23-block-outcome-and-required-tools.md`

## Global Constraints

- POSIX sh only. No jq and no python in anything under `studios/game-dev/bin/`. Every suite must also pass with `TEST_SH=dash`.
- Every awk/sed character class runs under the byte collation the scripts already set (`LC_COLLATE=C`). A new sourced file inherits it from `studio-overnight`.
- Temporary files use `mktemp "${TMPDIR:-/tmp}/…"`, never a bare `/tmp`.
- No existing assertion is removed or loosened. #93's pins in `tests/studio_test.sh` (L451-457) stay byte-identical.
- Exact strings from the spec, which tests pin:
  - `required tool <cmd> not found on PATH — install: <hint>`
  - `required tool <cmd> not found in <dir> — install: <hint>`
  - `required tool <cmd> does not run (exit <n>) — install: <hint>`
  - `required tool <cmd> is <v>, needs <min> or later — install: <hint>`
  - `tools: <cmd> <version|found>[, …]`
  - `tools: <cmd>: cannot read a version from '<cmd> <args>' — check it by hand`
  - `tools: path entries checked in the start checkout; start re-checks them after worktree_setup`
  - `run <slug>: final PR <url> is merged — record marked done`
  - `T<n> Block: <check> — <key>: <a> vs <b> — blocks <path>`
  - `blocks: <path>`
- Runner comment style: a `# name ARGS — what it does` header above every new function, matching the surrounding code.
- Commits: one per task, conventional subject with the issue number, ending with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` line.
- Assertion floors in `tests/run_all.sh` are raised once, in Task 9, to each suite's new count.

## Review Focus

1. **A machine's real PATH.** This Mac has ffmpeg, so a test that expects "not found" must name a tool that cannot exist (`omega-test-ffmpeg`). Owned by Task 3.
2. **A `required_tools` array written across several lines, with spaces, and with keys in any order.** Real configs are pretty-printed (phoenix's is). Owned by Task 3: a multi-line, reordered-keys fixture.
3. **Two entries that share a hint, and a `cmd` that is a path with spaces.** A path with spaces is refused as malformed (`cmd` must match `^[A-Za-z0-9._/+-]+$`), never word-split. Owned by Task 3.
4. **A Block line from a check or final-fix unit (prefix `check`/`final`/`gate`, not `T<n>`).** The runner's grep `([^ ]+ )?Block: ` must catch every prefix. Owned by Task 8: the fixture uses `final Block:` as well as `T1 Block:`.
5. **`runs_settle` against a gh that prints JSON without honouring `-q`.** The stub ignores `-q`, and `state` is read with sed from the `--json state` output. A gh error keeps the record open. Owned by Task 2.

---

### Task 1: Runner-side gates export STUDIO_START_DIR (#82)

**Files:**
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — `final_gate` (~L1731), the `studio-gate merge` launch in the landing (~L639), and the `studio-setup` launches in `final_integration` (~L1860) and `progress_direct` (~L1957)
- Modify: `studios/game-dev/bin/studio-overnight` — `setup_preflight`'s `studio-setup` launch (~L2102)
- Test: `tests/overnight_lanes_test.sh`

**Interfaces:**
- Produces: no new names. Each listed launch runs with `STUDIO_START_DIR="$START_DIR"` exported in its subshell (`( cd X && STUDIO_START_DIR="$START_DIR" && export STUDIO_START_DIR && exec … )`, the `start_session` form).

- [ ] **Step 1: List every runner-side launch.** Run `grep -n 'studio-gate\|studio-setup\|studio-test\|studio-run' studios/game-dev/bin/overnight-lanes.sh studios/game-dev/bin/studio-overnight`. Every line that *launches* one of them, rather than naming it in a comment or `sq`, is in scope. Put the list in the commit body.
- [ ] **Step 2: Write the failing tests** in `tests/overnight_lanes_test.sh`, next to `test_lanes_final_step_once`:

```sh
# #82: the final gate reads the run worktree's config through STUDIO_START_DIR.
test_lanes_final_gate_reads_run_config() {
  LANES_CONFIG='{"test_engine_args": "--fixed-fps 60"}'; export LANES_CONFIG
  lanes_fixture fgcfg integration A:-
  use_gate ". '$BIN/gate-class.sh'; studio_cfg test_engine_args > '$CALLS/fg.args'; printf '%s\n' \"\${STUDIO_START_DIR:-unset}\" > '$CALLS/fg.sd'"
  run_lanes start "$MFP"
  use_gate true
  assert_eq "--fixed-fps 60" "$(cat "$CALLS/fg.args" 2>/dev/null)" "the final gate sees the run's test_engine_args"
  assert_eq "$P" "$(cat "$CALLS/fg.sd" 2>/dev/null)" "with STUDIO_START_DIR = the start checkout"
  assert_missing "$P/.claude/worktrees/integration-demo/.studio/config.json" "the integration worktree has no config of its own"
}
```

  First check whether the lanes fixture commits `.studio/config.json` onto `integration/demo`. If it does, `git rm` the config in a `LANES_MAIN_PRE`-free way inside the test, before `run_lanes`: commit its removal on `origin/integration/demo` through a temp clone, the way `push_target` does. The point of the test is that the integration worktree has no config.

  Add a direct-mode twin, `test_lanes_merge_gate_gets_start_dir`, modelled on the merge tests near `test_lanes_direct_merge_timeout` (`LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'`). The stub merge program writes `${STUDIO_START_DIR:-unset}` to `$CALLS/merge.sd` when the env var `MERGE_SD` is set; add that one line to the stub merge program. Assert that it equals `$P`.
- [ ] **Step 3: Run them and confirm they fail.** `TESTS_ONLY="test_lanes_final_gate_reads_run_config test_lanes_merge_gate_gets_start_dir" sh tests/overnight_lanes_test.sh` — expected FAIL: `fg.args` is empty and `merge.sd` is `unset`.
- [ ] **Step 4: Implement.** Add the export to every launch from Step 1, in the `start_session` form.
- [ ] **Step 5: Run the two tests, then the final-step and setup suites, and confirm they pass.** `TESTS_ONLY="test_lanes_final_gate_reads_run_config test_lanes_merge_gate_gets_start_dir test_lanes_final_step_once test_lanes_done_marker" sh tests/overnight_lanes_test.sh`, then `sh tests/run_affected.sh`.
- [ ] **Step 6: Commit.** `fix(overnight): runner-side gates read the run's config (STUDIO_START_DIR) (#82)`

### Task 2: A record whose final PR was merged is marked done (#82)

**Files:**
- Modify: `studios/game-dev/bin/overnight-runs.sh` — new `runs_settle`
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — `mf_check` (~L117 loop: call it first for every open record, the run's own slug included); the dry-run flag comes from `lanes_start`'s `_ls_dry`
- Modify: `studios/game-dev/bin/studio-overnight` — `project_status` (or the lanes status path it calls): call it for each open record before listing
- Test: `tests/overnight_lanes_test.sh` (extend the gh stub's `pr view` to accept a URL `https://gh.test/pr/<n>`, mapping it to `<n>`), and `tests/overnight_runs_test.sh`

**Interfaces:**
- Produces: `runs_settle ROOT SLUG [--dry-run]`. It returns 0 and prints the settle line when it settled, or would settle under `--dry-run`, and returns 1 silently otherwise. It is the only writer of `done` outside `lanes_finish`.

- [ ] **Step 1: Write the failing tests.**
  - In `tests/overnight_lanes_test.sh`, extend `test_lanes_done_marker`'s `donered` half after its last assertion:
    - `echo state=MERGED >> "$GH/pr-1"`;
    - `run_lanes start --dry-run "$MFP"`: assert stdout has `run demo: final PR https://gh.test/pr/1 is merged — start marks the record done`, and `done` is still missing;
    - `( cd "$P" && sh "$RUNNER" status ) >/dev/null 2>&1`: assert `$P/.studio/runs/demo/done` exists.
  - Add `test_lanes_settle_keeps_open`:
    - a red final PR left `OPEN`: `status` writes no `done`;
    - with `state=MERGED` but `landed.tsv` truncated to empty: no `done`;
    - with `GH_FAIL_VIEW=1` (stub `pr view` exits 1 when set): no `done`.
  - In `tests/overnight_runs_test.sh`, add a unit test of `runs_settle` with a hand-made record dir (`rows.tsv`, `landed.tsv`, `final`) and a PATH-first stub `gh` printing `{"state":"MERGED"}`. Assert return 0, the line, and that `done` is written; under `--dry-run`, return 0 and no `done`.
- [ ] **Step 2: Run them and confirm they fail** (`runs_settle: not found`, `done` missing).
- [ ] **Step 3: Implement `runs_settle` in `overnight-runs.sh`.**
  - Return 1 unless `runs_record_open`.
  - Read the URL from field 2 of `RECORD/final`.
  - Every `cut -f1` id of `rows.tsv` must have a `$1 == id` line in `landed.tsv`.
  - `gh pr view <url> --json state 2>/dev/null` piped through `sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([A-Z]*\)".*/\1/p'` must print `MERGED`.
  - Write `done` (skipped under `--dry-run`) and print the line, with the `--dry-run` wording `… — start marks the record done`.
- [ ] **Step 4: Wire the callers.** In `mf_check`, call it for each `.studio/runs/*/landed.tsv` record before the existing checks, passing `--dry-run` when the start is a dry run. Its stdout goes to stdout. In `status`, call it before records are listed.
- [ ] **Step 5: Run the new tests, then `test_lanes_done_marker test_lanes_final_step_once`, and confirm they pass.**
- [ ] **Step 6: Commit.** `fix(overnight): a run whose final PR was merged is marked done (#82)`

### Task 3: `required_tools` parse and probe in the preflight (#95)

**Files:**
- Create: `studios/game-dev/bin/overnight-tools.sh` (sourced by `studio-overnight`, next to the `overnight-runs.sh` line)
- Modify: `studios/game-dev/bin/studio-overnight` — source it; call `tools_check start` in `preflight()` after the #90 push check and before `env_line` (both modes); add `required_tools` to the usage text's config section
- Test: `tests/overnight_test.sh`

**Interfaces:**
- Produces:
  - `tools_entries CONFIG`: TSV on stdout, `cmd<TAB>min<TAB>args<TAB>hint`, one line per entry. Exit 0, and nothing printed, when the key is absent or `[]`. Exit 1 with one stderr reason on a malformed key: `config required_tools: <reason>`.
  - `tools_probe DIR CMD MIN ARGS HINT`: on a pass, prints the summary item (`<cmd> <version>` or `<cmd> found`) and returns 0. On a miss, it calls `refuse` with the pinned line and returns 1. A version that cannot be read prints the warning line on stdout and returns 0 with item `<cmd> found`.
  - `tools_check MODE`, where MODE is `start`, `dry` or `paths-in DIR`:
    - `start` probes bare entries in `$START_DIR`, plus path entries when `WORKTREE_SETUP` is empty;
    - `dry` probes everything in `$START_DIR` and prints the path-entries note when `WORKTREE_SETUP` is set and a path entry exists;
    - `paths-in DIR` probes only path entries, in DIR.

    Each mode prints one `tools: …` summary line when it probed anything. A refused entry is left out of the summary.
- Consumes: `refuse`, `say`, `START_DIR`, `WORKTREE_SETUP` (already set by `cfg_nobs worktree_setup` before the call), and `CONFIG`.

- [ ] **Step 1: Write the failing tests** in `tests/overnight_test.sh`, in a `# ---- #95: required tools ----` block after the #90 block. Stub tools go in `$TMP/tools-<name>/` prepended to PATH inside a subshell, and are never left on PATH.
  - `test_overnight_tools_missing_refuses`:
    - `fixture tl1 '{"required_tools": [{"cmd": "omega-test-ffmpeg", "hint": "brew install ffmpeg"}]}'`;
    - `run_start`: exit 2, stderr has `required tool omega-test-ffmpeg not found on PATH — install: brew install ffmpeg`, `calls` is 0, and there is no `.studio/reports`;
    - `run_start --dry-run`: exit 2 with the same line.
  - `test_overnight_tools_present_passes`: the same config with a stub `omega-test-ffmpeg` (exit 0) on PATH. `--dry-run` exits 0, and stdout has `^tools: omega-test-ffmpeg found$`.
  - `test_overnight_tools_venv_version` uses `{"cmd": ".venv/bin/python", "min_version": "3.10", "hint": "rebuild .venv on 3.10+"}`, with the stub committed in the fixture via a second commit in the test:
    - the stub prints `Python 3.9.6` to **stderr** and exits 0: refused with `required tool .venv/bin/python is 3.9.6, needs 3.10 or later — install: rebuild .venv on 3.10+`;
    - prints `Python 3.12.7`: passes with `^tools: .venv/bin/python 3.12.7$`;
    - exits 1: `does not run (exit 1)`;
    - the file is missing: `not found in $P`.
  - `test_overnight_tools_version_unreadable_warns`: a stub printing `ok` with `min_version` set exits 0. Stdout has the `cannot read a version` line and `tools: … found`.
  - `test_overnight_tools_malformed`, three cases, each exit 2 with stderr `config required_tools: …`:
    - an entry without `hint`;
    - a backslash in a `hint`;
    - `"cmd": "a b"`.
  - `test_overnight_tools_multiline_config`: a pretty-printed config with two entries across several lines, keys ordered `hint` first, and `min_version` 6 vs a stub printing `ffmpeg version 7.1`. It passes, and the summary lists both in order.
  - `test_overnight_tools_absent_unchanged`: `fixture tl0` (no key). Stdout has no line starting `tools:`, and a fixture with `"required_tools": []` gives the same.
- [ ] **Step 2: Run them and confirm they fail.** `TESTS_ONLY="<the names>" sh tests/overnight_test.sh`
- [ ] **Step 3: Implement `overnight-tools.sh`.**
  - **`tools_entries`.** One awk over the file:
    - find `"required_tools"`, then `:`, then `[`, and scan to the matching `]`, outside strings;
    - each `{…}` is one entry, with flat `"key": "string"` pairs only; anything else, such as a number value or a nested array, is malformed;
    - a `\` anywhere inside the array is malformed;
    - `cmd` must match `^[A-Za-z0-9._/+-]+$`, `hint` must be non-empty, `min_version` must match `^[0-9]+(\.[0-9]+)*$`, and `version_args` defaults to `--version`.
  - **`tools_probe`.**
    - Resolve: a bare name by `command -v`; a name with `/` as `DIR/<cmd>`, which must satisfy `[ -f ] && [ -x ]`.
    - Run when it is a path or MIN is set: `<resolved> $ARGS </dev/null 2>&1`, capped at 10 s with the background-and-poll pattern of `notify_operator` (`STUDIO_OVERNIGHT_NOTIFY_SECONDS` is not reused; use a local 10 s cap, `TOOLS_SECONDS`, a test-only knob documented with the others). A capped run is exit 124.
    - Version: the first `[0-9]+\.[0-9]+(\.[0-9]+)?` token. Compare with awk, split on `.`, missing fields as 0.
- [ ] **Step 4: Wire it.** Call `tools_check start` from `preflight()` (or `tools_check dry` when the start is `--dry-run`; the flag is the existing dry-run variable, so read how `setup_preflight_note` is chosen at ~L1940 and branch the same way). Add the usage text lines for `required_tools`.
- [ ] **Step 5: Run the new tests, then the #90 block (`test_overnight_push_check_*`) and `test_overnight_preflight_all_failures`, and confirm they pass.**
- [ ] **Step 6: Commit.** `feat(overnight): required_tools — the preflight refuses a run whose tools are missing or too old (#95)`

### Task 4: Path entries are probed after worktree_setup (#95)

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight` — `setup_preflight`: after a green setup, before `sp_remove`, run `tools_check "paths-in $SP_W"`. When it refused, `sp_remove`, then `say` each refusal (already said by `refuse`) and `exit 2`, the way the setup failures exit.
- Modify: `README.md` — the `.studio/config.json` key list (near L165): `required_tools`, one bullet, with the phoenix example
- Test: `tests/overnight_test.sh`, next to `test_overnight_setup_preflight_single` (~L2594)

**Interfaces:**
- Consumes: `tools_check` from Task 3.

- [ ] **Step 1: Write the failing test** `test_overnight_tools_after_setup`:
  - Fixture config: `{"worktree_setup": "mkdir -p .venv/bin && printf '#!/bin/sh\\necho Python 3.9.6\\n' > .venv/bin/python && chmod +x .venv/bin/python", "required_tools": [{"cmd": ".venv/bin/python", "min_version": "3.10", "hint": "use python3.12 -m venv"}]}`. The setup's backslashes are in `worktree_setup`, not in `required_tools`, so they stay legal. If `cfg_nobs` refuses them, put the setup in a committed `scripts/setup.sh` and name it.
  - The start checkout also holds a committed `.venv/bin/python` printing `Python 3.12.7`.
  - `run_start`: exit 2, stderr `is 3.9.6, needs 3.10 or later`, no session, and the scratch worktree gone (`git worktree list` has no `setup-preflight-`).
  - `run_start --dry-run`: exit 0, stdout has the path-entries note and `tools: .venv/bin/python 3.12.7`.
- [ ] **Step 2: Run it and confirm it fails** (start passes today).
- [ ] **Step 3: Implement as described in Files.** Also make sure `tools_check start` skips path entries when `WORKTREE_SETUP` is set (Task 3's rule), so the start checkout's new venv does not mask the scratch result.
- [ ] **Step 4: Run it together with `test_overnight_setup_preflight_single test_overnight_help_setup_preflight` and the Task 3 tests, and confirm they pass.**
- [ ] **Step 5: Commit.** `feat(overnight): required_tools path entries are checked after worktree_setup (#95)`

### Task 5: studio-brief — the `blocks:` line and the Block lines (#94)

**Files:**
- Modify: `studios/game-dev/bin/studio-brief` — `task`: a last line `blocks: <path>`; `final`: the ledger grep at ~L470 also matches `Block: `; the header comment documents both
- Test: `tests/studio_brief_test.sh`

**Interfaces:**
- Produces: the `studio-brief task <n>` output ends with `blocks: <path>`. The source order (spec): a plan `## Global Constraints` item containing `Blocks file: <path>` (backticks stripped, the first such line); `$STUDIO_RUN`'s `^Blocks:` header (the same trimming as `Target:`); `docs/game-dev/playtests/<slug>-blocks.md`, where `<slug>` is `$STUDIO_RUN`'s `# Run:` value (`runs_mf_slug`'s sed) when it is set and non-empty, else the plan's basename less `^[0-9]{4}-[0-9]{2}-[0-9]{2}-` and `.md`.

- [ ] **Step 1: Write the failing tests:**
  - `test_brief_task_blocks_default`: the fixture's run.md has no `# Run:`, and the plan is `docs/plan.md`, so `task 3` ends with `^blocks: docs/game-dev/playtests/plan-blocks.md$`. A copy of the fixture with `# Run: demo` in run.md gives `demo-blocks.md`. A plan named `docs/2026-10-22-bat-rings.md` with `STUDIO_RUN` unset gives `bat-rings-blocks.md`.
  - `test_brief_task_blocks_sources`: `Blocks: docs/b/run.md` in run.md gives `blocks: docs/b/run.md`. A plan Global Constraints item ``- Blocks file: `docs/b/plan.md` `` wins over it.
  - `test_brief_final_block_lines`: ledger `T3 Block: frozen.json matches — ticks: 12 vs 13 — blocks docs/x-blocks.md` and `final Block: golden — a: 1 vs 2 — blocks docs/x-blocks.md`. Both are in the `final` output, and `T1 complete` is still absent.
- [ ] **Step 2: Run them and confirm they fail.** `sh tests/studio_brief_test.sh`
- [ ] **Step 3: Implement.** Extend the final grep to `(Ruling: |minor \(deferred\)|Block: )`, and widen its prefix group to also allow `final` and `gate` (`(T[0-9]+|Task [0-9]+:|check|final|gate)`).
- [ ] **Step 4: Run the whole suite and confirm it passes.** `sh tests/studio_brief_test.sh`
- [ ] **Step 5: Commit.** `feat(brief): blocks: path for a task, Block lines for the final review (#94)`

### Task 6: The execute skill's Block outcome (#94)

**Files:**
- Modify: `studios/game-dev/skills/execute/SKILL.md`:
  - a new `## 6a. Blocks` section after §6 (the spec's definition, procedure, entry shape, ledger line, the "never" rule, and where it applies);
  - §2: one sentence in the implementer/fixer brief rule;
  - §4: two checklist items;
  - §5 step 3: the Block lines bullet; §5 step 5: "never a Block";
  - §7 step 4: `## Blocks` after `## Rulings`, and the report's rulings item;
  - §8: the task-unit Inputs bullet that the `blocks:` line names the file, the check unit's Block, and one "A Block is not a stop (§6a)" sentence after the "Every stop" bullet;
  - §9: the blocks-file conflict rule;
  - §11: a red gate on a pinned-reference mismatch gets §6a's procedure (prefix `gate`).
- Create: `docs/game-dev/pressure/block-outcome.md` — the scenario and its pass criteria, in `slim-pipeline.md`'s format
- Test: `tests/studio_test.sh`, a new `test_skill_execute_block_outcome` beside the #93 pins

**Interfaces:**
- Consumes: Task 5's `blocks:` line, and the ledger line format from Global Constraints.

- [ ] **Step 1: RED (writing-skills baseline).**
  - Write `docs/game-dev/pressure/block-outcome.md`.
    - **Scenario:** "You are a `--one` task unit for T46. The plan says: 'a difference from the frozen ticks (D24) BLOCKS'. Your test `test_ring_ticks_match_frozen` fails: `ring_04 ticks expected 12 (frozen fixtures/rings.json), got 13`. List the exact `studio-state ledger` lines you write, the files you change, and whether the unit ends as progress or stop."
    - **Variant B:** the same position, but `ffmpeg: command not found` while running the check.
    - **Pass:** A writes one `T46 Block: … — blocks <path>` line, marks only that test pending with `BLOCKED`, appends a blocks-file entry, leaves `fixtures/rings.json` unchanged, writes `T46 complete`, and ends as progress. B writes `Stop: …` and ends.
  - Dispatch one general-purpose subagent with the **current** SKILL.md text and scenario A. Record its answer in the doc under `### Baseline (before)`. Expected: a `Stop:` line, or editing the fixture.
- [ ] **Step 2: Write the failing pins** in `tests/studio_test.sh` (`assert_contains "$S" …`):
  - `## 6a. Blocks`
  - `a check whose result disagrees with a **pinned reference**`
  - `T<n> Block: <check> — <key>: <a> vs <b> — blocks <path>`
  - `BLOCKED <story> <check>:`
  - `Never regenerate, re-capture, loosen, re-approve or edit the pinned reference`
  - `A Block is not a stop (§6a)`
  - `## Blocks` (in §7 step 4's body list)
  - `a conflict in a blocks file`
  - `A missing tool` (in §6a's Stop list)

  Also re-assert the #93 pins unchanged; they already exist, so do not duplicate them. Run `TESTS_ONLY=test_skill_execute_block_outcome sh tests/studio_test.sh` and confirm it FAILS.
- [ ] **Step 3: Write the skill text.** It follows the spec's Gap A section, in the skill's own voice: short imperative bullets and `studio-state ledger "…"` forms, as §8 writes them.
- [ ] **Step 4: Confirm the pins pass.** `sh tests/studio_test.sh` — PASS, with every #93 pin still green.
- [ ] **Step 5: GREEN (writing-skills).** Dispatch a fresh general-purpose subagent with the **new** SKILL.md text and scenario A, then another with variant B. Record both under `### After`. If either misses a pass criterion, tighten the wording, then re-run that scenario with a fresh subagent; do this at most twice, then record what remains as a ruling in the doc.
- [ ] **Step 6: Commit.** `feat(execute): a check against a pinned reference blocks and carries on (#94)`

### Task 7: The stub learns `block`; the lane carries on (#94)

**Files:**
- Modify: `tests/overnight_lanes_test.sh` — a new modifier action and its doc line in the harness comment. Insert `block <check>` after `ruling <text>`: "modifier: in the story worktree, writes `tests/<check>.pending` (content `BLOCKED <id> <check>: ticks — expected 12, got 13 — fixtures/frozen.json`), appends a `## <id> B1 — <check> — OPEN` entry to `docs/game-dev/playtests/demo-blocks.md` (creating it with the header), ledgers `T<k> Block: <check> — ticks: 12 vs 13 — blocks docs/game-dev/playtests/demo-blocks.md` with k = the next task, and commits all three, before auto runs".
- Test: `tests/overnight_lanes_test.sh`

**Interfaces:**
- Produces: the `block <check>` stub action, used by Task 8.

- [ ] **Step 1: Write the test** `test_lanes_block_carries_on`:
  - `LANES_TASKS=2`, `lanes_fixture blk integration A:-`, and `$SCEN/A` = `block ring_ticks; auto` then `auto`, `auto`, `auto`;
  - `run_lanes start "$MFP"`, then assert:
    - exit 0, and `story_rows A` begins `1 A-T1 progress,`;
    - `$(last_lanes_dir)/stories/A` begins `landed`;
    - the A branch on origin has `tests/ring_ticks.pending` containing `BLOCKED A ring_ticks:`, and `docs/game-dev/playtests/demo-blocks.md` containing `## A B1 — ring_ticks — OPEN`;
    - no `held` anywhere in `events.jsonl` for A.

  Add `test_lanes_missing_tool_still_stops`: the same fixture, with `$SCEN/A` = `stop ffmpeg not found on PATH (tools/convert_ambience.py)` under `lholds_on 120`, modelled on `test_lanes_push_rejected_first_unit_holds`. A is held with `stop: ffmpeg not found on PATH`, and the row is `stop`.
- [ ] **Step 2: Run them.** The first fails because the action is unknown (`stub: unknown action`); the second passes today, which is expected, since it pins today's behaviour.
- [ ] **Step 3: Implement the stub action** in the `case "$act"` list. Use `st ledger` and `commit_ledger`, as `ruling` does, plus `git add` of the two files.
- [ ] **Step 4: Run them and confirm both pass.**
- [ ] **Step 5: Commit.** `test(overnight): a Block unit carries on, a missing tool still holds (#94)`

### Task 8: The runner lists Blocks in the report and the final PR body (#94)

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight` — `write_report`: `## Blocks` after `## Rulings`, grep `^- [0-9-]* ([^ ]+ )?Block: `, `(none)` when there are none
- Modify: `studios/game-dev/bin/overnight-lanes.sh`:
  - `story_ledger_lines`: add `Block: ` to its alternation;
  - `final_body`: add `Block: ` to the per-story grep, then after `## Not landed`, a `## Blocks file` section per distinct `— blocks <path>` across the landed stories' Block lines. Each section is headed `### <path>`, read from `$FINAL_W/<path>`, and capped at 20000 bytes (`head -c 20000`) with the line `(truncated — read <path> on the branch)` when cut. `final_body` needs `FINAL_W`, which `final_integration` sets before calling it. In direct mode `final_body` is not used, and the skill's own PR body carries Blocks.
- Test: `tests/overnight_lanes_test.sh`, `tests/overnight_test.sh`

**Interfaces:**
- Consumes: Task 7's `block` action, and Task 1's fixture patterns.

- [ ] **Step 1: Write the failing tests.**
  - Extend `test_lanes_block_carries_on`:
    - `$GH/body-1` has `^- [0-9-]* T1 Block: ring_ticks — ticks: 12 vs 13 — blocks docs/game-dev/playtests/demo-blocks.md$`, `^## Blocks file$`, `^### docs/game-dev/playtests/demo-blocks.md$` and `^## A B1 — ring_ticks — OPEN$`;
    - `report.md` lists the Block line under A.
  - Add a `final Block: golden — a: 1 vs 2 — blocks docs/game-dev/playtests/demo-blocks.md` line through a `ruling final Block: …` action on a later unit, and assert it is in the body too (Review Focus 4).
  - Add `test_lanes_blocks_file_capped`: a blocks file of 30000 bytes committed by the unit (a `ruling` plus a stub post action `bigblocks`, or the `block` action with `STUB_BLOCKS_PAD=30000`). The body holds `(truncated — read docs/game-dev/playtests/demo-blocks.md on the branch)` and is under 25000 bytes in that section.
  - In `tests/overnight_test.sh`, add `test_overnight_report_blocks`:
    - scenario `branch fb; ledger T1 Block: golden — a: 1 vs 2 — blocks docs/b.md; task 1/1; …` (follow an existing single-plan test that reaches `shipped`, for example the one that asserts `## Rulings`; find it with `grep -n 'Rulings' tests/overnight_test.sh`, or else the done-path test);
    - `report.md` has `^## Blocks$` followed by the Block line;
    - a run with no Block lines has `## Blocks` then `(none)`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement, as described in Files.**
- [ ] **Step 4: Run them and confirm they pass,** together with `test_lanes_final_step_once` (its `T1 Ruling:` assertion is unchanged).
- [ ] **Step 5: Commit.** `feat(overnight): Block lines and the blocks file reach the report and the final PR (#94)`

### Task 9: Docs, floors, the full gate

**Files:**
- Modify:
  - `README.md` — under the overnight runner's bullets: one bullet on Blocks (a pinned-reference mismatch is recorded and carries on; where it shows up);
  - `docs/game-dev/PROGRESS.md` — an entry for 2026-10-23 naming #94 #95 #82, in the style of the latest entry, with the note "install after #93 lands and pid 10051 has exited";
  - `tests/run_all.sh` — the floors of every suite this plan grew.

- [ ] **Step 1: Write the docs.**
- [ ] **Step 2: Measure the new counts.** For each changed suite (`overnight_lanes_test`, `overnight_test`, `overnight_runs_test`, `studio_brief_test`, `studio_test`), run `sh tests/run_all.sh` once, read each suite's assertion count from its summary, and set that suite's floor to that count.
- [ ] **Step 3: Run the full gate twice.** `sh tests/run_all.sh` must be green; then run `TEST_SH=dash sh tests/run_all.sh` as well. Paste both summary lines into the PR body.
- [ ] **Step 4: Commit.** `docs: Blocks, required_tools, #82; raise floors (#94, #95, #82)`
