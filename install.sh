#!/bin/sh
set -eu
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_ROOT/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: install.sh <studio> [options]

Install a studio from this repository into its own Claude Code config root,
leaving ~/.claude untouched. The studio's skills, agents and hooks load as a
plugin straight from the studio directory; only CLAUDE.md, settings.json,
memory/ and bin/ are placed in the config root.

Options:
  --mode symlink|copy   symlink (default) keeps the repo as source of truth;
                        copy takes a frozen snapshot: the studio is copied to
                        <target>/studio and loaded from there
  --target DIR          override the target from studio.json
  --shim-dir DIR        where to write the launch shim (default ~/.local/bin)
  --no-mcp              never register an MCP server for this studio
  --dry-run             print every action, change nothing
  -h, --help            show this help

Studios: see studios/ in this repository.
USAGE
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

# Both paths this script creates in — and the uninstaller deletes from — are
# guarded before anything is written.
guard_target "$TARGET" "$REPO_ROOT"
guard_target "$SHIM_DIR" "$REPO_ROOT"

# The plugin directory Claude Code loads. Symlink mode points at the checkout
# so edits are live; copy mode snapshots the studio under the config root so
# the install has no dependency on this checkout.
if [ "$MODE" = "copy" ]; then
  PLUGIN_DIR="$TARGET/studio"
else
  PLUGIN_DIR="$STUDIO_DIR"
fi
SHIM_PATH="$SHIM_DIR/$SHIM_NAME"

log "studio:   $STUDIO"
log "target:   $TARGET"
log "mode:     $MODE"
log "plugin:   $PLUGIN_DIR"
log "shim:     $SHIM_PATH"
if [ "$DRY_RUN" = "1" ]; then log "(dry run — nothing will change)"; fi

run mkdir -p "$TARGET"

# A previous install of this studio leaves a manifest behind. Remove what it
# recorded before writing anything, so a reinstall never leaves stale links
# from an older layout beside the new one.
MANIFEST="$TARGET/.omega-ai-manifest"
if [ "$DRY_RUN" != "1" ]; then
  # settings.json is the one installed file Claude Code mutates in-session,
  # and the previous manifest records it — so a differing copy is preserved
  # before the old entries are removed, never silently discarded.
  if [ -f "$TARGET/settings.json" ] && ! cmp -s "$STUDIO_DIR/settings.json" "$TARGET/settings.json"; then
    backup="$TARGET/settings.json.bak-$(date +%Y%m%d%H%M%S)"
    cp "$TARGET/settings.json" "$backup"
    warn "existing settings.json differed; backed up to $backup"
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
# A differing existing copy was backed up above, before the old manifest's
# entries were removed.
if [ "$DRY_RUN" = "1" ]; then
  log "DRY  copy $TARGET/settings.json"
else
  rm -f "$TARGET/settings.json"
  cp "$STUDIO_DIR/settings.json" "$TARGET/settings.json"
  manifest_add "$MANIFEST" "$TARGET/settings.json"
fi

if [ "$MODE" = "copy" ]; then
  run rm -rf "$PLUGIN_DIR"
  run cp -R "$STUDIO_DIR" "$PLUGIN_DIR"
  manifest_add "$MANIFEST" "$PLUGIN_DIR"
fi

if [ "$DRY_RUN" = "1" ]; then
  log "DRY  write shim $SHIM_PATH"
else
  mkdir -p "$SHIM_DIR"
  cat > "$SHIM_PATH" <<SHIM
#!/usr/bin/env sh
# Generated by omega-ai install.sh — launches Claude Code against the
# $STUDIO studio's isolated config root with the studio plugin loaded live.
OMEGA_STUDIO_ROOT="$PLUGIN_DIR"
export OMEGA_STUDIO_ROOT
CLAUDE_CONFIG_DIR="$TARGET" \\
PATH="$TARGET/bin:\$PATH" \\
  exec claude --plugin-dir "\$OMEGA_STUDIO_ROOT" "\$@"
SHIM
  chmod +x "$SHIM_PATH"
  manifest_add "$MANIFEST" "$SHIM_PATH"

  case ":$PATH:" in
    *":$SHIM_DIR:"*) ;;
    *) warn "$SHIM_DIR is not on your PATH. Add it:
    export PATH=\"$SHIM_DIR:\$PATH\"" ;;
  esac
fi

# MCP registration is part of the engine toolkit and arrives with it; the
# flag is accepted now so scripts written against the final interface work.
if [ "$NO_MCP" = "1" ]; then
  log "mcp:      skipped (--no-mcp)"
else
  log "mcp:      none registered (arrives with the engine toolkit)"
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
