# MatchTransport.gd  (abstract)
# The link to the match mediator. Hides the wire details and the authority model
# from the rest of the game. NetworkOpponent talks only to this contract; the one
# live implementation is GDSyncTransport (over the GD-Sync relay).
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

# Clash sub-round (server-authoritative transports only): the mediator detected a
# contested-tile collision and wants this player's stance before revealing. The
# base contract makes these optional -- GDSyncTransport never emits/answers.
signal stance_needed(turn: int)

# Emitted if the remote peer drops mid-match. NetworkOpponent surfaces this (via
# aborted()) so the turn loop can end the match rather than wait forever for a reveal
# that will never come.
signal opponent_left()

# Send our planned sequence for `turn`. The mediator must withhold it from the
# opponent until they too have submitted.
func submit_sequence(turn: int, seq: Array) -> void:
	push_error("MatchTransport.submit_sequence is abstract")

# Answer a stance_needed. No-op by default: only clash-capable transports override.
func send_stance(_stance: String) -> void:
	pass
