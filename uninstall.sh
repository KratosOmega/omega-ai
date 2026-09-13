#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

STUDIO=""
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
    -h|--help) log "Usage: uninstall.sh <studio> [--target DIR] [--shim-dir DIR] [--purge] [--yes]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$STUDIO" ] || die "only one studio at a time"; STUDIO="$1"; shift ;;
  esac
done
[ -n "$STUDIO" ] || die "no studio given"
STUDIO="$(studio_arg "$STUDIO")"

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
TARGET="$(canon_path "$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")")"
SHIM_DIR="$(canon_path "$(expand_path "$SHIM_DIR")")"
SHIM_NAME="$(json_field "$STUDIO_DIR/studio.json" shim)"
# An empty name would make SHIM_PATH the shim directory itself, which
# manifest_remove would then treat as a removable entry.
[ -n "$SHIM_NAME" ] || die "studio.json has no shim name"

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
  rm -f "$SHIM_PATH"
  log "purged $TARGET"
  exit 0
fi

if [ -f "$MANIFEST" ]; then
  manifest_remove "$MANIFEST" "$TARGET" "$SHIM_PATH"
else
  warn "no manifest at $MANIFEST — removing nothing"
fi

rm -f "$SHIM_PATH"
log "uninstalled $STUDIO from $TARGET (user data kept; use --purge to remove everything)"
