# FitValue.gd -- fits the LEARNED VALUE FUNCTION on the self-play harvest.
# Run via run_fit_value.bat (headless; no C# build needed). Reads
# user://selfplay_v3.csv (28 autopsy features + outcome per turn/seat), fits a
# logistic regression p(win|state) by full-batch gradient descent on
# standardized features, reports fit quality, and writes THE CHALLENGER:
# user://value_fn_new.cfg. The live judge stays user://value_fn.cfg -- a new fit
# NEVER goes live by being fitted; it must first WIN run_value_arena.bat
# (champion vs challenger) and keep the position gates green, then
# run_promote_value.bat copies new -> live. Deterministic: fixed epochs, fixed
# learning rate, no shuffling.
#
# v3 (ROUND 10): CROSSED FEATURES. The linear model could learn "more hp good"
# but not "low energy only matters when ADJACENT" -- interactions were invisible
# by construction. The fitter now appends hand-chosen feature PRODUCTS (list
# below) to the 28 base columns. The pair list is written INTO the cfg, so
# inference (Eval.gd learned_p / Eval.cs LearnedP) replays whatever this file
# chose -- change the list here, and only here. The harvest CSV is untouched:
# crosses are derived from base columns at fit/inference time.
# Also v3: an 80/20 train/validation split by match seed -- train accuracy on
# its own flatters the fit; the VAL number is the honest one.
extends SceneTree

const CSV := "user://selfplay_v3.csv"   # ROUND 11 rules era: pivot tax + drain-cancel (v2 rows are the old game)
const OUT := "user://value_fn_new.cfg"
const N_BASE := 28
const EPOCHS := 400
const LR := 1.0          # stable for standardized features with a mean gradient
const VAL_FRACTION := 0.2   # last 20% of match seeds held out for validation
const FEATURE_NAMES := ["hp", "mp", "energy", "foe_hp", "foe_mp", "foe_energy",
	"dist", "shrink", "my_ac", "foe_ac", "my_nade", "foe_nade", "my_flank", "foe_flank",
	"my_to_pulse", "foe_to_pulse", "my_locked", "foe_locked", "my_noguard", "foe_noguard",
	"my_rest_ready", "foe_rest_ready", "my_cd_burst", "my_cd_bolt", "foe_cd_burst",
	"foe_cd_bolt", "my_cc", "foe_cc"]

# The interactions the duel actually runs on: resources x distance (a bolt in
# hand means nothing at range 5; an empty tank means nothing at range 5 either),
# hp fronts (whose health bar the fight is being played on), lockout x proximity,
# and curvature (squares) for the three nonlinear axes.
const CROSSES: Array = [
	[0, 6], [3, 6],      # hp x dist, foe_hp x dist
	[2, 6], [5, 6],      # energy x dist, foe_energy x dist
	[1, 6], [4, 6],      # mp x dist, foe_mp x dist
	[0, 3],              # hp x foe_hp
	[0, 7], [3, 7],      # hp x shrink, foe_hp x shrink (the closing zone reprices health)
	[16, 6], [17, 6],    # locked x dist (a locked foe is only safe from far away)
	[18, 5], [19, 2],    # my_noguard x foe_energy, foe_noguard x energy (unanswerable melee)
	[20, 6], [21, 6],    # rest_ready x dist (the rest doorway needs space)
	[26, 6], [27, 6],    # crowd-control x dist (a rooted fighter's distance is frozen)
	[0, 4], [3, 1],      # hp x foe_mp, foe_hp x mp (spell pressure against each bar)
	[6, 6], [0, 0], [3, 3],   # dist^2, hp^2, foe_hp^2 (curvature)
]

func _init() -> void:
	print("[fit] reading %s ..." % CSV)
	var f := FileAccess.open(CSV, FileAccess.READ)
	if f == null:
		print("[fit] ERROR: %s not found -- run the harvest night first (run_harvest.bat)." % CSV)
		quit(1)
		return
	var xs: Array = []
	var ys: Array = []
	var seeds: Array = []
	var draws := 0
	var bad := 0
	var first := true
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		if first:
			first = false
			if not line.begins_with("seed"):
				bad += 1   # no header? treat the line as data below on the next pass
			else:
				continue
		var c := line.split(",")
		if c.size() != N_BASE + 4:      # seed, turn, seat + 28 features + outcome
			bad += 1
			continue
		var z := int(c[c.size() - 1])
		if z == 0:
			draws += 1                  # draws carry no win signal for a logistic; skipped
			continue
		var row: Array = []
		for i in range(3, 3 + N_BASE):
			row.append(float(c[i]))
		# Append the crossed features (raw products; standardized below like any column).
		for cr in CROSSES:
			row.append(float(row[int(cr[0])]) * float(row[int(cr[1])]))
		xs.append(row)
		ys.append(1.0 if z > 0 else 0.0)
		seeds.append(int(c[0]))
	f.close()
	var n_feat := N_BASE + CROSSES.size()
	var n := xs.size()
	print("[fit] %d rows, %d features (28 base + %d crosses) (skipped %d draw rows, %d malformed)" %
			[n, n_feat, CROSSES.size(), draws, bad])
	if n < 500:
		print("[fit] ERROR: not enough data to fit -- need a harvest night.")
		quit(1)
		return

	# Train/validation split BY MATCH (seed), not by row: rows within a match are
	# heavily correlated, so a row-level split would leak the outcome into "val".
	var uniq := {}
	for s in seeds:
		uniq[s] = true
	var seed_list := uniq.keys()
	seed_list.sort()
	var n_val_seeds := int(float(seed_list.size()) * VAL_FRACTION)
	var val_set := {}
	for k in range(seed_list.size() - n_val_seeds, seed_list.size()):
		val_set[seed_list[k]] = true
	var tr_idx: Array = []
	var va_idx: Array = []
	for i in n:
		if val_set.has(seeds[i]):
			va_idx.append(i)
		else:
			tr_idx.append(i)
	print("[fit] split: %d train rows (%d matches) / %d val rows (%d matches)" %
			[tr_idx.size(), seed_list.size() - n_val_seeds, va_idx.size(), n_val_seeds])

	# Standardize on TRAIN statistics (the cfg stores mean/std so inference
	# reproduces this exactly; val uses train's numbers, as inference will).
	var mean: Array = []
	var std: Array = []
	for j in n_feat:
		var m := 0.0
		for i in tr_idx:
			m += float(xs[i][j])
		m /= float(tr_idx.size())
		var v := 0.0
		for i in tr_idx:
			var d: float = float(xs[i][j]) - m
			v += d * d
		mean.append(m)
		std.append(sqrt(v / float(tr_idx.size())))
	for i in n:
		for j in n_feat:
			var sd: float = float(std[j])
			xs[i][j] = (float(xs[i][j]) - float(mean[j])) / (sd if sd > 0.0 else 1.0)

	# Full-batch logistic regression on TRAIN: w[0..n_feat-1] features, w[n_feat] bias.
	var w: Array = []
	for _j in n_feat + 1:
		w.append(0.0)
	var ntr := tr_idx.size()
	for epoch in EPOCHS:
		var grad: Array = []
		for _j in n_feat + 1:
			grad.append(0.0)
		var loss := 0.0
		var correct := 0
		for i in tr_idx:
			var z2: float = float(w[n_feat])
			for j in n_feat:
				z2 += float(w[j]) * float(xs[i][j])
			var p := 1.0 / (1.0 + exp(-z2))
			var y: float = float(ys[i])
			loss += -(y * log(maxf(p, 1e-12)) + (1.0 - y) * log(maxf(1.0 - p, 1e-12)))
			if (p >= 0.5) == (y >= 0.5):
				correct += 1
			var err := p - y
			for j in n_feat:
				grad[j] = float(grad[j]) + err * float(xs[i][j])
			grad[n_feat] = float(grad[n_feat]) + err
		for j in n_feat + 1:
			w[j] = float(w[j]) - LR * float(grad[j]) / float(ntr)
		if (epoch + 1) % 50 == 0:
			print("[fit] epoch %d  train log-loss %.4f  acc %.1f%%" %
					[epoch + 1, loss / float(ntr), 100.0 * float(correct) / float(ntr)])

	# Honest quality: the held-out validation matches.
	var va_loss := 0.0
	var va_correct := 0
	for i in va_idx:
		var z3: float = float(w[n_feat])
		for j in n_feat:
			z3 += float(w[j]) * float(xs[i][j])
		var p2 := 1.0 / (1.0 + exp(-z3))
		va_loss += -(float(ys[i]) * log(maxf(p2, 1e-12)) + (1.0 - float(ys[i])) * log(maxf(1.0 - p2, 1e-12)))
		if (p2 >= 0.5) == (float(ys[i]) >= 0.5):
			va_correct += 1
	var acc := 100.0 * float(va_correct) / maxf(1.0, float(va_idx.size()))
	print("[fit] FINAL  VALIDATION log-loss %.4f  accuracy %.1f%%  (coin flip = 50%%)" %
			[va_loss / maxf(1.0, float(va_idx.size())), acc])

	# The story the weights tell (top influences, for sanity).
	var ranked: Array = []
	for j in n_feat:
		var nm: String
		if j < N_BASE:
			nm = FEATURE_NAMES[j]
		else:
			var cr: Array = CROSSES[j - N_BASE]
			nm = "%s*%s" % [FEATURE_NAMES[int(cr[0])], FEATURE_NAMES[int(cr[1])]]
		ranked.append({"n": nm, "w": float(w[j])})
	ranked.sort_custom(func(a, b): return absf(float(a["w"])) > absf(float(b["w"])))
	print("[fit] strongest signals (standardized weights):")
	for k in mini(10, ranked.size()):
		print("      %-24s %+.3f" % [ranked[k]["n"], float(ranked[k]["w"])])

	var cf := ConfigFile.new()
	cf.set_value("value", "w", w)
	cf.set_value("value", "mean", mean)
	cf.set_value("value", "std", std)
	cf.set_value("value", "crosses", CROSSES)
	cf.set_value("value", "n", n)
	cf.set_value("value", "acc", acc)
	cf.set_value("value", "names", FEATURE_NAMES)
	cf.save(OUT)
	print("[fit] wrote %s (the CHALLENGER) -- next: run_value_arena.bat (champion vs challenger)." % OUT)
	print("[fit] it goes live ONLY via run_promote_value.bat after winning the arena + gates.")
	quit(0)
