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
printf '%s\n' "${OMEGA_AUTOPILOT:-unset}" > "$CALLS/$n.env"
root="$(sh "$STUB_STATE_BIN" root)"
cp "$root/.studio/overnight.lock" "$CALLS/$n.lock" 2>/dev/null
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
    "branch "*)   b="${act#branch }"
                  git worktree add -q "$TMP_WT/wt-$b" -b "$b" >/dev/null 2>&1
                  sh "$STUB_STATE_BIN" set branch "$b" ;;
    "wtledger "*) ( cd "$(sh "$STUB_STATE_BIN" worktree)" && sh "$STUB_STATE_BIN" ledger "${act#wtledger }" ) ;;
    "cost "*)     cost="${act#cost }" ;;
    nocost)       cost="" ;;
    "sleep "*)    sleep "${act#sleep }" ;;
    ignoreterm)   trap '' TERM ;;
    hang)         while :; do sleep 1; done ;;
    rotsv)        r="$(sed -n 's/^run=//p' "$root/.studio/overnight.lock")"
                  touch "$r/units.tsv"; chmod 444 "$r/units.tsv" ;;
    "exit "*)     code="${act#exit }" ;;
  esac
done
printf '{"type":"system","subtype":"init"}\n'
[ -z "$cost" ] || printf '{"type":"result","subtype":"success","total_cost_usd":%s}\n' "$cost"
date +%s > "$CALLS/$n.t1"
exit "$code"
STUB
printf '#!/bin/sh\nexec claude "$@"\n' > "$FAKE/claude-gd"
printf '#!/bin/sh\nexit "${GH_STATUS:-0}"\n' > "$FAKE/gh"
# A fake caffeinate: records its argv, then lives until the -w pid dies.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$CALLS/caffeinate.args"\nwhile kill -0 "$3" 2>/dev/null; do sleep 1; done\n' > "$FAKE/caffeinate"
chmod +x "$FAKE"/*
export PATH="$FAKE:$PATH" STUB_STATE_BIN="$STATE_BIN"

# fixture NAME [CONFIG_JSON] — a committed project at stage plan with an
# approved spec and plan (with ## Decisions); fresh $CALLS and scenario.
fixture() {
  P="$TMP/$1"; CALLS="$TMP/calls-$1"; TMP_WT="$TMP/wts-$1"
  OVERNIGHT_SCENARIO="$TMP/scenario-$1"
  export CALLS TMP_WT OVERNIGHT_SCENARIO
  mkdir -p "$P/docs" "$CALLS" "$TMP_WT"; : > "$OVERNIGHT_SCENARIO"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
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

test_overnight_help() {
  out="$(sh "$RUNNER" --help 2>&1)"; st=$?
  assert_eq 0 "$st" "--help exits 0"
  printf '%s\n' "$out" > "$TMP/help.txt"
  for w in "start \[--dry-run\]" "status" "stop" "STUDIO_OVERNIGHT_SESSION_SECONDS" "overnight-deny.txt" "report.md"; do
    assert_contains "$TMP/help.txt" "$w" "help names $w"
  done
  assert_contains "$TMP/help.txt" "$RUNNER" "help names the runner by its absolute path"
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
  for bad in '"session_usd": 0' '"session_usd": 201' '"run_usd": 2001' '"session_minutes": 9' \
             '"session_minutes": 1.5' '"retries": 4' '"retries": "two"' '"kill_grace_seconds": 4'; do
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
  mkdir -p "$TMP/denybin"; cp "$RUNNER" "$STATE_BIN" "$TMP/denybin/"
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
  R="$(grep -v '^#' "$deny" | grep -c .)"
  assert_eq "$(printf -- '--disallowedTools\n'; grep -v '^#' "$deny" | grep .)" \
    "$(tail -n "$((R + 1))" "$a")" "--disallowedTools is the last option, followed by every rule in file order"
  assert_eq "1" "$(cat "$CALLS/1.env")" "OMEGA_AUTOPILOT=1 reaches the session"
  assert_eq "$P" "$(cat "$CALLS/1.pwd")" "every session starts in START_DIR"
}

test_overnight_retry_then_no_progress() {
  fixture retry; scenario "cost 1" "cost 1"; run_start
  d="$(last_run_dir)"
  assert_eq 1 "$RS_STATUS" "no progress exits 1"
  assert_eq 2 "$(calls)" "one retry, then stop"
  assert_file "$d/2-T1-retry.jsonl" "the retry is labelled T1-retry"
  assert_contains "$d/report.md" "no progress on T1" "the ending names the unit"
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
  assert_contains "$(last_run_dir)/report.md" "stop: no Godot binary (studio-test exit 2)" "the reason is printed verbatim"
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
  assert_contains "$(last_run_dir)/report.md" "no progress on T1" "two killed sessions with no progress stop the run"
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
}

test_overnight_no_inhibitor() {
  # A PATH holding only what the runner needs, and no caffeinate or
  # systemd-inhibit.
  fixture nocaf; done_scenario
  mkdir -p "$TMP/minbin"
  for u in sh git sed awk grep sort comm date ps pkill kill sleep cat mkdir rm touch \
           head tail tr dirname basename readlink wc uname mktemp cp mv chmod env printf; do
    p="$(command -v "$u" 2>/dev/null)" && case "$p" in /*) ln -sf "$p" "$TMP/minbin/$u" ;; esac
  done
  for f in claude claude-gd gh; do ln -sf "$FAKE/$f" "$TMP/minbin/$f"; done
  RS_STATUS=0
  ( cd "$P" && PATH="$TMP/minbin" sh "$RUNNER" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 0 "$RS_STATUS" "the run continues without a sleep inhibitor"
  assert_contains "$TMP/rs.err" "no sleep inhibitor" "one warning names the missing inhibitor"
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
  kill -KILL "$RPID"; wait "$RPID" 2>/dev/null
  # The killed runner's orphans: its watchdog subshell (same argv as the
  # runner), then the sleeps of the stub and of the watchdog (default 5400 s).
  pkill -KILL -f "sh $RUNNER start" 2>/dev/null
  pkill -KILL -f "sleep 30" 2>/dev/null; pkill -KILL -f "sleep 5400" 2>/dev/null
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
  ( cd "$P" && sh "$RUNNER" stop ) >/dev/null; bg_status
  assert_status 1 "status with no run exits 1" -- sh -c "cd '$P' && sh '$RUNNER' status"
  assert_eq "no run" "$(cd "$P" && sh "$RUNNER" status 2>&1)" "status prints no run"
}

run_tests test_overnight_report_done test_overnight_report_not_done \
  test_overnight_report_runner_error test_overnight_crash_resume test_overnight_status \
  test_overnight_timeout test_overnight_kill_after_grace \
  test_overnight_stop_file test_overnight_sigterm test_overnight_sigint test_overnight_sighup \
  test_overnight_stop_no_run test_overnight_inhibitor test_overnight_no_inhibitor \
  test_overnight_help test_overnight_dry_run \
  test_overnight_preflight_refusals test_overnight_preflight_all_failures \
  test_overnight_config_refusals test_overnight_deny_file_required \
  test_overnight_lock test_overnight_first_use_ignores \
  test_overnight_start_args test_overnight_reclaim_race \
  test_overnight_sequence_to_done test_overnight_launch_argv \
  test_overnight_retry_then_no_progress test_overnight_progress_resets_retry \
  test_overnight_retries_zero test_overnight_stop_line test_overnight_copied_stop_not_new \
  test_overnight_run_budget test_overnight_cost_unknown test_overnight_unexpected_stage \
  test_overnight_overhead
