# LoopbackTransport.gd
# An in-process MatchTransport so the whole submit/withhold/reveal protocol can be
# exercised with NO network and NO server -- two endpoints share one MatchMediator.
# This is the test rig for phase 2: a NetworkOpponent talking to a LoopbackTransport
# behaves exactly as it will against a real server, so we validate the protocol and
# determinism locally, then swap in an ENet/WebSocket transport with zero changes to
# NetworkOpponent or the turn loop.
class_name LoopbackTransport
extends MatchTransport

var _mediator: MatchMediator
var _slot: String        # "A" or "B"
var _config: MatchConfig

# Build a connected pair (shared mediator) from two agreeing configs. Returns
# [transport_for_A, transport_for_B].
static func pair(config_a: MatchConfig, config_b: MatchConfig) -> Array:
	var med := MatchMediator.new()
	var ta := LoopbackTransport.new()
	ta._mediator = med
	ta._slot = "A"
	ta._config = config_a
	var tb := LoopbackTransport.new()
	tb._mediator = med
	tb._slot = "B"
	tb._config = config_b
	med.register("A", ta._receive)
	med.register("B", tb._receive)
	return [ta, tb]

func submit_sequence(turn: int, seq: Array) -> void:
	_mediator.submit(_slot, turn, seq)

func handshake() -> Dictionary:
	return {"config": _config, "slot": _slot}

# Mediator -> us: our opponent's plan for this turn is now released.
func _receive(turn: int, opponent_seq: Array) -> void:
	turn_revealed.emit({"turn": turn, "opponent_seq": opponent_seq})
