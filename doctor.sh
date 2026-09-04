#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

PROFILE=""
TARGET_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || die "missing value for --target"
      need_value --target "$2"; TARGET_OVERRIDE="$2"; shift 2 ;;
    -h|--help) log "Usage: doctor.sh <profile> [--target DIR]"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$PROFILE" ] || die "only one profile at a time"; PROFILE="$1"; shift ;;
  esac
done
[ -n "$PROFILE" ] || die "no profile given"

PROFILE_DIR="$REPO_ROOT/profiles/$PROFILE"
TARGET="$(resolve_profile_target "$PROFILE_DIR" "$TARGET_OVERRIDE")"
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
  plugins="$(grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*true' "$TARGET/settings.json" 2>/dev/null || true)"
  if [ -n "$plugins" ]; then
    printf '%s\n' "$plugins" | sed 's/^/  /'
  else
    log "  (none)"
  fi
fi

log "launch:       $SHIM_NAME"
if command -v "$SHIM_NAME" >/dev/null 2>&1; then
  log "shim on PATH: yes ($(command -v "$SHIM_NAME"))"
else
  log "shim on PATH: no — add your shim directory to PATH"
fi

# Leakage check: nothing inside this root may resolve into ~/.claude, and the
# root itself may not be ~/.claude. Both the exact path and any descendant
# count as a leak. Known limits: only symlinks are inspected, to a depth of 3.
# The case patterns below carry a leading '(' because bash 3.2 mis-parses an
# unbalanced ')' inside a command substitution; POSIX allows the open paren.
leaks="$(find "$TARGET" -maxdepth 3 -type l -print 2>/dev/null | while IFS= read -r link; do
  dest="$(readlink "$link" 2>/dev/null || true)"
  case "${dest%/}" in
    ("${HOME%/}/.claude"|"${HOME%/}/.claude"/*) printf '%s -> %s\n' "$link" "$dest" ;;
  esac
done)"
case "${TARGET%/}" in
  "${HOME%/}/.claude"|"${HOME%/}/.claude"/*) leaks="$leaks
config root is inside ~/.claude: $TARGET" ;;
esac
if [ -n "$(printf '%s' "$leaks" | tr -d '[:space:]')" ]; then
  log "leakage:"
  printf '%s\n' "$leaks" | sed 's/^/  /'
  exit 1
fi
log "leakage: none"
