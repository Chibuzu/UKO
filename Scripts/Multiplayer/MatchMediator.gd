# MatchMediator.gd
# The fairness authority for one match. Its ONE job is the WEGO simultaneity
# guarantee: collect both players' planned sequences for a turn and reveal NOTHING
# until BOTH have arrived, then release each player the OTHER's sequence at once.
# A player who waits to "see" the opponent's plan first gets nothing to see.
#
# Transport-agnostic: a host wraps this and ferries submit()/deliver over the wire;
# the live GDSyncSession runs it on the host. It never runs the Resolver
# (that's the relay/lockstep model -- each client resolves the revealed pair). A
# server-authoritative variant would resolve here and deliver an event list instead.
class_name MatchMediator
extends RefCounted

var _pending := {}   # turn -> { "A": Array, "B": Array }
var _sinks := {}     # slot -> Callable(turn:int, opponent_seq:Array)

# Register where to deliver a slot's revealed opponent sequence ("A" or "B").
func register(slot: String, deliver: Callable) -> void:
	_sinks[slot] = deliver

# A player commits its sequence for `turn`. Withheld until the opponent also commits.
func submit(slot: String, turn: int, seq: Array) -> void:
	var box: Dictionary = _pending.get(turn, {})
	box[slot] = seq.duplicate(true)
	_pending[turn] = box
	if box.has("A") and box.has("B"):
		_reveal(turn, box)

# Both committed -> release simultaneously (each gets the OTHER's plan), then clear.
func _reveal(turn: int, box: Dictionary) -> void:
	if _sinks.has("A"):
		_sinks["A"].call(turn, box["B"])
	if _sinks.has("B"):
		_sinks["B"].call(turn, box["A"])
	_pending.erase(turn)

# How many turns are still waiting on a second submission (diagnostics / timeouts).
func outstanding() -> int:
	return _pending.size()

# Turn-timeout hook: force a default (e.g. wait) for a slot that went silent, which
# unblocks the turn exactly as if that player had submitted it.
func force_default(slot: String, turn: int, default_seq: Array = [{"id": "wait"}]) -> void:
	submit(slot, turn, default_seq)
