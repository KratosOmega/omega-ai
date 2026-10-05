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
  _n="$2"; _d="$3"; _t="${ADOPT_TPL:-$TMP/tpl-$_n-$_d}"
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
  assert_contains "$TMP/ad.err" "Task 1" "names Task 1"
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
  sed -e '$d' -e "s|^SELF_DIR=.*|SELF_DIR=\"$(dirname "$ADOPT")\"|" "$ADOPT" > "$TMP/adopt.lib"
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
  assert_contains "$TMP/ad.err" "Task 3: the claim" "a stale claim is a plain mismatch naming the claim"
  assert_not_contains "$TMP/ad.err" "seed S1 --reset" "and does not advise the command that fails again"
}

# ledger_texts — $W's story ledger as texts (date stripped), in order.
ledger_texts() { sed -n 's/^- [0-9-]* //p' "$W/.studio/ledger/S1.md"; }
seed_commits() { git -C "$W" log --format=%s | grep -c '^chore(studio): ledger (adopt)$'; }

test_adopt_seed_writes_truth() {
  adopt_repo sd 6 3
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "seed exits 0"
  assert_eq "seeded: 6 lines" "$(cat "$TMP/ad.out")" "seeded count"
  printf '%s\n' "source $ORIG spec -" "adopted $ORIG -> $CONV" "adopt-base $BASE" \
    "T1 complete $BASE..$C1" "T2 complete $C1..$C2" "T3 complete $C2..$C3" > "$TMP/sd.want"
  ledger_texts > "$TMP/sd.got"
  assert_eq "$(cat "$TMP/sd.want")" "$(cat "$TMP/sd.got")" "truth lines, in order"
  assert_eq "chore(studio): ledger (adopt)" "$(git -C "$W" log -1 --format=%s)" "one adopt commit"
  ( cd "$W" && STUDIO_STORY=S1 sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq "3/6" "$( cd "$W" && STUDIO_STORY=S1 sh "$STATE_BIN" get task )" "rebuild gives 3/6"
}

test_adopt_seed_second_run_noop() {
  adopt_repo sn 6 3
  adopt "$W" seed S1; _h="$(git -C "$W" rev-parse HEAD)"; cp "$W/.studio/ledger/S1.md" "$TMP/sn.led"
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "second seed exits 0"
  assert_eq "already seeded" "$(cat "$TMP/ad.out")" "says already seeded"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no new commit"
  assert_eq "$(cat "$TMP/sn.led")" "$(cat "$W/.studio/ledger/S1.md")" "ledger unchanged"
}

test_adopt_seed_check_requested() {
  adopt_repo sc 6 3
  ( cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" ledger "check requested" ) >/dev/null 2>&1
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "seed exits 0"
  assert_eq "check requested" "$(ledger_texts | tail -n 1)" "check requested is the last line"
}

test_adopt_seed_refuses_changed_title() {
  adopt_repo st 6 3
  sed "s/^### Task 2: step 2$/### Task 2: other/" "$P/$CONV" > "$TMP/st.conv" && cp "$TMP/st.conv" "$P/$CONV"
  _h="$(git -C "$W" rev-parse HEAD)"
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "changed title: exit 1"
  assert_contains "$TMP/ad.err" "Task 2" "names Task 2"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no commit"
  assert_missing "$W/.studio/ledger/S1.md" "ledger not written"
}

test_adopt_seed_wrong_branch() {
  adopt_repo sw 6 3
  adopt "$P" seed S1
  assert_eq 1 "$AD_STATUS" "wrong branch: exit 1"
  assert_contains "$TMP/ad.err" "S1-b" "names the story branch"
}

test_adopt_seed_carries_rulings() {
  adopt_repo sr 6 3
  { printf 'Task 2: parked — slow path — Ruling: fine for now\n'
    printf 'Task 3: minor (deferred): rename foo\n'
    printf 'Task 1: Ruling: kept X — cheaper\n'
    printf 'Task 5: Ruling: later\n'
    printf 'Task 2: fix round 1 — Ruling: nope\n'; } >> "$W/$WS/progress.md"
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "seed exits 0"
  ledger_texts > "$TMP/sr.got"
  assert_contains "$TMP/sr.got" "^minor (deferred) T2: slow path — Ruling: fine for now (standard mode)$" "parked"
  assert_contains "$TMP/sr.got" "^minor (deferred) T3: rename foo (standard mode)$" "minor deferred"
  assert_contains "$TMP/sr.got" "^T1 Ruling: kept X — cheaper$" "ruling"
  assert_not_contains "$TMP/sr.got" "T5" "n above k is not carried"
  assert_not_contains "$TMP/sr.got" "nope" "fix round lines are not carried"
}

test_adopt_seed_base_conflict() {
  adopt_repo sb 6 3
  adopt "$W" seed S1
  adopt "$W" seed S1 --base "$C1"
  assert_eq 1 "$AD_STATUS" "a different --base: exit 1"
  assert_contains "$TMP/ad.err" "adopt-base" "names adopt-base"
  adopt "$W" seed S1 --base "$BASE"
  assert_eq 0 "$AD_STATUS" "the same --base: exit 0"
}

test_adopt_seed_reset_after_rebase() {
  adopt_repo rb 6 3
  adopt "$W" seed S1
  ( cd "$P" && printf 'm\n' > m.txt && git add m.txt && git commit -q -m m && git push -q origin main ) >/dev/null 2>&1
  _new="$(git -C "$P" rev-parse main)"
  ( cd "$W" && git fetch -q origin && git rebase -q --onto "$_new" "$BASE" ) >/dev/null 2>&1
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "old claims no longer chain: exit 1"
  assert_contains "$TMP/ad.err" "the claim" "seed names the stale claim"
  assert_not_contains "$TMP/ad.err" "seed S1 --reset" "seed's advice is not the --reset that fails again"
  _l="$(git -C "$W" rev-list --reverse "$_new..HEAD" | head -n 3)"
  _n1="$(printf '%s\n' "$_l" | sed -n 1p)"; _n2="$(printf '%s\n' "$_l" | sed -n 2p)"; _n3="$(printf '%s\n' "$_l" | sed -n 3p)"
  set_claims "Task 1: complete (commits $(s7 "$_new")..$(s7 "$_n1"), review clean)" \
    "Task 2: complete (commits $(s7 "$_n1")..$(s7 "$_n2"), review clean)" \
    "Task 3: complete (commits $(s7 "$_n2")..$(s7 "$_n3"), review clean)"
  _head="$(git -C "$W" rev-parse HEAD)"
  adopt "$W" seed S1 --reset
  assert_eq 0 "$AD_STATUS" "reset seed exits 0"
  ledger_texts > "$TMP/rb.got"
  _r="$(grep -n "^adopt reset $_head$" "$TMP/rb.got" | tail -n 1 | cut -d: -f1)"
  [ -n "$_r" ] && assert_eq 1 1 "adopt reset line present" || assert_eq "reset line" "none" "adopt reset line present"
  tail -n +"$((${_r:-0} + 1))" "$TMP/rb.got" > "$TMP/rb.after"
  printf '%s\n' "source $ORIG spec -" "adopted $ORIG -> $CONV" "adopt-base $_new" \
    "T1 complete $_new..$_n1" "T2 complete $_n1..$_n2" "T3 complete $_n2..$_n3" > "$TMP/rb.want"
  assert_eq "$(cat "$TMP/rb.want")" "$(cat "$TMP/rb.after")" "fresh truth after the reset line"
  ( cd "$W" && STUDIO_STORY=S1 sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq "3/6" "$( cd "$W" && STUDIO_STORY=S1 sh "$STATE_BIN" get task )" "rebuild gives 3/6"
  ( cd "$W" && awk '/^- [0-9-]+ adopt reset /{ n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }' .studio/ledger/S1.md ) > "$TMP/rb.truth"
  assert_not_contains "$TMP/rb.truth" "$C1" "no pre-reset T line in the truth region"
}

test_adopt_seed_no_workspace_refused() {
  adopt_repo nws 6 3; rm -rf "$W/.superpowers"; _h="$(git -C "$W" rev-parse HEAD)"
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "work but no workspace: seed exits 1"
  assert_contains "$TMP/ad.err" "no SDD ledger for $ORIG" "inspect's message"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no commit"
  assert_missing "$W/.studio/ledger/S1.md" "ledger not written"
}

test_adopt_seed_existing_range_differs() {
  adopt_repo sx 6 3; adopt "$W" seed S1
  sed "s/^\(- [0-9-]* \)T2 complete .*/\1T2 complete $C1..$C3/" "$W/.studio/ledger/S1.md" > "$TMP/sx.led" && cp "$TMP/sx.led" "$W/.studio/ledger/S1.md"
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "an existing T line with another range: exit 1"
  assert_contains "$TMP/ad.err" "T2" "names T2"
}

test_adopt_seed_no_adopted_line() {
  adopt_repo sa 6 3; printf '# Ledger — S1\n\n' > "$P/.studio/ledger/S1.md"
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "no adopted line: exit 1"
  assert_contains "$TMP/ad.err" "no adopted line" "says so"
}

test_adopt_seed_failed_commit_restores() {
  adopt_repo sf 6 3; _h="$(git -C "$W" rev-parse HEAD)"
  _hd="$TMP/sf-hooks"; mkdir -p "$_hd"
  printf '#!/bin/sh\necho hook-says-no >&2\nexit 1\n' > "$_hd/pre-commit"; chmod +x "$_hd/pre-commit"
  git -C "$W" config core.hooksPath "$_hd"
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "failed commit: exit 1"
  assert_contains "$TMP/ad.err" "ledger restored" "says restored"
  assert_contains "$TMP/ad.err" "hook-says-no" "shows git's stderr"
  assert_missing "$W/.studio/ledger/S1.md" "ledger removed"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no commit"
}

# sync_repo NAME [N DONE] — adopt_repo, then seed.
sync_repo() {
  _sn="${2:-6}"; _sd="${3:-3}"; _st="$TMP/stpl-$_sn-$_sd"
  if [ ! -d "$_st" ]; then
    # The seeded fixture is built once per (TASKS, DONE) and copied per test.
    adopt_repo "stplsrc-$_sn-$_sd" "$_sn" "$_sd"; adopt "$W" seed S1
    mkdir -p "$_st"; cp -R "$P" "$_st/p"; cp -R "$W" "$_st/wt"; cp -R "$TMP/stplsrc-$_sn-$_sd.git" "$_st/origin.git"
    cp "$TMP/tpl-$_sn-$_sd"/c[0-9]* "$_st/"
  fi
  ADOPT_TPL="$_st" adopt_repo "$1" "$_sn" "$_sd"
}
# claim_t4 — commit T4 in $W and append its SDD claim; sets C4.
claim_t4() {
  wt_commit T4 S1-T4.txt; C4="$(git -C "$W" rev-parse HEAD)"
  printf 'Task 4: complete (commits %s..%s, review clean)\n' "$(s7 "$C3")" "$(s7 "$C4")" >> "$W/$WS/progress.md"
}
# set_truth N RANGE — replace $W's ledger T<N> line; del_truth N; add_truth TEXT.
set_truth() { sed "s/^\(- [0-9-]* \)T$1 complete .*/\1T$1 complete $2/" "$W/.studio/ledger/S1.md" > "$TMP/tr.led" && cp "$TMP/tr.led" "$W/.studio/ledger/S1.md"; }
del_truth() { grep -v "^- [0-9-]* T$1 complete " "$W/.studio/ledger/S1.md" > "$TMP/tr.led"; cp "$TMP/tr.led" "$W/.studio/ledger/S1.md"; }
add_truth() { printf -- '- 2026-10-04 %s\n' "$1" >> "$W/.studio/ledger/S1.md"; }
view_want() { # PLAN — the identity line and the three truth tasks
  printf '# SDD ledger — plan: %s\n' "$1"
  printf 'Task 1: complete (commits %s..%s, review clean)\n' "$BASE" "$C1"
  printf 'Task 2: complete (commits %s..%s, review clean)\n' "$C1" "$C2"
  printf 'Task 3: complete (commits %s..%s, review clean)\n' "$C2" "$C3"
}

test_sync_already_in_sync() {
  sync_repo sy1
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "sync exits 0"
  assert_contains "$TMP/ad.out" "^already in sync$" "in sync"
  assert_contains "$TMP/ad.out" "^k: 3/6 -> 3/6$" "k line"
  view_want "$ORIG" > "$TMP/sy.want"
  assert_eq "$(cat "$TMP/sy.want")" "$(cat "$W/$WS/progress.md")" "original view"
  _cd=".superpowers/sdd/2026-10-04-S1"
  assert_eq "$CONV" "$(cat "$W/$_cd/plan-path")" "converted view marker"
  view_want "$CONV" > "$TMP/sy.want"
  assert_eq "$(cat "$TMP/sy.want")" "$(cat "$W/$_cd/progress.md")" "converted view"
  assert_eq '*' "$(cat "$W/.superpowers/sdd/.gitignore")" "gitignore"
}

test_sync_accepts_claims() {
  sync_repo sy2; claim_t4
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "sync exits 0"
  assert_contains "$TMP/ad.out" "^accepted: T4 $C3\.\.$C4$" "accepted line"
  assert_contains "$TMP/ad.out" "^k: 3/6 -> 4/6$" "k line"
  assert_eq "chore(studio): ledger (sync)" "$(git -C "$W" log -1 --format=%s)" "sync commit"
  assert_contains "$W/.studio/ledger/S1.md" "T4 complete $C3\.\.$C4$" "T4 in the ledger"
  assert_eq "$(git -C "$W" rev-parse HEAD)" "$(git -C "$W" rev-parse origin/S1-b)" "pushed"
  assert_contains "$TMP/ad.out" "^pushed S1-b$" "pushed line"
  assert_eq "4/6" "$( cd "$W" && STUDIO_STORY=S1 sh "$STATE_BIN" get task )" "task view"
  _h="$(git -C "$W" rev-parse HEAD)"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "second sync exits 0"
  assert_contains "$TMP/ad.out" "^already in sync$" "second run: in sync"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no new commit"
}

test_sync_all_or_nothing() {
  sync_repo sy3; adopt "$W" sync S1; claim_t4
  _x="$(git -C "$W" commit-tree -m x -p "$C4" "$C4^{tree}")"
  printf 'Task 5: complete (commits %s..%s, review clean)\n' "$(s7 "$C4")" "$(s7 "$_x")" >> "$W/$WS/progress.md"
  cp "$W/.studio/ledger/S1.md" "$TMP/sy.led"; cp "$W/$WS/progress.md" "$TMP/sy.view"
  _h="$(git -C "$W" rev-parse HEAD)"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "a bad new claim: exit 1"
  assert_eq "$(cat "$TMP/sy.led")" "$(cat "$W/.studio/ledger/S1.md")" "ledger unchanged"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no commit"
  assert_eq "$(cat "$TMP/sy.view")" "$(cat "$W/$WS/progress.md")" "view unchanged"
}

test_sync_claim_end_differs() {
  sync_repo sy4
  set_claims "Task 1: complete (commits $(s7 "$BASE")..$(s7 "$C1"), review clean)" \
    "Task 2: complete (commits $(s7 "$C1")..$(s7 "$C3"), review clean)" \
    "Task 3: complete (commits $(s7 "$C2")..$(s7 "$C3"), review clean)"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "claim end differs: exit 1"
  assert_contains "$TMP/ad.err" "Task 2" "names Task 2"
}

test_sync_truth_mismatches() {
  sync_repo m1; set_truth 2 "$C1..$C1"; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "empty range: exit 1"; assert_contains "$TMP/ad.err" "empty range" "empty range"
  assert_contains "$TMP/ad.err" "$(s7 "$C1")" "names the sha"
  sync_repo m2; del_truth 2; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "gap: exit 1"; assert_contains "$TMP/ad.err" "T2" "names T2"
  sync_repo m3; add_truth "T1 complete $BASE..$C2"; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "two ranges: exit 1"; assert_contains "$TMP/ad.err" "T1" "names T1"
  sync_repo m4; set_truth 3 "$C3..$C2"; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "reversed: exit 1"; assert_contains "$TMP/ad.err" "not an ancestor" "not an ancestor"
  assert_contains "$TMP/ad.err" "$(s7 "$C3")" "names the sha"
  sync_repo m5
  ( cd "$W" && mkdir -p .studio && printf x > .studio/x.txt && git add -f .studio/x.txt && git commit -q -m studio-only ) >/dev/null 2>&1
  _s="$(git -C "$W" rev-parse HEAD)"; add_truth "T4 complete $C3..$_s"; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" ".studio-only range: exit 1"; assert_contains "$TMP/ad.err" "no commit outside .studio/" "studio-only"
  assert_contains "$TMP/ad.err" "$(s7 "$_s")" "names the sha"
}

test_sync_ambiguous_short_sha() {
  sync_repo am
  awk 'BEGIN { for (i = 1; i <= 1000; i++) printf "commit refs/heads/noise\ncommitter t <t@t> 1700000000 +0000\ndata <<EOF\nn%d\nEOF\n\n", i }' | git -C "$W" fast-import --quiet
  tok="$(git -C "$W" rev-list noise | cut -c1-4 | sort | uniq -d | head -n 1)"
  [ -n "$tok" ] || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "no ambiguous 4-char prefix in the noise branch"; return 0; }
  set_truth 1 "$tok..$C1"; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "ambiguous token: exit 1"
  assert_contains "$TMP/ad.err" "$tok" "names the token"
}

test_sync_rewrite_message() {
  sync_repo rw1
  ( cd "$P" && printf 'm\n' > m.txt && git add m.txt && git commit -q -m m && git push -q origin main ) >/dev/null 2>&1
  ( cd "$W" && git fetch -q origin && git rebase -q --onto "$(git -C "$P" rev-parse main)" "$BASE" && git push -qf origin S1-b ) >/dev/null 2>&1
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "rewritten: exit 1"
  assert_eq "history of S1-b was rewritten after its adopt base — re-adopt: studio-adopt seed S1 --reset" "$(cat "$TMP/ad.err")" "after the adopt base"
  sync_repo rw2
  _alt="$(git -C "$W" commit-tree -m alt -p "$C2" "$C2^{tree}")"
  ( cd "$W" && git rebase -q --onto "$_alt" "$C2" && git push -qf origin S1-b ) >/dev/null 2>&1
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "T3 rewritten: exit 1"
  assert_eq "history of S1-b was rewritten after T2 — re-adopt: studio-adopt seed S1 --reset" "$(cat "$TMP/ad.err")" "after T2"
}

test_sync_views_keep_other_lines() {
  sync_repo kp
  set_claims "Task 1: complete (commits $(s7 "$BASE")..$(s7 "$C1"), review clean)" \
    "Task 2: complete (commits $(s7 "$C1")..$(s7 "$C2"), review clean)" \
    "Task 3: complete (commits $(s7 "$C2")..$(s7 "$C3"), review clean)" \
    "Task 2: fix round 1/5 (1 addressed, 0 open; commits a..b)" \
    "Task 4: parked — x — Ruling: y" "notes line"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "sync exits 0"
  { view_want "$ORIG"; printf '%s\n' "Task 2: fix round 1/5 (1 addressed, 0 open; commits a..b)" "Task 4: parked — x — Ruling: y" "notes line"; } > "$TMP/kp.want"
  assert_eq "$(cat "$TMP/kp.want")" "$(cat "$W/$WS/progress.md")" "truth lines, then the kept lines in order"
  assert_contains "$TMP/ad.out" "^kept: 3 lines in $W/$WS$" "kept report"
}

test_sync_carries_rulings_once() {
  sync_repo cr
  { printf 'Task 2: parked — slow path — Ruling: fine for now\n'; printf 'Task 1: Ruling: kept X — cheaper\n'; printf 'Task 5: Ruling: later\n'; } >> "$W/$WS/progress.md"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "sync exits 0"
  assert_contains "$W/.studio/ledger/S1.md" "minor (deferred) T2: slow path — Ruling: fine for now (standard mode)$" "parked carried"
  assert_contains "$W/.studio/ledger/S1.md" "T1 Ruling: kept X — cheaper$" "ruling carried"
  assert_not_contains "$W/.studio/ledger/S1.md" "T5" "n above k not carried"
  assert_eq "chore(studio): ledger (sync)" "$(git -C "$W" log -1 --format=%s)" "one commit"
  _h="$(git -C "$W" rev-parse HEAD)"
  adopt "$W" sync S1
  assert_contains "$TMP/ad.out" "^already in sync$" "second run adds none"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no new commit"
}

test_sync_landed_note() {
  sync_repo ln
  mkdir -p "$P/docs/runs" "$P/.studio/runs/demo"
  printf '# Run: demo\nTarget: integration/demo\n' > "$P/docs/runs/demo.md"
  printf 'docs/runs/demo.md\n' > "$P/.studio/run"
  printf 'S1\tintegration/demo\tabc1234\t1\n' > "$P/.studio/runs/demo/landed.tsv"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "sync exits 0"
  assert_eq "Landed: integration/demo at abc1234 — continue dependent stories from there" "$(tail -n 1 "$W/$WS/progress.md")" "original ends with the note"
  assert_not_contains "$W/.superpowers/sdd/2026-10-04-S1/progress.md" "^Landed:" "converted view has none"
  rm "$P/.studio/runs/demo/landed.tsv"
  adopt "$W" sync S1
  assert_not_contains "$W/$WS/progress.md" "^Landed:" "no record, no note"
}

# run_wt NAME BRANCH — a run worktree $TMP/NAME on BRANCH whose .studio/run
# names a manifest `# Run: alpha` listing S1.
run_wt() {
  git -C "$P" worktree add -q -b "$2" "$TMP/$1" main >/dev/null 2>&1
  mkdir -p "$TMP/$1/docs/runs" "$TMP/$1/.studio"
  printf '# Run: alpha\nTarget: integration/demo\n\n| Story | Branch |\n|---|---|\n| S1 | S1-b |\n' > "$TMP/$1/docs/runs/alpha.md"
  printf 'docs/runs/alpha.md\n' > "$TMP/$1/.studio/run"
}

test_adopt_start_checkout_from_run_worktree() {
  sync_repo sc
  run_wt run-alpha run/alpha
  mkdir -p "$P/.studio/runs/alpha"; printf 'S1\tintegration/demo\tabc1234\t1\n' > "$P/.studio/runs/alpha/landed.tsv"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "sync exits 0"
  assert_eq "Landed: integration/demo at abc1234 — continue dependent stories from there" "$(tail -n 1 "$W/$WS/progress.md")" "manifest found in the run worktree"
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "seed exits 0 with the run worktree resolved"
}

test_adopt_start_checkout_two_listings_refuse() {
  sync_repo s2
  run_wt run-a2 run/alpha; run_wt run-b2 run/beta
  adopt "$W" seed S1
  assert_eq 1 "$AD_STATUS" "two listings: exit 1"
  assert_contains "$TMP/ad.err" "story S1 is listed by two run worktrees:" "message names the story"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "sync too: exit 1"
  assert_contains "$TMP/ad.err" "story S1 is listed by two run worktrees:" "sync message"
}

test_adopt_start_checkout_none_falls_back() {
  sync_repo s3
  mkdir -p "$P/docs/runs" "$P/.studio/runs/demo"
  printf '# Run: demo\nTarget: integration/demo\n' > "$P/docs/runs/demo.md"
  printf 'docs/runs/demo.md\n' > "$P/.studio/run"
  printf 'S1\tintegration/demo\tabc1234\t1\n' > "$P/.studio/runs/demo/landed.tsv"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "sync exits 0"
  assert_eq "Landed: integration/demo at abc1234 — continue dependent stories from there" "$(tail -n 1 "$W/$WS/progress.md")" "state root manifest used"
}

# per_run_lock STATE — a live per-run lock .studio/runs/alpha/lock holding S1.
per_run_lock() {
  mkdir -p "$TMP/run2/stories" "$P/.studio/runs/alpha"
  printf 'S1\n' > "$TMP/run2/rows.tsv"; printf '%s\n' "$1" > "$TMP/run2/stories/S1"
  sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 &
  DUMMY=$!
  printf 'pid=%s\nrun=%s\nstarted=x\n' "$DUMMY" "$TMP/run2" > "$P/.studio/runs/alpha/lock"
}

test_adopt_live_run_check_per_run_lock() {
  sync_repo pl
  per_run_lock sync-repair; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "sync-repair: exit 1"
  assert_eq "story S1 is in a live run — /hold it or wait for it to end" "$(cat "$TMP/ad.err")" "message"
  printf 'running\n' > "$TMP/run2/stories/S1"; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "running: exit 1"
  STUDIO_RUN="$TMP/run2/manifest.md"; STUDIO_STORY=S1; STUDIO_RUN_DIR="$TMP/run2"; export STUDIO_RUN STUDIO_STORY STUDIO_RUN_DIR
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "own unit: exit 0"
  unset STUDIO_RUN STUDIO_STORY STUDIO_RUN_DIR
  printf 'queued\n' > "$TMP/run2/stories/S1"; adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "queued: exit 0"
  live_done
}

test_adopt_part_done_ignores_sync() {
  adopt_repo ps 6 3
  wt_commit "wip a" wa.txt; _wa="$(git -C "$W" rev-parse HEAD)"
  inspect_s1
  assert_contains "$TMP/ad.out" "^T4 in progress: $_wa\.\.$_wa$" "baseline"
  wt_commit "chore(sync): merge origin/main into S1-b" ws1.txt
  wt_commit "fix(sync): resolve x" ws2.txt
  inspect_s1
  assert_contains "$TMP/ad.out" "^T4 in progress: $_wa\.\.$_wa$" "sync commits do not count"
}

# live_lock STATE… — a live dummy run holding S1 in state STATE.
live_lock() {
  mkdir -p "$TMP/run1/stories"; printf '# Run: x\n' > "$TMP/run1/manifest.md"; printf '%s\n' "$1" > "$TMP/run1/stories/S1"
  sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 &
  DUMMY=$!
  printf 'pid=%s\nrun=%s\nstarted=x\n' "$DUMMY" "$TMP/run1" > "$P/.studio/overnight.lock"
}
live_done() { pkill -P "$DUMMY" 2>/dev/null; kill "$DUMMY" 2>/dev/null; wait "$DUMMY" 2>/dev/null; return 0; }

test_sync_live_run_refusal() {
  sync_repo lr
  live_lock running; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "running: exit 1"
  assert_eq "story S1 is in a live run — /hold it or wait for it to end" "$(cat "$TMP/ad.err")" "message"
  printf 'held held by operator until 1\n' > "$TMP/run1/stories/S1"; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "held: exit 1"
  printf 'queued\n' > "$TMP/run1/stories/S1"; adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "queued: exit 0"
  live_done
}

test_sync_own_unit_exempt() {
  sync_repo ou
  live_lock running
  STUDIO_RUN="$TMP/run1/manifest.md"; STUDIO_STORY=S1; STUDIO_RUN_DIR="$TMP/run1"; export STUDIO_RUN STUDIO_STORY STUDIO_RUN_DIR
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "own unit: exit 0"
  STUDIO_STORY=S2; adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "another story's unit: exit 1"
  unset STUDIO_RUN STUDIO_STORY STUDIO_RUN_DIR
  live_done
}

test_sync_diverged_and_behind() {
  sync_repo db; git -C "$W" push -q origin S1-b
  git clone -q "$TMP/db.git" "$TMP/db-c2" >/dev/null 2>&1
  ( cd "$TMP/db-c2" && git checkout -q S1-b && printf r > S1-T4.txt && git add S1-T4.txt && git commit -q -m remote4 && git push -q origin S1-b ) >/dev/null 2>&1
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "behind: exit 0"
  assert_eq "$(git -C "$W" rev-parse HEAD)" "$(git -C "$W" rev-parse origin/S1-b)" "fast-forwarded"
  assert_contains "$TMP/ad.out" "^k: 3/6 -> 3/6$" "k line"
  assert_contains "$TMP/ad.out" "^T4 in progress: " "part-done line"
  wt_commit local5 S1-T5.txt
  ( cd "$TMP/db-c2" && printf s > S1-T6.txt && git add S1-T6.txt && git commit -q -m remote6 && git push -q origin S1-b ) >/dev/null 2>&1
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "diverged: exit 1"
  assert_eq "S1-b has diverged from origin/S1-b — reconcile it by hand, then sync" "$(cat "$TMP/ad.err")" "message"
}

test_sync_preconditions() {
  sync_repo pc
  adopt "$P" sync S1
  assert_eq 1 "$AD_STATUS" "on main: exit 1"
  assert_contains "$TMP/ad.err" "S1-b" "names the story branch"
  rm "$P/.studio/stories/S1.md"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "no pointer, no manifest: exit 1"
  mkdir -p "$P/docs/runs"
  printf '# Run: demo\nTarget: integration/demo\n\n| Story | Branch | Ticket | Spec | Plan | Depends on |\n|---|---|---|---|---|---|\n| S1 | S1-b | T-1 | a | b | - |\n' > "$P/docs/runs/demo.md"
  printf 'docs/runs/demo.md\n' > "$P/.studio/run"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "pointer re-initialised from the manifest row: exit 0"
  assert_file "$P/.studio/stories/S1.md" "pointer exists again"
  assert_contains "$TMP/ad.out" "^task view: skipped (stage idle)$" "stage idle skips the task view"
}

test_adopt_workspace_lookup_two_trees() {
  sync_repo tt
  git -C "$P" worktree add -q -b side "$TMP/tt-wt2" main >/dev/null 2>&1
  mkdir -p "$TMP/tt-wt2/.superpowers/sdd/2026-09-01-demo-plans"
  printf '%s\n' "$ORIG" > "$TMP/tt-wt2/.superpowers/sdd/2026-09-01-demo-plans/plan-path"
  cp "$W/$WS/progress.md" "$TMP/tt-wt2/.superpowers/sdd/2026-09-01-demo-plans/progress.md"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "two trees agree: exit 0"
  assert_contains "$TMP/ad.out" "^trees: .*$W" "lists the current tree"
  assert_contains "$TMP/ad.out" "^trees: .*$TMP/tt-wt2" "lists the second tree"
  sed "s/^Task 2: .*/Task 2: complete (commits $(s7 "$C1")..$(s7 "$C3"), review clean)/" "$TMP/tt-wt2/.superpowers/sdd/2026-09-01-demo-plans/progress.md" > "$TMP/tt.p"
  cp "$TMP/tt.p" "$TMP/tt-wt2/.superpowers/sdd/2026-09-01-demo-plans/progress.md"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "conflicting ranges: exit 1"
  assert_contains "$TMP/ad.err" "two ranges for Task 2" "says so"
  # A foreign owner of the slug sends the view to the collision name.
  sync_repo tc
  git -C "$P" worktree add -q -b side2 "$TMP/tc-wt2" main >/dev/null 2>&1
  mkdir -p "$TMP/tc-wt2/.superpowers/sdd/2026-09-01-demo-plans"
  printf '%s\n' "$ORIG" > "$TMP/tc-wt2/.superpowers/sdd/2026-09-01-demo-plans/plan-path"
  cp "$W/$WS/progress.md" "$TMP/tc-wt2/.superpowers/sdd/2026-09-01-demo-plans/progress.md"
  printf '%s\n' "docs/other/2026-09-01-demo.md" > "$W/$WS/plan-path"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "collision: exit 0"
  assert_eq "$ORIG" "$(cat "$W/.superpowers/sdd/2026-09-01-demo-plans/plan-path")" "view dir is the collision name"
  assert_eq "$(view_want "$ORIG")" "$(cat "$W/.superpowers/sdd/2026-09-01-demo-plans/progress.md")" "view written there"
}

test_sync_push_failure_warns() {
  sync_repo pf; claim_t4
  git -C "$W" config remote.origin.pushurl "$TMP/no-such.git"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "push failure: exit 0"
  assert_contains "$TMP/ad.out" "^push failed:" "reported"
  assert_eq "chore(studio): ledger (sync)" "$(git -C "$W" log -1 --format=%s)" "commit kept locally"
}

test_sync_failed_commit_restores() {
  sync_repo sfc; claim_t4
  cp "$W/.studio/ledger/S1.md" "$TMP/sfc.led"; _h="$(git -C "$W" rev-parse HEAD)"
  _hd="$TMP/sfc-hooks"; mkdir -p "$_hd"
  printf '#!/bin/sh\necho hook-says-no >&2\nexit 1\n' > "$_hd/pre-commit"; chmod +x "$_hd/pre-commit"
  git -C "$W" config core.hooksPath "$_hd"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "failed commit: exit 1"
  assert_contains "$TMP/ad.err" "ledger restored" "says restored"
  assert_contains "$TMP/ad.err" "hook-says-no" "shows git's stderr"
  assert_eq "$(cat "$TMP/sfc.led")" "$(cat "$W/.studio/ledger/S1.md")" "ledger byte-identical"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no commit"
}

test_sync_bad_new_claim_is_plain_mismatch() {
  sync_repo bn; adopt "$W" sync S1; claim_t4
  _x="$(git -C "$W" commit-tree -m x -p "$C4" "$C4^{tree}")"
  printf 'Task 5: complete (commits %s..%s, review clean)\n' "$(s7 "$C4")" "$(s7 "$_x")" >> "$W/$WS/progress.md"
  adopt "$W" sync S1
  assert_eq 1 "$AD_STATUS" "claim not on the branch: exit 1"
  assert_contains "$TMP/ad.err" "Task 5" "names the task"
  assert_contains "$TMP/ad.err" "$(s7 "$C4")\.\.$(s7 "$_x")" "names the claimed range"
  assert_contains "$TMP/ad.err" "$WS" "names the workspace"
  assert_not_contains "$TMP/ad.err" "rewritten" "no rewrite advice"
  assert_not_contains "$TMP/ad.err" "--reset" "no reset advice"
}

test_adopt_from_subdirectory() {
  sync_repo sub1
  mkdir -p "$W/sub/dir"
  claim_t4
  adopt "$W/sub/dir" sync S1
  assert_eq 0 "$AD_STATUS" "sync from a subdirectory exits 0"
  assert_eq "chore(studio): ledger (sync)" "$(git -C "$W" log -1 --format=%s)" "its commit lands"
  adopt_repo sub2 6 3
  mkdir -p "$W/sub/dir"
  adopt "$W/sub/dir" seed S1
  assert_eq 0 "$AD_STATUS" "seed from a subdirectory exits 0"
  assert_eq "chore(studio): ledger (adopt)" "$(git -C "$W" log -1 --format=%s)" "its commit lands"
}

test_adopt_seed_short_sha_line_same_range() {
  adopt_repo ssh 6 3; adopt "$W" seed S1
  sed "s/^\(- [0-9-]* \)T2 complete .*/\1T2 complete $(s7 "$C1")..$(s7 "$C2")/" "$W/.studio/ledger/S1.md" > "$TMP/ssh.led" && cp "$TMP/ssh.led" "$W/.studio/ledger/S1.md"
  git -C "$W" commit -q -am "short form" >/dev/null 2>&1
  adopt "$W" seed S1
  assert_eq 0 "$AD_STATUS" "a short-sha T line for the same range is not a mismatch"
  assert_not_contains "$TMP/ad.err" "claims say" "no mismatch line"
  assert_eq "1" "$(grep -c 'T2 complete' "$W/.studio/ledger/S1.md")" "no second T2 line"
}

test_sync_short_sha_truth_line() {
  sync_repo shs
  set_truth 2 "$(s7 "$C1")..$(s7 "$C2")"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "a short-sha truth line that resolves: exit 0"
  assert_contains "$TMP/ad.out" "^k: 3/6 -> 3/6$" "k line"
  assert_eq "$(view_want "$ORIG")" "$(cat "$W/$WS/progress.md")" "the view holds the full shas"
}

test_sync_view_collision_counter() {
  sync_repo cc
  git -C "$P" worktree add -q -b side3 "$TMP/cc-wt2" main >/dev/null 2>&1
  _stem="$(basename "$WS")"; _par="$(basename "$(dirname "$ORIG")")"
  mkdir -p "$TMP/cc-wt2/.superpowers/sdd/$_stem-$_par-2"
  printf '%s\n' "$ORIG" > "$TMP/cc-wt2/.superpowers/sdd/$_stem-$_par-2/plan-path"
  cp "$W/$WS/progress.md" "$TMP/cc-wt2/.superpowers/sdd/$_stem-$_par-2/progress.md"
  printf '%s\n' "docs/other/$_stem.md" > "$W/$WS/plan-path"
  mkdir -p "$W/$WS-$_par"; printf '%s\n' "docs/another/$_stem.md" > "$W/$WS-$_par/plan-path"
  adopt "$W" sync S1
  assert_eq 0 "$AD_STATUS" "two foreign owners: exit 0"
  assert_eq "$ORIG" "$(cat "$W/$WS-$_par-2/plan-path")" "view dir takes the -<parent>-2 name"
  assert_eq "$(view_want "$ORIG")" "$(cat "$W/$WS-$_par-2/progress.md")" "view written there"
  assert_contains "$TMP/ad.out" "^trees: .*$TMP/cc-wt2" "the second tree's workspace is found"
}

test_sync_view_write_failure_commits_nothing() {
  sync_repo vw; claim_t4
  cp "$W/.studio/ledger/S1.md" "$TMP/vw.led"; _h="$(git -C "$W" rev-parse HEAD)"; _o="$(git -C "$W" rev-parse origin/S1-b)"
  chmod 555 "$W/$WS"
  adopt "$W" sync S1
  chmod 755 "$W/$WS"
  assert_eq 1 "$AD_STATUS" "view write fails: exit 1"
  assert_contains "$TMP/ad.err" "could not write" "says so"
  assert_eq "$_h" "$(git -C "$W" rev-parse HEAD)" "no commit"
  assert_eq "$(cat "$TMP/vw.led")" "$(cat "$W/.studio/ledger/S1.md")" "ledger restored"
  assert_eq "$_o" "$(git -C "$W" rev-parse origin/S1-b)" "nothing pushed"
}

run_tests test_adopt_start_checkout_from_run_worktree test_adopt_start_checkout_two_listings_refuse test_adopt_start_checkout_none_falls_back test_adopt_live_run_check_per_run_lock test_adopt_part_done_ignores_sync test_adopt_seed_short_sha_line_same_range test_sync_short_sha_truth_line test_sync_view_collision_counter test_sync_view_write_failure_commits_nothing test_sync_failed_commit_restores test_sync_bad_new_claim_is_plain_mismatch test_adopt_from_subdirectory test_sync_already_in_sync test_sync_accepts_claims test_sync_all_or_nothing test_sync_claim_end_differs \
  test_sync_truth_mismatches test_sync_ambiguous_short_sha test_sync_rewrite_message test_sync_views_keep_other_lines \
  test_sync_carries_rulings_once test_sync_landed_note test_sync_live_run_refusal test_sync_own_unit_exempt \
  test_sync_diverged_and_behind test_sync_preconditions test_adopt_workspace_lookup_two_trees test_sync_push_failure_warns \
  test_adopt_seed_no_workspace_refused test_adopt_seed_existing_range_differs test_adopt_seed_no_adopted_line test_adopt_seed_failed_commit_restores \
  test_adopt_help_and_usage test_adopt_inspect_clean_chain test_adopt_inspect_from_any_checkout \
  test_adopt_inspect_not_started test_adopt_inspect_no_workspace test_adopt_main_merged_between_tasks \
  test_adopt_claim_tokens test_adopt_claim_gaps_and_order test_adopt_short_sha_lines_parse \
  test_adopt_part_done_filter test_adopt_post_task_commits test_adopt_explicit_base \
  test_adopt_check_done_on_branch_ledger test_adopt_workspaces_status test_adopt_claim_stops_at_close_paren \
  test_adopt_rewritten_history_message test_adopt_seed_writes_truth test_adopt_seed_second_run_noop \
  test_adopt_seed_check_requested test_adopt_seed_refuses_changed_title test_adopt_seed_wrong_branch \
  test_adopt_seed_carries_rulings test_adopt_seed_base_conflict test_adopt_seed_reset_after_rebase
