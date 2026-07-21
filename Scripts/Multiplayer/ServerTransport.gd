# ServerTransport.gd
# MatchTransport over OUR OWN server -- the sibling of GDSyncTransport. Also
# relays the server's clash sub-round (stance_needed / send_stance), which the
# relay era never had: the SERVER detects the contested tile and asks both
# players; GameController shows the same StanceOverlay offline play uses.
class_name ServerTransport
extends MatchTransport

var _session: ServerSession

func _init(session: ServerSession) -> void:
	_session = session
	_session.turn_revealed.connect(func(bundle): turn_revealed.emit(bundle))
	_session.opponent_left.connect(func(): opponent_left.emit())
	_session.stance_needed.connect(func(turn): stance_needed.emit(turn))

func submit_sequence(turn: int, seq: Array) -> void:
	_session.submit_local(turn, seq)

func send_stance(stance: String) -> void:
	_session.send_stance(stance)
