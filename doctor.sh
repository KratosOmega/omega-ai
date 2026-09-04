#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

PROFILE=""
TARGET_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) log "Usage: doctor.sh <profile> [--target DIR]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) PROFILE="$1"; shift ;;
  esac
done
[ -n "$PROFILE" ] || die "no profile given"

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
[ -d "$PROFILE_DIR" ] || die "unknown profile: $PROFILE"

if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$(expand_path "$TARGET_OVERRIDE")"
else
  TARGET="$(expand_path "$(json_field "$PROFILE_DIR/profile.json" target)")"
fi
SHIM_NAME="$(json_field "$PROFILE_DIR/profile.json" shim)"

log "profile:      $PROFILE"
log "config root:  $TARGET"
[ -d "$TARGET" ] || die "config root does not exist — run install.sh $PROFILE"

count() { [ -d "$1" ] && ls -1 "$1" 2>/dev/null | wc -l | tr -d ' ' || printf '0'; }
log "CLAUDE.md:    $([ -f "$TARGET/CLAUDE.md" ] && printf 'present' || printf 'MISSING')"
log "settings:     $([ -f "$TARGET/settings.json" ] && printf 'present' || printf 'MISSING')"
log "agents:       $(count "$TARGET/agents")"
log "skills:       $(count "$TARGET/skills")"
log "commands:     $(count "$TARGET/commands")"
log "hooks:        $(count "$TARGET/hooks")"

if [ -f "$TARGET/settings.json" ]; then
  log "plugins:"
  grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*true' "$TARGET/settings.json" 2>/dev/null \
    | sed 's/^/  /' || log "  (none)"
fi

log "launch:       $SHIM_NAME"
if command -v "$SHIM_NAME" >/dev/null 2>&1; then
  log "shim on PATH: yes ($(command -v "$SHIM_NAME"))"
else
  log "shim on PATH: no — add your shim directory to PATH"
fi

# Leakage check: nothing inside this root may resolve into ~/.claude.
leaks="$(find "$TARGET" -maxdepth 3 -type l -exec readlink {} \; 2>/dev/null \
  | grep -F "$HOME/.claude/" || true)"
case "${TARGET%/}" in
  "${HOME%/}/.claude") leaks="$leaks
target is ~/.claude" ;;
esac
if [ -n "$(printf '%s' "$leaks" | tr -d '[:space:]')" ]; then
  log "leakage:"
  printf '%s\n' "$leaks" | sed 's/^/  /'
  exit 1
fi
log "leakage: none"
