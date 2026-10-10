#!/usr/bin/env bash
# Automated headless test: server + 2 bots (+ a 3rd that must be rejected).
#   tools/bot_match.sh [seconds]
cd "$(dirname "$0")/.."
source tools/godot_path.sh
G="$(find_godot)"
DUR="${1:-40}"
PORT=9191
"$G" --headless --path . -- --server --port=$PORT > /tmp/tsd_server.log 2>&1 &
SP=$!
sleep 2
"$G" --headless --path . --script res://tests/bot_client.gd -- --url=ws://127.0.0.1:$PORT --name=BotA --duration=$DUR > /tmp/tsd_botA.log 2>&1 &
A=$!
sleep 0.5
"$G" --headless --path . --script res://tests/bot_client.gd -- --url=ws://127.0.0.1:$PORT --name=BotB --duration=$DUR > /tmp/tsd_botB.log 2>&1 &
B=$!
sleep 1
"$G" --headless --path . --script res://tests/bot_client.gd -- --url=ws://127.0.0.1:$PORT --name=BotC --duration=4 > /tmp/tsd_botC.log 2>&1
wait $A $B
kill $SP 2>/dev/null
for f in server botA botB botC; do echo "----- $f"; grep -v '^$' /tmp/tsd_$f.log | grep -v "Godot Engine" | head -50; done
