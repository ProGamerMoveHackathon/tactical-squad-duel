#!/usr/bin/env bash
# Visual test: server + two native windowed clients in demo mode that save screenshots.
#   tools/visual_test.sh <out_dir> [delay_seconds]
cd "$(dirname "$0")/.."
source tools/godot_path.sh
G="$(find_godot)"
OUT="${1:-/tmp}"
DELAY="${2:-12}"
PORT=9192
mkdir -p "$OUT"
"$G" --headless --path . -- --server --port=$PORT > /tmp/tsd_server.log 2>&1 &
SP=$!
sleep 2
"$G" --path . -- --auto --demo --name=Blue --server=ws://127.0.0.1:$PORT --screenshot="$OUT/shot_blue.png" --shot_delay=$DELAY > /tmp/tsd_cA.log 2>&1 &
A=$!
sleep 1
"$G" --path . -- --auto --demo --name=Red --server=ws://127.0.0.1:$PORT --screenshot="$OUT/shot_red.png" --shot_delay=$DELAY > /tmp/tsd_cB.log 2>&1 &
B=$!
( sleep $((DELAY + 15)); kill $A $B 2>/dev/null ) &
wait $A $B
kill $SP 2>/dev/null
for f in cA cB server; do echo "----- $f"; grep -v '^$' /tmp/tsd_$f.log | grep -v "Godot Engine" | head -30; done
