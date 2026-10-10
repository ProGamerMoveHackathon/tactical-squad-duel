extends Node2D
## Authentic ETH Zürich Polymensa architectural map rendering:
## - North Zone: Stainless steel kitchen, cold storage, food prep & dishwashing
## - Center Zone: Free-Flow servery with Warm Buffet, Salad Bar, and Cashier counters
## - South Zone: Mensa dining hall with oak tables, structural pillars & Polyterrasse windows
## - West/East Lobbies: "Zugang Free Flow" and "Ausgang Free Flow" with team runners

const Cfg = preload("res://scripts/config.gd")

var map  # MapData
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


func _draw() -> void:
	var T := Cfg.TILE
	var W := Cfg.MAP_W
	var H := Cfg.MAP_H

	# 1. Base floor zones
	for y in H:
		for x in W:
			var r := Rect2(x * T, y * T, T, T)
			if y <= 6:
				# Kitchen & prep area (Commercial slate/blue tile)
				var base_col := Color(0.20, 0.23, 0.27)
				if (x + y) % 2 == 0:
					base_col = Color(0.22, 0.25, 0.29)
				draw_rect(r, base_col)
				# Subtle tile grout
				draw_rect(r, Color(0.16, 0.18, 0.22, 0.4), false, 1.0)
			elif y <= 13:
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

	# 5. Wall & Furniture Shadows
	for y in H:
		for x in W:
			if map.is_wall_tile(x, y):
				draw_rect(Rect2(x * T + 4, y * T + 5, T, T), Color(0, 0, 0, 0.35))

	# 6. Walls, Buffets, Tables & Architecture
	for y in H:
		for x in W:
			if not map.is_wall_tile(x, y):
				continue
			var r := Rect2(x * T, y * T, T, T)

			if y == 0 or y == H - 1 or x == 0 or x == W - 1:
				# Outer perimeter concrete walls
				draw_rect(r, Color(0.35, 0.37, 0.40))
				_draw_bevel(r, Color(0.50, 0.52, 0.56), Color(0.22, 0.23, 0.25))

			elif y <= 6:
				# Kitchen counters & stainless equipment
				draw_rect(r, Color(0.46, 0.50, 0.54))
				_draw_bevel(r, Color(0.68, 0.72, 0.76), Color(0.28, 0.30, 0.33))
				# Stainless steel surface detail
				draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(T - 6, T - 6)), Color(0.42, 0.46, 0.50))
				draw_line(r.position + Vector2(5, 5), r.position + Vector2(T - 5, 5), Color(0.65, 0.70, 0.75, 0.4), 1.0)

			elif y <= 13:
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

			else:
				# Dining Hall Tables (Wood booths)
				draw_rect(r, Color(0.52, 0.38, 0.24))
				_draw_bevel(r, Color(0.68, 0.52, 0.35), Color(0.32, 0.22, 0.14))
				# Tabletop inlay with white placemats
				draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(T - 8, T - 8)), Color(0.48, 0.35, 0.22))
				draw_rect(Rect2(r.position + Vector2(6, 6), Vector2(6, 6)), Color(0.9, 0.9, 0.88, 0.6))
				draw_rect(Rect2(r.position + Vector2(T - 12, T - 12), Vector2(6, 6)), Color(0.9, 0.9, 0.88, 0.6))

	# 7. South Facade Window Mullions (Polyterrasse view promenade)
	for x in range(2, W - 2):
		var wx := x * T
		var wy := (H - 1) * T
		draw_rect(Rect2(wx + 2, wy + 2, T - 4, 3), Color(0.35, 0.65, 0.90, 0.7))
		draw_line(Vector2(wx + T * 0.5, wy), Vector2(wx + T * 0.5, wy + 5), Color(0.7, 0.8, 0.9, 0.8), 1.0)


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
