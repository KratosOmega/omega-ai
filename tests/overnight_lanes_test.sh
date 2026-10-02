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
# The stub gh (harness part 3): every call's argv is logged to $GH/calls.
# PRs live as files $GH/pr-<n> of key=value lines (head, base, state
# OPEN|MERGED, draft 1|0, oid, title; a later line wins), numbered by
# $GH/pr-count.
# - auth status: succeeds.
# - pr create [--draft] --base B --head H [--title T] [--body…]: a new PR,
#   prints https://gh.test/pr/<n>.
# - pr view <n|head> --json …: {"state":…,"isDraft":…,"number":n,
#   "mergeCommit":{"oid":…}} (mergeCommit null before a merge); no PR -> exit 1.
#   A $GH/pr-<n>.pending file is appended to the PR file after the view (a
#   GitHub read that lags the merge by one view).
# - pr ready <n>: draft=0. pr edit <n> [--title T] [--body-file F]: records
#   the title, and F's content in $GH/pr-<n>.body.
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
    shift 2; _d=0; _b=""; _h=""; _t=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --draft) _d=1 ;;
        --base) _b="$2"; shift ;;
        --head) _h="$2"; shift ;;
        --title) _t="$2"; shift ;;
        --body|--body-file) shift ;;
      esac
      shift
    done
    _n=$(( $(cat "$GH/pr-count" 2>/dev/null || echo 0) + 1 )); echo "$_n" > "$GH/pr-count"
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
        --body-file) cat "$2" > "$_f.body"; shift ;;
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
# moved away, so the runner's next fetch fails.
cat > "$FAKE/merge-stub" <<'STUB'
#!/bin/sh
echo "s merge $(date +%s)" >> "$CALLS/gate.iv"
k=$(( $(cat "$CALLS/merge-count" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$CALLS/merge-count"
out="$(printf '%s\n' ${MERGE_OUTCOMES:-ok} | sed -n "${k}p")"; [ -n "$out" ] || out=ok
f="$GH/pr-$1"; rc=0
case "$out" in
  ok)
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
esac
echo "e merge $(date +%s)" >> "$CALLS/gate.iv"
exit "$rc"
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
# integration/demo on origin for MODE integration; for MODE direct, an
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
  assert_contains "$R/report.md" "^Ending: partial: 0 landed, 2 stopped, 1 skipped$" "the report is written"
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
  test_lanes_docs_revision test_lanes_waiting_chain_starts_after_deps test_lanes_skip_on_stopped_dep \
  test_lanes_lane_kill9 test_lanes_end_sessions_spaced_path test_lanes_sigint test_lanes_runner_gone test_lanes_stop_file \
  test_lanes_land_clean_integration test_lanes_land_clean_direct test_lanes_land_conflict_one_repair \
  test_lanes_land_second_conflict_stops test_lanes_land_repair_no_progress test_lanes_direct_refused_then_repaired test_lanes_direct_merged_never_repairs \
  test_lanes_land_once_explicit_branch test_lanes_land_idempotent \
  test_lanes_land_crash_after_push test_lanes_land_lock_reclaim test_lanes_land_shipped_resume \
  test_lanes_gate_never_overlaps test_lanes_no_orphans
