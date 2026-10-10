extends Control
## Bottom HUD bar + top banners. Pure _draw() for compactness.

const Cfg = preload("res://scripts/config.gd")

const BAR_H := 64.0

var game  # ClientGame
var font: Font
var portrait_texture: Texture2D


func _ready() -> void:
	font = ThemeDB.fallback_font
	portrait_texture = load("res://assets/magic_student_portraits.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func _text(pos: Vector2, text: String, fs: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, text, align, width, fs, col)


func _text_center(center_x: float, y: float, text: String, fs: int, col := Color.WHITE, outline := true) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if outline:
		draw_string_outline(font, Vector2(center_x - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(center_x - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	if game == null or game.slot < 0:
		return
	var vw := size.x
	var top := Cfg.WORLD_SIZE.y
	var my_col: Color = Cfg.TEAM_COLORS[game.slot]
	var en_col: Color = Cfg.TEAM_COLORS[1 - game.slot]

	# ---- Bottom bar ------------------------------------------------------
	draw_rect(Rect2(0, top, vw, BAR_H), Color(0.07, 0.08, 0.10))
	draw_line(Vector2(0, top), Vector2(vw, top), my_col.darkened(0.3), 2.0)

	const SQUAD_NAMES := ["Alpha", "Bravo", "Charlie"]
	# Soldier cards
	for i in Cfg.SQUAD_SIZE:
		var o: Dictionary = game.own[i] if i < game.own.size() else {}
		var x := 8.0 + i * 166.0
		var r := Rect2(x, top + 7, 158, 50)
		var alive: bool = o.get("alive", true)
		var sel: bool = i == game.selected and alive
		draw_rect(r, Color(0.13, 0.15, 0.19) if alive else Color(0.1, 0.08, 0.08))
		if sel:
			draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
		if portrait_texture:
			var photo_rect := Rect2(x + 5, top + 10, 36, 42)
			draw_rect(photo_rect.grow(2.0), Color(0.86, 0.92, 0.96) if alive else Color(0.35, 0.35, 0.37))
			var portrait_source := Rect2(Vector2((i % 3) * 512 + 64, (i / 3) * 512), Vector2(384, 512))
			draw_texture_rect_region(portrait_texture, photo_rect, portrait_source, Color.WHITE if alive else Color(0.38, 0.38, 0.4, 0.8))
		var w: Dictionary = Cfg.WEAPONS[Cfg.SQUAD_WEAPONS[i]]
		_text(Vector2(x + 46, top + 25), "%d" % (i + 1), 16, my_col if alive else Color(0.4, 0.4, 0.4))
		_text(Vector2(x + 62, top + 25), "%s · %s" % [SQUAD_NAMES[i], w["name"]], 12, Color.WHITE if alive else Color(0.5, 0.5, 0.5))
		var hp: int = o.get("hp", Cfg.SOLDIER_HP)
		if alive:
			var frac := hp / float(Cfg.SOLDIER_HP)
			draw_rect(Rect2(x + 46, top + 34, 102, 8), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x + 46, top + 34, 102 * frac, 8), Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.25, 0.2), 1.0 - frac))
			var flags: int = o.get("flags", 0)
			var tags := ""
			if flags & 2: tags += "SUPP "
			if flags & 4: tags += "RUSH"
			_text(Vector2(x + 108, top + 51), tags, 9, Color(1.0, 0.85, 0.3))
		else:
			_text(Vector2(x + 46, top + 44), "K.I.A.", 13, Color(1.0, 0.3, 0.3))

	# Ability cards
	var ab_x := 512.0
	for a in 4:
		var def: Dictionary = Cfg.ABILITIES[a]
		var x := ab_x + a * 122.0
		var r := Rect2(x, top + 7, 114, 50)
		var cd: float = game.cooldowns[a] if a < game.cooldowns.size() else 0.0
		var is_ready := cd <= 0.0
		draw_rect(r, Color(0.15, 0.2, 0.17) if is_ready else Color(0.12, 0.12, 0.14))
		if not is_ready:
			var frac := clampf(cd / float(def["cooldown"]), 0.0, 1.0)
			draw_rect(Rect2(x, top + 7, 114 * frac, 50), Color(0, 0, 0, 0.45))
		var flash: float = game.ability_flash[a]
		if flash > 0.0:
			draw_rect(r, Color(0.5, 1.0, 0.7, flash), false, 3.0)
		draw_rect(Rect2(x + 6, top + 13, 22, 22), Color(0.3, 0.3, 0.35))
		_text(Vector2(x + 11, top + 30), def["key"], 15)
		_text(Vector2(x + 34, top + 29), def["name"], 15, Color.WHITE if is_ready else Color(0.6, 0.6, 0.6))
		if is_ready:
			_text(Vector2(x + 8, top + 51), "say \"%s\"" % def["name"].to_lower(), 11, Color(0.6, 0.9, 0.7))
		else:
			_text(Vector2(x + 8, top + 51), "%.1fs" % cd, 12, Color(0.9, 0.6, 0.4))

	# Voice + enemy status
	var vx := 1008.0
	var vstatus: String = game.voice.status
	var listening: bool = game.voice.enabled and vstatus == "listening"
	var dot_center := Vector2(vx + 10, top + 20)
	if listening:
		var pulse := 1.0 + 0.35 * sin(game.time * 8.0)
		draw_circle(dot_center, 6.0, Color(0.2, 1.0, 0.4))
		draw_arc(dot_center, 9.0 * pulse, 0.0, TAU, 16, Color(0.2, 1.0, 0.4, 0.4), 1.5)
	else:
		draw_circle(dot_center, 6.0, Color(1.0, 0.7, 0.2) if game.voice.enabled else Color(0.4, 0.4, 0.4))
	_text(Vector2(vx + 22, top + 25), "Voice [V]: " + vstatus, 12, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 250)
	if game.voice.last_heard != "":
		_text(Vector2(vx + 22, top + 41), "heard: \"%s\"" % game.voice.last_heard, 11, Color(0.6, 0.8, 1.0), HORIZONTAL_ALIGNMENT_LEFT, 250)
	_text(Vector2(vx + 4, top + 58), "Enemy squad:", 11, Color(0.7, 0.7, 0.7))
	for i in Cfg.SQUAD_SIZE:
		var alive: bool = game.enemy_alive[i] if i < game.enemy_alive.size() else true
		var c := Vector2(vx + 92 + i * 18, top + 54)
		if alive:
			draw_circle(c, 6, en_col)
		else:
			draw_arc(c, 6, 0, TAU, 12, en_col.darkened(0.5), 1.5)
			draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), en_col.darkened(0.3), 2)

	# ---- Top info ---------------------------------------------------------
	var n0: String = game.names[0] if game.names.size() > 0 else ""
	var n1: String = game.names[1] if game.names.size() > 1 else ""
	var me: String = n0 if game.slot == 0 else n1
	var them: String = n1 if game.slot == 0 else n0
	draw_rect(Rect2(0, 0, vw, 22), Color(0, 0, 0, 0.45))
	_text(Vector2(8, 16), "%s (you)" % me, 14, my_col)
	var them_str: String = them if them != "" else "waiting for opponent..."
	var tw := font.get_string_size(them_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(Vector2(vw - tw - 8, 16), them_str, 14, en_col)
	_text_center(vw * 0.5, 16, "Voice: \"Alpha to Mid\" · \"Watch North\" · \"Squad Rush\" · \"Halt\" | Fallback: LMB/RMB · 1-3 · Q E R F · V mic", 11, Color(0.8, 0.82, 0.85), false)

	# Banners
	var by := 52.0
	for m in game.messages:
		var k: float = clampf(m["t"], 0.0, 1.0)
		var col: Color = m["color"]
		col.a = k
		_text_center(vw * 0.5, by, m["text"], 18, col)
		by += 24.0

	# Big centre text
	var center_y := Cfg.WORLD_SIZE.y * 0.5
	match game.state:
		Cfg.State.WAITING:
			_text_center(vw * 0.5, center_y, "Waiting for an opponent to join...", 30, Color(1, 1, 1, 0.9))
			_text_center(vw * 0.5, center_y + 34, "Open this page in a second browser tab/window to test locally.", 16, Color(0.8, 0.8, 0.8))
		Cfg.State.COUNTDOWN:
			_text_center(vw * 0.5, center_y, "%d" % ceili(game.countdown), 72, Color(1, 1, 1))
			_text_center(vw * 0.5, center_y + 40, "You are %s - your base is on the left" % Cfg.TEAM_NAMES[game.slot], 18, my_col)
		Cfg.State.ENDED:
			var txt := "DRAW"
			var col := Color(0.9, 0.9, 0.9)
			if game.winner == game.slot:
				txt = "VICTORY"
				col = Color(0.4, 1.0, 0.5)
			elif game.winner >= 0:
				txt = "DEFEAT"
				col = Color(1.0, 0.35, 0.3)
			_text_center(vw * 0.5, center_y - 20, txt, 72, col)
			var votes: Array = game.rematch_votes
			var mine: bool = votes.size() > game.slot and votes[game.slot]
			_text_center(vw * 0.5, center_y + 70, "Waiting for opponent to accept rematch..." if mine else "Press Enter or say \"Rematch\"", 18, Color(0.9, 0.9, 0.9))
