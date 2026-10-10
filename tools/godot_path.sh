#!/usr/bin/env bash
# Shared helper: locate the Godot 4 binary.  Override with:  export GODOT=/path/to/godot
find_godot() {
  if [[ -n "${GODOT:-}" && -x "$GODOT" ]]; then echo "$GODOT"; return; fi
  for c in \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
    [[ -x "$c" ]] && { echo "$c"; return; }
  done
  for c in godot godot4 Godot; do
    command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return; }
  done
  echo "ERROR: Godot 4 not found. Set GODOT=/path/to/godot" >&2
  exit 1
}
