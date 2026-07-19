# FitValue.gd -- fits the LEARNED VALUE FUNCTION on the self-play harvest.
# Run via run_fit_value.bat (headless; no C# build needed). Reads
# user://selfplay_v2.csv (450 new-physics matches, 28 autopsy features + outcome),
# fits a logistic regression p(win|state) by full-batch gradient descent on
# standardized features, reports fit quality, and writes user://value_fn.cfg --
# which BrainBridge.LoadValueFn() / Eval.load_value_fn() read. The learned judge
# stays OFF in live play until it wins run_value_arena.bat + the position gates.
# Deterministic: fixed epochs, fixed learning rate, no shuffling.
extends SceneTree

const CSV := "user://selfplay_v2.csv"
const OUT := "user://value_fn.cfg"
const N_FEAT := 28
const EPOCHS := 400
const LR := 1.0          # stable for standardized features with a mean gradient
const FEATURE_NAMES := ["hp", "mp", "energy", "foe_hp", "foe_mp", "foe_energy",
	"dist", "shrink", "my_ac", "foe_ac", "my_nade", "foe_nade", "my_flank", "foe_flank",
	"my_to_pulse", "foe_to_pulse", "my_locked", "foe_locked", "my_noguard", "foe_noguard",
	"my_rest_ready", "foe_rest_ready", "my_cd_burst", "my_cd_bolt", "foe_cd_burst",
	"foe_cd_bolt", "my_cc", "foe_cc"]

func _init() -> void:
	print("[fit] reading %s ..." % CSV)
	var f := FileAccess.open(CSV, FileAccess.READ)
	if f == null:
		print("[fit] ERROR: %s not found -- run the harvest night first (run_harvest.bat)." % CSV)
		quit(1)
		return
	var xs: Array = []
	var ys: Array = []
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
		if c.size() != N_FEAT + 4:      # seed, turn, seat + 28 features + outcome
			bad += 1
			continue
		var z := int(c[c.size() - 1])
		if z == 0:
			draws += 1                  # draws carry no win signal for a logistic; skipped
			continue
		var row: Array = []
		for i in range(3, 3 + N_FEAT):
			row.append(float(c[i]))
		xs.append(row)
		ys.append(1.0 if z > 0 else 0.0)
	f.close()
	var n := xs.size()
	print("[fit] %d rows (skipped %d draw rows, %d malformed)" % [n, draws, bad])
	if n < 500:
		print("[fit] ERROR: not enough data to fit -- need a harvest night.")
		quit(1)
		return

	# Standardize (the cfg stores mean/std so inference reproduces this exactly).
	var mean: Array = []
	var std: Array = []
	for j in N_FEAT:
		var m := 0.0
		for i in n:
			m += float(xs[i][j])
		m /= float(n)
		var v := 0.0
		for i in n:
			var d: float = float(xs[i][j]) - m
			v += d * d
		mean.append(m)
		std.append(sqrt(v / float(n)))
	for i in n:
		for j in N_FEAT:
			var sd: float = float(std[j])
			xs[i][j] = (float(xs[i][j]) - float(mean[j])) / (sd if sd > 0.0 else 1.0)

	# Full-batch logistic regression: w[0..27] features, w[28] bias.
	var w: Array = []
	for _j in N_FEAT + 1:
		w.append(0.0)
	for epoch in EPOCHS:
		var grad: Array = []
		for _j in N_FEAT + 1:
			grad.append(0.0)
		var loss := 0.0
		var correct := 0
		for i in n:
			var z2: float = float(w[N_FEAT])
			for j in N_FEAT:
				z2 += float(w[j]) * float(xs[i][j])
			var p := 1.0 / (1.0 + exp(-z2))
			var y: float = float(ys[i])
			loss += -(y * log(maxf(p, 1e-12)) + (1.0 - y) * log(maxf(1.0 - p, 1e-12)))
			if (p >= 0.5) == (y >= 0.5):
				correct += 1
			var err := p - y
			for j in N_FEAT:
				grad[j] = float(grad[j]) + err * float(xs[i][j])
			grad[N_FEAT] = float(grad[N_FEAT]) + err
		for j in N_FEAT + 1:
			w[j] = float(w[j]) - LR * float(grad[j]) / float(n)
		if (epoch + 1) % 50 == 0:
			print("[fit] epoch %d  log-loss %.4f  acc %.1f%%" % [epoch + 1, loss / float(n), 100.0 * float(correct) / float(n)])

	# Final quality + the story the weights tell (top influences, for sanity).
	var loss2 := 0.0
	var correct2 := 0
	for i in n:
		var z3: float = float(w[N_FEAT])
		for j in N_FEAT:
			z3 += float(w[j]) * float(xs[i][j])
		var p2 := 1.0 / (1.0 + exp(-z3))
		loss2 += -(float(ys[i]) * log(maxf(p2, 1e-12)) + (1.0 - float(ys[i])) * log(maxf(1.0 - p2, 1e-12)))
		if (p2 >= 0.5) == (float(ys[i]) >= 0.5):
			correct2 += 1
	var acc := 100.0 * float(correct2) / float(n)
	print("[fit] FINAL  log-loss %.4f  train accuracy %.1f%%  (coin flip = 50%%)" % [loss2 / float(n), acc])
	var ranked: Array = []
	for j in N_FEAT:
		ranked.append({"n": FEATURE_NAMES[j], "w": float(w[j])})
	ranked.sort_custom(func(a, b): return absf(float(a["w"])) > absf(float(b["w"])))
	print("[fit] strongest signals (standardized weights):")
	for k in mini(8, ranked.size()):
		print("      %-14s %+.3f" % [ranked[k]["n"], float(ranked[k]["w"])])

	var cf := ConfigFile.new()
	cf.set_value("value", "w", w)
	cf.set_value("value", "mean", mean)
	cf.set_value("value", "std", std)
	cf.set_value("value", "n", n)
	cf.set_value("value", "acc", acc)
	cf.set_value("value", "names", FEATURE_NAMES)
	cf.save(OUT)
	print("[fit] wrote %s -- next: run_value_arena.bat (value-ON vs value-OFF, 150 matches)." % OUT)
	quit(0)
