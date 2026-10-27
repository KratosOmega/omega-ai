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
# gh pr view URL …: prints $STUBS/view (the -q TSV: state head merge). GH_FAIL=1: exit 1. GH_SLEEP: sleep first.
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
  printf 'OPEN\t%s\t-\n' "$FH" > "$STUBS/view"
  pr integration/i1 30 OPEN "$FH" - main
  settle i1
  assert_eq 1 "$RC" "the final PR is open: not cleaned"
  assert_contains "$TMP/out" "^run i1: not confirmed — final PR https://gh.test/pull/30 is not merged (OPEN)" "it names the final PR"
  assert_missing "$D/done" "no done"
  assert_status 0 "C-b is kept" -- remote_has C-b
  # The final PR is merged (a squash: main does not hold the integration head).
  land_squash integration/i1 "integration i1 (#30)"; MF="$MS"
  printf 'MERGED\t%s\t%s\n' "$FH" "$MF" > "$STUBS/view"
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

run_tests test_direct_runner_landed test_direct_hand_landed_backfill test_unmerged_story_untouched \
  test_integration_final_merged_or_open test_direct_progress_required test_live_run_skipped
