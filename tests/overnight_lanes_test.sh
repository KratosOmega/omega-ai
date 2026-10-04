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
# The runner's user-level registry lives under $HOME: never the real one.
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
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
#   (`--land`), $SCEN/<id>.gate (`--gate-repair`), $SCEN/progress
#   (`--progress`) or $SCEN/final-repair
#   (`/omega:integration repair`). A missing file or line means `auto`.
# - A line is a `;`-separated list of actions, run in order. `auto` runs
#   last unless the line names a terminal action (stop, noop, hang, exit,
#   repair, fakerepair, gaterepair, progress); naming `auto` itself changes
#   nothing.
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
#   bggate <s>      studio-gate studio-test around a sleep of s seconds,
#                   started in the background in its own session and left
#                   running (the sleep's pid in $CALLS/bggate.pid)
#   emit <file>     the file's lines on stdout (the unit's stream-json)
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
#   gaterepair      terminal (`--gate-repair`): in the story worktree, ledger
#                   `Repair: gate — fixed`, commit, push
#   gatelog         modifier: writes a studio-test log, .studio/reports/
#                   test-<stamp>.log, in the story worktree
#   progress        terminal (`--progress`): appends a line to
#                   docs/game-dev/PROGRESS.md in the cwd and commits
#                   "docs(progress): demo"
#   mergemain       terminal (final repair): in the cwd, merge origin/main
#                   with -X theirs (resolving the final step's conflict)
#   fixgate         terminal (final repair): commits the file `fixed` in the
#                   cwd (a gate that tests for it turns green)
#   dirtyfix        terminal (final unit): writes the file `fixed` in the cwd
#                   and commits nothing (uncommitted work)
#   breakrow        terminal (final unit): makes the run's final/units.tsv
#                   a directory, so the runner's own row write fails (a
#                   runner error, exit 3)
#   ruling <text>   modifier: ledgers <text> in the story worktree and
#                   commits it, before auto runs
#   inbox           modifier: the operator-inbox hook as a startup session
#                   runs it, its output in $CALLS/<n>.inbox
#   say <text>      modifier: `studio-overnight say <id> -- <text>`
cat > "$FAKE/claude" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  [ "${STUB_VERSION_STATUS:-0}" = 0 ] || exit "$STUB_VERSION_STATUS"
  echo "2.1.287 (Claude Code)"; exit 0
fi
id="${STUDIO_STORY:-}"; prompt="${2:-}"
case "$prompt" in
  *--gate-repair*) kind="$id.gate" ;;
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
env > "$CALLS/$n.fullenv"
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
    "bggate "*)       s="${act#bggate }"
                      # What the 2026-10-02 finish did: a gate started in the
                      # background, in its own session (as the Bash tool's
                      # shells are), left running when the session ends.
                      perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' sh "$(dirname "$STUB_STATE_BIN")/studio-gate" studio-test -- \
                        sh -c "echo \$\$ > '$CALLS/bggate.pid'; sleep $s" < /dev/null > /dev/null 2>&1 &
                      while [ ! -s "$CALLS/bggate.pid" ]; do sleep 0.1; done ;;
    "emit "*)         cat "${act#emit }" ;;
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
    gaterepair)       terminal=1; w="$(story_wt)"
                      ( cd "$w" && st ledger "Repair: gate — fixed" && commit_ledger gate-repair && sg push -q origin "$BRANCH" ) ;;
    gatelog)          w="$(story_wt)"
                      mkdir -p "$w/.studio/reports" && echo "FAIL test_no_line_is_absurdly_long" > "$w/.studio/reports/test-$(date +%Y%m%d-%H%M%S).log" ;;
    progress)         terminal=1
                      printf -- '- %s: demo progress\n' "$(date +%Y-%m-%d)" >> docs/game-dev/PROGRESS.md
                      git add docs/game-dev/PROGRESS.md && git commit -qm "docs(progress): demo" ;;
    mergemain)        terminal=1; git merge -q --no-edit -X theirs origin/main >&2 ;;
    fixgate)          terminal=1; : > fixed; git add fixed && git commit -qm "fix: the gate" ;;
    dirtyfix)         terminal=1; : > fixed ;;
    breakrow)         terminal=1; mkdir -p "$(dirname "$STUDIO_RUN")/final/units.tsv" ;;
    "ruling "*)       w="$(story_wt)"
                      ( cd "$w" && st ledger "${act#ruling }" && commit_ledger ruling ) ;;
    inbox)            printf '{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}' \
                        | sh "$STUB_PLUGIN/hooks/operator-inbox.sh" > "$CALLS/$n.inbox" ;;
    "say "*)          sh "$STUB_RUNNER" say "$id" -- "${act#say }" > /dev/null 2>&1 ;;
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
# The stub gh (harness part 3): every call's argv is logged to $GH/calls.
# PRs live as files $GH/pr-<n> of key=value lines (head, base, state
# OPEN|MERGED, draft 1|0, oid, title; a later line wins), numbered by
# $GH/pr-count.
# - auth status: succeeds.
# - pr create [--draft] --base B --head H [--title T] [--body…]: a new PR,
#   prints https://gh.test/pr/<n>; --body-file F's content is saved as
#   $GH/body-<n>.
# - pr view <n|head> --json …: {"state":…,"isDraft":…,"number":n,
#   "mergeCommit":{"oid":…}} (mergeCommit null before a merge); no PR -> exit 1.
#   A $GH/pr-<n>.pending file is appended to the PR file after the view (a
#   GitHub read that lags the merge by one view).
# - pr ready <n>: draft=0. pr edit <n> [--title T] [--body-file F]: records
#   the title, and F's content in $GH/pr-<n>.body and $GH/body-<n>.
# - pr list --head H --base B --state open --json number,url: [] or one object.
cat > "$FAKE/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GH/calls"
get() { sed -n "s/^$1=//p" "$2" | tail -n 1; }
# pr_file N|HEAD — the PR file for a number, or the newest PR with that head.
pr_file() {
  case "$1" in
    ''|*[!0-9]*) _pf=""
       for _f in "$GH"/pr-[0-9]*; do
         case "$_f" in *.body) continue ;; esac
         [ -f "$_f" ] && [ "$(get head "$_f")" = "$1" ] && _pf="$_f"
       done
       [ -n "$_pf" ] && printf '%s\n' "$_pf" ;;
    *) [ -f "$GH/pr-$1" ] && printf '%s\n' "$GH/pr-$1" ;;
  esac
}
case "$1 ${2:-}" in
  "auth status") exit 0 ;;
  "pr create")
    shift 2; _d=0; _b=""; _h=""; _t=""; _bf=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --draft) _d=1 ;;
        --base) _b="$2"; shift ;;
        --head) _h="$2"; shift ;;
        --title) _t="$2"; shift ;;
        --body) shift ;;
        --body-file) _bf="$2"; shift ;;
      esac
      shift
    done
    _n=$(( $(cat "$GH/pr-count" 2>/dev/null || echo 0) + 1 )); echo "$_n" > "$GH/pr-count"
    [ -z "$_bf" ] || cat "$_bf" > "$GH/body-$_n"
    printf 'head=%s\nbase=%s\nstate=OPEN\ndraft=%s\noid=\ntitle=%s\n' "$_h" "$_b" "$_d" "$_t" > "$GH/pr-$_n"
    echo "https://gh.test/pr/$_n" ;;
  "pr view")
    _f="$(pr_file "${3:-}")" || { echo "no pull requests found for ${3:-}" >&2; exit 1; }
    _o="$(get oid "$_f")"; if [ -n "$_o" ]; then _mc="{\"oid\":\"$_o\"}"; else _mc=null; fi
    if [ "$(get draft "$_f")" = 1 ]; then _dr=true; else _dr=false; fi
    printf '{"state":"%s","isDraft":%s,"number":%s,"mergeCommit":%s}\n' \
      "$(get state "$_f")" "$_dr" "${_f##*/pr-}" "$_mc"
    if [ -f "$_f.pending" ]; then cat "$_f.pending" >> "$_f"; rm -f "$_f.pending"; fi ;;
  "pr ready")
    _f="$(pr_file "${3:-}")" || exit 1
    echo draft=0 >> "$_f" ;;
  "pr edit")
    _f="$(pr_file "${3:-}")" || exit 1
    shift 3
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --title) echo "title=$2" >> "$_f"; shift ;;
        --body-file) cat "$2" > "$_f.body"; cat "$2" > "$GH/body-${_f##*/pr-}"; shift ;;
      esac
      shift
    done ;;
  "pr list")
    shift 2; _h=""; _b=""
    while [ "$#" -gt 0 ]; do
      case "$1" in --head) _h="$2"; shift ;; --base) _b="$2"; shift ;; esac
      shift
    done
    _f="$(pr_file "$_h")"
    if [ -n "$_f" ] && [ "$(get state "$_f")" = OPEN ] && { [ -z "$_b" ] || [ "$(get base "$_f")" = "$_b" ]; }; then
      printf '[{"number":%s,"url":"https://gh.test/pr/%s"}]\n' "${_f##*/pr-}" "${_f##*/pr-}"
    else
      echo '[]'
    fi ;;
esac
exit 0
STUB
# The stub merge program (direct fixtures commit scripts/merge.sh, which
# execs this): `s merge <epoch>` and `e merge <epoch>` around its work in
# $CALLS/gate.iv; its outcome is the next word of $MERGE_OUTCOMES (default
# ok; a counter file $CALLS/merge-count). ok: a temp clone of origin merges
# origin/<head> into <base> with --no-ff, pushes, and writes state=MERGED and
# oid=<merge sha> to the PR file; MERGE_DELETES_BRANCH=1 also deletes
# origin/<head>. refuse: exit 1, no merge. ghonly: as ok, but the merge is
# never pushed (GitHub says MERGED; the commit is nowhere on origin). lagoid:
# as ok, but the first view after it shows MERGED with no merge commit (the
# oid arrives via pr-<n>.pending). nofetch: as ok, then origin's bare repo is
# moved away, so the runner's next fetch fails. hang: a child sleep 300 and
# a wait, pids in $CALLS/merge.pid and $CALLS/merge-sleep.pid. mergehang: as
# ok, then as hang (the merge landed, the command never returned). termhang:
# as hang, with TERM ignored by the program and its child.
cat > "$FAKE/merge-stub" <<'STUB'
#!/bin/sh
echo "s merge $(date +%s)" >> "$CALLS/gate.iv"
k=$(( $(cat "$CALLS/merge-count" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$CALLS/merge-count"
out="$(printf '%s\n' ${MERGE_OUTCOMES:-ok} | sed -n "${k}p")"; [ -n "$out" ] || out=ok
f="$GH/pr-$1"; rc=0
case "$out" in
  ok|mergehang)
    head="$(sed -n 's/^head=//p' "$f" | tail -n 1)"; base="$(sed -n 's/^base=//p' "$f" | tail -n 1)"
    url="$(git remote get-url origin)"; d="$(mktemp -d)"
    ( cd "$d" && git clone -q "$url" c && cd c && git checkout -q "$base" \
      && git merge -q --no-ff --no-edit "origin/$head" && git push -q origin "$base" \
      && printf 'state=MERGED\noid=%s\n' "$(git rev-parse HEAD)" >> "$f" \
      && { [ "${MERGE_DELETES_BRANCH:-0}" != 1 ] || git push -q origin --delete "$head"; } ) || rc=1
    rm -rf "$d" ;;
  ghonly|lagoid|nofetch)
    head="$(sed -n 's/^head=//p' "$f" | tail -n 1)"; base="$(sed -n 's/^base=//p' "$f" | tail -n 1)"
    url="$(git remote get-url origin)"; d="$(mktemp -d)"
    ( cd "$d" && git clone -q "$url" c && cd c && git checkout -q "$base" \
      && git merge -q --no-ff --no-edit "origin/$head" \
      && { [ "$out" = ghonly ] || git push -q origin "$base"; } \
      && if [ "$out" = lagoid ]; then
           printf 'state=MERGED\noid=\n' >> "$f" && printf 'oid=%s\n' "$(git rev-parse HEAD)" > "$f.pending"
         else
           printf 'state=MERGED\noid=%s\n' "$(git rev-parse HEAD)" >> "$f"
         fi ) || rc=1
    rm -rf "$d"
    [ "$out" != nofetch ] || mv "$url" "$url.gone" ;;
  refuse) echo "merge refused: the gate is red"; rc=1 ;;
  hang) sleep 300 & echo "$!" > "$CALLS/merge-sleep.pid"; echo "$$" > "$CALLS/merge.pid"; wait ;;
  termhang) trap '' TERM; sleep 300 & echo "$!" > "$CALLS/merge-sleep.pid"; echo "$$" > "$CALLS/merge.pid"
    while kill -0 "$!" 2>/dev/null; do wait; done ;;
esac
[ "$out" != mergehang ] || { sleep 300 & echo "$!" > "$CALLS/merge-sleep.pid"; echo "$$" > "$CALLS/merge.pid"; wait; }
echo "e merge $(date +%s)" >> "$CALLS/gate.iv"
exit "$rc"
STUB
# A fake caffeinate: lives until the -w pid dies (no real keep-awake in tests).
printf '#!/bin/sh\nwhile kill -0 "$3" 2>/dev/null; do sleep 1; done\n' > "$FAKE/caffeinate"
chmod +x "$FAKE"/*
PATH="$FAKE:$PATH"; STUB_STATE_BIN="$STATE_BIN"
export PATH STUB_STATE_BIN
STUB_RUNNER="$RUNNER"; STUB_PLUGIN="$REPO_ROOT/studios/game-dev"; export STUB_RUNNER STUB_PLUGIN
# Default for later tasks: the final step's full gate is `true` (T11); a test
# that needs another gate exports its own and restores this afterwards.
STUDIO_OVERNIGHT_GATE_CMD=true; export STUDIO_OVERNIGHT_GATE_CMD
# The suites test today's endings: hold_minutes 0 (spec milestone gate 1).
STUDIO_OVERNIGHT_HOLD_MINUTES=0; export STUDIO_OVERNIGHT_HOLD_MINUTES

# calls — the stub session counter (0 when none ran).
calls() { cat "$CALLS/count" 2>/dev/null || echo 0; }
# last_lanes_dir — the newest manifest-mode run directory in $P.
last_lanes_dir() { ls -d "$P"/.studio/reports/overnight-demo-* 2>/dev/null | tail -n 1; }

# lanes_fixture NAME MODE ROW… — ROW is id:deps (deps comma-separated, or
# '-'). A clone $P of the bare origin $TMP/NAME.git, on branch run/demo
# (pushed): one spec with a ## Stories table, one approved and swept plan per
# story, studio state per story at stage plan, task 0/1; .studio/config.json
# from $LANES_CONFIG (default {}); LANES_CELLS=dash writes '-' in every Spec and
# Plan cell; LANES_PROGRESS=1 puts docs/game-dev/PROGRESS.md on main, so on
# run/demo too (default: none); the manifest docs/runs/demo.md with Docs: the
# docs commit, committed and pushed; integration/demo on origin for MODE
# integration; LANES_MAIN_MOVES=<file> then commits <file> (content `main`)
# on main and pushes it, so origin/main is not in integration/demo until the
# final step merges it; for MODE direct, an
# executable scripts/merge.sh (the stub merge program) committed on run/demo.
# Exports P, MFP, CALLS, GH,
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
  _lf_cells="${LANES_CELLS:-}"; _lf_progress="${LANES_PROGRESS:-}"; _lf_moves="${LANES_MAIN_MOVES:-}"
  _lf_spec=docs/game-dev/specs/2026-10-01-demo.md
  ( set -e
    cd "$P"
    git init -q -b main
    if [ "$_lf_progress" = 1 ]; then
      mkdir -p docs/game-dev && printf '# Progress\n' > docs/game-dev/PROGRESS.md \
        && git add docs/game-dev/PROGRESS.md && git commit -q -m init
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
    if [ "$_lf_mode" = direct ]; then
      mkdir -p scripts && printf '#!/bin/sh\nexec sh %s "$@"\n' "'$FAKE/merge-stub'" > scripts/merge.sh && chmod +x scripts/merge.sh
    fi
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
    if [ -n "$_lf_moves" ]; then
      git checkout -q main && printf 'main\n' > "$_lf_moves" && git add "$_lf_moves" \
        && git commit -q -m "main moves" && git push -q origin main && git checkout -q run/demo
    fi
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "lanes_fixture $_lf_name: setup failed"; }
  unset LANES_CONFIG LANES_CELLS LANES_PROGRESS LANES_MAIN_MOVES
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

# Final fix wave: a task the producer moved under ## Backlog keeps its heading
# but is not run, so preflight never asks it for a Spec: line; a task above
# the backlog still is.
test_lanes_preflight_backlog_tasks() {
  lanes_fixture backlog integration A:- B:-
  printf '\n### Task 2: u\n\nSpec: docs/game-dev/specs/2026-10-01-demo.md:L1-2\n\n## Backlog\n\n### Task 3: cut\n\nReason: not needed for the gate\n' \
    >> "$P/docs/game-dev/plans/2026-10-01-A.md"
  printf '\n### Task 2: nospec\n\n## Backlog\n\n### Task 3: cut\n' >> "$P/docs/game-dev/plans/2026-10-01-B.md"
  ( cd "$P" && git commit -qam backlog && git push -q origin run/demo ) >/dev/null 2>&1
  _rev="$(git -C "$P" rev-parse HEAD)"
  sed -i.bak "s/^Docs: .*/Docs: $_rev/" "$P/$MFP"; rm -f "$P/$MFP.bak"
  ( cd "$P" && git commit -qam docs && git push -q origin run/demo ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_not_contains "$LS_ERR" "A: plan task has no Spec: line" "a backlog task needs no Spec: line"
  assert_not_contains "$LS_ERR" "Task 3: cut" "no backlog task is named"
  assert_contains "$LS_ERR" "B: plan task has no Spec: line (### Task 2: nospec)" "a task above the backlog still needs one"
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
# ---- T9: waiting chains, skips, crashed lanes and stops ----

# wait_for COND SECS — eval COND once a second until it holds, up to SECS.
wait_for() {
  _wf_i=0
  while ! eval "$1" && [ "$_wf_i" -lt "$2" ]; do sleep 1; _wf_i=$((_wf_i + 1)); done
}
# pid_alive PID — the pid runs and is not a zombie.
pid_alive() {
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*|'') return 1 ;; esac
}
# wait_pid_or_fail PID SECS MSG — passes MSG when PID ends within SECS; else
# KILLs it and fails MSG. Reaps PID (a child of this shell) into WP_STATUS.
wait_pid_or_fail() {
  _wp_i=0
  while pid_alive "$1" && [ "$_wp_i" -lt "$2" ]; do sleep 1; _wp_i=$((_wp_i + 1)); done
  TESTS_RUN=$((TESTS_RUN + 1))
  if pid_alive "$1"; then kill -KILL "$1" 2>/dev/null; _fail "$3 (still alive after $2 s)"
  else _pass "$3"; fi
  WP_STATUS=0; wait "$1" 2>/dev/null || WP_STATUS=$?
}
# first_t0 ID — the start epoch of story ID's first unit (empty when none).
first_t0() {
  _ft_n="$(story_calls "$1" | sort -n | head -n 1)"
  [ -z "$_ft_n" ] || cat "$CALLS/$_ft_n.t0"
}
# dep_gap — seconds from the later of A's and B's landings to C's first unit.
dep_gap() {
  _dg_t0="$(first_t0 C)"
  _dg_land="$(awk -F'\t' '$1=="A"||$1=="B"{print $4}' "$P/.studio/runs/demo/landed.tsv" 2>/dev/null | sort -n | tail -n 1)"
  if [ -n "$_dg_t0" ] && [ -n "$_dg_land" ]; then echo $((_dg_t0 - _dg_land)); else echo 9999; fi
}
waiting_run() {
  lanes_fixture wait integration A:- B:- C:A,B
  printf 'sleep 2\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_POLL_SECONDS=1; export STUDIO_OVERNIGHT_POLL_SECONDS
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_POLL_SECONDS
}
test_lanes_waiting_chain_starts_after_deps() {
  waiting_run
  assert_eq 0 "$LS_STATUS" "all three land"
  assert_contains "$(last_lanes_dir)/stories/C" "^landed " "the waiting story lands"
  g="$(dep_gap)"
  assert_eq 1 "$([ "$g" -ge 0 ] && echo 1 || echo 0)" "C starts no earlier than its last dependency's landing (${g}s)"
  # Wall clock: a second sample only when the first is over; keep the shorter.
  if [ "$g" -gt 5 ]; then waiting_run; g2="$(dep_gap)"; [ "$g2" -ge "$g" ] || g="$g2"; fi
  assert_eq 1 "$([ "$g" -le 5 ] && echo 1 || echo 0)" "C starts within 5 s of its last dependency landing (min of two: ${g}s)"
}
test_lanes_skip_on_stopped_dep() {
  lanes_fixture skipdep integration A:- A2:- B:A C:A,A2
  printf 'stop nope\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_POLL_SECONDS=1; export STUDIO_OVERNIGHT_POLL_SECONDS
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_POLL_SECONDS
  R="$(last_lanes_dir)"
  assert_contains "$R/stories/A" "^stopped stop: nope$" "A stops with its reason"
  assert_contains "$R/stories/B" "^skipped A$" "the rest of A's chain is skipped"
  assert_contains "$R/stories/C" "^skipped A$" "a chain waiting on A is skipped, naming A"
  assert_contains "$R/stories/A2" "^landed " "an unrelated chain lands"
  assert_eq 0 "$(story_calls C | wc -l | tr -d ' ')" "a skipped story launches nothing"
  assert_contains "$R/report.md" "^Ending: partial: 1 landed, 1 stopped, 2 skipped$" "every story has an ending"
}
test_lanes_lane_kill9() {
  lanes_fixture kill9 integration A:- B:A C:- D:A
  printf 'hang\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_POLL_SECONDS=1; KILL_GRACE_SECONDS=2
  export STUDIO_OVERNIGHT_POLL_SECONDS KILL_GRACE_SECONDS
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > "$TMP/k9.out" 2>&1 & RPID=$!
  unset STUDIO_OVERNIGHT_POLL_SECONDS KILL_GRACE_SECONDS
  # Chain 1 (A B) is claimed by whichever lane got there first: its lane
  # number is in claims/1/lane, and that lane's live session in lanes/<k>/cpid.
  wait_for "[ -n \"\$(story_calls A)\" ] && _k1=\"\$(cat \"\$(last_lanes_dir)\"/claims/1/lane 2>/dev/null)\" && [ -s \"\$(last_lanes_dir)/lanes/\$_k1/cpid\" ]" 20
  R="$(last_lanes_dir)"; _k1="$(cat "$R"/claims/1/lane 2>/dev/null)"
  lane1="$(cat "$R"/claims/1/pid 2>/dev/null)"; cpid1="$(cat "$R/lanes/${_k1:-0}/cpid" 2>/dev/null)"
  # The lane's children other than its session (the unit watchdog) and
  # their own children (its sleep) are noted, not killed: the runner's sweep
  # must end them, as it ends the session.
  _kids="$(pgrep -P "${lane1:-0}" 2>/dev/null | grep -vx "${cpid1:-none}")"
  _gkids=""; for _k in $_kids; do _gkids="$_gkids $(pgrep -P "$_k" 2>/dev/null)"; done
  kill -9 "${lane1:-0}"
  wait_pid_or_fail "$RPID" 60 "the runner does not hang on a dead lane"
  assert_eq 1 "$WP_STATUS" "a crashed lane makes the run partial"
  assert_contains "$R/stories/A" "^stopped: lane crashed (137)$" "the parent marks the crashed lane's story with its rc"
  assert_contains "$R/stories/B" "^skipped A$" "the rest of the dead lane's chain is skipped, naming A"
  assert_contains "$R/stories/D" "^skipped A$" "a chain waiting on the dead lane's story is skipped"
  assert_contains "$R/stories/C" "^landed " "the other lane finished"
  assert_contains "$R/report.md" "^Ending: partial: 1 landed, 1 stopped, 2 skipped$" "the report is written with every story ended"
  assert_missing "$P/.studio/overnight.lock" "the run releases its lock"
  assert_eq "" "$(pgrep -f "$TMP/fakebin/claude" 2>/dev/null)" "the dead lane's hung session is ended by the runner"
  assert_eq 1 "$([ -n "$_kids" ] && echo 1 || echo 0)" "the dead lane had a unit watchdog"
  _left=""; for _k in $_kids $_gkids; do ! pid_alive "$_k" || _left="$_left $_k"; done
  assert_eq "" "$_left" "the dead lane's watchdog and its sleep are ended by the runner"
  pkill -9 -f "$TMP/fakebin/claude" 2>/dev/null
  for _k in $_kids $_gkids; do kill -9 "$_k" 2>/dev/null; done
}
# lanes_end_sessions under a run dir whose path has a space: the session in
# lanes/K/cpid (its own group) and the watchdog in lanes/K/wpid are ended and
# both files removed; with no lane named, every lane's.
test_lanes_end_sessions_spaced_path() {
  _sp_out="$( (
    SELF_DIR="$BIN"; GRACE=2; RUN_DIR="$TMP/spaced run/r"
    . "$BIN/overnight-lanes.sh"
    mkdir -p "$RUN_DIR/lanes/1" "$RUN_DIR/lanes/2"
    set -m; sleep 301 & _c1=$!; sleep 302 & _c2=$!; set +m
    sleep 303 & _w1=$!
    printf '%s\n' "$_c1" > "$RUN_DIR/lanes/1/cpid"; printf '%s\n' "$_w1" > "$RUN_DIR/lanes/1/wpid"
    printf '%s\n' "$_c2" > "$RUN_DIR/lanes/2/cpid"
    lanes_end_sessions 1
    sleep 1
    pid_live "$_c1" && echo "c1 alive"; pid_live "$_w1" && echo "w1 alive"
    pid_live "$_c2" || echo "c2 dead early"
    [ ! -f "$RUN_DIR/lanes/1/cpid" ] || echo "cpid 1 left"; [ ! -f "$RUN_DIR/lanes/1/wpid" ] || echo "wpid 1 left"
    lanes_end_sessions
    sleep 1
    pid_live "$_c2" && echo "c2 alive"; [ ! -f "$RUN_DIR/lanes/2/cpid" ] || echo "cpid 2 left"
    kill -9 "$_c1" "$_c2" "$_w1" 2>/dev/null
    echo done
  ) 2>/dev/null )"   # stderr: only the shell's own "Terminated" job notices
  assert_eq "done" "$_sp_out" "sessions and watchdogs end on a spaced path, named lane first, then every lane"
}
test_lanes_sigint() {
  LANES_CONFIG='{"overnight": {"max_lanes": 2}}'; export LANES_CONFIG
  lanes_fixture sigint integration A:- B:- D:-
  printf 'sleep 3\n' > "$SCEN/A"; printf 'sleep 3\n' > "$SCEN/B"
  set -m 2>/dev/null   # job control, as overnight_test.sh's start_bg: SIGINT is not ignored
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > "$TMP/si.out" 2>&1 &
  RPID=$!
  set +m 2>/dev/null
  wait_for "[ -f '$CALLS/2.t0' ]" 20
  kill -INT "$RPID"
  wait_pid_or_fail "$RPID" 60 "the runner ends after SIGINT"
  R="$(last_lanes_dir)"
  assert_eq 1 "$WP_STATUS" "a stopped run is partial"
  assert_eq 2 "$(calls)" "the two running units finish; nothing new starts"
  assert_file "$CALLS/1.t1" "unit 1 ran to its end"
  assert_file "$CALLS/2.t1" "unit 2 ran to its end"
  for id in A B; do assert_contains "$R/stories/$id" "^stopped stopped by user$" "$id ends stopped by user"; done
  assert_contains "$R/stories/D" "^skipped: run stopped$" "a chain no lane claimed ends skipped: run stopped"
  assert_contains "$R/report.md" "^Ending: stopped by user$" "a user stop is the run's ending (T12)"
  assert_contains "$R/report.md" "^Stories: 0 landed, 2 stopped, 1 skipped$" "the report still counts the stories"
  assert_contains "$R/report.md" "^Not landed: skipped — run stopped$" "the unclaimed story says why it did not land"
  assert_missing "$P/.studio/overnight.lock" "the run releases its lock"
}
test_lanes_runner_gone() {
  lanes_fixture gone integration A:-
  printf 'sleep 3\n' > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  R="$(last_lanes_dir)"; lane1="$(cat "$R"/claims/1/pid 2>/dev/null)"
  kill -9 "$RPID"; wait "$RPID" 2>/dev/null
  wait_for "! kill -0 ${lane1:-0} 2>/dev/null" 20
  TESTS_RUN=$((TESTS_RUN + 1))
  if kill -0 "${lane1:-0}" 2>/dev/null; then
    pkill -P "$lane1"; kill -9 "$lane1"; _fail "the lane exits once the runner is gone"
  else _pass "the lane exits once the runner is gone"; fi
  assert_eq 1 "$(calls)" "a lane launches nothing once the runner pid is gone"
  assert_contains "$R/stories/A" "^stopped stop: runner gone$" "the story names the runner's absence, not a user stop"
}
test_lanes_stop_file() {
  lanes_fixture stopf integration A:- B:A C:A
  printf 'sleep 2\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_POLL_SECONDS=1; export STUDIO_OVERNIGHT_POLL_SECONDS
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  unset STUDIO_OVERNIGHT_POLL_SECONDS
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  ( cd "$P" && sh "$RUNNER" stop ) >/dev/null
  wait_pid_or_fail "$RPID" 60 "the runner ends after stop"
  R="$(last_lanes_dir)"
  assert_eq 1 "$(calls)" "the running unit finishes; nothing new starts"
  assert_contains "$R/stories/A" "^stopped stopped by user$" "A ends stopped by user"
  assert_contains "$R/stories/B" "^skipped A$" "the rest of A's chain is skipped"
  assert_contains "$R/stories/C" "^skipped: run stopped$" "a waiting chain ends skipped: run stopped"
  assert_file "$R/report.md" "the report is written"
  assert_contains "$R/report.md" "^Ending: stopped by user$" "a stop request ends the run stopped by user"
}
# ---- T10: landing ----

# land_calls — how many sessions ran an `execute --land` repair unit.
land_calls() { grep -l -- '--land' "$CALLS"/*.argv 2>/dev/null | wc -l | tr -d ' '; }
# land_call — the call number of the (one) repair unit.
land_call() { grep -l -- '--land' "$CALLS"/*.argv 2>/dev/null | sed 's#.*/\([0-9]*\)\.argv#\1#' | head -n 1; }
# merges_of ID — runner merge commits for ID's branch on origin/integration/demo.
merges_of() { git -C "$P" log --merges --format=%s origin/integration/demo | grep -c "^Merge $1-b ($1) into integration/demo$"; }

test_lanes_land_clean_integration() {
  lanes_fixture landi integration A:- B:-
  main0="$(git -C "$P" rev-parse origin/main)"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "both land"
  assert_eq 0 "$(land_calls)" "no session for a clean landing"
  git -C "$P" fetch -q origin
  assert_eq 2 "$(git -C "$P" log --merges --format=%s origin/integration/demo | grep -c '^Merge .* into integration/demo$')" "two runner merge commits on the integration branch"
  for id in A B; do
    assert_eq 1 "$(merges_of "$id")" "$id: one merge commit, named for its branch and id"
    _sha="$(awk -F'\t' -v id="$id" '$1 == id { print $3 }' "$P/.studio/runs/demo/landed.tsv")"
    assert_eq "$(git -C "$P" rev-parse "origin/$id-b")" "$(git -C "$P" rev-parse -q --verify "${_sha:-none}^2" 2>/dev/null)" \
      "$id: the recorded sha is a --no-ff merge whose second parent is the story branch"
  done
  assert_eq "$main0" "$(git -C "$P" rev-parse origin/main)" "nothing reaches main"
  assert_eq 2 "$(wc -l < "$P/.studio/runs/demo/landed.tsv" | tr -d ' ')" "two landed lines"
  assert_eq "run/demo" "$(git -C "$P" rev-parse --abbrev-ref HEAD)" "no checkout is touched"
}
test_lanes_land_clean_direct() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture landd direct A:- B:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "both land"
  assert_eq 0 "$(land_calls)" "no session for a clean landing"
  assert_eq 2 "$(grep -c '^pr ready ' "$GH/calls")" "each draft PR is made ready by the runner"
  assert_eq 2 "$(grep -c '^s merge' "$CALLS/gate.iv" 2>/dev/null)" "the merge program ran once per story"
  git -C "$P" fetch -q origin
  for id in A B; do
    assert_status 0 "$id is in origin/main" -- git -C "$P" merge-base --is-ancestor "origin/$id-b" origin/main
    _f="$(grep -l "^head=$id-b$" "$GH"/pr-[0-9]* | head -n 1)"
    assert_contains "$P/.studio/runs/demo/landed.tsv" "^$id	main	$(sed -n 's/^oid=//p' "$_f" | tail -n 1)	" "$id: landed.tsv records the PR's merge commit"
    assert_contains "$(last_lanes_dir)/stories/$id" "^landed " "$id ends landed"
    assert_eq 1 "$(ls "$(last_lanes_dir)"/lanes/*/"$id-land.log" 2>/dev/null | wc -l | tr -d ' ')" "$id: the merge program's output goes to <id>-land.log"
  done
  assert_not_contains "$GH/calls" "progress/demo" "no PROGRESS.md: no progress PR"
}
test_lanes_land_conflict_one_repair() {
  # Two lanes: both branches start from the same target, A lands first (B's
  # finish sleeps), so B's landing conflicts on shared.txt. One lane would
  # not conflict: B would branch from the target after A landed.
  lanes_fixture landc integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'repair\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_eq 1 "$(land_calls)" "exactly one repair unit"
  n="$(land_call)"; [ -n "$n" ] || n=0
  assert_eq B "$(cat "$CALLS/$n.story" 2>/dev/null)" "the repair is the conflicting story's"
  assert_contains "$CALLS/$n.env" "^STUDIO_REPAIR=conflict$" "the repair knows why"
  assert_eq opus "$(sed -n 4p "$CALLS/$n.argv" 2>/dev/null)" "the repair runs on model_repair"
  assert_eq "/game-dev:execute --land" "$(cat "$CALLS/$n.prompt" 2>/dev/null)" "the repair prompt"
  assert_contains "$(last_lanes_dir)/stories/B" "^landed " "the retry lands"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "the first story lands"
  assert_eq 1 "$(cat "$(last_lanes_dir)"/lanes/*/units.tsv | grep -c '	B-repair	')" "the repair unit has a units.tsv row"
  git -C "$P" fetch -q origin
  assert_eq "1 1" "$(merges_of A) $(merges_of B)" "one runner merge per story"
}
test_lanes_land_second_conflict_stops() {
  lanes_fixture landc2 integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'fakerepair\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_eq 1 "$(land_calls)" "one repair, no second"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped landing failed after repair (conflict)$" "a second conflict stops the story"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: partial: 1 landed, 1 stopped, 0 skipped$" "the run is partial"
  assert_eq "" "$(ls -d "$(last_lanes_dir)/land.lock" 2>/dev/null)" "the land lock is released"
}
test_lanes_land_repair_no_progress() {
  lanes_fixture landnp integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'noop\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped repair made no progress$" "a repair with no Repair: line stops"
  lanes_fixture landst integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'stop cannot resolve\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: cannot resolve$" "a repair's Stop: line stops with its reason"
}
test_lanes_direct_refused_then_repaired() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture landr direct A:-
  printf 'repair\n' > "$SCEN/A.land"
  MERGE_OUTCOMES="refuse ok"; export MERGE_OUTCOMES
  run_lanes start "$MFP"
  unset MERGE_OUTCOMES
  assert_eq 1 "$(land_calls)" "one repair unit"
  n="$(land_call)"; [ -n "$n" ] || n=0
  assert_contains "$CALLS/$n.env" "^STUDIO_REPAIR=red:/.*/A-land.log$" "a refused merge command repairs with its log"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "the retry lands"
  assert_eq 2 "$(grep -c '^s merge' "$CALLS/gate.iv" 2>/dev/null)" "the merge command ran twice"
  assert_eq 1 "$(grep -c '^pr ready ' "$GH/calls")" "a PR already ready is not made ready again"
}
# Final fix wave (ruling): the merge command runs under session_minutes (the
# STUDIO_OVERNIGHT_SESSION_SECONDS hook here). A timeout ends its process
# group, is a failed landing with no repair, releases the land and gate
# locks, and the run still reports.
test_lanes_direct_merge_timeout() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture mto direct A:-
  printf 'repair\n' > "$SCEN/A.land"
  MERGE_OUTCOMES=hang; STUDIO_OVERNIGHT_SESSION_SECONDS=6; export MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS
  _t0="$(date +%s)"
  run_lanes start "$MFP"
  _t1="$(date +%s)"
  unset MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped landing failed (merge command timed out)$" "a hung merge command is a failed landing"
  assert_eq 0 "$(land_calls)" "a timed-out merge starts no repair"
  assert_eq 1 "$(grep -c '^s merge' "$CALLS/gate.iv" 2>/dev/null)" "the merge command ran once"
  _mp="$(cat "$CALLS/merge.pid" 2>/dev/null)"; _sp="$(cat "$CALLS/merge-sleep.pid" 2>/dev/null)"
  assert_status 1 "the merge program is ended" -- kill -0 "${_mp:-999999}"
  assert_status 1 "and its child, through the process group" -- kill -0 "${_sp:-999999}"
  assert_missing "$(last_lanes_dir)/land.lock" "the land lock is released"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
  assert_file "$(last_lanes_dir)/report.md" "the run still reports"
  assert_eq 1 "$([ $((_t1 - _t0)) -lt 100 ] && echo 1 || echo 0)" "the run does not wait out the hung merge"
}
# A merge command whose PR GitHub reports MERGED never starts a repair: a
# merge commit missing from origin, or a failed fetch, stops the landing
# (return 4); a merge commit that arrives on the second view lands.
test_lanes_direct_merged_never_repairs() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture mnr direct A:-
  printf 'repair\n' > "$SCEN/A.land"
  MERGE_OUTCOMES=ghonly; export MERGE_OUTCOMES
  run_lanes start "$MFP"
  unset MERGE_OUTCOMES
  assert_eq 0 "$(land_calls)" "MERGED with its commit absent from origin: no repair"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped landing failed (PR #1 is MERGED but its merge commit is not in origin/main)$" "the landing stops (return 4)"
  assert_eq 1 "$(grep -c '^s merge' "$CALLS/gate.iv" 2>/dev/null)" "the merge command ran once"
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture mnrf direct A:-
  printf 'repair\n' > "$SCEN/A.land"
  MERGE_OUTCOMES=nofetch; export MERGE_OUTCOMES
  run_lanes start "$MFP"
  unset MERGE_OUTCOMES
  mv "$TMP/mnrf.git.gone" "$TMP/mnrf.git" 2>/dev/null
  assert_eq 0 "$(land_calls)" "a failed fetch after the merge command: no repair"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped landing failed (cannot fetch origin)$" "the landing stops (return 4)"
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture mnrl direct A:-
  printf 'repair\n' > "$SCEN/A.land"
  MERGE_OUTCOMES=lagoid; export MERGE_OUTCOMES
  run_lanes start "$MFP"
  unset MERGE_OUTCOMES
  assert_eq 0 "$(land_calls)" "a merge commit lagging one view: no repair"
  _oid="$(sed -n 's/^oid=//p' "$GH/pr-1" | tail -n 1)"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed ${_oid:-none}$" "the second view lands it"
  assert_eq 1 "$(grep -c '^s merge' "$CALLS/gate.iv" 2>/dev/null)" "the merge command ran once"
}
# land_once ID BRANCH (Task 11's progress landing: a branch with no manifest
# row) runs step 0 against BRANCH: already landed -> recorded, no new merge.
test_lanes_land_once_explicit_branch() {
  lanes_fixture lob integration A:-
  _xb="$TMP/xb-lob"
  ( cd "$P" && git worktree add -q --no-track -b prog-x "$_xb" origin/integration/demo \
    && cd "$_xb" && mkdir -p .studio/ledger && printf -- '- 2026-10-01 shipped prog-x\n' > .studio/ledger/P1.md \
    && git add -A && git commit -qm p1-shipped && git push -q origin prog-x \
    && git push -q origin prog-x:integration/demo \
    && cd "$P" && git worktree remove --force "$_xb" && git branch -q -D prog-x ) >/dev/null 2>&1
  git -C "$P" fetch -q origin
  _t0="$(git -C "$P" rev-parse origin/integration/demo)"
  printf 'A\tA-b\tA\t\t\t\n' > "$TMP/lob.rows"
  _out="$( SELF_DIR="$BIN"; START_DIR="$P"; MF_MODE=integration; MF_TARGET=integration/demo; MF_ROWS="$TMP/lob.rows"
           . "$BIN/overnight-lanes.sh"; land_once P1 prog-x; echo "$? $LAND_SHA" )"
  git -C "$P" fetch -q origin
  assert_eq "0 $_t0" "$_out" "step 0 confirms the named branch: landed, LAND_SHA its head (a fast-forward)"
  assert_eq "$_t0" "$(git -C "$P" rev-parse origin/integration/demo)" "no merge is pushed"
}
test_lanes_land_idempotent() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture idem direct A:-
  MERGE_DELETES_BRANCH=1; export MERGE_DELETES_BRANCH
  run_lanes start "$MFP"                                  # lands A, and the merge deletes A-b
  unset MERGE_DELETES_BRANCH
  _oid="$(sed -n 's/^oid=//p' "$GH/pr-1" | tail -n 1)"
  : > "$CALLS/gate.iv"; rm -rf "$P/.studio/runs/demo"     # forget the runner's record
  _c0="$(calls)"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the resumed run is done"
  assert_eq 0 "$(grep -c '^s merge' "$CALLS/gate.iv")" "a merged PR is recorded with no merge command"
  assert_eq "$_c0" "$(calls)" "and no session"
  assert_contains "$P/.studio/runs/demo/landed.tsv" "^A	main	${_oid:-none}	[0-9]\{10\}$" "and appended to landed.tsv from GitHub alone, with the PR's merge commit"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed ${_oid:-none}$" "A is landed with the existing merge commit"
}
test_lanes_land_crash_after_push() {
  lanes_fixture crashp integration A:-
  # The hook's `sh -c` is the lane's own child, so $PPID is the lane (a
  # `$(…)` would name a command-substitution subshell instead).
  STUDIO_OVERNIGHT_LAND_HOOK="sh -c 'kill -9 \$PPID'; : > '$CALLS/survived'"; export STUDIO_OVERNIGHT_LAND_HOOK
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_LAND_HOOK
  assert_missing "$CALLS/survived" "the lane is killed between its push and its record"
  R1="$(last_lanes_dir)"
  rm -rf "$P/.studio/runs/demo"     # the killed lane wrote no landed.tsv line
  sleep 1                           # a new run dir name
  run_lanes start "$MFP"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(merges_of A)" "no second merge commit"
  assert_eq 0 "$(land_calls)" "no repair"
  assert_eq 1 "$([ "$(last_lanes_dir)" != "$R1" ] && echo 1 || echo 0)" "the resume is a second run"
  _m="$(git -C "$P" log --merges --format=%H origin/integration/demo | head -n 1)"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed ${_m:-none}$" "the resume records the landing from git alone"
  assert_contains "$P/.studio/runs/demo/landed.tsv" "^A	integration/demo	${_m:-none}	" "and appends landed.tsv"
}
test_lanes_land_lock_reclaim() {
  # A's lane is SIGKILLed right after its push, holding the land lock; B's
  # finish runs 4 s later, so B finds the dead holder's lock and reclaims it.
  lanes_fixture landk integration A:- B:-
  printf 'auto\nauto\nsleep 4\n' > "$SCEN/B"
  STUDIO_OVERNIGHT_POLL_SECONDS=1
  STUDIO_OVERNIGHT_LAND_HOOK="[ \"\$CUR_ID\" != A ] || { sh -c 'kill -9 \$PPID'; : > '$CALLS/survived'; }"
  export STUDIO_OVERNIGHT_POLL_SECONDS STUDIO_OVERNIGHT_LAND_HOOK
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_POLL_SECONDS STUDIO_OVERNIGHT_LAND_HOOK
  assert_missing "$CALLS/survived" "A's lane is killed holding the land lock"
  R="$(last_lanes_dir)"
  assert_contains "$R/stories/B" "^landed " "the other lane reclaims the dead holder's land lock and lands"
  assert_contains "$R/stories/A" "^landed " "the killed story is recorded landed from git by the sweep"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(merges_of A)" "A merged once"
  assert_eq 2 "$(wc -l < "$P/.studio/runs/demo/landed.tsv" | tr -d ' ')" "two landed lines"
  assert_eq "" "$(ls -d "$R/land.lock" 2>/dev/null)" "the land lock is released"
}
test_lanes_land_shipped_resume() {
  # A half-done story already at stage idle with a shipped line, its branch
  # on origin, not yet landed: the run lands it with no unit (run_story's
  # shortcut). A second run with the record forgotten confirms it from git.
  lanes_fixture shipres integration A:-
  _ab="$TMP/ab-shipres"
  ( cd "$P" && git worktree add -q --no-track -b A-b "$_ab" origin/integration/demo \
    && cd "$_ab" && git checkout -q run/demo -- docs/game-dev .studio/ledger/A.md \
    && printf 'A\n' > A-T1.txt && printf -- '- 2026-10-01 shipped A-b\n' >> .studio/ledger/A.md \
    && git add -A && git commit -qm a-shipped && git push -q origin A-b \
    && cd "$P" && git worktree remove --force "$_ab" && git branch -q -D A-b \
    && STUDIO_STORY=A sh "$STATE_BIN" set stage idle && STUDIO_STORY=A sh "$STATE_BIN" set task - \
    && printf -- '- 2026-10-01 shipped A-b\n' >> .studio/ledger/A.md \
    && git add -A && git commit -qm shipped && git push -q origin run/demo ) >/dev/null 2>&1
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the shipped story lands"
  assert_eq 0 "$(calls)" "with no unit"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(merges_of A)" "one runner merge"
  _m="$(git -C "$P" log --merges --format=%H origin/integration/demo | head -n 1)"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed ${_m:-none}$" "recorded with its merge commit"
  rm -rf "$P/.studio/runs/demo"; sleep 1
  run_lanes start "$MFP"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(merges_of A)" "an already-landed story is not merged again"
  assert_eq 0 "$(calls)" "no unit and no repair"
  assert_contains "$P/.studio/runs/demo/landed.tsv" "^A	integration/demo	${_m:-none}	" "it is recorded with the existing merge commit"
}
test_lanes_gate_never_overlaps() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture gate direct A:- B:- C:-
  for id in A B C; do printf 'gate 1; auto\ngate 1; auto\ngate 1; auto\n' > "$SCEN/$id"; done
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "all three land"
  assert_eq 3 "$(grep -c '^s merge' "$CALLS/gate.iv" 2>/dev/null)" "three merge commands"
  assert_eq 12 "$(grep -c '^s ' "$CALLS/gate.iv" 2>/dev/null)" "nine unit tests and three merge commands in one gate.iv"
  assert_eq "" "$(awk '$1=="s"{if(open)print "overlap at " $3; open=1} $1=="e"{open=0}' "$CALLS/gate.iv")" "unit tests and merge commands never overlap"
}
# ---- Gate repair: a red finish gate gets a repair unit and a fresh finish ----

# gate_calls — how many sessions ran an `execute --gate-repair` unit.
gate_calls() { grep -l -- '--gate-repair' "$CALLS"/*.argv 2>/dev/null | wc -l | tr -d ' '; }
# gate_call — the call number of the first gate-repair unit.
gate_call() { grep -l -- '--gate-repair' "$CALLS"/*.argv 2>/dev/null | sed 's#.*/\([0-9]*\)\.argv#\1#' | sort -n | head -n 1; }
# story_rows ID — `<n> <label> <outcome>` of ID's units.tsv rows, comma-joined.
story_rows() { cat "$(last_lanes_dir)"/lanes/*/units.tsv 2>/dev/null | awk -F'\t' -v p="$1-" 'index($2, p) == 1 { printf "%s %s %s,", $1, $2, $7 }'; }

test_lanes_gate_repair_then_lands() {
  lanes_fixture gaterep integration A:- B:A
  printf 'auto\nauto\ngatelog; stop gate red — studio-test: 1 failed\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the repaired story lands, and so does its dependent"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed [0-9a-f]\{40\}$" "A lands after its gate repair"
  assert_contains "$(last_lanes_dir)/stories/B" "^landed " "the dependent story runs and lands"
  assert_eq 1 "$(gate_calls)" "exactly one gate-repair unit"
  n="$(gate_call)"; [ -n "$n" ] || n=0
  assert_eq A "$(cat "$CALLS/$n.story" 2>/dev/null)" "the repair is the red story's"
  assert_eq "/game-dev:execute --gate-repair" "$(cat "$CALLS/$n.prompt" 2>/dev/null)" "the gate-repair prompt"
  assert_eq opus "$(sed -n 4p "$CALLS/$n.argv" 2>/dev/null)" "the gate repair runs on model_repair"
  assert_contains "$CALLS/$n.env" "^STUDIO_REPAIR=gate:/.*/A-b/\.studio/reports/test-[0-9-]*\.log$" "the repair reads the red gate's log"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish stop,4 A-gate-repair progress,5 A-finish done," \
    "$(story_rows A)" "a fresh finish follows the repair; unit numbers run on"
  assert_contains "$(last_lanes_dir)/report.md" "^| 4 | A-gate-repair | " "the report lists the gate-repair unit"
}
test_lanes_gate_repair_cap() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture gatecap integration A:- B:A
  printf 'auto\nauto\nstop gate red — studio-test: 1 failed\nstop gate red — studio-run: SCRIPT ERROR\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_eq 1 "$LS_STATUS" "a story red after its repairs makes the run partial"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped gate red after 1 repairs — studio-run: SCRIPT ERROR$" "the cap names the repairs and the last red line"
  assert_contains "$(last_lanes_dir)/stories/B" "^skipped A$" "the dependent is skipped"
  assert_eq 1 "$(gate_calls)" "one repair, no second"
  assert_contains "$(last_lanes_dir)/report.md" "stopped — gate red after 1 repairs — studio-run: SCRIPT ERROR" "the report names why"
}
# The same Stop line twice on the same date (the second finish fails as the
# first did) is still a new stop: missed, the finish would be retried and ship.
test_lanes_gate_repair_same_stop_twice() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture gatesame integration A:-
  printf 'auto\nauto\nstop gate red — studio-test: 1 failed\nstop gate red — studio-test: 1 failed\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped gate red after 1 repairs — studio-test: 1 failed$" "the repeated stop is detected"
  assert_eq 4 "$(cat "$CALLS/m-A" 2>/dev/null)" "no finish retry after the second red gate"
}
test_lanes_gate_repairs_zero() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 0}}'; export LANES_CONFIG
  lanes_fixture gatezero integration A:- B:A
  printf 'auto\nauto\nstop gate red — studio-test: 1 failed\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: gate red — studio-test: 1 failed$" "gate_repairs 0: the first red gate stops the story"
  assert_contains "$(last_lanes_dir)/stories/B" "^skipped A$" "and its dependent is skipped"
  assert_eq 0 "$(gate_calls)" "no gate-repair unit"
}
test_lanes_gate_hard_stops_no_repair() {
  lanes_fixture gatehard integration A:- B:- C:-
  printf 'auto\nauto\nstop studio-test: GODOT_PATH is not set\n' > "$SCEN/A"
  printf 'auto\nauto\nstop studio-test: GUT is not installed\n' > "$SCEN/B"
  printf 'auto\nauto\nstop gate timed out — studio-test ran past 90 min\n' > "$SCEN/C"
  for id in A B C; do printf 'gaterepair\n' > "$SCEN/$id.gate"; done
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: studio-test: GODOT_PATH is not set$" "exit 2 stays a hard stop"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: studio-test: GUT is not installed$" "exit 3 stays a hard stop"
  assert_contains "$(last_lanes_dir)/stories/C" "^stopped stop: gate timed out — studio-test ran past 90 min$" "a timed-out gate stays a hard stop"
  assert_eq 0 "$(gate_calls)" "no hard stop gets a gate-repair unit"
}
test_lanes_gate_repair_no_progress() {
  lanes_fixture gatenp integration A:-
  printf 'auto\nauto\nstop gate red — studio-test: 1 failed\n' > "$SCEN/A"
  printf 'noop\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped gate repair made no progress$" "a repair with no Repair: line stops"
  assert_contains "$(last_lanes_dir)/lanes/1/units.tsv" "	A-gate-repair	.*	noprog$" "its row says noprog"
  lanes_fixture gatered integration A:-
  printf 'auto\nauto\nstop gate red — studio-test: 1 failed\n' > "$SCEN/A"
  printf 'stop gate repair red — studio-test: 1 failed\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: gate repair red — studio-test: 1 failed$" "a repair's own red is a hard stop"
  assert_eq 1 "$(gate_calls)" "and gets no second repair"
}
test_lanes_gate_repair_model_and_no_log() {
  LANES_CONFIG='{"overnight": {"model_repair": "r-m"}}'; export LANES_CONFIG
  lanes_fixture gatemodel integration A:-
  printf 'auto\nauto\nstop gate red — studio-run: SCRIPT ERROR\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  n="$(gate_call)"; [ -n "$n" ] || n=0
  assert_eq r-m "$(sed -n 4p "$CALLS/$n.argv" 2>/dev/null)" "model_for gate-repair is model_repair"
  assert_contains "$CALLS/$n.env" "^STUDIO_REPAIR=gate:-$" "no studio-test log: gate:-"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "the repaired story lands"
}
# A stop requested while the gate-repair unit runs: no fresh finish starts,
# and the story ends with the halt's reason whether or not the repair landed.
test_lanes_gate_repair_halt() {
  for act in noop gaterepair; do
    lanes_fixture "gatehalt-$act" integration A:-
    printf 'auto\nauto\nstop gate red — studio-test: 1 failed\n' > "$SCEN/A"
    printf 'sleep 3; %s\n' "$act" > "$SCEN/A.gate"
    ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
    wait_for "[ -f '$CALLS/m-A.gate' ]" 60
    ( cd "$P" && sh "$RUNNER" stop ) >/dev/null
    wait_pid_or_fail "$RPID" 60 "the runner ends after stop"
    assert_contains "$(last_lanes_dir)/stories/A" "^stopped stopped by user$" "$act repair, then a stop: the story ends stopped by user"
    assert_eq 3 "$(cat "$CALLS/m-A" 2>/dev/null)" "$act repair, then a stop: no fresh finish"
  done
}
test_lanes_gate_repair_budget() {
  LANES_CONFIG='{"overnight": {"run_usd": 30, "session_usd": 25}}'; export LANES_CONFIG
  lanes_fixture gatebudget integration A:-
  printf 'cost 2\ncost 2\ncost 2; stop gate red — studio-test: 1 failed\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: run budget$" "spent 6 + 25 > 30: the run budget refuses the repair"
  assert_eq 0 "$(gate_calls)" "no gate-repair unit"
}
# ---- T11: the integration final step and the direct progress landing ----

# prompt_calls PROMPT — the stub call numbers whose prompt is exactly PROMPT.
prompt_calls() { grep -lxF -- "$1" "$CALLS"/*.prompt 2>/dev/null | sed 's#.*/\([0-9]*\)\.prompt$#\1#'; }
# final_gates — how many final gates ran (the test gate logs one line each).
final_gates() { cat "$CALLS/final-gates" 2>/dev/null | wc -l | tr -d ' '; }
# use_gate CMD — the final step's gate for the next run (restore with use_gate true).
use_gate() { STUDIO_OVERNIGHT_GATE_CMD="$1"; export STUDIO_OVERNIGHT_GATE_CMD; }

test_lanes_final_step_once() {
  LANES_PROGRESS=1; LANES_MAIN_MOVES=main.txt; export LANES_PROGRESS LANES_MAIN_MOVES
  lanes_fixture fin integration A:- B:-
  printf 'progress\n' > "$SCEN/progress"
  printf 'auto\nruling T1 Ruling: kept the cap — fits — a refactor; auto\n' > "$SCEN/A"
  main0="$(git -C "$P" rev-parse origin/main)"
  W="$P/.claude/worktrees/integration-demo"
  assert_status 1 "the fixture: origin/main is not yet in the integration branch" -- git -C "$P" merge-base --is-ancestor origin/main origin/integration/demo
  use_gate "echo gate >> '$CALLS/final-gates'"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_eq 1 "$(final_gates)" "one full gate on the combined head"
  assert_eq 1 "$(grep -c '^pr create --draft --base main --head integration/demo' "$GH/calls")" "one draft PR into main"
  assert_contains "$GH/pr-1" "^title=demo: the demo goal$" "the title is <slug>: <Goal>"
  assert_contains "$GH/body-1" "^## A$" "a section per landed story"
  assert_contains "$GH/body-1" "^## B$" "B's section"
  assert_contains "$GH/body-1" "^- [0-9-]* T1 Ruling: kept the cap" "a task's T<n> Ruling: line is in the body"
  git -C "$P" fetch -q origin
  assert_status 0 "origin/main is merged into the integration head" -- git -C "$P" merge-base --is-ancestor origin/main origin/integration/demo
  assert_eq 1 "$(git -C "$P" log --format=%s origin/integration/demo | grep -c '^docs(progress): demo$')" "one PROGRESS commit"
  _h="$(git -C "$P" rev-parse origin/integration/demo)"
  assert_contains "$P/.studio/runs/demo/gate" "^$_h green$" "the gate names the pushed head (PROGRESS commit included)"
  assert_contains "$P/.studio/runs/demo/final" "^$_h https://gh.test/pr/1 green$" "the final record: head, PR, color"
  _n="$(prompt_calls '/game-dev:execute --progress')"
  assert_eq 1 "$(printf '%s' "$_n" | grep -c .)" "one progress unit"
  [ -n "$_n" ] || _n=0
  assert_eq "" "$(cat "$CALLS/$_n.story" 2>/dev/null)" "the progress unit has no STUDIO_STORY"
  assert_contains "$CALLS/$_n.env" "^STUDIO_RUN=.*/overnight-demo-[0-9-]*/manifest.md$" "and STUDIO_RUN"
  assert_eq "$W" "$(cat "$CALLS/$_n.pwd" 2>/dev/null)" "it runs in the integration worktree"
  assert_eq sonnet "$(sed -n 4p "$CALLS/$_n.argv" 2>/dev/null)" "on model_progress"
  assert_contains "$(last_lanes_dir)/final/units.tsv" "	progress	" "the progress unit has a units.tsv row"
  assert_eq "$main0" "$(git -C "$P" rev-parse origin/main)" "nothing is merged into main"
  assert_not_contains "$GH/calls" "^pr merge" "the final PR is never merged"
  assert_contains "$(last_lanes_dir)/report.md" "^Final PR: https://gh.test/pr/1 (green)$" "the report names the final PR"
  assert_eq "" "$(git -C "$P" status --porcelain)" "the integration worktree leaves the checkout clean"
  # Resume with an unchanged head and the PR open: nothing more.
  sleep 1
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the resumed run is done"
  assert_eq 1 "$(final_gates)" "a resume at an unchanged head runs no gate"
  assert_eq 0 "$(grep -c '^pr edit ' "$GH/calls")" "and edits no PR"
  assert_eq 1 "$(grep -c '^pr create ' "$GH/calls")" "and opens none"
  assert_eq 1 "$(prompt_calls '/game-dev:execute --progress' | grep -c .)" "and runs no second progress unit"
  use_gate true
}
test_lanes_final_red_after_repair() {
  lanes_fixture finred integration A:-
  printf 'noop\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; exit 1"
  run_lanes start "$MFP"
  use_gate true
  assert_eq 2 "$(final_gates)" "one gate, one repair, one more gate"
  assert_contains "$GH/calls" "^pr create --draft .*--title \[red\] " "a red gate still opens the draft PR, titled [red]"
  _n="$(prompt_calls '/omega:integration repair demo')"
  assert_eq 1 "$(printf '%s' "$_n" | grep -c .)" "one final-repair unit"
  [ -n "$_n" ] || _n=0
  _log="$(last_lanes_dir)/final-gate.log"
  assert_contains "$CALLS/$_n.env" "^STUDIO_REPAIR=red:$_log$" "the repair reads the red gate's log"
  assert_file "$_log" "the gate's output is kept"
  assert_eq opus "$(sed -n 4p "$CALLS/$_n.argv" 2>/dev/null)" "the final repair runs on model_repair"
  assert_eq "$P/.claude/worktrees/integration-demo" "$(cat "$CALLS/$_n.pwd" 2>/dev/null)" "in the integration worktree"
  assert_contains "$(last_lanes_dir)/final/units.tsv" "	final-repair	" "the final repair has a units.tsv row"
  assert_contains "$P/.studio/runs/demo/gate" "^[0-9a-f]\{40\} red$" "the gate record says red"
  assert_contains "$P/.studio/runs/demo/final" " red$" "the final record says red"
  assert_eq "" "$(prompt_calls '/game-dev:execute --progress')" "no PROGRESS.md: no progress unit"
}
test_lanes_final_repair_turns_green() {
  lanes_fixture fingreen integration A:-
  printf 'fixgate\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; [ -f fixed ]"
  run_lanes start "$MFP"
  use_gate true
  assert_eq 2 "$(final_gates)" "red, the repair, green"
  assert_contains "$GH/calls" "^pr create --draft --base main --head integration/demo --title demo: the demo goal " "a green PR has no [red] prefix"
  git -C "$P" fetch -q origin
  assert_status 0 "the repair's commit is pushed" -- git -C "$P" cat-file -e origin/integration/demo:fixed
  assert_contains "$P/.studio/runs/demo/gate" "^$(git -C "$P" rev-parse origin/integration/demo) green$" "the gate record names the repaired head"
}
test_lanes_final_conflict() {
  LANES_MAIN_MOVES=shared.txt; export LANES_MAIN_MOVES
  lanes_fixture fincf integration A:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'mergemain\n' > "$SCEN/final-repair"
  run_lanes start "$MFP"
  _n="$(prompt_calls '/omega:integration repair demo')"
  assert_eq 1 "$(printf '%s' "$_n" | grep -c .)" "one final-repair unit for the conflict"
  [ -n "$_n" ] || _n=0
  assert_contains "$CALLS/$_n.env" "^STUDIO_REPAIR=conflict$" "the repair knows it is a conflict"
  git -C "$P" fetch -q origin
  assert_status 0 "the repaired merge is pushed" -- git -C "$P" merge-base --is-ancestor origin/main origin/integration/demo
  assert_contains "$P/.studio/runs/demo/final" " green$" "a resolved conflict and a green gate: green"
  # The repair cannot resolve it: red, the integration head unmerged.
  LANES_MAIN_MOVES=shared.txt; export LANES_MAIN_MOVES
  lanes_fixture fincf2 integration A:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'noop\n' > "$SCEN/final-repair"
  run_lanes start "$MFP"
  git -C "$P" fetch -q origin
  assert_status 1 "the integration head stays unmerged" -- git -C "$P" merge-base --is-ancestor origin/main origin/integration/demo
  assert_contains "$GH/calls" "^pr create --draft .*--title \[red\] " "titled [red]"
  assert_contains "$GH/body-1" "origin/main does not merge cleanly" "the body names the failure"
  assert_eq "" "$(git -C "$P/.claude/worktrees/integration-demo" status --porcelain 2>&1)" "no half-done merge is left in the worktree"
  assert_contains "$P/.studio/runs/demo/final" " red$" "the final record says red"
}
test_lanes_final_resume_edits_pr() {
  lanes_fixture finedit integration A:-
  use_gate "echo gate >> '$CALLS/final-gates'"
  run_lanes start "$MFP"
  rm -f "$P/.studio/runs/demo/final"; sleep 1
  run_lanes start "$MFP"
  use_gate true
  assert_eq 1 "$(final_gates)" "the gate record names HEAD: no second gate"
  assert_eq 1 "$(grep -c '^pr create ' "$GH/calls")" "one PR"
  assert_eq 1 "$(grep -c '^pr edit 1 --title demo: the demo goal --body-file ' "$GH/calls")" "the open PR is edited"
  assert_contains "$GH/body-1" "^## A$" "with the body"
}
test_lanes_final_skipped_on_stop_or_nothing_landed() {
  lanes_fixture finstop integration A:-
  printf 'stop no\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_not_contains "$GH/calls" "^pr create" "no final PR when no story landed"
  assert_missing "$P/.claude/worktrees/integration-demo" "and no integration worktree"
  # A lands, then the user stops the run while B finishes: no final step.
  lanes_fixture finstop2 integration A:- B:-
  printf 'auto\nauto\nsleep 8\n' > "$SCEN/B"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -s '$P/.studio/runs/demo/landed.tsv' ]" 60
  ( cd "$P" && sh "$RUNNER" stop ) >/dev/null
  wait_pid_or_fail "$RPID" 60 "the runner ends after stop"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A landed before the stop"
  assert_not_contains "$GH/calls" "^pr create" "no final PR after a stop"
  assert_missing "$P/.claude/worktrees/integration-demo" "the final step does not start after a stop"
}
# The default full gate (no test hook): studio-test, studio-lint (exit 3 =
# no linter, not red), studio-run --seconds 10, from the runner's own bin.
test_lanes_final_gate_default() {
  _gb="$TMP/gate bin"; mkdir -p "$_gb"
  printf '#!/bin/sh\necho test >> "%s/gd.log"\n' "$TMP" > "$_gb/studio-test"
  printf '#!/bin/sh\necho lint >> "%s/gd.log"; exit "${GD_LINT:-0}"\n' "$TMP" > "$_gb/studio-lint"
  printf '#!/bin/sh\necho "run $*" >> "%s/gd.log"\n' "$TMP" > "$_gb/studio-run"
  for _c in 0 3 1; do
    rm -f "$TMP/gd.log"
    _st="$( unset STUDIO_OVERNIGHT_GATE_CMD; SELF_DIR="$_gb"; GD_LINT="$_c"; export GD_LINT
            sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
            . "$BIN/overnight-lanes.sh"; sh -c "$(final_gate_cmds)"; echo $? )"
    case "$_c" in
      1) assert_eq "1" "$_st" "lint exit 1 is red" ;;
      *) assert_eq "0" "$_st" "lint exit $_c is not red" ;;
    esac
  done
  assert_eq "test lint" "$(tr '\n' ' ' < "$TMP/gd.log" | sed 's/ $//')" "a red lint stops the gate before studio-run"
  rm -f "$TMP/gd.log"
  ( unset STUDIO_OVERNIGHT_GATE_CMD; SELF_DIR="$_gb"
    sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
    . "$BIN/overnight-lanes.sh"; sh -c "$(final_gate_cmds)" )
  assert_eq "test lint run --seconds 10" "$(tr '\n' ' ' < "$TMP/gd.log" | sed 's/ $//')" "test, lint, then a 10 s run"
}
test_lanes_direct_progress_landing() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; LANES_PROGRESS=1; export LANES_CONFIG LANES_PROGRESS
  lanes_fixture dprog direct A:-
  printf 'progress\n' > "$SCEN/progress"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_contains "$GH/calls" "^pr create --base main --head progress/demo" "a ready progress PR"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(git -C "$P" log --format=%s origin/main | grep -c '^docs(progress): demo$')" "the progress entry landed on main through the merge command"
  assert_eq 2 "$(grep -c '^s merge' "$CALLS/gate.iv" 2>/dev/null)" "the merge command ran for A and for the progress PR"
  _n="$(prompt_calls '/game-dev:execute --progress')"; [ -n "$_n" ] || _n=0
  assert_eq "$P/.claude/worktrees/progress-demo" "$(cat "$CALLS/$_n.pwd" 2>/dev/null)" "the progress unit runs in its own worktree"
  assert_eq "" "$(cat "$CALLS/$_n.story" 2>/dev/null)" "with no STUDIO_STORY"
  assert_contains "$(last_lanes_dir)/report.md" "^Final PR: https://gh.test/pr/2 (green)$" "the report names the progress PR"
  assert_contains "$(last_lanes_dir)/report.md" "^## Landed$" "direct: a Landed section"
  assert_contains "$(last_lanes_dir)/report.md" "^A [0-9a-f]\{40\}$" "each landed story's merge commit"
  assert_contains "$(last_lanes_dir)/report.md" "^Progress PR: https://gh.test/pr/2 (landed)$" "and the progress PR's state"
  assert_contains "$(last_lanes_dir)/report.md" "git push origin --delete run/demo progress/demo A-b$" "direct cleanup names progress/<slug> (D12)"
  assert_not_contains "$(last_lanes_dir)/report.md" "^## Resume$" "no resume when done"
  # A refused progress landing: the PR stays open, no repair, the report names it.
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; LANES_PROGRESS=1; export LANES_CONFIG LANES_PROGRESS
  lanes_fixture dprogr direct A:-
  printf 'progress\n' > "$SCEN/progress"
  MERGE_OUTCOMES="ok refuse"; export MERGE_OUTCOMES
  run_lanes start "$MFP"
  unset MERGE_OUTCOMES
  assert_eq OPEN "$(sed -n 's/^state=//p' "$GH/pr-2" 2>/dev/null | tail -n 1)" "the refused progress PR stays open"
  assert_eq 0 "$(land_calls)" "with no repair"
  assert_eq "" "$(prompt_calls '/omega:integration repair demo')" "and no final repair"
  assert_contains "$(last_lanes_dir)/report.md" "progress PR https://gh.test/pr/2 left open" "the report names it"
}
# Last fix: a merge command that merged the PR and then hung past the timeout
# landed the story: the step-3 MERGED check runs after the timeout.
test_lanes_direct_merge_timeout_after_merge_lands() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture mtol direct A:-
  printf 'repair\n' > "$SCEN/A.land"
  MERGE_OUTCOMES=mergehang; STUDIO_OVERNIGHT_SESSION_SECONDS=6; export MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS
  run_lanes start "$MFP"
  unset MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS
  _oid="$(sed -n 's/^oid=//p' "$GH/pr-1" | tail -n 1)"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed ${_oid:-none}$" "a merge that landed and then hung is landed with its merge commit"
  assert_eq 0 "$(land_calls)" "no repair"
  _mp="$(cat "$CALLS/merge.pid" 2>/dev/null)"; _sp="$(cat "$CALLS/merge-sleep.pid" 2>/dev/null)"
  assert_status 1 "the hung merge program is ended" -- kill -0 "${_mp:-999999}"
  assert_status 1 "and its child" -- kill -0 "${_sp:-999999}"
}
# Last fix: a kill grace below studio-gate's own 10 s KILL still ends a merge
# group that ignores TERM: the watchdog KILLs the merge's group itself.
test_lanes_direct_merge_timeout_term_ignored() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture mtti direct A:-
  MERGE_OUTCOMES=termhang; STUDIO_OVERNIGHT_SESSION_SECONDS=6; KILL_GRACE_SECONDS=2
  export MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS KILL_GRACE_SECONDS
  run_lanes start "$MFP"
  unset MERGE_OUTCOMES STUDIO_OVERNIGHT_SESSION_SECONDS KILL_GRACE_SECONDS
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped landing failed (merge command timed out)$" "a TERM-ignoring hung merge is a failed landing"
  _mp="$(cat "$CALLS/merge.pid" 2>/dev/null)"; _sp="$(cat "$CALLS/merge-sleep.pid" 2>/dev/null)"
  _alive=0; kill -0 "${_mp:-999999}" 2>/dev/null && _alive=1; kill -0 "${_sp:-999999}" 2>/dev/null && _alive=1
  assert_eq 0 "$_alive" "no process of the TERM-ignoring merge group survives"
  kill -9 "${_mp:-999999}" "${_sp:-999999}" 2>/dev/null
}
# A final unit that leaves uncommitted work: discarded, never gated, red.
test_lanes_final_dirty_unit_is_red() {
  lanes_fixture findirty integration A:-
  printf 'dirtyfix\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; [ -f fixed ]"
  run_lanes start "$MFP"
  use_gate true
  W="$P/.claude/worktrees/integration-demo"
  assert_eq 1 "$(final_gates)" "an uncommitted repair gets no second gate"
  assert_contains "$P/.studio/runs/demo/gate" "^[0-9a-f]\{40\} red$" "the gate record says red"
  assert_contains "$P/.studio/runs/demo/final" " red$" "the final record says red"
  assert_contains "$GH/calls" "^pr create --draft .*--title \[red\] " "titled [red]"
  assert_contains "$GH/body-1" "final-repair unit left uncommitted changes" "the body names the uncommitted work"
  assert_eq "" "$(git -C "$W" status --porcelain 2>&1)" "the integration worktree is left clean"
  # A progress unit that commits, then leaves more work uncommitted: red too.
  LANES_PROGRESS=1; export LANES_PROGRESS
  lanes_fixture findirty2 integration A:-
  printf 'progress; dirtyfix\n' > "$SCEN/progress"
  run_lanes start "$MFP"
  assert_contains "$P/.studio/runs/demo/final" " red$" "a dirty progress unit makes the step red"
  assert_contains "$GH/body-1" "progress unit left uncommitted changes" "the body names it"
  assert_eq "" "$(git -C "$P/.claude/worktrees/integration-demo" status --porcelain 2>&1)" "and the worktree is clean"
}
# The run budget caps the final units too: at the cap, none launches.
test_lanes_final_budget() {
  LANES_CONFIG='{"overnight": {"run_usd": 10, "session_usd": 8}}'; LANES_PROGRESS=1; export LANES_CONFIG LANES_PROGRESS
  lanes_fixture finbudget integration A:-
  printf 'progress\n' > "$SCEN/progress"; printf 'fixgate\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; exit 1"
  run_lanes start "$MFP"
  use_gate true
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands within the cap (2 + 8 = 10)"
  assert_eq 3 "$(calls)" "no final unit launches past the cap (3 + 8 > 10)"
  assert_eq 1 "$(final_gates)" "one gate, no repair, no second gate"
  assert_contains "$(last_lanes_dir)/report.md" "run budget: no progress unit" "the progress refusal is recorded"
  assert_contains "$(last_lanes_dir)/report.md" "run budget: no final-repair unit" "the repair refusal is recorded"
  assert_contains "$P/.studio/runs/demo/final" " red$" "the final record says red"
}
# One final-repair unit in total: after a conflict repair, a red gate is final.
test_lanes_final_conflict_then_red() {
  LANES_MAIN_MOVES=shared.txt; export LANES_MAIN_MOVES
  lanes_fixture fincfred integration A:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'mergemain\nfixgate\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; exit 1"
  run_lanes start "$MFP"
  use_gate true
  assert_eq 1 "$(prompt_calls '/omega:integration repair demo' | grep -c .)" "exactly one final-repair unit"
  assert_eq 1 "$(final_gates)" "one gate"
  assert_contains "$P/.studio/runs/demo/final" " red$" "the step ends red"
}
# Final fix wave: a stop during the final gate (a Ctrl-C reaches studio-gate,
# exit 130) records no gate result, so a resume runs the gate again instead
# of opening a [red] PR that no complete gate produced. studio-gate's own
# signal exits (129/130/143) with no stop file are not recorded either; any
# other exit (an engine crash's 139) is a red gate: recorded, repaired.
test_lanes_final_gate_interrupted_not_recorded() {
  lanes_fixture fingint integration A:-
  use_gate "echo gate >> '$CALLS/final-gates'; if [ ! -f '$CALLS/gate-once' ]; then : > '$CALLS/gate-once'; : > '$P/.studio/overnight.stop'; exit 130; fi"
  run_lanes start "$MFP"
  assert_eq 1 "$(final_gates)" "the interrupted gate ran once"
  assert_missing "$P/.studio/runs/demo/gate" "a stopped gate records no result"
  assert_not_contains "$GH/calls" "^pr create" "no final PR after the stop"
  assert_eq "" "$(prompt_calls '/omega:integration repair demo')" "no repair after a stopped gate"
  sleep 1
  run_lanes start "$MFP"
  use_gate true
  assert_eq 2 "$(final_gates)" "the resume runs the gate again"
  assert_contains "$GH/calls" "^pr create --draft --base main --head integration/demo --title demo: the demo goal " "the resume's PR is green, not [red]"
  assert_contains "$P/.studio/runs/demo/final" " green$" "the final record says green"
  # studio-gate ended by a signal (130), no stop file: nothing recorded.
  lanes_fixture fingsig integration A:-
  use_gate "echo gate >> '$CALLS/final-gates'; exit 130"
  run_lanes start "$MFP"
  use_gate true
  assert_missing "$P/.studio/runs/demo/gate" "a gate ended by a signal records no result"
  assert_eq "" "$(prompt_calls '/omega:integration repair demo')" "and starts no repair"
  assert_contains "$GH/calls" "^pr create --draft .*--title \[red\] " "the signalled gate's PR is [red]"
  # An engine crash inside the gate (139): a red gate, recorded and repaired.
  lanes_fixture fingsegv integration A:-
  use_gate "echo gate >> '$CALLS/final-gates'; exit 139"
  run_lanes start "$MFP"
  use_gate true
  assert_contains "$P/.studio/runs/demo/gate" "^[0-9a-f]\{40\} red$" "a crashed engine's gate is recorded red"
  assert_eq 1 "$(prompt_calls '/omega:integration repair demo' | grep -c .)" "the one final-repair runs"
  assert_contains "$GH/calls" "^pr create --draft .*--title \[red\] " "the crashed gate's PR is [red]"
}
# ---- T12: status, report.md, run endings ----

test_lanes_status_per_story() {
  lanes_fixture stat integration A:- B:A C:-
  printf 'sleep 4\n' > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -n \"\$(story_calls A)\" ]" 20; sleep 1
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out"; st=$?
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq 0 "$st" "status exits 0 during a run"
  assert_eq "A B C" "$(awk '!/^ / { if (++r > 3) exit; printf "%s%s", s, $1; s=" " }' "$TMP/st.out")" "stories in manifest order"
  assert_contains "$TMP/st.out" "^A  lane [12]  running  unit A T1  task 0/1$" "A is running T1"
  assert_contains "$TMP/st.out" "^B  lane [12]  queued  unit -  task 0/1$" "B waits in A's chain, on A's lane"
  assert_contains "$TMP/st.out" "^C  lane [12]  " "C has its own lane"
  assert_contains "$TMP/st.out" "^gate: " "the gate line"
  assert_contains "$TMP/st.out" "^spent: \\$" "the spend line"
  assert_contains "$TMP/st.out" "^pid: $RPID$" "the runner pid"
}
test_lanes_report_every_ending() {
  lanes_fixture rep integration A:- B:A C:-
  printf 'stop broke\n' > "$SCEN/A"
  printf 'auto\nruling P1 Play: jump twice · a double jump · a single jump\n' > "$SCEN/C"
  run_lanes start "$MFP"
  R="$(last_lanes_dir)/report.md"
  assert_eq 1 "$LS_STATUS" "a partial run exits 1"
  assert_contains "$R" "^# Overnight run — demo$" "the head names the slug"
  assert_contains "$R" "^Ending: partial: 1 landed, 1 stopped, 1 skipped$" "the partial ending counts each kind"
  assert_contains "$R" "^Mode: integration$" "mode"
  assert_contains "$R" "^Target: integration/demo$" "target"
  assert_contains "$R" '^Spent: [$][0-9.]*$' "spend"
  assert_contains "$R" "^Started: .* · Ended: " "start and end times"
  assert_contains "$R" "^Final PR: https://gh.test/pr/1 (green)$" "the final PR"
  assert_eq "A B C" "$(sed -n 's/^## \([ABC]\)$/\1/p' "$R" | tr '\n' ' ' | sed 's/ $//')" "a section per story, in manifest order"
  assert_contains "$R" "^Not landed: stopped — stop: broke$" "a stopped story says why"
  assert_contains "$R" "Not landed: skipped — waits on A" "a skipped story names its blocker"
  assert_contains "$R" "^Branch: C-b$" "the story's branch"
  assert_contains "$R" "^Landed: [0-9a-f]\{40\}$" "a landed story's merge commit"
  assert_contains "$R" "^| 1 | C-T1 | 0 | 1 | " "the story's units table"
  assert_contains "$R" "^- [0-9-]* P1 Play: jump twice" "the story's play-list lines"
  assert_contains "$R" "^## Open bundle-2 PRs$" "open bundle-2 PRs section"
  assert_contains "$R" "^## Resume$" "resume when not done"
  assert_contains "$R" "^cd '$P' && '$RUNNER' start docs/runs/demo.md$" "the resume command names the manifest"
  assert_contains "$R" "^## Cleanup$" "cleanup section"
  assert_contains "$R" "^Run this after the final PR is landed; the run itself never deletes a remote branch\.$" "cleanup's warning line"
  assert_contains "$R" "git push origin --delete run/demo integration/demo C-b$" "cleanup names run, integration and landed story branches"
  assert_status 0 "the run deletes no remote branch (C-b is still on origin)" -- git -C "$P" ls-remote --exit-code origin refs/heads/C-b
  # The runner itself fails (exit 3) in the final step: still a full report.
  LANES_PROGRESS=1; export LANES_PROGRESS
  lanes_fixture reperr integration A:-
  printf 'breakrow\n' > "$SCEN/progress"
  run_lanes start "$MFP"
  R="$(last_lanes_dir)/report.md"
  assert_eq 1 "$LS_STATUS" "a runner error exits 1"
  assert_contains "$R" "^Ending: stop: runner error (exit 3)$" "the runner-error ending"
  assert_contains "$R" "^## A$" "every story is named"
  assert_contains "$R" "^Landed: [0-9a-f]\{40\}$" "with its outcome"
  assert_contains "$R" "^## Resume$" "and the resume command"
  assert_missing "$P/.studio/runs/demo/done" "no done marker"
  assert_missing "$P/.studio/overnight.lock" "the run releases its lock"
}
test_lanes_report_on_lane_crash() {
  lanes_fixture repcrash integration A:-
  printf 'hang\n' > "$SCEN/A"
  KILL_GRACE_SECONDS=2; export KILL_GRACE_SECONDS
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  unset KILL_GRACE_SECONDS
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  kill -9 "$(cat "$P"/.studio/reports/overnight-demo-*/claims/1/pid)"; pkill -9 -f "$TMP/fakebin/claude" 2>/dev/null
  wait_pid_or_fail "$RPID" 60 "the runner ends"
  R="$(last_lanes_dir)/report.md"
  assert_contains "$R" "^## A$" "the crashed story is named"
  assert_contains "$R" "Not landed: stopped: lane crashed (" "the report names a lane crash"
  assert_contains "$R" "^Final PR: none (no story landed)$" "no final PR, and why"
  pkill -9 -f "$TMP/fakebin/claude" 2>/dev/null
}
test_lanes_done_marker() {
  lanes_fixture donem integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "done exits 0"
  assert_file "$P/.studio/runs/demo/done" "done writes runs/<slug>/done"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: done$" "the done ending"
  assert_not_contains "$(last_lanes_dir)/report.md" "^## Resume$" "no resume when done"
  # Every story landed but the final gate is red: not done (ruling 4).
  lanes_fixture donered integration A:-
  printf 'noop\n' > "$SCEN/final-repair"
  use_gate "exit 1"
  run_lanes start "$MFP"
  use_gate true
  assert_eq 1 "$LS_STATUS" "a red final step exits 1"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: partial: 1 landed, 0 stopped, 0 skipped; final PR red$" "a red final PR is not done"
  assert_contains "$(last_lanes_dir)/report.md" "^Final PR: https://gh.test/pr/1 (red)$" "the final PR is named red"
  assert_missing "$P/.studio/runs/demo/done" "no done marker"
}
# AC16: a SIGKILLed runner. Its lane ends its story after the running unit;
# `status` then sweeps every story with no ending and writes report.md.
test_lanes_status_reaps_dead_runner() {
  LANES_CONFIG='{"overnight": {"max_lanes": 1}}'; export LANES_CONFIG
  lanes_fixture reap integration A:- B:A C:-
  printf 'sleep 3\n' > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  R="$(last_lanes_dir)"; lane1="$(cat "$R"/claims/1/pid 2>/dev/null)"
  kill -9 "$RPID"; wait "$RPID" 2>/dev/null
  wait_for "! kill -0 ${lane1:-0} 2>/dev/null" 30
  TESTS_RUN=$((TESTS_RUN + 1))
  if kill -0 "${lane1:-0}" 2>/dev/null; then
    pkill -9 -P "$lane1"; kill -9 "$lane1"; _fail "the lane exits once the runner is gone"
  else _pass "the lane exits once the runner is gone"; fi
  assert_missing "$R/report.md" "a SIGKILLed runner writes no report itself"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out"; st=$?
  assert_eq 1 "$st" "no live run: status exits 1"
  assert_contains "$TMP/st.out" "^no run — the last run: $R$" "status names the ended run"
  assert_contains "$TMP/st.out" "^A  lane 1  stopped  " "A ended"
  assert_contains "$TMP/st.out" "^B  lane 1  skipped  " "B ended"
  assert_contains "$TMP/st.out" "^C  lane -  skipped  " "the unclaimed story ended"
  assert_contains "$R/stories/C" "^skipped: run stopped$" "the sweep ends the unclaimed chain (D2)"
  assert_contains "$R/report.md" "^Ending: stop: runner gone$" "status writes the report"
  for id in A B C; do assert_contains "$R/report.md" "^## $id$" "the report names $id"; done
  assert_contains "$R/report.md" "^Not landed: stopped — stop: runner gone$" "A's outcome"
  assert_contains "$R/report.md" "^Not landed: skipped — run stopped$" "C's outcome"
  assert_contains "$R/events.jsonl" '"event":"story_state","story":"A","state":"stopped","why":"stop: runner gone"}$' "the reap's stopped story_state carries its why"
  assert_contains "$R/events.jsonl" '"event":"story_state","story":"C","state":"skipped","why":"run stopped"}$' "and the skipped one"
  # A resume after a SIGKILLed runner: the stale run gets its report too.
  lanes_fixture reap2 integration A:-
  printf 'sleep 3\n' > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  R="$(last_lanes_dir)"; lane1="$(cat "$R"/claims/1/pid 2>/dev/null)"
  kill -9 "$RPID"; wait "$RPID" 2>/dev/null
  wait_for "! kill -0 ${lane1:-0} 2>/dev/null" 30
  kill -9 "${lane1:-0}" 2>/dev/null
  sleep 1
  run_lanes start "$MFP"
  assert_contains "$R/report.md" "^Ending: stop: runner gone$" "start writes the stale run's report before it resumes"
  assert_eq 0 "$LS_STATUS" "the resumed run lands A"
}
# A runner SIGKILLed after its final step recorded the PR: the reap's report
# names that PR (the report a finished run would have written), not "none".
test_lanes_reap_names_final_pr() {
  LANES_PROGRESS=1; LANES_MAIN_MOVES=main.txt; export LANES_PROGRESS LANES_MAIN_MOVES
  lanes_fixture reapf integration A:-
  printf 'progress\n' > "$SCEN/progress"
  use_gate "echo gate >> '$CALLS/final-gates'"
  run_lanes start "$MFP"
  R="$(last_lanes_dir)"
  assert_contains "$P/.studio/runs/demo/final" " https://gh.test/pr/1 green$" "the fixture: the final step recorded its PR"
  # The runner died after that record: no report, no lock holder.
  rm -f "$R/report.md" "$R/done"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out"
  assert_contains "$R/report.md" "^Final PR: https://gh.test/pr/1 (green)$" "the reaped report names the final PR"
}
# ---- T13: start --detach and --help ----

# detach_stop — end a detached run: stop, then wait for the run lock to clear.
detach_stop() {
  ( cd "$P" && sh "$RUNNER" stop ) > /dev/null 2>&1
  wait_for "[ ! -f '$P/.studio/overnight.lock' ]" 60
  wait_for "[ -z \"\$(pgrep -f '$TMP'; pgrep -f '$RUNNER')\" ]" 20
}
test_lanes_detach_strips_env() {
  lanes_fixture det integration A:-
  st=0
  ( cd "$P" && env CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=x CLAUDE_EFFORT=max CLAUDE_PID=1 AI_AGENT=x \
      CLAUDE_CONFIG_DIR="$TMP/cfg" OMEGA_X=1 STUDIO_STORY=Z STUDIO_X=1 \
      sh "$RUNNER" start --detach "$MFP" ) > "$TMP/det.out" 2>&1 || st=$?
  assert_eq 0 "$st" "detach reports success once status answers"
  assert_contains "$TMP/det.out" "^detached: pid [0-9]*, log " "it prints the pid and the log"
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  detach_stop
  assert_not_contains "$CALLS/1.fullenv" "^CLAUDECODE=" "CLAUDECODE stripped"
  assert_not_contains "$CALLS/1.fullenv" "^CLAUDE_CODE_ENTRYPOINT=" "CLAUDE_CODE_* stripped"
  assert_not_contains "$CALLS/1.fullenv" "^CLAUDE_EFFORT=" "CLAUDE_EFFORT stripped"
  assert_not_contains "$CALLS/1.fullenv" "^CLAUDE_PID=" "CLAUDE_PID stripped"
  assert_not_contains "$CALLS/1.fullenv" "^AI_AGENT=" "AI_AGENT stripped"
  assert_not_contains "$CALLS/1.fullenv" "^OMEGA_X=" "OMEGA_* stripped"
  assert_not_contains "$CALLS/1.fullenv" "^STUDIO_X=" "STUDIO_* stripped"
  assert_contains "$CALLS/1.fullenv" "^CLAUDE_CONFIG_DIR=$TMP/cfg$" "CLAUDE_CONFIG_DIR is kept"
  assert_contains "$CALLS/1.fullenv" "^PATH=" "PATH is kept"
  assert_contains "$CALLS/1.fullenv" "^STUDIO_STORY=A$" "the runner's own STUDIO_STORY is set fresh"
  _dl="$(ls "$P"/.studio/reports/overnight-demo-detached-*.log 2>/dev/null | head -n 1)"
  assert_eq 1 "$([ -n "$_dl" ] && echo 1 || echo 0)" "the detached log is under reports"
  _dr="$(ls -d "$P"/.studio/reports/overnight-demo-[0-9]* 2>/dev/null | tail -n 1)"
  assert_eq 1 "$([ -L "$_dr/runner.log" ] && echo 1 || echo 0)" "the run dir links runner.log"
}
test_lanes_detach_refusal_in_foreground() {
  lanes_fixture detr direct A:-                        # direct without merge_command
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/detr.out" 2>&1 || st=$?
  assert_eq 2 "$st" "preflight runs in the foreground"
  assert_contains "$TMP/detr.out" "merge_command" "and its refusal is shown"
  assert_eq 0 "$(calls)" "no runner was started"
}
test_lanes_detach_child_refusal_surfaces() {
  lanes_fixture detk integration A:-
  printf 'hang\n' > "$SCEN/A"
  # A SIGKILLed runner whose lane still runs: the child's start refuses (2).
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  kill -KILL "$RPID" 2>/dev/null
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/detk.out" 2>&1 || st=$?
  pkill -f "$TMP/fakebin/claude" 2>/dev/null; pkill -f "$RUNNER start" 2>/dev/null
  wait "$RPID" 2>/dev/null
  wait_for "[ -z \"\$(pgrep -f '$TMP'; pgrep -f '$RUNNER')\" ]" 20
  assert_eq 2 "$st" "a refused detached start exits with the refusal"
  assert_contains "$TMP/detk.out" "lanes still run" "and shows the child's message"
  assert_not_contains "$TMP/detk.out" "^detached:" "and prints no success line"
}
test_lanes_detach_timeout_lock_held_points_at_status() {
  lanes_fixture dtl integration A:-
  printf 'hang\n' > "$SCEN/A"
  export STUDIO_OVERNIGHT_DETACH_STATUS_CMD=false
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/dtl.out" 2>&1 || st=$?
  unset STUDIO_OVERNIGHT_DETACH_STATUS_CMD
  assert_eq 1 "$st" "a status timeout exits 1"
  assert_contains "$TMP/dtl.out" "is live" "a lock-holding child is reported live"
  assert_contains "$TMP/dtl.out" "/studio-overnight' stop" "and stop is named, by its absolute path"
  assert_not_contains "$TMP/dtl.out" "run the plain command" "no plain start is offered"
  assert_eq 1 "$([ -f "$P/.studio/overnight.lock" ] && echo 1 || echo 0)" "the run still holds its lock"
  # The hung stub would hold the run past stop: end it, then wait the run out.
  ( cd "$P" && sh "$RUNNER" stop ) > /dev/null 2>&1; pkill -f "$TMP/fakebin/claude" 2>/dev/null
  detach_stop
}
test_lanes_detach_timeout_no_lock_ends_child() {
  lanes_fixture dtn integration A:-
  export STUDIO_OVERNIGHT_DETACH_STATUS_CMD=false
  export STUDIO_OVERNIGHT_DETACH_CHILD_CMD="sleep 301 & sleep 301"
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/dtn.out" 2>&1 || st=$?
  unset STUDIO_OVERNIGHT_DETACH_STATUS_CMD STUDIO_OVERNIGHT_DETACH_CHILD_CMD
  assert_eq 1 "$st" "a status timeout exits 1"
  assert_contains "$TMP/dtn.out" "never took the lock" "the message says the child was ended"
  assert_contains "$TMP/dtn.out" "start " "and the plain command is printed"
  sleep 1
  assert_eq 0 "$(pgrep -f 'sleep 301' | wc -l | tr -d ' ')" "no child survives"
}
test_lanes_help_modes() {
  sh "$RUNNER" --help > "$TMP/help"
  for t in "integration" "direct" "next" "gate lock" "max_lanes" "merge_command" "--detach" \
    "STUDIO_OVERNIGHT_POLL_SECONDS" "STUDIO_OVERNIGHT_LAND_HOOK" "STUDIO_OVERNIGHT_LABEL" "STUDIO_OVERNIGHT_GATE_CMD" "report.md"; do
    assert_contains "$TMP/help" "$t" "help names $t"
  done
  assert_contains "$REPO_ROOT/README.md" "studio-overnight start <manifest>" "README documents manifest runs"
  assert_contains "$REPO_ROOT/README.md" "studio-overnight next" "README documents next"
}
# ---- The finish gate under a lane, and status from anywhere (2026-10-02) ----

ACT="$REPO_ROOT/tests/fixtures/overnight-activity.jsonl"
REG="$HOME/.claude-gamedev/runs"
ELSEWHERE="$TMP/elsewhere"; mkdir -p "$ELSEWHERE"
# status_from DIR — `studio-overnight status` run in DIR: ST_RC, output in $TMP/st.out.
status_from() { ST_RC=0; ( cd "$1" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1 || ST_RC=$?; }

# A unit that leaves a gate running in the background (the 2026-10-02 finish):
# the runner ends it when the unit ends, so the retry never waits behind it
# and no gate outlives its unit.
test_lanes_left_gate_reaped() {
  lanes_fixture orphan integration A:-
  printf 'bggate 100; noop\ngate 1\n' > "$SCEN/A"
  _t0="$(date +%s)"
  run_lanes start "$MFP"
  _secs=$(( $(date +%s) - _t0 ))
  _gp="$(cat "$CALLS/bggate.pid" 2>/dev/null)"
  assert_eq 0 "$LS_STATUS" "A lands after its left-behind gate is ended"
  assert_status 1 "the left-behind gate's command is gone" -- kill -0 "${_gp:-999999}"
  assert_eq "" "$(pgrep -f 'studio-gate studio-test' 2>/dev/null | while read -r p; do ps -o args= -p "$p" | grep -F "$CALLS" ; done)" "no studio-gate of this run survives"
  assert_missing "$P/.studio/gate.lock" "the gate lock is free after the run"
  assert_missing "$P/.studio/gate.units" "every unit's gate registry is cleared"
  assert_contains "$LS_ERR" "left a gate running after it ended (pid [0-9]*) — ended it" "the runner says it ended the gate"
  assert_eq 1 "$(grep -c '^s A ' "$CALLS/gate.iv" 2>/dev/null)" "the retry's own gate ran"
  assert_eq yes "$([ "$_secs" -lt 60 ] && echo yes || echo "no ($_secs s)")" "the retry never waited behind the 100 s gate"
  assert_contains "$(last_lanes_dir)/lanes/1/units.tsv" "	A-T1	0	[^	]*	[^	]*	0	noprog$" "the unit that left the gate made no progress"
  assert_contains "$CALLS/1.fullenv" "^STUDIO_UNIT_TAG=overnight-demo-[0-9-]*-1-1-A-T1$" "each session carries its unit tag"
}
# A unit the session cap ends with no progress is `timed out`, not noprog,
# and the story's ending says so.
test_lanes_timed_out_outcome() {
  LANES_CONFIG='{"overnight": {"kill_grace_seconds": 5}}'; export LANES_CONFIG
  lanes_fixture tmo integration A:-
  printf 'hang\nhang\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_SESSION_SECONDS=2; export STUDIO_OVERNIGHT_SESSION_SECONDS
  run_lanes start "$MFP"; unset STUDIO_OVERNIGHT_SESSION_SECONDS
  R="$(last_lanes_dir)"
  assert_eq "timed out|timed out" "$(cut -f7 "$R/lanes/1/units.tsv" | paste -sd'|' -)" "both capped units are timed out"
  assert_contains "$R/stories/A" "^stopped timed out on T1 (session_minutes 90)$" "the ending names the timeout"
  assert_contains "$R/report.md" "^Not landed: stopped — timed out on T1 " "and so does the report"
}
# The runner's terminal: a line per unit start and end, and a heartbeat with
# the unit's last activity while it runs.
test_lanes_heartbeat() {
  lanes_fixture hb integration A:-
  printf 'emit %s; sleep 4\n' "$ACT" > "$SCEN/A"
  STUDIO_OVERNIGHT_HEARTBEAT_SECONDS=1; export STUDIO_OVERNIGHT_HEARTBEAT_SECONDS
  run_lanes start "$MFP"; unset STUDIO_OVERNIGHT_HEARTBEAT_SECONDS
  assert_contains "$LS_ERR" "^studio-overnight: run .*overnight-demo-.* started (pid [0-9]*) — watch: '.*studio-overnight' watch" "the start line names watch by its absolute path"
  assert_contains "$LS_ERR" "^studio-overnight: A T1 · started (lane 1)$" "a unit's start"
  assert_contains "$LS_ERR" "^studio-overnight: A 1-A-T1 · [0-9]*s · ui-designer · \"T1 loader fold options\" · Bash: npx vitest run \"src/loader/fold.test.ts\"$" "a heartbeat with the last activity"
  assert_contains "$LS_ERR" "^studio-overnight: A T1 · ended: progress · exit 0 · [0-9.]* min$" "a unit's end"
}
test_lanes_activity_verb() {
  assert_eq 'ui-designer · "T1 loader fold options" · Bash: npx vitest run "src/loader/fold.test.ts"' \
    "$(sh "$RUNNER" activity "$ACT")" "the running subagent, then its last tool call"
  { cat "$ACT"; printf '%s\n' '{"type":"user","message":{"content":[{"tool_use_id":"toolu_A1","type":"tool_result","content":"done"}]}}'; } > "$TMP/act2.jsonl"
  assert_eq 'Bash: npx vitest run "src/loader/fold.test.ts"' "$(sh "$RUNNER" activity "$TMP/act2.jsonl")" "a finished subagent is not named"
  printf '{"type":"system","subtype":"init"}\n' > "$TMP/act3.jsonl"
  assert_eq starting "$(sh "$RUNNER" activity "$TMP/act3.jsonl")" "no tool call yet"
}
# Status from outside any project, with zero, one and two live runs, then
# after they ended; and from the project through a symlinked spelling of its
# path (GameDev -> GameDev.nosync).
test_lanes_status_anywhere() {
  rm -rf "$REG"
  status_from "$ELSEWHERE"
  assert_eq 1 "$ST_RC" "zero runs: exit 1"
  assert_contains "$TMP/st.out" "^no run — nothing registered in $REG, and $ELSEWHERE is not a studio project" "zero runs: it says where it looked"
  # One live run, started through a symlinked path.
  lanes_fixture any1 integration A:-
  P1="$P"; ln -s "$P1" "$TMP/any1-link"
  printf 'emit %s; sleep 8\n' "$ACT" > "$SCEN/A"
  ( cd "$TMP/any1-link" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & R1=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 30; sleep 1
  status_from "$ELSEWHERE"
  assert_eq 3 "$ST_RC" "one live run elsewhere: exit 3 (0 is kept for this project's run)"
  assert_eq 1 "$(ls "$REG" | grep -c '^overnight-demo-[0-9-]*-[0-9]*$')" "the entry is named <run dir>-<runner pid>"
  assert_contains "$TMP/st.out" "^== overnight-demo-[0-9-]* — $P1$" "it names the run and its project (the real path)"
  assert_contains "$TMP/st.out" "^A  lane 1  running  unit A T1  task 0/1$" "the project's own status follows"
  assert_contains "$TMP/st.out" "^    1-A-T1 · [0-9]*s · ui-designer · \"T1 loader fold options\" · Bash: npx vitest" "the running unit's last activity in one line"
  assert_contains "$TMP/st.out" "^gate: free$" "the gate lock"
  status_from "$TMP/any1-link"
  assert_eq 0 "$ST_RC" "from the symlinked spelling of the project: live"
  status_from "$P1"
  assert_eq 0 "$ST_RC" "from the real path: live"
  # Two live runs.
  lanes_fixture any2 integration B:-
  P2="$P"; printf 'sleep 6\n' > "$SCEN/B"
  ( cd "$P2" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & R2=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 30
  status_from "$ELSEWHERE"
  assert_eq 3 "$ST_RC" "two live runs elsewhere: exit 3"
  assert_eq 2 "$(grep -c '^== overnight-demo-' "$TMP/st.out")" "both runs are listed"
  assert_contains "$TMP/st.out" " — $P2$" "the second project is named"
  # A project with no run of its own names the live ones elsewhere.
  lanes_fixture any3 integration C:-
  status_from "$P"
  assert_eq 1 "$ST_RC" "a project with no run: exit 1"
  assert_contains "$TMP/st.out" "^no run in $P — " "it says where it looked"
  assert_contains "$TMP/st.out" "^live elsewhere: $P1 (pid $R1)" "and names the live run elsewhere"
  wait_pid_or_fail "$R1" 90 "run 1 ends"; wait_pid_or_fail "$R2" 90 "run 2 ends"
  # After they ended: the last one, read clearly.
  status_from "$ELSEWHERE"
  assert_eq 1 "$ST_RC" "ended runs: exit 1"
  assert_contains "$TMP/st.out" "^no live run (registry $REG) — the last run was in " "it names the last run's project"
  assert_contains "$TMP/st.out" "^ended (done) — report: .*/report.md$" "an ended run in one line"
  assert_eq 0 "$(ls "$REG" | grep -c '^overnight-')" "no live entries remain"
  assert_contains "$REG/last" "^ended=" "the newest ended run is kept as last"
  # A registered project that lost its .studio/ is named, never re-entered:
  # the nested status must not fall back to the registry and recurse.
  mkdir -p "$TMP/nostudio"; printf 'root=%s\npid=1\n' "$TMP/nostudio" > "$REG/last"
  ( cd "$ELSEWHERE" && exec sh "$RUNNER" status ) > "$TMP/st.out" 2>&1 & _sp=$!
  wait_pid_or_fail "$_sp" 10 "a registered root with no .studio/ answers at once"
  assert_contains "$TMP/st.out" "^(the project has no .studio/ any more)$" "and says so"
  assert_eq 1 "$(grep -c '^no live run' "$TMP/st.out")" "once, with no recursion"
}
# An ended partial run: the story that stopped, the report and the resume.
test_lanes_status_ended_partial() {
  lanes_fixture endp integration S1:- S2:S1
  printf 'noop\nnoop\n' > "$SCEN/S1"
  run_lanes start "$MFP"
  status_from "$P"
  assert_eq 1 "$ST_RC" "an ended run: exit 1"
  assert_contains "$TMP/st.out" "^ended (partial) — S1 stopped: no progress on T1 — report: $(last_lanes_dir)/report.md — resume: cd '$P' && '.*studio-overnight' start docs/runs/demo.md$" "ended (partial) — who stopped and why — report — resume"
  status_from "$ELSEWHERE"
  assert_contains "$TMP/st.out" "^ended (partial) — S1 stopped: no progress on T1 — " "the same line from anywhere"
}
test_lanes_watch() {
  STUDIO_OVERNIGHT_WATCH_COUNT=2; export STUDIO_OVERNIGHT_WATCH_COUNT
  st=0; ( cd "$ELSEWHERE" && sh "$RUNNER" watch 1 ) > "$TMP/w.out" 2>&1 || st=$?
  st2=0; ( cd "$ELSEWHERE" && sh "$RUNNER" status --follow 1 ) > "$TMP/w2.out" 2>&1 || st2=$?
  unset STUDIO_OVERNIGHT_WATCH_COUNT
  assert_eq "0 0" "$st $st2" "watch and status --follow exit 0"
  assert_eq 2 "$(grep -c '^studio-overnight watch · [0-9:]* · every 1s · Ctrl-C to quit$' "$TMP/w.out")" "two refreshes"
  assert_eq 2 "$(grep -c '^studio-overnight watch · ' "$TMP/w2.out")" "status --follow is watch"
  assert_not_contains "$TMP/w.out" '"type"' "no raw JSON"
  assert_status 2 "a bad interval is usage" -- sh "$RUNNER" watch x
}
# The preflight warns when the slowest recent studio-test leaves a finish
# unit too little room under session_minutes.
test_lanes_gate_room_warning() {
  lanes_fixture room integration A:-
  printf '%s studio-test 600 0\n%s studio-test 5400 0\n%s merge 9000 0\n' 1 2 3 > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "a warning, not a refusal"
  assert_contains "$LS_ERR" "warning: the slowest of the last 10 studio-test runs took 90 min.*set overnight.session_minutes to at least 118" "the warning names the gate time and the minimum"
  printf '1 studio-test 600 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_not_contains "$LS_ERR" "warning: the slowest" "a 10-minute gate fits 90 minutes"
}

test_lanes_story_listed_events() {
  lanes_fixture evl integration A:- B:A C:-
  run_lanes start "$MFP"
  E="$(last_lanes_dir)/events.jsonl"
  assert_eq run_started "$(sed -n '1s/.*"event":"\([a-z_]*\)".*/\1/p' "$E")" "run_started is the first line"
  assert_contains "$E" '"event":"run_started","mode":"integration","max_lanes":2,"hold_minutes":0}$' "mode, lanes started, hold_minutes"
  assert_eq "story_listed story_listed story_listed" "$(sed -n '2,4s/.*"event":"\([a-z_]*\)".*/\1/p' "$E" | tr '\n' ' ' | sed 's/ $//')" "every story_listed right after run_started"
  assert_contains "$E" '"story":"A","chain":1,"depends":\[\]}$' "A: chain 1, no dependencies"
  assert_contains "$E" '"story":"B","chain":1,"depends":\["A"\]}$' "B: in A's chain, depends on A"
  assert_contains "$E" '"story":"C","chain":2,"depends":\[\]}$' "C: chain 2"
  for id in A B C; do
    assert_contains "$E" "\"event\":\"story_state\",\"story\":\"$id\",\"state\":\"landed\"}\$" "$id landed"
  done
  assert_eq run_ended "$(sed -n '$s/.*"event":"\([a-z_]*\)".*/\1/p' "$E")" "run_ended is the last line"
}
test_lanes_unit_env_run_dir() {
  lanes_fixture uenvl integration A:-
  run_lanes start "$MFP"
  assert_contains "$CALLS/1.fullenv" "^STUDIO_RUN_DIR=$(last_lanes_dir)$" "a lane unit gets STUDIO_RUN_DIR"
}

# ---- #27: lane holds ----
# lholds_on SECS — holds on for the next run (deadline SECS s, 1 s poll);
# lholds_off — the suite's default.
lholds_on() {
  STUDIO_OVERNIGHT_HOLD_MINUTES=5; STUDIO_OVERNIGHT_HOLD_SECONDS="$1"; STUDIO_OVERNIGHT_POLL_SECONDS=1
  export STUDIO_OVERNIGHT_HOLD_MINUTES STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
}
lholds_off() { STUDIO_OVERNIGHT_HOLD_MINUTES=0; unset STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS; }
# lanes_bg — `start $MFP` in the background: RPID.
lanes_bg() { ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > "$TMP/lbg.out" 2> "$TMP/lbg.err" < /dev/null & RPID=$!; }
# rec ID — story ID's record in the newest run.
rec() { cat "$(last_lanes_dir)/stories/$1" 2>/dev/null; }
# is_held ID — ID's record is a held one.
is_held() { case "$(rec "$1")" in "held "*) return 0 ;; esac; return 1; }
# lverb ARGS… — `studio-overnight ARGS` in $P: LV_STATUS, LV_OUT, LV_ERR.
lverb() {
  LV_STATUS=0
  ( cd "$P" && sh "$RUNNER" "$@" ) > "$TMP/lv.out" 2> "$TMP/lv.err" || LV_STATUS=$?
  LV_OUT="$TMP/lv.out"; LV_ERR="$TMP/lv.err"
}

test_lanes_held_dependents_wait() {
  lanes_fixture hdw integration A:- C:- D:A,C
  lholds_on 120
  printf 'auto\nstop need art\ninbox; ruling Directive 1: use the bus\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held stop: need art until 20[0-9-]*T[0-9:]*Z$" "a feature Stop: holds the story (AC17, AC19)"
  wait_for 'case "$(rec C)" in landed*) true ;; *) false ;; esac' 60
  assert_contains "$(last_lanes_dir)/stories/C" "^landed " "another lane runs on while A is held"
  assert_eq waiting "$(rec D)" "a story that depends on a held one keeps waiting"
  lverb status
  assert_contains "$LV_OUT" "^A  lane [0-9]*  held  " "status: A's state is held"
  assert_contains "$LV_OUT" "^    held — stop: need art — until [0-9][0-9]:[0-9][0-9] — say / resume / stop A$" "the held line in place of the unit line (AC27)"
  lverb say A -- use the bus; assert_eq 1 "$(cat "$LV_OUT")" "say A while held"
  lverb resume A; assert_eq "resume requested: A resumes within one poll" "$(cat "$LV_OUT")" "resume A"
  wait_pid_or_fail "$RPID" 120 "the run finishes after the resume"
  assert_eq 0 "$WP_STATUS" "every story lands"
  for id in A C D; do assert_contains "$(last_lanes_dir)/stories/$id" "^landed " "$id landed"; done
  _n="$(story_calls A | sort -n | sed -n 3p)"
  assert_contains "$CALLS/$_n.inbox" '^\[1, story\] use the bus$' "A's next unit got the directive"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"event":"message_requeued"' "the recorded directive is not requeued"
  assert_eq "1 A-T1 progress,2 A-final-review stop,3 A-final-review progress,4 A-finish done," "$(story_rows A)" "unit numbers run on after the hold"
  assert_contains "$(last_lanes_dir)/events.jsonl" '"story":"A","state":"held","why":"stop: need art","until":"20' "a held event"
  lholds_off
}
test_lanes_resume_after_gate_red_runs_gate_repair() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 0}}'; export LANES_CONFIG
  lanes_fixture rgr integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — studio-test: 1 failed\nauto\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held stop: gate red — studio-test: 1 failed until " "gate_repairs 0: a red finish holds"
  assert_eq 0 "$(gate_calls)" "no repair before the resume"
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq 1 "$(gate_calls)" "one gate-repair unit"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish stop,4 A-gate-repair progress,5 A-finish done," \
    "$(story_rows A)" "the first unit after the resume is the gate repair (AC20)"
  lholds_off
}
test_lanes_resume_gate_repairs_counted() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 0}}'; export LANES_CONFIG
  lanes_fixture rgc integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — x\nstop gate red — y\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  lverb resume A
  wait_for 'case "$(rec A)" in "held gate red after"*) true ;; *) false ;; esac' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held gate red after 1 repairs — y until " "the resume-granted repair counts (AC20)"
  lverb stop A; assert_eq "stop requested: A stops within one poll" "$(cat "$LV_OUT")" "stop A while held"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped gate red after 1 repairs — y" "$(rec A)" "stop on a held story ends it stopped <why> (AC23)"
  assert_eq 1 "$(gate_calls)" "one repair unit"
  lholds_off
}
test_lanes_resume_not_gate_red_no_repair_unit() {
  lanes_fixture rng integration A:-
  lholds_on 120
  printf 'auto\nstop need art\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for 'is_held A' 60
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq 0 "$(gate_calls)" "a latest Stop that is not gate red gets no repair unit"
  assert_eq "1 A-T1 progress,2 A-final-review stop,3 A-final-review progress,4 A-finish done," "$(story_rows A)" "the unit loop resumes"
  lholds_off
}
test_lanes_gate_repair_noprog_holds() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture grn integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — x\nauto\n' > "$SCEN/A"
  printf 'noop\ngaterepair\n' > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held gate repair made no progress until " "a gate repair with no progress holds (AC17)"
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq 2 "$(gate_calls)" "the latest Stop is still gate red: the resume gets a repair unit (R29)"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish stop,4 A-gate-repair noprog,5 A-gate-repair progress,6 A-finish done," \
    "$(story_rows A)" "repair, hold, repair, fresh finish"
  lholds_off
}
test_lanes_landing_never_holds() {
  lholds_on 120
  lanes_fixture lnh integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'noop\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped repair made no progress$" "a land repair with no progress ends at once (AC18)"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  lanes_fixture lnh2 integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'stop cannot resolve\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: cannot resolve$" "a land repair's Stop: ends at once"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  lholds_off
}
test_lanes_stop_queued_story() {
  lanes_fixture sqs integration A:- B:A D:B
  printf 'sleep 4; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec B)" = queued ]' 30
  lverb stop B; assert_eq "stop requested: B stops when its lane reaches it" "$(cat "$LV_OUT")" "stop on a queued story"
  wait_pid_or_fail "$RPID" 120 "the run ends"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq "stopped by operator" "$(rec B)" "B never starts (AC7, R5)"
  assert_eq "skipped B" "$(rec D)" "the rest of the chain is skipped, as today"
  assert_eq "" "$(story_calls B)" "B ran no unit"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "no control file left"
}
test_lanes_stop_running_story() {
  lanes_fixture srs integration A:-
  printf 'sleep 4; auto\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec A)" = running ]' 30
  lverb stop A; assert_eq "stop requested: A stops after its running unit" "$(cat "$LV_OUT")" "stop on a running story"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "after its unit (AC23)"
  assert_eq "1 A-T1 progress," "$(story_rows A)" "one unit ran"
}
test_lanes_stop_waiting_story() {
  lanes_fixture sws integration A:- B:- C:A,B
  STUDIO_OVERNIGHT_POLL_SECONDS=1; export STUDIO_OVERNIGHT_POLL_SECONDS
  printf 'sleep 8; auto\n' > "$SCEN/A"; printf 'sleep 8; auto\n' > "$SCEN/B"
  lanes_bg
  wait_for '[ "$(rec C)" = waiting ]' 30
  lverb stop C; assert_eq "stop requested: C stops when its lane reaches it" "$(cat "$LV_OUT")" "stop on a waiting story"
  wait_for '[ "$(rec C)" = "stopped by operator" ]' 5
  assert_eq "stopped by operator" "$(rec C)" "a waiting story stops within one poll"
  assert_eq 0 "$(awk 'BEGIN { n = 0 } /landed/ { n++ } END { print n }' "$(last_lanes_dir)/stories/A")" "before A lands"
  wait_pid_or_fail "$RPID" 120 "the run ends"
  assert_eq "" "$(story_calls C)" "C ran no unit"
  for id in A B; do assert_contains "$(last_lanes_dir)/stories/$id" "^landed " "$id still lands"; done
  unset STUDIO_OVERNIGHT_POLL_SECONDS
}
test_lanes_hold_waiting_story_holds_at_start() {
  lanes_fixture hws integration A:- B:- C:A,B
  lholds_on 120
  printf 'sleep 4; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(rec C)" = waiting ]' 30
  lverb hold C; assert_eq "hold requested: C holds when it would start" "$(cat "$LV_OUT")" "hold on a waiting story"
  wait_for 'is_held C' 60
  assert_contains "$(last_lanes_dir)/stories/C" "^held held by operator until " "C holds when it would start (R7)"
  assert_eq "" "$(story_calls C)" "before any unit"
  lverb resume C
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/C" "^landed " "C runs and lands after the resume"
  lholds_off
}
test_lanes_hold_running_then_resume() {
  lanes_fixture hrr integration A:-
  lholds_on 120
  printf 'sleep 4; auto\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec A)" = running ]' 30
  lverb hold A; assert_eq "hold requested: A holds at its next unit boundary" "$(cat "$LV_OUT")" "hold on a running story"
  wait_for 'is_held A' 30
  assert_contains "$(last_lanes_dir)/stories/A" "^held held by operator until " "held at the boundary"
  assert_eq "1 A-T1 progress," "$(story_rows A)" "after its running unit"
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish done," "$(story_rows A)" "the units ran on"
  lholds_off
}
test_lanes_run_stop_held_was_held() {
  lanes_fixture rsw integration A:- B:A
  lholds_on 120
  printf 'auto\nstop broke\n' > "$SCEN/A"
  lanes_bg
  wait_for 'is_held A' 60
  lverb stop; assert_contains "$LV_OUT" "^stop requested: the run ends after its running unit" "bare stop, as today"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped stopped by user (was held: stop: broke)" "$(rec A)" "the halt's reason, then the hold's (AC25)"
  assert_eq "skipped A" "$(rec B)" "its chain is skipped"
  lholds_off
}
test_lanes_final_step_no_delivery() {
  lanes_fixture fnd integration A:-
  printf 'auto\nauto\nsay left for later; auto\n' > "$SCEN/A"
  printf 'inbox; fixgate\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; [ -f fixed ]"
  run_lanes start "$MFP"
  use_gate true
  _n="$(prompt_calls '/omega:integration repair demo')"
  assert_file "$CALLS/$_n.inbox" "the final repair unit ran, and ran the hook"
  assert_eq "" "$(cat "$CALLS/$_n.inbox" 2>/dev/null)" "the final step's unit (no STUDIO_STORY) gets no delivery (AC9)"
  assert_file "$(last_lanes_dir)/inbox/A/1.msg" "the message stays pending"
  assert_contains "$(last_lanes_dir)/report.md" "^Operator messages left:$" "the report lists A's messages left (AC14)"
  assert_contains "$(last_lanes_dir)/report.md" "^- 1 (story, requeues 0): left for later$" "with the message"
}
test_lanes_deadline() {
  lanes_fixture ldl integration A:- B:A
  lholds_on 2
  printf 'auto\nstop need art\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_eq "stopped stop: need art (held 0h0m, no reply)" "$(rec A)" "the deadline ends the story (AC24)"
  assert_eq "skipped A" "$(rec B)" "and skips its chain"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "no control file left"
  lholds_off
}

test_lanes_stop_at_done_never_lands() {
  lanes_fixture sdn integration A:-
  printf 'auto\nauto\nsleep 5; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 3 ] && [ "$(rec A)" = running ]' 40
  lverb stop A; assert_eq "stop requested: A stops after its running unit" "$(cat "$LV_OUT")" "stop during the last unit"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "a .stop at done stops before landing (R5)"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish done," "$(story_rows A)" "the last unit was done"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "no control file left"
}
test_lanes_stop_held_by_operator() {
  lanes_fixture sho integration A:-
  lholds_on 120
  printf 'sleep 4; auto\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec A)" = running ]' 30
  lverb hold A
  wait_for 'is_held A' 30
  lverb stop A; assert_eq "stop requested: A stops within one poll" "$(cat "$LV_OUT")" "stop on an operator-held story"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "stopped by operator, not stopped held by operator (R5)"
  lholds_off
}
test_lanes_stop_pending_never_holds() {
  lanes_fixture spn integration A:-
  lholds_on 120
  printf 'auto\nsleep 4; stop need art\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 2 ] && [ "$(rec A)" = running ]' 30
  lverb stop A
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "a stop sent during the unit that ends holdable ends the story (R5)"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "no held event for a hold that never waited"
  lholds_off
}
test_lanes_gate_repair_own_stop_holds() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture gro integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — x\n' > "$SCEN/A"
  printf 'stop gate repair red — y\n' > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held stop: gate repair red — y until " "a gate-repair unit's own feature Stop holds (AC17)"
  lverb stop A
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped stop: gate repair red — y" "$(rec A)" "stop on the held story ends it with its why (AC23)"
  lholds_off
}
test_lanes_directive_cap_holds() {
  LANES_CONFIG='{"overnight": {"retries": 0}}'; export LANES_CONFIG
  lanes_fixture dch integration A:-
  lholds_on 120
  printf 'say keep to the plan\ninbox\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held directive 1 not recorded until " "an unrecorded directive past the limit holds the lane story (AC14)"
  lverb stop A
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped directive 1 not recorded" "$(rec A)" "stop ends it with that why"
  lholds_off
}
test_lanes_hold_during_last_unit_lands_and_clears() {
  lanes_fixture hlu integration A:-
  lholds_on 120
  printf 'auto\nauto\nsleep 5; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 3 ] && [ "$(rec A)" = running ]' 40
  lverb hold A
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "a hold sent during the last unit: the story still lands"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "the .hold is cleared when the story ends (R25)"
  lholds_off
}

# Last: no process any test started is still alive.
test_lanes_no_orphans() {
  _left="$(pgrep -f "$TMP" 2>/dev/null; pgrep -f "$RUNNER" 2>/dev/null)"
  assert_eq "" "$_left" "no stub session, lane or runner outlives its test"
}

run_tests test_lanes_chain_rule test_lanes_manifest_refusals test_lanes_preflight_backlog_tasks test_lanes_manifest_header_refusals \
  test_lanes_preflight_story_checks test_lanes_preflight_story_state test_lanes_docs_unreachable \
  test_lanes_git_too_old test_lanes_sourced_only test_lanes_next \
  test_lanes_next_all_planned_and_ambiguous test_lanes_next_plan_before_autopilot \
  test_lanes_two_independent_to_landed test_lanes_max_lanes_one_serializes test_lanes_models_and_env \
  test_lanes_story_stop_isolated test_lanes_budget test_lanes_budget_sums_all_lanes test_lanes_overhead \
  test_lanes_docs_revision test_lanes_waiting_chain_starts_after_deps test_lanes_skip_on_stopped_dep \
  test_lanes_lane_kill9 test_lanes_end_sessions_spaced_path test_lanes_sigint test_lanes_runner_gone test_lanes_stop_file \
  test_lanes_land_clean_integration test_lanes_land_clean_direct test_lanes_land_conflict_one_repair \
  test_lanes_land_second_conflict_stops test_lanes_land_repair_no_progress test_lanes_direct_refused_then_repaired test_lanes_direct_merged_never_repairs test_lanes_direct_merge_timeout \
  test_lanes_land_once_explicit_branch test_lanes_land_idempotent \
  test_lanes_land_crash_after_push test_lanes_land_lock_reclaim test_lanes_land_shipped_resume \
  test_lanes_gate_never_overlaps test_lanes_gate_repair_then_lands test_lanes_gate_repair_cap \
  test_lanes_gate_repair_same_stop_twice test_lanes_gate_repairs_zero test_lanes_gate_hard_stops_no_repair \
  test_lanes_gate_repair_no_progress test_lanes_gate_repair_model_and_no_log test_lanes_gate_repair_budget test_lanes_gate_repair_halt \
  test_lanes_final_step_once test_lanes_final_red_after_repair \
  test_lanes_final_repair_turns_green test_lanes_final_conflict test_lanes_final_resume_edits_pr \
  test_lanes_final_skipped_on_stop_or_nothing_landed test_lanes_final_gate_default test_lanes_direct_progress_landing \
  test_lanes_final_dirty_unit_is_red test_lanes_final_budget test_lanes_final_conflict_then_red test_lanes_final_gate_interrupted_not_recorded \
  test_lanes_direct_merge_timeout_after_merge_lands test_lanes_direct_merge_timeout_term_ignored \
  test_lanes_status_per_story test_lanes_report_every_ending test_lanes_report_on_lane_crash \
  test_lanes_done_marker test_lanes_status_reaps_dead_runner test_lanes_reap_names_final_pr \
  test_lanes_detach_strips_env test_lanes_detach_refusal_in_foreground test_lanes_detach_child_refusal_surfaces \
  test_lanes_detach_timeout_lock_held_points_at_status test_lanes_detach_timeout_no_lock_ends_child \
  test_lanes_help_modes test_lanes_left_gate_reaped test_lanes_timed_out_outcome test_lanes_heartbeat \
  test_lanes_activity_verb test_lanes_status_anywhere test_lanes_status_ended_partial test_lanes_watch \
  test_lanes_gate_room_warning test_lanes_story_listed_events test_lanes_unit_env_run_dir \
  test_lanes_held_dependents_wait test_lanes_resume_after_gate_red_runs_gate_repair test_lanes_resume_gate_repairs_counted \
  test_lanes_resume_not_gate_red_no_repair_unit test_lanes_gate_repair_noprog_holds test_lanes_landing_never_holds \
  test_lanes_stop_queued_story test_lanes_stop_running_story test_lanes_stop_waiting_story \
  test_lanes_hold_waiting_story_holds_at_start test_lanes_hold_running_then_resume test_lanes_run_stop_held_was_held \
  test_lanes_final_step_no_delivery test_lanes_deadline \
  test_lanes_stop_at_done_never_lands test_lanes_stop_held_by_operator test_lanes_stop_pending_never_holds \
  test_lanes_gate_repair_own_stop_holds test_lanes_directive_cap_holds test_lanes_hold_during_last_unit_lands_and_clears \
  test_lanes_no_orphans
