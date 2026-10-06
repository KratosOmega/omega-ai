#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: install.sh <studio> [options]

Install a studio from this repository into its own Claude Code config root,
leaving ~/.claude untouched. The studio's skills, agents and hooks load as a
plugin straight from the studio directory, and the omega global plugin
(shared/omega) loads beside it; only CLAUDE.md, settings.json, memory/ and
bin/ are placed in the config root.

Options:
  --mode symlink|copy   symlink (default) keeps the repo as source of truth;
                        copy takes a frozen snapshot: the studio is copied to
                        <target>/studio and the omega global plugin to
                        <target>/global, and both are loaded from there
  --target DIR          override the target from studio.json
  --shim-dir DIR        where to write the launch shim (default ~/.local/bin)
  --no-mcp              never register an MCP server for this studio
  --dry-run             print every action, change nothing
  -h, --help            show this help

A reinstall keeps every top-level settings.json key the studio's template
does not define (agentPushNotifEnabled, say); the template's own keys take
its values. The merge needs python3; without it the template is installed
as is and the previous file is backed up.

Environment:
  OMEGA_INSTALL_PYTHON  the python3 for that merge (default: python3 on
                        PATH, else /usr/bin/python3)

Studios: see studios/ in this repository.
USAGE
}

# settings_python — print a python3 that actually runs (3.7+: ordered dicts);
# return 1 when there is none. OMEGA_INSTALL_PYTHON names one instead (tests
# point it at a missing or broken interpreter). macOS's /usr/bin/python3 can
# be a stub that only offers to install the developer tools, hence a probe
# that runs it rather than a presence check.
settings_python() {
  if [ -n "${OMEGA_INSTALL_PYTHON:-}" ]; then
    _py="$OMEGA_INSTALL_PYTHON"
  else
    _py="$(command -v python3 2>/dev/null || true)"
    [ -n "$_py" ] || _py=/usr/bin/python3
  fi
  "$_py" -c 'import sys; sys.exit(sys.version_info < (3, 7))' >/dev/null 2>&1 || return 1
  printf '%s\n' "$_py"
}

# settings_merge PY TEMPLATE EXISTING — the reinstall's settings.json (#53):
# the template's top-level keys with the template's values, then every other
# top-level key of EXISTING, in its order. Prints "same" (EXISTING already
# holds exactly that content) or "differs", then the kept keys ", "-joined
# (empty when none), then the merged document. Exit 3: EXISTING is not a
# JSON object; 4: TEMPLATE is not. A top-level function, never a heredoc
# inside $( ): bash 3.2 mis-parses that.
settings_merge() {
  "$1" - "$2" "$3" <<'PY'
import json, sys

def load(path, code):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError):
        sys.exit(code)
    if not isinstance(doc, dict):
        sys.exit(code)
    return doc

template = load(sys.argv[1], 4)
existing = load(sys.argv[2], 3)
merged = dict(template)
kept = [k for k in existing if k not in template]
for k in kept:
    merged[k] = existing[k]
canon = lambda d: json.dumps(d, sort_keys=True)
out = "same" if canon(existing) == canon(merged) else "differs"
out += "\n" + ", ".join(json.dumps(k)[1:-1] for k in kept)
out += "\n" + json.dumps(merged, indent=2, ensure_ascii=False) + "\n"
sys.stdout.buffer.write(out.encode("utf-8"))
PY
}

STUDIO=""
MODE="symlink"
TARGET_OVERRIDE=""
SHIM_DIR="$HOME/.local/bin"
NO_MCP=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --mode)
      [ $# -ge 2 ] || die "missing value for --mode"
      need_value --mode "$2"; MODE="$2"; shift 2 ;;
    --target)
      [ $# -ge 2 ] || die "missing value for --target"
      need_value --target "$2"; TARGET_OVERRIDE="$2"; shift 2 ;;
    --shim-dir)
      [ $# -ge 2 ] || die "missing value for --shim-dir"
      need_value --shim-dir "$2"; SHIM_DIR="$2"; shift 2 ;;
    --no-mcp) NO_MCP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$STUDIO" ] || die "only one studio at a time"; STUDIO="$1"; shift ;;
  esac
done
export DRY_RUN

[ -n "$STUDIO" ] || { usage; die "no studio given"; }
STUDIO="$(studio_arg "$STUDIO")"
case "$MODE" in symlink|copy) ;; *) die "unknown mode: $MODE" ;; esac

STUDIO_DIR="$REPO_ROOT/studios/$STUDIO"
# The global plugin every studio loads beside its own.
GLOBAL_SRC="$REPO_ROOT/shared/omega"
# Two assignments, not one nested substitution: canon_path "$(resolve_studio_target ...)"
# ran canon_path on an empty string when resolve_studio_target died, and
# canon_path succeeding on that empty string satisfied `set -e`, silently
# swallowing the die and leaving TARGET="". Split so resolve_studio_target's
# own exit status is what `set -e` sees.
#
# The target is canonical so the shim and the manifest carry a path that is
# valid from any directory; a relative --target used to be recorded as typed.
TARGET="$(resolve_studio_target "$STUDIO_DIR" "$TARGET_OVERRIDE")"
TARGET="$(canon_path "$TARGET")"
SHIM_DIR="$(canon_path "$(expand_path "$SHIM_DIR")")"
SHIM_NAME="$(json_field "$STUDIO_DIR/studio.json" shim)"
[ -n "$SHIM_NAME" ] || die "studio.json has no shim name"
[ -f "$STUDIO_DIR/.claude-plugin/plugin.json" ] || die "studio has no .claude-plugin/plugin.json: $STUDIO"

# Everything the install reads is checked here, before the previous install
# is removed: a reinstall that dies half-way must leave the old one in place.
[ -f "$STUDIO_DIR/CLAUDE.md" ] || die "studio has no CLAUDE.md: $STUDIO"
[ -f "$STUDIO_DIR/settings.json" ] || die "studio has no settings.json: $STUDIO"
[ -f "$GLOBAL_SRC/.claude-plugin/plugin.json" ] || die "repository has no global plugin at shared/omega"

# Both paths this script creates in — and the uninstaller deletes from — are
# guarded before anything is written.
guard_target "$TARGET" "$REPO_ROOT"
guard_target "$SHIM_DIR" "$REPO_ROOT"

# The plugin directories Claude Code loads: the studio and the omega global
# plugin. Symlink mode points both at the checkout so edits are live; copy
# mode snapshots both under the config root so the install has no dependency
# on this checkout.
if [ "$MODE" = "copy" ]; then
  PLUGIN_DIR="$TARGET/studio"
  # Not <target>/omega: that is the runtime mode directory's parent
  # (${CLAUDE_CONFIG_DIR:-...}/omega/modes/<session_id>), and this install's
  # `rm -rf "$GLOBAL_DIR"` below would delete every live session's mode file
  # on a reinstall.
  GLOBAL_DIR="$TARGET/global"
else
  PLUGIN_DIR="$STUDIO_DIR"
  GLOBAL_DIR="$GLOBAL_SRC"
fi
SHIM_PATH="$SHIM_DIR/$SHIM_NAME"

log "studio:   $STUDIO"
log "target:   $TARGET"
log "mode:     $MODE"
log "plugin:   $PLUGIN_DIR"
log "global:   $GLOBAL_DIR"
log "shim:     $SHIM_PATH"
if [ "$DRY_RUN" = "1" ]; then log "(dry run — nothing will change)"; fi

run mkdir -p "$TARGET"

# A previous install of this studio leaves a manifest behind. Remove what it
# recorded before writing anything, so a reinstall never leaves stale links
# from an older layout beside the new one.
MANIFEST="$TARGET/.omega-ai-manifest"
# settings.json is the one installed file Claude Code mutates in-session, and
# the previous manifest records it, so what this install writes there is
# decided now, before the old entries are removed (#53). The template's
# top-level keys take its values; every other top-level key already in the
# file is kept. A link there is replaced, never merged from: its keys belong
# to whatever it points at (~/.claude, say). A copy is backed up only when
# something would be lost — with a merge, when a template-owned value
# changes; otherwise, as before, when the bytes differ from the template.
# Bytes identical to the template need no python: nothing to keep.
SETTINGS="$TARGET/settings.json"
SETTINGS_DOC=""   # the merged document; empty: install the template as is
SETTINGS_KEPT=""  # the kept keys, ", "-joined
SETTINGS_WHY=""   # why no merge happened, for the fallback warning
SETTINGS_BAK=""
SETTINGS_SAME=1
[ ! -f "$SETTINGS" ] || cmp -s "$STUDIO_DIR/settings.json" "$SETTINGS" || SETTINGS_SAME=0
if [ "$SETTINGS_SAME" = 0 ] && [ ! -L "$SETTINGS" ]; then
  if ! _py="$(settings_python)"; then
    SETTINGS_WHY="python3 not found or not working"
  else
    _rc=0
    _out="$(settings_merge "$_py" "$STUDIO_DIR/settings.json" "$SETTINGS")" || _rc=$?
    case "$_rc" in
      0)
        _nl='
'
        if [ "${_out%%"$_nl"*}" = same ]; then SETTINGS_SAME=1; else SETTINGS_SAME=0; fi
        _out="${_out#*"$_nl"}"
        SETTINGS_KEPT="${_out%%"$_nl"*}"
        if [ -n "$SETTINGS_KEPT" ]; then SETTINGS_DOC="${_out#*"$_nl"}"; fi
        ;;
      3) SETTINGS_WHY="not a valid JSON object" ;;
      *) SETTINGS_WHY="could not merge (python3 exit $_rc)" ;;
    esac
  fi
fi
if [ "$SETTINGS_SAME" = 0 ]; then
  if [ "$DRY_RUN" = "1" ]; then
    [ -z "$SETTINGS_WHY" ] || warn "settings.json: $SETTINGS_WHY — the studio template would be installed as is"
  else
    SETTINGS_BAK="$TARGET/settings.json.bak-$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$SETTINGS_BAK"
    warn "existing settings.json differed; backed up to $SETTINGS_BAK"
    [ -z "$SETTINGS_WHY" ] || warn "settings.json: $SETTINGS_WHY — installing the studio template as is; your previous file is $SETTINGS_BAK"
  fi
fi
# Remove what the previous manifest recorded before writing anything else
# (printed, not performed, in a dry run). The shim to remove is the one the
# previous manifest recorded, not the one this install will write: a
# reinstall with a different --shim-dir would otherwise skip the old shim as
# out of scope and orphan it. A manifest without the header (an install by
# the previous installer) falls back to the new path. Split assignment so a
# missing manifest cannot trip `set -e`.
_prev_shim="$(manifest_meta "$MANIFEST" shim || true)"
[ -n "$_prev_shim" ] || _prev_shim="$SHIM_PATH"
for server in $(manifest_mcp_servers "$MANIFEST"); do
  if [ "$DRY_RUN" = "1" ]; then log "DRY  mcp remove $server"; else mcp_remove "$TARGET" "$server"; fi
done
manifest_remove "$MANIFEST" "$TARGET" "$_prev_shim"
if [ "$DRY_RUN" != "1" ]; then
  # The pre-plugin layout linked skills, agents, commands and hooks into the
  # root; removing those entries leaves their directories behind, empty.
  # rmdir takes only an empty directory, so one that still holds user files
  # stays.
  for d in agents skills commands hooks; do
    rmdir "$TARGET/$d" 2>/dev/null || true
  done
  # The header tells uninstall and doctor what this install chose, so neither
  # has to be told --shim-dir or guess the mode.
  printf '# mode=%s\n# shim=%s\n' "$MODE" "$SHIM_PATH" > "$MANIFEST"
fi

# Only memory/ and bin/ live in the config root; skills, agents and hooks are
# served by the plugin. Shared first, studio second so the studio wins. The
# entries are read line by line: a path with a space is one entry.
for dir in memory bin; do
  for src in "$REPO_ROOT/shared/$dir" "$STUDIO_DIR/$dir"; do
    install_entries "$src" "$TARGET/$dir" "$MODE" | while IFS= read -r installed; do
      manifest_add "$MANIFEST" "$installed"
    done
  done
done

# CLAUDE.md is generated, so it is always written as a real file.
if [ "$DRY_RUN" = "1" ]; then
  log "DRY  render $TARGET/CLAUDE.md"
else
  # A link at the destination would be written through; remove it first, as
  # install_entries does for memory/ and bin/.
  rm -f "$TARGET/CLAUDE.md"
  {
    printf '<!-- GENERATED by omega-ai install.sh from shared/CLAUDE.part.md\n'
    printf '     and studios/%s/CLAUDE.md. Edits here are overwritten. -->\n\n' "$STUDIO"
    if [ -f "$REPO_ROOT/shared/CLAUDE.part.md" ]; then
      cat "$REPO_ROOT/shared/CLAUDE.part.md"
    fi
    printf '\n'
    cat "$STUDIO_DIR/CLAUDE.md"
    # Studio memory: curated, cross-project decisions the retro stage writes.
    # An @import is how Claude Code loads it; the path is relative to this
    # file. Claude's own auto memory stays under projects/<project>/memory/.
    if [ -f "$STUDIO_DIR/memory/MEMORY.md" ] || [ -f "$REPO_ROOT/shared/memory/MEMORY.md" ]; then
      printf '\n## Studio memory\n\nDurable studio-wide decisions, kept in version control:\n\n@memory/MEMORY.md\n'
    fi
  } > "$TARGET/CLAUDE.md"
  manifest_add "$MANIFEST" "$TARGET/CLAUDE.md"
fi

# settings.json is copied, never linked: Claude Code writes to it in-session.
# What to write, and any backup, was decided above, before the old
# manifest's entries were removed.
if [ "$DRY_RUN" = "1" ]; then
  if [ -n "$SETTINGS_DOC" ]; then
    log "DRY  merge $SETTINGS (keeping your keys: $SETTINGS_KEPT)"
  else
    log "DRY  copy $SETTINGS"
  fi
else
  rm -f "$SETTINGS"
  if [ -n "$SETTINGS_DOC" ]; then
    printf '%s\n' "$SETTINGS_DOC" > "$SETTINGS"
    log "settings.json: kept your keys: $SETTINGS_KEPT"
  else
    cp "$STUDIO_DIR/settings.json" "$SETTINGS"
  fi
  manifest_add "$MANIFEST" "$SETTINGS"
fi

if [ "$MODE" = "copy" ]; then
  run rm -rf "$PLUGIN_DIR"
  run cp -R "$STUDIO_DIR" "$PLUGIN_DIR"
  manifest_add "$MANIFEST" "$PLUGIN_DIR"
  run rm -rf "$GLOBAL_DIR"
  run cp -R "$GLOBAL_SRC" "$GLOBAL_DIR"
  manifest_add "$MANIFEST" "$GLOBAL_DIR"
fi

if [ "$DRY_RUN" = "1" ]; then
  log "DRY  write shim $SHIM_PATH"
else
  mkdir -p "$SHIM_DIR"
  # Never write through a link at the shim's path.
  rm -f "$SHIM_PATH"
  cat > "$SHIM_PATH" <<SHIM
#!/usr/bin/env sh
# Generated by omega-ai install.sh — launches Claude Code against the
# $STUDIO studio's isolated config root with the studio plugin and the
# omega global plugin loaded live.
OMEGA_STUDIO_ROOT="$PLUGIN_DIR"
OMEGA_GLOBAL_ROOT="$GLOBAL_DIR"
export OMEGA_STUDIO_ROOT OMEGA_GLOBAL_ROOT
CLAUDE_CONFIG_DIR="$TARGET" \\
PATH="$TARGET/bin:\$OMEGA_GLOBAL_ROOT/bin:\$PATH" \\
  exec claude --plugin-dir "\$OMEGA_STUDIO_ROOT" --plugin-dir "\$OMEGA_GLOBAL_ROOT" "\$@"
SHIM
  chmod +x "$SHIM_PATH"
  manifest_add "$MANIFEST" "$SHIM_PATH"

  # Studio commands a person runs from a terminal (studio.json "commands",
  # space-separated names in the studio's bin/): one shim each beside the
  # launch shim, running the installed command against this config root, so
  # `studio-overnight status` works from any directory. Recorded in the
  # manifest; manifest_remove takes them as launchers of this root.
  for cmd in $(json_field "$STUDIO_DIR/studio.json" commands); do
    case "$cmd" in *[!A-Za-z0-9._-]*|.*) warn "skipping bad command name in studio.json: $cmd"; continue ;; esac
    [ -f "$TARGET/bin/$cmd" ] || { warn "studio.json names command $cmd, but $TARGET/bin/$cmd is missing"; continue; }
    # A file of the user's own at that name is kept; a link (a hand-made
    # `ln -s …/bin/$cmd`) is replaced, never written through — `cat >` would
    # overwrite the studio's own command with this shim.
    if [ -f "$SHIM_DIR/$cmd" ] && [ ! -L "$SHIM_DIR/$cmd" ] \
       && ! grep -q '^# Generated by omega-ai install.sh' "$SHIM_DIR/$cmd"; then
      warn "$SHIM_DIR/$cmd exists and was not written by install.sh; keeping it (remove it and reinstall to put $cmd on PATH)"
      continue
    fi
    rm -f "$SHIM_DIR/$cmd"
    cat > "$SHIM_DIR/$cmd" <<CMDSHIM
#!/usr/bin/env sh
# Generated by omega-ai install.sh — runs the $STUDIO studio's $cmd from any
# directory, against its config root, with the studio's bin/ and the launch
# shim ($SHIM_NAME) on PATH.
CLAUDE_CONFIG_DIR="$TARGET" \\
PATH="$SHIM_DIR:$TARGET/bin:$GLOBAL_DIR/bin:\$PATH" \\
  exec sh "$TARGET/bin/$cmd" "\$@"
CMDSHIM
    chmod +x "$SHIM_DIR/$cmd"
    manifest_add "$MANIFEST" "$SHIM_DIR/$cmd"
    log "command:  $SHIM_DIR/$cmd"
  done

  case ":$PATH:" in
    *":$SHIM_DIR:"*) ;;
    *) warn "$SHIM_DIR is not on your PATH. Add it:
    export PATH=\"$SHIM_DIR:\$PATH\"" ;;
  esac
fi

# Optional MCP server. godot-mcp needs Node 18+ and a Godot binary; it is
# registered at user scope inside the config root, so it exists only for this
# studio, and recorded in the manifest so a reinstall or uninstall removes it.
# It is never written into the plugin's .mcp.json: a machine without Node
# must not see a startup failure.
ENGINE="$(json_field "$STUDIO_DIR/studio.json" engine)"
RESOLVE=""
[ -n "$ENGINE" ] && RESOLVE="$STUDIO_DIR/engines/$(engine_dir "$ENGINE")/resolve.sh"
if [ "$NO_MCP" = "1" ]; then
  log "mcp:      skipped (--no-mcp)"
elif [ -z "$ENGINE" ] || [ ! -f "$RESOLVE" ]; then
  log "mcp:      none (studio declares no engine adapter)"
elif [ "$(node_major)" -lt 18 ]; then
  log "mcp:      skipped (node 18+ not found — install Node.js to enable godot-mcp)"
elif ! GODOT="$(sh "$RESOLVE" 2>/dev/null)"; then
  log "mcp:      skipped (no Godot binary found — set GODOT_PATH and reinstall to enable godot-mcp)"
elif ! command -v claude >/dev/null 2>&1; then
  log "mcp:      skipped (claude is not on PATH)"
elif [ "$DRY_RUN" = "1" ]; then
  log "DRY  mcp add godot"
elif CLAUDE_CONFIG_DIR="$TARGET" claude mcp add --scope user godot \
       -e "GODOT_PATH=$GODOT" -- npx -y @coding-solo/godot-mcp >/dev/null 2>&1; then
  manifest_add "$MANIFEST" "mcp godot"
  log "mcp:      godot registered (npx -y @coding-solo/godot-mcp, GODOT_PATH=$GODOT)"
else
  warn "mcp registration failed; the studio works without it. To retry:
    CLAUDE_CONFIG_DIR=\"$TARGET\" claude mcp add --scope user godot -e GODOT_PATH=\"$GODOT\" -- npx -y @coding-solo/godot-mcp"
fi

if [ "$DRY_RUN" = "1" ]; then
  log ""
  log "(dry run complete)"
else
  log ""
  if sh "$REPO_ROOT/doctor.sh" "$STUDIO" --target "$TARGET"; then
    log ""
    log "Installed. Launch with: $SHIM_NAME"
  else
    warn "installed, but doctor found problems (see above) — fix them before launching $SHIM_NAME"
    exit 1
  fi
fi
