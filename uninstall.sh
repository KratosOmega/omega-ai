#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

PROFILE=""
TARGET_OVERRIDE=""
SHIM_DIR="$HOME/.local/bin"
PURGE=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || die "missing value for --target"
      need_value --target "$2"; TARGET_OVERRIDE="$2"; shift 2 ;;
    --shim-dir)
      [ $# -ge 2 ] || die "missing value for --shim-dir"
      need_value --shim-dir "$2"; SHIM_DIR="$2"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) log "Usage: uninstall.sh <profile> [--target DIR] [--shim-dir DIR] [--purge] [--yes]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$PROFILE" ] || die "only one profile at a time"; PROFILE="$1"; shift ;;
  esac
done
[ -n "$PROFILE" ] || die "no profile given"

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
TARGET="$(resolve_profile_target "$PROFILE_DIR" "$TARGET_OVERRIDE")"
SHIM_DIR="$(expand_path "$SHIM_DIR")"
SHIM_NAME="$(json_field "$PROFILE_DIR/profile.json" shim)"

# Guard both paths this script deletes from.
guard_target "$TARGET" "$REPO_ROOT"
guard_target "$SHIM_DIR" "$REPO_ROOT"
[ -d "$TARGET" ] || die "nothing installed at $TARGET"

MANIFEST="$TARGET/.omega-ai-manifest"
SHIM_PATH="${SHIM_DIR%/}/$SHIM_NAME"

if [ "$PURGE" = "1" ]; then
  if [ "$ASSUME_YES" != "1" ]; then
    printf 'Delete the entire config root %s, including sessions and history? [y/N] ' "$TARGET"
    read -r reply
    case "$reply" in y|Y) ;; *) die "aborted" ;; esac
  fi
  rm -rf "$TARGET"
  if [ -n "$SHIM_NAME" ]; then rm -f "$SHIM_PATH"; fi
  log "purged $TARGET"
  exit 0
fi

if [ -f "$MANIFEST" ]; then
  # The manifest lives inside a user-writable root and can be stale from an
  # install that used a different --target or --shim-dir. Delete only what this
  # invocation is responsible for: entries under TARGET, plus its own shim.
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    in_scope=0
    case "$entry" in
      "${TARGET%/}"/*) in_scope=1 ;;
    esac
    if [ -n "$SHIM_NAME" ] && [ "$entry" = "$SHIM_PATH" ]; then in_scope=1; fi
    if [ "$in_scope" != "1" ]; then
      warn "skipping manifest entry outside $TARGET: $entry"
      continue
    fi
    rm -rf "$entry"
  done < "$MANIFEST"
  rm -f "$MANIFEST"
else
  warn "no manifest at $MANIFEST — removing nothing"
fi

if [ -n "$SHIM_NAME" ]; then rm -f "$SHIM_PATH"; fi
log "uninstalled $PROFILE from $TARGET (user data kept; use --purge to remove everything)"
