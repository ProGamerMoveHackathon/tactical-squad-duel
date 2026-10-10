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
const SUBJECT_NAMES := {-1: "SQUAD", 0: "ALPHA", 1: "BRAVO", 2: "CHARLIE"}

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
		_handle_result(str(item.get("key", "")), str(item.get("text", "")), bool(item.get("final", false)))


func _handle_result(key: String, text: String, is_final: bool) -> void:
	var lower := text.to_lower()
	var best := lower.split(" | ")[0].strip_edges()
	if best != "":
		last_heard = best
	var fired: Array = _fired.get(key, [])

	for alt in text.split(" | "):
		var cmd := parse_voice(alt)
		if cmd["type"] != CmdType.NONE:
			var cmd_key := "%d:%s:%s" % [cmd["type"], str(cmd.get("subject", "")), str(cmd.get("param", cmd.get("ability", "")))]
			if cmd_key in fired:
				continue
			fired.append(cmd_key)
			_fired[key] = fired
			command_spoken.emit(cmd)
			if cmd["type"] == CmdType.SELECT and cmd.get("subject", -1) >= 0:
				select_spoken.emit(cmd["subject"], best)
			elif cmd["type"] == CmdType.ABILITY:
				ability_spoken.emit(cmd["ability"], best)
			break

	if is_final and _fired.size() > 64:
		_fired.clear()


## Static natural grammar parser for testing and runtime.
static func parse_voice(raw: String) -> Dictionary:
	var cleaned := " "
	var lower := raw.to_lower()
	for c in lower:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			cleaned += c
		else:
			cleaned += " "
	cleaned = " " + " ".join(cleaned.split(" ", false)) + " "

	# 1. Meta match commands
	for w in Cfg.VOICE_ACTIONS["deploy"]:
		if cleaned.find(" " + w + " ") != -1:
			return {"type": CmdType.DEPLOY, "text": raw}
	for w in Cfg.VOICE_ACTIONS["rematch"]:
		if cleaned.find(" " + w + " ") != -1:
			return {"type": CmdType.REMATCH, "text": raw}

	# 2. Extract Subject (Alpha, Bravo, Charlie, Delta, Squad, or default -2)
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

	if not named and not _find(text, "next").is_empty():
		return {"type": CmdType.SELECT_NEXT, "subject": -2}

	hit = _find(text, "abilities")
	if not hit.is_empty():
		text = _cut(text, hit)
		var callout := _find(text, "callouts")
		return {"type": CmdType.ABILITY, "ability": hit[0], "subject": subject,
			"target": callout[0] if not callout.is_empty() else "",
			"dir": _direction(text) if callout.is_empty() else Vector2.ZERO}

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
