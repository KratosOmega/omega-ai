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
    mkdir -p .studio/ledger; printf '%s\n' "$4" > ".studio/ledger/$3.md"; printf x > .marker
    git add -A; git commit -q -m ledger; git push -q -f origin "HEAD:refs/heads/$2" ) >/dev/null 2>&1
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
test_ids_integration_inherits_main() {               # review I1 + M4 (case)
  _own=docs/game-dev/plans/2026-10-01-S1.md
  mkdir -p "$TMP/pre6i/.studio/ledger" "$TMP/pre6i/docs/game-dev/plans"
  printf -- '- 2026-10-01 plan approved %s\n- 2026-10-01 T1 complete\n' "$_own" > "$TMP/pre6i/.studio/ledger/S1.md"
  printf '# Plan\n\nStory: S1\n' > "$TMP/pre6i/$_own"
  ids_fixture t6i "$TMP/pre6i" "S1|S1|$_own"
  push_ledger t6i integration/other S1 "$(printf -- '- 2026-10-01 plan approved %s\n- 2026-10-01 T1 complete' "$_own")"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "integration/other inherited main's own S1 ledger unchanged: not a second claim"
  push_ledger t6i integration/other S1 "$(printf -- '- 2026-10-01 plan approved %s\n- 2026-10-01 T1 complete\n- 2026-10-02 T2 complete' "$_own")"
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "integration/other changed the ledger: taken"
  assert_contains "$IS_ERR" "story id 'S1' is taken: origin/integration/other:\.studio/ledger/S1\.md belongs to run other's" "integration message"
  ids_fixture t6c - 'S1|-|-'
  push_ledger t6c integration/other s1 '- 2026-10-01 shipped S1-b'
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "s1.md on integration/other makes S1 taken (any case)"
  assert_contains "$IS_ERR" "origin/integration/other:\.studio/ledger/s1\.md belongs" "names the file as it is"
}
test_ids_plan_case_and_color() {                     # review M4 (case), M1
  mkdir -p "$TMP/pre9/docs/game-dev/plans"; printf '# Plan\n\nStory: s1\n' > "$TMP/pre9/$OLD_PLAN"
  ids_fixture t9 "$TMP/pre9" 'S1|-|-'
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "'Story: s1' in a main plan makes S1 taken (any case)"
  git -C "$P" config color.ui always
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "still taken with color.ui=always"
  assert_contains "$IS_ERR" "origin/main:$OLD_PLAN says 'Story: S1'\$" "rule 4 line is clean of color codes"
}
test_ids_default_ref_missing() {                     # review M2
  ids_fixture t10 - 'S1|-|-'
  git -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/nope
  run_ids check-id S1
  assert_eq 2 "$IS_STATUS" "origin/HEAD names a ref that does not exist"
  assert_contains "$IS_ERR" "origin/HEAD is not set — run: git remote set-head origin --auto" "start's message"
}
test_ids_slug_dash_and_readonly() {                  # review M3, M4 (writes nothing)
  pre_stale "$TMP/pre11"
  ids_fixture t11 "$TMP/pre11" 'S1|-|-'
  run_ids check-id S1 --slug -
  assert_eq 1 "$IS_STATUS" "taken"
  assert_eq "studio-overnight: pick an unused id: the ticket, or <run slug>-S<n>" "$(tail -n 1 "$IS_ERR")" "--slug - is no slug: no --S1 suggestion"
  _before="$(cd "$P" && find .studio -type f | sort | paste -sd ' ' -)"
  run_ids check-id S1
  assert_eq "" "$(git -C "$P" status --porcelain)" "check-id leaves the tree clean"
  assert_eq "$_before" "$(cd "$P" && find .studio -type f | sort | paste -sd ' ' -)" "and writes nothing under .studio"
}
test_ids_run_records() {                             # spec test 7 (+ legacy, linked worktree)
  ids_fixture t7 - 'S1|-|-'
  _rr="$P/.studio/runs"
  # Rows on another branch than this story's (S1-b): another story's id (#56 FI1).
  mkdir -p "$_rr/old"; printf 'S1\told-b\tS1\t-\t-\t\n' > "$_rr/old/rows.tsv"; : > "$_rr/old/landed.tsv"; : > "$_rr/old/done"
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
  printf 'S1\told-b\tS1\t-\t-\t\n' > "$P/.studio/reports/overnight-legacy-20261001-000000/rows.tsv"
  run_ids check-id S1
  assert_contains "$IS_ERR" "run legacy (record \.studio/runs/legacy) lists it" "and its newest report's rows.tsv (D2)"
  rm -rf "$_rr/legacy"; mkdir -p "$_rr/demo"; printf 'S1\told-b\tS1\t-\t-\t\n' > "$_rr/demo/rows.tsv"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "this run's own record does not count"
  run_ids check-id S1 --slug other
  assert_eq 1 "$IS_STATUS" "under another slug, demo's record is another run's"
}
# #56 FI1: a half-done story carried from an earlier run into a new one
# keeps its id: a record's row on this story's own Branch does not count.
test_ids_carried_over_branch() {
  ids_fixture tco - 'S1|-|-'
  _rr="$P/.studio/runs"
  mkdir -p "$_rr/old.20261001T000000Z"; printf 's1\tS1-b\tS1\t-\t-\t\n' > "$_rr/old.20261001T000000Z/rows.tsv"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "an archived record's row on this story's branch (from the manifest row): the same story carried over"
  run_ids check-id S1 --branch S1-b
  assert_eq 0 "$IS_STATUS" "--branch names the same branch: free"
  run_ids check-id S1 --branch other-b
  assert_eq 1 "$IS_STATUS" "same id on a different branch: taken"
  assert_contains "$IS_ERR" "story id 'S1' is taken: run old (record \.studio/runs/old\.20261001T000000Z) lists it\$" "names the record"
  run_ids check-id S1 --branch -
  assert_eq 1 "$IS_STATUS" "--branch -: unknown, no exception"
  : > "$_rr/old.20261001T000000Z/rows.tsv"; printf 'S1\tintegration/old\tabc\t1\n' > "$_rr/old.20261001T000000Z/landed.tsv"
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "a landed.tsv line has no branch: still taken"
  rm -rf "$_rr/old.20261001T000000Z"; mkdir -p "$_rr/leg" "$P/.studio/reports/overnight-leg-20261001-000000"; : > "$_rr/leg/landed.tsv"
  printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$P/.studio/reports/overnight-leg-20261001-000000/rows.tsv"
  run_ids check-id S1
  assert_eq 0 "$IS_STATUS" "a pre-#56 record's report rows on this story's branch: carried over"
  run_ids check-id S1 --branch x-b
  assert_eq 1 "$IS_STATUS" "and on another branch: taken"
  rm -f "$P/.studio/run"
  run_ids check-id S1
  assert_eq 1 "$IS_STATUS" "no manifest row: no default branch, no exception"
  run_ids check-id S1 --branch S1-b
  assert_eq 0 "$IS_STATUS" "--branch alone gives it"
}
test_ids_defaults_any_case() {                       # review m-B
  _own=docs/game-dev/plans/2026-10-01-S1.md
  mkdir -p "$TMP/pre-dc/.studio/ledger" "$TMP/pre-dc/docs/game-dev/plans"
  printf -- '- 2026-10-01 plan approved %s\n' "$_own" > "$TMP/pre-dc/.studio/ledger/S1.md"
  printf '# Plan\n\nStory: S1\n' > "$TMP/pre-dc/$_own"
  ids_fixture tdc "$TMP/pre-dc" "S1|KAN-7|$_own"
  run_ids check-id s1
  assert_eq 0 "$IS_STATUS" "check-id s1 takes row S1's defaults (its Plan): its own ledger"
  run_ids check-id s1 --plan -
  assert_eq "studio-overnight: use 'KAN-7' instead" "$(tail -n 1 "$IS_ERR")" "and its Ticket"
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
  assert_contains "$IS_ERR" "^studio-overnight: check-id: story id 'S 1' must match \^\[A-Za-z0-9\._-\]" "says why"
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
  assert_contains "$TMP/help" "check-id <id> \[--plan <path>|-\] \[--ticket <ticket>|-\] \[--slug <slug>\] \[--branch <branch>|-\]" "usage names check-id"
  assert_contains "$TMP/help" "0 free · 1 taken" "and its exit codes"
  assert_contains "$REPO_ROOT/README.md" "studio-overnight check-id <id>" "README documents check-id"
  assert_contains "$REPO_ROOT/README.md" "check-id: 0 free · 1 taken · 2 usage" "README's table gives its exit codes"
}

run_tests test_ids_main_ledger_taken test_ids_main_plan_only test_ids_run_branch_plan_not_checked \
  test_ids_own_ledger test_ids_integration_branches test_ids_integration_inherits_main test_ids_plan_case_and_color test_ids_default_ref_missing test_ids_slug_dash_and_readonly test_ids_run_records test_ids_carried_over_branch test_ids_defaults_any_case test_ids_case_insensitive \
  test_ids_suggestion test_ids_defaults_need_listed_row test_ids_usage test_ids_docs
