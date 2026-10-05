#!/bin/sh
# studio_peers_test.sh (#39): studio-peers and the peer-runs SessionStart hook.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
STUDIO_DIR="$REPO_ROOT/studios/game-dev"
PEERS="$STUDIO_DIR/bin/studio-peers"
HOOK="$STUDIO_DIR/hooks/peer-runs.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'exec 2>/dev/null; kill $DUMMIES; rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
DUMMIES=""
SS_START='{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}'
RULE='These files are being changed by another live run. Do not edit them beyond what your task needs; if your task needs to, keep the change minimal and name each such file in your report.'
# live_dummy — a live pid whose args name studio-overnight (DUMMY).
live_dummy() { sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; DUMMIES="$DUMMIES $DUMMY"; }
dead_pid() { sh -c ':' & wait $!; DEAD=$!; }
# prun SLUG PID STARTED DOCS — a per-run lock, run dir (PR_DIR), manifest.
prun() {
  PR_DIR="$P/.studio/reports/overnight-$1-20261004-210000"; mkdir -p "$PR_DIR/stories" "$P/.studio/runs/$1"
  printf '# Run: %s\n\nMode: integration\nDocs: %s\n' "$1" "$4" > "$PR_DIR/manifest.md"
  printf 'pid=%s\nrun=%s\nstarted=%s\n' "$2" "$PR_DIR" "$3" > "$P/.studio/runs/$1/lock"
}
# prow DIR ID PLAN STATE TASK — a rows.tsv line, the story record and the state file.
prow() {
  printf '%s\tb-%s\t\t\t%s\t\n' "$2" "$2" "$3" >> "$1/rows.tsv"
  printf '%s\n' "$4" > "$1/stories/$2"
  printf 'task: %s\n' "$5" > "$P/.studio/stories/$2.md"
}
# peers_fixture NAME — git project P with two plans and live runs alpha, beta.
peers_fixture() {
  P="$TMP/$1"; mkdir -p "$P/docs" "$P/.studio/stories"
  git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
  printf '# Plan A\n\n### Task 1: one\n\nFiles: `a1.txt`\n\n### Task 2: two\n\nFiles: `a2.txt`, `shared.txt`\n\n### Task 3: three\n\nFiles: `a3.txt:10-20` (note)\n\n## Backlog\n\n### Task 4: later\n\nFiles: `a4.txt`\n' > "$P/docs/plan-a.md"
  printf '# Plan B\n\n### Task 1: one\n\n**Files:**\n- Create: `b1.txt`\n- Modify: `b2.txt:5-9`\n\n### Task 2: two\n\n**Files:**\n- Test: `b3.txt`\n' > "$P/docs/plan-b.md"
  git -C "$P" add docs; git -C "$P" commit -q -m docs
  DOCS="$(git -C "$P" rev-parse HEAD)"
  live_dummy; prun alpha "$DUMMY" 2026-10-04T21:00:01Z "$DOCS"; A_DIR="$PR_DIR"
  prow "$A_DIR" S1 docs/plan-a.md running 1/3; prow "$A_DIR" S2 docs/plan-a.md landed 3/3
  live_dummy; prun beta "$DUMMY" 2026-10-04T21:00:05Z "$DOCS"; B_DIR="$PR_DIR"
  prow "$B_DIR" S3 docs/plan-b.md running 0/2
}

test_peers_default_two_runs() {
  peers_fixture t1; cd "$P"
  assert_eq "beta integration: S3 task 0/2" "$(sh "$PEERS" --exclude "$A_DIR")" "the other run only, landed stories left out"
  assert_eq "alpha integration: S1 task 1/3
beta integration: S3 task 0/2" "$(sh "$PEERS")" "both runs without --exclude"
}
test_peers_files_both_forms() {
  peers_fixture t2; cd "$P"
  assert_eq "alpha a2.txt
alpha a3.txt
alpha shared.txt
beta b1.txt
beta b2.txt
beta b3.txt" "$(sh "$PEERS" --files)" "tasks k+1..N, both Files forms, sorted, :lines stripped, Backlog excluded"
}
test_peers_unreadable_run() {
  peers_fixture t3; cd "$P"; rm "$B_DIR/rows.tsv"
  assert_eq "alpha integration: S1 task 1/3
beta: unreadable" "$(sh "$PEERS")" "no rows.tsv: unreadable"
  assert_eq "alpha a2.txt
alpha a3.txt
alpha shared.txt
beta: unreadable" "$(sh "$PEERS" --files)" "unreadable in the files form"
  peers_fixture t3b; cd "$P"; printf '# Run: beta\n\nMode: integration\nDocs: deadbeef\n' > "$B_DIR/manifest.md"
  assert_eq "alpha a2.txt
alpha a3.txt
alpha shared.txt
beta: unreadable" "$(sh "$PEERS" --files)" "a plan missing at Docs: is unreadable"
  sh "$PEERS" --files >/dev/null 2>&1; assert_eq 0 "$?" "exit 0"
}
test_peers_ignores_single_and_dead() {
  P="$TMP/t4"; mkdir -p "$P/.studio/stories" "$P/.studio/reports/overnight-20261004-210000"; git -C "$P" init -q -b main; cd "$P"
  live_dummy; printf 'pid=%s\nrun=%s\nstarted=2026-10-04T22:00:00Z\n' "$DUMMY" "$P/.studio/reports/overnight-20261004-210000" > "$P/.studio/overnight.lock"
  dead_pid; prun gone "$DEAD" 2026-10-04T21:00:00Z deadbeef
  assert_eq "" "$(sh "$PEERS")" "a single-plan lock and a dead lock print nothing"
}
# A live lock with no start= (and no started=) line: runs_live's empty columns
# must not shift the fields studio-peers reads (#39 final review, known #2).
test_peers_lock_without_start() {
  peers_fixture t8; cd "$P"
  printf 'pid=%s\nrun=%s\n' "$(sed -n 's/^pid=//p' "$P/.studio/runs/beta/lock")" "$B_DIR" > "$P/.studio/runs/beta/lock"
  assert_eq "beta integration: S3 task 0/2" "$(sh "$PEERS" --exclude "$A_DIR")" "a lock without start= or started= is still a peer"
  assert_eq "alpha integration: S1 task 1/3" "$(sh "$PEERS" --exclude "$B_DIR")" "and --exclude still matches its run dir"
}
test_peer_hook_block() {
  peers_fixture t5; cd "$P"
  out="$(printf '%s' "$SS_START" | STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR="$A_DIR" sh "$HOOK")"
  printf '%s\n' "$out" > "$TMP/o5"
  assert_contains "$TMP/o5" '^Other live runs$' "the heading"
  assert_contains "$TMP/o5" 'beta integration: S3 task 0/2' "the peer run"
  assert_contains "$TMP/o5" '^  beta b1.txt$' "indented peer paths"
  assert_not_contains "$TMP/o5" 'alpha' "the own run is excluded"
  assert_eq 1 "$(grep -cxF -- "$RULE" "$TMP/o5")" "the rule line, verbatim"
  # 45 paths: 40 then 'and 5 more'
  { printf '# Plan C\n\n### Task 1: big\n\nFiles: '; i=1; while [ $i -le 45 ]; do printf '`f%02d.txt`, ' $i; i=$((i + 1)); done; printf '\n'; } > "$P/docs/plan-c.md"
  git -C "$P" add docs; git -C "$P" commit -q -m c
  printf '# Run: beta\n\nMode: integration\nDocs: %s\n' "$(git -C "$P" rev-parse HEAD)" > "$B_DIR/manifest.md"
  printf 'S3\tb-S3\t\t\tdocs/plan-c.md\t\n' > "$B_DIR/rows.tsv"
  out="$(printf '%s' "$SS_START" | STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR="$A_DIR" sh "$HOOK")"
  assert_eq 40 "$(printf '%s\n' "$out" | grep -c '^  beta f')" "40 paths printed"
  assert_eq "  and 5 more" "$(printf '%s\n' "$out" | grep '^  and ')" "and 5 more"
}
test_peer_hook_silent() {
  peers_fixture t6; cd "$P"
  rm "$P/.studio/runs/alpha/lock"
  assert_eq "" "$(printf '%s' "$SS_START" | STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR="$B_DIR" sh "$HOOK")" "no other live run"
  assert_eq "" "$(printf '%s' "$SS_START" | STUDIO_RUN_DIR="$A_DIR" sh "$HOOK")" "no STUDIO_UNIT_TAG"
  mkdir -p "$TMP/single"
  assert_eq "" "$(printf '%s' "$SS_START" | STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR="$TMP/single" sh "$HOOK")" "no rows.tsv (single-plan unit)"
}
test_peer_hook_exit0_bad_input() {
  peers_fixture t7; cd "$P"
  printf '%s' "$SS_START" | STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR="$TMP/nonexistent" sh "$HOOK" >/dev/null 2>&1; assert_eq 0 "$?" "missing run dir"
  printf 'garbage\377' | STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR="$A_DIR" sh "$HOOK" >/dev/null 2>&1; assert_eq 0 "$?" "garbage stdin"
  cp -R "$STUDIO_DIR" "$TMP/plugin"; chmod -x "$TMP/plugin/bin/studio-peers"
  printf '%s' "$SS_START" | STUDIO_UNIT_TAG=u1 STUDIO_RUN_DIR="$A_DIR" "$TMP/plugin/hooks/peer-runs.sh" >/dev/null 2>&1; assert_eq 0 "$?" "studio-peers not executable"
}

run_tests test_peers_default_two_runs test_peers_files_both_forms test_peers_unreadable_run \
  test_peers_ignores_single_and_dead test_peers_lock_without_start test_peer_hook_block test_peer_hook_silent test_peer_hook_exit0_bad_input
