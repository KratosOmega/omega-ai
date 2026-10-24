#!/bin/sh
# gate-class.sh — sourced by studio-gate (#71): the argv classifier, the config
# read and the load gate. Never run directly. Callers set GC_DISPATCH (the
# resolved $SELF_DIR/studio-dispatch) before gate_classify.
#
# Test-only knobs (production: unset, the machine is read):
#   STUDIO_GATE_LOADAVG    the 1-minute load average (a decimal)
#   STUDIO_GATE_PHYS_CORES the physical core count (a positive integer)
#
# Load rule: t = 2 x physical cores (8 on the 4-core i7-7700HQ). It admits the
# measured baseline (load ~ 5 with two live runs and a wall-paced suite) and a
# CPU-bound fixed-fps suite (~ 6). It refuses at >= 8, when every logical CPU is
# busy. There is no config override.

# Byte collation: under a UTF-8 locale macOS sh matches [a-z] by collation (A-Y too).
unset LC_ALL; LC_COLLATE=C
# cfg-begin (byte-identical in bin/gate-class.sh and engines/godot/cfg.sh; #71 D15)
# cfg_field FILE KEY — a flat JSON string key's value (studio-dispatch field()).
cfg_field() {
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}
# studio_cfg KEY — KEY from .studio/config.json at the git top level (else the
# current dir); when that file lacks it, from $STUDIO_START_DIR's (the run's).
studio_cfg() {
  _sc_top="$(git rev-parse --show-toplevel 2>/dev/null)" || _sc_top=""
  [ -n "$_sc_top" ] || _sc_top="$(pwd -P)"
  _sc_v="$(cfg_field "$_sc_top/.studio/config.json" "$1")"
  if [ -z "$_sc_v" ] && [ -n "${STUDIO_START_DIR:-}" ]; then
    _sc_v="$(cfg_field "$STUDIO_START_DIR/.studio/config.json" "$1")"
  fi
  printf '%s\n' "$_sc_v"
}
# cfg-end

# gate_wt — the worktree the caller is in: the git top level, else the cwd.
gate_wt() {
  _gw_t="$(git rev-parse --show-toplevel 2>/dev/null)" || _gw_t=""
  [ -n "$_gw_t" ] || _gw_t="$(pwd -P)"
  ( cd "$_gw_t" && pwd -P )
}

# gc_resolve PATH — PATH with every symlink resolved (studio-dispatch's loop),
# its directory in physical form. Prints nothing when the directory is gone.
gc_resolve() {
  _gr_s="$1"; _gr_n=0
  while [ -L "$_gr_s" ]; do
    _gr_n=$((_gr_n + 1))
    [ "$_gr_n" -le 40 ] || return 0
    _gr_l="$(readlink "$_gr_s")"
    case "$_gr_l" in
      /*) _gr_s="$_gr_l" ;;
      *)  _gr_s="$(dirname "$_gr_s")/$_gr_l" ;;
    esac
  done
  _gr_d="$(cd "$(dirname "$_gr_s")" 2>/dev/null && pwd -P)" || return 0
  [ -n "$_gr_d" ] || return 0
  printf '%s/%s\n' "$_gr_d" "$(basename "$_gr_s")"
}

# _gc_file P — P is not an option, has no glob characters, and is an existing
# regular file relative to the cwd.
_gc_file() {
  case "$1" in
    ''|-*|*'*'*|*'?'*|*'['*|*'{'*) return 1 ;;
  esac
  [ -f "$1" ]
}

# _gc_word W — a non-empty word of letters, digits, _ and -.
_gc_word() {
  case "$1" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# _gc_godot "$@" — the args after `sh`; prints the argv class, or nothing.
_gc_godot() {
  [ "$#" -ge 2 ] && [ "$2" = test ] || return 0
  [ -n "${GC_DISPATCH:-}" ] || return 0
  [ "$(gc_resolve "$1")" = "$GC_DISPATCH" ] || return 0
  case "$#" in
    2) echo shareable ;;
    3)
      [ "$3" != --file ] || return 0
      if [ -d "$3" ]; then echo shareable; fi ;;
    4)
      [ "$3" = --file ] || return 0
      case "$4" in
        ''|,*|*,|*,,*|*,*,*,*) return 0 ;;
      esac
      echo short ;;
  esac
  return 0
}

# _gc_vitest "$@" — the args after `vitest`; return 0 iff whitelisted.
_gc_vitest() {
  [ "${1:-}" = run ] || return 1
  shift
  _gv_min=0; _gv_max=0; _gv_pos=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --minWorkers=1) _gv_min=$((_gv_min + 1)) ;;
      --maxWorkers=1|--maxWorkers=2) _gv_max=$((_gv_max + 1)) ;;
      --reporter=*) _gc_word "${1#--reporter=}" || return 1 ;;
      --silent|--no-color) ;;
      --testNamePattern=?*) ;;
      -t)
        [ "$#" -ge 2 ] || return 1
        case "$2" in ''|-*) return 1 ;; esac
        shift ;;
      -*) return 1 ;;
      *) _gc_file "$1" || return 1; _gv_pos=$((_gv_pos + 1)) ;;
    esac
    shift
  done
  [ "$_gv_min" = 1 ] && [ "$_gv_max" = 1 ] && [ "$_gv_pos" -ge 1 ]
}

# _gc_tsc "$@" — the args after `tsc`; return 0 iff whitelisted.
_gc_tsc() {
  _gt_ne=0; _gt_p=0; _gt_pr=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --noEmit) _gt_ne=$((_gt_ne + 1)) ;;
      -p|--project)
        [ "$#" -ge 2 ] || return 1
        _gc_file "$2" || return 1
        _gt_p=$((_gt_p + 1)); shift ;;
      --pretty)
        [ "$#" -ge 2 ] && [ "$2" = false ] || return 1
        _gt_pr=$((_gt_pr + 1)); shift ;;
      *) return 1 ;;
    esac
    shift
  done
  [ "$_gt_ne" = 1 ] && [ "$_gt_p" -le 1 ] && [ "$_gt_pr" -le 1 ]
}

# _gc_eslint "$@" — the args after `eslint`; return 0 iff whitelisted.
_gc_eslint() {
  _ge_pos=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --max-warnings)
        [ "$#" -ge 2 ] || return 1
        case "$2" in ''|*[!0-9]*) return 1 ;; esac
        shift ;;
      --format)
        [ "$#" -ge 2 ] || return 1
        _gc_word "$2" || return 1
        shift ;;
      -*) return 1 ;;
      *) _gc_file "$1" || return 1; _ge_pos=$((_ge_pos + 1)) ;;
    esac
    shift
  done
  [ "$_ge_pos" -ge 1 ]
}

# gate_classify CMD [ARG…] — one line: `short godot`, `short node`,
# `shareable godot` or `exclusive godot`. Needs GC_DISPATCH.
gate_classify() {
  _gcl_c=""; _gcl_k=godot
  case "${1:-}" in
    sh|/bin/sh)
      shift
      if [ "$#" -ge 1 ]; then _gcl_c="$(_gc_godot "$@")"; fi ;;
    npx|node_modules/.bin/vitest|./node_modules/.bin/vitest|node_modules/.bin/tsc|./node_modules/.bin/tsc|node_modules/.bin/eslint|./node_modules/.bin/eslint)
      if [ "$1" = npx ]; then
        shift
        if [ "${1:-}" = --no-install ]; then shift; fi
        _gcl_t="${1:-}"
        if [ "$#" -ge 1 ]; then shift; fi
      else
        _gcl_t="${1##*/}"
        shift
      fi
      case "$_gcl_t" in
        vitest) if _gc_vitest "$@"; then _gcl_c=short; fi ;;
        tsc)    if _gc_tsc "$@"; then _gcl_c=short; fi ;;
        eslint) if _gc_eslint "$@"; then _gcl_c=short; fi ;;
      esac
      if [ -n "$_gcl_c" ]; then _gcl_k=node; fi ;;
  esac
  [ -n "$_gcl_c" ] || _gcl_c=exclusive
  printf '%s %s\n' "$_gcl_c" "$_gcl_k"
}

# gate_effective CLASS LANE_ON — CLASS when LANE_ON is 1; with the lane off, a
# shareable or short caller is exclusive.
gate_effective() {
  if [ "$2" = 1 ]; then printf '%s\n' "$1"; return 0; fi
  case "$1" in
    shareable|short) echo exclusive ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# gate_phys_cores — the physical core count (a positive integer), else return 1.
gate_phys_cores() {
  if [ -n "${STUDIO_GATE_PHYS_CORES+x}" ]; then
    _gp_n="$STUDIO_GATE_PHYS_CORES"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin) _gp_n="$(sysctl -n hw.physicalcpu 2>/dev/null)" ;;
      Linux)  _gp_n="$(awk -F: '/^physical id/ { p = $2 + 0 } /^core id/ { s[p "," ($2 + 0)] = 1 } END { n = 0; for (k in s) n++; print n }' /proc/cpuinfo 2>/dev/null)" ;;
      *) return 1 ;;
    esac
  fi
  case "$_gp_n" in
    ''|*[!0-9]*|0|0[0-9]*) return 1 ;;
  esac
  printf '%s\n' "$_gp_n"
}

# _gc_cfg_raw KEY — KEY's raw token (quotes stripped, so 8, "8" and "auto" all
# read) from the same config files studio_cfg reads; empty when absent.
_gc_cfg_raw() {
  _gr_top="$(git rev-parse --show-toplevel 2>/dev/null)" || _gr_top=""
  [ -n "$_gr_top" ] || _gr_top="$(pwd -P)"
  _gr_v=""
  for _gr_f in "$_gr_top/.studio/config.json" "${STUDIO_START_DIR:+$STUDIO_START_DIR/.studio/config.json}"; do
    [ -n "$_gr_f" ] && [ -f "$_gr_f" ] || continue
    _gr_v="$(sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([^,}[:space:]]*\).*/\1/p' "$_gr_f" | head -n 1 | tr -d '"')"
    [ -z "$_gr_v" ] || break
  done
  printf '%s\n' "$_gr_v"
}

# gate_node_workers — the vitest worker count for a whole-suite run (a positive
# integer): config node_workers (auto or 1-32) when set, else auto = max(2,
# physical cores / 2), else 2 when the cores are unreadable. A bad value prints
# `gate: node_workers must be auto or 1-32, got <v>` on stderr and returns 1.
gate_node_workers() {
  _gn_v="$(_gc_cfg_raw node_workers)"
  case "$_gn_v" in
    ''|auto) ;;
    [1-9]|[1-2][0-9]|3[0-2]) printf '%s\n' "$_gn_v"; return 0 ;;
    *) printf 'gate: node_workers must be auto or 1-32, got %s\n' "$_gn_v" >&2; return 1 ;;
  esac
  _gn_c="$(gate_phys_cores)" || { echo 2; return 0; }
  _gn_h=$((_gn_c / 2))
  [ "$_gn_h" -ge 2 ] || _gn_h=2
  printf '%s\n' "$_gn_h"
}

# gate_load1 — the 1-minute load average (a decimal), else return 1.
gate_load1() {
  if [ -n "${STUDIO_GATE_LOADAVG+x}" ]; then
    _gl_v="$STUDIO_GATE_LOADAVG"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin) _gl_v="$(sysctl -n vm.loadavg 2>/dev/null | awk '{ print $2 }')" ;;
      Linux)  _gl_v="$(awk '{ print $1 }' /proc/loadavg 2>/dev/null)" ;;
      *) return 1 ;;
    esac
  fi
  printf '%s\n' "$_gl_v" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || return 1
  printf '%s\n' "$_gl_v"
}

# gate_load_ok [CORES] — prints <load>/<threshold> (? for an unreadable side).
# Returns 0 iff both are readable and load < threshold (t = 2 x physical cores).
# CORES, when given, is the core count already read (gate_phys_cores' output,
# empty when unreadable): studio-gate reads it once, not on every poll (§7).
gate_load_ok() {
  _go_l="$(gate_load1)" || _go_l="?"
  _go_t="?"
  if [ "$#" -ge 1 ]; then _go_c="$1"; else _go_c="$(gate_phys_cores)" || _go_c=""; fi
  case "$_go_c" in ''|*[!0-9]*|0|0[0-9]*) ;; *) _go_t=$((_go_c * 2)) ;; esac
  printf '%s/%s\n' "$_go_l" "$_go_t"
  [ "$_go_l" != "?" ] && [ "$_go_t" != "?" ] || return 1
  awk -v l="$_go_l" -v t="$_go_t" 'BEGIN { exit !(l + 0 < t + 0) }'
}
