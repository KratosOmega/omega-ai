#!/bin/sh
# overnight-cleanup.sh: a run whose every story is confirmed merged into its
# target closes its record and cleans up after itself (worktrees, local and
# remote branches, Jira, Multica, story pointers). Each case builds its own
# origin (a bare repo) and project clone under $TMP, and stubs gh, acli and
# multica on PATH.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
BIN="$REPO_ROOT/studios/game-dev/bin"
mk_tmp overnight_cleanup; trap '{ for _d in $DUMMIES; do kill "$_d"; done; wait; } 2>/dev/null; rm_tmp "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
DUMMIES=""
TAB="$(printf '\t')"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
. "$BIN/overnight-runs.sh"
. "$BIN/overnight-tools.sh"
. "$BIN/overnight-cleanup.sh"
live_dummy() { sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; DUMMIES="$DUMMIES $DUMMY"; }

# ---- stubs: gh, acli, multica (PATH-first). Each logs its argv, one call per line, to $STUBS/<name>.log.
STUBS="$TMP/stubs"; mkdir -p "$STUBS/bin"
cat > "$STUBS/bin/gh" <<'STUB'
#!/bin/sh
# gh pr list --head B …: prints $STUBS/prs/<B with / as %> (TSV: number state head merge base url).
# gh pr view URL …: prints $STUBS/view (JSON). GH_FAIL=1: exit 1. GH_SLEEP: sleep first.
printf '%s\n' "$*" >> "$STUBS/gh.log"
[ -z "${GH_SLEEP:-}" ] || sleep "$GH_SLEEP"
[ -z "${GH_FAIL:-}" ] || { echo "gh: HTTP 502" >&2; exit 1; }
case "$1 $2" in
  "pr list") while [ "$#" -gt 0 ]; do [ "$1" = --head ] && { b="$2"; break; }; shift; done
             f="$STUBS/prs/$(printf '%s' "$b" | tr / %)"; [ ! -f "$f" ] || cat "$f" ;;
  "pr view") cat "$STUBS/view" 2>/dev/null ;;
esac
exit 0
STUB
cat > "$STUBS/bin/acli" <<'STUB'
#!/bin/sh
# view KEY: status from $STUBS/jira/KEY (default "To Do"). search: $STUBS/jira/children (default []).
# comment create / transition: exit $ACLI_RC (default 0); transition writes the status.
printf '%s\n' "$*" >> "$STUBS/acli.log"
[ -z "${ACLI_SLEEP:-}" ] || sleep "$ACLI_SLEEP"
k=""; s=""; a="$*"
while [ "$#" -gt 0 ]; do case "$1" in --key) k="$2"; shift ;; --status) s="$2"; shift ;; esac; shift; done
case "$a" in
  "jira workitem view "*) k="${a#jira workitem view }"; k="${k%% *}"
    printf '{\n  "key": "%s",\n  "fields": {\n    "status": {\n      "name": "%s",\n      "statusCategory": { "name": "x" }\n    }\n  }\n}\n' \
      "$k" "$(cat "$STUBS/jira/$k" 2>/dev/null || echo 'To Do')" ;;
  "jira workitem search "*) cat "$STUBS/jira/children" 2>/dev/null || echo '[]' ;;
  "jira workitem comment create "*) exit "${ACLI_RC:-0}" ;;
  "jira workitem transition "*) [ "${ACLI_RC:-0}" = 0 ] || exit "$ACLI_RC"; printf '%s\n' "$s" > "$STUBS/jira/$k" ;;
esac
exit 0
STUB
cat > "$STUBS/bin/multica" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUBS/multica.log"
exit "${MULTICA_RC:-0}"
STUB
chmod +x "$STUBS/bin/gh" "$STUBS/bin/acli" "$STUBS/bin/multica"
PATH="$STUBS/bin:$PATH"; export PATH STUBS
STUDIO_OVERNIGHT_TOOLS_SECONDS=10; export STUDIO_OVERNIGHT_TOOLS_SECONDS

# stubs_reset — empty logs, no PR or Jira data, no failure knobs.
stubs_reset() {
  rm -rf "$STUBS/prs" "$STUBS/jira" "$STUBS/view"; mkdir -p "$STUBS/prs" "$STUBS/jira"
  : > "$STUBS/gh.log"; : > "$STUBS/acli.log"; : > "$STUBS/multica.log"
  unset GH_FAIL GH_SLEEP ACLI_RC ACLI_SLEEP MULTICA_RC
}
# pr BRANCH NUMBER STATE HEAD MERGE BASE — one PR line for BRANCH in the gh stub.
pr() { printf '%s\t%s\t%s\t%s\t%s\thttps://gh.test/pull/%s\n' "$2" "$3" "$4" "$5" "$6" "$2" >> "$STUBS/prs/$(printf '%s' "$1" | tr / %)"; }

# ---- the project: origin (bare) and its clone R, with main checked out.
# proj NAME — R and O fresh; main has one commit; origin/HEAD is main.
proj() {
  O="$TMP/$1.git"; R="$TMP/$1"; rm -rf "$O" "$R"
  git init -q --bare -b main "$O" && git clone -q "$O" "$R" 2>/dev/null
  git -C "$R" commit -q --allow-empty -m init && git -C "$R" push -q origin main
  git -C "$R" remote set-head origin main >/dev/null 2>&1
  mkdir -p "$R/.studio/runs" "$R/.studio/reports" "$R/.studio/stories"
  stubs_reset
}
# story_branch BRANCH FILE — BRANCH off origin/main with one commit adding FILE, pushed; TIP its head.
story_branch() {
  git -C "$R" checkout -q -b "$1" origin/main && printf '%s\n' "$1" > "$R/$2" && git -C "$R" add "$2" \
    && git -C "$R" commit -q -m "work $1" && git -C "$R" push -q origin "$1" && git -C "$R" checkout -q main
  TIP="$(git -C "$R" rev-parse "$1")"
}
# land_merge BRANCH — a merge commit of BRANCH on main, pushed (the runner's landing); MS its sha.
land_merge() {
  git -C "$R" pull -q --ff-only origin main 2>/dev/null; git -C "$R" merge -q --no-ff -m "Merge $1" "$1" \
    && git -C "$R" push -q origin main; MS="$(git -C "$R" rev-parse HEAD)"
}
# land_squash BRANCH SUBJECT — a squash of BRANCH on main, pushed (a hand landing on GitHub); MS its sha.
land_squash() {
  git -C "$R" pull -q --ff-only origin main 2>/dev/null; git -C "$R" merge -q --squash "$1" >/dev/null \
    && git -C "$R" commit -q -m "$2" && git -C "$R" push -q origin main; MS="$(git -C "$R" rev-parse HEAD)"
}
# record SLUG MODE TARGET ROWS… — .studio/runs/SLUG (rows.tsv; empty landed.tsv) and its report dir
# with manifest.md and rows.tsv. A row is ID:BRANCH:TICKET. RUN is the report dir.
record() {
  _s="$1"; _m="$2"; _t="$3"; shift 3
  D="$R/.studio/runs/$_s"; RUN="$R/.studio/reports/overnight-${_s%.*T*Z}-20261027-010000"
  mkdir -p "$D" "$RUN"; : > "$D/rows.tsv"; : > "$D/landed.tsv"
  for _r in "$@"; do
    printf '%s\t%s\t%s\tdocs/s.md\tdocs/p.md\t\n' "${_r%%:*}" "$(printf '%s' "$_r" | cut -d: -f2)" "${_r##*:}" >> "$D/rows.tsv"
  done
  cp "$D/rows.tsv" "$RUN/rows.tsv"
  printf '# Run: %s\n\nMode: %s\nTarget: %s\nDocs: %s\n' "${_s%.*T*Z}" "$_m" "$_t" "$(git -C "$R" rev-parse origin/main)" > "$RUN/manifest.md"
}
# landed ID SHA [TARGET] — a landed.tsv line.
landed() { printf '%s\t%s\t%s\t1\n' "$1" "${3:-main}" "$2" >> "$D/landed.tsv"; }
# settle ARGS — cleanup_record "$R" ARGS, output in $TMP/out, status in $RC.
settle() { cleanup_record "$R" "$@" > "$TMP/out" 2>&1; RC=$?; }
remote_has() { git -C "$R" ls-remote --exit-code origin "refs/heads/$1" >/dev/null 2>&1; }

# ---- Task 1: confirmation and the record

test_direct_runner_landed() {
  proj d1; story_branch A-b a.txt; TA="$TIP"; land_merge A-b; MA="$MS"
  story_branch B-b b.txt; land_merge B-b; MB="$MS"
  record d1 direct main A:A-b:- B:B-b:-; landed A "$MA"; landed B "$MB"
  settle d1
  assert_eq 0 "$RC" "every story landed by the runner: cleaned"
  assert_contains "$TMP/out" "^run d1: confirmed — every story is in origin/main" "the head line says confirmed"
  assert_file "$D/done" "the record is done"
  assert_file "$D/cleaned" "and cleaned"
  assert_contains "$TMP/out" "^run d1: cleaned up$" "the tail line"
  assert_eq 2 "$(grep -c . "$D/landed.tsv")" "landed.tsv is unchanged"
}

test_direct_hand_landed_backfill() {
  proj d2; story_branch K-b k.txt; TK="$TIP"; land_squash K-b "K by hand (#7)"; MK="$MS"
  record d2 direct main K:K-b:-
  pr K-b 7 MERGED "$TK" "$MK" main
  settle d2
  assert_eq 0 "$RC" "a story landed by hand: cleaned"
  assert_eq "K${TAB}main${TAB}$MK" "$(cut -f1-3 "$D/landed.tsv")" "landed.tsv is backfilled from the PR's merge commit"
  assert_contains "$TMP/out" "^  done: landed.tsv: K $MK (PR https://gh.test/pull/7)$" "the backfill is reported"
  assert_file "$D/done" "the record is done"
  assert_status 2 "the squashed branch is deleted (its tip is the merged PR's head)" -- remote_has K-b
}

test_unmerged_story_untouched() {
  proj d3; story_branch A-b a.txt; land_merge A-b; MA="$MS"; story_branch U-b u.txt
  record d3 direct main A:A-b:- U:U-b:-; landed A "$MA"
  pr U-b 9 OPEN "$TIP" - main
  mkdir -p "$R/.claude/worktrees"; git -C "$R" worktree add -q "$R/.claude/worktrees/A-b" A-b
  : > "$R/.studio/stories/A.md"
  settle d3
  assert_eq 1 "$RC" "an unmerged story: not cleaned"
  assert_contains "$TMP/out" "^run d3: not confirmed — U: U-b is not merged into main" "it names the story"
  assert_missing "$D/done" "no done"
  assert_missing "$D/cleaned" "no cleaned"
  assert_status 0 "A-b is still on origin" -- remote_has A-b
  assert_status 0 "U-b is still on origin" -- remote_has U-b
  assert_status 0 "the worktree is kept" -- test -d "$R/.claude/worktrees/A-b"
  assert_file "$R/.studio/stories/A.md" "the story pointer is kept"
  assert_eq 1 "$(grep -c . "$D/landed.tsv")" "landed.tsv is unchanged"
  assert_eq "" "$(cat "$STUBS/acli.log" "$STUBS/multica.log")" "no Jira or Multica call"
}

test_integration_final_merged_or_open() {
  proj i1; git -C "$R" push -q origin origin/main:refs/heads/integration/i1
  git -C "$R" fetch -q origin
  story_branch C-b c.txt
  git -C "$R" checkout -q -b integration/i1 origin/integration/i1 && git -C "$R" merge -q --no-ff -m "Merge C" C-b \
    && git -C "$R" push -q origin integration/i1 && git -C "$R" checkout -q main
  MC="$(git -C "$R" rev-parse integration/i1)"; FH="$MC"
  record i1 integration integration/i1 C:C-b:-; landed C "$MC" integration/i1
  printf '%s https://gh.test/pull/30 green\n' "$FH" > "$D/final"
  printf '{"state":"OPEN","headRefOid":"%s","mergeCommit":null}\n' "$FH" > "$STUBS/view"
  pr integration/i1 30 OPEN "$FH" - main
  settle i1
  assert_eq 1 "$RC" "the final PR is open: not cleaned"
  assert_contains "$TMP/out" "^run i1: not confirmed — final PR https://gh.test/pull/30 is not merged (OPEN)" "it names the final PR"
  assert_missing "$D/done" "no done"
  assert_status 0 "C-b is kept" -- remote_has C-b
  # The final PR is merged (a squash: main does not hold the integration head).
  land_squash integration/i1 "integration i1 (#30)"; MF="$MS"
  printf '{"state":"MERGED","headRefOid":"%s","mergeCommit":{"oid":"%s"}}\n' "$FH" "$MF" > "$STUBS/view"
  : > "$STUBS/prs/integration%i1"; pr integration/i1 30 MERGED "$FH" "$MF" main
  settle i1
  assert_eq 0 "$RC" "the final PR is merged: cleaned"
  assert_contains "$TMP/out" "^run i1: confirmed — every story is in origin/integration/i1; final PR https://gh.test/pull/30 merged" "the head names the final PR"
  assert_file "$D/done" "done"
  assert_status 2 "integration/i1 is deleted" -- remote_has integration/i1
  assert_status 2 "C-b is deleted (its tip is in the merged final head)" -- remote_has C-b
}

test_direct_progress_required() {
  proj p1; mkdir -p "$R/docs/game-dev"; printf '# Progress\n' > "$R/docs/game-dev/PROGRESS.md"
  git -C "$R" add docs && git -C "$R" commit -q -m progress-file && git -C "$R" push -q origin main
  story_branch A-b a.txt; land_merge A-b; MA="$MS"
  record p1 direct main A:A-b:-; landed A "$MA"
  git -C "$R" checkout -q -b progress/p1 origin/main && printf 'entry\n' >> "$R/docs/game-dev/PROGRESS.md" \
    && git -C "$R" commit -qam "docs(progress): p1" && git -C "$R" push -q origin progress/p1 && git -C "$R" checkout -q main
  PT="$(git -C "$R" rev-parse progress/p1)"
  settle p1
  assert_eq 1 "$RC" "a PROGRESS.md run whose progress entry is not on main: not cleaned"
  assert_contains "$TMP/out" "^run p1: not confirmed — the progress entry (progress/p1) is not on main" "it says so"
  assert_missing "$D/done" "no done"
  land_squash progress/p1 "docs(progress): p1 (#12)"; pr progress/p1 12 MERGED "$PT" "$MS" main
  settle p1
  assert_eq 0 "$RC" "the progress PR landed by hand: cleaned"
  assert_contains "$TMP/out" "; progress entry on origin/main$" "the head names the progress entry"
  assert_status 2 "progress/p1 is deleted" -- remote_has progress/p1
}

test_direct_progress_in_story_landing() {
  proj p2; mkdir -p "$R/docs/game-dev"; printf '# Progress\n' > "$R/docs/game-dev/PROGRESS.md"
  git -C "$R" add docs && git -C "$R" commit -q -m progress-file && git -C "$R" push -q origin main
  git -C "$R" checkout -q -b S-b origin/main && printf 'S entry\n' >> "$R/docs/game-dev/PROGRESS.md" \
    && git -C "$R" commit -qam "S with its entry" && git -C "$R" push -q origin S-b && git -C "$R" checkout -q main
  TS="$(git -C "$R" rev-parse S-b)"; land_squash S-b "S by hand (#21)"
  record p2 direct main S:S-b:-; pr S-b 21 MERGED "$TS" "$MS" main
  settle p2
  assert_eq 0 "$RC" "the story's own landing carries the PROGRESS entry: cleaned"
  assert_contains "$TMP/out" "; progress entry in S's landing$" "the head says where the entry is"
}

test_live_run_skipped() {
  proj lv; story_branch A-b a.txt; land_merge A-b
  record lv direct main A:A-b:-; landed A "$MS"
  live_dummy; printf 'pid=%s\nrun=%s\nstarted=2026-10-27T01:00:00Z\n' "$DUMMY" "$RUN" > "$D/lock"
  settle lv
  assert_eq 3 "$RC" "a live run is skipped"
  assert_missing "$D/done" "its record is untouched"
  assert_eq "" "$(cat "$STUBS/gh.log")" "and gh is not asked"
  settle lv --self
  assert_eq 0 "$RC" "--self (the run's own finish) cleans it"
  rm -f "$D/lock"
}

# ---- Task 2: the steps

# full_direct SLUG — a done direct run of two rows (A runner-landed with merge
# commits, K hand-squashed), each with a story worktree, a run worktree on
# run/SLUG and a pushed progress-less run; Jira keys KAN-1 (A) and KAN-2 (K).
full_direct() {
  proj "$1"
  git -C "$R" checkout -q -b "run/$1" origin/main && printf 'plan\n' > "$R/plan.md" && git -C "$R" add plan.md \
    && git -C "$R" commit -q -m "docs(run): $1" && git -C "$R" push -q origin "run/$1" && git -C "$R" checkout -q main
  RT="$(git -C "$R" rev-parse "run/$1")"
  story_branch A-b a.txt; TA="$TIP"; land_merge A-b; MA="$MS"
  story_branch K-b k.txt; TK="$TIP"; land_squash K-b "K by hand (#7)"; MK="$MS"
  record "$1" direct main A:A-b:KAN-1 K:K-b:KAN-2; landed A "$MA"
  pr A-b 5 MERGED "$TA" "$MA" main; pr K-b 7 MERGED "$TK" "$MK" main
  mkdir -p "$R/.claude/worktrees"
  git -C "$R" worktree add -q "$R/.claude/worktrees/run-$1" "run/$1"
  : > "$R/.claude/worktrees/run-$1/.studio-run-placeholder"; rm -f "$R/.claude/worktrees/run-$1/.studio-run-placeholder"
  mkdir -p "$R/.claude/worktrees/run-$1/.studio"; printf 'docs/runs/%s.md\n' "$1" > "$R/.claude/worktrees/run-$1/.studio/run"
  git -C "$R" worktree add -q "$R/.claude/worktrees/A-b" A-b
  git -C "$R" worktree add -q "$R/.claude/worktrees/K-b" K-b
  printf '# Studio State\n\nstage: idle\n\n## Ledger\n\n' > "$R/.studio/stories/A.md"
  printf '# Studio State\n\nstage: idle\n\n## Ledger\n\n' > "$R/.studio/stories/K.md"
}
# mirror SLUG IDS… — a retired Multica bridge state file for this run: story ID=IDENT pairs,
# with no final newline (as the bridge's json.dump writes it); a second, older run of the
# slug shares the first pair, so the files' lines must not run together.
mirror() {
  _ms="$1"; shift; mkdir -p "$HOME/.claude-gamedev/multica/state/retired"; _mj=""
  for _mp in "$@"; do _mj="$_mj${_mj:+, }\"${_mp%%=*}\": \"${_mp#*=}\""; done
  printf '{"key": "k", "root": "%s", "run_dir": "%s", "stories": {%s}, "run_issue": "OMEG-1"}' "$R" "$RUN" "$_mj" \
    > "$HOME/.claude-gamedev/multica/state/retired/overnight-$_ms-20261027-010000-abcd1234.json"
  printf '{"key": "k", "root": "%s", "run_dir": "%s", "stories": {"%s": "%s"}}' "$R" "${RUN%-*}-000000" "${1%%=*}" "${1#*=}" \
    > "$HOME/.claude-gamedev/multica/state/retired/overnight-$_ms-20261026-000000-abcd1234.json"
}

test_steps_full_direct() {
  full_direct f1; mirror f1 A=OMEG-10 K=OMEG-11
  settle f1
  assert_eq 0 "$RC" "a full direct run cleans up"
  assert_contains "$TMP/out" "^  done: deleted origin/A-b$" "the runner-landed branch is deleted"
  assert_contains "$TMP/out" "^  done: deleted origin/K-b$" "the squashed branch is deleted"
  assert_status 2 "A-b is gone from origin" -- remote_has A-b
  assert_status 2 "K-b is gone from origin" -- remote_has K-b
  _tag="run-archive/f1-$(printf '%.12s' "$RT")"
  assert_contains "$TMP/out" "^  done: tagged origin/run/f1 as $_tag$" "run/f1 is tagged first"
  assert_eq "$RT" "$(git -C "$R" ls-remote origin "refs/tags/$_tag" | cut -f1)" "the archive tag is on origin at the run branch's tip"
  assert_status 2 "run/f1 is gone from origin" -- remote_has run/f1
  assert_missing "$R/.claude/worktrees/run-f1" "the run worktree is removed (its .studio/run is the runner's own)"
  assert_missing "$R/.claude/worktrees/A-b" "the story worktrees are removed"
  assert_missing "$R/.claude/worktrees/K-b" "both"
  assert_eq "" "$(git -C "$R" branch --list A-b K-b run/f1)" "and their local branches"
  assert_eq "KAN-1 KAN-2" "$(sed -n 's/^jira workitem transition --key \([^ ]*\) --status Done --yes$/\1/p' "$STUBS/acli.log" | tr '\n' ' ' | sed 's/ $//')" "each Jira key moves to Done"
  assert_eq 2 "$(grep -c '^jira workitem comment create --key' "$STUBS/acli.log")" "after one comment each"
  assert_contains "$STUBS/acli.log" "^- K: https://gh.test/pull/7, merge $(printf '%.12s' "$MK")$" "the comment names the PR and merge sha"
  assert_contains "$STUBS/acli.log" "^- A: https://gh.test/pull/5, merge $(printf '%.12s' "$MA")$" "a runner landing's PR too"
  assert_eq "issue status OMEG-10 done --no-start
issue status OMEG-11 done --no-start" "$(cat "$STUBS/multica.log")" "each Multica mirror is set to done"
  assert_file "$R/.studio/stories/done/A.md" "the story pointers are archived"
  assert_missing "$R/.studio/stories/K.md" "out of the live set"
  assert_contains "$R/.studio/stories/done/K.md" "^- [0-9-]* merged $MK into main (run f1)$" "with a merged ledger line"
  assert_file "$D/cleaned" "cleaned"
  assert_contains "$D/cleanup.log" "^run f1: cleaned up$" "the attempt is logged"
  # A rerun does nothing: no gh, acli or multica call.
  : > "$STUBS/gh.log"; : > "$STUBS/acli.log"; : > "$STUBS/multica.log"
  settle f1
  assert_eq 0 "$RC" "a cleaned record: 0"
  assert_eq "run f1: already cleaned up" "$(cat "$TMP/out")" "it says so"
  assert_eq "" "$(cat "$STUBS/gh.log" "$STUBS/acli.log" "$STUBS/multica.log")" "and calls nothing"
}

test_steps_dry_run_writes_nothing() {
  full_direct dr; mirror dr A=OMEG-10 K=OMEG-11
  _refs="$(git -C "$R" for-each-ref | sort)"
  settle dr --dry-run
  assert_eq 0 "$RC" "the dry run: nothing would be left"
  assert_contains "$TMP/out" "^  would: landed.tsv: K $MK (PR https://gh.test/pull/7)$" "it names the backfill"
  assert_contains "$TMP/out" "^  would: mark the record done$" "the record"
  assert_contains "$TMP/out" "^  would: delete origin/A-b$" "the remote branches"
  assert_contains "$TMP/out" "^  would: tag origin/run/dr as run-archive/dr-" "the run branch's archive tag"
  assert_contains "$TMP/out" "^  would: remove worktree $R/.claude/worktrees/A-b$" "the worktrees"
  assert_contains "$TMP/out" "^  would: delete local branch K-b$" "the local branches"
  assert_contains "$TMP/out" "^  would: Jira KAN-2 To Do → Done, comment: Merged into main by overnight run dr: - K: https://gh.test/pull/7" "the Jira moves"
  assert_contains "$TMP/out" "^  would: Multica OMEG-11 → done$" "the Multica moves"
  assert_contains "$TMP/out" "^  would: archive story pointer A " "the story pointers"
  assert_contains "$TMP/out" "^run dr: dry run — nothing would be left$" "the tail"
  assert_eq "$_refs" "$(git -C "$R" for-each-ref | sort)" "no ref changed"
  assert_status 0 "A-b is still on origin" -- remote_has A-b
  assert_status 0 "run/dr is still on origin" -- remote_has run/dr
  assert_eq "" "$(git -C "$R" ls-remote --tags origin)" "no tag pushed"
  assert_eq 0 "$(grep -c . "$D/landed.tsv" | sed 's/^1$/0/')" "landed.tsv not backfilled"
  assert_eq "$(printf 'A\tmain\t%s' "$MA")" "$(cut -f1-3 "$D/landed.tsv")" "landed.tsv unchanged"
  assert_eq "" "$(ls "$D" | grep -v -e '^rows.tsv$' -e '^landed.tsv$')" "no record file written"
  assert_status 0 "the worktree is kept" -- test -d "$R/.claude/worktrees/A-b"
  assert_file "$R/.studio/stories/A.md" "the pointer is kept"
  assert_eq "" "$(grep -e 'comment create' -e transition "$STUBS/acli.log")" "acli only read"
  assert_eq "" "$(cat "$STUBS/multica.log")" "multica not called"
  assert_eq "" "$(grep -v -e '^pr list' -e '^pr view' "$STUBS/gh.log")" "gh only read"
}

test_steps_kept_branches_and_worktrees() {
  full_direct kp
  # K-b moved past its merged PR's head; A-b has an open follow-up PR; A's worktree is dirty.
  git -C "$R/.claude/worktrees/K-b" commit -q --allow-empty -m more && git -C "$R/.claude/worktrees/K-b" push -q origin K-b
  pr A-b 8 OPEN "$TA" - main
  printf 'wip\n' > "$R/.claude/worktrees/A-b/a.txt"
  settle kp
  assert_eq 1 "$RC" "something is left"
  assert_contains "$TMP/out" "^  left: origin/K-b: tip [0-9a-f]* is not merged into main — kept$" "a moved tip is kept"
  assert_status 0 "K-b is still on origin" -- remote_has K-b
  assert_contains "$TMP/out" "^  left: origin/A-b: open PR https://gh.test/pull/8 — kept$" "an open PR keeps its branch"
  assert_status 0 "A-b is still on origin" -- remote_has A-b
  assert_contains "$TMP/out" "^  left: worktree $R/.claude/worktrees/A-b has uncommitted changes — kept$" "a dirty worktree is kept"
  assert_eq "wip" "$(cat "$R/.claude/worktrees/A-b/a.txt")" "with its change"
  assert_eq "A-b" "$(git -C "$R" branch --list A-b | tr -d ' *+')" "and its local branch"
  assert_missing "$R/.claude/worktrees/K-b" "K's clean worktree is removed"
  assert_contains "$TMP/out" "^  left: local branch K-b: tip [0-9a-f]* is not merged into main — kept$" "but its moved branch is kept"
  assert_file "$D/done" "the record is still done"
  assert_missing "$D/cleaned" "but not cleaned"
  assert_contains "$TMP/out" "^run kp: 4 left — rerun: studio-overnight settle kp$" "the tail counts what is left"
  # The rest is fixed by hand; a rerun finishes.
  git -C "$R/.claude/worktrees/A-b" checkout -q -- a.txt; : > "$STUBS/prs/A-b"; pr A-b 5 MERGED "$TA" "$MA" main
  git -C "$R" push -q origin --delete K-b; git -C "$R" branch -q -D K-b
  settle kp
  assert_eq 0 "$RC" "the rerun finishes"
  assert_status 2 "A-b is gone" -- remote_has A-b
  assert_missing "$R/.claude/worktrees/A-b" "its worktree too"
  assert_eq 2 "$(grep -c '^jira workitem comment create' "$STUBS/acli.log")" "no Jira comment posted twice"
}

test_steps_tool_failures() {
  full_direct tf; mirror tf A=OMEG-10 K=OMEG-11
  ACLI_RC=1; MULTICA_RC=1; export ACLI_RC MULTICA_RC
  settle tf
  assert_eq 1 "$RC" "acli and multica fail: left"
  assert_contains "$TMP/out" "^  left: Jira KAN-1: comment failed (exit 1" "the Jira failure is reported"
  assert_contains "$TMP/out" "^  left: Multica OMEG-10: exit 1" "the Multica failure is reported"
  assert_contains "$TMP/out" "^  done: deleted origin/A-b$" "the other steps still run"
  assert_file "$R/.studio/stories/done/A.md" "the pointers too"
  # The comment went through but the transition fails: the rerun does not re-post.
  unset ACLI_RC MULTICA_RC; printf 'jira-comment KAN-1\n' >> "$D/cleanup.state"; : > "$STUBS/acli.log"
  ACLI_SLEEP=3 STUDIO_OVERNIGHT_TOOLS_SECONDS=1; export ACLI_SLEEP
  printf '{"cleanup": {"timeout_seconds": 1}}\n' > "$R/.studio/config.json"
  settle tf
  assert_contains "$TMP/out" "^  left: Jira KAN-1: cannot read it (timed out after 1s)$" "an acli timeout is reported"
  unset ACLI_SLEEP; rm -f "$R/.studio/config.json"
  settle tf
  assert_eq 0 "$RC" "the rerun finishes"
  assert_eq 1 "$(grep -c '^jira workitem comment create --key KAN-2' "$STUBS/acli.log")" "KAN-2 gets its one comment"
  assert_eq 0 "$(grep -c '^jira workitem comment create --key KAN-1' "$STUBS/acli.log")" "KAN-1's comment is not posted again"
  assert_eq "Done" "$(cat "$STUBS/jira/KAN-1")" "KAN-1 is Done"
  # gh fails: nothing is confirmed (K needs its PR).
  full_direct tg; GH_FAIL=1; export GH_FAIL
  settle tg
  assert_eq 1 "$RC" "gh fails: not confirmed"
  assert_contains "$TMP/out" "^run tg: not confirmed — gh pr list --head K-b: exit 1: gh: HTTP 502$" "the gh failure is the reason"
  assert_missing "$D/done" "nothing written"
  unset GH_FAIL
  # A key Jira does not know (another tracker's): skipped, not left.
  full_direct tj; printf '#!/bin/sh\necho "✗ Error: Issue does not exist or you do not have permission to see it." >&2; exit 1\n' > "$TMP/noissue"
  chmod +x "$TMP/noissue"; printf '{"cleanup": {"jira_cli": "%s"}}\n' "$TMP/noissue" > "$R/.studio/config.json"
  settle tj
  assert_eq 0 "$RC" "an unknown key does not block the cleanup"
  assert_contains "$TMP/out" "^  skip: Jira KAN-1: Jira has no such issue (or no access to it) — not a Jira ticket here$" "it is skipped with the reason"
  # No acli at all.
  full_direct tn; printf '{"cleanup": {"jira_cli": "no-such-acli"}}\n' > "$R/.studio/config.json"
  settle tn
  assert_contains "$TMP/out" "^  left: Jira KAN-1 KAN-2: no-such-acli not found — not updated$" "a missing acli is reported"
  assert_contains "$TMP/out" "^  done: deleted origin/A-b$" "the other steps still run"
}

test_steps_jira_guards() {
  full_direct jg
  # KAN-1 is also the ticket of a row of another, unfinished run; KAN-2 has an open child.
  mkdir -p "$R/.studio/runs/other.20261025T011344Z"; printf 'A-2\tA2-b\tKAN-1\n' > "$R/.studio/runs/other.20261025T011344Z/rows.tsv"
  : > "$R/.studio/runs/other.20261025T011344Z/landed.tsv"
  printf '[{"key": "KAN-9", "fields": {}}]\n' > "$STUBS/jira/children"
  settle jg
  assert_contains "$TMP/out" "^  left: Jira KAN-1 kept open: also the ticket of A-2 (run other.20261025T011344Z, not done)$" "a ticket shared with a run not done stays open"
  assert_contains "$TMP/out" "^  left: Jira KAN-2 kept open: open children KAN-9$" "a ticket with open children stays open"
  assert_eq "" "$(grep -e 'comment create' -e transition "$STUBS/acli.log")" "nothing posted"
  # The other run is done and landed; the child is closed; a Done ticket is not touched.
  : > "$R/.studio/runs/other.20261025T011344Z/done"; printf 'A-2\tmain\tabc\t1\n' > "$R/.studio/runs/other.20261025T011344Z/landed.tsv"
  printf '[]\n' > "$STUBS/jira/children"; printf 'Done\n' > "$STUBS/jira/KAN-2"; : > "$STUBS/acli.log"
  settle jg
  assert_eq 0 "$RC" "the guards clear"
  assert_contains "$TMP/out" "^  skip: Jira KAN-2 is already Done$" "a Done ticket is skipped"
  assert_eq 1 "$(grep -c 'transition --key KAN-1 ' "$STUBS/acli.log")" "KAN-1 moves"
  assert_eq 0 "$(grep -c -e 'comment create --key KAN-2' -e 'transition --key KAN-2' "$STUBS/acli.log")" "KAN-2 gets no comment and no move"
}

test_steps_config_off_and_due() {
  full_direct cf
  printf '{\n  "merge_command": "x",\n  "cleanup": {\n    "remote_branches": "off",\n    "jira": "off",\n    "worktrees": "maybe",\n    "retry_minutes": 30\n  }\n}\n' > "$R/.studio/config.json"
  settle cf
  assert_contains "$TMP/out" "^  skip: remote_branches (cleanup.remote_branches is off)$" "remote deletion off"
  assert_status 0 "A-b stays on origin" -- remote_has A-b
  assert_contains "$TMP/out" "^  skip: jira (cleanup.jira is off)$" "Jira off"
  assert_eq "" "$(cat "$STUBS/acli.log")" "no acli call"
  assert_contains "$TMP/out" '^  left: config cleanup.worktrees must be "on" or "off", got "maybe" — step not run$' "a bad switch is reported"
  assert_status 0 "and its step does not run" -- test -d "$R/.claude/worktrees/A-b"
  # --due: tried just now, retry 30 min: skipped silently.
  : > "$STUBS/gh.log"
  settle cf --due
  assert_eq 3 "$RC" "not due: skipped"
  assert_eq "" "$(cat "$TMP/out" "$STUBS/gh.log")" "silently, with no call"
  printf '%s\n' "$(( $(date +%s) - 1900 ))" > "$D/cleanup.tried"
  settle cf --due
  assert_eq 1 "$RC" "due again after retry_minutes"
  # The sweep prints confirmed records only and skips cleaned ones.
  rm -f "$R/.studio/config.json"; printf '0\n' > "$D/cleanup.tried"
  record un direct main U:U-b:-
  cleanup_sweep "$R" > "$TMP/sw" 2>&1
  assert_contains "$TMP/sw" "^run cf: cleaned up$" "the sweep cleans a confirmed record"
  assert_not_contains "$TMP/sw" "run un" "an unconfirmed one prints nothing"
  assert_file "$R/.studio/runs/un/cleanup.tried" "but it was tried"
  : > "$STUBS/gh.log"; rm -f "$R/.studio/runs/un/cleanup.tried"; rm -rf "$R/.studio/runs/un"
  cleanup_sweep "$R" > "$TMP/sw" 2>&1
  assert_eq "" "$(cat "$TMP/sw" "$STUBS/gh.log")" "a cleaned record is not looked at again"
}

test_steps_archived_record() {
  full_direct ar
  mv "$R/.studio/runs/ar" "$R/.studio/runs/ar.20261026T000000Z"; D="$R/.studio/runs/ar.20261026T000000Z"
  settle ar.20261026T000000Z
  assert_eq 0 "$RC" "an archived record cleans its stories"
  assert_status 2 "its story branches go" -- remote_has A-b
  assert_status 0 "run/ar is left to the newer run of the slug" -- remote_has run/ar
  assert_status 0 "and so is the run worktree" -- test -d "$R/.claude/worktrees/run-ar"
}

# studio-overnight settle: from the project, one record or every one.
test_settle_cli() {
  full_direct sc; record nm direct main N:N-b:-
  ( cd "$R" && sh "$BIN/studio-overnight" settle a b ) > "$TMP/o" 2>&1; assert_eq 2 $? "two slugs: usage"
  ( cd "$R" && sh "$BIN/studio-overnight" settle ../x ) > "$TMP/o" 2>&1; assert_eq 2 $? "a path: usage"
  ( cd "$R" && sh "$BIN/studio-overnight" settle nosuch ) > "$TMP/o" 2>&1; assert_eq 2 $? "no such record: 2"
  assert_contains "$TMP/o" "^run nosuch: no record" "it says so"
  ( cd "$R" && sh "$BIN/studio-overnight" settle --dry-run ) > "$TMP/o" 2>&1; assert_eq 1 $? "bare settle --dry-run: one record not confirmed, 1"
  assert_contains "$TMP/o" "^run nm: not confirmed — N: N-b is not merged into main$" "every record is listed"
  assert_contains "$TMP/o" "^run sc: dry run — nothing would be left$" "the confirmed one too"
  assert_status 0 "the dry run deleted nothing" -- remote_has A-b
  ( cd "$R" && sh "$BIN/studio-overnight" settle sc ) > "$TMP/o" 2>&1; assert_eq 0 $? "settle <slug>: cleaned, 0"
  assert_contains "$TMP/o" "^run sc: cleaned up$" "the tail line"
  rm -rf "$R/.studio/runs/nm"
  ( cd "$R" && sh "$BIN/studio-overnight" settle --all ) > "$TMP/o" 2>&1; assert_eq 0 $? "nothing left to clean: 0"
  assert_eq "every run record is cleaned up" "$(cat "$TMP/o")" "it says so"
}

run_tests test_settle_cli test_direct_progress_in_story_landing test_direct_runner_landed test_direct_hand_landed_backfill test_unmerged_story_untouched \
  test_integration_final_merged_or_open test_direct_progress_required test_live_run_skipped \
  test_steps_full_direct test_steps_dry_run_writes_nothing test_steps_kept_branches_and_worktrees \
  test_steps_tool_failures test_steps_jira_guards test_steps_config_off_and_due test_steps_archived_record
