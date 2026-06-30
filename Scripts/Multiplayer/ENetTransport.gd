# EnetTransport.gd
# The real-network MatchTransport: a thin adapter that lets a NetworkOpponent talk
# to a NetworkSession exactly as it talked to the LoopbackTransport. Swapping one
# for the other is the only difference between a local protocol test and a live
# online match -- NetworkOpponent and the turn loop don't change.
class_name EnetTransport
extends MatchTransport

var _session: NetworkSession

func _init(session: NetworkSession) -> void:
	_session = session
	# Re-emit the session's reveals as our own turn_revealed signal.
	_session.turn_revealed.connect(func(bundle): turn_revealed.emit(bundle))
	_session.opponent_left.connect(func(): opponent_left.emit())

func submit_sequence(turn: int, seq: Array) -> void:
	_session.submit_local(turn, seq)

func handshake() -> Dictionary:
	return {}   # the real handshake runs on NetworkSession.match_ready, before the loop starts
