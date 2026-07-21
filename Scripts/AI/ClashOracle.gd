# ClashOracle.gd
# The AI's answer to the clash sub-round: a 3x3 stance game solved on the ACTUAL
# committed plans. Each cell resolves the full turn with (mine, theirs) stamped
# on the declared moves and scores it with the shared Eval -- so the mix reflects
# what push/pull/feint really DO from this exact position (the hp swing, the
# tile, the stagger), not a hand-authored triangle. NashSolver mixes; we sample,
# so the AI's stance is unexploitable over repeated clashes. Offline-only today
# (the online stance-exchange message is queued in HANDOFF).
class_name ClashOracle
extends RefCounted

const STANCES := ["push", "pull", "feint"]

static func choose_stance(grid: Grid, a: Combatant, b: Combatant,
		seq_a: Array, seq_b: Array, _turn: int, ai_is_a: bool) -> String:
	var me: Combatant = a if ai_is_a else b
	var foe: Combatant = b if ai_is_a else a
	var M: Array = []
	for mine in STANCES:
		var row: Array = []
		for theirs in STANCES:
			var sa := _stamped(seq_a, mine if ai_is_a else theirs)
			var sb := _stamped(seq_b, theirs if ai_is_a else mine)
			var my_seq: Array = sa if ai_is_a else sb
			var foe_seq: Array = sb if ai_is_a else sa
			row.append(Eval.score_rich(me, foe, grid, my_seq, foe_seq))
		M.append(row)
	var mix := NashSolver.solve(M)
	var r := randf()
	var acc := 0.0
	for i in mix.size():
		acc += float(mix[i])
		if r <= acc:
			return STANCES[i]
	return STANCES[0]

# A deep-enough copy of a plan with `stance` stamped on every declared move
# (the clash reads the rider off the colliding move; never mutates the original).
static func _stamped(plan: Array, stance: String) -> Array:
	var out: Array = []
	for act in plan:
		var d: Dictionary = act.duplicate()
		if String(d.get("id", "")) == "move":
			d["stance"] = stance
		out.append(d)
	return out
