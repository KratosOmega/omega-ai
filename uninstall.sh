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
    -h|--help) log "Usage: uninstall.sh <studio> [--target DIR] [--shim-dir DIR] [--purge] [--yes]   (--shim-dir only for installs made before the manifest recorded the shim)"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$STUDIO" ] || die "only one studio at a time"; STUDIO="$1"; shift ;;
  esac
done
[ -n "$STUDIO" ] || die "no studio given"
STUDIO="$(studio_arg "$STUDIO")"

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
# Two assignments, not one nested substitution — see install.sh for why: a
# single `canon_path "$(resolve_studio_target ...)"` masks the inner die
# under `set -e`.
TARGET="$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")"
TARGET="$(canon_path "$TARGET")"
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
# The shim the install recorded wins over the derived path; a manifest from
# the previous installer records none, and --shim-dir is the fallback.
SHIM_PATH="$(manifest_meta "$MANIFEST" shim)"
if [ -n "$SHIM_PATH" ]; then
  guard_target "$(dirname "$SHIM_PATH")" "$REPO_ROOT"
else
  SHIM_PATH="${SHIM_DIR%/}/$SHIM_NAME"
fi
if [ -f "$SHIM_PATH" ] && ! shim_owned "$SHIM_PATH" "$TARGET"; then
  warn "shim $SHIM_PATH launches another config root; keeping it"
  SHIM_PATH=""
fi

if [ "$PURGE" = "1" ]; then
  # Only a root this installer wrote may be purged; the manifest is the proof.
  [ -f "$MANIFEST" ] || die "no manifest at $MANIFEST — not an omega-ai config root, refusing to purge"
  if [ "$ASSUME_YES" != "1" ]; then
    printf 'Delete the entire config root %s, including sessions and history? [y/N] ' "$TARGET"
    read -r reply
    case "$reply" in y|Y) ;; *) die "aborted" ;; esac
  fi
  # rm -rf on a symlink removes the link and keeps the directory: purge the
  # directory the target names, then the link that named it.
  real="$(canon_path "$TARGET/.")"
  rm -rf "$real"
  if [ -L "$TARGET" ]; then rm -f "$TARGET"; fi
  [ -z "$SHIM_PATH" ] || rm -f "$SHIM_PATH"
  log "purged $TARGET"
  exit 0
fi

if [ -f "$MANIFEST" ]; then
  manifest_remove "$MANIFEST" "$TARGET" "$SHIM_PATH"
else
  warn "no manifest at $MANIFEST — removing nothing"
fi

[ -z "$SHIM_PATH" ] || rm -f "$SHIM_PATH"
log "uninstalled $STUDIO from $TARGET (user data kept; use --purge to remove everything)"
