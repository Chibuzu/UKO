# Tuner.gd -- self-play weight tuning (Texel-style perturbation hill-climb).
# Run headless from the project folder:
#   godot --headless --script "res://Scripts/AI/Tuning/Tuner.gd"
# Each iteration perturbs every tunable Eval weight by +/-STEP, plays the candidate
# against the current best over the seed suite (both seats), and adopts it only if
# it clearly wins. Accepted weights are saved to user://tuned_eval.cfg and printed
# as a paste-ready dictionary at the end. Start with ITERS 5 as a smoke test; raise
# it for an overnight run.
extends SceneTree

const ITERS := 150
const STEP := 0.12   # finer mutations for refinement runs
const SEEDS := [11, 23, 37, 51, 68, 84, 97]
const ACCEPT := 0.55      # candidate must take this score share to replace the base
const SAVE_PATH := "user://tuned_eval.cfg"

func _init() -> void:
	# Tune under the CHALLENGING throttle: Eval weights are shared across profiles,
	ExtremeAI.set_profile("challenging")   # so this just makes every match ~3x faster.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base := Eval.get_weights()
	# Resume evolution from the saved champion when one exists -- successive runs
	# CONTINUE the climb instead of restarting from the hand defaults every night.
	var prev := ConfigFile.new()
	if prev.load(SAVE_PATH) == OK:
		for k in prev.get_section_keys("eval"):
			base[k] = prev.get_value("eval", k)
		print("[tuner] resuming from saved champion")
	print("[tuner] booted")
	print("[tuner] start; %d iters, %d seeds, step %.2f" % [ITERS, SEEDS.size(), STEP])
	for it in range(ITERS):
		var cand := {}
		for k in Eval.TUNABLE:
			var s := 1.0 + STEP * (1.0 if rng.randf() < 0.5 else -1.0)
			cand[k] = float(base[k]) * s
		cand["DISCOUNT"] = clampf(float(cand["DISCOUNT"]), 0.5, 0.99)
		var score := 0.0
		var games := 0
		for seed_value in SEEDS:
			for w1a in [true, false]:
				var r := SelfPlayArena.play_match(cand, base, int(seed_value), w1a)
				games += 1
				# Margin-based scoring: pure win/loss is dominated by map seat
				# advantage (each seed's layout favors one spawn -> constant 50%).
				# HP margin registers "wins bigger / loses slower", the real signal.
				score += 0.5 + clampf(float(r["hp_margin"]) / 200.0, -0.5, 0.5)
		var share := score / float(games)
		if share >= ACCEPT:
			base = cand
			_save(base)
			print("[tuner] iter %d: ACCEPTED (%.0f%%)" % [it + 1, share * 100.0])
		else:
			print("[tuner] iter %d: kept base (cand %.0f%%)" % [it + 1, share * 100.0])
	Eval.set_weights(base)
	print("[tuner] done. Best weights (paste into Eval defaults or load the cfg):")
	print(base)
	quit()

func _save(w: Dictionary) -> void:
	var cf := ConfigFile.new()
	for k in w:
		cf.set_value("eval", String(k), w[k])
	cf.save(SAVE_PATH)
