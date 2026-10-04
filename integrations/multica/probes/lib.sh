# lib.sh — shared by the #28 open probes (P1-P7). Sourced, never executed.
# Run the probes by hand in Terminal.app, not in a Claude session: they write
# to the real workspace. Nothing here reads or prints anything under ~/.multica.
M="${MULTICA_CLI:-/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica}"
PROFILE="${MULTICA_PROBE_PROFILE:-desktop-api.multica.ai}"
WS="${MULTICA_PROBE_WORKSPACE:?set MULTICA_PROBE_WORKSPACE to your workspace id}"
SERVER="${MULTICA_PROBE_SERVER:-https://api.multica.ai}"
PROBE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RES="${MULTICA_PROBE_RESULTS:-$HOME/.claude-gamedev/multica/probes}"
mkdir -p "$RES"
mc() { "$M" --profile "$PROFILE" --workspace-id "$WS" "$@"; }
pj() { /usr/bin/python3 "$PROBE_DIR/pj.py" "$@"; }
# redact — token-shaped strings (leading boundary, so `format_x` survives),
# e-mail addresses and home paths out of stdin.
redact() {
  sed -E 's/(^|[^A-Za-z0-9])(mul|mat)_[A-Za-z0-9_-]+/\1<token>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+/operator@example.com/g; s#/Users/[^/ "]+#/Users/operator#g'
}
record() {
  printf '%s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$RES/results.txt"
  printf '%s: %s\n' "$1" "$2"
}
cleanup_add() { printf '%s %s\n' "$1" "$2" >> "$RES/cleanup.txt"; }   # KIND ID
confirm() { printf '%s [y/N] ' "$1"; read -r _a; [ "$_a" = y ]; }
die() { printf 'probe: %s\n' "$*" >&2; exit 1; }
# unverified DESC CMD... — run a CLI verb or flag that no feasibility probe
# verified. On failure stop loudly: nothing continues past a step that did not
# happen. (exit, not return: lib is sourced into the probe script.)
unverified() {
  _uv_d="$1"; shift
  "$@" || {
    printf 'FAIL: %s is not a verified CLI verb and it failed. Do this step in the Multica web UI, then re-run this script.\n' "$_uv_d" >&2
    exit 1
  }
}
[ -x "$M" ] || die "Multica CLI not executable: $M (set MULTICA_CLI)"
# agent_id — gd-probe's id, looked up by name from `agent list`.
agent_id() { mc agent list --output json | pj find name gd-probe id; }
# need_agent — sets AID or stops.
need_agent() { AID="$(agent_id)"; [ -n "$AID" ] || die "agent gd-probe not found in 'agent list'"; }
# need_runtime_profile — MULTICA_PROBE_RUNTIME_PROFILE is required.
need_runtime_profile() {
  RP="${MULTICA_PROBE_RUNTIME_PROFILE:-}"
  [ -n "$RP" ] || die "set MULTICA_PROBE_RUNTIME_PROFILE to the probe runtime profile id"
}
# wait_idle ISSUE MAX_SECONDS — until `issue runs --active` lists nothing.
wait_idle() {
  _wi=0
  while [ "$_wi" -lt "$2" ]; do
    [ "$(mc issue runs "$1" --active --output json | pj count)" = 0 ] && return 0
    sleep 10; _wi=$((_wi + 10))
  done
  return 1
}
