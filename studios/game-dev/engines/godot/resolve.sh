#!/bin/sh
# resolve.sh — print the Godot binary to use, or exit 2.
#
# Order: $GODOT_PATH when set and executable; the first executable
# Godot*.app bundle under $GODOT_APP_DIR (default /Applications); godot on
# PATH. Nothing else is searched, so a result is always explainable.
set -u

if [ -n "${GODOT_PATH:-}" ] && [ -x "$GODOT_PATH" ]; then
  printf '%s\n' "$GODOT_PATH"
  exit 0
fi

for app in "${GODOT_APP_DIR:-/Applications}"/Godot*.app/Contents/MacOS/Godot; do
  if [ -x "$app" ]; then
    printf '%s\n' "$app"
    exit 0
  fi
done

if command -v godot >/dev/null 2>&1; then
  command -v godot
  exit 0
fi

echo "no Godot binary found; set GODOT_PATH" >&2
exit 2
