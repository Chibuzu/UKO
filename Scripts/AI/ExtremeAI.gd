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
#   * PRUNING: iterated elimination of strictly dominated moves (both sides) before
#     the solve -- the human skill of collapsing the foe's reachable set, made exact.
#   * THE CLOCK: Eval prices the telegraphed walls / zone ring and centre depth, and
#     in the squeezed endgame (shrink >= 2) the deep look widens -- it sees furthest
#     exactly when the arena is small enough to afford it.
#
# Per-pair scoring + candidate generation are the shared AIToolkit / Eval modules
# (same game HARD reasons about); EXTREME owns only the SELECTION rule below. Setting
# Eval.LOOKAHEAD_DEPTH = 1 and EXPLOIT_LAMBDA = 0 recovers the pure shallow-equilibrium brain.
class_name ExtremeAI
extends RefCounted

const ROOT_ROWS      := 3     # how many of MY near-best moves get the deep (2-turn) look
const ROOT_COLS      := 6     # ...each deepened only vs the foe's most threatening replies
const ROOT_ROWS_END  := 5     # once the zone has squeezed the arena (shrink >= 2), moves are
const ROOT_COLS_END  := 9     #   few and lethal: see further exactly when it's cheap to.
const DOM_EPS        := 0.001 # strict-dominance margin for pruning the matrix
# ── Evolved weights (self-play champion, validated 63% vs defaults on fresh
# seeds + all position tests green). EXTREME plays these; CHALLENGING keeps the
# hand-tuned Eval defaults -- the tiers are genuinely different fighters.
const CHAMPION_WEIGHTS := {
		"W_DEAL": 0.7760433647207,
		"W_TAKE": 0.71699658697021,
		"W_ENERGY": 0.06208346917766,
		"W_MP": 0.05249705114287,
		"W_LOCK": 0.14339931739404,
		"W_DANGER_MELEE": 0.28679863478809,
		"W_DANGER_SPELL": 0.46562601883242,
		"W_PRESSURE": 0.34921951412432,
		"W_ATTRITION": 15.3749149091094,
		"W_TEMPO": 0.17207918087285,
		"W_MOBILITY": 0.86039590436426,
		"W_PRESS": 0.08479263985039,
		"W_INCOMING": 8.52305065613671,
		"W_CENTER": 0.28679863478809,
		"W_ITEM": 1.14719453915234,
		"W_LETHAL": 4.80466090909668,
		"DISCOUNT": 0.69843902824863,
}

# ── Difficulty profiles: same brain, different throttles. CHALLENGING is the
# approved frozen feel; EXTREME opens budget, width, and exploitation.
const PROFILES := {
	"challenging": {"budget_ms": 250, "rows": 3, "cols": 6, "rows_end": 5, "cols_end": 9, "lambda": 0.0},
	"extreme":     {"budget_ms": 700, "rows": 4, "cols": 8, "rows_end": 6, "cols_end": 10, "lambda": 0.6},
}
static var P: Dictionary = PROFILES["extreme"]
static func set_profile(name: String) -> void:
	P = PROFILES.get(name, PROFILES["extreme"])
	# Weights ride with the tier: champion for EXTREME, hand defaults otherwise.
	if name == "extreme":
		Eval.set_weights(CHAMPION_WEIGHTS)
	else:
		Eval.set_weights(Eval.DEFAULTS)

const MIN_MIX        := 0.05  # support pruning: drop mix entries below this and renormalize --
							  #   a 2-3% sampled row reads as a blunder even when the math is right
const BUDGET_MS      := 250   # think budget: after the baseline deep look, keep deepening
							  #   the next most decision-relevant cells until this runs out
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
	var t0 := Time.get_ticks_msec()
	Eval.clear_cache()   # per-decision transposition cache for subgame values

	# Shallow payoff matrix: MY score for (my move i, foe reply j) -- one turn + heuristic.
	var M: Array = []
	for my_seq in my_cands:
		var row: Array = []
		for foe_seq in foe_cands:
			row.append(Eval.score_rich(me, foe, grid, my_seq, foe_seq))
		M.append(row)

	# DEPTH -- baseline selective deepening, then BUDGETED: the strongest rows vs the
	# most threatening replies get the full deep look first; whatever time remains
	# upgrades the next most decision-relevant shallow cells. In the squeezed endgame
	# branching collapses and the subgame cache bites, so the same budget reaches much
	# further -- and the leaves look one ply deeper (functionally: perfect endgames).
	if Eval.LOOKAHEAD_DEPTH >= 2:
		var deep_rows := int(P["rows_end"]) if grid.shrink_level >= 2 else int(P["rows"])
		var deep_cols := int(P["cols_end"]) if grid.shrink_level >= 2 else int(P["cols"])
		var leaf := Eval.LOOKAHEAD_DEPTH - 1
		if grid.shrink_level >= 3:
			leaf = Eval.LOOKAHEAD_DEPTH
		var done := {}
		for i in _top_rows(M, deep_rows):
			for j in _worst_cols(M[i], deep_cols):
				M[i][j] = Eval.score_deep(me, foe, grid, my_cands[i], foe_cands[j], leaf)
				done["%d,%d" % [i, j]] = true
		for cell in _deepen_order(M):
			if Time.get_ticks_msec() - t0 >= int(P["budget_ms"]):
				break
			var ci: int = cell["i"]
			var cj: int = cell["j"]
			if done.has("%d,%d" % [ci, cj]):
				continue
			M[ci][cj] = Eval.score_deep(me, foe, grid, my_cands[ci], foe_cands[cj], leaf)

	# PRUNE: iterated elimination of strictly dominated moves -- mine (rows) and the
	# foe's (columns). A move that is worse than another against EVERYTHING is not
	# part of any sane mix; the human skill of "pruning the reachable set", made
	# exact. Solving the reduced game sharpens the equilibrium and speeds the solve.
	var dom := _dominance_filter(M)
	var reduced := _submatrix(M, dom["rows"], dom["cols"])

	# Unexploitable equilibrium mix over my surviving moves -- the floor. Expanded
	# back to full candidate indexing (eliminated moves get probability 0).
	var mix: Array = _expand(NashSolver.solve(reduced), dom["rows"], my_cands.size())

	# DEPTH 3 (selective): the solved mix now says which of MY lines actually carry
	# weight. Re-score those rows' most threatening cells ONE PLY DEEPER (their
	# leaves become solved depth-2 subgames -> 3-ply total) inside the remaining
	# budget, then re-solve on the refined matrix. The transposition cache makes
	# revisited states cheap; the budget guard means this phase can only refine
	# the answer, never stall a turn.
	if Eval.LOOKAHEAD_DEPTH >= 2 and Time.get_ticks_msec() - t0 < int(P["budget_ms"]):
		var deep2: int = Eval.LOOKAHEAD_DEPTH
		var touched := false
		for i in mix.size():
			if float(mix[i]) < 0.10:
				continue
			for j in _worst_cols(M[i], int(P["cols"])):
				if Time.get_ticks_msec() - t0 >= int(P["budget_ms"]):
					break
				M[i][j] = Eval.score_deep(me, foe, grid, my_cands[i], foe_cands[j], deep2)
				touched = true
		if touched:
			dom = _dominance_filter(M)
			mix = _expand(NashSolver.solve(_submatrix(M, dom["rows"], dom["cols"])), dom["rows"], my_cands.size())

	# EXPLOITATION: tilt the mix toward punishing the foe's observed habits IN THIS
	# SITUATION, scaled by how much history backs the read (confidence) and bounded
	# by EXPLOIT_LAMBDA. The equilibrium stays underneath.
	if opp_model != null and float(P["lambda"]) > 0.0 and opp_model.is_warm():
		var sit: String = OpponentModel.situation_of(foe, me, grid)
		var q: Array = _predict(opp_model, foe_cands, sit)
		var ev: Array = []
		for i in my_cands.size():
			var e := 0.0
			for j in foe_cands.size():
				e += float(M[i][j]) * float(q[j])
			ev.append(e)
		var exploit: Array = _softmax(ev, EXPLOIT_TEMP)
		var lam: float = float(P["lambda"]) * opp_model.confidence()
		for i in mix.size():
			mix[i] = (1.0 - lam) * float(mix[i]) + lam * float(exploit[i])

	mix = _prune_support(mix, MIN_MIX)   # keep mixing, but never play negligible lines
	return my_cands[_sample(mix)]

# Drop empty sequences from a candidate list.
static func _clean(cands: Array) -> Array:
	var out: Array = []
	for s in cands:
		if not s.is_empty():
			out.append(s)
	return out

# Iterated elimination of strictly dominated moves. Rows are MY moves (I maximise M):
# row i dies if some row k beats it against EVERY live column by at least DOM_EPS.
# Columns are the FOE's (it minimises M): column j dies if some column l is lower
# against every live row. Repeats until stable; at least one row and column always
# survive (a maximal move can't be strictly dominated).
static func _dominance_filter(M: Array) -> Dictionary:
	var rows: Array = []
	for i in M.size():
		rows.append(i)
	var cols: Array = []
	for j in (M[0] as Array).size():
		cols.append(j)
	var changed := true
	while changed:
		changed = false
		var keep_r: Array = []
		for i in rows:
			var dominated := false
			for k in rows:
				if k == i:
					continue
				var beats_all := true
				for j in cols:
					if float(M[k][j]) < float(M[i][j]) + DOM_EPS:
						beats_all = false
						break
				if beats_all:
					dominated = true
					break
			if dominated:
				changed = true
			else:
				keep_r.append(i)
		if not keep_r.is_empty():
			rows = keep_r
		var keep_c: Array = []
		for j in cols:
			var dominated2 := false
			for l in cols:
				if l == j:
					continue
				var lower_all := true
				for i in rows:
					if float(M[i][l]) > float(M[i][j]) - DOM_EPS:
						lower_all = false
						break
				if lower_all:
					dominated2 = true
					break
			if dominated2:
				changed = true
			else:
				keep_c.append(j)
		if not keep_c.is_empty():
			cols = keep_c
	return {"rows": rows, "cols": cols}

static func _submatrix(M: Array, rows: Array, cols: Array) -> Array:
	var out: Array = []
	for i in rows:
		var r: Array = []
		for j in cols:
			r.append(M[i][j])
		out.append(r)
	return out

# Expand a mix over surviving rows back to the full candidate list (zeros elsewhere).
static func _expand(mix: Array, rows: Array, n: int) -> Array:
	var out: Array = []
	for _i in n:
		out.append(0.0)
	for k in rows.size():
		var idx: int = rows[k]
		out[idx] = float(mix[k])
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

# Priority order for BUDGETED deepening over the whole matrix: rows by best
# worst-case first (the moves the mix will actually weight), and within a row the
# foe's most threatening replies first. The budget loop walks this list.
static func _deepen_order(M: Array) -> Array:
	var out: Array = []
	for i in _top_rows(M, M.size()):
		for j in _worst_cols(M[i], (M[i] as Array).size()):
			out.append({"i": int(i), "j": int(j)})
	return out

# Predicted foe-reply distribution from observed tendencies (normalized weights).
static func _predict(opp_model, foe_cands: Array, sit: String = "") -> Array:
	var w: Array = []
	var tot := 0.0
	for fc in foe_cands:
		var x: float = opp_model.weight_of(fc, sit)
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

# Zero out entries below the floor and renormalize. Mixing stays (unexploitable
# frequencies survive within the kept support); only the "why did it do THAT" tail
# -- near-tie noise like a pointless there-and-back -- gets cut.
static func _prune_support(mix: Array, floor_p: float) -> Array:
	var out: Array = []
	var tot := 0.0
	for v in mix:
		var x: float = float(v) if float(v) >= floor_p else 0.0
		out.append(x)
		tot += x
	if tot <= 0.0:
		return mix
	for i in out.size():
		out[i] = float(out[i]) / tot
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
