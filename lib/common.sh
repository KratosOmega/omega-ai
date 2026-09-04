#!/bin/sh
# Shared helpers for omega-ai scripts. Sourced, never executed.

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# run CMD... — execute, or print the command when DRY_RUN=1.
run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf 'DRY  %s\n' "$*" >&2
  else
    "$@"
  fi
}

# need_value FLAG VALUE — reject an option supplied without a usable value.
# An empty value is an error, never a silent fall back to a default.
need_value() {
  [ -n "${2:-}" ] || die "missing value for $1"
}

# json_field FILE KEY — value of a flat JSON string key; empty when absent.
json_field() {
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

# expand_path PATH — expand a leading tilde.
expand_path() {
  case "$1" in
    '~')   printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *)     printf '%s\n' "$1" ;;
  esac
}

# canon_path PATH — print PATH in canonical absolute form. A relative PATH is
# resolved against the current directory; '.' and '..' segments are folded, and
# symlinked *ancestors* are resolved physically. Prints an empty line for empty
# input. Creates nothing.
#
# Why not realpath / readlink -f: neither is guaranteed on macOS, and both
# refuse a path that does not exist yet — which is the normal case here, since
# the install target is usually about to be created. Walking the path one
# component at a time resolves the part that does exist with `cd -P`/`pwd -P`
# (the only POSIX way to dereference a symlinked directory) and folds the
# missing tail textually, which is exactly how the kernel would resolve it.
#
# The final component is deliberately left undereferenced, so a path naming a
# symlink still names the symlink and not its destination — uninstall.sh must
# delete an installed link, never whatever the link points at.
canon_path() {
  _cp_in="$1"
  if [ -z "$_cp_in" ]; then
    printf '%s\n' ""
    return 0
  fi
  case "$_cp_in" in
    /*) ;;
    *)  _cp_in="$(pwd -P)/$_cp_in" ;;
  esac
  _cp_out=""
  _cp_rest="$_cp_in"
  while [ -n "$_cp_rest" ]; do
    _cp_seg="${_cp_rest%%/*}"
    if [ "$_cp_seg" = "$_cp_rest" ]; then _cp_rest=""; else _cp_rest="${_cp_rest#*/}"; fi
    case "$_cp_seg" in
      ''|'.')
        ;;
      '..')
        # _cp_out is already physical, so popping it textually is correct.
        _cp_out="${_cp_out%/*}" ;;
      *)
        _cp_out="$_cp_out/$_cp_seg"
        if [ -n "$_cp_rest" ] && [ -L "$_cp_out" ]; then
          _cp_phys="$(CDPATH='' cd -P "$_cp_out" 2>/dev/null && pwd -P)" || _cp_phys=""
          if [ -n "$_cp_phys" ]; then _cp_out="${_cp_phys%/}"; fi
        fi ;;
    esac
  done
  printf '%s\n' "${_cp_out:-/}"
}

# guard_target PATH REPO_ROOT — refuse to create anything anywhere dangerous.
# Used for the config root and for the shim directory: both are paths the
# installer creates and the uninstaller deletes from.
#
# Every path is canonicalized first. Without that, a '..' spelling such as
# ~/x/../.claude matches none of the patterns below and walks straight into the
# user's existing setup. $HOME and the repository root are canonicalized for the
# same reason: comparing a resolved path against an unresolved one is a
# false negative whenever either side crosses a symlink.
guard_target() {
  _t="$(canon_path "${1%/}")"
  _repo="$(canon_path "${2%/}")"
  _home="$(canon_path "${HOME%/}")"
  [ -n "$_t" ] || die "install target is empty"
  [ "$_t" != "$_home" ] || die "refusing to install into your home directory"
  case "$_t" in
    "$_home/.claude"|"$_home/.claude"/*)
      die "refusing to install into ~/.claude — that is your existing setup" ;;
  esac
  case "$_t" in
    "$_repo"|"$_repo"/*) die "refusing to install into the repository itself: $_t" ;;
  esac
  return 0
}

# resolve_profile_target PROFILE_DIR [OVERRIDE] — print the profile's config
# root. OVERRIDE wins when given; otherwise profile.json's target is used.
# Dies when the profile, its profile.json, or the resolved target is missing.
resolve_profile_target() {
  _pdir="${1%/}"
  _override="${2:-}"
  _pname="$(basename "$_pdir")"
  [ -d "$_pdir" ] || die "unknown profile: $_pname"
  [ -f "$_pdir/profile.json" ] || die "profile has no profile.json: $_pname"
  if [ -n "$_override" ]; then
    _resolved="$(expand_path "$_override")"
  else
    _resolved="$(expand_path "$(json_field "$_pdir/profile.json" target)")"
  fi
  [ -n "$_resolved" ] || die "profile.json declares no target: $_pname"
  printf '%s\n' "$_resolved"
}

# install_entries SRC_DIR DEST_DIR MODE — install each child of SRC_DIR into
# DEST_DIR, replacing same-named entries. Prints each destination path.
install_entries() {
  _src="$1"; _dest="$2"; _mode="$3"
  [ -d "$_src" ] || return 0
  run mkdir -p "$_dest"
  for _entry in "$_src"/*; do
    [ -e "$_entry" ] || continue
    _name="$(basename "$_entry")"
    case "$_name" in .gitkeep) continue ;; esac
    run rm -rf "$_dest/$_name"
    if [ "$_mode" = "copy" ]; then
      run cp -R "$_entry" "$_dest/$_name"
    else
      run ln -s "$_entry" "$_dest/$_name"
    fi
    printf '%s\n' "$_dest/$_name"
  done
}

# manifest_add MANIFEST PATH — record an installed path, one per line.
manifest_add() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    return 0
  fi
  printf '%s\n' "$2" >> "$1"
}
