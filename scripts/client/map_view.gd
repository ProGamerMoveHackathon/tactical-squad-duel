extends Node2D
## Authentic ETH Zürich Polymensa architectural map rendering:
## - North Zone: Stainless steel kitchen, cold storage, food prep & dishwashing
## - Center Zone: Free-Flow servery with Warm Buffet, Salad Bar, and Cashier counters
## - South Zone: Mensa dining hall with oak tables, chairs, Mensa trays & Polyterrasse windows
## - West/East Lobbies: "Zugang Free Flow" and "Ausgang Free Flow" with team runners

const Cfg = preload("res://scripts/config.gd")

var map  # MapData
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


func _draw() -> void:
	if map == null:
		return
	var T := Cfg.TILE
	var W := Cfg.MAP_W
	var H := Cfg.MAP_H

	# 1. Base floor zones (determined symmetrically by tile zone)
	for y in H:
		for x in W:
			var r := Rect2(x * T, y * T, T, T)
			var z: int = map.tile_zone(x, y)
			if z == map.Zone.KITCHEN:
				# Kitchen & prep area (Commercial non-slip slate/blue tile)
				var base_col := Color(0.20, 0.23, 0.27)
				if (x + y) % 2 == 0:
					base_col = Color(0.22, 0.25, 0.29)
				draw_rect(r, base_col)
				# Subtle tile grout
				draw_rect(r, Color(0.16, 0.18, 0.22, 0.4), false, 1.0)
			elif z == map.Zone.SERVERY:
				# Free-Flow Servery & Cashier Zone (Polished light terrazzo)
				var base_col := Color(0.23, 0.25, 0.27)
				if (x + y) % 2 == 0:
					base_col = Color(0.25, 0.27, 0.29)
				draw_rect(r, base_col)
			else:
				# Polymensa Dining Hall (Warm oak wood parquet)
				var base_col := Color(0.27, 0.22, 0.17)
				if (x + y) % 2 == 0:
					base_col = Color(0.29, 0.24, 0.18)
				draw_rect(r, base_col)
				# Parquet plank lines
				draw_line(Vector2(x * T, y * T + T * 0.5), Vector2((x + 1) * T, y * T + T * 0.5), Color(0.22, 0.18, 0.14, 0.3), 1.0)

	# 2. Spawn entrance / exit runners (Lobbies)
	# West: Zugang Free Flow (Blue team)
	draw_rect(Rect2(T, 6 * T, 3 * T, 10 * T), Color(Cfg.TEAM_COLORS[0], 0.08))
	draw_rect(Rect2(T, 6 * T, 3 * T, 10 * T), Color(Cfg.TEAM_COLORS[0], 0.25), false, 1.5)
	# East: Ausgang Free Flow (Red team)
	draw_rect(Rect2(Cfg.WORLD_SIZE.x - 4 * T, 6 * T, 3 * T, 10 * T), Color(Cfg.TEAM_COLORS[1], 0.08))
	draw_rect(Rect2(Cfg.WORLD_SIZE.x - 4 * T, 6 * T, 3 * T, 10 * T), Color(Cfg.TEAM_COLORS[1], 0.25), false, 1.5)

	# 3. Architectural Tray Guide Rails (Metallic rails along buffet counters)
	draw_line(Vector2(3 * T, 8.5 * T), Vector2(17 * T, 8.5 * T), Color(0.65, 0.70, 0.75, 0.5), 2.0)
	draw_line(Vector2(3 * T, 8.7 * T), Vector2(17 * T, 8.7 * T), Color(0.65, 0.70, 0.75, 0.3), 1.0)
	draw_line(Vector2(23 * T, 8.5 * T), Vector2(37 * T, 8.5 * T), Color(0.65, 0.70, 0.75, 0.5), 2.0)
	draw_line(Vector2(23 * T, 8.7 * T), Vector2(37 * T, 8.7 * T), Color(0.65, 0.70, 0.75, 0.3), 1.0)

	# 4. Floor Decals & Blueprint Text
	if font:
		# Centre Hall Blueprint Header
		draw_string(font, Vector2(Cfg.WORLD_SIZE.x * 0.5 - 130, 8.0 * T), "ETH ZÜRICH · POLYMENSA", HORIZONTAL_ALIGNMENT_CENTER, 260, 16, Color(1, 1, 1, 0.12))
		draw_string(font, Vector2(Cfg.WORLD_SIZE.x * 0.5 - 120, 8.5 * T + 4), "GESCHOSS F · FREIFLÄCHE GASTRONOMIE", HORIZONTAL_ALIGNMENT_CENTER, 240, 10, Color(1, 1, 1, 0.07))
		draw_string(font, Vector2(Cfg.WORLD_SIZE.x * 0.5 - 120, 13.5 * T), "— POLYTERRASSE MENSA-SAAL —", HORIZONTAL_ALIGNMENT_CENTER, 240, 12, Color(1, 1, 1, 0.10))

		# West Lobby: Zugang
		draw_string(font, Vector2(1.5 * T, 6.5 * T), "ZUGANG FREE FLOW ↓", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.75, 1.0, 0.35))
		draw_string(font, Vector2(1.5 * T, 16.5 * T), "TREPPENHAUS WEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.15))

		# East Lobby: Ausgang
		draw_string(font, Vector2(34.5 * T, 6.5 * T), "AUSGANG FREE FLOW ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.5, 0.4, 0.35))
		draw_string(font, Vector2(34.5 * T, 16.5 * T), "TREPPENHAUS OST", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.15))

		# Stations
		draw_string(font, Vector2(3.5 * T, 2.5 * T), "KÜCHE / FOOD PREP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.12))
		draw_string(font, Vector2(4.0 * T, 10.0 * T), "WARMBUFFET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.75, 0.3, 0.3))
		draw_string(font, Vector2(11.0 * T, 10.0 * T), "GRILL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.75, 0.3, 0.3))
		draw_string(font, Vector2(18.0 * T, 10.5 * T), "SALATBAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.9, 0.5, 0.35))
		draw_string(font, Vector2(13.0 * T, 12.8 * T), "KASSE 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.2))
		draw_string(font, Vector2(25.5 * T, 12.8 * T), "KASSE 2", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.2))

		# Dining Hall Labels
		draw_string(font, Vector2(6.0 * T, 16.7 * T), "TISCHE 1-6 (SAAL SÜD)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.12))
		draw_string(font, Vector2(24.0 * T, 5.7 * T), "TISCHE 7-12 (SAAL NORD)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.12))

	# 5. Panoramic Terrace Cafe Seating (Bistro tables & stools along the windows)
	for bx in [6, 11, 16]:
		_draw_terrace_bistro_set(Vector2(bx * T + T * 0.5, 19.5 * T), bx)
	for bx in [23, 28, 33]:
		_draw_terrace_bistro_set(Vector2(bx * T + T * 0.5, 1.5 * T), bx + 10)

	# 6. Chairs around Dining Tables (drawn before tabletops so seats tuck under tables)
	for y in H:
		for x in W:
			if map.is_table_tile(x, y):
				_draw_chairs_for_table_tile(x, y)

	# 7. Wall, Buffet & Table Shadows
	for y in H:
		for x in W:
			if map.is_wall_tile(x, y):
				draw_rect(Rect2(x * T + 4, y * T + 5, T, T), Color(0, 0, 0, 0.35))

	# 8. Walls, Buffets, Kitchen Counters & Dining Tables
	for y in H:
		for x in W:
			if not map.is_wall_tile(x, y):
				continue
			var r := Rect2(x * T, y * T, T, T)

			if y == 0 or y == H - 1 or x == 0 or x == W - 1:
				# Outer perimeter concrete walls
				draw_rect(r, Color(0.35, 0.37, 0.40))
				_draw_bevel(r, Color(0.50, 0.52, 0.56), Color(0.22, 0.23, 0.25))

			elif map.is_table_tile(x, y):
				# Mensa Dining Tables (Swiss oak, placemats, trays, food, drinks)
				_draw_dining_table(r, x, y)

			else:
				var z: int = map.tile_zone(x, y)
				if z == map.Zone.KITCHEN:
					# Kitchen counters & stainless equipment
					draw_rect(r, Color(0.46, 0.50, 0.54))
					_draw_bevel(r, Color(0.68, 0.72, 0.76), Color(0.28, 0.30, 0.33))
					# Stainless steel surface detail
					draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(T - 6, T - 6)), Color(0.42, 0.46, 0.50))
					draw_line(r.position + Vector2(5, 5), r.position + Vector2(T - 5, 5), Color(0.65, 0.70, 0.75, 0.4), 1.0)
				else:
					# Free-Flow Buffet & Salad Bar Islands
					var is_salad := (x >= 17 and x <= 22)
					var top_col := Color(0.36, 0.55, 0.42) if is_salad else Color(0.50, 0.42, 0.34)
					draw_rect(r, Color(0.38, 0.40, 0.44))
					draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(T - 4, T - 4)), top_col)
					_draw_bevel(r, Color(0.70, 0.65, 0.55), Color(0.22, 0.20, 0.18))
					# Warm buffet heat lamp glow
					if not is_salad:
						draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(T - 8, 4)), Color(1.0, 0.7, 0.2, 0.4))
					else:
						draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(T - 8, T - 8)), Color(0.25, 0.8, 0.4, 0.2))

	# 9. Window Mullions along South and North Facades
	for x in range(2, W - 2):
		var wx := x * T
		var wy := (H - 1) * T
		draw_rect(Rect2(wx + 2, wy + 2, T - 4, 3), Color(0.35, 0.65, 0.90, 0.7))
		draw_line(Vector2(wx + T * 0.5, wy), Vector2(wx + T * 0.5, wy + 5), Color(0.7, 0.8, 0.9, 0.8), 1.0)


func _draw_chairs_for_table_tile(x: int, y: int) -> void:
	var T := Cfg.TILE
	# North edge chairs (facing South into table)
	if not map.is_table_tile(x, y - 1):
		_draw_chair(Vector2(x * T + 8.0, y * T - 4.0), Vector2(0, 1), x * 7 + y * 3 + 1)
		_draw_chair(Vector2(x * T + 24.0, y * T - 4.0), Vector2(0, 1), x * 7 + y * 3 + 2)

	# South edge chairs (facing North into table)
	if not map.is_table_tile(x, y + 1):
		_draw_chair(Vector2(x * T + 8.0, (y + 1) * T + 4.0), Vector2(0, -1), x * 7 + y * 3 + 3)
		_draw_chair(Vector2(x * T + 24.0, (y + 1) * T + 4.0), Vector2(0, -1), x * 7 + y * 3 + 4)

	# West edge chair (facing East into table)
	if not map.is_table_tile(x - 1, y):
		_draw_chair(Vector2(x * T - 4.0, y * T + 16.0), Vector2(1, 0), x * 7 + y * 3 + 5)

	# East edge chair (facing West into table)
	if not map.is_table_tile(x + 1, y):
		_draw_chair(Vector2((x + 1) * T + 4.0, y * T + 16.0), Vector2(-1, 0), x * 7 + y * 3 + 6)


func _draw_chair(pos: Vector2, facing_dir: Vector2, seed_val: int) -> void:
	# Subtle natural jitter (chair slightly angled or pulled out)
	var jitter_angle := (float((seed_val * 17) % 7) - 3.0) * 0.03
	var jitter_offset := Vector2(float((seed_val * 13) % 5) - 2.0, float((seed_val * 11) % 5) - 2.0) * 0.35
	var p := pos + jitter_offset
	var angle := facing_dir.angle() + jitter_angle

	# Chair contact shadow on floor
	draw_circle(p + Vector2(1.0, 1.5), 5.5, Color(0, 0, 0, 0.28))

	draw_set_transform(p, angle)

	# 4 tubular steel frame corners
	draw_circle(Vector2(-4.5, -4.5), 1.0, Color(0.16, 0.16, 0.18))
	draw_circle(Vector2(-4.5, 4.5), 1.0, Color(0.16, 0.16, 0.18))
	draw_circle(Vector2(3.5, -4.5), 1.0, Color(0.16, 0.16, 0.18))
	draw_circle(Vector2(3.5, 4.5), 1.0, Color(0.16, 0.16, 0.18))

	# Molded Swiss canteen seat (beech wood or dark anthracite)
	var seat_col := Color(0.62, 0.46, 0.30) if seed_val % 2 == 0 else Color(0.56, 0.42, 0.28)
	draw_rect(Rect2(-4.5, -5.0, 8.5, 10.0), seat_col)
	draw_rect(Rect2(-4.5, -5.0, 8.5, 10.0), seat_col.lightened(0.18), false, 1.0)

	# Curved ergonomic backrest along rear (-X)
	draw_line(Vector2(-5.5, -5.5), Vector2(-5.5, 5.5), Color(0.35, 0.24, 0.14), 2.5)
	draw_line(Vector2(-5.5, -5.0), Vector2(-5.5, 5.0), Color(0.75, 0.58, 0.38), 1.2)

	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_dining_table(r: Rect2, x: int, y: int) -> void:
	var T := Cfg.TILE

	# Solid oak base
	var base_wood := Color(0.50, 0.36, 0.22)
	draw_rect(r, base_wood)

	# Inset tabletop
	var top_wood := Color(0.60, 0.44, 0.28)
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(T - 4, T - 4)), top_wood)

	# Wood grain lines across tabletop
	draw_line(r.position + Vector2(3, 10), r.position + Vector2(T - 3, 10), Color(0.52, 0.38, 0.24, 0.35), 1.0)
	draw_line(r.position + Vector2(3, 16), r.position + Vector2(T - 3, 16), Color(0.48, 0.34, 0.20, 0.35), 1.0)
	draw_line(r.position + Vector2(3, 22), r.position + Vector2(T - 3, 22), Color(0.52, 0.38, 0.24, 0.35), 1.0)

	# Outer edge bevel
	_draw_bevel(r, Color(0.72, 0.56, 0.38), Color(0.32, 0.22, 0.14))

	# Mensa Trays & Dining items
	var tray_cols := [Color(0.75, 0.24, 0.22), Color(0.24, 0.38, 0.62), Color(0.38, 0.40, 0.42)]
	var t_seed := (x * 11 + y * 17)

	# Tray 1 (North side of table)
	var t1_pos := r.position + Vector2(3, 4)
	var t1_col: Color = tray_cols[t_seed % 3]
	_draw_mensa_tray(t1_pos, t1_col, t_seed)

	# Tray 2 (South side of table)
	var t2_pos := r.position + Vector2(15, 17)
	var t2_col: Color = tray_cols[(t_seed + 1) % 3]
	_draw_mensa_tray(t2_pos, t2_col, t_seed + 1)

	# Center accents: salt & pepper shakers, table order QR code
	draw_circle(r.position + Vector2(15.0, 15.0), 1.2, Color(0.95, 0.95, 0.95, 0.9))
	draw_circle(r.position + Vector2(17.5, 15.0), 1.2, Color(0.18, 0.18, 0.18, 0.9))
	draw_rect(Rect2(r.position + Vector2(6, 15), Vector2(4, 4)), Color(0.9, 0.9, 0.9, 0.6))
	draw_rect(Rect2(r.position + Vector2(7, 16), Vector2(2, 2)), Color(0.15, 0.15, 0.15, 0.7))


func _draw_mensa_tray(pos: Vector2, tray_col: Color, seed_val: int) -> void:
	# Tray rim & base (13px wide x 10px high)
	draw_rect(Rect2(pos, Vector2(13, 10)), tray_col)
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(11, 8)), tray_col.darkened(0.15))
	draw_rect(Rect2(pos, Vector2(13, 10)), Color(1, 1, 1, 0.18), false, 1.0)

	# White porcelain plate
	draw_circle(pos + Vector2(5.5, 5.0), 3.2, Color(0.94, 0.94, 0.92))
	draw_circle(pos + Vector2(5.5, 5.0), 2.2, Color(0.88, 0.88, 0.86))
	# Meal accent (pasta/curry/salad)
	var meal_cols := [Color(0.85, 0.52, 0.22), Color(0.38, 0.75, 0.32), Color(0.82, 0.30, 0.22)]
	draw_circle(pos + Vector2(5.5, 5.0), 1.4, meal_cols[seed_val % 3])

	# Cutlery (silver fork/knife line)
	draw_line(pos + Vector2(1.5, 2.0), pos + Vector2(1.5, 8.0), Color(0.85, 0.85, 0.88), 0.8)

	# Drink glass / water cup (translucent glass blue)
	draw_circle(pos + Vector2(10.5, 3.0), 1.6, Color(0.45, 0.80, 0.95, 0.85))

	# Paper napkin
	draw_rect(Rect2(pos + Vector2(9.5, 6.0), Vector2(2.5, 2.5)), Color(0.95, 0.95, 0.95, 0.75))


func _draw_terrace_bistro_set(center: Vector2, seed_val: int) -> void:
	# Soft floor shadow
	draw_circle(center + Vector2(1.5, 2.0), 8.5, Color(0, 0, 0, 0.25))

	# 3 round wooden bar stools around the table
	for i in 3:
		var a := float(i) * TAU / 3.0 + float(seed_val) * 0.4
		var sp := center + Vector2.from_angle(a) * 13.0
		draw_circle(sp + Vector2(1, 1.5), 3.5, Color(0, 0, 0, 0.22))
		draw_circle(sp, 3.5, Color(0.22, 0.22, 0.25))
		draw_circle(sp, 2.8, Color(0.62, 0.46, 0.30))
		draw_arc(sp, 2.8, 0.0, TAU, 12, Color(0.72, 0.56, 0.38), 0.8)

	# Round cafe table (radius 8px)
	draw_circle(center, 8.0, Color(0.55, 0.40, 0.26))
	draw_arc(center, 8.0, 0.0, TAU, 24, Color(0.75, 0.78, 0.82), 1.2) # Chrome rim
	draw_circle(center, 6.5, Color(0.58, 0.42, 0.28))

	# Espresso cup & saucer
	draw_circle(center + Vector2(-1.5, -1.0), 2.0, Color(0.92, 0.92, 0.92))
	draw_circle(center + Vector2(-1.5, -1.0), 1.2, Color(0.30, 0.18, 0.10))


func _draw_bevel(r: Rect2, light: Color, dark: Color) -> void:
	var T := Cfg.TILE
	var x := int(r.position.x / T)
	var y := int(r.position.y / T)
	if not map.is_wall_tile(x, y - 1):
		draw_rect(Rect2(r.position, Vector2(T, 3)), light)
	if not map.is_wall_tile(x - 1, y):
		draw_rect(Rect2(r.position, Vector2(3, T)), light.darkened(0.1))
	if not map.is_wall_tile(x, y + 1):
		draw_rect(Rect2(r.position + Vector2(0, T - 3), Vector2(T, 3)), dark)
	if not map.is_wall_tile(x + 1, y):
		draw_rect(Rect2(r.position + Vector2(T - 3, 0), Vector2(3, T)), dark.lightened(0.05))
