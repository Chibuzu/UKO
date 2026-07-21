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
# Eval.LOOKAHEAD_DEPTH = 1 and a profile lambda of 0 recovers the pure
# shallow-equilibrium brain.
class_name ExtremeAI
extends RefCounted

const DOM_EPS        := 0.001 # strict-dominance margin for pruning the matrix
# ARCHIVE -- the shelved self-play champion (validated 63% vs defaults in
# self-play, then SHELVED after live-play regressions: passive waits, flank
# order, rest-into-bolt). Both tiers play Eval.DEFAULTS (see set_profile).
# Kept as data for evolution's next base; re-adoption requires the full gate
# suite. NOT read by any code path.
#   W_DEAL 0.776  W_TAKE 0.717  W_ENERGY 0.062  W_MP 0.052  W_LOCK 0.143
#   W_DANGER_MELEE 0.287  W_DANGER_SPELL 0.466  W_PRESSURE 0.349
#   W_ATTRITION 15.375  W_TEMPO 0.172  W_MOBILITY 0.860  W_PRESS 0.085
#   W_INCOMING 8.523  W_CENTER 0.287  W_ITEM 1.147  W_LETHAL 4.805
#   DISCOUNT 0.698

# ── Difficulty profiles: same brain, different throttles. CHALLENGING is the
# approved frozen feel; EXTREME opens budget, width, and exploitation. These
# dicts are the ONLY tuning source -- the code reads P[...], nothing else.
const PROFILES := {
	"challenging": {"budget_ms": 250, "budget_end_ms": 250, "rows": 3, "cols": 6, "rows_end": 5, "cols_end": 9, "lambda": 0.0},
	"extreme":     {"budget_ms": 3000, "budget_end_ms": 6000, "rows": 4, "cols": 8, "rows_end": 6, "cols_end": 10, "lambda": 0.6},
	# ROUND 10 (Fra-ratified "3s+"): EXTREME thinks 3s/turn (6s in the squeezed
	# endgame, where depth converts to near-perfect play). At 3s the root matrix
	# deepens to FULL coverage -- the old 700ms cap left half of it shallow. The
	# live turn no longer blocks the UI (AIOpponent polls the bridge's background
	# thread). Roll back = these two numbers.
}
static var P: Dictionary = PROFILES["extreme"]
static func set_profile(name: String) -> void:
	P = PROFILES.get(name, PROFILES["extreme"])
	# WEB CLAMP (round 17): the website build has no C# and no background thread,
	# so this brain runs ON the main thread -- a 3s/6s budget would freeze the
	# page every AI turn. Same brain, shorter leash. Platform clamp, NOT a rules
	# change: native builds keep full budgets (their C# twin owns the search),
	# and BrainAgreement never runs with the "web" feature, so parity is silent.
	if OS.has_feature("web") and int(P["budget_ms"]) > 900:
		P = P.duplicate()
		P["budget_ms"] = 900
		P["budget_end_ms"] = mini(int(P["budget_end_ms"]), 1200)
	# Weights ride with the tier: champion for EXTREME, hand defaults otherwise.
	# Champion SHELVED after live-play regressions (passive waits, flank order,
	# rest-into-bolt): it beat defaults in self-play but fails the richer human
	# gauntlet. It stays as evolution's base; re-adoption requires the new
	# behavior gates (tests 5-7) once written. Both tiers play hand defaults.
	Eval.set_weights(Eval.DEFAULTS)
	Eval.load_calibration()   # judge in P(win) once a calibration exists

const MIN_MIX        := 0.05  # support pruning: drop mix entries below this and renormalize --
							  #   a 2-3% sampled row reads as a blunder even when the math is right
const EXPLOIT_TEMP   := 3.0   # softmax temp over my EV vs the predicted foe (lower = greedier)

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array, opp_model = null) -> Array:
	var my_cands: Array = _clean(AIToolkit.candidates(me, foe, grid))
	var foe_cands: Array = _clean(AIToolkit.candidates(foe, me, grid))
	if my_cands.is_empty():
		return [{"id": "rest"}]
	if foe_cands.is_empty():
		foe_cands = [[{"id": "rest"}]]
	var t0 := Time.get_ticks_msec()
	# Endgame: depth converts to near-perfect play once the zone squeezes --
	# EXTREME doubles its budget there (cache + tiny branching make it cheap).
	var budget: int = int(P.get("budget_end_ms", P["budget_ms"])) if grid.shrink_level >= 2 else int(P["budget_ms"])
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
			if Time.get_ticks_msec() - t0 >= budget:
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
	# CALIBRATED JUDGMENT: convert every cell to win-probability before solving --
	# a nonlinear monotone map, so the equilibrium shifts exactly as it should:
	# ahead plays tight, behind polarizes. Points stay the internal currency.
	if Eval.CAL_A > 0.0:
		for wi in M.size():
			for wj in (M[wi] as Array).size():
				M[wi][wj] = Eval.to_winprob(float(M[wi][wj]))

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
	if Eval.LOOKAHEAD_DEPTH >= 2 and Time.get_ticks_msec() - t0 < budget:
		var deep2: int = Eval.LOOKAHEAD_DEPTH
		var touched := false
		for i in mix.size():
			if float(mix[i]) < 0.10:
				continue
			for j in _worst_cols(M[i], int(P["cols"])):
				if Time.get_ticks_msec() - t0 >= budget:
					break
				var v3 := Eval.score_deep(me, foe, grid, my_cands[i], foe_cands[j], deep2)
				M[i][j] = Eval.to_winprob(v3) if Eval.CAL_A > 0.0 else v3
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
	# TERMINAL ANTI-TELL (gate #8, both live losses): at starved endstates a collapsed
	# near-pure mix is a read a human exploits ("low energy -> it will guard"). Cap the
	# top line and re-spread the rest, ONLY when starved -- normal play is untouched.
	# Play-time spread on the SAMPLED path only: ChooseMix / the agreement harness's
	# deterministic pipeline are deliberately outside it. Mirrored in ExtremeAI.cs.
	if me.energy < Config.COST_GUARD:
		mix = _terminal_spread(mix)
	return my_cands[_sample(mix)]

const TERMINAL_CAP := 0.70   # max probability any single line keeps at a starved endstate

# Cap the mix's top entry at TERMINAL_CAP and hand the excess to the other live
# lines, proportionally. No-op when support is a single line (nothing to spread to).
static func _terminal_spread(mix: Array) -> Array:
	var top := 0
	var live := 0
	for i in mix.size():
		if float(mix[i]) > 0.0:
			live += 1
		if float(mix[i]) > float(mix[top]):
			top = i
	if live < 2 or float(mix[top]) <= TERMINAL_CAP:
		return mix
	var excess := float(mix[top]) - TERMINAL_CAP
	var rest := 1.0 - float(mix[top])
	var out := mix.duplicate()
	out[top] = TERMINAL_CAP
	for i in out.size():
		if i != top and float(out[i]) > 0.0:
			out[i] = float(out[i]) + excess * (float(mix[i]) / rest)
	return out

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
# Ranks are computed on QUANTIZED scores (1e-4 grid): the GD and C# evals drift by
# ~1e-7, and raw-score ranking let that drift pick DIFFERENT cells to deepen on
# knife-edge positions -- materially different matrices, 2-point value gaps
# (agreement pos2). Quantized ranks + index tiebreak = identical selection.
static func _rq(v: float) -> float:
	return floorf(v * 1e4 + 0.5) / 1e4

static func _top_rows(M: Array, k: int) -> Array:
	var rows: Array = []
	for i in M.size():
		var worst := INF
		for v in M[i]:
			worst = minf(worst, float(v))
		rows.append({"i": i, "w": _rq(worst)})
	# Stable tie-break (index asc): sort_custom is unstable; ties here decide which
	# rows get the deep look, so the order must be DEFINED (and match the C# port).
	rows.sort_custom(func(x, y):
		if float(x["w"]) != float(y["w"]):
			return float(x["w"]) > float(y["w"])
		return int(x["i"]) < int(y["i"]))
	var out: Array = []
	for n in range(mini(k, rows.size())):
		out.append(int(rows[n]["i"]))
	return out

# The k columns where the foe hurts me most in a row -- the replies worth a deep
# look (the foe's best answers to that move), so we don't deepen against all of them.
static func _worst_cols(row: Array, k: int) -> Array:
	var cols: Array = []
	for j in row.size():
		cols.append({"j": j, "v": _rq(float(row[j]))})
	cols.sort_custom(func(x, y):
		if float(x["v"]) != float(y["v"]):
			return float(x["v"]) < float(y["v"])
		return int(x["j"]) < int(y["j"]))
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
