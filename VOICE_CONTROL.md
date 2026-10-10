# 🎙️ Voice Control & Tactical Command Guide

> **Tactical Squad Duel** supports **100% hands-free voice gameplay**. You can command your entire squad—selection, positioning, sightlines, abilities, joining matches, and rematches—purely through natural spoken military commands, inspired by *There Came an Echo* and *Tom Clancy's EndWar*.
>
> Standard mouse and keyboard controls remain active at all times as responsive fallbacks.

---

## 📑 Table of Contents
1. [Browser Setup & Microphone Permissions](#-browser-setup--microphone-permissions)
2. [Command Grammar: How to Speak](#-command-grammar-how-to-speak)
3. [Complete Voice Command Cheat Sheet](#-complete-voice-command-cheat-sheet)
4. [Tactical Landmarks & Callout Map](#-tactical-landmarks--callout-map)
5. [Perspective & Directional System](#-perspective--directional-system)
6. [HUD & Audio Feedback](#-hud--audio-feedback)
7. [Tips for Reliable Voice Recognition](#-tips-for-reliable-voice-recognition)
8. [Developer Guide: Extending Voice Commands](#-developer-guide-extending-voice-commands)

---

## 🌐 Browser Setup & Microphone Permissions

The voice system uses the native browser **Web Speech API** via Godot's `JavaScriptBridge`.

### Supported Browsers
- **Google Chrome** (Recommended, lowest latency)
- **Microsoft Edge** (Recommended)
- **Brave** (Enable Web Speech in settings)
- **Safari** (macOS / iOS)

### Microphone Permissions
1. When you first open the game on `http://localhost:8080` (or `https://your-domain.com`), the browser will ask for microphone permission. Click **Allow**.
2. **Auto-Start**: Voice recognition starts automatically when you click **Deploy** or press **V**.
3. **Manual Toggle**: Click the **Mic** button in the lower right corner or press **V** to start/stop listening.

---

## 🗣️ Command Grammar: How to Speak

The parser recognizes natural speech following a standard squad military syntax:

$$\mathbf{[Subject]} \longrightarrow \mathbf{[Action]} \longrightarrow \mathbf{[Target / Direction]}$$

### 1. Subject (Who)
- **Individual Soldiers**:
  - `Alpha` (Soldier 1 · Rifle)
  - `Bravo` (Soldier 2 · SMG)
  - `Charlie` (Soldier 3 · Shotgun)
  - *Synonyms*: `"One"`, `"Two"`, `"Three"`, `"Rifle"`, `"SMG"`, `"Shotgun"`, `"Gunner"`, `"Breacher"`
- **All Soldiers**:
  - `Squad`, `All`, `Team`, `Everyone`
- **Default (Omitted)**:
  - If you omit the name (e.g. just say *"Move to Mid"*), the order automatically applies to the **currently active soldier**.

### 2. Actions & Targets (What & Where)
- **Movement to Landmarks**: *"Alpha to Mid"*, *"Bravo go to North"*, *"Advance to Choke"*
- **Squad Formations**: *"Squad move to Mid"*, *"All fall back to Base"*
- **Directional Steps**: *"Move North"*, *"Advance"*, *"Step back"*, *"Fall back"*
- **Aiming & Watching**: *"Watch North"*, *"Face East"*, *"Cover Mid"*, *"Hold angle"*
- **Abilities**: *"Fog"*, *"Scan"*, *"Rush"*, *"Outrage"*, *"Flash"*, *"Break magic"*, *"Fireball"*, *"Invisible"*
- **Stop**: *"Stop"*, *"Halt"*, *"Hold position"*, *"Stay"*
- **Match Progression**: *"Deploy"*, *"Start"*, *"Rematch"*, *"Play again"*

---

## 📋 Complete Voice Command Cheat Sheet

| Category | Example Spoken Phrases | In-Game Action |
|---|---|---|
| **Selection** | `"Alpha"`, `"Bravo"`, `"Charlie"`<br>`"Select One"`, `"Switch to Rifle"` | Selects and highlights that squad member. |
| **Callout Movement** | `"Alpha move to Mid"`<br>`"Bravo to North"`<br>`"Charlie advance to Choke"`<br>`"Move to Base"` | Selected soldier computes an A* path straight to that landmark. |
| **Squad Movement** | `"Squad advance to Mid"`<br>`"All fall back to Base"`<br>`"Team move to Yard"` | Entire squad advances or retreats in a tactical spread formation. |
| **Directional Steps** | `"Advance"`, `"Push forward"`<br>`"Fall back"`, `"Retreat"`<br>`"Step North"`, `"Move South"` | Steps ~140 pixels in that compass direction. |
| **Halt / Hold** | `"Stop"`<br>`"Alpha halt"`<br>`"Squad hold position"` | Cancels waypoints and immediately stops moving. |
| **Watch / Aim Angle** | `"Watch North"`<br>`"Aim South"`<br>`"Bravo watch Mid"`<br>`"Cover East"` | Rotates firing cone to guard that direction or landmark. |
| **Fog Magic** | `"Fog"`<br>`"Cast fog"`<br>`"Charlie fog"` | Conjures vision-blocking fog just ahead of each eligible caster. |
| **Squad Abilities** | `"Fog"`<br>`"Scan"`<br>`"Rush"`<br>`"Outrage"`<br>`"Flash"`<br>`"Break magic"`<br>`"Fireball"`<br>`"Invisible"` | Casts the equipped ability for every eligible squad member, with server-side MP and cooldown checks. |
| **Match Flow** | `"Deploy"`, `"Ready"`, `"Start"`<br>`"Rematch"`, `"Play again"` | Connects to lobby or requests an instant rematch after match ends. |

---

## 🗺️ Tactical Landmarks & Callout Map (ETH Zürich Polymensa)

The battlefield is modeled directly after the **ETH Polymensa (Geschoss F)** architectural floor plan, featuring 9 named tactical landmarks rendered directly on screen with cyan badges `[NAME]`:

```
+---------------------------------------------------------------------------------+
|                                    [KÜCHE]                                      |
|                        (Kitchen & Food Prep Corridor)                           |
|                                                                                 |
|       [CHOKE]                                                   [ENEMY CHOKE]   |
|   (Kitchen Door)                                                                |
|                                                                                 |
|                    [PILLAR]                                                     |
|                    (Column)                                                     |
|                                                                                 |
| [ZUGANG]   [TRAYS]                 [BUFFET]                            [AUSGANG]|
| (Entrance) (Tablett)         (Salad Bar / Mid)                          (Exit)  |
|                                                                                 |
|       [KASSE]                                                   [ENEMY KASSE]   |
|     (Cashiers)                                                                  |
|                                                                                 |
|                                   [TABLES]                                      |
|                       (Polyterrasse Dining Hall)                                |
+---------------------------------------------------------------------------------+
```

### Callout Descriptions & Spoken Synonyms
- **`[ZUGANG]` / Base**: West entrance lobby (`"Base"`, `"Zugang"`, `"Entrance"`).
- **`[TRAYS]` / Yard**: Free-Flow tray dispensers (`"Trays"`, `"Tablett"`, `"Yard"`).
- **`[CHOKE]` / Kitchen Door**: Doorway into the northern kitchen (`"Choke"`, `"Kitchen door"`).
- **`[KASSE]` / Flank**: Register checkouts dividing servery from dining (`"Kasse"`, `"Cashier"`, `"Flank"`).
- **`[PILLAR]`**: Concrete structural column providing heavy cover (`"Pillar"`, `"Column"`).
- **`[BUFFET]` / Mid**: The central salad bar and warm buffet islands (`"Buffet"`, `"Salad"`, `"Mid"`).
- **`[KÜCHE]` / North**: Upper kitchen corridor ideal for long-range Rifle duels (`"Küche"`, `"Kitchen"`, `"North"`).
- **`[TABLES]` / South**: Great Polyterrasse dining hall with wooden table booths (`"Tables"`, `"Dining"`, `"South"`).
- **`[AUSGANG]` / Enemy**: East exit lobby and opponent spawn (`"Ausgang"`, `"Exit"`, `"Enemy base"`).

---

## 🧭 Perspective & Directional System

In *Tactical Squad Duel*, the map is **point-mirrored** ($180^\circ$ rotational symmetry):
- **Blue Team (Player 1)** defends on the left and attacks to the right.
- **Red Team (Player 2)** has their camera rotated $180^\circ$ so they **also** defend on the left and attack to the right on their screen!

### How Voice Commands Adapt:
- **"North" / "Up"**: Always means **UP** on your screen (towards the top corridor).
- **"South" / "Down"**: Always means **DOWN** on your screen (towards the bottom corridor).
- **"East" / "Advance" / "Forward"**: Always means **FORWARD towards the enemy**.
- **"West" / "Fall back" / "Retreat"**: Always means **BACK towards your home base**.
- **"Base"**: Always means **YOUR spawn**, regardless of which team you are on.
- **"Enemy"**: Always means the **OPPONENT'S spawn**.

---

## 🎧 HUD & Audio Feedback

The user interface keeps you informed of speech recognition in real time:

```
+-----------------------------------------------------------------------------------------+
| Blue (you)               Voice: "Alpha to Mid" · "Watch North" · "Squad Rush"           |
|                                                                                         |
|                                     [BATTLEFIELD]                                       |
|                                                                                         |
| [1 Alpha]   [2 Bravo]   [3 Charlie]        [W/E/R equipped abilities]          (o) Voice |
|   Rifle       SMG        Shotgun                                              heard: "" |
+-----------------------------------------------------------------------------------------+
```

1. **Microphone Indicator**:
   - 🟢 **Pulsing Green Circle**: Microphone is actively listening for your voice.
   - 🟡 **Yellow Circle**: Voice system is initializing or connecting.
   - ⚫ **Grey Circle**: Voice is disabled (press `V` to turn on).
2. **Transcript Feed**:
   - `heard: "alpha to mid"` displays the raw speech transcribed by the browser.
3. **Radio Chirp SFX**:
   - Every valid command triggers a crisp military comms sound.
4. **Combat Notification Banner**:
   - The top banner flashes confirmed orders:
     - `🎙️ [ALPHA] Move -> MID`
     - `🎙️ [SQUAD] RUSH`
     - `🎙️ [BRAVO] Watch NORTH`

---

## 💡 Tips for Reliable Voice Recognition

1. **Quiet Background**: Built-in laptop microphones work best in a relatively quiet room. A headset microphone provides near-100% recognition accuracy.
2. **Short & Crisp**: Say concise phrases:
   - *"Alpha to Mid"* is recognized faster than *"Could Alpha please move to the middle area"*.
3. **Compound Orders**: You can chain thoughts:
   - *"Alpha"* (pause 0.2s) *"Mid"*
   - *"Watch North"*
   - *"Cast fog"*
4. **Squad Formations**: Use squad orders to coordinate:
   - *"Squad advance to Mid"* sends all 3 soldiers toward the center in a staggered formation.
   - *"Stop"* halts all movement instantly if you hear gunfire.

---

## 💻 Developer Guide: Extending Voice Commands

### 1. Adding New Synonyms or Words
All voice vocabulary is centrally declared in [`scripts/config.gd`](file:///Users/cyrill/hackathon-game/scripts/config.gd):

```gdscript
const VOICE_CALLOUTS := {
    "mid": ["mid", "middle", "center", "centre"],
    "north": ["north", "top", "upper"],
    "window": ["window", "ledge", "balcony"], # Add custom landmark words here!
}
```

### 2. Adding Landmark Positions
Coordinates are defined in [`scripts/map_data.gd`](file:///Users/cyrill/hackathon-game/scripts/map_data.gd):

```gdscript
const CALLOUT_POSITIONS := {
    "mid": Vector2(20.0 * Cfg.TILE, 9.0 * Cfg.TILE),
    "window": Vector2(15.0 * Cfg.TILE, 3.0 * Cfg.TILE), # Team 0 pixel position
}
```
*Note: `callout_position()` automatically computes `Cfg.WORLD_SIZE - p` for Team 1.*

### 3. Grammar Parsing Logic
The multi-token grammar recognizer lives in [`scripts/client/voice.gd`](file:///Users/cyrill/hackathon-game/scripts/client/voice.gd):
- Strips punctuation and normalizes tokens.
- Extracts `subject`, `action`, and `param`.
- Emits `command_spoken(cmd)`.

### 4. Running the Voice Unit Tests
We maintain an automated unit test suite verifying phrase parsing without launching a browser or window:

```bash
godot --headless --path . --script res://tests/test_voice_parser.gd
```

Output:
```
  [PASS] alpha move to mid            -> type=2 subj=0 param=mid
  [PASS] bravo go to north            -> type=2 subj=1 param=north
  [PASS] charlie advance to choke     -> type=2 subj=2 param=choke
  [PASS] watch north                  -> type=4 subj=-2 param=north
  [PASS] cast fog                     -> type=7 subj=-2 param=0
  ...
Test results: 27 passed, 0 failed.
```
