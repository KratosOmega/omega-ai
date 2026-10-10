#!/bin/sh
# Suite for studios/game-dev/bin/studio-brief: it prints exactly a task or
# final-review unit's inputs, and nothing else.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

BRIEF="$REPO_ROOT/studios/game-dev/bin/studio-brief"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
mk_tmp studio_brief_test
trap 'rm_tmp "$TMP"' EXIT

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
test_brief_directive_edge_cases() {
  Q="$TMP/proje"; build_fixture "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 && export STUDIO_STORY
    sh "$STATE_BIN" ledger "Directive 1: use the bus"
    sh "$STATE_BIN" ledger "Directive 10: ten"
    sh "$STATE_BIN" ledger "Directive 10 retired"
    sh "$STATE_BIN" ledger "Directive 5 retired"
    sh "$STATE_BIN" ledger "Directive 5: after its retire line" ) >/dev/null 2>&1
  printf 'Directive 8: bare line with no date prefix\n' >> "$Q/.studio/ledger/S1.md"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$TMP/de.txt"
  assert_contains "$TMP/de.txt" "Directive 1: use the bus" "retiring id 10 leaves id 1 active (no prefix match)"
  assert_not_contains "$TMP/de.txt" "Directive 10" "id 10 is retired, its line and its retire line left out"
  assert_contains "$TMP/de.txt" "Directive 5: after its retire line" "a retire line before the directive does not retire it"
  assert_not_contains "$TMP/de.txt" "Directive 8" "a line without the '- <date> ' prefix is not a directive"
  # no STUDIO_STORY: the ledger is the spec slug's (a dated spec name, its date stripped)
  Q2="$TMP/projs"; build_fixture "$Q2"
  cp "$Q2/docs/spec.md" "$Q2/docs/2026-10-03-demo.md"
  ( cd "$Q2" && unset STUDIO_STORY && sh "$STATE_BIN" set spec docs/2026-10-03-demo.md && sh "$STATE_BIN" set plan docs/plan.md \
    && sh "$STATE_BIN" ledger "Directive 1: slug path" ) >/dev/null 2>&1
  ( cd "$Q2" && unset STUDIO_STORY && sh "$BRIEF" task 3 ) > "$TMP/dslug.txt"
  assert_contains "$TMP/dslug.txt" "^==> .*/\.studio/ledger/demo\.md$" "no STUDIO_STORY: the part is headed by the dated spec name's slug ledger"
  assert_contains "$TMP/dslug.txt" "Directive 1: slug path" "and carries the directive"
}
test_brief_no_directives_no_part() {
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$TMP/nd.txt"
  assert_eq 0 "$(grep -c '^==> .*\.studio/ledger/' "$TMP/nd.txt")" "no directives: no ledger part in task"
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$TMP/ndf.txt"
  assert_eq 1 "$(grep -c '^==> .*\.studio/ledger/' "$TMP/ndf.txt")" "final keeps only its rulings part"
}


# ctx_fixture DIR — a fixture whose plan carries a Context: header.
ctx_fixture() {
  build_fixture "$1"
  sed -i.bak 's|^# Plan$|# Plan\
Context: docs/c1.md, docs/c2.md|' "$1/docs/plan.md"; rm -f "$1/docs/plan.md.bak"
  printf 'MARK-C1\n' > "$1/docs/c1.md"; printf 'MARK-C2\n' > "$1/docs/c2.md"
}
# commit_fixture DIR — commits c0..c2 in DIR; sets S0 S1 S2 to their shas.
commit_fixture() {
  Q="$1"
  ( cd "$Q" && git add -A && git -c user.email=t@t -c user.name=t commit -qm c0 \
    && for i in 1 2; do echo "x$i" > "docs/x$i.txt"; git add -A; git -c user.email=t@t -c user.name=t commit -qm "c$i"; done ) >/dev/null 2>&1
  S0="$(cd "$Q" && git rev-parse HEAD~2)"; S1="$(cd "$Q" && git rev-parse HEAD~1)"; S2="$(cd "$Q" && git rev-parse HEAD)"
}
brief_in() { _d="$1"; shift; ( cd "$_d" && STUDIO_STORY=S1 sh "$BRIEF" "$@" ); }
ledger_in() { _d="$1"; shift; ( cd "$_d" && STUDIO_STORY=S1 sh "$STATE_BIN" ledger "$*" ) >/dev/null 2>&1; }

test_brief_context_appended() {
  Q="$TMP/projc"; ctx_fixture "$Q"; commit_fixture "$Q"
  ledger_in "$Q" "adopt-base $S0"; ledger_in "$Q" "T1 complete $S0..$S1"
  for v in "task 1" final "check 1"; do
    # shellcheck disable=SC2086
    brief_in "$Q" $v > "$TMP/ctx.out"; st=$?
    assert_eq 0 "$st" "$v exits 0"
    assert_contains "$TMP/ctx.out" "^## Context files$" "$v: the Context files part"
    assert_contains "$TMP/ctx.out" "^==> docs/c1.md:L1-1$" "$v: c1 headed"
    assert_contains "$TMP/ctx.out" "MARK-C1" "$v: c1 text"
    assert_contains "$TMP/ctx.out" "MARK-C2" "$v: c2 text"
  done
  brief_in "$Q" final > "$TMP/ctx.out"
  assert_eq 1 "$(tail -n 1 "$TMP/ctx.out" | grep -c '^diff: ')" "final: the last line is still diff:"
  brief_in "$Q" check 1 > "$TMP/ctx.out"
  assert_eq 1 "$(tail -n 1 "$TMP/ctx.out" | grep -c '^diff: ')" "check: the last line is still diff:"
}
test_brief_context_cap() {
  Q="$TMP/projcap"; ctx_fixture "$Q"
  awk 'BEGIN{for(i=0;i<110;i++) printf "%0100d\n", i}' > "$Q/docs/c1.md"
  awk 'BEGIN{for(i=0;i<20;i++) printf "%099d\n", i}' > "$Q/docs/c2.md"
  brief_in "$Q" task 1 > "$TMP/cap.out"; st=$?
  assert_eq 0 "$st" "task 1 exits 0"
  assert_contains "$TMP/cap.out" "^==> docs/c1.md:L1-110$" "c1 is included"
  assert_not_contains "$TMP/cap.out" "^==> docs/c2.md" "c2 is over the cap"
  assert_contains "$TMP/cap.out" "^Read these as well:$" "the overflow heading"
  assert_contains "$TMP/cap.out" "^- docs/c2.md$" "c2 is listed"
}
test_brief_context_missing_file() {
  Q="$TMP/projcm"; ctx_fixture "$Q"
  sed -i.bak 's|^Context: .*|Context: docs/nope.md|' "$Q/docs/plan.md"; rm -f "$Q/docs/plan.md.bak"
  brief_in "$Q" task 1 > /dev/null 2> "$TMP/cm.err"; st=$?
  assert_eq 1 "$st" "a missing Context file exits 1"
  assert_contains "$TMP/cm.err" "Context file docs/nope.md not found" "names the file"
}
test_brief_context_no_glob() {
  Q="$TMP/projcg"; ctx_fixture "$Q"
  sed -i.bak 's|^Context: .*|Context: docs/c*.md|' "$Q/docs/plan.md"; rm -f "$Q/docs/plan.md.bak"
  brief_in "$Q" task 1 > /dev/null 2> "$TMP/cg.err"; st=$?
  assert_eq 1 "$st" "a * in a Context path is a name, not a glob"
  assert_contains "$TMP/cg.err" "Context file docs/c[*].md not found" "names the literal path"
}
test_brief_final_plan_acceptance() {
  Q="$TMP/projpa"; build_fixture "$Q"
  printf '# Spec\n\n## Purpose\nx\n' > "$Q/docs/spec.md"
  printf '\n## Acceptance criteria\n1. MARK-PLAN-AC\n' >> "$Q/docs/plan.md"
  brief_in "$Q" final > "$TMP/pa.out"; st=$?
  assert_eq 0 "$st" "final falls back to the plan's acceptance criteria"
  assert_contains "$TMP/pa.out" "^==> docs/plan.md:L" "headed by the plan"
  assert_contains "$TMP/pa.out" "MARK-PLAN-AC" "the plan's criterion"
  Q2="$TMP/projpb"; build_fixture "$Q2"
  printf '# Spec\n\n## Purpose\nx\n' > "$Q2/docs/spec.md"
  brief_in "$Q2" final > /dev/null 2> "$TMP/pb.err"; st=$?
  assert_eq 1 "$st" "neither file has the section"
  assert_contains "$TMP/pb.err" "## Acceptance criteria not found in" "today's failure text"
}
test_brief_check_verb() {
  Q="$TMP/projk"; build_fixture "$Q"; commit_fixture "$Q"
  ledger_in "$Q" "T1 complete $S0..$S1"
  brief_in "$Q" check 1 > /dev/null 2> "$TMP/k.err"; st=$?
  assert_eq 1 "$st" "no adopt-base exits 1"
  assert_contains "$TMP/k.err" "adopt-base" "names adopt-base"
  ledger_in "$Q" "adopt-base $S0"; ledger_in "$Q" "T2 complete $S1..$S2"
  brief_in "$Q" check 2 > "$TMP/k2.out"; st=$?
  assert_eq 0 "$st" "check 2 exits 0"
  assert_contains "$TMP/k2.out" "^### Task 1:" "task 1 block"
  assert_contains "$TMP/k2.out" "^### Task 2:" "task 2 block"
  assert_not_contains "$TMP/k2.out" "^### Task 3:" "task 3 block absent"
  assert_not_contains "$TMP/k2.out" "MARK-DATA" "task 3's spec part absent"
  assert_contains "$TMP/k2.out" "MARK-PURPOSE" "task 1's spec part present"
  assert_contains "$TMP/k2.out" "^range: $S0\.\.$S2$" "range"
  assert_contains "$TMP/k2.out" "^diff: git diff $S0\.\.$S2$" "diff"
  assert_contains "$TMP/k2.out" "^## Global Constraints" "GC part"
  assert_contains "$TMP/k2.out" "^## Decisions" "Decisions part"
  brief_in "$Q" check 0 > "$TMP/k0.out"; st=$?
  assert_eq 0 "$st" "check 0 exits 0"
  assert_contains "$TMP/k0.out" "^range: none — no finished task$" "check 0 range"
  assert_not_contains "$TMP/k0.out" "^### Task" "check 0 has no task blocks"
  brief_in "$Q" check 3 > /dev/null 2> "$TMP/k3.err"; st=$?
  assert_eq 1 "$st" "check 3 exits 1"
  assert_contains "$TMP/k3.err" "T3 complete" "names T3 complete"
}
test_brief_check_uses_truth_region() {
  Q="$TMP/projkt"; build_fixture "$Q"; commit_fixture "$Q"
  ledger_in "$Q" "adopt-base $S0"; ledger_in "$Q" "T1 complete $S0..$S1"
  ledger_in "$Q" "adopt reset $S2"
  ledger_in "$Q" "adopt-base $S1"; ledger_in "$Q" "T1 complete $S1..$S2"
  brief_in "$Q" check 1 > "$TMP/kt.out"; st=$?
  assert_eq 0 "$st" "check 1 exits 0"
  assert_contains "$TMP/kt.out" "^range: $S1\.\.$S2$" "the range comes after the last reset"
}
test_brief_final_reads_check_rulings() {
  Q="$TMP/projkr"; build_fixture "$Q"
  ledger_in "$Q" "check Ruling: kept X — fine — low"
  ledger_in "$Q" "minor (deferred) T2: y (standard mode)"
  brief_in "$Q" final > "$TMP/kr.out"
  assert_contains "$TMP/kr.out" "check Ruling: kept X — fine — low" "the check ruling"
  assert_contains "$TMP/kr.out" "minor (deferred) T2: y (standard mode)" "the deferred minor"
}
test_brief_original_plan_item() {
  Q="$TMP/projop"; build_fixture "$Q"
  printf '# Orig\n\n### Task 1: o\nMARK-ORIG\nmore\n\n### Task 2: p\n' > "$Q/docs/orig.md"
  sed -i.bak 's|^Spec: docs/spec.md:L3-4$|Spec: docs/orig.md:L3-5|' "$Q/docs/plan.md"; rm -f "$Q/docs/plan.md.bak"
  brief_in "$Q" task 1 > "$TMP/op.out"; st=$?
  assert_eq 0 "$st" "task 1 exits 0"
  assert_contains "$TMP/op.out" "^==> docs/orig.md:L3-5$" "the original plan's lines"
  assert_contains "$TMP/op.out" "MARK-ORIG" "its text"
}
test_brief_usage_names_check() {
  sh "$BRIEF" bogus > /dev/null 2> "$TMP/u.err"; st=$?
  assert_eq 2 "$st" "usage exits 2"
  assert_contains "$TMP/u.err" "check <k>" "usage names check"
  assert_contains "$TMP/u.err" "validate <plan>" "usage names validate"
  assert_contains "$TMP/u.err" "| rewrite" "usage names rewrite"
}
# AC9 + Review Focus 5: an L<a> item is one line.
test_brief_single_line_item() {
  Q="$TMP/projl"; build_fixture "$Q"
  sed -i.bak 's#^Spec: docs/spec.md:L3-4$#Spec: docs/spec.md:L3#' "$Q/docs/plan.md"; rm -f "$Q/docs/plan.md.bak"
  ( cd "$Q" && sh "$STATE_BIN" init && sh "$STATE_BIN" set plan docs/plan.md ) >/dev/null 2>&1
  brief_in "$Q" task 1 > "$TMP/l.out"; st=$?
  assert_eq 0 "$st" "task accepts <spec>:L3"
  assert_contains "$TMP/l.out" '^==> docs/spec.md:L3-3$' "read as L3-3"
  assert_eq "$(sed -n 3p "$Q/docs/spec.md")" "$(sed -n '/^==> docs\/spec.md:L3-3$/{n;p;}' "$TMP/l.out")" "emits line 3"
}
test_brief_validate_good_plan() {
  Q="$TMP/projv"; build_fixture "$Q"
  # Tasks 2 and 4 have no Spec: line in the fixture — give them one.
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/v.out" 2> "$TMP/v.err"; st=$?
  assert_eq 0 "$st" "a good plan passes"
  assert_contains "$TMP/v.out" '^studio-brief: 4 tasks, 5 Spec items ok$' "counts tasks and items"
}
# AC9: every problem in one run.
test_brief_validate_reports_all() {
  Q="$TMP/projbad"; mkdir -p "$Q/docs"; printf 'l1\nl2\n# H\nl4\n' > "$Q/docs/s.md"
  cat > "$Q/docs/plan.md" <<'PLAN'
# Plan
### Task 1: a
Spec: docs/s.md L2
### Task 2: b
Spec: docs/s.md:L5-3
### Task 3: c
Spec: docs/none.md:L1
### Task 4: d
Spec: docs/s.md:L3-9
### Task 5: e
Spec: docs/s.md§# Missing
### Task 6: f
no spec here
### Task 7: g
Spec: docs/s.md:L144, docs/s.md:L1-2, docs/s.md§# H
PLAN
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/b.out" 2> "$TMP/b.err"; st=$?
  assert_eq 1 "$st" "exit 1"
  assert_contains "$TMP/b.err" "^studio-brief: task 1: cannot parse Spec: item 'docs/s.md L2'$" "unparseable"
  assert_contains "$TMP/b.err" "^studio-brief: task 2: bad range in Spec: item 'docs/s.md:L5-3'$" "a > b"
  assert_contains "$TMP/b.err" "^studio-brief: task 3: spec docs/none.md not found" "missing file"
  assert_contains "$TMP/b.err" "^studio-brief: task 4: range .* is past the end of docs/s.md (4 lines)$" "past EOF"
  assert_contains "$TMP/b.err" "^studio-brief: task 5: heading '# Missing' not found in docs/s.md$" "missing heading"
  assert_contains "$TMP/b.err" "^studio-brief: task 6: no Spec: line$" "no Spec: line"
  assert_contains "$TMP/b.err" "^studio-brief: task 7: range .*L144.* is past the end" "the phoenix L144 item parses, then fails only on range"
  assert_eq 7 "$(grep -c '^studio-brief: task ' "$TMP/b.err")" "one line per problem, nothing for good items"
  assert_eq "" "$(cat "$TMP/b.out")" "no ok line"
}
# Final review m10: a second `### Task 3:` block is never checked (and
# `task 3` can never reach it), so validate names the duplicate.
test_brief_validate_duplicate_task() {
  Q="$TMP/projdup"; mkdir -p "$Q/docs"; printf 'l1\nl2\n' > "$Q/docs/s.md"
  cat > "$Q/docs/plan.md" <<'PLAN'
# Plan
### Task 1: a
Spec: docs/s.md:L1
### Task 3: b
Spec: docs/s.md:L2
### Task 3: c
Spec: docs/none.md:L1
PLAN
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/d.out" 2> "$TMP/d.err"; st=$?
  assert_eq 1 "$st" "exit 1"
  assert_contains "$TMP/d.err" '^studio-brief: task 3: duplicate ### Task heading$' "names the duplicate"
  assert_eq 1 "$(grep -c '^studio-brief: task 3: duplicate' "$TMP/d.err")" "once"
  assert_eq "" "$(cat "$TMP/d.out")" "no ok line"
}
test_brief_validate_missing_plan_and_no_state() {
  Q="$TMP/projns"; mkdir -p "$Q"
  ( cd "$Q" && sh "$BRIEF" validate nope.md ) > /dev/null 2> "$TMP/n.err"; st=$?
  assert_eq 2 "$st" "a missing plan exits 2"
  assert_contains "$TMP/n.err" "plan nope.md not found" "names it"
  Q="$TMP/projns2"; build_fixture "$Q"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > /dev/null 2>&1; st=$?
  assert_eq 1 "$st" "no studio state needed (the fixture plan's tasks 2 and 4 lack Spec:)"
}
# D12: the plan path is the caller's; Spec paths are the work root's.
test_brief_validate_relative_to_caller() {
  Q="$TMP/projrel"; build_fixture "$Q"
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  ( cd "$Q/docs" && sh "$BRIEF" validate plan.md ) > /dev/null 2>&1; st=$?
  assert_eq 0 "$st" "from docs/: plan.md is found, docs/spec.md resolves from the root"
}

DET="$REPO_ROOT/studios/game-dev/bin/godot-cmd.awk"
# godot_md FILE [OUT] — the detector's md output (rows, or OUT) for FILE.
godot_md() { LC_ALL=C awk -v mode=md ${2:+-v out=$2} -f "$DET" "$1"; }
# #66 AC3: a fenced block, a bullet's inline span, a prose line with two spans; prose ignored.
test_godot_cmd_md_finds_bare_forms() {
  cat > "$TMP/ac3.md" <<'MD'
# Plan
Prose Godot --headless --script res://p.gd is not a command.
```sh
Godot --headless --path . --script res://tools/importer.gd 2>&1 | tail -5
studio-gate godot -- Godot --headless --import .
```
- [ ] **Step 3:** `Godot --headless --path . --script res://a.gd` then check.
Run `Godot --headless --import .` and then `Godot --headless --path . --script res://b.gd`; done.
MD
  printf '%s\t%s\t%s\n' \
    4 c 'Godot --headless --path . --script res://tools/importer.gd 2>&1' \
    7 c 'Godot --headless --path . --script res://a.gd' \
    8 c 'Godot --headless --import .' \
    8 c 'Godot --headless --path . --script res://b.gd' > "$TMP/ac3.want"
  godot_md "$TMP/ac3.md" > "$TMP/ac3.got"; st=$?
  assert_eq 0 "$st" "md mode exits 0"
  assert_eq "$(cat "$TMP/ac3.want")" "$(cat "$TMP/ac3.got")" "rows: line, verdict c, segment; prose and the gated line ignored"
}
# #66 Review Focus 3: span and fence edges, rows and rewrite.
test_godot_cmd_md_span_edges() {
  cat > "$TMP/edge.md" <<'MD'
Double ``Godot --script `x` y`` here.
Unclosed `Godot --script z
   ~~~
   godot --import
   ~~~
Already `studio-gate godot -- Godot --script res://c.gd` here.
`Godot --version` and `Godot --path . -- -s` and `cd x && Godot -s y.gd`
```
`Godot --script in-a-fence-is-shell-text.gd`
```
MD
  printf '%s\t%s\t%s\n' 1 c 'Godot --script `x` y' 4 c 'godot --import' 7 c 'Godot -s y.gd' > "$TMP/edge.want"
  godot_md "$TMP/edge.md" > "$TMP/edge.got"
  assert_eq "$(cat "$TMP/edge.want")" "$(cat "$TMP/edge.got")" "double-backtick span, indented ~~~ fence, && in a span; unclosed, gated, --version, -- args and fenced backticks ignored"
  cat > "$TMP/edge.rw.want" <<'MD'
Double ``studio-gate godot -- Godot --script `x` y`` here.
Unclosed `Godot --script z
   ~~~
   studio-gate godot -- godot --import
   ~~~
Already `studio-gate godot -- Godot --script res://c.gd` here.
`Godot --version` and `Godot --path . -- -s` and `cd x && studio-gate godot -- Godot -s y.gd`
```
`Godot --script in-a-fence-is-shell-text.gd`
```
MD
  godot_md "$TMP/edge.md" rewrite > "$TMP/edge.rw.got"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/edge.rw.want" "$TMP/edge.rw.got"; then _pass "rewrite inserts the gate at each c segment, every other byte the same"
  else _fail "rewrite inserts the gate at each c segment ($(diff "$TMP/edge.rw.want" "$TMP/edge.rw.got" | head -n 4))"; fi
  printf 'x `Godot --script a`' > "$TMP/nonl.md"
  LC_ALL=C awk -v mode=md -v out=rewrite -v nonl=1 -f "$DET" "$TMP/nonl.md" > "$TMP/nonl.out"
  assert_eq 'x `studio-gate godot -- Godot --script a`' "$(cat "$TMP/nonl.out")" "nonl: rewritten"
  assert_eq "$(printf 'x `studio-gate godot -- Godot --script a`' | wc -c | tr -d ' ')" "$(wc -c < "$TMP/nonl.out" | tr -d ' ')" "nonl=1: no newline added"
}
# #66 I2: multi-line forms and CommonMark fences — a \-continued fenced
# command, a span wrapped across lines (also when the Godot word is on its
# second line), a blank line ending a paragraph, a ~~~ fence holding ``` lines,
# a ```` fence holding a ``` line, a ``` line with a backtick in its info
# string (a span, not a fence), and an unclosed fence running to EOF.
test_godot_cmd_md_multiline() {
  cat > "$TMP/ml.md" <<'MD'
Intro text.
```sh
Godot --headless --path . \
  --script res://y.gd
cd x && \
  Godot --import .
```
Intro `Godot --headless --path .
  --script res://x.gd` wrapped, and `ls
-la` too. Run `cd x &&
  Godot -s w.gd` now.

- item `Godot --script q

- next `Godot --path . -s r.gd`
~~~md
```sh
Godot --import .
~~~
Godot --script later.gd in plain prose.
````
```
Godot -s inner.gd
````
Then `Godot -s tail.gd`.
``` Godot -s inline.gd ```
```
Godot --import eof
MD
  printf '%s\t%s\t%s\n' \
    3 c 'Godot --headless --path . --script res://y.gd' \
    6 c 'Godot --import .' \
    8 c 'Godot --headless --path . --script res://x.gd' \
    11 c 'Godot -s w.gd' \
    15 c 'Godot --path . -s r.gd' \
    18 c 'Godot --import .' \
    23 c 'Godot -s inner.gd' \
    25 c 'Godot -s tail.gd' \
    26 c 'Godot -s inline.gd' \
    28 c 'Godot --import eof' > "$TMP/ml.want"
  godot_md "$TMP/ml.md" > "$TMP/ml.got"; st=$?
  assert_eq 0 "$st" "md mode exits 0 on multi-line forms"
  assert_eq "$(cat "$TMP/ml.want")" "$(cat "$TMP/ml.got")" "rows: continued and wrapped commands are one command at their first line; fences close only on their own kind and length; prose after mixed fences ignored"
  cat > "$TMP/ml.rw.want" <<'MD'
Intro text.
```sh
studio-gate godot -- Godot --headless --path . \
  --script res://y.gd
cd x && \
  studio-gate godot -- Godot --import .
```
Intro `studio-gate godot -- Godot --headless --path .
  --script res://x.gd` wrapped, and `ls
-la` too. Run `cd x &&
  studio-gate godot -- Godot -s w.gd` now.

- item `Godot --script q

- next `studio-gate godot -- Godot --path . -s r.gd`
~~~md
```sh
studio-gate godot -- Godot --import .
~~~
Godot --script later.gd in plain prose.
````
```
studio-gate godot -- Godot -s inner.gd
````
Then `studio-gate godot -- Godot -s tail.gd`.
``` studio-gate godot -- Godot -s inline.gd ```
```
studio-gate godot -- Godot --import eof
MD
  godot_md "$TMP/ml.md" rewrite > "$TMP/ml.rw.got"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/ml.rw.want" "$TMP/ml.rw.got"; then _pass "rewrite: the gate lands at each segment's own line and column"
  else _fail "rewrite: the gate lands at each segment's own line and column ($(diff "$TMP/ml.rw.want" "$TMP/ml.rw.got" | head -n 6 | tr '\n' '|'))"; fi
}
# godot_fixture DIR — ctx_fixture plus bare Godot forms: a Task 1 step, the
# spec's Purpose line (in Task 1's L3-4) and AC 1 (S1's final), and Context c1.
godot_fixture() {
  ctx_fixture "$1"
  awk '{ print } /^MARK-T1$/ { print "- [ ] **Step 3:** `Godot --headless --path . --script res://tools/importer.gd` then check." }' "$1/docs/plan.md" > "$TMP/gp" && mv "$TMP/gp" "$1/docs/plan.md"
  sed -i.bak -e 's/^MARK-PURPOSE$/MARK-PURPOSE run `Godot --headless --import .` first/' \
             -e 's|^1\. First MARK-AC1$|1. First MARK-AC1 via `Godot --headless --path . --script res://ac.gd`|' "$1/docs/spec.md"
  rm -f "$1/docs/spec.md.bak"
  printf 'MARK-C1 `Godot --headless --import .`\n' > "$1/docs/c1.md"
}
# #66 AC4 + Review Focus 3: rewrite wraps only the c forms; every other byte is the same.
test_brief_rewrite_wraps_only() {
  cat "$TMP/ac3.md" "$TMP/edge.md" > "$TMP/rw.in"
  { sed -e 's/^Godot --headless --path \. --script res:\/\/tools/studio-gate godot -- &/' \
        -e 's/`Godot --headless --path \. --script res:\/\/a\.gd`/`studio-gate godot -- Godot --headless --path . --script res:\/\/a.gd`/' \
        -e 's/^Run `Godot --headless --import \.` and then `Godot/Run `studio-gate godot -- Godot --headless --import .` and then `studio-gate godot -- Godot/' "$TMP/ac3.md"
    cat "$TMP/edge.rw.want"; } > "$TMP/rw.want"
  sh "$BRIEF" rewrite < "$TMP/rw.in" > "$TMP/rw.out" 2> "$TMP/rw.err"; st=$?
  assert_eq 0 "$st" "rewrite exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rw.want" "$TMP/rw.out"; then _pass "rewrite: each c form gated, nothing else changed"
  else _fail "rewrite: each c form gated ($(diff "$TMP/rw.want" "$TMP/rw.out" | head -n 4))"; fi
  assert_eq "" "$(cat "$TMP/rw.err")" "nothing on stderr"
  printf 'a\tb\r\n- `ls -la` \303\251\n\n```\nGodot --version\n```\n' > "$TMP/rw0.in"
  sh "$BRIEF" rewrite < "$TMP/rw0.in" > "$TMP/rw0.out"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rw0.in" "$TMP/rw0.out"; then _pass "no c form: byte-identical (tab, CR, UTF-8, fences)"; else _fail "no c form: byte-identical"; fi
  printf 'x `Godot --script a`' | sh "$BRIEF" rewrite > "$TMP/rw1.out"
  assert_eq "$(printf 'x `studio-gate godot -- Godot --script a`' | wc -c | tr -d ' ')" "$(wc -c < "$TMP/rw1.out" | tr -d ' ')" "no final newline in, none out"
  : | sh "$BRIEF" rewrite > "$TMP/rw2.out"
  assert_eq 0 "$(wc -c < "$TMP/rw2.out" | tr -d ' ')" "empty in, empty out"
}
# #66 AC4: task, check and final output is rewritten; Context files are not.
test_brief_task_check_final_rewritten() {
  Q="$TMP/projg"; godot_fixture "$Q"; commit_fixture "$Q"
  ledger_in "$Q" "adopt-base $S0"; ledger_in "$Q" "T1 complete $S0..$S1"
  for v in "task 1" "check 1"; do
    # shellcheck disable=SC2086
    brief_in "$Q" $v > "$TMP/g.out" 2> "$TMP/g.err"; st=$?
    assert_eq 0 "$st" "$v exits 0"
    assert_contains "$TMP/g.out" 'Step 3:\*\* `studio-gate godot -- Godot --headless --path \. --script res://tools/importer\.gd` then check\.$' "$v: the plan step is gated"
    assert_contains "$TMP/g.out" '^MARK-PURPOSE run `studio-gate godot -- Godot --headless --import \.` first$' "$v: the cited spec range is gated"
    assert_contains "$TMP/g.out" '^MARK-C1 `Godot --headless --import \.`$' "$v: a Context file is printed as is"
    assert_contains "$TMP/g.out" '^==> docs/plan\.md:L[0-9]*-[0-9]*$' "$v: part headers unchanged"
    assert_eq "" "$(cat "$TMP/g.err")" "$v: no warning"
  done
  brief_in "$Q" final > "$TMP/gf.out"; st=$?
  assert_eq 0 "$st" "final exits 0"
  assert_contains "$TMP/gf.out" '^1\. First MARK-AC1 via `studio-gate godot -- Godot --headless --path \. --script res://ac\.gd`$' "final: the AC text is gated"
}
# #66 AC4: validate names the line and the wrapped form; the gated form passes.
test_brief_validate_godot_form() {
  Q="$TMP/projvg"; build_fixture "$Q"
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  printf -- '- [ ] **Step 2:** `Godot --headless --path . --script res://x.gd 2>&1 | tail -5` then commit.\n' >> "$Q/docs/plan.md"
  _ln="$(grep -c '' "$Q/docs/plan.md")"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/vg.out" 2> "$TMP/vg.err"; st=$?
  assert_eq 1 "$st" "a bare Godot script run fails validate"
  assert_contains "$TMP/vg.err" "^studio-brief: line $_ln: unwrapped Godot script/import run; write it as: studio-gate godot -- Godot --headless --path \. --script res://x\.gd 2>&1\$" "names the line and the wrapped form"
  assert_eq "" "$(cat "$TMP/vg.out")" "no ok line"
  sed -i.bak 's/`Godot --headless/`studio-gate godot -- Godot --headless/' "$Q/docs/plan.md"; rm -f "$Q/docs/plan.md.bak"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/vg.out" 2> "$TMP/vg.err"; st=$?
  assert_eq 0 "$st" "the gated form passes"
  assert_contains "$TMP/vg.out" '^studio-brief: 4 tasks, 5 Spec items ok$' "and counts as before"
}
# #66 AC4: no detector → rewrite passes through with one warning; validate fails closed; task warns once.
test_brief_missing_detector() {
  mkdir -p "$TMP/nodet"; cp "$BRIEF" "$TMP/nodet/studio-brief"; ln -s "$STATE_BIN" "$TMP/nodet/studio-state"
  printf 'x `Godot --script a.gd`\n' > "$TMP/nd.md"
  sh "$TMP/nodet/studio-brief" rewrite < "$TMP/nd.md" > "$TMP/nd.out" 2> "$TMP/nd.err"; st=$?
  assert_eq 0 "$st" "rewrite without the detector exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/nd.md" "$TMP/nd.out"; then _pass "and passes the text through"; else _fail "and passes the text through"; fi
  assert_contains "$TMP/nd.err" 'godot-cmd.awk' "with a warning naming the detector"
  assert_eq 1 "$(grep -c . "$TMP/nd.err")" "one warning"
  Q="$TMP/projnd"; build_fixture "$Q"
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  ( cd "$Q" && sh "$TMP/nodet/studio-brief" validate docs/plan.md ) > "$TMP/ndv.out" 2> "$TMP/ndv.err"; st=$?
  assert_eq 1 "$st" "validate without the detector fails closed"
  assert_contains "$TMP/ndv.err" 'reinstall omega-ai' "and says to reinstall"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$TMP/nodet/studio-brief" task 3 ) > "$TMP/ndt.out" 2> "$TMP/ndt.err"; st=$?
  assert_eq 0 "$st" "task without the detector still exits 0"
  assert_contains "$TMP/ndt.out" "MARK-T3" "with the raw task text"
  assert_eq 1 "$(grep -c 'godot-cmd.awk' "$TMP/ndt.err")" "one warning for all its parts"
}
# #66 R4: a detector that is present but fails — task warns once and prints raw; validate fails closed; rewrite passes through.
test_brief_broken_detector() {
  mkdir -p "$TMP/baddet"; cp "$BRIEF" "$TMP/baddet/studio-brief"; ln -s "$STATE_BIN" "$TMP/baddet/studio-state"
  printf 'BEGIN { exit 3 }\n' > "$TMP/baddet/godot-cmd.awk"
  Q="$TMP/projbd"; build_fixture "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$TMP/baddet/studio-brief" task 3 ) > "$TMP/bdt.out" 2> "$TMP/bdt.err"; st=$?
  assert_eq 0 "$st" "task with a failing detector exits 0"
  assert_contains "$TMP/bdt.out" "MARK-T3" "and prints the raw task body"
  assert_contains "$TMP/bdt.err" 'detector failed' "with a warning that the detector failed"
  assert_eq 1 "$(grep -c 'detector failed' "$TMP/bdt.err")" "one warning for all its parts"
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  ( cd "$Q" && sh "$TMP/baddet/studio-brief" validate docs/plan.md ) > "$TMP/bdv.out" 2> "$TMP/bdv.err"; st=$?
  assert_eq 1 "$st" "validate with a failing detector fails closed"
  assert_contains "$TMP/bdv.err" 'reinstall omega-ai' "and says to reinstall"
  printf 'x `Godot --script a.gd`\n' > "$TMP/bd.md"
  sh "$TMP/baddet/studio-brief" rewrite < "$TMP/bd.md" > "$TMP/bdr.out" 2> "$TMP/bdr.err"; st=$?
  assert_eq 0 "$st" "rewrite with a failing detector exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/bd.md" "$TMP/bdr.out"; then _pass "and passes the text through"; else _fail "and passes the text through"; fi
  assert_eq 1 "$(grep -c . "$TMP/bdr.err")" "one warning"
}
# #66 R4: rewrite with an unusable TMPDIR warns and passes stdin through.
test_brief_rewrite_no_tmpdir() {
  printf 'x `Godot --script a.gd`\n' > "$TMP/nt.md"
  ( TMPDIR="$TMP/does-not-exist"; export TMPDIR; sh "$BRIEF" rewrite < "$TMP/nt.md" > "$TMP/nt.out" 2> "$TMP/nt.err" ); st=$?
  assert_eq 0 "$st" "rewrite with an unusable TMPDIR exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/nt.md" "$TMP/nt.out"; then _pass "and passes stdin through unchanged"; else _fail "and passes stdin through unchanged"; fi
  assert_contains "$TMP/nt.err" 'temp file' "with a warning"
}
# #66 I1: rewrite <file> gates the file in place (task-brief writes the brief to
# a file and prints only its path); no c form, a missing or failing detector or
# an unwritable directory leave it untouched; a missing file is an error.
test_brief_rewrite_file() {
  mkdir -p "$TMP/rf"
  printf -- '### Task 1: x\n- [ ] **Step 1:** `Godot --headless --path . --script res://a.gd` then check.\n```sh\nGodot --headless --import .\n```\n' > "$TMP/rf/brief.md"
  printf -- '### Task 1: x\n- [ ] **Step 1:** `studio-gate godot -- Godot --headless --path . --script res://a.gd` then check.\n```sh\nstudio-gate godot -- Godot --headless --import .\n```\n' > "$TMP/rf/brief.want"
  ( cd "$TMP/rf" && sh "$BRIEF" rewrite brief.md ) > "$TMP/rf.out" 2> "$TMP/rf.err"; st=$?
  assert_eq 0 "$st" "rewrite <file> exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rf/brief.want" "$TMP/rf/brief.md"; then _pass "the file is gated in place (path relative to the caller)"
  else _fail "the file is gated in place ($(diff "$TMP/rf/brief.want" "$TMP/rf/brief.md" | head -n 4 | tr '\n' '|'))"; fi
  assert_eq "" "$(cat "$TMP/rf.out")" "nothing on stdout"
  assert_eq "" "$(cat "$TMP/rf.err")" "nothing on stderr"
  assert_eq "brief.md brief.want" "$(ls -A "$TMP/rf" | tr '\n' ' ' | sed 's/ $//')" "no temp file left beside it"
  printf 'a\tb\r\n- `ls -la` \303\251\n```\nGodot --version\n```\nno final newline `Godot --script a.gd' > "$TMP/rf/same.md"
  cp "$TMP/rf/same.md" "$TMP/rf.same.orig"
  sh "$BRIEF" rewrite "$TMP/rf/same.md" 2> "$TMP/rf.err"; st=$?
  assert_eq 0 "$st" "no c form: exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rf.same.orig" "$TMP/rf/same.md"; then _pass "no c form: byte-identical (tab, CR, UTF-8, fence, no final newline)"; else _fail "no c form: byte-identical"; fi
  printf 'x `Godot --script a.gd`' > "$TMP/rf/nonl.md"
  sh "$BRIEF" rewrite "$TMP/rf/nonl.md"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$(cat "$TMP/rf/nonl.md")" = 'x `studio-gate godot -- Godot --script a.gd`' ] && [ -n "$(tail -c1 "$TMP/rf/nonl.md")" ]; then _pass "no final newline in, none added"; else _fail "no final newline in, none added"; fi
  mkdir -p "$TMP/rfbad"; cp "$BRIEF" "$TMP/rfbad/studio-brief"; ln -s "$STATE_BIN" "$TMP/rfbad/studio-state"
  printf 'BEGIN { exit 3 }\n' > "$TMP/rfbad/godot-cmd.awk"
  printf 'x `Godot --script a.gd`\n' > "$TMP/rf/bd.md"; cp "$TMP/rf/bd.md" "$TMP/rf.bd.orig"
  sh "$TMP/rfbad/studio-brief" rewrite "$TMP/rf/bd.md" > "$TMP/rf.out" 2> "$TMP/rf.err"; st=$?
  assert_eq 0 "$st" "a failing detector: exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rf.bd.orig" "$TMP/rf/bd.md"; then _pass "a failing detector leaves the file untouched"; else _fail "a failing detector leaves the file untouched"; fi
  assert_eq 1 "$(grep -c . "$TMP/rf.err")" "a failing detector: one warning"
  rm -f "$TMP/rfbad/godot-cmd.awk"
  sh "$TMP/rfbad/studio-brief" rewrite "$TMP/rf/bd.md" > "$TMP/rf.out" 2> "$TMP/rf.err"; st=$?
  assert_eq 0 "$st" "a missing detector: exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rf.bd.orig" "$TMP/rf/bd.md"; then _pass "a missing detector leaves the file untouched"; else _fail "a missing detector leaves the file untouched"; fi
  assert_eq 1 "$(grep -c . "$TMP/rf.err")" "a missing detector: one warning"
  assert_contains "$TMP/rf.err" 'godot-cmd.awk' "naming the detector"
  mkdir -p "$TMP/rfro"; cp "$TMP/rf/bd.md" "$TMP/rfro/bd.md"; chmod 555 "$TMP/rfro"
  sh "$BRIEF" rewrite "$TMP/rfro/bd.md" > "$TMP/rf.out" 2> "$TMP/rf.err"; st=$?
  chmod 755 "$TMP/rfro"
  assert_eq 0 "$st" "no temp file possible: exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rf.bd.orig" "$TMP/rfro/bd.md"; then _pass "no temp file possible: the file is untouched"; else _fail "no temp file possible: the file is untouched"; fi
  assert_eq 1 "$(grep -c . "$TMP/rf.err")" "no temp file possible: one warning"
  sh "$BRIEF" rewrite "$TMP/rf/nope.md" > "$TMP/rf.out" 2> "$TMP/rf.err"; st=$?
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$st" -ne 0 ]; then _pass "a missing file exits non-zero"; else _fail "a missing file exits non-zero"; fi
  assert_contains "$TMP/rf.err" 'nope\.md not found' "and names the file"
  assert_eq 0 "$(ls "$TMP/rf" | grep -c nope)" "and creates nothing"
}

run_tests test_godot_cmd_md_finds_bare_forms test_godot_cmd_md_span_edges test_godot_cmd_md_multiline test_brief_task test_brief_final test_brief_refusals test_brief_missing_sections test_brief_directives_task test_brief_directives_final test_brief_directive_text_not_ruling test_brief_directive_edge_cases test_brief_no_directives_no_part test_brief_context_appended test_brief_context_cap test_brief_context_missing_file test_brief_context_no_glob test_brief_final_plan_acceptance test_brief_check_verb test_brief_check_uses_truth_region test_brief_final_reads_check_rulings test_brief_original_plan_item test_brief_usage_names_check test_brief_single_line_item test_brief_validate_good_plan test_brief_validate_reports_all test_brief_validate_duplicate_task test_brief_validate_missing_plan_and_no_state test_brief_validate_relative_to_caller test_brief_rewrite_wraps_only test_brief_task_check_final_rewritten test_brief_validate_godot_form test_brief_missing_detector test_brief_broken_detector test_brief_rewrite_no_tmpdir test_brief_rewrite_file
