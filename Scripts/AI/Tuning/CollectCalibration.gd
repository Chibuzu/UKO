# CollectCalibration.gd -- plays self-play matches, records (position score ->
# eventual winner) pairs, fits the logistic scale, saves user://calibration.cfg.
# v2: samples are LATE-GAME WEIGHTED when fitting (a turn-40 lead predicts the
# winner far better than a turn-3 one), and every tuple is appended to
# user://selfplay_data.csv -- the experience log the future learned value
# function trains on. From then on the brain judges in P(win) automatically. Rerun after big rule or
# weight changes; delete the cfg to disable calibration.
extends SceneTree
const MATCHES := 40

func _init() -> void:
	ExtremeAI.set_profile("challenging")
	var pairs: Array = []
	for m in range(MATCHES):
		var r := RandomNumberGenerator.new()
		r.seed = 1000 + m * 13
		var g := Grid.new()
		g.generate(r)
		var a := Combatant.new("A", g.spawn_a, Config.Facing.EAST)
		var b := Combatant.new("B", g.spawn_b, Config.Facing.WEST)
		a.equip(SelfPlayArena.kit())
		b.equip(SelfPlayArena.kit())
		var hist: Array = []
		var res := "ongoing"
		var turn := 0
		while turn < 50:
			turn += 1
			if turn > 1 and (turn - 1) % Config.MAP_ROTATE_EVERY == 0:
				var rr := g.rotate_blockers([a.pos, b.pos])
				a.pos = rr["positions"][0]
				b.pos = rr["positions"][1]
				for idx in rr["crushed_idx"]:
					var who: Combatant = a if int(idx) == 0 else b
					who.hp = maxi(1, who.hp - Config.MAP_CRUSH_DAMAGE)
					who.rest_ready = false
			hist.append(Eval._eval_situation(a, b, g))
			var sa := ExtremeAI.choose_sequence(a, b, g, a.spell_ids())
			var sb := ExtremeAI.choose_sequence(b, a, g, b.spell_ids())
			var out := Resolver.resolve(g, a, b, sa, sb, turn)
			a = out["a"]
			b = out["b"]
			res = String(out["result"])
			if res != "ongoing":
				break
		var a_won := 0.5
		if res == "a_wins":
			a_won = 1.0
		elif res == "b_wins":
			a_won = 0.0
		elif a.hp != b.hp:
			a_won = 1.0 if a.hp > b.hp else 0.0
		var fa := FileAccess.open("user://selfplay_data.csv", FileAccess.READ_WRITE if FileAccess.file_exists("user://selfplay_data.csv") else FileAccess.WRITE)
		if fa:
			fa.seek_end()
		for t in range(hist.size()):
			var w := 0.3 + 0.7 * float(t + 1) / float(hist.size())   # late positions weigh more
			pairs.append([float(hist[t]), a_won, w])
			if fa:
				fa.store_line("%f,%d,%d,%f" % [float(hist[t]), t + 1, hist.size(), a_won])
		if fa:
			fa.close()
		print("[cal] match %d/%d: %s (%d turns)" % [m + 1, MATCHES, res, turn])
	var best_a := 0.02
	var best_ll := 1.0e18
	var aa := 0.002
	while aa <= 0.2:
		var ll := _logloss(pairs, aa)
		if ll < best_ll:
			best_ll = ll
			best_a = aa
		aa *= 1.2
	var cf := ConfigFile.new()
	cf.set_value("cal", "a", best_a)
	cf.save("user://calibration.cfg")
	print("[cal] fitted A = %f (logloss %.4f, %d samples) -> saved. Brain now judges in P(win)." % [best_a, best_ll, pairs.size()])
	quit()

func _logloss(pairs: Array, a: float) -> float:
	var s := 0.0
	for p in pairs:
		var q: float = clampf(1.0 / (1.0 + exp(-a * float(p[0]))), 0.001, 0.999)
		var y: float = float(p[1])
		var w: float = float(p[2]) if p.size() > 2 else 1.0
		s += -w * (y * log(q) + (1.0 - y) * log(1.0 - q))
	return s / maxf(1.0, float(pairs.size()))
