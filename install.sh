#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: install.sh <profile> [options]

Install a profile from this repository into its own Claude Code config root,
leaving ~/.claude untouched.

Options:
  --mode symlink|copy   symlink (default) keeps the repo as source of truth;
                        copy takes a frozen snapshot
  --target DIR          override the target from profile.json
  --shim-dir DIR        where to write the launch shim (default ~/.local/bin)
  --dry-run             print every action, change nothing
  -h, --help            show this help

Profiles: see profiles/ in this repository.
USAGE
}

PROFILE=""
MODE="symlink"
TARGET_OVERRIDE=""
SHIM_DIR="$HOME/.local/bin"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --target) TARGET_OVERRIDE="${2:-}"; shift 2 ;;
    --shim-dir) SHIM_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$PROFILE" ] || die "only one profile at a time"; PROFILE="$1"; shift ;;
  esac
done
export DRY_RUN

[ -n "$PROFILE" ] || { usage; die "no profile given"; }
case "$MODE" in symlink|copy) ;; *) die "unknown mode: $MODE" ;; esac

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
[ -d "$PROFILE_DIR" ] || die "unknown profile: $PROFILE"
[ -f "$PROFILE_DIR/profile.json" ] || die "profile has no profile.json: $PROFILE"

if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$(expand_path "$TARGET_OVERRIDE")"
else
  TARGET="$(expand_path "$(json_field "$PROFILE_DIR/profile.json" target)")"
fi
SHIM_NAME="$(json_field "$PROFILE_DIR/profile.json" shim)"
[ -n "$SHIM_NAME" ] || die "profile.json has no shim name"

guard_target "$TARGET" "$REPO_ROOT"

log "profile:  $PROFILE"
log "target:   $TARGET"
log "mode:     $MODE"
log "shim:     $SHIM_DIR/$SHIM_NAME"
if [ "$DRY_RUN" = "1" ]; then log "(dry run — nothing will change)"; fi

run mkdir -p "$TARGET"
