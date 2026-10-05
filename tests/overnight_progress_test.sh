#!/bin/sh
# The progress bar and rough finish time of `studio-overnight status` (#37),
# against hand-built run dirs: no stub sessions, no runs. A fixture is a
# project with story state files, a live lock (a dummy process named
# studio-overnight) and a run dir holding rows.tsv, chains, stories/ and the
# lanes' units.tsv. Times are chosen so a unit is a round number of minutes.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
BIN="$REPO_ROOT/studios/game-dev/bin"
RUNNER="$BIN/studio-overnight"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
DUMMIES=""
trap '{ for _d in $DUMMIES; do kill "$_d"; done; wait; } 2>/dev/null; rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
# A fixed machine reading, so no test depends on the real machine's load.
ENVFX="$TMP/envfx"; mkdir -p "$ENVFX"; echo Linux > "$ENVFX/uname"
STUDIO_ENV_FIXTURE="$ENVFX"; export STUDIO_ENV_FIXTURE

# proj NAME — a fresh project $P with a run dir $RD (reports/overnight-demo-1)
# and no lock.
proj() {
  P="$TMP/$1"; rm -rf "$P"; mkdir -p "$P/.studio/stories"
  ( cd "$P" && git init -q -b main && git commit -q --allow-empty -m init ) >/dev/null 2>&1
  RD="$P/.studio/reports/overnight-demo-1"; mkdir -p "$RD/stories" "$RD/lanes/1" "$RD/lanes/2" "$RD/claims"
  printf '# Run: demo\nMode: integration\nTarget: integration/demo\nDocs: x\nGoal: g\n' > "$RD/manifest.md"
  : > "$RD/rows.tsv"; : > "$RD/chains"
}
# live — a lock naming a live process whose argv holds studio-overnight.
live() {
  sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; DUMMIES="$DUMMIES $DUMMY"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T01:00:00Z\n' "$DUMMY" "$RD" > "$P/.studio/overnight.lock"
}
# story ID DEPS RECORD TASK — a manifest row, its record and its state file.
story() {
  printf '%s\t%s-b\t%s\t-\t-\t%s\n' "$1" "$1" "$1" "$2" >> "$RD/rows.tsv"
  printf '%s\n' "$3" > "$RD/stories/$1"
  printf '# Studio State\n\nstage: execute\nspec: -\nplan: -\ntask: %s\nbranch: -\nmilestone: prototype\n\n## Ledger\n\n' "$4" > "$P/.studio/stories/$1.md"
}
# chain K WAITS MEMBERS — a chains line.
chain() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RD/chains"; }
# units DIR LABEL OUTCOME MINUTES… — rows for DIR/units.tsv, numbered in order.
units() {
  _u_d="$1"; _u_l="$2"; _u_o="$3"; shift 3
  for _u_m in "$@"; do
    mkdir -p "$_u_d"
    _u_n=$(( $(cat "$_u_d/units.tsv" 2>/dev/null | wc -l) + 1 ))
    printf '%s\t%s\t0\t1.00\t%s\t0\t%s\n' "$_u_n" "$_u_l" "$_u_m" "$_u_o" >> "$_u_d/units.tsv"
  done
}
# running DIR ID LABEL SECS_AGO — a unit that started SECS_AGO ago.
running() {
  printf '%s %s\n' "$(( $(date +%s) - $4 ))" "1-$2-$3" > "$1/unit.now"
  printf '%s\n' "${2:+$2 }$3" > "$1/current"
}
# st — `status` in $P: ST_RC; st.out.
st() { ST_RC=0; ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1 || ST_RC=$?; }

test_progress_fresh_no_data() {
  proj fresh; story A - running "0/3"; chain 1 - A; live
  st
  assert_contains "$TMP/st.out" "^progress: \[                    \] 0%  0/6 units · ETA: after the first unit$" "5 units for A (3 tasks, final review, finish) plus the final step; no data, no ETA"
  assert_contains "$TMP/st.out" "^A  lane -  running  unit -  task 0/3   \[              \] 0%$" "A's own 14-wide bar"
  assert_eq progress "$(sed -n 1p "$TMP/st.out" | cut -c1-8)" "the progress line comes first"
}
test_progress_mid_run_eta() {
  proj mid; story A - running "3/6"; chain 1 - A; live
  mkdir -p "$RD/claims/1"; echo 1 > "$RD/claims/1/lane"
  units "$RD/lanes/1" A-T1 progress 10; units "$RD/lanes/1" A-T2 progress 20; units "$RD/lanes/1" A-T3 progress 30
  running "$RD/lanes/1" A T4 600
  st
  # done 3; left T4..T6 + review + finish = 5; planned 8 + the final step = 9.
  assert_contains "$TMP/st.out" "^progress: \[======              \] 33%  3/9 units · ETA ~[0-9][0-9]:[0-9][0-9] (in 1h50m, rough: 3 units timed)$" "mean task 20 min: 10 left of T4, then 20+20+20+20, plus the final step 20"
  assert_contains "$TMP/st.out" "^A  lane 1  running  unit A T4  task 3/6   \[=====         \] 37%$" "the story's bar: 3 of 8"
}
test_progress_past_run_median() {
  proj past; story A - running "0/2"; chain 1 - A; live
  mkdir -p "$RD/../overnight-demo-0/lanes/1" "$RD/../overnight-demo-0/final"
  units "$RD/../overnight-demo-0/lanes/1" A-T1 progress 10; units "$RD/../overnight-demo-0/lanes/1" A-T2 progress 30
  units "$RD/../overnight-demo-0/lanes/1" A-T3 progress 20; units "$RD/../overnight-demo-0/lanes/1" A-final-review progress 40
  units "$RD/../overnight-demo-0/lanes/1" A-finish done 10; units "$RD/../overnight-demo-0/lanes/1" A-T4 noprog 500
  units "$RD/../overnight-demo-0/final" progress progress 20
  st
  # Medians: task 20, final review 40, finish 10, other 20: 2*20 + 40 + 10 + 20.
  assert_contains "$TMP/st.out" "(in 1h50m, rough: 6 past units)$" "past runs' medians, only progress and done rows"
  assert_contains "$TMP/st.out" "^progress: \[                    \] 0%  0/5 units" "nothing done in this run"
}
test_progress_repair_adds_a_unit() {
  proj rep; story A - running "2/2"; chain 1 - A; live
  mkdir -p "$RD/claims/1"; echo 1 > "$RD/claims/1/lane"
  units "$RD/lanes/1" A-T1 progress 10; units "$RD/lanes/1" A-T2 progress 10; units "$RD/lanes/1" A-final-review progress 10
  running "$RD/lanes/1" A finish 0
  st
  assert_contains "$TMP/st.out" "^progress: \[============        \] 60%  3/5 units" "3 done; finish and the final step left"
  running "$RD/lanes/1" A gate-repair 0
  st
  assert_contains "$TMP/st.out" "^progress: \[==========          \] 50%  3/6 units" "a running repair unit is one more planned: the bar steps back"
  assert_contains "$TMP/st.out" "^A  lane 1  running  unit A gate-repair  task 2/2   \[========      \] 60%$" "and so is the story's"
}
test_progress_chains_waits_and_held() {
  proj ch; story A - running "2/3"; story C - running "0/5"; story D "A,C" queued "0/1"; story H - "held held by operator until 2026-10-04T12:00:00Z" "0/9"
  chain 1 - A; chain 2 - C; chain 3 "A,C" D; chain 4 - H; live
  mkdir -p "$RD/claims/1" "$RD/claims/2"; echo 1 > "$RD/claims/1/lane"; echo 2 > "$RD/claims/2/lane"
  units "$RD/lanes/1" A-T1 progress 10; units "$RD/lanes/1" A-T2 progress 10
  st
  # Unit mean 10: A 3 left (30), C 7 (70), D 3 (30) after both; H is held. 70 + 30 + the final step 10.
  assert_contains "$TMP/st.out" "(in 1h50m, rough: 2 units timed)$" "slowest chain, the waiting chain after the chains it waits on"
  assert_contains "$TMP/st.out" "^H  lane -  held  unit -  task 0/9   \[              \] 0%  (excluded from ETA)$" "a held story says so"
  assert_not_contains "$TMP/st.out" "^A .*excluded" "only the held story"
}
test_progress_ended_run_no_eta() {
  proj end; story A - "landed abc" "3/3"; story B - "stopped stop: broke" "1/2"; chain 1 - A; chain 2 - B
  units "$RD/lanes/1" A-T1 progress 10 10 10; units "$RD/lanes/1" A-final-review progress 10; units "$RD/lanes/1" A-finish done 10
  units "$RD/lanes/2" B-T1 progress 10
  mkdir -p "$RD/final"; units "$RD/final" progress progress 5
  printf '# Overnight run — demo\nEnding: partial: 1 landed, 1 stopped, 0 skipped\n\n## Resume\n\ncd x\n' > "$RD/report.md"
  st
  assert_eq 1 "$ST_RC" "an ended run exits 1"
  assert_contains "$TMP/st.out" "^progress: \[====================\] 100%  7/7 units$" "all stories ended and the final step ran: the final value, no ETA"
  assert_not_contains "$TMP/st.out" "ETA" "an ended run has no ETA"
  assert_contains "$TMP/st.out" "^A  lane -  landed  unit -  task 3/3   \[==============\] 100%$" "a landed story is full"
  assert_contains "$TMP/st.out" "^B  lane -  stopped  unit -  task 1/2   \[==============\] 100%$" "so is a stopped one"
  # No final unit and an ending that is not done: the bar stops short.
  rm -rf "$RD/final"
  st
  assert_contains "$TMP/st.out" "^progress: \[=================   \] 85%  6/7 units$" "the final step not done: 6 of 7, rounded down"
  printf '# Overnight run — demo\nEnding: done\n' > "$RD/report.md"
  st
  assert_contains "$TMP/st.out" "^progress: \[====================\] 100%  7/7 units$" "a done ending counts the final step"
}
test_progress_single_plan() {
  proj single; rm -rf "$RD"; RD="$P/.studio/reports/overnight-20261004-010000"; mkdir -p "$RD"
  printf '# Studio State\n\nstage: execute\nspec: -\nplan: -\ntask: 2/3\nbranch: -\nmilestone: prototype\n\n## Ledger\n\n' > "$P/.studio/STATE.md"
  units "$RD" T1 progress 10; units "$RD" T2 progress 10
  running "$RD" "" T3 300
  live
  st
  assert_eq 0 "$ST_RC" "a live single-plan run"
  # done 2; T3 + review + finish left: 5 planned, no final step; T3 has 5 min left, then 10 + 10.
  assert_contains "$TMP/st.out" "^progress: \[========            \] 40%  2/5 units · ETA ~[0-9][0-9]:[0-9][0-9] (in 0h25m, rough: 2 units timed)$" "tasks left plus review plus finish, one chain"
  assert_contains "$TMP/st.out" "^run: $RD$" "the existing lines stay"
  assert_contains "$TMP/st.out" "^spent: " "the existing lines stay"
  # Ended: the bar at its final value, no ETA.
  rm -f "$P/.studio/overnight.lock" "$RD/unit.now"
  units "$RD" T3 progress 10; units "$RD" final-review progress 10; units "$RD" finish done 10
  printf '# Overnight run\nEnding: done\n\n## Resume\n\ncd x\n' > "$RD/report.md"
  printf '# Studio State\n\nstage: idle\nspec: -\nplan: -\ntask: -\nbranch: -\nmilestone: prototype\n\n## Ledger\n\n' > "$P/.studio/STATE.md"
  st
  assert_eq 1 "$ST_RC" "an ended run exits 1"
  assert_contains "$TMP/st.out" "^progress: \[====================\] 100%  5/5 units$" "an ended single-plan run: full bar, no ETA"
  assert_not_contains "$TMP/st.out" "ETA" "no ETA once ended"
}
test_progress_retry_and_unit_kinds() {
  proj kinds; story A - running "1/2"; chain 1 - A; live
  mkdir -p "$RD/claims/1"; echo 1 > "$RD/claims/1/lane"
  units "$RD/lanes/1" A-T1 noprog 99; units "$RD/lanes/1" A-T1-retry progress 10
  units "$RD/lanes/1" "A-T1" "timed out" 99
  st
  assert_contains "$TMP/st.out" "^progress: .* 20%  1/5 units" "a retry that made progress is one done unit"
  assert_contains "$TMP/st.out" "rough: 1 units timed" "unfinished units are not timed"
}

test_progress_scale_with_past_rows() {
  # The past median is computed once per kind and only the newest 20 runs are read:
  # many past rows and many stories must not make status slow.
  proj scale; _i=1
  while [ "$_i" -le 10 ]; do story "S$_i" - running "0/4"; chain "$_i" - "S$_i"; _i=$((_i + 1)); done
  live
  _t0=$(date +%s); st; _tb=$(( $(date +%s) - _t0 ))   # the baseline on this machine, no history
  _r=1
  while [ "$_r" -le 30 ]; do
    _pd="$P/.studio/reports/overnight-old-$_r/lanes/1"; mkdir -p "$_pd"
    awk -v r="$_r" 'BEGIN { for (i = 1; i <= 100; i++) printf "%d\tS1-T%d\t0\t1.00\t%d\t0\tprogress\n", i, i, 5 + (i * r) % 17 }' > "$_pd/units.tsv"
    touch -t "2026010100$(printf '%02d' "$_r")" "$P/.studio/reports/overnight-old-$_r"
    _r=$((_r + 1))
  done
  _t0=$(date +%s); st; _t1=$(date +%s)
  _fast=fast; [ $(( _t1 - _t0 )) -le $(( _tb + 3 )) ] || _fast="slow ($(( _t1 - _t0 )) s vs $_tb s)"
  assert_eq fast "$_fast" "3000 past rows add under 3 s to status over the same 10 stories with none"
  assert_contains "$TMP/st.out" "rough: 2000 past units" "only the newest 20 runs' rows are read"
}
test_progress_held_single_plan_no_eta() {
  proj sheld; rm -rf "$RD"; RD="$P/.studio/reports/overnight-20261004-010000"; mkdir -p "$RD/control"
  printf '# Studio State\n\nstage: execute\nspec: -\nplan: -\ntask: 1/3\nbranch: -\nmilestone: prototype\n\n## Ledger\n\n' > "$P/.studio/STATE.md"
  units "$RD" T1 progress 10; echo "held by operator until 2026-10-04T12:00:00Z" > "$RD/control/-.held"
  live; st
  assert_contains "$TMP/st.out" "^progress: .* 1/5 units · held (no ETA)$" "a held single-plan run shows no ETA"
}
test_progress_ended_single_plan_ignores_project_task() {
  proj send; rm -rf "$RD"; RD="$P/.studio/reports/overnight-20261004-010000"; mkdir -p "$RD"
  printf '# Studio State\n\nstage: execute\nspec: -\nplan: -\ntask: 1/9\nbranch: -\nmilestone: prototype\n\n## Ledger\n\n' > "$P/.studio/STATE.md"
  units "$RD" T1 progress 10
  printf '# Overnight run\nEnding: stopped\n' > "$RD/report.md"
  st
  assert_not_contains "$TMP/st.out" "^progress:" "an ended run that did not finish shows no bar (a newer plan's task would skew it)"
}
test_progress_resume_review_not_double_counted() {
  proj resume; story A - running "2/2"; chain 1 - A; live
  printf -- '- 2026-10-03 final review done\n' >> "$P/.studio/stories/A.md"
  st
  # No units done; no task left, review done earlier, finish left: 1 + the final step.
  assert_contains "$TMP/st.out" "^progress: .* 0/2 units" "a final review done in an earlier run is not planned again"
}
test_progress_symlinked_run_not_past() {
  proj sym; story A - running "0/1"; chain 1 - A
  units "$RD/lanes/1" A-T1 progress 10
  ln -s "$P" "$TMP/symp"; live
  printf 'pid=%s\nrun=%s\nstarted=x\n' "$DUMMY" "$TMP/symp/.studio/reports/overnight-demo-1" > "$P/.studio/overnight.lock"
  st
  assert_not_contains "$TMP/st.out" "past units" "the current run, spelled through a symlink, is not a past run"
}

run_tests test_progress_fresh_no_data test_progress_mid_run_eta test_progress_past_run_median \
  test_progress_repair_adds_a_unit test_progress_chains_waits_and_held test_progress_ended_run_no_eta \
  test_progress_single_plan test_progress_retry_and_unit_kinds \
  test_progress_scale_with_past_rows test_progress_held_single_plan_no_eta \
  test_progress_ended_single_plan_ignores_project_task test_progress_resume_review_not_double_counted \
  test_progress_symlinked_run_not_past
