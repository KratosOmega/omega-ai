# Unique Story Ids — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A story id, once used in a project, is not handed out again: `studio-overnight check-id` says whether an id is free, autopilot proposes ids that are, and brainstorm, plan, `next` and `start` refuse a reused one before anything inherits a dead story's ledger.

**Architecture:** A new sourced file `studios/game-dev/bin/overnight-ids.sh` holds the four "taken" rules (`ids_reasons`), the suggestion (`ids_suggest`), the shared report (`ids_check`) and the verb (`cmd_check_id`). `overnight-lanes.sh` sources it, so every manifest-mode path has it (start, `--detach`'s check, `next`, `check-id`) and the single-plan path never loads it. `mf_check` and `lanes_next` call `ids_check` per row; `lanes_next` also switches to whole-line ledger matches. Three skills gain the id rule and the `check-id` call.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2, Linux `dash`), git ≥ 2.38, the plain-sh test harness (`tests/assert.sh`). No new dependencies.

**Spec:** `docs/game-dev/specs/2026-10-07-unique-story-ids.md` (R1–R5, Test strategy 1–16).

Story: #56 (GitHub issue). Branch `issue-56-unique-story-ids` (omega-ai has no Jira). **Base:** 72523a5. Line numbers are at that commit; relocate each with its `grep -n`.

## Global Constraints

- POSIX sh only; must run under macOS `/bin/sh` (bash 3.2) and `dash`. No `local`; function variables carry a per-function prefix (`_ir_`, `_is_`, …).
- Id pattern `^[A-Za-z0-9._-]+$`. Ids compare case-insensitively everywhere (ledger file names, rows, `landed.tsv`, `Story:` lines).
- check-id reads `refs/remotes/origin/<d>`, `<d>` from `origin/HEAD`; it never fetches and never writes.
- Exit codes: `check-id` 0 free · 1 taken · 2 usage (bad option, bad id, `origin/HEAD` unset). `next` keeps exit 2 for a taken id (as for an ambiguous match). `start` refuses (exit 2) through `refuse`.
- Messages, exactly (stderr through `say`/`refuse`, prefix `studio-overnight: `):
  - `story id '<id>' is taken: origin/<d>:<ledger path> belongs to another story[ (plan <p>, shipped <v>)]`
  - `story id '<id>' is taken: origin/<d>:<plan path> says 'Story: <id>'`
  - `story id '<id>' is taken: origin/integration/<s>:<ledger path> belongs to run <s>'s integration branch`
  - `story id '<id>' is taken: run <s> (record .studio/runs/<dir>) lists it`
  - then `use '<candidate>' instead`, or `pick an unused id: the ticket, or <run slug>-S<n>`
  - free: stdout `check-id: <id> is free`
  - usage: `check-id: story id '<id>' must match ^[A-Za-z0-9._-]+$` · `origin/HEAD is not set — run: git remote set-head origin --auto`
- No id format check on manifests; existing `S<n>` manifests and ledgers keep working; nothing is migrated. Phoenix is not changed.
- A phoenix overnight run is live on the installed plugin: nothing is installed, pulled into the main checkout, or merged while `studio-overnight status` shows a live run.
- Review policy: per-task Opus review for T1 and T4 (new seam; cross-system wiring and a record-format addition). T2 and T3 are mechanical and fold into the final review. A standalone whole-branch Opus review always runs at the end. Re-review only after a Critical, 3+ Importants or a production-bug fix; never a third pass.
- `tests/overnight_test.sh` and `tests/overnight_lanes_test.sh` never run at the same time in one checkout. Parallel tasks run in separate worktrees, each running only its affected suites; the full gate runs once, on the integrated branch.

## Execution shape (maximum parallelism)

| Task | Depends on | Wave | Review | Files (hunks) |
|------|------------|------|--------|---------------|
| T1 check-id core, verb, docs | — | 1 | task (Opus) | new `overnight-ids.sh`; `overnight-lanes.sh` (one source line, top); `studio-overnight` (header, usage, dispatch); `README.md`; new `tests/overnight_ids_test.sh` |
| T2 whole-line ledger matches in `next` (R4) | — | 1 | final | `overnight-lanes.sh` (`lanes_next` classification only); `tests/overnight_lanes_test.sh` (one test near `test_lanes_next*`, one `run_tests` name) |
| T3 skill text + contract greps | — | 1 | final | autopilot, plan, brainstorm `SKILL.md`; `tests/omega_contracts/autopilot_contract.sh`; `tests/studio_test.sh` |
| T4 wire check-id into `next` and `start`; record rows; fixture knob | T1, T2 | 2 | task (Opus) | `overnight-lanes.sh` (`mf_check` per-story loop, `lanes_run` record, `lanes_next` loop head); `tests/overnight_lanes_test.sh`; `docs/game-dev/PROGRESS.md` |
| T5 final review, fix wave, full gate, PR | T1–T4 | 3 | — | — |

T1, T2 and T3 run concurrently, each in its own worktree off the story branch at this plan's commit, and are cherry-picked onto the story branch in any order: they share no hunk (T1's only `overnight-lanes.sh` edit is one line under the header guard; T2's is inside `lanes_next` at ~2107-2111; T3 touches no code). T4 starts from the story branch after T1 and T2 are on it.

## Decisions

- **D1 — Where check-id lives.** `overnight-ids.sh`, sourced by `overnight-lanes.sh` right after its `SELF_DIR` guard, not by `studio-overnight`'s top level. Why: only manifest-mode paths need it, and `test_overnight_deny_file_required` (`tests/overnight_test.sh:384`) runs a copy of the runner beside exactly the files the top level sources; a new top-level `.` would break that copy. The `check-id` dispatch sources `overnight-lanes.sh` (as `next` does), which brings `mf_load`/`row_field` for the defaults too.
- **D2 — Run records and `rows.tsv`.** At 72523a5 a record (`.studio/runs/<slug>/`) holds `lock`, `stop`, `landed.tsv`, `done`, `gate`, `final` — not `rows.tsv`; the rows live in the report dir (`.studio/reports/overnight-<slug>-<ts>/rows.tsv`). Spec rule 3 says the record lists the id in `rows.tsv`. So: (a) `lanes_run` copies the run's rows into the record (`$RECORD/rows.tsv`, T4) so new records match the spec; (b) rule 3 reads a record's `rows.tsv` and `landed.tsv`, and for a record with no `rows.tsv` (written before #56) the newest report's `rows.tsv` of its base slug (`runs_rows`), unless that base slug is this run's own (its reports cannot be told apart from this run's).
- **D3 — Record names.** A record dir `<n>` is this run's own only when `<n>` equals this run's slug exactly. An archived `<slug>.<YYYYMMDDTHHMMSSZ>` is another run (its base slug, the suffix stripped, is named in the message), even when the base equals this slug.
- **D4 — Reason order.** Rule 1, rule 4, rule 2, rule 3 (the spec's example order: default-branch reasons first). One line per reason; a rule can give several (two case-variant ledger files, several plans, several records).
- **D5 — Own-ledger exceptions are per rule, as the spec states.** Rule 1: own when the last `plan approved` or `adopted … ->` path equals this story's known plan, or this run's `landed.tsv` lists the id. Rule 2: only this run's own integration branch is skipped. Rule 4: only this story's own plan path is skipped. Rule 3: only this run's own record is skipped.
- **D6 — Defaults.** `.studio/run` (relative to the current checkout, or absolute) names a manifest; when that manifest has a row whose Story cell equals `<id>` exactly, unset flags default to its Plan cell, Ticket cell and the manifest's slug, and its rows feed the suggestion's skip list. Otherwise no defaults and no rows. `-` and empty mean unknown/none.
- **D7 — Roots.** check-id reads git through `START_DIR` (`studio-state root --work`: this checkout, a run worktree included) and records through `STATE_ROOT` (`studio-state root`: the main checkout's root, also from a linked worktree). `studio-state` falls back to `pwd`, so the empty-`START_DIR` guard (exit 2, `no studio state here (run from the project checkout)`) is defensive only. `--slug` must match the id pattern (exit 2).
- **D8 — `next` with `origin/HEAD` unset** exits 2 with start's message before classifying anything (it cannot check ids). Rows whose id does not match the pattern are not checked by `next` or `mf_check` (`mf_check` already refuses them).
- **D9 — Spec-mandated change to an existing test.** `test_lanes_preflight_refuses_stopped_record` ends with "a done record no longer conflicts" (exit 0). Under rule 3 a done record still lists `S1`, so that assertion becomes: exit 2, no AC8 "stopped run" line, and the check-id record line (T4).

## Review Focus

1. **Resuming a run after its stories landed must not refuse its own ids** (direct mode puts the story ledger on `main`; the integration PR does too once merged). Expected: own by plan equality or `landed.tsv`. Pinned by `test_ids_own_ledger` (T1: plan, adopted and landed sub-cases) and `test_lanes_ids_direct_resume_after_landing` (T4).
2. **A ticket that is not an id (`#56`, a URL)** must not be suggested; the suggestion falls back to `<slug>-S<n>`. Pinned in `test_ids_suggestion` (T1).
3. **check-id from a run worktree** (the plan/brainstorm call) must read records under the main checkout's `<root>`, not the worktree's. Pinned in `test_ids_run_records` (T1, linked-worktree sub-case).
4. **Ids that differ only in case** (`s1.md` on main, `s1` in a `landed.tsv`) are the same id on macOS. Pinned by `test_ids_case_insensitive` and the lowercase `landed.tsv` sub-case of `test_ids_run_records` (T1).
5. **autopilot's story-list call from the main checkout**, where `.studio/run` is absent or names another run: explicit flags only, no manifest rows, and no defaults leak from an unrelated manifest. Pinned in `test_ids_suggestion` (T1, no-pointer sub-case) and `test_ids_defaults_need_listed_row` (T1).

## File Structure

- Create `studios/game-dev/bin/overnight-ids.sh` (executable, like its siblings) — check-id's rules, suggestion, report and verb.
- Create `tests/overnight_ids_test.sh` — its own small fixture (no stubs: check-id reads git and files only); `run_all.sh` picks it up by name.
- Modify `studios/game-dev/bin/overnight-lanes.sh` — source line (T1); `lanes_next` whole-line matches (T2); `mf_check` per-story check, `lanes_run` record rows, `lanes_next` per-row check (T4).
- Modify `studios/game-dev/bin/studio-overnight` — header exit line, usage, `check-id` dispatch (T1).
- Modify `README.md` — command table and an Overnight runs bullet (T1).
- Modify `shared/omega/skills/autopilot/SKILL.md`, `studios/game-dev/skills/plan/SKILL.md`, `studios/game-dev/skills/brainstorm/SKILL.md`; `tests/omega_contracts/autopilot_contract.sh`, `tests/studio_test.sh` (T3).
- Modify `tests/overnight_lanes_test.sh` — R4 test (T2); fixture knob `LANES_MAIN_PRE`, wiring tests, D9 (T4).
- Modify `docs/game-dev/PROGRESS.md` — one entry (T4).

---

### Task 1: `check-id` — rules, suggestion, verb, usage and README

Review: task (Opus). Wave 1, parallel with T2 and T3.

**Files:**
- Create: `studios/game-dev/bin/overnight-ids.sh` (`chmod +x`)
- Create: `tests/overnight_ids_test.sh`
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — one line after the guard at :13
- Modify: `studios/game-dev/bin/studio-overnight` — header `# Exit:` (:14-16), `usage()` (:261-…), dispatch (`next)` at :1986)
- Modify: `README.md` — the `studio-overnight` table row (:100) and the Overnight runs bullets (after the `next` bullet, :130-131)

**Interfaces:**
- Consumes (defined in `studio-overnight` / `overnight-runs.sh` / `overnight-lanes.sh`): `say`, `usage`, `START_DIR`, `STATE_ROOT`, `runs_rows ROOT SLUG`, `mf_load MANIFEST` (needs `MF_ROWS` set; sets `MF_SLUG`), `row_field ID FIELD`.
- Produces (T4 relies on these exact names):
  - `IDS_PAT='^[A-Za-z0-9._-]+$'`
  - `ids_ok TEXT` → 0 when TEXT matches `IDS_PAT`.
  - `ids_default_branch` → prints `<d>` (no `origin/`); returns 1 when `origin/HEAD` is unset.
  - `ids_reasons ID PLAN SLUG D` → one reason per line (the text after `is taken: `); nothing when free. PLAN `-`/empty = unknown; SLUG may be empty.
  - `ids_suggest ID TICKET SLUG PLAN D ROWS` → prints the first free candidate; returns 1 when none. ROWS is a rows TSV path or empty.
  - `ids_check ID TICKET SLUG PLAN D ROWS EMIT` → 0 when free; else calls `EMIT` (`say` or `refuse`) once per reason as `story id '<id>' is taken: <reason>`, then once with the suggestion line, and returns 1. Runs in the current shell (no pipeline around `EMIT`, so `refuse`'s `FAILED=1` sticks).
  - `cmd_check_id ARGS…` → the verb; returns 0/1/2.

Anchors: `grep -n 'sourced by studio-overnight" >&2; exit 2; }' studios/game-dev/bin/overnight-lanes.sh`; `grep -n '^# Exit:\|^usage: \|^  next \[<manifest>\]\|^  next)$' studios/game-dev/bin/studio-overnight`; `grep -n 'studio-overnight next. reads the manifest\|^| .studio-overnight start' README.md`.

- [ ] **Step 1: Write the failing test file** `tests/overnight_ids_test.sh` (complete):

```sh
#!/bin/sh
# check-id (#56): a story id, once used in a project, is not handed out again.
# Each project is a clone $P of a local bare origin, on run/demo cut from main.
# No stub sessions: check-id reads git refs and files only. Runs offline.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
BIN="$REPO_ROOT/studios/game-dev/bin"
RUNNER="$BIN/studio-overnight"
STATE_BIN="$BIN/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
OLD_PLAN=docs/game-dev/plans/2026-10-02-mob-composer.md

# pre_stale DIR — KAN-1499's shipped story S1, as phoenix's main held it:
# its ledger (plan approved OLD_PLAN, T1-T2 complete, shipped) and OLD_PLAN.
pre_stale() {
  mkdir -p "$1/.studio/ledger" "$1/docs/game-dev/plans"
  printf -- '- 2026-10-02 plan approved %s\n- 2026-10-02 T1 complete\n- 2026-10-02 T2 complete\n- 2026-10-03 shipped KAN-1499-mob-composer\n' \
    "$OLD_PLAN" > "$1/.studio/ledger/S1.md"
  printf '# Plan: mob composer\n\nStory: S1\n\n### Task 1: t\n' > "$1/$OLD_PLAN"
}

# ids_fixture NAME PRE ROW… — bare origin $TMP/NAME.git and its clone $P.
# main holds PRE's files when PRE is a directory ('-': an empty commit), is
# pushed, and origin/HEAD is set. run/demo is cut from main, gets studio
# state and docs/runs/demo.md (Mode integration, one row per ROW =
# id|ticket|plan), is committed and pushed; .studio/run names the manifest.
ids_fixture() {
  _if_n="$1"; _if_pre="$2"; shift 2
  P="$TMP/$_if_n"; export P
  rm -rf "$P" "$TMP/$_if_n.git"; mkdir -p "$P"
  git init -q --bare "$TMP/$_if_n.git"
  ( set -e; cd "$P"
    git init -q -b main
    if [ -d "$_if_pre" ]; then cp -R "$_if_pre/." . && git add -A && git commit -q -m pre
    else git commit -q --allow-empty -m init; fi
    git remote add origin "$TMP/$_if_n.git" && git push -q origin main && git remote set-head origin main
    git checkout -q -b run/demo
    sh "$STATE_BIN" init >/dev/null
    mkdir -p docs/runs
    { printf '# Run: demo\n\nMode: integration\nTarget: integration/demo\nDocs: -\nGoal: g\n\n'
      printf '| Story | Branch | Ticket | Spec | Plan | Depends on |\n|---|---|---|---|---|---|\n'
      for _r in "$@"; do
        _i="${_r%%|*}"; _x="${_r#*|}"
        printf '| %s | %s-b | %s | - | %s | - |\n' "$_i" "$_i" "${_x%%|*}" "${_x#*|}"
      done; } > docs/runs/demo.md
    git add -A && git commit -q -m manifest && git push -q origin run/demo
    printf '.studio/run\n' >> "$(git rev-parse --git-common-dir)/info/exclude"
    printf 'docs/runs/demo.md\n' > .studio/run
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "ids_fixture $_if_n: setup failed"; }
}

# push_ledger NAME BRANCH ID TEXT — commit .studio/ledger/ID.md (TEXT) on a
# branch cut from origin/main, through a temp clone; push it as BRANCH; fetch in $P.
push_ledger() {
  rm -rf "$TMP/pl"
  ( set -e; git clone -q "$TMP/$1.git" "$TMP/pl"; cd "$TMP/pl"; git checkout -q -B x origin/main
    mkdir -p .studio/ledger; printf '%s\n' "$4" > ".studio/ledger/$3.md"
    git add -A; git commit -q -m ledger; git push -q origin "HEAD:refs/heads/$2" ) >/dev/null 2>&1
  git -C "$P" fetch -q origin >/dev/null 2>&1
}

# run_ids ARGS — `studio-overnight ARGS` in $P (or in $IDS_CWD when set):
# IS_STATUS, and IS_OUT and IS_ERR (paths).
run_ids() {
  IS_STATUS=0; IS_OUT="$TMP/ids.out"; IS_ERR="$TMP/ids.err"
  ( cd "${IDS_CWD:-$P}" && exec sh "$RUNNER" "$@" ) > "$IS_OUT" 2> "$IS_ERR" < /dev/null || IS_STATUS=$?
}

test_ids_main_ledger_taken() {                       # spec test 1
  pre_stale "$TMP/pre1"
  ids_fixture t1 "$TMP/pre1" 'S1|KAN-1541|-'
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "a shipped S1 ledger of another plan on origin/main: taken"
  assert_contains "$IS_ERR" "^studio-overnight: story id 'S1' is taken: origin/main:\.studio/ledger/S1\.md belongs to another story (plan $OLD_PLAN, shipped KAN-1499-mob-composer)\$" "names the ledger, its plan and its shipped branch"
  assert_contains "$IS_ERR" "^studio-overnight: story id 'S1' is taken: origin/main:$OLD_PLAN says 'Story: S1'\$" "and the old plan"
  assert_eq "studio-overnight: use 'KAN-1541' instead" "$(tail -n 1 "$IS_ERR")" "the suggestion comes last: the row's ticket"
  assert_eq "" "$(cat "$IS_OUT")" "nothing on stdout"
  assert_eq "S1.md|$OLD_PLAN" \
    "$(sed -n 's/.* is taken: origin\/main:\([^ ]*\) .*/\1/p' "$IS_ERR" | sed 's#^\.studio/ledger/##' | paste -sd '|' -)" \
    "rule 1's line first, then rule 4's"
}
test_ids_main_plan_only() {                          # spec test 2
  mkdir -p "$TMP/pre2/docs/game-dev/plans"; printf '# Plan\n\nStory: S1\n' > "$TMP/pre2/$OLD_PLAN"
  ids_fixture t2 "$TMP/pre2" 'S1|-|-'
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "a plan on origin/main saying Story: S1: taken"
  assert_contains "$IS_ERR" "story id 'S1' is taken: origin/main:$OLD_PLAN says 'Story: S1'\$" "names the plan"
  assert_not_contains "$IS_ERR" "belongs to" "no ledger reason"
  mkdir -p "$TMP/pre2b/docs/game-dev/specs" "$TMP/pre2b/docs/game-dev/plans"
  printf '# Spec\n\nStory: S1\n' > "$TMP/pre2b/docs/game-dev/specs/2026-10-02-x.md"
  printf '# Plan\n\nStory: S10\nStory: S1 (draft)\n' > "$TMP/pre2b/docs/game-dev/plans/2026-10-02-y.md"
  ids_fixture t2b "$TMP/pre2b" 'S1|-|-'
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "a spec saying Story: S1, and plan lines that only contain it, do not count"
  assert_contains "$IS_OUT" "^check-id: S1 is free\$" "free"
}
test_ids_run_branch_plan_not_checked() {             # spec test 3
  _p3=docs/game-dev/plans/2026-10-07-greater-slime.md
  ids_fixture t3 - "KAN-1541|KAN-1541|$_p3"
  ( cd "$P" && mkdir -p docs/game-dev/plans .studio/ledger && printf '# Plan\n\nStory: KAN-1541\n' > "$_p3" \
    && printf -- '- 2026-10-07 plan approved %s\n' "$_p3" > .studio/ledger/KAN-1541.md \
    && git add -A && git commit -qm plan && git push -q origin run/demo ) >/dev/null 2>&1
  run_ids check-id KAN-1541
  assert_eq 0 "$IS_STATUS" "the story's own plan and ledger on the run branch only: free"
  assert_contains "$IS_OUT" "^check-id: KAN-1541 is free\$" "says so"
}
test_ids_own_ledger() {                              # spec test 4 (+ adopted, landed)
  _own=docs/game-dev/plans/2026-10-01-S1.md
  mkdir -p "$TMP/pre4/.studio/ledger" "$TMP/pre4/docs/game-dev/plans"
  printf -- '- 2026-10-01 plan approved %s\n- 2026-10-01 T1 complete\n' "$_own" > "$TMP/pre4/.studio/ledger/S1.md"
  printf '# Plan\n\nStory: S1\n' > "$TMP/pre4/$_own"
  ids_fixture t4 "$TMP/pre4" "S1|S1|$_own"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "own ledger (last plan approved = the row's Plan) and own plan on main: free"
  run_ids check-id S1 --plan docs/game-dev/plans/other.md
  assert_eq 1 "$IS_STATUS" "with another plan the same ledger is another story's"
  mkdir -p "$TMP/pre4a/.studio/ledger"
  printf -- '- 2026-09-30 source docs/superpowers/plans/o.md spec -\n- 2026-09-30 adopted docs/superpowers/plans/o.md -> %s\n' "$_own" > "$TMP/pre4a/.studio/ledger/S1.md"
  ids_fixture t4a "$TMP/pre4a" "S1|S1|$_own"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "own adopted ledger (adopted … -> the row's Plan, no plan approved): free"
  mkdir -p "$TMP/pre4l/.studio/ledger"
  printf -- '- 2026-09-30 plan approved docs/game-dev/plans/2026-09-30-older.md\n' > "$TMP/pre4l/.studio/ledger/S1.md"
  ids_fixture t4l "$TMP/pre4l" "S1|S1|$_own"
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "a ledger for an older plan: taken"
  mkdir -p "$P/.studio/runs/demo"; printf 's1\tintegration/demo\tabc\t1\n' > "$P/.studio/runs/demo/landed.tsv"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "this run's landed.tsv lists it (any case): its own"
}
test_ids_integration_branches() {                    # spec test 6
  ids_fixture t6 - 'S1|-|-'
  push_ledger t6 integration/other S1 '- 2026-10-01 shipped S1-b'
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "S1.md on another run's integration branch: taken"
  assert_contains "$IS_ERR" "story id 'S1' is taken: origin/integration/other:\.studio/ledger/S1\.md belongs to run other's integration branch\$" "names the branch"
  ids_fixture t6b - 'S1|-|-'
  push_ledger t6b integration/demo S1 '- 2026-10-01 shipped S1-b'
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "this run's own integration branch is not checked"
}
test_ids_run_records() {                             # spec test 7 (+ legacy, linked worktree)
  ids_fixture t7 - 'S1|-|-'
  _rr="$P/.studio/runs"
  mkdir -p "$_rr/old"; printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$_rr/old/rows.tsv"; : > "$_rr/old/landed.tsv"; : > "$_rr/old/done"
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "a done record's rows.tsv lists S1: taken"
  assert_contains "$IS_ERR" "story id 'S1' is taken: run old (record \.studio/runs/old) lists it\$" "names the run and its record"
  mv "$_rr/old" "$_rr/old.20261001T000000Z"
  run_ids check-id S1
  assert_contains "$IS_ERR" "story id 'S1' is taken: run old (record \.studio/runs/old\.20261001T000000Z) lists it\$" "an archived record too"
  # From a linked worktree: records are read under the main checkout's root.
  ( cd "$P" && git worktree add -q -b run/x "$P/.claude/worktrees/run-x" run/demo ) >/dev/null 2>&1
  IDS_CWD="$P/.claude/worktrees/run-x"; run_ids check-id S1 --slug x; unset IDS_CWD
  assert_eq 1 "$IS_STATUS" "from a run worktree the main checkout's records count"
  rm -rf "$_rr/old.20261001T000000Z"
  mkdir -p "$_rr/legacy"; printf 's1\tintegration/legacy\tabc\t1\n' > "$_rr/legacy/landed.tsv"
  run_ids check-id S1
  assert_contains "$IS_ERR" "run legacy (record \.studio/runs/legacy) lists it" "a record written before #56: its landed.tsv (any case)"
  : > "$_rr/legacy/landed.tsv"; mkdir -p "$P/.studio/reports/overnight-legacy-20261001-000000"
  printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$P/.studio/reports/overnight-legacy-20261001-000000/rows.tsv"
  run_ids check-id S1
  assert_contains "$IS_ERR" "run legacy (record \.studio/runs/legacy) lists it" "and its newest report's rows.tsv (D2)"
  rm -rf "$_rr/legacy"; mkdir -p "$_rr/demo"; printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$_rr/demo/rows.tsv"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "this run's own record does not count"
  run_ids check-id S1 --slug other
  assert_eq 1 "$IS_STATUS" "under another slug, demo's record is another run's"
}
test_ids_case_insensitive() {                        # spec test 8
  mkdir -p "$TMP/pre8/.studio/ledger"
  printf -- '- 2026-10-01 plan approved docs/game-dev/plans/x.md\n' > "$TMP/pre8/.studio/ledger/s1.md"
  ids_fixture t8 "$TMP/pre8" 'S1|-|-'
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "s1.md on origin/main makes S1 taken"
  assert_contains "$IS_ERR" "origin/main:\.studio/ledger/s1\.md belongs to another story (plan docs/game-dev/plans/x\.md)\$" "names the file as it is"
}
test_ids_suggestion() {                              # spec test 14 (+ Review Focus 2, 5)
  mkdir -p "$TMP/pre14/.studio/ledger"
  printf -- '- 2026-10-01 plan approved docs/game-dev/plans/k.md\n' > "$TMP/pre14/.studio/ledger/KAN-1541.md"
  printf -- '- 2026-10-01 plan approved docs/game-dev/plans/k3.md\n' > "$TMP/pre14/.studio/ledger/KAN-1541-3.md"
  ids_fixture t14 "$TMP/pre14" 'KAN-1541|KAN-1541|-' 'KAN-1541-2|KAN-1541|-'
  run_ids check-id KAN-1541
  assert_eq 1 "$IS_STATUS" "taken"
  assert_eq "studio-overnight: use 'KAN-1541-4' instead" "$(tail -n 1 "$IS_ERR")" "skips another row's id (-2) and a taken candidate (-3)"
  run_ids check-id KAN-1541 --ticket '#56' --slug zz
  assert_eq "studio-overnight: use 'zz-S1' instead" "$(tail -n 1 "$IS_ERR")" "a ticket that is not an id falls back to <slug>-S<n>"
  rm -f "$P/.studio/run"
  run_ids check-id KAN-1541 --ticket -
  assert_eq "studio-overnight: pick an unused id: the ticket, or <run slug>-S<n>" "$(tail -n 1 "$IS_ERR")" "no pointer, no ticket, no slug: no candidate"
}
test_ids_defaults_need_listed_row() {                # Review Focus 5
  pre_stale "$TMP/pre-d"
  ids_fixture tdf "$TMP/pre-d" 'A|KAN-9|-'
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "taken"
  assert_eq "studio-overnight: pick an unused id: the ticket, or <run slug>-S<n>" "$(tail -n 1 "$IS_ERR")" "a manifest that does not list the id gives no defaults (no ticket, no slug)"
}
test_ids_usage() {                                   # spec test 15
  ids_fixture t15 - 'S1|-|-'
  run_ids check-id 'S 1'
  assert_eq 2 "$IS_STATUS" "a bad id is a usage error"
  assert_contains "$IS_ERR" "check-id: story id 'S 1' must match" "says why"
  run_ids check-id;              assert_eq 2 "$IS_STATUS" "no id"
  run_ids check-id S1 --bogus x; assert_eq 2 "$IS_STATUS" "an unknown option"
  run_ids check-id S1 --plan;    assert_eq 2 "$IS_STATUS" "an option without its value"
  run_ids check-id S1 S2;        assert_eq 2 "$IS_STATUS" "two ids"
  run_ids check-id S1 --slug 'a/b'; assert_eq 2 "$IS_STATUS" "a bad slug"
  ( cd "$P" && git remote set-head origin -d ) >/dev/null 2>&1
  run_ids check-id S1
  assert_eq 2 "$IS_STATUS" "origin/HEAD unset"
  assert_contains "$IS_ERR" "origin/HEAD is not set — run: git remote set-head origin --auto" "with start's message"
}
test_ids_docs() {                                    # R5
  assert_status 2 "overnight-ids.sh refuses to run directly" -- sh "$BIN/overnight-ids.sh"
  sh "$RUNNER" --help > "$TMP/help" 2>&1
  assert_contains "$TMP/help" "check-id <id> \[--plan <path>|-\] \[--ticket <ticket>|-\] \[--slug <slug>\]" "usage names check-id"
  assert_contains "$TMP/help" "0 free · 1 taken" "and its exit codes"
  assert_contains "$REPO_ROOT/README.md" "studio-overnight check-id <id>" "README documents check-id"
  assert_contains "$REPO_ROOT/README.md" "check-id: 0 free · 1 taken · 2 usage" "README's table gives its exit codes"
}

run_tests test_ids_main_ledger_taken test_ids_main_plan_only test_ids_run_branch_plan_not_checked \
  test_ids_own_ledger test_ids_integration_branches test_ids_run_records test_ids_case_insensitive \
  test_ids_suggestion test_ids_defaults_need_listed_row test_ids_usage test_ids_docs
```

- [ ] **Step 2: Run it; every test fails.** `sh tests/overnight_ids_test.sh` — `check-id` is an unknown verb today (`usage >&2; exit 2`), so each status assertion sees 2 and each message assertion misses; `test_ids_docs` fails on the missing file and texts.

- [ ] **Step 3: Create `studios/game-dev/bin/overnight-ids.sh`** (complete; `chmod +x`):

```sh
#!/bin/sh
# overnight-ids.sh — story ids (#56): a story id, once used in a project, is
# not handed out again (ledgers are keyed by id and outlive the run).
# check-id's four taken rules (ids_reasons), its suggestion (ids_suggest),
# the report every caller shares (ids_check) and the verb (cmd_check_id).
# Sourced by overnight-lanes.sh, so by every manifest-mode path; never run on
# its own. Reads git refs and files only: it never fetches and never writes.
[ -n "${SELF_DIR:-}" ] || { echo "overnight-ids.sh: sourced by studio-overnight" >&2; exit 2; }
IDS_PAT='^[A-Za-z0-9._-]+$'

# ids_lc TEXT — TEXT in lower case: ids compare case-insensitively (a macOS
# checkout treats s1.md and S1.md as one file).
ids_lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# ids_ok TEXT — TEXT matches the id pattern.
ids_ok() { printf '%s\n' "$1" | grep -Eq "$IDS_PAT"; }
# ids_default_branch — <d> from refs/remotes/origin/HEAD, without origin/; 1 when unset.
ids_default_branch() {
  _idb="$(git -C "$START_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || return 1
  _idb="${_idb#origin/}"; [ -n "$_idb" ] || return 1
  printf '%s\n' "$_idb"
}
# ids_has FILE ID — FILE's first tab-separated column holds ID, in any case.
ids_has() { [ -f "$1" ] && awk -F'\t' -v w="$(ids_lc "$2")" 'tolower($1) == w { f = 1 } END { exit !f }' "$1"; }
# ids_ledgers REF ID — the .studio/ledger/<ID>.md paths on REF, matched in any
# case by listing the directory (a case-sensitive `git show` would miss s1.md).
ids_ledgers() {
  git -C "$START_DIR" ls-tree --name-only "$1" -- .studio/ledger/ 2>/dev/null \
    | awk -v w="$(ids_lc ".studio/ledger/$2.md")" 'tolower($0) == w'
}
# ids_own TEXT PLAN — the ledger TEXT is this story's: PLAN is known and is the
# path of its last `plan approved` line or of its last `adopted <orig> -> <p>`.
ids_own() {
  case "$2" in ''|-) return 1 ;; esac
  [ "$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* plan approved //p' | tail -n 1)" = "$2" ] \
    || [ "$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* adopted .* -> //p' | tail -n 1)" = "$2" ]
}
# ids_detail TEXT — " (plan <p>, shipped <v>)" from the ledger TEXT's last such
# lines; either part alone, or nothing when it has neither.
ids_detail() {
  _idp="$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* plan approved //p' | tail -n 1)"
  _ids="$(printf '%s\n' "$1" | sed -n 's/^- [0-9-]* shipped //p' | tail -n 1)"
  _idd="${_idp:+plan $_idp}"
  [ -z "$_ids" ] || _idd="${_idd:+$_idd, }shipped $_ids"
  [ -z "$_idd" ] || printf ' (%s)' "$_idd"
}

# ids_reasons ID PLAN SLUG D — why ID is taken, one line per reason (the text
# after "is taken: "), in the order rule 1, 4, 2, 3 (D4); nothing when free.
# PLAN is this story's plan ('-' or empty: unknown), SLUG this run's slug
# (may be empty), D the default branch.
ids_reasons() {
  _ir_ref="refs/remotes/origin/$4"
  # 1. A ledger on the default branch that is not this story's own.
  for _ir_p in $(ids_ledgers "$_ir_ref" "$1"); do
    _ir_t="$(git -C "$START_DIR" show "$_ir_ref:$_ir_p" 2>/dev/null)"
    ids_own "$_ir_t" "$2" && continue
    [ -n "$3" ] && ids_has "$STATE_ROOT/.studio/runs/$3/landed.tsv" "$1" && continue
    printf 'origin/%s:%s belongs to another story%s\n' "$4" "$_ir_p" "$(ids_detail "$_ir_t")"
  done
  # 4. A plan on the default branch, other than this story's, with the line
  #    `Story: <id>` (git grep has no -x: each hit is re-tested whole-line).
  git -C "$START_DIR" grep -l -i -F -e "Story: $1" "$_ir_ref" -- docs/game-dev/plans 2>/dev/null \
    | while IFS= read -r _ir_h; do
        _ir_p="${_ir_h#"$_ir_ref":}"
        [ "$_ir_p" != "$2" ] || continue
        git -C "$START_DIR" show "$_ir_ref:$_ir_p" 2>/dev/null | grep -qixF -- "Story: $1" || continue
        printf "origin/%s:%s says 'Story: %s'\n" "$4" "$_ir_p" "$1"
      done
  # 2. A ledger on another run's integration branch.
  for _ir_r in $(git -C "$START_DIR" for-each-ref --format='%(refname)' refs/remotes/origin/integration/ 2>/dev/null); do
    _ir_s="${_ir_r#refs/remotes/origin/integration/}"
    [ "$_ir_s" != "$3" ] || continue
    for _ir_p in $(ids_ledgers "$_ir_r" "$1"); do
      printf "origin/integration/%s:%s belongs to run %s's integration branch\n" "$_ir_s" "$_ir_p" "$_ir_s"
    done
  done
  # 3. Another run's record: live, stopped, done or archived <slug>.<ts> (D2, D3).
  for _ir_d in "$STATE_ROOT"/.studio/runs/*/; do
    [ -d "$_ir_d" ] || continue
    _ir_d="${_ir_d%/}"; _ir_n="${_ir_d##*/}"
    [ "$_ir_n" != "$3" ] || continue
    _ir_b="$(printf '%s\n' "$_ir_n" | sed 's/\.[0-9]\{8\}T[0-9]\{6\}Z$//')"
    if ids_has "$_ir_d/rows.tsv" "$1" || ids_has "$_ir_d/landed.tsv" "$1" \
       || { [ ! -f "$_ir_d/rows.tsv" ] && [ "$_ir_b" != "$3" ] \
            && _ir_rw="$(runs_rows "$STATE_ROOT" "$_ir_b")" && ids_has "$_ir_rw" "$1"; }; then
      printf 'run %s (record .studio/runs/%s) lists it\n' "$_ir_b" "$_ir_n"
    fi
  done
}

# ids_suggest ID TICKET SLUG PLAN D ROWS — the first candidate that matches
# the id pattern, is not ID, is not a row id in ROWS (any case) and is free by
# ids_reasons: TICKET (when not ID), TICKET-2 … TICKET-9, then SLUG-S1 …
# SLUG-S9. TICKET '-' or empty: none. 1 when no candidate is left.
ids_suggest() {
  _is_c=""
  case "$2" in ''|-) ;; *)
    _is_c="$2"
    for _is_n in 2 3 4 5 6 7 8 9; do _is_c="$_is_c
$2-$_is_n"; done ;;
  esac
  if [ -n "$3" ]; then
    for _is_n in 1 2 3 4 5 6 7 8 9; do _is_c="$_is_c
$3-S$_is_n"; done
  fi
  _is_o="$(printf '%s\n' "$_is_c" | while IFS= read -r _is_k; do
    [ -n "$_is_k" ] && ids_ok "$_is_k" || continue
    [ "$(ids_lc "$_is_k")" != "$(ids_lc "$1")" ] || continue
    [ -z "$6" ] || ! ids_has "$6" "$_is_k" || continue
    [ -z "$(ids_reasons "$_is_k" "$4" "$3" "$5" < /dev/null)" ] || continue
    printf '%s\n' "$_is_k"; break
  done)"
  [ -n "$_is_o" ] || return 1
  printf '%s\n' "$_is_o"
}

# ids_check ID TICKET SLUG PLAN D ROWS EMIT — 0 when ID is free. Taken: EMIT
# (say or refuse) once per reason, then once with the suggestion; 1. The
# here-document keeps EMIT in this shell, so refuse's FAILED=1 sticks.
ids_check() {
  _ic_r="$(ids_reasons "$1" "$4" "$3" "$5" < /dev/null)"
  [ -n "$_ic_r" ] || return 0
  while IFS= read -r _ic_l; do
    "$7" "story id '$1' is taken: $_ic_l"
  done <<EOF_IC
$_ic_r
EOF_IC
  if _ic_s="$(ids_suggest "$1" "$2" "$3" "$4" "$5" "$6" < /dev/null)"; then
    "$7" "use '$_ic_s' instead"
  else
    "$7" "pick an unused id: the ticket, or <run slug>-S<n>"
  fi
  return 1
}

# cmd_check_id ARGS — `check-id <id> [--plan <path>|-] [--ticket <ticket>|-]
# [--slug <slug>]` (R2). Defaults (D6): the row of .studio/run's manifest
# that lists <id>. 0 free · 1 taken · 2 usage.
cmd_check_id() {
  _cc_id=""; _cc_p=""; _cc_t=""; _cc_s=""; _cc_hp=0; _cc_ht=0; _cc_hs=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --plan|--ticket|--slug)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { usage >&2; return 2; }
        case "$1" in
          --plan) _cc_p="$2"; _cc_hp=1 ;;
          --ticket) _cc_t="$2"; _cc_ht=1 ;;
          *) _cc_s="$2"; _cc_hs=1 ;;
        esac
        shift 2 ;;
      -*) usage >&2; return 2 ;;
      *) [ -z "$_cc_id" ] || { usage >&2; return 2; }; _cc_id="$1"; shift ;;
    esac
  done
  [ -n "$_cc_id" ] || { usage >&2; return 2; }
  ids_ok "$_cc_id" || { say "check-id: story id '$_cc_id' must match $IDS_PAT"; return 2; }
  [ "$_cc_hs" = 0 ] || ids_ok "$_cc_s" || { say "check-id: slug '$_cc_s' must match $IDS_PAT"; return 2; }
  [ -n "$START_DIR" ] || { say "no studio state here (run from the project checkout)"; return 2; }
  _cc_d="$(ids_default_branch)" || { say "origin/HEAD is not set — run: git remote set-head origin --auto"; return 2; }
  MF_ROWS="$(mktemp "${TMPDIR:-/tmp}/check-id.XXXXXX")" || return 2
  trap 'rm -f "$MF_ROWS"' EXIT
  _cc_m="$(head -n 1 "$START_DIR/.studio/run" 2>/dev/null)"
  case "$_cc_m" in ''|/*) ;; *) _cc_m="$START_DIR/$_cc_m" ;; esac
  if [ -n "$_cc_m" ] && [ -f "$_cc_m" ] && mf_load "$_cc_m" \
     && awk -F'\t' -v id="$_cc_id" '$1 == id { f = 1 } END { exit !f }' "$MF_ROWS"; then
    [ "$_cc_hp" = 1 ] || _cc_p="$(row_field "$_cc_id" plan)"
    [ "$_cc_ht" = 1 ] || _cc_t="$(row_field "$_cc_id" ticket)"
    [ "$_cc_hs" = 1 ] || _cc_s="$MF_SLUG"
  else
    : > "$MF_ROWS"
  fi
  [ -n "$_cc_p" ] || _cc_p=-
  if ids_check "$_cc_id" "$_cc_t" "$_cc_s" "$_cc_p" "$_cc_d" "$MF_ROWS" say; then
    echo "check-id: $_cc_id is free"
    return 0
  fi
  return 1
}
```

- [ ] **Step 4: Wire it.**
  - `overnight-lanes.sh`, the line after the `SELF_DIR` guard (:13): `. "$SELF_DIR/overnight-ids.sh"   # story ids (#56): ids_check, used by mf_check and lanes_next`. Add `overnight-ids.sh` to the header comment's list of what it relies on.
  - `studio-overnight` dispatch, before `next)`:
    ```sh
      check-id)
        shift
        . "$SELF_DIR/overnight-lanes.sh"   # mf_load, row_field; it sources overnight-ids.sh
        cmd_check_id "$@"
        exit $? ;;
    ```
  - Header comment (:14-16): add `check-id 0 free · 1 taken · 2 usage.`

- [ ] **Step 5: Usage text.** In `usage()`'s first line add ` | check-id <id> [--plan <path>|-] [--ticket <ticket>|-] [--slug <slug>]` after `next [<manifest>]`, and after the `next [<manifest>]` paragraph:

```
  check-id <id> [--plan <path>|-] [--ticket <ticket>|-] [--slug <slug>]
                     is <id> free for a new story? Taken (any case) when
                     origin/<default> holds another story's .studio/ledger/<id>.md
                     (its last plan approved or adopted path is not this
                     story's plan), another run's origin/integration/<slug>
                     holds it, another run's record under .studio/runs/
                     (archived ones too) lists it, or a plan under
                     docs/game-dev/plans/ on origin/<default> says Story: <id>.
                     Defaults: the row of .studio/run's manifest. No fetch.
                     Exit 0 free · 1 taken (each reason, then a free id to use
                     instead) · 2 usage
```

- [ ] **Step 6: README.** Table row (:100): add `\| check-id` after `\| next` in the command cell, and `; check-id: 0 free · 1 taken · 2 usage` to the exit cell. After the `studio-overnight next` bullet (:130-131):

```markdown
- `studio-overnight check-id <id>` says whether a story id is free. Ledgers are
  keyed by story id and outlive the run, so an id once used in the project is
  never handed out again: `/omega:autopilot` proposes the ticket (`KAN-1541`)
  or `<slug>-S<n>` and checks each id; brainstorm, plan, `next` and `start`
  refuse a taken one, naming why and a free id to use instead.
```

- [ ] **Step 7: Run; they pass.** `sh tests/overnight_ids_test.sh` (all pass). Then the touched neighbours: `TESTS_ONLY="test_overnight_help test_help_names_concurrent_runs test_overnight_deny_file_required" sh tests/overnight_test.sh`; then (not concurrently) `TESTS_ONLY="test_lanes_help_modes test_lanes_sourced_only test_lanes_next test_lanes_conflicts_lock_without_start" sh tests/overnight_lanes_test.sh`; `TESTS_ONLY="test_bin_syntax" sh tests/studio_test.sh` (the new file parses and is executable).

- [ ] **Step 8: Commit** — `git add studios/game-dev/bin/overnight-ids.sh tests/overnight_ids_test.sh && git commit -m 'feat(overnight): check-id — a story id once used is not handed out again (#56)' -- studios/game-dev/bin/overnight-ids.sh studios/game-dev/bin/overnight-lanes.sh studios/game-dev/bin/studio-overnight README.md tests/overnight_ids_test.sh`

Acceptance: R2 whole (rules 1–4, exits, messages, suggestion, defaults), R5; spec tests 1, 2, 3, 4, 6, 7, 8, 14, 15 pass; Review Focus 1 (check-id half), 2, 3, 4, 5.

---

### Task 2: whole-line ledger matches in `next` (R4)

Review: final (mechanical). Wave 1, parallel with T1 and T3.

**Files:**
- Modify: `studios/game-dev/bin/overnight-lanes.sh:2107-2111` (`lanes_next`'s classification) and one helper above `lanes_next` (:2087)
- Test: `tests/overnight_lanes_test.sh` — a new test after `test_lanes_next_plan_before_autopilot` (:855-866); its name in `run_tests` next to `test_lanes_next_plan_before_autopilot` (:4064)

**Interfaces:**
- Produces: `ln_has FILE TEXT` — 0 when FILE has a ledger line whose text after `- <date> ` is exactly TEXT. (T4 does not call it; T4 edits the same function's loop head, a different hunk.)

Anchors: `grep -n 'grep -qF' studios/game-dev/bin/overnight-lanes.sh`; `grep -n '^test_lanes_next_plan_before_autopilot\|test_lanes_next_all_planned_and_ambiguous test_lanes_next_plan_before_autopilot' tests/overnight_lanes_test.sh`.

- [ ] **Step 1: Failing test** (spec test 13):

```sh
# #56 R4: next matches a ledger line whole, after `- <date> `.
test_lanes_next_whole_line_ledger() {
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nwl integration S1:-
  _wl_s=docs/game-dev/specs/2026-10-01-demo.md; _wl_p=docs/game-dev/plans/2026-10-01-S1.md
  printf -- '- 2026-10-01 spec approved %s\n- 2026-10-01 plan approved %s\n- 2026-10-01 Decisions swept S10\n' "$_wl_s" "$_wl_p" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next exits 0"
  assert_contains "$LS_OUT" "^S1  plan  spec=$_wl_s  plan=$_wl_p\$" "Decisions swept S10 does not sweep S1"
  printf -- '- 2026-10-01 spec approved %s\n- 2026-10-01 plan approved %s.old\n- 2026-10-01 Decisions swept S1\n' "$_wl_s" "$_wl_p" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^S1  plan  " "plan approved <plan>.old does not approve <plan>"
  printf -- '- 2026-10-01 spec approved %s.old\n' "$_wl_s" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^S1  brainstorm  " "spec approved <spec>.old does not approve <spec>"
  printf -- '- 2026-10-01 spec approved %s\n- 2026-10-01 plan approved %s\n- 2026-10-01 Decisions swept S1\n' "$_wl_s" "$_wl_p" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^S1  planned  " "the exact lines still make it planned"
}
```

- [ ] **Step 2: Run; it fails.** `TESTS_ONLY=test_lanes_next_whole_line_ledger sh tests/overnight_lanes_test.sh` — today `grep -qF` matches `Decisions swept S10` and both `.old` lines, so the first three assertions see `planned`/`plan`.

- [ ] **Step 3: Implement.** Above `lanes_next`:

```sh
# ln_has FILE TEXT — FILE has a ledger line whose text after `- <date> ` is
# exactly TEXT (#56 R4: `Decisions swept S10` is not `Decisions swept S1`,
# and `plan approved <plan>.old` does not approve <plan>).
ln_has() { sed -n 's/^- [0-9-]* //p' "$1" 2>/dev/null | grep -qxF -- "$2"; }
```

and in `lanes_next` replace the three `grep -qF "<text>" "$_ln_led"` calls with `ln_has "$_ln_led" "<text>"` (same texts: `spec approved $_ln_spec`, `plan approved $_ln_plan`, `Decisions swept $_ln_id`).

- [ ] **Step 4: Run** the new test and every `next` test: `TESTS_ONLY="test_lanes_next_whole_line_ledger test_lanes_next test_lanes_next_all_planned_and_ambiguous test_lanes_next_plan_before_autopilot test_lanes_next_adopted_planned test_lanes_next_slug_forms" sh tests/overnight_lanes_test.sh` — all pass.

- [ ] **Step 5: Commit** — `git commit -m 'fix(overnight): next matches ledger lines whole (#56)' -- studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh`

Acceptance: R4; spec test 13.

---

### Task 3: skill text — the id rule, the slug and fetch first, `check-id` calls; contract greps

Review: final (mechanical: text). Wave 1, parallel with T1 and T2.

**Files:**
- Modify: `shared/omega/skills/autopilot/SKILL.md` — new-run bullets (:68-86), step 2's failure line (:141), readiness (:166)
- Modify: `studios/game-dev/skills/plan/SKILL.md:169-182` and `studios/game-dev/skills/brainstorm/SKILL.md:218-246`
- Test: `tests/omega_contracts/autopilot_contract.sh` (new function, called from `test_autopilot_contract`), `tests/studio_test.sh` (new function, added to `run_tests`)

**Interfaces:** Consumes the verb's spelling only: `studio-overnight check-id <id> [--plan <path>|-] [--ticket <ticket>|-] [--slug <slug>]` (T1). Keep every literal the existing contract tests pin — notably `an id or branch that another run uses`, `not \`off\`, not all digits`, `.studio/runs/<slug>.$(date -u +%Y%m%dT%H%M%SZ)`, `git worktree add --no-track -b run/<slug> <root>/.claude/worktrees/run-<slug> origin/<default>`, `` `git worktree add <path> run/<slug>` when the branch exists ``, `one \`AskUserQuestion\` with two questions`, `When \`next\` exits non-zero`, `no conflicting live or stopped run (slug, story, branch)`, `studio-state show\` after entering`, `no checkout holds run/<slug>`, ``The bare `<id>` form``.

- [ ] **Step 1: Failing contract tests.**

In `tests/omega_contracts/autopilot_contract.sh`, add and call it from `test_autopilot_contract` (next to `test_autopilot_run_worktree`):

```sh
# #56: a story id once used is not handed out again: the slug and a fetch
# come before the story list; the default id; check-id on every id.
test_autopilot_story_ids() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" 'studio-overnight check-id <id> --ticket <t> --slug <slug> --plan -' "the story list checks every id"
  assert_contains "$S" 'otherwise `<slug>-S<n>`' "the default id when the ticket does not fit"
  assert_contains "$S" '`KAN-1541-1`, `KAN-1541-2`' "rows sharing a ticket"
  assert_contains "$S" 'a story id `check-id` refuses' "a failing next names a taken id"
  _f="$(grep -n -F -m1 -- '**The slug and a fetch, before the story list.**' "$S" | cut -d: -f1)"
  _g="$(grep -n -F -m1 -- 'Then run `git fetch origin`, so the story ids' "$S" | cut -d: -f1)"
  _l="$(grep -n -F -m1 -- 'Then ask the story list' "$S" | cut -d: -f1)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$_f" ] && [ -n "$_g" ] && [ -n "$_l" ] && [ "$_f" -lt "$_l" ] && [ "$_g" -lt "$_l" ]; then
    _pass "the slug check and the fetch come before the story list"
  else _fail "the slug check and the fetch come before the story list ($_f, $_g, $_l)"; fi
  assert_not_contains "$S" '`git fetch origin`, then `git worktree add' "the run worktree step no longer fetches after the story list"
}
```

In `tests/studio_test.sh`, add (and append the name to the `run_tests` list after `test_plan_brainstorm_slug_form`):

```sh
# #56: plan and brainstorm check a manifest story's id first; the Stories
# table copies the manifest's ids.
test_plan_brainstorm_check_id() {
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  BR="$REPO_ROOT/studios/game-dev/skills/brainstorm/SKILL.md"
  for f in "$PL" "$BR"; do
    assert_contains "$f" 'Run `studio-overnight check-id <id>` there first' "$f checks the id after entering the run worktree"
    assert_contains "$f" 'before writing any file or ledger line' "$f stops before any write"
    assert_contains "$f" 'run the same `studio-overnight check-id <id>` first' "$f checks the <id> form under a manifest too"
    _a="$(grep -n -F -m1 -- 'Run `studio-overnight check-id <id>` there first' "$f" | cut -d: -f1)"
    _b="$(grep -n -F -m1 -- 'Run `studio-state show` after entering' "$f" | cut -d: -f1)"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]; then _pass "$f: check-id is the first step after entering"
    else _fail "$f: check-id is the first step after entering ($_a, $_b)"; fi
  done
  assert_contains "$BR" "The \`Story\` cells are the manifest's own ids" "the Stories table copies the manifest's ids"
}
```

- [ ] **Step 2: Run; they fail.** `sh tests/omega_test.sh` (it sources the contracts) and `TESTS_ONLY=test_plan_brainstorm_check_id sh tests/studio_test.sh` — none of the new literals exists; the order check sees empty line numbers.

- [ ] **Step 3: autopilot.** In the "A new run" list:
  - Insert before `- Then ask the story list` (:76) a new bullet:

    ```
       - **The slug and a fetch, before the story list.** Settle the run slug now (from `/omega:autopilot <slug>` or an `integration slug=<slug>` line; with neither, ask for it before the story list) and check it: not `off`, not all digits, not used by a live or stopped run. A done record is archived: `mv <root>/.studio/runs/<slug> <root>/.studio/runs/<slug>.$(date -u +%Y%m%dT%H%M%SZ)`. Then run `git fetch origin`, so the story ids below are checked against a fresh `origin/<default>`.
    ```
  - In the story-list bullet, after its first sentence, add:

    ```
         **Story ids are never reused in a project** (a ledger is keyed by its id and outlives the run). Propose each id by default: the ticket when it matches `^[A-Za-z0-9._-]+$` (`KAN-1541`; rows sharing a ticket get `KAN-1541-1`, `KAN-1541-2`), otherwise `<slug>-S<n>` (a ticket such as `#56` or a URL does not fit). Check every id, proposed or typed, from the main checkout: `studio-overnight check-id <id> --ticket <t> --slug <slug> --plan -` (`<t>` the row's ticket, or `-`). Exit 1: refuse and re-ask with its message and its suggested id, as for an id another run uses; exit 2: the id does not match the pattern, or `origin/HEAD` is not set (`git remote set-head origin --auto`).
    ```
  - *The run worktree* steps 1–2 become:

    ```
         1. The slug was checked, and `origin` fetched, before the story list (above).
         2. `git worktree add --no-track -b run/<slug> <root>/.claude/worktrees/run-<slug> origin/<default>`, or `git worktree add <path> run/<slug>` when the branch exists.
    ```
  - Step 2's failure line (:141): `(the manifest, a missing or ambiguous spec or plan)` → `(the manifest, a missing or ambiguous spec or plan, a story id \`check-id\` refuses: rename that row to the id it suggests)`.
  - Readiness (:166): after `no conflicting live or stopped run (slug, story, branch)` insert `, no story id another story already used (\`check-id\`'s rules)`.

- [ ] **Step 4: plan and brainstorm** (the same edit in both `<slug>/<id>` blocks). After step 3 (enter and check with `git rev-parse --show-toplevel`), insert step 4 and renumber `studio-state show` to 5 and `Continue as the <id> form` to 6:

    ```
    4. Run `studio-overnight check-id <id>` there first (its Plan, Ticket and
       slug come from the worktree's `.studio/run`). On a non-zero exit, print
       its output and stop, before writing any file or ledger line: another
       story in this project already used the id.
    ```
  Replace `The bare \`<id>\` form keeps today's meaning in the current checkout.` with:

    ```
    Invoked as `<id>` where the current checkout's `.studio/run` names a
    manifest that lists it, run the same `studio-overnight check-id <id>` first,
    before §0 writes anything. The bare `<id>` form keeps today's meaning in the
    current checkout: outside a manifest its ledger is spec-slug keyed, and the
    id is not checked.
    ```
  In brainstorm only, after the paragraph ending `` `studio-brief final` prints exactly those numbered items. ``, add:

    ```
    The `Story` cells are the manifest's own ids, copied exactly (`KAN-1541`,
    `<slug>-S1`); never invent or renumber one.
    ```

- [ ] **Step 5: Run; they pass.** `sh tests/omega_test.sh`, `sh tests/studio_test.sh`, `sh tests/pointer_skills_omega_test.sh`, `sh tests/pointer_skills_route_test.sh` — all green (the existing pins above still hold).

- [ ] **Step 6: Commit** — `git commit -m 'docs(skills): story ids are never reused — autopilot proposes and checks them; brainstorm and plan check first (#56)' -- shared/omega/skills/autopilot/SKILL.md studios/game-dev/skills/plan/SKILL.md studios/game-dev/skills/brainstorm/SKILL.md tests/omega_contracts/autopilot_contract.sh tests/studio_test.sh`

Acceptance: R1 (stated in autopilot; brainstorm's sentence), R3's three skill callers; spec test 16.

---

### Task 4: wire check-id into `next` and `start`; records keep their rows; fixture knob

Review: task (Opus). Wave 2: starts from the story branch with T1 and T2 on it.

**Files:**
- Modify: `studios/game-dev/bin/overnight-lanes.sh` — `mf_check`'s per-story list and loop head (:227-230), `lanes_run`'s record line (:2000), `lanes_next`'s loop head (:2093-2097)
- Modify: `tests/overnight_lanes_test.sh` — `lanes_fixture` (:511-599), new tests, `test_lanes_preflight_refuses_stopped_record` (:3537-3552), `run_tests`
- Modify: `docs/game-dev/PROGRESS.md` — one dated entry, newest first

**Interfaces:**
- Consumes: `ids_ok`, `ids_default_branch`, `ids_check ID TICKET SLUG PLAN D ROWS EMIT` (T1); `refuse`, `say`, `DEFAULT_BRANCH` (preflight), `MF_SLUG`, `MF_ROWS`.
- Produces: `LANES_MAIN_PRE=<dir>` fixture knob; `$RECORD/rows.tsv` (the run's rows, rewritten at every start).

Anchors: `grep -n 'print \$1 "\\\\t" \$5 }' studios/game-dev/bin/overnight-lanes.sh` (or read :226-232); `grep -n 'touch "\$RECORD/landed.tsv"\|^lanes_next()\|_ln_bs=""; _ln_pl=""' studios/game-dev/bin/overnight-lanes.sh`; `grep -n 'git commit -q --allow-empty -m init\|unset LANES_CONFIG LANES_CELLS\|a done record no longer conflicts' tests/overnight_lanes_test.sh`.

- [ ] **Step 1: Fixture knob.** In `lanes_fixture`: read `_lf_pre="${LANES_MAIN_PRE:-}"` with the other knobs; right after the `if [ "$_lf_progress" = 1 ] … fi` block and before `git remote add origin`:

```sh
    if [ -n "$_lf_pre" ]; then cp -R "$_lf_pre/." . && git add -A && git commit -q -m "main: files before the run"; fi
```
add `LANES_MAIN_PRE` to the `unset` line, and to the header comment: `LANES_MAIN_PRE=<dir> commits <dir>'s files on main before run/demo is cut, so the run branch inherits them (#56).` Add a helper next to it:

```sh
OLD_PLAN=docs/game-dev/plans/2026-10-02-mob-composer.md
# lanes_pre_stale DIR — KAN-1499's shipped story S1 as phoenix's main held it
# (#56): its ledger (plan approved OLD_PLAN, T1-T2 complete, shipped) and OLD_PLAN.
lanes_pre_stale() {
  mkdir -p "$1/.studio/ledger" "$1/docs/game-dev/plans"
  printf -- '- 2026-10-02 plan approved %s\n- 2026-10-02 T1 complete\n- 2026-10-02 T2 complete\n- 2026-10-03 shipped KAN-1499-mob-composer\n' \
    "$OLD_PLAN" > "$1/.studio/ledger/S1.md"
  printf '# Plan: mob composer\n\nStory: S1\n\n### Task 1: t\n' > "$1/$OLD_PLAN"
}
```

- [ ] **Step 2: Failing tests** (all in `run_tests`):

```sh
# ---- #56: story ids are checked by next and start ----
test_lanes_ids_next_refuses_stale() {               # spec test 9
  lanes_pre_stale "$TMP/pre-nis"
  LANES_MAIN_PRE="$TMP/pre-nis"; LANES_CELLS=dash; export LANES_MAIN_PRE LANES_CELLS
  lanes_fixture nis integration S1:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n' > "$P/.studio/ledger/demo.md"
  ( cd "$P" && git rm -q docs/game-dev/plans/2026-10-01-S1.md && git commit -qm "own plan not written yet" ) >/dev/null 2>&1
  assert_eq "$OLD_PLAN" "$(cd "$P" && grep -rlxF 'Story: S1' docs/game-dev/plans)" "the header search alone finds exactly the old plan"
  run_lanes next "$MFP"
  assert_eq 2 "$LS_STATUS" "next refuses the stale id"
  assert_contains "$LS_ERR" "^studio-overnight: story id 'S1' is taken: origin/main:\.studio/ledger/S1\.md belongs to another story (plan $OLD_PLAN, shipped KAN-1499-mob-composer)\$" "with check-id's message"
  assert_not_contains "$LS_OUT" "^S1  " "before the row is classified"
  assert_not_contains "$LS_OUT" "^next: " "and no next command"
}
test_lanes_ids_start_refuses_stale() {              # spec test 10
  lanes_pre_stale "$TMP/pre-sis"
  LANES_MAIN_PRE="$TMP/pre-sis"; export LANES_MAIN_PRE
  lanes_fixture sis integration S1:-
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "start --dry-run refuses a row reusing the stale S1"
  assert_contains "$LS_ERR" "story id 'S1' is taken: origin/main:\.studio/ledger/S1\.md belongs to another story" "the ledger reason"
  assert_contains "$LS_ERR" "story id 'S1' is taken: origin/main:$OLD_PLAN says 'Story: S1'" "the plan reason"
  assert_eq 0 "$(calls)" "no unit ran"
}
test_lanes_ids_ticket_id_seeds_clean() {            # spec test 11
  lanes_pre_stale "$TMP/pre-tis"
  LANES_MAIN_PRE="$TMP/pre-tis"; LANES_TASKS=2; export LANES_MAIN_PRE LANES_TASKS
  lanes_fixture tis integration KAN-1541:-
  run_lanes check-id KAN-1541
  assert_eq 0 "$LS_STATUS" "KAN-1541 is free beside the stale S1"
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next classifies it"
  assert_contains "$LS_OUT" "^KAN-1541  " "its row"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "start --dry-run passes"
  assert_eq "check: task rebuilt to 0/2 from the ledger" \
    "$(cd "$P" && STUDIO_STORY=KAN-1541 sh "$STATE_BIN" check --rebuild 2>&1 | tail -n 1)" "it seeds at task 0 of 2"
  # The fixture seeded KAN-1541 (task 0/2, no T lines). S1 seeded the same way
  # (tests/state_pointer_test.sh's pattern) reads the inherited S1.md's T1-T2.
  assert_eq "check: task rebuilt to 2/2 from the ledger" \
    "$(cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" init >/dev/null 2>&1 \
       && STUDIO_STORY=S1 sh "$STATE_BIN" set task 0/2 \
       && STUDIO_STORY=S1 sh "$STATE_BIN" check --rebuild 2>&1 | tail -n 1)" "the hazard it avoids: S1 on the same tree rebuilds to 2 of 2"
}
test_lanes_ids_slug_id_plans_clean() {              # spec test 12
  lanes_pre_stale "$TMP/pre-sid"
  LANES_MAIN_PRE="$TMP/pre-sid"; LANES_CELLS=dash; export LANES_MAIN_PRE LANES_CELLS
  lanes_fixture sid integration demo-S1:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-demo-S1.md\n- 2026-10-01 Decisions swept demo-S1\n' > "$P/.studio/ledger/demo.md"
  run_lanes check-id demo-S1
  assert_eq 0 "$LS_STATUS" "a <slug>-S<n> id is free beside the stale S1"
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next passes"
  assert_contains "$LS_OUT" "^demo-S1  planned  spec=docs/game-dev/specs/2026-10-01-demo.md  plan=docs/game-dev/plans/2026-10-01-demo-S1.md\$" "and plans it from its own plan"
}
test_lanes_ids_own_adopted_dry_run() {              # spec test 5
  _oa=docs/game-dev/plans/2026-10-01-S1.md; _oo=docs/superpowers/plans/2026-09-01-demo.md
  mkdir -p "$TMP/pre-oal/.studio/ledger" "$TMP/pre-oal/docs/game-dev/plans"
  printf -- '- 2026-09-30 source %s spec -\n- 2026-09-30 adopted %s -> %s\n- 2026-10-01 shipped S1-b\n' "$_oo" "$_oo" "$_oa" > "$TMP/pre-oal/.studio/ledger/S1.md"
  printf '# Plan\n\nStory: S1\n' > "$TMP/pre-oal/$_oa"
  LANES_MAIN_PRE="$TMP/pre-oal"; export LANES_MAIN_PRE
  lanes_fixture oal integration S1:-
  run_lanes check-id S1
  assert_eq 0 "$LS_STATUS" "a landed adopted ledger for the row's own plan is the story's own"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "start --dry-run passes"
}
test_lanes_ids_direct_resume_after_landing() {      # Review Focus 1
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture idr direct A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "A lands on main"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(git -C "$P" ls-tree --name-only origin/main -- .studio/ledger/ | grep -c '/A\.md$')" "A's ledger is on main now"
  rm -f "$P/.studio/runs/demo/done"   # a stopped record of this run: a resume
  run_lanes check-id A
  assert_eq 0 "$LS_STATUS" "its own landed ledger does not make A taken"
  run_lanes start --dry-run "$MFP"
  assert_not_contains "$LS_ERR" "is taken" "a resume after landing is not refused for its own id"
}
test_lanes_ids_record_keeps_rows() {                # D2
  lanes_fixture rkr integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_file "$P/.studio/runs/demo/rows.tsv" "the record keeps the run's rows"
  assert_contains "$P/.studio/runs/demo/rows.tsv" "^A	A-b	" "A's row"
  run_lanes check-id A --slug other --plan -
  assert_contains "$LS_ERR" "story id 'A' is taken: run demo (record \.studio/runs/demo) lists it" "check-id reads it"
}
```

And in `test_lanes_preflight_refuses_stopped_record` (D9) replace its last two lines with:

```sh
  : > "$P/.studio/runs/alpha/done"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a done record still lists S1 (#56 rule 3)"
  assert_not_contains "$LS_ERR" "is used by stopped run alpha" "it is no longer a stopped-run conflict (AC8)"
  assert_contains "$LS_ERR" "story id 'S1' is taken: run alpha (record \.studio/runs/alpha) lists it" "check-id's record rule names it"
```

- [ ] **Step 3: Run; they fail.** `TESTS_ONLY="test_lanes_ids_next_refuses_stale test_lanes_ids_start_refuses_stale test_lanes_ids_ticket_id_seeds_clean test_lanes_ids_slug_id_plans_clean test_lanes_ids_own_adopted_dry_run test_lanes_ids_direct_resume_after_landing test_lanes_ids_record_keeps_rows test_lanes_preflight_refuses_stopped_record" sh tests/overnight_lanes_test.sh` — expected: 9 and 10 fail (exit 0: nothing checks ids yet); the record test fails (no `rows.tsv` in the record); D9's new lines fail (exit 0). Tests 5, 11, 12 and the direct-resume test pass already: they guard against the wiring refusing a free or own id, so they can only go red in Step 4 (see the Falsify pass, item 5).

- [ ] **Step 4: Implement.**
  - `mf_check`, the per-story list and loop (:228-230):
    ```sh
      awk -F'\t' '!($1 in seen) { seen[$1] = 1; print $1 "\t" $5 "\t" $3 }' "$MF_ROWS" > "$MF_TMP/stories"
      while IFS='	' read -r _id _plan _tkt; do
        printf '%s\n' "$_id" | grep -Eq '^[A-Za-z0-9._-]+$' || continue
        # #56 R3: the backstop — the id is checked against the default branch fetched above.
        [ -z "$DEFAULT_BRANCH" ] \
          || ids_check "$_id" "$_tkt" "$MF_SLUG" "${_plan:--}" "$DEFAULT_BRANCH" "$MF_ROWS" refuse < /dev/null || :
    ```
    (the rest of the loop body is unchanged).
  - `lanes_run` (:2000): `mkdir -p "$RECORD" && touch "$RECORD/landed.tsv" && cp "$MF_ROWS" "$RECORD/rows.tsv" || { rm -f "$LOCK"; say "cannot create $RECORD"; exit 2; }` — `MF_ROWS` is `$RUN_DIR/rows.tsv` there. Comment: `# the record keeps the run's rows: check-id's rule 3 (#56 D2)`.
  - `lanes_next`, after `mf_load "$1" || exit 2`:
    ```sh
      _ln_db="$(ids_default_branch)" || { say "origin/HEAD is not set — run: git remote set-head origin --auto"; exit 2; }
    ```
    and as the first statements of the row loop, after `[ -n "$_ln_id" ] || continue` (the raw Plan cell, before `next_match` replaces it; `_ln_d` is the deps column, hence `_ln_db`):
    ```sh
        # #56 R3: a story id used before in this project is refused before classification.
        if ids_ok "$_ln_id"; then
          ids_check "$_ln_id" "$_ln_t" "$MF_SLUG" "${_ln_plan:--}" "$_ln_db" "$MF_ROWS" say < /dev/null || exit 2
        fi
    ```

- [ ] **Step 5: Run** the eight tests above (pass), then `sh tests/overnight_ids_test.sh`, then the whole `sh tests/overnight_lanes_test.sh`. For any other pre-existing lanes test that now fails: if it reuses an id across runs or through a done record (rule 3) or a ledger on main (rule 1), the new refusal is the spec's behaviour — change that test's assertion as in D9 and name it in the commit body; anything else is a bug in this task. Watch `test_lanes_recheck_race_one_wins` (alpha and gamma share `S1`): both preflights pass before either run creates its record or report dir (the lock hook sleeps between preflight and lock), so the loser must still lose at the re-check; if the re-check runs `mf_check` after the winner wrote its record, the loser also gets check-id's record line — still a refusal; widen that test's message assertion only if it pins one exact line. Run it three times.

- [ ] **Step 6: PROGRESS.** Add a dated entry at the top of `docs/game-dev/PROGRESS.md` in its existing style: `### 2026-10-07 — Unique story ids (#56)` — phoenix's `S1` inherited KAN-1499's shipped ledger; `check-id` and its four rules; autopilot proposes `KAN-<n>` / `<slug>-S<n>` and checks; brainstorm, plan, `next` and `start` refuse a reused id; `next` matches ledger lines whole; records keep `rows.tsv`; spec and plan paths.

- [ ] **Step 7: Commit** — `git commit -m 'feat(overnight): next and start refuse a reused story id; records keep their rows (#56)' -- studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh docs/game-dev/PROGRESS.md`

Acceptance: R3 (`next`, `start`/`--dry-run`, and `--detach` through `lanes_start --check`'s `mf_check`); spec tests 5, 9, 10, 11, 12; D2, D9; Review Focus 1.

---

### Task 5: final whole-branch review, fix wave, gate, PR

- [ ] Standalone whole-branch review on Opus over `72523a5..HEAD` against the spec and this plan (T2 and T3 get their only review here).
- [ ] One fresh fixer for the findings (minors batched); re-review only per the Global Constraints rule.
- [ ] Full gate once on the integrated branch: `sh tests/run_all.sh`, then `sh integrations/multica/tests/run.sh`.
- [ ] PR `Closes #56`, body with D2 (records gain `rows.tsv`) and D9 (an existing assertion changed by rule 3). Do not merge, install or pull into the main checkout while `studio-overnight status` shows a live run; otherwise merge once green (standing omega-ai merge authority) and leave the reinstall as a noted follow-up.

## Falsify pass

Checked against the code at 72523a5:

1. **Anchors exist as described.** `mf_load` :47-73; `mf_conflicts` :91-136; `mf_check` :161-286 with the fetch at :213 and the per-story `awk … print $1 "\t" $5` + loop at :228-229; `lanes_run` :1992 with the record line at :2000; `next_match` :2064-2085; `lanes_next` :2090 with `grep -qF` at :2107, :2109, :2110. `studio-overnight`: `usage()` :261, `preflight()` :485 with `DEFAULT_BRANCH` at :531-533, channel/progress sourced at :1961-1963, `next)` dispatch :1986-1996. `lanes_fixture` :528-599 (push + `set-head` :550, `checkout -b run/demo` :551, `unset` :598). The `<slug>/<id>` blocks: plan :169-182, brainstorm :218-231; autopilot story list :76, run-worktree steps :80-81.
2. **Changed after the check: records have no `rows.tsv`.** The spec (rule 3, test 7) says a record lists ids in `rows.tsv`; at 72523a5 `run_populate` copies rows into the report dir only (`$RUN_DIR/rows.tsv`, :1973), and the record holds `landed.tsv`/`done`/`gate`/`final`. Added D2 (the record now keeps `rows.tsv`; old records fall back to `landed.tsv` and their newest report) and `test_lanes_ids_record_keeps_rows`.
3. **Changed: where to source.** A top-level `.` in `studio-overnight` would break `test_overnight_deny_file_required` (it copies exactly the top-level-sourced files to a temp bin). Moved the source line into `overnight-lanes.sh` (D1).
4. **Changed: an existing test contradicts the spec.** `test_lanes_preflight_refuses_stopped_record` expects a done record to stop conflicting; rule 3 says a done record's ids are taken. Rewritten in T4 (D9).
5. **Tests fail on today's code.** Every T1 test calls `check-id`, an unknown verb today (`*) usage >&2; exit 2`), so status and message assertions fail; `test_ids_docs` fails on the missing file. T2's first three assertions see `planned`/`plan` because `grep -qF` matches `Decisions swept S10` and the `.old` lines. T3's literals do not exist yet. T4: tests 9 and 10 exit 0 today (verified by reading `mf_check` and `lanes_next`: nothing compares ids with `origin/main`); the record test fails on the missing `rows.tsv`; D9's new lines fail (exit 0 today). Tests 5, 11, 12 and the direct-resume test are **guards against over-refusal**: on the branch after T1 they can only fail if T4's wiring refuses a free id, so before T4 they pass after their `check-id` line — they are falsifiable by T4, not by today's code, and that is their purpose (each also fails on 72523a5 itself at its first `check-id` call).
6. **Parallel hunks.** T1 edits `overnight-lanes.sh` at :13 only; T2 at :2087-2111; T3 no code. T1's tests are a new file; T2 edits `overnight_lanes_test.sh` near :866 and the `run_tests` line :4064; T3 edits skills and two contract test files. T4 (sequential) edits `overnight-lanes.sh` :228-230, :2000, :2093-2097 — next to T2's hunk, which is why it waits for T2.
7. **git behaviour relied on.** `git grep -l -i -F -e … <ref> -- <path>` prints `<ref>:<path>` (checked on this repo: `refs/remotes/origin/main:docs/game-dev/plans/2026-10-05-setup-preflight.md`); `git grep` has no `-x` (checked: `git grep -h` lists no line-regexp option on git 2.39.3); `git ls-tree --name-only <ref> -- <dir>/` lists the directory's entries (checked on this repo).
8. **Existing suites that might now refuse.** Standard lanes fixtures put only an empty `init` commit on `main`, so rows are free. Direct-mode landings put `A.md` on `main` with `plan approved` = the row's Plan → own (pinned). The adopt fixture pushes the run commit to `main` (`adopt_lanes_fixture`), whose `S1.md` last `plan approved` is the row's Plan → own. Two-run tests use `A…` vs `S1…`; the one test sharing `S1` across slugs is the race test (Step 5's note). `test_lanes_preflight_done_record_needs_archive` archives `demo` with an empty `landed.tsv` and no `rows.tsv`: its base slug is this slug, so no report fallback → free, as it expects.
9. **Coverage.** R1 → T3 (autopilot, brainstorm sentence); R2 → T1; R3 → T3 (autopilot, brainstorm, plan), T4 (`next`, `start`, and `--detach` through `lanes_start --check` → `mf_check`); R4 → T2; R5 → T1. Spec tests: 1, 2, 3, 4, 6, 7, 8, 14, 15 → T1; 13 → T2; 16 → T3; 5, 9, 10, 11, 12 → T4.
