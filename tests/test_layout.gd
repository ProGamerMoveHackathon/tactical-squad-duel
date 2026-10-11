extends Node

const Cfg = preload("res://scripts/config.gd")
const MapData = preload("res://scripts/map_data.gd")
const Hud = preload("res://scripts/client/hud.gd")

var failed := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  [PASS] ", label)
	else:
		failed += 1
		print("  [FAIL] ", label)


func _ready() -> void:
	var map = MapData.new()
	var hud = Hud.new()
	hud.size = Vector2(1280, 812)
	_check(is_equal_approx(hud.bar_top(), 704.0), "bottom HUD anchors to the viewport instead of the world")
	hud.free()
	_check(Cfg.MAP_W == 80 and Cfg.MAP_H == 71, "arena includes the enlarged hall and lower square room")
	_check(not map.is_wall_tile(4, map.MAIN_BOTTOM), "Entrance 1 threshold is open")
	_check(not map.is_wall_tile(Cfg.MAP_W - 1, 4), "Entrance 2 threshold is open")
	_check(not map.is_wall_tile(37, 20), "open centre of the revised plan stays walkable")
	_check(map.tables.size() == 82, "blast damage and the messy row leave the revised table count")
	var unique_tables := {}
	var four_seat := 0
	var eight_seat := 0
	for table in map.tables:
		var anchor: Vector2i = table["anchor"]
		unique_tables[anchor] = true
		if table["seats"] == 4:
			four_seat += 1
		elif table["seats"] == 8:
			eight_seat += 1
	_check(unique_tables.size() == map.tables.size(), "table anchors are unique")
	_check(four_seat == 28 and eight_seat == 54, "revised plan uses only four-chair and eight-chair tables")
	_check(map.layout_overlaps.is_empty(), "walls, furniture, plants and counters do not overlap")
	for y in range(1, 8):
		_check(map.solid_kind(18, y) == map.SolidKind.RUBBLE, "explosion blocks upper passage row %d" % y)
	_check(not map.is_wall_tile(39, 23), "spilled glass remains decorative and walkable")
	_check(map.solid_kind(map.ROOM_LEFT, 62) == map.SolidKind.RUBBLE, "left exterior passage is sealed with rubble")
	_check(map.solid_kind(map.ROOM_LEFT + 2, 62) == map.SolidKind.RUBBLE, "rubble pile extends into the lower room")

	for team in 2:
		for idx in Cfg.SQUAD_SIZE:
			var entry: Vector2 = map.entry_position(team, idx)
			var spawn: Vector2 = map.spawn_position(team, idx)
			_check(not map.is_wall_at(entry), "team %d unit %d starts in its doorway" % [team + 1, idx + 1])
			_check(not map.is_wall_at(spawn), "team %d unit %d has a clear formation point" % [team + 1, idx + 1])
			_check(not map.find_path(entry, spawn).is_empty(), "team %d unit %d can enter and spread out" % [team + 1, idx + 1])
	_check(not map.find_path(map.spawn_position(0, 0), map.spawn_position(1, 0)).is_empty(), "both halves of the arena are connected")
	_check(not map.is_wall_tile(39, map.MAIN_BOTTOM), "central lower passage is open")
	_check(not map.is_wall_tile(32, map.MAIN_BOTTOM), "marked wall segment left of the passage is removed")
	_check(map.service_fixtures.size() == 5, "lower room contains the annotated service fixtures")
	_check(map.ROOM_RIGHT == 78, "lower room expands almost to the right edge of the main hall")
	_check(map.solid_kind(36, 45) == map.SolidKind.COUNTER, "cash register has collision")
	_check(map.solid_kind(44, 47) == map.SolidKind.COUNTER, "metal food line has collision")
	_check(map.solid_kind(40, 55) == map.SolidKind.COUNTER, "revised buffet perimeter has collision")
	_check(not map.is_wall_tile(47, 55) and not map.is_wall_tile(48, 63), "buffet island has two entrances")
	_check(not map.is_wall_tile(47, 59), "buffet island remains hollow")
	_check(map.solid_kind(72, 51) == map.SolidKind.COUNTER and not map.is_wall_tile(75, 55), "right food line leaves a broad wall-side aisle")
	_check(not map.is_wall_tile(74, 39), "destroyed table is walkable debris")
	_check(map.is_wall_tile(62, 39), "diagonal tipped table retains collision")
	_check(not map.is_wall_tile(74, map.MAIN_BOTTOM), "exploded wall opens a second route into the lower room")
	_check(not map.find_path(Vector2(39.5, 40.0) * Cfg.TILE, Vector2(34.0, 58.0) * Cfg.TILE).is_empty(), "lower square room is reachable")
	_check(not map.find_path(Vector2(74.0, 40.0) * Cfg.TILE, Vector2(70.0, 66.0) * Cfg.TILE).is_empty(), "new breach connects to the expanded room")
	_check(not map.find_path(Vector2(34.0, 58.0) * Cfg.TILE, Vector2(70.0, 66.0) * Cfg.TILE).is_empty(), "lower room circulation remains connected")
	_check(not map.find_path(Vector2(47.0, 53.0) * Cfg.TILE, Vector2(47.0, 59.0) * Cfg.TILE).is_empty(), "top buffet entrance reaches the hollow centre")
	map.set_doors_closed(true)
	_check(map.is_wall_tile(4, map.MAIN_BOTTOM), "Entrance 1 gains collision after deployment")
	_check(map.is_wall_tile(Cfg.MAP_W - 1, 4), "Entrance 2 gains collision after deployment")
	map.set_doors_closed(false)

	print("\nLayout test results: %d failed." % failed)
	get_tree().quit(1 if failed > 0 else 0)
