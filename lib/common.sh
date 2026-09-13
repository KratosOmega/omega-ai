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

# studio_arg NAME — the studio name as typed, with a trailing slash stripped
# (tab completion adds one; it used to install fine and then fail the
# doctor's name check). A name with a slash inside it, or an empty one, dies.
studio_arg() {
  _s="${1%/}"
  [ -n "$_s" ] || die "no studio given"
  case "$_s" in */*) die "studio must be a name, not a path: $1" ;; esac
  printf '%s\n' "$_s"
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
#
# The target is checked by where it *points*: canon_path leaves a final
# symlink undereferenced, so the "/." suffix makes it an ancestor and resolves
# it physically. Without that, `--target ~/evil` with `evil -> studios/general`
# passes and a wet install renders the studio's CLAUDE.md onto itself. The
# dereferenced form is used for this comparison only — callers keep the path
# as given, so uninstall still deletes a link and never what it points at. A
# target that does not exist yet has nothing to dereference and passes as
# before. $HOME and the repository root get the same treatment so a symlinked
# spelling of either side cannot make the comparison miss.
#
# ~/.claude is refused both as spelled and as resolved: when it is itself a
# symlink (dotfiles-style ~/.claude -> ~/dotfiles/claude), the dereferenced
# target names the destination, which the textual pattern never matches — so
# the destination is refused too. The textual pattern stays for a ~/.claude
# that does not exist yet. $_home is stripped of a trailing slash after
# canonicalizing so HOME=/ yields "/.claude", never a "//.claude" that
# matches nothing.
guard_target() {
  _raw="${1%/}"
  [ -n "$_raw" ] || die "install target is empty"
  _t="$(canon_path "$_raw/.")"
  _repo="$(canon_path "${2%/}/.")"
  _home="$(canon_path "${HOME%/}/.")"
  _home="${_home%/}"
  _claude="$(canon_path "$_home/.claude/.")"
  [ "$_t" != "$_home" ] || die "refusing to install into your home directory"
  case "$_t" in
    "$_home/.claude"|"$_home/.claude"/*|"$_claude"|"$_claude"/*)
      die "refusing to install into ~/.claude — that is your existing setup" ;;
  esac
  case "$_t" in
    "$_repo"|"$_repo"/*) die "refusing to install into the repository itself: $_t" ;;
  esac
  return 0
}

# resolve_studio_target STUDIO_DIR [OVERRIDE] — print the studio's config
# root. OVERRIDE wins when given; otherwise studio.json's target is used.
# Dies when the studio, its studio.json, or the resolved target is missing.
resolve_studio_target() {
  _sdir="${1%/}"
  _override="${2:-}"
  _sname="$(basename "$_sdir")"
  [ -d "$_sdir" ] || die "unknown studio: $_sname"
  [ -f "$_sdir/studio.json" ] || die "studio has no studio.json: $_sname"
  if [ -n "$_override" ]; then
    _resolved="$(expand_path "$_override")"
  else
    _resolved="$(expand_path "$(json_field "$_sdir/studio.json" target)")"
  fi
  [ -n "$_resolved" ] || die "studio.json declares no target: $_sname"
  printf '%s\n' "$_resolved"
}

# requires_of FILE KIND — print the names a requires.txt declares for KIND
# (plugin, skill, or agent), one per line. A missing file prints nothing, so
# a studio with no dependencies needs only an empty requires.txt.
requires_of() {
  [ -f "$1" ] || return 0
  awk -v kind="$2" '$1 == kind { print $2 }' "$1"
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

# manifest_meta MANIFEST KEY — the value of the header line "# KEY=value"
# the installer writes (mode, shim); empty when the manifest or the key is
# absent. One key per line, so a shim path with a space survives.
manifest_meta() {
  [ -f "$1" ] || return 0
  sed -n "s/^# $2=//p" "$1" | head -n 1
}

# shim_owned SHIM TARGET — SHIM launches Claude Code against TARGET. Two
# studios can share a shim directory and a root can be reinstalled at another
# target; a shim that points elsewhere is not this root's to delete.
shim_owned() {
  [ -f "$1" ] && grep -qF "CLAUDE_CONFIG_DIR=\"$2\"" "$1"
}

# manifest_remove MANIFEST TARGET SHIM_PATH — delete every path the manifest
# records that lies under TARGET, plus the shim at SHIM_PATH, then delete the
# manifest itself. A missing manifest is a no-op.
#
# Header lines ("# key=value") are metadata, never paths.
#
# The manifest lives inside a user-writable root and can be stale from an
# install that used a different --target or --shim-dir, so entries outside
# TARGET are skipped with a warning. Scope is decided on the canonical form of
# both sides: a '..' spelling such as "$TARGET/../.claude/settings.json"
# matches "$TARGET/*" textually while pointing outside the root entirely. The
# removal itself uses the entry exactly as written, so a path the kernel
# cannot resolve deletes nothing rather than deleting the folded path instead.
# SHIM_PATH is canonicalized for the same reason: on macOS a shim under
# $TMPDIR is spelled /var/... while its recorded entry folds to /private/var/...
#
# The scope root is resolved physically ("/." makes its final component an
# ancestor for canon_path): entries under a symlinked root (`--target ~/link`)
# canonicalize through the link to the real directory, so the scope must be
# the real directory too — otherwise every entry looks outside scope and the
# cleanup is a silent no-op. A root that does not exist yet stays textual.
#
# An entry with a trailing slash is skipped outright: `rm -rf link/` follows
# a symlink and deletes the linked directory's contents (leaving the link),
# so a crafted "<target>/memory/sub/" would delete through a link into the
# repository while canon_path still judges it in scope. The installer never
# records a trailing slash.
manifest_remove() {
  _m="$1"; _scope_root="$2"; _shim="$3"
  [ -f "$_m" ] || return 0
  _scope_canon="$(canon_path "${_scope_root%/}/.")"
  _shim_canon="$(canon_path "$_shim")"
  while IFS= read -r _entry; do
    [ -n "$_entry" ] || continue
    case "$_entry" in '#'*) continue ;; esac
    case "$_entry" in
      */) warn "skipping manifest entry with trailing slash: $_entry"; continue ;;
    esac
    _entry_canon="$(canon_path "$_entry")"
    _in_scope=0
    case "$_entry_canon" in
      "${_scope_canon%/}"/*) _in_scope=1 ;;
    esac
    if [ -n "$_shim_canon" ] && [ "$_entry_canon" = "$_shim_canon" ]; then _in_scope=1; fi
    if [ "$_in_scope" != "1" ]; then
      warn "skipping manifest entry outside $_scope_root: $_entry"
      continue
    fi
    rm -rf "$_entry"
  done < "$_m"
  rm -f "$_m"
}
