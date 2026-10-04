# wrapper-lib.sh — sourced by claude-multica and omega-multica-agent (never
# run). The caller sets $self (its own real path, symlinks resolved) and
# $WRAPPER (its name) first. Defines paths and functions only.
WRAPPER_BIN="$(cd "$(dirname "$self")" && pwd -P)"
MULTICA_DIR="$(cd "$WRAPPER_BIN/.." && pwd -P)"
REPO="$(cd "$MULTICA_DIR/../.." && pwd -P)"
SO="$REPO/studios/game-dev/bin/studio-overnight"
STATE_BIN="$REPO/studios/game-dev/bin/studio-state"
MULTICA_DENY="$MULTICA_DIR/multica-deny.txt"
AGENT_CONTEXT="$MULTICA_DIR/agent-context.md"
die() { printf '%s: %s\n' "$WRAPPER" "$*" >&2; exit 1; }
# sq TEXT — TEXT as one single-quoted shell word.
sq() { printf "'%s'" "$(printf '%s' "$1" | LC_ALL=C sed "s/'/'\\\\''/g")"; }
# deny_list DIR — the core's rules for DIR, then multica-deny.txt's; one per
# line. Returns 1 with ONE line on stderr when deny-rules fails or prints
# nothing; on success deny-rules' notes are passed to stderr.
deny_list() {
  _dl_err="$(mktemp "${TMPDIR:-/tmp}/omega-deny.XXXXXX")" || { printf '%s: cannot make a temp file\n' "$WRAPPER" >&2; return 1; }
  _dl_core="$(sh "$SO" deny-rules --dir "$1" 2>"$_dl_err")"; _dl_st=$?
  if [ "$_dl_st" -ne 0 ]; then
    printf '%s: deny-rules failed (exit %s) for %s: %s\n' "$WRAPPER" "$_dl_st" "$1" "$(tail -n 1 "$_dl_err")" >&2
    rm -f "$_dl_err"; return 1
  fi
  cat "$_dl_err" >&2; rm -f "$_dl_err"
  [ -n "$_dl_core" ] || { printf '%s: deny-rules printed no rules for %s\n' "$WRAPPER" "$1" >&2; return 1; }
  [ -f "$MULTICA_DENY" ] || { printf '%s: missing %s\n' "$WRAPPER" "$MULTICA_DENY" >&2; return 1; }
  _dl_mine="$(LC_ALL=C sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$MULTICA_DENY" | grep -Ev '^(#|$)')"
  [ -n "$_dl_mine" ] || { printf '%s: %s has no rules\n' "$WRAPPER" "$MULTICA_DENY" >&2; return 1; }
  printf '%s\n%s\n' "$_dl_core" "$_dl_mine"
}
# resolve_path P — P's real location (symlinks followed); returns 1 if unresolvable.
resolve_path() {
  _rp="$1"
  while [ -L "$_rp" ]; do
    _rl="$(readlink "$_rp")"
    case "$_rl" in /*) _rp="$_rl" ;; *) _rp="$(dirname "$_rp")/$_rl" ;; esac
  done
  _rd="$(cd -P "$(dirname "$_rp")" 2>/dev/null && pwd -P)" || return 1    # -P: a `..` after a symlinked dir is physical
  printf '%s/%s' "$_rd" "$(basename "$_rp")"
}
# deny_words DIR — deny_list as words for eval: --disallowedTools 'rule' …
deny_words() {
  _dw_list="$(deny_list "$1")" || return 1
  _dw_out=""
  while IFS= read -r _dw_r; do
    [ -n "$_dw_r" ] || continue
    _dw_out="$_dw_out --disallowedTools $(sq "$_dw_r")"
  done <<EOT
$_dw_list
EOT
  [ -n "$_dw_out" ] || { printf '%s: no deny words for %s\n' "$WRAPPER" "$1" >&2; return 1; }
  printf '%s' "$_dw_out"
}
