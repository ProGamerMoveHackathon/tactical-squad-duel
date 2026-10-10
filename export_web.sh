#!/usr/bin/env bash
# Export the web client into build/web/
set -euo pipefail
cd "$(dirname "$0")"
source tools/godot_path.sh
G="$(find_godot)"
mkdir -p build/web
touch build/.gdignore
"$G" --headless --path . --import >/dev/null 2>&1 || true
"$G" --headless --path . --export-release "Web" build/web/index.html
echo "Web build ready in build/web/"
