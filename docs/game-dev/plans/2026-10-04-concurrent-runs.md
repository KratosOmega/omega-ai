# Concurrent Autopilot Runs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Draft — awaiting user review

**Goal:** Let several manifest runs live in one project at once. Each run is
planned in its own run worktree, started from it, and lands on its own. The
runs share the machine through the existing gate lock and a new project-wide,
first-come-first-served session cap. Each run sees what the other live runs
are changing, and each story merges its moved sync refs before every task unit.

**Architecture:** Two new sourced libraries in `studios/game-dev/bin/`:
- `overnight-runs.sh`: one view of "the live runs of this project", plus helpers:
  - `runs_live` reads the per-run locks and the old `.studio/overnight.lock`;
  - the start-dir and selector helpers;
  - the run-worktree finder;
  - the plan `Files:` parser;
  - a symlink mutex.
- `overnight-sessions.sh`: the session slots, the FIFO wait queue, and the
  owner-checked release and reclaim.

They are used by:
- the runner (`studio-overnight`, `overnight-lanes.sh`, `overnight-channel.sh`);
- the new reader `studio-peers` and its SessionStart hook `peer-runs.sh`;
- `studio-adopt` (#35).

`studio-state` gains a local stage pointer for run worktrees; nothing else
about its roots changes. The skills (autopilot, brainstorm, plan, execute,
studio) move planning into run worktrees and add the `sync:` repair form.
Contract tests pin both.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2; Linux `dash`), git ≥ 2.38
(`git_version_ok`; git 2.39.3 on the dev machine), BSD/GNU sed, awk, grep, ps.
No new dependencies.

**Spec:** `docs/game-dev/specs/2026-10-04-concurrent-runs.md` (approved
2026-10-04, commit bcafbbd). All `L<a>-<b>` references below are lines of that file.

Story: #39 (GitHub issue). Branch worktree-issue-39-concurrent-runs.

**Base:** 85aa5eb (origin/main 4e71aa6 with #35 merged in). The line numbers
below are taken at that commit. Relocate each one with its `grep -n` pattern.

**Review policy (user CLAUDE.md):**
- Each task carries `Spec:` (its spec line ranges), `Review: task|final`,
  `Wave:` and `Touches:` under its heading.
- A `Review: task` task gets a per-task review on Opus (`model: "opus"`). A
  `Review: final` task folds into the final review.
- Minor findings are batched into the final fix wave. Every fix round goes to
  a fresh fixer, given the findings and the diff range.
- Re-review only after a Critical, three or more Importants, or a
  production-bug fix. Never a third pass.
- The final review is a standalone whole-branch review on Opus, never folded
  into the last task review. Then the full gate.
- One task = one implementer with its own test cycle. The tasks of one wave
  touch disjoint files (tests included). They run concurrently in their own
  worktrees and are cherry-picked onto this branch in task order. Hand-backs
  are 1.5k characters or less, and full reports go to a file.
- Task 1 is a gate: the operator runs the probe, and no wave-1 task starts
  until it passes.

---

## Prerequisites — re-run the anchor greps

Before a task edits `studio-overnight` (SO) or `overnight-lanes.sh` (LN), its
implementer re-runs the greps for the anchors it touches. An earlier wave's
cherry-picks move the lines, so trust the pattern, not the number.

```sh
SO=studios/game-dev/bin/studio-overnight; LN=studios/game-dev/bin/overnight-lanes.sh
grep -n '^lock_pid()\|^lock_live()\|^take_lock()' "$SO"               # 191 192 198
grep -n '^START_DIR=\|^STATE_ROOT=\|^LOCK=\|^STOP_FILE=' "$SO"         # 380-384
grep -n '^preflight()\|if lock_live; then$' "$SO"                      # 390, the live refusal ~470
grep -n '^model_for()\|repair|final-repair|gate-repair' "$SO"           # 156, 162
grep -n '^reg_write()\|^reg_live()\|^reg_end()' "$SO"                   # 937 931 948
grep -n '^start_session()\|^run_unit()\|model_for "\$2"' "$SO"          # 963 979 983
grep -n '^unlock()\|^end_session()\|^story_units()' "$SO"               # 1086 1103 1150
grep -n '_before="\$SIG"; _base=' "$SO"                                 # 1166
grep -n '^detach_start()\|^acquire_run_lock()\|^run_setup()' "$SO"      # 1186 1314 1344
grep -n '^project_status()\|^registry_status()\|^cmd_status()\|^cmd_watch()' "$SO"  # 1401 1452 1476 1497
grep -n '^  stop)$\|^  status)$\|^  watch)' "$SO"                       # dispatch ~1550-1620
grep -n '^mf_load()\|^mf_check()\|^story_units_table()' "$LN"           # 46 84 1015
grep -n '^land_repair()\|^gate_repair()\|^lane_halt()\|^lane_exit()' "$LN"  # 495 545 621 663
grep -n '^lane_main()\|^run_story()\|^lanes_end_sessions()\|^lanes_sweep()' "$LN"  # 710 785 851 906
grep -n '^lanes_report()\|## Resume' "$LN"                              # 1042, 1114
grep -n '^lanes_load_run()\|^lanes_reap_stale()\|^lanes_status_lines()\|^lanes_status()\|^lanes_on_exit()' "$LN"  # 1144 1193 1207 1241 1264
grep -n '^final_unit()\|^lanes_run()\|^lanes_start()\|^lanes_next()' "$LN"  # 1321 1633 1680 1727
grep -n '^chan_find_run()\|^chan_stop_run()\|^chan_main()' studios/game-dev/bin/overnight-channel.sh  # 104 296 350
```

---

## Global Constraints

These are the spec's values, verbatim. A task that touches one of them uses it exactly.

**Paths** (all under `<root>` = `studio-state root`, the main checkout):
- the per-run lock and stop flag: `.studio/runs/<slug>/lock` and `.studio/runs/<slug>/stop` (L137);
- the lock records `pid=`, `run=`, `started=` and `start=` (L138);
- a single-plan run keeps `.studio/overnight.lock` and `.studio/overnight.stop` (L142);
- session slots: `.studio/sessions/<n>`, n in 1..cap, taken with `mkdir` (L245);
- waiters: `.studio/sessions/wait/<epoch ns>-<lane pid>` (L245);
- mutexes: `.studio/runs.mutex` (L151) and `.studio/sessions.mutex` (L249), never the gate mutex;
- the run worktree for a new run: `<root>/.claude/worktrees/run-<slug>` (L133);
- a done record is archived to `.studio/runs/<slug>.<utc ts>` (L147);
- `run_setup` adds `.studio/runs/` and `.studio/sessions/` to `info/exclude` before the lock (L141).

**Config:** `overnight.max_sessions`, default 6, range 1–8, integer. It is read from
`<root>/.studio/config.json` at each slot request and validated by the preflight (L243, L325).

**Limits:** the peers block prints at most 40 paths, and the preflight overlap list at
most 20. Both end with `and N more` and are constants in the scripts (L213, L152, L326).

**Events** (`docs/game-dev/overnight-events.md`):
- `story_synced`: `story`, `refs`, `sha`, or `skipped=` / `failed=` (L230);
- `session_wait`: `lane`, `story`, `since` (L252).

**Commit subjects, ledger lines and endings:**
- a clean sync merge: `chore(sync): merge <ref> into <Branch>` (L227);
- a sync repair: `fix(sync): <summary>`, with the ledger line `Synced: <summary>` (L236);
- a red sync repair: `Stop: sync repair red — <failing line>`, committed, not pushed (L237);
- a stopped sync repair's story ending: `stopped sync repair: <reason>` (L239);
- the repair env is `STUDIO_REPAIR=sync:<ref>`, prompt `/game-dev:execute --land` (L232).

**Fixed texts:**
- `no live run <slug>`: `status --run`, exit 1 (L159);
- `no live run lists <story>`: channel resolution (L173);
- `waiting for a session slot since <hh:mm>`: status (L157);
- `Other live runs`: the hook block's heading (L211);
- the peers rule, verbatim (L213): *These files are being changed by another live run. Do not edit them beyond what your task needs; if your task needs to, keep the change minimal and name each such file in your report.*;
- `next:` forms (L177): `next: /game-dev:brainstorm <slug>/<id>`, `next: /game-dev:plan <slug>/<id>`, `next: /omega:autopilot <slug>`;
- README and Multica README line (L88): "another run can be planned and started while one is live".

**Platform and process:**
- POSIX `sh`, macOS `/bin/sh` (bash 3.2), BSD tools, no new dependencies (L92).
- No `date +%N` and no `\t` inside sed brackets (BSD): use `[[:blank:]]` or a literal tab.
- Every new file under `studios/*/bin/` and `studios/*/hooks/` is `chmod +x` (`test_bin_syntax` requires it).
- Tests follow `tests/assert.sh`. They run offline in temp dirs with temp `HOME`s and make no model calls.
- The engineer never runs install or uninstall against the real HOME.
- Public repo: fixtures use made-up ids (`S1`, `A`) and slugs (`alpha`, `beta`, `demo`). No workspace data, user names or machine paths.
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01KsvA6zmie14GBYrnrabeRh
  ```

---

## Decisions

**Spec defects — need an operator ruling (flagged in the hand-back)**

- D1: The Milestone gate's step 2 (L30) says the existing suites keep every
  assertion except the `next:` text. It cannot hold for assertions pinned on
  behaviour that the ACs change.

  **Ruling taken:** each such assertion is rewritten to the AC's behaviour,
  and the task that changes it names it:
  - autopilot contract L48, L62, L70, L76, L77 (AC15, AC16; Task 5);
  - `test_router_overnight_lock` in `tests/studio_test.sh` (AC19; Task 4);
  - the lanes suite's manifest lock and stop paths at ~1675, ~1689, ~1877 and ~1938 (AC4; Task 7);
  - `tests/overnight_progress_test.sh` L66, "the progress line comes first", which becomes "first in its block" (AC10, D15; Task 12).

  No other existing assertion changes.

  **Why:** the ACs are the binding behaviour, and step 2's intent (no lost
  coverage) is kept: each rewritten assertion still pins the same rule at its new place.
- D2: AC8 says "(autopilot does this at AC12)" (L147). It means AC15 (L178,
  "a done record is archived"); AC12 is `stop`. **Why:** a cross-reference typo. Task 5 puts the archive step in AC15's flow.

**Locks, records and identity**

- D3: The FIFO wait key is `max(date +%s × 10^9, last + 1)`. It is made under
  `sessions.mutex`, and `last` is kept in `.studio/sessions/wait/.last`.

  **Why:** macOS `date` has no `%N` (trial: it prints a literal `N`). Under
  the mutex the key is unique and increasing, so it gives the same order a
  nanosecond clock would. The keys have 19 digits until the year 2286, so
  text order is number order; bash 3.2 arithmetic is 64-bit (trial).
- D4: A record exists when `.studio/runs/<slug>/landed.tsv` exists.

  **Why:** the per-run lock now lives in `.studio/runs/<slug>/`, so the
  directory alone does not mean a record. A start that loses the race removes
  its lock and `rmdir`s the directory only when it is empty.
- D5: The stop flag follows the lock. A live old-style manifest run (holding
  `.studio/overnight.lock`, AC31) is stopped through `.studio/overnight.stop`.
  `runs_stop_of LOCK` gives the pair.

  **Why:** that runner reads only that file, and `test_verbs_run_pinning` stays valid.
- D6: `run_excludes` writes all seven entries before the lock, into the common
  git dir's `info/exclude`:
  - `.studio/overnight.lock` and `.studio/overnight.stop`;
  - `.studio/runs/` and `.studio/sessions/`;
  - `.studio/runs.mutex` and `.studio/sessions.mutex`;
  - `.claude/worktrees/`.

  Today's two writers, `run_setup` and `lanes_run`, call it instead.

  **Why:** AC4 asks for "before the lock", and one writer keeps the list in one place.
- D7: The lock gains `start=`. `take_lock` writes `pid= run= started= start=`.
  Old locks without `start=` fall back as in D26.
- D8: The post-lock re-check is `lock_recheck`. SO defines it for single-plan
  runs: it refuses any other live run. LN redefines it for manifest runs:
  - Task 7: it refuses a live single-plan run;
  - Task 11: it also refuses a live run that shares the slug, a story id or a
    story branch, or whose Target equals one of this run's story branches.

  It runs under `.studio/runs.mutex`. A loser calls `lock_lost`, which removes
  its own lock and run dir, drops the mutex and exits 2.
- D9: Lanes copy `manifest.md`, `rows.tsv` and `chains` into the run dir
  between `take_lock` and the re-check (`run_populate`). Today `lanes_run`
  copies them after `acquire_run_lock` returns.

  **Why:** this makes the re-check sound. The re-checks are serialized by the
  mutex, and each run populates before its own. So for two conflicting
  starts, the later re-check always sees the earlier run's lock and rows (or
  finds them gone if that run lost), and at most one start wins. Without
  this, both could miss each other.
- D10: The test hook `STUDIO_OVERNIGHT_LOCK_HOOK` is `eval`ed in
  `acquire_run_lock` just before `take_lock`, the same way
  `STUDIO_OVERNIGHT_RACE_HOOK` is. Task 7 adds it, and Tasks 7 and 11 use it
  to force the start races.
- D11: `reg_write` drops a same-root entry only when `reg_live` is false
  (AC6). `unlock` removes `LOCK` only when its `pid=` is `$$`, and removes its
  own `STOP_FILE`.
- D12: The start dir (AC7, D26) is used for:
  - each status block;
  - each reap (`lanes_reap_stale`, `status`);
  - the channel's `CH_START`;
  - the report's Resume line through `lanes_report` (it already prints `cd <START_DIR>`).
- D13: Bare `stop`:
  - with no live run, today's text, exit 1;
  - with one live run, today's text and that run's own flag (D5);
  - with two or more, nothing written, exit 1, and stdout lists them:
    ```
    <n> runs are live — nothing stopped:
      <slug|run dir basename>  <run dir>
    stop one: '<abs>' stop --run <slug> · stop all: '<abs>' stop --all
    ```

  `stop --all` writes each still-live run's flag (it re-checks `runs_lock_live`
  just before each write) and prints one `stop requested: <slug> (pid <p>)`
  line per run. With none live it prints today's no-run text and exits 1.
- D14: The `--run` selector (status, watch, stop and the channel verbs) matches
  a run's slug or its run dir basename, through `runs_match`. A single-plan run
  has slug `-` and is selected by basename.
- D15: `status` with at least one live **manifest** run prints
  `sessions: <live>/<cap>` first (AC10), then the blocks. So
  `overnight_progress_test.sh` L66 reads line 2 (part of D1). With only a
  single-plan run live, or with `--run`, there is no `sessions:` line.

  **Why:** this is AC10's order. Single-plan runs hold no slots (D19), so their
  output stays today's.
- D16: Block headers.
  - With two or more live runs, each block starts with
    `== <slug> (<kind>, pid <pid>) — <run dir>`, oldest first (lock `started=`, then slug).
  - With one live run, the block is printed without a header, as today.
- D17: Outside a project, `registry_status` groups the live entries by `root=`
  in first-seen order. It prints `== <run>, <run> — <root>` and that root's
  status once.
- D18: AC13 with no live run in the project keeps today's
  `no live run in <root>` (an existing assertion). `no live run lists <story>`
  is printed when two or more runs are live and none lists the story. With
  exactly one live run that does not list the story, the run is taken, and
  `chan_open` refuses with today's `<story> is not in run <run>`.

**Sessions**

- D19: Session slots apply to manifest runs only.
  - SO defines no-op `session_acquire`, `session_started` and `session_release`.
  - LN redefines them, as it already redefines `stop_requested` and `halt_reason`.

  **Why:** a single-plan run excludes every manifest run (AC5), so it never
  shares the machine with another run.
- D20: The owner file is four `key=value` lines: `lane=`, `session=`, `run=`,
  `unit=`. A wait entry holds `lane=`, `run=`, `story=` and `unit=`.
  - Release, reclaim and drop rename a slot to `.studio/sessions/.gone.<n>.<pid>.<$$>`, then `rm -rf` it.
  - A slot directory with no owner file, found under the mutex, is reclaimed: its taker died mid-write, since all writes happen under the mutex.
- D21: The cap is read at each try. When it is lowered below the live count, no
  new slot is taken until the count drops; live slots are never revoked. A
  missing or invalid value at runtime uses the preflight's validated
  `SESS_START_CAP`, and never fails a lane.
- D22: The wait is ended only by a halt: `lane_halt` in a lane, or the stop
  file for a final unit (`slot_halt`). An operator's story hold or stop is
  taken at the next `op_boundary`, as today. A halted wait sets `UNIT_HALTED=1`
  and `run_unit` returns without a row. Each caller then ends:
  - `story_units`: `ENDING=$(halt_reason)`;
  - `land_repair`: the record `stopped <halt reason>`;
  - `gate_repair` and `sync_repair`: `ENDING=$(lane_halt_reason)`;
  - `final_unit`: `final_note "stopped before <label>"`, return 1.
- D23: The slot is taken after `model_for` and before `run_event
  unit_started`, the unit clock, `unit.now`, the watchdog and the heartbeat
  (AC27). `$UNIT_DIR/current` and `utag` are written before the wait, so
  `status` names the waiting unit.
  - While it waits, `$UNIT_DIR/slotwait` holds `hh:mm`.
  - `status` prints `    waiting for a session slot since <hh:mm>` under the story line, or `final: waiting for a session slot since <hh:mm>` for a final unit.
- D24: The `session_wait` event is written once per wait, when the first try
  fails. Its fields are:
  - `lane=<k>`, or `final` for a final unit;
  - `story=<id>`, or `-`;
  - `since=<ISO UTC>`.
- D25: The poll interval is `STUDIO_OVERNIGHT_SLOT_POLL_SECONDS`, default 2. It
  is a test hook like `STUDIO_OVERNIGHT_POLL_SECONDS`. A mutex take waits up
  to 10 s, in 0.1 s steps.
- D26: The start dir is the lock's `start=`, else the registry's `start=` for
  the same `run=` (live entries, then `last`), else the caller's `START_DIR`.

**Sync**

- D27: A sync merge is
  `git merge --no-ff --no-edit -m "chore(sync): merge <ref> into <Branch>" <ref>`.

  **Why:** without `--no-ff`, a fast-forwardable ref would put the default
  branch's commits on the story's first-parent line. `studio-adopt`'s
  `part_done` and the land check read that line. A trial confirmed that
  `--no-ff -m` keeps the subject and makes two parents.
- D28: Each sync ref is checked with `rev-parse -q --verify
  refs/remotes/<ref>^{commit}` before `merge-tree`.

  **Why:** a trial showed `merge-tree --write-tree` exits 1, the conflict
  code, for a ref that does not exist. A missing ref is `failed=merge-tree`,
  never a sync repair.
- D29: The ahead test is `git rev-list --count refs/remotes/origin/<Branch>..HEAD`.
  A non-zero count, or a failure (no `origin/<Branch>`; exit 128 in the
  trial), is `skipped=ahead`.

  **Why:** a branch that was never pushed may hold unpushed work.
- D30: `story_synced` fields:
  - merged: `story`, `refs[]=<ref>,<ref>` and `sha` (the new head);
  - skipped: `story` and `skipped=<no-worktree|dirty|ahead>`;
  - failed: `story` and `failed=<fetch|merge-tree|merge|push>`.

  When every ref is already an ancestor, there is no event. When a later ref
  fails after an earlier one merged, the merged event comes first, then the
  failed one. The events doc's sentence "No other field is optional"
  (overnight-events.md:55) gains this exception.
- D31: When a tree is not clean after `merge --abort`, the runner says so,
  naming the worktree, and the event is still `failed=merge`. The runner
  never runs `reset` or `clean` on story work. The next unit's §0 sees the
  tree.
- D32: Sync repair:
  - the story record and unit label are `sync-repair`;
  - `model_for` maps it to the repair model;
  - it is added to:
    - the `story_units_table` regex;
    - the bridge `STATUS` (`in_progress`);
    - `studio-adopt`'s `live_run_check` states;
    - the events doc's `story_state` list;
  - its snapshots are `$UNIT_DIR/sync.before` and `sync.after`;
  - progress is a new `Synced:` line;
  - on success the record goes back to `running`, `stops.before` is
    re-snapshotted, and the unit runs;
  - the ending text is `sync repair: <reason>`, so `run_story` writes
    `stopped sync repair: <reason>`. The reason is:
    - `<the Stop text>` for a new `Stop:` line;
    - `no progress` for no progress, plus the orphan note when the unit was orphaned;
    - `timed out (session_minutes <n>)` for a timeout;
  - `holdable` already returns 1 for these endings (verified), so the story stops at once.
- D33: After a sync repair the check ends. The next ref, if any, is synced
  before the next task unit; nothing is re-checked right after a repair.
- D34: The sync hook is `unit_pre LABEL`.
  - SO's default returns 0.
  - In `story_units` the order becomes: snapshot, stage check, budget, `_base`, then `unit_pre "$_base" || return 0`, then `_before="$SIG"`.
  - LN's `unit_pre` runs `sync_check` for `T<n>` and `final-review` (retries included), only when `CUR_ID` and `LDIR` are set and `lane_halt` is false.

  **Why:** this keeps the sync away from every repair unit and every final-step unit (AC24).

**Awareness, planning and #35**

- D35: `studio-peers` output:
  - default: `<slug> <mode>: <id> task <k/N>, …`, or `<slug> <mode>: -` when no story is open;
  - `--files`: `<slug> <path>` lines, sorted and de-duplicated per run;
  - an unreadable run: `<slug>: unreadable` in both forms.

  Stories whose record is an ending (`landed`, `stopped`, `skipped`) are left
  out. Plans are read with `git -C <root> show <Docs>:<plan>`, since the
  object store is shared by every worktree.
- D36: The `Files:` parser (`runs_plan_files K`):
  - it counts the `### Task [0-9]` headings as ordinals and stops at `## Backlog`; a `## ` line ends a task;
  - it reads the studio `Files:` line and superpowers' `**Files:**` list (`- Create:`, `- Modify:`, `- Test:` bullets);
  - backticked tokens win when a line has any; otherwise the line is split on commas;
  - each path loses a ` (…)` note and a `:<lines>` suffix (`:L?[0-9][0-9,-]*$`);
  - a token holding a blank is dropped;
  - the output is `sort -u`.
- D37: The peers hook is a separate SessionStart entry (`startup|compact`) in
  `hooks.json`, so `test_inbox_hook_registered`'s count of two inbox
  registrations holds. The block also reaches final-step units, which are
  manifest unit sessions (L211).
- D38: The preflight overlap warning (AC9) goes to stderr through `say`, one block per other run:
  ```
  studio-overnight: warning — live run <slug> is changing files this run's unfinished tasks change too:
    <path>            (up to 20)
    and <N> more
  ```
- D39: AC8's data:
  - another live run's ids and branches come from its run dir's `rows.tsv`, and its Target from its `manifest.md`;
  - a stopped record's come from the newest
    `.studio/reports/overnight-<slug>-<8 digits>-<6 digits>/rows.tsv`, a
    pattern that `overnight-<slug>-detached-…` and longer slugs never match;
  - this run's own record without `done` is a resume, and is allowed;
  - every refusal names the run (slug and run dir) and the way out.
- D40: AC20's "run worktree of the run named by the story's manifest row" is
  the checkout from `git worktree list --porcelain` that has a
  `branch refs/heads/run/*` (the main checkout included) and whose
  `.studio/run` manifest has a row for the id.
  - Two such checkouts refuse with `story <id> is listed by two run worktrees: <a> <b>`.
  - None falls back to `$STATE_ROOT`.
- D41: `studio-state init --local` also appends `.studio/STATE.md` to the
  common `info/exclude`. "Linked worktree" means `--git-dir` differs from
  `--git-common-dir`, which a trial confirmed: they are equal in the main
  checkout and differ in a linked one.
- D42: `start_session` exports `STUDIO_START_DIR="$START_DIR"` to every unit,
  final units included (AC30).
- D43: Help (`usage`) gains:
  - several live runs, and `--run` for `status`, `watch` and `stop`;
  - `stop --all`;
  - `max_sessions`;
  - "install or pull omega-ai only when `status` shows no live run" (L82-86, L395).

---

## AC coverage

| AC / gate step | Task(s) | Test(s) |
|---|---|---|
| AC1 root unchanged | T2 | `test_state_root_from_run_worktree`, `test_state_gate_lock_from_run_worktree` |
| AC2 local pointer, `init --local` | T2 | `test_state_init_local_creates_pointer`, `test_state_init_local_refusals`, `test_state_local_pointer_only_when_present`, `test_state_run_worktree_leaves_main_state`, `test_state_story_state_stays_at_root` |
| AC3 run worktree | T3 (finder), T5 (creation) | `test_runs_worktree_of`; `test_autopilot_run_worktree` |
| AC4 per-run lock, stop, exclude, detach | T7 | `test_lanes_per_run_lock_paths`, `test_lanes_detach_with_other_run_live`, `test_lanes_excludes_before_lock` |
| AC5 single vs manifest | T7 | `test_lanes_manifest_refuses_live_single`, `test_overnight_lock_refuses_live_manifest`, `test_lanes_lock_race_single_vs_manifest` |
| AC6 `reg_write` | T7 | `test_lanes_reg_write_keeps_live_sibling` |
| AC7 start dir | T7, T10 | `test_lanes_reap_resume_line_run_worktree`, `test_verbs_channel_start_dir_from_lock` |
| AC8 preflight refusals, re-check | T11 | `test_lanes_preflight_refuses_live_slug_id_branch`, `test_lanes_preflight_refuses_stopped_record`, `test_lanes_preflight_done_record_needs_archive`, `test_lanes_preflight_branch_forms`, `test_lanes_preflight_slug_off_and_digits`, `test_lanes_preflight_resume_own_record`, `test_lanes_recheck_race_one_wins` |
| AC9 overlap warning | T8 (data), T11 (warning) | `test_peers_files_both_forms`; `test_lanes_overlap_warning` |
| AC10 status | T7 (blocks, `--run`), T10 (registry), T12 (`sessions:`, waiting) | `test_lanes_two_runs_each_own_lock`, `test_lanes_status_run_not_live`, `test_status_two_runs_blocks_oldest_first`, `test_status_run_not_live`, `test_status_registry_root_once`, `test_lanes_session_wait_event_and_status` |
| AC11 watch `--run` | T10 | `test_watch_run_selects` |
| AC12 stop | T7 (one run), T10 (rest) | `test_lanes_per_run_lock_paths`, `test_stop_two_runs_refuses`, `test_stop_run_writes_own_flag`, `test_stop_all_writes_each_flag`, `test_stop_story_unchanged` |
| AC13 channel resolution | T7 (live set), T10 | `test_verbs_channel_resolution_by_story`, `test_verbs_channel_run_flag_slug_or_basename`, `test_verbs_channel_no_run_lists_story` |
| AC14 `next` slug forms | T11 | `test_lanes_next` (rewritten), `test_lanes_next_slug_forms` |
| AC15 autopilot new run | T5 | `test_autopilot_run_worktree` |
| AC16 discovery lists | T5 | `test_autopilot_discovery_lists_runs` |
| AC17 brainstorm/plan `<slug>/<id>` | T4 | `test_plan_brainstorm_slug_form` |
| AC18 baseline + start from run worktree | T5 | `test_autopilot_start_from_run_worktree` |
| AC19 `off`, studio lock check | T4 (studio), T5 (autopilot) | `test_router_overnight_lock` (rewritten); `test_autopilot_off_stop_rule` |
| AC20 #35 compatibility | T9 (+T5 forms, T7 env) | `test_adopt_start_checkout_*`, `test_adopt_live_run_check_per_run_lock`, `test_adopt_part_done_ignores_sync`; `test_autopilot_adopt_slug_forms` |
| AC21 `studio-peers` | T8 | `test_peers_default_two_runs`, `test_peers_files_both_forms`, `test_peers_unreadable_run` |
| AC22 peer-runs hook | T8 | `test_peer_hook_block`, `test_peer_hook_silent`, `test_peer_hook_exit0_bad_input`, `test_hook_files` |
| AC23 brief rule | T4 | `test_execute_peers_brief_rule` |
| AC24 sync check | T13 | `test_lanes_sync_clean_merge_no_session`, `test_lanes_sync_skips`, `test_lanes_no_sync_before_repairs` |
| AC25 per-ref merge, abort, push, event | T13 | `test_lanes_sync_integration_two_refs`, `test_lanes_sync_failed_merge_aborts` |
| AC26 sync repair | T13 (+T4 §9) | `test_lanes_sync_conflict_launches_repair`, `test_lanes_sync_repair_stops`; `test_execute_sync_repair_form` |
| AC27 session cap | T6, T12 | `test_sess_*`; `test_lanes_slot_cap_two_across_runs`, `test_lanes_slot_cap_one_alternates`, `test_lanes_slot_kill9_lane_reclaimed`, `test_lanes_slot_stop_ends_wait`, `test_lanes_slot_released_every_exit`, `test_lanes_slot_wait_not_in_session_minutes`, `test_lanes_max_sessions_preflight` |
| AC28 `session_wait` | T12 | `test_lanes_session_wait_event_and_status`, `test_events_contract_doc` |
| AC29 events doc + bridge | T14 (+T12, T13 rows) | `test_events_contract_doc`; bridge `test_event_mapping_rows` (new `story_synced`, `session_wait`, `sync-repair` rows), `test_two_runs_one_root_mirrored`, the `test_commands` run-stop row |
| AC30 `.studio/run` per checkout, `STUDIO_START_DIR` | T7 | `test_lanes_units_get_start_dir` |
| AC31 old-style runs | T7 (+T11) | `test_lanes_old_lock_counts_live`, `test_lanes_old_lock_reaped_by_start`, existing `test_verbs_run_pinning` |
| Milestone step 1 (probe) | T1 | operator-run `tests/probes/run_worktree_probe.sh` |
| Milestone step 2 (suites green) | every task; Final gate | `sh tests/run_all.sh`, `sh integrations/multica/tests/run.sh` |
| Milestone step 3 (round trip) | T15 | `test_lanes_round_trip_two_runs`, `test_lanes_round_trip_sync_conflict`, `test_lanes_round_trip_stop_one_of_two` |
| Milestone step 4 (live, phoenix) | operator, after merge | — |

---

## Review Focus

1. **At most one of two conflicting starts wins.** The lock is taken before
   the re-check, the run dir is populated before the mutex, and the loser
   leaves nothing behind (D8, D9). Tests: `test_lanes_recheck_race_one_wins`
   (T11), `test_lanes_lock_race_single_vs_manifest` (T7).
2. **FIFO slots with owner-checked release.** Only the oldest waiter takes a
   slot, a late release never frees another lane's slot, and a dead owner is
   reclaimed by liveness, never by age. Tests: `test_sess_fifo_oldest_waiter_only`
   and `test_sess_release_owner_checked` (T6), `test_lanes_slot_cap_one_alternates` (T12).
3. **The sync never leaves a half merge and never runs a session for a clean
   one.** Tests: `test_lanes_sync_failed_merge_aborts`,
   `test_lanes_sync_clean_merge_no_session` (T13).
4. **The local pointer is used only in a linked worktree that has one, and
   story state never moves.** Tests: `test_state_local_pointer_only_when_present`,
   `test_state_story_state_stays_at_root` (T2).
5. **Run selection.** Bare `stop` never stops two runs, and the channel finds
   the run from the story. Tests: `test_stop_two_runs_refuses`,
   `test_verbs_channel_resolution_by_story` (T10).

---

## File Structure

| File | Change | Task |
|---|---|---|
| `tests/probes/run_worktree_probe.sh` | new: Milestone step 1 probe | T1 |
| `studios/game-dev/bin/studio-state` | local pointer, `init --local`, header, usage | T2 |
| `studios/game-dev/bin/overnight-runs.sh` | new lib: live runs, selectors, start dir, records, worktree finder, plan files, mutex | T3 |
| `studios/game-dev/bin/overnight-sessions.sh` | new lib: slots, FIFO queue, release, reclaim | T6 |
| `studios/game-dev/bin/studio-overnight` | per-run lock, re-check, excludes, `reg_write`, `unlock`, detach, status blocks, `--run`, stop forms, registry de-dup, session hooks, `unit_pre`, `model_for`, help | T7, T10, T12, T13 |
| `studios/game-dev/bin/overnight-lanes.sh` | `run_paths`, `run_populate`, re-check, reaps, AC8/AC9, `next`, session integration, sync check and repair | T7, T11, T12, T13 |
| `studios/game-dev/bin/overnight-channel.sh` | live-run set, AC13 resolution, per-run `stop --run` | T7, T10 |
| `studios/game-dev/bin/studio-peers` | new reader | T8 |
| `studios/game-dev/hooks/peer-runs.sh` | new SessionStart hook | T8 |
| `studios/game-dev/hooks/hooks.json` | register `peer-runs.sh` | T8 |
| `studios/game-dev/bin/studio-adopt` | `start_checkout`, `live_run_check`, `part_done` | T9 |
| `studios/game-dev/skills/execute/SKILL.md` | §1 mode list, §9 `sync:`, the peers brief rule | T4 |
| `studios/game-dev/skills/brainstorm/SKILL.md`, `studios/game-dev/skills/plan/SKILL.md` | `<slug>/<id>` form | T4 |
| `studios/game-dev/skills/studio/SKILL.md` | AC19 | T4 |
| `shared/omega/skills/autopilot/SKILL.md` | AC15, AC16, AC18, AC19, AC20 forms | T5 |
| `docs/game-dev/overnight-events.md` | `session_wait` (T12), `story_synced` and `sync-repair` (T13), "Finding a run" (T14) | T12, T13, T14 |
| `README.md`, `integrations/multica/README.md`, `docs/game-dev/PROGRESS.md` | one line each; progress entry | T14 |
| `integrations/multica/bridge/mirror.py` | `story_synced` comment, `sync-repair` status | T14 |
| `tests/state_test.sh` | AC1, AC2 | T2 |
| `tests/overnight_runs_test.sh` | new suite for `overnight-runs.sh` | T3 |
| `tests/overnight_sessions_test.sh` | new suite for `overnight-sessions.sh` | T6 |
| `tests/studio_peers_test.sh` | new suite for `studio-peers` and the hook | T8 |
| `tests/studio_test.sh` | skill contracts (execute, brainstorm, plan, studio) | T4 |
| `tests/omega_contracts/autopilot_contract.sh` | autopilot contract | T5 |
| `tests/hook_test.sh` | hook files and registration | T8 |
| `tests/studio_adopt_test.sh` | AC20 | T9 |
| `tests/overnight_test.sh` | fake per-run runs, verbs, status, help | T7, T10, T12 |
| `tests/overnight_lanes_test.sh` | lanes: locks, preflight, next, slots, sync, round trip; the stub `claude` | T7, T11, T12, T13, T15 |
| `tests/overnight_progress_test.sh` | L66 (D15) | T12 |
| `integrations/multica/tests/test_mirror_runs.py`, `test_mirror_status.py`, `test_commands.py` | AC29 | T14 |

---

## Tasks

### Task 1: The run-worktree probe (Milestone gate step 1)

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L24-29, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L336-336, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L394-394
Review: final
Wave: 0
Touches: `tests/probes/run_worktree_probe.sh`

**Interfaces:**
- Produces: `sh tests/probes/run_worktree_probe.sh [LAUNCHER]` (default `claude-gd`).
  It exits 0 on PASS, 1 on FAIL, 2 on usage or a missing launcher, and keeps its logs in `$PROBE_DIR`.
- Consumes: `studio-overnight deny-rules --dir <dir>` (the runner's deny list),
  `studio-state`, `studio-gate` and the runner's launch flags (`with_launch_args`).

**Implementer builds** (no model call; the implementer never runs the probe):

- [ ] **Step 1: Write the script.** Follow `tests/probes/bash_timeout_probe.sh`:
  a header that explains what it proves, `set -u`, usage, and a `mktemp`
  `PROBE_DIR`. It is not part of `tests/run_all.sh`. The fixture it builds,
  all under `$PROBE_DIR`, offline:
  - A bare origin, plus a project `p`:
    - `git init -b main`, one commit, `remote set-head origin main`;
    - `studio-state init`, with `.studio/config.json` committed and pushed;
    - `STUDIO_STORY=x studio-state init`, then `set task 0/3`.
  - Branches `x-b` and `run/x`, both pushed.
  - A story worktree `p/.claude/worktrees/x-b` on `x-b`, and a run worktree
    `p/.claude/worktrees/run-x` on `run/x`.
  - `p/.claude/worktrees/` added to the common `info/exclude`.
  - A shim `studio-test` in `$PROBE_DIR/bin` that runs
    `studio-gate studio-test -- sh -c '…'`. The inner command writes these to `$PROBE_DIR/gate.seen`:
    - `root=$(studio-state root)`;
    - `lock=<yes|no>`, whether `<root>/.studio/gate.lock` exists while the command runs.
  - `PATH` is `$PROBE_DIR/bin:<repo>/studios/game-dev/bin:$PATH`.

  The session is launched from the run worktree with the runner's flags:
  ```sh
  ( cd "$RW" && env STUDIO_STORY=x "$L" -p "$P" --model sonnet --output-format stream-json --verbose \
      --permission-mode auto --permission-prompts none --max-budget-usd 2 --disallowedTools $RULES ) \
    > "$D/session.jsonl" 2> "$D/session.err" < /dev/null
  ```
  `$RULES` holds one argument per line of `studio-overnight deny-rules --dir "$RW"`,
  built with `set --` as `with_launch_args` does. The prompt `$P` names the
  three steps verbatim:
  1. enter `<root>/.claude/worktrees/x-b` with execute's **Enter the feature
     checkout** (`EnterWorktree path:` when offered, else `cd`), write
     `probe.txt`, then `git add probe.txt && git commit -m "probe: story commit"`;
  2. run `STUDIO_STORY=x studio-state set task 1/3`;
  3. run `studio-test`.

  Then it replies with one line: `PROBE: done`, or `PROBE: denied <step>`.
- [ ] **Step 2: The verdict.** After the session, the script checks:
  - `git -C p log x-b -1 --format=%s` is `probe: story commit`, and `run/x` and `main` have no such commit;
  - `p/.studio/stories/x.md` has `task: 1/3`, and `run-x/.studio/stories/` does not exist;
  - `gate.seen` has `root=<p>` and `lock=yes`;
  - the jsonl has no permission denial (`"permission_denials":[]` or no
    `permission_denials` entry naming a tool), and the reply line is `PROBE: done`.

  It prints `PASS` or `FAIL: <first failed check>`, and the log paths.
- [ ] **Step 3: Syntax only.** Run `sh -n tests/probes/run_worktree_probe.sh`; expect exit 0.
- [ ] **Step 4: Commit.** `test(probes): run-worktree probe for concurrent runs (#39)` with the trailers.

**Operator runs** (needs `claude-gd` and a login; about one model session):

- [ ] `sh tests/probes/run_worktree_probe.sh`. Expected: `PASS`.
- [ ] **Gate:** any `FAIL` stops execution. A denial or a commit in the wrong
  checkout means the run-worktree design does not hold under the runner's
  permissions. The plan returns to the operator with the log, and no wave-1
  task starts.

---

### Task 2: `studio-state` — the local stage pointer

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L120-132, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L291-291, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L337-343
Review: task
Wave: 1
Touches: `studios/game-dev/bin/studio-state`, `tests/state_test.sh`

**Interfaces:**
- Produces:
  - `STATE` is `<work root>/.studio/STATE.md` when the work root is a linked
    worktree and that file exists; otherwise it is `<root>/.studio/STATE.md`.
    `STUDIO_STORY` still overrides it to `<root>/.studio/stories/<id>.md`.
  - `studio-state init --local`.
  - `root` and its usage line are unchanged in output.
- Consumes: nothing new.

- [ ] **Step 1: Write the failing tests** in `tests/state_test.sh`, and add each to `run_tests` (`grep -n '^run_tests' tests/state_test.sh`):

```sh
# #39 fixture: a project P (main checkout, studio-state init, one commit) and a
# linked run worktree RW on run/x under P/.claude/worktrees/run-x.
rw_fixture() {
  P="$TMP/rw-$1"; RW="$P/.claude/worktrees/run-x"; rm -rf "$P"; mkdir -p "$P"
  ( cd "$P" && git init -q -b main && sh "$STATE_BIN" init >/dev/null \
      && git add -A && git -c user.name=t -c user.email=t@t commit -qm init \
      && git worktree add -q -b run/x "$RW" ) >/dev/null 2>&1
}
test_state_root_from_run_worktree() {
  rw_fixture root
  assert_eq "$P" "$(cd "$RW" && sh "$STATE_BIN" root)" "root is the main checkout from a run worktree"
  assert_eq "$RW" "$(cd "$RW" && sh "$STATE_BIN" root --work)" "--work is the run worktree"
}
test_state_init_local_creates_pointer() {
  rw_fixture local
  ( cd "$RW" && sh "$STATE_BIN" init --local ) > "$TMP/out" 2>&1
  assert_file "$RW/.studio/STATE.md" "the local pointer exists"
  assert_contains "$RW/.studio/STATE.md" '^stage: idle$' "stage idle"
  assert_contains "$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude" '^\.studio/STATE\.md$' "kept out of git (D41)"
  assert_eq "" "$(git -C "$RW" status --porcelain)" "no untracked noise"
}
test_state_init_local_refusals() {
  rw_fixture refuse
  st=0; ( cd "$P" && sh "$STATE_BIN" init --local ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "refused in the main checkout"
  assert_contains "$TMP/out" "init --local: the main checkout" "says why"
  ( cd "$RW" && sh "$STATE_BIN" init --local ) >/dev/null 2>&1
  st=0; ( cd "$RW" && sh "$STATE_BIN" init --local ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "refused when the checkout already has one"
}
test_state_local_pointer_only_when_present() {
  rw_fixture present
  ( cd "$RW" && sh "$STATE_BIN" set stage brainstorm ) >/dev/null 2>&1
  assert_contains "$P/.studio/STATE.md" '^stage: brainstorm$' "no local pointer: the root's STATE.md, as today"
  ( cd "$P" && sh "$STATE_BIN" set stage idle ) >/dev/null 2>&1
  ( cd "$RW" && sh "$STATE_BIN" init --local && sh "$STATE_BIN" set stage plan ) >/dev/null 2>&1
  assert_contains "$RW/.studio/STATE.md" '^stage: plan$' "with one: the local pointer"
  assert_eq idle "$(cd "$P" && sh "$STATE_BIN" get stage)" "the main checkout reads its own"
  rm -f "$RW/.studio/STATE.md"
  assert_eq idle "$(cd "$RW" && sh "$STATE_BIN" get stage)" "pointer removed: back to the root's STATE.md"
}
test_state_run_worktree_leaves_main_state() {
  rw_fixture untouched
  _before="$(cat "$P/.studio/STATE.md")"
  ( cd "$RW" && sh "$STATE_BIN" init --local && sh "$STATE_BIN" set stage brainstorm \
      && sh "$STATE_BIN" set spec docs/s.md && sh "$STATE_BIN" ledger "spec approved docs/s.md" ) >/dev/null 2>&1
  assert_eq "$_before" "$(cat "$P/.studio/STATE.md")" "stage writes in a run worktree leave the main STATE.md"
}
test_state_story_state_stays_at_root() {
  rw_fixture story
  ( cd "$RW" && sh "$STATE_BIN" init --local && STUDIO_STORY=S1 sh "$STATE_BIN" init \
      && STUDIO_STORY=S1 sh "$STATE_BIN" set task 1/3 ) >/dev/null 2>&1
  assert_contains "$P/.studio/stories/S1.md" '^task: 1/3$' "STUDIO_STORY state is at <root>"
  assert_missing "$RW/.studio/stories" "never in the run worktree"
}
test_state_gate_lock_from_run_worktree() {
  rw_fixture gate
  ( cd "$RW" && sh "$BIN/studio-gate" studio-test -- sh -c "test -d '$P/.studio/gate.lock' && echo held" ) > "$TMP/out" 2>&1
  assert_contains "$TMP/out" '^held$' "studio-gate locks <main>/.studio/gate.lock from a run worktree"
  assert_missing "$RW/.studio/gate.lock" "and nothing in the run worktree"
}
```
(`STATE_BIN` and `BIN` stand for the suite's own names for `studio-state` and the bin dir; check them with `grep -n '^[A-Z_]*=' tests/state_test.sh | head`, and use the `assert_*` names `tests/assert.sh` defines.)

- [ ] **Step 2: Run them and see them fail.** Run `TESTS_ONLY="test_state_init_local_creates_pointer test_state_local_pointer_only_when_present" sh tests/state_test.sh`. Expected: FAIL. (`test_state_root_from_run_worktree`, `…_story_state_stays_at_root` and `…_gate_lock_…` may already pass, which is fine; they pin AC1.)
- [ ] **Step 3: Implement.**
  - In the roots block (`grep -n '^STATE="\$STATE_ROOT/.studio/STATE.md"' studios/game-dev/bin/studio-state`, line 47), replace the `STATE=` line with:
    ```sh
    # AC2 (#39): a linked worktree (its git dir is not the common one) that has
    # its own .studio/STATE.md — a run worktree after `init --local` — keeps its
    # stage there. Every other key stays at today's root: STUDIO_STORY state,
    # the gate lock, records and reports at STATE_ROOT; the ledger, config.json,
    # spec and plan at WORK_ROOT.
    STATE="$STATE_ROOT/.studio/STATE.md"
    _gd="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
    _gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    if [ -n "$_gd" ] && [ "$_gd" != "$_gcd" ] && [ -f "$WORK_ROOT/.studio/STATE.md" ]; then
      STATE="$WORK_ROOT/.studio/STATE.md"
    fi
    LINKED=0; [ -z "$_gd" ] || [ "$_gd" = "$_gcd" ] || LINKED=1
    ```
    The `STUDIO_STORY` block after it is unchanged, so it still overrides `STATE`.
  - Add the `init --local` branch before `init)`'s story branch:
    ```sh
    if [ "${2:-}" = --local ]; then
      [ "$LINKED" = 1 ] || fail "init --local: the main checkout keeps $STATE_ROOT/.studio/STATE.md — run it in a run worktree"
      [ ! -f "$WORK_ROOT/.studio/STATE.md" ] || fail "init --local: $WORK_ROOT/.studio/STATE.md already exists"
      mkdir -p "$WORK_ROOT/.studio"
      # same idle template as plain init (one heredoc; factor it into a function)
      write_idle_state "$WORK_ROOT/.studio/STATE.md"
      _gc="$_gcd"; mkdir -p "$_gc/info"
      grep -qxF '.studio/STATE.md' "$_gc/info/exclude" 2>/dev/null || {
        if [ -s "$_gc/info/exclude" ] && [ -n "$(tail -c 1 "$_gc/info/exclude")" ]; then printf '\n' >> "$_gc/info/exclude"; fi
        printf '.studio/STATE.md\n' >> "$_gc/info/exclude"; }
      printf 'initialised %s (local stage pointer)\n' "$WORK_ROOT/.studio/STATE.md"; exit 0
    fi
    ```
    Factor the two existing idle heredocs into `write_idle_state FILE`. `init --local` together with `STUDIO_STORY` is a usage error.
  - Header comment (lines 2-7): one project has one stage, except that a run
    worktree (`init --local`) keeps its own stage pointer. Everything else
    keyed on `root` stays project-wide (AC1's list). Usage line:
    `studio-state root [--work]   print the project root (the main checkout; the gate lock, stories, records), or the working root`
    and `init [--local]`.
- [ ] **Step 4: Run the tests** from Step 1, all eight. Expected: PASS. Then run `sh tests/state_test.sh` and `sh tests/toolkit_test.sh`. Expected: exit 0.
- [ ] **Step 5: Commit.** `feat(studio): local stage pointer for run worktrees (#39)` with the trailers.

---

### Task 3: `overnight-runs.sh` — the live runs of a project

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L75-75, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L133-133, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L143-144, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L209-209, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L303-303
Review: task
Wave: 1
Touches: `studios/game-dev/bin/overnight-runs.sh`, `tests/overnight_runs_test.sh`

**Interfaces** (a sourced lib; every function reads only, except `mx_*`):

```
runs_kv KEY FILE              value of the first KEY= line
runs_lock_live FILE           pid= alive, not a zombie, ps args contain studio-overnight
runs_live ROOT                TSV, oldest first (started, then slug):
                              started  slug  kind  pid  run_dir  start_dir  lock_path
                              kind manifest|single; slug '-' for single; covers
                              ROOT/.studio/runs/*/lock and ROOT/.studio/overnight.lock
runs_match SEL                stdin runs_live lines -> the line whose slug or run-dir basename is SEL
runs_stop_of LOCK             the stop flag paired with a lock (D5)
runs_start_dir LOCK           D26 (prints "" when unknown)
runs_record_open ROOT SLUG    0: ROOT/.studio/runs/SLUG/landed.tsv exists and done does not
runs_record_done ROOT SLUG    0: landed.tsv and done exist
runs_rows ROOT SLUG [RUNDIR]  path of the run's rows.tsv: RUNDIR/rows.tsv, else the newest
                              ROOT/.studio/reports/overnight-SLUG-<8d>-<6d>/rows.tsv; 1 none
runs_mf_header FILE NAME      a manifest header value (mf_header's rule)
runs_mf_slug FILE             the manifest's `# Run:` slug
runs_worktree_of BRANCH       the checkout that has BRANCH checked out (porcelain), "" for none
runs_plan_files K             stdin a plan -> files of tasks K+1..N, sorted unique (D36)
mx_take PATH PID / mx_drop PATH PID   symlink mutex (D25)
```

- [ ] **Step 1: Write the failing suite** `tests/overnight_runs_test.sh`. Make it executable; `run_all.sh` picks up `tests/*_test.sh`.

```sh
#!/bin/sh
# overnight-runs.sh (#39): the live runs of one project, selectors, records,
# the run-worktree finder, the plan Files: parser and the symlink mutex.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
LIB="$REPO_ROOT/studios/game-dev/bin/overnight-runs.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'kill $DUMMIES 2>/dev/null; rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
DUMMIES=""
TAB="$(printf '\t')"
. "$LIB"
# live_dummy — a live pid whose args name studio-overnight (DUMMY).
live_dummy() { sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; DUMMIES="$DUMMIES $DUMMY"; }
dead_pid() { sh -c ':' & wait $!; DEAD=$!; }
# plock ROOT SLUG PID STARTED [START] — a per-run lock and its run dir with a manifest.
plock() {
  _d="$1/.studio/reports/overnight-$2-20261004-21000$5"; mkdir -p "$_d" "$1/.studio/runs/$2"
  printf '# Run: %s\n\nMode: integration\nTarget: integration/%s\n' "$2" "$2" > "$_d/manifest.md"
  printf 'pid=%s\nrun=%s\nstarted=%s\n%s' "$3" "$_d" "$4" "${6:+start=$6
}" > "$1/.studio/runs/$2/lock"
  PL_DIR="$_d"
}

test_runs_live_per_run_and_old_lock() {
  R="$TMP/live"; mkdir -p "$R/.studio"
  live_dummy; plock "$R" beta "$DUMMY" 2026-10-04T21:00:05Z 1
  live_dummy; plock "$R" alpha "$DUMMY" 2026-10-04T21:00:01Z 2 "$R/wt-alpha"
  live_dummy; _od="$R/.studio/reports/overnight-old-20261003-210000"; mkdir -p "$_od"
  printf '# Run: old\n' > "$_od/manifest.md"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$DUMMY" "$_od" > "$R/.studio/overnight.lock"
  runs_live "$R" > "$TMP/out"
  assert_eq "old alpha beta" "$(cut -f2 "$TMP/out" | tr '\n' ' ' | sed 's/ $//')" "oldest first, the old-style lock included"
  assert_eq "manifest manifest manifest" "$(cut -f3 "$TMP/out" | tr '\n' ' ' | sed 's/ $//')" "an old lock whose run dir has manifest.md is a manifest run"
  assert_eq "$R/wt-alpha" "$(awk -F'\t' '$2 == "alpha" { print $6 }' "$TMP/out")" "start dir from start="
  assert_eq "$R/.studio/overnight.lock" "$(awk -F'\t' '$2 == "old" { print $7 }' "$TMP/out")" "the lock path"
}
test_runs_live_skips_dead_and_single() {
  R="$TMP/dead"; mkdir -p "$R/.studio"
  dead_pid; plock "$R" gone "$DEAD" 2026-10-04T21:00:00Z 1
  live_dummy; _sd="$R/.studio/reports/overnight-20261004-210000"; mkdir -p "$_sd"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T22:00:00Z\n' "$DUMMY" "$_sd" > "$R/.studio/overnight.lock"
  runs_live "$R" > "$TMP/out"
  assert_eq 1 "$(grep -c . "$TMP/out")" "a dead lock is not live"
  assert_eq "-${TAB}single" "$(cut -f2,3 "$TMP/out")" "a single-plan run: slug -, kind single"
}
test_runs_match_slug_or_basename() {
  R="$TMP/match"; mkdir -p "$R/.studio"; live_dummy; plock "$R" alpha "$DUMMY" 2026-10-04T21:00:00Z 1
  assert_eq alpha "$(runs_live "$R" | runs_match alpha | cut -f2)" "by slug"
  assert_eq alpha "$(runs_live "$R" | runs_match "$(basename "$PL_DIR")" | cut -f2)" "by run dir basename"
  assert_eq "" "$(runs_live "$R" | runs_match beta)" "no match prints nothing"
}
test_runs_stop_of() {
  assert_eq /r/.studio/runs/a/stop "$(runs_stop_of /r/.studio/runs/a/lock)" "per-run"
  assert_eq /r/.studio/overnight.stop "$(runs_stop_of /r/.studio/overnight.lock)" "old-style and single-plan (D5)"
}
test_runs_start_dir_lock_then_registry() {
  R="$TMP/sd"; mkdir -p "$R/.studio" "$HOME/.claude-gamedev/runs"
  live_dummy; plock "$R" a "$DUMMY" 2026-10-04T21:00:00Z 1 "$R/wt-a"
  assert_eq "$R/wt-a" "$(runs_start_dir "$R/.studio/runs/a/lock")" "lock start= wins"
  plock "$R" b "$DUMMY" 2026-10-04T21:00:00Z 2
  printf 'root=%s\nstart=%s\nrun=%s\npid=%s\n' "$R" "$R/wt-b" "$PL_DIR" "$DUMMY" > "$HOME/.claude-gamedev/runs/x-$DUMMY"
  assert_eq "$R/wt-b" "$(runs_start_dir "$R/.studio/runs/b/lock")" "else the registry's start= for the same run="
  plock "$R" c "$DUMMY" 2026-10-04T21:00:00Z 3
  assert_eq "" "$(runs_start_dir "$R/.studio/runs/c/lock")" "else empty (the caller keeps its own)"
}
test_runs_records() {
  R="$TMP/rec"; mkdir -p "$R/.studio/runs/open" "$R/.studio/runs/done" "$R/.studio/runs/lockonly"
  : > "$R/.studio/runs/open/landed.tsv"; : > "$R/.studio/runs/done/landed.tsv"; : > "$R/.studio/runs/done/done"
  : > "$R/.studio/runs/lockonly/lock"
  runs_record_open "$R" open; assert_eq 0 $? "landed.tsv, no done: open"
  runs_record_open "$R" done; assert_eq 1 $? "done is not open"
  runs_record_done "$R" done; assert_eq 0 $? "done"
  runs_record_open "$R" lockonly; assert_eq 1 $? "a lock alone is no record (D4)"
}
test_runs_rows_newest_report() {
  R="$TMP/rows"; mkdir -p "$R/.studio/reports/overnight-a-20261001-010101" "$R/.studio/reports/overnight-a-20261002-010101" \
    "$R/.studio/reports/overnight-a-b-20261003-010101" "$R/.studio/reports/overnight-a-detached-20261004-010101"
  for _d in "$R"/.studio/reports/*; do : > "$_d/rows.tsv"; done
  assert_eq "$R/.studio/reports/overnight-a-20261002-010101/rows.tsv" "$(runs_rows "$R" a)" "the newest of slug a only (D39)"
  assert_eq /x/rows.tsv "$(mkdir -p "$TMP/x"; runs_rows "$R" a /x)" "an explicit run dir wins"
}
test_runs_worktree_of() {
  R="$TMP/wt"; ( mkdir -p "$R" && cd "$R" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i \
      && git branch run/alpha && git worktree add -q .claude/worktrees/run-alpha run/alpha ) >/dev/null 2>&1
  assert_eq "$R/.claude/worktrees/run-alpha" "$(cd "$R" && runs_worktree_of run/alpha)" "the checkout holding run/alpha"
  assert_eq "$R" "$(cd "$R" && runs_worktree_of main)" "the main checkout counts"
  assert_eq "" "$(cd "$R" && runs_worktree_of run/beta)" "none"
}
test_runs_plan_files_studio_form() {
  printf '%s\n' '# P' '' '### Task 1: a' 'Files: `a.sh` (:10), `t/a_test.sh`' '' '### Task 2: b' \
    'Files: src/b.gd:L10-20, src/c.gd (new)' '' '## Backlog' '' '### Task 3: cut' 'Files: z.sh' > "$TMP/plan"
  assert_eq "src/b.gd src/c.gd" "$(runs_plan_files 1 < "$TMP/plan" | tr '\n' ' ' | sed 's/ $//')" "tasks after k=1 only; :lines and (notes) stripped; backlog ignored"
  assert_eq "a.sh src/b.gd src/c.gd t/a_test.sh" "$(runs_plan_files 0 < "$TMP/plan" | tr '\n' ' ' | sed 's/ $//')" "k=0: every task, sorted"
}
test_runs_plan_files_superpowers_form() {
  printf '%s\n' '### Task 1: x' '' '**Files:**' '- Create: `src/new.py`' '- Modify: `src/old.py:123-145`' \
    '- Test: `tests/test_x.py`' '' '- [ ] **Step 1: …**' '' '## Self-review' 'Files: no.sh' > "$TMP/plan2"
  assert_eq "src/new.py src/old.py tests/test_x.py" "$(runs_plan_files 0 < "$TMP/plan2" | tr '\n' ' ' | sed 's/ $//')" "bullets read; a ## line ends the task"
}
test_mx_take_drop_and_dead_owner() {
  M="$TMP/m.mutex"; live_dummy
  mx_take "$M" "$DUMMY"; assert_eq 0 $? "taken"
  assert_eq "$DUMMY" "$(readlink "$M")" "names its owner"
  mx_drop "$M" 1; assert_symlink "$M" "a drop by another pid leaves it"
  mx_drop "$M" "$DUMMY"; assert_missing "$M" "dropped by its owner"
  dead_pid; ln -s "$DEAD" "$M"
  mx_take "$M" "$DUMMY"; assert_eq 0 $? "a dead owner's mutex is removed and retaken"
  mx_drop "$M" "$DUMMY"
}

run_tests test_runs_live_per_run_and_old_lock test_runs_live_skips_dead_and_single test_runs_match_slug_or_basename \
  test_runs_stop_of test_runs_start_dir_lock_then_registry test_runs_records test_runs_rows_newest_report \
  test_runs_worktree_of test_runs_plan_files_studio_form test_runs_plan_files_superpowers_form test_mx_take_drop_and_dead_owner
```
(`run_tests` and `assert_symlink` are in `tests/assert.sh`; check the exact signatures with `grep -n '^assert_symlink\|^run_tests' tests/assert.sh`.)

- [ ] **Step 2: Run it and see it fail.** `sh tests/overnight_runs_test.sh`. Expected: FAIL (no lib).
- [ ] **Step 3: Implement** `studios/game-dev/bin/overnight-runs.sh` (`chmod +x`, with the `#!/bin/sh` line `test_bin_syntax` requires). The hard parts, in full:

```sh
#!/bin/sh
# overnight-runs.sh — the live runs of one project (#39), sourced by
# studio-overnight, overnight-lanes.sh, overnight-channel.sh, studio-peers
# and studio-adopt. The per-run locks (.studio/runs/<slug>/lock) and the
# single-plan or old-style .studio/overnight.lock are the source of truth
# (AC6); the registry is only a view. Everything here reads, except mx_*.

runs_kv() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -n 1; }
runs_lock_live() {
  _rk_p="$(runs_kv pid "$1")"
  [ -n "$_rk_p" ] && kill -0 "$_rk_p" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$_rk_p" 2>/dev/null)" in Z*|'') return 1 ;; esac
  ps -o args= -p "$_rk_p" 2>/dev/null | grep -q studio-overnight
}
runs_mf_header() { sed -n "s/^$2:[[:blank:]]*//p" "$1" 2>/dev/null | head -n 1 | sed -e 's/[[:blank:]]#.*$//' -e 's/[[:blank:]]*$//'; }
runs_mf_slug() { sed -n 's/^# Run:[[:blank:]]*//p' "$1" 2>/dev/null | head -n 1 | sed -e 's/[[:blank:]]#.*$//' -e 's/[[:blank:]]*$//'; }
runs_stop_of() {
  case "$1" in */.studio/overnight.lock) printf '%s\n' "${1%/overnight.lock}/overnight.stop" ;;
               *) printf '%s\n' "${1%/lock}/stop" ;; esac
}
runs_start_dir() {
  _rs_s="$(runs_kv start "$1")"
  if [ -z "$_rs_s" ]; then
    _rs_r="$(runs_kv run "$1")"; _rs_g="${REGISTRY:-$HOME/.claude-gamedev/runs}"
    for _rs_e in "$_rs_g"/overnight-* "$_rs_g/last"; do
      [ -f "$_rs_e" ] && [ -n "$_rs_r" ] && [ "$(runs_kv run "$_rs_e")" = "$_rs_r" ] || continue
      _rs_s="$(runs_kv start "$_rs_e")"; break
    done
  fi
  printf '%s\n' "$_rs_s"
}
runs_live() {
  for _rl_l in "$1"/.studio/runs/*/lock "$1/.studio/overnight.lock"; do
    [ -f "$_rl_l" ] && runs_lock_live "$_rl_l" || continue
    _rl_d="$(runs_kv run "$_rl_l")"
    case "$_rl_l" in
      */.studio/overnight.lock)
        if [ -f "$_rl_d/manifest.md" ]; then _rl_k=manifest; _rl_s="$(runs_mf_slug "$_rl_d/manifest.md")"
        else _rl_k=single; _rl_s=-; fi ;;
      *) _rl_k=manifest; _rl_s="${_rl_l%/lock}"; _rl_s="${_rl_s##*/}" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(runs_kv started "$_rl_l")" "$_rl_s" "$_rl_k" \
      "$(runs_kv pid "$_rl_l")" "$_rl_d" "$(runs_start_dir "$_rl_l")" "$_rl_l"
  done | sort -t "$(printf '\t')" -k1,1 -k2,2
}
runs_match() { awk -F'\t' -v s="$1" '{ b = $5; sub(/.*\//, "", b) } $2 == s || b == s { print; exit }'; }
runs_record_open() { [ -f "$1/.studio/runs/$2/landed.tsv" ] && [ ! -f "$1/.studio/runs/$2/done" ]; }
runs_record_done() { [ -f "$1/.studio/runs/$2/landed.tsv" ] && [ -f "$1/.studio/runs/$2/done" ]; }
runs_rows() {
  if [ -n "${3:-}" ]; then printf '%s\n' "$3/rows.tsv"; return 0; fi
  _rr="$(ls -d "$1/.studio/reports/overnight-$2-"[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | sort | tail -n 1)"
  [ -n "$_rr" ] && [ -f "$_rr/rows.tsv" ] || return 1
  printf '%s\n' "$_rr/rows.tsv"
}
runs_worktree_of() {
  git worktree list --porcelain 2>/dev/null \
    | awk -v b="branch refs/heads/$1" '/^worktree /{ w = substr($0, 10) } $0 == b { print w; exit }'
}
runs_plan_files() {
  awk -v k="$1" '
    function clean(p) {
      sub(/[ \t]+\(.*$/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", p)
      sub(/:L?[0-9][0-9,-]*$/, "", p)
      if (p != "" && p !~ /[ \t]/) print p
    }
    function emit(s,   n, i, a) {
      if (s ~ /`/) {
        while (match(s, /`[^`]+`/)) { clean(substr(s, RSTART + 1, RLENGTH - 2)); s = substr(s, RSTART + RLENGTH) }
        return
      }
      n = split(s, a, ","); for (i = 1; i <= n; i++) clean(a[i])
    }
    /^## Backlog/ { exit }
    /^### Task [0-9]/ { t++; intask = 1; inlist = 0; next }
    /^## / { intask = 0; inlist = 0; next }
    !intask || t <= k { next }
    /^Files:/ { s = $0; sub(/^Files:[ \t]*/, "", s); emit(s); next }
    /^\*\*Files:\*\*/ { inlist = 1; s = $0; sub(/^\*\*Files:\*\*[ \t]*/, "", s); if (s != "") emit(s); next }
    inlist && /^[ \t]*- (Create|Modify|Test):/ { s = $0; sub(/^[ \t]*- (Create|Modify|Test):[ \t]*/, "", s); emit(s); next }
    inlist && /^[ \t]*$/ { next }
    inlist { inlist = 0 }
  ' | sort -u
}
mx_take() {
  _mx_i=0
  while ! ln -s "$2" "$1" 2>/dev/null; do
    _mx_o="$(readlink "$1" 2>/dev/null)"
    if [ -n "$_mx_o" ] && ! kill -0 "$_mx_o" 2>/dev/null && [ "$(readlink "$1" 2>/dev/null)" = "$_mx_o" ]; then
      rm -f "$1"; continue
    fi
    _mx_i=$((_mx_i + 1)); [ "$_mx_i" -lt 100 ] || return 1
    sleep 0.1
  done
}
mx_drop() { [ "$(readlink "$1" 2>/dev/null)" != "$2" ] || rm -f "$1"; return 0; }
```
Each function gets a one-line comment, in the house style. `runs_live`'s
`sort -t <tab> -k1,1 -k2,2` puts the oldest first (ISO times sort as text),
breaking ties by slug.

- [ ] **Step 4: Run the suite.** `sh tests/overnight_runs_test.sh`. Expected: PASS. Then `sh tests/studio_test.sh` (`test_bin_syntax`). Expected: exit 0.
- [ ] **Step 5: Commit.** `feat(studio): overnight-runs.sh — live runs, selectors, plan files (#39)` with the trailers.

---

### Task 4: Skills — execute §1/§9 and the peers brief rule, brainstorm and plan `<slug>/<id>`, studio's lock check

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L58-63, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L189-194, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L196-196, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L215-215, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L232-239, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L295-297, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L379-384, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L396-396
Review: final
Wave: 1
Touches: `studios/game-dev/skills/execute/SKILL.md`, `studios/game-dev/skills/brainstorm/SKILL.md`, `studios/game-dev/skills/plan/SKILL.md`, `studios/game-dev/skills/studio/SKILL.md`, `tests/studio_test.sh`

**Interfaces:** skill text only, pinned by contract tests in `tests/studio_test.sh`.

- [ ] **Step 1: Write the failing tests** in `tests/studio_test.sh`, and add them to its `run_tests`:
  - `test_execute_sync_repair_form`: `execute/SKILL.md` contains:
    - `STUDIO_REPAIR=sync:<ref>`;
    - `stage execute` (as §9's `sync:` precondition);
    - `fix(sync): <summary>` and `Synced: <summary>`;
    - `Stop: sync repair red — <failing line>`;
    - `studio-test <paths>`.

    §1's mode list names `--land` with `sync:<ref>`, so assert `--land.*sync:`.
  - `test_execute_peers_brief_rule`: execute contains `Other live runs` and
    `every implementer and fixer brief` (AC23).
  - `test_plan_brainstorm_slug_form`: both skills contain:
    - `/game-dev:plan <slug>/<id>` (respectively `/game-dev:brainstorm <slug>/<id>`);
    - `run/<slug>`;
    - `studio-state show` after entering;
    - the refusal `no checkout holds run/<slug>`;
    - `The bare <id> form`.
  - `test_router_overnight_lock` (rewrite, D1):
    - it asserts `studio-overnight status`;
    - it asserts no `.studio/overnight.lock`;
    - in place of "routes nothing else" it asserts `A live run does not make the project busy`.

  Check the current body with `grep -n 'test_router_overnight_lock' -A12 tests/studio_test.sh`.
- [ ] **Step 2: Run them and see them fail.** `TESTS_ONLY="test_execute_sync_repair_form test_execute_peers_brief_rule test_plan_brainstorm_slug_form test_router_overnight_lock" sh tests/studio_test.sh`. Expected: FAIL.
- [ ] **Step 3: Edit the skills.**
  - **execute §1** (`grep -n '^## 1. Mode' studios/game-dev/skills/execute/SKILL.md`): in the `--land` item, add "or a sync repair (`STUDIO_REPAIR=sync:<ref>`, §9)".
  - **execute §9** (`grep -n '^## 9. Landing repair' …`): add a `sync:<ref>` form after the preconditions:
    - preconditions: `stage execute` in place of `stage idle` and a `shipped` line; `STUDIO_REPAIR=sync:<ref>` set;
    - **Enter the feature checkout** as today;
    - `git fetch origin`, then `git merge <ref>`;
    - resolve the conflict with one fresh fixer (§4a's brief);
    - gate: `studio-test <paths>`, the files the resolution touched, as §11 scopes it, up to three rounds;
    - green: commit `fix(sync): <summary>`, push, ledger `Synced: <summary>`, commit and push the ledger;
    - red after three rounds: ledger `Stop: sync repair red — <failing line>`, commit, do not push;
    - the next task's `Verify:` and the finish gate cover the rest.

    The `origin/<Target>` form is unchanged.
  - **execute §2** (`grep -n '^## 2. Who implements' …`): add a bullet:
    > Under a lane, when the session's start output has an `Other live runs` block (the peer-runs hook), copy that block verbatim into every implementer and fixer brief.
  - **brainstorm** (`grep -n 'Epic under a manifest' studios/game-dev/skills/brainstorm/SKILL.md`, line 213) and **plan** (`grep -n 'Invoked with an id\|Not a manifest story' studios/game-dev/skills/plan/SKILL.md`, lines 74 and 165): add a `<slug>/<id>` form, invoked as `/game-dev:brainstorm <slug>/<id>` or `/game-dev:plan <slug>/<id>`:
    - first find the checkout of `run/<slug>`: `git worktree list --porcelain`, the `worktree` whose `branch refs/heads/run/<slug>`;
    - when none holds it, stop with "no checkout holds run/<slug> — /omega:autopilot <slug> creates its run worktree";
    - enter it with execute's **Enter the feature checkout** procedure (`EnterWorktree path:`, else `cd`), and check it with `git rev-parse --show-toplevel`;
    - run `studio-state show` and print it;
    - then continue as the `<id>` form under that worktree's `.studio/run`, with every file path absolute under it.

    Then: "The bare `<id>` form keeps today's meaning in the current checkout." The `next` printing (§7 Gate, near brainstorm line 257) prints the `<slug>/<id>` form when it came from one.
  - **studio** (`grep -n 'Overnight run live' studios/game-dev/skills/studio/SKILL.md`, lines 18-22): the bullet becomes:
    > **Overnight run live:** `studio-overnight status` (exit 0) shows the live runs. Mention them in one line. A live run does not make the project busy: route as usual.

    Remove the `.studio/overnight.lock` path and "routes nothing else".
- [ ] **Step 4: Run** the Step 2 command. Expected: PASS. Then run `sh tests/studio_test.sh`. Expected: exit 0.
- [ ] **Step 5: Commit.** `docs(skills): sync repair form, peers brief rule, <slug>/<id> forms (#39)` with the trailers.

---

### Task 5: Autopilot — run worktrees, discovery lists, start, `off`, adopt forms

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L57-57, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L87-87, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L178-188, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L195-196, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L202-202, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L294-294, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L379-381
Review: final
Wave: 1
Touches: `shared/omega/skills/autopilot/SKILL.md`, `tests/omega_contracts/autopilot_contract.sh`

**Interfaces:** skill text only, pinned by `tests/omega_contracts/autopilot_contract.sh` (run by `tests/omega_test.sh`).

- [ ] **Step 1: Rewrite the contract first.**
  - Replace these assertions (D1). Find them with
    `grep -n 'switch this checkout\|a run is live: stop\|git switch run\|only after the switch\|Then, on .run' tests/omega_contracts/autopilot_contract.sh`:
    - L48 `switch this checkout to .<default>. first`;
    - L62 `.studio-overnight status. exits 0, a run is live: stop`;
    - L70 `git switch run/<slug>. when it already exists`;
    - L76 `Write it only after the switch to .run/<slug>.`;
    - L77 `Then, on .run/<slug>., write the lane count`.
  - Add these functions:
  - `test_autopilot_run_worktree`:
    - `git worktree add --no-track -b run/<slug> <root>/.claude/worktrees/run-<slug> origin/<default>`;
    - `git worktree add <path> run/<slug>`;
    - `Enter the feature checkout`;
    - `git rev-parse --show-toplevel`;
    - `studio-state init --local`;
    - `worktree_setup`;
    - `The main checkout's branch is never switched`;
    - the slug rules: `off`, `all-digit`;
    - the done-record archive `.studio/runs/<slug>.<utc ts>`;
    - the story-list refusal (`AC8 would refuse`, as the literal rule text "an id or branch another run uses").
  - `test_autopilot_discovery_lists_runs`:
    - `runs being planned`;
    - `started runs`;
    - one `AskUserQuestion` with each run and `new run`;
    - `/omega:autopilot <slug>` skips the question;
    - `A live run never stops discovery`.
  - `test_autopilot_start_from_run_worktree`:
    - `cd '<run worktree>' && '<abs>' start --detach <manifest>`;
    - the baseline `studio-test` in the run worktree after `worktree_setup`;
    - `git worktree remove <path>` once the run is `done`;
    - `nothing removes the worktree automatically`.
  - `test_autopilot_off_stop_rule`: `off` clears the mode, then a bare `studio-overnight stop` with one live run; with several, it lists them and names `stop --run <slug>` and `stop --all`.
  - `test_autopilot_adopt_slug_forms`: the adopt steps print `/game-dev:plan <slug>/<id>` and `/game-dev:brainstorm <slug>/<id>`.

  `test_autopilot_adopt_order` stays unchanged.
- [ ] **Step 2: Run it and see it fail.** `sh tests/omega_test.sh`. Expected: FAIL on the new functions.
- [ ] **Step 3: Edit `shared/omega/skills/autopilot/SKILL.md`.**
  - `off` (`grep -n '^`off`' …`, line 18): clear the mode, then run AC12's bare-stop rule.
  - Phase 1, step 1 **Discovery** (line 55):
    - drop the "a run is live: stop" sentence;
    - with no slug, list:
      - the **runs being planned**: run worktrees (porcelain `branch refs/heads/run/*`) whose `.studio/run` names a manifest with no `<root>/.studio/runs/<slug>/landed.tsv`;
      - the **started runs**: records without `done`, live or not, as `studio-overnight status` prints them;
    - ask one `AskUserQuestion` (each run, and "new run");
    - a run being planned resumes at step 2 from its run worktree, and a started run at step 4;
    - `/omega:autopilot <slug>` skips the question.
  - Replace the run-branch bullet (lines 71-72) with AC15's steps:
    1. check the slug (AC8: not `off`, not all digits, not used by a live or stopped run), and archive a done record with `mv <root>/.studio/runs/<slug> <root>/.studio/runs/<slug>.$(date -u +%Y%m%dT%H%M%SZ)` (D2);
    2. `git fetch origin`, then create the worktree with `git worktree add --no-track -b run/<slug> <root>/.claude/worktrees/run-<slug> origin/<default>`, or `git worktree add <path> run/<slug>` when the branch exists;
    3. enter it with **Enter the feature checkout** and check it with `git rev-parse --show-toplevel`;
    4. print the path;
    5. run `studio-state init --local`, then `worktree_setup` when configured;
    6. every later phase-1 step runs there: the lane count, the manifest, `.studio/run` and the commits. Paths are absolute under the run worktree, except half-done story worktrees (`<root>/.claude/worktrees/…`).

    "The main checkout's branch is never switched." Lines 67 and 76-77: the lane count is written in the run worktree.
  - The story-list question refuses an id or branch that another run uses (AC8).
  - Step 4: the baseline `studio-test` runs in the run worktree after `worktree_setup`.
  - Step 5 (line 157): `cd '<run worktree>' && '<abs>' start --detach <manifest>`. `<dir>` (line 52) becomes the run worktree. The report names `git worktree remove <path>` once `done`; nothing removes the worktree automatically.
  - Adopt step 1a.3 (`grep -n 'game-dev:plan <id>\|game-dev:brainstorm <id>' …`): print the `<slug>/<id>` forms.
- [ ] **Step 4: Run** `sh tests/omega_test.sh`. Expected: exit 0.
- [ ] **Step 5: Commit.** `docs(autopilot): plan and start runs from run worktrees (#39)` with the trailers.

---

### Task 6: `overnight-sessions.sh` — slots, FIFO queue, release, reclaim

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L243-251, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L303-303, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L319-319, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L360-367
Review: task
Wave: 2
Touches: `studios/game-dev/bin/overnight-sessions.sh`, `tests/overnight_sessions_test.sh`

**Interfaces** (sourced after `overnight-runs.sh`; the caller sets `STATE_ROOT`, `SESS_ME` (the lane's pid, or the runner's for a final unit), `SESS_RUN` (the run dir) and `SESS_START_CAP`):

```
sess_init                 SESS_DIR, SESS_MX; SESS_SLOT="" SESS_WAIT="" (no mkdir)
sess_cap                  max_sessions from <root>/.studio/config.json, else SESS_START_CAP, else 6 (D21)
sess_pid_is PID WORD      PID runs (not a zombie) and its ps args contain WORD
sess_owner_live FILE      lane pid is a live studio-overnight, or session pid a live claude
sess_live_count           live slots (owner checked; no reclaim)
sess_enqueue STORY UNIT   join the tail: SESS_WAIT=<dir>/wait/<key>-<SESS_ME>
sess_try UNIT             under the mutex: reclaim; oldest + below cap -> take; 0 with SESS_SLOT
sess_session PID          record the session pid in this lane's owner file
sess_release              owner-checked release under the mutex (every exit path)
sess_wait_cancel          leave the queue
sess_drop_owner PID       a dead lane's slots and wait entries (sweep)
```

- [ ] **Step 1: Write the failing suite** `tests/overnight_sessions_test.sh`. Use the same preamble as Task 3's suite (`live_dummy`, `dead_pid`, temp `HOME`), and source both libs:

```sh
. "$REPO_ROOT/studios/game-dev/bin/overnight-runs.sh"
. "$REPO_ROOT/studios/game-dev/bin/overnight-sessions.sh"
# proj NAME CAP — STATE_ROOT with config max_sessions CAP; sess_init.
proj() { STATE_ROOT="$TMP/$1"; mkdir -p "$STATE_ROOT/.studio"
  printf '{"overnight": {"max_sessions": %s}}\n' "$2" > "$STATE_ROOT/.studio/config.json"
  SESS_START_CAP=6; SESS_RUN="$TMP/run-$1"; sess_init; }
# as PID — act as lane PID (a fresh SESS_SLOT/SESS_WAIT per lane: save and restore around calls).
test_sess_fifo_oldest_waiter_only() {
  proj fifo 1; live_dummy; L1="$DUMMY"; live_dummy; L2="$DUMMY"; live_dummy; L3="$DUMMY"
  SESS_ME="$L1"; sess_enqueue S1 u1; sess_try u1; assert_eq 0 $? "first in line takes the one slot"; S_L1="$SESS_SLOT"
  SESS_ME="$L2"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S2 u2; W2="$SESS_WAIT"
  SESS_ME="$L3"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S3 u3; W3="$SESS_WAIT"
  SESS_ME="$L1"; SESS_SLOT="$S_L1"; sess_release
  SESS_ME="$L3"; SESS_WAIT="$W3"; sess_try u3; assert_eq 1 $? "a younger waiter never takes a free slot"
  SESS_ME="$L2"; SESS_WAIT="$W2"; sess_try u2; assert_eq 0 $? "the oldest waiter takes it"
  assert_eq "$L2" "$(runs_kv lane "$STATE_ROOT/.studio/sessions/$SESS_SLOT/owner")" "owner names the lane"
  assert_missing "$W2" "the taker left the queue"
}
test_sess_cap_respected() {
  proj cap 2; live_dummy; A="$DUMMY"; live_dummy; B="$DUMMY"; live_dummy; C="$DUMMY"
  for _l in "$A" "$B" "$C"; do SESS_ME="$_l"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; eval "R_$_l=\$?"; done
  eval "assert_eq 0 \$R_$A 'slot 1'"; eval "assert_eq 0 \$R_$B 'slot 2'"; eval "assert_eq 1 \$R_$C 'cap 2: the third waits'"
  assert_eq 2 "$(sess_live_count)" "two live"
}
test_sess_cap_lowered_no_new_take() {
  proj lower 3; live_dummy; A="$DUMMY"; live_dummy; B="$DUMMY"; live_dummy; C="$DUMMY"
  for _l in "$A" "$B"; do SESS_ME="$_l"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; done
  printf '{"overnight": {"max_sessions": 1}}\n' > "$STATE_ROOT/.studio/config.json"
  SESS_ME="$C"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u
  assert_eq 1 $? "live 2 > cap 1: no take (D21)"; assert_eq 2 "$(sess_live_count)" "live slots are never revoked"
}
test_sess_release_owner_checked() {
  proj late 1; live_dummy; A="$DUMMY"; live_dummy; B="$DUMMY"
  SESS_ME="$A"; sess_enqueue S u; sess_try u; SA="$SESS_SLOT"
  kill "$A"; wait "$A" 2>/dev/null                                 # A dies; B reclaims and takes the slot
  SESS_ME="$B"; SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; assert_eq 0 $? "reclaimed and retaken"
  SESS_ME="$A"; SESS_SLOT="$SA"; sess_release                     # a late release in A's name
  assert_eq "$B" "$(runs_kv lane "$STATE_ROOT/.studio/sessions/$SA/owner")" "a late release leaves the other lane's slot"
}
test_sess_reclaim_dead_owner_and_ownerless() {
  proj reclaim 1; dead_pid; mkdir -p "$STATE_ROOT/.studio/sessions/1"
  printf 'lane=%s\nsession=\nrun=x\nunit=u\n' "$DEAD" > "$STATE_ROOT/.studio/sessions/1/owner"
  live_dummy; SESS_ME="$DUMMY"; sess_enqueue S u; sess_try u; assert_eq 0 $? "a dead owner's slot is reclaimed by liveness"
  proj ownerless 1; mkdir -p "$STATE_ROOT/.studio/sessions/1"
  SESS_SLOT=""; SESS_WAIT=""; sess_enqueue S u; sess_try u; assert_eq 0 $? "a slot with no owner file is reclaimed (D20)"
}
test_sess_owner_live_by_session_pid() {
  proj sesslive 1; dead_pid; sh -c 'sleep 60; :' claude >/dev/null 2>&1 & CL=$!; DUMMIES="$DUMMIES $CL"
  mkdir -p "$STATE_ROOT/.studio/sessions/1"
  printf 'lane=%s\nsession=%s\nrun=x\nunit=u\n' "$DEAD" "$CL" > "$STATE_ROOT/.studio/sessions/1/owner"
  live_dummy; SESS_ME="$DUMMY"; sess_enqueue S u; sess_try u
  assert_eq 1 $? "a dead lane whose session still runs keeps its slot"
}
test_sess_reclaim_dead_waiter() {
  proj waiter 1; dead_pid; mkdir -p "$STATE_ROOT/.studio/sessions/wait"
  : > "$STATE_ROOT/.studio/sessions/wait/1000000000000000000-$DEAD"
  live_dummy; SESS_ME="$DUMMY"; sess_enqueue S u; sess_try u
  assert_eq 0 $? "a dead waiter at the head is dropped, the next one serves"
}
test_sess_wait_key_monotonic() {
  proj keys 1; live_dummy; SESS_ME="$DUMMY"
  sess_enqueue S u; K1="${SESS_WAIT##*/}"; SESS_WAIT=""; sess_enqueue S u; K2="${SESS_WAIT##*/}"
  assert_eq 19 "${#K1%-*}" "19-digit key (D3)"
  [ "${K2%-*}" -gt "${K1%-*}" ]; assert_eq 0 $? "strictly increasing within one second"
}
test_sess_drop_owner() {
  proj drop 2; live_dummy; A="$DUMMY"; SESS_ME="$A"; sess_enqueue S u; sess_try u; SESS_WAIT=""; sess_enqueue S u
  SESS_ME=$$; sess_drop_owner "$A"
  assert_eq 0 "$(sess_live_count)" "the dead lane's slot is gone"
  assert_eq "" "$(ls "$STATE_ROOT/.studio/sessions/wait" | grep -- "-$A\$")" "and its wait entry"
}
test_sess_cap_config_fallback() {
  proj fb 1; printf '{"overnight": {"max_sessions": "x"}}\n' > "$STATE_ROOT/.studio/config.json"; SESS_START_CAP=3
  assert_eq 3 "$(sess_cap)" "invalid at runtime: the start's value"
  printf '{"overnight": {"max_sessions": 9}}\n' > "$STATE_ROOT/.studio/config.json"
  assert_eq 3 "$(sess_cap)" "out of range: the start's value"
}
```
(Add `run_tests` with every function. Each test that kills a dummy waits for it. The suite's EXIT trap kills `$DUMMIES`.)

- [ ] **Step 2: Run it and see it fail.** `sh tests/overnight_sessions_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `studios/game-dev/bin/overnight-sessions.sh` (`chmod +x`):

```sh
#!/bin/sh
# overnight-sessions.sh — the project-wide session cap (#39 AC27): slots
# <root>/.studio/sessions/<n> (mkdir, n in 1..cap), a FIFO of waiters
# <root>/.studio/sessions/wait/<key>-<lane pid>, every change under
# <root>/.studio/sessions.mutex (never the gate mutex). Sourced after
# overnight-runs.sh. The caller sets STATE_ROOT, SESS_ME, SESS_RUN and
# SESS_START_CAP. A slot's owner file: lane= session= run= unit= (D20).

sess_init() { SESS_DIR="$STATE_ROOT/.studio/sessions"; SESS_MX="$STATE_ROOT/.studio/sessions.mutex"; SESS_SLOT=""; SESS_WAIT=""; }
sess_cap() {
  _sc="$(sed -n 's/.*"max_sessions"[[:space:]]*:[[:space:]]*\([^,}[:space:]]*\).*/\1/p' "$STATE_ROOT/.studio/config.json" 2>/dev/null | head -n 1)"
  case "$_sc" in ''|*[!0-9]*) _sc="${SESS_START_CAP:-6}" ;; esac
  { [ "$_sc" -ge 1 ] && [ "$_sc" -le 8 ]; } 2>/dev/null || _sc="${SESS_START_CAP:-6}"
  printf '%s\n' "$_sc"
}
sess_pid_is() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*|'') return 1 ;; esac
  ps -o args= -p "$1" 2>/dev/null | grep -q -- "$2"
}
sess_owner_live() { sess_pid_is "$(runs_kv lane "$1")" studio-overnight || sess_pid_is "$(runs_kv session "$1")" claude; }
sess_gone() { _sg="$SESS_DIR/.gone.${1##*/}.${SESS_ME:-$$}.$$"; mv "$1" "$_sg" 2>/dev/null && rm -rf "$_sg"; }
sess_live_count() {
  _sl=0
  for _s in "$SESS_DIR"/[0-9]*; do [ -d "$_s" ] && [ -f "$_s/owner" ] && sess_owner_live "$_s/owner" && _sl=$((_sl + 1)); done
  printf '%s\n' "$_sl"
}
# sess_reclaim — under the mutex: a slot with no owner file or a dead owner,
# and a wait entry whose lane is dead, go (AC27: liveness, never age).
sess_reclaim() {
  for _sr in "$SESS_DIR"/[0-9]*; do
    [ -d "$_sr" ] || continue
    { [ -f "$_sr/owner" ] && sess_owner_live "$_sr/owner"; } || sess_gone "$_sr"
  done
  for _sr in "$SESS_DIR"/wait/[0-9]*-[0-9]*; do
    [ -f "$_sr" ] || continue
    sess_pid_is "${_sr##*-}" studio-overnight || rm -f "$_sr"
  done
}
# sess_key — D3: epoch s × 10^9 bumped past the last key (under the mutex).
sess_key() {
  _sk="$(( $(date +%s) * 1000000000 ))"
  _skl="$(cat "$SESS_DIR/wait/.last" 2>/dev/null)"; case "$_skl" in ''|*[!0-9]*) _skl=0 ;; esac
  [ "$_sk" -gt "$_skl" ] || _sk=$((_skl + 1))
  printf '%s\n' "$_sk" > "$SESS_DIR/wait/.last"; printf '%s\n' "$_sk"
}
sess_enqueue() {
  mkdir -p "$SESS_DIR/wait" 2>/dev/null || return 1
  mx_take "$SESS_MX" "$SESS_ME" || return 1
  SESS_WAIT="$SESS_DIR/wait/$(sess_key)-$SESS_ME"
  printf 'lane=%s\nrun=%s\nstory=%s\nunit=%s\n' "$SESS_ME" "$SESS_RUN" "$1" "$2" > "$SESS_WAIT"
  mx_drop "$SESS_MX" "$SESS_ME"
}
sess_try() {
  mx_take "$SESS_MX" "$SESS_ME" || return 1
  sess_reclaim
  [ -z "$SESS_WAIT" ] || [ -f "$SESS_WAIT" ] || SESS_WAIT=""      # dropped by a sweep: re-queue
  _st_rc=1
  _st_head="$(ls "$SESS_DIR/wait" 2>/dev/null | grep -E '^[0-9]+-[0-9]+$' | sort | head -n 1)"
  if [ -n "$SESS_WAIT" ] && [ "$_st_head" = "${SESS_WAIT##*/}" ]; then
    _st_cap="$(sess_cap)"; _st_live=0
    for _st_s in "$SESS_DIR"/[0-9]*; do [ -d "$_st_s" ] && _st_live=$((_st_live + 1)); done
    _st_n=1
    while [ "$_st_live" -lt "$_st_cap" ] && [ "$_st_n" -le "$_st_cap" ]; do
      if mkdir "$SESS_DIR/$_st_n" 2>/dev/null; then
        printf 'lane=%s\nsession=\nrun=%s\nunit=%s\n' "$SESS_ME" "$SESS_RUN" "$1" > "$SESS_DIR/$_st_n/owner"
        rm -f "$SESS_WAIT"; SESS_WAIT=""; SESS_SLOT="$_st_n"; _st_rc=0; break
      fi
      _st_n=$((_st_n + 1))
    done
  fi
  mx_drop "$SESS_MX" "$SESS_ME"
  return "$_st_rc"
}
sess_session() {
  [ -n "${SESS_SLOT:-}" ] || return 0
  _ss="$SESS_DIR/$SESS_SLOT/owner"
  [ "$(runs_kv lane "$_ss")" = "$SESS_ME" ] || return 0
  sed "s/^session=.*/session=$1/" "$_ss" > "$_ss.$$" && mv -f "$_ss.$$" "$_ss"
}
sess_release() {
  [ -n "${SESS_SLOT:-}" ] || return 0
  _sr_d="$SESS_DIR/$SESS_SLOT"; SESS_SLOT=""
  _sr_m=0; ! mx_take "$SESS_MX" "$SESS_ME" || _sr_m=1
  [ "$(runs_kv lane "$_sr_d/owner")" != "$SESS_ME" ] || sess_gone "$_sr_d"
  [ "$_sr_m" = 0 ] || mx_drop "$SESS_MX" "$SESS_ME"
}
sess_wait_cancel() { [ -z "${SESS_WAIT:-}" ] || rm -f "$SESS_WAIT"; SESS_WAIT=""; }
sess_drop_owner() {
  [ -n "$1" ] || return 0
  _sd_me="${SESS_ME:-$$}"; _sd_m=0; ! mx_take "$SESS_MX" "$_sd_me" || _sd_m=1
  for _sd in "$SESS_DIR"/[0-9]*; do
    [ -d "$_sd" ] && [ "$(runs_kv lane "$_sd/owner")" = "$1" ] && sess_gone "$_sd"
  done
  rm -f "$SESS_DIR"/wait/[0-9]*-"$1"
  [ "$_sd_m" = 0 ] || mx_drop "$SESS_MX" "$_sd_me"
}
```
- [ ] **Step 4: Run the suite.** `sh tests/overnight_sessions_test.sh`. Expected: PASS. Then `sh tests/studio_test.sh`. Expected: exit 0.
- [ ] **Step 5: Commit.** `feat(studio): overnight-sessions.sh — FIFO session slots (#39)` with the trailers.

---

### Task 7: Per-run locks, run identity and the status loop

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L137-144, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L156-159, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L163-163, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L257-261, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L278-283, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L289-290, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L344-349, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L358-358
Review: task
Wave: 2
Touches: `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-lanes.sh`, `studios/game-dev/bin/overnight-channel.sh`, `tests/overnight_test.sh`, `tests/overnight_lanes_test.sh`

**Interfaces:**
- Produces:
  - **Lock and identity:**
    - `LOCK` and `STOP_FILE` are per run for manifest runs (`run_paths SLUG`);
    - `take_lock` writes `start=`;
    - `acquire_run_lock` calls `run_excludes`, the `STUDIO_OVERNIGHT_LOCK_HOOK` hook, `run_populate`, and `lock_recheck` under `runs.mutex`;
    - `lock_lost WHY`;
    - `unlock` is owner-checked;
    - `reg_write` keeps live siblings;
    - `STUDIO_START_DIR` is exported to every unit.
  - **Status:**
    - `project_status` loops over `runs_live`, with D16 headers;
    - `status --run <sel>` and `no live run <sel>`;
    - the dead-lock reap (D12, AC31).
  - **Stop and channel:**
    - bare `stop` with one live run writes that run's flag;
    - `chan_find_run` (in a project) takes its run from `runs_live`, with `--run` matched by `runs_match`;
    - `chan_stop_run` writes the run's own flag (D5).
  - **Tests:** the test helpers `fake_mrun` (overnight_test.sh), and `lanes_add_run`, `run_lanes_in`, `bg_lanes`, `bg_wait` (lanes suite).
- Consumes:
  - from T3: `runs_live`, `runs_match`, `runs_stop_of`, `runs_start_dir`, `mx_take`, `mx_drop`;
  - from T2: `studio-state init --local`, used in the fixture.

- [ ] **Step 1: Test helpers.**

  In `tests/overnight_test.sh`, after `fake_run` (`grep -n '^fake_run()' tests/overnight_test.sh`):
```sh
# fake_mrun SLUG [ID=RECORD]… — a live manifest run with a per-run lock
# (#39): <root>/.studio/runs/SLUG/lock (pid, run, started, start=$P), its run
# dir FR_DIR ($P/.studio/reports/overnight-SLUG-20261004-210000) with
# manifest.md (`# Run: SLUG`), channel, rows.tsv and stories/, and a registry
# entry. FR_PID is its live_dummy; FR_LOCK the lock.
fake_mrun() {
  _fm_s="$1"; shift
  FR_DIR="$P/.studio/reports/overnight-$_fm_s-20261004-210000"; mkdir -p "$FR_DIR/stories" "$P/.studio/runs/$_fm_s"
  printf '# Run: %s\n\nMode: integration\nTarget: integration/%s\n' "$_fm_s" "$_fm_s" > "$FR_DIR/manifest.md"
  printf 'hold_minutes=%s\ndirective_chars=%s\n' "${FR_HOLD:-480}" "${FR_CHARS:-4000}" > "$FR_DIR/channel"
  live_dummy; FR_PID="$DUMMY"; FR_LOCK="$P/.studio/runs/$_fm_s/lock"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T21:00:0%s\nstart=%s\n' "$FR_PID" "$FR_DIR" "${FR_SEQ:-0}" "$P" > "$FR_LOCK"
  mkdir -p "$HOME/.claude-gamedev/runs"
  printf 'root=%s\nstart=%s\nrun=%s\npid=%s\nstarted=2026-10-04T21:00:00Z\n' "$P" "$P" "$FR_DIR" "$FR_PID" \
    > "$HOME/.claude-gamedev/runs/overnight-$_fm_s-$FR_PID"
  : > "$FR_DIR/rows.tsv"
  for _fm_r in "$@"; do
    _fm_id="${_fm_r%%=*}"
    printf '%s\t%s-b\t%s\t-\t-\t\n' "$_fm_id" "$_fm_id" "$_fm_id" >> "$FR_DIR/rows.tsv"
    printf '%s\n' "${_fm_r#*=}" > "$FR_DIR/stories/$_fm_id"
    ( cd "$P" && STUDIO_STORY="$_fm_id" && export STUDIO_STORY && sh "$STATE_BIN" init && sh "$STATE_BIN" ledger "plan approved x" ) >/dev/null 2>&1
  done
  ( cd "$P" && git add -A .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm "stories $_fm_s" ) >/dev/null 2>&1
}
```
  `fake_run_end PID` also removes `$P/.studio/runs/*/lock` whose `pid=` is PID.

  In `tests/overnight_lanes_test.sh`, after `run_lanes` (`grep -n '^run_lanes()' tests/overnight_lanes_test.sh`):
```sh
# lanes_add_run SLUG MODE ROW… — a second run in the current fixture $P
# (after lanes_fixture): run worktree RW=$P/.claude/worktrees/run-SLUG on
# run/SLUG from origin/main (studio-state init --local), .studio/config.json
# from $LANES_CONFIG (default {}; MODE direct adds scripts/merge.sh and
# merge_command), its own spec, one plan per story, story state at <root>
# (stage plan, task 0/1, approved and swept), manifest RMF=docs/runs/SLUG.md,
# all committed and pushed; integration/SLUG on origin for MODE integration.
# Story ids must not clash with $P's run (A, B, …): use S1, S2, ….
lanes_add_run() {
  _ar_s="$1"; _ar_m="$2"; shift 2
  RW="$P/.claude/worktrees/run-$_ar_s"; RMF="docs/runs/$_ar_s.md"; export RW RMF
  _ar_cfg="${LANES_CONFIG:-}"; [ -n "$_ar_cfg" ] || _ar_cfg='{}'
  _ar_spec="docs/game-dev/specs/2026-10-01-$_ar_s.md"
  ( set -e
    cd "$P"; git fetch -q origin
    grep -qxF .claude/worktrees/ "$(git rev-parse --git-common-dir)/info/exclude" 2>/dev/null \
      || printf '.claude/worktrees/\n' >> "$(git rev-parse --git-common-dir)/info/exclude"
    git worktree add -q --no-track -b "run/$_ar_s" "$RW" origin/main
    cd "$RW"; sh "$STATE_BIN" init --local >/dev/null
    mkdir -p docs/game-dev/specs docs/game-dev/plans docs/runs .studio
    if [ "$_ar_m" = direct ]; then
      mkdir -p scripts && printf '#!/bin/sh\nexec sh %s "$@"\n' "'$FAKE/merge-stub'" > scripts/merge.sh && chmod +x scripts/merge.sh
      _ar_cfg="$(printf '%s' "$_ar_cfg" | sed 's/^{ *}$/{"overnight": {}}/; s/"overnight": {/"overnight": {"merge_command": "scripts\/merge.sh <pr>", /; s/, }/}/')"
    fi
    printf '%s\n' "$_ar_cfg" > .studio/config.json
    { printf '# Spec: %s\n\n## Stories\n\n| Story | Summary |\n|-------|---------|\n' "$_ar_s"
      for _r in "$@"; do printf '| %s | story %s |\n' "${_r%%:*}" "${_r%%:*}"; done; } > "$_ar_spec"
    for _r in "$@"; do
      _id="${_r%%:*}"; _plan="docs/game-dev/plans/2026-10-01-$_id.md"
      printf '# Plan: %s\n\nStory: %s\n\n## Decisions\n\n- none\n\n### Task 1: t\n\nSpec: %s:L1-2\nFiles: `%s-T1.txt`\n\n### Task 2: u\n\nSpec: %s:L1-2\nFiles: `%s-T2.txt`\n' \
        "$_id" "$_id" "$_ar_spec" "$_id" "$_ar_spec" "$_id" > "$_plan"
      STUDIO_STORY="$_id"; export STUDIO_STORY
      sh "$STATE_BIN" init >/dev/null; sh "$STATE_BIN" set spec "$_ar_spec"; sh "$STATE_BIN" set plan "$_plan"
      sh "$STATE_BIN" ledger "spec approved $_ar_spec"; sh "$STATE_BIN" ledger "plan approved $_plan"
      sh "$STATE_BIN" ledger "Decisions swept $_id"; sh "$STATE_BIN" set stage plan; sh "$STATE_BIN" set task 0/2
      unset STUDIO_STORY
    done
    git add -A && git commit -q -m docs && git push -q origin "run/$_ar_s"
    _docs="$(git rev-parse HEAD)"
    if [ "$_ar_m" = integration ]; then _t="integration/$_ar_s"; else _t=main; fi
    { printf '# Run: %s\n\nMode: %s\nTarget: %s\nDocs: %s\nGoal: the %s goal\n\n' "$_ar_s" "$_ar_m" "$_t" "$_docs" "$_ar_s"
      printf '| Story | Branch | Ticket | Spec | Plan | Depends on |\n|-------|--------|--------|------|------|------------|\n'
      for _r in "$@"; do _id="${_r%%:*}"
        printf '| %s | %s-b | %s | %s | docs/game-dev/plans/2026-10-01-%s.md | %s |\n' "$_id" "$_id" "$_id" "$_ar_spec" "$_id" "$(printf '%s' "${_r#*:}" | sed 's/,/, /g')"
      done; } > "$RMF"
    printf '%s\n' "$RMF" > .studio/run
    git add -A && git commit -q -m manifest && git push -q origin "run/$_ar_s"
    [ "$_ar_m" != integration ] || git push -q origin "origin/main:refs/heads/integration/$_ar_s"
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "lanes_add_run $_ar_s: setup failed"; }
  unset LANES_CONFIG
}
# run_lanes_in DIR ARGS — run_lanes from DIR (same LS_* results and watchdog).
run_lanes_in() { _rli="$P"; P="$1"; shift; run_lanes "$@"; P="$_rli"; }
# bg_lanes NAME DIR ARGS — `studio-overnight ARGS` in DIR in the background:
# $TMP/bg-NAME.{pid,out,err}. bg_wait NAME — wait up to 120 s; BG_STATUS.
bg_lanes() { _bn="$1"; _bd="$2"; shift 2
  ( cd "$_bd" && exec sh "$RUNNER" "$@" ) > "$TMP/bg-$_bn.out" 2> "$TMP/bg-$_bn.err" < /dev/null &
  echo "$!" > "$TMP/bg-$_bn.pid"; }
bg_wait() { _bp="$(cat "$TMP/bg-$1.pid")"; _bi=0
  while kill -0 "$_bp" 2>/dev/null && [ "$_bi" -lt 1200 ]; do sleep 0.1; _bi=$((_bi + 1)); done
  if kill -0 "$_bp" 2>/dev/null; then kill -TERM "$_bp"; TESTS_RUN=$((TESTS_RUN + 1)); _fail "bg run $1 ran past 120 s"; fi
  BG_STATUS=0; wait "$_bp" 2>/dev/null || BG_STATUS=$?; }
```
  (The config `sed` for direct mode is a convenience; the implementer may build the JSON with an explicit `printf` instead, for each config the tests use.)

- [ ] **Step 2: Write the failing tests.**

  In `tests/overnight_lanes_test.sh`; add every name to `run_tests`:
```sh
test_lanes_per_run_lock_paths() {
  lanes_fixture perrun integration A:-
  printf 'sleep 3\n' > "$SCEN/A"
  bg_lanes pr "$P" start "$MFP"
  _i=0; while [ ! -f "$P/.studio/runs/demo/lock" ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_file "$P/.studio/runs/demo/lock" "the manifest run's lock is .studio/runs/<slug>/lock"
  assert_contains "$P/.studio/runs/demo/lock" "^start=$P\$" "it records the start dir"
  assert_missing "$P/.studio/overnight.lock" "no project-wide lock"
  ( cd "$P" && sh "$RUNNER" stop ) > "$TMP/out" 2>&1
  assert_file "$P/.studio/runs/demo/stop" "bare stop with one live run writes its own flag"
  bg_wait pr
  assert_missing "$P/.studio/runs/demo/lock" "unlocked at the end"
  assert_missing "$P/.studio/runs/demo/stop" "and its stop flag removed"
}
test_lanes_excludes_before_lock() {
  lanes_fixture excl integration A:-
  _ex="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  STUDIO_OVERNIGHT_LOCK_HOOK="cp '$_ex' '$TMP/excl.at-lock'"; export STUDIO_OVERNIGHT_LOCK_HOOK
  run_lanes start "$MFP"; unset STUDIO_OVERNIGHT_LOCK_HOOK
  for _e in .studio/runs/ .studio/sessions/ .studio/runs.mutex .studio/sessions.mutex .studio/overnight.lock .studio/overnight.stop .claude/worktrees/; do
    assert_contains "$TMP/excl.at-lock" "^$(printf '%s' "$_e" | sed 's/\./\\./g')\$" "$_e excluded before the lock (D6)"
  done
}
test_lanes_two_runs_each_own_lock() {
  lanes_fixture two integration A:-
  lanes_add_run alpha integration S1:-
  printf 'sleep 3\n' > "$SCEN/A"; printf 'sleep 3\n' > "$SCEN/S1"
  bg_lanes demo "$P" start "$MFP"; bg_lanes alpha "$RW" start "$RMF"
  sleep 1
  assert_file "$P/.studio/runs/demo/lock" "demo holds its lock"
  assert_file "$P/.studio/runs/alpha/lock" "alpha holds its own"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1; _st=$?
  assert_eq 0 "$_st" "status exits 0 with runs live"
  assert_contains "$TMP/st.out" '^== alpha (manifest, pid [0-9]*) — ' "a headed block per run (D16)"
  assert_contains "$TMP/st.out" '^== demo (manifest, pid [0-9]*) — ' "both"
  ( cd "$P" && sh "$RUNNER" status --run alpha ) > "$TMP/st1.out" 2>&1
  assert_not_contains "$TMP/st1.out" '^== ' "status --run prints one block, no header"
  assert_contains "$TMP/st1.out" "run: .*overnight-alpha-" "alpha's block"
  bg_wait demo; bg_wait alpha
  assert_eq 0 "$BG_STATUS" "alpha ran to its end beside demo"
  assert_contains "$P/.studio/runs/alpha/landed.tsv" '^S1	' "and landed S1"
}
test_lanes_status_run_not_live() {
  lanes_fixture nolive integration A:-
  ( cd "$P" && sh "$RUNNER" status --run ghost ) > "$TMP/out" 2>&1; _st=$?
  assert_eq 1 "$_st" "status --run <slug> exits 1 when that run is not live"
  assert_contains "$TMP/out" '^no live run ghost$' "the fixed text"
}
test_lanes_manifest_refuses_live_single() {
  lanes_fixture msingle integration A:-
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T21:00:00Z\n' "$_d" "$P/.studio/reports/overnight-20261004-210000" > "$P/.studio/overnight.lock"
  run_lanes start "$MFP"
  kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$P/.studio/overnight.lock"
  assert_eq 2 "$LS_STATUS" "a manifest start refuses while a single-plan run is live (AC5)"
  assert_contains "$LS_ERR" "a run is live" "names it"
}
test_lanes_lock_race_single_vs_manifest() {
  lanes_fixture race integration A:-
  printf 'sleep 2\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_LOCK_HOOK='sleep 2'; export STUDIO_OVERNIGHT_LOCK_HOOK
  bg_lanes m "$P" start "$MFP"; unset STUDIO_OVERNIGHT_LOCK_HOOK
  sleep 0.5
  # The single-plan start passed its preflight before the manifest run locked; the re-check catches it.
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T21:00:00Z\n' "$_d" "$P/.studio/reports/overnight-20261004-210000" > "$P/.studio/overnight.lock"
  bg_wait m; kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$P/.studio/overnight.lock"
  assert_eq 2 "$BG_STATUS" "the manifest start that re-checks after a single-plan lock appears loses"
  assert_missing "$P/.studio/runs/demo/lock" "the loser leaves no lock"
  assert_eq "" "$(ls -d "$P"/.studio/reports/overnight-demo-* 2>/dev/null)" "and no run dir"
}
test_lanes_reg_write_keeps_live_sibling() {
  lanes_fixture reg integration A:-
  mkdir -p "$HOME/.claude-gamedev/runs"
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'root=%s\nstart=%s\nrun=/x/overnight-sib\npid=%s\n' "$P" "$P" "$_d" > "$HOME/.claude-gamedev/runs/overnight-sib-$_d"
  printf 'root=%s\nstart=%s\nrun=/x/overnight-dead\npid=999999\n' "$P" "$P" > "$HOME/.claude-gamedev/runs/overnight-dead-999999"
  run_lanes start "$MFP"
  assert_file "$HOME/.claude-gamedev/runs/overnight-sib-$_d" "a live sibling's entry is kept (AC6)"
  assert_missing "$HOME/.claude-gamedev/runs/overnight-dead-999999" "a dead one is dropped"
  kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$HOME"/.claude-gamedev/runs/overnight-sib-*
}
test_lanes_detach_with_other_run_live() {
  lanes_fixture det integration A:-
  lanes_add_run alpha integration S1:-
  printf 'sleep 4\n' > "$SCEN/S1"; bg_lanes alpha "$RW" start "$RMF"; sleep 1
  printf 'hang\n' > "$SCEN/A"
  run_lanes start --detach "$MFP"
  assert_eq 0 "$LS_STATUS" "detach succeeds with another run live (waits on its own lock and status --run)"
  assert_contains "$LS_OUT" "^detached: pid " "detached"
  detach_stop; bg_wait alpha
}
test_lanes_units_get_start_dir() {
  lanes_fixture sdenv integration A:-
  lanes_add_run alpha integration S1:-
  run_lanes_in "$RW" start "$RMF"
  _n="$(grep -l '^S1$' "$CALLS"/*.story | head -n 1)"; _n="${_n%.story}"
  assert_contains "$_n.fullenv" "^STUDIO_START_DIR=$RW\$" "every unit gets STUDIO_START_DIR (AC30)"
}
test_lanes_reap_resume_line_run_worktree() {
  lanes_fixture reap integration A:-
  lanes_add_run alpha integration S1:-
  printf 'hang\n' > "$SCEN/S1"; bg_lanes alpha "$RW" start "$RMF"; sleep 2
  _rp="$(sed -n 's/^pid=//p' "$P/.studio/runs/alpha/lock")"
  pkill -KILL -P "$_rp" 2>/dev/null; kill -KILL "$_rp"; bg_wait alpha
  pkill -KILL -f "$CALLS" 2>/dev/null; sleep 1
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/out" 2>&1
  _rd="$(ls -d "$P"/.studio/reports/overnight-alpha-* | tail -n 1)"
  assert_file "$_rd/report.md" "status from the main checkout reaped the dead run"
  assert_contains "$_rd/report.md" "^cd '$RW' && " "its Resume line changes into the run worktree (AC7)"
}
test_lanes_old_lock_counts_live() {
  lanes_fixture oldlive integration A:-
  _od="$P/.studio/reports/overnight-old-20261003-210000"; mkdir -p "$_od"; printf '# Run: old\n' > "$_od/manifest.md"
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'pid=%s\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$_d" "$_od" > "$P/.studio/overnight.lock"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/out" 2>&1; _st=$?
  kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$P/.studio/overnight.lock"
  assert_eq 0 "$_st" "an old-style manifest run on overnight.lock is live (AC31)"
}
test_lanes_old_lock_reaped_by_start() {
  lanes_fixture oldreap integration A:-
  _od="$P/.studio/reports/overnight-old-20261003-210000"; mkdir -p "$_od/stories" "$_od/lanes"
  printf '# Run: old\n\nMode: integration\nTarget: integration/old\n' > "$_od/manifest.md"; : > "$_od/rows.tsv"; : > "$_od/chains"
  printf 'pid=999999\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$_od" > "$P/.studio/overnight.lock"
  run_lanes start "$MFP"
  assert_file "$_od/report.md" "start reaps a dead old-style manifest lock (AC31)"
  assert_eq 0 "$LS_STATUS" "and runs"
}
```

  Update these existing lanes tests (D1); relocate them with `grep -n 'overnight.stop\|overnight.lock' tests/overnight_lanes_test.sh`:
  - ~1675 and ~1689 write `$P/.studio/runs/demo/stop`;
  - `detach_stop` (~1877) waits on `$P/.studio/runs/demo/lock`;
  - ~1938 asserts `$P/.studio/runs/demo/lock`;
  - `test_lanes_chain_rule` also asserts `assert_missing "$P/.studio/runs/demo/lock"`.

  In `tests/overnight_test.sh`, add:
```sh
test_verbs_per_run_channel_and_stop_run() {
  fixture perrun; FR_SEQ=1; fake_mrun alpha S1=running
  verb say S1 hello
  assert_eq 0 "$V_STATUS" "say finds the per-run run $(cat "$V_ERR")"
  verb stop --run alpha
  assert_file "$P/.studio/runs/alpha/stop" "stop --run writes the run's own flag (D5)"
  assert_missing "$P/.studio/overnight.stop" "never the project-wide one"
  fake_run_end
}
# AC5: a single-plan start refuses while a manifest run holds a per-run lock
# (modelled on test_overnight_lock; the single-plan fixture passes every
# earlier preflight check).
test_overnight_lock_refuses_live_manifest() {
  fixture smani; fake_mrun alpha S1=running
  run_start
  assert_eq 2 "$RS_STATUS" "a single-plan start refuses while a manifest run is live"
  assert_contains "$RS_ERR" "alpha" "names the live run"
  assert_contains "$RS_ERR" "pid $FR_PID" "and its pid"
  assert_eq 0 "$(calls)" "no session"
  assert_missing "$P/.studio/overnight.lock" "no lock left behind"
  fake_run_end
}
```
  `test_verbs_run_pinning` stays unchanged: it uses an old-style lock, so it
  still asserts `.studio/overnight.stop` (D5).

- [ ] **Step 3: Run them and see them fail.**
  `TESTS_ONLY="test_lanes_per_run_lock_paths test_lanes_two_runs_each_own_lock test_lanes_lock_race_single_vs_manifest" sh tests/overnight_lanes_test.sh`
  and `TESTS_ONLY=test_verbs_per_run_channel_and_stop_run sh tests/overnight_test.sh`. Expected: FAIL.
- [ ] **Step 4: Implement in SO.**
  - Source the lib next to the channel (`grep -n '^\. "\$SELF_DIR/overnight-channel.sh"' "$SO"`): `. "$SELF_DIR/overnight-runs.sh"`. It must be sourced before the dispatch and before `cmd_start`, so put it right after the globals block (line ~385).
  - `take_lock`: `printf 'pid=%s\nrun=%s\nstarted=%s\nstart=%s\n' "$$" "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$START_DIR"`.
  - `run_excludes` (new, D6): it sets `_excl` the way `run_setup` does today and appends the seven entries idempotently. `run_setup` calls it in place of its loop, and `lanes_run`'s two `grep -qxF … >> "$_excl"` lines go.
  - `lock_recheck` (SO default, single-plan):
    ```sh
    # lock_recheck — after take_lock, under runs.mutex (D8): 0 when this start
    # may run; 1 with RECHECK_WHY. A single-plan run excludes every other run.
    lock_recheck() {
      _lc="$(runs_live "$STATE_ROOT" | awk -F'\t' -v me="$LOCK" '$7 != me' | head -n 1)"
      [ -n "$_lc" ] || return 0
      RECHECK_WHY="a run is live: $(printf '%s\n' "$_lc" | awk -F'\t' '{ print ($2 == "-" ? "single-plan" : $2) " (" $5 ", pid " $4 ")" }') — $(sq "$SELF_ABS") status"
      return 1
    }
    run_populate() { :; }   # overnight-lanes.sh fills the run dir before the re-check (D9)
    # lock_lost WHY — this start lost: its lock, run dir and empty record dir go, the mutex is dropped, exit 2.
    lock_lost() {
      [ "$(lock_pid)" != "$$" ] || rm -f "$LOCK"
      rm -rf "$RUN_DIR"
      [ "$LOCK" = "$STATE_ROOT/.studio/overnight.lock" ] || rmdir "$(dirname "$LOCK")" 2>/dev/null
      mx_drop "$STATE_ROOT/.studio/runs.mutex" "$$"
      say "$1"; exit 2
    }
    ```
  - The new `acquire_run_lock` tail. The stale reclaim at the top is unchanged:
    ```sh
      run_excludes
      rm -f "$STOP_FILE"
      mkdir -p "$(dirname "$LOCK")"
      # Test hook (D10): runs after the preflight, just before the lock is taken.
      [ -z "${STUDIO_OVERNIGHT_LOCK_HOOK:-}" ] || eval "$STUDIO_OVERNIGHT_LOCK_HOOK"
      take_lock "$RUN_DIR" || { say "lock taken by another start"; exit 2; }
      mkdir -p "$RUN_DIR" || { rm -f "$LOCK"; say "cannot create $RUN_DIR"; exit 2; }
      run_populate || lock_lost "cannot populate $RUN_DIR"
      # AC8/AC5 re-check (D8, D9): the lock first, so of two starts the later re-check sees the earlier.
      mx_take "$STATE_ROOT/.studio/runs.mutex" "$$" || lock_lost "$STATE_ROOT/.studio/runs.mutex is busy — start again"
      lock_recheck || lock_lost "$RECHECK_WHY"
      mx_drop "$STATE_ROOT/.studio/runs.mutex" "$$"
      reg_write
      say "run $RUN_DIR started (pid $$) — watch: … · status: … · stop: $(sq "$SELF_ABS") stop${RUN_SLUG:+ --run $RUN_SLUG}"
    ```
  - `unlock`: `[ "$(lock_pid)" != "$$" ] || rm -f "$LOCK"; rm -f "$STOP_FILE"` (D11).
  - `reg_write`: `… && [ "$(reg_get root "$_rw")" = "$STATE_ROOT" ] && ! reg_live "$_rw" && rm -f "$_rw"`.
  - `start_session`: export `STUDIO_START_DIR="$START_DIR"` with the other exports (D42).
  - `preflight`: the `if lock_live` refusal stays (it covers AC5's manifest side and AC31). A single-plan preflight also refuses when `runs_live "$STATE_ROOT"` prints any line, with the same text as `lock_recheck`.
  - `detach_start`: after the dry run, validate `_dslug` (as `mf_check` does), then set
    `LOCK="$STATE_ROOT/.studio/runs/$_dslug/lock"`. The status probe becomes
    `sh "$SELF_ABS" status --run "$_dslug"`. The echo reads `watch: … watch --run <slug> · status: … status --run <slug>`.
  - `project_status`, rewritten as a loop:
    ```sh
    project_status() {
      status_reap_dead                      # D12/AC31: every dead lock whose run dir has manifest.md and no report.md
      _ps_all="$(runs_live "$STATE_ROOT")"
      if [ -n "${RUN_SEL:-}" ]; then
        _ps_all="$(printf '%s\n' "$_ps_all" | runs_match "$RUN_SEL")"
        [ -n "$_ps_all" ] || { printf 'no live run %s\n' "$RUN_SEL"; return 1; }
      fi
      if [ -n "$_ps_all" ]; then
        _ps_n="$(printf '%s\n' "$_ps_all" | grep -c .)"
        printf '%s\n' "$_ps_all" | while IFS="$(printf '\t')" read -r _ps_t _ps_s _ps_k _ps_p _ps_d _ps_sd _ps_l; do
          if [ "$_ps_n" -gt 1 ]; then printf '\n== %s (%s, pid %s) — %s\n' "$_ps_s" "$_ps_k" "$_ps_p" "$_ps_d"; fi
          ( LOCK="$_ps_l"; START_DIR="${_ps_sd:-$START_DIR}"
            if [ "$_ps_k" = manifest ]; then . "$SELF_DIR/overnight-lanes.sh"; lanes_status "$_ps_d" live
            else single_status "$_ps_d"; fi )
        done
        return 0
      fi
      … today's "no live run" path (unchanged: the lock's or the newest run dir) …
    }
    ```
    `single_status DIR` is today's single-plan live block, moved into a function
    unchanged. The first header's leading blank line is dropped: print the blank
    line only before the second and later blocks. `status_reap_dead` loops over
    `.studio/runs/*/lock` and `.studio/overnight.lock`. For a lock that is not
    live, whose `run=` dir has `manifest.md` and no `report.md`, it reaps
    exactly as `lanes_reap_stale` does, in a subshell with `LOCK` set to it and
    `START_DIR` from `runs_start_dir`.
  - Dispatch:
    - `status` accepts `--run <sel>` (sets `RUN_SEL`), as well as `''` and `--follow`.
    - `stop` with no argument: one live run (`runs_live`) gets `: > "$(runs_stop_of <its lock>)"` and today's message. No live run gets today's message. Two or more live runs keep today's single-lock behaviour until Task 10, so write the oldest run's flag and leave a `# T10` comment.
- [ ] **Step 5: Implement in LN.**
  - `run_paths SLUG`: `LOCK="$STATE_ROOT/.studio/runs/$1/lock"; STOP_FILE="$STATE_ROOT/.studio/runs/$1/stop"; RUN_SLUG="$1"`. In `lanes_start` it runs right after `[ "$FAILED" -eq 0 ] || exit 2`, so the slug is already valid.
  - `run_populate` (LN redefinition) holds what `lanes_run` does today between `acquire_run_lock` and `printf … manifest.path`: the `mkdir -p` of claims, stories and lanes, and the three `cp`. Its failure path is now `lock_lost`.
  - `lock_recheck` (LN redefinition, Task 7 part): refuse a live single-plan run. That is a `runs_live` line of kind `single`, other than this lock, refused with today's single-plan text. Task 11 extends it.
  - `lanes_reap_stale` reads the per-run `LOCK` (after `run_paths`). After it, the same reap runs for a dead `.studio/overnight.lock` whose run dir has `manifest.md` (`lanes_reap_old`), and `START_DIR` comes from `runs_start_dir` in both subshells (D12).
  - `lanes_load_run`: unchanged (it is passed `RUN_DIR`).
  - `lanes_status DIR live`: `pid: $(lock_pid)` now reads the per-block `LOCK`. No change, and it is verified by `test_lanes_two_runs_each_own_lock`.
- [ ] **Step 6: Implement in the channel.** `chan_find_run`'s in-project branch:
  ```sh
  _cf_live="$(runs_live "$STATE_ROOT")"
  if [ -n "$A_RUN" ]; then
    _cf_l="$(printf '%s\n' "$_cf_live" | runs_match "$A_RUN")"
    [ -n "$_cf_l" ] || chan_fail 1 "run $A_RUN is not live"
  else
    [ -n "$_cf_live" ] || chan_fail 1 "no live run in $STATE_ROOT"
    _cf_l="$(printf '%s\n' "$_cf_live" | head -n 1)"     # T10: AC13's resolution
  fi
  IFS="$(printf '\t')" read -r _ _ _ CH_PID CH_RUN _cf_sd CH_LOCK <<EOF
  $_cf_l
  EOF
  CH_ROOT="$STATE_ROOT"; CH_START="${_cf_sd:-$START_DIR}"
  ```
  `chan_stop_run` writes `$(runs_stop_of "$CH_LOCK")`. Outside a project
  (registry), `CH_LOCK` is found with `runs_live "$CH_ROOT" | runs_match "${CH_RUN##*/}"`,
  falling back to `$CH_ROOT/.studio/overnight.stop` when there is no match.
- [ ] **Step 7: Run the tests.** Run the Step 3 commands. Expected: PASS. Then run the whole affected suites: `sh tests/overnight_test.sh`, `sh tests/overnight_lanes_test.sh`, `sh tests/overnight_progress_test.sh`, `sh tests/studio_adopt_test.sh`, `sh tests/hook_test.sh`. Expected: exit 0 each.
- [ ] **Step 8: Commit.** `feat(overnight): per-run locks, run identity, status per run (#39)` with the trailers.

---
### Task 8: `studio-peers` and the `peer-runs.sh` hook

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L206-215, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L289-289, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L305-305, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L377-378
Review: task
Wave: 2
Touches: `studios/game-dev/bin/studio-peers`, `studios/game-dev/hooks/peer-runs.sh`, `studios/game-dev/hooks/hooks.json`, `tests/studio_peers_test.sh`, `tests/hook_test.sh`

**Interfaces:**
- Produces:
  - `studio-peers [--exclude <run dir>] [--files]`: output per D35, always exit 0, writes nothing;
  - the hook `peer-runs.sh`, which prints plain text on stdout, as `operator-inbox.sh` does at SessionStart.
- Consumes: from T3, `runs_live`, `runs_mf_header`, `runs_plan_files`. The story state file is
  `<root>/.studio/stories/<id>.md` (`task: k/N`), and the story record is `<run dir>/stories/<id>` (first line).

- [ ] **Step 1: Write the failing suite** `tests/studio_peers_test.sh` (new, executable).

  Its fixture `peers_fixture` makes a git project `P`: `main`, a `docs` commit
  holding two plans, and a fake run per slug. It reuses Task 3's `live_dummy`
  and `plock` shapes:
  - the run dir holds `manifest.md` (`# Run:`, `Mode:`, `Docs: <sha>`), `rows.tsv` (`id\tbranch\tticket\tspec\tplan\tdeps`) and `stories/<id>`;
  - the story state is `$P/.studio/stories/<id>.md`.

  The tests:
  - `test_peers_default_two_runs`:
    - with alpha (S1 `running`, task 1/3; S2 `landed`) and beta (S3 `running`, task 0/2) live, run from `$P` with `--exclude <alpha run dir>`;
    - expected output exactly `beta integration: S3 task 0/2`;
    - without `--exclude`, both runs show, alpha as `alpha integration: S1 task 1/3`. The landed S2 is left out.
  - `test_peers_files_both_forms`:
    - S1's plan uses the studio form and S3's the superpowers form;
    - `--files` prints `alpha <path>` lines only for tasks 2..3 of S1, and `beta <path>` lines for tasks 1..2 of S3;
    - the output is sorted and de-duplicated, with `:<lines>` stripped.
  - `test_peers_unreadable_run`: delete beta's `rows.tsv` and it prints `beta: unreadable` in both forms. A plan missing at `Docs:` gives the same in `--files`. The exit status is 0.
  - `test_peers_ignores_single_and_dead`: a live single-plan lock and a dead per-run lock print nothing.
  - `test_peer_hook_block`:
    - with `STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR=<alpha run dir>`, run the hook from `$P` with SessionStart JSON on stdin;
    - the output has `^Other live runs$`, `beta integration: S3 task 0/2`, the indented beta paths, and the rule line verbatim (Global Constraints);
    - with 45 paths it prints 40, then `  and 5 more`.
  - `test_peer_hook_silent`: no output with no other live run, without `STUDIO_UNIT_TAG`, or when `STUDIO_RUN_DIR` has no `rows.tsv` (a single-plan unit).
  - `test_peer_hook_exit0_bad_input`: a missing `STUDIO_RUN_DIR` dir, garbage stdin, and a `studio-peers` that is not executable (copy the plugin tree to `$TMP` and `chmod -x` it) each exit 0.

  In `tests/hook_test.sh`:
  - `test_hook_files` gains two assertions:
    - `assert_contains … 'CLAUDE_PLUGIN_ROOT}/hooks/peer-runs.sh'`;
    - `assert_eq 1 "$(grep -c 'hooks/peer-runs.sh' …)"`.
  - When `jq` is present, it asserts that the peer-runs entry's matcher is `startup|compact`.
  - `test_inbox_hook_registered` is unchanged: operator-inbox is still registered twice (D37).

- [ ] **Step 2: Run them and see them fail.** Run `sh tests/studio_peers_test.sh` and `TESTS_ONLY=test_hook_files sh tests/hook_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.** `studios/game-dev/bin/studio-peers` (`chmod +x`):

```sh
#!/bin/sh
# studio-peers — the other live manifest runs of this project (#39 AC21):
# their slug, mode and unfinished stories (task k/N), or with --files the
# files of those stories' unfinished tasks (k+1..N above ## Backlog) read
# from each run's plans at its Docs: revision. Reads only; no lock. A run
# whose data cannot be read prints `<slug>: unreadable`. Always exits 0.
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SELF_DIR/overnight-runs.sh"
EXCL=""; FILES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude) EXCL="${2:-}"; shift 2 || shift ;;
    --files) FILES=1; shift ;;
    *) printf 'usage: studio-peers [--exclude <run dir>] [--files]\n' >&2; exit 0 ;;
  esac
done
ROOT="$(sh "$SELF_DIR/studio-state" root 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0
canon() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s\n' "$1"; }
[ -z "$EXCL" ] || EXCL="$(canon "$EXCL")"
TAB="$(printf '\t')"
# peer_run SLUG DIR — this run's line(s); 1 when its data cannot be read.
peer_run() {
  _pr_mf="$2/manifest.md"; _pr_rows="$2/rows.tsv"
  [ -r "$_pr_mf" ] && [ -r "$_pr_rows" ] || return 1
  _pr_mode="$(runs_mf_header "$_pr_mf" Mode)"; _pr_docs="$(runs_mf_header "$_pr_mf" Docs)"
  _pr_open=""; _pr_files=""
  for _pr_id in $(cut -f1 "$_pr_rows" | awk 'NF && !seen[$0]++'); do
    case "$(head -n 1 "$2/stories/$_pr_id" 2>/dev/null)" in landed*|stopped*|skipped*) continue ;; esac
    _pr_t="$(sed -n 's/^task:[[:blank:]]*//p' "$ROOT/.studio/stories/$_pr_id.md" 2>/dev/null | head -n 1)"
    [ -n "$_pr_t" ] || _pr_t=-
    _pr_open="$_pr_open${_pr_open:+, }$_pr_id task $_pr_t"
    if [ "$FILES" = 1 ]; then
      _pr_k="${_pr_t%%/*}"; case "$_pr_k" in ''|*[!0-9]*) _pr_k=0 ;; esac
      _pr_plan="$(awk -F'\t' -v id="$_pr_id" '$1 == id { print $5; exit }' "$_pr_rows")"
      [ -n "$_pr_docs" ] && [ -n "$_pr_plan" ] || return 1
      _pr_f="$(git -C "$ROOT" show "$_pr_docs:$_pr_plan" 2>/dev/null)" || return 1
      _pr_files="$_pr_files$(printf '%s\n' "$_pr_f" | runs_plan_files "$_pr_k")
"
    fi
  done
  if [ "$FILES" = 1 ]; then
    printf '%s' "$_pr_files" | awk 'NF' | sort -u | sed "s|^|$1 |"
  else
    printf '%s %s: %s\n' "$1" "${_pr_mode:--}" "${_pr_open:--}"
  fi
}
runs_live "$ROOT" | while IFS="$TAB" read -r _t _slug _kind _pid _dir _sd _lock; do
  [ "$_kind" = manifest ] || continue
  [ -z "$EXCL" ] || [ "$(canon "$_dir")" != "$EXCL" ] || continue
  _out="$(peer_run "$_slug" "$_dir")" && printf '%s\n' "$_out" | awk 'NF' || printf '%s: unreadable\n' "$_slug"
done
exit 0
```

  `studios/game-dev/hooks/peer-runs.sh` (`chmod +x`):

```sh
#!/bin/sh
# peer-runs.sh — SessionStart (startup|compact) hook (#39 AC22). In a
# manifest unit session (STUDIO_UNIT_TAG, STUDIO_RUN_DIR with rows.tsv) it
# prints the `Other live runs` block: studio-peers' runs, up to 40 of their
# unfinished-task files and `and N more`, then the peers rule. Nothing when
# no other run is live or outside a unit. Exits 0 on every path; errors go
# to <run dir>/hook.log.
trap 'exit 0' EXIT
[ -n "${STUDIO_UNIT_TAG:-}" ] && [ -n "${STUDIO_RUN_DIR:-}" ] && [ -f "$STUDIO_RUN_DIR/rows.tsv" ] || exit 0
exec 2>> "$STUDIO_RUN_DIR/hook.log"
cat > /dev/null 2>&1 || true
HERE="$(cd "$(dirname "$0")" && pwd)"; PEERS="$HERE/../bin/studio-peers"
MAX=40
RUNS="$(sh "$PEERS" --exclude "$STUDIO_RUN_DIR")" || exit 0
[ -n "$(printf '%s' "$RUNS" | tr -d ' \n')" ] || exit 0
FILES="$(sh "$PEERS" --exclude "$STUDIO_RUN_DIR" --files | grep -v ': unreadable$')"
N="$(printf '%s\n' "$FILES" | grep -c .)"
printf 'Other live runs\n\n%s\n' "$RUNS"
if [ "$N" -gt 0 ]; then
  printf '\nFiles their unfinished tasks change:\n'
  printf '%s\n' "$FILES" | grep . | head -n "$MAX" | sed 's/^/  /'
  [ "$N" -le "$MAX" ] || printf '  and %s more\n' "$((N - MAX))"
fi
printf '\n%s\n' "These files are being changed by another live run. Do not edit them beyond what your task needs; if your task needs to, keep the change minimal and name each such file in your report."
```

  In `hooks.json`, add a third SessionStart entry after the operator-inbox one:
  `{"matcher": "startup|compact", "hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/peer-runs.sh\""}]}`.
- [ ] **Step 4: Run** the Step 2 commands. Expected: PASS. Then `sh tests/hook_test.sh` and `sh tests/studio_test.sh` (`test_bin_syntax`). Expected: exit 0.
- [ ] **Step 5: Commit.** `feat(studio): studio-peers and the peer-runs hook (#39)` with the trailers.

---

### Task 9: `studio-adopt` (#35) from a run worktree

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L197-202, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L290-290, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L376-376
Review: task
Wave: 2
Touches: `studios/game-dev/bin/studio-adopt`, `tests/studio_adopt_test.sh`

**Interfaces:**
- Produces:
  - `start_checkout ID`: D40;
  - `run_target` and `run_manifest` use it when `STUDIO_RUN`/`IN_RUN` are unset;
  - `live_run_check` reads every live lock through `runs_live`;
  - `part_done` ignores the sync subjects.
- Consumes: from T3, `runs_live`, `runs_worktree_of`. (`.studio/runs/<slug>/lock` is written by T7; the tests build it by hand.)

- [ ] **Step 1: Read AC20** (L197-202) and the current functions. Find them with
  `grep -n '^state_root()\|^plan_file()\|^part_done()\|^run_target()\|^run_manifest()\|^live_run_check()\|^cmd_seed()\|^cmd_sync()' studios/game-dev/bin/studio-adopt`
  (76, 83, 207, 229, 538, 560, 398, 639).
- [ ] **Step 2: Write the failing tests** in `tests/studio_adopt_test.sh`. Reuse its fixture helpers; find them with `grep -n '^[a-z_]*()' tests/studio_adopt_test.sh | head -20`.
  - `test_adopt_start_checkout_from_run_worktree`:
    - a run worktree `run-alpha` on `run/alpha`, whose `.studio/run` manifest lists `S1`;
    - from the main checkout, `studio-adopt seed S1` and `run_target` resolve to the run worktree's manifest and `.studio/run`. Assert the printed manifest path is under `run-alpha`.
  - `test_adopt_start_checkout_two_listings_refuse`: two run worktrees list `S1`. The command exits non-zero with `story S1 is listed by two run worktrees:`.
  - `test_adopt_start_checkout_none_falls_back`: no run worktree lists it, so `$STATE_ROOT`'s `.studio/run` is used, as today.
  - `test_adopt_live_run_check_per_run_lock`:
    - a live `.studio/runs/alpha/lock` (a `live_dummy` pid, run dir with `rows.tsv` listing `S1`, `stories/S1` = `sync-repair`) makes `studio-adopt sync S1` refuse as for a live story;
    - the same with `running`;
    - the own-unit exemption (`IN_RUN_DIR` = that run dir) still passes.
  - `test_adopt_part_done_ignores_sync`: a story branch whose task commit is followed by `chore(sync): merge origin/main into S1-b` and `fix(sync): resolve x` still counts the task as done, the same count as without those commits.
- [ ] **Step 3: Run them and see them fail.** `TESTS_ONLY="test_adopt_start_checkout_from_run_worktree test_adopt_live_run_check_per_run_lock test_adopt_part_done_ignores_sync" sh tests/studio_adopt_test.sh`. Expected: FAIL.
- [ ] **Step 4: Implement.**
  - Source `overnight-runs.sh` next to the script's other setup.
  - `start_checkout ID`, after `state_root`:
    ```sh
    # start_checkout ID — the checkout whose .studio/run manifest lists ID
    # (#39 AC20, D40): a porcelain worktree on run/* (the main checkout
    # included). Two refuse; none prints state_root.
    start_checkout() {
      _sc_hits=""
      for _sc_w in $(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{ w = substr($0, 10) } /^branch refs\/heads\/run\//{ print w }'); do
        _sc_m="$(head -n 1 "$_sc_w/.studio/run" 2>/dev/null)"; [ -n "$_sc_m" ] || continue
        case "$_sc_m" in /*) ;; *) _sc_m="$_sc_w/$_sc_m" ;; esac
        grep -q "^|[[:blank:]]*$1[[:blank:]]*|" "$_sc_m" 2>/dev/null && _sc_hits="$_sc_hits $_sc_w"
      done
      set -- $_sc_hits
      [ "$#" -le 1 ] || die "story $1 is listed by two run worktrees: $*"
      if [ "$#" = 1 ]; then printf '%s\n' "$1"; else state_root; fi
    }
    ```
    The `die` message must name the id. Save `$1` before the `set --` (the
    sketch shadows it). Worktree paths with blanks are out of scope, as they
    are everywhere in the runner.
  - `run_target` and `run_manifest`: replace `state_root` with `start_checkout "$ID"` when no `STUDIO_RUN`/`IN_RUN` is set. Callers that have no id keep `state_root`.
  - `live_run_check`: loop over `runs_live "$(state_root)"` in place of the single `overnight.lock` read. For each run dir whose `rows.tsv` lists the id, apply today's state test, with the list `running|held|repair|gate-repair|sync-repair|landing`. The exemption is unchanged.
  - `part_done`: change the awk subject regex to
    `^(fix\(final|fix\(gate|fix\(review|fix\(sync|chore\(sync|docs\(progress)`.
- [ ] **Step 5: Run the tests.** Run the Step 3 command, then `sh tests/studio_adopt_test.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `feat(studio): studio-adopt resolves stories from run worktrees (#39)` with the trailers.

---

### Task 10: Run selection — `stop`, `watch`, the channel's resolution, the registry

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L55-63, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L80-88, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L156-173, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L354-358, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L395-395
Review: task
Wave: 3
Touches: `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-channel.sh`, `tests/overnight_test.sh`

**Interfaces:**
- Produces:
  - bare `stop` with two or more live runs (D13), `stop --run <sel>`, `stop --all`;
  - `watch [--run <sel>] [SECONDS]`;
  - AC13's resolution in `chan_find_run` (D18);
  - `registry_status` prints each root once (D17);
  - help (D43).
- Consumes: from T7, `runs_live`, `runs_match`, `runs_stop_of`, `fake_mrun`, `RUN_SEL` and `project_status`.

- [ ] **Step 1: Write the failing tests** in `tests/overnight_test.sh`, each using `fixture` and `fake_mrun` (`FR_SEQ` orders them):
  - `test_status_two_runs_blocks_oldest_first`:
    - `fake_mrun beta S2=running` (`FR_SEQ=2`) and `fake_mrun alpha S1=running` (`FR_SEQ=1`);
    - status exits 0, and the `== alpha (manifest, pid …) — …` line comes before `== beta …`.
  - `test_status_run_not_live`: `status --run ghost` exits 1 with `no live run ghost`. `status --run alpha` prints alpha's `run:` and no `== `.
  - `test_status_registry_root_once`: from a non-project dir, two live entries for one root print that root's `== … — <root>` header once, naming both runs, and exit 3 as today.
  - `test_watch_run_selects`: `STUDIO_OVERNIGHT_WATCH_ONCE`-style single pass. Use the suite's existing watch hook; find it with `grep -n 'WATCH' tests/overnight_test.sh`. `watch --run beta 1` prints beta's block only.
  - `test_stop_two_runs_refuses`:
    - with two live, bare `stop` exits 1 and writes no flag;
    - stdout has `2 runs are live — nothing stopped:`, a line per slug, `stop --run <slug>` and `stop --all`.
  - `test_stop_run_writes_own_flag`:
    - `stop --run beta` writes `.studio/runs/beta/stop` only;
    - `stop --run <alpha run dir basename>` writes alpha's;
    - for a single-plan `fake_run`, `stop --run <basename>` writes `.studio/overnight.stop`.
  - `test_stop_all_writes_each_flag`: both flags are written, one `stop requested: <slug> (pid <p>)` line each. A run ended just before (`fake_run_end` on beta) is skipped.
  - `test_stop_story_unchanged`: `stop S1` with two runs live resolves alpha (it lists S1) and writes the story control file as today, with no run flag.
  - `test_verbs_channel_resolution_by_story`: with alpha listing S1 and beta listing S2, each of `say`, `unsay`, `hold`, `resume`, `said` and `stop` on S2 acts on beta's run dir. Check where today's single-run tests look; find them with `grep -n 'inbox/\|control/' tests/overnight_test.sh | head`.
  - `test_verbs_channel_run_flag_slug_or_basename`: `say --run beta S2 x` and `say --run <beta basename> S2 x` both reach beta. `--run alpha S2` refuses with today's `S2 is not in run …`. Check the flag's position against the existing `verb say - --run overnight-sd-1 -- …` test (line ~1100).
  - `test_verbs_channel_no_run_lists_story`: with two live runs and neither listing `S9`, the verb exits 1 with `no live run lists S9`. With zero runs it keeps today's `no live run in <root>` (D18).
  - `test_verbs_channel_start_dir_from_lock`: `fake_mrun` with `start=$P/wt` in the lock, so `CH_START` is `$P/wt`. Assert it through the verb's start-dir-dependent output; find it with `grep -n 'CH_START' studios/game-dev/bin/overnight-channel.sh`.
  - `test_help_names_concurrent_runs`: help lists `status [--run <slug>]`, `watch [--run <slug>]`, `stop --run`, `stop --all`, `max_sessions`, and `install or pull omega-ai only when` (D43).
- [ ] **Step 2: Run them and see them fail.** `TESTS_ONLY="test_stop_two_runs_refuses test_verbs_channel_resolution_by_story test_status_registry_root_once" sh tests/overnight_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **Stop dispatch.** Relocate with `grep -n '^  stop)$' "$SO"`:
    ```sh
    stop)
      shift
      case "${1:-}" in
        '') _sl="$(runs_live "$STATE_ROOT")"; _sn="$(printf '%s\n' "$_sl" | grep -c .)"
            if [ "$_sn" = 0 ]; then echo "no run in $STATE_ROOT"; exit 1; fi    # today's text: relocate it verbatim
            if [ "$_sn" -gt 1 ]; then
              printf '%s runs are live — nothing stopped:\n' "$_sn"
              printf '%s\n' "$_sl" | awk -F'\t' '{ b = $5; sub(/.*\//, "", b); printf "  %s  %s\n", ($2 == "-" ? b : $2), $5 }'
              printf "stop one: %s stop --run <slug> · stop all: %s stop --all\n" "$(sq "$SELF_ABS")" "$(sq "$SELF_ABS")"
              exit 1
            fi
            _sk="$(printf '%s\n' "$_sl" | cut -f7)"; : > "$(runs_stop_of "$_sk")"
            echo "stop requested: the run ends after its running unit (pid $(printf '%s\n' "$_sl" | cut -f4))" ;;
        --all) [ "$#" -eq 1 ] || usage
            _sl="$(runs_live "$STATE_ROOT")"; [ -n "$_sl" ] || { echo "no run in $STATE_ROOT"; exit 1; }
            printf '%s\n' "$_sl" | while IFS="$(printf '\t')" read -r _ _ss _ _sp _sd _ _sk; do
              runs_lock_live "$_sk" || continue
              : > "$(runs_stop_of "$_sk")"; printf 'stop requested: %s (pid %s)\n' "$([ "$_ss" != - ] && echo "$_ss" || basename "$_sd")" "$_sp"
            done ;;
        *) chan_main stop "$@" ;;
      esac ;;
    ```
    Keep today's exact no-run text and the stop message; read them first.
    `stop --run <sel>` with no story already goes to `chan_main`, whose
    `chan_stop_run` writes the run's own flag (T7). `stop --run <sel> <story>`
    is unchanged.
  - **`watch`.** Parse `--run <sel>` before the optional `SECONDS`, set `RUN_SEL`, and refresh `project_status`'s output.
  - **`chan_find_run`, in project (D18):**
    ```sh
    if [ -n "$A_RUN" ]; then …(T7)…
    else
      _cf_n="$(printf '%s\n' "$_cf_live" | grep -c .)"
      [ "$_cf_n" -gt 0 ] || chan_fail 1 "no live run in $STATE_ROOT"
      _cf_l=""
      if [ -n "${A_STORY:-}" ]; then
        _cf_l="$(printf '%s\n' "$_cf_live" | while IFS="$(printf '\t')" read -r _ _ _ _ _d _ _; do
                   awk -F'\t' -v s="$A_STORY" '$1 == s { f = 1 } END { exit !f }' "$_d/rows.tsv" 2>/dev/null && { printf '%s\n' "$_d"; break; }
                 done)"
        [ -z "$_cf_l" ] || _cf_l="$(printf '%s\n' "$_cf_live" | awk -F'\t' -v d="$_cf_l" '$5 == d')"
      fi
      if [ -z "$_cf_l" ]; then
        [ "$_cf_n" = 1 ] || chan_fail 1 "no live run lists ${A_STORY:-that story}"
        _cf_l="$_cf_live"
      fi
    fi
    ```
    `A_STORY` is the parsed story argument; find its name with `grep -n 'A_STORY\|A_ID' studios/game-dev/bin/overnight-channel.sh | head`. A verb with no story (`said` with no story, run-level `stop`) uses the "exactly one live run" rule.
  - **`registry_status` (D17).** Collect the live entries, group them by `root=` in first-seen order, and print one header per root: `== <run>, <run> — <root>`, then that root's `project_status` once.
  - **`usage` (D43).** Add the forms, plus the line `install or pull omega-ai only when \`studio-overnight status\` shows no live run (a run reads the plugin while it runs)`.
- [ ] **Step 4: Run the tests.** Run the Step 2 command, then `sh tests/overnight_test.sh`, `sh tests/overnight_lanes_test.sh` and `sh integrations/multica/tests/run.sh` (the bridge calls `stop --run`). Expected: exit 0.
- [ ] **Step 5: Commit.** `feat(overnight): stop, watch and channel pick one of several runs (#39)` with the trailers.

---

### Task 11: The manifest preflight — conflicts, re-check, overlap warning, `next`

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L145-152, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L177-177, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L350-353, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L359-359
Review: task
Wave: 3
Touches: `studios/game-dev/bin/overnight-lanes.sh`, `tests/overnight_lanes_test.sh`

**Interfaces:**
- Produces:
  - `mf_conflicts LIVE_ONLY`: prints one refusal line per conflict, and is used by both `mf_check` and the LN `lock_recheck`;
  - `mf_overlap_warn`;
  - `lanes_next`'s slug forms.
- Consumes:
  - from T3, `runs_live`, `runs_rows`, `runs_record_open`, `runs_record_done`, `runs_mf_header`, `runs_plan_files`;
  - from T8, `studio-peers --files`;
  - from T7, `lock_recheck` and `lanes_add_run`.

- [ ] **Step 1: Write the failing tests** in `tests/overnight_lanes_test.sh`:
  - `test_lanes_preflight_refuses_live_slug_id_branch`:
    - `lanes_fixture` (`demo`, story `A`), with alpha (story `S1`) added and live through `bg_lanes` and the `hang` scenario;
    - three manifests in alpha's run worktree start with `--dry-run`, one per conflict:
      1. slug `alpha` (a copy of RMF with new ids);
      2. a row with id `S1`;
      3. a row with branch `S1-b`;
    - each exits 2 and names `alpha`, its run dir, and the way out (`stop --run alpha` or a new slug, id or branch);
    - `detach_stop`-style cleanup ends alpha.
  - `test_lanes_preflight_refuses_stopped_record`: after alpha ends stopped (its record has `landed.tsv` and no `done`), a new manifest using `S1` refuses. The rows come from the newest `reports/overnight-alpha-*` (D39).
  - `test_lanes_preflight_done_record_needs_archive`: `: > .studio/runs/alpha/done` makes a new run named `alpha` refuse with `.studio/runs/alpha.<utc ts>` named in the message. After `mv` to `alpha.20261004T000000Z` it passes.
  - `test_lanes_preflight_branch_forms`:
    - branches `run/x`, `integration-x` and `progress/y` refuse, by their `/`→`-` form;
    - a branch equal to a live run's Target (`integration/alpha`) refuses.
  - `test_lanes_preflight_slug_off_and_digits`: `# Run: off` and `# Run: 123` refuse.
  - `test_lanes_preflight_resume_own_record`: `demo` stopped and restarted with the same manifest passes (its own record without `done` is a resume).
  - `test_lanes_recheck_race_one_wins`:
    - two manifests that share story id `S1` (alpha in `RW`, gamma in a second run worktree, both added by `lanes_add_run`);
    - `STUDIO_OVERNIGHT_LOCK_HOOK='sleep 2'` makes both pass the preflight before either locks: `bg_lanes` both within 0.5 s;
    - after both end, exactly one exited 0, and the other exited 2 with a message naming the winner;
    - the loser left no `.studio/runs/<slug>/lock`, no run dir, and no record dir.
  - `test_lanes_overlap_warning`:
    - alpha is live and its unfinished S1 task 2 `Files:` names `shared.txt`;
    - demo's A task 1 names `shared.txt` too;
    - `start --dry-run` of demo exits 0, and stderr has `warning — live run alpha is changing files` and `  shared.txt`;
    - with 25 shared paths it lists 20, then `  and 5 more`.
  - `test_lanes_next` (rewrite, D1): the three `next:` asserts become `next: /game-dev:brainstorm demo/A`, `next: /game-dev:plan demo/A` and `next: /omega:autopilot demo`. Relocate them with `grep -n 'next: /' tests/overnight_lanes_test.sh`.
  - `test_lanes_next_slug_forms`: a manifest whose slug is `alpha-2` prints `alpha-2/<id>`.
- [ ] **Step 2: Run them and see them fail.** `TESTS_ONLY="test_lanes_preflight_refuses_live_slug_id_branch test_lanes_recheck_race_one_wins test_lanes_overlap_warning test_lanes_next" sh tests/overnight_lanes_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement in LN.**
  - Add to `mf_check` (`grep -n '^mf_check()' "$LN"`), after the slug regex check:
    - `case "$MF_SLUG" in off) refuse "slug off is reserved (/omega:autopilot off) — pick another" ;; *[!0-9]*) ;; *) refuse "slug $MF_SLUG is all digits (it reads as a story id) — pick another" ;; esac`;
    - a branch-form check on each row's branch (`printf %s "$b" | tr / -`, then `case run-*|integration-*|progress-*`);
    - `mf_conflicts 0`, where each output line becomes a `refuse`;
    - `mf_overlap_warn` last (it only warns).
  - The hard part, `mf_conflicts`:
    ```sh
    # mf_conflicts LIVE_ONLY — this manifest (MF_SLUG, MF_ROWS) against the
    # other runs (#39 AC8, D39): live runs' rows.tsv and Target, and with
    # LIVE_ONLY=0 also stopped records (landed.tsv, no done; rows from the
    # newest report dir) and a done record of this slug. One line per conflict.
    mf_conflicts() {
      _mc_tab="$(printf '\t')"
      runs_live "$STATE_ROOT" | while IFS="$_mc_tab" read -r _ _mc_s _mc_k _mc_p _mc_d _ _mc_l; do
        [ "$_mc_l" != "$LOCK" ] || continue
        [ "$_mc_k" = manifest ] || continue
        _mc_how="live run $_mc_s ($_mc_d, pid $_mc_p) — stop it ($(sq "$SELF_ABS") stop --run $_mc_s) or pick another"
        [ "$_mc_s" != "$MF_SLUG" ] || printf 'slug %s is used by %s slug\n' "$MF_SLUG" "$_mc_how"
        mf_rows_clash "$_mc_d/rows.tsv" "$_mc_how"
        _mc_t="$(runs_mf_header "$_mc_d/manifest.md" Target)"
        cut -f2 "$MF_ROWS" | grep -qxF -- "$_mc_t" && printf 'branch %s is the Target of %s branch\n' "$_mc_t" "$_mc_how"
      done
      [ "$1" = 1 ] && return 0
      for _mc_r in "$STATE_ROOT"/.studio/runs/*/landed.tsv; do
        [ -f "$_mc_r" ] || continue
        _mc_s="${_mc_r%/landed.tsv}"; _mc_s="${_mc_s##*/}"
        if [ "$_mc_s" = "$MF_SLUG" ]; then
          runs_record_done "$STATE_ROOT" "$_mc_s" && printf 'run %s is done: archive its record first: mv %s %s.<utc ts>\n' \
            "$_mc_s" "$(sq "$STATE_ROOT/.studio/runs/$_mc_s")" "$(sq "$STATE_ROOT/.studio/runs/$_mc_s")"
          continue                                    # own open record: a resume
        fi
        runs_record_open "$STATE_ROOT" "$_mc_s" || continue
        runs_live "$STATE_ROOT" | runs_match "$_mc_s" | grep -q . && continue   # counted above
        _mc_rows="$(runs_rows "$STATE_ROOT" "$_mc_s")" || continue
        mf_rows_clash "$_mc_rows" "stopped run $_mc_s (record $STATE_ROOT/.studio/runs/$_mc_s) — resume it ($(sq "$SELF_ABS") start <its manifest>) or pick another"
      done
    }
    # mf_rows_clash ROWS HOW — a story id or branch of MF_ROWS that ROWS uses too.
    mf_rows_clash() {
      awk -F'\t' -v how="$2" 'NR == FNR { id[$1] = 1; br[$2] = 1; next }
        ($1 in id) { printf "story %s is used by %s id\n", $1, how }
        ($2 in br) { printf "branch %s is used by %s branch\n", $2, how }' "$1" "$MF_ROWS" 2>/dev/null
    }
    ```
    (The `NR == FNR` pass reads the other run's rows first, then flags this run's rows.)
  - **`lock_recheck`** (LN, extending T7): it refuses a live single-plan run as before, then runs `_rc="$(mf_conflicts 1)"`. A non-empty result sets `RECHECK_WHY="lost the start race: $(printf '%s\n' "$_rc" | head -n 1)"` and returns 1.
  - **`mf_overlap_warn`:**
    - the other runs' files come from `sh "$SELF_DIR/studio-peers" --files`, grouped by slug;
    - this run's files come from each row's plan at `MF_DOCS` (`git show`), each from its story's `task` k (0 when there is no state), through `runs_plan_files`;
    - it prints the intersection per slug in D38's format, at most 20 lines plus `and N more`;
    - any failure warns nothing.
  - **`lanes_next`** (`grep -n 'next: /' "$LN"`): print `next: /game-dev:brainstorm $MF_SLUG/$_ln_bs`, `next: /game-dev:plan $MF_SLUG/$_ln_pl` and `next: /omega:autopilot $MF_SLUG`.
- [ ] **Step 4: Run the tests.** Run the Step 2 command, then `sh tests/overnight_lanes_test.sh` and `sh tests/overnight_test.sh`. Expected: exit 0.
- [ ] **Step 5: Commit.** `feat(overnight): runs refuse shared slugs, stories and branches (#39)` with the trailers.

---

### Task 12: Session slots in the runner, `session_wait`, `sessions:` in status

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L156-157, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L243-252, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L301-303, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L323-326, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L360-367
Review: task
Wave: 4
Touches: `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-lanes.sh`, `tests/overnight_lanes_test.sh`, `tests/overnight_test.sh`, `tests/overnight_progress_test.sh`, `docs/game-dev/overnight-events.md`

**Interfaces:**
- Produces:
  - `session_acquire LABEL`, `session_started PID` and `session_release`: no-ops in SO, real in LN (D19);
  - `UNIT_HALTED`;
  - `$UNIT_DIR/slotwait`;
  - the `session_wait` event;
  - the `sessions: <live>/<cap>` line;
  - `max_sessions` preflight validation;
  - stub: `$CALLS/live/` and `$CALLS/max`.
- Consumes: the T6 lib (`sess_*`), and from T7, `runs_live` and `project_status`.

- [ ] **Step 1: Stub changes** in the lanes suite's stub `claude` (`grep -n 'n.lock' tests/overnight_lanes_test.sh`, line 128). After the numbering block, add:
  ```sh
  # #39: live-session counter. live/<pid> while this session runs; max holds the
  # largest count seen (updated under n.lock).
  mkdir -p "$CALLS/live"; : > "$CALLS/live/$$"
  trap 'rm -f "$CALLS/live/$$"' EXIT; trap 'rm -f "$CALLS/live/$$"; exit 143' TERM
  while ! mkdir "$CALLS/n.lock" 2>/dev/null; do sleep 0.1; done
  _lv="$(ls "$CALLS/live" | grep -c .)"; _mx="$(cat "$CALLS/max" 2>/dev/null || echo 0)"
  [ "$_lv" -le "$_mx" ] || echo "$_lv" > "$CALLS/max"
  rmdir "$CALLS/n.lock"
  printf '%s\n' "$(date +%s)" > "$CALLS/$n.t0w"      # wall start, for the session_minutes test
  ```
  The stub's existing actions keep their behaviour. Check that no action `exec`s away from the trap: `grep -n 'exec ' tests/overnight_lanes_test.sh | head`. If one does, rewrite it to a plain call.
- [ ] **Step 2: Write the failing tests** in `tests/overnight_lanes_test.sh`:
  - `test_lanes_slot_cap_two_across_runs`:
    - `LANES_CONFIG='{"overnight": {"max_lanes": 2, "max_sessions": 2}}'`;
    - `lanes_fixture` with A and B (independent) and `lanes_add_run alpha integration S1:- S2:-` with `max_lanes` 2, where every story's first line is `sleep 2`, then `auto`;
    - both run at once (`bg_lanes`);
    - `assert_eq 2 "$(cat "$CALLS/max")"` (four lanes, cap 2); both exit 0 and all four stories land.
  - `test_lanes_slot_cap_one_alternates`:
    - cap 1, demo A and alpha S1, each with two task units (`sleep 1` each);
    - the stub's `t0` order alternates between the runs after the first unit: read `$CALLS/<n>.story` in call order and expect no story with three calls in a row while the other waits;
    - `max` is 1.
  - `test_lanes_slot_kill9_lane_reclaimed`:
    - cap 1, demo with A (`hang`) and B (`auto`), `max_lanes` 2;
    - once A's unit runs, `kill -9` A's lane pid (`$RUN_DIR/lanes/<k>/pid`) and its stub session;
    - B's unit then starts (a slot reclaim by liveness) and the run ends.
  - `test_lanes_slot_stop_ends_wait`:
    - cap 1, with A holding the slot (`sleep 4`);
    - B waits, which shows as `waiting for a session slot since` in `status` and as `lanes/<k>/slotwait`;
    - `stop` then makes B's story end `stopped by user` without a call for B, and the wait entry is gone.
  - `test_lanes_slot_released_every_exit`: after runs that end in each way (a normal end, a `stop` mid-unit, a SIGTERM to the runner, a lane killed by `lanes_sweep`), `.studio/sessions/` has no `[0-9]*` dirs and `wait/` has no entries.
  - `test_lanes_slot_wait_not_in_session_minutes`:
    - cap 1, with A holding the slot for 3 s (`sleep 3`) while B waits;
    - B's `session_wait` event comes before its `unit_started` event in `events.jsonl`;
    - B's stub `t0` is at or after A's `t1`, so B's unit clock (the `unit.now` start and the watchdog) began only once it held the slot;
    - if the suite has a seconds-scale session-limit hook (`grep -n 'SESSION_SECONDS\|session_minutes' tests/overnight_lanes_test.sh | head`), also set it below A's hold time and assert B's unit is not `timed out`.
  - `test_lanes_session_wait_event_and_status`: `events.jsonl` has a `session_wait` line with `"lane":"<k>"`, `"story":"B"` and an ISO `since`. Status with the run live prints `sessions: 1/1` first and `    waiting for a session slot since <hh:mm>` under B.
  - `test_lanes_max_sessions_preflight`: `max_sessions` `0`, `9` and `"x"` each refuse at `start --dry-run` with `overnight.max_sessions`, exit 2.

  In `tests/overnight_test.sh`:
  - add `session_wait` to `test_events_contract_doc`'s event list (`grep -n 'for e in run_started' tests/overnight_test.sh`);
  - add `test_status_sessions_line_first`: with `fake_mrun alpha`, a manually made `.studio/sessions/1` (owner = `FR_PID`) and config `max_sessions` 3, status line 1 is `sessions: 1/3`.

  In `tests/overnight_progress_test.sh` L66 (D1, D15): with a manifest run live, the progress line is line 2:
  ```sh
  assert_eq sessions "$(sed -n 1p "$TMP/st.out" | cut -c1-8)" "the sessions line comes first (#39 AC10)"
  assert_eq progress "$(sed -n 2p "$TMP/st.out" | cut -c1-8)" "the progress line comes first in the run's block"
  ```
  Check what that test's fixture makes live (`grep -n 'test_progress_fresh_no_data' -A20 tests/overnight_progress_test.sh`). If it uses an old-style manifest `overnight.lock`, it counts as a live manifest run (AC31), so the sessions line appears.
- [ ] **Step 3: Run them and see them fail.** `TESTS_ONLY="test_lanes_slot_cap_two_across_runs test_lanes_slot_stop_ends_wait test_lanes_session_wait_event_and_status" sh tests/overnight_lanes_test.sh`. Expected: FAIL.
- [ ] **Step 4: Implement in SO.**
  - `session_acquire() { :; }`, `session_started() { :; }` and `session_release() { :; }`, near `run_unit`.
  - In `run_unit` (`grep -n 'model_for "\$2"' "$SO"`), right after the model line:
    `UNIT_HALTED=0; session_acquire "$2" || { UNIT_HALTED=1; return 0; }`.
    `current` and `utag` are already written above it (D23).
  - After `with_launch_args start_session`: `session_started "$CPID"`.
  - After the wait loop, where `CPID=""` is set: `session_release`.
  - `end_session` and `on_exit` call `session_release`; `lanes_on_exit`'s path reaches `end_session` already.
  - In `story_units`, after `run_unit`: `[ "$UNIT_HALTED" = 0 ] || { ENDING="$(halt_reason)"; return 0; }`.
  - In the `preflight`, for manifest runs only (`[ -n "${MF:-}" ]` or the dispatcher's mode flag; read how `preflight manifest` is called), validate `max_sessions` the way `max_lanes` is validated. The value is read from `$STATE_ROOT/.studio/config.json` with today's `cfg_raw` logic pointed at that file. Range 1–8, integer, else `refuse "overnight.max_sessions must be an integer 1-8 in $STATE_ROOT/.studio/config.json"`. Set `SESS_START_CAP`.
  - `project_status` (T7's loop): when at least one live run is `manifest` and there is no `RUN_SEL`, first print `sessions: <live>/<cap>`. Use the T6 lib with `SESS_START_CAP` defaulting to 6; `<live>` is `sess_live_count`, a read without reclaim (D37 equivalent).
- [ ] **Step 5: Implement in LN.** Source `overnight-sessions.sh` next to the runs lib. Then the hard part:
  ```sh
  # slot_halt — a wait ends only on a halt (D22): lane_halt in a lane, the stop file for the final step.
  slot_halt() { if [ -n "${LANE_PID:-}" ]; then lane_halt; else [ -e "$STOP_FILE" ]; fi; }
  # session_acquire LABEL — queue for a project session slot before the unit
  # starts (#39 AC27): FIFO, taken before unit_started and the clocks. 1 on a
  # halt (the wait entry removed). The first failed try writes slotwait and
  # the session_wait event.
  session_acquire() {
    SESS_ME="${LANE_PID:-$$}"; SESS_RUN="$RUN_DIR"; sess_init
    _sa_story="${CUR_ID:--}"; _sa_lane="${LANE_K:-final}"; _sa_waited=0
    sess_enqueue "$_sa_story" "$1" || { say "sessions: cannot queue in $STATE_ROOT/.studio/sessions"; return 1; }
    while :; do
      if slot_halt; then sess_wait_cancel; rm -f "$UNIT_DIR/slotwait"; return 1; fi
      if sess_try "$1"; then rm -f "$UNIT_DIR/slotwait"; return 0; fi
      [ -n "$SESS_WAIT" ] || sess_enqueue "$_sa_story" "$1"     # swept: re-queue at the tail
      if [ "$_sa_waited" = 0 ]; then
        _sa_waited=1; date +%H:%M > "$UNIT_DIR/slotwait"
        run_event session_wait "lane=$_sa_lane" "story=$_sa_story" "since=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      fi
      sleep "${STUDIO_OVERNIGHT_SLOT_POLL_SECONDS:-2}"
    done
  }
  session_started() { sess_session "$1"; }
  session_release() { sess_release; sess_wait_cancel; }
  ```
  `LANE_K` is the lane number variable; find its real name with `grep -n 'LANE_K\|_lm_k\|lanes/\$' "$LN" | head`.
  - Handle `UNIT_HALTED` after the other `run_unit` callers (D22):
    - `land_repair`: `story_write "$1" "stopped $(lane_halt_reason)"; return 1`;
    - `gate_repair`: `ENDING="$(lane_halt_reason)"; return 1`;
    - `final_unit`: `final_note "stopped before $1"; return 1`. Find `final_note` with `grep -n '^final_note()' "$LN"`; if it does not exist, use what `final_unit`'s budget path writes.
  - `lane_exit` and `lanes_on_exit` call `session_release`.
  - `lanes_end_sessions` and `lanes_sweep`: after each lane pid's KILL, `sess_drop_owner "<lane pid>"` (SESS_* initialised with `SESS_ME=$$`).
  - `lanes_status_lines`: under a story whose lane has `lanes/<k>/slotwait`, print `    waiting for a session slot since $(cat …)` in place of the `unit_now_line`. For `final/slotwait`, print `final: waiting for a session slot since …`.
  - `session_wait` is written in LN, so `test_events_contract_doc` sees it.
- [ ] **Step 6: Events doc.** Add a row after `unit_ended`:
  `| \`session_wait\` | \`lane\`, \`story\`, \`since\` | \`lane\` is the lane number or \`final\`; \`story\` is \`-\` for a final-step unit; \`since\` is ISO-8601 UTC; once per wait, when the first slot request fails; the unit's own \`unit_started\` follows when it gets a slot |`
- [ ] **Step 7: Run the tests.** Run the Step 3 command, then `sh tests/overnight_lanes_test.sh`, `sh tests/overnight_test.sh`, `sh tests/overnight_progress_test.sh` and `sh tests/overnight_sessions_test.sh`. Expected: exit 0.
- [ ] **Step 8: Commit.** `feat(overnight): project-wide session cap with a FIFO queue (#39)` with the trailers.

---

### Task 13: The sync check and the sync repair

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L219-239, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L301-304, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L368-375
Review: task
Wave: 5
Touches: `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-lanes.sh`, `tests/overnight_lanes_test.sh`, `tests/overnight_test.sh`, `docs/game-dev/overnight-events.md`

**Interfaces:**
- Produces:
  - SO: `unit_pre LABEL` (a no-op), the `sync-repair` label in `model_for` and `story_units_table`;
  - LN: `unit_pre`, `sync_check ID`, `sync_repair ID REF`;
  - the `story_synced` event;
  - stub: kind `<id>.sync` and the `syncrepair` action.
- Consumes: `git_retry`, `row_field`, `story_state`, `story_write`, `snapshot`, `new_stop`, `run_unit`, `unit_outcome`, `orphan_note`, `lane_halt`, `lane_halt_reason`, and T12's `UNIT_HALTED`.

- [ ] **Step 1: Stub changes.**
  - Kind (`grep -n '\*--land\*) kind=' tests/overnight_lanes_test.sh`): before `--land`, add `*--land*) case "${STUDIO_REPAIR:-}" in sync:*) kind="$id.sync" ;; *) kind="$id.land" ;; esac ;;`.
  - Action `syncrepair`, in the stub's action `case`:
    ```sh
    syncrepair)  terminal=1; w="$(story_wt)"; _ref="${STUDIO_REPAIR#sync:}"
                 ( cd "$w" && git fetch -q origin && { git merge -q --no-edit "$_ref" >/dev/null 2>&1 || {
                     git checkout -q --theirs -- . && git add -A && git -c core.editor=true commit -q --no-edit; }; } \
                   && git commit -q --allow-empty -m "fix(sync): resolve $_ref" \
                   && STUDIO_STORY="$id" sh "$STATE_BIN" ledger "Synced: merged $_ref" \
                   && git add -A && git commit -q -m "docs(ledger): synced" && git push -q origin HEAD ) >> "$CALLS/$n.log" 2>&1 ;;
    ```
    `STATE_BIN` inside the stub is the variable the stub already uses for ledger writes (`grep -n 'ledger' tests/overnight_lanes_test.sh | head -5`). Use it.
- [ ] **Step 2: Write the failing tests** in `tests/overnight_lanes_test.sh`. Fixture: `lanes_fixture syncX integration A:-` with A's plan at two tasks (the fixture's default is `task 0/1`: set `task 0/2` and add a Task 2, as `lanes_add_run` does). A's first unit is `auto` (task 1), and its scenario line 1 also moves `origin/integration/demo` through a helper: action `push_target <file>` commits a file to `integration/demo` on the origin through a temp clone. Add it as a stub action, or as a `waitfor` pre-step in the test.
  - `test_lanes_sync_clean_merge_no_session`:
    - after task 1, the target gains `other.txt` (no overlap);
    - before task 2 the lane merges it, so `git -C <story wt> log --format=%s -1 HEAD^2` exists and the subject `chore(sync): merge origin/integration/demo into A-b` is in A-b's history;
    - the stub call count for A is 2 (the task units plus the finish units as today: compare against the same fixture with no target move);
    - `events.jsonl` has `story_synced` with `"refs":["origin/integration/demo"]` and a `sha` equal to `git rev-parse` of that merge;
    - origin's `A-b` has the merge (the push refspec).
  - `test_lanes_sync_skips`: three sub-cases, each asserting the event field and no merge commit:
    - `skipped=dirty`: the stub's task-1 action leaves an untracked file (`dirtyfix` action);
    - `skipped=ahead`: it commits without pushing (`noop` plus a local commit);
    - `skipped=no-worktree`: it removes the story worktree.
  - `test_lanes_sync_integration_two_refs`: `origin/main` and `origin/integration/demo` both move. Two `chore(sync)` merges land in that order, and one event lists both refs.
  - `test_lanes_sync_failed_merge_aborts`:
    - a `pre-merge-commit` hook in the common git dir that exits 1 (verified in a trial: `merge-tree` exits 0, `merge` exits 1, `--abort` leaves the tree clean);
    - expect a `story_synced` `failed=merge`, the head unchanged, `git status --porcelain` empty, no `MERGE_HEAD`, and the story still lands (the hook is removed by the stub's task 2).
  - `test_lanes_sync_conflict_launches_repair`:
    - the target changes `A-T1.txt`, which task 1 wrote;
    - one call with kind `A.sync`: its `.env` has `STUDIO_REPAIR=sync:origin/integration/demo` and its argv has `--land`;
    - the `.sync` scenario is `syncrepair`;
    - the record went through `sync-repair`, then `running`, and the story lands;
    - the unit's row label is `sync-repair`.
  - `test_lanes_sync_repair_stops`: three sub-cases (a scenario each), each ending `stopped sync repair: …`, with no retry (one `.sync` call):
    - `stop` → `stop: …` text;
    - `noop` → `no progress`;
    - `hang` with a short `session_minutes` → `timed out (session_minutes`.
  - `test_lanes_no_sync_before_repairs`: the existing gate-repair and landing-repair fixtures (relocate with `grep -n 'test_lanes_gate_repair\|test_lanes_land_repair' tests/overnight_lanes_test.sh | head -3`) with the target moved before the repair. There is no `story_synced` event and no `chore(sync)` commit before the repair call's `t0`.

  In `tests/overnight_test.sh`: add `story_synced` to `test_events_contract_doc`'s list.
- [ ] **Step 3: Run them and see them fail.** `TESTS_ONLY="test_lanes_sync_clean_merge_no_session test_lanes_sync_failed_merge_aborts test_lanes_sync_conflict_launches_repair" sh tests/overnight_lanes_test.sh`. Expected: FAIL.
- [ ] **Step 4: Implement in SO.**
  - `unit_pre() { return 0; }`.
  - In `story_units`, after `_base` is computed and before `_before="$SIG"` (`grep -n '_before="\$SIG"; _base=' "$SO"`), split the line so `_base` comes first, then `unit_pre "$_base" || return 0`, then `_before="$SIG"`.
  - `model_for`: the `repair|final-repair|gate-repair` case becomes `repair|final-repair|gate-repair|sync-repair`.
  - The `story_units_table` regex in LN gains `sync-repair` (`grep -n 'gate-repair' "$LN" | head`).
- [ ] **Step 5: Implement in LN.** The hard part, in full:
  ```sh
  # unit_pre LABEL — the sync check (#39 AC24) before a task unit and the
  # final-review unit of a story; never before repairs, landing or the final
  # step (D34). 1 when the story must end (ENDING set).
  unit_pre() {
    [ -n "${CUR_ID:-}" ] && [ -n "${LDIR:-}" ] || return 0
    case "$1" in T[0-9]*|final-review) ;; *) return 0 ;; esac
    ! lane_halt || return 0
    sync_check "$CUR_ID"
  }
  # sync_emit ID MERGED — the merged event, when any ref merged.
  sync_emit() { [ -z "$2" ] || run_event story_synced "story=$1" "refs[]=$2" "sha=$(git -C "$SY_W" rev-parse HEAD)"; }
  # sync_check ID — merge each moved sync ref into the story branch (AC24-26).
  # A skip or failure is an event and never stops the story; a conflict
  # launches one sync repair. Writes no studio state.
  sync_check() {
    _sy_b="$(row_field "$1" branch)"
    SY_W="$(story_state "$1" worktree 2>/dev/null)" && [ -n "$SY_W" ] \
      && [ "$(git -C "$SY_W" symbolic-ref -q --short HEAD 2>/dev/null)" = "$_sy_b" ] \
      || { run_event story_synced "story=$1" skipped=no-worktree; return 0; }
    [ -z "$(git -C "$SY_W" status --porcelain 2>/dev/null)" ] || { run_event story_synced "story=$1" skipped=dirty; return 0; }
    git_retry -C "$SY_W" fetch -q origin || { run_event story_synced "story=$1" failed=fetch; return 0; }
    _sy_a="$(git -C "$SY_W" rev-list --count "refs/remotes/origin/$_sy_b..HEAD" 2>/dev/null)" || _sy_a=x
    [ "$_sy_a" = 0 ] || { run_event story_synced "story=$1" skipped=ahead; return 0; }
    _sy_refs="origin/$MF_TARGET"; [ "$MF_TARGET" = "$DEFAULT_BRANCH" ] || _sy_refs="$_sy_refs origin/$DEFAULT_BRANCH"
    _sy_done=""
    for _sy_r in $_sy_refs; do
      git -C "$SY_W" rev-parse -q --verify "refs/remotes/$_sy_r^{commit}" >/dev/null \
        || { sync_emit "$1" "$_sy_done"; run_event story_synced "story=$1" failed=merge-tree; return 0; }
      ! git -C "$SY_W" merge-base --is-ancestor "refs/remotes/$_sy_r" HEAD || continue
      _sy_rc=0; git -C "$SY_W" merge-tree --write-tree HEAD "refs/remotes/$_sy_r" >/dev/null 2>&1 || _sy_rc=$?
      case "$_sy_rc" in
        0) if ! git -C "$SY_W" merge -q --no-ff --no-edit -m "chore(sync): merge $_sy_r into $_sy_b" "refs/remotes/$_sy_r" >/dev/null 2>&1; then
             git -C "$SY_W" merge --abort >/dev/null 2>&1
             [ -z "$(git -C "$SY_W" status --porcelain 2>/dev/null)" ] || say "sync: $SY_W is not clean after merge --abort — left as is for the next unit"
             sync_emit "$1" "$_sy_done"; run_event story_synced "story=$1" failed=merge; return 0
           fi
           git_retry -C "$SY_W" push -q origin "HEAD:refs/heads/$_sy_b" \
             || { sync_emit "$1" "$_sy_done$_sy_r"; run_event story_synced "story=$1" failed=push; return 0; }
           _sy_done="$_sy_done${_sy_done:+,}$_sy_r" ;;
        1) sync_emit "$1" "$_sy_done"; sync_repair "$1" "$_sy_r"; return $? ;;
        *) sync_emit "$1" "$_sy_done"; run_event story_synced "story=$1" failed=merge-tree; return 0 ;;
      esac
    done
    sync_emit "$1" "$_sy_done"
    return 0
  }
  # sync_repair ID REF — one sync-repair unit (AC26), the landing-repair path:
  # `/game-dev:execute --land` with STUDIO_REPAIR=sync:REF. A new Synced: line
  # is progress; a new Stop:, no progress or a timeout end the story at once.
  sync_repair() {
    if lane_halt; then ENDING="$(lane_halt_reason)"; return 1; fi
    if run_budget_out; then ENDING="stop: run budget"; return 1; fi
    story_write "$1" sync-repair
    snapshot "$UNIT_DIR/sync.before"
    _sr_b="$(grep -c 'Synced:' "$(ledger_of "$1")" 2>/dev/null)"
    _sr_p="$PROMPT"; _sr_e="$LAUNCH_ENV"
    PROMPT="/game-dev:execute --land"; LAUNCH_ENV="$LAUNCH_ENV STUDIO_REPAIR=$(sq "sync:$2")"
    n=$((n + 1)); run_unit "$n" sync-repair
    PROMPT="$_sr_p"; LAUNCH_ENV="$_sr_e"
    if [ "$UNIT_HALTED" = 1 ]; then ENDING="$(lane_halt_reason)"; return 1; fi
    snapshot "$UNIT_DIR/sync.after"
    if new_stop "$UNIT_DIR/sync.before" "$UNIT_DIR/sync.after"; then ENDING="sync repair: $STOP_ENDING"; return 1; fi
    if [ "$(grep -c 'Synced:' "$(ledger_of "$1")" 2>/dev/null)" -gt "${_sr_b:-0}" ]; then
      story_write "$1" running; snapshot "$UNIT_DIR/stops.before"; return 0
    fi
    case "$(unit_outcome)" in
      "timed out"*) ENDING="sync repair: timed out (session_minutes $SESSION_MINUTES)" ;;
      *) ENDING="sync repair: no progress$(orphan_note)" ;;
    esac
    return 1
  }
  ```
  **Check against the real code before copying.** The names `ledger_of`,
  `new_stop`'s arguments, `STOP_ENDING`, `unit_outcome`'s output,
  `orphan_note`, `SESSION_MINUTES`, `DEFAULT_BRANCH`, `MF_TARGET` and the
  snapshot file pair are taken from `land_repair` and `gate_repair`
  (`grep -n '^land_repair()' -A40 "$LN"`). Mirror whatever those two do for:
  - the ledger path;
  - the Stop detection;
  - the row written for the unit (`row sync-repair …`, as `land_repair` writes `row repair …`).

  The sketch fixes the order and the endings. The helper names follow the
  file. `git_retry` takes the git arguments; check its signature with `sed -n 18,32p "$LN"`.
  - In `story_units`, a `unit_pre` return of 1 leaves `ENDING` set, and
    `run_story` writes `stopped $ENDING`, which is `stopped sync repair: <reason>`
    (verified: `run_story`'s `*) story_write "$1" "stopped $ENDING"`).
    `holdable` returns 1 for `sync repair: …` endings (verified), so the story stops without a hold.
  - The bridge `STATUS` and the events doc state list are in Task 14 and Step 6 here.
- [ ] **Step 6: Events doc.**
  - Add a row after `story_state`:
    `| \`story_synced\` | \`story\`, \`refs\`, \`sha\`, \`skipped\`, \`failed\` | merged: \`refs\` (array, in merge order) and \`sha\` (the new head); \`skipped\`: \`no-worktree\`, \`dirty\`, \`ahead\`; \`failed\`: \`fetch\`, \`merge-tree\`, \`merge\`, \`push\`; no event when every ref is already merged; a merged line comes before a later \`failed\` one |`
  - The `story_state` row's states gain `sync-repair`.
  - The optional-fields sentence (`grep -n 'No other field is optional' docs/game-dev/overnight-events.md`) gains: "`story_synced` carries either `refs` and `sha`, or `skipped`, or `failed`."
- [ ] **Step 7: Run the tests.** Run the Step 3 command, then `sh tests/overnight_lanes_test.sh` and `sh tests/overnight_test.sh`. Expected: exit 0.
- [ ] **Step 8: Commit.** `feat(overnight): stories sync with moved targets before each task (#39)` with the trailers.

---

### Task 14: Contract docs, READMEs, PROGRESS and the Multica bridge

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L80-88, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L257-257, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L296-299, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L385-385
Review: task
Wave: 6
Touches: `docs/game-dev/overnight-events.md`, `README.md`, `integrations/multica/README.md`, `docs/game-dev/PROGRESS.md`, `integrations/multica/bridge/mirror.py`, `integrations/multica/tests/test_mirror_runs.py`, `integrations/multica/tests/test_commands.py`

**Interfaces:**
- Produces:
  - the "Finding a run" section rewritten;
  - `mirror.py` maps `story_synced` to a comment, has `sync-repair` in `STATUS`, and ignores `session_wait`.
- Consumes: the event shapes from T12 and T13.

- [ ] **Step 1: Write the failing bridge tests.**
  - In `test_mirror_runs.py`'s `test_event_mapping_rows` table (relocate with `grep -n 'state="gate-repair"' integrations/multica/tests/test_mirror_runs.py`), add these rows:
    - `(ev("story_state", story="A", state="sync-repair"), "in_progress", None)`;
    - `(ev("story_synced", story="B", refs=["origin/main"], sha="abc1234"), None, "studio: synced origin/main (abc1234)")`;
    - `(ev("story_synced", story="B", skipped="dirty"), None, "studio: sync skipped: dirty")`;
    - `(ev("story_synced", story="B", failed="merge"), None, "studio: sync failed: merge")`;
    - `(ev("session_wait", lane="1", story="B", since="2026-10-04T01:00:00Z"), None, None)`.
  - Add `test_two_runs_one_root_mirrored`: two live registry entries with the same `root=` and different run dirs are both adopted and polled. Model it on `test_same_basename_two_roots`, line 86.
  - `test_commands.py`: the run-stop rows already assert `["stop","--run",B]`. Add one row naming a slug-style basename, to pin that the bridge passes the run dir basename (which `runs_match` accepts, D14).
- [ ] **Step 2: Run them and see them fail.** `sh integrations/multica/tests/run.sh`. Expected: FAIL on the new rows.
- [ ] **Step 3: Implement.**
  - `mirror.py`:
    - add `"sync-repair": "in_progress"` to `STATUS`;
    - in `event_writes`, after the `story_state` branch:
      ```python
      if e == "story_synced":
          if ev.get("refs"):
              return [say("synced %s (%s)" % (", ".join(map(str, ev.get("refs") or [])), str(ev.get("sha", "?"))[:7]))]
          if ev.get("skipped"):
              return [say("sync skipped: %s" % ev.get("skipped"))]
          return [say("sync failed: %s" % ev.get("failed", "?"))]
      ```
    - `session_wait` falls through to `return []` (ignored). Add a comment saying so.
    - The adoption of two entries with one root: if `test_two_runs_one_root_mirrored` fails, the tracking key must be the run dir, not the root. Check `state.tracked_keys` and fix only that.
  - `overnight-events.md` "Finding a run" (`grep -n '^## Finding a run' docs/game-dev/overnight-events.md`): rewrite it for:
    - per-run locks `<root>/.studio/runs/<slug>/lock` (`pid=`, `run=`, `started=`, `start=`) and the single-plan `.studio/overnight.lock`;
    - one root holding several live registry entries;
    - AC6's drop rule (a same-root entry is dropped only when not live);
    - AC13's resolution order, and `--run <slug|run dir basename>`;
    - `stop --run` writing the run's own flag.

    Keep the strings `test_events_contract_doc` asserts: `run=<run dir>`, `--run <run>`, `run <name> is not live`, `origin=`.
  - `README.md` and `integrations/multica/README.md`: one line each, verbatim from L88: "another run can be planned and started while one is live". Put it next to the overnight paragraph (`grep -n 'overnight' README.md | head -5`).
  - `docs/game-dev/PROGRESS.md`: add an entry in the file's format (`sed -n 1,30p docs/game-dev/PROGRESS.md`) for #39. Give the plan path and no merge sha; the merger fills that in.
- [ ] **Step 4: Run the tests.** `sh integrations/multica/tests/run.sh` and `sh tests/overnight_test.sh` (the contract doc test). Expected: exit 0.
- [ ] **Step 5: Commit.** `docs(overnight): concurrent runs in the contract, READMEs and bridge (#39)` with the trailers.

---

### Task 15: The Milestone round trip (gate step 3)

Spec: docs/game-dev/specs/2026-10-04-concurrent-runs.md:L31-38, docs/game-dev/specs/2026-10-04-concurrent-runs.md:L386-386
Review: final
Wave: 6
Touches: `tests/overnight_lanes_test.sh`

**Interfaces:** consumes everything above, plus three stub additions:
- the stub runs the peers hook at start;
- a `waitfor <path>` action modifier;
- `syncrepair` (T13).

- [ ] **Step 1: Stub additions.**
  - **Peers hook.** At start, after the env capture, the stub runs
    `sh "$STUB_PLUGIN/hooks/peer-runs.sh" < /dev/null > "$CALLS/$n.peers" 2>/dev/null`.
    It does this only when `STUDIO_UNIT_TAG` is set, which the runner exports.
    Check that `STUB_PLUGIN` points at the repo's `studios/game-dev`
    (`grep -n 'STUB_PLUGIN=' tests/overnight_lanes_test.sh`).
  - **`waitfor`.** A scenario line `waitfor <path> <action>` polls up to 60 s
    for `<path>`, then runs `<action>`. It is used to hold alpha's story mid-way
    until beta has landed.
- [ ] **Step 2: Write the tests.**
  - `test_lanes_round_trip_two_runs`:
    1. Set up the fixture:
       - `lanes_fixture rt integration X:-` provides the project and origin. X is a placeholder story that is never started.
       - `LANES_CONFIG='{"overnight": {"max_lanes": 1, "max_sessions": 2}}'` and `lanes_add_run alpha integration S1:-` give `RW_A`.
       - The same config with `lanes_add_run beta direct S2:-` gives `RW_B`.
       - Set `max_sessions` 2 in `$P/.studio/config.json` too, since it is read from the root.
    2. Write the scenarios:
       - S1 task 1: `auto`;
       - S1 task 2: `waitfor $P/.studio/runs/beta/landed.tsv.S2 auto`, which waits until beta's record shows S2 landed. Use a marker file written by a `merge-stub` hook, or poll `grep -q '^S2' landed.tsv` through a tiny `waitfor` script;
       - S2: `auto`, landing through the direct `merge-stub`.
    3. `bg_lanes alpha "$RW_A" start docs/runs/alpha.md`. Wait for `$P/.studio/runs/alpha/lock`, then `bg_lanes beta "$RW_B" start docs/runs/beta.md`. Each starts while the other is live.
    4. While both are live, `( cd "$P" && sh "$RUNNER" status )` shows:
       - line 1 `sessions: [0-2]/2`;
       - `== alpha (manifest`;
       - `== beta (manifest`.
    5. Bare `stop` exits 1, lists `alpha` and `beta`, and names `stop --run <slug>` and `stop --all`. Neither flag exists (the stop itself is in the third test).
    6. Wait for `bg_wait beta`, which ends 0 with S2 landed on `main`.
    7. Then alpha's S1 task 2 runs. Before it:
       - one `story_synced` event for S1 with refs `origin/integration/alpha`, `origin/main`;
       - the merge commit on `S1-b`;
       - no stub call between task 1 and task 2 other than task 2 itself (the sync ran no session).
    8. `assert_eq 2 "$(cat "$CALLS/max")"`, or `≤ 2` with at least one moment of 2: assert `[ "$(cat "$CALLS/max")" -le 2 ]`.
    9. Every `$CALLS/<n>.peers` of a unit started while the other run was live has `^Other live runs$` and the other run's slug.
  - `test_lanes_round_trip_stop_one_of_two`: the same pair, with S1 and S2 both `hang`.
    1. Start both, as above.
    2. Bare `stop` exits 1 and lists both runs (step 5 above).
    3. `stop --run alpha` writes only `$P/.studio/runs/alpha/stop`, and `bg_wait alpha` ends.
    4. Beta's lock is still held, its runner is alive, and no `beta/stop` exists.
    5. Clean up with `stop --run beta` and `bg_wait beta`.
  - `test_lanes_round_trip_sync_conflict`: the same pair, except beta's S2 changes `S1-T1.txt`, which S1's task 1 wrote. Alpha's task-2 sync conflicts, and exactly one `S1.sync` stub call (`syncrepair`) resolves it. Then S1 lands, and `stopped` appears nowhere in alpha's `landed.tsv`.
- [ ] **Step 3: Run them.** `TESTS_ONLY="test_lanes_round_trip_two_runs test_lanes_round_trip_sync_conflict test_lanes_round_trip_stop_one_of_two" sh tests/overnight_lanes_test.sh`. Expected: PASS. Earlier tasks built the behaviour; a failure here is a defect for a fresh fixer, not a test to bend.
- [ ] **Step 4: Run the whole suite.** `sh tests/overnight_lanes_test.sh`. Expected: exit 0.
- [ ] **Step 5: Commit.** `test(overnight): concurrent runs round trip (#39)` with the trailers.

---

## Final gate

After the final whole-branch review on Opus, and its fix wave if any:

- [ ] `sh tests/run_all.sh`. Expected: exit 0, with every suite green, the new `overnight_runs_test.sh`, `overnight_sessions_test.sh` and `studio_peers_test.sh` included (auto-discovered).
- [ ] `sh integrations/multica/tests/run.sh`. Expected: exit 0.
- [ ] Milestone step 3: `TESTS_ONLY="test_lanes_round_trip_two_runs test_lanes_round_trip_sync_conflict test_lanes_round_trip_stop_one_of_two" sh tests/overnight_lanes_test.sh`. Expected: PASS. It is part of the run above; run it alone once more and paste the output into the PR.
- [ ] `git diff origin/main --stat` lists only the files in File Structure, plus this plan.
- [ ] Public-repo hygiene:
  - `git diff origin/main | grep -n '/Users/\|/home/'` prints nothing new;
  - fixtures use only `S1`/`S2`/`A`/`B`/`X` ids and `alpha`/`beta`/`gamma`/`demo` slugs.
- [ ] **Operator-run, Milestone step 4 (after merge and a reinstall from a checkout with no live run):** on phoenix:
  1. plan run A in one `claude-gd` session and start it detached;
  2. while A runs, plan run B in a second session and start it;
  3. `studio-overnight status` shows both blocks and `sessions:`;
  4. both runs land.

  Record the result in `docs/game-dev/PROGRESS.md`.

---

## Falsify claims

Each claim is load-bearing for the plan. It was checked against the code at
85aa5eb, or in a trial script in the planner's scratchpad (macOS,
`/bin/sh` = bash 3.2, git 2.39.3).

| # | Claim | How checked | Result |
|---|---|---|---|
| 1 | `studio-state root` from a linked worktree prints the main checkout (first porcelain entry) | read studio-state:38-45; trial t2 (porcelain line 1 from `run-alpha` is the main path) | OK |
| 2 | `--git-dir` ≠ `--git-common-dir` exactly in a linked worktree | trial t2 | OK |
| 3 | `STUDIO_STORY` state is keyed on `STATE_ROOT`, the gate lock on `studio-state root` | read studio-state:46-51; studio-gate:37,41 | OK |
| 4 | `date +%s%N` gives nanoseconds on macOS | trial t1: prints `…N` | FIXED (D3 key) |
| 5 | bash 3.2 `$(( ))` is 64-bit (19-digit keys) | trial t1 | OK |
| 6 | `sleep 0.1` works in `/bin/sh` on macOS | trial t1 | OK |
| 7 | `mkdir` gives one winner of 20 racing takers | trial t1 | OK |
| 8 | `ln -s <pid> <path>` is an atomic mutex; `readlink` reads the owner | trial t1 | OK |
| 9 | In a lane subshell `$$` is the runner's pid, and `sh -c 'echo $PPID'` gives the lane's | trial t1; LN `LANE_PID` | OK |
| 10 | `merge-tree --write-tree`: exit 0 clean, 1 conflict | trial t2 | OK |
| 11 | `merge-tree` exits ≠1 for a missing ref | trial t2/t3: exits **1** | FIXED (D28: verify first) |
| 12 | A failed `git merge` followed by `merge --abort` leaves a clean tree | trial t2 (conflict) and t5 (pre-merge-commit hook) | OK |
| 13 | `merge --no-ff --no-edit -m S` keeps subject S and makes two parents | trial t2 | OK |
| 14 | `rev-list --count origin/X..HEAD` with no `origin/X` returns 0 | trial t2: exit 128 | FIXED (D29: failure = ahead) |
| 15 | A fetch from a linked worktree works with the fixture's remote | trial t2 (relative URL failed), t3 (absolute OK) | FIXED (fixtures use absolute URLs) |
| 16 | `ps -o args=` of a session launched through `claude-gd` contains `claude` | trial t4 | OK |
| 17 | `lanes_run` copies `rows.tsv` into the run dir before the lock | read LN `lanes_run` (1633-1680): after `acquire_run_lock` | FIXED (D9 `run_populate`) |
| 18 | The existing suites keep every assertion except `next:` (Milestone step 2) | read autopilot contract L48-77, studio_test `test_router_overnight_lock`, lanes ~1675/1689/1877/1938, progress L66 | FIXED (D1, needs a ruling) |
| 19 | AC8's "autopilot does this at AC12" names the archiving AC | read spec L147, L162-167, L178 | FIXED (D2: AC15) |
| 20 | T7 can change the lock path without touching the channel | read `chan_find_run` (reads `lock_live`'s run) and `chan_stop_run` (writes `overnight.stop`) | FIXED (T7 Step 6) |
| 21 | The bridge's `STATUS` covers every `story_state` value after #39 | read mirror.py:14, :457 | FIXED (T14 adds `sync-repair`) |
| 22 | `lanes_status`'s `pid:` line works per block | read LN 1241-1262 (`lock_pid` reads `$LOCK`) | FIXED (T7 sets `LOCK` per block) |
| 23 | `run_story` writes `stopped $ENDING`, so `sync repair: …` becomes `stopped sync repair: …` | read LN `run_story` (`*) story_write "$1" "stopped $ENDING"`) | OK |
| 24 | `holdable` does not hold a `sync repair:` ending | read SO 675-685 | OK |
| 25 | `snapshot`'s SIG has no HEAD, so a sync merge is not progress | read SO 523-548 | OK |
| 26 | New `tests/*_test.sh` suites are auto-discovered | read tests/run_all.sh | OK |
| 27 | New bin and hook files must be executable | read `test_bin_syntax` | OK (each task says `chmod +x`) |
| 28 | `test_events_contract_doc` needs new events added to its list and finds calls only in SO, LN, the channel and operator-inbox | read overnight_test.sh:208-240 | OK (`run_event` calls kept in LN; T12/T13 extend the list) |
| 29 | A third SessionStart entry keeps `test_inbox_hook_registered` (count 2, jq select by command) | read hook_test.sh:408-418 | OK |
| 30 | SessionStart hooks may print plain text | read operator-inbox.sh:129 (plain at SessionStart) | OK |
| 31 | `studio-state worktree` exits 0 and prints the story worktree path | read studio-state:364-406 | OK |
| 32 | A run-worktree session can enter a sibling story worktree, write story state at the root, and take the gate lock under the runner's permissions | needs a live model session | UNVERIFIED (T1 probe, operator-run) |
| 33 | Two live runs on phoenix both land | live | UNVERIFIED (Milestone step 4, operator-run) |

Counts: OK 21 · FIXED 10 · UNVERIFIED 2.

---

## Task order

| Wave | Tasks | Why |
|---|---|---|
| 0 | T1 | The probe gates the whole design (Milestone step 1); no implementation starts until the operator reports PASS. |
| 1 | T2, T3, T4, T5 | Independent: studio-state; the new runs lib; skill texts; the autopilot skill. Disjoint files, tests included. |
| 2 | T6, T7, T8, T9 | Each needs T3's lib (`runs_live`, `mx_*`, `runs_plan_files`, `runs_worktree_of`); T7's fixture uses T2's `init --local`. Disjoint: T6 sessions lib; T7 SO, LN, channel, overnight and lanes tests; T8 peers, hook, hooks.json, hook test; T9 studio-adopt. |
| 3 | T10, T11 | T10 builds on T7's `runs_live` use in SO, the channel and `fake_mrun` (SO, channel, overnight_test). T11 builds on T7's `lock_recheck`, `run_paths` and `lanes_add_run`, and T8's `studio-peers --files` (LN, lanes test). Disjoint files; only one of them edits SO and one edits LN. |
| 4 | T12 | Needs T6's lib and T7's run_unit/status loop. Edits SO and LN, so it is alone. |
| 5 | T13 | Needs T12's `UNIT_HALTED` and the stub changes. Edits SO and LN, so it is alone. |
| 6 | T14, T15 | T14 needs T12's and T13's events (docs, bridge). T15 needs everything. Disjoint: T14 never touches the lanes test, and T15 touches only it. |

After wave 6, the final whole-branch review runs on Opus, then the fix wave, then the Final gate.
