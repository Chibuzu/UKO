# BrainAgreement.gd -- BRAIN-PORT VERIFICATION: the two brains (GDScript vs C#) are
# compared NUMERICALLY on frozen positions. Everything up to the final random sample
# is deterministic, so this is near-exact, not statistical:
#   1. CANDIDATES  : serialized candidate lists must match 1:1 (order included)
#   2. SCORE_RICH  : per-cell shallow scores, |delta| < 1e-6
#   3. SCORE_DEEP  : depth-1 subgame-valued scores (caches cleared), |delta| < 1e-6
#   4. NASH        : mixes on shared matrices, |delta| < 1e-9
#   5. FULL VALUE  : the whole ExtremeAI pipeline (unlimited budget, no opp model,
#                    no sampling). Nash equilibria are DISCONTINUOUS in payoffs, so
#                    sub-1e-6 eval drift can select different-but-equivalent
#                    equilibria ("twins") -- raw mixes may differ while both are
#                    correct. The invariant twins share is the GUARANTEED VALUE
#                    (min over foe columns of mixᵀM): compare THAT, |delta| < 1e-3.
#                    Per-index mix deltas are printed as info, never failed.
# Run: run_brain_agreement.bat
extends SceneTree

const FULL_GEAR := ["discount_charm", "burst_node", "blink_boots", "dark_focus"]
var _fails := 0
var _checks := 0

func _chk(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: %s %s" % [name, detail])

func _init() -> void:
	print("[harness] v5 -- v4 + deep-cell probe on the exact deepened cells")
	# ── ENVIRONMENT SELF-CHECK: refuse to run against stale files. Tonight proved
	# that a silent old file wastes an hour; now the harness names the culprit.
	var env_ok := true
	env_ok = _need("res://Scripts/AI/ExtremeAI.gd", "_rq(") and env_ok
	env_ok = _need("res://Scripts/Port/CSharp/Brain/ExtremeAI.cs", "Rq(") and env_ok
	env_ok = _need("res://Scripts/AI/NashSolver.gd", "1e6") and env_ok
	env_ok = _need("res://Scripts/Port/CSharp/Brain/NashSolver.cs", "1e6") and env_ok
	env_ok = _need("res://Scripts/Port/CSharp/BrainBridge.cs", "GuaranteedValue") and env_ok
	if not env_ok:
		print("[harness] STALE FILES DETECTED -- replace the file(s) named above, rebuild, rerun.")
		quit(1)
		return
	print("[harness] environment OK: all tonight's files are in place.")
	var bridge = load("res://Scripts/Port/CSharp/BrainBridge.cs").new()
	bridge.SetProfile("extreme")
	bridge.SetCal(0.0)                # defensive: pin calibration to 0 on the C# side too
	Eval.set_weights(Eval.DEFAULTS)   # mirror what SetProfile does on the C# side
	Eval.CAL_A = 0.0                  # calibration off on BOTH sides for exactness
	print("[env] CAL_A pinned to 0 on both sides (gd=%.3f)" % Eval.CAL_A)

	var positions := _positions()
	for pi in range(positions.size()):
		print("[agreement] position %d / %d ..." % [pi + 1, positions.size()])
		var P: Dictionary = positions[pi]
		var g: Grid = P["grid"]
		var me: Combatant = P["me"]
		var foe: Combatant = P["foe"]
		var rows := _rows_of(g.blocked)
		var brows := _rows_of(g.base_blocked)

		# 1) candidates
		var gd_c := AIToolkit.candidates(me, foe, g)
		var gd_ser: Array = []
		for s in gd_c:
			gd_ser.append(_seq_str(s))
		var cs_ser: Array = Array(bridge.CandidatesOf(rows, brows, g.rot_step, g.shrink_level, _cd(me), _cd(foe)))
		_chk("pos%d candidates count" % pi, gd_ser.size() == cs_ser.size(), "%d vs %d" % [gd_ser.size(), cs_ser.size()])
		var n := mini(gd_ser.size(), cs_ser.size())
		for i in range(n):
			if gd_ser[i] != cs_ser[i]:
				_chk("pos%d candidate %d" % [pi, i], false, "%s vs %s" % [gd_ser[i], cs_ser[i]])
				break

		# 2) score_rich on a spread of cells
		var foe_c := AIToolkit.candidates(foe, me, g)
		var pairs := mini(6, mini(gd_c.size(), foe_c.size()))
		for i in range(pairs):
			for j in range(pairs):
				var gd_s := Eval.score_rich(me, foe, g, gd_c[i], foe_c[j])
				var cs_s: float = bridge.ScoreRich(rows, brows, g.rot_step, g.shrink_level, _cd(me), _cd(foe), gd_c[i], foe_c[j])
				_chk("pos%d rich[%d,%d]" % [pi, i, j], absf(gd_s - cs_s) < 1e-6, "%.9f vs %.9f" % [gd_s, cs_s])

		# 3) score_deep leaf 1, a few cells (clear caches both sides)
		for i in range(mini(2, gd_c.size())):
			for j in range(mini(2, foe_c.size())):
				Eval.clear_cache()
				var gd_d := Eval.score_deep(me, foe, g, gd_c[i], foe_c[j], 1)
				var cs_d: float = bridge.ScoreDeep(rows, brows, g.rot_step, g.shrink_level, _cd(me), _cd(foe), gd_c[i], foe_c[j], 1)
				_chk("pos%d deep[%d,%d]" % [pi, i, j], absf(gd_d - cs_d) < 1e-6, "%.9f vs %.9f" % [gd_d, cs_d])

		# 4) Nash mixes on the shallow matrix
		var M: Array = []
		for i in range(mini(5, gd_c.size())):
			var row: Array = []
			for j in range(mini(5, foe_c.size())):
				row.append(Eval.score_rich(me, foe, g, gd_c[i], foe_c[j]))
			M.append(row)
		var gd_mix := NashSolver.solve(M)
		var cs_mix: Array = Array(bridge.SolveMatrix(M, 0))
		for i in range(gd_mix.size()):
			_chk("pos%d nash[%d]" % [pi, i], absf(float(gd_mix[i]) - float(cs_mix[i])) < 1e-9, "%.12f vs %.12f" % [float(gd_mix[i]), float(cs_mix[i])])

		# 5) full deterministic pipeline
		var gd_full := _gd_choose_mix(me, foe, g)
		var cs_full: Dictionary = bridge.ChooseMixDet(rows, brows, g.rot_step, g.shrink_level, _cd(me), _cd(foe))
		var cs_cands: Array = Array(cs_full["cands"])
		var cs_m: Array = Array(cs_full["mix"])
		_chk("pos%d full cand count" % pi, gd_full["cands"].size() == cs_cands.size(), "%d vs %d" % [gd_full["cands"].size(), cs_cands.size()])
		if gd_full["cands"].size() == cs_cands.size():
			for i in range(cs_cands.size()):
				if String(gd_full["cands"][i]) != String(cs_cands[i]):
					_chk("pos%d full cand %d" % [pi, i], false, "%s vs %s" % [gd_full["cands"][i], cs_cands[i]])
					break
			# Equilibrium twins: mixes may legally differ index-by-index. INFO only.
			var max_d := 0.0
			for i in range(cs_m.size()):
				max_d = maxf(max_d, absf(float(gd_full["mix"][i]) - float(cs_m[i])))
			if max_d > 1e-6:
				print("  [info] pos%d mix max-delta %.6f (equilibrium selection; value is the invariant)" % [pi, max_d])
			var v_ok := absf(float(gd_full["value"]) - float(cs_full["value"])) < 1e-3
			_chk("pos%d full VALUE" % pi, v_ok,
					"%.6f vs %.6f" % [float(gd_full["value"]), float(cs_full["value"])])
			if not v_ok:
				# ── DIVERGENCE HUNT: scan EVERY rich cell GD-vs-C# and name the
				# exact candidate pairs where the engines disagree. Slow (once).
				print("  [hunt] scanning full rich matrix for pos%d ... (~1-2 min)" % pi)
				var hg := AIToolkit.candidates(me, foe, g)
				var hf := AIToolkit.candidates(foe, me, g)
				var worst: Array = []
				for hi in range(hg.size()):
					for hj in range(hf.size()):
						var a_gd := Eval.score_rich(me, foe, g, hg[hi], hf[hj])
						var a_cs: float = bridge.ScoreRich(rows, brows, g.rot_step, g.shrink_level, _cd(me), _cd(foe), hg[hi], hf[hj])
						var dd := absf(a_gd - a_cs)
						if dd > 1e-4:
							worst.append({"d": dd, "i": hi, "j": hj, "gd": a_gd, "cs": a_cs})
				worst.sort_custom(func(x, y): return float(x["d"]) > float(y["d"]))
				print("  [hunt] rich: %d divergent cell(s) > 1e-4" % worst.size())
				for w in range(mini(6, worst.size())):
					var W: Dictionary = worst[w]
					print("  [hunt] rich cell(%d,%d) gd=%.6f cs=%.6f  Δ=%.6f" % [int(W["i"]), int(W["j"]), float(W["gd"]), float(W["cs"]), float(W["d"])])
					print("         me : %s" % _seq_str(hg[int(W["i"])]))
					print("         foe: %s" % _seq_str(hf[int(W["j"])]))
				# ── DEEP-CELL PROBE: compare score_deep on the EXACT cells the
				# pipeline deepens (rich already proven identical everywhere).
				var hM: Array = []
				for hi2 in range(hg.size()):
					var hrow: Array = []
					for hj2 in range(hf.size()):
						hrow.append(Eval.score_rich(me, foe, g, hg[hi2], hf[hj2]))
					hM.append(hrow)
				var p_rows := int(ExtremeAI.P["rows_end"]) if g.shrink_level >= 2 else int(ExtremeAI.P["rows"])
				var p_cols := int(ExtremeAI.P["cols_end"]) if g.shrink_level >= 2 else int(ExtremeAI.P["cols"])
				var p_leaf := Eval.LOOKAHEAD_DEPTH - 1
				if g.shrink_level >= 3:
					p_leaf = Eval.LOOKAHEAD_DEPTH
				var deep_bad := 0
				for di in ExtremeAI._top_rows(hM, p_rows):
					for dj in ExtremeAI._worst_cols(hM[di], p_cols):
						Eval.clear_cache()
						var g_d := Eval.score_deep(me, foe, g, hg[di], hf[dj], p_leaf)
						var c_d: float = bridge.ScoreDeep(rows, brows, g.rot_step, g.shrink_level, _cd(me), _cd(foe), hg[di], hf[dj], p_leaf)
						if absf(g_d - c_d) > 1e-4:
							deep_bad += 1
							if deep_bad <= 6:
								print("  [hunt] DEEP cell(%d,%d) gd=%.6f cs=%.6f  Δ=%.6f" % [di, dj, g_d, c_d, absf(g_d - c_d)])
								print("         me : %s" % _seq_str(hg[di]))
								print("         foe: %s" % _seq_str(hf[dj]))
				print("  [hunt] deep: %d divergent deepened cell(s) > 1e-4" % deep_bad)
				if deep_bad == 0:
					print("  [hunt] rich AND deep agree on all pipeline cells -> divergence is POST-matrix (dominance/solve/prune/value) -- report this line.")

	print("")
	if _fails == 0:
		print("[agreement] ALL %d CHECKS PASS -- the C# brain agrees with the GDScript brain." % _checks)
	else:
		print("[agreement] %d / %d checks FAILED." % [_fails, _checks])
	quit(0 if _fails == 0 else 1)

func _need(path: String, marker: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("[env] MISSING FILE: %s" % path)
		return false
	var ok := f.get_as_text().contains(marker)
	f.close()
	if not ok:
		print("[env] STALE: %s is an OLD version (marker '%s' not found) -- replace it." % [path, marker])
	else:
		print("[env] ok: %s" % path)
	return ok

# GDScript mirror of ExtremeAI.choose_sequence: unlimited budget, no opp model, no
# sampling -- uses ExtremeAI's own statics so the pipeline is the real one.
func _gd_choose_mix(me: Combatant, foe: Combatant, grid: Grid) -> Dictionary:
	var my_cands: Array = ExtremeAI._clean(AIToolkit.candidates(me, foe, grid))
	var foe_cands: Array = ExtremeAI._clean(AIToolkit.candidates(foe, me, grid))
	if my_cands.is_empty():
		return {"cands": [_seq_str([{"id": "rest"}])], "mix": [1.0]}
	if foe_cands.is_empty():
		foe_cands = [[{"id": "rest"}]]
	Eval.clear_cache()
	var M: Array = []
	for ms in my_cands:
		var row: Array = []
		for fs in foe_cands:
			row.append(Eval.score_rich(me, foe, grid, ms, fs))
		M.append(row)
	if Eval.LOOKAHEAD_DEPTH >= 2:
		var deep_rows := int(ExtremeAI.P["rows_end"]) if grid.shrink_level >= 2 else int(ExtremeAI.P["rows"])
		print("  [gd] deep rows pick: %s" % str(ExtremeAI._top_rows(M, deep_rows)))
		var deep_cols := int(ExtremeAI.P["cols_end"]) if grid.shrink_level >= 2 else int(ExtremeAI.P["cols"])
		var leaf := Eval.LOOKAHEAD_DEPTH - 1
		if grid.shrink_level >= 3:
			leaf = Eval.LOOKAHEAD_DEPTH
		var done := {}
		for i in ExtremeAI._top_rows(M, deep_rows):
			for j in ExtremeAI._worst_cols(M[i], deep_cols):
				M[i][j] = Eval.score_deep(me, foe, grid, my_cands[i], foe_cands[j], leaf)
				done["%d,%d" % [i, j]] = true
		# budget-0 semantics: NO budgeted extension (mirrors ChooseMixDet's budget 0)
	# CAL_A forced 0 -> no winprob map
	var dom := ExtremeAI._dominance_filter(M)
	var mix: Array = ExtremeAI._expand(NashSolver.solve(ExtremeAI._submatrix(M, dom["rows"], dom["cols"])), dom["rows"], my_cands.size())
	# budget-0 semantics: depth-3 refine is time-gated -> skipped
	mix = ExtremeAI._prune_support(mix, ExtremeAI.MIN_MIX)
	# Guaranteed value: the floor this mix secures against any foe column.
	var gv := INF
	for j in range(foe_cands.size()):
		var col := 0.0
		for i in range(my_cands.size()):
			col += float(mix[i]) * float(M[i][j])
		gv = minf(gv, col)
	var ser: Array = []
	for c in my_cands:
		ser.append(_seq_str(c))
	return {"cands": ser, "mix": mix, "value": gv}

# ── fixtures ──────────────────────────────────────────────────────────────
func _positions() -> Array:
	var out: Array = []
	# adjacent duel, full resources
	out.append(_pos(Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100, Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100, [], 0, 0))
	# spaced, mid-game resources
	out.append(_pos(Vector2i(2, 4), Config.Facing.EAST, 80, 70, 60, Vector2i(5, 4), Config.Facing.WEST, 75, 60, 55, [], 0, 0))
	# PRESS-STARVING shape: foe one action from lockout, me healthy at dist 2
	out.append(_pos(Vector2i(2, 4), Config.Facing.EAST, 90, 80, 80, Vector2i(4, 4), Config.Facing.WEST, 60, 40, 15, [], 0, 0))
	# walls + a cooldown + spent grenade
	var p4 := _pos(Vector2i(2, 3), Config.Facing.SOUTH, 55, 30, 45, Vector2i(5, 5), Config.Facing.NORTH, 70, 90, 70,
		["........", "..#.....", "........", "....#...", "........", "......#.", "........", "........"], 1, 0)
	(p4["me"] as Combatant).cooldowns["dark_bolt"] = 2
	(p4["foe"] as Combatant).spent_once["grenade"] = true
	out.append(p4)
	# endgame: shrink 2 (deep look widens), low hp both
	out.append(_pos(Vector2i(3, 3), Config.Facing.EAST, 35, 50, 60, Vector2i(4, 4), Config.Facing.WEST, 30, 40, 50, [], 2, 2))
	return out

func _pos(mp: Vector2i, mf: int, mhp: int, mmp: int, men: int,
		fp: Vector2i, ff: int, fhp: int, fmp: int, fen: int,
		wall_rows: Array, rot: int, shrink: int) -> Dictionary:
	var g := Grid.new()
	if not wall_rows.is_empty():
		var m: Array = []
		for y in range(Grid.SIZE):
			var row: Array = []
			var line: String = wall_rows[y] if y < wall_rows.size() else ""
			for x in range(Grid.SIZE):
				row.append(x < line.length() and line[x] == "#")
			m.append(row)
		g.blocked = m
	g.base_blocked = g.blocked.duplicate(true)
	g.rot_step = rot
	g.shrink_level = shrink
	if shrink > 0:
		for y in range(Grid.SIZE):
			for x in range(Grid.SIZE):
				if mini(mini(x, y), mini(Grid.SIZE - 1 - x, Grid.SIZE - 1 - y)) < shrink:
					g.blocked[y][x] = true
	var me := Combatant.new("A", mp, mf)
	me.equip(FULL_GEAR)
	me.hp = mhp
	me.mp = mmp
	me.energy = men
	var foe := Combatant.new("B", fp, ff)
	foe.equip(FULL_GEAR)
	foe.hp = fhp
	foe.mp = fmp
	foe.energy = fen
	return {"grid": g, "me": me, "foe": foe}

# ── helpers (formats shared with the C# side) ────────────────────────────
func _rows_of(blocked: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in range(Grid.SIZE):
		var s := ""
		for x in range(Grid.SIZE):
			s += "#" if blocked[y][x] else "."
		rows.append(s)
	return rows

func _cd(c: Combatant) -> Dictionary:
	return c.to_bridge_dict()   # the ONE marshal contract lives on Combatant

func _seq_str(seq: Array) -> String:
	var parts: Array = []
	for a in seq:
		var s := String(a.get("id", ""))
		if a.has("tile"):
			var t: Vector2i = a["tile"]
			s += "@%d.%d" % [t.x, t.y]
		if a.has("facing"):
			s += "^%d" % int(a["facing"])
		parts.append(s)
	return "+".join(parts)
