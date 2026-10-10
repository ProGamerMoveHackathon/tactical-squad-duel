extends RefCounted
## Shared game constants (used by both the authoritative server and the client).
## Access via: const Cfg = preload("res://scripts/config.gd")

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 2
const SQUAD_SIZE := 3

const TILE := 32
const MAP_W := 40
const MAP_H := 22
const WORLD_SIZE := Vector2(MAP_W * TILE, MAP_H * TILE)

# --- Soldiers -------------------------------------------------------------
const SOLDIER_RADIUS := 11.0
const SOLDIER_HP := 100
const MOVE_SPEED := 120.0              # px / s
const TURN_SPEED := deg_to_rad(540.0)  # rad / s
## If true, a soldier that was moving keeps walking to its destination after the
## player switches to another soldier. If false it stops immediately.
const CONTINUE_MOVE_WHEN_DESELECTED := true

# --- Vision ---------------------------------------------------------------
const VIEW_RANGE := 420.0
const VIEW_CONE := deg_to_rad(120.0)   # full angle
const AWARE_RADIUS := 64.0             # 360 degree "hearing" radius
const SMOKE_SEE_DEPTH := 22.0          # how far you can see into a smoke cloud

# --- Weapons --------------------------------------------------------------
enum Weapon { RIFLE, SMG, SHOTGUN }
const WEAPONS := {
	Weapon.RIFLE: {"name": "Rifle", "range": 400.0, "cone": 18.0, "interval": 0.60, "damage": 34, "pellets": 1, "accuracy": 0.92},
	Weapon.SMG: {"name": "SMG", "range": 290.0, "cone": 44.0, "interval": 0.13, "damage": 8, "pellets": 1, "accuracy": 0.72},
	Weapon.SHOTGUN: {"name": "Shotgun", "range": 175.0, "cone": 66.0, "interval": 0.90, "damage": 10, "pellets": 6, "accuracy": 0.62},
}
## Weapon of each squad slot (same for both teams).
const SQUAD_WEAPONS := [Weapon.RIFLE, Weapon.SMG, Weapon.SHOTGUN]
const REACTION_TIME := 0.22  # delay before a soldier opens fire on a newly acquired target

# --- Abilities ------------------------------------------------------------
enum Ability { SMOKE, SCAN, SUPPRESS, RUSH }
const ABILITIES := {
	Ability.SMOKE: {"name": "Smoke", "key": "Q", "cooldown": 22.0, "duration": 9.0, "radius": 74.0, "throw_range": 340.0},
	Ability.SCAN: {"name": "Scan", "key": "E", "cooldown": 18.0, "duration": 2.5, "radius": 460.0},
	Ability.SUPPRESS: {"name": "Suppress", "key": "R", "cooldown": 20.0, "duration": 6.0, "cone_mult": 1.8, "accuracy_mult": 0.55, "rate_mult": 1.3},
	Ability.RUSH: {"name": "Rush", "key": "F", "cooldown": 16.0, "duration": 4.0, "speed_mult": 1.65},
}
## Spoken phrases that trigger each ability (lower-case, matched as whole words /
## word sequences). Includes a few common speech-recognition mishearings.
const VOICE_PHRASES := {
	Ability.SMOKE: ["smoke", "smoked", "smokes", "smoking", "smog", "smoky"],
	Ability.SCAN: ["scan", "scans", "scanning", "scanner", "radar", "ping"],
	Ability.SUPPRESS: ["suppress", "suppressing", "suppression", "surpress", "oppress", "cover fire", "covering fire"],
	Ability.RUSH: ["rush", "rushing", "russia", "brush", "sprint", "go go"],
}
## Recently moved enemies are what "Scan" reveals.
const SCAN_MOVE_MEMORY := 1.5

# --- Match ----------------------------------------------------------------
const COUNTDOWN := 3.0

enum State { WAITING, COUNTDOWN, PLAYING, ENDED }

const TEAM_COLORS := [Color(0.30, 0.65, 1.0), Color(1.0, 0.38, 0.32)]
const TEAM_NAMES := ["Blue", "Red"]


static func weapon_cone(weapon: int, suppressed: bool) -> float:
	var c: float = deg_to_rad(WEAPONS[weapon]["cone"])
	if suppressed:
		c = min(c * ABILITIES[Ability.SUPPRESS]["cone_mult"], VIEW_CONE)
	return c
