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
const MapData = preload("res://scripts/map_data.gd")

signal command_spoken(cmd: Dictionary)
signal status_changed(status: String)

enum CmdType {
	NONE,
	SELECT,
	MOVE_CALLOUT,
	MOVE_DIR,
	WATCH_DIR,
	WATCH_CALLOUT,
	HALT,
	ABILITY,
	DEPLOY,
	REMATCH,
	SELECT_NEXT,
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

## Commands that are safe to run from interim text. A fireball without a target
## waits for the final result, because "fireball ... kitchen" is still coming.
static func is_complete(cmd: Dictionary) -> bool:
	if cmd.get("type") == CmdType.ABILITY and cmd.get("ability") == Cfg.Ability.FIREBALL:
		return cmd.get("target", "") != "" or cmd.get("dir", Vector2.ZERO) != Vector2.ZERO
	return true


static func command_signature(cmd: Dictionary) -> String:
	if cmd.get("type") == CmdType.ABILITY:
		return "ability:%d" % cmd["ability"]  # cooldowns are per team: once per utterance
	return "%d:%d:%s:%s" % [cmd.get("type", 0), cmd.get("subject", -2), str(cmd.get("param", "")), str(cmd.get("dist", ""))]


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
		CmdType.MOVE_CALLOUT:
			return pre + "MOVE > " + MapData.callout_label(cmd["param"])
		CmdType.MOVE_DIR:
			var extra: String = {"short": " (BIT)", "far": " (FAR)"}.get(cmd.get("dist", ""), "")
			return pre + "MOVE " + str(cmd["param"]) + extra
		CmdType.WATCH_DIR:
			return pre + "WATCH " + str(cmd["param"])
		CmdType.WATCH_CALLOUT:
			return pre + "WATCH " + MapData.callout_label(cmd["param"])
		CmdType.HALT:
			return pre + "STOP"
		CmdType.ABILITY:
			var tag: String = pre + str(Cfg.ABILITIES[cmd["ability"]]["name"]).to_upper()
			if cmd.get("target", "") != "":
				tag += " > " + MapData.callout_label(cmd["target"])
			elif cmd.get("dir", Vector2.ZERO) != Vector2.ZERO:
				tag += " " + direction_label(cmd["dir"])
			return tag
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
		var callouts := {}
		for id in Cfg.CALLOUTS:
			var words: Array = Cfg.CALLOUTS[id]["words"]
			callouts[id] = words
			if Cfg.CALLOUTS[id]["mirror"]:
				var twin := []
				for p in Cfg.VOICE_ENEMY_PREFIXES:
					for w in words:
						twin.append(p + " " + w)
				callouts["enemy_" + id] = twin
		callouts["enemy_base"] = callouts["enemy_base"] + Cfg.VOICE_ENEMY_BASE_WORDS
		_vocab = {
			"subjects": _sorted(Cfg.VOICE_SUBJECTS),
			"numbers": _sorted(Cfg.VOICE_SUBJECT_NUMBERS),
			"callouts": _sorted(callouts),
			"directions": _sorted(Cfg.VOICE_DIRECTIONS),
			"abilities": _sorted(Cfg.VOICE_PHRASES),
		}
		for key in Cfg.VOICE_ACTIONS:
			_vocab[key] = _sorted({key: Cfg.VOICE_ACTIONS[key]})
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


## Lower-case, letters/digits only, padded with spaces: " alpha go to kitchen ".
static func normalize(raw: String) -> String:
	var out := ""
	for c in raw.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else " "
	var words := out.split(" ", false)
	for i in range(1, words.size()):
		if words[i] in ["two", "2", "too"] and not words[i - 1] in ["select", "to", "unit", "soldier", "number"]:
			words[i] = "to"
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
	for seg in _split_segments(text):
		var cmd := _parse_segment(seg, subject)
		if cmd["type"] == CmdType.NONE:
			continue
		subject = cmd.get("subject", subject)
		cmd["text"] = raw
		# "go to base then go up": the second move starts where the first ends.
		if cmd["type"] == CmdType.MOVE_CALLOUT or cmd["type"] == CmdType.MOVE_DIR:
			cmd["queue"] = subject in moved
			moved.append(subject)
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
	if not hit.is_empty():
		text = _cut(text, hit)
		var callout := _find(text, "callouts")
		return {"type": CmdType.ABILITY, "ability": hit[0], "subject": subject,
			"target": callout[0] if not callout.is_empty() else "",
			"dir": _direction(text) if callout.is_empty() else Vector2.ZERO}

	if not named and not _find(text, "next").is_empty():
		return {"type": CmdType.SELECT_NEXT, "subject": -2}

	hit = _find(text, "watch")
	if not hit.is_empty():
		var rest := _cut(text, hit)
		var callout := _find(rest, "callouts")
		if not callout.is_empty():
			return {"type": CmdType.WATCH_CALLOUT, "subject": subject, "param": callout[0]}
		var wdir := _direction(rest)
		if wdir != Vector2.ZERO:
			return {"type": CmdType.WATCH_DIR, "subject": subject, "param": direction_label(wdir), "dir": wdir}

	hit = _find(text, "callouts")
	if not hit.is_empty():
		return {"type": CmdType.MOVE_CALLOUT, "subject": subject, "param": hit[0]}

	var dir := _direction(text)
	if dir != Vector2.ZERO:
		return {"type": CmdType.MOVE_DIR, "subject": subject, "param": direction_label(dir), "dir": dir, "dist": dist}

	if named and subject >= 0:
		return {"type": CmdType.SELECT, "subject": subject}
	return {"type": CmdType.NONE}
