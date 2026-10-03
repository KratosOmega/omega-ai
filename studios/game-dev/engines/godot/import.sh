# import.sh — sourced by test.sh and run.sh: make sure the project's import
# cache is complete before the engine runs from it.
#
# The cache needs an import when .godot/ is absent, when an import product is
# missing (a *.import file whose source exists names a dest_files entry that is
# not on disk — what a killed or interrupted import leaves, and what a branch
# that adds assets with their .import files leaves), when a product's .md5
# sidecar is missing (Godot writes it once that file's import has finished, so
# a product without one may be cut short), or when a class_name script exists
# but .godot/global_script_class_cache.cfg does not. An asset added without its
# .import file is not seen. Checking takes 2–3 s on a 5k-asset project; a
# re-import takes 24 s (a no-op over a complete cache) to 130 s (from nothing),
# so the import only runs when the check asks for it.

# import_missing PROJECT — print each missing import product (res:// relative).
# A .import file under a directory Godot does not scan (one holding .gdignore,
# or a nested project.godot) is skipped: Godot never imports it.
import_missing() {
  ( cd "$1" && find . -path ./.godot -prune -o -path ./.git -prune -o -path ./.claude -prune \
      -o -name node_modules -prune -o -name .gdignore -print -o -name project.godot -print \
      -o -name '*.import' -type f -print |
    awk '
      /\/\.gdignore$|\/project\.godot$/ { d = $0; sub(/\/[^\/]*$/, "", d); if (d != ".") skip[d] = 1; next }
      { imp[++n] = $0 }
      END {
        for (i = 1; i <= n; i++) {
          f = imp[i]; ok = 1
          for (d in skip) if (index(f, d "/") == 1) { ok = 0; break }
          if (!ok) continue
          src = ""; dl = ""
          while ((getline line < f) > 0) {
            if (line ~ /^source_file="res:\/\//) { src = line; sub(/^source_file="res:\/\//, "", src); sub(/"$/, "", src) }
            else if (line ~ /^dest_files=\[/) dl = line
          }
          close(f)
          if (src == "") continue
          # Each entry is a quoted string; a file name may itself hold a comma.
          while (match(dl, /"[^"]*"/)) {
            x = substr(dl, RSTART + 1, RLENGTH - 2); dl = substr(dl, RSTART + RLENGTH)
            sub(/^res:\/\//, "", x)
            # A product <name>-<32 hex>.<ext> has the sidecar <name>-<32 hex>.md5. The
            # hash is the last "-<hex>." of the last path component (a source name
            # may hold hex of its own), and its length is checked, not matched with
            # {32}, which mawk lacks.
            m = ""
            if (match(x, /-[0-9a-f]+\.[^\/-]*$/) && index(substr(x, RSTART + 1), ".") == 33)
              m = substr(x, 1, RSTART + 32) ".md5"
            if (x != "") print src "\t" x "\t" m
          }
        }
      }
    ' 2>/dev/null |
    while IFS="	" read -r src dest md5; do
      [ -e "$src" ] || continue
      if [ ! -e "$dest" ] || { [ -n "$md5" ] && [ ! -e "$md5" ]; }; then printf '%s\n' "$dest"; fi
    done )
}

# import_class_cache_missing PROJECT — true when a class_name script exists and
# the global class cache does not. addons/ counts: GUT's GutTest is one.
import_class_cache_missing() {
  [ ! -f "$1/.godot/global_script_class_cache.cfg" ] || return 1
  grep -rlqs --include='*.gd' --exclude-dir=.godot --exclude-dir=.git --exclude-dir=.claude \
    '^class_name ' "$1" 2>/dev/null
}

# ensure_import GODOT PROJECT LOG VERB — import when the cache is incomplete,
# then check again. Returns 1 (after printing why) when the import exits
# non-zero; the engine must not run on that cache. An import that exits 0 but
# leaves products (or the class cache) missing is a warning, and returns 0:
# Godot writes no product for a source it failed on, so what is still missing
# then is mostly what it will never produce, and stopping would fail every run.
ensure_import() {
  _ig="$1"; _ip="$2"; _il="$3"; _iv="$4"
  if [ -d "$_ip/.godot" ]; then
    _imiss="$(import_missing "$_ip" | wc -l | tr -d ' ')"
    _icls=0; import_class_cache_missing "$_ip" && _icls=1
    if [ "$_imiss" -eq 0 ] && [ "$_icls" -eq 0 ]; then
      return 0
    fi
    if [ "$_imiss" -eq 0 ]; then _iwhy="no class cache"
    elif [ "$_icls" -eq 1 ]; then _iwhy="$_imiss missing, no class cache"
    else _iwhy="$_imiss missing"
    fi
    printf '%s: import cache incomplete (%s) — importing\n' "$_iv" "$_iwhy"
  else
    printf '%s: no import cache (.godot/) — importing\n' "$_iv"
  fi
  _it0="$(date +%s)"
  "$_ig" --headless --path "$_ip" --import >>"$_il" 2>&1
  _irc=$?
  if [ "$_irc" -ne 0 ]; then
    printf '%s: the asset import did not complete (engine exit %s); last lines of %s:\n' "$_iv" "$_irc" "$_il"
    tail -n 20 "$_il"
    return 1
  fi
  printf '%s: imported in %ss\n' "$_iv" "$(( $(date +%s) - _it0 ))"
  _imiss="$(import_missing "$_ip")"
  if [ -n "$_imiss" ]; then
    printf '%s: WARNING: the import finished but left %s import product(s) missing, e.g.:\n' \
      "$_iv" "$(printf '%s\n' "$_imiss" | wc -l | tr -d ' ')"
    printf '%s\n' "$_imiss" | head -n 5 | sed 's/^/  /'
    printf 'Running anyway; Godot does not produce them. Any import errors are in %s.\n' "$_il"
  fi
  if import_class_cache_missing "$_ip"; then
    printf '%s: WARNING: the import finished but left no .godot/global_script_class_cache.cfg; running anyway.\n' "$_iv"
  fi
  return 0
}
