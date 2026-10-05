#!/bin/sh
# #42 — `stories`, `worktree`'s candidates, the header and usage, and the
# Milestone gate 2 round trip (spec AC20-AC23, AC26, AC37, AC41).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/tests/state_fixtures.sh"

T="$(printf '\t')"
# story_at D SPEC STAGE — D's own pointer brainstorms SPEC and moves to STAGE (plan or execute).
story_at() {
  for _a in "stage brainstorm" "spec $2" "stage plan"; do st "$1" set $_a >/dev/null 2>&1; done
  [ "$3" = plan ] || st "$1" set stage "$3" >/dev/null 2>&1
}
# finish_at D SPEC — D's own pointer holds SPEC, finished (a shipped line, stage idle).
finish_at() { story_at "$1" "$2" plan; st "$1" ledger "shipped https://x/pull/1" >/dev/null; st "$1" set stage idle >/dev/null; }
# commit_in D — one commit on D's branch, so the branch is not merged into main.
commit_in() { ( cd "$1" && printf '%s\n' "$1" > c.txt && git add c.txt && g commit -qm c ) >/dev/null 2>&1; }
# has_line FILE LINE — the number of lines in FILE exactly equal to LINE.
has_line() { grep -cxF -- "$2" "$1" || true; }

test_state_stories_lists_live_pointers() {
  proj sl; plan_in_p                                        # P's in-place story at plan
  wt a feat/a; WA="$W"; story_at "$WA" docs/t.md plan       # active
  wt e feat/e; WE="$W"; finish_at "$WE" docs/e.md           # finished
  wt n feat/n                                               # pointer-less
  wt i feat/i; WI="$W"; st "$WI" set stage idle >/dev/null  # idle, not finished
  wt x feat/x; WX="$W"; story_at "$WX" docs/x.md plan; rm -rf "$WX"                       # prunable
  wt r feat/r; WR="$W"; story_at "$WR" docs/r.md plan; git -C "$P" worktree remove --force "$WR" >/dev/null 2>&1
  wt d feat/d; WD="$W"; story_at "$WD" docs/d.md plan; git -C "$WD" checkout -q --detach >/dev/null 2>&1
  st_rc "$P" stories; cp "$TMP/st.out" "$TMP/sl.tsv"
  assert_eq 0 "$ST_RC" "stories exits 0"
  assert_eq "$P${T}main${T}plan${T}docs/s.md${T}0/3${T}active" "$(sed -n 1p "$TMP/sl.tsv")" "main's in-place story is first"
  assert_eq 1 "$(has_line "$TMP/sl.tsv" "$WA${T}feat/a${T}plan${T}docs/t.md${T}-${T}active")" "WA is listed active"
  assert_eq 1 "$(has_line "$TMP/sl.tsv" "$WE${T}feat/e${T}idle${T}docs/e.md${T}-${T}finished")" "WE is listed finished"
  assert_eq 1 "$(has_line "$TMP/sl.tsv" "$WD${T}-${T}plan${T}docs/d.md${T}-${T}active")" "a detached worktree's branch is -"
  assert_eq 4 "$(wc -l < "$TMP/sl.tsv" | tr -d ' ')" "nothing else: pointer-less, idle-unfinished, prunable and removed are skipped"
  assert_not_contains "$TMP/sl.tsv" "^$P-n$T" "the pointer-less worktree is skipped"
  assert_not_contains "$TMP/sl.tsv" "^$WI$T" "the idle unfinished pointer is skipped"
  assert_not_contains "$TMP/sl.tsv" "^$WX$T" "the prunable worktree is skipped"
  assert_not_contains "$TMP/sl.tsv" "^$WR$T" "the removed worktree is skipped"
  st "$WA" stories > "$TMP/sl-a.tsv"
  assert_eq "$(cat "$TMP/sl.tsv")" "$(cat "$TMP/sl-a.tsv")" "stories from WA prints the same lines"
  # none: nothing, exit 0.
  proj sn; wt e feat/e
  st_rc "$P" stories
  assert_eq 0 "$ST_RC" "no stories exits 0"
  assert_eq "" "$(cat "$TMP/st.out")" "and prints nothing"
  # git failing (f2-M14).
  mkdir -p "$TMP/nogit"; printf '#!/bin/sh\nexit 1\n' > "$TMP/nogit/git"; chmod +x "$TMP/nogit/git"
  _rc=0; ( cd "$P" && PATH="$TMP/nogit:$PATH" sh "$STATE_BIN" stories ) > "$TMP/ng.out" 2> "$TMP/ng.err" || _rc=$?
  assert_eq 1 "$_rc" "a git failure exits 1"
  assert_eq "studio-state: git worktree list failed" "$(cat "$TMP/ng.err")" "naming git worktree list"
  assert_eq "" "$(cat "$TMP/ng.out")" "and lists nothing"
}

test_state_stories_marks_run_worktrees() {
  proj sr; wt r feat/r; WR="$W"
  st "$WR" init --local >/dev/null; : > "$WR/.studio/run"
  story_at "$WR" docs/t.md plan
  st "$P" stories > "$TMP/sr.tsv"
  assert_eq "$WR${T}feat/r${T}plan${T}docs/t.md${T}-${T}run" "$(cat "$TMP/sr.tsv")" "a run worktree is listed run"
  st "$WR" set stage execute >/dev/null
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "with only a run worktree at execute, worktree from P exits 1"
  assert_eq "studio-state: no feature branch recorded" "$(cat "$TMP/st.err")" "it is no candidate"
  wt e feat/e; WE="$W"; finish_at "$WE" docs/e.md
  st_rc "$P" worktree
  assert_eq 0 "$ST_RC" "a finished WE beside the run worktree is the one candidate"
  assert_eq "$WE" "$(cat "$TMP/st.out")" "worktree prints WE, not counting the run worktree"
}

test_state_stories_branch_rename() {
  proj sb; wt e feat/e; WE="$W"; story_at "$WE" docs/s.md execute; st "$WE" set branch feat/e >/dev/null
  git -C "$WE" branch -m feat/e KAN-1-e
  st "$P" stories > "$TMP/sb.tsv"
  assert_eq "$WE${T}KAN-1-e${T}execute${T}docs/s.md${T}-${T}active" "$(cat "$TMP/sb.tsv")" "stories shows the new branch name"
  st_rc "$WE" worktree
  assert_eq 0 "$ST_RC" "worktree from WE exits 0 after the rename"
  assert_eq "$WE" "$(cat "$TMP/st.out")" "and prints WE"
}

test_state_worktree_from_local_pointer() {
  proj wl; wt e feat/e; WE="$W"; story_at "$WE" docs/s.md execute; st "$WE" set branch feat/e >/dev/null
  st_rc "$WE" worktree
  assert_eq 0 "$ST_RC" "WE on its recorded branch exits 0"
  assert_eq "$WE" "$(cat "$TMP/st.out")" "and prints WE"
  st "$WE" set branch - >/dev/null
  st_rc "$WE" worktree
  assert_eq 1 "$ST_RC" "with branch - it exits 1"
  assert_eq "studio-state: no feature branch recorded" "$(cat "$TMP/st.err")" "no feature branch recorded"
  st "$WE" set branch feat/e >/dev/null
  git -C "$WE" switch -q -c feat/z >/dev/null 2>&1
  git -C "$P" worktree add -q "$P-g" feat/e >/dev/null 2>&1; WG="$P-g"
  st_rc "$WE" worktree
  assert_eq 1 "$ST_RC" "with feat/e checked out in WG it exits 1"
  assert_eq "" "$(cat "$TMP/st.out")" "and never prints WG"
  assert_eq "studio-state: this checkout's story is on feat/e, which is checked out in $WG — switch this checkout back to feat/e" \
    "$(cat "$TMP/st.err")" "naming WG and asking to switch back"
  git -C "$P" worktree remove "$WG" >/dev/null 2>&1
  st_rc "$WE" worktree
  assert_eq 1 "$ST_RC" "with feat/e checked out nowhere and WE on feat/z it exits 1"
  assert_eq "studio-state: this checkout's story is on feat/e, but feat/z is checked out here — switch this checkout back to feat/e" \
    "$(cat "$TMP/st.err")" "naming the current branch"
  git -C "$WE" checkout -q --detach >/dev/null 2>&1
  st_rc "$WE" worktree
  assert_eq 1 "$ST_RC" "on a detached HEAD it exits 1"
  assert_eq "studio-state: this checkout's story is on feat/e, but a detached HEAD is checked out here — switch this checkout back to feat/e" \
    "$(cat "$TMP/st.err")" "naming a detached HEAD"
}

test_state_worktree_candidates_from_main() {
  proj wc; wt e feat/e; WE="$W"; finish_at "$WE" docs/e.md
  st_rc "$P" worktree
  assert_eq 0 "$ST_RC" "one finished WE exits 0"
  assert_eq "$WE" "$(cat "$TMP/st.out")" "and prints WE"
  wt f feat/f; WF="$W"; story_at "$WF" docs/f.md execute
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "WE finished plus WF at execute exits 1"
  assert_eq "" "$(cat "$TMP/st.out")" "printing no path"
  assert_eq "studio-state: 2 stories fit — choose one:" "$(sed -n 1p "$TMP/st.err")" "stderr counts the candidates"
  assert_eq 1 "$(has_line "$TMP/st.err" "$WE${T}feat/e${T}docs/e.md${T}finished")" "and lists WE"
  assert_eq 1 "$(has_line "$TMP/st.err" "$WF${T}feat/f${T}docs/f.md${T}active")" "and lists WF"
  assert_eq 3 "$(wc -l < "$TMP/st.err" | tr -d ' ')" "and nothing else"
  # a story at plan is no candidate; none and no handed line: no feature branch recorded (f2-M16).
  proj wc2; wt a feat/a; WA="$W"; story_at "$WA" docs/t.md plan
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "WA at plan only: exit 1"
  assert_eq "studio-state: no feature branch recorded" "$(cat "$TMP/st.err")" "no feature branch recorded"
  # P idle, spec -, branch feat/f live in a pointer-less WF (f2-I5).
  wt f feat/f; WF="$W"; st "$P" set branch feat/f >/dev/null
  st_rc "$P" worktree
  assert_eq 0 "$ST_RC" "main's recorded branch live in WF is a candidate"
  assert_eq "$WF" "$(cat "$TMP/st.out")" "worktree prints WF"
}

test_state_worktree_main_execute_no_branch() {
  proj mx; plan_in_p; st "$P" set stage execute >/dev/null
  wt f feat/f; WF="$W"; finish_at "$WF" docs/f.md
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "P at execute with branch - exits 1"
  assert_eq "" "$(cat "$TMP/st.out")" "never printing P or WF"
  assert_eq "studio-state: no feature branch recorded" "$(cat "$TMP/st.err")" "no feature branch recorded"
  wt s feat/s; WS="$W"; st "$P" set branch feat/s >/dev/null
  st_rc "$P" worktree
  assert_eq 0 "$ST_RC" "with branch feat/s live in WS it exits 0"
  assert_eq "$WS" "$(cat "$TMP/st.out")" "and prints WS"
  git -C "$P" worktree remove "$WS" >/dev/null 2>&1; git -C "$P" switch -q feat/s >/dev/null 2>&1
  st_rc "$P" worktree
  assert_eq 0 "$ST_RC" "with P on feat/s itself it exits 0"
  assert_eq "$P" "$(cat "$TMP/st.out")" "and prints P"
}

test_state_worktree_legacy_main_branch() {
  proj lm; plan_in_p; wt e feat/e; WE="$W"
  st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null; st "$P" set stage idle >/dev/null
  _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$P" worktree
  assert_eq 0 "$ST_RC" "P idle, spec S, branch feat/e: exit 0"
  assert_eq "$WE" "$(cat "$TMP/st.out")" "worktree prints WE"
  assert_missing "$WE/.studio/STATE.md" "and adopts nothing"
  git -C "$P" worktree remove "$WE" >/dev/null 2>&1
  st_rc "$P" worktree
  assert_eq 3 "$ST_RC" "with WE removed it exits 3, as today"
  assert_eq "studio-state: no worktree has feat/e checked out" "$(sed -n 1p "$TMP/st.err")" "naming the branch"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P is unchanged"
}

test_state_review_from_main_finds_worktree_born_story() {
  proj rv; plan_in_p; wt e feat/e; WE="$W"
  st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null
  mkdir -p "$WE/.studio/ledger"; printf -- '- 2026-10-05 shipped https://x/pull/1\n' > "$WE/.studio/ledger/s.md"
  st "$P" set stage idle >/dev/null                          # a finished legacy story, WE not adopted
  wt a feat/a; WA="$W"; finish_at "$WA" docs/t.md            # WA's worktree-born story finishes
  st "$P" stories > "$TMP/rv.tsv"
  assert_eq 1 "$(has_line "$TMP/rv.tsv" "$WE${T}feat/e${T}idle${T}docs/s.md${T}0/3${T}finished")" "main's row sits at WE"
  assert_eq 1 "$(has_line "$TMP/rv.tsv" "$WA${T}feat/a${T}idle${T}docs/t.md${T}-${T}finished")" "WA is listed finished"
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "worktree from P exits 1"
  assert_eq "" "$(cat "$TMP/st.out")" "never printing WE alone"
  assert_eq "studio-state: 2 stories fit — choose one:" "$(sed -n 1p "$TMP/st.err")" "two stories fit"
  assert_eq 1 "$(has_line "$TMP/st.err" "$WE${T}feat/e${T}docs/s.md${T}finished")" "it lists WE"
  assert_eq 1 "$(has_line "$TMP/st.err" "$WA${T}feat/a${T}docs/t.md${T}finished")" "and WA"
  assert_missing "$WE/.studio/STATE.md" "WE was not adopted by P's calls"
}

test_state_worktree_no_resurrect() {
  proj nr; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"; commit_in "$WE"
  st "$P" handoff "$WE" >/dev/null 2>&1
  st "$WE" reset >/dev/null
  git -C "$P" worktree remove --force "$WE" >/dev/null 2>&1
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "an abandoned, removed S never exits 3"
  assert_eq "studio-state: 1 story fits — choose one:" "$(sed -n 1p "$TMP/st.err")" "it is only offered"
  assert_eq "$WE${T}feat/e${T}docs/s.md${T}removed${T}git worktree add '$WE' 'feat/e' && (cd '$WE' && studio-state take 'docs/s.md')" \
    "$(sed -n 2p "$TMP/st.err")" "as a removed candidate with the re-add-and-take command"
  # T is handed to WF: only the newest handed line is offered.
  plan_in_p docs/t.md; st "$P" set stage execute >/dev/null; wt f feat/f; WF="$W"; commit_in "$WF"
  st "$P" handoff "$WF" >/dev/null 2>&1
  st_rc "$P" worktree
  assert_eq 0 "$ST_RC" "T at execute in WF is the candidate"
  assert_eq "$WF" "$(cat "$TMP/st.out")" "worktree prints WF"
  git -C "$P" worktree remove --force "$WF" >/dev/null 2>&1
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "with WF removed it exits 1"
  assert_contains "$TMP/st.err" "${T}docs/t.md${T}removed${T}" "T is offered"
  assert_not_contains "$TMP/st.err" "docs/s.md" "S is no longer offered"
  git -C "$P" merge -q --no-edit feat/f >/dev/null 2>&1
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "with T's branch merged nothing is offered"
  assert_eq "studio-state: no feature branch recorded" "$(cat "$TMP/st.err")" "no feature branch recorded"
}

test_state_exit_codes_documented() {
  _rc=0; ( cd "$TMP" && sh "$STATE_BIN" ) 2> "$TMP/usage.err" || _rc=$?
  assert_eq 1 "$_rc" "usage exits 1"
  assert_contains "$TMP/usage.err" '4 refused:' "the usage text names exit 4"
  assert_contains "$TMP/usage.err" '| stories |' "the usage line names stories"
  assert_contains "$TMP/usage.err" 'set \[--force\] KEY VALUE' "and set --force"
  sed -n 2,40p "$STATE_BIN" > "$TMP/header.txt"
  assert_contains "$TMP/header.txt" '4 refused: a story switch in this checkout' "the header's Exit line names exit 4"
  assert_not_contains "$TMP/header.txt" 'one project has one stage' "the shared-pointer sentence is gone"
  for _w in 'studio-state stories' 'init --local' 'state.mutex' 'handing' 'STUDIO_STATE_FORCE' 'STUDIO_STATE_NO_ADOPT' 'project-wide' 'pointer-less'; do
    assert_contains "$TMP/header.txt" "$_w" "the header describes $_w"
  done
}

test_state_round_trip_two_stories() {
  proj rt; plan_in_p; wt e feat/e; WE="$W"; wt a feat/a; WA="$W"
  st "$P" set branch - >/dev/null; st "$P" set stage execute >/dev/null           # execute §0 in P
  st "$WE" handoff "$WE" >/dev/null                                               # (c) inside WE
  assert_eq "execute idle -" "$(st "$WE" get stage) $(st "$P" get stage) $(st "$P" get branch)" "S moved to WE; P idle, branch -"
  assert_eq 1 "$(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "P's ledger has the handed line"
  for _a in "stage brainstorm" "spec docs/t.md" "stage plan" "plan docs/p.md" "task 0/3"; do st "$WA" set $_a >/dev/null; done
  _wa="$(sum "$WA/.studio/STATE.md")"
  st "$WE" set task 1/3 >/dev/null; st "$WE" set task 2/3 >/dev/null
  st "$WE" ledger "shipped https://x/pull/1" >/dev/null; st "$WE" set stage idle >/dev/null; st "$WE" set task - >/dev/null
  _we="$(sum "$WE/.studio/STATE.md")"
  st "$P" stories > "$TMP/rt.tsv"
  assert_contains "$TMP/rt.tsv" "^$WE${T}feat/e${T}idle${T}docs/s.md${T}-${T}finished$" "stories lists WE finished"
  assert_contains "$TMP/rt.tsv" "^$WA${T}feat/a${T}plan${T}docs/t.md${T}0/3${T}active$" "stories lists WA active"
  assert_eq "$WE" "$(st "$P" worktree)" "worktree from P prints WE (WA at plan is no candidate)"
  st_rc "$P" set stage brainstorm; assert_eq 0 "$ST_RC" "P starts story T"
  st_rc "$P" set spec docs/t.md; assert_eq 0 "$ST_RC" "P sets T's spec with WE on disk"
  assert_eq "$_wa" "$(sum "$WA/.studio/STATE.md")" "WA never changed because of S or T"
  assert_eq "$_we" "$(sum "$WE/.studio/STATE.md")" "WE never changed because of A or T"
  assert_eq docs/t.md "$(st "$P" get spec)" "P holds T, not A"
  assert_eq 0 "$(sed -n '/^## Ledger/,$p' "$P/.studio/STATE.md" | grep -c 'docs/t.md')" "P's ledger holds no line written from WA"
}

run_tests test_state_stories_lists_live_pointers test_state_stories_marks_run_worktrees \
  test_state_stories_branch_rename test_state_worktree_from_local_pointer \
  test_state_worktree_candidates_from_main test_state_worktree_main_execute_no_branch \
  test_state_worktree_legacy_main_branch test_state_review_from_main_finds_worktree_born_story \
  test_state_worktree_no_resurrect test_state_exit_codes_documented test_state_round_trip_two_stories
