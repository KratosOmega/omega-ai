# An Adopted Story Starts from Its Own Run Worktree — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Approved (2026-10-06). D1-D6 ruled by the user; delivered through subagent-driven execution, the final whole-branch review and its fix wave.

**Goal:** `studio-adopt seed` and `sync` must find an adopted story's run worktree even when that worktree has no `.studio/run`. They must never quietly read another live run's ledger, Target and manifest. Each failure must name what was read and where the missing line actually is. An adopted story that was never seeded can neither rebuild to task 1 nor start overnight.

**Architecture:**
- `studios/game-dev/bin/studio-adopt`:
  - `start_checkout` becomes a four-tier lookup, `sc_resolve`. It returns the checkout and its manifest, so `run_target` and `run_manifest` read the manifest of the checkout that was resolved, through `start_manifest`.
  - The `no adopted line` / `no ledger` refusals name the ledger that was read and the start checkout. Through `adopted_hint` they also name any other worktree's ledger that holds the line.
- `studios/game-dev/bin/studio-state`: `check --rebuild` under `STUDIO_STORY` refuses an adopted, started story that this checkout never seeded (`adopt_guard`).
- `studios/game-dev/bin/overnight-lanes.sh`: `mf_check` ends with `mf_ready`. It refuses to start when the start checkout has no `.studio/run` (or one naming no manifest of this run), or when an adopted story with a branch has no `adopt-base` in its story ledger.
- `shared/omega/skills/autopilot/SKILL.md`:
  - discovery re-creates a missing `.studio/run`;
  - step 3 ledgers and seeds from the run worktree;
  - a failed seed stops.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2, Linux `dash`), git ≥ 2.38, BSD/GNU sed and awk. No new dependencies.

**Spec:** GitHub issue #50 plus the user-approved rulings D1–D6, written out in *Design* below. This story has no separate spec file. Acceptance checks are cited as `A<n>`.

Story: #50 (GitHub issue). Branch `issue-50-adopt-run-worktree-seed`. omega-ai has no Jira, so the branch carries no `KAN-` prefix.

**Base:** 81691ab (origin/main, with #39, #41, #42 and #47 merged). Line numbers below are taken at that commit. Relocate each one with its `grep -n` pattern.

**Prototype:** every hard-part code block and test below was run in a scratch copy of the repo at 81691ab (macOS, bash 3.2, git 2.39.3):
- `studio_adopt_test.sh` 258/0, plus all 26 new studio-adopt assertions green (T1 17, T2 9). At 81691ab the T1 tier tests fail 11 of their 15 assertions: seed exits 1 with `no adopted line`, and `run_target` prints `integration/other`, which is exactly the 10-05 symptom.
- `state_test.sh` 234/0, plus the new guard test 8/0.
- The lanes adopt tests plus the two new readiness tests: 29/0.
- The full `overnight_lanes_test.sh` with the fixture change.

**Review policy (user CLAUDE.md):**
- Each task carries `Spec:`, `Review: task|final`, `Wave:`, `Touches:` and a risk tag under its heading.
- `Review: task` means a per-task review on Opus (`model: "opus"`). It applies to the risky seams: the tier lookup (T1), the rebuild guard (T3) and the start readiness check (T4).
- The mechanical tasks (T2 messages, T5 skill text) are `Review: final`.
- Minor findings are batched into the final fix wave. Every fix round goes to a fresh fixer, given the findings and the diff range.
- Re-review only after a Critical, three or more Importants, or a production-bug fix. Never a third pass.
- The final review is a standalone whole-branch review on Opus (T6), followed by the full gate.
- One task = one implementer.
  - Wave-mates run in parallel, each in its own worktree branched from the story branch. Their Touches are disjoint, tests included. Integrate by cherry-pick into the story branch.
  - Each implementer commits only its own paths: `git commit -m '<msg>' -- <paths>`.
  - Hand-backs are 1.5k characters or less, with the full report in a file.
- Suites:
  - Each task runs only the suites it names.
  - `tests/overnight_test.sh` and `tests/overnight_lanes_test.sh` never run at the same time: only T4 runs the full lanes suite, and no task runs `overnight_test.sh` before the gate.
  - The integrated full gate (`sh tests/run_all.sh`, which runs every `tests/*_test.sh` one after another) runs once, after the final fix wave.
- **Live run:** a live overnight run executes the main checkout's installed scripts. Never edit, pull into or reinstall from `/Users/xinli/GameDev/proj/omega-ai` or `~/.claude-gamedev` during this story. The change lands by PR merge only.

---

## Design

Rulings D1–D6 were approved by the user and are not re-opened here. Each ruling below is followed by the code facts it rests on, checked at 81691ab, and the plan-level refinements those facts force. The refinements are marked **R**.

**D1 — start_checkout resolves in tiers.**
1. A `run/*` worktree (the main checkout included) whose `.studio/run` manifest has a row for ID. This is today's rule; two hits still refuse.
2. Otherwise, a `run/*` worktree with no `.studio/run` whose committed `docs/runs/<slug>.md` (for `run/<slug>`) has a row for ID. It is used, with a one-line stderr note.
3. Otherwise, when the main checkout is on `run/*` (another run's checkout), refuse with a message that:
   - says no run worktree was found for ID;
   - says what was looked for;
   - names every run worktree checked;
   - says that the main checkout is on `run/<other>`.
4. Otherwise (no run involved: a manual adopt), `state_root`, as today.

Facts:
- The committed manifest path is `docs/runs/<slug>.md`: autopilot SKILL.md:86 writes it and :100 points `.studio/run` at it.
- The slug charset excludes `/` (`mf_check`, overnight-lanes.sh:163), so `run/<slug>` maps 1:1 to the file.
- `.studio/run` is never committed. Autopilot never `git add`s it.
- `start_checkout` (studio-adopt:85-100) falls back silently to `state_root`.
- `run_target` (:258-268) and `run_manifest` (:568-578) re-read `<checkout>/.studio/run`, so they would miss a tier-2 manifest.
- R1: `sc_resolve ID` prints `<checkout><TAB><manifest or empty>`. `start_checkout` prints its first field; `start_manifest` prints its second, or the manifest named by `$STUDIO_START_DIR/.studio/run` when that variable is set (AC20 of #39).
- R2: tier 2 considers only worktrees whose `.studio/run` is missing or empty. A pointer that names another manifest is the operator's explicit choice and is not second-guessed.
- R3: the tier-2 note prints once per invocation. A marker `$TMPD/sc.noted` does this. The marker is skipped when `TMPD` is unset or missing, because `test_adopt_run_target_from_start_checkout` sources the script with `TMPD` pointing at a directory that does not exist.
- R4: `cmd_inspect` sets `START_ROOT` (it never did), so `plan_file` and `docs_paths` read the resolved checkout and not the main one. This is a same-class latent bug. `inspect` already calls `run_target "$ID"`, so it already goes through the lookup.
- Fix wave (final review I1): "main checkout not on `run/*`" is not the same as "no run involved". Tier 3 also refuses when a checked `run/*` worktree's ledger has an `adopted` line for ID (truth region), for example a run worktree whose `.studio/run` is missing and whose manifest is not committed yet, or whose pointer names a missing file. Tier 4 is reached only when no run is involved. A pointer naming a missing file is listed as `.studio/run → missing <pointer>`.
- Behaviour change (D1 as ruled; final review M7): a manual adopt (no run) while another run holds the main checkout (on `run/<other>`) now refuses at tier 3. Before #50 it silently used the other run's ledger and Target. The way through is `STUDIO_START_DIR=<checkout holding the story's adopted line>`. Its Target, if any, is then the one read; it only narrows part-done filtering.

**D2 — the refusals name what was read.** The `no adopted line` refusals in `cmd_seed` (:449) and `cmd_sync` (:719), and sync's `no ledger` refusal (:716), name:
- the ledger file that was read;
- the start checkout;
- when another worktree's ledger has an `adopted` line for ID, where that line is: "ledger it from the start checkout".

**D3 — the restart guard.** Facts:
- The only from-scratch progress computation is `check --rebuild` under `STUDIO_STORY` (studio-state:886-907). It sets `task k/N` unconditionally, so it can lower progress.
- The non-story path (:928-931) only ever raises the count.
- "Adopted" is known from an `adopted <orig> -> <conv>` line in a story ledger's truth region (the lines after the last `adopt reset`).
- "Seeded" leaves an `adopt-base` line. Seed writes it unconditionally (studio-adopt `sd_add`, ~:511), and so does execute §0's new-branch path (execute SKILL.md:127-129).
- `sync` requires that line (:722).
- "Started" means the pointer's branch is not `-`. Seed refuses a pointer with no branch (:455-457).
- R5: `adopt_guard` runs first in the story-rebuild branch. It refuses (exit 1) when all three hold:
  1. the branch is set;
  2. this checkout's ledger has no `adopt-base` in its truth region;
  3. some worktree's ledger has an `adopted` line for the story.

  Non-adopted stories, and not-started adopted ones, are unaffected.

**D4 — a failed seed stops.** Facts:
- `studios/game-dev/skills/execute/SKILL.md` never calls `studio-adopt seed`. It calls only `sync` (:115, :136-137, :228-230), and it already stops on exit 1/2.
- The only caller of `seed` is autopilot SKILL.md:150 (step 3.3).
- R6: the stop rule goes into autopilot step 3.3, on its own line (`test_autopilot_adopt_order` compares offsets inside the 3.3 line). Execute is unchanged.

**D5 — the run's start checkout is ready before it starts.** Facts:
- Manifest starts all go through `lanes_start` (overnight-lanes.sh:1977), which runs `mf_check` (:161-288). `mf_check` has that single caller, used by `start`, `start --dry-run` and `--detach`'s foreground dry run (and by #49's planned `lanes_start --check`).
- Its `refuse` (studio-overnight:95) accumulates problems; exit 2 follows.
- `START_DIR` is `root --work` of the cwd (studio-overnight:457). Manifest start never reads `.studio/run`; only `next` does (:1814).
- `story_ledger_text` (:1257) needs `RUN_DIR`, which is unset at preflight, so the check reads files and git directly.
- Seed runs in the story worktree on the story branch (studio-adopt:455-458) and writes that checkout's ledger. So "seeded" lives in the story worktree's ledger, or on the story branch. It is never in the start checkout.
- R7: `mf_ready`, the last step of `mf_check` before `mf_overlap_warn`, refuses with one line per problem:
  - `START_DIR` has no `.studio/run`;
  - a manifest story is adopted (an `adopted` line in `START_DIR`'s ledger, else in any worktree's ledger) and its Branch exists locally or on origin, but its story ledger (the worktree's file when there is one, else the branch's committed file) has no `adopt-base`.

  A not-started adopted story (no branch yet) is skipped, because execute §0 records its base.
- R8: `lanes_fixture` (tests/overnight_lanes_test.sh:528) never wrote `.studio/run`. The real flow always does (autopilot :100). The fixture now writes it (git-excluded), otherwise R7 would fail every manifest-start test.
- The autopilot changes:
  - discovery also lists a `run/*` worktree that has no `.studio/run` but has a committed `docs/runs/<slug>.md`, and rewrites the pointer on resume;
  - step 3 ledgers `adopted` from the run worktree;
  - step 3 seeds only once the run worktree has `.studio/run`;
  - the readiness checklist names the new dry-run checks.

  "Seeds adopted stories from the run worktree" is read as: seed runs in the story worktree (it must, per :455) and resolves the run worktree as its start checkout.

**D6 — tests, red before the fix.**
- `tests/studio_adopt_test.sh` gets an `incident_repo` fixture. It has the main checkout on `run/other` with its own `.studio/run` and manifest (a live run), plus a run worktree on `run/kan` that holds the adopted story. The cases:
  - tier 2;
  - tier 1;
  - the tier-3 refusal;
  - the adopted line only in the main checkout's ledger (D2);
  - sync's message.
- The rebuild guard test goes in `tests/state_test.sh`.
- The readiness test goes in `tests/overnight_lanes_test.sh`. That suite owns manifest start and `mf_check`; `overnight_runs_test.sh` is helper unit tests only, and `overnight_test.sh` covers single-plan starts only.

### Acceptance checks

- A1: From the story worktree, with the run worktree lacking `.studio/run` and the main checkout on another live run:
  - `studio-adopt seed S1` exits 0 and prints `seeded: 6 lines`;
  - stderr carries the tier-2 note exactly once;
  - `start_checkout`, `start_manifest` and `run_target` name the run worktree, its `docs/runs/kan.md` and `integration/kan`;
  - `sync` exits 0.
- A2: With `.studio/run` present, seed exits 0 and prints no note.
- A3: No run worktree lists S1, and the main checkout is on `run/other`. Seed and sync exit 1 with `no run worktree found for S1: looked for…`, naming both checked worktrees and `the main checkout <P> is on run/other`, and never `no adopted line`.
- A4: The adopted line is only in the main checkout's ledger.
  - Seed's refusal names `<RK>/.studio/ledger/S1.md`, `(start checkout <RK>)` and `an adopted line for S1 is in <P>/.studio/ledger/S1.md — ledger it from the start checkout`.
  - Sync's names `<W>/.studio/ledger/S1.md` and the same hint.
- A5: For an adopted, started, unseeded story, `check --rebuild` exits 1, names both ledgers and `studio-adopt seed`, and leaves `task` untouched. After `adopt-base` is ledgered it rebuilds. With branch `-` it rebuilds as before.
- A6: `studio-overnight start --dry-run <manifest>` exits 2:
  - when the start checkout has no `.studio/run` (naming the checkout);
  - when an adopted story with a branch is unseeded (naming the story, the branch and `studio-adopt seed <id> in <worktree>`).

  After the fix it exits 0.
- A7: Every existing suite stays green: today's tier-1 behaviour, two-listing refusal, spaced paths, the `STUDIO_START_DIR` precedence and the no-id `run_target`.
- A8: The autopilot skill text carries the D4/D5 rules, pinned by `autopilot_contract.sh`.

---

## Global Constraints

- POSIX sh only. Print text with `printf '%s\n'`, never `echo` with `\n`: macOS `sh` is bash 3.2, whose `echo` expands escapes. That was a falsify finding in this plan.
- No new temp files in `sc_resolve` except the optional `$TMPD/sc.noted` marker (R3).
- Worktree records are TAB-separated and never word-split. A project path may hold a space (`test_adopt_start_checkout_spaced_path`).
- New shell variables use a fresh function prefix:
  - studio-adopt: `_sc_`, `_sk_`, `_sm_`, `_ax_` (`_ae_` is `adopt_evidence`'s);
  - studio-state: `_ag_`;
  - overnight-lanes: `rd_truth`, `rd_adopted` (`_ra_`), `mf_ready` (`_rd_`). `_mr_` is `mx_reap`'s in overnight-runs.sh.
- **Fixed texts** (quote exactly; the tests grep them):
  - tier-2 note: `note: run worktree <W> has no .studio/run — using its committed docs/runs/<slug>.md for <id>`
  - tier-3 refusal begins `no run worktree found for <id>: looked for a run/* worktree whose .studio/run (or, without one, committed docs/runs/<slug>.md) has a row for <id>; checked: <W> (run/<s>, .studio/run); <W2> (run/<s2>, no .studio/run); <W3> (run/<s3>, .studio/run → missing <pointer>)[; the main checkout <P> is on run/<other>[ (another run)]][; an adopted line for <id> is in <ledger>[, <ledger>…]] — write .studio/run in <id>'s run worktree (printf '%s\n' docs/runs/<slug>.md > .studio/run), or set STUDIO_START_DIR`
    - It refuses when the main checkout is on `run/*`, **or** when a checked `run/*` worktree's ledger has an `adopted` line for <id> (final review I1: a run is involved but tiers 1-2 missed its worktree; never the tier-4 fallback). The main-checkout clause appears only in the first case; ` (another run)` is dropped when the main checkout's own ledger has the `adopted` line (it may be <id>'s own run, missing the row).
  - two hits (unchanged): `story <id> is listed by two run worktrees: <W1>, <W2>`
  - seed: `no adopted line for <id> in <ledger> (start checkout <S>)` + hint
  - sync: `no ledger for <id> on <Branch> (<ledger>; start checkout <S>) — run: studio-adopt seed <id>` + hint
  - sync: `no adopted line for <id> in <ledger> (the ledger of <Branch>; start checkout <S>) — run: studio-adopt seed <id>` + hint
  - hint: `; an adopted line for <id> is in <ledger>[, <ledger>…] — ledger it from the start checkout`
  - guard: `studio-state: check --rebuild: <id> is adopted (<ledger>) but <this ledger> has no adopt-base line — never seeded here; a rebuild would restart it from task 1. Run studio-adopt seed <id> in the checkout of <Branch> first.`
  - readiness: `start checkout <dir> has no .studio/run — write it there: printf '%s\n' <manifest> > .studio/run`, `start checkout <dir>: .studio/run names <pointer>, not this run's manifest — write it there: printf '%s\n' <manifest> > .studio/run` (the pointer, relative to <dir> or absolute, must name an existing file whose `# Run:` slug is this run's; final review M2), and `<id>: adopted (<ledger>) but not seeded on <Branch> — run studio-adopt seed <id> in <worktree or "the <Branch> worktree">, then STUDIO_STORY=<id> studio-state check --rebuild there`
- Exit codes: studio-adopt refusals 1 (as today); studio-state `fail` 1; the lanes preflight 2 (as today).
- Test fixtures use only the `S1`/`S9`/`AD`/`A` ids and the `kan`/`other`/`demo`/`alpha` slugs. No `/Users/` paths.

## Review Focus

Most likely first. Each line has the test that pins it.

1. **A resumed or re-started run whose adopted story already ran.** Its ledger has `adopt-base`, or its branch is gone after landing. Readiness must pass. Pinned by `test_lanes_adopt_round_trip` (second start of a run with a seeded story), which T4 keeps green.
2. **Two pointer-less run worktrees both commit a manifest that lists the id.** That must refuse like two tier-1 hits, never pick one. T1 adds `test_adopt_incident_tier2_two_refuse`.
3. **A seeded but not yet committed story ledger** (the operator just ran seed in the story worktree). Readiness reads the worktree file before the branch's committed copy, so it passes. Pinned by `test_lanes_ready_adopted_unseeded`'s second dry run, which seeds without committing.
4. **A manual adopt with no run anywhere** (the main checkout on `main`, no `run/*` worktree). Tier 4 keeps today's `state_root` behaviour. Pinned by every `adopt_repo`/`sync_repo` test, which run exactly like that.
5. **The run worktree path holds a space.** `sc_resolve` keeps TAB records end to end. Pinned by `test_adopt_start_checkout_spaced_path` (tier 1). The tier-2 branch reads the same records.

---

## Prerequisites — re-run the anchor greps

Before a task edits a file, its implementer re-runs the greps for the anchors it touches. Trust the pattern, not the number.

```sh
SA=studios/game-dev/bin/studio-adopt; SS=studios/game-dev/bin/studio-state; LN=studios/game-dev/bin/overnight-lanes.sh
grep -n '^state_root()\|^start_checkout()\|^start_root()\|^plan_file()\|^run_target()\|^docs_paths()' "$SA"   # 77 85 105 112 258 279
grep -n '^cmd_inspect()\|^cmd_seed()\|^run_manifest()\|^manifest_branch()\|^cmd_sync()' "$SA"                # 339 427 568 580 671
grep -n 'no adopted line\|no ledger for\|STATE_ROOT="\$(state_root)"' "$SA"                                    # 449 716 719; 353 438 674
grep -n '^ledger_file()\|^truth_lines()\|^# plan_task_count FILE\|"\$rebuild" = "1" \]; then' "$SS"          # 556 564 572 886
grep -n '^story_state()\|^mf_check()\|^mf_overlap_warn()\|done < "\$MF_TMP/stories"\|^lanes_start()' "$LN"    # 76 161 137 282 1977
grep -n '^lanes_fixture()\|git push -q origin run/demo$\|^adopt_lanes_fixture()\|seed S1; sh "\$STATE_BIN" check --rebuild\|^run_tests' tests/overnight_lanes_test.sh
grep -n 'studio-adopt seed\|runs being planned\|Write the pointer\|Readiness checklist\|adopted <original> -> <new plan>' shared/omega/skills/autopilot/SKILL.md  # 150 57 100 159 142
```

---

## File Structure

| File | Task | Change |
|---|---|---|
| `studios/game-dev/bin/studio-adopt` | T1, T2 | `sc_resolve`/`start_checkout`/`start_manifest`; `run_target`, `run_manifest`, `cmd_inspect` callers; `adopted_hint` and three messages |
| `tests/studio_adopt_test.sh` | T1, T2 | `incident_repo`, `adopt_lib`; 6 tests |
| `studios/game-dev/bin/studio-state` | T3 | `adopt_guard`, one call |
| `tests/state_test.sh` | T3 | 1 test |
| `studios/game-dev/bin/overnight-lanes.sh` | T4 | `rd_truth`, `rd_adopted`, `mf_ready`, one call in `mf_check` |
| `tests/overnight_lanes_test.sh` | T4 | `lanes_fixture` pointer, `adopt_lanes_fixture` `ALF_NOSEED`, 2 tests |
| `shared/omega/skills/autopilot/SKILL.md` | T5 | discovery, step 3, readiness text |
| `tests/omega_contracts/autopilot_contract.sh` | T5 | `test_autopilot_adopt_ready` |
| `docs/game-dev/PROGRESS.md` | T6 | log entry |

---

## Tasks

### Task 1: studio-adopt — the tier lookup

Spec: D1, R1–R4; A1–A3, A7
Review: task (Opus) · **risky** (new seam: every studio-adopt caller resolves through it)
Wave: 1
Touches: `studios/game-dev/bin/studio-adopt`, `tests/studio_adopt_test.sh`

**Interfaces:**
- Produces:
  - `sc_resolve ID`: on stdout, `<checkout>\t<manifest or empty>`, status 0. On a refusal (two hits in a tier, or tier 3): one stderr line, status 1.
  - `start_checkout ID`: the checkout. Same status.
  - `start_manifest ID`: the manifest path or nothing; status 0, or 1 when `sc_resolve` refuses. `$STUDIO_START_DIR/.studio/run` wins when that variable is set.
  - The test helpers `incident_repo NAME [noptr]` (sets `P`, `W`, `RK`, `BASE`, `C1..C3`) and `adopt_lib` (writes `$TMP/adopt.lib`).
  - T2 builds on these.
- Consumes: the existing `state_root`, `manifest_branch`, `TAB`, `TMPD` and `start_root` (unchanged; it calls `start_checkout`).

- [ ] **Step 1: Read** `start_checkout`, `start_root`, `run_target`, `run_manifest`, `cmd_inspect` (to `TARGET=`), and the fixtures `adopt_repo`, `build_adopt_tpl`, `run_wt`, `move_adoption_lines` and `test_adopt_run_target_from_start_checkout` (grep above).
- [ ] **Step 2: Write the failing tests.** Add them after `test_adopt_seed_start_dir_wins`, and add every name to the `run_tests` line (`TESTS_ONLY` skips unlisted names).

```sh
# incident_repo NAME [noptr] — 10-05 (#50): adopt_repo NAME 6 3, then a run
# worktree $RK on run/kan whose committed docs/runs/kan.md lists S1 and whose
# ledger holds S1's source/adopted lines (moved out of $P's), with
# .studio/run unless noptr; and $P switched to run/other with its own
# committed docs/runs/other.md (S9 only) and .studio/run — another live run.
incident_repo() {
  adopt_repo "$1" 6 3
  RK="$TMP/$1-run-kan"
  ( set -e
    git -C "$P" worktree add -q -b run/kan "$RK" main
    mkdir -p "$RK/docs/runs"
    printf '# Run: kan\nTarget: integration/kan\n\n| Story | Branch |\n|---|---|\n| S1 | S1-b |\n' > "$RK/docs/runs/kan.md"
    move_adoption_lines "$P" "$RK"
    git -C "$RK" add docs/runs/kan.md .studio/ledger/S1.md
    git -C "$RK" commit -q -m "docs(run): kan manifest"
    [ "${2:-}" = noptr ] || printf 'docs/runs/kan.md\n' > "$RK/.studio/run"
    git -C "$P" switch -q -c run/other
    mkdir -p "$P/docs/runs"
    printf '# Run: other\nTarget: integration/other\n\n| Story | Branch |\n|---|---|\n| S9 | S9-b |\n' > "$P/docs/runs/other.md"
    git -C "$P" add docs/runs/other.md
    git -C "$P" commit -q -m "docs(run): other manifest"
    printf 'docs/runs/other.md\n' > "$P/.studio/run"
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "incident_repo $1: setup failed"; }
}
# adopt_lib — studio-adopt as a sourceable library at $TMP/adopt.lib.
adopt_lib() { sed -e '$d' -e "s|^SELF_DIR=.*|SELF_DIR=\"$(dirname "$ADOPT")\"|" "$ADOPT" > "$TMP/adopt.lib"; }

test_adopt_incident_seed_tier2() {
  incident_repo it2 noptr
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "no .studio/run in the run worktree: seed still exits 0"
  assert_eq "seeded: 6 lines" "$(cat "$TMP/ad.out")" "seeded from the run worktree's ledger"
  assert_contains "$TMP/ad.err" "note: run worktree $RK has no .studio/run — using its committed docs/runs/kan.md for S1" "one note names the committed manifest"
  assert_eq 1 "$(grep -c '^note: run worktree' "$TMP/ad.err")" "the note prints once per invocation"
  adopt_lib
  ( cd "$W" && . "$TMP/adopt.lib" && TMPD="$TMP/it2.d" && mkdir -p "$TMPD" \
      && { start_checkout S1; start_manifest S1; run_target S1; } > "$TMP/it2.out" ) 2>/dev/null
  assert_eq "$RK
$RK/docs/runs/kan.md
integration/kan" "$(cat "$TMP/it2.out")" "start_checkout, start_manifest and run_target name the run worktree"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "and sync passes"
}

test_adopt_incident_seed_tier1() {
  incident_repo it1
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "with .studio/run: seed exits 0"
  assert_not_contains "$TMP/ad.err" "note:" "and prints no note"
}

test_adopt_incident_tier2_two_refuse() {
  incident_repo it22 noptr
  _r2="$TMP/it22-run-kan2"
  ( set -e; git -C "$P" worktree add -q -b run/kan2 "$_r2" run/kan
    sed 's/^# Run: kan$/# Run: kan2/' "$_r2/docs/runs/kan.md" > "$_r2/docs/runs/kan2.md"
    git -C "$_r2" add docs/runs/kan2.md; git -C "$_r2" commit -q -m "docs(run): kan2 manifest" ) >/dev/null 2>&1
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "two pointer-less run worktrees list S1: refused"
  assert_contains "$TMP/ad.err" "story S1 is listed by two run worktrees: " "same message as two tier-1 hits"
}

test_adopt_incident_no_run_worktree_refuses() {
  incident_repo inr noptr
  ( cd "$RK" && git rm -q docs/runs/kan.md && git commit -q -m drop ) >/dev/null 2>&1
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "no run worktree lists S1, main on another run: seed refuses"
  assert_contains "$TMP/ad.err" "no run worktree found for S1: looked for" "says what it looked for"
  assert_contains "$TMP/ad.err" "checked: $P (run/other, .studio/run); $RK (run/kan, no .studio/run)" "names every run worktree checked"
  assert_contains "$TMP/ad.err" "the main checkout $P is on run/other" "and the main checkout's run"
  assert_not_contains "$TMP/ad.err" "no adopted line" "not the misleading ledger error"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "sync refuses the same way"
  assert_contains "$TMP/ad.err" "no run worktree found for S1" "sync message"
}
```

`test_adopt_incident_tier2_two_refuse` (green in the prototype): its `kan2` worktree is branched from `run/kan`, so it also carries `kan.md`. Only `docs/runs/kan2.md` matters for `run/kan2`.

- [ ] **Step 3: Run them red.**
  `TESTS_ONLY="test_adopt_incident_seed_tier2 test_adopt_incident_seed_tier1 test_adopt_incident_tier2_two_refuse test_adopt_incident_no_run_worktree_refuses" sh tests/studio_adopt_test.sh`.
  Expected: FAIL. `seed` exits 1 with `no adopted line for S1 in the start checkout`, and `run_target` prints `integration/other`. Tier 1 passes already.
- [ ] **Step 4: Implement.** Replace `start_checkout` (:85-100) with the block below, keeping the header comment style. `start_root` is unchanged.

```sh
# sc_resolve ID — ID's start checkout and its run manifest, as
# "<checkout><TAB><manifest or empty>" (#50 D1):
#   1. a run/* worktree (the main checkout included) whose .studio/run names a
#      manifest with a row for ID (#39 AC20, D40);
#   2. else a run/* worktree with no .studio/run whose committed
#      docs/runs/<slug>.md (for run/<slug>) has a row for ID — with a one-line
#      stderr note, once per invocation;
#   3. else, when the main checkout is on run/* (another run's checkout),
#      refuse, naming what was looked for and every run worktree checked;
#   4. else state_root and the manifest its .studio/run names (no run: a
#      manual adopt).
# Two hits in one tier refuse. Status 1 after a refusal (one stderr line).
# No temp files: callers source this with TMPD unset or missing.
sc_resolve() {
  _sc_id="$1"
  # One record per line, never word-split: a project path may hold a space.
  _sc_all="$(git worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{ w = substr($0, 10) } /^branch refs\/heads\/run\//{ print w "\t" substr($0, 23) }' \
    | while IFS="$TAB" read -r _sc_w _sc_s; do
        _sc_m="$(head -n 1 "$_sc_w/.studio/run" 2>/dev/null)"
        if [ -n "$_sc_m" ]; then
          [ "${_sc_m#/}" != "$_sc_m" ] || _sc_m="$_sc_w/$_sc_m"   # relative to the worktree
          printf 'seen\t%s (run/%s, .studio/run)\n' "$_sc_w" "$_sc_s"
          if [ -f "$_sc_m" ] && [ -n "$(manifest_branch "$_sc_m" "$_sc_id")" ]; then printf '1\t%s\t%s\n' "$_sc_w" "$_sc_m"; fi
        else
          _sc_c="docs/runs/$_sc_s.md"
          printf 'seen\t%s (run/%s, no .studio/run)\n' "$_sc_w" "$_sc_s"
          if git -C "$_sc_w" ls-files --error-unmatch -- "$_sc_c" >/dev/null 2>&1 && [ -f "$_sc_w/$_sc_c" ] \
             && [ -n "$(manifest_branch "$_sc_w/$_sc_c" "$_sc_id")" ]; then printf '2\t%s\t%s\n' "$_sc_w" "$_sc_w/$_sc_c"; fi
        fi
      done)"
  for _sc_t in 1 2; do
    _sc_h="$(printf '%s\n' "$_sc_all" | awk -F'\t' -v t="$_sc_t" '$1 == t { print $2 "\t" $3 }')"
    _sc_n="$(printf '%s' "$_sc_h" | grep -c .)"
    if [ "$_sc_n" -gt 1 ]; then
      echo "story $_sc_id is listed by two run worktrees: $(printf '%s\n' "$_sc_h" | cut -f1 | paste -sd, - | sed 's/,/, /g')" >&2; return 1
    fi
    [ "$_sc_n" = 1 ] || continue
    if [ "$_sc_t" = 2 ] && [ ! -e "${TMPD:-/nonexistent}/sc.noted" ]; then
      : > "${TMPD:-/nonexistent}/sc.noted" 2>/dev/null || true
      _sc_w="${_sc_h%%"$TAB"*}"
      echo "note: run worktree $_sc_w has no .studio/run — using its committed ${_sc_h#*"$TAB""$_sc_w"/} for $_sc_id" >&2
    fi
    printf '%s\n' "$_sc_h"; return 0
  done
  _sc_r="$(state_root)"
  _sc_b="$(git -C "$_sc_r" symbolic-ref -q --short HEAD 2>/dev/null || true)"
  case "$_sc_b" in
    run/*)
      printf '%s\n' "no run worktree found for $_sc_id: looked for a run/* worktree whose .studio/run (or, without one, committed docs/runs/<slug>.md) has a row for $_sc_id; checked: $(printf '%s\n' "$_sc_all" | sed -n 's/^seen	//p' | paste -sd';' - | sed 's/;/; /g'); the main checkout $_sc_r is on $_sc_b (another run) — write .studio/run in $_sc_id's run worktree (printf '%s\\n' docs/runs/<slug>.md > .studio/run), or set STUDIO_START_DIR" >&2
      return 1 ;;
  esac
  _sc_m="$(head -n 1 "$_sc_r/.studio/run" 2>/dev/null || true)"
  case "$_sc_m" in ''|/*) ;; *) _sc_m="$_sc_r/$_sc_m" ;; esac
  [ -n "$_sc_m" ] && [ -f "$_sc_m" ] || _sc_m=""
  printf '%s\t%s\n' "$_sc_r" "$_sc_m"
}

# start_checkout ID — sc_resolve's checkout.
start_checkout() {
  _sk_l="$(sc_resolve "$1")" || return 1
  printf '%s\n' "${_sk_l%%"$TAB"*}"
}

# start_manifest ID — the run manifest of ID's start checkout: the one
# $STUDIO_START_DIR/.studio/run names when STUDIO_START_DIR is set, else
# sc_resolve's. Nothing when none.
start_manifest() {
  if [ -n "${STUDIO_START_DIR:-}" ]; then
    _sm_m="$(head -n 1 "$STUDIO_START_DIR/.studio/run" 2>/dev/null || true)"
    case "$_sm_m" in ''|/*) ;; *) _sm_m="$STUDIO_START_DIR/$_sm_m" ;; esac
  else
    _sm_l="$(sc_resolve "$1")" || return 1
    _sm_m="${_sm_l#*"$TAB"}"
  fi
  if [ -n "$_sm_m" ] && [ -f "$_sm_m" ]; then printf '%s\n' "$_sm_m"; fi
  return 0
}
```

  - The `sed -n 's/^seen	//p'` holds a literal TAB. Keep it as a TAB, or write `"s/^seen$TAB//p"`.
  - The tier-3 text is printed with `printf '%s\n'`, because `echo` would turn its `\\n` into a newline under bash-sh.
  - `manifest_branch` is defined later in the file. That is fine: it is called at run time.
  - **Callers:**
    - `run_target`: when `STUDIO_RUN` is empty and an id is given, `_rt_m="$(start_manifest "$1")" || return 1`. Keep the no-id branch (`state_root`'s `.studio/run`), which `test_adopt_run_target_from_start_checkout` pins.
    - `run_manifest`: when `IN_RUN` is empty, `_rm_m="$(start_manifest "$ID")" || return 1`, then print it when it is a file.
    - `cmd_inspect`: after `TOPLEVEL=`, add `START_ROOT="$(start_root "$ID")" || return 1` (R4).
  - The R1 side effect: with `STUDIO_START_DIR` set and `STUDIO_RUN` unset, `run_target` now reads that directory's `.studio/run`. In `test_adopt_seed_start_dir_wins` `TARGET` becomes empty. That is harmless: `TARGET` only filters merges in `part_done` (:249), and the test stays green.
- [ ] **Step 5: Run green.** Run the Step 3 command; expected PASS. Then:
  - `sh tests/studio_adopt_test.sh`, expected 0 failed (258 baseline + new);
  - `TESTS_ONLY="test_lanes_adopt_seeded_runs_rest test_lanes_adopt_round_trip test_lanes_adopt_sync_fail_holds" sh tests/overnight_lanes_test.sh`, expected 0 failed. Their fixture's main checkout is on `run/demo` without `.studio/run`, so seed now resolves through tier 2 instead of the fallback.
- [ ] **Step 6: Commit** `fix(studio-adopt): find the run worktree without .studio/run; never read another run's (#50)` with the trailers, `-- studios/game-dev/bin/studio-adopt tests/studio_adopt_test.sh`.

**Acceptance:**
- A1–A3 hold.
- `test_adopt_start_checkout_*`, `test_adopt_seed_*` and `test_adopt_run_target_from_start_checkout` are unchanged and green.

---

### Task 2: studio-adopt — the refusals name what was read

Spec: D2; A4
Review: final · **mechanical**
Wave: 2 (after T1, same files)
Touches: `studios/game-dev/bin/studio-adopt`, `tests/studio_adopt_test.sh`

**Interfaces:**
- Consumes: T1's `incident_repo`, `START_ROOT` set in seed and sync, and `truth_lines FILE` (studio-adopt :270).
- Produces: `adopted_hint ID SKIP…`, which prints the hint fragment or nothing, always status 0.

- [ ] **Step 1: Write the failing tests** (add them to `run_tests`):

```sh
test_adopt_incident_adopted_line_in_main_ledger() {
  incident_repo iml
  move_adoption_lines "$RK" "$P"
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "adopted line only in the main checkout's ledger: seed refuses"
  assert_contains "$TMP/ad.err" "no adopted line for S1 in $RK/.studio/ledger/S1.md (start checkout $RK)" "names the ledger read and the start checkout"
  assert_contains "$TMP/ad.err" "an adopted line for S1 is in $P/.studio/ledger/S1.md — ledger it from the start checkout" "and where the line is"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "sync refuses too"
  assert_contains "$TMP/ad.err" "no ledger for S1 on S1-b ($W/.studio/ledger/S1.md; start checkout $RK) — run: studio-adopt seed S1" "sync names the ledger it looked for"
  assert_contains "$TMP/ad.err" "an adopted line for S1 is in $P/.studio/ledger/S1.md" "and the hint"
}

test_sync_no_adopted_line_names_ledger() {
  sync_repo nal
  grep -v ' adopted ' "$W/.studio/ledger/S1.md" > "$TMP/nal.led"; cp "$TMP/nal.led" "$W/.studio/ledger/S1.md"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "no adopted line in the story ledger: sync refuses"
  assert_contains "$TMP/ad.err" "no adopted line for S1 in $W/.studio/ledger/S1.md (the ledger of S1-b; start checkout $P) — run: studio-adopt seed S1" "names the ledger and the start checkout"
  assert_not_contains "$TMP/ad.err" "an adopted line for S1 is in" "no hint when only the start checkout has the line"
}
```

- [ ] **Step 2: Run red:** `TESTS_ONLY="test_adopt_incident_adopted_line_in_main_ledger test_sync_no_adopted_line_names_ledger" sh tests/studio_adopt_test.sh`. Expected FAIL: the old texts.
- [ ] **Step 3: Implement.** Add `adopted_hint` before `# docs_paths ID`:

```sh
# adopted_hint ID SKIP… — #50 D2: when a worktree other than SKIP… has an
# `adopted` line for ID in its .studio/ledger/ID.md (truth region), print
# "; an adopted line for ID is in <ledgers> — ledger it from the start
# checkout"; else nothing. Appended to the "no adopted line" refusals.
adopted_hint() {
  _ax_id="$1"; shift
  _ax_hits="$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r _ax_w; do
      for _ax_s in "$@"; do [ "$_ax_w" = "$_ax_s" ] && continue 2; done
      _ax_f="$_ax_w/.studio/ledger/$_ax_id.md"
      if [ -f "$_ax_f" ] && truth_lines "$_ax_f" | grep -q '^- [0-9-]* adopted .* -> '; then printf '%s\n' "$_ax_f"; fi
    done | paste -sd, - | sed 's/,/, /g')"
  [ -z "$_ax_hits" ] || printf '; an adopted line for %s is in %s — ledger it from the start checkout' "$_ax_id" "$_ax_hits"
}
```

  Then change the three refusals:
  - seed (:449): `echo "no adopted line for $ID in $_sd_src (start checkout $START_ROOT)$(adopted_hint "$ID" "$START_ROOT")" >&2`
  - sync (:716): `echo "no ledger for $ID on $BRANCH ($_sy_led; start checkout $START_ROOT) — run: studio-adopt seed $ID$(adopted_hint "$ID" "$TOPLEVEL" "$START_ROOT")" >&2`
  - sync (:719): `echo "no adopted line for $ID in $_sy_led (the ledger of $BRANCH; start checkout $START_ROOT) — run: studio-adopt seed $ID$(adopted_hint "$ID" "$TOPLEVEL" "$START_ROOT")" >&2`

  Sync skips the start checkout in the hint, because there the line is where it belongs and the fix is "run seed".
- [ ] **Step 4: Run green:** the Step 2 command, then `sh tests/studio_adopt_test.sh` (0 failed). Grep the suite for the old texts (`grep -n 'in the start checkout\|in the ledger of' tests/studio_adopt_test.sh`) and update any assertion that quoted them.
- [ ] **Step 5: Commit** `fix(studio-adopt): name the ledger read and where the adopted line is (#50)`, `-- studios/game-dev/bin/studio-adopt tests/studio_adopt_test.sh`.

**Acceptance:** A4 holds; the suite is green.

---

### Task 3: studio-state — the restart guard

Spec: D3, R5; A5
Review: task (Opus) · **risky** (data: progress a rebuild may lower; cross-system with seed and execute §0)
Wave: 1
Touches: `studios/game-dev/bin/studio-state`, `tests/state_test.sh`

**Interfaces:**
- Consumes: `field`, `ledger_file`, `truth_lines` and `fail` (studio-state :556-566; `fail` exits 1 with `studio-state: `).
- Produces: `adopt_guard`, a call before the story rebuild. There is no new CLI surface.

- [ ] **Step 1: Read** `check` (:874-940), `ledger_file`, `truth_lines` and `set_branch` (it does not validate that the branch exists, so the fixture can name `AD-b` before creating it).
- [ ] **Step 2: Write the failing test** in `tests/state_test.sh` (add it to `run_tests`, :677):

```sh
test_state_rebuild_refuses_unseeded_adopted() {
  P="$TMP/story-ad"; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    sh "$STATE_BIN" init
    printf '# P\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md
    export STUDIO_STORY=AD; sh "$STATE_BIN" init
    sh "$STATE_BIN" set plan docs/p.md; sh "$STATE_BIN" set task 0/3; sh "$STATE_BIN" set branch AD-b
    sh "$STATE_BIN" ledger "adopted docs/o.md -> docs/p.md"
    git worktree add -q -b AD-b "$TMP/story-ad-wt" ) >/dev/null 2>&1
  W="$TMP/story-ad-wt"
  st=0; ( cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "unseeded adopted story: check --rebuild exits 1"
  assert_contains "$TMP/out" "AD is adopted ($P/.studio/ledger/AD.md) but $W/.studio/ledger/AD.md has no adopt-base line" "names both ledgers"
  assert_contains "$TMP/out" "studio-adopt seed AD" "and the fix"
  assert_eq 0/3 "$(cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" get task)" "task untouched"
  st=0; ( cd "$P" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 1 "$st" "from the checkout holding the adopted line too"
  ( cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" ledger "adopt-base 0123456789abcdef0123456789abcdef01234567" \
      && STUDIO_STORY=AD sh "$STATE_BIN" ledger "T1 complete aaaa..bbbb" ) >/dev/null 2>&1
  st=0; ( cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 0 "$st" "seeded (adopt-base): the rebuild runs"
  assert_eq 1/3 "$(cd "$W" && STUDIO_STORY=AD sh "$STATE_BIN" get task)" "and counts the seeded tasks"
  ( cd "$P" && STUDIO_STORY=AD sh "$STATE_BIN" set task 0/3 && STUDIO_STORY=AD sh "$STATE_BIN" set branch - ) >/dev/null 2>&1
  st=0; ( cd "$P" && STUDIO_STORY=AD sh "$STATE_BIN" check --rebuild ) > "$TMP/out" 2>&1 || st=$?
  assert_eq 0 "$st" "a not-started adopted story (branch -) rebuilds as before"
}
```

- [ ] **Step 3: Run red:** `TESTS_ONLY=test_state_rebuild_refuses_unseeded_adopted sh tests/state_test.sh`. Expected FAIL: exit 0 at `0/3`.
- [ ] **Step 4: Implement.** Insert this before `# plan_task_count FILE`:

```sh
# adopt_guard — #50 D3, before check --rebuild under STUDIO_STORY: refuse an
# adopted, started story this checkout never seeded. Adopted: some worktree's
# .studio/ledger/<id>.md has an `adopted` line after its last `adopt reset`.
# Started: the story pointer has a branch. Seeded here: this checkout's ledger
# has an `adopt-base` line after its last `adopt reset` (seed and execute §0's
# new-branch path write it). Otherwise the rebuild would set task 0/N and the
# story would restart from task 1.
adopt_guard() {
  _ag_b="$(field branch)"
  case "$_ag_b" in ''|-) return 0 ;; esac
  _ag_lf="$(ledger_file)"
  if [ -f "$_ag_lf" ] && truth_lines "$_ag_lf" | grep -q '^- [0-9-]* adopt-base '; then return 0; fi
  _ag_at="$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r _ag_w; do
      _ag_f="$_ag_w/.studio/ledger/$STORY.md"
      if [ -f "$_ag_f" ] && truth_lines "$_ag_f" | grep -q '^- [0-9-]* adopted .* -> '; then printf '%s\n' "$_ag_f"; fi
    done | head -n 1)"
  [ -n "$_ag_at" ] || return 0
  fail "check --rebuild: $STORY is adopted ($_ag_at) but $_ag_lf has no adopt-base line — never seeded here; a rebuild would restart it from task 1. Run studio-adopt seed $STORY in the checkout of $_ag_b first."
}
```

  Call it as the first line inside `if [ -n "$STORY" ] && [ "$rebuild" = "1" ]; then` (:886). Only the story-rebuild branch gets it.
- [ ] **Step 5: Run green:**
  - the Step 3 command;
  - `for f in tests/state_*_test.sh; do sh "$f" || echo "FAIL $f"; done` (state_test 234 baseline, plus guard/move/pointer/stories);
  - `sh tests/studio_adopt_test.sh`: seed then sync's own `check --rebuild` (studio-adopt :786) must still pass, since seed wrote `adopt-base` first;
  - `TESTS_ONLY="test_lanes_adopt_seeded_runs_rest test_lanes_adopt_round_trip test_lanes_adopt_sync_fail_holds" sh tests/overnight_lanes_test.sh`.
- [ ] **Step 6: Commit** `fix(studio-state): check --rebuild refuses an adopted story never seeded here (#50)`, `-- studios/game-dev/bin/studio-state tests/state_test.sh`.

**Acceptance:**
- A5 holds.
- Every `state_*` suite is green, and so are the studio-adopt and lanes-adopt suites.
- No non-adopted story's rebuild changes: the guard returns before any git call unless the branch is set and `adopt-base` is absent.

---

### Task 4: overnight-lanes — the start readiness check

Spec: D5, R7, R8; A6
Review: task (Opus) · **risky** (cross-system: every manifest start goes through it; the fixture change touches every lanes test)
Wave: 1
Touches: `studios/game-dev/bin/overnight-lanes.sh`, `tests/overnight_lanes_test.sh`

**Interfaces:**
- Consumes: `MF`, `MF_ROWS` (TSV, id first and Branch second), `MF_TMP`, `START_DIR`, `refuse`, `story_state` (overnight-lanes :76) and `mf_check`'s tail (`done < "$MF_TMP/stories"`, then `mf_overlap_warn`).
- Produces: `rd_truth` (stdin to truth lines), `rd_adopted ID` (the first ledger with an `adopted` line: `START_DIR`'s, else any worktree's) and `mf_ready`.
- Test knob: `ALF_NOSEED=1` makes `adopt_lanes_fixture` skip its seed and rebuild.
- #49 coordination:
  - #49 (plan on branch `49-preflight-worktree-setup`) adds `setup_preflight` inside `lanes_start` after `mf_check`, and a `lanes_start --check` mode. Both go through `mf_check`, so `mf_ready` runs first in every mode, and this task does not touch `lanes_start`.
  - #49's new tests use `lanes_fixture`, which now writes `.studio/run`, so they pass `mf_ready`.
  - The only expected merge overlap is the `run_tests` list (and PROGRESS.md in T6). Whichever PR merges second takes both sides.

- [ ] **Step 1: Read** `mf_check` (:161-288), `lanes_start` (:1977-1998), `lanes_fixture` (:528-600), `adopt_lanes_fixture` (:2881-2915) and `run_lanes`.
- [ ] **Step 2: Fixture changes** (the real flow always writes the pointer, at autopilot :100):
  - in `lanes_fixture`, right after `git add -A && git commit -q -m manifest && git push -q origin run/demo`:
    ```sh
    printf '.studio/run\n' >> "$(git rev-parse --git-common-dir)/info/exclude"; printf '%s\n' "$MFP" > .studio/run
    ```
  - in `adopt_lanes_fixture`, replace `sh "$ADOPT_BIN" seed S1; sh "$STATE_BIN" check --rebuild` with
    ```sh
    [ "${ALF_NOSEED:-}" = 1 ] || { sh "$ADOPT_BIN" seed S1; sh "$STATE_BIN" check --rebuild; }
    ```
- [ ] **Step 3: Write the failing tests.** Put them before `test_lanes_adopt_seeded_runs_rest`. In `run_tests`, insert `test_lanes_ready_needs_run_pointer test_lanes_ready_adopted_unseeded \` just before `test_lanes_no_orphans`, which must stay last.

```sh
test_lanes_ready_adopted_unseeded() {
  ALF_NOSEED=1; adopt_lanes_fixture rau; unset ALF_NOSEED
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "an unseeded adopted story refuses the start"
  assert_contains "$LS_ERR" "S1: adopted (.*) but not seeded on S1-b" "names the story and branch"
  assert_contains "$LS_ERR" "studio-adopt seed S1 in $AW" "and the fix, in its worktree"
  ( cd "$AW" && sh "$ADOPT_BIN" seed S1 && STUDIO_STORY=S1 sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "seeded: the dry run passes"
}
test_lanes_ready_needs_run_pointer() {
  lanes_fixture rnp integration A:-
  rm -f "$P/.studio/run"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "no .studio/run: refused"
  assert_contains "$LS_ERR" "start checkout $P has no .studio/run" "names the checkout"
  printf '%s\n' "$MFP" > "$P/.studio/run"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "with the pointer: the dry run passes"
}
```

  `ALF_NOSEED=1; …; unset ALF_NOSEED` is used because a prefix assignment on a shell function is not portable.
- [ ] **Step 4: Run red:** `TESTS_ONLY="test_lanes_ready_needs_run_pointer test_lanes_ready_adopted_unseeded" sh tests/overnight_lanes_test.sh`. Expected FAIL: both dry runs exit 0.
- [ ] **Step 5: Implement.** In `mf_check`, add `mf_ready` on its own line between `done < "$MF_TMP/stories"` and `mf_overlap_warn`. Define these right after `mf_check`:

```sh
# rd_truth — stdin's lines after its last `adopt reset` line (all of them when
# there is none): the truth region every adopt reader uses (#35 D2).
rd_truth() { awk '/^- [0-9-]+ adopt reset /{ n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }'; }

# rd_adopted ID — the first ledger with an `adopted` line for ID in its truth
# region: START_DIR's, else any worktree's (#50 case b: ledgered from the
# wrong checkout). Nothing when none.
rd_adopted() {
  { printf '%s\n' "$START_DIR"; git -C "$START_DIR" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'; } \
    | while IFS= read -r _ra_w; do
        _ra_f="$_ra_w/.studio/ledger/$1.md"
        if [ -f "$_ra_f" ] && rd_truth < "$_ra_f" | grep -q '^- [0-9-]* adopted .* -> '; then printf '%s\n' "$_ra_f"; break; fi
      done
}

# mf_ready — #50 D5: the start checkout is ready for this run. One refuse per
# problem: START_DIR has no .studio/run; an adopted story whose branch exists,
# locally or on origin, but whose story ledger (its worktree's, else the
# branch's) has no `adopt-base` line: never seeded, so its first unit would
# start at task 1. A not-started adopted story (no branch yet) is skipped:
# execute §0 records its adopt-base. Reads files and git only (RUN_DIR is not
# set yet, so story_ledger_text cannot be used).
mf_ready() {
  if [ -z "$(head -n 1 "$START_DIR/.studio/run" 2>/dev/null)" ]; then
    refuse "start checkout $START_DIR has no .studio/run — write it there: printf '%s\\n' ${MF#"$START_DIR"/} > .studio/run"
  fi
  awk -F'\t' '!($1 in s) { s[$1] = 1; print $1 "\t" $2 }' "$MF_ROWS" > "$MF_TMP/ready"
  while IFS='	' read -r _rd_id _rd_b; do
    printf '%s\n' "$_rd_id" | grep -Eq '^[A-Za-z0-9._-]+$' || continue
    case "$_rd_b" in ''|-) continue ;; esac
    _rd_l="$(rd_adopted "$_rd_id")"; [ -n "$_rd_l" ] || continue
    git -C "$START_DIR" rev-parse -q --verify "refs/heads/$_rd_b^{commit}" >/dev/null 2>&1 \
      || git -C "$START_DIR" rev-parse -q --verify "refs/remotes/origin/$_rd_b^{commit}" >/dev/null 2>&1 \
      || continue
    _rd_w="$(story_state "$_rd_id" worktree 2>/dev/null)" || _rd_w=""
    { if [ -n "$_rd_w" ] && [ -f "$_rd_w/.studio/ledger/$_rd_id.md" ]; then cat "$_rd_w/.studio/ledger/$_rd_id.md"
      else git -C "$START_DIR" show "refs/heads/$_rd_b:.studio/ledger/$_rd_id.md" \
        || git -C "$START_DIR" show "refs/remotes/origin/$_rd_b:.studio/ledger/$_rd_id.md"
      fi; } 2>/dev/null | rd_truth | grep -q '^- [0-9-]* adopt-base ' && continue
    refuse "$_rd_id: adopted ($_rd_l) but not seeded on $_rd_b — run studio-adopt seed $_rd_id in ${_rd_w:-the $_rd_b worktree}, then STUDIO_STORY=$_rd_id studio-state check --rebuild there"
  done < "$MF_TMP/ready"
}
```

  - `'	'` in `IFS='	'` is a literal TAB, as elsewhere in this file.
  - `MF` here is the manifest path `mf_load` set. When `START_DIR` is its prefix, the hint shows the relative path.
  - A single-plan start (no manifest) never reaches `mf_check`, so it is unchanged.
- [ ] **Step 6: Run green:**
  - the Step 4 command;
  - `TESTS_ONLY="test_lanes_adopt_seeded_runs_rest test_lanes_adopt_round_trip test_lanes_adopt_sync_fail_holds" sh tests/overnight_lanes_test.sh`;
  - then the **full** `sh tests/overnight_lanes_test.sh` (it takes a while; run nothing from `overnight_test.sh` meanwhile). Expected 0 failed.

  Tests that start other manifests (`os.md`, `bf.md`, `docs/runs/<f>.md` from a run worktree) still pass: the check needs *a* `.studio/run` in the start checkout, never one naming this manifest.
- [ ] **Step 7: Commit** `feat(overnight): refuse to start until the start checkout is ready — .studio/run, adopted stories seeded (#50)`, `-- studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh`.

**Acceptance:** A6 holds, and the full lanes suite is green with the pointer in `lanes_fixture`.

---

### Task 5: autopilot skill — re-create the pointer, seed from the run worktree, stop on a failed seed

Spec: D4 (R6), D5 (autopilot part); A8
Review: final · **mechanical**
Wave: 1
Touches: `shared/omega/skills/autopilot/SKILL.md`, `tests/omega_contracts/autopilot_contract.sh`

**Interfaces:** the skill text only. The literals below are pinned by the new contract function, so the implementer writes them verbatim.

- [ ] **Step 1: Read** autopilot SKILL.md :52-64 (discovery), :96-102 (the pointer), :139-157 (step 3) and :159-166 (readiness), plus `test_autopilot_adopt_order` and `test_autopilot_discovery_lists_runs` in the contract. Every new sentence goes on its **own line**: `test_autopilot_adopt_order` compares offsets inside the step-3.3 line ("In that worktree, only"), and the step-3 `adopted` bullet must stay above `Each story, not-started and half-done alike`.
- [ ] **Step 2: Write the failing contract.** Add `test_autopilot_adopt_ready` to `autopilot_contract.sh`, and call it after `test_autopilot_adopt_order` in the list that calls it:

```sh
# #50: the run worktree's pointer is re-created, adopted lines and seeds come
# from the run worktree, a failed seed stops, readiness names the new checks.
test_autopilot_adopt_ready() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  for lit in 'a run worktree with no `.studio/run` whose `docs/runs/<slug>.md` is committed' \
    'rewrite the missing pointer first' \
    'ledgered from the run worktree, never from the main checkout' \
    'the run worktree has `.studio/run` before the first seed' \
    'A failed seed stops here' \
    'never run `studio-state check --rebuild`, `next` or the start after it' \
    "the start checkout's \`.studio/run\`" \
    'every adopted story with a branch seeded on it'; do
    assert_contains "$S" "$lit" "autopilot #50: $lit"
  done
}
```

- [ ] **Step 3: Run red:** `sh tests/omega_test.sh` (it runs the contracts). Expected: the 8 new assertions fail, and the 495 baseline passes.
- [ ] **Step 4: Edit the skill** (new lines, wording around the pinned literals is free):
  - Discovery, after the `runs being planned` bullet (:57), a new sub-bullet: "also a run worktree with no `.studio/run` whose `docs/runs/<slug>.md` is committed (`git -C <dir> ls-files --error-unmatch docs/runs/<slug>.md`, for `run/<slug>`): list it the same way. On resume, rewrite the missing pointer first: `printf '%s\n' docs/runs/<slug>.md > .studio/run` in that worktree. The pointer is uncommitted local state, so a re-created worktree loses it."
  - Step 3, the adopted bullet (:142): add "— ledgered from the run worktree, never from the main checkout (`studio-state ledger` writes the ledger of the checkout the shell is in)". The literal `studio-state ledger "adopted <original> -> <new plan>"` stays as it is.
  - Step 3, a new bullet before the adopted bullet: "Check that the run worktree has `.studio/run` before the first seed (write it as in step 1 when missing): `studio-adopt seed` finds the story's run through it, and falls back to the committed manifest only with a note."
  - Step 3.3, a new line right after the `In that worktree, only` line: "A failed seed stops here: when `studio-adopt seed <id>` exits non-zero, print its stderr line and stop; never run `studio-state check --rebuild`, `next` or the start after it (a rebuild of an unseeded adopted story refuses anyway)."
  - Readiness (:162), inside the dry-run line's parenthesis, after `no conflicting live or stopped run (slug, story, branch)`: ", the start checkout's `.studio/run`, every adopted story with a branch seeded on it".
- [ ] **Step 5: Run green:** `sh tests/omega_test.sh` (0 failed) and `sh tests/pointer_skills_omega_test.sh` (0 failed).
- [ ] **Step 6: Commit** `docs(autopilot): re-create .studio/run, seed from the run worktree, stop on a failed seed (#50)`, `-- shared/omega/skills/autopilot/SKILL.md tests/omega_contracts/autopilot_contract.sh`.

**Acceptance:**
- A8 holds.
- `test_autopilot_adopt_order` and `test_autopilot_discovery_lists_runs` are still green.
- execute SKILL.md is untouched (R6).

---

### Task 6: PROGRESS, final review, gate, PR

Spec: all; A1–A8
Review: — (this task *is* the final review) · **mechanical**
Wave: 3
Touches: `docs/game-dev/PROGRESS.md` (plus whatever the fix wave touches)

- [x] **Step 1:** Add a log entry at the top of `## Log` in `docs/game-dev/PROGRESS.md`, `### 2026-10-06 — Adopted story starts from its own run worktree (#50)`. It covers:
  - the root cause (a missing `.studio/run` fell back to the main checkout's run; an adopted line ledgered from the main checkout);
  - the four tiers;
  - the messages;
  - the rebuild guard;
  - the start readiness check;
  - the autopilot rules;
  - the operator note: after merge, reinstall only from a checkout with no live run (memory: no pull while a run is live).

  Commit it with `-- docs/game-dev/PROGRESS.md`.
- [x] **Step 2: Final whole-branch review** on Opus (`model: "opus"`), standalone, over `git diff origin/main...HEAD`. Give it this plan's Design, Global Constraints and Review Focus. Ask it to try:
  - a run worktree with a stale `.studio/run` naming a deleted file;
  - the main checkout on `run/*` with a pointer listing the id;
  - a resumed run;
  - execute §0's window between `set branch` and the `adopt-base` line (no rebuild runs there);
  - #49's `--check` path.
- [x] **Step 3: Fix wave**, one fresh fixer given the findings and the diff range. Re-review only after a Critical, three or more Importants, or a production-bug fix.
- [ ] **Step 4: Full gate:** `sh tests/run_all.sh`, expected exit 0. It runs the suites one at a time, so the two overnight suites never overlap. Then:
  - `git diff origin/main --stat` lists only the File Structure files plus this plan;
  - `git diff origin/main | grep -n '/Users/\|/home/'` prints nothing new.
- [ ] **Step 5: PR** into `main`, `Closes #50`, with the PR trailer. Merge once the gate is green (memory: omega-ai merge authority). Never pull or reinstall into the main checkout while a live run is going; the change lands by merge only. Afterwards remove the agent worktrees and, once merged, the story worktree.

---

## Task order

| Wave | Tasks | Why |
|---|---|---|
| 1 | T1 (risky), T3 (risky), T4 (risky), T5 (mechanical) | Disjoint files, tests included: studio-adopt plus its suite; studio-state plus state_test; overnight-lanes plus the lanes suite; the autopilot skill plus its contract. T3 and T4 read only on-disk ledger formats (`adopted`, `adopt-base`), never T1's functions. Only T4 runs the full lanes suite; T1 and T3 run three lanes adopt tests by `TESTS_ONLY`, which is safe to overlap (each suite run uses its own `mktemp -d`). |
| 2 | T2 (mechanical) | Same files as T1. Needs `incident_repo` and `START_ROOT` resolution. |
| 3 | T6 | PROGRESS, the final Opus review, the fix wave, the gate, the PR. |

Per-task reviews (Opus) for T1, T3 and T4 run as each hands back. T2 and T5 fold into the final review.

---

## Falsify claims

Checked against the code at 81691ab, or in the planner's scratch copy (macOS, `/bin/sh` = bash 3.2, git 2.39.3).

| # | Claim | How checked | Result |
|---|---|---|---|
| 1 | The committed manifest of `run/<slug>` is `docs/runs/<slug>.md` | autopilot SKILL.md:86, :100; mf_check slug charset :163 | OK |
| 2 | `.studio/run` is never committed, so a re-created worktree has none | autopilot :100-101 (`git add` list omits it); repro `no-runptr` | OK |
| 3 | `start_checkout` falls back silently to `state_root` | studio-adopt :85-100 | OK |
| 4 | `run_target`/`run_manifest` re-read `<checkout>/.studio/run`, so tier 2 needs a manifest hand-off | :258-268, :568-578 | FIXED (R1 `start_manifest`) |
| 5 | `cmd_inspect` sets `START_ROOT` | :339-360: it does not | FIXED (R4) |
| 6 | The no-id `run_target` must keep `state_root` | `test_adopt_run_target_from_start_checkout` (rt.none) | OK (kept) |
| 7 | `sc_resolve` may write temp files | the same test sets `TMPD` to a missing dir after sourcing | FIXED (R3: optional marker) |
| 8 | `echo` prints a literal `\n` in the tier-3 hint | trial: bash-sh `echo` expanded it into a newline | FIXED (`printf '%s\n'`) |
| 9 | The 10-05 shape is red at 81691ab and green after T1 | prototype: 11 of 15 T1 tier assertions fail at 81691ab (`integration/other`), 0 after | OK |
| 10 | execute SKILL calls `studio-adopt seed` | grep: only `sync` (:115, :136, :228); the only seed caller is autopilot :150 | FIXED (R6: rule goes in autopilot) |
| 11 | "Seeded" can be checked in the start checkout | seed runs on the story branch in the story worktree and writes *its* ledger (:455-458) | FIXED (R7: story worktree or branch ledger) |
| 12 | `check --rebuild`'s story branch is the only from-scratch progress path, and it can lower `task` | studio-state :886-907 vs :928-931 | OK |
| 13 | `adopt-base` is written by seed and by execute §0's new-branch path, and `sync` requires it | studio-adopt ~:511, :722; execute SKILL :127-129 | OK |
| 14 | Execute §0 never rebuilds between `set branch` and `adopt-base` | execute SKILL :122-129 (sync, which rebuilds, runs later) | OK |
| 15 | `set branch` accepts a branch that does not exist yet (the guard test fixture) | studio-state `set_branch` (:515) | OK |
| 16 | Manifest starts all pass `mf_check`, and `refuse` accumulates to exit 2 | `lanes_start` :1977-1998 (single caller :1986); studio-overnight :95 | OK |
| 17 | `story_ledger_text` is usable at preflight | :1257 needs `RUN_DIR` (unset, `set -u`) | FIXED (direct file or git reads) |
| 18 | The pointer refusal leaves existing lanes tests green | `lanes_fixture` had no pointer, so every start would refuse; full suite with the fixture change in the scratch copy | FIXED (R8), 0 FAIL |
| 19 | The pointer may be required to name *this* manifest | lanes tests start `os.md`, `bf.md`, `docs/runs/<f>.md` from other checkouts | FIXED (only presence is required) |
| 20 | The readiness test belongs in `overnight_runs_test.sh` or `overnight_test.sh` | runs = helper unit tests; overnight = single-plan only; lanes owns manifest start | FIXED (D6 → lanes suite) |
| 21 | `_mr_` is a free prefix in overnight-lanes | `mx_reap` (overnight-runs.sh :114-124) uses `_mr_i`/`_mr_t`/`_mr_rc` | FIXED (`_rd_`, `_ra_`) |
| 22 | A prefix assignment on a shell function is portable | POSIX leaves it unspecified | FIXED (`ALF_NOSEED=1; …; unset`) |
| 23 | New tests run without being listed | `run_tests` + `TESTS_ONLY` (tests/assert.sh) skip unlisted names | OK (every task lists its names) |
| 24 | `test_autopilot_adopt_order` tolerates new text on the 3.3 line | it compares offsets inside that line | FIXED (new lines only) |
| 25 | #49 conflicts with T4 | #49's plan edits `lanes_start`/studio-overnight and adds `lanes_fixture`-based tests; T4 edits `mf_check` and the fixture only | OK (overlap: `run_tests` list, PROGRESS) |
| 26 | Guard, T1 and T2 keep the existing suites green | scratch copy: studio_adopt 258/0 (+26 new), state_test 234/0 (+8), lanes adopt + ready 29/0 | OK |
| 27 | Two pointer-less run worktrees listing the id refuse (Review Focus 2) | prototype: `test_adopt_incident_tier2_two_refuse` 2/0 | OK |

Counts: OK 16 · FIXED 11 · UNVERIFIED 0.
