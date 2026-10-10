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
var deployment := 0.0
var countdown := 0.0
var winner := -1
var selected := 0
var own := []          # Array of Dictionary
var enemies := {}      # idx -> Dictionary
var ghosts := []       # last known enemy positions
var scanned := []      # [[idx, pos]]
var enemy_alive := [true, true, true, true]
var smokes := []       # [[pos, r, t_left]]
var cooldowns := [0.0, 0.0, 0.0, 0.0]
var names := ["", ""]
var rematch_votes := [false, false]

# --- Effects -------------------------------------------------------------
var time := 0.0
var tracers := []
var magic_particles := []
var hurts := []
var corpses := []
var scan_fx := []
var messages := []
var ability_flash := [0.0, 0.0, 0.0, 0.0]

var world_rotation := 0.0
var voice_pings := []  # world markers for voice orders: {pos, label, t, max}
var _voice_dest := {}  # soldier idx -> destination of its last voice move
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
var world_light: CanvasModulate
var hud: Control
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var name_edit: LineEdit
var url_edit: LineEdit
var connect_btn: Button
var status_label: Label
var mic_btn: Button
var menu_panorama: TextureRect
var pause_layer: CanvasLayer
var pause_overlay: ColorRect
var pause_main_panel: VBoxContainer
var pause_settings_panel: VBoxContainer
var voice: Node
var sfx: Node


func _ready() -> void:
	_reset_own()
	voice = Voice.new()
	add_child(voice)
	voice.command_spoken.connect(_on_voice_command)
	voice.status_changed.connect(func(s): print("[Voice] ", s))
	sfx = Sfx.new()
	add_child(sfx)
	_build_world()
	_build_hud()
	_build_menu()
	_build_pause_menu()
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
##   --say="alpha go to kitchen;smoke mid"      feed voice commands once the match runs
func _setup_debug_hooks() -> void:
	if OS.has_feature("web"):
		return
	var say := _query_param("say")
	if say != "":
		var lines := Array(say.split(";", false))
		var timer := Timer.new()
		timer.wait_time = 1.2
		timer.autostart = true
		add_child(timer)
		timer.timeout.connect(func():
			if state == Cfg.State.PLAYING and not lines.is_empty():
				voice.inject(lines.pop_front()))
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
			var idx: int = step[0] % Cfg.SQUAD_SIZE
			_select(idx)
			var target := Cfg.WORLD_SIZE * 0.5 + Vector2(randf_range(-200, 60) * (1 if slot == 0 else -1), randf_range(-200, 200))
			Net.c_move.rpc_id(1, target, false)
			if step[0] == 4:
				_use_ability(Cfg.Ability.SMOKE, false)
			if step[0] == 5:
				_use_ability(Cfg.Ability.SUPPRESS, false))
	if _query_param("pause") != "":
		get_tree().create_timer(4.0).timeout.connect(_open_pause)


# --------------------------------------------------------------------------
# Scene construction
# --------------------------------------------------------------------------

func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	world_light = CanvasModulate.new()
	world_light.color = Color.WHITE
	world.add_child(world_light)
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
	blocker.size = Vector2(Cfg.WORLD_SIZE.x, Hud.BAR_H)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_layer.add_child(blocker)
	mic_btn = Button.new()
	mic_btn.focus_mode = Control.FOCUS_NONE
	mic_btn.position = Vector2(Cfg.WORLD_SIZE.x - 82, Cfg.WORLD_SIZE.y + 10)
	mic_btn.size = Vector2(72, 22)
	mic_btn.add_theme_font_size_override("font_size", 11)
	mic_btn.pressed.connect(_toggle_voice)
	hud_layer.add_child(mic_btn)
	hud_layer.visible = false


func _toggle_voice() -> void:
	if not voice.available:
		_msg("Voice needs Chrome / Edge / Safari (web build). Keys still work.", Color(1.0, 0.7, 0.4))
		return
	voice.toggle()


func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu_panorama = TextureRect.new()
	menu_panorama.name = "CampusFlythrough"
	menu_panorama.texture = load("res://assets/eth_campus_panorama_pixel.png")
	menu_panorama.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_panorama.stretch_mode = TextureRect.STRETCH_SCALE
	menu_panorama.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	menu_panorama.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panorama_ratio := float(menu_panorama.texture.get_width()) / float(menu_panorama.texture.get_height())
	var menu_height: float = get_viewport().get_visible_rect().size.y
	menu_panorama.size = Vector2(menu_height * panorama_ratio, menu_height)
	menu_layer.add_child(menu_panorama)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.025, 0.065, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(center)
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.012, 0.03, 0.06, 0.96)
	panel_style.border_color = Color(0.72, 0.91, 1.0, 0.98)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", panel_style)
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
	title.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.55, 0.85, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "1 vs 1 · 4 soldiers each · see them before they see you"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.38, 0.88, 1.0))
	box.add_child(sub)
	box.add_child(HSeparator.new())

	var name_label := Label.new()
	name_label.text = "Callsign"
	name_label.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	box.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.max_length = 16
	_style_menu_field(name_edit)
	var qn := _query_param("name")
	name_edit.text = qn if qn != "" else "Player%d" % (randi() % 900 + 100)
	box.add_child(name_edit)
	var url_label := Label.new()
	url_label.text = "Server"
	url_label.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	box.add_child(url_label)
	url_edit = LineEdit.new()
	url_edit.text = _default_url()
	_style_menu_field(url_edit)
	box.add_child(url_edit)
	connect_btn = Button.new()
	connect_btn.text = "Deploy"
	connect_btn.custom_minimum_size = Vector2(0, 40)
	_style_menu_button(connect_btn)
	connect_btn.pressed.connect(_on_connect_pressed)
	box.add_child(connect_btn)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.28))
	status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	box.add_child(HSeparator.new())
	var help := Label.new()
	help.text = "VOICE COMMANDS  ([who] [action] [where], mic starts on Deploy, V toggles)\n" \
		+ "- Who: \"Alpha\" / \"Bravo\" / \"Charlie\" / \"Delta\" / \"Squad\" (or nobody = selected soldier)\n" \
		+ "- Places: \"Bravo go to kitchen\", \"Squad to mid\", \"Charlie push enemy tables\"\n" \
		+ "- Directions: \"Go left\", \"Alpha move up\", \"Advance\", \"Fall back a bit\", \"Stop\"\n" \
		+ "- Aim: \"Watch left\", \"Bravo cover mid\"   - Abilities: \"Smoke kitchen\", \"Scan\", \"Rush\"\n" \
		+ "- Chain: \"Bravo go to buffet and watch right\"   - Match: \"Rematch\"\n\n" \
		+ "Fallback: LMB move · RMB face · 1-4 / numpad select · Q E R F abilities · V mic toggle"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.82, 0.9, 0.96))
	box.add_child(help)
	name_edit.text_submitted.connect(func(_t): _on_connect_pressed())
	url_edit.text_submitted.connect(func(_t): _on_connect_pressed())


func _build_pause_menu() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 20
	add_child(pause_layer)
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.0, 0.006, 0.018, 0.88)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	pause_layer.add_child(pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 430)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.04, 0.07, 0.98)
	panel_style.border_color = Color(0.28, 0.82, 1.0, 0.92)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 34
	panel_style.content_margin_right = 34
	panel_style.content_margin_top = 28
	panel_style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var menu_content := Control.new()
	menu_content.custom_minimum_size = Vector2(356, 366)
	panel.add_child(menu_content)

	pause_main_panel = VBoxContainer.new()
	pause_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_main_panel.add_theme_constant_override("separation", 12)
	menu_content.add_child(pause_main_panel)
	var pause_title := Label.new()
	pause_title.text = "PAUSE MENU"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.add_theme_font_size_override("font_size", 32)
	pause_title.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	pause_main_panel.add_child(pause_title)
	var warning := Label.new()
	warning.text = "ONLINE MATCH CONTINUES WHILE THIS MENU IS OPEN"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 14)
	warning.add_theme_color_override("font_color", Color(1.0, 0.52, 0.28))
	pause_main_panel.add_child(warning)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	pause_main_panel.add_child(spacer)
	var resume_button := Button.new()
	resume_button.text = "RESUME"
	resume_button.custom_minimum_size.y = 54
	_style_menu_button(resume_button)
	resume_button.pressed.connect(_close_pause)
	pause_main_panel.add_child(resume_button)
	var settings_button := Button.new()
	settings_button.text = "SETTINGS"
	settings_button.custom_minimum_size.y = 54
	_style_menu_button(settings_button)
	settings_button.pressed.connect(_show_pause_settings)
	pause_main_panel.add_child(settings_button)
	var leave_button := Button.new()
	leave_button.text = "LEAVE GAME"
	leave_button.custom_minimum_size.y = 54
	_style_menu_button(leave_button)
	leave_button.pressed.connect(_leave_match)
	pause_main_panel.add_child(leave_button)

	pause_settings_panel = VBoxContainer.new()
	pause_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_settings_panel.add_theme_constant_override("separation", 18)
	pause_settings_panel.visible = false
	menu_content.add_child(pause_settings_panel)
	var settings_title := Label.new()
	settings_title.text = "SETTINGS"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 32)
	pause_settings_panel.add_child(settings_title)
	var volume_label := Label.new()
	volume_label.text = "MASTER VOLUME"
	volume_label.add_theme_font_size_override("font_size", 17)
	pause_settings_panel.add_child(volume_label)
	var volume_slider := HSlider.new()
	volume_slider.min_value = -30.0
	volume_slider.max_value = 0.0
	volume_slider.step = 1.0
	volume_slider.value = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	volume_slider.custom_minimum_size.y = 48
	volume_slider.value_changed.connect(_set_master_volume)
	pause_settings_panel.add_child(volume_slider)
	var hint := Label.new()
	hint.text = "Adjust game sound effects and alerts. Online play continues in the background."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.72, 0.82, 0.9))
	pause_settings_panel.add_child(hint)
	var settings_spacer := Control.new()
	settings_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pause_settings_panel.add_child(settings_spacer)
	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size.y = 54
	_style_menu_button(back_button)
	back_button.pressed.connect(_show_pause_main)
	pause_settings_panel.add_child(back_button)

	var controls_margin := MarginContainer.new()
	controls_margin.set_anchor(SIDE_LEFT, 1.0)
	controls_margin.set_anchor(SIDE_RIGHT, 1.0)
	controls_margin.set_anchor(SIDE_TOP, 0.5)
	controls_margin.set_anchor(SIDE_BOTTOM, 0.5)
	controls_margin.offset_left = -300
	controls_margin.offset_right = -20
	controls_margin.offset_top = -170
	controls_margin.offset_bottom = 170
	pause_overlay.add_child(controls_margin)
	var controls_panel := PanelContainer.new()
	var controls_style := StyleBoxFlat.new()
	controls_style.bg_color = Color(0.018, 0.04, 0.07, 0.96)
	controls_style.border_color = Color(0.24, 0.62, 0.8, 0.88)
	controls_style.set_border_width_all(2)
	controls_style.set_corner_radius_all(10)
	controls_style.content_margin_left = 20
	controls_style.content_margin_right = 20
	controls_style.content_margin_top = 18
	controls_style.content_margin_bottom = 18
	controls_panel.add_theme_stylebox_override("panel", controls_style)
	controls_margin.add_child(controls_panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls_panel.add_child(controls)
	var controls_title := Label.new()
	controls_title.text = "CONTROLS"
	controls_title.add_theme_font_size_override("font_size", 20)
	controls.add_child(controls_title)
	var help := Label.new()
	help.text = "1–4 / Numpad: select soldier\nTab: next living soldier\nLeft click: move / select\nRight click: face direction\nQ: smoke · E: scan\nR: suppress · F: rush\nV: voice toggle\nEscape: close menu"
	help.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	controls.add_child(help)


func _open_pause() -> void:
	if pause_overlay == null or slot < 0:
		return
	pause_overlay.visible = true
	pause_main_panel.visible = true
	pause_settings_panel.visible = false
	sfx.play("voice", -10.0)


func _close_pause() -> void:
	if pause_overlay == null:
		return
	pause_overlay.visible = false
	pause_main_panel.visible = true
	pause_settings_panel.visible = false
	sfx.play("voice", -10.0)


func _show_pause_settings() -> void:
	pause_main_panel.visible = false
	pause_settings_panel.visible = true
	sfx.play("voice", -10.0)


func _show_pause_main() -> void:
	pause_settings_panel.visible = false
	pause_main_panel.visible = true
	sfx.play("voice", -10.0)


func _set_master_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), clampf(value, -30.0, 0.0))


func _leave_match() -> void:
	_close_pause()
	_connected = false
	slot = -1
	Net.leave()
	_show_menu(true, "Left online match.")


func _style_menu_field(field: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.018, 0.055, 0.1, 0.98)
	normal.border_color = Color(0.28, 0.76, 0.96, 0.95)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var focus := normal.duplicate()
	focus.bg_color = Color(0.025, 0.12, 0.2, 1.0)
	focus.border_color = Color(1.0, 0.83, 0.28, 1.0)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
	field.add_theme_color_override("caret_color", Color(0.38, 0.88, 1.0))
	field.add_theme_color_override("selection_color", Color(0.08, 0.45, 0.62, 0.9))


func _style_menu_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.32, 0.46, 0.98)
	normal.border_color = Color(0.28, 0.76, 0.96, 0.95)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.06, 0.45, 0.62, 1.0)
	hover.border_color = Color(0.82, 0.96, 1.0, 1.0)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.015, 0.2, 0.3, 1.0)
	pressed.border_color = Color(1.0, 0.83, 0.28, 1.0)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.02, 0.06, 0.09, 0.94)
	disabled.border_color = Color(0.24, 0.36, 0.43, 0.9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.65, 0.72))
	button.add_theme_font_size_override("font_size", 16)


func _show_menu(show: bool, status: String) -> void:
	if show and pause_overlay != null:
		pause_overlay.visible = false
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
	magic_particles.clear()
	hurts.clear()
	corpses.clear()
	scan_fx.clear()


func _on_snapshot(d: Dictionary) -> void:
	var prev_state := state
	state = d["st"]
	if state == Cfg.State.DEPLOYMENT and prev_state != Cfg.State.DEPLOYMENT:
		_reset_round_visuals()
		sfx.play("start", -4.0)
	if state == Cfg.State.COUNTDOWN and prev_state == Cfg.State.DEPLOYMENT:
		sfx.play("start", -6.0)
	if state == Cfg.State.WAITING and prev_state != Cfg.State.WAITING:
		_reset_round_visuals()
	deployment = d.get("dp", 0.0)
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
			var spell_color := Color(0.12, 0.92, 1.0) if team == slot else Color(1.0, 0.16, 0.72)
			for end in ev[4]:
				tracers.append({"a": from, "b": end, "t": 0.26, "max": 0.26,
					"color": spell_color, "seed": randf() * TAU, "hit": ev[5] > 0})
				_spawn_magic_burst(end, spell_color.lerp(Color.WHITE, 0.35), (end - from).normalized(), 7 if ev[5] > 0 else 3)
			_spawn_magic_burst(from, spell_color, Vector2.from_angle(own[ev[2]]["disp_facing"]) if team == slot and ev[2] < own.size() else Vector2.RIGHT, 8)
			var snd: String = ["cast", "cast_fast", "cast_burst"][weapon]
			sfx.play(snd, -10.0 if team == slot else -6.0)
			if ev[5] > 0 and team != slot:
				sfx.play("hit", -4.0)
		"incoming":
			hurts.append({"idx": ev[1], "angle": ev[2], "dmg": ev[3], "t": 1.2})
			if ev[1] < own.size():
				var incoming_dir := Vector2.from_angle(ev[2])
				_spawn_magic_burst(own[ev[1]]["disp"] + incoming_dir * Cfg.SOLDIER_RADIUS, Color(1.0, 0.18, 0.72), -incoming_dir, 9)
			sfx.play("cast_fast" if ev[3] == 0 else "hit", -12.0 if ev[3] == 0 else -4.0)
		"kill":
			var team: int = ev[1]
			var idx: int = ev[2]
			corpses.append({"pos": ev[3], "team": team, "idx": idx})
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


func _spawn_magic_burst(at: Vector2, col: Color, direction: Vector2, amount: int) -> void:
	var base_angle := direction.angle() if direction.length_squared() > 0.001 else 0.0
	for _i in amount:
		var angle := base_angle + randf_range(-0.95, 0.95)
		magic_particles.append({
			"pos": at + Vector2.from_angle(angle) * randf_range(0.0, 4.0),
			"vel": Vector2.from_angle(angle) * randf_range(35.0, 115.0),
			"t": randf_range(0.20, 0.42),
			"max": 0.42,
			"color": col,
			"size": randf_range(1.5, 3.3),
		})


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
	if menu_layer != null and menu_layer.visible and menu_panorama != null:
		var travel := maxf(0.0, menu_panorama.size.x - get_viewport().get_visible_rect().size.x)
		var flythrough := 0.5 - 0.5 * cos(time * 0.15)
		menu_panorama.position = Vector2(-travel * flythrough, sin(time * 0.21) * 8.0)
	var k := 1.0 - exp(-18.0 * dt)
	for o in own:
		o["disp"] = o["disp"].lerp(o["pos"], k)
		o["disp_facing"] = lerp_angle(o["disp_facing"], o["facing"], k)
	for idx in enemies:
		var e: Dictionary = enemies[idx]
		e["disp"] = e["disp"].lerp(e["pos"], k)
		e["disp_facing"] = lerp_angle(e["disp_facing"], e["facing"], k)
	_tick_list(tracers, dt)
	_tick_magic_particles(dt)
	_tick_list(hurts, dt)
	_tick_list(scan_fx, dt)
	_tick_list(ghosts, dt)
	_tick_list(messages, dt)
	_tick_list(voice_pings, dt)
	if mic_btn:
		mic_btn.text = "Mic ON [V]" if voice.enabled else "Mic OFF [V]"
	for a in 4:
		ability_flash[a] = maxf(0.0, ability_flash[a] - dt * 2.0)
	if vision_mask:
		vision_mask.reveal_all = state == Cfg.State.DEPLOYMENT or state == Cfg.State.COUNTDOWN or state == Cfg.State.ENDED
	if world_light:
		if state == Cfg.State.DEPLOYMENT:
			world_light.color = Color(1.0, 0.98, 0.90)
		elif state == Cfg.State.COUNTDOWN:
			var light_level := _countdown_light_level()
			world_light.color = Color(light_level, light_level * 0.96, light_level * 0.82)
		else:
			world_light.color = Color.WHITE
	# Continuous right-drag facing
	if slot >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not menu_layer.visible and not pause_overlay.visible:
		_face_send_t -= dt
		if _face_send_t <= 0.0:
			_face_send_t = 0.05
			Net.c_face.rpc_id(1, world.get_local_mouse_position())


func _countdown_light_level() -> float:
	var elapsed := clampf(Cfg.COUNTDOWN - countdown, 0.0, Cfg.COUNTDOWN)
	# One blink, a long pause, two blinks, three blinks, then a final shutdown.
	for centre in [0.18, 0.90, 1.08, 1.55, 1.71, 1.87]:
		var distance: float = absf(elapsed - centre)
		if distance < 0.065:
			return lerpf(0.12, 1.0, smoothstep(0.0, 0.065, distance))
	if elapsed >= 2.45:
		return lerpf(1.0, 0.12, smoothstep(2.45, 2.62, elapsed))
	return 1.0


func _tick_list(list: Array, dt: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		list[i]["t"] -= dt
		if list[i]["t"] <= 0.0:
			list.remove_at(i)


func _tick_magic_particles(dt: float) -> void:
	for i in range(magic_particles.size() - 1, -1, -1):
		var p: Dictionary = magic_particles[i]
		p["t"] -= dt
		p["pos"] += p["vel"] * dt
		p["vel"] *= exp(-5.0 * dt)
		if p["t"] <= 0.0:
			magic_particles.remove_at(i)


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		if slot >= 0 and not menu_layer.visible:
			if pause_overlay.visible and pause_settings_panel.visible:
				_show_pause_main()
			elif pause_overlay.visible:
				_close_pause()
			else:
				_open_pause()
			get_viewport().set_input_as_handled()
		return
	if slot < 0 or menu_layer.visible or not Net.is_online():
		return
	if pause_overlay.visible:
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
		var number_selection := _number_key_selection(event)
		if number_selection >= 0:
			_select(number_selection)
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_TAB: _cycle_select()
			KEY_Q: _use_ability(Cfg.Ability.SMOKE, false)
			KEY_E: _use_ability(Cfg.Ability.SCAN, false)
			KEY_R: _use_ability(Cfg.Ability.SUPPRESS, false)
			KEY_F: _use_ability(Cfg.Ability.RUSH, false)
			KEY_V: _toggle_voice()
			KEY_ENTER, KEY_KP_ENTER:
				if state == Cfg.State.ENDED:
					Net.c_rematch.rpc_id(1)
			_: return
		get_viewport().set_input_as_handled()


func _number_key_selection(event: InputEventKey) -> int:
	for code in [event.keycode, event.physical_keycode]:
		match code:
			KEY_1, KEY_KP_1: return 0
			KEY_2, KEY_KP_2: return 1
			KEY_3, KEY_KP_3: return 2
			KEY_4, KEY_KP_4: return 3
	return -1


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
	return Voice.SUBJECT_NAMES.get(idx, "SOLDIER")


func _on_voice_command(cmd: Dictionary) -> void:
	var ctype: int = cmd.get("type", Voice.CmdType.NONE)
	if ctype == Voice.CmdType.NONE:
		return

	if ctype == Voice.CmdType.DEPLOY:
		if menu_layer.visible and not connect_btn.disabled:
			_on_connect_pressed()
		return
	elif ctype == Voice.CmdType.REMATCH:
		if state == Cfg.State.ENDED and Net.is_online():
			Net.c_rematch.rpc_id(1)
		return

	if slot < 0 or not Net.is_online():
		return

	if state != Cfg.State.PLAYING and state != Cfg.State.COUNTDOWN:
		return
	sfx.play("voice", -8.0)
	var subj: int = cmd.get("subject", -2)
	var units := _voice_units(subj)
	if units.is_empty():
		_msg("%s is down" % _soldier_name(subj if subj >= 0 else selected), Color(1.0, 0.5, 0.4))
		return
	if subj >= 0:
		_select(subj)

	match ctype:
		Voice.CmdType.SELECT_NEXT:
			_cycle_select()

		Voice.CmdType.HALT:
			for i in units:
				Net.c_unit_stop.rpc_id(1, i)
				_ping(own[i]["pos"], "")

		Voice.CmdType.MOVE_CALLOUT:
			var cid: String = cmd["param"]
			var target := map.callout_position(cid, slot)
			var spots := _formation(target, units.size())
			for k in units.size():
				_voice_move(units[k], spots[k], cmd.get("queue", false))
			_ping(target, MapData.callout_label(cid))

		Voice.CmdType.MOVE_DIR:
			var dir := _world_dir(cmd["dir"])
			var max_d: float = {"short": Cfg.VOICE_STEP_SHORT, "far": Cfg.VOICE_STEP_FAR}.get(cmd.get("dist", ""), Cfg.VOICE_STEP)
			var queue: bool = cmd.get("queue", false)
			for i in units:
				var from: Vector2 = _voice_dest.get(i, own[i]["pos"]) if queue else own[i]["pos"]
				var dest := _dir_destination(from, dir, max_d)
				_voice_move(i, dest, queue)
				_ping(dest, "")

		Voice.CmdType.WATCH_DIR:
			var dir := _world_dir(cmd["dir"])
			for i in units:
				Net.c_unit_face.rpc_id(1, i, own[i]["pos"] + dir * 100.0)
				_ping(own[i]["pos"] + dir * 48.0, "")

		Voice.CmdType.WATCH_CALLOUT:
			var cid: String = cmd["param"]
			var target := map.callout_position(cid, slot)
			for i in units:
				Net.c_unit_face.rpc_id(1, i, target)
			_ping(target, MapData.callout_label(cid))

		Voice.CmdType.ABILITY:
			var ab: int = cmd["ability"]
			var caster: Dictionary = own[selected]
			var target: Vector2 = caster["pos"] + Vector2.from_angle(caster["facing"]) * 160.0
			if cmd.get("target", "") != "":
				target = map.callout_position(cmd["target"], slot)
			elif cmd.get("dir", Vector2.ZERO) != Vector2.ZERO:
				target = caster["pos"] + _world_dir(cmd["dir"]) * 200.0
			Net.c_ability.rpc_id(1, ab, target, true)
			if ab == Cfg.Ability.SMOKE:
				_ping(target, "SMOKE")


func _voice_move(idx: int, dest: Vector2, queue: bool) -> void:
	Net.c_unit_move.rpc_id(1, idx, dest, queue)
	_voice_dest[idx] = dest


## Soldiers a voice order applies to: the named one, the whole squad, or the
## selected soldier when nobody was named. Dead soldiers are skipped.
func _voice_units(subj: int) -> Array:
	var out := []
	for i in Cfg.SQUAD_SIZE:
		if own[i]["alive"] and (subj == -1 or i == (subj if subj >= 0 else selected)):
			out.append(i)
	return out


## Screen-relative direction (x right, y down) -> world direction. Red's world
## is rotated 180 degrees on screen.
func _world_dir(screen_dir: Vector2) -> Vector2:
	return screen_dir.rotated(-world_rotation)


## Walk straight until a wall; if something blocks the way right in front of the
## soldier, aim further out and let the server's A* path around it.
func _dir_destination(from: Vector2, dir: Vector2, max_d: float) -> Vector2:
	var d := map.walk_distance(from, dir, max_d, Cfg.SOLDIER_RADIUS)
	if d >= Cfg.TILE * 1.5:
		return from + dir * d
	var far := from + dir * minf(max_d, Cfg.VOICE_STEP)
	return Vector2(clampf(far.x, Cfg.TILE, Cfg.WORLD_SIZE.x - Cfg.TILE), clampf(far.y, Cfg.TILE, Cfg.WORLD_SIZE.y - Cfg.TILE))


## Spread squad members around a destination: one on the spot, two slightly
## behind on either side and one further back (from this player's point of view).
func _formation(target: Vector2, count: int) -> Array:
	var fwd := _world_dir(Vector2.RIGHT)
	var side := fwd.orthogonal()
	var offsets := [Vector2.ZERO, side * 28.0 - fwd * 16.0, -side * 28.0 - fwd * 16.0, -fwd * 36.0]
	var out := []
	for k in count:
		var p: Vector2 = target + offsets[k % offsets.size()]
		out.append(target if map.is_wall_at(p) else p)
	return out


func _ping(pos: Vector2, label: String) -> void:
	voice_pings.append({"pos": pos, "label": label, "t": 1.6, "max": 1.6})
