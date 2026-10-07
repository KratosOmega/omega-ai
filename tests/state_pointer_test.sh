#!/bin/sh
# #42 — a stage pointer per checkout: resolution, auto-create, the
# project-wide milestone and state.mutex (spec AC1-AC11, AC27, AC40-AC43).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/tests/state_fixtures.sh"

# exclude_of DIR — the common git dir's info/exclude for the repository at DIR.
exclude_of() { printf '%s/info/exclude\n' "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"; }
# header FILE — FILE up to and including its `## Ledger` line.
header() { sed -n '1,/^## Ledger/p' "$1"; }
# after_line FILE KEY — the line right after the first `KEY: ` line.
after_line() { awk -v k="$2: " 'index($0, k) == 1 { getline; print; exit }' "$1"; }
# secs_min2 FUNC — run FUNC twice; SECS is the shorter wall-clock time, in whole seconds.
secs_min2() {
  _t0=$(date +%s); "$1"; _a1=$(( $(date +%s) - _t0 ))
  _t0=$(date +%s); "$1"; _a2=$(( $(date +%s) - _t0 ))
  SECS=$_a1; [ "$_a2" -ge "$SECS" ] || SECS=$_a2
}

test_state_main_checkout_unchanged() {
  proj main
  st "$P" set stage brainstorm >/dev/null
  assert_missing "$P/.studio/state.mutex" "no mutex left after set stage"
  st "$P" set spec docs/s.md >/dev/null
  assert_eq docs/s.md "$(st "$P" get spec)" "P reads its spec"
  assert_contains "$P/.studio/STATE.md" '^spec: docs/s.md$' "the main pointer carries it"
  st "$P" show > "$TMP/show.out"
  assert_contains "$TMP/show.out" '^stage: brainstorm$' "show prints the stage"
  assert_contains "$TMP/show.out" '^milestone: prototype$' "show prints the milestone"
  st "$P" ledger x >/dev/null
  assert_contains "$P/.studio/ledger/s.md" '^- [0-9-]* x$' "the ledger line lands in .studio/ledger/s.md"
  assert_missing "$P/.studio/state.mutex" "no mutex left after ledger"
  st "$P" reset > "$TMP/reset.out"
  assert_contains "$TMP/reset.out" '^reset to idle$' "reset prints as today"
  assert_eq idle "$(st "$P" get stage)" "reset leaves P idle"
  assert_missing "$P/.studio/ledger/s.md" "reset drops the feature ledger"
  assert_contains "$P/.studio/STATE.md" '^milestone: prototype$' "the main pointer keeps its milestone line"
  assert_missing "$P/.studio/state.mutex" "no mutex left after reset"
  assert_contains "$(exclude_of "$P")" '^\.studio/state\.mutex$' "the mutex is git-excluded"
}

test_state_two_worktrees_independent() {
  proj two; wt a feat/a; WA="$W"; wt b feat/b; WB="$W"
  st "$WA" set stage brainstorm >/dev/null; st "$WA" set spec docs/s.md >/dev/null
  st "$WB" set stage brainstorm >/dev/null; st "$WB" set spec docs/t.md >/dev/null
  assert_eq docs/s.md "$(st "$WA" get spec)" "WA reads its own spec"
  assert_eq docs/t.md "$(st "$WB" get spec)" "WB reads its own spec"
  assert_file "$WA/.studio/STATE.md" "WA's pointer exists"; assert_file "$WB/.studio/STATE.md" "WB's pointer exists"
  assert_eq "" "$(git -C "$WA" status --porcelain)" "WA's git status stays clean"
  assert_eq "" "$(git -C "$WB" status --porcelain)" "WB's git status stays clean"
  assert_eq 1 "$(grep -cxF .studio/STATE.md "$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude")" "one exclude line"
  assert_eq idle "$(st "$P" get stage)" "P is untouched"
}

test_state_pointerless_reads_idle() {
  proj pl; plan_in_p; wt c feat/c; _s="$(sum "$P/.studio/STATE.md")"
  assert_eq plan "$(st "$P" get stage)" "P is at plan"
  assert_eq idle "$(st "$W" get stage)" "WC reads idle"
  for _k in spec plan task branch; do
    assert_eq - "$(st "$W" get "$_k")" "WC's $_k is -"
  done
  assert_eq "$(st "$P" get milestone)" "$(st "$W" get milestone)" "WC's milestone is P's"
  st "$W" show > "$TMP/show.out"
  assert_contains "$TMP/show.out" '^stage: idle$' "show prints stage idle"
  assert_contains "$TMP/show.out" '^milestone: prototype$' "show prints main's milestone"
  assert_contains "$TMP/show.out" '^(no story in this checkout)$' "show says there is no story here"
  # AC3/AC28: nothing of main's story but the take hint, which is the last line.
  sed '$d' "$TMP/show.out" > "$TMP/show.head"
  assert_not_contains "$TMP/show.head" 'docs/s.md' "show prints nothing of main's story above the hint"
  assert_contains "$TMP/show.out" "studio-state take docs/s.md continues it here$" "and ends with the take hint"
  assert_eq "check: ok" "$(st "$W" check)" "check prints check: ok"
  st_rc "$W" worktree
  assert_eq 1 "$ST_RC" "worktree exits 1"
  assert_contains "$TMP/st.err" '^studio-state: no feature branch recorded$' "worktree says no feature branch"
  assert_missing "$W/.studio/STATE.md" "reads create no pointer"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "the main pointer is unchanged"
}

test_state_no_main_pointer_exits_1() {
  proj nm; wt c feat/c; rm "$P/.studio/STATE.md"
  st_rc "$W" get stage
  assert_eq 1 "$ST_RC" "get stage exits 1 without a main pointer"
  assert_contains "$TMP/st.err" "run 'studio-state init'" "says to run init"
  st_rc "$W" set stage brainstorm
  assert_eq 1 "$ST_RC" "set exits 1 without a main pointer"
  assert_missing "$W/.studio/STATE.md" "and creates no pointer"
}

test_state_worktree_write_leaves_main_untouched() {
  proj wlm; wt a feat/a; WA="$W"; _s="$(sum "$P/.studio/STATE.md")"
  st "$WA" set stage brainstorm >/dev/null
  assert_contains "$WA/.studio/STATE.md" '^stage: brainstorm$' "WA's own file holds the stage"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P unchanged after WA's set"
  st "$WA" ledger y >/dev/null
  assert_contains "$WA/.studio/STATE.md" '^- [0-9-]* y$' "WA's ledger line is in WA's pointer"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P unchanged after WA's ledger"
  st "$WA" reset >/dev/null
  assert_eq idle "$(st "$WA" get stage)" "WA resets to idle"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P unchanged after WA's reset"
}

test_state_new_story_seeds_idle() {
  proj seed; wt c feat/c
  st "$W" set stage brainstorm >/dev/null
  for _k in spec plan task branch; do
    assert_contains "$W/.studio/STATE.md" "^$_k: -\$" "the new pointer seeds $_k: -"
  done
  assert_contains "$W/.studio/STATE.md" '^stage: brainstorm$' "then applies the write"
  assert_not_contains "$W/.studio/STATE.md" '^milestone:' "a local pointer has no milestone line"
}

test_state_ledger_auto_creates() {
  proj lac; wt c feat/c
  st "$W" ledger "Bug: x" >/dev/null
  assert_file "$W/.studio/STATE.md" "the first ledger write creates the pointer"
  assert_eq 1 "$(sed -n '/^## Ledger/,$p' "$W/.studio/STATE.md" | grep -c '^- [0-9-]* Bug: x$')" "the line is under ## Ledger"
}

test_state_auto_create_race() {
  proj race; _r=1
  while [ "$_r" -le 5 ]; do
    wt "c$_r" "feat/c$_r"
    ( cd "$W" && sh "$STATE_BIN" set spec docs/s.md ) > "$TMP/a.out" 2>&1 & _p1=$!
    ( cd "$W" && sh "$STATE_BIN" set plan docs/p.md ) > "$TMP/b.out" 2>&1 & _p2=$!
    _s1=0; wait "$_p1" || _s1=$?; _s2=0; wait "$_p2" || _s2=$?
    assert_eq "0 0" "$_s1 $_s2" "round $_r: both first writes exit 0"
    assert_eq "docs/s.md docs/p.md" "$(st "$W" get spec) $(st "$W" get plan)" "round $_r: both values land"
    _r=$((_r + 1))
  done
  assert_eq 1 "$(grep -cxF .studio/STATE.md "$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude")" "the exclude line once"
}

test_state_parallel_local_writes_keep_both() {
  proj par; wt a feat/a; st "$W" set stage brainstorm >/dev/null; _r=1; _bad=0
  while [ "$_r" -le 20 ]; do
    ( cd "$W" && sh "$STATE_BIN" set spec "docs/s$_r.md" ) >/dev/null 2>&1 & _p1=$!
    ( cd "$W" && sh "$STATE_BIN" set plan "docs/p$_r.md" ) >/dev/null 2>&1 & _p2=$!
    wait "$_p1"; wait "$_p2"
    [ "$(st "$W" get spec) $(st "$W" get plan)" = "docs/s$_r.md docs/p$_r.md" ] || _bad=$((_bad + 1))
    _r=$((_r + 1))
  done
  assert_eq 0 "$_bad" "20 rounds of a parallel spec/plan pair keep both values (f2-I6)"
}

test_state_exclude_newline_repair() {
  proj exn; wt c feat/c; _ex="$(exclude_of "$P")"
  printf 'x' > "$_ex"
  st "$W" set stage brainstorm >/dev/null
  assert_eq 1 "$(grep -cx x "$_ex")" "the unterminated line x survives whole"
  assert_eq 1 "$(grep -cxF .studio/STATE.md "$_ex")" "the pointer line is its own line"
  assert_eq 1 "$(grep -cxF .studio/state.mutex "$_ex")" "the mutex line is its own line"
}

test_state_reset_pointerless_noop() {
  proj rpn; plan_in_p; wt c feat/c; _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$W" reset
  assert_eq 0 "$ST_RC" "reset exits 0"
  assert_eq "no story in this checkout" "$(cat "$TMP/st.out")" "reset says there is no story"
  st_rc "$W" check --rebuild
  assert_eq 0 "$ST_RC" "check --rebuild exits 0"
  assert_eq "no story in this checkout" "$(cat "$TMP/st.out")" "check --rebuild says there is no story"
  assert_missing "$W/.studio/STATE.md" "neither writes a pointer"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "the main pointer is unchanged"
}

test_state_init_local_is_auto_create() {
  proj ila; wt a feat/a; WA="$W"; wt b feat/b; WB="$W"; wt c feat/c; WC="$W"
  st_rc "$WA" init --local
  assert_eq 0 "$ST_RC" "init --local exits 0"
  st "$WB" set stage brainstorm >/dev/null; st "$WB" reset >/dev/null
  assert_eq "$(header "$WA/.studio/STATE.md")" "$(header "$WB/.studio/STATE.md")" "init --local's header equals an auto-created one"
  st "$WC" set stage idle >/dev/null
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$WA/.studio/STATE.md" "$WC/.studio/STATE.md"; then _pass "byte-identical to an auto-created idle pointer"
  else _fail "byte-identical to an auto-created idle pointer"; fi
  st_rc "$WA" init --local
  assert_eq 1 "$ST_RC" "a second init --local exits 1"
  assert_contains "$TMP/st.err" 'init --local: .* already exists' "and says the pointer exists"
  st_rc "$P" init --local
  assert_eq 1 "$ST_RC" "init --local is refused in the main checkout"
  assert_contains "$TMP/st.err" 'init --local: the main checkout' "and says why"
  _rc=0; ( cd "$WC" && rm -f .studio/STATE.md && STUDIO_STORY=S1 sh "$STATE_BIN" init --local ) > "$TMP/st.out" 2> "$TMP/st.err" || _rc=$?
  assert_eq 1 "$_rc" "init --local is refused under STUDIO_STORY"
  assert_contains "$TMP/st.err" 'cannot be combined with STUDIO_STORY' "and says why"
  assert_missing "$WC/.studio/STATE.md" "the refusal writes nothing"
  # T2#2: two concurrent calls both pass the early check while the mutex is held;
  # the re-check under the mutex makes the second one exit 1 (AC8).
  proj ilc; wt a feat/a; WA="$W"; hold_mutex
  ( cd "$WA" && sh "$STATE_BIN" init --local ) > "$TMP/ic1.out" 2> "$TMP/ic1.err" & _i1=$!
  ( cd "$WA" && sh "$STATE_BIN" init --local ) > "$TMP/ic2.out" 2> "$TMP/ic2.err" & _i2=$!
  sleep 1; release_mutex
  _r1=0; wait "$_i1" || _r1=$?; _r2=0; wait "$_i2" || _r2=$?
  assert_eq "0 1" "$(printf '%s\n%s\n' "$_r1" "$_r2" | sort | tr '\n' ' ' | sed 's/ $//')" "of two concurrent init --local calls, one exits 1"
  cat "$TMP/ic1.err" "$TMP/ic2.err" > "$TMP/ic.err"
  assert_contains "$TMP/ic.err" 'init --local: .* already exists' "the loser says the pointer exists"
}

test_state_init_in_linked_worktree() {
  proj iil; wt c feat/c
  st_rc "$W" init
  assert_eq 1 "$ST_RC" "init in a linked worktree exits 1"
  assert_contains "$TMP/st.err" '^studio-state: this is a linked worktree — its stage pointer is created on its first write; to create it now, run studio-state init --local$' "names init --local"
  assert_missing "$W/.studio/STATE.md" "and writes no pointer"
  mkdir -p "$TMP/nonrepo"
  st_rc "$TMP/nonrepo" init
  assert_eq 0 "$ST_RC" "init outside a repository still works"
  assert_file "$TMP/nonrepo/.studio/STATE.md" "and writes the pointer"
  assert_contains "$TMP/nonrepo/.studio/STATE.md" '^milestone: prototype$' "the main pointer keeps its milestone line"
}

test_state_tracked_pointer_refused() {
  proj trk; wt t feat/t; _s="$(sum "$P/.studio/STATE.md")"
  ( cd "$W" && mkdir -p .studio \
      && printf '# Studio State\n\nstage: execute\nspec: docs/s.md\nplan: -\ntask: -\nbranch: -\n\n## Ledger\n\n' > .studio/STATE.md \
      && git add -f .studio/STATE.md && g commit -qm tracked ) >/dev/null 2>&1
  assert_eq idle "$(st "$W" get stage)" "a tracked STATE.md reads as pointer-less"
  assert_eq - "$(st "$W" get spec)" "and nothing of it is read"
  st_rc "$W" set stage brainstorm
  assert_eq 1 "$ST_RC" "auto-create into a tracked file exits 1"
  assert_contains "$TMP/st.err" "^studio-state: $W/.studio/STATE.md is tracked by git — a tracked STATE.md is never a stage pointer; run git rm --cached .studio/STATE.md on this branch$" "says to git rm --cached"
  assert_contains "$W/.studio/STATE.md" '^stage: execute$' "the tracked file is untouched"
  assert_missing "$P/.studio/state.mutex" "the refusal releases the mutex"
  _rc=0; ( cd "$W" && STUDIO_STORY=S1 sh "$STATE_BIN" init && STUDIO_STORY=S1 sh "$STATE_BIN" set task 1/2 ) >/dev/null 2>&1 || _rc=$?
  assert_eq 0 "$_rc" "STUDIO_STORY init and set exit 0 there"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "the main pointer is unchanged"
  # AC4: take and handoff into WT refuse the same way.
  plan_in_p; _s="$(sum "$P/.studio/STATE.md")"
  st_rc "$P" handoff "$W"
  assert_eq 1 "$ST_RC" "handoff into WT exits 1"
  assert_contains "$TMP/st.err" "^studio-state: $W/.studio/STATE.md is tracked by git — .*run git rm --cached .studio/STATE.md on this branch$" "naming git rm --cached"
  st_rc "$W" take docs/s.md
  assert_eq 1 "$ST_RC" "take in WT exits 1"
  assert_contains "$TMP/st.err" "^studio-state: $W/.studio/STATE.md is tracked by git — .*run git rm --cached .studio/STATE.md on this branch$" "naming git rm --cached"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "the main pointer is unchanged"
  assert_contains "$W/.studio/STATE.md" '^stage: execute$' "the tracked file is untouched"
}

_story_calls() {
  ( cd "$WA" && STUDIO_STORY=S1 sh "$STATE_BIN" init && STUDIO_STORY=S1 sh "$STATE_BIN" set task 1/2 \
      && STUDIO_STORY=S1 sh "$STATE_BIN" ledger x && STUDIO_STORY=S1 sh "$STATE_BIN" check --rebuild ) > "$TMP/story.out" 2>&1 \
    || printf 'failed\n' >> "$TMP/story.out"
}
test_state_story_writes_unchanged() {
  proj swu; wt a feat/a; WA="$W"; hold_mutex
  secs_min2 _story_calls
  [ "$SECS" -lt 2 ] && _pass "STUDIO_STORY calls never wait on the mutex" || _fail "STUDIO_STORY calls never wait on the mutex (${SECS}s)"
  TESTS_RUN=$((TESTS_RUN + 1))
  assert_not_contains "$TMP/story.out" '^failed$' "each call exits 0"
  assert_file "$P/.studio/stories/S1.md" "the story file is at <root>"
  assert_contains "$P/.studio/stories/S1.md" '^task: 0/2$' "check --rebuild rebuilt task from the ledger, as today"
  assert_not_contains "$P/.studio/stories/S1.md" '^milestone:' "a new story file has no milestone line"
  assert_contains "$WA/.studio/ledger/S1.md" '^- [0-9-]* x$' "the ledger line is in WA's ledger dir, as today"
  assert_missing "$WA/.studio/STATE.md" "no local pointer is created"
  assert_eq "$HOLD_PID" "$(readlink "$P/.studio/state.mutex")" "the held mutex is untouched"
  release_mutex
}

test_state_milestone_is_project_wide() {
  proj mpw; wt a feat/a; WA="$W"
  st_rc "$WA" set milestone alpha
  assert_eq 0 "$ST_RC" "WA's set milestone exits 0"
  assert_contains "$P/.studio/STATE.md" '^milestone: alpha$' "it writes main's milestone"
  assert_missing "$WA/.studio/STATE.md" "and never auto-creates WA's pointer"
  assert_eq alpha "$(st "$WA" get milestone)" "WA reads alpha"
  assert_eq alpha "$(st "$P" get milestone)" "P reads alpha"
  ( cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" init ) >/dev/null
  assert_eq alpha "$(cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" get milestone)" "STUDIO_STORY reads alpha"
  assert_not_contains "$P/.studio/stories/S1.md" '^milestone:' "a new story file has no milestone line"
  ( cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" set milestone beta ) >/dev/null
  assert_contains "$P/.studio/STATE.md" '^milestone: beta$' "STUDIO_STORY's set milestone writes main"
  assert_not_contains "$P/.studio/stories/S1.md" '^milestone:' "and leaves the story file without one"
  st "$WA" show > "$TMP/show.out"
  assert_contains "$TMP/show.out" '^milestone: beta$' "show in WA prints main's milestone"
  ( cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" show ) > "$TMP/show.out"
  assert_contains "$TMP/show.out" '^milestone: beta$' "show under STUDIO_STORY prints main's milestone"
  wt b feat/b; WB="$W"; mkdir -p "$WB/.studio"
  printf '# Studio State\n\nstage: plan\nspec: docs/t.md\nplan: -\ntask: -\nbranch: -\nmilestone: prototype\n\n## Ledger\n\n' > "$WB/.studio/STATE.md"
  assert_eq beta "$(st "$WB" get milestone)" "a #39 local pointer's milestone line is ignored by get"
  st "$WB" show > "$TMP/show.out"
  assert_contains "$TMP/show.out" '^milestone: beta$' "and replaced in show"
  assert_eq 1 "$(grep -c '^milestone:' "$TMP/show.out")" "show prints one milestone line"
  assert_eq milestone "$(after_line "$TMP/show.out" branch | sed 's/:.*//')" "after branch:"
}

test_state_milestone_without_main() {
  _M="$TMP/nomain"; rm -rf "$_M"; mkdir -p "$_M"
  ( cd "$_M" && git init -q -b main && g commit -q --allow-empty -m i && git worktree add -q -b run/x "$_M-rw" ) >/dev/null 2>&1
  st "$_M-rw" init --local >/dev/null
  assert_eq prototype "$(st "$_M-rw" get milestone)" "no main pointer: prototype"
  st_rc "$_M-rw" set milestone alpha
  assert_eq 1 "$ST_RC" "set milestone exits 1"; assert_contains "$TMP/st.err" "no main pointer — run studio-state init in" "names init"
  _t0=$(date +%s)
  st "$_M-rw" set stage brainstorm >/dev/null; st "$_M-rw" ledger x >/dev/null; st "$_M-rw" reset >/dev/null
  [ $(( $(date +%s) - _t0 )) -lt 3 ] && _pass "local writes never wait" || _fail "local writes never wait"; TESTS_RUN=$((TESTS_RUN + 1))
  assert_missing "$_M/.studio" "no <root>/.studio is created (f3-N3)"
}

test_state_every_write_holds_mutex() {
  proj ewh; wt a feat/a; WA="$W"; st "$WA" set stage brainstorm >/dev/null; hold_mutex
  ( cd "$P" && sh "$STATE_BIN" set stage brainstorm ) > /dev/null 2> "$TMP/e1" & _a=$!
  ( cd "$WA" && sh "$STATE_BIN" set spec docs/s.md ) > /dev/null 2> "$TMP/e2" & _b=$!
  ( cd "$WA" && sh "$STATE_BIN" ledger x ) > /dev/null 2> "$TMP/e3" & _c=$!
  ( cd "$WA" && sh "$STATE_BIN" set milestone alpha ) > /dev/null 2> "$TMP/e4" & _d=$!
  _t0=$(date +%s)
  ( cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" init && STUDIO_STORY=S1 sh "$STATE_BIN" set task 1/2 ) >/dev/null 2>&1
  st "$P" get stage >/dev/null; st "$WA" show >/dev/null
  [ $(( $(date +%s) - _t0 )) -lt 3 ] && _pass "STUDIO_STORY writes and reads do not wait" || _fail "STUDIO_STORY writes and reads do not wait"
  TESTS_RUN=$((TESTS_RUN + 1))
  for _j in "$_a:1" "$_b:2" "$_c:3" "$_d:4"; do
    _s=0; wait "${_j%%:*}" || _s=$?
    assert_eq 1 "$_s" "write ${_j#*:} exits 1 after the timeout"
    assert_contains "$TMP/e${_j#*:}" "state.mutex is busy (pid $HOLD_PID)" "write ${_j#*:} names the holder"
  done
  release_mutex
  # f3-N8: a pending hand-off and a busy mutex never fail a read.
  proj ewp; plan_in_p; st "$P" set stage execute >/dev/null; wt e feat/e; WE="$W"
  printf -- '- 2026-10-05 handing\tspec=docs/s.md\tplan=docs/p.md\tbranch=feat/e\tpath=%s\n' "$WE" >> "$P/.studio/STATE.md"
  _s="$(sum "$P/.studio/STATE.md")"; hold_mutex
  ( cd "$P" && sh "$STATE_BIN" get stage ) > "$TMP/p1.out" 2> "$TMP/p1.err" & _a=$!
  ( cd "$P" && sh "$STATE_BIN" show ) > "$TMP/p2.out" 2> "$TMP/p2.err" & _b=$!
  for _j in "$_a:1" "$_b:2"; do
    _s2=0; wait "${_j%%:*}" || _s2=$?
    assert_eq 0 "$_s2" "read ${_j#*:} exits 0 after the wait"
    assert_eq "studio-state: a hand-off to $WE is pending and $P/.studio/state.mutex is busy (pid $HOLD_PID) — showing unhealed state" \
      "$(cat "$TMP/p${_j#*:}.err")" "read ${_j#*:} says it shows unhealed state"
  done
  assert_eq execute "$(cat "$TMP/p1.out")" "get stage prints the unhealed stage"
  assert_contains "$TMP/p2.out" '^stage: execute$' "show prints the unhealed pointer"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "nothing is healed"
  assert_missing "$WE/.studio/STATE.md" "nor a target written"
  release_mutex
}

_reaped_set() { dead_mutex; st "$P" set stage brainstorm >/dev/null; }
test_state_dead_holder_reaped_fast() {
  proj dhr
  secs_min2 _reaped_set
  [ "$SECS" -lt 2 ] && _pass "a dead holder's link is reaped in under 2 s" || _fail "a dead holder's link is reaped in under 2 s (${SECS}s)"
  TESTS_RUN=$((TESTS_RUN + 1))
  assert_eq brainstorm "$(st "$P" get stage)" "the write lands"
  assert_missing "$P/.studio/state.mutex" "and leaves no link"
}

test_state_mutex_reap_race() {
  proj reap; _r=1
  while [ "$_r" -le 20 ]; do
    dead_mutex; _i=1; _pids=""
    while [ "$_i" -le 6 ]; do ( cd "$P" && sh "$STATE_BIN" ledger "L$_i-$_r" ) >/dev/null 2>&1 & _pids="$_pids $!"; _i=$((_i + 1)); done
    for _q in $_pids; do wait "$_q"; done
    _r=$((_r + 1))
  done
  assert_eq 120 "$(grep -c '^- [0-9-]* L[0-9]*-[0-9]*$' "$P/.studio/STATE.md")" "all 120 lines land"
  assert_eq 120 "$(grep '^- [0-9-]* L' "$P/.studio/STATE.md" | sort -u | wc -l | tr -d ' ')" "each exactly once"
  assert_missing "$P/.studio/state.mutex.reap" "no reap directory is left"
}

test_state_agent_worktree_isolated() {
  proj awi; plan_in_p; st "$P" set stage execute >/dev/null
  wt a feat/a; WA="$W"; st "$WA" set stage brainstorm >/dev/null
  _A="$P/.claude/worktrees/agent-abc"
  git -C "$P" worktree add -q -b agent-abc "$_A" >/dev/null 2>&1
  _s="$(sum "$P/.studio/STATE.md")"; _sa="$(sum "$WA/.studio/STATE.md")"
  assert_eq idle "$(st "$_A" get stage)" "the agent worktree reads idle, not P's execute"
  assert_eq - "$(st "$_A" get spec)" "and none of P's story"
  st "$_A" set stage brainstorm >/dev/null
  assert_file "$_A/.studio/STATE.md" "its first write auto-creates its pointer"
  assert_eq "$_s" "$(sum "$P/.studio/STATE.md")" "P's pointer is unchanged"
  assert_eq "$_sa" "$(sum "$WA/.studio/STATE.md")" "WA's pointer is unchanged"
  st "$P" stories > "$TMP/awi.tsv"
  assert_eq 1 "$(grep -c "^$_A$(printf '\t')" "$TMP/awi.tsv")" "stories lists the agent worktree's story"
  _rc=0; git -C "$P" worktree remove "$_A" >/dev/null 2>&1 || _rc=$?
  assert_eq 0 "$_rc" "git worktree remove succeeds without --force"
  assert_missing "$_A/.studio/STATE.md" "and the pointer is gone"
  st "$P" stories > "$TMP/awi.tsv"
  assert_eq 0 "$(grep -c "^$_A$(printf '\t')" "$TMP/awi.tsv")" "and stories no longer lists it"
}

test_state_legacy_pointer_resolves() {
  proj leg
  printf '# Studio State\n\nstage: plan\nspec: -\nplan: -\ntask: 8/8\nlast_playtest: docs/x.md\nmilestone: prototype\n\n## Ledger\n\n' > "$P/.studio/STATE.md"
  assert_eq plan "$(st "$P" get stage)" "a legacy main pointer resolves"
  st "$P" show > "$TMP/show.out"
  assert_eq "milestone: prototype" "$(after_line "$TMP/show.out" task)" "show prints the milestone after task: (no branch: line)"
  assert_eq 1 "$(grep -c '^milestone:' "$TMP/show.out")" "once"
  st_rc "$P" set branch feat/x
  assert_eq 0 "$ST_RC" "set branch on a legacy pointer exits 0"
  assert_eq "branch: feat/x" "$(after_line "$P/.studio/STATE.md" task)" "branch: is inserted after task:"
  st "$P" show > "$TMP/show.out"
  assert_eq "milestone: prototype" "$(after_line "$TMP/show.out" branch)" "then show prints the milestone after branch:"
  st "$P" set milestone alpha >/dev/null
  wt b feat/b; WB="$W"; mkdir -p "$WB/.studio"
  printf '# Studio State\n\nstage: idle\nspec: -\nplan: -\ntask: -\nbranch: -\nmilestone: prototype\n\n## Ledger\n\n' > "$WB/.studio/STATE.md"
  assert_eq alpha "$(st "$WB" get milestone)" "a #39 local pointer reads main's milestone"
  assert_eq idle "$(st "$WB" get stage)" "and its own stage"
  st_rc "$WB" set stage brainstorm
  assert_eq 0 "$ST_RC" "and accepts writes"
  assert_contains "$WB/.studio/STATE.md" '^stage: brainstorm$' "into its own file"
}

# exclusive-scan: test_state_story_writes_unchanged in (c) asserts STUDIO_STORY calls take at most 2 s while the mutex is held; failed under load (audit)
# exclusive-scan: test_state_milestone_without_main in (a) asserts local writes take at most 3 s
# exclusive-scan: test_state_every_write_holds_mutex in (a) asserts STUDIO_STORY writes take at most 3 s while the mutex is held
# exclusive-scan: test_state_dead_holder_reaped_fast in (a) asserts a dead holder is reaped inside a 2 s ceiling
# exclusive-scan: test_state_init_local_is_auto_create in (b) two init --local calls must both be waiting on the mutex when the 1 s sleep ends
TESTS_EXCLUSIVE="test_state_story_writes_unchanged test_state_milestone_without_main test_state_every_write_holds_mutex test_state_dead_holder_reaped_fast test_state_init_local_is_auto_create"
run_tests test_state_main_checkout_unchanged test_state_two_worktrees_independent \
  test_state_pointerless_reads_idle test_state_no_main_pointer_exits_1 \
  test_state_worktree_write_leaves_main_untouched test_state_new_story_seeds_idle \
  test_state_ledger_auto_creates test_state_auto_create_race test_state_parallel_local_writes_keep_both \
  test_state_exclude_newline_repair test_state_reset_pointerless_noop test_state_init_local_is_auto_create \
  test_state_init_in_linked_worktree test_state_tracked_pointer_refused test_state_story_writes_unchanged \
  test_state_milestone_is_project_wide test_state_milestone_without_main test_state_every_write_holds_mutex \
  test_state_dead_holder_reaped_fast test_state_mutex_reap_race test_state_agent_worktree_isolated \
  test_state_legacy_pointer_resolves
