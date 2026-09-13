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

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
TARGET="$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")"
SHIM_DIR="$(canon_path "$(expand_path "$SHIM_DIR")")"
SHIM_NAME="$(json_field "$STUDIO_DIR/studio.json" shim)"

# Guard both paths this script deletes from.
guard_target "$TARGET" "$REPO_ROOT"
guard_target "$SHIM_DIR" "$REPO_ROOT"
[ -d "$TARGET" ] || die "nothing installed at $TARGET"

MANIFEST="$TARGET/.omega-ai-manifest"
SHIM_PATH="${SHIM_DIR%/}/$SHIM_NAME"
TARGET_CANON="$(canon_path "$TARGET")"

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
    # Scope is decided on the canonical form of both sides: a '..' spelling
    # such as "$TARGET/../.claude/settings.json" matches "$TARGET/*" textually
    # while pointing outside the config root entirely. The removal below still
    # uses the entry exactly as written, so a path the kernel cannot resolve
    # deletes nothing rather than deleting the folded path instead.
    entry_canon="$(canon_path "$entry")"
    in_scope=0
    case "$entry_canon" in
      "${TARGET_CANON%/}"/*) in_scope=1 ;;
    esac
    if [ -n "$SHIM_NAME" ] && [ "$entry_canon" = "$SHIM_PATH" ]; then in_scope=1; fi
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
log "uninstalled $STUDIO from $TARGET (user data kept; use --purge to remove everything)"
