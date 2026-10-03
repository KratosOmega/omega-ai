# import.sh — sourced by test.sh and run.sh: make sure the project's import
# cache is complete before the engine runs from it.
#
# The cache needs an import when .godot/ is absent, when an import product is
# missing (a *.import file whose source exists names a dest_files entry that is
# not on disk — what a killed or interrupted import leaves, and what a branch
# that adds assets leaves), when a product's .md5 sidecar is missing (Godot
# writes it once that file's import has finished, so a product without one may
# be cut short), or when a class_name script exists but
# .godot/global_script_class_cache.cfg does not. Checking takes about a second
# on a 5k-asset project; a no-op `--import` over a complete cache takes ~25 s,
# so the import only runs when the check asks for it.

# import_missing PROJECT — print each missing import product (res:// relative).
import_missing() {
  ( cd "$1" && find . -path ./.godot -prune -o -path ./.git -prune -o -path ./.claude -prune \
      -o -name node_modules -prune -o -name '*.import' -print0 |
    xargs -0 awk '
      function flush(   n, a, i, x) {
        n = split(dl, a, ",")
        for (i = 1; i <= n; i++) {
          x = a[i]; gsub(/^ *"res:\/\//, "", x); gsub(/" *$/, "", x)
          # A product <name>-<32 hex>.<ext> has the sidecar <name>-<32 hex>.md5.
          m = ""; if (match(x, /-[0-9a-f]{32}\./)) m = substr(x, 1, RSTART + 32) ".md5"
          if (src != "" && x != "") print src "\t" x "\t" m
        }
        src = ""; dl = ""
      }
      FNR == 1 && NR > 1 { flush() }
      /^source_file="res:\/\// { s = $0; sub(/^source_file="res:\/\//, "", s); sub(/"$/, "", s); src = s }
      /^dest_files=\[/ { d = $0; sub(/^dest_files=\[/, "", d); sub(/\]$/, "", d); dl = d }
      END { flush() }
    ' 2>/dev/null |
    while IFS="	" read -r src dest md5; do
      [ -e "$src" ] || continue
      if [ ! -e "$dest" ] || { [ -n "$md5" ] && [ ! -e "$md5" ]; }; then printf '%s\n' "$dest"; fi
    done )
}

# import_class_cache_missing PROJECT — true when a class_name script exists and
# the global class cache does not.
import_class_cache_missing() {
  [ ! -f "$1/.godot/global_script_class_cache.cfg" ] || return 1
  grep -rlqs --include='*.gd' --exclude-dir=.godot --exclude-dir=.git --exclude-dir=addons \
    '^class_name ' "$1" 2>/dev/null
}

# ensure_import GODOT PROJECT LOG VERB — import when the cache is incomplete,
# then check again. Returns 1 (after printing why) when the import exits
# non-zero or leaves products missing; the engine must not run on that cache.
ensure_import() {
  _ig="$1"; _ip="$2"; _il="$3"; _iv="$4"
  if [ -d "$_ip/.godot" ]; then
    _imiss="$(import_missing "$_ip" | wc -l | tr -d ' ')"
    if [ "$_imiss" -eq 0 ] && ! import_class_cache_missing "$_ip"; then
      return 0
    fi
    printf '%s: import cache incomplete (%s missing) — importing\n' "$_iv" "$_imiss"
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
  _imiss="$(import_missing "$_ip")"
  if [ -n "$_imiss" ]; then
    printf '%s: the asset import did not complete — %s import product(s) still missing, e.g.:\n' \
      "$_iv" "$(printf '%s\n' "$_imiss" | wc -l | tr -d ' ')"
    printf '%s\n' "$_imiss" | head -n 5 | sed 's/^/  /'
    printf 'Their sources failed to import; the errors are in %s.\n' "$_il"
    return 1
  fi
  printf '%s: imported in %ss\n' "$_iv" "$(( $(date +%s) - _it0 ))"
  return 0
}
