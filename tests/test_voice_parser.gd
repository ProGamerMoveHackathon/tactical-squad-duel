extends SceneTree
## Automated unit test suite for the tactical voice grammar parser.
## Run with:
##   godot --headless --path . --script res://tests/test_voice_parser.gd

func _init() -> void:
	var Voice = load("res://scripts/client/voice.gd")
	var Cfg = load("res://scripts/config.gd")
	var MapData = load("res://scripts/map_data.gd")
	var T = Voice.CmdType

	var cases := [
		# [Input, expected_type, expected_subject, expected_param_or_ability]
		# Fixed map points
		["alpha move to mid", T.MOVE_CALLOUT, 0, "mid"],
		["bravo go to kitchen", T.MOVE_CALLOUT, 1, "kitchen"],
		["charlie to tables", T.MOVE_CALLOUT, 2, "tables"],
		["delta move to the buffet", T.MOVE_CALLOUT, 3, "buffet"],
		["mid", T.MOVE_CALLOUT, -2, "mid"],
		["go to the buffet", T.MOVE_CALLOUT, -2, "buffet"],
		["rifle go to base", T.MOVE_CALLOUT, 0, "base"],
		["fall back to base", T.MOVE_CALLOUT, -2, "base"],
		["advance to kasse", T.MOVE_CALLOUT, -2, "cashier"],
		["squad move to the cashier", T.MOVE_CALLOUT, -1, "cashier"],
		["alpha take the top lane", T.MOVE_CALLOUT, 0, "top_lane"],
		["bravo terrace", T.MOVE_CALLOUT, 1, "bottom_lane"],
		["go to kitchen door", T.MOVE_CALLOUT, -2, "kitchen"],
		["charlie push enemy kitchen", T.MOVE_CALLOUT, 2, "enemy_kitchen"],
		["go to their tables", T.MOVE_CALLOUT, -2, "enemy_tables"],
		["all push to the enemy base", T.MOVE_CALLOUT, -1, "enemy_base"],
		["rush the exit", T.ABILITY, -2, Cfg.Ability.RUSH],
		# Directions (screen relative)
		["go left", T.MOVE_DIR, -2, "LEFT"],
		["alpha move up", T.MOVE_DIR, 0, "UP"],
		["north", T.MOVE_DIR, -2, "UP"],
		["move south", T.MOVE_DIR, -2, "DOWN"],
		["advance", T.MOVE_DIR, -2, "RIGHT"],
		["push forward", T.MOVE_DIR, -2, "RIGHT"],
		["fall back", T.MOVE_DIR, -2, "LEFT"],
		["step back", T.MOVE_DIR, -2, "LEFT"],
		["bravo go up and right", T.MOVE_DIR, 1, "UP-RIGHT"],
		["charlie northwest", T.MOVE_DIR, 2, "UP-LEFT"],
		["squad move down left", T.MOVE_DIR, -1, "DOWN-LEFT"],
		["go all the way right", T.MOVE_DIR, -2, "RIGHT"],
		# Watching
		["watch north", T.WATCH_DIR, -2, "UP"],
		["bravo watch left", T.WATCH_DIR, 1, "LEFT"],
		["charlie face east", T.WATCH_DIR, 2, "RIGHT"],
		["alpha cover mid", T.WATCH_CALLOUT, 0, "mid"],
		["squad look at the kitchen", T.WATCH_CALLOUT, -1, "kitchen"],
		["turn around", T.NONE, -2, null],
		# Halt
		["stop", T.HALT, -2, null],
		["alpha halt", T.HALT, 0, null],
		["squad hold", T.HALT, -1, null],
		["everyone hold position", T.HALT, -1, null],
		# Abilities
		["fog", T.ABILITY, -2, Cfg.Ability.FOG],
		["cast fog", T.ABILITY, -2, Cfg.Ability.FOG],
		["scan", T.ABILITY, -2, Cfg.Ability.SCAN],
		["squad rush", T.ABILITY, -1, Cfg.Ability.RUSH],
		["bravo sprint", T.ABILITY, 1, Cfg.Ability.RUSH],
		["outrage", T.ABILITY, -2, Cfg.Ability.OUTRAGE],
		["flash forward", T.ABILITY, -2, Cfg.Ability.FLASH],
		["break magic", T.ABILITY, -2, Cfg.Ability.BREAK_MAGIC],
		["switch weapon", T.ABILITY, -2, Cfg.Ability.BREAK_MAGIC],
		["fireball", T.ABILITY, -2, Cfg.Ability.FIREBALL],
		["fireball mid", T.ABILITY, -2, Cfg.Ability.FIREBALL],
		["charlie fireball the buffet", T.ABILITY, 2, Cfg.Ability.FIREBALL],
		["invisible", T.ABILITY, -2, Cfg.Ability.INVISIBLE],
		["smoke", T.ABILITY, -2, Cfg.Ability.FOG],
		["f*** magic", T.ABILITY, -2, Cfg.Ability.BREAK_MAGIC],
		["bravo fuck magic", T.ABILITY, 1, Cfg.Ability.BREAK_MAGIC],
		["cast fireball to the kitchen", T.ABILITY, -2, Cfg.Ability.FIREBALL],
		["use scan", T.ABILITY, -2, Cfg.Ability.SCAN],
		# Selection
		["alpha", T.SELECT, 0, null],
		["bravo", T.SELECT, 1, null],
		["select three", T.SELECT, 2, null],
		["delta", T.SELECT, 3, null],
		["four", T.SELECT, 3, null],
		["switch to charlie", T.SELECT, 2, null],
		["two", T.SELECT, 1, null],
		["next", T.SELECT_NEXT, -2, null],
		# "to" misheard as "two" must not select Bravo
		["go two kitchen", T.MOVE_CALLOUT, -2, "kitchen"],
		["alpha 2 mid", T.MOVE_CALLOUT, 0, "mid"],
		["two go left", T.MOVE_DIR, 1, "LEFT"],
		# Match flow
		["deploy", T.DEPLOY, -2, null],
		["rematch", T.REMATCH, -2, null],
		["play again", T.REMATCH, -2, null],
		# Noise
		["all right", T.NONE, -2, null],
		["what is for lunch", T.NONE, -2, null],
	]

	var passed := 0
	var failed := 0
	for c in cases:
		var raw: String = c[0]
		var res: Dictionary = Voice.parse_voice(raw)
		var actual_t: int = res.get("type", T.NONE)
		var actual_s: int = res.get("subject", -2)
		var actual_p = res.get("param", res.get("ability", null))
		var ok: bool = actual_t == c[1] and actual_s == c[2]
		if c[3] != null:
			ok = ok and actual_p == c[3]
		if ok:
			passed += 1
			print("  [PASS] %-32s -> %s" % [raw, Voice.format_action_tag(res)])
		else:
			failed += 1
			print("  [FAIL] %-32s -> expected(type=%d, subj=%d, p=%s) got(type=%d, subj=%d, p=%s)" % [
				raw, c[1], c[2], str(c[3]), actual_t, actual_s, str(actual_p)])

	# Chained orders: later orders reuse the previous soldier.
	var chain: Array = Voice.parse_utterance("bravo go to kitchen and then watch left and fog")
	var chain_ok: bool = chain.size() == 3 \
		and chain[0]["type"] == T.MOVE_CALLOUT and chain[0]["subject"] == 1 \
		and chain[1]["type"] == T.WATCH_DIR and chain[1]["subject"] == 1 \
		and chain[2]["type"] == T.ABILITY and chain[2]["subject"] == 1
	var chain2: Array = Voice.parse_utterance("alpha go to mid then charlie go to tables")
	chain_ok = chain_ok and chain2.size() == 2 and chain2[0]["subject"] == 0 and chain2[1]["subject"] == 2
	# A second move for the same soldier queues after the first; other soldiers don't.
	chain_ok = chain_ok and not chain[0]["queue"] and not chain2[1]["queue"]
	var chain3: Array = Voice.parse_utterance("alpha fall back to base then go up a bit")
	chain_ok = chain_ok and chain3.size() == 2 and not chain3[0]["queue"] and chain3[1]["queue"] \
		and chain3[1]["dist"] == "short"
	if chain_ok:
		passed += 1
		print("  [PASS] chained orders")
	else:
		failed += 1
		print("  [FAIL] chained orders: ", chain, " / ", chain2)

	# Spell slots: [input, slot, subject, target]. The ability is resolved later from the loadout.
	var spell_cases := [
		["spell one", 0, -2, ""],
		["spell two", 1, -2, ""],
		["spell 2", 1, -2, ""],
		["spell to", 1, -2, ""],
		["spell three", 2, -2, ""],
		["first spell", 0, -2, ""],
		["second ability", 1, -2, ""],
		["cast w", 0, -2, ""],
		["cast E", 1, -2, ""],
		["cast r", 2, -2, ""],
		["charlie spell three", 2, 2, ""],
		["bravo second spell mid", 1, 1, "mid"],
		["two spell one", 0, 1, ""],
		["squad use skill three", 2, -1, ""],
		["spell two at the enemy kitchen", 1, -2, "enemy_kitchen"],
	]
	for c in spell_cases:
		var res: Dictionary = Voice.parse_voice(c[0])
		if res.get("type") == T.ABILITY and res.get("ability") == -1 and res.get("slot") == c[1] \
				and res.get("subject") == c[2] and res.get("target") == c[3]:
			passed += 1
			print("  [PASS] %-32s -> %s" % [c[0], Voice.format_action_tag(res)])
		else:
			failed += 1
			print("  [FAIL] %-32s -> expected slot %d subj %d target '%s', got %s" % [c[0], c[1], c[2], c[3], res])
	var spell_chain: Array = Voice.parse_utterance("alpha go to mid and spell two")
	if spell_chain.size() == 2 and spell_chain[1]["type"] == T.ABILITY and spell_chain[1]["slot"] == 1 \
			and spell_chain[1]["subject"] == 0 and Voice.parse_voice("first").get("type") == T.SELECT:
		passed += 1
		print("  [PASS] spell slots chain and keep plain ordinals")
	else:
		failed += 1
		print("  [FAIL] spell slots chain and keep plain ordinals: ", spell_chain)

	# The Voice node resolves a slot against the loadout before emitting the order.
	var voice = Voice.new()
	var spoken := []
	voice.spell_resolver = func(subj: int, slot_idx: int) -> int:
		return [Cfg.Ability.FOG, Cfg.Ability.SCAN, Cfg.Ability.FIREBALL][slot_idx] if subj == 2 else -1
	voice.command_spoken.connect(func(cmd): spoken.append(cmd))
	voice.inject("charlie spell three mid")
	voice.inject("alpha spell one")
	voice._evaluate_results()
	if spoken.size() == 1 and spoken[0]["ability"] == Cfg.Ability.FIREBALL and spoken[0]["target"] == "mid" \
			and voice.history[0]["tags"] == ["CHARLIE FIREBALL > MID"] and voice.history.size() == 2 \
			and voice.history[1]["tags"].is_empty():
		passed += 1
		print("  [PASS] spell slot resolved from loadout")
	else:
		failed += 1
		print("  [FAIL] spell slot resolved from loadout: ", spoken, " / ", voice.history)
	voice.free()

	# Fireball without a target waits for the final result; with a target it can fire early.
	var timing_ok: bool = not Voice.is_complete(Voice.parse_voice("fireball")) \
		and Voice.is_complete(Voice.parse_voice("fireball kitchen")) \
		and Voice.is_complete(Voice.parse_voice("scan"))
	if timing_ok:
		passed += 1
		print("  [PASS] interim completeness")
	else:
		failed += 1
		print("  [FAIL] interim completeness")

	# Every callout (and enemy twin) must sit on open floor, mirrored for Red.
	var map = MapData.new()
	var floor_ok: bool = true
	for id in MapData.callout_ids():
		for team in 2:
			var p: Vector2 = map.callout_position(id, team)
			if p == Vector2.ZERO or map.is_wall_at(p):
				floor_ok = false
				print("  callout %s (team %d) is not on open floor: %s" % [id, team, p])
		if map.callout_position(id, 0) != Cfg.WORLD_SIZE - map.callout_position(id, 1):
			floor_ok = false
	if floor_ok:
		passed += 1
		print("  [PASS] callouts on open floor (%d points)" % MapData.callout_ids().size())
	else:
		failed += 1
		print("  [FAIL] callouts on open floor")

	print("\nTest results: %d passed, %d failed." % [passed, failed])
	quit(1 if failed > 0 else 0)
