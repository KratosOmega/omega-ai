#!/bin/sh
# Tests for install.sh and uninstall.sh (#28). Offline: a temp HOME, the stub Multica
# board, stub security and launchctl, recorder `claude-gd`, a minimal PATH. Never the
# real Keychain, launchd, Multica CLI or ~/.claude-gamedev.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
. "$REPO_ROOT/tests/assert.sh"

# A clean environment: nothing from the caller's Multica/omega session.
for _v in $(env | sed -n 's/^\(MULTICA_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(OMEGA_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(STUB_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done
unset STUDIO_RUN_ORIGIN GIT_DIR GIT_WORK_TREE
PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE

TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
M="$REPO_ROOT/integrations/multica"
TESTS="$M/tests"
INSTALL="$M/install.sh"
UNINSTALL="$M/uninstall.sh"
FAKE="$TMP/fake"; SEC="$TMP/sec"; LC="$TMP/lc"; PROJ="$TMP/proj"
HOME="$TMP/home"
BASE="$HOME/.claude-gamedev/multica"
LA="$HOME/Library/LaunchAgents/ai.omega.multica-bridge.plist"
TOK=mul_testtoken123456
PY="${OMEGA_MULTICA_TEST_PY:-}"
if [ -z "$PY" ]; then
  if /usr/bin/python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then PY=/usr/bin/python3; else PY=python3; fi
fi
PATH="$FAKE:/usr/bin:/bin"
export HOME PATH
OMEGA_MULTICA_SECURITY="$TESTS/stub-security"; STUB_SECURITY_DIR="$SEC"
OMEGA_MULTICA_LAUNCHCTL="$TESTS/stub-launchctl"; STUB_LAUNCHCTL_DIR="$LC"
OMEGA_MULTICA_RUNTIME_WAIT=4; OMEGA_MULTICA_SELFTEST_WAIT=10
export OMEGA_MULTICA_SECURITY STUB_SECURITY_DIR OMEGA_MULTICA_LAUNCHCTL STUB_LAUNCHCTL_DIR
export OMEGA_MULTICA_RUNTIME_WAIT OMEGA_MULTICA_SELFTEST_WAIT
PY_REAL="$("$PY" -c 'import os, sys; print(os.path.realpath(sys.executable))')"

mkdir -p "$FAKE" "$PROJ"
printf '#!/bin/sh\nexit 0\n' > "$FAKE/claude-gd"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/oldpy"
chmod 755 "$FAKE/claude-gd" "$FAKE/oldpy"

# reset — a fresh home, board, Keychain and launchd.
reset() {
  rm -rf "$HOME" "$TMP/cli" "$SEC" "$LC"
  mkdir -p "$HOME" "$SEC" "$LC"
  "$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import bridgetest; bridgetest.Board(sys.argv[2])' \
    "$TESTS" "$TMP/cli"
  CALLS="$TMP/cli/stub-state/calls.jsonl"
}
# boardpy CODE — edit the stub board: CODE sees the dict `b`.
boardpy() {
  "$PY" -c 'import json, sys
p = sys.argv[1] + "/stub-state/board.json"
b = json.load(open(p))
exec(sys.argv[2])
json.dump(b, open(p, "w"))' "$TMP/cli" "$1"
}
# inst ARGS… — install.sh with the token on stdin; output to $TMP/out, $TMP/err; exit code in $RC.
inst() {
  printf '%s\n' "$TOK" | sh "$INSTALL" --workspace-id ws-test --cli "$TMP/cli/multica" --python "$PY" "$@" \
    >"$TMP/out" 2>"$TMP/err"; RC=$?
  [ -z "${DEBUG_ERR:-}" ] || sed 's/^/    stderr: /' "$TMP/err" >&2
}
uninst() {
  sh "$UNINSTALL" "$@" >"$TMP/out" 2>"$TMP/err" </dev/null; RC=$?
  [ -z "${DEBUG_ERR:-}" ] || sed 's/^/    stderr: /' "$TMP/err" >&2
}
# fault CMD EXIT STDERR — every `multica CMD` call fails with that exit code and stderr line.
fault() {
  "$PY" -c 'import json, sys
json.dump([{"cmd": sys.argv[2], "exit": int(sys.argv[3]), "stderr": sys.argv[4], "count": -1}],
          open(sys.argv[1] + "/stub-state/faults.json", "w"))' "$TMP/cli" "$1" "$2" "$3"
}
# fast_sleep on|off — a `sleep` first on PATH that returns at once and logs its argument to $TMP/sleeps,
# so the wait loops are counted, not timed (immune to machine load).
fast_sleep() {
  rm -f "$FAKE/sleep" "$TMP/sleeps"
  if [ "$1" = on ]; then
    printf '#!/bin/sh\necho "$1" >> "%s/sleeps"\n' "$TMP" > "$FAKE/sleep"; chmod 755 "$FAKE/sleep"; : > "$TMP/sleeps"
  fi
}
nsleeps() { grep -c . "$TMP/sleeps" 2>/dev/null || true; }
# verbs FILE — the bootout/bootstrap/kickstart verbs of a launchctl call log, in call order, comma terminated.
verbs() { grep -o '"\(bootout\|bootstrap\|kickstart\)"' "$1" | tr -d '"' | tr '\n' ','; }
# clear_calls — forget the calls so far.
clear_calls() { : > "$CALLS"; : > "$LC/calls"; : > "$SEC/calls"; }
# count FILE PATTERN — lines of FILE matching the fixed string.
count() { grep -cF -- "$2" "$1" 2>/dev/null || true; }
# mcalls WORDS — board calls whose argv starts with WORDS (a JSON list prefix, e.g. '"property", "create"').
mcalls() { count "$CALLS" "\"argv\": [$1"; }
mtime() { "$PY" -c 'import os, sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }
# jfield FILE EXPR — evaluate a Python expression on the JSON in FILE (as `d`).
jfield() { "$PY" -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
# lastcall WORDS — the argv (one JSON line) of the last call starting with WORDS.
lastcall() { grep -F -- "\"argv\": [$1" "$CALLS" | tail -n 1; }
# argcheck KIND — facts about the last `agent create` call, one per line.
argcheck() {
  "$PY" -c 'import json, sys
rec = [json.loads(l) for l in open(sys.argv[1]) if l.startswith("{\"argv\": [\"agent\", \"create\"")][-1]
a = rec["argv"]
def val(flag):
    return a[a.index(flag) + 1]
want = open(sys.argv[2], encoding="utf-8").read().rstrip("\n")
print("runtime-id=" + val("--runtime-id"))
print("max=" + val("--max-concurrent-tasks"))
print("name=" + val("--name"))
print("instructions-match=" + str(val("--instructions") == want))
print("env-stdin=" + str("--custom-env-stdin" in a))
print("stdin=" + json.dumps(json.loads(rec["stdin"]), sort_keys=True))' "$CALLS" "$M/agent-instructions.md"
}

test_install_fresh() {
  reset
  inst
  assert_eq 0 "$RC" "fresh install exits 0"
  _b="$TMP/cli/stub-state/board.json"
  assert_eq "omega_run,omega_story" "$(jfield "$_b" '",".join(sorted(p["name"] for p in d["properties"]))')" "both properties exist"
  assert_eq "claude-multica,omega-multica-agent" \
    "$(jfield "$_b" '",".join(sorted(p["command_name"] for p in d["runtime_profiles"]))')" "both runtime profiles exist (command-name form)"
  assert_eq "2" "$(jfield "$_b" 'len(d["runtimes"])')" "both runtimes exist"
  assert_eq "claude,claude" "$(jfield "$_b" '",".join(p["protocol_family"] for p in d["runtime_profiles"])')" "profiles use protocol family claude"
  for _k in server_url workspace_id operator_member_id roots poll_seconds cli studio_overnight; do
    assert_contains "$BASE/config" "^$_k=" "config has $_k"
  done
  assert_contains "$BASE/config" '^operator_member_id=m-op$' "config operator_member_id"
  assert_contains "$BASE/config" '^workspace_id=ws-test$' "config workspace_id"
  assert_contains "$BASE/config" "^studio_overnight=$REPO_ROOT/studios/game-dev/bin/studio-overnight\$" "config studio_overnight"
  assert_eq "-rw-------" "$(ls -l "$BASE/config" | cut -c1-10)" "config is mode 600"
  assert_eq "$REPO_ROOT/integrations/multica/bin/claude-multica" "$(readlink "$HOME/.local/bin/claude-multica")" "claude-multica link"
  assert_eq "$REPO_ROOT/integrations/multica/bin/omega-multica-agent" "$(readlink "$HOME/.local/bin/omega-multica-agent")" "omega-multica-agent link"
  assert_file "$BASE/lib/bin/multica-bridge" "lib has the bridge entry point"
  assert_file "$BASE/lib/bridge/service.py" "lib has the bridge package"
  assert_file "$LC/loaded" "the agent is loaded"
  assert_status 0 "the loaded plist lints" -- plutil -lint -s "$LC/loaded"
  assert_eq "$PY_REAL" "$("$PY" -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["ProgramArguments"][0])' "$LC/loaded")" "plist names the interpreter's real path"
  assert_eq "True" "$("$PY" -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["KeepAlive"])' "$LC/loaded")" "plist KeepAlive"
  assert_eq "$HOME" "$("$PY" -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["EnvironmentVariables"]["HOME"])' "$LC/loaded")" "plist HOME"
  assert_eq "$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$("$PY" -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["EnvironmentVariables"]["PATH"])' "$LC/loaded")" "plist PATH (R45)"
  assert_eq "True" "$(jfield "$BASE/selftest.json" 'd["ok"]')" "the real self-test passed through the copied lib"
  assert_contains "$TMP/out" 'Documents Folder' "the P5 step is printed"
  assert_contains "$TMP/out" 'self-test passed' "the success line is printed"
  assert_eq 1 "$(count "$LC/calls" '"kickstart"')" "one kickstart"
}

test_install_token_never_in_argv_files_or_output() {
  reset
  inst --agent gd --project "$PROJ"
  assert_eq 0 "$RC" "install with an agent exits 0"
  assert_eq "0" "$("$PY" -c 'import json, sys
tok = sys.argv[2]
n = 0
for l in open(sys.argv[1]):
    r = json.loads(l)
    if tok in json.dumps(r["argv"]) or tok in r["stdin"]:
        n += 1
print(n)' "$CALLS" "$TOK")" "the token is in no stub-multica argv or stdin"
  assert_not_contains "$LC/calls" "$TOK" "the token is in no launchctl call"
  assert_not_contains "$SEC/calls" "$TOK" "the token is in no security argv"
  assert_eq "" "$(grep -rlF -- "$TOK" "$HOME" 2>/dev/null)" "the token is in no file under HOME"
  assert_not_contains "$TMP/out" "$TOK" "the token is not in stdout"
  assert_not_contains "$TMP/err" "$TOK" "the token is not in stderr"
  assert_not_contains "$LC/loaded" "$TOK" "the token is not in the plist"
}

test_install_rerun_changes_nothing() {
  reset
  inst; assert_eq 0 "$RC" "first install exits 0"
  _c="$(mtime "$BASE/config")"; _p="$(mtime "$LA")"
  clear_calls
  sleep 1
  inst
  assert_eq 0 "$RC" "second install exits 0"
  assert_eq 0 "$(mcalls '"property", "create"')" "no property create"
  assert_eq 0 "$(mcalls '"runtime", "profile", "create"')" "no profile create"
  assert_eq 0 "$(mcalls '"agent", "create"')" "no agent create"
  assert_eq 0 "$(count "$LC/calls" '"bootout"')" "no bootout"
  assert_eq 0 "$(count "$LC/calls" '"bootstrap"')" "no bootstrap"
  assert_eq 1 "$(count "$LC/calls" '"kickstart"')" "one kickstart"
  assert_eq "$_c" "$(mtime "$BASE/config")" "config mtime unchanged"
  assert_eq "$_p" "$(mtime "$LA")" "plist mtime unchanged"
  assert_eq "True" "$(jfield "$BASE/selftest.json" 'd["ok"]')" "the self-test passed again"
}

test_install_token_prompt_once() {
  reset
  inst; clear_calls
  inst
  assert_eq 0 "$(count "$SEC/calls" 'add-generic-password')" "the second run does not prompt for the token"
}

test_install_new_token() {
  reset
  inst; clear_calls
  inst --new-token
  assert_eq 0 "$RC" "--new-token run exits 0"
  assert_eq 1 "$(count "$SEC/calls" 'add-generic-password')" "--new-token stores the token once"
}

test_install_token_rejected() {
  reset
  boardpy 'b["token"] = "mul_someoneelse"'
  inst
  assert_eq 1 "$RC" "a rejected token exits 1"
  assert_contains "$TMP/err" 'step 3' "stderr names step 3"
  assert_contains "$TMP/err" '--new-token' "stderr names --new-token"
  assert_missing "$BASE/config" "no config written"
}

test_install_property_archived_refused() {
  reset
  boardpy 'b["properties"][0]["archived"] = True'
  inst
  assert_eq 1 "$RC" "an archived property exits 1"
  assert_contains "$TMP/err" 'step 5' "stderr names step 5"
  assert_contains "$TMP/err" 'omega_run is archived' "stderr names the property"
}

test_install_property_wrong_type_refused() {
  reset
  boardpy 'b["properties"][1]["type"] = "select"'
  inst
  assert_eq 1 "$RC" "a wrong-type property exits 1"
  assert_contains "$TMP/err" 'omega_story exists with type select, not text' "stderr names the type"
}

test_install_not_admin_refused() {
  reset
  boardpy 'b["properties"] = []; b["role"] = "member"'
  inst
  assert_eq 1 "$RC" "a member cannot create properties: exit 1"
  assert_contains "$TMP/err" 'step 5' "stderr names step 5"
  assert_contains "$TMP/err" 'owner or admin' "stderr says owner or admin"
}

test_install_runtime_wait_times_out() {
  reset
  boardpy 'b["auto_runtime"] = False'
  fast_sleep on
  inst
  _n="$(nsleeps)"
  fast_sleep off
  assert_eq 1 "$RC" "no runtime: exit 1"
  assert_contains "$TMP/err" 'multica daemon restart' "stderr names the daemon restart"
  assert_eq 2 "$_n" "the 4 s limit is two 2 s waits (counted, not timed)"
}

test_install_wait_limit_hooks_must_be_numeric() {
  reset
  boardpy 'b["auto_runtime"] = False'
  fast_sleep on
  OMEGA_MULTICA_RUNTIME_WAIT=abc; export OMEGA_MULTICA_RUNTIME_WAIT
  inst
  _n="$(nsleeps)"
  OMEGA_MULTICA_RUNTIME_WAIT=4; export OMEGA_MULTICA_RUNTIME_WAIT
  assert_eq 1 "$RC" "a non-numeric runtime wait still ends: exit 1"
  assert_eq 30 "$_n" "a non-numeric runtime wait falls back to 60 s (thirty 2 s waits)"
  reset
  printf 'none\n' > "$LC/mode"
  OMEGA_MULTICA_SELFTEST_WAIT=abc; export OMEGA_MULTICA_SELFTEST_WAIT
  fast_sleep on
  inst
  _n="$(nsleeps)"
  OMEGA_MULTICA_SELFTEST_WAIT=10; export OMEGA_MULTICA_SELFTEST_WAIT
  fast_sleep off
  assert_eq 1 "$RC" "a non-numeric self-test wait still ends: exit 1"
  assert_eq 30 "$_n" "a non-numeric self-test wait falls back to 30 s"
}

test_install_multiple_daemons_needs_daemon_id() {
  reset
  boardpy 'b["auto_runtime"] = False
b["runtime_profiles"] = [{"id": "rp-o", "command_name": "omega-multica-agent"}, {"id": "rp-c", "command_name": "claude-multica"}]
b["runtimes"] = [{"id": "rt-%s-%s" % (d, k), "profile_id": p, "daemon_id": "daemon-" + d, "status": "online", "name": "Claude (host-%s)" % d}
                 for d in ("1", "2") for k, p in (("omega", "rp-o"), ("claude", "rp-c"))]'
  inst
  assert_eq 1 "$RC" "two daemons: exit 1"
  assert_contains "$TMP/err" 'daemon-1' "stderr names daemon-1"
  assert_contains "$TMP/err" 'daemon-2' "stderr names daemon-2"
  assert_contains "$TMP/err" '--daemon-id' "stderr names --daemon-id"
  assert_contains "$TMP/err" 'host-1' "stderr names daemon-1's host"
  assert_contains "$TMP/err" 'host-2' "stderr names daemon-2's host"
  fast_sleep on
  inst --daemon-id nope
  fast_sleep off
  assert_eq 1 "$RC" "an unknown --daemon-id: exit 1"
  assert_contains "$TMP/err" 'daemon nope' "stderr names the bad daemon id"
  inst --daemon-id daemon-2 --agent gd --project "$PROJ"
  assert_eq 0 "$RC" "--daemon-id daemon-2: exit 0"
  assert_contains_line "runtime-id=rt-2-omega" "$(argcheck)" "the agent is bound to daemon-2's omega runtime"
}

# assert_contains_line LINE TEXT MSG — TEXT has a line equal to LINE.
assert_contains_line() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if printf '%s\n' "$2" | grep -Fxq -- "$1"; then _pass "$3"; else _fail "$3 (no line '$1')"; fi
}

test_install_agent_args() {
  reset
  inst --agent gd --project "$PROJ"
  assert_eq 0 "$RC" "install with an agent exits 0"
  _a="$(argcheck)"
  _rt="$(jfield "$TMP/cli/stub-state/board.json" '[r["id"] for r in d["runtimes"] if r["profile_id"] == [p["id"] for p in d["runtime_profiles"] if p["command_name"] == "omega-multica-agent"][0]][0]')"
  assert_contains_line "runtime-id=$_rt" "$_a" "agent create: the omega runtime"
  assert_contains_line "max=1" "$_a" "agent create: one concurrent task"
  assert_contains_line "name=gd" "$_a" "agent create: the name"
  assert_contains_line "instructions-match=True" "$_a" "agent create: the instructions file's text"
  assert_contains_line "env-stdin=True" "$_a" "agent create: --custom-env-stdin"
  assert_contains_line "stdin={\"OMEGA_PROJECT\": \"$PROJ\"}" "$_a" "agent create: OMEGA_PROJECT on stdin"
  inst --agent gd --project "$PROJ"
  assert_eq 0 "$RC" "rerun exits 0"
  assert_contains "$TMP/out" 'agent gd exists — skipped' "rerun skips the agent"
  assert_eq 1 "$(mcalls '"agent", "create"')" "still one agent create"
}

test_install_agent_archived_skipped() {
  reset
  inst --agent gd --project "$PROJ"
  boardpy 'b["agents"][0]["archived_at"] = "2026-10-04T05:19:43Z"'
  clear_calls
  inst --agent gd --project "$PROJ"
  assert_eq 0 "$RC" "an archived agent does not fail the install"
  assert_contains "$TMP/out" 'agent gd is archived — unarchive it in Multica or choose another --agent name' "R49 text"
  assert_eq 0 "$(mcalls '"agent", "create"')" "no agent create"
}

test_install_selftest_file_access_reported() {
  reset
  printf 'file-access\n' > "$LC/mode"
  inst
  assert_eq 1 "$RC" "file-access: exit 1"
  assert_contains "$TMP/err" '/Library/Developer/CommandLineTools/usr/bin/python3' "stderr has the interpreter path"
  assert_contains "$TMP/err" 'Files and Folders' "stderr has the System Settings pane"
  assert_not_contains "$TMP/err" 'stopped in' "no redundant trap line after the file-access message"
}

test_install_selftest_sees_the_project_root() {
  reset
  mkdir -p "$TMP/accproj/.studio"
  chmod 000 "$TMP/accproj/.studio"
  inst --agent gd --project "$TMP/accproj"
  chmod 755 "$TMP/accproj/.studio"
  assert_eq 1 "$RC" "a project whose run state cannot be read fails the install (roots empty)"
  assert_contains "$TMP/err" "$TMP/accproj/.studio" "stderr names the unreadable path"
  assert_contains "$TMP/err" 'Files and Folders' "stderr has the System Settings pane"
  assert_contains "$BASE/config" "^selftest_roots=$TMP/accproj\$" "the project is in the config as a self-test root"
  inst
  assert_eq 0 "$RC" "a re-run without --project keeps the root and now passes"
  assert_contains "$BASE/config" "^selftest_roots=$TMP/accproj\$" "the root is carried over"
  assert_contains "$BASE/selftest.json" "accproj" "the self-test checked it"
}

test_install_project_with_comma_or_newline_refused() {
  reset
  mkdir -p "$TMP/a,b"
  inst --agent gd --project "$TMP/a,b"
  assert_eq 2 "$RC" "a comma in --project: usage error"
  assert_contains "$TMP/err" 'must not contain a comma' "one-line error names the comma"
  assert_eq 0 "$(grep -c 'wrote' "$TMP/out")" "nothing written"
  nl="$(printf 'x\ny')"
  mkdir -p "$TMP/$nl"
  inst --agent gd --project "$TMP/$nl"
  assert_eq 2 "$RC" "a newline in --project: usage error"
  assert_contains "$TMP/err" 'must not contain a newline' "one-line error names the newline"
  rm -rf "$TMP/a,b" "$TMP/$nl"
}

test_install_drops_a_stale_selftest_root() {
  reset
  mkdir -p "$TMP/gone/.studio"
  inst --agent gd --project "$TMP/gone"
  assert_eq 0 "$RC" "install with a readable project"
  assert_contains "$BASE/config" "^selftest_roots=$TMP/gone\$" "the root is recorded"
  rm -rf "$TMP/gone"
  inst
  assert_eq 0 "$RC" "a re-run after the project vanished still installs"
  assert_contains "$TMP/out" 'dropping the self-test root' "the drop is noted"
  assert_contains "$BASE/config" '^selftest_roots=$' "the stale root is gone from the config"
}

test_install_selftest_timeout() {
  reset
  printf 'none\n' > "$LC/mode"
  inst_env_wait
  assert_eq 1 "$RC" "no self-test: exit 1"
  assert_contains "$TMP/err" 'bridge.log' "stderr names bridge.log"
}
inst_env_wait() { OMEGA_MULTICA_SELFTEST_WAIT=2; export OMEGA_MULTICA_SELFTEST_WAIT; inst; OMEGA_MULTICA_SELFTEST_WAIT=10; export OMEGA_MULTICA_SELFTEST_WAIT; }

test_install_python_too_old() {
  reset
  printf '%s\n' "$TOK" | sh "$INSTALL" --workspace-id ws-test --cli "$TMP/cli/multica" --python "$FAKE/oldpy" \
    >"$TMP/out" 2>"$TMP/err"; RC=$?
  assert_eq 1 "$RC" "an old python exits 1"
  assert_contains "$TMP/err" 'step 1' "stderr names step 1"
  assert_eq "" "$(find "$HOME" -type f 2>/dev/null)" "nothing written under HOME"
  assert_missing "$HOME/.claude-gamedev" "no ~/.claude-gamedev"
}

test_install_foreign_symlink_refused() {
  reset
  mkdir -p "$HOME/.local/bin"
  printf 'mine\n' > "$HOME/.local/bin/claude-multica"
  inst
  assert_eq 1 "$RC" "a regular file in the way: exit 1"
  assert_contains "$TMP/err" "$HOME/.local/bin/claude-multica" "stderr names the file"
  assert_eq "mine" "$(cat "$HOME/.local/bin/claude-multica")" "the file is untouched"
}

test_install_links_multica_bridge_and_it_runs() {
  reset
  inst
  assert_eq 0 "$RC" "install exits 0"
  assert_eq "$REPO_ROOT/integrations/multica/bin/multica-bridge" "$(readlink "$HOME/.local/bin/multica-bridge")" "multica-bridge link"
  assert_contains "$TMP/out" 'linked .*multica-bridge' "install says it linked multica-bridge"
  PATH="$HOME/.local/bin:$PATH" multica-bridge status > "$TMP/status" 2>&1
  assert_eq 0 "$?" "multica-bridge status runs from PATH"
  assert_contains "$TMP/status" '^cli: ' "status prints the CLI line"
}

test_install_foreign_multica_bridge_refused() {
  reset
  mkdir -p "$HOME/.local/bin"
  printf 'mine\n' > "$HOME/.local/bin/multica-bridge"
  inst
  assert_eq 1 "$RC" "a regular file named multica-bridge in the way: exit 1"
  assert_contains "$TMP/err" "$HOME/.local/bin/multica-bridge" "stderr names the file"
  assert_eq "mine" "$(cat "$HOME/.local/bin/multica-bridge")" "the file is untouched"
  reset
  mkdir -p "$HOME/.local/bin"
  ln -s /bin/echo "$HOME/.local/bin/multica-bridge"
  inst
  assert_eq 1 "$RC" "a foreign link: exit 1"
  assert_eq "/bin/echo" "$(readlink "$HOME/.local/bin/multica-bridge")" "the foreign link is untouched"
}

test_uninstall_multica_bridge_link_only_if_ours() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  uninst
  assert_missing "$HOME/.local/bin/multica-bridge" "our multica-bridge link is gone"
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  rm -f "$HOME/.local/bin/multica-bridge"
  ln -s /bin/echo "$HOME/.local/bin/multica-bridge"
  uninst
  assert_eq "/bin/echo" "$(readlink "$HOME/.local/bin/multica-bridge")" "a foreign multica-bridge link survives"
}

test_uninstall_profiles_found_by_basename_of_command() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  boardpy 'for p in b["runtime_profiles"]: p["command_name"] = "/home/x/.local/bin/" + p["command_name"]'
  clear_calls
  uninst --profiles
  assert_eq 0 "$RC" "uninstall --profiles exits 0"
  assert_eq 2 "$(mcalls '"runtime", "profile", "delete"')" "profiles stored with a path form are still deleted"
}

test_install_relative_cli_is_stored_absolute() {
  reset
  ( cd "$TMP/cli" && printf '%s\n' "$TOK" | sh "$INSTALL" --workspace-id ws-test --cli ./multica --python "$PY" >"$TMP/out" 2>"$TMP/err" )
  assert_eq 0 "$?" "a relative --cli works"
  assert_contains "$BASE/config" "^cli=$TMP/cli/multica\$" "config stores the absolute path"
}

test_install_usage() {
  reset
  printf '%s\n' "$TOK" | sh "$INSTALL" --workspace-id ws-test --cli "$TMP/cli/multica" --python "$PY" --agent gd >/dev/null 2>"$TMP/err"; RC=$?
  assert_eq 2 "$RC" "--agent without --project: exit 2"
  printf '%s\n' "$TOK" | sh "$INSTALL" --workspace-id ws-test --bogus >/dev/null 2>"$TMP/err"; RC=$?
  assert_eq 2 "$RC" "--bogus: exit 2"
  printf '%s\n' "$TOK" | sh "$INSTALL" --workspace-id >/dev/null 2>"$TMP/err"; RC=$?
  assert_eq 2 "$RC" "a flag with no value: exit 2"
  printf '%s\n' "$TOK" | sh "$INSTALL" --cli "$TMP/cli/multica" --python "$PY" >/dev/null 2>"$TMP/err"; RC=$?
  assert_eq 2 "$RC" "no workspace id: exit 2"
  assert_contains "$TMP/err" '--workspace-id' "stderr names --workspace-id"
  assert_missing "$BASE" "usage errors write nothing"
}

test_uninstall_removes() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  mkdir -p "$BASE/state"; printf 'x\n' > "$BASE/state/keep"
  clear_calls
  uninst
  assert_eq 0 "$RC" "uninstall exits 0"
  assert_missing "$LA" "the plist is gone"
  assert_missing "$HOME/.local/bin/claude-multica" "claude-multica link gone"
  assert_missing "$HOME/.local/bin/omega-multica-agent" "omega-multica-agent link gone"
  assert_missing "$BASE/lib" "lib is gone"
  assert_eq 1 "$(count "$SEC/calls" 'delete-generic-password')" "the Keychain item is deleted"
  assert_missing "$SEC/omega-multica-bridge-$(id -un)" "the stub Keychain item is gone"
  assert_file "$BASE/config" "config is kept"
  assert_file "$BASE/state/keep" "state/ is kept"
  assert_eq 1 "$(count "$LC/calls" '"bootout"')" "launchd agent booted out"
  assert_eq 0 "$(grep -c . "$CALLS")" "no board call at all"
}

test_uninstall_profiles_refused_while_bound() {
  reset
  inst --agent gd --project "$PROJ"; assert_eq 0 "$RC" "install exits 0"
  uninst --profiles
  assert_eq 1 "$RC" "bound agent: exit 1"
  assert_contains "$TMP/err" 'archive agent gd in Multica first' "stderr names the agent"
  assert_file "$LA" "plist still present"
  assert_symlink "$HOME/.local/bin/claude-multica" "link still present"
  assert_file "$BASE/lib/bin/multica-bridge" "lib still present"
  assert_file "$SEC/omega-multica-bridge-$(id -un)" "Keychain item still present"
}

test_uninstall_profiles_deletes() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  clear_calls
  uninst --profiles
  assert_eq 0 "$RC" "uninstall --profiles exits 0"
  assert_eq 2 "$(mcalls '"runtime", "profile", "delete"')" "two profile deletes"
  assert_eq 0 "$(grep -F '"runtime", "profile", "delete"' "$CALLS" | grep -c -- '--output')" "delete takes no --output"
  assert_eq 0 "$(jfield "$TMP/cli/stub-state/board.json" 'len(d["runtime_profiles"])')" "the profiles are gone"
}

test_uninstall_purge() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  uninst --purge
  assert_eq 0 "$RC" "uninstall --purge exits 0"
  assert_missing "$BASE" "~/.claude-gamedev/multica is gone"
}

test_uninstall_never_writes_issues_agents_properties() {
  reset
  inst --agent gd --project "$PROJ"
  boardpy 'b["agents"][0]["archived_at"] = "2026-10-04T05:19:43Z"'
  clear_calls
  uninst --profiles
  assert_eq 0 "$RC" "uninstall --profiles exits 0 once the agent is archived"
  assert_eq "" "$("$PY" -c 'import json, sys
ok = {("user", "profile", "get"), ("runtime", "profile", "list"), ("agent", "list"), ("runtime", "list"),
      ("runtime", "profile", "delete")}
for l in open(sys.argv[1]):
    a = json.loads(l)["argv"]
    if tuple(a[:3]) not in ok and tuple(a[:2]) not in ok:
        print(" ".join(a))' "$CALLS")" "every uninstall call is a read or a profile delete"
}

test_uninstall_usage() {
  uninst --bogus
  assert_eq 2 "$RC" "uninstall --bogus: exit 2"
}

test_install_server_unreachable_not_token() {
  reset
  fault "user profile get" 2 "Could not connect to the Multica server."
  inst --server-url https://down.test
  assert_eq 1 "$RC" "an unreachable server exits 1"
  assert_contains "$TMP/err" 'step 3' "stderr names step 3"
  assert_contains "$TMP/err" 'https://down.test' "stderr names the server"
  assert_contains "$TMP/err" '--server-url' "stderr names --server-url"
  assert_not_contains "$TMP/err" '--new-token' "an unreachable server does not blame the token"
}

test_install_profile_get_other_failure_names_code_and_redacts() {
  reset
  fault "user profile get" 7 "weird failure for $TOK"
  inst
  assert_eq 1 "$RC" "another failure exits 1"
  assert_contains "$TMP/err" 'step 3' "stderr names step 3"
  assert_contains "$TMP/err" 'exit 7' "stderr names the exit code"
  assert_contains "$TMP/err" 'weird failure' "stderr has the first CLI line"
  assert_not_contains "$TMP/err" "$TOK" "the token is redacted from stderr"
  assert_not_contains "$TMP/err" '--new-token' "an unknown failure does not blame the token"
}

test_install_property_create_failure_kinds() {
  reset
  boardpy 'b["properties"] = []'
  fault "property create" 2 "Could not connect"
  inst
  assert_eq 1 "$RC" "unreachable on property create: exit 1"
  assert_contains "$TMP/err" 'cannot reach' "stderr says the server is unreachable"
  assert_not_contains "$TMP/err" 'owner or admin' "unreachable is not an admin problem"
  fault "property create" 7 "kaboom"
  inst
  assert_eq 1 "$RC" "another property create failure: exit 1"
  assert_contains "$TMP/err" 'exit 7' "stderr names the exit code"
  assert_not_contains "$TMP/err" 'owner or admin' "an unknown failure is not an admin problem"
}

test_install_step_named_on_bare_failures() {
  reset
  printf '#!/bin/sh\nexit 1\n' > "$FAKE/ln"; chmod 755 "$FAKE/ln"
  inst
  rm -f "$FAKE/ln"
  assert_eq 1 "$RC" "a failing ln exits 1"
  assert_contains "$TMP/err" 'step 6' "stderr names step 6"
  reset
  printf '#!/bin/sh\nexit 1\n' > "$FAKE/cp"; chmod 755 "$FAKE/cp"
  inst
  rm -f "$FAKE/cp"
  assert_eq 1 "$RC" "a failing cp exits 1"
  assert_contains "$TMP/err" 'step 9' "stderr names step 9"
}

test_install_rerun_updates_lib() {
  reset
  inst; assert_eq 0 "$RC" "first install exits 0"
  _m="$(mtime "$BASE/lib/bin/multica-bridge")"
  clear_calls
  inst
  assert_eq "$_m" "$(mtime "$BASE/lib/bin/multica-bridge")" "a no-change re-run leaves lib alone"
  printf '# stale local edit\n' >> "$BASE/lib/bridge/state.py"
  clear_calls
  inst
  assert_eq 0 "$RC" "re-run over a stale lib exits 0"
  assert_not_contains "$BASE/lib/bridge/state.py" 'stale local edit' "the stale edit is gone: lib matches the source again"
  assert_eq 1 "$(count "$LC/calls" '"kickstart"')" "one kickstart"
  assert_missing "$BASE/lib.old" "no lib.old left behind"
  assert_missing "$BASE/lib.new" "no lib.new left behind"
}

test_install_lib_swap_failure_keeps_old_lib() {
  reset
  inst; assert_eq 0 "$RC" "first install exits 0"
  printf '# marker of the old copy\n' >> "$BASE/lib/bridge/state.py"
  printf '#!/bin/sh\nfor a; do prev2="$prev"; prev="$a"; done\ncase "$prev2" in */lib.new) exit 1 ;; esac\nexec /bin/mv "$@"\n' > "$FAKE/mv"
  chmod 755 "$FAKE/mv"
  inst
  rm -f "$FAKE/mv"
  assert_eq 1 "$RC" "a failing swap exits 1"
  assert_contains "$TMP/err" 'step 9' "stderr names step 9"
  assert_contains "$BASE/lib/bridge/state.py" 'marker of the old copy' "the old lib is restored"
  assert_file "$BASE/lib/bin/multica-bridge" "lib is whole"
}

test_install_plist_change_reloads() {
  reset
  inst; assert_eq 0 "$RC" "first install exits 0"
  printf '<!-- hand edit -->\n' >> "$LA"
  clear_calls
  inst
  assert_eq 0 "$RC" "re-run over a changed plist exits 0"
  assert_eq "bootout,bootstrap,kickstart," "$(verbs "$LC/calls")" "bootout, then bootstrap, then kickstart"
  assert_eq "0" "$(grep -c 'hand edit' "$LA")" "the plist is rewritten"
  assert_eq "0" "$(grep -c 'hand edit' "$LC/loaded")" "the loaded plist is the new one"
}

test_install_bootout_lingers_and_bootstrap_retries() {
  reset
  inst; assert_eq 0 "$RC" "first install exits 0"
  printf '<!-- hand edit -->\n' >> "$LA"
  clear_calls
  fast_sleep on
  STUB_LAUNCHCTL_LINGER=2; STUB_LAUNCHCTL_BOOTSTRAP_FAILS=1; export STUB_LAUNCHCTL_LINGER STUB_LAUNCHCTL_BOOTSTRAP_FAILS
  inst
  unset STUB_LAUNCHCTL_LINGER STUB_LAUNCHCTL_BOOTSTRAP_FAILS
  fast_sleep off
  assert_eq 0 "$RC" "a lingering job and one EIO still install"
  assert_file "$LC/loaded" "the agent ends up loaded"
  assert_eq 2 "$(count "$LC/calls" '"bootstrap"')" "bootstrap was retried once"
  reset
  inst
  printf '<!-- hand edit -->\n' >> "$LA"
  fast_sleep on
  STUB_LAUNCHCTL_BOOTSTRAP_FAILS=9; export STUB_LAUNCHCTL_BOOTSTRAP_FAILS
  inst
  unset STUB_LAUNCHCTL_BOOTSTRAP_FAILS
  fast_sleep off
  assert_eq 1 "$RC" "a bootstrap that never works exits 1"
  assert_contains "$TMP/err" 'step 9' "stderr names step 9"
}

test_install_stale_selftest_not_accepted() {
  reset
  inst; assert_eq 0 "$RC" "first install exits 0"
  printf 'none\n' > "$LC/mode"
  fast_sleep on
  inst_env_wait
  assert_eq 1 "$RC" "a re-run whose bridge writes nothing fails, it does not reuse the old self-test"
  assert_missing "$BASE/selftest.json" "the old self-test was removed before the restart"
  printf 'stale\n' > "$LC/mode"
  inst_env_wait
  fast_sleep off
  assert_eq 1 "$RC" "an old instance's late write is not accepted"
  assert_contains "$TMP/err" 'fresh self-test' "stderr says no fresh self-test"
}

test_install_roots_are_normalised() {
  reset
  mkdir -p "$TMP/studioproj/sub" "$TMP/studioproj/.studio"
  git -C "$TMP/studioproj" init -q
  inst --roots "$TMP/studioproj/sub"
  assert_eq 0 "$RC" "a roots directory inside a project: exit 0"
  assert_contains "$BASE/config" "^roots=$TMP/studioproj\$" "the root is the project root (studio-state root)"
  reset
  inst --roots "$TMP/no/such/dir"
  assert_eq 1 "$RC" "a missing roots directory: exit 1"
  assert_contains "$TMP/err" 'step 4' "stderr names step 4"
  assert_missing "$BASE/config" "no config written"
}

test_install_foreign_link_refused() {
  reset
  mkdir -p "$HOME/.local/bin"
  ln -s /bin/echo "$HOME/.local/bin/claude-multica"
  inst
  assert_eq 1 "$RC" "a foreign link in the way: exit 1"
  assert_contains "$TMP/err" 'step 6' "stderr names step 6"
  assert_eq "/bin/echo" "$(readlink "$HOME/.local/bin/claude-multica")" "the foreign link is untouched"
}

test_install_cli_environment_isolated() {
  reset
  MULTICA_TOKEN=mul_wrong; MULTICA_SERVER_URL=https://elsewhere.test; MULTICA_DAEMON_PORT=1; MULTICA_TASK_ID=t-9
  export MULTICA_TOKEN MULTICA_SERVER_URL MULTICA_DAEMON_PORT MULTICA_TASK_ID
  inst
  unset MULTICA_TOKEN MULTICA_SERVER_URL MULTICA_DAEMON_PORT MULTICA_TASK_ID
  assert_eq 0 "$RC" "install ignores the caller's MULTICA_* variables"
  assert_eq "ok" "$("$PY" -c 'import json, sys
n = 0
for l in open(sys.argv[1]):
    e = json.loads(l)["env"]
    if "MULTICA_DAEMON_PORT" in e or "MULTICA_TASK_ID" in e or e.get("PATH") != "/usr/bin:/bin" \
            or e.get("HOME") != sys.argv[2] or e.get("MULTICA_TOKEN") != sys.argv[3] \
            or e.get("MULTICA_SERVER_URL") != "https://api.multica.ai":
        n += 1
print("ok" if n == 0 else "bad %d" % n)' "$CALLS" "$BASE/cli-home" "$TOK")" "every CLI call had the clean environment (PATH, HOME, token, server)"
}

test_install_config_values_carried_over() {
  reset
  inst --server-url https://x.test --poll-seconds 30
  assert_eq 0 "$RC" "first install exits 0"
  inst
  assert_eq 0 "$RC" "re-run with no flags exits 0"
  assert_contains "$BASE/config" '^server_url=https://x.test$' "server_url is kept"
  assert_contains "$BASE/config" '^poll_seconds=30$' "poll_seconds is kept"
}

test_install_project_checked_before_side_effects() {
  reset
  inst --agent gd --project "$TMP/not/a/dir"
  assert_eq 2 "$RC" "a bad --project: exit 2"
  assert_contains "$TMP/err" '--project' "stderr names --project"
  assert_missing "$BASE" "nothing was written"
  assert_missing "$CALLS" "no board call"
}

test_uninstall_foreign_link_survives() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  rm -f "$HOME/.local/bin/claude-multica"
  ln -s /bin/echo "$HOME/.local/bin/claude-multica"
  uninst
  assert_eq 0 "$RC" "uninstall exits 0"
  assert_eq "/bin/echo" "$(readlink "$HOME/.local/bin/claude-multica")" "a link that is not ours survives"
  assert_missing "$HOME/.local/bin/omega-multica-agent" "our own link is gone"
}

test_uninstall_keychain_failure_reported() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  : > "$SEC/locked"
  uninst
  assert_eq 1 "$RC" "a Keychain delete failure other than not-found: exit 1"
  assert_contains "$TMP/err" 'Keychain item' "stderr names the Keychain item"
  rm -f "$SEC/locked"
  uninst
  assert_eq 0 "$RC" "a second uninstall succeeds"
  uninst
  assert_eq 0 "$RC" "an absent Keychain item is not an error"
}

test_uninstall_profiles_missing_vs_locked_token() {
  reset
  inst; assert_eq 0 "$RC" "install exits 0"
  uninst
  uninst --profiles
  assert_eq 1 "$RC" "no token stored: exit 1"
  assert_contains "$TMP/err" 'no token is stored' "stderr says the token is missing"
  assert_not_contains "$TMP/err" 'locked' "a missing token is not blamed on a locked Keychain"
  : > "$SEC/locked"
  uninst --profiles
  assert_contains "$TMP/err" 'locked' "a locked Keychain says so"
}

run_tests test_install_project_with_comma_or_newline_refused test_install_drops_a_stale_selftest_root \
  test_install_links_multica_bridge_and_it_runs test_install_foreign_multica_bridge_refused \
  test_uninstall_multica_bridge_link_only_if_ours test_uninstall_profiles_found_by_basename_of_command \
  test_install_relative_cli_is_stored_absolute test_install_fresh test_install_token_never_in_argv_files_or_output \
  test_install_rerun_changes_nothing test_install_token_prompt_once test_install_new_token \
  test_install_token_rejected test_install_property_archived_refused test_install_property_wrong_type_refused \
  test_install_not_admin_refused test_install_runtime_wait_times_out \
  test_install_multiple_daemons_needs_daemon_id test_install_agent_args test_install_agent_archived_skipped \
  test_install_selftest_file_access_reported test_install_selftest_sees_the_project_root test_install_selftest_timeout test_install_python_too_old \
  test_install_foreign_symlink_refused test_install_usage test_uninstall_removes \
  test_uninstall_profiles_refused_while_bound test_uninstall_profiles_deletes test_uninstall_purge \
  test_uninstall_never_writes_issues_agents_properties test_uninstall_usage \
  test_install_wait_limit_hooks_must_be_numeric test_install_server_unreachable_not_token \
  test_install_profile_get_other_failure_names_code_and_redacts test_install_property_create_failure_kinds \
  test_install_step_named_on_bare_failures test_install_rerun_updates_lib test_install_lib_swap_failure_keeps_old_lib \
  test_install_plist_change_reloads test_install_bootout_lingers_and_bootstrap_retries \
  test_install_stale_selftest_not_accepted test_install_roots_are_normalised test_install_foreign_link_refused \
  test_install_cli_environment_isolated test_install_config_values_carried_over \
  test_install_project_checked_before_side_effects test_uninstall_foreign_link_survives \
  test_uninstall_keychain_failure_reported test_uninstall_profiles_missing_vs_locked_token
