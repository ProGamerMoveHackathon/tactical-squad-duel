extends Node2D
## Draws all dynamic world entities: soldiers, firing cones, tracers, smoke,
## scan pings, damage indicators. Lives inside the (possibly rotated) World node.

const Cfg = preload("res://scripts/config.gd")

var game  # ClientGame
var font: Font
var soldier_texture: Texture2D
var soldier_textures: Array[Texture2D] = []


func _ready() -> void:
	font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists("res://assets/magic_student_sprites.png"):
		soldier_texture = load("res://assets/magic_student_sprites.png")
		for idx in Cfg.SQUAD_SIZE:
			var region := AtlasTexture.new()
			region.atlas = soldier_texture
			region.region = Rect2(Vector2(idx % 3, idx / 3) * 512.0, Vector2(512, 512))
			soldier_textures.append(region)


func _process(_dt: float) -> void:
	queue_redraw()


func _team_color(team: int) -> Color:
	return Cfg.TEAM_COLORS[team]


func _draw() -> void:
	if game == null or game.slot < 0:
		return
	var my_team: int = game.slot
	var enemy_team: int = 1 - my_team
	var now: float = game.time
	var smokes: Array = game.smoke_list()

	# Corpses
	for c in game.corpses:
		var col: Color = _team_color(c["team"]).darkened(0.5)
		var p: Vector2 = c["pos"]
		if not soldier_textures.is_empty():
			var corpse_texture := soldier_textures[int(c.get("idx", 0)) % soldier_textures.size()]
			draw_set_transform(p, c.get("facing", 0.0), Vector2.ONE)
			draw_texture_rect(corpse_texture, Rect2(-24, -18, 48, 36), false, Color(0.3, 0.25, 0.25, 0.55))
			draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_circle(p, 9.0, Color(0.25, 0.05, 0.05, 0.6))
		draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), col, 2.5)
		draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), col, 2.5)

	const POLY_BADGES := {
		"base": "ZUGANG",
		"yard": "TRAYS",
		"choke": "CHOKE",
		"flank": "KASSE",
		"pillar": "PILLAR",
		"mid": "BUFFET",
		"north": "KÜCHE",
		"south": "TABLES",
		"enemy": "AUSGANG",
	}
	# Tactical Callout Landmarks (always visible for voice navigation)
	for cid in game.map.CALLOUT_POSITIONS:
		var cp: Vector2 = game.map.callout_position(cid, my_team)
		_draw_callout_badge(cp, POLY_BADGES.get(cid, cid.to_upper()))

	# Own firing cones (clipped by walls / smoke)
	for o in game.own:
		if not o["alive"]:
			continue
		var is_sel: bool = o["idx"] == game.selected
		var weapon: int = Cfg.SQUAD_WEAPONS[o["idx"]]
		var suppressed: bool = o["flags"] & 2 != 0
		var a := 0.20 if is_sel else 0.09
		var col: Color = Color(1.0, 0.85, 0.3) if suppressed else _team_color(my_team)
		_draw_cone(o["disp"], o["disp_facing"], Cfg.weapon_cone(weapon, suppressed), Cfg.WEAPONS[weapon]["range"], Color(col, a), Color(col, a + 0.25), smokes)

	# Visible enemy cones
	for idx in game.enemies:
		var e: Dictionary = game.enemies[idx]
		var weapon: int = Cfg.SQUAD_WEAPONS[idx]
		var suppressed: bool = e["flags"] & 2 != 0
		_draw_cone(e["disp"], e["disp_facing"], Cfg.weapon_cone(weapon, suppressed), Cfg.WEAPONS[weapon]["range"], Color(_team_color(enemy_team), 0.08), Color(_team_color(enemy_team), 0.3), smokes)

	# Selected soldier path / watch direction
	if game.selected >= 0 and game.selected < game.own.size():
		var o: Dictionary = game.own[game.selected]
		if o["alive"]:
			var tgt: Vector2 = o["target"]
			if tgt.distance_to(o["disp"]) > 4.0:
				_draw_dashed(o["disp"], tgt, Color(1, 1, 1, 0.45))
				draw_arc(tgt, 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 2.0)
			if o["watch"] != INF:
				var wp: Vector2 = o["disp"] + Vector2.from_angle(o["watch"]) * 46.0
				draw_line(o["disp"] + Vector2.from_angle(o["watch"]) * 30.0, wp, Color(1, 1, 0.6, 0.8), 2.0)
				draw_circle(wp, 3.0, Color(1, 1, 0.6, 0.8))

	# Last-known enemy positions (ghosts)
	for g in game.ghosts:
		var k: float = clampf(g["t"] / 2.0, 0.0, 1.0)
		draw_arc(g["pos"], Cfg.SOLDIER_RADIUS, 0.0, TAU, 20, Color(_team_color(enemy_team), 0.5 * k), 2.0)
		_draw_label(g["pos"] + Vector2(0, -1), "?", Color(1, 1, 1, 0.6 * k), 12)

	# Scan pings (enemies revealed by Scan)
	for s in game.scanned:
		var p: Vector2 = s[1]
		var pulse := 0.5 + 0.5 * sin(now * 10.0)
		draw_arc(p, 14.0 + pulse * 6.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.3, 0.9), 2.0)
		draw_circle(p, 4.0, Color(1.0, 0.3, 0.3, 0.9))
	for fx in game.scan_fx:
		var k: float = 1.0 - fx["t"] / fx["max"]
		draw_arc(fx["origin"], fx["radius"] * k, 0.0, TAU, 96, Color(0.4, 1.0, 0.7, 0.6 * (1.0 - k)), 3.0)

	# Enemies
	for idx in game.enemies:
		var e: Dictionary = game.enemies[idx]
		_draw_soldier(e["disp"], e["disp_facing"], enemy_team, idx, e["hp"], e["flags"], false)

	# Own soldiers
	for o in game.own:
		if o["alive"]:
			_draw_soldier(o["disp"], o["disp_facing"], my_team, o["idx"], o["hp"], o["flags"], o["idx"] == game.selected)

	# Tracers & muzzle flashes
	for tr in game.tracers:
		var k: float = tr["t"] / tr["max"]
		draw_line(tr["a"], tr["b"], Color(tr["color"], k), 2.0)
		if tr["flash"]:
			draw_circle(tr["a"], 5.0 * k + 1.0, Color(1.0, 0.9, 0.5, k))
		if tr["hit"]:
			draw_circle(tr["b"], 3.0, Color(1.0, 0.2, 0.2, k))

	# Smoke clouds
	for sm in game.smokes:
		var p: Vector2 = sm[0]
		var r: float = sm[1]
		var t_left: float = sm[2]
		var fade := clampf(t_left / 1.0, 0.0, 1.0)
		for i in 5:
			var rr := r * (1.0 - i * 0.15)
			var wob := Vector2(sin(now * 0.7 + i * 1.7), cos(now * 0.6 + i * 2.3)) * 4.0
			draw_circle(p + wob, rr, Color(0.72, 0.74, 0.76, 0.22 * fade))
		draw_circle(p, r * 0.45, Color(0.8, 0.82, 0.84, 0.35 * fade))

	# Incoming-fire indicators from hidden shooters
	for h in game.hurts:
		if h["idx"] >= game.own.size():
			continue
		var o: Dictionary = game.own[h["idx"]]
		if not o["alive"]:
			continue
		var k: float = h["t"] / 1.2
		var col := Color(1.0, 0.15, 0.1, k) if h["dmg"] > 0 else Color(1.0, 0.7, 0.2, k * 0.8)
		var ang: float = h["angle"]
		draw_arc(o["disp"], 24.0, ang - 0.45, ang + 0.45, 12, col, 4.0)
		var tip: Vector2 = o["disp"] + Vector2.from_angle(ang) * 34.0
		draw_primitive(PackedVector2Array([tip, o["disp"] + Vector2.from_angle(ang - 0.18) * 27.0, o["disp"] + Vector2.from_angle(ang + 0.18) * 27.0]), PackedColorArray([col, col, col]), PackedVector2Array())


func _draw_soldier(p: Vector2, facing: float, team: int, idx: int, hp: int, flags: int, is_sel: bool) -> void:
	var col := _team_color(team)
	var weapon: int = Cfg.SQUAD_WEAPONS[idx]
	var r := Cfg.SOLDIER_RADIUS

	# Selection highlight ring (pulsing)
	if is_sel:
		var pulse := 0.5 + 0.5 * sin(game.time * 6.0)
		draw_arc(p, r + 7.0 + pulse * 2.5, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.5)

	# Rush speed lines behind unit
	if flags & 4 != 0:  # rush
		var back := Vector2.from_angle(facing + PI)
		for i in 3:
			draw_line(p + back * (r + 3 + i * 4) + back.orthogonal() * (i - 1) * 5.0, p + back * (r + 10 + i * 4) + back.orthogonal() * (i - 1) * 5.0, Color(0.6, 1.0, 0.9, 0.7), 2.0)

	# Shadow
	draw_circle(p + Vector2(2, 3), r + 2.0, Color(0, 0, 0, 0.35))

	# Team identification base ring
	draw_circle(p, r + 2.0, Color(col.r, col.g, col.b, 0.35))
	draw_arc(p, r + 2.5, 0.0, TAU, 32, col, 2.0)

	if not soldier_textures.is_empty():
		# Each squad slot has a matching modern-student portrait and overhead sprite.
		var sprite_mod := Color(0.92, 0.96, 1.0) if team == 0 else Color(1.0, 0.88, 0.88)
		draw_set_transform(p, facing, Vector2.ONE)
		draw_texture_rect(soldier_textures[idx % soldier_textures.size()], Rect2(-24, -18, 48, 36), false, sprite_mod)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		# Fallback geometric soldier
		var dir := Vector2.from_angle(facing)
		var gun_len := 20.0
		var gun_w := 4.0
		match weapon:
			Cfg.Weapon.RIFLE:
				gun_len = 24.0
				gun_w = 3.0
			Cfg.Weapon.SHOTGUN:
				gun_len = 17.0
				gun_w = 6.0
		draw_line(p + dir * 4.0, p + dir * gun_len, Color(0.12, 0.12, 0.14), gun_w + 2.0)
		draw_line(p + dir * 4.0, p + dir * gun_len, Color(0.35, 0.35, 0.38), gun_w)
		draw_circle(p, r, col.darkened(0.25))
		draw_circle(p, r - 3.0, col)
		draw_circle(p + dir * 2.0, 4.5, col.lightened(0.35))

	# Health ring
	var frac := clampf(hp / float(Cfg.SOLDIER_HP), 0.0, 1.0)
	draw_arc(p, r + 3.0, 0.0, TAU, 32, Color(0, 0, 0, 0.55), 3.0)
	var hp_col := Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.25, 0.2), 1.0 - frac)
	if frac > 0.0:
		draw_arc(p, r + 3.0, -PI * 0.5 - game.world_rotation, -PI * 0.5 - game.world_rotation + TAU * frac, 32, hp_col, 3.0)

	if flags & 2 != 0:  # suppress
		draw_arc(p, r + 7.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3, 0.7), 2.0)

	# Label (counter-rotated so text is always upright)
	var label: String = str(idx + 1) if team == game.slot else ["A", "B", "C"][idx]
	draw_circle(p + Vector2(0, 1), 6.5, Color(0, 0, 0, 0.55))
	_draw_label(p + Vector2(0, 2), label, Color.WHITE, 11)


func _draw_label(p: Vector2, text: String, col: Color, size: int) -> void:
	draw_set_transform(p, -game.world_rotation)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_cone(origin: Vector2, facing: float, cone: float, radius: float, fill: Color, line: Color, smokes: Array) -> void:
	var steps := maxi(3, int(ceil(cone / deg_to_rad(3.0))))
	var pts := PackedVector2Array([origin])
	for i in steps + 1:
		var a := facing - cone * 0.5 + cone * float(i) / steps
		var d := Vector2.from_angle(a)
		pts.append(origin + d * game.map.sight_distance(origin, d, radius, smokes))
	var cols := PackedColorArray([fill, fill, fill])
	for i in steps:
		draw_primitive(PackedVector2Array([pts[0], pts[i + 1], pts[i + 2]]), cols, PackedVector2Array())
	draw_line(origin, pts[1], line, 1.0)
	draw_line(origin, pts[pts.size() - 1], line, 1.0)


func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	var d := (b - a) / length
	var t := 0.0
	while t < length:
		draw_line(a + d * t, a + d * minf(t + 8.0, length), col, 2.0)
		t += 14.0


func _draw_callout_badge(p: Vector2, text: String) -> void:
	var col := Color(0.4, 0.78, 1.0, 0.5)
	draw_circle(p, 2.5, col)
	draw_arc(p, 8.0, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.25), 1.0)
	_draw_label(p + Vector2(0, -12), "[" + text + "]", col, 10)
