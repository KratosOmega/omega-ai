# Overnight gate repair — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native; one Opus whole-branch review at the end). Steps use `- [ ]`.

**Goal:** in a lane run, a story whose finish gate is red gets a gate-repair unit and a fresh finish (full gate) instead of stopping; bounded by `overnight.gate_repairs`.

**Architecture:** across sessions, never inside one: finish (gate once) → `Stop: gate red — …` → runner launches `/game-dev:execute --gate-repair` (fix + targeted test only) → `Repair:` line → runner re-runs `story_units` (a fresh finish re-runs the full gate). The runner still never writes studio state.

**Tech stack:** POSIX sh (`studio-overnight`, `overnight-lanes.sh`), the execute skill (markdown), sh test suites with the stub `claude`.

**Spec:** the story text in the session that created this plan (copied into the commit message of the runner task); acceptance list reproduced under each task.

## Global Constraints

- POSIX sh, same style as the existing scripts (comment block per function, `_xx_` locals).
- Non-lane (single-feature) mode behaviour unchanged.
- The runner never writes studio state; only sessions write the ledger.
- `overnight.gate_repairs`: int, default 2, range 0-3; 0 = today's behaviour.
- Only `Stop: gate red — …` is repairable; every other stop stays hard.

## Review Focus

1. A Stop line copied into the feature ledger from the Docs revision appears in both ledgers — must not read as a new stop once counting replaces `sort -u` (per-ledger occurrence numbering, deduped across ledgers).
2. Unit numbering across the retry: `story_units` resets `n=0`, so a second call would overwrite `1-<id>-T1.jsonl` etc. — `n` must continue.
3. A halt (stop file, runner gone, run budget) between the repair and the retry ends the story with the halt reason, launching nothing.
4. The run budget refuses a gate-repair launch the way `story_units` refuses a unit (`stop: run budget`, lane budget flag).
5. No `test-*.log` in the feature checkout (a red `studio-run` or `studio-lint`, or an adapter without logs) → `STUDIO_REPAIR=gate:-`; the skill reads the Stop line instead.

---

### Task 1: runner — gate-repair unit, retry loop, cap, stop detection by count

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight` — `model_for` (~88-96), help Config table (~200-215), `cfg` block (~300-340), `snapshot` (~368-377), `story_units` (~731-760).
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — new `gate_repair` + `gate_log_of` near `land_repair` (~474), `run_story` (~684-708).
- Test: `tests/overnight_lanes_test.sh` (stub kind `<id>.gate`, actions `gaterepair`, `gatelog`), `tests/overnight_test.sh` (help names `gate_repairs`; config refuses `"gate_repairs": 4`).

**Interfaces:**
- `snapshot FILE` — FILE holds each Stop line suffixed `\t<k>` (k = its occurrence number within its own ledger), deduped across the two ledgers, sorted. Consumers strip the suffix: `_new="${_new%	*}"`.
- `story_units` — continues the caller's `n` (`n="${n:-0}"`); the before-snapshot is taken on its own first pass.
- `model_for gate-repair` → `MODEL_REPAIR`.
- `GATE_REPAIRS` (from `cfg gate_repairs 2 0 3 int`).
- `gate_log_of DIR` → newest `DIR/.studio/reports/test-*.log` (abs), else `-`.
- `gate_repair ID` → 0 when a `Repair:` line was added (retry); 1 with `ENDING` set: `stop: <reason>` (a new Stop line), `gate repair made no progress`, `gate repair timed out (session_minutes N)`, `stop: run budget`, or the halt reason.
- `run_story` loop: while `ENDING` is `stop: gate red — *`: cap reached → `ENDING="gate red after <k> repairs — <line>"` (unchanged when `GATE_REPAIRS=0`); else `gate_repair` then `story_units` again.

- [ ] Step 1: stub — kind `*--gate-repair*` → `$id.gate`; `gaterepair` (terminal: in the story worktree ledger `Repair: gate — fixed`, commit, push); `gatelog` (modifier: writes `<story wt>/.studio/reports/test-<stamp>.log`).
- [ ] Step 2: failing tests in `overnight_lanes_test.sh`:
  - `test_lanes_gate_repair_then_lands` — A:- B:A; A line 3 `gatelog; stop gate red — studio-test: 1 failed`; `A.gate` = `gaterepair`. A landed, B landed, one `--gate-repair` call: prompt, model opus, `STUDIO_REPAIR=gate:<abs log>`, units.tsv row `A-gate-repair … progress`, unit stems unique (no overwrite: 5 A rows numbered 1-5).
  - `test_lanes_gate_repair_cap` — `gate_repairs: 1`, lines 3 and 4 two different gate-red stops → `stopped gate red after 1 repairs — <second>`; B `skipped A`; one repair call.
  - `test_lanes_gate_repair_same_stop_twice` — `gate_repairs: 1`, the identical stop at lines 3 and 4 → `stopped gate red after 1 repairs — X` (missed detection would retry the finish and ship).
  - `test_lanes_gate_repairs_zero` — `gate_repairs: 0` → `stopped stop: gate red — X`, no repair call, B skipped.
  - `test_lanes_gate_hard_stops_no_repair` — A, B, C independent: exit-2 message, exit-3 hint, `gate timed out — studio-test ran past 90 min` → each `stopped stop: …`, zero repair calls.
  - `test_lanes_gate_repair_no_progress` — `A.gate` = `noop` → `stopped gate repair made no progress`; `stop gate repair red — X` → `stopped stop: gate repair red — X`, one repair call (a repair's red is hard).
  - `test_lanes_gate_repair_model` — `model_repair: r-m` → the repair runs `--model r-m`; no log → `STUDIO_REPAIR=gate:-`.
  - `overnight_test.sh`: help names `gate_repairs`; config refusals add `'"gate_repairs": 4'`.
- [ ] Step 3: run `sh tests/overnight_lanes_test.sh` — new tests fail.
- [ ] Step 4: implement (snapshot, story_units, model_for, cfg+help, gate_log_of, gate_repair, run_story).

  ```sh
  # snapshot tail
  _stops() { grep '^- [0-9-]* Stop: ' | awk '{ k[$0]++; printf "%s\t%d\n", $0, k[$0] }'; }
  if [ "$FEATURE_DIR" = "$START_DIR" ]; then printf '%s\n' "$_l" | _stops
  else { printf '%s\n' "$_l" | _stops; ledger_of "$START_DIR" | _stops; }; fi | sort -u > "$1"
  ```
- [ ] Step 5: `sh tests/overnight_lanes_test.sh && sh tests/overnight_test.sh` green.
- [ ] Step 6: commit `feat(overnight): lanes repair a red integration gate across sessions`.

### Task 2: execute skill, docs

**Files:**
- Modify: `studios/game-dev/skills/execute/SKILL.md` — §1 mode list; §5 (gate-enforced findings never left/deferred); §7 lane rules (name the gate-repair unit); new §11 `Gate repair (--gate-repair)` modeled on §9.
- Modify: `README.md` overnight section, `docs/game-dev/PROGRESS.md` (new log entry).
- Test: `tests/studio_test.sh` contract asserts (`--gate-repair`, `Repair: gate —`, `Stop: gate repair red —`, `gate_repairs`, the §5 rule, no "only its repair unit repairs it").

- [ ] Step 1: failing contract asserts; Step 2: write the text; Step 3: `sh tests/run_all.sh` green; Step 4: commit `docs(execute): gate-repair unit; gate-enforced findings never deferred`.

### Final

- [ ] Opus whole-branch review; fix wave; full suite `sh tests/run_all.sh`.
