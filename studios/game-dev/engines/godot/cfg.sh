#!/bin/sh
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
