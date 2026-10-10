extends SceneTree
## Automated unit test suite for the tactical voice grammar parser.
## Run with:
##   godot --headless --path . --script res://tests/test_voice_parser.gd

func _init() -> void:
	var Voice = load("res://scripts/client/voice.gd")
	var Cfg = load("res://scripts/config.gd")

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
		["fog", Voice.CmdType.ABILITY, -2, Cfg.Ability.FOG],
		["cast fog", Voice.CmdType.ABILITY, -2, Cfg.Ability.FOG],
		["scan", Voice.CmdType.ABILITY, -2, Cfg.Ability.SCAN],
		["squad rush", Voice.CmdType.ABILITY, -1, Cfg.Ability.RUSH],
		["outrage", Voice.CmdType.ABILITY, -2, Cfg.Ability.OUTRAGE],
		["flash forward", Voice.CmdType.ABILITY, -2, Cfg.Ability.FLASH],
		["break magic", Voice.CmdType.ABILITY, -2, Cfg.Ability.BREAK_MAGIC],
		["fireball", Voice.CmdType.ABILITY, -2, Cfg.Ability.FIREBALL],
		["invisible", Voice.CmdType.ABILITY, -2, Cfg.Ability.INVISIBLE],
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
		["fog buffet", Voice.CmdType.ABILITY, -2, Cfg.Ability.FOG],
	]

	var passed := 0
	var failed := 0
	for c in cases:
		var raw: String = c[0]
		var exp_t: int = c[1]
		var exp_s: int = c[2]
		var exp_p = c[3]

		var res: Dictionary = Voice.parse_voice(raw)
		var actual_t: int = res.get("type", Voice.CmdType.NONE)
		var actual_s: int = res.get("subject", -2)
		var actual_p = res.get("param", res.get("ability", null))

		var ok := (actual_t == exp_t and actual_s == exp_s)
		if exp_p != null:
			ok = ok and (actual_p == exp_p)

		if ok:
			passed += 1
			print("  [PASS] %-28s -> type=%d subj=%d param=%s" % [raw, actual_t, actual_s, str(actual_p)])
		else:
			failed += 1
			print("  [FAIL] %-28s -> expected(type=%d, subj=%d, p=%s) got(type=%d, subj=%d, p=%s)" % [
				raw, exp_t, exp_s, str(exp_p), actual_t, actual_s, str(actual_p)
			])

	print("\nTest results: %d passed, %d failed." % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)
