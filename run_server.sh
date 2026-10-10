#!/usr/bin/env bash
# Run the dedicated authoritative game server (headless).
#   ./run_server.sh [port]
set -euo pipefail
cd "$(dirname "$0")"
source tools/godot_path.sh
G="$(find_godot)"
PORT="${1:-9080}"
exec "$G" --headless --path . -- --server --port="$PORT"
