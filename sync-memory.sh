#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

PROFILE=""
TARGET_OVERRIDE=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_OVERRIDE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) log "Usage: sync-memory.sh <profile> [--target DIR] [--dry-run]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) PROFILE="$1"; shift ;;
  esac
done
export DRY_RUN
[ -n "$PROFILE" ] || die "no profile given"

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
[ -d "$PROFILE_DIR" ] || die "unknown profile: $PROFILE"

if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$(expand_path "$TARGET_OVERRIDE")"
else
  TARGET="$(expand_path "$(json_field "$PROFILE_DIR/profile.json" target)")"
fi

SRC="$TARGET/memory"
DEST="$PROFILE_DIR/memory"
[ -d "$SRC" ] || die "no memory directory at $SRC"

# -type f skips symlinks, which already point back into this repository.
find "$SRC" -type f -print | while IFS= read -r file; do
  rel="${file#"$SRC"/}"
  run mkdir -p "$DEST/$(dirname "$rel")"
  run cp "$file" "$DEST/$rel"
  log "synced $rel"
done

log "memory sync complete: $SRC -> $DEST"
