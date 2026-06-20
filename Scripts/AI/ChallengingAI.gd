# ChallengingAI.gd
# The "Challenging" brain. Unlike Easy (a fixed reaction ladder), this one LOOKS
# AHEAD at its own options: it builds a bounded set of candidate 1-2 action
# sequences, plays each through the REAL resolver against one assumed enemy move
# (what Easy would do this turn), scores the resulting position, and keeps the
# best. Because Resolver.resolve clones its inputs and never mutates them, this
# is side-effect free and reuses the exact combat rules (no duplicated math).
#
# It does NOT model a smart/uncertain enemy — that's reserved for Hard/Extreme.
# It assumes the enemy plays simply and optimizes its response.
#
# The scoring weights below are hand-tuned starting points; tune by playtest.
class_name ChallengingAI
extends RefCounted

const W_RES := 0.02      # tiny reward for keeping energy/mp (don't bleed dry)
const W_DIST := 0.4      # mild reward for staying close (keeps pressure on)


static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array) -> Array:
	# Assume the enemy plays the simple (Easy) move this turn, then optimize.
	var foe_seq := StubOpponent.choose_sequence(foe, me, grid, foe.spell_ids())

	# Start from Easy's own pick as a guaranteed-sane floor: Challenging is only
	# ever allowed to REPLACE it with something that scores strictly better.
	var best: Array = StubOpponent.choose_sequence(me, foe, grid, spells)
	var best_score := _score(me, foe, grid, best, foe_seq)

	for seq in AIToolkit.candidates(me, foe, grid):
		if seq.is_empty():
			continue
		var sc := _score(me, foe, grid, seq, foe_seq)
		if sc > best_score:
			best_score = sc
			best = seq
	return best

# Play my_seq vs the assumed foe_seq through the real rules; score from my side.
# me has id "B" and foe id "A" in the live game, so resolve(grid, foe, me, ...)
# preserves player order (A resolves before B on ties) exactly as in a real turn.
static func _score(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)
	var foe_after: Combatant = out["a"]
	var me_after: Combatant = out["b"]
	var dealt := float(foe.hp - foe_after.hp)
	var taken := float(me.hp - me_after.hp)
	var s := dealt * Eval.W_DEAL - taken * Eval.W_TAKE
	match String(out["result"]):
		"b_wins": s += Eval.W_WIN
		"a_wins": s -= Eval.W_WIN
	s += float(me_after.energy + me_after.mp) * W_RES
	s -= float(Grid.dist(me_after.pos, foe_after.pos)) * W_DIST
	return s
