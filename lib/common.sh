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

# guard_target TARGET REPO_ROOT — refuse to install anywhere dangerous.
guard_target() {
  _t="${1%/}"
  _repo="${2%/}"
  [ -n "$_t" ] || die "install target is empty"
  [ "$_t" != "${HOME%/}" ] || die "refusing to install into your home directory"
  [ "$_t" != "${HOME%/}/.claude" ] || die "refusing to install into ~/.claude — that is your existing setup"
  case "$_t" in
    "$_repo"|"$_repo"/*) die "refusing to install into the repository itself: $_t" ;;
  esac
  return 0
}
