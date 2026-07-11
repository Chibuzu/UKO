# NashSolver.gd
# Solves a two-player ZERO-SUM matrix game for the row player's optimal MIXED
# strategy via regret matching (self-play, the engine behind CFR for normal-form
# games). The row player maximises M; the column player minimises it. The returned
# distribution is the game-theoretic equilibrium -- the mixed minimax strategy that
# maximises the row player's WORST-CASE expected payoff. It is unexploitable: no
# fixed reply beats it in the long run, so there is no pattern left to read.
#
# Pure / static / no game knowledge -- it just takes a matrix of numbers, so it is
# unit-testable against known games (rock-paper-scissors -> uniform).
class_name NashSolver
extends RefCounted

const ITERS := 600   # regret-matching iterations; ~0.01 strategy error, a few ms on a 12x12 [perf/accuracy dial]

# M: rows x cols, the ROW player's payoff. Returns a probability distribution over
# rows (length = M.size()) = the row player's equilibrium strategy.
static func solve(M: Array) -> Array:
	return solve_iters(M, ITERS)

# Same regret-matching solve with an explicit iteration budget; the subgame nodes
# in EXTREME's lookahead pass a smaller one to stay affordable.
static func solve_iters(M: Array, iters: int) -> Array:
	var n := M.size()
	if n == 0:
		return []
	# PAYOFF QUANTIZATION (both engines, identical): Nash equilibria are
	# DISCONTINUOUS in payoffs -- a last-bit float difference between the GD and
	# C# evals can legally flip which equivalent equilibrium regret-matching
	# converges to (support flips of whole percentage points from 1e-6 drift).
	# Rounding the matrix to a 1e-6 grid BEFORE solving makes both solvers see
	# bit-identical inputs forever, so every future eval term stays agreement-safe.
	# 1e-6 payoff precision is far beyond any behavioral meaning.
	M = M.duplicate(true)
	for r in range(n):
		var row: Array = M[r]
		for cc in range(row.size()):
			row[cc] = floorf(float(row[cc]) * 1e6 + 0.5) / 1e6
	var m: int = (M[0] as Array).size()
	if m == 0:
		return _uniform(n)

	var reg_r := _zeros(n)   # row player's cumulative regret per move
	var reg_c := _zeros(m)   # column player's cumulative regret per move
	var sum_r := _zeros(n)   # accumulated row strategy (its time-average is the answer)

	for _t in range(iters):
		var sr := _strategy(reg_r)          # current row mix from positive regrets
		var sc := _strategy(reg_c)          # current column mix

		# Row payoff for each pure row vs the column's current mix; accrue regret.
		var ur := _zeros(n)
		for i in n:
			var s := 0.0
			for j in m:
				s += float(M[i][j]) * float(sc[j])
			ur[i] = s
		var evr := 0.0
		for i in n:
			evr += float(sr[i]) * float(ur[i])
		for i in n:
			reg_r[i] = float(reg_r[i]) + float(ur[i]) - evr

		# Column minimises M (its payoff is -M); same regret update on its side.
		var uc := _zeros(m)
		for j in m:
			var s2 := 0.0
			for i in n:
				s2 += -float(M[i][j]) * float(sr[i])
			uc[j] = s2
		var evc := 0.0
		for j in m:
			evc += float(sc[j]) * float(uc[j])
		for j in m:
			reg_c[j] = float(reg_c[j]) + float(uc[j]) - evc

		for i in n:
			sum_r[i] = float(sum_r[i]) + float(sr[i])

	return _normalize(sum_r)

# Row player's guaranteed (maximin) value when committing to `row_mix`: the column
# player best-responds, so it is the worst column. Used to value a solved subgame.
static func value_of(M: Array, row_mix: Array) -> float:
	var n := M.size()
	if n == 0:
		return 0.0
	var m: int = (M[0] as Array).size()
	if m == 0:
		return 0.0
	var worst := INF
	for j in m:
		var cv := 0.0
		for i in n:
			cv += float(row_mix[i]) * float(M[i][j])
		worst = minf(worst, cv)
	return worst

# Regret matching: play proportional to positive cumulative regret (uniform until
# some regret is positive).
static func _strategy(regret: Array) -> Array:
	var n := regret.size()
	var pos := _zeros(n)
	var tot := 0.0
	for i in n:
		pos[i] = maxf(0.0, float(regret[i]))
		tot += float(pos[i])
	if tot <= 0.0:
		return _uniform(n)
	for i in n:
		pos[i] = float(pos[i]) / tot
	return pos

static func _normalize(v: Array) -> Array:
	var tot := 0.0
	for x in v:
		tot += float(x)
	if tot <= 0.0:
		return _uniform(v.size())
	var out: Array = []
	for x in v:
		out.append(float(x) / tot)
	return out

static func _uniform(n: int) -> Array:
	var out: Array = []
	var p := (1.0 / float(n)) if n > 0 else 0.0
	for _i in n:
		out.append(p)
	return out

static func _zeros(n: int) -> Array:
	var out: Array = []
	for _i in n:
		out.append(0.0)
	return out
