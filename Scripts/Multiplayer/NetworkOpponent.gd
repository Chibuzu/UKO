# NetworkOpponent.gd  (SKELETON -- transport + server are later phases)
# Online opponent. Implements the CLIENT side of the fair exchange against a
# MatchTransport mediator (server or host):
#   1. SUBMIT our local sequence for this turn to the mediator.
#   2. AWAIT the mediator's REVEAL, which it sends only once BOTH players have
#      submitted -- so neither side can peek at the other's plan first. The mediator
#      withholds; we simply wait, and a 150ms-away opponent is invisible because we
#      were waiting for them to finish planning anyway (this is a WEGO game).
#
# Because the Core Resolver is deterministic, the wire payload is just the two
# sequences (a handful of action dicts). Each client recomputes the identical turn;
# positions, HP, and animation state never cross the network. (This is the
# relay/lockstep model. A server-authoritative variant would instead receive the
# resolved event list and skip the local resolve -- see MULTIPLAYER.md.)
class_name NetworkOpponent
extends OpponentSource

var _net: MatchTransport

func _init(transport: MatchTransport) -> void:
	_net = transport

func opponent_sequence(me: Combatant, foe: Combatant, grid: Grid, turn_num: int, local_seq: Array, opp_model) -> Array:
	_net.submit_sequence(turn_num, local_seq)             # 1. commit ours (mediator withholds it)
	var bundle: Dictionary = await _net.turn_revealed     # 2. released only when BOTH have committed
	while int(bundle.get("turn", -1)) != turn_num:        # ignore any stale reveal from an earlier turn
		bundle = await _net.turn_revealed
	return bundle.get("opponent_seq", [{"id": "wait"}])
