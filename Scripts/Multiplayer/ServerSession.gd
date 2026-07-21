# ServerSession.gd
# The online backend for OUR OWN authoritative server (Tools/GameServer) --
# GDSyncSession's drop-in sibling with the same surface (match_ready /
# match_failed / turn_revealed / opponent_left + quick/host/join/submit_local),
# so LobbyPage swaps backends without relearning anything. Differences from the
# relay era, both server-authoritative by design:
#   * ROOM CODES come FROM the server (`hosted` signal), never made up locally.
#   * THE MAP arrives as layout rows in `matched` (MatchConfig.map_rows) -- the
#     server generates it and both clients load it verbatim; rotations then
#     derive deterministically from the same base on all three machines.
#   * THE CLASH sub-round exists online: `stance_needed` fires when the server
#     detects a contested-tile collision; GameController shows the overlay and
#     answers via send_stance().
# Where the server lives: ws://127.0.0.1:8765 by default (run_server.bat on this
# PC). To point at a friend's PC or a rented box, create user://server.cfg with
#   [server]
#   url="ws://THEIR-ADDRESS:8765"
# Lives at /root/ServerSession so it survives the scene change into the match.
class_name ServerSession
extends Node

signal match_ready(config: MatchConfig)   # handshake done; both sides hold a config
signal match_failed(reason: String)       # lobby/connection error before the match starts
signal hosted(code: String)               # the server assigned our private room code
signal turn_revealed(bundle: Dictionary)  # both submitted -> released together
signal opponent_left()                    # the other player dropped mid-match
signal stance_needed(turn: int)           # contested-tile clash: pick push/pull/feint

const DEFAULT_URL := "ws://127.0.0.1:8765"

var _ws := WebSocketPeer.new()
var _connected := false
var _in_match := false
var _local_is_a := true
var _intent := ""                 # "quick" | "host" | "join" -- sent once welcome arrives
var _join_code := ""
var _loadout: Array = []

static func server_url() -> String:
	var cf := ConfigFile.new()
	if cf.load("user://server.cfg") == OK:
		return String(cf.get_value("server", "url", _platform_default()))
	return _platform_default()

# ROUND 17 (web era): on the website build, default to the SAME machine that
# served the page -- our game server serves both, so browser players never type
# an address (the lobby box still overrides via user://server.cfg). ws:// from
# http pages, wss:// from https pages (browsers forbid mixing them).
static func _platform_default() -> String:
	if OS.has_feature("web"):
		var origin := String(JavaScriptBridge.eval(
			"(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host", true))
		if origin.begins_with("ws") and not origin.ends_with("://"):
			return origin
	return DEFAULT_URL

func _ready() -> void:
	var err := _ws.connect_to_url(server_url())
	if err != OK:
		match_failed.emit("Could not reach the server at %s" % server_url())

# ── lobby intents (same names GDSyncSession exposes) ─────────────────────────
func quick_match(my_loadout: Array) -> void:
	_loadout = my_loadout.duplicate()
	_intent = "quick"
	_send_intent_if_ready()

# The `_code` argument exists only for surface compatibility: OUR server assigns
# codes itself and answers with `hosted(code)` -- nothing local is trusted.
func host_code(_code: String, my_loadout: Array) -> void:
	_loadout = my_loadout.duplicate()
	_intent = "host"
	_send_intent_if_ready()

func join_code(code: String, my_loadout: Array) -> void:
	_loadout = my_loadout.duplicate()
	_intent = "join"
	_join_code = code
	_send_intent_if_ready()

var _welcomed := false
func _send_intent_if_ready() -> void:
	if not _welcomed or _intent == "":
		return
	# hello rides with the intent so the server always has our gear before matching.
	_send({"t": "hello", "name": "player", "gear": _loadout, "version": "1"})
	match _intent:
		"quick": _send({"t": "quick"})
		"host": _send({"t": "host"})
		"join": _send({"t": "join", "code": _join_code})
	_intent = ""

# ── the match wire (MatchTransport calls these through ServerTransport) ─────
func submit_local(turn: int, seq: Array) -> void:
	_send({"t": "plan", "turn": turn, "seq": _seq_out(seq)})

func send_stance(stance: String) -> void:
	_send({"t": "stance", "stance": stance})

# ── socket pump ─────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
			while _ws.get_available_packet_count() > 0:
				_recv(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			set_process(false)
			if _in_match:
				opponent_left.emit()
			elif not _connected:
				match_failed.emit("No server at %s -- is run_server.bat running?" % server_url())
			else:
				match_failed.emit("Connection to the server was lost.")

func _send(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))

func _recv(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if msg == null or not (msg is Dictionary):
		return
	match String(msg.get("t", "")):
		"welcome":
			_welcomed = true
			_send_intent_if_ready()
		"hosted":
			hosted.emit(String(msg.get("code", "")))
		"queued":
			pass   # quick match: waiting for the next real player
		"err":
			match_failed.emit(String(msg.get("msg", "server error")))
		"matched":
			_in_match = true
			_local_is_a = String(msg.get("seat", "A")) == "A"
			var cfg := MatchConfig.make(0, "1",
				Array(msg.get("gear_a", [])), Array(msg.get("gear_b", [])), _local_is_a)
			cfg.map_rows = Array(msg.get("rows", []))
			match_ready.emit(cfg)
		"clash":
			stance_needed.emit(int(msg.get("turn", 0)))
		"reveal":
			var opp: Array = Array(msg.get("seq_b" if _local_is_a else "seq_a", []))
			turn_revealed.emit({"turn": int(msg.get("turn", 0)), "opponent_seq": _seq_in(opp)})
		"foe_left":
			opponent_left.emit()
		"over":
			pass   # both clients resolve the final turn themselves (deterministic)

# ── act (de)serialization: wire JSON <-> the game's plan dicts ──────────────
func _seq_out(seq: Array) -> Array:
	var out: Array = []
	for a in seq:
		var d: Dictionary = a
		var o := {"id": String(d.get("id", "wait"))}
		if d.has("tile"):
			var t: Vector2i = d["tile"]
			o["tile"] = [t.x, t.y]
		if d.has("facing"):
			o["facing"] = int(d["facing"])
		if d.has("stance"):
			o["stance"] = String(d["stance"])
		out.append(o)
	return out

func _seq_in(seq: Array) -> Array:
	var out: Array = []
	for a in seq:
		if not (a is Dictionary):
			continue
		var d: Dictionary = a
		var o := {"id": String(d.get("id", "wait"))}
		if d.has("tile") and d["tile"] is Array and (d["tile"] as Array).size() == 2:
			var t: Array = d["tile"]
			o["tile"] = Vector2i(int(t[0]), int(t[1]))
		if d.has("facing"):
			o["facing"] = int(d["facing"])
		if d.has("stance"):
			o["stance"] = String(d["stance"])
		out.append(o)
	return out
