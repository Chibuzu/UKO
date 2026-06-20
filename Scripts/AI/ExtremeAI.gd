# ExtremeAI.gd
# The EXTREME brain. HARD plays a robust BEST-RESPONSE -- strong, but any best
# response has a pattern a sharp human can eventually read and exploit (baiting the
# guard, cornering it). EXTREME stops best-responding. It treats each turn as the
# simultaneous, hidden-move game it actually is and plays the game-theoretic
# EQUILIBRIUM: a mixed strategy whose worst-case payoff is maximised, so no fixed
# counter beats it over time -- there is no readable pattern left to abuse.
#
# It reuses HARD's exact per-pair scorer to fill the payoff matrix, so all the
# threat / resource / positional reasoning is identical -- EXTREME changes only HOW
# the move is chosen (sample an equilibrium mix vs. take the robust argmax). A pro
# can still win games by playing a balanced strategy of their own; they just can't
# find a repeatable exploit.
class_name ExtremeAI
extends RefCounted

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array, opp_model = null) -> Array:
	# Rows = my candidate moves, columns = the foe's feasible replies (same
	# generators HARD/Challenging use).
	var my_cands: Array = []
	for s in AIToolkit.candidates(me, foe, grid):
		if not s.is_empty():
			my_cands.append(s)
	var foe_cands: Array = []
	for s in AIToolkit.candidates(foe, me, grid):
		if not s.is_empty():
			foe_cands.append(s)
	if my_cands.is_empty():
		return [{"id": "rest"}]
	if foe_cands.is_empty():
		foe_cands = [[{"id": "rest"}]]

	# Payoff matrix M[i][j] = MY score if I play my_cands[i] and the foe plays
	# foe_cands[j], via HARD's scorer -- identical threat/resource/position reasoning;
	# EXTREME only changes the selection rule on top of it. The duel is treated as
	# zero-sum (the foe minimises my score), so the solution is the mixed minimax.
	var M: Array = []
	for my_seq in my_cands:
		var row: Array = []
		for foe_seq in foe_cands:
			row.append(HardAI._score_rich(me, foe, grid, my_seq, foe_seq))
		M.append(row)

	# Solve for my unexploitable mixed strategy, then sample my move from it. The
	# unpredictability is a property of the equilibrium, not an ad-hoc mixer.
	var mix: Array = NashSolver.solve(M)
	return my_cands[_sample(mix)]

# Sample an index from a probability distribution (intentionally nondeterministic).
static func _sample(dist: Array) -> int:
	var r := randf()
	var acc := 0.0
	for i in dist.size():
		acc += float(dist[i])
		if r <= acc:
			return i
	return maxi(0, dist.size() - 1)
