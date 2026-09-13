#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

STUDIO=""
TARGET_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || die "missing value for --target"
      need_value --target "$2"; TARGET_OVERRIDE="$2"; shift 2 ;;
    -h|--help) log "Usage: doctor.sh <studio> [--target DIR]"; exit 0 ;;
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
SHIM_NAME="$(json_field "$STUDIO_DIR/studio.json" shim)"
PLUGIN_JSON="$STUDIO_DIR/.claude-plugin/plugin.json"
REQUIRES="$STUDIO_DIR/requires.txt"
failed=0

log "studio:       $STUDIO"
log "config root:  $TARGET"
[ -d "$TARGET" ] || die "config root does not exist — run install.sh $STUDIO"

if [ -f "$TARGET/CLAUDE.md" ]; then log "CLAUDE.md:    present"; else log "CLAUDE.md:    MISSING"; failed=1; fi
if [ -f "$TARGET/settings.json" ]; then log "settings:     present"; else log "settings:     MISSING"; failed=1; fi

# Plugin content is counted in the studio directory, which is what the shim's
# --plugin-dir loads; nothing under the config root carries it.
count_skills() {
  _n=0
  for _d in "$1"/skills/*/; do
    [ -f "${_d}SKILL.md" ] && _n=$((_n + 1))
  done
  printf '%s' "$_n"
}
count_agents() {
  _n=0
  for _f in "$1"/agents/*.md; do
    [ -f "$_f" ] && _n=$((_n + 1))
  done
  printf '%s' "$_n"
}

if [ -f "$PLUGIN_JSON" ]; then
  pname="$(json_field "$PLUGIN_JSON" name)"
  pver="$(json_field "$PLUGIN_JSON" version)"
  hooks_state="none"
  [ -f "$STUDIO_DIR/hooks/hooks.json" ] && hooks_state="present"
  log "plugin:       ${pname:-?} ${pver:-?}   skills $(count_skills "$STUDIO_DIR")  agents $(count_agents "$STUDIO_DIR")  hooks $hooks_state"
  if [ "$pname" != "$STUDIO" ]; then
    warn "plugin name '$pname' does not match studio '$STUDIO' — skills would load under the wrong prefix"
    failed=1
  fi
else
  warn "no plugin manifest at $PLUGIN_JSON"
  failed=1
fi

# Required plugins: declared in requires.txt, enabled in settings.json, and
# fetched into the config root's plugin cache on first launch.
log "plugins:"
listed=0
required="$(requires_of "$REQUIRES" plugin | tr '\n' ' ')"
for req in $required; do
  listed=1
  rname="${req%@*}"
  rmarket="${req#*@}"
  # -F: a plugin id is data ('.' in it must not match any character).
  if grep -F "\"$req\"" "$TARGET/settings.json" 2>/dev/null | grep -q '"[[:space:]]*:[[:space:]]*true'; then
    cache="$TARGET/plugins/cache/$rmarket/$rname"
    if [ -d "$cache" ]; then
      versions="$(ls -1 "$cache" 2>/dev/null | tr '\n' ' ')"
      log "  $req ok ${versions% }"
    else
      log "  $req enabled, not yet fetched — launch $SHIM_NAME once"
    fi
  else
    log "  $req NOT ENABLED in settings.json"
    failed=1
  fi
done
# Plugins enabled beyond the declared ones are listed too, so the report
# shows everything a session will load.
others="$(grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*true' "$TARGET/settings.json" 2>/dev/null \
  | sed 's/"\([^"]*\)".*/\1/' || true)"
for p in $others; do
  case " $required" in
    *" $p "*) ;;
    *) listed=1; log "  $p (enabled, not declared in requires.txt)" ;;
  esac
done
[ "$listed" = "1" ] || log "  (none)"

log "launch:       $SHIM_NAME"
if command -v "$SHIM_NAME" >/dev/null 2>&1; then
  log "shim on PATH: yes ($(command -v "$SHIM_NAME"))"
else
  log "shim on PATH: no — add your shim directory to PATH"
fi

# The pre-plugin installer linked skills/, agents/, commands/ and hooks/ into
# the root; any symlink under those, or a dangling link directly under the
# root, is that layout left behind — a reinstall removes what its manifest
# recorded.
stale=""
for d in skills agents commands hooks; do
  for l in "$TARGET/$d"/*; do
    [ -L "$l" ] && stale="$stale $d/$(basename "$l")"
  done
done
for l in "$TARGET"/*; do
  if [ -L "$l" ] && [ ! -e "$l" ]; then stale="$stale $(basename "$l")"; fi
done
if [ -n "$stale" ]; then
  warn "stale layout from a previous installer:$stale — run install.sh $STUDIO again"
  failed=1
fi

# Leakage check: nothing inside this root may resolve into ~/.claude, and the
# root itself may not be ~/.claude. Both sides are canonical: ~/.claude may
# itself be a symlink (dotfiles), and a link destination may be spelled with
# '..'. Only symlinks are inspected, to a depth of 3.
home_canon="$(canon_path "${HOME%/}/.")"
home_canon="${home_canon%/}"
claude_canon="$(canon_path "$home_canon/.claude/.")"
# is_leak CANONICAL_PATH — inside ~/.claude, as spelled or as resolved. The
# leading '(' on each pattern is the bash-3.2-in-a-command-substitution
# workaround already used below: an unbalanced ')' inside $(...) is otherwise
# mis-parsed, so every case arm's paren is balanced explicitly.
is_leak() {
  case "$1" in
    ("$home_canon/.claude"|"$home_canon/.claude"/*|"$claude_canon"|"$claude_canon"/*) return 0 ;;
  esac
  return 1
}
leaks="$(find "$TARGET" -maxdepth 3 -type l -print 2>/dev/null | while IFS= read -r link; do
  dest="$(readlink "$link" 2>/dev/null || true)"
  case "$dest" in (/*) ;; (*) dest="$(dirname "$link")/$dest" ;; esac
  if is_leak "$(canon_path "$dest")"; then printf '%s -> %s\n' "$link" "$dest"; fi
done)"
if is_leak "$(canon_path "${TARGET%/}/.")"; then
  leaks="$leaks
config root is inside ~/.claude: $TARGET"
fi
if [ -n "$(printf '%s' "$leaks" | tr -d '[:space:]')" ]; then
  log "leakage:"
  printf '%s\n' "$leaks" | sed 's/^/  /'
  exit 1
fi
log "leakage: none"

if [ "$failed" != "0" ]; then
  log "doctor: FAILED (see warnings above)"
  exit 1
fi
