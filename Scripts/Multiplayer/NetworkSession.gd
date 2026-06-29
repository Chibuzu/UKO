# NetworkSession.gd
# The real networking hub for an online 1v1 (Godot high-level multiplayer / ENet).
# It is a Node because RPCs need one. It owns the connection, runs the HANDSHAKE
# (exchange both loadouts + a shared map seed so both Resolvers start identical),
# and on the HOST it runs the MatchMediator -- the fairness authority that withholds
# each plan until both have submitted. The host is side "A", the client side "B".
#
# This is host-authoritative-MEDIATOR (relay/lockstep): the host pairs the two
# submitted sequences and reveals them; each client still runs its own Resolver.
# Nothing but the two sequences (a few action dicts) ever crosses the wire.
#
# NOTE: needs in-engine testing -- the fairness logic (MatchMediator) is verified,
# but the ENet/RPC plumbing here has not been run yet.
class_name NetworkSession
extends Node

signal match_ready(config: MatchConfig)   # handshake done; both sides hold an identical config
signal turn_revealed(bundle: Dictionary)  # { turn, opponent_seq } -- both submitted, released
signal connection_failed()
signal opponent_left()

const PORT_DEFAULT := 7777
const CONTENT_VERSION := "0.1"   # bump when rules/spells/gear change; both sides must match

var _is_host := false
var _my_loadout: Array = []
var _mediator: MatchMediator      # host only

# ── connect ────────────────────────────────────────────────────────────────
func host(my_loadout: Array, port: int = PORT_DEFAULT) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, 1) != OK:   # 1v1 -> one client slot
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	_is_host = true
	_my_loadout = my_loadout.duplicate()
	_mediator = MatchMediator.new()
	_mediator.register("A", _deliver_to_host)
	_mediator.register("B", _deliver_to_client)
	multiplayer.peer_disconnected.connect(func(_id): opponent_left.emit())
	# the client says hello (with its loadout) once connected -> see _rpc_client_hello

func join(ip: String, my_loadout: Array, port: int = PORT_DEFAULT) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	_is_host = false
	_my_loadout = my_loadout.duplicate()
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): opponent_left.emit())

# ── handshake ────────────────────────────────────────────────────────────────
func _on_connected_to_server() -> void:
	_rpc_client_hello.rpc_id(1, _my_loadout)   # client -> host: here's my loadout (I'm B)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_hello(loadout_b: Array) -> void:
	if not _is_host:
		return
	var seed_value := randi()                  # host picks the shared map seed
	var client_id := multiplayer.get_remote_sender_id()
	_rpc_handshake.rpc_id(client_id, seed_value, CONTENT_VERSION, _my_loadout, loadout_b)
	match_ready.emit(MatchConfig.make(seed_value, CONTENT_VERSION, _my_loadout, loadout_b, true))

@rpc("authority", "call_remote", "reliable")
func _rpc_handshake(seed_value: int, version: String, loadout_a: Array, loadout_b: Array) -> void:
	if version != CONTENT_VERSION:
		connection_failed.emit()   # rules mismatch -> refuse (lockstep would desync)
		return
	match_ready.emit(MatchConfig.make(seed_value, version, loadout_a, loadout_b, false))

# ── per-turn exchange ────────────────────────────────────────────────────────
# Called by EnetTransport once our local player has committed this turn's plan.
func submit_local(turn: int, seq: Array) -> void:
	if _is_host:
		_mediator.submit("A", turn, seq)        # straight into the host's mediator
	else:
		_rpc_submit.rpc_id(1, turn, seq)         # ship to the host

@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit(turn: int, seq: Array) -> void:
	if _is_host:
		_mediator.submit("B", turn, seq)         # the client's plan reached the mediator

# Mediator -> host's own player (deliver locally).
func _deliver_to_host(turn: int, opp_seq: Array) -> void:
	turn_revealed.emit({"turn": turn, "opponent_seq": opp_seq})

# Mediator -> client (ship the reveal).
func _deliver_to_client(turn: int, opp_seq: Array) -> void:
	for id in multiplayer.get_peers():
		_rpc_reveal.rpc_id(id, turn, opp_seq)

@rpc("authority", "call_remote", "reliable")
func _rpc_reveal(turn: int, opp_seq: Array) -> void:
	turn_revealed.emit({"turn": turn, "opponent_seq": opp_seq})
