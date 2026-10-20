#!/bin/sh
# isolate.sh [--check | --scrub | --leaks DIR] — per-worktree user:// for the Godot
# adapter (#71 D12). Godot keeps user:// under one per-project folder, so lanes in
# different worktrees would share (and corrupt) it. In a linked worktree whose
# .studio/config.json says "user_dir": "per-worktree", an untracked, git-excluded
# override.cfg points user:// at <project>-lanes-<h8>/<worktree id> instead.
#
#   isolate.sh           ensure the override.cfg, scrub project.godot, sweep dead dirs
#                        (daily); always exit 0
#   isolate.sh --check   0 when isolation is in effect, 1 otherwise; writes nothing
#   isolate.sh --scrub   remove the lanes lines a run put in project.godot that HEAD
#                        lacks: 0 clean or n/a · 3 removed (stdout: the keys) · 1 error
#   isolate.sh --leaks DIR  0 none · 3 found (stdout: <path>: <keys> per file) · 1 error
#
# Test-only knob: STUDIO_GODOT_USER_ROOT names the data root holding the per-project
# folders (production: unset, so ~/Library/Application Support on Darwin). Setting it
# also marks the platform known; any other platform without it is not isolated.
set -u

LANES_USE_RE='^config/use_custom_user_dir='
LANES_NAME_RE='^config/custom_user_dir_name="[^"]*-lanes(-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])?/[^"]*"[[:space:]]*$'
MARKER='; omega-ai studio-test: per-worktree user:// (#71). Generated; never commit.'

. "$(dirname "$0")/cfg.sh"

# is_opted — this worktree asked for per-worktree user://.
is_opted() { [ "$(studio_cfg user_dir)" = per-worktree ]; }

# load_git — sets _is_gd (git dir) and _is_gcd (common dir); 0 only when linked.
load_git() {
  _is_gd="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  _is_gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$_is_gd" ] && [ -n "$_is_gcd" ] && [ "$_is_gd" != "$_is_gcd" ]
}

# project_name — config/name of ./project.godot, reduced to a safe folder name.
project_name() {
  _is_p="$(sed -n 's/^config\/name="\(.*\)".*/\1/p' project.godot 2>/dev/null | head -n 1 | sed 's/[^A-Za-z0-9._-]//g')"
  case "$_is_p" in ''|.|..) _is_p=godot-project ;; esac
  printf '%s\n' "$_is_p"
}

# hash8 — the clone's key: two clones never share or sweep each other's folder.
hash8() { printf '%s' "$_is_gcd" | cksum | awk '{ printf "%08x", $1 }'; }

# expected NAME — the exact override.cfg content.
expected() {
  printf '%s\n[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="%s"\n' "$MARKER" "$1"
}

# user_root — the data root, empty when the platform is unknown.
user_root() {
  if [ -n "${STUDIO_GODOT_USER_ROOT:-}" ]; then
    printf '%s\n' "$STUDIO_GODOT_USER_ROOT"
  elif [ "$(uname 2>/dev/null)" = Darwin ]; then
    printf '%s\n' "$HOME/Library/Application Support"
  fi
}

# is_ours FILE — a regular file whose line 1 is the marker.
is_ours() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(head -n 1 "$1")" = "$MARKER" ]; }

# lanes_awk list|filter HEADFILE CURRENT [all|name] — one predicate for both: a CURRENT line
# is "ours" when HEAD lacks it and it matches the name pattern (or, with `all`, the use
# pattern too). list prints those lines; filter prints the rest. FILENAME == ARGV[1]
# (not NR == FNR) so an empty HEAD file still counts as the first file.
lanes_awk() {
  awk -v mode="$1" -v use="$LANES_USE_RE" -v nm="$LANES_NAME_RE" -v which="${4:-all}" '
    FILENAME == ARGV[1] { head[$0] = 1; next }
    {
      ours = !($0 in head) && ((which == "all" && $0 ~ use) || $0 ~ nm)
      if (mode == "list" ? ours : !ours) print
    }
  ' "$2" "$3"
}

# keys_of — stdin lines to the unique `, `-joined keys.
keys_of() { sed 's/=.*//' | awk '!s[$0]++' | paste -sd, - | sed 's/,/, /g'; }

# do_scrub — every tracked project.godot under cwd loses the lanes lines HEAD lacks
# (a file not in HEAD is skipped).
do_scrub() {
  is_opted && load_git || return 0
  _is_hf="$(mktemp "${TMPDIR:-/tmp}/isolate-head.XXXXXX")" || return 1
  _is_nf="$_is_hf.new"; _is_ks="$_is_hf.keys"; _is_ls="$_is_hf.list"; : > "$_is_ks"
  _is_err=0
  git -c core.quotePath=false ls-files -- project.godot '*/project.godot' > "$_is_ls" 2>/dev/null
  while IFS= read -r _is_p; do
    [ -n "$_is_p" ] && [ -f "$_is_p" ] || continue
    git show "HEAD:./$_is_p" > "$_is_hf" 2>/dev/null || continue
    _is_rm="$(lanes_awk list "$_is_hf" "$_is_p")"
    [ -n "$_is_rm" ] || continue
    # temp file beside it, then mv: an interrupt never leaves project.godot half-written
    if lanes_awk filter "$_is_hf" "$_is_p" > "$_is_nf" && _is_tp="$(mktemp "$_is_p.XXXXXX")" \
        && cp -p "$_is_p" "$_is_tp" && cat "$_is_nf" > "$_is_tp" && mv -f "$_is_tp" "$_is_p"; then
      printf '%s\n' "$_is_rm" >> "$_is_ks"
    else
      _is_err=1; rm -f "${_is_tp:-}"
    fi
  done < "$_is_ls"
  _is_keys="$(keys_of < "$_is_ks")"
  rm -f "$_is_hf" "$_is_nf" "$_is_ks" "$_is_ls" "${_is_tp:-}"
  [ "$_is_err" = 0 ] || return 1
  [ -n "$_is_keys" ] || return 0
  printf '%s\n' "$_is_keys"
  return 3
}

do_check() {
  [ -n "$(user_root)" ] || return 1
  load_git || return 1
  [ -f project.godot ] && [ -f override.cfg ] || return 1
  _is_name="$(project_name)-lanes-$(hash8)/$(basename "$_is_gd")"
  expected "$_is_name" | cmp -s - override.cfg || return 1
  if grep -q "$LANES_USE_RE" project.godot; then return 1; fi
  return 0
}

# do_sweep PROJECT H8 — at most daily, remove this clone's dead, old, per-worktree dirs.
do_sweep() {
  _is_root="$(user_root)"; [ -n "$_is_root" ] || return 0
  _is_state="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [ -n "$_is_state" ] && [ -d "$_is_state/.studio" ] || return 0
  _is_stamp="$_is_state/.studio/gate.isolate-sweep"
  if [ -e "$_is_stamp" ] && [ -z "$(find "$_is_stamp" -mtime +0 2>/dev/null)" ]; then return 0; fi
  _is_dir="$_is_root/$1-lanes-$2"
  _is_live="$(ls "$_is_gcd/worktrees" 2>/dev/null)"
  if [ -d "$_is_dir" ] && [ ! -L "$_is_dir" ]; then
    for _is_c in "$_is_dir"/*; do
      [ -d "$_is_c" ] && [ ! -L "$_is_c" ] || continue
      [ "$(dirname "$_is_c")" = "$_is_dir" ] || continue
      _is_b="$(basename "$_is_c")"
      case "$_is_b" in ''|.|..) continue ;; esac
      printf '%s\n' "$_is_live" | grep -qxF -- "$_is_b" && continue
      [ -n "$(find "$_is_c" -prune -mmin +60 2>/dev/null)" ] || continue
      rm -rf "$_is_c"
    done
  fi
  touch "$_is_stamp" 2>/dev/null
  return 0
}

do_ensure() {
  is_opted && load_git || return 0
  [ -f project.godot ] || return 0
  _is_foreign=0
  if [ -e override.cfg ] || [ -L override.cfg ]; then
    is_ours override.cfg || _is_foreign=1
  fi
  if [ "$_is_foreign" = 1 ] || git ls-files --error-unmatch override.cfg >/dev/null 2>&1; then
    echo "studio-test: override.cfg here is not studio-test's (or is tracked) — user:// stays shared; GUT short checks use the main lane" >&2
    return 0
  fi
  _is_proj="$(project_name)"
  _is_h8="$(hash8)"
  _is_name="$_is_proj-lanes-$_is_h8/$(basename "$_is_gd")"
  if ! expected "$_is_name" | cmp -s - override.cfg 2>/dev/null; then
    _is_tmp="override.cfg.tmp.$$"
    trap 'rm -f "$_is_tmp"; exit 1' HUP INT TERM
    expected "$_is_name" > "$_is_tmp" && mv -f "$_is_tmp" override.cfg || { rm -f "$_is_tmp"; trap - HUP INT TERM; return 0; }
    trap - HUP INT TERM
  fi
  # Exclude it (once) in the shared info/exclude.
  _is_top="$(git rev-parse --show-toplevel 2>/dev/null)"
  _is_cwd="$(pwd -P)"
  _is_rel="${_is_cwd#"$_is_top"}"
  _is_ex="$_is_gcd/info/exclude"
  mkdir -p "$_is_gcd/info" 2>/dev/null
  if ! grep -qxF -- "$_is_rel/override.cfg" "$_is_ex" 2>/dev/null; then
    if [ -s "$_is_ex" ] && [ -n "$(tail -c 1 "$_is_ex")" ]; then printf '\n' >> "$_is_ex"; fi
    printf '%s\n' "$_is_rel/override.cfg" >> "$_is_ex"
  fi
  _is_keys="$(do_scrub)"; _is_rc=$?
  if [ "$_is_rc" = 3 ]; then
    printf 'studio-test: project.godot carried the per-worktree user:// setting (%s) — removed before the run\n' "$_is_keys" >&2
  fi
  do_sweep "$_is_proj" "$_is_h8"
  return 0
}

# do_leaks DIR — project.godot files (staged or working tree) carrying lanes lines HEAD lacks.
do_leaks() {
  _is_d="${1:-}"
  [ -n "$_is_d" ] && git -C "$_is_d" rev-parse --git-dir >/dev/null 2>&1 || return 1
  _is_list="$(git -C "$_is_d" -c core.quotePath=false ls-files -- project.godot '*/project.godot' 2>/dev/null)" || return 1
  _is_hf="$(mktemp "${TMPDIR:-/tmp}/isolate-leak.XXXXXX")" || return 1
  _is_cf="$_is_hf.cur"; _is_of="$_is_hf.out"; : > "$_is_of"
  printf '%s\n' "$_is_list" | while IFS= read -r _is_p; do
    [ -n "$_is_p" ] || continue
    : > "$_is_hf"
    git -C "$_is_d" show "HEAD:$_is_p" > "$_is_hf" 2>/dev/null
    { git -C "$_is_d" show ":$_is_p" 2>/dev/null; cat "$_is_d/$_is_p" 2>/dev/null; } > "$_is_cf"
    case "$_is_p" in */*) _is_od="${_is_p%/*}/" ;; *) _is_od="" ;; esac
    if is_ours "$_is_d/${_is_od}override.cfg"; then _is_w=all; else _is_w=name; fi
    _is_k="$(lanes_awk list "$_is_hf" "$_is_cf" "$_is_w" | keys_of)"
    if [ -n "$_is_k" ]; then printf '%s: %s\n' "$_is_p" "$_is_k" >> "$_is_of"; fi
  done
  _is_out="$(cat "$_is_of")"
  rm -f "$_is_hf" "$_is_cf" "$_is_of"
  [ -n "$_is_out" ] || return 0
  printf '%s\n' "$_is_out"
  return 3
}

case "${1:-}" in
  '')      do_ensure; exit 0 ;;
  --check) do_check; exit $? ;;
  --scrub) do_scrub; exit $? ;;
  --leaks) do_leaks "${2:-}"; exit $? ;;
  *)       echo "usage: isolate.sh [--check | --scrub | --leaks DIR]" >&2; exit 1 ;;
esac
