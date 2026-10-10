extends Node2D
## Static map rendering: floor, grid and walls.

const Cfg = preload("res://scripts/config.gd")

var map  # MapData


func _draw() -> void:
	var T := Cfg.TILE
	draw_rect(Rect2(Vector2.ZERO, Cfg.WORLD_SIZE), Color(0.17, 0.19, 0.17))
	# Floor checker
	for y in Cfg.MAP_H:
		for x in Cfg.MAP_W:
			if (x + y) % 2 == 0 and not map.is_wall_tile(x, y):
				draw_rect(Rect2(x * T, y * T, T, T), Color(0.19, 0.21, 0.19))
	# Spawn zones
	draw_rect(Rect2(T, 6 * T, 3 * T, 10 * T), Color(Cfg.TEAM_COLORS[0], 0.07))
	draw_rect(Rect2(Cfg.WORLD_SIZE.x - 4 * T, 6 * T, 3 * T, 10 * T), Color(Cfg.TEAM_COLORS[1], 0.07))
	# Centre marker
	draw_arc(Cfg.WORLD_SIZE * 0.5, 90.0, 0.0, TAU, 48, Color(1, 1, 1, 0.05), 2.0)
	# Wall shadows
	for y in Cfg.MAP_H:
		for x in Cfg.MAP_W:
			if map.is_wall_tile(x, y):
				draw_rect(Rect2(x * T + 4, y * T + 5, T, T), Color(0, 0, 0, 0.35))
	# Walls
	for y in Cfg.MAP_H:
		for x in Cfg.MAP_W:
			if map.is_wall_tile(x, y):
				var r := Rect2(x * T, y * T, T, T)
				draw_rect(r, Color(0.42, 0.44, 0.48))
				# bevel edges toward open floor
				if not map.is_wall_tile(x, y - 1):
					draw_rect(Rect2(r.position, Vector2(T, 3)), Color(0.62, 0.64, 0.68))
				if not map.is_wall_tile(x - 1, y):
					draw_rect(Rect2(r.position, Vector2(3, T)), Color(0.55, 0.57, 0.61))
				if not map.is_wall_tile(x, y + 1):
					draw_rect(Rect2(r.position + Vector2(0, T - 3), Vector2(T, 3)), Color(0.28, 0.29, 0.32))
				if not map.is_wall_tile(x + 1, y):
					draw_rect(Rect2(r.position + Vector2(T - 3, 0), Vector2(3, T)), Color(0.32, 0.33, 0.36))
