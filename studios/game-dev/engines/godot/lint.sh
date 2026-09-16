#!/bin/sh
# lint.sh [PATH] — gdlint, then gdformat --check, over every .gd file under
# PATH (default the project) outside addons/. Invoked by studio-dispatch.
#
# Exit: 0 clean · 1 findings · 3 gdtoolkit not installed.
set -u

target="${1:-.}"

if ! command -v gdlint >/dev/null 2>&1 && ! command -v gdformat >/dev/null 2>&1; then
  echo 'studio-lint: gdtoolkit is not installed. Install it with: pip install "gdtoolkit==4.*"' >&2
  exit 3
fi

files="$(find "$target" -name '*.gd' -not -path '*/addons/*' -not -path '*/.godot/*' -print | sort)"
if [ -z "$files" ]; then
  echo "studio-lint: no .gd files under $target"
  exit 0
fi

status=0
if command -v gdlint >/dev/null 2>&1; then
  printf '%s\n' "$files" | xargs gdlint || status=1
else
  echo "studio-lint: gdlint not found; running gdformat only" >&2
fi
if command -v gdformat >/dev/null 2>&1; then
  printf '%s\n' "$files" | xargs gdformat --check || status=1
else
  echo "studio-lint: gdformat not found; running gdlint only" >&2
fi

[ "$status" -eq 0 ] && echo "studio-lint: clean"
exit "$status"
