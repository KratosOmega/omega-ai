#!/bin/sh
# #42 — the story-switch guard, --force and exit 4 (spec AC24-AC26).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/tests/state_fixtures.sh"

SWITCH_MSG='studio-state: this checkout is on story s (stage plan, task 0/3) — finish or reset it first, start the new story in its own worktree (EnterWorktree), or pass --force'
MOVED_MSG='studio-state: this checkout holds no story — docs/s.md moved to /w x on 2026-10-05; continue it there, start a new story with /game-dev:brainstorm, or pass --force'
T="$(printf '\t')"
HANDED_LINE="- 2026-10-05 handed${T}spec=docs/s.md${T}plan=docs/p.md${T}branch=feat/x${T}path=/w x"

# plan_in D — D brainstorms and plans docs/s.md, task 0/3.
plan_in() { for _a in "stage brainstorm" "spec docs/s.md" "stage plan" "plan docs/p.md" "task 0/3"; do
  st "$1" set $_a >/dev/null 2>&1; done; }
# pointer_of D — D's own stage pointer.
pointer_of() { printf '%s/.studio/STATE.md\n' "$1"; }
forced_count() { grep -c '^- [0-9-]* forced ' "$1"; }

# guard_case D LABEL — AC24's switch refusal and its allowed neighbours, on D's pointer.
guard_case() {
  _d="$1"; _l="$2"; _f="$(pointer_of "$_d")"; plan_in "$_d"; _s="$(sum "$_f")"
  st_rc "$_d" set spec docs/t.md
  assert_eq 4 "$ST_RC" "$_l: set spec over another spec at plan exits 4"
  assert_eq "$SWITCH_MSG" "$(cat "$TMP/st.err")" "$_l: with the switch message"
  st_rc "$_d" set stage brainstorm
  assert_eq 4 "$ST_RC" "$_l: set stage brainstorm at plan exits 4"
  assert_eq "$SWITCH_MSG" "$(cat "$TMP/st.err")" "$_l: with the switch message"
  assert_eq "$_s" "$(sum "$_f")" "$_l: the refusals write nothing"
  st_rc "$_d" set spec docs/s.md
  assert_eq 0 "$ST_RC" "$_l: set spec to the same spec exits 0"
  st_rc "$_d" set spec -
  assert_eq 0 "$ST_RC" "$_l: clearing spec at plan is not a switch"
  st "$_d" set spec docs/s.md >/dev/null 2>&1
  st "$_d" reset >/dev/null 2>&1; st "$_d" set stage brainstorm >/dev/null 2>&1; st "$_d" set spec docs/s.md >/dev/null 2>&1
  st_rc "$_d" set spec docs/t.md
  assert_eq 0 "$ST_RC" "$_l: at brainstorm, set spec over another spec exits 0"
  assert_contains "$TMP/st.err" 'docs/s\.md' "$_l: with a warning naming the old spec"
  assert_eq 1 "$(wc -l < "$TMP/st.err" | tr -d ' ')" "$_l: one warning line"
  assert_eq docs/t.md "$(st "$_d" get spec)" "$_l: and writes"
}

test_state_story_switch_guard() {
  proj sw; guard_case "$P" P
  wt a feat/a; guard_case "$W" WA
}

test_state_story_switch_exempt_in_run_worktree() {
  proj run; wt r feat/r; mkdir -p "$W/.studio"; touch "$W/.studio/run"; plan_in "$W"
  assert_eq plan "$(st "$W" get stage)" "the run worktree is at plan"
  st_rc "$W" set stage brainstorm
  assert_eq 0 "$ST_RC" "set stage brainstorm at plan exits 0 in a run worktree"
  st "$W" set stage plan >/dev/null 2>&1
  st_rc "$W" set spec docs/t.md
  assert_eq 0 "$ST_RC" "set spec over another spec at plan exits 0 in a run worktree"
  assert_eq docs/t.md "$(st "$W" get spec)" "and writes"
}

test_state_force_override() {
  proj frc; plan_in "$P"; _f="$P/.studio/STATE.md"
  st_rc "$P" set --force spec docs/t.md
  assert_eq 0 "$ST_RC" "set --force spec at plan exits 0"
  assert_eq docs/t.md "$(st "$P" get spec)" "and writes"
  assert_eq 1 "$(grep -c '^- [0-9-]* forced spec=docs/t\.md over docs/s\.md (stage plan)$' "$_f")" "one forced spec line"
  assert_eq 1 "$(forced_count "$_f")" "and no other forced line"
  ( cd "$P" && STUDIO_STATE_FORCE=1 sh "$STATE_BIN" set stage brainstorm ) >/dev/null 2>&1
  assert_eq brainstorm "$(st "$P" get stage)" "STUDIO_STATE_FORCE=1 overrides"
  assert_eq 1 "$(grep -c '^- [0-9-]* forced stage=brainstorm over docs/t\.md (stage plan)$' "$_f")" "one forced stage line"
  st_rc "$P" set --force task 0/3
  assert_eq 0 "$ST_RC" "set --force task at brainstorm exits 0"
  assert_eq 2 "$(forced_count "$_f")" "no forced line when nothing was refused"
  _s="$(sum "$_f")"
  st_rc "$P" set spec --force x
  assert_eq 1 "$ST_RC" "set spec --force x exits 1"
  assert_contains "$TMP/st.err" '^usage: studio-state' "with the usage text"
  st_rc "$P" set spec --force
  assert_eq 1 "$ST_RC" "set spec --force exits 1"
  assert_contains "$TMP/st.err" '^usage: studio-state' "with the usage text"
  st_rc "$P" get --force spec
  assert_eq 1 "$ST_RC" "get --force spec exits 1"
  assert_contains "$TMP/st.err" '^usage: studio-state' "with the usage text"
  assert_contains "$TMP/st.err" '4 refused: a story switch in this checkout, a story write after the story moved away, or a take/handoff onto another story or the wrong spec (--force overrides where stated)' "the usage text names exit 4"
  assert_eq "$_s" "$(sum "$_f")" "the usage errors write nothing"
}

# moved_writes D VERDICT LABEL — the four story writes AC24 guards after a move.
moved_writes() {
  _f="$(pointer_of "$1")"
  for _a in "stage plan" "stage execute" "plan docs/p.md" "task 0/3"; do
    _s="$(sum "$_f")"
    st_rc "$1" set $_a
    if [ "$2" = refuse ]; then
      assert_eq 4 "$ST_RC" "$3: set $_a exits 4"
      assert_eq "$MOVED_MSG" "$(cat "$TMP/st.err")" "$3: with the moved message"
      assert_eq "$_s" "$(sum "$_f")" "$3: and writes nothing"
    else
      assert_eq 0 "$ST_RC" "$3: set $_a exits 0"
    fi
  done
}

test_state_storyless_write_after_handed_line() {
  proj mv; _f="$P/.studio/STATE.md"
  printf '%s\n' "$HANDED_LINE" >> "$_f"
  moved_writes "$P" refuse "after a handed line"
  st_rc "$P" set task -
  assert_eq 0 "$ST_RC" "set task - exits 0"
  st_rc "$P" set branch -
  assert_eq 0 "$ST_RC" "set branch - exits 0"
  st "$P" set stage brainstorm >/dev/null 2>&1; st "$P" set spec docs/t.md >/dev/null 2>&1
  st "$P" reset >/dev/null 2>&1
  assert_contains "$_f" '^- [0-9-]* abandoned docs/t\.md$' "reset writes the abandoned line"
  moved_writes "$P" accept "after a newer abandoned line"
  st "$P" reset >/dev/null 2>&1
  printf '%s\n- 2026-10-05 restored docs/s.md from the handed line\n' "$HANDED_LINE" >> "$_f"
  moved_writes "$P" accept "after a newer restored line"
  assert_eq 0 "$(forced_count "$_f")" "no forced line anywhere"
}

run_tests test_state_story_switch_guard test_state_story_switch_exempt_in_run_worktree \
  test_state_force_override test_state_storyless_write_after_handed_line
