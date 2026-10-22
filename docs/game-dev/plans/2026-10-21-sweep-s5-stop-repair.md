# S5 stop repair: a task unit's non-human Stop gets one debug-repair unit before it holds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Under a lane, a task unit's new feature-side `Stop:` that names no human-owned category
(`taste`, `scope`, `perm`, `env`, `human`) and is not a fixed-text stop gets up to `stop_repairs`
debug-repair units (`/game-dev:execute --debug-repair`, `model_repair`). Each one is followed by the
unit loop again. The story holds only when the repair fails or the cap is used (#69, G7). The skills
require a category on every Stop, and the plan sweep rewrites "stop if X" clauses.
**Architecture:** `story_gate_loop` (L) becomes one repair loop with two arms: the gate arm, byte for
byte, and a new `"stop: "*` arm guarded by a pure predicate `stop_repairable`. `stop_repair` mirrors
`gate_repair`. `story_units` (O) records the stopping unit's label in `STOP_LABEL`, which every unit
launch (`run_unit`) resets. The new unit kind `debug-repair` is added to every list of unit kinds. The
execute skill gets the category rule and a new §12 mode. The plan skill gets the sweep rule.
**Tech Stack:** POSIX sh (dash-clean), awk, python3 where already used.
**Spec:** docs/game-dev/specs/2026-10-21-backlog-sweep.md §8 (with §8.3 rulings 4, 4a, 4b)
**Story branch:** `issue-69-stop-repair` off integration/backlog-2026-10-21

**Base and story.** Umbrella #83, story #69. S5 merges **last** (spec §11 step 4). It rebases on S1-S4
and S6. Line numbers are as of 1cfca7f. S1 (L/O small hunks), S3 (O/L one-liners), S4 (O `run_unit`
:1355-1420, L `merge_wait`) and S6 (X §0/§4a/§5/§7, review SKILL :76-79, :100-101) move them. Relocate
each one with its `grep -n` anchor before you edit. Below, `$W` is the story worktree's root.

Paths: `L` = `studios/game-dev/bin/overnight-lanes.sh`, `O` = `studios/game-dev/bin/studio-overnight`,
`T` = `tests/overnight_lanes_test.sh`, `OT` = `tests/overnight_test.sh`, `X` =
`studios/game-dev/skills/execute/SKILL.md`, `PL` = `studios/game-dev/skills/plan/SKILL.md`, `R` =
`studios/game-dev/skills/review/SKILL.md`, `ST` = `tests/studio_test.sh`, `AT` = `tests/studio_adopt_test.sh`.

**Run recipe** (every "Run" below). Use a scratch cwd outside every work tree, with an existing TMPDIR.
Run long `T` selections as one background run plus its notification, never with stacked pollers.

```sh
S=/private/tmp/claude-501/-Users-xinli-GameDev-proj-omega-ai/5a98a755-7ca1-4ed6-b551-b3a3f4153b67/scratchpad/s5
mkdir -p "$S/tmp" && cd "$S" && export TMPDIR="$S/tmp"
TESTS_ONLY="<names>" sh "$W/tests/<suite>.sh"        # then the same with: dash "$W/tests/<suite>.sh"
sh "$W/integrations/multica/tests/run.sh"             # the Multica suite (not in run_all)
```

## Global Constraints

- POSIX sh only, clean under dash: no bashisms, no `local`, no `$BASHPID`.
- Config: `cfg stop_repairs 1 0 3 int`, after `cfg gate_repairs` (O:665). Default 1. `0` = today's behaviour, byte for byte (A1).
- `STOP_HUMAN_CATS="taste scope perm env human"`, in L, the single source of truth. X lists the same five in the same order.
- Stop line format: `- <date> Stop: [<category>] <reason>`. The category goes after `Stop: `, never before it (A4, F6).
- Fixed-text prefixes (never repaired): `gate red — `, `gate timed out — `, `gate repair red — `, `land repair red — `, `sync repair red — `, `worktree setup`, `adopt sync — `, `check — `.
- Unit kind / story state / label: `debug-repair`. Prompt `/game-dev:execute --debug-repair`. Env `STUDIO_REPAIR=stop:<label>`.
- Ledger line: `Repair: stop — <root cause>; <fix>`, counted with `^- [0-9-]* Repair: stop — `. Commits `fix(stop): <summary>`, `chore(studio): debug repair`.
- Endings: `debug repair made no progress<orphan_note> — after <reason>`, `debug repair timed out (session_minutes N) — after <reason>`, `debug repair stalled<stall_note> — after <reason>`. Each is followed by `$UNIT_DENY_NOTE`.
- Never a repair of a repair (4b). `STOP_LABEL` is reset on every launch (4). Stage must be `execute` (4a).
- Single-plan runs are unchanged: they have no `story_gate_loop`.
- No phoenix change (A3). No reinstall. No PROGRESS.md entry (the controller writes it).

## Review Focus

1. **Category spelling and glob quoting.** `case "$r" in "[$c] "*)` must keep `[$c] ` quoted, or
   `[taste] ` becomes a bracket expression and `t boom` reads as human-owned. These are repairable:
   `[Taste] x`, `[taste]x`, ` [taste] x`, `t boom`, `e x`, `[*] x` and `[bug] x`. Test: T3
   `test_lanes_stop_repairable_table`.
2. **Label shapes.** These are repairable: `T1`, `T12` and `T12-retry`. These are not: ``, `T`, `Tx`,
   `T1x`, `T1-retry-x`, `final-review`, `check`, `finish` and `debug-repair`. Test: T3
   `test_lanes_stop_repairable_table`.
3. **A stale `T<n>` label on a non-task unit's Stop.** A gate-repair unit (and a resume-granted gate
   repair) writes an uncategorised Stop after a task unit set `STOP_LABEL`. It must hold, even with
   `stop_repairs 3`. Test: T4 `test_lanes_stop_repair_gate_repair_stop_holds`.
4. **A plan unit that flips the stage to `execute` and then stops.** Its pre-unit stage was `plan`, so
   it is never repairable, even though the after-snapshot reads `execute`. Test: T4
   `test_lanes_stop_repair_plan_stage_holds`, second fixture.
5. **The run budget at the repair boundary.** `stop_repair` refuses with `stop: run budget`, and no
   debug-repair unit runs. Test: T5 `test_lanes_stop_repair_budget`.

## Tasks

Order: T1 → T2 → T3 → T4 → T5 → T6 → T7. T2 and T3 are independent and may run in parallel worktrees;
T4 needs both. T6 needs T3 (the `STOP_HUMAN_CATS` contract). **Risky** (per-task Opus review): T3,
T4, T5, T6. **Mechanical**: T1, T2, T7.

---

### Task 1: Test stub — the `--debug-repair` kind, two actions, the stop_repairs-0 golden — Mechanical

**Files:**
- Modify: `T:42-130` (stub header comment), `T:158-165` (kind case), `T:297-357` (actions), `T:362-372` (post actions), `T:1550-1555` (helpers)
  - Preflight fix (shared regions, see **Merge notes**): in the header, edit only S5's own action-doc lines. S2 owns :84-88, and S1 adds `push_ref` to the action docs (:58-61, :136-143). Union S5's names with S1's there, and on T:328's post-action list (`push_ref` and `stage` both). Put the `stage` arm after `rmwt` (:371), not next to S1's `push_ref` arm (after :364), and `stoprepair` after `gaterepair` (:337-338).
- Create: `tests/fixtures/overnight-stop-repairs-zero.golden`
- Test: `T` (new test after `test_lanes_gate_repair_budget`, T:1661-1668; run list T:4871ff)

**Interfaces:**
- Produces (stub):
  - kind `*--debug-repair*) kind="$id.debug"` (scenario `$SCEN/<id>.debug`, counter `m-<id>.debug`);
  - terminal action `stoprepair`: in the story worktree, an empty commit `fix(stop): fixed`, then
    `st ledger "Repair: stop — leaked state; reset it"`, then `commit_ledger debug-repair`, then
    `sg push -q origin "$BRANCH"`;
  - post action `stage <s>`: `st set stage <s>` in the cwd (where `auto` sets it).
- Produces (helpers): `debug_calls` (the count of argv files naming `--debug-repair`), `debug_call`
  (the first one's call number), and `sr_norm DIR`.

- [ ] **Step 1: Write the stub changes and `test_lanes_stop_repairs_zero_today`.**

```sh
# sr_norm DIR — what a stop_repairs-0 run shows, volatile fields masked: records, unit rows,
# story_state/unit_* events, the report's ending, not-landed and A-unit lines.
sr_norm() {
  for _sn_id in A B; do printf 'rec %s: %s\n' "$_sn_id" "$(cat "$1/stories/$_sn_id" 2>/dev/null)"; done
  printf 'rows: %s\n' "$(story_rows A)"
  grep -E '"event":"(story_state|unit_started|unit_ended)"' "$1/events.jsonl" \
    | sed -E 's/"(ts|run|unit)":"[^"]*",?//g; s/"usd":[^,}]*,?//g'
  grep -E '^(Ending|Not landed|Skipped)|^\| [0-9]+ \| A-' "$1/report.md" | sed -E 's/[0-9]+(\.[0-9]+)?/N/g'
}
test_lanes_stop_repairs_zero_today() {
  LANES_TASKS=2; LANES_CONFIG='{"overnight": {"stop_repairs": 0}}'; export LANES_TASKS LANES_CONFIG
  lanes_fixture srzero integration A:- B:A
  printf 'auto\nstop boom\n' > "$SCEN/A"; printf 'stoprepair\n' > "$SCEN/A.debug"
  run_lanes start "$MFP"
  G="$REPO_ROOT/tests/fixtures/overnight-stop-repairs-zero.golden"
  if [ "${TEST_SR_GOLDEN_WRITE:-}" = 1 ]; then sr_norm "$(last_lanes_dir)" > "$G"; fi
  sr_norm "$(last_lanes_dir)" > "$TMP/srzero.out"
  assert_eq "" "$(diff "$G" "$TMP/srzero.out")" "stop_repairs 0: records, rows, events and report as before S5"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: boom$" "the task unit's stop ends the story"
  assert_eq 0 "$(debug_calls)" "no debug-repair unit"
}
```

  Adjust the masks to the real event line (`{"v":1,"ts":…,"run":…,"event":…}`, studio-event:11). The
  golden must hold no time, no cost, no run name and no sha.
- [ ] **Step 2:** Run it with `TEST_SR_GOLDEN_WRITE=1`, **on the untouched runner** (no task below has
  started). Read the golden by hand: rows `1 A-T1 progress,2 A-T2 stop,`, `rec A: stopped stop: boom`,
  `rec B: skipped A`. Then run it without the switch. Expect PASS (it is a regression guard, so it is
  green first by design). Run it under dash too.
- [ ] **Step 3:** Commit `test(lanes): debug-repair stub kind and stop_repairs-0 golden (#69)`, with the
  attribution trailer below.

**Commit trailer** (every commit in this plan ends with these two lines):

```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HHd9n1KiKNE9YBptbSEgPL
```

---

### Task 2: `stop_repairs` config and the `debug-repair` kind everywhere kinds are listed — Mechanical

**Files:**
- Modify: `O:444-446` (help, after gate_repairs), `O:665` (cfg), `O:220-228` (`model_for`), `L:1355-1363` (`story_units_table` regex),
  `studios/game-dev/bin/studio-adopt:697`, `integrations/multica/bridge/mirror.py:14-16`, `integrations/multica/README.md:225`,
  `studios/game-dev/bin/overnight-progress.sh:10` (comment), `studios/game-dev/hooks/operator-inbox.sh:107-110`,
  `docs/game-dev/overnight-events.md:99,103`
- Test: `OT` (new test near `test_overnight_config_refusals`, OT:440-451; run list OT:2671ff), `AT:843-857` (new test after it; run list AT:1084),
  `integrations/multica/tests/test_mirror_runs.py:290-305`

**Interfaces:**
- Produces: `STOP_REPAIRS` (0-3, default 1); `model_for debug-repair` → `$MODEL_REPAIR`;
  `story_units_table` accepts `<id>-debug-repair`; the `debug-repair` story state is live for
  studio-adopt and is `in_progress` for Multica.
- Help text (exact, after O:446):

```
  stop_repairs         1     0-3      lanes: debug-repair units per story before a task unit's Stop:
                                    that names no human-owned category holds (taste, scope, perm,
                                    env, human); each is followed by the unit loop again;
                                    0 = such a stop holds at once
```

- [ ] **Step 1: Failing tests.**
  - OT `test_overnight_stop_repairs_config`:
    - `'"stop_repairs": 4'` and `'"stop_repairs": "x"'`: each is `refuse_case "config …" "stop_repairs"`;
    - `0` and `3`: `run_start --dry-run`, then `assert_eq 0 "$RS_STATUS"`;
    - help: `assert_contains "$TMP/help.txt" "stop_repairs  *1  *0-3"` and `"names no human-owned category"`.
    - The default 1 is proven in T4 (`then_lands` runs with no `stop_repairs` key).
  - AT `test_adopt_refuses_story_in_debug_repair`: `sync_repo dr`, `per_run_lock debug-repair`,
    `adopt "$W" sync S1`, then `assert_eq 1 "$AD_STATUS"` and the message `story S1 is in a live run — /hold it or wait for it to end`. Then `live_done`.
  - mirror: in the rows table, after the `sync-repair` / `held` pair, add
    `(ev("story_state", story="A", state="debug-repair"), "in_progress", None)`, then a `held` row as the
    others have.
- [ ] **Step 2:** Run the `OT` and `AT` tests and the Multica suite. Expect FAIL. The key is unknown, so
  no refusal and no help line. Adopt lets the story pass. Mirror keeps `blocked`.
- [ ] **Step 3: Implement.**
  - The cfg line and the help.
  - `model_for`: `repair|final-repair|gate-repair|sync-repair|debug-repair)`.
  - L:1359 regex: `…|gate-repair|sync-repair|debug-repair)(-retry)?$`.
  - studio-adopt:697: `running|held|repair|gate-repair|sync-repair|debug-repair|landing`.
  - mirror `STATUS`: `"debug-repair": "in_progress"`. Multica README:225: add `` `debug-repair` `` to the in_progress row.
  - overnight-progress.sh:10: "a repair, gate-repair or debug-repair unit". No code: `kind()` already
    counts it as `other` (:104-110).
  - operator-inbox.sh:109: "in a --land, --gate-repair or --debug-repair unit".
  - overnight-events.md:99: add `debug-repair` to the `story_state` values after `sync-repair`.
- [ ] **Step 4:** Run the same tests (sh and dash; the Multica suite once). Expect PASS. Also run
  `TESTS_ONLY=test_overnight_help` (OT) and `test_overnight_models_by_unit`.
- [ ] **Step 5:** Commit `feat(overnight): stop_repairs config and the debug-repair unit kind (#69)`.

---

### Task 3: `STOP_HUMAN_CATS` and `stop_repairable` — Risky

**Files:**
- Modify: `L` (insert after `gate_repair`, before the `# ---- The sync check` banner at L:749)
- Test: `T` (a sourced unit test, modelled on `test_lanes_end_sessions_spaced_path` T:1193-1205)

**Interfaces:**
- Produces: `STOP_HUMAN_CATS` (a variable); `stop_repairable` (status 0/1; writes nothing). It reads
  `ENDING`, `STOP_ENDING`, `STOP_SRC`, `STOP_LABEL`, `SIG_STAGE`, `UNIT_DENY_NOTE`, `_rs_srep` and
  `STOP_REPAIRS`, and calls O's `isolated`.
- Consumes: `isolated` (O:924), and `STOP_ENDING`/`STOP_SRC` from `take_new_stop` (O:807-817).

- [ ] **Step 1: Failing test `test_lanes_stop_repairable_table`.**

```sh
test_lanes_stop_repairable_table() {
  _srt="$( (
    SELF_DIR="$BIN"; RUN_DIR="$TMP/srt"; . "$BIN/overnight-lanes.sh"
    isolated() { [ "$SRT_ISO" = 1 ]; }
    # c WANT REASON [LABEL SRC ISO STAGE NOTE USED CAP] — one row; prints only a mismatch.
    c() {
      STOP_ENDING="stop: $2"; UNIT_DENY_NOTE="${7-}"; ENDING="$STOP_ENDING$UNIT_DENY_NOTE"
      STOP_LABEL="${3-T2}"; STOP_SRC="${4-feature}"; SRT_ISO="${5-1}"; SIG_STAGE="${6-execute}"
      _rs_srep="${8-0}"; STOP_REPAIRS="${9-1}"
      if stop_repairable; then _g=yes; else _g=no; fi
      [ "$_g" = "$1" ] || printf 'want %s got %s: [%s] %s/%s/%s/%s/[%s]/%s/%s\n' "$1" "$_g" "$2" \
        "$STOP_LABEL" "$STOP_SRC" "$SRT_ISO" "$SIG_STAGE" "$UNIT_DENY_NOTE" "$_rs_srep" "$STOP_REPAIRS"
    }
    for r in "boom" "[bug] boom" "[Taste] x" "[taste]x" " [taste] x" "t boom" "e x" "[*] x" "x [env] y"; do c yes "$r"; done
    for k in taste scope perm env human; do c no "[$k] x"; done
    for r in "gate red — x" "gate timed out — x" "gate repair red — x" "land repair red — x" \
             "sync repair red — x" "worktree setup failed — exit 5" "adopt sync — T1: empty range" "check — x"; do c no "$r"; done
    for l in T1 T12 T12-retry; do c yes boom "$l"; done
    for l in "" T Tx T1x T1-retry-x final-review check finish debug-repair; do c no boom "$l"; done
    c no boom T2 start; c no boom T2 feature 0; c no boom T2 feature 1 plan
    c no boom T2 feature 1 execute " [permission-route — denied: x]"
    c no boom T2 feature 1 execute "" 1 1; c yes boom T2 feature 1 execute "" 2 3; c no boom T2 feature 1 execute "" 0 0
    # A runner-made ending (not the unit's Stop) is never repaired.
    STOP_ENDING="stop: boom"; ENDING="stop: unexpected stage idle"; stop_repairable && echo "runner-made ending repaired"
    STOP_ENDING=""; ENDING="stop: run budget"; stop_repairable && echo "empty STOP_ENDING repaired"
  ) 2>&1 )"
  assert_eq "" "$_srt" "stop_repairable: every row of spec §8.3's table"
}
```

- [ ] **Step 2:** Run it. Expect FAIL (`stop_repairable: not found`).
- [ ] **Step 3: Implement** (full code, spec §8.3 conditions 1-7):

```sh
# STOP_HUMAN_CATS — the human-owned Stop categories (#69). The execute skill's "Every stop" lists
# the same five in this order (tests/studio_test.sh checks both). A Stop names one as
# `Stop: [<category>] <reason>`.
STOP_HUMAN_CATS="taste scope perm env human"
# stop_repairable — the ending is a task unit's new feature-side Stop that names no human-owned
# category and is no fixed-text stop, and the story has stop repairs left (spec §8.3). Reads
# ENDING, STOP_ENDING, STOP_SRC, STOP_LABEL (story_units: the stopping unit's label when its
# stage was execute; every launch resets it), SIG_STAGE (the after-snapshot), UNIT_DENY_NOTE,
# _rs_srep and STOP_REPAIRS. Writes nothing.
stop_repairable() {
  [ "${_rs_srep:-0}" -lt "${STOP_REPAIRS:-0}" ] || return 1                          # 1
  [ "${ENDING%% \[permission-route — *}" = "${STOP_ENDING:-}" ] || return 1         # 2
  [ "${STOP_SRC:-}" = feature ] && isolated || return 1                              # 3
  _xr_l="${STOP_LABEL:-}"; _xr_l="${_xr_l%-retry}"                                   # 4
  case "$_xr_l" in T[0-9]*) ;; *) return 1 ;; esac
  case "${_xr_l#T}" in *[!0-9]*) return 1 ;; esac
  [ "${SIG_STAGE:-}" = execute ] || return 1                                         # 4a
  [ -z "${UNIT_DENY_NOTE:-}" ] || return 1                                           # 5
  _xr_r="${STOP_ENDING#stop: }"
  for _xr_c in $STOP_HUMAN_CATS; do                                                  # 6
    case "$_xr_r" in "[$_xr_c] "*) return 1 ;; esac      # quoted: a literal bracket, not a glob
  done
  case "$_xr_r" in                                                                   # 7
    "gate red — "*|"gate timed out — "*|"gate repair red — "*|"land repair red — "*|"sync repair red — "*|\
    "worktree setup"*|"adopt sync — "*|"check — "*) return 1 ;;
  esac
  return 0
}
```

  Condition 2 with an empty `STOP_ENDING` is false for every `stop: …` ending. That covers the
  runner-made stops (`unexpected stage`, `run budget`, `story_resolve`). The `_xr_` prefix is unused
  today. Don't use `_sr_`: `sync_repair` uses it (L:825-848).
- [ ] **Step 4:** Run it (sh and dash). Expect PASS. Also `test_lanes_end_sessions_spaced_path`: the
  sourcing pattern still works.
- [ ] **Step 5:** Commit `feat(lanes): stop_repairable and STOP_HUMAN_CATS (#69)`.

---

### Task 4: `stop_repair`, the two-arm loop, `STOP_LABEL` — Risky

**Files:**
- Modify:
  - L: `stop_repair` after `stop_repairable`;
  - `story_gate_loop` L:1089-1107 (its comment too);
  - `run_story` L:1108-1162 (comment, `STOP_LABEL=""` at L:1127, `_rs_srep=0` at L:1130);
  - O `run_unit` L:1347 (`STOP_LABEL=""` next to `UNIT_DENY_NOTE=""`);
  - O `story_units` O:1592-1627 (head reset at :1594, and the Stop branch at :1612);
  - O `story_units`' comment block O:1580-1591.
- Test: `T` (new tests after T3's), `T:3389-3420` (`test_lanes_adopt_round_trip`: an existing test whose behaviour changes)

**Interfaces:**
- Consumes: `stop_repairable` (T3), `STOP_REPAIRS` and `model_for debug-repair` (T2), the stub kind (T1).
- Produces:
  - `stop_repair ID` returns 0 after progress (`story_write ID running`). Otherwise it returns 1 with
    `ENDING` set (spec §8.5's table).
  - `_rs_srep` is the story's debug-repair count.
  - `STOP_LABEL` is `$_base` (no `-retry` suffix) when the stopping unit's pre-unit `_stage` was
    `execute`. Otherwise it is empty.

- [ ] **Step 1: Failing tests.** Default fixture shape: `LANES_TASKS=2`, `A: 'auto\nstop boom'`
  (T2 stops feature-side; see Falsified #19). Holds are off unless a test says `lholds_on`.
  - `test_lanes_stop_repair_then_lands`:
    - setup: `LANES_CONFIG='{"overnight": {"model_repair": "r-m"}}'`; `integration A:- B:A`;
      `A: 'auto\nstop boom\nauto\nauto\nauto'`; `A.debug: 'stoprepair'`;
    - `assert_eq 0 "$LS_STATUS"`;
    - `^landed ` for A and for B;
    - `assert_eq 1 "$(debug_calls)"`;
    - with `n="$(debug_call)"`: the prompt `/game-dev:execute --debug-repair`, `sed -n 4p` argv = `r-m`,
      and `assert_contains "$CALLS/$n.env" '^STUDIO_REPAIR=stop:T2$'`;
    - `assert_eq "1 A-T1 progress,2 A-T2 stop,3 A-debug-repair progress,4 A-T2 progress,5 A-final-review progress,6 A-finish done," "$(story_rows A)"`;
    - `^| 3 | A-debug-repair | ` in report.md;
    - events: `"state":"debug-repair"` and `"label":"debug-repair","model":"r-m"`.
  - `test_lanes_stop_repair_direct_mode`: the same scenario under `direct A:-`. A lands, and
    `debug_calls` is 1.
  - `test_lanes_stop_repair_human_category_holds`: one fixture `A:- B:- C:- D:- E:-`, story i with
    `auto\nstop [<cat_i>] x`. For each: `^stopped stop: \[<cat>\] x$`. Then `debug_calls` is 0.
  - `test_lanes_stop_repair_fixed_text_holds`:
    - `A: 'auto\nstop gate timed out — studio-test ran past 90 min'`;
    - `B: 'auto\nstop worktree setup failed — exit 5'`;
    - `C: 'auto\nauto\nauto\nstop gate red — x'`, with `C.gate: gaterepair`;
    - A and B: `stopped stop: <text>`;
    - C: `^landed `;
    - `debug_calls` is 0 and `gate_calls` is 1.
  - `test_lanes_stop_repair_never_chains`: `stop_repairs 3`, `A.debug: 'stop still broken'`. Then
    `^stopped stop: still broken$`, and `debug_calls` is 1.
  - `test_lanes_stop_repair_non_task_unit`: default one task, `A: 'auto\nstop boom'` (final-review).
    Then `^stopped stop: boom$`, and `debug_calls` is 0.
  - `test_lanes_stop_repair_skips_denied_unit`: `F` is the permission-denied fixture (T:3029).
    `A: 'auto\nemit $F; stop boom'`. Then `^stopped stop: boom \[permission-route — `, and `debug_calls`
    is 0.
  - `test_lanes_stop_repair_plan_stage_holds`, two fixtures, each with `stop_repairs 3`:
    - (a) `A: 'auto; stage plan\nstop boom'` (unit 2 is labelled `T1` by `label_for`, pre-stage plan);
    - (b) `A: 'auto; stage plan\nstop boom; stage execute'` (Review Focus 4);
    - each: `^stopped stop: boom$`, and `debug_calls` is 0.
  - `test_lanes_stop_repair_then_gate_red`:
    - setup: `gate_repairs 1`, `stop_repairs 1`;
    - `A: 'auto\nstop boom\nauto\nauto\nstop gate red — x\nauto'`; `A.debug: stoprepair`; `A.gate: gaterepair`;
    - A lands;
    - `debug_calls` is 1 and `gate_calls` is 1;
    - rows: `…,3 A-debug-repair progress,…,6 A-finish stop,7 A-gate-repair progress,8 A-finish done,`.
  - `test_lanes_stop_repair_gate_repair_stop_holds` (Review Focus 3):
    - setup: `stop_repairs 3`;
    - `A: 'auto\nstop boom\nauto\nauto\nstop gate red — x'`; `A.debug: stoprepair`; `A.gate: 'stop weird'`;
    - `^stopped stop: weird$`;
    - `debug_calls` is 1 (the T2 repair only) and `gate_calls` is 1.
- [ ] **Step 2:** Run them (one background `TESTS_ONLY` run). Expect FAIL: no `stop: ` arm, so every
  uncategorised T2 stop ends `stopped stop: boom` with no repair.
- [ ] **Step 3: Implement.**
  - O `run_unit`: `UNIT_DENY_NOTE=""; STOP_LABEL=""` (ruling 4: every launch, every kind).
  - O `story_units` head: `STOP_ENDING=""; STOP_SRC=""; STOP_LABEL=""`.
  - O `story_units` Stop branch (O:1612):

```sh
    if [ -n "$NEW_STOP" ]; then
      row "$n" "$_base$suffix" stop; [ "$_stage" != execute ] || STOP_LABEL="$_base"
      ENDING="$STOP_ENDING$UNIT_DENY_NOTE"; return 0
    fi
```

  - L `run_story`: `n=0; STOP_ENDING=""; STOP_SRC=""; STOP_LABEL=""`, and `_rs_srep=0` beside
    `_rs_rep=0`.
  - L `story_gate_loop` (full; the gate arm's statements are today's, in order):

```sh
story_gate_loop() {
  while :; do
    case "$ENDING" in
      "stop: gate red — "*)
        if [ "$_rs_rep" -ge "$GATE_REPAIRS" ]; then
          [ "$_rs_rep" -eq 0 ] || ENDING="gate red after $_rs_rep repairs — ${ENDING#stop: gate red — }"
          break
        fi
        op_boundary "$1" || break
        _rs_rep=$((_rs_rep + 1))
        gate_repair "$1" || break
        story_units ;;
      "stop: "*)
        stop_repairable || break
        op_boundary "$1" || break
        _rs_srep=$((_rs_srep + 1))
        stop_repair "$1" || break
        story_units ;;
      *) break ;;
    esac
  done
}
```

  - L `stop_repair` (full; it mirrors `gate_repair` L:721-747):

```sh
# stop_repair ID — the debug-repair unit of a story whose task unit stopped on a Stop that names no
# human-owned category (stop_repairable): stories/ID = debug-repair, then
# `/game-dev:execute --debug-repair` (label debug-repair, model_repair) with
# STUDIO_REPAIR=stop:<the task unit's label> added to the story's env words. Returns 0 when the
# feature ledger gained a `Repair: stop — ` line: the caller re-runs story_units. Else returns 1
# with ENDING set: the halt reason; `stop: run budget`; `stop: <reason>` for the unit's own new
# Stop (never repaired: spec §8.3 4b); `debug repair made no progress [(orphaned: …)] — after
# <reason>`, `debug repair timed out (session_minutes N) — after <reason>` or `debug repair
# stalled (no output for N min: <command>) — after <reason>`. <reason> is the task unit's
# Stop reason. Each ending carries the unit's permission-route note (#66 R5).
stop_repair() {
  if lane_halt; then ENDING="$(lane_halt_reason)"; return 1; fi
  if run_budget_out; then ENDING="stop: run budget"; return 1; fi
  _dr_r="${STOP_ENDING#stop: }"; _dr_l="$STOP_LABEL"     # before run_unit resets STOP_LABEL
  story_write "$1" debug-repair
  snapshot "$UNIT_DIR/stops.before"
  _dr_b="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Repair: stop — ')"
  _dr_p="$PROMPT"; _dr_e="$LAUNCH_ENV"
  PROMPT="/game-dev:execute --debug-repair"
  LAUNCH_ENV="$LAUNCH_ENV STUDIO_REPAIR=$(sq "stop:$_dr_l")"
  n=$((${n:-0} + 1)); run_unit "$n" debug-repair
  PROMPT="$_dr_p"; LAUNCH_ENV="$_dr_e"
  if [ "$UNIT_HALTED" != 0 ]; then ENDING="$(lane_halt_reason)"; return 1; fi   # D22
  snapshot "$UNIT_DIR/stops.after"
  take_new_stop "$UNIT_DIR/stops.before" "$UNIT_DIR/stops.after"
  _dr_a="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Repair: stop — ')"
  if [ -n "$NEW_STOP" ]; then row "$n" debug-repair stop; ENDING="$STOP_ENDING$UNIT_DENY_NOTE"; return 1; fi
  if [ "$_dr_a" -gt "$_dr_b" ]; then row "$n" debug-repair progress; story_write "$1" running; return 0; fi
  _dr_o="$(unit_outcome)"
  case "$_dr_o" in
    "timed out") row "$n" debug-repair "timed out"
                 ENDING="debug repair timed out (session_minutes $SESSION_MINUTES) — after $_dr_r$UNIT_DENY_NOTE" ;;
    stalled) row "$n" debug-repair stalled; ENDING="debug repair stalled$(stall_note) — after $_dr_r$UNIT_DENY_NOTE" ;;
    *) row "$n" debug-repair "$_dr_o"; ENDING="debug repair made no progress$(orphan_note "$_dr_o") — after $_dr_r$UNIT_DENY_NOTE" ;;
  esac
  ! lane_halt || ENDING="$(lane_halt_reason)"
  return 1
}
```

  - Comments: update `story_gate_loop`'s and `run_story`'s header comments, which call gate red "the
    one repairable stop". Update `story_units`' ENDING list. Update L's file header list (L:6-8) only if
    it names repair functions. S3 adds `allow_rules` to L:7: union the names, keeping S3's (preflight fix).
  - **The existing test that changes:** in `test_lanes_adopt_round_trip` (T:3392), S1's T5 writes an
    uncategorised feature Stop with holds on, so it would now get a repair. Make it
    `printf 'auto\nstop [human] broke\n'`, and the assertion `"was held: stop: \[human\] broke"`
    (T:3403).
- [ ] **Step 4:** Run the new tests and `test_lanes_stop_repairs_zero_today`,
  `test_lanes_stop_repairable_table`, every `test_lanes_gate_repair*`,
  `test_lanes_resume_after_gate_red_runs_gate_repair`, `test_lanes_resume_gate_repairs_counted`,
  `test_lanes_resume_not_gate_red_no_repair_unit`, `test_lanes_gate_repair_noprog_holds`,
  `test_lanes_permission_route_note`, `test_lanes_held_dependents_wait` and `test_lanes_adopt_round_trip`.
  Use sh, then dash. Expect PASS. The golden must still match byte for byte.
- [ ] **Step 5: Audit run.** Run the whole `T` and `OT` suites once (background,
  `TEST_SUITES="overnight_lanes_test overnight_test" sh "$W/tests/run_all.sh"`; a partial run, so it
  takes no heavy-suite lock: preflight fix). Floor-only red lines are expected here. Any other red test other than the ones this task changed is a regression. Fix the code, not the test.
  The one exception: a test whose own scenario writes an uncategorised task-unit Stop, as in the
  round-trip case. Give it a `[human]` category, and record it in the task report.
- [ ] **Step 6:** Commit `feat(lanes): a task unit's non-human Stop gets a debug-repair unit (#69)`.

---

### Task 5: The repair's failure endings hold; the cap spans a resume; the budget boundary — Risky

**Files:**
- Modify: `O:928-940` (`holdable`'s isolated list, O:936-937)
- Test: `T` (new tests; `TESTS_EXCLUSIVE` T:4842-4850, `TESTS_REAL_CLOCK` T:4853-4857)

**Interfaces:**
- Consumes: `stop_repair`'s endings (T4).
- Produces: `holdable` holds `"debug repair made no progress"*`, `"debug repair timed out"*` and
  `"debug repair stalled"*` once isolated. These are globs, because the orphan note and the `— after`
  tail follow the stem. The `gate repair made no progress` pattern stays exact (out of scope, spec §10).

- [ ] **Step 1: Failing tests** (holds on with `lholds_on 120`, then `wait_for 'is_held A' 60`, the
  asserts, `lverb stop A`, `wait_pid_or_fail "$RPID" 60`, `lholds_off`). Each test also asserts
  `assert_eq 1 "$(debug_calls)"`.
  - `test_lanes_stop_repair_no_progress_holds`:
    - `A.debug: noop`;
    - `^held debug repair made no progress — after boom until `;
    - the row `	A-debug-repair	.*	noprog$`.
  - `test_lanes_stop_repair_timed_out_holds`:
    - setup: `kill_grace_seconds 5`, `A.debug: hang`, `STUDIO_OVERNIGHT_SESSION_SECONDS=10`;
    - `^held debug repair timed out (session_minutes 90) — after boom until `.
    - Add to `TESTS_REAL_CLOCK` (as `test_lanes_timed_out_outcome`).
  - `test_lanes_stop_repair_stalled_holds`:
    - setup: `A: 'emit <gate.jsonl>; auto\nemit <gate.jsonl>; stop boom'`, where the open `studio-test`
      call keeps a slow task unit from stalling (T:1771-1774), and `A.debug: 'emit <sleep.jsonl>; hang'`;
    - the idle seams as `test_lanes_sync_repair_stops` sets them (T:1777);
    - `^held debug repair stalled (no output for 20 min: Bash: sleep 999) — after boom until `.
    - Add to `TESTS_EXCLUSIVE` (as `test_lanes_stalled_outcome`).
    - The spec's `…_stopped_holds` is this row of §8.5's table. The repair-wrote-a-Stop row is
      `never_chains` (T4).
  - `test_lanes_stop_repair_cap_across_resume`:
    - `A: 'auto\nstop boom\nstop again\nauto\nauto\nauto'`; `A.debug: noop`;
    - held on `debug repair made no progress — after boom`;
    - `lverb resume A`;
    - `wait_for 'case "$(rec A)" in "held stop: again"*) true ;; *) false ;; esac' 60`;
    - `debug_calls` is still 1 (the cap was used before the resume);
    - stop A.
  - `test_lanes_stop_repair_budget` (holds off; Review Focus 5):
    - setup: `run_usd 30`, `session_usd 25`, `A: 'cost 2\ncost 4; stop boom'` (2 + 25 ≤ 30 lets T2
      run; after it, 6 + 25 > 30 refuses the repair);
    - `^stopped stop: run budget$`;
    - `debug_calls` is 0.
- [ ] **Step 2:** Run them. Expect FAIL. The first three end `stopped debug repair …`, because
  `holdable` has no glob. `cap_across_resume` never holds. The budget test may already pass, because
  `stop_repair` checks the budget first: say so in the task report, since it is a boundary pin.
- [ ] **Step 3: Implement.** O:936-937: append
  `|"debug repair made no progress"*|"debug repair timed out"*|"debug repair stalled"*` to the
  `isolated` case list. Update `holdable`'s comment (O:925-927).
- [ ] **Step 4:** Run the new tests, `test_lanes_gate_repair_noprog_holds` and
  `test_lanes_permission_route_note` (sh and dash). Expect PASS. Run OT's hold tests
  (`TESTS_ONLY` = every OT test whose name contains `hold`): single-plan `holdable` sees no new ending.
- [ ] **Step 5:** Commit `feat(overnight): a failed debug repair holds the story (#69)`.

---

### Task 6: Skill text — categories, "Every stop", §12 `--debug-repair`, the plan sweep rule — Risky

**Files:**
- Modify:
  - X: :328-333 (mode list), :504-509 (§5 step 2 regex), :573-579 (§6 stop list), :715-716 (§7),
    :804-826 (§8 Every stop), :850 (Operator messages), :902 (§9), :924 (§10), :981 (§11), a new §12
    after :993;
  - `R:102` only (the same regex). S6 owns R:100 and X:505 and merges first; S5 changes only the
    X:507 and R:102 regex lines and re-checks them against S6's text (preflight fix);
  - `PL:228-235` (§7 step 2).
- Test: `ST`:
  - `test_execute_contract` :253-260 (the literal `'final|gate|review'` at :257);
  - `test_execute_one_contract` :445-455 (:452);
  - `test_execute_lanes` :533-576 (:570; S1 adds its assertion after :561, so keep both on merge);
  - `test_execute_gate_repair` :675-704 (the enter-first loop :696-702);
  - `test_execute_operator_messages` :714-735;
  - the run list at the end.

**Interfaces:**
- Produces (X), the literals the contract pins:
  - `studio-state ledger "Stop: [<category>] <reason>"`;
  - the one line `The categories, in this order: `taste`, `scope`, `perm`, `env`, `human`.`;
  - `Relaxing, skipping or loosening a check is never the offered fix`;
  - `"can't find the cause", "nondeterminism" and "flaky" are not stop reasons`;
  - `Stop: [env] <the printed message>` (all three hard stops);
  - `^## 12. Debug repair (--debug-repair)`;
  - ``^- `--debug-repair` ``;
  - `STUDIO_REPAIR=stop:<label>`;
  - `Repair: stop — <root cause>; <fix>`;
  - `fix(stop): <summary>`;
  - `fix\((T[0-9]+|final|gate|stop|review|B[0-9]+)\)` (X §5 and R).
- Produces (PL): `diagnose X; stop only if Y`.
- Consumes: `STOP_HUMAN_CATS` in L (T3).

- [ ] **Step 1: Failing tests.**
  - New `test_stop_categories_contract`:

```sh
test_stop_categories_contract() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"; L="$REPO_ROOT/studios/game-dev/bin/overnight-lanes.sh"
  _x="$(sed -n 's/^.*The categories, in this order: \(.*\)\.$/\1/p' "$E" | tr -d '`,')"
  _l="$(sed -n 's/^STOP_HUMAN_CATS="\(.*\)"$/\1/p' "$L")"
  assert_eq "taste scope perm env human" "$_x" "X lists the five categories in this order"
  assert_eq "$_l" "$_x" "X's category list equals STOP_HUMAN_CATS in L"
  assert_contains "$E" 'studio-state ledger "Stop: \[<category>\] <reason>"' "every stop names a category"
  assert_contains "$E" 'Relaxing, skipping or loosening a check is never the offered fix' "relaxing a check is never the fix"
  assert_contains "$E" '"flaky" are not stop reasons' "can't-find-the-cause is not a stop reason"
  assert_eq 3 "$(grep -c 'Stop: \[env\] <the printed message>' "$E")" "the three engine hard stops are env"
  assert_eq 0 "$(grep -c '"Stop: <the printed message>"' "$E")" "no uncategorised engine stop is left"
  assert_contains "$E" 'fix\\((T\[0-9\]+|final|gate|stop|review|B\[0-9\]+)\\)' "§5 verifies fix(stop) commits"
  assert_contains "$REPO_ROOT/studios/game-dev/skills/review/SKILL.md" '|gate|stop|review|' "review verifies fix(stop) commits"
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  assert_contains "$PL" 'diagnose X; stop only if Y' "the plan sweep rewrites stop-if-X clauses"
}
```

  - New `test_execute_debug_repair`:
    - `^## 12. Debug repair (--debug-repair)$`;
    - ``^- `--debug-repair` ``;
    - `STUDIO_REPAIR=stop:<label>`;
    - `its latest `Stop:` line names no human-owned category`;
    - `superpowers:systematic-debugging`;
    - `fix(stop): <summary>`;
    - `Repair: stop — <root cause>; <fix>`;
    - `Stop: \[<category>\] debug repair — `;
    - `Stop: \[human\] debug repair — <precondition>`;
    - the §12 `Never ships, never lands` (via `section_count … '^## 12[.] '` = 1).
  - Extend the enter-first loop to `'## 9\.' '## 11\.' '## 12\.'`.
  - Add `assert_eq 1 "$(section_count "$E" '^## 12[.] ' '(see §8, Operator messages)')"` to the
    operator-messages test.
  - Update `ST:257`'s literal to `'final|gate|stop|review'`, `ST:452` to
    `'studio-state ledger "Stop: \[<category>\] <reason>"'`, and `ST:570` to
    ``'`studio-state ledger "Stop: [env] <the printed message>"` (not `gate red`)'``. Escape the brackets
    for grep.
  - Add both new tests to ST's run list.
- [ ] **Step 2:** Run ST's changed and new tests. Expect FAIL.
- [ ] **Step 3: Implement the text.** Keep every untouched pinned literal intact. Grep each one before
  you save.
  - **X :328-333:** "Three more modes" → "Four more modes" (and "all three" → "all four"). Add:
    "- `--debug-repair`: the debug-repair unit (§12), launched under a lane when a task unit's Stop
    names no human-owned category."
  - **X §8 Every stop (:804-806):** run `studio-state ledger "Stop: [<category>] <reason>"`, one line,
    category first, then the reason. Add:
    - the categories line (exact, one line), then the five-row table from spec §8.2;
    - the fixed-text stops this skill prescribes keep their exact text (list the eight prefixes);
    - "can't find the cause", "nondeterminism" and "flaky" are not stop reasons: diagnose with
      `superpowers:systematic-debugging`; fixing the root cause is always in scope;
    - Relaxing, skipping or loosening a check is never the offered fix;
    - under a lane, a task unit's Stop with no category (or another word) gets a debug-repair unit
      (§12, `overnight.stop_repairs`) before the story holds.
  - **X §6 (:573-579):** give each allowed stop its category: an irreversible, destructive or
    security-sensitive operation is `perm`; a plan too broken to follow is `scope`; `studio-test` /
    `studio-run` exit 2 and exit 3 are `env`.
  - **X :716, :902, :981:** `Stop: [env] <the printed message>`. **X :924:** `Stop: [<category>] <reason>`.
  - **X :507:** the regex becomes `fix\((T[0-9]+|final|gate|stop|review|B[0-9]+)\)`. **R:102** is the
    same. Change only those two regex lines; S6's X:505 and R:100 text stays as S6 left it (preflight
    fix). **X :850:** "§9 (`--land`), §11 (`--gate-repair`) and §12 (`--debug-repair`) units: after
    their **Enter the feature checkout** step."
  - **X §12** (new, after §11; modelled on it; spec §8.7). Its bullets, in this order:
    - **Launch:** prompt, start checkout, the story's env as in §11, `STUDIO_REPAIR=stop:<label>`
      (`<label>` is the task unit's `T<n>`). It bypasses §0's stage gate, and any miss is
      `Stop: [human] debug repair — <precondition>`.
    - **Enter the feature checkout** first.
    - **Operator messages** (see §8, Operator messages).
    - **Preconditions:** `stage execute`, no `shipped` line, its latest `Stop:` line names no
      human-owned category and is not a fixed-text stop, and `STUDIO_REPAIR` starts with `stop:`.
    - **Diagnose:** `superpowers:systematic-debugging`, with the Stop line, the task's text
      (`studio-brief task <n>`) and the failing output. Include the determinism triage recipe,
      verbatim from spec §8.7.
    - **Fix:** one fresh fixer (§5 step 5's owning role) commits `fix(stop): <summary>`. Relaxing,
      skipping or loosening a check is never the fix.
    - **Verify what failed, not the whole gate:** `studio-test --file …`, gate-routed, foreground,
      `timeout` `$BASH_MAX_TIMEOUT_MS`, up to three rounds as §11. Exit 2/3 is
      `Stop: [env] <the printed message>`, committed.
    - **Record:** `studio-state ledger "Repair: stop — <root cause>; <fix>"`, then
      `git add .studio/ledger && git commit -m "chore(studio): debug repair"`, then push the story
      branch. The runner then runs the task unit again.
    - **No root cause, or the cause needs a person:** `Stop: [<category>] debug repair — <what was
      ruled out>; <the decision needed>`, committed, with a human-owned category (`human` when no
      other fits). The runner never repairs a debug repair's own Stop.
    - The git-lock retry rule (as §11).
    - **Never ships, never lands** (as §11: no `shipped`, no PR, no `stage`/`task` change, never merges).
    - One unit: end the turn.
  - **PL :228-235**, appended to step 2, spec §8.8's sentence verbatim (it holds the literal
    `diagnose X; stop only if Y` and the twin-cooks example).
- [ ] **Step 4:** Run the whole ST suite, plus `pointer_skills_execute_test` and `pointer_skills_route_test`
  (sh and dash). Expect PASS.
- [ ] **Step 5:** Commit `docs(skills): Stop categories, --debug-repair (§12), the stop-if-X sweep rule (#69)`.

---

### Task 7: Rebase, golden re-check, affected suites, floors — Mechanical

This task follows S2's "For other stories" recipe exactly (preflight fix).

- [ ] Run `git fetch`, then merge the latest `origin/integration/backlog-2026-10-21` into the story branch.
  S1, S3, S4 and S6 are already in (S2's build order: S5 is last). On a `tests/run_all.sh` floors-table
  conflict, take the integration branch's whole file
  (`git checkout origin/integration/backlog-2026-10-21 -- tests/run_all.sh`), never a hand-merge of counts.
  Resolve X conflicts with S6 (§5) and S1 (§7 step 4) by keeping both sides' text, and the other shared
  regions per **Merge notes** below.
- [ ] **Golden re-check** (when the merge brought any change under `studios/game-dev/bin/`):
  - add a temp worktree at the new merge-base under `$S`;
  - copy this branch's `T` and its golden into it;
  - run `TEST_SR_GOLDEN_WRITE=1 TESTS_ONLY=test_lanes_stop_repairs_zero_today` there;
  - copy the regenerated golden back and diff it. Only base-side changes are allowed (for example
    S1's report lines);
  - rerun the test on the story head. Expect PASS. Remove the temp worktree.
  - Commit the regenerated golden (and any other change) now, before the counts run (preflight fix).
- [ ] With a clean tree, run `sh "$W/tests/run_affected.sh" --base origin/integration/backlog-2026-10-21 --list`.
  Run what it lists, plus `harness_test` if it is missing. The list must include `overnight_lanes_test`,
  `overnight_test`, `studio_test`, `studio_adopt_test`, `overnight_progress_test` and `harness_test`
  (the knob and test-list checks). Run them through run_all, one background run under sh, then one
  under dash: `TEST_SUITES="<list> harness_test" sh "$W/tests/run_all.sh"`, then the same with
  `TEST_SH=dash`. These are partial runs, so they take no heavy-suite lock. Also run the Multica suite once.
  - Red only with `floor` / `no floors row` lines is expected. Any other red: fix, commit, and re-run both.
- [ ] With no commit since the last run, update the floors: `sh "$W/tests/run_all.sh" --update-floors`.
  Any commit after the run means a re-run first. Expect rises for `overnight_lanes_test`,
  `overnight_test`, `studio_test` and `studio_adopt_test` only.
- [ ] Commit `test(floors): S5 counts` (only `tests/run_all.sh`).

### Merge notes (preflight fix)

S5 merges last (after S1, S3, S4 and S6), so it unions every shared region:
- **T:328 post-action list and the T stub's action docs (T:58-61, T:136-143).** S1 adds `push_ref`; S5
  adds `stage` and `stoprepair`. Keep both names on :328 and on the header lines. S2's :84-88 header
  lines stay as S2 left them.
- **T post-loop arms.** S1's `push_ref` arm sits after :364; S5's `stage` arm goes after `rmwt` :371 and
  `stoprepair` after `gaterepair` :337-338.
- **L header :7.** S3 adds `allow_rules`; S5 unions any repair helper names onto it.
- **X:507 and R:102.** S6 merged first and owns X:505 and R:100. S5 changes only the two regex lines and
  re-checks them against S6's text.
- **studio_test `test_execute_lanes`.** S1's assertion sits after :561; S5 edits :570. Keep both.
- **`run_tests` lists and rulings tails** (T, OT, ST, AT). S1, S2, S3, S4 and S6 append here too. On a
  conflict, keep both sides; S5 adds its names on its own new continuation line.
- **`tests/run_all.sh` floors.** On a conflict, take the integration branch's `run_all.sh`, then redo
  Task 7 from the commit step.

---

## Final review, gate, acceptance

- **Final whole-branch review (Opus, standalone):** the controller's job, over the integration branch.
  Focus for S5:
  - the Review Focus above;
  - A1: with `stop_repairs 0`, nothing changes (the golden);
  - the gate arm is byte for byte;
  - the `debug-repair` kind is in every list spec §8.5 names;
  - X's pinned literals are intact.
- **Full gate:** the controller runs it once, at the end (sh and `TEST_SH=dash`; a full run, so run_all
  takes the heavy-suite lock itself: preflight fix).
- **Manual acceptance** (operator; with the sweep's later live check). In a phoenix-like run, a task
  unit writes an uncategorised Stop, for example a leaked-state twin-cook mismatch. Check:
  - one `debug-repair` unit runs on `model_repair`;
  - its `fix(stop)` commit and its `Repair: stop — ` line land;
  - the task unit runs again, and the story goes on;
  - the final review's verify-prior-fixes list shows the `fix(stop)` commit.

  Only a real model session can prove that the skill text produces a root-cause fix and not a weakened
  test. No automated check can.

## Falsified assumptions (planner falsify clause)

Each load-bearing assumption, checked against the code at 1cfca7f:

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | `story_gate_loop` is L:1095-1107, its comment L:1089-1094 | true | read |
| 2 | `gate_repair` (L:721-747) is the model for `stop_repair`: lane_halt, run_budget_out, snapshot, `take_new_stop`, the `unit_outcome` cases, the final `lane_halt` | true | read |
| 3 | `_rs_rep=0` is set once in `run_story` at L:1130, after the first `story_units` | true | L:1129-1130 |
| 4 | `holdable`'s isolated list is O:936-937 and strips the permission note first | true | O:928-940 (`_h_e` at :933) |
| 5 | `model_for` is at O:225 | true | O:220-228; `repair|final-repair|gate-repair|sync-repair` at :225 |
| 6 | `story_units` sets ENDING from a new Stop at O:1615 | true (±3) | O:1612. `_stage` (pre-unit) at :1602, `_base` at :1605 |
| 7 | `label_for` labels a plan-stage unit `T1` | true | O:826-827 `plan:*` → T1 |
| 8 | `run_unit` is every unit's launch, so one reset there covers ruling 4 | true | the call sites are O:1608, L:673, L:730, L:828, L:1692 (final_unit); `UNIT_DENY_NOTE=""` at O:1347 |
| 9 | `story_units_table`'s label regex is L:1359 | true | read |
| 10 | studio-adopt's live states are at :697 | true | `running|held|repair|gate-repair|sync-repair|landing` |
| 11 | mirror.py `STATUS` is :14-16, and an unknown state only warns | true | :14-16; the warning at :469-470 |
| 12 | overnight-progress.sh needs a code change for the new kind | **false** | `kind()` (:104-110) maps any non-T/fr/fin label to `other`; only the :10 comment changes |
| 13 | operator-inbox.sh:109, multica README:225, overnight-events.md:99 | true | read |
| 14 | `cfg gate_repairs` is at O:665, and its help is at O:444-446 | true | read |
| 15 | X's mode list is :328-333, §11 is :935-993 (end of file), and the hard stops are :716, :902, :981 | true | read; also `Stop: <reason>` at :924 (§10) |
| 16 | the spec's regex order `final|gate|stop|review` breaks no reader | **false** | `ST:257` greps the literal `'final|gate|review'` in X → T6 updates it |
| 17 | X §5's regex is the only verify-prior-fixes list | **false** | R:102 has the same regex. T6 adds `stop` there too (S6 edits R:100-101: rebase) |
| 18 | the Stop readers grep `^- [0-9-]* Stop: ` | true | O:799, O:810, L:680, L:701, L:972 |
| 19 | the spec's `_sr_b` local names are free | **false** | `_sr_` is `sync_repair`'s (L:825-848) and the sessions' (overnight-sessions.sh:83-86) → `_dr_` (stop_repair) and `_xr_` (stop_repairable), both unused |
| 20 | the stub can make T1's first unit write a feature-side Stop (spec's then_lands says `stop:T1`) | **false** | `stop` is terminal, so `auto` (which adds the worktree, T:216-227) never runs; the Stop lands in the start checkout (STOP_SRC=start). Tests use `LANES_TASKS=2`, so T2 stops and `STUDIO_REPAIR=stop:T2` |
| 21 | the stub can reach a plan-stage unit with a worktree | **false** as is | there is no action to set the stage → T1 adds the post action `stage <s>` (`st set stage`, in the cwd, as `auto` does at T:225) |
| 22 | default `stop_repairs 1` leaves the existing tests green | **false** | `test_lanes_adopt_round_trip` (T:3389-3392): S1-T5 writes `Stop: broke` feature-side with holds on → T4 gives it `[human]`. The other `stop …` scenarios are first-unit (start-side) or final-review stops (T:1001, 1145, 1949, 2216, 2939, 2999, 3151, 3177, 3214, 3699): checked by the T4 audit run |
| 23 | a suite-wide env override can default `stop_repairs` to 0 | false (none needed) | there is no env hook for `gate_repairs` either; config comes only through `LANES_CONFIG` |
| 24 | assert.sh keeps `TEST_*` and unsets `STUDIO_*` | true | assert.sh:4-6 → the golden switch is `TEST_SR_GOLDEN_WRITE` |
| 25 | the timed-out tests are real-clock and the stall tests exclusive | true | T:4842-4857 |
| 26 | the Multica tests run in run_all | **false** | they run from `integrations/multica/tests/run.sh` (unittest discover); T2 and T7 run it by hand |
| 27 | L can be sourced alone for a unit test | true | T:1193-1196 (`SELF_DIR`, `RUN_DIR`, then `. overnight-lanes.sh`); `isolated` is O's, so the test defines it |
| 28 | studio-adopt's `part_done` ignores repair commits | partly | it skips `fix(final|gate|review|sync` (studio-adopt:317-325), not `fix(stop)`. A `fix(stop)` commit counts as the stopped task's work, which is the right attribution, so there is no change. Noted for the final review |
| 29 | the event line shape for the golden's masks | true | studio-event:11 `{"v":1,"ts":"<UTC>",…}` with `run` |

## Self-review

1. **Spec coverage (§8):**
   - §8.2's format, categories and `STOP_HUMAN_CATS`: T3 and T6.
   - The skill rules and the fixed-text list: T6, and T3's condition 7.
   - The `[env]` hard stops and the legacy-is-repairable rule: T6, T3.
   - §8.3's conditions 1-7, 4, 4a and 4b: T3 (the predicate), T4 (the `STOP_LABEL` reset and set, the
     pre-stage check, `never_chains`, `gate_repair_stop_holds`).
   - §8.4's loop, A1 and the independent counters: T4 and T1's golden. The resume path stays unchanged:
     T4 and T5's resume tests.
   - §8.5's `stop_repair`, its endings table and the `holdable` globs: T4, T5. The new-kind lists: T2.
   - §8.6 (config and help): T2.
   - §8.7 (§12): T6. §8.8 (PL): T6. §8.8a (`fix(stop)` in the regex): T6.
   - Every acceptance test named in §8.8a maps to a task. `…_stopped_holds` is read as the stalled row
     (T5).
2. **Step scan:** each code task is failing test → run (FAIL) → implement → run (PASS) → commit. T1 is
   green-first by design (a golden guard, stated). In T5 the budget pin may pass at once (stated).
3. **Names:** these are spelled the same in every task and the table: `stop_repairable`,
   `stop_repair`, `STOP_HUMAN_CATS`, `STOP_LABEL`, `STOP_REPAIRS`, `_rs_srep`, `_dr_*`, `_xr_*`,
   `debug-repair`, `$id.debug`, `stoprepair`, `stage <s>`, `debug_calls`, `debug_call`, `sr_norm`,
   `TEST_SR_GOLDEN_WRITE`.
4. **Review Focus:** each of the 5 has a pinning test in its owning task (T3 ×2, T4 ×2, T5 ×1).
5. **Proportion:** full code is given only for `stop_repairable`, `stop_repair`, the loop, the table
   test, the golden normalizer and the categories contract. The rest is named, with the values the spec
   pins.
