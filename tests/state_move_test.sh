#!/bin/sh
# #42 — handoff, take, restore, adopt, self-heal and the take hint
# (spec AC4, AC12-AC19, AC27, AC28).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/tests/state_fixtures.sh"

T="$(printf '\t')"
# fields D — D's stage, spec, plan, task and branch on one line.
fields() { for _fk in stage spec plan task branch; do st "$1" get $_fk; done | tr '\n' ' ' | sed 's/ $//'; }
# kind_n FILE KIND — the number of KIND move records in FILE.
kind_n() { grep -c "^- [0-9-]* $2$T" "$1"; }
# story_in D SPEC — D brainstorms and plans SPEC itself (its own pointer).
story_in() { for _a in "stage brainstorm" "spec $2" "stage plan"; do st "$1" set --force $_a >/dev/null 2>&1; done; }
# commit_ledger D MSG — commit D's .studio/ledger on its branch.
commit_ledger() { ( cd "$1" && git add -f .studio/ledger && g commit -qm "$2" ) >/dev/null 2>&1; }

test_state_handoff_moves_story() {
  proj hm; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  printf -- '- 2026-10-01 Bug: x\n- 2026-10-01 abandoned docs/old.md\n' >> "$P/.studio/STATE.md"
  _ms="$(st "$P" get milestone)"
  st_rc "$P" handoff "$WE"
  assert_eq 0 "$ST_RC" "handoff exits 0"; assert_contains "$TMP/st.out" "^handed docs/s.md to $WE$" "prints the move"
  assert_eq "execute docs/s.md docs/p.md 0/3 feat/e" \
    "$(for k in stage spec plan task branch; do st "$WE" get $k; done | tr '\n' ' ' | sed 's/ $//')" "WE holds the story"
  assert_eq 1 "$(grep -c '^- ' "$WE/.studio/STATE.md")" "WE's ledger holds only the handed line"
  assert_eq "idle - - - -" "$(for k in stage spec plan task branch; do st "$P" get $k; done | tr '\n' ' ' | sed 's/ $//')" "P is idle"
  assert_eq "$_ms" "$(st "$P" get milestone)" "milestone kept"
  assert_contains "$P/.studio/STATE.md" "Bug: x" "main keeps its notes (D1)"
  assert_contains "$P/.studio/STATE.md" "abandoned docs/old.md" "and its abandoned line"
  assert_eq 1 "$(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "the move reads handed in main"
  assert_eq 0 "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md")" "no handing line left"
  assert_not_contains "$WE/.studio/STATE.md" '^milestone:' "the target pointer has no milestone line"
  _x="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  assert_eq 1 "$(grep -cxF .studio/STATE.md "$_x")" "STATE.md excluded once"
  assert_eq "" "$(git -C "$WE" status --porcelain)" "the target pointer never shows in git status"
  # f2-M7: an idle target's own ledger lines stay, before the handed line.
  proj hm2; plan_in_p; wt e feat/e; WE="$W"; st "$WE" ledger "Bug: y" >/dev/null
  st "$P" handoff "$WE" >/dev/null 2>&1
  assert_eq "Bug: y|handed" "$(sed -n 's/^- [0-9-]* \(Bug: y\)$/\1/p; s/^- [0-9-]* \(handed\)\t.*/\1/p' "$WE/.studio/STATE.md" | tr '\n' '|' | sed 's/|$//')" "Bug: y kept before handed"
}

test_state_handoff_order_and_self_heal() {
  proj ho; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  assert_eq 1 "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md")" "kill after step 3: the intent line"
  assert_missing "$WE/.studio/STATE.md" "kill after step 3: no target yet"
  _b="$(sum "$P/.studio/STATE.md")"
  ( cd "$P" && STUDIO_STATE_NO_ADOPT=1 sh "$STATE_BIN" get stage ) >/dev/null 2>&1
  assert_eq "$_b" "$(sum "$P/.studio/STATE.md")" "NO_ADOPT suppresses the heal (AC19)"
  assert_eq idle "$(st "$P" get stage)" "the next P read completes the move"
  assert_eq docs/s.md "$(st "$WE" get spec)" "the target holds S"
  assert_eq "0 1" "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md") $(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "one handed, no handing"
  # kill after step 4; the target advances first; the heal runs step 5 only (f2-I2c).
  proj ho4; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill4 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  st "$WE" set task 2/3 >/dev/null; _wl="$(grep -c '^- ' "$WE/.studio/STATE.md")"
  st "$P" get stage >/dev/null
  assert_eq 2/3 "$(st "$WE" get task)" "the target's progress is kept"
  assert_eq "$_wl" "$(grep -c '^- ' "$WE/.studio/STATE.md")" "no ledger line added to the target"
  assert_eq idle "$(st "$P" get stage)" "P idle"
  # worktree gone after step 3: one void line, then nothing (f2-I2a).
  proj hov; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  git -C "$P" worktree remove "$WE" >/dev/null 2>&1
  st "$P" get stage >/dev/null; st "$P" show >/dev/null
  assert_eq 1 "$(grep -c "$(printf ' void\t.*reason=worktree gone\tpath=')" "$P/.studio/STATE.md")" "one void line"
  assert_eq execute "$(st "$P" get stage)" "main keeps its story"
  # a re-run of the same handoff heals first: no second record (f2-M13; G4).
  proj hor; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && STUDIO_STATE_TEST_SEAM=kill3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1
  st_rc "$P" handoff "$WE"
  assert_eq 0 "$ST_RC" "the re-run exits 0"
  assert_eq "0 1" "$(grep -c "$(printf ' handing\t')" "$P/.studio/STATE.md") $(grep -c "$(printf ' handed\t')" "$P/.studio/STATE.md")" "no second record"
  assert_contains "$TMP/st.out" "^handed docs/s.md to $WE$" "the re-run prints the move"
}

test_state_self_heal_ignores_completed_handoff() {
  proj hic; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  st "$P" handoff "$WE" >/dev/null 2>&1
  st "$WE" reset >/dev/null 2>&1
  _rc=0; git -C "$P" worktree remove "$WE" >/dev/null 2>&1 || _rc=$?
  assert_eq 0 "$_rc" "the abandoned WE is removed without --force"
  plan_in_p
  git -C "$P" worktree add -q "$WE" feat/e >/dev/null 2>&1
  _s="$(sum "$P/.studio/STATE.md")"
  st "$P" get stage >/dev/null; st "$P" show >/dev/null
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "a handed line is never acted on"
  assert_missing "$WE/.studio/STATE.md" "and the re-made WE gets no pointer"
  st_rc "$P" handoff "$WE"
  assert_eq 0 "$ST_RC" "handoff WE then exits 0"
  assert_eq docs/s.md "$(st "$WE" get spec)" "and moves S"
  # a handed line naming main's current spec changes nothing (f2-M13).
  proj hic2; plan_in_p; wt e feat/e; WE="$W"
  printf -- '- 2026-10-05 handed\tspec=docs/s.md\tplan=docs/p.md\tbranch=feat/e\tpath=%s\n' "$WE" >> "$P/.studio/STATE.md"
  _s="$(sum "$P/.studio/STATE.md")"
  assert_eq plan "$(st "$P" get stage)" "P keeps its story"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "the handed line changes nothing"
  assert_missing "$WE/.studio/STATE.md" "and writes no target"
}

test_state_self_heal_scope() {
  proj hsc; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  printf -- '- 2026-10-05 handing\tspec=docs/s.md\tplan=docs/p.md\tbranch=feat/e\tpath=%s\n' "$WE" >> "$P/.studio/STATE.md"
  _s="$(sum "$P/.studio/STATE.md")"
  for _d in "$P" "$WE"; do
    st "$_d" root >/dev/null 2>&1; st "$_d" root --work >/dev/null 2>&1
    st_rc "$_d" bogus
    assert_eq 1 "$ST_RC" "a usage error exits 1 ($(basename "$_d"))"
  done
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "root, root --work and usage never heal"
  assert_missing "$WE/.studio/STATE.md" "and write no target"
  assert_missing "$P/.studio/state.mutex" "and leave no mutex"
  assert_eq idle "$(st "$P" get stage)" "get stage then heals"
  assert_eq docs/s.md "$(st "$WE" get spec)" "the target holds S"
}

test_state_move_record_parse() {
  proj mrp; _sp='docs/a b to (c).md'
  ( cd "$P" && printf '# A\n' > "$_sp" && git add -A && g commit -qm a ) >/dev/null 2>&1
  for _a in "stage brainstorm" "stage plan" "plan docs/p.md" "task 0/3"; do
    [ "$_a" = "stage plan" ] && st "$P" set spec "$_sp" >/dev/null 2>&1
    st "$P" set $_a >/dev/null 2>&1
  done
  wt "w x" feat/w; WX="$W"
  st_rc "$P" handoff "$WX"
  assert_eq 0 "$ST_RC" "a spec and a path with spaces and ( hand off"
  assert_eq "handed $_sp to $WX" "$(cat "$TMP/st.out")" "prints the move intact"
  assert_eq "$_sp" "$(st "$WX" get spec)" "WX holds the spec intact"
  _f="$P/.studio/STATE.md"
  assert_eq "$_sp" "$(sed -n "s/^- [0-9-]* handed${T}spec=\([^$T]*\)${T}.*/\1/p" "$_f")" "the record's spec round-trips"
  assert_eq docs/p.md "$(sed -n "s/^- [0-9-]* handed${T}.*${T}plan=\([^$T]*\)${T}.*/\1/p" "$_f")" "its plan round-trips"
  assert_eq feat/w "$(sed -n "s/^- [0-9-]* handed${T}.*${T}branch=\([^$T]*\)${T}.*/\1/p" "$_f")" "its branch round-trips"
  assert_eq "$WX" "$(sed -n "s/^- [0-9-]* handed${T}.*${T}path=\(.*\)$/\1/p" "$_f")" "its path round-trips, last"
  assert_eq 1 "$(kind_n "$WX/.studio/STATE.md" handed)" "the target has the same record"
  st "$P" stories > "$TMP/mrp.tsv"
  assert_eq 1 "$(grep -cxF "$WX${T}feat/w${T}plan${T}$_sp${T}0/3${T}active" "$TMP/mrp.tsv")" "stories lists the space path intact"
  ( cd "$WX" && printf w > w.txt && git add w.txt && g commit -qm w ) >/dev/null 2>&1   # feat/w unmerged
  git -C "$P" worktree remove "$WX" >/dev/null 2>&1
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "worktree from P offers the removed story with exit 1"
  assert_eq "$WX${T}feat/w${T}$_sp${T}removed${T}git worktree add '$WX' 'feat/w' && (cd '$WX' && studio-state take 'docs/a b to (c).md')" \
    "$(sed -n 2p "$TMP/st.err")" "as a removed candidate with shq-quoted parts"
  git -C "$P" worktree add -q "$WX" feat/w >/dev/null 2>&1
  st_rc "$WX" take "$_sp"
  assert_eq 0 "$ST_RC" "take restores it after removal"
  assert_eq "restored $_sp from the handed line" "$(cat "$TMP/st.out")" "and says so"
  assert_eq "execute $_sp docs/p.md 0/3 feat/w" "$(fields "$WX")" "WX holds it again"
  # a TAB in spec cannot be recorded (f2-M2).
  proj mrt; wt e feat/e; WE="$W"
  st "$P" set stage brainstorm >/dev/null; st "$P" set spec "$(printf 'docs/a\tb.md')" >/dev/null; st "$P" set stage plan >/dev/null
  _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$P" handoff "$WE"
  assert_eq 1 "$ST_RC" "a TAB in spec exits 1"
  assert_contains "$TMP/st.err" '^studio-state: a TAB in spec cannot be recorded$' "naming the field"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "and writes nothing"
}

test_state_handoff_refusals() {
  proj hr; plan_in_p; wt e feat/e; WE="$W"; _f="$P/.studio/STATE.md"; _s="$(sum "$_f")"
  _rc=0; ( cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1 || _rc=$?
  assert_eq 1 "$_rc" "exit 1 under STUDIO_STORY"
  st_rc "$P" handoff "$P"
  assert_eq 1 "$ST_RC" "exit 1 to the main checkout"
  assert_contains "$TMP/st.err" 'is not a live linked worktree of this repository' "naming the rule"
  st_rc "$P" handoff /tmp
  assert_eq 1 "$ST_RC" "exit 1 to a path that is no worktree"
  st_rc "$P" handoff "$TMP/nowhere"
  assert_eq 1 "$ST_RC" "exit 1 to a missing path"
  wt d feat/d; WD="$W"; git -C "$WD" checkout -q --detach >/dev/null 2>&1
  st_rc "$P" handoff "$WD"
  assert_eq 1 "$ST_RC" "exit 1 to a detached worktree"
  assert_eq "studio-state: $WD has a detached HEAD — check out the story's branch there first" "$(cat "$TMP/st.err")" "with the detached text"
  st_rc "$P" handoff
  assert_eq 1 "$ST_RC" "handoff without a path is usage"
  st_rc "$P" handoff "$WE" extra
  assert_eq 1 "$ST_RC" "handoff with two paths is usage"
  assert_eq "$_s" "$(sum "$_f")" "the exit-1 refusals write nothing"
  assert_missing "$WE/.studio/STATE.md" "nor a target"
  assert_missing "$WD/.studio/STATE.md" "nor a detached target"
  proj hri; wt e feat/e
  st_rc "$P" handoff "$W"
  assert_eq 1 "$ST_RC" "exit 1 from an idle P"
  assert_contains "$TMP/st.err" 'no story to hand off' "naming the idle main"
  # exit 4 onto a target holding another story, active or finished.
  proj hr4; plan_in_p; _f="$P/.studio/STATE.md"
  wt a feat/a; WA="$W"; story_in "$WA" docs/t.md; _sa="$(sum "$WA/.studio/STATE.md")"; _s="$(sum "$_f")"
  st_rc "$P" handoff "$WA"
  assert_eq 4 "$ST_RC" "exit 4 onto WA holding a story"
  assert_eq "studio-state: $WA holds story t (stage plan) — finish or reset it there first, or pass --force" "$(cat "$TMP/st.err")" "naming it"
  wt f feat/f; WF="$W"; story_in "$WF" docs/t.md; st "$WF" ledger "shipped feat/f" >/dev/null; st "$WF" set stage idle >/dev/null
  _sf="$(sum "$WF/.studio/STATE.md")"
  st_rc "$P" handoff "$WF"
  assert_eq 4 "$ST_RC" "exit 4 onto WF holding a finished story"
  assert_contains "$TMP/st.err" "$WF holds story t (stage idle)" "naming it"
  assert_eq "$_s $_sa $_sf" "$(sum "$_f") $(sum "$WA/.studio/STATE.md") $(sum "$WF/.studio/STATE.md")" "the exit-4 refusals write nothing"
  st_rc "$P" handoff --force "$WA"
  assert_eq 0 "$ST_RC" "--force moves it"
  assert_eq "plan docs/s.md docs/p.md 0/3 feat/a" "$(fields "$WA")" "WA holds S"
  assert_eq 1 "$(grep -c "^- [0-9-]* forced handoff=$WA over docs/t.md (stage plan)$" "$WA/.studio/STATE.md")" "with one forced line"
  assert_eq "forced|handed" "$(sed -n 's/^- [0-9-]* \(forced\) .*/\1/p; s/^- [0-9-]* \(handed\)\t.*/\1/p' "$WA/.studio/STATE.md" | tr '\n' '|' | sed 's/|$//')" "forced, then handed (G3)"
  # main's own spec in the target: both checkouts named, nothing written (f3-N5).
  proj hrb; plan_in_p; wt s feat/s; WS="$W"; story_in "$WS" docs/s.md; _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$P" handoff "$WS"
  assert_eq 4 "$ST_RC" "exit 4 onto WS holding main's own spec"
  assert_eq "studio-state: s is in both $WS (stage plan) and the main checkout (stage plan) — reset it in one of them, or pass --force" "$(cat "$TMP/st.err")" "naming both checkouts"
  assert_eq 0 "$(kind_n "$P/.studio/STATE.md" handing)" "no handing line"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "and nothing written"
}

test_state_take_after_stop_before_handoff() {
  proj tsb; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/s; WE="$W"
  st "$WE" show > "$TMP/show.out"
  assert_eq "the main checkout's story docs/s.md (stage execute) — if no session is working on it in $P, studio-state take docs/s.md continues it here" \
    "$(tail -n 1 "$TMP/show.out")" "WE's show ends with the take hint"
  assert_missing "$WE/.studio/STATE.md" "show writes nothing"
  st_rc "$WE" take docs/s.md
  assert_eq 0 "$ST_RC" "take exits 0"
  assert_eq "handed docs/s.md to $WE" "$(cat "$TMP/st.out")" "and prints the move (G7)"
  assert_eq "execute docs/s.md docs/p.md 0/3 feat/s" "$(fields "$WE")" "WE holds the story on its branch"
  assert_eq "idle - - - -" "$(fields "$P")" "P idle with branch -"
  assert_eq 1 "$(kind_n "$P/.studio/STATE.md" handed)" "one handed line"
  assert_eq 0 "$(kind_n "$P/.studio/STATE.md" handing)" "no handing line"
}

test_state_take_main_planned_story() {
  proj tmp; plan_in_p; wt x feat/x; WX="$W"
  st_rc "$WX" take docs/s.md
  assert_eq 0 "$ST_RC" "take of a planned story exits 0"
  assert_eq "plan docs/s.md docs/p.md 0/3 feat/x" "$(fields "$WX")" "WX holds it"
  assert_eq "idle - - - -" "$(fields "$P")" "P idle"
  _s="$(sum "$P/.studio/STATE.md")"
  st "$WX" set stage execute >/dev/null
  assert_eq execute "$(st "$WX" get stage)" "WX advances"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "and writes WX only"
}

test_state_take_refusals() {
  proj tr; plan_in_p; wt x feat/x; WX="$W"; _s="$(sum "$P/.studio/STATE.md")"
  for _fo in "" --force; do
    st_rc "$WX" take $_fo docs/t.md
    assert_eq 4 "$ST_RC" "take${_fo:+ $_fo} T while P holds S exits 4"
    assert_eq "studio-state: the main checkout's story is docs/s.md, not docs/t.md" "$(cat "$TMP/st.err")" "naming main's story"
  done
  st_rc "$P" take docs/s.md
  assert_eq 1 "$ST_RC" "take in the main checkout exits 1"
  assert_contains "$TMP/st.err" 'take runs in a linked worktree' "naming the rule"
  _rc=0; ( cd "$WX" && STUDIO_STORY=S1 sh "$STATE_BIN" take docs/s.md ) >/dev/null 2>&1 || _rc=$?
  assert_eq 1 "$_rc" "take under STUDIO_STORY exits 1"
  st_rc "$WX" take
  assert_eq 1 "$ST_RC" "take without a spec is usage"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "the refusals write nothing"
  assert_missing "$WX/.studio/STATE.md" "nor a pointer here"
  # main at execute with its branch live in WE: not overridable.
  proj tre; plan_in_p; st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null
  wt e feat/e; WE="$W"; wt x feat/x; WX="$W"; _s="$(sum "$P/.studio/STATE.md")"
  for _fo in "" --force; do
    st_rc "$WX" take $_fo docs/s.md
    assert_eq 4 "$ST_RC" "take${_fo:+ $_fo} of a story executing in WE exits 4"
    assert_eq "studio-state: docs/s.md is being executed in $WE — continue it there" "$(cat "$TMP/st.err")" "naming WE"
  done
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "and writes nothing"
  assert_missing "$WX/.studio/STATE.md" "nor a pointer in WX"
  # WA holding A: AC15's exit 4, and --force moves it.
  proj tra; plan_in_p; wt a feat/a; WA="$W"; story_in "$WA" docs/t.md; _sa="$(sum "$WA/.studio/STATE.md")"
  st_rc "$WA" take docs/s.md
  assert_eq 4 "$ST_RC" "take in WA holding A exits 4"
  assert_eq "studio-state: $WA holds story t (stage plan) — finish or reset it there first, or pass --force" "$(cat "$TMP/st.err")" "naming A"
  assert_eq "$_sa" "$(sum "$WA/.studio/STATE.md")" "and writes nothing"
  st_rc "$WA" take --force docs/s.md
  assert_eq 0 "$ST_RC" "take --force moves it"
  assert_eq "plan docs/s.md docs/p.md 0/3 feat/a" "$(fields "$WA")" "WA holds S"
  assert_eq 1 "$(grep -c "^- [0-9-]* forced handoff=$WA over docs/t.md (stage plan)$" "$WA/.studio/STATE.md")" "with a forced line"
  _sa="$(sum "$WA/.studio/STATE.md")"; _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$WA" take docs/s.md
  assert_eq 0 "$ST_RC" "take of a spec already here exits 0"
  assert_eq "docs/s.md is already in this checkout" "$(cat "$TMP/st.out")" "and says so"
  assert_eq "$_sa $_s" "$(sum "$WA/.studio/STATE.md") $(sum "$P/.studio/STATE.md")" "writing nothing"
  # while main also holds it: both checkouts named (f3-N5).
  proj trb; plan_in_p; wt s feat/s; WS="$W"; story_in "$WS" docs/s.md; _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$WS" take docs/s.md
  assert_eq 4 "$ST_RC" "take while P also holds S exits 4"
  assert_eq "studio-state: s is in both $WS (stage plan) and the main checkout (stage plan) — reset it in one of them, or pass --force" "$(cat "$TMP/st.err")" "naming both checkouts"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "and writes nothing"
}

# four_writes D VERDICT LABEL — AC24's four story writes in D.
four_writes() {
  _fw="$1/.studio/STATE.md"
  for _a in "stage plan" "plan docs/p.md" "task 0/3" "stage execute"; do
    _fs="$(sum "$_fw")"
    st_rc "$1" set $_a
    if [ "$2" = refuse ]; then
      assert_eq 4 "$ST_RC" "$3: set $_a exits 4"
      assert_eq "$4" "$(cat "$TMP/st.err")" "$3: naming S and WX"
      assert_eq "$_fs" "$(sum "$_fw")" "$3: writing nothing"
    else
      assert_eq 0 "$ST_RC" "$3: set $_a exits 0"
    fi
  done
}

test_state_write_after_take_refused() {
  proj wat; plan_in_p; wt x feat/x; WX="$W"
  st "$WX" take docs/s.md >/dev/null 2>&1
  _msg="studio-state: this checkout holds no story — docs/s.md moved to $WX on $(date +%Y-%m-%d); continue it there, start a new story with /game-dev:brainstorm, or pass --force"
  four_writes "$P" refuse "after take" "$_msg"
  st_rc "$P" set task -
  assert_eq 0 "$ST_RC" "set task - exits 0"
  st_rc "$P" set --force plan docs/p.md
  assert_eq 0 "$ST_RC" "set --force plan writes"
  assert_eq 1 "$(grep -c '^- [0-9-]* forced plan=docs/p\.md over docs/s\.md (stage idle)$' "$P/.studio/STATE.md")" "with a forced line"
  st "$P" set plan - >/dev/null 2>&1
  st_rc "$P" set stage brainstorm
  assert_eq 0 "$ST_RC" "set stage brainstorm starts a new story"
  st_rc "$P" set spec docs/t.md
  assert_eq 0 "$ST_RC" "set spec T"
  st "$P" reset >/dev/null 2>&1
  assert_contains "$P/.studio/STATE.md" '^- [0-9-]* abandoned docs/t\.md$' "T reset: newest line abandoned"
  four_writes "$P" accept "after abandoned"
  proj wat2
  four_writes "$P" accept "spec - and no handed line"
}

test_state_take_restores_removed_worktree() {
  proj trr; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  st "$P" handoff "$WE" >/dev/null 2>&1
  st "$WE" ledger "T1 complete a..b" >/dev/null; st "$WE" ledger "T2 complete b..c" >/dev/null
  commit_ledger "$WE" ledger
  git -C "$P" worktree remove "$WE" >/dev/null 2>&1
  assert_missing "$WE" "WE is removed"
  _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$P" worktree
  assert_eq 1 "$ST_RC" "worktree from P exits 1 offering the removed story"
  assert_eq 2 "$(wc -l < "$TMP/st.err" | tr -d ' ')" "with one candidate line"
  assert_eq removed "$(sed -n 2p "$TMP/st.err" | cut -f4)" "marked removed"
  _cmd="$(sed -n 2p "$TMP/st.err" | cut -f5-)"
  mkdir -p "$TMP/trr-bin"; ln -sf "$STATE_BIN" "$TMP/trr-bin/studio-state"
  _rc=0; ( cd "$P" && PATH="$TMP/trr-bin:$PATH" sh -c "$_cmd" ) > "$TMP/st.out" 2>/dev/null || _rc=$?
  assert_eq 0 "$_rc" "its command re-adds WE and takes S, exit 0"
  assert_contains "$TMP/st.out" '^restored docs/s.md from the handed line$' "take prints the restore"
  assert_eq "execute docs/s.md docs/p.md 2/3 feat/e" "$(fields "$WE")" "WE holds S with its progress"
  assert_eq 1 "$(grep -c '^- [0-9-]* restored docs/s\.md from the handed line$' "$WE/.studio/STATE.md")" "with a restored line"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P is unchanged"
  assert_eq "" "$(git -C "$WE" status --porcelain)" "the restored pointer never shows in git status"
  # a shipped story restores idle.
  st "$WE" ledger "shipped feat/e" >/dev/null; commit_ledger "$WE" shipped
  git -C "$P" worktree remove "$WE" >/dev/null 2>&1
  git -C "$P" worktree add -q "$WE" feat/e >/dev/null 2>&1
  st_rc "$WE" take docs/s.md
  assert_eq 0 "$ST_RC" "a shipped story's take exits 0"
  assert_eq "idle docs/s.md docs/p.md 2/3 feat/e" "$(fields "$WE")" "and restores it idle"
  # restore needs the plan in this checkout (G2).
  proj trp; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  st "$P" handoff "$WE" >/dev/null 2>&1
  ( cd "$WE" && git rm -q docs/p.md && g commit -qm rm ) >/dev/null 2>&1
  git -C "$P" worktree remove "$WE" >/dev/null 2>&1
  git -C "$P" worktree add -q "$WE" feat/e >/dev/null 2>&1
  st_rc "$WE" take docs/s.md
  assert_eq 1 "$ST_RC" "restore without the plan exits 1"
  assert_eq "studio-state: plan file missing: docs/p.md — restore needs the plan in this checkout" "$(cat "$TMP/st.err")" "naming the plan"
  assert_missing "$WE/.studio/STATE.md" "and writes nothing"
}

test_state_take_restores_renamed_branch() {
  proj trn; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  st "$P" handoff "$WE" >/dev/null 2>&1
  st "$WE" ledger "T1 complete a..b" >/dev/null; commit_ledger "$WE" ledger
  git -C "$WE" branch -m feat/e KAN-1-e >/dev/null 2>&1
  git -C "$P" worktree remove "$WE" >/dev/null 2>&1
  _W2="$P-e2"; git -C "$P" worktree add -q "$_W2" KAN-1-e >/dev/null 2>&1
  _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$_W2" take docs/s.md
  assert_eq 0 "$ST_RC" "take after a branch rename exits 0"
  assert_eq "execute docs/s.md docs/p.md 1/3 KAN-1-e" "$(fields "$_W2")" "restores S on the renamed branch"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P is unchanged"
  wt u feat/u; st_rc "$W" take docs/s.md
  assert_eq 4 "$ST_RC" "an unrelated worktree without S's ledger exits 4"
  assert_eq "studio-state: the main checkout's story is -, not docs/s.md" "$(cat "$TMP/st.err")" "with the not-main's-story text"
  assert_missing "$W/.studio/STATE.md" "and writes nothing"
  # a handed line whose path is still a live worktree elsewhere is not restored.
  proj trl; plan_in_p; wt e feat/e; WE="$W"; st "$P" handoff "$WE" >/dev/null 2>&1
  wt o feat/o; st_rc "$W" take docs/s.md
  assert_eq 4 "$ST_RC" "take while the handed path is live elsewhere exits 4"
}

test_state_adopt_legacy_execute() {
  proj ale; plan_in_p; st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null; wt e feat/e; WE="$W"
  ( cd "$WE" && sh "$STATE_BIN" get plan ) > "$TMP/adopt.out" 2> "$TMP/adopt.err"
  assert_eq docs/p.md "$(cat "$TMP/adopt.out")" "WE's first get plan prints the plan, and only it"
  assert_eq "" "$(cat "$TMP/adopt.err")" "adopt is silent"
  assert_eq "execute docs/s.md docs/p.md 0/3 feat/e" "$(fields "$WE")" "WE holds S"
  assert_eq "idle - - - -" "$(fields "$P")" "P is idle"
  assert_eq 1 "$(kind_n "$P/.studio/STATE.md" handed)" "one handed line"
  assert_contains "$P/.studio/STATE.md" "${T}via=adopt${T}path=$WE$" "carrying via=adopt before path="
  # NO_ADOPT suppresses it (AC19).
  proj ale2; plan_in_p; st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null; wt e feat/e
  _s="$(sum "$P/.studio/STATE.md")"
  assert_eq idle "$(cd "$W" && STUDIO_STATE_NO_ADOPT=1 sh "$STATE_BIN" get stage)" "NO_ADOPT reads idle"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "and moves nothing"
  assert_missing "$W/.studio/STATE.md" "nor creates a pointer"
}

test_state_adopt_legacy_finished() {
  proj alf; plan_in_p; st "$P" set stage idle >/dev/null; st "$P" set branch feat/e >/dev/null; wt e feat/e; WE="$W"
  mkdir -p "$WE/.studio/ledger"; printf '# Ledger — s\n\n- 2026-10-01 shipped feat/e\n' > "$WE/.studio/ledger/s.md"
  assert_eq idle "$(st "$WE" get stage)" "WE reads idle"
  assert_eq docs/s.md "$(st "$WE" get spec)" "and holds S: adopted"
  assert_eq "idle - - - -" "$(fields "$P")" "P is idle with no spec"
  proj alf2; plan_in_p; st "$P" set stage idle >/dev/null; st "$P" set branch feat/e >/dev/null; wt e feat/e
  _s="$(sum "$P/.studio/STATE.md")"
  assert_eq - "$(st "$W" get spec)" "without S's ledger in WE: no adopt"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P is unchanged"
  assert_missing "$W/.studio/STATE.md" "and WE has no pointer"
}

test_state_adopt_skips_next_story() {
  for _stg in brainstorm plan; do
    proj "as$_stg"; st "$P" set stage brainstorm >/dev/null; st "$P" set spec docs/t.md >/dev/null
    [ "$_stg" = brainstorm ] || st "$P" set stage plan >/dev/null
    st "$P" set branch feat/e >/dev/null; wt e feat/e; _s="$(sum "$P/.studio/STATE.md")"
    assert_eq idle "$(st "$W" get stage)" "at $_stg, WE reads idle"
    assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "at $_stg, P is unchanged"
    assert_missing "$W/.studio/STATE.md" "at $_stg, WE has no pointer"
  done
}

test_state_take_hint_under_stale_branch() {
  proj ths; st "$P" set stage brainstorm >/dev/null; st "$P" set spec docs/t.md >/dev/null
  st "$P" set stage plan >/dev/null; st "$P" set plan docs/p.md >/dev/null; st "$P" set branch feat/e >/dev/null
  wt e feat/e; WE="$W"; wt a feat/a; WA="$W"
  st "$WA" show > "$TMP/show.out"
  assert_eq "the main checkout's story docs/t.md (stage plan) — if no session is working on it in $P, studio-state take docs/t.md continues it here" \
    "$(tail -n 1 "$TMP/show.out")" "WA's show ends with the take hint"
  st_rc "$WA" take docs/t.md
  assert_eq 0 "$ST_RC" "take A in WA moves it"
  assert_eq "plan docs/t.md docs/p.md - feat/a" "$(fields "$WA")" "WA holds A"
  assert_eq idle "$(st "$WE" get stage)" "WE reads idle"
  assert_missing "$WE/.studio/STATE.md" "WE does not adopt"
  # at execute with feat/e live in WE: no hint in WA.
  proj ths2; plan_in_p; st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null
  wt e feat/e; wt a feat/a; WA="$W"
  st "$WA" show > "$TMP/show.out"
  assert_eq "(no story in this checkout)" "$(tail -n 1 "$TMP/show.out")" "no hint while WE executes it"
  # an adoptable worktree gets the adopt wording, under NO_ADOPT.
  ( cd "$P-e" && STUDIO_STATE_NO_ADOPT=1 sh "$STATE_BIN" show ) > "$TMP/show.out" 2>&1
  assert_eq "the main checkout's story docs/s.md (stage execute) — it moves here on the first studio-state call" \
    "$(tail -n 1 "$TMP/show.out")" "the adoptable form"
  # an agent worktree gets no hint.
  proj ths3; plan_in_p; _A="$P/.claude/worktrees/agent-x"; git -C "$P" worktree add -q -b agent-x "$_A" >/dev/null 2>&1
  st "$_A" show > "$TMP/show.out"
  assert_eq "(no story in this checkout)" "$(tail -n 1 "$TMP/show.out")" "no hint in an agent worktree"
}

test_state_take_refuses_in_place_story() {
  # I1: an in-place story — P itself on feat at execute — is being executed in the
  # main checkout, which is a live worktree too: no hint in WX, and take exits 4 (AC16, AC28).
  proj tip; git -C "$P" checkout -q -b feat >/dev/null 2>&1; plan_in_p
  st "$P" set branch feat >/dev/null; st "$P" set stage execute >/dev/null
  git -C "$P" worktree add -q -b other "$P-x" main >/dev/null 2>&1; WX="$P-x"; _s="$(sum "$P/.studio/STATE.md")"
  st "$WX" show > "$TMP/show.out"
  assert_eq "(no story in this checkout)" "$(tail -n 1 "$TMP/show.out")" "no take hint while P executes it in place"
  for _fo in "" --force; do
    st_rc "$WX" take $_fo docs/s.md
    assert_eq 4 "$ST_RC" "take${_fo:+ $_fo} of the in-place story exits 4"
    assert_eq "studio-state: docs/s.md is being executed in $P — continue it there" "$(cat "$TMP/st.err")" "naming the main checkout"
  done
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P is unchanged"
  assert_missing "$WX/.studio/STATE.md" "and WX has no pointer"
}

test_state_mutex_serialises_moves() {
  proj msm; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"; hold_mutex
  ( cd "$P" && sh "$STATE_BIN" handoff "$WE" ) > /dev/null 2> "$TMP/m1" & _hp=$!
  _s=0; wait "$_hp" || _s=$?
  assert_eq 1 "$_s" "handoff exits 1 after the timeout"
  assert_contains "$TMP/m1" "state.mutex is busy (pid $HOLD_PID)" "naming the holder"
  assert_missing "$WE/.studio/STATE.md" "and writes no target"
  assert_eq 0 "$(kind_n "$P/.studio/STATE.md" handing)" "nor an intent"
  release_mutex; dead_mutex
  st_rc "$P" handoff "$WE"
  assert_eq 0 "$ST_RC" "after a dead holder, the move succeeds"
  assert_eq docs/s.md "$(st "$WE" get spec)" "WE holds S"
}

test_state_handoff_rechecks_target_under_mutex() {
  # T4#3: a target removed while handoff waits for the mutex is refused, not re-created.
  proj hrm; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"; hold_mutex; _s="$(sum "$P/.studio/STATE.md")"
  ( cd "$P" && sh "$STATE_BIN" handoff "$WE" ) > "$TMP/hrm.out" 2> "$TMP/hrm.err" & _hp=$!
  sleep 1; git -C "$P" worktree remove "$WE" >/dev/null 2>&1; release_mutex
  _rc=0; wait "$_hp" || _rc=$?
  assert_eq 1 "$_rc" "handoff to a worktree removed during the wait exits 1"
  assert_eq "studio-state: $WE is not a live linked worktree of this repository" "$(cat "$TMP/hrm.err")" "naming the rule"
  assert_missing "$WE" "and does not re-create it"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "main keeps its story"
}

test_state_mutex_single_acquisition() {
  # One sample each (a heal, an adopt and a restore cannot be repeated); the bound
  # of 5 s still separates one acquisition from a self-wait on the 10 s timeout.
  proj sa; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  printf -- '- 2026-10-05 handing\tspec=docs/s.md\tplan=docs/p.md\tbranch=feat/e\tpath=%s\n' "$WE" >> "$P/.studio/STATE.md"
  _t0=$(date +%s); st "$P" handoff "$WE" >/dev/null 2>&1
  [ $(( $(date +%s) - _t0 )) -lt 5 ] && _pass "heal + move in one acquisition" || _fail "heal + move in one acquisition"; TESTS_RUN=$((TESTS_RUN + 1))
  _x="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  assert_eq 1 "$(grep -cxF .studio/state.mutex "$_x")" "state.mutex excluded once"
  dead_mutex; assert_eq "" "$(git -C "$P" status --porcelain)" "a dangling link never shows in git status"
  # INT during a paused move: exit 130, no link, no target pointer.
  proj si; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  ( cd "$P" && own_group env STUDIO_STATE_TEST_SEAM=pause3 sh "$STATE_BIN" handoff "$WE" ) >/dev/null 2>&1 & _hp=$!
  # Wait for the pause itself (the intent line): bash drops an INT that lands while it
  # waits on a foreground child that does not die of it, so an early INT can be lost.
  _i=0; while ! grep -q "^- [0-9-]* handing$T" "$P/.studio/STATE.md" && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_symlink "$P/.studio/state.mutex" "the paused move holds the mutex"
  sleep 0.3; kill -INT "$_hp"; _s=0; wait "$_hp" || _s=$?
  assert_eq 130 "$_s" "INT exits 130"
  assert_missing "$P/.studio/state.mutex" "the trap released the mutex"
  assert_missing "$WE/.studio/STATE.md" "no target pointer was written"
  # adopt + its write, and a restore, each in one acquisition.
  proj sa2; plan_in_p; wt e feat/e; st "$P" set stage execute >/dev/null; st "$P" set branch feat/e >/dev/null
  _t0=$(date +%s); st "$W" set task 1/3 >/dev/null 2>&1
  [ $(( $(date +%s) - _t0 )) -lt 5 ] && _pass "adopt then set: one acquisition" || _fail "adopt then set: one acquisition"; TESTS_RUN=$((TESTS_RUN + 1))
  assert_eq 1/3 "$(st "$W" get task)" "the adopted story took the write"
  git -C "$P" worktree remove "$W" >/dev/null 2>&1; git -C "$P" worktree add -q "$W" feat/e >/dev/null 2>&1
  _t0=$(date +%s); st "$W" take docs/s.md >/dev/null 2>&1
  [ $(( $(date +%s) - _t0 )) -lt 5 ] && _pass "restore: one acquisition" || _fail "restore: one acquisition"; TESTS_RUN=$((TESTS_RUN + 1))
  assert_eq execute "$(st "$W" get stage)" "the restore landed"
}

test_state_free_text_notes_are_not_records() {
  # Records are anchored to their exact format: a note never triggers a heal or a restore.
  proj ftn; wt e feat/e; WE="$W"
  st "$P" ledger "handing the build to QA" >/dev/null; st "$P" ledger "handed docs/s.md over to Bob" >/dev/null
  _s="$(sum "$P/.studio/STATE.md")"; hold_mutex
  st_rc "$P" get stage
  assert_eq idle "$(cat "$TMP/st.out")" "a handing note is no pending move"
  assert_eq "" "$(cat "$TMP/st.err")" "so no heal waits on the mutex"
  release_mutex
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "and nothing is written"
  st_rc "$P" set stage plan
  assert_eq 0 "$ST_RC" "a handed note does not refuse a story write"
  st_rc "$WE" take docs/s.md
  assert_eq 4 "$ST_RC" "a handed note restores nothing"
}

test_state_rewriters_skip_tab_notes() {
  # T4#2: step 5 and the roll-back rewrite only a record of newest_rec's exact
  # format, never a free-text note that starts "handing<TAB>".
  proj rtn; st "$P" ledger "handing${T}foo" >/dev/null; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  st_rc "$P" handoff "$WE"
  assert_eq 0 "$ST_RC" "the handoff exits 0"
  assert_eq 1 "$(grep -c "^- [0-9-]* handing${T}foo$" "$P/.studio/STATE.md")" "step 5 leaves the note as it was"
  assert_eq "0 1" "$(grep -c "^- [0-9-]* handing${T}spec=" "$P/.studio/STATE.md") $(grep -c "^- [0-9-]* handed${T}spec=" "$P/.studio/STATE.md")" "and rewrites the record to handed"
  proj rtv; st "$P" ledger "handing${T}foo" >/dev/null; plan_in_p
  printf -- '- 2026-10-05 handing\tspec=docs/s.md\tplan=docs/p.md\tbranch=feat/g\tpath=%s\n' "$P-gone" >> "$P/.studio/STATE.md"
  st_rc "$P" get stage
  assert_eq plan "$(cat "$TMP/st.out")" "a heal of a gone target keeps main's story"
  assert_eq 1 "$(grep -c "^- [0-9-]* handing${T}foo$" "$P/.studio/STATE.md")" "the roll-back leaves the note as it was"
  assert_eq "0 1" "$(grep -c "^- [0-9-]* handing${T}spec=" "$P/.studio/STATE.md") $(grep -c "^- [0-9-]* void${T}spec=.*${T}reason=worktree gone${T}path=" "$P/.studio/STATE.md")" "and voids the record"
}

# exclusive-scan: test_state_mutex_single_acquisition in (a, b) asserts 5 s bounds and sends INT inside the paused move
# exclusive-scan: test_state_handoff_rechecks_target_under_mutex in (b) the one second pause must see the handoff blocked on the mutex before the target is removed
TESTS_EXCLUSIVE="test_state_mutex_single_acquisition test_state_handoff_rechecks_target_under_mutex"
run_tests test_state_handoff_moves_story test_state_handoff_order_and_self_heal \
  test_state_self_heal_ignores_completed_handoff test_state_self_heal_scope test_state_move_record_parse \
  test_state_handoff_refusals test_state_take_after_stop_before_handoff test_state_take_main_planned_story \
  test_state_take_refusals test_state_take_refuses_in_place_story test_state_write_after_take_refused test_state_take_restores_removed_worktree \
  test_state_take_restores_renamed_branch test_state_adopt_legacy_execute test_state_adopt_legacy_finished \
  test_state_adopt_skips_next_story test_state_take_hint_under_stale_branch test_state_mutex_serialises_moves \
  test_state_handoff_rechecks_target_under_mutex \
  test_state_mutex_single_acquisition test_state_free_text_notes_are_not_records \
  test_state_rewriters_skip_tab_notes
