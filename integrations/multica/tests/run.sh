#!/bin/sh
# The Multica integration's gate (milestone gate step 2): every
# *_test.sh here, then the Python unittest suite, offline.
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"
PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
status=0
for t in "$HERE"/*_test.sh; do
  [ -f "$t" ] || continue
  printf '\n=== %s ===\n' "$(basename "$t")"
  sh "$t" || status=1
done
PY="${OMEGA_MULTICA_TEST_PY:-}"
if [ -z "$PY" ]; then
  if /usr/bin/python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then PY=/usr/bin/python3; else PY=python3; fi
fi
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || { echo "run.sh: $PY is older than Python 3.9"; exit 1; }
if ls "$HERE"/test_*.py >/dev/null 2>&1; then
  printf '\n=== python unittest (%s) ===\n' "$("$PY" --version 2>&1)"
  ( cd "$HERE" && "$PY" -m unittest discover -s . -p 'test_*.py' -t . ) || status=1
fi
exit "$status"
