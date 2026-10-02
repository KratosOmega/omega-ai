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

# The stub session (harness part 2). `--version` as in overnight_test.sh.
# Every other call is one unit, keyed by $STUDIO_STORY and the prompt:
# - Numbering: a global call number n under a `mkdir $CALLS/n.lock` spin
#   ($CALLS/count), and a per-story, per-kind number m. Each call records
#   $CALLS/<n>.argv (one element per line), .story, .prompt, .pid, .pwd,
#   .env (OMEGA_AUTOPILOT, STUDIO_RUN, STUDIO_DOCS_REV, STUDIO_REPAIR,
#   STUDIO_GATE_HELD as KEY=value lines), .t0 and .t1 (epoch seconds).
# - Scenario: line m of $SCEN/<id> (unit prompts), $SCEN/<id>.land
#   (`--land`), $SCEN/progress (`--progress`) or $SCEN/final-repair
#   (`/omega:integration repair`). A missing file or line means `auto`.
# - A line is a `;`-separated list of actions, run in order. `auto` runs
#   last unless the line names a terminal action (stop, noop, hang, exit,
#   repair, fakerepair, progress); naming `auto` itself changes nothing.
# - Actions:
#   auto            one well-behaved unit, as execute §0/§8 would: §0 adds
#                   the story worktree $TMP_WT/<Branch> (--no-track; from
#                   origin/<Branch> when it exists only there, else a new
#                   branch from origin/<Target> with the Docs revision's
#                   spec, plan and story ledger checked out and committed),
#                   sets branch and stage execute; on an existing branch it
#                   syncs spec and plan from $STUDIO_DOCS_REV and commits
#                   only when they differ (D3), never the ledger. Then the
#                   next unit by state: a task commits <id>-T<k>.txt (or the
#                   conflict file), ledgers `T<k> complete` (committed),
#                   pushes, sets task k/N; the final review ledgers `final
#                   review done` (committed, pushed); the finish ledgers
#                   `shipped <Branch>` (integration) or `shipped <url>` from
#                   `gh pr create --draft` (direct), commits and pushes it,
#                   then sets stage idle and task -.
#   conflict <file> modifier: auto's task commit writes <file> (content: the
#                   story id) instead of <id>-T<k>.txt
#   cost <usd>      the result event's total_cost_usd (default 1)
#   sleep <s>       sleep s seconds
#   gate <s>        studio-gate studio-test around a sleep of s seconds,
#                   logging `s|e <story> <epoch>` lines to $CALLS/gate.iv
#   stop <reason>   terminal: ledgers `Stop: <reason>` (uncommitted) in the
#                   story worktree, or in the cwd when there is none
#   noop            terminal: does nothing (no progress)
#   hang            terminal: never returns
#   exit <code>     terminal: exits <code> without working
#   repair          terminal (`--land`): in the story worktree, fetch, merge
#                   origin/<Target> with -X theirs, ledger `Repair: merged
#                   target`, commit, push
#   fakerepair      terminal: ledgers `Repair: merged target` and commits it
#                   in the story worktree; no merge, no push
#   progress        terminal (`--progress`): appends a line to PROGRESS.md in
#                   the cwd and commits "docs(progress): demo"
cat > "$FAKE/claude" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  [ "${STUB_VERSION_STATUS:-0}" = 0 ] || exit "$STUB_VERSION_STATUS"
  echo "2.1.287 (Claude Code)"; exit 0
fi
id="${STUDIO_STORY:-}"; prompt="${2:-}"
case "$prompt" in
  *--land*) kind="$id.land" ;;
  *--progress*) kind=progress ;;
  *'/omega:integration repair'*) kind=final-repair ;;
  *) kind="$id" ;;
esac
while ! mkdir "$CALLS/n.lock" 2>/dev/null; do sleep 0.1; done
n=$(( $(cat "$CALLS/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS/count"
m=$(( $(cat "$CALLS/m-$kind" 2>/dev/null || echo 0) + 1 )); echo "$m" > "$CALLS/m-$kind"
rmdir "$CALLS/n.lock"
date +%s > "$CALLS/$n.t0"
echo "$$" > "$CALLS/$n.pid"
for a in "$@"; do printf '%s\n' "$a"; done > "$CALLS/$n.argv"
printf '%s\n' "$id" > "$CALLS/$n.story"
printf '%s\n' "$prompt" > "$CALLS/$n.prompt"
pwd -P > "$CALLS/$n.pwd"
printf 'OMEGA_AUTOPILOT=%s\nSTUDIO_RUN=%s\nSTUDIO_DOCS_REV=%s\nSTUDIO_REPAIR=%s\nSTUDIO_GATE_HELD=%s\n' \
  "${OMEGA_AUTOPILOT:-}" "${STUDIO_RUN:-}" "${STUDIO_DOCS_REV:-}" "${STUDIO_REPAIR:-}" "${STUDIO_GATE_HELD:-}" > "$CALLS/$n.env"
line="$(sed -n "${m}p" "$SCEN/$kind" 2>/dev/null)"

st() { sh "$STUB_STATE_BIN" "$@"; }
# sg ARGS — git ARGS, retried on a lock it could not take (execute's rule).
sg() {
  _i=0
  while :; do
    _e="$(git "$@" 2>&1 >/dev/null)" && return 0
    if [ "$_i" -lt 5 ] && printf '%s\n' "$_e" | grep -Eq 'could not lock|cannot lock ref|Unable to create'; then
      _i=$((_i + 1)); sleep 1; continue
    fi
    printf '%s\n' "$_e" >&2; return 1
  done
}
hdr() { sed -n "s/^$1:[ 	]*//p" "$STUDIO_RUN" | head -n 1 | sed -e 's/[ 	]#.*$//' -e 's/[ 	]*$//'; }
TARGET="$(hdr Target)"; MODE="$(hdr Mode)"
BRANCH="$(awk -F'|' -v id="$id" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  /^\|/ { for (i = 1; i <= NF; i++) c[i] = trim($i)
          if (!hdr) { for (i = 1; i <= NF; i++) col[c[i]] = i; if ("Story" in col) hdr = 1; next }
          if (c[col["Story"]] == id) { print c[col["Branch"]]; exit } }' "$STUDIO_RUN" 2>/dev/null)"
story_wt() { _w="$(st worktree 2>/dev/null)"; [ -n "$_w" ] && [ -d "$_w" ] && printf '%s\n' "$_w"; }
commit_ledger() { git add ".studio/ledger/$id.md" && git commit -qm "ledger($id): $1"; }

auto() {
  spec="$(st get spec)"; plan="$(st get plan)"
  wt="$(story_wt)"
  if [ -z "$wt" ]; then
    sg fetch -q origin
    wt="$TMP_WT/$BRANCH"
    if git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then
      sg worktree add -q "$wt" "$BRANCH"; fresh=0
    elif git rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null; then
      sg worktree add -q --no-track -b "$BRANCH" "$wt" "origin/$BRANCH"; fresh=0
    else
      sg worktree add -q --no-track -b "$BRANCH" "$wt" "origin/$TARGET"; fresh=1
    fi
    if [ "$fresh" = 1 ]; then
      ( cd "$wt" && git checkout -q "$STUDIO_DOCS_REV" -- "$spec" "$plan" ".studio/ledger/$id.md" \
          && git commit -qm "docs($id): run docs" )
    fi
    st set branch "$BRANCH"; st set stage execute
  fi
  cd "$wt" || exit 9
  git checkout -q "$STUDIO_DOCS_REV" -- "$spec" "$plan"
  git diff --cached --quiet || git commit -qm "docs($id): plan at run docs $(printf '%.7s' "$STUDIO_DOCS_REV")"
  task="$(st get task)"; k="${task%/*}"; N="${task#*/}"
  case "$k" in ''|-|*[!0-9]*) k=0 ;; esac
  case "$N" in ''|-|*[!0-9]*) N=1 ;; esac
  frd="$(grep -c 'final review done$' ".studio/ledger/$id.md" 2>/dev/null)"
  if [ "$k" -lt "$N" ]; then
    k=$((k + 1)); f="${conflict:-$id-T$k.txt}"
    printf '%s\n' "$id" > "$f"; git add "$f"; git commit -qm "feat($id): T$k"
    st ledger "T$k complete"; commit_ledger "T$k complete"
    sg push -q origin "$BRANCH"
    st set task "$k/$N"
  elif [ "${frd:-0}" -eq 0 ]; then
    st ledger "final review done"; commit_ledger "final review done"
    sg push -q origin "$BRANCH"
  else
    sg push -q origin "$BRANCH"
    if [ "$MODE" = direct ]; then
      shipped="$(gh pr create --draft --base main --head "$BRANCH" --title "$id" --body "$id")"
    else
      shipped="$BRANCH"
    fi
    st ledger "shipped $shipped"; commit_ledger shipped
    sg push -q origin "$BRANCH"
    st set stage idle; st set task -
  fi
}

cost=1; code=0; terminal=0; conflict=""
old_ifs="$IFS"; IFS=';'
set -f; set -- $line; set +f
IFS="$old_ifs"
for act in "$@"; do
  act="$(printf '%s' "$act" | sed 's/^ *//; s/ *$//')"
  case "$act" in
    ''|auto)          ;;
    "conflict "*)     conflict="${act#conflict }" ;;
    "cost "*)         cost="${act#cost }" ;;
    "sleep "*)        sleep "${act#sleep }" ;;
    "gate "*)         s="${act#gate }"
                      sh "$(dirname "$STUB_STATE_BIN")/studio-gate" studio-test -- sh -c \
                        "echo s $id \$(date +%s) >> '$CALLS/gate.iv'; sleep $s; echo e $id \$(date +%s) >> '$CALLS/gate.iv'" ;;
    "stop "*)         terminal=1; w="$(story_wt)"
                      ( [ -z "$w" ] || cd "$w"; st ledger "Stop: ${act#stop }" ) ;;
    noop)             terminal=1 ;;
    hang)             terminal=1; while :; do sleep 1; done ;;
    "exit "*)         terminal=1; code="${act#exit }" ;;
    repair)           terminal=1; w="$(story_wt)"
                      ( cd "$w" && sg fetch -q origin && git merge -q --no-edit -X theirs "origin/$TARGET" \
                        && st ledger "Repair: merged target" && commit_ledger repair && sg push -q origin "$BRANCH" ) ;;
    fakerepair)       terminal=1; w="$(story_wt)"
                      ( cd "$w" && st ledger "Repair: merged target" && commit_ledger repair ) ;;
    progress)         terminal=1
                      printf -- '- %s: demo progress\n' "$(date +%Y-%m-%d)" >> PROGRESS.md
                      git add PROGRESS.md && git commit -qm "docs(progress): demo" ;;
    *)                echo "stub: unknown action '$act'" >&2 ;;
  esac
done
[ "$terminal" = 1 ] || ( auto ) >&2
printf '{"type":"system","subtype":"init"}\n'
[ -z "$cost" ] || printf '{"type":"result","subtype":"success","total_cost_usd":%s}\n' "$cost"
date +%s > "$CALLS/$n.t1"
exit "$code"
STUB
printf '#!/bin/sh\nexec claude "$@"\n' > "$FAKE/claude-gd"
# The stub gh: logs its argv; `auth status` succeeds; `pr create` prints a
# PR url numbered by a counter (T10 fills the rest).
cat > "$FAKE/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GH/calls"
case "$1 ${2:-}" in
  "auth status") exit 0 ;;
  "pr create")
    _n=$(( $(cat "$GH/pr-count" 2>/dev/null || echo 0) + 1 )); echo "$_n" > "$GH/pr-count"
    echo "https://example.test/pull/$_n" ;;
esac
exit 0
STUB
# A fake caffeinate: lives until the -w pid dies (no real keep-awake in tests).
printf '#!/bin/sh\nwhile kill -0 "$3" 2>/dev/null; do sleep 1; done\n' > "$FAKE/caffeinate"
chmod +x "$FAKE"/*
PATH="$FAKE:$PATH"; STUB_STATE_BIN="$STATE_BIN"
export PATH STUB_STATE_BIN
# Default for later tasks: the final step's full gate is `true` (T11); a test
# that needs another gate exports its own and restores this afterwards.
STUDIO_OVERNIGHT_GATE_CMD=true; export STUDIO_OVERNIGHT_GATE_CMD

# calls — the stub session counter (0 when none ran).
calls() { cat "$CALLS/count" 2>/dev/null || echo 0; }
# last_lanes_dir — the newest manifest-mode run directory in $P.
last_lanes_dir() { ls -d "$P"/.studio/reports/overnight-demo-* 2>/dev/null | tail -n 1; }

# lanes_fixture NAME MODE ROW… — ROW is id:deps (deps comma-separated, or
# '-'). A clone $P of the bare origin $TMP/NAME.git, on branch run/demo
# (pushed): one spec with a ## Stories table, one approved and swept plan per
# story, studio state per story at stage plan, task 0/1; .studio/config.json
# from $LANES_CONFIG (default {}); LANES_CELLS=dash writes '-' in every Spec and
# Plan cell; LANES_PROGRESS=1 puts a PROGRESS.md on main (default: none); the
# manifest docs/runs/demo.md with Docs: the docs commit, committed and pushed;
# integration/demo on origin for MODE integration. Exports P, MFP, CALLS, GH,
# TMP_WT and SCEN (an empty scenario dir: every unit is `auto`); unsets LANES_*.
lanes_fixture() {
  _lf_name="$1"; _lf_mode="$2"; shift 2
  P="$TMP/$_lf_name"; CALLS="$TMP/calls-$_lf_name"; GH="$TMP/gh-$_lf_name"; TMP_WT="$TMP/wts-$_lf_name"
  SCEN="$TMP/scen-$_lf_name"
  MFP=docs/runs/demo.md
  export P MFP CALLS GH TMP_WT SCEN
  rm -rf "$P" "$CALLS" "$GH" "$TMP_WT" "$SCEN" "$TMP/$_lf_name.git"
  mkdir -p "$P" "$CALLS" "$GH" "$TMP_WT" "$SCEN"
  git init -q --bare "$TMP/$_lf_name.git"
  _lf_cfg="${LANES_CONFIG:-}"; [ -n "$_lf_cfg" ] || _lf_cfg='{}'
  _lf_cells="${LANES_CELLS:-}"; _lf_progress="${LANES_PROGRESS:-}"
  _lf_spec=docs/game-dev/specs/2026-10-01-demo.md
  ( set -e
    cd "$P"
    git init -q -b main
    if [ "$_lf_progress" = 1 ]; then
      printf '# Progress\n' > PROGRESS.md && git add PROGRESS.md && git commit -q -m init
    else
      git commit -q --allow-empty -m init
    fi
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
        if [ "$_lf_cells" = dash ]; then
          printf '| %s | %s-b | %s | - | - | %s |\n' "$_id" "$_id" "$_id" "$_deps"
        else
          printf '| %s | %s-b | %s | %s | docs/game-dev/plans/2026-10-01-%s.md | %s |\n' "$_id" "$_id" "$_id" "$_lf_spec" "$_id" "$_deps"
        fi
      done
    } > "$MFP"
    git add -A && git commit -q -m manifest && git push -q origin run/demo
    [ "$_lf_mode" != integration ] || git push -q origin origin/main:refs/heads/integration/demo
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "lanes_fixture $_lf_name: setup failed"; }
  unset LANES_CONFIG LANES_CELLS LANES_PROGRESS
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

test_lanes_next() {
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nxt integration A:- B:A C:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-A.md\n- 2026-10-01 Decisions swept A\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-B.md\n' > "$P/.studio/ledger/demo.md"
  grep -v '^| C |' "$P/docs/game-dev/specs/2026-10-01-demo.md" > "$TMP/s" && mv "$TMP/s" "$P/docs/game-dev/specs/2026-10-01-demo.md"
  rm -f "$P/docs/game-dev/plans/2026-10-01-C.md"
  ( cd "$P" && git add -A && git commit -qm planning-state ) >/dev/null 2>&1
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next exits 0"
  assert_contains "$LS_OUT" "^A  planned  spec=docs/game-dev/specs/2026-10-01-demo.md  plan=docs/game-dev/plans/2026-10-01-A.md$" "A resolved and planned"
  assert_contains "$LS_OUT" "^B  plan  " "B lacks its sweep line"
  assert_contains "$LS_OUT" "^C  brainstorm  spec=-  plan=-$" "C has no spec row"
  assert_contains "$LS_OUT" "^next: /game-dev:brainstorm C$" "brainstorm comes before plan"
  printf '%s\n' "$MFP" > "$P/.studio/run"
  run_lanes next
  assert_contains "$LS_OUT" "^next: /game-dev:brainstorm C$" "no argument reads .studio/run"
  rm "$P/.studio/run"; run_lanes next
  assert_eq 2 "$LS_STATUS" "no pointer and no argument exits 2"
  assert_contains "$LS_ERR" "no run manifest (.studio/run)" "and says why"
}
test_lanes_next_all_planned_and_ambiguous() {
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nxt2 integration A:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-A.md\n- 2026-10-01 Decisions swept A\n' > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^next: /omega:autopilot$" "every row planned"
  cp "$P/docs/game-dev/plans/2026-10-01-A.md" "$P/docs/game-dev/plans/2026-10-02-A2.md"
  ( cd "$P" && git add -A && git commit -qm dup ) >/dev/null 2>&1
  run_lanes next "$MFP"
  assert_eq 2 "$LS_STATUS" "two plans for one story"
  assert_contains "$LS_ERR" "A matches two plans" "the refusal names both"
}
test_lanes_next_plan_before_autopilot() {
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nxt3 integration A:- B:A
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-A.md\n- 2026-10-01 Decisions swept A\n' > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^B  plan  " "B has no plan approval"
  assert_contains "$LS_OUT" "^next: /game-dev:plan B$" "plan comes when nothing needs brainstorming"
  _before="$(cd "$P" && git status --porcelain | wc -l | tr -d ' ')"
  run_lanes next "$MFP"
  assert_eq "$_before" "$(cd "$P" && git status --porcelain | wc -l | tr -d ' ')" "next writes nothing"
}

# story_calls ID — the stub call numbers of story ID, one per line.
story_calls() { grep -lx "$1" "$CALLS"/*.story 2>/dev/null | sed 's#.*/\([0-9]*\)\.story$#\1#'; }

test_lanes_two_independent_to_landed() {
  lanes_fixture two integration A:- B:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "both stories land (stub landing)"
  for id in A B; do
    assert_contains "$(last_lanes_dir)/stories/$id" "^landed [0-9a-f]\{40\}$" "$id ends landed with its branch head"
    assert_eq 3 "$(story_calls "$id" | wc -l | tr -d ' ')" "$id: one launch per unit (T1, final review, finish)"
    assert_contains "$P/.studio/runs/demo/landed.tsv" "^$id	integration/demo	[0-9a-f]\{40\}	[0-9]\{10\}$" "$id: a D27 landed.tsv line"
  done
  assert_eq 2 "$(ls -d "$(last_lanes_dir)"/lanes/* | wc -l | tr -d ' ')" "max_lanes 0 = one lane per chain"
  assert_contains "$(last_lanes_dir)/manifest.md" "^# Run: demo$" "the run keeps its copy of the manifest"
  assert_eq 2 "$(ls "$(last_lanes_dir)"/claims | wc -l | tr -d ' ')" "each chain claimed once"
  assert_contains "$(last_lanes_dir)/lanes/1/units.tsv" "	[AB]-T1	" "units.tsv labels carry the story id"
  _stems="$(ls "$(last_lanes_dir)"/lanes/*/ | grep -c '^1-[AB]-T1\.jsonl$')"
  assert_eq 2 "$_stems" "unit files are <n>-<id>-<label>.jsonl"
  assert_missing "$P/.studio/overnight.lock" "the run releases its lock"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: done$" "the report names the ending"
}
test_lanes_max_lanes_one_serializes() {
  LANES_CONFIG='{"overnight": {"max_lanes": 1}}'; export LANES_CONFIG
  lanes_fixture one integration A:- B:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "both land"
  assert_eq 1 "$(ls -d "$(last_lanes_dir)"/lanes/* | wc -l | tr -d ' ')" "one lane"
  # every B unit starts after every A unit ended
  a_end="$(for n in $(story_calls A); do cat "$CALLS/$n.t1"; done | sort -n | tail -n 1)"
  b_start="$(for n in $(story_calls B); do cat "$CALLS/$n.t0"; done | sort -n | head -n 1)"
  assert_eq 1 "$([ -n "$a_end" ] && [ -n "$b_start" ] && [ "$b_start" -ge "$a_end" ] && echo 1 || echo 0)" "the one lane runs the chains one after another"
}
test_lanes_models_and_env() {
  LANES_CONFIG='{"overnight": {"model_task": "t-m", "model_final": "f-m", "model_finish": "x-m"}}'; export LANES_CONFIG
  lanes_fixture models integration A:-
  # A runner started under a gate holder must still not pass it on (D17).
  STUDIO_GATE_HELD=12345; export STUDIO_GATE_HELD
  run_lanes start "$MFP"
  unset STUDIO_GATE_HELD
  for pair in "1 t-m" "2 f-m" "3 x-m"; do set -- $pair
    assert_eq "$2" "$(sed -n 4p "$CALLS/$1.argv" 2>/dev/null)" "call $1 runs with --model $2"
  done
  assert_contains "$CALLS/1.env" "^STUDIO_RUN=.*/overnight-demo-[0-9-]*/manifest.md$" "STUDIO_RUN names the run's copy of the manifest"
  assert_contains "$CALLS/1.env" "^STUDIO_DOCS_REV=[0-9a-f]\{40\}$" "the docs revision"
  assert_contains "$CALLS/1.env" "^OMEGA_AUTOPILOT=1$" "autopilot is on"
  assert_contains "$CALLS/1.env" "^STUDIO_GATE_HELD=$" "STUDIO_GATE_HELD never reaches a session"
  assert_eq "$P" "$(cat "$CALLS/1.pwd" 2>/dev/null)" "a unit starts in START_DIR"
  assert_eq "/game-dev:execute --one" "$(cat "$CALLS/1.prompt" 2>/dev/null)" "the unit prompt"
}
test_lanes_story_stop_isolated() {
  lanes_fixture stopone integration A:- B:-
  printf 'stop broken fixture\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_eq 1 "$LS_STATUS" "a stopped story makes the run partial"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: broken fixture$" "A stopped with its reason"
  assert_contains "$(last_lanes_dir)/stories/B" "^landed " "B still landed"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: partial: 1 landed, 1 stopped, 0 skipped$" "the ending counts the stories"
}
test_lanes_budget() {
  LANES_CONFIG='{"overnight": {"run_usd": 30, "session_usd": 25}}'; export LANES_CONFIG
  lanes_fixture budget integration A:-
  printf 'cost 10\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: run budget$" "spent 10 + 25 > 30 stops before the second launch"
  assert_eq 1 "$(calls)" "exactly one launch"
}
test_lanes_budget_sums_all_lanes() {
  LANES_CONFIG='{"overnight": {"run_usd": 40, "session_usd": 25}}'; export LANES_CONFIG
  lanes_fixture budget2 integration A:- B:-
  # A's T1 costs 10 at once, then its final review runs 6 s; B's T1 costs 10
  # and ends at about 3 s. B alone (10 + 25 = 35) is under 40; with A's 10 it
  # is not, so B stops after one launch on the run-wide sum.
  printf 'cost 10\nsleep 6\n' > "$SCEN/A"; printf 'sleep 3; cost 10\n' > "$SCEN/B"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: run budget$" "B stops on the run-wide spend"
  assert_eq 1 "$(story_calls B | wc -l | tr -d ' ')" "B launched once"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: run budget$" "A stops once the sum passes too"
}
test_lanes_overhead() {
  lanes_fixture overhead integration A:-
  run_lanes start "$MFP"
  # A missing stamp counts as a huge gap (t0 9999999999, t1 0), never a pass.
  g1=$(( $(cat "$CALLS/2.t0" 2>/dev/null || echo 9999999999) - $(cat "$CALLS/1.t1" 2>/dev/null || echo 0) ))
  g2=$(( $(cat "$CALLS/3.t0" 2>/dev/null || echo 9999999999) - $(cat "$CALLS/2.t1" 2>/dev/null || echo 0) ))
  g="$g1"; [ "$g2" -ge "$g" ] || g="$g2"   # min of two: one slow sample under load is not overhead
  assert_eq 1 "$([ "$g" -le 5 ] && echo 1 || echo 0)" "runner overhead between units <= 5 s (min of two: ${g}s)"
}
test_lanes_docs_revision() {
  lanes_fixture docsrev integration A:- B:A
  # B's branch exists only on origin, half-begun: a stale plan and a ledger
  # line of its own. §0 adopts it (D10), syncs spec and plan (D3) and keeps
  # the ledger.
  _bb="$TMP/bb-docsrev"
  ( cd "$P" && git worktree add -q --no-track -b B-b "$_bb" origin/integration/demo \
    && cd "$_bb" && git checkout -q run/demo -- docs/game-dev .studio/ledger/B.md \
    && printf 'STALE\n' >> docs/game-dev/plans/2026-10-01-B.md \
    && printf -- '- 2026-10-01 Ruling: kept on the branch\n' >> .studio/ledger/B.md \
    && git add -A && git commit -qm b-start && git push -q origin B-b \
    && cd "$P" && git worktree remove --force "$_bb" && git branch -q -D B-b ) >/dev/null 2>&1
  printf 'sleep 3\n' > "$SCEN/A"
  ( cd "$P" && sleep 1 && printf 'CHANGED\n' >> docs/game-dev/plans/2026-10-01-B.md && git commit -qam mid-run ) >/dev/null 2>&1 &
  run_lanes start "$MFP"; wait
  assert_eq 0 "$LS_STATUS" "both land"
  b_wt="$(git -C "$P" worktree list --porcelain | sed -n 's/^worktree //p' | grep '/B-b$')"
  [ -n "$b_wt" ] || b_wt="$TMP/no-B-b-worktree"
  assert_not_contains "$b_wt/docs/game-dev/plans/2026-10-01-B.md" "CHANGED" "a later story reads docs from the Docs revision only"
  assert_not_contains "$b_wt/docs/game-dev/plans/2026-10-01-B.md" "STALE" "an existing branch's plan is synced from the Docs revision"
  assert_contains "$b_wt/.studio/ledger/B.md" "Ruling: kept on the branch" "an existing branch's ledger is never overwritten"
  assert_eq 1 "$(git -C "$P" log --format=%s refs/remotes/origin/B-b 2>/dev/null | grep -c '^docs(B): plan at run docs ')" "the sync commits once"
}
# Last: no process any test started is still alive.
test_lanes_no_orphans() {
  _left="$(pgrep -f "$TMP" 2>/dev/null; pgrep -f "$RUNNER" 2>/dev/null)"
  assert_eq "" "$_left" "no stub session, lane or runner outlives its test"
}

run_tests test_lanes_chain_rule test_lanes_manifest_refusals test_lanes_manifest_header_refusals \
  test_lanes_preflight_story_checks test_lanes_preflight_story_state test_lanes_docs_unreachable \
  test_lanes_git_too_old test_lanes_sourced_only test_lanes_next \
  test_lanes_next_all_planned_and_ambiguous test_lanes_next_plan_before_autopilot \
  test_lanes_two_independent_to_landed test_lanes_max_lanes_one_serializes test_lanes_models_and_env \
  test_lanes_story_stop_isolated test_lanes_budget test_lanes_budget_sums_all_lanes test_lanes_overhead \
  test_lanes_docs_revision test_lanes_no_orphans
