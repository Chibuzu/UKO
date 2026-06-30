# GDSyncSession.gd
# The online hub built on the GD-Sync plugin (managed global relay + lobbies), the
# drop-in replacement for NetworkSession. GD-Sync solves the two things raw ENet
# couldn't for worldwide play: its relay removes all NAT/firewall/port-forwarding
# pain (clients only make OUTBOUND connections), and its lobbies provide matchmaking.
#
# Everything ABOVE the wire is reused unchanged: this runs our MatchMediator on the
# GD-Sync host, ships the two sequences over GD-Sync remote calls, and produces the
# same MatchConfig + turn_revealed/opponent_left that NetworkOpponent already expects.
#
# Side mapping: the GD-Sync host == side A, the joiner == side B (so MatchConfig
# local_is_a == GDSync.is_host()). In a 2-player lobby, GDSync.call_func() runs on
# "all other clients" -- i.e. exactly the opponent -- so the submit/reveal exchange
# needs no peer IDs.
#
# This node lives at /root/GDSyncSession with a FIXED name on every client: GD-Sync
# routes remote calls by node path, and the node survives the scene change into the
# match (same requirement the ENet path had).
class_name GDSyncSession
extends Node

signal match_ready(config: MatchConfig)   # handshake done; both sides hold a config
signal match_failed(reason: String)       # lobby/connection error before the match starts
signal turn_revealed(bundle: Dictionary)  # both submitted -> released together
signal opponent_left()                    # the other player dropped mid-match

const CONTENT_VERSION := "0.1"            # must match across both builds
const SEAT_LIMIT := 2                     # 1v1

enum Intent { NONE, QUICK, HOST_CODE, JOIN_CODE }

var _intent: int = Intent.NONE
var _code := ""
var _my_loadout: Array = []
var _mediator: MatchMediator              # host only
var _am_host := false                     # cached at match start (host == side A)
var _in_match := false                    # match_ready emitted -> drops become opponent_left
var _lobby_busy := false                  # guard against double create/join from re-fired signals
var _connected_ok := false                # relay connection established
var _joined_ok := false                   # entered a lobby

func _ready() -> void:
	if get_node_or_null("/root/GDSync") == null:
		push_error("GD-Sync autoload missing. Enable the plugin (Project Settings > Plugins) and check the GDSync autoload path in the Globals tab.")
		return
	GDSync.connected.connect(_on_connected)
	GDSync.connection_failed.connect(func(_e): match_failed.emit("Could not reach the server."))
	GDSync.disconnected.connect(_on_disconnected)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_creation_failed.connect(_on_lobby_creation_failed)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.lobby_join_failed.connect(_on_lobby_join_failed)
	GDSync.lobbies_received.connect(_on_lobbies_received)
	GDSync.client_joined.connect(_on_client_joined)
	GDSync.client_left.connect(_on_client_left)
	# Remote calls are blocked until exposed.
	GDSync.expose_func(_recv_hello)
	GDSync.expose_func(_recv_start)
	GDSync.expose_func(_recv_submit)
	GDSync.expose_func(_recv_reveal)

# ── public entry points (from the lobby UI) ──────────────────────────────────
func quick_match(my_loadout: Array) -> void:
	_begin(Intent.QUICK, "", my_loadout)

func host_code(code: String, my_loadout: Array) -> void:
	_begin(Intent.HOST_CODE, code, my_loadout)

func join_code(code: String, my_loadout: Array) -> void:
	_begin(Intent.JOIN_CODE, code, my_loadout)

func _begin(intent: int, code: String, my_loadout: Array) -> void:
	_intent = intent
	_code = code
	_my_loadout = my_loadout.duplicate()
	if GDSync.is_active():
		_on_connected()
	else:
		GDSync.start_multiplayer()   # connect to the relay first
	_watchdog()

# Turns a silent hang (no internet, blocked relay, host no longer hosting the code)
# into a clear message that also tells us WHICH stage failed. HOST/QUICK legitimately
# wait for an opponent, so only the connect step and a code-join get a timeout.
func _watchdog() -> void:
	await get_tree().create_timer(10.0).timeout
	if _in_match:
		return
	if not _connected_ok:
		match_failed.emit("Couldn't reach GD-Sync. Check internet, and that the API keys are set in this build.")
	elif _intent == Intent.JOIN_CODE and not _joined_ok:
		match_failed.emit("No response from code %s. Is the host still hosting that code?" % _code)

func _on_connected() -> void:
	if _lobby_busy:
		return                              # already creating/joining -> ignore a re-fired connect
	_lobby_busy = true
	_connected_ok = true
	print("[GDSync] connected as ", GDSync.get_client_id(), "; intent=", _intent)
	match _intent:
		Intent.QUICK:
			GDSync.get_public_lobbies()        # -> _on_lobbies_received
		Intent.HOST_CODE:
			GDSync.lobby_create(_code, "", true, SEAT_LIMIT, {"game": "UKO"})
		Intent.JOIN_CODE:
			GDSync.lobby_join(_code, "")

# ── matchmaking ──────────────────────────────────────────────────────────────
func _on_lobbies_received(lobbies: Array) -> void:
	if _intent != Intent.QUICK:
		return
	for l in lobbies:                          # join the first UKO lobby with a free seat
		var tags: Dictionary = l.get("Tags", {})
		if tags.get("game", "") == "UKO" and int(l.get("PlayerCount", SEAT_LIMIT)) < SEAT_LIMIT:
			GDSync.lobby_join(l.get("Name", ""), "")
			return
	GDSync.lobby_create("uko_%d" % (randi() % 1000000), "", true, SEAT_LIMIT, {"game": "UKO"})

func _on_lobby_created(name: String) -> void:
	print("[GDSync] lobby created: ", name, " -> joining")
	GDSync.lobby_join(name, "")                # must join within 5s of creating

func _on_lobby_creation_failed(name: String, error: int) -> void:
	push_warning("[GDSync] lobby creation failed: %s error=%d" % [name, error])
	match_failed.emit("Could not create a match.")

func _on_lobby_join_failed(name: String, error: int) -> void:
	push_warning("[GDSync] lobby join failed: %s error=%d" % [name, error])
	if _intent == Intent.QUICK:
		# the lobby filled between browse and join -> make our own and wait
		GDSync.lobby_create("uko_%d" % (randi() % 1000000), "", true, SEAT_LIMIT, {"game": "UKO"})
	else:
		match_failed.emit("Could not join that match (wrong code or already full).")

func _on_lobby_joined(_name: String) -> void:
	_joined_ok = true
	print("[GDSync] joined lobby ", _name, " as client ", GDSync.get_client_id(), " host=", GDSync.is_host())
	# Announce ourselves to whoever else is in the lobby. If we're the joiner, this
	# reaches the host and triggers the start; if we're the host (alone), it reaches
	# no one yet and the joiner's own hello will trigger it later.
	GDSync.call_func(_recv_hello, [_my_loadout])

func _on_client_joined(client_id: int) -> void:
	print("[GDSync] client_joined ", client_id, " (me=", GDSync.get_client_id(), ", host=", GDSync.is_host(), ")")

# ── handshake (host orchestrates) ────────────────────────────────────────────
func _recv_hello(data: Array) -> void:
	if not GDSync.is_host() or _in_match:
		return                                 # only the host starts, and only once
	var opp_loadout: Array = data[0]           # GD-Sync delivers params as one array arg
	print("[GDSync] host got hello -> starting match")
	var seed_value := randi()                  # host picks the shared map seed
	_am_host = true
	_mediator = MatchMediator.new()
	_mediator.register("A", _deliver_local)    # host == A
	_mediator.register("B", _deliver_remote)
	GDSync.call_func(_recv_start, [seed_value, _my_loadout, opp_loadout])   # -> the joiner
	_emit_ready(seed_value, _my_loadout, opp_loadout, true)

func _recv_start(data: Array) -> void:
	if _in_match:
		return
	var seed_value: int = data[0]              # GD-Sync delivers params as one array arg
	var loadout_a: Array = data[1]
	var loadout_b: Array = data[2]
	_am_host = false                           # joiner == B
	_emit_ready(seed_value, loadout_a, loadout_b, false)

func _emit_ready(seed_value: int, loadout_a: Array, loadout_b: Array, local_a: bool) -> void:
	_in_match = true
	match_ready.emit(MatchConfig.make(seed_value, CONTENT_VERSION, loadout_a, loadout_b, local_a))

# ── per-turn exchange ────────────────────────────────────────────────────────
# Called by GDSyncTransport once the local player has committed this turn's plan.
func submit_local(turn: int, seq: Array) -> void:
	if _am_host:
		_mediator.submit("A", turn, seq)       # straight into the host's mediator
	else:
		GDSync.call_func(_recv_submit, [turn, seq])   # -> host

func _recv_submit(data: Array) -> void:
	if _mediator != null:                      # runs on the host
		_mediator.submit("B", data[0], data[1])   # data = [turn, seq]

func _deliver_local(turn: int, opp_seq: Array) -> void:    # mediator A-sink (host's own)
	turn_revealed.emit({"turn": turn, "opponent_seq": opp_seq})

func _deliver_remote(turn: int, opp_seq: Array) -> void:   # mediator B-sink -> joiner
	GDSync.call_func(_recv_reveal, [turn, opp_seq])

func _recv_reveal(data: Array) -> void:      # runs on the joiner
	turn_revealed.emit({"turn": data[0], "opponent_seq": data[1]})   # data = [turn, opp_seq]

# ── disconnects ──────────────────────────────────────────────────────────────
func _on_client_left(_client_id: int) -> void:
	if _in_match:
		opponent_left.emit()                   # mid-match -> turn loop ends the match
	else:
		match_failed.emit("The other player left before the match started.")

func _on_disconnected() -> void:
	if _in_match:
		opponent_left.emit()
	else:
		match_failed.emit("Lost connection to the server.")

func leave() -> void:
	if GDSync.is_active():
		GDSync.lobby_leave()
