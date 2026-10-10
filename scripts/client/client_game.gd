extends Node
## Client: menu, connection, input -> server commands, snapshot interpolation,
## visual effects. Builds its scene tree in code.

const Cfg = preload("res://scripts/config.gd")
const MapData = preload("res://scripts/map_data.gd")
const MapView = preload("res://scripts/client/map_view.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const VisionMask = preload("res://scripts/client/vision_mask.gd")
const Hud = preload("res://scripts/client/hud.gd")
const Voice = preload("res://scripts/client/voice.gd")
const Sfx = preload("res://scripts/client/sfx.gd")

const FOG_SHADER := """
shader_type canvas_item;
uniform float darkness = 0.74;
void fragment() {
	float m = texture(TEXTURE, UV).r;
	COLOR = vec4(0.01, 0.015, 0.03, darkness * (1.0 - m));
}
"""

var map := MapData.new()

# --- Match state (from server) --------------------------------------------
var slot := -1
var state := Cfg.State.WAITING
var countdown := 0.0
var winner := -1
var selected := 0
var own := []          # Array of Dictionary
var enemies := {}      # idx -> Dictionary
var ghosts := []       # last known enemy positions
var scanned := []      # [[idx, pos]]
var enemy_alive := [true, true, true]
var smokes := []       # [[pos, r, t_left]]
var cooldowns := [0.0, 0.0, 0.0, 0.0]
var names := ["", ""]
var rematch_votes := [false, false]

# --- Effects -------------------------------------------------------------
var time := 0.0
var tracers := []
var hurts := []
var corpses := []
var scan_fx := []
var messages := []
var ability_flash := [0.0, 0.0, 0.0, 0.0]

var world_rotation := 0.0
var _sel_lock_until := 0.0
var _face_send_t := 0.0
var _connected := false

# --- Nodes -----------------------------------------------------------------
var world: Node2D
var map_view: Node2D
var entity_view: Node2D
var fog_vp: SubViewport
var vision_mask: Node2D
var fog_sprite: Sprite2D
var hud: Control
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var name_edit: LineEdit
var url_edit: LineEdit
var connect_btn: Button
var status_label: Label
var voice: Node
var sfx: Node


func _ready() -> void:
	_reset_own()
	voice = Voice.new()
	add_child(voice)
	voice.command_spoken.connect(_on_voice_command)
	voice.status_changed.connect(func(s): _msg("Voice: " + s, Color(0.6, 0.8, 1.0)))
	sfx = Sfx.new()
	add_child(sfx)
	_build_world()
	_build_hud()
	_build_menu()
	Net.welcomed.connect(_on_welcome)
	Net.snapshot_received.connect(_on_snapshot)
	Net.rejected.connect(_on_rejected)
	Net.connection_ok.connect(_on_connection_ok)
	Net.connection_lost.connect(_on_connection_lost)
	_show_menu(true, "")
	if _query_param("auto") != "":
		_on_connect_pressed()
	_setup_debug_hooks()


## Native-only testing helpers:
##   --screenshot=/path.png [--shot_delay=8]  save a frame and quit
##   --demo                                     squad auto-advances toward the centre
func _setup_debug_hooks() -> void:
	if OS.has_feature("web"):
		return
	var shot := _query_param("screenshot")
	if shot != "":
		var delay := float(_query_param("shot_delay")) if _query_param("shot_delay") != "" else 8.0
		get_tree().create_timer(delay).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(shot)
			print("screenshot saved: ", shot)
			get_tree().quit())
	if _query_param("demo") != "":
		var timer := Timer.new()
		timer.wait_time = 2.0
		timer.autostart = true
		add_child(timer)
		var step := [0]
		timer.timeout.connect(func():
			if state != Cfg.State.PLAYING:
				return
			step[0] += 1
			var idx: int = step[0] % 3
			_select(idx)
			var target := Cfg.WORLD_SIZE * 0.5 + Vector2(randf_range(-200, 60) * (1 if slot == 0 else -1), randf_range(-200, 200))
			Net.c_move.rpc_id(1, target, false)
			if step[0] == 4:
				_use_ability(Cfg.Ability.SMOKE, false)
			if step[0] == 5:
				_use_ability(Cfg.Ability.SUPPRESS, false))


# --------------------------------------------------------------------------
# Scene construction
# --------------------------------------------------------------------------

func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	map_view = MapView.new()
	map_view.map = map
	world.add_child(map_view)

	fog_vp = SubViewport.new()
	fog_vp.size = Vector2i(Cfg.WORLD_SIZE * 0.5)
	fog_vp.disable_3d = true
	fog_vp.transparent_bg = false
	fog_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(fog_vp)
	vision_mask = VisionMask.new()
	vision_mask.game = self
	vision_mask.scale = Vector2(0.5, 0.5)
	fog_vp.add_child(vision_mask)

	fog_sprite = Sprite2D.new()
	fog_sprite.centered = false
	fog_sprite.scale = Vector2(2, 2)
	fog_sprite.texture = fog_vp.get_texture()
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	mat.shader = sh
	fog_sprite.material = mat
	world.add_child(fog_sprite)

	entity_view = EntityView.new()
	entity_view.game = self
	world.add_child(entity_view)
	world.visible = false


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = Hud.new()
	hud.game = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(hud)
	# Block clicks on the bottom bar from reaching the world.
	var blocker := Control.new()
	blocker.position = Vector2(0, Cfg.WORLD_SIZE.y)
	blocker.size = Vector2(Cfg.WORLD_SIZE.x, 64)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_layer.add_child(blocker)
	var mic_btn := Button.new()
	mic_btn.text = "Mic"
	mic_btn.focus_mode = Control.FOCUS_NONE
	mic_btn.position = Vector2(1222, Cfg.WORLD_SIZE.y + 8)
	mic_btn.size = Vector2(50, 26)
	mic_btn.pressed.connect(func(): voice.toggle())
	hud_layer.add_child(mic_btn)
	hud_layer.visible = false


func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(520, 0)
	margin.add_child(box)

	var title := Label.new()
	title.text = "TACTICAL SQUAD DUEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "1 vs 1 · 3 soldiers each · see them before they see you"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	box.add_child(sub)
	box.add_child(HSeparator.new())

	var name_label := Label.new()
	name_label.text = "Callsign"
	box.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.max_length = 16
	var qn := _query_param("name")
	name_edit.text = qn if qn != "" else "Player%d" % (randi() % 900 + 100)
	box.add_child(name_edit)
	var url_label := Label.new()
	url_label.text = "Server"
	box.add_child(url_label)
	url_edit = LineEdit.new()
	url_edit.text = _default_url()
	box.add_child(url_edit)
	connect_btn = Button.new()
	connect_btn.text = "Deploy"
	connect_btn.custom_minimum_size = Vector2(0, 40)
	connect_btn.pressed.connect(_on_connect_pressed)
	box.add_child(connect_btn)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	box.add_child(HSeparator.new())
	var help := Label.new()
	help.text = "VOICE COMMANDS (Hands-Free):\n" \
		+ "• Select: \"Alpha\", \"Bravo\", \"Charlie\", \"Squad\"\n" \
		+ "• Move: \"Alpha to Mid\", \"Advance to North\", \"Fall back to Base\", \"Stop\"\n" \
		+ "• Aim: \"Watch North\", \"Watch Mid\", \"Aim South\"\n" \
		+ "• Abilities: \"Smoke Mid\", \"Scan\", \"Suppress\", \"Squad Rush\"\n" \
		+ "• Match: \"Deploy\", \"Rematch\"\n\n" \
		+ "Fallback: LMB move · RMB face · 1-3 select · Q E R F abilities · V mic toggle"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	box.add_child(help)
	name_edit.text_submitted.connect(func(_t): _on_connect_pressed())
	url_edit.text_submitted.connect(func(_t): _on_connect_pressed())


func _show_menu(show: bool, status: String) -> void:
	menu_layer.visible = show
	world.visible = not show
	hud_layer.visible = not show
	status_label.text = status
	connect_btn.disabled = false


# --------------------------------------------------------------------------
# Connection
# --------------------------------------------------------------------------

func _query_param(key: String) -> String:
	if not OS.has_feature("web"):
		for a in OS.get_cmdline_user_args():
			if a == "--" + key:
				return "1"
			if a.begins_with("--" + key + "="):
				return a.substr(key.length() + 3)
		return ""
	var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % key, true)
	return str(v) if v != null else ""


func _default_url() -> String:
	var q := _query_param("server")
	if q != "":
		return q
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("""(function(){
			if (location.protocol === 'https:') return 'wss://' + location.host + '/ws';
			return 'ws://' + (location.hostname || 'localhost') + ':%d';
		})()""" % Cfg.DEFAULT_PORT, true)
		if v != null:
			return str(v)
	return "ws://127.0.0.1:%d" % Cfg.DEFAULT_PORT


func _on_connect_pressed() -> void:
	voice.start()
	var url := url_edit.text.strip_edges()
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		status_label.text = "Server address must start with ws:// or wss://"
		return
	connect_btn.disabled = true
	status_label.text = "Connecting to %s ..." % url
	var err := Net.join(url)
	if err != OK:
		_show_menu(true, "Could not start connection (error %d)" % err)


func _on_connection_ok() -> void:
	_connected = true
	Net.c_hello.rpc_id(1, name_edit.text)


func _on_welcome(s: int) -> void:
	slot = s
	world_rotation = PI if slot == 1 else 0.0
	world.rotation = world_rotation
	world.position = Cfg.WORLD_SIZE if slot == 1 else Vector2.ZERO
	_reset_round_visuals()
	_show_menu(false, "")
	sfx.play("start", -6.0)
	voice.start()


func _on_rejected(reason: String) -> void:
	Net.leave()
	_show_menu(true, reason)


func _on_connection_lost(reason: String) -> void:
	_connected = false
	slot = -1
	Net.leave()
	_show_menu(true, reason + ". Is the server running?")


# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------

func _reset_own() -> void:
	own.clear()
	for i in Cfg.SQUAD_SIZE:
		own.append({"idx": i, "pos": Vector2.ZERO, "disp": Vector2.ZERO, "facing": 0.0, "disp_facing": 0.0,
			"hp": Cfg.SOLDIER_HP, "flags": 8, "alive": true, "target": Vector2.ZERO, "watch": INF, "init": false})


func _reset_round_visuals() -> void:
	_reset_own()
	enemies.clear()
	ghosts.clear()
	scanned.clear()
	tracers.clear()
	hurts.clear()
	corpses.clear()
	scan_fx.clear()


func _on_snapshot(d: Dictionary) -> void:
	var prev_state := state
	state = d["st"]
	if state == Cfg.State.COUNTDOWN and prev_state != Cfg.State.COUNTDOWN:
		_reset_round_visuals()
		sfx.play("start", -4.0)
	if state == Cfg.State.WAITING and prev_state != Cfg.State.WAITING:
		_reset_round_visuals()
	countdown = d["ct"]
	winner = d["win"]
	if time > _sel_lock_until:
		selected = d["sel"]
	for e in d["own"]:
		var o: Dictionary = own[e[0]]
		o["pos"] = e[1]
		o["facing"] = e[2]
		o["hp"] = e[3]
		o["flags"] = e[4]
		o["alive"] = e[4] & 8 != 0
		o["target"] = e[5]
		o["watch"] = e[6]
		if not o["init"] or o["disp"].distance_to(o["pos"]) > 120.0:
			o["disp"] = o["pos"]
			o["disp_facing"] = o["facing"]
			o["init"] = true
	var seen := {}
	for e in d["en"]:
		var idx: int = e[0]
		seen[idx] = true
		if not enemies.has(idx):
			enemies[idx] = {"disp": e[1], "disp_facing": e[2]}
			for g in ghosts.duplicate():
				if g["idx"] == idx:
					ghosts.erase(g)
		var en: Dictionary = enemies[idx]
		en["pos"] = e[1]
		en["facing"] = e[2]
		en["hp"] = e[3]
		en["flags"] = e[4]
	for idx in enemies.keys():
		if not seen.has(idx):
			ghosts.append({"idx": idx, "pos": enemies[idx]["disp"], "t": 2.0})
			enemies.erase(idx)
	scanned = d["sc"]
	enemy_alive = d["ea"]
	smokes = d["sm"]
	cooldowns = d["cd"]
	rematch_votes = d["rm"]
	names = d["names"]
	for ev in d["ev"]:
		_handle_event(ev)


func _handle_event(ev: Array) -> void:
	match ev[0]:
		"msg":
			_msg(ev[1], Color(1, 1, 1))
		"deny":
			_msg("%s: %s" % [Cfg.ABILITIES[ev[1]]["name"], ev[2]], Color(1.0, 0.5, 0.4))
			sfx.play("deny", -8.0)
		"ability":
			var a: int = ev[1]
			ability_flash[a] = 1.0
			var weapon_name: String = Cfg.WEAPONS[Cfg.SQUAD_WEAPONS[ev[2]]]["name"]
			_msg("%s! (%s%s)" % [Cfg.ABILITIES[a]["name"], weapon_name, ", voice" if ev[3] else ""], Color(0.5, 1.0, 0.7))
			sfx.play("ability", -6.0)
		"scan":
			scan_fx.append({"origin": ev[1], "radius": ev[2], "t": 1.0, "max": 1.0})
			_msg("Scan: %d moving contact%s" % [ev[3], "" if ev[3] == 1 else "s"], Color(1.0, 0.6, 0.5))
		"shot":
			var team: int = ev[1]
			var weapon: int = Cfg.SQUAD_WEAPONS[ev[2]]
			var from: Vector2 = ev[3]
			var first := true
			for end in ev[4]:
				tracers.append({"a": from, "b": end, "t": 0.12, "max": 0.12,
					"color": Color(1.0, 0.95, 0.6) if team == slot else Color(1.0, 0.6, 0.5),
					"flash": first, "hit": ev[5] > 0})
				first = false
			var snd: String = ["rifle", "smg", "shotgun"][weapon]
			sfx.play(snd, -10.0 if team == slot else -6.0)
			if ev[5] > 0 and team != slot:
				sfx.play("hit", -4.0)
		"incoming":
			hurts.append({"idx": ev[1], "angle": ev[2], "dmg": ev[3], "t": 1.2})
			sfx.play("smg" if ev[3] == 0 else "hit", -12.0 if ev[3] == 0 else -4.0)
		"kill":
			var team: int = ev[1]
			var idx: int = ev[2]
			corpses.append({"pos": ev[3], "team": team})
			var wname: String = Cfg.WEAPONS[Cfg.SQUAD_WEAPONS[idx]]["name"]
			if team == slot:
				_msg("Your %s is down!" % wname, Color(1.0, 0.4, 0.3))
			else:
				_msg("Enemy %s eliminated!" % wname, Color(0.5, 1.0, 0.5))
			sfx.play("kill", -3.0)


func _msg(text: String, col: Color) -> void:
	messages.append({"text": text, "color": col, "t": 3.0})
	while messages.size() > 4:
		messages.pop_front()


func smoke_list() -> Array:
	var out := []
	for s in smokes:
		out.append([s[0], s[1]])
	return out


# --------------------------------------------------------------------------
# Frame update
# --------------------------------------------------------------------------

func _process(dt: float) -> void:
	time += dt
	var k := 1.0 - exp(-18.0 * dt)
	for o in own:
		o["disp"] = o["disp"].lerp(o["pos"], k)
		o["disp_facing"] = lerp_angle(o["disp_facing"], o["facing"], k)
	for idx in enemies:
		var e: Dictionary = enemies[idx]
		e["disp"] = e["disp"].lerp(e["pos"], k)
		e["disp_facing"] = lerp_angle(e["disp_facing"], e["facing"], k)
	_tick_list(tracers, dt)
	_tick_list(hurts, dt)
	_tick_list(scan_fx, dt)
	_tick_list(ghosts, dt)
	_tick_list(messages, dt)
	for a in 4:
		ability_flash[a] = maxf(0.0, ability_flash[a] - dt * 2.0)
	if vision_mask:
		vision_mask.reveal_all = state == Cfg.State.ENDED
	# Continuous right-drag facing
	if slot >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not menu_layer.visible:
		_face_send_t -= dt
		if _face_send_t <= 0.0:
			_face_send_t = 0.05
			Net.c_face.rpc_id(1, world.get_local_mouse_position())


func _tick_list(list: Array, dt: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		list[i]["t"] -= dt
		if list[i]["t"] <= 0.0:
			list.remove_at(i)


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if slot < 0 or menu_layer.visible or not Net.is_online():
		return
	if event is InputEventMouseButton and event.pressed:
		var mp := world.get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Clicking one of your soldiers selects it.
			for o in own:
				if o["alive"] and o["disp"].distance_to(mp) <= Cfg.SOLDIER_RADIUS + 5.0:
					_select(o["idx"])
					return
			Net.c_move.rpc_id(1, mp, event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_face_send_t = 0.05
			Net.c_face.rpc_id(1, mp)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _select(0)
			KEY_2: _select(1)
			KEY_3: _select(2)
			KEY_TAB: _cycle_select()
			KEY_Q: _use_ability(Cfg.Ability.SMOKE, false)
			KEY_E: _use_ability(Cfg.Ability.SCAN, false)
			KEY_R: _use_ability(Cfg.Ability.SUPPRESS, false)
			KEY_F: _use_ability(Cfg.Ability.RUSH, false)
			KEY_V: voice.toggle()
			KEY_ENTER, KEY_KP_ENTER:
				if state == Cfg.State.ENDED:
					Net.c_rematch.rpc_id(1)
			_: return
		get_viewport().set_input_as_handled()


func _select(idx: int) -> void:
	if idx < 0 or idx >= own.size() or not own[idx]["alive"]:
		return
	selected = idx
	_sel_lock_until = time + 0.4
	Net.c_select.rpc_id(1, idx)


func _cycle_select() -> void:
	for i in range(1, Cfg.SQUAD_SIZE + 1):
		var j := (selected + i) % Cfg.SQUAD_SIZE
		if own[j]["alive"]:
			_select(j)
			return


func _use_ability(ability: int, via_voice: bool) -> void:
	Net.c_ability.rpc_id(1, ability, world.get_local_mouse_position(), via_voice)


func _soldier_name(idx: int) -> String:
	match idx:
		0: return "ALPHA"
		1: return "BRAVO"
		2: return "CHARLIE"
		_: return "SOLDIER"


func _on_voice_command(cmd: Dictionary) -> void:
	var ctype: int = cmd.get("type", Voice.CmdType.NONE)
	if ctype == Voice.CmdType.NONE:
		return

	# Meta commands (deploy / rematch)
	if ctype == Voice.CmdType.DEPLOY:
		if menu_layer.visible:
			_msg("🎙️ Deploying...", Color(0.4, 0.9, 1.0))
			_on_connect_pressed()
		return
	elif ctype == Voice.CmdType.REMATCH:
		if state == Cfg.State.ENDED:
			_msg("🎙️ Rematch requested", Color(0.4, 0.9, 1.0))
			Net.c_rematch.rpc_id(1)
		return

	if slot < 0 or not Net.is_online():
		return

	sfx.play("voice", -8.0)
	var subj: int = cmd.get("subject", -2)

	match ctype:
		Voice.CmdType.SELECT:
			if subj >= 0:
				_select(subj)
				_msg("🎙️ Selected %s" % _soldier_name(subj), Color(0.4, 0.9, 1.0))

		Voice.CmdType.HALT:
			if subj == -1:
				var orig_sel := selected
				for i in Cfg.SQUAD_SIZE:
					if own[i]["alive"]:
						_select(i)
						Net.c_move.rpc_id(1, own[i]["disp"], false)
				if own[orig_sel]["alive"]:
					_select(orig_sel)
				_msg("🎙️ [SQUAD] HALT", Color(1.0, 0.8, 0.4))
			else:
				var target_idx: int = subj if subj >= 0 else selected
				if target_idx >= 0 and target_idx < own.size() and own[target_idx]["alive"]:
					if target_idx != selected:
						_select(target_idx)
					Net.c_move.rpc_id(1, own[target_idx]["disp"], false)
					_msg("🎙️ [%s] HALT" % _soldier_name(target_idx), Color(1.0, 0.8, 0.4))

		Voice.CmdType.MOVE_CALLOUT:
			var cid: String = cmd.get("param", "")
			var target_pos: Vector2 = map.callout_position(cid, slot)
			if target_pos == Vector2.ZERO:
				return
			if subj == -1:
				var offsets := [Vector2(-24, 0), Vector2(24, -20), Vector2(0, 24)]
				var orig_sel := selected
				for i in Cfg.SQUAD_SIZE:
					if own[i]["alive"]:
						_select(i)
						Net.c_move.rpc_id(1, target_pos + offsets[i], false)
				if own[orig_sel]["alive"]:
					_select(orig_sel)
				_msg("🎙️ [SQUAD] Move -> %s" % cid.to_upper(), Color(0.4, 0.9, 1.0))
			else:
				var target_idx: int = subj if subj >= 0 else selected
				if target_idx >= 0 and target_idx < own.size() and own[target_idx]["alive"]:
					if target_idx != selected:
						_select(target_idx)
					Net.c_move.rpc_id(1, target_pos, false)
					_msg("🎙️ [%s] Move -> %s" % [_soldier_name(target_idx), cid.to_upper()], Color(0.4, 0.9, 1.0))

		Voice.CmdType.MOVE_DIR:
			var dir_name: String = cmd.get("param", "")
			var angle: float = map.team_direction_angle(dir_name, slot)
			var step_vec := Vector2.from_angle(angle) * 140.0
			if subj == -1:
				var orig_sel := selected
				for i in Cfg.SQUAD_SIZE:
					if own[i]["alive"]:
						_select(i)
						var dest: Vector2 = own[i]["disp"] + step_vec
						dest.x = clampf(dest.x, Cfg.TILE, Cfg.WORLD_SIZE.x - Cfg.TILE)
						dest.y = clampf(dest.y, Cfg.TILE, Cfg.WORLD_SIZE.y - Cfg.TILE)
						Net.c_move.rpc_id(1, dest, false)
				if own[orig_sel]["alive"]:
					_select(orig_sel)
				_msg("🎙️ [SQUAD] Step %s" % dir_name.to_upper(), Color(0.4, 0.9, 1.0))
			else:
				var target_idx: int = subj if subj >= 0 else selected
				if target_idx >= 0 and target_idx < own.size() and own[target_idx]["alive"]:
					if target_idx != selected:
						_select(target_idx)
					var dest: Vector2 = own[target_idx]["disp"] + step_vec
					dest.x = clampf(dest.x, Cfg.TILE, Cfg.WORLD_SIZE.x - Cfg.TILE)
					dest.y = clampf(dest.y, Cfg.TILE, Cfg.WORLD_SIZE.y - Cfg.TILE)
					Net.c_move.rpc_id(1, dest, false)
					_msg("🎙️ [%s] Step %s" % [_soldier_name(target_idx), dir_name.to_upper()], Color(0.4, 0.9, 1.0))

		Voice.CmdType.WATCH_DIR:
			var dir_name: String = cmd.get("param", "")
			var angle: float = map.team_direction_angle(dir_name, slot)
			if subj == -1:
				var orig_sel := selected
				for i in Cfg.SQUAD_SIZE:
					if own[i]["alive"]:
						_select(i)
						Net.c_face.rpc_id(1, own[i]["disp"] + Vector2.from_angle(angle) * 100.0)
				if own[orig_sel]["alive"]:
					_select(orig_sel)
				_msg("🎙️ [SQUAD] Watch %s" % dir_name.to_upper(), Color(0.4, 0.9, 1.0))
			else:
				var target_idx: int = subj if subj >= 0 else selected
				if target_idx >= 0 and target_idx < own.size() and own[target_idx]["alive"]:
					if target_idx != selected:
						_select(target_idx)
					Net.c_face.rpc_id(1, own[target_idx]["disp"] + Vector2.from_angle(angle) * 100.0)
					_msg("🎙️ [%s] Watch %s" % [_soldier_name(target_idx), dir_name.to_upper()], Color(0.4, 0.9, 1.0))

		Voice.CmdType.WATCH_CALLOUT:
			var cid: String = cmd.get("param", "")
			var target_pos: Vector2 = map.callout_position(cid, slot)
			if target_pos == Vector2.ZERO:
				return
			if subj == -1:
				var orig_sel := selected
				for i in Cfg.SQUAD_SIZE:
					if own[i]["alive"]:
						_select(i)
						Net.c_face.rpc_id(1, target_pos)
				if own[orig_sel]["alive"]:
					_select(orig_sel)
				_msg("🎙️ [SQUAD] Watch %s" % cid.to_upper(), Color(0.4, 0.9, 1.0))
			else:
				var target_idx: int = subj if subj >= 0 else selected
				if target_idx >= 0 and target_idx < own.size() and own[target_idx]["alive"]:
					if target_idx != selected:
						_select(target_idx)
					Net.c_face.rpc_id(1, target_pos)
					_msg("🎙️ [%s] Watch %s" % [_soldier_name(target_idx), cid.to_upper()], Color(0.4, 0.9, 1.0))

		Voice.CmdType.ABILITY:
			var ab: int = cmd.get("ability", -1)
			if ab < 0 or not Cfg.ABILITIES.has(ab):
				return
			var target_idx: int = subj if subj >= 0 else selected
			if target_idx >= 0 and target_idx < own.size() and own[target_idx]["alive"]:
				if target_idx != selected:
					_select(target_idx)
			var target_pos := Vector2.ZERO
			var t_callout: String = cmd.get("target", "")
			if t_callout != "":
				target_pos = map.callout_position(t_callout, slot)
			else:
				var cur: Dictionary = own[selected]
				var face_ang: float = cur.get("disp_facing", cur.get("facing", 0.0))
				target_pos = cur.get("disp", Vector2.ZERO) + Vector2.from_angle(face_ang) * 160.0
			_msg("🎙️ [%s] %s" % [_soldier_name(selected), Cfg.ABILITIES[ab]["name"].to_upper()], Color(0.5, 1.0, 0.7))
			Net.c_ability.rpc_id(1, ab, target_pos, true)
