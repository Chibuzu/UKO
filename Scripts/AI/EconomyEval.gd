# EconomyEval.gd
# The new-AI per-pair EVALUATOR (remodel step #1). Answers the same question as
# Eval -- "if I play my_seq and the foe plays foe_seq, how good is the result for
# me?" -- but scores it in the RESOURCE ECONOMY instead of the old damage/mobility
# heuristic. It is a drop-in alongside Eval (same signatures, same A=foe / B=me
# resolve order, same depth-2 subgame lookahead), so the matrix/Nash machinery
# uses it unchanged; only the value MODEL differs.
#
# Why the leaf is just advantage + position:
#   ResourceModel.advantage(after) already captures the WHOLE turn's exchange --
#   HP dealt/taken AND the MP/EP each side spent -- on one HP-equivalent axis. So
#   "resources spent to act vs resources removed from the enemy" falls straight
#   out of the resulting stockpiles; we don't add a separate damage term (that
#   would double-count HP). TileUtility adds where the position LEAVES us.
#
# MODULAR: reads no spell/gear ids. Combat runs through the real Resolver, value
# through ResourceModel + TileUtility, so new gear is priced automatically. This
# is also the natural seam for the goal layer (step #3): add a goal-potential
# term inside _position_value and nothing else changes.
class_name EconomyEval
extends RefCounted

const W_WIN := 1000.0     # winning/losing the duel dominates the economy
const W_POS := 0.5        # weight on positional advantage (standing-value differential)
const DISCOUNT := 0.9     # a future turn is worth slightly less than now
const LOOKAHEAD_DEPTH := 2  # 1 = this turn + static economy; 2 = + solved next-turn subgame
const DEEP_CANDS := 3     # per-side candidate cap inside a subgame node (keep it bounded)
const DEEP_ITERS := 64    # regret iterations for subgame solves (small matrices converge fast)

# my_seq vs one foe reply, MY perspective. Static leaf.
static func score_rich(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array) -> float:
	return score_deep(me, foe, grid, my_seq, foe_seq, 0)

# Depth-aware: depth 0 reads the resulting position statically; depth > 0 REPLACES
# that static read with the equilibrium value of the next-turn subgame, so the AI
# sees set-up -> payoff and bait -> punish across turns (the "trace optimal paths"
# part), all measured in the same economy currency.
static func score_deep(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array, depth: int) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)   # A=foe, B=me (live order)
	var foe_after: Combatant = out["a"]
	var me_after: Combatant = out["b"]
	var res := String(out["result"])
	var win := 0.0
	if res == "b_wins":
		win = W_WIN
	elif res == "a_wins":
		win = -W_WIN
	if depth <= 0 or res == "a_wins" or res == "b_wins":
		return win + _position_value(me_after, foe_after, grid)
	return win + DISCOUNT * _subgame_value(me_after, foe_after, grid, depth)

# Economic + positional worth of a resolved position, MY perspective. This is the
# whole value model: the resource exchange (advantage) plus how good the tiles we
# each ended on are (offense reach, safety, escape room, walls about to drop).
static func _position_value(me: Combatant, foe: Combatant, grid: Grid) -> float:
	var econ := ResourceModel.advantage(me, foe)
	var mine := TileUtility.standing_value(grid, me, foe, me.pos)
	var theirs := TileUtility.standing_value(grid, foe, me, foe.pos)
	if mine == -INF:
		mine = -500.0   # never let an (impossible) blocked stand poison the solver
	if theirs == -INF:
		theirs = -500.0
	return econ + W_POS * (mine - theirs)

# Maximin value of the next turn from this position: both sides pick fresh capped
# candidates, solve that small matrix, return what `me` can guarantee.
static func _subgame_value(me: Combatant, foe: Combatant, grid: Grid, depth: int) -> float:
	var my_c := _capped_cands(me, foe, grid)
	if my_c.is_empty():
		return _position_value(me, foe, grid)
	var foe_c := _capped_cands(foe, me, grid)
	if foe_c.is_empty():
		foe_c = [[{"id": "rest"}]]
	var M: Array = []
	for mc in my_c:
		var row: Array = []
		for fc in foe_c:
			row.append(score_deep(me, foe, grid, mc, fc, depth - 1))
		M.append(row)
	var mix := NashSolver.solve_iters(M, DEEP_ITERS)
	return NashSolver.value_of(M, mix)

# The DEEP_CANDS strongest candidate sequences for `me`, by a cheap positional
# proxy (no full sim), to keep subgame matrices small. The ROOT decision never
# caps -- the orchestrator feeds it the intent-pruned PlanGenerator set instead.
static func _capped_cands(me: Combatant, foe: Combatant, grid: Grid) -> Array:
	var clean: Array = []
	for c in AIToolkit.candidates(me, foe, grid):
		if not c.is_empty():
			clean.append(c)
	if clean.size() <= DEEP_CANDS:
		return clean
	var ranked: Array = []
	for c in clean:
		ranked.append({"seq": c, "v": _cheap_rank(me, foe, grid, c)})
	ranked.sort_custom(func(x, y): return float(x["v"]) > float(y["v"]))
	var out: Array = []
	for k in range(DEEP_CANDS):
		out.append(ranked[k]["seq"])
	return out

# Cheap economy/positional proxy for subgame capping: project the sequence and
# read the standing value where it lands -- no turn simulation.
static func _cheap_rank(me: Combatant, foe: Combatant, grid: Grid, seq: Array) -> float:
	var m := me.clone()
	for a in seq:
		AIToolkit.apply_projection(m, a)
	var v := TileUtility.standing_value(grid, m, foe, m.pos)
	return v if v != -INF else -500.0
