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
		["alpha move to mid", Voice.CmdType.MOVE_CALLOUT, 0, "mid"],
		["bravo go to north", Voice.CmdType.MOVE_CALLOUT, 1, "north"],
		["charlie advance to choke", Voice.CmdType.MOVE_CALLOUT, 2, "choke"],
		["delta move to south", Voice.CmdType.MOVE_CALLOUT, 3, "south"],
		["mid", Voice.CmdType.MOVE_CALLOUT, -2, "mid"],
		["north", Voice.CmdType.MOVE_CALLOUT, -2, "north"],
		["watch north", Voice.CmdType.WATCH_DIR, -2, "north"],
		["bravo watch south", Voice.CmdType.WATCH_DIR, 1, "south"],
		["charlie face east", Voice.CmdType.WATCH_DIR, 2, "east"],
		["stop", Voice.CmdType.HALT, -2, null],
		["alpha halt", Voice.CmdType.HALT, 0, null],
		["squad hold", Voice.CmdType.HALT, -1, null],
		["smoke", Voice.CmdType.ABILITY, -2, Cfg.Ability.SMOKE],
		["smoke mid", Voice.CmdType.ABILITY, -2, Cfg.Ability.SMOKE],
		["scan", Voice.CmdType.ABILITY, -2, Cfg.Ability.SCAN],
		["suppress", Voice.CmdType.ABILITY, -2, Cfg.Ability.SUPPRESS],
		["squad rush", Voice.CmdType.ABILITY, -1, Cfg.Ability.RUSH],
		["advance", Voice.CmdType.MOVE_DIR, -2, "east"],
		["push forward", Voice.CmdType.MOVE_DIR, -2, "east"],
		["fall back", Voice.CmdType.MOVE_DIR, -2, "west"],
		["step back", Voice.CmdType.MOVE_DIR, -2, "west"],
		["move south", Voice.CmdType.MOVE_CALLOUT, -2, "south"],
		["alpha", Voice.CmdType.SELECT, 0, null],
		["bravo", Voice.CmdType.SELECT, 1, null],
		["deploy", Voice.CmdType.DEPLOY, -2, null],
		["rematch", Voice.CmdType.REMATCH, -2, null],
		["rifle go to base", Voice.CmdType.MOVE_CALLOUT, 0, "base"],
		["alpha move to buffet", Voice.CmdType.MOVE_CALLOUT, 0, "mid"],
		["bravo go to kitchen", Voice.CmdType.MOVE_CALLOUT, 1, "north"],
		["charlie to tables", Voice.CmdType.MOVE_CALLOUT, 2, "south"],
		["advance to kasse", Voice.CmdType.MOVE_CALLOUT, -2, "flank"],
		["smoke buffet", Voice.CmdType.ABILITY, -2, Cfg.Ability.SMOKE],
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
	var chain: Array = Voice.parse_utterance("bravo go to kitchen and then watch left and smoke")
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

	# Smoke without a target waits for the final result; with a target it can fire early.
	var timing_ok: bool = not Voice.is_complete(Voice.parse_voice("smoke")) \
		and Voice.is_complete(Voice.parse_voice("smoke kitchen")) \
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
