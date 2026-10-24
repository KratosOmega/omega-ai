# Overnight throughput Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make overnight runs use the Mac mini. Plan-time story splitting puts work in parallel lanes, a one-lane run warns and offers backfill, vitest workers and gate caps are sized to the machine, lanes run checkpoint suites, and the skills use only command forms that worktree isolation does not refuse.

**Architecture:** POSIX-sh verbs in `studios/game-dev/bin/` plus skill-text rules.
- `studio-brief` gains `After:` validation and a `tracks` subcommand. `gate-class.sh` gains the worker count. `gate-times.sh` gains the learned cap.
- `studio-overnight` and `overnight-lanes.sh` gain three preflight readouts and one launch env word.
- New verbs `studio-vitest`, `studio-tsc`, `sdd-run` and `studio-docs-sync` replace the prescribed forms that isolation refuses.
- The plan, execute and autopilot skills carry the new rules. Contract and pointer tests pin them.

**Tech Stack:** POSIX sh (macOS `/bin/sh` and dash), awk, git; the repo's `tests/assert.sh` runner.

**Spec:** `docs/game-dev/specs/2026-10-23-overnight-throughput.md` (approved 2026-10-23).

## Global Constraints

- POSIX sh only. Every script passes under macOS `/bin/sh` (bash 3.2) and dash, and sets `unset LC_ALL; LC_COLLATE=C` as the other bin scripts do.
- Every new config key is listed in `studio-overnight --help`'s Config block with its default and range. A present value out of range or of the wrong kind is a refusal (`refuse`).
- On the old 4-core laptop with phoenix's measured times, every new automatic value works out to today's value, or is off.
- No existing gate, reviewer or test is weakened. The finish gate still runs the whole gate once.
- Every skill wording change updates its pin in `tests/studio_test.sh`, `tests/pointer_skills_*` or `tests/omega_contracts/*`.
- `sh tests/run_all.sh` is green at the end.
- New preflight stdout lines go after #93's `push_check` and #95's `tools_check`, before `env_line`, and never reorder them. If #95 has not landed when a task runs, they go directly after `push_check`. #95's rebase then puts `tools_check` between `push_check` and them.
- **Rebase before Task 1, and again before Task 6:** onto `origin/main` once PR #93 has merged, and onto `origin/fix/block-and-tools` if it has landed. That branch adds execute §6a "Blocks" and edits §2, §4, §5, §7-§9 and §11, the same sections Tasks 4 and 6-8 edit.
- Commit subjects use the repo's style (`feat(overnight): …`, `feat(studio-brief): …`, `docs(skills): …`), each ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A `Files:` path written two ways (`./scripts/a.gd`, `res://scripts/a.gd`, trailing spaces, backticks) must join the same track. Normalize before comparing (Task 1).
2. `### Task`, `Files:` or `After:` lines inside a fenced code block must be ignored, as `plan_tasks` ignores fenced headings (Task 1).
3. `gate.times` holds old 4-field rows, malformed lines and `main:<reason>` lanes. The learned cap and the suite median read only well-formed 8-field rows. Any other line is skipped, never a crash, and the fallback is today's cap (Tasks 5, 6).
4. A config value written as `6`, `"6"` or `"auto"`. `cfg_raw` returns `"auto"` with its quotes, and every new key must accept both spellings (Tasks 4, 5, 6).
5. A resumed lane story whose ledger already holds `T<n> complete` lines from before this feature has no `suite green` line. The checkpoint count starts at its `base` line, so the first checkpoint fires at once, which is safe and expected (Task 6).

---

### Task 1: `studio-brief` — `After:` validation and `tracks`

**Files:**
- Modify: `studios/game-dev/bin/studio-brief` (usage line :76; `validate)` branch :287-326; a new `tracks)` branch; header comment :32)
- Test: `tests/studio_brief_test.sh`

**Interfaces:**
- Produces:
  - `studio-brief tracks <plan>` prints `tracks: <K>`, then one line per track: `track <k>: T<a> T<b> … — <m> tasks — files: <p1>, <p2>, …`. Tasks are in ascending order, tracks are ordered by their smallest task, and files are sorted and unique.
  - Exit 0, or 2 for bad usage or a missing plan.
  - Only tasks above `## Backlog` count.
  - Edges: a shared normalized `Files:` path, or an `After:` reference in either direction.
- Produces: `validate` fails (exit 1) with `studio-brief: task <n>: After: T<m> is not an earlier task above ## Backlog` for a forward, self, unknown or backlog reference.

- [ ] **Step 1: Write the failing tests** in `tests/studio_brief_test.sh`:
  - `test_tracks_two_groups`: a fixture plan T1(`a.gd`) T2(`a.gd, b.gd`) T3(`x.js`) T4(`x.js`). Expect the output exactly:
    ```
    tracks: 2
    track 1: T1 T2 — 2 tasks — files: a.gd, b.gd
    track 2: T3 T4 — 2 tasks — files: x.js
    ```
  - `test_tracks_after_joins`: the same plan, with T3 gaining `After: T2`. Expect `tracks: 1`.
  - `test_tracks_normalizes_paths`: T1 `Files: ./a.gd`, T2 `Files: res://a.gd`, and a backticked `` `a.gd` ``. All three join: `tracks: 1`.
  - `test_tracks_ignores_backlog_and_fences`: T5 under `## Backlog` shares `x.js`, and a fenced block holds `### Task 9:` with `Files: a.gd`. Neither changes the two-track output.
  - `test_tracks_deterministic`: two runs give identical stdout.
  - `test_validate_after_forward_fails` (`After: T3` on T2), `test_validate_after_unknown_fails` (`After: T9`), `test_validate_after_ok` (`After: T1` on T2). Plus the existing no-`After:` fixture still passes (assert exit 0).
- [ ] **Step 2: Run them and see them fail.** `sh tests/studio_brief_test.sh`. Expected: the new tests FAIL (`tracks` is an unknown verb; `After:` is not checked).
- [ ] **Step 3: Implement.**
  - Add `plan_tasks_above_backlog PLAN`: `plan_tasks`'s awk, stopping at a `^## Backlog` line outside a fence.
  - Add `task_field PLAN N KEY`, which prints the value of `KEY:` inside `### Task N:`'s block (from `section`).
  - Path normalization: strip backticks, a leading `./` or `res://`, and surrounding spaces; split on `,`.
  - `tracks` is a union-find over task numbers in one awk program, fed `<task>\t<file>` and `<task>\t@T<m>` rows.
  - Add the `After:` check to `validate`'s per-task loop.
- [ ] **Step 4: Run the tests and see them pass.** `sh tests/studio_brief_test.sh`. Expected: all ok, no FAIL.
- [ ] **Step 5: Commit** `feat(studio-brief): After: lines and the tracks subcommand`.

### Task 2: Plan skill — the split at the plan gate

**Files:**
- Modify: `studios/game-dev/skills/plan/SKILL.md` (§2 task lines :61-90; §6 self-review and stop :186-208; §7 sweep :236-258)
- Test: `tests/studio_test.sh` (a new `test_plan_split_rules`)

**Interfaces:**
- Consumes: `studio-brief tracks <plan>` (Task 1) and `studio-overnight check-id` (existing).
- Produces: the sibling naming rule (`<id>-<k>`, `<Branch>-<k>`, `<plan stem>-<k>.md`) and the commit subject `docs(plans): approve <topic> (split <S>)`, which Task 3's test fixture reproduces.

- [ ] **Step 1: Write the failing test** `test_plan_split_rules` in `tests/studio_test.sh`. It asserts that the plan skill contains each literal:
  - `After: T<a>[, T<b>…]`
  - `studio-brief tracks <plan>`
  - `at least two tracks with at least 3 tasks each`
  - `Reply **approve** (split), **approve one** (keep one story), or name the task to change.`
  - `<id>-<k>`, `<Branch>-<k>`, `<plan stem>-<k>.md`
  - `A **feature AC** that tasks in two tracks both implement ties those tracks`
  - `A **cross-cutting AC**`
  - `docs(plans): approve <topic> (split <S>)`
  - `becomes a manifest Depends on`

  It also asserts that, for a manifest story, the conflict-scan paragraph appears before `studio-brief tracks` in the file (compare line numbers with `grep -n`).
- [ ] **Step 2: Run it and see it fail.** `TESTS_ONLY=test_plan_split_rules sh tests/studio_test.sh`. Expected: FAIL on the first literal.
- [ ] **Step 3: Write the skill text.**
  - §2 adds the `After:` line beside `Review:`, with its one-line meaning.
  - §6 gets a new **Split for parallel lanes (manifest stories only)** block, before the approval stop. It carries the spec's A3 steps 1-4 as written, with the conflict scan moved here first (spec A1).
  - The stop message gains the split line and the `approve one` reply.
  - §7 step 1 says the conflict scan already ran in §6 for a manifest story. A dependency across siblings found later becomes a manifest Depends on.
  - Keep every existing literal that `tests/studio_test.sh` and `tests/pointer_skills_*` pin. Run both to check.
- [ ] **Step 4: Run the tests and see them pass.** `sh tests/studio_test.sh`, `sh tests/pointer_skills_route_test.sh`, `sh tests/pointer_skills_execute_test.sh`. Expected: no FAIL.
- [ ] **Step 5: Commit** `docs(plan): split a manifest story into parallel tracks at the plan gate`.

### Task 3: One lane in effect — the readout and the backfill offer

**Files:**
- Modify:
  - `studios/game-dev/bin/overnight-lanes.sh` (`lanes_dry_run` :412, `lanes_start` :2076, after `build_chains`)
  - `studios/game-dev/bin/studio-overnight` (`preflight()` single-plan path, after `tools_check`)
  - `shared/omega/skills/autopilot/SKILL.md` (step 3, after the overlap check)
- Test: `tests/overnight_lanes_test.sh`, `tests/overnight_test.sh`, `tests/omega_contracts/autopilot_contract.sh`

**Interfaces:**
- Produces: `one_lane_note` in `overnight-lanes.sh`. It prints on stdout exactly
  `one lane: a hold idles this run until you answer; add an independent story to keep the machine busy`
  when the chain count is 1 or `MAX_LANES` is 1, and prints nothing otherwise. The single-plan preflight prints the same line unconditionally.

- [ ] **Step 1: Write the failing tests.**
  - `test_lanes_one_lane_note_one_chain`: `lanes_fixture` with `A:- B:A`; `--dry-run` stdout contains the line; exit 0.
  - `test_lanes_one_lane_note_max_lanes_1`: `A:- B:-` with `LANES_CONFIG='{"overnight": {"max_lanes": 1}}'`; the line is printed.
  - `test_lanes_no_note_two_chains`: `A:- B:-`; the line is absent.
  - `test_lanes_split_siblings_planned`: a fixture whose rows are `A:-` and `A-2:-`, with the same spec, two plans, and both `plan approved` lines. `next` prints `next: /omega:autopilot demo`, and `--dry-run` shows two chains.
  - `test_single_plan_one_lane_note` (overnight_test.sh): the single-plan `--dry-run` prints the line.
  - Autopilot contract: step 3 contains `**add a backfill story**`, `**run as is**`, and the backfill offer comes before `Check that the run worktree has \`.studio/run\` before the first seed`.
- [ ] **Step 2: Run them and see them fail.** `TESTS_ONLY="test_lanes_one_lane_note_one_chain test_lanes_one_lane_note_max_lanes_1 test_lanes_no_note_two_chains test_lanes_split_siblings_planned" sh tests/overnight_lanes_test.sh`, and the same for the other two suites. Expected: FAIL on the missing line or literal. `test_lanes_split_siblings_planned` may already pass: if so, keep it as the AC4 pin.
- [ ] **Step 3: Implement.**
  - Add `one_lane_note` and call it from `lanes_dry_run` and `lanes_start` after the chains are built.
  - In single-plan `preflight()`, print the line after `tools_check`.
  - In autopilot step 3, add the offer per spec A4: the same rule over the manifest rows, one `AskUserQuestion`, and step 3 again from the top after a backfill row is planned.
- [ ] **Step 4: Run the tests and see them pass.** The three suites above. Expected: no FAIL.
- [ ] **Step 5: Commit** `feat(overnight): one-lane readout and a backfill offer before seeding`.

### Task 4: `studio-vitest`, `studio-tsc` and `node_workers`

**Files:**
- Create: `studios/game-dev/bin/studio-vitest`, `studios/game-dev/bin/studio-tsc`
- Modify:
  - `studios/game-dev/bin/gate-class.sh` (add `gate_node_workers` after `gate_phys_cores` :203)
  - `studios/game-dev/bin/overnight-allow.txt`
  - `studios/game-dev/bin/studio-overnight` (`--help` Config block: top-level `node_workers`, `node_dir`)
  - `studios/game-dev/skills/plan/SKILL.md` §2 (:85-87)
  - `studios/game-dev/skills/execute/SKILL.md` §2 (:380-386)
  - `shared/omega/skills/autopilot/SKILL.md` step 1a.4 (:125)
  - `README.md` toolkit table
- Test:
  - `tests/gate_class_test.sh` (worker count)
  - `tests/toolkit_test.sh` (the verbs, with a stub `npx` and `studio-gate` on `PATH` that record argv)
  - `tests/studio_test.sh` and `tests/omega_contracts/autopilot_contract.sh` (pins: the old `cd <node dir> && studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=2` literal in studio_test.sh :640 becomes `studio-vitest <file>…`)

**Interfaces:**
- Produces:
  - `gate_node_workers`. It prints a positive integer: the `node_workers` value from `studio_cfg` (an integer 1-32) when one is set, else max(2, `gate_phys_cores` / 2) (integer division), else 2 when the cores are unreadable. A bad value prints `gate: node_workers must be auto or 1-32, got <v>` on stderr and returns 1.
  - `studio-vitest [--dir D] [-t P] [ARG…]` changes into the node dir, then execs `studio-gate vitest -- npx vitest run --minWorkers=1 --maxWorkers=<W> [-t P] ARG…`. W = 2 iff there is at least one ARG and every ARG is an existing file. Otherwise W = `gate_node_workers`.
  - `studio-tsc [--dir D]` execs `studio-gate tsc -- npx tsc --noEmit` from the node dir.
  - The node dir is `--dir`, else `studio_cfg node_dir`, else `.` when `./package.json` exists. Otherwise exit 2 with `studio-vitest: no node dir — set node_dir in .studio/config.json or pass --dir` (`studio-tsc:` likewise).

- [ ] **Step 1: Write the failing tests.**
  - `test_node_workers_auto`: `STUDIO_GATE_PHYS_CORES=4` gives `2`; `12` gives `6`; `2` gives `2`; unset with a stubbed `uname` of `Plan9` gives `2`.
  - `test_node_workers_config`: `{"node_workers": 8}` gives 8, `{"node_workers": "auto"}` gives auto's value, `33` returns 1.
  - `test_vitest_files_two_workers`: one file and five files both give `--maxWorkers=2`, and `studio-gate --classify -- npx vitest run --minWorkers=1 --maxWorkers=2 <the five files>` prints class `short`.
  - `test_vitest_dir_node_workers` (a dir, and no ARG): `--maxWorkers=6` with `STUDIO_GATE_PHYS_CORES=12`, classified exclusive.
  - `test_vitest_no_node_dir`: exit 2 and the message.
  - `test_tsc_runs_from_node_dir`: the recorded cwd is the node dir.
  - The pin updates in `studio_test.sh` and the autopilot contract assert the new forms, and assert `cd <node dir> && studio-gate vitest` is absent.
- [ ] **Step 2: Run them and see them fail.** `sh tests/gate_class_test.sh`, `sh tests/toolkit_test.sh`. Expected: FAIL (no such verb or function).
- [ ] **Step 3: Implement** the function and both verbs (header comments in the house style: usage, exit codes, config). Add both verbs to `overnight-allow.txt` in its existing rule form. Rewrite the three skill passages to `studio-vitest <file>…` and `studio-tsc`. Add the help and README lines.
- [ ] **Step 4: Run the tests and see them pass.** The suites above, plus `sh tests/gate_lanes_test.sh` (unchanged short-lane behaviour). Expected: no FAIL.
- [ ] **Step 5: Commit** `feat(studio): studio-vitest and studio-tsc; node_workers sized to the machine`.

### Task 5: The learned gate cap

**Files:**
- Modify:
  - `studios/game-dev/bin/gate-times.sh` (add `gate_learned_cap`)
  - `studios/game-dev/bin/studio-gate` (cap setup :323-331; the 124 message)
  - `studios/game-dev/bin/studio-overnight` (`cfg gate_cap_factor 4 0 10 int` in `preflight()`; `caps_env` :772 adds `STUDIO_GATE_CAP_FACTOR`; a `gate caps:` readout after the `one lane:` line; `--help`)
- Test: `tests/gate_times_test.sh` (the function), `tests/gate_lanes_test.sh` (the cap firing), `tests/overnight_test.sh` (readout, env word)

**Interfaces:**
- Produces:
  - `gate_learned_cap FILE WHO FACTOR MAXMIN`. It prints whole minutes, or nothing.
    - Rows: well-formed 8-field rows whose `who` = WHO, rc = 0 and lane is `main` or starts with `main:`.
    - Fewer than 5 rows, FACTOR 0, or MAXMIN empty or 0: it prints nothing.
    - Otherwise it prints clamp(ceil(FACTOR × p95(hold) / 60), 15, MAXMIN), with p95 by nearest rank over the newest 50 such rows.
  - `studio-gate` uses it only when `STUDIO_GATE_MINUTES` > 0 and WHO ≠ `setup`. The binding cap is the learned value. The 124 line is
    `gate: <who> ran past its learned cap of <N> min (<F> × p95 of the last <M> runs) — stopped`.
  - `STUDIO_GATE_CAP_FACTOR` (0-10) travels in `caps_env`. When it is unset, studio-gate uses 4.

- [ ] **Step 1: Write the failing tests.**
  - `test_learned_cap_needs_five_rows`: 4 rows print nothing, 5 rows print a value.
  - `test_learned_cap_p95_and_clamp`:
    - holds of 60 s ×4 and 290 s with F=4 and MAX=60 give 20;
    - holds of 30 s ×5 give 15 (the floor);
    - holds of 1200 s ×5 with MAX=60 give 60.
  - `test_learned_cap_skips_bad_rows`: a 4-field row, a `short` lane row, rc 1 rows and a garbage line are ignored.
  - `test_learned_cap_factor_zero`: prints nothing.
  - `test_gate_learned_cap_fires` (gate_lanes_test.sh): 5 rows of 1 s for `who` `probe`, `STUDIO_GATE_MINUTES=60`, `STUDIO_GATE_SECONDS` unset, and a command that sleeps past a test-only floor. Use `STUDIO_GATE_LEARNED_FLOOR_SECONDS`, a new test knob named in the header that defaults to 900, at production value in one other test. Expected: exit 124 and the learned-cap line.
  - `test_overnight_caps_readout`: gate.times with 5 `studio-test` rows gives `--dry-run` stdout containing `gate caps: studio-test 20 min (×4 p95)`. The single-plan launch env contains `STUDIO_GATE_CAP_FACTOR='4'`.
- [ ] **Step 2: Run them and see them fail.** The three suites, with `TESTS_ONLY` set to the new names. Expected: FAIL.
- [ ] **Step 3: Implement** per the Interfaces. The readout lists every `who` with ≥ 5 rows as `<who> <N> min`, and the rest under `default <GATE_MIN> min for <who>, … (fewer than 5 runs)`.
- [ ] **Step 4: Run the tests and see them pass.** The three suites, full. Expected: no FAIL.
- [ ] **Step 5: Commit** `feat(gate): a run cap learned from gate.times (gate_cap_factor)`.

### Task 6: Checkpoint suites in lanes

**Files:**
- Modify:
  - `studios/game-dev/bin/studio-overnight` (`preflight()`: resolve `suite_every`; readout; `--help`)
  - `studios/game-dev/bin/overnight-lanes.sh` (`story_launch_env` :392 adds `STUDIO_SUITE_EVERY`)
  - `studios/game-dev/skills/execute/SKILL.md` (§3 `suite` bullet; §5 step 2 pattern :507; §8 task unit; §11 preconditions note)
  - `tests/overnight_lanes_test.sh` (the fake session gains a `checkpoint` scenario action)
- Test: `tests/overnight_test.sh`, `tests/overnight_lanes_test.sh`, `tests/studio_test.sh`

**Interfaces:**
- Produces:
  - `suite_every_resolve` sets `SUITE_EVERY` (an integer) and `SUITE_NOTE` (the readout text).
    - Config is an integer 0-20 or `"auto"`. In a single-plan run it is always 0 with `off — single-plan run`.
    - Auto: the newest 10 well-formed rc-0 main-lane `studio-test` rows of `$STATE_ROOT/.studio/gate.times`. Fewer than 3 gives 0 (`off — fewer than 3 suite runs`). A median ≤ 480 s gives 4 (`every 4 tasks (median suite <m.m> min)`). Otherwise 0 (`off — median suite <m.m> min`).
  - Readout: `suite checkpoint: <SUITE_NOTE>`, after `gate caps:`.
  - Launch env word: `STUDIO_SUITE_EVERY='<n>'`, in manifest stories only.
  - Ledger lines (execute):
    - `suite green T<n> <full sha>`
    - `Stop: gate red — checkpoint after T<n> — <failing line>`
  - Commit subject (execute): `fix(suite): <summary>`.

- [ ] **Step 1: Write the failing tests.**
  - `test_suite_every_auto_on` (median of 4.5 min over 10 rows gives every 4) and `test_suite_every_auto_off_slow` (20 min gives off).
  - `test_suite_every_few_rows` (2 rows gives off) and `test_suite_every_config` (`2` gives 2, `"auto"` is accepted, `21` is a refusal).
  - `test_suite_every_single_plan_off`: the readout says `off — single-plan run`, and the launch env has no `STUDIO_SUITE_EVERY`.
  - `test_help_lists_new_keys`: `studio-overnight --help` lists `suite_every`, `gate_cap_factor`, `node_workers` and `node_dir`, each with its default and range (AC15).
  - `test_lanes_suite_every_env`: a lane's `$CALLS/<n>.env` contains `STUDIO_SUITE_EVERY=4`. The fixture seeds gate.times with 10 rows of 270 s.
  - `test_lanes_checkpoint_red_repairs_then_next_task`:
    - Setup: `LANES_TASKS=4`, and the scenario for A is `auto`, `checkpoint stop gate red — checkpoint after T2 — studio-test: 1 failed`, `auto`, `auto`, `auto`, `auto`, plus `A.gate` with `gaterepair`. The new fake action `checkpoint` completes the task (advances `task`, writes `T<n> complete`), then writes the Stop.
    - Expected rows: `1 A-T1 progress,2 A-T2 stop,3 A-gate-repair progress,4 A-T3 progress,5 A-T4 progress,6 A-final-review progress,7 A-finish done,`, and A lands.
    - This proves AC12: no T2 re-run, and no finish in between.
  - `test_execute_checkpoint_rules` (studio_test.sh): the execute skill contains
    - `STUDIO_SUITE_EVERY`
    - `suite green T<n> <full sha>`
    - `fix(suite): <summary>`
    - `Stop: gate red — checkpoint after T<n> — <failing line>`
    - `A checkpoint never re-opens it`
    - the pattern `fix\((T[0-9]+|final|gate|review|suite|B[0-9]+)\)`
- [ ] **Step 2: Run them and see them fail.** The three suites, with `TESTS_ONLY` set to the new names. Expected: FAIL. If the red-checkpoint lane test fails for a runner reason (not only the missing fake action), fix the runner in Step 3. Spec D2 makes that part of this task.
- [ ] **Step 3: Implement** the resolver, the readout, the env word, the fake action, and the execute text: spec D1-D2 as written, in §8's task-unit flow after §6's writes, with `suite green` recorded by `Verify: suite` tasks too (§3).
- [ ] **Step 4: Run the tests and see them pass.** `sh tests/overnight_test.sh`, `sh tests/overnight_lanes_test.sh`, `sh tests/studio_test.sh`, `sh tests/pointer_skills_execute_test.sh`. Expected: no FAIL.
- [ ] **Step 5: Commit** `feat(overnight): checkpoint suites every K tasks in lanes (suite_every)`.

### Task 7: `sdd-run` and `studio-docs-sync`

**Files:**
- Create: `studios/game-dev/bin/sdd-run`, `studios/game-dev/bin/studio-docs-sync`
- Modify:
  - `studios/game-dev/bin/overnight-allow.txt`
  - `studios/game-dev/skills/execute/SKILL.md`: §0 docs sync :105-123; §1 :313-315; §2 :362; §4a :460-461; §5 :515-516. Every `bash "$(sdd-script …)"` and `git checkout $STUDIO_DOCS_REV -- …`.
  - `README.md` toolkit table
- Test:
  - `tests/sdd_script_test.sh` (sdd-run)
  - `tests/studio_test.sh` (pins :276, :548-549, :793-794, :829-834 move to the new forms)
  - a new `tests/docs_sync_test.sh`, added to `run_all.sh`'s suite list if it is not globbed

**Interfaces:**
- Produces:
  - `sdd-run [--skill S] <name> [ARG…]` resolves exactly as `sdd-script` does (run `sdd-script`; do not duplicate its logic), then `exec bash <path> ARG…`. Exit 1 with `sdd-script`'s message when that fails.
  - `studio-docs-sync [--new] [<extra path>…]`:
    - It reads `STUDIO_DOCS_REV`, `STUDIO_STORY`, `studio-state get spec` and `get plan`, and the plan's `Context:` header (parsed as `studio-brief`'s `context_part` does).
    - It runs `git checkout <rev> -- <spec> <plan> [.studio/ledger/<id>.md with --new] <context…> <extra…>`.
    - When `git diff --cached --quiet` fails, it commits `docs(<id>): plan at run docs <short rev>`, or with `--new` `docs(<id>): approved plan`.
    - Exit 0; 1 on a git failure (git's stderr passed through); 2 on usage, or on a missing `STUDIO_DOCS_REV` or `STUDIO_STORY`.

- [ ] **Step 1: Write the failing tests.**
  - `test_sdd_run_execs_script`: a fake superpowers tree in which `review-package` echoes its args gives `sdd-run review-package a b` printing `a b`.
  - `test_sdd_run_missing`: exits 1 with sdd-script's message.
  - `test_docs_sync_commits_on_change`, `test_docs_sync_noop_when_same` (no new commit), `test_docs_sync_new_adds_ledger`, `test_docs_sync_context_paths`, `test_docs_sync_usage` (exit 2 without `STUDIO_DOCS_REV`).
  - Pins: execute contains `sdd-run review-package <plan> <BASE> HEAD`, `sdd-run task-brief <plan> <n>`, `studio-docs-sync` and `studio-docs-sync --new`, and none of `bash "$(sdd-script`, `git checkout $STUDIO_DOCS_REV`.
- [ ] **Step 2: Run them and see them fail.** `sh tests/sdd_script_test.sh`, `sh tests/docs_sync_test.sh`, `sh tests/studio_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** both verbs and the execute rewrites. `sdd-script` stays, and execute's "never search; `sdd-script` not found → reinstall omega-ai" rule now names `sdd-run`.
- [ ] **Step 4: Run the tests and see them pass.** The suites above, plus `sh tests/overnight_lanes_test.sh` (its fake session may match on the docs-sync form). Expected: no FAIL.
- [ ] **Step 5: Commit** `feat(studio): sdd-run and studio-docs-sync replace the forms isolation refuses`.

### Task 8: Plain git forms everywhere, the brief rule and the guard

**Files:**
- Modify: every chained git form found by
  ``grep -rnE '`[^`]*git [^`]*(&&|;|\|)[^`]*`|`[^`]*(&&|;|\|) *git [^`]*`' studios shared --include='*.md'``.
  - That is execute (8 lines), plan (2), brainstorm (1), `shared/omega/skills/{autopilot,integration,parallel}/SKILL.md` (1, 1, 2).
  - Also every `$(…)` fed into git or `studio-state ledger` in those files, such as `studio-state ledger "adopt-base $(git rev-parse HEAD)"`.
  - Also execute §2 (the E2 sentence) and `docs/game-dev/PROGRESS.md` (the entry).
- Test:
  - a new `tests/omega_contracts/isolation_forms_contract.sh`
  - `tests/studio_test.sh`
  - `tests/omega_contracts/autopilot_contract.sh`, `tests/hook_test.sh` and the other pins the grep in Step 2 names

**Interfaces:**
- Consumes: `sdd-run`, `studio-docs-sync` (Task 7), `studio-vitest` and `studio-tsc` (Task 4).
- Produces: the E2 sentence, verbatim from the spec's §E2 block quote.

- [ ] **Step 1: Write the failing test** `isolation_forms_contract.sh`. Over every `*.md` under `studios/` and `shared/omega/`, it fails, naming file:line, on:
  - `bash "$(sdd-script`
  - `git checkout $STUDIO_DOCS_REV`
  - `cd <node dir> && studio-gate`
  - an inline backticked span, or a line inside a fenced block, that runs `git` and contains `&&`, `;` or `|`

  It also asserts that execute §2 contains the E2 sentence.
- [ ] **Step 2: Run it and see it fail.** `sh tests/omega_contracts/isolation_forms_contract.sh`. Expected: FAIL listing about 15 lines. Then `grep -rn -- '&& git commit' tests` to list the pins that will move.
- [ ] **Step 3: Rewrite each form** as numbered separate calls, keeping its meaning: a failed `git add` stops before the commit. A `$(…)` value becomes "run X; then use its output in Y". Add the E2 sentence to execute §2's brief list and to §0's rules. Update each pin to the new wording. Add the PROGRESS entry in the file's existing style: what changed, why, the measured numbers from the spec's Intent, and "install after the active runs end".
- [ ] **Step 4: Run the tests and see them pass.** `sh tests/omega_contracts/isolation_forms_contract.sh`, `sh tests/studio_test.sh`, `sh tests/omega_contracts/autopilot_contract.sh`, `sh tests/hook_test.sh`. Expected: no FAIL.
- [ ] **Step 5: Run the full gate.** `sh tests/run_all.sh`. Expected: exit 0, every suite ok.
- [ ] **Step 6: Commit** `docs(skills): plain git forms, the isolation brief rule and its guard`.
