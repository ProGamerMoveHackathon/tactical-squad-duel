#!/usr/bin/env bash
# One-command local test: exports the web client, starts the game server and a
# static web server, and opens two browser tabs (one per player).
#   ./run_local.sh            (re-export + run)
#   ./run_local.sh --no-export
set -euo pipefail
cd "$(dirname "$0")"
source tools/godot_path.sh
G="$(find_godot)"

if [[ "${1:-}" != "--no-export" || ! -f build/web/index.html ]]; then
  ./export_web.sh
fi

cleanup() { kill "${SERVER_PID:-}" "${WEB_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

"$G" --headless --path . -- --server --port=9080 &
SERVER_PID=$!
python3 tools/serve_web.py 8080 build/web &
WEB_PID=$!
sleep 1.5

URL="http://localhost:8080/"
echo ""
echo "  Game server : ws://localhost:9080"
echo "  Web client  : $URL"
echo "  Open the URL in TWO browser tabs/windows (one per player). Ctrl+C to stop."
echo ""
if command -v open >/dev/null 2>&1; then
  open "${URL}?name=Blue"; sleep 1; open "${URL}?name=Red"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}?name=Blue"; sleep 1; xdg-open "${URL}?name=Red"
fi
wait
