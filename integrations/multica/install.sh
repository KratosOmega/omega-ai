#!/bin/sh
# install.sh — set up the omega-ai Multica integration on this Mac (#28).
set -eu
unset CDPATH
HERE="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$HERE/../.." && pwd -P)"
BASE="$HOME/.claude-gamedev/multica"
CLI_HOME="$BASE/cli-home"
CFG="$BASE/config"
LABEL=ai.omega.multica-bridge
SERVICE=omega-multica-bridge
ACCOUNT="$(id -un)"
SECURITY="${OMEGA_MULTICA_SECURITY:-/usr/bin/security}"
LAUNCHCTL="${OMEGA_MULTICA_LAUNCHCTL:-/bin/launchctl}"
DESKTOP_CLI=/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica
LAUNCHD_PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"   # R45
# D1a (P1) swap point: the profiles' command names live in command-names.sh (shared with uninstall.sh).
. "$HERE/command-names.sh"
# D1e (P5) swap point: the Multica.app ~/Documents step text.
P5_TEXT='One-time step: System Settings → Privacy & Security → Files and Folders → Multica → turn on "Documents Folder" (needed for projects under ~/Documents).'
TOKEN=
TMPD=
WORKSPACE_ID=
SERVER_URL=
ROOTS=
SELFTEST_ROOTS=
CLI=
PY=
DAEMON_ID=
AGENT=
PROJECT_ARG=
POLL_SECONDS=
NEW_TOKEN=0

STEP="step 0 (arguments)"
DIED=
die() { DIED=1; printf 'install: %s\n' "$*" >&2; exit 1; }
# Every failing exit names its step: die does, and so does this trap for a bare set -e exit.
on_exit() {
  oe_rc=$?
  [ -z "$TMPD" ] || rm -rf "$TMPD"
  if [ "$oe_rc" -ne 0 ] && [ "$oe_rc" -ne 2 ] && [ -z "$DIED" ]; then
    printf 'install: stopped in %s (exit %s)\n' "$STEP" "$oe_rc" >&2
  fi
}
trap on_exit EXIT

usage() {
  cat <<'EOF'
usage: install.sh --workspace-id <id> [--server-url <url>] [--roots <dir[,dir…]>] [--cli <path>]
                  [--python <path>] [--daemon-id <id>] [--agent <name> --project <dir>]
                  [--poll-seconds <5-300>] [--new-token] [--help]
Values not given come from ~/.claude-gamedev/multica/config, then the defaults.
EOF
}
usage_err() { DIED=1; printf 'install: %s\n' "$*" >&2; usage >&2; exit 2; }

# The only way install.sh runs the Multica CLI: a subshell with no inherited
# MULTICA_* variables, the operator's token in the environment (never argv),
# an empty HOME so no local profile is read, and JSON output.
mcli_plain() {
  (
    for v in $(env | sed -n 's/^\(MULTICA_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
    MULTICA_TOKEN="$TOKEN"; MULTICA_SERVER_URL="$SERVER_URL"; MULTICA_WORKSPACE_ID="$WORKSPACE_ID"
    HOME="$CLI_HOME"; PATH=/usr/bin:/bin
    export MULTICA_TOKEN MULTICA_SERVER_URL MULTICA_WORKSPACE_ID HOME PATH
    exec "$CLI" "$@"
  )
}
mcli() { mcli_plain "$@" --output json; }
# redact — stdin with the token (if known) replaced by ***.
redact() {
  if [ -n "$TOKEN" ]; then
    rd_pat="$(printf '%s' "$TOKEN" | sed 's/[][\.*^$/]/\\&/g')"
    sed "s/$rd_pat/***/g"
  else
    cat
  fi
}
# errline FILE — the first line of a CLI's stderr, redacted and cut short.
errline() { sed -n 1p "$1" 2>/dev/null | redact | cut -c1-200; }
# cli_fail STEP RC ERRFILE WHAT — P7h exit codes: 3 token, 2 unreachable, else the code and first stderr line.
cli_fail() {
  case "$2" in
    3) die "$1: Multica rejected the token ($4) — run install.sh --new-token" ;;
    2) die "$1: cannot reach the Multica server $SERVER_URL ($4) — check the network and --server-url" ;;
    *) cf_l="$(errline "$3")"; die "$1: $4 failed (exit $2)${cf_l:+: $cf_l}" ;;
  esac
}
ij() { PYTHONPATH="$HERE" PYTHONDONTWRITEBYTECODE=1 "$PY" -m bridge.installjson "$@"; }

read_token() {   # prints nothing; sets TOKEN or dies
  rt_rc=0
  TOKEN="$("$SECURITY" find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null)" || rt_rc=$?
  case "$rt_rc" in
    0) ;;
    44) die "no token is stored in the Keychain (item $SERVICE / $ACCOUNT) — run install.sh --new-token" ;;
    *) die "cannot read the token from the Keychain (item $SERVICE / $ACCOUNT, exit $rt_rc) — is the Keychain locked?" ;;
  esac
  [ -n "$TOKEN" ] || die "the Keychain item $SERVICE / $ACCOUNT is empty — run install.sh --new-token"
}

ensure_token() {
  if [ "$NEW_TOKEN" = 1 ] || ! "$SECURITY" find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
    echo "Paste your Multica API token at the Keychain prompt (it is not shown):"
    "$SECURITY" add-generic-password -s "$SERVICE" -a "$ACCOUNT" -U -w ||
      die "step 2 (token): the Keychain did not store the token"
  fi
  read_token
}

cfg() {   # cfg KEY — the existing config's value, or nothing
  if [ -f "$CFG" ]; then sed -n "s/^$1=//p" "$CFG" | sed -n 1p; fi
  return 0
}

wait_runtimes() {   # sets DAEMON and RT_OMEGA or dies
  limit="${OMEGA_MULTICA_RUNTIME_WAIT:-60}"; waited=0
  case "$limit" in ''|*[!0-9]*) limit=60 ;; esac
  while :; do
    rc=0; mcli runtime list > "$TMPD/rt.json" 2>"$TMPD/cli.err" || rc=$?
    [ "$rc" = 0 ] || cli_fail "step 7 (runtimes)" "$rc" "$TMPD/cli.err" "runtime list"
    ids="$(ij daemons "$P_OMEGA" "$P_CLAUDE" < "$TMPD/rt.json")" || die "step 7 (runtimes): cannot read the runtime list"
    if [ -n "$DAEMON_ID" ]; then
      ids="$(printf '%s\n' "$ids" | grep -Fx -- "$DAEMON_ID" || true)"
    fi
    n="$(printf '%s' "$ids" | grep -c . || true)"
    if [ "$n" = 1 ]; then
      DAEMON="$ids"
      RT_OMEGA="$(ij runtime-for "$P_OMEGA" "$DAEMON" < "$TMPD/rt.json" | sed -n 1p)"
      return 0
    fi
    if [ "$n" -gt 1 ]; then
      named="$(ij daemon-names "$P_OMEGA" "$P_CLAUDE" < "$TMPD/rt.json" | tr '\n' ';' | sed 's/;$//; s/;/; /g')" ||
        named="$(printf '%s' "$ids" | tr '\n' ' ')"
      die "step 7 (runtimes): several daemons serve both profiles: $named — re-run with --daemon-id <one of the ids>"
    fi
    if [ "$waited" -ge "$limit" ]; then
      [ -z "$DAEMON_ID" ] || die "step 7 (runtimes): no online runtime for both profiles on daemon $DAEMON_ID after $limit s — check --daemon-id"
      die "step 7 (runtimes): no online runtime for \"omega game-dev\" and \"claude (multica)\" after $limit s — restart the Multica daemon (quit and reopen Multica.app, or run: multica daemon restart), then re-run install.sh"
    fi
    sleep 2; waited=$((waited + 2))
  done
}

wait_selftest() {
  limit="${OMEGA_MULTICA_SELFTEST_WAIT:-30}"; waited=0
  case "$limit" in ''|*[!0-9]*) limit=30 ;; esac
  # Only a self-test checked at or after START counts: the old bridge instance may write one
  # between the rm and its kill by kickstart -k.
  while [ "$(ij selftest-fresh "$BASE/selftest.json" "$START" 2>/dev/null || true)" != fresh ]; do
    [ "$waited" -ge "$limit" ] && die "step 10 (self-test): the bridge wrote no fresh self-test in $limit s — see $BASE/bridge.log and $BASE/launchd.err"
    sleep 1; waited=$((waited + 1))
  done
  res="$(ij selftest-kind "$BASE/selftest.json")" || die "step 10 (self-test): unreadable $BASE/selftest.json"
  [ "$res" = ok ] && { echo "install: the bridge is running and its self-test passed"; return 0; }
  kind="$(printf '%s' "$res" | cut -f1)"; err="$(printf '%s' "$res" | cut -f2)"; interp="$(printf '%s' "$res" | cut -f3)"
  if [ "$kind" = file-access ]; then
    DIED=1    # this branch has said everything: no "stopped in step 10" line from the trap
    printf 'install: the bridge cannot read your files: %s\n' "$err" >&2
    printf 'Grant access to this program: %s\n' "$interp" >&2
    printf 'System Settings → Privacy & Security → Files and Folders (or Full Disk Access) → add it, then run: launchctl kickstart -k gui/%s/%s\n' "$(id -u)" "$LABEL" >&2
    exit 1
  fi
  die "step 10 (self-test): $kind: $err"
}

# ensure_profile DISPLAY COMMAND — sets ENSURED_ID: the first profile with that command name, else a new one.
ensure_profile() {
  ids="$(ij profile-for-command "$2" < "$TMPD/profiles.json")" || die "step 7 (runtimes): cannot read the runtime profile list"
  ENSURED_ID="$(printf '%s\n' "$ids" | sed -n 1p)"
  if [ -z "$ENSURED_ID" ]; then
    rc=0
    mcli runtime profile create --display-name "$1" --command-name "$2" --protocol-family claude \
      > "$TMPD/created.json" 2>"$TMPD/cli.err" || rc=$?
    [ "$rc" = 0 ] || cli_fail "step 7 (runtimes)" "$rc" "$TMPD/cli.err" "creating the runtime profile \"$1\""
    ENSURED_ID="$(ij get id < "$TMPD/created.json")" || die "step 7 (runtimes): the created profile \"$1\" has no id"
    echo "install: created runtime profile \"$1\""
  fi
}

# link_wrapper NAME — R48: create or replace the link only when absent or already ours.
link_wrapper() {
  lw_target="$HERE/bin/$1"; lw_link="$HOME/.local/bin/$1"
  if [ -L "$lw_link" ]; then
    lw_dest="$(readlink "$lw_link")"
    case "$lw_dest" in
      */integrations/multica/bin/*) ;;
      *) die "step 6 (wrappers): $lw_link is a link to $lw_dest, not ours — move it aside and re-run" ;;
    esac
    [ "$lw_dest" = "$lw_target" ] && return 0
  elif [ -e "$lw_link" ]; then
    die "step 6 (wrappers): $lw_link exists and is not a link into integrations/multica/bin — move it aside and re-run"
  fi
  mkdir -p "$HOME/.local/bin" || die "step 6 (wrappers): cannot create $HOME/.local/bin"
  ln -sfn "$lw_target" "$lw_link" || die "step 6 (wrappers): cannot link $lw_link"
  echo "install: linked $lw_link"
}

# ---- Step 0: arguments (R10) -------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --new-token) NEW_TOKEN=1; shift; continue ;;
    --workspace-id|--server-url|--roots|--cli|--python|--daemon-id|--agent|--project|--poll-seconds)
      [ $# -ge 2 ] || usage_err "$1 needs a value"
      case "$1" in
        --workspace-id) WORKSPACE_ID="$2" ;;
        --server-url) SERVER_URL="$2" ;;
        --roots) ROOTS="$2" ;;
        --cli) CLI="$2" ;;
        --python) PY="$2" ;;
        --daemon-id) DAEMON_ID="$2" ;;
        --agent) AGENT="$2" ;;
        --project) PROJECT_ARG="$2" ;;
        --poll-seconds) POLL_SECONDS="$2" ;;
      esac
      shift 2 ;;
    *) usage_err "unknown argument: $1" ;;
  esac
done
if [ -n "$AGENT" ] && [ -z "$PROJECT_ARG" ]; then usage_err "--agent needs --project"; fi
if [ -z "$AGENT" ] && [ -n "$PROJECT_ARG" ]; then usage_err "--project needs --agent"; fi
if [ -n "$PROJECT_ARG" ] && [ ! -d "$PROJECT_ARG" ]; then usage_err "--project is not a directory: $PROJECT_ARG"; fi
if [ -n "$PROJECT_ARG" ]; then      # the config line is comma-separated and one line per key
  case "$PROJECT_ARG" in
    *,*) usage_err "--project must not contain a comma: $PROJECT_ARG" ;;
  esac
  case "$PROJECT_ARG" in
    *"
"*) usage_err "--project must not contain a newline" ;;
  esac
fi
[ -n "$WORKSPACE_ID" ] || WORKSPACE_ID="$(cfg workspace_id)"
[ -n "$SERVER_URL" ] || SERVER_URL="$(cfg server_url)"
[ -n "$SERVER_URL" ] || SERVER_URL=https://api.multica.ai
[ -n "$POLL_SECONDS" ] || POLL_SECONDS="$(cfg poll_seconds)"
[ -n "$POLL_SECONDS" ] || POLL_SECONDS=15
[ -n "$ROOTS" ] || ROOTS="$(cfg roots)"
[ -n "$WORKSPACE_ID" ] || usage_err "no workspace id — pass --workspace-id <id>"
case "$POLL_SECONDS" in
  ''|*[!0-9]*) usage_err "--poll-seconds must be a number from 5 to 300" ;;
esac
if [ "$POLL_SECONDS" -lt 5 ] || [ "$POLL_SECONDS" -gt 300 ]; then usage_err "--poll-seconds must be from 5 to 300"; fi

TMPD="$(mktemp -d)" || die "step 0 (arguments): cannot create a temporary directory"
STEP="step 1 (prerequisites)"

# ---- Step 1: prerequisites ---------------------------------------------------
[ -n "$PY" ] || PY=/usr/bin/python3        # R4
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1 ||
  die "step 1 (python): $PY is not Python 3.9 or newer"
PY_REAL="$("$PY" -c 'import os, sys; print(os.path.realpath(sys.executable))')"
[ -n "$CLI" ] || CLI="$(cfg cli)"
if [ -z "$CLI" ]; then
  if [ -x "$DESKTOP_CLI" ]; then CLI="$DESKTOP_CLI"; else CLI="$(command -v multica || true)"; fi
fi
[ -n "$CLI" ] && [ -x "$CLI" ] ||
  die "step 1 (multica): no Multica CLI found — install Multica.app (expected $DESKTOP_CLI) or pass --cli <path>"
case "$CLI" in      # the launchd service runs from /: a relative path would not be found there
  /*) ;;
  *) CLI="$(cd "$(dirname "$CLI")" && pwd -P)/$(basename "$CLI")" ;;
esac
command -v claude-gd >/dev/null 2>&1 || die "step 1 (claude-gd): not on PATH — install omega-ai first"

mkdir -p "$BASE" "$CLI_HOME" || die "step 1 (prerequisites): cannot create $BASE"
chmod 700 "$BASE" "$CLI_HOME" || die "step 1 (prerequisites): cannot set permissions on $BASE"

# ---- Steps 2-3: token --------------------------------------------------------
STEP="step 2 (token)"
ensure_token
STEP="step 3 (token check)"
rc=0; mcli user profile get > "$TMPD/profile.json" 2>"$TMPD/cli.err" || rc=$?
[ "$rc" = 0 ] || cli_fail "step 3 (token check)" "$rc" "$TMPD/cli.err" "user profile get"
OPERATOR="$(ij get id < "$TMPD/profile.json")" || die "step 3 (token check): Multica's answer has no member id"

# ---- Step 4: config ----------------------------------------------------------
STEP="step 4 (config)"
NEWROOTS=
while IFS= read -r item; do
  [ -n "$item" ] || continue
  norm="$(cd "$item" && "$REPO/studios/game-dev/bin/studio-state" root)" ||
    die "step 4 (config): cannot resolve the project root $item"
  if [ -z "$NEWROOTS" ]; then NEWROOTS="$norm"; else NEWROOTS="$NEWROOTS,$norm"; fi
done <<EOF
$(printf '%s\n' "$ROOTS" | tr ',' '\n')
EOF
# The self-test also reads the --project root (carried over when not given): a macOS file-access block
# on the agent's project must fail the install here, not at night (I1).
if [ -n "$PROJECT_ARG" ]; then
  SELFTEST_ROOTS="$(cd "$PROJECT_ARG" && pwd -P)" || die "step 4 (config): cannot resolve --project $PROJECT_ARG"
else
  SELFTEST_ROOTS=
  _st_old="$(cfg selftest_roots)"
  while IFS= read -r item; do       # carried over only while it is still a directory
    [ -n "$item" ] || continue
    if [ -d "$item" ]; then
      if [ -z "$SELFTEST_ROOTS" ]; then SELFTEST_ROOTS="$item"; else SELFTEST_ROOTS="$SELFTEST_ROOTS,$item"; fi
    else
      echo "install: note: dropping the self-test root $item (no longer a directory)"
    fi
  done <<EOF
$(printf '%s\n' "$_st_old" | tr ',' '\n')
EOF
fi
{
  printf 'server_url=%s\n' "$SERVER_URL"
  printf 'workspace_id=%s\n' "$WORKSPACE_ID"
  printf 'operator_member_id=%s\n' "$OPERATOR"
  printf 'roots=%s\n' "$NEWROOTS"
  printf 'poll_seconds=%s\n' "$POLL_SECONDS"
  printf 'cli=%s\n' "$CLI"
  printf 'studio_overnight=%s\n' "$REPO/studios/game-dev/bin/studio-overnight"
  printf 'selftest_roots=%s\n' "$SELFTEST_ROOTS"
} > "$TMPD/config.new"
if ! cmp -s "$TMPD/config.new" "$CFG" 2>/dev/null; then       # R34: write only when the text differs
  cfg_tmp="$(mktemp "$BASE/.config.XXXXXX")" || die "step 4 (config): cannot create a file under $BASE"
  cat "$TMPD/config.new" > "$cfg_tmp" || die "step 4 (config): cannot write $cfg_tmp"
  chmod 600 "$cfg_tmp" || die "step 4 (config): cannot set permissions on $cfg_tmp"
  mv "$cfg_tmp" "$CFG" || die "step 4 (config): cannot write $CFG"
  echo "install: wrote $CFG"
fi

# ---- Step 5: properties ------------------------------------------------------
STEP="step 5 (properties)"
rc=0; mcli property list --include-archived > "$TMPD/props.json" 2>"$TMPD/cli.err" || rc=$?
[ "$rc" = 0 ] || cli_fail "step 5 (properties)" "$rc" "$TMPD/cli.err" "property list"
for pname in omega_run omega_story; do
  pstate="$(ij property-state "$pname" < "$TMPD/props.json")" || die "step 5 (properties): cannot read the property list"
  case "$pstate" in
    ok) ;;
    archived) die "step 5 (properties): $pname is archived — unarchive it in Multica" ;;
    wrong-type:*) die "step 5 (properties): $pname exists with type ${pstate#wrong-type:}, not text" ;;
    absent)
      rc=0; mcli property create --name "$pname" --type text >/dev/null 2>"$TMPD/cli.err" || rc=$?
      if [ "$rc" != 0 ]; then
        # Only a permission failure says owner or admin; anything else names its exit code.
        if [ "$rc" != 2 ] && [ "$rc" != 3 ] && grep -qi 'forbidden\|permission\|not allowed\|owner\|admin' "$TMPD/cli.err"; then
          die "step 5 (properties): could not create $pname — you must be a workspace owner or admin"
        fi
        cli_fail "step 5 (properties)" "$rc" "$TMPD/cli.err" "creating $pname"
      fi
      echo "install: created property $pname" ;;
    *) die "step 5 (properties): unexpected state '$pstate' for $pname" ;;
  esac
done

# ---- Step 6: wrappers --------------------------------------------------------
STEP="step 6 (wrappers)"
link_wrapper claude-multica
link_wrapper omega-multica-agent
link_wrapper multica-bridge          # `multica-bridge status` is the first troubleshooting step (I2)

# ---- Step 7: runtimes --------------------------------------------------------
STEP="step 7 (runtimes)"
rc=0; mcli runtime profile list > "$TMPD/profiles.json" 2>"$TMPD/cli.err" || rc=$?
[ "$rc" = 0 ] || cli_fail "step 7 (runtimes)" "$rc" "$TMPD/cli.err" "runtime profile list"
ensure_profile "omega game-dev" "$CMD_OMEGA"; P_OMEGA="$ENSURED_ID"
ensure_profile "claude (multica)" "$CMD_CLAUDE"; P_CLAUDE="$ENSURED_ID"
wait_runtimes

# ---- Step 8: agent -----------------------------------------------------------
STEP="step 8 (agent)"
if [ -n "$AGENT" ]; then
  PROJECT="$(cd "$PROJECT_ARG" && pwd -P)" || die "step 8 (agent): cannot resolve --project $PROJECT_ARG"
  rc=0; mcli agent list --include-archived > "$TMPD/agents.json" 2>"$TMPD/cli.err" || rc=$?
  [ "$rc" = 0 ] || cli_fail "step 8 (agent)" "$rc" "$TMPD/cli.err" "agent list"
  astate="$(ij agent-state "$AGENT" < "$TMPD/agents.json")" || die "step 8 (agent): cannot read the agent list"
  case "$astate" in
    active) echo "agent $AGENT exists — skipped" ;;
    archived) echo "agent $AGENT is archived — unarchive it in Multica or choose another --agent name" ;;
    absent)
      instructions="$(cat "$HERE/agent-instructions.md")" || die "step 8 (agent): cannot read $HERE/agent-instructions.md"
      rc=0
      ij json-env OMEGA_PROJECT "$PROJECT" | mcli agent create --name "$AGENT" --runtime-id "$RT_OMEGA" \
        --max-concurrent-tasks 1 --instructions "$instructions" --custom-env-stdin >/dev/null 2>"$TMPD/cli.err" || rc=$?
      [ "$rc" = 0 ] || cli_fail "step 8 (agent)" "$rc" "$TMPD/cli.err" "creating agent $AGENT"
      echo "install: created agent $AGENT" ;;
    *) die "step 8 (agent): unexpected state '$astate' for $AGENT" ;;
  esac
fi

# ---- Step 9: service ---------------------------------------------------------
STEP="step 9 (service)"
rm -rf "$BASE/lib.new" || die "step 9 (service): cannot clear $BASE/lib.new"
mkdir -p "$BASE/lib.new/bin" "$BASE/lib.new/bridge" || die "step 9 (service): cannot create $BASE/lib.new"
cp "$HERE/bin/multica-bridge" "$BASE/lib.new/bin/multica-bridge" || die "step 9 (service): cannot copy the bridge entry point"
for src in "$HERE"/bridge/*.py; do cp "$src" "$BASE/lib.new/bridge/" || die "step 9 (service): cannot copy $src"; done
# __pycache__ is excluded: the running bridge writes bytecode into lib/.
if [ ! -d "$BASE/lib" ] || ! diff -rq -x __pycache__ "$BASE/lib" "$BASE/lib.new" >/dev/null 2>&1; then
  # Rename the old copy aside, then move the new one in; put the old one back if that fails.
  rm -rf "$BASE/lib.old" || die "step 9 (service): cannot clear $BASE/lib.old"
  if [ -d "$BASE/lib" ]; then mv "$BASE/lib" "$BASE/lib.old" || die "step 9 (service): cannot move $BASE/lib aside"; fi
  if ! mv "$BASE/lib.new" "$BASE/lib"; then
    if [ -d "$BASE/lib.old" ]; then mv "$BASE/lib.old" "$BASE/lib" || true; fi
    die "step 9 (service): cannot install the new bridge copy (the old one was kept)"
  fi
  rm -rf "$BASE/lib.old"
  echo "install: copied the bridge to $BASE/lib"
else
  rm -rf "$BASE/lib.new"
fi
GUI="gui/$(id -u)"
LA="$HOME/Library/LaunchAgents/$LABEL.plist"
ij plist "$HERE/launchd/$LABEL.plist.in" "$PY_REAL" "$BASE/lib" "$BASE" "$HOME" "$LAUNCHD_PATH" > "$TMPD/plist" ||
  die "step 9 (service): cannot build the launchd plist"
plutil -lint -s "$TMPD/plist" >/dev/null 2>&1 || die "step 9 (service): the launchd plist does not lint"
if ! cmp -s "$TMPD/plist" "$LA" 2>/dev/null; then
  mkdir -p "$HOME/Library/LaunchAgents" || die "step 9 (service): cannot create $HOME/Library/LaunchAgents"
  cp "$TMPD/plist" "$LA" || die "step 9 (service): cannot write $LA"
  "$LAUNCHCTL" bootout "$GUI/$LABEL" 2>/dev/null || true
  # bootout can return before the job is gone: wait (bounded) for it, or bootstrap fails with EIO.
  bo_w=0
  while "$LAUNCHCTL" print "$GUI/$LABEL" >/dev/null 2>&1 && [ "$bo_w" -lt 5 ]; do sleep 1; bo_w=$((bo_w + 1)); done
  echo "install: wrote $LA"
fi
if ! "$LAUNCHCTL" print "$GUI/$LABEL" >/dev/null 2>&1; then
  bs_n=1
  until "$LAUNCHCTL" bootstrap "$GUI" "$LA"; do
    [ "$bs_n" -lt 3 ] || die "step 9 (service): launchctl bootstrap failed"
    bs_n=$((bs_n + 1)); sleep 2
  done
fi
START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -f "$BASE/selftest.json" || die "step 9 (service): cannot remove the old self-test"
"$LAUNCHCTL" kickstart -k "$GUI/$LABEL" || die "step 9 (service): launchctl kickstart failed"   # R34

# ---- Step 10: self-test ------------------------------------------------------
STEP="step 10 (self-test)"
printf '%s\n' "$P5_TEXT"
wait_selftest
