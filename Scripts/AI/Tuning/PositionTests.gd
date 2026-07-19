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
# Flip to true to run the suite with the LEARNED VALUE JUDGE armed (reads
# user://value_fn.cfg). This is the ADOPTION GATE: after an ADOPT verdict from
# run_value_arena.bat, the judge must keep ALL SIX behavior gates green here
# before it is flipped on for live EXTREME. Flip back to false afterwards.
const USE_VALUE := false

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
	if USE_VALUE:
		if Eval.load_value_fn():
			Eval.VALUE_ON = true
			print("[positions] running with the LEARNED VALUE JUDGE (value_fn.cfg)")
		else:
			print("[positions] USE_VALUE set but user://value_fn.cfg missing/invalid -- hand eval")
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

# 4) YOUR backstab scenario, generalized: one hit from death, foe ADJACENT and
# TRULY disarmed -- 0 energy (even wait->swing needs 20), 0 mp (burst/bolt are
# MP-powered), grenade SPENT (the once-per-match item costs neither resource!).
# Every earlier version of this gate secretly left the foe a weapon, and the
# brain rightly refused to rest into it; the premise finally matches the name.
# WHAT WE ASSERT (evolved in round 9b): demanding literally "rest" turned out to
# under-specify survival. Resting IN PLACE lets the foe wait->swing next turn
# and take the heal straight back; the brain's line -- chip damage, then step
# where 20 energy can't reach, rest SAFELY next turn -- is strictly better play.
# So the gate now asserts the SPIRIT: after the chosen turn the fighter must be
# alive and OUT of the foe's next-turn one-shot range (worst incoming < hp).
# The old stand-and-bang death line fails this; any true survival play passes.
func _test_critical_rest() -> void:
	print("[positions] 4/4 critical-survival...")
	var g := _blank_grid()
	var me := _mk("B", Vector2i(5, 4), Config.Facing.EAST, 15, 60)
	me.mp = 60
	var foe := _mk("A", Vector2i(6, 4), Config.Facing.WEST, 100, 0)
	foe.mp = 0
	foe.spent_once["grenade"] = true
	var safe := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(me, foe, g, me.spell_ids())
		var out := Resolver.resolve(g, foe, me, [{"id": "wait"}, {"id": "wait"}], seq, 1)
		var me2: Combatant = out["b"]
		var foe2: Combatant = out["a"]
		if me2.hp > 0 and me2.hp > ThreatModel.worst_damage(foe2, me2, g):
			safe += 1
	_check("critical-survival: exits one-shot range at death's door", float(safe) / SAMPLES, 0.6)


# 5) YOUR report: foe at 10 energy (one action from lockout), two tiles away, me
# healthy -- pressing is nearly free. Passivity here was the recurring complaint.
# PREMISE (round 9b): mp = 0 too. Since the kit fix the foe holds real spells,
# and DARK BOLT costs 0 energy -- at default full mp the "locked-out" foe was
# actually two bolts from ending me, and the brain's hedge was correct play.
# "Locked out" now means locked out. PRESSING (round 9b): blink onto an adjacent
# tile and aoe_burst count too -- the brain's favourite line here is blink-in ->
# burst, which the old predicate (attack/bolt/move only) scored as passivity.
func _test_press_starving() -> void:
	print("[positions] 5/6 press-the-starving-man...")
	var g := _blank_grid()
	var me := _mk("B", Vector2i(4, 4), Config.Facing.WEST, 90, 80)
	var foe := _mk("A", Vector2i(2, 4), Config.Facing.EAST, 60, 10)
	foe.mp = 0
	var pressed := 0
	for _i in range(SAMPLES):
		var seq := ExtremeAI.choose_sequence(me, foe, g, me.spell_ids())
		for act in seq:
			var id := String(act.get("id", ""))
			var closes: bool = act.has("tile") and Grid.dist(Vector2i(act.get("tile", me.pos)), foe.pos) < 2
			if id == "attack" or id == "dark_bolt" or id == "aoe_burst" \
					or ((id == "move" or id == "blink_step") and closes):
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
