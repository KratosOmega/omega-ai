#!/bin/sh
# Lanes suite for studio-overnight's manifest mode (overnight-lanes.sh). A
# stub `claude`, `claude-gd` and `gh` come first on PATH; every project is a
# local clone of a local bare origin. Runs offline.
#
# Harness rules (later tasks copy these patterns):
# - Never prefix a shell-function call with an assignment: `VAR=v run_lanes`
#   leaves VAR set afterwards in macOS /bin/sh (bash 3.2 in POSIX mode). Write
#   `VAR=v; export VAR; run_lanes …; unset VAR`, or use a subshell. A test
#   that changes PATH saves it and restores it.
# - lanes_fixture reads its config variant from LANES_CONFIG and unsets every
#   LANES_* before it returns, so no setting leaks into a later test.
# - run_lanes guards each runner call with a 120 s watchdog; a fired watchdog
#   kills the runner and fails the test. Every background process a test
#   starts is killed before the test returns.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

BIN="$REPO_ROOT/studios/game-dev/bin"
RUNNER="$BIN/studio-overnight"
STATE_BIN="$BIN/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fakebin"
mkdir -p "$FAKE"
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# The stub session: --version as in overnight_test.sh; a session counts
# itself in $CALLS/count and records its argv (T8 adds the scenario part).
cat > "$FAKE/claude" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  [ "${STUB_VERSION_STATUS:-0}" = 0 ] || exit "$STUB_VERSION_STATUS"
  echo "2.1.287 (Claude Code)"; exit 0
fi
n=$(( $(cat "$CALLS/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CALLS/count"
for a in "$@"; do printf '%s\n' "$a"; done > "$CALLS/$n.argv"
exit 0
STUB
printf '#!/bin/sh\nexec claude "$@"\n' > "$FAKE/claude-gd"
# The stub gh: logs its argv; `auth status` succeeds (T10 fills the rest).
cat > "$FAKE/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GH/calls"
case "$1 ${2:-}" in
  "auth status") exit 0 ;;
esac
exit 0
STUB
chmod +x "$FAKE"/*
PATH="$FAKE:$PATH"; STUB_STATE_BIN="$STATE_BIN"
export PATH STUB_STATE_BIN

# calls — the stub session counter (0 when none ran).
calls() { cat "$CALLS/count" 2>/dev/null || echo 0; }
# last_lanes_dir — the newest manifest-mode run directory in $P.
last_lanes_dir() { ls -d "$P"/.studio/reports/overnight-demo-* 2>/dev/null | tail -n 1; }

# lanes_fixture NAME MODE ROW… — ROW is id:deps (deps comma-separated, or
# '-'). A clone $P of the bare origin $TMP/NAME.git, on branch run/demo
# (pushed): one spec with a ## Stories table, one approved and swept plan per
# story, studio state per story at stage plan, task 0/1; .studio/config.json
# from $LANES_CONFIG (default {}); the manifest docs/runs/demo.md with Docs:
# the docs commit, committed and pushed; integration/demo on origin for
# MODE integration. Exports P, MFP, CALLS, GH, TMP_WT; unsets LANES_*.
lanes_fixture() {
  _lf_name="$1"; _lf_mode="$2"; shift 2
  P="$TMP/$_lf_name"; CALLS="$TMP/calls-$_lf_name"; GH="$TMP/gh-$_lf_name"; TMP_WT="$TMP/wts-$_lf_name"
  MFP=docs/runs/demo.md
  export P MFP CALLS GH TMP_WT
  rm -rf "$P" "$CALLS" "$GH" "$TMP_WT" "$TMP/$_lf_name.git"
  mkdir -p "$P" "$CALLS" "$GH" "$TMP_WT"
  git init -q --bare "$TMP/$_lf_name.git"
  _lf_cfg="${LANES_CONFIG:-}"; [ -n "$_lf_cfg" ] || _lf_cfg='{}'
  _lf_spec=docs/game-dev/specs/2026-10-01-demo.md
  ( set -e
    cd "$P"
    git init -q -b main && git commit -q --allow-empty -m init
    git remote add origin "$TMP/$_lf_name.git" && git push -q origin main && git remote set-head origin main
    git checkout -q -b run/demo
    mkdir -p docs/game-dev/specs docs/game-dev/plans docs/runs
    { printf '# Spec: demo\n\n## Acceptance criteria\n\n1. one\n2. two\n3. three\n\n## Stories\n\n'
      printf '| Story | Summary |\n|-------|---------|\n'
      for _r in "$@"; do printf '| %s | story %s |\n' "${_r%%:*}" "${_r%%:*}"; done
    } > "$_lf_spec"
    sh "$STATE_BIN" init >/dev/null
    printf '%s\n' "$_lf_cfg" > .studio/config.json
    for _r in "$@"; do
      _id="${_r%%:*}"; _plan="docs/game-dev/plans/2026-10-01-$_id.md"
      printf '# Plan: %s\n\nStory: %s\n\n## Global Constraints\n\n- none\n\n## Decisions\n\n- none\n\n### Task 1: t\n\nSpec: %s:L1-2\nReview: final\n' \
        "$_id" "$_id" "$_lf_spec" > "$_plan"
      STUDIO_STORY="$_id"; export STUDIO_STORY
      sh "$STATE_BIN" init >/dev/null
      sh "$STATE_BIN" set spec "$_lf_spec"; sh "$STATE_BIN" set plan "$_plan"
      sh "$STATE_BIN" ledger "spec approved $_lf_spec"
      sh "$STATE_BIN" ledger "plan approved $_plan"
      sh "$STATE_BIN" ledger "Decisions swept $_id"
      sh "$STATE_BIN" set stage plan; sh "$STATE_BIN" set task 0/1
      unset STUDIO_STORY
    done
    git add -A && git commit -q -m docs && git push -q origin run/demo
    _docs="$(git rev-parse HEAD)"
    if [ "$_lf_mode" = integration ]; then _target=integration/demo; else _target=main; fi
    { printf '# Run: demo\n\nMode: %s            # or: direct\nTarget: %s\nDocs: %s\nGoal: the demo goal\n\n' "$_lf_mode" "$_target" "$_docs"
      printf '| Story | Branch | Ticket | Spec | Plan | Depends on |\n|-------|--------|--------|------|------|------------|\n'
      for _r in "$@"; do
        _id="${_r%%:*}"; _deps="$(printf '%s' "${_r#*:}" | sed 's/,/, /g')"
        printf '| %s | %s-b | %s | %s | docs/game-dev/plans/2026-10-01-%s.md | %s |\n' "$_id" "$_id" "$_id" "$_lf_spec" "$_id" "$_deps"
      done
    } > "$MFP"
    git add -A && git commit -q -m manifest && git push -q origin run/demo
    [ "$_lf_mode" != integration ] || git push -q origin origin/main:refs/heads/integration/demo
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "lanes_fixture $_lf_name: setup failed"; }
  unset LANES_CONFIG
}

# run_lanes ARGS — `studio-overnight ARGS` in $P: LS_STATUS, and LS_OUT and
# LS_ERR (file paths). A 120 s watchdog kills the runner and fails the test.
run_lanes() {
  LS_STATUS=0; LS_OUT="$TMP/ls.out"; LS_ERR="$TMP/ls.err"
  rm -f "$TMP/ls.timeout"
  ( cd "$P" && exec sh "$RUNNER" "$@" ) > "$LS_OUT" 2> "$LS_ERR" < /dev/null &
  _rl_pid=$!
  ( _sp=; trap 'kill $_sp 2>/dev/null; exit 0' TERM
    sleep 120 & _sp=$!; wait "$_sp"
    : > "$TMP/ls.timeout"
    kill -TERM "$_rl_pid" 2>/dev/null
    sleep 5 & _sp=$!; wait "$_sp"
    kill -KILL "$_rl_pid" 2>/dev/null
  ) > /dev/null 2>&1 &
  _rl_wd=$!
  wait "$_rl_pid"; LS_STATUS=$?
  kill "$_rl_wd" 2>/dev/null; wait "$_rl_wd" 2>/dev/null
  if [ -f "$TMP/ls.timeout" ]; then
    rm -f "$TMP/ls.timeout"
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "run_lanes $*: the runner ran past 120 s and was killed"
  fi
}

test_lanes_chain_rule() {
  lanes_fixture chains integration A:- B:- C:A D:A E:C,B F:E
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "dry run exits 0"
  assert_contains "$LS_OUT" "^chain 1: A C$" "a single dependency on a chain's last story appends"
  assert_contains "$LS_OUT" "^chain 2: B$" "an independent row opens a chain"
  assert_contains "$LS_OUT" "^chain 3 (waits on A): D$" "a fork opens a waiting chain"
  assert_contains "$LS_OUT" "^chain 4 (waits on C,B): E F$" "two dependencies open a waiting chain; its successor appends"
  assert_contains "$LS_OUT" "STUDIO_STORY='A' " "the launch line carries the story (env words are KEY='value')"
  assert_contains "$LS_OUT" "STUDIO_DOCS_REV='[0-9a-f]\{40\}'" "and the docs revision"
  assert_contains "$LS_OUT" "BASH_MAX_TIMEOUT_MS='5400000'" "Bash timeout = session_minutes × 60000"
  assert_contains "$LS_OUT" "'--model' 'sonnet'" "the first unit's model"
  assert_contains "$LS_OUT" "Bash(git push \* main)" "the deny rules are expanded"
  assert_eq 4 "$(grep -c "claude-gd -p" "$LS_OUT")" "one launch line per chain"
  assert_contains "$LS_OUT" "^deny: [0-9][0-9]* rules$" "the deny rule count"
  assert_eq 0 "$(calls)" "dry run launches no session"
  assert_missing "$P/.studio/overnight.lock" "dry run takes no lock"
  assert_eq "" "$(ls -d "$P"/.studio/tmp.* 2>/dev/null)" "dry run leaves no temp dir"
}

test_lanes_manifest_refusals() {
  lanes_fixture refuse direct A:- B:A
  # direct without merge_command; later-row dependency; duplicate id; a '-' cell
  printf '| C | C-b | C | - | - | D |\n| A | A-b | A | x | y | - |\n' >> "$P/$MFP"
  sed -i.bak 's/^Story: B$/Story: X/' "$P/docs/game-dev/plans/2026-10-01-B.md"; rm -f "$P"/docs/game-dev/plans/*.bak
  ( cd "$P" && git commit -qam break && git push -q origin run/demo ) >/dev/null 2>&1
  # Preflight reads plans at the Docs: revision: point Docs: at the break.
  _rev="$(git -C "$P" rev-parse HEAD)"
  sed -i.bak "s/^Docs: .*/Docs: $_rev/" "$P/$MFP"; rm -f "$P/$MFP.bak"
  ( cd "$P" && git commit -qam docs && git push -q origin run/demo ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  for m in "merge_command" "depends on D, which is not an earlier row" "duplicate story A" \
           "C: Spec or Plan is '-'" "B: plan has no 'Story: B' line"; do
    assert_contains "$LS_ERR" "$m" "refusal: $m"
  done
  assert_not_contains "$LS_ERR" "A: plan" "a good plan raises nothing"
}

test_lanes_manifest_header_refusals() {
  lanes_fixture header integration A:-
  sed -i.bak -e 's/^Mode: .*/Mode: sideways/' -e 's/^| A |/| A b |/' "$P/$MFP"; rm -f "$P/$MFP.bak"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "Mode must be integration or direct" "a bad mode"
  assert_contains "$LS_ERR" "story id 'A b'" "a bad id"
  lanes_fixture target integration A:-
  sed -i.bak 's/^Target: .*/Target: main/' "$P/$MFP"; rm -f "$P/$MFP.bak"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a wrong target is refused"
  assert_contains "$LS_ERR" "Target must be integration/demo" "integration's target"
  run_lanes start --dry-run docs/runs/none.md
  assert_eq 2 "$LS_STATUS" "a missing manifest is refused"
  assert_contains "$LS_ERR" "no manifest at docs/runs/none.md" "names the path"
}

test_lanes_preflight_story_checks() {
  lanes_fixture pstory integration A:- B:-
  rm "$P/.studio/stories/B.md"
  printf -- '- 2026-10-01 Stop: x\n' >> "$P/.studio/ledger/A.md"
  git -C "$P" push -q origin --delete integration/demo
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "B: no story file" "a missing story file"
  assert_contains "$LS_ERR" "A: uncommitted ledger change" "a dirty story ledger in START_DIR"
  assert_contains "$LS_ERR" "origin/integration/demo does not exist" "integration branch missing"
}

test_lanes_preflight_story_state() {
  lanes_fixture pstate integration A:- B:-
  ( cd "$P" && STUDIO_STORY=A sh "$STATE_BIN" set stage idle
    sed -i.bak '/Decisions swept B/d; /plan approved/d' .studio/ledger/B.md && rm -f .studio/ledger/B.md.bak
    git commit -qam x && git push -q origin run/demo ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "A: stage idle" "idle without a shipped line"
  assert_contains "$LS_ERR" "B: no 'plan approved" "plan approval"
  assert_contains "$LS_ERR" "B: no 'Decisions swept B'" "the question sweep"
}

test_lanes_docs_unreachable() {
  lanes_fixture docs integration A:-
  sed -i.bak 's/^Docs: .*/Docs: 0123456789abcdef0123456789abcdef01234567/' "$P/$MFP"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "Docs: .* is not on origin/run/demo" "the docs revision must be on origin"
}

test_lanes_git_too_old() {
  lanes_fixture oldgit integration A:-
  mkdir -p "$TMP/oldgit-bin"
  printf '#!/bin/sh\ncase "$1" in --version|version) echo "git version 2.30.1";; *) exec %s "$@";; esac\n' "$(command -v git)" > "$TMP/oldgit-bin/git"
  chmod +x "$TMP/oldgit-bin/git"
  _saved_path="$PATH"; PATH="$TMP/oldgit-bin:$PATH"; export PATH
  run_lanes start --dry-run "$MFP"
  PATH="$_saved_path"; export PATH
  assert_eq 2 "$LS_STATUS" "refused"
  assert_contains "$LS_ERR" "git 2.38 or newer" "git version floor"
}

test_lanes_sourced_only() {
  assert_status 2 "overnight-lanes.sh refuses to run directly" -- sh "$REPO_ROOT/studios/game-dev/bin/overnight-lanes.sh"
  _out="$(sh "$REPO_ROOT/studios/game-dev/bin/overnight-lanes.sh" 2>&1)"
  assert_eq "overnight-lanes.sh: sourced by studio-overnight" "$_out" "and says why"
}

run_tests test_lanes_chain_rule test_lanes_manifest_refusals test_lanes_manifest_header_refusals \
  test_lanes_preflight_story_checks test_lanes_preflight_story_state test_lanes_docs_unreachable \
  test_lanes_git_too_old test_lanes_sourced_only
