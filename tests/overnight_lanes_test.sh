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
STATE_BIN="$BIN/studio-state"
ADOPT_BIN="$BIN/studio-adopt"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/overnight_lanes_test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# The runner is reached through a link under $TMP, so its argv (and its lanes',
# and a --detach child's) names $TMP: pgrep -f "$TMP" finds only this run's.
mkdir -p "$TMP/bin" && ln -s "$BIN/studio-overnight" "$TMP/bin/studio-overnight" && mk_msleep \
  || { echo "lanes: setup failed" >&2; exit 1; }
RUNNER="$TMP/bin/studio-overnight"
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
#   .peers (the peer-runs hook's output; only with STUDIO_UNIT_TAG set),
#   .env (OMEGA_AUTOPILOT, STUDIO_RUN, STUDIO_DOCS_REV, STUDIO_REPAIR,
#   STUDIO_GATE_HELD as KEY=value lines), .t0 and .t1 (epoch seconds).
# - Live count (#39): $CALLS/live/<pid> while a call runs; $CALLS/max holds
#   the most calls seen running at once.
# - Scenario: line m of $SCEN/<id> (unit prompts), $SCEN/<id>.land
#   (`--land`), $SCEN/<id>.sync (`--land` with STUDIO_REPAIR=sync:<ref>),
#   $SCEN/<id>.gate (`--gate-repair`), $SCEN/progress
#   (`--progress`) or $SCEN/final-repair
#   (`/omega:integration repair`). A missing file or line means `auto`.
# - A line is a `;`-separated list of actions, run in order. `auto` runs
#   last unless the line names a terminal action (stop, noop, hang, exit,
#   repair, fakerepair, gaterepair, syncrepair, progress); naming `auto`
#   itself changes nothing. Post actions (push_target, push_main, dirty,
#   localcommit, rmwt) run after auto or the terminal action, in order.
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
#   waitfor <path>  poll up to 60 s for <path> to exist and be non-empty
#                   (e.g. a peer run's landed.tsv); the unit then goes on
#   waitexist <path> as waitfor, but an empty file counts (a stop file, a
#                   release file). In waitfor, waitafter and waitexist paths
#                   @RUN@ stands for $STUDIO_RUN_DIR. A wait that reaches its
#                   ceiling (STUB_WAIT_TICKS, default 600 ticks of 0.1 s)
#                   appends its path to $CALLS/wait.timeout.
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
#   gatecmd         terminal: in the story worktree, runs `studio-setup gate`;
#                   a red one ledgers and commits `Stop: gate red — <its
#                   stderr line>` (execute §7's gate_command step)
#   Every auto (execute §0 and §6, D43): after the docs sync it runs the real
#   `studio-setup`, then `studio-adopt sync` when the feature ledger has an
#   `adopted` line; a failure of either ledgers and commits `Stop: …` and ends
#   the unit. A ledger with `check requested` and no `check done` is a check
#   unit: it ledgers `check done none`, commits and pushes. A task commit's
#   ledger line is `T<k> complete <a>..<b>` (full shas).
#   syncrepair      terminal (`--land`, STUDIO_REPAIR=sync:<ref>): in the
#                   story worktree, fetch, merge <ref> (a conflict resolved
#                   with --theirs), commit `fix(sync): resolve <ref>`, ledger
#                   `Synced: merged <ref>` (committed), push
#   push_target <f> post: commits <f> (content: the branch name) to
#                   origin/<Target> through a temp clone
#   push_main <f>   post: the same on origin/main
#   mark <path>     post: writes <path> (a flag another unit can waitfor)
#   waitafter <path> post: as waitfor, after auto (the unit's work is pushed)
#   dirty <f>       post: an untracked <f> in the story worktree
#   localcommit     post: an empty commit in the story worktree, not pushed
#   rmwt            post: removes the story worktree (the branch stays)
#   mergehook on|off  modifier: adds (on) or removes (off) a pre-merge-commit
#                   hook that exits 1, in the common git dir
#   probe           modifier: the story worktree's state now, as key=value
#                   lines in $CALLS/<n>.probe: head, subject, p2 (HEAD^2 or
#                   empty), remote (origin's <Branch>, by ls-remote), dirty
#                   (porcelain line count), mergehead (1 when MERGE_HEAD)
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
  *--land*) case "${STUDIO_REPAIR:-}" in sync:*) kind="$id.sync" ;; *) kind="$id.land" ;; esac ;;
  *--progress*) kind=progress ;;
  *'/omega:integration repair'*) kind=final-repair ;;
  *) kind="$id" ;;
esac
while ! mkdir "$CALLS/n.lock" 2>/dev/null; do sleep 0.1; done
n=$(( $(cat "$CALLS/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS/count"
m=$(( $(cat "$CALLS/m-$kind" 2>/dev/null || echo 0) + 1 )); echo "$m" > "$CALLS/m-$kind"
rmdir "$CALLS/n.lock"
# #39: live-session counter. live/<pid> while this session runs; max holds the
# largest count seen (updated under n.lock).
mkdir -p "$CALLS/live"; : > "$CALLS/live/$$"
trap 'rm -f "$CALLS/live/$$"' EXIT; trap 'rm -f "$CALLS/live/$$"; exit 143' TERM
while ! mkdir "$CALLS/n.lock" 2>/dev/null; do sleep 0.1; done
_lv="$(ls "$CALLS/live" | grep -c .)"; _mx="$(cat "$CALLS/max" 2>/dev/null || echo 0)"
[ "$_lv" -le "$_mx" ] || echo "$_lv" > "$CALLS/max"
rmdir "$CALLS/n.lock"
printf '%s\n' "$(date +%s)" > "$CALLS/$n.t0w"      # wall start, for the session_minutes test
date +%s > "$CALLS/$n.t0"
echo "$$" > "$CALLS/$n.pid"
for a in "$@"; do printf '%s\n' "$a"; done > "$CALLS/$n.argv"
printf '%s\n' "$id" > "$CALLS/$n.story"
printf '%s\n' "$prompt" > "$CALLS/$n.prompt"
pwd -P > "$CALLS/$n.pwd"
printf 'OMEGA_AUTOPILOT=%s\nSTUDIO_RUN=%s\nSTUDIO_DOCS_REV=%s\nSTUDIO_REPAIR=%s\nSTUDIO_GATE_HELD=%s\n' \
  "${OMEGA_AUTOPILOT:-}" "${STUDIO_RUN:-}" "${STUDIO_DOCS_REV:-}" "${STUDIO_REPAIR:-}" "${STUDIO_GATE_HELD:-}" > "$CALLS/$n.env"
env > "$CALLS/$n.fullenv"
# #39: a unit session starts under the peers hook, as SessionStart runs it.
[ -z "${STUDIO_UNIT_TAG:-}" ] || sh "$STUB_PLUGIN/hooks/peer-runs.sh" < /dev/null > "$CALLS/$n.peers" 2>/dev/null
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
  if ! _se="$(sh "$(dirname "$STUB_STATE_BIN")/studio-setup" 2>&1 >/dev/null)"; then
    st ledger "Stop: $_se"; commit_ledger setup-stop; return 0
  fi
  if grep -q '^- [0-9-]* adopted ' ".studio/ledger/$id.md" 2>/dev/null; then
    if ! _sy="$(sh "$(dirname "$STUB_STATE_BIN")/studio-adopt" sync "$id" 2>&1 >/dev/null)"; then
      st ledger "Stop: adopt sync — $(printf '%s\n' "$_sy" | tail -n 1)"; commit_ledger sync-stop; return 0
    fi
  fi
  if grep -q '^- [0-9-]* check requested$' ".studio/ledger/$id.md" 2>/dev/null \
     && ! grep -q '^- [0-9-]* check done' ".studio/ledger/$id.md"; then
    st ledger "check done none"; commit_ledger check; sg push -q origin "$BRANCH"; return 0
  fi
  task="$(st get task)"; k="${task%/*}"; N="${task#*/}"
  case "$k" in ''|-|*[!0-9]*) k=0 ;; esac
  case "$N" in ''|-|*[!0-9]*) N=1 ;; esac
  frd="$(grep -c 'final review done$' ".studio/ledger/$id.md" 2>/dev/null)"
  if [ "$k" -lt "$N" ]; then
    k=$((k + 1)); f="${conflict:-$id-T$k.txt}"
    _a="$(git rev-parse HEAD)"
    printf '%s\n' "$id" > "$f"; git add "$f"; git commit -qm "feat($id): T$k"
    st ledger "T$k complete $_a..$(git rev-parse HEAD)"; commit_ledger "T$k complete"
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

# push_to BRANCH FILE — commit FILE (content: BRANCH) to origin's BRANCH via a temp clone.
push_to() {
  _pd="$(mktemp -d "${TMPDIR:-/tmp}/lanes-stub.XXXXXX")"
  ( git clone -q "$(git remote get-url origin)" "$_pd/c" && cd "$_pd/c" && git checkout -q "$1" \
    && printf '%s\n' "$1" > "$2" && git add "$2" && git commit -qm "$1 moves: $2" && git push -q origin "$1" ) >&2
  rm -rf "$_pd"
}
cost=1; code=0; terminal=0; conflict=""; post=""
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
    "waitfor "*)      _wf="$(printf '%s' "${act#waitfor }" | sed "s|@RUN@|${STUDIO_RUN_DIR:-@RUN@}|g")"; _wi=0
                      while [ ! -s "$_wf" ] && [ "$_wi" -lt "${STUB_WAIT_TICKS:-600}" ]; do sleep 0.1; _wi=$((_wi + 1)); done
                      [ -s "$_wf" ] || echo "$_wf" >> "$CALLS/wait.timeout" ;;
    "waitexist "*)    _wf="$(printf '%s' "${act#waitexist }" | sed "s|@RUN@|${STUDIO_RUN_DIR:-@RUN@}|g")"; _wi=0
                      while [ ! -e "$_wf" ] && [ "$_wi" -lt "${STUB_WAIT_TICKS:-600}" ]; do sleep 0.1; _wi=$((_wi + 1)); done
                      [ -e "$_wf" ] || echo "$_wf" >> "$CALLS/wait.timeout" ;;
    "gate "*)         s="${act#gate }"
                      sh "$(dirname "$STUB_STATE_BIN")/studio-gate" studio-test -- sh -c \
                        "echo s $id \$(date +%s) >> '$CALLS/gate.iv'; sleep $s; echo e $id \$(date +%s) >> '$CALLS/gate.iv'" ;;
    "bggate "*)       s="${act#bggate }"
                      # What the 2026-10-02 finish did: a gate started in the
                      # background, in its own session (as the Bash tool's
                      # shells are), left running when the session ends.
                      perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' sh "$(dirname "$STUB_STATE_BIN")/studio-gate" studio-test -- \
                        sh -c "echo \$\$ > '$CALLS/bggate.pid'; sleep $s" < /dev/null > /dev/null 2>&1 &
                      _bi=0; while [ ! -s "$CALLS/bggate.pid" ] && [ "$_bi" -lt 600 ]; do sleep 0.1; _bi=$((_bi + 1)); done ;;
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
    syncrepair)       terminal=1; w="$(story_wt)"; _ref="${STUDIO_REPAIR#sync:}"
                      ( cd "$w" && sg fetch -q origin && { git merge -q --no-edit "$_ref" >/dev/null 2>&1 || {
                          git checkout -q --theirs -- . && git add -A && git -c core.editor=true commit -q --no-edit; }; } \
                        && git commit -q --allow-empty -m "fix(sync): resolve $_ref" \
                        && st ledger "Synced: merged $_ref" \
                        && git add -A && git commit -q -m "docs(ledger): synced" && sg push -q origin HEAD ) >> "$CALLS/$n.log" 2>&1 ;;
    "push_target "*|"push_main "*|"dirty "*|"mark "*|"waitafter "*|localcommit|rmwt) post="$post${post:+;}$act" ;;
    "mergehook "*)    _hd="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/hooks"; mkdir -p "$_hd"
                      if [ "${act#mergehook }" = on ]; then printf '#!/bin/sh\nexit 1\n' > "$_hd/pre-merge-commit"; chmod +x "$_hd/pre-merge-commit"
                      else rm -f "$_hd/pre-merge-commit"; fi ;;
    probe)            w="$(story_wt)"
                      ( cd "$w" && printf 'head=%s\nsubject=%s\np2=%s\nremote=%s\ndirty=%s\nmergehead=%s\n' \
                          "$(git rev-parse HEAD)" "$(git log -1 --format=%s)" "$(git rev-parse -q --verify 'HEAD^2' 2>/dev/null)" \
                          "$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)" "$(git status --porcelain | grep -c .)" \
                          "$(if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then echo 1; else echo 0; fi)" ) > "$CALLS/$n.probe" ;;
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
    gatecmd)          terminal=1; w="$(story_wt)"
                      ( cd "$w" && { _g="$(sh "$(dirname "$STUB_STATE_BIN")/studio-setup" gate 2>&1 >/dev/null)" \
                        || { st ledger "Stop: gate red — $_g"; commit_ledger gate-red; }; } ) ;;
    "ruling "*)       w="$(story_wt)"
                      ( cd "$w" && st ledger "${act#ruling }" && commit_ledger ruling ) ;;
    inbox)            printf '{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}' \
                        | sh "$STUB_PLUGIN/hooks/operator-inbox.sh" > "$CALLS/$n.inbox" ;;
    "say "*)          sh "$STUB_RUNNER" say "$id" -- "${act#say }" > /dev/null 2>&1 ;;
    *)                echo "stub: unknown action '$act'" >&2 ;;
  esac
done
[ "$terminal" = 1 ] || ( auto ) >&2
IFS=';'; set -f; set -- $post; set +f; IFS="$old_ifs"
for act in "$@"; do
  case "$act" in
    "push_target "*)  push_to "$TARGET" "${act#push_target }" ;;
    "push_main "*)    push_to main "${act#push_main }" ;;
    "dirty "*)        w="$(story_wt)"; : > "$w/${act#dirty }" ;;
    "mark "*)         echo 1 > "${act#mark }" ;;
    "waitafter "*)    _wf="$(printf '%s' "${act#waitafter }" | sed "s|@RUN@|${STUDIO_RUN_DIR:-@RUN@}|g")"; _wi=0
                      while [ ! -s "$_wf" ] && [ "$_wi" -lt "${STUB_WAIT_TICKS:-600}" ]; do sleep 0.1; _wi=$((_wi + 1)); done
                      [ -s "$_wf" ] || echo "$_wf" >> "$CALLS/wait.timeout" ;;
    localcommit)      w="$(story_wt)"; git -C "$w" commit -q --allow-empty -m "local: not pushed" ;;
    rmwt)             w="$(story_wt)"; git worktree remove --force "$w" ;;
  esac
done
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
    url="$(git remote get-url origin)"; d="$(mktemp -d "${TMPDIR:-/tmp}/lanes-stub.XXXXXX")"
    ( cd "$d" && git clone -q "$url" c && cd c && git checkout -q "$base" \
      && git merge -q --no-ff --no-edit "origin/$head" && git push -q origin "$base" \
      && printf 'state=MERGED\noid=%s\n' "$(git rev-parse HEAD)" >> "$f" \
      && { [ "${MERGE_DELETES_BRANCH:-0}" != 1 ] || git push -q origin --delete "$head"; } ) || rc=1
    rm -rf "$d" ;;
  ghonly|lagoid|nofetch)
    head="$(sed -n 's/^head=//p' "$f" | tail -n 1)"; base="$(sed -n 's/^base=//p' "$f" | tail -n 1)"
    url="$(git remote get-url origin)"; d="$(mktemp -d "${TMPDIR:-/tmp}/lanes-stub.XXXXXX")"
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
# LANES_TASKS=2 gives every plan a Task 2 and sets task 0/2 (default: one task).
# LANES_MAIN_PRE=<dir> commits <dir>'s files on main before run/demo is cut, so the run branch inherits them (#56).
# Exports P, MFP, CALLS, GH,
# TMP_WT and SCEN (an empty scenario dir: every unit is `auto`); unsets LANES_*.
# LANES_FIXTURE_TEMPLATES (suite-local): 1 (default) builds each key once under
# $TMP/tpl/l-<key>/ and copies it; 0 builds fresh every call.
LANES_FIXTURE_TEMPLATES="${LANES_FIXTURE_TEMPLATES:-1}"
lf_failed() { TESTS_RUN=$((TESTS_RUN + 1)); _fail "lanes_fixture $_lf_name: setup failed"; }
lanes_fixture() {
  _lf_name="$1"; _lf_mode="$2"; shift 2
  P="$TMP/$_lf_name"; CALLS="$TMP/calls-$_lf_name"; GH="$TMP/gh-$_lf_name"; TMP_WT="$TMP/wts-$_lf_name"
  SCEN="$TMP/scen-$_lf_name"
  MFP=docs/runs/demo.md
  export P MFP CALLS GH TMP_WT SCEN
  rm -rf "$P" "$CALLS" "$GH" "$TMP_WT" "$SCEN" "$TMP/$_lf_name.git"
  mkdir -p "$CALLS" "$GH" "$TMP_WT" "$SCEN"
  if [ "$LANES_FIXTURE_TEMPLATES" = 0 ]; then
    lf_build "$P" "$TMP/$_lf_name.git" "$_lf_mode" "$@" || lf_failed
  else
    # The key is the whole tuple the build reads (mode, rows, every LANES_* input, the stub path).
    # The date is in the key: ledger lines carry the build day, so a run crossing midnight rebuilds.
    _lf_t="$TMP/tpl/l-$(printf '%s|' "$(date +%Y-%m-%d)" "$_lf_mode" "$@" "${LANES_CONFIG:-}" "${LANES_CELLS:-}" "${LANES_PROGRESS:-}" \
      "${LANES_MAIN_MOVES:-}" "${LANES_TASKS:-}" "${LANES_MAIN_PRE:-}" "$(lf_pre_sum)" "$FAKE" | cksum | tr ' ' -)"
    if [ ! -f "$_lf_t/ok" ]; then
      if lf_build "$_lf_t/p" "$_lf_t/p.git" "$_lf_mode" "$@"; then : > "$_lf_t/ok"; else rm -rf "$_lf_t"; fi
    fi
    if [ -f "$_lf_t/ok" ] && cp -Rp "$_lf_t/p" "$P" && cp -Rp "$_lf_t/p.git" "$TMP/$_lf_name.git" \
         && git -C "$P" remote set-url origin "$TMP/$_lf_name.git"; then :; else lf_failed; fi
  fi
  unset LANES_CONFIG LANES_CELLS LANES_PROGRESS LANES_MAIN_MOVES LANES_TASKS LANES_MAIN_PRE
}
# lf_pre_sum — LANES_MAIN_PRE's files and their contents, for the template key (empty when unset).
lf_pre_sum() {
  [ -n "${LANES_MAIN_PRE:-}" ] || return 0
  ( cd "$LANES_MAIN_PRE" && find . -type f -exec cksum {} + | sort )
}
# lf_build DIR ORIGIN MODE ROW… — the fixture body at DIR with its bare origin at ORIGIN;
# status non-zero on any failed step. Each step ends in `|| exit 1`, not set -e: lf_build runs
# as an if/|| condition, where errexit is off even inside the subshell.
lf_build() {
  _lb_dir="$1"; _lb_origin="$2"; _lf_mode="$3"; shift 3
  rm -rf "$_lb_dir" "$_lb_origin"; mkdir -p "$_lb_dir" && git init -q --bare "$_lb_origin" || return 1
  _lf_cfg="${LANES_CONFIG:-}"; [ -n "$_lf_cfg" ] || _lf_cfg='{}'
  _lf_cells="${LANES_CELLS:-}"; _lf_progress="${LANES_PROGRESS:-}"; _lf_moves="${LANES_MAIN_MOVES:-}"
  _lf_tasks="${LANES_TASKS:-1}"; _lf_pre="${LANES_MAIN_PRE:-}"
  _lf_spec=docs/game-dev/specs/2026-10-01-demo.md
  ( cd "$_lb_dir" || exit 1
    git init -q -b main || exit 1
    if [ "$_lf_progress" = 1 ]; then
      mkdir -p docs/game-dev && printf '# Progress\n' > docs/game-dev/PROGRESS.md \
        && git add docs/game-dev/PROGRESS.md && git commit -q -m init || exit 1
    else
      git commit -q --allow-empty -m init || exit 1
    fi
    if [ -n "$_lf_pre" ]; then cp -R "$_lf_pre/." . && git add -A && git commit -q -m "main: files before the run" || exit 1; fi
    git remote add origin "$_lb_origin" && git push -q origin main && git remote set-head origin main || exit 1
    git checkout -q -b run/demo || exit 1
    mkdir -p docs/game-dev/specs docs/game-dev/plans docs/runs || exit 1
    { printf '# Spec: demo\n\n## Acceptance criteria\n\n1. one\n2. two\n3. three\n\n## Stories\n\n'
      printf '| Story | Summary |\n|-------|---------|\n'
      for _r in "$@"; do printf '| %s | story %s |\n' "${_r%%:*}" "${_r%%:*}"; done
    } > "$_lf_spec" || exit 1
    sh "$STATE_BIN" init >/dev/null || exit 1
    printf '%s\n' "$_lf_cfg" > .studio/config.json || exit 1
    if [ "$_lf_mode" = direct ]; then
      mkdir -p scripts && printf '#!/bin/sh\nexec sh %s "$@"\n' "'$FAKE/merge-stub'" > scripts/merge.sh && chmod +x scripts/merge.sh || exit 1
    fi
    for _r in "$@"; do
      _id="${_r%%:*}"; _plan="docs/game-dev/plans/2026-10-01-$_id.md"
      printf '# Plan: %s\n\nStory: %s\n\n## Global Constraints\n\n- none\n\n## Decisions\n\n- none\n\n### Task 1: t\n\nSpec: %s:L1-2\nReview: final\n' \
        "$_id" "$_id" "$_lf_spec" > "$_plan" || exit 1
      [ "$_lf_tasks" != 2 ] || printf '\n### Task 2: u\n\nSpec: %s:L1-2\nReview: final\n' "$_lf_spec" >> "$_plan" || exit 1
      STUDIO_STORY="$_id"; export STUDIO_STORY
      sh "$STATE_BIN" init >/dev/null || exit 1
      sh "$STATE_BIN" set spec "$_lf_spec" || exit 1
      sh "$STATE_BIN" set plan "$_plan" || exit 1
      sh "$STATE_BIN" ledger "spec approved $_lf_spec" || exit 1
      sh "$STATE_BIN" ledger "plan approved $_plan" || exit 1
      sh "$STATE_BIN" ledger "Decisions swept $_id" || exit 1
      sh "$STATE_BIN" set stage plan || exit 1
      sh "$STATE_BIN" set task "0/$_lf_tasks" || exit 1
      unset STUDIO_STORY
    done
    git add -A && git commit -q -m docs && git push -q origin run/demo || exit 1
    _docs="$(git rev-parse HEAD)" || exit 1
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
    } > "$MFP" || exit 1
    git add -A && git commit -q -m manifest && git push -q origin run/demo || exit 1
    printf '.studio/run\n' >> "$(git rev-parse --git-common-dir)/info/exclude" && printf '%s\n' "$MFP" > .studio/run || exit 1
    [ "$_lf_mode" != integration ] || git push -q origin origin/main:refs/heads/integration/demo || exit 1
    if [ -n "$_lf_moves" ]; then
      git checkout -q main && printf 'main\n' > "$_lf_moves" && git add "$_lf_moves" \
        && git commit -q -m "main moves" && git push -q origin main && git checkout -q run/demo || exit 1
    fi
  ) >/dev/null 2>&1
}
OLD_PLAN=docs/game-dev/plans/2026-10-02-mob-composer.md
# lanes_pre_stale DIR — KAN-1499's shipped story S1 as phoenix's main held it
# (#56): its ledger (plan approved OLD_PLAN, T1-T2 complete, shipped) and OLD_PLAN.
lanes_pre_stale() {
  mkdir -p "$1/.studio/ledger" "$1/docs/game-dev/plans"
  printf -- '- 2026-10-02 plan approved %s\n- 2026-10-02 T1 complete\n- 2026-10-02 T2 complete\n- 2026-10-03 shipped KAN-1499-mob-composer\n' \
    "$OLD_PLAN" > "$1/.studio/ledger/S1.md"
  printf '# Plan: mob composer\n\nStory: S1\n\n### Task 1: t\n' > "$1/$OLD_PLAN"
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
# lanes_add_run SLUG MODE ROW… — a second run in the current fixture $P
# (after lanes_fixture): run worktree RW=$P/.claude/worktrees/run-SLUG on
# run/SLUG from origin/main (studio-state init --local), .studio/config.json
# from $LANES_CONFIG (default {}; MODE direct adds scripts/merge.sh and
# merge_command), its own spec, one plan per story, story state at <root>
# (stage plan, task 0/1, approved and swept), manifest RMF=docs/runs/SLUG.md,
# all committed and pushed; integration/SLUG on origin for MODE integration.
# Story ids must not clash with $P's run (A, B, …): use S1, S2, ….
lanes_add_run() {
  _ar_s="$1"; _ar_m="$2"; shift 2
  RW="$P/.claude/worktrees/run-$_ar_s"; RMF="docs/runs/$_ar_s.md"; export RW RMF
  _ar_cfg="${LANES_CONFIG:-}"; [ -n "$_ar_cfg" ] || _ar_cfg='{}'
  _ar_spec="docs/game-dev/specs/2026-10-01-$_ar_s.md"
  ( set -e
    cd "$P"; git fetch -q origin
    grep -qxF .claude/worktrees/ "$(git rev-parse --git-common-dir)/info/exclude" 2>/dev/null \
      || printf '.claude/worktrees/\n' >> "$(git rev-parse --git-common-dir)/info/exclude"
    git worktree add -q --no-track -b "run/$_ar_s" "$RW" origin/main
    cd "$RW"; sh "$STATE_BIN" init --local >/dev/null
    mkdir -p docs/game-dev/specs docs/game-dev/plans docs/runs .studio
    if [ "$_ar_m" = direct ]; then
      mkdir -p scripts && printf '#!/bin/sh\nexec sh %s "$@"\n' "'$FAKE/merge-stub'" > scripts/merge.sh && chmod +x scripts/merge.sh
      _ar_cfg="$(printf '%s' "$_ar_cfg" | sed 's/^{ *}$/{"overnight": {}}/; s/"overnight": {/"overnight": {"merge_command": "scripts\/merge.sh <pr>", /; s/, }/}/')"
    fi
    printf '%s\n' "$_ar_cfg" > .studio/config.json
    { printf '# Spec: %s\n\n## Stories\n\n| Story | Summary |\n|-------|---------|\n' "$_ar_s"
      for _r in "$@"; do printf '| %s | story %s |\n' "${_r%%:*}" "${_r%%:*}"; done; } > "$_ar_spec"
    for _r in "$@"; do
      _id="${_r%%:*}"; _plan="docs/game-dev/plans/2026-10-01-$_id.md"
      printf '# Plan: %s\n\nStory: %s\n\n## Decisions\n\n- none\n\n### Task 1: t\n\nSpec: %s:L1-2\nFiles: `%s-T1.txt`\n\n### Task 2: u\n\nSpec: %s:L1-2\nFiles: `%s-T2.txt`\n' \
        "$_id" "$_id" "$_ar_spec" "$_id" "$_ar_spec" "$_id" > "$_plan"
      STUDIO_STORY="$_id"; export STUDIO_STORY
      sh "$STATE_BIN" init >/dev/null; sh "$STATE_BIN" set spec "$_ar_spec"; sh "$STATE_BIN" set plan "$_plan"
      sh "$STATE_BIN" ledger "spec approved $_ar_spec"; sh "$STATE_BIN" ledger "plan approved $_plan"
      sh "$STATE_BIN" ledger "Decisions swept $_id"; sh "$STATE_BIN" set stage plan; sh "$STATE_BIN" set task 0/2
      unset STUDIO_STORY
    done
    git add -A && git commit -q -m docs && git push -q origin "run/$_ar_s"
    _docs="$(git rev-parse HEAD)"
    if [ "$_ar_m" = integration ]; then _t="integration/$_ar_s"; else _t=main; fi
    { printf '# Run: %s\n\nMode: %s\nTarget: %s\nDocs: %s\nGoal: the %s goal\n\n' "$_ar_s" "$_ar_m" "$_t" "$_docs" "$_ar_s"
      printf '| Story | Branch | Ticket | Spec | Plan | Depends on |\n|-------|--------|--------|------|------|------------|\n'
      for _r in "$@"; do _id="${_r%%:*}"
        printf '| %s | %s-b | %s | %s | docs/game-dev/plans/2026-10-01-%s.md | %s |\n' "$_id" "$_id" "$_id" "$_ar_spec" "$_id" "$(printf '%s' "${_r#*:}" | sed 's/,/, /g')"
      done; } > "$RMF"
    printf '%s\n' "$RMF" > .studio/run
    git add -A && git commit -q -m manifest && git push -q origin "run/$_ar_s"
    [ "$_ar_m" != integration ] || git push -q origin "origin/main:refs/heads/integration/$_ar_s"
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "lanes_add_run $_ar_s: setup failed"; }
  unset LANES_CONFIG
}
# run_lanes_in DIR ARGS — run_lanes from DIR (same LS_* results and watchdog).
run_lanes_in() { _rli="$P"; P="$1"; shift; run_lanes "$@"; P="$_rli"; }
# bg_lanes NAME DIR ARGS — `studio-overnight ARGS` in DIR in the background:
# $TMP/bg-NAME.{pid,out,err}. bg_wait NAME — wait up to 120 s; BG_STATUS.
bg_lanes() { _bn="$1"; _bd="$2"; shift 2
  ( cd "$_bd" && exec sh "$RUNNER" "$@" ) > "$TMP/bg-$_bn.out" 2> "$TMP/bg-$_bn.err" < /dev/null &
  echo "$!" > "$TMP/bg-$_bn.pid"; }
bg_wait() { _bp="$(cat "$TMP/bg-$1.pid")"; _bi=0
  while kill -0 "$_bp" 2>/dev/null && [ "$_bi" -lt 1200 ]; do sleep 0.1; _bi=$((_bi + 1)); done
  if kill -0 "$_bp" 2>/dev/null; then kill -TERM "$_bp"; TESTS_RUN=$((TESTS_RUN + 1)); _fail "bg run $1 ran past 120 s"; fi
  BG_STATUS=0; wait "$_bp" 2>/dev/null || BG_STATUS=$?; }

test_lanes_chain_rule() {
  lanes_fixture chains integration A:- B:- C:A D:A E:C,B F:E
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "dry run exits 0 $(cat "$LS_ERR")"
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
  assert_missing "$P/.studio/runs/demo/lock" "nor a per-run lock"
  assert_eq "" "$(ls -d "$P"/.studio/tmp.* 2>/dev/null)" "dry run leaves no temp dir"
}

# A story Branch that is the default branch (direct mode's Target too): its
# story worktree would be the main checkout, a sync would merge into it and
# the runner would push to origin/<default> (#39 final review, T13-1).
test_lanes_branch_default_or_target_refused() {
  for _bm in integration direct; do
    lanes_fixture "bdt-$_bm" "$_bm" A:-
    sed -i.bak 's/^| A | A-b |/| A | main |/' "$P/$MFP"; rm -f "$P/$MFP.bak"
    run_lanes start --dry-run "$MFP"
    assert_eq 2 "$LS_STATUS" "$_bm: a story on the default branch refuses"
    assert_contains "$LS_ERR" "manifest: A: branch main is the default branch or the run's Target — pick another" "$_bm: the refusal names the story and branch"
  done
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
  assert_contains "$LS_OUT" "^next: /game-dev:brainstorm demo/C$" "brainstorm comes before plan"
  printf '%s\n' "$MFP" > "$P/.studio/run"
  run_lanes next
  assert_contains "$LS_OUT" "^next: /game-dev:brainstorm demo/C$" "no argument reads .studio/run"
  rm "$P/.studio/run"; run_lanes next
  assert_eq 2 "$LS_STATUS" "no pointer and no argument exits 2"
  assert_contains "$LS_ERR" "no run manifest (.studio/run)" "and says why"
}
test_lanes_next_all_planned_and_ambiguous() {
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nxt2 integration A:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-A.md\n- 2026-10-01 Decisions swept A\n' > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^next: /omega:autopilot demo$" "every row planned"
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
  assert_contains "$LS_OUT" "^next: /game-dev:plan demo/B$" "plan comes when nothing needs brainstorming"
  _before="$(cd "$P" && git status --porcelain | wc -l | tr -d ' ')"
  run_lanes next "$MFP"
  assert_eq "$_before" "$(cd "$P" && git status --porcelain | wc -l | tr -d ' ')" "next writes nothing"
}

# #56 R4: next matches a ledger line whole, after `- <date> `.
test_lanes_next_whole_line_ledger() {
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nwl integration S1:-
  _wl_s=docs/game-dev/specs/2026-10-01-demo.md; _wl_p=docs/game-dev/plans/2026-10-01-S1.md
  printf -- '- 2026-10-01 spec approved %s\n- 2026-10-01 plan approved %s\n- 2026-10-01 Decisions swept S10\n' "$_wl_s" "$_wl_p" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next exits 0"
  assert_contains "$LS_OUT" "^S1  plan  spec=$_wl_s  plan=$_wl_p\$" "Decisions swept S10 does not sweep S1"
  printf -- '- 2026-10-01 spec approved %s\n- 2026-10-01 plan approved %s.old\n- 2026-10-01 Decisions swept S1\n' "$_wl_s" "$_wl_p" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^S1  plan  " "plan approved <plan>.old does not approve <plan>"
  printf -- '- 2026-10-01 spec approved %s.old\n' "$_wl_s" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^S1  brainstorm  " "spec approved <spec>.old does not approve <spec>"
  printf -- '- 2026-10-01 spec approved %s\n- 2026-10-01 plan approved %s\n- 2026-10-01 Decisions swept S1\n' "$_wl_s" "$_wl_p" > "$P/.studio/ledger/demo.md"
  run_lanes next "$MFP"
  assert_contains "$LS_OUT" "^S1  planned  " "the exact lines still make it planned"
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
  # B's cost waits until A's T1 row is in a lane's units.tsv; A's final review
  # waits until B's record reads stopped.
  printf 'cost 10\nwaitexist %s\n' "$SCEN/release-budA" > "$SCEN/A"
  printf 'waitexist %s; cost 10\n' "$SCEN/release-budB" > "$SCEN/B"
  release_when budB '[ -n "$(cat "$(last_lanes_dir)"/lanes/*/units.tsv 2>/dev/null)" ]'
  release_when budA '[ "$(rec B)" = "stopped stop: run budget" ]'
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: run budget$" "B stops on the run-wide spend"
  assert_eq 1 "$(story_calls B | wc -l | tr -d ' ')" "B launched once"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: run budget$" "A stops once the sum passes too"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  rw_kill
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
  rm -f "$TMP/dr-mid"
  printf 'waitexist %s\n' "$TMP/dr-mid" > "$SCEN/A"
  # Once the run holds its lock, the commit moves the checkout; A then goes on.
  ( wait_for "[ -e '$P/.studio/runs/demo/lock' ]" 60
    cd "$P" && printf 'CHANGED\n' >> docs/game-dev/plans/2026-10-01-B.md && git commit -qam mid-run
    : > "$TMP/dr-mid" ) >/dev/null 2>&1 &
  run_lanes start "$MFP"; wait
  assert_eq 0 "$LS_STATUS" "both land"
  b_wt="$(git -C "$P" worktree list --porcelain | sed -n 's/^worktree //p' | grep '/B-b$')"
  [ -n "$b_wt" ] || b_wt="$TMP/no-B-b-worktree"
  assert_not_contains "$b_wt/docs/game-dev/plans/2026-10-01-B.md" "CHANGED" "a later story reads docs from the Docs revision only"
  assert_not_contains "$b_wt/docs/game-dev/plans/2026-10-01-B.md" "STALE" "an existing branch's plan is synced from the Docs revision"
  assert_contains "$b_wt/.studio/ledger/B.md" "Ruling: kept on the branch" "an existing branch's ledger is never overwritten"
  assert_eq 1 "$(git -C "$P" log --format=%s refs/remotes/origin/B-b 2>/dev/null | grep -c '^docs(B): plan at run docs ')" "the sync commits once"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
# ---- T9: waiting chains, skips, crashed lanes and stops ----

# wait_for COND SECS — eval COND every 0.2 s until it holds, up to SECS.
wait_for() {
  _wf_i=0
  while ! eval "$1" && [ "$_wf_i" -lt $(( $2 * 5 )) ]; do sleep 0.2; _wf_i=$((_wf_i + 1)); done
}
# release_when TAG COND — in the background: once COND holds (60 s ceiling),
# create $SCEN/release-TAG, which a stub `waitexist` is holding on. A COND that
# never holds leaves the file out, so the stub's wait hits its ceiling and
# writes $CALLS/wait.timeout, which the test asserts missing. The watcher's pid is
# recorded; a test that calls release_when ends with rw_kill, and before_each runs it
# too, so a watcher never outlives its test.
release_when() {
  ( wait_for "$2" 60; if eval "$2"; then : > "$SCEN/release-$1"; fi ) > /dev/null 2>&1 &
  printf '%s\n' "$!" >> "$TMP/rw.pids"
}
rw_kill() {
  [ -f "$TMP/rw.pids" ] || return 0
  # Signal a pid only while it is still our watcher: a subshell of this suite (its args
  # are the suite's own, which name $0), never a pid the OS has since recycled.
  while read -r _rw_p; do
    case "$(ps -o args= -p "$_rw_p" 2>/dev/null)" in
      *"$0"*) kill "$_rw_p" 2>/dev/null ;;
    esac
  done < "$TMP/rw.pids"
  rm -f "$TMP/rw.pids"
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
  while pid_alive "$1" && [ "$_wp_i" -lt $(( $2 * 5 )) ]; do sleep 0.2; _wp_i=$((_wp_i + 1)); done
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
    ( own_group "$TMP/bin/msleep" 301 ) & _c1=$!; ( own_group "$TMP/bin/msleep" 302 ) & _c2=$!
    "$TMP/bin/msleep" 303 & _w1=$!
    printf '%s\n' "$_c1" > "$RUN_DIR/lanes/1/cpid"; printf '%s\n' "$_w1" > "$RUN_DIR/lanes/1/wpid"
    printf '%s\n' "$_c2" > "$RUN_DIR/lanes/2/cpid"
    lanes_end_sessions 1
    wait_for '! pid_live "$_c1" && ! pid_live "$_w1"' 1
    pid_live "$_c1" && echo "c1 alive"; pid_live "$_w1" && echo "w1 alive"
    pid_live "$_c2" || echo "c2 dead early"
    [ ! -f "$RUN_DIR/lanes/1/cpid" ] || echo "cpid 1 left"; [ ! -f "$RUN_DIR/lanes/1/wpid" ] || echo "wpid 1 left"
    lanes_end_sessions
    wait_for '! pid_live "$_c2"' 1
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
  # own_group: a group of its own with SIGINT not ignored (as a terminal's Ctrl-C reaches it)
  ( cd "$P" && own_group sh "$RUNNER" start "$MFP" ) > "$TMP/si.out" 2>&1 & RPID=$!
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
  printf 'waitexist %s\n' "$SCEN/release-gone" > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  R="$(last_lanes_dir)"; lane1="$(cat "$R"/claims/1/pid 2>/dev/null)"
  kill -9 "$RPID"; wait "$RPID" 2>/dev/null
  : > "$SCEN/release-gone"
  wait_for "! kill -0 ${lane1:-0} 2>/dev/null" 20
  TESTS_RUN=$((TESTS_RUN + 1))
  if kill -0 "${lane1:-0}" 2>/dev/null; then
    pkill -P "$lane1"; kill -9 "$lane1"; _fail "the lane exits once the runner is gone"
  else _pass "the lane exits once the runner is gone"; fi
  assert_eq 1 "$(calls)" "a lane launches nothing once the runner pid is gone"
  assert_contains "$R/stories/A" "^stopped stop: runner gone$" "the story names the runner's absence, not a user stop"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_stop_file() {
  lanes_fixture stopf integration A:- B:A C:A
  printf 'waitexist %s\n' "$P/.studio/runs/demo/stop" > "$SCEN/A"
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
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nwaitfor %s\n' "$P/.studio/runs/demo/landed.tsv" > "$SCEN/B"
  printf 'fakerepair\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_eq 1 "$(land_calls)" "one repair, no second"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped landing failed after repair (conflict)$" "a second conflict stops the story"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: partial: 1 landed, 1 stopped, 0 skipped$" "the run is partial"
  assert_eq "" "$(ls -d "$(last_lanes_dir)/land.lock" 2>/dev/null)" "the land lock is released"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_land_repair_no_progress() {
  lanes_fixture landnp integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nwaitfor %s\n' "$P/.studio/runs/demo/landed.tsv" > "$SCEN/B"
  printf 'noop\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped repair made no progress$" "a repair with no Repair: line stops"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  lanes_fixture landst integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nwaitfor %s\n' "$P/.studio/runs/demo/landed.tsv" > "$SCEN/B"
  printf 'stop cannot resolve\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: cannot resolve$" "a repair's Stop: line stops with its reason"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
  next_second                       # a new run dir name
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
  printf 'auto\nauto\nwaitexist %s\n' "$SCEN/release-landk" > "$SCEN/B"
  # B finishes once A's lane is dead and the land lock it held is left.
  release_when landk '_p="$(cat "$(last_lanes_dir)/claims/1/pid" 2>/dev/null)"; [ -n "$_p" ] && ! pid_alive "$_p" && [ -e "$(last_lanes_dir)/land.lock" ]'
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
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  rw_kill
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
  rm -rf "$P/.studio/runs/demo"; next_second
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
    printf 'waitexist %s; %s\n' "$P/.studio/runs/demo/stop" "$act" > "$SCEN/A.gate"
    ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
    wait_for "[ -f '$CALLS/m-A.gate' ]" 60
    ( cd "$P" && sh "$RUNNER" stop ) >/dev/null
    wait_pid_or_fail "$RPID" 60 "the runner ends after stop"
    assert_contains "$(last_lanes_dir)/stories/A" "^stopped stopped by user$" "$act repair, then a stop: the story ends stopped by user"
    assert_eq 3 "$(cat "$CALLS/m-A" 2>/dev/null)" "$act repair, then a stop: no fresh finish"
    assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
# ---- #39 T13: the sync check before task and final-review units ----

# sync_events ID — ID's story_synced lines in the last run's events.jsonl.
sync_events() { grep "\"event\":\"story_synced\",\"story\":\"$1\"" "$(last_lanes_dir)/events.jsonl" 2>/dev/null; }
# sync_skips ID — the skipped values of ID's story_synced lines, comma-joined.
sync_skips() { sync_events "$1" | sed -n 's/.*"skipped":"\([a-z-]*\)".*/\1/p' | paste -sd, -; }
# sync_merges ID — the chore(sync) subjects on origin's ID-b, oldest first, `|`-joined.
sync_merges() { git -C "$P" fetch -q origin; git -C "$P" log --reverse --format=%s "origin/$1-b" 2>/dev/null | grep '^chore(sync): ' | paste -sd'|' -; }
# nth_call ID K — the global number of ID's K-th stub call (0 when none).
nth_call() { _nc="$(story_calls "$1" | sort -n | sed -n "${2}p")"; printf '%s\n' "${_nc:-0}"; }
# probe_get N KEY — KEY from call N's probe file.
probe_get() { sed -n "s/^$2=//p" "$CALLS/$1.probe" 2>/dev/null; }
# sync_call — the call number of the (one) sync-repair unit (0 when none).
sync_call() { _sc="$(grep -l '^STUDIO_REPAIR=sync:' "$CALLS"/*.env 2>/dev/null | sed 's#.*/\([0-9]*\)\.env#\1#' | head -n 1)"; printf '%s\n' "${_sc:-0}"; }

test_lanes_sync_clean_merge_no_session() {
  LANES_TASKS=2; export LANES_TASKS
  lanes_fixture syncok integration A:-
  printf 'push_target other.txt\nprobe\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the story lands"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A ends landed"
  n2="$(nth_call A 2)"; _m="$(probe_get "$n2" head)"
  assert_eq "chore(sync): merge origin/integration/demo into A-b" "$(probe_get "$n2" subject)" "before task 2 the lane merged the moved target"
  assert_eq "integration/demo moves: other.txt" "$(git -C "$P" log -1 --format=%s "$(probe_get "$n2" p2)" 2>/dev/null)" "the merge's second parent is the moved target"
  assert_eq "$_m" "$(probe_get "$n2" remote)" "the merge is pushed to origin's A-b (HEAD:refs/heads/A-b)"
  assert_eq 4 "$(story_calls A | wc -l | tr -d ' ')" "no session for the sync: T1, T2, final review, finish, as with no target move"
  assert_missing "$CALLS/m-A.sync" "no sync-repair unit"
  assert_contains "$(last_lanes_dir)/events.jsonl" "\"event\":\"story_synced\",\"story\":\"A\",\"refs\":\[\"origin/integration/demo\"\],\"sha\":\"$_m\"}$" "a story_synced event names the ref and the new head"
  assert_eq "chore(sync): merge origin/integration/demo into A-b" "$(sync_merges A)" "one sync merge in A-b's history"
  assert_eq "no-worktree" "$(sync_skips A)" "before task 1 there is no story worktree yet"
}
test_lanes_sync_skips() {
  for _ss in dirty ahead no-worktree; do
    LANES_TASKS=2; export LANES_TASKS
    lanes_fixture "sync-$_ss" integration A:-
    case "$_ss" in
      dirty) printf 'push_target other.txt; dirty stray.txt\n' > "$SCEN/A" ;;
      ahead) printf 'push_target other.txt; localcommit\nlocalcommit\n' > "$SCEN/A" ;;
      no-worktree) printf 'push_target other.txt; rmwt\nrmwt\n' > "$SCEN/A" ;;
    esac
    run_lanes start "$MFP"
    assert_eq "no-worktree,$_ss,$_ss" "$(sync_skips A)" "$_ss: the checks before task 2 and the final review are skipped=$_ss"
    assert_eq 0 "$(sync_events A | grep -c '"refs"')" "$_ss: no merged event"
    assert_eq "" "$(sync_merges A)" "$_ss: no sync merge"
    assert_contains "$(last_lanes_dir)/stories/A" "^landed " "$_ss: a skip never stops the story"
  done
}
test_lanes_sync_integration_two_refs() {
  LANES_TASKS=2; export LANES_TASKS
  lanes_fixture sync2 integration A:-
  printf 'push_target other.txt; push_main main.txt\nprobe\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  n2="$(nth_call A 2)"; _m="$(probe_get "$n2" head)"
  assert_eq "chore(sync): merge origin/integration/demo into A-b|chore(sync): merge origin/main into A-b" "$(sync_merges A)" "the target, then the default branch, one merge each"
  assert_eq "chore(sync): merge origin/main into A-b" "$(probe_get "$n2" subject)" "both merged before task 2"
  assert_eq 1 "$(sync_events A | grep -c '"refs"')" "one merged event"
  assert_contains "$(last_lanes_dir)/events.jsonl" "\"story\":\"A\",\"refs\":\[\"origin/integration/demo\",\"origin/main\"\],\"sha\":\"$_m\"}$" "it lists both refs in merge order and the new head"
}
test_lanes_sync_failed_merge_aborts() {
  LANES_TASKS=2; export LANES_TASKS
  lanes_fixture syncfail integration A:-
  printf 'mergehook on; push_target other.txt\nprobe; mergehook off\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/events.jsonl" '"event":"story_synced","story":"A","failed":"merge"}$' "a refused merge is failed=merge"
  n2="$(nth_call A 2)"
  assert_eq "ledger(A): T1 complete" "$(probe_get "$n2" subject)" "the head is task 1's"
  assert_eq "$(probe_get "$n2" head)" "$(probe_get "$n2" remote)" "and nothing new was pushed"
  assert_eq "0 0" "$(probe_get "$n2" dirty) $(probe_get "$n2" mergehead)" "merge --abort left a clean tree and no MERGE_HEAD"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "a failed sync never stops the story"
}
test_lanes_sync_conflict_launches_repair() {
  LANES_TASKS=2; export LANES_TASKS
  lanes_fixture synccf integration A:-
  printf 'push_target A-T1.txt\n' > "$SCEN/A"
  printf 'syncrepair\n' > "$SCEN/A.sync"
  run_lanes start "$MFP"
  assert_eq 1 "$(cat "$CALLS/m-A.sync" 2>/dev/null)" "one sync-repair call"
  _n="$(sync_call)"
  assert_contains "$CALLS/$_n.env" "^STUDIO_REPAIR=sync:origin/integration/demo$" "the repair names the ref"
  assert_contains "$CALLS/$_n.argv" "^/game-dev:execute --land$" "through the landing-repair prompt"
  assert_eq opus "$(sed -n 4p "$CALLS/$_n.argv" 2>/dev/null)" "on model_repair"
  _states="$(grep '"event":"story_state","story":"A"' "$(last_lanes_dir)/events.jsonl" | sed -n 's/.*"state":"\([a-z-]*\)".*/\1/p' | paste -sd' ' -)"
  assert_eq "queued running sync-repair running landing landed" "$_states" "the record goes sync-repair, then running, and the story lands"
  assert_eq "1 A-T1 progress,2 A-sync-repair progress,3 A-T2 progress,4 A-final-review progress,5 A-finish done," "$(story_rows A)" "the repair's row is sync-repair, and task 2 follows it"
  assert_eq "" "$(sync_merges A)" "a conflict is never merged by the runner"
}
test_lanes_sync_repair_stops() {
  for _sr in stop noop hang; do
    LANES_TASKS=2; export LANES_TASKS
    LANES_CONFIG='{"overnight": {"kill_grace_seconds": 5}}'; export LANES_CONFIG
    lanes_fixture "syncstop-$_sr" integration A:-
    printf 'push_target A-T1.txt\n' > "$SCEN/A"
    case "$_sr" in
      stop) printf 'stop cannot resolve\n' > "$SCEN/A.sync"; _want="stop: cannot resolve" ;;
      noop) printf 'noop\n' > "$SCEN/A.sync"; _want="no progress" ;;
      hang) printf 'hang\n' > "$SCEN/A.sync"; _want="timed out (session_minutes 90)"
            STUDIO_OVERNIGHT_SESSION_SECONDS=10; export STUDIO_OVERNIGHT_SESSION_SECONDS ;;
    esac
    run_lanes start "$MFP"; unset STUDIO_OVERNIGHT_SESSION_SECONDS
    assert_contains "$(last_lanes_dir)/stories/A" "^stopped sync repair: $_want$" "$_sr: the story ends stopped sync repair: $_want"
    assert_eq 1 "$(cat "$CALLS/m-A.sync" 2>/dev/null)" "$_sr: no retry"
    assert_eq 1 "$(cat "$CALLS/m-A" 2>/dev/null)" "$_sr: no unit after it"
  done
}
# A sync repair that lands but spends the run budget: the story stops before
# its next unit (#39 final review, known #3), as a gate repair's budget does.
test_lanes_sync_repair_budget() {
  LANES_TASKS=2; export LANES_TASKS
  LANES_CONFIG='{"overnight": {"run_usd": 30, "session_usd": 25}}'; export LANES_CONFIG
  lanes_fixture syncbudget integration A:-
  printf 'cost 2; push_target A-T1.txt\n' > "$SCEN/A"
  printf 'syncrepair; cost 4\n' > "$SCEN/A.sync"
  run_lanes start "$MFP"
  assert_eq 1 "$(cat "$CALLS/m-A.sync" 2>/dev/null)" "spent 2 + 25 <= 30: the sync repair runs"
  assert_contains "$(last_lanes_dir)/stories/A" "^stopped stop: run budget$" "spent 6 + 25 > 30 after it: the story stops on the run budget"
  assert_eq 1 "$(cat "$CALLS/m-A" 2>/dev/null)" "no task unit after the repair"
}
test_lanes_no_sync_before_repairs() {
  # A gate repair: the target moves during the red finish.
  lanes_fixture syncgr integration A:-
  printf 'auto\nauto\ngatelog; stop gate red — studio-test: 1 failed; push_target other.txt\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_eq 1 "$(gate_calls)" "gate repair: one gate-repair unit"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "gate repair: A lands"
  assert_eq "no-worktree" "$(sync_skips A)" "gate repair: no check after the target moved (task 1's skip only)"
  assert_eq 1 "$(sync_events A | grep -c .)" "gate repair: no other story_synced event"
  assert_eq "" "$(sync_merges A)" "gate repair: no sync merge"
  # A landing repair: A lands during B's finish, so B's landing conflicts.
  lanes_fixture synclr integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nwaitfor %s\n' "$P/.studio/runs/demo/landed.tsv" > "$SCEN/B"
  printf 'repair\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_eq 1 "$(land_calls)" "landing repair: one repair unit"
  assert_contains "$(last_lanes_dir)/stories/B" "^landed " "landing repair: B lands"
  assert_eq "no-worktree" "$(sync_skips B)" "landing repair: no check after the target moved (task 1's skip only)"
  assert_eq 1 "$(sync_events B | grep -c .)" "landing repair: no other story_synced event"
  assert_eq "" "$(sync_merges B)" "landing repair: no sync merge"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
  # Resume with an unchanged head and the PR open: nothing more. (A done record
  # must be archived first, so the run is made a stopped one: #39 AC8.)
  rm -f "$P/.studio/runs/demo/done"
  next_second
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the resumed run is done"
  assert_eq 1 "$(final_gates)" "a resume at an unchanged target head runs no gate (Step 0 returns before setup)"
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
# main moves during A's finish (a unit with no sync check before it, #39
# D34), so the conflict reaches the final step rather than a sync repair.
test_lanes_final_conflict() {
  lanes_fixture fincf integration A:-
  printf 'conflict shared.txt\nauto\npush_main shared.txt\n' > "$SCEN/A"; printf 'mergemain\n' > "$SCEN/final-repair"
  run_lanes start "$MFP"
  _n="$(prompt_calls '/omega:integration repair demo')"
  assert_eq 1 "$(printf '%s' "$_n" | grep -c .)" "one final-repair unit for the conflict"
  [ -n "$_n" ] || _n=0
  assert_contains "$CALLS/$_n.env" "^STUDIO_REPAIR=conflict$" "the repair knows it is a conflict"
  git -C "$P" fetch -q origin
  assert_status 0 "the repaired merge is pushed" -- git -C "$P" merge-base --is-ancestor origin/main origin/integration/demo
  assert_contains "$P/.studio/runs/demo/final" " green$" "a resolved conflict and a green gate: green"
  # The repair cannot resolve it: red, the integration head unmerged.
  lanes_fixture fincf2 integration A:-
  printf 'conflict shared.txt\nauto\npush_main shared.txt\n' > "$SCEN/A"; printf 'noop\n' > "$SCEN/final-repair"
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
  rm -f "$P/.studio/runs/demo/final" "$P/.studio/runs/demo/done"; next_second
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
  printf 'auto\nauto\nwaitexist %s\n' "$P/.studio/runs/demo/stop" > "$SCEN/B"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -s '$P/.studio/runs/demo/landed.tsv' ]" 60
  ( cd "$P" && sh "$RUNNER" stop ) >/dev/null
  wait_pid_or_fail "$RPID" 60 "the runner ends after stop"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A landed before the stop"
  assert_not_contains "$GH/calls" "^pr create" "no final PR after a stop"
  assert_missing "$P/.claude/worktrees/integration-demo" "the final step does not start after a stop"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
# The default full gate (no test hook): studio-test, studio-lint (exit 3 =
# no linter, not red), studio-run --seconds 10, from the runner's own bin.
test_lanes_final_gate_default() {
  _gb="$TMP/gate bin"; mkdir -p "$_gb"
  cp "$BIN/overnight-ids.sh" "$_gb/"   # overnight-lanes.sh sources it from SELF_DIR (#56)
  printf '#!/bin/sh\necho test >> "%s/gd.log"\n' "$TMP" > "$_gb/studio-test"
  printf '#!/bin/sh\necho lint >> "%s/gd.log"; exit "${GD_LINT:-0}"\n' "$TMP" > "$_gb/studio-lint"
  printf '#!/bin/sh\necho "run $*" >> "%s/gd.log"\n' "$TMP" > "$_gb/studio-run"
  printf '#!/bin/sh\necho "setup $*" >> "%s/gd.log"\n' "$TMP" > "$_gb/studio-setup"
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
  assert_eq "test lint run --seconds 10 setup gate" "$(tr '\n' ' ' < "$TMP/gd.log" | sed 's/ $//')" "test, lint, a 10 s run, then the project gate (D10)"
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
# #42 AC40: a final unit has no STUDIO_STORY; its `studio-state ledger "Stop: x"`
# writes the worktree's local pointer, which must stay out of git (excluded, not
# untracked) so the dirty check and `clean -fdq` neither flag nor delete it.
test_lanes_final_unit_stop_pointer_invisible() {
  lanes_fixture finptr integration A:-
  printf 'stop x\n' > "$SCEN/final-repair"
  use_gate "[ -f fixed ]"
  run_lanes start "$MFP"
  use_gate true
  FINAL_W="$P/.claude/worktrees/integration-demo"
  assert_eq 1 "$(prompt_calls '/omega:integration repair demo' | grep -c .)" "the final-repair unit ran"
  assert_file "$FINAL_W/.studio/STATE.md" "the final unit's Stop line made a local pointer"
  assert_contains "$FINAL_W/.studio/STATE.md" "Stop: x" "and holds the Stop line"
  assert_eq "" "$(git -C "$FINAL_W" status --porcelain 2>&1)" "the pointer is invisible to git status"
  git -C "$FINAL_W" clean -fdq
  assert_file "$FINAL_W/.studio/STATE.md" "git clean -fdq leaves it (excluded, not untracked)"
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
  lanes_fixture fincfred integration A:-
  printf 'conflict shared.txt\nauto\npush_main shared.txt\n' > "$SCEN/A"; printf 'mergemain\nfixgate\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; exit 1"
  run_lanes start "$MFP"
  use_gate true
  assert_eq 1 "$(prompt_calls '/omega:integration repair demo' | grep -c .)" "exactly one final-repair unit"
  assert_eq 1 "$(final_gates)" "one gate"
  assert_contains "$P/.studio/runs/demo/final" " red$" "the step ends red"
}
# A stop that lands while the final worktree is being added ends the step
# before the (possibly long) worktree setup runs.
test_lanes_final_stop_before_setup() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */integration-*) : > '"'$TMP/setup-ran-fstop'"';; esac"}'; export LANES_CONFIG
  lanes_fixture fstop integration A:-
  printf '#!/bin/sh\ncase "$(pwd -P)" in */integration-*) : > "%s/.studio/runs/demo/stop";; esac\n' "$P" > "$P/.git/hooks/post-checkout"
  chmod +x "$P/.git/hooks/post-checkout"
  run_lanes start "$MFP"
  rm -f "$P/.git/hooks/post-checkout"
  assert_missing "$TMP/setup-ran-fstop" "a stop requested before setup: setup does not run"
  assert_not_contains "$GH/calls" "^pr create" "no final PR after the stop"
}
# Final fix wave: a stop during the final gate (a Ctrl-C reaches studio-gate,
# exit 130) records no gate result, so a resume runs the gate again instead
# of opening a [red] PR that no complete gate produced. studio-gate's own
# signal exits (129/130/143) with no stop file are not recorded either; any
# other exit (an engine crash's 139) is a red gate: recorded, repaired.
test_lanes_final_gate_interrupted_not_recorded() {
  lanes_fixture fingint integration A:-
  use_gate "echo gate >> '$CALLS/final-gates'; if [ ! -f '$CALLS/gate-once' ]; then : > '$CALLS/gate-once'; : > '$P/.studio/runs/demo/stop'; exit 130; fi"
  run_lanes start "$MFP"
  assert_eq 1 "$(final_gates)" "the interrupted gate ran once"
  assert_missing "$P/.studio/runs/demo/gate" "a stopped gate records no result"
  assert_not_contains "$GH/calls" "^pr create" "no final PR after the stop"
  assert_eq "" "$(prompt_calls '/omega:integration repair demo')" "no repair after a stopped gate"
  next_second
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

# A dead old-style .studio/overnight.lock naming an older run must not mask a
# newer manifest run in a no-live `status` (#39 final review, T7-2).
test_lanes_status_dead_old_lock_not_masking() {
  lanes_fixture sdol integration A:-
  run_lanes start "$MFP"
  R="$(last_lanes_dir)"
  _o="$P/.studio/reports/overnight-20000101-000000"; mkdir -p "$_o"
  printf '# Overnight run\n\nEnding: done\n' > "$_o/report.md"; touch -t 200001010000 "$_o"
  _d="$(sh -c 'echo $$')"
  printf 'pid=%s\nrun=%s\nstarted=2000-01-01T00:00:00Z\n' "$_d" "$_o" > "$P/.studio/overnight.lock"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1; _st=$?
  assert_eq 1 "$_st" "no live run: status exits 1"
  assert_contains "$TMP/st.out" "^no run — the last run: $R$" "the newer manifest run is shown, not the dead lock's older run"
  assert_not_contains "$TMP/st.out" "$_o" "the dead lock's run is not named"
  rm -f "$P/.studio/overnight.lock"
}
# chain_unit_now C — chain C is claimed and its lane's unit.now exists.
chain_unit_now() {
  _cu_r="$(last_lanes_dir)"; _cu_k="$(cat "$_cu_r/claims/$1/lane" 2>/dev/null)"
  [ -n "$_cu_k" ] && [ -e "$_cu_r/lanes/$_cu_k/unit.now" ]
}
test_lanes_status_per_story() {
  lanes_fixture stat integration A:- B:A C:-
  printf 'waitexist %s\n' "$SCEN/release-stat" > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -n \"\$(story_calls A)\" ]" 20
  # C's chain is claimed and A's unit.now is written: status shows both.
  wait_for 'chain_unit_now 1 && [ -s "$(last_lanes_dir)/claims/2/lane" ]' 60
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out"; st=$?
  : > "$SCEN/release-stat"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq 0 "$st" "status exits 0 during a run"
  # The run's block follows the project's sessions line (#39 AC10, D15).
  assert_eq "A B C" "$(awk '!/^ / && !/^progress:/ && !/^sessions:/ { if (++r > 3) exit; printf "%s%s", s, $1; s=" " }' "$TMP/st.out")" "stories in manifest order"
  assert_contains "$TMP/st.out" "^A  lane [12]  running  unit A T1  task 0/1   \[[= ]*\] [0-9]*%$" "A is running T1"
  assert_contains "$TMP/st.out" "^B  lane [12]  queued  unit -  task 0/1   \[[= ]*\] [0-9]*%$" "B waits in A's chain, on A's lane"
  assert_contains "$TMP/st.out" "^C  lane [12]  " "C has its own lane"
  assert_contains "$TMP/st.out" "^gate: " "the gate line"
  assert_contains "$TMP/st.out" "^spent: \\$" "the spend line"
  assert_contains "$TMP/st.out" "^pid: $RPID$" "the runner pid"
  assert_contains "$TMP/st.out" "^progress: \[[= ]*\] [0-9]*%  [0-9]*/[0-9]* units · ETA" "the progress line comes with a finish estimate"
  assert_contains "$TMP/st.out" "^env: cpu " "the resource readout"
  assert_eq 1 "$(awk '/^pid:/ { p = NR } /^env:/ { e = NR } END { print (p && e > p) ? 1 : 0 }' "$TMP/st.out")" "the readout comes after the existing lines"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
  printf 'waitexist %s\n' "$SCEN/release-reap" > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  R="$(last_lanes_dir)"; lane1="$(cat "$R"/claims/1/pid 2>/dev/null)"
  kill -9 "$RPID"; wait "$RPID" 2>/dev/null
  : > "$SCEN/release-reap"
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
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  assert_contains "$R/report.md" "^Ending: stop: runner gone$" "status writes the report"
  for id in A B C; do assert_contains "$R/report.md" "^## $id$" "the report names $id"; done
  assert_contains "$R/report.md" "^Not landed: stopped — stop: runner gone$" "A's outcome"
  assert_contains "$R/report.md" "^Not landed: skipped — run stopped$" "C's outcome"
  assert_contains "$R/events.jsonl" '"event":"story_state","story":"A","state":"stopped","why":"stop: runner gone"}$' "the reap's stopped story_state carries its why"
  assert_contains "$R/events.jsonl" '"event":"story_state","story":"C","state":"skipped","why":"run stopped"}$' "and the skipped one"
  # A resume after a SIGKILLed runner: the stale run gets its report too.
  lanes_fixture reap2 integration A:-
  printf 'waitexist %s\n' "$SCEN/release-reap" > "$SCEN/A"
  ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & RPID=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 20
  R="$(last_lanes_dir)"; lane1="$(cat "$R"/claims/1/pid 2>/dev/null)"
  kill -9 "$RPID"; wait "$RPID" 2>/dev/null
  : > "$SCEN/release-reap"
  wait_for "! kill -0 ${lane1:-0} 2>/dev/null" 30
  kill -9 "${lane1:-0}" 2>/dev/null
  next_second
  run_lanes start "$MFP"
  assert_contains "$R/report.md" "^Ending: stop: runner gone$" "start writes the stale run's report before it resumes"
  assert_eq 0 "$LS_STATUS" "the resumed run lands A"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
  wait_for "[ ! -f '$P/.studio/runs/demo/lock' ]" 60
  wait_for "[ -z \"\$(pgrep -f '$TMP')\" ]" 20
}
test_lanes_detach_strips_env() {
  lanes_fixture det integration A:-
  st=0
  ( cd "$P" && env CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=x CLAUDE_EFFORT=max CLAUDE_PID=1 AI_AGENT=x \
      CLAUDE_CONFIG_DIR="$TMP/cfg" OMEGA_X=1 STUDIO_STORY=Z STUDIO_X=1 \
      sh "$RUNNER" start --detach "$MFP" ) > "$TMP/det.out" 2>&1 || st=$?
  assert_eq 0 "$st" "detach reports success once status answers"
  assert_contains "$TMP/det.out" "^detached: pid [0-9]*, log " "it prints the pid and the log"
  assert_contains "$TMP/det.out" "^env: cpu " "the foreground preflight prints the resource readout"
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
  # Reaped here, so bash's "Killed: 9" job notice goes to /dev/null and not
  # to the suite's output while the detach below runs.
  wait "$RPID" 2>/dev/null
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/detk.out" 2>&1 || st=$?
  pkill -f "$TMP/fakebin/claude" 2>/dev/null; pkill -f "$TMP/bin/studio-overnight start" 2>/dev/null
  wait_for "[ -z \"\$(pgrep -f '$TMP')\" ]" 20
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
  assert_contains "$TMP/dtl.out" "status --run demo, or .*/studio-overnight' stop --run demo$" "status and stop name the detached run (another run may be live)"
  assert_not_contains "$TMP/dtl.out" "run the plain command" "no plain start is offered"
  assert_eq 1 "$([ -f "$P/.studio/runs/demo/lock" ] && echo 1 || echo 0)" "the run still holds its lock"
  # The hung stub would hold the run past stop: end it, then wait the run out.
  ( cd "$P" && sh "$RUNNER" stop ) > /dev/null 2>&1; pkill -f "$TMP/fakebin/claude" 2>/dev/null
  detach_stop
}
test_lanes_detach_timeout_no_lock_ends_child() {
  lanes_fixture dtn integration A:-
  export STUDIO_OVERNIGHT_DETACH_STATUS_CMD=false
  export STUDIO_OVERNIGHT_DETACH_CHILD_CMD="'$TMP/bin/msleep' 301 & '$TMP/bin/msleep' 301"
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/dtn.out" 2>&1 || st=$?
  unset STUDIO_OVERNIGHT_DETACH_STATUS_CMD STUDIO_OVERNIGHT_DETACH_CHILD_CMD
  assert_eq 1 "$st" "a status timeout exits 1"
  assert_contains "$TMP/dtn.out" "never took the lock" "the message says the child was ended"
  assert_contains "$TMP/dtn.out" "start " "and the plain command is printed"
  wait_for '[ -z "$(pgrep -f "$TMP/bin/msleep 301\$")" ]' 1
  assert_eq 0 "$(pgrep -f "$TMP/bin/msleep 301\$" | wc -l | tr -d ' ')" "no child survives"
}
test_lanes_detach_poll_keeps_budget() {
  lanes_fixture dpk integration A:-
  : > "$TMP/dpk.count"
  STUDIO_OVERNIGHT_DETACH_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_DETACH_STATUS_CMD="echo x >> '$TMP/dpk.count'; false"
  STUDIO_OVERNIGHT_DETACH_CHILD_CMD="'$TMP/bin/msleep' 309"
  export STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_STATUS_CMD STUDIO_OVERNIGHT_DETACH_CHILD_CMD
  _t0=$(date +%s); st=0
  ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/dpk.out" 2>&1 || st=$?
  _el=$(( $(date +%s) - _t0 ))
  unset STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_STATUS_CMD STUDIO_OVERNIGHT_DETACH_CHILD_CMD
  assert_eq 1 "$st" "the window times out: the child never took the lock"
  assert_contains "$TMP/dpk.out" "never took the lock" "the no-lock message"
  assert_eq 1 "$([ "$_el" -ge 10 ] && echo 1 || echo 0)" "the window still lasts 10 s at a 0.2 s poll (${_el}s)"
  assert_eq 50 "$(wc -l < "$TMP/dpk.count" | tr -d ' ')" "the status check ran 10 s x 5 ticks: the knob survived --detach's STUDIO_* strip"
}
test_lanes_detach_poll_rejects_bad_value() {
  lanes_fixture dpb integration A:-
  st=0
  ( cd "$P" && STUDIO_OVERNIGHT_DETACH_POLL_SECONDS=1.0 sh "$RUNNER" start --detach "$MFP" ) > "$TMP/dpb.out" 2>&1 || st=$?
  assert_eq 2 "$st" "a bad detach poll exits 2"
  assert_contains "$TMP/dpb.out" "studio-overnight: STUDIO_OVERNIGHT_DETACH_POLL_SECONDS must be 1, 0.5, 0.2 or 0.1, got 1.0" "the refusal names the knob and the value"
  assert_missing "$P/.studio/runs/demo/lock" "no run lock was taken"
  assert_not_contains "$TMP/dpb.out" "detached:" "nothing was detached"
}
test_lanes_origin_attached() {
  lanes_fixture ora integration A:-
  rm -f "$HOME/.claude-gamedev/runs/last"
  STUDIO_RUN_ORIGIN="multica:task-a1"; export STUDIO_RUN_ORIGIN
  run_lanes start "$MFP"; unset STUDIO_RUN_ORIGIN
  assert_eq 0 "$LS_STATUS" "the manifest run lands A"
  assert_contains "$HOME/.claude-gamedev/runs/last" '^origin=multica:task-a1$' "manifest mode writes origin=, kept in runs/last"
  assert_not_contains "$CALLS/1.fullenv" '^STUDIO_RUN_ORIGIN=' "no unit session inherits the variable"
}
test_lanes_origin_detach() {
  lanes_fixture ord integration A:-
  printf 'emit %s; waitexist %s\n' "$ACT" "$P/.studio/runs/demo/stop" > "$SCEN/A"
  st=0
  ( cd "$P" && env STUDIO_RUN_ORIGIN=multica:task-d1 sh "$RUNNER" start --detach "$MFP" ) > "$TMP/det.out" 2>&1 || st=$?
  assert_eq 0 "$st" "detach starts"
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  _e="$(ls -t "$HOME"/.claude-gamedev/runs/overnight-demo-* 2>/dev/null | head -n 1)"
  assert_contains "$_e" '^origin=multica:task-d1$' "--detach carries origin= through its STUDIO_* strip"
  assert_not_contains "$CALLS/1.fullenv" '^STUDIO_RUN_ORIGIN=' "the detached run's unit does not inherit it"
  detach_stop
  assert_contains "$HOME/.claude-gamedev/runs/last" '^origin=multica:task-d1$' "kept in runs/last"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_origin_detach_refused() {
  lanes_fixture odr integration A:-
  st=0
  ( cd "$P" && env 'STUDIO_RUN_ORIGIN=bad value' sh "$RUNNER" start --detach "$MFP" ) > "$TMP/det.out" 2>&1 || st=$?
  assert_eq 0 "$st" "a refused origin still starts the run"
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  _e="$(ls -t "$HOME"/.claude-gamedev/runs/overnight-demo-* 2>/dev/null | head -n 1)"
  assert_not_contains "$_e" '^origin=' "no origin= line"
  _dl="$(ls -t "$P"/.studio/reports/overnight-demo-detached-*.log | head -n 1)"
  assert_eq 1 "$(cat "$TMP/det.out" "$_dl" | grep -c 'STUDIO_RUN_ORIGIN ignored')" "one warning, in the foreground only"
  detach_stop
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
  assert_eq "" "$(pgrep -f 'studio-gate studio-test' 2>/dev/null | while read -r p; do ps -o args= -p "$p" | grep -F "$CALLS" ; done)" "no studio-gate of this run survives"   # scan-ok: filtered by $CALLS on the same line
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
  P1="$P"; ln -s "$P1" "$TMP/any1-link"; _s1="$SCEN"; _c1="$CALLS"
  printf 'emit %s; waitexist %s\n' "$ACT" "$SCEN/release-any1" > "$SCEN/A"
  ( cd "$TMP/any1-link" && exec sh "$RUNNER" start "$MFP" ) > /dev/null 2>&1 & R1=$!
  wait_for "[ -f '$CALLS/1.t0' ]" 30
  # The session's activity is in its stream log before status reads it.
  wait_for "grep -q 'loader fold options' \"\$(last_lanes_dir)\"/lanes/1/*.jsonl 2>/dev/null" 60
  status_from "$ELSEWHERE"
  assert_eq 3 "$ST_RC" "one live run elsewhere: exit 3 (0 is kept for this project's run)"
  assert_eq 1 "$(ls "$REG" | grep -c '^overnight-demo-[0-9-]*-[0-9]*$')" "the entry is named <run dir>-<runner pid>"
  assert_contains "$TMP/st.out" "^== overnight-demo-[0-9-]* — $P1$" "it names the run and its project (the real path)"
  assert_contains "$TMP/st.out" "^A  lane 1  running  unit A T1  task 0/1   \[[= ]*\] [0-9]*%$" "the project's own status follows"
  assert_contains "$TMP/st.out" "^    1-A-T1 · [0-9]*s · ui-designer · \"T1 loader fold options\" · Bash: npx vitest" "the running unit's last activity in one line"
  assert_contains "$TMP/st.out" "^gate: free$" "the gate lock"
  status_from "$TMP/any1-link"
  assert_eq 0 "$ST_RC" "from the symlinked spelling of the project: live"
  status_from "$P1"
  assert_eq 0 "$ST_RC" "from the real path: live"
  # Two live runs.
  lanes_fixture any2 integration B:-
  P2="$P"; _s2="$SCEN"; _c2="$CALLS"; printf 'waitexist %s\n' "$SCEN/release-any2" > "$SCEN/B"
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
  : > "$_s1/release-any1"; : > "$_s2/release-any2"
  wait_pid_or_fail "$R1" 90 "run 1 ends"; wait_pid_or_fail "$R2" 90 "run 2 ends"
  assert_missing "$_c1/wait.timeout" "no stub wait hit its ceiling (first run)"
  assert_missing "$_c2/wait.timeout" "no stub wait hit its ceiling (second run)"
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
  printf '1 studio-test 3000 0\n2 gate 2400 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_contains "$LS_ERR" "the slowest of the last 10 studio-test runs plus the slowest of the last 10 gate_command runs took 90 min" "the sum names both gates"
  assert_contains "$LS_ERR" "at least 118" "the minimum covers the sum"
  printf '1 gate 600 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_not_contains "$LS_ERR" "warning: the slowest" "a 10-minute gate_command alone fits"
}
# gate.times tolerates a non-integer duration: it is skipped, not fatal.
test_lanes_gate_times_non_integer() {
  lanes_fixture gtni integration A:-
  printf '1 studio-test 12.5 0\n2 studio-test abc 0\n3 gate 1e3 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "non-integer gate.times values do not abort the preflight"
  assert_not_contains "$LS_ERR" "syntax\|arithmetic\|warning: the slowest" "skipped, no shell error, no warning"
  printf '1 studio-test 12.5 0\n2 studio-test 5400 0\n' > "$P/.studio/gate.times"
  run_lanes start --dry-run "$MFP"
  assert_contains "$LS_ERR" "warning: the slowest of the last 10 studio-test runs took 90 min" "integer rows still count beside a skipped one"
}
# D2: check lines count after the last adopt reset only, so an old `check
# done` does not hide a re-ledgered `check requested`.
test_lanes_check_truth_region() {
  lanes_fixture ctr integration A:- B:-
  for _t in "A:check requested" "A:check done none" "B:check requested" "B:check done none" "B:adopt reset 2026-10-04" "B:check requested"; do
    ( cd "$P" && STUDIO_STORY="${_t%%:*}" sh "$STATE_BIN" ledger "${_t#*:}" ) >/dev/null 2>&1
  done
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm chk ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "dry run exits 0"
  assert_eq 1 "$(grep -c "STUDIO_STORY='B'.*'--model' 'opus'" "$LS_OUT")" "B (check requested after its reset) gets the check unit's model"
  assert_eq 0 "$(grep -c "STUDIO_STORY='A'.*'--model' 'opus'" "$LS_OUT")" "A (its check done) does not"
}
# D14: the gate-repair unit reads the log the Stop line names.
test_lanes_gate_log_from_stop() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture gatestop integration A:-
  printf 'auto\nauto\ngatelog; stop gate red — gate_command exit 3 — log .studio/reports/gate-20261004-000000.log\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  n="$(gate_call)"; [ -n "$n" ] || n=0
  assert_contains "$CALLS/$n.env" "^STUDIO_REPAIR=gate:/.*/A-b/\.studio/reports/gate-20261004-000000\.log$" "the Stop's log wins over the newer test log"
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
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nwaitfor %s\n' "$P/.studio/runs/demo/landed.tsv" > "$SCEN/B"
  printf 'noop\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped repair made no progress$" "a land repair with no progress ends at once (AC18)"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  lanes_fixture lnh2 integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nwaitfor %s\n' "$P/.studio/runs/demo/landed.tsv" > "$SCEN/B"
  printf 'stop cannot resolve\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: cannot resolve$" "a land repair's Stop: ends at once"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  lholds_off
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_stop_queued_story() {
  lanes_fixture sqs integration A:- B:A D:B
  printf 'waitexist @RUN@/control/B.stop; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec B)" = queued ]' 30
  lverb stop B; assert_eq "stop requested: B stops when its lane reaches it" "$(cat "$LV_OUT")" "stop on a queued story"
  wait_pid_or_fail "$RPID" 120 "the run ends"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq "stopped by operator" "$(rec B)" "B never starts (AC7, R5)"
  assert_eq "skipped B" "$(rec D)" "the rest of the chain is skipped, as today"
  assert_eq "" "$(story_calls B)" "B ran no unit"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "no control file left"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_stop_running_story() {
  lanes_fixture srs integration A:-
  printf 'waitexist @RUN@/control/A.stop; auto\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec A)" = running ]' 30
  lverb stop A; assert_eq "stop requested: A stops after its running unit" "$(cat "$LV_OUT")" "stop on a running story"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "after its unit (AC23)"
  assert_eq "1 A-T1 progress," "$(story_rows A)" "one unit ran"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_stop_waiting_story() {
  lanes_fixture sws integration A:- B:- C:A,B
  STUDIO_OVERNIGHT_POLL_SECONDS=1; export STUDIO_OVERNIGHT_POLL_SECONDS
  printf 'waitexist %s; auto\n' "$SCEN/release-sws" > "$SCEN/A"; printf 'waitexist %s; auto\n' "$SCEN/release-sws" > "$SCEN/B"
  lanes_bg
  wait_for '[ "$(rec C)" = waiting ]' 30
  lverb stop C; assert_eq "stop requested: C stops when its lane reaches it" "$(cat "$LV_OUT")" "stop on a waiting story"
  wait_for '[ "$(rec C)" = "stopped by operator" ]' 5
  assert_eq "stopped by operator" "$(rec C)" "a waiting story stops within one poll"
  assert_eq 0 "$(awk 'BEGIN { n = 0 } /landed/ { n++ } END { print n }' "$(last_lanes_dir)/stories/A")" "before A lands"
  : > "$SCEN/release-sws"
  wait_pid_or_fail "$RPID" 120 "the run ends"
  assert_eq "" "$(story_calls C)" "C ran no unit"
  for id in A B; do assert_contains "$(last_lanes_dir)/stories/$id" "^landed " "$id still lands"; done
  unset STUDIO_OVERNIGHT_POLL_SECONDS
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_hold_waiting_story_holds_at_start() {
  lanes_fixture hws integration A:- B:- C:A,B
  lholds_on 120
  printf 'waitexist @RUN@/control/C.hold; auto\n' > "$SCEN/A"
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
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_hold_running_then_resume() {
  lanes_fixture hrr integration A:-
  lholds_on 120
  printf 'waitexist @RUN@/control/A.hold; auto\nauto\nauto\n' > "$SCEN/A"
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
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
  printf 'auto\nauto\nwaitexist @RUN@/control/A.stop; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 3 ] && [ "$(rec A)" = running ]' 40
  lverb stop A; assert_eq "stop requested: A stops after its running unit" "$(cat "$LV_OUT")" "stop during the last unit"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "a .stop at done stops before landing (R5)"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish done," "$(story_rows A)" "the last unit was done"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "no control file left"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_stop_held_by_operator() {
  lanes_fixture sho integration A:-
  lholds_on 120
  printf 'waitexist @RUN@/control/A.hold; auto\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec A)" = running ]' 30
  lverb hold A
  wait_for 'is_held A' 30
  lverb stop A; assert_eq "stop requested: A stops within one poll" "$(cat "$LV_OUT")" "stop on an operator-held story"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "stopped by operator, not stopped held by operator (R5)"
  lholds_off
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_stop_pending_never_holds() {
  lanes_fixture spn integration A:-
  lholds_on 120
  printf 'auto\nwaitexist @RUN@/control/A.stop; stop need art\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 2 ] && [ "$(rec A)" = running ]' 30
  lverb stop A
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "a stop sent during the unit that ends holdable ends the story (R5)"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "no held event for a hold that never waited"
  lholds_off
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
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
  printf 'auto\nauto\nwaitexist @RUN@/control/A.hold; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 3 ] && [ "$(rec A)" = running ]' 40
  lverb hold A
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "a hold sent during the last unit: the story still lands"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "the .hold is cleared when the story ends (R25)"
  lholds_off
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}

# Last: no process any test started is still alive.
test_lanes_no_orphans() {
  _left="$(pgrep -f "$TMP" 2>/dev/null)"
  assert_eq "" "$_left" "no stub session, lane or runner outlives its test"
}

# ---- #35: autopilot adopts outside work ----
# redocs — commit everything in $P and point the manifest's Docs: at that commit.
redocs() {
  ( cd "$P" && git add -A && git commit -q -m "docs: more" && git push -q origin run/demo \
    && _rd="$(git rev-parse HEAD)" && sed "s/^Docs: .*/Docs: $_rd/" "$MFP" > "$TMP/mf.new" && cp "$TMP/mf.new" "$MFP" \
    && git add -A && git commit -q -m manifest && git push -q origin run/demo ) >/dev/null 2>&1
}
# adopt_docs ID — ID's Docs ledger gets the adopted and adopt-base lines (the
# original and converted plan are one file here, so the stub's sync passes).
adopt_docs() {
  _ad_p="docs/game-dev/plans/2026-10-01-$1.md"
  printf -- '- 2026-10-01 adopted %s -> %s\n- 2026-10-01 adopt-base %s\n' "$_ad_p" "$_ad_p" "$(git -C "$P" rev-parse origin/integration/demo)" \
    >> "$P/.studio/ledger/$1.md"
}

# adopt_lanes_fixture NAME — lanes_fixture NAME integration S1:-, then S1 made an
# adopted, half-done story as autopilot step 3 leaves it:
# - a 6-task original plan $AO and a 6-task converted plan (Story: S1, Source:)
#   in the manifest's Plan cell;
# - branch S1-b off origin/main with T1-T3 done the standard way (one commit each,
#   plus SDD claims in the worktree's $AWS for $AO), pushed;
# - the worktree $AW at $P/.claude/worktrees/S1-b;
# - `studio-adopt seed S1` committed, `check --rebuild` = 3/6, stage execute;
# - Docs: re-pointed at the new docs commit. Exports AO, AW, AWS.
adopt_lanes_fixture() {
  lanes_fixture "$1" integration S1:-
  AO=docs/superpowers/plans/2026-09-01-demo.md; AW="$P/.claude/worktrees/S1-b"; AWS=.superpowers/sdd/2026-09-01-demo
  export AO AW AWS
  _alf_c=docs/game-dev/plans/2026-10-01-S1.md
  ( set -e; cd "$P"
    mkdir -p "$(dirname "$AO")"
    { printf '# Demo\n\n'; for i in 1 2 3 4 5 6; do printf '### Task %s: step %s\n\nFiles: s%s.txt\n\n' "$i" "$i" "$i"; done; } > "$AO"
    { printf '# Plan: S1\n\nStory: S1\nSource: %s\n\n## Global Constraints\n\n- none\n\n## Decisions\n\n- none\n\n## Acceptance criteria\n\n1. works\n\n' "$AO"
      for i in 1 2 3 4 5 6; do printf '### Task %s: step %s\n\nSpec: %s:L3-4\nReview: final\n\n' "$i" "$i" "$AO"; done
      printf '## Backlog\n'; } > "$_alf_c"
    git add -A; git commit -q -m "adopt: plans"; git push -q origin run/demo
    git push -q origin "$(git rev-parse HEAD):refs/heads/main"   # the original is on main too
    git fetch -q origin
    STUDIO_STORY=S1; export STUDIO_STORY
    sh "$STATE_BIN" set task 0/6
    sh "$STATE_BIN" ledger "source $AO spec -"; sh "$STATE_BIN" ledger "adopted $AO -> $_alf_c"
    git worktree add -q --no-track -b S1-b "$AW" origin/main
    cd "$AW"; mkdir -p "$AWS"; printf '%s\n' "$AO" > "$AWS/plan-path"; printf '*\n' > .superpowers/sdd/.gitignore
    printf '# SDD ledger — plan: %s\n' "$AO" > "$AWS/progress.md"
    for i in 1 2 3; do
      _a="$(git rev-parse --short HEAD)"; printf '%s\n' "$i" > "s$i.txt"; git add "s$i.txt"; git commit -q -m "feat: step $i"
      printf 'Task %s: complete (commits %s..%s, review clean)\n' "$i" "$_a" "$(git rev-parse --short HEAD)" >> "$AWS/progress.md"
    done
    git push -q -u origin S1-b
    sh "$STATE_BIN" set branch S1-b; sh "$STATE_BIN" set stage execute
    [ "${ALF_NOSEED:-}" = 1 ] || { sh "$ADOPT_BIN" seed S1; sh "$STATE_BIN" check --rebuild; }
    cd "$P"; unset STUDIO_STORY
    git add -A .studio/ledger; git commit -q -m "docs(run): demo planned"; git push -q origin run/demo
    _d="$(git rev-parse HEAD)"; sed "s/^Docs: .*/Docs: $_d/" "$MFP" > "$MFP.t" && mv "$MFP.t" "$MFP"
    git add "$MFP"; git commit -q -m "docs(run): demo docs"; git push -q origin run/demo ) >/dev/null 2>&1 \
    || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "adopt_lanes_fixture $1: setup failed"; }
}

test_lanes_ready_adopted_unseeded() {
  ALF_NOSEED=1; adopt_lanes_fixture rau; unset ALF_NOSEED
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "an unseeded adopted story refuses the start"
  assert_contains "$LS_ERR" "S1: adopted (.*) but not seeded on S1-b" "names the story and branch"
  assert_contains "$LS_ERR" "studio-adopt seed S1 in $AW" "and the fix, in its worktree"
  ( cd "$AW" && sh "$ADOPT_BIN" seed S1 && STUDIO_STORY=S1 sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "seeded: the dry run passes"
}
test_lanes_ready_needs_run_pointer() {
  lanes_fixture rnp integration A:-
  rm -f "$P/.studio/run"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "no .studio/run: refused"
  assert_contains "$LS_ERR" "start checkout $P has no .studio/run — write it there: printf '%s\\\\n' $MFP > .studio/run" "names the checkout and the pointer to write"
  # #50 final review M2: the pointer must name this run's manifest.
  printf 'docs/runs/demoo.md\n' > "$P/.studio/run"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a pointer naming a missing file: refused"
  assert_contains "$LS_ERR" "start checkout $P: .studio/run names docs/runs/demoo.md, not this run's manifest — write it there: printf '%s\\\\n' $MFP > .studio/run" "names the bad pointer and the fix"
  sed 's/^# Run: demo$/# Run: other/' "$P/$MFP" > "$P/docs/runs/other.md"
  printf '%s\n' "$P/docs/runs/other.md" > "$P/.studio/run"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a pointer naming another run's manifest: refused"
  assert_contains "$LS_ERR" "start checkout $P: .studio/run names $P/docs/runs/other.md, not this run's manifest" "names the other manifest"
  printf '%s\n' "$MFP" > "$P/.studio/run"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "with the pointer: the dry run passes"
}
# #50 final review M5/M6: the readiness hint never names a removed worktree,
# and an adopted story whose branch is gone after landing is skipped.
test_lanes_ready_stale_worktree_and_landed() {
  ALF_NOSEED=1; adopt_lanes_fixture rsl; unset ALF_NOSEED
  rm -rf "$AW"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "unseeded, its worktree removed: refused"
  assert_contains "$LS_ERR" "studio-adopt seed S1 in the S1-b worktree, then" "the hint names the branch's worktree, not the removed path"
  assert_not_contains "$LS_ERR" "seed S1 in $AW" "never the removed path"
  ( cd "$P" && git worktree prune && git branch -q -D S1-b && git push -q origin --delete S1-b && git fetch -q --prune origin ) >/dev/null 2>&1
  run_lanes start --dry-run "$MFP"
  assert_not_contains "$LS_ERR" "not seeded on S1-b" "branch gone after landing: not a readiness problem"
  assert_eq 0 "$LS_STATUS" "and the dry run passes"
}
test_lanes_adopt_seeded_runs_rest() {
  adopt_lanes_fixture asr
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_eq "1 S1-T4 progress,2 S1-T5 progress,3 S1-T6 progress,4 S1-final-review progress,5 S1-finish done," "$(story_rows S1)" "a seeded 3/6 story runs T4-T6, then the final review and finish"
  git -C "$AW" log --format=%s origin/S1-b > "$TMP/asr.log"
  for _t in 4 5 6; do
    assert_eq 1 "$(grep -c "^feat(S1): T$_t\$" "$TMP/asr.log")" "one T$_t commit"
  done
  git -C "$AW" show origin/S1-b:.studio/ledger/S1.md > "$TMP/asr.led" 2>/dev/null
  assert_eq 3 "$(grep -c '^- [0-9-]* T[456] complete [0-9a-f]\{40\}\.\.[0-9a-f]\{40\}$' "$TMP/asr.led")" "the ledger's T4-T6 lines are full-sha ranges"
}

test_lanes_adopt_round_trip() {
  adopt_lanes_fixture art
  lholds_on 120
  printf 'auto\nstop broke\n' > "$SCEN/S1"
  lanes_bg
  wait_for 'is_held S1' 60
  lverb stop
  wait_pid_or_fail "$RPID" 60 "the run ends"
  lholds_off
  case "$(story_rows S1)" in
    "1 S1-T4 progress,2 S1-T5"*) _pass_msg=ok ;;
    *) _pass_msg="" ;;
  esac
  assert_eq ok "$_pass_msg" "the first run did T4 and started T5 ($(story_rows S1))"
  assert_contains "$(last_lanes_dir)/stories/S1" "was held: stop: broke" "the held story's record"
  # An operator resolves the Stop in the worktree, then syncs.
  ( cd "$AW" && git commit -qam "ledger: stop" ) >/dev/null 2>&1
  _art_s=0; ( cd "$AW" && STUDIO_STORY= sh "$ADOPT_BIN" sync S1 ) > "$TMP/art.out" 2> "$TMP/art.err" || _art_s=$?
  assert_eq 0 "$_art_s" "the operator's sync succeeds ($(tail -n 1 "$TMP/art.err"))"
  assert_contains "$AW/$AWS/progress.md" "^Task 4: complete (commits [0-9a-f]\{40\}\.\.[0-9a-f]\{40\}, review clean)$" "T4 is claimed in the original's SDD ledger"
  # Standard-mode T5.
  ( cd "$AW" && _a="$(git rev-parse --short HEAD)" && printf '5\n' > s5.txt && git add s5.txt && git commit -q -m "feat: step 5 (standard)" \
    && printf 'Task 5: complete (commits %s..%s, review clean)\n' "$_a" "$(git rev-parse --short HEAD)" >> "$AWS/progress.md" ) >/dev/null 2>&1
  printf 'auto\nauto\nauto\n' > "$SCEN/S1"; echo 0 > "$CALLS/m-S1"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the second run is done"
  assert_eq "1 S1-T5 progress,2 S1-final-review progress,3 S1-finish done," "$(story_rows S1)" "the new run's units, the first labelled T5 (D38)"
  git -C "$AW" log --format=%s origin/S1-b > "$TMP/art.log"
  assert_eq 1 "$(grep -c '^feat: step 5 (standard)$' "$TMP/art.log")" "the standard T5 commit once"
  assert_eq 0 "$(grep -c '^feat(S1): T5$' "$TMP/art.log")" "no studio T5 commit"
  assert_eq 1 "$(grep -c '^feat(S1): T6$' "$TMP/art.log")" "one T6 commit"
  _art_sync="$(git -C "$AW" log --format=%H --grep='^chore(studio): ledger (sync)$' origin/S1-b | head -n 1)"
  [ -n "$_art_sync" ] || _art_sync=none
  git -C "$AW" show "$_art_sync" > "$TMP/art.sync" 2>/dev/null
  assert_contains "$TMP/art.sync" "^+- [0-9-]* T5 complete [0-9a-f]\{40\}\.\.[0-9a-f]\{40\}$" "a ledger (sync) commit adds the T5 claim"
  assert_contains "$(last_lanes_dir)/stories/S1" "^landed " "the story landed"
}

test_lanes_next_adopted_planned() {
  lanes_fixture nad integration S1:- S2:-
  mkdir -p "$P/docs/superpowers/specs" "$P/docs/superpowers/plans"
  printf '# S1\n\nAn outside spec, no stories table.\n' > "$P/docs/superpowers/specs/2026-09-01-s1.md"
  printf '# S2 plan\n\n### Task 1: t\n' > "$P/docs/superpowers/plans/2026-09-01-s2.md"
  sed -e 's#^\(| S1 | S1-b | S1 | \)[^|]*|#\1docs/superpowers/specs/2026-09-01-s1.md |#' \
      -e 's#^\(| S2 | S2-b | S2 | \)[^|]*|#\1docs/superpowers/plans/2026-09-01-s2.md |#' "$P/$MFP" > "$TMP/mf.s" && cp "$TMP/mf.s" "$P/$MFP"
  printf -- '- 2026-10-01 spec approved docs/superpowers/specs/2026-09-01-s1.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-S1.md\n- 2026-10-01 Decisions swept S1\n' > "$P/.studio/ledger/s1.md"
  printf -- '- 2026-10-01 spec approved docs/superpowers/plans/2026-09-01-s2.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-S2.md\n- 2026-10-01 Decisions swept S2\n' > "$P/.studio/ledger/s2.md"
  ( cd "$P" && git add -A && git commit -qm planning-state ) >/dev/null 2>&1
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next exits 0"
  assert_contains "$LS_OUT" "^S1  planned  spec=docs/superpowers/specs/2026-09-01-s1.md  plan=" "an adopted story with a superpowers spec is planned"
  assert_contains "$LS_OUT" "^S2  planned  spec=docs/superpowers/plans/2026-09-01-s2.md  plan=" "one with the original plan as its Spec cell is planned"
}

test_lanes_context_preflight() {
  lanes_fixture ctx integration S1:-
  sed 's#^Story: S1$#Story: S1\nContext: docs/game-dev/adopted/S1/carry.md#' "$P/docs/game-dev/plans/2026-10-01-S1.md" > "$TMP/p.s" \
    && cp "$TMP/p.s" "$P/docs/game-dev/plans/2026-10-01-S1.md"
  redocs
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a Context file missing from Docs is refused"
  assert_contains "$LS_ERR" "S1: Context file docs/game-dev/adopted/S1/carry.md is not in Docs: $(sed -n 's/^Docs: //p' "$P/$MFP")$" "naming the path and the Docs sha"
  mkdir -p "$P/docs/game-dev/adopted/S1" && printf 'carry\n' > "$P/docs/game-dev/adopted/S1/carry.md"
  redocs
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "the file in Docs passes"
}

test_lanes_check_unit_first() {
  lanes_fixture chu integration A:-
  printf -- '- 2026-10-01 check requested\n' >> "$P/.studio/ledger/A.md"
  redocs
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_eq "1 A-check progress,2 A-T1 progress,3 A-final-review progress,4 A-finish done," "$(story_rows A)" "a requested check is the story's first unit"
  assert_contains "$(last_lanes_dir)/events.jsonl" '"event":"unit_started","story":"A",.*"label":"check","model":"opus"' "the check unit runs on opus"
}

test_lanes_adopt_sync_fail_holds() {
  lanes_fixture asf integration S1:-
  lholds_on 120
  _x="$(git -C "$P" rev-parse origin/integration/demo)"
  adopt_docs S1
  printf -- '- 2026-10-01 T1 complete %s..%s\n' "$_x" "$_x" >> "$P/.studio/ledger/S1.md"
  redocs
  lanes_bg
  wait_for 'is_held S1' 60
  assert_contains "$(last_lanes_dir)/stories/S1" "^held stop: adopt sync — " "a failed sync holds the story"
  assert_contains "$TMP_WT/S1-b/.studio/ledger/S1.md" "Stop: adopt sync — T1: empty range" "the feature ledger names the sync's stderr line"
  assert_contains "$(last_lanes_dir)/events.jsonl" '"state":"held","why":"stop: adopt sync — ' "a held event"
  lverb stop
  wait_pid_or_fail "$RPID" 60 "the run ends"
  lholds_off
}

# #49: the preflight's scratch worktrees in $P (empty when none).
pf_wts() { git -C "$P" worktree list --porcelain | sed -n 's/^worktree //p' | grep '/setup-preflight-'; ls -d "$P"/.claude/worktrees/setup-preflight-* 2>/dev/null; }

test_lanes_setup_preflight_refuses_linked_only() {
  LANES_CONFIG='{"worktree_setup": "[ -d .git ]"}'; export LANES_CONFIG
  lanes_fixture pfr integration A:-
  assert_eq 0 "$( cd "$P" && [ -d .git ] && echo 0 || echo 1)" "the fixture's setup passes in the main checkout"
  run_lanes start "$MFP"
  assert_eq 2 "$LS_STATUS" "a setup that fails in a linked worktree refuses start"
  assert_contains "$LS_ERR" "worktree_setup: checking it once in a scratch linked worktree off origin/integration/demo before launch — up to 20 min" "the running line names the base and the cap"
  assert_contains "$LS_ERR" "worktree_setup failed in a linked worktree — exit 1 — log $P/.studio/reports/setup-preflight-[0-9-]*\.log" "the refusal names the exit and the log"
  _pl="$(sed -n 's/.* — log \(.*\.log\) — .*/\1/p' "$LS_ERR" | head -n 1)"
  assert_eq 1 "$([ -f "$_pl" ] && echo 1 || echo 0)" "the named log exists after the scratch worktree is gone"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
  assert_eq 0 "$(calls)" "no unit ran"
  assert_missing "$P/.studio/runs/demo/lock" "no run lock was taken"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
}
test_lanes_setup_preflight_pass_launches() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) [ -f .git ] && echo pf >> '"'$TMP/pf-ran'"';; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-ran"
  lanes_fixture pfp integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "a green preflight launches the run"
  assert_eq 1 "$(wc -l < "$TMP/pf-ran" | tr -d ' ')" "the setup ran once, in a linked worktree (.git is a file)"
  assert_contains "$LS_ERR" "worktree_setup: green in a linked worktree" "the green line"
  assert_contains "$(last_lanes_dir)/report.md" "^Ending: done$" "the run ends done"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
}
test_lanes_setup_preflight_unset_silent() {
  lanes_fixture pfu integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run ends done"
  assert_not_contains "$LS_ERR" "worktree_setup" "unset: no preflight line"
  assert_eq "" "$(pf_wts)" "none at all"
}
test_lanes_setup_preflight_dry_run_skips() {
  LANES_CONFIG='{"worktree_setup": "[ -d .git ]"}'; export LANES_CONFIG
  lanes_fixture pfd integration A:-
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "the dry run does not run the setup, so it passes"
  assert_contains "$LS_OUT" "^worktree_setup: start checks it once in a scratch linked worktree off origin/integration/demo before launch (up to 20 min); --dry-run does not run it$" "it says start will"
  assert_eq 0 "$(ls "$P"/.studio/reports/setup-* 2>/dev/null | wc -l | tr -d ' ')" "no setup log"
  assert_eq "" "$(pf_wts)" "no scratch worktree"
}
test_lanes_setup_preflight_interrupt_cleans() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) : > '"'$TMP/pf-int'"'; '"'$TMP/bin/msleep'"' 4831;; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-int"
  lanes_fixture pfi integration A:-
  lanes_bg
  wait_for "[ -f '$TMP/pf-int' ]" 60
  kill -TERM "$RPID"
  wait_pid_or_fail "$RPID" 20 "TERM during the check ends start promptly"
  assert_eq 2 "$WP_STATUS" "exit 2: nothing started"
  assert_contains "$TMP/lbg.err" "worktree_setup check interrupted — nothing started" "it says so"
  wait_for '[ -z "$(pgrep -f "$TMP/bin/msleep 4831\$")" ]' 1
  assert_eq 0 "$(pgrep -f "$TMP/bin/msleep 4831\$" | wc -l | tr -d ' ')" "the setup's processes are gone"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
  assert_eq 0 "$(calls)" "no unit ran"
}
test_lanes_setup_preflight_sweeps_stale() {
  LANES_CONFIG='{"worktree_setup": "true"}'; export LANES_CONFIG
  lanes_fixture pfs integration A:-
  mkdir -p "$P/.claude/worktrees"
  git -C "$P" worktree add -q --detach "$P/.claude/worktrees/setup-preflight-999999" HEAD
  printf '999999\n' > "$(git -C "$P/.claude/worktrees/setup-preflight-999999" rev-parse --absolute-git-dir)/studio-setup-preflight"
  # Not the preflight's (no marker): a story worktree that merely has the name.
  git -C "$P" worktree add -q -b setup-preflight-999998 "$P/.claude/worktrees/setup-preflight-999998" HEAD
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "a dead start's leftover does not block the next start"
  assert_missing "$P/.claude/worktrees/setup-preflight-999999" "and it is swept"
  assert_eq "$P/.claude/worktrees/setup-preflight-999998" "$(git -C "$P" worktree list --porcelain | sed -n 's/^worktree //p' | grep '/setup-preflight-')" "a same-named tree without the marker is never swept"
  git -C "$P" worktree remove --force "$P/.claude/worktrees/setup-preflight-999998"
  assert_eq "" "$(pf_wts)" "nothing else is left"
}
# pf_target_config NAME JSON — commits JSON as .studio/config.json on
# origin/integration/demo of fixture NAME (the scratch tree's own config).
pf_target_config() {
  ( set -e; rm -rf "$TMP/pf-push"
    git clone -q -b integration/demo "$TMP/$1.git" "$TMP/pf-push"; cd "$TMP/pf-push"
    mkdir -p .studio && printf '%s\n' "$2" > .studio/config.json
    git add -f .studio/config.json && git commit -q -m cfg && git push -q origin HEAD:integration/demo
  ) >/dev/null 2>&1 || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "pf_target_config $1: setup failed"; }
  rm -rf "$TMP/pf-push"
}
test_lanes_setup_preflight_bad_config() {
  LANES_CONFIG='{"worktree_setup": "true"}'; export LANES_CONFIG
  lanes_fixture pfb integration A:-
  pf_target_config pfb '{"worktree_setup": "true", "worktree_setup_minutes": 0}'
  run_lanes start "$MFP"
  assert_eq 2 "$LS_STATUS" "studio-setup's exit 2 (bad config in the tree) refuses start"
  assert_contains "$LS_ERR" "^studio-overnight: worktree_setup check: studio-setup: worktree_setup_minutes must be an integer 1-120$" "the refusal relays studio-setup's line"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
  assert_eq 0 "$(calls)" "no unit ran"
  assert_missing "$P/.studio/runs/demo/lock" "no run lock was taken"
}
test_lanes_setup_preflight_timeout() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) '"'$TMP/bin/msleep'"' 4834;; esac"}'; export LANES_CONFIG
  lanes_fixture pft integration A:-
  STUDIO_SETUP_TIMEOUT_SECONDS=1; export STUDIO_SETUP_TIMEOUT_SECONDS
  run_lanes start "$MFP"
  unset STUDIO_SETUP_TIMEOUT_SECONDS
  assert_eq 2 "$LS_STATUS" "a setup that times out refuses start"
  assert_contains "$LS_ERR" "worktree_setup failed in a linked worktree — exit 124 (timed out after worktree_setup_minutes) — log $P/.studio/reports/setup-preflight-[0-9-]*\.log — " "the refusal names the timeout and the log"
  _pl="$(sed -n 's/.* — log \(.*\.log\) — .*/\1/p' "$LS_ERR" | head -n 1)"
  assert_eq 1 "$([ -f "$_pl" ] && echo 1 || echo 0)" "the named log exists after the scratch worktree is gone"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
  wait_for '[ -z "$(pgrep -f "$TMP/bin/msleep 4834\$")" ]' 20
  assert_eq "" "$(pgrep -f "$TMP/bin/msleep 4834\$")" "the timed-out command is gone"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
  assert_eq 0 "$(calls)" "no unit ran"
  pkill -f "$TMP/bin/msleep 4834\$" 2>/dev/null
}

test_lanes_setup_fail_holds() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) ;; *) exit 5;; esac"}'; export LANES_CONFIG
  lanes_fixture suf integration A:-
  lholds_on 120
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held stop: worktree setup failed — exit 5 — log .studio/reports/setup-" "a failed worktree_setup holds the story"
  lverb stop
  wait_pid_or_fail "$RPID" 60 "the run ends"
  lholds_off
}

test_lanes_setup_fail_final_red() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */integration-*) exit 4;; esac"}'; export LANES_CONFIG
  lanes_fixture sff integration A:-
  run_lanes start "$MFP"
  R="$(last_lanes_dir)/report.md"
  assert_contains "$R" "^Final PR: .* (red)$" "a failed final setup is a red final PR"
  assert_contains "$R" "^Final note: .*worktree setup failed — exit 4 — log " "the note names the setup"
  assert_missing "$(last_lanes_dir)/final-gate.log" "no gate ran"
  assert_missing "$P/.studio/runs/demo/gate" "no gate record, so a resume re-runs setup"
}

# A worktree_setup that kills studio-setup itself (a signal death: no stderr
# line) inside an integration or progress worktree. No double quote or
# backslash: studio-setup's config reader cannot decode them.
SETUP_KILL='case $(pwd -P) in */integration-*|*/progress-*) p=$$; while [ $p -gt 1 ]; do q=$(ps -o ppid= -p $p | tr -d " "); case $(ps -o command= -p $p) in sh?/*studio-setup) kill -9 $p;; esac; p=$q; done;; esac'
setup_kill_config() {
  printf '{%s"worktree_setup": "%s"}' "$1" "$(printf '%s' "$SETUP_KILL" | tr '"' "'")"
}
test_lanes_setup_silent_fail_final_red() {
  LANES_CONFIG="$(setup_kill_config '')"; export LANES_CONFIG; LANES_PROGRESS=1; export LANES_PROGRESS
  lanes_fixture ssf integration A:-
  use_gate "echo gate >> '$CALLS/final-gates'"
  run_lanes start "$MFP"
  use_gate true
  R="$(last_lanes_dir)/report.md"
  assert_eq 0 "$(final_gates)" "a setup killed by a signal: no gate runs"
  assert_contains "$R" "^Final PR: .* (red)$" "the final PR is red"
  assert_contains "$R" "^Final note: .*worktree setup failed — exit [0-9]" "the note names the status though stderr was empty"
  assert_missing "$P/.studio/runs/demo/gate" "no gate record"
  assert_not_contains "$GH/calls" "^pr create --draft .*--title demo: " "no green PR"
}

test_lanes_setup_fail_path_specials() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */integration-*) exit 4;; esac"}'; export LANES_CONFIG
  lanes_fixture 'sp#a&b' integration A:-
  use_gate "echo gate >> '$CALLS/final-gates'"
  run_lanes start "$MFP"
  use_gate true
  R="$(last_lanes_dir)/report.md"
  assert_eq 0 "$(final_gates)" "a failed setup: no gate runs (# and & in the path)"
  assert_contains "$R" "^Final PR: .* (red)$" "red"
  assert_contains "$R" "^Final note: .*worktree setup failed — exit 4 — log $P/.claude/worktrees/integration-demo/.studio/reports/setup-" "the note's log path is intact under the worktree"
}

test_lanes_direct_setup_fail_note() {
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>", "worktree_setup": "case $(pwd -P) in */progress-*) exit 6;; esac"}'; LANES_PROGRESS=1; export LANES_CONFIG LANES_PROGRESS
  lanes_fixture 'dps#a&b' direct A:-
  printf 'progress\n' > "$SCEN/progress"
  run_lanes start "$MFP"
  assert_eq 0 "$(prompt_calls '/game-dev:execute --progress' | grep -c .)" "a failed progress setup: no progress unit"
  assert_contains "$(last_lanes_dir)/report.md" "^Final note: .*worktree setup failed — exit 6 — log $P/.claude/worktrees/progress-demo/.studio/reports/setup-" "the note is intact"
  LANES_CONFIG="$(setup_kill_config '"merge_command": "scripts/merge.sh <pr>", ')"; export LANES_CONFIG; LANES_PROGRESS=1; export LANES_PROGRESS
  lanes_fixture dpsk direct A:-
  printf 'progress\n' > "$SCEN/progress"
  run_lanes start "$MFP"
  assert_eq 0 "$(prompt_calls '/game-dev:execute --progress' | grep -c .)" "a signalled progress setup: no progress unit"
  assert_contains "$(last_lanes_dir)/report.md" "^Final note: .*worktree setup failed — exit [0-9]" "the note is not empty"
}

test_lanes_gate_command_final() {
  LANES_CONFIG='{"gate_command": "echo gc >> '"'$TMP/calls-gcf/gc'"'; exit 0"}'; export LANES_CONFIG
  lanes_fixture gcf integration A:-
  run_lanes start "$MFP"
  assert_eq 1 "$(wc -l < "$CALLS/gc" 2>/dev/null | tr -d ' ')" "the final gate ran gate_command once"
  assert_contains "$(last_lanes_dir)/report.md" "^Final PR: .* (green)$" "and is green"
  LANES_CONFIG='{"gate_command": "echo gc >> '"'$TMP/calls-gcr/gc'"'; exit 2"}'; export LANES_CONFIG
  lanes_fixture gcr integration A:-
  printf 'noop\n' > "$SCEN/final-repair"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/final-gate.log" "gate_command exit 2 — log " "a red gate_command is a red final gate"
  assert_contains "$(last_lanes_dir)/report.md" "^Final PR: .* (red)$" "and a red PR"
}

test_lanes_gate_command_finish_red_repair() {
  LANES_CONFIG='{"gate_command": "exit 3", "overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture gcfr integration A:-
  printf 'auto\nauto\ngatecmd\nauto\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  run_lanes start "$MFP"
  assert_eq 1 "$(gate_calls)" "one gate-repair unit"
  n="$(gate_call)"; [ -n "$n" ] || n=0
  assert_contains "$CALLS/$n.env" "^STUDIO_REPAIR=gate:/.*/A-b/\.studio/reports/gate-[0-9-]*\.log$" "the repair reads the Stop's own log"
}

test_lanes_report_adopted_lines() {
  lanes_fixture rad integration A:- B:- C:-
  adopt_docs A; adopt_docs B
  redocs
  printf 'auto\nstop broke\n' > "$SCEN/B"
  run_lanes start "$MFP"
  R="$(last_lanes_dir)/report.md"
  assert_contains "$R" "^Adopted from docs/game-dev/plans/2026-10-01-A.md; landed on integration/demo — continue dependent stories from there$" "a landed adopted story"
  assert_contains "$R" "^Adopted from docs/game-dev/plans/2026-10-01-B.md\. To continue the standard way: cd '.*' && '.*/studio-adopt' sync B$" "a stopped adopted story"
  assert_eq 2 "$(grep -c '^Adopted from ' "$R")" "a story that was not adopted has no line"
}

# ---- #39 T7: per-run locks, run identity and the status loop ----
test_lanes_per_run_lock_paths() {
  lanes_fixture perrun integration A:-
  printf 'waitexist %s\n' "$SCEN/release-prl" > "$SCEN/A"
  bg_lanes pr "$P" start "$MFP"
  _i=0; while [ ! -f "$P/.studio/runs/demo/lock" ] && [ "$_i" -lt 600 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_file "$P/.studio/runs/demo/lock" "the manifest run's lock is .studio/runs/<slug>/lock"
  assert_contains "$P/.studio/runs/demo/lock" "^start=$P\$" "it records the start dir"
  assert_missing "$P/.studio/overnight.lock" "no project-wide lock"
  ( cd "$P" && sh "$RUNNER" stop ) > "$TMP/out" 2>&1
  assert_file "$P/.studio/runs/demo/stop" "bare stop with one live run writes its own flag"
  : > "$SCEN/release-prl"   # the unit is held on this file, not the flag, so the flag outlives the assert
  bg_wait pr
  assert_missing "$P/.studio/runs/demo/lock" "unlocked at the end"
  assert_missing "$P/.studio/runs/demo/stop" "and its stop flag removed"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_excludes_before_lock() {
  lanes_fixture excl integration A:-
  _ex="$(git -C "$P" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  STUDIO_OVERNIGHT_LOCK_HOOK="cp '$_ex' '$TMP/excl.at-lock'"; export STUDIO_OVERNIGHT_LOCK_HOOK
  run_lanes start "$MFP"; unset STUDIO_OVERNIGHT_LOCK_HOOK
  for _e in .studio/runs/ .studio/sessions/ .studio/runs.mutex .studio/sessions.mutex .studio/runs.mutex.reap/ .studio/sessions.mutex.reap/ .studio/overnight.lock .studio/overnight.stop .claude/worktrees/; do
    assert_contains "$TMP/excl.at-lock" "^$(printf '%s' "$_e" | sed 's/\./\\./g')\$" "$_e excluded before the lock (D6)"
  done
}
test_lanes_two_runs_each_own_lock() {
  lanes_fixture two integration A:-
  lanes_add_run alpha integration S1:-
  printf 'waitexist %s\n' "$SCEN/release-two" > "$SCEN/A"; printf 'waitexist %s\n' "$SCEN/release-two" > "$SCEN/S1"
  bg_lanes demo "$P" start "$MFP"; bg_lanes alpha "$RW" start "$RMF"
  # Both preflights run at once: wait for both locks (a ceiling of a minute), not a fixed sleep.
  _i=0; while { [ ! -f "$P/.studio/runs/demo/lock" ] || [ ! -f "$P/.studio/runs/alpha/lock" ]; } && [ "$_i" -lt 600 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_file "$P/.studio/runs/demo/lock" "demo holds its lock"
  assert_file "$P/.studio/runs/alpha/lock" "alpha holds its own"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1; _st=$?
  assert_eq 0 "$_st" "status exits 0 with runs live"
  assert_contains "$TMP/st.out" '^== alpha (manifest, pid [0-9]*) — ' "a headed block per run (D16)"
  assert_contains "$TMP/st.out" '^== demo (manifest, pid [0-9]*) — ' "both"
  ( cd "$P" && sh "$RUNNER" status --run alpha ) > "$TMP/st1.out" 2>&1
  assert_not_contains "$TMP/st1.out" '^== ' "status --run prints one block, no header"
  assert_contains "$TMP/st1.out" "run: .*overnight-alpha-" "alpha's block"
  : > "$SCEN/release-two"
  bg_wait demo; bg_wait alpha
  assert_eq 0 "$BG_STATUS" "alpha ran to its end beside demo"
  assert_contains "$P/.studio/runs/alpha/landed.tsv" '^S1	' "and landed S1"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_status_run_not_live() {
  lanes_fixture nolive integration A:-
  ( cd "$P" && sh "$RUNNER" status --run ghost ) > "$TMP/out" 2>&1; _st=$?
  assert_eq 1 "$_st" "status --run <slug> exits 1 when that run is not live"
  assert_contains "$TMP/out" '^no live run ghost$' "the fixed text"
}
test_lanes_manifest_refuses_live_single() {
  lanes_fixture msingle integration A:-
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T21:00:00Z\n' "$_d" "$P/.studio/reports/overnight-20261004-210000" > "$P/.studio/overnight.lock"
  run_lanes start "$MFP"
  kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$P/.studio/overnight.lock"
  assert_eq 2 "$LS_STATUS" "a manifest start refuses while a single-plan run is live (AC5)"
  assert_contains "$LS_ERR" "a run is live" "names it"
}
test_lanes_lock_race_single_vs_manifest() {
  lanes_fixture race integration A:-
  printf 'sleep 2\n' > "$SCEN/A"
  STUDIO_OVERNIGHT_LOCK_HOOK='sleep 2'; export STUDIO_OVERNIGHT_LOCK_HOOK
  bg_lanes m "$P" start "$MFP"; unset STUDIO_OVERNIGHT_LOCK_HOOK
  sleep 0.5
  # The single-plan start passed its preflight before the manifest run locked; the re-check catches it.
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T21:00:00Z\n' "$_d" "$P/.studio/reports/overnight-20261004-210000" > "$P/.studio/overnight.lock"
  bg_wait m; kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$P/.studio/overnight.lock"
  assert_eq 2 "$BG_STATUS" "the manifest start that re-checks after a single-plan lock appears loses"
  assert_missing "$P/.studio/runs/demo/lock" "the loser leaves no lock"
  assert_eq "" "$(ls -d "$P"/.studio/reports/overnight-demo-* 2>/dev/null)" "and no run dir"
}
test_lanes_reg_write_keeps_live_sibling() {
  lanes_fixture reg integration A:-
  mkdir -p "$HOME/.claude-gamedev/runs"
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'root=%s\nstart=%s\nrun=/x/overnight-sib\npid=%s\n' "$P" "$P" "$_d" > "$HOME/.claude-gamedev/runs/overnight-sib-$_d"
  printf 'root=%s\nstart=%s\nrun=/x/overnight-dead\npid=999999\n' "$P" "$P" > "$HOME/.claude-gamedev/runs/overnight-dead-999999"
  run_lanes start "$MFP"
  assert_file "$HOME/.claude-gamedev/runs/overnight-sib-$_d" "a live sibling's entry is kept (AC6)"
  assert_missing "$HOME/.claude-gamedev/runs/overnight-dead-999999" "a dead one is dropped"
  kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$HOME"/.claude-gamedev/runs/overnight-sib-*
}
test_lanes_detach_with_other_run_live() {
  lanes_fixture det integration A:-
  lanes_add_run alpha integration S1:-
  printf 'hang\n' > "$SCEN/S1"; bg_lanes alpha "$RW" start "$RMF"
  _i=0; while [ ! -f "$P/.studio/runs/alpha/lock" ] && [ "$_i" -lt 600 ]; do sleep 0.1; _i=$((_i + 1)); done
  _ap="$(sed -n 's/^pid=//p' "$P/.studio/runs/alpha/lock")"
  printf 'hang\n' > "$SCEN/A"
  run_lanes start --detach "$MFP"
  assert_eq 0 "$LS_STATUS" "detach succeeds with another run live (waits on its own lock and status --run)"
  assert_contains "$LS_OUT" "^detached: pid " "detached"
  assert_eq "pid=$_ap" "$(grep '^pid=' "$P/.studio/runs/alpha/lock" 2>/dev/null)" "alpha still holds its lock when detach returns"
  # Stop demo by name: alpha is untouched and stays live.
  ( cd "$P" && sh "$RUNNER" stop --run demo ) > /dev/null 2>&1
  assert_file "$P/.studio/runs/demo/stop" "stop --run demo writes demo's flag"
  assert_missing "$P/.studio/runs/alpha/stop" "and not alpha's"
  assert_eq "pid=$_ap" "$(grep '^pid=' "$P/.studio/runs/alpha/lock" 2>/dev/null)" "alpha still holds its lock after demo's stop"
  assert_eq 1 "$(pid_alive "$_ap" && echo 1 || echo 0)" "and alpha's runner is still live"
  # Then end both: stop alpha, end the hung stubs, wait both runs out.
  ( cd "$P" && sh "$RUNNER" stop --run alpha ) > /dev/null 2>&1; pkill -f "$TMP/fakebin/claude" 2>/dev/null
  detach_stop; bg_wait alpha
}
# Two starts of one slug share its lock path: a second start while the first
# is live refuses (exit 2, naming it) and never reclaims, rewrites or removes
# the live run's lock, stop flag or run dir.
test_lanes_same_slug_live_refused() {
  lanes_fixture same integration A:-
  printf 'hang\n' > "$SCEN/A"
  bg_lanes first "$P" start "$MFP"
  wait_for "[ -f '$CALLS/1.story' ]" 60
  _lp="$(sed -n 's/^pid=//p' "$P/.studio/runs/demo/lock")"
  _ld="$(ls -d "$P"/.studio/reports/overnight-demo-[0-9]* 2>/dev/null)"
  printf 'operator stop\n' > "$P/.studio/runs/demo/stop"   # the run stays live until its hung unit ends
  run_lanes start "$MFP"
  assert_eq 2 "$LS_STATUS" "a second start of a live slug exits 2"
  assert_contains "$LS_ERR" "slug demo is used by live run demo (.*pid $_lp)" "and names the live run and its pid"
  assert_not_contains "$LS_ERR" "reclaiming stale lock" "it never treats the live lock as stale"
  assert_contains "$P/.studio/runs/demo/lock" "^pid=$_lp\$" "the live run's lock is unchanged"
  assert_contains "$P/.studio/runs/demo/stop" "^operator stop\$" "its stop flag is left alone"
  assert_eq "$_ld" "$(ls -d "$P"/.studio/reports/overnight-demo-[0-9]* 2>/dev/null)" "no second run dir"
  assert_eq 1 "$([ -d "$_ld" ] && echo 1 || echo 0)" "the live run's dir is kept"
  pkill -f "$TMP/fakebin/claude" 2>/dev/null
  bg_wait first
}
test_lanes_units_get_start_dir() {
  lanes_fixture sdenv integration A:-
  lanes_add_run alpha integration S1:-
  run_lanes_in "$RW" start "$RMF"
  _n="$(grep -l '^S1$' "$CALLS"/*.story | head -n 1)"; _n="${_n%.story}"
  assert_contains "$_n.fullenv" "^STUDIO_START_DIR=$RW\$" "every unit gets STUDIO_START_DIR (AC30)"
}
test_lanes_reap_resume_line_run_worktree() {
  lanes_fixture reap integration A:-
  lanes_add_run alpha integration S1:-
  printf 'hang\n' > "$SCEN/S1"; bg_lanes alpha "$RW" start "$RMF"
  # Wait for the hung unit (its session is running), not a fixed sleep.
  _i=0; while [ ! -f "$CALLS/1.story" ] && [ "$_i" -lt 600 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_file "$CALLS/1.story" "the hung unit's session started"
  _rp="$(sed -n 's/^pid=//p' "$P/.studio/runs/alpha/lock")"
  pkill -KILL -P "$_rp" 2>/dev/null; kill -KILL "$_rp"; bg_wait alpha
  # The hung stub runs in its own process group: end it by its path.
  pkill -KILL -f "$TMP/fakebin/claude" 2>/dev/null
  wait_for '[ -z "$(pgrep -f "$TMP/fakebin/claude")" ]' 60
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/out" 2>&1
  _rd="$(ls -d "$P"/.studio/reports/overnight-alpha-* | tail -n 1)"
  assert_file "$_rd/report.md" "status from the main checkout reaped the dead run"
  assert_contains "$_rd/report.md" "^cd '$RW' && " "its Resume line changes into the run worktree (AC7)"
}
test_lanes_old_lock_counts_live() {
  lanes_fixture oldlive integration A:-
  _od="$P/.studio/reports/overnight-old-20261003-210000"; mkdir -p "$_od"; printf '# Run: old\n' > "$_od/manifest.md"
  sh -c 'sleep 30; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'pid=%s\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$_d" "$_od" > "$P/.studio/overnight.lock"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/out" 2>&1; _st=$?
  kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$P/.studio/overnight.lock"
  assert_eq 0 "$_st" "an old-style manifest run on overnight.lock is live (AC31)"
}
test_lanes_old_lock_reaped_by_start() {
  lanes_fixture oldreap integration A:-
  _od="$P/.studio/reports/overnight-old-20261003-210000"; mkdir -p "$_od/stories" "$_od/lanes"
  printf '# Run: old\n\nMode: integration\nTarget: integration/old\n' > "$_od/manifest.md"; : > "$_od/rows.tsv"; : > "$_od/chains"
  printf 'pid=999999\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$_od" > "$P/.studio/overnight.lock"
  run_lanes start "$MFP"
  assert_file "$_od/report.md" "start reaps a dead old-style manifest lock (AC31)"
  assert_eq 0 "$LS_STATUS" "and runs"
}

# ---- #39 T11: the manifest preflight — conflicts, re-check, overlap, next ----
# live_alpha NAME — lanes_fixture NAME (demo, story A) with alpha (S1) added and
# live: its S1 unit hangs. end_alpha stops it and ends its stub by temp path.
live_alpha() {
  lanes_fixture "$1" integration A:-
  lanes_add_run alpha integration S1:-
  printf 'hang\n' > "$SCEN/S1"
  bg_lanes alpha "$RW" start "$RMF"
  wait_for "[ -f '$CALLS/1.story' ]" 60
}
end_alpha() {
  ( cd "$P" && sh "$RUNNER" stop --run alpha ) > /dev/null 2>&1
  pkill -f "$TMP/fakebin/claude" 2>/dev/null
  bg_wait alpha
}
test_lanes_preflight_refuses_live_slug_id_branch() {
  live_alpha pfl
  _ad="$(ls -d "$P"/.studio/reports/overnight-alpha-[0-9]* | tail -n 1)"
  sed 's/S1/X1/g' "$RW/$RMF" > "$RW/docs/runs/m1.md"
  sed -e 's/^# Run: alpha/# Run: beta/' -e 's/S1-b/X1-b/g' "$RW/$RMF" > "$RW/docs/runs/m2.md"
  sed -e 's/^# Run: alpha/# Run: beta/' -e 's/| S1 | S1-b | S1 |/| X1 | S1-b | X1 |/' "$RW/$RMF" > "$RW/docs/runs/m3.md"
  for _m in m1:slug:alpha m2:story:S1 m3:branch:S1-b; do
    _f="${_m%%:*}"; _w="${_m#*:}"; _k="${_w%%:*}"; _v="${_w#*:}"
    run_lanes_in "$RW" start --dry-run "docs/runs/$_f.md"
    assert_eq 2 "$LS_STATUS" "$_f: a $_k shared with a live run refuses"
    assert_contains "$LS_ERR" "$_k $_v is used by live run alpha ($_ad, pid [0-9]*)" "$_f: names the run and its dir"
    assert_contains "$LS_ERR" "stop it ('.*studio-overnight' stop --run alpha) or pick another" "$_f: and the way out"
  done
  end_alpha
}
test_lanes_preflight_refuses_live_old_style_run() {
  lanes_fixture pfold integration A:-
  _od="$P/.studio/reports/overnight-old-20261003-210000"; mkdir -p "$_od"
  printf '# Run: old\n\nMode: integration\nTarget: integration/old\n' > "$_od/manifest.md"
  printf 'A\tA-b\tA\t-\t-\t\n' > "$_od/rows.tsv"
  sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & _d=$!
  printf 'pid=%s\nrun=%s\nstarted=2026-10-03T21:00:00Z\nstart=%s\n' "$_d" "$_od" "$P" > "$P/.studio/overnight.lock"
  run_lanes start --dry-run "$MFP"
  _st="$LS_STATUS"; _er="$TMP/pfold1.err"; cp "$LS_ERR" "$_er"
  sed 's/^# Run: demo/# Run: old/' "$P/$MFP" > "$P/docs/runs/os.md"
  run_lanes start --dry-run docs/runs/os.md
  _st2="$LS_STATUS"; _er2="$LS_ERR"
  kill "$_d"; wait "$_d" 2>/dev/null; rm -f "$P/.studio/overnight.lock"
  assert_eq 2 "$_st" "a story shared with a live old-style run refuses (AC8, AC31)"
  assert_contains "$_er" "story A is used by live run old ($_od, pid $_d)" "names the old-style run"
  assert_eq 2 "$_st2" "a slug shared with a live old-style run refuses"
  assert_contains "$_er2" "slug old is used by live run old" "names the slug"
}
# A live lock with no start= line gives runs_live an empty start_dir column;
# mf_conflicts must still read the lock path (field 7) and skip its own lock
# in the re-check, and still name the other run (#39 final review, known #2).
test_lanes_conflicts_lock_without_start() {
  _cs_p="$TMP/cs"; mkdir -p "$_cs_p/.studio/runs/demo" "$_cs_p/.studio/runs/alpha"
  sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & _cs_d=$!
  for _cs_s in demo alpha; do
    _cs_r="$_cs_p/.studio/reports/overnight-$_cs_s-20261004-210000"; mkdir -p "$_cs_r"
    printf '# Run: %s\n\nMode: integration\nTarget: integration/%s\n' "$_cs_s" "$_cs_s" > "$_cs_r/manifest.md"
    printf 'pid=%s\nrun=%s\nstarted=2026-10-04T21:00:0%s\n' "$_cs_d" "$_cs_r" "${#_cs_s}" > "$_cs_p/.studio/runs/$_cs_s/lock"
  done
  printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$_cs_p/.studio/reports/overnight-demo-20261004-210000/rows.tsv"
  printf 'S9\tS9-b\tS9\t-\t-\t\n' > "$_cs_p/.studio/reports/overnight-alpha-20261004-210000/rows.tsv"
  _cs_out="$( (
    SELF_DIR="$BIN"; STATE_ROOT="$_cs_p"; SELF_ABS="$BIN/studio-overnight"; MF_SLUG=demo
    MF_ROWS="$_cs_p/.studio/reports/overnight-demo-20261004-210000/rows.tsv"; LOCK="$_cs_p/.studio/runs/demo/lock"
    sq() { printf "'%s'" "$1"; }
    . "$BIN/overnight-runs.sh"; . "$BIN/overnight-lanes.sh"
    printf 'recheck:\n'; mf_conflicts 1
    printf 'S9\tS9-b\tS9\t-\t-\t\n' >> "$MF_ROWS"; printf 'other:\n'; mf_conflicts 1
  ) 2>&1)"
  kill "$_cs_d"; wait "$_cs_d" 2>/dev/null
  assert_eq "recheck:
other:
story S9 is used by live run alpha ($_cs_p/.studio/reports/overnight-alpha-20261004-210000, pid $_cs_d) — stop it ('$BIN/studio-overnight' stop --run alpha) or pick another id
branch S9-b is used by live run alpha ($_cs_p/.studio/reports/overnight-alpha-20261004-210000, pid $_cs_d) — stop it ('$BIN/studio-overnight' stop --run alpha) or pick another branch" \
    "$_cs_out" "its own start=-less lock is skipped; the other run is named with its pid"
}
test_lanes_preflight_refuses_stopped_record() {
  lanes_fixture pfs integration S1:-
  mkdir -p "$P/.studio/runs/alpha" "$P/.studio/reports/overnight-alpha-20261004-210000"
  : > "$P/.studio/runs/alpha/landed.tsv"
  printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$P/.studio/reports/overnight-alpha-20261004-210000/rows.tsv"
  printf 'docs/runs/alpha-real.md\n' > "$P/.studio/reports/overnight-alpha-20261004-210000/manifest.path"
  mkdir -p "$P/.studio/reports/overnight-alpha-20261003-210000"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a story of a stopped run's record refuses"
  assert_contains "$LS_ERR" "story S1 is used by stopped run alpha (record $P/.studio/runs/alpha, report $P/.studio/reports/overnight-alpha-20261004-210000) — resume it" "names the run, its record and its newest report"
  assert_contains "$LS_ERR" "— resume it ('.*' start docs/runs/alpha-real.md) or abandon it (mv '$P/.studio/runs/alpha' '$P/.studio/runs/alpha'.<utc ts>: a story carried into a new run keeps its id and its branch) or pick another id" "the way out: resume with the real manifest path, or abandon by archiving the record (AC8)"
  assert_contains "$LS_ERR" "branch S1-b is used by stopped run alpha" "and its branch"
  : > "$P/.studio/runs/alpha/done"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "a done record's S1 on this story's branch S1-b: the same story carried over (#56 FI1)"
  printf 'S1\told-b\tS1\t-\t-\t\n' > "$P/.studio/reports/overnight-alpha-20261004-210000/rows.tsv"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a done record still lists S1 on another branch (#56 rule 3)"
  assert_not_contains "$LS_ERR" "is used by stopped run alpha" "it is no longer a stopped-run conflict (AC8)"
  assert_contains "$LS_ERR" "story id 'S1' is taken: run alpha (record \.studio/runs/alpha) lists it" "check-id's record rule names it"
}
test_lanes_preflight_done_record_needs_archive() {
  lanes_fixture pfd integration A:-
  mkdir -p "$P/.studio/runs/demo"; : > "$P/.studio/runs/demo/landed.tsv"; : > "$P/.studio/runs/demo/done"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a new run named like a done record refuses"
  assert_contains "$LS_ERR" "run demo is done: archive its record first: mv '$P/.studio/runs/demo' '$P/.studio/runs/demo'\.<utc ts> (its story ids stay taken: a story carried into the new run keeps its id and its branch)" "names the archive path"
  mv "$P/.studio/runs/demo" "$P/.studio/runs/demo.20261004T000000Z"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "after the archive it passes"
  # A post-#56 done record keeps rows.tsv: archived, its ids stay taken by
  # rule 3 unless the row is this story's, carried over on the same branch.
  mkdir -p "$P/.studio/runs/demo"; : > "$P/.studio/runs/demo/landed.tsv"; : > "$P/.studio/runs/demo/done"
  printf 'A\tA-b\tA\t-\t-\t\n' > "$P/.studio/runs/demo/rows.tsv"
  rm -rf "$P/.studio/runs/demo.20261004T000000Z"; mv "$P/.studio/runs/demo" "$P/.studio/runs/demo.20261005T000000Z"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "an archived record with rows.tsv: A on A-b again is the same story carried over"
  printf 'A\told-b\tA\t-\t-\t\n' > "$P/.studio/runs/demo.20261005T000000Z/rows.tsv"
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "A on another branch in the archived record: taken"
  assert_contains "$LS_ERR" "story id 'A' is taken: run demo (record \.studio/runs/demo\.20261005T000000Z) lists it" "names the archived record"
}
test_lanes_preflight_branch_forms() {
  lanes_fixture pfb integration A:-
  for _b in run/x integration-x progress/y; do
    sed "s#| A | A-b |#| A | $_b |#" "$P/$MFP" > "$P/docs/runs/bf.md"
    run_lanes start --dry-run docs/runs/bf.md
    assert_eq 2 "$LS_STATUS" "branch $_b refuses"
    assert_contains "$LS_ERR" "branch $_b collides" "branch $_b names its form"
  done
  live_alpha pfb2
  sed 's#| A | A-b |#| A | integration/alpha |#' "$P/$MFP" > "$P/docs/runs/bf.md"
  run_lanes start --dry-run docs/runs/bf.md
  assert_eq 2 "$LS_STATUS" "a live run's Target as a branch refuses"
  assert_contains "$LS_ERR" "branch integration/alpha is the Target of live run alpha" "names it"
  end_alpha
}
test_lanes_preflight_slug_off_and_digits() {
  lanes_fixture pfo integration A:-
  sed 's/^# Run: demo/# Run: off/' "$P/$MFP" > "$P/docs/runs/off.md"
  run_lanes start --dry-run docs/runs/off.md
  assert_eq 2 "$LS_STATUS" "slug off refuses"
  assert_contains "$LS_ERR" "slug off is reserved (/omega:autopilot off)" "reserved"
  sed 's/^# Run: demo/# Run: 123/' "$P/$MFP" > "$P/docs/runs/num.md"
  run_lanes start --dry-run docs/runs/num.md
  assert_eq 2 "$LS_STATUS" "an all-digit slug refuses"
  assert_contains "$LS_ERR" "slug 123 is all digits" "reads as a story id"
}
test_lanes_preflight_resume_own_record() {
  lanes_fixture pfr integration A:-
  mkdir -p "$P/.studio/runs/demo"; : > "$P/.studio/runs/demo/landed.tsv"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "a stopped run's own record (no done) is a resume"
}
# ---- #56: story ids are checked by next and start ----
test_lanes_ids_next_refuses_stale() {               # spec test 9
  lanes_pre_stale "$TMP/pre-nis"
  LANES_MAIN_PRE="$TMP/pre-nis"; LANES_CELLS=dash; export LANES_MAIN_PRE LANES_CELLS
  lanes_fixture nis integration S1:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n' > "$P/.studio/ledger/demo.md"
  ( cd "$P" && git rm -q docs/game-dev/plans/2026-10-01-S1.md && git commit -qm "own plan not written yet" ) >/dev/null 2>&1
  assert_eq "$OLD_PLAN" "$(cd "$P" && grep -rlxF 'Story: S1' docs/game-dev/plans)" "the header search alone finds exactly the old plan"
  run_lanes next "$MFP"
  assert_eq 2 "$LS_STATUS" "next refuses the stale id"
  assert_contains "$LS_ERR" "^studio-overnight: story id 'S1' is taken: origin/main:\.studio/ledger/S1\.md belongs to another story (plan $OLD_PLAN, shipped KAN-1499-mob-composer)\$" "with check-id's message"
  assert_not_contains "$LS_OUT" "^S1  " "before the row is classified"
  assert_not_contains "$LS_OUT" "^next: " "and no next command"
}
test_lanes_ids_start_refuses_stale() {              # spec test 10
  lanes_pre_stale "$TMP/pre-sis"
  LANES_MAIN_PRE="$TMP/pre-sis"; export LANES_MAIN_PRE
  lanes_fixture sis integration S1:-
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "start --dry-run refuses a row reusing the stale S1"
  assert_contains "$LS_ERR" "story id 'S1' is taken: origin/main:\.studio/ledger/S1\.md belongs to another story" "the ledger reason"
  assert_contains "$LS_ERR" "story id 'S1' is taken: origin/main:$OLD_PLAN says 'Story: S1'" "the plan reason"
  assert_eq 0 "$(calls)" "no unit ran"
}
test_lanes_ids_ticket_id_seeds_clean() {            # spec test 11
  lanes_pre_stale "$TMP/pre-tis"
  LANES_MAIN_PRE="$TMP/pre-tis"; LANES_TASKS=2; export LANES_MAIN_PRE LANES_TASKS
  lanes_fixture tis integration KAN-1541:-
  run_lanes check-id KAN-1541
  assert_eq 0 "$LS_STATUS" "KAN-1541 is free beside the stale S1"
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next classifies it"
  assert_contains "$LS_OUT" "^KAN-1541  " "its row"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "start --dry-run passes"
  assert_eq "check: task rebuilt to 0/2 from the ledger" \
    "$(cd "$P" && STUDIO_STORY=KAN-1541 sh "$STATE_BIN" check --rebuild 2>&1 | tail -n 1)" "it seeds at task 0 of 2"
  # The fixture seeded KAN-1541 (task 0/2, no T lines). S1 seeded the same way
  # (tests/state_pointer_test.sh's pattern) reads the inherited S1.md's T1-T2.
  assert_eq "check: task rebuilt to 2/2 from the ledger" \
    "$(cd "$P" && STUDIO_STORY=S1 sh "$STATE_BIN" init >/dev/null 2>&1 \
       && STUDIO_STORY=S1 sh "$STATE_BIN" set task 0/2 \
       && STUDIO_STORY=S1 sh "$STATE_BIN" check --rebuild 2>&1 | tail -n 1)" "the hazard it avoids: S1 on the same tree rebuilds to 2 of 2"
}
test_lanes_ids_slug_id_plans_clean() {              # spec test 12
  lanes_pre_stale "$TMP/pre-sid"
  LANES_MAIN_PRE="$TMP/pre-sid"; LANES_CELLS=dash; export LANES_MAIN_PRE LANES_CELLS
  lanes_fixture sid integration demo-S1:-
  printf -- '- 2026-10-01 spec approved docs/game-dev/specs/2026-10-01-demo.md\n- 2026-10-01 plan approved docs/game-dev/plans/2026-10-01-demo-S1.md\n- 2026-10-01 Decisions swept demo-S1\n' > "$P/.studio/ledger/demo.md"
  run_lanes check-id demo-S1
  assert_eq 0 "$LS_STATUS" "a <slug>-S<n> id is free beside the stale S1"
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "next passes"
  assert_contains "$LS_OUT" "^demo-S1  planned  spec=docs/game-dev/specs/2026-10-01-demo.md  plan=docs/game-dev/plans/2026-10-01-demo-S1.md\$" "and plans it from its own plan"
}
test_lanes_ids_own_adopted_dry_run() {              # spec test 5
  _oa=docs/game-dev/plans/2026-10-01-S1.md; _oo=docs/superpowers/plans/2026-09-01-demo.md
  mkdir -p "$TMP/pre-oal/.studio/ledger" "$TMP/pre-oal/docs/game-dev/plans"
  printf -- '- 2026-09-30 source %s spec -\n- 2026-09-30 adopted %s -> %s\n- 2026-10-01 shipped S1-b\n' "$_oo" "$_oo" "$_oa" > "$TMP/pre-oal/.studio/ledger/S1.md"
  printf '# Plan\n\nStory: S1\n' > "$TMP/pre-oal/$_oa"
  LANES_MAIN_PRE="$TMP/pre-oal"; export LANES_MAIN_PRE
  lanes_fixture oal integration S1:-
  run_lanes check-id S1
  assert_eq 0 "$LS_STATUS" "a landed adopted ledger for the row's own plan is the story's own"
  run_lanes start --dry-run "$MFP"
  assert_eq 0 "$LS_STATUS" "start --dry-run passes"
}
test_lanes_ids_direct_resume_after_landing() {      # Review Focus 1
  LANES_CONFIG='{"merge_command": "scripts/merge.sh <pr>"}'; export LANES_CONFIG
  lanes_fixture idr direct A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "A lands on main"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(git -C "$P" ls-tree --name-only origin/main -- .studio/ledger/ | grep -c '/A\.md$')" "A's ledger is on main now"
  rm -f "$P/.studio/runs/demo/done"   # a stopped record of this run: a resume
  run_lanes check-id A
  assert_eq 0 "$LS_STATUS" "its own landed ledger does not make A taken"
  run_lanes start --dry-run "$MFP"
  assert_not_contains "$LS_ERR" "is taken" "a resume after landing is not refused for its own id"
}
test_lanes_ids_record_keeps_rows() {                # D2
  lanes_fixture rkr integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  assert_file "$P/.studio/runs/demo/rows.tsv" "the record keeps the run's rows"
  assert_contains "$P/.studio/runs/demo/rows.tsv" "^A	A-b	" "A's row"
  rm -rf "$P"/.studio/reports/overnight-demo-*   # no report fallback: the record's copy alone
  run_lanes check-id A --slug other --plan - --branch -
  assert_contains "$LS_ERR" "story id 'A' is taken: run demo (record \.studio/runs/demo) lists it" "check-id reads it"
}
test_lanes_ids_record_rows_union() {                # review M3
  lanes_fixture rru integration A:- B:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "the run is done"
  rm -f "$P/.studio/runs/demo/done"   # a stopped record of this run: a resume
  grep -v '^| B |' "$P/$MFP" > "$TMP/m" && mv "$TMP/m" "$P/$MFP"
  ( cd "$P" && git add -A && git commit -qm "drop B" && git push -q origin run/demo ) >/dev/null 2>&1
  run_lanes start "$MFP"
  assert_contains "$P/.studio/runs/demo/rows.tsv" "^A	A-b	" "A's row"
  assert_contains "$P/.studio/runs/demo/rows.tsv" "^B	B-b	" "a story dropped from the manifest keeps its row"
  assert_eq 1 "$(grep -c '^A	' "$P/.studio/runs/demo/rows.tsv")" "one row per id"
  assert_eq "" "$(ls "$P/.studio/runs/demo" | grep 'rows\.tsv\.')" "no tmp file left"
}
test_lanes_ids_next_needs_origin_head() {           # D8
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nho integration A:-
  git -C "$P" remote set-head origin -d
  run_lanes next "$MFP"
  assert_eq 2 "$LS_STATUS" "next with origin/HEAD unset exits 2"
  assert_contains "$LS_ERR" "origin/HEAD is not set — run: git remote set-head origin --auto" "with start's message"
  assert_not_contains "$LS_OUT" "^A  " "before classifying anything"
}
test_lanes_ids_next_carried_over() {                # #56 FI1
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nco integration A:-
  mkdir -p "$P/.studio/runs/old.20261001T000000Z"; printf 'A\tA-b\tA\t-\t-\t\n' > "$P/.studio/runs/old.20261001T000000Z/rows.tsv"
  run_lanes next "$MFP"
  assert_eq 0 "$LS_STATUS" "a story carried over from an archived run on its own branch keeps its id"
  assert_contains "$LS_OUT" "^A  " "next classifies it"
  printf 'A\told-b\tA\t-\t-\t\n' > "$P/.studio/runs/old.20261001T000000Z/rows.tsv"
  run_lanes next "$MFP"
  assert_eq 2 "$LS_STATUS" "the same id on another branch: taken"
  assert_contains "$LS_ERR" "story id 'A' is taken: run old (record \.studio/runs/old\.20261001T000000Z) lists it" "names the record"
}
test_lanes_ids_start_needs_default_ref() {          # review m-A
  lanes_pre_stale "$TMP/pre-sdr"
  LANES_MAIN_PRE="$TMP/pre-sdr"; export LANES_MAIN_PRE
  lanes_fixture sdr integration S1:-
  git -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/nope
  run_lanes start --dry-run "$MFP"
  assert_eq 2 "$LS_STATUS" "a dangling origin/HEAD refuses"
  assert_contains "$LS_ERR" "origin/HEAD is not set — run: git remote set-head origin --auto" "with the origin/HEAD message"
}
test_lanes_ids_empty_cell_no_shift() {              # review m-2
  lanes_fixture ecs integration A:-
  sed 's#^| A | A-b | A | \([^|]*\) | [^|]* |#| A | A-b | KAN-1 | \1 |  |#' "$P/$MFP" > "$P/docs/runs/ec.md"
  assert_contains "$P/docs/runs/ec.md" "^| A | A-b | KAN-1 | docs/game-dev/specs/2026-10-01-demo.md |  | - |\$" "the Plan cell is empty"
  run_lanes start --dry-run docs/runs/ec.md
  assert_eq 2 "$LS_STATUS" "an empty Plan refuses"
  assert_contains "$LS_ERR" "manifest: A: Spec or Plan is '-'" "the row refusal"
  assert_not_contains "$LS_ERR" "KAN-1 ledger line" "no ledger check of the Ticket as a plan"
  assert_not_contains "$LS_ERR" "plan KAN-1 is not in Docs" "the Ticket is not read as the Plan"
}
test_lanes_recheck_race_one_wins() {
  lanes_fixture rcr integration A:-
  lanes_add_run alpha integration S1:-; _aw="$RW"; _am="$RMF"
  lanes_add_run gamma integration S1:-; _gw="$RW"; _gm="$RMF"
  printf 'sleep 2\n' > "$SCEN/S1"
  STUDIO_OVERNIGHT_LOCK_HOOK='sleep 2'; export STUDIO_OVERNIGHT_LOCK_HOOK
  bg_lanes alpha "$_aw" start "$_am"; sleep 0.2; bg_lanes gamma "$_gw" start "$_gm"
  unset STUDIO_OVERNIGHT_LOCK_HOOK
  bg_wait alpha; _as=$BG_STATUS; bg_wait gamma; _gs=$BG_STATUS
  if [ "$_as" = 0 ]; then _win=alpha; _lose=gamma; _ls=$_gs; else _win=gamma; _lose=alpha; _ls=$_as; fi
  assert_eq 0 "$([ "$_as" = 0 ] || [ "$_gs" = 0 ] && echo 0 || echo 1)" "one of the two runs exits 0"
  assert_eq 2 "$_ls" "the loser exits 2"
  assert_contains "$TMP/bg-$_lose.err" "lost the start race: story S1 is used by live run $_win" "and names the winner"
  assert_missing "$P/.studio/runs/$_lose/lock" "the loser left no lock"
  assert_missing "$P/.studio/runs/$_lose" "no record dir"
  assert_eq "" "$(ls -d "$P"/.studio/reports/overnight-$_lose-* 2>/dev/null)" "and no run dir"
}
# overlap_case NAME ALPHA_FILES DEMO_FILES — alpha (S1 task 2 names ALPHA_FILES)
# is live; demo's A task 1 names DEMO_FILES; `start --dry-run` of demo.
overlap_case() {
  lanes_fixture "$1" integration A:-
  lanes_add_run alpha integration S1:-
  ( cd "$RW" && sed -i '' "s|^Files: \`S1-T2.txt\`|Files: $2|" docs/game-dev/plans/2026-10-01-S1.md \
    && git add -A && git commit -qm files && git push -q origin run/alpha \
    && _d="$(git rev-parse HEAD)" && sed "s/^Docs: .*/Docs: $_d/" "$RMF" > "$TMP/mf.new" && cp "$TMP/mf.new" "$RMF" \
    && git add -A && git commit -qm manifest && git push -q origin run/alpha ) > /dev/null 2>&1
  printf 'hang\n' > "$SCEN/S1"
  bg_lanes alpha "$RW" start "$RMF"
  wait_for "[ -f '$CALLS/1.story' ]" 60
  printf 'Files: %s\n' "$3" >> "$P/docs/game-dev/plans/2026-10-01-A.md"
  redocs
  run_lanes start --dry-run "$MFP"
}
test_lanes_overlap_warning() {
  overlap_case ovl '`shared.txt`, `only-alpha.txt`' '`shared.txt`, `only-demo.txt`'
  assert_eq 0 "$LS_STATUS" "an overlap only warns"
  assert_contains "$LS_ERR" "warning — live run alpha is changing files this run's unfinished tasks change too:" "the D38 header"
  assert_contains "$LS_ERR" "^  shared.txt\$" "lists the shared path"
  assert_not_contains "$LS_ERR" "only-alpha.txt" "and not the unshared ones"
  end_alpha
  _a=""; _d=""
  for _i in $(seq 10 34); do _a="$_a\`shared$_i.txt\`, "; done
  overlap_case ovl25 "$_a" "$_a"
  assert_eq 0 "$LS_STATUS" "25 shared paths still only warn"
  assert_eq 20 "$(grep -c '^  shared[0-9]*\.txt$' "$LS_ERR")" "at most 20 paths are listed"
  assert_contains "$LS_ERR" "^  and 5 more\$" "then the rest as a count"
  end_alpha
}
test_lanes_next_slug_forms() {
  LANES_CELLS=dash; export LANES_CELLS
  lanes_fixture nxs integration A:-
  sed 's/^# Run: demo/# Run: alpha-2/' "$P/$MFP" > "$P/docs/runs/alpha-2.md"
  run_lanes next docs/runs/alpha-2.md
  assert_contains "$LS_OUT" "^next: /game-dev:brainstorm alpha-2/A\$" "the slug is part of the next command"
}

# ---- #39 T12: the project-wide session cap (AC27, AC28) ----
# sess_left — the slot dirs and wait entries left under $P/.studio/sessions ("" when none).
sess_left() { ls -d "$P"/.studio/sessions/[0-9]* "$P"/.studio/sessions/wait/[0-9]* 2>/dev/null; }
# lane_of ID — the number of the demo run's lane whose current unit names ID.
lane_of() {
  for _lo in "$(last_lanes_dir)"/lanes/*/current; do
    case "$(cat "$_lo" 2>/dev/null)" in "$1 "*) _lo="${_lo%/current}"; printf '%s\n' "${_lo##*/}"; return 0 ;; esac
  done
  return 1
}
# slot_waiting ID — ID's lane is waiting for a session slot (lanes/<k>/slotwait).
slot_waiting() { _sw_k="$(lane_of "$1")" && [ -f "$(last_lanes_dir)/lanes/$_sw_k/slotwait" ]; }
# n_calls ID — how many sessions ran for story ID.
n_calls() { story_calls "$1" | wc -l | tr -d ' '; }
slot_poll() { STUDIO_OVERNIGHT_SLOT_POLL_SECONDS=1; export STUDIO_OVERNIGHT_SLOT_POLL_SECONDS; }

test_lanes_slot_cap_two_across_runs() {
  LANES_CONFIG='{"overnight": {"max_lanes": 2, "max_sessions": 2}}'; export LANES_CONFIG
  lanes_fixture cap2 integration A:- B:-
  LANES_CONFIG='{"overnight": {"max_lanes": 2}}'; export LANES_CONFIG
  lanes_add_run alpha integration S1:- S2:-
  for _id in A B S1 S2; do printf 'sleep 2\n' > "$SCEN/$_id"; done
  slot_poll
  bg_lanes demo "$P" start "$MFP"; bg_lanes alpha "$RW" start "$RMF"
  bg_wait demo; _ds="$BG_STATUS"; bg_wait alpha
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  assert_eq 0 "$_ds" "demo runs to its end under the cap"
  assert_eq 0 "$BG_STATUS" "and so does alpha"
  assert_eq 2 "$(cat "$CALLS/max" 2>/dev/null)" "four lanes in two runs, never more than two sessions at once (cap 2)"
  for _id in A B; do assert_contains "$P/.studio/runs/demo/landed.tsv" "^$_id	" "$_id lands"; done
  for _id in S1 S2; do assert_contains "$P/.studio/runs/alpha/landed.tsv" "^$_id	" "$_id lands"; done
  assert_eq "" "$(sess_left)" "no slot or wait entry is left"
}
test_lanes_slot_cap_one_alternates() {
  LANES_CONFIG='{"overnight": {"max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture alt integration A:-
  lanes_add_run alpha integration S1:-
  # A's first unit is long enough for alpha to start and queue behind it.
  printf 'waitexist %s\nsleep 1\n' "$SCEN/release-alt" > "$SCEN/A"; printf 'sleep 1\nsleep 1\n' > "$SCEN/S1"
  slot_poll
  bg_lanes demo "$P" start "$MFP"
  wait_for "[ -f '$CALLS/1.story' ]" 60
  bg_lanes alpha "$RW" start "$RMF"
  # alpha's lane is queued behind A's first unit (a sessions/wait entry): let it go.
  wait_for '[ -n "$(ls "$P"/.studio/sessions/wait/[0-9]* 2>/dev/null)" ]' 60
  : > "$SCEN/release-alt"
  bg_wait demo; _ds="$BG_STATUS"; bg_wait alpha
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  assert_eq 0 "$_ds" "demo lands"; assert_eq 0 "$BG_STATUS" "alpha lands"
  _seq="$(_i=1; while [ "$_i" -le "$(calls)" ]; do cat "$CALLS/$_i.story"; _i=$((_i + 1)); done | tr '\n' ' ')"
  assert_eq "A S1" "$(printf '%s\n' "$_seq" | cut -d' ' -f1-2)" "the waiting run's lane takes the slot A's first unit frees (FIFO)"
  # No story runs three units in a row while the other still has one to run.
  _run3="$(printf '%s\n' "$_seq" | awk '{ for (i = 1; i + 2 <= NF; i++) if ($i == $(i+1) && $i == $(i+2)) for (j = i + 3; j <= NF; j++) if ($j != $i) { print i; exit } }')"
  assert_eq "" "$_run3" "the two runs alternate under cap 1 (calls: $_seq)"
  assert_eq 1 "$(cat "$CALLS/max" 2>/dev/null)" "never two sessions at once"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_slot_kill9_lane_reclaimed() {
  LANES_CONFIG='{"overnight": {"max_lanes": 2, "max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slk9 integration A:- B:-
  printf 'hang\n' > "$SCEN/A"
  slot_poll; KILL_GRACE_SECONDS=2; export KILL_GRACE_SECONDS
  bg_lanes demo "$P" start "$MFP"
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS KILL_GRACE_SECONDS
  wait_for "[ -n \"\$(story_calls A)\" ] && lane_of A > /dev/null" 60
  R="$(last_lanes_dir)"; _k="$(lane_of A)"
  _lp="$(cat "$R/lanes/${_k:-0}/pid" 2>/dev/null)"; _sp="$(cat "$CALLS/$(story_calls A | head -n 1).pid" 2>/dev/null)"
  _b0="$(n_calls B)"
  kill -9 "${_lp:-0}" "${_sp:-0}"
  bg_wait demo
  assert_eq 1 "$BG_STATUS" "the run ends, partial (A's lane crashed)"
  assert_eq 1 "$([ "$(n_calls B)" -gt "$_b0" ] && echo 1 || echo 0)" "B's next unit gets the dead lane's slot (reclaimed by liveness)"
  assert_contains "$R/stories/B" "^landed " "and B lands"
  assert_contains "$R/stories/A" "^stopped: lane crashed (137)$" "A's story names the crash"
  assert_eq "" "$(sess_left)" "no slot or wait entry is left"
}
test_lanes_slot_stop_ends_wait() {
  LANES_CONFIG='{"overnight": {"max_lanes": 2, "max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slstop integration A:- B:-
  printf 'waitexist %s\n' "$P/.studio/runs/demo/stop" > "$SCEN/A"
  slot_poll
  bg_lanes demo "$P" start "$MFP"
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  wait_for "slot_waiting B" 60
  R="$(last_lanes_dir)"; _k="$(lane_of B)"
  assert_file "$R/lanes/${_k:-0}/slotwait" "B's lane waits for a slot: lanes/<k>/slotwait"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1
  assert_contains "$TMP/st.out" "^    waiting for a session slot since [0-9][0-9]:[0-9][0-9]\$" "status shows the wait"
  _b0="$(n_calls B)"
  ( cd "$P" && sh "$RUNNER" stop ) > /dev/null 2>&1
  bg_wait demo
  assert_contains "$R/stories/B" "^stopped stopped by user\$" "a stop ends the wait: B ends stopped by user"
  assert_eq "$_b0" "$(n_calls B)" "no session is launched for B after the stop"
  assert_missing "$R/lanes/${_k:-0}/slotwait" "slotwait goes"
  assert_eq "" "$(sess_left)" "the wait entry is gone and no slot is left"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
# A first queueing that fails (here: sessions/wait cannot be created) is said
# and retried in the wait loop, never taken as a halt (#39 final review,
# T12-1): once the queue can be written, the story runs and lands.
test_lanes_slot_enqueue_failure_retried() {
  LANES_CONFIG='{"overnight": {"max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slenq integration A:-
  mkdir -p "$P/.studio/sessions"; : > "$P/.studio/sessions/wait"
  slot_poll
  bg_lanes x "$P" start "$MFP"
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  wait_for "grep -q 'sessions: cannot queue' '$TMP/bg-x.out' '$TMP/bg-x.err' 2>/dev/null" 60
  assert_eq 1 "$(cat "$TMP/bg-x.out" "$TMP/bg-x.err" 2>/dev/null | grep -c 'sessions: cannot queue')" "the failed first queueing is said once"
  rm -f "$P/.studio/sessions/wait"
  bg_wait x
  assert_eq 0 "$BG_STATUS" "the run ends normally"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A is not ended as stopped by user: its lane queued again and ran"
  assert_eq "" "$(sess_left)" "no slot or wait entry is left"
}
# session_release removes the unit dir's slotwait with the wait entry, so a
# HUP or runner error mid-wait never leaves a stale `waiting for a session
# slot` (final/slotwait) behind (#39 final review, T12-3).
test_lanes_session_release_clears_slotwait() {
  _rs_out="$( (
    SELF_DIR="$BIN"; STATE_ROOT="$TMP/srs"; UNIT_DIR="$TMP/srs/final"; mkdir -p "$UNIT_DIR" "$STATE_ROOT/.studio/sessions/wait"
    . "$BIN/overnight-runs.sh"; . "$BIN/overnight-sessions.sh"; . "$BIN/overnight-lanes.sh"
    sess_init; SESS_ME=$$; SESS_WAIT="$STATE_ROOT/.studio/sessions/wait/1-$$"; : > "$SESS_WAIT"
    date +%H:%M > "$UNIT_DIR/slotwait"
    session_release
    [ -e "$UNIT_DIR/slotwait" ] && echo "slotwait left"; [ -e "$STATE_ROOT/.studio/sessions/wait/1-$$" ] && echo "wait entry left"
    echo done
  ) 2>&1)"
  assert_eq "done" "$_rs_out" "session_release removes slotwait and the wait entry"
}
test_lanes_slot_released_every_exit() {
  LANES_CONFIG='{"overnight": {"max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slx1 integration A:-
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "a normal end"
  assert_eq "" "$(sess_left)" "a normal end leaves no slot or wait entry"
  LANES_CONFIG='{"overnight": {"max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slx2 integration A:-
  printf 'waitexist %s\n' "$P/.studio/runs/demo/stop" > "$SCEN/A"
  bg_lanes x "$P" start "$MFP"; wait_for "[ -f '$CALLS/1.t0' ]" 60
  ( cd "$P" && sh "$RUNNER" stop ) > /dev/null 2>&1; bg_wait x
  assert_eq "" "$(sess_left)" "a stop mid-unit leaves no slot or wait entry"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  LANES_CONFIG='{"overnight": {"max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slx3 integration A:-
  printf 'waitexist %s\n' "$P/.studio/runs/demo/stop" > "$SCEN/A"
  bg_lanes x "$P" start "$MFP"; wait_for "[ -f '$CALLS/1.t0' ]" 60
  kill -TERM "$(cat "$TMP/bg-x.pid")"; bg_wait x
  assert_eq "" "$(sess_left)" "a SIGTERM to the runner leaves no slot or wait entry"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  LANES_CONFIG='{"overnight": {"max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slx4 integration A:-
  printf 'hang\n' > "$SCEN/A"
  KILL_GRACE_SECONDS=2; export KILL_GRACE_SECONDS
  bg_lanes x "$P" start "$MFP"; unset KILL_GRACE_SECONDS
  wait_for "[ -f '$CALLS/1.story' ] && [ -s \"\$(last_lanes_dir)/lanes/1/cpid\" ]" 60
  kill -9 "$(cat "$(last_lanes_dir)/lanes/1/pid" 2>/dev/null)"; bg_wait x
  assert_eq "" "$(pgrep -f "$TMP/fakebin/claude" 2>/dev/null)" "the killed lane's session is ended by the sweep"
  assert_eq "" "$(sess_left)" "and the sweep frees the dead lane's slot"
}
test_lanes_slot_wait_not_in_session_minutes() {
  LANES_CONFIG='{"overnight": {"max_lanes": 2, "max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slmin integration A:- B:-
  printf 'waitexist %s\n' "$SCEN/release-slmin" > "$SCEN/A"
  release_when slmin 'slot_waiting B'
  slot_poll; run_lanes start "$MFP"
  EV="$(last_lanes_dir)/events.jsonl"
  assert_eq 0 "$LS_STATUS" "both land under cap 1"
  _w="$(grep -n '"event":"session_wait".*"story":"B"' "$EV" | head -n 1 | cut -d: -f1)"
  _u="$(awk -v w="${_w:-0}" 'NR > w && /"event":"unit_started"/ && /"story":"B"/ { print NR; exit }' "$EV")"
  assert_eq 1 "$([ -n "$_w" ] && [ -n "$_u" ] && echo 1 || echo 0)" "B's session_wait comes before the unit_started of the unit it waited for"
  # Cap 1: each session starts at or after the previous one's end (wall clock),
  # so B's unit (its clock, unit.now and watchdog) began once A's had ended.
  _ov=""; _i=2
  while [ "$_i" -le "$(calls)" ]; do
    [ "$(cat "$CALLS/$_i.t0w")" -ge "$(cat "$CALLS/$((_i - 1)).t1")" ] || _ov="$_ov $_i"
    _i=$((_i + 1))
  done
  assert_eq "" "$_ov" "no session starts before the one holding the slot ends"
  _bn="$(story_calls B | sort -n | while read -r _c; do [ "$_c" -gt 1 ] && [ "$(cat "$CALLS/$((_c - 1)).story")" = A ] && { echo "$_c"; break; }; done)"
  assert_eq 1 "$([ -n "$_bn" ] && [ "$(cat "$CALLS/$_bn.t0w")" -ge "$(cat "$CALLS/$((_bn - 1)).t1")" ] && echo 1 || echo 0)" "B's unit after A's starts at or after A's end (t0 >= t1)"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
  # The session limit (STUDIO_OVERNIGHT_SESSION_SECONDS, 5 s) is shorter than an
  # 8 s wait behind another run's slot: B never times out.
  LANES_CONFIG='{"overnight": {"max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slmin2 integration B:-
  mkdir -p "$P/.studio/sessions/1"
  sh -c 'sleep 8; :' studio-overnight >/dev/null 2>&1 & _hold=$!
  printf 'lane=%s\nsession=\nrun=other\nunit=hold\n' "$_hold" > "$P/.studio/sessions/1/owner"
  STUDIO_OVERNIGHT_SESSION_SECONDS=5; export STUDIO_OVERNIGHT_SESSION_SECONDS
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_SESSION_SECONDS STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  kill "$_hold" 2>/dev/null; wait "$_hold" 2>/dev/null
  R="$(last_lanes_dir)"
  assert_eq 0 "$LS_STATUS" "B lands after its wait"
  assert_contains "$R/events.jsonl" '"event":"session_wait".*"story":"B"' "B waited for the slot"
  assert_not_contains "$R/lanes/1/units.tsv" "timed out" "the wait is not session time: no unit timed out"
  rw_kill
}
test_lanes_session_wait_event_and_status() {
  LANES_CONFIG='{"overnight": {"max_lanes": 2, "max_sessions": 1}}'; export LANES_CONFIG
  lanes_fixture slev integration A:- B:-
  printf 'waitexist %s\n' "$SCEN/release-slev" > "$SCEN/A"
  slot_poll
  bg_lanes demo "$P" start "$MFP"
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  wait_for "slot_waiting B" 60
  R="$(last_lanes_dir)"; _k="$(lane_of B)"; _hm="$(cat "$R/lanes/${_k:-0}/slotwait" 2>/dev/null)"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1
  : > "$SCEN/release-slev"
  bg_wait demo
  assert_eq "sessions: 1/1" "$(sed -n 1p "$TMP/st.out")" "status prints the sessions line first (AC10)"
  assert_eq "    waiting for a session slot since $_hm" "$(grep -A1 '^B  lane ' "$TMP/st.out" | sed -n 2p)" "under B: the wait and its start"
  assert_contains "$R/events.jsonl" '"event":"session_wait","lane":"'"$_k"'","story":"B","since":"[0-9-]*T[0-9:]*Z"' "the session_wait event: lane, story and an ISO since (AC28)"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_max_sessions_preflight() {
  lanes_fixture msp integration A:-
  for _v in 0 9 '"x"' 8; do
    ( cd "$P" && printf '{"overnight": {"max_sessions": %s}}\n' "$_v" > .studio/config.json \
      && git commit -qam "cfg $_v" ) > /dev/null 2>&1
    run_lanes start --dry-run "$MFP"
    if [ "$_v" = 8 ]; then
      assert_eq 0 "$LS_STATUS" "max_sessions 8 passes"
    else
      assert_eq 2 "$LS_STATUS" "max_sessions $_v refuses"
      assert_contains "$LS_ERR" "overnight.max_sessions must be an integer 1-8 in $P/.studio/config.json" "and says why ($_v)"
    fi
  done
}

# ---- T15: the Milestone round trip (two concurrent runs) ----

# rt_pair — alpha (integration, S1) and beta (direct, S2) in one project, each
# max_lanes 1, 2 sessions at once. The fixture's own run (X) is never started.
rt_pair() {
  _rt_cfg='{"overnight": {"max_lanes": 1, "max_sessions": 2}}'
  LANES_CONFIG="$_rt_cfg"; export LANES_CONFIG
  lanes_fixture rt integration X:-
  printf '%s\n' "$_rt_cfg" > "$P/.studio/config.json"
  LANES_CONFIG="$_rt_cfg"; export LANES_CONFIG
  lanes_add_run alpha integration S1:-; RW_A="$RW"; RMF_A="$RMF"
  LANES_CONFIG="$_rt_cfg"; export LANES_CONFIG
  lanes_add_run beta direct S2:-; RW_B="$RW"; RMF_B="$RMF"
  slot_poll
}
# rt_start — start alpha, wait for its lock, then start beta while alpha is live.
rt_start() {
  bg_lanes alpha "$RW_A" start "$RMF_A"
  wait_for "[ -f '$P/.studio/runs/alpha/lock' ]" 60
  bg_lanes beta "$RW_B" start "$RMF_B"
  wait_for "[ -f '$P/.studio/runs/beta/lock' ]" 60
}
# rt_bare_stop — a bare stop with two live runs exits 1, names both, stops none.
rt_bare_stop() {
  ( cd "$P" && sh "$RUNNER" stop ) > "$TMP/bs.out" 2>&1; _bs=$?
  assert_eq 1 "$_bs" "a bare stop with two live runs exits 1"
  assert_contains "$TMP/bs.out" 'alpha' "and lists alpha"
  assert_contains "$TMP/bs.out" 'beta' "and lists beta"
  assert_contains "$TMP/bs.out" 'stop --run <slug>' "names stop --run <slug>"
  assert_contains "$TMP/bs.out" 'stop --all' "and stop --all"
  assert_missing "$P/.studio/runs/alpha/stop" "a bare stop wrote no alpha stop"
  assert_missing "$P/.studio/runs/beta/stop" "nor a beta stop"
}
# rt_scen — S1's task 1 pushes a target move, flags it, then holds until beta
# has landed S2 (so task 2's sync sees both moved refs); S2 waits for the flag.
# $1 is S2's task 1 line (default: auto).
rt_scen() {
  printf 'auto; push_target other.txt; mark %s; waitafter %s\n' "$TMP/rt-s1t1" "$P/.studio/runs/beta/landed.tsv" > "$SCEN/S1"
  printf 'waitfor %s; %s\n' "$TMP/rt-s1t1" "${1:-auto}" > "$SCEN/S2"
  rm -f "$TMP/rt-s1t1"
}
rt_alpha_dir() { ls -d "$P"/.studio/reports/overnight-alpha-* 2>/dev/null | tail -n 1; }

test_lanes_round_trip_two_runs() {
  rt_pair; rt_scen
  rt_start
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1; _st=$?
  assert_eq 0 "$_st" "status exits 0 with both runs live"
  assert_contains "$TMP/st.out" '^sessions: [0-2]/2' "status line 1 shows the session count"
  assert_eq "sessions" "$(head -n 1 "$TMP/st.out" | cut -d: -f1)" "and it is line 1"
  assert_contains "$TMP/st.out" '^== alpha (manifest' "alpha's block"
  assert_contains "$TMP/st.out" '^== beta (manifest' "beta's block"
  rt_bare_stop
  bg_wait beta
  assert_eq 0 "$BG_STATUS" "beta ends 0"
  assert_contains "$P/.studio/runs/beta/landed.tsv" '^S2	' "S2 landed"
  git -C "$P" fetch -q origin
  assert_eq 1 "$(git -C "$P" ls-tree -r --name-only origin/main | grep -c '^S2-T1.txt$')" "S2's work is on main"
  bg_wait alpha
  assert_eq 0 "$BG_STATUS" "alpha ends 0"
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  assert_contains "$P/.studio/runs/alpha/landed.tsv" '^S1	' "S1 landed"
  _ev="$(rt_alpha_dir)/events.jsonl"
  assert_eq 1 "$(grep '"event":"story_synced","story":"S1"' "$_ev" | grep -c '"refs":\["origin/integration/alpha","origin/main"\]')" "one story_synced for S1 names both refs"
  assert_eq "chore(sync): merge origin/integration/alpha into S1-b|chore(sync): merge origin/main into S1-b" "$(sync_merges S1)" "the merge commits are on S1-b"
  assert_eq 4 "$(story_calls S1 | wc -l | tr -d ' ')" "S1: T1, T2, final review, finish"
  assert_missing "$CALLS/m-S1.sync" "the sync ran no session"
  assert_eq 4 "$(story_calls S2 | wc -l | tr -d ' ')" "S2: T1, T2, final review, finish"
  assert_eq 1 "$([ "$(cat "$CALLS/max")" -le 2 ] && echo 1 || echo 0)" "never more than 2 sessions at once (max $(cat "$CALLS/max"))"
  # Units that started while the other run was live saw it in their peers block.
  _seen=0
  # One assertion per call (4 per story, asserted above), so the count is fixed.
  for _pn in $(story_calls S1) $(story_calls S2); do
    case "$(cat "$CALLS/$_pn.story")" in S1) _other=beta ;; *) _other=alpha ;; esac
    _ok=1
    if grep -q '^Other live runs$' "$CALLS/$_pn.peers" 2>/dev/null; then
      _seen=$((_seen + 1)); grep -q "$_other" "$CALLS/$_pn.peers" || _ok=0
    fi
    assert_eq 1 "$_ok" "call $_pn: no Other live runs block, or it names the other run ($_other)"
  done
  assert_eq 1 "$([ "$_seen" -ge 1 ] && echo 1 || echo 0)" "at least one unit saw the Other live runs block"
}
test_lanes_round_trip_stop_one_of_two() {
  rt_pair
  # A stop ends a run after its running unit (never mid-unit), so the units
  # are long sleeps, not `hang`: alpha's ends soon, beta's outlives it.
  printf 'waitexist %s\n' "$SCEN/release-alpha" > "$SCEN/S1"; printf 'waitexist %s\n' "$P/.studio/runs/beta/stop" > "$SCEN/S2"
  rt_start
  wait_for "[ \"\$(ls '$CALLS/live' 2>/dev/null | grep -c .)\" -ge 2 ]" 60
  rt_bare_stop
  ( cd "$P" && sh "$RUNNER" stop --run alpha ) > "$TMP/so.out" 2>&1
  assert_file "$P/.studio/runs/alpha/stop" "stop --run alpha writes alpha's stop"
  : > "$SCEN/release-alpha"   # alpha's unit is held on this file, so its flag outlives the assert
  assert_missing "$P/.studio/runs/beta/stop" "and not beta's"
  bg_wait alpha
  assert_file "$P/.studio/runs/beta/lock" "beta's lock is still held"
  assert_eq 1 "$(kill -0 "$(cat "$TMP/bg-beta.pid")" 2>/dev/null && echo 1 || echo 0)" "beta's runner is alive"
  assert_missing "$P/.studio/runs/beta/stop" "still no beta stop"
  ( cd "$P" && sh "$RUNNER" stop --run beta ) > /dev/null 2>&1
  bg_wait beta
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  assert_missing "$P/.studio/runs/beta/lock" "beta's lock is gone after its stop"
  assert_missing "$CALLS/wait.timeout" "no stub wait hit its ceiling"
}
test_lanes_round_trip_sync_conflict() {
  rt_pair; rt_scen 'conflict S1-T1.txt'
  printf 'syncrepair\n' > "$SCEN/S1.sync"
  rt_start
  bg_wait beta
  assert_eq 0 "$BG_STATUS" "beta ends 0"
  bg_wait alpha
  assert_eq 0 "$BG_STATUS" "alpha ends 0"
  unset STUDIO_OVERNIGHT_SLOT_POLL_SECONDS
  assert_eq 1 "$(cat "$CALLS/m-S1.sync" 2>/dev/null)" "exactly one S1.sync call resolves the conflict"
  assert_contains "$P/.studio/runs/alpha/landed.tsv" '^S1	' "S1 lands"
  assert_not_contains "$P/.studio/runs/alpha/landed.tsv" 'stopped' "stopped appears nowhere in alpha's landed.tsv"
}

test_lanes_detach_setup_preflight_refused() {
  LANES_CONFIG='{"worktree_setup": "[ -d .git ]"}'; export LANES_CONFIG
  lanes_fixture pfdr integration A:-
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/pfdr.out" 2>&1 || st=$?
  assert_eq 2 "$st" "detach: the check runs in the foreground and refuses"
  assert_contains "$TMP/pfdr.out" "worktree_setup failed in a linked worktree — exit 1 — log " "the refusal is shown"
  assert_not_contains "$TMP/pfdr.out" "^detached:" "no child was started"
  assert_not_contains "$TMP/pfdr.out" "the detached run did not start" "the refusal is the foreground's, not a child's"
  assert_eq "" "$(ls "$P/.studio/reports" 2>/dev/null | grep '^overnight-demo-detached-')" "no detached child log: no child was started"
  assert_eq 0 "$(calls)" "no unit ran"
  assert_eq "" "$(pf_wts)" "no scratch worktree"
}
# A11: TERM to `start --detach` while its foreground check runs the setup.
test_lanes_detach_setup_preflight_interrupt() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) : > '"'$TMP/pf-dint'"'; '"'$TMP/bin/msleep'"' 4835;; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-dint"
  lanes_fixture pfdi integration A:-
  ( cd "$P" && exec sh "$RUNNER" start --detach "$MFP" ) > "$TMP/pfdi.out" 2>&1 < /dev/null &
  _pdi=$!
  wait_for "[ -f '$TMP/pf-dint' ] && [ -n \"\$(pf_wts)\" ]" 60
  assert_eq 1 "$([ -f "$TMP/pf-dint" ] && echo 1 || echo 0)" "the check is running the setup"
  kill -TERM "$_pdi"
  wait_pid_or_fail "$_pdi" 20 "TERM during detach's check ends it promptly"
  assert_eq 2 "$WP_STATUS" "exit 2: nothing started"
  assert_eq 1 "$(grep -c 'worktree_setup check interrupted — nothing started' "$TMP/pfdi.out")" "it says so, once"
  wait_for '[ -z "$(pgrep -f "$TMP/bin/msleep 4835\$")" ] && [ -z "$(pf_wts)" ]' 20
  assert_eq "" "$(pgrep -f "$TMP/bin/msleep 4835\$")" "the setup's processes are gone"
  assert_eq "" "$(pf_wts)" "no scratch worktree is left"
  assert_missing "$P/.studio/gate.lock" "the gate lock is released"
  assert_eq "" "$(ls "$P/.studio/reports" 2>/dev/null | grep '^overnight-demo-detached-')" "no detached child log: no child was started"
  assert_eq 0 "$(calls)" "no unit ran"
  pkill -f "$TMP/bin/msleep 4835\$" 2>/dev/null
}
test_lanes_detach_setup_preflight_runs_once() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) echo pf >> '"'$TMP/pf-det'"';; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-det"
  lanes_fixture pfdo integration A:-
  st=0; ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/pfdo.out" 2>&1 || st=$?
  assert_eq 0 "$st" "a green check detaches"
  assert_contains "$TMP/pfdo.out" "worktree_setup: checking it once" "the running line is in the foreground output"
  wait_for "[ -f '$CALLS/1.fullenv' ]" 60
  detach_stop
  assert_eq 1 "$(wc -l < "$TMP/pf-det" | tr -d ' ')" "the setup ran once: the child skipped it"
  assert_contains "$(ls -d "$P"/.studio/reports/overnight-demo-detached-* | tail -n 1)" "worktree_setup: checked by start --detach at [0-9a-f]\{7\}$" "the child's log says it skipped the check"
  assert_eq "" "$(pf_wts)" "no scratch worktree"
}
test_lanes_setup_checked_env_binds_to_sha() {
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) echo pf >> '"'$TMP/pf-env'"';; esac"}'; export LANES_CONFIG
  rm -f "$TMP/pf-env"
  lanes_fixture pfe integration A:-
  STUDIO_OVERNIGHT_SETUP_CHECKED=0000000000000000000000000000000000000000; export STUDIO_OVERNIGHT_SETUP_CHECKED
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_SETUP_CHECKED
  assert_eq 2 "$LS_STATUS" "a value that is not the base's commit (Target moved since detach checked it) refuses"
  assert_contains "$LS_ERR" "^studio-overnight: worktree_setup: origin/integration/demo moved since start --detach checked it — start --detach again$" "it says why"
  assert_missing "$TMP/pf-env" "and does not re-run the setup"
  assert_eq "" "$(pf_wts)" "no scratch worktree"
  assert_eq 0 "$(calls)" "no unit ran"
  rm -f "$TMP/pf-env"
  LANES_CONFIG='{"worktree_setup": "case $(pwd -P) in */setup-preflight-*) echo pf >> '"'$TMP/pf-env'"';; esac"}'; export LANES_CONFIG
  lanes_fixture pfe2 integration A:-
  STUDIO_OVERNIGHT_SETUP_CHECKED="$(git -C "$P" ls-remote origin refs/heads/integration/demo | cut -f1)"; export STUDIO_OVERNIGHT_SETUP_CHECKED
  _pfe_short="$(printf '%.7s' "$STUDIO_OVERNIGHT_SETUP_CHECKED")"
  run_lanes start "$MFP"
  unset STUDIO_OVERNIGHT_SETUP_CHECKED
  assert_eq 0 "$LS_STATUS" "the run ends done"
  assert_missing "$TMP/pf-env" "the base's own commit skips the check"
  assert_contains "$LS_ERR" "^studio-overnight: worktree_setup: checked by start --detach at $_pfe_short$" "the skip is logged"
  assert_not_contains "$CALLS/1.fullenv" "STUDIO_OVERNIGHT_SETUP_CHECKED" "the variable is not passed on to unit sessions"
}

test_lanes_runner_argv_names_tmp() {
  lanes_fixture argv integration A:-
  # TERM is a stop request (the running unit finishes), so the unit waits on a release file.
  printf 'waitfor %s\n' "$TMP/argv.go1" > "$SCEN/A"
  lanes_bg
  wait_for "[ -f '$CALLS/1.t0' ]" 60
  _lane="$(cat "$(last_lanes_dir)/claims/1/pid" 2>/dev/null)"
  ps -o args= -p "$RPID" > "$TMP/argv.runner" 2>/dev/null; ps -o args= -p "${_lane:-0}" > "$TMP/argv.lane" 2>/dev/null
  assert_contains "$TMP/argv.runner" "$TMP/bin/studio-overnight start" "the runner's argv carries \$TMP"
  assert_contains "$TMP/argv.lane" "$TMP/bin/studio-overnight start" "a lane's argv carries \$TMP"
  kill -TERM "$RPID"; echo go > "$TMP/argv.go1"
  wait_pid_or_fail "$RPID" 60 "the attached run ends on TERM, after its unit"
  lanes_fixture argv2 integration A:-
  printf 'waitfor %s\n' "$TMP/argv.go2" > "$SCEN/A"
  ( cd "$P" && sh "$RUNNER" start --detach "$MFP" ) > "$TMP/argv.det" 2>&1
  _dp="$(sed -n 's/^detached: pid \([0-9]*\),.*/\1/p' "$TMP/argv.det")"
  ps -o args= -p "${_dp:-0}" > "$TMP/argv.child" 2>/dev/null
  assert_contains "$TMP/argv.child" "$TMP/bin/studio-overnight start" "the --detach child's argv carries \$TMP"
  [ -z "$_dp" ] || kill -TERM "$_dp" 2>/dev/null
  echo go > "$TMP/argv.go2"
  wait_for "[ ! -f '$P/.studio/runs/demo/lock' ]" 60
  wait_for "[ -z \"\$(pgrep -f '$TMP/bin/studio-overnight')\" ]" 60
}
# The waiting-chain wait at its production poll (5 s; before_each leaves the
# knob unset for real-clock tests): C waits for A and B, then starts after them.
test_lanes_wait_deps_default_poll() {
  lanes_fixture wdd integration A:- B:- C:A,B
  printf 'sleep 2\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_eq 0 "$LS_STATUS" "all three land at the default poll"
  assert_contains "$(last_lanes_dir)/stories/C" "^landed " "the waiting story lands"
  g="$(dep_gap)"
  assert_eq 1 "$([ "$g" -ge 0 ] && [ "$g" -le 15 ] && echo 1 || echo 0)" "C starts after its last dependency's landing, within one default poll plus overhead (${g}s)"
}

# The stub's waitexist action and its @RUN@ token, driven directly (no runner).
test_stub_waitexist_and_run_token() {
  _sw="$TMP/stubwait"; rm -rf "$_sw"; mkdir -p "$_sw/calls" "$_sw/scen" "$_sw/run"
  : > "$_sw/run/x"
  printf 'waitexist @RUN@/x; noop\n' > "$_sw/scen/A"
  _sw_t0="$(date +%s)"
  ( cd "$_sw" && CALLS="$_sw/calls" SCEN="$_sw/scen" STUDIO_RUN_DIR="$_sw/run" STUDIO_STORY=A STUDIO_RUN=/dev/null \
      sh "$FAKE/claude" -p go ) > /dev/null 2>&1
  assert_eq 1 "$([ $(( $(date +%s) - _sw_t0 )) -lt 5 ] && echo 1 || echo 0)" "waitexist on an existing empty file returns at once"
  assert_missing "$_sw/calls/wait.timeout" "an existing empty file is no timeout"
  printf 'waitexist @RUN@/gone; noop\n' > "$_sw/scen/A"; rm -rf "$_sw/calls"; mkdir -p "$_sw/calls"
  ( cd "$_sw" && STUB_WAIT_TICKS=10 CALLS="$_sw/calls" SCEN="$_sw/scen" STUDIO_RUN_DIR="$_sw/run" STUDIO_STORY=A STUDIO_RUN=/dev/null \
      sh "$FAKE/claude" -p go ) > /dev/null 2>&1
  assert_eq "$_sw/run/gone" "$(cat "$_sw/calls/wait.timeout" 2>/dev/null)" "a missing path hits its ceiling and is recorded, @RUN@ expanded"
  printf 'waitfor @RUN@/x; noop\n' > "$_sw/scen/A"; rm -rf "$_sw/calls"; mkdir -p "$_sw/calls"
  ( cd "$_sw" && STUB_WAIT_TICKS=10 CALLS="$_sw/calls" SCEN="$_sw/scen" STUDIO_RUN_DIR="$_sw/run" STUDIO_STORY=A STUDIO_RUN=/dev/null \
      sh "$FAKE/claude" -p go ) > /dev/null 2>&1
  assert_eq "$_sw/run/x" "$(cat "$_sw/calls/wait.timeout" 2>/dev/null)" "waitfor still needs a non-empty file; an empty one is recorded at its ceiling"
  printf 'noop; waitafter @RUN@/y\n' > "$_sw/scen/A"; rm -rf "$_sw/calls"; mkdir -p "$_sw/calls"; echo done > "$_sw/run/y"
  ( cd "$_sw" && STUB_WAIT_TICKS=10 CALLS="$_sw/calls" SCEN="$_sw/scen" STUDIO_RUN_DIR="$_sw/run" STUDIO_STORY=A STUDIO_RUN=/dev/null \
      sh "$FAKE/claude" -p go ) > /dev/null 2>&1
  assert_missing "$_sw/calls/wait.timeout" "waitafter on a non-empty file (@RUN@ expanded) is no timeout"
  rm -f "$_sw/run/y"; rm -rf "$_sw/calls"; mkdir -p "$_sw/calls"
  ( cd "$_sw" && STUB_WAIT_TICKS=10 CALLS="$_sw/calls" SCEN="$_sw/scen" STUDIO_RUN_DIR="$_sw/run" STUDIO_STORY=A STUDIO_RUN=/dev/null \
      sh "$FAKE/claude" -p go ) > /dev/null 2>&1
  assert_eq "$_sw/run/y" "$(cat "$_sw/calls/wait.timeout" 2>/dev/null)" "waitafter on a missing file hits its ceiling and is recorded, @RUN@ expanded"
}

# lf_norm SRC DEST NAME — a copy of the work tree SRC at DEST (.git left out; git-ignored
# files such as .studio/STATE.md are kept), with the tree's own path ($TMP/NAME) turned into
# @N@ in every file that holds it.
lf_norm() {
  rm -rf "$2"; mkdir -p "$2"
  ( cd "$1" && tar -cf - --exclude=./.git . ) | ( cd "$2" && tar -xf - )
  for _ln_f in $(grep -rlF "$TMP/$3" "$2" 2>/dev/null); do
    sed "s|$TMP/$3|@N@|g" "$_ln_f" > "$_ln_f.n" && mv "$_ln_f.n" "$_ln_f"
  done
}
# A copied fixture equals a fresh build: the same tree (git-ignored files too), the same
# commits, clean, origin/run/demo at HEAD, its own origin url, nothing naming the template.
# The manifest names its docs commit by sha, which depends on the commit time, so the
# manifest's Docs: line and the manifest commit's tree are compared by what they point at.
test_lanes_fixture_copy_equals_build() {
  _eq_save="$LANES_FIXTURE_TEMPLATES"
  for _eq_shape in 1 2 3; do
    for _eq_pass in A B; do
      if [ "$_eq_pass" = A ]; then LANES_FIXTURE_TEMPLATES=1; else LANES_FIXTURE_TEMPLATES=0; fi
      case "$_eq_shape" in
        1) _eq_lbl="integration A:-"; lanes_fixture "eq$_eq_pass" integration A:- ;;
        2) _eq_lbl="integration A:- B:A"; lanes_fixture "eq$_eq_pass" integration A:- B:A ;;
        3) _eq_lbl="direct A:- tasks 2 config"
           LANES_TASKS=2; LANES_CONFIG='{"overnight": {"max_lanes": 2}}'; export LANES_TASKS LANES_CONFIG
           lanes_fixture "eq$_eq_pass" direct A:- ;;
      esac
    done
    LANES_FIXTURE_TEMPLATES="$_eq_save"
    lf_norm "$TMP/eqA" "$TMP/eqn/A" eqA; lf_norm "$TMP/eqB" "$TMP/eqn/B" eqB
    for _eq_x in A B; do
      _eq_dd="$(sed -n 's/^Docs: //p' "$TMP/eqn/$_eq_x/docs/runs/demo.md")"
      assert_eq "$(git -C "$TMP/eq$_eq_x" log --all --format='%H %s' | sed -n 's/ docs$//p')" "$_eq_dd" "the manifest's Docs: names the docs commit [$_eq_lbl, $_eq_x]"
      sed 's/^Docs: .*/Docs: @D@/' "$TMP/eqn/$_eq_x/docs/runs/demo.md" > "$TMP/eqn/$_eq_x/docs/runs/demo.md.n" \
        && mv "$TMP/eqn/$_eq_x/docs/runs/demo.md.n" "$TMP/eqn/$_eq_x/docs/runs/demo.md"
    done
    _eq_d="$(diff -r "$TMP/eqn/A" "$TMP/eqn/B" 2>&1)"
    assert_eq "" "$_eq_d" "a copied fixture's tree (git-ignored files too) equals a fresh build's [$_eq_lbl]"
    assert_eq "$(git -C "$TMP/eqB" log --all --format='%T %s' | grep -v ' manifest$')" "$(git -C "$TMP/eqA" log --all --format='%T %s' | grep -v ' manifest$')" "the same commits (tree and subject; the manifest commit apart) [$_eq_lbl]"
    assert_eq "$(git -C "$TMP/eqB.git" for-each-ref --format='%(refname)')" "$(git -C "$TMP/eqA.git" for-each-ref --format='%(refname)')" "the bare origins hold the same refs [$_eq_lbl]"
    assert_eq "$(git -C "$TMP/eqB.git" log --all --format='%T %s' | grep -v ' manifest$')" "$(git -C "$TMP/eqA.git" log --all --format='%T %s' | grep -v ' manifest$')" "the bare origins hold the same commits [$_eq_lbl]"
    assert_eq "" "$(git -C "$TMP/eqA" status --porcelain)$(git -C "$TMP/eqB" status --porcelain)" "both trees are clean [$_eq_lbl]"
    assert_eq "$(git -C "$TMP/eqA" rev-parse HEAD)" "$(git -C "$TMP/eqA" rev-parse origin/run/demo)" "origin/run/demo is HEAD in the copy [$_eq_lbl]"
    assert_eq "$TMP/eqA.git" "$(git -C "$TMP/eqA" remote get-url origin)" "the copy's origin is its own bare repo [$_eq_lbl]"
    assert_eq "" "$(grep -rF "$TMP/tpl" "$TMP/eqA" 2>/dev/null | head -n 1)" "nothing in the copy names the template [$_eq_lbl]"
  done
  # A reused name is a fresh project, not a copy nested into the old one.
  LANES_FIXTURE_TEMPLATES=1
  LANES_CONFIG='{"a":1}'; export LANES_CONFIG; lanes_fixture eqX integration A:-
  LANES_CONFIG='{"b":2}'; export LANES_CONFIG; lanes_fixture eqX integration A:-
  LANES_FIXTURE_TEMPLATES="$_eq_save"
  assert_eq '{"b":2}' "$(cat "$TMP/eqX/.studio/config.json")" "a second fixture of the same name carries the new config"
  assert_missing "$TMP/eqX/eqX" "and does not nest the copy inside the old project"
}
test_fixture_template_failed_build_not_reused() {
  mkdir -p "$TMP/fbbin"; _fb_real="$(command -v git)"
  cat > "$TMP/fbbin/git" <<'FAKEGIT'
#!/bin/sh
for a in "$@"; do
  if [ "$a" = push ] && [ ! -e "$FB_COUNT" ]; then : > "$FB_COUNT"; exit 1; fi
done
exec "$FB_REAL" "$@"
FAKEGIT
  chmod +x "$TMP/fbbin/git"
  _fb_path="$PATH"; _fb_save="$LANES_FIXTURE_TEMPLATES"; LANES_FIXTURE_TEMPLATES=1
  FB_COUNT="$TMP/fb.count"; FB_REAL="$_fb_real"; export FB_COUNT FB_REAL
  PATH="$TMP/fbbin:$PATH"
  _fb_cfg='{"fb": 1}'   # a tuple no other test builds, so its template is built here
  # lanes_fixture's key: date, mode, rows, CONFIG, CELLS, PROGRESS, MAIN_MOVES, TASKS, MAIN_PRE, its sum, stub path.
  _fb_key="$(printf '%s|' "$(date +%Y-%m-%d)" integration A:- "$_fb_cfg" "" "" "" "" "" "" "$FAKE" | cksum | tr ' ' -)"
  _fb_before="$TESTS_FAILED"
  LANES_CONFIG="$_fb_cfg"; export LANES_CONFIG
  lanes_fixture fb1 integration A:- > "$TMP/fb1.out"
  PATH="$_fb_path"; unset FB_COUNT FB_REAL
  assert_contains "$TMP/fb1.out" "lanes_fixture fb1: setup failed" "a failed build is reported"
  assert_eq $((_fb_before + 1)) "$TESTS_FAILED" "and counted as a failure"
  TESTS_FAILED=$((TESTS_FAILED - 1))
  assert_missing "$TMP/tpl/l-$_fb_key/ok" "a failed build leaves no ok marker"
  LANES_CONFIG="$_fb_cfg"; export LANES_CONFIG
  lanes_fixture fb2 integration A:-
  LANES_FIXTURE_TEMPLATES="$_fb_save"
  assert_eq "$_fb_before" "$TESTS_FAILED" "the next fixture of that tuple builds afresh and succeeds"
  assert_file "$TMP/tpl/l-$_fb_key/ok" "the rebuilt template is marked ok"
  assert_file "$TMP/fb2/docs/runs/demo.md" "and the project carries the manifest"
}

# Partitions. The exclusive seeds are the spec's lanes list (R5); the rulings below follow R6.
# exclusive-scan: test_lanes_overhead in (a) it bounds the runner's gap between units by a fixed elapsed ceiling; the best of two samples helps but a loaded machine can still break it
# exclusive-scan: test_lanes_waiting_chain_starts_after_deps in (a) it bounds the gap from the last landing to the waiting story's start by a fixed elapsed ceiling; the retry takes a second sample but the bound stays
# exclusive-scan: test_lanes_skip_on_stopped_dep out (d) the one-second value is only the runner's poll interval; nothing has to beat a clock
# exclusive-scan: test_lanes_lane_kill9 out (d) the poll and grace values are no window: the test kills the lane itself and waits on events with ceilings of a minute
# exclusive-scan: test_lanes_sigint in (b) a spec seed: the INT must land while both units are still inside their short stub sleeps
# exclusive-scan: test_lanes_stop_file out (d) the stub session waits on the stop flag, an event; the one-second value is a poll interval
# exclusive-scan: test_lanes_land_conflict_one_repair in (d) the first story must land inside the second story's short finish sleep, or the conflict flips to the other story; it is also in the real-clock list
# exclusive-scan: test_lanes_direct_merge_timeout in (d) a spec seed: a hung merge must be cut by a session limit of a few seconds, and the run is also bounded by an elapsed ceiling
# exclusive-scan: test_lanes_land_lock_reclaim out (d) the second story finishes on a release file set once the dead holder's lock exists, an event; the one-second value is a poll interval
# exclusive-scan: test_lanes_direct_merge_timeout_after_merge_lands in (d) a spec seed: the hung merge must outlast a session limit of a few seconds
# exclusive-scan: test_lanes_direct_merge_timeout_term_ignored in (d) a spec seed: the TERM-ignoring merge must be cut by a session limit of a few seconds plus a short grace
# exclusive-scan: test_lanes_report_on_lane_crash out (d) the grace value is no window: the test kills the lane and its session itself, then waits on the runner with a ceiling of a minute
# exclusive-scan: test_lanes_detach_poll_rejects_bad_value out (d) a false hit: the flagged value is the one the runner refuses at start, before any clock runs
# exclusive-scan: test_lanes_timed_out_outcome out (d) the stub session hangs until killed, so any session limit ends it and a late start cannot flip the outcome; it is in the real-clock list
# exclusive-scan: test_lanes_heartbeat in (d) a spec seed: a one-second heartbeat must show while a short session still runs
# exclusive-scan: test_lanes_stop_waiting_story in (a) it asserts the stop took effect inside a fixed five-second ceiling, one poll, so a starved runner can miss it
# exclusive-scan: test_lanes_setup_preflight_interrupt_cleans out (b) the TERM lands after an event wait on the setup's marker file, while its sleeper lasts far longer than the test, so there is no window; the 1 s gone-check follows the runner's exit, and the kill chain (sp_interrupt, tg_signal, studio-gate holding until the setup's group is gone) clears the sleeper before the runner exits, so it is a post-condition and not a window
# exclusive-scan: test_lanes_setup_preflight_timeout out (d) the setup command sleeps far longer than the one-second cap, so a late start still times out and nothing can flip
# exclusive-scan: test_lanes_lock_race_single_vs_manifest in (b) a spec seed: the lock hook's short sleep is the window the single-plan lock must land in
# exclusive-scan: test_lanes_recheck_race_one_wins in (b) a spec seed: the lock hook's short sleep is the window both starts race through
# exclusive-scan: test_lanes_slot_cap_two_across_runs in (b) it asserts two short stub sessions overlap, so a staggered start under load lowers the maximum it sees
# exclusive-scan: test_lanes_slot_cap_one_alternates in (d) the first hand-over is an event, but the other run's lane must queue again before the running story's short sleeps end
# exclusive-scan: test_lanes_slot_kill9_lane_reclaimed out (d) the grace value is no window: the test kills the lane itself and waits on events
# exclusive-scan: test_lanes_slot_released_every_exit out (b) the TERM lands after an event wait on the unit's start, while its stub waits for a release file, so there is no window; the grace value is no window either
# exclusive-scan: test_lanes_slot_wait_not_in_session_minutes in (d) a spec seed: a session limit of a few seconds must be outlasted by a longer wait for the slot
# exclusive-scan: test_lanes_detach_setup_preflight_interrupt out (b) the TERM lands after an event wait on the setup's marker file, while its sleeper lasts far longer than the test, so there is no window
# exclusive-scan: test_lanes_runner_argv_names_tmp out (b) the TERM lands after an event wait on the unit's start, while the unit waits for a release file, so there is no window
# exclusive-scan: test_lanes_wait_deps_default_poll in (a) it bounds the gap after the last landing by an elapsed ceiling at the production poll, while the first dependency sleeps briefly
# exclusive-scan: test_stub_waitexist_and_run_token in (a) it bounds the stub's return on an existing file by an elapsed ceiling
# exclusive-scan: test_lanes_runner_gone out (static) the stub session waits on a release file, an event; the lane's exit is awaited with a long ceiling
# exclusive-scan: test_lanes_per_run_lock_paths out (static) the stub waits on the stop flag, an event; the lock wait now has a ceiling of a minute
# exclusive-scan: test_lanes_two_runs_each_own_lock out (static) the stubs wait on a release file, an event; the lock wait now has a ceiling of a minute
# exclusive-scan: test_lanes_gate_repair_halt out (static) the gate stub waits on the stop flag, an event
# exclusive-scan: test_lanes_status_reaps_dead_runner out (static) the stub session waits on a release file, an event
# exclusive-scan: test_lanes_setup_preflight_refuses_linked_only in (c) a spec seed: it failed under a loaded run and passed alone
# exclusive-scan: test_lanes_detach_timeout_no_lock_ends_child in (c) a spec seed: it failed under load; the children must be gone inside a ceiling of one second
# exclusive-scan: test_lanes_end_sessions_spaced_path in (a) a spec seed: the ended sessions are awaited with a one-second ceiling
TESTS_EXCLUSIVE="test_lanes_slot_wait_not_in_session_minutes test_lanes_direct_merge_timeout \
  test_lanes_direct_merge_timeout_after_merge_lands test_lanes_direct_merge_timeout_term_ignored \
  test_lanes_sigint test_lanes_end_sessions_spaced_path test_lanes_lock_race_single_vs_manifest \
  test_lanes_recheck_race_one_wins test_lanes_heartbeat test_lanes_setup_preflight_refuses_linked_only \
  test_lanes_detach_timeout_no_lock_ends_child \
  test_lanes_overhead test_lanes_waiting_chain_starts_after_deps test_lanes_land_conflict_one_repair \
  test_lanes_stop_waiting_story test_lanes_slot_cap_two_across_runs test_lanes_slot_cap_one_alternates \
  test_lanes_wait_deps_default_poll test_stub_waitexist_and_run_token"
TESTS_FINAL="test_lanes_no_orphans"
# Real-clock: timing-behaviour tests (rule 2) and the carriers of each production-value knob (R7).
TESTS_REAL_CLOCK="test_lanes_sync_repair_stops test_lanes_timed_out_outcome \
  test_lanes_slot_cap_two_across_runs test_lanes_gate_never_overlaps \
  test_lanes_left_gate_reaped test_lanes_land_conflict_one_repair \
  test_lanes_detach_timeout_lock_held_points_at_status test_lanes_wait_deps_default_poll"
before_each() {
  rw_kill
  unset STUDIO_SETUP_POLL_SECONDS STUDIO_GATE_POLL_SECONDS \
        STUDIO_OVERNIGHT_REAP_POLL_SECONDS STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
  is_real_clock && return 0
  STUDIO_SETUP_POLL_SECONDS=0.2; STUDIO_GATE_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_REAP_POLL_SECONDS=0.2; STUDIO_OVERNIGHT_DETACH_POLL_SECONDS=0.2
  STUDIO_OVERNIGHT_POLL_SECONDS=1   # land-lock and hold polls: 5 s -> 1 s (existing knob, whole seconds)
  export STUDIO_SETUP_POLL_SECONDS STUDIO_GATE_POLL_SECONDS STUDIO_OVERNIGHT_REAP_POLL_SECONDS \
         STUDIO_OVERNIGHT_DETACH_POLL_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
}

run_tests test_stub_waitexist_and_run_token test_lanes_setup_preflight_refuses_linked_only test_lanes_setup_preflight_pass_launches \
  test_lanes_setup_preflight_unset_silent test_lanes_setup_preflight_dry_run_skips \
  test_lanes_setup_preflight_interrupt_cleans test_lanes_setup_preflight_sweeps_stale \
  test_lanes_setup_preflight_bad_config test_lanes_setup_preflight_timeout \
  test_lanes_detach_setup_preflight_refused test_lanes_detach_setup_preflight_interrupt \
  test_lanes_detach_setup_preflight_runs_once test_lanes_setup_checked_env_binds_to_sha \
  test_lanes_chain_rule test_lanes_manifest_refusals test_lanes_branch_default_or_target_refused test_lanes_conflicts_lock_without_start test_lanes_preflight_backlog_tasks test_lanes_manifest_header_refusals \
  test_lanes_preflight_story_checks test_lanes_preflight_story_state test_lanes_docs_unreachable \
  test_lanes_git_too_old test_lanes_sourced_only test_lanes_next \
  test_lanes_next_all_planned_and_ambiguous test_lanes_next_plan_before_autopilot \
  test_lanes_next_whole_line_ledger \
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
  test_lanes_sync_clean_merge_no_session test_lanes_sync_skips test_lanes_sync_integration_two_refs \
  test_lanes_sync_failed_merge_aborts test_lanes_sync_conflict_launches_repair test_lanes_sync_repair_stops test_lanes_sync_repair_budget \
  test_lanes_no_sync_before_repairs \
  test_lanes_final_step_once test_lanes_final_red_after_repair \
  test_lanes_final_repair_turns_green test_lanes_final_conflict test_lanes_final_resume_edits_pr \
  test_lanes_final_skipped_on_stop_or_nothing_landed test_lanes_final_stop_before_setup test_lanes_final_gate_default test_lanes_direct_progress_landing \
  test_lanes_final_dirty_unit_is_red test_lanes_final_unit_stop_pointer_invisible test_lanes_final_budget test_lanes_final_conflict_then_red test_lanes_final_gate_interrupted_not_recorded \
  test_lanes_direct_merge_timeout_after_merge_lands test_lanes_direct_merge_timeout_term_ignored \
  test_lanes_status_dead_old_lock_not_masking test_lanes_status_per_story test_lanes_report_every_ending test_lanes_report_on_lane_crash \
  test_lanes_done_marker test_lanes_status_reaps_dead_runner test_lanes_reap_names_final_pr \
  test_lanes_detach_strips_env test_lanes_detach_refusal_in_foreground test_lanes_detach_child_refusal_surfaces \
  test_lanes_detach_timeout_lock_held_points_at_status test_lanes_detach_timeout_no_lock_ends_child \
  test_lanes_detach_poll_keeps_budget test_lanes_detach_poll_rejects_bad_value \
  test_lanes_origin_attached test_lanes_origin_detach test_lanes_origin_detach_refused \
  test_lanes_help_modes test_lanes_left_gate_reaped test_lanes_timed_out_outcome test_lanes_heartbeat \
  test_lanes_activity_verb test_lanes_status_anywhere test_lanes_status_ended_partial test_lanes_watch \
  test_lanes_gate_room_warning test_lanes_gate_times_non_integer test_lanes_check_truth_region test_lanes_gate_log_from_stop test_lanes_story_listed_events test_lanes_unit_env_run_dir \
  test_lanes_held_dependents_wait test_lanes_resume_after_gate_red_runs_gate_repair test_lanes_resume_gate_repairs_counted \
  test_lanes_resume_not_gate_red_no_repair_unit test_lanes_gate_repair_noprog_holds test_lanes_landing_never_holds \
  test_lanes_stop_queued_story test_lanes_stop_running_story test_lanes_stop_waiting_story \
  test_lanes_hold_waiting_story_holds_at_start test_lanes_hold_running_then_resume test_lanes_run_stop_held_was_held \
  test_lanes_final_step_no_delivery test_lanes_deadline \
  test_lanes_stop_at_done_never_lands test_lanes_stop_held_by_operator test_lanes_stop_pending_never_holds \
  test_lanes_gate_repair_own_stop_holds test_lanes_directive_cap_holds test_lanes_hold_during_last_unit_lands_and_clears \
  test_lanes_next_adopted_planned test_lanes_context_preflight test_lanes_check_unit_first test_lanes_adopt_sync_fail_holds test_lanes_setup_fail_holds test_lanes_setup_fail_final_red test_lanes_setup_silent_fail_final_red test_lanes_setup_fail_path_specials test_lanes_direct_setup_fail_note test_lanes_gate_command_final test_lanes_gate_command_finish_red_repair test_lanes_report_adopted_lines test_lanes_adopt_seeded_runs_rest test_lanes_adopt_round_trip \
  test_lanes_per_run_lock_paths test_lanes_excludes_before_lock test_lanes_two_runs_each_own_lock \
  test_lanes_status_run_not_live test_lanes_manifest_refuses_live_single test_lanes_lock_race_single_vs_manifest \
  test_lanes_reg_write_keeps_live_sibling test_lanes_detach_with_other_run_live test_lanes_units_get_start_dir \
  test_lanes_reap_resume_line_run_worktree test_lanes_old_lock_counts_live test_lanes_old_lock_reaped_by_start \
  test_lanes_same_slug_live_refused \
  test_lanes_preflight_refuses_live_slug_id_branch test_lanes_preflight_refuses_live_old_style_run test_lanes_preflight_refuses_stopped_record test_lanes_preflight_done_record_needs_archive \
  test_lanes_preflight_branch_forms test_lanes_preflight_slug_off_and_digits test_lanes_preflight_resume_own_record \
  test_lanes_ids_next_refuses_stale test_lanes_ids_start_refuses_stale test_lanes_ids_ticket_id_seeds_clean \
  test_lanes_ids_slug_id_plans_clean test_lanes_ids_own_adopted_dry_run test_lanes_ids_direct_resume_after_landing \
  test_lanes_ids_record_keeps_rows test_lanes_ids_record_rows_union test_lanes_ids_next_needs_origin_head test_lanes_ids_next_carried_over test_lanes_ids_start_needs_default_ref test_lanes_ids_empty_cell_no_shift \
  test_lanes_recheck_race_one_wins test_lanes_overlap_warning test_lanes_next_slug_forms \
  test_lanes_slot_cap_two_across_runs test_lanes_slot_cap_one_alternates test_lanes_slot_kill9_lane_reclaimed \
  test_lanes_slot_stop_ends_wait test_lanes_slot_enqueue_failure_retried test_lanes_session_release_clears_slotwait test_lanes_slot_released_every_exit test_lanes_slot_wait_not_in_session_minutes \
  test_lanes_session_wait_event_and_status test_lanes_max_sessions_preflight \
  test_lanes_round_trip_two_runs test_lanes_round_trip_sync_conflict test_lanes_round_trip_stop_one_of_two \
  test_lanes_ready_needs_run_pointer test_lanes_ready_adopted_unseeded test_lanes_ready_stale_worktree_and_landed \
  test_lanes_runner_argv_names_tmp test_lanes_wait_deps_default_poll \
  test_lanes_fixture_copy_equals_build test_fixture_template_failed_build_not_reused \
  test_lanes_no_orphans
