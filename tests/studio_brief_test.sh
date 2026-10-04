#!/bin/sh
# Suite for studios/game-dev/bin/studio-brief: it prints exactly a task or
# final-review unit's inputs, and nothing else.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

BRIEF="$REPO_ROOT/studios/game-dev/bin/studio-brief"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# build_fixture DIR — a temp git repo with spec, plan, story, ledger, manifest.
build_fixture() {
  d="$1"
  mkdir -p "$d/docs"
  git init -q "$d"
  cat > "$d/docs/spec.md" <<'SPEC'
# Spec

## Purpose
MARK-PURPOSE

## Acceptance criteria
1. First MARK-AC1
   more one
2. Second MARK-AC2
   more two
3. Third MARK-AC3
   more three
4. Fourth MARK-AC4
   more four

## Stories

| Story | Acceptance criteria | Depends on |
|-------|---------------------|------------|
| S1 | 1, 3 | - |
| S2 | 2, 4 | S1 |

## Architecture

### Data
MARK-DATA

### Flow
MARK-FLOW

## Risks
None.
SPEC
  cat > "$d/docs/plan.md" <<'PLAN'
# Plan

## Global Constraints
- constraint line

## Decisions
- decision line

## Tasks

### Task 1: one
Spec: docs/spec.md:L3-4
MARK-T1

### Task 2: two
MARK-T2

### Task 3: three
Spec: docs/spec.md:L3-4, docs/spec.md§### Data
MARK-T3

### Task 4: four
MARK-T4
PLAN
  ( cd "$d"
    sh "$STATE_BIN" init
    export STUDIO_STORY=S1
    sh "$STATE_BIN" init
    sh "$STATE_BIN" set spec docs/spec.md
    sh "$STATE_BIN" set plan docs/plan.md
    sh "$STATE_BIN" ledger "Ruling: chose X"
    sh "$STATE_BIN" ledger "Task 2: minor (deferred): rename"
    sh "$STATE_BIN" ledger "T1 complete" ) >/dev/null 2>&1
  printf '# Run\n\nTarget: integration/demo # the lane\nStories: S1\n' > "$TMP/run.md"
}

P="$TMP/proj"
build_fixture "$P"
STUDIO_RUN="$TMP/run.md"; export STUDIO_RUN

test_brief_task() {
  out="$TMP/task3.txt"
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$out"; st=$?
  assert_eq 0 "$st" "task 3 exits 0"
  assert_contains "$out" "^==> docs/plan.md:L[0-9]*-[0-9]*$" "parts are headed with file and lines"
  assert_contains "$out" "MARK-T3" "task 3's block is present"
  assert_not_contains "$out" "MARK-T2" "task 2 is absent"
  assert_not_contains "$out" "MARK-T4" "task 4 is absent"
  assert_contains "$out" "^## Global Constraints" "global constraints present"
  assert_contains "$out" "^## Decisions" "decisions present"
  assert_contains "$out" "MARK-PURPOSE" "the L-range is present"
  assert_contains "$out" "MARK-DATA" "the § range is present"
  assert_not_contains "$out" "MARK-FLOW" "the sibling subsection is absent"
  assert_not_contains "$out" "MARK-AC1" "uncited spec sections are absent"
}
test_brief_final() {
  out="$TMP/final.txt"
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$out"; st=$?
  assert_eq 0 "$st" "final exits 0"
  assert_contains "$out" "MARK-AC1" "the story's AC 1"
  assert_contains "$out" "MARK-AC3" "the story's AC 3"
  assert_not_contains "$out" "MARK-AC2" "another story's AC is absent"
  assert_contains "$out" "| S1 |" "the story's row"
  assert_contains "$out" "Ruling: chose X" "ruling lines"
  assert_contains "$out" "minor (deferred): rename" "deferred minors"
  assert_not_contains "$out" "T1 complete" "other ledger lines are absent"
  assert_contains "$out" "^diff: git diff origin/integration/demo\.\.\.HEAD$" "the diff command"
  assert_not_contains "$out" "MARK-T" "no plan text"
}
test_brief_refusals() {
  assert_status 1 "a missing task exits 1" -- sh -c "cd '$P' && STUDIO_STORY=S1 sh '$BRIEF' task 9"
  # a task whose Spec: cites a range past EOF
  sed -i.bak 's/^Spec: docs\/spec.md:L3-4, /Spec: docs\/spec.md:L3-9999, /' "$P/docs/plan.md"
  assert_status 1 "a range past the end exits 1" -- sh -c "cd '$P' && STUDIO_STORY=S1 sh '$BRIEF' task 3"
  mv "$P/docs/plan.md.bak" "$P/docs/plan.md"
  # the root STATE.md has no spec (only S1's does); set it so final reaches the Stories check
  ( cd "$P" && sh "$STATE_BIN" set spec docs/spec.md ) >/dev/null 2>&1
  assert_status 1 "final with a Stories table needs STUDIO_STORY" -- sh -c "cd '$P' && STUDIO_STORY= sh '$BRIEF' final"
  ( cd "$P" && STUDIO_STORY= sh "$BRIEF" final ) > /dev/null 2> "$TMP/nostory.err"
  assert_contains "$TMP/nostory.err" "STUDIO_STORY not set" "the refusal names STUDIO_STORY, not a missing spec"
  assert_status 2 "no verb is usage" -- sh "$BRIEF"
  assert_status 2 "an unknown verb is usage" -- sh "$BRIEF" bogus
}
test_brief_missing_sections() {
  # AC19: a plan with no Global Constraints and a task with no Spec: line.
  Q="$TMP/proj2"
  build_fixture "$Q"
  grep -v -e '^## Global Constraints' -e '^- constraint line' "$Q/docs/plan.md" > "$Q/docs/plan.new"
  mv "$Q/docs/plan.new" "$Q/docs/plan.md"
  out="$TMP/task2.txt"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" task 2 ) > "$out"; st=$?
  assert_eq 0 "$st" "task 2 with no Global Constraints and no Spec: exits 0"
  assert_contains "$out" "(plan has no ## Global Constraints)" "the missing section is noted"
  assert_contains "$out" "MARK-T2" "the task block is still present"
  assert_contains "$out" "^## Decisions" "decisions still present"
  assert_contains "$out" "(task 2 has no Spec: line)" "the missing Spec: line is noted"
}

# add_directives DIR — S1's ledger in DIR gains active, retired and
# ruling-looking directives.
add_directives() {
  ( cd "$1" && STUDIO_STORY=S1 && export STUDIO_STORY
    sh "$STATE_BIN" ledger "Directive 1: use the bus"
    sh "$STATE_BIN" ledger "Directive 2: Ruling: is not a ruling"
    sh "$STATE_BIN" ledger "Directive 3: temp"
    sh "$STATE_BIN" ledger "Directive 3 retired" ) >/dev/null 2>&1
}
test_brief_directives_task() {
  Q="$TMP/projd"; build_fixture "$Q"; add_directives "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$TMP/dt.txt"; st=$?
  assert_eq 0 "$st" "task 3 exits 0"
  assert_contains "$TMP/dt.txt" "^==> .*/\.studio/ledger/S1\.md$" "a ledger part headed by the story's ledger"
  assert_contains "$TMP/dt.txt" "^- [0-9-]* Directive 1: use the bus$" "an active directive"
  assert_contains "$TMP/dt.txt" "^- [0-9-]* Directive 2: Ruling: is not a ruling$" "another"
  assert_not_contains "$TMP/dt.txt" "Directive 3" "a retired directive and its retire line are left out"
  assert_not_contains "$TMP/dt.txt" "T1 complete" "no other ledger line"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" task 2 ) > "$TMP/dt2.txt"
  assert_contains "$TMP/dt2.txt" "Directive 1: use the bus" "a task with no Spec: line still gets them"
  assert_contains "$TMP/dt2.txt" "(task 2 has no Spec: line)" "and its note"
}
test_brief_directives_final() {
  Q="$TMP/projf"; build_fixture "$Q"; add_directives "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$TMP/df.txt"; st=$?
  assert_eq 0 "$st" "final exits 0"
  ld="$(grep -n 'Directive 1: use the bus' "$TMP/df.txt" | cut -d: -f1)"
  dd="$(grep -n '^diff: ' "$TMP/df.txt" | cut -d: -f1)"
  assert_eq 1 "$([ -n "$ld" ] && [ -n "$dd" ] && [ "$ld" -lt "$dd" ] && echo 1 || echo 0)" "the directives come before diff: (AC15)"
  assert_not_contains "$TMP/df.txt" "Directive 3" "no retired directive"
}
test_brief_directive_text_not_ruling() {
  Q="$TMP/projr"; build_fixture "$Q"; add_directives "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$TMP/dr.txt"
  awk '/^==> .*\.studio\/ledger\// { p++; next } /^==> |^diff: / { p = 0 } p == 1' "$TMP/dr.txt" > "$TMP/dr.rulings"
  assert_eq 1 "$(grep -c 'Ruling: ' "$TMP/dr.rulings")" "the rulings part holds only the real ruling"
  assert_contains "$TMP/dr.rulings" "minor (deferred): rename" "a Task-prefixed deferred minor still matches"
  assert_not_contains "$TMP/dr.rulings" "Directive" "directive text never reads as a ruling"
}
test_brief_no_directives_no_part() {
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$TMP/nd.txt"
  assert_eq 0 "$(grep -c '^==> .*\.studio/ledger/' "$TMP/nd.txt")" "no directives: no ledger part in task"
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$TMP/ndf.txt"
  assert_eq 1 "$(grep -c '^==> .*\.studio/ledger/' "$TMP/ndf.txt")" "final keeps only its rulings part"
}

run_tests test_brief_task test_brief_final test_brief_refusals test_brief_missing_sections test_brief_directives_task test_brief_directives_final test_brief_directive_text_not_ruling test_brief_no_directives_no_part
