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
5. [Directions & Distance](#-directions--distance)
6. [Feedback: What You See](#-feedback-what-you-see)
7. [Multi-Tab Testing & Troubleshooting](#-multi-tab-testing--troubleshooting)
8. [Tips for Reliable Recognition](#-tips-for-reliable-recognition)
9. [Developer Guide](#-developer-guide)

---

## 🌐 Browser Setup & Microphone

Voice uses the browser **Web Speech API** through Godot's `JavaScriptBridge`.

- **Supported Browsers**: Google Chrome and Microsoft Edge (recommended), Safari.
  - *Note*: Firefox does not support the Web Speech API natively; use keyboard/mouse controls on Firefox.
- **Secure Context Required**: The browser microphone only activates on `http://localhost`, `http://127.0.0.1`, or `https://`.
- **Internet Connection**: Chrome's speech recognizer performs cloud-assisted processing and requires an active internet connection.

### Turning the Microphone On / Off
1. **Auto-Start**: The microphone automatically activates when you click **Deploy** (or press `Enter` / say *"deploy"*). Allow microphone permissions when prompted by your browser.
2. **Toggle Button / Key**: Press **V** or click the **Mic ON/OFF** button in the bottom-right corner to toggle listening at any time.

### Multi-Tab Mutex & Visibility Awareness
When testing a 1v1 match locally (e.g. via `./run_local.sh`), having two browser tabs open simultaneously could cause microphone contention and abort loops. The game resolves this automatically:
- **Tab Mutex**: A shared `localStorage` lock ensures only one browser tab actively consumes the microphone at a time.
- **Automatic Pause on Blur**: Switching to another tab or minimizing the window automatically pauses voice recognition in the hidden tab (`document.hidden`) and frees the microphone.
- **Automatic Resume on Focus**: Focusing the tab automatically reclaims the microphone lock.
- **Manual Claiming**: If a tab reports `mic in other tab (click Mic to claim)`, simply click the **Mic** button in that tab to forcefully claim the microphone.

---

## 🗣️ Command Grammar

Every voice utterance follows an intuitive tactical grammar:

```
[who]        [action]      [where / what]
 Bravo        go to         kitchen
 Charlie      watch         right
 Alpha        ability two   mid
 Squad        hold
```

### 1. Who (Target Soldier)
Specifies which squad member executes the command. If omitted, the command defaults to the **currently selected soldier**.

| Say | Soldier | Slot / Role |
|---|---|---|
| `Alpha`, `Alfa`, `Rifle`, `Sniper` | **Alpha** | 1 · Rifle |
| `Bravo`, `SMG`, `Gunner` | **Bravo** | 2 · SMG |
| `Charlie`, `Shotgun`, `Breacher` | **Charlie** | 3 · Shotgun |
| `Delta`, `Marksman` | **Delta** | 4 · Marksman |
| `One` / `Two` / `Three` / `Four` | **1**, **2**, **3**, **4** | Only recognized at the **start** of a phrase (e.g., `"two go left"`, `"select three"`), preventing `"to"` from misidentifying as soldier 2. |
| `Squad`, `Team`, `Everyone`, `All`, `All units` | **Entire Squad** | Directs all living squad members simultaneously. |
| *(nobody specified)* | **Selected Soldier** | Reuses the active selection or the soldier specified earlier in the phrase. |

> **Selection Note**: Naming an individual soldier automatically **selects** them, ensuring subsequent follow-ups (such as aiming or casting) originate from them. Squad commands do not change the active selection.

---

### 2. Chaining Orders & Sequential Queueing
Combine multiple tactical commands into a single breath using `and`, `then`, or `also`:
- **Chained Commands**:
  - `"Bravo go to kitchen and watch right"`
  - `"Alpha go to mid then Charlie go to tables"`
  - `"Squad rush and go forward"`
- **Subject Inheritance**: Later clauses without an explicit subject automatically inherit the previously named soldier.
- **Movement Queueing**: If multiple movement orders are issued to the **same** soldier in a single utterance, the second move is automatically **queued** to execute after the first completes:
  - `"Alpha fall back to base then go up a bit"` (walks to base first, then steps upward).
  - Moves issued to *different* soldiers execute concurrently without delay.
- **Compound Directions**: Natural phrases like `"up and left"` or `"down and right"` are parsed as single diagonal movement vectors rather than chained command splits.

---

## 📋 Command Cheat Sheet

| Category | Example Spoken Phrases | Action & Behavior |
|---|---|---|
| **Select Soldier** | `"Alpha"`, `"Bravo"`, `"Select four"`, `"Switch to Charlie"`, `"Two"` | Selects the corresponding squad member. |
| **Cycle Soldier** | `"Next"`, `"Cycle"`, `"Switch"` | Cycles forward to the next living squad member. |
| **Move to Callout** | `"Bravo go to kitchen"`, `"Charlie to tables"`, `"Delta move to buffet"`, `"Mid"` | Computes an A* navigation path to the named landmark. |
| **Squad Move** | `"Squad to mid"`, `"Everyone fall back to base"`, `"All push enemy tables"` | Moves the entire squad into a structured tactical formation around the target. |
| **Move in Direction** | `"Go left"`, `"Alpha move up"`, `"Advance"`, `"Push forward"`, `"Fall back"` | Moves in that screen direction until encountering an obstacle (default ~9 tiles / 288px). |
| **Distance Modifiers** | `"... a bit"`, `"step back"`, `"... slightly"` · `"... all the way"`, `"... far"` | Short step (~3 tiles / 96px) · Maximum step until wall contact (~2000px). |
| **Halt / Stop** | `"Stop"`, `"Halt"`, `"Hold"`, `"Alpha hold position"`, `"Squad freeze"` | Immediately cancels navigation paths and stops all movement. |
| **Aim / Watch Angle** | `"Watch left"`, `"Bravo face up"`, `"Alpha cover mid"`, `"Squad look at cashier"` | Locks firing cone towards that direction or callout. Retains facing while moving. |
| **Cast Fireball** | `"Fireball"`, `"Fireball mid"`, `"Charlie fireball the buffet"`, `"Fireball left"` | Blasts the target callout or direction (server clamps range to 320px). Walls block; friendly fire enabled. |
| **Cast Abilities by Name** | `"Fog"`, `"Scan"`, `"Rush"`, `"Outrage"`, `"Flash"`, `"Break magic"`, `"Invisible"` | Casts the equipped ability across all eligible living casters (respecting MP and cooldowns). |
| **Cast Abilities by Slot** | `"Spell one"`, `"Ability two"`, `"Slot three"`, `"Cast E"`, `"Cast W"`, `"Third spell"` | Casts the ability mapped to slot **W / E / R** of the named or selected caster. |
| **Targeted Spell Slots** | `"Spell two mid"`, `"Bravo second spell right"`, `"Cast E at enemy kitchen"` | Targets and casts the slotted spell towards a map landmark or screen direction. |
| **Match Flow** | `"Deploy"`, `"Join game"`, `"Rematch"`, `"Play again"`, `"One more"` | Deploys into the lobby or votes for a rematch post-game. |

---

## 🗺️ Map Callouts (Fixed Points)

The map features labelled visual badges for every strategic landmark. **The spoken name matches the map label exactly**.

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
             (Your Side: Blue)                    (Opponent Side: Red)
```

> **Symmetry Guarantee**: The ETH Polymensa map is point-mirrored, and Red's camera view is rotated $180^\circ$. Consequently, **every callout appears in the exact same screen location for both players**: your home base is always on the left, and the opponent is always on the right.

### Callout Dictionary & Synonyms

| Callout Label | Spoken Alternatives & Phonetic Synonyms | Enemy Twin Prefix (`enemy`, `their`, `opponent`) |
|---|---|---|
| `BASE` | `base`, `bass`, `home`, `spawn`, `entrance`, `zugang` | `"enemy base"`, `"their base"`, `"exit"`, `"ausgang"` |
| `KITCHEN` | `kitchen`, `kitchen door`, `prep`, `choke` | `"enemy kitchen"`, `"their kitchen"`, `"enemy choke"` |
| `BUFFET` | `buffet`, `buffets`, `grill`, `trays`, `tray`, `yard` | `"enemy buffet"`, `"their buffet"`, `"enemy grill"` |
| `CASHIER` | `cashier`, `cashiers`, `checkout`, `register`, `kasse`, `kassa`, `flank` | `"enemy cashier"`, `"their register"`, `"enemy kasse"` |
| `TABLES` | `tables`, `table`, `dining`, `dining hall` | `"enemy tables"`, `"their tables"`, `"enemy dining"` |
| `MID` | `mid`, `middle`, `center`, `centre`, `salad`, `salad bar` | *(Central landmark: neutral, no enemy prefix)* |
| `TOP LANE` | `top lane`, `toplane`, `upper lane`, `corridor`, `hallway` | *(Neutral lane: spans across map)* |
| `BOTTOM LANE`| `bottom lane`, `lower lane`, `terrace`, `window`, `windows` | *(Neutral lane: spans across map)* |

---

## 🧭 Directions & Distance

Directions are **screen-relative** and identical for both players:

| Spoken Direction | Screen Heading | Tactical Meaning |
|---|---|---|
| `up`, `north`, `top`, `upper`, `upward` | ↑ | North / Top of screen |
| `down`, `south`, `bottom`, `lower`, `downward` | ↓ | South / Bottom of screen |
| `right`, `east`, `forward`, `ahead`, `advance`, `push`, `front` | → | East / Towards enemy base |
| `left`, `west`, `back`, `backward`, `retreat`, `fall back`, `behind` | ← | West / Towards your home base |
| `northeast`, `northwest`, `southeast`, `southwest` | ↗, ↖, ↘, ↙ | Diagonals |
| `up and right`, `down and left`, etc. | ↗, ↙ | Combined directional phrasing |

### Stepping Distances
- **Default Step**: ~9 tiles ($288\text{ px}$). The soldier walks in the chosen direction and halts at obstacles.
- **Short Step** (`"a bit"`, `"a little"`, `"slightly"`, `"step"`, `"inch"`): ~3 tiles ($96\text{ px}$).
- **Full / Max Distance** (`"all the way"`, `"far"`, `"full"`, `"until the wall"`, `"max"`): Moves up to $2000\text{ px}$, stopping only when colliding with walls.

---

## 🎧 Feedback: What You See

### 1. In-Game Voice HUD Panel (Bottom-Right)
Active whenever the microphone is enabled:
- **Header State**: Displays real-time recognizer health:
  - `LISTENING`: Active and waiting for speech.
  - `HEARING YOU`: Audio detected; displays live animated volume bars.
  - `PAUSED (BACKGROUND TAB)`: Microphone relinquished because tab lost focus.
  - `MIC IN OTHER TAB`: Another local tab has claimed the audio device.
  - `MIC BLOCKED` / `NO MICROPHONE`: Permission or hardware issue.
- **Live Interim Line** (Yellow): Displays words being recognized incrementally in real time.
- **Utterance History**: Shows the last 4 utterances, their recognized action tags (e.g. `> BRAVO MOVE > KITCHEN + BRAVO WATCH RIGHT`), and elapsed age. Fades out after 9 seconds. Unrecognized phrases show `not a command`.

### 2. Tactical Map Overlay
- **Pings**: A tactical green circle and label appears at order destinations (movement targets, watched callouts, or targeted spells).
- **Movement Trails**: Dashed visual trajectories render for all moving soldiers, indicating active navigation paths.
- **Sound Feedback**: A crisp tactical radio chirp plays whenever a voice order is recognized and issued.

---

## 🧪 Multi-Tab Testing & Troubleshooting

When developing locally with two tabs (Blue vs Red):

| Symptom | Cause | Solution |
|---|---|---|
| Panel displays `mic in other tab` | Another tab holds the localStorage mutex. | Click the **Mic ON/OFF** button in the current tab to claim mic focus immediately. |
| Panel displays `paused (background tab)` | The browser tab is hidden or minimized. | Click into the tab or bring it to the foreground; recognition will resume within 250ms. |
| Panel displays `mic blocked` | Browser denied microphone permission. | Click the lock/tune icon in the browser address bar, set Microphone to **Allow**, and reload. |
| Commands not recognized on Firefox | Firefox lacks Web Speech API support. | Use Google Chrome, Microsoft Edge, or Safari. Use keyboard fallbacks (`W`, `E`, `R`, `1`-`4`) on Firefox. |
| Console error `aborted` | Rapid browser microphone recreation. | The voice system automatically applies exponential backoff and locks to stabilize Chrome. |

### Inspecting Recognition in DevTools
Press `F12` or `Cmd+Option+I` to view the browser console. The built-in `[TSD Voice]` logger outputs:
```text
[TSD Voice] recognition active in tab 4k7a9x, session 1
[TSD Voice] audio/speech detected!
[TSD Voice] heard: bravo go to kitchen (final=false)
[TSD Voice] heard: bravo go to kitchen and watch right (final=true)
```

---

## 💡 Tips for Reliable Recognition

1. **Keep Commands Concise**: Short phrases recognize faster and with higher accuracy. `"Bravo kitchen"` works just as reliably as `"Bravo, please move to the kitchen"`.
2. **Use Callout Names Directly**: Saying `"Mid"` or `"Cashier"` immediately moves your currently selected soldier without requiring prefix verbs.
3. **Headset Recommendations**: Built-in laptop microphones often capture game sound effects or echo. A headset mic provides the best speech recognition.
4. **Interim Execution**: Single-stage orders (such as directional movement or callout moves) execute as soon as the speech stream stabilizes for $0.4\text{ seconds}$—you do not have to wait for the browser to finalize the sentence. Untargeted spell orders like `"fireball"` wait briefly for an optional target callout before defaulting.

---

## 💻 Developer Guide

### Architecture & Source Files
- [`scripts/config.gd`](file:///Users/cyrill/hackathon-game/scripts/config.gd): Vocabulary dictionaries:
  - `VOICE_SUBJECTS` & `VOICE_SUBJECT_NUMBERS`: Soldier mappings (`Alpha` through `Delta`, `Squad`, numbers `1`-`4`).
  - `CALLOUTS`: Landmark positions, badge names, and phonetic word lists.
  - `VOICE_DIRECTIONS` & `VOICE_DIRECTION_VECTORS`: Screen-space directional mappings.
  - `VOICE_PHRASES`: Ability names and phonetic mishearings.
  - `VOICE_SPELL_NOUNS` & `VOICE_SPELL_SLOTS`: Slotted spell triggers (`W`, `E`, `R`).
  - `VOICE_ACTIONS`: Command verbs (`watch`, `halt`, `deploy`, `rematch`, etc.).
- [`scripts/client/voice.gd`](file:///Users/cyrill/hackathon-game/scripts/client/voice.gd):
  - JavaScript Web Speech bridge (`JS_SETUP`) with localStorage tab mutex and visibility awareness.
  - Dynamic result queueing, interim stability timer (`INTERIM_STABLE_S = 0.4`), and grammar parser (`parse_utterance`, `parse_voice`).
- [`scripts/client/client_game.gd`](file:///Users/cyrill/hackathon-game/scripts/client/client_game.gd):
  - `_on_voice_command`: Maps parsed voice payloads into game server RPCs (`c_unit_move`, `c_unit_face`, `c_unit_stop`, `c_ability`).
  - Handles squad formation spreading and queued path generation.

### Running Headless Parser Tests
Verify all grammar rules, phonetic aliases, spell slot bindings, and callout coordinates without opening a Godot window:

```bash
# Locate Godot via the project helper:
GODOT=$(bash -c 'source tools/godot_path.sh; find_godot')

# Run the test suite:
$GODOT --headless --path . --script res://tests/test_voice_parser.gd
```
*(If `godot` is already in your system PATH, simply run `godot --headless --path . --script res://tests/test_voice_parser.gd`)*.

### Simulating Speech in Browser DevTools
Simulate speech inputs directly inside the browser console without a microphone:
```javascript
window.tsdVoice.queue.push({
  key: 'test:1',
  alts: ['charlie go to tables and watch right'],
  final: true
});
```

### In-Engine Debug Injection
In Godot GDScript or during automated bot matches:
```gdscript
# Directly inject spoken text:
Voice.inject("bravo go to kitchen")

# Or run client with the --say flag:
godot --path . -- --auto --name=Blue "--say=bravo go to kitchen;squad watch right;fireball mid"
```
