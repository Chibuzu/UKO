# MatchTransport.gd  (abstract)
# The link to the match mediator. Hides the wire details (ENet, WebSocket, a headless
# Godot host, or a Loopback stub for local protocol tests) and the authority model
# from the rest of the game. NetworkOpponent talks only to this contract.
#
# The mediator's ONE non-negotiable job: never release a player's submitted sequence
# to the opponent until the opponent has also submitted (the simultaneity guarantee).
#
# Signals:
#   turn_revealed({ turn:int, opponent_seq:Array }) -- emitted once both players'
#       submissions for `turn` are in and the mediator releases them together.
class_name MatchTransport
extends RefCounted

signal turn_revealed(bundle: Dictionary)

# Send our planned sequence for `turn`. The mediator must withhold it from the
# opponent until they too have submitted.
func submit_sequence(turn: int, seq: Array) -> void:
	push_error("MatchTransport.submit_sequence is abstract")

# Agree on the match's starting conditions before turn 1: map seed, both loadouts
# (gear ids -> spells are derived), and a content version so both clients share rules.
func handshake() -> Dictionary:
	push_error("MatchTransport.handshake is abstract")
	return {}
