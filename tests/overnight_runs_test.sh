#!/bin/sh
# overnight-runs.sh (#39): the live runs of one project, selectors, records,
# the run-worktree finder, the plan Files: parser and the symlink mutex.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
LIB="$REPO_ROOT/studios/game-dev/bin/overnight-runs.sh"
mk_tmp overnight_runs; trap '{ for _d in $DUMMIES; do kill "$_d"; done; wait; } 2>/dev/null; rm_tmp "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
DUMMIES=""
TAB="$(printf '\t')"
. "$LIB"
. "$REPO_ROOT/studios/game-dev/bin/overnight-tools.sh"   # tools_run: runs_settle's gh call goes through it
# live_dummy — a live pid whose args name studio-overnight (DUMMY).
live_dummy() { sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; DUMMIES="$DUMMIES $DUMMY"; }
dead_pid() { sh -c ':' & wait $!; DEAD=$!; }
# plock ROOT SLUG PID STARTED [START] — a per-run lock and its run dir with a manifest.
plock() {
  _d="$1/.studio/reports/overnight-$2-20261004-21000$5"; mkdir -p "$_d" "$1/.studio/runs/$2"
  printf '# Run: %s\n\nMode: integration\nTarget: integration/%s\n' "$2" "$2" > "$_d/manifest.md"
  printf 'pid=%s\nrun=%s\nstarted=%s\n%s' "$3" "$_d" "$4" "${6:+start=$6
}" > "$1/.studio/runs/$2/lock"
  PL_DIR="$_d"
}

test_runs_live_per_run_and_old_lock() {
  R="$TMP/live"; mkdir -p "$R/.studio"
  live_dummy; plock "$R" beta "$DUMMY" 2026-10-04T21:00:05Z 1
  live_dummy; plock "$R" alpha "$DUMMY" 2026-10-04T21:00:01Z 2 "$R/wt-alpha"
  live_dummy; _od="$R/.studio/reports/overnight-old-20261003-210000"; mkdir -p "$_od"
  printf '# Run: old\n' > "$_od/manifest.md"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$DUMMY" "$_od" > "$R/.studio/overnight.lock"
  runs_live "$R" > "$TMP/out"
  assert_eq "old alpha beta" "$(cut -f2 "$TMP/out" | tr '\n' ' ' | sed 's/ $//')" "oldest first, the old-style lock included"
  assert_eq "manifest manifest manifest" "$(cut -f3 "$TMP/out" | tr '\n' ' ' | sed 's/ $//')" "an old lock whose run dir has manifest.md is a manifest run"
  assert_eq "$R/wt-alpha" "$(awk -F'\t' '$2 == "alpha" { print $6 }' "$TMP/out")" "start dir from start="
  assert_eq "$R/.studio/overnight.lock" "$(awk -F'\t' '$2 == "old" { print $7 }' "$TMP/out")" "the lock path"
}
test_runs_live_skips_dead_and_single() {
  R="$TMP/dead"; mkdir -p "$R/.studio"
  dead_pid; plock "$R" gone "$DEAD" 2026-10-04T21:00:00Z 1
  live_dummy; _sd="$R/.studio/reports/overnight-20261004-210000"; mkdir -p "$_sd"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T22:00:00Z\n' "$DUMMY" "$_sd" > "$R/.studio/overnight.lock"
  runs_live "$R" > "$TMP/out"
  assert_eq 1 "$(grep -c . "$TMP/out")" "a dead lock is not live"
  assert_eq "-${TAB}single" "$(cut -f2,3 "$TMP/out")" "a single-plan run: slug -, kind single"
}
test_runs_match_slug_or_basename() {
  R="$TMP/match"; mkdir -p "$R/.studio"; live_dummy; plock "$R" alpha "$DUMMY" 2026-10-04T21:00:00Z 1
  assert_eq alpha "$(runs_live "$R" | runs_match alpha | cut -f2)" "by slug"
  assert_eq alpha "$(runs_live "$R" | runs_match "$(basename "$PL_DIR")" | cut -f2)" "by run dir basename"
  assert_eq "" "$(runs_live "$R" | runs_match beta)" "no match prints nothing"
}
test_runs_stop_of() {
  assert_eq /r/.studio/runs/a/stop "$(runs_stop_of /r/.studio/runs/a/lock)" "per-run"
  assert_eq /r/.studio/overnight.stop "$(runs_stop_of /r/.studio/overnight.lock)" "old-style and single-plan (D5)"
}
test_runs_start_dir_lock_then_registry() {
  R="$TMP/sd"; mkdir -p "$R/.studio" "$HOME/.claude-gamedev/runs"
  live_dummy; plock "$R" a "$DUMMY" 2026-10-04T21:00:00Z 1 "$R/wt-a"
  assert_eq "$R/wt-a" "$(runs_start_dir "$R/.studio/runs/a/lock")" "lock start= wins"
  plock "$R" b "$DUMMY" 2026-10-04T21:00:00Z 2
  printf 'root=%s\nstart=%s\nrun=%s\npid=%s\n' "$R" "$R/wt-b" "$PL_DIR" "$DUMMY" > "$HOME/.claude-gamedev/runs/$(basename "$PL_DIR")-$DUMMY"
  assert_eq "$R/wt-b" "$(runs_start_dir "$R/.studio/runs/b/lock")" "else the registry's start= for the same run="
  plock "$R" c "$DUMMY" 2026-10-04T21:00:00Z 3
  assert_eq "" "$(runs_start_dir "$R/.studio/runs/c/lock")" "else empty (the caller keeps its own)"
}
test_runs_records() {
  R="$TMP/rec"; mkdir -p "$R/.studio/runs/open" "$R/.studio/runs/done" "$R/.studio/runs/lockonly"
  : > "$R/.studio/runs/open/landed.tsv"; : > "$R/.studio/runs/done/landed.tsv"; : > "$R/.studio/runs/done/done"
  : > "$R/.studio/runs/lockonly/lock"
  runs_record_open "$R" open; assert_eq 0 $? "landed.tsv, no done: open"
  runs_record_open "$R" done; assert_eq 1 $? "done is not open"
  runs_record_done "$R" done; assert_eq 0 $? "done"
  runs_record_open "$R" lockonly; assert_eq 1 $? "a lock alone is no record (D4)"
}
# settle_repo DIR — DIR a git repo with two commits: C1, then its child C2.
settle_repo() {
  git init -q "$1" && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m c1 \
    && C1="$(git -C "$1" rev-parse HEAD)" \
    && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m c2 \
    && C2="$(git -C "$1" rev-parse HEAD)"
}
# runs_settle: a hand-made record and a PATH-first gh stub. The landings (C1, C2) are in the
# final PR's head (C2), and the stub's headRefOid is that head.
test_runs_settle() {
  R="$TMP/settle"; D="$R/.studio/runs/s"; settle_repo "$R"; mkdir -p "$D" "$TMP/ghbin"
  printf 'A\tb\nB\tb\n' > "$D/rows.tsv"; printf 'A\tt\t%s\t1\n' "$C1" > "$D/landed.tsv"
  printf '%s https://gh.test/pr/7 red\n' "$C2" > "$D/final"
  cat > "$TMP/ghbin/gh" <<'STUB'
#!/bin/sh
printf '{"state":"%s","headRefOid":"%s"}\n' "${GH_STATE:-MERGED}" "$GH_HEAD"
STUB
  chmod +x "$TMP/ghbin/gh"
  GH_HEAD="$C2"; export GH_HEAD
  _op="$PATH"; PATH="$TMP/ghbin:$PATH"
  runs_settle "$R" s >/dev/null; assert_eq 1 $? "a story not landed: no settle"
  printf 'B\tt\t%s\t2\n' "$C2" >> "$D/landed.tsv"
  GH_STATE=OPEN; export GH_STATE
  runs_settle "$R" s >/dev/null 2>"$TMP/se.err"; assert_eq 1 $? "an OPEN PR: no settle"
  assert_eq "" "$(cat "$TMP/se.err")" "an OPEN PR says nothing"
  GH_STATE=MERGED
  assert_eq "run s: final PR https://gh.test/pr/7 is merged — start marks the record done" "$(runs_settle "$R" s --dry-run)" "dry-run line"
  assert_missing "$D/done" "dry-run writes nothing"
  assert_eq "run s: final PR https://gh.test/pr/7 is merged — record marked done" "$(runs_settle "$R" s)" "the settle line"
  assert_file "$D/done" "done written"
  runs_settle "$R" s >/dev/null; assert_eq 1 $? "a done record is not open"
  printf '#!/bin/sh\nexit 1\n' > "$TMP/ghbin/gh"
  rm -f "$D/done"; runs_settle "$R" s >/dev/null 2>"$TMP/se.err"; assert_eq 1 $? "a gh failure: no settle"
  assert_eq "run s: cannot read the state of final PR https://gh.test/pr/7 — record left open" "$(cat "$TMP/se.err")" "and it says so on stderr"
  assert_missing "$D/done" "a gh failure writes nothing"
  rm -f "$D/done"; : > "$D/final"
  runs_settle "$R" s >/dev/null; assert_eq 1 $? "no final URL: no settle"
  unset GH_STATE GH_HEAD; PATH="$_op"
}
# runs_settle trusts the merged PR only for the work it carries, and never for a live run:
# each case below leaves the record open, and the last (all guards met) settles it.
test_runs_settle_guards() {
  R="$TMP/sg"; D="$R/.studio/runs/g"; settle_repo "$R"; mkdir -p "$D" "$TMP/sgbin"
  printf 'A\tb\nB\tb\n' > "$D/rows.tsv"; printf 'A\tt\t%s\t1\nB\tt\t%s\t2\n' "$C1" "$C2" > "$D/landed.tsv"
  cat > "$TMP/sgbin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
printf '{"state":"MERGED","headRefOid":"%s"}\n' "$GH_HEAD"
STUB
  chmod +x "$TMP/sgbin/gh"
  GH_LOG="$TMP/sg.calls"; : > "$GH_LOG"; export GH_LOG GH_HEAD
  _op="$PATH"; PATH="$TMP/sgbin:$PATH"
  # A final step at C1 (A landed), merged by hand; then B landed at C2 and no new final step ran.
  printf '%s https://gh.test/pr/8 red\n' "$C1" > "$D/final"; GH_HEAD="$C1"
  runs_settle "$R" g >/dev/null 2>"$TMP/sg.err"; assert_eq 1 $? "a story landed after the final PR's head: no settle"
  assert_missing "$D/done" "the record stays open (B is not in the merged PR)"
  assert_eq "" "$(cat "$TMP/sg.err")" "silently"
  # The PR's head moved past RECORD/final's head.
  printf '%s https://gh.test/pr/8 red\n' "$C2" > "$D/final"; GH_HEAD="$C1"
  runs_settle "$R" g >/dev/null 2>"$TMP/sg.err"; assert_eq 1 $? "headRefOid is not RECORD/final's head: no settle"
  assert_missing "$D/done" "the record stays open"
  # A head that is no commit here.
  _rz="$(printf '%040d' 0)"
  printf '%s https://gh.test/pr/8 red\n' "$_rz" > "$D/final"; GH_HEAD="$_rz"
  runs_settle "$R" g >/dev/null 2>&1; assert_eq 1 $? "a missing object: no settle"
  assert_missing "$D/done" "the record stays open"
  # A live run of the slug: gh is not asked.
  printf '%s https://gh.test/pr/8 red\n' "$C2" > "$D/final"; GH_HEAD="$C2"
  live_dummy; printf 'pid=%s\nrun=%s\nstarted=2026-10-23T01:00:00Z\n' "$DUMMY" "$TMP/sg-run" > "$D/lock"
  : > "$GH_LOG"
  runs_settle "$R" g >/dev/null 2>&1; assert_eq 1 $? "a live run: no settle"
  assert_missing "$D/done" "the live run's record stays open"
  assert_eq "" "$(cat "$GH_LOG")" "and gh is not asked"
  rm -f "$D/lock"
  # A URL that is not https is never passed to gh.
  printf '%s --repo=x red\n' "$C2" > "$D/final"
  runs_settle "$R" g >/dev/null 2>"$TMP/sg.err"; assert_eq 1 $? "a URL that is not https: no settle"
  assert_eq "run g: cannot read the state of final PR --repo=x — record left open" "$(cat "$TMP/sg.err")" "it says so on stderr"
  assert_eq "" "$(cat "$GH_LOG")" "and gh is not asked"
  # Every guard met.
  printf '%s https://gh.test/pr/8 red\n' "$C2" > "$D/final"
  assert_eq "run g: final PR https://gh.test/pr/8 is merged — record marked done" "$(runs_settle "$R" g)" "all guards met: settled"
  assert_eq "pr view https://gh.test/pr/8 --json state,headRefOid" "$(cat "$GH_LOG")" "gh is asked for the state and the head"
  unset GH_LOG GH_HEAD; PATH="$_op"
}
# exclusive-scan: test_runs_settle_gh_capped out (d) the one-second cap only has to fire before a gh that sleeps ten seconds answers MERGED; a late cap still leaves the record open
# A gh that does not answer within the cap (STUDIO_OVERNIGHT_TOOLS_SECONDS, tools_run's) is a gh failure.
test_runs_settle_gh_capped() {
  R="$TMP/sgc"; D="$R/.studio/runs/c"; settle_repo "$R"; mkdir -p "$D" "$TMP/sgcbin"
  printf 'A\tb\n' > "$D/rows.tsv"; printf 'A\tt\t%s\t1\n' "$C2" > "$D/landed.tsv"
  printf '%s https://gh.test/pr/9 red\n' "$C2" > "$D/final"
  cat > "$TMP/sgcbin/gh" <<'STUB'
#!/bin/sh
i=0; while [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
printf '{"state":"MERGED","headRefOid":"%s"}\n' "$GH_HEAD"
STUB
  chmod +x "$TMP/sgcbin/gh"
  GH_HEAD="$C2"; STUDIO_OVERNIGHT_TOOLS_SECONDS=1; export GH_HEAD STUDIO_OVERNIGHT_TOOLS_SECONDS
  _op="$PATH"; PATH="$TMP/sgcbin:$PATH"
  runs_settle "$R" c >/dev/null 2>"$TMP/sgc.err"; assert_eq 1 $? "a gh past the cap: no settle"
  assert_eq "run c: cannot read the state of final PR https://gh.test/pr/9 — record left open" "$(cat "$TMP/sgc.err")" "it says so on stderr"
  assert_missing "$D/done" "the record stays open"
  unset GH_HEAD STUDIO_OVERNIGHT_TOOLS_SECONDS; PATH="$_op"
}
test_runs_rows_newest_report() {
  R="$TMP/rows"; mkdir -p "$R/.studio/reports/overnight-a-20261001-010101" "$R/.studio/reports/overnight-a-20261002-010101" \
    "$R/.studio/reports/overnight-a-b-20261003-010101" "$R/.studio/reports/overnight-a-detached-20261004-010101"
  for _d in "$R"/.studio/reports/*; do : > "$_d/rows.tsv"; done
  assert_eq "$R/.studio/reports/overnight-a-20261002-010101/rows.tsv" "$(runs_rows "$R" a)" "the newest of slug a only (D39)"
  assert_eq /x/rows.tsv "$(mkdir -p "$TMP/x"; runs_rows "$R" a /x)" "an explicit run dir wins"
}
test_runs_worktree_of() {
  R="$TMP/wt"; ( mkdir -p "$R" && cd "$R" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i \
      && git branch run/alpha && git worktree add -q .claude/worktrees/run-alpha run/alpha ) >/dev/null 2>&1
  assert_eq "$R/.claude/worktrees/run-alpha" "$(cd "$R" && runs_worktree_of run/alpha)" "the checkout holding run/alpha"
  assert_eq "$R" "$(cd "$R" && runs_worktree_of main)" "the main checkout counts"
  assert_eq "" "$(cd "$R" && runs_worktree_of run/beta)" "none"
}
test_runs_plan_files_studio_form() {
  printf '%s\n' '# P' '' '### Task 1: a' 'Files: `a.sh` (:10), `t/a_test.sh`' '' '### Task 2: b' \
    'Files: src/b.gd:L10-20, src/c.gd (new)' '' '## Backlog' '' '### Task 3: cut' 'Files: z.sh' > "$TMP/plan"
  assert_eq "src/b.gd src/c.gd" "$(runs_plan_files 1 < "$TMP/plan" | tr '\n' ' ' | sed 's/ $//')" "tasks after k=1 only; :lines and (notes) stripped; backlog ignored"
  assert_eq "a.sh src/b.gd src/c.gd t/a_test.sh" "$(runs_plan_files 0 < "$TMP/plan" | tr '\n' ' ' | sed 's/ $//')" "k=0: every task, sorted"
}
test_runs_plan_files_superpowers_form() {
  printf '%s\n' '### Task 1: x' '' '**Files:**' '- Create: `src/new.py`' '- Modify: `src/old.py:123-145`' \
    '- Test: `tests/test_x.py`' '' '- [ ] **Step 1: …**' '' '## Self-review' 'Files: no.sh' > "$TMP/plan2"
  assert_eq "src/new.py src/old.py tests/test_x.py" "$(runs_plan_files 0 < "$TMP/plan2" | tr '\n' ' ' | sed 's/ $//')" "bullets read; a ## line ends the task"
}
test_runs_plan_files_comma_line_list() {
  printf '%s\n' '### Task 1: a' 'Files: src/a.gd:10,20, src/b.gd' > "$TMP/plan3"
  _o="$(runs_plan_files 0 < "$TMP/plan3" | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "src/a.gd src/b.gd" "$_o" "a comma line list continues the path; 20 is not a file"
}
test_mx_take_drop_and_dead_owner() {
  M="$TMP/m.mutex"; live_dummy
  mx_take "$M" "$DUMMY"; assert_eq 0 $? "taken"
  assert_eq "$DUMMY" "$(readlink "$M")" "names its owner"
  mx_drop "$M" 1; assert_symlink "$M" "a drop by another pid leaves it"
  mx_drop "$M" "$DUMMY"; assert_missing "$M" "dropped by its owner"
  dead_pid; ln -s "$DEAD" "$M"
  mx_take "$M" "$DUMMY"; assert_eq 0 $? "a dead owner's mutex is removed and retaken"
  mx_drop "$M" "$DUMMY"
}
# A dead-pid link and 6 takers at once, 20 rounds: the reap must never let two
# takers hold the mutex together (#39 final review, known #1). Each holder
# marks itself in $H, logs how many marks it sees, and unmarks before mx_drop.
test_mutex_reap_race() {
  M="$TMP/race.mutex"; H="$TMP/race.holders"; RL="$TMP/race.log"; mkdir -p "$H"; : > "$RL"
  _taker='. "$1"; mx_take "$2" "$$" || { echo take-failed >> "$4"; exit 1; }
    mkdir "$3/$$"; ls "$3" | wc -l | tr -d " " >> "$4"; sleep 0.05
    ls "$3" | wc -l | tr -d " " >> "$4"; rmdir "$3/$$"; mx_drop "$2" "$$"'
  _r=0
  while [ "$_r" -lt 20 ]; do
    dead_pid; rm -f "$M"; ln -s "$DEAD" "$M"
    _k=0; _pids=""
    while [ "$_k" -lt 6 ]; do
      sh -c "$_taker" taker "$LIB" "$M" "$H" "$RL" & _pids="$_pids $!"; _k=$((_k + 1))
    done
    for _p in $_pids; do wait "$_p"; done
    _r=$((_r + 1))
  done
  assert_eq 240 "$(grep -c . "$RL")" "every taker took the mutex and logged twice (20 rounds x 6)"
  assert_eq 0 "$(grep -c take-failed "$RL")" "no taker timed out"
  assert_eq "" "$(grep -vx 1 "$RL" | sort | uniq -c | tr -s ' \n' '  ')" "never more than one holder at once"
  assert_missing "$M" "the last holder dropped it"
  assert_missing "$M.reap" "no reap lock is left behind"
}

# AC27 (f3-N2): a reap lock left by a reaper killed mid-reap (older than 5 s)
# is broken, so a dead holder's link is still reaped and the take succeeds.
test_mutex_stale_reap_lock_broken() {
  M="$TMP/stale.mutex"; rm -rf "$M" "$M.reap"
  sh -c 'exit 0' & _d=$!; wait "$_d"
  ln -s "$_d" "$M"; mkdir "$M.reap"
  touch -t "$(date -v-1M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-1 min' +%Y%m%d%H%M.%S)" "$M.reap"
  _t0=$(date +%s)
  if mx_take "$M" $$; then _ok=0; else _ok=1; fi
  assert_eq 0 "$_ok" "the take succeeds past a stale reap lock"
  assert_eq "$$" "$(readlink "$M")" "the mutex names the taker"
  assert_missing "$M.reap" "the stale reap lock is gone"
  [ $(( $(date +%s) - _t0 )) -lt 5 ] && _pass "no long wait" || _fail "no long wait"
  TESTS_RUN=$((TESTS_RUN + 1)); mx_drop "$M" $$
}

TESTS_REAL_CLOCK="test_mutex_reap_race"
# exclusive-scan: test_mutex_stale_reap_lock_broken in (a) asserts the take finishes inside a 5 s ceiling
TESTS_EXCLUSIVE="test_mutex_stale_reap_lock_broken"
run_tests test_runs_live_per_run_and_old_lock test_runs_live_skips_dead_and_single test_runs_match_slug_or_basename \
  test_runs_stop_of test_runs_start_dir_lock_then_registry test_runs_records test_runs_settle test_runs_settle_guards test_runs_settle_gh_capped test_runs_rows_newest_report \
  test_runs_worktree_of test_runs_plan_files_studio_form test_runs_plan_files_superpowers_form test_runs_plan_files_comma_line_list test_mx_take_drop_and_dead_owner \
  test_mutex_reap_race test_mutex_stale_reap_lock_broken
