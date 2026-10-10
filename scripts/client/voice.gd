extends Node
## Voice commands through the browser's Web Speech API (Chrome / Edge / Safari),
## bridged into Godot with JavaScriptBridge. Recognised phrases are parsed with a
## tactical grammar ([who] [action] [where]) so the game is playable hands-free.
##
## Speech arrives as "results" that grow while the player talks (interim) and
## are eventually finalised. Interim text is acted on once it has been stable
## for INTERIM_STABLE_S, so short orders feel instant; finals always run. Each
## command fires at most once per result.

const Cfg = preload("res://scripts/config.gd")

signal command_spoken(cmd: Dictionary)
signal status_changed(status: String)

enum CmdType {
	NONE,
	SELECT,
	MOVE_DIR,
	WATCH_DIR,
	HALT,
	ABILITY,
	DEPLOY,
	REMATCH,
	SELECT_NEXT,
	STEER,
}

const INTERIM_STABLE_S := 0.4
const HISTORY_SIZE := 4
const HISTORY_TTL := 9.0
const SUBJECT_NAMES := {-1: "SQUAD", 0: "ALPHA", 1: "BRAVO", 2: "CHARLIE", 3: "DELTA"}

const JS_SETUP := """
(function () {
  if (window.tsdVoice) return;
  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  var TAB_ID = Math.random().toString(36).substring(2, 9);
  var v = window.tsdVoice = {
    supported: !!SR,
    active: false,
    speaking: false,
    queue: [],
    status: SR ? 'off' : 'unsupported',
    session: 0
  };
  var rec = null, want = false, restartTimer = null, abortCount = 0;
  var FATAL = { 'not-allowed': 'mic blocked', 'service-not-allowed': 'mic blocked',
                'audio-capture': 'no microphone', 'network': 'speech service offline' };

  function tryClaimMic() {
    try {
      var holder = localStorage.getItem('tsd_mic_holder');
      var ts = parseInt(localStorage.getItem('tsd_mic_ts') || '0', 10);
      var now = Date.now();
      if (!holder || holder === TAB_ID || (now - ts) > 4000) {
        localStorage.setItem('tsd_mic_holder', TAB_ID);
        localStorage.setItem('tsd_mic_ts', String(now));
        return true;
      }
      return false;
    } catch (e) { return true; }
  }

  function releaseMic() {
    try {
      if (localStorage.getItem('tsd_mic_holder') === TAB_ID) {
        localStorage.removeItem('tsd_mic_holder');
      }
    } catch (e) {}
  }

  setInterval(function () {
    if (v.active) {
      try { localStorage.setItem('tsd_mic_ts', String(Date.now())); } catch (e) {}
    }
  }, 1500);

  function stopRec() {
    if (!rec) return;
    try {
      rec.onstart = rec.onerror = rec.onend = rec.onresult = null;
      rec.onspeechstart = rec.onspeechend = null;
      rec.abort();
    } catch (e) {}
    rec = null;
  }

  function scheduleRestart(ms) {
    if (restartTimer) clearTimeout(restartTimer);
    restartTimer = setTimeout(function () {
      if (want && !v.active && !document.hidden) createAndStart();
    }, ms);
  }

  function createAndStart() {
    if (!SR || !want || document.hidden) return;
    if (!tryClaimMic()) {
      v.status = 'mic in other tab (click Mic to claim)';
      scheduleRestart(2000);
      return;
    }
    stopRec();
    try {
      rec = new SR();
      rec.continuous = true;
      rec.interimResults = true;
      rec.maxAlternatives = 3;
      rec.lang = 'en-US';
      rec.onstart = function () {
        v.active = true;
        abortCount = 0;
        v.session++;
        v.status = 'listening';
        console.log('[TSD Voice] recognition active in tab ' + TAB_ID + ', session ' + v.session);
      };
      rec.onspeechstart = function () {
        v.speaking = true;
        console.log('[TSD Voice] audio/speech detected!');
      };
      rec.onspeechend = function () {
        v.speaking = false;
      };
      rec.onerror = function (e) {
        if (e.error === 'no-speech') return;
        if (e.error === 'aborted') {
          abortCount++;
          console.warn('[TSD Voice] aborted by Chrome (attempt ' + abortCount + ')');
          if (abortCount >= 3) {
            want = false;
            v.active = false;
            v.status = 'mic busy (another tab/app has lock)';
            releaseMic();
            return;
          }
          scheduleRestart(1200 * abortCount);
          return;
        }
        console.warn('[TSD Voice] event error:', e.error);
        if (FATAL[e.error]) {
          want = false;
          v.active = false;
          v.status = FATAL[e.error];
          releaseMic();
        } else {
          v.status = 'error: ' + e.error;
        }
      };
      rec.onend = function () {
        v.active = false;
        v.speaking = false;
        if (want && !document.hidden) scheduleRestart(250);
      };
      rec.onresult = function (ev) {
        for (var i = ev.resultIndex; i < ev.results.length; i++) {
          var r = ev.results[i], alts = [];
          for (var j = 0; j < r.length; j++) alts.push(r[j].transcript);
          console.log('[TSD Voice] heard:', alts[0], '(final=' + r.isFinal + ')');
          v.queue.push({ key: v.session + ':' + i, alts: alts, final: r.isFinal });
        }
      };
      rec.start();
    } catch (e) {
      if (want) scheduleRestart(1000);
    }
  }

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) {
      if (v.active) {
        console.log('[TSD Voice] tab hidden; releasing microphone');
        stopRec();
        releaseMic();
        v.status = 'paused (background tab)';
      }
    } else {
      if (want) {
        console.log('[TSD Voice] tab focused; reclaiming microphone');
        scheduleRestart(250);
      }
    }
  });

  v.start = function (forceClaim) {
    if (!SR) return;
    want = true;
    abortCount = 0;
    if (forceClaim) {
      try {
        localStorage.setItem('tsd_mic_holder', TAB_ID);
        localStorage.setItem('tsd_mic_ts', String(Date.now()));
      } catch (e) {}
    }
    v.status = 'listening';
    createAndStart();
  };

  v.stop = function () {
    want = false;
    v.active = false;
    v.speaking = false;
    v.status = 'off';
    releaseMic();
    if (restartTimer) clearTimeout(restartTimer);
    stopRec();
  };

  v.poll = function () {
    var q = v.queue; v.queue = [];
    return JSON.stringify({ q: q, status: v.status, speaking: v.speaking });
  };
})();
"""

var available := false
var enabled := false
var speaking := false
var status := "unavailable"
## Words currently being spoken (not final yet).
var interim_text := ""
## Recent utterances, oldest first: {key, text, tags: Array[String], age}.
## An entry without tags was heard but not understood.
var history := []
var last_action := ""
## func(subject: int, slot: int) -> ability id or -1. Turns "spell two" into the
## ability equipped in that slot; set by the game, which knows the loadouts.
var spell_resolver := Callable()

var _results := {}  # result key -> {alts, final, changed, done, sigs}
var _clock := 0.0
var _poll_t := 0.0
var _typed := 0


func _ready() -> void:
	available = OS.has_feature("web")
	if not available:
		status = "web only"
		return
	JavaScriptBridge.eval(JS_SETUP, true)
	if not JavaScriptBridge.eval("window.tsdVoice.supported", true):
		available = false
		status = "unsupported browser"
	else:
		status = "off"


func start(force_claim: bool = true) -> void:
	if not available or enabled:
		return
	enabled = true
	JavaScriptBridge.eval("window.tsdVoice.start(%s)" % ("true" if force_claim else "false"), true)
	_set_status("listening")


func stop() -> void:
	if not available or not enabled:
		return
	enabled = false
	speaking = false
	interim_text = ""
	JavaScriptBridge.eval("window.tsdVoice.stop()", true)
	_set_status("off")


func toggle() -> void:
	if enabled:
		stop()
	else:
		start(true)


## Feed text as if it had been spoken (debug hooks / typed commands).
func inject(text: String) -> void:
	_typed += 1
	_on_result("typed:%d" % _typed, [text], true)


func _set_status(s: String) -> void:
	if s != status:
		status = s
		status_changed.emit(status)


func _process(delta: float) -> void:
	_clock += delta
	for h in history:
		h["age"] += delta
	while not history.is_empty() and history[0]["age"] > HISTORY_TTL:
		history.pop_front()
	if available:
		_poll_t -= delta
		if _poll_t <= 0.0:
			_poll_t = 0.05
			_poll()
	_evaluate_results()


func _poll() -> void:
	var raw = JavaScriptBridge.eval("window.tsdVoice.poll()", true)
	if typeof(raw) != TYPE_STRING:
		return
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return
	speaking = bool(data.get("speaking", false))
	var new_status := str(data.get("status", status))
	if new_status != "listening" and new_status != "off":
		enabled = false
	_set_status(new_status)
	for item in data.get("q", []):
		_on_result(str(item.get("key", "")), item.get("alts", []), bool(item.get("final", false)))


func _on_result(key: String, alts: Array, is_final: bool) -> void:
	var clean := PackedStringArray()
	for a in alts:
		var s := str(a).strip_edges()
		if s != "":
			clean.append(s)
	var r: Dictionary = _results.get(key, {"alts": PackedStringArray(), "final": false, "changed": _clock, "done": "", "sigs": []})
	if clean != r["alts"]:
		r["alts"] = clean
		r["changed"] = _clock
	r["final"] = is_final
	_results[key] = r


func _evaluate_results() -> void:
	var live := ""
	var live_t := -1.0
	for key in _results.keys():
		var r: Dictionary = _results[key]
		var text: String = r["alts"][0] if not r["alts"].is_empty() else ""
		var stable: bool = r["final"] or _clock - r["changed"] >= INTERIM_STABLE_S
		var state_id := "%s|%s" % [text, r["final"]]
		if stable and r["done"] != state_id:
			r["done"] = state_id
			_act(key, r)
		if r["final"]:
			if text != "":
				_history_entry(key, text)["age"] = 0.0
			_results.erase(key)
		elif r["changed"] > live_t:
			live = text
			live_t = r["changed"]
	interim_text = live


func _act(key: String, r: Dictionary) -> void:
	var cmds := best_parse(r["alts"])
	for cmd in cmds:
		if cmd.get("type") == CmdType.ABILITY and cmd["ability"] < 0:
			cmd["ability"] = spell_resolver.call(cmd["subject"], cmd["slot"]) if spell_resolver.is_valid() else -1
			if cmd["ability"] < 0:
				continue
		if not r["final"] and not is_complete(cmd):
			continue
		var sig := command_signature(cmd)
		if sig in r["sigs"]:
			continue
		r["sigs"].append(sig)
		last_action = format_action_tag(cmd)
		_history_entry(key, r["alts"][0])["tags"].append(last_action)
		command_spoken.emit(cmd)


func _history_entry(key: String, text: String) -> Dictionary:
	for h in history:
		if h["key"] == key:
			h["text"] = text
			return h
	var entry := {"key": key, "text": text, "tags": [], "age": 0.0}
	history.append(entry)
	while history.size() > HISTORY_SIZE:
		history.pop_front()
	return entry


# --------------------------------------------------------------------------
# Command helpers
# --------------------------------------------------------------------------

## Commands that are safe to run from interim text. A fireball without a direction
## waits for the final result, in case a direction is still coming.
static func is_complete(cmd: Dictionary) -> bool:
	if cmd.get("type") == CmdType.ABILITY and cmd.get("ability") == Cfg.Ability.FIREBALL:
		return cmd.get("dir", Vector2.ZERO) != Vector2.ZERO
	# Turns add up, so "left" must not fire before a possible "... 30" arrives.
	if cmd.get("type") == CmdType.STEER and cmd["turn"] != 0.0:
		return cmd["exact"]
	return true


static func command_signature(cmd: Dictionary) -> String:
	if cmd.get("type") == CmdType.ABILITY:
		return "ability:%d" % cmd["ability"]  # cooldowns are per team: once per utterance
	var step: int = cmd.get("step", 0)
	if cmd.get("type") == CmdType.STEER:
		return "steer:%d:%d:%d:%d:%s:%d" % [cmd["subject"], cmd["move"], cmd["turn"], cmd["tiles"], cmd["dist"], step]
	return "%d:%d:%s:%s:%d" % [cmd.get("type", 0), cmd.get("subject", -2), str(cmd.get("param", "")), str(cmd.get("dist", "")), step]


static func direction_label(dir: Vector2) -> String:
	var parts := []
	if dir.y < -0.1: parts.append("UP")
	if dir.y > 0.1: parts.append("DOWN")
	if dir.x > 0.1: parts.append("RIGHT")
	if dir.x < -0.1: parts.append("LEFT")
	return "-".join(parts)


static func format_action_tag(cmd: Dictionary) -> String:
	var who: String = SUBJECT_NAMES.get(cmd.get("subject", -2), "")
	var pre := who + " " if who != "" else ""
	match cmd.get("type", CmdType.NONE):
		CmdType.SELECT:
			return "SELECT " + who
		CmdType.SELECT_NEXT:
			return "NEXT SOLDIER"
		CmdType.MOVE_DIR:
			var extra: String = {"short": " (BIT)", "far": " (FAR)"}.get(cmd.get("dist", ""), "")
			return pre + "MOVE " + str(cmd["param"]) + extra
		CmdType.WATCH_DIR:
			return pre + "WATCH " + str(cmd["param"])
		CmdType.HALT:
			return pre + "STOP"
		CmdType.ABILITY:
			# Cast by every ready squad member, whoever was named.
			var tag: String = "SQUAD " + (str(Cfg.ABILITIES[cmd["ability"]]["name"]).to_upper() if cmd["ability"] >= 0 \
				else "SPELL " + Cfg.ABILITY_SLOT_KEYS[cmd["slot"]])
			if cmd.get("dir", Vector2.ZERO) != Vector2.ZERO:
				tag += " " + direction_label(cmd["dir"])
			return tag
		CmdType.STEER:
			var parts := []
			if absf(cmd["turn"]) >= 180.0:
				parts.append("TURN AROUND")
			elif cmd["turn"] != 0.0:
				parts.append("%s %d" % ["RIGHT" if cmd["turn"] > 0.0 else "LEFT", absf(cmd["turn"])])
			if cmd["move"] != 0:
				var walk: String = "FORWARD" if cmd["move"] > 0 else "BACK"
				if cmd["tiles"] > 0:
					walk += " %d" % cmd["tiles"]
				elif cmd["dist"] == "short":
					walk += " (BIT)"
				parts.append(walk)
			return pre + " + ".join(parts)
		CmdType.DEPLOY:
			return "DEPLOY"
		CmdType.REMATCH:
			return "REMATCH"
	return ""


# --------------------------------------------------------------------------
# Grammar
# --------------------------------------------------------------------------

static var _vocab := {}


## [[phrase, id], ...] with the longest phrase first.
static func _sorted(map: Dictionary) -> Array:
	var out := []
	for id in map:
		for w in map[id]:
			out.append([str(w), id])
	out.sort_custom(func(a, b): return a[0].length() > b[0].length())
	return out


static func _phrases(name: String) -> Array:
	if _vocab.is_empty():
		var spell_slots := {}
		for k in Cfg.VOICE_SPELL_SLOTS.size():
			var words: Dictionary = Cfg.VOICE_SPELL_SLOTS[k]
			spell_slots[k] = []
			for noun in Cfg.VOICE_SPELL_NOUNS:
				for w in words["number"] + words["ordinal"]:
					spell_slots[k].append(noun + " " + w)
				for w in words["ordinal"]:
					spell_slots[k].append(w + " " + noun)
		_vocab = {
			"spell_slots": _sorted(spell_slots),
			"subjects": _sorted(Cfg.VOICE_SUBJECTS),
			"numbers": _sorted(Cfg.VOICE_SUBJECT_NUMBERS),
			"directions": _sorted(Cfg.VOICE_DIRECTIONS),
			"abilities": _sorted(Cfg.VOICE_PHRASES),
		}
		for key in Cfg.VOICE_ACTIONS:
			_vocab[key] = _sorted({key: Cfg.VOICE_ACTIONS[key]})
		for key in Cfg.VOICE_STEER:
			_vocab["steer_" + key] = _sorted({key: Cfg.VOICE_STEER[key]})
		var compass := {}
		for id in Cfg.VOICE_DIRECTIONS:
			compass[id] = Cfg.VOICE_DIRECTIONS[id].filter(func(w): return not w in Cfg.VOICE_STEER["left"] + Cfg.VOICE_STEER["right"])
		_vocab["compass"] = _sorted(compass)
	return _vocab[name]


## Longest vocabulary phrase found in `text` -> [id, index, phrase], or [].
static func _find(text: String, vocab_name: String) -> Array:
	for entry in _phrases(vocab_name):
		var idx := text.find(" " + entry[0] + " ")
		if idx != -1:
			return [entry[1], idx, entry[0]]
	return []


static func _cut(text: String, hit: Array) -> String:
	return text.substr(0, hit[1]) + text.substr(hit[1] + hit[2].length() + 1)


## Lower-case, letters/digits only, padded with spaces.
static func normalize(raw: String) -> String:
	var out := ""
	for c in raw.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else " "
	var words := out.split(" ", false)
	for i in words.size():
		if words[i] == "too":
			words[i] = "two"
	var text := " " + " ".join(words) + " "
	return text.replace(" all right ", " alright ")


## Sum of all direction words in `text`, snapped to the 8 compass directions.
static func _direction(text: String) -> Vector2:
	var v := Vector2.ZERO
	var hit := _find(text, "directions")
	while not hit.is_empty():
		v += Cfg.VOICE_DIRECTION_VECTORS[hit[0]]
		text = _cut(text, hit)
		hit = _find(text, "directions")
	return Vector2(signf(v.x), signf(v.y)).normalized()


static func _split_segments(text: String) -> Array:
	var single_dirs := []
	for id in Cfg.VOICE_DIRECTIONS:
		single_dirs.append_array(Cfg.VOICE_DIRECTIONS[id])
	var words := text.split(" ", false)
	var segs := []
	var cur := []
	for i in words.size():
		var w := words[i]
		# "up and left" is one diagonal, not two orders.
		var joins_dirs := w == "and" and i > 0 and i + 1 < words.size() \
			and words[i - 1] in single_dirs and words[i + 1] in single_dirs
		if w in ["and", "then", "also"] and not joins_dirs:
			if not cur.is_empty():
				segs.append(" " + " ".join(cur) + " ")
			cur = []
		elif not joins_dirs:
			cur.append(w)
	if not cur.is_empty():
		segs.append(" " + " ".join(cur) + " ")
	return segs


## Parses a whole utterance into a list of commands. Orders can be chained with
## "and" / "then"; a later order without a name reuses the previous soldier.
static func parse_utterance(raw: String) -> Array:
	var text := normalize(raw)
	if text.strip_edges() == "":
		return []
	if not _find(text, "rematch").is_empty():
		return [{"type": CmdType.REMATCH, "text": raw}]
	if not _find(text, "deploy").is_empty():
		return [{"type": CmdType.DEPLOY, "text": raw}]
	var out := []
	var subject := -2
	var moved := []
	var steered := []
	for seg in _split_segments(text):
		var cmd := _parse_segment(seg, subject)
		if cmd["type"] == CmdType.NONE:
			continue
		subject = cmd.get("subject", subject)
		cmd["text"] = raw
		# The second move for the same soldier starts where the first ends.
		if cmd["type"] == CmdType.MOVE_DIR:
			cmd["step"] = moved.count(subject)
			cmd["queue"] = cmd["step"] > 0
			moved.append(subject)
		elif cmd["type"] == CmdType.STEER:
			cmd["step"] = steered.count(subject)
			steered.append(subject)
		out.append(cmd)
	return out


## First command of an utterance (or NONE). Kept for tests and simple callers.
static func parse_voice(raw: String) -> Dictionary:
	var cmds := parse_utterance(raw)
	return cmds[0] if not cmds.is_empty() else {"type": CmdType.NONE, "text": raw}


static func best_parse(alts) -> Array:
	for a in alts:
		var cmds := parse_utterance(a)
		if not cmds.is_empty():
			return cmds
	return []


static func _parse_segment(text: String, inherited: int) -> Dictionary:
	var subject := inherited
	var named := false

	# Before the soldier numbers: "first spell" must not select Alpha.
	var spell_slot := -1
	if _find(text, "abilities").is_empty():
		var spell := _find(text, "spell_slots")
		if not spell.is_empty():
			spell_slot = spell[0]
			text = _cut(text, spell)

	# A number names a soldier only at the start ("two go left", "select three").
	var words := text.split(" ", false)
	var lead := 0
	while lead < words.size() and words[lead] in ["select", "switch", "to", "unit", "soldier", "number"]:
		lead += 1
	if lead < words.size():
		for entry in _phrases("numbers"):
			if words[lead] == entry[0]:
				subject = entry[1]
				named = true
				words.remove_at(lead)
				text = " " + " ".join(words) + " "
				break

	# Distance words first: "all the way" must not read as "all" (= squad).
	var dist := ""
	var hit := _find(text, "far")
	if not hit.is_empty():
		dist = "far"
		text = _cut(text, hit)
	hit = _find(text, "short")
	if not hit.is_empty():
		dist = "short"
		text = _cut(text, hit)

	if not named:
		hit = _find(text, "subjects")
		if not hit.is_empty():
			subject = hit[0]
			named = true
			text = _cut(text, hit)

	if not _find(text, "halt").is_empty():
		return {"type": CmdType.HALT, "subject": subject}

	hit = _find(text, "abilities")
	if not hit.is_empty() or spell_slot >= 0:
		if not hit.is_empty():
			text = _cut(text, hit)
		# A spell slot ("ability": -1) is resolved against the loadout by the Voice node.
		return {"type": CmdType.ABILITY, "ability": hit[0] if not hit.is_empty() else -1,
			"slot": spell_slot, "subject": subject,
			"dir": _direction(text)}

	if not named and not _find(text, "next").is_empty():
		return {"type": CmdType.SELECT_NEXT, "subject": -2}

	# "about face" is a turn, not a watch order.
	if not _find(text, "steer_around").is_empty():
		return _parse_steer(text, subject, dist)

	hit = _find(text, "watch")
	if not hit.is_empty():
		var rest := _cut(text, hit)
		var wdir := _direction(rest)
		if wdir != Vector2.ZERO:
			return {"type": CmdType.WATCH_DIR, "subject": subject, "param": direction_label(wdir), "dir": wdir}
		return {"type": CmdType.NONE}

	# Without a compass word, forward / back / left / right steer the soldier.
	if _find(text, "compass").is_empty():
		var steer := _parse_steer(text, subject, dist)
		if steer["type"] != CmdType.NONE:
			return steer

	var dir := _direction(text)
	if dir != Vector2.ZERO:
		return {"type": CmdType.MOVE_DIR, "subject": subject, "param": direction_label(dir), "dir": dir, "dist": dist}

	if named and subject >= 0:
		return {"type": CmdType.SELECT, "subject": subject}
	return {"type": CmdType.NONE}


## Soldier-relative driving: "forward", "back 5", "left 30", "go right", "turn around".
## turn is in degrees (positive = right / clockwise on screen); tiles 0 = until a wall.
static func _parse_steer(text: String, subject: int, dist: String) -> Dictionary:
	var turn := 0.0
	var move := 0
	var hit := _find(text, "steer_around")
	if not hit.is_empty():
		turn = 180.0
		text = _cut(text, hit)
	for side in [["left", -1.0], ["right", 1.0]]:
		hit = _find(text, "steer_" + side[0])
		if not hit.is_empty():
			turn = side[1] * Cfg.VOICE_TURN_DEFAULT
			text = _cut(text, hit)
	if not _find(text, "steer_backward").is_empty():
		move = -1
	elif not _find(text, "steer_forward").is_empty():
		move = 1
	var go := not _find(text, "steer_go").is_empty()
	if move == 0 and go and ((turn != 0.0 and turn != 180.0) or _number(text) > 0 or dist != ""):
		move = 1
	if turn == 0.0 and move == 0:
		return {"type": CmdType.NONE}
	var n := _number(text)
	var exact := turn == 180.0
	var tiles := 0
	if turn != 0.0 and not exact:
		if n > 0:
			turn = signf(turn) * minf(n, 360.0)
			exact = true
		elif dist == "short" and move == 0:
			turn = signf(turn) * Cfg.VOICE_TURN_SHORT
			dist = ""
	elif n > 0:
		tiles = n
	return {"type": CmdType.STEER, "subject": subject, "move": move, "turn": turn, "exact": exact,
		"tiles": tiles, "dist": dist}


## First number in `text` ("30", "forty five", "a hundred"), or -1.
static func _number(text: String) -> int:
	var total := -1
	for w in text.split(" ", false):
		if w.is_valid_int():
			return int(w) if total < 0 else total + int(w)
		if Cfg.VOICE_NUMBER_WORDS.has(w):
			var v: int = Cfg.VOICE_NUMBER_WORDS[w]
			total = maxi(total, 1) * 100 if v == 100 else maxi(total, 0) + v
		elif total >= 0:
			break
	return total
