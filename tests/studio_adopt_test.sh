#!/bin/sh
# Suite for studios/game-dev/bin/studio-adopt (#35): inspect, seed and sync
# against fixture git repos. Offline; no sessions; a temp HOME.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
ADOPT="$REPO_ROOT/studios/game-dev/bin/studio-adopt"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
unset STUDIO_RUN STUDIO_RUN_DIR STUDIO_STORY STUDIO_DOCS_REV STUDIO_GATE_HELD

ORIG=docs/superpowers/plans/2026-09-01-demo.md
CONV=docs/game-dev/plans/2026-10-04-S1.md
WS=.superpowers/sdd/2026-09-01-demo

# adopt_repo NAME TASKS DONE — $P: a clone of bare $TMP/NAME.git on main with
# an original plan ($ORIG, TASKS tasks) and its converted plan ($CONV); branch
# S1-b off main with DONE task commits (S1-T<n>.txt), checked out in worktree
# $W, pushed; SDD workspace $W/$WS for $ORIG with one claim per done task in
# SDD's format (short shas); studio state for S1 (spec $ORIG, plan $CONV,
# task 0/TASKS, branch S1-b, stage execute) and $P's ledger lines `source` and
# `adopted`. Sets P, W, BASE (main's tip) and C1..C<DONE> (full shas).
adopt_repo() {
  _n="$2"; _d="$3"; _t="$TMP/tpl-$_n-$_d"
  # The fixture is built once per (TASKS, DONE) into a template, then copied
  # per test: the build costs seconds, a copy costs milliseconds.
  [ -d "$_t" ] || build_adopt_tpl "tpl-$_n-$_d" "$_n" "$_d"
  P="$TMP/$1"; W="$TMP/$1-wt"
  rm -rf "$P" "$W" "$TMP/$1.git"
  cp -R "$_t/p" "$P"; cp -R "$_t/wt" "$W"; cp -R "$_t/origin.git" "$TMP/$1.git"
  ( cd "$P" && git remote set-url origin "$TMP/$1.git" \
      && printf '%s/.git\n' "$W" > .git/worktrees/wt/gitdir && printf 'gitdir: %s/.git/worktrees/wt\n' "$P" > "$W/.git" ) >/dev/null 2>&1 \
    || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "adopt_repo $1: copy failed"; }
  BASE="$(git -C "$P" rev-parse main)"
  i=1; while [ "$i" -le "$_d" ]; do eval "C$i=\$(cat \"\$_t/c$i\")"; i=$((i + 1)); done
}
build_adopt_tpl() {
  _bt="$TMP/$1"; mkdir -p "$_bt"; P="$_bt/p"; W="$_bt/wt"; _n="$2"; _d="$3"
  git init -q --bare "$_bt/origin.git"
  ( set -e; git init -q -b main "$P"; cd "$P"
    git remote add origin "$_bt/origin.git"
    mkdir -p "$(dirname "$ORIG")" "$(dirname "$CONV")"
    { printf '# Demo plan\n\n'; i=1
      while [ "$i" -le "$_n" ]; do printf '### Task %s: step %s\n\nFiles: src/s%s.txt\n\n' "$i" "$i" "$i"; i=$((i + 1)); done; } > "$ORIG"
    { printf '# S1 plan\n\nStory: S1\nSource: %s\nStatus: Draft (awaiting approval)\n\n## Global Constraints\n\n- none\n\n## Decisions\n\n- none\n\n## Acceptance criteria\n\n1. works\n\n' "$ORIG"
      i=1; while [ "$i" -le "$_n" ]; do printf '### Task %s: step %s\n\nSpec: %s:L3-4\nReview: final\n\n' "$i" "$i" "$ORIG"; i=$((i + 1)); done
      printf '## Backlog\n'; } > "$CONV"
    git add -A; git commit -q -m plans; git push -q origin main; git remote set-head origin main
    sh "$STATE_BIN" init
    STUDIO_STORY=S1; export STUDIO_STORY; sh "$STATE_BIN" init
    sh "$STATE_BIN" set spec "$ORIG"; sh "$STATE_BIN" set plan "$CONV"; sh "$STATE_BIN" set task "0/$_n"
    sh "$STATE_BIN" ledger "source $ORIG spec -"; sh "$STATE_BIN" ledger "adopted $ORIG -> $CONV"
    git worktree add -q -b S1-b "$W" main; cd "$W"
    mkdir -p "$WS"; printf '%s\n' "$ORIG" > "$WS/plan-path"; printf '*\n' > .superpowers/sdd/.gitignore
    printf '# SDD ledger — plan: %s\n' "$ORIG" > "$WS/progress.md"
    i=1; while [ "$i" -le "$_d" ]; do
      _a="$(git rev-parse --short HEAD)"
      printf 'T%s\n' "$i" > "S1-T$i.txt"; git add "S1-T$i.txt"; git commit -q -m "feat: step $i"
      printf 'Task %s: complete (commits %s..%s, review clean)\n' "$i" "$_a" "$(git rev-parse --short HEAD)" >> "$WS/progress.md"
      git rev-parse HEAD > "$_bt/c$i"; i=$((i + 1))
    done
    git push -q origin S1-b
    sh "$STATE_BIN" set branch S1-b; sh "$STATE_BIN" set stage execute ) >/dev/null 2>&1 \
    || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "adopt_repo $1: setup failed"; }
}
# adopt DIR ARGS — studio-adopt ARGS in DIR: AD_STATUS, $TMP/ad.out, $TMP/ad.err.
adopt() { _ad="$1"; shift; AD_STATUS=0; ( cd "$_ad" && sh "$ADOPT" "$@" ) > "$TMP/ad.out" 2> "$TMP/ad.err" || AD_STATUS=$?; }
# wt_commit MSG FILE — one commit in $W touching FILE; prints nothing.
wt_commit() { ( cd "$W" && printf '%s\n' "$1" >> "$2" && git add "$2" && git commit -q -m "$1" ) >/dev/null 2>&1; }
s7() { printf '%.7s' "$1"; }
# inspect_s1 [ARGS] — the standard inspect of the fixture story, from $P.
inspect_s1() { adopt "$P" inspect S1 --branch S1-b --plan "$ORIG" "$@"; }
# set_claims LINES… — rewrite the fixture workspace's progress.md.
set_claims() { { printf '# SDD ledger — plan: %s\n' "$ORIG"; for _l in "$@"; do printf '%s\n' "$_l"; done; } > "$W/$WS/progress.md"; }

test_adopt_help_and_usage() {
  adopt "$TMP" --help
  assert_eq 0 "$AD_STATUS" "--help exits 0"
  assert_contains "$TMP/ad.out" "inspect <id> --branch" "help names inspect"
  assert_contains "$TMP/ad.out" "seed" "help names seed"
  assert_contains "$TMP/ad.out" "sync" "help names sync"
  assert_contains "$TMP/ad.out" "Exit: 0" "help gives the exit codes"
  assert_contains "$TMP/ad.out" "superpowers 6.4.1" "help pins the superpowers version"
  assert_eq 3 "$(grep -c 'Example:' "$TMP/ad.out")" "one Example per verb"
  adopt "$TMP"; assert_eq 2 "$AD_STATUS" "no args: usage"
  adopt "$TMP" frobnicate S1; assert_eq 2 "$AD_STATUS" "unknown verb: usage"
  adopt "$TMP" inspect a/b --branch x --plan y; assert_eq 2 "$AD_STATUS" "bad id: usage"
  adopt "$TMP" inspect S1 --plan "$ORIG"; assert_eq 2 "$AD_STATUS" "missing --branch: usage"
}

test_adopt_inspect_clean_chain() {
  adopt_repo cc 6 3; inspect_s1
  assert_eq 0 "$AD_STATUS" "clean chain exits 0"
  assert_contains "$TMP/ad.out" "^base: $BASE$" "base is the fork point"
  assert_contains "$TMP/ad.out" "^T1 complete $BASE\.\.$C1$" "T1 range"
  assert_contains "$TMP/ad.out" "^T3 complete $C2\.\.$C3$" "T3 range"
  assert_contains "$TMP/ad.out" "^k: 3/6$" "k/N"
  assert_contains "$TMP/ad.out" "^workspace: $W/$WS (3 claims)$" "workspace line"
  assert_not_contains "$TMP/ad.out" "in progress" "no in-progress line"
}

test_adopt_inspect_from_any_checkout() {
  adopt_repo ac 6 3; inspect_s1; cp "$TMP/ad.out" "$TMP/ac.p"
  adopt "$W" inspect S1 --branch S1-b --plan "$ORIG"
  assert_eq 0 "$AD_STATUS" "from the worktree: exit 0"
  assert_eq "$(cat "$TMP/ac.p")" "$(cat "$TMP/ad.out")" "same stdout from either checkout"
}

test_adopt_inspect_not_started() {
  adopt_repo ns 6 3
  adopt "$P" inspect S1 --branch S9-b --plan "$ORIG"
  assert_eq 0 "$AD_STATUS" "not started exits 0"
  assert_contains "$TMP/ad.out" "^branch: S9-b (not started)$" "branch line"
  assert_contains "$TMP/ad.out" "^k: 0/6$" "k is 0"
}

test_adopt_inspect_no_workspace() {
  adopt_repo nw1 6 3; rm -rf "$W/.superpowers"; inspect_s1
  assert_eq 1 "$AD_STATUS" "work but no workspace: exit 1"
  assert_eq "work on S1-b past $(s7 "$BASE") but no SDD ledger for $ORIG in any worktree — restore it, or write one in SDD's format, and inspect again" "$(cat "$TMP/ad.err")" "exact L148 message"
  adopt_repo nw 6 0; rm -rf "$W/.superpowers"; inspect_s1
  assert_eq 0 "$AD_STATUS" "no work, no workspace: clean"
  assert_contains "$TMP/ad.out" "^k: 0/6$" "k is 0"
  assert_contains "$TMP/ad.out" "^workspace: none$" "workspace none"
}

test_adopt_main_merged_between_tasks() {
  adopt_repo mm 6 2
  ( cd "$P" && printf 'm2\n' > m2.txt && git add m2.txt && git commit -q -m m2 && git push -q origin main ) >/dev/null 2>&1
  ( cd "$W" && git fetch -q origin && git merge -q --no-edit origin/main ) >/dev/null 2>&1
  _m7="$(git -C "$W" rev-parse --short HEAD)"
  ( cd "$W" && mkdir -p .studio/ledger && printf -- '- 2026-10-04 base origin/main\n' > .studio/ledger/S1.md \
    && git add .studio/ledger/S1.md && git commit -q -m "chore: ledger" ) >/dev/null 2>&1
  wt_commit T3 S1-T3.txt
  _t7="$(git -C "$W" rev-parse --short HEAD)"
  printf 'Task 3: complete (commits %s..%s, review clean)\n' "$_m7" "$_t7" >> "$W/$WS/progress.md"
  inspect_s1
  assert_eq 0 "$AD_STATUS" "merged main between tasks: exit 0"
  assert_contains "$TMP/ad.out" "^base: $BASE$" "base is the original fork point"
  assert_contains "$TMP/ad.out" "^k: 3/6$" "k is 3"
}

test_adopt_claim_tokens() {
  adopt_repo ct 6 3
  set_claims "Task 1: complete (commits 0cb5..$(s7 "$C1"), review clean)"
  inspect_s1
  assert_eq 1 "$AD_STATUS" "a 4-hex token is ignored: one token is an empty range"
  assert_contains "$TMP/ad.err" "empty range" "names the empty range"
  set_claims "Task 1: complete (commits deadbee faceted $(s7 "$BASE")..$(s7 "$C1"), review clean)"
  inspect_s1
  assert_eq 0 "$AD_STATUS" "an unresolvable word is skipped"
  assert_contains "$TMP/ad.out" "^T1 complete $BASE\.\.$C1$" "range from the resolvable tokens"
  set_claims "Task 1: complete (commits none, review clean)"
  inspect_s1
  assert_eq 1 "$AD_STATUS" "no token: exit 1"
  assert_contains "$TMP/ad.err" "commits none, review clean" "names the line"
}

test_adopt_claim_gaps_and_order() {
  adopt_repo cg 6 3
  _l1="Task 1: complete (commits $(s7 "$BASE")..$(s7 "$C1"), review clean)"
  _l2="Task 2: complete (commits $(s7 "$C1")..$(s7 "$C2"), review clean)"
  _l3="Task 3: complete (commits $(s7 "$C2")..$(s7 "$C3"), review clean)"
  set_claims "$_l1" "$_l3"; inspect_s1
  assert_eq 1 "$AD_STATUS" "gap: exit 1"
  assert_contains "$TMP/ad.err" "T2" "names T2"
  set_claims "$_l2" "$_l1" "$_l3"; inspect_s1
  assert_eq 0 "$AD_STATUS" "out of order: exit 0"
  assert_contains "$TMP/ad.out" "^k: 3/6$" "merged by number"
  set_claims "$_l1" "Task 7: complete (commits $(s7 "$C2")..$(s7 "$C3"), review clean)"; inspect_s1
  assert_eq 1 "$AD_STATUS" "Task 7 on a 6-task plan: exit 1"
  assert_contains "$TMP/ad.err" "Task 7" "names Task 7"
}

test_adopt_short_sha_lines_parse() {
  adopt_repo ss 6 3; inspect_s1; cp "$TMP/ad.out" "$TMP/ss.short"
  set_claims "Task 1: complete (commits $BASE..$C1, review clean)" "Task 2: complete (commits $C1..$C2, review clean)" "Task 3: complete (commits $C2..$C3, review clean)"
  inspect_s1
  assert_eq 0 "$AD_STATUS" "40-hex claims: exit 0"
  assert_eq "$(cat "$TMP/ss.short")" "$(cat "$TMP/ad.out")" "7-hex and 40-hex claims give the same full-sha lines"
  assert_contains "$TMP/ad.out" "^T2 complete $C1\.\.$C2$" "full shas"
}

test_adopt_part_done_filter() {
  adopt_repo pd 6 3
  ( cd "$W" && mkdir -p .studio/ledger && printf 'x\n' > .studio/note && git add .studio/note && git commit -q -m "chore(studio): note" ) >/dev/null 2>&1
  ( cd "$W" && printf 'p\n' >> "$ORIG" && printf 'p\n' >> "$CONV" && git add "$ORIG" "$CONV" && git commit -q -m "docs(S1): plan at run docs" ) >/dev/null 2>&1
  ( cd "$W" && printf 'p\n' >> "$CONV" && printf -- '- 2026-10-04 x\n' >> .studio/ledger/S1.md && git add "$CONV" .studio/ledger/S1.md && git commit -q -m "docs(S1): approved plan" ) >/dev/null 2>&1
  ( cd "$P" && printf 'm\n' > m.txt && git add m.txt && git commit -q -m m && git push -q origin main ) >/dev/null 2>&1
  ( cd "$W" && git fetch -q origin && git merge -q --no-edit origin/main ) >/dev/null 2>&1
  ( cd "$W" && mkdir -p src && printf 'x\n' > src/x && git add src/x && git commit -q -m "fix(final): x" ) >/dev/null 2>&1
  wt_commit "wip a" wa.txt; _wa="$(git -C "$W" rev-parse HEAD)"
  wt_commit "wip b" wb.txt; _wb="$(git -C "$W" rev-parse HEAD)"
  inspect_s1
  assert_eq 0 "$AD_STATUS" "part-done: exit 0"
  assert_contains "$TMP/ad.out" "^T4 in progress: $_wa\.\.$_wb$" "only the two work commits count"
}

test_adopt_post_task_commits() {
  adopt_repo pt 3 3; wt_commit "extra" ex.txt; _e="$(git -C "$W" rev-parse HEAD)"
  inspect_s1
  assert_eq 0 "$AD_STATUS" "post-task: exit 0"
  assert_contains "$TMP/ad.out" "^post-task commits: $_e\.\.$_e$" "post-task line"
}

test_adopt_explicit_base() {
  adopt_repo eb 6 3
  inspect_s1 --base "$C1"
  assert_eq 1 "$AD_STATUS" "base after T1's start: mismatch"
  assert_contains "$TMP/ad.err" "T1" "names T1"
  inspect_s1 --base "$BASE"
  assert_eq 0 "$AD_STATUS" "explicit fork base: clean"
  inspect_s1 --base nope
  assert_eq 1 "$AD_STATUS" "unknown base: exit 1"
  assert_contains "$TMP/ad.err" "nope" "names the token"
}

test_adopt_check_done_on_branch_ledger() {
  adopt_repo cd 6 3
  # AC13: the check unit commits `check done <a>..<b>` in the story branch's
  # ledger; the start checkout's ledger has no such line.
  wt_commit "fix: before check" fa.txt; _fa="$(git -C "$W" rev-parse HEAD)"
  wt_commit "fix: after check" fb.txt; _fb="$(git -C "$W" rev-parse HEAD)"
  wt_commit "wip real" wr.txt; _wr="$(git -C "$W" rev-parse HEAD)"
  inspect_s1
  assert_contains "$TMP/ad.out" "^T4 in progress: $_fa\.\.$_wr$" "before the ledger line: all three count"
  ( cd "$W" && mkdir -p .studio/ledger && printf -- '- 2026-10-04 check done %s..%s\n' "$C3" "$_fb" >> .studio/ledger/S1.md \
    && git add .studio/ledger/S1.md && git commit -q -m "chore(studio): check done" ) >/dev/null 2>&1
  inspect_s1
  assert_eq 0 "$AD_STATUS" "check done on the branch: exit 0"
  assert_contains "$TMP/ad.out" "^T4 in progress: $_wr\.\.$_wr$" "commits inside the branch ledger's check range are not part-done"
}

test_adopt_workspaces_status() {
  adopt_repo wsx 6 3
  mkdir -p "$W/.superpowers/sdd/zz-other"; printf 'docs/other.md\n' > "$W/.superpowers/sdd/zz-other/plan-path"
  sed '$d' "$ADOPT" > "$TMP/adopt.lib"
  ( cd "$P" && . "$TMP/adopt.lib" && TMPD="$TMP/wsd" && workspaces "$ORIG" > "$TMP/ws.out"; echo "$?" > "$TMP/ws.st" ) 2>/dev/null
  assert_eq 0 "$(cat "$TMP/ws.st")" "a matching workspace printed: status 0 though the last scanned names another plan"
  assert_eq 1 "$(wc -l < "$TMP/ws.out" | tr -d ' ')" "only the matching workspace is printed"
  ( cd "$P" && . "$TMP/adopt.lib" && TMPD="$TMP/wsd" && workspaces "docs/none.md" > "$TMP/ws.out"; echo "$?" > "$TMP/ws.st" ) 2>/dev/null
  assert_eq 0 "$(cat "$TMP/ws.st")" "no match: empty output, status 0"
  assert_eq 0 "$(wc -c < "$TMP/ws.out" | tr -d ' ')" "no match prints nothing"
}

test_adopt_claim_stops_at_close_paren() {
  adopt_repo cp 6 3
  set_claims "Task 1: complete (commits $(s7 "$BASE")..$(s7 "$C1"), review clean) fixed $(s7 "$C3")"
  inspect_s1
  assert_eq 0 "$AD_STATUS" "a hex token after the closing paren: exit 0"
  assert_contains "$TMP/ad.out" "^T1 complete $BASE\.\.$C1$" "only the tokens inside the parentheses count"
}

test_adopt_rewritten_history_message() {
  adopt_repo rw 6 3
  ( cd "$W" && git commit -q --amend -m "feat: step 3 reworded" ) >/dev/null 2>&1
  inspect_s1
  assert_eq 1 "$AD_STATUS" "a claim whose end left the branch: exit 1"
  assert_contains "$TMP/ad.err" "history of S1-b was rewritten after T3 — re-adopt: studio-adopt seed S1 --reset" "AC10b wording"
}

run_tests test_adopt_help_and_usage test_adopt_inspect_clean_chain test_adopt_inspect_from_any_checkout \
  test_adopt_inspect_not_started test_adopt_inspect_no_workspace test_adopt_main_merged_between_tasks \
  test_adopt_claim_tokens test_adopt_claim_gaps_and_order test_adopt_short_sha_lines_parse \
  test_adopt_part_done_filter test_adopt_post_task_commits test_adopt_explicit_base \
  test_adopt_check_done_on_branch_ledger test_adopt_workspaces_status test_adopt_claim_stops_at_close_paren \
  test_adopt_rewritten_history_message
