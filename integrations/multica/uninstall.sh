#!/bin/sh
# uninstall.sh — remove the omega-ai Multica integration from this Mac (#28).
# Never deletes or edits Multica issues, agents or properties.
set -eu
unset CDPATH
HERE="$(cd "$(dirname "$0")" && pwd -P)"
BASE="$HOME/.claude-gamedev/multica"
CLI_HOME="$BASE/cli-home"
CFG="$BASE/config"
LABEL=ai.omega.multica-bridge
SERVICE=omega-multica-bridge
ACCOUNT="$(id -un)"
SECURITY="${OMEGA_MULTICA_SECURITY:-/usr/bin/security}"
LAUNCHCTL="${OMEGA_MULTICA_LAUNCHCTL:-/bin/launchctl}"
. "$HERE/command-names.sh"          # the same names as install.sh (D1a swap point)
TOKEN=
TMPD=
CLI=
SERVER_URL=
WORKSPACE_ID=
PY=/usr/bin/python3
PROFILES=0
PURGE=0
FAILED=0

die() { printf 'uninstall: %s\n' "$*" >&2; exit 1; }

usage() { printf 'usage: uninstall.sh [--profiles] [--purge] [--help]\n'; }

# The only way uninstall.sh runs the Multica CLI (see install.sh): no inherited
# MULTICA_* variables, the token in the environment, an empty HOME, no --output here.
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
ij() { PYTHONPATH="$HERE" PYTHONDONTWRITEBYTECODE=1 "$PY" -m bridge.installjson "$@"; }

read_token() {
  rt_rc=0
  TOKEN="$("$SECURITY" find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null)" || rt_rc=$?
  case "$rt_rc" in
    0) ;;
    44) die "no token is stored in the Keychain (item $SERVICE / $ACCOUNT) — run install.sh --new-token first, or delete the runtime profiles in Multica" ;;
    *) die "cannot read the token from the Keychain (item $SERVICE / $ACCOUNT, exit $rt_rc) — is the Keychain locked?" ;;
  esac
  [ -n "$TOKEN" ] || die "the Keychain item $SERVICE / $ACCOUNT is empty"
}

cfg() {
  if [ -f "$CFG" ]; then sed -n "s/^$1=//p" "$CFG" | sed -n 1p; fi
  return 0
}

for arg in "$@"; do
  case "$arg" in
    --profiles) PROFILES=1 ;;
    --purge) PURGE=1 ;;
    --help) usage; exit 0 ;;
    *) printf 'uninstall: unknown argument: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

PIDS=
if [ "$PROFILES" = 1 ]; then
  # Nothing is removed until every check here has passed.
  read_token
  CLI="$(cfg cli)"; SERVER_URL="$(cfg server_url)"; WORKSPACE_ID="$(cfg workspace_id)"
  [ -n "$CLI" ] && [ -n "$WORKSPACE_ID" ] || die "no usable $CFG — cannot reach Multica to delete the runtime profiles"
  [ -n "$SERVER_URL" ] || SERVER_URL=https://api.multica.ai
  mkdir -p "$CLI_HOME"
  mcli runtime profile list > "$TMPD/profiles.json" 2>/dev/null || die "runtime profile list failed"
  PIDS="$(ij profile-for-command "$CMD_OMEGA" < "$TMPD/profiles.json"; ij profile-for-command "$CMD_CLAUDE" < "$TMPD/profiles.json")"
  PIDS="$(printf '%s\n' "$PIDS" | grep . || true)"
  mcli agent list > "$TMPD/agents.json" 2>/dev/null || die "agent list failed"
  mcli runtime list > "$TMPD/rt.json" 2>/dev/null || die "runtime list failed"
  # shellcheck disable=SC2086
  BOUND="$(ij bound-agents "$TMPD/agents.json" "$TMPD/rt.json" $PIDS)" || die "cannot read Multica's answers"
  if [ -n "$BOUND" ]; then
    printf '%s\n' "$BOUND" | while IFS= read -r name; do
      printf 'uninstall: archive agent %s in Multica first\n' "$name" >&2
    done
    exit 1
  fi
fi

"$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
LA="$HOME/Library/LaunchAgents/$LABEL.plist"
if [ -e "$LA" ] || [ -L "$LA" ]; then rm -f "$LA"; echo "uninstall: removed $LA"; fi

for w in claude-multica omega-multica-agent multica-bridge; do
  link="$HOME/.local/bin/$w"
  if [ -L "$link" ]; then
    dest="$(readlink "$link")"
    case "$dest" in
      */integrations/multica/bin/*) rm -f "$link"; echo "uninstall: removed $link" ;;
    esac
  fi
done

if [ -d "$BASE/lib" ]; then rm -rf "$BASE/lib"; echo "uninstall: removed $BASE/lib"; fi

kc=0
"$SECURITY" delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || kc=$?
case "$kc" in
  0) echo "uninstall: removed the Keychain item $SERVICE" ;;
  44) ;;    # not there, fine
  *) printf 'uninstall: could not delete the Keychain item %s (exit %s) — delete it in Keychain Access\n' "$SERVICE" "$kc" >&2; FAILED=1 ;;
esac

if [ "$PROFILES" = 1 ]; then
  for id in $PIDS; do
    if mcli_plain runtime profile delete "$id" >/dev/null 2>&1; then
      echo "uninstall: deleted runtime profile $id"
    else
      printf 'uninstall: could not delete runtime profile %s\n' "$id" >&2; FAILED=1
    fi
  done
fi

if [ "$PURGE" = 1 ]; then rm -rf "$BASE"; echo "uninstall: removed $BASE"; fi
exit "$FAILED"
