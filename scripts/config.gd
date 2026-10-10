extends RefCounted
## Shared game constants (used by both the authoritative server and the client).
## Access via: const Cfg = preload("res://scripts/config.gd")

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 2
const SQUAD_SIZE := 4

const TILE := 32
const MAP_W := 40
const MAP_H := 22
const WORLD_SIZE := Vector2(MAP_W * TILE, MAP_H * TILE)

# --- Soldiers -------------------------------------------------------------
const SOLDIER_RADIUS := 11.0
const SOLDIER_HP := 100
const SOLDIER_MP := 100.0
const MP_RECOVERY_TIME := 16.0
const MP_RESTORE_PER_DAMAGE := 0.35
const HEALTH_REGEN_DELAY := 10.0
const HEALTH_REGEN_RATE := 5.0
const MOVE_SPEED := 120.0              # px / s
const TURN_SPEED := deg_to_rad(540.0)  # rad / s
## If true, a soldier that was moving keeps walking to its destination after the
## player switches to another soldier. If false it stops immediately.
const CONTINUE_MOVE_WHEN_DESELECTED := true

# --- Vision ---------------------------------------------------------------
const VIEW_RANGE := 420.0
const VIEW_CONE := deg_to_rad(120.0)   # full angle
const AWARE_RADIUS := 64.0             # 360 degree "hearing" radius
const FOG_SEE_DEPTH := 22.0            # how far you can see into a fog cloud

# --- Weapons --------------------------------------------------------------
enum Weapon { RIFLE, SMG, SHOTGUN }
const WEAPONS := {
	Weapon.RIFLE: {"name": "Arc Bolt", "range": 400.0, "cone": 18.0, "interval": 0.60, "damage": 34, "pellets": 1, "accuracy": 0.92},
	Weapon.SMG: {"name": "Volley", "range": 290.0, "cone": 44.0, "interval": 0.13, "damage": 8, "pellets": 1, "accuracy": 0.72},
	Weapon.SHOTGUN: {"name": "Prism", "range": 175.0, "cone": 66.0, "interval": 0.90, "damage": 10, "pellets": 6, "accuracy": 0.62},
}
## Weapon of each squad slot (same for both teams).
const SQUAD_WEAPONS := [Weapon.RIFLE, Weapon.SMG, Weapon.SHOTGUN, Weapon.RIFLE]
const REACTION_TIME := 0.22  # delay before a soldier opens fire on a newly acquired target

# --- Abilities ------------------------------------------------------------
enum Ability { FOG, SCAN, RUSH, OUTRAGE, FLASH, BREAK_MAGIC, FIREBALL, INVISIBLE }
const ABILITY_COUNT := 8
const ABILITIES := {
	Ability.FOG: {"name": "Fog", "description": "Creates a vision-blocking fog cloud in front of each caster.", "mp_cost": 50.0, "cooldown": 10.0, "duration": 9.0, "radius": 74.0, "throw_distance": 96.0},
	Ability.SCAN: {"name": "Scan", "description": "Reveals recently moving enemies near each caster.", "mp_cost": 35.0, "cooldown": 7.0, "duration": 2.5, "radius": 460.0},
	Ability.RUSH: {"name": "Rush", "description": "Increases movement speed by 65% for 4 seconds.", "mp_cost": 45.0, "cooldown": 9.0, "duration": 4.0, "speed_mult": 1.65},
	Ability.OUTRAGE: {"name": "Outrage", "description": "Doubles attack speed and reduces damage taken by 20% for 2 seconds.", "mp_cost": 60.0, "cooldown": 12.0, "duration": 2.0, "rate_mult": 2.0, "damage_taken_mult": 0.8},
	Ability.FLASH: {"name": "Flash", "description": "Blinks forward in 0.1 seconds and grants invulnerability during the blink.", "mp_cost": 45.0, "cooldown": 8.0, "duration": 0.1, "distance": 150.0},
	Ability.BREAK_MAGIC: {"name": "F*** Magic", "description": "First cast: dash into stick stance (+25% speed, -80% range, +200% damage for 3s). Recast: fire a huge 5x-damage projectile, jump backward, and return to the wand.", "mp_cost": 55.0, "cooldown": 8.0, "dash_duration": 0.12, "dash_distance": 105.0, "return_duration": 0.2, "return_distance": 120.0, "stick_speed_mult": 1.25, "stick_range_mult": 0.2, "stick_damage_mult": 3.0, "burst_duration": 3.0, "wand_rate_mult": 1.5, "wand_range_mult": 1.35, "return_projectile_damage_mult": 5.0, "return_projectile_radius": 18.0},
	Ability.FIREBALL: {"name": "Fireball", "description": "Blasts the selected area for damage and knockback. Walls block it; friendly fire is enabled.", "mp_cost": 70.0, "cooldown": 13.0, "cast_range": 320.0, "radius": 78.0, "damage": 42, "knockback": 76.0},
	Ability.INVISIBLE: {"name": "Invisible", "description": "Become invisible and move 50% faster for 5 seconds. Dealing damage ends the effect.", "mp_cost": 65.0, "cooldown": 16.0, "duration": 5.0, "speed_mult": 1.5},
}
## Three equipped abilities per squad member. Bit N corresponds to Ability N.
const DEFAULT_LOADOUTS := [67, 28, 97, 134]
const ABILITY_SLOT_KEYS := ["W", "E", "R"]
## Spoken phrases that trigger each ability (lower-case, matched as whole words /
## word sequences). Includes a few common speech-recognition mishearings.
const VOICE_PHRASES := {
	Ability.FOG: ["fog", "fog magic", "cast fog", "summon fog", "mist", "cast mist"],
	Ability.SCAN: ["scan", "scans", "scanning", "scanner", "radar", "ping", "sonar", "pulse"],
	Ability.RUSH: ["rush", "rushing", "russia", "brush", "sprint", "dash", "boost", "go go"],
	Ability.OUTRAGE: ["outrage", "rage", "enrage", "fury"],
	Ability.FLASH: ["flash", "blink", "flash forward"],
	Ability.BREAK_MAGIC: ["break magic", "stick mode", "wand mode", "switch weapon"],
	Ability.FIREBALL: ["fireball", "fire ball", "cast fireball"],
	Ability.INVISIBLE: ["invisible", "invisibility", "vanish", "cloak"],
}

# --- Voice command vocabulary ------------------------------------------------
# Grammar: [who] [action] [where]. Every list is matched on whole words and the
# longest phrase wins, so "kitchen door" beats "kitchen" and "play again" beats "play".

const VOICE_SUBJECTS := {
	0: ["alpha", "alfa", "alpher", "rifle", "sniper"],
	1: ["bravo", "brava", "bravos", "smg", "s m g", "gunner"],
	2: ["charlie", "charley", "charly", "shotgun", "shot gun", "breacher"],
	3: ["delta", "delter", "marksman"],
	-1: ["squad", "everyone", "everybody", "team", "all units", "all"],
}
## Number words only count as a soldier when they open the command ("two, go left")
## because recognisers constantly write "to" as "two" / "2".
const VOICE_SUBJECT_NUMBERS := {
	0: ["one", "1", "first"],
	1: ["two", "2", "second"],
	2: ["three", "3", "third"],
	3: ["four", "4", "fourth"],
}

## Named map points. `tile` is in tiles from Blue's point of view; Red gets the
## point-mirrored spot, so every callout sits at the same place on both players'
## screens. `mirror` callouts also get an "enemy <name>" twin on the far half.
## The label is drawn on the map and is exactly what the player should say.
const CALLOUTS := {
	"base": {"label": "BASE", "tile": Vector2(3.5, 11.0), "mirror": true,
		"words": ["base", "bass", "home", "spawn", "entrance", "zugang"]},
	"kitchen": {"label": "KITCHEN", "tile": Vector2(9.5, 5.5), "mirror": true,
		"words": ["kitchen", "kitchen door", "prep", "choke"]},
	"buffet": {"label": "BUFFET", "tile": Vector2(9.5, 9.5), "mirror": true,
		"words": ["buffet", "buffets", "grill", "trays", "tray", "yard"]},
	"cashier": {"label": "CASHIER", "tile": Vector2(14.0, 12.5), "mirror": true,
		"words": ["cashier", "cashiers", "checkout", "register", "kasse", "kassa", "flank"]},
	"tables": {"label": "TABLES", "tile": Vector2(9.5, 16.5), "mirror": true,
		"words": ["tables", "table", "dining", "dining hall"]},
	"mid": {"label": "MID", "tile": Vector2(20.0, 11.0), "mirror": false,
		"words": ["mid", "middle", "center", "centre", "salad", "salad bar"]},
	"top_lane": {"label": "TOP LANE", "tile": Vector2(20.0, 1.5), "mirror": false,
		"words": ["top lane", "toplane", "upper lane", "corridor", "hallway"]},
	"bottom_lane": {"label": "BOTTOM LANE", "tile": Vector2(20.0, 19.5), "mirror": false,
		"words": ["bottom lane", "lower lane", "terrace", "window", "windows"]},
}
## "enemy kitchen", "their tables", ... address the mirrored twin of a callout.
const VOICE_ENEMY_PREFIXES := ["enemy", "enemies", "their", "opponent", "opponents"]
## Extra ways to say the enemy spawn (the twin of "base").
const VOICE_ENEMY_BASE_WORDS := ["enemy", "exit", "ausgang", "enemy spawn"]

## Screen-relative directions (x = right / towards the enemy, y = down).
## Both players see their base on the left, so these mean the same for both teams.
const VOICE_DIRECTIONS := {
	"n": ["north", "up", "upward", "upwards", "top", "upper"],
	"s": ["south", "down", "downward", "downwards", "bottom", "lower"],
	"e": ["east", "right", "forward", "forwards", "ahead", "advance", "push", "front", "onward"],
	"w": ["west", "left", "back", "backward", "backwards", "retreat", "fall back", "rear", "behind"],
	"ne": ["northeast"],
	"nw": ["northwest"],
	"se": ["southeast"],
	"sw": ["southwest"],
}
const VOICE_DIRECTION_VECTORS := {
	"n": Vector2(0, -1), "s": Vector2(0, 1), "e": Vector2(1, 0), "w": Vector2(-1, 0),
	"ne": Vector2(1, -1), "nw": Vector2(-1, -1), "se": Vector2(1, 1), "sw": Vector2(-1, 1),
}
## How far a direction order walks (px). Soldiers stop early at walls.
const VOICE_STEP := 288.0
const VOICE_STEP_SHORT := 96.0
const VOICE_STEP_FAR := 2000.0

const VOICE_ACTIONS := {
	"watch": ["watch", "look", "face", "aim", "cover", "check", "guard", "eyes on", "point", "turn"],
	"halt": ["stop", "halt", "hold", "hold position", "freeze", "stay", "wait", "stand still", "cancel"],
	"next": ["next", "cycle", "switch"],
	"select": ["select", "switch to", "unit", "soldier", "number"],
	"short": ["a bit", "a little", "little", "bit", "slightly", "step", "inch"],
	"far": ["far", "all the way", "full", "until the wall", "max"],
	"deploy": ["deploy", "join game", "start game", "lets go", "let s go"],
	"rematch": ["rematch", "play again", "new match", "new game", "one more"],
}
## Recently moved enemies are what "Scan" reveals.
const SCAN_MOVE_MEMORY := 1.5

# --- Match ----------------------------------------------------------------
const COUNTDOWN := 3.0
const DEPLOYMENT_DURATION := 2.4

enum State { WAITING, LOADOUT, DEPLOYMENT, COUNTDOWN, PLAYING, ENDED }

const TEAM_COLORS := [Color(0.30, 0.65, 1.0), Color(1.0, 0.38, 0.32)]
const TEAM_NAMES := ["Blue", "Red"]


static func weapon_cone(weapon: int) -> float:
	return deg_to_rad(WEAPONS[weapon]["cone"])
