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
  refuse_case "live lock" "pid $DUMMY"
  kill "$DUMMY" 2>/dev/null; wait "$DUMMY" 2>/dev/null
  # A stale lock: the pid is dead. The run proceeds with a warning
  # (one no-progress-free session: it ships).
  scenario "stage execute; ledger shipped https://x/pull/1; stage idle; task -"
  run_start
  assert_contains "$RS_ERR" "reclaiming stale lock (pid $DUMMY)" "a dead pid is reclaimed with a warning"
  assert_contains "$CALLS/1.lock" "^pid=" "the lock names the runner's pid during the run"
  assert_missing "$P/.studio/overnight.lock" "the lock is removed when the run ends"
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

run_tests test_overnight_help test_overnight_dry_run \
  test_overnight_preflight_refusals test_overnight_preflight_all_failures \
  test_overnight_config_refusals test_overnight_deny_file_required
