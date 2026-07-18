# OvernightArena.gd -- OVERNIGHT SELF-PLAY. Two experiments in one run:
#   PHASE 1  "cs_d3 vs cs_d2"  : does DEPTH buy skill? (the whole point of the port)
#   PHASE 2  "cs_d2 vs gd"     : C# ExtremeAI vs the GDScript ExtremeAI (port check).
# Real gear (FULL_GEAR -- sidesteps the SelfPlayArena kit bug), seeded arenas, seat
# alternation, live rotation/zone clock. Appends running results to
# user://overnight_results.txt so partial progress survives an interruption.
extends SceneTree

const FULL_GEAR := ["discount_charm", "burst_node", "blink_boots", "dark_focus"]
const MATCHES_PER_PHASE := 150
const MAX_TURNS := 80          # cap -> draw (no zone stall runs forever)
const SEED_BASE := 990001
const OUT := "user://overnight_results.txt"

var bridge = null

func _init() -> void:
	bridge = load("res://Scripts/Port/CSharp/BrainBridge.cs").new()
	bridge.SetProfile("extreme")
	bridge.LoadCalibration()
	_log("==== OVERNIGHT RUN start %s | %d matches/phase, max %d turns ====" %
			[Time.get_datetime_string_from_system(), MATCHES_PER_PHASE, MAX_TURNS])
	_phase("cs_d3_vs_cs_d2", "cs3", "cs2")
	_phase("cs_d2_vs_gd", "cs2", "gd")
	_log("==== OVERNIGHT RUN done %s ====" % Time.get_datetime_string_from_system())
	quit(0)

func _phase(name: String, brain_x: String, brain_y: String) -> void:
	var wx := 0
	var wy := 0
	var dr := 0
	var margin := 0.0   # avg (x hp - y hp) at match end, a finer signal than W/L
	for mi in range(MATCHES_PER_PHASE):
		# Seat alternation: even matches X sits in seat A, odd in seat B.
		var x_is_a := (mi % 2 == 0)
		var r := _run_match(SEED_BASE + mi, brain_x if x_is_a else brain_y, brain_y if x_is_a else brain_x)
		var x_hp: int = r["a_hp"] if x_is_a else r["b_hp"]
		var y_hp: int = r["b_hp"] if x_is_a else r["a_hp"]
		margin += float(x_hp - y_hp)
		match r["result"]:
			"a_wins": if x_is_a: wx += 1
			else: wy += 1
			"b_wins": if x_is_a: wy += 1
			else: wx += 1
			_: dr += 1
		if (mi + 1) % 10 == 0:
			_log("[%s] %d/%d  %s %d - %d %s (draws %d)  avg-margin %+.1f" %
					[name, mi + 1, MATCHES_PER_PHASE, brain_x, wx, wy, brain_y, dr, margin / float(mi + 1)])
	_log("[%s] FINAL  %s %d - %d %s (draws %d)  winrate %.1f%%  avg-margin %+.1f" %
			[name, brain_x, wx, wy, brain_y, dr,
			100.0 * float(wx) / maxf(1.0, float(wx + wy)), margin / float(MATCHES_PER_PHASE)])

func _run_match(match_seed: int, brain_a: String, brain_b: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	var g := Grid.new()
	g.generate(rng)
	var a := Combatant.new("A", g.spawn_a, Config.Facing.EAST)
	a.equip(FULL_GEAR)
	var b := Combatant.new("B", g.spawn_b, Config.Facing.WEST)
	b.equip(FULL_GEAR)
	for turn in range(1, MAX_TURNS + 1):
		var sa := _choose(brain_a, a, b, g)
		var sb := _choose(brain_b, b, a, g)
		var out := Resolver.resolve(g, a, b, sa, sb, turn)
		a = out["a"]
		b = out["b"]
		if String(out["result"]) != "ongoing":
			return {"result": out["result"], "a_hp": a.hp, "b_hp": b.hp}
		# The live rotation/zone clock (mirrors GameController._rotate_map).
		if turn % Config.MAP_ROTATE_EVERY == 0:
			var res := g.rotate_blockers([a.pos, b.pos])
			a.pos = res["positions"][0]
			b.pos = res["positions"][1]
			for idx in res["crushed_idx"]:
				var who: Combatant = a if int(idx) == 0 else b
				who.hp = maxi(1, who.hp - Config.MAP_CRUSH_DAMAGE)
				who.rest_ready = false
	return {"result": "draw", "a_hp": a.hp, "b_hp": b.hp}

func _choose(brain: String, me: Combatant, foe: Combatant, g: Grid) -> Array:
	match brain:
		"cs3":
			bridge.SetDepth(3)
			return _bridge_choose(me, foe, g)
		"cs2":
			bridge.SetDepth(2)
			return _bridge_choose(me, foe, g)
		"gd":
			ExtremeAI.set_profile("extreme")   # the GDScript twin at the live EXTREME dials
			return ExtremeAI.choose_sequence(me, foe, g, me.spell_ids(), null)
	return [{"id": "wait"}]

func _bridge_choose(me: Combatant, foe: Combatant, g: Grid) -> Array:
	var seq: Array = Array(bridge.ChooseSequence(_rows(g.blocked), _rows(g.base_blocked),
			g.rot_step, g.shrink_level, _cd(me), _cd(foe), false))
	return seq if not seq.is_empty() else [{"id": "wait"}]

func _rows(blocked: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in range(Grid.SIZE):
		var line := ""
		for x in range(Grid.SIZE):
			line += "#" if blocked[y][x] else "."
		rows.append(line)
	return rows

func _cd(c: Combatant) -> Dictionary:
	return c.to_bridge_dict()   # the ONE marshal contract lives on Combatant

func _log(s: String) -> void:
	print(s)
	var f := FileAccess.open(OUT, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(s)
		f.close()
