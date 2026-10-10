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
	Ability.BREAK_MAGIC: {"name": "F*** Magic", "description": "First cast: dash into stick stance (+25% speed, -80% range, +200% damage for 3s). Recast: fire a huge 5x-damage projectile, jump backward without turning, return to the wand, and gain attack speed/range for 3s.", "mp_cost": 55.0, "cooldown": 8.0, "dash_duration": 0.12, "dash_distance": 105.0, "return_duration": 0.2, "return_distance": 120.0, "stick_speed_mult": 1.25, "stick_range_mult": 0.2, "stick_damage_mult": 3.0, "burst_duration": 3.0, "wand_rate_mult": 1.5, "wand_range_mult": 1.35, "return_projectile_damage_mult": 5.0, "return_projectile_radius": 18.0},
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
	Ability.SCAN: ["scan", "scans", "scanning", "scanner", "radar", "ping"],
	Ability.RUSH: ["rush", "rushing", "russia", "brush", "sprint", "go go"],
	Ability.OUTRAGE: ["outrage", "rage", "enrage", "fury"],
	Ability.FLASH: ["flash", "blink", "flash forward"],
	Ability.BREAK_MAGIC: ["break magic", "stick mode", "wand mode", "switch weapon"],
	Ability.FIREBALL: ["fireball", "fire ball", "cast fireball"],
	Ability.INVISIBLE: ["invisible", "invisibility", "vanish", "cloak"],
}

## Voice command vocabulary for 100% hands-free tactical control.
const VOICE_SUBJECTS := {
	0: ["alpha", "alfa", "one", "first", "rifle", "sniper"],
	1: ["bravo", "two", "second", "smg", "gunner"],
	2: ["charlie", "three", "third", "shotgun", "breacher"],
	3: ["delta", "four", "fourth", "marksman"],
	-1: ["squad", "all", "team", "everyone"],
}

const VOICE_CALLOUTS := {
	"mid": ["mid", "middle", "center", "centre", "buffet", "salad", "salad bar"],
	"north": ["north", "top", "upper", "kitchen", "kuche", "prep"],
	"south": ["south", "bottom", "lower", "dining", "tables", "terrasse", "polyterrasse"],
	"base": ["base", "home", "spawn", "entrance", "zugang", "west"],
	"yard": ["yard", "courtyard", "patio", "tray", "trays", "tablett"],
	"choke": ["choke", "door", "bridge", "gate", "kitchen door"],
	"flank": ["flank", "alley", "side", "kasse", "cashier", "checkout"],
	"pillar": ["pillar", "cover", "box", "rock", "column", "post"],
	"enemy": ["enemy", "enemy base", "their base", "exit", "ausgang", "east"],
}

const VOICE_DIRECTIONS := {
	"north": ["north", "up", "upward"],
	"south": ["south", "down", "downward"],
	"east": ["east", "forward", "front", "ahead", "right"],
	"west": ["west", "back", "rear", "behind", "left"],
}

const VOICE_ACTIONS := {
	"move": ["move to", "move", "go to", "go", "advance to", "advance", "run to", "run", "push to", "push", "walk to", "walk", "proceed to", "proceed", "step", "fall back to", "fall back", "retreat to", "retreat"],
	"watch": ["watch", "face", "look", "aim", "cover", "point", "hold angle"],
	"halt": ["stop", "halt", "hold position", "hold", "stay", "freeze", "cancel"],
	"deploy": ["deploy", "ready", "start", "play", "join"],
	"rematch": ["rematch", "play again", "again", "restart"],
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
