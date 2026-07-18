# PositionTests.gd -- the AI's regression suite. Scripted positions assert that the
# brain behaves sanely (its mixed strategy is sampled ~21 times per test, so the
# thresholds are frequencies, not certainties -- mixing SOME risk is correct play).
# Run headless:  godot --headless --script "res://Scripts/AI/Tuning/PositionTests.gd"
# Add a position every time a playtest finds a misplay: harvest the state with the
# replay's arrow keys, script it here, and no future change can regress it silently.
#
# 2026-07-17 RE-SITE: gates 1-4 still used coordinates from the old 12x12 board;
# on today's 8x8 (border walls at 0/7, interior 1..6) their fighters stood
# off-board or on walls -- e.g. the flee gate's kill line attacked a border-wall
# tile, so it could never connect and the gate passed vacuously. All fixtures now
# sit in the 1..6 interior with the same tactical shape (distances, facings,
# resources unchanged). First green run after this change re-baselines the suite.
extends SceneTree

const SAMPLES := 21
# Flip to true to run the suite on the EVOLVED weights (user://tuned_eval.cfg).
const USE_TUNED := false

var _fails := 0

func _init() -> void:
	if USE_TUNED:
		var cf := ConfigFile.new()
		if cf.load("user://tuned_eval.cfg") == OK:
			var w := {}
			for k in cf.get_section_keys("eval"):
				w[k] = cf.get_value("eval", k)
			Eval.set_weights(w)
			print("[positions] running on TUNED weights")
	print("[positions] booted -- running 6 tests (~126 AI decisions; a couple of minutes is normal)")
	_test_flee_not_wait()
	_test_hold_grenade()
	_test_safe_rest()
	_test_critical_rest()
	_test_press_starving()
	_test_no_lead_wait_under_aoe()
	print("[positions] %s" % ("ALL PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(0 if _fails == 0 else 1)

# Border-only arena so each test controls the terrain exactly.
func _blank_grid() -> Grid:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var g := Grid.new()
	g.generate(rng)
	for y in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			g.blocked[y][x] = (x == 0 or y == 0 or x == Grid.SIZE - 1 or y == Grid.SIZE - 1)
	g.base_blocked = g.blocked.duplicate(true)
	return g

func _mk(id: String, pos: Vector2i, facing: int, hp: int, energy: int) -> Combatant:
	var c := Combatant.new(id, pos, facing)
	c.equip(SelfPlayArena.kit())
	c.hp = hp
	c.energy = energy
	return c

func _check(name: String, rate: float, minimum: float, maximum: float = 1.0) -> void:
	var ok := rate >= minimum and rate <= maximum
	if not ok:
		_fails += 1
	print("[%s] %s  rate %.0f%% (want %.0f..%.0f%%)" % [
		"PASS" if ok else "FAIL", name, rate * 100.0, minimum * 100.0, maximum * 100.0])

# 1) Lethal threat, one escape: the brain must overwhelmingly survive, never idle
# into a kill ("the AI should never give up").
func _test_flee_not_wait() -> void:
	var g := _blank_grid()
	var atk := _mk("A", Vector2i(5, 4), Config.Facing.WEST, 100, 100)
	var run := _mk("B", Vector2i(3, 4), Config.Facing.WEST, 22, 60)
	var kill: Array = [{"id": "move", "tile": Vector2i(4, 4)}, {"id": "attack", "tile": Vector2i(3, 4)}]
	print("[positions] 1/3 flee-not-wait...")
	var alive := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(run, atk, g, run.spell_ids())
		var out := Resolver.resolve(g, atk, run, kill, seq, 1)
		if int(out["b"].hp) > 0:
			alive += 1
	_check("flee-not-wait: survives the kill line", float(alive) / SAMPLES, 0.7)

# 2) No purpose, no throw: at full health and range 5 the grenade should be held
# (its option value), not fished with.
func _test_hold_grenade() -> void:
	var g := _blank_grid()
	var me := _mk("B", Vector2i(6, 4), Config.Facing.WEST, 100, 100)
	var foe := _mk("A", Vector2i(1, 4), Config.Facing.EAST, 100, 100)
	print("[positions] 2/3 hold-grenade...")
	var thrown := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(me, foe, g, me.spell_ids())
		for act in seq:
			if String(act.get("id", "")) == "grenade":
				thrown += 1
				break
	_check("hold-grenade: no aimless throws", float(thrown) / SAMPLES, 0.0, 0.2)

# 3) Hurt and completely safe: resting should dominate.
func _test_safe_rest() -> void:
	var g := _blank_grid()
	var me := _mk("B", Vector2i(6, 6), Config.Facing.WEST, 40, 60)
	me.mp = 40
	var foe := _mk("A", Vector2i(1, 1), Config.Facing.EAST, 100, 10)
	print("[positions] 3/3 safe-rest...")
	var rested := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(me, foe, g, me.spell_ids())
		for act in seq:
			if String(act.get("id", "")) == "rest":
				rested += 1
				break
	_check("safe-rest: heals when unpunishable", float(rested) / SAMPLES, 0.5)

# 4) YOUR backstab scenario, generalized: one hit from death, foe ADJACENT but at
# zero energy (harmless this turn). Resting on the spot is legal, safe, and the
# survival play -- the brain must take it far more often than any stylish setup.
func _test_critical_rest() -> void:
	print("[positions] 4/4 critical-rest...")
	var g := _blank_grid()
	var me := _mk("B", Vector2i(5, 4), Config.Facing.EAST, 15, 60)
	me.mp = 60
	var foe := _mk("A", Vector2i(6, 4), Config.Facing.WEST, 100, 0)
	var rested := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(me, foe, g, me.spell_ids())
		for act in seq:
			if String(act.get("id", "")) == "rest":
				rested += 1
				break
	_check("critical-rest: heals at death's door vs a spent foe", float(rested) / SAMPLES, 0.6)


# 5) YOUR report: foe at 10 energy (one action from lockout), two tiles away, me
# healthy -- pressing is nearly free. Passivity here was the recurring complaint.
func _test_press_starving() -> void:
	print("[positions] 5/6 press-the-starving-man...")
	var g := _blank_grid()
	var me := _mk("B", Vector2i(4, 4), Config.Facing.WEST, 90, 80)
	var foe := _mk("A", Vector2i(2, 4), Config.Facing.EAST, 60, 10)
	var pressed := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(me, foe, g, me.spell_ids())
		for act in seq:
			var id := String(act.get("id", ""))
			if id == "attack" or id == "dark_bolt" or (id == "move" and Grid.dist(Vector2i(act.get("tile", me.pos)), foe.pos) < 2):
				pressed += 1
				break
	_check("press-starving: attacks or closes on a locked-out foe", float(pressed) / SAMPLES, 0.6)

# 6) YOUR report: foe can step in and AoE-burst; leading with WAIT eats it, while
# moving FIRST dodges -- action order is the whole test.
func _test_no_lead_wait_under_aoe() -> void:
	print("[positions] 6/6 no-lead-wait-under-aoe...")
	var g := _blank_grid()
	var me := _mk("B", Vector2i(5, 4), Config.Facing.WEST, 70, 60)
	var foe := _mk("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100)
	var safe := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(me, foe, g, me.spell_ids())
		if seq.size() > 0 and String(seq[0].get("id", "")) != "wait":
			safe += 1
	_check("no-lead-wait: acts before waiting under burst threat", float(safe) / SAMPLES, 0.7)
