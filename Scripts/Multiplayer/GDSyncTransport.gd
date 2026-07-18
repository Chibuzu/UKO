# GDSyncTransport.gd
# MatchTransport over GD-Sync -- the drop-in that lets NetworkOpponent run on the
# GD-Sync relay exactly as it ran on Loopback/ENet. Swapping transports is the whole
# difference between local, LAN, and worldwide play; NetworkOpponent and the turn loop
# never change.
class_name GDSyncTransport
extends MatchTransport

var _session: GDSyncSession

func _init(session: GDSyncSession) -> void:
	_session = session
	_session.turn_revealed.connect(func(bundle): turn_revealed.emit(bundle))
	_session.opponent_left.connect(func(): opponent_left.emit())

func submit_sequence(turn: int, seq: Array) -> void:
	_session.submit_local(turn, seq)
