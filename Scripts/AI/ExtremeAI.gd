# ExtremeAI.gd
# The EXTREME brain. It still treats each turn as the simultaneous, hidden-move game
# it is and solves for the game-theoretic EQUILIBRIUM -- a mixed strategy whose worst
# case is maximised, so no fixed counter beats it over time. That equilibrium is the
# unexploitable FLOOR. On top of it EXTREME adds two things HARD / Challenging lack:
#
#   * DEPTH (lookahead): the strongest of its candidate moves are scored two turns
#     deep -- each leaf is the SOLVED value of the next turn's subgame -- so it sees
#     set-up -> burst and bait -> punish combos, not just this turn + a heuristic.
#   * EXPLOITATION (bounded): pure equilibrium never PUNISHES a predictable human.
#     With a read (OpponentModel warm) it tilts -- by a bounded amount -- toward the
#     move that best answers the foe's observed habits, keeping the equilibrium mix
#     underneath so a sharp opponent still can't find a repeatable exploit.
#
# Per-pair scoring + candidate generation are the shared AIToolkit / Eval modules
# (same game HARD reasons about); EXTREME owns only the SELECTION rule below. Setting
# Eval.LOOKAHEAD_DEPTH = 1 and EXPLOIT_LAMBDA = 0 recovers the pure shallow-equilibrium brain.
class_name ExtremeAI
extends RefCounted

const ROOT_ROWS      := 3     # how many of MY near-best moves get the deep (2-turn) look
const ROOT_COLS      := 6     # ...each deepened only vs the foe's most threatening replies
const EXPLOIT_LAMBDA := 0.4   # 0 = pure equilibrium (unexploitable); 1 = pure best-response
							  #   to the read. Bounded, so a sharp human can't re-exploit the tilt.
const EXPLOIT_TEMP   := 3.0   # softmax temp over my EV vs the predicted foe (lower = greedier)

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array, opp_model = null) -> Array:
	var my_cands: Array = _clean(AIToolkit.candidates(me, foe, grid))
	var foe_cands: Array = _clean(AIToolkit.candidates(foe, me, grid))
	if my_cands.is_empty():
		return [{"id": "rest"}]
	if foe_cands.is_empty():
		foe_cands = [[{"id": "rest"}]]

	# Shallow payoff matrix: MY score for (my move i, foe reply j) -- one turn + heuristic.
	var M: Array = []
	for my_seq in my_cands:
		var row: Array = []
		for foe_seq in foe_cands:
			row.append(Eval.score_rich(me, foe, grid, my_seq, foe_seq))
		M.append(row)

	# DEPTH: deepening every cell is a matrix-of-matrices blow-up, so deepen only the
	# handful of moves I'd actually consider (selective deepening) -- recompute those
	# rows with the full two-turn lookahead.
	if Eval.LOOKAHEAD_DEPTH >= 2:
		for i in _top_rows(M, ROOT_ROWS):
			for j in _worst_cols(M[i], ROOT_COLS):
				M[i][j] = Eval.score_deep(me, foe, grid, my_cands[i], foe_cands[j], Eval.LOOKAHEAD_DEPTH - 1)

	# Unexploitable equilibrium mix over my moves -- the floor.
	var mix: Array = NashSolver.solve(M)

	# EXPLOITATION: tilt the mix toward punishing the foe's observed habits, bounded by
	# EXPLOIT_LAMBDA, only once the model is warm. The equilibrium stays underneath.
	if opp_model != null and EXPLOIT_LAMBDA > 0.0 and opp_model.is_warm():
		var q: Array = _predict(opp_model, foe_cands)
		var ev: Array = []
		for i in my_cands.size():
			var e := 0.0
			for j in foe_cands.size():
				e += float(M[i][j]) * float(q[j])
			ev.append(e)
		var exploit: Array = _softmax(ev, EXPLOIT_TEMP)
		for i in mix.size():
			mix[i] = (1.0 - EXPLOIT_LAMBDA) * float(mix[i]) + EXPLOIT_LAMBDA * float(exploit[i])

	return my_cands[_sample(mix)]

# Drop empty sequences from a candidate list.
static func _clean(cands: Array) -> Array:
	var out: Array = []
	for s in cands:
		if not s.is_empty():
			out.append(s)
	return out

# Indices of the rows with the best WORST-CASE value -- the moves worth deepening.
static func _top_rows(M: Array, k: int) -> Array:
	var rows: Array = []
	for i in M.size():
		var worst := INF
		for v in M[i]:
			worst = minf(worst, float(v))
		rows.append({"i": i, "w": worst})
	rows.sort_custom(func(x, y): return float(x["w"]) > float(y["w"]))
	var out: Array = []
	for n in range(mini(k, rows.size())):
		out.append(int(rows[n]["i"]))
	return out

# The k columns where the foe hurts me most in a row -- the replies worth a deep
# look (the foe's best answers to that move), so we don't deepen against all of them.
static func _worst_cols(row: Array, k: int) -> Array:
	var cols: Array = []
	for j in row.size():
		cols.append({"j": j, "v": float(row[j])})
	cols.sort_custom(func(x, y): return float(x["v"]) < float(y["v"]))
	var out: Array = []
	for n in range(mini(k, cols.size())):
		out.append(int(cols[n]["j"]))
	return out

# Predicted foe-reply distribution from observed tendencies (normalized weights).
static func _predict(opp_model, foe_cands: Array) -> Array:
	var w: Array = []
	var tot := 0.0
	for fc in foe_cands:
		var x: float = opp_model.weight_of(fc)
		w.append(x)
		tot += x
	if tot <= 0.0:
		return _uniform(foe_cands.size())
	for i in w.size():
		w[i] = float(w[i]) / tot
	return w

static func _softmax(xs: Array, temp: float) -> Array:
	if xs.is_empty():
		return []
	var hi := -INF
	for x in xs:
		hi = maxf(hi, float(x))
	var out: Array = []
	var z := 0.0
	for x in xs:
		var e: float = exp((float(x) - hi) / maxf(0.0001, temp))
		out.append(e)
		z += e
	for i in out.size():
		out[i] = float(out[i]) / z
	return out

static func _uniform(n: int) -> Array:
	var out: Array = []
	var p := (1.0 / float(n)) if n > 0 else 0.0
	for _i in n:
		out.append(p)
	return out

# Sample an index from a probability distribution (intentionally nondeterministic).
static func _sample(dist: Array) -> int:
	var r := randf()
	var acc := 0.0
	for i in dist.size():
		acc += float(dist[i])
		if r <= acc:
			return i
	return maxi(0, dist.size() - 1)
