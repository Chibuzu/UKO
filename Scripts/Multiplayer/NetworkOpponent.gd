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

signal _resolved()   # internal: fires when this turn's reveal OR a disconnect lands

var _net: MatchTransport
var _aborted := false
var _pending_turn := -1
var _bundle: Dictionary = {}

func _init(transport: MatchTransport) -> void:
	_net = transport
	# Connect ONCE (not per turn): a peer that drops while we're still selecting must
	# also be caught, so the next opponent_sequence returns immediately instead of
	# submitting into the void.
	_net.turn_revealed.connect(_on_reveal)
	_net.opponent_left.connect(_on_left)

func _on_reveal(bundle: Dictionary) -> void:
	if not _aborted and _bundle.is_empty() and int(bundle.get("turn", -1)) == _pending_turn:
		_bundle = bundle
		_resolved.emit()

func _on_left() -> void:
	_aborted = true
	_resolved.emit()   # wake a pending await, if any

func opponent_sequence(me: Combatant, foe: Combatant, grid: Grid, turn_num: int, local_seq: Array, opp_model) -> Array:
	if _aborted:
		return [{"id": "wait"}]                            # peer already gone -> loop will end the match
	_pending_turn = turn_num
	_bundle = {}
	_net.submit_sequence(turn_num, local_seq)             # 1. commit ours (mediator withholds it)
	if _bundle.is_empty() and not _aborted:               # guard: an in-process reveal may already be in
		await _resolved                                   # 2. released only when BOTH have committed
	if _aborted:
		return [{"id": "wait"}]
	return _bundle.get("opponent_seq", [{"id": "wait"}])

func aborted() -> bool:
	return _aborted

# The live transport -- GameController connects the clash sub-round through it.
func transport() -> MatchTransport:
	return _net
