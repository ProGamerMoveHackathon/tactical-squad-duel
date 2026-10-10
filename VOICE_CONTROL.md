# 🎙️ Voice Control & Tactical Command Guide

> **Tactical Squad Duel** can be played completely hands-free: select soldiers, send them to named places on the map, steer them in a direction, aim, and fire abilities, all by speaking.
>
> Mouse and keyboard keep working at all times.

---

## 📑 Table of Contents
1. [Browser Setup & Microphone](#-browser-setup--microphone)
2. [Command Grammar](#-command-grammar)
3. [Command Cheat Sheet](#-command-cheat-sheet)
4. [Map Callouts (Fixed Points)](#-map-callouts-fixed-points)
5. [Directions](#-directions)
6. [Feedback: What You See](#-feedback-what-you-see)
7. [Tips for Reliable Recognition](#-tips-for-reliable-recognition)
8. [Developer Guide](#-developer-guide)

---

## 🌐 Browser Setup & Microphone

Voice uses the browser **Web Speech API** through Godot's `JavaScriptBridge`.

- **Supported**: Google Chrome and Microsoft Edge (recommended), Safari. Firefox has no Web Speech API, so use the keyboard there.
- **Secure context required**: the mic only works on `http://localhost` or `https://`.
- Chrome's recognizer runs in the cloud, so it needs an internet connection.

**Turning it on**
1. The mic starts automatically when you click **Deploy**. Allow the microphone when the browser asks.
2. Press **V** or click **Mic ON/OFF** (bottom-right) to toggle listening at any time.

---

## 🗣️ Command Grammar

```
[who]  [action]  [where]
 Bravo   go to    kitchen
```

**Who** (optional)
| Say | Soldier |
|---|---|
| `Alpha`, `Rifle`, `Sniper` | 1 · Rifle |
| `Bravo`, `SMG`, `Gunner` | 2 · SMG |
| `Charlie`, `Shotgun`, `Breacher` | 3 · Shotgun |
| `Squad`, `Team`, `Everyone`, `All` | all living soldiers |
| `One` / `Two` / `Three` | only at the **start** (`"two, go left"`), because recognizers often write "to" as "two" |
| *(nobody)* | the currently selected soldier |

Naming a single soldier also **selects** them, so a follow-up like `"fireball mid"` is aimed from the soldier you just talked to. Squad orders don't change the selection. Abilities are always cast by every living squad member that has them equipped and enough MP.

**Chaining**: join orders with `and` / `then`. An order without a name reuses the last soldier you named, and a second move for the same soldier is **queued** after the first:
- `"Bravo go to kitchen and watch right"`
- `"Alpha fall back to base then go up a bit"` (walks to base first, then up)
- `"Alpha go to mid then Charlie go to tables"`

---

## 📋 Command Cheat Sheet

| Category | Example phrases | What happens |
|---|---|---|
| **Select** | `"Alpha"`, `"Select three"`, `"Switch to Charlie"`, `"Next"` | Selects that soldier (`next` cycles). |
| **Go to a callout** | `"Bravo go to kitchen"`, `"Squad to mid"`, `"Charlie push enemy tables"` | A* path to the named point. Squads spread into a small formation. |
| **Move in a direction** | `"Go left"`, `"Alpha move up"`, `"Advance"`, `"Fall back"`, `"Bravo go up and right"` | Walks that way until a wall (max ~9 tiles). If blocked right away, paths around the obstacle. |
| **Distance** | `"... a bit"` / `"step back"` · `"... all the way"` / `"far"` | Short step (~3 tiles) · go until the wall. |
| **Stop** | `"Stop"`, `"Halt"`, `"Alpha hold"`, `"Squad hold position"` | Cancels the path immediately. |
| **Watch / aim** | `"Watch left"`, `"Bravo face up"`, `"Alpha cover mid"`, `"Squad look at the cashier"`, `"Turn right"` | Locks the firing cone toward a direction or callout. Moving keeps the angle. |
| **Fireball** | `"Fireball"`, `"Fireball mid"`, `"Charlie fireball the buffet"`, `"Fireball left"` | At a callout, in a direction, or 160px ahead (server clamps cast range). |
| **Other abilities** | `"Fog"`, `"Scan"`, `"Rush"` / `"Sprint"`, `"Outrage"`, `"Flash"`, `"Break magic"`, `"Invisible"` | Casts the equipped ability for every eligible squad member, with server-side MP and cooldown checks. |
| **Match flow** | `"Deploy"` (menu), `"Rematch"` / `"Play again"` | Join or vote for a rematch. |

---

## 🗺️ Map Callouts (Fixed Points)

Every callout is drawn on the map as a labelled badge, and **the label is exactly what you say**. Your own half is blue. The **enemy twins** on the far half are red and are addressed with `enemy` / `their`: `"enemy kitchen"`, `"their tables"`.

```
+------------------------------------------------------------------------+
|                              [TOP LANE]                                |
|        [KITCHEN]                                    [ENEMY TABLES]     |
|                                                                        |
|        [BUFFET]                                     [ENEMY CASHIER]    |
| [BASE]                         [MID]                       [ENEMY BASE]|
|                [CASHIER]                            [ENEMY BUFFET]     |
|                                                                        |
|        [TABLES]                                     [ENEMY KITCHEN]    |
|                             [BOTTOM LANE]                             |
+------------------------------------------------------------------------+
            (you)                                  (opponent)
```

| Callout | Also understood as |
|---|---|
| `BASE` | home, spawn, entrance, zugang |
| `KITCHEN` | kitchen door, prep, choke |
| `BUFFET` | grill, trays, yard |
| `CASHIER` | checkout, register, kasse, flank |
| `TABLES` | table, dining, dining hall |
| `MID` | middle, center, salad, salad bar |
| `TOP LANE` | upper lane, corridor, hallway |
| `BOTTOM LANE` | lower lane, terrace, window(s) |
| `ENEMY BASE` | enemy, exit, ausgang, enemy spawn |

The map is point-mirrored and Red's camera is rotated 180°, so **every callout sits at the same spot on both players' screens**: your base is always on the left.

---

## 🧭 Directions

Directions are **screen-relative** and mean the same thing for both teams:

| Say | Direction on your screen |
|---|---|
| `up`, `north`, `top` | ↑ |
| `down`, `south`, `bottom` | ↓ |
| `right`, `east`, `forward`, `advance`, `push`, `ahead` | → toward the enemy |
| `left`, `west`, `back`, `fall back`, `retreat` | ← toward your base |
| `up right`, `northeast`, `down and left`, ... | diagonals |

---

## 🎧 Feedback: What You See

**Voice panel (bottom-right of the battlefield)**, visible while the mic is on:
- Header: mic state (`LISTENING`, or `HEARING YOU` with animated level bars while you speak).
- **Live line** (yellow): the words being recognised right now, as you say them.
- **History**: your last 3 utterances, each with the orders they produced (`> BRAVO MOVE > KITCHEN  +  BRAVO WATCH RIGHT`) or `not a command`. Entries fade after ~9s.
- When idle it cycles example phrases. If the mic is blocked, it tells you how to fix it.

**On the map**
- A green ping marks every voice order (the destination, the watched callout, or the fireball target), with the callout name.
- Dashed lines show where each soldier is walking, not just the selected one.

**Bottom bar**: mic status, a **Mic ON/OFF** button, and the enemies-alive counter. A radio chirp plays for every recognised order.

---

## 💡 Tips for Reliable Recognition

1. Use a headset mic in noisy rooms. Laptop mics also pick up teammates talking.
2. Short phrases work best: `"Bravo kitchen"` is as good as `"Bravo, please go to the kitchen"`.
3. Orders fire as soon as your words have been stable for ~0.4s, so you don't have to wait for the browser to finish a sentence. A target-less `"fireball ..."` waits for the end of the sentence so it can pick up the target.
4. If something is misheard, check the voice panel to see exactly what the browser heard.

---

## 💻 Developer Guide

### Vocabulary and callouts
Everything lives in [`scripts/config.gd`](scripts/config.gd):
- `VOICE_SUBJECTS`, `VOICE_SUBJECT_NUMBERS`: who.
- `CALLOUTS`: named map points (`label`, `tile` position from Blue's view, `mirror` for an enemy twin, spoken `words`). Badges, parser and positions all read from this table.
- `VOICE_DIRECTIONS`, `VOICE_PHRASES` (abilities), `VOICE_ACTIONS` (watch / halt / next / distance / deploy / rematch).

Phrases match on whole words and the **longest phrase wins** (`"kitchen door"` beats `"kitchen"`, `"play again"` beats `"play"`). The test suite checks that every callout sits on open floor.

### Code map
- [`scripts/client/voice.gd`](scripts/client/voice.gd): Web Speech bridge, interim/final result handling, transcript history, and the static grammar parser (`parse_utterance`, `parse_voice`).
- [`scripts/client/client_game.gd`](scripts/client/client_game.gd): `_on_voice_command` turns commands into server RPCs (`c_unit_move`, `c_unit_face`, `c_unit_stop`, `c_ability`), plus direction walking and squad formation.
- [`scripts/client/hud.gd`](scripts/client/hud.gd): voice panel. [`scripts/client/entity_view.gd`](scripts/client/entity_view.gd): callout badges and voice pings.

### Testing without a microphone
```bash
# Parser unit tests (no window)
godot --headless --path . --script res://tests/test_voice_parser.gd

# Native client that "speaks" a list of commands once the match runs
godot --path . -- --auto --name=Blue "--say=bravo go to kitchen;squad watch right;fireball mid"
```
In the browser console you can also simulate the recognizer:
```js
tsdVoice.queue.push({key: 'test:1', alts: ['charlie go to tables'], final: true})
```
