#!/bin/sh
# run_affected.sh - run only the suites a change can affect (R9).
#
#   sh tests/run_affected.sh [--base REF] [--list]
#
# IN-PROGRESS CHECK ONLY. The merge gate is `sh tests/run_all.sh`.
#
#   --base REF  compare against REF (default origin/main; never fetched)
#   --list      print "suite<TAB>reason" lines and exit 0
#
# Changed files: git diff --name-only --no-renames <merge-base> (committed,
# staged, unstaged, deleted; a rename lists both paths) plus untracked files.
# Mapping, first match wins:
#   1. tests/assert.sh, tests/run_all.sh, lib/*        -> all suites
#   2. tests/<x>_test.sh -> itself; tests/run_affected.sh -> run_affected_test;
#      tests/exclusive_scan.awk -> harness_test
#   3. docs/**   -> suites naming the doc path or its directory, else none
#   4. other     -> reverse-reference closure over the code files; the suites
#                   in the closure. None found -> unknown -> all suites.
set -u

REF=origin/main
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || { echo "run_affected: --base needs a REF" >&2; exit 2; }
            REF=$2; shift 2 ;;
    --list) LIST=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "run_affected: unknown argument $1" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.." || exit 2
WORK="$(mktemp -d "${TMPDIR:-/tmp}/run_affected.XXXXXX")" && [ -d "$WORK" ] \
  || { echo "run_affected: cannot create temp dir under ${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

BASE=$(git rev-parse --verify -q "$REF^{commit}" 2>/dev/null) &&
  BASE=$(git merge-base "$REF" HEAD 2>/dev/null) || BASE=
if [ -z "$BASE" ]; then
  echo "run_affected: base $REF not found — git fetch, or pass --base" >&2
  exit 2
fi
echo "run_affected: base $REF $BASE" >&2

if git diff --name-only --no-renames "$BASE" > "$WORK/tracked" 2>/dev/null &&
   git diff -M --name-status --diff-filter=R "$BASE" > "$WORK/rstatus" 2>/dev/null &&
   git ls-files --others --exclude-standard > "$WORK/untracked" 2>/dev/null; then
  :
else
  echo "run_affected: git diff failed against $BASE - not guessing, run sh tests/run_all.sh" >&2
  exit 1
fi
sort -u "$WORK/tracked" "$WORK/untracked" > "$WORK/changed"
# Rename pairs old<TAB>new. A rename target nobody references is covered by its
# old path only if the old path reached an existing suite (else it is unknown).
awk -F'	' '{ print $2 "\t" $3 }' "$WORK/rstatus" > "$WORK/pairs"
if [ ! -s "$WORK/changed" ]; then
  echo "no changes against $REF" >&2
  exit 0
fi

# All suites present in the working tree.
for _f in tests/*_test.sh; do
  [ -e "$_f" ] && basename "$_f" .sh
done | sort > "$WORK/all"

# Code files for the closure (tracked, still present, plus untracked).
{ git ls-files; git ls-files --others --exclude-standard; } | sort -u | while IFS= read -r _f; do
  [ -f "$_f" ] || continue
  case "$_f" in
    tests/*|lib/*|bin/*|studios/*/bin/*|studios/*/hooks/*|shared/*/bin/*|shared/*/hooks/*|integrations/*/bin/*) echo "$_f" ;;
    */*) ;;
    *.sh) echo "$_f" ;;
  esac
done > "$WORK/code"

: > "$WORK/out"      # suite<TAB>reason
add_all() {          # add_all REASON
  while IFS= read -r _s; do printf '%s\t%s\n' "$_s" "$1"; done < "$WORK/all" >> "$WORK/out"
}
add_suite() {        # add_suite SUITE REASON  (skips a suite that no longer exists)
  if grep -qx "$1" "$WORK/all"; then
    printf '%s\t%s\n' "$1" "$2" >> "$WORK/out"
  else
    echo "run_affected: $1 no longer exists, nothing to run" >&2
  fi
}

# key_of PATH: basename, or last two components for generic basenames.
key_of() {
  _b=$(basename "$1")
  case "$_b" in
    SKILL.md|README.md|hooks.json|plugin.json|config.json|run.sh)
      printf '%s/%s\n' "$(basename "$(dirname "$1")")" "$_b" ;;
    *) printf '%s\n' "$_b" ;;
  esac
}

# closure FILE: print the tests/*_test.sh members of FILE's closure.
closure() {
  printf '%s\n' "$1" > "$WORK/members"
  while :; do
    { cat "$WORK/members"; while IFS= read -r _m; do key_of "$_m"; done < "$WORK/members"; } |
      sort -u > "$WORK/pats"
    tr '\n' '\0' < "$WORK/code" | xargs -0 grep -lF -f "$WORK/pats" 2>/dev/null > "$WORK/hits"
    sort -u "$WORK/members" "$WORK/hits" > "$WORK/next"
    cmp -s "$WORK/next" "$WORK/members" && break
    cp "$WORK/next" "$WORK/members"
  done
  grep -E '^tests/[^/]*_test\.sh$' "$WORK/members" | while IFS= read -r _m; do
    basename "$_m" .sh
  done
}

# old_covers NEW: true if NEW is a rename target whose old path already selected
# an existing suite (or all suites, for a shared file).
old_covers() {
  _old=$(awk -F'	' -v n="$1" '$2 == n { print $1; exit }' "$WORK/pairs")
  [ -n "$_old" ] || return 1
  case "$_old" in
    tests/assert.sh|tests/run_all.sh|lib/*) return 0 ;;
  esac
  [ -n "$(closure "$_old" | grep -xFf "$WORK/all")" ]
}

while IFS= read -r f; do
  case "$f" in
    tests/assert.sh|tests/run_all.sh|lib/*) add_all "shared: $f"; continue ;;
    tests/run_affected.sh) add_suite run_affected_test itself; continue ;;
    tests/exclusive_scan.awk) add_suite harness_test itself; continue ;;
    tests/*/*) ;;
    tests/*_test.sh) add_suite "$(basename "$f" .sh)" itself; continue ;;
    docs/*)
      _dir=$(dirname "$f")
      _re=$(printf '%s' "$_dir" | sed 's/[.[\*^$()+?{|]/\\&/g')
      _found=0
      for _t in tests/*_test.sh; do
        [ -e "$_t" ] || continue
        if grep -qF -- "$f" "$_t" 2>/dev/null ||
           grep -qE -- "$_re/?([^A-Za-z0-9_./-]|\$)" "$_t" 2>/dev/null; then
          add_suite "$(basename "$_t" .sh)" "reads $f"
          _found=1
        fi
      done
      [ "$_found" = 1 ] || echo "no suite reads $f" >&2
      continue ;;
  esac
  _hit=$(closure "$f")
  if [ -n "$_hit" ]; then
    for _s in $_hit; do add_suite "$_s" "via $f"; done
  elif ! old_covers "$f"; then
    add_all "unknown: $f"
  fi
done < "$WORK/changed"

# One row per suite, first reason wins.
awk -F'\t' '!seen[$1]++' "$WORK/out" | sort -t'	' -k1,1 > "$WORK/final"

if [ "$LIST" = 1 ]; then
  cat "$WORK/final"
  exit 0
fi

if [ ! -s "$WORK/final" ]; then
  echo "run_affected: no suites affected" >&2
  exit 0
fi
echo "run_affected: in-progress check only — the merge gate is sh tests/run_all.sh" >&2
SUITES=$(cut -f1 "$WORK/final" | tr '\n' ' ' | sed 's/ $//')
ALL=$(tr '\n' ' ' < "$WORK/all" | sed 's/ $//')
rm -rf "$WORK"; trap - EXIT
if [ "$SUITES" = "$ALL" ]; then
  unset TEST_SUITES   # "all" means all, not an inherited selection
  exec sh tests/run_all.sh
fi
TEST_SUITES="$SUITES"
export TEST_SUITES
exec sh tests/run_all.sh
