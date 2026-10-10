extends SceneTree
## godot --headless --path . --script res://tests/print_map.gd

func _init() -> void:
	var MapData = load("res://scripts/map_data.gd")
	var m = MapData.new()
	m.debug_print()
	for team in 2:
		for i in 3:
			var p: Vector2 = m.spawn_position(team, i)
			print("spawn ", team, " ", i, " ", p, " wall=", m.is_wall_at(p))
	var path = m.find_path(m.spawn_position(0, 0), m.spawn_position(1, 0))
	print("path len ", path.size())
	quit()
