# ValidateChampion.gd -- run AFTER a tuner session.
# Gauntlets the evolved champion (user://tuned_eval.cfg) against the ORIGINAL hand
# defaults on FRESH seeds it never trained on: the overfit / intransitivity gate.
# Adopt only if it wins here AND PositionTests stay green (flip USE_TUNED there).
extends SceneTree
const SEEDS := [101, 202, 303, 404, 505]

func _init() -> void:
	ExtremeAI.set_profile("challenging")
	var defaults := Eval.get_weights()
	var cf := ConfigFile.new()
	if cf.load("user://tuned_eval.cfg") != OK:
		print("[validate] no tuned_eval.cfg found -- run the tuner first")
		quit(1)
		return
	var champ := {}
	for k in cf.get_section_keys("eval"):
		champ[k] = cf.get_value("eval", k)
	print("[validate] champion vs hand defaults on fresh seeds ", SEEDS)
	var score := 0.0
	var games := 0
	for sd in SEEDS:
		for w1a in [true, false]:
			var r := SelfPlayArena.play_match(champ, defaults, int(sd), w1a)
			games += 1
			score += 0.5 + clampf(float(r["hp_margin"]) / 200.0, -0.5, 0.5)
			print("  seed %d as %s: %s (margin %d, %d turns)" % [sd, "A" if w1a else "B", r["result"], r["hp_margin"], r["turns"]])
	var share := score / float(games)
	var verdict := "ADOPT (if PositionTests also pass with USE_TUNED)" if share >= 0.55 else ("KEEP DEFAULTS" if share < 0.50 else "MARGINAL -- evolve further before adopting")
	print("[validate] champion share vs defaults: %.0f%%  ->  %s" % [share * 100.0, verdict])
	quit()
