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
enum Ability { FOG, SCAN, SUPPRESS, RUSH }
const ABILITIES := {
	Ability.FOG: {"name": "Fog", "mp_cost": 50.0, "cooldown": 10.0, "duration": 9.0, "radius": 74.0, "throw_distance": 96.0},
	Ability.SCAN: {"name": "Scan", "mp_cost": 35.0, "cooldown": 7.0, "duration": 2.5, "radius": 460.0},
	Ability.SUPPRESS: {"name": "Suppress", "mp_cost": 70.0, "cooldown": 12.0, "duration": 6.0, "cone_mult": 1.8, "accuracy_mult": 0.55, "rate_mult": 1.3},
	Ability.RUSH: {"name": "Rush", "mp_cost": 45.0, "cooldown": 9.0, "duration": 4.0, "speed_mult": 1.65},
}
## Three equipped abilities per squad member. Bit N corresponds to Ability N.
const DEFAULT_LOADOUTS := [7, 13, 11, 14]
const ABILITY_SLOT_KEYS := ["W", "E", "R"]
## Spoken phrases that trigger each ability (lower-case, matched as whole words /
## word sequences). Includes a few common speech-recognition mishearings.
const VOICE_PHRASES := {
	Ability.FOG: ["fog", "fog magic", "cast fog", "summon fog", "mist", "cast mist"],
	Ability.SCAN: ["scan", "scans", "scanning", "scanner", "radar", "ping"],
	Ability.SUPPRESS: ["suppress", "suppressing", "suppression", "surpress", "oppress", "cover fire", "covering fire"],
	Ability.RUSH: ["rush", "rushing", "russia", "brush", "sprint", "go go"],
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


static func weapon_cone(weapon: int, suppressed: bool) -> float:
	var c: float = deg_to_rad(WEAPONS[weapon]["cone"])
	if suppressed:
		c = min(c * ABILITIES[Ability.SUPPRESS]["cone_mult"], VIEW_CONE)
	return c
