# gate_lanes_fixture.sh — sourced (not a suite) by tests/gate_lanes_test.sh and
# tests/probes/gate_lane_bench.sh: a stub studio, a project repo with linked
# worktrees, and background callers whose runs leave start/end marks (#71 R3).
# The sourcer sets BIN (studios/game-dev/bin) and TMP (an existing scratch dir).
#
# API:
#   lanes_init               $LS (the stub studio root) and the env: exports
#                            OMEGA_STUDIO_ROOT=$LS STUDIO_GATE_POLL_SECONDS=0.1
#                            STUDIO_GATE_LOADAVG=0 STUDIO_GATE_PHYS_CORES=4
#                            LANES_MARKS LANES_HOLD_DIR LANES_GATE LANES_STUB;
#                            unsets the lane env and the stub knobs below
#   lanes_repo NAME          a project repo at $TMP/NAME → $LR (lane on)
#   lanes_wt NAME [on|off]   a linked worktree $LR-wt/NAME (lane per the
#                            argument, default on; override.cfg present) → its path
#   lanes_bg TAG DIR -- CMD… run CMD from DIR in the background with LANES_TAG=TAG;
#                            $TMP/out.TAG, err.TAG, rc.TAG (its status), pid.TAG
#                            (CMD's pid: the gate's, since the wrappers exec it)
#   lanes_suite TAG DIR      lanes_bg … sh $BIN/studio-test (a shareable suite)
#   lanes_gut TAG DIR        lanes_bg … sh $BIN/studio-test --file tests/unit/a.gd (a GUT short)
#   lanes_vitest TAG DIR     lanes_bg from DIR/web-tools … studio-gate vitest -- the O10 vitest form
#   lanes_x TAG DIR          lanes_bg … studio-gate x -- sh -c … (exclusive; the same stub marks)
#   lanes_go TAG             release the runs holding on TAG
#   lanes_wait_mark REGEX    event wait (0.1 s polls, 30 s) for a marks line; else a FAIL
#   lanes_wait_file PATH     event wait for PATH (a glob is fine); else a FAIL
#   lanes_wait_err TAG REGEX event wait for REGEX in $TMP/err.TAG; else a FAIL
#   lanes_done TAG           wait (30 s) for TAG's call to end → its exit status
#   lanes_overlap A B        yes iff `s A` comes before `e B` and `s B` before `e A`
#
# The stub ($LS/engines/godot/test.sh, the node_modules/.bin stubs, the exclusive
# form) appends `s <tag> <lane> <nice> <pid> <demote-env> <pwd -P>` (pwd last: a
# path may hold a space) and `e <tag>` to $LANES_MARKS. Knobs (env of the call):
#   LANES_SLEEP=N        hold N s instead of on the hold file
#   LANES_HOLD=NAME      hold on $LANES_HOLD_DIR/NAME instead of the tag's file
#   LANES_RC=N           exit N (default 0)
#   LANES_TRAP=1         ignore TERM
#   LANES_NEST=1         run `sh $LANES_GATE inner -- true` inside the run
#   LANES_DEMOTE=REASON  in the slot (STUDIO_GATE_DEMOTE set): write REASON to the
#                        demote file and exit 1
#   LANES_DEMOTE_SLEEP=N with LANES_DEMOTE: sleep N s after writing it, then exit 1
#   LANES_LEAK=1         in the slot (STUDIO_GATE_LANE=short): leave a leak, which the
#                        stub isolate.sh's next --scrub reports (exit 3) and clears

lanes_stub_text() {
  cat <<'STUB'
#!/bin/sh
# stub run: marks start (tag, lane, niceness, pid, demote env, worktree) and end;
# holds until $LANES_HOLD_DIR/<tag> exists (event wait, at most 30 s) or LANES_SLEEP s.
_t="${LANES_TAG:-t}"
printf 's %s %s %s %s %s %s\n' "$_t" "${STUDIO_GATE_LANE:--}" "$(ps -o nice= -p $$ | tr -d ' ')" "$$" "${STUDIO_GATE_DEMOTE:-none}" "$(pwd -P)" >> "$LANES_MARKS"
[ -z "${LANES_NEST:-}" ] || sh "$LANES_GATE" inner -- true
[ -z "${LANES_LEAK:-}" ] || [ "${STUDIO_GATE_LANE:-}" != short ] || : > "$LANES_HOLD_DIR/leaked"
if [ -n "${LANES_DEMOTE:-}" ] && [ -n "${STUDIO_GATE_DEMOTE:-}" ]; then
  printf '%s\n' "$LANES_DEMOTE" > "$STUDIO_GATE_DEMOTE"
  [ -z "${LANES_DEMOTE_SLEEP:-}" ] || sleep "$LANES_DEMOTE_SLEEP"
  printf 'e %s\n' "$_t" >> "$LANES_MARKS"; exit 1
fi
[ -z "${LANES_TRAP:-}" ] || trap '' TERM
_h="${LANES_HOLD:-$_t}"
if [ -n "${LANES_SLEEP:-}" ]; then sleep "$LANES_SLEEP"
else _i=0; while [ ! -f "$LANES_HOLD_DIR/$_h" ] && [ "$_i" -lt 300 ]; do sleep 0.1; _i=$((_i + 1)); done; fi
printf 'e %s\n' "$_t" >> "$LANES_MARKS"
exit "${LANES_RC:-0}"
STUB
}

lanes_init() {
  LS="$TMP/lanes-studio"
  mkdir -p "$LS/engines/godot" "$TMP/lanes-holds"
  printf '{"engine": "godot4"}\n' > "$LS/studio.json"
  lanes_stub_text > "$LS/engines/godot/test.sh"
  chmod +x "$LS/engines/godot/test.sh"
  LANES_STUB="$LS/engines/godot/test.sh"
  printf '#!/bin/sh\ncase "${1:-}" in --check) [ -f override.cfg ] ;;\n  --scrub) [ -f "$LANES_HOLD_DIR/leaked" ] || exit 0; rm -f "$LANES_HOLD_DIR/leaked"; echo config/use_custom_user_dir; exit 3 ;;\n  *) exit 0 ;; esac\n' > "$LS/engines/godot/isolate.sh"
  chmod +x "$LS/engines/godot/isolate.sh"
  LANES_MARKS="$TMP/lanes-marks"; : > "$LANES_MARKS"
  LANES_HOLD_DIR="$TMP/lanes-holds"; rm -f "$LANES_HOLD_DIR"/*
  LANES_GATE="$BIN/studio-gate"
  unset STUDIO_START_DIR STUDIO_GATE_HELD STUDIO_GATE_LANE STUDIO_GATE_DEMOTE STUDIO_UNIT_TAG \
        STUDIO_GATE_MINUTES STUDIO_GATE_SECONDS STUDIO_GATE_SHORT_SECONDS \
        LANES_TAG LANES_SLEEP LANES_HOLD LANES_RC LANES_TRAP LANES_NEST LANES_DEMOTE LANES_DEMOTE_SLEEP LANES_LEAK
  OMEGA_STUDIO_ROOT="$LS"; STUDIO_GATE_POLL_SECONDS=0.1; STUDIO_GATE_LOADAVG=0; STUDIO_GATE_PHYS_CORES=4
  export OMEGA_STUDIO_ROOT STUDIO_GATE_POLL_SECONDS STUDIO_GATE_LOADAVG STUDIO_GATE_PHYS_CORES \
         LANES_MARKS LANES_HOLD_DIR LANES_GATE LANES_STUB
}

# _lanes_git DIR ARGS… — git in DIR with a fixed identity.
_lanes_git() { _lg_d="$1"; shift; git -C "$_lg_d" -c user.name=t -c user.email=t@t "$@"; }

lanes_repo() {
  LR="$TMP/$1"
  mkdir -p "$LR/addons/gut" "$LR/tests/unit" "$LR/web-tools/tests" "$LR/web-tools/node_modules/.bin"
  printf 'config_version=5\n' > "$LR/project.godot"
  printf 'extends SceneTree\n' > "$LR/addons/gut/gut_cmdln.gd"
  for _lr_f in a b c d; do printf 'extends GutTest\n' > "$LR/tests/unit/$_lr_f.gd"; done
  for _lr_f in a b; do printf 'test("%s", () => {})\n' "$_lr_f" > "$LR/web-tools/tests/$_lr_f.test.ts"; done
  for _lr_f in vitest tsc; do
    lanes_stub_text > "$LR/web-tools/node_modules/.bin/$_lr_f"; chmod +x "$LR/web-tools/node_modules/.bin/$_lr_f"
  done
  _lanes_git "$LR" init -q -b main >/dev/null 2>&1
  _lanes_git "$LR" add -f -A >/dev/null 2>&1
  _lanes_git "$LR" commit -q -m fixture >/dev/null 2>&1
  ( cd "$LR" && sh "$BIN/studio-state" init ) >/dev/null 2>&1
  printf '{"engine": "godot4", "gate_short_lane": "on"}\n' > "$LR/.studio/config.json"
}

lanes_wt() {
  _lw_p="$LR-wt/$1"
  _lanes_git "$LR" worktree add -q "$_lw_p" -b "b-$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-')" >/dev/null 2>&1
  mkdir -p "$_lw_p/.studio"
  printf '{"engine": "godot4", "gate_short_lane": "%s"}\n' "${2:-on}" > "$_lw_p/.studio/config.json"
  : > "$_lw_p/override.cfg"
  ( cd "$_lw_p" && pwd -P )
}

lanes_bg() {
  _lb_t="$1"; _lb_d="$2"; shift 3
  rm -f "$TMP/rc.$_lb_t" "$TMP/pid.$_lb_t" "$TMP/out.$_lb_t" "$TMP/err.$_lb_t"
  ( cd "$_lb_d" && LANES_TAG="$_lb_t" sh -c 'echo $$ > "$0"; exec "$@"' "$TMP/pid.$_lb_t" "$@" \
      > "$TMP/out.$_lb_t" 2> "$TMP/err.$_lb_t"; echo $? > "$TMP/rc.$_lb_t" ) &
}
lanes_suite() { lanes_bg "$1" "$2" -- sh "$BIN/studio-test"; }
lanes_gut() { lanes_bg "$1" "$2" -- sh "$BIN/studio-test" --file tests/unit/a.gd; }
lanes_vitest() {
  lanes_bg "$1" "$2/web-tools" -- sh "$LANES_GATE" vitest -- node_modules/.bin/vitest run --minWorkers=1 --maxWorkers=2 tests/a.test.ts
}
lanes_x() { lanes_bg "$1" "$2" -- sh "$LANES_GATE" x -- sh -c 'exec sh "$0"' "$LANES_STUB"; }

lanes_go() { : > "$LANES_HOLD_DIR/$1"; }

# _lanes_poll CMD… — true once CMD succeeds (0.1 s polls, 30 s); else a counted FAIL.
_lanes_poll() {
  _lp_i=0
  while [ "$_lp_i" -lt 300 ]; do
    "$@" && return 0
    sleep 0.1; _lp_i=$((_lp_i + 1))
  done
  TESTS_RUN=$((TESTS_RUN + 1)); _fail "waited 30 s for: $*"
  return 1
}
_lanes_has_mark() { grep -Eq -- "$1" "$LANES_MARKS" 2>/dev/null; }
_lanes_exists() { for _le_f in $1; do [ -e "$_le_f" ] && return 0; done; return 1; }
_lanes_err_has() { grep -Eq -- "$2" "$TMP/err.$1" 2>/dev/null; }
_lanes_rc_ready() { [ -s "$TMP/rc.$1" ]; }
lanes_wait_mark() { _lanes_poll _lanes_has_mark "$1"; }
lanes_wait_file() { _lanes_poll _lanes_exists "$1"; }
lanes_wait_err() { _lanes_poll _lanes_err_has "$1" "$2"; }
lanes_done() {
  _lanes_poll _lanes_rc_ready "$1" || { echo timeout; return 0; }
  cat "$TMP/rc.$1"
}

lanes_overlap() {
  awk -v a="$1" -v b="$2" '
    $1 == "s" && $2 == a && !sa { sa = NR } $1 == "e" && $2 == a && !ea { ea = NR }
    $1 == "s" && $2 == b && !sb { sb = NR } $1 == "e" && $2 == b && !eb { eb = NR }
    END {
      if (!sa || !sb) { print "no"; exit }
      if (!ea) ea = NR + 1; if (!eb) eb = NR + 1
      print ((sa < eb && sb < ea) ? "yes" : "no")
    }' "$LANES_MARKS"
}
