#!/bin/sh
# Runs every test file. Non-zero exit if any file fails.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
status=0
for f in "$DIR"/*_test.sh; do
  printf '\n=== %s ===\n' "$(basename "$f")"
  sh "$f" || status=1
done
exit "$status"
