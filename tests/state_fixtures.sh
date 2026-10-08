# tests/state_fixtures.sh — sourced by tests/state_*_test.sh (#42); not a test file.
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
mk_tmp state_fixtures; trap 'rm_tmp "$TMP"' EXIT
g() { git -c user.name=t -c user.email=t@t "$@"; }
st() { _std="$1"; shift; ( cd "$_std" && sh "$STATE_BIN" "$@" ); }
st_rc() { _std="$1"; shift; ST_RC=0; ( cd "$_std" && sh "$STATE_BIN" "$@" ) > "$TMP/st.out" 2> "$TMP/st.err" || ST_RC=$?; }
sum() { cksum < "$1" 2>/dev/null || echo none; }
# proj NAME — main checkout P on main: studio-state init, docs/s.md, docs/t.md and a
# three-task docs/p.md, all committed.
proj() {
  P="$TMP/$1"; rm -rf "$P" "$P"-*; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && sh "$STATE_BIN" init >/dev/null \
    && printf '# S\n' > docs/s.md && printf '# T\n' > docs/t.md \
    && printf '# Plan\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md \
    && git add -A && g commit -qm init ) >/dev/null 2>&1
}
# wt NAME BRANCH — linked worktree $P-NAME on a new BRANCH; sets W.
wt() { W="$P-$1"; git -C "$P" worktree add -q -b "$2" "$W" >/dev/null 2>&1; }
# plan_in_p [SPEC] — P brainstorms and plans SPEC (default docs/s.md), task 0/3.
plan_in_p() { for _a in "stage brainstorm" "spec ${1:-docs/s.md}" "stage plan" "plan docs/p.md" "task 0/3"; do
  st "$P" set $_a >/dev/null 2>&1; done; }
hold_mutex() { sleep 120 & HOLD_PID=$!; ln -s "$HOLD_PID" "$P/.studio/state.mutex"; }
release_mutex() { kill "$HOLD_PID" 2>/dev/null; wait "$HOLD_PID" 2>/dev/null; rm -f "$P/.studio/state.mutex"; }
dead_mutex() { sh -c 'exit 0' & _dm=$!; wait "$_dm"; ln -sfn "$_dm" "$P/.studio/state.mutex"; }
# wait_all PID… — wait for every PID, whatever its status.
wait_all() { for _wa in "$@"; do wait "$_wa" 2>/dev/null || true; done; }
