#!/bin/sh
# cfg-begin (byte-identical in bin/gate-class.sh and engines/godot/cfg.sh; #71 D15)
# cfg_field FILE KEY — a flat JSON string key's value (studio-dispatch field()).
cfg_field() {
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}
# cfg_token FILE KEY — a flat JSON key's raw token (a bare number; a string
# keeps its quotes).
cfg_token() {
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\([^,}[:space:]]*\).*/\1/p' "$1" | head -n 1
}
# studio_cfg_by READER KEY [ROOT] — the one config resolver (studio_cfg, the
# engine adapters and studio-setup): KEY, read by READER (cfg_field or
# cfg_token), from .studio/config.json at the git top level (else the current
# dir); when that file lacks it, from $STUDIO_START_DIR's (the run's); when
# that lacks it too and ROOT is given, from ROOT's (studio-setup passes the
# state root): tree -> $STUDIO_START_DIR -> ROOT, key by key.
studio_cfg_by() {
  _sc_top="$(git rev-parse --show-toplevel 2>/dev/null)" || _sc_top=""
  [ -n "$_sc_top" ] || _sc_top="$(pwd -P)"
  _sc_v=""
  for _sc_d in "$_sc_top" "${STUDIO_START_DIR:-}" "${3:-}"; do
    [ -n "$_sc_d" ] || continue
    _sc_v="$("$1" "$_sc_d/.studio/config.json" "$2")"
    [ -z "$_sc_v" ] || break
  done
  printf '%s\n' "$_sc_v"
}
# studio_cfg KEY [ROOT] — a string KEY, resolved by studio_cfg_by.
studio_cfg() { studio_cfg_by cfg_field "$@"; }
# cfg-end
