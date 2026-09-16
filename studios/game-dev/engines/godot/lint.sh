#!/bin/sh
# lint.sh [PATH] — gdlint, then gdformat --check, over every .gd file under
# PATH (default the project) outside addons/. Invoked by studio-dispatch
# from the project root.
#
# Exit: 0 clean · 1 findings or not a project · 3 gdtoolkit not installed.
set -u

PROJECT="$(pwd -P)"
target="${1:-.}"

if [ ! -f "$PROJECT/project.godot" ]; then
  echo "studio-lint: no project.godot in $PROJECT — run from the project root" >&2
  exit 1
fi

if ! command -v gdlint >/dev/null 2>&1 && ! command -v gdformat >/dev/null 2>&1; then
  echo 'studio-lint: gdtoolkit is not installed. Install it with: pip install "gdtoolkit==4.*"' >&2
  exit 3
fi

# An emptiness probe: -exec below re-runs find, but a single -print | head
# check up front is cheap and keeps the "no .gd files" message exact.
found="$(find "$target" -name '*.gd' -not -path '*/addons/*' -not -path '*/.godot/*' -print | head -n 1)"
if [ -z "$found" ]; then
  echo "studio-lint: no .gd files under $target"
  exit 0
fi

status=0
if command -v gdlint >/dev/null 2>&1; then
  # -exec … {} + batches paths as argv elements (never word-split), so a
  # path with a space in it survives intact.
  find "$target" -name '*.gd' -not -path '*/addons/*' -not -path '*/.godot/*' -exec gdlint {} + || status=1
else
  echo "studio-lint: gdlint not found; running gdformat only" >&2
fi
if command -v gdformat >/dev/null 2>&1; then
  find "$target" -name '*.gd' -not -path '*/addons/*' -not -path '*/.godot/*' -exec gdformat --check {} + || status=1
else
  echo "studio-lint: gdformat not found; running gdlint only" >&2
fi

[ "$status" -eq 0 ] && echo "studio-lint: clean"
exit "$status"
