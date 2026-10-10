# Tactical Squad Duel

Competitive top-down 1 vs 1 tactical shooter for the browser (Godot 4.7, Compatibility renderer).
Each player commands a squad of 3 soldiers (Rifle, SMG, Shotgun) but controls only one at a time.
Visibility, shooting, damage and abilities are all decided by a dedicated **authoritative Godot server**;
clients only receive the enemy soldiers their squad can actually see.

## Quick start (everything on your own PC)

Requirements: Godot 4.7.x (with the **Web** export templates), Python 3.

```bash
./run_local.sh          # exports the web build, starts game server + web server, opens 2 tabs
./run_local.sh --no-export   # skip the export if nothing changed
```

Then play one side in each tab: <http://localhost:8080/?name=Blue> and <http://localhost:8080/?name=Red>.
Add `&auto=1` to the URL to skip the menu and connect immediately.

Manual steps if you prefer:

```bash
./export_web.sh                         # -> build/web/
./run_server.sh                         # game server on ws://localhost:9080
python3 tools/serve_web.py 8080         # static web server for build/web
```

No web export templates yet? Either *Editor → Manage Export Templates → Download*, or install
only the web templates (~90 MB instead of 1.3 GB): `python3 tools/fetch_web_templates.py 4.7.2`.

If Godot is not in `/Applications`, `~/Applications` or `~/Downloads`, set `GODOT=/path/to/Godot`.

## Controls

| Action | Keyboard / mouse | Voice (press **V** or the *Mic* button first) |
|---|---|---|
| Move selected soldier | Left click (Shift+click keeps the watch direction) | |
| Set watch / firing direction | Right click or right-drag | |
| Switch soldier | `1` `2` `3`, `Tab`, or click a soldier | "alpha", "bravo", "charlie" |
| Smoke (at mouse cursor, max throw range) | `Q` | "smoke" |
| Scan (reveal nearby *moving* enemies) | `E` | "scan" |
| Suppress (wider cone, less accuracy, faster fire) | `R` | "suppress" |
| Rush (speed boost) | `F` | "rush" |
| Rematch | `Enter` | |

Soldiers shoot automatically at the closest enemy inside their firing cone with clear line of sight
(after a short reaction time). Moving soldiers are less accurate. Unselected soldiers finish their
current move and then hold position, watching their assigned direction
(`CONTINUE_MOVE_WHEN_DESELECTED` in `scripts/config.gd` makes them stop instantly instead).

Voice uses the browser Web Speech API (Chrome / Edge; Safari partially; Firefox → keyboard only).
It needs a secure context: `http://localhost` works, on the VM use HTTPS.

## Architecture

```
scripts/
  config.gd             all tuning (weapons, vision, abilities, voice phrases)
  map_data.gd           point-symmetric map, DDA line of sight, smoke occlusion, collision, A*
  net.gd                autoload "Net": WebSocket peer + every RPC
  main.gd               headless / --server -> dedicated server, otherwise client
  server/server_game.gd authoritative simulation + per-player filtered snapshots (30 Hz)
  client/client_game.gd menu, input -> intents, snapshot interpolation, effects
  client/vision_mask.gd fog-of-war mask (SubViewport + shader)
  client/entity_view.gd soldiers, cones, tracers, smoke, pings
  client/hud.gd         HUD
  client/voice.gd       Web Speech API <-> Godot via JavaScriptBridge
  client/sfx.gd         procedural sounds
tests/bot_client.gd     headless bot (tools/bot_match.sh runs server + 2 bots)
deploy/                 Caddyfile + systemd unit for the VM
```

* Clients send intent only (`select`, `move`, `face`, `ability`, `rematch`). The server validates
  slot ownership, game state, cooldowns, coordinates and throw range.
* Every tick the server computes, per team, which enemies are inside any squad member's view cone
  (or close-range awareness radius), within range and not occluded by walls or smoke.
  Only those enemies are serialized into that player's snapshot. Hidden shooters only reveal an
  approximate *direction* of incoming fire. The client's fog of war is cosmetic.
* Player 2's view is rotated 180° so both players see their base on the left.

## Deploying on the VM

1. Copy the project (incl. `build/web`) to `/opt/tactical-squad-duel` and install a Linux Godot 4.7.2
   binary as `/usr/local/bin/godot`. Run `godot --headless --path /opt/tactical-squad-duel --import` once.
2. `deploy/tactical-squad-duel.service` → `/etc/systemd/system/`, then
   `systemctl enable --now tactical-squad-duel`.
3. Install [Caddy](https://caddyserver.com), copy `deploy/Caddyfile` to `/etc/caddy/Caddyfile`,
   set your domain, `systemctl reload caddy`. Open ports 80/443.
4. Players open `https://your-domain/`. The client automatically connects to `wss://your-domain/ws`.

Alternatively the Godot server can terminate TLS itself:
`godot --headless --path . -- --server --port=9080 --cert=fullchain.pem --key=privkey.pem`
(then connect with `?server=wss://host:9080`).
