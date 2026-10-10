extends Node
## Voice commands through the browser's Web Speech API (Chrome / Edge / Safari),
## bridged into Godot with JavaScriptBridge. Recognised phrases are parsed using
## a tactical squad grammar ([Who] [Action] [Where/Target]) allowing 100% hands-free
## gameplay.

const Cfg = preload("res://scripts/config.gd")

signal command_spoken(cmd: Dictionary)
signal ability_spoken(ability: int, heard: String)
signal select_spoken(idx: int, heard: String)
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
	REMATCH
}

const JS_SETUP := """
(function () {
  if (window.tsdVoice) return;
  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  var v = window.tsdVoice = {
    supported: !!SR,
    active: false,
    queue: [],
    status: SR ? 'off (press V)' : 'unsupported',
    session: 0,
    interim: '',
    lastHeard: ''
  };
  var rec = null, want = false, restartTimer = null;

  function stopRec() {
    if (rec) {
      try {
        rec.onstart = null;
        rec.onerror = null;
        rec.onend = null;
        rec.onresult = null;
        rec.abort();
      } catch (e) {}
      rec = null;
    }
  }

  function createAndStart() {
    if (!SR || !want) return;
    stopRec();
    try {
      rec = new SR();
      rec.continuous = true;
      rec.interimResults = true;
      rec.maxAlternatives = 3;
      rec.lang = 'en-US';

      rec.onstart = function () {
        v.active = true;
        v.session++;
        v.status = 'listening';
      };

      rec.onerror = function (e) {
        if (e.error === 'no-speech' || e.error === 'aborted') {
          return;
        }
        if (e.error === 'not-allowed') {
          want = false;
          v.active = false;
          v.status = 'mic blocked (allow in browser)';
        } else if (e.error === 'audio-capture') {
          want = false;
          v.active = false;
          v.status = 'no microphone found';
        } else if (e.error === 'network') {
          want = false;
          v.active = false;
          v.status = 'offline / speech service error';
        } else {
          v.status = 'error: ' + e.error;
        }
      };

      rec.onend = function () {
        v.active = false;
        if (want) {
          // Chrome pauses on silence; immediately restart with fresh SR instance!
          if (restartTimer) clearTimeout(restartTimer);
          restartTimer = setTimeout(function () {
            if (want && !v.active) {
              createAndStart();
            }
          }, 200);
        } else {
          if (!v.status.startsWith('error') && !v.status.startsWith('mic blocked') && !v.status.startsWith('no microphone')) {
            v.status = 'off (press V)';
          }
        }
      };

      rec.onresult = function (ev) {
        for (var i = ev.resultIndex; i < ev.results.length; i++) {
          var r = ev.results[i], alts = [];
          for (var j = 0; j < r.length; j++) alts.push(r[j].transcript);
          var textStr = alts.join(' | ');
          if (r.isFinal) {
            v.lastHeard = alts[0].trim();
            v.interim = '';
          } else {
            v.interim = alts[0].trim();
          }
          v.queue.push({ key: v.session + ':' + i, text: textStr, final: r.isFinal });
        }
      };

      rec.start();
    } catch (e) {
      if (want) {
        if (restartTimer) clearTimeout(restartTimer);
        restartTimer = setTimeout(function () {
          if (want && !v.active) createAndStart();
        }, 500);
      }
    }
  }

  v.start = function () {
    if (!SR) return;
    want = true;
    v.status = 'listening';
    createAndStart();
  };

  v.stop = function () {
    want = false;
    v.active = false;
    v.status = 'off (press V)';
    v.interim = '';
    if (restartTimer) clearTimeout(restartTimer);
    stopRec();
  };

  v.poll = function () {
    var q = v.queue; v.queue = [];
    return JSON.stringify({
      q: q,
      status: v.status,
      supported: v.supported,
      active: v.active,
      interim: v.interim || '',
      lastHeard: v.lastHeard || ''
    });
  };
})();
"""

var available := false
var enabled := false
var status := "unavailable"
var last_heard := ""
var last_heard_timer := 0.0
var last_action := ""
var interim_text := ""
var _fired := {}  # result key -> Array of fired command ids
var _poll_t := 0.0


func _ready() -> void:
	available = OS.has_feature("web")
	if available:
		JavaScriptBridge.eval(JS_SETUP, true)
		var supported = JavaScriptBridge.eval("window.tsdVoice.supported", true)
		if not supported:
			available = false
			status = "not supported by this browser (use keys)"
		else:
			status = "off (press V)"
	else:
		status = "web only (use keys)"


func start() -> void:
	if not available or enabled:
		return
	enabled = true
	JavaScriptBridge.eval("window.tsdVoice.start()", true)
	status = "listening"
	status_changed.emit(status)


func stop() -> void:
	if not available or not enabled:
		return
	enabled = false
	interim_text = ""
	JavaScriptBridge.eval("window.tsdVoice.stop()", true)
	status = "off (press V)"
	status_changed.emit(status)


func toggle() -> void:
	if enabled:
		stop()
	else:
		start()


func _process(delta: float) -> void:
	if last_heard_timer > 0.0:
		last_heard_timer = maxf(0.0, last_heard_timer - delta)

	if not available:
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = 0.06
	var raw = JavaScriptBridge.eval("window.tsdVoice.poll()", true)
	if typeof(raw) != TYPE_STRING:
		return
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var new_status: String = str(data.get("status", status))
	var is_active: bool = bool(data.get("active", false))
	if new_status.begins_with("error") or new_status.begins_with("mic blocked") or new_status.begins_with("no microphone") or new_status.begins_with("offline"):
		enabled = false
	elif is_active or new_status == "listening":
		enabled = true

	var cur_interim: String = str(data.get("interim", "")).strip_edges()
	interim_text = cur_interim

	var cur_last: String = str(data.get("lastHeard", "")).strip_edges()
	if cur_last != "" and cur_last != last_heard:
		last_heard = cur_last
		last_heard_timer = 5.0

	if new_status != status:
		status = new_status
		status_changed.emit(status)
	for item in data.get("q", []):
		_handle_result(str(item.get("key", "")), str(item.get("text", "")), bool(item.get("final", false)))


func _handle_result(key: String, text: String, is_final: bool) -> void:
	var lower := text.to_lower()
	var best := lower.split(" | ")[0].strip_edges()
	if best != "":
		last_heard = best
		last_heard_timer = 5.0
		if is_final:
			interim_text = ""
	var fired: Array = _fired.get(key, [])

	for alt in text.split(" | "):
		var cmd := parse_voice(alt)
		if cmd["type"] != CmdType.NONE:
			var cmd_key := "%d:%s:%s" % [cmd["type"], str(cmd.get("subject", "")), str(cmd.get("param", cmd.get("ability", "")))]
			if cmd_key in fired:
				continue
			fired.append(cmd_key)
			_fired[key] = fired
			last_action = format_action_tag(cmd)
			last_heard_timer = 5.0
			interim_text = ""
			command_spoken.emit(cmd)
			if cmd["type"] == CmdType.SELECT and cmd.get("subject", -1) >= 0:
				select_spoken.emit(cmd["subject"], best)
			elif cmd["type"] == CmdType.ABILITY:
				ability_spoken.emit(cmd["ability"], best)
			break

	if is_final and _fired.size() > 64:
		_fired.clear()


static func format_action_tag(cmd: Dictionary) -> String:
	var subj_str := ""
	var subj: int = cmd.get("subject", -2)
	match subj:
		-1: subj_str = "SQUAD "
		0: subj_str = "ALPHA "
		1: subj_str = "BRAVO "
		2: subj_str = "CHARLIE "
		_: subj_str = ""

	match cmd.get("type", CmdType.NONE):
		CmdType.SELECT:
			return subj_str + "SELECT"
		CmdType.MOVE_CALLOUT:
			return subj_str + "→ " + str(cmd.get("param", "")).to_upper()
		CmdType.MOVE_DIR:
			return subj_str + "STEP " + str(cmd.get("param", "")).to_upper()
		CmdType.WATCH_DIR:
			return subj_str + "WATCH " + str(cmd.get("param", "")).to_upper()
		CmdType.HALT:
			return subj_str + "HALT"
		CmdType.ABILITY:
			var ab: int = cmd.get("ability", 0)
			return Cfg.ABILITIES[ab]["name"].to_upper()
		CmdType.DEPLOY:
			return "DEPLOY"
		CmdType.REMATCH:
			return "REMATCH"
	return "OK"


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

	# 2. Extract Subject (Alpha, Bravo, Charlie, Squad, or default -2)
	var subject := -2
	for s_id in Cfg.VOICE_SUBJECTS:
		for w in Cfg.VOICE_SUBJECTS[s_id]:
			var needle: String = " " + str(w) + " "
			var idx: int = cleaned.find(needle)
			if idx != -1:
				subject = s_id
				cleaned = cleaned.erase(idx, needle.length())
				cleaned = " " + " ".join(cleaned.split(" ", false)) + " "
				break
		if subject != -2:
			break

	# 3. Halt / Stop command
	for w in Cfg.VOICE_ACTIONS["halt"]:
		if cleaned.find(" " + w + " ") != -1:
			return {"type": CmdType.HALT, "subject": subject, "text": raw}

	# 4. Abilities
	for ab_id in Cfg.VOICE_PHRASES:
		for w in Cfg.VOICE_PHRASES[ab_id]:
			if cleaned.find(" " + w + " ") != -1:
				var target_callout := ""
				for c_id in Cfg.VOICE_CALLOUTS:
					for cw in Cfg.VOICE_CALLOUTS[c_id]:
						if cleaned.find(" " + cw + " ") != -1:
							target_callout = c_id
							break
					if target_callout != "":
						break
				return {"type": CmdType.ABILITY, "ability": ab_id, "subject": subject, "target": target_callout, "text": raw}

	# 5. Watch / Aim command
	var is_watch := false
	for w in Cfg.VOICE_ACTIONS["watch"]:
		if cleaned.find(" " + w + " ") != -1:
			is_watch = true
			break
	if is_watch:
		for d_id in Cfg.VOICE_DIRECTIONS:
			for dw in Cfg.VOICE_DIRECTIONS[d_id]:
				if cleaned.find(" " + dw + " ") != -1:
					return {"type": CmdType.WATCH_DIR, "subject": subject, "param": d_id, "text": raw}
		for c_id in Cfg.VOICE_CALLOUTS:
			for cw in Cfg.VOICE_CALLOUTS[c_id]:
				if cleaned.find(" " + cw + " ") != -1:
					return {"type": CmdType.WATCH_CALLOUT, "subject": subject, "param": c_id, "text": raw}

	# 6. Move command to callout or direction
	for c_id in Cfg.VOICE_CALLOUTS:
		for cw in Cfg.VOICE_CALLOUTS[c_id]:
			if cleaned.find(" " + cw + " ") != -1:
				return {"type": CmdType.MOVE_CALLOUT, "subject": subject, "param": c_id, "text": raw}

	for d_id in Cfg.VOICE_DIRECTIONS:
		for dw in Cfg.VOICE_DIRECTIONS[d_id]:
			if cleaned.find(" " + dw + " ") != -1:
				return {"type": CmdType.MOVE_DIR, "subject": subject, "param": d_id, "text": raw}

	if cleaned.find(" advance ") != -1 or cleaned.find(" push forward ") != -1 or cleaned.find(" push ") != -1:
		return {"type": CmdType.MOVE_DIR, "subject": subject, "param": "east", "text": raw}
	if cleaned.find(" fall back ") != -1 or cleaned.find(" retreat ") != -1:
		return {"type": CmdType.MOVE_DIR, "subject": subject, "param": "west", "text": raw}

	# 7. Pure Selection
	if subject >= 0:
		return {"type": CmdType.SELECT, "subject": subject, "text": raw}

	return {"type": CmdType.NONE, "text": raw}
