#!/bin/sh
# overnight-sessions.sh — the project-wide session cap (#39 AC27): slots
# <root>/.studio/sessions/<n> (mkdir, n in 1..cap), a FIFO of waiters
# <root>/.studio/sessions/wait/<key>-<lane pid>, every change under
# <root>/.studio/sessions.mutex (never the gate mutex). Sourced after
# overnight-runs.sh. The caller sets STATE_ROOT, SESS_ME, SESS_RUN and
# SESS_START_CAP. A slot's owner file: lane= session= run= unit= (D20).

sess_init() { SESS_DIR="$STATE_ROOT/.studio/sessions"; SESS_MX="$STATE_ROOT/.studio/sessions.mutex"; SESS_SLOT=""; SESS_WAIT=""; }
sess_cap() {
  _sc="$(sed -n 's/.*"max_sessions"[[:space:]]*:[[:space:]]*\([^,}[:space:]]*\).*/\1/p' "$STATE_ROOT/.studio/config.json" 2>/dev/null | head -n 1)"
  case "$_sc" in ''|*[!0-9]*) _sc="${SESS_START_CAP:-6}" ;; esac
  { [ "$_sc" -ge 1 ] && [ "$_sc" -le 8 ]; } 2>/dev/null || _sc="${SESS_START_CAP:-6}"
  printf '%s\n' "$_sc"
}
sess_pid_is() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*|'') return 1 ;; esac
  ps -o args= -p "$1" 2>/dev/null | grep -q -- "$2"
}
sess_owner_live() { sess_pid_is "$(runs_kv lane "$1")" studio-overnight || sess_pid_is "$(runs_kv session "$1")" claude; }
sess_gone() { _sg="$SESS_DIR/.gone.${1##*/}.${SESS_ME:-$$}.$$"; mv "$1" "$_sg" 2>/dev/null && rm -rf "$_sg"; }
sess_live_count() {
  _sl=0
  for _s in "$SESS_DIR"/[0-9]*; do [ -d "$_s" ] && [ -f "$_s/owner" ] && sess_owner_live "$_s/owner" && _sl=$((_sl + 1)); done
  printf '%s\n' "$_sl"
}
# sess_reclaim — under the mutex: a slot with no owner file or a dead owner,
# and a wait entry whose lane is dead, go (AC27: liveness, never age).
sess_reclaim() {
  for _sr in "$SESS_DIR"/[0-9]*; do
    [ -d "$_sr" ] || continue
    { [ -f "$_sr/owner" ] && sess_owner_live "$_sr/owner"; } || sess_gone "$_sr"
  done
  for _sr in "$SESS_DIR"/wait/[0-9]*-[0-9]*; do
    [ -f "$_sr" ] || continue
    sess_pid_is "${_sr##*-}" studio-overnight || rm -f "$_sr"
  done
}
# sess_key — D3: epoch s x 10^9 bumped past the last key (under the mutex).
sess_key() {
  _sk="$(( $(date +%s) * 1000000000 ))"
  _skl="$(cat "$SESS_DIR/wait/.last" 2>/dev/null)"; case "$_skl" in ''|*[!0-9]*) _skl=0 ;; esac
  [ "$_sk" -gt "$_skl" ] || _sk=$((_skl + 1))
  printf '%s\n' "$_sk" > "$SESS_DIR/wait/.last"; printf '%s\n' "$_sk"
}
sess_enqueue() {
  mkdir -p "$SESS_DIR/wait" 2>/dev/null || return 1
  mx_take "$SESS_MX" "$SESS_ME" || return 1
  SESS_WAIT="$SESS_DIR/wait/$(sess_key)-$SESS_ME"
  printf 'lane=%s\nrun=%s\nstory=%s\nunit=%s\n' "$SESS_ME" "$SESS_RUN" "$1" "$2" > "$SESS_WAIT"
  mx_drop "$SESS_MX" "$SESS_ME"
}
sess_try() {
  mx_take "$SESS_MX" "$SESS_ME" || return 1
  sess_reclaim
  [ -z "$SESS_WAIT" ] || [ -f "$SESS_WAIT" ] || SESS_WAIT=""      # dropped by a sweep: re-queue
  _st_rc=1
  _st_head="$(ls "$SESS_DIR/wait" 2>/dev/null | grep -E '^[0-9]+-[0-9]+$' | sort | head -n 1)"
  if [ -n "$SESS_WAIT" ] && [ "$_st_head" = "${SESS_WAIT##*/}" ]; then
    _st_cap="$(sess_cap)"; _st_live=0
    for _st_s in "$SESS_DIR"/[0-9]*; do [ -d "$_st_s" ] && _st_live=$((_st_live + 1)); done
    _st_n=1
    while [ "$_st_live" -lt "$_st_cap" ] && [ "$_st_n" -le "$_st_cap" ]; do
      if mkdir "$SESS_DIR/$_st_n" 2>/dev/null; then
        printf 'lane=%s\nsession=\nrun=%s\nunit=%s\n' "$SESS_ME" "$SESS_RUN" "$1" > "$SESS_DIR/$_st_n/owner"
        rm -f "$SESS_WAIT"; SESS_WAIT=""; SESS_SLOT="$_st_n"; _st_rc=0; break
      fi
      _st_n=$((_st_n + 1))
    done
  fi
  mx_drop "$SESS_MX" "$SESS_ME"
  return "$_st_rc"
}
sess_session() {
  [ -n "${SESS_SLOT:-}" ] || return 0
  _ss="$SESS_DIR/$SESS_SLOT/owner"
  [ "$(runs_kv lane "$_ss")" = "$SESS_ME" ] || return 0
  sed "s/^session=.*/session=$1/" "$_ss" > "$_ss.$$" && mv -f "$_ss.$$" "$_ss"
}
sess_release() {
  [ -n "${SESS_SLOT:-}" ] || return 0
  _sr_d="$SESS_DIR/$SESS_SLOT"; SESS_SLOT=""
  _sr_m=0; ! mx_take "$SESS_MX" "$SESS_ME" || _sr_m=1
  [ "$(runs_kv lane "$_sr_d/owner")" != "$SESS_ME" ] || sess_gone "$_sr_d"
  [ "$_sr_m" = 0 ] || mx_drop "$SESS_MX" "$SESS_ME"
}
sess_wait_cancel() { [ -z "${SESS_WAIT:-}" ] || rm -f "$SESS_WAIT"; SESS_WAIT=""; }
sess_drop_owner() {
  [ -n "$1" ] || return 0
  _sd_me="${SESS_ME:-$$}"; _sd_m=0; ! mx_take "$SESS_MX" "$_sd_me" || _sd_m=1
  for _sd in "$SESS_DIR"/[0-9]*; do
    [ -d "$_sd" ] && [ "$(runs_kv lane "$_sd/owner")" = "$1" ] && sess_gone "$_sd"
  done
  rm -f "$SESS_DIR"/wait/[0-9]*-"$1"
  [ "$_sd_m" = 0 ] || mx_drop "$SESS_MX" "$_sd_me"
}
