extends Control
## Bottom HUD bar + top banners. Pure _draw() for compactness.

const Cfg = preload("res://scripts/config.gd")
const Voice = preload("res://scripts/client/voice.gd")

const BAR_H := 108.0

var game  # ClientGame
var font: Font
var portrait_texture: Texture2D
var card_texture: Texture2D
var eth_logo_texture: Texture2D
var card_date := ""


func _ready() -> void:
	font = ThemeDB.fallback_font
	portrait_texture = load("res://assets/magic_student_portraits.png")
	card_texture = load("res://assets/unit_card_eth_frame.svg")
	eth_logo_texture = load("res://assets/eth_zurich_logo.png")
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


func _text_w(text: String, fs: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## Shortens text to max_w with "...". keep_end keeps the newest words of live speech.
func _fit(text: String, fs: int, max_w: float, keep_end := false) -> String:
	if _text_w(text, fs) <= max_w:
		return text
	var t := text
	while t.length() > 1 and _text_w(("..." + t) if keep_end else (t + "..."), fs) > max_w:
		t = t.substr(1) if keep_end else t.left(-1)
	return ("..." + t) if keep_end else (t + "...")


# ---- Voice feedback ----------------------------------------------------------

const VOICE_HINTS := [
	"\"bravo go to kitchen\"", "\"squad watch right\"", "\"smoke mid\"",
	"\"alpha fall back a bit\"", "\"charlie push enemy tables\"", "\"go up\"", "\"stop\"",
]


func _mic_status_text() -> String:
	var v = game.voice
	match v.status:
		"listening": return "HEARING YOU" if v.speaking else "LISTENING"
		"off": return "MIC OFF"
		"web only": return "WEB BUILD ONLY"
		"unsupported browser": return "NO VOICE IN THIS BROWSER"
		"mic blocked": return "MIC BLOCKED"
		"no microphone": return "NO MICROPHONE"
		"speech service offline": return "SPEECH SERVICE OFFLINE"
	return str(v.status).to_upper()


func _mic_color() -> Color:
	var v = game.voice
	if v.enabled and v.status == "listening":
		return Color(1.0, 0.9, 0.35) if v.speaking else Color(0.35, 1.0, 0.6)
	if v.status == "off" or v.status == "web only":
		return Color(0.55, 0.57, 0.6)
	return Color(1.0, 0.6, 0.3)


func _draw_mic_icon(c: Vector2, col: Color) -> void:
	draw_rect(Rect2(c.x - 3, c.y - 6, 6, 8), col)
	draw_circle(Vector2(c.x, c.y - 6), 3.0, col)
	draw_circle(Vector2(c.x, c.y + 2), 3.0, col)
	draw_arc(Vector2(c.x, c.y + 1), 6.0, 0.15, PI - 0.15, 10, col, 1.5)
	draw_line(Vector2(c.x, c.y + 7), Vector2(c.x, c.y + 10), col, 1.5)
	draw_line(Vector2(c.x - 3, c.y + 10), Vector2(c.x + 3, c.y + 10), col, 1.5)


## Bottom-right transcript: live words while speaking plus the last few
## utterances with what they triggered (or "not understood").
func _draw_voice_panel(vw: float, top: float) -> void:
	var v = game.voice
	var problem: bool = not v.status in ["listening", "off", "web only"]
	var entries := []
	for h in v.history:
		if h["age"] < Voice.HISTORY_TTL:
			entries.append(h)
	entries = entries.slice(maxi(0, entries.size() - 3))
	if not v.enabled and not problem and entries.is_empty() and v.interim_text == "":
		return

	const W := 340.0
	const ENTRY_H := 36.0
	var h_total := 30.0 + entries.size() * ENTRY_H + 26.0
	var x0: float = vw - W - 8.0
	var y0: float = top - 8.0 - h_total
	var col := _mic_color()
	draw_rect(Rect2(x0, y0, W, h_total), Color(0.03, 0.04, 0.06, 0.8))
	draw_rect(Rect2(x0, y0, W, h_total), Color(col, 0.55), false, 1.5)

	# Header: mic icon, state, level bars while speech is detected
	_draw_mic_icon(Vector2(x0 + 14, y0 + 14), col)
	_text(Vector2(x0 + 28, y0 + 19), "VOICE  " + _mic_status_text(), 12, col)
	_text(Vector2(x0 + W - 70, y0 + 19), "V to toggle", 10, Color(0.5, 0.55, 0.6))
	if v.enabled:
		for i in 5:
			var lvl: float = 0.25 + 0.75 * absf(sin(game.time * (7.0 + i * 1.7) + i)) if v.speaking else 0.15
			var bh := 12.0 * lvl
			draw_rect(Rect2(x0 + W - 108 + i * 5, y0 + 20 - bh, 3, bh), Color(col, 0.9))
	draw_line(Vector2(x0 + 6, y0 + 27), Vector2(x0 + W - 6, y0 + 27), Color(1, 1, 1, 0.08), 1.0)

	# History, oldest at the top
	var y := y0 + 30.0
	for h in entries:
		var a: float = clampf((Voice.HISTORY_TTL - h["age"]) / 1.5, 0.0, 1.0)
		_text(Vector2(x0 + 10, y + 14), _fit("\"%s\"" % h["text"], 13, W - 20), 13, Color(0.92, 0.94, 0.97, a))
		if h["tags"].is_empty():
			_text(Vector2(x0 + 18, y + 30), "not a command", 11, Color(0.6, 0.62, 0.66, a))
		else:
			_text(Vector2(x0 + 18, y + 30), _fit("> " + "  +  ".join(h["tags"]), 11, W - 28), 11, Color(0.4, 1.0, 0.65, a))
		y += ENTRY_H

	# Live line
	var ly := y + 18.0
	if v.interim_text != "":
		var caret := "_" if fmod(game.time, 0.8) < 0.4 else " "
		_text(Vector2(x0 + 10, ly), _fit(v.interim_text, 13, W - 30, true) + caret, 13, Color(1.0, 0.88, 0.35))
	elif problem:
		var help := "Allow the microphone for this page, then press V" if v.status == "mic blocked" else "Voice unavailable - keyboard and mouse still work"
		_text(Vector2(x0 + 10, ly), _fit(help, 11, W - 20), 11, Color(1.0, 0.7, 0.45))
	elif v.enabled:
		var hint: String = VOICE_HINTS[int(game.time / 3.5) % VOICE_HINTS.size()]
		_text(Vector2(x0 + 10, ly), "try: " + hint, 11, Color(0.5, 0.58, 0.66))
	else:
		_text(Vector2(x0 + 10, ly), "mic off - press V to talk", 11, Color(0.5, 0.58, 0.66))


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
		if eth_logo_texture:
			draw_texture_rect_region(eth_logo_texture, Rect2(x + 10, top + 11, 68, 12), Rect2(35, 48, 510, 88), Color.WHITE if alive else Color(0.55, 0.55, 0.58))
		if portrait_texture:
			var photo_rect := Rect2(x + 116, top + 25, 28, 44)
			draw_rect(photo_rect.grow(2.0), Color(0.96, 0.97, 0.98) if alive else Color(0.45, 0.45, 0.47))
			var portrait_source := Rect2(Vector2((i % 3) * 512 + 64, (i / 3) * 512), Vector2(384, 512))
			draw_texture_rect_region(portrait_texture, photo_rect, portrait_source, Color.WHITE if alive else Color(0.38, 0.38, 0.4, 0.8))
		var w: Dictionary = Cfg.WEAPONS[Cfg.SQUAD_WEAPONS[i]]
		var ink := Color(0.025, 0.035, 0.055) if alive else Color(0.28, 0.28, 0.3)
		_text(Vector2(x + 10, top + 47), "%d" % (i + 1), 13, my_col if alive else Color(0.4, 0.4, 0.4))
		_text(Vector2(x + 25, top + 47), "%s · %s" % [SQUAD_NAMES[i], w["name"]], 11, ink)
		var hp: float = o.get("hp", Cfg.SOLDIER_HP)
		if alive:
			var frac := hp / float(Cfg.SOLDIER_HP)
			draw_rect(Rect2(x + 10, top + 55, 99, 8), Color(0.06, 0.08, 0.11, 0.55))
			draw_rect(Rect2(x + 10, top + 55, 99 * frac, 8), Color(0.28, 0.95, 0.36).lerp(Color(1.0, 0.25, 0.2), 1.0 - frac))
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
	for a in 4:
		var def: Dictionary = Cfg.ABILITIES[a]
		var x := ab_x + a * 82.0
		var r := Rect2(x, top + 7, 76, 94)
		var cd: float = game.cooldowns[a] if a < game.cooldowns.size() else 0.0
		var is_ready := cd <= 0.0
		draw_rect(r, Color(0.15, 0.2, 0.17) if is_ready else Color(0.12, 0.12, 0.14))
		if not is_ready:
			var frac := clampf(cd / float(def["cooldown"]), 0.0, 1.0)
			draw_rect(Rect2(x, top + 7, 76 * frac, 94), Color(0, 0, 0, 0.45))
		var flash: float = game.ability_flash[a]
		if flash > 0.0:
			draw_rect(r, Color(0.5, 1.0, 0.7, flash), false, 3.0)
		draw_rect(Rect2(x + 8, top + 16, 24, 24), Color(0.3, 0.3, 0.35))
		_text(Vector2(x + 14, top + 34), def["key"], 15)
		_text(Vector2(x + 8, top + 58), def["name"], 14, Color.WHITE if is_ready else Color(0.6, 0.6, 0.6))
		if is_ready:
			_text(Vector2(x + 8, top + 84), "say \"%s\"" % def["name"].to_lower(), 10, Color(0.6, 0.9, 0.7))
		else:
			_text(Vector2(x + 8, top + 84), "%.1fs" % cd, 12, Color(0.9, 0.6, 0.4))

	# ---- Bottom right card: mic state (button is a real Button) + enemies --
	var voice = game.voice
	var vx := 1004.0
	var box_r := Rect2(vx, top + 7, vw - vx - 8.0, 50)
	var listening: bool = voice.enabled and voice.status == "listening"
	draw_rect(box_r, Color(0.13, 0.15, 0.19))
	draw_rect(box_r, Color(0.3, 1.0, 0.6, 0.7) if listening else Color(0.24, 0.28, 0.32), false, 1.0)
	_draw_mic_icon(Vector2(vx + 14, top + 21), _mic_color())
	_text(Vector2(vx + 26, top + 26), _fit(_mic_status_text(), 12, 160), 12, _mic_color())
	_text(Vector2(vx + 10, top + 49), "Enemies alive", 10, Color(0.6, 0.6, 0.65))
	for i in Cfg.SQUAD_SIZE:
		var alive: bool = game.enemy_alive[i] if i < game.enemy_alive.size() else true
		var c := Vector2(vx + 86 + i * 14, top + 45)
		if alive:
			draw_circle(c, 4.5, en_col)
		else:
			draw_arc(c, 4.5, 0, TAU, 12, en_col.darkened(0.5), 1.2)
			draw_line(c + Vector2(-3, -3), c + Vector2(3, 3), en_col.darkened(0.3), 1.5)

	_draw_voice_panel(vw, top)

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
	_text_center(vw * 0.5, 16, "Voice: \"Bravo go to kitchen\" · \"Squad watch right\" · \"Smoke mid\" · \"Stop\"  |  Keys: LMB/RMB · 1-4 · Q E R F · V mic", 11, Color(0.8, 0.82, 0.85), false)

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
