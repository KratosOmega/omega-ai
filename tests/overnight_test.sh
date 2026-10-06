#!/bin/sh
# Runner suite for studios/game-dev/bin/studio-overnight. A stub `claude`
# (first on PATH) plays each session from a scenario file: one line per
# session, actions separated by ';'. Runs offline; no real claude, gh or
# caffeinate is ever called.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

RUNNER="$REPO_ROOT/studios/game-dev/bin/studio-overnight"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# The runner's user-level registry lives under $HOME: never the real one.
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
FAKE="$TMP/fakebin"
mkdir -p "$FAKE"

# The stub session. Records argv (one element per line), cwd, the
# OMEGA_AUTOPILOT value, start/end epoch seconds and a copy of the lock, then
# runs this call's scenario line.
cat > "$FAKE/claude" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  [ "${STUB_VERSION_STATUS:-0}" = 0 ] || exit "$STUB_VERSION_STATUS"
  echo "2.1.287 (Claude Code)"; exit 0
fi
n=$(( $(cat "$CALLS/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CALLS/count"
echo "$$" > "$CALLS/$n.pid"
date +%s > "$CALLS/$n.t0"
for a in "$@"; do printf '%s\n' "$a"; done > "$CALLS/$n.argv"
pwd -P > "$CALLS/$n.pwd"
printf '%s %s\n' "${STUDIO_UNIT_TAG:-unset}" "${STUDIO_RUN_DIR:-unset}" > "$CALLS/$n.chan"
printf '%s\n' "${OMEGA_AUTOPILOT:-unset}" > "$CALLS/$n.env"
root="$(sh "$STUB_STATE_BIN" root)"
cp "$root/.studio/overnight.lock" "$CALLS/$n.lock" 2>/dev/null
[ -f "$CALLS/caffeinate.pid" ] && kill -0 "$(cat "$CALLS/caffeinate.pid")" 2>/dev/null && echo alive > "$CALLS/$n.caf"
line="$(sed -n "${n}p" "$OVERNIGHT_SCENARIO")"
cost=1; code=0
old_ifs="$IFS"; IFS=';'
set -f; set -- $line; set +f
IFS="$old_ifs"
for act in "$@"; do
  act="$(printf '%s' "$act" | sed 's/^ *//; s/ *$//')"
  case "$act" in
    "stage "*)    sh "$STUB_STATE_BIN" set stage "${act#stage }" ;;
    "task "*)     sh "$STUB_STATE_BIN" set task "${act#task }" ;;
    "ledger "*)   sh "$STUB_STATE_BIN" ledger "${act#ledger }" ;;
    # branch: real execute's (c) (#42) — a new worktree, the hand-off into it,
    # then `set branch` there; the line's later actions run in the worktree.
    "branch "*)   b="${act#branch }"
                  git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  cd "$TMP_WT/wt-$b" && sh "$STUB_STATE_BIN" handoff "$(pwd -P)" >/dev/null 2>&1
                  sh "$STUB_STATE_BIN" set branch "$b" ;;
    # legacybranch: the pre-#42 (c), `set branch` in the start checkout.
    "legacybranch "*) b="${act#legacybranch }"
                  git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  sh "$STUB_STATE_BIN" set branch "$b" ;;
    # inplace: (c) with consent to work in place — no worktree, no hand-off.
    inplace)      git checkout -q -b feat && sh "$STUB_STATE_BIN" set branch feat ;;
    stopbeforec)  sh "$STUB_STATE_BIN" ledger "Stop: stopped before isolation" ;;
    wtcheck)      _w=0; sh "$STUB_STATE_BIN" worktree >/dev/null 2>&1 || _w=$?; echo "$_w" > "$CALLS/$n.wt" ;;
    "dupstory "*) b="${act#dupstory }"; ( git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  cd "$TMP_WT/wt-$b" && for a in "stage brainstorm" "spec docs/spec.md" "stage plan"; do sh "$STUB_STATE_BIN" set $a; done ) >/dev/null 2>&1 ;;
    "rmwt "*)     ( cd / && git -C "$root" worktree remove --force "$TMP_WT/wt-${act#rmwt }" ) >/dev/null 2>&1 ;;
    "wtledger "*) ( cd "$(sh "$STUB_STATE_BIN" worktree)" && sh "$STUB_STATE_BIN" ledger "${act#wtledger }" ) ;;
    "cost "*)     cost="${act#cost }" ;;
    nocost)       cost="" ;;
    "sleep "*)    sleep "${act#sleep }" ;;
    ignoreterm)   trap '' TERM ;;
    hang)         while :; do sleep 1; done ;;
    orphan)       printf '%s\n' 'Background tasks still running after 600s; terminating. Set CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 to wait indefinitely.' >&2 ;;
    rotsv)        r="$(sed -n 's/^run=//p' "$root/.studio/overnight.lock")"
                  touch "$r/units.tsv"; chmod 444 "$r/units.tsv" ;;
    rmrundir)     r="$(sed -n 's/^run=//p' "$root/.studio/overnight.lock")"; rm -rf "$r" ;;
    "exit "*)     code="${act#exit }" ;;
    inbox)        printf '{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}' \
                    | sh "$STUB_PLUGIN/hooks/operator-inbox.sh" > "$CALLS/$n.inbox" ;;
    "say "*)      sh "$STUB_RUNNER" say - -- "${act#say }" > /dev/null 2>&1 ;;
    "corruptrq "*) r="$(sed -n 's/^run=//p' "$root/.studio/overnight.lock")"
                  for f in "$r"/inbox/-/delivered/*/[0-9]*.msg; do
                    sed "s/^requeues: .*/requeues: ${act#corruptrq }/" "$f" > "$f.t" && mv "$f.t" "$f"
                  done ;;
    holdop)       sh "$STUB_RUNNER" hold - > /dev/null 2>&1 ;;
    stopop)       sh "$STUB_RUNNER" stop - > /dev/null 2>&1 ;;
    "unsay "*)    sh "$STUB_RUNNER" unsay - "${act#unsay }" > /dev/null 2>&1 ;;
  esac
done
printf '{"type":"system","subtype":"init"}\n'
[ -z "$cost" ] || printf '{"type":"result","subtype":"success","total_cost_usd":%s}\n' "$cost"
date +%s > "$CALLS/$n.t1"
exit "$code"
STUB
printf '#!/bin/sh\nexec claude "$@"\n' > "$FAKE/claude-gd"
printf '#!/bin/sh\nexit "${GH_STATUS:-0}"\n' > "$FAKE/gh"
# A fake caffeinate: records its argv and pid, then lives until the -w pid dies.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$CALLS/caffeinate.args"\necho "$$" > "$CALLS/caffeinate.pid"\nwhile kill -0 "$3" 2>/dev/null; do sleep 1; done\n' > "$FAKE/caffeinate"
chmod +x "$FAKE"/*
export PATH="$FAKE:$PATH" STUB_STATE_BIN="$STATE_BIN" STUB_RUNNER="$RUNNER" STUB_PLUGIN="$REPO_ROOT/studios/game-dev"
# The suites test today's endings: hold_minutes 0 (spec milestone gate 1).
STUDIO_OVERNIGHT_HOLD_MINUTES=0; export STUDIO_OVERNIGHT_HOLD_MINUTES

# fixture NAME [CONFIG_JSON] — a committed project at stage plan with an
# approved spec and plan (with ## Decisions); fresh $CALLS and scenario.
fixture() {
  P="$TMP/$1"; CALLS="$TMP/calls-$1"; TMP_WT="$TMP/wts-$1"
  OVERNIGHT_SCENARIO="$TMP/scenario-$1"
  export CALLS TMP_WT OVERNIGHT_SCENARIO
  mkdir -p "$P/docs" "$CALLS" "$TMP_WT"; : > "$OVERNIGHT_SCENARIO"
  rm -rf "$TMP/$1.git"; git init -q --bare "$TMP/$1.git"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git remote add origin "$TMP/$1.git" && git push -q origin main && git remote set-head origin main
    sh "$STATE_BIN" init >/dev/null
    [ -z "${2:-}" ] || printf '%s\n' "$2" > .studio/config.json
    printf '# Spec\n' > docs/spec.md
    printf '# Plan\n\n## Decisions\n\n- none\n' > docs/plan.md
    sh "$STATE_BIN" set spec docs/spec.md; sh "$STATE_BIN" set plan docs/plan.md
    sh "$STATE_BIN" set stage plan
    sh "$STATE_BIN" ledger "spec approved docs/spec.md"
    sh "$STATE_BIN" ledger "plan approved docs/plan.md"
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m fixture ) >/dev/null 2>&1
}
# scenario LINE... — one line per stub session.
scenario() { printf '%s\n' "$@" > "$OVERNIGHT_SCENARIO"; }
# run_start [ARGS] — `studio-overnight start ARGS` in $P, foreground.
run_start() {
  RS_STATUS=0
  ( cd "$P" && sh "$RUNNER" start "$@" ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  RS_OUT="$TMP/rs.out"; RS_ERR="$TMP/rs.err"
}
calls() { cat "$CALLS/count" 2>/dev/null || echo 0; }
last_run_dir() { ls -d "$P"/.studio/reports/overnight-* 2>/dev/null | tail -n 1; }
# A live process whose argv names studio-overnight (the trailing ':' stops sh
# from exec-ing sleep, which would drop the name from ps).
live_dummy() { sh -c 'sleep 60; :' studio-overnight >/dev/null 2>&1 & DUMMY=$!; }

# ---- #27: the operator verbs against a fake live run ----
# fake_run NAME single|manifest [ID=RECORD]… — a live run with no runner in
# the current fixture $P:
# - the lock names a live_dummy pid (FR_PID) and run dir FR_DIR
#   ($P/.studio/reports/NAME);
# - FR_DIR/channel holds FR_HOLD (default 480) and FR_CHARS (default 4000);
# - a registry entry exists (root and start $P).
# manifest also writes:
# - rows.tsv, and stories/ID = RECORD;
# - each story's studio state and ledger (`plan approved x`), committed.
fake_run() {
  _fr_n="$1"; _fr_m="$2"; shift 2
  FR_DIR="$P/.studio/reports/$_fr_n"; mkdir -p "$FR_DIR/stories"
  printf 'hold_minutes=%s\ndirective_chars=%s\n' "${FR_HOLD:-480}" "${FR_CHARS:-4000}" > "$FR_DIR/channel"
  live_dummy; FR_PID="$DUMMY"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$FR_PID" "$FR_DIR" > "$P/.studio/overnight.lock"
  mkdir -p "$HOME/.claude-gamedev/runs"
  printf 'root=%s\nstart=%s\nrun=%s\npid=%s\nstarted=2026-10-03T21:00:00Z\n' "$P" "$P" "$FR_DIR" "$FR_PID" \
    > "$HOME/.claude-gamedev/runs/$_fr_n-$FR_PID"
  [ "$_fr_m" = manifest ] || return 0
  : > "$FR_DIR/rows.tsv"
  for _fr_r in "$@"; do
    _fr_id="${_fr_r%%=*}"
    printf '%s\t%s-b\t%s\t-\t-\t\n' "$_fr_id" "$_fr_id" "$_fr_id" >> "$FR_DIR/rows.tsv"
    printf '%s\n' "${_fr_r#*=}" > "$FR_DIR/stories/$_fr_id"
    ( cd "$P" && STUDIO_STORY="$_fr_id" && export STUDIO_STORY \
        && sh "$STATE_BIN" init && sh "$STATE_BIN" ledger "plan approved x" ) >/dev/null 2>&1
  done
  ( cd "$P" && git add -A .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm stories ) >/dev/null 2>&1
}
# fake_mrun SLUG [ID=RECORD]… — a live manifest run with a per-run lock
# (#39): <root>/.studio/runs/SLUG/lock (pid, run, started, start=$P), its run
# dir FR_DIR ($P/.studio/reports/overnight-SLUG-20261004-210000) with
# manifest.md (`# Run: SLUG`), channel, rows.tsv and stories/, and a registry
# entry. FR_PID is its live_dummy; FR_LOCK the lock.
fake_mrun() {
  _fm_s="$1"; shift
  FR_DIR="$P/.studio/reports/overnight-$_fm_s-20261004-210000"; mkdir -p "$FR_DIR/stories" "$P/.studio/runs/$_fm_s"
  printf '# Run: %s\n\nMode: integration\nTarget: integration/%s\n' "$_fm_s" "$_fm_s" > "$FR_DIR/manifest.md"
  printf 'hold_minutes=%s\ndirective_chars=%s\n' "${FR_HOLD:-480}" "${FR_CHARS:-4000}" > "$FR_DIR/channel"
  live_dummy; FR_PID="$DUMMY"; FR_LOCK="$P/.studio/runs/$_fm_s/lock"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-04T21:00:0%s\nstart=%s\n' "$FR_PID" "$FR_DIR" "${FR_SEQ:-0}" "$P" > "$FR_LOCK"
  mkdir -p "$HOME/.claude-gamedev/runs"
  printf 'root=%s\nstart=%s\nrun=%s\npid=%s\nstarted=2026-10-04T21:00:00Z\n' "$P" "$P" "$FR_DIR" "$FR_PID" \
    > "$HOME/.claude-gamedev/runs/overnight-$_fm_s-$FR_PID"
  : > "$FR_DIR/rows.tsv"
  for _fm_r in "$@"; do
    _fm_id="${_fm_r%%=*}"
    printf '%s\t%s-b\t%s\t-\t-\t\n' "$_fm_id" "$_fm_id" "$_fm_id" >> "$FR_DIR/rows.tsv"
    printf '%s\n' "${_fm_r#*=}" > "$FR_DIR/stories/$_fm_id"
    ( cd "$P" && STUDIO_STORY="$_fm_id" && export STUDIO_STORY && sh "$STATE_BIN" init && sh "$STATE_BIN" ledger "plan approved x" ) >/dev/null 2>&1
  done
  ( cd "$P" && git add -A .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm "stories $_fm_s" ) >/dev/null 2>&1
}
# fake_run_end [PID] — end a fake run (default FR_PID): its dummy, lock (the
# project-wide one, or a per-run .studio/runs/*/lock) and registry entry.
fake_run_end() {
  _fe_p="${1:-$FR_PID}"
  kill "$_fe_p" 2>/dev/null; wait "$_fe_p" 2>/dev/null
  rm -f "$HOME"/.claude-gamedev/runs/*-"$_fe_p"
  [ "$(sed -n 's/^pid=//p' "$P/.studio/overnight.lock" 2>/dev/null)" != "$_fe_p" ] || rm -f "$P/.studio/overnight.lock"
  for _fe_l in "$P"/.studio/runs/*/lock; do
    [ -f "$_fe_l" ] && [ "$(sed -n 's/^pid=//p' "$_fe_l")" = "$_fe_p" ] && rm -f "$_fe_l"
  done
  return 0
}
# verb_in DIR ARGS… — `studio-overnight ARGS` in DIR: V_STATUS; V_OUT and
# V_ERR (file paths). verb ARGS… — the same in $P.
verb_in() {
  _vi_d="$1"; shift; V_STATUS=0
  ( cd "$_vi_d" && sh "$RUNNER" "$@" ) > "$TMP/v.out" 2> "$TMP/v.err" || V_STATUS=$?
  V_OUT="$TMP/v.out"; V_ERR="$TMP/v.err"
}
verb() { verb_in "$P" "$@"; }
# put_msg DIR ID SCOPE TEXT [TARGET] — a message file DIR/ID.msg, as say writes it.
put_msg() {
  mkdir -p "$1"
  printf 'id: %s\nscope: %s\ntarget: %s\nstory: -\nqueued: 2026-10-03T21:04:00Z\nrequeues: 0\n--\n%s\n' \
    "$2" "$3" "${5:--}" "$4" > "$1/$2.msg"
}
# ledger_add LINE… — single-plan ledger lines in $P, committed.
ledger_add() {
  ( cd "$P" && for _la in "$@"; do sh "$STATE_BIN" ledger "$_la"; done \
      && git add -A .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm ledger ) >/dev/null 2>&1
}
# body FILE — a message file's body.
body() { sed '1,/^--$/d' "$1"; }

test_overnight_help() {
  out="$(sh "$RUNNER" --help 2>&1)"; st=$?
  assert_eq 0 "$st" "--help exits 0"
  printf '%s\n' "$out" > "$TMP/help.txt"
  for w in "start \[--dry-run\]" "status" "stop" "STUDIO_OVERNIGHT_SESSION_SECONDS" "overnight-deny.txt" "report.md" \
           "run_usd .*0-5000" "max_lanes" "model_task" "model_final" "model_finish" "model_repair" "model_progress" "merge_command" "gate_repairs .*0-3" \
           "say <story>" "said <story>" "unsay <story> <id>" "hold <story>" "resume <story>" "stop <story>" "--run <run>" "hold_minutes .*0-1440" \
           "directive_chars .*500-16000" "STUDIO_OVERNIGHT_HOLD_MINUTES — test hook" "STUDIO_OVERNIGHT_HOLD_SECONDS — test hook" \
           "STUDIO_OVERNIGHT_INBOX_WAIT — test hook" "events.jsonl" "next tool call" \
           "deny-rules \[--dir" "STUDIO_RUN_ORIGIN"; do
    assert_contains "$TMP/help.txt" "$w" "help names $w"
  done
  assert_contains "$REPO_ROOT/docs/game-dev/overnight-events.md" "deny-rules" "the contract doc lists deny-rules"
  assert_contains "$REPO_ROOT/docs/game-dev/overnight-events.md" "origin=" "the contract doc documents origin="
  assert_contains "$TMP/help.txt" "$RUNNER" "help names the runner by its absolute path"
  assert_contains "$TMP/help.txt" "STUDIO_OVERNIGHT_RACE_HOOK — test hook" "help documents the race test hook (D13)"
  assert_contains "$TMP/help.txt" "^The run may: commit, push the feature branch, open a draft PR\.$" "help lists what the run may do"
  assert_contains "$TMP/help.txt" "^The run may not: merge, force-push, delete a remote branch" "help lists what the run may not do"
  assert_contains "$TMP/help.txt" "secrets" "the may-not line names secrets"
}

# AC30: the contract #28 builds on. Every event the code writes is in the
# doc's table and every documented event is written; the doc names the
# envelope, the verbs and exit codes, the files and run discovery.
test_events_contract_doc() {
  DOC="${EVENTS_DOC:-$REPO_ROOT/docs/game-dev/overnight-events.md}"   # EVENTS_DOC: a scratch copy, to prove the check fails
  B="$REPO_ROOT/studios/game-dev/bin"; H="$REPO_ROOT/studios/game-dev/hooks/operator-inbox.sh"
  assert_file "$DOC" "the contract exists"
  # every call site, comment lines dropped: `run_event NAME …`, `chan_event
  # NAME …` and the hook's `"$RD" NAME …`
  cat "$B/studio-overnight" "$B/overnight-lanes.sh" "$B/overnight-channel.sh" "$H" | grep -v '^[[:space:]]*#' \
    | grep -oE '(run_event|chan_event|"\$RD") [a-z_]+ ("|[a-z_]+(=|:=|\[\]=)|'"'"')' > "$TMP/ev-calls.txt"
  cat "$B/studio-overnight" "$B/overnight-lanes.sh" "$B/overnight-channel.sh" "$H" | grep -v '^[[:space:]]*#' \
    | grep -oE '(run_event|chan_event|"\$RD") [a-z_]+ .*' > "$TMP/ev-lines.txt"
  for e in run_started story_listed story_state story_synced unit_started unit_ended session_wait message_queued message_delivered message_requeued control run_ended; do
    assert_contains "$DOC" "^| \`$e\` |" "the doc's table lists $e"
    assert_eq 1 "$(awk -v e="$e" '$2 == e { f = 1 } END { print f ? 1 : 0 }' "$TMP/ev-calls.txt")" "the code writes $e"
    # fields: those at the event's call sites equal those in the doc's fields column
    awk -v e="$e" '$2 == e' "$TMP/ev-lines.txt" | grep -oE "(^| |\"|')[a-z_]+(:=|\[\]=|=)" \
      | tr -d " \"'" | sed -e 's/:=$//' -e 's/\[\]=$//' -e 's/=$//' | sort -u > "$TMP/ev-code.txt"
    grep "^| \`$e\` |" "$DOC" | awk -F'|' '{ print $3 }' | grep -oE '`[a-z_]+`' | tr -d '`' | sort -u > "$TMP/ev-doc.txt"
    for k in $(cat "$TMP/ev-code.txt"); do
      assert_eq 1 "$(grep -qx "$k" "$TMP/ev-doc.txt" && echo 1 || echo 0)" "$e: emitted field $k is in the doc's row"
    done
    for k in $(cat "$TMP/ev-doc.txt"); do
      assert_eq 1 "$(grep -qx "$k" "$TMP/ev-code.txt" && echo 1 || echo 0)" "$e: documented field $k is emitted"
    done
  done
  # every event the code writes is documented
  for e in $(awk '{ print $2 }' "$TMP/ev-calls.txt" | sort -u); do
    assert_contains "$DOC" "^| \`$e\` |" "$e, written by the code, is documented"
  done
  for w in '"v":1' '^## Schema v1' 'never renamed or removed' 'run=<run dir>' 'events.jsonl' 'hook.log' 'inbox/<story>/<id>.msg' \
           'delivered/<unit tag>/<id>.msg' 'control/<story>.hold' '^requeues: 0$' '^--$' 'hold_minutes=<N>' 'directive_chars=<N>' \
           'say <story>' 'said <story>' 'unsay <story> <id>' 'hold <story>' 'resume <story>' 'stop <story>' '--run <run>' \
           '^| 0 | ' '^| 1 | ' '^| 2 | ' 'run <name> is not live'; do
    assert_contains "$DOC" "$w" "the doc names $w"
  done
  assert_contains "$REPO_ROOT/README.md" "studio-overnight say" "README teaches say"
  assert_contains "$REPO_ROOT/README.md" "hold_minutes" "README names hold_minutes"
  assert_contains "$REPO_ROOT/README.md" "overnight-events.md" "README links the contract"
  assert_contains "$REPO_ROOT/README.md" "next tool call" "README states the delivery latency"
}

test_overnight_session_seconds_refused() {
  for bad in 1.5 abc -3 "10 s"; do
    fixture secs; STUDIO_OVERNIGHT_SESSION_SECONDS="$bad"; export STUDIO_OVERNIGHT_SESSION_SECONDS
    refuse_case "STUDIO_OVERNIGHT_SESSION_SECONDS=$bad" "STUDIO_OVERNIGHT_SESSION_SECONDS"
    unset STUDIO_OVERNIGHT_SESSION_SECONDS
  done
}

test_overnight_dry_run() {
  fixture dry
  run_start --dry-run
  assert_eq 0 "$RS_STATUS" "dry run exits 0 when every preflight check passes"
  assert_contains "$RS_OUT" "OMEGA_AUTOPILOT=1 claude-gd -p '/game-dev:execute --one'" "dry run prints the launch line, prompt first"
  assert_contains "$RS_OUT" "'Bash(git push --force:\*)'" "a deny rule with spaces is one quoted word"
  assert_contains "$RS_OUT" "'--max-budget-usd' '25'" "session_usd defaults to 25"
  assert_missing "$P/.studio/overnight.lock" "dry run takes no lock"
  assert_missing "$P/.studio/reports" "dry run makes no run directory"
  assert_eq 0 "$(calls)" "dry run launches no session"
  assert_contains "$RS_OUT" "^env: cpu " "the preflight prints the resource readout"
}
# A machine short of memory warns in the preflight and blocks nothing (#37).
test_overnight_preflight_env_warns_not_blocks() {
  fixture envw
  _fx="$TMP/envw-fx"; rm -rf "$_fx"; mkdir -p "$_fx"
  echo Linux > "$_fx/uname"; echo "0.5 0.5 0.5 1/9 1" > "$_fx/proc.loadavg"; echo 4 > "$_fx/nproc"
  printf 'MemTotal: 8388608 kB\nMemAvailable: 300000 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$_fx/proc.meminfo"
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 100 1 190840000 1%% /\n' > "$_fx/df"
  printf '  PID  PPID   RSS %%CPU COMMAND\n 10 1 3000000 1.0 firefox\n' > "$_fx/ps"
  STUDIO_ENV_FIXTURE="$_fx"; export STUDIO_ENV_FIXTURE
  run_start --dry-run
  unset STUDIO_ENV_FIXTURE
  assert_eq 0 "$RS_STATUS" "a memory warning does not refuse the start"
  assert_contains "$RS_OUT" "^env: cpu 0.5/4 · memory critical (swap 0.0 GB) · disk 182 GB free$" "the summary line"
  assert_contains "$RS_OUT" "^⚠ memory critically low (3% available) — close something; top by memory:$" "the warning block"
  assert_contains "$RS_OUT" "^    firefox 2.9 GB$" "and the top list"
}

# refuse_case NAME MESSAGE-PATTERN — run start in the current fixture and
# assert a one-line refusal, exit 2, no lock, no session.
refuse_case() {
  run_start
  assert_eq 2 "$RS_STATUS" "$1: exit 2"
  assert_contains "$RS_ERR" "$2" "$1: names the failure"
  assert_eq 1 "$(grep -c . "$RS_ERR")" "$1: one line"
  assert_missing "$P/.studio/overnight.lock" "$1: no lock"
  assert_eq 0 "$(calls)" "$1: no session"
}

test_overnight_preflight_refusals() {
  fixture r1; sed -i.bak '/plan approved/d' "$P/.studio/ledger/spec.md"; rm -f "$P/.studio/ledger/spec.md.bak"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm x )
  refuse_case "no plan approved line" "plan approved"
  fixture r1b; sed -i.bak 's|plan approved docs/plan.md$|plan approved docs/plan.md.old|' "$P/.studio/ledger/spec.md"; rm -f "$P/.studio/ledger/spec.md.bak"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm x )
  refuse_case "only a longer path is approved" "plan approved"
  fixture r1c; ( cd "$P" && sh "$STATE_BIN" set plan - && git add -A && git -c user.name=t -c user.email=t@t commit -qm x ) >/dev/null
  refuse_case "no plan set" "no spec or plan set"
  fixture r1d; ( cd "$P" && sh "$STATE_BIN" set spec - && git add -A && git -c user.name=t -c user.email=t@t commit -qm x ) >/dev/null
  refuse_case "no spec set" "no spec or plan set"
  fixture r2; printf 'more\n' >> "$P/docs/plan.md"; refuse_case "dirty plan" "uncommitted"
  fixture r3; printf -- '- x\n' >> "$P/.studio/ledger/spec.md"; refuse_case "dirty ledger" "read the Stop: line"
  fixture r4; printf '# Plan\n' > "$P/docs/plan.md"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm x )
  refuse_case "no Decisions section" "## Decisions"
  fixture r5; ( cd "$P" && sh "$STATE_BIN" set stage idle ); refuse_case "stage idle" "stage idle"
  fixture r6; STUB_VERSION_STATUS=1; export STUB_VERSION_STATUS
  refuse_case "claude-gd --version fails" "claude-gd"; unset STUB_VERSION_STATUS
  fixture r7; GH_STATUS=1; export GH_STATUS; refuse_case "gh not authenticated" "gh auth status"; unset GH_STATUS
}

test_overnight_preflight_all_failures() {
  fixture r8; ( cd "$P" && sh "$STATE_BIN" set stage idle )
  GH_STATUS=1; export GH_STATUS; run_start; unset GH_STATUS
  assert_eq 2 "$RS_STATUS" "two failures: exit 2"
  assert_eq 2 "$(grep -c . "$RS_ERR")" "two failures: one line each"
}

test_overnight_config_refusals() {
  for bad in '"session_usd": 0' '"session_usd": 201' '"run_usd": 5001' '"session_minutes": 9' \
             '"session_minutes": 1.5' '"run_usd": 0.5' '"retries": 4' '"retries": "two"' '"kill_grace_seconds": 4' '"gate_repairs": 4'; do
    key="$(printf '%s' "$bad" | sed 's/^"\([a-z_]*\)".*/\1/')"
    fixture cfg "{ \"overnight\": { $bad } }"
    refuse_case "config $bad" "$key"
  done
  fixture cfgok '{ "overnight": { "session_usd": 2.5, "run_usd": 10, "session_minutes": 10, "retries": 0, "kill_grace_seconds": 5 } }'
  run_start --dry-run
  assert_eq 0 "$RS_STATUS" "in-range config passes, decimals allowed for USD"
  assert_contains "$RS_OUT" "'--max-budget-usd' '2.5'" "session_usd is read from config"
}

test_overnight_deny_file_required() {
  # The runner reads overnight-deny.txt beside itself: run a copy whose
  # sibling deny file holds only comments.
  fixture deny
  mkdir -p "$TMP/denybin"; cp "$RUNNER" "$STATE_BIN" "$REPO_ROOT/studios/game-dev/bin/overnight-channel.sh" "$REPO_ROOT/studios/game-dev/bin/overnight-runs.sh" "$REPO_ROOT/studios/game-dev/bin/overnight-sessions.sh" "$REPO_ROOT/studios/game-dev/bin/overnight-progress.sh" "$REPO_ROOT/studios/game-dev/bin/studio-env" "$TMP/denybin/"
  printf '# only a comment\n\n' > "$TMP/denybin/overnight-deny.txt"
  RS_STATUS=0; ( cd "$P" && sh "$TMP/denybin/studio-overnight" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 2 "$RS_STATUS" "a deny file with no rules refuses"
  assert_contains "$TMP/rs.err" "overnight-deny.txt" "the refusal names the deny file"
  rm -f "$TMP/denybin/overnight-deny.txt"
  RS_STATUS=0; ( cd "$P" && sh "$TMP/denybin/studio-overnight" start ) > /dev/null 2>&1 || RS_STATUS=$?
  assert_eq 2 "$RS_STATUS" "a missing deny file refuses"
}

test_overnight_lock() {
  fixture lock; live_dummy
  printf 'pid=%s\nrun=x\nstarted=y\n' "$DUMMY" > "$P/.studio/overnight.lock"
  run_start
  assert_eq 2 "$RS_STATUS" "live lock: exit 2"
  assert_contains "$RS_ERR" "pid $DUMMY" "live lock: names the live pid"
  assert_eq 1 "$(grep -c . "$RS_ERR")" "live lock: one line"
  assert_eq 0 "$(calls)" "live lock: no session"
  assert_contains "$P/.studio/overnight.lock" "^pid=$DUMMY\$" "live lock: the lock still holds the live pid"
  kill "$DUMMY" 2>/dev/null; wait "$DUMMY" 2>/dev/null
  # A stale lock: the pid is dead. The run proceeds with a warning
  # (one no-progress-free session: it ships).
  scenario "stage execute; ledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_contains "$RS_ERR" "reclaiming stale lock (pid $DUMMY)" "a dead pid is reclaimed with a warning"
  assert_contains "$CALLS/1.lock" "^pid=" "the lock names the runner's pid during the run"
  assert_missing "$P/.studio/overnight.lock" "the lock is removed when the run ends"
}

test_overnight_start_args() {
  fixture args
  run_start --dryrun
  assert_eq 2 "$RS_STATUS" "an unknown start argument exits 2"
  assert_contains "$RS_ERR" "usage:" "an unknown start argument prints usage"
  assert_missing "$P/.studio/overnight.lock" "an unknown start argument takes no lock"
  assert_eq 0 "$(calls)" "an unknown start argument launches no session"
}

test_overnight_reclaim_race() {
  fixture race; live_dummy; export DUMMY
  printf 'pid=999999\nrun=x\nstarted=y\n' > "$P/.studio/overnight.lock"
  STUDIO_OVERNIGHT_RACE_HOOK='printf "pid=%s\nrun=z\nstarted=y\n" "$DUMMY" > "$LOCK"'
  export STUDIO_OVERNIGHT_RACE_HOOK
  run_start
  unset STUDIO_OVERNIGHT_RACE_HOOK
  kill "$DUMMY" 2>/dev/null; wait "$DUMMY" 2>/dev/null
  assert_eq 2 "$RS_STATUS" "a lock retaken mid-reclaim exits 2"
  assert_contains "$RS_ERR" "lock taken by another start" "the loser says so"
  assert_contains "$P/.studio/overnight.lock" "^pid=$DUMMY$" "the other start's lock is not removed"
  assert_eq 0 "$(calls)" "the loser launches no session"
}
# A live run's lock found mid-reclaim (its holder took it after this start's
# preflight) is put back and refused by name; its stop flag is left alone.
test_overnight_reclaim_finds_live_lock() {
  fixture racelive; live_dummy; export DUMMY
  printf 'pid=999999\nrun=x\nstarted=y\n' > "$P/.studio/overnight.lock"
  STUDIO_OVERNIGHT_RACE_HOOK='printf "pid=%s\nrun=z\nstarted=y\n" "$DUMMY" > "$LOCK"; printf "operator stop\n" > "$STOP_FILE"'
  export STUDIO_OVERNIGHT_RACE_HOOK
  run_start
  unset STUDIO_OVERNIGHT_RACE_HOOK
  kill "$DUMMY" 2>/dev/null; wait "$DUMMY" 2>/dev/null
  assert_eq 2 "$RS_STATUS" "a live lock found mid-reclaim exits 2"
  assert_contains "$RS_ERR" "a run is live: single-plan (z, pid $DUMMY)" "the refusal names the live run and its pid"
  assert_contains "$P/.studio/overnight.lock" "^pid=$DUMMY$" "the live lock is put back unchanged"
  assert_contains "$P/.studio/overnight.stop" "^operator stop$" "the live run's stop flag is left alone"
  assert_eq "" "$(ls "$P"/.studio/overnight.lock.stale.* 2>/dev/null)" "no stale copy is left behind"
  assert_eq 0 "$(calls)" "the loser launches no session"
}

test_overnight_first_use_ignores() {
  fixture ign
  scenario "stage execute; ledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_contains "$P/.studio/reports/.gitignore" "^\*$" "reports/ ignores everything in it"
  assert_contains "$P/.git/info/exclude" "^\.studio/overnight\.lock$" "the lock is excluded locally"
  assert_contains "$P/.git/info/exclude" "^\.studio/overnight\.stop$" "the stop file is excluded locally"
  assert_eq "" "$(cd "$P" && git status --porcelain -- .gitignore .studio/reports)" "no tracked file changes"
}

# done_scenario — the four units of a two-task plan.
done_scenario() {
  scenario "stage execute; task 1/2; ledger T1 complete a..b; cost 2" \
           "task 2/2; ledger T2 complete b..c; ledger T2 Ruling: kept x — y — z; cost 2.25" \
           "ledger final review done; cost 3" \
           "ledger P1 Play: jump on the box; ledger shipped https://github.com/o/r/pull/9; stage idle; task -; cost 1"
}

test_overnight_sequence_to_done() {
  fixture done; done_scenario; run_start
  d="$(last_run_dir)"
  assert_eq 0 "$RS_STATUS" "a shipped run exits 0"
  assert_eq 4 "$(calls)" "four sessions: two tasks, final review, finish"
  for f in 1-T1 2-T2 3-final-review 4-finish; do assert_file "$d/$f.jsonl" "session log $f.jsonl"; assert_file "$d/$f.err" "stderr $f.err"; done
  assert_eq "8.25" "$(awk -F'\t' '{ s += $4 } END { print s }' "$d/units.tsv")" "spend sums each session's total_cost_usd"
  assert_eq "done" "$(awk -F'\t' 'END { print $7 }' "$d/units.tsv")" "the last unit's outcome is done"
  assert_eq "0 0 0 0" "$(awk -F'\t' '{ printf "%s%s", (NR > 1 ? " " : ""), $6 }' "$d/units.tsv")" "a session that ends on time is never marked timed_out"
}

test_overnight_launch_argv() {
  fixture argv; done_scenario; run_start
  a="$CALLS/1.argv"
  deny="$REPO_ROOT/studios/game-dev/bin/overnight-deny.txt"
  # claude-gd passes its argv through, so the stub sees -p, then the prompt.
  assert_eq "-p" "$(sed -n 1p "$a")" "the session runs headless (-p)"
  assert_eq "/game-dev:execute --one" "$(sed -n 2p "$a")" "the prompt is the first argument after -p (D1)"
  for f in "--output-format" "stream-json" "--verbose" "--permission-mode" "auto" "--permission-prompts" "none" "--max-budget-usd" "25"; do
    assert_contains "$a" "^$f\$" "argv has $f as its own element"
  done
  assert_contains "$a" "^Bash(git push --force:\*)\$" "a deny rule with spaces is one element"
  assert_eq "--model" "$(sed -n 3p "$a")" "--model is element 3 (D6)"
  assert_eq "sonnet" "$(sed -n 4p "$a")" "task units default to model_task"
  grep -v '^#' "$deny" | grep . | grep -v '{merge_basename}' | sed 's/{default_branch}/main/g' > "$TMP/rules.txt"
  R="$(grep -c . "$TMP/rules.txt")"
  assert_eq "$(printf -- '--disallowedTools\n'; cat "$TMP/rules.txt")" \
    "$(tail -n "$((R + 1))" "$a")" "--disallowedTools is the last option, followed by every rule in file order"
  # The -C and gh api forms a mid-command force-push or remote delete takes (AC16).
  for r in 'Bash(git -C * push -f*)' 'Bash(git -C * push --force*)' 'Bash(git -C * push * -f*)' \
           'Bash(gh api * -X DELETE*)' 'Bash(gh api * --method DELETE*)' 'Bash(gh api --method DELETE*)'; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qxF -- "$r" "$a"; then _pass "argv denies $r"; else _fail "argv denies $r"; fi
  done
  assert_eq "1" "$(cat "$CALLS/1.env")" "OMEGA_AUTOPILOT=1 reaches the session"
  assert_eq "$P" "$(cat "$CALLS/1.pwd")" "every session starts in START_DIR"
}

# Final fix wave (AC19): a single-plan run never uses the manifest mode's
# LAUNCH_ENV, UNIT_CWD or LDIR inherited from the user's environment.
test_overnight_ignores_inherited_lane_vars() {
  fixture hostile
  LAUNCH_ENV="OMEGA_AUTOPILOT=hostile; : > '$CALLS/pwned'"; UNIT_CWD="$TMP"; LDIR="$TMP/hostile-ldir"
  export LAUNCH_ENV UNIT_CWD LDIR
  mkdir -p "$LDIR"
  run_start --dry-run
  assert_contains "$RS_OUT" "OMEGA_AUTOPILOT=1 claude-gd -p '/game-dev:execute --one'" "the dry run's launch line ignores an inherited LAUNCH_ENV"
  done_scenario; run_start
  unset LAUNCH_ENV UNIT_CWD LDIR
  assert_eq "1" "$(cat "$CALLS/1.env")" "an inherited LAUNCH_ENV is never evaluated"
  assert_missing "$CALLS/pwned" "nothing in it runs"
  assert_eq "$P" "$(cat "$CALLS/1.pwd")" "an inherited UNIT_CWD never moves the session"
  assert_missing "$TMP/hostile-ldir/cpid" "an inherited LDIR gets no cpid"
  assert_missing "$TMP/hostile-ldir/wpid" "nor a wpid"
}

test_overnight_retry_then_no_progress() {
  fixture retry; scenario "cost 1" "cost 1"; run_start
  d="$(last_run_dir)"
  assert_eq 1 "$RS_STATUS" "no progress exits 1"
  assert_eq 2 "$(calls)" "one retry, then stop"
  assert_file "$d/2-T1-retry.jsonl" "the retry is labelled T1-retry"
  assert_contains "$d/report.md" "no progress on T1" "the ending names the unit"
  assert_eq "noprog noprog" "$(awk -F'\t' '{ printf "%s%s", (NR > 1 ? " " : ""), $7 }' "$d/units.tsv")" "each no-progress unit's row says noprog"
}

# A session that ended its turn with background work running: print mode
# kills that work 600 s later and says so on stderr (phoenix
# mob-composer-parity, 2026-10-03). The unit is named `orphaned`, not
# `noprog`; it still spends a retry, and the ending keeps its prefix.
test_overnight_orphaned_unit() {
  fixture orph; scenario "cost 1; orphan" "cost 1"; run_start
  d="$(last_run_dir)"
  assert_eq 2 "$(calls)" "an orphaned unit spends the retry like any no-progress unit"
  assert_eq "orphaned noprog" "$(awk -F'\t' '{ printf "%s%s", (NR > 1 ? " " : ""), $7 }' "$d/units.tsv")" \
    "the orphaned unit's row says orphaned, the plain one noprog"
  assert_contains "$d/report.md" "^Ending: no progress on T1$" "the last unit was plain no progress"
  fixture orph2; scenario "cost 1" "cost 1; orphan"; run_start
  assert_contains "$(last_run_dir)/report.md" \
    "^Ending: no progress on T1 (orphaned: the session ended its turn with background work running)$" \
    "an orphaned last unit names the cause in the ending"
}

# D8: stage execute with task -, or 0/N, is still the first task.
test_overnight_label_t1() {
  for t in - 0/2; do
    fixture lab; ( cd "$P" && sh "$STATE_BIN" set stage execute && sh "$STATE_BIN" set task "$t" \
      && git add -A && git -c user.name=t -c user.email=t@t commit -qm x ) >/dev/null
    scenario "cost 1" "cost 1"; run_start
    assert_file "$(last_run_dir)/1-T1.jsonl" "stage execute, task $t: the unit is T1"
    rm -rf "$P" "$CALLS" "$TMP_WT"
  done
}

test_overnight_progress_resets_retry() {
  fixture reset; scenario "cost 1" "stage execute; task 1/2" "cost 1" "cost 1"; run_start
  assert_eq 4 "$(calls)" "progress resets the retry count"
  assert_contains "$(last_run_dir)/report.md" "no progress on T2" "the stuck unit is T2"
}

test_overnight_retries_zero() {
  fixture r0 '{ "overnight": { "retries": 0 } }'; scenario "cost 1"; run_start
  assert_eq 1 "$(calls)" "retries 0 stops after the first no-progress session"
}

test_overnight_stop_line() {
  fixture stopl; scenario "stage execute; ledger Stop: no Godot binary (studio-test exit 2)"; run_start
  assert_eq 1 "$RS_STATUS" "a Stop: line exits 1"
  assert_eq 1 "$(calls)" "a Stop: line is never retried"
  assert_eq stop "$(awk -F'\t' 'NR == 1 { print $7 }' "$(last_run_dir)/units.tsv")" "the stopped unit's row says stop"
  assert_contains "$(last_run_dir)/report.md" "stop: no Godot binary (studio-test exit 2)" "the reason is printed verbatim"
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"story_state","story":"-","state":"stopped","why":"stop: no Godot binary (studio-test exit 2)"}$' "the not-done ending is a stopped story_state with its why (R17)"
}

test_overnight_copied_stop_not_new() {
  fixture copied
  ( cd "$P" && sh "$STATE_BIN" ledger "Stop: an old reason" && git add -A && git -c user.name=t -c user.email=t@t commit -qm old ) >/dev/null
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b" \
           "wtledger Stop: fresh reason"
  run_start
  assert_eq 2 "$(calls)" "a Stop: line the new worktree copied is not new"
  assert_contains "$(last_run_dir)/report.md" "stop: fresh reason" "a Stop: line written in the feature worktree stops the run"
}

test_overnight_run_budget() {
  fixture budget '{ "overnight": { "session_usd": 2, "run_usd": 5 } }'
  scenario "stage execute; task 1/3; cost 2" "task 2/3; cost 2" "task 3/3; cost 2"; run_start
  assert_eq 2 "$(calls)" "the run stops before a launch that could pass run_usd"
  assert_contains "$(last_run_dir)/report.md" "stop: run budget" "budget is the ending"
}

test_overnight_cost_unknown() {
  fixture nocost; scenario "stage execute; task 1/1; nocost" "ledger final review done" \
    "ledger shipped https://x/pull/2; stage idle; task -"
  run_start
  assert_eq "unknown" "$(awk -F'\t' 'NR == 1 { print $4 }' "$(last_run_dir)/units.tsv")" "a session with no result event costs unknown"
}

test_overnight_unexpected_stage() {
  fixture stage; scenario "stage idle"; run_start
  assert_contains "$(last_run_dir)/report.md" "stop: unexpected stage idle" "idle without shipped stops"
}

test_overnight_unknown_label_stops() {
  fixture badlabel; scenario "stage execute; task 1/1"
  STUDIO_OVERNIGHT_LABEL=bogus; export STUDIO_OVERNIGHT_LABEL
  run_start
  unset STUDIO_OVERNIGHT_LABEL
  assert_eq 1 "$RS_STATUS" "an unknown unit label is a runner error"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: runner error (exit 3)$" "the report names the runner error"
  assert_missing "$CALLS/1.argv" "no claude session launches with an empty --model"
}

test_overnight_overhead() {
  fixture over; done_scenario; run_start
  g1=$(( $(cat "$CALLS/2.t0") - $(cat "$CALLS/1.t1") ))
  g2=$(( $(cat "$CALLS/3.t0") - $(cat "$CALLS/2.t1") ))
  g=$g1; [ "$g2" -lt "$g" ] && g=$g2
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$g" -le 5 ]; then _pass "runner overhead between units <= 5 s (min of two: ${g}s)"; else _fail "runner overhead ${g}s > 5 s"; fi
}

# start_bg [ARGS] — the runner in the background with job control on, so it
# is not started with SIGINT ignored (POSIX ignores it for async lists in a
# non-interactive shell, and an ignored-on-entry signal cannot be trapped).
start_bg() {
  set -m 2>/dev/null
  ( cd "$P" && exec sh "$RUNNER" start "$@" ) > "$TMP/bg.out" 2> "$TMP/bg.err" &
  RPID=$!
  set +m 2>/dev/null
}
# wait_for FILE — up to 10 s.
wait_for() { _i=0; while [ ! -e "$1" ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done; }
bg_status() { BG_STATUS=0; wait "$RPID" || BG_STATUS=$?; }
# ---- #27: single-plan holds ----
# holds_on SECS — holds on for the next run: hold_minutes 5, a deadline of
# SECS seconds, a 1 s poll. holds_off — the suite's default (holds off).
holds_on() {
  STUDIO_OVERNIGHT_HOLD_MINUTES=5; STUDIO_OVERNIGHT_HOLD_SECONDS="$1"; STUDIO_OVERNIGHT_POLL_SECONDS=1
  export STUDIO_OVERNIGHT_HOLD_MINUTES STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
}
holds_off() { STUDIO_OVERNIGHT_HOLD_MINUTES=0; unset STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS; }
# wait_held SECS — up to SECS s for the newest run's control/-.held; R is
# the run dir.
wait_held() {
  _wh_i=0
  while [ "$_wh_i" -lt $(( $1 * 5 )) ]; do
    R="$(last_run_dir)"; [ -n "$R" ] && [ -f "$R/control/-.held" ] && return 0
    sleep 0.2; _wh_i=$((_wh_i + 1))
  done
  R="$(last_run_dir)"; return 1
}
# bg_alive — the start_bg runner runs and is not a zombie.
bg_alive() {
  kill -0 "$RPID" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$RPID" 2>/dev/null)" in Z*|'') return 1 ;; esac
}
# bg_end SECS MSG — passes MSG when the start_bg run ends within SECS (else
# KILLs it and fails); then bg_status.
bg_end() {
  _be_i=0; while bg_alive && [ "$_be_i" -lt "$1" ]; do sleep 1; _be_i=$((_be_i + 1)); done
  TESTS_RUN=$((TESTS_RUN + 1))
  if bg_alive; then kill -KILL "$RPID" 2>/dev/null; _fail "$2 (still running after $1 s)"; else _pass "$2"; fi
  bg_status
}
# unit_col N — column N of the newest run's units.tsv, space-joined.
unit_col() { awk -F'\t' -v c="$1" '{ printf "%s%s", (NR > 1 ? " " : ""), $c }' "$(last_run_dir)/units.tsv"; }
# ISO1 — one unit's actions that isolate the run (a feature worktree) and
# finish T1 of 2.
ISO1="stage execute; branch feat; task 1/2; wtledger T1 complete a..b"

test_overnight_timeout() {
  fixture tmo; scenario "stage execute; sleep 30" "cost 1"
  STUDIO_OVERNIGHT_SESSION_SECONDS=1; export STUDIO_OVERNIGHT_SESSION_SECONDS
  run_start; unset STUDIO_OVERNIGHT_SESSION_SECONDS
  assert_eq 1 "$(awk -F'\t' 'NR == 1 { print $6 }' "$(last_run_dir)/units.tsv")" "a session past its time is marked timed_out"
  assert_missing "$CALLS/1.t1" "the watchdog cut the session short during its sleep 30"
  assert_eq short "$(awk -F'\t' 'NR == 1 { print ($5 < 0.5 ? "short" : $5) }' "$(last_run_dir)/units.tsv")" "the timed-out session took well under 30 s"
  assert_eq progress "$(awk -F'\t' 'NR == 1 { print $7 }' "$(last_run_dir)/units.tsv")" "a timed-out session that moved the signature counts as progress"
}

test_overnight_kill_after_grace() {
  fixture grace '{ "overnight": { "kill_grace_seconds": 5 } }'
  scenario "ignoreterm; hang" "ignoreterm; hang"
  STUDIO_OVERNIGHT_SESSION_SECONDS=1; export STUDIO_OVERNIGHT_SESSION_SECONDS
  run_start; unset STUDIO_OVERNIGHT_SESSION_SECONDS
  assert_eq 2 "$(calls)" "a session that ignores TERM is killed after the grace, and counted"
  assert_contains "$(last_run_dir)/report.md" "^Ending: timed out on T1 (session_minutes " "two killed sessions with no progress stop the run, named as timed out"
  assert_eq "timed out" "$(awk -F'\t' 'NR == 1 { print $7 }' "$(last_run_dir)/units.tsv")" "a unit the watchdog ended with no progress is recorded timed out, not noprog"
}

test_overnight_stop_file() {
  fixture stopf; scenario "stage execute; sleep 2; task 1/3" "task 2/3" "task 3/3"
  start_bg; wait_for "$CALLS/1.t0"
  out="$(cd "$P" && sh "$RUNNER" stop)"; st=$?
  assert_eq 0 "$st" "stop exits 0 while a run is live"
  bg_status
  assert_eq 1 "$(calls)" "the running unit finishes and no other starts"
  assert_contains "$(last_run_dir)/report.md" "stopped by user" "the ending says so"
  assert_missing "$P/.studio/overnight.stop" "the stop file is removed at the end"
}

test_overnight_sigterm() {
  fixture term; scenario "stage execute; sleep 2; task 1/3; exit 7" "task 2/3"
  start_bg; wait_for "$CALLS/1.t0"; kill -TERM "$RPID"; bg_status
  assert_eq 1 "$(calls)" "SIGTERM to the runner: the running unit finishes, then the run stops"
  assert_eq 7 "$(awk -F'\t' 'NR == 1 { print $3 }' "$(last_run_dir)/units.tsv")" "the session's exit code survives the interrupted wait"
  assert_eq 1 "$BG_STATUS" "a user stop exits 1"
}

test_overnight_sigint() {
  fixture int; scenario "stage execute; sleep 2; task 1/3" "task 2/3"
  start_bg; wait_for "$CALLS/1.t0"; kill -INT "$RPID"; bg_status
  assert_eq 1 "$(calls)" "SIGINT to the runner: the running unit finishes, then the run stops"
  assert_contains "$(last_run_dir)/report.md" "stopped by user" "SIGINT is a user stop"
}

test_overnight_sighup() {
  fixture hup '{ "overnight": { "kill_grace_seconds": 5 } }'
  scenario "stage execute; sleep 30" "task 1/2"
  start_bg; wait_for "$CALLS/1.t0"
  spid="$(cat "$CALLS/1.pid")"
  kill -HUP "$RPID"; bg_status
  assert_eq 1 "$BG_STATUS" "a closed terminal exits 1"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: terminal closed (SIGHUP)$" "the ending names the closed terminal"
  assert_missing "$P/.studio/overnight.lock" "the lock is gone"
  assert_eq dead "$(kill -0 "$spid" 2>/dev/null && echo live || echo dead)" "the running session was ended before unlock"
  assert_eq "" "$(pgrep -g "$spid" 2>/dev/null)" "nothing in the session's process group survives"
  assert_eq 1 "$(calls)" "no further unit starts"
}

test_overnight_stop_no_run() {
  fixture norun
  assert_status 1 "stop with no run exits 1" -- sh -c "cd '$P' && sh '$RUNNER' stop"
}

test_overnight_inhibitor() {
  [ "$(uname -s)" = Darwin ] || { printf '  skip caffeinate case (not Darwin)\n'; return 0; }
  fixture caf; done_scenario; run_start
  pid="$(sed -n 's/^pid=//p' "$CALLS/1.lock")"
  assert_eq "-i -w $pid" "$(cat "$CALLS/caffeinate.args")" "caffeinate -i -w <runner pid> is held for the run"
  assert_contains "$CALLS/1.caf" "^alive$" "caffeinate is alive during the first unit"
  assert_contains "$CALLS/4.caf" "^alive$" "caffeinate is still alive during the last unit (AC13)"
  cpid="$(cat "$CALLS/caffeinate.pid")"; _i=0
  while kill -0 "$cpid" 2>/dev/null && [ "$_i" -lt 30 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_eq dead "$(kill -0 "$cpid" 2>/dev/null && echo live || echo dead)" "caffeinate ends with the run"
}

# A watchdog whose claim mkdir fails for a reason other than EEXIST (the run
# directory is gone) still ends the session at its deadline.
test_overnight_claim_without_run_dir() {
  fixture noclaim; scenario "stage execute; rmrundir; sleep 30"
  STUDIO_OVERNIGHT_SESSION_SECONDS=1; export STUDIO_OVERNIGHT_SESSION_SECONDS
  t0="$(date +%s)"; run_start; t1="$(date +%s)"; unset STUDIO_OVERNIGHT_SESSION_SECONDS
  assert_missing "$CALLS/1.t1" "the session was cut short at its deadline"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ $((t1 - t0)) -lt 20 ]; then _pass "the run did not wait out the session's sleep 30 ($((t1 - t0))s)"; else _fail "the run took $((t1 - t0))s: the watchdog did not act"; fi
}

# make_minbin — $TMP/minbin: only what the runner needs, plus the stubs.
make_minbin() {
  mkdir -p "$TMP/minbin"
  for u in sh git sed awk grep sort comm date ps pkill kill sleep cat mkdir rm touch \
           head tail tr cut ln dirname basename readlink wc uname mktemp cp mv chmod env printf; do
    p="$(command -v "$u" 2>/dev/null)" && case "$p" in /*) ln -sf "$p" "$TMP/minbin/$u" ;; esac
  done
  for f in claude claude-gd gh; do ln -sf "$FAKE/$f" "$TMP/minbin/$f"; done
}

test_overnight_no_inhibitor() {
  # A PATH holding only what the runner needs, and no caffeinate or
  # systemd-inhibit.
  fixture nocaf; done_scenario
  make_minbin
  RS_STATUS=0
  ( cd "$P" && PATH="$TMP/minbin" sh "$RUNNER" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 0 "$RS_STATUS" "the run continues without a sleep inhibitor"
  assert_contains "$TMP/rs.err" "no sleep inhibitor" "one warning names the missing inhibitor"
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"run_ended","ending":"done"' "studio-event runs under the minimal PATH"
  assert_not_contains "$TMP/rs.err" "events.jsonl" "no event write failed"
}

test_overnight_report_done() {
  fixture rep; done_scenario; run_start
  R="$(last_run_dir)/report.md"
  assert_contains "$R" "^Ending: done$" "report: the ending"
  assert_contains "$R" "^PR: https://github.com/o/r/pull/9$" "report: the PR URL from the shipped line"
  assert_contains "$R" "^Spent: \\\$8.25$" "report: the total spend"
  assert_contains "$R" "| 3 | final-review | 0 | 3 |" "report: one row per unit with exit and cost"
  assert_contains "$R" "T2 Ruling: kept x — y — z" "report: every Ruling: line, verbatim with its cost"
  assert_contains "$R" "P1 Play: jump on the box" "report: the play list"
  assert_not_contains "$R" "^## Resume" "report: no resume command when done"
}

test_overnight_report_anchors() {
  fixture anch
  scenario "stage execute; task 1/1; ledger T1 Review: reworded the Ruling: and P1 Play: lines" \
           "ledger final review done; ledger Ruling: plain one — y — z" \
           "ledger P1 Play: jump; ledger shipped https://x/pull/5; stage idle; task -"
  run_start
  R="$(last_run_dir)/report.md"
  assert_eq 0 "$(grep -c 'reworded the Ruling:' "$R")" "report: a line that only mentions Ruling: or Play: is listed in neither section"
  assert_contains "$R" "^- [0-9-]* Ruling: plain one — y — z$" "report: a Ruling: line with no task label is listed"
  assert_contains "$R" "^- [0-9-]* P1 Play: jump$" "report: the play line is listed"
}

test_overnight_resume_quote() {
  fixture "q'uote"; scenario "cost 1" "cost 1"; run_start
  R="$(last_run_dir)/report.md"
  q="$(printf '%s' "$P" | sed "s/'/'\\\\''/g")"
  assert_eq "cd '$q' && '$RUNNER' start" "$(tail -n 1 "$R")" "report: a ' in the path is escaped in the resume command"
  assert_eq "$P" "$(sh -c "$(tail -n 1 "$R" | sed 's/ && .*//'); pwd -P")" "report: the escaped cd reaches the checkout"
}

test_overnight_report_not_done() {
  fixture repn; scenario "cost 1" "nocost"; run_start
  R="$(last_run_dir)/report.md"
  assert_contains "$R" "^Ending: no progress on T1$" "report: the stop reason"
  assert_contains "$R" "cost unknown" "report: an unknown cost is said next to the total"
  assert_contains "$R" "^## Resume" "report: a resume section when not done"
  assert_contains "$R" "cd '$P' && '$RUNNER' start" "report: the absolute resume command (D16)"
  assert_contains "$R" "^PR: none$" "report: no PR yet"
}

test_overnight_report_runner_error() {
  fixture err; scenario "stage execute; task 1/2; rotsv"; run_start
  R="$(last_run_dir)/report.md"
  assert_eq 1 "$RS_STATUS" "a runner error exits 1"
  assert_contains "$R" "^Ending: stop: runner error (exit 3)$" "the EXIT trap writes the report"
  assert_missing "$P/.studio/overnight.lock" "the EXIT trap unlocks"
}

test_overnight_crash_resume() {
  fixture crash; scenario "stage execute; task 1/2; sleep 30" "task 2/2" "ledger final review done" \
    "ledger shipped https://x/pull/3; stage idle; task -"
  start_bg; wait_for "$CALLS/1.t0"
  # Crash mid-session: wait for the stub's own sleep, so the kill lands in it.
  spid="$(cat "$CALLS/1.pid")"; _i=0
  while [ -z "$(pgrep -P "$spid" 2>/dev/null)" ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
  # Record the runner's children (the session and the watchdog) while it lives.
  kids="$(pgrep -P "$RPID" 2>/dev/null | tr '\n' ' ')"
  kill -KILL "$RPID"; wait "$RPID" 2>/dev/null
  # The killed runner's orphans, by recorded pid only — never a machine-wide
  # pkill, which would hit a real overnight run's watchdog. The session's
  # group is the stub's pid (D6); the watchdog and its sleep share the
  # runner's group, which start_bg made $RPID.
  kill -KILL -"$spid" 2>/dev/null; kill -KILL -"$RPID" 2>/dev/null
  for k in $kids; do pkill -KILL -P "$k" 2>/dev/null; kill -KILL "$k" 2>/dev/null; done
  _i=0  # killed orphans are reaped by init, not by us: give it a moment
  while [ -n "$(for k in $spid $kids; do kill -0 "$k" 2>/dev/null && echo "$k"; done)" ] && [ "$_i" -lt 30 ]; do sleep 0.1; _i=$((_i + 1)); done
  assert_eq "" "$(for k in $spid $kids; do kill -0 "$k" 2>/dev/null && echo "$k"; done)" "no recorded orphan survives the cleanup"
  assert_file "$P/.studio/overnight.lock" "a killed runner leaves its lock"
  run_start
  assert_eq 0 "$RS_STATUS" "the next start reclaims the stale lock and resumes from state"
  assert_contains "$RS_ERR" "reclaiming stale lock" "with a warning"
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "and writes the morning report"
}

test_overnight_status() {
  fixture stat; scenario "stage execute; task 1/2; cost 1.5" "sleep 3; task 2/2"
  start_bg; wait_for "$CALLS/2.t0"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out"; st=$?
  assert_eq 0 "$st" "status exits 0 while a run is live"
  assert_contains "$TMP/st.out" "^run: $P/.studio/reports/overnight-" "status: run dir"
  assert_contains "$TMP/st.out" "^unit: T2$" "status: the running unit"
  assert_contains "$TMP/st.out" "^task: 1/2$" "status: task k/N"
  assert_contains "$TMP/st.out" "^spent: \\\$1.50$" "status: spend so far"
  assert_contains "$TMP/st.out" "^pid: $RPID$" "status: the lock pid"
  assert_contains "$TMP/st.out" "^now: 2-T2 · [0-9]*[sm] · " "status: the running unit's elapsed time and activity"
  assert_contains "$TMP/st.out" "^gate: free$" "status: the gate lock"
  assert_contains "$TMP/st.out" "^env: cpu " "status: the resource readout"
  assert_eq 1 "$(awk '/^gate:/ { g = NR } /^env:/ { e = NR } END { print (g && e > g) ? 1 : 0 }' "$TMP/st.out")" "status: the readout comes after the existing lines"
  ( cd "$P" && sh "$RUNNER" stop ) >/dev/null; bg_status
  assert_status 1 "status with no run exits 1" -- sh -c "cd '$P' && sh '$RUNNER' status"
  ( cd "$P" && sh "$RUNNER" status ) > "$TMP/st.out" 2>&1
  assert_contains "$TMP/st.out" "^no run — the last run: $P/.studio/reports/overnight-" "status with no run names the last run"
  assert_contains "$TMP/st.out" "^ended (stopped by user) — report: $P/.studio/reports/overnight-.*/report.md — resume: " "and how it ended, its report and how to resume"
}

test_overnight_check_unit() {
  fixture chk
  ( cd "$P" && sh "$STATE_BIN" set stage execute && sh "$STATE_BIN" set task 1/2 \
      && sh "$STATE_BIN" ledger "check requested" \
      && git add -A && git -c user.name=t -c user.email=t@t commit -qm chk ) >/dev/null 2>&1
  scenario "ledger check done none" "task 2/2" "ledger final review done" "stage idle; task -; ledger shipped x"
  run_start
  assert_eq "check T2 final-review finish" "$(unit_col 2)" "a requested, undone check runs first, then T2"
  assert_eq opus "$(sed -n '/^--model$/{n;p;}' "$CALLS/1.argv")" "the check unit gets model_final"
  assert_eq "progress progress progress done" "$(unit_col 7)" "a check unit that ledgers check done is progress"
  fixture chk2
  ( cd "$P" && sh "$STATE_BIN" set stage execute && sh "$STATE_BIN" set task 1/2 \
      && sh "$STATE_BIN" ledger "check requested" && sh "$STATE_BIN" ledger "check done none" \
      && git add -A && git -c user.name=t -c user.email=t@t commit -qm chk ) >/dev/null 2>&1
  scenario "task 2/2" "ledger final review done" "stage idle; task -; ledger shipped x"
  run_start
  assert_eq "T2 final-review finish" "$(unit_col 2)" "a done check is not run again"
  fixture chk3
  ( cd "$P" && sh "$STATE_BIN" set stage execute && sh "$STATE_BIN" set task 1/2 \
      && sh "$STATE_BIN" ledger "check requested" && sh "$STATE_BIN" ledger "check done none" \
      && sh "$STATE_BIN" ledger "adopt reset 2026-10-04" && sh "$STATE_BIN" ledger "check requested" \
      && git add -A && git -c user.name=t -c user.email=t@t commit -qm chk ) >/dev/null 2>&1
  scenario "ledger check done none" "task 2/2" "ledger final review done" "stage idle; task -; ledger shipped x"
  run_start
  assert_eq "check T2 final-review finish" "$(unit_col 2)" "a check done before an adopt reset does not suppress the re-requested check"
}

test_overnight_adopt_config_refusals() {
  fixture adc '{"worktree_setup_minutes": 0}'
  run_start --dry-run
  assert_eq 2 "$RS_STATUS" "worktree_setup_minutes 0: exit 2"
  assert_contains "$RS_ERR" "config overnight.worktree_setup_minutes must be from 1 to 120, got 0" "names the key and range"
  fixture adc2 '{"gate_command": "a\\b"}'
  run_start --dry-run
  assert_eq 2 "$RS_STATUS" "a backslash in gate_command: exit 2"
  assert_contains "$RS_ERR" "gate_command" "names gate_command"
  assert_contains "$RS_ERR" "gate_command must not contain a backslash.*script" "the refusal names the reason and the way out"
  fixture adc3 '{"gate_command": "make test", "worktree_setup": "make setup", "worktree_setup_minutes": 5}'
  run_start --dry-run
  assert_eq 0 "$RS_STATUS" "valid adopt keys pass"
}

test_overnight_models_by_unit() {
  fixture models '{"overnight": {"model_final": "opus-x", "model_finish": "son.1"}}'
  scenario "stage execute; task 1/1; ledger T1 complete" "ledger final review done" "ledger shipped https://x/pr/1; stage idle"
  run_start
  assert_eq 0 "$RS_STATUS" "the run ends done"
  assert_eq sonnet "$(sed -n 4p "$CALLS/1.argv")" "a task unit gets model_task (default sonnet)"
  assert_eq opus-x "$(sed -n 4p "$CALLS/2.argv")" "the final review gets model_final"
  assert_eq son.1 "$(sed -n 4p "$CALLS/3.argv")" "the finish gets model_finish"
}
test_overnight_config_refusals_v2() {
  fixture cfgv2 '{"overnight": {"max_lanes": 9, "run_usd": 0.5, "model_task": "Sonnet 4"}, "merge_command": "missing.sh"}'
  run_start --dry-run
  assert_eq 2 "$RS_STATUS" "refused"
  assert_contains "$RS_ERR" "overnight.max_lanes" "max_lanes out of range"
  assert_contains "$RS_ERR" "run_usd" "run_usd between 0 and 1"
  assert_contains "$RS_ERR" "model_task" "a model with a space"
  assert_contains "$RS_ERR" "merge_command" "merge_command without <pr> and not an executable under the checkout"
}
test_overnight_default_branch_required() {
  fixture nohead
  git -C "$P" remote set-head origin -d >/dev/null 2>&1
  run_start --dry-run
  assert_eq 2 "$RS_STATUS" "no origin/HEAD is a refusal"
  assert_contains "$RS_ERR" "origin/HEAD is not set" "the refusal says how to fix it"
}
test_overnight_deny_merge_basename() {
  fixture denymb '{"merge_command": "scripts/merge.sh <pr>"}'
  mkdir -p "$P/scripts"; printf '#!/bin/sh\n' > "$P/scripts/merge.sh"; chmod +x "$P/scripts/merge.sh"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m m ) >/dev/null 2>&1
  run_start --dry-run
  assert_eq 0 "$RS_STATUS" "a valid merge_command passes"
  assert_contains "$RS_OUT" "'Bash(\*merge.sh\*)'" "the merge program is denied by basename"
  assert_contains "$RS_OUT" "'Bash(gh api \*pulls/\*/merge\*)'" "the merge endpoint is denied"
}
# dr DIR [ARGS] — deny-rules from DIR; stdout dr.out, stderr dr.err, exit DR_STATUS.
dr() {
  _d="$1"; shift; DR_STATUS=0
  ( cd "$_d" && sh "$RUNNER" deny-rules "$@" ) > "$TMP/dr.out" 2> "$TMP/dr.err" || DR_STATUS=$?
}
DENY_SRC="$REPO_ROOT/studios/game-dev/bin/overnight-deny.txt"
test_overnight_deny_rules_basic() {
  fixture drb '{"merge_command": "scripts/merge.sh <pr>"}'
  dr "$P"
  assert_eq 0 "$DR_STATUS" "deny-rules exits 0 in a project"
  assert_eq "$(grep -Evc '^[[:space:]]*(#|$)' "$DENY_SRC")" "$(grep -c . "$TMP/dr.out")" "every rule printed once"
  assert_contains "$TMP/dr.out" '^Bash(git push \* main)$' "{default_branch} expanded from origin/HEAD"
  assert_contains "$TMP/dr.out" '^Bash(\*merge\.sh\*)$' "{merge_basename} is the first word's basename"
  assert_not_contains "$TMP/dr.out" '{' "no placeholder left"
  assert_eq "" "$(cat "$TMP/dr.err")" "no notes when both values exist"
}
test_overnight_deny_rules_no_origin_head() {
  fixture drh; git -C "$P" remote set-head origin -d >/dev/null 2>&1
  dr "$P"
  assert_eq 0 "$DR_STATUS" "no origin/HEAD still exits 0"
  assert_not_contains "$TMP/dr.out" 'git push \* {default_branch}' "no raw placeholder"
  assert_not_contains "$TMP/dr.out" '^Bash(git push \* )$' "no rule with an empty branch"
  assert_eq "$(grep -v '^#' "$DENY_SRC" | grep . | grep -v '{default_branch}' | grep -vc '{merge_basename}')" \
    "$(grep -c . "$TMP/dr.out")" "only placeholder-free rules remain"
  assert_contains "$TMP/dr.err" 'deny-rules: no origin/HEAD in .* rules using {default_branch} dropped' "one note for {default_branch}"
  assert_contains "$TMP/dr.err" 'rules using {merge_basename} dropped' "one note for {merge_basename}"
  assert_eq 2 "$(grep -c . "$TMP/dr.err")" "exactly one note per dropped placeholder"
}
test_overnight_deny_rules_merge_basename() {
  fixture drm
  dr "$P"
  assert_eq 0 "$DR_STATUS" "no merge_command still exits 0"
  assert_eq "$(grep -v '^#' "$DENY_SRC" | grep . | grep -vc '{merge_basename}')" \
    "$(grep -c . "$TMP/dr.out")" "only the {merge_basename} rule is dropped"
  assert_contains "$TMP/dr.err" 'no merge_command in .*config.json .* rules using {merge_basename} dropped' "one note naming the config"
  assert_eq 1 "$(grep -c . "$TMP/dr.err")" "no {default_branch} note when origin/HEAD is set"
}
test_overnight_deny_rules_dir() {
  fixture drd '{"merge_command": "scripts/merge.sh <pr>"}'; mkdir -p "$TMP/elsewhere"
  dr "$TMP/elsewhere" --dir "$P"
  assert_eq 0 "$DR_STATUS" "--dir works from another directory"
  assert_contains "$TMP/dr.out" '^Bash(git push \* main)$' "values come from --dir, not the cwd"
  assert_contains "$TMP/dr.out" '^Bash(\*merge\.sh\*)$' "merge_command read from the work root's config"
  dr "$TMP/elsewhere" --dir="$P/docs"
  assert_contains "$TMP/dr.out" '^Bash(git push \* main)$' "--dir=PATH form, a subdirectory resolves to the work root"
  assert_contains "$TMP/dr.out" '^Bash(\*merge\.sh\*)$' "merge_command read from the work root's config"
}
test_overnight_deny_rules_outside_git() {
  mkdir -p "$TMP/plain"
  dr "$TMP/plain"
  assert_eq 0 "$DR_STATUS" "outside git and outside a studio project: exit 0"
  assert_eq 2 "$(grep -c . "$TMP/dr.err")" "two notes"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -e "$TMP/plain/.studio" ]; then _fail "deny-rules writes nothing"; else _pass "deny-rules writes nothing"; fi
}
test_overnight_deny_rules_empty_file() {
  mkdir -p "$TMP/drcopy"; cp -R "$REPO_ROOT/studios/game-dev/bin/." "$TMP/drcopy/"
  printf '# only a comment\n\n' > "$TMP/drcopy/overnight-deny.txt"
  st=0; ( cd "$TMP" && sh "$TMP/drcopy/studio-overnight" deny-rules ) >/dev/null 2>"$TMP/dr.err" || st=$?
  assert_eq 1 "$st" "a deny file with no rules exits 1"
  rm -f "$TMP/drcopy/overnight-deny.txt"
  st=0; ( cd "$TMP" && sh "$TMP/drcopy/studio-overnight" deny-rules ) >/dev/null 2>&1 || st=$?
  assert_eq 1 "$st" "a missing deny file exits 1"
}
test_overnight_deny_rules_usage() {
  fixture dru
  dr "$P" --bogus;            assert_eq 2 "$DR_STATUS" "an unknown argument exits 2"
  dr "$P" --dir;              assert_eq 2 "$DR_STATUS" "--dir without a value exits 2"
  dr "$P" --dir "$TMP/nope";  assert_eq 2 "$DR_STATUS" "--dir that is not a directory exits 2"
}
test_overnight_deny_rules_match_launch() {
  fixture drl; done_scenario; run_start
  sed '1,/^--disallowedTools$/d' "$CALLS/1.argv" > "$TMP/launch-rules.txt"
  dr "$P"
  assert_eq "$(cat "$TMP/launch-rules.txt")" "$(cat "$TMP/dr.out")" "deny-rules prints exactly the unit's rules"
}
REGL="$HOME/.claude-gamedev/runs/last"
# reg_keys FILE — the entry's keys in order, space-separated.
reg_keys() { sed 's/=.*//' "$1" | tr '\n' ' ' | sed 's/ $//'; }
test_overnight_origin_written() {
  fixture org; done_scenario; rm -f "$REGL"
  STUDIO_RUN_ORIGIN="multica:0b5f-12ab"; export STUDIO_RUN_ORIGIN
  run_start; unset STUDIO_RUN_ORIGIN
  assert_eq 0 "$RS_STATUS" "the run ends normally"
  assert_contains "$REGL" '^origin=multica:0b5f-12ab$' "origin= written and kept in runs/last"
  assert_eq "root start run pid started origin spec ended" "$(reg_keys "$REGL")" "origin= follows started=, then a single-plan run's spec= (#42), ended= is last"
  assert_not_contains "$RS_ERR" 'STUDIO_RUN_ORIGIN ignored' "a valid value draws no warning"
}
test_overnight_origin_absent_without_variable() {
  fixture orn; done_scenario; rm -f "$REGL"; unset STUDIO_RUN_ORIGIN
  run_start
  assert_eq "root start run pid started spec ended" "$(reg_keys "$REGL")" "without the variable there is no origin= line"
  STUDIO_RUN_ORIGIN=""; export STUDIO_RUN_ORIGIN
  fixture ore; done_scenario; rm -f "$REGL"; run_start; unset STUDIO_RUN_ORIGIN
  assert_not_contains "$REGL" '^origin=' "an empty variable writes no line"
  assert_not_contains "$RS_ERR" 'STUDIO_RUN_ORIGIN' "and no warning"
}
test_overnight_origin_refused() {
  long="$(printf '%0201d' 0 | tr 0 a)"; i=0
  for v in "has space" "a/b" "a=b" "a
b" "$long" "héllo"; do
    i=$((i + 1)); fixture "orr$i"; done_scenario; rm -f "$REGL"
    STUDIO_RUN_ORIGIN="$v"; export STUDIO_RUN_ORIGIN; run_start; unset STUDIO_RUN_ORIGIN
    assert_eq 0 "$RS_STATUS" "a refused origin still runs ($i)"
    assert_not_contains "$REGL" '^origin=' "no origin= line ($i)"
    assert_eq 1 "$(grep -c 'STUDIO_RUN_ORIGIN ignored' "$RS_ERR")" "exactly one warning ($i)"
  done
  fixture or200; done_scenario; rm -f "$REGL"
  STUDIO_RUN_ORIGIN="${long%a}"; export STUDIO_RUN_ORIGIN; run_start; unset STUDIO_RUN_ORIGIN
  assert_contains "$REGL" "^origin=${long%a}$" "200 bytes is accepted"
}
test_overnight_run_usd_default_uncapped() {
  fixture uncapped
  scenario "stage execute; task 1/1; ledger T1 complete; cost 400" "ledger final review done; cost 400" "ledger shipped u; stage idle; cost 1"
  run_start
  assert_eq 0 "$RS_STATUS" "run_usd 0 caps nothing: an \$801 run ends done"
}

test_overnight_hold_config_refused() {
  fixture hcf '{"overnight": {"hold_minutes": 1441}}'; refuse_case "hold_minutes 1441" "hold_minutes"
  fixture hcf '{"overnight": {"directive_chars": 499}}'; refuse_case "directive_chars 499" "directive_chars"
  for bad in abc 1441 -1 1.5; do
    fixture "hcm$bad"; STUDIO_OVERNIGHT_HOLD_MINUTES="$bad"
    refuse_case "STUDIO_OVERNIGHT_HOLD_MINUTES=$bad" "STUDIO_OVERNIGHT_HOLD_MINUTES"
  done
  STUDIO_OVERNIGHT_HOLD_MINUTES=0
  fixture hcs; STUDIO_OVERNIGHT_HOLD_SECONDS=1.5; export STUDIO_OVERNIGHT_HOLD_SECONDS
  refuse_case "STUDIO_OVERNIGHT_HOLD_SECONDS=1.5" "STUDIO_OVERNIGHT_HOLD_SECONDS"
  unset STUDIO_OVERNIGHT_HOLD_SECONDS
}
# run_start_hold VALUE — run_start with STUDIO_OVERNIGHT_HOLD_MINUTES=VALUE, then back to 0.
run_start_hold() { STUDIO_OVERNIGHT_HOLD_MINUTES="$1"; export STUDIO_OVERNIGHT_HOLD_MINUTES; run_start; STUDIO_OVERNIGHT_HOLD_MINUTES=0; }
test_overnight_channel_file() {
  fixture chf; done_scenario; run_start
  assert_eq "hold_minutes=0|directive_chars=4000" "$(tr '\n' '|' < "$(last_run_dir)/channel" | sed 's/|$//')" "channel: the effective hold_minutes and the default cap"
  fixture chf2 '{"overnight": {"directive_chars": 800, "hold_minutes": 30}}'; done_scenario; run_start
  assert_contains "$(last_run_dir)/channel" "^directive_chars=800$" "the configured cap"
  assert_contains "$(last_run_dir)/channel" "^hold_minutes=0$" "the test override wins over config"
  fixture chf3; done_scenario; run_start_hold 010
  assert_contains "$(last_run_dir)/channel" "^hold_minutes=10$" "010 is normalised to 10 (R26)"
  fixture chf4; done_scenario; run_start_hold 1440
  assert_contains "$(last_run_dir)/channel" "^hold_minutes=1440$" "1440 is the upper bound and is accepted"
  fixture chf5; done_scenario; unset STUDIO_OVERNIGHT_HOLD_MINUTES; run_start
  assert_contains "$(last_run_dir)/channel" "^hold_minutes=480$" "with no override and no config, hold_minutes defaults to 480"
  STUDIO_OVERNIGHT_HOLD_MINUTES=0; export STUDIO_OVERNIGHT_HOLD_MINUTES
}
test_overnight_unit_env() {
  fixture uenv; done_scenario; run_start
  _r="$(last_run_dir)"
  assert_eq "$(basename "$_r")-0-1-T1 $_r" "$(cat "$CALLS/1.chan")" "a unit gets STUDIO_UNIT_TAG and STUDIO_RUN_DIR"
  fixture uenv2; run_start --dry-run
  assert_not_contains "$RS_OUT" "STUDIO_RUN_DIR" "the dry-run launch line is unchanged"
}
test_overnight_events_two_units() {
  fixture ev2
  scenario "stage execute; task 1/1; ledger T1 complete; cost 2" \
           "ledger final review done; ledger shipped https://github.com/o/r/pull/9; stage idle; task -; cost 1"
  run_start
  E="$(last_run_dir)/events.jsonl"; B="$(basename "$(last_run_dir)")"
  assert_eq "run_started story_listed story_state unit_started unit_ended unit_started unit_ended run_ended" \
    "$(sed -n 's/.*"event":"\([a-z_]*\)".*/\1/p' "$E" | tr '\n' ' ' | sed 's/ $//')" "the events, in order"
  assert_eq 8 "$(grep -c "^{\"v\":1,\"ts\":\"[0-9-]*T[0-9:]*Z\",\"run\":\"$B\",\"event\":" "$E")" "every line: v, ts, run"
  assert_contains "$E" '"event":"run_started","mode":"single","max_lanes":1,"hold_minutes":0}$' "run_started"
  assert_contains "$E" '"event":"story_listed","story":"-","chain":1,"depends":\[\]}$' "one story_listed: -"
  assert_contains "$E" '"event":"story_state","story":"-","state":"running"}$' "running"
  assert_contains "$E" "\"event\":\"unit_started\",\"story\":\"-\",\"unit\":\"$B-0-1-T1\",\"label\":\"T1\",\"model\":\"sonnet\"}\$" "unit_started"
  assert_contains "$E" "\"event\":\"unit_ended\",\"story\":\"-\",\"unit\":\"$B-0-1-T1\",\"label\":\"T1\",\"outcome\":\"progress\",\"usd\":2}\$" "unit_ended: progress, usd"
  assert_contains "$E" '"label":"final-review","outcome":"done","usd":1}$' "the second unit ends done"
  assert_contains "$E" "\"event\":\"run_ended\",\"ending\":\"done\",\"report\":\"$(last_run_dir)/report.md\"}\$" "run_ended names the report"
}

test_say_writes_message() {
  fixture sw; fake_run overnight-sw-1 single
  verb say - 'Use the EventBus, not "signals" — it'\''s $HOME'
  assert_eq 0 "$V_STATUS" "say exits 0"
  assert_eq 1 "$(cat "$V_OUT")" "say prints the id"
  M="$FR_DIR/inbox/-/1.msg"
  assert_file "$M" "the message is in the story's inbox"
  assert_eq "id: 1|scope: story|target: -|story: -|requeues: 0|--" \
    "$(sed '/^--$/q' "$M" | grep -v '^queued: ' | tr '\n' '|' | sed 's/|$//')" "the header, in order"
  assert_contains "$M" '^queued: 20[0-9-]*T[0-9:]*Z$' "queued is ISO-8601 UTC"
  assert_eq 'Use the EventBus, not "signals" — it'\''s $HOME' "$(body "$M")" "the body is the text, verbatim"
  assert_eq "1.msg" "$(ls -A "$FR_DIR/inbox/-")" "no temp file and no lock left"
  assert_contains "$FR_DIR/events.jsonl" '"event":"message_queued","story":"-","id":1,"scope":"story"}$' "message_queued"
  assert_not_contains "$FR_DIR/events.jsonl" "EventBus" "message text never reaches the log"
  fake_run_end
}
test_say_dash_text_and_unit() {
  fixture sd; fake_run overnight-sd-1 single
  verb say - --unit -- use --force, not '$(x)' "it's"
  assert_eq 0 "$V_STATUS" "say -- exits 0"
  assert_eq "use --force, not \$(x) it's" "$(body "$FR_DIR/inbox/-/1.msg")" "every word after -- is text, joined by spaces"
  assert_contains "$FR_DIR/inbox/-/1.msg" "^scope: unit$" "--unit gives scope unit"
  verb say - --run overnight-sd-1 -- --run x
  assert_eq 0 "$V_STATUS" "--run before --, and an option-like word after it"
  assert_eq "--run x" "$(body "$FR_DIR/inbox/-/2.msg")" "after --, --run is text"
  verb say - --bogus x;  assert_eq 2 "$V_STATUS" "an unknown option is usage"
  verb say - a b;        assert_eq 2 "$V_STATUS" "two text words without -- is usage"
  verb said --unit -;    assert_eq 2 "$V_STATUS" "--unit belongs to say only"
  verb said - -- x;      assert_eq 2 "$V_STATUS" "-- belongs to say only"
  verb say --run;        assert_eq 2 "$V_STATUS" "--run needs a value"
  fake_run_end
}
test_say_empty_text_exit_2() {
  fixture se; fake_run overnight-se-1 single
  nl='
'
  verb say - '';                   assert_eq 2 "$V_STATUS" "say - '': exit 2"
  assert_contains "$V_ERR" "say: empty text" "it names the reason"
  verb say - --;                   assert_eq 2 "$V_STATUS" "say - -- with nothing after it: exit 2"
  verb say - -- '' ' ';            assert_eq 2 "$V_STATUS" "say - -- '' ' ': exit 2"
  verb say - '   ';                assert_eq 2 "$V_STATUS" "spaces only: exit 2"
  verb say - " 	$nl ";           assert_eq 2 "$V_STATUS" "blanks, a tab and a newline: exit 2"
  verb say - --unit --;            assert_eq 2 "$V_STATUS" "--unit with no text: exit 2"
  verb say -;                      assert_eq 2 "$V_STATUS" "no text at all: exit 2"
  assert_missing "$FR_DIR/inbox/-/1.msg" "nothing is written"
  assert_missing "$FR_DIR/events.jsonl" "no event"
  fake_run_end
  verb say - '';                   assert_eq 2 "$V_STATUS" "empty text is usage even with no live run"
}
test_say_ids_ledger_and_inbox() {
  fixture si; ledger_add "Directive 7: older run" "Directive 9 retired"
  fake_run overnight-si-1 single
  verb say - first;  assert_eq 10 "$(cat "$V_OUT")" "the next id passes the ledger's highest (a retired line counts)"
  mkdir -p "$FR_DIR/inbox/-/delivered/tagx"; mv "$FR_DIR/inbox/-/10.msg" "$FR_DIR/inbox/-/delivered/tagx/"
  verb say - second; assert_eq 11 "$(cat "$V_OUT")" "a delivered message's id counts"
  verb say - third;  assert_eq 12 "$(cat "$V_OUT")" "a pending message's id counts"
  assert_missing "$FR_DIR/inbox/-/.lock" "the inbox lock is released"
  fake_run_end
}
test_say_cap() {
  fixture sc; ledger_add "Directive 1: $(printf '%200s' '' | tr ' ' a)"
  FR_CHARS=500; fake_run overnight-sc-1 single; unset FR_CHARS
  verb say - "$(printf '%200s' '' | tr ' ' b)";              assert_eq 0 "$V_STATUS" "400 of 500"
  verb say - --unit -- "$(printf '%400s' '' | tr ' ' u)";    assert_eq 0 "$V_STATUS" "a unit message is not capped"
  verb say - "$(printf '%101s' '' | tr ' ' c)"
  assert_eq 1 "$V_STATUS" "501 characters exceed directive_chars 500"
  assert_contains "$V_ERR" "directive_chars 500" "the refusal names the cap"
  assert_contains "$V_ERR" "^  1  active  aaaa" "it lists the active directive with its id"
  assert_contains "$V_ERR" "^  2  pending  bbbb" "and the pending one"
  assert_not_contains "$V_ERR" "uuuu" "and not the unit message"
  assert_missing "$FR_DIR/inbox/-/4.msg" "nothing is written"
  verb say - "$(printf '%100s' '' | tr ' ' c)";              assert_eq 0 "$V_STATUS" "exactly 500 fits"
  fake_run_end
}
test_say_cap_counts_characters() {
  fixture scc; FR_CHARS=500; fake_run overnight-scc-1 single; unset FR_CHARS
  verb say - "$(printf '%300s' '' | sed 's/ /é/g')"; assert_eq 0 "$V_STATUS" "300 two-byte characters"
  verb say - "$(printf '%200s' '' | sed 's/ /é/g')"; assert_eq 0 "$V_STATUS" "500 characters (1000 bytes) fit a 500-character cap"
  verb say - "é";                                     assert_eq 1 "$V_STATUS" "the 501st character does not"
  fake_run_end
}
test_say_bad_directive_chars_defaults() {
  fixture sbc; FR_CHARS=abc; fake_run overnight-sbc-1 single; unset FR_CHARS
  verb say - short; assert_eq 0 "$V_STATUS" "a malformed directive_chars does not break say"
  verb say - "$(printf '%4000s' '' | tr ' ' x)"
  assert_eq 1 "$V_STATUS" "the cap falls back to the default 4000"
  assert_contains "$V_ERR" "directive_chars 4000" "and the refusal names it"
  fake_run_end
  fixture sbc2; FR_CHARS=100; fake_run overnight-sbc2-1 single; unset FR_CHARS
  verb say - "$(printf '%200s' '' | tr ' ' x)"; assert_eq 0 "$V_STATUS" "a value below the 500 range also falls back to 4000"
  fake_run_end
}
test_inbox_lock_failures() {
  [ "$(id -u)" != 0 ] || return 0
  fixture il; fake_run overnight-il-1 single
  chmod 555 "$FR_DIR"
  verb say - x; _il_st="$V_STATUS"
  chmod 755 "$FR_DIR"
  assert_eq 1 "$_il_st" "an inbox that cannot be created refuses"
  assert_contains "$V_ERR" "^studio-overnight: cannot create .*/inbox/-$" "it names the real failure, not a busy inbox"
  assert_eq 1 "$(grep -c . "$V_ERR")" "one stderr line"
  mkdir -p "$FR_DIR/inbox/-/.lock"; touch -t 200001010000 "$FR_DIR/inbox/-/.lock"
  chmod 555 "$FR_DIR/inbox/-"
  STUDIO_OVERNIGHT_INBOX_WAIT=2; export STUDIO_OVERNIGHT_INBOX_WAIT
  verb say - x; _il_st="$V_STATUS"
  unset STUDIO_OVERNIGHT_INBOX_WAIT
  chmod 755 "$FR_DIR/inbox/-"
  assert_eq 1 "$_il_st" "a stale lock that cannot be broken gives up after WAIT instead of spinning"
  assert_contains "$V_ERR" "inbox busy" "and says busy"
  fake_run_end
}
test_said_lists_states() {
  fixture sl; ledger_add "Directive 1: one" "Directive 2: two" "Directive 2 retired"
  fake_run overnight-sl-1 single
  verb said -; assert_eq "1  active  one" "$(cat "$V_OUT")" "an active directive; a retired one is not listed"
  verb say - three; verb say - --unit four; verb say - five
  mkdir -p "$FR_DIR/inbox/-/delivered/tg"; mv "$FR_DIR/inbox/-/5.msg" "$FR_DIR/inbox/-/delivered/tg/"
  verb unsay - 1; assert_eq "retire queued: message 6 retires directive 1" "$(cat "$V_OUT")" "unsay of an active directive"
  verb said -
  assert_eq 0 "$V_STATUS" "said exits 0"
  assert_eq "1  retiring  one|3  pending  three|4  pending (unit)  four|5  delivered  five" \
    "$(tr '\n' '|' < "$V_OUT" | sed 's/|$//')" "every state, in id order; the retire message is not listed"
  fake_run_end
  fixture sl2; fake_run overnight-sl2-1 single
  verb said -; assert_eq "(no directives)" "$(cat "$V_OUT")" "none"
  fake_run_end
}
test_unsay_pending_active_delivered() {
  fixture us; ledger_add "Directive 1: one" "Directive 2: two" "Directive 2 retired"
  fake_run overnight-us-1 single; IB="$FR_DIR/inbox/-"
  verb say - three; verb unsay - 3
  assert_eq "removed message 3 (it was not delivered)" "$(cat "$V_OUT")" "a pending story message is removed"
  assert_missing "$IB/3.msg" "its file is gone"
  # a removed highest id is free again, so each id is read from say's output
  verb say - --unit four; U4="$(cat "$V_OUT")"
  assert_eq 3 "$U4" "unsay of the newest pending id frees it: the next say reuses 3 (R11 gap ruling)"
  verb unsay - "$U4"; assert_eq 0 "$V_STATUS" "a pending unit message is removed"
  verb say - five; F5="$(cat "$V_OUT")"; mkdir -p "$IB/delivered/tg"; mv "$IB/$F5.msg" "$IB/delivered/tg/"
  verb unsay - "$F5"; R6=$((F5 + 1))
  assert_eq "retire queued: message $R6 retires directive $F5" "$(cat "$V_OUT")" "delivered, not recorded: a retire"
  assert_contains "$IB/$R6.msg" "^scope: retire$" "the retire's scope"
  assert_contains "$IB/$R6.msg" "^target: $F5$" "and target"
  verb unsay - "$F5"; assert_eq 1 "$V_STATUS" "a retiring directive: exit 1"
  assert_contains "$V_ERR" "already retiring" "named"
  verb unsay - "$R6"; assert_eq 1 "$V_STATUS" "a retire message: exit 1"
  verb unsay - 2; assert_eq 1 "$V_STATUS" "a retired id: exit 1"
  assert_contains "$V_ERR" "already retired" "named"
  verb unsay - 99; assert_eq 1 "$V_STATUS" "an unknown id: exit 1"
  assert_eq 1 "$(grep -c . "$V_ERR")" "a refusal is one stderr line"
  verb say - --unit seven; U7="$(cat "$V_OUT")"; mv "$IB/$U7.msg" "$IB/delivered/tg/"
  verb unsay - "$U7"; assert_eq 1 "$V_STATUS" "a delivered unit message is spent: exit 1"
  for bad in 01 x '' 1x; do verb unsay - "$bad"; assert_eq 2 "$V_STATUS" "id '$bad' is usage"; done
  fake_run_end
}
test_unsay_loses_race_to_hook() {
  fixture ur; fake_run overnight-ur-1 single; IB="$FR_DIR/inbox/-"
  put_msg "$IB" 1 story one
  # a stub rm claims the message into delivered/ (as the hook's mv does), then fails as rm of a gone file does
  mkdir -p "$TMP/urbin"
  printf '#!/bin/sh\ncase "$*" in *1.msg*) mkdir -p "%s/delivered/tagx"; mv "%s/1.msg" "%s/delivered/tagx/"; exit 1 ;; esac\nexec /bin/rm "$@"\n' "$IB" "$IB" "$IB" > "$TMP/urbin/rm"
  chmod +x "$TMP/urbin/rm"
  _ur_path="$PATH"; PATH="$TMP/urbin:$PATH"; verb unsay - 1; PATH="$_ur_path"
  assert_eq 1 "$V_STATUS" "unsay loses the race: exit 1"
  assert_eq "studio-overnight: unsay: message 1 was just delivered; run unsay 1 again to retire it" "$(cat "$V_ERR")" "one stderr line names the cause"
  assert_not_contains "$V_OUT" "removed message" "it does not claim a withdrawal"
  assert_missing "$IB/.lock" "the inbox lock is released"
  fake_run_end
}
test_unsay_id_prefix() {
  fixture up; ledger_add "Directive 10: ten"
  fake_run overnight-up-1 single; IB="$FR_DIR/inbox/-"
  put_msg "$IB" 1 story one
  verb unsay - 1
  assert_eq "removed message 1 (it was not delivered)" "$(cat "$V_OUT")" "unsay 1 removes message 1"
  assert_missing "$IB/1.msg" "1.msg is gone"
  assert_eq "" "$(ls "$IB" | grep -v '^delivered$')" "no retire was queued for directive 10"
  verb said -; assert_eq "10  active  ten" "$(cat "$V_OUT")" "directive 10 is still active"
  verb unsay - 1; assert_eq 1 "$V_STATUS" "a second unsay 1 is unknown"
  fake_run_end
}
test_hold_resume_stop_table() {
  fixture tb
  fake_run overnight-tb-1 manifest Q=queued W=waiting R=running G=gate-repair \
    H="held stop: need art until 2026-10-04T05:00:00Z" L=landing P=repair
  C="$FR_DIR/control"
  for id in Q W R G H L P; do cp "$FR_DIR/stories/$id" "$TMP/rec-$id"; done
  for id in Q W; do verb hold "$id"; assert_eq "hold requested: $id holds when it would start" "$(cat "$V_OUT")" "hold $id"; done
  for id in R G; do verb hold "$id"; assert_eq "hold requested: $id holds at its next unit boundary" "$(cat "$V_OUT")" "hold $id"; done
  for id in Q W R G; do assert_file "$C/$id.hold" "hold $id writes control/$id.hold"; done
  verb hold H; assert_eq 1 "$V_STATUS" "hold on a held story"; assert_contains "$V_ERR" "already held" "named"
  for id in L P; do
    verb hold "$id"; assert_eq 1 "$V_STATUS" "hold $id (landing)"; assert_contains "$V_ERR" "land lock" "named"
    verb resume "$id"; assert_eq 1 "$V_STATUS" "resume $id (landing)"
    verb stop "$id"; assert_eq 1 "$V_STATUS" "stop $id (landing)"; assert_contains "$V_ERR" "land lock" "named"
    verb say "$id" note; assert_eq 0 "$V_STATUS" "say $id still queues"
  done
  for id in Q W R G; do verb resume "$id"; assert_eq 1 "$V_STATUS" "resume $id: not held"; assert_contains "$V_ERR" "is not held" "named"; done
  verb resume H; assert_eq "resume requested: H resumes within one poll" "$(cat "$V_OUT")" "resume H"
  assert_file "$C/H.resume" "control/H.resume"
  for id in Q W; do verb stop "$id"; assert_eq "stop requested: $id stops when its lane reaches it" "$(cat "$V_OUT")" "stop $id"; done
  for id in R G; do verb stop "$id"; assert_eq "stop requested: $id stops after its running unit" "$(cat "$V_OUT")" "stop $id"; done
  verb stop H; assert_eq "stop requested: H stops within one poll" "$(cat "$V_OUT")" "stop H"
  for id in Q W R G H; do assert_file "$C/$id.stop" "control/$id.stop"; done
  for id in L P; do assert_missing "$C/$id.hold" "no control file for $id"; assert_missing "$C/$id.stop" "nor a stop"; done
  for id in Q W R G H L P; do assert_eq "$(cat "$TMP/rec-$id")" "$(cat "$FR_DIR/stories/$id")" "the verbs never write $id's record"; done
  verb hold Q; assert_eq "hold requested: Q holds when it would start" "$(cat "$V_OUT")" "hold again: the same line (R22)"
  assert_contains "$FR_DIR/events.jsonl" '"event":"control","story":"Q","action":"hold"}$' "a control event for hold"
  assert_contains "$FR_DIR/events.jsonl" '"event":"control","story":"H","action":"resume"}$' "for resume"
  assert_contains "$FR_DIR/events.jsonl" '"event":"control","story":"R","action":"stop"}$' "for stop"
  assert_eq "" "$(ls -A "$C" | grep '^\.')" "no temp control file left"
  fake_run_end
}
test_hold_resume_stop_usage_and_unwritable() {
  fixture hu
  for bad in "hold" "hold a b" "hold --unit a" "resume" "resume a b" "stop a b" "stop --unit a" "hold a --"; do
    verb $bad; assert_eq 2 "$V_STATUS" "'$bad' is usage, even with no live run"
  done
  fake_run overnight-hu-1 manifest S=running
  verb stop S; assert_eq "stop requested: S stops after its running unit" "$(cat "$V_OUT")" "stop"
  verb stop S; assert_eq 0 "$V_STATUS" "a repeat stop exits 0 (R22)"
  assert_eq "stop requested: S stops after its running unit" "$(cat "$V_OUT")" "and prints the same line"
  if [ "$(id -u)" != 0 ]; then
    rm -rf "$FR_DIR/control"; mkdir "$FR_DIR/control"; chmod 555 "$FR_DIR/control"
    verb hold S; _hu_st="$V_STATUS"; chmod 755 "$FR_DIR/control"
    assert_eq 1 "$_hu_st" "an unwritable control dir refuses hold"
    assert_eq 1 "$(grep -c . "$V_ERR")" "the refusal is one stderr line (R27)"
    assert_contains "$V_ERR" "^studio-overnight: cannot write .*/control/S.hold$" "and names the file"
  fi
  fake_run_end
}
test_hold_minutes_zero() {
  fixture hz; FR_HOLD=0; fake_run overnight-hz-1 manifest S1=running S2="held stop: x until 2026-10-04T05:00:00Z"; unset FR_HOLD
  verb hold S1;   assert_eq 1 "$V_STATUS" "hold with hold_minutes 0"
  assert_eq "studio-overnight: holds are off: hold_minutes 0" "$(cat "$V_ERR")" "the exact line"
  verb resume S2; assert_eq 1 "$V_STATUS" "resume with hold_minutes 0"
  assert_contains "$V_ERR" "holds are off: hold_minutes 0" "named"
  verb say S1 x;  assert_eq 0 "$V_STATUS" "say works"
  verb said S1;   assert_eq 0 "$V_STATUS" "said works"
  verb unsay S1 1; assert_eq 0 "$V_STATUS" "unsay works"
  verb stop S1;   assert_eq 0 "$V_STATUS" "stop <story> works"
  fake_run_end
}
test_single_plan_verbs() {
  fixture spv; fake_run overnight-spv-1 single; C="$FR_DIR/control"
  verb hold -;   assert_eq "hold requested: - holds at its next unit boundary" "$(cat "$V_OUT")" "hold - on the running story"
  verb resume -; assert_eq 1 "$V_STATUS" "resume -: not held"
  verb hold S1;  assert_eq 1 "$V_STATUS" "a story id in a single-plan run"
  mkdir -p "$C"; printf 'held stop: x until 2026-10-04T05:00:00Z\n' > "$C/-.held"
  verb hold -;   assert_eq 1 "$V_STATUS" "control/-.held: already held"
  verb resume -; assert_eq 0 "$V_STATUS" "resume - on a held story"
  assert_file "$C/-.resume" "control/-.resume"
  verb stop -;   assert_eq "stop requested: - stops within one poll" "$(cat "$V_OUT")" "stop - on a held story"
  rm -f "$C/-.held"
  verb stop -;   assert_eq "stop requested: - stops after its running unit" "$(cat "$V_OUT")" "stop - on the running story"
  assert_missing "$P/.studio/overnight.stop" "stop - never writes the run's stop file"
  fake_run_end
}
test_resume_refused_dirty_ledger() {
  fixture rd; fake_run overnight-rd-1 manifest H="held stop: x until 2026-10-04T05:00:00Z"
  printf -- '- 2026-10-03 hand edit\n' >> "$P/.studio/ledger/H.md"
  verb resume H; assert_eq 1 "$V_STATUS" "a dirty start ledger refuses resume"
  assert_contains "$V_ERR" "\.studio/ledger/H\.md" "it names the file"
  assert_missing "$FR_DIR/control/H.resume" "no control file"
  fake_run_end
  fixture rd2; ledger_add "Directive 1: x"; fake_run overnight-rd2-1 single
  mkdir -p "$FR_DIR/control"; printf 'held stop: x until 2026-10-04T05:00:00Z\n' > "$FR_DIR/control/-.held"
  printf -- '- 2026-10-03 hand edit\n' >> "$P/.studio/ledger/spec.md"
  verb resume -; assert_eq 1 "$V_STATUS" "single-plan: a dirty .studio/ledger refuses resume"
  assert_contains "$V_ERR" "\.studio/ledger/spec\.md" "it names the file"
  fake_run_end
}
test_resume_from_feature_worktree() {
  fixture rw; fake_run overnight-rw-1 manifest H="held stop: x until 2026-10-04T05:00:00Z"
  git -C "$P" worktree add -q -b feat-h "$TMP/wt-rw" >/dev/null 2>&1
  printf -- '- 2026-10-03 feature-side edit\n' >> "$TMP/wt-rw/.studio/ledger/H.md"
  verb_in "$TMP/wt-rw" said H; assert_eq 0 "$V_STATUS" "a verb inside a feature worktree finds the run"
  verb_in "$TMP/wt-rw" resume H
  assert_eq 0 "$V_STATUS" "the dirty check reads the run's start checkout, not the cwd"
  assert_file "$FR_DIR/control/H.resume" "the control file is the run's"
  rm -f "$FR_DIR/control/H.resume"
  printf -- '- 2026-10-03 start-side edit\n' >> "$P/.studio/ledger/H.md"
  verb_in "$TMP/wt-rw" resume H; assert_eq 1 "$V_STATUS" "a dirty start ledger refuses, from the worktree too"
  fake_run_end
}
test_verbs_refusals() {
  fixture rf
  verb say - x; assert_eq 1 "$V_STATUS" "no live run: exit 1"
  assert_contains "$V_ERR" "no live run" "named"
  fake_run overnight-rf-1 manifest S1=running S2="landed abc1234" S3="stopped stop: x" S4="skipped S2"
  verb say S9 x; assert_eq 1 "$V_STATUS" "a story not in the run"; assert_contains "$V_ERR" "S9 is not in run overnight-rf-1" "named"
  verb say - x;  assert_eq 1 "$V_STATUS" "- in a manifest run"
  for id in S2 S3 S4; do
    verb said "$id"; assert_eq 1 "$V_STATUS" "$id has ended: exit 1"
    assert_contains "$V_ERR" "story $id has ended" "named"
    assert_eq 1 "$(grep -c . "$V_ERR")" "one line"
  done
  verb said;          assert_eq 2 "$V_STATUS" "said with no story"
  verb unsay S1;      assert_eq 2 "$V_STATUS" "unsay with no id"
  verb said S1 S1 S1; assert_eq 2 "$V_STATUS" "too many words"
  rm -f "$FR_DIR/channel"
  verb said S1; assert_eq 1 "$V_STATUS" "a run without a channel file"
  assert_contains "$V_ERR" "predates the operator channel" "named"
  fake_run_end
  fixture rf2; fake_run overnight-rf2-1 single
  verb say S1 x; assert_eq 1 "$V_STATUS" "a story id in a single-plan run"
  assert_contains "$V_ERR" "single-plan run: its story is -" "named"
  fake_run_end
}
test_verbs_run_pinning() {
  fixture pa; fake_run overnight-pa-1 single; PA="$P"; PA_PID="$FR_PID"
  verb say --run overnight-pa-1 - x; assert_eq 0 "$V_STATUS" "--run naming this project's run"
  verb say - --run overnight-pa-1 -- y; assert_eq 0 "$V_STATUS" "--run anywhere before --"
  verb say --run overnight-pa - x; assert_eq 1 "$V_STATUS" "a prefix is not a match"
  assert_contains "$V_ERR" "run overnight-pa is not live" "named"
  fixture pb; fake_run overnight-pb-1 manifest S1=running; PB="$P"; PB_PID="$FR_PID"
  verb_in "$PA" say --run overnight-pb-1 - x
  assert_eq 1 "$V_STATUS" "inside a project, only that project's run"
  assert_contains "$V_ERR" "run overnight-pb-1 is not live" "never a fallback to another project's run"
  assert_missing "$PB/.studio/reports/overnight-pb-1/inbox" "nothing reached the other run"
  mkdir -p "$TMP/outside"
  verb_in "$TMP/outside" said -; assert_eq 1 "$V_STATUS" "two live runs outside a project and no --run"
  assert_contains "$V_ERR" "overnight-pa-1" "names the first"; assert_contains "$V_ERR" "overnight-pb-1" "and the second"
  verb_in "$TMP/outside" said --run overnight-pb-1 S1; assert_eq 0 "$V_STATUS" "--run picks one"
  assert_eq "(no directives)" "$(cat "$V_OUT")" "from the named run"
  verb_in "$TMP/outside" say --run overnight-zz - x; assert_eq 1 "$V_STATUS" "an unknown run"
  assert_contains "$V_ERR" "run overnight-zz is not live" "named"
  # bare stop with --run
  P="$PA"; verb stop --run overnight-pb-1; assert_eq 1 "$V_STATUS" "stop --run of another project's run"
  assert_missing "$PA/.studio/overnight.stop" "no stop file here"
  assert_missing "$PB/.studio/overnight.stop" "nor there"
  verb_in "$TMP/outside" stop --run overnight-pb-1; assert_eq 0 "$V_STATUS" "stop --run from outside"
  assert_contains "$V_OUT" "^stop requested: the run ends after its running unit (pid $PB_PID)$" "today's line"
  assert_file "$PB/.studio/overnight.stop" "the named run's stop file"
  P="$PB"; fake_run_end "$PB_PID"
  # an ended run is never live
  printf 'root=%s\nstart=%s\nrun=%s\npid=1\nended=x\n' "$PB" "$PB" "$PB/.studio/reports/overnight-pb-1" > "$HOME/.claude-gamedev/runs/last"
  verb_in "$TMP/outside" said --run overnight-pb-1 S1; assert_eq 1 "$V_STATUS" "the last ended run is not live"
  rm -f "$HOME/.claude-gamedev/runs/last"
  P="$PA"; verb stop --run overnight-pa-1; assert_eq 0 "$V_STATUS" "stop --run of this project's run"
  assert_file "$PA/.studio/overnight.stop" "writes its stop file"
  fake_run_end "$PA_PID"
}
test_verbs_per_run_channel_and_stop_run() {
  fixture perrun; FR_SEQ=1; fake_mrun alpha S1=running
  verb say S1 hello
  assert_eq 0 "$V_STATUS" "say finds the per-run run $(cat "$V_ERR")"
  verb stop --run alpha
  assert_file "$P/.studio/runs/alpha/stop" "stop --run writes the run's own flag (D5)"
  assert_missing "$P/.studio/overnight.stop" "never the project-wide one"
  fake_run_end
}
# AC5: a single-plan start refuses while a manifest run holds a per-run lock
# (modelled on test_overnight_lock; the single-plan fixture passes every
# earlier preflight check).
test_overnight_lock_refuses_live_manifest() {
  fixture smani; fake_mrun alpha S1=running
  run_start
  assert_eq 2 "$RS_STATUS" "a single-plan start refuses while a manifest run is live"
  assert_contains "$RS_ERR" "alpha" "names the live run"
  assert_contains "$RS_ERR" "pid $FR_PID" "and its pid"
  assert_eq 0 "$(calls)" "no session"
  assert_missing "$P/.studio/overnight.lock" "no lock left behind"
  fake_run_end
}
test_inbox_lock_stale_broken() {
  fixture lk; fake_run overnight-lk-1 single
  mkdir -p "$FR_DIR/inbox/-/.lock"; touch -t 202001010000 "$FR_DIR/inbox/-/.lock"
  verb say - x
  assert_eq 0 "$V_STATUS" "a stale lock is broken"
  assert_eq 1 "$(cat "$V_OUT")" "and the message written"
  assert_eq "1.msg" "$(ls -A "$FR_DIR/inbox/-")" "no lock and no renamed stale lock left"
  fake_run_end
}
test_inbox_lock_busy() {
  fixture lb; fake_run overnight-lb-1 single
  mkdir -p "$FR_DIR/inbox/-/.lock"
  STUDIO_OVERNIGHT_INBOX_WAIT=2; export STUDIO_OVERNIGHT_INBOX_WAIT
  t0="$(date +%s)"; verb say - x; t1="$(date +%s)"
  unset STUDIO_OVERNIGHT_INBOX_WAIT
  assert_eq 1 "$V_STATUS" "a fresh lock held past the wait: exit 1"
  assert_contains "$V_ERR" "inbox busy" "named"
  assert_eq 1 "$([ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -lt 10 ] && echo 1 || echo 0)" "it waited about STUDIO_OVERNIGHT_INBOX_WAIT seconds"
  assert_missing "$FR_DIR/inbox/-/1.msg" "nothing written"
  assert_eq 1 "$([ -d "$FR_DIR/inbox/-/.lock" ] && echo 1 || echo 0)" "a fresh lock is never broken"
  fake_run_end
}
# a verb killed (INT, TERM) while it holds the inbox lock releases it
test_inbox_lock_released_on_signal() {
  for sig in TERM INT; do
    D="$TMP/lsig-$sig"; mkdir -p "$D"; rm -f "$D/held"
    ( SELF_DIR="$REPO_ROOT/studios/game-dev/bin"; . "$SELF_DIR/overnight-channel.sh"
      CH_IB="$D/inbox"; CH_STORY=-; trap - INT TERM
      chan_lock; : > "$D/held"; sleep 30 & wait ) > /dev/null 2>&1 &
    LP=$!
    wait_for "$D/held"
    assert_file "$D/held" "$sig: the verb took the lock"
    assert_eq 1 "$([ -d "$D/inbox/.lock" ] && echo 1 || echo 0)" "$sig: the lock is held"
    kill -$sig "$LP" 2>/dev/null; wait "$LP" 2>/dev/null
    assert_eq 0 "$([ -d "$D/inbox/.lock" ] && echo 1 || echo 0)" "$sig: the lock is gone after the signal"
  done
}
test_inbox_unlock_after_release_keeps_foreign_lock() {
  D="$TMP/lfor"; rm -rf "$D"; mkdir -p "$D/inbox"
  # a verb that unlocks explicitly, then a concurrent locker is mid-acquire
  # (mkdir done, owner not yet written), then the verb exits (EXIT trap)
  ( SELF_DIR="$REPO_ROOT/studios/game-dev/bin"; . "$SELF_DIR/overnight-channel.sh"
    CH_IB="$D/inbox"; CH_STORY=-
    chan_lock; inbox_unlock "$CH_IB"; mkdir "$D/inbox/.lock"; exit 0 ) > /dev/null 2>&1
  assert_eq 1 "$([ -d "$D/inbox/.lock" ] && echo 1 || echo 0)" "a foreign lock without an owner survives the verb's exit"
  for sg in "INT 130" "TERM 143" "HUP 129"; do
    set -- $sg
    sh -c 'SELF_DIR="$1"; . "$1/overnight-channel.sh"; CH_IB="$2"; CH_STORY=-; chan_lock; kill -$3 $$' x \
      "$REPO_ROOT/studios/game-dev/bin" "$D/in2" "$1" > /dev/null 2>&1
    assert_eq "$2" "$?" "$1 exits $2"
  done
}
test_channel_sourced_only() {
  assert_status 2 "overnight-channel.sh refuses to run on its own" -- sh "$REPO_ROOT/studios/game-dev/bin/overnight-channel.sh"
  assert_eq "overnight-channel.sh: sourced by studio-overnight" \
    "$(sh "$REPO_ROOT/studios/game-dev/bin/overnight-channel.sh" 2>&1)" "and says why"
}

test_overnight_hold_on_feature_stop() {
  fixture hof; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art"
  start_bg
  wait_held 20; assert_file "$R/control/-.held" "a feature-ledger Stop: after isolation holds the story"
  assert_contains "$R/control/-.held" "^held stop: need art until 20[0-9-]*T[0-9:]*Z$" "the held record: why, then the deadline"
  sleep 2; assert_eq 2 "$(calls)" "no session runs while held"
  assert_contains "$R/events.jsonl" '"event":"story_state","story":"-","state":"held","why":"stop: need art","until":"20' "a held story_state event"
  verb status
  assert_contains "$V_OUT" "^held — stop: need art — until [0-9][0-9]:[0-9][0-9] — say / resume / stop -$" "status shows the held line"
  verb stop -; assert_eq "stop requested: - stops within one poll" "$(cat "$V_OUT")" "stop - on the held story"
  bg_end 20 "the run ends within a poll"
  assert_eq 1 "$BG_STATUS" "a stopped run exits 1"
  assert_contains "$R/report.md" "^Ending: stop: need art$" "stop on a held story ends it with its why (AC23)"
  assert_eq "" "$(ls -A "$R/control")" "no control file is left (R25)"
  assert_missing "$P/.studio/overnight.lock" "the lock is released"
  holds_off
}
test_overnight_start_ledger_stop_ends_at_once() {
  holds_on 60
  fixture sls; scenario "stage execute; inplace; task 1/2; ledger Stop: from the start checkout"; run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: from the start checkout$" "a Stop: in the start ledger after isolation ends at once"
  assert_missing "$(last_run_dir)/control/-.held" "never held"
  fixture sls2; scenario "stage execute; task 1/2; ledger Stop: before isolation"; run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: before isolation$" "a Stop: before isolation ends at once"
  fixture sls3; scenario "stage execute; inplace; wtledger Stop: both; ledger Stop: both"; run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: both$" "the same Stop: in both ledgers ends at once (AC18's tie)"
  assert_not_contains "$(last_run_dir)/events.jsonl" '"state":"held"' "no held event"
  holds_off
}
test_overnight_resume_runs_next_unit() {
  fixture rnu; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art" "inbox; task 2/2; wtledger T2 complete b..c" \
           "wtledger final review done" "wtledger shipped https://x/pull/3; stage idle; task -"
  start_bg; wait_held 20
  verb say - "use the bus"; assert_eq 1 "$(cat "$V_OUT")" "say on the held story: id 1"
  verb say - --unit "skip polish"
  verb resume -; assert_eq "resume requested: - resumes within one poll" "$(cat "$V_OUT")" "resume -"
  bg_end 60 "the resumed run finishes"
  assert_eq 0 "$BG_STATUS" "it ends done"
  assert_eq "1 2 3 4 5" "$(unit_col 1)" "unit numbers run on after the hold"
  assert_contains "$CALLS/3.inbox" '^\[1, story\] use the bus$' "the next unit got the directive at startup"
  assert_contains "$CALLS/3.inbox" '^\[2, unit\] skip polish$' "and the unit message"
  assert_contains "$R/events.jsonl" '"event":"message_requeued","story":"-","id":1,"unit":"[^"]*-0-3-T2","requeues":1}$' "the unrecorded directive was requeued (AC13)"
  assert_contains "$R/inbox/-/1.msg" "^requeues: 1$" "back in pending with requeues 1"
  assert_missing "$R/inbox/-/2.msg" "a unit message is never requeued"
  assert_contains "$R/report.md" "^## Operator messages left$" "the report lists the messages left (AC14)"
  assert_contains "$R/report.md" "^- 1 (story, requeues 1): use the bus$" "id, scope, requeues, text"
  assert_contains "$R/events.jsonl" '"state":"running"}$' "a running event after the resume"
  holds_off
}
test_overnight_new_stop_holds_again() {
  fixture nsh; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art" "wtledger Stop: still need art"
  start_bg; wait_held 20
  verb resume -
  _i=0; while [ "$(calls)" -lt 3 ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
  wait_held 20
  _j=0; until grep -q 'still need art' "$R/control/-.held" 2>/dev/null || [ "$_j" -ge 50 ]; do sleep 0.2; _j=$((_j + 1)); done
  assert_contains "$R/control/-.held" "^held stop: still need art until " "a new stop after a resume holds again (AC20)"
  verb stop -; bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: stop: still need art$" "with the new why"
  holds_off
}
test_overnight_hold_deadline() {
  fixture hdl; holds_on 2
  scenario "$ISO1" "wtledger Stop: need art"
  t0="$(date +%s)"; run_start; t1="$(date +%s)"
  assert_eq 1 "$RS_STATUS" "the run ends 1"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: need art (held 0h0m, no reply)$" "the deadline appends the hold's length (AC24)"
  assert_eq 1 "$([ $((t1 - t0)) -ge 2 ] && echo 1 || echo 0)" "it waited out the deadline"
  assert_eq 2 "$(calls)" "no unit ran while held"
  holds_off
}
test_overnight_stop_beats_resume() {
  fixture sbr; holds_on 60; STUDIO_OVERNIGHT_POLL_SECONDS=3
  scenario "$ISO1" "wtledger Stop: need art" "wtledger final review done"
  start_bg; wait_held 20; sleep 1
  # Both files land between two polls: the runner is paused while they are written.
  kill -STOP "$RPID"; : > "$R/control/-.stop"; : > "$R/control/-.resume"; kill -CONT "$RPID"
  bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: stop: need art$" ".stop beats .resume in one poll (AC22)"
  assert_eq 2 "$(calls)" "no unit ran"
  holds_off
}
test_overnight_resume_wins_at_deadline() {
  fixture rwd; holds_on 2; STUDIO_OVERNIGHT_POLL_SECONDS=4
  scenario "$ISO1" "wtledger Stop: need art" "wtledger final review done" \
           "wtledger shipped https://x/pull/7; stage idle; task -"
  start_bg; wait_held 20; sleep 1
  verb resume -
  bg_end 60 "the run ends"
  assert_eq 0 "$BG_STATUS" "a resume seen at the poll after the deadline still resumes (AC22)"
  assert_contains "$R/report.md" "^Ending: done$" "and the run finishes"
  holds_off
}
test_overnight_requeue_then_hold() {
  fixture rth; holds_on 60
  scenario "stage execute; branch feat; task 1/3; wtledger T1 complete a..b; say use the bus" \
           "inbox; task 2/3; wtledger T2 complete b..c" \
           "inbox; task 3/3; wtledger T3 complete c..d"
  start_bg; wait_held 20
  assert_contains "$R/control/-.held" "^held directive 1 not recorded until " "requeued retries + 1 times: the story holds (AC14)"
  assert_eq "progress progress progress" "$(unit_col 7)" "the unit's own outcome is kept in its row"
  verb stop -; bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: directive 1 not recorded$" "stop ends it with that why"
  assert_contains "$R/report.md" "^- 1 (story, requeues 2): use the bus$" "the message is listed"
  holds_off
}
test_overnight_recorded_directive_stays_delivered() {
  fixture rds
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; say use the bus" \
           "inbox; wtledger Directive 1: use the bus; task 2/2; wtledger T2 complete b..c" \
           "wtledger final review done" "wtledger shipped https://x/pull/4; stage idle; task -"
  run_start
  assert_eq 0 "$RS_STATUS" "done"
  R="$(last_run_dir)"
  assert_eq 1 "$(ls "$R"/inbox/-/delivered/*/1.msg 2>/dev/null | wc -l | tr -d ' ')" "a recorded directive stays delivered"
  assert_not_contains "$R/events.jsonl" '"event":"message_requeued"' "and is not requeued"
  assert_not_contains "$R/report.md" "Operator messages left" "nothing left"
}
test_overnight_requeue_id_prefix() {
  fixture rip
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; say one" \
           "inbox; wtledger Directive 10: not one; task 2/2; wtledger T2 complete b..c" \
           "wtledger final review done" "wtledger shipped https://x/pull/8; stage idle; task -"
  run_start; R="$(last_run_dir)"
  assert_contains "$R/events.jsonl" '"event":"message_requeued","story":"-","id":1,' "Directive 10: does not record message 1"
  assert_contains "$R/report.md" "^- 1 (story, requeues 1): one$" "message 1 is left"
}
test_overnight_requeue_done_no_hold() {
  fixture rdn '{"overnight": {"retries": 0}}'; holds_on 60
  scenario "stage execute; branch feat; task 1/1; wtledger T1 complete a..b; say use the bus" \
           "inbox; wtledger final review done; wtledger shipped https://x/pull/5; stage idle; task -"
  run_start; R="$(last_run_dir)"
  assert_eq 0 "$RS_STATUS" "a unit that ships is done, whatever it left unrecorded (AC14)"
  assert_contains "$R/report.md" "^Ending: done$" "done"
  assert_not_contains "$R/events.jsonl" '"state":"held"' "never held"
  assert_contains "$R/report.md" "^- 1 (story, requeues 1): use the bus$" "the message is listed"
  holds_off
}
# a hand-edited `requeues:` header ("1x", "08") counts as 0: the runner lives
test_overnight_requeue_corrupt_header() {
  for bad in 1x 08; do
    want=1; [ "$bad" != 08 ] || want=9   # 08 is decimal 8: requeued to 9
    fixture rch$bad '{"overnight": {"retries": 0}}'; holds_on 60
    scenario "stage execute; branch feat; task 1/1; wtledger T1 complete a..b; say use the bus" \
             "inbox; corruptrq $bad; wtledger final review done; wtledger shipped https://x/pull/5; stage idle; task -"
    run_start; R="$(last_run_dir)"
    assert_eq 0 "$RS_STATUS" "requeues: $bad does not kill the runner"
    assert_contains "$R/report.md" "^Ending: done$" "$bad: done"
    assert_contains "$R/events.jsonl" '"event":"message_requeued".*"requeues":'"$want" "$bad: counted as $((want - 1)), requeued to $want"
    holds_off
  done
}
test_overnight_prestop_and_limit_end_at_once() {
  holds_on 60
  fixture pli '{"overnight": {"retries": 0}}'
  scenario "stage execute; task 1/2; ledger T1 complete a..b; say x" \
           "inbox; task 2/2; ledger T2 complete b..c" "ledger final review done" \
           "ledger shipped https://x/pull/6; stage idle; task -"
  run_start
  assert_eq 0 "$RS_STATUS" "before isolation the limit never holds; the story goes on (R6)"
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"message_requeued"' "the message was still requeued"
  fixture pl2 '{"overnight": {"retries": 0}}'
  scenario "stage execute; inplace; task 1/2; wtledger T1 complete a..b; say x" \
           "inbox; ledger Stop: start side"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: start side$" "a start-ledger Stop: in the same unit as the limit ends at once (AC18)"
  assert_missing "$(last_run_dir)/control/-.held" "never held"
  holds_off
}
test_overnight_stop_story_running() {
  fixture ssr
  scenario "stage execute; task 1/3; stopop" "task 2/3"
  run_start
  assert_eq 1 "$(calls)" "stop - on the running story ends it after its unit"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stopped by operator$" "stopped by operator (AC23)"
  assert_eq "" "$(ls -A "$(last_run_dir)/control" 2>/dev/null)" "no control file left"
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"story_state".*"state":"stopped","why":"by operator"' "the story_state why is by operator, as in lanes (R5)"
  assert_not_contains "$(last_run_dir)/events.jsonl" '"why":"stopped by operator"' "never the doubled form"
}
test_overnight_hold_story_running() {
  fixture hsr; holds_on 60
  scenario "$ISO1; holdop" "wtledger final review done" "wtledger shipped https://x/pull/9; stage idle; task -"
  start_bg; wait_held 20
  assert_contains "$R/control/-.held" "^held held by operator until " "hold - holds at the next unit boundary"
  assert_eq 1 "$(calls)" "before the next unit"
  verb resume -; bg_end 60 "the run goes on"
  assert_eq 0 "$BG_STATUS" "and finishes"
  assert_eq 3 "$(calls)" "the remaining units ran"
  holds_off
}
test_overnight_hold_last_unit_done_finishes() {
  fixture hld; holds_on 60
  scenario "stage execute; task 1/1; ledger T1 complete a..b" "ledger final review done" \
           "holdop; ledger shipped https://x/pull/6; stage idle; task -"
  run_start
  assert_eq 0 "$RS_STATUS" "a hold sent during the last unit: the run still finishes done"
  assert_not_contains "$(last_run_dir)/events.jsonl" '"state":"held"' "never held"
  assert_eq "" "$(ls -A "$(last_run_dir)/control" 2>/dev/null)" "the .hold is cleared"
  holds_off
}
test_overnight_run_stop_while_held() {
  fixture rsh; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art"
  start_bg; wait_held 20
  verb stop; assert_contains "$V_OUT" "^stop requested: the run ends after its running unit" "bare stop, as today"
  bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: stopped by user (was held: stop: need art)$" "the halt's reason, then the hold's (AC25)"
  holds_off
}
test_overnight_hold_minutes_zero_ends_at_once() {
  fixture hmz
  scenario "$ISO1; holdop" "wtledger Stop: need art"
  run_start
  assert_eq 2 "$(calls)" "hold_minutes 0: a hold is refused, nothing waits"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: need art$" "a feature Stop: ends at once, as today (AC26)"
  assert_missing "$(last_run_dir)/control/-.held" "never held"
}
test_overnight_requeue_minimal_path() {
  fixture rmp; make_minbin
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; say use the bus" \
           "inbox; task 2/2; wtledger T2 complete b..c" "wtledger final review done" \
           "wtledger shipped https://x/pull/2; stage idle; task -"
  RS_STATUS=0
  ( cd "$P" && PATH="$TMP/minbin" sh "$RUNNER" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 0 "$RS_STATUS" "the channel works under the minimal PATH"
  assert_not_contains "$TMP/rs.err" "not found" "no missing command"
  assert_contains "$CALLS/2.inbox" '^\[1, story\] use the bus$' "say, the hook and the claim ran"
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"message_requeued"' "and the requeue check"
  assert_contains "$(last_run_dir)/report.md" "^- 1 (story, requeues 1): use the bus$" "and the report"
}
test_overnight_orphaned_holds_after_isolation() {
  fixture oho; holds_on 2
  scenario "$ISO1" "cost 1" "cost 1; orphan"
  run_start; R="$(last_run_dir)"
  assert_eq 3 "$(calls)" "the orphaned no-progress ending comes after the retry"
  assert_contains "$R/events.jsonl" '"state":"held","why":"no progress on T2 (orphaned: ' "an orphaned no-progress ending holds after isolation, like any no-progress ending"
  assert_contains "$R/report.md" "^Ending: no progress on T2 (orphaned: .*) (held 0h0m, no reply)$" "the deadline then ends it with the cause kept"
  fixture oho2; holds_on 2
  scenario "stage execute; task 1/2" "cost 1" "cost 1; orphan"
  run_start; R="$(last_run_dir)"
  assert_contains "$R/report.md" "^Ending: no progress on T2 (orphaned: .*)$" "before isolation it ends at once"
  assert_not_contains "$R/events.jsonl" '"state":"held"' "never held"
  holds_off
}

test_overnight_stop_held_by_operator() {
  fixture sho; holds_on 60
  scenario "$ISO1; holdop" "wtledger final review done"
  start_bg; wait_held 20
  assert_contains "$R/control/-.held" "^held held by operator until " "held by the operator"
  verb stop -; bg_end 20 "the run ends within a poll"
  assert_contains "$R/report.md" "^Ending: stopped by operator$" "a stop on an operator-held story is stopped by operator (R5)"
  assert_eq 1 "$(calls)" "no unit ran"
  holds_off
}
test_overnight_stop_pending_never_holds() {
  fixture spn; holds_on 60
  scenario "$ISO1; wtledger Stop: need art; stopop" "wtledger final review done"
  run_start; R="$(last_run_dir)"
  assert_contains "$R/report.md" "^Ending: stopped by operator$" "a stop sent during the unit that ends holdable ends the story (R5)"
  assert_not_contains "$R/events.jsonl" '"state":"held"' "no held event for a hold that never waited"
  assert_missing "$R/control/-.held" "no held record"
  assert_eq 1 "$(calls)" "no unit ran"
  holds_off
}
test_overnight_sighup_while_held() {
  fixture shh; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art"
  start_bg; wait_held 20
  kill -HUP "$RPID"; bg_status
  assert_eq 1 "$BG_STATUS" "a closed terminal exits 1"
  assert_contains "$R/report.md" "^Ending: stop: terminal closed (SIGHUP) (was held: stop: need art)$" "the closed terminal keeps the hold's why (AC25)"
  assert_eq "" "$(ls -A "$R/control" 2>/dev/null)" "no held record is left once a report is written (R25)"
  holds_off
}
# retire_case NAME LEDGERED — a ledgered Directive 1 is retired by `unsay 1`
# in unit 1; unit 2 gets the retire message and records it when LEDGERED=1.
retire_case() {
  fixture "$1"; ledger_add "Directive 1: use the bus"
  if [ "$2" = 1 ]; then _rc_rec="wtledger Directive 1 retired; "; else _rc_rec=""; fi
  scenario "$ISO1; unsay 1" "inbox; ${_rc_rec}task 2/2; wtledger T2 complete b..c" \
           "wtledger final review done" "wtledger shipped https://x/pull/11; stage idle; task -"
  run_start; R="$(last_run_dir)"
}
test_overnight_requeue_retire() {
  retire_case rtr1 1
  assert_not_contains "$R/events.jsonl" '"event":"message_requeued"' "a recorded retire is not requeued"
  assert_not_contains "$R/report.md" "Operator messages left" "nothing left"
  retire_case rtr2 0
  assert_contains "$R/events.jsonl" '"event":"message_requeued","story":"-","id":2,' "an unrecorded retire is requeued"
  assert_contains "$R/report.md" "^- 2 (retire, requeues 1): " "and left, as a retire message"
}


# ---- #39 T10: run selection for status, watch, stop and the channel ----
test_status_two_runs_blocks_oldest_first() {
  fixture s2r; FR_SEQ=2; fake_mrun beta S2=running; _pb="$FR_PID"; FR_SEQ=1; fake_mrun alpha S1=running
  verb status
  assert_eq 0 "$V_STATUS" "status with two live runs exits 0"
  _a="$(grep -n '^== alpha (manifest, pid ' "$V_OUT" | cut -d: -f1)"; _b="$(grep -n '^== beta (manifest, pid ' "$V_OUT" | cut -d: -f1)"
  if [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]; then _pass "alpha's block comes before beta's"; else _fail "block order: alpha=$_a beta=$_b"; fi
  fake_run_end "$FR_PID"; fake_run_end "$_pb"
}
test_status_run_not_live() {
  fixture snl; FR_SEQ=1; fake_mrun alpha S1=running
  verb status --run ghost
  assert_eq 1 "$V_STATUS" "status --run of a run that is not live exits 1"
  assert_contains "$V_OUT" "no live run ghost" "and says so"
  verb status --run alpha
  assert_contains "$V_OUT" "run:" "status --run alpha prints alpha's run line"
  if grep -q '^== ' "$V_OUT"; then _fail "a single selected run has no == header"; else _pass "a single selected run has no == header"; fi
  fake_run_end
}
test_status_registry_root_once() {
  fixture srr; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running
  mkdir -p "$TMP/outside"
  verb_in "$TMP/outside" status
  assert_eq 3 "$V_STATUS" "outside a project, live runs elsewhere exit 3"
  assert_eq 1 "$(grep -c "^== .* — $P\$" "$V_OUT")" "the root's header prints once"
  assert_contains "$V_OUT" "^== .*alpha.* — $P\$" "the header names alpha"
  assert_contains "$V_OUT" "^== .*beta.* — $P\$" "and beta"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
}
test_watch_run_selects() {
  fixture wrs; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running
  STUDIO_OVERNIGHT_WATCH_COUNT=1; export STUDIO_OVERNIGHT_WATCH_COUNT
  verb watch --run beta 1
  assert_eq 0 "$V_STATUS" "watch --run exits 0"
  assert_contains "$V_OUT" "S2" "beta's story is shown"
  if grep -q 'S1' "$V_OUT"; then _fail "alpha's story is not shown"; else _pass "alpha's story is not shown"; fi
  verb watch --run beta
  assert_eq 0 "$V_STATUS" "watch --run with the default seconds"
  unset STUDIO_OVERNIGHT_WATCH_COUNT
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
}
test_stop_two_runs_refuses() {
  fixture s2x; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running
  verb stop
  assert_eq 1 "$V_STATUS" "bare stop with two live runs exits 1"
  assert_contains "$V_OUT" "2 runs are live — nothing stopped:" "says nothing was stopped"
  assert_contains "$V_OUT" "  alpha  " "lists alpha"
  assert_contains "$V_OUT" "  beta  " "lists beta"
  assert_contains "$V_OUT" "stop --run <slug>" "names stop --run"
  assert_contains "$V_OUT" "stop --all" "names stop --all"
  assert_missing "$P/.studio/runs/alpha/stop" "no flag for alpha"
  assert_missing "$P/.studio/runs/beta/stop" "no flag for beta"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
}
test_stop_run_writes_own_flag() {
  fixture srf; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; _ad="$FR_DIR"; FR_SEQ=2; fake_mrun beta S2=running
  verb stop --run beta
  assert_eq 0 "$V_STATUS" "stop --run beta"
  assert_file "$P/.studio/runs/beta/stop" "beta's flag"
  assert_missing "$P/.studio/runs/alpha/stop" "not alpha's"
  verb stop --run "$(basename "$_ad")"
  assert_eq 0 "$V_STATUS" "stop --run <run dir basename>"
  assert_file "$P/.studio/runs/alpha/stop" "alpha's flag"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
  fixture srs; fake_run overnight-srs-1 single
  verb stop --run overnight-srs-1
  assert_eq 0 "$V_STATUS" "stop --run of a single-plan run"
  assert_file "$P/.studio/overnight.stop" "writes the project-wide flag"
  fake_run_end
}
test_stop_all_writes_each_flag() {
  fixture sal; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running; _pb="$FR_PID"
  verb stop --all
  assert_eq 0 "$V_STATUS" "stop --all"
  assert_file "$P/.studio/runs/alpha/stop" "alpha's flag"
  assert_file "$P/.studio/runs/beta/stop" "beta's flag"
  assert_contains "$V_OUT" "stop requested: alpha (pid $_pa)" "one line for alpha"
  assert_contains "$V_OUT" "stop requested: beta (pid $_pb)" "one line for beta"
  rm -f "$P"/.studio/runs/*/stop
  fake_run_end "$_pb"
  verb stop --all
  assert_file "$P/.studio/runs/alpha/stop" "alpha still stopped"
  assert_missing "$P/.studio/runs/beta/stop" "an ended run is skipped"
  fake_run_end "$_pa"
}
# #39 AC10, D15: with a manifest run live, status prints `sessions: <live>/<cap>`
# first: the live slots under <root>/.studio/sessions (an owner whose lane is
# live) and the cap from <root>/.studio/config.json. `status --run` has none.
test_status_sessions_line_first() {
  fixture ssl '{"overnight": {"max_sessions": 3}}'; fake_mrun alpha S1=running
  mkdir -p "$P/.studio/sessions/1"
  printf 'lane=%s\nsession=\nrun=%s\nunit=x\n' "$FR_PID" "$FR_DIR" > "$P/.studio/sessions/1/owner"
  verb status
  assert_eq 0 "$V_STATUS" "status with a manifest run live"
  assert_eq "sessions: 1/3" "$(sed -n 1p "$V_OUT")" "line 1 is the sessions line (#39 AC10)"
  verb status --run alpha
  assert_not_contains "$V_OUT" "^sessions: " "status --run prints no sessions line (D15)"
  fake_run_end
}
test_stop_story_unchanged() {
  fixture ssu; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running
  verb stop S1
  assert_eq 0 "$V_STATUS" "stop S1 with two runs live $(cat "$V_ERR")"
  assert_file "$P/.studio/reports/overnight-alpha-20261004-210000/control/S1.stop" "alpha's story control file"
  assert_missing "$P/.studio/runs/alpha/stop" "no run flag"
  assert_missing "$P/.studio/runs/beta/stop" "none for beta"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
}
test_verbs_channel_resolution_by_story() {
  fixture vcs; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running; _bd="$FR_DIR"
  verb say S2 hello; assert_eq 0 "$V_STATUS" "say S2 $(cat "$V_ERR")"
  assert_file "$_bd/inbox/S2/1.msg" "say S2 reaches beta"
  verb said S2; assert_eq 0 "$V_STATUS" "said S2"
  assert_contains "$V_OUT" "1" "said S2 lists beta's directive"
  verb hold S2; assert_eq 0 "$V_STATUS" "hold S2 $(cat "$V_ERR")"
  assert_file "$_bd/control/S2.hold" "hold on beta"
  printf "held\n" > "$_bd/stories/S2"
  verb resume S2; assert_eq 0 "$V_STATUS" "resume S2 $(cat "$V_ERR")"
  assert_file "$_bd/control/S2.resume" "resume on beta"
  verb unsay S2 1; assert_eq 0 "$V_STATUS" "unsay S2 1 $(cat "$V_ERR")"
  assert_missing "$_bd/inbox/S2/1.msg" "unsay on beta"
  verb stop S2; assert_eq 0 "$V_STATUS" "stop S2"
  assert_file "$_bd/control/S2.stop" "stop on beta"
  assert_missing "$P/.studio/reports/overnight-alpha-20261004-210000/inbox/S2" "nothing for alpha"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
}
test_verbs_channel_run_flag_slug_or_basename() {
  fixture vcr; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running; _bd="$FR_DIR"
  verb say --run beta S2 x; assert_eq 0 "$V_STATUS" "say --run <slug> $(cat "$V_ERR")"
  verb say --run "$(basename "$_bd")" S2 y; assert_eq 0 "$V_STATUS" "say --run <basename>"
  assert_file "$_bd/inbox/S2/2.msg" "both reached beta"
  verb say --run alpha S2 z; assert_eq 1 "$V_STATUS" "--run alpha S2 refuses"
  assert_contains "$V_ERR" "S2 is not in run" "with today's text"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
}
test_verbs_channel_no_run_lists_story() {
  fixture vcn; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S2=running
  verb say S9 x
  assert_eq 1 "$V_STATUS" "no run lists S9"
  assert_contains "$V_ERR" "no live run lists S9" "says so"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
  verb say S9 x
  assert_eq 1 "$V_STATUS" "no run at all"
  assert_contains "$V_ERR" "no live run in $P" "keeps today's text"
}
test_verbs_channel_start_dir_from_lock() {
  fixture vcd; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"
  mkdir -p "$P/wt"; sed -i.bak "s|^start=.*|start=$P/wt|" "$FR_LOCK"; rm -f "$FR_LOCK.bak"
  # resume's dirty check runs in the start dir: a held story, a ledger changed there
  printf 'held\n' > "$FR_DIR/stories/S1"
  ( cd "$P/wt" && g=g; command "${g}it" init -q && mkdir -p .studio/ledger && printf 'x\n' > .studio/ledger/S1.md ) >/dev/null 2>&1
  verb resume S1
  assert_eq 1 "$V_STATUS" "resume is refused"
  assert_contains "$V_ERR" "uncommitted changes in $P/wt" "the dirty check ran in the lock's start dir"
  fake_run_end "$_pa"
}
test_verbs_channel_ambiguous_story_refused() {
  fixture vca; FR_SEQ=1; fake_mrun alpha S1=running; _pa="$FR_PID"; FR_SEQ=2; fake_mrun beta S1=running
  verb say S1 x
  assert_eq 1 "$V_STATUS" "S1 is in two live runs"
  assert_contains "$V_ERR" "S1 is in 2 live runs (alpha, beta)" "names both runs"
  assert_contains "$V_ERR" "--run" "points at --run"
  verb say --run beta S1 y; assert_eq 0 "$V_STATUS" "--run picks one"
  fake_run_end "$FR_PID"; fake_run_end "$_pa"
}
test_help_names_concurrent_runs() {
  out="$(sh "$RUNNER" --help 2>&1)"; printf '%s\n' "$out" > "$TMP/help.txt"
  for w in "status \[--run <slug>\]" "watch \[--run <slug>\]" "stop --run" "stop --all" "max_sessions" 'install or pull omega-ai only when `studio-overnight status` shows no live run' "applies to watch only"; do
    assert_contains "$TMP/help.txt" "$w" "help names $w"
  done
}
# ---- #42: the single-plan runner follows its story (AC38, AC39) ----
# wait_task DIR TASK — up to 10 s for DIR's own pointer to read `task: TASK`.
wait_task() {
  _wt_i=0
  while ! grep -qx "task: $2" "$1/.studio/STATE.md" 2>/dev/null && [ "$_wt_i" -lt 50 ]; do sleep 0.2; _wt_i=$((_wt_i + 1)); done
}
test_single_plan_follows_story_after_unit_1() {
  fixture fol
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b" \
           "task 2/2; wtledger T2 complete b..c" "wtledger final review done" \
           "wtledger shipped https://x/pull/1; stage idle; task -"
  run_start
  WE="$(cd "$TMP_WT/wt-feat" && pwd -P)"
  assert_eq "$P" "$(cat "$CALLS/1.pwd")" "unit 1 starts in START_DIR"
  assert_eq "$WE" "$(cat "$CALLS/2.pwd")" "unit 2 starts in the story's worktree"
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "the run ends done"
  assert_eq idle "$(cd "$P" && sh "$STATE_BIN" get stage)" "P is idle after the hand-off"
  assert_contains "$CALLS/1.lock" "^spec=docs/spec.md$" "the lock persists the run's spec"
  assert_contains "$HOME/.claude-gamedev/runs/last" "^spec=docs/spec.md$" "and so does the registry entry"
}
test_single_plan_rerun_after_stop_before_handoff() {
  fixture rrs
  scenario "stage execute; stopbeforec" \
           "wtcheck; branch feat; task 1/2; wtledger T1 complete a..b" \
           "task 2/2; wtledger T2 complete b..c; wtledger final review done" \
           "wtledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: stopped before isolation$" "unit 1 stops before (c)"
  ( cd "$P" && git add .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm stop ) >/dev/null 2>&1
  run_start
  assert_eq 1 "$(cat "$CALLS/2.wt")" "the re-run's worktree exits 1 (no feature branch recorded)"
  assert_eq "$(cd "$TMP_WT/wt-feat" && pwd -P)" "$(cat "$CALLS/3.pwd")" "unit 2 of the re-run runs in the story worktree"
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "and it finishes"
}
test_single_plan_story_not_found_stops() {
  fixture snf
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; rmwt feat"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: story docs/spec.md not found$" "a removed story worktree stops the run"
  assert_eq 1 "$(calls)" "no unit runs once the story is gone"
}
test_single_plan_resume_line_names_story_worktree() {
  fixture rln
  scenario "$ISO1" "wtledger Stop: need art"
  run_start
  WE="$(cd "$TMP_WT/wt-feat" && pwd -P)"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: need art$" "the story's Stop: ends the run"
  assert_eq "cd '$WE' && '$RUNNER' start" "$(tail -n 1 "$(last_run_dir)/report.md")" "the Resume line changes into the story's worktree"
}
test_single_plan_ambiguous_story_stops() {
  fixture amb
  scenario "$ISO1; dupstory dup" "task 2/2"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: ambiguous story docs/spec.md$" "two checkouts holding the spec stop the run, never a guess"
  assert_eq 1 "$(calls)" "no unit runs in either"
}
test_single_plan_preflight_names_story() {
  fixture pns
  scenario "$ISO1" "wtledger Stop: need art"
  run_start
  WE="$(cd "$TMP_WT/wt-feat" && pwd -P)"
  run_start
  assert_eq 2 "$RS_STATUS" "a start from the idle main checkout is refused"
  assert_contains "$RS_ERR" "no spec or plan set (studio-state get spec, get plan) — the story is in $WE$" "the refusal names where the story is"
  assert_eq 2 "$(calls)" "no unit ran"
}
test_single_plan_from_story_worktree() {
  fixture fsw
  ( cd "$P" && sh "$STATE_BIN" reset --keep-ledger ) >/dev/null 2>&1
  git -C "$P" worktree add -q "$TMP_WT/wa" -b wa >/dev/null 2>&1
  WA="$(cd "$TMP_WT/wa" && pwd -P)"
  ( cd "$WA" && sh "$STATE_BIN" set stage plan && sh "$STATE_BIN" set spec docs/spec.md \
      && sh "$STATE_BIN" set plan docs/plan.md ) >/dev/null 2>&1
  assert_eq plan "$(cd "$WA" && sh "$STATE_BIN" get stage)" "WA's own pointer is at plan"
  _ck="$(cksum < "$P/.studio/STATE.md")"
  scenario "stage execute; task 1/1; ledger T1 complete a..b" "ledger final review done" \
           "ledger shipped https://x/pull/1; stage idle; task -"
  RS_STATUS=0
  ( cd "$WA" && sh "$RUNNER" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 0 "$RS_STATUS" "a single-plan run from a story worktree runs to done (AC39)"
  assert_eq "$_ck" "$(cksum < "$P/.studio/STATE.md")" "the main pointer stays byte-identical"
  assert_eq "$WA" "$(cat "$CALLS/1.pwd")" "unit 1 runs in WA"
  assert_eq "$WA" "$(cat "$CALLS/2.pwd")" "and so does unit 2"
}
test_single_plan_in_place_keeps_main_pointer() {
  fixture ipk
  scenario "stage execute; inplace; task 1/2; ledger T1 complete a..b" "task 2/2; ledger T2 complete b..c" \
           "ledger final review done" "ledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_eq 0 "$RS_STATUS" "an in-place story runs to done"
  assert_eq "$P" "$(cat "$CALLS/2.pwd")" "unit 2 starts in P"
  assert_eq feat "$(cd "$P" && sh "$STATE_BIN" get branch)" "the main pointer records P's branch"
  assert_not_contains "$P/.studio/STATE.md" "handed" "no hand-off ran"
}
test_channel_ledger_follows_story() {
  fixture clf; holds_on 60
  scenario "$ISO1; wtledger Directive 7: keep the bus" "wtledger Stop: need art"
  start_bg; wait_held 20
  # A second worktree story at execute: worktree's candidate list from P has two.
  ( git -C "$P" worktree add -q "$TMP_WT/wt-oth" -b oth && cd "$TMP_WT/wt-oth" \
      && sh "$STATE_BIN" set spec docs/other.md && sh "$STATE_BIN" set stage execute ) >/dev/null 2>&1
  verb said -
  assert_contains "$V_OUT" "^7  active  keep the bus$" "said reads the ledger where the story's pointer is"
  verb say - x
  assert_eq 0 "$V_STATUS" "say - succeeds during the hold"
  assert_eq 8 "$(cat "$V_OUT")" "the next id counts the story worktree's Directive lines"
  verb stop -; bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: stop: need art$" "with the story's Stop:"
  holds_off
}
test_status_reads_persisted_spec() {
  fixture srp; scenario "$ISO1; sleep 3"
  start_bg; wait_task "$TMP_WT/wt-feat" 1/2
  verb status
  assert_contains "$V_OUT" "^task: 1/2$" "status reads the task in the story's worktree"
  bg_end 40 "the run ends"
  fixture srp2; scenario "$ISO1; rmwt feat; sleep 3"
  start_bg; wait_for "$CALLS/1.t0"
  _i=0; until { [ -n "$(git -C "$P" branch --list feat)" ] && [ ! -d "$TMP_WT/wt-feat" ]; } || [ "$_i" -ge 50 ]; do sleep 0.2; _i=$((_i + 1)); done
  verb status
  assert_contains "$V_OUT" "^task: story docs/spec.md not found$" "an unresolved story is named in place of the task"
  bg_end 40 "the run ends"
}
test_single_plan_ignores_new_story_in_start() {
  fixture ins
  scenario "$ISO1; sleep 3" "task 2/2; wtledger T2 complete b..c" "wtledger final review done" \
           "wtledger shipped https://x/pull/1; stage idle; task -"
  start_bg; wait_task "$TMP_WT/wt-feat" 1/2
  ( cd "$P" && sh "$STATE_BIN" set stage brainstorm && sh "$STATE_BIN" set spec docs/other.md \
      && sh "$STATE_BIN" ledger "Stop: unrelated" ) >/dev/null 2>&1
  assert_contains "$P/.studio/ledger/other.md" "Stop: unrelated" "a new story in P has a Stop: line"
  bg_end 60 "the run ends"
  assert_eq 0 "$BG_STATUS" "the run is not stopped by an unrelated story in P"
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "it finishes"
  assert_eq 4 "$(calls)" "every unit ran"
}
run_tests test_overnight_report_done test_overnight_report_not_done test_overnight_preflight_env_warns_not_blocks \
  test_overnight_report_anchors test_overnight_resume_quote test_overnight_label_t1 \
  test_overnight_session_seconds_refused test_overnight_claim_without_run_dir \
  test_overnight_report_runner_error test_overnight_crash_resume test_overnight_status \
  test_overnight_timeout test_overnight_kill_after_grace \
  test_overnight_stop_file test_overnight_sigterm test_overnight_sigint test_overnight_sighup \
  test_overnight_stop_no_run test_overnight_inhibitor test_overnight_no_inhibitor \
  test_overnight_help test_events_contract_doc test_overnight_dry_run \
  test_overnight_preflight_refusals test_overnight_preflight_all_failures \
  test_overnight_config_refusals test_overnight_deny_file_required \
  test_overnight_lock test_overnight_first_use_ignores \
  test_overnight_start_args test_overnight_reclaim_race test_overnight_reclaim_finds_live_lock \
  test_overnight_sequence_to_done test_overnight_launch_argv test_overnight_ignores_inherited_lane_vars \
  test_overnight_retry_then_no_progress test_overnight_orphaned_unit test_overnight_progress_resets_retry \
  test_overnight_retries_zero test_overnight_stop_line test_overnight_copied_stop_not_new \
  test_overnight_run_budget test_overnight_cost_unknown test_overnight_unexpected_stage \
  test_overnight_overhead test_overnight_unknown_label_stops \
  test_overnight_models_by_unit test_overnight_check_unit test_overnight_adopt_config_refusals test_overnight_config_refusals_v2 \
  test_overnight_default_branch_required test_overnight_deny_merge_basename \
  test_overnight_run_usd_default_uncapped \
  test_overnight_deny_rules_basic test_overnight_deny_rules_no_origin_head test_overnight_deny_rules_merge_basename \
  test_overnight_deny_rules_dir test_overnight_deny_rules_outside_git test_overnight_deny_rules_empty_file \
  test_overnight_deny_rules_usage test_overnight_deny_rules_match_launch \
  test_overnight_origin_written test_overnight_origin_absent_without_variable test_overnight_origin_refused \
  test_overnight_hold_config_refused test_overnight_channel_file test_overnight_unit_env \
  test_overnight_events_two_units \
  test_say_writes_message \
  test_say_dash_text_and_unit \
  test_say_empty_text_exit_2 \
  test_say_ids_ledger_and_inbox \
  test_say_cap \
  test_say_cap_counts_characters test_say_bad_directive_chars_defaults test_inbox_lock_failures \
  test_said_lists_states \
  test_unsay_pending_active_delivered \
  test_unsay_id_prefix \
  test_unsay_loses_race_to_hook \
  test_hold_resume_stop_table \
  test_hold_resume_stop_usage_and_unwritable test_hold_minutes_zero \
  test_single_plan_verbs \
  test_resume_refused_dirty_ledger \
  test_resume_from_feature_worktree \
  test_verbs_refusals \
  test_verbs_run_pinning test_verbs_per_run_channel_and_stop_run test_overnight_lock_refuses_live_manifest \
  test_inbox_lock_stale_broken \
  test_inbox_lock_busy \
  test_inbox_lock_released_on_signal \
  test_inbox_unlock_after_release_keeps_foreign_lock \
  test_channel_sourced_only \
  test_overnight_hold_on_feature_stop \
  test_overnight_start_ledger_stop_ends_at_once \
  test_overnight_resume_runs_next_unit \
  test_overnight_new_stop_holds_again \
  test_overnight_hold_deadline \
  test_overnight_stop_beats_resume \
  test_overnight_resume_wins_at_deadline \
  test_overnight_requeue_then_hold \
  test_overnight_recorded_directive_stays_delivered \
  test_overnight_requeue_id_prefix \
  test_overnight_requeue_done_no_hold \
  test_overnight_requeue_corrupt_header \
  test_overnight_prestop_and_limit_end_at_once \
  test_overnight_stop_story_running \
  test_overnight_hold_story_running \
  test_overnight_hold_last_unit_done_finishes \
  test_overnight_run_stop_while_held \
  test_overnight_hold_minutes_zero_ends_at_once \
  test_overnight_requeue_minimal_path \
  test_overnight_orphaned_holds_after_isolation \
  test_overnight_stop_held_by_operator \
  test_overnight_stop_pending_never_holds \
  test_overnight_sighup_while_held \
  test_overnight_requeue_retire \
  test_status_two_runs_blocks_oldest_first test_status_run_not_live test_status_registry_root_once \
  test_watch_run_selects test_stop_two_runs_refuses test_stop_run_writes_own_flag test_stop_all_writes_each_flag \
  test_stop_story_unchanged test_verbs_channel_resolution_by_story test_verbs_channel_run_flag_slug_or_basename \
  test_verbs_channel_no_run_lists_story test_verbs_channel_ambiguous_story_refused test_verbs_channel_start_dir_from_lock test_help_names_concurrent_runs \
  test_status_sessions_line_first \
  test_single_plan_follows_story_after_unit_1 test_single_plan_rerun_after_stop_before_handoff \
  test_single_plan_story_not_found_stops test_single_plan_resume_line_names_story_worktree \
  test_single_plan_ambiguous_story_stops test_single_plan_preflight_names_story \
  test_single_plan_from_story_worktree test_single_plan_in_place_keeps_main_pointer \
  test_channel_ledger_follows_story test_status_reads_persisted_spec \
  test_single_plan_ignores_new_story_in_start
