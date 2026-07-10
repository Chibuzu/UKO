# EconomyAI.gd
# The remodelled top brain (remodel step #4 -- the orchestrator). One turn:
#
#   1. classify INTENT from the resource differential (IntentSelector)
#   2. generate a small, diverse, intent-aligned PLAN set for me AND the foe
#      (PlanGenerator -- pruned so the mix spreads only over good moves)
#   3. score every (my plan x foe plan) cell in the resource ECONOMY by rolling
#      it through the real Resolver (EconomyEval), with depth-2 lookahead on the
#      rows worth considering (the "trace optimal paths" step)
#   4. solve that matrix for the unexploitable mixed strategy (NashSolver)
#   5. sample a plan from the mix
#
# This is the brain that makes the AI ACT on the new principles. It owns only the
# SELECTION rule; every piece it calls is a standalone, gear-generic module, so a
# new spell or gear flows through (intent reads resources, plans read role tags,
# the evaluator reads the Resolver) with no changes here.
#
# Pure Nash by default (EXPLOIT_LAMBDA = 0): the sharpness comes from PRUNING to
# good plans, not from randomness -- a bolt with the foe in range is a high-value
# row, so the equilibrium loads onto it. The optional exploitation lean is left
# wired but off; turn it up to punish a predictable human while keeping the
# equilibrium floor underneath.
class_name EconomyAI
extends RefCounted

const ROOT_ROWS := 4       # rows (my plans) to deepen with the 2-turn lookahead
const ROOT_COLS := 3       # foe replies per deepened row to look at (its best answers)
const EXPLOIT_LAMBDA := 0.0  # 0 = pure Nash. >0 tilts toward the foe's observed habits (bounded)
const EXPLOIT_TEMP := 8.0    # softmax temperature for the exploit tilt
const DEBUG_LOG := false     # TEMPORARY diag; OFF (would flood overnight self-play logs)

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array, opp_model = null) -> Array:
	# 1. Strategic intent for MY plans, from the resource economy.
	var my_intent := IntentSelector.classify(me, foe)

	# 2. Columns = the foe's most THREATENING replies (broad, not intent-pruned), so
	#    I'm never blind to a closing attack or flank. Computed ONCE and reused as
	#    both the matrix columns and the yardstick my own plans are ranked against.
	var foe_plans: Array = PlanGenerator.threat_columns(foe, me, grid)
	var my_plans: Array = PlanGenerator.plans(me, foe, grid, my_intent, foe_plans)
	if my_plans.is_empty():
		return [{"id": "rest"}]
	if foe_plans.is_empty():
		foe_plans = [[{"id": "rest"}]]

	# 3. Payoff matrix: my economy value for (my plan i vs foe plan j), shallow first.
	var M: Array = []
	for mp in my_plans:
		var row: Array = []
		for fp in foe_plans:
			row.append(EconomyEval.score_rich(me, foe, grid, mp, fp))
		M.append(row)

	# Selective deepening: only the rows I'd actually consider get the 2-turn read,
	# against the foe's best answers -- avoids the matrix-of-matrices blow-up.
	if EconomyEval.LOOKAHEAD_DEPTH >= 2:
		for i in _top_rows(M, ROOT_ROWS):
			for j in _worst_cols(M[i], ROOT_COLS):
				M[i][j] = EconomyEval.score_deep(me, foe, grid, my_plans[i], foe_plans[j], EconomyEval.LOOKAHEAD_DEPTH - 1)

	# 4. Unexploitable equilibrium mix over my plans.
	var mix: Array = NashSolver.solve(M)

	# Optional bounded exploitation (off by default): tilt toward punishing the
	# foe's observed habits, keeping the equilibrium underneath.
	if opp_model != null and EXPLOIT_LAMBDA > 0.0 and opp_model.is_warm():
		var q: Array = _predict(opp_model, foe_plans)
		var ev: Array = []
		for i in my_plans.size():
			var e := 0.0
			for j in foe_plans.size():
				e += float(M[i][j]) * float(q[j])
			ev.append(e)
		var exploit: Array = _softmax(ev, EXPLOIT_TEMP)
		for i in mix.size():
			mix[i] = (1.0 - EXPLOIT_LAMBDA) * float(mix[i]) + EXPLOIT_LAMBDA * float(exploit[i])

	# 5. Sample a plan from the mix.
	var idx := _sample(mix)
	if DEBUG_LOG:
		_log_decision(my_intent, my_plans, foe_plans, M, mix, idx)
	return my_plans[idx]

# ── diagnostics (TEMPORARY) ────────────────────────────────────────────────
# Compact one-line view of a sequence, e.g. "[blink(4,5), attack(5,5)]".
static func _seq_str(seq: Array) -> String:
	var parts: Array = []
	for a in seq:
		var s := String(a.get("id", "?"))
		if a.has("tile"):
			s += str(a["tile"])
		parts.append(s)
	return "[" + ", ".join(parts) + "]"

# Dump the foe columns, my plans with their Nash weight, the payoff matrix, and the
# choice -- so we can SEE on a guard turn whether the bolt column was present and
# whether the lateral dodge survived pruning.
static func _log_decision(intent: String, my_plans: Array, foe_plans: Array, M: Array, mix: Array, idx: int) -> void:
	print("[EconomyAI] intent=", intent)
	print("  FOE COLUMNS:")
	for j in foe_plans.size():
		print("    c", j, " ", _seq_str(foe_plans[j]))
	print("  MY PLANS (p = Nash mix | cells = value vs each column):")
	for i in my_plans.size():
		var row := ""
		for j in M[i].size():
			row += "%8.1f" % float(M[i][j])
		var p := float(mix[i]) if i < mix.size() else 0.0
		var mark := "  <== CHOSEN" if i == idx else ""
		print("    r", i, " p=", "%.2f" % p, "  ", PlanGenerator.plan_role(my_plans[i]), " ", _seq_str(my_plans[i]), " |", row, mark)

# ── matrix helpers (self-contained; small + pure) ──────────────────────────
# Rows with the best WORST-CASE value -- the plans worth a deep look.
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

# The k columns where the foe hurts me most in a row -- its best replies to deepen.
static func _worst_cols(row: Array, k: int) -> Array:
	var cols: Array = []
	for j in row.size():
		cols.append({"j": j, "v": float(row[j])})
	cols.sort_custom(func(x, y): return float(x["v"]) < float(y["v"]))
	var out: Array = []
	for n in range(mini(k, cols.size())):
		out.append(int(cols[n]["j"]))
	return out

# Predicted foe-reply distribution from observed tendencies (normalized).
static func _predict(opp_model, foe_plans: Array) -> Array:
	var w: Array = []
	var tot := 0.0
	for fp in foe_plans:
		var x: float = opp_model.weight_of(fp)
		w.append(x)
		tot += x
	if tot <= 0.0:
		return _uniform(foe_plans.size())
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
