# OpponentSource.gd
# THE MULTIPLAYER SEAM. A turn needs two planned sequences: the local player's
# (from SelectionController) and the OPPONENT's. The Resolver is a pure function of
# those two sequences, so it does not care where the opponent's comes from -- a
# remote human is just a different OpponentSource than the AI. Swapping this single
# object is the whole offline<->online switch in the turn loop; nothing else in the
# Core, View, or AI changes.
#
# Contract:
#   opponent_sequence() returns the opponent combatant's planned action sequence for
#   this turn. It MAY be a coroutine (await a network reveal, or a repaint frame).
#   It receives the LOCAL player's sequence so a networked implementation can submit
#   it as part of a fair exchange -- but an implementation must never let the remote
#   side observe that plan before both players have committed (the WEGO simultaneity
#   guarantee lives inside the implementation, not here).
class_name OpponentSource
extends RefCounted

# me = the opponent combatant (whose plan we want); foe = the local player.
func opponent_sequence(me: Combatant, foe: Combatant, grid: Grid, turn_num: int, local_seq: Array, opp_model) -> Array:
	push_error("OpponentSource.opponent_sequence is abstract")
	return [{"id": "wait"}]

# True once the opponent connection has dropped and this source can no longer produce
# real plans (a remote peer left). The turn loop ends the match instead of hanging on
# a reveal that will never arrive. Offline sources (the AI) never abort.
func aborted() -> bool:
	return false
