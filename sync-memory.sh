#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

STUDIO=""
TARGET_OVERRIDE=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || die "missing value for --target"
      need_value --target "$2"; TARGET_OVERRIDE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) log "Usage: sync-memory.sh <studio> [--target DIR] [--dry-run]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$STUDIO" ] || die "only one studio at a time"; STUDIO="$1"; shift ;;
  esac
done
export DRY_RUN
[ -n "$STUDIO" ] || die "no studio given"
STUDIO="$(studio_arg "$STUDIO")"

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
TARGET="$(canon_path "$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")")"

SRC="$TARGET/memory"
DEST="$STUDIO_DIR/memory"
[ -d "$SRC" ] || die "no memory directory at $SRC"

# -type f skips symlinks, which already point back into this repository.
find "$SRC" -type f -print | while IFS= read -r file; do
  rel="${file#"$SRC"/}"
  run mkdir -p "$DEST/$(dirname "$rel")"
  run cp "$file" "$DEST/$rel"
  log "synced $rel"
done

log "memory sync complete: $SRC -> $DEST"
