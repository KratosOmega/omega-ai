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
MANIFEST="$TARGET/.omega-ai-manifest"
# What the shim actually loads: the snapshot in copy mode, the checkout
# otherwise. The manifest header says which; an older manifest says nothing
# and is treated as symlink mode.
MODE="$(manifest_meta "$MANIFEST" mode)"
if [ "$MODE" = "copy" ]; then PLUGIN_DIR="$TARGET/studio"; else PLUGIN_DIR="$STUDIO_DIR"; fi
# The global plugin, as the shim loads it: the snapshot in copy mode, the
# checkout otherwise.
if [ "$MODE" = "copy" ]; then GLOBAL_DIR="$TARGET/global"; else GLOBAL_DIR="$REPO_ROOT/shared/omega"; fi
GLOBAL_JSON="$GLOBAL_DIR/.claude-plugin/plugin.json"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
REQUIRES="$STUDIO_DIR/requires.txt"
RECORDED_SHIM="$(manifest_meta "$MANIFEST" shim)"
failed=0

log "studio:       $STUDIO"
log "config root:  $TARGET"
log "plugin dir:   $PLUGIN_DIR"
[ -d "$TARGET" ] || die "config root does not exist — run install.sh $STUDIO"

if [ -f "$TARGET/CLAUDE.md" ]; then log "CLAUDE.md:    present"; else log "CLAUDE.md:    MISSING"; failed=1; fi
if [ -f "$TARGET/settings.json" ]; then log "settings:     present"; else log "settings:     MISSING"; failed=1; fi

# Plugin content is counted where the shim loads it from (see PLUGIN_DIR).
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
  [ -f "$PLUGIN_DIR/hooks/hooks.json" ] && hooks_state="present"
  log "plugin:       ${pname:-?} ${pver:-?}   skills $(count_skills "$PLUGIN_DIR")  agents $(count_agents "$PLUGIN_DIR")  hooks $hooks_state"
  if [ "$pname" != "$STUDIO" ]; then
    warn "plugin name '$pname' does not match studio '$STUDIO' — skills would load under the wrong prefix"
    failed=1
  fi
else
  warn "no plugin manifest at $PLUGIN_JSON"
  failed=1
fi

if [ -f "$GLOBAL_JSON" ]; then
  gname="$(json_field "$GLOBAL_JSON" name)"
  gver="$(json_field "$GLOBAL_JSON" version)"
  ghooks="none"
  [ -f "$GLOBAL_DIR/hooks/hooks.json" ] && ghooks="present"
  log "global plugin: ${gname:-?} ${gver:-?}   skills $(count_skills "$GLOBAL_DIR")  hooks $ghooks"
  if [ "$gname" != "omega" ]; then
    warn "global plugin name '$gname' is not 'omega' — its skills would load under the wrong prefix"
    failed=1
  fi
  if [ "$ghooks" != "present" ]; then
    warn "global plugin has no hooks/hooks.json — modes would not be injected"
    failed=1
  fi
else
  warn "no global plugin manifest at $GLOBAL_JSON — run install.sh $STUDIO again"
  failed=1
fi

# Required plugins: declared in requires.txt, enabled in settings.json, and
# fetched into the config root's plugin cache on first launch.
log "plugins:"
listed=0
# grep_escape STRING — escape BRE metacharacters so a plugin id (data, not a
# pattern) matches only itself: an unescaped '.' would match any character
# and a two-stage grep (id line, then a ": true" line) would lose adjacency —
# "foo.bar@m": false next to "other@x": true would read as foo.bar@m enabled.
grep_escape() { printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'; }
required="$(requires_of "$REQUIRES" plugin | tr '\n' ' ')"
for req in $required; do
  listed=1
  rname="${req%@*}"
  rmarket="${req#*@}"
  if grep -q "\"$(grep_escape "$req")\"[[:space:]]*:[[:space:]]*true" "$TARGET/settings.json" 2>/dev/null; then
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

# Delegated skills and agents: every skill/agent line in requires.txt must
# exist in the cached plugin. This is what protects the composition decision
# — a renamed upstream skill is reported here, not discovered mid-session.
# Layout: plugins/cache/<marketplace>/<plugin>/<version>/{skills,agents}.
delegation_state() {
  _plugin="${2%%:*}"; _name="${2#*:}"; _state="uncached"
  for _v in "$TARGET"/plugins/cache/*/"$_plugin"/*/; do
    [ -d "$_v" ] || continue
    _state="missing"
    if [ "$1" = "skill" ] && [ -f "$_v/skills/$_name/SKILL.md" ]; then _state="ok"; break; fi
    if [ "$1" = "agent" ] && [ -f "$_v/agents/$_name.md" ]; then _state="ok"; break; fi
  done
  printf '%s\n' "$_state"
}

checked=0
missing_lines=""
tally=""
for req in $(requires_of "$REQUIRES" plugin); do
  pname="${req%@*}"
  total=0; resolved=0
  for kind in skill agent; do
    for ref in $(requires_of "$REQUIRES" "$kind"); do
      [ "${ref%%:*}" = "$pname" ] || continue
      case "$(delegation_state "$kind" "$ref")" in
        ok) total=$((total + 1)); resolved=$((resolved + 1)); checked=1 ;;
        missing) total=$((total + 1)); checked=1
          missing_lines="$missing_lines
  $ref MISSING from the cached plugin" ;;
        uncached) ;;
      esac
    done
  done
  [ "$total" -gt 0 ] && tally="$tally
  $pname: $resolved of $total resolved"
done
if [ "$checked" = "1" ]; then
  log "delegations:$tally"
  if [ -n "$missing_lines" ]; then
    printf '%s\n' "$missing_lines" | sed '/^$/d'
    failed=1
  fi
else
  log "delegations:  not checked — plugins not yet fetched; launch $SHIM_NAME once, then re-run doctor"
fi

# Engine binary, through the studio's own adapter. A missing binary is a
# warning: the studio installs and plans without it; studio-test and
# studio-run exit 2 until it is found.
ENGINE="$(json_field "$STUDIO_DIR/studio.json" engine)"
if [ -n "$ENGINE" ]; then
  RESOLVE="$STUDIO_DIR/engines/$(engine_dir "$ENGINE")/resolve.sh"
  if [ ! -f "$RESOLVE" ]; then
    log "engine:       $ENGINE — no adapter at engines/$(engine_dir "$ENGINE")/"
  elif GODOT="$(sh "$RESOLVE" 2>/dev/null)"; then
    log "engine:       $ENGINE at $GODOT"
  else
    log "engine:       $ENGINE — no binary found (set GODOT_PATH); studio-test and studio-run will exit 2"
  fi

  # MCP registration lands in the config root's .claude.json under
  # CLAUDE_CONFIG_DIR. Read the file rather than `claude mcp list`, which
  # starts every server to health-check it.
  if [ -f "$TARGET/.claude.json" ] && grep -q '"godot"' "$TARGET/.claude.json"; then
    log "mcp:          godot registered"
  else
    log "mcp:          none (optional — reinstall with Node 18+ and a Godot binary to enable godot-mcp)"
  fi
fi

log "launch:       $SHIM_NAME"
# The shim the manifest recorded is the one this install wrote; `command -v`
# would happily report an older shim of the same name on PATH.
if [ -z "$RECORDED_SHIM" ]; then
  log "shim:         not recorded — manifest predates this installer; run install.sh $STUDIO again"
  failed=1
elif [ ! -f "$RECORDED_SHIM" ]; then
  log "shim:         MISSING $RECORDED_SHIM — run install.sh $STUDIO"
  failed=1
elif ! shim_owned "$RECORDED_SHIM" "$TARGET"; then
  log "shim:         stale (launches another root) $RECORDED_SHIM — run install.sh $STUDIO"
  failed=1
elif ! grep -q -- '--plugin-dir' "$RECORDED_SHIM"; then
  log "shim:         stale (no --plugin-dir) $RECORDED_SHIM — run install.sh $STUDIO"
  failed=1
elif ! grep -qF -- '--plugin-dir "$OMEGA_GLOBAL_ROOT"' "$RECORDED_SHIM"; then
  log "shim:         stale (no global plugin) $RECORDED_SHIM — run install.sh $STUDIO"
  failed=1
else
  log "shim:         ok $RECORDED_SHIM"
  shim_dir="$(dirname "$RECORDED_SHIM")"
  case ":$PATH:" in
    *":$shim_dir:"*) log "shim on PATH: yes" ;;
    *) log "shim on PATH: no — add $shim_dir to PATH" ;;
  esac
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
# An MCP server registered outside the config root would be a leak into the
# user's general setup. The check cannot tell our registration from one the
# user made on purpose, so it warns and names the file rather than failing.
if [ -f "$HOME/.claude.json" ] && grep -q 'godot-mcp' "$HOME/.claude.json" 2>/dev/null; then
  warn "~/.claude.json registers godot-mcp — if this studio's installer did that, it leaked; if it is your own setup, ignore this"
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
