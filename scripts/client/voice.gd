extends Node
## Voice commands through the browser's Web Speech API (Chrome / Edge / Safari),
## bridged into Godot with JavaScriptBridge. Recognised phrases are turned into
## ability / selection commands. Every command also has a keyboard shortcut, so
## the game is fully playable without a microphone.

const Cfg = preload("res://scripts/config.gd")

signal ability_spoken(ability: int, heard: String)
signal select_spoken(idx: int, heard: String)
signal status_changed(status: String)

const SELECT_PHRASES := {
	0: ["alpha", "alfa"],
	1: ["bravo"],
	2: ["charlie"],
}

const JS_SETUP := """
(function () {
  if (window.tsdVoice) return;
  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  var v = window.tsdVoice = { supported: !!SR, active: false, queue: [], status: SR ? 'off' : 'unsupported', session: 0 };
  var rec = null, want = false;
  function make() {
    rec = new SR();
    rec.continuous = true;
    rec.interimResults = true;
    rec.maxAlternatives = 3;
    rec.lang = 'en-US';
    rec.onstart = function () { v.active = true; v.session++; v.status = 'listening'; };
    rec.onerror = function (e) {
      v.status = 'error: ' + e.error;
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed' || e.error === 'audio-capture') want = false;
    };
    rec.onend = function () {
      v.active = false;
      if (want) { setTimeout(function () { try { rec.start(); } catch (e) {} }, 200); }
      else if (v.status.indexOf('error') !== 0) { v.status = 'off'; }
    };
    rec.onresult = function (ev) {
      for (var i = ev.resultIndex; i < ev.results.length; i++) {
        var r = ev.results[i], alts = [];
        for (var j = 0; j < r.length; j++) alts.push(r[j].transcript);
        v.queue.push({ key: v.session + ':' + i, text: alts.join(' | '), final: r.isFinal });
      }
    };
  }
  v.start = function () {
    if (!SR) return;
    want = true;
    if (!rec) make();
    v.status = 'starting';
    try { rec.start(); } catch (e) {}
  };
  v.stop = function () { want = false; v.status = 'off'; if (rec) { try { rec.stop(); } catch (e) {} } };
  v.poll = function () {
    var q = v.queue; v.queue = [];
    return JSON.stringify({ q: q, status: v.status, supported: v.supported });
  };
})();
"""

var available := false
var enabled := false
var status := "unavailable"
var last_heard := ""
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


func toggle() -> void:
	if not available:
		status_changed.emit(status)
		return
	enabled = not enabled
	JavaScriptBridge.eval("window.tsdVoice.%s()" % ("start" if enabled else "stop"), true)
	status = "starting..." if enabled else "off (press V)"
	status_changed.emit(status)


func _process(delta: float) -> void:
	if not available:
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = 0.08
	var raw = JavaScriptBridge.eval("window.tsdVoice.poll()", true)
	if typeof(raw) != TYPE_STRING:
		return
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var new_status: String = data.get("status", status)
	if new_status == "listening":
		new_status = "listening"
	elif new_status == "off":
		new_status = "off (press V)"
	if new_status.begins_with("error: not-allowed"):
		enabled = false
		new_status = "mic blocked - allow microphone access"
	if new_status != status:
		status = new_status
		status_changed.emit(status)
	for item in data.get("q", []):
		_handle_result(str(item.get("key", "")), str(item.get("text", "")), bool(item.get("final", false)))


func _handle_result(key: String, text: String, is_final: bool) -> void:
	var lower := text.to_lower()
	# Use only the best alternative for display, all alternatives for matching.
	var best := lower.split(" | ")[0].strip_edges()
	if best != "":
		last_heard = best
	var fired: Array = _fired.get(key, [])
	for ability in Cfg.VOICE_PHRASES:
		var cmd_id := "a%d" % ability
		if cmd_id in fired:
			continue
		if _matches(lower, Cfg.VOICE_PHRASES[ability]):
			fired.append(cmd_id)
			ability_spoken.emit(ability, best)
	for idx in SELECT_PHRASES:
		var cmd_id := "s%d" % idx
		if cmd_id in fired:
			continue
		if _matches(lower, SELECT_PHRASES[idx]):
			fired.append(cmd_id)
			select_spoken.emit(idx, best)
	_fired[key] = fired
	if is_final and _fired.size() > 64:
		_fired.clear()


static func _matches(text: String, phrases: Array) -> bool:
	# Whole-word matching across all alternatives.
	var cleaned := ""
	for c in text:
		cleaned += c if (c >= "a" and c <= "z") or c == "|" else " "
	for alt in cleaned.split("|"):
		var padded := " " + " ".join(alt.split(" ", false)) + " "
		for p in phrases:
			if padded.find(" " + p + " ") != -1:
				return true
	return false
