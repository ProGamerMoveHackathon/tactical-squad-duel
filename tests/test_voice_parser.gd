extends SceneTree
## Automated unit test suite for the tactical voice grammar parser.
## Run with:
##   godot --headless --path . --script res://tests/test_voice_parser.gd

func _init() -> void:
	var Voice = load("res://scripts/client/voice.gd")
	var Cfg = load("res://scripts/config.gd")
	var T = Voice.CmdType

	var cases := [
		# [Input, expected_type, expected_subject, expected_param_or_ability]
		# Directions (screen relative compass words)
		["alpha move up", T.MOVE_DIR, 0, "UP"],
		["north", T.MOVE_DIR, -2, "UP"],
		["move south", T.MOVE_DIR, -2, "DOWN"],
		["go east", T.MOVE_DIR, -2, "RIGHT"],
		["bravo go up and right", T.MOVE_DIR, 1, "UP-RIGHT"],
		["charlie northwest", T.MOVE_DIR, 2, "UP-LEFT"],
		["squad move down left", T.MOVE_DIR, -1, "DOWN-LEFT"],
		# Steering relative to the soldier
		["go left", T.STEER, -2, null],
		["advance", T.STEER, -2, null],
		["push forward", T.STEER, -2, null],
		["fall back", T.STEER, -2, null],
		["step back", T.STEER, -2, null],
		["go all the way right", T.STEER, -2, null],
		# Watching
		["watch north", T.WATCH_DIR, -2, "UP"],
		["bravo watch left", T.WATCH_DIR, 1, "LEFT"],
		["charlie face east", T.WATCH_DIR, 2, "RIGHT"],
		["watch ahead", T.NONE, -2, null],
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
		["fireball left", T.ABILITY, -2, Cfg.Ability.FIREBALL],
		["charlie fireball right", T.ABILITY, 2, Cfg.Ability.FIREBALL],
		["invisible", T.ABILITY, -2, Cfg.Ability.INVISIBLE],
		["smoke", T.ABILITY, -2, Cfg.Ability.FOG],
		["f*** magic", T.ABILITY, -2, Cfg.Ability.BREAK_MAGIC],
		["bravo fuck magic", T.ABILITY, 1, Cfg.Ability.BREAK_MAGIC],
		["cast fireball up", T.ABILITY, -2, Cfg.Ability.FIREBALL],
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
		# "to" misheard as "two"
		["two go left", T.STEER, 1, null],
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
	var chain: Array = Voice.parse_utterance("bravo move north and then watch left and fog")
	var chain_ok: bool = chain.size() == 3 \
		and chain[0]["type"] == T.MOVE_DIR and chain[0]["subject"] == 1 \
		and chain[1]["type"] == T.WATCH_DIR and chain[1]["subject"] == 1 \
		and chain[2]["type"] == T.ABILITY and chain[2]["subject"] == 1
	var chain2: Array = Voice.parse_utterance("alpha move up then charlie move south")
	chain_ok = chain_ok and chain2.size() == 2 and chain2[0]["subject"] == 0 and chain2[1]["subject"] == 2
	# A second move for the same soldier queues after the first; other soldiers don't.
	chain_ok = chain_ok and not chain[0]["queue"] and not chain2[1]["queue"]
	var chain3: Array = Voice.parse_utterance("alpha move south then go up a bit")
	chain_ok = chain_ok and chain3.size() == 2 and not chain3[0]["queue"] and chain3[1]["queue"] \
		and chain3[1]["dist"] == "short"
	var chain4: Array = Voice.parse_utterance("alpha move up then move up")
	chain_ok = chain_ok and chain4.size() == 2 and not chain4[0]["queue"] and chain4[1]["queue"] \
		and chain4[0]["step"] == 0 and chain4[1]["step"] == 1
	var sig0: String = Voice.command_signature(chain4[0])
	var sig1: String = Voice.command_signature(chain4[1])
	chain_ok = chain_ok and sig0 != sig1
	if chain_ok:
		passed += 1
		print("  [PASS] chained orders")
	else:
		failed += 1
		print("  [FAIL] chained orders: ", chain, " / ", chain2, " / ", chain4)

	# Steering: [input, subject, move, turn, tiles, dist]. move 1 = forward, -1 = back; turn in degrees (+ = right).
	var steer_cases := [
		["alpha forward", 0, 1, 0.0, 0, ""],
		["alpha stop", 0, null, null, null, null],
		["alpha backward", 0, -1, 0.0, 0, ""],
		["alpha back", 0, -1, 0.0, 0, ""],
		["alpha left 30", 0, 0, -30.0, 0, ""],
		["alpha left 30 degrees", 0, 0, -30.0, 0, ""],
		["bravo right forty five", 1, 0, 45.0, 0, ""],
		["turn left", -2, 0, -90.0, 0, ""],
		["charlie right", 2, 0, 90.0, 0, ""],
		["a bit left", -2, 0, -30.0, 0, ""],
		["go left", -2, 1, -90.0, 0, ""],
		["go right 20", -2, 1, 20.0, 0, ""],
		["alpha forward 5", 0, 1, 0.0, 5, ""],
		["bravo back two tiles", 1, -1, 0.0, 2, ""],
		["forward a bit", -2, 1, 0.0, 0, "short"],
		["step back", -2, -1, 0.0, 0, "short"],
		["go all the way right", -2, 1, 90.0, 0, "far"],
		["squad advance", -1, 1, 0.0, 0, ""],
		["turn around", -2, 0, 180.0, 0, ""],
		["delta about face", 3, 0, 180.0, 0, ""],
		["keep going", -2, 1, 0.0, 0, ""],
		["alpha turn right a hundred", 0, 0, 100.0, 0, ""],
		["alpha left 120", 0, 0, -120.0, 0, ""],
		["alpha left 180", 0, 0, -180.0, 0, ""],
		["alpha right one eighty", 0, 0, 180.0, 0, ""],
		["alpha right one twenty", 0, 0, 120.0, 0, ""],
		["alpha left one thirty five", 0, 0, -135.0, 0, ""],
		["alpha left one hundred and twenty", 0, 0, -120.0, 0, ""],
		["alpha turn right 270", 0, 0, 270.0, 0, ""],
		["advance two tiles", -2, 1, 0.0, 2, ""],
		["advance too tiles", -2, 1, 0.0, 2, ""],
		["go two tiles", -2, 1, 0.0, 2, ""],
		["push two tiles", -2, 1, 0.0, 2, ""],
		["move two tiles", -2, 1, 0.0, 2, ""],
		["alpha advance two tiles", 0, 1, 0.0, 2, ""],
	]
	for c in steer_cases:
		var res: Dictionary = Voice.parse_voice(c[0])
		var ok: bool
		if c[2] == null:
			ok = res.get("type") == T.HALT and res.get("subject") == c[1]
		else:
			ok = res.get("type") == T.STEER and res.get("subject") == c[1] and res.get("move") == c[2] \
				and is_equal_approx(res.get("turn", 999.0), c[3]) and res.get("tiles") == c[4] and res.get("dist") == c[5]
		if ok:
			passed += 1
			print("  [PASS] %-32s -> %s" % [c[0], Voice.format_action_tag(res)])
		else:
			failed += 1
			print("  [FAIL] %-32s -> expected subj %s move %s turn %s tiles %s dist '%s', got %s" % [c[0], c[1], c[2], c[3], c[4], c[5], res])
	# A bare turn waits for a possible number; a numbered turn or a walk can fire from interim text.
	var steer_timing: bool = not Voice.is_complete(Voice.parse_voice("alpha left")) \
		and Voice.is_complete(Voice.parse_voice("alpha left 30")) \
		and Voice.is_complete(Voice.parse_voice("alpha forward")) \
		and Voice.is_complete(Voice.parse_voice("turn around"))
	var steer_chain: Array = Voice.parse_utterance("alpha left 30 and forward")
	steer_timing = steer_timing and steer_chain.size() == 2 and steer_chain[1]["type"] == T.STEER \
		and steer_chain[1]["subject"] == 0 and steer_chain[1]["move"] == 1
	if steer_timing:
		passed += 1
		print("  [PASS] steering timing and chaining")
	else:
		failed += 1
		print("  [FAIL] steering timing and chaining: ", steer_chain)

	# Spell slots: [input, slot, subject, dir]. The ability is resolved later from the loadout.
	var spell_cases := [
		["spell one", 0, -2, Vector2.ZERO],
		["spell two", 1, -2, Vector2.ZERO],
		["spell 2", 1, -2, Vector2.ZERO],
		["spell to", 1, -2, Vector2.ZERO],
		["spell three", 2, -2, Vector2.ZERO],
		["first spell", 0, -2, Vector2.ZERO],
		["second ability", 1, -2, Vector2.ZERO],
		["cast w", 0, -2, Vector2.ZERO],
		["cast E", 1, -2, Vector2.ZERO],
		["cast r", 2, -2, Vector2.ZERO],
		["charlie spell three", 2, 2, Vector2.ZERO],
		["bravo second spell right", 1, 1, Vector2(1, 0)],
		["two spell one", 0, 1, Vector2.ZERO],
		["squad use skill three", 2, -1, Vector2.ZERO],
		["spell two left", 1, -2, Vector2(-1, 0)],
	]
	for c in spell_cases:
		var res: Dictionary = Voice.parse_voice(c[0])
		if res.get("type") == T.ABILITY and res.get("ability") == -1 and res.get("slot") == c[1] \
				and res.get("subject") == c[2] and res.get("dir", Vector2.ZERO) == c[3]:
			passed += 1
			print("  [PASS] %-32s -> %s" % [c[0], Voice.format_action_tag(res)])
		else:
			failed += 1
			print("  [FAIL] %-32s -> expected slot %d subj %d dir %s, got %s" % [c[0], c[1], c[2], c[3], res])
	var spell_chain: Array = Voice.parse_utterance("alpha move up and spell two")
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
	voice.inject("charlie spell three")
	voice.inject("alpha spell one")
	voice.inject("bravo move up then move up")
	voice._evaluate_results()
	if spoken.size() == 3 and spoken[0]["ability"] == Cfg.Ability.FIREBALL \
			and spoken[1]["type"] == T.MOVE_DIR and spoken[2]["type"] == T.MOVE_DIR \
			and not spoken[1]["queue"] and spoken[2]["queue"] \
			and voice.history[0]["tags"] == ["SQUAD FIREBALL"] and voice.history.size() == 3 \
			and voice.history[1]["tags"].is_empty():
		passed += 1
		print("  [PASS] spell slot resolved from loadout and chained duplicate moves emitted")
	else:
		failed += 1
		print("  [FAIL] spell slot resolved from loadout: ", spoken, " / ", voice.history)
	voice.free()

	# Fireball without a direction waits for the final result; with a direction it can fire early.
	var timing_ok: bool = not Voice.is_complete(Voice.parse_voice("fireball")) \
		and Voice.is_complete(Voice.parse_voice("fireball left")) \
		and Voice.is_complete(Voice.parse_voice("scan"))
	if timing_ok:
		passed += 1
		print("  [PASS] interim completeness")
	else:
		failed += 1
		print("  [FAIL] interim completeness")

	print("\nTest results: %d passed, %d failed." % [passed, failed])
	quit(1 if failed > 0 else 0)
