extends Control
## Bottom HUD bar + top banners. Pure _draw() for compactness.

const Cfg = preload("res://scripts/config.gd")

const BAR_H := 108.0

var game  # ClientGame
var font: Font
var portrait_texture: Texture2D
var card_texture: Texture2D
var card_date := ""


func _ready() -> void:
	font = ThemeDB.fallback_font
	portrait_texture = load("res://assets/magic_student_portraits.png")
	card_texture = load("res://assets/unit_card_eth_frame.svg")
	var today := Time.get_date_dict_from_system()
	card_date = "%02d.%02d.%04d" % [int(today["day"]), int(today["month"]), int(today["year"])]
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


func _hit_alert_strength(unit_idx: int) -> float:
	var strength := 0.0
	for hit in game.hurts:
		if int(hit.get("idx", -1)) == unit_idx and int(hit.get("dmg", 0)) > 0:
			strength = maxf(strength, clampf(float(hit.get("t", 0.0)) / 1.2, 0.0, 1.0))
	return strength


func _draw_pixel_hit_alert(pos: Vector2, alpha: float) -> void:
	# Block-built punctuation keeps the warning crisp at the HUD's pixel scale.
	var bounce := -2.0 if int(game.time * 12.0) % 2 == 0 else 0.0
	var p := pos + Vector2(0.0, bounce)
	var shadow := Color(0.02, 0.015, 0.02, 0.82 * alpha)
	var red := Color(1.0, 0.08, 0.035, alpha)
	var hot := Color(1.0, 0.78, 0.12, alpha)
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(9, 16)), shadow)
	draw_rect(Rect2(p, Vector2(5, 9)), red)
	draw_rect(Rect2(p + Vector2(0, 11), Vector2(5, 3)), hot)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 6)), Color(1.0, 0.55, 0.28, alpha))


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

	const SQUAD_NAMES := ["Alpha", "Bravo", "Charlie", "Delta"]
	# Soldier cards
	for i in Cfg.SQUAD_SIZE:
		var o: Dictionary = game.own[i] if i < game.own.size() else {}
		var x := 6.0 + i * 158.0
		var r := Rect2(x, top + 7, 152, 94)
		var alive: bool = o.get("alive", true)
		var sel: bool = i == game.selected and alive
		if card_texture:
			draw_texture_rect(card_texture, r, false, Color.WHITE if alive else Color(0.55, 0.55, 0.58, 0.92))
		else:
			draw_rect(r, Color(0.92, 0.94, 0.98) if alive else Color(0.45, 0.45, 0.48))
		if sel:
			draw_rect(r, Color(1.0, 0.83, 0.28, 1.0), false, 3.0)
		_text(Vector2(x + 8, top + 22), "EHT züri", 10, Color(0.02, 0.025, 0.035) if alive else Color(0.4, 0.4, 0.42))
		var equipped_badges: Array = game.equipped_abilities(i)
		const ABILITY_BADGES := ["SM", "SC", "SU", "RU"]
		for badge_idx in mini(3, equipped_badges.size()):
			var badge_x := x + 77 + badge_idx * 13.0
			draw_rect(Rect2(badge_x, top + 11, 11, 12), Color(0.1, 0.36, 0.58) if alive else Color(0.34, 0.34, 0.36))
			_text(Vector2(badge_x + 1, top + 20), ABILITY_BADGES[equipped_badges[badge_idx]], 5, Color.WHITE if alive else Color(0.72, 0.72, 0.74))
		var hit_alert := _hit_alert_strength(i) if alive else 0.0
		var hit_pulse := hit_alert * (0.45 + 0.55 * absf(sin(game.time * 18.0)))
		if portrait_texture:
			var photo_rect := Rect2(x + 116, top + 25, 28, 44)
			draw_rect(photo_rect.grow(2.0), Color(0.96, 0.97, 0.98) if alive else Color(0.45, 0.45, 0.47))
			var portrait_source := Rect2(Vector2((i % 3) * 512 + 64, (i / 3) * 512), Vector2(384, 512))
			draw_texture_rect_region(portrait_texture, photo_rect, portrait_source, Color.WHITE if alive else Color(0.38, 0.38, 0.4, 0.8))
			if hit_alert > 0.0:
				draw_rect(photo_rect, Color(1.0, 0.02, 0.015, 0.52 * hit_pulse))
				draw_rect(photo_rect.grow(2.0), Color(1.0, 0.08, 0.035, hit_pulse), false, 2.0)
		if hit_alert > 0.0:
			_draw_pixel_hit_alert(Vector2(x + 108, top + 29), hit_pulse)
		var w: Dictionary = Cfg.WEAPONS[Cfg.SQUAD_WEAPONS[i]]
		var ink := Color(0.025, 0.035, 0.055) if alive else Color(0.28, 0.28, 0.3)
		_text(Vector2(x + 10, top + 47), "%d" % (i + 1), 13, my_col if alive else Color(0.4, 0.4, 0.4))
		_text(Vector2(x + 25, top + 47), "%s · %s" % [SQUAD_NAMES[i], w["name"]], 11, ink)
		var hp: float = o.get("hp", Cfg.SOLDIER_HP)
		if alive:
			var frac := hp / float(Cfg.SOLDIER_HP)
			_text(Vector2(x + 10, top + 54), "HP", 6, ink)
			draw_rect(Rect2(x + 24, top + 49, 85, 5), Color(0.06, 0.08, 0.11, 0.55))
			draw_rect(Rect2(x + 24, top + 49, 85 * frac, 5), Color(0.28, 0.95, 0.36).lerp(Color(1.0, 0.25, 0.2), 1.0 - frac))
			var mp: float = o.get("mp", Cfg.SOLDIER_MP)
			var mp_frac := clampf(mp / Cfg.SOLDIER_MP, 0.0, 1.0)
			_text(Vector2(x + 10, top + 62), "MP", 6, ink)
			draw_rect(Rect2(x + 24, top + 57, 85, 5), Color(0.025, 0.07, 0.13, 0.72))
			draw_rect(Rect2(x + 24, top + 57, 85 * mp_frac, 5), Color(0.18, 0.58, 1.0))
			var flags: int = o.get("flags", 0)
			var tags := ""
			if flags & 2: tags += "SUPP "
			if flags & 4: tags += "RUSH"
			if tags != "":
				_text(Vector2(x + 80, top + 23), tags, 7, Color(0.72, 0.28, 0.04))
		else:
			_text(Vector2(x + 12, top + 62), "K.I.A.", 14, Color(0.72, 0.08, 0.08))
			draw_line(Vector2(x + 7, top + 12), Vector2(x + 145, top + 96), Color(0.7, 0.05, 0.05, 0.85), 4.0)
			draw_line(Vector2(x + 145, top + 12), Vector2(x + 7, top + 96), Color(0.7, 0.05, 0.05, 0.85), 4.0)
		_text(Vector2(x + 10, top + 76), "Studies", 6, Color(0.12, 0.16, 0.22))
		_text(Vector2(x + 10, top + 86), "Comp Sc BSc", 6, Color(0.04, 0.05, 0.07))
		_text(Vector2(x + 10, top + 96), "xx-xxx-xxx VSETH", 6, Color(0.04, 0.05, 0.07))
		_text(Vector2(x + 91, top + 96), "S", 27, Color(0.02, 0.025, 0.035))
		_text(Vector2(x + 111, top + 86), card_date, 6, Color(0.04, 0.05, 0.07))

	# Ability cards
	var ab_x := 642.0
	var equipped: Array = game.equipped_abilities(game.selected)
	for ability_slot in equipped.size():
		var a: int = equipped[ability_slot]
		var def: Dictionary = Cfg.ABILITIES[a]
		var x := ab_x + ability_slot * 82.0
		var r := Rect2(x, top + 7, 76, 94)
		var cd: float = game.cooldowns[a] if a < game.cooldowns.size() else 0.0
		var ready_casters: int = game.ready_ability_casters(a)
		var is_ready := cd <= 0.0 and ready_casters > 0
		draw_rect(r, Color(0.15, 0.2, 0.17) if is_ready else Color(0.12, 0.12, 0.14))
		if not is_ready:
			var frac := clampf(cd / float(def["cooldown"]), 0.0, 1.0)
			draw_rect(Rect2(x, top + 7, 76 * frac, 94), Color(0, 0, 0, 0.45))
		var flash: float = game.ability_flash[a]
		if flash > 0.0:
			draw_rect(r, Color(0.5, 1.0, 0.7, flash), false, 3.0)
		draw_rect(Rect2(x + 8, top + 16, 24, 24), Color(0.3, 0.3, 0.35))
		_text(Vector2(x + 14, top + 34), Cfg.ABILITY_SLOT_KEYS[ability_slot], 15)
		_text(Vector2(x + 8, top + 58), def["name"], 14, Color.WHITE if is_ready else Color(0.6, 0.6, 0.6))
		_text(Vector2(x + 44, top + 34), "%d MP" % int(def["mp_cost"]), 9, Color(0.4, 0.72, 1.0))
		if is_ready:
			_text(Vector2(x + 8, top + 84), "say \"%s\"" % def["name"].to_lower(), 10, Color(0.6, 0.9, 0.7))
		elif ready_casters == 0:
			_text(Vector2(x + 8, top + 84), "MP CHARGING", 9, Color(0.35, 0.72, 1.0))
		else:
			_text(Vector2(x + 8, top + 84), "%.1fs" % cd, 12, Color(0.9, 0.6, 0.4))

	# Voice + enemy status
	var vx := 896.0
	var vstatus: String = game.voice.status
	var listening: bool = game.voice.enabled and vstatus == "listening"
	var dot_center := Vector2(vx + 10, top + 24)
	if listening:
		var pulse := 1.0 + 0.35 * sin(game.time * 8.0)
		draw_circle(dot_center, 6.0, Color(0.2, 1.0, 0.4))
		draw_arc(dot_center, 9.0 * pulse, 0.0, TAU, 16, Color(0.2, 1.0, 0.4, 0.4), 1.5)
	else:
		draw_circle(dot_center, 6.0, Color(1.0, 0.7, 0.2) if game.voice.enabled else Color(0.4, 0.4, 0.4))
	_text(Vector2(vx + 22, top + 29), "Voice [V]: " + vstatus, 12, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 205)
	if game.voice.last_heard != "":
		_text(Vector2(vx + 22, top + 49), "heard: \"%s\"" % game.voice.last_heard, 11, Color(0.6, 0.8, 1.0), HORIZONTAL_ALIGNMENT_LEFT, 205)
	_text(Vector2(vx + 4, top + 84), "Enemy squad:", 11, Color(0.7, 0.7, 0.7))
	for i in Cfg.SQUAD_SIZE:
		var alive: bool = game.enemy_alive[i] if i < game.enemy_alive.size() else true
		var c := Vector2(vx + 92 + i * 18, top + 80)
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
	_text_center(vw * 0.5, 16, "Voice: \"Alpha to Mid\" · \"Delta Watch North\" · \"Squad Rush\" · \"Halt\" | Fallback: LMB/RMB · 1-4 · W E R · V mic", 11, Color(0.8, 0.82, 0.85), false)

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
		Cfg.State.DEPLOYMENT:
			_text_center(vw * 0.5, center_y, "SQUAD DEPLOYMENT", 34, Color(0.7, 0.94, 1.0))
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
